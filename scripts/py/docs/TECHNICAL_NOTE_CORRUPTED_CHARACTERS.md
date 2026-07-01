# Technical Note: Corrupted Characters in XML

## Issue Identification

When opening XML files in VSCode, you may see characters displayed as:
```
UserText="EM☐EM☐EM☐EM☐EM☐EM☐EM☐EM☐EM☐"
```

Where "EM" appears with error box symbols (☐).

## Root Cause

These are **invalid UTF-8 byte sequences** or **corrupted characters** that violate the XML 1.0 specification.

### What They Likely Are

1. **ESC Control Character (0x1B)**
   - Often appears as "EM" in text editors
   - Part of ANSI escape sequences
   - Not allowed in XML 1.0

2. **Other Control Characters**
   - Characters in range 0x00-0x1F (except tab, newline, CR)
   - Characters like 0x7F (DEL)
   - Invalid in XML attribute values

3. **Corrupted UTF-8 Sequences**
   - Incomplete multi-byte UTF-8 characters
   - Invalid byte combinations
   - Encoding conversion errors

4. **Source System Issues**
   - Test equipment outputting raw terminal codes
   - Encoding mismatch during data export
   - Binary data mixed with text

## XML 1.0 Valid Characters

According to XML 1.0 specification, valid characters are:

```
#x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
```

In plain terms:
- Tab (0x09) ✓
- Newline (0x0A) ✓
- Carriage Return (0x0D) ✓
- Space through most Unicode (0x20-0xD7FF) ✓
- Private use area (0xE000-0xFFFD) ✓
- Supplementary planes (0x10000-0x10FFFF) ✓

**NOT allowed:**
- Control characters 0x00-0x08 ✗
- Control character 0x0B (vertical tab) ✗
- Control character 0x0C (form feed) ✗
- Control characters 0x0E-0x1F ✗ ← **This includes ESC (0x1B)**
- DEL character 0x7F ✗

## Why This Causes Parsing Errors

XML parsers strictly enforce the character set rules. When they encounter an invalid character:

```python
xml.etree.ElementTree.ParseError: not well-formed (invalid token): line 4, column 331
```

The parser stops immediately at the first invalid character.

## How the Sanitizer Fixes It

### Step 1: Encoding Cleanup
```python
# Replace invalid UTF-8 sequences
sanitized = sanitized.encode('utf-8', errors='replace').decode('utf-8', errors='replace')
# Remove replacement character
sanitized = sanitized.replace('\ufffd', '')
```

### Step 2: Character Filtering
```python
def is_valid_xml_char(char):
    codepoint = ord(char)
    return (
        codepoint == 0x09 or  # tab
        codepoint == 0x0A or  # newline
        codepoint == 0x0D or  # carriage return
        (0x20 <= codepoint <= 0xD7FF) or
        (0xE000 <= codepoint <= 0xFFFD) or
        (0x10000 <= codepoint <= 0x10FFFF)
    )

# Filter out invalid characters
sanitized = ''.join(char if is_valid_xml_char(char) else '' for char in sanitized)
```

### Result
```xml
Before: <Lot UserText="EM☐EM☐EM☐EM☐EM☐" ...>
After:  <Lot UserText="" ...>
```

All invalid characters are removed, leaving a clean (though empty) attribute value.

## Common Sources of These Characters

### 1. Test Equipment Output
Test equipment may output ANSI escape sequences for terminal formatting:
```
\x1B[31m  ← Red color code
\x1B[0m   ← Reset code
```

### 2. Serial Communication
Raw serial port data may include control characters:
```
\x02  ← STX (Start of Text)
\x03  ← ETX (End of Text)
\x1B  ← ESC
```

### 3. Encoding Conversion Errors
Converting between encodings (e.g., Shift-JIS → UTF-8) can produce invalid sequences if not done correctly.

### 4. Copy-Paste Issues
Copying data from terminals or legacy systems may include hidden control characters.

## Diagnostic Information

When the sanitizer encounters these characters, it logs:

```
ERROR: XML Parse Error at line 4, column 331
ERROR: Character at error position: '\x1b' (ord=27)
ERROR: Snippet: ...UserText="EM☐EM☐" OperatorName="HTTVXF"...
ERROR:                    ^
```

This shows:
- **Character value**: `\x1b` (hexadecimal notation)
- **ASCII code**: `27` (decimal)
- **Character name**: ESC (Escape)
- **Location**: Exact position in the file

## Prevention Strategies

### 1. Fix at Source
Update test equipment configuration to:
- Disable ANSI escape sequences
- Use plain text output
- Ensure proper UTF-8 encoding

### 2. Pre-Processing
Add a pre-processing step before XML generation:
```python
# Remove control characters before creating XML
clean_text = ''.join(c for c in raw_text if ord(c) >= 32 or c in '\t\n\r')
```

### 3. Proper Encoding
Ensure consistent encoding throughout the pipeline:
- Test equipment → UTF-8
- Data export → UTF-8
- XML generation → UTF-8

### 4. Validation
Add validation before XML generation:
```python
import re
# Check for invalid characters
if re.search(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', text):
    # Clean or reject the data
    pass
```

## Impact on Data

### What's Lost
- The corrupted characters themselves (which were likely meaningless anyway)
- Any formatting information they represented

### What's Preserved
- All valid text content
- All other attributes
- Complete test data
- Metadata

### Example
```
Original (corrupted):
  UserText="EM☐EM☐EM☐EM☐EM☐"
  
After sanitization:
  UserText=""
  
Impact: Empty UserText field, but all other data intact
```

## Routing Decision

Files with corrupted characters are routed to **SANDBOX** because:

1. **Data Quality Concern**: Presence of invalid characters indicates potential data quality issues
2. **Source System Issue**: Suggests problems with test equipment or data export
3. **Safety Measure**: Allows review before promoting to production
4. **Traceability**: Maintains audit trail of problematic files

## Monitoring Recommendations

### Track Frequency
Monitor how often files contain corrupted characters:
```sql
SELECT COUNT(*) 
FROM processing_log 
WHERE log_message LIKE '%invalid characters%'
```

### Identify Patterns
Look for patterns in affected files:
- Specific test equipment
- Specific time periods
- Specific products or lots
- Specific operators

### Alert Thresholds
Set alerts if:
- >5% of files have corrupted characters
- Specific equipment consistently produces bad data
- Sudden increase in corrupted files

## Resolution Steps

### Immediate (Automated)
1. Sanitizer removes invalid characters ✓
2. File processes successfully ✓
3. Routes to SANDBOX ✓
4. Output generated ✓

### Short-term (Manual)
1. Review SANDBOX files
2. Identify common patterns
3. Investigate source systems
4. Implement targeted fixes

### Long-term (Preventive)
1. Update test equipment configuration
2. Improve data export processes
3. Add validation at source
4. Implement encoding standards

## Technical Details

### Character Encoding Basics

**UTF-8 Encoding:**
- 1 byte: 0x00-0x7F (ASCII compatible)
- 2 bytes: 0xC0-0xDF + 0x80-0xBF
- 3 bytes: 0xE0-0xEF + 2 continuation bytes
- 4 bytes: 0xF0-0xF7 + 3 continuation bytes

**Invalid Sequences:**
- Incomplete multi-byte sequences
- Invalid continuation bytes
- Overlong encodings
- Surrogate pairs in UTF-8

### ESC Character Details

**ESC (Escape) - 0x1B:**
- ASCII control character
- Used in ANSI escape sequences
- Common in terminal emulators
- NOT valid in XML 1.0

**ANSI Escape Sequence Example:**
```
\x1B[31mRed Text\x1B[0m
 ↑                ↑
ESC              ESC
```

Both ESC characters (0x1B) are invalid in XML.

## Summary

The "EM☐" characters you see in VSCode are **corrupted/invalid characters** (likely ESC 0x1B) that violate XML 1.0 specification. The enhanced sanitizer:

1. ✓ Detects these characters
2. ✓ Shows diagnostic information
3. ✓ Removes them automatically
4. ✓ Continues processing
5. ✓ Routes to SANDBOX
6. ✓ Generates output file

**No manual intervention required** - the system handles it automatically while maintaining data quality through appropriate routing.
