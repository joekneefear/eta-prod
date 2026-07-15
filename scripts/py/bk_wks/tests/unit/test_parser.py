"""Unit tests for Parser component.

Tests field extraction, normalization, and record parsing.
"""

import pytest

from scribe_lot_mapper.exceptions import ParsingError
from scribe_lot_mapper.extractors.parser import Parser
from scribe_lot_mapper.models import ParsedRecord


@pytest.mark.unit
class TestParserBasics:
    """Test basic Parser functionality."""

    def test_parser_init_with_defaults(self) -> None:
        """Test Parser initialization with default values."""
        parser = Parser()

        assert parser.format_spec == {}
        assert parser.empty_marker == "N/A"

    def test_parser_init_with_custom_empty_marker(self) -> None:
        """Test Parser initialization with custom empty marker."""
        parser = Parser(empty_marker="NULL")

        assert parser.empty_marker == "NULL"

    def test_parser_init_with_format_spec(self) -> None:
        """Test Parser initialization with format specification."""
        format_spec = {
            "delimiter": "\t",
            "fields": {
                "parameter_set_id": {"position": 1, "column_index": 0, "type": "VARCHAR"}
            },
        }
        parser = Parser(format_spec=format_spec)

        assert parser.format_spec == format_spec


@pytest.mark.unit
class TestParserNormalization:
    """Test field value normalization."""

    def test_normalize_empty_string(self) -> None:
        """Test normalizing empty string."""
        parser = Parser()
        result = parser.normalize_value("")

        assert result == "N/A"

    def test_normalize_whitespace_only(self) -> None:
        """Test normalizing whitespace-only string."""
        parser = Parser()
        result = parser.normalize_value("   \t  \n  ")

        assert result == "N/A"

    def test_normalize_strip_whitespace(self) -> None:
        """Test normalizing strips leading/trailing whitespace."""
        parser = Parser()
        result = parser.normalize_value("  test value  ")

        assert result == "test value"

    def test_normalize_remove_double_quotes(self) -> None:
        """Test normalizing removes double quotes."""
        parser = Parser()
        result = parser.normalize_value('"quoted value"')

        assert result == "quoted value"

    def test_normalize_remove_single_quotes(self) -> None:
        """Test normalizing removes single quotes."""
        parser = Parser()
        result = parser.normalize_value("'quoted value'")

        assert result == "quoted value"

    def test_normalize_collapse_multiple_spaces(self) -> None:
        """Test normalizing collapses multiple spaces."""
        parser = Parser()
        result = parser.normalize_value("value   with   spaces")

        assert result == "value with spaces"

    def test_normalize_custom_empty_marker(self) -> None:
        """Test normalizing with custom empty marker."""
        parser = Parser(empty_marker="NULL")
        result = parser.normalize_value("")

        assert result == "NULL"


@pytest.mark.unit
class TestParserFieldParsing:
    """Test field parsing with type conversion."""

    def test_parse_field_varchar(self) -> None:
        """Test parsing VARCHAR field."""
        parser = Parser()
        result = parser.parse_field("test value", "VARCHAR")

        assert result == "test value"

    def test_parse_field_int(self) -> None:
        """Test parsing INT field."""
        parser = Parser()
        result = parser.parse_field("42", "INT")

        assert result == 42
        assert isinstance(result, int)

    def test_parse_field_integer(self) -> None:
        """Test parsing INTEGER field."""
        parser = Parser()
        result = parser.parse_field("42", "INTEGER")

        assert result == 42

    def test_parse_field_float(self) -> None:
        """Test parsing FLOAT field."""
        parser = Parser()
        result = parser.parse_field("3.14159", "FLOAT")

        assert abs(result - 3.14159) < 0.0001
        assert isinstance(result, float)

    def test_parse_field_decimal(self) -> None:
        """Test parsing DECIMAL field."""
        parser = Parser()
        result = parser.parse_field("3.14", "DECIMAL")

        assert abs(result - 3.14) < 0.01

    def test_parse_field_empty_int_returns_zero(self) -> None:
        """Test parsing empty INT field returns 0."""
        parser = Parser()
        result = parser.parse_field("", "INT")

        assert result == 0

    def test_parse_field_invalid_int_returns_zero(self) -> None:
        """Test parsing invalid INT returns 0."""
        parser = Parser()
        result = parser.parse_field("not a number", "INT")

        assert result == 0

    def test_parse_field_int_with_leading_digits(self) -> None:
        """Test parsing INT with leading digits extracted."""
        parser = Parser()
        result = parser.parse_field("42abc", "INT")

        assert result == 42

    def test_parse_field_float_with_leading_digits(self) -> None:
        """Test parsing FLOAT with leading digits extracted."""
        parser = Parser()
        result = parser.parse_field("3.14abc", "FLOAT")

        assert abs(result - 3.14) < 0.01


@pytest.mark.unit
class TestParserRecordParsing:
    """Test complete record parsing."""

    def test_parse_record_simple(self) -> None:
        """Test parsing simple tab-delimited record."""
        parser = Parser()
        line = "GMBG3002\t1.0\tJUL 14 2026\tWW29\tFB6\tTEST_1\t1\tLEFT\tTHK-1-51T\t301.2\tN/A\tN/A\tN/A\tN/A\tN/A\tN/A\tN/A\tN/A\tN/A\tN/A\tN/A"

        record = parser.parse_record(line)

        assert record.parameter_set_id == "GMBG3002"
        assert record.parameter_set_version == "1.0"
        assert record.facility == "FB6"
        assert record.unit_id == "LEFT"
        assert record.type_id == "THK-1-51T"
        assert record.c_values[0] == "301.2"

    def test_parse_record_empty_fields(self) -> None:
        """Test parsing record with empty fields."""
        parser = Parser()
        line = "GMBG3002\t\tJUL 14 2026\t\tFB6\t\t1\tLEFT\tTHK-1-51T\t\t\t\t\t\t\t\t\t\t\t\t"

        record = parser.parse_record(line)

        assert record.parameter_set_id == "GMBG3002"
        assert record.parameter_set_version == "N/A"
        assert record.parameter_name == "N/A"

    def test_parse_record_with_line_number(self) -> None:
        """Test parsing record with line number for error reporting."""
        parser = Parser()
        line = "GMBG3002\t1.0\tJUL 14 2026\tWW29\tFB6\tTEST_1\t1\tLEFT\tTHK-1-51T\t301.2"

        record = parser.parse_record(line, line_number=42)

        assert record.parameter_set_id == "GMBG3002"

    def test_parse_record_extracts_c_values(self) -> None:
        """Test that parser extracts c_value array."""
        parser = Parser()
        line = "GMBG3002\t1.0\tJUL 14 2026\tWW29\tFB6\tTEST_1\t1\tLEFT\tTHK-1-51T\t301.2\t4.9\t5.7\t5.7\t5.4\t\t\t\t\t\t\t"

        record = parser.parse_record(line)

        assert len(record.c_values) == 5
        assert record.c_values[0] == "301.2"
        assert record.c_values[1] == "4.9"
        assert record.c_values[2] == "5.7"
        assert record.c_values[3] == "5.7"
        assert record.c_values[4] == "5.4"

    def test_parse_record_extracts_d_values(self) -> None:
        """Test that parser extracts d_value array."""
        parser = Parser()
        line = "GMBG3002\t1.0\tJUL 14 2026\tWW29\tFB6\tTEST_1\t1\tLEFT\tTHK-1-51T\t\t\t\t\t\t10.5\t20.3\t30.1\t40.2\t50.0\t\t"

        record = parser.parse_record(line)

        assert len(record.d_values) == 5
        assert record.d_values[0] == "10.5"
        assert record.d_values[1] == "20.3"
        assert record.d_values[2] == "30.1"
        assert record.d_values[3] == "40.2"
        assert record.d_values[4] == "50.0"

    def test_parse_record_is_parsed_record(self) -> None:
        """Test that parsed result is ParsedRecord instance."""
        parser = Parser()
        line = "GMBG3002\t1.0\tJUL 14 2026\tWW29\tFB6\tTEST_1\t1\tLEFT\tTHK-1-51T\t301.2"

        record = parser.parse_record(line)

        assert isinstance(record, ParsedRecord)

    def test_parse_record_normalizes_whitespace(self) -> None:
        """Test that parser normalizes whitespace in fields."""
        parser = Parser()
        line = "  GMBG3002  \t  1.0  \t  JUL 14 2026  \t  WW29  \t  FB6  \t  TEST_1  \t  1  \t  LEFT  \t  THK-1-51T  \t  301.2  "

        record = parser.parse_record(line)

        assert record.parameter_set_id == "GMBG3002"
        assert record.parameter_set_version == "1.0"
        assert record.facility == "FB6"
        assert record.unit_id == "LEFT"

    def test_parse_record_sequence_number_as_int(self) -> None:
        """Test that sequence_number is parsed as integer."""
        parser = Parser()
        line = "GMBG3002\t1.0\tJUL 14 2026\tWW29\tFB6\tTEST_1\t42\tLEFT\tTHK-1-51T\t301.2"

        record = parser.parse_record(line)

        assert record.sequence_number == 42
        assert isinstance(record.sequence_number, int)


@pytest.mark.unit
class TestParserEdgeCases:
    """Test edge cases and error conditions."""

    def test_parse_record_short_line(self) -> None:
        """Test parsing line with fewer fields than expected."""
        parser = Parser()
        line = "GMBG3002\t1.0\tJUL 14 2026"

        record = parser.parse_record(line)

        assert record.parameter_set_id == "GMBG3002"
        assert record.parameter_set_version == "1.0"
        assert record.date_time == "JUL 14 2026"
        # Remaining fields should be N/A
        assert record.facility == "N/A"

    def test_parse_record_with_custom_delimiter(self) -> None:
        """Test parsing record with non-tab delimiter."""
        parser = Parser()
        line = "GMBG3002|1.0|JUL 14 2026|WW29|FB6|TEST_1|1|LEFT|THK-1-51T|301.2"

        record = parser.parse_record(line, delimiter="|")

        assert record.parameter_set_id == "GMBG3002"
        assert record.parameter_set_version == "1.0"
        assert record.facility == "FB6"

    def test_parse_record_with_quoted_fields(self) -> None:
        """Test parsing record with quoted fields."""
        parser = Parser()
        line = '"GMBG3002"\t"1.0"\t"JUL 14 2026"\t"WW29"\t"FB6"\t"TEST_1"\t"1"\t"LEFT"\t"THK-1-51T"\t"301.2"'

        record = parser.parse_record(line)

        assert record.parameter_set_id == "GMBG3002"
        assert record.parameter_set_version == "1.0"
        assert record.facility == "FB6"

    def test_parse_record_empty_line(self) -> None:
        """Test parsing empty line."""
        parser = Parser()
        line = ""

        record = parser.parse_record(line)

        assert record.parameter_set_id == "N/A"
        assert record.facility == "N/A"

    def test_parse_record_whitespace_only_line(self) -> None:
        """Test parsing whitespace-only line."""
        parser = Parser()
        line = "   \t  \t   "

        record = parser.parse_record(line)

        assert record.parameter_set_id == "N/A"


@pytest.mark.unit
class TestParserMultiSiteDetection:
    """Test multi-site record detection capabilities."""

    def test_parse_record_single_site(self) -> None:
        """Test parsing single-site record."""
        parser = Parser()
        line = "GMBG3002\t1.0\tJUL 14 2026\tWW29\tFB6\tTEST_1\t1\tLEFT\tTHK-1-51T\t301.2"

        record = parser.parse_record(line)

        assert not record.is_multi_site()
        assert record.site_count() == 1

    def test_parse_record_multi_site_from_c_values(self) -> None:
        """Test parsing multi-site record detected from c_values."""
        parser = Parser()
        line = "GMBG3002\t1.0\tJUL 14 2026\tWW29\tFB6\tTEST_1\t1\tLEFT\tTHK-1-51T\t301.2\t4.9\t5.7\t5.7\t5.4"

        record = parser.parse_record(line)

        assert record.is_multi_site()
        assert record.site_count() == 5

    def test_parse_record_multi_site_from_d_values(self) -> None:
        """Test parsing multi-site record detected from d_values."""
        parser = Parser()
        line = "GMBG3002\t1.0\tJUL 14 2026\tWW29\tFB6\tTEST_1\t1\tLEFT\tTHK-1-51T\t\t\t\t\t\t10.5\t20.3\t30.1\t40.2\t50.0"

        record = parser.parse_record(line)

        assert record.is_multi_site()
        assert record.site_count() == 5


@pytest.mark.unit
class TestParserWithFormatSpec:
    """Test Parser with custom format specification."""

    def test_parse_record_with_format_spec(self) -> None:
        """Test parsing with custom format specification."""
        format_spec = {
            "delimiter": "\t",
            "fields": {
                "parameter_set_id": {
                    "position": 1,
                    "column_index": 0,
                    "type": "VARCHAR",
                },
                "facility": {"position": 5, "column_index": 4, "type": "VARCHAR"},
                "unit_id": {"position": 8, "column_index": 7, "type": "VARCHAR"},
            },
        }
        parser = Parser(format_spec=format_spec)
        line = "GMBG3002\t1.0\tJUL 14 2026\tWW29\tFB6\tTEST_1\t1\tLEFT\tTHK-1-51T\t301.2"

        record = parser.parse_record(line)

        assert record.parameter_set_id == "GMBG3002"
        assert record.facility == "FB6"
        assert record.unit_id == "LEFT"
