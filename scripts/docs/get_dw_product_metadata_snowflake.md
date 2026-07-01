# get_dw_product_metadata_snowflake.py

Python script replacing the legacy `getDWProductMetadata.sh` script to securely extract Data Warehouse product metadata directly from Snowflake.

## Overview
This script executes a complex, pre-defined SQL query against the Snowflake database (specifically `ANALYTICSPRD.ENTERPRISE.PART_DIM` and `applicationprd.mfg.get_supply_path_end_part_component_site`) to extract product configuration metadata. The extracted result set is sanitized and written to a pipe-delimited text file. 

By default, the script also securely logs execution benchmarks and records the execution details to a `jsonl` file. It is designed to be highly resilient, preventing concurrent executions using a cross-platform file locking mechanism.

## Features
- **Cross-Platform Singleton Execution:** Uses `filelock` to guarantee only one instance of the script runs at a time across any host OS, preventing race conditions or locked file overwrites.
- **Robust Data Sanitization:** Automatically replaces or strips double (`"`) and single (`'`) quotes from all Snowflake string fields during CSV writing to avoid downstream parser breaking.
- **Resilient Output Generation & Archival:** If a previous run was successful, the script will create a gzip archive of the older metadata file before overwriting the current state.
- **Non-blocking Telemetry:** Wraps all benchmark logging (to local JSONL files and Oracle Database insertion) within `try-except` blocks. This ensures the main data extraction and metadata file generation process is never halted by a peripheral logging or database connection failure.
- **Environment Driven Settings:** Designed to be run without arguments in production environments by deferring to system environment variables for paths and credentials.

---

## Configuration & Usage

The script is intended to be executed from the command line or scheduled via a cron/batch job orchestrator. 

```bash
python get_dw_product_metadata_snowflake.py [options]
```

### Script Arguments & Flags

| Flag / Option | Description |
| :--- | :--- |
| `--test`, `-t` | Run in test mode. Outputs files to the test directory (`/export/home/dpower/jag/test_refdata`) instead of the production archive paths (`/apps/exensio_data/reference_data`). |
| `--no-benchmark` | Disable benchmark JSONL and Oracle logging entirely for the run (Benchmarking is enabled by default). |
| `--pipeline-name <NAME>` | Override the pipeline name string used for benchmark logging. Defaults to `DWProductMetadata`. |
| `--pipeline-type <TYPE>` | Override the pipeline type string used for benchmark logging. Defaults to `batch`. |
| `--no-archive` | Skip creating a `.gz` archive backup of the existing output file before executing the new export. |
| `--header <STRING>` | Optional pipe-delimited string to write as the first row of the output file. Defaults to `PRODUCT\|ITEM_TYPE\|FAB\|FAB_DESC\|AFM\|PROCESS...` |
| `--snow-user <USER>` | Override the Snowflake database username. Defaults to the `SNOW_USER` environment variable. |
| `--snow-pass <PASS>` | Override the Snowflake database password. Defaults to the `SNOWFLAKE_PASSWORD` environment variable. |
| `--ora-user <USER>` | Override the Oracle database username used purely for benchmark database inserts. Defaults to `DWH_MSTR_USR`. |
| `--ora-pass <PASS>` | Override the Oracle database password. Defaults to the `DWH_MSTR_PASSWORD` environment variable. |

---

## Execution Examples

**1. Standard Production Run (Default)**
Running the script without any arguments will utilize the system's environment variables for credentials and write out the metadata to the production `/apps/exensio_data/` paths. It will log benchmarks to the production JSONL file and archive the old output.
```bash
python get_dw_product_metadata_snowflake.py
```

**2. Test Environment Run**
This will execute the script using the `--test` flag. It will pull the data from Snowflake exactly the same, but route the output file (`product.out`) and the benchmark telemetry string to the test directories instead.
```bash
python get_dw_product_metadata_snowflake.py -t
```
```bash
python get_dw_product_metadata_snowflake.py --test
```

**3. Silent Data Extract (No Benchmarks, No Backups)**
If you simply want to rapidly fetch the product metadata file and overwrite the local copy without triggering any secondary Oracle logs or gzip archives, use these flags:
```bash
python get_dw_product_metadata_snowflake.py --no-benchmark --no-archive
```

**4. Custom Pipeline Telemetry Tracking**
If you are testing different pipeline ingestion topologies and want to track the runs differently in the JSONL benchmark log, you can override the string keys:
```bash
python get_dw_product_metadata_snowflake.py --pipeline-name "my_custom_integration" --pipeline-type "streaming"
```

**5. Local Workstation Run with Explicit Credentials**
If you are debugging locally on Windows and lack the full Unix environment variables, you can explicitly pass the Snowflake and Oracle DB keys to authenticate:
```bash
python get_dw_product_metadata_snowflake.py --snow-user my_sf_user --snow-pass MyS3cret! --ora-pass My0raclePass!
```

---

## File Operations & Output Paths

**Output Generation:**
The script writes the raw SQL extract to a temporary `.tmp` file in the configured directory, performs the quote sanitization pass, and finally renames it to `product.out`. 

**Production Paths (Default):**
- **Output:** `/apps/exensio_data/reference_data/product.out`
- **Archive:** `/apps/exensio_data/archives-yms/reference_data/product/`
- **JSONL Benchmark Log:** `/apps/exensio_data/reference_data/benchmark/benchmark.jsonl`

**Test Paths (`--test`):**
- **Output:** `/export/home/dpower/jag/test_refdata/product.out`
- **Archive:** `/export/home/dpower/jag/test_refdata/archive/`
- **JSONL Benchmark Log:** `/export/home/dpower/jag/test_refdata/benchmark/benchmark.jsonl`
