"""Unit tests for FormatSpecParser component.

Tests BCP format specification parsing, caching, and field extraction.
"""

from pathlib import Path
from typing import Dict

import pytest

from scribe_lot_mapper.exceptions import ParsingError
from scribe_lot_mapper.readers.format_parser import FormatSpecParser


@pytest.mark.unit
class TestFormatSpecParserBasics:
    """Test basic FormatSpecParser functionality."""

    def test_parser_init_without_file_uses_standard_phist(self) -> None:
        """Test initialization without file uses standard PHIST fields."""
        parser = FormatSpecParser()

        fields = parser.get_fields()
        assert len(fields) > 0
        assert "parameter_set_id" in fields
        assert "facility" in fields
        assert "unit_id" in fields
        assert "type_id" in fields

    def test_parser_standard_phist_field_definitions(self) -> None:
        """Test standard PHIST field definitions are correct."""
        parser = FormatSpecParser()

        fields = parser.get_fields()

        # Check specific fields
        assert fields["parameter_set_id"]["position"] == 1
        assert fields["parameter_set_id"]["column_index"] == 0

        assert fields["facility"]["position"] == 5
        assert fields["facility"]["column_index"] == 4

        assert fields["unit_id"]["position"] == 8
        assert fields["unit_id"]["column_index"] == 7

    def test_parser_field_properties(self) -> None:
        """Test field property structure."""
        parser = FormatSpecParser()

        field = parser.get_field_by_position(1)
        assert field is not None
        assert field["field_name"] == "parameter_set_id"
        assert field["type"] == "VARCHAR"
        assert field["length"] == 255

    def test_parser_get_delimiter(self) -> None:
        """Test default delimiter is tab."""
        parser = FormatSpecParser()
        assert parser.get_delimiter() == "\t"

    def test_parser_get_encoding(self) -> None:
        """Test default encoding is UTF-8."""
        parser = FormatSpecParser()
        assert parser.get_encoding() == "utf-8"


@pytest.mark.unit
class TestFormatSpecParserFieldAccess:
    """Test field access methods."""

    def test_get_field_by_position(self) -> None:
        """Test retrieving field by position (1-based)."""
        parser = FormatSpecParser()

        field_1 = parser.get_field_by_position(1)
        assert field_1 is not None
        assert field_1["field_name"] == "parameter_set_id"

        field_5 = parser.get_field_by_position(5)
        assert field_5 is not None
        assert field_5["field_name"] == "facility"

    def test_get_field_by_index(self) -> None:
        """Test retrieving field by index (0-based)."""
        parser = FormatSpecParser()

        field_0 = parser.get_field_by_index(0)
        assert field_0 is not None
        assert field_0["field_name"] == "parameter_set_id"

        field_4 = parser.get_field_by_index(4)
        assert field_4 is not None
        assert field_4["field_name"] == "facility"

    def test_get_field_nonexistent_position(self) -> None:
        """Test retrieving nonexistent field returns None."""
        parser = FormatSpecParser()

        field = parser.get_field_by_position(999)
        assert field is None

    def test_get_field_nonexistent_index(self) -> None:
        """Test retrieving nonexistent field by index returns None."""
        parser = FormatSpecParser()

        field = parser.get_field_by_index(999)
        assert field is None

    def test_get_all_fields(self) -> None:
        """Test getting all field definitions."""
        parser = FormatSpecParser()

        fields = parser.get_fields()
        assert isinstance(fields, dict)
        assert len(fields) == len(FormatSpecParser.STANDARD_PHIST_FIELDS)

        # All expected fields should be present
        for field_name in FormatSpecParser.STANDARD_PHIST_FIELDS:
            assert field_name in fields


@pytest.mark.unit
class TestFormatSpecParserFileLoading:
    """Test loading format specs from files."""

    def test_parser_load_simple_spec_file(self, tmp_work_dir: Path) -> None:
        """Test loading a simple format specification file.

        Args:
            tmp_work_dir: Temporary working directory
        """
        spec_file = tmp_work_dir / "test.bcp_fmt"
        spec_file.write_text(
            """# Test BCP format specification
parameter_set_id = 1, VARCHAR, 20
facility = 5, VARCHAR, 10
unit_id = 8, VARCHAR, 10
type_id = 9, VARCHAR, 15
"""
        )

        parser = FormatSpecParser(spec_file)
        fields = parser.get_fields()

        assert "parameter_set_id" in fields
        assert fields["parameter_set_id"]["position"] == 1
        assert fields["parameter_set_id"]["type"] == "VARCHAR"
        assert fields["parameter_set_id"]["length"] == 20

        assert "facility" in fields
        assert fields["facility"]["position"] == 5

    def test_parser_load_spec_with_comments(self, tmp_work_dir: Path) -> None:
        """Test loading spec file with comments.

        Args:
            tmp_work_dir: Temporary working directory
        """
        spec_file = tmp_work_dir / "spec_with_comments.bcp_fmt"
        spec_file.write_text(
            """# This is a header comment
# Another comment line

# Field definitions
parameter_set_id = 1, VARCHAR, 20  # Test program ID
facility = 5, VARCHAR, 10          # Facility code

# More comments at end
"""
        )

        parser = FormatSpecParser(spec_file)
        fields = parser.get_fields()

        assert len(fields) == 2
        assert "parameter_set_id" in fields
        assert "facility" in fields

    def test_parser_load_spec_file_not_found(self, tmp_work_dir: Path) -> None:
        """Test loading nonexistent spec file.

        Args:
            tmp_work_dir: Temporary working directory
        """
        missing_spec = tmp_work_dir / "nonexistent.bcp_fmt"

        with pytest.raises(ParsingError) as exc_info:
            FormatSpecParser(missing_spec)

        assert "not found" in str(exc_info.value).lower()

    def test_parser_load_spec_invalid_format(self, tmp_work_dir: Path) -> None:
        """Test loading spec file with invalid format.

        Args:
            tmp_work_dir: Temporary working directory
        """
        bad_spec = tmp_work_dir / "bad.bcp_fmt"
        bad_spec.write_text(
            """# Missing position numbers
parameter_set_id = VARCHAR, 20
facility = INVALID
"""
        )

        with pytest.raises(ParsingError):
            FormatSpecParser(bad_spec)

    def test_parser_load_empty_spec_file(self, tmp_work_dir: Path) -> None:
        """Test loading empty spec file.

        Args:
            tmp_work_dir: Temporary working directory
        """
        empty_spec = tmp_work_dir / "empty.bcp_fmt"
        empty_spec.write_text("# Just comments\n# No fields\n")

        with pytest.raises(ParsingError) as exc_info:
            FormatSpecParser(empty_spec)

        assert "No field definitions" in str(exc_info.value)


@pytest.mark.unit
class TestFormatSpecParserCaching:
    """Test format specification caching."""

    def test_cache_spec(self) -> None:
        """Test caching a parsed specification."""
        # Clear cache first
        FormatSpecParser.clear_cache()

        parser = FormatSpecParser()
        spec = parser.get_spec()

        # Cache should be empty initially
        assert FormatSpecParser.get_cached_spec("test_key") is None

        # Cache the spec
        FormatSpecParser.cache_spec("test_key", spec)

        # Should retrieve from cache
        cached = FormatSpecParser.get_cached_spec("test_key")
        assert cached is not None
        assert cached == spec

    def test_cache_multiple_specs(self) -> None:
        """Test caching multiple specs."""
        FormatSpecParser.clear_cache()

        spec1 = {"name": "spec1", "fields": {}}
        spec2 = {"name": "spec2", "fields": {}}

        FormatSpecParser.cache_spec("key1", spec1)
        FormatSpecParser.cache_spec("key2", spec2)

        assert FormatSpecParser.get_cached_spec("key1") == spec1
        assert FormatSpecParser.get_cached_spec("key2") == spec2

    def test_clear_cache(self) -> None:
        """Test clearing cache."""
        FormatSpecParser.cache_spec("key1", {"test": "spec"})
        assert FormatSpecParser.get_cached_spec("key1") is not None

        FormatSpecParser.clear_cache()
        assert FormatSpecParser.get_cached_spec("key1") is None

    def test_parse_or_use_cached_creates_entry(self, tmp_work_dir: Path) -> None:
        """Test parse_or_use_cached creates cache entry.

        Args:
            tmp_work_dir: Temporary working directory
        """
        FormatSpecParser.clear_cache()

        spec_file = tmp_work_dir / "cache_test.bcp_fmt"
        spec_file.write_text("parameter_set_id = 1, VARCHAR, 20\n")

        # First call should parse and cache
        parser1 = FormatSpecParser.parse_or_use_cached(spec_file)
        assert parser1.get_fields() is not None

        # Verify it's in cache
        cached = FormatSpecParser.get_cached_spec(spec_file)
        assert cached is not None

    def test_parse_or_use_cached_uses_cache(self, tmp_work_dir: Path) -> None:
        """Test parse_or_use_cached uses existing cache.

        Args:
            tmp_work_dir: Temporary working directory
        """
        FormatSpecParser.clear_cache()

        spec_file = tmp_work_dir / "cache_test2.bcp_fmt"
        spec_file.write_text("parameter_set_id = 1, VARCHAR, 20\n")

        # Pre-populate cache
        cached_spec = {"cached": True, "fields": {}}
        FormatSpecParser.cache_spec(spec_file, cached_spec)

        # Should use cached version
        parser = FormatSpecParser.parse_or_use_cached(spec_file)
        assert parser.get_spec() == cached_spec


@pytest.mark.unit
class TestFormatSpecParserSpecRetrieval:
    """Test complete spec retrieval."""

    def test_get_spec(self) -> None:
        """Test getting complete spec."""
        parser = FormatSpecParser()
        spec = parser.get_spec()

        assert isinstance(spec, dict)
        assert "delimiter" in spec
        assert "encoding" in spec
        assert "fields" in spec
        assert "has_header" in spec

    def test_spec_contains_all_phist_fields(self) -> None:
        """Test spec contains all PHIST fields."""
        parser = FormatSpecParser()
        spec = parser.get_spec()

        fields = spec["fields"]
        for field_name in FormatSpecParser.STANDARD_PHIST_FIELDS:
            assert field_name in fields
            assert "position" in fields[field_name]
            assert "column_index" in fields[field_name]


@pytest.mark.unit
class TestFormatSpecParserEdgeCases:
    """Test edge cases and error conditions."""

    def test_parser_field_with_minimal_definition(self, tmp_work_dir: Path) -> None:
        """Test parsing field with minimal definition (no length).

        Args:
            tmp_work_dir: Temporary working directory
        """
        spec_file = tmp_work_dir / "minimal.bcp_fmt"
        spec_file.write_text("parameter_set_id = 1, VARCHAR\n")

        parser = FormatSpecParser(spec_file)
        field = parser.get_field_by_position(1)

        assert field is not None
        assert field["type"] == "VARCHAR"
        assert field["length"] == 255  # Default

    def test_parser_numeric_field_types(self, tmp_work_dir: Path) -> None:
        """Test parsing numeric field types.

        Args:
            tmp_work_dir: Temporary working directory
        """
        spec_file = tmp_work_dir / "numeric.bcp_fmt"
        spec_file.write_text(
            """parameter_set_id = 1, VARCHAR, 20
sequence_number = 7, INT, 4
timestamp = 3, DATETIME, 19
"""
        )

        parser = FormatSpecParser(spec_file)

        seq_field = parser.get_field_by_position(7)
        assert seq_field["type"] == "INT"
        assert seq_field["length"] == 4

        ts_field = parser.get_field_by_position(3)
        assert ts_field["type"] == "DATETIME"

    def test_parser_preserves_field_order(self) -> None:
        """Test that field order is preserved."""
        parser = FormatSpecParser()
        fields = parser.get_fields()

        # Get fields in order by position
        ordered_fields = sorted(fields.items(), key=lambda x: x[1]["position"])

        # First field should be parameter_set_id
        assert ordered_fields[0][0] == "parameter_set_id"

        # Position should increment by 1
        for i, (name, field) in enumerate(ordered_fields):
            assert field["position"] == i + 1

