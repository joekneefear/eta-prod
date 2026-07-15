"""Unit tests for output generators (CSV, JSON, IFF).

Tests generation of normalized output in multiple formats with proper
escaping, hierarchical structure, and workstream compliance.
"""

import csv
import json
import pytest
from pathlib import Path
from tempfile import TemporaryDirectory

from scribe_lot_mapper.generators.csv_generator import CSVGenerator
from scribe_lot_mapper.generators.json_generator import JSONGenerator
from scribe_lot_mapper.generators.iff_generator import IFFGenerator
from scribe_lot_mapper.models import MappingRecord


# ============================================================================
# Test Fixtures
# ============================================================================


@pytest.fixture
def temp_output_dir():
    """Create temporary directory for output files."""
    with TemporaryDirectory() as tmpdir:
        yield tmpdir


@pytest.fixture
def sample_mapping_records() -> list[MappingRecord]:
    """Create sample MappingRecords for testing."""
    return [
        MappingRecord(
            mapping_id="uuid-001",
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            test_program="GMBG3002",
            equipment_id="THK-1-51T",
            facility="FB6",
            timestamp="2026-07-14T03:34:33Z",
            created_at="2026-07-14T10:00:00Z",
            wafer_family="GOXTWS",
            wafer_batch=1125,
            test_value="301.2",
            sequence_number=1,
            site_number=1,
            unit_id="LEFT",
            validation_status="valid",
        ),
        MappingRecord(
            mapping_id="uuid-002",
            scribe_id="THK_1_51_CENTER_2",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            test_program="GMBG3002",
            equipment_id="THK-1-51T",
            facility="FB6",
            timestamp="2026-07-14T03:34:40Z",
            created_at="2026-07-14T10:00:00Z",
            wafer_family="GOXTWS",
            wafer_batch=1125,
            test_value="299.8",
            sequence_number=2,
            site_number=2,
            unit_id="CENTER",
            validation_status="valid",
        ),
        MappingRecord(
            mapping_id="uuid-003",
            scribe_id="THK_1_51_RIGHT_3",
            lot_id="KG42910X1",
            wafer_id="GOXTWS2135",
            test_program="GTGX9A510",
            equipment_id="THK-1-51T",
            facility="FB6",
            timestamp="2026-07-14T03:35:00Z",
            created_at="2026-07-14T10:00:00Z",
            wafer_family="GOXTWS",
            wafer_batch=2135,
            test_value="305.5",
            sequence_number=3,
            site_number=1,
            unit_id="RIGHT",
            validation_status="valid",
        ),
    ]


@pytest.fixture
def sample_mapping_records_with_special_chars() -> list[MappingRecord]:
    """Create MappingRecords with special characters for escaping tests."""
    return [
        MappingRecord(
            mapping_id="uuid-special-001",
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            test_program="TEST,WITH,COMMA",
            equipment_id="THK-1-51T",
            facility="FB6",
            timestamp="2026-07-14T03:34:33Z",
            created_at="2026-07-14T10:00:00Z",
            test_value='301.2"quoted"',
            unit_id="LEFT",
            validation_status="valid",
        ),
        MappingRecord(
            mapping_id="uuid-special-002",
            scribe_id="THK_1_51_CENTER_2",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            test_program="TEST\nWITH\nNEWLINE",
            equipment_id="THK-1-51T",
            facility="FB6",
            timestamp="2026-07-14T03:34:40Z",
            created_at="2026-07-14T10:00:00Z",
            test_value="299.8",
            unit_id="CENTER",
            validation_status="valid",
        ),
    ]


# ============================================================================
# CSV Generator Tests
# ============================================================================


class TestCSVGenerator:
    """Test suite for CSVGenerator."""

    def test_csv_generation_basic(self, temp_output_dir, sample_mapping_records):
        """Test basic CSV file generation."""
        generator = CSVGenerator(temp_output_dir)
        output_file = "test_mappings.csv"

        generator.generate(sample_mapping_records, output_file)

        # Verify file was created
        output_path = Path(temp_output_dir) / output_file
        assert output_path.exists()
        assert output_path.stat().st_size > 0

    def test_csv_headers_present(self, temp_output_dir, sample_mapping_records):
        """Test that CSV headers are written correctly."""
        generator = CSVGenerator(temp_output_dir)
        output_file = "test_mappings.csv"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r") as f:
            reader = csv.DictReader(f)
            # Check headers exist
            assert reader.fieldnames is not None
            assert "mapping_id" in reader.fieldnames
            assert "scribe_id" in reader.fieldnames
            assert "lot_id" in reader.fieldnames
            assert "wafer_id" in reader.fieldnames
            assert "test_program" in reader.fieldnames

    def test_csv_record_count(self, temp_output_dir, sample_mapping_records):
        """Test that all records are written to CSV."""
        generator = CSVGenerator(temp_output_dir)
        output_file = "test_mappings.csv"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            # Should have 3 records (excluding header)
            assert len(rows) == len(sample_mapping_records)

    def test_csv_field_values(self, temp_output_dir, sample_mapping_records):
        """Test that CSV field values are correctly written."""
        generator = CSVGenerator(temp_output_dir)
        output_file = "test_mappings.csv"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            # Check first row
            first_row = rows[0]
            assert first_row["mapping_id"] == "uuid-001"
            assert first_row["scribe_id"] == "THK_1_51_LEFT_1"
            assert first_row["lot_id"] == "KG4BNTCX"
            assert first_row["wafer_id"] == "GOXTWS1125"

    def test_csv_special_characters_escaped(self, temp_output_dir, sample_mapping_records_with_special_chars):
        """Test that special characters are properly escaped in CSV."""
        generator = CSVGenerator(temp_output_dir)
        output_file = "test_special.csv"

        generator.generate(sample_mapping_records_with_special_chars, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            # Check that records with special chars are present and readable
            assert len(rows) == 2
            # Comma-containing field should be properly quoted
            assert "TEST,WITH,COMMA" in rows[0]["test_program"]

    def test_csv_empty_records_list(self, temp_output_dir):
        """Test CSV generation with empty records list."""
        generator = CSVGenerator(temp_output_dir)
        output_file = "test_empty.csv"

        generator.generate([], output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            # Should have headers but no data rows
            assert len(rows) == 0

    def test_csv_default_filename(self, temp_output_dir, sample_mapping_records):
        """Test that default filename is used when not specified."""
        generator = CSVGenerator(temp_output_dir)

        generator.generate(sample_mapping_records)

        output_path = Path(temp_output_dir) / "mappings.csv"
        assert output_path.exists()

    def test_csv_invalid_directory_error(self, sample_mapping_records):
        """Test error handling for invalid output directory."""
        generator = CSVGenerator("/nonexistent/invalid/path")

        # Should raise IOError
        with pytest.raises(IOError):
            generator.generate(sample_mapping_records)


# ============================================================================
# JSON Generator Tests
# ============================================================================


class TestJSONGenerator:
    """Test suite for JSONGenerator."""

    def test_json_generation_basic(self, temp_output_dir, sample_mapping_records):
        """Test basic JSON file generation."""
        generator = JSONGenerator(temp_output_dir)
        output_file = "test_mappings.json"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        assert output_path.exists()
        assert output_path.stat().st_size > 0

    def test_json_structure_valid(self, temp_output_dir, sample_mapping_records):
        """Test that JSON structure is valid and complete."""
        generator = JSONGenerator(temp_output_dir)
        output_file = "test_mappings.json"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r") as f:
            data = json.load(f)

        # Check top-level structure
        assert "metadata" in data
        assert "by_scribe" in data
        assert "mappings" in data

    def test_json_metadata_present(self, temp_output_dir, sample_mapping_records):
        """Test that JSON metadata is correctly populated."""
        generator = JSONGenerator(temp_output_dir)
        output_file = "test_mappings.json"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r") as f:
            data = json.load(f)

        metadata = data["metadata"]
        assert metadata["total_records"] == len(sample_mapping_records)
        assert metadata["unique_scribes"] == 3
        assert metadata["unique_lots"] == 2
        assert metadata["unique_wafers"] == 2

    def test_json_hierarchical_structure(self, temp_output_dir, sample_mapping_records):
        """Test that JSON hierarchy groups by scribe correctly."""
        generator = JSONGenerator(temp_output_dir)
        output_file = "test_mappings.json"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r") as f:
            data = json.load(f)

        by_scribe = data["by_scribe"]
        # Should have 3 scribes
        assert len(by_scribe) == 3
        assert "THK_1_51_LEFT_1" in by_scribe
        assert "THK_1_51_CENTER_2" in by_scribe

    def test_json_mapping_records_present(self, temp_output_dir, sample_mapping_records):
        """Test that flat mappings array contains all records."""
        generator = JSONGenerator(temp_output_dir)
        output_file = "test_mappings.json"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r") as f:
            data = json.load(f)

        mappings = data["mappings"]
        assert len(mappings) == len(sample_mapping_records)
        assert mappings[0]["mapping_id"] == "uuid-001"

    def test_json_scribe_structure(self, temp_output_dir, sample_mapping_records):
        """Test that scribe structure contains proper context."""
        generator = JSONGenerator(temp_output_dir)
        output_file = "test_mappings.json"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r") as f:
            data = json.load(f)

        scribe_info = data["by_scribe"]["THK_1_51_LEFT_1"]
        assert "lots" in scribe_info
        assert len(scribe_info["lots"]) > 0

    def test_json_lot_wafer_relationship(self, temp_output_dir, sample_mapping_records):
        """Test that lot-wafer relationship is correctly represented."""
        generator = JSONGenerator(temp_output_dir)
        output_file = "test_mappings.json"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r") as f:
            data = json.load(f)

        # Check scribe with lot KG4BNTCX
        scribe_info = data["by_scribe"]["THK_1_51_LEFT_1"]
        lot = scribe_info["lots"][0]
        assert lot["lot_id"] == "KG4BNTCX"
        assert "GOXTWS1125" in lot["wafers"]

    def test_json_indent_level(self, temp_output_dir, sample_mapping_records):
        """Test that JSON indentation level is respected."""
        generator = JSONGenerator(temp_output_dir, indent=4)
        output_file = "test_mappings.json"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r") as f:
            content = f.read()

        # Check for 4-space indentation
        assert "    " in content  # 4 spaces should be present

    def test_json_default_filename(self, temp_output_dir, sample_mapping_records):
        """Test that default filename is used when not specified."""
        generator = JSONGenerator(temp_output_dir)

        generator.generate(sample_mapping_records)

        output_path = Path(temp_output_dir) / "mappings.json"
        assert output_path.exists()

    def test_json_empty_records_list(self, temp_output_dir):
        """Test JSON generation with empty records list."""
        generator = JSONGenerator(temp_output_dir)
        output_file = "test_empty.json"

        generator.generate([], output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r") as f:
            data = json.load(f)

        assert data["metadata"]["total_records"] == 0
        assert len(data["mappings"]) == 0

    def test_json_invalid_directory_error(self, sample_mapping_records):
        """Test error handling for invalid output directory."""
        generator = JSONGenerator("/nonexistent/invalid/path")

        with pytest.raises(IOError):
            generator.generate(sample_mapping_records)


# ============================================================================
# IFF Generator Tests
# ============================================================================


class TestIFFGenerator:
    """Test suite for IFFGenerator."""

    def test_iff_generation_basic(self, temp_output_dir, sample_mapping_records):
        """Test basic IFF file generation."""
        generator = IFFGenerator(temp_output_dir)
        output_file = "test_mappings.iff"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        assert output_path.exists()
        assert output_path.stat().st_size > 0

    def test_iff_headers_present(self, temp_output_dir, sample_mapping_records):
        """Test that IFF metadata headers are written."""
        generator = IFFGenerator(temp_output_dir)
        output_file = "test_mappings.iff"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        # First lines should be metadata headers
        assert any("SCRIBE-LOT-WAFER MAPPING OUTPUT" in line for line in lines)
        assert any("FORMAT: IFF" in line for line in lines)

    def test_iff_column_header_row(self, temp_output_dir, sample_mapping_records):
        """Test that IFF column header row is present."""
        generator = IFFGenerator(temp_output_dir)
        output_file = "test_mappings.iff"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Header row should start with #
        assert "#" in content
        # Should contain MAPPING_ID field name
        assert "MAPPING_ID" in content

    def test_iff_vertical_tab_separator(self, temp_output_dir, sample_mapping_records):
        """Test that IFF uses vertical tab as field separator."""
        generator = IFFGenerator(temp_output_dir)
        output_file = "test_mappings.iff"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "rb") as f:
            content = f.read()

        # Check for vertical tab (ASCII 11, 0x0B)
        assert b"\x0B" in content

    def test_iff_record_count_in_header(self, temp_output_dir, sample_mapping_records):
        """Test that record count is written to metadata header."""
        generator = IFFGenerator(temp_output_dir)
        output_file = "test_mappings.iff"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r", encoding="utf-8") as f:
            content = f.read()

        assert f"TOTAL_RECORDS: {len(sample_mapping_records)}" in content

    def test_iff_data_rows_written(self, temp_output_dir, sample_mapping_records):
        """Test that data rows are written correctly."""
        generator = IFFGenerator(temp_output_dir)
        output_file = "test_mappings.iff"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        # Should have metadata headers + column header + data rows
        # At least metadata lines (4) + column header (1) + data rows (3) = 8+
        assert len(lines) >= 8

    def test_iff_field_values_preserved(self, temp_output_dir, sample_mapping_records):
        """Test that field values are correctly written in IFF format."""
        generator = IFFGenerator(temp_output_dir)
        output_file = "test_mappings.iff"

        generator.generate(sample_mapping_records, output_file)

        output_path = Path(temp_output_dir) / output_file
        with open(output_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        # Find first data row (after metadata and column header)
        data_lines = [l for l in lines if not l.startswith("#") and not l.startswith("##")]
        assert len(data_lines) == len(sample_mapping_records)

        # Parse first data row
        first_row = data_lines[0].strip()
        fields = first_row.split(chr(11))
        # Should have correct number of fields
        assert len(fields) == len(IFFGenerator.HEADER_FIELDS)

    def test_iff_default_filename(self, temp_output_dir, sample_mapping_records):
        """Test that default filename is used when not specified."""
        generator = IFFGenerator(temp_output_dir)

        generator.generate(sample_mapping_records)

        output_path = Path(temp_output_dir) / "mappings.iff"
        assert output_path.exists()

    def test_iff_empty_records_list(self, temp_output_dir):
        """Test IFF generation with empty records list."""
        generator = IFFGenerator(temp_output_dir)
        output_file = "test_empty.iff"

        generator.generate([], output_file)

        output_path = Path(temp_output_dir) / output_file
        assert output_path.exists()
        # Should still have headers
        with open(output_path, "r", encoding="utf-8") as f:
            content = f.read()
        assert "TOTAL_RECORDS: 0" in content

    def test_iff_invalid_directory_error(self, sample_mapping_records):
        """Test error handling for invalid output directory."""
        generator = IFFGenerator("/nonexistent/invalid/path")

        with pytest.raises(IOError):
            generator.generate(sample_mapping_records)


# ============================================================================
# Multi-Generator Integration Tests
# ============================================================================


class TestOutputGeneratorsIntegration:
    """Integration tests for multiple output generators."""

    def test_multiple_formats_same_records(self, temp_output_dir, sample_mapping_records):
        """Test generating all three formats from same records."""
        csv_gen = CSVGenerator(temp_output_dir)
        json_gen = JSONGenerator(temp_output_dir)
        iff_gen = IFFGenerator(temp_output_dir)

        csv_gen.generate(sample_mapping_records, "test.csv")
        json_gen.generate(sample_mapping_records, "test.json")
        iff_gen.generate(sample_mapping_records, "test.iff")

        # All files should exist
        assert (Path(temp_output_dir) / "test.csv").exists()
        assert (Path(temp_output_dir) / "test.json").exists()
        assert (Path(temp_output_dir) / "test.iff").exists()

    def test_record_count_consistency(self, temp_output_dir, sample_mapping_records):
        """Test that all formats write same number of records."""
        csv_gen = CSVGenerator(temp_output_dir)
        json_gen = JSONGenerator(temp_output_dir)
        iff_gen = IFFGenerator(temp_output_dir)

        csv_gen.generate(sample_mapping_records, "test.csv")
        json_gen.generate(sample_mapping_records, "test.json")
        iff_gen.generate(sample_mapping_records, "test.iff")

        # Verify record counts
        # CSV
        csv_path = Path(temp_output_dir) / "test.csv"
        with open(csv_path, "r") as f:
            csv_rows = len(list(csv.DictReader(f)))
        assert csv_rows == len(sample_mapping_records)

        # JSON
        json_path = Path(temp_output_dir) / "test.json"
        with open(json_path, "r") as f:
            json_data = json.load(f)
        assert json_data["metadata"]["total_records"] == len(sample_mapping_records)

        # IFF
        iff_path = Path(temp_output_dir) / "test.iff"
        with open(iff_path, "r", encoding="utf-8") as f:
            content = f.read()
        assert f"TOTAL_RECORDS: {len(sample_mapping_records)}" in content
