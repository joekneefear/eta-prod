# YAML Configuration Guide for DTS1000 Parser

## Overview

The DTS1000/DTS2000 parser now supports **YAML-based configuration** for custom field extraction. This allows you to define site-specific parsing rules **without modifying code**.

---

## Quick Start

### 1. Basic Usage (No Configuration Needed)

```bash
# Uses default parsing for all fields
python dts1000_juno_translator_enricher.py \
  --infile test_data.xls \
  --out /outbox \
  --site PHXFT \
  --ws_source prod \
  --metadata_source ERT
```

### 2. With YAML Configuration

```bash
# Automatically loads site-specific rules from YAML
python dts1000_juno_translator_enricher.py \
  --infile test_data.xls \
  --out /outbox \
  --site PHXFT \
  --ws_source prod \
  --metadata_source ERT
```

**That's it!** The parser automatically:
1. Looks for `dts1000_custom_parsers.yaml` in resources directory
2. Loads configuration for `PHXFT` site
3. Applies custom extractors defined in YAML

---

## Configuration File

### Default Location

```
scripts/py/resources/dts1000_custom_parsers.yaml
```

### Custom Location

Use `--parser_config` parameter:

```bash
python dts1000_juno_translator_enricher.py \
  --infile test_data.xls \
  --out /outbox \
  --site PHXFT \
  --parser_config /path/to/custom_config.yaml \
  ...
```

---

## YAML File Structure

### Complete Example

```yaml
sites:
  PHXFT:
    # Enable/disable custom parsers
    custom_parsers:
      lot_parser: true
      program_parser: true
      time_parser: true
    
    # Lot ID parsing
    lot_id:
      pattern: '^([A-Z]+)-([A-Z0-9]+)-([A-Z0-9]+)-([A-Z0-9]+)$'
      groups:
        1: PROCESS
        2: PRODUCT
        3: INTERNAL_CONTROL
        4: LOT
      fallback_field: 'LOT'
    
    # Program parsing
    program:
      extract_revision: true
      revision_position: -1
      strip_extension: true
      fallback_program: 'UNKNOWN'
    
    # Timestamp parsing
    timestamp:
      source: 'file_modified'
      format: '%Y/%m/%d %H:%M:%S'
      apply_to:
        - START_TIME
        - END_TIME

defaults:
  custom_parsers:
    lot_parser: false
    program_parser: false
    time_parser: false
```

---

## Configuration Options

### 1. Lot ID Parser

#### Enable/Disable

```yaml
sites:
  SITE_NAME:
    custom_parsers:
      lot_parser: true  # or false
```

#### Pattern Matching

```yaml
lot_id:
  # Regex pattern to match lot ID
  pattern: '^([A-Z]+)-([A-Z0-9]+)-([A-Z0-9]+)-([A-Z0-9]+)$'
  
  # Map regex groups to metadata fields
  groups:
    1: PROCESS          # First group
    2: PRODUCT          # Second group
    3: INTERNAL_CONTROL # Third group
    4: LOT              # Fourth group
  
  # Fallback if pattern doesn't match
  fallback_field: 'LOT'
```

#### Example Patterns

**Pattern 1: PROCESS-DEVICE-CONTROL-LOT**
```yaml
# Matches: FT-FCPF250N65S3L1-F154-HVPFT160003
pattern: '^([A-Z]+)-([A-Z0-9]+)-([A-Z0-9]+)-([A-Z0-9]+)$'
groups:
  1: PROCESS
  2: PRODUCT
  3: INTERNAL_CONTROL
  4: LOT
```

**Pattern 2: PRODUCT_LOT_WAFER**
```yaml
# Matches: DEVICE123_LOT456_W01
pattern: '^([A-Z0-9]+)_([A-Z0-9]+)_([A-Z0-9]+)$'
groups:
  1: PRODUCT
  2: LOT
  3: WAFER
```

**Pattern 3: Simple LOT-WAFER**
```yaml
# Matches: ABC123-W05
pattern: '^([A-Z0-9]+)-W([0-9]+)$'
groups:
  1: LOT
  2: WAFER
```

---

### 2. Program Parser

#### Enable/Disable

```yaml
sites:
  SITE_NAME:
    custom_parsers:
      program_parser: true  # or false
```

#### Configuration

```yaml
program:
  # Extract revision from filename
  extract_revision: true  # or false
  
  # Position of revision character
  # -1 = last char, -2 = second to last, etc.
  revision_position: -1
  
  # Strip file extension before parsing
  strip_extension: true  # or false
  
  # Fallback program name
  fallback_program: 'UNKNOWN'
```

#### Examples

**Example 1: Last Character as Revision**
```yaml
# Input: MyTestProg5.tst
# Output: PROGRAM='MyTestProg', REVISION='5'
program:
  extract_revision: true
  revision_position: -1
  strip_extension: true
```

**Example 2: No Revision Extraction**
```yaml
# Input: MyTestProg.tst
# Output: PROGRAM='MyTestProg', REVISION=''
program:
  extract_revision: false
  strip_extension: true
```

**Example 3: Second to Last Character**
```yaml
# Input: TestProgA1.tst
# Output: PROGRAM='TestProg1', REVISION='A'
program:
  extract_revision: true
  revision_position: -2
  strip_extension: true
```

---

### 3. Timestamp Parser

#### Enable/Disable

```yaml
sites:
  SITE_NAME:
    custom_parsers:
      time_parser: true  # or false
```

#### Configuration

```yaml
timestamp:
  # Source of timestamp
  # Options: 'file_modified', 'excel_date', 'current'
  source: 'file_modified'
  
  # Output format (Python strftime format)
  format: '%Y/%m/%d %H:%M:%S'
  
  # Fields to populate
  apply_to:
    - START_TIME
    - END_TIME
```

#### Source Options

**Option 1: File Modified Time**
```yaml
# Uses file's last modification timestamp
timestamp:
  source: 'file_modified'
  format: '%Y/%m/%d %H:%M:%S'
```

**Option 2: Excel Date Row**
```yaml
# Uses date from Excel file (default behavior)
timestamp:
  source: 'excel_date'
  format: '%Y/%m/%d %H:%M:%S'
```

**Option 3: Current Time**
```yaml
# Uses current system time
timestamp:
  source: 'current'
  format: '%Y/%m/%d %H:%M:%S'
```

#### Format Options

```yaml
# Standard format
format: '%Y/%m/%d %H:%M:%S'  # 2026/01/29 14:30:45

# ISO format
format: '%Y-%m-%dT%H:%M:%S'  # 2026-01-29T14:30:45

# US format
format: '%m/%d/%Y %I:%M:%S %p'  # 01/29/2026 02:30:45 PM

# Date only
format: '%Y/%m/%d'  # 2026/01/29
```

---

## Site-Specific Examples

### Example 1: PHXFT (Phoenix Final Test)

```yaml
sites:
  PHXFT:
    custom_parsers:
      lot_parser: true
      program_parser: true
      time_parser: true
    
    lot_id:
      pattern: '^([A-Z]+)-([A-Z0-9]+)-([A-Z0-9]+)-([A-Z0-9]+)$'
      groups:
        1: PROCESS
        2: PRODUCT
        3: INTERNAL_CONTROL
        4: LOT
      fallback_field: 'LOT'
    
    program:
      extract_revision: true
      revision_position: -1
      strip_extension: true
    
    timestamp:
      source: 'file_modified'
      format: '%Y/%m/%d %H:%M:%S'
```

**Input**:
- Lot: `FT-FCPF250N65S3L1-F154-HVPFT160003`
- Program: `C:\Programs\MyTestProg5.tst`
- File modified: `2026-01-29 14:30:45`

**Output**:
- `PROCESS` = `FT`
- `PRODUCT` = `FCPF250N65S3L1`
- `INTERNAL_CONTROL` = `F154`
- `LOT` = `HVPFT160003`
- `PROGRAM` = `MyTestProg`
- `REVISION` = `5`
- `START_TIME` = `2026/01/29 14:30:45`
- `END_TIME` = `2026/01/29 14:30:45`

---

### Example 2: GRESHAM (Different Pattern)

```yaml
sites:
  GRESHAM:
    custom_parsers:
      lot_parser: true
      program_parser: false
      time_parser: true
    
    lot_id:
      pattern: '^([A-Z0-9]+)_([A-Z0-9]+)_W([0-9]+)$'
      groups:
        1: PRODUCT
        2: LOT
        3: WAFER
      fallback_field: 'LOT'
    
    timestamp:
      source: 'excel_date'
      format: '%Y/%m/%d %H:%M:%S'
```

**Input**:
- Lot: `DEVICE123_LOT456_W05`

**Output**:
- `PRODUCT` = `DEVICE123`
- `LOT` = `LOT456`
- `WAFER` = `05`
- `PROGRAM` = (default parsing)
- Timestamps from Excel file

---

### Example 3: Default Site (No Custom Parsing)

```yaml
sites:
  SITE_DEFAULT:
    custom_parsers:
      lot_parser: false
      program_parser: false
      time_parser: false
```

**Behavior**: Uses standard parser behavior for all fields

---

## Migration from Command-Line Flags

### Old Approach (Command-Line Flags)

```bash
python dts1000_juno_translator_enricher.py \
  --infile test_data.xls \
  --out /outbox \
  --site PHXFT \
  --custom_lot_parser \
  --custom_program_parser \
  --use_file_time \
  ...
```

### New Approach (YAML Configuration)

**1. Create YAML config** (one time):

```yaml
sites:
  PHXFT:
    custom_parsers:
      lot_parser: true
      program_parser: true
      time_parser: true
    # ... configuration details
```

**2. Run script** (simplified):

```bash
python dts1000_juno_translator_enricher.py \
  --infile test_data.xls \
  --out /outbox \
  --site PHXFT \
  ...
```

**Benefits**:
- ✅ No command-line flags needed
- ✅ Configuration is version controlled
- ✅ Easy to modify without code changes
- ✅ Self-documenting with YAML comments

---

## Troubleshooting

### Config File Not Found

**Error**:
```
WARN: Parser config file not found: /path/to/config.yaml
INFO: Using default parsing (no custom extractors)
```

**Solution**:
1. Check file path
2. Verify file exists
3. Use `--parser_config` to specify custom path

---

### Site Not Found in Config

**Log Message**:
```
WARN: Site 'MYSITE' not found in config, using defaults
```

**Solution**:
Add site to YAML:

```yaml
sites:
  MYSITE:
    custom_parsers:
      lot_parser: true
    # ... configuration
```

---

### Invalid Regex Pattern

**Error**:
```
ERROR: Invalid regex pattern in lot_id config: ...
```

**Solution**:
1. Test regex pattern online (regex101.com)
2. Escape special characters: `\.`, `\(`, `\)`
3. Use raw strings in YAML (no escaping needed)

---

### Pattern Doesn't Match

**Behavior**: Falls back to default field

**Debug**:
1. Check pattern against actual lot ID
2. Verify group numbers match
3. Test with simpler pattern first

**Example Debug**:
```yaml
# Start simple
pattern: '^(.+)$'
groups:
  1: LOT

# Then add complexity
pattern: '^([A-Z]+)-(.+)$'
groups:
  1: PROCESS
  2: LOT
```

---

## Best Practices

### 1. Start with Defaults

```yaml
sites:
  NEW_SITE:
    custom_parsers:
      lot_parser: false
      program_parser: false
      time_parser: false
```

Enable custom parsers one at a time.

---

### 2. Test Patterns Incrementally

```yaml
# Step 1: Test basic pattern
pattern: '^(.+)$'

# Step 2: Add structure
pattern: '^([A-Z]+)-(.+)$'

# Step 3: Add full pattern
pattern: '^([A-Z]+)-([A-Z0-9]+)-([A-Z0-9]+)-([A-Z0-9]+)$'
```

---

### 3. Use Comments

```yaml
sites:
  PHXFT:
    # Phoenix Final Test - Updated 2026-01-29
    # Contact: user@example.com
    
    lot_id:
      # Pattern for FT lots: PROCESS-DEVICE-CONTROL-LOT
      # Example: FT-FCPF250N65S3L1-F154-HVPFT160003
      pattern: '^([A-Z]+)-([A-Z0-9]+)-([A-Z0-9]+)-([A-Z0-9]+)$'
```

---

### 4. Version Control

```bash
# Commit YAML changes
git add scripts/py/resources/dts1000_custom_parsers.yaml
git commit -m "Updated PHXFT lot ID pattern"
```

---

### 5. Fallback Fields

Always specify fallback:

```yaml
lot_id:
  pattern: '^...$'
  groups: {...}
  fallback_field: 'LOT'  # Always have a fallback!
```

---

## Summary

### Advantages of YAML Configuration

- ✅ **No code changes** for new sites
- ✅ **Easy to maintain** - edit YAML file
- ✅ **Version controlled** - track changes
- ✅ **Self-documenting** - YAML comments
- ✅ **Site-specific** - different rules per site
- ✅ **Testable** - validate patterns independently

### Quick Reference

| Task | Command |
|------|---------|
| Use default config | No parameters needed |
| Custom config file | `--parser_config /path/to/file.yaml` |
| Add new site | Edit YAML, add site section |
| Disable custom parsing | Set `custom_parsers: false` |
| Test pattern | Use regex101.com |

**Configuration is now data-driven and maintainable!** 🎉
