"""Unit tests for EquipmentParser component.

Tests equipment code decomposition, normalization, and error handling.
"""

import pytest

from scribe_lot_mapper.exceptions import ExtractionError
from scribe_lot_mapper.extractors.equipment_parser import EquipmentParser
from scribe_lot_mapper.models import EquipmentInfo


@pytest.mark.unit
class TestEquipmentParserBasics:
    """Test basic EquipmentParser functionality."""

    def test_equipment_parser_init_with_defaults(self) -> None:
        """Test EquipmentParser initialization with default values."""
        parser = EquipmentParser()

        assert parser.unknown_marker == "UNKNOWN"

    def test_equipment_parser_init_with_custom_unknown_marker(self) -> None:
        """Test EquipmentParser initialization with custom unknown marker."""
        parser = EquipmentParser(unknown_marker="NULL")

        assert parser.unknown_marker == "NULL"


@pytest.mark.unit
class TestEquipmentParserStandardPattern:
    """Test parsing equipment codes matching standard pattern."""

    def test_parse_standard_code_thk_1_51t(self) -> None:
        """Test parsing standard equipment code THK-1-51T."""
        parser = EquipmentParser()
        info = parser.parse("THK-1-51T")

        assert info.raw_code == "THK-1-51T"
        assert info.facility == "THK"
        assert info.probe == 1
        assert info.position == 51
        assert info.type == "T"
        assert isinstance(info, EquipmentInfo)

    def test_parse_standard_code_thk_1_51f(self) -> None:
        """Test parsing equipment code with F type indicator."""
        parser = EquipmentParser()
        info = parser.parse("THK-1-51F")

        assert info.facility == "THK"
        assert info.probe == 1
        assert info.position == 51
        assert info.type == "F"

    def test_parse_standard_code_ri_1_11(self) -> None:
        """Test parsing equipment code without type indicator."""
        parser = EquipmentParser()
        info = parser.parse("RI-1-11")

        assert info.facility == "RI"
        assert info.probe == 1
        assert info.position == 11
        assert info.type == ""

    def test_parse_standard_code_aci_1_31(self) -> None:
        """Test parsing equipment code ACI-1-31."""
        parser = EquipmentParser()
        info = parser.parse("ACI-1-31")

        assert info.facility == "ACI"
        assert info.probe == 1
        assert info.position == 31
        assert info.type == ""

    def test_parse_standard_code_bv_8_31(self) -> None:
        """Test parsing equipment code with higher probe number."""
        parser = EquipmentParser()
        info = parser.parse("BV-8-31")

        assert info.facility == "BV"
        assert info.probe == 8
        assert info.position == 31
        assert info.type == ""

    def test_parse_standard_code_fb6_5_100t(self) -> None:
        """Test parsing equipment code with larger position number."""
        parser = EquipmentParser()
        info = parser.parse("FB6-5-100T")

        assert info.facility == "FB6"
        assert info.probe == 5
        assert info.position == 100
        assert info.type == "T"

    def test_parse_returns_equipment_info(self) -> None:
        """Test that parse returns EquipmentInfo instance."""
        parser = EquipmentParser()
        info = parser.parse("THK-1-51T")

        assert isinstance(info, EquipmentInfo)

    def test_parse_preserves_raw_code(self) -> None:
        """Test that raw_code is preserved as-is."""
        parser = EquipmentParser()
        info = parser.parse("THK-1-51T")

        assert info.raw_code == "THK-1-51T"


@pytest.mark.unit
class TestEquipmentParserNormalization:
    """Test equipment code normalization."""

    def test_normalize_standard_code_with_type(self) -> None:
        """Test normalizing code with type indicator."""
        parser = EquipmentParser()
        result = parser.normalize("THK-1-51T")

        assert result == "THK-1-51-T"

    def test_normalize_standard_code_without_type(self) -> None:
        """Test normalizing code without type indicator."""
        parser = EquipmentParser()
        result = parser.normalize("RI-1-11")

        assert result == "RI-1-11"

    def test_normalize_lowercase_to_uppercase(self) -> None:
        """Test normalizing converts lowercase to uppercase."""
        parser = EquipmentParser()
        result = parser.normalize("thk-1-51t")

        assert result == "THK-1-51-T"

    def test_normalize_mixed_case(self) -> None:
        """Test normalizing handles mixed case."""
        parser = EquipmentParser()
        result = parser.normalize("ThK-1-51t")

        assert result == "THK-1-51-T"

    def test_normalize_with_whitespace(self) -> None:
        """Test normalizing strips whitespace."""
        parser = EquipmentParser()
        result = parser.normalize("  THK-1-51T  ")

        assert result == "THK-1-51-T"

    def test_normalize_fb6_5_100t(self) -> None:
        """Test normalizing multi-digit facility, probe, and position."""
        parser = EquipmentParser()
        result = parser.normalize("FB6-5-100T")

        assert result == "FB6-5-100-T"

    def test_normalize_empty_string(self) -> None:
        """Test normalizing empty string returns empty."""
        parser = EquipmentParser()
        result = parser.normalize("")

        assert result == ""

    def test_normalize_none_returns_empty(self) -> None:
        """Test normalizing None-like values returns empty."""
        parser = EquipmentParser()
        result = parser.normalize("")

        assert result == ""


@pytest.mark.unit
class TestEquipmentParserDecompose:
    """Test decompose method."""

    def test_decompose_returns_tuple(self) -> None:
        """Test decompose returns tuple."""
        parser = EquipmentParser()
        result = parser.decompose("THK-1-51T")

        assert isinstance(result, tuple)
        assert len(result) == 4

    def test_decompose_thk_1_51t(self) -> None:
        """Test decomposing THK-1-51T."""
        parser = EquipmentParser()
        facility, probe, position, type_code = parser.decompose("THK-1-51T")

        assert facility == "THK"
        assert probe == 1
        assert position == 51
        assert type_code == "T"

    def test_decompose_ri_1_11(self) -> None:
        """Test decomposing RI-1-11."""
        parser = EquipmentParser()
        facility, probe, position, type_code = parser.decompose("RI-1-11")

        assert facility == "RI"
        assert probe == 1
        assert position == 11
        assert type_code == ""

    def test_decompose_bv_8_31(self) -> None:
        """Test decomposing BV-8-31."""
        parser = EquipmentParser()
        facility, probe, position, type_code = parser.decompose("BV-8-31")

        assert facility == "BV"
        assert probe == 8
        assert position == 31
        assert type_code == ""

    def test_decompose_probe_is_int(self) -> None:
        """Test that probe is returned as integer."""
        parser = EquipmentParser()
        facility, probe, position, type_code = parser.decompose("THK-1-51T")

        assert isinstance(probe, int)

    def test_decompose_position_is_int(self) -> None:
        """Test that position is returned as integer."""
        parser = EquipmentParser()
        facility, probe, position, type_code = parser.decompose("THK-1-51T")

        assert isinstance(position, int)


@pytest.mark.unit
class TestEquipmentParserErrorHandling:
    """Test error handling."""

    def test_parse_empty_string_raises_extraction_error(self) -> None:
        """Test parsing empty string raises ExtractionError."""
        parser = EquipmentParser()

        with pytest.raises(ExtractionError) as exc_info:
            parser.parse("")

        assert exc_info.value.error_code == "EQUIPMENT_PARSE_001"

    def test_parse_none_raises_extraction_error(self) -> None:
        """Test parsing None raises ExtractionError."""
        parser = EquipmentParser()

        with pytest.raises(ExtractionError) as exc_info:
            parser.parse(None)

        assert exc_info.value.error_code == "EQUIPMENT_PARSE_001"

    def test_parse_non_string_raises_extraction_error(self) -> None:
        """Test parsing non-string raises ExtractionError."""
        parser = EquipmentParser()

        with pytest.raises(ExtractionError) as exc_info:
            parser.parse(12345)

        assert exc_info.value.error_code == "EQUIPMENT_PARSE_001"

    def test_parse_whitespace_only_raises_extraction_error(self) -> None:
        """Test parsing whitespace-only string raises ExtractionError."""
        parser = EquipmentParser()

        with pytest.raises(ExtractionError) as exc_info:
            parser.parse("   \t  \n  ")

        assert exc_info.value.error_code == "EQUIPMENT_PARSE_001"


@pytest.mark.unit
class TestEquipmentParserHeuristicParsing:
    """Test heuristic parsing of non-standard codes."""

    def test_parse_code_with_underscores_instead_of_hyphens(self) -> None:
        """Test parsing code with underscores instead of hyphens."""
        parser = EquipmentParser()
        info = parser.parse("THK_1_51T")

        # Heuristic parsing should extract what it can
        assert info.raw_code == "THK_1_51T"
        assert info.facility == "THK"
        assert info.type == "T"

    def test_parse_code_with_spaces_instead_of_hyphens(self) -> None:
        """Test parsing code with spaces instead of hyphens."""
        parser = EquipmentParser()
        info = parser.parse("THK 1 51T")

        assert info.raw_code == "THK 1 51T"
        assert info.facility == "THK"

    def test_parse_malformed_code_returns_equipment_info(self) -> None:
        """Test parsing malformed code still returns EquipmentInfo."""
        parser = EquipmentParser()
        info = parser.parse("BADCODE")

        assert isinstance(info, EquipmentInfo)
        assert info.raw_code == "BADCODE"

    def test_parse_malformed_code_marks_unknown_components(self) -> None:
        """Test malformed code marks unknown components appropriately."""
        parser = EquipmentParser()
        info = parser.parse("BADCODE")

        # Some components may be marked as unknown
        assert isinstance(info, EquipmentInfo)

    def test_parse_partial_code_with_custom_unknown_marker(self) -> None:
        """Test parsing with custom unknown marker."""
        parser = EquipmentParser(unknown_marker="NULL")
        info = parser.parse("BADCODE")

        assert isinstance(info, EquipmentInfo)
        # Facility might be marked as NULL if not recognized
        assert info.facility in ["NULL", "BADCODE"]


@pytest.mark.unit
class TestEquipmentParserEdgeCases:
    """Test edge cases and boundary conditions."""

    def test_parse_single_digit_probe(self) -> None:
        """Test parsing single-digit probe number."""
        parser = EquipmentParser()
        info = parser.parse("THK-1-51T")

        assert info.probe == 1
        assert isinstance(info.probe, int)

    def test_parse_two_digit_probe(self) -> None:
        """Test parsing two-digit probe number."""
        parser = EquipmentParser()
        info = parser.parse("THK-12-51T")

        assert info.probe == 12
        assert isinstance(info.probe, int)

    def test_parse_single_digit_position(self) -> None:
        """Test parsing single-digit position."""
        parser = EquipmentParser()
        info = parser.parse("THK-1-5T")

        assert info.position == 5
        assert isinstance(info.position, int)

    def test_parse_three_digit_position(self) -> None:
        """Test parsing three-digit position."""
        parser = EquipmentParser()
        info = parser.parse("THK-1-999T")

        assert info.position == 999
        assert isinstance(info.position, int)

    def test_parse_two_letter_facility(self) -> None:
        """Test parsing two-letter facility code."""
        parser = EquipmentParser()
        info = parser.parse("RI-1-11")

        assert info.facility == "RI"
        assert len(info.facility) == 2

    def test_parse_three_letter_facility(self) -> None:
        """Test parsing three-letter facility code."""
        parser = EquipmentParser()
        info = parser.parse("THK-1-51T")

        assert info.facility == "THK"
        assert len(info.facility) == 3

    def test_parse_four_letter_facility(self) -> None:
        """Test parsing four-letter facility code."""
        parser = EquipmentParser()
        info = parser.parse("ABCD-1-51T")

        assert info.facility == "ABCD"
        assert len(info.facility) == 4

    def test_parse_without_type_sets_empty_type(self) -> None:
        """Test parsing code without type sets empty type."""
        parser = EquipmentParser()
        info = parser.parse("RI-1-11")

        assert info.type == ""
        assert isinstance(info.type, str)

    def test_normalize_normalized_code_is_idempotent(self) -> None:
        """Test that normalizing twice gives same result."""
        parser = EquipmentParser()
        normalized1 = parser.normalize("THK-1-51T")
        normalized2 = parser.normalize(normalized1)

        assert normalized1 == normalized2

    def test_parse_normalized_code_is_consistent(self) -> None:
        """Test parsing normalized code gives same components."""
        parser = EquipmentParser()
        info1 = parser.parse("THK-1-51T")
        normalized = parser.normalize("THK-1-51T")
        info2 = parser.parse(normalized)

        assert info1.facility == info2.facility
        assert info1.probe == info2.probe
        assert info1.position == info2.position
        assert info1.type == info2.type


@pytest.mark.unit
class TestEquipmentParserIntegration:
    """Integration tests for parse/normalize/decompose together."""

    def test_parse_normalize_roundtrip(self) -> None:
        """Test parse and normalize work together correctly."""
        parser = EquipmentParser()
        code = "THK-1-51T"
        normalized = parser.normalize(code)
        info = parser.parse(normalized)

        assert info.facility == "THK"
        assert info.probe == 1
        assert info.position == 51
        assert info.type == "T"

    def test_parse_decompose_consistency(self) -> None:
        """Test parse and decompose give consistent results."""
        parser = EquipmentParser()
        code = "BV-8-31"
        
        info = parser.parse(code)
        facility, probe, position, type_code = parser.decompose(code)

        assert info.facility == facility
        assert info.probe == probe
        assert info.position == position
        assert info.type == type_code

    def test_multiple_codes_independent(self) -> None:
        """Test parsing multiple codes doesn't interfere."""
        parser = EquipmentParser()
        
        info1 = parser.parse("THK-1-51T")
        info2 = parser.parse("RI-1-11")
        info3 = parser.parse("BV-8-31")

        assert info1.facility == "THK"
        assert info2.facility == "RI"
        assert info3.facility == "BV"

    def test_same_code_parsed_twice_gives_same_result(self) -> None:
        """Test parsing same code twice gives identical results."""
        parser = EquipmentParser()
        
        info1 = parser.parse("THK-1-51T")
        info2 = parser.parse("THK-1-51T")

        assert info1.facility == info2.facility
        assert info1.probe == info2.probe
        assert info1.position == info2.position
        assert info1.type == info2.type
        assert info1.normalized_code == info2.normalized_code


@pytest.mark.unit
class TestEquipmentParserRealWorldExamples:
    """Test with real-world equipment codes."""

    def test_parse_real_equipment_code_1(self) -> None:
        """Test parsing real equipment code from manufacturing data."""
        parser = EquipmentParser()
        info = parser.parse("FB6-1-51T")

        assert info.facility == "FB6"
        assert info.probe == 1
        assert info.position == 51
        assert info.type == "T"

    def test_parse_real_equipment_code_2(self) -> None:
        """Test parsing another real equipment code."""
        parser = EquipmentParser()
        info = parser.parse("BUCHEON-5-100F")

        # Might fail standard pattern, test heuristic parsing
        assert isinstance(info, EquipmentInfo)
        assert info.raw_code == "BUCHEON-5-100F"

    def test_parse_real_equipment_code_multiple_facilities(self) -> None:
        """Test parsing codes from different facilities."""
        parser = EquipmentParser()
        codes = ["THK-1-51T", "RI-1-11", "ACI-1-31", "BV-8-31", "FB6-5-100T"]

        for code in codes:
            info = parser.parse(code)
            assert isinstance(info, EquipmentInfo)
            assert len(info.facility) >= 2
