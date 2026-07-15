"""Unit tests for TimestampNormalizer utility.

Tests timestamp parsing, normalization, and ISO 8601 conversion.
"""

import pytest

from scribe_lot_mapper.exceptions import ExtractionError
from scribe_lot_mapper.utils import TimestampNormalizer


@pytest.mark.unit
class TestTimestampNormalizerBasics:
    """Test basic TimestampNormalizer functionality."""

    def test_normalize_workstream_format(self) -> None:
        """Test normalizing workstream timestamp format (JUL 14 2026 03:00:16:000AM)."""
        timestamp = "JUL 14 2026 03:00:16:000AM"
        result = TimestampNormalizer.normalize(timestamp)

        assert result == "2026-07-14T03:00:16Z"
        assert isinstance(result, str)

    def test_normalize_iso8601_with_z(self) -> None:
        """Test normalizing ISO 8601 with Z suffix."""
        timestamp = "2026-07-14T03:00:16Z"
        result = TimestampNormalizer.normalize(timestamp)

        assert result == "2026-07-14T03:00:16Z"

    def test_normalize_iso8601_basic_format(self) -> None:
        """Test normalizing ISO 8601 basic format."""
        timestamp = "2026-07-14 03:00:16"
        result = TimestampNormalizer.normalize(timestamp)

        assert result == "2026-07-14T03:00:16Z"

    def test_normalize_iso_date_only(self) -> None:
        """Test normalizing ISO date-only format."""
        timestamp = "2026-07-14"
        result = TimestampNormalizer.normalize(timestamp)

        assert result == "2026-07-14T00:00:00Z"

    def test_normalize_full_month_name(self) -> None:
        """Test normalizing with full month name (July instead of Jul)."""
        timestamp = "July 14 2026 03:00:16:000AM"
        result = TimestampNormalizer.normalize(timestamp)

        assert result == "2026-07-14T03:00:16Z"


@pytest.mark.unit
class TestTimestampNormalizerEdgeCases:
    """Test edge cases and variations."""

    def test_normalize_pm_timestamp(self) -> None:
        """Test normalizing PM timestamp."""
        timestamp = "JUL 14 2026 03:00:16:000PM"
        result = TimestampNormalizer.normalize(timestamp)

        # 3 PM is 15:00
        assert "2026-07-14T15:00:16Z" == result

    def test_normalize_midnight(self) -> None:
        """Test normalizing midnight timestamp."""
        timestamp = "JAN 01 2026 12:00:00:000AM"
        result = TimestampNormalizer.normalize(timestamp)

        assert "2026-01-01T00:00:00Z" == result

    def test_normalize_noon(self) -> None:
        """Test normalizing noon timestamp."""
        timestamp = "DEC 31 2026 12:00:00:000PM"
        result = TimestampNormalizer.normalize(timestamp)

        assert "2026-12-31T12:00:00Z" == result

    def test_normalize_with_leading_whitespace(self) -> None:
        """Test normalizing timestamp with leading whitespace."""
        timestamp = "  JUL 14 2026 03:00:16:000AM  "
        result = TimestampNormalizer.normalize(timestamp)

        assert result == "2026-07-14T03:00:16Z"

    def test_normalize_different_months(self) -> None:
        """Test normalizing timestamps with various months."""
        test_cases = [
            ("JAN 01 2026 10:00:00:000AM", "2026-01-01"),
            ("FEB 28 2026 10:00:00:000AM", "2026-02-28"),
            ("MAR 15 2026 10:00:00:000AM", "2026-03-15"),
            ("APR 30 2026 10:00:00:000AM", "2026-04-30"),
            ("MAY 31 2026 10:00:00:000AM", "2026-05-31"),
            ("JUN 30 2026 10:00:00:000AM", "2026-06-30"),
            ("JUL 31 2026 10:00:00:000AM", "2026-07-31"),
            ("AUG 31 2026 10:00:00:000AM", "2026-08-31"),
            ("SEP 30 2026 10:00:00:000AM", "2026-09-30"),
            ("OCT 31 2026 10:00:00:000AM", "2026-10-31"),
            ("NOV 30 2026 10:00:00:000AM", "2026-11-30"),
            ("DEC 31 2026 10:00:00:000AM", "2026-12-31"),
        ]

        for timestamp, expected_date in test_cases:
            result = TimestampNormalizer.normalize(timestamp)
            assert result.startswith(expected_date)


@pytest.mark.unit
class TestTimestampNormalizerErrors:
    """Test error handling."""

    def test_normalize_empty_string_raises_error(self) -> None:
        """Test normalizing empty string raises ExtractionError."""
        with pytest.raises(ExtractionError) as exc_info:
            TimestampNormalizer.normalize("")

        assert "Empty timestamp" in str(exc_info.value)

    def test_normalize_none_raises_error(self) -> None:
        """Test normalizing None-like string raises ExtractionError."""
        with pytest.raises(ExtractionError):
            TimestampNormalizer.normalize("   ")

    def test_normalize_invalid_format_raises_error(self) -> None:
        """Test normalizing invalid format raises ExtractionError."""
        with pytest.raises(ExtractionError) as exc_info:
            TimestampNormalizer.normalize("not a timestamp")

        assert "Cannot parse timestamp" in str(exc_info.value)


@pytest.mark.unit
class TestTimestampNormalizerIso8601Format:
    """Test ISO 8601 output format."""

    def test_iso8601_has_t_separator(self) -> None:
        """Test ISO 8601 output contains T separator."""
        timestamp = "JUL 14 2026 03:00:16:000AM"
        result = TimestampNormalizer.normalize(timestamp)

        assert "T" in result

    def test_iso8601_has_z_suffix(self) -> None:
        """Test ISO 8601 output has Z suffix."""
        timestamp = "JUL 14 2026 03:00:16:000AM"
        result = TimestampNormalizer.normalize(timestamp)

        assert result.endswith("Z")

    def test_iso8601_no_microseconds(self) -> None:
        """Test ISO 8601 output has no microseconds."""
        timestamp = "JUL 14 2026 03:00:16:000AM"
        result = TimestampNormalizer.normalize(timestamp)

        assert result == "2026-07-14T03:00:16Z"
        assert "." not in result


@pytest.mark.unit
class TestTimestampNormalizerParse:
    """Test parse method (returns datetime object)."""

    def test_parse_workstream_format(self) -> None:
        """Test parsing workstream timestamp returns datetime."""
        timestamp = "JUL 14 2026 03:00:16:000AM"
        result = TimestampNormalizer.parse(timestamp)

        assert result.year == 2026
        assert result.month == 7
        assert result.day == 14
        assert result.hour == 3
        assert result.minute == 0
        assert result.second == 16

    def test_parse_iso8601_format(self) -> None:
        """Test parsing ISO 8601 timestamp returns datetime."""
        timestamp = "2026-07-14T03:00:16Z"
        result = TimestampNormalizer.parse(timestamp)

        assert result.year == 2026
        assert result.month == 7
        assert result.day == 14

    def test_parse_empty_raises_error(self) -> None:
        """Test parsing empty string raises ExtractionError."""
        with pytest.raises(ExtractionError):
            TimestampNormalizer.parse("")

    def test_parse_invalid_raises_error(self) -> None:
        """Test parsing invalid format raises ExtractionError."""
        with pytest.raises(ExtractionError):
            TimestampNormalizer.parse("not a timestamp")


@pytest.mark.unit
class TestTimestampNormalizerIdempotence:
    """Test idempotent behavior (parsing then normalizing is identity)."""

    def test_normalize_then_normalize_idempotent(self) -> None:
        """Test normalizing twice produces same result."""
        timestamp = "JUL 14 2026 03:00:16:000AM"

        normalized_once = TimestampNormalizer.normalize(timestamp)
        normalized_twice = TimestampNormalizer.normalize(normalized_once)

        assert normalized_once == normalized_twice

    def test_parse_then_normalize_matches_normalize(self) -> None:
        """Test that parse then normalize matches direct normalize."""
        timestamp = "JUL 14 2026 03:00:16:000AM"

        # Direct normalization
        direct_result = TimestampNormalizer.normalize(timestamp)

        # Parse then normalize (convert back to ISO 8601)
        parsed = TimestampNormalizer.parse(timestamp)
        indirect_result = TimestampNormalizer._to_iso8601(parsed)

        assert direct_result == indirect_result


@pytest.mark.unit
class TestTimestampNormalizerTimeHandling:
    """Test various time values."""

    def test_normalize_seconds_precision(self) -> None:
        """Test normalizing preserves seconds precision."""
        timestamp = "JUL 14 2026 03:45:59:000AM"
        result = TimestampNormalizer.normalize(timestamp)

        assert "03:45:59" in result

    def test_normalize_single_digit_hours(self) -> None:
        """Test normalizing single-digit hours."""
        timestamp = "JUL 14 2026 09:00:00:000AM"
        result = TimestampNormalizer.normalize(timestamp)

        assert "2026-07-14T09:00:00Z" == result

    def test_normalize_all_hours(self) -> None:
        """Test normalizing various hours of day."""
        for hour in range(1, 13):
            timestamp = f"JUL 14 2026 {hour:02d}:30:00:000AM"
            result = TimestampNormalizer.normalize(timestamp)
            assert result.startswith("2026-07-14T")
            assert ":30:00Z" in result
