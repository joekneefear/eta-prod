# Contributing to Scribe-Lot-Mapper

## Development Setup

### Prerequisites
- Python 3.9+
- pip or Poetry for dependency management

### Installation

```bash
# Clone the repository (or navigate to your working copy)
cd scripts/py/bk_wks

# Install in development mode with all dependencies
pip install -e ".[dev]"

# Or with Poetry
poetry install --with dev
```

## Code Quality Standards

### Type Hints
All code must use Python type hints with **mypy strict mode** enabled:

```bash
make type-check
```

Example:
```python
def extract_scribe(
    unit_id: str,
    equipment_info: EquipmentInfo,
    site_number: int = 1,
) -> str:
    """Extract scribe identifier."""
    ...
```

### Code Formatting
Code must be formatted with **black** (line length: 100):

```bash
make format
```

### Linting
Code must pass **ruff** linting:

```bash
make lint
```

### Docstrings
All modules, classes, and functions must have comprehensive docstrings in Google style:

```python
def generate(
    self,
    records: List[MappingRecord],
    filename: str = "mappings.csv",
) -> None:
    """Generate CSV output file.

    Args:
        records: List of mapping records to output
        filename: Output filename (default: mappings.csv)

    Raises:
        FileOperationError: If file cannot be written
    """
    ...
```

## Testing

### Unit Tests
```bash
make test-unit
```

Tests go in `tests/unit/` with naming pattern `test_*.py`:

```python
import pytest
from scribe_lot_mapper.extractors import EquipmentParser

def test_equipment_parser_decompose():
    """Test equipment code decomposition."""
    parser = EquipmentParser()
    facility, probe, position, type_ = parser.decompose("THK-1-51T")
    
    assert facility == "THK"
    assert probe == 1
    assert position == 51
    assert type_ == "T"
```

### Property-Based Tests
```bash
make test-property
```

Tests go in `tests/property_based/` using **hypothesis**:

```python
from hypothesis import given, strategies as st

@given(st.text(min_size=1, max_size=20))
def test_scribe_extraction_consistency(unit_id: str):
    """Test that scribe extraction is deterministic."""
    extractor = ScribeExtractor()
    
    result1 = extractor.normalize(unit_id)
    result2 = extractor.normalize(unit_id)
    
    assert result1 == result2
```

### Integration Tests
```bash
make test-integration
```

Tests go in `tests/integration/` for end-to-end scenarios:

```python
def test_end_to_end_mapping_generation(sample_input_file, output_dir):
    """Test complete mapping pipeline."""
    # Read input, process, generate output
    # Verify output format and content
    ...
```

### Code Coverage
Target: **90%+ coverage**

```bash
make test  # Runs all tests and generates coverage report
```

## Development Workflow

### 1. Create Feature Branch
```bash
git checkout -b feature/my-feature
```

### 2. Implement Feature
- Write code following all style guidelines
- Add comprehensive docstrings
- Include type hints
- Write tests (unit + property-based + integration)

### 3. Verify Quality
```bash
make check  # Runs type-check, lint, format, and tests
```

### 4. Commit Changes
```bash
# Stage specific files (not `git add .`)
git add src/scribe_lot_mapper/my_module.py
git add tests/unit/test_my_module.py

# Commit with clear message
git commit -m "feat: implement equipment parser decomposition"
```

### 5. Create Pull Request
- Reference related issues
- Provide clear description of changes
- Ensure all checks pass

## File Structure

### Source Code
```
src/scribe_lot_mapper/
├── __init__.py              # Package exports
├── exceptions.py            # Custom exceptions
├── models.py                # Data models (dataclasses)
├── config.py                # Configuration management
├── main.py                  # CLI entry point
├── readers/
│   ├── file_reader.py       # FileReader component
│   └── format_parser.py     # FormatSpecParser component
├── extractors/
│   ├── parser.py            # Parser component
│   ├── equipment_parser.py
│   ├── scribe_extractor.py
│   ├── lot_wafer_extractor.py
│   └── multi_site_detector.py
├── mappers/
│   └── mapping_generator.py
├── validators/
│   └── validator.py
├── generators/
│   ├── base.py              # OutputGenerator base class
│   ├── csv_generator.py
│   ├── json_generator.py
│   └── iff_generator.py
├── services/
│   ├── lookup_service.py
│   └── error_handler.py
└── utils/
    └── timestamp_normalizer.py
```

### Test Structure
```
tests/
├── conftest.py              # pytest fixtures and configuration
├── unit/
│   ├── test_equipment_parser.py
│   ├── test_scribe_extractor.py
│   ├── test_lot_wafer_extractor.py
│   └── ... (one test file per component)
├── property_based/
│   ├── test_properties.py   # All property-based tests
│   └── strategies.py        # Custom hypothesis strategies
└── integration/
    └── test_end_to_end.py
```

## Correctness Properties

When implementing features, ensure they satisfy the documented correctness properties:

1. **Lot-Scribe Bidirectionality** - Forward/reverse mapping consistency
2. **Scribe Extraction Consistency** - Deterministic scribe_id generation
3. **Lot-Wafer Invariant** - Many-to-one lot-wafer relationship
4. **Multi-Site Expansion Completeness** - Correct expansion count
5. **Validation Error Separation** - Invalid records in error output
6. **Reverse Lookup Consistency** - Returned lots have mapping records
7. **Timestamp Normalization** - Idempotent ISO 8601 conversion
8. **Mapping ID Uniqueness** - No duplicate mapping_ids

See `design.md` for detailed property descriptions.

## Common Tasks

### Add a New Component
1. Create component module in appropriate subpackage
2. Define public interface with type hints
3. Add comprehensive docstrings
4. Create unit tests in `tests/unit/`
5. Create property-based tests in `tests/property_based/`
6. Update `__init__.py` imports
7. Run `make check` to verify

### Modify Data Models
1. Update dataclass definition in `models.py`
2. Update all components that create/consume the model
3. Add migration tests
4. Update documentation in design.md
5. Run `make check`

### Add Configuration Option
1. Add field to appropriate config dataclass in `config.py`
2. Update configuration loading logic
3. Add validation if needed
4. Document in README.md
5. Run `make check`

## Debugging

### Enable Debug Logging
```bash
SCRIBE_MAPPER_LOGGING_LEVEL=DEBUG scribe-lot-mapper map-records ...
```

### Use pytest with Debugging
```bash
# Stop on first failure with debugger
pytest -x --pdb tests/

# Show print statements
pytest -s tests/test_my_module.py

# Verbose output with test names
pytest -v tests/
```

### Type Checking Errors
```bash
# Show detailed mypy errors
mypy src/scribe_lot_mapper/ --strict --show-error-codes
```

## Performance Considerations

- Use `__slots__` in hot path classes for memory efficiency
- Prefer generators for large file processing (lazy evaluation)
- Cache expensive computations (format specs, parsed indices)
- Profile with `cProfile` for bottlenecks: `python -m cProfile -s cumtime main.py`

## Documentation

- Update README.md for user-facing changes
- Add docstrings to all public APIs
- Update design.md for architectural changes
- Include examples in complex function docstrings

## Questions?

- Review existing test files for patterns
- Check design.md for architecture details
- Read requirement.md for feature specifications
