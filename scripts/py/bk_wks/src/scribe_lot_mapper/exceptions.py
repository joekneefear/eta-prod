"""Custom exception classes for Scribe-Lot-Mapper service.

This module defines the exception hierarchy used throughout the service for
error handling and reporting.
"""


class ScribeLotMapperError(Exception):
    """Base exception for all Scribe-Lot-Mapper errors.

    All custom exceptions in this service inherit from this base class,
    allowing callers to catch all service-specific errors uniformly.
    """

    pass


class ParsingError(ScribeLotMapperError):
    """Raised when parsing workstream records fails.

    This exception is raised when:
    - File format is invalid or unreadable
    - Record structure doesn't match expected format
    - Required fields are missing or malformed
    """

    pass


class ExtractionError(ScribeLotMapperError):
    """Raised when field extraction or normalization fails.

    This exception is raised when:
    - Equipment code cannot be decomposed
    - Scribe identifier cannot be extracted
    - Lot/wafer identifiers are invalid
    - Timestamp cannot be parsed
    """

    pass


class MappingError(ScribeLotMapperError):
    """Raised when mapping record creation fails.

    This exception is raised when:
    - Required mapping components are missing
    - Bidirectional mapping cannot be established
    - Mapping ID assignment fails
    """

    pass


class ValidationError(ScribeLotMapperError):
    """Raised when validation of mapping records fails.

    This exception is raised when:
    - Record is incomplete (missing scribe_id, lot_id, or wafer_id)
    - Lot-wafer consistency check fails
    - Invalid field values detected
    """

    pass


class FileOperationError(ScribeLotMapperError):
    """Raised when file operations fail.

    This exception is raised when:
    - Input file cannot be opened or read
    - Output file cannot be written
    - File encoding issues occur
    - File format cannot be determined
    """

    pass


class ConfigurationError(ScribeLotMapperError):
    """Raised when configuration is invalid.

    This exception is raised when:
    - Required configuration values are missing
    - Configuration values are out of valid range
    - Configuration conflicts exist
    """

    pass
