# Oracle Integration Status Report

**Date:** 2026-03-04  
**System:** Pipeline Service & E142 Extraction Scripts

## Summary

✅ **YES** - The system is now configured to use Oracle as the primary data source for pipeline benchmarking.

## Oracle Table Schema Alignment

### Current Oracle Table: `PIPELINE_RUNS`

The table schema **MATCHES** the application models with all required fields:

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| ID | NUMBER | No | Auto-generated (IDENTITY) |
| START_LOCAL | TIMESTAMP(6) WITH TIME ZONE | No | ✓ Aligned |
| END_LOCAL | TIMESTAMP(6) WITH TIME ZONE | No | ✓ Aligned |
| START_UTC | TIMESTAMP(6) WITH TIME ZONE | No | ✓ Aligned |
| END_UTC | TIMESTAMP(6) WITH TIME ZONE | No | ✓ Aligned |
| ELAPSED_SECONDS | NUMBER(12,3) | No | ✓ Aligned |
| ELAPSED_HUMAN | VARCHAR2(256) | No | ✓ Aligned |
| OUTPUT_FILE | VARCHAR2(1024) | Yes | ✓ Made nullable |
| ROWCOUNT | NUMBER(12,0) | No | ✓ Aligned |
| LOG_FILE | VARCHAR2(1024) | No | ✓ Aligned |
| PID | NUMBER(10,0) | No | ✓ Aligned |
| DATE_CODE | VARCHAR2(64) | No | ✓ Aligned |
| PIPELINE_NAME | VARCHAR2(255) | Yes | ✓ Aligned |
| SCRIPT_NAME | VARCHAR2(255) | Yes | ✓ Aligned |
| PIPELINE_TYPE | VARCHAR2(100) | Yes | ✓ Aligned |
| ENVIRONMENT | VARCHAR2(50) | Yes | ✓ Aligned |
| ARCHIVED_FILE | VARCHAR2(1024) | Yes | ✓ Aligned |
| OUTPUT_FILE_GEN | VARCHAR2(1024) | Yes | ✓ Aligned |
| OUTPUT_FILES_GEN | CLOB | Yes | ✓ Aligned |
| OUTPUT_FILE_TRACE | VARCHAR2(1024) | Yes | ✓ Aligned |
| OUTPUT_FILES_TRACE | CLOB | Yes | ✓ Aligned |
| ARCHIVED_GEN_FILES | CLOB | Yes | ✓ Aligned |
| ARCHIVED_TRACE_FILES | CLOB | Yes | ✓ Aligned |
| ROWS_EXTRACTED | NUMBER(12,0) | Yes | ✓ Aligned |
| ROWS_WRITTEN | NUMBER(12,0) | Yes | ✓ Aligned |
| TOTAL_FILES | NUMBER(5,0) | Yes | ✓ Aligned |
| OUT_FILES | CLOB | Yes | ✓ Aligned |
| METADATA | CLOB | Yes | ✓ Added via migration |
| BENCHMARK | CLOB | Yes | ✓ Added via migration |
| CREATED_AT | TIMESTAMP(6) WITH TIME ZONE | No | Auto-generated |

### Key Updates Applied

1. **OUTPUT_FILE made nullable** - Supports multi-file outputs where `output_file` is "N/A"
2. **METADATA & BENCHMARK columns added** - Extensible CLOB fields for script diagnostics
3. **Multi-output tracking** - Separate fields for genealogy vs trace files
4. **Row count metrics** - Detailed tracking of extracted/written rows

## Integration Points

### 1. Perl Scripts (Data Producers)

**File:** `scripts/getSnowflakeE142ModuleTrace.pl`

✅ **Configured to write to Oracle:**
```perl
# Command-line options
--benchmark_db_dsn {oracle-dsn}
--benchmark_db_user [{user}]      # Optional, defaults to 'refdb'
--benchmark_db_pass [{password}]

# Writes benchmark data to Oracle via writeBenchmarkToOracle()
```

**Features:**
- Writes JSONL benchmark logs (backward compatible)
- **Simultaneously writes to Oracle** when DSN provided
- Serializes arrays/objects to JSON for CLOB columns
- Handles timestamp conversion for Oracle TIMESTAMP WITH TIME ZONE
- Default credentials: `refdb` / `br#^gox66312sdAB`

**Example Usage:**
```bash
perl_db getSnowflakeE142ModuleTrace.pl \
  --source_odbc MART_SNOWFLAKE \
  --source_warehouse EXENSIO_WH \
  --source_schema ANALYTICSPRD.MFG \
  --view_name E142_VN5_B1T_EXENSIO_FAB2PUCK_RPT \
  --flow B1T \
  --stage WAFER \
  --out_trace /apps/exensio_data/trace \
  --benchmark_log ./log/benchmark.jsonl \
  --benchmark_db_dsn DWPRD \
  --benchmark_db_user
```

### 2. Pipeline Service (Data Consumer)

**File:** `pipeline-service-prod/main.py`

✅ **Configured to read from Oracle:**
```bash
# Environment variables
export PIPELINE_BACKEND=oracle
export ORACLE_DSN=DWPRD
export ORACLE_USER=refdb
export ORACLE_PASSWORD=br#^gox66312sdAB
export ORACLE_TABLE=PIPELINE_RUNS
```

**Repository:** `pipeline-service-prod/app/repository.py`
- `OraclePipelineRepository` class handles all Oracle operations
- Uses `python-oracledb` driver (Thin mode)
- Supports:
  - SELECT with filtering (time range, pipeline name, row counts)
  - INSERT for new records
  - COUNT for pagination
  - Pipeline summaries with statistics

**API Endpoints:**
- `GET /v1/get_pipeline_info` - Query pipeline runs with filters
- `GET /v1/pipelines` - Get pipeline summaries
- `POST /v1/pipelines` - Insert new pipeline record
- `POST /v1/pipelines/raw` - Insert with parser plugins

### 3. Python Manager Script

**File:** `scripts/py/get_snowflake_e142_extraction_manager.py`

✅ **Passes Oracle credentials to Perl scripts:**
```python
# Config file: scripts/py/resources/e142_extraction_config.yaml
defaults:
  benchmark_db_dsn: "DWPRD"
  benchmark_db_user: true  # Uses default credentials
```

**Modes:**
- `cron` - Automated scheduled runs
- `manual` - One-time execution
- `historical` - Date range extraction
- `all` - All facilities

## Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. E142 Extraction (Perl Script)                           │
│    - Queries Snowflake for E142 data                       │
│    - Writes trace files (.w2f, .a2w, etc.)                 │
│    - Collects benchmark metrics                            │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ├──────────────────┬─────────────────────────┐
                 ▼                  ▼                         ▼
    ┌────────────────────┐  ┌──────────────────┐  ┌──────────────────┐
    │ JSONL File         │  │ Oracle DB        │  │ Log Files        │
    │ (backward compat)  │  │ PIPELINE_RUNS    │  │ (diagnostics)    │
    └────────────────────┘  └────────┬─────────┘  └──────────────────┘
                                     │
                                     │ Primary Source
                                     ▼
                         ┌────────────────────────┐
                         │ 2. Pipeline Service    │
                         │    (FastAPI)           │
                         │    - Reads from Oracle │
                         │    - Serves via REST   │
                         └────────┬───────────────┘
                                  │
                                  ▼
                         ┌────────────────────────┐
                         │ 3. Frontend/Clients    │
                         │    - Dashboard         │
                         │    - Monitoring        │
                         │    - Analytics         │
                         └────────────────────────┘
```

## Configuration Files

### 1. E142 Extraction Config
**File:** `scripts/py/resources/e142_extraction_config.yaml`

```yaml
defaults:
  source_odbc: "MART_SNOWFLAKE"
  source_warehouse: "EXENSIO_WH"
  source_schema: "ANALYTICSPRD.MFG"
  max_hours: 48
  get_product: true
  benchmark_log: "./log/benchmark.jsonl"
  benchmark_db_dsn: "DWPRD"
  benchmark_db_user: true  # Uses default credentials

facilities:
  VN5:
    facility_name: "Vietnam Facility 5"
    flow: "B1T"
    view_name: "E142_VN5_B1T_EXENSIO_FAB2PUCK_RPT"
    out_trace: "/apps/exensio_data/trace/vn5"
    stages:
      WAFER:
        enabled: true
        modfile: "./log/modfile_vn5_wafer.txt"
        cron_schedule: "0 */2 * * *"  # Every 2 hours
```

### 2. Pipeline Service Config
**Environment Variables:**

```bash
# Backend selection
export PIPELINE_BACKEND=oracle

# Oracle connection
export ORACLE_DSN=DWPRD
export ORACLE_USER=refdb
export ORACLE_PASSWORD=br#^gox66312sdAB
export ORACLE_TABLE=PIPELINE_RUNS

# Optional: Role for dependent objects
export SNOW_ROLE=EXENSIO_ROLE
```

## Verification Steps

### 1. Check Oracle Table Exists
```sql
SELECT COUNT(*) FROM REFDB.PIPELINE_RUNS;
```

### 2. Verify Recent Inserts
```sql
SELECT 
  pipeline_name,
  script_name,
  start_local,
  rowcount,
  total_files
FROM REFDB.PIPELINE_RUNS
WHERE pipeline_name LIKE 'E142%'
ORDER BY start_local DESC
FETCH FIRST 10 ROWS ONLY;
```

### 3. Test Pipeline Service
```bash
# Start service
cd pipeline-service-prod
export PIPELINE_BACKEND=oracle
export ORACLE_DSN=DWPRD
export ORACLE_USER=refdb
export ORACLE_PASSWORD=br#^gox66312sdAB
uvicorn main:main_app --host 0.0.0.0 --port 8000

# Query API
curl "http://localhost:8000/v1/get_pipeline_info?pipeline_name=E142_VN5_WAFER&limit=5"
```

### 4. Test E142 Extraction with Oracle
```bash
cd scripts
python3 py/get_snowflake_e142_extraction_manager.py manual \
  --facility VN5 \
  --stage WAFER \
  --max-hours 2

# Check Oracle for new record
sqlplus refdb/password@DWPRD <<EOF
SELECT pipeline_name, rowcount, total_files 
FROM PIPELINE_RUNS 
WHERE pipeline_name = 'E142_VN5_WAFER'
ORDER BY start_local DESC
FETCH FIRST 1 ROW ONLY;
EOF
```

## Migration Status

✅ **Completed:**
1. Oracle table schema created with all required columns
2. `OUTPUT_FILE` made nullable (supports multi-file outputs)
3. `METADATA` and `BENCHMARK` CLOB columns added
4. Perl scripts updated to write to Oracle
5. Pipeline service configured to read from Oracle
6. Python manager passes Oracle credentials
7. Indexes created for performance

✅ **Backward Compatibility:**
- JSONL files still written (dual-write mode)
- Can switch between backends via `PIPELINE_BACKEND` env var
- Existing JSONL data can be migrated to Oracle

## Recommendations

### For Production Deployment:

1. **Set environment variables** on all execution hosts:
   ```bash
   export PIPELINE_BACKEND=oracle
   export ORACLE_DSN=DWPRD
   export ORACLE_USER=refdb
   export ORACLE_PASSWORD=br#^gox66312sdAB
   ```

2. **Update cron jobs** to include Oracle parameters:
   ```bash
   0 */2 * * * . $HOME/.bashrc; python3 /path/to/get_snowflake_e142_extraction_manager.py cron --facility VN5 --stage WAFER
   ```

3. **Monitor Oracle table growth:**
   ```sql
   SELECT 
     TO_CHAR(start_local, 'YYYY-MM-DD') as run_date,
     COUNT(*) as runs,
     SUM(rowcount) as total_rows
   FROM PIPELINE_RUNS
   WHERE pipeline_name LIKE 'E142%'
   GROUP BY TO_CHAR(start_local, 'YYYY-MM-DD')
   ORDER BY run_date DESC;
   ```

4. **Set up table partitioning** (optional, for large volumes):
   ```sql
   -- Partition by month for better performance
   ALTER TABLE PIPELINE_RUNS 
   MODIFY PARTITION BY RANGE (start_local)
   INTERVAL (NUMTOYMINTERVAL(1, 'MONTH'));
   ```

## Conclusion

✅ **The system is fully configured to use Oracle as the primary data source.**

- Perl scripts write benchmark data to Oracle
- Pipeline service reads from Oracle
- Table schema matches application models
- All required fields are present and properly typed
- Backward compatibility maintained with JSONL files

**Next Steps:**
1. Deploy to production with Oracle environment variables
2. Monitor initial runs for any issues
3. Consider migrating historical JSONL data to Oracle
4. Set up automated table maintenance (archiving old records)
