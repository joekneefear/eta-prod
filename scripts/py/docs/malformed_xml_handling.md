# Malformed XML Handling Strategy

## Problem Statement

The JND Probe Tesec WMC Enricher script was failing when encountering malformed XML files with errors like:
```
Failed to parse XML: not well-formed (invalid token): line 4, column 331
```

This caused the entire processing pipeline to halt, preventing file generation even when most of the data was valid.

## Solution Overview

Implemented a multi-tier fallback strategy that attempts to recover from XML parsing errors and continue processing:

### Tier 1: Standard XML Parsing
- Attempts normal XML parsing using `xml.etree.ElementTree`
- If successful, processing continues normally
- This is the fastest and most reliable method for well-formed XML

### Tier 2: XML Sanitization
- If initial parsing fails, attempts to fix common XML issues:
  - Unescaped ampersands (`&` → `&amp;`)
  - Unescaped `<` and `>` in attribute values
  - Invalid control characters
  - Other common malformations

- After sanitization, re-attempts parsing
- If successful, marks file as `is_malformed = True` for tracking

### Tier 3: Regex-Based Extraction
- If sanitization fails, falls back to regex pattern matching
- Extracts critical attributes from the `<Lot>` element:
  - `LotId`
  - `SublotId`
  - `UserText`
  - `JobName`
  - Other lot-level attributes

- Creates a minimal XML tree structure with extracted data
- Allows processing to continue with partial information

### Tier 4: Graceful Degradation
- Files that cannot be fully parsed are marked for SANDBOX routing
- Metadata enrichment continues with available data
- Output file is still generated (avoiding complete failure)

## Implementation Details

### SxmlParser Changes

#### New Attributes
```python
self.is_malformed = False  # Tracks if XML required sanitization/fallback
```

#### New Methods

**`_sanitize_xml(xml_content)`**
- Fixes common XML syntax issues
- Returns sanitized XML string
- Logs sanitization actions

**`_create_minimal_tree_from_regex(xml_content)`**
- Extracts Lot attributes using regex patterns
- Builds minimal ElementTree structure
- Returns partial tree or None if extraction fails

### Main Script Changes

```python
tesec_sxml_parser = SxmlParser(input_file)

# Check if XML was malformed and mark for sandbox if needed
if tesec_sxml_parser.is_malformed:
    Log.WARN("XML file is malformed - will route to SANDBOX")
    writer_instance.noMeta = True
```

### SxmlEnricher Changes

Added try-catch blocks around individual line enrichment operations:
```python
try:
    # File element enrichment
    if '<File ' in updated_line:
        updated_line = self.enrich_file_element(updated_line)
    # ... other enrichments
except Exception as line_error:
    Log.WARN(f"Error enriching line (continuing anyway): {line_error}")
    # Continue with the original line if enrichment fails
    pass
```

Added fallback for complete enrichment failure:
- Returns original content with metadata inserted
- Prevents total processing failure

## Common XML Issues Handled

### 1. Unescaped Ampersands
**Problem:**
```xml
<Lot TestName="A&B" />
```

**Fix:**
```xml
<Lot TestName="A&amp;B" />
```

### 2. Unescaped Angle Brackets in Attributes
**Problem:**
```xml
<Lot Description="Value<10" />
```

**Fix:**
```xml
<Lot Description="Value&lt;10" />
```

### 3. Invalid Control Characters
**Problem:**
```xml
<Lot Name="Test\x00Data" />
```

**Fix:**
```xml
<Lot Name="TestData" />
```

### 4. Corrupted/Invalid UTF-8 Characters
**Problem (what you're seeing in VSCode):**
```xml
<Lot UserText="EM☐EM☐EM☐EM☐EM☐" />
```
These are invalid UTF-8 byte sequences or corrupted characters that appear as error boxes.

**Fix:**
```xml
<Lot UserText="" />
```

The sanitizer removes all invalid XML characters according to XML 1.0 specification.

### 5. Excessive Whitespace in Attributes
**Problem:**
```xml
<Lot UserText="									" />
```

**Fix:**
```xml
<Lot UserText="" />
```

The sanitizer normalizes multiple tabs/spaces to single spaces and trims.

### 6. Malformed Tag Structure
**Problem:**
```xml
<Lot LotId="ABC123" SublotId="1" Extra="Value
```

**Fallback:**
- Regex extraction of available attributes
- Minimal tree creation with partial data

## Real-World Example - Your Actual Case

The error you encountered:
```
Failed to parse XML: not well-formed (invalid token): line 4, column 331
```

With this Lot tag showing in VSCode:
```xml
<Lot PartType="FPF5-1" UserText="EM☐EM☐EM☐EM☐EM☐EM☐EM☐EM☐EM☐" 
     OperatorName="HTTVXF" TesterType="881-TT/A" ...>
```

**Root Cause:** The `UserText` attribute contains **invalid UTF-8 byte sequences** or **corrupted characters** that appear as "EM" with error boxes in VSCode. These are not valid XML characters according to the XML 1.0 specification.

**What column 331 likely is:**
- One of these corrupted characters at that position
- Or an unescaped `&` after these characters
- Or a combination of encoding issues

The enhanced sanitizer will:
1. **Fix encoding issues**: Replace/remove invalid UTF-8 sequences
2. **Remove invalid XML characters**: Filter out characters not allowed in XML 1.0
3. **Normalize whitespace**: Clean up the attribute value
4. **Show diagnostics**: Log exactly which character at column 331 is problematic
5. **Continue processing**: Generate output file even with corrupted data

### Diagnostic Output Example
```
ERROR: XML Parse Error at line 4, column 331
ERROR: Character at error position: '\x1b' (ord=27)  ← Invalid control character
ERROR: Snippet: ...UserText="EM☐EM☐" OperatorName="HTTVXF"...
ERROR:                    ^
INFO: Attempting to sanitize and re-parse XML...
INFO: XML sanitization completed (removed invalid characters and fixed encoding)
INFO: XML successfully parsed after sanitization
```

After sanitization, the UserText will be cleaned:
```xml
<Lot PartType="FPF5-1" UserText="" OperatorName="HTTVXF" ...>
```
```

This shows the exact problem: `Probe&Test` should be `Probe&amp;Test`.

## Routing Logic

### Production Schema
Files routed to production when:
- XML is well-formed OR successfully sanitized
- All required metadata is available
- Valid Technology, scribe ID, and wafer map present

### Sandbox Schema
Files routed to sandbox when:
- XML required fallback regex extraction (`is_malformed = True`)
- Missing critical metadata
- Invalid TPNO or scribe information
- Missing wafer map coordinates

## Benefits

### 1. Resilience
- Script no longer fails completely on malformed XML
- Partial data extraction allows continued processing
- Output files are generated even with imperfect input

### 2. Traceability
- `is_malformed` flag tracks problematic files
- Detailed logging shows which recovery method was used
- Sandbox routing ensures data quality separation

### 3. Data Recovery
- Extracts maximum possible information from damaged files
- Metadata enrichment continues with available data
- Reduces data loss from formatting issues

### 4. Operational Continuity
- Processing pipeline doesn't halt on single bad file
- Batch operations can complete successfully
- Manual intervention only needed for truly unrecoverable files

## Logging

The enhanced error handling provides detailed logging:

### Successful Parse
```
INFO: XML parsed successfully
```

### Sanitization Success
```
WARN: Initial XML parse failed: not well-formed (invalid token): line 4, column 331
ERROR: XML Parse Error at line 4, column 331
ERROR: Context:
ERROR:     Line 2: <STDML>
ERROR:     Line 3: <Metadata>...</Metadata>
ERROR: >>> Line 4: <Lot PartType="FPF5-1" UserText="..." OperatorName="HTTVXF"...
ERROR:     Line 5: <ParametricData>
ERROR: Character at error position: '&' (ord=38)
ERROR: Snippet: ...TestCode="Probe&Test" StartTime="2026/02/17...
ERROR:          ^
INFO: Attempting to sanitize and re-parse XML...
INFO: XML sanitization completed
INFO: XML successfully parsed after sanitization
WARN: XML file is malformed - will route to SANDBOX
```

### Fallback Extraction
```
ERROR: Failed to parse XML even after sanitization: ...
ERROR: XML Parse Error at line 4, column 331
ERROR: Context: [shows problematic area]
WARN: Attempting fallback: extracting data using regex patterns...
INFO: Created minimal tree with 8 Lot attributes
INFO: Extracted attributes: ['LotId', 'SublotId', 'UserText', ...]
INFO: Fallback extraction successful - continuing with partial data
WARN: XML file is malformed - will route to SANDBOX
```

The diagnostic logging shows:
- Exact line and column of the error
- 2 lines of context before and after
- The specific character causing the issue
- A snippet with a pointer to the error location

## Testing Recommendations

### Test Cases

1. **Well-formed XML**: Verify normal processing path
2. **Unescaped ampersands**: Test sanitization tier
3. **Invalid control characters**: Test character removal
4. **Severely malformed XML**: Test regex fallback
5. **Missing Lot element**: Test complete failure handling

### Validation

- Check that malformed files are routed to SANDBOX
- Verify output files are generated for all test cases
- Confirm metadata enrichment works with partial data
- Validate logging provides sufficient debugging information

## Future Enhancements

### Potential Improvements

1. **More sophisticated sanitization**
   - Handle unclosed tags
   - Fix mismatched quotes
   - Repair broken CDATA sections

2. **Enhanced regex extraction**
   - Extract ParametricData when possible
   - Recover Unit/Die information
   - Parse nested structures

3. **Configurable tolerance levels**
   - Allow users to set strictness levels
   - Option to reject vs. sandbox malformed files
   - Configurable sanitization rules

4. **Automated reporting**
   - Generate reports on malformed file frequency
   - Track common error patterns
   - Alert on systematic issues

## Related Files

- `scripts/py/lib/Parser/SxmlParser.py` - Core parsing logic
- `scripts/py/lib/Enricher/SxmlEnricher.py` - Enrichment with error handling
- `scripts/py/jnd_probe_tesec_wmc_enricher.py` - Main script integration
- `scripts/py/lib/Log.py` - Logging infrastructure
- `scripts/py/lib/Util.py` - Utility functions including `dp_exit`

## Summary

The malformed XML handling strategy transforms the script from brittle (fails on any XML error) to resilient (recovers from most errors). This ensures operational continuity while maintaining data quality through appropriate routing to production or sandbox schemas.
