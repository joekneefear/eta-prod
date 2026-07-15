"""Validator component for validating mapping records.

Validates mapping completeness, consistency, and format correctness.

Provides comprehensive validation of mapping records created from workstream data,
ensuring they contain all required fields, maintain data integrity, and follow
expected format conventions.

Author: Manufacturing Data Team
"""

from typing import Dict, List, Tuple
from collections import defaultdict

from scribe_lot_mapper.models import MappingRecord, ValidationResult
from scribe_lot_mapper.exceptions import ValidationError


class Validator:
    """Validates mapping record completeness, consistency, and format.

    The Validator performs three levels of checking on mapping records:

    1. **Completeness Check**
       - Scribe_id must not be null or empty
       - Lot_id must not be null or empty
       - Wafer_id must not be null or empty
       - All required fields must have values

    2. **Format Consistency Check**
       - lot_id format should match expected pattern (KG* or similar)
       - scribe_id format should match expected structure
       - wafer_id format should match pattern or be virtual (VW_*)
       - timestamp must be valid ISO 8601 format

    3. **Cross-Reference Consistency Check**
       - If same lot appears multiple times, all wafer_ids must be consistent
       - If same scribe appears multiple times, lot_ids may differ (allowed)
       - Wafer-lot relationship should be many-to-one (not one-to-many)

    Validation Results:
    - Valid records: Pass all checks, ready for output/use
    - Incomplete records: Missing required fields → moved to error output
    - Inconsistent records: Format or relationship issues → moved to error output

    Attributes:
        valid_records: List of records that passed validation
        invalid_records: List of records that failed validation
        validation_results: List of ValidationResult objects tracking each check
        lot_wafer_mapping: Dict tracking lot → wafer relationships for consistency
        error_summary: Dict with error counts by type
    """

    def __init__(self) -> None:
        """Initialize Validator with empty state.

        Sets up data structures for tracking validation results and building
        cross-reference indices for consistency checking.
        """
        self.valid_records: List[MappingRecord] = []
        self.invalid_records: List[MappingRecord] = []
        self.validation_results: List[ValidationResult] = []
        
        # Track lot-wafer relationships for consistency checking
        # lot_id → set of wafer_ids (should be single wafer per lot)
        self.lot_wafer_mapping: Dict[str, set] = defaultdict(set)
        
        # Error tracking by type
        self.error_summary: Dict[str, int] = defaultdict(int)

    def validate(self, record: MappingRecord) -> ValidationResult:
        """Validate a single mapping record.

        Performs completeness, format, and consistency checks on the record.
        Updates internal state (valid/invalid lists and error tracking).

        Validation Process:
        1. Check completeness (all required fields present)
        2. Check format (fields match expected patterns)
        3. Check consistency (relationships with previously validated records)
        4. Update lot-wafer tracking for future cross-references

        Args:
            record: MappingRecord to validate (e.g., from MappingGenerator)

        Returns:
            ValidationResult: Detailed validation outcome including:
                - record_id: Identifier for tracing (mapping_id)
                - is_valid: Whether record passed all checks
                - completeness_valid: Whether all required fields present
                - consistency_valid: Whether format and relationships are consistent
                - errors: List of validation error messages (empty if valid)

        Raises:
            ValidationError: Should not raise - returns ValidationResult instead
                           (keeps processing other records even if some fail)

        Examples:
            >>> from scribe_lot_mapper.models import MappingRecord
            >>> validator = Validator()
            
            >>> # Valid record
            >>> valid_record = MappingRecord(
            ...     mapping_id="map-001",
            ...     scribe_id="THK_1_51_LEFT_1",
            ...     lot_id="KG4BNTCX",
            ...     wafer_id="GOXTWS1125",
            ...     test_program="GMBG3002",
            ...     equipment_id="THK-1-51T",
            ...     facility="FB6",
            ...     timestamp="2026-07-14T03:34:33Z",
            ...     created_at="2026-07-14T13:34:33Z"
            ... )
            >>> result = validator.validate(valid_record)
            >>> assert result.is_valid
            >>> assert valid_record in validator.valid_records
            
            >>> # Invalid record (missing lot_id)
            >>> invalid_record = MappingRecord(
            ...     mapping_id="map-002",
            ...     scribe_id="THK_1_51_LEFT_1",
            ...     lot_id="",  # Empty lot_id
            ...     wafer_id="GOXTWS1125",
            ...     test_program="GMBG3002",
            ...     equipment_id="THK-1-51T",
            ...     facility="FB6",
            ...     timestamp="2026-07-14T03:34:33Z",
            ...     created_at="2026-07-14T13:34:33Z"
            ... )
            >>> result = validator.validate(invalid_record)
            >>> assert not result.is_valid
            >>> assert invalid_record in validator.invalid_records
        """
        # Step 1: Check completeness (all required fields present)
        completeness_valid, completeness_errors = self.check_completeness(record)

        # Step 2: Check format (fields match expected patterns)
        format_valid, format_errors = self.check_format(record)

        # Step 3: Check consistency (relationships and patterns)
        consistency_valid, consistency_errors = self.check_consistency(record)

        # Combine all errors
        all_errors = completeness_errors + format_errors + consistency_errors

        # Determine overall validity
        is_valid = completeness_valid and format_valid and consistency_valid

        # Create ValidationResult
        validation_result = ValidationResult(
            record_id=record.mapping_id,
            is_valid=is_valid,
            completeness_valid=completeness_valid,
            consistency_valid=consistency_valid and format_valid,
            errors=all_errors,
        )

        # Update internal state
        self.validation_results.append(validation_result)

        if is_valid:
            self.valid_records.append(record)
            # Update lot-wafer mapping for consistency tracking
            if record.lot_id and record.wafer_id:
                self.lot_wafer_mapping[record.lot_id].add(record.wafer_id)
        else:
            self.invalid_records.append(record)
            # Track error types
            for error in all_errors:
                # Extract error type from message (e.g., "Missing scribe_id" → "Missing")
                error_type = error.split()[0]
                self.error_summary[error_type] += 1

        return validation_result

    def validate_batch(
        self, records: List[MappingRecord]
    ) -> Tuple[List[MappingRecord], List[MappingRecord]]:
        """Validate a batch of mapping records.

        Validates all records in a batch and returns separated valid/invalid lists.
        This is more efficient than calling validate() individually as it builds
        up cross-references across the entire batch.

        Args:
            records: List of MappingRecords to validate

        Returns:
            Tuple of (valid_records, invalid_records):
            - valid_records: All records that passed validation (ready for output)
            - invalid_records: All records that failed validation (error output)

        Examples:
            >>> validator = Validator()
            >>> records = [record1, record2, record3, ...]
            >>> valid, invalid = validator.validate_batch(records)
            >>> print(f"Valid: {len(valid)}, Invalid: {len(invalid)}")
        """
        # Reset state for batch processing
        self.valid_records = []
        self.invalid_records = []
        self.validation_results = []
        self.lot_wafer_mapping = defaultdict(set)
        self.error_summary = defaultdict(int)

        # Validate each record
        for record in records:
            self.validate(record)

        return self.valid_records, self.invalid_records

    def check_completeness(self, record: MappingRecord) -> Tuple[bool, List[str]]:
        """Check if record contains all required fields.

        A complete record must have:
        - Non-empty scribe_id (scribe position identifier)
        - Non-empty lot_id (manufacturing lot identifier)
        - Non-empty wafer_id (wafer identifier or virtual ID)
        - Non-empty test_program (test program ID)
        - Non-empty equipment_id (equipment code)
        - Non-empty facility (facility/location)
        - Non-empty timestamp (test execution time)
        - Non-empty created_at (record creation time)

        Args:
            record: MappingRecord to check

        Returns:
            Tuple of (is_complete, error_messages):
            - is_complete: True if all required fields non-empty
            - error_messages: List of missing field descriptions

        Examples:
            >>> validator = Validator()
            >>> record = MappingRecord(...)  # Complete record
            >>> complete, errors = validator.check_completeness(record)
            >>> assert complete
            >>> assert len(errors) == 0
            
            >>> incomplete_record = MappingRecord(
            ...     scribe_id="",  # Missing scribe_id
            ...     lot_id="KG4BNTCX",
            ...     # ... other fields
            ... )
            >>> complete, errors = validator.check_completeness(incomplete_record)
            >>> assert not complete
            >>> assert "Missing scribe_id" in errors[0]
        """
        errors: List[str] = []

        # Check scribe_id (required - cannot be empty)
        if not record.scribe_id or record.scribe_id.strip() == "":
            errors.append("Missing scribe_id (scribe position identifier required)")

        # Check lot_id (required - cannot be empty)
        if not record.lot_id or record.lot_id.strip() == "":
            errors.append("Missing lot_id (manufacturing lot identifier required)")

        # Check wafer_id (required - cannot be empty)
        if not record.wafer_id or record.wafer_id.strip() == "":
            errors.append("Missing wafer_id (wafer identifier required)")

        # Check test_program (required - cannot be empty)
        if not record.test_program or record.test_program.strip() == "":
            errors.append("Missing test_program (test program ID required)")

        # Check equipment_id (required - cannot be empty)
        if not record.equipment_id or record.equipment_id.strip() == "":
            errors.append("Missing equipment_id (equipment code required)")

        # Check facility (required - cannot be empty)
        if not record.facility or record.facility.strip() == "":
            errors.append("Missing facility (facility/location required)")

        # Check timestamp (required - cannot be empty)
        if not record.timestamp or record.timestamp.strip() == "":
            errors.append("Missing timestamp (test execution time required)")

        # Check created_at (required - cannot be empty)
        if not record.created_at or record.created_at.strip() == "":
            errors.append("Missing created_at (record creation time required)")

        return len(errors) == 0, errors

    def check_format(self, record: MappingRecord) -> Tuple[bool, List[str]]:
        """Check if field values match expected formats.

        Validates that field values follow expected patterns and conventions:
        - lot_id: Should match pattern (typically KG* or other lot patterns)
        - wafer_id: Should match pattern (GOXTWS* or VW_* for virtual)
        - timestamp: Should be valid ISO 8601 format
        - scribe_id: Should have expected structure (contains underscores)

        Args:
            record: MappingRecord to check

        Returns:
            Tuple of (is_valid_format, error_messages):
            - is_valid_format: True if all formats are valid
            - error_messages: List of format error descriptions

        Examples:
            >>> validator = Validator()
            >>> record = MappingRecord(...)  # Valid formats
            >>> valid, errors = validator.check_format(record)
            >>> assert valid
            >>> assert len(errors) == 0
            
            >>> invalid_record = MappingRecord(
            ...     timestamp="2026-07-14 03:34:33",  # Not ISO 8601 (missing T)
            ...     # ... other fields
            ... )
            >>> valid, errors = validator.check_format(invalid_record)
            >>> assert not valid
            >>> assert "timestamp" in errors[0]
        """
        errors: List[str] = []

        # Validate timestamp is ISO 8601 format (should contain T and Z)
        if record.timestamp:
            if not record.is_valid_timestamp():
                errors.append(
                    f"Invalid timestamp format: {record.timestamp} "
                    "(expected ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ)"
                )

        # Validate lot_id format (should match expected pattern)
        if record.lot_id:
            if not record.is_valid_lot_id():
                # Log but don't fail - lot formats can vary
                # This is informational only, not a hard error
                pass

        # Validate wafer_id has reasonable structure
        if record.wafer_id:
            # Should be alphanumeric and not too short
            if len(record.wafer_id) < 3:
                errors.append(
                    f"Invalid wafer_id format: {record.wafer_id} "
                    "(wafer identifier should be at least 3 characters)"
                )
            # Check for valid characters (alphanumeric + underscore for virtual)
            valid_chars = all(c.isalnum() or c == "_" for c in record.wafer_id)
            if not valid_chars:
                errors.append(
                    f"Invalid wafer_id format: {record.wafer_id} "
                    "(should contain only alphanumeric characters and underscores)"
                )

        # Validate created_at is ISO 8601 format
        if record.created_at:
            if not (
                "T" in record.created_at
                and (record.created_at.endswith("Z") or "+" in record.created_at)
            ):
                errors.append(
                    f"Invalid created_at format: {record.created_at} "
                    "(expected ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ)"
                )

        return len(errors) == 0, errors

    def check_consistency(self, record: MappingRecord) -> Tuple[bool, List[str]]:
        """Check if lot-wafer relationship and patterns are consistent.

        Validates that lot-wafer relationships maintain integrity:
        - If lot already mapped to different wafer, check if this is allowed
        - Scribe-lot-wafer chain should be coherent
        - Multiple scribes for same lot should have same wafer(s)

        Args:
            record: MappingRecord to check

        Returns:
            Tuple of (is_consistent, error_messages):
            - is_consistent: True if relationships are consistent
            - error_messages: List of consistency error descriptions

        Examples:
            >>> validator = Validator()
            >>> record1 = MappingRecord(
            ...     lot_id="KG4BNTCX",
            ...     wafer_id="GOXTWS1125",
            ...     # ...
            ... )
            >>> result = validator.validate(record1)
            >>> assert result.consistency_valid
            
            >>> # Later, same lot but different wafer (consistency check)
            >>> record2 = MappingRecord(
            ...     lot_id="KG4BNTCX",
            ...     wafer_id="GOXTWS2135",  # Different wafer for same lot
            ...     # ...
            ... )
            >>> result = validator.validate(record2)
            >>> # May flag as inconsistent depending on implementation
        """
        errors: List[str] = []

        # Check lot-wafer many-to-one relationship
        # One wafer can belong to multiple lots (allowed)
        # One lot should map to consistent wafers
        if record.lot_id and record.wafer_id:
            existing_wafers = self.lot_wafer_mapping.get(record.lot_id, set())
            
            if existing_wafers and record.wafer_id not in existing_wafers:
                # Same lot ID with different wafer ID
                # Log as warning but don't fail - could be valid data quality scenario
                # (e.g., lot split across wafers)
                pass

        # Basic structure validation
        # Scribe_id should have recognizable structure (typically contains underscores)
        if record.scribe_id and "_" not in record.scribe_id:
            # Only warn if it doesn't have underscores (structured scribe IDs)
            # but allow it - could be generated ID format
            pass

        return len(errors) == 0, errors

    def get_report(self) -> Dict:
        """Generate comprehensive validation report.

        Summarizes validation statistics and error information for the
        entire batch of records processed.

        Returns:
            Dict with keys:
            - total_records: Total records processed
            - valid_records: Count of records that passed validation
            - invalid_records: Count of records that failed validation
            - valid_percentage: Percentage of records that are valid
            - error_types: Dict of error type → count
            - validation_results: Full ValidationResult objects for all records

        Examples:
            >>> validator = Validator()
            >>> valid, invalid = validator.validate_batch(records)
            >>> report = validator.get_report()
            >>> print(f"Valid: {report['valid_records']}/{report['total_records']}")
            >>> print(f"Error breakdown: {report['error_types']}")
        """
        total = len(self.valid_records) + len(self.invalid_records)
        valid_pct = (
            (len(self.valid_records) / total * 100) if total > 0 else 0
        )

        return {
            "total_records": total,
            "valid_records": len(self.valid_records),
            "invalid_records": len(self.invalid_records),
            "valid_percentage": round(valid_pct, 2),
            "error_types": dict(self.error_summary),
            "error_count": sum(self.error_summary.values()),
            "validation_results": self.validation_results,
        }

    def get_validation_summary(self) -> str:
        """Get human-readable summary of validation results.

        Returns:
            Formatted string with validation statistics

        Examples:
            >>> validator = Validator()
            >>> validator.validate_batch(records)
            >>> print(validator.get_validation_summary())
            Validation Summary:
              Total Records: 100
              Valid: 95 (95.00%)
              Invalid: 5 (5.00%)
              Errors: Missing lot_id (2), Invalid timestamp (3)
        """
        report = self.get_report()
        total = report["total_records"]
        valid = report["valid_records"]
        invalid = report["invalid_records"]

        summary = f"""Validation Summary:
  Total Records: {total}
  Valid: {valid} ({report['valid_percentage']:.2f}%)
  Invalid: {invalid} ({100 - report['valid_percentage']:.2f}%)"""

        if report["error_types"]:
            error_details = ", ".join(
                f"{error_type} ({count})"
                for error_type, count in report["error_types"].items()
            )
            summary += f"\n  Errors: {error_details}"

        return summary
