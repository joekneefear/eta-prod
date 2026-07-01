# Qorvo FT PSI CSV Pipeline — Documentation

> **Last Updated:** 2026-03-12  
> **Author:** jgarcia  
> **Python Version:** 3.12

---

## Overview

The **Qorvo FT PSI CSV Pipeline** processes Qorvo PSI (Product Specific Information) Final Test CSV data files, parsing parametric test results, bin summaries, and die-level measurements into an Internal Flat File (IFF) format with gzip compression. There are **two variants**:

| Variant | Entry Point | Parser | Data Source | Description |
|---------|-------------|--------|-------------|-------------|
| **PSI** | `qorvo_ft_psi_csv.py` | `QorvoPsiParser` | PSI QA/FT/RG CSV | Standard PSI test data (QA, FT, RG processing steps) |
| **PSI CR** | `qorvo_ft_psi_cr_csv.py` | `QorvoPsiCrParser` | PSI CRSS CSV | CRSS (Contact Resistance) test data |

```
┌──────────────┐    ┌──────────────────┐    ┌─────────┐    ┌──────────┐
│  PSI CSV     │───▶│  QorvoPsiParser  │───▶│  IFF    │───▶│  Writer  │
│  Input File  │    │  or CrParser     │    │  Format │    │  .iff.gz │
└──────────────┘    └──────────────────┘    └─────────┘    └──────────┘
```

Both scripts share the same output pipeline: `Model` → `IFF.print_par()` → `IFF.print_limit()` → `Writer` with gzip.

---

## Core Scripts

### 1. Entry Point — `qorvo_ft_psi_csv.py`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/qorvo_ft_psi_csv.py` |
| **Purpose** | CLI entry point for standard PSI QA/FT/RG processing |
| **Created** | 2025-Mar-11 |

**CLI Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `--infile` | ✅ | Input PSI CSV file (supports `.gz`) |
| `--out` | ✅ | Output directory |
| `--site` | ✅ | Fab and site in `FAB_SITE` format (e.g., `QRV_ME`) |
| `--pstep` | ✅ | Processing step: `QA`, `FT`, or `RG` |
| `--config_file` | ❌ | Facility mapping YAML (default: `resources/xFCS_FACILITY_MAPPING.yaml`) |
| `--exclude_params` | ❌ | Flag to apply excluded parameter list from config |
| `--pplog` | ❌ | Enable PPLogger database persistence |
| `--logfile` / `--log_file` / `--log` | ❌ | Override log file path |

**Processing Flow:**

1. Initialize Oracle DB session, logging, and `PPLogger`
2. Parse `--site` into `fab` + `site` components
3. Load facility mapping config (env, excluded parameters)
4. Decompress input if `.gz`
5. Parse CSV via `QorvoPsiParser`:
   - `parse_to_model()` for QA/FT steps
   - `parse_to_model_RG()` for RG step
6. Set model header fields: `FAB`, `FACILITY`, `AREA=FT`, `PROGRAM_CLASS=2`
7. Build program name: `{site}_{PRODUCT}_{RECIPE}_{PROCESSING_STEP}`
8. Write IFF via `IFF.print_par()` and `IFF.print_limit()`
9. Exit with PPLogger

**IFF Output Configuration:**
```python
data_items  = ['partid', 'site', 'soft_bin', 'hard_bin', 'bindesc', 'touchdown_num', 'ecid']
test_items  = ['number', 'name', 'units']
bin_items   = ['number', 'name', 'PF', 'count']
```

---

### 2. Entry Point — `qorvo_ft_psi_cr_csv.py`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/qorvo_ft_psi_cr_csv.py` |
| **Purpose** | CLI entry point for PSI CRSS (Contact Resistance) processing |
| **Created** | 2025-May-21 |

**CLI Arguments:** Same as `qorvo_ft_psi_csv.py`.

**Key Differences from PSI variant:**

| Aspect | PSI | PSI CR |
|--------|-----|--------|
| Parser | `QorvoPsiParser(args=params)` | `QorvoPsiCrParser(infile=output)` |
| Processing steps | QA, FT, RG | Single model parse |
| Program name format | `{site}_{PRODUCT}_{RECIPE}_{STEP}` | `{site}_{PRODUCT}_{RECIPE}:{STEP}` |
| Limit input_file | Not set | `model.limit.input_file = basename` |
| Timestamp in filename | `False` | `False` |

---

## Parser Libraries

### 3. Parser — `lib/Parser/QorvoPsiParser.py`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/lib/Parser/QorvoPsiParser.py` |
| **Class** | `QorvoPsiParser` (extends `Base`) |
| **Size** | ~928 lines |
| **Created** | 2025-Mar-11 |

**Supported Processing Steps:**

| Step | Parse Method | CSV Structure |
|------|-------------|---------------|
| `QA` | `parse_to_model(infile, 'QA')` | Header rows → Test/Item/Limit/Bias columns → Serial data rows |
| `FT` | `parse_to_model(infile, 'FT')` | Same as QA with `DTA File Name` instead of `CSV File Name` |
| `RG` | `parse_to_model_RG(infile)` | `ItemName`/`Volt`/`FREQ`/`Level` rows → ID data rows |

**Key Methods:**

| Method | Description |
|--------|-------------|
| `parse_to_model(infile, pStep, excluded_params)` | Main parser for QA/FT. Extracts header rows (Test, Item, Limit, Bias 1/2, Time), builds tests with limits (LSL/HSL), and processes Serial-indexed die results. |
| `parse_to_model_RG(infile, excluded_params)` | RG-specific parser. Uses `ItemName`/`Volt`/`FREQ`/`Level` rows. Handles `OK`→`0`, `NG`→`1` result conversions and `mOhm`→`Ohm` unit conversion. |
| `construct_testname(row)` | Builds test name from Item + Bias conditions. Special handling for `ABSDEL` items (numeric `T#` formatting). |
| `construct_testname_RG(row_data)` | RG test name: `{Item}_Volt={v}_FREQ={f}_Level={l}` |
| `extract_lot_device_recipe_end_time_retestbin(data, pStep)` | Parses filename tokens to extract LotId, Device, Recipe, EndTime, RetestBin, SubconLotId. Filters unwanted subcon prefixes (`RB`, `00`, `DT`). |
| `extract_fields_from_data_rg(data)` | RG-specific extraction from `DataFileName`/`TestFileName` rows. Handles Windows/POSIX paths and multi-extension stripping. |
| `parse_and_format_date(date_string)` | Smart date parser with heuristics for ambiguous formats (day-first vs month-first, AM/PM detection, ISO detection). |
| `extract_numeric_from_str_RG(str_value)` | Extracts numeric value with `mOhm`/`m` unit conversion (÷1000). |

**SAME Value Handling (QA/FT):**

Items with name `SAME` reference another test by `Bias 1 Value` matching the target test number. Limits (LSL/HSL) are computed per group: `>` limits → LSL (max), `<` limits → HSL (min).

**Filename Parsing Pattern:**

```
FT_FT_DEVICE_LOTID_SUBCON.DTA  →  device=DEVICE, lot=LOTID, subcon=SUBCON
FT_DEVICE_LOTID.DTA            →  device=DEVICE, lot=LOTID, subcon=NA
```

Prefixes `FT`, `QA`, `RG` are consumed. Trailing `.DTA`, `.string`, etc. are stripped.

---

### 4. Parser — `lib/Parser/QorvoPsiCrParser.py`

| Item | Detail |
|------|--------|
| **Path** | `scripts/py/lib/Parser/QorvoPsiCrParser.py` |
| **Class** | `QorvoPsiCrParser` (extends `Base`) |
| **Size** | 359 lines |
| **Created** | 2025-May-20 |

**Key Methods:**

| Method | Description |
|--------|-------------|
| `parse_to_model(excluded_params)` | Main parse method. Extracts header, then processes `SITE_NUM`/`Units`/`Lower Limit`/`Upper Limit`/`Bias1`/`Bias2` parameter rows and numeric die data rows. |
| `extract_header()` | Regex-based extraction of `Program`, `Lot Id`, `WAFER_ID`, `Operator ID`, `Comment`, `Beginning Time`, `Ending Time` from CSV rows. Parses Recipe from `Program` path (splits on `\` for `Recipe` folder). |
| `extract_fourth_value()` | Extracts retest bin from the 4th underscore-delimited token of the input filename (only if it starts with `RB`). |
| `_extract_numeric(value)` | Regex extraction of numeric values including scientific notation. |

**CRSS CSV Structure:**

```
Program:      C:\...\Recipe\RECIPE_NAME\...
Lot Id:       PREFIX_PRODUCT_LOTID
WAFER_ID:     SCRIBE_ID
Operator ID:  OPERATOR
Beginning Time: 2025-05-20 14:30:00
Ending Time:    2025-05-20 15:00:00
SITE_NUM:     [col5] [col10+]  ← test names
Units:        [col5] [col10+]  ← units
Lower Limit:  [col5] [col10+]  ← LSL
Upper Limit:  [col5] [col10+]  ← HSL
Bias1:        [col5] [col10+]  ← bias labels
Bias2:        [col5] [col10+]  ← bias labels
--- data rows (regex: ^\d+,\d+,\d+,[^,]*,\d+,...) ---
```

**Test Naming:** `{SITE_NUM_name}_{Bias1}_{Bias2}` (biases appended only if present).

**Test Column Selection:** Columns at index 5 and index ≥ 10 are included as test columns (columns 6–9 are skipped).

---

## Shared Libraries Used

| Library | Path | Role in PSI Pipeline |
|---------|------|---------------------|
| `Model` | `lib/Data/Model.py` | Container for header, wafers, tests, bins, limits |
| `Metadata` | `lib/Data/Metadata.py` | Header metadata object (note: **not** `MetadataDTO` — PSI uses the simpler `Metadata` class) |
| `Wafer` | `lib/Data/Wafer.py` | Wafer container with tests, dies, sbins, hbins |
| `Test` | `lib/Data/Test.py` | Test definition with number, name, units, LSL/HSL/LPL/HPL |
| `Die` | `lib/Data/Die.py` | Die-level data: partid, site, bins, ecid, touchdown, results |
| `Bin` | `lib/Data/Bin.py` | Bin summary: number, name, PF, count |
| `IFF` | `lib/Formatter/IFF.py` | Formats and writes PAR, LIMIT, BIN, DATA sections |
| `Writer` | `lib/Writer.py` | Atomic file writer with temp+rename, gzip, PRODUCTION/SANDBOX routing |
| `PPLogger` | `lib/PPLogger.py` | Database logger for `refdb.pp_log` |
| `Log` | `lib/Log.py` | Centralized logging (file + console + PPLogger integration) |
| `Util` | `lib/Util.py` | CLI arg parsing, `rep_na`, `dp_exit`, YAML loading, `trim` |
| `DbConnectionFactory` | `lib/DbConnectionFactory.py` | Oracle DB session factory |

> **Note:** PSI scripts use `Metadata` (not `MetadataDTO`). The `MetadataDTO` class with XML generation is used by the Klarf 1.8 enrichment pipeline.

---

## Recent Changes

### 2025-Sep-14 — Updated Data Mapping

- **`QorvoPsiParser.py`:** Updated to adhere to new data mapping adjustments.

### 2025-Aug-28 — Data Mapping Update

- **`QorvoPsiParser.py`:** Updated parsing logic to adhere to updated data mapping specifications.

### 2025-Aug-06 — Filename Timestamp Removal

- **`Writer.py`:** Both PSI scripts set `use_timestamp_in_filename=False`. Wafer number(s) are now the last string segment before the file extension.

### 2025-Jun-10 to Jun-15 — Date Parsing Improvements

- **`QorvoPsiParser.py` / `QorvoPsiCrParser.py`:** Improved `parse_and_format_date()` to handle:
  - Day-first with `-` and `/` delimiters (in addition to space)
  - Ambiguous dates where both day and month values are ≤ 12
  - AM/PM detection to assume US format (month-first)
  - ISO format detection (4-digit year first)

### 2025-May-29 — PSI CR Initial

- **`qorvo_ft_psi_cr_csv.py`** and **`QorvoPsiCrParser.py`:** Initial implementation for CRSS (Contact Resistance) CSV parsing.

### 2025-May-05 to May-13 — PSI Finalization

- **`QorvoPsiParser.py`:** Finalized test name construction (removed test number prefix). Bug fix for locating `Serial` row index.

### 2025-Apr-02 — IFF/SXML Refactor

- **`QorvoPsiParser.py`:** Refactored as part of the broader IFF/SXML generation refactor.

### 2025-Mar-11 — PSI Initial

- **`qorvo_ft_psi_csv.py`** and **`QorvoPsiParser.py`:** Initial implementation for Qorvo PSI QA/FT CSV parsing.

---

## Directory Structure

```
scripts/py/
├── qorvo_ft_psi_csv.py               # PSI entry point (QA/FT/RG)
├── qorvo_ft_psi_cr_csv.py            # PSI CR entry point (CRSS)
├── resources/
│   └── xFCS_FACILITY_MAPPING.yaml    # Facility/env/excluded-params config
├── lib/
│   ├── Parser/
│   │   ├── QorvoPsiParser.py         # PSI QA/FT/RG parser (928 lines)
│   │   └── QorvoPsiCrParser.py       # PSI CR parser (359 lines)
│   ├── Formatter/
│   │   └── IFF.py                    # IFF output formatter
│   ├── Writer.py                     # Atomic file writer
│   ├── Data/
│   │   ├── Metadata.py               # Header metadata (used by PSI)
│   │   ├── Model.py, Wafer.py, Die.py, Test.py, Bin.py, ...
│   │   └── Limit.py                  # Limit data container
│   ├── Log.py                        # Centralized logging
│   ├── PPLogger.py                   # DB preprocessing logger
│   └── Util.py                       # Shared utilities
└── docs/
    └── PSI_FT/
        └── claude.md                 # This file
```
