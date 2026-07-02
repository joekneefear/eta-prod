# Design Document: INNO FT XLSX Parser and Enricher

## Overview

`inno_ft_xlsx_enricher.py` reads a Final Test Excel (`.xlsx`) file produced by INNO test equipment, parses the header block and test-result table, calls the RefDB `on_lot` REST endpoint, maps fields according to a YAML configuration file, and writes a gzip-compressed IFF output file. All mapping logic lives in YAML for operator-driven configurability — mirroring `klarf_18_enricher.py`.

---

## Architecture

```
CLI (inno_ft_xlsx_enricher.py)
       │
       ├─ 1. Load YAML config  (InnoFtXlsx_Enrichment.yaml)
       ├─ 2. Parse xlsx        (lib/Parser/InnoFtXlsxParser.py)
       │       └─ openpyxl read-only, data_only=True
       │       └─ header block → dict (label: value)
       │       └─ test table   → Model (tests + dies)
       ├─ 3. RefDB on_lot call (lib/WS/RefdbAPIClient.py)
       │       └─ lot_metadata dict
       ├─ 4. Enrich            (lib/Enricher/InnoFtXlsxEnricher.py)
       │       └─ YAML-driven field resolution
       │       └─ writes to model.header (Metadata)
       ├─ 5. Write IFF         (lib/Writer + lib/Formatter/IFF.py)
       │       └─ gzip-compressed output
       └─ 6. PPLogger          (lib/PPLogger.py)
```

---

## Components and Interfaces

### 1. `inno_ft_xlsx_enricher.py` (entry point)

Mirrors `klarf_18_enricher.py` structure exactly:
- `initialize_log_file()` — respects `DPLOG` env var and `--log*` overrides
- `main()` — parses CLI args, orchestrates all steps, calls `Util.dp_exit`

CLI args:

| Arg | Required | Description |
|---|---|---|
| `--infile` | yes | Input `.xlsx` or `.xlsx.gz` file |
| `--out` | yes | Output directory |
| `--site` | no | Force site key (skips auto-detect) |
| `--config` | no | YAML config path (default: `resources/InnoFtXlsx_Enrichment.yaml`) |
| `--ws_url` | no | YAML file containing RefDB endpoint URLs |
| `--ws_source` | no | Source key within ws_url YAML (e.g., `prod`) |
| `--pplog` | no | Enable PPLogger database persistence |
| `--force_prd` | no | Force production routing even if RefDB returns no data |
| `--forced_final_folder` | no | `SBX` forces sandbox output |

### 2. `lib/Parser/InnoFtXlsxParser.py`

Parses the INNO xlsx format into a `Model` object.

**Header block** — rows at top of sheet 1, each row is `[label, empty, value]`:

| xlsx Label | Parsed to |
|---|---|
| `Program` | `header['Program']` (full name, e.g. `IN0167_FT1x4_STGB_DFNX_R10_125C.pgs`) |
| `Product` | `header['Product']` (INNO product code, e.g. `IN0167`) |
| `WaferModle` | `header['WaferModle']` |
| `LotID` | `header['LotID']` |
| `TesterId` | `header['TesterId']` |
| `Handler` | `header['Handler']` |
| `Device Name` | `header['Device Name']` |
| `Test temp` | `header['Test temp']` |
| `TestDate` | `header['TestDate']` |
| `Sub LotID` | `header['Sub LotID']` |
| `Operator ID` | `header['Operator ID']` |
| `Lot_Q'ty` | `header['Lot_Qty']` (not loaded to IFF — skip) |
| `STS8200 StationA` | skipped |

**Test table detection** — scan rows until column A matches `Test#` or is numeric (`No` column). The table structure is:

```
         T1          T2          T3         T4
         Vth_HT      Igss_HT     Ron_HT     Idss_HT
LL       1           -10000      120        -1000
HL       3.5         508000      220        55000
Unit     V           nA          mohm       nA
No       BIN         ...
1        1           1.6319      17846.21   ...
```

**Recipe revision** — extracted from `Program` field using pattern `_R(\d+)_`. Example: `IN0167_FT1x4_STGB_DFNX_R10_125C.pgs` → `10`.

**Public interface:**

```python
class InnoFtXlsxParser:
    def parse_to_model(self, infile: str) -> Model
```

`parse_to_model` returns a fully populated `Model` with:
- `model.header` — `Metadata` object with parsed header fields stored in `model.header._raw` dict
- `model.tests` — list of `Test` objects
- `model.wafers[0].dies` — list of `Die` objects
- `model.wafers[0].sbins` / `hbins` — accumulated bin counts

### 3. `lib/Enricher/InnoFtXlsxEnricher.py`

Maps parsed header fields + RefDB metadata → `model.header` (`Metadata`) attributes using YAML-driven rules. Mirrors `Klarf18Enricher` API and logic.

```python
class InnoFtXlsxEnricher:
    def __init__(self, raw_header: dict, model: Model, config: dict,
                 site: str = "DEFAULT", lot_metadata: dict = None)
    def enrich(self) -> Model  # populates model.header, returns model
```

Field resolution follows the same rule chain as `Klarf18Enricher`:
1. Extract by rule type (`constant`, `field`, `refdb`, `composite`)
2. Apply transforms (`slice`, `format`, `regex_replace`)
3. Use `fallback` if result is `"NA"` or empty

The enricher maps resolved values onto `model.header` attributes by target name (e.g., `LOT`, `SOURCE_LOT`, `RECIPE`, `RECIPE_REVISION`, `TESTER_ID`, etc.) using `setattr`.

### 4. `resources/InnoFtXlsx_Enrichment.yaml`

Top-level keys are site names. Each has:
- `env` — PPLogger environment name
- `match_fab` — list of substrings to auto-detect site from `LotID` or a site-supplied field (optional)
- `ws_site_retry` — optional retry site param for RefDB
- `fields` — mapping rules dict

**Supported rule types:**

| Type | Description |
|---|---|
| `constant` | Literal `value` |
| `field` | Read from `raw_header[source]` |
| `refdb` | Read from `lot_metadata[source]` |
| `composite` | Template string built from named sub-parts |
| + `regex_replace` | `[pattern, replacement]` applied to resolved value |
| + `format` | Python `.format()` applied to resolved value |
| + `slice` | `[start, end]` substring |
| + `fallback` | Secondary rule used when primary yields `"NA"` |

---

## Data Models

### xlsx `raw_header` dict (output of parser, input to enricher)

```python
{
    "Program":     "IN0167_FT1x4_STGB_DFNX_R10_125C.pgs",
    "Product":     "IN0167",
    "WaferModle":  "B07233.08",
    "LotID":       "9UU190002",
    "TesterId":    "T-435",
    "Handler":     "NIEpsonHandlerX.dll",
    "Device Name": "NTMT130N70GN1TXG",
    "Test temp":   "125C",
    "TestDate":    "5/28/2026",
    "Sub LotID":   "WC201HW0101",
    "Operator ID": "20051905",
}
```

### `Metadata` attribute mapping (target → `model.header.<ATTR>`)

| YAML field name | `model.header` attr | Notes |
|---|---|---|
| `AlternateProduct` | `ALTERNATE_PRODUCT` | refdb `alternateProduct`, fallback: `Product` xlsx field |
| `EndTime` | `END_TIME` | xlsx `TestDate` formatted |
| `Fab` | `FAB` | refdb `fab`, fallback: `"NA"` |
| `LotId` | `LOT` | xlsx `LotID` |
| `MeasuringEquipment` | `MEASURING_EQUIPMENT` | xlsx `TesterId` |
| `ProcessingStep` | `PROCESSING_STEP` | constant `"FT"` |
| `Product` | `PRODUCT` | refdb `product`, fallback: xlsx `Device Name` |
| `Recipe` | `RECIPE` | xlsx `Program` (full name) |
| `RecipeRevision` | `RECIPE_REVISION` | regex `_R(\d+)_` on `Program` |
| `SourceLot` | `SOURCE_LOT` | refdb `sourceLot` + `.S`, fallback: `LotID` + `.S` |
| `StartTime` | `START_TIME` | xlsx `TestDate` formatted |
| `WaferId` | `SCRIBE_ID` | xlsx `WaferModle` |
| `SubconLotId` | `SUBCON_LOT` | xlsx `Sub LotID` |
| `Operator` | `OPERATOR` | xlsx `Operator ID` |

---

## Correctness Properties

A property is a characteristic or behavior that should hold true across all valid executions — a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.

Property 1: Recipe revision extraction
*For any* program string containing the pattern `_R<digits>_`, the parsed `RecipeRevision` must equal those digits.
**Validates: Requirements 3.3**

Property 2: SourceLot always ends with `.S`
*For any* LotID value parsed from a valid xlsx file, the resolved `SOURCE_LOT` metadata field must end with the suffix `.S`.
**Validates: Requirements 5.9, 8.1**

Property 3: LotId round-trip
*For any* xlsx file with a non-empty `LotID` header cell, parsing then enriching must produce a `LOT` field equal to the raw `LotID` value.
**Validates: Requirements 3.2, 5.3**

Property 4: Field fallback activates on missing refdb
*For any* refdb-typed mapping rule, when `lot_metadata` is empty or the target key is absent, the resolved value must equal the fallback rule's result (not `"NA"` if a fallback is configured).
**Validates: Requirements 4.4, 5.7**

Property 5: Whitespace-only header values become `"NA"`
*For any* xlsx header cell whose value is composed entirely of whitespace (or is empty), the corresponding parsed field must resolve to `"NA"` in the raw header dict.
**Validates: Requirements 3.8**

Property 6: Die count matches data rows
*For any* xlsx file, the number of `Die` objects in `wafer.dies` must equal the number of numeric data rows in the test table (rows where column A is a positive integer).
**Validates: Requirements 3.7**

Property 7: Sandbox routing when refdb fields missing
*For any* site configuration that contains at least one `refdb`-typed field and whose `on_lot` call returns a no-data status, the writer's `noMeta` flag must be `True` (unless `--force_prd` is set).
**Validates: Requirements 4.6, 6.6**

---

## Error Handling

| Scenario | Behavior |
|---|---|
| `--infile` missing | `Log.ERROR` + `Util.dp_exit(1)` |
| `--out` missing | `Log.ERROR` + `Util.dp_exit(1)` |
| YAML config not found or unreadable | `Log.ERROR` + `Util.dp_exit(1)` |
| xlsx file unreadable | `Log.ERROR` + `Util.dp_exit(1)` |
| `LotID` missing from xlsx | `Log.WARN`, set `LOT = "NA"`, continue |
| RefDB call fails (network/timeout) | `Log.WARN`, proceed with fallbacks |
| RefDB returns `NO_DATA` / `ERROR` | `Log.WARN`, use fallbacks, set `noMeta=True` (unless `force_prd`) |
| Writer fails | `Log.ERROR` + `Util.dp_exit(1)` |

---

## Testing Strategy

**Unit tests** (`scripts/py/tests/test_inno_ft_xlsx_parser.py`, `test_inno_ft_xlsx_enricher.py`):
- Specific examples using the sample file `scripts/py/docs/9UU190002 (1).xlsx`
- Edge cases: empty cells, missing header rows, malformed Program strings with no `_R\d+_`
- Error conditions: missing required fields, bad YAML

**Property-based tests** — use `hypothesis` library (consistent with Python ecosystem; same choice as other test files in `scripts/py/tests/`):
- Each property test runs a minimum of 100 iterations
- Generators produce random xlsx-like header dicts and test tables

Property test tags (comment format):
```python
# Feature: inno-ft-xlsx-enricher, Property 1: Recipe revision extraction
# Feature: inno-ft-xlsx-enricher, Property 2: SourceLot always ends with .S
# Feature: inno-ft-xlsx-enricher, Property 3: LotId round-trip
# Feature: inno-ft-xlsx-enricher, Property 4: Field fallback activates on missing refdb
# Feature: inno-ft-xlsx-enricher, Property 5: Whitespace-only header values become NA
# Feature: inno-ft-xlsx-enricher, Property 6: Die count matches data rows
# Feature: inno-ft-xlsx-enricher, Property 7: Sandbox routing when refdb fields missing
```
