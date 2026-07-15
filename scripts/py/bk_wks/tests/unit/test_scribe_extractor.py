"""Unit tests for ScribeExtractor component.

Tests scribe extraction, unit_id normalization, directional mapping, and
composite scribe_id generation.
"""

import pytest

from scribe_lot_mapper.exceptions import ExtractionError
from scribe_lot_mapper.extractors.scribe_extractor import ScribeExtractor
from scribe_lot_mapper.models import EquipmentInfo


# ============================================================================
# Test Fixtures
# ============================================================================


@pytest.fixture
def scribe_extractor() -> ScribeExtractor:
    """Create default ScribeExtractor instance."""
    return ScribeExtractor()


@pytest.fixture
def equipment_thk_1_51() -> EquipmentInfo:
    """Create sample EquipmentInfo for THK-1-51T."""
    return EquipmentInfo(
        raw_code="THK-1-51T",
        facility="THK",
        probe=1,
        position=51,
        type="T",
        normalized_code="THK-1-51-T",
    )


@pytest.fixture
def equipment_ri_1_11() -> EquipmentInfo:
    """Create sample EquipmentInfo for RI-1-11."""
    return EquipmentInfo(
        raw_code="RI-1-11",
        facility="RI",
        probe=1,
        position=11,
        type="",
        normalized_code="RI-1-11",
    )


@pytest.fixture
def equipment_fb6_5_100() -> EquipmentInfo:
    """Create sample EquipmentInfo for FB6-5-100T."""
    return EquipmentInfo(
        raw_code="FB6-5-100T",
        facility="FB6",
        probe=5,
        position=100,
        type="T",
        normalized_code="FB6-5-100-T",
    )


@pytest.fixture
def equipment_goxtws() -> EquipmentInfo:
    """Create sample EquipmentInfo for GOXTWS1125."""
    return EquipmentInfo(
        raw_code="GOXTWS1125",
        facility="GOXTWS",
        probe=0,
        position=0,
        type="",
        normalized_code="GOXTWS1125",
    )


# ============================================================================
# Test Initialization
# ============================================================================


@pytest.mark.unit
class TestScribeExtractorInit:
    """Test ScribeExtractor initialization."""

    def test_init_with_defaults(self) -> None:
        """Test ScribeExtractor initialization with default unknown marker."""
        extractor = ScribeExtractor()

        assert extractor.unknown_marker == "SITE"

    def test_init_with_custom_unknown_marker(self) -> None:
        """Test ScribeExtractor initialization with custom unknown marker."""
        extractor = ScribeExtractor(unknown_marker="UNKNOWN")

        assert extractor.unknown_marker == "UNKNOWN"

    def test_directional_mappings_present(self) -> None:
        """Test that directional mappings are defined."""
        extractor = ScribeExtractor()

        assert extractor.DIRECTIONAL_MAPPINGS["LEFT"] == "1"
        assert extractor.DIRECTIONAL_MAPPINGS["CENTER"] == "2"
        assert extractor.DIRECTIONAL_MAPPINGS["RIGHT"] == "3"
        assert extractor.DIRECTIONAL_MAPPINGS["TOP"] == "1"
        assert extractor.DIRECTIONAL_MAPPINGS["BOTTOM"] == "2"


# ============================================================================
# Test Normalization
# ============================================================================


@pytest.mark.unit
class TestScribeExtractorNormalization:
    """Test unit_id normalization."""

    def test_normalize_left(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of LEFT directional indicator."""
        result = scribe_extractor.normalize("LEFT")
        assert result == "1"

    def test_normalize_center(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of CENTER directional indicator."""
        result = scribe_extractor.normalize("CENTER")
        assert result == "2"

    def test_normalize_right(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of RIGHT directional indicator."""
        result = scribe_extractor.normalize("RIGHT")
        assert result == "3"

    def test_normalize_top(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of TOP directional indicator."""
        result = scribe_extractor.normalize("TOP")
        assert result == "1"

    def test_normalize_bottom(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of BOTTOM directional indicator."""
        result = scribe_extractor.normalize("BOTTOM")
        assert result == "2"

    def test_normalize_lowercase_left(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of lowercase directional indicator."""
        result = scribe_extractor.normalize("left")
        assert result == "1"

    def test_normalize_mixed_case_center(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of mixed-case directional indicator."""
        result = scribe_extractor.normalize("Center")
        assert result == "2"

    def test_normalize_alphanumeric_a6(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of alphanumeric value A6."""
        result = scribe_extractor.normalize("A6")
        assert result == "A6"

    def test_normalize_lowercase_alphanumeric(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization converts lowercase alphanumeric to uppercase."""
        result = scribe_extractor.normalize("a6")
        assert result == "A6"

    def test_normalize_numeric_1(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of numeric value."""
        result = scribe_extractor.normalize("1")
        assert result == "1"

    def test_normalize_numeric_2(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of numeric value."""
        result = scribe_extractor.normalize("2")
        assert result == "2"

    def test_normalize_empty_string(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of empty string."""
        result = scribe_extractor.normalize("")
        assert result == ""

    def test_normalize_whitespace_only(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of whitespace-only string."""
        result = scribe_extractor.normalize("   ")
        assert result == ""

    def test_normalize_none(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of None value."""
        result = scribe_extractor.normalize(None)
        assert result == ""

    def test_normalize_with_leading_trailing_spaces(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization strips leading/trailing whitespace."""
        result = scribe_extractor.normalize("  A6  ")
        assert result == "A6"

    def test_normalize_with_leading_trailing_spaces_directional(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of directional indicator with spaces."""
        result = scribe_extractor.normalize("  LEFT  ")
        assert result == "1"


# ============================================================================
# Test Composite ID Generation
# ============================================================================


@pytest.mark.unit
class TestScribeExtractorCompositeId:
    """Test composite scribe_id generation."""

    def test_generate_composite_id_standard(self, scribe_extractor: ScribeExtractor) -> None:
        """Test generating composite ID with standard components."""
        result = scribe_extractor.generate_composite_id(
            facility="THK",
            probe=1,
            position=51,
            unit_id="LEFT",
            site_number=1,
        )
        assert result == "THK_1_51_LEFT_1"

    def test_generate_composite_id_different_facility(self, scribe_extractor: ScribeExtractor) -> None:
        """Test generating composite ID with different facility."""
        result = scribe_extractor.generate_composite_id(
            facility="FB6",
            probe=5,
            position=100,
            unit_id="A6",
            site_number=2,
        )
        assert result == "FB6_5_100_A6_2"

    def test_generate_composite_id_no_unit_id(self, scribe_extractor: ScribeExtractor) -> None:
        """Test generating composite ID with unknown unit_id."""
        result = scribe_extractor.generate_composite_id(
            facility="RI",
            probe=1,
            position=11,
            unit_id="SITE",
            site_number=1,
        )
        assert result == "RI_1_11_SITE_1"

    def test_generate_composite_id_site_number_5(self, scribe_extractor: ScribeExtractor) -> None:
        """Test generating composite ID with site_number=5."""
        result = scribe_extractor.generate_composite_id(
            facility="THK",
            probe=1,
            position=51,
            unit_id="CENTER",
            site_number=5,
        )
        assert result == "THK_1_51_CENTER_5"

    def test_generate_composite_id_numeric_unit_id(self, scribe_extractor: ScribeExtractor) -> None:
        """Test generating composite ID with numeric unit_id."""
        result = scribe_extractor.generate_composite_id(
            facility="BV",
            probe=8,
            position=31,
            unit_id="1",
            site_number=1,
        )
        assert result == "BV_8_31_1_1"


# ============================================================================
# Test Extract Method
# ============================================================================


@pytest.mark.unit
class TestScribeExtractorExtract:
    """Test extract method combining all functionality."""

    def test_extract_with_left_unit_id(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extracting scribe with LEFT unit_id."""
        result = scribe_extractor.extract("LEFT", equipment_thk_1_51, site_number=1)
        assert result == "THK_1_51_LEFT_1"

    def test_extract_with_center_unit_id(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extracting scribe with CENTER unit_id."""
        result = scribe_extractor.extract("CENTER", equipment_thk_1_51, site_number=2)
        assert result == "THK_1_51_CENTER_2"

    def test_extract_with_right_unit_id(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extracting scribe with RIGHT unit_id."""
        result = scribe_extractor.extract("RIGHT", equipment_thk_1_51, site_number=3)
        assert result == "THK_1_51_RIGHT_3"

    def test_extract_with_empty_unit_id(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extracting scribe with empty unit_id uses unknown marker."""
        result = scribe_extractor.extract("", equipment_thk_1_51, site_number=1)
        assert result == "THK_1_51_SITE_1"

    def test_extract_with_alphanumeric_unit_id(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extracting scribe with alphanumeric unit_id."""
        result = scribe_extractor.extract("A6", equipment_thk_1_51, site_number=1)
        assert result == "THK_1_51_A6_1"

    def test_extract_with_numeric_unit_id(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extracting scribe with numeric unit_id."""
        result = scribe_extractor.extract("1", equipment_thk_1_51, site_number=1)
        assert result == "THK_1_51_1_1"

    def test_extract_with_ri_equipment(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_ri_1_11: EquipmentInfo,
    ) -> None:
        """Test extracting scribe with RI equipment."""
        result = scribe_extractor.extract("LEFT", equipment_ri_1_11, site_number=1)
        assert result == "RI_1_11_LEFT_1"

    def test_extract_with_fb6_equipment(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_fb6_5_100: EquipmentInfo,
    ) -> None:
        """Test extracting scribe with FB6 equipment."""
        result = scribe_extractor.extract("A6", equipment_fb6_5_100, site_number=2)
        assert result == "FB6_5_100_A6_2"

    def test_extract_with_goxtws_equipment(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_goxtws: EquipmentInfo,
    ) -> None:
        """Test extracting scribe with GOXTWS wafer equipment."""
        result = scribe_extractor.extract("A6", equipment_goxtws, site_number=1)
        assert result == "GOXTWS_0_0_A6_1"

    def test_extract_multisite_site_number_4(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extracting scribe with site_number=4 for multi-site."""
        result = scribe_extractor.extract("CENTER", equipment_thk_1_51, site_number=4)
        assert result == "THK_1_51_CENTER_4"

    def test_extract_multisite_site_number_5(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extracting scribe with site_number=5 for multi-site."""
        result = scribe_extractor.extract("RIGHT", equipment_thk_1_51, site_number=5)
        assert result == "THK_1_51_RIGHT_5"


# ============================================================================
# Test Error Handling
# ============================================================================


@pytest.mark.unit
class TestScribeExtractorErrorHandling:
    """Test error handling in extract method."""

    def test_extract_with_none_equipment_info(
        self, scribe_extractor: ScribeExtractor
    ) -> None:
        """Test extract raises ExtractionError with None equipment_info."""
        with pytest.raises(ExtractionError) as exc_info:
            scribe_extractor.extract("LEFT", None, site_number=1)

        assert exc_info.value.error_code == "SCRIBE_EXTRACT_001"

    def test_extract_with_invalid_site_number_zero(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extract raises ExtractionError with site_number=0."""
        with pytest.raises(ExtractionError) as exc_info:
            scribe_extractor.extract("LEFT", equipment_thk_1_51, site_number=0)

        assert exc_info.value.error_code == "SCRIBE_EXTRACT_002"

    def test_extract_with_invalid_site_number_negative(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extract raises ExtractionError with negative site_number."""
        with pytest.raises(ExtractionError) as exc_info:
            scribe_extractor.extract("LEFT", equipment_thk_1_51, site_number=-1)

        assert exc_info.value.error_code == "SCRIBE_EXTRACT_002"

    def test_extract_with_invalid_site_number_too_high(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extract raises ExtractionError with site_number > 5."""
        with pytest.raises(ExtractionError) as exc_info:
            scribe_extractor.extract("LEFT", equipment_thk_1_51, site_number=6)

        assert exc_info.value.error_code == "SCRIBE_EXTRACT_002"

    def test_extract_with_non_integer_site_number(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extract raises ExtractionError with non-integer site_number."""
        with pytest.raises(ExtractionError) as exc_info:
            scribe_extractor.extract("LEFT", equipment_thk_1_51, site_number="1")  # type: ignore

        assert exc_info.value.error_code == "SCRIBE_EXTRACT_002"


# ============================================================================
# Test Edge Cases
# ============================================================================


@pytest.mark.unit
class TestScribeExtractorEdgeCases:
    """Test edge cases and special scenarios."""

    def test_normalize_with_whitespace_around_directional(
        self, scribe_extractor: ScribeExtractor
    ) -> None:
        """Test normalization with whitespace around directional indicator."""
        result = scribe_extractor.normalize("  left  ")
        assert result == "1"

    def test_normalize_p1_format(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of P1 format (probe position)."""
        result = scribe_extractor.normalize("P1")
        assert result == "P1"

    def test_normalize_lowercase_p1_format(self, scribe_extractor: ScribeExtractor) -> None:
        """Test normalization of lowercase p1 format."""
        result = scribe_extractor.normalize("p1")
        assert result == "P1"

    def test_extract_deterministic_same_inputs(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test that extract is deterministic (same inputs = same output)."""
        result1 = scribe_extractor.extract("LEFT", equipment_thk_1_51, site_number=1)
        result2 = scribe_extractor.extract("LEFT", equipment_thk_1_51, site_number=1)

        assert result1 == result2

    def test_extract_consistent_across_calls(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extract consistency across multiple calls."""
        results = [
            scribe_extractor.extract("A6", equipment_thk_1_51, site_number=1)
            for _ in range(5)
        ]

        assert all(r == "THK_1_51_A6_1" for r in results)

    def test_extract_different_extractors_same_result(
        self, equipment_thk_1_51: EquipmentInfo
    ) -> None:
        """Test that different extractor instances produce same results."""
        extractor1 = ScribeExtractor()
        extractor2 = ScribeExtractor()

        result1 = extractor1.extract("LEFT", equipment_thk_1_51, site_number=1)
        result2 = extractor2.extract("LEFT", equipment_thk_1_51, site_number=1)

        assert result1 == result2


# ============================================================================
# Test Integration with Equipment Parser
# ============================================================================


@pytest.mark.unit
class TestScribeExtractorIntegration:
    """Test integration with equipment parsing."""

    def test_extract_with_standard_equipment_codes(
        self, scribe_extractor: ScribeExtractor
    ) -> None:
        """Test extracting scribes from standard equipment codes."""
        equipment_codes = [
            EquipmentInfo("THK-1-51T", "THK", 1, 51, "T", "THK-1-51-T"),
            EquipmentInfo("RI-1-11", "RI", 1, 11, "", "RI-1-11"),
            EquipmentInfo("FB6-5-100T", "FB6", 5, 100, "T", "FB6-5-100-T"),
        ]

        results = [
            scribe_extractor.extract("LEFT", eq, site_number=1)
            for eq in equipment_codes
        ]

        assert results[0] == "THK_1_51_LEFT_1"
        assert results[1] == "RI_1_11_LEFT_1"
        assert results[2] == "FB6_5_100_LEFT_1"

    def test_extract_all_directional_indicators(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extracting with all directional indicators."""
        directions = ["LEFT", "CENTER", "RIGHT", "TOP", "BOTTOM"]
        results = [
            scribe_extractor.extract(direction, equipment_thk_1_51, site_number=1)
            for direction in directions
        ]

        assert results[0] == "THK_1_51_LEFT_1"
        assert results[1] == "THK_1_51_CENTER_1"
        assert results[2] == "THK_1_51_RIGHT_1"
        assert results[3] == "THK_1_51_TOP_1"
        assert results[4] == "THK_1_51_BOTTOM_1"

    def test_extract_all_site_numbers(
        self,
        scribe_extractor: ScribeExtractor,
        equipment_thk_1_51: EquipmentInfo,
    ) -> None:
        """Test extracting with all valid site numbers (1-5)."""
        results = [
            scribe_extractor.extract("CENTER", equipment_thk_1_51, site_number=i)
            for i in range(1, 6)
        ]

        assert results[0] == "THK_1_51_CENTER_1"
        assert results[1] == "THK_1_51_CENTER_2"
        assert results[2] == "THK_1_51_CENTER_3"
        assert results[3] == "THK_1_51_CENTER_4"
        assert results[4] == "THK_1_51_CENTER_5"


# ============================================================================
# Test Custom Unknown Marker
# ============================================================================


@pytest.mark.unit
class TestScribeExtractorCustomUnknownMarker:
    """Test ScribeExtractor with custom unknown marker."""

    def test_extract_with_custom_unknown_marker(
        self, equipment_thk_1_51: EquipmentInfo
    ) -> None:
        """Test extract uses custom unknown marker for empty unit_id."""
        extractor = ScribeExtractor(unknown_marker="UNKNOWN")

        result = extractor.extract("", equipment_thk_1_51, site_number=1)

        assert result == "THK_1_51_UNKNOWN_1"

    def test_extract_with_null_unknown_marker(
        self, equipment_thk_1_51: EquipmentInfo
    ) -> None:
        """Test extract uses NULL unknown marker."""
        extractor = ScribeExtractor(unknown_marker="NULL")

        result = extractor.extract("", equipment_thk_1_51, site_number=1)

        assert result == "THK_1_51_NULL_1"

    def test_extract_with_empty_string_unknown_marker(
        self, equipment_thk_1_51: EquipmentInfo
    ) -> None:
        """Test extract with empty string unknown marker."""
        extractor = ScribeExtractor(unknown_marker="")

        result = extractor.extract("", equipment_thk_1_51, site_number=1)

        # Empty marker still results in underscores, just no visible marker
        assert result == "THK_1_51__1"
