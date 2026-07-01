# Pipeline Service - Command-Line Interface

## Overview

The Pipeline Service now supports command-line arguments for configuration, similar to the Perl script `getCamstarWafer2AssemblyGenealogy.pl`. This provides a more flexible way to configure the service without relying solely on environment variables.

## Key Features

- **Default Credentials Support**: Pass `--oracle-user` without a value to use default credentials (refdb/br#^gox66312sdAB)
- **Flexible Configuration**: Command-line args override environment variables
- **Backward Compatible**: Existing environment variable configuration still works
- **Multiple Backends**: Support for both JSONL and Oracle backends

## Quick Start

### 1. Use Default Oracle Credentials and DSN (Simplest - Recommended)

```bash
python run_with_args.py --backend oracle --oracle-user
```

This automatically uses:
- DSN: `exnqa-db.onsemi.com:1740/EXNQA.onsemi.com` (QA database)
- Username: `refdb`
- Password: `br#^gox66312sdAB`

### 2. Use Default Credentials with Custom DSN

```bash
python run_with_args.py --backend oracle --oracle-dsn DWPRD --oracle-user
```

### 2. Custom Oracle Credentials via Command Line

```bash
python run_with_args.py \
  --backend oracle \
  --oracle-dsn "//oracle-prod.example.com:1521/PRODDB" \
  --oracle-user "custom_user" \
  --oracle-password "custom_password"
```

### 3. Custom Oracle Credentials via Environment Variables

```bash
export ORACLE_USER="pipeline_user"
export ORACLE_PASSWORD="secure_password"

python run_with_args.py --backend oracle
```

Note: When using environment variables, the default DSN will be used unless specified.

### 4. JSONL Backend (Default)

```bash
python run_with_args.py --backend jsonl --jsonl-path ./data/pipeline.jsonl
```

## Command-Line Options

### Backend Selection

```
--backend {jsonl,oracle}
    Storage backend (default: jsonl or PIPELINE_BACKEND env var)
```

### JSONL Options

```
--jsonl-path PATH
    Path to JSONL file (default: pipeline_data.jsonl or PIPELINE_JSONL_PATH env var)
```

### Oracle Options

```
--oracle-dsn DSN
    Oracle DSN (TNS name or connection string)
    Default: exnqa-db.onsemi.com:1740/EXNQA.onsemi.com (QA database)
    Examples: DWPRD, LOTGPRD, //hostname:1521/service_name

--oracle-user [USERNAME]
    Oracle username (optional value)
    - If specified without value: uses default credentials (refdb)
    - If specified with value: uses provided username
    - If not specified: uses ORACLE_USER env var

--oracle-password [PASSWORD]
    Oracle password (optional value)
    - If specified without value: uses default password
    - If specified with value: uses provided password
    - If not specified: uses ORACLE_PASSWORD env var

--oracle-table TABLE
    Oracle table name (default: pipeline_runs or ORACLE_TABLE env var)

--oracle-column-map JSON
    JSON mapping of model fields to DB columns
    Example: '{"start_utc":"START_UTC","rowcount":"ROW_COUNT"}'
```

### Server Options

```
--host HOST
    Host to bind to (default: 127.0.0.1)

--port PORT
    Port to bind to (default: 8001)

--reload
    Enable auto-reload for development
```

### CORS Options

```
--cors-origins ORIGINS
    Comma-separated list of allowed CORS origins
    Example: "http://localhost:3000,http://localhost:8080"

--cors-allow-all
    Allow all CORS origins (development only)
```

## Usage Examples

### Example 1: Development with Default Credentials and DSN

```bash
python run_with_args.py \
  --backend oracle \
  --oracle-user \
  --reload \
  --cors-allow-all
```

This uses the QA database by default.

### Example 2: Production with Custom DSN and Credentials

```bash
python run_with_args.py \
  --backend oracle \
  --oracle-dsn "//oracle-prod.example.com:1521/PRODDB" \
  --oracle-user "pipeline_prod" \
  --oracle-password "$(cat /secure/oracle_password.txt)" \
  --host 0.0.0.0 \
  --port 8001 \
  --cors-origins "http://dashboard.example.com"
```

### Example 3: QA Environment with Custom Credentials

```bash
export ORACLE_USER="pipeline_qa"
export ORACLE_PASSWORD="qa_password"

python run_with_args.py \
  --backend oracle \
  --port 8002
```

Note: Uses default QA DSN (exnqa-db.onsemi.com:1740/EXNQA.onsemi.com)

### Example 4: JSONL Backend for Local Development

```bash
python run_with_args.py \
  --backend jsonl \
  --jsonl-path ./test_data/pipeline.jsonl \
  --reload \
  --cors-allow-all
```

### Example 5: Oracle with Custom Table and Column Mapping

```bash
python run_with_args.py \
  --backend oracle \
  --oracle-dsn DWPRD \
  --oracle-user \
  --oracle-table CUSTOM_PIPELINE_RUNS \
  --oracle-column-map '{"start_utc":"START_TIME","end_utc":"END_TIME"}'
```

## Credential Resolution Order

The service resolves credentials in this priority order:

1. **Command-line explicit values** (highest priority)
   ```bash
   --oracle-user "myuser" --oracle-password "mypass" --oracle-dsn "custom-dsn"
   ```

2. **Environment variables**
   ```bash
   export ORACLE_USER="myuser"
   export ORACLE_PASSWORD="mypass"
   export ORACLE_DSN="custom-dsn"
   ```

3. **Default credentials and DSN** (when flags present but empty)
   ```bash
   --oracle-user  # Uses refdb/br#^gox66312sdAB and default QA DSN
   ```

4. **Error** (when no credentials available)
   ```
   [ERROR] Oracle credentials required
   ```

## Comparison with Perl Script

The command-line interface mirrors the Perl script's credential handling:

| Feature | Perl Script | Python Service |
|---------|-------------|----------------|
| Default credentials flag | `--benchmark_db_user` | `--oracle-user` |
| Default username | `refdb` | `refdb` |
| Default password | `br#^gox66312sdAB` | `br#^gox66312sdAB` |
| Custom credentials | `--benchmark_db_user "user" --benchmark_db_pass "pass"` | `--oracle-user "user" --oracle-password "pass"` |
| Environment variables | `BENCHMARK_DB_USER`, `BENCHMARK_DB_PASS` | `ORACLE_USER`, `ORACLE_PASSWORD` |
| DSN parameter | `--benchmark_db_dsn` | `--oracle-dsn` |

## Security Considerations

### Default Credentials

**Pros**:
- Simple configuration
- No credential management needed
- Consistent with Perl script

**Cons**:
- Shared credentials (less auditing granularity)
- Password visible in script code
- Not suitable for high-security environments

**Recommendation**: Use default credentials for:
- Development and QA environments
- Standard deployments with shared service accounts
- Quick testing and proof-of-concept

### Custom Credentials

**Pros**:
- Individual user accountability
- Better audit trail
- Can use stronger passwords
- Can rotate passwords independently

**Cons**:
- More configuration required
- Need credential management system

**Recommendation**: Use custom credentials for:
- Production environments requiring audit trails
- Compliance-driven deployments
- Multi-tenant environments
- High-security requirements

### Best Practices

1. **Use environment variables** for production credentials
   ```bash
   export ORACLE_USER="$(cat /secure/oracle_user.txt)"
   export ORACLE_PASSWORD="$(cat /secure/oracle_password.txt)"
   python run_with_args.py --backend oracle --oracle-dsn DWPRD
   ```

2. **Restrict file permissions** on password files
   ```bash
   chmod 600 /secure/oracle_password.txt
   ```

3. **Use secrets management** in production
   - AWS Secrets Manager
   - HashiCorp Vault
   - Kubernetes Secrets

4. **Avoid command-line passwords** in production
   - Visible in process listings (`ps aux`)
   - Logged in shell history
   - Use environment variables or secrets files instead

## Backward Compatibility

The new command-line interface is fully backward compatible:

### Existing Environment Variable Configuration Still Works

```bash
# Old way (still works)
export PIPELINE_BACKEND=oracle
export ORACLE_DSN=DWPRD
export ORACLE_USER=refdb
export ORACLE_PASSWORD="br#^gox66312sdAB"
uvicorn main:main_app --host 0.0.0.0 --port 8001

# New way (equivalent)
python run_with_args.py \
  --backend oracle \
  --oracle-dsn DWPRD \
  --oracle-user refdb \
  --oracle-password "br#^gox66312sdAB"
```

### Existing Scripts and Deployment Configurations

No changes required to existing deployment scripts. The service can still be started with:

```bash
uvicorn main:main_app --host 0.0.0.0 --port 8001
```

Environment variables will be used as before.

## Troubleshooting

### Issue: "Oracle credentials required" error

**Cause**: No credentials provided via command-line or environment variables

**Solution**: 
```bash
# Use default credentials
python run_with_args.py --backend oracle --oracle-dsn DWPRD --oracle-user

# Or provide custom credentials
python run_with_args.py --backend oracle --oracle-dsn DWPRD \
  --oracle-user "myuser" --oracle-password "mypass"

# Or set environment variables
export ORACLE_USER="myuser"
export ORACLE_PASSWORD="mypass"
python run_with_args.py --backend oracle --oracle-dsn DWPRD
```

### Issue: "Using default Oracle credentials" not appearing in log

**Cause**: The `--oracle-user` flag is not being passed without a value

**Solution**: Ensure the flag has no value after it:
```bash
python run_with_args.py --oracle-user     # Correct (no value)
python run_with_args.py --oracle-user ""  # Incorrect (empty string is a value)
```

### Issue: Connection fails with default credentials

**Cause**: Default credentials may not have access to the database

**Solution**:
1. Verify database user exists: `sqlplus refdb/br#^gox66312sdAB@DWPRD`
2. Check permissions on `pipeline_runs` table
3. Use custom credentials if default account is not configured

### Issue: Want to use defaults but need custom password

**Cause**: Default credentials are all-or-nothing

**Solution**: Use environment variables or explicit command-line arguments:
```bash
export ORACLE_USER="refdb"
export ORACLE_PASSWORD="your_custom_password"
python run_with_args.py --backend oracle --oracle-dsn DWPRD
```

## Help and Documentation

### Get Help

```bash
python run_with_args.py --help
```

### View API Documentation

Once the service is running:
```
http://localhost:8001/docs
```

### Check Service Health

```bash
curl http://localhost:8001/health
```

## Migration from Environment Variables

### Step 1: Test with Command-Line Args

```bash
# Current (environment variables)
export ORACLE_USER="myuser"
export ORACLE_PASSWORD="mypass"
uvicorn main:main_app --port 8001

# New (command-line args)
python run_with_args.py \
  --backend oracle \
  --oracle-dsn DWPRD \
  --oracle-user "myuser" \
  --oracle-password "mypass" \
  --port 8001
```

### Step 2: Update Deployment Scripts

Replace `uvicorn` commands with `run_with_args.py`:

```bash
# Before
uvicorn main:main_app --host 0.0.0.0 --port 8001

# After
python run_with_args.py \
  --backend oracle \
  --oracle-dsn DWPRD \
  --oracle-user \
  --host 0.0.0.0 \
  --port 8001
```

### Step 3: Update Systemd Service (if applicable)

```ini
[Service]
ExecStart=/usr/bin/python3 /app/run_with_args.py \
  --backend oracle \
  --oracle-dsn DWPRD \
  --oracle-user \
  --host 0.0.0.0 \
  --port 8001
```

## Related Documentation

- [Main README](./README.md) - Service overview and features
- [Oracle Benchmark Integration](../docs/oracle_benchmark_integration.md) - Perl script Oracle integration
- [Default Credentials Usage](../DEFAULT_CREDENTIALS_USAGE.md) - Perl script default credentials guide

## Summary

The command-line interface provides:

✅ **Simplified configuration** - One command instead of multiple environment variables  
✅ **Default credentials** - Quick setup with `--oracle-user` flag  
✅ **Flexible credentials** - Command-line, environment variables, or defaults  
✅ **Backward compatible** - Existing configurations still work  
✅ **Consistent with Perl script** - Same credential handling pattern  

Choose the credential method that best fits your environment's security and operational requirements.
