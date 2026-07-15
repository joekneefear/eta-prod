"""Protocol interfaces for Scribe-Lot-Mapper service components.

This module defines Protocol interfaces (structural subtyping) for all major
components in the service. These protocols define the expected behavior of
implementations without forcing inheritance, allowing flexible, duck-typed
implementations.

Each protocol represents a component boundary, enabling:
- Type-safe composition of components
- Testability via mock implementations
- Clear separation of concerns
- Flexible implementation strategies
"""

from typing import Any, Dict, Iterator, List, Optional, Protocol, Union
from datetime import datetime

from .models import (
    ParsedRecord,
    EquipmentInfo,
    MappingRecord,
    LotHistoryRecord,
    LotAttributeRecord,
    ValidationResult,
)


# ============================================================================
# File and Format Protocols
# ============================================================================


class FileReader(Protocol):
    """Protocol for reading and streaming workstream extract files.

    Implementations must support:
    - Opening files with encoding/compression detection
    - Streaming records to avoid memory overhead
    - Validation before processing
    - Proper resource cleanup
    """

    def open(self, filepath: str) -> None:
        """Open and validate a workstream extract file.

        Args:
            filepath: Path to the file to open

        Raises:
            FileOperationError: If file cannot be opened or validated
        """
        ...

    def close(self) -> None:
        """Close the file and release resources."""
        ...

    def read(self) -> Iterator[str]:
        """Stream raw records from the file.

        Yields:
            Raw line/record from file

        Raises:
            FileOperationError: If read fails during streaming
        """
        ...

    def validate(self) -> bool:
        """Validate file format before processing.

        Returns:
            True if file format is valid, False otherwise
        """
        ...

    def detect_file_type(self, filepath: str) -> str:
        """Detect the file type from name pattern or content.

        Args:
            filepath: Path to file to analyze

        Returns:
            File type identifier ("phist", "lhist", "lot_attr", etc.)
        """
        ...


class FormatSpecParser(Protocol):
    """Protocol for parsing BCP format specification files.

    Format specs define column mappings and field definitions for phist files.
    Implementations should cache parsed specs for reuse.
    """

    def parse(self, spec_file: str) -> Dict[int, Dict[str, Any]]:
        """Parse a BCP format specification file.

        Args:
            spec_file: Path to .bcp_fmt format specification file

        Returns:
            Mapping of column index to field metadata
            {0: {'name': 'parameter_set_id', 'type': 'string'}, ...}

        Raises:
            FileOperationError: If spec file cannot be read
            ParsingError: If spec format is invalid
        """
        ...

    def get_cached_spec(self, spec_file: str) -> Optional[Dict[int, Dict[str, Any]]]:
        """Retrieve cached specification if available.

        Args:
            spec_file: Path to spec file to look up in cache

        Returns:
            Cached spec or None if not cached
        """
        ...

    def clear_cache(self) -> None:
        """Clear all cached specifications."""
        ...


# ============================================================================
# Extraction Protocols
# ============================================================================


class Parser(Protocol):
    """Protocol for extracting and normalizing individual record fields.

    Implementations handle field extraction according to format specs,
    whitespace normalization, and special character handling.
    """

    def parse_record(self, raw_line: str, format_spec: Dict[int, Dict[str, Any]]) -> ParsedRecord:
        """Parse a raw record line into structured fields.

        Args:
            raw_line: Unparsed record from file
            format_spec: Field definitions from format specification

        Returns:
            ParsedRecord with all fields extracted

        Raises:
            ParsingError: If parsing fails
        """
        ...

    def parse_field(self, field_value: str, field_type: str) -> Any:
        """Parse a single field according to its type.

        Args:
            field_value: Raw field value from record
            field_type: Data type identifier

        Returns:
            Parsed field value with appropriate type
        """
        ...

    def normalize_value(self, value: str) -> str:
        """Normalize a value (whitespace, special chars, etc.).

        Args:
            value: Raw value to normalize

        Returns:
            Normalized value
        """
        ...


class EquipmentCodeParser(Protocol):
    """Protocol for decomposing equipment codes into components.

    Equipment codes follow structure: [FACILITY]-[PROBE]-[POSITION][TYPE]
    Example: THK-1-51T → facility=THK, probe=1, position=51, type=T
    """

    def parse(self, equipment_code: str) -> EquipmentInfo:
        """Parse and decompose an equipment code.

        Args:
            equipment_code: Equipment identifier to parse

        Returns:
            EquipmentInfo with all components extracted

        Raises:
            ExtractionError: If code cannot be decomposed
        """
        ...

    def normalize(self, equipment_code: str) -> str:
        """Normalize equipment code to standard format.

        Args:
            equipment_code: Code to normalize

        Returns:
            Normalized equipment code
        """
        ...


class ScribeExtractor(Protocol):
    """Protocol for extracting and normalizing scribe position identifiers.

    Scribe IDs are extracted from unit_id and equipment context,
    handling various formats (LEFT, CENTER, A6, 1, etc.).
    """

    def extract(
        self,
        unit_id: str,
        equipment_info: EquipmentInfo,
        site_number: int = 1,
    ) -> str:
        """Extract and normalize scribe identifier.

        Args:
            unit_id: Scribe position from record (e.g., "LEFT", "A6")
            equipment_info: Parsed equipment information
            site_number: Multi-site measurement index (1-5)

        Returns:
            Normalized scribe_id

        Raises:
            ExtractionError: If scribe cannot be extracted
        """
        ...

    def normalize(self, unit_id: str) -> str:
        """Normalize unit_id to standard format.

        Args:
            unit_id: Raw unit_id from record

        Returns:
            Normalized scribe identifier
        """
        ...


class LotWaferExtractor(Protocol):
    """Protocol for extracting lot and wafer identifiers and relationships.

    Handles lot extraction (KG* pattern), wafer extraction (GOXTWS* pattern),
    and virtual wafer ID generation when source not present.
    """

    def extract(
        self, record: ParsedRecord
    ) -> tuple[str, str, str]:
        """Extract lot, wafer, and wafer family from record.

        Args:
            record: ParsedRecord to extract from

        Returns:
            Tuple of (lot_id, wafer_id, wafer_family)

        Raises:
            ExtractionError: If extraction fails
        """
        ...

    def normalize_lot(self, lot_string: str) -> str:
        """Normalize lot identifier to standard format.

        Args:
            lot_string: Raw lot identifier

        Returns:
            Normalized lot_id
        """
        ...

    def normalize_wafer(self, wafer_string: str) -> str:
        """Normalize wafer identifier to standard format.

        Args:
            wafer_string: Raw wafer identifier

        Returns:
            Normalized wafer_id
        """
        ...

    def generate_virtual_wafer(
        self,
        lot_id: str,
        equipment_id: str,
        timestamp: str,
    ) -> str:
        """Generate virtual wafer ID when source not present.

        Args:
            lot_id: Lot identifier
            equipment_id: Equipment where test occurred
            timestamp: Test execution timestamp

        Returns:
            Generated virtual wafer_id
        """
        ...


class MultiSiteDetector(Protocol):
    """Protocol for detecting and expanding multi-site test records.

    Multi-site records contain measurements for multiple scribes (1-5 sites).
    Implementations must detect site count and expand into separate records.
    """

    def detect(self, record: ParsedRecord) -> int:
        """Detect number of sites in record.

        Counts non-empty c_value and d_value fields (max 5 sites).

        Args:
            record: ParsedRecord to analyze

        Returns:
            Number of sites (1-5)
        """
        ...

    def expand(self, record: ParsedRecord) -> List[ParsedRecord]:
        """Expand multi-site record into separate single-site records.

        Args:
            record: ParsedRecord to expand

        Returns:
            List of single-site ParsedRecords
        """
        ...

    def extract_site_values(self, record: ParsedRecord, site_index: int) -> Dict[str, Any]:
        """Extract values for specific site from multi-site record.

        Args:
            record: ParsedRecord containing multiple sites
            site_index: Index of site to extract (1-5)

        Returns:
            Dictionary of field values for this site
        """
        ...


# ============================================================================
# Mapping Generation Protocol
# ============================================================================


class MappingGenerator(Protocol):
    """Protocol for creating bidirectional mapping records.

    Implementations generate MappingRecords linking scribe ↔ lot ↔ wafer,
    creating indices for both forward and reverse lookups.
    """

    def generate(self, parsed_record: ParsedRecord) -> MappingRecord:
        """Generate mapping record from parsed record.

        Args:
            parsed_record: ProcessedRecord after extraction

        Returns:
            Complete MappingRecord with all relationships

        Raises:
            MappingError: If mapping cannot be created
        """
        ...

    def create_bidirectional_mapping(
        self,
        scribe_id: str,
        lot_id: str,
        wafer_id: str,
    ) -> MappingRecord:
        """Create bidirectional mapping with all relationships.

        Args:
            scribe_id: Normalized scribe position
            lot_id: Manufacturing lot identifier
            wafer_id: Wafer identifier

        Returns:
            MappingRecord with all three relationships

        Raises:
            MappingError: If mapping creation fails
        """
        ...

    def assign_mapping_id(self, mapping: MappingRecord) -> str:
        """Assign unique mapping ID (UUID) to record.

        Args:
            mapping: MappingRecord to assign ID to

        Returns:
            Unique mapping_id (UUID v4)
        """
        ...


# ============================================================================
# Validation Protocol
# ============================================================================


class Validator(Protocol):
    """Protocol for validating mapping completeness and consistency.

    Implementations check that records contain required fields and maintain
    lot-wafer consistency.
    """

    def validate(self, mapping: MappingRecord) -> ValidationResult:
        """Validate a single mapping record.

        Args:
            mapping: MappingRecord to validate

        Returns:
            ValidationResult with pass/fail status and errors

        Raises:
            ValidationError: If validation fails critically
        """
        ...

    def check_completeness(self, mapping: MappingRecord) -> bool:
        """Check that record contains all required fields.

        Args:
            mapping: MappingRecord to check

        Returns:
            True if complete, False otherwise
        """
        ...

    def check_consistency(self, mapping: MappingRecord) -> bool:
        """Check lot-wafer consistency and format validity.

        Args:
            mapping: MappingRecord to check

        Returns:
            True if consistent, False otherwise
        """
        ...

    def generate_report(self) -> Dict[str, Any]:
        """Generate validation report.

        Returns:
            Dictionary with validation statistics:
            {
                'total_records': int,
                'valid_records': int,
                'incomplete_records': int,
                'inconsistent_records': int
            }
        """
        ...


# ============================================================================
# Output Generation Protocols
# ============================================================================


class OutputGenerator(Protocol):
    """Base protocol for output generation in any format.

    Implementations handle format-specific output generation and file writing.
    """

    def write(self, mappings: List[MappingRecord], filepath: str) -> None:
        """Write mapping records to output file in specific format.

        Args:
            mappings: List of MappingRecords to write
            filepath: Path to output file

        Raises:
            FileOperationError: If write fails
        """
        ...

    def write_headers(self) -> str:
        """Generate format-specific headers.

        Returns:
            Header string for output format
        """
        ...

    def format_record(self, mapping: MappingRecord) -> str:
        """Format single mapping record for output.

        Args:
            mapping: MappingRecord to format

        Returns:
            Formatted record string
        """
        ...


class CSVGenerator(Protocol):
    """Protocol for CSV output generation.

    Implementations generate CSV with proper escaping and headers.
    """

    def write(self, mappings: List[MappingRecord], filepath: str) -> None:
        """Write mappings to CSV file.

        Args:
            mappings: List of MappingRecords
            filepath: Output file path

        Raises:
            FileOperationError: If write fails
        """
        ...


class JSONGenerator(Protocol):
    """Protocol for JSON output generation.

    Implementations generate hierarchical JSON with proper serialization.
    """

    def write(self, mappings: List[MappingRecord], filepath: str) -> None:
        """Write mappings to JSON file.

        Args:
            mappings: List of MappingRecords
            filepath: Output file path

        Raises:
            FileOperationError: If write fails
        """
        ...


class IFFGenerator(Protocol):
    """Protocol for IFF (workstream format) output generation.

    Implementations follow workstream standards with vertical tab delimiters.
    """

    def write(self, mappings: List[MappingRecord], filepath: str) -> None:
        """Write mappings to IFF file.

        Args:
            mappings: List of MappingRecords
            filepath: Output file path

        Raises:
            FileOperationError: If write fails
        """
        ...


# ============================================================================
# Service Protocols
# ============================================================================


class LookupService(Protocol):
    """Protocol for performing scribe↔lot reverse lookups.

    Implementations provide forward and reverse query capabilities
    with optional filtering by date range, facility, or test program.
    """

    def find_lots_by_scribe(self, scribe_id: str) -> List[tuple[str, str, Dict[str, Any]]]:
        """Find all lots and wafers used for a scribe.

        Args:
            scribe_id: Scribe identifier to query

        Returns:
            List of (lot_id, wafer_id, metadata) tuples

        Raises:
            ExtractionError: If query fails
        """
        ...

    def find_scribes_by_lot(self, lot_id: str) -> List[tuple[str, Dict[str, Any]]]:
        """Find all scribes processed in a lot.

        Args:
            lot_id: Lot identifier to query

        Returns:
            List of (scribe_id, metadata) tuples

        Raises:
            ExtractionError: If query fails
        """
        ...

    def query_by_date_range(
        self,
        scribe_id: str,
        start_date: str,
        end_date: str,
    ) -> List[MappingRecord]:
        """Query mappings by date range.

        Args:
            scribe_id: Scribe identifier
            start_date: ISO 8601 start date
            end_date: ISO 8601 end date

        Returns:
            List of matching MappingRecords
        """
        ...

    def query_by_facility(self, facility: str) -> List[MappingRecord]:
        """Query all mappings for a facility.

        Args:
            facility: Facility code to filter by

        Returns:
            List of matching MappingRecords
        """
        ...

    def query_by_test_program(self, test_program: str) -> List[MappingRecord]:
        """Query all mappings for a test program.

        Args:
            test_program: Test program identifier to filter by

        Returns:
            List of matching MappingRecords
        """
        ...


class ErrorHandler(Protocol):
    """Protocol for centralized error handling and reporting.

    Implementations log errors with context, track error types,
    and generate error reports.
    """

    def log_error(
        self,
        error_type: str,
        message: str,
        context: Dict[str, Any],
    ) -> None:
        """Log an error with context information.

        Args:
            error_type: Type of error (ParsingError, ValidationError, etc.)
            message: Error message
            context: Context dict (line_number, field_name, file_name, etc.)
        """
        ...

    def write_error_record(self, record_data: Dict[str, Any], filepath: str) -> None:
        """Write error record to .err output file.

        Args:
            record_data: Failed record data
            filepath: Path to error output file
        """
        ...

    def generate_error_report(self) -> Dict[str, Any]:
        """Generate error report.

        Returns:
            Dictionary with error statistics:
            {
                'error_count': int,
                'error_types': {type: count, ...},
                'sample_errors': [error_msg, ...]
            }
        """
        ...

    def clear_errors(self) -> None:
        """Clear all accumulated errors."""
        ...
