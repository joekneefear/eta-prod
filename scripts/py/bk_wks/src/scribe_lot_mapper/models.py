"""Data models for Scribe-Lot-Mapper service.

This module defines immutable dataclasses representing the core data structures
used throughout the service pipeline, from raw record parsing through final
mapping generation.

All dataclasses are frozen (immutable) to ensure thread-safety and prevent
accidental modifications during processing.
"""

from dataclasses import dataclass, field
from datetime import datetime
from typing import List, Optional


def validate_lot_id(lot_id: str) -> bool:
    """Validate lot identifier format.

    Args:
        lot_id: Lot identifier to validate

    Returns:
        True if lot_id matches expected pattern, False otherwise
    """
    return lot_id.startswith("KG") and len(lot_id) >= 4


def validate_iso8601_timestamp(timestamp: str) -> bool:
    """Validate ISO 8601 timestamp format.

    Args:
        timestamp: Timestamp string to validate

    Returns:
        True if timestamp is valid ISO 8601, False otherwise
    """
    if not timestamp:
        return False
    try:
        # Basic validation: must contain 'T' separator and 'Z' or +/-
        return "T" in timestamp and (timestamp.endswith("Z") or "+" in timestamp or timestamp.count("-") > 2)
    except (ValueError, AttributeError):
        return False


@dataclass(frozen=True)
class ParsedRecord:
    """Raw extracted fields from a workstream parameter history record.

    Represents a single record after initial parsing and field extraction,
    before any normalization or transformation.

    Attributes:
        raw_line: Original unparsed record line from file
        parameter_set_id: Test program identifier (e.g., "GMBG3002")
        parameter_set_version: Test program version
        date_time: Timestamp from record (various formats possible)
        facility: Location/facility code
        parameter_name: Test name/description
        sequence_number: Order in test sequence
        unit_id: Scribe position identifier (e.g., "LEFT", "A6", "1")
        type_id: Equipment identifier/type code
        c_values: Text/measurement values (c_value_1 through c_value_5)
        d_values: Numeric/measurement values (d_value_1 through d_value_5)
        limits_high: Upper limit specification
        limits_low: Lower limit specification
        timestamp: Normalized ISO 8601 timestamp
    """

    raw_line: str
    parameter_set_id: str
    parameter_set_version: str
    date_time: str
    facility: str
    parameter_name: str
    sequence_number: int
    unit_id: str
    type_id: str
    c_values: List[str] = field(default_factory=list)
    d_values: List[str] = field(default_factory=list)
    limits_high: str = ""
    limits_low: str = ""
    timestamp: str = ""

    def is_multi_site(self) -> bool:
        """Check if record contains multiple site measurements.

        Returns:
            True if non-empty c_value or d_value lists exist, False otherwise
        """
        non_empty_c_values = sum(1 for v in self.c_values if v and v.strip())
        non_empty_d_values = sum(1 for v in self.d_values if v and v.strip())
        return max(non_empty_c_values, non_empty_d_values) > 1

    def site_count(self) -> int:
        """Get number of measurement sites in record.

        Returns:
            Count of non-empty c_value and d_value fields (max 5)
        """
        non_empty_c_values = sum(1 for v in self.c_values if v and v.strip())
        non_empty_d_values = sum(1 for v in self.d_values if v and v.strip())
        return max(non_empty_c_values, non_empty_d_values, 1)

    def has_required_fields(self) -> bool:
        """Check if record has minimum required fields for processing.

        Returns:
            True if parameter_set_id, facility, unit_id, type_id are non-empty
        """
        required = [self.parameter_set_id, self.facility, self.unit_id, self.type_id]
        return all(field for field in required)


@dataclass(frozen=True)
class EquipmentInfo:
    """Decomposed equipment code components.

    Represents the results of parsing an equipment code like "THK-1-51T"
    into its constituent facility, probe, position, and type parts.

    Attributes:
        raw_code: Original unparsed equipment code
        facility: Facility/location component (e.g., "THK", "RI", "ACI")
        probe: Probe number (typically 1-8)
        position: Test position number (typically 1-60)
        type: Equipment type indicator ("T", "F", or empty)
        normalized_code: Standardized equipment code format
    """

    raw_code: str
    facility: str
    probe: int
    position: int
    type: str
    normalized_code: str


@dataclass(frozen=True)
class MappingRecord:
    """Complete bidirectional mapping record linking scribe ↔ lot ↔ wafer.

    Represents a normalized mapping record after full processing pipeline:
    parsing, extraction, validation, and enrichment. Contains all relationships
    enabling forward (lot→scribe) and reverse (scribe→lot) lookups.

    Each record contains scribe_id, lot_id, AND wafer_id together, enabling
    all four mapping directions:
    - Scribe → Lot/Wafer (forward lookup)
    - Lot/Wafer → Scribe (reverse lookup)
    - Wafer → Lot (one-to-one via implicit relationship)
    - Lot → Wafer (one-to-many via distinct records)

    All required fields (scribe_id, lot_id, wafer_id, test_program, equipment_id,
    facility, timestamp, created_at, mapping_id) must be non-empty and valid.

    Attributes:
        mapping_id: Unique identifier (UUID) for this mapping record
        scribe_id: Normalized scribe position identifier (non-empty, required)
        lot_id: Manufacturing lot identifier, typically KG* pattern (non-empty, required)
        wafer_id: Wafer identifier - batch number or virtual ID (non-empty, required)
        test_program: Test program identifier from parameter_set_id (non-empty)
        equipment_id: Equipment code e.g., "THK-1-51T" (non-empty)
        facility: Facility/location code e.g., "FB6", "THK" (non-empty)
        timestamp: ISO 8601 test execution timestamp (non-empty, required)
        created_at: ISO 8601 record creation timestamp (non-empty)
        wafer_family: Wafer family/type classification (optional, empty string default)
        wafer_batch: Wafer batch number as integer (optional, 0 default)
        test_value: Measured test value as string representation (optional)
        sequence_number: Test sequence order (optional, 0 default)
        site_number: Multi-site measurement index 1-5 (optional, 1 default)
        unit_id: Scribe position within site e.g., "LEFT", "CENTER", "A6" (optional)
        validation_status: Validation result - "valid", "incomplete", or "inconsistent"
        parent_mapping_id: Links to parent record if from multi-site expansion (optional)
    """

    mapping_id: str
    scribe_id: str
    lot_id: str
    wafer_id: str
    test_program: str
    equipment_id: str
    facility: str
    timestamp: str
    created_at: str
    wafer_family: str = ""
    wafer_batch: int = 0
    test_value: str = ""
    sequence_number: int = 0
    site_number: int = 1
    unit_id: str = ""
    validation_status: str = "valid"
    parent_mapping_id: Optional[str] = None

    def is_complete(self) -> bool:
        """Check if record contains all required fields.

        A complete record must have non-empty scribe_id, lot_id, wafer_id,
        test_program, equipment_id, facility, timestamp, and created_at.

        Returns:
            True if all required fields are non-empty, False otherwise
        """
        required_fields = [
            self.mapping_id,
            self.scribe_id,
            self.lot_id,
            self.wafer_id,
            self.test_program,
            self.equipment_id,
            self.facility,
            self.timestamp,
            self.created_at,
        ]
        return all(field for field in required_fields)

    def is_valid_lot_id(self) -> bool:
        """Validate lot identifier format.

        Returns:
            True if lot_id matches expected pattern, False otherwise
        """
        return validate_lot_id(self.lot_id)

    def is_valid_timestamp(self) -> bool:
        """Validate that timestamp is ISO 8601 format.

        Returns:
            True if timestamp is valid ISO 8601, False otherwise
        """
        return validate_iso8601_timestamp(self.timestamp)

    def is_from_multi_site_expansion(self) -> bool:
        """Check if this record came from multi-site expansion.

        Returns:
            True if parent_mapping_id is set, False otherwise
        """
        return self.parent_mapping_id is not None


@dataclass(frozen=True)
class LotHistoryRecord:
    """Lot movement and transaction history record.

    Optional enrichment data from lot_history files, providing context
    about lot movements and transactions (moves, scraps, etc.).

    Attributes:
        lot_id: Manufacturing lot identifier
        operation: Operation type (MVOU, MOVE, SCRAP, etc.)
        transaction_type: Type of transaction
        quantity: Units/wafers affected
        equipment_id: Equipment where operation occurred
        timestamp: ISO 8601 timestamp of operation
    """

    lot_id: str
    operation: str
    transaction_type: str
    quantity: int
    equipment_id: str
    timestamp: str


@dataclass(frozen=True)
class LotAttributeRecord:
    """Lot custom attribute (key-value pair).

    Optional enrichment data from lot_attributes files, providing additional
    context like EPI SLOT for Silicon Carbide (SiC) wafer identification.

    Attributes:
        lot_id: Manufacturing lot identifier
        attribute_name: Name of the attribute (e.g., "EPI SLOT", "WAFER_ID")
        attribute_value: Value of the attribute
        attribute_type: Data type ("A"=ASCII, "N"=Numeric)
    """

    lot_id: str
    attribute_name: str
    attribute_value: str
    attribute_type: str


@dataclass(frozen=True)
class ValidationResult:
    """Result of validation for a single mapping record.

    Represents the outcome of validation checks on a mapping record,
    including what passed, what failed, and why.

    Attributes:
        record_id: Original record identifier/line number
        is_valid: Whether record passed all validation checks
        completeness_valid: Whether record contains all required fields
        consistency_valid: Whether lot-wafer relationship is consistent
        errors: List of validation error messages (empty if valid)
    """

    record_id: str
    is_valid: bool
    completeness_valid: bool
    consistency_valid: bool
    errors: List[str] = field(default_factory=list)

    def has_errors(self) -> bool:
        """Check if validation result contains any errors.

        Returns:
            True if errors list is not empty, False otherwise
        """
        return len(self.errors) > 0

    def add_error(self, error_message: str) -> "ValidationResult":
        """Create new ValidationResult with additional error.

        Since ValidationResult is frozen, returns new instance with error appended.

        Args:
            error_message: Error message to add

        Returns:
            New ValidationResult with error added
        """
        new_errors = list(self.errors) + [error_message]
        return ValidationResult(
            record_id=self.record_id,
            is_valid=False,
            completeness_valid=self.completeness_valid,
            consistency_valid=self.consistency_valid,
            errors=new_errors,
        )

    def error_summary(self) -> str:
        """Get summary of all errors as single string.

        Returns:
            Comma-separated error messages
        """
        return "; ".join(self.errors) if self.errors else "No errors"
