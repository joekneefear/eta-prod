# Camstar Wafer2Assembly File Type Tracking

**Date:** 2026-03-04  
**Script:** `getCamstarWafer2AssemblyGenealogy.pl`  
**Status:** ✅ Complete

## Overview

Added file type tracking to the Camstar Wafer2Assembly genealogy extraction script, similar to E142 implementation. This tracks the two types of trace files generated: a2w (Assembly to Wafer) and w2a (Wafer to Assembly).

## File Types Tracked

| Type | Description | Direction |
|------|-------------|-----------|
| a2w | Assembly to Wafer | Backward traceability |
| w2a | Wafer to Assembly | Forward traceability |

## Changes Made

### 1. Row Counting During File Generation

Added `%file_type_row_counts` hash to track rows written to each file:

```perl
my %file_type_row_counts = (); # Track rows per file type

# Initialize counter when creating new file
$file_type_row_counts{$traceLotFile} = 0;

# Increment counter when writing row
$file_type_row_counts{$traceLotFile}++;
```

### 2. File Type Statistics Calculation

Calculate file type counts and row totals after file generation:

```perl
my %file_type_counts = ();
my %file_type_rows = ();
foreach my $fileName (@csv_files)
{
	if ($fileName =~ /\.(\w+)\.csv$/)
	{
		my $file_type = $1;
		$file_type_counts{$file_type} = ($file_type_counts{$file_type} || 0) + 1;
		$file_type_rows{$file_type} = ($file_type_rows{$file_type} || 0) + ($file_type_row_counts{$fileName} || 0);
	}
}
```

### 3. Enhanced Logging

Added file type breakdown to INFO logs:

```perl
INFO("File Type Breakdown: a2w=".($ file_type_counts{a2w} || 0)." files (".($ file_type_rows{a2w} || 0)." rows), w2a=".($file_type_counts{w2a} || 0)." files (".($file_type_rows{w2a} || 0)." rows)");
```

### 4. Benchmark Metadata

Added file type data to benchmark stats:

```perl
file_type_counts => \%file_type_counts_stats,
file_type_rows => \%file_type_rows_stats,
```

### 5. Oracle Metadata Storage

Updated `writeBenchmarkToOracle` to include file type data in metadata JSON:

```perl
my %metadata = (
	rows_fetched => $statsRef->{rows_fetched} || 0,
	rows_kept => $statsRef->{rows_kept} || 0,
	rows_skipped => $statsRef->{rows_skipped} || 0,
	file_type_counts => \%file_type_counts,
	file_type_rows => \%file_type_rows,
);
```


## Example Output

### Log Output
```
INFO: Camstar Genealogy/Assembly diagnostics: fetched=580 kept=580 skipped=0 files_written=11
INFO: Rows Total Count: Extracted=580 | Written=1160 | Files=11
INFO: Rows Detailed: Genealogy=580 | Trace=580
INFO: File Type Breakdown: a2w=5 files (290 rows), w2a=5 files (290 rows)
```

### Benchmark JSONL
```json
{
  "pipeline_name": "getCamstarWafer2AssemblyGenealogy",
  "total_files": 11,
  "rows_extracted": 580,
  "rows_written": 1160,
  "file_type_counts": {
    "a2w": 5,
    "w2a": 5
  },
  "file_type_rows": {
    "a2w": 290,
    "w2a": 290
  },
  "metadata": {
    "rows_fetched": 580,
    "rows_kept": 580,
    "rows_skipped": 0,
    "file_type_counts": {"a2w": 5, "w2a": 5},
    "file_type_rows": {"a2w": 290, "w2a": 290}
  }
}
```

### Oracle Query
```sql
SELECT 
  pipeline_name,
  start_local,
  total_files,
  JSON_VALUE(metadata, '$.file_type_counts.a2w') as a2w_count,
  JSON_VALUE(metadata, '$.file_type_counts.w2a') as w2a_count,
  JSON_VALUE(metadata, '$.file_type_rows.a2w') as a2w_rows,
  JSON_VALUE(metadata, '$.file_type_rows.w2a') as w2a_rows
FROM REFDB.PIPELINE_RUNS
WHERE pipeline_name = 'getCamstarWafer2AssemblyGenealogy'
ORDER BY start_local DESC
FETCH FIRST 10 ROWS ONLY;
```

## Benefits

1. **Visibility** - Track which trace file types are generated
2. **Balance Verification** - Ensure a2w and w2a files are balanced
3. **Troubleshooting** - Identify missing file types
4. **Monitoring** - Track file generation patterns over time
5. **Dashboard Integration** - Display in pipeline dashboard

## Backward Compatibility

✅ Fully backward compatible:
- Uses existing `metadata` CLOB column
- No schema changes required
- Existing records without file type data return null
- Works with both JSONL and Oracle backends

## Testing

```bash
cd scripts

# Run Camstar extraction with Oracle benchmarking
perl_db getCamstarWafer2AssemblyGenealogy.pl \
  --source_db CEBU \
  --start_hours 24 \
  --end_hours 0 \
  --out_gen /apps/exensio_data/genealogy \
  --out_trace /apps/exensio_data/trace \
  --archive_gen /apps/exensio_data/archives-yms/genealogy \
  --archive_trace /apps/exensio_data/archives-yms/trace \
  --logfile ./log/camstar_cebu.log \
  --benchmark_log ./log/benchmark.jsonl \
  --benchmark_db_dsn DWPRD \
  --benchmark_db_user \
  --pipeline_name getCamstarWafer2AssemblyGenealogy_CEBU \
  --pipeline_type batch

# Verify JSONL output
tail -1 ./log/benchmark.jsonl | jq '.file_type_counts, .file_type_rows'

# Verify Oracle insert
sqlplus refdb/password@DWPRD <<EOF
SELECT JSON_VALUE(metadata, '$.file_type_counts') 
FROM pipeline_runs 
WHERE pipeline_name = 'getCamstarWafer2AssemblyGenealogy_CEBU'
ORDER BY start_local DESC 
FETCH FIRST 1 ROW ONLY;
EOF
```

## Dashboard Display

The pipeline dashboard will automatically display Camstar file type data:

- **Dashboard Card**: Shows aggregated a2w and w2a statistics
- **Details Modal**: Shows file type breakdown per run
- **File Type Labels**: 
  - a2w → "Assembly→Wafer"
  - w2a → "Wafer→Assembly"

## Files Modified

1. ✅ `scripts/getCamstarWafer2AssemblyGenealogy.pl` - Added file type tracking

## Related Documentation

- `E142_FILE_TYPE_TRACKING.md` - E142 implementation (reference)
- `E142_FILE_TYPE_IMPLEMENTATION_SUMMARY.md` - Implementation guide
- `pipeline-dashboard-rc11/E142_DASHBOARD_INTEGRATION.md` - Dashboard integration

