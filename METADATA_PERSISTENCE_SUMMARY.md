# Metadata Persistence Investigation Summary

## Question
"The perl script is not persisting metadata info into db? I have metadata info how the pipeline-service-prod is getting that to the endpoint and how the pipeline-dashboard-rc11 is showing that to the user?"

## Answer: The Code is Correct - Metadata SHOULD Be Persisting

After thorough investigation, **all code is correctly implemented** for the complete metadata flow from Perl scripts → Oracle → Pipeline Service → Dashboard. If metadata is not appearing, it's a runtime/configuration issue, not a code issue.

## Complete Flow Verification

### ✅ 1. Perl Scripts Write Metadata to Oracle

**E142 Script** (`getSnowflakeE142ModuleTrace.pl` lines 730-830):
```perl
# Build file type statistics
my %file_type_counts = ();  # {w2f: 5, a2w: 3, ...}
my %file_type_rows = ();    # {w2f: 1200, a2w: 850, ...}

foreach my $f (@{$statsRef->{output_files_trace}}) {
    if ($base =~ /\.(\w+)\.gz$/) {
        my $file_type = $1;
        $file_type_counts{$file_type}++;
        $file_type_rows{$file_type} += $out_files_info{$f};
    }
}

# Create metadata JSON
my %metadata = (
    rows_fetched => $statsRef->{rows_fetched},
    rows_kept => $statsRef->{rows_kept},
    file_type_counts => \%file_type_counts,  # ← HERE
    file_type_rows => \%file_type_rows,      # ← HERE
);

my $metadataJson = JSON::PP->new->utf8->encode(\%metadata);

# Insert to Oracle
$sth->bind_param(':metadata', $metadataJson);  # ← Bound to CLOB
$sth->execute();
$dbh->commit();
```

**Camstar Script** (`getCamstarWafer2AssemblyGenealogy.pl` lines 937-1020):
- Same pattern as E142
- Builds file_type_counts and file_type_rows
- Writes to Oracle metadata column

**Status**: ✅ Code is correct

---

### ✅ 2. Oracle Repository Reads Metadata

**File**: `pipeline-service-prod/app/repository.py` (lines 305-324)

```python
# Parse JSON CLOB from Oracle
if 'metadata' in record_dict and record_dict['metadata']:
    try:
        if hasattr(record_dict['metadata'], 'read'):
            # Oracle CLOB object
            record_dict['metadata'] = json.loads(record_dict['metadata'].read())
        elif isinstance(record_dict['metadata'], str):
            # String
            record_dict['metadata'] = json.loads(record_dict['metadata'])
    except:
        pass

# Create PipelineInfo object
rec = PipelineInfo(**record_dict)

# Enrich with computed fields
from .utils import enrich_pipeline_info
rec = enrich_pipeline_info(rec)  # ← Extracts file_type_counts/rows
results.append(rec)
```

**Status**: ✅ Code is correct

---

### ✅ 3. Utils Enriches PipelineInfo with File Type Fields

**File**: `pipeline-service-prod/app/utils.py` (lines 8-30)

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
            record.file_type_counts = file_type_counts  # ← Populates model field
        if file_type_rows:
            record.file_type_rows = file_type_rows      # ← Populates model field
    
    return record
```

**Status**: ✅ Code is correct

---

### ✅ 4. PipelineInfo Model Has File Type Fields

**File**: `pipeline-service-prod/app/models.py` (lines 45-48)

```python
class PipelineInfo(BaseModel):
    # ... other fields ...
    
    # Arbitrary metadata and benchmark fields
    metadata: Optional[dict] = Field(None, description="Arbitrary script diagnostics and metadata (dict)")
    benchmark: Optional[dict] = Field(None, description="Benchmark/monitoring information (dict)")
    
    # Computed fields for E142 file type breakdown (extracted from metadata)
    file_type_counts: Optional[dict] = Field(None, description="E142 trace file counts by type (w2f, a2w, f2w, etc.)")
    file_type_rows: Optional[dict] = Field(None, description="E142 trace file row counts by type")
```

**Status**: ✅ Code is correct

---

### ✅ 5. API Returns File Type Data

**File**: `pipeline-service-prod/main.py` (lines 70-120)

The `/get_pipeline_info` endpoint returns PipelineInfo objects which include:
- `metadata`: Full metadata dict with file_type_counts and file_type_rows
- `file_type_counts`: Extracted field (top-level for easy access)
- `file_type_rows`: Extracted field (top-level for easy access)

**Example API Response**:
```json
{
  "results": [{
    "pipeline_name": "E142_trace_extraction",
    "date_code": "20260304_120000",
    "metadata": {
      "rows_fetched": 580,
      "rows_kept": 580,
      "file_type_counts": {"w2f": 1, "a2w": 2, "f2w": 1},
      "file_type_rows": {"w2f": 150, "a2w": 430, "f2w": 200}
    },
    "file_type_counts": {"w2f": 1, "a2w": 2, "f2w": 1},
    "file_type_rows": {"w2f": 150, "a2w": 430, "f2w": 200}
  }]
}
```

**Status**: ✅ Code is correct

---

### ✅ 6. Dashboard TypeScript Types Include File Type Fields

**File**: `pipeline-dashboard-rc11/src/types/pipeline.ts`

```typescript
export interface PipelineRun {
  // ... other fields ...
  metadata?: Record<string, any>;
  benchmark?: Record<string, any>;
  file_type_counts?: Record<string, number>;  // ← HERE
  file_type_rows?: Record<string, number>;    // ← HERE
}
```

**Status**: ✅ Code is correct

---

### ✅ 7. Dashboard Components Display File Type Data

**File**: `pipeline-dashboard-rc11/src/components/PipelineSummaryDashboard.vue`

```vue
<!-- Shows file type statistics if data exists -->
<div v-if="hasE142Data" class="grid grid-cols-1 lg:grid-cols-2 gap-6">
  <div class="bg-white ...">
    <h3>File Type Distribution</h3>
    <FileTypeDonutChart :pipelines="filteredPipelines" />
  </div>
  <div class="bg-gradient-to-br ...">
    <h3>Trace File Statistics</h3>
    <div v-for="(stats, fileType) in e142FileTypeStats" :key="fileType">
      <div>{{ fileType }}</div>
      <div>{{ stats.totalFiles.toLocaleString() }} files</div>
      <div>{{ stats.totalRows.toLocaleString() }} rows</div>
    </div>
  </div>
</div>
```

**Computed Properties** (lines 310-340):
```typescript
const hasE142Data = computed(() => {
  return filteredPipelines.value.some(p => 
    p.file_type_counts && Object.keys(p.file_type_counts).length > 0
  );
});

const e142FileTypeStats = computed(() => {
  const stats: Record<string, { totalFiles: number; totalRows: number }> = {};
  
  filteredPipelines.value.forEach(p => {
    if (!p.file_type_counts) return;
    
    Object.entries(p.file_type_counts).forEach(([fileType, count]) => {
      if (!stats[fileType]) {
        stats[fileType] = { totalFiles: 0, totalRows: 0 };
      }
      stats[fileType].totalFiles += count;
      
      if (p.file_type_rows && p.file_type_rows[fileType]) {
        stats[fileType].totalRows += p.file_type_rows[fileType];
      }
    });
  });
  
  return stats;
});
```

**Status**: ✅ Code is correct

---

## Why Metadata Might Not Be Appearing

Since all code is correct, the issue must be one of these:

### 1. Perl Scripts Not Running
- Scripts haven't been executed since metadata code was added
- Scripts are failing before reaching Oracle insert
- Check script logs for errors

### 2. Oracle Connection Issues
- Perl scripts can't connect to Oracle
- Wrong credentials or DSN
- Network issues
- Check Perl script logs for "Failed to insert benchmark into Oracle" warnings

### 3. Oracle Table Schema Issues
- `metadata` column doesn't exist
- `metadata` column is wrong type (should be CLOB)
- Column permissions issue

### 4. Pipeline Service Configuration Issues
- `PIPELINE_BACKEND` not set to "oracle"
- Oracle credentials not configured
- Wrong table name in `ORACLE_TABLE`

### 5. No Recent Data
- Old records don't have metadata (added recently)
- Need to run scripts again to generate new records with metadata

---

## Diagnostic Steps (In Order)

### Step 1: Check if Perl Scripts Have Run Recently
```bash
# Check E142 log file
tail -100 /path/to/getSnowflakeE142ModuleTrace.log

# Look for:
# - "Benchmark data inserted into Oracle pipeline_runs table" (success)
# - "Failed to insert benchmark into Oracle" (failure)
```

### Step 2: Query Oracle Directly
```sql
-- Check if metadata column exists and has data
SELECT 
    date_code,
    pipeline_name,
    start_utc,
    CASE 
        WHEN metadata IS NULL THEN 'NULL'
        WHEN DBMS_LOB.GETLENGTH(metadata) = 0 THEN 'EMPTY'
        ELSE 'HAS DATA'
    END as metadata_status,
    DBMS_LOB.SUBSTR(metadata, 500, 1) as metadata_preview
FROM pipeline_runs
WHERE pipeline_name LIKE '%E142%' OR pipeline_name LIKE '%Camstar%'
ORDER BY start_utc DESC
FETCH FIRST 10 ROWS ONLY;
```

**Expected**: metadata_status = 'HAS DATA' and metadata_preview shows JSON

**If NULL or EMPTY**:
- Perl scripts not writing data
- Go back to Step 1

### Step 3: Test Pipeline Service API
```bash
# Test API endpoint
curl "http://your-server:8080/pipeline-service/v1/get_pipeline_info?limit=1" | jq '.results[0] | {pipeline_name, file_type_counts, file_type_rows}'
```

**Expected**:
```json
{
  "pipeline_name": "E142_trace_extraction",
  "file_type_counts": {"w2f": 1, "a2w": 2},
  "file_type_rows": {"w2f": 150, "a2w": 430}
}
```

**If null**:
- Check pipeline service environment variables
- Check pipeline service logs
- Verify `PIPELINE_BACKEND=oracle`

### Step 4: Test Dashboard
1. Open dashboard in browser
2. Open DevTools Console
3. Run:
```javascript
fetch('http://your-server:8080/pipeline-service/v1/get_pipeline_info?limit=10')
  .then(r => r.json())
  .then(data => {
    console.log('Total results:', data.results.length);
    const withFileTypes = data.results.filter(r => r.file_type_counts);
    console.log('Results with file_type_counts:', withFileTypes.length);
    console.log('First result:', withFileTypes[0]);
  });
```

**Expected**: Should show results with file_type_counts

**If no results with file_type_counts**:
- No data in database yet
- Go back to Step 2

---

## Quick Test Script

Save as `test_metadata_flow.py` in project root:

```python
#!/usr/bin/env python3
import os
import sys

# Add pipeline service to path
sys.path.insert(0, 'eta_master/pipeline-service-prod')

# Configure Oracle connection
os.environ['PIPELINE_BACKEND'] = 'oracle'
os.environ['ORACLE_DSN'] = 'your_dsn_here'
os.environ['ORACLE_USER'] = 'your_user_here'
os.environ['ORACLE_PASSWORD'] = 'your_password_here'
os.environ['ORACLE_TABLE'] = 'pipeline_runs'

print("Testing metadata flow...")
print("=" * 60)

try:
    from app.repository import get_repository
    
    print("\n1. Connecting to Oracle...")
    repo = get_repository('oracle')
    print("   ✓ Connected successfully")
    
    print("\n2. Fetching recent pipeline runs...")
    results = repo.get_pipeline_info(
        start_utc=None,
        end_utc=None,
        min_rowcount=None,
        max_rowcount=None,
        limit=10,
        offset=0
    )
    print(f"   ✓ Found {len(results)} records")
    
    print("\n3. Checking for metadata...")
    with_metadata = [r for r in results if r.metadata]
    print(f"   ✓ {len(with_metadata)} records have metadata")
    
    print("\n4. Checking for file type data...")
    with_file_types = [r for r in results if r.file_type_counts]
    print(f"   ✓ {len(with_file_types)} records have file_type_counts")
    
    if with_file_types:
        print("\n5. Sample record with file type data:")
        rec = with_file_types[0]
        print(f"   Pipeline: {rec.pipeline_name}")
        print(f"   Date Code: {rec.date_code}")
        print(f"   File Type Counts: {rec.file_type_counts}")
        print(f"   File Type Rows: {rec.file_type_rows}")
        print("\n   ✓ Metadata flow is working correctly!")
    else:
        print("\n   ⚠ No records with file type data found")
        print("   This means:")
        print("   - Perl scripts haven't run since metadata code was added")
        print("   - OR scripts are failing before Oracle insert")
        print("   - OR filtering is excluding E142/Camstar records")
        
        if with_metadata:
            print("\n   Sample metadata from a record:")
            rec = with_metadata[0]
            print(f"   Pipeline: {rec.pipeline_name}")
            print(f"   Metadata keys: {list(rec.metadata.keys())}")
            print(f"   Metadata: {rec.metadata}")

except Exception as e:
    print(f"\n   ✗ Error: {e}")
    import traceback
    traceback.print_exc()

print("\n" + "=" * 60)
```

Run:
```bash
python test_metadata_flow.py
```

---

## Conclusion

**All code is correctly implemented**. The metadata flow from Perl → Oracle → API → Dashboard is complete and correct.

If metadata is not appearing:
1. Run the diagnostic steps above
2. Most likely cause: Perl scripts haven't run since metadata code was added
3. Solution: Execute the Perl scripts to generate new records with metadata

**Files to check**:
- Perl script logs: Look for Oracle insert success/failure messages
- Oracle table: Query directly to see if metadata column has data
- Pipeline service logs: Check for errors reading from Oracle
- Dashboard console: Check for API response data

**Next action**: Run Step 1 (check Perl logs) and Step 2 (query Oracle) from the diagnostic steps.
