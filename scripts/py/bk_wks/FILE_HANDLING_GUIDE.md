# File Handling Guide - Quick Reference

## Overview

Task 3 implements file reading and format parsing components for workstream extract files. These components enable efficient, streaming file processing with automatic encoding detection and format specification parsing.

---

## FileReader - Reading Workstream Files

### Basic Usage

```python
from scribe_lot_mapper.readers.file_reader import FileReader

# Open and read a phist file
reader = FileReader("data/edbws_phist.txt")

# Stream records
with reader:
    for line in reader:
        print(line)  # Raw tab-delimited record
```

### With Encoding Specification

```python
# Specify encoding if known
reader = FileReader(
    "data/file.phist",
    encoding="utf-8"
)
```

### Manual Open/Close

```python
reader = FileReader("data/file.phist")

# Manually open
reader.open()

# Process records
for line in reader:
    process(line)

# Close
reader.close()
```

### File Type Detection

```python
reader = FileReader("data/edbws_phist.txt")

file_type = reader.get_file_type()  # "phist"
encoding = reader.get_encoding()    # "utf-8"
line_count = reader.get_line_count() # After iteration
```

### Validation

```python
reader = FileReader("data/file.phist")

if reader.validate():
    print("File format is valid")
else:
    print("File format is invalid")
```

### Supported File Types

```
phist         - Parameter history (primary)
lhist         - Lot history
lot_attr      - Lot attributes
product       - Product catalog
entity        - Equipment definitions
unknown       - Unrecognized type
```

### Compression Support

```python
# Automatically detects and handles gzip
reader = FileReader("data/file.phist.gz")

# Works exactly the same as uncompressed
with reader:
    for line in reader:
        process(line)
```

### Error Handling

```python
from scribe_lot_mapper.exceptions import FileOperationError

try:
    reader = FileReader("nonexistent.phist")
except FileOperationError as e:
    print(f"File error: {e}")
```

---

## FormatSpecParser - Reading Format Specifications

### Default PHIST Fields

```python
from scribe_lot_mapper.readers.format_parser import FormatSpecParser

# Use standard PHIST field definitions (no file needed)
parser = FormatSpecParser()

# All 21 PHIST fields available
fields = parser.get_fields()
print(fields["parameter_set_id"])  # Field definition
print(fields["unit_id"])           # Scribe position field
```

### Load Custom Format Spec

```python
# Parse a .bcp_fmt format specification file
parser = FormatSpecParser("specs/edbws_phist.bcp_fmt")

# Access fields
fields = parser.get_fields()
delimiter = parser.get_delimiter()  # Usually "\t"
encoding = parser.get_encoding()    # Usually "utf-8"
```

### Field Access

```python
# By position (1-based column number)
field = parser.get_field_by_position(1)
# Returns: {'field_name': 'parameter_set_id', 'position': 1, ...}

# By index (0-based array position)
field = parser.get_field_by_index(0)
# Same field as position 1

# Get all fields
all_fields = parser.get_fields()
```

### Standard PHIST Fields

```
Position  Field Name                Type      Purpose
--------  -------------------------  -------   ----------------
1         parameter_set_id          VARCHAR   Test program ID
2         parameter_set_version     VARCHAR   Test version
3         date_time                 VARCHAR   Timestamp
4         work_week                 VARCHAR   Calendar week
5         facility                  VARCHAR   Location code
6         parameter_name            VARCHAR   Test name
7         sequence_number           INT       Test order
8         unit_id                   VARCHAR   Scribe position ← CRITICAL
9         type_id                   VARCHAR   Equipment code ← CRITICAL
10-14     c_value_1 to c_value_5    VARCHAR   Text measurements
15-19     d_value_1 to d_value_5    VARCHAR   Numeric measurements
20        limits_high               VARCHAR   Upper limit
21        limits_low                VARCHAR   Lower limit
```

### Caching

```python
# Cache a parsed specification
parser = FormatSpecParser("specs/format.bcp_fmt")
spec = parser.get_spec()

FormatSpecParser.cache_spec("specs/format.bcp_fmt", spec)

# Later: Retrieve from cache
cached = FormatSpecParser.get_cached_spec("specs/format.bcp_fmt")

# Or use automatic caching
parser = FormatSpecParser.parse_or_use_cached("specs/format.bcp_fmt")

# Clear all cache
FormatSpecParser.clear_cache()
```

### Format Specification File Format

```
# Comments start with #
# Format: field_name = position, type, length

parameter_set_id = 1, VARCHAR, 20
facility = 5, VARCHAR, 10
unit_id = 8, VARCHAR, 10
type_id = 9, VARCHAR, 15
```

### Error Handling

```python
from scribe_lot_mapper.exceptions import ParsingError

try:
    parser = FormatSpecParser("missing.bcp_fmt")
except ParsingError as e:
    print(f"Parse error: {e}")
```

---

## Combined Usage - Reading Files with Format Specs

### Example: Process PHIST Records

```python
from scribe_lot_mapper.readers import FileReader, FormatSpecParser

# Get format specification
format_spec = FormatSpecParser()  # Uses standard PHIST

# Open and read file
reader = FileReader("data/edbws_phist.txt")

# Process records
with reader:
    for line_num, line in enumerate(reader, 1):
        if not line.strip():
            continue  # Skip empty lines
        
        # Split by delimiter
        fields = line.split("\t")
        
        # Map to field names
        spec_fields = format_spec.get_fields()
        record_data = {}
        
        for field_name, field_def in spec_fields.items():
            idx = field_def["column_index"]
            if idx < len(fields):
                record_data[field_name] = fields[idx]
        
        # Process mapped record
        process_record(record_data)
```

### Example: Custom Format and File Type

```python
# Detect file type and get appropriate format
reader = FileReader("data/lot_history.txt")
file_type = reader.get_file_type()  # "lhist"

# For phist, always use standard format
if file_type == "phist":
    format_parser = FormatSpecParser()  # Standard PHIST
else:
    # Could load custom format for other types
    format_parser = FormatSpecParser(f"specs/{file_type}.bcp_fmt")

# Process
with reader:
    for line in reader:
        # Use format_parser to interpret fields
        pass
```

---

## Integration with Parser Component (Task 4)

These components will be used by the Parser component:

```python
from scribe_lot_mapper.readers import FileReader, FormatSpecParser
from scribe_lot_mapper.extractors import Parser

# Initialize readers/parsers
file_reader = FileReader("data/edbws_phist.txt")
format_spec = FormatSpecParser()

# Parser will use these to extract fields
parser = Parser(file_reader, format_spec)

# Parse records into ParsedRecord objects
for parsed_record in parser.parse_file():
    # Fully extracted and normalized
    print(parsed_record.parameter_set_id)
    print(parsed_record.unit_id)
```

---

## Best Practices

### Do Use Context Managers
```python
# Good - Resources cleaned up automatically
with FileReader("file.phist") as reader:
    for line in reader:
        process(line)
```

### Don't Forget to Close Manual Opens
```python
# Remember to close!
reader.open()
try:
    for line in reader:
        process(line)
finally:
    reader.close()
```

### Do Validate Before Processing
```python
reader = FileReader("file.phist")
if not reader.validate():
    raise ValueError("Invalid file format")

# Safe to process
with reader:
    for line in reader:
        process(line)
```

### Do Cache Format Specs for Reuse
```python
# First time: Parse and cache
parser = FormatSpecParser.parse_or_use_cached("specs/format.bcp_fmt")

# Later calls use cached version
parser = FormatSpecParser.parse_or_use_cached("specs/format.bcp_fmt")
```

---

## Error Handling

```python
from scribe_lot_mapper.exceptions import FileOperationError, ParsingError

try:
    reader = FileReader("data.phist")
    reader.open()
    
    for line in reader:
        # Errors during reading will raise FileOperationError
        process(line)
    
    reader.close()
    
except FileOperationError as e:
    print(f"File operation failed: {e}")
    # Has context: file_path, operation, line_number
    
except ParsingError as e:
    print(f"Parsing failed: {e}")
    # Has context: line_number, file_name
```

---

## Performance Considerations

### Memory Efficiency
- FileReader uses streaming (not loading entire file)
- Processes one record at a time
- Ideal for large files (millions of records)

### Encoding Detection
- First access checks encoding (~1KB)
- Specify encoding if known to skip detection
- Fallback to Latin-1 (accepts all bytes)

### Caching
- FormatSpecParser caches parsed specs
- Reuse parser instances for repeated parsing
- Clear cache if format files change

---

## Troubleshooting

### "File not found" Error
```python
from pathlib import Path

# Verify file exists
filepath = "data/edbws_phist.txt"
if not Path(filepath).exists():
    print(f"File not found: {filepath}")
```

### "Invalid format" During Validation
```python
reader = FileReader("file.phist")

# File may have insufficient fields or encoding issues
# Try specifying encoding
reader_with_encoding = FileReader("file.phist", encoding="latin-1")
```

### Encoding Errors
```python
# FileReader handles encoding errors by replacing invalid chars
# To see which encoding was detected
reader = FileReader("file.phist")
print(f"Detected encoding: {reader.get_encoding()}")
```

### Format Spec Missing Fields
```python
from scribe_lot_mapper.exceptions import ParsingError

try:
    parser = FormatSpecParser("bad_format.bcp_fmt")
except ParsingError as e:
    print(f"Invalid format spec: {e}")
    # Fallback to standard PHIST
    parser = FormatSpecParser()
```

---

## API Reference

### FileReader Methods

| Method | Parameters | Returns | Purpose |
|--------|-----------|---------|---------|
| `__init__()` | filepath, encoding, file_type | - | Initialize reader |
| `open()` | - | None | Open file for reading |
| `close()` | - | None | Close file |
| `__iter__()` | - | Iterator[str] | Iterate over lines |
| `__enter__()` | - | self | Context manager entry |
| `__exit__()` | exc_type, exc_val, exc_tb | None | Context manager exit |
| `validate()` | - | bool | Validate file format |
| `detect_file_type()` | filepath | str | Detect file type |
| `get_file_type()` | - | str | Get detected type |
| `get_encoding()` | - | str | Get encoding |
| `get_line_count()` | - | int | Get lines processed |

### FormatSpecParser Methods

| Method | Parameters | Returns | Purpose |
|--------|-----------|---------|---------|
| `__init__()` | filepath | - | Initialize parser |
| `get_fields()` | - | Dict | Get all fields |
| `get_field_by_position()` | position | Dict | Get field by 1-based column |
| `get_field_by_index()` | index | Dict | Get field by 0-based index |
| `get_delimiter()` | - | str | Get field separator |
| `get_encoding()` | - | str | Get file encoding |
| `get_spec()` | - | Dict | Get complete spec |
| `cache_spec()` | filepath, spec | None | Cache spec |
| `get_cached_spec()` | filepath | Dict | Retrieve cached spec |
| `clear_cache()` | - | None | Clear all cache |
| `parse_or_use_cached()` | filepath | Parser | Parse or use cache |

---

**For more details, see TASK_3_COMPLETE.md and implementation docstrings.**

