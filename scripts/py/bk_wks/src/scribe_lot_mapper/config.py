"""Configuration and settings for Scribe-Lot-Mapper service.

This module defines configuration management, default settings, and
environment-based configuration loading.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional


@dataclass
class LoggingConfig:
    """Logging configuration.

    Attributes:
        level: Logging level ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")
        log_file: Path to log file (optional)
        console_output: Whether to output to console
        max_bytes: Maximum size of log file before rotation (bytes)
        backup_count: Number of backup log files to keep
    """

    level: str = "INFO"
    log_file: Optional[Path] = None
    console_output: bool = True
    max_bytes: int = 10 * 1024 * 1024  # 10 MB
    backup_count: int = 5


@dataclass
class ParserConfig:
    """Parser configuration.

    Attributes:
        encoding: File encoding to attempt (utf-8, ascii, latin-1)
        chunk_size: Number of records to process at a time (memory optimization)
        skip_malformed: Whether to skip records that fail parsing
        normalize_whitespace: Whether to normalize leading/trailing whitespace
        empty_value_marker: Value to use for empty fields
    """

    encoding: str = "utf-8"
    chunk_size: int = 1000
    skip_malformed: bool = True
    normalize_whitespace: bool = True
    empty_value_marker: str = "N/A"


@dataclass
class ExtractionConfig:
    """Field extraction configuration.

    Attributes:
        max_site_count: Maximum number of multi-site sites (1-5)
        generate_virtual_ids: Whether to generate IDs when missing
        timestamp_formats: List of timestamp formats to try
        strict_validation: Whether to require all fields or allow partial
        unknown_equipment_marker: Marker for unknown equipment codes
    """

    max_site_count: int = 5
    generate_virtual_ids: bool = True
    timestamp_formats: List[str] = field(
        default_factory=lambda: [
            "%b %d %Y %H:%M:%S:%f%p",  # JUL 14 2026 03:00:16:000AM
            "%Y-%m-%dT%H:%M:%SZ",  # ISO 8601
            "%Y-%m-%d %H:%M:%S",
        ]
    )
    strict_validation: bool = False
    unknown_equipment_marker: str = "UNKNOWN"


@dataclass
class MappingConfig:
    """Mapping generation configuration.

    Attributes:
        include_metadata: Whether to include all metadata in output
        assignment_strategy: How to generate mapping IDs ("uuid" or "sequential")
        preserve_original_fields: Whether to preserve original field values
        deduplicate: Whether to remove duplicate mappings
    """

    include_metadata: bool = True
    assignment_strategy: str = "uuid"
    preserve_original_fields: bool = True
    deduplicate: bool = False


@dataclass
class OutputConfig:
    """Output generation configuration.

    Attributes:
        formats: List of output formats ("csv", "json", "iff")
        csv_dialect: CSV dialect for pandas write operations
        json_indent: JSON indentation level
        overwrite_existing: Whether to overwrite existing output files
        include_headers: Whether to include headers in output
    """

    formats: List[str] = field(default_factory=lambda: ["csv"])
    csv_dialect: str = "unix"
    json_indent: int = 2
    overwrite_existing: bool = False
    include_headers: bool = True


@dataclass
class ValidationConfig:
    """Validation configuration.

    Attributes:
        check_completeness: Check all required fields present
        check_consistency: Check lot-wafer relationships consistent
        check_format: Check format compliance
        generate_error_report: Write error reports
        separate_invalid_records: Move invalid records to .err files
    """

    check_completeness: bool = True
    check_consistency: bool = True
    check_format: bool = True
    generate_error_report: bool = True
    separate_invalid_records: bool = True


@dataclass
class ServiceConfig:
    """Top-level service configuration.

    Aggregates all component-specific configurations plus global settings.

    Attributes:
        logging: Logging configuration
        parser: Parser configuration
        extraction: Extraction configuration
        mapping: Mapping generation configuration
        output: Output generation configuration
        validation: Validation configuration
        max_records: Maximum records to process (0 = unlimited)
        dry_run: Whether to perform dry-run (no output files written)
        stop_on_error: Whether to halt on first error or continue
    """

    logging: LoggingConfig = field(default_factory=LoggingConfig)
    parser: ParserConfig = field(default_factory=ParserConfig)
    extraction: ExtractionConfig = field(default_factory=ExtractionConfig)
    mapping: MappingConfig = field(default_factory=MappingConfig)
    output: OutputConfig = field(default_factory=OutputConfig)
    validation: ValidationConfig = field(default_factory=ValidationConfig)
    max_records: int = 0
    dry_run: bool = False
    stop_on_error: bool = False

    @classmethod
    def load_defaults(cls) -> "ServiceConfig":
        """Load default configuration.

        Returns:
            ServiceConfig: Configuration with all default values
        """
        return cls()

    @classmethod
    def load_from_env(cls) -> "ServiceConfig":
        """Load configuration from environment variables.

        Environment variable naming convention:
        - SCRIBE_MAPPER_LOGGING_LEVEL
        - SCRIBE_MAPPER_PARSER_ENCODING
        - etc.

        Returns:
            ServiceConfig: Configuration loaded from environment
        """
        import os

        config = cls.load_defaults()

        # Logging
        if log_level := os.getenv("SCRIBE_MAPPER_LOGGING_LEVEL"):
            config.logging.level = log_level
        if log_file := os.getenv("SCRIBE_MAPPER_LOG_FILE"):
            config.logging.log_file = Path(log_file)

        # Parser
        if encoding := os.getenv("SCRIBE_MAPPER_PARSER_ENCODING"):
            config.parser.encoding = encoding
        if chunk_size := os.getenv("SCRIBE_MAPPER_CHUNK_SIZE"):
            config.parser.chunk_size = int(chunk_size)

        # Extraction
        if max_sites := os.getenv("SCRIBE_MAPPER_MAX_SITES"):
            config.extraction.max_site_count = int(max_sites)

        # Output
        if formats := os.getenv("SCRIBE_MAPPER_OUTPUT_FORMATS"):
            config.output.formats = formats.split(",")

        # Global
        if max_records := os.getenv("SCRIBE_MAPPER_MAX_RECORDS"):
            config.max_records = int(max_records)
        if dry_run := os.getenv("SCRIBE_MAPPER_DRY_RUN"):
            config.dry_run = dry_run.lower() in ("true", "1", "yes")

        return config


# Default instance
DEFAULT_CONFIG = ServiceConfig.load_defaults()
