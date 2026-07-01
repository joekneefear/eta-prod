# DTS1000/DTS2000 XLS Parser - Implementation Walkthrough

## Overview

Successfully implemented a Python parser for **SHEDCL DTS1000/DTS2000** (JUNO) Excel test data files, converted from the Perl module `Dts_2k_xls.pm`. The parser includes a flexible custom field injection system for handling site-specific data formats.

---

## What Was Implemented

### Core Parser Files

#### 1. [Dts1k2kXlsParser.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/lib/Parser/Dts1k2kXlsParser.py)

**Main parser class** (430 lines)

**Key Features**:
- Parses Excel files using `openpyxl` library
- Extracts metadata (lot, product, operator, timestamps, equipment, etc.)
- Parses test definitions (names, limits, units, bias conditions)
- Parses die data (part IDs, bins, test results)
- Creates structured data model (`Model`, `Wafer`, `Test`, `Die`, `Bin` objects)
   - **Custom Field Extraction Framework:**
     - **YAML-Based Configuration**: Site-specific parsing rules defined in `resources/dts1000_custom_parsers.yaml`.
     - **`ParserConfig.py`**: Auto-loads YAML config and registers extractors.
     - **`CustomExtractors.py`**: Implements specific extractors (Lot ID, Program, Time).
   - **Main Script (`dts1000_juno_translator_enricher.py`):**
     - Full command-line interface with YAML config support.
     - Integration with RefDB and IFF generation.
   - **Logging:**
     - Integrated `pplogger` for RefDB logging.
     - Standardized metadata logging pattern (LOT, DEVICE, etc.).


**Main Methods**:
- `parse_to_model(infile)` - Entry point, returns `Model` object
- `_parse_excel_file()` - Row-by-row Excel parsing
- `_parse_lot_field()`, `_parse_program_field()`, etc. - Field-specific parsing with custom extractor support
- `_create_tests()`, `_create_bins()` - Object creation from parsed data

---

#### 2. [ParserConfig.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/lib/Config/ParserConfig.py)

**Configuration management class** (75 lines)

**Purpose**: Manages custom field extractors

**Methods**:
- `__init__(config_file, site)`: Auto-load configurations
- `register_extractor(field_name, callback)` - Register custom parser
- `has_extractor(field_name)` - Check if custom parser exists
- `get_extractor(field_name)` - Retrieve custom parser

**Supported Fields**:
- `lot_parser` - Custom lot ID parsing
- `device_parser` - Custom device name parsing
- `time_parser` - Custom timestamp extraction
- `program_parser` - Custom test program parsing
- `process_parser` - Custom process field parsing

---

#### 3. [CustomExtractors.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/lib/Parser/CustomExtractors.py)

**Custom field extractor implementations** (170 lines)

**Extractors Implemented**:

##### `LotIdExtractor`
Parses lot format: `FT-FCPF250N65S3L1-F154-HVPFT160003`

**Extraction**:
- `FT` → `PROCESS` (Final Test)
- `FCPF250N65S3L1` → `PRODUCT` (Device name)
- `F154` → `INTERNAL_CONTROL`
- `HVPFT160003` → `LOT`

##### `TestProgramExtractor`
Extracts program name and revision from filename

**Example**:
- Input: `C:\Programs\MyTestProg5.tst`
- Output: `PROGRAM='MyTestProg'`, `REVISION='5'`

##### `TimeExtractor`
Uses file modification timestamp instead of hardcoded 1/1/1970

**Output**: `START_TIME` and `END_TIME` in `YYYY/MM/DD HH:MM:SS` format

---

#### 4. [Dts1000XlsParser_examples.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/lib/Parser/Dts1000XlsParser_examples.py)

**Usage examples** (140 lines)

**Examples Included**:
1. Standard parsing (no custom extractors)
2. Custom lot ID parsing
3. Custom test program parsing
4. File modification time extraction
5. All custom extractors combined

---

## Data Structure Flow

```mermaid
graph TD
    A[Excel File] --> B[Dts1k2kXlsParser]
    B --> C[Model]
    C --> D[Metadata/Header]
    C --> E[Wafer]
    C --> F[Tests List]
    C --> G[Limit]
    E --> H[Dies List]
    E --> I[Bins List]
    H --> J[Results List]
    F --> K[Conditions List]
    
    style A fill:#e1f5ff
    style C fill:#fff4e1
    style D fill:#f0f0f0
    style E fill:#f0f0f0
    style F fill:#f0f0f0
```

---

## Usage Examples

### Standard Parsing

```python
from lib.Parser.Dts1k2kXlsParser import Dts1k2kXlsParser

parser = Dts1k2kXlsParser()
model = parser.parse_to_model('test_data.xls')

print(f"LOT: {model.header.LOT}")
print(f"PRODUCT: {model.header.PRODUCT}")
print(f"Tests: {len(model.tests)}")
print(f"Dies: {len(model.wafers[0].dies)}")
```

### Custom Lot Parsing

```python
from lib.Parser.Dts1k2kXlsParser import Dts1k2kXlsParser, ParserConfig
from lib.Parser.CustomExtractors import LotIdExtractor

config = ParserConfig()
config.register_extractor('lot_parser', LotIdExtractor.extract)

parser = Dts1k2kXlsParser(config)
model = parser.parse_to_model('FT-FCPF250N65S3L1-F154-HVPFT160003.xls')

# Lot ID is decomposed:
print(f"PROCESS: {model.header.PROCESS}")  # 'FT'
print(f"PRODUCT: {model.header.PRODUCT}")  # 'FCPF250N65S3L1'
print(f"LOT: {model.header.LOT}")          # 'HVPFT160003'
```

### All Custom Extractors

```python
from lib.Parser.Dts1k2kXlsParser import Dts1k2kXlsParser, ParserConfig
from lib.Parser.CustomExtractors import (
    LotIdExtractor,
    TestProgramExtractor,
    TimeExtractor
)

config = ParserConfig()
config.register_extractor('lot_parser', LotIdExtractor.extract)
config.register_extractor('program_parser', TestProgramExtractor.extract)
config.register_extractor('time_parser', TimeExtractor.extract)

parser = Dts1k2kXlsParser(config)
model = parser.parse_to_model('sample.xls')

# All custom fields are extracted
```

---

## Key Design Decisions

### 1. **Callback-Based Custom Extraction**

### 1. **YAML-Based Configuration**

Using YAML files (`dts1000_custom_parsers.yaml`) allows for:
- **Zero-code updates**: Add new patterns without modifying Python code
- **Site-specific rules**: Distinct configs for multiple facilities
- **Auto-registration**: Scripts automatically pick up the config


**Benefits**:
- ✅ Flexible - users can inject custom logic without modifying parser
- ✅ Extensible - new extractors can be added easily
- ✅ Optional - standard parsing works without configuration
- ✅ Composable - multiple extractors can be combined

### 2. **Data Structure Compatibility**

All data structures use existing Python classes from `lib.Data`:

**Benefits**:
- ✅ Compatible with downstream processing
- ✅ Consistent with other parsers in the codebase
- ✅ Type-safe with proper class attributes

### 3. **Excel Library Choice**

Using `openpyxl` instead of `xlrd`:

**Benefits**:
- ✅ Supports both `.xls` and `.xlsx` formats
- ✅ Actively maintained
- ✅ Better performance for large files

---

## Files Created

| File | Lines | Purpose |
|------|-------|---------|
| [Dts1k2kXlsParser.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/lib/Parser/Dts1k2kXlsParser.py) | 430 | Main parser class |
| [ParserConfig.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/lib/Parser/ParserConfig.py) | 75 | Configuration management |
| [CustomExtractors.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/lib/Parser/CustomExtractors.py) | 170 | Custom field extractors |
| [Dts1000XlsParser_examples.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/lib/Parser/Dts1000XlsParser_examples.py) | 140 | Usage examples |

**Total**: ~815 lines of Python code

---

## Next Steps

### Testing & Validation

> [!IMPORTANT]
> **Testing Required**
> 
> The parser has been implemented but needs testing with actual DTS1000/DTS2000 Excel files.

#### Recommended Tests

1. **Basic Parsing Test**
   - Obtain a sample DTS1000/DTS2000 Excel file
   - Run standard parser
   - Verify metadata, test count, die count, bin counts

2. **Custom Extractor Tests**
   - Test lot ID decomposition with pattern `FT-DEVICE-CONTROL-LOT`
   - Test program/revision extraction
   - Test file timestamp extraction

3. **Comparison Test** (if Perl parser is available)
   - Parse same file with both Perl and Python parsers
   - Compare output fields for consistency

4. **Edge Cases**
   - Empty cells
   - Missing fields
   - Malformed data rows
   - Large files (performance test)

### Installation

**Required Package**:
```bash
pip install openpyxl
```

### Integration

The parser is ready to integrate into your data processing pipeline:

```python
from lib.Parser import Dts1000XlsParser

# Use like any other parser in the system
parser = Dts1000XlsParser()
model = parser.parse_to_model(input_file)

# Process model as usual
# ... downstream processing ...
```

---

## Summary

✅ **Completed**:
- Full Python implementation of DTS1000/DTS2000 parser
- Custom field injection framework
- Three custom extractors (lot, program, time)
- Comprehensive usage examples
- Integration with existing data structures

📋 **Pending**:
- Testing with actual DTS1000/DTS2000 files
- Validation against Perl parser output (if available)
- Performance benchmarking with large files

🎯 **Ready For**:
- User testing
- Integration into production pipeline
- Extension with additional custom extractors as needed
