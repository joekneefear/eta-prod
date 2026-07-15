"""Unit tests for MultiSiteDetector component.

Tests multi-site detection, record expansion, site value extraction, and
handling of edge cases.
"""

import pytest

from scribe_lot_mapper.extractors.multi_site_detector import MultiSiteDetector
from scribe_lot_mapper.models import ParsedRecord


# ============================================================================
# Test Fixtures
# ============================================================================


@pytest.fixture
def multi_site_detector() -> MultiSiteDetector:
    """Create default MultiSiteDetector instance."""
    return MultiSiteDetector()


@pytest.fixture
def single_site_record() -> ParsedRecord:
    """Create single-site record (1 measurement)."""
    return ParsedRecord(
        raw_line="test_line_1",
        parameter_set_id="GMBG3002",
        parameter_set_version="v1",
        date_time="JUL 14 2026 03:00:16:000AM",
        facility="FB6",
        parameter_name="TEST_PARAM",
        sequence_number=1,
        unit_id="LEFT",
        type_id="THK-1-51T",
        c_values=["301.2"],
        d_values=["301.2"],
        limits_high="350",
        limits_low="250",
        timestamp="2026-07-14T03:00:16Z",
    )


@pytest.fixture
def two_site_record() -> ParsedRecord:
    """Create two-site record (2 measurements)."""
    return ParsedRecord(
        raw_line="test_line_2",
        parameter_set_id="GMBG3002",
        parameter_set_version="v1",
        date_time="JUL 14 2026 03:00:16:000AM",
        facility="FB6",
        parameter_name="TEST_PARAM",
        sequence_number=1,
        unit_id="",
        type_id="THK-1-51T",
        c_values=["55.1", "4.9"],
        d_values=["55.1", "4.9"],
        limits_high="100",
        limits_low="0",
        timestamp="2026-07-14T03:00:16Z",
    )


@pytest.fixture
def five_site_record() -> ParsedRecord:
    """Create five-site record (5 measurements)."""
    return ParsedRecord(
        raw_line="test_line_5",
        parameter_set_id="GMBG3002",
        parameter_set_version="v1",
        date_time="JUL 14 2026 03:00:16:000AM",
        facility="FB6",
        parameter_name="TEST_PARAM",
        sequence_number=1,
        unit_id="",
        type_id="THK-1-51T",
        c_values=["55.1", "4.9", "5.7", "5.7", "5.4"],
        d_values=["55.1", "4.9", "5.7", "5.7", "5.4"],
        limits_high="100",
        limits_low="0",
        timestamp="2026-07-14T03:00:16Z",
    )


@pytest.fixture
def record_with_empty_values() -> ParsedRecord:
    """Create record with some empty measurement values."""
    return ParsedRecord(
        raw_line="test_line_partial",
        parameter_set_id="GMBG3002",
        parameter_set_version="v1",
        date_time="JUL 14 2026 03:00:16:000AM",
        facility="FB6",
        parameter_name="TEST_PARAM",
        sequence_number=1,
        unit_id="",
        type_id="THK-1-51T",
        c_values=["55.1", "4.9", "", "", "5.4"],
        d_values=["55.1", "4.9", "", "", "5.4"],
        limits_high="100",
        limits_low="0",
        timestamp="2026-07-14T03:00:16Z",
    )


@pytest.fixture
def record_with_whitespace_values() -> ParsedRecord:
    """Create record with whitespace-only values."""
    return ParsedRecord(
        raw_line="test_line_whitespace",
        parameter_set_id="GMBG3002",
        parameter_set_version="v1",
        date_time="JUL 14 2026 03:00:16:000AM",
        facility="FB6",
        parameter_name="TEST_PARAM",
        sequence_number=1,
        unit_id="",
        type_id="THK-1-51T",
        c_values=["55.1", "   ", "5.7"],
        d_values=["55.1", "   ", "5.7"],
        limits_high="100",
        limits_low="0",
        timestamp="2026-07-14T03:00:16Z",
    )


# ============================================================================
# Test Detection
# ============================================================================


@pytest.mark.unit
class TestMultiSiteDetection:
    """Test site detection logic."""

    def test_detect_single_site(
        self, multi_site_detector: MultiSiteDetector, single_site_record: ParsedRecord
    ) -> None:
        """Test detection of single-site record."""
        count = multi_site_detector.detect(single_site_record)
        assert count == 1

    def test_detect_two_sites(
        self, multi_site_detector: MultiSiteDetector, two_site_record: ParsedRecord
    ) -> None:
        """Test detection of two-site record."""
        count = multi_site_detector.detect(two_site_record)
        assert count == 2

    def test_detect_five_sites(
        self, multi_site_detector: MultiSiteDetector, five_site_record: ParsedRecord
    ) -> None:
        """Test detection of five-site record."""
        count = multi_site_detector.detect(five_site_record)
        assert count == 5

    def test_detect_with_empty_values(
        self,
        multi_site_detector: MultiSiteDetector,
        record_with_empty_values: ParsedRecord,
    ) -> None:
        """Test detection correctly ignores empty values."""
        # Record has c_values=["55.1", "4.9", "", "", "5.4"]
        # Non-empty count = 3 (55.1, 4.9, 5.4)
        count = multi_site_detector.detect(record_with_empty_values)
        assert count == 3

    def test_detect_with_whitespace_values(
        self,
        multi_site_detector: MultiSiteDetector,
        record_with_whitespace_values: ParsedRecord,
    ) -> None:
        """Test detection treats whitespace-only values as empty."""
        # Record has c_values=["55.1", "   ", "5.7"]
        # Whitespace-only is treated as empty, so non-empty count = 2
        count = multi_site_detector.detect(record_with_whitespace_values)
        assert count == 2

    def test_detect_none_record(self, multi_site_detector: MultiSiteDetector) -> None:
        """Test detection with None record returns minimum count."""
        count = multi_site_detector.detect(None)
        assert count == 1

    def test_detect_empty_arrays(self, multi_site_detector: MultiSiteDetector) -> None:
        """Test detection with empty value arrays."""
        record = ParsedRecord(
            raw_line="test",
            parameter_set_id="TEST",
            parameter_set_version="v1",
            date_time="JUL 14 2026",
            facility="FB6",
            parameter_name="PARAM",
            sequence_number=1,
            unit_id="",
            type_id="THK-1-51T",
            c_values=[],
            d_values=[],
            timestamp="2026-07-14T03:00:00Z",
        )
        count = multi_site_detector.detect(record)
        assert count == 1


# ============================================================================
# Test is_multi_site
# ============================================================================


@pytest.mark.unit
class TestIsMultiSite:
    """Test multi-site flag checking."""

    def test_is_multi_site_false_for_single_site(
        self, multi_site_detector: MultiSiteDetector, single_site_record: ParsedRecord
    ) -> None:
        """Test single-site record returns False."""
        is_multi = multi_site_detector.is_multi_site(single_site_record)
        assert is_multi is False

    def test_is_multi_site_true_for_two_sites(
        self, multi_site_detector: MultiSiteDetector, two_site_record: ParsedRecord
    ) -> None:
        """Test two-site record returns True."""
        is_multi = multi_site_detector.is_multi_site(two_site_record)
        assert is_multi is True

    def test_is_multi_site_true_for_five_sites(
        self, multi_site_detector: MultiSiteDetector, five_site_record: ParsedRecord
    ) -> None:
        """Test five-site record returns True."""
        is_multi = multi_site_detector.is_multi_site(five_site_record)
        assert is_multi is True

    def test_is_multi_site_false_for_none(
        self, multi_site_detector: MultiSiteDetector
    ) -> None:
        """Test None record returns False."""
        is_multi = multi_site_detector.is_multi_site(None)
        assert is_multi is False


# ============================================================================
# Test Site Value Extraction
# ============================================================================


@pytest.mark.unit
class TestExtractSiteValues:
    """Test site value extraction."""

    def test_extract_site_zero(
        self, multi_site_detector: MultiSiteDetector, five_site_record: ParsedRecord
    ) -> None:
        """Test extraction of first site (index 0)."""
        values = multi_site_detector.extract_site_values(five_site_record, 0)

        assert values["c_value"] == "55.1"
        assert values["d_value"] == "55.1"
        assert values["site_index"] == 0

    def test_extract_site_one(
        self, multi_site_detector: MultiSiteDetector, five_site_record: ParsedRecord
    ) -> None:
        """Test extraction of second site (index 1)."""
        values = multi_site_detector.extract_site_values(five_site_record, 1)

        assert values["c_value"] == "4.9"
        assert values["d_value"] == "4.9"
        assert values["site_index"] == 1

    def test_extract_site_middle(
        self, multi_site_detector: MultiSiteDetector, five_site_record: ParsedRecord
    ) -> None:
        """Test extraction of middle site (index 2)."""
        values = multi_site_detector.extract_site_values(five_site_record, 2)

        assert values["c_value"] == "5.7"
        assert values["d_value"] == "5.7"
        assert values["site_index"] == 2

    def test_extract_site_last(
        self, multi_site_detector: MultiSiteDetector, five_site_record: ParsedRecord
    ) -> None:
        """Test extraction of last site (index 4)."""
        values = multi_site_detector.extract_site_values(five_site_record, 4)

        assert values["c_value"] == "5.4"
        assert values["d_value"] == "5.4"
        assert values["site_index"] == 4

    def test_extract_site_out_of_bounds(
        self, multi_site_detector: MultiSiteDetector, five_site_record: ParsedRecord
    ) -> None:
        """Test extraction with out-of-bounds index returns empty values."""
        values = multi_site_detector.extract_site_values(five_site_record, 10)

        assert values["c_value"] == ""
        assert values["d_value"] == ""
        assert values["site_index"] == 10

    def test_extract_site_with_partial_arrays(
        self,
        multi_site_detector: MultiSiteDetector,
        record_with_empty_values: ParsedRecord,
    ) -> None:
        """Test extraction with partial value arrays."""
        # c_values=["55.1", "4.9", "", "", "5.4"]
        values = multi_site_detector.extract_site_values(record_with_empty_values, 2)
        assert values["c_value"] == ""
        assert values["d_value"] == ""

    def test_extract_site_mismatched_array_lengths(
        self, multi_site_detector: MultiSiteDetector
    ) -> None:
        """Test extraction with different c_values and d_values lengths."""
        record = ParsedRecord(
            raw_line="test",
            parameter_set_id="TEST",
            parameter_set_version="v1",
            date_time="JUL 14 2026",
            facility="FB6",
            parameter_name="PARAM",
            sequence_number=1,
            unit_id="",
            type_id="THK-1-51T",
            c_values=["55.1", "4.9"],  # 2 values
            d_values=["55.1", "4.9", "5.7"],  # 3 values
            timestamp="2026-07-14T03:00:00Z",
        )

        # Should handle gracefully
        values = multi_site_detector.extract_site_values(record, 2)
        assert values["c_value"] == ""  # Out of bounds for c_values
        assert values["d_value"] == "5.7"  # Within bounds for d_values


# ============================================================================
# Test Record Expansion
# ============================================================================


@pytest.mark.unit
class TestRecordExpansion:
    """Test record expansion logic."""

    def test_expand_single_site_returns_original(
        self, multi_site_detector: MultiSiteDetector, single_site_record: ParsedRecord
    ) -> None:
        """Test single-site record expansion returns original unchanged."""
        expanded = multi_site_detector.expand(single_site_record)

        assert len(expanded) == 1
        assert expanded[0] is single_site_record

    def test_expand_two_sites(
        self, multi_site_detector: MultiSiteDetector, two_site_record: ParsedRecord
    ) -> None:
        """Test two-site record expansion creates 2 records."""
        expanded = multi_site_detector.expand(two_site_record)

        assert len(expanded) == 2
        assert expanded[0].c_values == ["55.1"]
        assert expanded[0].d_values == ["55.1"]
        assert expanded[1].c_values == ["4.9"]
        assert expanded[1].d_values == ["4.9"]

    def test_expand_five_sites(
        self, multi_site_detector: MultiSiteDetector, five_site_record: ParsedRecord
    ) -> None:
        """Test five-site record expansion creates 5 records."""
        expanded = multi_site_detector.expand(five_site_record)

        assert len(expanded) == 5
        assert expanded[0].c_values == ["55.1"]
        assert expanded[1].c_values == ["4.9"]
        assert expanded[2].c_values == ["5.7"]
        assert expanded[3].c_values == ["5.7"]
        assert expanded[4].c_values == ["5.4"]

    def test_expand_none_record(
        self, multi_site_detector: MultiSiteDetector
    ) -> None:
        """Test expansion of None record returns empty list."""
        expanded = multi_site_detector.expand(None)
        assert expanded == []

    def test_expand_preserves_context(
        self, multi_site_detector: MultiSiteDetector, two_site_record: ParsedRecord
    ) -> None:
        """Test expansion preserves non-site-specific fields."""
        expanded = multi_site_detector.expand(two_site_record)

        # Check first expanded record
        assert expanded[0].raw_line == two_site_record.raw_line
        assert expanded[0].parameter_set_id == two_site_record.parameter_set_id
        assert expanded[0].facility == two_site_record.facility
        assert expanded[0].unit_id == two_site_record.unit_id
        assert expanded[0].type_id == two_site_record.type_id
        assert expanded[0].limits_high == two_site_record.limits_high
        assert expanded[0].limits_low == two_site_record.limits_low
        assert expanded[0].timestamp == two_site_record.timestamp

        # Check second expanded record
        assert expanded[1].raw_line == two_site_record.raw_line
        assert expanded[1].parameter_set_id == two_site_record.parameter_set_id

    def test_expand_with_partial_sites(
        self,
        multi_site_detector: MultiSiteDetector,
        record_with_empty_values: ParsedRecord,
    ) -> None:
        """Test expansion with partial sites (some empty values)."""
        # Record has c_values=["55.1", "4.9", "", "", "5.4"]
        # Should detect 3 sites (non-empty count)
        expanded = multi_site_detector.expand(record_with_empty_values)

        assert len(expanded) == 3
        assert expanded[0].c_values == ["55.1"]
        assert expanded[1].c_values == ["4.9"]
        assert expanded[2].c_values == ["5.4"]

    def test_expand_creates_new_records(
        self, multi_site_detector: MultiSiteDetector, two_site_record: ParsedRecord
    ) -> None:
        """Test expansion creates new ParsedRecord instances."""
        expanded = multi_site_detector.expand(two_site_record)

        assert expanded[0] is not two_site_record
        assert expanded[1] is not two_site_record
        assert expanded[0] is not expanded[1]

    def test_expand_preserves_immutability(
        self, multi_site_detector: MultiSiteDetector, two_site_record: ParsedRecord
    ) -> None:
        """Test that original record is not modified during expansion."""
        original_c_values = list(two_site_record.c_values)
        original_d_values = list(two_site_record.d_values)

        multi_site_detector.expand(two_site_record)

        assert two_site_record.c_values == original_c_values
        assert two_site_record.d_values == original_d_values


# ============================================================================
# Test Edge Cases
# ============================================================================


@pytest.mark.unit
class TestEdgeCases:
    """Test edge cases and error conditions."""

    def test_record_with_all_empty_values(
        self, multi_site_detector: MultiSiteDetector
    ) -> None:
        """Test record with all empty c_values and d_values."""
        record = ParsedRecord(
            raw_line="test",
            parameter_set_id="TEST",
            parameter_set_version="v1",
            date_time="JUL 14 2026",
            facility="FB6",
            parameter_name="PARAM",
            sequence_number=1,
            unit_id="",
            type_id="THK-1-51T",
            c_values=["", "", ""],
            d_values=["", "", ""],
            timestamp="2026-07-14T03:00:00Z",
        )

        count = multi_site_detector.detect(record)
        assert count == 1

        expanded = multi_site_detector.expand(record)
        assert len(expanded) == 1

    def test_single_empty_value(
        self, multi_site_detector: MultiSiteDetector
    ) -> None:
        """Test detection with single empty value."""
        record = ParsedRecord(
            raw_line="test",
            parameter_set_id="TEST",
            parameter_set_version="v1",
            date_time="JUL 14 2026",
            facility="FB6",
            parameter_name="PARAM",
            sequence_number=1,
            unit_id="",
            type_id="THK-1-51T",
            c_values=[""],
            d_values=[""],
            timestamp="2026-07-14T03:00:00Z",
        )

        count = multi_site_detector.detect(record)
        assert count == 1

    def test_d_values_only(
        self, multi_site_detector: MultiSiteDetector
    ) -> None:
        """Test record with only d_values, no c_values."""
        record = ParsedRecord(
            raw_line="test",
            parameter_set_id="TEST",
            parameter_set_version="v1",
            date_time="JUL 14 2026",
            facility="FB6",
            parameter_name="PARAM",
            sequence_number=1,
            unit_id="",
            type_id="THK-1-51T",
            c_values=[],
            d_values=["55.1", "4.9", "5.7"],
            timestamp="2026-07-14T03:00:00Z",
        )

        count = multi_site_detector.detect(record)
        assert count == 3

        expanded = multi_site_detector.expand(record)
        assert len(expanded) == 3

    def test_c_values_only(
        self, multi_site_detector: MultiSiteDetector
    ) -> None:
        """Test record with only c_values, no d_values."""
        record = ParsedRecord(
            raw_line="test",
            parameter_set_id="TEST",
            parameter_set_version="v1",
            date_time="JUL 14 2026",
            facility="FB6",
            parameter_name="PARAM",
            sequence_number=1,
            unit_id="",
            type_id="THK-1-51T",
            c_values=["55.1", "4.9"],
            d_values=[],
            timestamp="2026-07-14T03:00:00Z",
        )

        count = multi_site_detector.detect(record)
        assert count == 2

        expanded = multi_site_detector.expand(record)
        assert len(expanded) == 2

    def test_mixed_empty_and_whitespace(
        self, multi_site_detector: MultiSiteDetector
    ) -> None:
        """Test record with mix of empty strings and whitespace."""
        record = ParsedRecord(
            raw_line="test",
            parameter_set_id="TEST",
            parameter_set_version="v1",
            date_time="JUL 14 2026",
            facility="FB6",
            parameter_name="PARAM",
            sequence_number=1,
            unit_id="",
            type_id="THK-1-51T",
            c_values=["55.1", "", "   ", "4.9"],
            d_values=["55.1", "", "   ", "4.9"],
            timestamp="2026-07-14T03:00:00Z",
        )

        count = multi_site_detector.detect(record)
        assert count == 2  # Only 55.1 and 4.9 are non-empty

        expanded = multi_site_detector.expand(record)
        assert len(expanded) == 2


# ============================================================================
# Test Integration
# ============================================================================


@pytest.mark.unit
class TestIntegration:
    """Test integrated behavior."""

    def test_expand_then_detect(
        self, multi_site_detector: MultiSiteDetector, two_site_record: ParsedRecord
    ) -> None:
        """Test that expanded records are detected as single-site."""
        expanded = multi_site_detector.expand(two_site_record)

        # Each expanded record should be single-site
        for record in expanded:
            count = multi_site_detector.detect(record)
            assert count == 1

    def test_detector_instance_independence(self) -> None:
        """Test that multiple detector instances work independently."""
        detector1 = MultiSiteDetector()
        detector2 = MultiSiteDetector()

        record = ParsedRecord(
            raw_line="test",
            parameter_set_id="TEST",
            parameter_set_version="v1",
            date_time="JUL 14 2026",
            facility="FB6",
            parameter_name="PARAM",
            sequence_number=1,
            unit_id="",
            type_id="THK-1-51T",
            c_values=["55.1", "4.9", "5.7"],
            d_values=["55.1", "4.9", "5.7"],
            timestamp="2026-07-14T03:00:00Z",
        )

        assert detector1.detect(record) == detector2.detect(record)
        assert len(detector1.expand(record)) == len(detector2.expand(record))

    def test_expand_consistency(
        self, multi_site_detector: MultiSiteDetector, five_site_record: ParsedRecord
    ) -> None:
        """Test that multiple expansions produce identical results."""
        expanded1 = multi_site_detector.expand(five_site_record)
        expanded2 = multi_site_detector.expand(five_site_record)

        assert len(expanded1) == len(expanded2)
        for e1, e2 in zip(expanded1, expanded2):
            assert e1.c_values == e2.c_values
            assert e1.d_values == e2.d_values
            assert e1.parameter_set_id == e2.parameter_set_id
