"""Scribe-to-Lot/Wafer Mapping Service.

Manufacturing traceability service that extracts and normalizes scribe position,
lot, and wafer identifiers from workstream parameter history files. Creates
bidirectional mappings enabling both forward (lot→scribe) and reverse (scribe→lot)
lookup for defect analysis and yield correlation.
"""

__version__ = "1.0.0"
__author__ = "Manufacturing Analytics"
__license__ = "Proprietary"

from scribe_lot_mapper.exceptions import (
    ConfigurationError,
    ExtractionError,
    FileOperationError,
    MappingError,
    ParsingError,
    ScribeLotMapperError,
    ValidationError,
)
from scribe_lot_mapper.interfaces import (
    CSVGenerator,
    EquipmentCodeParser,
    ErrorHandler,
    FileReader,
    FormatSpecParser,
    IFFGenerator,
    JSONGenerator,
    LookupService,
    MappingGenerator,
    MultiSiteDetector,
    OutputGenerator,
    Parser,
    ScribeExtractor,
    Validator,
    LotWaferExtractor,
)
from scribe_lot_mapper.models import (
    EquipmentInfo,
    LotAttributeRecord,
    LotHistoryRecord,
    MappingRecord,
    ParsedRecord,
    ValidationResult,
)

__all__ = [
    # Exceptions
    "ScribeLotMapperError",
    "ParsingError",
    "ExtractionError",
    "MappingError",
    "ValidationError",
    "FileOperationError",
    "ConfigurationError",
    # Data Models
    "ParsedRecord",
    "EquipmentInfo",
    "MappingRecord",
    "LotHistoryRecord",
    "LotAttributeRecord",
    "ValidationResult",
    # Protocols/Interfaces
    "FileReader",
    "FormatSpecParser",
    "Parser",
    "EquipmentCodeParser",
    "ScribeExtractor",
    "LotWaferExtractor",
    "MultiSiteDetector",
    "MappingGenerator",
    "Validator",
    "OutputGenerator",
    "CSVGenerator",
    "JSONGenerator",
    "IFFGenerator",
    "LookupService",
    "ErrorHandler",
]
