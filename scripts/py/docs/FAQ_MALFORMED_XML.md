# FAQ: Malformed XML Handling

## Q: Will the excessive tabs in UserText cause parsing to fail?

**A: No, tabs are valid XML. But corrupted/invalid characters will cause failure.**

Valid XML (tabs are OK):
```xml
<Lot UserText="									" OperatorName="HTTVXF" ...>
```

Invalid XML (corrupted characters - what you're actually seeing):
```xml
<Lot UserText="EM☐EM☐EM☐EM☐EM☐" OperatorName="HTTVXF" ...>
```

When you open the file in VSCode and see "EM" with error boxes (☐), these are **invalid UTF-8 byte sequences** or **corrupted characters** that are not allowed in XML 1.0.

## Q: So what's causing the error at "line 4, column 331"?

**A: The corrupted characters in UserText.**

The characters showing as "EM☐" in VSCode are likely:
1. **Invalid control characters** (like ESC, 0x1B)
2. **Corrupted UTF-8 sequences** from encoding issues
3. **Non-XML-compliant characters** from the source system

These are NOT valid XML characters according to XML 1.0 specification.

## Q: Will Tier 2 (sanitization) fix this?

**A: Yes! Here's what happens:**

### Step 1: Parse Attempt
```
WARN: Initial XML parse failed: not well-formed (invalid token): line 4, column 331
```

### Step 2: Diagnostic
```
ERROR: XML Parse Error at line 4, column 331
ERROR: Character at error position: '\x1b' (ord=27)  ← ESC control character
ERROR: Snippet: ...UserText="EM☐EM☐" OperatorName="HTTVXF"...
ERROR:                    ^
```
Now you know exactly what's wrong - invalid control characters!

### Step 3: Sanitization
The sanitizer automatically:
- **Removes invalid UTF-8 sequences** (those "EM☐" characters)
- **Filters out invalid XML characters** per XML 1.0 spec
- Converts `&` → `&amp;`
- Converts `<` → `&lt;`
- Converts `>` → `&gt;`
- Normalizes whitespace
- Removes control characters

### Step 4: Success
```
INFO: XML sanitization completed (removed invalid characters and fixed encoding)
INFO: XML successfully parsed after sanitization
WARN: XML file is malformed - will route to SANDBOX
```

File is processed successfully and routed to SANDBOX for safety.

The corrupted `UserText="EM☐EM☐EM☐"` becomes `UserText=""`

## Q: What if sanitization doesn't work?

**A: Tier 3 (regex fallback) extracts critical data:**

```
WARN: Attempting fallback: extracting data using regex patterns...
INFO: Created minimal tree with 8 Lot attributes
INFO: Extracted attributes: ['LotId', 'SublotId', 'UserText', 'OperatorName', ...]
INFO: Fallback extraction successful - continuing with partial data
```

The script will:
- Extract whatever attributes it can find
- Create a minimal XML structure
- Continue processing with available data
- Generate output file (routed to SANDBOX)

## Q: Will my file still be processed?

**A: Yes! The script no longer fails completely.**

Before the fix:
```
ERROR: Failed to parse XML: not well-formed (invalid token): line 4, column 331
[Script exits with error code 1]
[No output file generated]
```

After the fix:
```
WARN: Initial XML parse failed: not well-formed (invalid token): line 4, column 331
INFO: Attempting to sanitize and re-parse XML...
INFO: XML successfully parsed after sanitization
WARN: XML file is malformed - will route to SANDBOX
[Script continues]
[Output file generated and sent to SANDBOX]
```

## Q: How do I know if my file was malformed?

**A: Check the logs for these indicators:**

1. **Sanitization was needed:**
   ```
   INFO: XML successfully parsed after sanitization
   WARN: XML file is malformed - will route to SANDBOX
   ```

2. **Fallback was used:**
   ```
   INFO: Fallback extraction successful - continuing with partial data
   WARN: XML file is malformed - will route to SANDBOX
   ```

3. **File routing:**
   - Production: Well-formed XML with complete metadata
   - Sandbox: Malformed XML or missing critical metadata

## Q: What should I do if files keep failing?

**A: Use the diagnostic output to fix the source:**

1. **Check the error diagnostics** in the log:
   ```
   ERROR: Character at error position: '&' (ord=38)
   ERROR: Snippet: ...TestCode="Probe&Test"...
   ```

2. **Fix the root cause** in the data source:
   - Update the test equipment configuration
   - Fix the data export script
   - Add proper XML escaping at the source

3. **Monitor patterns:**
   - If many files have the same issue, fix upstream
   - If only occasional files fail, the fallback is sufficient

## Q: Will this affect performance?

**A: Minimal impact:**

- **Well-formed XML**: No performance impact (Tier 1 - normal parsing)
- **Malformed XML**: Small overhead for sanitization attempt (Tier 2)
- **Severely malformed**: Additional overhead for regex extraction (Tier 3)

Most files will parse normally with no performance degradation.

## Summary

✅ Your file with tabs in `UserText` is valid XML
✅ The error at column 331 is likely an unescaped `&` elsewhere
✅ Tier 2 sanitization will fix it automatically
✅ You'll get detailed diagnostics showing the exact problem
✅ File will be processed and routed to SANDBOX
✅ No manual intervention needed
