"""
Custom exception classes for the Scribe-to-Lot/Wafer Mapping Service.

This module defines a hierarchy of custom exceptions used throughout the system
to handle errors in parsing, extraction, validation, and I/O operations.

Author: Manufacturing Data Team
"""

from typing import Optional


class MapperError(Exception):
    """
    Base exception class for all Scribe-to-Lot/Wafer Mapping Service errors.
    
    All custom exceptions inherit from this class, allowing callers to catch
    all mapper-specific errors with a single except clause.
    """

    def __init__(
        self,
        message: str,
        error_code: Optional[str] = None,
        context: Optional[dict] = None,
    ) -> None:
        """
        Initialize MapperError.

        Args:
            message: Human-readable error description
            error_code: Optional unique error code for classification (e.g., "PARSE_001")
            context: Optional dictionary with additional error context
                (line number, file name, field name, etc.)
        """
        super().__init__(message)
        self.message = message
        self.error_code = error_code
        self.context = context or {}

    def __str__(self) -> str:
        """Return formatted error message with code and context."""
        msg = self.message
        if self.error_code:
            msg = f"[{self.error_code}] {msg}"
        if self.context:
            context_str = ", ".join(f"{k}={v}" for k, v in self.context.items())
            msg = f"{msg} ({context_str})"
        return msg


class ParsingError(MapperError):
    """
    Raised when file parsing or field extraction fails.

    This includes errors in reading files, decoding content, detecting file
    format, or extracting fields according to BCP format specifications.
    """

    def __init__(
        self,
        message: str,
        line_number: Optional[int] = None,
        file_name: Optional[str] = None,
        error_code: str = "PARSE_001",
    ) -> None:
        """
        Initialize ParsingError with file and line context.

        Args:
            message: Description of parsing failure
            line_number: Line number where error occurred
            file_name: Name of file being parsed
            error_code: Error classification code (default: PARSE_001)
        """
        context = {}
        if line_number is not None:
            context["line_number"] = line_number
        if file_name is not None:
            context["file_name"] = file_name

        super().__init__(message, error_code=error_code, context=context)


class ExtractionError(MapperError):
    """
    Raised when data extraction, normalization, or decomposition fails.

    This includes errors in extracting equipment codes, scribe identifiers,
    lot/wafer information, or other structured data extraction operations.
    """

    def __init__(
        self,
        message: str,
        field_name: Optional[str] = None,
        field_value: Optional[str] = None,
        error_code: str = "EXTRACT_001",
    ) -> None:
        """
        Initialize ExtractionError with field context.

        Args:
            message: Description of extraction failure
            field_name: Name of field being extracted
            field_value: The problematic value being extracted
            error_code: Error classification code (default: EXTRACT_001)
        """
        context = {}
        if field_name is not None:
            context["field_name"] = field_name
        if field_value is not None:
            context["field_value"] = field_value

        super().__init__(message, error_code=error_code, context=context)


class ValidationError(MapperError):
    """
    Raised when mapping record validation fails.

    This includes errors in completeness checks, consistency verification,
    format validation, and cross-reference checks.
    """

    def __init__(
        self,
        message: str,
        record_id: Optional[str] = None,
        validation_type: Optional[str] = None,
        error_code: str = "VALID_001",
    ) -> None:
        """
        Initialize ValidationError with validation context.

        Args:
            message: Description of validation failure
            record_id: Identifier of record that failed validation
            validation_type: Type of validation that failed
                (e.g., "completeness", "consistency", "format")
            error_code: Error classification code (default: VALID_001)
        """
        context = {}
        if record_id is not None:
            context["record_id"] = record_id
        if validation_type is not None:
            context["validation_type"] = validation_type

        super().__init__(message, error_code=error_code, context=context)


class FileIOError(MapperError):
    """
    Raised when file I/O operations fail.

    This includes errors in reading, writing, or managing files (file not found,
    permission denied, disk full, encoding issues, etc.).
    """

    def __init__(
        self,
        message: str,
        file_path: Optional[str] = None,
        operation: Optional[str] = None,
        error_code: str = "IO_001",
    ) -> None:
        """
        Initialize FileIOError with file operation context.

        Args:
            message: Description of I/O failure
            file_path: Path to file involved in failed operation
            operation: Type of operation that failed (read, write, open, etc.)
            error_code: Error classification code (default: IO_001)
        """
        context = {}
        if file_path is not None:
            context["file_path"] = file_path
        if operation is not None:
            context["operation"] = operation

        super().__init__(message, error_code=error_code, context=context)


class ConfigurationError(MapperError):
    """
    Raised when configuration or initialization fails.

    This includes invalid configuration values, missing required settings,
    or incompatible configuration combinations.
    """

    def __init__(
        self,
        message: str,
        config_key: Optional[str] = None,
        error_code: str = "CONFIG_001",
    ) -> None:
        """
        Initialize ConfigurationError with configuration context.

        Args:
            message: Description of configuration problem
            config_key: Name of problematic configuration key
            error_code: Error classification code (default: CONFIG_001)
        """
        context = {}
        if config_key is not None:
            context["config_key"] = config_key

        super().__init__(message, error_code=error_code, context=context)


class LookupError(MapperError):
    """
    Raised when lookup operations fail or return unexpected results.

    This includes errors in scribe→lot or lot→scribe reverse lookups,
    missing data, or inconsistent lookup results.
    """

    def __init__(
        self,
        message: str,
        query_key: Optional[str] = None,
        query_type: Optional[str] = None,
        error_code: str = "LOOKUP_001",
    ) -> None:
        """
        Initialize LookupError with lookup context.

        Args:
            message: Description of lookup failure
            query_key: Key being looked up (scribe_id, lot_id, etc.)
            query_type: Type of lookup (forward, reverse, filter, etc.)
            error_code: Error classification code (default: LOOKUP_001)
        """
        context = {}
        if query_key is not None:
            context["query_key"] = query_key
        if query_type is not None:
            context["query_type"] = query_type

        super().__init__(message, error_code=error_code, context=context)
