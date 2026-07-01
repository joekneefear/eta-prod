# E142 Extraction Manager - Quick Reference

## Common Commands

### List Facilities
```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py list
```

### Generate Crontab
```bash
# View on screen
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py generate-cron

# Save to file
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py generate-cron --output /tmp/crontab.txt
```

### Manual Run (One-Time)
```bash
# Use default modfile
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py manual --facility MY1 --stage WAFER

# Custom modfile
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py manual --facility MY1 --stage WAFER --modfile /path/to/modfile.txt

# Custom max hours
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py manual --facility MY1 --stage WAFER --max-hours 48
```

### Historical Extraction (Date Range)
```bash
# Single day
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py historical \
  --facility MY1 --stage WAFER \
  --start-date 2026-02-10 --end-date 2026-02-10

# Multiple days (Feb 10-20)
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py historical \
  --facility MY1 --stage WAFER \
  --start-date 2026-02-10 --end-date 2026-02-20

# Last 7 days
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py historical \
  --facility MY1 --stage WAFER \
  --start-date $(date -d '7 days ago' +%Y-%m-%d) --end-date $(date +%Y-%m-%d)
```

### Run All Facilities
```bash
# All facilities, specific stage
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py all --stage WAFER

# All facilities, all stages
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py all
```

### Cron Mode (Used by Cron Jobs)
```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py cron --facility MY1 --stage WAFER
```

## Facility Codes

| Code | Name | Flow | Stages |
|------|------|------|--------|
| VN5 | Vietnam/OSV | B1T | WAFER, TEST, DIEBOND |
| MY1 | Malaysia/SBN | PIM | WAFER, TEST, DIEBOND |
| CNG | China/Shenzhen | PIM | WAFER, TEST, DIEBOND |

## Log Files

Logs are written to:
```
$DPLOG/getSnowflakeE142ModuleTrace.<facility>.<stage>.<timestamp>.log
```

Examples:
```
$DPLOG/getSnowflakeE142ModuleTrace.MY1.WAFER.2026-03-04_10:30:15.log
$DPLOG/getSnowflakeE142ModuleTrace.VN5.TEST.2026-03-04_14:45:22.log
```

## Configuration File

Location: `$DPSCRIPT/py/resources/e142_extraction_config.yaml`

Edit to:
- Add new facilities
- Change cron schedules
- Modify max_hours
- Enable/disable stages
- Update paths

## Environment Variables

Required:
```bash
export SNOW_USER="your_username"
export SNOW_PASS="your_password"
```

Should already be set:
```bash
export DPSCRIPT="/export/home/dpower/scripts"
export DPLOG="/export/home/dpower/log"
export DPDATA="/export/home/dpower/data"
```

## Cron Job Format

Old format (direct Perl):
```bash
05 6,18 * * * . $HOME/.bashrc; /bin/bash -c '$DPSCRIPT/getSnowflakeE142ModuleTrace.pl --source_odbc ...' > /dev/null 2>&1
```

New format (Python manager):
```bash
05 6,18 * * * . $HOME/.bashrc; python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py cron --facility MY1 --stage WAFER > /dev/null 2>&1
```

## Troubleshooting

### Check if script exists
```bash
ls -la $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py
```

### Check if config exists
```bash
ls -la $DPSCRIPT/py/resources/e142_extraction_config.yaml
```

### Check if Perl script exists
```bash
ls -la $DPSCRIPT/getSnowflakeE142ModuleTrace.pl
```

### Test environment variables
```bash
echo $SNOW_USER
echo $SNOW_PASS
echo $DPSCRIPT
echo $DPLOG
echo $DPDATA
```

### View recent logs
```bash
ls -lt $DPLOG/getSnowflakeE142ModuleTrace.*.log | head -5
```

### Check cron jobs
```bash
crontab -l | grep E142
```

### Test cron command manually
```bash
. $HOME/.bashrc; python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py cron --facility MY1 --stage WAFER
```

## Help

Get help for any command:
```bash
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py --help
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py cron --help
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py manual --help
python3 $DPSCRIPT/py/get_snowflake_e142_extraction_manager.py historical --help
```
