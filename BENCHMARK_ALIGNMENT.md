# Benchmark JSONL Output Alignment

## Overview
Three scripts (`n_getSnowflakeE142ModuleTrace.pl`, `n_getCamstarWafer2AssemblyGenealogy.pl`, and `refdata_extract.py`) now emit aligned benchmark JSONL logs compatible with `pipeline-service-prod/app/models.py`.

## Standardized Benchmark Fields

All scripts now log these core fields:

### Timing Fields (Required)
- `start_local` - Start time in local timezone (format: `YYYY-MM-DD HH:MM:SS`)
- `end_local` - End time in local timezone
- `start_utc` - Start time in UTC (format: `YYYY-MM-DDTHH:MM:SSZ`)
- `end_utc` - End time in UTC
- `elapsed_seconds` - Duration in seconds (float, 3 decimal places)
- `elapsed_human` - Human-readable duration (format: `XmYs` or `Xh Ym Zs`)

### Identity Fields (Required)
- `pid` - Process ID
- `date_code` - Unique date code identifier (format: `YYYYMMDD_HHMMSS`)
- `log_file` - Path to log file
- `pipeline_name` - Name of the pipeline
- `script_name` - Name of the script file
- `pipeline_type` - Type of pipeline (batch, streaming, ml)
- `environment` - Environment (prod, dev, test, qa)

### Data Fields (Required)
- `output_file` - Primary output file path
- `rowcount` - Total rows processed (rowcount = rows_extracted + rows_written)
- **`rows_extracted`** - Number of rows from source database
- **`rows_written`** - Number of rows written to output files
- **`total_files`** - Number of output files generated

### File Fields (Optional but Recommended)
- `archived_file` - Path to archived file (single file case)
- `output_file_gen` - Primary genealogy output file
- `output_files_gen` - Array of genealogy output files
- `output_file_trace` - Primary trace output file
- `output_files_trace` - Array of trace output files
- `archived_gen_files` - Array of archived genealogy files
- `archived_trace_files` - Array of archived trace files
- `out_files` - Array of objects with `{path, rows}` structure

### Diagnostics Fields (Script-Specific, Optional)
These fields explain data filtering and processing outcomes:

#### E142 Module Trace
```perl
rows_fetched => $rowsFetched                           # Rows from Snowflake
rows_kept => $rowsKept                                 # Rows passing all filters
rows_dropped_status => $rowsStatusSkipped              # Rows with status != "PASS"
rows_dropped_no_backend_lot => $rowsDroppedNoBackendLot # Rows with missing backend lot
rows_dropped_prod_regex => $rowsDroppedProdRegex       # Rows matching --prod_not_regexp
```

#### Camstar Genealogy/Assembly
```perl
rows_fetched => $rowsFetched                           # Rows from Camstar database
rows_kept => $rowsKept                                 # Rows with valid wafer ID and fab source lot
rows_skipped => $rowsSkipped                           # Rows that failed validation
```

#### Refdata Extract (Python)
- Uses `rows_extracted = rowcount` (equivalent to E142's `rows_fetched`)
- Uses `rows_written = rowcount` (no filtering, all rows are kept)
- Optional metadata: `source_name`, `output_name`

---

## Script-Specific Details

### 1. n_getSnowflakeE142ModuleTrace.pl

**Location:** `c:\Users\fg8n8x\Desktop\eta\eta_1_15\eta_master\scripts\n_getSnowflakeE142ModuleTrace.pl`

**Benchmark Emission:**
- Lines 603-629: Build `%bench` hash with all fields
- Calls `writeBenchmark()` function which appends JSONL to `$hOptions{BENCHMARK_LOG}`

**Unique Diagnostics:**
- Tracks reason for each dropped row (status=FAIL, no backend lot, product regex match)
- These counters help diagnose no-output runs when `E142 extraction diagnostics` message shows zero `rows_kept`

**Output Files:**
- Multiple trace files per wafer (WAFER stage) or per backend lot (other stages)
- Each file tracked with row count in `@out_files` array

---

### 2. n_getCamstarWafer2AssemblyGenealogy.pl

**Location:** `c:\Users\fg8n8x\Desktop\eta\eta_1_15\eta_master\scripts\n_getCamstarWafer2AssemblyGenealogy.pl`

**Benchmark Emission:**
- Lines 716-790: Build `%stats` hash with aligned fields
- Calls `writeBenchmark()` with `%stats` reference

**Diagnostics Added (NEW):**
- `rows_fetched` - Campstar query results
- `rows_kept` - Records with valid exensioWaferID and fabSourceLot
- `rows_skipped` - Records failing validation (empty wafer ID, etc.)
- Logged via: `INFO("Camstar Genealogy/Assembly diagnostics: fetched=... kept=... skipped=... files_written=...")`

**Output Files:**
- One genealogy file (Assembly2Wafer)
- Multiple trace files (one per Assembly lot for A2W, one per fab source lot for W2A)
- Total files = trace count + 1 (genealogy)

---

### 3. refdata_extract.py

**Location:** `c:\Users\fg8n8x\Desktop\eta\eta_1_15\eta_master\scripts\refdata\refdata_extract.py`

**Benchmark Emission:**
- Lines 823-844: Build `stats` dict with aligned fields
- Calls `log_benchmark_jsonl()` which appends JSON line to `benchmark.jsonl`

**Fields Aligned (NEW):**
- `rows_extracted` = `rowcount` (rows selected from query)
- `rows_written` = `rowcount` (single output file, all rows written)
- `total_files` = 1 (always single output per refdata run)

**Output Files:**
- Single output file per refdata_extract invocation
- Optional archiving with gzip compression

---

## Pydantic Model Compatibility

All benchmark fields map to `pipeline-service-prod/app/models.py`:

```python
class PipelineInfo(BaseModel):
    # Core timing
    start_local: datetime
    end_local: datetime
    start_utc: datetime
    end_utc: datetime
    elapsed_seconds: float
    elapsed_human: str
    
    # Identity
    pid: int
    date_code: str
    log_file: str
    pipeline_name: Optional[str]
    script_name: Optional[str]
    pipeline_type: Optional[str]
    environment: Optional[str]
    
    # Data metrics
    output_file: Optional[str]
    rowcount: int
    rows_extracted: Optional[int]
    rows_written: Optional[int]
    total_files: Optional[int]
    
    # Multi-output
    output_file_gen: Optional[str]
    output_files_gen: Optional[List[str]]
    output_file_trace: Optional[str]
    output_files_trace: Optional[List[str]]
    archived_gen_files: Optional[List[str]]
    archived_trace_files: Optional[List[str]]
    out_files: Optional[List[dict]]
    
    # Extensible
    metadata: Optional[dict]  # Can hold diagnostic counters
    benchmark: Optional[dict] # Reserved for future use
```

---

## Testing

### E142 Diagnostics Example
```json
{
  "start_local": "2026-02-24 14:30:00",
  "end_local": "2026-02-24 14:35:15",
  "start_utc": "2026-02-24T21:30:00Z",
  "end_utc": "2026-02-24T21:35:15Z",
  "elapsed_seconds": 315.234,
  "elapsed_human": "5m 15s",
  "rows_extracted": 1500,
  "rows_kept": 1200,
  "rows_dropped_status": 200,
  "rows_dropped_no_backend_lot": 50,
  "rows_dropped_prod_regex": 50,
  "total_files": 5,
  "rows_written": 1200
}
```
**Insight:** E142 extracted 1500 rows but only kept 1200 (dropped 300 total: 200 bad status, 50 missing backend, 50 prod regex)

### Camstar Diagnostics Example
```json
{
  "start_local": "2026-02-24 05:00:00",
  "end_local": "2026-02-24 05:45:30",
  "rows_fetched": 850,
  "rows_kept": 800,
  "rows_skipped": 50,
  "total_files": 3,
  "rows_written": 800
}
```
**Insight:** Camstar fetched 850 records from database but 50 failed validation (likely invalid wafer IDs or fab source lots)

### Refdata Diagnostics Example
```json
{
  "start_local": "2026-02-24 01:30:00",
  "end_local": "2026-02-24 01:35:45",
  "rows_extracted": 5000,
  "rows_written": 5000,
  "total_files": 1,
  "archived_file": "/archive/refdata-20260224_013000.prod.gz"
}
```
**Insight:** Refdata extracted and wrote 5000 rows (no filtering) to single output file

---

## Usage in Pipeline Service

The `POST /v1/pipelines/raw` endpoint accepts benchmark JSONL lines:

```python
{
  "script_name": "n_getSnowflakeE142ModuleTrace.pl",
  "pipeline_name": "getSnowflakeE142ModuleTrace",
  "benchmark_line": "{...full benchmark JSON...}",
  "metadata_line": "{...diagnostic info...}"  # optional
}
```

The benchmarks are persisted in the database and accessible via:
- `GET /v1/get_pipeline_info` - Returns all records with embedded benchmark data
- Dashboard filters/visualizations can analyze rows_extracted/rows_written trends

---

## Best Practices

1. **Always populate `rows_extracted`** - Shows what the source returned
2. **Always populate `rows_written`** - Shows final output size
3. **Use diagnostic fields to explain gaps** - When rows_extracted > rows_written, explain why
4. **Use consistent naming** - `fetched` vs `extracted` should be used consistently (prefer `rows_extracted`)
5. **Test no-output cases** - Verify diagnostic counters help diagnose empty result sets
6. **Round elapsed_seconds to 3 decimals** - Consistent precision across scripts

---

## Recent Changes

**2026-02-25:**
- ✅ Added `rows_extracted` alignment to `refdata_extract.py` (lines 826-827)
- ✅ Added diagnostic counters to `n_getCamstarWafer2AssemblyGenealogy.pl` (rows_fetched, rows_kept, rows_skipped)
- ✅ Added INFO logging for Camstar diagnostics to match E142 pattern
- ✅ All three scripts now emit compatible benchmark JSONL with rows_extracted and rows_written
