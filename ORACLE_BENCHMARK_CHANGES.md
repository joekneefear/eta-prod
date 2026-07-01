# Oracle Benchmark Integration - Implementation Summary

## Overview

Updated `getCamstarWafer2AssemblyGenealogy.pl` to support writing benchmark/performance metrics to an Oracle database table in addition to the existing JSONL file format.

## Changes Made

### 1. Script Modifications (`scripts/getCamstarWafer2AssemblyGenealogy.pl`)

#### New Command-Line Options
- `--benchmark_db_dsn`: Oracle DSN (TNS name or connection string)
- `--benchmark_db_user`: Database username (optional value; if passed without value, uses default "refdb")
- `--benchmark_db_pass`: Database password (optional value; if passed without value, uses default "br#^gox66312sdAB")

#### Default Credentials Support
- When `--benchmark_db_user` is passed without a value, the script automatically uses:
  - Username: `refdb`
  - Password: `br#^gox66312sdAB`
- This simplifies configuration for standard deployments

#### New Environment Variables Support
- `BENCHMARK_DB_USER`: Database username
- `BENCHMARK_DB_PASS`: Database password

#### New Subroutine: `writeBenchmarkToOracle()`
- Connects to Oracle database using DBI
- Serializes complex data structures (arrays) to JSON for CLOB columns
- Inserts benchmark data into `pipeline_runs` table
- Handles errors gracefully (non-blocking)
- Commits transaction on success, rolls back on failure

#### Modified Benchmark Logging Section
- Calls `writeBenchmarkToOracle()` after `writeBenchmark()` if Oracle credentials provided
- Maintains backward compatibility (JSONL-only mode still works)

### 2. Documentation Created

#### `docs/oracle_benchmark_integration.md`
Comprehensive documentation covering:
- Features and benefits
- Database setup instructions
- Configuration options
- Usage examples
- Data schema details
- Query examples
- Error handling
- Security best practices
- Troubleshooting guide
- Migration instructions

#### `scripts/getCamstarWafer2AssemblyGenealogy_oracle_benchmark_example.sh`
Executable shell script with three complete examples:
- Example 1: JSONL + Oracle (dual persistence)
- Example 2: Oracle only
- Example 3: TNS name with environment variables

#### `scripts/ORACLE_BENCHMARK_QUICKSTART.txt`
Quick reference card with:
- Command-line options summary
- Environment variables
- Quick examples
- Prerequisites checklist
- Behavior notes
- Security tips
- Troubleshooting commands
- Query examples

### 3. Database Schema (Already Provided)

#### `pipeline-service-prod/sql/create_pipeline_runs.sql`
- Table structure with all required columns
- Indexes for performance
- Support for both Oracle 12c+ (IDENTITY) and older versions (SEQUENCE)

#### `pipeline-service-prod/sql/migration_add_metadata_benchmark.sql`
- Adds `metadata` and `benchmark` CLOB columns
- Includes JSON validation constraints for Oracle 12.2+
- Provides backfill guidance

## Key Features

### 1. Dual Persistence
- Write to both JSONL file and Oracle database simultaneously
- Provides redundancy and flexibility

### 2. Configurable Credentials
- Support for environment variables (recommended for security)
- Support for command-line arguments (for testing)
- Automatic fallback to environment variables

### 3. Non-Blocking Design
- Oracle insert failures don't stop pipeline execution
- Warnings logged for troubleshooting
- Pipeline always completes successfully

### 4. Rich Metadata Storage
- Diagnostic counters (rows_fetched, rows_kept, rows_skipped)
- File tracking (output and archived files)
- JSON serialization for complex data structures
- Extensible metadata and benchmark JSON columns

### 5. Flexible Connection
- Supports TNS names (e.g., "DWPRD", "LOTGPRD")
- Supports full connection strings (e.g., "//host:1521/service")
- Compatible with existing Oracle infrastructure

## Data Stored in Oracle

### Core Metrics
- Timestamps (local and UTC)
- Elapsed time (seconds and human-readable)
- Row counts (extracted, written, total)
- File counts

### File Tracking
- Output file paths (genealogy and trace)
- Archived file paths
- Multiple files stored as JSON arrays in CLOB columns

### Diagnostic Counters
- `rows_fetched`: Rows retrieved from source database
- `rows_kept`: Rows successfully processed
- `rows_skipped`: Rows that failed validation

### Pipeline Metadata
- Pipeline name and type
- Script name
- Environment (prod/qa/dev)
- Process ID
- Log file path
- Date code

## Backward Compatibility

✅ Fully backward compatible:
- Existing pipelines continue to work without changes
- JSONL-only mode still supported
- No breaking changes to existing functionality
- New options are optional

## Security Considerations

1. **Environment Variables**: Recommended for credentials
2. **File Permissions**: Restrict password files to 600
3. **Dedicated User**: Use INSERT-only database user
4. **Password Rotation**: Regular password updates
5. **Oracle Wallet**: Consider for production environments

## Usage Patterns

### Pattern 1: Default Credentials (Simplest - Recommended)
1. Pass `--benchmark_db_dsn` with TNS name
2. Pass `--benchmark_db_user` without a value
3. Script uses built-in credentials (refdb/br#^gox66312sdAB)
4. Optionally keep `--benchmark_log` for dual persistence

### Pattern 2: Custom Credentials via Environment Variables
1. Set `BENCHMARK_DB_USER` and `BENCHMARK_DB_PASS` environment variables
2. Pass `--benchmark_db_dsn` with TNS name
3. Script uses environment variable credentials
4. Better security than command-line arguments

### Pattern 3: Custom Credentials via Command Line
1. Pass `--benchmark_db_dsn` with TNS name
2. Pass `--benchmark_db_user "username"`
3. Pass `--benchmark_db_pass "password"`
4. Less secure (visible in process list)

### Pattern 4: JSONL-Only (Existing Behavior)
1. Keep `--benchmark_log` option
2. Don't add Oracle options
3. No changes to existing behavior

## Testing Checklist

- [ ] Database table created with correct schema
- [ ] Migration applied for metadata/benchmark columns
- [ ] DBD::Oracle Perl module installed
- [ ] TNS configuration tested (tnsping)
- [ ] Database credentials verified (sqlplus)
- [ ] Test run with JSONL + Oracle
- [ ] Test run with Oracle only
- [ ] Test run with JSONL only (backward compatibility)
- [ ] Verify data in pipeline_runs table
- [ ] Test error handling (invalid credentials)
- [ ] Test error handling (connection failure)
- [ ] Verify non-blocking behavior
- [ ] Check log files for warnings

## Query Examples

### Recent Pipeline Runs
```sql
SELECT pipeline_name, start_utc, elapsed_human, rowcount, total_files
FROM pipeline_runs
WHERE start_utc >= SYSTIMESTAMP - INTERVAL '7' DAY
ORDER BY start_utc DESC;
```

### Performance Trends
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

### Diagnostic Analysis
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

## Files Modified/Created

### Modified
- `scripts/getCamstarWafer2AssemblyGenealogy.pl`

### Created
- `docs/oracle_benchmark_integration.md`
- `scripts/getCamstarWafer2AssemblyGenealogy_oracle_benchmark_example.sh`
- `scripts/ORACLE_BENCHMARK_QUICKSTART.txt`
- `ORACLE_BENCHMARK_CHANGES.md` (this file)

### Referenced (Already Existed)
- `pipeline-service-prod/sql/create_pipeline_runs.sql`
- `pipeline-service-prod/sql/migration_add_metadata_benchmark.sql`

## Next Steps

1. **Database Setup**: Run DDL and migration scripts
2. **Test Environment**: Test in dev/qa environment first
3. **Credentials**: Set up environment variables or secure password storage
4. **Pilot Run**: Test with one pipeline
5. **Monitor**: Check logs and database for successful inserts
6. **Rollout**: Gradually add to other pipelines
7. **Documentation**: Update team runbooks and procedures

## Support

For questions or issues:
1. Check `docs/oracle_benchmark_integration.md` for detailed documentation
2. Review `scripts/ORACLE_BENCHMARK_QUICKSTART.txt` for quick reference
3. Examine log files for warnings and errors
4. Test database connectivity with `tnsping` and `sqlplus`
5. Verify DBD::Oracle module installation

## Benefits

1. **Centralized Monitoring**: All pipeline metrics in one database
2. **Historical Analysis**: Query trends and performance over time
3. **Alerting**: Build alerts on pipeline failures or performance degradation
4. **Reporting**: Generate reports and dashboards from database
5. **Troubleshooting**: Rich diagnostic data for debugging
6. **Scalability**: Database handles large volumes better than flat files
7. **Integration**: Easy integration with monitoring and BI tools
