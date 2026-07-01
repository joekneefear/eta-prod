# E142 Historical Mode - Detailed Guide

## Overview

Historical mode extracts E142 trace data for a specific date range, processing **one day at a time** with separate modfiles per day.

**Perfect for:** Backfilling data for Feb 10-20, 2026 (or any date range)

## How It Works

### Process Flow

```
For each day in date range:
  1. Create temporary modfile with day's timestamp
     Example: /tmp/modfile_VN5_WAFER_20260210.txt
     Content: "2026-02-10 00:00:00"
  
  2. Run Perl script with:
     --modfile /tmp/modfile_VN5_WAFER_20260210.txt
     --max_hours 24
  
  3. Perl script queries Snowflake:
     WHERE METAMODIFIEDDATE BETWEEN 
       TO_TIMESTAMP('2026-02-10 00:00:00', 'YYYY-MM-DD HH24:MI:SS.FF3')
       AND timestampadd(hour, 24, TO_TIMESTAMP('2026-02-10 00:00:00', ...))
  
  4. Generate trace files for that day
  
  5. Delete temporary modfile
  
  6. Move to next day
```

### Key Characteristics

✅ **One day at a time** - Sequential processing, not parallel  
✅ **Separate modfiles** - Each day gets its own temporary modfile  
✅ **24-hour windows** - Default extracts exactly one day of data  
✅ **Automatic cleanup** - Temporary modfiles deleted after each run  
✅ **Progress tracking** - Shows [X/Y] for each day  
✅ **Error resilience** - Continues to next day if one fails  
✅ **Summary report** - Final success/failure count  

## Basic Usage

### Syntax

```bash
python3 e142_extraction_manager.py historical \
  --facility {FACILITY} \
  --stage {STAGE} \
  --start-date {YYYY-MM-DD} \
  --end-date {YYYY-MM-DD} \
  [--max-hours {HOURS}]
```

### Parameters

- `--facility`: Facility code (VN5, MY1, CNG)
- `--stage`: Stage (WAFER, TEST, DIEBOND, SINGULATION, LEADFRAME_ATTACH, INTERNAL2DID)
- `--start-date`: Start date (YYYY-MM-DD format)
- `--end-date`: End date (YYYY-MM-DD format, inclusive)
- `--max-hours`: Hours to extract per day (default: 24)

## Examples

### Example 1: VN5 WAFER (Feb 10-20)

```bash
python3 e142_extraction_manager.py historical \
  --facility VN5 \
  --stage WAFER \
  --start-date 2026-02-10 \
  --end-date 2026-02-20
```

**What happens:**
```
[1/11] Processing: 2026-02-10
  Creating modfile: /tmp/modfile_VN5_WAFER_20260210.txt
  Content: "2026-02-10 00:00:00"
  Running: perl getSnowflakeE142ModuleTrace.pl --modfile /tmp/modfile_VN5_WAFER_20260210.txt --max_hours 24 ...
  ✓ SUCCESS: 2026-02-10
  Files created: 45
  Rows extracted: 125430
  Elapsed: 12m 28s
  Cleanup: Deleted /tmp/modfile_VN5_WAFER_20260210.txt

[2/11] Processing: 2026-02-11
  Creating modfile: /tmp/modfile_VN5_WAFER_20260211.txt
  Content: "2026-02-11 00:00:00"
  Running: perl getSnowflakeE142ModuleTrace.pl --modfile /tmp/modfile_VN5_WAFER_20260211.txt --max_hours 24 ...
  ✓ SUCCESS: 2026-02-11
  Files created: 52
  Rows extracted: 138920
  Elapsed: 14m 15s
  Cleanup: Deleted /tmp/modfile_VN5_WAFER_20260211.txt

... (continues for each day)

[11/11] Processing: 2026-02-20
  ✓ SUCCESS: 2026-02-20
  Files created: 48
  Rows extracted: 131245
  Elapsed: 13m 02s

============================================================
Historical Extraction Complete
============================================================
Total days: 11
Success: 11
Failed: 0
Total files created: 523
============================================================
```

### Example 2: Single Day Extraction

```bash
# Extract only Feb 15, 2026
python3 e142_extraction_manager.py historical \
  --facility VN5 \
  --stage WAFER \
  --start-date 2026-02-15 \
  --end-date 2026-02-15
```

### Example 3: All Stages for One Facility

```bash
# VN5 - All stages for Feb 10-20
python3 e142_extraction_manager.py historical \
  --facility VN5 --stage WAFER \
  --start-date 2026-02-10 --end-date 2026-02-20

python3 e142_extraction_manager.py historical \
  --facility VN5 --stage TEST \
  --start-date 2026-02-10 --end-date 2026-02-20

python3 e142_extraction_manager.py historical \
  --facility VN5 --stage DIEBOND \
  --start-date 2026-02-10 --end-date 2026-02-20
```

### Example 4: Custom Time Window (48 hours)

```bash
# Extract 48 hours per day (overlapping windows)
python3 e142_extraction_manager.py historical \
  --facility VN5 \
  --stage WAFER \
  --start-date 2026-02-10 \
  --end-date 2026-02-20 \
  --max-hours 48
```

**Use case:** If data arrives late or you want overlapping coverage

## Batch Processing Script

### Complete Feb 10-20 Extraction (All Facilities)

Create `run_feb_10_20_extraction.sh`:

```bash
#!/bin/bash

# E142 Historical Extraction: Feb 10-20, 2026
# Processes all facilities and stages

START_DATE="2026-02-10"
END_DATE="2026-02-20"
SCRIPT="e142_extraction_manager.py"

echo "=========================================="
echo "E142 Historical Extraction"
echo "Date Range: $START_DATE to $END_DATE"
echo "=========================================="
echo ""

# Function to run extraction with error handling
run_extraction() {
    local facility=$1
    local stage=$2
    
    echo "[$facility - $stage] Starting..."
    
    python3 $SCRIPT historical \
        --facility $facility \
        --stage $stage \
        --start-date $START_DATE \
        --end-date $END_DATE \
        --max-hours 24
    
    if [ $? -eq 0 ]; then
        echo "[$facility - $stage] ✓ SUCCESS"
    else
        echo "[$facility - $stage] ✗ FAILED"
    fi
    echo ""
}

# VN5 (B1T Flow)
echo "=== VN5 (Vietnam/OSV - B1T) ==="
run_extraction VN5 WAFER
run_extraction VN5 TEST
run_extraction VN5 DIEBOND

# MY1 (PIM Flow)
echo "=== MY1 (Malaysia/SBN - PIM) ==="
run_extraction MY1 WAFER
run_extraction MY1 TEST
run_extraction MY1 DIEBOND

# CNG (PIM Flow)
echo "=== CNG (China/Shenzhen - PIM) ==="
run_extraction CNG WAFER
run_extraction CNG TEST
run_extraction CNG DIEBOND

echo "=========================================="
echo "All extractions complete!"
echo "=========================================="
```

**Run it:**
```bash
chmod +x run_feb_10_20_extraction.sh
./run_feb_10_20_extraction.sh
```

### Parallel Processing (Advanced)

If you want to run multiple facilities in parallel:

```bash
#!/bin/bash

START_DATE="2026-02-10"
END_DATE="2026-02-20"

# Run all facilities in parallel (background jobs)
python3 e142_extraction_manager.py historical --facility VN5 --stage WAFER --start-date $START_DATE --end-date $END_DATE &
python3 e142_extraction_manager.py historical --facility MY1 --stage WAFER --start-date $START_DATE --end-date $END_DATE &
python3 e142_extraction_manager.py historical --facility CNG --stage WAFER --start-date $START_DATE --end-date $END_DATE &

# Wait for all to complete
wait

echo "All parallel extractions complete!"
```

**⚠️ Warning:** Parallel runs consume more resources. Monitor system load.

## Monitoring & Verification

### Real-Time Monitoring

```bash
# Watch logs
tail -f $DPLOG/getSnowflakeE142ModuleTrace.VN5.WAFER.*.log

# Monitor benchmark data
tail -f $DPLOG/benchmark.jsonl | jq '{date: .date_code, rows: .rows_extracted, elapsed: .elapsed_human}'

# Watch output files being created
watch -n 5 'ls -lh $DPDATA/data/e142_trace/*.gz | tail -10'
```

### Post-Extraction Verification

#### 1. Check Benchmark Summary

```bash
# View all Feb 10-20 extractions
jq -r 'select(.pipeline_name | contains("VN5_WAFER")) | 
       [.date_code, .rows_extracted, .total_files, .elapsed_human] | 
       @tsv' $DPLOG/benchmark.jsonl | grep "202602"

# Output:
# 20260210_030015  125430  45  12m 28s
# 20260211_030015  138920  52  14m 15s
# 20260212_030015  142350  48  13m 45s
# ...
```

#### 2. Count Output Files Per Day

```bash
# Count files for each day
for day in {10..20}; do
    count=$(ls -1 $DPDATA/data/e142_trace/*202602${day}*.gz 2>/dev/null | wc -l)
    echo "Feb $day: $count files"
done

# Output:
# Feb 10: 45 files
# Feb 11: 52 files
# Feb 12: 48 files
# ...
```

#### 3. Verify Row Counts

```bash
# Total rows extracted for Feb 10-20
jq -r 'select(.date_code | startswith("202602")) | .rows_extracted' $DPLOG/benchmark.jsonl | 
    awk '{sum+=$1} END {print "Total rows:", sum}'

# Output:
# Total rows: 1,423,567
```

#### 4. Check for Failures

```bash
# Find failed extractions
jq -r 'select(.date_code | startswith("202602")) | 
       select(.rowcount == 0 or .total_files == 0) | 
       [.date_code, .pipeline_name, "FAILED"] | 
       @tsv' $DPLOG/benchmark.jsonl

# If empty output = all successful
```

## Troubleshooting

### Issue 1: No Rows Extracted for a Day

**Symptoms:**
```
[5/11] Processing: 2026-02-14
  ✓ SUCCESS: 2026-02-14
  Files created: 0
  Rows extracted: 0
```

**Diagnosis:**
```bash
# Check diagnostics in log
grep "E142 extraction diagnostics" $DPLOG/getSnowflakeE142ModuleTrace.VN5.WAFER.2026-02-14*.log

# Output might show:
# fetched=0 kept=0 dropped_status=0 dropped_no_backend_lot=0 dropped_prod_regex=0
```

**Possible Causes:**
1. **No data in Snowflake for that day** - Normal if no production activity
2. **Time window mismatch** - Data might be in different 24-hour window
3. **Product filter too aggressive** - Check `prod_not_regexp` setting

**Solutions:**
```bash
# Try 48-hour window to catch late-arriving data
python3 e142_extraction_manager.py historical \
  --facility VN5 --stage WAFER \
  --start-date 2026-02-14 --end-date 2026-02-14 \
  --max-hours 48

# Or disable product filter temporarily (edit config)
prod_not_regexp: ""  # Empty = no filtering
```

### Issue 2: Extraction Timeout

**Symptoms:**
```
[3/11] Processing: 2026-02-12
  ✗ TIMEOUT: 2026-02-12 (exceeded 1 hour)
```

**Solutions:**
```python
# Increase timeout in Python script (line ~250)
result = subprocess.run(
    cmd,
    capture_output=True,
    text=True,
    timeout=7200  # Change from 3600 to 7200 (2 hours)
)
```

### Issue 3: Modfile Not Cleaned Up

**Symptoms:**
```bash
ls /tmp/modfile_*.txt
# Shows leftover modfiles
```

**Cause:** Script crashed before cleanup

**Solution:**
```bash
# Manual cleanup
rm /tmp/modfile_*.txt

# Or modify Python script to keep them for debugging (line ~280)
# Comment out: Path(modfile_path).unlink()
```

### Issue 4: Lock File Blocking

**Symptoms:**
```
ERROR: Another instance is already running (lock: ./log/E142_VN5_WAFER.lock)
```

**Solution:**
```bash
# Check if process actually running
ps aux | grep getSnowflakeE142ModuleTrace

# If not running, remove stale lock
rm ./log/E142_VN5_WAFER.lock
```

## Performance Optimization

### Execution Time Estimates

| Facility | Stage   | Avg Time/Day | Total (11 days) |
|----------|---------|--------------|-----------------|
| VN5      | WAFER   | 12 min       | ~2.2 hours      |
| VN5      | TEST    | 10 min       | ~1.8 hours      |
| VN5      | DIEBOND | 8 min        | ~1.5 hours      |
| MY1      | WAFER   | 10 min       | ~1.8 hours      |
| MY1      | TEST    | 8 min        | ~1.5 hours      |
| MY1      | DIEBOND | 7 min        | ~1.3 hours      |
| CNG      | WAFER   | 9 min        | ~1.6 hours      |
| CNG      | TEST    | 7 min        | ~1.3 hours      |
| CNG      | DIEBOND | 6 min        | ~1.1 hours      |

**Total Sequential Time:** ~14 hours for all facilities/stages

### Optimization Strategies

1. **Run during off-peak hours** (nights/weekends)
2. **Parallel processing** (multiple facilities at once)
3. **Stagger start times** (avoid Snowflake query contention)
4. **Increase max_hours** (fewer, larger queries vs many small ones)

## Best Practices

### ✅ DO

- **Test single day first** before running full range
- **Monitor first facility** before starting others
- **Check output files** after each facility completes
- **Save benchmark logs** for audit trail
- **Run during off-peak hours** for large date ranges
- **Use max_hours 24** for clean daily boundaries

### ❌ DON'T

- **Don't run multiple stages for same facility in parallel** (lock conflicts)
- **Don't use max_hours > 48** (query performance degrades)
- **Don't delete benchmark logs** (needed for troubleshooting)
- **Don't interrupt running extractions** (can corrupt modfiles)

## Quick Reference

```bash
# Basic historical extraction
python3 e142_extraction_manager.py historical \
  --facility VN5 --stage WAFER \
  --start-date 2026-02-10 --end-date 2026-02-20

# Single day
python3 e142_extraction_manager.py historical \
  --facility VN5 --stage WAFER \
  --start-date 2026-02-15 --end-date 2026-02-15

# Custom time window
python3 e142_extraction_manager.py historical \
  --facility VN5 --stage WAFER \
  --start-date 2026-02-10 --end-date 2026-02-20 \
  --max-hours 48

# Monitor progress
tail -f $DPLOG/getSnowflakeE142ModuleTrace.VN5.WAFER.*.log

# Check results
jq -r '[.date_code, .rows_extracted, .elapsed_human] | @tsv' $DPLOG/benchmark.jsonl | grep "202602"
```

## Related Documentation

- [E142_EXTRACTION_MANAGER_GUIDE.md](E142_EXTRACTION_MANAGER_GUIDE.md) - Complete manager guide
- [E142_CRON_SETUP_GUIDE.md](E142_CRON_SETUP_GUIDE.md) - Cron automation setup
- `getSnowflakeE142ModuleTrace.pl` - Perl script documentation
