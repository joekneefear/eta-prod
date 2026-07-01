# E142 Extraction Manager - Configuration Guide

## Configuration File Location

The Python manager automatically finds the config file at:
```
<python_script_directory>/resources/e142_extraction_config.yaml
```

**Full path:**
```
/export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/py/resources/e142_extraction_config.yaml
```

## Path Resolution

### 1. Python Manager Script Location

```
/export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/py/get_snowflake_e142_extraction_manager.py
```

### 2. Config File (Auto-discovered)

```
/export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/py/resources/e142_extraction_config.yaml
```

### 3. Perl Script (From Config)

The Perl script location is defined in the config file:

```yaml
paths:
  script_dir: "/export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts"
```

Python manager resolves to:
```
{script_dir}/getSnowflakeE142ModuleTrace.pl
```

**Full path:**
```
/export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/getSnowflakeE142ModuleTrace.pl
```

## Configuration Options

### Using Absolute Paths (Current Setup)

```yaml
paths:
  script_dir: "/export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts"
  log_dir: "/export/home/dpower/logs"
  data_dir: "/export/home/dpower/data/data"
  status_dir: "/export/home/dpower/status_files"
```

**Pros:**
- ✅ No environment variables needed
- ✅ Explicit and clear
- ✅ Works immediately

**Cons:**
- ❌ Hardcoded paths
- ❌ Need to edit config for different environments

### Using Environment Variables

```yaml
paths:
  script_dir: "${DPSCRIPT}"
  log_dir: "${DPLOG}"
  data_dir: "${DPDATA}/data"
  status_dir: "${HOME}/status_files"
```

**Pros:**
- ✅ Flexible across environments
- ✅ No config changes needed

**Cons:**
- ❌ Must set environment variables
- ❌ Less explicit

### Mixed Approach (Recommended)

```yaml
paths:
  script_dir: "/export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts"
  log_dir: "${DPLOG}"
  data_dir: "${DPDATA}/data"
  status_dir: "${HOME}/status_files"
```

**Why:**
- Script location is fixed (project-specific)
- Data/log locations vary by environment (use env vars)

## Environment Variables

### Required

```bash
# Snowflake credentials
export SNOW_USER="your_snowflake_username"
export SNOW_PASS="your_snowflake_password"
```

### Optional (if using env vars in config)

```bash
# Only needed if config uses ${DPLOG}, ${DPDATA}, etc.
export DPLOG="/export/home/dpower/logs"
export DPDATA="/export/home/dpower/data"
export HOME="/export/home/dpower"
```

### Not Needed

```bash
# DPSCRIPT is NOT needed - script path is in config file
# export DPSCRIPT="/path/to/scripts"  # ← Not required
```

## Customizing Paths

### Change Perl Script Location

Edit `scripts/py/resources/e142_extraction_config.yaml`:

```yaml
paths:
  script_dir: "/new/path/to/scripts"  # ← Change this
```

### Change Output Directories

```yaml
facilities:
  VN5:
    out_trace: "/custom/path/e142_trace"  # ← Change this
```

### Change Log Directory

```yaml
paths:
  log_dir: "/custom/log/path"  # ← Change this
```

## Verification

### Check Config File Exists

```bash
ls -l /export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/py/resources/e142_extraction_config.yaml
```

### Check Perl Script Exists

```bash
ls -l /export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/getSnowflakeE142ModuleTrace.pl
```

### Test Configuration

```bash
cd /export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/py

# List facilities (tests config loading)
python3 get_snowflake_e142_extraction_manager.py list
```

## Override Config File

If you need to use a different config file:

```bash
python3 get_snowflake_e142_extraction_manager.py \
  --config /path/to/custom_config.yaml \
  list
```

## Configuration Hierarchy

1. **Python script location** (fixed)
   ```
   /export/home/dpower/jag/.../scripts/py/get_snowflake_e142_extraction_manager.py
   ```

2. **Config file** (auto-discovered from Python script location)
   ```
   <python_script_dir>/resources/e142_extraction_config.yaml
   ```

3. **Perl script** (from config file `paths.script_dir`)
   ```
   {script_dir}/getSnowflakeE142ModuleTrace.pl
   ```

4. **Output/log paths** (from config file, can use env vars)
   ```
   {log_dir}/...
   {out_trace}/...
   ```

## Example: Complete Setup

```bash
# 1. Set required environment variables
export SNOW_USER="your_username"
export SNOW_PASS="your_password"
export DPLOG="/export/home/dpower/logs"
export DPDATA="/export/home/dpower/data"
export HOME="/export/home/dpower"

# 2. Navigate to Python script directory
cd /export/home/dpower/jag/CE-2778-change-batch-scripts-to-get-site_dim-from-snowflake-dev-integration/scripts/py

# 3. Verify configuration
python3 get_snowflake_e142_extraction_manager.py list

# 4. Run extraction
python3 get_snowflake_e142_extraction_manager.py historical \
  --facility VN5 --stage WAFER \
  --start-date 2026-02-10 --end-date 2026-02-20
```

## Troubleshooting

### Config file not found

**Error:**
```
FileNotFoundError: Config file not found: e142_extraction_config.yaml
```

**Solution:**
```bash
# Check if config exists
ls -l scripts/py/resources/e142_extraction_config.yaml

# Make sure you're in the right directory
pwd
# Should be: /export/home/dpower/jag/.../scripts/py
```

### Perl script not found

**Error:**
```
FileNotFoundError: [Errno 2] No such file or directory: '/path/to/getSnowflakeE142ModuleTrace.pl'
```

**Solution:**
```bash
# Check Perl script location in config
grep script_dir scripts/py/resources/e142_extraction_config.yaml

# Verify Perl script exists at that location
ls -l /export/home/dpower/jag/.../scripts/getSnowflakeE142ModuleTrace.pl

# Update config if path is wrong
vi scripts/py/resources/e142_extraction_config.yaml
```

### Environment variable not expanded

**Error:**
```
FileNotFoundError: ${DPLOG}/benchmark.jsonl
```

**Solution:**
```bash
# Set the environment variable
export DPLOG="/export/home/dpower/logs"

# Or use absolute path in config instead
vi scripts/py/resources/e142_extraction_config.yaml
# Change: log_dir: "${DPLOG}"
# To:     log_dir: "/export/home/dpower/logs"
```

## Summary

✅ **Config file**: Auto-discovered at `<python_script_dir>/resources/e142_extraction_config.yaml`  
✅ **Perl script**: Configured in YAML at `paths.script_dir`  
✅ **Paths**: Can use absolute paths or environment variables  
✅ **No DPSCRIPT needed**: Script path is in config file  
✅ **Flexible**: Override config with `--config` flag if needed  
