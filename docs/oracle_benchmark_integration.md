# Oracle Benchmark Integration for getCamstarWafer2AssemblyGenealogy.pl

## Overview

The `getCamstarWafer2AssemblyGenealogy.pl` script now supports writing benchmark/performance metrics directly to an Oracle database table in addition to (or instead of) the JSONL file format.

## Features

- **Dual persistence**: Write to both JSONL file and Oracle database simultaneously
- **Configurable credentials**: Support for environment variables or command-line arguments
- **Non-blocking**: Oracle insert failures won't stop the pipeline execution
- **Rich metadata**: Stores diagnostic counters (rows_fetched, rows_kept, rows_skipped) in JSON format
- **Flexible connection**: Supports TNS names or full Oracle connection strings

## Database Setup

### 1. Create the pipeline_runs table

Run the DDL script to create the table structure:

```sql
-- See: pipeline-service-prod/sql/create_pipeline_runs.sql
sqlplus user/pass@DWPRD @pipeline-service-prod/sql/create_pipeline_runs.sql
```

### 2. Apply metadata/benchmark migration

Add the JSON columns for extensible metadata storage:

```sql
-- See: pipeline-service-prod/sql/migration_add_metadata_benchmark.sql
sqlplus user/pass@DWPRD @pipeline-service-prod/sql/migration_add_metadata_benchmark.sql
```

## Configuration

### Command-Line Options

New options added to the script:

- `--benchmark_db_dsn`: Oracle DSN (TNS name or connection string)
- `--benchmark_db_user`: Database username (optional value; if flag passed without value, uses default: "refdb")
- `--benchmark_db_pass`: Database password (optional value; if flag passed without value, uses default: "br#^gox66312sdAB")

### Default Credentials

For convenience, the script supports default credentials. Simply pass the `--benchmark_db_user` flag without a value:

```bash
--benchmark_db_user
```

This will automatically use:
- Username: `refdb`
- Password: `br#^gox66312sdAB`

### Environment Variables

For custom credentials, use environment variables for better security:

```bash
export BENCHMARK_DB_USER="pipeline_user"
export BENCHMARK_DB_PASS="secure_password"
```

### Oracle DSN Formats

The `--benchmark_db_dsn` parameter accepts:

1. **TNS Name**: `DWPRD`, `LOTGPRD`, etc. (requires tnsnames.ora configuration)
2. **Connection String**: `//hostname:1521/service_name`

## Usage Examples

### Example 1: Default Credentials (Simplest - Recommended)

Use built-in default credentials by passing `--benchmark_db_user` without a value:

```bash
perl scripts/getCamstarWafer2AssemblyGenealogy.pl \
  --source_db CEBU \
  --source_warehouse application_prd_wh \
  --source_schema ANALYTICSPRD.FCS \
  --start_hours 2 \
  --end_hours 0 \
  --out_gen ./output/gen \
  --archive_gen ./archive/gen \
  --out_trace ./output/trace \
  --archive_trace ./archive/trace \
  --logfile ./log/getCamstarWafer2AssemblyGenealogy.log \
  --benchmark_log ./log/benchmark.jsonl \
  --benchmark_db_dsn DWPRD \
  --benchmark_db_user \
  --pipeline_name "camstar_wafer2assembly_cebu" \
  --pipeline_type "batch"
```

This uses:
- Username: `refdb`
- Password: `br#^gox66312sdAB`

### Example 2: Custom Credentials via Command Line

Specify custom credentials explicitly:

```bash
perl scripts/getCamstarWafer2AssemblyGenealogy.pl \
  --source_db OSV \
  --source_warehouse application_prd_wh \
  --source_schema ANALYTICSPRD.FCS \
  --start_hours 2 \
  --end_hours 0 \
  --out_gen ./output/gen \
  --archive_gen ./archive/gen \
  --out_trace ./output/trace \
  --archive_trace ./archive/trace \
  --logfile ./log/getCamstarWafer2AssemblyGenealogy.log \
  --benchmark_log ./log/benchmark.jsonl \
  --benchmark_db_dsn DWPRD \
  --benchmark_db_user "custom_user" \
  --benchmark_db_pass "custom_password" \
  --pipeline_name "camstar_wafer2assembly_osv" \
  --pipeline_type "batch"
```

### Example 3: Custom Credentials via Environment Variables

Use environment variables for better security:

```bash
export BENCHMARK_DB_USER="pipeline_writer"
export BENCHMARK_DB_PASS="$(cat /secure/oracle_password.txt)"

perl scripts/getCamstarWafer2AssemblyGenealogy.pl \
  --source_db ONSZ \
  --source_warehouse application_prd_wh \
  --source_schema ANALYTICSPRD.FCS \
  --start_hours 24 \
  --end_hours 0 \
  --out_gen ./output/gen \
  --archive_gen ./archive/gen \
  --out_trace ./output/trace \
  --archive_trace ./archive/trace \
  --logfile ./log/getCamstarWafer2AssemblyGenealogy_onsz.log \
  --benchmark_db_dsn "//oracle-server.example.com:1521/PRODDB" \
  --pipeline_name "camstar_wafer2assembly_onsz" \
  --pipeline_type "batch"
```

### Example 4: Oracle Only (No JSONL)

Write only to Oracle database, omitting the JSONL file:

```bash
perl scripts/getCamstarWafer2AssemblyGenealogy.pl \
  --source_db SBN \
  --source_warehouse application_prd_wh \
  --source_schema ANALYTICSPRD.FCS \
  --start_hours 4 \
  --end_hours 0 \
  --out_gen ./output/gen \
  --archive_gen ./archive/gen \
  --out_trace ./output/trace \
  --archive_trace ./archive/trace \
  --logfile ./log/getCamstarWafer2AssemblyGenealogy_sbn.log \
  --benchmark_db_dsn LOTGPRD \
  --benchmark_db_user \
  --pipeline_name "camstar_wafer2assembly_sbn" \
  --pipeline_type "batch"
```

## Data Stored in Oracle

The following fields are inserted into the `pipeline_runs` table:

### Core Metrics
- `start_local`, `end_local`: Local timestamps
- `start_utc`, `end_utc`: UTC timestamps
- `elapsed_seconds`: Execution time in seconds
- `elapsed_human`: Human-readable elapsed time (e.g., "2h 15m 30s")
- `rowcount`: Total rows written (genealogy + trace)
- `rows_extracted`: Rows fetched from source database
- `rows_written`: Rows written to output files
- `total_files`: Number of output files generated

### File Tracking
- `output_file_gen`: Genealogy output file path
- `output_files_gen`: JSON array of genealogy files (CLOB)
- `output_file_trace`: Trace output file path
- `output_files_trace`: JSON array of trace files (CLOB)
- `archived_gen_files`: JSON array of archived genealogy files (CLOB)
- `archived_trace_files`: JSON array of archived trace files (CLOB)

### Metadata (JSON CLOB)
```json
{
  "rows_fetched": 1234,
  "rows_kept": 1200,
  "rows_skipped": 34
}
```

### Benchmark (JSON CLOB)
Complete benchmark data including all metrics, file paths, and diagnostic counters.

### Pipeline Info
- `pipeline_name`: Unique pipeline identifier
- `script_name`: Script filename
- `pipeline_type`: Type (e.g., "batch", "streaming")
- `environment`: Environment (prod/qa/dev)
- `log_file`: Path to log file
- `pid`: Process ID
- `date_code`: Timestamp code for file naming

## Querying Benchmark Data

### Recent pipeline runs
```sql
SELECT pipeline_name, start_utc, elapsed_human, rowcount, total_files
FROM pipeline_runs
WHERE start_utc >= SYSTIMESTAMP - INTERVAL '7' DAY
ORDER BY start_utc DESC;
```

### Performance trends
```sql
SELECT pipeline_name, 
       TRUNC(start_utc) as run_date,
       AVG(elapsed_seconds) as avg_elapsed,
       AVG(rowcount) as avg_rows,
       COUNT(*) as run_count
FROM pipeline_runs
WHERE pipeline_name LIKE 'camstar_wafer2assembly%'
  AND start_utc >= SYSTIMESTAMP - INTERVAL '30' DAY
GROUP BY pipeline_name, TRUNC(start_utc)
ORDER BY run_date DESC;
```

### Diagnostic analysis (using JSON columns)
```sql
-- Oracle 12.2+ with JSON support
SELECT pipeline_name, start_utc,
       JSON_VALUE(metadata, '$.rows_fetched') as rows_fetched,
       JSON_VALUE(metadata, '$.rows_kept') as rows_kept,
       JSON_VALUE(metadata, '$.rows_skipped') as rows_skipped
FROM pipeline_runs
WHERE JSON_VALUE(metadata, '$.rows_skipped') > 0
ORDER BY start_utc DESC;
```

## Error Handling

The Oracle benchmark insertion is designed to be non-blocking:

1. If `BENCHMARK_DB_DSN` is not provided, Oracle insert is skipped silently
2. If credentials are missing, a warning is logged and execution continues
3. If database connection fails, a warning is logged and execution continues
4. If insert fails, transaction is rolled back and a warning is logged

The pipeline will always complete successfully even if Oracle benchmark logging fails.

## Security Best Practices

1. **Use environment variables** for credentials instead of command-line arguments
2. **Restrict file permissions** on password files: `chmod 600 /secure/oracle_password.txt`
3. **Use dedicated database user** with INSERT-only permissions on pipeline_runs table
4. **Rotate passwords regularly** and use strong passwords
5. **Consider Oracle Wallet** for credential management in production

## Troubleshooting

### Connection Issues

Check TNS configuration:
```bash
tnsping DWPRD
```

Test connection:
```bash
sqlplus user/pass@DWPRD
```

### Missing DBD::Oracle Module

Install the Perl Oracle driver:
```bash
cpan DBD::Oracle
# or
perl -MCPAN -e 'install DBD::Oracle'
```

### Check Logs

The script logs Oracle-related warnings to the main log file:
```bash
grep -i "benchmark\|oracle" ./log/getCamstarWafer2AssemblyGenealogy.log
```

## Migration from JSONL-only

To migrate existing pipelines:

1. Apply database migrations (create table + add JSON columns)
2. Add `--benchmark_db_dsn` to existing pipeline invocations
3. Set `BENCHMARK_DB_USER` and `BENCHMARK_DB_PASS` environment variables
4. Keep `--benchmark_log` for redundancy during transition period
5. Monitor logs for any Oracle-related warnings
6. Once stable, optionally remove `--benchmark_log` to use Oracle exclusively

## Related Files

- `scripts/getCamstarWafer2AssemblyGenealogy.pl` - Main script
- `pipeline-service-prod/sql/create_pipeline_runs.sql` - Table DDL
- `pipeline-service-prod/sql/migration_add_metadata_benchmark.sql` - JSON columns migration
- `scripts/getCamstarWafer2AssemblyGenealogy_oracle_benchmark_example.sh` - Usage examples
