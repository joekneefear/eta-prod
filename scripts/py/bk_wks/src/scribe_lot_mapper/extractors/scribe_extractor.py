"""ScribeExtractor component for extracting and normalizing scribe identifiers.

Extracts scribe position information from unit_id and equipment context.
Handles directional indicators (LEFT, CENTER, RIGHT, TOP, BOTTOM) and generates
composite scribe identifiers linking equipment position to test site.

This component is responsible for normalizing scribe position identifiers from
workstream data and creating structured scribe IDs for use in mapping generation.

Author: Manufacturing Data Team
"""

from typing import Optional

from scribe_lot_mapper.exceptions import ExtractionError
from scribe_lot_mapper.models import EquipmentInfo


class ScribeExtractor:
    """Extracts and normalizes scribe position identifiers.

    A scribe is an individual test site or die position on a wafer. Scribe
    identification requires both equipment context (facility, probe, position)
    and unit-level position information (unit_id like "LEFT", "A6", etc.).

    This class handles:
    - Extracting unit_id from test records
    - Normalizing directional indicators (LEFT→1, CENTER→2, RIGHT→3, etc.)
    - Correlating equipment position with unit_id for unique identification
    - Handling multi-site measurements (site_number 1-5)
    - Generating composite scribe_id in standardized format

    Scribe Identification Logic:
    1. If unit_id is present, normalize it and use as scribe identifier
    2. If unit_id is empty, derive from equipment position + site_number
    3. Create composite scribe_id: [EQUIPMENT]_[POSITION]_[UNIT_ID]_[SITE]

    Examples:
    - equipment="THK-1-51T", unit_id="LEFT", site=1
      → scribe_id="THK_1_51_LEFT_1"
    - equipment="THK-1-51T", unit_id="", site=2
      → scribe_id="THK_1_51_SITE_2"
    - equipment="GOXTWS1125", unit_id="A6", site=1
      → scribe_id="GOXTWS_A6_1"

    Attributes:
        unknown_marker: String used to mark unknown or missing unit_ids
        DIRECTIONAL_MAPPINGS: Dictionary mapping directional terms to numeric codes
    """

    # Directional indicators and their numeric equivalents
    # Maps human-readable directions to single-digit codes for consistent representation
    DIRECTIONAL_MAPPINGS = {
        "LEFT": "1",
        "CENTER": "2",
        "RIGHT": "3",
        "TOP": "1",
        "BOTTOM": "2",
    }

    def __init__(self, unknown_marker: str = "SITE") -> None:
        """Initialize ScribeExtractor.

        Args:
            unknown_marker: Marker used when unit_id is missing or unknown
                          (default: "SITE")
        """
        self.unknown_marker = unknown_marker

    def extract(
        self,
        unit_id: str,
        equipment_info: EquipmentInfo,
        site_number: int = 1,
    ) -> str:
        """Extract and normalize scribe identifier from context.

        Combines equipment information (facility, probe, position) with unit-level
        position information (unit_id like "LEFT", "A6") to create a unique, 
        normalized scribe_id. Handles missing unit_id by deriving from equipment
        position and site number.

        Scribe Identification Logic:
        1. Normalize unit_id (map directional indicators, handle empty values)
        2. Create composite scribe_id using facility, probe, position, normalized 
           unit_id, and site_number
        3. Return standardized scribe_id

        Args:
            unit_id: Scribe position identifier from record
                    Examples: "LEFT", "CENTER", "RIGHT", "A6", "1", or empty
            equipment_info: Decomposed equipment information containing facility,
                          probe, position components
            site_number: Sequential site number for multi-site measurements (1-5)
                       Default is 1 for single-site records

        Returns:
            str: Normalized scribe_id in format FACILITY_PROBE_POSITION_UNITID_SITE
                Examples:
                - "THK_1_51_LEFT_1"
                - "THK_1_51_SITE_2"
                - "GOXTWS_A6_1"

        Raises:
            ExtractionError: If extraction fails due to invalid equipment_info
                           or invalid input types

        Examples:
            >>> from scribe_lot_mapper.models import EquipmentInfo
            >>> extractor = ScribeExtractor()
            
            >>> equipment = EquipmentInfo(
            ...     raw_code="THK-1-51T",
            ...     facility="THK",
            ...     probe=1,
            ...     position=51,
            ...     type="T",
            ...     normalized_code="THK-1-51-T"
            ... )
            >>> extractor.extract("LEFT", equipment, site_number=1)
            'THK_1_51_LEFT_1'

            >>> extractor.extract("", equipment, site_number=2)
            'THK_1_51_SITE_2'

            >>> extractor.extract("CENTER", equipment, site_number=1)
            'THK_1_51_CENTER_1'

            >>> equipment2 = EquipmentInfo(
            ...     raw_code="GOXTWS1125",
            ...     facility="GOXTWS",
            ...     probe=0,
            ...     position=0,
            ...     type="",
            ...     normalized_code="GOXTWS1125"
            ... )
            >>> extractor.extract("A6", equipment2, site_number=1)
            'GOXTWS_A6_1'
        """
        if not equipment_info:
            raise ExtractionError(
                "Equipment info cannot be None",
                field_name="equipment_info",
                field_value="None",
                error_code="SCRIBE_EXTRACT_001",
            )

        if not isinstance(site_number, int) or site_number < 1 or site_number > 5:
            raise ExtractionError(
                "Site number must be integer between 1-5",
                field_name="site_number",
                field_value=str(site_number),
                error_code="SCRIBE_EXTRACT_002",
            )

        # Normalize unit_id (handle empty, directional mappings, etc.)
        normalized_unit_id = self.normalize(unit_id)

        # If unit_id is empty after normalization, use unknown_marker
        if not normalized_unit_id:
            normalized_unit_id = self.unknown_marker

        # Generate composite scribe_id
        scribe_id = self.generate_composite_id(
            facility=equipment_info.facility,
            probe=equipment_info.probe,
            position=equipment_info.position,
            unit_id=normalized_unit_id,
            site_number=site_number,
        )

        return scribe_id

    def normalize(self, unit_id: str) -> str:
        """Normalize unit_id to standard format.

        Handles:
        - Empty/whitespace-only values → returns empty string
        - Directional indicators (LEFT, CENTER, RIGHT, TOP, BOTTOM) 
          → maps to numeric equivalents (1, 2, 3, etc.)
        - Alphanumeric values (A6, P1, etc.) → returns as-is (uppercase)
        - Numeric values (1, 2, etc.) → returns as-is

        Normalization allows consistent representation of scribe positions
        regardless of input format variations.

        Args:
            unit_id: Raw unit_id from record
                    Examples: "LEFT", "CENTER", "A6", "1", "P1", "", None

        Returns:
            str: Normalized unit_id
                - Empty string if input is None, empty, or whitespace-only
                - Mapped numeric value for directional indicators
                  ("LEFT" → "1", "CENTER" → "2", etc.)
                - Uppercase alphanumeric for other values ("a6" → "A6")

        Examples:
            >>> extractor = ScribeExtractor()
            >>> extractor.normalize("LEFT")
            '1'
            >>> extractor.normalize("CENTER")
            '2'
            >>> extractor.normalize("RIGHT")
            '3'
            >>> extractor.normalize("A6")
            'A6'
            >>> extractor.normalize("a6")
            'A6'
            >>> extractor.normalize("1")
            '1'
            >>> extractor.normalize("")
            ''
            >>> extractor.normalize("   ")
            ''
            >>> extractor.normalize(None)
            ''
        """
        # Handle None and empty values
        if unit_id is None or unit_id == "":
            return ""

        # Normalize to uppercase and strip whitespace
        normalized = unit_id.strip().upper()

        # If empty after stripping, return empty string
        if not normalized:
            return ""

        # Apply directional mappings (e.g., LEFT → 1, CENTER → 2)
        if normalized in self.DIRECTIONAL_MAPPINGS:
            return self.DIRECTIONAL_MAPPINGS[normalized]

        # Return as-is (already uppercase)
        return normalized

    def generate_composite_id(
        self,
        facility: str,
        probe: int,
        position: int,
        unit_id: str,
        site_number: int = 1,
    ) -> str:
        """Generate composite scribe_id combining all location information.

        Creates a unique, structured scribe identifier that combines:
        - Equipment facility (e.g., "THK", "FB6")
        - Probe number (e.g., 1, 8)
        - Position number (e.g., 51, 11)
        - Unit position identifier (e.g., "LEFT", "A6", "1")
        - Site number for multi-site measurements (1-5)

        Format: [FACILITY]_[PROBE]_[POSITION]_[UNIT_ID]_[SITE]

        This composite ID provides a complete location identifier that can be
        used to trace test results back to specific scribe/die positions.

        Args:
            facility: Facility code (e.g., "THK", "FB6", "RI")
            probe: Probe number (typically 1-8)
            position: Test position number (typically 1-60)
            unit_id: Unit position identifier (e.g., "LEFT", "A6", "1")
            site_number: Multi-site measurement index (1-5, default=1)

        Returns:
            str: Composite scribe_id in format FACILITY_PROBE_POSITION_UNITID_SITE
                Examples:
                - "THK_1_51_LEFT_1"
                - "FB6_5_100_A6_2"
                - "RI_1_11_SITE_1"

        Examples:
            >>> extractor = ScribeExtractor()
            >>> extractor.generate_composite_id("THK", 1, 51, "LEFT", 1)
            'THK_1_51_LEFT_1'
            >>> extractor.generate_composite_id("FB6", 5, 100, "A6", 2)
            'FB6_5_100_A6_2'
            >>> extractor.generate_composite_id("RI", 1, 11, "SITE", 1)
            'RI_1_11_SITE_1'
        """
        return f"{facility}_{probe}_{position}_{unit_id}_{site_number}"
