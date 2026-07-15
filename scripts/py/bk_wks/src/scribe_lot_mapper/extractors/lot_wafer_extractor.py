"""LotWaferExtractor component for extracting lot and wafer identifiers.

Extracts and normalizes lot identifiers (KG* pattern) and wafer batch identifiers
(GOXTWS* pattern), establishes their relationship, and generates virtual wafer IDs
when source identifiers are not present.

This component is responsible for normalizing lot and wafer identifiers from
workstream data and establishing bidirectional lot↔wafer relationships.

Author: Manufacturing Data Team
"""

import hashlib
from typing import Optional, Tuple
from datetime import datetime

from scribe_lot_mapper.exceptions import ExtractionError
from scribe_lot_mapper.models import ParsedRecord


class LotWaferExtractor:
    """Extracts and normalizes lot and wafer identifiers and relationships.

    A lot is a manufacturing lot identifier (e.g., "KG4BNTCX") that may contain
    one or more wafers. A wafer is identified by a batch number (e.g., "GOXTWS1125")
    or a virtual ID generated from lot + equipment + timestamp.

    This class handles:
    - Extracting lot identifiers from records (KG* pattern)
    - Extracting wafer batch identifiers (GOXTWS* pattern)
    - Normalizing both identifiers to standard format
    - Establishing lot→wafer relationship (many-to-one)
    - Generating virtual wafer IDs when source not present
    - Validating identifier format correctness

    Lot-Wafer Relationship:
    - Every wafer belongs to exactly one lot (one-to-one from wafer perspective)
    - One lot may contain multiple wafers (one-to-many from lot perspective)
    - Virtual wafers are generated when explicit wafer ID is missing

    Examples:
    - lot_id="KG4BNTCX", wafer_id="GOXTWS1125" → lot and wafer both present
    - lot_id="KG4BNTCX", wafer_id="" → virtual wafer ID generated
    - lot_id="", wafer_id="GOXTWS1125" → attempt to extract lot from other fields

    Attributes:
        LOT_PATTERN_PREFIX: Expected prefix for lot identifiers ("KG")
        WAFER_PATTERN_PREFIX: Expected prefix for wafer batch identifiers ("GOXTWS")
        VIRTUAL_WAFER_PREFIX: Prefix used for generated virtual wafer IDs
    """

    # Lot pattern constants
    LOT_PATTERN_PREFIX = "KG"
    
    # Wafer pattern constants
    WAFER_PATTERN_PREFIX = "GOXTWS"
    
    # Virtual wafer generation constants
    VIRTUAL_WAFER_PREFIX = "VW_"

    def __init__(self) -> None:
        """Initialize LotWaferExtractor."""
        pass

    def extract(
        self, record: ParsedRecord
    ) -> Tuple[str, str, str]:
        """Extract lot, wafer, and wafer family from parsed record.

        Attempts to extract lot and wafer identifiers from available fields in
        the record. If explicit wafer identifier is missing, generates a virtual
        wafer ID based on lot, equipment, and timestamp.

        The extraction logic prioritizes explicit field values but can fall back
        to derived/virtual values to ensure completeness.

        Args:
            record: ParsedRecord to extract from (contains all parsed fields)

        Returns:
            Tuple of (lot_id, wafer_id, wafer_family):
            - lot_id: Normalized lot identifier (or empty string if not found)
            - wafer_id: Wafer batch identifier or virtual wafer ID
            - wafer_family: Wafer family/type classification (or empty string)

        Raises:
            ExtractionError: If extraction fails critically (e.g., invalid record)

        Examples:
            >>> from scribe_lot_mapper.models import ParsedRecord
            >>> extractor = LotWaferExtractor()
            
            >>> # Record with both lot and wafer
            >>> record = ParsedRecord(
            ...     raw_line="...",
            ...     parameter_set_id="GMBG3002",
            ...     parameter_set_version="1.0",
            ...     date_time="2026-07-14 03:34:33",
            ...     facility="FB6",
            ...     parameter_name="TEST_1",
            ...     sequence_number=1,
            ...     unit_id="LEFT",
            ...     type_id="THK-1-51T",
            ...     c_values=["301.2"],
            ...     d_values=[],
            ...     timestamp="2026-07-14T03:34:33Z"
            ... )
            >>> # Assume lot_id and wafer_id are in type_id or other fields
            >>> lot_id, wafer_id, wafer_family = extractor.extract(record)

            >>> # Record with lot only (wafer will be virtual)
            >>> lot_id, wafer_id, wafer_family = extractor.extract(record)
            >>> assert lot_id.startswith("KG")
            >>> assert wafer_id.startswith("VW_") or wafer_id.startswith("GOXTWS")
        """
        if not record:
            raise ExtractionError(
                "Record cannot be None",
                field_name="record",
                field_value="None",
                error_code="LOT_WAFER_EXTRACT_001",
            )

        if not record.has_required_fields():
            raise ExtractionError(
                "Record is missing required fields",
                field_name="record",
                field_value=str(record),
                error_code="LOT_WAFER_EXTRACT_002",
            )

        # Extract lot identifier from available sources
        lot_id = self._extract_lot_from_record(record)

        # Extract wafer identifier from available sources
        wafer_id = self._extract_wafer_from_record(record)

        # If wafer_id is empty, generate virtual wafer ID
        if not wafer_id:
            wafer_id = self.generate_virtual_wafer(
                lot_id=lot_id,
                equipment_id=record.type_id,
                timestamp=record.timestamp,
            )

        # Extract wafer family/type classification
        wafer_family = self._extract_wafer_family(wafer_id)

        return lot_id, wafer_id, wafer_family

    def _extract_lot_from_record(self, record: ParsedRecord) -> str:
        """Extract lot identifier from record fields.

        Searches multiple record fields for lot identifiers matching KG* pattern.
        Prioritizes explicit lot fields but can derive from equipment or other context.

        Args:
            record: ParsedRecord to search

        Returns:
            Normalized lot identifier, or empty string if not found

        Note:
            In the parameter history (phist) format, lot identifier may appear in:
            - type_id field (equipment code may include lot reference)
            - parameter_set_id field (test program may include lot context)
            - Other context fields (if available in extended formats)
        """
        # Try to extract lot from type_id field (most common location)
        if record.type_id:
            lot = self._find_lot_in_string(record.type_id)
            if lot:
                return self.normalize_lot(lot)

        # Try to extract lot from parameter_set_id field
        if record.parameter_set_id:
            lot = self._find_lot_in_string(record.parameter_set_id)
            if lot:
                return self.normalize_lot(lot)

        # Try to extract lot from parameter_name field
        if record.parameter_name:
            lot = self._find_lot_in_string(record.parameter_name)
            if lot:
                return self.normalize_lot(lot)

        # No lot found in any field
        return ""

    def _extract_wafer_from_record(self, record: ParsedRecord) -> str:
        """Extract wafer identifier from record fields.

        Searches multiple record fields for wafer identifiers matching GOXTWS* pattern
        or other known wafer ID patterns.

        Args:
            record: ParsedRecord to search

        Returns:
            Normalized wafer identifier, or empty string if not found

        Note:
            In the parameter history (phist) format, wafer identifier may appear in:
            - type_id field (equipment code may include wafer reference)
            - parameter_set_id field (test program may include wafer context)
            - c_values or d_values fields (measurement metadata)
        """
        # Try to extract wafer from type_id field
        if record.type_id:
            wafer = self._find_wafer_in_string(record.type_id)
            if wafer:
                return self.normalize_wafer(wafer)

        # Try to extract wafer from parameter_set_id field
        if record.parameter_set_id:
            wafer = self._find_wafer_in_string(record.parameter_set_id)
            if wafer:
                return self.normalize_wafer(wafer)

        # Try to extract wafer from parameter_name field
        if record.parameter_name:
            wafer = self._find_wafer_in_string(record.parameter_name)
            if wafer:
                return self.normalize_wafer(wafer)

        # No wafer found in any field
        return ""

    def _find_lot_in_string(self, text: str) -> Optional[str]:
        """Search for lot identifier pattern (KG*) in text.

        Args:
            text: Text to search

        Returns:
            Lot identifier if found, None otherwise

        Examples:
            >>> extractor = LotWaferExtractor()
            >>> extractor._find_lot_in_string("KG4BNTCX")
            'KG4BNTCX'
            >>> extractor._find_lot_in_string("TEST_KG42910X1_END")
            'KG42910X1'
            >>> extractor._find_lot_in_string("NO_LOT_HERE")
            None
        """
        if not text:
            return None

        # Look for KG pattern followed by alphanumeric characters
        # Pattern: KG followed by at least 3 more alphanumeric chars
        text = text.upper()
        
        # Find all occurrences of KG followed by alphanumerics
        idx = text.find(self.LOT_PATTERN_PREFIX)
        if idx == -1:
            return None

        # Extract substring starting with KG
        substring = text[idx:]
        
        # Find the end of the lot ID (stop at first non-alphanumeric or hyphen/underscore)
        lot_id = ""
        for char in substring:
            if char.isalnum():
                lot_id += char
            else:
                break

        # Validate that we have a meaningful lot ID (at least KG + 2 more chars)
        if len(lot_id) >= len(self.LOT_PATTERN_PREFIX) + 2:
            return lot_id

        return None

    def _find_wafer_in_string(self, text: str) -> Optional[str]:
        """Search for wafer identifier pattern (GOXTWS*) in text.

        Args:
            text: Text to search

        Returns:
            Wafer identifier if found, None otherwise

        Examples:
            >>> extractor = LotWaferExtractor()
            >>> extractor._find_wafer_in_string("GOXTWS1125")
            'GOXTWS1125'
            >>> extractor._find_wafer_in_string("TEST_GOXTWS2135_END")
            'GOXTWS2135'
            >>> extractor._find_wafer_in_string("NO_WAFER_HERE")
            None
        """
        if not text:
            return None

        # Look for GOXTWS pattern followed by digits
        text = text.upper()
        
        # Find all occurrences of GOXTWS
        idx = text.find(self.WAFER_PATTERN_PREFIX)
        if idx == -1:
            return None

        # Extract substring starting with GOXTWS
        substring = text[idx:]
        
        # Find the end of the wafer ID (stop at first non-alphanumeric)
        wafer_id = ""
        for char in substring:
            if char.isalnum():
                wafer_id += char
            else:
                break

        # Validate that we have a meaningful wafer ID (at least GOXTWS + digits)
        if len(wafer_id) > len(self.WAFER_PATTERN_PREFIX):
            return wafer_id

        return None

    def _extract_wafer_family(self, wafer_id: str) -> str:
        """Extract wafer family/type classification from wafer identifier.

        Analyzes wafer ID to determine family/type for categorization.
        For GOXTWS pattern: family is generally "GOXTWS" prefix.

        Args:
            wafer_id: Normalized wafer identifier

        Returns:
            Wafer family string, or empty string if not determinable

        Examples:
            >>> extractor = LotWaferExtractor()
            >>> extractor._extract_wafer_family("GOXTWS1125")
            'GOXTWS'
            >>> extractor._extract_wafer_family("GOXTWS2135")
            'GOXTWS'
            >>> extractor._extract_wafer_family("VW_abc123def456")
            'VIRTUAL'
        """
        if not wafer_id:
            return ""

        # Check for virtual wafer prefix
        if wafer_id.startswith(self.VIRTUAL_WAFER_PREFIX):
            return "VIRTUAL"

        # Check for GOXTWS pattern
        if wafer_id.startswith(self.WAFER_PATTERN_PREFIX):
            return self.WAFER_PATTERN_PREFIX

        # Default to empty if type cannot be determined
        return ""

    def normalize_lot(self, lot_string: str) -> str:
        """Normalize lot identifier to standard format.

        Standardizes lot identifiers by:
        - Converting to uppercase
        - Stripping whitespace
        - Validating against KG* pattern
        - Removing any trailing non-alphanumeric characters

        Args:
            lot_string: Raw lot identifier to normalize

        Returns:
            Normalized lot_id (uppercase, whitespace-trimmed)
            Returns empty string if validation fails

        Examples:
            >>> extractor = LotWaferExtractor()
            >>> extractor.normalize_lot("KG4BNTCX")
            'KG4BNTCX'
            >>> extractor.normalize_lot("kg4bntcx")
            'KG4BNTCX'
            >>> extractor.normalize_lot("  KG4BNTCX  ")
            'KG4BNTCX'
            >>> extractor.normalize_lot("KG42910X1")
            'KG42910X1'
            >>> extractor.normalize_lot("kg42910x1")
            'KG42910X1'
            >>> extractor.normalize_lot("INVALID_LOT")
            ''
            >>> extractor.normalize_lot("")
            ''
        """
        if not lot_string:
            return ""

        # Convert to uppercase and strip whitespace
        normalized = lot_string.strip().upper()

        # Validate against pattern (must start with KG)
        if not normalized.startswith(self.LOT_PATTERN_PREFIX):
            return ""

        # Validate that lot is at least KG + 2 more alphanumeric characters
        if len(normalized) < len(self.LOT_PATTERN_PREFIX) + 2:
            return ""

        # Remove any trailing non-alphanumeric characters
        normalized = "".join(c for c in normalized if c.isalnum())

        return normalized

    def normalize_wafer(self, wafer_string: str) -> str:
        """Normalize wafer identifier to standard format.

        Standardizes wafer identifiers by:
        - Converting to uppercase
        - Stripping whitespace
        - Validating format (GOXTWS* or other known patterns)
        - Removing any trailing non-alphanumeric characters

        Args:
            wafer_string: Raw wafer identifier to normalize

        Returns:
            Normalized wafer_id (uppercase, whitespace-trimmed)
            Returns empty string if validation fails

        Examples:
            >>> extractor = LotWaferExtractor()
            >>> extractor.normalize_wafer("GOXTWS1125")
            'GOXTWS1125'
            >>> extractor.normalize_wafer("goxtws1125")
            'GOXTWS1125'
            >>> extractor.normalize_wafer("  GOXTWS1125  ")
            'GOXTWS1125'
            >>> extractor.normalize_wafer("GOXTWS2135")
            'GOXTWS2135'
            >>> extractor.normalize_wafer("INVALID_WAFER")
            ''
            >>> extractor.normalize_wafer("")
            ''
        """
        if not wafer_string:
            return ""

        # Convert to uppercase and strip whitespace
        normalized = wafer_string.strip().upper()

        # Check for known wafer patterns
        if not (normalized.startswith(self.WAFER_PATTERN_PREFIX) or 
                normalized.startswith(self.VIRTUAL_WAFER_PREFIX)):
            return ""

        # Validate minimum length (GOXTWS + at least 1 digit)
        if len(normalized) <= len(self.WAFER_PATTERN_PREFIX) and \
           not normalized.startswith(self.VIRTUAL_WAFER_PREFIX):
            return ""

        # Remove any trailing non-alphanumeric characters (except underscores for virtual)
        if normalized.startswith(self.VIRTUAL_WAFER_PREFIX):
            # For virtual wafers, allow underscores
            normalized = "".join(
                c for c in normalized if c.isalnum() or c == "_"
            )
        else:
            # For standard wafers, only alphanumerics
            normalized = "".join(c for c in normalized if c.isalnum())

        return normalized

    def generate_virtual_wafer(
        self,
        lot_id: str,
        equipment_id: str,
        timestamp: str,
    ) -> str:
        """Generate virtual wafer ID when source identifier not present.

        Creates a deterministic virtual wafer identifier combining:
        - Lot identifier (primary key component)
        - Equipment identifier (location component)
        - Timestamp (uniqueness component)

        The virtual ID format ensures:
        - Determinism: Same inputs always produce same output
        - Uniqueness: Different lots/equipment/times produce different IDs
        - Consistency: Can be regenerated from same inputs

        Args:
            lot_id: Lot identifier (part of virtual ID)
            equipment_id: Equipment where test occurred (part of virtual ID)
            timestamp: Test execution timestamp in ISO 8601 format

        Returns:
            Generated virtual wafer_id in format: VW_[lot_hash]_[equipment_hash]
            Example: VW_abc123def456_xyz789uvw012

        Note:
            Virtual wafer IDs are marked with VW_ prefix to distinguish from
            explicit batch identifiers like GOXTWS1125.

        Examples:
            >>> extractor = LotWaferExtractor()
            >>> virtual_id = extractor.generate_virtual_wafer(
            ...     lot_id="KG4BNTCX",
            ...     equipment_id="THK-1-51T",
            ...     timestamp="2026-07-14T03:34:33Z"
            ... )
            >>> assert virtual_id.startswith("VW_")
            >>> # Same inputs produce same output (deterministic)
            >>> virtual_id2 = extractor.generate_virtual_wafer(
            ...     lot_id="KG4BNTCX",
            ...     equipment_id="THK-1-51T",
            ...     timestamp="2026-07-14T03:34:33Z"
            ... )
            >>> assert virtual_id == virtual_id2
        """
        # Combine components for hashing
        combined = f"{lot_id}_{equipment_id}_{timestamp}"

        # Generate hash using SHA256 for deterministic, compact ID
        hash_obj = hashlib.sha256(combined.encode())
        hash_hex = hash_obj.hexdigest()[:16]  # Use first 16 chars for conciseness

        # Format virtual wafer ID with prefix and hashes
        virtual_wafer_id = f"{self.VIRTUAL_WAFER_PREFIX}{hash_hex}"

        return virtual_wafer_id
