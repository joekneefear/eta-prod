"""Unit tests for MappingGenerator component.

Tests mapping record generation, bidirectional linkage, ID assignment,
wafer info extraction, and error handling.
"""

import pytest
from datetime import datetime, timezone

from scribe_lot_mapper.exceptions import MappingError
from scribe_lot_mapper.mappers.mapping_generator import MappingGenerator
from scribe_lot_mapper.models import MappingRecord, ParsedRecord


# ============================================================================
# Test Fixtures
# ============================================================================


@pytest.fixture
def mapping_generator_uuid() -> MappingGenerator:
    """Create MappingGenerator with UUID strategy."""
    return MappingGenerator(id_strategy="uuid")


@pytest.fixture
def mapping_generator_sequential() -> MappingGenerator:
    """Create MappingGenerator with sequential strategy."""
    return MappingGenerator(id_strategy="sequential")


@pytest.fixture
def sample_parsed_record() -> ParsedRecord:
    """Create sample ParsedRecord for testing."""
    return ParsedRecord(
        raw_line="test_line_data",
        parameter_set_id="GMBG3002",
        parameter_set_version="1.0",
        date_time="JUL 14 2026 03:34:33",
        facility="FB6",
        parameter_name="TEST_PARAM_1",
        sequence_number=1,
        unit_id="LEFT",
        type_id="THK-1-51T",
        c_values=["301.2"],
        d_values=["301.2"],
        limits_high="350.0",
        limits_low="250.0",
        timestamp="2026-07-14T03:34:33Z",
    )


@pytest.fixture
def sample_parsed_record_empty_unit_id() -> ParsedRecord:
    """Create sample ParsedRecord with empty unit_id."""
    return ParsedRecord(
        raw_line="test_line_data",
        parameter_set_id="GMBG3002",
        parameter_set_version="1.0",
        date_time="JUL 14 2026 03:34:33",
        facility="FB6",
        parameter_name="TEST_PARAM_1",
        sequence_number=1,
        unit_id="",
        type_id="THK-1-51T",
        c_values=["301.2"],
        d_values=["301.2"],
        limits_high="350.0",
        limits_low="250.0",
        timestamp="2026-07-14T03:34:33Z",
    )


@pytest.fixture
def sample_parsed_record_multi_site() -> ParsedRecord:
    """Create sample ParsedRecord with multiple sites."""
    return ParsedRecord(
        raw_line="test_line_data",
        parameter_set_id="GMBG3002",
        parameter_set_version="1.0",
        date_time="JUL 14 2026 03:34:33",
        facility="FB6",
        parameter_name="TEST_PARAM_1",
        sequence_number=1,
        unit_id="",
        type_id="THK-1-51T",
        c_values=["55.1", "4.9", "5.7", "5.7", "5.4"],
        d_values=["55.1", "4.9", "5.7", "5.7", "5.4"],
        limits_high="350.0",
        limits_low="250.0",
        timestamp="2026-07-14T03:34:33Z",
    )


# ============================================================================
# Test Initialization
# ============================================================================


@pytest.mark.unit
class TestMappingGeneratorInit:
    """Test MappingGenerator initialization."""

    def test_init_uuid_strategy(self) -> None:
        """Test initialization with UUID strategy."""
        generator = MappingGenerator(id_strategy="uuid")
        assert generator.id_strategy == "uuid"
        assert generator._sequence_counter == 0

    def test_init_sequential_strategy(self) -> None:
        """Test initialization with sequential strategy."""
        generator = MappingGenerator(id_strategy="sequential")
        assert generator.id_strategy == "sequential"
        assert generator._sequence_counter == 0

    def test_init_default_strategy(self) -> None:
        """Test initialization with default strategy (uuid)."""
        generator = MappingGenerator()
        assert generator.id_strategy == "uuid"

    def test_init_invalid_strategy(self) -> None:
        """Test initialization with invalid strategy raises ValueError."""
        with pytest.raises(ValueError, match="Unknown ID strategy"):
            MappingGenerator(id_strategy="invalid")

    def test_init_wafer_family_cache(self) -> None:
        """Test that wafer family cache is initialized."""
        generator = MappingGenerator()
        assert generator._wafer_family_cache == {}


# ============================================================================
# Test Mapping ID Assignment
# ============================================================================


@pytest.mark.unit
class TestMappingIdAssignment:
    """Test mapping ID generation."""

    def test_assign_uuid_id(self, mapping_generator_uuid: MappingGenerator) -> None:
        """Test UUID ID assignment."""
        id1 = mapping_generator_uuid.assign_mapping_id()
        id2 = mapping_generator_uuid.assign_mapping_id()
        
        assert id1 != id2  # UUIDs should be unique
        assert len(id1) == 36  # UUID v4 format: 8-4-4-4-12
        assert "-" in id1  # UUID contains hyphens

    def test_assign_sequential_id(
        self, mapping_generator_sequential: MappingGenerator
    ) -> None:
        """Test sequential ID assignment."""
        id1 = mapping_generator_sequential.assign_mapping_id()
        id2 = mapping_generator_sequential.assign_mapping_id()
        id3 = mapping_generator_sequential.assign_mapping_id()
        
        assert id1 == "MAP_0000000001"
        assert id2 == "MAP_0000000002"
        assert id3 == "MAP_0000000003"

    def test_sequential_id_ordering(
        self, mapping_generator_sequential: MappingGenerator
    ) -> None:
        """Test that sequential IDs maintain order."""
        ids = [mapping_generator_sequential.assign_mapping_id() for _ in range(5)]
        assert ids == sorted(ids)  # IDs should be in ascending order


# ============================================================================
# Test Mapping Generation
# ============================================================================


@pytest.mark.unit
class TestMappingGeneration:
    """Test mapping record generation."""

    def test_generate_basic_mapping(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test basic mapping generation."""
        mapping = mapping_generator_uuid.generate(
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
            site_number=1,
        )
        
        assert isinstance(mapping, MappingRecord)
        assert mapping.scribe_id == "THK_1_51_LEFT_1"
        assert mapping.lot_id == "KG4BNTCX"
        assert mapping.wafer_id == "GOXTWS1125"
        assert mapping.test_program == "GMBG3002"
        assert mapping.equipment_id == "THK-1-51T"
        assert mapping.facility == "FB6"
        assert mapping.site_number == 1
        assert mapping.validation_status == "valid"
        assert mapping.parent_mapping_id is None

    def test_generate_mapping_with_test_value(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test mapping generation with explicit test value."""
        mapping = mapping_generator_uuid.generate(
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
            test_value="301.2",
        )
        
        assert mapping.test_value == "301.2"

    def test_generate_mapping_with_wafer_info(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test mapping generation with wafer family and batch."""
        mapping = mapping_generator_uuid.generate(
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
            wafer_family="GOXTWS",
            wafer_batch=1125,
        )
        
        assert mapping.wafer_family == "GOXTWS"
        assert mapping.wafer_batch == 1125

    def test_generate_mapping_multi_site(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test mapping generation for multi-site record."""
        mapping = mapping_generator_uuid.generate(
            scribe_id="THK_1_51_SITE_2",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
            site_number=2,
        )
        
        assert mapping.site_number == 2

    def test_generate_mapping_with_parent_id(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test mapping generation for expanded records with parent tracking."""
        parent_id = "MAP_0000000001"
        mapping = mapping_generator_uuid.generate(
            scribe_id="THK_1_51_SITE_2",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
            parent_mapping_id=parent_id,
        )
        
        assert mapping.parent_mapping_id == parent_id
        assert mapping.is_from_multi_site_expansion()

    def test_generate_assigns_unique_id(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test that each generated mapping gets unique ID."""
        mapping1 = mapping_generator_uuid.generate(
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
        )
        
        mapping2 = mapping_generator_uuid.generate(
            scribe_id="THK_1_51_CENTER_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
        )
        
        assert mapping1.mapping_id != mapping2.mapping_id

    def test_generate_includes_created_at_timestamp(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test that generated mapping includes creation timestamp."""
        mapping = mapping_generator_uuid.generate(
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
        )
        
        assert mapping.created_at
        assert "T" in mapping.created_at  # ISO 8601 format
        assert mapping.created_at.endswith("Z")  # UTC timezone

    def test_generate_preserves_unit_id(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test that unit_id from parsed record is preserved."""
        mapping = mapping_generator_uuid.generate(
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
        )
        
        assert mapping.unit_id == "LEFT"

    def test_generate_handles_empty_unit_id(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record_empty_unit_id: ParsedRecord,
    ) -> None:
        """Test that empty unit_id is handled gracefully."""
        mapping = mapping_generator_uuid.generate(
            scribe_id="THK_1_51_SITE_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record_empty_unit_id,
        )
        
        assert mapping.unit_id == ""

    def test_generate_includes_all_required_fields(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test that generated mapping is complete with all required fields."""
        mapping = mapping_generator_uuid.generate(
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
        )
        
        assert mapping.is_complete()
        assert mapping.is_valid_lot_id()
        assert mapping.is_valid_timestamp()


# ============================================================================
# Test Error Handling
# ============================================================================


@pytest.mark.unit
class TestMappingGenerationErrors:
    """Test error handling in mapping generation."""

    def test_generate_empty_scribe_id_raises_error(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test that empty scribe_id raises MappingError."""
        with pytest.raises(MappingError, match="scribe_id cannot be empty"):
            mapping_generator_uuid.generate(
                scribe_id="",
                lot_id="KG4BNTCX",
                wafer_id="GOXTWS1125",
                parsed_record=sample_parsed_record,
            )

    def test_generate_none_scribe_id_raises_error(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test that None scribe_id raises MappingError."""
        with pytest.raises(MappingError, match="scribe_id cannot be empty"):
            mapping_generator_uuid.generate(
                scribe_id=None,
                lot_id="KG4BNTCX",
                wafer_id="GOXTWS1125",
                parsed_record=sample_parsed_record,
            )

    def test_generate_empty_lot_id_raises_error(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test that empty lot_id raises MappingError."""
        with pytest.raises(MappingError, match="lot_id cannot be empty"):
            mapping_generator_uuid.generate(
                scribe_id="THK_1_51_LEFT_1",
                lot_id="",
                wafer_id="GOXTWS1125",
                parsed_record=sample_parsed_record,
            )

    def test_generate_none_lot_id_raises_error(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test that None lot_id raises MappingError."""
        with pytest.raises(MappingError, match="lot_id cannot be empty"):
            mapping_generator_uuid.generate(
                scribe_id="THK_1_51_LEFT_1",
                lot_id=None,
                wafer_id="GOXTWS1125",
                parsed_record=sample_parsed_record,
            )

    def test_generate_empty_wafer_id_raises_error(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test that empty wafer_id raises MappingError."""
        with pytest.raises(MappingError, match="wafer_id cannot be empty"):
            mapping_generator_uuid.generate(
                scribe_id="THK_1_51_LEFT_1",
                lot_id="KG4BNTCX",
                wafer_id="",
                parsed_record=sample_parsed_record,
            )

    def test_generate_none_wafer_id_raises_error(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test that None wafer_id raises MappingError."""
        with pytest.raises(MappingError, match="wafer_id cannot be empty"):
            mapping_generator_uuid.generate(
                scribe_id="THK_1_51_LEFT_1",
                lot_id="KG4BNTCX",
                wafer_id=None,
                parsed_record=sample_parsed_record,
            )

    def test_generate_none_parsed_record_raises_error(
        self,
        mapping_generator_uuid: MappingGenerator,
    ) -> None:
        """Test that None parsed_record raises MappingError."""
        with pytest.raises(MappingError, match="parsed_record cannot be None"):
            mapping_generator_uuid.generate(
                scribe_id="THK_1_51_LEFT_1",
                lot_id="KG4BNTCX",
                wafer_id="GOXTWS1125",
                parsed_record=None,
            )

    def test_generate_invalid_site_number_raises_error(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test that invalid site_number raises MappingError."""
        with pytest.raises(MappingError, match="site_number must be integer between 1-5"):
            mapping_generator_uuid.generate(
                scribe_id="THK_1_51_LEFT_1",
                lot_id="KG4BNTCX",
                wafer_id="GOXTWS1125",
                parsed_record=sample_parsed_record,
                site_number=0,  # Invalid: must be 1-5
            )

        with pytest.raises(MappingError, match="site_number must be integer between 1-5"):
            mapping_generator_uuid.generate(
                scribe_id="THK_1_51_LEFT_1",
                lot_id="KG4BNTCX",
                wafer_id="GOXTWS1125",
                parsed_record=sample_parsed_record,
                site_number=6,  # Invalid: must be 1-5
            )


# ============================================================================
# Test Bidirectional Mapping
# ============================================================================


@pytest.mark.unit
class TestBidirectionalMapping:
    """Test bidirectional mapping creation."""

    def test_create_bidirectional_mapping(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test creating bidirectional mapping."""
        mapping = mapping_generator_uuid.create_bidirectional_mapping(
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
        )
        
        assert isinstance(mapping, MappingRecord)
        assert mapping.scribe_id == "THK_1_51_LEFT_1"
        assert mapping.lot_id == "KG4BNTCX"
        assert mapping.wafer_id == "GOXTWS1125"

    def test_bidirectional_mapping_extracts_test_value(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test that bidirectional mapping extracts test value from c_values."""
        mapping = mapping_generator_uuid.create_bidirectional_mapping(
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
        )
        
        assert mapping.test_value == "301.2"

    def test_bidirectional_mapping_extracts_wafer_info(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test that bidirectional mapping extracts wafer family and batch."""
        mapping = mapping_generator_uuid.create_bidirectional_mapping(
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
        )
        
        assert mapping.wafer_family == "GOXTWS"
        assert mapping.wafer_batch == 1125

    def test_bidirectional_mapping_with_parent_id(
        self,
        mapping_generator_uuid: MappingGenerator,
        sample_parsed_record: ParsedRecord,
    ) -> None:
        """Test bidirectional mapping with parent tracking."""
        parent_id = "MAP_parent_001"
        mapping = mapping_generator_uuid.create_bidirectional_mapping(
            scribe_id="THK_1_51_SITE_2",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            parsed_record=sample_parsed_record,
            parent_mapping_id=parent_id,
        )
        
        assert mapping.parent_mapping_id == parent_id


# ============================================================================
# Test Wafer Info Extraction
# ============================================================================


@pytest.mark.unit
class TestWaferInfoExtraction:
    """Test wafer family and batch extraction."""

    def test_extract_goxtws_wafer_info(
        self, mapping_generator_uuid: MappingGenerator
    ) -> None:
        """Test extraction of GOXTWS wafer info."""
        family, batch = mapping_generator_uuid._extract_wafer_info("GOXTWS1125")
        assert family == "GOXTWS"
        assert batch == 1125

    def test_extract_goxtws_different_batch(
        self, mapping_generator_uuid: MappingGenerator
    ) -> None:
        """Test extraction of different GOXTWS batch."""
        family, batch = mapping_generator_uuid._extract_wafer_info("GOXTWS2135")
        assert family == "GOXTWS"
        assert batch == 2135

    def test_extract_virtual_wafer_info(
        self, mapping_generator_uuid: MappingGenerator
    ) -> None:
        """Test extraction of virtual wafer info."""
        family, batch = mapping_generator_uuid._extract_wafer_info("VW_abc123def456")
        assert family == "VIRTUAL"
        assert batch == 0

    def test_extract_wafer_info_empty_wafer_id(
        self, mapping_generator_uuid: MappingGenerator
    ) -> None:
        """Test extraction with empty wafer_id."""
        family, batch = mapping_generator_uuid._extract_wafer_info("")
        assert family == ""
        assert batch == 0

    def test_extract_wafer_info_caching(
        self, mapping_generator_uuid: MappingGenerator
    ) -> None:
        """Test that wafer info extraction uses caching."""
        wafer_id = "GOXTWS1125"
        
        # First call - should compute and cache
        family1, batch1 = mapping_generator_uuid._extract_wafer_info(wafer_id)
        
        # Second call - should use cache
        family2, batch2 = mapping_generator_uuid._extract_wafer_info(wafer_id)
        
        assert family1 == family2
        assert batch1 == batch2
        assert wafer_id in mapping_generator_uuid._wafer_family_cache


# ============================================================================
# Test Timestamp Generation
# ============================================================================


@pytest.mark.unit
class TestTimestampGeneration:
    """Test ISO 8601 timestamp generation."""

    def test_get_current_iso8601_timestamp(
        self, mapping_generator_uuid: MappingGenerator
    ) -> None:
        """Test ISO 8601 timestamp generation."""
        timestamp = mapping_generator_uuid._get_current_iso8601_timestamp()
        
        assert isinstance(timestamp, str)
        assert "T" in timestamp  # ISO 8601 format includes T separator
        assert timestamp.endswith("Z")  # UTC timezone marker

    def test_iso8601_timestamp_format(
        self, mapping_generator_uuid: MappingGenerator
    ) -> None:
        """Test that timestamp follows correct ISO 8601 format."""
        timestamp = mapping_generator_uuid._get_current_iso8601_timestamp()
        
        # Format should be: YYYY-MM-DDTHH:MM:SSZ
        parts = timestamp.split("T")
        assert len(parts) == 2
        
        date_part = parts[0]
        time_part = parts[1]
        
        # Date: YYYY-MM-DD
        assert len(date_part.split("-")) == 3
        
        # Time: HH:MM:SSZ
        assert time_part.endswith("Z")
