# Integrating ERT API Priority in Klarf 1.8

The objective is to prioritize Reference Table data (via ERT API `on_lot` endpoint) over Klarf 1.8 parsed data for specific columns like `AlternateProduct`, `Fab`, `Facility`, `LotType`, `Process`, `SourceLot`, and `Technology`.

## Proposed Changes

### 1. `klarf_18_enricher.py`
- Add command-line parameters `--ws_url` and `--ws_source` (similar to `pp_bk_sic_wlbi_analog.py`).
- Implement querying the `RefdbAPIClient` for the extracted `lot_id` from the Klarf file.
- Support the lot modification logic (e.g. handling `M0`, `KG` prefixes) to ensure the API finds the lot.
- Pass the resulting `lot_metadata` JSON into `Klarf18Enricher`.

### 2. `lib/Enricher/Klarf18Enricher.py`
- Update constructor to accept `lot_metadata`.
- Update `_do_resolve` to handle `type: refdb`.
  - When `type: refdb` is encountered, look up the `source` key in `self.lot_metadata`.
  - If found and not nullish, return it with `meta_source="ERT_REFDB"`.
  - If not found or API failed, it respects the existing `fallback` mechanism.

### 3. `resources/Klarf18_Enrichment.yaml`
- Use the prioritized `fallback` chaining feature in YAML for the `BK_SICA88_Rework` site.
  - Example: `AlternateProduct` first tries `type: refdb, source: productCode`, and falls back to `type: constant`.
  - Example: `Product` doesn't use `refdb`, it uses `type: field` with `regex_replace` as defined originally.
  - Example: `SourceLot` tries `type: refdb` and uses `format: "{0}.S"`.

## Verification Plan

- Manually verify that `klarf_18_enricher.py` accurately reads the ERT API and applies it to the XML `<Metadata>` section when the API answers successfully.
