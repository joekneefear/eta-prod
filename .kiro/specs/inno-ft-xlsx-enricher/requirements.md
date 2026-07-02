# Requirements Document

## Introduction

This feature implements a parser and enricher for INNO Final Test Excel (`.xlsx`) data files. The script reads an xlsx file produced by INNO test equipment, extracts header metadata and test results, calls the RefDB `on_lot` endpoint to retrieve lot reference metadata, maps all fields according to a YAML configuration file, and writes an IFF output file. The mapping rules are driven entirely by the YAML config to allow easy per-site adjustments without code changes — following the same pattern as `klarf_18_enricher.py`.

## Glossary

- **Parser**: `InnoFtXlsxParser` — class that reads the INNO xlsx file and extracts the header block and test-result table into a structured `Model`.
- **Enricher**: `InnoFtXlsxEnricher` — class that maps extracted metadata fields and RefDB fields to the IFF metadata header using YAML-driven rules.
- **YAML Config**: `InnoFtXlsx_Enrichment.yaml` — site-keyed configuration file defining field mapping rules (constant, field, refdb, composite, regex, format) for each metadata target.
- **RefDB**: Reference Database REST API (`on_lot` endpoint) that returns lot-level metadata (product, fab, lotType, sourceLot, alternateProduct, etc.).
- **IFF**: Internal File Format — the output format produced via `Model` + `IFF` formatter classes already in `lib/`.
- **Model**: `lib/Data/Model.py` — data container for header metadata, tests, wafers, dies, and bins.
- **PPLogger**: `lib/PPLogger.py` — optional database logger for `refdb.pp_log` persistence.
- **Writer**: `lib/Writer.py` — handles output file routing (production vs sandbox) and optional gzip.
- **Site**: A YAML top-level key (e.g., `INNO_DEFAULT`, `INNO_KOREA`) identifying a site-specific mapping block.

---

## Requirements

### Requirement 1: Script Entry Point

**User Story:** As a data pipeline operator, I want to invoke the script from the command line with standard arguments, so that it integrates seamlessly with the existing ETL pipeline.

#### Acceptance Criteria

1. THE Script SHALL accept the following CLI parameters: `--infile`, `--out`, `--site`, `--config`, `--ws_url`, `--ws_source`, `--pplog`, `--force_prd`, `--forced_final_folder`.
2. IF `--infile` is not provided, THEN THE Script SHALL log an error and exit with code 1.
3. IF `--out` is not provided, THEN THE Script SHALL log an error and exit with code 1.
4. WHEN `--pplog` is passed, THE Script SHALL enable PPLogger database persistence.
5. THE Script SHALL initialize the log file using the same `initialize_log_file()` convention as `klarf_18_enricher.py` (respecting `DPLOG` env var, `--log` / `--logfile` overrides).
6. WHEN the input file has a `.gz` extension, THE Script SHALL decompress it before parsing.

---

### Requirement 2: YAML Configuration Loading

**User Story:** As an engineer, I want all field-mapping logic in a YAML file, so that I can adjust mappings per site without modifying Python code.

#### Acceptance Criteria

1. THE Script SHALL load `InnoFtXlsx_Enrichment.yaml` from `scripts/py/resources/` by default, overridable via `--config`.
2. IF the config file does not exist or fails to load, THEN THE Script SHALL log an error and exit with code 1.
3. THE YAML Config SHALL support a `DEFAULT` top-level site key used as the baseline mapping for all sites.
4. THE YAML Config SHALL support additional named site keys (e.g., `INNO_KOREA`) that override specific `DEFAULT` fields.
5. WHEN a `--site` argument is provided, THE Script SHALL use that site key from the YAML config.
6. IF no `--site` is provided and no auto-detection is possible, THE Script SHALL fall back to `DEFAULT`.

---

### Requirement 3: XLSX Parsing

**User Story:** As a data engineer, I want the parser to extract header metadata and test results from the INNO xlsx format, so that I can build a complete `Model` for IFF output.

#### Acceptance Criteria

1. THE Parser SHALL read the xlsx file using `openpyxl` (read-only mode, `data_only=True`).
2. THE Parser SHALL extract the following header fields from the xlsx header block (rows at the top of sheet 1 before the test table):

   | xlsx Field Label | Target Metadata Attr |
   |---|---|
   | `Program`        | `RECIPE` / `PROGRAM`  |
   | `Product`        | `ALTERNATE_PRODUCT`   |
   | `WaferModle`     | `WAFER_ID`            |
   | `LotID`          | `LOT_ID` / `SOURCE_LOT` |
   | `TesterId`       | `TESTER_ID`           |
   | `Handler`        | `HANDLER`             |
   | `Device Name`    | `PRODUCT`             |
   | `Test temp`      | `TEMPERATURE`         |
   | `TestDate`       | `START_TIME` / `END_TIME` |
   | `Sub LotID`      | `SUBCON_LOT_ID`       |
   | `Operator ID`    | `OPERATOR`            |

3. THE Parser SHALL extract `RecipeRevision` from the `Program` field using the pattern `_R(\d+)_` (e.g., `IN0167_FT1x4_STGB_DFNX_R10_125C.pgs` → revision `10`).
4. THE Parser SHALL detect the test table by finding the row containing `Test#` or `No` in column A.
5. THE Parser SHALL parse test parameter names from the row labeled `Test Parameter`.
6. THE Parser SHALL parse lower limits (`LL`), upper limits (`HL`), and units (`Unit`) rows into the model's test objects.
7. THE Parser SHALL parse each data row (where column A is a numeric part index and column B is a BIN value) into `Die` objects with test results.
8. IF a header field row is not found in the xlsx, THE Parser SHALL default that field to `"NA"`.
9. THE Parser SHALL support `.xlsx` and `.gz`-compressed `.xlsx` files.

---

### Requirement 4: RefDB on_lot Metadata Retrieval

**User Story:** As a data engineer, I want to enrich parsed lot data with RefDB reference metadata, so that fields like `Fab`, `LotType`, `Technology`, and `AlternateProduct` are populated from authoritative sources.

#### Acceptance Criteria

1. WHEN `--ws_url` and `--ws_source` are provided and a valid `LotID` was parsed, THE Script SHALL call the RefDB `on_lot` endpoint.
2. THE Script SHALL use `RefdbAPIClient` (existing `lib/WS/RefdbAPIClient.py`) to perform the HTTP call.
3. WHEN the `on_lot` response has a valid status (not `NO_DATA`, `ERROR`, `NULL`, or empty), THE Script SHALL use the returned metadata for field resolution.
4. WHEN the `on_lot` response is empty or has a no-data status, THE Script SHALL log a warning and proceed with YAML-defined fallback field values.
5. WHERE a YAML site config specifies `ws_site_retry`, THEN THE Script SHALL retry the `on_lot` call with that site parameter before using fallbacks.
6. WHEN RefDB metadata is unavailable and the YAML mapping uses `refdb`-typed fields, THE Script SHALL route the output to sandbox by setting `writer.noMeta = True` (unless `--force_prd` is set).

---

### Requirement 5: Field Mapping and Enrichment

**User Story:** As a data engineer, I want the YAML config to drive all field resolution, so that I can add or change mappings without touching Python code.

#### Acceptance Criteria

1. THE Enricher SHALL support the following YAML field mapping types: `constant`, `field`, `refdb`, `composite`, `regex_replace`, and `format`.
2. WHEN a field rule has type `constant`, THE Enricher SHALL use the literal `value` from the YAML.
3. WHEN a field rule has type `field`, THE Enricher SHALL read the named key from the parsed xlsx header dict.
4. WHEN a field rule has type `refdb`, THE Enricher SHALL read the named key from the RefDB on_lot response dict.
5. WHEN a field rule has a `regex_replace` transform, THE Enricher SHALL apply the pattern/replacement to the resolved value.
6. WHEN a field rule has a `format` transform, THE Enricher SHALL apply Python `.format()` string substitution.
7. WHEN a field rule has a `fallback` sub-rule, THE Enricher SHALL use it when the primary resolution returns `"NA"` or empty.
8. THE Enricher SHALL build the `RECIPE_REVISION` field by extracting the `_R(\d+)_` token from the `Program` xlsx field.
9. THE Enricher SHALL set `SOURCE_LOT` to `LotID + ".S"` when no RefDB sourceLot is available.
10. THE Enricher SHALL set `PROCESSING_STEP` to the constant `"FT"`.

---

### Requirement 6: IFF Output

**User Story:** As a pipeline consumer, I want the script to produce a valid gzip-compressed IFF file in the output directory, so that the downstream loader can ingest it.

#### Acceptance Criteria

1. THE Script SHALL write output using the existing `Writer` class with `gzipIFF=True`.
2. THE Script SHALL use the existing `IFF` formatter class from `lib/Formatter/IFF.py`.
3. THE IFF output SHALL include the following data items: `partid`, `site`, `soft_bin`, `hard_bin`, `bindesc`.
4. THE IFF output SHALL include the following test items: `number`, `name`, `units`.
5. THE IFF output SHALL include the following bin items: `number`, `name`, `PF`, `count`.
6. WHEN `writer.noMeta = True` (sandbox routing), THE Writer SHALL write to the sandbox output path.
7. WHEN `forced_final_folder = "SBX"` is passed, THE Writer SHALL force sandbox routing regardless of metadata status.

---

### Requirement 7: Logging and PPLogger

**User Story:** As a support engineer, I want all major steps logged and optionally persisted to the database, so that I can diagnose failures.

#### Acceptance Criteria

1. THE Script SHALL log all major processing steps (file read, parse, RefDB call, enrichment, write) via `Log.INFO`.
2. THE Script SHALL log all errors via `Log.ERROR` before exiting.
3. WHEN `--pplog` is passed, THE Script SHALL persist run metadata to `refdb.pp_log` via `PPLogger`.
4. THE PPLogger SHALL be populated with: raw file path, script name, site, env, lot ID, and limit file path.
5. WHEN processing completes successfully, THE Script SHALL call `Util.dp_exit(0, pplogger=pplogger)`.
6. WHEN processing fails, THE Script SHALL call `Util.dp_exit(1, pplogger=pplogger, error=<message>)`.

---

### Requirement 8: YAML Mapping for INNO Default Site

**User Story:** As a data engineer, I want a working `DEFAULT` YAML mapping block for the INNO xlsx format that correctly resolves all "Include" fields from the mapping table, so that the script produces valid output out of the box.

#### Acceptance Criteria

1. THE YAML Config `DEFAULT` block SHALL map the following fields using the rules below:

   | Metadata Field     | Mapping Rule |
   |---|---|
   | `AlternateProduct` | `refdb` → `alternateProduct`, fallback: xlsx `Product` |
   | `EndTime`          | `field` → xlsx `TestDate`, format `yyyy/mm/dd hh:mm:ss` |
   | `Fab`              | `refdb` → `fab`, fallback: `constant` `"NA"` |
   | `LotId`            | `field` → xlsx `LotID` |
   | `MeasuringEquipment` | `field` → xlsx `TesterId` |
   | `ProcessingStep`   | `constant` → `"FT"` |
   | `Product`          | `refdb` → `product`, fallback: xlsx `Device Name` |
   | `Recipe`           | `field` → xlsx `Program` (full program name) |
   | `RecipeRevision`   | `field` → xlsx `Program`, extract `_R(\d+)_` |
   | `SourceLot`        | `refdb` → `sourceLot`, format append `.S`; fallback: xlsx `LotID` + `".S"` |
   | `StartTime`        | `field` → xlsx `TestDate`, format `yyyy/mm/dd hh:mm:ss` |
   | `WaferId`          | `field` → xlsx `WaferModle` |

2. THE YAML Config SHALL include a site-specific block (e.g., `INNO_DEFAULT`) with `match_fab` patterns (e.g., `["INNOBE", "INNO"]`) for auto-detection.
