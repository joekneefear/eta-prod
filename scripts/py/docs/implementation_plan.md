# Implementation Plan: SHEDCL DTS1000 XLS Parser (Python)

## Goal

Convert the Perl parser `Dts_2k_xls.pm` to Python with enhanced custom field injection capabilities. The parser will process **SHEDCL DTS1000** (JUNO) Excel test data files and support custom parsing logic for specific fields like lot ID decomposition, test program extraction, and file-based timestamps.

## User Review Required

> [!IMPORTANT]
> **Custom Parsing Requirements Confirmation**
> 
> Please confirm the custom parsing requirements:
> 
> 1. **Lot ID Parsing**: From `FT-FCPF250N65S3L1-F154-HVPFT160003`, extract:
>    - `FT` → Process (Final Test)
>    - `FCPF250N65S3L1` → Device/Product name
>    - `F154` → Internal control naming
>    - `HVPFT160003` → Lot ID
> 
> 2. **Test Program Parsing**: From `TestFilename`, map as test program with last character as revision
> 
> 3. **Time Parsing**: Use file modified date instead of 1/1/1970 for START_TIME and END_TIME
> 
> **Question**: Should these custom parsers be:
> - A) Always active (hardcoded into the parser)
> - B) Optional via configuration (as designed in the design document)
> - C) Separate parser class that extends the base parser

---

## Proposed Changes

### Parser Module

#### [NEW] [Dts1000XlsParser.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/lib/Parser/Dts1000XlsParser.py)

Main parser class that:
- Loads Excel files using `openpyxl` library
- Parses metadata rows (Date, Version, Station, SystemName, DeviceName, LotName, etc.)
- Parses test definition rows (Item Name, Bias1/2/3, Min_Limit, Max_Limit)
- Parses data rows (Serial, Bin, test results)
- Creates `Model`, `Wafer`, `Test`, `Die`, and `Bin` objects
- Supports custom field extraction via callback configuration

**Key Methods**:
- `parse_to_model(infile: str) -> Model`: Main entry point
- `_parse_worksheet()`: Row-by-row parsing logic
- `_extract_metadata()`: Metadata field extraction with custom extractor support
- `_parse_test_definitions()`: Test name, limits, units, bias parsing
- `_parse_die_data()`: Die results and bin assignment
- `_create_tests()`: Test object creation with limits and conditions
- `_create_bins()`: Bin object creation with counts

---

#### [NEW] [ParserConfig.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/lib/Parser/ParserConfig.py)

Configuration class for custom parsing:
- Stores custom extractor callbacks
- Provides registration interface
- Supports field-specific overrides

**Structure**:
```python
class ParserConfig:
    custom_extractors: Dict[str, Callable]
    
    def register_extractor(field_name: str, callback: Callable)
```

---

#### [NEW] [CustomExtractors.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/lib/Parser/CustomExtractors.py)

Custom field extraction implementations:

**Classes**:
1. `CustomExtractor` (base class)
2. `LotIdExtractor`: Parses lot string pattern `PROCESS-DEVICE-CONTROL-LOTID`
3. `TestProgramExtractor`: Extracts program name and revision from filename
4. `DataportTimeExtractor`: Uses file modification time for START_TIME/END_TIME

Each extractor follows the interface:
```python
@staticmethod
def extract(raw_data: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]
```

---

## Verification Plan

### Automated Tests

> [!WARNING]
> **No Existing Test Framework Found**
> 
> After searching the codebase, no existing unit tests were found for the Parser module. The verification will rely on:
> 1. Manual testing with sample files
> 2. Output comparison with Perl parser (if available)

### Manual Verification Steps

#### Test 1: Basic Parsing (Standard Mode)

**Objective**: Verify parser can read Excel file and create correct data structures

**Steps**:
1. Obtain a sample DTS-2000 Excel file (`.xls` format)
2. Run the parser in standard mode:
   ```python
   from lib.Parser.Dts1000XlsParser import Dts1000XlsParser
   
   parser = Dts1000XlsParser()
   model = parser.parse_to_model('path/to/sample.xls')
   
   # Verify metadata
   print(f"LOT: {model.header.LOT}")
   print(f"PRODUCT: {model.header.PRODUCT}")
   print(f"PROGRAM: {model.header.PROGRAM}")
   print(f"OPERATOR: {model.header.OPERATOR}")
   print(f"START_TIME: {model.header.START_TIME}")
   print(f"END_TIME: {model.header.END_TIME}")
   
   # Verify test count
   print(f"Number of tests: {len(model.tests)}")
   
   # Verify wafer and die data
   wafer = model.wafers[0]
   print(f"Number of dies: {len(wafer.dies)}")
   print(f"Number of bins: {len(wafer.bins)}")
   
   # Verify first test
   test = model.tests[0]
   print(f"Test 1: {test.name}, LSL={test.LSL}, HSL={test.HSL}, units={test.units}")
   
   # Verify first die
   die = wafer.dies[0]
   print(f"Die 1: partid={die.partid}, bin={die.soft_bin}, results={len(die.result)}")
   ```

3. **Expected Results**:
   - All metadata fields populated (no `None` values for key fields)
   - Test count matches Excel "Item Name" row
   - Die count matches data rows
   - Bin counts are accurate
   - Test results align with test definitions (same count)

---

#### Test 2: Custom Lot ID Parsing

**Objective**: Verify custom lot ID extractor correctly parses the pattern

**Steps**:
1. Create a test file or use existing file with lot format: `FT-FCPF250N65S3L1-F154-HVPFT160003`
2. Run parser with custom lot extractor:
   ```python
   from lib.Parser.Dts1000XlsParser import Dts1000XlsParser, ParserConfig
   from lib.Parser.CustomExtractors import LotIdExtractor
   
   config = ParserConfig()
   config.register_extractor('lot_parser', LotIdExtractor.extract)
   
   parser = Dts1000XlsParser(config)
   model = parser.parse_to_model('path/to/sample.xls')
   
   print(f"PROCESS: {model.header.PROCESS}")  # Should be 'FT'
   print(f"PRODUCT: {model.header.PRODUCT}")  # Should be 'FCPF250N65S3L1'
   print(f"INTERNAL_CONTROL: {model.header.INTERNAL_CONTROL}")  # Should be 'F154'
   print(f"LOT: {model.header.LOT}")  # Should be 'HVPFT160003'
   ```

3. **Expected Results**:
   - `PROCESS = 'FT'`
   - `PRODUCT = 'FCPF250N65S3L1'`
   - `INTERNAL_CONTROL = 'F154'`
   - `LOT = 'HVPFT160003'`

---

#### Test 3: Test Program and Revision Parsing

**Objective**: Verify test program extraction with revision as last character

**Steps**:
1. Run parser with test program extractor:
   ```python
   from lib.Parser.Dts1000XlsParser import Dts1000XlsParser, ParserConfig
   from lib.Parser.CustomExtractors import TestProgramExtractor
   
   config = ParserConfig()
   config.register_extractor('program_parser', TestProgramExtractor.extract)
   
   parser = Dts1000XlsParser(config)
   model = parser.parse_to_model('path/to/sample.xls')
   
   print(f"PROGRAM: {model.header.PROGRAM}")
   print(f"REVISION: {model.header.REVISION}")
   ```

2. **Expected Results**:
   - If TestFilename = `C:\Programs\MyTestProg5.tst`, then:
     - `PROGRAM = 'MyTestProg'`
     - `REVISION = '5'`

---

#### Test 4: File Modified Time Extraction

**Objective**: Verify file timestamp is used instead of hardcoded 1/1/1970

**Steps**:
1. Check file modification time:
   ```python
   import os
   from datetime import datetime
   
   file_path = 'path/to/sample.xls'
   mod_time = os.path.getmtime(file_path)
   expected_time = datetime.fromtimestamp(mod_time).strftime('%Y/%m/%d %H:%M:%S')
   print(f"File modified: {expected_time}")
   ```

2. Run parser with time extractor:
   ```python
   from lib.Parser.Dts1000XlsParser import Dts1000XlsParser, ParserConfig
   from lib.Parser.CustomExtractors import DataportTimeExtractor
   
   config = ParserConfig()
   config.register_extractor('time_parser', DataportTimeExtractor.extract)
   
   parser = Dts1000XlsParser(config)
   model = parser.parse_to_model('path/to/sample.xls')
   
   print(f"START_TIME: {model.header.START_TIME}")
   print(f"END_TIME: {model.header.END_TIME}")
   ```

3. **Expected Results**:
   - `START_TIME` and `END_TIME` match file modification timestamp
   - Format: `YYYY/MM/DD HH:MM:SS`
   - NOT `1970/01/01 00:00:00`

---

#### Test 5: All Custom Extractors Combined

**Objective**: Verify all custom extractors work together

**Steps**:
1. Run parser with all custom extractors:
   ```python
   from lib.Parser.Dts1000XlsParser import Dts1000XlsParser, ParserConfig
   from lib.Parser.CustomExtractors import (
       LotIdExtractor,
       TestProgramExtractor,
       DataportTimeExtractor
   )
   
   config = ParserConfig()
   config.register_extractor('lot_parser', LotIdExtractor.extract)
   config.register_extractor('program_parser', TestProgramExtractor.extract)
   config.register_extractor('time_parser', DataportTimeExtractor.extract)
   
   parser = Dts1000XlsParser(config)
   model = parser.parse_to_model('path/to/FT-FCPF250N65S3L1-F154-HVPFT160003.xls')
   
   # Print all custom-parsed fields
   print(f"PROCESS: {model.header.PROCESS}")
   print(f"PRODUCT: {model.header.PRODUCT}")
   print(f"LOT: {model.header.LOT}")
   print(f"PROGRAM: {model.header.PROGRAM}")
   print(f"REVISION: {model.header.REVISION}")
   print(f"START_TIME: {model.header.START_TIME}")
   print(f"END_TIME: {model.header.END_TIME}")
   ```

2. **Expected Results**: All custom fields correctly parsed

---

### Comparison Test (If Perl Parser Available)

**Objective**: Ensure Python parser output matches Perl parser output

**Steps**:
1. Run Perl parser on sample file (if available)
2. Run Python parser on same file
3. Compare key fields:
   - Metadata fields (LOT, PRODUCT, PROGRAM, etc.)
   - Test count and names
   - Die count
   - Bin counts
   - Sample test results

**Note**: This test requires access to the Perl parser execution environment.

---

## Dependencies

**Required Python Packages**:
- `openpyxl` (for Excel file parsing)

**Installation**:
```bash
pip install openpyxl
```

**Existing Internal Dependencies**:
- `lib.Data.Model`
- `lib.Data.Wafer`
- `lib.Data.Test`
- `lib.Data.Die`
- `lib.Data.Bin`
- `lib.Data.Metadata`
- `lib.Log`
- `lib.Util`

---

## Notes

1. **Excel Library**: Using `openpyxl` instead of `xlrd` because it supports both `.xls` and `.xlsx` formats and is actively maintained.

2. **Custom Extractor Design**: The callback-based design allows users to inject custom parsing without modifying the core parser class, making it extensible and maintainable.

3. **Data Structure Compatibility**: All data structures follow the existing Python `lib.Data` patterns to ensure compatibility with downstream processing.

4. **Error Handling**: Parser will include error handling for:
   - Missing files
   - Invalid Excel format
   - Missing required fields
   - Malformed data rows

5. **Logging**: Will use existing `lib.Log` module for consistent logging across the codebase.
