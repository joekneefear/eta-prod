"""Unit tests for LotWaferExtractor component.

Tests lot extraction, wafer extraction, virtual wafer generation,
normalization, and format validation.
"""

import pytest

from scribe_lot_mapper.exceptions import ExtractionError
from scribe_lot_mapper.extractors.lot_wafer_extractor import LotWaferExtractor
from scribe_lot_mapper.models import ParsedRecord


# ============================================================================
# Test Fixtures
# ============================================================================


@pytest.fixture
def lot_wafer_extractor() -> LotWaferExtractor:
    """Create default LotWaferExtractor instance."""
    return LotWaferExtractor()


@pytest.fixture
def valid_parsed_record() -> ParsedRecord:
    """Create a valid ParsedRecord with standard data."""
    return ParsedRecord(
        raw_line="test_line",
        parameter_set_id="GMBG3002",
        parameter_set_version="1.0",
        date_time="2026-07-14 03:34:33",
        facility="FB6",
        parameter_name="TEST_1",
        sequence_number=1,
        unit_id="LEFT",
        type_id="THK-1-51T",
        c_values=["301.2"],
        d_values=[],
        timestamp="2026-07-14T03:34:33Z"
    )


@pytest.fixture
def record_with_lot() -> ParsedRecord:
    """Create ParsedRecord with lot identifier in type_id."""
    return ParsedRecord(
        raw_line="test_line",
        parameter_set_id="GMBG3002",
        parameter_set_version="1.0",
        date_time="2026-07-14 03:34:33",
        facility="FB6",
        parameter_name="TEST_1",
        sequence_number=1,
        unit_id="LEFT",
        type_id="THK_KG4BNTCX_51T",  # Lot embedded in equipment code
        c_values=["301.2"],
        d_values=[],
        timestamp="2026-07-14T03:34:33Z"
    )


@pytest.fixture
def record_with_lot_and_wafer() -> ParsedRecord:
    """Create ParsedRecord with both lot and wafer identifiers."""
    return ParsedRecord(
        raw_line="test_line",
        parameter_set_id="GMBG3002",
        parameter_set_version="1.0",
        date_time="2026-07-14 03:34:33",
        facility="FB6",
        parameter_name="TEST_1",
        sequence_number=1,
        unit_id="LEFT",
        type_id="THK_KG4BNTCX_GOXTWS1125_51T",  # Both lot and wafer
        c_values=["301.2"],
        d_values=[],
        timestamp="2026-07-14T03:34:33Z"
    )


@pytest.fixture
def record_with_only_wafer() -> ParsedRecord:
    """Create ParsedRecord with wafer but no lot."""
    return ParsedRecord(
        raw_line="test_line",
        parameter_set_id="GMBG3002",
        parameter_set_version="1.0",
        date_time="2026-07-14 03:34:33",
        facility="FB6",
        parameter_name="TEST_1",
        sequence_number=1,
        unit_id="LEFT",
        type_id="THK_GOXTWS2135_51T",  # Wafer but no lot
        c_values=["301.2"],
        d_values=[],
        timestamp="2026-07-14T03:34:33Z"
    )


# ============================================================================
# Test Lot Normalization
# ============================================================================


@pytest.mark.unit
class TestLotNormalization:
    """Test lot identifier normalization."""

    def test_normalize_lot_standard_format(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization of standard lot format."""
        result = lot_wafer_extractor.normalize_lot("KG4BNTCX")
        assert result == "KG4BNTCX"

    def test_normalize_lot_lowercase(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization converts lowercase lot to uppercase."""
        result = lot_wafer_extractor.normalize_lot("kg4bntcx")
        assert result == "KG4BNTCX"

    def test_normalize_lot_mixed_case(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization of mixed-case lot."""
        result = lot_wafer_extractor.normalize_lot("Kg4BntCx")
        assert result == "KG4BNTCX"

    def test_normalize_lot_with_whitespace(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization strips whitespace."""
        result = lot_wafer_extractor.normalize_lot("  KG4BNTCX  ")
        assert result == "KG4BNTCX"

    def test_normalize_lot_with_leading_whitespace(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization strips leading whitespace."""
        result = lot_wafer_extractor.normalize_lot("  KG42910X1")
        assert result == "KG42910X1"

    def test_normalize_lot_alternative_format(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization of alternative lot format."""
        result = lot_wafer_extractor.normalize_lot("KG42910X1")
        assert result == "KG42910X1"

    def test_normalize_lot_empty_string(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization of empty string."""
        result = lot_wafer_extractor.normalize_lot("")
        assert result == ""

    def test_normalize_lot_none(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization of None."""
        result = lot_wafer_extractor.normalize_lot(None)  # type: ignore
        assert result == ""

    def test_normalize_lot_invalid_no_kg_prefix(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization rejects lot without KG prefix."""
        result = lot_wafer_extractor.normalize_lot("4BNTCX")
        assert result == ""

    def test_normalize_lot_invalid_too_short(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization rejects lot that is too short."""
        result = lot_wafer_extractor.normalize_lot("KG")
        assert result == ""

    def test_normalize_lot_invalid_kg_only(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization rejects lot with only KG."""
        result = lot_wafer_extractor.normalize_lot("KG1")
        assert result == ""

    def test_normalize_lot_with_non_alphanumeric(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization removes non-alphanumeric characters."""
        result = lot_wafer_extractor.normalize_lot("KG4-BNTCX")
        assert result == "KG4BNTCX"

    def test_normalize_lot_with_special_chars(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization removes special characters."""
        result = lot_wafer_extractor.normalize_lot("KG4_BNTCX_123")
        assert result == "KG4BNTCX123"


# ============================================================================
# Test Wafer Normalization
# ============================================================================


@pytest.mark.unit
class TestWaferNormalization:
    """Test wafer identifier normalization."""

    def test_normalize_wafer_standard_format(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization of standard wafer format."""
        result = lot_wafer_extractor.normalize_wafer("GOXTWS1125")
        assert result == "GOXTWS1125"

    def test_normalize_wafer_lowercase(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization converts lowercase wafer to uppercase."""
        result = lot_wafer_extractor.normalize_wafer("goxtws1125")
        assert result == "GOXTWS1125"

    def test_normalize_wafer_mixed_case(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization of mixed-case wafer."""
        result = lot_wafer_extractor.normalize_wafer("GoxTws2135")
        assert result == "GOXTWS2135"

    def test_normalize_wafer_with_whitespace(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization strips whitespace."""
        result = lot_wafer_extractor.normalize_wafer("  GOXTWS1125  ")
        assert result == "GOXTWS1125"

    def test_normalize_wafer_alternative_format(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization of alternative wafer format."""
        result = lot_wafer_extractor.normalize_wafer("GOXTWS2135")
        assert result == "GOXTWS2135"

    def test_normalize_wafer_empty_string(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization of empty string."""
        result = lot_wafer_extractor.normalize_wafer("")
        assert result == ""

    def test_normalize_wafer_none(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization of None."""
        result = lot_wafer_extractor.normalize_wafer(None)  # type: ignore
        assert result == ""

    def test_normalize_wafer_invalid_no_goxtws_prefix(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization rejects wafer without GOXTWS prefix."""
        result = lot_wafer_extractor.normalize_wafer("1125")
        assert result == ""

    def test_normalize_wafer_with_non_alphanumeric(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization removes non-alphanumeric characters."""
        result = lot_wafer_extractor.normalize_wafer("GOXTWS-1125")
        assert result == "GOXTWS1125"

    def test_normalize_virtual_wafer(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization of virtual wafer format."""
        result = lot_wafer_extractor.normalize_wafer("VW_abc123def456")
        assert result == "VW_abc123def456"

    def test_normalize_virtual_wafer_uppercase(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test normalization of virtual wafer to uppercase."""
        result = lot_wafer_extractor.normalize_wafer("vw_abc123def456")
        assert result == "VW_ABC123DEF456"


# ============================================================================
# Test Find Lot in String
# ============================================================================


@pytest.mark.unit
class TestFindLotInString:
    """Test finding lot patterns in strings."""

    def test_find_lot_simple(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test finding simple lot pattern."""
        result = lot_wafer_extractor._find_lot_in_string("KG4BNTCX")
        assert result == "KG4BNTCX"

    def test_find_lot_with_prefix(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test finding lot pattern with text prefix."""
        result = lot_wafer_extractor._find_lot_in_string("TEST_KG4BNTCX_END")
        assert result == "KG4BNTCX"

    def test_find_lot_with_underscore(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test finding lot pattern with underscores."""
        result = lot_wafer_extractor._find_lot_in_string("THK_KG42910X1_51T")
        assert result == "KG42910X1"

    def test_find_lot_not_found(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test lot pattern not found."""
        result = lot_wafer_extractor._find_lot_in_string("NO_LOT_HERE")
        assert result is None

    def test_find_lot_empty_string(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test finding lot in empty string."""
        result = lot_wafer_extractor._find_lot_in_string("")
        assert result is None

    def test_find_lot_lowercase(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test finding lot in lowercase."""
        result = lot_wafer_extractor._find_lot_in_string("test_kg4bntcx_end")
        assert result == "KG4BNTCX"

    def test_find_lot_none_input(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test finding lot in None input."""
        result = lot_wafer_extractor._find_lot_in_string(None)  # type: ignore
        assert result is None


# ============================================================================
# Test Find Wafer in String
# ============================================================================


@pytest.mark.unit
class TestFindWaferInString:
    """Test finding wafer patterns in strings."""

    def test_find_wafer_simple(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test finding simple wafer pattern."""
        result = lot_wafer_extractor._find_wafer_in_string("GOXTWS1125")
        assert result == "GOXTWS1125"

    def test_find_wafer_with_prefix(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test finding wafer pattern with text prefix."""
        result = lot_wafer_extractor._find_wafer_in_string("TEST_GOXTWS1125_END")
        assert result == "GOXTWS1125"

    def test_find_wafer_with_underscore(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test finding wafer pattern with underscores."""
        result = lot_wafer_extractor._find_wafer_in_string("THK_GOXTWS2135_51T")
        assert result == "GOXTWS2135"

    def test_find_wafer_not_found(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test wafer pattern not found."""
        result = lot_wafer_extractor._find_wafer_in_string("NO_WAFER_HERE")
        assert result is None

    def test_find_wafer_empty_string(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test finding wafer in empty string."""
        result = lot_wafer_extractor._find_wafer_in_string("")
        assert result is None

    def test_find_wafer_lowercase(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test finding wafer in lowercase."""
        result = lot_wafer_extractor._find_wafer_in_string("test_goxtws1125_end")
        assert result == "GOXTWS1125"

    def test_find_wafer_none_input(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test finding wafer in None input."""
        result = lot_wafer_extractor._find_wafer_in_string(None)  # type: ignore
        assert result is None


# ============================================================================
# Test Extract Wafer Family
# ============================================================================


@pytest.mark.unit
class TestExtractWaferFamily:
    """Test wafer family extraction."""

    def test_extract_wafer_family_goxtws(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test extracting family from GOXTWS wafer."""
        result = lot_wafer_extractor._extract_wafer_family("GOXTWS1125")
        assert result == "GOXTWS"

    def test_extract_wafer_family_virtual(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test extracting family from virtual wafer."""
        result = lot_wafer_extractor._extract_wafer_family("VW_abc123def456")
        assert result == "VIRTUAL"

    def test_extract_wafer_family_empty(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test extracting family from empty wafer ID."""
        result = lot_wafer_extractor._extract_wafer_family("")
        assert result == ""

    def test_extract_wafer_family_unknown(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test extracting family from unknown wafer pattern."""
        result = lot_wafer_extractor._extract_wafer_family("UNKNOWN1234")
        assert result == ""


# ============================================================================
# Test Virtual Wafer Generation
# ============================================================================


@pytest.mark.unit
class TestVirtualWaferGeneration:
    """Test virtual wafer ID generation."""

    def test_generate_virtual_wafer_basic(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test generating virtual wafer ID."""
        virtual_id = lot_wafer_extractor.generate_virtual_wafer(
            lot_id="KG4BNTCX",
            equipment_id="THK-1-51T",
            timestamp="2026-07-14T03:34:33Z"
        )
        assert virtual_id.startswith("VW_")
        assert len(virtual_id) == len("VW_") + 16

    def test_generate_virtual_wafer_deterministic(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test that virtual wafer generation is deterministic."""
        id1 = lot_wafer_extractor.generate_virtual_wafer(
            lot_id="KG4BNTCX",
            equipment_id="THK-1-51T",
            timestamp="2026-07-14T03:34:33Z"
        )
        id2 = lot_wafer_extractor.generate_virtual_wafer(
            lot_id="KG4BNTCX",
            equipment_id="THK-1-51T",
            timestamp="2026-07-14T03:34:33Z"
        )
        assert id1 == id2

    def test_generate_virtual_wafer_different_lots(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test that different lots produce different virtual wafers."""
        id1 = lot_wafer_extractor.generate_virtual_wafer(
            lot_id="KG4BNTCX",
            equipment_id="THK-1-51T",
            timestamp="2026-07-14T03:34:33Z"
        )
        id2 = lot_wafer_extractor.generate_virtual_wafer(
            lot_id="KG42910X1",
            equipment_id="THK-1-51T",
            timestamp="2026-07-14T03:34:33Z"
        )
        assert id1 != id2

    def test_generate_virtual_wafer_different_equipment(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test that different equipment produces different virtual wafers."""
        id1 = lot_wafer_extractor.generate_virtual_wafer(
            lot_id="KG4BNTCX",
            equipment_id="THK-1-51T",
            timestamp="2026-07-14T03:34:33Z"
        )
        id2 = lot_wafer_extractor.generate_virtual_wafer(
            lot_id="KG4BNTCX",
            equipment_id="RI-1-11",
            timestamp="2026-07-14T03:34:33Z"
        )
        assert id1 != id2

    def test_generate_virtual_wafer_different_timestamp(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test that different timestamps produce different virtual wafers."""
        id1 = lot_wafer_extractor.generate_virtual_wafer(
            lot_id="KG4BNTCX",
            equipment_id="THK-1-51T",
            timestamp="2026-07-14T03:34:33Z"
        )
        id2 = lot_wafer_extractor.generate_virtual_wafer(
            lot_id="KG4BNTCX",
            equipment_id="THK-1-51T",
            timestamp="2026-07-14T04:35:34Z"
        )
        assert id1 != id2


# ============================================================================
# Test Extract Method
# ============================================================================


@pytest.mark.unit
class TestExtractMethod:
    """Test the main extract method."""

    def test_extract_with_both_lot_and_wafer(
        self,
        lot_wafer_extractor: LotWaferExtractor,
        record_with_lot_and_wafer: ParsedRecord
    ) -> None:
        """Test extraction when both lot and wafer are present."""
        lot_id, wafer_id, wafer_family = lot_wafer_extractor.extract(record_with_lot_and_wafer)
        
        assert lot_id == "KG4BNTCX"
        assert wafer_id == "GOXTWS1125"
        assert wafer_family == "GOXTWS"

    def test_extract_with_lot_only_generates_virtual_wafer(
        self,
        lot_wafer_extractor: LotWaferExtractor,
        record_with_lot: ParsedRecord
    ) -> None:
        """Test extraction generates virtual wafer when lot present but wafer absent."""
        lot_id, wafer_id, wafer_family = lot_wafer_extractor.extract(record_with_lot)
        
        assert lot_id == "KG4BNTCX"
        assert wafer_id.startswith("VW_")
        assert wafer_family == "VIRTUAL"

    def test_extract_with_wafer_only_no_lot(
        self,
        lot_wafer_extractor: LotWaferExtractor,
        record_with_only_wafer: ParsedRecord
    ) -> None:
        """Test extraction when wafer present but no lot."""
        lot_id, wafer_id, wafer_family = lot_wafer_extractor.extract(record_with_only_wafer)
        
        assert lot_id == ""
        assert wafer_id == "GOXTWS2135"
        assert wafer_family == "GOXTWS"

    def test_extract_returns_tuple(
        self,
        lot_wafer_extractor: LotWaferExtractor,
        record_with_lot_and_wafer: ParsedRecord
    ) -> None:
        """Test extraction returns tuple of three strings."""
        result = lot_wafer_extractor.extract(record_with_lot_and_wafer)
        
        assert isinstance(result, tuple)
        assert len(result) == 3
        assert all(isinstance(item, str) for item in result)


# ============================================================================
# Test Error Handling
# ============================================================================


@pytest.mark.unit
class TestErrorHandling:
    """Test error handling in extract method."""

    def test_extract_with_none_record(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test extract raises ExtractionError with None record."""
        with pytest.raises(ExtractionError) as exc_info:
            lot_wafer_extractor.extract(None)  # type: ignore

        assert exc_info.value.error_code == "LOT_WAFER_EXTRACT_001"

    def test_extract_with_incomplete_record(self, lot_wafer_extractor: LotWaferExtractor) -> None:
        """Test extract raises ExtractionError with incomplete record."""
        incomplete_record = ParsedRecord(
            raw_line="",
            parameter_set_id="",  # Empty required field
            parameter_set_version="",
            date_time="",
            facility="",
            parameter_name="",
            sequence_number=0,
            unit_id="",
            type_id="",
            c_values=[],
            d_values=[],
            timestamp=""
        )
        
        with pytest.raises(ExtractionError) as exc_info:
            lot_wafer_extractor.extract(incomplete_record)

        assert exc_info.value.error_code == "LOT_WAFER_EXTRACT_002"


# ============================================================================
# Test Integration
# ============================================================================


@pytest.mark.unit
class TestExtractorIntegration:
    """Test integration scenarios."""

    def test_extract_multiple_records_consistency(
        self,
        lot_wafer_extractor: LotWaferExtractor,
        record_with_lot_and_wafer: ParsedRecord
    ) -> None:
        """Test that extraction is consistent across multiple calls."""
        results = [
            lot_wafer_extractor.extract(record_with_lot_and_wafer)
            for _ in range(3)
        ]
        
        # All results should be identical
        assert all(r == results[0] for r in results)

    def test_extract_different_extractors_same_result(
        self,
        record_with_lot_and_wafer: ParsedRecord
    ) -> None:
        """Test that different extractor instances produce same results."""
        extractor1 = LotWaferExtractor()
        extractor2 = LotWaferExtractor()
        
        result1 = extractor1.extract(record_with_lot_and_wafer)
        result2 = extractor2.extract(record_with_lot_and_wafer)
        
        assert result1 == result2

    def test_normalize_extracted_lot_and_wafer(
        self,
        lot_wafer_extractor: LotWaferExtractor
    ) -> None:
        """Test normalizing extracted lot and wafer identifiers."""
        lot_id = lot_wafer_extractor.normalize_lot("kg4bntcx")
        wafer_id = lot_wafer_extractor.normalize_wafer("goxtws1125")
        
        assert lot_id == "KG4BNTCX"
        assert wafer_id == "GOXTWS1125"

    def test_format_validation_pipeline(
        self,
        lot_wafer_extractor: LotWaferExtractor
    ) -> None:
        """Test format validation in full pipeline."""
        # Valid formats
        assert lot_wafer_extractor.normalize_lot("KG4BNTCX") == "KG4BNTCX"
        assert lot_wafer_extractor.normalize_wafer("GOXTWS1125") == "GOXTWS1125"
        
        # Invalid formats
        assert lot_wafer_extractor.normalize_lot("INVALID") == ""
        assert lot_wafer_extractor.normalize_wafer("INVALID") == ""
