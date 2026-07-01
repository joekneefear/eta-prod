# Klarf 1.8 Enrichment Pipeline — Documentation

> **Last Updated:** 2026-03-17  
> **Author:** jgarcia  
> **Python Version:** 3.12

---

## Overview

The **Klarf 1.8 Enrichment Pipeline** reads KLA Reference Files (Klarf v1.8), parses their hierarchical metadata (Lot → Wafer → Defect), enriches the content with a `<Metadata>` XML header, and writes the enriched output to site-specific directories. The pipeline supports multi-site YAML-driven configuration, optional ERT Reference DB API lookups, and database logging via `PPLogger`.

```
┌──────────────┐    ┌──────────────┐    ┌───────────────────┐    ┌──────────┐
│  Klarf 1.8   │───▶│  Klarf18     │───▶│  Klarf18Enricher  │───▶│  Writer  │
│  Input File  │    │  Parser      │    │  (YAML-driven)    │    │  Output  │
└──────────────┘    └──────────────┘    └───────────────────┘    └──────────┘
                                               │
                                    ┌──────────┴──────────┐
                                    │  RefdbAPIClient     │
                                    │  (Optional ERT WS)  │
                                    └─────────────────────┘
```

---

## Core Scripts & Libraries

### 1. Entry Point — `klarf_18_enricher.py`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/klarf_18_enricher.py` |
| **Purpose** | CLI entry point that orchestrates the full pipeline |
| **Author** | jgarcia |
| **Created** | 2026-Feb-16 |

**CLI Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `--infile` | ✅ | Input Klarf 1.8 file (supports `.gz`) |
| `--out` | ✅ | Output directory |
| `--config` | ❌ | Path to YAML config (default: `resources/Klarf18_Enrichment.yaml`) |
| `--site` | ❌ | Force site override (auto-detected from `FabID` if omitted) |
| `--forced_final_folder` | ❌ | Set to `SBX` to force SANDBOX output |
| `--force_prd` | ❌ | Exception override: allow PRODUCTION routing even when metadata is missing |
| `--ws_url` | ❌ | YAML config for ERT Reference DB web service URLs |
| `--ws_source` | ❌ | Source key for ERT WS URL resolution |
| `--pplog` | ❌ | Enable PPLogger database persistence |
| `--logfile` / `--log_file` / `--log` | ❌ | Override log file path (default: `$DPLOG/<script_name>.log`) |

**Processing Flow:**

1. Initialize logging (`Log`) and `PPLogger`
2. Load YAML configuration
3. Read original Klarf file content (supports gzip)
4. Parse metadata via `Klarf18` parser
5. Optionally fetch ERT Reference DB lot metadata via `RefdbAPIClient`
6. Auto-detect site from `FabID` in metadata (or use `--site`)
7. Enrich content via `Klarf18Enricher` (prepends `<Metadata>` XML)
8. Evaluate routing flags for `Writer`:
    - `forced_sandbox=True` when `--forced_final_folder SBX`
    - `noMeta=True` when selected mapping uses `refdb` fields and `on_lot` response `status` is `NO_DATA`, `ERROR`, `NULL`, empty, or missing
    - Exception: if `--force_prd` is set, keep `noMeta=False` and allow PRODUCTION routing
9. Write enriched output via `Writer` (atomic temp-file + rename)
9. Exit with `PPLogger` persistence

---

### 2. Parser — `lib/Parser/Klarf18.py`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/lib/Parser/Klarf18.py` |
| **Class** | `Klarf18` |
| **Purpose** | Hierarchical (stack-based) parser for Klarf 1.8 format |
| **Created** | 2026-Feb-16 |

**Key Design:**

- Uses a **token-based** approach with regex tokenization: `Record`, `Field`, `List`, braces, semicolons, quoted strings
- **Stack-based context** tracks nesting: `Record → { nested Records/Fields } → }`
- Returns a **nested dictionary** preserving the Klarf hierarchy (`Lot → Wafer → Defect`)
- Internal keys prefixed with `_` (e.g., `_val`, `_type`, `_records`)
- Supports both `.gz` and plain-text input files
- Strips `/* ... */` comments before parsing

**Output Structure:**

```python
{
    "LotRecord": {"_val": "LOT123", "_type": "LotRecord", ...},
    "WaferRecord": {"_val": "W_01", "_type": "WaferRecord", ...},
    "FabID": ["CZ2"],
    "DeviceID": ["PROD_A"],
    "StepID": ["STEP1"],
    ...
}
```

---

### 3. Enricher — `lib/Enricher/Klarf18Enricher.py`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/lib/Enricher/Klarf18Enricher.py` |
| **Class** | `Klarf18Enricher` |
| **Purpose** | Generates `<Metadata>` XML from parsed data + YAML rules |
| **Created** | 2026-Feb-16 |

**Constructor Parameters:**

| Parameter | Description |
|-----------|-------------|
| `metadata` | Parsed dictionary from `Klarf18.parse()` |
| `original_content` | Raw file content to prepend metadata to |
| `config` | Loaded YAML configuration dictionary |
| `site` | Site key (e.g., `CZ2_KLARF_18_Si`, `DEFAULT`) |
| `lot_metadata` | Optional dict from ERT Reference DB API |

**Rule Resolution Types** (from YAML):

| Type | Description |
|------|-------------|
| `constant` | Static value, meta_source = `SCRIPT_CONSTANT` |
| `record` | Lookup from a `Record` block in parsed metadata |
| `field` | Lookup from a `Field` block, supports `index`, `slice`, `format`, `regex_replace` |
| `refdb` | Lookup from ERT Reference DB lot metadata, meta_source = `ERT_REFDB` |
| `composite` | Template-based combination of multiple sub-rules via `{part_name}` |
| `wafer_record` | Specialized WaferId resolver for runtime `WaferRecord` interpretation. Supports scribe detection, numeric wafer extraction, RefDB `sourceLot` preference, and file `LotRecord` fallback based on YAML options. |

**Fallback Support:** Any rule can define a `fallback` sub-rule that triggers if the primary value resolves to `NA` or empty.

**Source Tagging:** Values altered by `slice`, `regex_replace`, or `format` are tagged as `Klarf_1.8_CORRECTION` instead of `KLARF_1.8`.

### `wafer_record` Rule Details

The `wafer_record` rule type was added to support business-rule-driven `WaferId` construction without hardcoding site-specific logic into the main mapping structure.

**Supported YAML options:**

| Key | Description |
|-----|-------------|
| `source` | Metadata key containing the Klarf wafer value, typically `WaferRecord` |
| `construction_mode` | Controls how the resolver behaves. Current modes: `auto` and `source_lot_wafer_number` |
| `source_lot_refdb_source` | RefDB/on_lot key to use first for source lot lookup, e.g. `sourceLot` |
| `source_lot_source` | File metadata fallback key, typically `LotRecord` |
| `scribe_regex` | Regex used to detect scribe-style wafer values |
| `scribe_replacement` | Replacement pattern for direct scribe-based `WaferId` construction |
| `scribe_wafer_group` | Regex capture-group index containing the wafer number when extracting from scribe text |

**Mode behavior:**

- `auto`
    - If `WaferRecord` matches `scribe_regex`, construct directly from the scribe replacement.
    - Else if `WaferRecord` is numeric, construct `sourceLot_waferNumber` using RefDB source lot first when configured, then `LotRecord` fallback.
    - Else return the raw `WaferRecord` value.

- `source_lot_wafer_number`
    - If `WaferRecord` matches `scribe_regex`, construct directly from the scribe replacement even if RefDB is empty or the on_lot call failed.
    - Else if `WaferRecord` is numeric, construct `sourceLot_waferNumber` using RefDB/on_lot `sourceLot` first, then file `LotRecord` fallback.
    - Else return `NA` and log a warning.

**Normalization rules:**

- Source lot values have trailing `.S` removed before constructing `WaferId`.
- Numeric wafer values are zero-padded to 2 digits (`4` → `04`).
- Scribe example: `KG58Z02X-18 E7` → `KG58Z02X_18`
- Numeric example with RefDB source lot: `sourceLot=KG61Z2AX`, `WaferRecord=4` → `KG61Z2AX_04`
- Numeric example with RefDB unavailable: `LotRecord=KG61Z2AX.S`, `WaferRecord=4` → `KG61Z2AX_04`

**Output:** Returns `<Metadata>` XML string + `\n` + original file content.

---

### 4. Configuration — `resources/Klarf18_Enrichment.yaml`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/resources/Klarf18_Enrichment.yaml` |
| **Purpose** | Multi-site field mapping rules for enrichment |

**Configured Sites:**

| Site Key | `match_fab` Pattern | `env` Value | Notes |
|----------|---------------------|-------------|-------|
| `CZ2_KLARF_18_Si` | `CZ2` | `CZ2_Defect` | Silicon process rules, composite WaferId |
| `DEFAULT` | *(fallback)* | `klarf_18_enricher` | Pass-through direct mappings |
| `JND` | `JND` | `jnd_defect` | Aizu2 FAB (PTI) |
| `BK_SICA88_Rework` | *(explicit site selection / config key use)* | `kri_klarf_18_epi_rework` | ERT RefDB priority with specialized `WaferId` runtime logic |

**Site matching** is done by checking if any `match_fab` pattern is a substring of the extracted `FabID` (case-insensitive).

### `BK_SICA88_Rework` `WaferId` Behavior

`BK_SICA88_Rework` now uses a dedicated `wafer_record` rule instead of a plain `record` or simple regex replacement.

Current YAML behavior:

```yaml
WaferId:
    type: wafer_record
    source: WaferRecord
    construction_mode: source_lot_wafer_number
    source_lot_refdb_source: sourceLot
    source_lot_source: LotRecord
    scribe_regex: "^([A-Z0-9]+)-(\\d{2})\\s[A-Z0-9]{2}$"
    scribe_wafer_group: 2
    scribe_replacement: "\\1_\\2"
    target: WAFER_ID
```

Resolution order for `BK_SICA88_Rework`:

1. Read `WaferRecord` from the Klarf file.
2. If it matches the configured scribe regex, build `WaferId` directly from the scribe replacement.
3. Otherwise, if it is numeric, build `WaferId` as `<source lot>_<zero-padded wafer number>`.
4. Source lot lookup order for numeric values:
     1. RefDB/on_lot `sourceLot`
     2. file `LotRecord`
5. If neither RefDB source lot nor `LotRecord` is available for a numeric value, `WaferId` resolves to `NA` and a warning is logged.

This design ensures the following business behavior:

- **Scribe match wins**, regardless of whether on_lot returned metadata.
- **Numeric wafer values prefer RefDB source lot** when on_lot succeeds.
- **Numeric wafer values fall back to `LotRecord`** when on_lot returns `NO_DATA`, `ERROR`, `NULL`, an empty payload, or the lot is not found.
- The existing SANDBOX routing behavior remains controlled by `writer.noMeta=True` whenever the selected mapping depends on `refdb` fields and the on_lot call is considered no-data/error.

---

### 5. Writer — `lib/Writer.py`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/lib/Writer.py` |
| **Class** | `Writer` |
| **Purpose** | Atomic file output with temp-file + rename pattern |
| **Created** | 2023-Sep-06 |

**Key Features:**

- **Atomic writes:** Writes to `.tmp` file first, then `os.rename()` to final path
- **Output routing:** Files go to `PRODUCTION/`, `SANDBOX/`, or `QDE/` subdirectories based on metadata flags (`noMeta`, `wmapIsEmpty`, `forced_sandbox`, `qde`)
- **Klarf 1.8 no-metadata policy:** For mappings that depend on `refdb` fields (for example, `BK_SICA88_Rework`), the script sets `writer.noMeta=True` when `on_lot` response `status` is `NO_DATA`, `ERROR`, `NULL`, empty, or missing, which routes output to `SANDBOX` for safe review.
- **Business-rule exception:** `--force_prd` overrides the no-metadata SANDBOX default and allows PRODUCTION routing for approved exception scenarios.
- **Gzip compression:** Optional via `gzipIFF` flag, also uses temp files for atomic compression
- **Fork support:** Copies output to a secondary `forkdir` with both plain and `.gz` versions
- **Timestamp in filename:** Configurable via `use_timestamp_in_filename` (default `True`), with optional site/script-level skip lists
- **PPLogger integration:** Automatically sets output directory on the logger

**API:**

```python
writer = Writer(outdir=out_dir, basename=fname, ext=fext, gzipIFF=True, pplogger=pplogger)
writer.open()       # Creates .tmp file
writer.put(data)    # Writes data (supports str and pd.DataFrame)
writer.close()      # Renames .tmp → final, optionally compresses and forks
writer.cancel()     # Removes temp/output file on error
```

---

### 6. Formatter — `lib/Formatter/IFF.py`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/lib/Formatter/IFF.py` |
| **Class** | `IFF` (extends `Base`) |
| **Purpose** | Internal Flat File formatter for wafer-level data |
| **Created** | 2023-Oct-12 |

**Key Methods:**

| Method | Description |
|--------|-------------|
| `print_par()` | Writes PAR data grouped by `START_TIME`, combining wafer numbers |
| `print_par_per_wafer_number()` | Writes PAR data with one file per wafer |
| `write_dict_line_list()` | Writes dictionary route data to files |
| `write_jnd_lot_metadata()` | Writes sorted, deduplicated JND lot metadata |
| `write_dict_to_file(version)` | Writes Klarf v1.2 format data |
| `save_dataframe_to_csv()` | Saves pandas DataFrames to CSV with atomic temp-file pattern |
| `print_limit()` | Writes limit data with optional condition sections |
| `build_outfilename()` | Appends wafer number(s) to filename before extension |

**File Structure Written (PAR):**

```xml
<HEADER>key=value pairs</HEADER>
<WMAP>wafer map data</WMAP>
<PAR>test records (CSV)</PAR>
<WAFER>WAFER_ID=..., WAFER_NUMBER=...</WAFER>
<BIN>/<SBIN>/<HBIN> bin data
<DATA>die data with attributes</DATA>
<STAT>statistics (if min values present)</STAT>
```

---

### 7. Formatter — `lib/Formatter/SXML.py`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/lib/Formatter/SXML.py` |
| **Class** | `SXML` |
| **Purpose** | SXML (Structured XML) writer |
| **Created** | 2023-Sep-06 |

**Key Methods:**

| Method | Description |
|--------|-------------|
| `write_xml_to_file()` | Writes SXML string to file using atomic temp + rename. Supports fork and gzip. Uses `ISO-8859-1` encoding. |
| `write_list_of_line_string_to_file()` | Writes a list of line strings using `Writer.open()/put()/close()` |

---

## Supporting Libraries

| Library | Path | Purpose |
|---------|------|---------|
| `Log` | `lib/Log.py` | Centralized logger with `INFO`, `WARN`, `ERROR`, `DEBUG` methods. Dual output to file (RotatingFileHandler, 10MB max) and console. Integrates with `PPLogger` for selective DB persistence. |
| `PPLogger` | `lib/PPLogger.py` | Database logger for `refdb.pp_log`. Tracks lot, script, environment, error codes. Supports Oracle DB via SQLAlchemy. Smart message filtering (only persists errors, warnings, and key operational events). |
| `MetadataDTO` | `lib/Data/MetadataDTO.py` | Data Transfer Object with 60+ metadata constants. Generates ordered `<Metadata>` XML with `<Attribute>` elements containing `Name`, `Source`, and `Value`. |
| `MetadataDTOAttribute` | `lib/Data/MetadataDTOAttribute.py` | Individual metadata attribute container with `name`, `source`, `value` properties. |
| `Util` | `lib/Util.py` | Utility functions: CLI arg parsing (`process_command_line_args`), `dp_exit`, `rep_na`, `get_logging_time`, `is_gzipped`, YAML loading. |
| `RefdbAPIClient` | `lib/WS/RefdbAPIClient.py` | REST API client for ERT Reference DB lookups (lot metadata by lot ID). |
| `Base` | `lib/Data/Base.py` | Base class for data objects, provides attribute initialization. |

---

## Recent Changes

### 2026-Mar-17 — `BK_SICA88_Rework` WaferId Runtime Refactor

> Conversation: *Klarf 1.8 WaferRecord handling for BK rework files*

- **`Klarf18Enricher.py`:** Added `wafer_record` rule type for runtime interpretation of `WaferRecord` values.
- **YAML-driven regex support:** Scribe detection and transformation are now configurable by YAML (`scribe_regex`, `scribe_replacement`, `scribe_wafer_group`) instead of being hardcoded in one fixed branch.
- **BK-only behavior:** Limited the new specialized `WaferId` logic to `BK_SICA88_Rework`; other sites (`CZ2_KLARF_18_Si`, `DEFAULT`) retain their previous behavior.
- **RefDB-first source lot lookup:** For BK numeric wafer values, `WaferId` construction uses on_lot `sourceLot` first and falls back to file `LotRecord` when RefDB data is unavailable.
- **Scribe precedence:** For BK scribe-matching wafer values, `WaferId` is constructed directly from the scribe pattern even when the on_lot endpoint returns no data or errors.
- **Fallback routing alignment:** This behavior is consistent with existing SANDBOX routing when the site uses `refdb` mappings and the on_lot status is no-data/error.

### 2026-Mar-11 — Atomic File Write Hardening

> Conversation: *Securing File Writes*

- **`Writer.py`:** Ensured all file writes use atomic temp-file + `os.rename()` pattern. Both compressed (`.gz`) and uncompressed files are handled atomically to prevent downstream processes from accessing incomplete files.
- **`IFF.py` (`save_dataframe_to_csv`):** Refactored to use the same atomic temporary file strategy as `Writer.py`. Temp file is cleaned up on error.
- **`SXML.py` (`write_xml_to_file`):** Refactored to use atomic temp + rename. Temp file cleanup on error.

### 2026-Feb-16 — Klarf 1.8 Enrichment Pipeline (Initial)

- **`klarf_18_enricher.py`:** New entry-point script for Klarf 1.8 enrichment.
- **`Klarf18.py`:** New stack-based hierarchical parser for Klarf 1.8 format.
- **`Klarf18Enricher.py`:** New site-aware enricher with YAML-driven field mapping, ERT RefDB integration, composite rules, and fallback support.
- **`Klarf18_Enrichment.yaml`:** New multi-site configuration with `CZ2_KLARF_18_Si`, `DEFAULT`, `JND`, and `BK_SICA88_Rework` site profiles.
- **`PPLogger`:** Integration for `refdb.pp_log` persistence with `--pplog` CLI flag.

### 2025-Aug-06 — Filename Timestamp & Wafer Number Ordering

- **`Writer.py`:** Made timestamp in filename optional (`use_timestamp_in_filename` parameter).
- **`IFF.py`:** Added `build_outfilename()` to ensure wafer number(s) are the last segment before the file extension.

### 2025-Apr-02 — IFF/SXML Refactor

- **`Writer.py`, `IFF.py`, `SXML.py`:** Major refactor of Python scripts involved in translation, enrichment, and generation of IFF, XML, and SXML formats.

---

## Directory Structure

```
scripts/py/
├── klarf_18_enricher.py          # Entry point
├── resources/
│   └── Klarf18_Enrichment.yaml   # Site configuration
├── lib/
│   ├── Parser/
│   │   └── Klarf18.py            # Klarf 1.8 parser
│   ├── Enricher/
│   │   ├── Klarf18Enricher.py    # Klarf 1.8 enricher
│   │   ├── Klarf12Enricher.py    # Klarf 1.2 enricher (related)
│   │   ├── KDFXmlEnricher.py     # KDF XML enricher
│   │   ├── SxmlEnricher.py       # SXML enricher
│   │   └── SiCWlbiEnricher.py    # SiC WLBI enricher
│   ├── Formatter/
│   │   ├── IFF.py                # Internal Flat File formatter
│   │   └── SXML.py               # SXML formatter
│   ├── Writer.py                 # Atomic file writer
│   ├── Log.py                    # Centralized logging
│   ├── PPLogger.py               # DB preprocessing logger
│   ├── Util.py                   # Shared utilities
│   ├── Data/
│   │   ├── MetadataDTO.py        # Metadata DTO with XML generation
│   │   ├── MetadataDTOAttribute.py
│   │   ├── Base.py, Model.py, Wafer.py, Die.py, Bin.py, Test.py, ...
│   │   └── Models/
│   │       └── PPLog.py          # SQLAlchemy model for pp_log
│   └── WS/
│       └── RefdbAPIClient.py     # ERT Reference DB REST client
└── docs/
    └── Klarf1.8/
        └── claude.md             # This file
```
