# Design Document: Scribe-to-Lot/Wafer Mapping Service

## Overview

The Scribe-to-Lot/Wafer Mapping Service is a data transformation utility that extracts and normalizes manufacturing traceability information from workstream parameter history (phist) files, with optional enrichment from lot history (lhist) and lot attributes (lot_attr) files. It creates bidirectional mapping records that link scribe positions to lots and wafers, enabling defect analysis and yield correlation across production stages. The service supports multiple input/output formats and provides both forward (lot→scribe) and reverse (scribe→lot) lookup capabilities.

### File Input Strategy

**Required Input:**
- **phist** (edbws_phist file): Primary source containing all test measurements and scribe position data

**Optional Enrichment Inputs:**
- **lot_attr** (lot_attributes): Maps wafer identifiers to lot attributes (EPI SLOT for SiC tracking)
- **lhist** (lot_history): Provides lot movement context and quantity changes
- **product** (product_catalog): Product context for test program correlation
- **entity** (_entity): Equipment definitions for facility context

The service is designed to work with phist files as the primary source but can integrate supplementary files to enhance mapping quality and add context to the scribe-lot-wafer relationships.

---

## Architecture

### High-Level Flow

```
Input File (phist)
    ↓
[File Reader & Parser]
    ↓
[Field Extraction Engine]
    ├─ Equipment Parser (decompose equipment codes)
    ├─ Scribe Extractor (unit_id normalization)
    ├─ Lot/Wafer Extractor (lot and wafer identification)
    └─ Multi-Site Detector (handle c_value/d_value arrays)
    ↓
[Mapping Generator]
    ├─ Create scribe→lot mapping
    ├─ Create lot→scribe mapping
    └─ Assign mapping_id and timestamps
    ↓
[Validation Engine]
    ├─ Check completeness
    ├─ Verify consistency
    └─ Separate valid/invalid records
    ↓
[Output Generator]
    ├─ CSV output
    ├─ JSON output
    └─ IFF output (workstream format)
    ↓
Output Files (mappings.csv, mappings.json, mappings.iff)
```

---

## Components and Interfaces

### 1. File Reader Component

**Purpose:** Open, validate, and read workstream extract files (single or multiple file types)

**Public Interface:**
```
FileReader.open(filepath) → FileHandle
FileReader.read(FileHandle) → Iterator<RawRecord>
FileReader.validate(FileHandle) → ValidationResult
FileReader.detectFileType(filepath) → FileType
FileReader.close(FileHandle) → void
```

**Supported Input Files:**
- **phist** (parameter_history): Primary source - test measurements and scribe data
- **lhist** (lot_history): Lot movement and lot quantity changes
- **lot_attr** (lot_attributes): Custom lot attributes including wafer mapping
- **product** (product_catalog): Product information for context
- **entity** (_ent): Equipment/entity definitions

**Primary Focus for Scribe Mapping:** phist files (parameter history)
**Secondary Integration:** lhist for lot context, lot_attr for wafer relationships

**Responsibilities:**
- Detect file type from name pattern or content header
- Detect file encoding (UTF-8, ASCII, or binary)
- Handle both text and compressed (gzip) files
- Validate file format before processing
- Stream records to avoid loading entire file into memory
- Use format specification files (.bcp_fmt) to guide parsing

**Error Handling:**
- File not found → return FileNotFoundError with filepath
- Unreadable format → log and skip to next readable section
- Encoding issues → attempt fallback to ASCII/UTF-8
- Unknown file type → attempt to parse as phist (default) or halt with error

---

### 2. Parser Component

**Purpose:** Parse individual records and extract fields according to BCP format specification

**Public Interface:**
```
Parser.parseRecord(RawRecord, FormatSpec) → ParsedRecord
Parser.parseField(fieldValue, fieldType) → FieldValue
Parser.normalizeValue(value) → NormalizedValue
Parser.extractFields(record) → FieldMap
```

**Field Mapping:**
Based on `edbws_phist.bcp_fmt`:
- Field 1: parameter_set_id (test program)
- Field 2: parameter_set_version (test version)
- Field 3: date_time (timestamp)
- Field 4: work_week (optional)
- Field 5: facility (location code)
- Field 6: parameter_name (test name)
- Field 7: sequence_number (order in test)
- Field 8: unit_id (scribe position identifier) ← **KEY FIELD**
- Field 9: type_id (equipment identifier)
- Field 10-15: c_value_1-5 (text measurements)
- Field 16-20: d_value_1-5 (numeric measurements)
- Field 21-26: various flags and limits

**Special Handling:**
- c_value/d_value arrays treated as multi-site measurements
- Empty values normalized to "N/A"
- Timestamps standardized to ISO 8601 format

---

### 3. Equipment Parser Component

**Purpose:** Decompose equipment codes into facility, probe, position, and site components

**Public Interface:**
```
EquipmentParser.parse(equipmentCode) → EquipmentInfo
EquipmentParser.decompose(code) → (facility, probe, position, siteType)
EquipmentParser.normalize(code) → NormalizedCode
```

**Pattern Recognition:**
Equipment codes follow structure: `[FACILITY]-[PROBE]-[POSITION][TYPE]`

Examples:
- `THK-1-51T` → facility=THK, probe=1, position=51, type=T
- `THK-1-51F` → facility=THK, probe=1, position=51, type=F
- `RI-1-11` → facility=RI, probe=1, position=11, type=(empty)
- `ACI-1-31` → facility=ACI, probe=1, position=31, type=(empty)
- `BV-8-31` → facility=BV, probe=8, position=31, type=(empty)

**Output Structure:**
```
EquipmentInfo {
  raw_code: String,
  facility: String,
  probe: Integer,
  position: Integer,
  type: String (T, F, or empty)
}
```

---

### 4. Scribe Extractor Component

**Purpose:** Extract and normalize scribe position identifiers from unit_id and equipment context

**Public Interface:**
```
ScribeExtractor.extract(unit_id, equipmentInfo, siteNumber) → ScribeIdentifier
ScribeExtractor.normalize(unit_id) → NormalizedScribeId
ScribeExtractor.generateScribeId(lot, equipment, position) → ScribeId
```

**Scribe Identification Logic:**
1. If unit_id is present (e.g., "LEFT", "CENTER", "A6", "1"), use it directly
2. If unit_id is empty, derive from equipment.position + site_number
3. Map directional indicators: LEFT=1, CENTER=2, RIGHT=3, TOP=1, BOTTOM=2
4. Create composite scribe_id: `[EQUIPMENT]_[POSITION]_[UNIT_ID]_[SITE]`

**Examples:**
- Input: equipment="THK-1-51T", unit_id="LEFT", site=1 → Output: "THK_1_51_LEFT_1"
- Input: equipment="THK-1-51T", unit_id="", site=1 → Output: "THK_1_51_SITE_1"
- Input: equipment="GOXTWS1125", unit_id="A6", site=1 → Output: "GOXTWS_A6_1"

---

### 5. Lot/Wafer Extractor Component

**Purpose:** Extract lot and wafer identifiers and establish their relationship

**Public Interface:**
```
LotWaferExtractor.extract(record) → (lot_id, wafer_id, wafer_family)
LotWaferExtractor.normalizeLot(lotString) → NormalizedLot
LotWaferExtractor.normalizeWafer(waferString) → NormalizedWafer
LotWaferExtractor.generateVirtualWafer(lot, equipment, timestamp) → VirtualWaferId
```

**Lot Pattern Recognition:**
- Lot identifiers are alphanumeric with format: `KG[PRODUCT_CODE][SEQUENCE]` (e.g., "KG4BNTCX", "KG42910X1")
- Extract directly from record where present
- Maintain mapping of lot → wafer(s)

**Wafer Pattern Recognition:**
- Wafer batch identifiers follow pattern: `[PREFIX][BATCH_NUMBER]` (e.g., "GOXTWS1125", "GOXTWS1135")
- Decompose to extract wafer family and batch
- Track wafer→lot relationship (one wafer per lot, one lot may have multiple wafers)

**Virtual Wafer Generation:**
If wafer_id is missing:
```
virtual_wafer_id = lot_id + "_W" + equipment_hash + "_" + timestamp_epoch
```

---

### 6. Multi-Site Detector Component

**Purpose:** Identify when a single record contains measurements for multiple scribe sites

**Public Interface:**
```
MultiSiteDetector.detect(record) → Integer (number of sites)
MultiSiteDetector.extractSiteValues(record, siteIndex) → SiteData
MultiSiteDetector.expandRecord(record) → List<ExpandedRecord>
```

**Detection Logic:**
1. Count non-empty c_value fields (c_value_1 to c_value_5) → max 5 sites
2. Count non-empty d_value fields (d_value_1 to d_value_5) → max 5 sites
3. Site count = max(c_value count, d_value count)
4. If site count > 1, expand record into multiple mapping records

**Expansion Example:**
```
Input record with c_value_1=55.1, c_value_2=4.9, c_value_3=5.7, c_value_4=5.7, c_value_5=5.4
↓
Output: 5 mapping records, each with:
  - Record 1: value=55.1, site_number=1
  - Record 2: value=4.9, site_number=2
  - Record 3: value=5.7, site_number=3
  - Record 4: value=5.7, site_number=4
  - Record 5: value=5.4, site_number=5
```

---

### 7. Mapping Generator Component

**Purpose:** Create bidirectional mapping records linking scribes ↔ lots ↔ wafers (all three relationships)

**Public Interface:**
```
MappingGenerator.generate(parsedRecord) → MappingRecord
MappingGenerator.createBidirectionalMapping(scribe, lot, wafer) → MappingRecord
MappingGenerator.assignMappingId(mapping) → String
```

**Mapping Record Structure (includes ALL relationships):**
```
MappingRecord {
  # Unique identifier
  mapping_id: String (UUID),
  
  # Scribe information
  scribe_id: String,
  equipment_id: String,
  position: Integer,
  unit_id: String,
  
  # Lot information
  lot_id: String,
  
  # Wafer information (complete)
  wafer_id: String,
  wafer_family: String,
  wafer_batch: Integer,
  
  # Test context
  test_program: String (parameter_set_id),
  test_value: String,
  facility: String,
  sequence_number: Integer,
  site_number: Integer,
  
  # Timestamps
  timestamp: ISO8601 (test execution time),
  created_at: ISO8601 (record creation time)
}
```

**Bidirectional Relationships (ALL three directions enabled):**

1. **Scribe → Lot/Wafer (Forward Lookup)**
   - Index: `scribe_id → [(lot_id, wafer_id, test_program, timestamp), ...]`
   - Query: "What lots/wafers used this scribe?"
   - Example: scribe "THK_1_51_LEFT_1" → lots ["KG4BNTCX", "KG42910X1"] with wafers ["GOXTWS1125", "GOXTWS2135"]

2. **Lot/Wafer → Scribe (Reverse Lookup)**
   - Index: `(lot_id, wafer_id) → [(scribe_id, test_program, timestamp), ...]`
   - Query: "Which scribes processed this lot/wafer?"
   - Example: lot "KG4BNTCX" + wafer "GOXTWS1125" → scribes ["THK_1_51_LEFT_1", "THK_1_51_CENTER_2", "THK_1_51_RIGHT_3"]

3. **Wafer → Lot (Implicit, One-to-One)**
   - Relationship: Every wafer belongs to exactly one lot
   - Query: "Which lot owns this wafer?"
   - Derived from: wafer_id + lot_id in mapping records

4. **Lot → Wafer (Implicit, One-to-Many)**
   - Relationship: One lot may contain multiple wafers
   - Query: "Which wafers belong to this lot?"
   - Derived from: All records with same lot_id grouped by wafer_id

**Key Feature: Single Record Enables All Relationships**
Each MappingRecord contains scribe_id, lot_id, AND wafer_id together, enabling:
- **Forward query:** scribe_id → find all lot_id + wafer_id combinations
- **Reverse query:** lot_id + wafer_id → find all scribe_id values
- **Transitive query:** scribe_id → wafer_id (via lot_id)
- **Lot-wafer query:** lot_id → all wafer_ids (via distinct records with same lot_id)
- **Completeness:** Every relationship verified in single record

---

### 8. Validation Component

**Purpose:** Validate mapping completeness and consistency

**Public Interface:**
```
Validator.validate(mappingRecord) → ValidationResult
Validator.checkCompleteness(record) → Boolean
Validator.checkConsistency(record, indexedData) → Boolean
Validator.generateReport() → ValidationReport
```

**Validation Rules:**
1. **Completeness Check:**
   - scribe_id must not be null/empty
   - lot_id must not be null/empty
   - wafer_id must not be null/empty

2. **Consistency Check:**
   - lot_id format must match pattern `KG*`
   - scribe_id format must match expected structure
   - wafer_id format must match pattern or be virtual (lot_*_W*)
   - timestamp must be valid ISO 8601

3. **Cross-Reference Check:**
   - If same lot appears multiple times, all wafer_ids must be consistent
   - If same scribe appears multiple times, lot_ids may differ (allowed)

**Invalid Record Handling:**
- Write to separate `.err` output file
- Include validation failure reason in error log

---

### 9. Output Generator Component

**Purpose:** Generate normalized output in multiple formats

**Public Interface:**
```
OutputGenerator.generateCSV(mappings, filepath) → void
OutputGenerator.generateJSON(mappings, filepath) → void
OutputGenerator.generateIFF(mappings, filepath) → void
OutputGenerator.writeHeaders(format) → void
```

**CSV Format:**
```
scribe_id,lot_id,wafer_id,test_program,equipment_id,facility,sequence_number,site_number,unit_id,test_value,timestamp,mapping_id
THK_1_51_LEFT_1,KG4BNTCX,GOXTWS1125,GMBG3002,THK-1-51T,FB6,1,1,LEFT,301.2,2026-07-14T03:34:33Z,uuid-1234
```

**JSON Format:**
```json
{
  "mappings": [
    {
      "mapping_id": "uuid-1234",
      "scribe": {
        "id": "THK_1_51_LEFT_1",
        "equipment": "THK-1-51T",
        "position": "51",
        "unit_id": "LEFT",
        "site_number": 1
      },
      "lot": {
        "id": "KG4BNTCX",
        "wafer": "GOXTWS1125"
      },
      "test": {
        "program": "GMBG3002",
        "value": "301.2",
        "timestamp": "2026-07-14T03:34:33Z"
      }
    }
  ]
}
```

**IFF Format:**
Follows workstream standard with vertical tab separators and proper headers (reference: FCS_WKSTRM.PL specification)

---

### 10. Lookup Service Component

**Purpose:** Provide reverse lookup capability (scribe→lot and lot→scribe)

**Public Interface:**
```
LookupService.findLotsByScribe(scribe_id) → List<(lot_id, wafer_id, test_context)>
LookupService.findScribesByLot(lot_id) → List<(scribe_id, test_context)>
LookupService.queryByDateRange(scribe_id, start_date, end_date) → List<MappingRecord>
LookupService.queryByFacility(facility) → List<MappingRecord>
LookupService.queryByTestProgram(test_program) → List<MappingRecord>
```

**Index Storage:**
- Use in-memory HashMap for scribe→lot (fast lookup)
- Use in-memory HashMap for lot→scribe (fast lookup)
- Optional persistence to SQLite for large datasets

---

## Data Models

### ParsedRecord (from phist/parameter_history)
```
ParsedRecord {
  raw_line: String,
  parameter_set_id: String,
  parameter_set_version: String,
  date_time: String (ISO 8601),
  facility: String,
  parameter_name: String,
  sequence_number: Integer,
  unit_id: String,
  type_id: String (equipment code),
  c_values: List<String> (c_value_1 to c_value_5),
  d_values: List<String> (d_value_1 to d_value_5),
  limits_high: String,
  limits_low: String,
  timestamp: ISO8601
}
```

### LotHistoryRecord (from lhist/lot_history) - Optional enrichment
```
LotHistoryRecord {
  lot_id: String,
  operation: String,
  transaction_type: String (MVOU, MOVE, SCRAP, etc.),
  quantity: Integer,
  equipment_id: String,
  timestamp: ISO8601
}
```

### LotAttributeRecord (from lot_attr) - Optional enrichment
```
LotAttributeRecord {
  lot_id: String,
  attribute_name: String,
  attribute_value: String,
  attribute_type: String (A=ASCII, N=Numeric)
}
```
**Special:** EPI SLOT attribute used for Silicon Carbide (SiC) wafer identification

### EquipmentInfo
```
EquipmentInfo {
  raw_code: String,
  facility: String,
  probe: Integer,
  position: Integer,
  type: String,
  normalized_code: String
}
```

### MappingRecord (after full processing)
```
MappingRecord {
  mapping_id: String (UUID),
  scribe_id: String,
  lot_id: String,
  wafer_id: String,
  test_program: String,
  equipment_id: String,
  facility: String,
  sequence_number: Integer,
  site_number: Integer,
  unit_id: String,
  test_value: String/Number,
  timestamp: String (ISO 8601),
  created_at: String (ISO 8601),
  validation_status: String (valid, incomplete, inconsistent)
}
```

---

## Correctness Properties

A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.

### Property 1: Lot-Scribe Bidirectionality
**For any** mapping record, if scribe_id maps to lot_id in forward direction, then lot_id must map to scribe_id in reverse direction. The mapping is bijective: one scribe belongs to one lot in one test execution, and one lot contains multiple scribes.

**Validates: Requirements 4.1, 4.3, 8.1**

### Property 2: Scribe Extraction Consistency
**For any** equipment code and unit_id combination, the extracted scribe_id must be deterministic: given the same inputs, the scribe_id must be identical across multiple invocations.

**Validates: Requirements 2.1, 2.2**

### Property 3: Lot-Wafer Relationship Invariant
**For any** lot_id in the mapping data, all associated wafer_ids must belong to that single lot (many-to-one relationship). A wafer cannot belong to multiple lots.

**Validates: Requirements 3.1, 3.2, 6.3**

### Property 4: Multi-Site Expansion Completeness
**For any** record with N non-empty c_value/d_value fields, the expansion must produce exactly N mapping records, and the sum of test values across expanded records must equal the original record's total values.

**Validates: Requirements 7.1, 7.2, 7.3**

### Property 5: Validation Error Separation
**For any** batch of mapping records processed, every invalid record (missing required fields) must be written to error output, and no invalid record may appear in valid output.

**Validates: Requirements 6.1, 6.2, 9.3**

### Property 6: Reverse Lookup Consistency
**For any** scribe_id lookup query, all returned lot_ids must have mapping records in the data that contain that scribe_id. No lot_id is returned unless a mapping record linking it to the scribe exists.

**Validates: Requirements 8.1, 8.2**

### Property 7: Timestamp Normalization
**For any** timestamp in the source data (various formats like "JUL 14 2026 03:00:16:000AM"), the parsed and normalized timestamp must represent the same moment in time when converted to ISO 8601 format. Parsing then normalizing must be idempotent.

**Validates: Requirements 1.4, 2.3**

### Property 8: Mapping ID Uniqueness
**For any** two distinct mapping records in the output, their mapping_ids must be unique. No two records may share the same mapping_id.

**Validates: Requirements 4.5**

---

## Error Handling

### Parser Errors
- **Malformed field:** Log warning with line number, skip field, use "N/A"
- **Invalid equipment code:** Log warning, assign "UNKNOWN" equipment_id
- **Missing unit_id:** Use equipment position as fallback scribe identifier
- **Invalid timestamp:** Use current timestamp as fallback

### Extraction Errors
- **No lot identifier:** Generate virtual lot_id based on equipment + timestamp
- **No wafer identifier:** Generate virtual wafer_id based on lot + equipment + timestamp
- **Inconsistent lot-wafer mapping:** Log warning, but allow record (may be data quality issue from source)

### Validation Errors
- **Missing scribe_id:** Move to error output, don't process further
- **Missing lot_id:** Move to error output
- **Missing wafer_id:** Move to error output
- **Lot-wafer inconsistency:** Flag in validation report but allow output (with warning)

### Output Errors
- **File write failure:** Log error with filepath and reason, attempt to write to alternate location
- **Permission denied:** Log error and halt with appropriate exit code
- **Disk full:** Log error and halt

---

## Testing Strategy

### Unit Tests
1. **Equipment Parser Tests:**
   - Parse standard equipment codes (THK-1-51T, RI-1-11, etc.)
   - Handle malformed codes gracefully
   - Verify decomposition accuracy

2. **Scribe Extractor Tests:**
   - Extract scribe_id from various unit_id formats (LEFT, CENTER, A6, 1, etc.)
   - Generate composite scribe_ids correctly
   - Handle missing unit_id with fallback logic

3. **Lot/Wafer Extractor Tests:**
   - Extract lot from standard format (KG*)
   - Extract wafer from batch identifier (GOXTWS*, etc.)
   - Generate virtual wafer_id when source not present
   - Validate format correctness

4. **Multi-Site Detector Tests:**
   - Detect single-site records (1 site)
   - Detect multi-site records (2-5 sites)
   - Correctly expand records into separate mapping records
   - Preserve parent-child relationships

5. **Validation Tests:**
   - Accept complete and consistent records
   - Reject records with missing fields
   - Flag inconsistent lot-wafer relationships
   - Generate accurate validation reports

### Property-Based Tests
- Test Property 1 (Bidirectionality): Generate random scribe-lot pairs, verify forward/reverse consistency
- Test Property 2 (Scribe Extraction Consistency): Generate random equipment codes and unit_ids, verify deterministic scribe_id
- Test Property 3 (Lot-Wafer Invariant): Generate random lot-wafer mappings, verify one-to-many relationship holds
- Test Property 4 (Multi-Site Expansion): Generate records with variable field counts, verify expansion produces correct number of records
- Test Property 5 (Validation Error Separation): Generate mixed valid/invalid records, verify separation is complete
- Test Property 6 (Reverse Lookup Consistency): Generate mappings, query by scribe, verify all returned lots have corresponding records
- Test Property 7 (Timestamp Normalization): Generate timestamps in various formats, verify parsing produces equivalent ISO 8601

### Integration Tests
- End-to-end file processing with sample workstream data
- Multiple output format generation (CSV, JSON, IFF)
- Large dataset processing (100K+ records)
- Error handling and recovery

---

## Implementation Approach

**Language:** Python 3.9+ leveraging existing organizational libraries

**Best Practices:**
- Follow PEP 8 style guide with black formatter
- Type hints throughout (mypy strict mode)
- Comprehensive docstrings (Google/NumPy style)
- Dataclasses for data models
- Protocol and ABC for interfaces
- **Reuse existing library modules** from `scripts/py/lib/`
- Pytest for unit and integration testing
- Property-based testing with hypothesis
- Error handling with custom exceptions
- Configuration via dataclass + Pydantic for validation
- Click for CLI with automatic help/version

**Existing Libraries to Leverage:**

1. **Logging & Error Handling** (`lib/Log.py`)
   - Centralized logger with file and console output
   - PPLogger integration for production logging
   - Already configured with RotatingFileHandler and formatting

2. **Utilities** (`lib/Util.py`)
   - File operations (gzip, zip, compression)
   - Date/time parsing and manipulation
   - Exit handling and error reporting
   - Already integrates with PPLogger

3. **Data Models** (`lib/Data/`)
   - Base data classes and structures
   - Metadata handling (Metadata.py, MetadataDTO.py)
   - Die, Wafer, Test data models
   - Use as reference for our MappingRecord models

4. **Parser Infrastructure** (`lib/Parser/`)
   - Parser base patterns and implementations
   - Example: JndLehParser, KDFXmlParser for reference
   - Already handles file format specifications

5. **WS/Workstream Utilities** (`lib/WS/`)
   - RefdbAPIClient for metadata lookups
   - Workstream-specific utilities

**Custom Modules to Create** (in `src/scribe_lot_mapper/`):
1. `readers.FileReader` - Read and stream workstream files (leverage `Util.py` file ops)
2. `readers.FormatSpecParser` - Parse BCP format specifications
3. `extractors.Parser` - Extract and normalize fields
4. `extractors.EquipmentParser` - Decompose equipment codes
5. `extractors.ScribeExtractor` - Extract and normalize scribe IDs
6. `extractors.LotWaferExtractor` - Extract lot and wafer information
7. `extractors.MultiSiteDetector` - Detect and expand multi-site records
8. `mappers.MappingGenerator` - Create bidirectional mappings
9. `validators.Validator` - Validate mapping completeness and consistency
10. `generators.CSVGenerator`, `JSONGenerator`, `IFFGenerator` - Output generation
11. `services.LookupService` - Provide scribe/lot lookup functionality
12. `services.ErrorHandler` - Centralized error handling (extend `Util.dp_exit()`)

**Import Strategy:**
```python
# Import existing libraries
from lib.Log import Log
from lib.Util import Util
from lib.PPLogger import PPLogger
from lib.WS.RefdbAPIClient import RefdbAPIClient

# Initialize logging
Log.configure_logger(log_file='scribe_mapper.log', pplogger=pplogger, level='INFO')
logger = Log.get_logger()

# Use existing utilities
try:
    # Processing...
    logger.info("Processing file...")
except Exception as e:
    Log.ERROR(str(e), exc_info=True, persist=True)
    Util.dp_exit(code=1, error=str(e), pplogger=pplogger)
```

**Key Libraries (standard + existing):**
- `pandas` - Data manipulation and CSV operations
- `pydantic` - Configuration validation
- `click` - CLI framework
- `pytest` - Testing framework
- `hypothesis` - Property-based testing
- `mypy` - Static type checking
- `black` - Code formatting
- `ruff` - Linting
- `python-dateutil` - Timestamp parsing (already in `Util.py`)
- `uuid` - Built-in UUID generation
- Plus all dependencies from `lib/` modules

---

**Document Version:** 1.0  
**Created:** July 14, 2026  
**Status:** Design Phase Complete
