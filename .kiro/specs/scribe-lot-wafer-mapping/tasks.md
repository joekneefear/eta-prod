# Implementation Plan: Scribe-to-Lot/Wafer Mapping Service

## Overview

This plan breaks down the design into discrete, incremental implementation tasks using Python 3.9+ with best practices. Each task builds on previous steps and ends with working, tested code. The implementation follows a bottom-up approach: build core parsing and extraction components first, then integrate them into mapping generation, validation, and output stages.

All code follows PEP 8, uses type hints, includes comprehensive docstrings, and is tested with pytest and hypothesis.

---

## Tasks

- [x] 1. Set up Python project structure with best practices
  - Initialize project with pyproject.toml and Poetry/pip configuration
  - Set up directory structure (src/, tests/, docs/)
  - Configure type checking (mypy), formatting (black), linting (ruff)
  - Create base modules: exceptions.py, models.py, config.py
  - Set up pytest and hypothesis for testing
  - Create Makefile for common tasks (lint, format, test, type-check)
  - _Requirements: 10.1, 10.2, 10.3_

- [x] 2. Implement core data models and interfaces
  - Create dataclasses: ParsedRecord, EquipmentInfo, MappingRecord, LotHistoryRecord, LotAttributeRecord
  - Define Protocol interfaces for each component (FileReader, Parser, Extractor, etc.)
  - Create custom exceptions: ParsingError, ExtractionError, ValidationError, etc.
  - Add comprehensive type hints and docstrings throughout
  - _Requirements: all_

- [x] 3. Implement file handling and format detection
  - [x] 3.1 Create FileReader class with streaming support
    - Read and validate phist, lhist, lot_attr files
    - Detect file encoding and compression (gzip)
    - Implement __iter__ for streaming records
    - Add logging for file operations and errors
    - _Requirements: 1.1, 1.2_

  - [x] 3.2 Create FormatSpecParser for BCP format specifications
    - Parse .bcp_fmt files into column mappings
    - Validate format specifications
    - Cache parsed specs for reuse
    - _Requirements: 1.1_

- [x] 4. Implement field extraction and normalization
  - [x] 4.1 Create Parser class for record field extraction
    - Extract fields according to BCP format spec
    - Handle tab and whitespace delimiters
    - Normalize special characters and whitespace
    - Type-hint all extraction methods
    - _Requirements: 1.3, 1.4, 1.5_

  - [x] 4.2 Create TimestampNormalizer utility
    - Parse various date formats (e.g., "JUL 14 2026 03:00:16:000AM")
    - Normalize to ISO 8601 format
    - Handle timezone conversions
    - _Requirements: 1.4_

- [-] 5. Implement equipment code decomposition
  - [x] 5.1 Create EquipmentParser class
    - Decompose equipment codes (THK-1-51T, RI-1-11, etc.)
    - Extract facility, probe, position, type components
    - Handle unknown patterns gracefully
    - Add comprehensive docstrings with examples
    - _Requirements: 2.1_

- [x] 6. Implement scribe extraction and normalization
  - [x] 6.1 Create ScribeExtractor class
    - Extract scribe from unit_id field
    - Normalize directional indicators
    - Generate composite scribe_id
    - Return structured ScribeInfo object
    - _Requirements: 2.2, 2.3_

- [x] 7. Implement lot and wafer extraction
  - [x] 7.1 Create LotWaferExtractor class
    - Extract lot identifiers (KG* pattern)
    - Extract wafer batch identifiers (GOXTWS* pattern)
    - Generate virtual wafer IDs when missing
    - Validate format correctness
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [x] 8. Implement multi-site record detection and expansion
  - [x] 8.1 Create MultiSiteDetector class
    - Detect number of sites from c_value and d_value fields
    - Expand multi-site records into separate single-site records
    - Preserve parent-child relationships
    - Return list of expanded records
    - _Requirements: 7.1, 7.2, 7.3_

- [x] 9. Implement bidirectional mapping generation
  - [x] 9.1 Create MappingGenerator class
    - Generate mapping records linking scribe → lot → wafer
    - Create bidirectional indices
    - Assign unique mapping_ids (UUID)
    - Include all contextual metadata
    - Return MappingRecord dataclass instances
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 10. Implement validation engine
  - [x] 10.1 Create Validator class
    - Check record completeness (scribe_id, lot_id, wafer_id present)
    - Check consistency (format validation, cross-reference checks)
    - Generate validation reports with counts and error summaries
    - Return ValidationResult with valid/invalid record lists
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

- [x] 11. Implement output generation (CSV, JSON, IFF)
  - [x] 11.1 Create OutputGenerator base class with write method
    - Abstract base for all output formats
    - Handle file write errors and permission issues
    - Add logging for output operations

  - [x] 11.2 Create CSVGenerator class
    - Generate CSV output with proper escaping
    - Use pandas DataFrame for robust handling
    - Include headers and all required columns
    - _Requirements: 5.1, 5.2_

  - [x] 11.3 Create JSONGenerator class
    - Generate JSON output with hierarchical structure
    - Use json library with proper serialization
    - Handle dataclass to dict conversion
    - _Requirements: 5.3_

  - [x] 11.4 Create IFFGenerator class
    - Generate IFF output with workstream format
    - Implement proper headers and separators
    - Handle vertical tab delimiters
    - _Requirements: 5.4_

- [x] 12. Implement lookup service (reverse queries)
  - [x] 12.1 Create LookupService class
    - Implement scribe→lot lookup
    - Implement lot→scribe lookup
    - Support filtering by date range, facility, test program
    - Load mapping data into in-memory indices
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [x] 13. Implement error handling framework
  - [x] 13.1 Create ErrorHandler class
    - Log errors with context (line number, field name, file name)
    - Track error counts and types
    - Generate error reports
    - Write error records to .err output files
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_

- [x] 14. Create main CLI script with Click
  - [x] 14.1 Create main.py with Click CLI interface
    - Parse command-line arguments (-input, -output, -format, etc.)
    - Implement -help and -version options
    - Orchestrate component pipeline
    - Handle startup and shutdown errors
    - Return appropriate exit codes
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

  - [x] 14.2 Wire all components together in main script
    - Initialize FileReader with input filepath
    - Chain Parser → EquipmentParser → ScribeExtractor → LotWaferExtractor
    - Apply MultiSiteDetector and expand records
    - Generate mappings with MappingGenerator
    - Run Validator and separate records
    - Generate output with all enabled formats
    - Report final statistics and error counts
    - _Requirements: all_

- [x] 15. Create comprehensive test suite
  - [x] 15.1 Write unit tests for all extractors
    - EquipmentParser: standard codes, malformed codes, decomposition accuracy
    - ScribeExtractor: various unit_id formats, directional normalization
    - LotWaferExtractor: lot extraction, wafer patterns, virtual ID generation
    - MultiSiteDetector: single-site, multi-site, expansion accuracy
    - MappingGenerator: record creation, bidirectional indices, mapping_id uniqueness
    - Validator: completeness checks, consistency checks, error separation
    - All tests in tests/unit/ with 90%+ code coverage

  - [x] 15.2 Write property-based tests with hypothesis
    - **Property 1: Lot-Scribe Bidirectionality** - Forward/reverse consistency
    - **Property 2: Scribe Extraction Consistency** - Deterministic scribe_id
    - **Property 3: Lot-Wafer Invariant** - Many-to-one lot-wafer relationship
    - **Property 4: Multi-Site Expansion Completeness** - Correct expansion count
    - **Property 5: Validation Error Separation** - Invalid records in error output
    - **Property 6: Reverse Lookup Consistency** - Returned lots have mapping records
    - **Property 7: Timestamp Normalization** - Idempotent ISO 8601 conversion
    - **Property 8: Mapping ID Uniqueness** - No duplicate mapping_ids
    - All tests in tests/property_based/ with strategies for each property

  - [x] 15.3 Write integration test for end-to-end processing
    - Test with sample phist file (small dataset)
    - Verify CSV, JSON, and IFF outputs generated correctly
    - Verify error handling for partial failures
    - Verify exit codes and status messages
    - Test in tests/integration/test_end_to_end.py

- [x] 16. Code quality and best practices
  - Run mypy strict mode type checking and fix all issues
  - Run black formatter for code style consistency
  - Run ruff linter and fix all issues
  - Ensure 90%+ code coverage with pytest
  - Add comprehensive docstrings (Google style) to all modules
  - Create README.md with usage examples
  - Create CONTRIBUTING.md for development guidelines

- [x] 17. Checkpoint - Production readiness validation
  - All unit tests pass
  - All property-based tests pass
  - Integration test passes
  - Type checking passes (mypy strict)
  - Code formatting passes (black)
  - Linting passes (ruff)
  - Code coverage ≥ 90%
  - Documentation complete
  - Ready for deployment

---

## Notes

- All code must use type hints (mypy strict mode)
- All modules must have docstrings (Google/NumPy style)
- All dataclasses must be immutable where appropriate (frozen=True)
- All I/O operations must use logging
- All custom exceptions inherit from custom base exception classes
- Unit tests should use pytest fixtures for common setup
- Property tests use hypothesis with appropriate search strategies
- Integration tests use actual workstream data files
- CI/CD ready: GitHub Actions workflow for lint/type/test checks

---

**Implementation Language:** Python 3.9+  
**Test Framework:** pytest + hypothesis  
**Type Checking:** mypy (strict mode)  
**Code Quality:** black + ruff  
**Execution Method:** Sequential task execution with checkpoints every 3-4 tasks
