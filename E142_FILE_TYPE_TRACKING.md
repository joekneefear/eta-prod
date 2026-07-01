# E142 File Type Tracking Implementation

**Date:** 2026-03-04  
**Feature:** Track E142 trace files by type (w2f, a2w, f2w, etc.)

## Overview

This implementation adds file type breakdown tracking for E142 trace extraction pipelines, allowing detailed monitoring of which types of trace files are generated per run.

## Changes Made

### 1. Perl Script Enhancement (`scripts/getSnowflakeE142ModuleTrace.pl`)

**Location:** Lines 700-720 (in `writeBenchmarkToOracle` subroutine)

**Added Logic:**
```perl
# Count files by type for E142 trace file categorization
my %file_type_counts = ();
my %file_type_rows = ();
foreach my $f (keys %out_files_info)
{
    my $base = basename($f);
    # Extract file type from extension (e.g., .w2f.gz -> w2f)
    if ($base =~ /\.(\w+)\.gz$/)
    {
        my $file_type = $1;
        $file_type_counts{$file_type} = ($file_type_counts{$file_type} || 0) + 1;
        $file_type_rows{$file_type} = ($file_type_rows{$file_type} || 0) + ($out_files_info{$f} || 0);
    }
}

# Add to metadata
my %metadata = (
    # ... existing fields ...
    file_type_counts => \%file_type_counts,
    file_type_rows => \%file_type_rows,
);
```

**What It Does:**
- Parses file extensions from generated trace files
- Counts number of files per type
- Sums row counts per type
- Stores in `metadata` JSON column in Oracle

### 2. Pipeline Service Models (`pipeline-service-prod/app/models.py`)

**Added Fields to `PipelineInfo`:**
```python
# Computed fields for E142 file type breakdown (extracted from metadata)
file_type_counts: Optional[dict] = Field(None, description="E142 trace file counts by type (w2f, a2w, f2w, etc.)")
file_type_rows: Optional[dict] = Field(None, description="E142 trace file row counts by type")
```

### 3. Utility Functions (`pipeline-service-prod/app/utils.py`)

**Added Functions:**
```python
def extract_file_type_data(metadata: Optional[dict]) -> tuple:
    """Extract E142 file type counts and rows from metadata."""
    if not metadata:
        return None, None
    
    file_type_counts = metadata.get('file_type_counts')
    file_type_rows = metadata.get('file_type_rows')
    
    return file_type_counts, file_type_rows


def enrich_pipeline_info(record: PipelineInfo) -> PipelineInfo:
    """Enrich PipelineInfo with computed fields from metadata."""
    if record.metadata:
        file_type_counts, file_type_rows = extract_file_type_data(record.metadata)
        if file_type_counts:
            record.file_type_counts = file_type_counts
        if file_type_rows:
            record.file_type_rows = file_type_rows
    
    return record
```

### 4. Repository Enhancement (`pipeline-service-prod/app/repository.py`)

**Updated `get_pipeline_info` methods:**
- JSONL repository: Enriches records before returning
- Oracle repository: Parses JSON CLOB fields and enriches records

### 5. New API Endpoint (`pipeline-service-prod/main.py`)

**Endpoint:** `GET /e142/file_types`

**Parameters:**
- `pipeline_name` (optional): Filter by E142 pipeline name
- `start_utc` (optional): Filter by start UTC
- `end_utc` (optional): Filter by end UTC
- `limit` (default: 100): Maximum records to return

**Response:**
```json
{
  "total_runs": 10,
  "file_types": {
    "w2f": {
      "total_files": 150,
      "total_rows": 87500,
      "runs_with_type": 10
    },
    "a2w": {
      "total_files": 25,
      "total_rows": 12300,
      "runs_with_type": 5
    },
    "f2w": {
      "total_files": 30,
      "total_rows": 15600,
      "runs_with_type": 6
    }
  },
  "runs": [
    {
      "pipeline_name": "E142_VN5_WAFER",
      "start_local": "2026-03-04T14:30:22",
      "date_code": "20260304_143022",
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

## File Type Reference

### Forward Traceability
- **w2f** = Wafer to Final (WAFER stage)
  - Traces from wafer → assembly → test
  - One file per wafer

### Backward Traceability
- **a2w** = Assembly to Wafer (DIEBOND stage)
- **f2w** = Final Test to Wafer (TEST stage)
- **s2w** = Singulation to Wafer (SINGULATION stage)
- **fa2w** = Frame Attach to Wafer (LEADFRAME_ATTACH stage)
- **id2w** = Internal2DID to Wafer (INTERNAL2DID stage)
- **c2w** = Case Screw to Wafer (CASESCREW_ATTACH stage)

All backward files trace from test/assembly → wafer, one file per backend lot.

## Usage Examples

### 1. Query E142 Pipeline with File Type Data

**API Request:**
```bash
curl "http://localhost:8000/v1/get_pipeline_info?pipeline_name=E142_VN5_WAFER&limit=5"
```

**Response includes:**
```json
{
  "total": 100,
  "count": 5,
  "results": [
    {
      "pipeline_name": "E142_VN5_WAFER",
      "start_local": "2026-03-04T14:30:22",
      "rowcount": 8750,
      "total_files": 15,
      "file_type_counts": {
        "w2f": 15
      },
      "file_type_rows": {
        "w2f": 8750
      },
      "metadata": {
        "rows_fetched": 8750,
        "rows_kept": 8750,
        "file_type_counts": {"w2f": 15},
        "file_type_rows": {"w2f": 8750}
      }
    }
  ]
}
```

### 2. Get Aggregated File Type Statistics

**API Request:**
```bash
curl "http://localhost:8000/e142/file_types?start_utc=2026-03-01T00:00:00Z&limit=50"
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
    },
    "f2w": {
      "total_files": 75,
      "total_rows": 39000,
      "runs_with_type": 15
    }
  },
  "runs": [...]
}
```

### 3. Oracle SQL Queries

#### Get File Type Counts from Metadata
```sql
SELECT 
  pipeline_name,
  start_local,
  total_files,
  JSON_VALUE(metadata, '$.file_type_counts.w2f') as w2f_count,
  JSON_VALUE(metadata, '$.file_type_counts.a2w') as a2w_count,
  JSON_VALUE(metadata, '$.file_type_counts.f2w') as f2w_count,
  JSON_VALUE(metadata, '$.file_type_counts.s2w') as s2w_count,
  JSON_VALUE(metadata, '$.file_type_counts.fa2w') as fa2w_count,
  JSON_VALUE(metadata, '$.file_type_counts.id2w') as id2w_count
FROM REFDB.PIPELINE_RUNS
WHERE pipeline_name LIKE 'E142%'
ORDER BY start_local DESC
FETCH FIRST 20 ROWS ONLY;
```

#### Get File Type Row Counts
```sql
SELECT 
  pipeline_name,
  start_local,
  rowcount as total_rows,
  JSON_VALUE(metadata, '$.file_type_rows.w2f') as w2f_rows,
  JSON_VALUE(metadata, '$.file_type_rows.a2w') as a2w_rows,
  JSON_VALUE(metadata, '$.file_type_rows.f2w') as f2w_rows
FROM REFDB.PIPELINE_RUNS
WHERE pipeline_name LIKE 'E142%'
  AND start_local > SYSTIMESTAMP - INTERVAL '7' DAY
ORDER BY start_local DESC;
```

#### Aggregate File Types Over Time
```sql
SELECT 
  TO_CHAR(start_local, 'YYYY-MM-DD') as run_date,
  COUNT(*) as total_runs,
  SUM(CAST(JSON_VALUE(metadata, '$.file_type_counts.w2f') AS NUMBER)) as total_w2f,
  SUM(CAST(JSON_VALUE(metadata, '$.file_type_counts.a2w') AS NUMBER)) as total_a2w,
  SUM(CAST(JSON_VALUE(metadata, '$.file_type_counts.f2w') AS NUMBER)) as total_f2w,
  SUM(CAST(JSON_VALUE(metadata, '$.file_type_rows.w2f') AS NUMBER)) as total_w2f_rows
FROM REFDB.PIPELINE_RUNS
WHERE pipeline_name LIKE 'E142%'
  AND start_local > SYSTIMESTAMP - INTERVAL '30' DAY
GROUP BY TO_CHAR(start_local, 'YYYY-MM-DD')
ORDER BY run_date DESC;
```

#### Find Runs with Specific File Types
```sql
SELECT 
  pipeline_name,
  start_local,
  total_files,
  metadata
FROM REFDB.PIPELINE_RUNS
WHERE pipeline_name LIKE 'E142%'
  AND JSON_EXISTS(metadata, '$.file_type_counts.fa2w')
ORDER BY start_local DESC;
```

## Data Structure

### Metadata Column Content (Example)
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
```
total_files = sum(file_type_counts.values())
rowcount = sum(file_type_rows.values())
```

## Testing

### 1. Test Perl Script Changes

```bash
cd scripts

# Run E142 extraction with Oracle benchmarking
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

# Check JSONL output
tail -1 ./log/benchmark.jsonl | jq '.metadata.file_type_counts'
```

### 2. Verify Oracle Insert

```sql
-- Check latest E142 run
SELECT 
  pipeline_name,
  start_local,
  total_files,
  JSON_VALUE(metadata, '$.file_type_counts') as file_types
FROM REFDB.PIPELINE_RUNS
WHERE pipeline_name = 'E142_VN5_WAFER'
ORDER BY start_local DESC
FETCH FIRST 1 ROW ONLY;
```

### 3. Test API Endpoints

```bash
# Start pipeline service
cd pipeline-service-prod
export PIPELINE_BACKEND=oracle
export ORACLE_DSN=DWPRD
export ORACLE_USER=refdb
export ORACLE_PASSWORD=br#^gox66312sdAB
uvicorn main:main_app --host 0.0.0.0 --port 8000

# Test file type endpoint
curl "http://localhost:8000/e142/file_types?limit=10" | jq

# Test pipeline info with file types
curl "http://localhost:8000/v1/get_pipeline_info?pipeline_name=E142_VN5_WAFER&limit=5" | jq '.results[0].file_type_counts'
```

## Benefits

1. **Detailed Tracking** - Know exactly which file types are generated per run
2. **Trend Analysis** - Monitor file type distribution over time
3. **Capacity Planning** - Understand storage needs by file type
4. **Troubleshooting** - Identify missing or unexpected file types
5. **Stage Monitoring** - Track which stages are producing files
6. **Facility Comparison** - Compare file type patterns across facilities

## Dashboard Visualization Ideas

1. **Stacked Bar Chart** - File types per day
2. **Pie Chart** - File type distribution (current month)
3. **Time Series** - File counts by type over time
4. **Heatmap** - File types by facility and stage
5. **Table** - Latest runs with file type breakdown

## Backward Compatibility

✅ **Fully backward compatible:**
- Existing records without `file_type_counts` return `null`
- API handles missing data gracefully
- No schema changes required (uses existing `metadata` column)
- JSONL and Oracle backends both supported

## Future Enhancements

1. **File Size Tracking** - Add file sizes per type
2. **Compression Ratios** - Track pre/post compression sizes
3. **Processing Time** - Time spent per file type
4. **Error Tracking** - Failed files by type
5. **Alerts** - Notify when expected file types are missing
