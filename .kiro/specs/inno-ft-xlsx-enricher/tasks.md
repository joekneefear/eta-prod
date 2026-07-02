# Implementation Plan: INNO FT XLSX Parser and Enricher

## Overview

Implement `inno_ft_xlsx_enricher.py` and its supporting Parser/Enricher classes following the `klarf_18_enricher.py` pattern. All field mapping logic lives in `InnoFtXlsx_Enrichment.yaml`. The implementation builds incrementally: YAML config → Parser → Enricher → main script.

## Tasks

- [x] 1. Create the YAML enrichment configuration
  - Create `scripts/py/resources/InnoFtXlsx_Enrichment.yaml`
  - Add `INNO_DEFAULT` site block with `match_fab: ["INNO"]`, `env: "inno_ft_xlsx"`, and all Include-field mappings from the mapping table:
    - `AlternateProduct`: `refdb` → `alternateProduct`, fallback: `field` → `Product` xlsx header
    - `EndTime`: `field` → `TestDate`, with date format transform
    - `Fab`: `refdb` → `fab`, fallback: `constant` `"NA"`
    - `LotId`: `field` → `LotID`
    - `MeasuringEquipment`: `field` → `TesterId`
    - `ProcessingStep`: `constant` → `"FT"`
    - `Product`: `refdb` → `product`, fallback: `field` → `Device Name`
    - `Recipe`: `field` → `Program`
    - `RecipeRevision`: `field` → `Program`, with `regex_replace: [".*_R(\\d+)_.*", "\\1"]`
    - `SourceLot`: `refdb` → `sourceLot` + `.S`; fallback: `field` → `LotID` + `regex_replace` to append `.S`
    - `StartTime`: `field` → `TestDate`, with date format transform
    - `WaferId`: `field` → `WaferModle`
    - `SubconLotId`: `field` → `Sub LotID`
    - `Operator`: `field` → `Operator ID`
  - Add `DEFAULT` block as pass-through (same as INNO_DEFAULT but without match_fab)
  - _Requirements: 2.1, 2.3, 2.4, 8.1_

- [x] 2. Implement `InnoFtXlsxParser`
  - [x] 2.1 Create `scripts/py/lib/Parser/InnoFtXlsxParser.py`
    - Load xlsx with `openpyxl` (`read_only=True`, `data_only=True`)
    - Parse header block: iterate rows until test table marker; for each row where col A is a known label and col B has a value, store `raw_header[label] = value`
    - Labels to capture: `Program`, `Product`, `WaferModle`, `LotID`, `TesterId`, `Handler`, `Device Name`, `Test temp`, `TestDate`, `Sub LotID`, `Operator ID`
    - Default missing labels to `"NA"` in `raw_header`
    - Detect test table start: row where col A is `Test#` or first numeric row under a `No` column
    - Parse `Test Parameter` row → test names list
    - Parse `LL`, `HL`, `Unit` rows → low limits, high limits, units lists
    - Parse data rows (col A = sequential int, col B = BIN) → `Die` objects
    - Build `Test` objects from test names + limits + units
    - Accumulate `Bin` objects for sbins/hbins
    - Store `raw_header` on `model.header._raw` (or as `model.header.raw_fields` dict attr)
    - Set `model.header.LOT = raw_header.get("LotID", "NA")`
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9_

  - [x]* 2.2 Write property test: Die count matches data rows
    - **Property 6: Die count matches data rows**
    - Generate synthetic xlsx-like row lists with N random numeric data rows
    - Assert `len(wafer.dies) == N`
    - **Validates: Requirements 3.7**

  - [x]* 2.3 Write property test: Whitespace-only header values become NA
    - **Property 5: Whitespace-only header values become NA**
    - Generate header row lists where value cell is whitespace-only or empty
    - Assert parsed field resolves to `"NA"`
    - **Validates: Requirements 3.8**

  - [x]* 2.4 Write unit tests for InnoFtXlsxParser
    - Parse sample file `scripts/py/docs/9UU190002 (1).xlsx`
    - Assert `raw_header["LotID"] == "9UU190002"`
    - Assert `raw_header["Device Name"] == "NTMT130N70GN1TXG"`
    - Assert `raw_header["Program"]` starts with `"IN0167"`
    - Assert test names, limits, and at least 5 dies are parsed
    - _Requirements: 3.2, 3.4, 3.5, 3.6, 3.7_

- [x] 3. Checkpoint — Ensure parser tests pass, ask the user if questions arise.

- [x] 4. Implement `InnoFtXlsxEnricher`
  - [x] 4.1 Create `scripts/py/lib/Enricher/InnoFtXlsxEnricher.py`
    - Mirror `Klarf18Enricher` structure: `__init__(raw_header, model, config, site, lot_metadata)`, `enrich()`, `_apply_mapping()`, `_resolve_rule()`, `_do_resolve()`
    - `_do_resolve` handles: `constant`, `field` (reads `raw_header[source]`), `refdb` (reads `lot_metadata[source]`, case-insensitive fallback), `composite`
    - Transformation phase: `slice`, `format`, `regex_replace`
    - `_resolve_rule` applies `fallback` when primary yields `"NA"` or empty
    - `enrich()` calls `_apply_mapping()`, then sets each resolved value on `model.header` via attribute name mapping (e.g., `LotId` → `model.header.LOT`, `AlternateProduct` → `model.header.ALTERNATE_PRODUCT`, etc.)
    - Target attribute map (YAML field name → `model.header` attr):

      ```
      AlternateProduct  → ALTERNATE_PRODUCT
      EndTime           → END_TIME
      Fab               → FAB
      LotId             → LOT
      MeasuringEquipment→ MEASURING_EQUIPMENT
      ProcessingStep    → PROCESSING_STEP
      Product           → PRODUCT
      Recipe            → RECIPE
      RecipeRevision    → RECIPE_REVISION
      SourceLot         → SOURCE_LOT
      StartTime         → START_TIME
      WaferId           → SCRIBE_ID
      SubconLotId       → SUBCON_LOT
      Operator          → OPERATOR
      ```
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 5.10_

  - [x]* 4.2 Write property test: Recipe revision extraction
    - **Property 1: Recipe revision extraction**
    - Generate random strings of form `PREFIX_R<N>_SUFFIX.pgs` with random N (1–999)
    - Assert enricher resolves `RecipeRevision` to str(N)
    - **Validates: Requirements 3.3, 5.5**

  - [x]* 4.3 Write property test: SourceLot always ends with `.S`
    - **Property 2: SourceLot always ends with .S**
    - Generate random LotID strings; enrich with empty `lot_metadata`
    - Assert `model.header.SOURCE_LOT.endswith(".S")`
    - **Validates: Requirements 5.9, 8.1**

  - [x]* 4.4 Write property test: LotId round-trip
    - **Property 3: LotId round-trip**
    - Generate random LotID values in raw_header
    - Assert `model.header.LOT == raw_header["LotID"]`
    - **Validates: Requirements 3.2, 5.3**

  - [x]* 4.5 Write property test: Fallback activates on missing refdb key
    - **Property 4: Fallback activates on missing refdb key**
    - Generate rules with type `refdb` + a `fallback` sub-rule; pass empty `lot_metadata`
    - Assert resolved value equals fallback result, not `"NA"`
    - **Validates: Requirements 4.4, 5.7**

  - [x]* 4.6 Write unit tests for InnoFtXlsxEnricher
    - Test constant resolution, field resolution against a known raw_header dict
    - Test RefDB resolution with a mock `lot_metadata` dict
    - Test `regex_replace` and `format` transforms
    - _Requirements: 5.1–5.10_

- [x] 5. Checkpoint — Ensure enricher tests pass, ask the user if questions arise.

- [x] 6. Implement `inno_ft_xlsx_enricher.py` (main script)
  - [x] 6.1 Create `scripts/py/inno_ft_xlsx_enricher.py`
    - Copy `initialize_log_file()` from `klarf_18_enricher.py` verbatim
    - `main()` flow:
      1. Setup PPLogger, Log, parse CLI args with `Util.process_command_line_args`
      2. Validate `--infile` and `--out`; exit 1 if missing
      3. Load YAML config; exit 1 if not found
      4. Decompress `.gz` if needed
      5. Call `InnoFtXlsxParser().parse_to_model(infile)` → `model`
      6. Set `pplogger.set_lot(model.header.LOT)`
      7. Determine `site`: use `--site` arg if provided; else auto-detect from `LotID` via `match_fab` patterns in YAML; else `"DEFAULT"`
      8. Set PPLogger env/site from YAML site config
      9. Call RefDB `on_lot` if `--ws_url` and `--ws_source` provided; handle `ws_site_retry`
      10. Determine `route_to_sandbox_no_meta` (same logic as `klarf_18_enricher.py`)
      11. Call `InnoFtXlsxEnricher(raw_header, model, config, site, lot_metadata).enrich()`
      12. Set `model.header.DATA_FILE_NAME`, `AREA = "FT"`, `PROGRAM_CLASS = 2`, build `PROGRAM` name
      13. `model.build_limit()`
      14. Open `Writer`, instantiate `IFF`, call `print_par_per_wafer_number()` + `print_limit()`
      15. `pplogger.set_limit_file(...)`, `Util.dp_exit(0)`
    - _Requirements: 1.1–1.6, 4.1–4.6, 6.1–6.7, 7.1–7.6_

  - [x]* 6.2 Write property test: Sandbox routing when refdb fields missing
    - **Property 7: Sandbox routing when refdb fields missing**
    - For any site config with at least one `refdb` field and `on_lot_no_data_status=True`, assert `route_to_sandbox_no_meta == True` (and `== False` when `force_prd=True`)
    - **Validates: Requirements 4.6, 6.6**

  - [x]* 6.3 Write integration test using sample file
    - Parse `scripts/py/docs/9UU190002 (1).xlsx` end-to-end (no RefDB call)
    - Assert output IFF file is created in a temp dir
    - Assert `model.header.LOT == "9UU190002"`, `model.header.SOURCE_LOT == "9UU190002.S"`
    - Assert `model.header.RECIPE_REVISION == "10"` (from `_R10_` in program name)
    - Assert `model.header.ALTERNATE_PRODUCT == "IN0167"` (from xlsx `Product` fallback)
    - Assert `model.header.PRODUCT == "NTMT130N70GN1TXG"` (from xlsx `Device Name` fallback)
    - _Requirements: 1.1, 3.2, 3.3, 5.3, 5.8, 5.9, 6.1_

- [x] 7. Final Checkpoint — Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- The `raw_header` dict uses the exact xlsx label strings as keys (e.g., `"Device Name"`, `"Sub LotID"`) — the YAML `source` values must match these exactly
- `RecipeRevision` regex: `.*_R(\d+)_.*` → replacement `\1` (capture group only)
- `SourceLot` fallback regex: `(.*)` → replacement `\1.S` (or simply append `.S` after stripping any existing `.S`)
- openpyxl must be available in the environment (already used by `Dts1k2kXlsParser`)
