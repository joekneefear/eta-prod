````markdown
# KRI_FOX_XP WLBI — Documentation

> **Last Updated:** 2026-03-19  
> **Author:** jgarcia  
> **Python Version:** 3.12

---

## Overview

This mini-pipeline ingests WLBI (wafer-level build information) CSV files, enriches them with WS (web service / refdb) metadata, fills missing values with `NA`, and writes an Internal Flat File (IFF) styled output (CSV/IFF) using the shared `Writer`/`IFF` helpers.

There are three cooperating modules documented here:

| Component | Entry Point / Class | Purpose |
|-----------|---------------------|---------|
| CLI Driver | `pp_bk_sic_wlbi_analog.py` | Process input WLBI CSV, fetch lot metadata, enrich and write IFF output |
| Parser | `SiCWlbiParser` | Extract lot id from WLBI CSV and attempt WS metadata retrieval (with fallback/modifications) |
| Enricher | `SiCWlbiEnricher` | Parse WLBI CSV into logical "sets", append probe/load/facility/srcLot values, fill blanks with `NA`, and produce `Model` containing `misc` DataFrames |

```
WLBI CSV  -->  SiCWlbiParser.get_lotid_from_wlbi_csv()  -->  Refdb API lookup
                                              |                              
                                              v                              
                               SiCWlbiEnricher.enrich_wlbi_srcLot_probe_card_load_board_fill_na()
                                              |
                                              v
                                         IFF + Writer (gzipIFF)
```

---

## Core Scripts

### 1. Entry Point — `pp_bk_sic_wlbi_analog.py`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/pp_bk_sic_wlbi_analog.py` |
| **Purpose** | CLI wrapper: validate CLI args, configure logging, resolve WS URLs, fetch lot metadata, enrich WLBI sets, and write IFF output |
| **Created / Author** | 2024 - jgarcia |

**CLI / Expected Parameters (provided via `Util.process_command_line_args`)**

| Param | Required | Description |
|-------|----------|-------------|
| `--infile` | ✅ | Input WLBI CSV file |
| `--out` | ✅ | Output directory (outbox) |
| `--site` | ✅ | Site code (used when enriching) |
| `--ws_url` | ✅ | YAML config path with WS endpoints |
| `--ws_source` | ✅ | WS source key used to pick URLs from YAML |
| `--logfile` | ❌ | Log file path (overrides DPLOG-based default) |

Notes:
- The script validates that `--infile` is a CSV by calling `Util.is_csv_file()` and exits non-zero on failure.
- Logging initialization uses the `DPLOG` environment variable as default and accepts CLI overrides (`--logfile`, `--log_file`, `--log`).
- The script instantiates `RefdbAPIClient()` and invokes the parser/enricher pipeline. If metadata appears missing or contains an error, it marks the `Writer.noMeta = True` so downstream output reflects the missing metadata.

**Output behavior**
- The `Writer` is instantiated with `gzipIFF=True` and `basename` derived from the input filename (spaces replaced with `_`).
- The script constructs an `IFF` using the `Writer` and `Model` returned by the enricher and calls `iff_instance.save_dataframe_to_csv()` to persist output.

---

### 2. Parser — `SiCWlbiParser`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/lib/Parser/SiCWlbiParser.py` |
| **Class** | `SiCWlbiParser` |
| **Purpose** | Read WLBI CSV to obtain `strLotName` (lot id) and perform metadata retrieval attempts against configured WS endpoints |

Key behavior and error handling:

- `get_lotid_from_wlbi_csv()` opens the CSV and scans rows for a header starting with `strLotName` and returns the second column as lot id. File-not-found and generic exceptions are logged and cause `Util.dp_exit(1, ...)`.
- `get_metadata_by_lot(lot, api_client, url)` encapsulates WS lookups:
  - It first attempts the original lot ID: `GET {url}/{lot}` via `api_client.get_metadata()`.
  - If the result contains an error or missing status, it tries a set of heuristic modifications for lots with special prefixes:
    - `M0...` → replace third character with `0` (if length == 10)
    - `KG...` / `KH...` → try the first 8 characters
    - `MKG...` / `MKH...` → try dropping leading `M` and variations truncated to 8 chars
  - Each modified candidate is tried in turn; the call count and attempted modified lot ids are logged.
  - On exceptions from the API client, errors are logged and the method returns `None` (caller reacts accordingly).

This logic enables the driver script to retry using alternate WS endpoints (e.g., `on_lot` then `pp_lot`) and to attempt modified lot ID variants before giving up.

---

### 3. Enricher — `SiCWlbiEnricher`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/lib/Enricher/SiCWlbiEnricher.py` |
| **Class** | `SiCWlbiEnricher` |
| **Purpose** | Parse WLBI CSV into logical sets, append `strProbeCard`/`strLoadBoard`/`strFacility`/`strSrcLot`, fill blanks with `NA`, and return a `Model` with `misc` DataFrames |

Important methods:

- `fill_empty_with_na(df)` — replaces empty strings and NaN with `NA` (regex and `fillna`).
- `append_str_src_lot(current_set, strSrcLot)` — when `strLotName` is encountered, append a `strSrcLot` row if available.
- `append_probe_and_load_values(current_set, strWaferID_line)` — reads `strWaferID` content split by `/` to populate `strProbeCard` and `strLoadBoard`. If missing, uses the configured `fill_with` value (default `'NA'`).
- `read_wblbi_data_and_enrich_first_set(csv_file_path)` — the core parser:
  - Reads the input CSV as raw rows and groups rows into logical "sets" separated by empty rows.
  - For the first set, after collecting rows it ensures `strProbeCard`, `strLoadBoard`, and `strFacility` are appended once.
  - `strSrcLot` is added when `strLotName` is present; `strWaferID` is captured for probe/load parsing.
  - Returns a list of sets, each a list-of-lists (rows).
- `enrich_wlbi_srcLot_probe_card_load_board_fill_na(wlbi_file)` — builds a `Model`, transforms each set into a pandas `DataFrame` (first row treated as header), pads headers to match the longest row, ensures at least one data row, calls `fill_empty_with_na()`, and appends each DataFrame to `model.misc`.

Error handling:
- File I/O errors and unexpected exceptions are logged and cause `Util.dp_exit(1, ...)` (consistent with the project’s exit conventions).

---

## Processing Flow (concise)

1. `pp_bk_sic_wlbi_analog.py` parses CLI args and configures logging.
2. `SiCWlbiParser.get_lotid_from_wlbi_csv()` extracts the lot id from the WLBI CSV.
3. The driver tries `on_lot` WS URL, then falls back to `pp_lot` if metadata indicates an error/missing data.
4. `SiCWlbiEnricher` reads WLBI sets, appends probe/load/facility/srcLot, and returns a `Model` containing `pandas.DataFrame` objects in `model.misc`.
5. An `IFF` instance is constructed with the `Writer` and `Model`, and `save_dataframe_to_csv()` persists the result (gzip enabled).

---

## Recent Changes / Notes

- 2024 — Initial implementation and refactor to the current Refdb API client usage.
- Parser and enricher focus on resilience: multiple WS attempts, lot-ID heuristics, and robust NA-filling for downstream systems that expect explicit `NA` markers.
- Writer is invoked with `gzipIFF=True` by default in the CLI driver.

---

## Directory Structure (relevant files)

```
scripts/py/
├── pp_bk_sic_wlbi_analog.py            # CLI entry point for WLBI enrichment
├── docs/
│   └── KRI_FOX_XP_WLBI/
│       └── claude.md                   # This documentation file
└── lib/
    ├── Parser/
    │   └── SiCWlbiParser.py           # Lot extraction + WS retrieval heuristics
    └── Enricher/
        └── SiCWlbiEnricher.py         # Set grouping, probe/load/facility/srcLot appends, NA fill
```

````
