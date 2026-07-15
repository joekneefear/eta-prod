"""Custom exception classes for Scribe-Lot-Mapper service.

This module defines the exception hierarchy used throughout the service for
error handling and reporting.
"""

from typing import Optional


class ScribeLotMapperError(Exception):
    """Base exception for all Scribe-Lot-Mapper errors.

    All custom exceptions in this service inherit from this base class,
    allowing callers to catch all service-specific errors uniformly.
    """

    def __init__(
        self,
        message: str,
        error_code: Optional[str] = None,
        context: Optional[dict] = None,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.error_code = error_code
        self.context = context or {}

    def __str__(self) -> str:
        msg = self.message
        if self.error_code:
            msg = f"[{self.error_code}] {msg}"
        if self.context:
            context_str = ", ".join(f"{k}={v}" for k, v in self.context.items())
            msg = f"{msg} ({context_str})"
        return msg


class ParsingError(ScribeLotMapperError):
    """Raised when parsing workstream records fails.

    This exception is raised when:
    - File format is invalid or unreadable
    - Record structure doesn't match expected format
    - Required fields are missing or malformed
    """

    def __init__(
        self,
        message: str,
        line_number: Optional[int] = None,
        file_name: Optional[str] = None,
        error_code: str = "PARSE_001",
    ) -> None:
        context = {}
        if line_number is not None:
            context["line_number"] = line_number
        if file_name is not None:
            context["file_name"] = file_name
        super().__init__(message, error_code=error_code, context=context)


class ExtractionError(ScribeLotMapperError):
    """Raised when field extraction or normalization fails.

    This exception is raised when:
    - Equipment code cannot be decomposed
    - Scribe identifier cannot be extracted
    - Lot/wafer identifiers are invalid
    - Timestamp cannot be parsed
    """

    def __init__(
        self,
        message: str,
        field_name: Optional[str] = None,
        field_value: Optional[str] = None,
        error_code: str = "EXTRACT_001",
    ) -> None:
        context = {}
        if field_name is not None:
            context["field_name"] = field_name
        if field_value is not None:
            context["field_value"] = field_value
        super().__init__(message, error_code=error_code, context=context)


class MappingError(ScribeLotMapperError):
    """Raised when mapping record creation fails.

    This exception is raised when:
    - Required mapping components are missing
    - Bidirectional mapping cannot be established
    - Mapping ID assignment fails
    """

    def __init__(
        self,
        message: str,
        mapping_id: Optional[str] = None,
        error_code: str = "MAP_001",
    ) -> None:
        context = {}
        if mapping_id is not None:
            context["mapping_id"] = mapping_id
        super().__init__(message, error_code=error_code, context=context)


class ValidationError(ScribeLotMapperError):
    """Raised when validation of mapping records fails.

    This exception is raised when:
    - Record is incomplete (missing scribe_id, lot_id, or wafer_id)
    - Lot-wafer consistency check fails
    - Invalid field values detected
    """

    def __init__(
        self,
        message: str,
        record_id: Optional[str] = None,
        validation_type: Optional[str] = None,
        error_code: str = "VALID_001",
    ) -> None:
        context = {}
        if record_id is not None:
            context["record_id"] = record_id
        if validation_type is not None:
            context["validation_type"] = validation_type
        super().__init__(message, error_code=error_code, context=context)


class FileOperationError(ScribeLotMapperError):
    """Raised when file operations fail.

    This exception is raised when:
    - Input file cannot be opened or read
    - Output file cannot be written
    - File encoding issues occur
    - File format cannot be determined
    """

    def __init__(
        self,
        message: str,
        file_path: Optional[str] = None,
        operation: Optional[str] = None,
        error_code: str = "IO_001",
    ) -> None:
        context = {}
        if file_path is not None:
            context["file_path"] = file_path
        if operation is not None:
            context["operation"] = operation
        super().__init__(message, error_code=error_code, context=context)


class ConfigurationError(ScribeLotMapperError):
    """Raised when configuration is invalid.

    This exception is raised when:
    - Required configuration values are missing
    - Configuration values are out of valid range
    - Configuration conflicts exist
    """

    def __init__(
        self,
        message: str,
        config_key: Optional[str] = None,
        error_code: str = "CONFIG_001",
    ) -> None:
        context = {}
        if config_key is not None:
            context["config_key"] = config_key
        super().__init__(message, error_code=error_code, context=context)
