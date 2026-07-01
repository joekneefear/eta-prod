# E142 Extraction Manager - Setup Guide

## Overview

The `get_snowflake_e142_extraction_manager.py` script provides a centralized way to manage E142 extractions across multiple facilities with support for:
- Automated cron jobs
- Manual one-time runs
- Historical date range extraction
- Centralized configuration via YAML

## Current Setup

Your existing cron jobs directly call the Perl script:
```bash
# Old format (direct Perl call)
05 6,18 * * * . /export/home/dpower/.bashrc; /bin/bash -c '$DPSCRIPT/getSnowflakeE142ModuleTrace.pl --source_odbc MART_SNOWFLAKE ...' > /dev/null 2>&1
```

The new Python manager simplifies this to:
```bash
# New format (Python manager)
05 6,18 * * * . $HOME/.bashrc; python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py cron --facility MY1 --stage WAFER > /dev/null 2>&1
```

## Configuration File

Location: `$DPSCRIPT/py/resources/e142_extraction_config.yaml`

The config file defines:
- Global defaults (ODBC, warehouse, schema, max_hours, etc.)
- Path configuration (script_dir, log_dir, data_dir)
- Facility configurations (VN5, MY1, CNG)
- Stage configurations (WAFER, TEST, DIEBOND)
- Cron schedules

## Usage Examples

### 1. List Configured Facilities

```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py list
```

Output:
```
Configured Facilities:
  VN5: Vietnam/OSV (B1T)
    ✓ WAFER
    ✓ TEST
    ✓ DIEBOND
  MY1: Malaysia/SBN (PIM)
    ✓ WAFER
    ✓ TEST
    ✓ DIEBOND
  CNG: China/Shenzhen (PIM)
    ✓ WAFER
    ✓ TEST
    ✓ DIEBOND
```

### 2. Generate Crontab Entries

```bash
# Print to stdout
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py generate-cron

# Save to file
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py generate-cron --output /tmp/e142_crontab.txt
```

### 3. Cron Mode (Automated)

Used by cron jobs - uses configured modfile:

```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py cron --facility MY1 --stage WAFER
```

### 4. Manual Mode (One-Time Run)

Run with default modfile:
```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py manual --facility MY1 --stage WAFER
```

Run with custom modfile:
```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py manual --facility MY1 --stage WAFER --modfile /tmp/custom_modfile.txt
```

Run with custom max_hours:
```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py manual --facility MY1 --stage WAFER --max-hours 48
```

### 5. Historical Mode (Date Range)

Extract data for a specific date range:

```bash
# Single day
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py historical \
  --facility MY1 --stage WAFER \
  --start-date 2026-02-10 --end-date 2026-02-10

# Multiple days
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py historical \
  --facility MY1 --stage WAFER \
  --start-date 2026-02-10 --end-date 2026-02-20

# With custom max_hours per day
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py historical \
  --facility MY1 --stage WAFER \
  --start-date 2026-02-10 --end-date 2026-02-20 \
  --max-hours 24
```

### 6. Run All Facilities

Run all configured facilities for a specific stage:
```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py all --stage WAFER
```

Run all facilities, all stages:
```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py all
```

## Migration Steps

### Step 1: Verify Configuration

Check that your config file has correct paths:
```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py list
```

### Step 2: Test Manual Run

Test a single extraction manually:
```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py manual --facility MY1 --stage WAFER
```

Check the log file in `$DPLOG/getSnowflakeE142ModuleTrace.MY1.WAFER.*.log`

### Step 3: Generate New Crontab

```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py generate-cron --output /tmp/e142_new_crontab.txt
```

Review the generated crontab:
```bash
cat /tmp/e142_new_crontab.txt
```

### Step 4: Update Crontab

Backup existing crontab:
```bash
crontab -l > ~/crontab_backup_$(date +%Y%m%d).txt
```

Edit crontab:
```bash
crontab -e
```

Replace old E142 entries with new ones from `/tmp/e142_new_crontab.txt`

Verify:
```bash
crontab -l | grep E142
```

## Cron Schedule Format

The config file uses standard 5-field cron format:
```
# ┌───────────── minute (0 - 59)
# │ ┌───────────── hour (0 - 23)
# │ │ ┌───────────── day of month (1 - 31)
# │ │ │ ┌───────────── month (1 - 12)
# │ │ │ │ ┌───────────── day of week (0 - 6) (Sunday=0)
# │ │ │ │ │
# * * * * *
```

Examples:
- `05 6,18 * * *` - Run at 6:05 AM and 6:05 PM daily
- `30 7,19 * * *` - Run at 7:30 AM and 7:30 PM daily
- `00 8,20 * * *` - Run at 8:00 AM and 8:00 PM daily

## Environment Variables Required

The script expects these environment variables to be set:

```bash
# Snowflake credentials
export SNOW_USER="your_username"
export SNOW_PASS="your_password"

# Path variables (should already be set in .bashrc)
export DPSCRIPT="/export/home/dpower/scripts"
export DPLOG="/export/home/dpower/log"
export DPDATA="/export/home/dpower/data"
```

## Logging

Logs are written to:
```
$DPLOG/getSnowflakeE142ModuleTrace.<facility>.<stage>.<timestamp>.log
```

Example:
```
/export/home/dpower/log/getSnowflakeE142ModuleTrace.MY1.WAFER.2026-03-04_10:30:15.log
```

## Troubleshooting

### Issue: "Config file not found"

Check that the config file exists:
```bash
ls -la $DPSCRIPT/py/resources/e142_extraction_config.yaml
```

Specify custom config path:
```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py --config /path/to/config.yaml list
```

### Issue: "Missing environment variables: SNOW_USER, SNOW_PASS"

Set credentials in your shell or .bashrc:
```bash
export SNOW_USER="your_username"
export SNOW_PASS="your_password"
```

### Issue: "Perl script not found"

Check that the Perl script exists:
```bash
ls -la $DPSCRIPT/getSnowflakeE142ModuleTrace.pl
```

Update `script_dir` in config if needed.

### Issue: "Can't locate PDF/API2.pm"

The script sets `PERL5LIB` to include `$DPSCRIPT/lib` automatically. Verify:
```bash
ls -la $DPSCRIPT/lib/PDF/
```

### Issue: Cron job not running

Check cron logs:
```bash
grep E142 /var/log/cron
```

Test the exact cron command manually:
```bash
. $HOME/.bashrc; python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py cron --facility MY1 --stage WAFER
```

## Advanced Configuration

### Adding a New Facility

Edit `e142_extraction_config.yaml`:

```yaml
facilities:
  NEW_FAC:
    facility_code: NEW_FAC
    facility_name: "New Facility Name"
    flow: B1T  # or PIM
    view_name: E142_NEW_FAC_B1T_EXENSIO_FAB2PUCK_RPT
    out_trace: "${DPDATA}/data/e142_trace"
    stages:
      WAFER:
        enabled: true
        modfile: "${HOME}/status_files/getSnowflakeE142ModuleTrace.pl.E142_NEW_FAC_B1T_EXENSIO_FAB2PUCK_RPT.wafer.prd.moddate"
        cron_schedule: "00 3,15 * * *"
```

### Disabling a Stage

Set `enabled: false` in config:

```yaml
stages:
  WAFER:
    enabled: false  # This stage will be skipped
    modfile: "..."
    cron_schedule: "..."
```

### Changing Max Hours

Update in config:
```yaml
defaults:
  max_hours: 168  # 7 days
```

Or override per run:
```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py manual --facility MY1 --stage WAFER --max-hours 168
```

## Benefits of Using the Manager

1. **Centralized Configuration**: All settings in one YAML file
2. **Simplified Cron Jobs**: Short, readable cron entries
3. **Historical Extraction**: Easy date range processing
4. **Consistent Logging**: Standardized log file naming
5. **Error Handling**: Better error messages and validation
6. **Maintainability**: Easy to add/modify facilities
7. **Documentation**: Self-documenting configuration

## Support

For issues or questions:
1. Check logs in `$DPLOG/`
2. Run with `--help` for usage info
3. Test manually before adding to cron
4. Verify environment variables are set
