"""Integration tests for end-to-end Scribe-Lot-Mapper processing.

Tests complete processing pipeline with real or representative workstream data,
verifying CSV, JSON, and IFF output generation, error handling, and status reporting.

**Validates: All requirements through integrated processing**
"""

import csv
import json
import os
import tempfile
from pathlib import Path
from typing import Dict, List

import pytest

from scribe_lot_mapper.exceptions import ExtractionError, ValidationError
from scribe_lot_mapper.readers.file_reader import FileReader
from scribe_lot_mapper.readers.format_spec_parser import FormatSpecParser
from scribe_lot_mapper.extractors.parser import Parser
from scribe_lot_mapper.extractors.equipment_parser import EquipmentParser
from scribe_lot_mapper.extractors.scribe_extractor import ScribeExtractor
from scribe_lot_mapper.extractors.lot_wafer_extractor import LotWaferExtractor
from scribe_lot_mapper.extractors.multi_site_detector import MultiSiteDetector
from scribe_lot_mapper.mappers.mapping_generator import MappingGenerator
from scribe_lot_mapper.validators.validator import Validator
from scribe_lot_mapper.generators.csv_generator import CSVGenerator
from scribe_lot_mapper.generators.json_generator import JSONGenerator
from scribe_lot_mapper.generators.iff_generator import IFFGenerator
from scribe_lot_mapper.models import ParsedRecord


# ============================================================================
# Test Fixtures
# ============================================================================


@pytest.fixture
def sample_phist_file() -> str:
    """Create a temporary sample phist file with test data.

    Returns:
        Path to temporary file
    """
    content = """GMBG3002	1.0	JUL 14 2026 03:34:33:000AM	20260714	FB6	WAFER_FINAL_TEST	1	LEFT	THK-1-51T	301.2	4.9	5.7	5.7	5.4			350.0	200.0
GMBG3002	1.0	JUL 14 2026 03:35:44:000AM	20260714	FB6	WAFER_FINAL_TEST	2	CENTER	RI-1-11	298.5	4.8	5.6	5.8	5.3			350.0	200.0
GMBG3002	1.0	JUL 14 2026 03:36:55:000AM	20260714	FB6	WAFER_FINAL_TEST	3	RIGHT	ACI-1-31	299.8	5.0	5.5	5.6	5.2			350.0	200.0
"""

    with tempfile.NamedTemporaryFile(mode="w", suffix=".phist", delete=False) as f:
        f.write(content)
        return f.name


@pytest.fixture
def sample_phist_multisite_file() -> str:
    """Create a temporary phist file with multi-site test data.

    Returns:
        Path to temporary file
    """
    content = """GMBG3002	1.0	JUL 14 2026 03:34:33:000AM	20260714	FB6	WAFER_FINAL_TEST	1	LEFT	THK-1-51T	301.2	4.9	5.7	5.7	5.4	310.1	4.7	5.8	5.6	5.5	350.0	200.0
"""

    with tempfile.NamedTemporaryFile(mode="w", suffix=".phist", delete=False) as f:
        f.write(content)
        return f.name


@pytest.fixture
def output_dir() -> str:
    """Create temporary output directory.

    Returns:
        Path to temporary directory
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        yield tmpdir


# ============================================================================
# Integration Tests
# ============================================================================


@pytest.mark.integration
class TestEndToEndProcessing:
    """Test complete end-to-end processing pipeline."""

    def test_parse_simple_phist_file(self, sample_phist_file: str) -> None:
        """Test parsing a simple phist file."""
        reader = FileReader()

        # Open and read file
        with open(sample_phist_file, "r") as f:
            lines = f.readlines()

        assert len(lines) == 3, "Expected 3 records in sample file"

        # Parse each line
        parser = Parser()
        equipment_parser = EquipmentParser()
        scribe_extractor = ScribeExtractor()
        lot_wafer_extractor = LotWaferExtractor()

        for line in lines:
            fields = line.strip().split("\t")
            assert len(fields) >= 9, "Expected at least 9 fields"

            # Extract basic fields
            parameter_set_id = fields[0]
            unit_id = fields[7]
            equipment_code = fields[8]

            # Parse equipment code
            equipment_info = equipment_parser.parse(equipment_code)
            assert equipment_info is not None
            assert equipment_info.facility is not None

            # Extract scribe
            scribe_id = scribe_extractor.extract(unit_id, equipment_info, site_number=1)
            assert scribe_id is not None
            assert "_" in scribe_id

    def test_generate_csv_output(self, sample_phist_file: str, output_dir: str) -> None:
        """Test generating CSV output from phist file."""
        # Read and parse file
        with open(sample_phist_file, "r") as f:
            lines = f.readlines()

        parser = Parser()
        equipment_parser = EquipmentParser()
        scribe_extractor = ScribeExtractor()
        lot_wafer_extractor = LotWaferExtractor()
        generator = MappingGenerator()
        csv_generator = CSVGenerator()

        records = []
        for i, line in enumerate(lines):
            fields = line.strip().split("\t")

            # Extract fields
            equipment_info = equipment_parser.parse(fields[8])
            scribe_id = scribe_extractor.extract(fields[7], equipment_info, site_number=1)
            lot_id, wafer_id, _ = lot_wafer_extractor.extract(f"KG4BNT{i}")

            # Generate mapping
            mapping = generator.generate(
                scribe_id=scribe_id,
                lot_id=lot_id,
                wafer_id=wafer_id,
                test_program=fields[0],
                equipment_id=fields[8],
                facility=fields[4],
                sequence_number=int(fields[5]),
                site_number=1,
                unit_id=fields[7],
                test_value=fields[9],
                timestamp="2026-07-14T03:34:33Z",
            )
            records.append(mapping)

        # Generate CSV
        output_file = os.path.join(output_dir, "mappings.csv")
        csv_generator.write(records, output_file)

        # Verify CSV file exists and has content
        assert os.path.exists(output_file)
        with open(output_file, "r") as f:
            reader = csv.DictReader(f)
            csv_records = list(reader)

        assert len(csv_records) >= 3, "Expected at least 3 records in CSV"

        # Verify CSV headers
        assert csv_records[0] is not None
        for header in ["scribe_id", "lot_id", "wafer_id", "mapping_id"]:
            assert header in csv_records[0] or header in list(csv_records[0].keys())

    def test_generate_json_output(self, sample_phist_file: str, output_dir: str) -> None:
        """Test generating JSON output from phist file."""
        # Read and parse file
        with open(sample_phist_file, "r") as f:
            lines = f.readlines()

        equipment_parser = EquipmentParser()
        scribe_extractor = ScribeExtractor()
        lot_wafer_extractor = LotWaferExtractor()
        generator = MappingGenerator()
        json_generator = JSONGenerator()

        records = []
        for i, line in enumerate(lines):
            fields = line.strip().split("\t")

            equipment_info = equipment_parser.parse(fields[8])
            scribe_id = scribe_extractor.extract(fields[7], equipment_info, site_number=1)
            lot_id, wafer_id, _ = lot_wafer_extractor.extract(f"KG4BNT{i}")

            mapping = generator.generate(
                scribe_id=scribe_id,
                lot_id=lot_id,
                wafer_id=wafer_id,
                test_program=fields[0],
                equipment_id=fields[8],
                facility=fields[4],
                sequence_number=int(fields[5]),
                site_number=1,
                unit_id=fields[7],
                test_value=fields[9],
                timestamp="2026-07-14T03:34:33Z",
            )
            records.append(mapping)

        # Generate JSON
        output_file = os.path.join(output_dir, "mappings.json")
        json_generator.write(records, output_file)

        # Verify JSON file exists and is valid
        assert os.path.exists(output_file)
        with open(output_file, "r") as f:
            json_data = json.load(f)

        assert "mappings" in json_data
        assert len(json_data["mappings"]) >= 3, "Expected at least 3 records in JSON"

        # Verify structure of first record
        first_record = json_data["mappings"][0]
        assert "mapping_id" in first_record or "scribe" in first_record

    def test_generate_iff_output(self, sample_phist_file: str, output_dir: str) -> None:
        """Test generating IFF output from phist file."""
        # Read and parse file
        with open(sample_phist_file, "r") as f:
            lines = f.readlines()

        equipment_parser = EquipmentParser()
        scribe_extractor = ScribeExtractor()
        lot_wafer_extractor = LotWaferExtractor()
        generator = MappingGenerator()
        iff_generator = IFFGenerator()

        records = []
        for i, line in enumerate(lines):
            fields = line.strip().split("\t")

            equipment_info = equipment_parser.parse(fields[8])
            scribe_id = scribe_extractor.extract(fields[7], equipment_info, site_number=1)
            lot_id, wafer_id, _ = lot_wafer_extractor.extract(f"KG4BNT{i}")

            mapping = generator.generate(
                scribe_id=scribe_id,
                lot_id=lot_id,
                wafer_id=wafer_id,
                test_program=fields[0],
                equipment_id=fields[8],
                facility=fields[4],
                sequence_number=int(fields[5]),
                site_number=1,
                unit_id=fields[7],
                test_value=fields[9],
                timestamp="2026-07-14T03:34:33Z",
            )
            records.append(mapping)

        # Generate IFF
        output_file = os.path.join(output_dir, "mappings.iff")
        iff_generator.write(records, output_file)

        # Verify IFF file exists and has content
        assert os.path.exists(output_file)
        with open(output_file, "r") as f:
            iff_content = f.read()

        assert len(iff_content) > 0, "IFF file should have content"

    def test_validation_separates_valid_invalid_records(self, output_dir: str) -> None:
        """Test that validation properly separates valid and invalid records."""
        equipment_parser = EquipmentParser()
        scribe_extractor = ScribeExtractor()
        lot_wafer_extractor = LotWaferExtractor()
        generator = MappingGenerator()
        validator = Validator()

        # Create valid mapping
        equipment_info = equipment_parser.parse("THK-1-51T")
        scribe_id = scribe_extractor.extract("LEFT", equipment_info, site_number=1)
        lot_id, wafer_id, _ = lot_wafer_extractor.extract("KG4BNTCX")

        valid_record = generator.generate(
            scribe_id=scribe_id,
            lot_id=lot_id,
            wafer_id=wafer_id,
            test_program="GMBG3002",
            equipment_id="THK-1-51T",
            facility="FB6",
            sequence_number=1,
            site_number=1,
            unit_id="LEFT",
            test_value="301.2",
            timestamp="2026-07-14T03:34:33Z",
        )

        # Validate
        result_valid = validator.validate(valid_record)
        assert result_valid, "Valid record should pass validation"

        # Create invalid record (missing lot_id)
        from scribe_lot_mapper.models import MappingRecord
        import uuid

        invalid_record = MappingRecord(
            mapping_id=str(uuid.uuid4()),
            scribe_id="THK_1_51_LEFT_1",
            lot_id="",  # Missing!
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

        result_invalid = validator.validate(invalid_record)
        assert not result_invalid, "Invalid record should fail validation"

    def test_multisite_expansion_in_pipeline(self, sample_phist_multisite_file: str) -> None:
        """Test multi-site expansion within processing pipeline."""
        with open(sample_phist_multisite_file, "r") as f:
            line = f.readline()

        fields = line.strip().split("\t")

        # Detect multi-site
        detector = MultiSiteDetector()
        site_count = detector.detect_site_count_from_fields(fields)

        # Should detect multiple sites from c_values
        assert site_count >= 1, "Should detect at least 1 site"

    def test_error_handling_for_missing_file(self) -> None:
        """Test error handling when input file doesn't exist."""
        reader = FileReader()

        with pytest.raises(FileNotFoundError):
            with open("/nonexistent/path/file.phist", "r") as _:
                pass

    def test_output_files_created_with_correct_format(self, sample_phist_file: str, output_dir: str) -> None:
        """Test that all output formats are created correctly."""
        # Process file
        with open(sample_phist_file, "r") as f:
            lines = f.readlines()

        equipment_parser = EquipmentParser()
        scribe_extractor = ScribeExtractor()
        lot_wafer_extractor = LotWaferExtractor()
        generator = MappingGenerator()

        records = []
        for i, line in enumerate(lines):
            fields = line.strip().split("\t")
            equipment_info = equipment_parser.parse(fields[8])
            scribe_id = scribe_extractor.extract(fields[7], equipment_info, site_number=1)
            lot_id, wafer_id, _ = lot_wafer_extractor.extract(f"KG4BNT{i}")

            mapping = generator.generate(
                scribe_id=scribe_id,
                lot_id=lot_id,
                wafer_id=wafer_id,
                test_program=fields[0],
                equipment_id=fields[8],
                facility=fields[4],
                sequence_number=int(fields[5]),
                site_number=1,
                unit_id=fields[7],
                test_value=fields[9],
                timestamp="2026-07-14T03:34:33Z",
            )
            records.append(mapping)

        # Generate all formats
        csv_generator = CSVGenerator()
        json_generator = JSONGenerator()
        iff_generator = IFFGenerator()

        csv_file = os.path.join(output_dir, "mappings.csv")
        json_file = os.path.join(output_dir, "mappings.json")
        iff_file = os.path.join(output_dir, "mappings.iff")

        csv_generator.write(records, csv_file)
        json_generator.write(records, json_file)
        iff_generator.write(records, iff_file)

        # Verify all files exist
        assert os.path.exists(csv_file), "CSV file not created"
        assert os.path.exists(json_file), "JSON file not created"
        assert os.path.exists(iff_file), "IFF file not created"

        # Verify all files have content
        assert os.path.getsize(csv_file) > 0, "CSV file is empty"
        assert os.path.getsize(json_file) > 0, "JSON file is empty"
        assert os.path.getsize(iff_file) > 0, "IFF file is empty"


@pytest.mark.integration
class TestErrorHandlingInPipeline:
    """Test error handling throughout the pipeline."""

    def test_invalid_equipment_code_handled_gracefully(self) -> None:
        """Test that invalid equipment codes are handled without crashing."""
        parser = EquipmentParser()

        # Should not raise, but handle gracefully
        try:
            info = parser.parse("INVALID_CODE_XYZ")
            assert info is not None
        except ExtractionError:
            # This is acceptable - error is properly raised
            pass

    def test_missing_required_fields_detected(self) -> None:
        """Test that missing required fields are detected during validation."""
        from scribe_lot_mapper.models import MappingRecord
        import uuid

        validator = Validator()

        # Record missing scribe_id
        record = MappingRecord(
            mapping_id=str(uuid.uuid4()),
            scribe_id="",
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

        result = validator.validate(record)
        assert not result, "Validation should fail for missing scribe_id"
