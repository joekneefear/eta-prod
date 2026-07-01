# Default Credentials Usage Guide

## Overview

The `getCamstarWafer2AssemblyGenealogy.pl` script now supports default Oracle database credentials for simplified configuration. This feature allows you to enable Oracle benchmark logging with minimal command-line arguments.

## Default Credentials

When you pass the `--benchmark_db_user` flag **without a value**, the script automatically uses:

- **Username**: `refdb`
- **Password**: `br#^gox66312sdAB`

## Quick Start

### Minimal Configuration (Recommended)

```bash
perl scripts/getCamstarWafer2AssemblyGenealogy.pl \
  --source_db CEBU \
  --source_warehouse application_prd_wh \
  --source_schema ANALYTICSPRD.FCS \
  --start_hours 2 \
  --end_hours 0 \
  --out_gen ./output/gen \
  --archive_gen ./archive/gen \
  --out_trace ./output/trace \
  --archive_trace ./archive/trace \
  --logfile ./log/getCamstarWafer2AssemblyGenealogy.log \
  --benchmark_log ./log/benchmark.jsonl \
  --benchmark_db_dsn DWPRD \
  --benchmark_db_user \
  --pipeline_name "camstar_wafer2assembly_cebu" \
  --pipeline_type "batch"
```

**Note**: The `--benchmark_db_user` flag has no value after it. This triggers the default credentials.

## How It Works

### Credential Resolution Order

The script resolves credentials in the following order:

1. **Command-line explicit value**: `--benchmark_db_user "username" --benchmark_db_pass "password"`
2. **Environment variables**: `$BENCHMARK_DB_USER` and `$BENCHMARK_DB_PASS`
3. **Default credentials**: If `--benchmark_db_user` flag is present but empty
4. **Skip Oracle**: If no credentials are found, Oracle insert is skipped with a warning

### Code Logic

```perl
# If benchmark_db_user flag is present (even if empty), use default credentials
if (exists($optionsRef->{BENCHMARK_DB_USER}) && length($user) == 0)
{
    $user = "refdb";
    $pass = 'br#^gox66312sdAB';
    INFO("Using default benchmark database credentials (user: $user)");
}
```

## Usage Scenarios

### Scenario 1: Standard Deployment (Use Defaults)

**When to use**: Standard production environment with shared benchmark database

```bash
--benchmark_db_dsn DWPRD \
--benchmark_db_user
```

**Result**: Uses `refdb` / `br#^gox66312sdAB`

### Scenario 2: Custom User (Override Defaults)

**When to use**: Specific user account required for security or auditing

```bash
--benchmark_db_dsn DWPRD \
--benchmark_db_user "pipeline_writer" \
--benchmark_db_pass "custom_password"
```

**Result**: Uses `pipeline_writer` / `custom_password`

### Scenario 3: Environment Variables (Secure Custom)

**When to use**: Custom credentials needed but want to avoid command-line exposure

```bash
export BENCHMARK_DB_USER="secure_user"
export BENCHMARK_DB_PASS="secure_password"

# In script invocation:
--benchmark_db_dsn DWPRD
```

**Result**: Uses `secure_user` / `secure_password` from environment

### Scenario 4: No Oracle (Skip Benchmark DB)

**When to use**: JSONL-only logging, no Oracle database available

```bash
--benchmark_log ./log/benchmark.jsonl
# No --benchmark_db_dsn or --benchmark_db_user
```

**Result**: Only JSONL file is created, no Oracle insert attempted

## Comparison Table

| Method | Command-Line Args | Env Vars | Security | Ease of Use |
|--------|------------------|----------|----------|-------------|
| **Default Credentials** | `--benchmark_db_user` | None | Medium | ⭐⭐⭐⭐⭐ Easiest |
| **Explicit Command-Line** | `--benchmark_db_user "user" --benchmark_db_pass "pass"` | None | Low (visible in ps) | ⭐⭐⭐ Moderate |
| **Environment Variables** | `--benchmark_db_dsn DWPRD` | `BENCHMARK_DB_USER`, `BENCHMARK_DB_PASS` | High | ⭐⭐⭐⭐ Easy |
| **JSONL Only** | `--benchmark_log file.jsonl` | None | N/A | ⭐⭐⭐⭐⭐ Easiest |

## Security Considerations

### Default Credentials

**Pros**:
- Simple configuration
- No credential management needed
- Consistent across deployments

**Cons**:
- Shared credentials (less auditing granularity)
- Password visible in script code
- Not suitable for high-security environments

**Recommendation**: Use default credentials for:
- Development and QA environments
- Standard production deployments with shared service accounts
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

## Migration Path

### From JSONL-Only to Oracle with Defaults

**Step 1**: Add Oracle DSN and default credentials flag
```bash
# Before
--benchmark_log ./log/benchmark.jsonl

# After (dual mode)
--benchmark_log ./log/benchmark.jsonl \
--benchmark_db_dsn DWPRD \
--benchmark_db_user
```

**Step 2**: Monitor both outputs for consistency

**Step 3**: Optionally remove JSONL once Oracle is stable
```bash
# Oracle only
--benchmark_db_dsn DWPRD \
--benchmark_db_user
```

### From Default to Custom Credentials

**Step 1**: Set environment variables
```bash
export BENCHMARK_DB_USER="custom_user"
export BENCHMARK_DB_PASS="custom_password"
```

**Step 2**: Remove the `--benchmark_db_user` flag (or provide explicit value)
```bash
# Before (default)
--benchmark_db_dsn DWPRD \
--benchmark_db_user

# After (custom via env vars)
--benchmark_db_dsn DWPRD

# Or (custom via command line)
--benchmark_db_dsn DWPRD \
--benchmark_db_user "custom_user" \
--benchmark_db_pass "custom_password"
```

## Troubleshooting

### Issue: "Using default benchmark database credentials" not appearing in log

**Cause**: The `--benchmark_db_user` flag is not being passed, or has an explicit value

**Solution**: Ensure the flag is present without a value:
```bash
--benchmark_db_user    # Correct (no value)
--benchmark_db_user "" # Incorrect (empty string is still a value)
```

### Issue: Oracle insert fails with authentication error

**Cause**: Default credentials may not have access to the database

**Solution**: 
1. Verify database user exists: `sqlplus refdb/br#^gox66312sdAB@DWPRD`
2. Check permissions: `SELECT * FROM user_tab_privs WHERE table_name = 'PIPELINE_RUNS';`
3. Use custom credentials if default account is not configured

### Issue: Want to use defaults but also need custom password

**Cause**: Default credentials are all-or-nothing

**Solution**: Use environment variables or explicit command-line arguments:
```bash
export BENCHMARK_DB_USER="refdb"
export BENCHMARK_DB_PASS="your_custom_password"

# Then omit --benchmark_db_user flag entirely
--benchmark_db_dsn DWPRD
```

## Best Practices

1. **Development/QA**: Use default credentials for simplicity
2. **Production**: Evaluate security requirements before choosing default vs. custom
3. **Dual Mode**: Keep JSONL logging during initial Oracle rollout
4. **Monitoring**: Check logs for "Using default benchmark database credentials" message
5. **Documentation**: Document which credentials are used in each environment
6. **Testing**: Test with default credentials in non-production first
7. **Rotation**: If using defaults, ensure password rotation is coordinated across all pipelines

## Examples by Environment

### Development Environment
```bash
# Simple, use defaults
perl getCamstarWafer2AssemblyGenealogy.pl \
  --benchmark_db_dsn DWDEV \
  --benchmark_db_user \
  [... other options ...]
```

### QA Environment
```bash
# Dual mode for validation
perl getCamstarWafer2AssemblyGenealogy.pl \
  --benchmark_log ./log/benchmark.jsonl \
  --benchmark_db_dsn DWQA \
  --benchmark_db_user \
  [... other options ...]
```

### Production Environment (Standard)
```bash
# Use defaults if approved
perl getCamstarWafer2AssemblyGenealogy.pl \
  --benchmark_db_dsn DWPRD \
  --benchmark_db_user \
  [... other options ...]
```

### Production Environment (High Security)
```bash
# Use custom credentials via env vars
export BENCHMARK_DB_USER="pipeline_prod_writer"
export BENCHMARK_DB_PASS="$(cat /secure/oracle_password.txt)"

perl getCamstarWafer2AssemblyGenealogy.pl \
  --benchmark_db_dsn DWPRD \
  [... other options ...]
```

## Summary

The default credentials feature provides a balance between ease of use and functionality:

✅ **Simplifies configuration** - One flag instead of managing credentials  
✅ **Backward compatible** - Existing pipelines unaffected  
✅ **Flexible** - Can override with custom credentials anytime  
✅ **Non-blocking** - Failures don't stop pipeline execution  
✅ **Documented** - Clear logging when defaults are used  

Choose the credential method that best fits your environment's security and operational requirements.
