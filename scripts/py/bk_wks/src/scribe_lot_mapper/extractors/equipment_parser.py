"""EquipmentParser component for decomposing equipment codes.

Parses equipment codes like "THK-1-51T" into facility, probe, position, and type.
Follows the pattern: [FACILITY]-[PROBE]-[POSITION][TYPE]

This component is responsible for normalizing equipment identifiers from workstream
data and extracting their constituent components for use in scribe identification
and facility tracking.

Author: Manufacturing Data Team
"""

import re
from typing import Optional

from scribe_lot_mapper.exceptions import ExtractionError
from scribe_lot_mapper.models import EquipmentInfo


class EquipmentParser:
    """Decomposes equipment codes into constituent parts.

    This parser handles the standard equipment code pattern used in workstream data:
    [FACILITY]-[PROBE]-[POSITION][TYPE]

    Examples of valid equipment codes:
    - THK-1-51T → facility=THK, probe=1, position=51, type=T
    - THK-1-51F → facility=THK, probe=1, position=51, type=F
    - RI-1-11 → facility=RI, probe=1, position=11, type=""
    - ACI-1-31 → facility=ACI, probe=1, position=31, type=""
    - BV-8-31 → facility=BV, probe=8, position=31, type=""

    The parser handles:
    - Standard pattern recognition and extraction
    - Facility names (typically 2-3 uppercase letters)
    - Probe numbers (typically 1-8)
    - Position numbers (typically 1-60)
    - Type indicators (typically "T", "F", or absent)
    - Graceful handling of malformed codes

    The standard pattern regex matches:
    - Facility: 2-4 uppercase letters (e.g., THK, RI, ACI, BV, FB6)
    - Hyphen separator
    - Probe: 1-2 digits (e.g., 1, 8)
    - Hyphen separator
    - Position: 1-3 digits (e.g., 11, 51, 100)
    - Type: optional single letter (T, F, etc.)

    Attributes:
        unknown_marker: String used to mark unparseable codes (default: "UNKNOWN")
        pattern: Compiled regex for standard equipment code format
    """

    # Standard equipment code pattern: [FACILITY]-[PROBE]-[POSITION][TYPE]
    # Examples: THK-1-51T, RI-1-11, ACI-1-31, BV-8-31
    # Facility: 2-4 letters, Probe: 1-2 digits, Position: 1-3 digits, Type: optional letter
    STANDARD_PATTERN = re.compile(
        r"^([A-Z]{2,4})-(\d{1,2})-(\d{1,3})([A-Z]?)$"
    )

    def __init__(self, unknown_marker: str = "UNKNOWN") -> None:
        """Initialize EquipmentParser.

        Args:
            unknown_marker: Marker used for unknown or unparseable equipment codes
                          (default: "UNKNOWN")
        """
        self.unknown_marker = unknown_marker

    def parse(self, equipment_code: str) -> EquipmentInfo:
        """Parse equipment code into components.

        Attempts to decompose the equipment code using the standard pattern.
        If the code matches the pattern, extracts all components and returns
        an EquipmentInfo object with all fields populated.

        If the code does not match the standard pattern, attempts to extract
        components heuristically (looking for hyphens and numeric patterns).
        Gracefully handles malformed codes by returning what can be extracted
        or marking components as "UNKNOWN".

        Args:
            equipment_code: Equipment identifier string (e.g., "THK-1-51T")

        Returns:
            EquipmentInfo with all components extracted or marked as unknown

        Raises:
            ExtractionError: If the equipment code is None, empty, or cannot be
                           processed (should not happen due to graceful handling)

        Examples:
            >>> parser = EquipmentParser()
            >>> info = parser.parse("THK-1-51T")
            >>> info.facility
            'THK'
            >>> info.probe
            1
            >>> info.position
            51
            >>> info.type
            'T'
            >>> info.normalized_code
            'THK-1-51-T'

            >>> info = parser.parse("RI-1-11")
            >>> info.type
            ''
            >>> info.normalized_code
            'RI-1-11'
        """
        if not equipment_code or not isinstance(equipment_code, str):
            raise ExtractionError(
                "Equipment code must be a non-empty string",
                field_name="equipment_code",
                field_value=str(equipment_code),
                error_code="EQUIPMENT_PARSE_001",
            )

        # Try standard pattern first
        match = self.STANDARD_PATTERN.match(equipment_code.strip())
        if match:
            facility, probe_str, position_str, type_char = match.groups()
            try:
                probe = int(probe_str)
                position = int(position_str)
                normalized = self.normalize(equipment_code)
                return EquipmentInfo(
                    raw_code=equipment_code,
                    facility=facility,
                    probe=probe,
                    position=position,
                    type=type_char,
                    normalized_code=normalized,
                )
            except (ValueError, TypeError) as e:
                raise ExtractionError(
                    f"Failed to parse equipment code: {str(e)}",
                    field_name="equipment_code",
                    field_value=equipment_code,
                    error_code="EQUIPMENT_PARSE_002",
                ) from e

        # Fall back to heuristic parsing
        return self._parse_heuristic(equipment_code)

    def decompose(self, code: str) -> tuple[str, int, int, str]:
        """Decompose equipment code into components.

        Parses the equipment code and extracts its constituent parts as
        a tuple for situations where a structured EquipmentInfo object
        is not needed.

        Args:
            code: Equipment code string (e.g., "THK-1-51T")

        Returns:
            Tuple of (facility, probe, position, type)
            - facility: string (e.g., "THK")
            - probe: integer (e.g., 1)
            - position: integer (e.g., 51)
            - type: string, may be empty (e.g., "T" or "")

        Raises:
            ExtractionError: If decomposition fails

        Examples:
            >>> parser = EquipmentParser()
            >>> facility, probe, position, type_code = parser.decompose("THK-1-51T")
            >>> facility
            'THK'
            >>> probe
            1
            >>> position
            51
            >>> type_code
            'T'
        """
        equipment_info = self.parse(code)
        return (
            equipment_info.facility,
            equipment_info.probe,
            equipment_info.position,
            equipment_info.type,
        )

    def normalize(self, code: str) -> str:
        """Normalize equipment code to standard format.

        Converts equipment codes to a consistent format for comparison
        and storage. The standard format is: [FACILITY]-[PROBE]-[POSITION]-[TYPE]

        For codes with type indicators (e.g., "THK-1-51T"):
            THK-1-51T → THK-1-51-T

        For codes without type (e.g., "RI-1-11"):
            RI-1-11 → RI-1-11

        This ensures consistent representation regardless of input format
        variations.

        Args:
            code: Equipment code string (may be in various formats)

        Returns:
            Normalized equipment code in standard format

        Examples:
            >>> parser = EquipmentParser()
            >>> parser.normalize("THK-1-51T")
            'THK-1-51-T'
            >>> parser.normalize("RI-1-11")
            'RI-1-11'
            >>> parser.normalize("thk-1-51t")  # Uppercase conversion
            'THK-1-51-T'
        """
        if not code:
            return ""

        # Convert to uppercase for consistency
        code = code.strip().upper()

        # Try standard pattern
        match = self.STANDARD_PATTERN.match(code)
        if match:
            facility, probe, position, type_char = match.groups()
            # Format: FACILITY-PROBE-POSITION or FACILITY-PROBE-POSITION-TYPE
            if type_char:
                return f"{facility}-{probe}-{position}-{type_char}"
            else:
                return f"{facility}-{probe}-{position}"

        # If no match, return the code as-is (uppercase)
        return code

    def _parse_heuristic(self, code: str) -> EquipmentInfo:
        """Attempt heuristic parsing when standard pattern doesn't match.

        This method tries to extract components from malformed equipment codes
        by looking for hyphen separators and numeric patterns. It's a fallback
        for handling data quality issues or non-standard equipment code formats.

        Strategy:
        1. Split by hyphens to get potential components
        2. Extract facility (first alphabetic component)
        3. Extract probe (first numeric component)
        4. Extract position (second numeric component)
        5. Extract type (trailing alphabetic character)
        6. Mark anything that can't be extracted as "UNKNOWN"

        Args:
            code: Equipment code string that didn't match standard pattern

        Returns:
            EquipmentInfo with whatever components could be extracted

        Examples:
            >>> parser = EquipmentParser()
            >>> info = parser._parse_heuristic("THK_1_51T")  # Underscores instead of hyphens
            >>> info.facility
            'THK'
            >>> info.probe
            1
            >>> info.position
            51
            >>> info.type
            'T'
        """
        facility_str = self.unknown_marker
        probe = 0
        position = 0
        type_str = ""

        try:
            # Normalize separators: replace underscores, spaces with hyphens
            normalized_code = code.upper().replace("_", "-").replace(" ", "-")

            # Split by hyphen
            parts = [p.strip() for p in normalized_code.split("-") if p.strip()]

            if len(parts) >= 1:
                # Try to extract facility (first all-letter component)
                for part in parts:
                    if part and part.isalpha() and len(part) >= 2:
                        facility_str = part
                        break

            if len(parts) >= 2:
                # Try to extract probe (first numeric component)
                for part in parts:
                    if part and part.isdigit():
                        probe = int(part)
                        break

            if len(parts) >= 3:
                # Try to extract position (second numeric component)
                numeric_count = 0
                for part in parts:
                    if part and part.isdigit():
                        numeric_count += 1
                        if numeric_count == 2:
                            position = int(part)
                            break

            # Extract type indicator (any trailing single letter)
            # Look at last character of last part
            if parts and len(parts[-1]) > 0:
                last_char = parts[-1][-1]
                if last_char.isalpha() and last_char not in facility_str:
                    type_str = last_char

        except (ValueError, IndexError, AttributeError):
            # If heuristic parsing fails, return with unknown_marker
            pass

        normalized = self.normalize(code)
        return EquipmentInfo(
            raw_code=code,
            facility=facility_str,
            probe=probe,
            position=position,
            type=type_str,
            normalized_code=normalized,
        )
