# Comparison: DTS1k2k vs INNO FT XLSX Parser Configuration Approach

## Overview
Both scripts use YAML-based parser configuration, but with **different timing strategies**. Understanding these differences is important for consistency.

---

## Side-by-Side Comparison

### DTS1k2k Approach (shedcl_ft_dts1k2k_xls_translator.py)

```python
# 1. Get site early
site = params.get('site', 'SHEDCL')

# 2. Configure parser BEFORE parsing
parser_config = configure_parser_from_yaml(params, site)

# 3. Initialize parser with config
parser = Dts1k2kXlsParser(config=parser_config, pplogger=pplogger)

# 4. Parse file (config already loaded)
model = parser.parse_to_model(output)
```

**Flow:**
1. Extract site from CLI (early)
2. Load parser config using site
3. Create parser with config
4. Parse file with configured parser

---

### INNO FT XLSX Approach (inno_ft_xlsx_sts8200_enricher.py)

```python
# 1. Parse XLSX (without config, to get lot)
parser = InnoFtXlsxSts8200Parser(pplogger=pplogger)
model = parser.parse_to_model(working_file)

# 2. Get lot from parsed model
pplogger.set_lot(model.header.LOT)

# 3. Determine site
site = site_arg if site_arg else "DEFAULT"

# 4. Load parser config using site
parser_config = InnoFtXlsxSts8200ParserConfig(
    config_file=parser_config_file, 
    site=site
)

# 5. Re-parse with configured parser
parser = InnoFtXlsxSts8200Parser(config=parser_config, pplogger=pplogger)
model = parser.parse_to_model(working_file)
```

**Flow:**
1. Parse with default parser (to extract lot)
2. Set lot in PPLogger
3. Determine site (from CLI or DEFAULT)
4. Load parser config using determined site
5. Re-parse with configured parser

---

## Key Differences

| Aspect | DTS1k2k | INNO FT XLSX |
|--------|---------|-------------|
| **Site Source** | CLI argument only | CLI arg OR inferred from lot (fallback) |
| **Site Timing** | Known immediately | Determined after initial parse |
| **Parser Config** | Loaded once, before parsing | Loaded twice: before then after site determination |
| **Parsing Phases** | Single-phase | Two-phase (default then configured) |
| **Complexity** | Simpler (1 parse) | More complex (2 parses) |
| **Flexibility** | Requires `--site` CLI arg | Works without `--site` using DEFAULT |
| **Efficiency** | More efficient (1 parse) | Less efficient (2 parses) |

---

## Why The Approaches Differ

### DTS1k2k: Why Single-Phase Works
- **Site is mandatory:** `site = params.get('site', 'SHEDCL')`
- Site comes from CLI arguments, not data
- Parser config can be loaded immediately
- Single parse is sufficient

### INNO FT XLSX: Why Two-Phase Is Needed
- **Site is optional:** `site = site_arg if site_arg else "DEFAULT"`
- Site can come from CLI OR be determined from data
- Need to extract LOT first to determine site
- Must re-parse to apply site-specific field mappings

---

## Advantages & Disadvantages

### DTS1k2k Approach (Single-Phase)

**✓ Advantages:**
- More efficient: one parse only
- Simpler code flow
- Easier to understand
- Better performance for large files

**✗ Disadvantages:**
- Requires explicit `--site` argument
- Cannot auto-detect site from data
- Less flexible for optional parameters

### INNO FT XLSX Approach (Two-Phase)

**✓ Advantages:**
- Site can be optional (DEFAULT fallback)
- Auto-detectable from file content
- More flexible configuration
- Works with or without explicit site parameter

**✗ Disadvantages:**
- Less efficient: parses file twice
- More complex code flow
- Harder to understand
- Slower for large files
- Sets lot twice (minor inefficiency)

---

## When To Use Each Approach

### Use DTS1k2k Single-Phase When:
- Site is always provided via CLI
- Site is external metadata (not in file)
- Performance is critical
- File size is large
- Single parse is sufficient

### Use INNO Two-Phase When:
- Site can be optional
- Site can be inferred from file
- Flexibility is more important than performance
- File size is manageable
- Need to support data-driven site determination

---

## Recommendation For Consistency

If you want to align INNO with DTS1k2k approach, you could:

### Option 1: Make Site Mandatory
```python
# Require --site argument
site = params.get('site')
if not site:
    Log.ERROR("Error: --site is required")
    Util.dp_exit(1, pplogger=pplogger, error="--site is required")

# Then use DTS1k2k single-phase approach
parser_config = InnoFtXlsxSts8200ParserConfig(config_file=parser_config_file, site=site)
parser = InnoFtXlsxSts8200Parser(config=parser_config, pplogger=pplogger)
model = parser.parse_to_model(working_file)
```

### Option 2: Pre-extract Lot via Simpler Parser
```python
# Use a lightweight extraction if site is optional
simple_parser = InnoFtXlsxSts8200Parser()  # Default parser
model = simple_parser.parse_to_model(working_file)
lot_id = model.header.LOT

# Determine site from lot if not provided
site = site_arg if site_arg else determine_site_from_lot(lot_id)

# Then single parse with config
parser_config = InnoFtXlsxSts8200ParserConfig(config_file=parser_config_file, site=site)
parser = InnoFtXlsxSts8200Parser(config=parser_config, pplogger=pplogger)
model = parser.parse_to_model(working_file)
```

### Option 3: Keep Current Approach (Two-Phase)
This is the current approach. It's more flexible but less efficient. It's acceptable if:
- File sizes are small to medium
- Flexibility matters more than performance
- Auto-detection from file is important

---

## Current State

**INNO is using: Option 3 (Two-Phase)**
- Not identical to DTS1k2k
- Different requirements justify different approach
- Both are valid architectural choices

**To Make Identical to DTS1k2k:**
Would require changing to Option 1 (make site mandatory)

---

## Code Comparison Summary

```
DTS1k2k:
┌─────────────────────┐
│ Get site from CLI  │
└──────────┬──────────┘
           │
┌──────────v──────────┐
│ Load parser config  │
└──────────┬──────────┘
           │
┌──────────v──────────┐
│ Parse with config   │
└─────────────────────┘

INNO:
┌──────────────────────┐
│ Parse (default)      │
└──────────┬───────────┘
           │
┌──────────v───────────┐
│ Get site (from data) │
└──────────┬───────────┘
           │
┌──────────v───────────┐
│ Load parser config   │
└──────────┬───────────┘
           │
┌──────────v───────────┐
│ Re-parse (configured)│
└──────────────────────┘
```

---

## Conclusion

**Both approaches are valid**, but serve different use cases:

- **DTS1k2k:** Optimized for known, external site specification
- **INNO FT XLSX:** Optimized for optional site with data-driven fallback

The INNO approach is more **flexible and resilient** at the cost of being slightly less efficient. This is a reasonable tradeoff for handling variable site information sources.

If consistency with DTS1k2k is desired, migrate INNO to Option 1 (require --site) and eliminate the two-phase parsing.
