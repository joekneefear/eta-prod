"""Unit tests for Validator component.

Tests validation of mapping records for completeness, format, and consistency.
Covers valid records, invalid records, error tracking, and batch processing.
"""

import pytest

from scribe_lot_mapper.validators.validator import Validator
from scribe_lot_mapper.models import MappingRecord


# ============================================================================
# Test Fixtures
# ============================================================================


@pytest.fixture
def validator() -> Validator:
    """Create Validator instance for testing."""
    return Validator()


@pytest.fixture
def valid_mapping_record() -> MappingRecord:
    """Create a complete, valid mapping record."""
    return MappingRecord(
        mapping_id="map-001",
        scribe_id="THK_1_51_LEFT_1",
        lot_id="KG4BNTCX",
        wafer_id="GOXTWS1125",
        test_program="GMBG3002",
        equipment_id="THK-1-51T",
        facility="FB6",
        sequence_number=1,
        site_number=1,
        unit_id="LEFT",
        test_value="301.2",
        timestamp="2026-07-14T03:34:33Z",
        created_at="2026-07-14T13:34:33Z",
        validation_status="valid",
    )


@pytest.fixture
def missing_scribe_record() -> MappingRecord:
    """Create record with missing scribe_id."""
    return MappingRecord(
        mapping_id="map-002",
        scribe_id="",  # Missing
        lot_id="KG4BNTCX",
        wafer_id="GOXTWS1125",
        test_program="GMBG3002",
        equipment_id="THK-1-51T",
        facility="FB6",
        sequence_number=1,
        site_number=1,
        unit_id="LEFT",
        test_value="301.2",
        timestamp="2026-07-14T03:34:33Z",
        created_at="2026-07-14T13:34:33Z",
    )


@pytest.fixture
def missing_lot_record() -> MappingRecord:
    """Create record with missing lot_id."""
    return MappingRecord(
        mapping_id="map-003",
        scribe_id="THK_1_51_LEFT_1",
        lot_id="",  # Missing
        wafer_id="GOXTWS1125",
        test_program="GMBG3002",
        equipment_id="THK-1-51T",
        facility="FB6",
        sequence_number=1,
        site_number=1,
        unit_id="LEFT",
        test_value="301.2",
        timestamp="2026-07-14T03:34:33Z",
        created_at="2026-07-14T13:34:33Z",
    )


@pytest.fixture
def missing_wafer_record() -> MappingRecord:
    """Create record with missing wafer_id."""
    return MappingRecord(
        mapping_id="map-004",
        scribe_id="THK_1_51_LEFT_1",
        lot_id="KG4BNTCX",
        wafer_id="",  # Missing
        test_program="GMBG3002",
        equipment_id="THK-1-51T",
        facility="FB6",
        sequence_number=1,
        site_number=1,
        unit_id="LEFT",
        test_value="301.2",
        timestamp="2026-07-14T03:34:33Z",
        created_at="2026-07-14T13:34:33Z",
    )


@pytest.fixture
def invalid_timestamp_record() -> MappingRecord:
    """Create record with invalid timestamp format."""
    return MappingRecord(
        mapping_id="map-005",
        scribe_id="THK_1_51_LEFT_1",
        lot_id="KG4BNTCX",
        wafer_id="GOXTWS1125",
        test_program="GMBG3002",
        equipment_id="THK-1-51T",
        facility="FB6",
        sequence_number=1,
        site_number=1,
        unit_id="LEFT",
        test_value="301.2",
        timestamp="2026-07-14 03:34:33",  # Invalid: missing T separator
        created_at="2026-07-14T13:34:33Z",
    )


@pytest.fixture
def short_wafer_record() -> MappingRecord:
    """Create record with too-short wafer_id."""
    return MappingRecord(
        mapping_id="map-006",
        scribe_id="THK_1_51_LEFT_1",
        lot_id="KG4BNTCX",
        wafer_id="WX",  # Too short
        test_program="GMBG3002",
        equipment_id="THK-1-51T",
        facility="FB6",
        sequence_number=1,
        site_number=1,
        unit_id="LEFT",
        test_value="301.2",
        timestamp="2026-07-14T03:34:33Z",
        created_at="2026-07-14T13:34:33Z",
    )


# ============================================================================
# Test Initialization
# ============================================================================


@pytest.mark.unit
class TestValidatorInit:
    """Test Validator initialization."""

    def test_init_creates_empty_state(self, validator: Validator) -> None:
        """Test that Validator initializes with empty state."""
        assert validator.valid_records == []
        assert validator.invalid_records == []
        assert validator.validation_results == []
        assert validator.lot_wafer_mapping == {}
        assert validator.error_summary == {}

    def test_init_multiple_instances_independent(self) -> None:
        """Test that multiple Validator instances are independent."""
        validator1 = Validator()
        validator2 = Validator()
        
        # Modify validator1
        validator1.valid_records.append(None)
        
        # validator2 should not be affected
        assert len(validator2.valid_records) == 0


# ============================================================================
# Test Completeness Checking
# ============================================================================


@pytest.mark.unit
class TestCompletenessChecking:
    """Test completeness validation."""

    def test_valid_record_is_complete(
        self, validator: Validator, valid_mapping_record: MappingRecord
    ) -> None:
        """Test that valid record passes completeness check."""
        is_complete, errors = validator.check_completeness(valid_mapping_record)
        assert is_complete
        assert len(errors) == 0

    def test_missing_scribe_id_detected(
        self, validator: Validator, missing_scribe_record: MappingRecord
    ) -> None:
        """Test that missing scribe_id is detected."""
        is_complete, errors = validator.check_completeness(missing_scribe_record)
        assert not is_complete
        assert any("scribe_id" in error for error in errors)

    def test_missing_lot_id_detected(
        self, validator: Validator, missing_lot_record: MappingRecord
    ) -> None:
        """Test that missing lot_id is detected."""
        is_complete, errors = validator.check_completeness(missing_lot_record)
        assert not is_complete
        assert any("lot_id" in error for error in errors)

    def test_missing_wafer_id_detected(
        self, validator: Validator, missing_wafer_record: MappingRecord
    ) -> None:
        """Test that missing wafer_id is detected."""
        is_complete, errors = validator.check_completeness(missing_wafer_record)
        assert not is_complete
        assert any("wafer_id" in error for error in errors)

    def test_all_required_fields_checked(
        self, validator: Validator
    ) -> None:
        """Test that all required fields are checked for completeness."""
        # Create record with multiple missing fields
        incomplete_record = MappingRecord(
            mapping_id="map-test",
            scribe_id="",  # Missing
            lot_id="",  # Missing
            wafer_id="",  # Missing
            test_program="",  # Missing
            equipment_id="",  # Missing
            facility="",  # Missing
            timestamp="",  # Missing
            created_at="",  # Missing
        )
        
        is_complete, errors = validator.check_completeness(incomplete_record)
        assert not is_complete
        assert len(errors) > 0  # Multiple errors


# ============================================================================
# Test Format Checking
# ============================================================================


@pytest.mark.unit
class TestFormatChecking:
    """Test format validation."""

    def test_valid_record_passes_format_check(
        self, validator: Validator, valid_mapping_record: MappingRecord
    ) -> None:
        """Test that valid record passes format check."""
        is_valid, errors = validator.check_format(valid_mapping_record)
        assert is_valid
        assert len(errors) == 0

    def test_invalid_timestamp_detected(
        self, validator: Validator, invalid_timestamp_record: MappingRecord
    ) -> None:
        """Test that invalid ISO 8601 timestamp is detected."""
        is_valid, errors = validator.check_format(invalid_timestamp_record)
        assert not is_valid
        assert any("timestamp" in error for error in errors)

    def test_short_wafer_id_detected(
        self, validator: Validator, short_wafer_record: MappingRecord
    ) -> None:
        """Test that too-short wafer_id is detected."""
        is_valid, errors = validator.check_format(short_wafer_record)
        assert not is_valid
        assert any("wafer_id" in error for error in errors)

    def test_invalid_characters_in_wafer_id_detected(
        self, validator: Validator
    ) -> None:
        """Test that invalid characters in wafer_id are detected."""
        record = MappingRecord(
            mapping_id="map-test",
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS@#$%",  # Invalid characters
            test_program="GMBG3002",
            equipment_id="THK-1-51T",
            facility="FB6",
            timestamp="2026-07-14T03:34:33Z",
            created_at="2026-07-14T13:34:33Z",
        )
        
        is_valid, errors = validator.check_format(record)
        assert not is_valid
        assert any("wafer_id" in error for error in errors)


# ============================================================================
# Test Consistency Checking
# ============================================================================


@pytest.mark.unit
class TestConsistencyChecking:
    """Test consistency validation."""

    def test_valid_record_passes_consistency_check(
        self, validator: Validator, valid_mapping_record: MappingRecord
    ) -> None:
        """Test that valid record passes consistency check."""
        is_consistent, errors = validator.check_consistency(valid_mapping_record)
        assert is_consistent
        assert len(errors) == 0

    def test_lot_wafer_tracking(
        self, validator: Validator, valid_mapping_record: MappingRecord
    ) -> None:
        """Test that lot-wafer relationships are tracked."""
        # Validate first record
        validator.validate(valid_mapping_record)
        
        # Check that lot-wafer mapping was updated
        assert valid_mapping_record.lot_id in validator.lot_wafer_mapping
        assert valid_mapping_record.wafer_id in validator.lot_wafer_mapping[
            valid_mapping_record.lot_id
        ]


# ============================================================================
# Test Record Validation
# ============================================================================


@pytest.mark.unit
class TestRecordValidation:
    """Test individual record validation."""

    def test_validate_valid_record(
        self, validator: Validator, valid_mapping_record: MappingRecord
    ) -> None:
        """Test validating a complete, valid record."""
        result = validator.validate(valid_mapping_record)
        
        assert result.is_valid
        assert result.completeness_valid
        assert result.consistency_valid
        assert len(result.errors) == 0
        assert valid_mapping_record in validator.valid_records

    def test_validate_incomplete_record(
        self, validator: Validator, missing_scribe_record: MappingRecord
    ) -> None:
        """Test validating incomplete record."""
        result = validator.validate(missing_scribe_record)
        
        assert not result.is_valid
        assert not result.completeness_valid
        assert len(result.errors) > 0
        assert missing_scribe_record in validator.invalid_records

    def test_validate_format_error_record(
        self, validator: Validator, invalid_timestamp_record: MappingRecord
    ) -> None:
        """Test validating record with format errors."""
        result = validator.validate(invalid_timestamp_record)
        
        assert not result.is_valid
        assert len(result.errors) > 0

    def test_validation_result_contains_mapping_id(
        self, validator: Validator, valid_mapping_record: MappingRecord
    ) -> None:
        """Test that ValidationResult includes mapping_id."""
        result = validator.validate(valid_mapping_record)
        assert result.record_id == valid_mapping_record.mapping_id

    def test_validation_updates_error_summary(
        self, validator: Validator, missing_scribe_record: MappingRecord
    ) -> None:
        """Test that error summary is updated on validation."""
        validator.validate(missing_scribe_record)
        
        assert len(validator.error_summary) > 0
        assert validator.error_summary.get("Missing", 0) > 0


# ============================================================================
# Test Batch Validation
# ============================================================================


@pytest.mark.unit
class TestBatchValidation:
    """Test batch record validation."""

    def test_validate_batch_returns_separated_lists(
        self,
        validator: Validator,
        valid_mapping_record: MappingRecord,
        missing_scribe_record: MappingRecord,
    ) -> None:
        """Test that batch validation returns separated valid/invalid lists."""
        records = [valid_mapping_record, missing_scribe_record]
        valid, invalid = validator.validate_batch(records)
        
        assert len(valid) == 1
        assert len(invalid) == 1
        assert valid_mapping_record in valid
        assert missing_scribe_record in invalid

    def test_validate_batch_resets_state(
        self,
        validator: Validator,
        valid_mapping_record: MappingRecord,
    ) -> None:
        """Test that batch validation resets state from previous batches."""
        # First batch
        validator.validate_batch([valid_mapping_record])
        first_valid_count = len(validator.valid_records)
        
        # Second batch
        validator.validate_batch([valid_mapping_record])
        second_valid_count = len(validator.valid_records)
        
        # Should have same count (state was reset)
        assert first_valid_count == second_valid_count

    def test_validate_empty_batch(self, validator: Validator) -> None:
        """Test validating empty batch."""
        valid, invalid = validator.validate_batch([])
        
        assert len(valid) == 0
        assert len(invalid) == 0


# ============================================================================
# Test Report Generation
# ============================================================================


@pytest.mark.unit
class TestReportGeneration:
    """Test validation report generation."""

    def test_get_report_all_valid(
        self,
        validator: Validator,
        valid_mapping_record: MappingRecord,
    ) -> None:
        """Test report with all valid records."""
        validator.validate_batch([valid_mapping_record])
        report = validator.get_report()
        
        assert report["total_records"] == 1
        assert report["valid_records"] == 1
        assert report["invalid_records"] == 0
        assert report["valid_percentage"] == 100.0

    def test_get_report_mixed_records(
        self,
        validator: Validator,
        valid_mapping_record: MappingRecord,
        missing_scribe_record: MappingRecord,
    ) -> None:
        """Test report with mixed valid/invalid records."""
        validator.validate_batch([valid_mapping_record, missing_scribe_record])
        report = validator.get_report()
        
        assert report["total_records"] == 2
        assert report["valid_records"] == 1
        assert report["invalid_records"] == 1
        assert report["valid_percentage"] == 50.0

    def test_get_report_includes_error_types(
        self,
        validator: Validator,
        missing_scribe_record: MappingRecord,
        missing_lot_record: MappingRecord,
    ) -> None:
        """Test that report includes error type breakdown."""
        validator.validate_batch([missing_scribe_record, missing_lot_record])
        report = validator.get_report()
        
        assert "error_types" in report
        assert len(report["error_types"]) > 0

    def test_get_report_all_invalid(
        self,
        validator: Validator,
        missing_scribe_record: MappingRecord,
    ) -> None:
        """Test report with all invalid records."""
        validator.validate_batch([missing_scribe_record])
        report = validator.get_report()
        
        assert report["total_records"] == 1
        assert report["valid_records"] == 0
        assert report["invalid_records"] == 1
        assert report["valid_percentage"] == 0.0


# ============================================================================
# Test Summary Generation
# ============================================================================


@pytest.mark.unit
class TestSummaryGeneration:
    """Test validation summary generation."""

    def test_get_validation_summary_format(
        self,
        validator: Validator,
        valid_mapping_record: MappingRecord,
    ) -> None:
        """Test that summary has expected format."""
        validator.validate_batch([valid_mapping_record])
        summary = validator.get_validation_summary()
        
        assert "Validation Summary:" in summary
        assert "Total Records:" in summary
        assert "Valid:" in summary
        assert "Invalid:" in summary

    def test_get_validation_summary_includes_errors(
        self,
        validator: Validator,
        missing_scribe_record: MappingRecord,
    ) -> None:
        """Test that summary includes error information."""
        validator.validate_batch([missing_scribe_record])
        summary = validator.get_validation_summary()
        
        assert "Errors:" in summary

    def test_get_validation_summary_no_errors_valid_batch(
        self,
        validator: Validator,
        valid_mapping_record: MappingRecord,
    ) -> None:
        """Test that summary for valid batch doesn't show errors section."""
        validator.validate_batch([valid_mapping_record])
        summary = validator.get_validation_summary()
        
        # Should not have "Errors:" line when all valid
        lines = summary.split("\n")
        error_lines = [l for l in lines if "Errors:" in l]
        assert len(error_lines) == 0


# ============================================================================
# Test Integration
# ============================================================================


@pytest.mark.unit
class TestValidatorIntegration:
    """Test Validator integration scenarios."""

    def test_validate_multiple_records_in_sequence(
        self,
        validator: Validator,
        valid_mapping_record: MappingRecord,
        missing_scribe_record: MappingRecord,
    ) -> None:
        """Test validating multiple records sequentially."""
        result1 = validator.validate(valid_mapping_record)
        result2 = validator.validate(missing_scribe_record)
        
        assert result1.is_valid
        assert not result2.is_valid
        assert len(validator.validation_results) == 2

    def test_lot_wafer_mapping_accumulates(
        self, validator: Validator
    ) -> None:
        """Test that lot-wafer mapping accumulates across validations."""
        record1 = MappingRecord(
            mapping_id="map-1",
            scribe_id="SCRIBE_1",
            lot_id="KG_LOT_1",
            wafer_id="WAF_1",
            test_program="TEST_1",
            equipment_id="EQP_1",
            facility="FAC_1",
            timestamp="2026-07-14T03:34:33Z",
            created_at="2026-07-14T13:34:33Z",
        )
        
        record2 = MappingRecord(
            mapping_id="map-2",
            scribe_id="SCRIBE_2",
            lot_id="KG_LOT_1",
            wafer_id="WAF_2",
            test_program="TEST_2",
            equipment_id="EQP_2",
            facility="FAC_1",
            timestamp="2026-07-14T03:34:33Z",
            created_at="2026-07-14T13:34:33Z",
        )
        
        validator.validate(record1)
        validator.validate(record2)
        
        # Both wafers should be mapped to the lot
        assert "KG_LOT_1" in validator.lot_wafer_mapping
        assert len(validator.lot_wafer_mapping["KG_LOT_1"]) == 2
        assert "WAF_1" in validator.lot_wafer_mapping["KG_LOT_1"]
        assert "WAF_2" in validator.lot_wafer_mapping["KG_LOT_1"]
