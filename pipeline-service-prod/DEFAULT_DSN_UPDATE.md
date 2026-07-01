# Default DSN Update Summary

## Change

Updated the default Oracle DSN to use the QA database:

**New Default DSN**: `exnqa-db.onsemi.com:1740/EXNQA.onsemi.com`

## Impact

### Simplest Usage Now Requires No DSN Parameter

**Before:**
```bash
python run_with_args.py --backend oracle --oracle-dsn DWPRD --oracle-user
```

**After:**
```bash
python run_with_args.py --backend oracle --oracle-user
```

This automatically connects to the QA database with default credentials.

### Quick Start Script Updated

**Before:**
```bash
./start_with_defaults.sh DWPRD 8001
```

**After:**
```bash
./start_with_defaults.sh  # Uses QA database by default
```

Or specify a custom DSN:
```bash
./start_with_defaults.sh DWPRD 8001
```

## Default Configuration

When using `--oracle-user` without other parameters, the service now uses:

| Parameter | Default Value |
|-----------|---------------|
| **DSN** | `exnqa-db.onsemi.com:1740/EXNQA.onsemi.com` |
| **Username** | `refdb` |
| **Password** | `br#^gox66312sdAB` |
| **Table** | `pipeline_runs` |
| **Port** | `8001` |

## Usage Examples

### 1. Simplest - All Defaults (QA Database)

```bash
python run_with_args.py --backend oracle --oracle-user
```

### 2. Production Database with Default Credentials

```bash
python run_with_args.py --backend oracle --oracle-dsn DWPRD --oracle-user
```

### 3. Custom DSN and Credentials

```bash
python run_with_args.py --backend oracle \
  --oracle-dsn "//prod-db.example.com:1521/PRODDB" \
  --oracle-user "prod_user" \
  --oracle-password "prod_pass"
```

### 4. Environment Variables (Custom DSN)

```bash
export ORACLE_DSN="DWPRD"
export ORACLE_USER="myuser"
export ORACLE_PASSWORD="mypass"
python run_with_args.py --backend oracle
```

## Backward Compatibility

✅ **Fully backward compatible** - All existing configurations still work:

- Explicit DSN parameters override the default
- Environment variables override the default
- Existing scripts with `--oracle-dsn` parameter unchanged

## Files Updated

1. **`run_with_args.py`**
   - Changed `--oracle-dsn` default from `None` to `exnqa-db.onsemi.com:1740/EXNQA.onsemi.com`
   - Removed DSN requirement check (now has default)
   - Updated help text and examples

2. **`start_with_defaults.sh`**
   - Changed default DSN from `DWPRD` to `exnqa-db.onsemi.com:1740/EXNQA.onsemi.com`

3. **`CLI_USAGE.md`**
   - Updated all examples to show default DSN usage
   - Added note about default DSN in command-line options section
   - Updated credential resolution order to include default DSN

4. **`CLI_QUICKSTART.txt`**
   - Updated simplest usage example
   - Added default values section
   - Updated all usage examples

5. **`README.md`**
   - Updated quick start examples
   - Updated configuration examples

## Benefits

✅ **Simpler for QA/Development**: No need to specify DSN for testing  
✅ **Safer Default**: Points to QA database, not production  
✅ **Consistent with Best Practices**: Test environment as default  
✅ **Still Flexible**: Easy to override for production use  
✅ **Backward Compatible**: Existing configurations unchanged  

## Migration Guide

### For QA/Development Users

**No changes needed!** The new default makes it even simpler:

```bash
# Old way
python run_with_args.py --backend oracle --oracle-dsn EXNQA --oracle-user

# New way (simpler)
python run_with_args.py --backend oracle --oracle-user
```

### For Production Users

**No changes needed!** Continue specifying production DSN:

```bash
# Still works exactly the same
python run_with_args.py --backend oracle --oracle-dsn DWPRD --oracle-user
```

### For Environment Variable Users

**No changes needed!** Environment variables still override defaults:

```bash
export ORACLE_DSN="DWPRD"
export ORACLE_USER="prod_user"
export ORACLE_PASSWORD="prod_pass"
python run_with_args.py --backend oracle
```

## Testing

### Test Default DSN

```bash
python run_with_args.py --backend oracle --oracle-user
# Should connect to: exnqa-db.onsemi.com:1740/EXNQA.onsemi.com
```

### Test Custom DSN Override

```bash
python run_with_args.py --backend oracle --oracle-dsn DWPRD --oracle-user
# Should connect to: DWPRD
```

### Test Environment Variable Override

```bash
export ORACLE_DSN="CUSTOM_DSN"
python run_with_args.py --backend oracle --oracle-user
# Should connect to: CUSTOM_DSN
```

## Rationale

1. **QA as Default**: Safer to default to test environment rather than production
2. **Simplicity**: Reduces required parameters for common use case (development/testing)
3. **Explicit Production**: Forces explicit DSN specification for production use
4. **Consistency**: Matches common practice of defaulting to non-production environments

## Related Documentation

- [CLI Usage Guide](./CLI_USAGE.md) - Complete command-line interface documentation
- [CLI Quick Start](./CLI_QUICKSTART.txt) - Quick reference
- [Main README](./README.md) - Service overview

---

**Updated**: March 2, 2026  
**Default DSN**: `exnqa-db.onsemi.com:1740/EXNQA.onsemi.com` (QA Database)
