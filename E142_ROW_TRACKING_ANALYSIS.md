# E142 Row Tracking Analysis

**Script:** `scripts/getSnowflakeE142ModuleTrace.pl`  
**Date:** 2026-03-04

## Summary

✅ **YES** - The script correctly inserts data into `rows_extracted`, `rows_written`, and `total_files` columns in Oracle.

## Data Flow & Logic

### 1. Row Counting Logic

The script tracks rows at multiple stages:

```perl
# Stage 1: Snowflake Query Processing
my $rowsFetched = 0;              # Total rows from Snowflake
my $rowsStatusSkipped = 0;        # Rows skipped due to status issues
my $rowsDroppedNoBackendLot = 0;  # Rows dropped (no backend lot)
my $rowsDroppedProdRegex = 0;     # Rows dropped (product regex filter)
my $rowsKept = 0;                 # Rows actually kept for output

# Stage 2: File Writing
my %out_files_info = ();          # Hash: filename => row_count
my $filesWritten = 0;             # Total files written

# Stage 3: Benchmark Aggregation
my $total_rows = 0;               # Sum of all rows across all files
my $total_files = 0;              # Count of output files
```

### 2. Row Tracking During Query Processing

**Location:** Lines 420-500 (while loop processing Snowflake results)

```perl
while( my $ref=$dwsth->fetchrow_hashref())
{
    $rowsFetched++;  # Count every row from Snowflake
    
    # ... processing logic ...
    
    if ( $status == 0 )  # Status check passed
    {
        # ... create output string ...
        
        if ( length($backendLot) > 0 && 
             not ( length($snowflakeProduct) == 0 && 
                   length($prodNotRegexp) > 0 && 
                   $backendProduct =~ $prodNotRegexp ))
        {
            $rowsKept++;  # Row passed all filters
            
            # Add to output data structures
            push(@{$backendLotData{$hashKey}}, $str);
            
            if ( $sourceStage eq "WAFER")
            {
                push(@{$fabTestLotData{$hashKey}{$waferHashKey}}, $str);
            }
        }
        else
        {
            # Track why rows were dropped
            if (length($backendLot) == 0)
                $rowsDroppedNoBackendLot++;
            elsif (...)
                $rowsDroppedProdRegex++;
        }
    }
    else
    {
        $rowsStatusSkipped++;  # Status check failed
    }
}
```

**Key Insight:** Only rows that pass ALL filters (`$rowsKept`) are written to files.

### 3. Row Counting During File Writing

#### For Non-WAFER Stages (DIEBOND, TEST, etc.)

**Location:** Lines 512-530

```perl
if ( $sourceStage ne "WAFER" )
{
    while( my ($key, $val) = each %backendLotData )
    {
        $fileName = ".../$key.$backwardExtensions{$sourceStage}";
        open OUT, ">$fileName";
        print OUT "$class53Header\n";  # Header line (NOT counted)
        
        $out_files_info{$fileName} = 0;  # Initialize counter
        push @csv_files, $fileName;
        
        @arr = @{$val};  # Get array of data rows for this file
        while( my ($i, $arrstr) = each @arr )
        {
            $out_files_info{$fileName}++;  # Increment per row
            print OUT "$arrstr\n";
        }
        close OUT;
        $filesWritten++;
    }
}
```

**Output Files:**
- Extension: `.a2w` (assembly to wafer), `.f2w` (final test to wafer), etc.
- One file per backend lot
- Format: `E142_{FACILITY}_{FLOW}-{STAGE}-{DATETIME}-{KEY}.{EXT}`

#### For WAFER Stage

**Location:** Lines 535-560

```perl
if ( $sourceStage eq "WAFER" )
{
    while( my ($srclot, $srclothash) = each %fabTestLotData )
    {
        while( my ($wfr, $val) = each %{$srclothash})
        {
            $fileName = ".../$wfr.$forwardExtensions{$sourceStage}";
            open OUT, ">$fileName";
            print OUT "$class53Header\n";  # Header line (NOT counted)
            
            $out_files_info{$fileName} = 0;  # Initialize counter
            push @csv_files, $fileName;
            
            @arr = @{$val};  # Get array of data rows for this wafer
            while( my ($i, $arrstr) = each @arr )
            {
                $out_files_info{$fileName}++;  # Increment per row
                print OUT "$arrstr\n";
            }
            close OUT;
            $filesWritten++;
        }
    }
}
```

**Output Files:**
- Extension: `.w2f` (wafer to final)
- One file per wafer
- Format: `E142_{FACILITY}_{FLOW}-WAFER-{DATETIME}-{WAFER_ID}.w2f`

**Important:** Header lines are NOT counted in `$out_files_info{$fileName}`.

### 4. Benchmark Data Aggregation

**Location:** Lines 585-605

```perl
# Build outputs arrays for benchmarking
my @output_files_trace = ();
my @out_files = ();
my $total_rows = 0;
my $total_files = 0;

foreach my $f (@csv_files)
{
    my $base = basename($f);
    my $final_path = "$outputTraceDir/" . $base . ".gz";
    push @output_files_trace, $final_path;
    
    my $rows = $out_files_info{$f} || 0;  # Get row count for this file
    $total_rows += $rows;                  # Accumulate total
    $total_files++;                        # Count files
    
    push @out_files, { path => $final_path, rows => $rows };
}

# Log total rows extracted and written
INFO("Rows Total Count: Extracted=$total_rows | Written=$total_rows | Files=$total_files");
```

### 5. Oracle Insert Values

**Location:** Lines 615-635

```perl
my %bench = (
    # ... timestamps ...
    rowcount       => $total_rows,        # Total rows across all files
    rows_extracted => $total_rows,        # Same as rowcount
    rows_written   => $total_rows,        # Same as rowcount
    total_files    => $total_files,       # Number of trace files
    output_files_trace => \@output_files_trace,  # Array of file paths
    out_files      => \@out_files,        # Array of {path, rows} objects
    
    # Diagnostic metadata (stored in METADATA column)
    rows_fetched   => $rowsFetched,       # From Snowflake
    rows_kept      => $rowsKept,          # Passed filters
    rows_dropped_status => $rowsStatusSkipped,
    rows_dropped_no_backend_lot => $rowsDroppedNoBackendLot,
    rows_dropped_prod_regex => $rowsDroppedProdRegex,
);
```

## Data Validation

### Relationship Between Counters

```
rowsFetched (from Snowflake)
    ├─ rowsStatusSkipped (status check failed)
    ├─ rowsDroppedNoBackendLot (no backend lot)
    ├─ rowsDroppedProdRegex (product regex filter)
    └─ rowsKept (passed all filters)
         └─ total_rows (written to files)
              └─ rows_extracted = rows_written = total_rows
```

**Validation Formula:**
```
rowsFetched = rowsStatusSkipped + rowsDroppedNoBackendLot + rowsDroppedProdRegex + rowsKept
rowsKept = total_rows = rows_extracted = rows_written
```

### Example Log Output

```
INFO: E142 extraction diagnostics: 
  fetched=580 
  kept=580 
  dropped_status=0 
  dropped_no_backend_lot=0 
  dropped_prod_regex=0 
  files_written=1 
  stage=WAFER 
  flow=B1T 
  view=ANALYTICSPRD.MFG.E142_VN5_B1T_EXENSIO_FAB2PUCK_RPT

INFO: Rows Total Count: Extracted=580 | Written=580 | Files=1
```

## Oracle Table Mapping

### Columns Populated

| Oracle Column | Perl Variable | Description |
|--------------|---------------|-------------|
| `ROWCOUNT` | `$total_rows` | Total data rows across all files |
| `ROWS_EXTRACTED` | `$total_rows` | Same as ROWCOUNT (all kept rows) |
| `ROWS_WRITTEN` | `$total_rows` | Same as ROWCOUNT (all kept rows) |
| `TOTAL_FILES` | `$total_files` | Number of trace files generated |
| `OUTPUT_FILES_TRACE` | `@output_files_trace` | JSON array of file paths |
| `OUT_FILES` | `@out_files` | JSON array of {path, rows} objects |
| `METADATA` | `%metadata` | JSON with diagnostic counters |
| `BENCHMARK` | `%bench` | JSON with full benchmark data |

### METADATA Column Content

```json
{
  "rows_fetched": 580,
  "rows_kept": 580,
  "rows_dropped_status": 0,
  "rows_dropped_no_backend_lot": 0,
  "rows_dropped_prod_regex": 0
}
```

### OUT_FILES Column Content

```json
[
  {
    "path": "/apps/exensio_data/trace/E142_VN5_B1T-WAFER-20260304_143022-VN5-K12345_01.w2f.gz",
    "rows": 580
  }
]
```

## File Types & Extensions

### Forward Extensions (WAFER stage)
```perl
my %forwardExtensions = ( "WAFER" => "w2f" );
```
- `w2f` = Wafer to Final (forward traceability)
- One file per wafer
- Traces from wafer → assembly → test

### Backward Extensions (Other stages)
```perl
my %backwardExtensions = ( 
    "DIEBOND"          => "a2w",   # Assembly to Wafer
    "SINGULATION"      => "s2w",   # Singulation to Wafer
    "LEADFRAME_ATTACH" => "fa2w",  # Frame Attach to Wafer
    "CASESCREW_ATTACH" => "c2w",   # Case Screw to Wafer
    "INTERNAL2DID"     => "id2w",  # Internal2DID to Wafer
    "TEST"             => "f2w"    # Final Test to Wafer
);
```
- Backward traceability files
- One file per backend lot
- Traces from test/assembly → wafer

## Trends & Verification

### Expected Behavior

1. **Normal Run (all rows pass filters):**
   ```
   rowsFetched = rowsKept = total_rows = rows_extracted = rows_written
   dropped_* = 0
   ```

2. **Run with Filters Active:**
   ```
   rowsFetched > rowsKept = total_rows
   dropped_* > 0
   ```

3. **No Data Run:**
   ```
   rowsFetched = 0
   total_rows = 0
   total_files = 0
   ```

### Verification Queries

#### Check Recent E142 Runs
```sql
SELECT 
  pipeline_name,
  start_local,
  rowcount,
  rows_extracted,
  rows_written,
  total_files,
  JSON_VALUE(metadata, '$.rows_fetched') as rows_fetched,
  JSON_VALUE(metadata, '$.rows_kept') as rows_kept
FROM REFDB.PIPELINE_RUNS
WHERE pipeline_name LIKE 'E142%'
ORDER BY start_local DESC
FETCH FIRST 10 ROWS ONLY;
```

#### Validate Row Counts Match
```sql
SELECT 
  pipeline_name,
  start_local,
  CASE 
    WHEN rowcount = rows_extracted 
     AND rowcount = rows_written 
     AND rowcount = JSON_VALUE(metadata, '$.rows_kept')
    THEN 'VALID'
    ELSE 'MISMATCH'
  END as validation_status,
  rowcount,
  rows_extracted,
  rows_written,
  JSON_VALUE(metadata, '$.rows_kept') as rows_kept
FROM REFDB.PIPELINE_RUNS
WHERE pipeline_name LIKE 'E142%'
  AND start_local > SYSTIMESTAMP - INTERVAL '7' DAY
ORDER BY start_local DESC;
```

#### Check File Details
```sql
SELECT 
  pipeline_name,
  start_local,
  total_files,
  JSON_QUERY(out_files, '$[*].path') as file_paths,
  JSON_QUERY(out_files, '$[*].rows') as file_row_counts
FROM REFDB.PIPELINE_RUNS
WHERE pipeline_name = 'E142_VN5_WAFER'
ORDER BY start_local DESC
FETCH FIRST 5 ROWS ONLY;
```

## Logic Assessment

### ✅ Correct Behaviors

1. **Row counting is accurate** - Increments per data row written (excludes header)
2. **File counting is accurate** - Counts each trace file generated
3. **Consistency maintained** - `rows_extracted = rows_written = total_rows`
4. **Diagnostic tracking** - Captures filter drops in metadata
5. **Per-file tracking** - `out_files` array shows rows per file

### ⚠️ Semantic Note

The naming might be slightly misleading:

- `rows_extracted` = rows kept after filtering (not raw Snowflake rows)
- `rows_written` = same as rows_extracted (always equal)
- True "extracted from Snowflake" count is in `metadata.rows_fetched`

**Recommendation:** This is acceptable because:
- The script's purpose is to produce trace files
- "Extracted" means "extracted for output" (post-filtering)
- Raw Snowflake count is preserved in `metadata.rows_fetched`
- Consistency is maintained across all three fields

## Conclusion

✅ **The script correctly populates Oracle columns:**

1. **`rows_extracted`** = Total data rows written to trace files (post-filtering)
2. **`rows_written`** = Same as rows_extracted (always equal)
3. **`total_files`** = Number of trace files generated (`.w2f`, `.a2w`, `.f2w`, etc.)
4. **`output_files_trace`** = JSON array of gzipped trace file paths
5. **`out_files`** = JSON array with per-file row counts

✅ **The logic is working as intended:**

- Counts only data rows (excludes headers)
- Tracks filtering at multiple stages
- Maintains consistency across metrics
- Provides detailed diagnostics in metadata
- Supports both forward (WAFER) and backward (other stages) traceability

✅ **Trends can be monitored via:**

- `rowcount` vs `metadata.rows_fetched` = filter effectiveness
- `total_files` = number of lots/wafers processed
- `out_files` array = distribution of rows across files
- Time series analysis of extraction volumes
