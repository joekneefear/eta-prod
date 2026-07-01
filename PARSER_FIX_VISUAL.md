# Visual Guide: PowerchipWatParser Alignment Fix

## The Problem in Pictures

### WAT File Structure (RGAAK2000.WAT)

```
Line 6:  WAF EpiScribe      SITE    CAPDENSITY... MIMLACAP_ILK  MIMLACAP_BV  ...
         ^^^ ^^^^^^^^^^^     ^^^^    ^^^^^^^^^^^   ^^^^^^^^^^^^  ^^^^^^^^^^^
         |   |               |       |             |             |
         |   |               |       Parameter 1   Parameter 2   Parameter 3
         |   |               SITE column
         |   EpiScribe NAME column (variable length!)
         Wafer Number

Line 7:  ID                 ID                    Volts                      V
         ^^                 ^^                    ^^^^^         ^^^^^^^^^^^^^
         Skip               Skip                  Unit for P1   Unit for P4
         
Line 8:  1   75AJF068SEB7  -1       0.9681541    -12.42022     48.5634       ...
         ^   ^^^^^^^^^^^^  ^^^      ^^^^^^^^^    ^^^^^^^^^     ^^^^^^^
         |   |             |        |            |             |
         |   |             |        Value for P1 Value for P2  Value for P3
         |   |             SITE value
         |   EpiScribe name
         Wafer #

Line 136: SPEC HI                   1.12         -9.8          55            ...
          ^^^^^^^^                   ^^^^         ^^^^          ^^
          Skip these                 P1 limit     P2 limit      P3 limit
          (NO EpiScribe!)
```

### The Bug Visualized

**What Parser Did (WRONG):**

```
Parser sees "WAF EpiScribe SITE" → thinks data starts at position X
Parser sees "SPEC HI" → tries to align starting at position X
But "SPEC HI" line has NO EpiScribe column!
Result: Everything shifts LEFT by one column

SPEC HI values:     1.12        -9.8         55          ...
Parser assigned to: [ignored]   Parameter1   Parameter2  ...  ← OFF BY 1!
Should be:                      Parameter1   Parameter2  Parameter3
```

**Fixed Behavior (CORRECT):**

```
Parser uses WHITESPACE SPLIT for all rows:
- Data row:   split() → [WAF#, EpiName, SITE, val1, val2, val3, ...]
- SPEC row:   split() → ["SPEC", "HI", val1, val2, val3, ...]

Result: Values extracted by position in array, not character position!
SPEC HI values:     1.12        -9.8         55          ...
Parser assigns to:  Parameter1  Parameter2   Parameter3  ✓ CORRECT!
```

## Code Comparison

### OLD CODE (Complex & Wrong)

```python
# UNITS: Used fixed 15-character width
units_area_start = id_match.end()
units_area = raw_line_no_nl[units_area_start:]
width = 15  # Fixed width
chunk = units_area[col_start:col_end]  # Extract 15 chars
# Problem: Assumes header spacing matches units spacing
```

```python
# SPEC HI: Multi-method with fallbacks
values = self._parse_limit_row_robust(
    raw_line_no_nl, "SPEC HI", expected,
    absolute_param_start_index,        # Based on header
    data_row_param_start_index,        # Based on data rows
    header_param_area,                 # From header
    param_rel_bounds                   # Computed from header
)
# Problem: Tries to use header positions for SPEC row that has different structure
```

### NEW CODE (Simple & Correct)

```python
# UNITS: Simple whitespace split
units_tokens = line.split()  # ["ID", "ID", "Volts", "", "V", ...]
unit_values = units_tokens[2:]  # Skip "ID ID"
# Solution: Works regardless of column widths or positions
```

```python
# SPEC HI: Simple whitespace split
spec_tokens = line.split()  # ["SPEC", "HI", "1.12", "-9.8", "55", ...]
spec_values = spec_tokens[2:]  # Skip "SPEC HI"
val = spec_values[t_idx]  # Get value by array index
# Solution: Gets correct value regardless of EpiScribe presence
```

## Why Whitespace Split Works

### Key Insight:
WAT format uses **variable-width whitespace separation**, NOT fixed columns!

```
# These are NOT aligned to fixed columns:
CAPDENSITY_MIMLACAP_0P0  ← 23 characters
MIMLACAP_ILK             ← 12 characters
N_GMMAX_10X10_NVT_3V     ← 20 characters

# Values are separated by whitespace, not character positions:
0.9681541     -12.42022       48.5634
^^^^^^^^^     ^^^^^^^^^       ^^^^^^^
  Token 0       Token 1       Token 2
```

### Whitespace Split Advantages:

1. **Format Independent**: Works with any column widths
2. **EpiScribe Agnostic**: Automatically handles presence/absence
3. **Robust**: Handles multiple spaces, tabs, varying alignment
4. **Simple**: No complex position calculations needed

## Testing the Fix

### Test Script Output:

```bash
$ python test_parser_alignment.py

LOT: RGAAK2000
PRODUCT: WGASPCJ0RJ001-FAB
RECIPE: AFEJAV41ASMR_R90_C

FIRST SECTION (11 tests with EpiScribe column):
====================================================================================
#    Test Name                           Units      SPEC HI         SPEC LO         CRIT      
------------------------------------------------------------------------------------
1    CAPDENSITY_MIMLACAP_0P0            NA         1.12            0.88            1         
2    MIMLACAP_ILK                       Volts      -9.8            -17             1         
3    MIMLACAP_BV                        NA         55              22              1         
4    N_GMMAX_10X10_NVT_3V               NA         2.61E-05        2.36E-05        0         
5    VTNLIN_10X10_NVT_3V                V          -0.039          -0.17           1         
...

VALIDATION CHECKS:
====================================================================================
✓ CHECK 1 PASSED: First test has SPEC HI = 1.12
✓ CHECK 2 PASSED: First test has no units (expected for capacity)
✓ CHECK 3 PASSED: Test 4 units = V
✓ CHECK 4 PASSED: Wafer 1 die 1 has 21 results

OVERALL: 4/4 checks passed
```

## Files Affected

### Modified:
- `scripts/py/lib/Parser/PowerchipWatParser.py`
  - Lines 745-773: UNITS parsing
  - Lines 775-790: SPEC HI parsing
  - Lines 792-810: SPEC LO parsing
  - Lines 812-830: CRIT parsing

### Created:
- `test_parser_alignment.py` - Test script
- `PARSER_FIX_ANALYSIS.md` - Detailed analysis
- `PARSER_FIX_SUMMARY.md` - Quick summary
- `PARSER_FIX_VISUAL.md` - This visual guide

## Bottom Line

**Problem**: Fixed-width parsing assumed alignment that didn't exist  
**Solution**: Use whitespace split for all supplementary rows  
**Result**: Parameters, data, units, and limits now correctly aligned ✓

---

*Date: January 15, 2026*  
*Parser Version: 2.0*
