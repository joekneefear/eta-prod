# Metadata Flow Diagnostic Guide

## Overview
This document helps diagnose why E142/Camstar file type metadata might not be appearing in the dashboard.

## Complete Data Flow

### 1. Perl Scripts → Oracle Database
**E142 Script**: `eta_master/scripts/getSnowflakeE142ModuleTrace.pl`
**Camstar Script**: `eta_master/scripts/getCamstarWafer2AssemblyGenealogy.pl`

Both scripts:
- ✅ Build `file_type_counts` hash (e.g., `{w2f: 5, a2w: 3}`)
- ✅ Build `file_type_rows` hash (e.g., `{w2f: 1200, a2w: 850}`)
- ✅ Create metadata JSON with these fields
- ✅ Write to Oracle `pipeline_runs.metadata` column (CLOB)

**E142 Example** (lines 730-750):
```perl
my %metadata = (
    rows_fetched => $statsRef->{rows_fetched} || 0,
    rows_kept => $statsRef->{rows_kept} || 0,
    file_type_counts => \%file_type_counts,  # ← File type data here
    file_type_rows => \%file_type_rows,      # ← File type data here
);
my $metadataJson = JSON::PP->new->utf8->encode(\%metadata);
$sth->bind_param(':metadata', $metadataJson);  # ← Bound to Oracle
```

### 2. Oracle Database → Pipeline Service
**File**: `eta_master/pipeline-service-prod/app/repository.py`

**OraclePipelineRepository.get_pipeline_info()** (lines 305-324):
- ✅ Reads metadata CLOB from Oracle
- ✅ Parses JSON string to Python dict
- ✅ Creates PipelineInfo object with metadata
- ✅ Calls `enrich_pipeline_info()` to extract file type fields

**Code** (lines 305-324):
```python
# Parse JSON CLOB fields
if 'metadata' in record_dict and record_dict['metadata']:
    try:
        if hasattr(record_dict['metadata'], 'read'):
            record_dict['metadata'] = json.loads(record_dict['metadata'].read())
        elif isinstance(record_dict['metadata'], str):
            record_dict['metadata'] = json.loads(record_dict['metadata'])
    except:
        pass

rec = PipelineInfo(**record_dict)
# Enrich with computed fields
from .utils import enrich_pipeline_info
rec = enrich_pipeline_info(rec)  # ← Extracts file_type_counts/rows
results.append(rec)
```

### 3. Pipeline Service → Dashboard
**File**: `eta_master/pipeline-service-prod/app/utils.py`

**enrich_pipeline_info()** (lines 19-30):
```python
def enrich_pipeline_info(record: PipelineInfo) -> PipelineInfo:
    """Extract E142 file type breakdown if available."""
    if record.metadata:
        file_type_counts, file_type_rows = extract_file_type_data(record.metadata)
        if file_type_counts:
            record.file_type_counts = file_type_counts  # ← Populates model field
        if file_type_rows:
            record.file_type_rows = file_type_rows      # ← Populates model field
    return record
```

**API Response** includes:
- `file_type_counts`: `{w2f: 5, a2w: 3, ...}`
- `file_type_rows`: `{w2f: 1200, a2w: 850, ...}`

### 4. Dashboard Display
**File**: `pipeline-dashboard-rc11/src/components/FileTypeDonutChart.vue`

Expects API response with:
```typescript
{
  file_type_counts: { w2f: 5, a2w: 3 },
  file_type_rows: { w2f: 1200, a2w: 850 }
}
```

## Diagnostic Steps

### Step 1: Verify Perl Scripts Are Writing Metadata
**Check Oracle directly:**
```sql
SELECT 
    date_code,
    pipeline_name,
    DBMS_LOB.SUBSTR(metadata, 4000, 1) as metadata_preview
FROM pipeline_runs
WHERE pipeline_name LIKE 'E142%' OR pipeline_name LIKE 'Camstar%'
ORDER BY start_utc DESC
FETCH FIRST 5 ROWS ONLY;
```

**Expected output:**
```json
{
  "rows_fetched": 580,
  "rows_kept": 580,
  "file_type_counts": {"w2f": 1, "a2w": 2},
  "file_type_rows": {"w2f": 150, "a2w": 430}
}
```

**If metadata is NULL or empty:**
- ❌ Perl scripts are not running or failing before Oracle insert
- Check Perl script logs for errors
- Verify Oracle credentials in Perl scripts

### Step 2: Verify Pipeline Service Can Read Metadata
**Test API endpoint:**
```bash
curl "http://your-server:8080/pipeline-service/v1/get_pipeline_info?pipeline_name=E142&limit=1"
```

**Expected response:**
```json
{
  "results": [{
    "pipeline_name": "E142_trace_extraction",
    "metadata": {
      "file_type_counts": {"w2f": 1, "a2w": 2},
      "file_type_rows": {"w2f": 150, "a2w": 430}
    },
    "file_type_counts": {"w2f": 1, "a2w": 2},
    "file_type_rows": {"w2f": 150, "a2w": 430}
  }]
}
```

**If file_type_counts/file_type_rows are missing:**
- ❌ `enrich_pipeline_info()` is not extracting data correctly
- Check pipeline service logs for errors
- Verify `PIPELINE_BACKEND=oracle` environment variable

### Step 3: Verify Dashboard Receives Data
**Open browser console on dashboard:**
```javascript
// Check API response
fetch('http://your-server:8080/pipeline-service/v1/get_pipeline_info?limit=1')
  .then(r => r.json())
  .then(data => console.log(data.results[0].file_type_counts));
```

**Expected output:**
```javascript
{w2f: 1, a2w: 2, f2w: 1}
```

**If undefined:**
- ❌ API is not returning file type data
- Go back to Step 2

### Step 4: Verify Dashboard Components Render Data
**Check FileTypeDonutChart component:**
1. Open dashboard
2. Filter for E142 or Camstar pipelines
3. Open browser DevTools → Console
4. Look for errors related to Chart.js or FileTypeDonutChart

**Common issues:**
- Chart.js not installed: `npm install chart.js vue-chartjs`
- Data format mismatch: Check TypeScript types in `pipeline.ts`

## Common Issues & Solutions

### Issue 1: Metadata Column is NULL in Oracle
**Cause**: Perl scripts failing before Oracle insert

**Solution**:
1. Check Perl script logs
2. Verify Oracle credentials
3. Test Oracle connection manually
4. Check if error handling is swallowing errors

### Issue 2: Metadata Contains JSON but No file_type_counts
**Cause**: Perl scripts not building file type hashes

**Solution**:
1. Verify output files have correct extensions (`.w2f.gz`, `.a2w.gz`)
2. Check regex pattern in Perl: `/\.(\w+)\.gz$/`
3. Add debug logging to print `%file_type_counts` before JSON encoding

### Issue 3: API Returns metadata but Not file_type_counts
**Cause**: `enrich_pipeline_info()` not being called or failing

**Solution**:
1. Check pipeline service logs for errors
2. Verify `from .utils import enrich_pipeline_info` is not failing
3. Add logging in `enrich_pipeline_info()` to debug
4. Ensure Oracle repository is calling enrichment (line 324)

### Issue 4: Dashboard Shows No Charts
**Cause**: Frontend not receiving or rendering data

**Solution**:
1. Check browser console for errors
2. Verify API endpoint URL is correct
3. Check CORS settings if API is on different domain
4. Verify Chart.js dependencies are installed

## Quick Test Script

Create this test file to verify the complete flow:

**test_metadata_flow.py**:
```python
import os
import sys
sys.path.insert(0, 'eta_master/pipeline-service-prod')

# Set Oracle credentials
os.environ['PIPELINE_BACKEND'] = 'oracle'
os.environ['ORACLE_DSN'] = 'your_dsn'
os.environ['ORACLE_USER'] = 'your_user'
os.environ['ORACLE_PASSWORD'] = 'your_password'
os.environ['ORACLE_TABLE'] = 'pipeline_runs'

from app.repository import get_repository

repo = get_repository('oracle')
results = repo.get_pipeline_info(
    start_utc=None,
    end_utc=None,
    min_rowcount=None,
    max_rowcount=None,
    limit=5,
    offset=0,
    pipeline_name='E142%'
)

for rec in results:
    print(f"\nPipeline: {rec.pipeline_name}")
    print(f"Date Code: {rec.date_code}")
    print(f"Metadata: {rec.metadata}")
    print(f"File Type Counts: {rec.file_type_counts}")
    print(f"File Type Rows: {rec.file_type_rows}")
```

Run:
```bash
cd eta_master/pipeline-service-prod
python ../../test_metadata_flow.py
```

## Environment Variables Checklist

Ensure these are set in your pipeline service environment:

```bash
# Backend selection
PIPELINE_BACKEND=oracle

# Oracle connection
ORACLE_DSN=your_oracle_dsn
ORACLE_USER=your_username
ORACLE_PASSWORD=your_password
ORACLE_TABLE=pipeline_runs

# Optional: Column mapping if your DB columns differ
# ORACLE_COLUMN_MAP='{"start_utc": "START_UTC_COL"}'
```

## Next Steps

1. Run Step 1 (Oracle query) to verify data is being written
2. If Step 1 fails, check Perl script execution and logs
3. If Step 1 passes, run Step 2 (API test) to verify service reads data
4. If Step 2 fails, check pipeline service logs and environment variables
5. If Step 2 passes, run Step 3 (browser console) to verify dashboard receives data
6. If Step 3 fails, check CORS and network settings
7. If Step 3 passes, check Step 4 (component rendering) for frontend issues

## Contact Points

- **Perl Scripts**: Lines 730-830 in `getSnowflakeE142ModuleTrace.pl`
- **Oracle Repository**: Lines 305-324 in `repository.py`
- **Enrichment Logic**: Lines 8-30 in `utils.py`
- **Dashboard Chart**: `FileTypeDonutChart.vue`
- **TypeScript Types**: `pipeline.ts`
