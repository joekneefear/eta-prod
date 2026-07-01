# E142 File Type Tracking - Implementation Summary

**Date:** 2026-03-04  
**Status:** ✅ Complete  
**Feature:** Track E142 trace files by type (w2f, a2w, f2w, s2w, fa2w, id2w, c2w)

## What Was Implemented

### 1. Perl Script Enhancement ✅
**File:** `scripts/getSnowflakeE142ModuleTrace.pl`

Added file type counting logic that:
- Parses file extensions from generated trace files
- Counts files per type (w2f, a2w, f2w, etc.)
- Sums row counts per type
- Stores in `metadata.file_type_counts` and `metadata.file_type_rows`

**No schema changes required** - uses existing `metadata` CLOB column.

### 2. Pipeline Service API ✅
**Files:** 
- `pipeline-service-prod/app/models.py`
- `pipeline-service-prod/app/utils.py`
- `pipeline-service-prod/app/repository.py`
- `pipeline-service-prod/main.py`

Added:
- `file_type_counts` and `file_type_rows` fields to `PipelineInfo` model
- `extract_file_type_data()` utility function
- `enrich_pipeline_info()` to populate computed fields
- New endpoint: `GET /e142/file_types` for aggregated statistics

## File Types Tracked

| Extension | Description | Stage | Traceability |
|-----------|-------------|-------|--------------|
| w2f | Wafer to Final | WAFER | Forward |
| a2w | Assembly to Wafer | DIEBOND | Backward |
| f2w | Final Test to Wafer | TEST | Backward |
| s2w | Singulation to Wafer | SINGULATION | Backward |
| fa2w | Frame Attach to Wafer | LEADFRAME_ATTACH | Backward |
| id2w | Internal2DID to Wafer | INTERNAL2DID | Backward |
| c2w | Case Screw to Wafer | CASESCREW_ATTACH | Backward |

## API Endpoints

### 1. Get Pipeline Info with File Types
```bash
GET /v1/get_pipeline_info?pipeline_name=E142_VN5_WAFER&limit=5
```

**Response includes:**
```json
{
  "results": [
    {
      "pipeline_name": "E142_VN5_WAFER",
      "total_files": 15,
      "file_type_counts": {
        "w2f": 15
      },
      "file_type_rows": {
        "w2f": 8750
      }
    }
  ]
}
```

### 2. Get Aggregated File Type Statistics
```bash
GET /e142/file_types?start_utc=2026-03-01T00:00:00Z&limit=50
```

**Response:**
```json
{
  "total_runs": 25,
  "file_types": {
    "w2f": {
      "total_files": 375,
      "total_rows": 218750,
      "runs_with_type": 25
    },
    "a2w": {
      "total_files": 50,
      "total_rows": 24600,
      "runs_with_type": 10
    }
  },
  "runs": [...]
}
```

## SQL Queries

### Get File Type Breakdown
```sql
SELECT 
  pipeline_name,
  start_local,
  total_files,
  JSON_VALUE(metadata, '$.file_type_counts.w2f') as w2f_count,
  JSON_VALUE(metadata, '$.file_type_counts.a2w') as a2w_count,
  JSON_VALUE(metadata, '$.file_type_counts.f2w') as f2w_count
FROM REFDB.PIPELINE_RUNS
WHERE pipeline_name LIKE 'E142%'
ORDER BY start_local DESC
FETCH FIRST 20 ROWS ONLY;
```

### Aggregate Over Time
```sql
SELECT 
  TO_CHAR(start_local, 'YYYY-MM-DD') as run_date,
  COUNT(*) as total_runs,
  SUM(CAST(JSON_VALUE(metadata, '$.file_type_counts.w2f') AS NUMBER)) as total_w2f,
  SUM(CAST(JSON_VALUE(metadata, '$.file_type_counts.a2w') AS NUMBER)) as total_a2w
FROM REFDB.PIPELINE_RUNS
WHERE pipeline_name LIKE 'E142%'
  AND start_local > SYSTIMESTAMP - INTERVAL '30' DAY
GROUP BY TO_CHAR(start_local, 'YYYY-MM-DD')
ORDER BY run_date DESC;
```

## Testing

### Run Unit Tests
```bash
cd pipeline-service-prod
python3 test_e142_file_types.py
```

### Test Perl Script
```bash
cd scripts
perl_db getSnowflakeE142ModuleTrace.pl \
  --source_odbc MART_SNOWFLAKE \
  --source_warehouse EXENSIO_WH \
  --source_schema ANALYTICSPRD.MFG \
  --view_name E142_VN5_B1T_EXENSIO_FAB2PUCK_RPT \
  --flow B1T \
  --stage WAFER \
  --out_trace /apps/exensio_data/trace/vn5 \
  --benchmark_log ./log/benchmark.jsonl \
  --benchmark_db_dsn DWPRD \
  --benchmark_db_user \
  --pipeline_name E142_VN5_WAFER \
  --max_hours 2

# Verify output
tail -1 ./log/benchmark.jsonl | jq '.metadata.file_type_counts'
```

### Test API
```bash
# Start service
cd pipeline-service-prod
export PIPELINE_BACKEND=oracle
export ORACLE_DSN=DWPRD
export ORACLE_USER=refdb
export ORACLE_PASSWORD=br#^gox66312sdAB
uvicorn main:main_app --host 0.0.0.0 --port 8000

# Test endpoints
curl "http://localhost:8000/e142/file_types?limit=10" | jq
curl "http://localhost:8000/v1/get_pipeline_info?pipeline_name=E142_VN5_WAFER&limit=5" | jq '.results[0].file_type_counts'
```

## Data Structure

### Metadata Column (Oracle CLOB)
```json
{
  "rows_fetched": 8750,
  "rows_kept": 8750,
  "rows_dropped_status": 0,
  "rows_dropped_no_backend_lot": 0,
  "rows_dropped_prod_regex": 0,
  "file_type_counts": {
    "w2f": 15,
    "a2w": 3,
    "f2w": 5
  },
  "file_type_rows": {
    "w2f": 8750,
    "a2w": 1200,
    "f2w": 2500
  }
}
```

### Validation
```python
total_files = sum(file_type_counts.values())  # Should equal total_files column
rowcount = sum(file_type_rows.values())       # Should equal rowcount column
```

## Benefits

1. ✅ **Detailed Tracking** - Know exactly which file types are generated
2. ✅ **Trend Analysis** - Monitor file type distribution over time
3. ✅ **Capacity Planning** - Understand storage needs by file type
4. ✅ **Troubleshooting** - Identify missing or unexpected file types
5. ✅ **Stage Monitoring** - Track which stages are producing files
6. ✅ **Facility Comparison** - Compare patterns across facilities

## Backward Compatibility

✅ **Fully backward compatible:**
- No schema changes (uses existing `metadata` column)
- Existing records without file type data return `null`
- API handles missing data gracefully
- Works with both JSONL and Oracle backends

## Files Modified

1. ✅ `scripts/getSnowflakeE142ModuleTrace.pl` - Added file type counting
2. ✅ `pipeline-service-prod/app/models.py` - Added computed fields
3. ✅ `pipeline-service-prod/app/utils.py` - Added extraction/enrichment functions
4. ✅ `pipeline-service-prod/app/repository.py` - Enhanced both repositories
5. ✅ `pipeline-service-prod/main.py` - Added `/e142/file_types` endpoint

## Files Created

1. ✅ `E142_FILE_TYPE_TRACKING.md` - Comprehensive documentation
2. ✅ `pipeline-service-prod/test_e142_file_types.py` - Unit tests
3. ✅ `E142_FILE_TYPE_IMPLEMENTATION_SUMMARY.md` - This file

## Next Steps

### Immediate
1. Deploy Perl script changes to production
2. Deploy pipeline-service changes
3. Run test extraction to verify data collection
4. Verify Oracle metadata contains file type data

### Future Enhancements
1. Dashboard visualization (charts, graphs)
2. File size tracking per type
3. Compression ratio tracking
4. Processing time per file type
5. Alerts for missing expected file types
6. Historical trend reports

## Deployment Checklist

- [ ] Backup current Perl script
- [ ] Deploy updated `getSnowflakeE142ModuleTrace.pl`
- [ ] Deploy updated pipeline-service code
- [ ] Restart pipeline-service
- [ ] Run test E142 extraction
- [ ] Verify Oracle insert with file type data
- [ ] Test API endpoints
- [ ] Monitor first production runs
- [ ] Update documentation/runbooks

## Support

For questions or issues:
1. Check `E142_FILE_TYPE_TRACKING.md` for detailed documentation
2. Run `test_e142_file_types.py` to verify functionality
3. Check Oracle `metadata` column for file type data
4. Review API response for `file_type_counts` field
