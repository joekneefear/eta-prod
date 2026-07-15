# Scribe-to-Lot/Wafer Mapping Service

Manufacturing traceability service that extracts and normalizes scribe position, lot, and wafer identifiers from workstream parameter history files. Creates bidirectional mappings enabling both forward (lot→scribe) and reverse (scribe→lot) lookup for defect analysis and yield correlation.

## Features

- **Bidirectional Mapping**: Link scribes ↔ lots ↔ wafers in both directions
- **Multi-Site Support**: Handle workstream records with measurements from multiple scribe sites (c_value/d_value arrays)
- **Format Support**: Read tab/whitespace-delimited workstream files (phist format)
- **Multi-Format Output**: Generate CSV, JSON, and IFF (workstream) format outputs
- **Validation Engine**: Comprehensive validation with detailed error reporting
- **Reverse Lookup**: Query scribes by lot or lots by scribe with filtering by date/facility/test program
- **Error Handling**: Robust error handling with detailed logging and error record separation

## Installation

```bash
cd scripts/py/bk_wks
pip install -e ".[dev]"
```

## Quick Start

### Basic Usage

```bash
scribe-lot-mapper \
  --input workstream_extract.phist \
  --output ./mappings \
  --format csv
```

### With Filtering

```bash
scribe-lot-mapper \
  --input workstream_extract.phist \
  --output ./mappings \
  --format csv,json \
  --facility BUCHEON \
  --product "GMBG*"
```

### Reverse Lookup

```bash
scribe-lot-mapper \
  --lookup \
  --scribe "THK_1_51_LEFT_1" \
  --mapping-db ./mappings/mappings.csv
```

## Architecture

### Core Components

1. **FileReader** - Stream workstream extract files with encoding detection
2. **FormatSpecParser** - Parse BCP format specifications (.bcp_fmt)
3. **Parser** - Extract and normalize record fields
4. **EquipmentParser** - Decompose equipment codes (e.g., THK-1-51T)
5. **ScribeExtractor** - Extract and normalize scribe position identifiers
6. **LotWaferExtractor** - Extract lot and wafer identifiers
7. **MultiSiteDetector** - Detect and expand multi-site records
8. **MappingGenerator** - Create bidirectional mapping records
9. **Validator** - Validate mapping completeness and consistency
10. **OutputGenerator** - Generate CSV, JSON, IFF outputs
11. **LookupService** - Provide scribe/lot reverse lookup
12. **ErrorHandler** - Centralized error handling and reporting

### Data Models

- **ParsedRecord** - Raw extracted fields from workstream record
- **EquipmentInfo** - Decomposed equipment code components
- **MappingRecord** - Complete mapping with all relationships (scribe + lot + wafer)
- **ValidationResult** - Validation outcome with pass/fail details

## Development

### Running Tests

```bash
# All tests with coverage
make test

# Unit tests only
pytest tests/unit/

# Property-based tests
pytest tests/property_based/

# Integration tests
pytest tests/integration/
```

### Code Quality

```bash
# Type checking
make type-check

# Formatting
make format

# Linting
make lint

# All checks
make check
```

### Project Structure

```
scripts/py/bk_wks/
├── src/scribe_lot_mapper/
│   ├── __init__.py
│   ├── main.py                    # CLI entry point
│   ├── config.py                  # Configuration and settings
│   ├── exceptions.py              # Custom exceptions
│   ├── models.py                  # Data models (dataclasses)
│   ├── readers/
│   │   ├── __init__.py
│   │   ├── file_reader.py         # FileReader component
│   │   └── format_parser.py       # FormatSpecParser component
│   ├── extractors/
│   │   ├── __init__.py
│   │   ├── parser.py              # Parser component
│   │   ├── equipment_parser.py    # EquipmentParser component
│   │   ├── scribe_extractor.py    # ScribeExtractor component
│   │   ├── lot_wafer_extractor.py # LotWaferExtractor component
│   │   └── multi_site_detector.py # MultiSiteDetector component
│   ├── mappers/
│   │   ├── __init__.py
│   │   └── mapping_generator.py   # MappingGenerator component
│   ├── validators/
│   │   ├── __init__.py
│   │   └── validator.py           # Validator component
│   ├── generators/
│   │   ├── __init__.py
│   │   ├── base.py                # OutputGenerator base class
│   │   ├── csv_generator.py       # CSVGenerator component
│   │   ├── json_generator.py      # JSONGenerator component
│   │   └── iff_generator.py       # IFFGenerator component
│   ├── services/
│   │   ├── __init__.py
│   │   ├── lookup_service.py      # LookupService component
│   │   └── error_handler.py       # ErrorHandler component
│   └── utils/
│       ├── __init__.py
│       └── timestamp_normalizer.py # Timestamp normalization utility
├── tests/
│   ├── __init__.py
│   ├── conftest.py                # pytest fixtures
│   ├── unit/                       # Unit tests (90%+ coverage target)
│   ├── property_based/             # Hypothesis property tests
│   └── integration/                # End-to-end tests
├── docs/
│   ├── ARCHITECTURE.md
│   ├── API.md
│   └── DEVELOPMENT.md
├── Makefile
├── pyproject.toml
├── README.md
└── .gitignore
```

## Correctness Properties

The service ensures 8 formal correctness properties verified through property-based testing:

1. **Lot-Scribe Bidirectionality** - Forward/reverse mapping consistency
2. **Scribe Extraction Consistency** - Deterministic scribe_id generation
3. **Lot-Wafer Invariant** - Many-to-one lot-wafer relationship
4. **Multi-Site Expansion Completeness** - Correct expansion count and values
5. **Validation Error Separation** - Invalid records in error output only
6. **Reverse Lookup Consistency** - Returned lots have mapping records
7. **Timestamp Normalization** - Idempotent ISO 8601 conversion
8. **Mapping ID Uniqueness** - No duplicate mapping_ids

## License

Proprietary - Manufacturing Analytics

## Contact

For questions or issues: analytics@example.com
