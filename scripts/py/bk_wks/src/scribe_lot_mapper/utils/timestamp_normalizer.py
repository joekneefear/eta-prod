"""TimestampNormalizer utility for parsing and normalizing timestamps.

Handles various timestamp formats commonly found in workstream data and
normalizes them to ISO 8601 format.
"""

from datetime import datetime
from typing import Optional

from dateutil import parser as dateutil_parser

from scribe_lot_mapper.exceptions import ExtractionError


class TimestampNormalizer:
    """Parses and normalizes timestamps to ISO 8601 format.

    Supports multiple timestamp formats found in workstream data:
    - "JUL 14 2026 03:00:16:000AM" (workstream format)
    - "2026-07-14T03:00:16Z" (ISO 8601)
    - "2026-07-14 03:00:16" (ISO basic format)
    - And other common formats via dateutil fallback
    """

    # Custom format patterns to try first
    CUSTOM_FORMATS = [
        "%b %d %Y %H:%M:%S:%f%p",  # JUL 14 2026 03:00:16:000AM
        "%B %d %Y %H:%M:%S:%f%p",  # July 14 2026 03:00:16:000AM
    ]

    # Standard ISO formats
    ISO_FORMATS = [
        "%Y-%m-%dT%H:%M:%SZ",  # 2026-07-14T03:00:16Z
        "%Y-%m-%d %H:%M:%S",   # 2026-07-14 03:00:16
        "%Y-%m-%d",  # 2026-07-14
    ]

    @classmethod
    def normalize(cls, timestamp_str: str) -> str:
        """Normalize timestamp to ISO 8601 format.

        Args:
            timestamp_str: Timestamp string in any supported format

        Returns:
            str: ISO 8601 formatted timestamp (YYYY-MM-DDTHH:MM:SSZ)

        Raises:
            ExtractionError: If timestamp cannot be parsed
        """
        if not timestamp_str or timestamp_str.strip() == "":
            raise ExtractionError("Empty timestamp string")

        # Try custom formats first
        for fmt in cls.CUSTOM_FORMATS:
            try:
                dt = datetime.strptime(timestamp_str.strip(), fmt)
                return cls._to_iso8601(dt)
            except ValueError:
                continue

        # Try ISO formats
        for fmt in cls.ISO_FORMATS:
            try:
                dt = datetime.strptime(timestamp_str.strip(), fmt)
                return cls._to_iso8601(dt)
            except ValueError:
                continue

        # Fallback to dateutil parser
        try:
            dt = dateutil_parser.parse(timestamp_str)
            return cls._to_iso8601(dt)
        except (ValueError, dateutil_parser.ParserError) as e:
            raise ExtractionError(f"Cannot parse timestamp: {timestamp_str}") from e

    @classmethod
    def _to_iso8601(cls, dt: datetime) -> str:
        """Convert datetime to ISO 8601 format.

        Args:
            dt: datetime object

        Returns:
            str: ISO 8601 formatted timestamp
        """
        # Remove microseconds and ensure Z suffix for UTC
        return dt.replace(microsecond=0).isoformat() + "Z"

    @classmethod
    def parse(cls, timestamp_str: str) -> datetime:
        """Parse timestamp to datetime object.

        Args:
            timestamp_str: Timestamp string in any supported format

        Returns:
            datetime: Parsed datetime object (naive, no timezone)

        Raises:
            ExtractionError: If timestamp cannot be parsed
        """
        # Try custom formats first
        for fmt in cls.CUSTOM_FORMATS:
            try:
                return datetime.strptime(timestamp_str.strip(), fmt)
            except ValueError:
                continue

        # Try ISO formats
        for fmt in cls.ISO_FORMATS:
            try:
                return datetime.strptime(timestamp_str.strip(), fmt)
            except ValueError:
                continue

        # Fallback to dateutil parser
        try:
            return dateutil_parser.parse(timestamp_str)
        except (ValueError, dateutil_parser.ParserError) as e:
            raise ExtractionError(f"Cannot parse timestamp: {timestamp_str}") from e
