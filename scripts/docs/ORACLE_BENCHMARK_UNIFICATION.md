# Oracle Benchmark Logging Unification

This document outlines the unified Oracle benchmark logging standard implemented across the primary data extraction scripts. This standardization ensures consistent observability, granular file-level reporting, and full compatibility with the `pipeline-service-prod` backend.

## Standardized Scripts

- **LotG Metadata**: `scripts/py/pipelines/get_subcon_lot_metadata_lotG.py`
- **Snowflake Metadata**: `scripts/py/pipelines/get_dw_product_metadata_snowflake.py`
- **E142 Module Trace**: `scripts/getSnowflakeE142ModuleTrace.pl` (Uses `VIEW_NAME` option as source name)
- **Camstar Genealogy**: `scripts/getCamstarWafer2AssemblyGenealogy.pl`

## Key Features

### 1. Unified Schema Support
All scripts now populate the complete set of columns in the `pipeline_runs` table:
- **Execution Context**: `status`, `error_message`, `hostname`, `run_args`, `pid`.
- **Performance Metrics**: `start_local`, `end_local`, `elapsed_seconds`, `elapsed_human`.
- **Data Metrics**: `rows_extracted`, `rows_written`, `total_files`, `rowcount`.

### 2. Structured `out_files` Column
The `out_files` column (Oracle `CLOB`) contains a JSON-serialized array of dictionaries. This allows the backend to precisely track which file contains what data:
```json
[
  { "path": "/apps/exensio_data/E142_B1T-WAFER.csv.gz", "rows": 1250 },
  { "path": "/apps/exensio_data/archive/E142_B1T-WAFER.csv.gz", "rows": 1250 }
]
```

### 3. Default Credentials & Connection
Scripts are configured to use a central `refdb` Oracle account and a default `EXNQA` connection string if no overrides are provided:
- **Default DSN**: `exnqa-db.onsemi.com:1740/EXNQA.onsemi.com` (Used if `--benchmark_db_dsn` is omitted and `$BENCHMARK_DB_DSN` is empty)
- **Default User**: `refdb`
- **Default Password**: `br#^gox66312sdAB` (Triggered by `--benchmark_db_user` flag)

## Backend Integration

The data produced by these scripts is consumed by the `pipeline-service-prod` dashboard. By adhering to the `PipelineInfo` model, these scripts enable:
- **Drill-down views** into individual file row counts.
- **Environment tracking** (Dev vs QA vs Prod).
- **Audit trails** of the exact command-line arguments used for every run.
