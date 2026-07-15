"""Unit tests for LookupService component.

Tests scribe→lot, lot→scribe lookups, and filtered queries by date range,
facility, and test program.
"""

import pytest
from uuid import uuid4

from scribe_lot_mapper.services.lookup_service import LookupService
from scribe_lot_mapper.models import MappingRecord


# ============================================================================
# Test Fixtures
# ============================================================================


@pytest.fixture
def lookup_service() -> LookupService:
    """Create a fresh LookupService instance."""
    return LookupService()


@pytest.fixture
def sample_mappings() -> list[MappingRecord]:
    """Create sample mapping records for testing."""
    return [
        MappingRecord(
            mapping_id=str(uuid4()),
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            test_program="GMBG3002",
            equipment_id="THK-1-51T",
            facility="FB6",
            timestamp="2026-07-14T03:34:33Z",
            created_at="2026-07-14T04:00:00Z",
            site_number=1,
            unit_id="LEFT",
            test_value="301.2",
        ),
        MappingRecord(
            mapping_id=str(uuid4()),
            scribe_id="THK_1_51_CENTER_2",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            test_program="GMBG3002",
            equipment_id="THK-1-51T",
            facility="FB6",
            timestamp="2026-07-14T03:35:00Z",
            created_at="2026-07-14T04:00:00Z",
            site_number=2,
            unit_id="CENTER",
            test_value="4.9",
        ),
        MappingRecord(
            mapping_id=str(uuid4()),
            scribe_id="THK_1_51_LEFT_1",
            lot_id="KG42910X1",
            wafer_id="GOXTWS1135",
            test_program="GTGX9A510_501",
            equipment_id="THK-1-51T",
            facility="FB6",
            timestamp="2026-07-15T10:00:00Z",
            created_at="2026-07-15T10:30:00Z",
            site_number=1,
            unit_id="LEFT",
            test_value="305.1",
        ),
        MappingRecord(
            mapping_id=str(uuid4()),
            scribe_id="RI_1_11_A6_1",
            lot_id="KG4BNTCX",
            wafer_id="GOXTWS1125",
            test_program="GMBG3002",
            equipment_id="RI-1-11",
            facility="ACI",
            timestamp="2026-07-14T05:00:00Z",
            created_at="2026-07-14T05:30:00Z",
            site_number=1,
            unit_id="A6",
            test_value="250.0",
        ),
    ]


# ============================================================================
# Tests for load_mappings
# ============================================================================


def test_load_mappings_success(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test successful loading of mapping records into indices."""
    lookup_service.load_mappings(sample_mappings)

    stats = lookup_service.get_index_stats()
    assert stats["total_mappings"] == 4
    assert stats["unique_scribes"] == 3  # THK_1_51_LEFT_1, THK_1_51_CENTER_2, RI_1_11_A6_1
    assert stats["unique_lot_wafer_pairs"] == 3  # (KG4BNTCX, GOXTWS1125), (KG42910X1, GOXTWS1135), ...


def test_load_mappings_empty_raises_error(lookup_service: LookupService) -> None:
    """Test that loading empty list raises ValueError."""
    with pytest.raises(ValueError, match="Cannot load empty or None records list"):
        lookup_service.load_mappings([])


def test_load_mappings_clears_previous(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test that loading new mappings clears previous indices."""
    lookup_service.load_mappings(sample_mappings)
    stats1 = lookup_service.get_index_stats()

    # Load just first two mappings
    lookup_service.load_mappings(sample_mappings[:2])
    stats2 = lookup_service.get_index_stats()

    assert stats1["total_mappings"] == 4
    assert stats2["total_mappings"] == 2


def test_load_mappings_skips_incomplete_records(lookup_service: LookupService) -> None:
    """Test that incomplete records are skipped during loading."""
    incomplete_record = MappingRecord(
        mapping_id="",  # Empty mapping_id makes it incomplete
        scribe_id="THK_1_51_LEFT_1",
        lot_id="KG4BNTCX",
        wafer_id="GOXTWS1125",
        test_program="GMBG3002",
        equipment_id="THK-1-51T",
        facility="FB6",
        timestamp="2026-07-14T03:34:33Z",
        created_at="2026-07-14T04:00:00Z",
    )

    lookup_service.load_mappings([incomplete_record])
    stats = lookup_service.get_index_stats()

    assert stats["total_mappings"] == 0


# ============================================================================
# Tests for find_lots_by_scribe (Forward Lookup)
# ============================================================================


def test_find_lots_by_scribe_success(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test finding all lots used by a scribe.

    **Validates: Requirements 8.1** - Returns all lot_ids and wafer_ids for a scribe
    **Validates: Requirements 8.4** - Includes timestamp and test context
    """
    lookup_service.load_mappings(sample_mappings)

    # THK_1_51_LEFT_1 is used in two different lots
    results = lookup_service.find_lots_by_scribe("THK_1_51_LEFT_1")

    assert len(results) == 2
    lot_ids = {result[0] for result in results}
    assert lot_ids == {"KG4BNTCX", "KG42910X1"}

    # Check that context is included
    for lot_id, wafer_id, context in results:
        assert "test_program" in context
        assert "timestamp" in context
        assert "facility" in context


def test_find_lots_by_scribe_not_found(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test that query returns empty list for unknown scribe.

    **Validates: Requirements 8.3** - Returns empty result if scribe not found
    """
    lookup_service.load_mappings(sample_mappings)

    results = lookup_service.find_lots_by_scribe("UNKNOWN_SCRIBE_ID")

    assert results == []


def test_find_lots_by_scribe_empty_id_raises_error(lookup_service: LookupService) -> None:
    """Test that empty scribe_id raises ValueError."""
    with pytest.raises(ValueError, match="scribe_id cannot be empty or None"):
        lookup_service.find_lots_by_scribe("")


def test_find_lots_by_scribe_grouped_by_test_program(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test that results include test_program context for grouping.

    **Validates: Requirements 8.2** - Returns results with test_program for grouping
    """
    lookup_service.load_mappings(sample_mappings)

    results = lookup_service.find_lots_by_scribe("THK_1_51_LEFT_1")

    assert len(results) == 2
    test_programs = {result[2]["test_program"] for result in results}
    assert test_programs == {"GMBG3002", "GTGX9A510_501"}


# ============================================================================
# Tests for find_scribes_by_lot (Reverse Lookup)
# ============================================================================


def test_find_scribes_by_lot_success(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test finding all scribes used in a lot."""
    lookup_service.load_mappings(sample_mappings)

    # Lot KG4BNTCX has scribes: THK_1_51_LEFT_1, THK_1_51_CENTER_2, RI_1_11_A6_1
    results = lookup_service.find_scribes_by_lot("KG4BNTCX")

    assert len(results) == 3
    scribe_ids = {result[0] for result in results}
    assert scribe_ids == {"THK_1_51_LEFT_1", "THK_1_51_CENTER_2", "RI_1_11_A6_1"}


def test_find_scribes_by_lot_with_wafer_filter(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test finding scribes for specific lot+wafer combination."""
    lookup_service.load_mappings(sample_mappings)

    # Lot KG4BNTCX with wafer GOXTWS1125 has: THK_1_51_LEFT_1, THK_1_51_CENTER_2, RI_1_11_A6_1
    results = lookup_service.find_scribes_by_lot("KG4BNTCX", wafer_id="GOXTWS1125")

    assert len(results) == 3
    scribe_ids = {result[0] for result in results}
    assert scribe_ids == {"THK_1_51_LEFT_1", "THK_1_51_CENTER_2", "RI_1_11_A6_1"}


def test_find_scribes_by_lot_not_found(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test that query returns empty list for unknown lot."""
    lookup_service.load_mappings(sample_mappings)

    results = lookup_service.find_scribes_by_lot("UNKNOWN_LOT")

    assert results == []


def test_find_scribes_by_lot_empty_id_raises_error(lookup_service: LookupService) -> None:
    """Test that empty lot_id raises ValueError."""
    with pytest.raises(ValueError, match="lot_id cannot be empty or None"):
        lookup_service.find_scribes_by_lot("")


def test_find_scribes_by_lot_includes_context(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test that results include context information."""
    lookup_service.load_mappings(sample_mappings)

    results = lookup_service.find_scribes_by_lot("KG4BNTCX")

    for scribe_id, context in results:
        assert "test_program" in context
        assert "timestamp" in context
        assert "facility" in context


# ============================================================================
# Tests for query_by_date_range
# ============================================================================


def test_query_by_date_range_all_dates(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test that query without date filters returns all mappings for scribe."""
    lookup_service.load_mappings(sample_mappings)

    results = lookup_service.query_by_date_range("THK_1_51_LEFT_1")

    assert len(results) == 2


def test_query_by_date_range_with_start_date(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test filtering by start date (inclusive)."""
    lookup_service.load_mappings(sample_mappings)

    # THK_1_51_LEFT_1 has timestamps:
    # - 2026-07-14T03:34:33Z
    # - 2026-07-15T10:00:00Z
    # Start from 2026-07-15 should only include second record
    results = lookup_service.query_by_date_range("THK_1_51_LEFT_1", start_date="2026-07-15T00:00:00Z")

    assert len(results) == 1
    assert results[0].timestamp == "2026-07-15T10:00:00Z"


def test_query_by_date_range_with_end_date(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test filtering by end date (inclusive)."""
    lookup_service.load_mappings(sample_mappings)

    results = lookup_service.query_by_date_range("THK_1_51_LEFT_1", end_date="2026-07-14T12:00:00Z")

    assert len(results) == 1
    assert results[0].timestamp == "2026-07-14T03:34:33Z"


def test_query_by_date_range_with_both_dates(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test filtering by both start and end dates."""
    lookup_service.load_mappings(sample_mappings)

    results = lookup_service.query_by_date_range(
        "THK_1_51_LEFT_1",
        start_date="2026-07-14T00:00:00Z",
        end_date="2026-07-14T23:59:59Z"
    )

    assert len(results) == 1
    assert results[0].timestamp == "2026-07-14T03:34:33Z"


def test_query_by_date_range_not_found(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test query returns empty for unknown scribe."""
    lookup_service.load_mappings(sample_mappings)

    results = lookup_service.query_by_date_range("UNKNOWN_SCRIBE")

    assert results == []


def test_query_by_date_range_empty_id_raises_error(lookup_service: LookupService) -> None:
    """Test that empty scribe_id raises ValueError."""
    with pytest.raises(ValueError, match="scribe_id cannot be empty or None"):
        lookup_service.query_by_date_range("")


# ============================================================================
# Tests for query_by_facility
# ============================================================================


def test_query_by_facility_success(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test querying mappings by facility.

    **Validates: Requirements 8.5** - Support filtering by facility
    """
    lookup_service.load_mappings(sample_mappings)

    # Facility FB6 has 3 mappings (THK records + one RI record at ACI)
    results = lookup_service.query_by_facility("FB6")

    assert len(results) == 3
    assert all(record.facility == "FB6" for record in results)


def test_query_by_facility_multiple_facilities(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test that different facilities are indexed separately."""
    lookup_service.load_mappings(sample_mappings)

    fb6_results = lookup_service.query_by_facility("FB6")
    aci_results = lookup_service.query_by_facility("ACI")

    assert len(fb6_results) == 3
    assert len(aci_results) == 1


def test_query_by_facility_not_found(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test that unknown facility returns empty list."""
    lookup_service.load_mappings(sample_mappings)

    results = lookup_service.query_by_facility("UNKNOWN_FACILITY")

    assert results == []


def test_query_by_facility_empty_id_raises_error(lookup_service: LookupService) -> None:
    """Test that empty facility raises ValueError."""
    with pytest.raises(ValueError, match="facility cannot be empty or None"):
        lookup_service.query_by_facility("")


# ============================================================================
# Tests for query_by_test_program
# ============================================================================


def test_query_by_test_program_success(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test querying mappings by test program.

    **Validates: Requirements 8.5** - Support filtering by test program
    """
    lookup_service.load_mappings(sample_mappings)

    # Test program GMBG3002 has 3 mappings
    results = lookup_service.query_by_test_program("GMBG3002")

    assert len(results) == 3
    assert all(record.test_program == "GMBG3002" for record in results)


def test_query_by_test_program_multiple_programs(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test that different test programs are indexed separately."""
    lookup_service.load_mappings(sample_mappings)

    gmbg_results = lookup_service.query_by_test_program("GMBG3002")
    gtgx_results = lookup_service.query_by_test_program("GTGX9A510_501")

    assert len(gmbg_results) == 3
    assert len(gtgx_results) == 1


def test_query_by_test_program_not_found(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test that unknown test program returns empty list."""
    lookup_service.load_mappings(sample_mappings)

    results = lookup_service.query_by_test_program("UNKNOWN_PROGRAM")

    assert results == []


def test_query_by_test_program_empty_id_raises_error(lookup_service: LookupService) -> None:
    """Test that empty test_program raises ValueError."""
    with pytest.raises(ValueError, match="test_program cannot be empty or None"):
        lookup_service.query_by_test_program("")


# ============================================================================
# Tests for get_index_stats
# ============================================================================


def test_get_index_stats_empty_service(lookup_service: LookupService) -> None:
    """Test stats on empty lookup service."""
    stats = lookup_service.get_index_stats()

    assert stats["total_mappings"] == 0
    assert stats["unique_scribes"] == 0
    assert stats["unique_lot_wafer_pairs"] == 0
    assert stats["facilities"] == []
    assert stats["test_programs"] == []


def test_get_index_stats_loaded_data(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test stats with loaded mappings."""
    lookup_service.load_mappings(sample_mappings)

    stats = lookup_service.get_index_stats()

    assert stats["total_mappings"] == 4
    assert stats["unique_scribes"] == 3
    assert stats["unique_lot_wafer_pairs"] == 3
    assert "FB6" in stats["facilities"]
    assert "ACI" in stats["facilities"]
    assert "GMBG3002" in stats["test_programs"]
    assert "GTGX9A510_501" in stats["test_programs"]


# ============================================================================
# Tests for clear_indices
# ============================================================================


def test_clear_indices(lookup_service: LookupService, sample_mappings: list) -> None:
    """Test clearing all indices."""
    lookup_service.load_mappings(sample_mappings)

    stats_before = lookup_service.get_index_stats()
    assert stats_before["total_mappings"] == 4

    lookup_service.clear_indices()

    stats_after = lookup_service.get_index_stats()
    assert stats_after["total_mappings"] == 0


# ============================================================================
# Bidirectionality Tests
# ============================================================================


def test_bidirectionality_forward_then_reverse(
    lookup_service: LookupService, sample_mappings: list
) -> None:
    """Test that forward and reverse lookups are consistent.

    **Validates: Properties 6** - Reverse lookup consistency
    """
    lookup_service.load_mappings(sample_mappings)

    # Forward: Find lots for scribe THK_1_51_LEFT_1
    lots = lookup_service.find_lots_by_scribe("THK_1_51_LEFT_1")
    lot_ids = {lot[0] for lot in lots}

    # For each lot found, reverse lookup should include our scribe
    for lot_id, wafer_id, _ in lots:
        scribes = lookup_service.find_scribes_by_lot(lot_id, wafer_id=wafer_id)
        scribe_ids = {scribe[0] for scribe in scribes}

        assert "THK_1_51_LEFT_1" in scribe_ids


def test_bidirectionality_reverse_then_forward(
    lookup_service: LookupService, sample_mappings: list
) -> None:
    """Test that reverse then forward lookups return consistent results."""
    lookup_service.load_mappings(sample_mappings)

    # Reverse: Find scribes for lot KG4BNTCX
    scribes = lookup_service.find_scribes_by_lot("KG4BNTCX")
    scribe_ids = {scribe[0] for scribe in scribes}

    # Forward: For each scribe, find its lots
    for scribe_id, _ in scribes:
        lots = lookup_service.find_lots_by_scribe(scribe_id)
        lot_ids = {lot[0] for lot in lots}

        # Each scribe should have KG4BNTCX in its lots
        assert "KG4BNTCX" in lot_ids
