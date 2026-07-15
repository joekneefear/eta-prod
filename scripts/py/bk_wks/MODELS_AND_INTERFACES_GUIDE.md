# Core Models and Interfaces - Developer Guide

## Quick Reference

### Task 2 Deliverables

**Location:** `src/scribe_lot_mapper/`

**Files Created/Enhanced:**
- `models.py` - 6 immutable dataclasses
- `exceptions.py` - 7 exception classes (pre-existing)
- `interfaces.py` - 14 Protocol interfaces (NEW)
- `__init__.py` - Enhanced exports

---

## Data Models (Immutable Dataclasses)

### ParsedRecord
Represents a raw record after field extraction, before processing.

```python
from scribe_lot_mapper import ParsedRecord

record = ParsedRecord(
    raw_line="...",
    parameter_set_id="GMBG3002",
    parameter_set_version="1.0",
    date_time="2026-07-14 03:34:33",
    facility="FB6",
    parameter_name="TEST_1",
    sequence_number=1,
    unit_id="LEFT",
    type_id="THK-1-51T",
    c_values=["301.2", "4.9", "5.7"],
    d_values=[],
    timestamp="2026-07-14T03:34:33Z"
)

# Helper methods
if record.is_multi_site():
    sites = record.site_count()  # Returns 3
```

**Key Methods:**
- `is_multi_site()` - Check if record has multiple measurements
- `site_count()` - Get number of sites (1-5)
- `has_required_fields()` - Validate minimum required fields

---

### EquipmentInfo
Represents decomposed equipment code components.

```python
from scribe_lot_mapper import EquipmentInfo

equipment = EquipmentInfo(
    raw_code="THK-1-51T",
    facility="THK",
    probe=1,
    position=51,
    type="T",
    normalized_code="THK-1-51-T"
)
```

---

### MappingRecord
Complete mapping linking scribe ↔ lot ↔ wafer (main output).

```python
from scribe_lot_mapper import MappingRecord
from datetime import datetime

mapping = MappingRecord(
    mapping_id="550e8400-e29b-41d4-a716-446655440000",
    scribe_id="THK_1_51_LEFT_1",
    lot_id="KG4BNTCX",
    wafer_id="GOXTWS1125",
    test_program="GMBG3002",
    equipment_id="THK-1-51T",
    facility="FB6",
    timestamp="2026-07-14T03:34:33Z",
    created_at="2026-07-14T03:35:00Z",
    test_value="301.2",
    sequence_number=1,
    site_number=1,
    unit_id="LEFT"
)

# Validation methods
if mapping.is_complete():
    if mapping.is_valid_lot_id() and mapping.is_valid_timestamp():
        print("Record is valid and complete")

if mapping.is_from_multi_site_expansion():
    print(f"Parent record: {mapping.parent_mapping_id}")
```

**Key Methods:**
- `is_complete()` - Check all required fields present
- `is_valid_lot_id()` - Validate lot format (KG*)
- `is_valid_timestamp()` - Validate ISO 8601
- `is_from_multi_site_expansion()` - Check if from expansion

---

### LotHistoryRecord
Optional enrichment: lot movement tracking.

```python
from scribe_lot_mapper import LotHistoryRecord

history = LotHistoryRecord(
    lot_id="KG4BNTCX",
    operation="MOVE",
    transaction_type="MVOU",
    quantity=24,
    equipment_id="THK-1-51T",
    timestamp="2026-07-14T03:34:33Z"
)
```

---

### LotAttributeRecord
Optional enrichment: lot custom attributes.

```python
from scribe_lot_mapper import LotAttributeRecord

attribute = LotAttributeRecord(
    lot_id="KG4BNTCX",
    attribute_name="EPI_SLOT",
    attribute_value="SLOT_5",
    attribute_type="A"  # A=ASCII, N=Numeric
)
```

---

### ValidationResult
Result of validation on a mapping record.

```python
from scribe_lot_mapper import ValidationResult

result = ValidationResult(
    record_id="line_42",
    is_valid=False,
    completeness_valid=True,
    consistency_valid=False,
    errors=["lot_id format invalid"]
)

if result.has_errors():
    print(result.error_summary())  # "lot_id format invalid"

# Add error (returns new instance due to frozen dataclass)
result_with_more_errors = result.add_error("timestamp invalid")
```

**Key Methods:**
- `has_errors()` - Check if any validation errors exist
- `add_error(msg)` - Create new result with additional error
- `error_summary()` - Get all errors as single string

---

## Exception Hierarchy

All exceptions inherit from `ScribeLotMapperError` for uniform catching:

```python
from scribe_lot_mapper import (
    ScribeLotMapperError,
    ParsingError,
    ExtractionError,
    MappingError,
    ValidationError,
    FileOperationError,
    ConfigurationError
)

try:
    # processing
    pass
except FileOperationError as e:
    print(f"File error: {e}")
except ScribeLotMapperError as e:
    print(f"Any service error: {e}")
```

**When to use:**
- `ParsingError` - Record format/field issues
- `ExtractionError` - Equipment/scribe/lot/wafer extraction failures
- `MappingError` - Mapping record creation failures
- `ValidationError` - Validation check failures
- `FileOperationError` - File I/O issues
- `ConfigurationError` - Invalid configuration

---

## Protocol Interfaces

Protocols define component contracts using structural subtyping (no inheritance needed).

### File Reading
```python
from scribe_lot_mapper import FileReader

class MyFileReader:
    """Implement FileReader protocol."""
    
    def open(self, filepath: str) -> None: ...
    def close(self) -> None: ...
    def read(self):  # Iterator[str]
        yield "record line"
    def validate(self) -> bool:
        return True
    def detect_file_type(self, filepath: str) -> str:
        return "phist"

# Automatically satisfies FileReader protocol
reader = MyFileReader()
```

### Parsing
```python
from scribe_lot_mapper import Parser, ParsedRecord

class MyParser:
    """Implement Parser protocol."""
    
    def parse_record(self, raw_line: str, format_spec) -> ParsedRecord:
        # Return ParsedRecord
        pass
    
    def parse_field(self, field_value: str, field_type: str):
        pass
    
    def normalize_value(self, value: str) -> str:
        return value.strip()
```

### Validation
```python
from scribe_lot_mapper import Validator, ValidationResult

class MyValidator:
    """Implement Validator protocol."""
    
    def validate(self, mapping) -> ValidationResult:
        # Return ValidationResult
        pass
    
    def check_completeness(self, mapping: MappingRecord) -> bool:
        return mapping.is_complete()
    
    def check_consistency(self, mapping: MappingRecord) -> bool:
        return mapping.is_valid_lot_id()
    
    def generate_report(self):
        return {"total": 0, "valid": 0}
```

### Output Generation
```python
from scribe_lot_mapper import OutputGenerator

class MyCSVGenerator:
    """Implement CSV output."""
    
    def write(self, mappings, filepath: str) -> None:
        # Write CSV
        pass
    
    def write_headers(self) -> str:
        return "scribe_id,lot_id,wafer_id,..."
    
    def format_record(self, mapping) -> str:
        return f"{mapping.scribe_id},{mapping.lot_id},..."
```

---

## Complete List of Protocols

**File & Format:**
- `FileReader` - Read/stream workstream files
- `FormatSpecParser` - Parse BCP format specs

**Extraction:**
- `Parser` - Extract/normalize fields
- `EquipmentCodeParser` - Decompose equipment codes
- `ScribeExtractor` - Extract scribe identifiers
- `LotWaferExtractor` - Extract lot/wafer identifiers
- `MultiSiteDetector` - Detect/expand multi-site records

**Processing:**
- `MappingGenerator` - Create bidirectional mappings
- `Validator` - Validate mapping records

**Output:**
- `OutputGenerator` - Base output protocol
- `CSVGenerator` - CSV output
- `JSONGenerator` - JSON output
- `IFFGenerator` - IFF/workstream output

**Services:**
- `LookupService` - Reverse lookups
- `ErrorHandler` - Error handling/reporting

---

## Type Annotations

All code uses complete type hints for mypy strict mode:

```python
from typing import List, Optional, Dict, Any
from scribe_lot_mapper import MappingRecord, ValidationResult

def process_mappings(
    records: List[MappingRecord],
    output_format: str = "csv"
) -> Dict[str, Any]:
    """Process and output mappings.
    
    Args:
        records: List of mapping records
        output_format: "csv", "json", or "iff"
    
    Returns:
        Dictionary with output statistics
    
    Raises:
        ValidationError: If records invalid
    """
    pass
```

---

## Common Patterns

### Creating a Valid MappingRecord
```python
from scribe_lot_mapper import MappingRecord
from uuid import uuid4
from datetime import datetime

mapping = MappingRecord(
    mapping_id=str(uuid4()),
    scribe_id="THK_1_51_LEFT_1",
    lot_id="KG4BNTCX",  # Must start with KG
    wafer_id="GOXTWS1125",
    test_program="GMBG3002",
    equipment_id="THK-1-51T",
    facility="FB6",
    timestamp="2026-07-14T03:34:33Z",  # ISO 8601
    created_at=datetime.now().isoformat() + "Z",
    test_value="301.2"
)

assert mapping.is_complete()
assert mapping.is_valid_lot_id()
assert mapping.is_valid_timestamp()
```

### Handling Multi-Site Records
```python
from scribe_lot_mapper import ParsedRecord

record = ParsedRecord(
    raw_line="...",
    parameter_set_id="GMBG3002",
    # ... other fields
    c_values=["301.2", "4.9", "5.7"],
    d_values=[],
)

if record.is_multi_site():
    num_sites = record.site_count()  # 3
    # Expander will create 3 separate MappingRecords
```

### Validation Workflow
```python
from scribe_lot_mapper import Validator, ValidationResult

# Assume validator and mapping exist
result = validator.validate(mapping)

if result.is_valid:
    print("Record is valid")
else:
    print(f"Errors: {result.error_summary()}")
    # Write to error file
```

---

## Next Steps

With Task 2 complete, implementations can:

1. **Task 3:** Implement FileReader using models
2. **Task 4:** Implement Parser to create ParsedRecords
3. **Tasks 5-8:** Implement Extractors using protocols
4. **Task 9:** Implement MappingGenerator using MappingRecord
5. **Task 10:** Implement Validator using ValidationResult
6. **Task 11:** Implement OutputGenerators for CSV/JSON/IFF
7. **Task 12:** Implement LookupService for queries
8. **Task 13:** Implement ErrorHandler

All components are type-safe and designed for comprehensive testing.

