# SubCon Refdata: migrate to `n_refdata_extract.py`

This document shows an example of how to run the SubCon LOT reference-data extraction using the new `n_refdata_extract.py` runner with optional column collapse (COALESCE-like behavior). The approach preserves previous single-column output behavior when `column_collapse` is not used.

## CLI Example

```bash
n_refdata_extract.py \
  --source_odbc LOTGDB \
  --source_schema LOTG_OWNER \
  --sql_file subcon_lot_refdata.sql \
  --output_prefix SubconLotRefData \
  --header "LOT|PARENT_LOT|PRODUCT|LOT_OWNER|SOURCE_LOT" \
  --column_collapse '{"PRODUCT": [4, 3]}' \
  --delimiter "|"
```

- `--column_collapse` is optional. If omitted, `n_refdata_extract.py` will behave exactly like the legacy script (single-column or full multi-column output depending on the SQL/result set).
- The JSON for `--column_collapse` maps output columns to an ordered list of fallback column indices (0-based). In the example above, `PRODUCT` uses column index `4` first, falling back to `3`.

## YAML Source Example

You can put the same configuration into a sources YAML/JSON file for `n_refdata_extract.py`:

```yaml
sources:
  - pipeline_name: SubconLotRefData
    source_odbc: LOTGDB
    source_schema: LOTG_OWNER
    sql_file: subcon_lot_refdata.sql
    output_prefix: SubconLotRefData
    header: "LOT|PARENT_LOT|PRODUCT|LOT_OWNER|SOURCE_LOT"
    column_collapse: {"PRODUCT": [4, 3]}
    delimiter: "|"
```

## Notes

- The SQL should be extracted to `subcon_lot_refdata.sql` and should return the columns in the order implied by the header. The `column_collapse` indices should reference the returned columns by 0-based index.
- If you do not set `column_collapse`, the runner will preserve legacy behavior.
- Archive and benchmark logging remain unchanged and will be written to the configured directories.

Saved to: `docs/subcon_refdata_migration.md`

## SQL file and parameters

- The extracted SQL was saved to `scripts/subcon_lot_refdata_query.sql` and contains a placeholder comment for the time filter. Replace the placeholder comment with one of the following options:
  - Specific range:

    ```sql
    AND POST_DATE BETWEEN TO_DATE(:from_date, 'YYYY-MM-DD')
                      AND TO_DATE(:to_date || ' 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
    ```

  - Default recent (original behavior):

    ```sql
    AND POST_DATE >= sysdate - 32*interval '1' hour
    ```

- Using named parameters (`:from_date`, `:to_date`) lets you supply values via `--params_file` (recommended) or `--params_json` (inline).

## Example params file

Create `params.json` with:

```json
{
  "from_date": "2026-02-01",
  "to_date": "2026-02-01"
}
```

## CLI examples

- Using a params file (recommended on Windows):

```bash
python n_refdata_extract.py \
  --sql_file scripts/subcon_lot_refdata_query.sql \
  --source_odbc LOTGDB \
  --source_schema LOTG_OWNER \
  --reference_data_dir ./out \
  --benchmark_log_dir ./benchmark \
  --params_file params.json \
  --output_prefix SubconLotRefData \
  --header "LOT|LOT_CLASS|PARENT_LOT|PRODUCT|PARENT_PRODUCT|LOT_OWNER|SOURCE_LOT"
```

- Inline JSON (bash):

```bash
python n_refdata_extract.py --sql_file scripts/subcon_lot_refdata_query.sql \
  --params_json '{"from_date":"2026-02-01","to_date":"2026-02-01"}' \
  --source_odbc LOTGDB --reference_data_dir ./out
```

- Inline JSON (PowerShell):

```powershell
python n_refdata_extract.py --sql_file scripts/subcon_lot_refdata_query.sql \
  --params_json '{ "from_date":"2026-02-01", "to_date":"2026-02-01" }' \
  --source_odbc LOTGDB --reference_data_dir ./out
```

## Column collapse reminder

- The SQL returns columns in this order (0-based indices):
  - 0: `LOT`
  - 1: `LOT_CLASS`
  - 2: `PARENT_LOT`
  - 3: `PRODUCT`
  - 4: `PARENT_PRODUCT`
  - 5: `LOT_OWNER`
  - 6: `SOURCE_LOT`

- To prefer `PARENT_PRODUCT` over `PRODUCT` use `--column_collapse '{"PRODUCT": [4,3]}'` (0-based indices). If omitted, legacy behavior is preserved.

## Quick note

- If you prefer not to use named params, you can leave the default recent interval in the SQL and run without `--params_file`.
