# E142 Extraction Manager - Complete Guide

## Overview

The E142 Extraction Manager is a Python wrapper for `getSnowflakeE142ModuleTrace.pl` that provides:
- **Cron automation** - Scheduled extractions with configured modfiles
- **Manual runs** - One-time extractions with custom parameters
- **Historical extraction** - Date range processing (one day at a time)
- **Multi-facility support** - VN5, MY1, CNG configurations
- **Benchmark logging** - Automatic performance tracking

## Architecture

```
Python Manager (Orchestrator)
    ↓
    Calls Perl Script with parameters
    ↓
getSnowflakeE142ModuleTrace.pl
    ↓
    Queries Snowflake → Generates trace files
    ↓
    Logs benchmarks → JSONL + Oracle DB
```

## Files Structure

```
scripts/py/
├── e142_extraction_manager.py          # Main Python script
├── resources/
│   └── e142_extraction_config.yaml     # Configuration file
└── docs/
    ├── E142_EXTRACTION_MANAGER_GUIDE.md    # This file
    ├── E142_HISTORICAL_MODE_GUIDE.md       # Historical extraction details
    └── E142_CRON_SETUP_GUIDE.md            # Cron automation setup
```

## Quick Start

### 1. Setup Environment

```bash
# Required environment variables
export SNOW_USER="your_snowflake_username"
export SNOW_PASS="your_snowflake_password"

# Path variables (adjust to your environment)
export DPSCRIPT="/path/to/scripts"
export DPLOG="/path/to/logs"
export DPDATA="/path/to/data"
export HOME="/export/home/dpower"

# Optional: Snowflake role
export SNOW_ROLE="YOUR_ROLE"
```

### 2. Install Dependencies

```bash
pip3 install pyyaml
```

### 3. Verify Configuration

```bash
# List configured facilities
python3 e142_extraction_manager.py list

# Output:
# Configured Facilities:
#   VN5: Vietnam/OSV (B1T)
#     ✓ WAFER
#     ✓ TEST
#     ✓ DIEBOND
#   MY1: Malaysia/SBN (PIM)
#     ✓ WAFER
#     ✓ TEST
#     ✓ DIEBOND
#   CNG: China/Shenzhen (PIM)
#     ✓ WAFER
#     ✓ TEST
#     ✓ DIEBOND
```

## Execution Modes

### Mode 1: CRON (Automated Scheduled Runs)

Uses configured modfile that tracks last extraction timestamp.

```bash
# Run as cron job
python3 e142_extraction_manager.py cron --facility VN5 --stage WAFER
```

**Characteristics:**
- Uses modfile from config: `$HOME/status_files/getSnowflakeE142ModuleTrace.pl.E142_VN5_B1T_EXENSIO_FAB2PUCK_RPT.wafer.prd.moddate`
- Updates modfile after successful run
- Extracts data since last run (incremental)
- Default `--max_hours 120` (5 days lookback)

**Cron Schedule Example:**
```cron
# VN5 WAFER - Every 6 hours at :00 minutes
00 3,9,15,21 * * * python3 /path/to/e142_extraction_manager.py cron --facility VN5 --stage WAFER
```

### Mode 2: MANUAL (One-Time Run)

Manual execution with optional custom modfile.

```bash
# Use default configured modfile
python3 e142_extraction_manager.py manual --facility VN5 --stage WAFER

# Use custom modfile
python3 e142_extraction_manager.py manual \
  --facility VN5 --stage WAFER \
  --modfile /path/to/custom_modfile.txt

# Override max_hours
python3 e142_extraction_manager.py manual \
  --facility VN5 --stage WAFER \
  --max-hours 48
```

**Use Cases:**
- Testing configuration changes
- Re-running failed extractions
- Custom time window extraction
- Debugging

### Mode 3: HISTORICAL (Date Range Extraction)

**⭐ Recommended for Feb 10-20 requirement**

Processes date range **one day at a time** with separate modfiles.

```bash
# Extract Feb 10-20, 2026 (one day at a time)
python3 e142_extraction_manager.py historical \
  --facility VN5 \
  --stage WAFER \
  --start-date 2026-02-10 \
  --end-date 2026-02-20 \
  --max-hours 24
```

**How It Works:**
1. Loops through each day (Feb 10, 11, 12, ..., 20)
2. Creates temporary modfile per day: `/tmp/modfile_VN5_WAFER_20260210.txt`
3. Modfile content: `"2026-02-10 00:00:00"`
4. Runs Perl script with `--max_hours 24` (extracts 24 hours from that timestamp)
5. Deletes temporary modfile
6. Repeats for next day

**Output Example:**
```
[1/11] Processing: 2026-02-10
  ✓ SUCCESS: 2026-02-10
  Files created: 45
  Rows extracted: 125430
  Elapsed: 12m 28s

[2/11] Processing: 2026-02-11
  ✓ SUCCESS: 2026-02-11
  Files created: 52
  Rows extracted: 138920
  Elapsed: 14m 15s

...

Historical Extraction Complete
Total days: 11
Success: 11
Failed: 0
```

See [E142_HISTORICAL_MODE_GUIDE.md](E142_HISTORICAL_MODE_GUIDE.md) for detailed examples.

### Mode 4: ALL (Run All Facilities)

```bash
# Run all facilities for WAFER stage
python3 e142_extraction_manager.py all --stage WAFER

# Run all facilities, all stages
python3 e142_extraction_manager.py all
```

## Configuration File

Location: `scripts/py/resources/e142_extraction_config.yaml`

### Structure

```yaml
defaults:
  source_odbc: MART_SNOWFLAKE
  source_warehouse: MFG_PRD_RPT_WH
  source_schema: ANALYTICSPRD.MFG
  get_product: true
  max_hours: 120
  prod_not_regexp: "^NVG.+"
  benchmark_log: "${DPLOG}/benchmark.jsonl"
  benchmark_db_dsn: DWPRD
  benchmark_db_user: true

paths:
  script_dir: "${DPSCRIPT}"
  log_dir: "${DPLOG}"
  data_dir: "${DPDATA}/data"
  status_dir: "${HOME}/status_files"

facilities:
  VN5:
    facility_code: VN5
    facility_name: "Vietnam/OSV"
    flow: B1T
    view_name: E142_VN5_B1T_EXENSIO_FAB2PUCK_RPT
    out_trace: "${DPDATA}/data/e142_trace"
    stages:
      WAFER:
        enabled: true
        modfile: "${HOME}/status_files/getSnowflakeE142ModuleTrace.pl.E142_VN5_B1T_EXENSIO_FAB2PUCK_RPT.wafer.prd.moddate"
        cron_schedule: "00 3,15 3,9,15,21 * * *"
      # ... more stages
```

### Environment Variable Expansion

The config supports environment variables:
- `${DPSCRIPT}` → `/export/home/dpower/scripts`
- `${DPLOG}` → `/export/home/dpower/logs`
- `${DPDATA}` → `/export/home/dpower/data`
- `${HOME}` → `/export/home/dpower`

## Benchmark Logging

### Default Behavior

The Python manager **passes benchmark parameters to the Perl script**, which handles all logging:

```python
# Python builds command with:
--benchmark_log ${DPLOG}/benchmark.jsonl
--benchmark_db_dsn DWPRD
--benchmark_db_user  # Uses default credentials
```

### Perl Script Benchmark Implementation

The Perl script (`getSnowflakeE142ModuleTrace.pl`) logs:

**JSONL File** (`$DPLOG/benchmark.jsonl`):
```json
{
  "start_local": "2026-02-10 03:00:15",
  "end_local": "2026-02-10 03:12:43",
  "start_utc": "2026-02-10T10:00:15Z",
  "end_utc": "2026-02-10T10:12:43Z",
  "elapsed_seconds": 748.23,
  "elapsed_human": "12m 28s",
  "rowcount": 125430,
  "rows_extracted": 125430,
  "rows_written": 125430,
  "total_files": 45,
  "rows_fetched": 125430,
  "rows_kept": 125430,
  "rows_dropped_status": 0,
  "rows_dropped_no_backend_lot": 0,
  "rows_dropped_prod_regex": 0,
  "pipeline_name": "E142_VN5_WAFER",
  "environment": "prod",
  "output_files_trace": ["/path/to/file1.gz", "/path/to/file2.gz"]
}
```

**Oracle Database** (`PIPELINE_RUNS` table):
- Same data inserted into Oracle if `--benchmark_db_dsn` provided
- Default credentials: `refdb` / `br#^gox66312sdAB` (when `--benchmark_db_user` flag present)
- DSN: `DWPRD` (Oracle TNS name)

### Benchmark Database Connection

**Default Connection (from Perl script lines 632-640):**

```perl
# If benchmark_db_user flag is present (even if empty), use default credentials
if (exists($optionsRef->{BENCHMARK_DB_USER}) && length($user) == 0)
{
    $user = "refdb";
    $pass = 'br#^gox66312sdAB';
    INFO("Using default benchmark database credentials (user: $user)");
}

# Connect to Oracle
$dbh = DBI->connect("dbi:Oracle:$dsn", $user, $pass, {
    PrintError => 0,
    RaiseError => 1,
    AutoCommit => 0
});
```

**Connection Details:**
- **DSN**: `EXNQA` (Oracle TNS name from `~/tns/tnsnames.ora`)
- **Host**: `exnqa-db.onsemi.com:1740`
- **Service**: `EXNQA.onsemi.com`
- **Default User**: `refdb`
- **Default Password**: `br#^gox66312sdAB`
- **Table**: `PIPELINE_RUNS`

**To Use Custom Credentials:**
```bash
# Set environment variables
export BENCHMARK_DB_USER="custom_user"
export BENCHMARK_DB_PASS="custom_pass"

# Or pass via command line (Python manager doesn't support this yet)
perl getSnowflakeE142ModuleTrace.pl \
  --benchmark_db_dsn DWPRD \
  --benchmark_db_user custom_user \
  --benchmark_db_pass custom_pass
```

### Disable Benchmark Logging

Edit `e142_extraction_config.yaml`:

```yaml
defaults:
  # benchmark_log: "${DPLOG}/benchmark.jsonl"  # Comment out
  # benchmark_db_dsn: DWPRD                     # Comment out
  # benchmark_db_user: true                     # Comment out
```

## Output Files

### Trace Files

**Location:**
- B1T flow: `$DPDATA/data/e142_trace/`
- PIM flow: `$DPDATA/data/e142_pim_trace/`

**Naming Convention:**
```
E142_{FACILITY}_{FLOW}-{STAGE}-{TIMESTAMP}-{KEY}.{EXT}.gz

Examples:
E142_VN5_B1T-WAFER-20260210_030015-VN5-LOTID.w2f.gz
E142_MY1_PIM-TEST-20260210_070030-MY1-TESTLOT.f2w.gz
```

**Extensions:**
- `.w2f` - Wafer to Final (forward trace)
- `.a2w` - Assembly to Wafer (backward trace from DIEBOND)
- `.s2w` - Singulation to Wafer (backward trace from SINGULATION)
- `.f2w` - Final to Wafer (backward trace from TEST)

### Log Files

**Location:** `$DPLOG/`

**Files:**
```
getSnowflakeE142ModuleTrace.VN5.WAFER.2026-02-10_03:00:15.log
getSnowflakeE142ModuleTrace.MY1.TEST.2026-02-10_07:00:30.log
extraction_runner_20260210_030015.log  # Python manager log
benchmark.jsonl                          # Benchmark data
```

## Monitoring & Troubleshooting

### Real-Time Monitoring

```bash
# Watch logs
tail -f $DPLOG/getSnowflakeE142ModuleTrace.VN5.WAFER.*.log

# Monitor benchmark
tail -f $DPLOG/benchmark.jsonl | jq .
```

### Check Extraction Status

```bash
# View recent benchmarks
tail -10 $DPLOG/benchmark.jsonl | jq '{pipeline: .pipeline_name, rows: .rows_extracted, elapsed: .elapsed_human, success: (.rowcount > 0)}'

# Count output files
ls -lh $DPDATA/data/e142_trace/*.gz | wc -l

# Check for errors in logs
grep -i error $DPLOG/getSnowflakeE142ModuleTrace.*.log
```

### Common Issues

**1. No rows extracted**
```bash
# Check diagnostics in log
grep "E142 extraction diagnostics" $DPLOG/*.log

# Common causes:
# - rows_dropped_prod_regex > 0: Product filter too aggressive
# - rows_dropped_status > 0: onScribe web service unavailable
# - rows_fetched = 0: Time window has no data
```

**2. Modfile not updating**
```bash
# Check modfile timestamp
cat $HOME/status_files/getSnowflakeE142ModuleTrace.pl.*.moddate

# Should update after successful run
# If stuck, manually update:
echo "2026-02-10 00:00:00" > $HOME/status_files/getSnowflakeE142ModuleTrace.pl.E142_VN5_B1T_EXENSIO_FAB2PUCK_RPT.wafer.prd.moddate
```

**3. Lock file error**
```bash
# Error: "Another instance is already running"
# Check for stale lock
ls -lh ./log/*.lock

# Remove if process not running
rm ./log/E142_VN5_WAFER.lock
```

## Best Practices

### For Historical Extraction (Feb 10-20)

1. **Run one facility at a time** to avoid resource contention
2. **Use max_hours 24** for clean daily boundaries
3. **Monitor first day** before running full range
4. **Check output files** after each facility completes

```bash
# Recommended approach
python3 e142_extraction_manager.py historical \
  --facility VN5 --stage WAFER \
  --start-date 2026-02-10 --end-date 2026-02-20 \
  --max-hours 24

# Wait for completion, verify output, then run next
python3 e142_extraction_manager.py historical \
  --facility VN5 --stage TEST \
  --start-date 2026-02-10 --end-date 2026-02-20 \
  --max-hours 24
```

### For Production Cron

1. **Stagger schedules** to avoid overlapping runs
2. **Use max_hours 120** for 5-day lookback (handles missed runs)
3. **Monitor benchmark logs** for performance trends
4. **Set up alerts** for failed extractions

## Backlog Management & Catch-up Strategy

When a backlog exists (e.g., historical data from March 3rd is needed today, March 11th), special handling is required to "clear" the pipeline.

### 1. Automatic Modfile Updating
The script is designed to "walk" forward in time. When a run completes successfully:
- It identifies the latest `METAMODIFIEDDATE` in the results.
- It **overwrites** the `--modfile` with this timestamp.
- The next run (scheduled or manual) continues exactly from this benchmark.

### 2. The Catch-up Run
Because the script uses a fixed window (`modfile_date` + `max_hours`), a standard hourly window (2 hours) will not clear a multi-day backlog quickly.

**Recommendation:**
To catch up after multiple days of inactivity, run the first extraction with a very high `--max-hours` value (e.g., `240` hours for 10 days).

```bash
# Example Catch-up for VN5 TEST (8-day backlog)
python3 e142_extraction_manager.py manual \
  --facility VN5 --stage TEST \
  --max-hours 240
```

### 3. Recovery after Partial Runs
If a catch-up run is interrupted or uses too small a window (e.g., 120h for a 200h backlog):
- **Do not reset anything.**
- Simply run the script again. 
- The first run successfully updated the `modfile` to the 120h mark; the second run will pick up from there and clear the rest.

## Performance

### Typical Execution Times

- **WAFER stage**: 10-15 minutes per day
- **TEST stage**: 8-12 minutes per day
- **DIEBOND stage**: 5-10 minutes per day

### Resource Usage

- **Memory**: ~500MB per Perl process
- **Disk I/O**: Moderate (gzip compression)
- **Network**: Snowflake query + web service calls

### Optimization Tips

1. **Reduce prod_not_regexp filtering** if too many rows dropped
2. **Increase max_hours** for cron to reduce frequency
3. **Run historical extractions during off-peak hours**

## Support & References

- **Perl Script**: `scripts/getSnowflakeE142ModuleTrace.pl`
- **Python Manager**: `scripts/py/e142_extraction_manager.py`
- **Configuration**: `scripts/py/resources/e142_extraction_config.yaml`
- **Historical Guide**: `scripts/py/docs/E142_HISTORICAL_MODE_GUIDE.md`
- **Cron Setup**: `scripts/py/docs/E142_CRON_SETUP_GUIDE.md`

## Quick Reference

```bash
# List facilities
python3 e142_extraction_manager.py list

# Generate crontab
python3 e142_extraction_manager.py generate-cron

# Cron mode
python3 e142_extraction_manager.py cron --facility VN5 --stage WAFER

# Manual mode
python3 e142_extraction_manager.py manual --facility VN5 --stage WAFER

# Historical mode (Feb 10-20)
python3 e142_extraction_manager.py historical \
  --facility VN5 --stage WAFER \
  --start-date 2026-02-10 --end-date 2026-02-20

# All facilities
python3 e142_extraction_manager.py all --stage WAFER
```
