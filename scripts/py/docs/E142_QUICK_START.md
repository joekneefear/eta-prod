# E142 Extraction Manager - Quick Start

## File Locations

```
/export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/
├── scripts/
│   ├── getSnowflakeE142ModuleTrace.pl          # Perl extraction script
│   └── py/
│       ├── get_snowflake_e142_extraction_manager.py    # Python manager (THIS SCRIPT)
│       ├── resources/
│       │   └── e142_extraction_config.yaml     # Configuration file
│       └── docs/
│           ├── E142_QUICK_START.md             # This file
│           ├── E142_EXTRACTION_MANAGER_GUIDE.md
│           └── E142_HISTORICAL_MODE_GUIDE.md
```

## Setup

### 1. Set Environment Variables

```bash
# Required for Snowflake authentication
export SNOW_USER="your_snowflake_username"
export SNOW_PASS="your_snowflake_password"

# Required for file paths (used by config file)
export DPSCRIPT="/path/to/scripts"
export DPLOG="/path/to/logs"
export DPDATA="/path/to/data"
export HOME="/export/home/dpower"

# Optional: Snowflake role
export SNOW_ROLE="YOUR_ROLE"

# Verify perl_db is in PATH
which perl_db
# Should show: /apps/exensio/pdf/exn41/bin/perl_db
```

### 2. Install Dependencies

```bash
pip3 install pyyaml
```

### 3. Create Required Directories

```bash
# Log directory
mkdir -p /export/home/dpower/logs

# Trace output directories
mkdir -p /export/home/dpower/data/e142_trace/tmp
mkdir -p /export/home/dpower/data/e142_pim_trace/tmp

# Status files (modfiles)
mkdir -p /export/home/dpower/status_files

# Verify directories exist
ls -ld /export/home/dpower/logs
ls -ld /export/home/dpower/data/e142_trace
ls -ld /export/home/dpower/data/e142_pim_trace
ls -ld /export/home/dpower/status_files
```

### 4. Verify Setup

```bash
# Navigate to script directory
cd /export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/py

# List configured facilities
python3 get_snowflake_e142_extraction_manager.py list

# Should show:
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

## Usage

### Historical Extraction (Feb 10-20, 2026)

```bash
# Navigate to script directory
cd /export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/py

# VN5 WAFER
python3 get_snowflake_e142_extraction_manager.py historical \
  --facility VN5 \
  --stage WAFER \
  --start-date 2026-02-10 \
  --end-date 2026-02-20

# VN5 TEST
python3 get_snowflake_e142_extraction_manager.py historical \
  --facility VN5 \
  --stage TEST \
  --start-date 2026-02-10 \
  --end-date 2026-02-20

# VN5 DIEBOND
python3 get_snowflake_e142_extraction_manager.py historical \
  --facility VN5 \
  --stage DIEBOND \
  --start-date 2026-02-10 \
  --end-date 2026-02-20
```

### Manual Run (One-Time)

```bash
cd /export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/py

python3 get_snowflake_e142_extraction_manager.py manual \
  --facility VN5 \
  --stage WAFER
```

### Cron Mode (Automated)

```bash
cd /export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/py

python3 get_snowflake_e142_extraction_manager.py cron \
  --facility VN5 \
  --stage WAFER
```

## Configuration File Location

The script automatically looks for the config file at:
```
<script_directory>/resources/e142_extraction_config.yaml
```

Which resolves to:
```
/export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/py/resources/e142_extraction_config.yaml
```

### Perl Script Path Resolution

The Perl script location is configured in the YAML file:

```yaml
paths:
  script_dir: "/export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts"
```

The Python manager will look for:
```
{script_dir}/getSnowflakeE142ModuleTrace.pl
```

**To change the Perl script location:**
1. Edit `scripts/py/resources/e142_extraction_config.yaml`
2. Update `paths.script_dir` to your actual script directory
3. Can use absolute path or environment variable like `"${DPSCRIPT}"`

### Override Config Location

If you need to use a different config file:

```bash
python3 get_snowflake_e142_extraction_manager.py historical \
  --config /path/to/custom_config.yaml \
  --facility VN5 \
  --stage WAFER \
  --start-date 2026-02-10 \
  --end-date 2026-02-20
```

## Output Files

### Trace Files

**VN5 (B1T):**
```
/export/home/dpower/data/e142_trace/E142_VN5_B1T-WAFER-20260210_030015-VN5-LOTID.w2f.gz
/export/home/dpower/data/e142_trace/E142_VN5_B1T-TEST-20260210_040020-VN5-TESTLOT.f2w.gz
```

**MY1/CNG (PIM):**
```
/export/home/dpower/data/e142_pim_trace/E142_MY1_PIM-WAFER-20260210_060005-MY1-WAFERID.w2f.gz
/export/home/dpower/data/e142_pim_trace/E142_CNG_PIM-TEST-20260210_100015-CNG-TESTLOT.f2w.gz
```

### Log Files

```
/export/home/dpower/logs/getSnowflakeE142ModuleTrace.VN5.WAFER.2026-02-10_03:00:15.log
/export/home/dpower/logs/benchmark.jsonl
```

## Monitoring

### Watch Progress

```bash
# Watch log file
tail -f /export/home/dpower/logs/getSnowflakeE142ModuleTrace.VN5.WAFER.*.log

# Watch benchmark data
tail -f /export/home/dpower/logs/benchmark.jsonl | jq .
```

### Check Results

```bash
# Count output files
ls -lh /export/home/dpower/data/e142_trace/*.gz | wc -l

# View benchmark summary
jq -r '[.date_code, .rows_extracted, .elapsed_human] | @tsv' /export/home/dpower/logs/benchmark.jsonl | grep "202602"
```

## Troubleshooting

### Error: Config file not found

```bash
# Check if config exists
ls -l /export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/py/resources/e142_extraction_config.yaml

# If missing, check your path
pwd
```

### Error: Missing environment variables

```bash
# Only Snowflake credentials are required
echo $SNOW_USER
echo $SNOW_PASS

# Set them if missing
export SNOW_USER="your_username"
export SNOW_PASS="your_password"

# No other environment variables needed - all paths are in config file
```

### Error: OUT_TRACE directory not writable

```bash
# Create directories with absolute paths
mkdir -p /export/home/dpower/data/e142_trace/tmp
mkdir -p /export/home/dpower/data/e142_pim_trace/tmp

# Check permissions
ls -ld /export/home/dpower/data/e142_trace
ls -ld /export/home/dpower/data/e142_pim_trace

# Verify writable
test -w /export/home/dpower/data/e142_trace && echo "writable" || echo "NOT writable"
```

### Error: Perl script not found

```bash
# Check if Perl script exists at configured location
# (Path is in config file: paths.script_dir)
ls -l /export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/getSnowflakeE142ModuleTrace.pl

# If script is in different location, update config file:
# Edit: scripts/py/resources/e142_extraction_config.yaml
# Change: paths.script_dir to your actual script directory
```

### Error: perl_db not found

```bash
# Check if perl_db is in PATH
which perl_db

# Should show: /apps/exensio/pdf/exn41/bin/perl_db

# If not found, add to PATH
export PATH="/apps/exensio/pdf/exn41/bin:$PATH"

# Or use absolute path in config
vi scripts/py/resources/e142_extraction_config.yaml
# Change: perl_interpreter: "perl_db"
# To:     perl_interpreter: "/apps/exensio/pdf/exn41/bin/perl_db"
```

### Error: Can't locate DBI.pm

```bash
# This means perl_db is not being used
# Verify config has correct perl_interpreter
grep perl_interpreter scripts/py/resources/e142_extraction_config.yaml

# Should show: perl_interpreter: "perl_db"
```

## Complete Example: Feb 10-20 Extraction

```bash
#!/bin/bash

# Set Snowflake credentials only
export SNOW_USER="your_username"
export SNOW_PASS="your_password"

# Navigate to script directory
cd /export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/py

# Run VN5 extractions
echo "=== VN5 Extractions ==="
python3 get_snowflake_e142_extraction_manager.py historical \
  --facility VN5 --stage WAFER \
  --start-date 2026-02-10 --end-date 2026-02-20

python3 get_snowflake_e142_extraction_manager.py historical \
  --facility VN5 --stage TEST \
  --start-date 2026-02-10 --end-date 2026-02-20

python3 get_snowflake_e142_extraction_manager.py historical \
  --facility VN5 --stage DIEBOND \
  --start-date 2026-02-10 --end-date 2026-02-20

echo "Complete!"
```

## Next Steps

- See [E142_EXTRACTION_MANAGER_GUIDE.md](E142_EXTRACTION_MANAGER_GUIDE.md) for complete documentation
- See [E142_HISTORICAL_MODE_GUIDE.md](E142_HISTORICAL_MODE_GUIDE.md) for historical mode details
- Check benchmark logs: `$DPLOG/benchmark.jsonl`
- Verify output files: `$DPDATA/data/e142_trace/`
