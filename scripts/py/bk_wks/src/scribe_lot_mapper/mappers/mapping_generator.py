"""MappingGenerator component for creating bidirectional mapping records.

Creates mapping records that link scribes, lots, and wafers enabling all four
mapping directions:
- Scribe → Lot/Wafer (forward lookup)
- Lot/Wafer → Scribe (reverse lookup)
- Wafer → Lot (one-to-one implicit)
- Lot → Wafer (one-to-many implicit)

Each mapping record contains scribe_id, lot_id, AND wafer_id together, enabling
all relationships and providing complete traceability from individual scribe
positions through production lots to wafer numbers.

Author: Manufacturing Data Team
"""

from datetime import datetime, timezone
from typing import Optional
from uuid import uuid4

from scribe_lot_mapper.exceptions import MappingError
from scribe_lot_mapper.models import MappingRecord, ParsedRecord


class MappingGenerator:
    """Creates bidirectional mapping records linking scribe ↔ lot ↔ wafer.

    Generates MappingRecord instances that establish bidirectional relationships
    between scribes, lots, and wafers. Each record contains all three identifiers
    (scribe_id, lot_id, wafer_id) plus test context, enabling:

    1. Forward Lookup (Lot → Scribe)
       - Input: lot_id, wafer_id
       - Output: All scribes that processed this lot/wafer
       - Example: "Which scribes tested lot KG4BNTCX, wafer GOXTWS1125?"

    2. Reverse Lookup (Scribe → Lot)
       - Input: scribe_id
       - Output: All lots and wafers processed by this scribe
       - Example: "What lots have been processed by scribe THK_1_51_LEFT_1?"

    3. Transitive Lookup (Scribe → Wafer)
       - Input: scribe_id
       - Output: All wafers processed by this scribe (via lot relationship)
       - Example: "What wafers did scribe A6 work on?"

    4. Lot-Wafer Query (Lot → Wafer)
       - Input: lot_id
       - Output: All wafers belonging to this lot
       - Example: "Which wafers are in lot KG4BNTCX?"

    The bidirectionality is achieved by storing all three identifiers in a single
    record, allowing any component to be used as a lookup key.

    Multi-site Handling:
    Records expanded from multi-site measurements (multiple c_value/d_value fields)
    are linked via parent_mapping_id to maintain traceability of expansion source.

    Attributes:
        id_strategy: Strategy for generating mapping IDs ("uuid" or "sequential")
        _sequence_counter: Counter for sequential ID generation
        _wafer_family_cache: Cache for wafer family extraction (performance optimization)
    """

    def __init__(self, id_strategy: str = "uuid") -> None:
        """Initialize MappingGenerator.

        Args:
            id_strategy: ID generation strategy, either "uuid" (default) or "sequential"
                        - "uuid": Generate UUID v4 identifiers (globally unique, non-sequential)
                        - "sequential": Generate sequential numeric IDs (compact, ordered)

        Raises:
            ValueError: If id_strategy is not recognized
        """
        if id_strategy not in ("uuid", "sequential"):
            raise ValueError(
                f"Unknown ID strategy: {id_strategy}. Must be 'uuid' or 'sequential'"
            )
        self.id_strategy = id_strategy
        self._sequence_counter = 0
        self._wafer_family_cache = {}

    def generate(
        self,
        scribe_id: str,
        lot_id: str,
        wafer_id: str,
        parsed_record: ParsedRecord,
        site_number: int = 1,
        parent_mapping_id: Optional[str] = None,
        test_value: str = "",
        wafer_family: str = "",
        wafer_batch: int = 0,
    ) -> MappingRecord:
        """Generate a mapping record linking scribe, lot, and wafer.

        Creates a complete MappingRecord that establishes bidirectional relationships
        between the scribe, lot, and wafer, along with full test context from the
        original parsed record. The generated record enables all four mapping directions.

        Mapping Record Contains:
        - Unique mapping_id (UUID or sequential)
        - Scribe information: scribe_id, unit_id, site_number
        - Lot identifier: lot_id
        - Wafer identifiers: wafer_id, wafer_family, wafer_batch
        - Test context: test_program, test_value, equipment_id, facility
        - Timestamps: ISO 8601 test execution time, record creation time
        - Multi-site tracking: parent_mapping_id if from expansion
        - Validation status: "valid" by default

        All required fields must be non-empty for a complete mapping record.

        Args:
            scribe_id: Normalized scribe position identifier
                      (e.g., "THK_1_51_LEFT_1", "GOXTWS_A6_1")
                      Must be non-empty string
            lot_id: Manufacturing lot identifier following KG* pattern
                   (e.g., "KG4BNTCX", "KG42910X1")
                   Must be non-empty string
            wafer_id: Wafer identifier - batch number or virtual ID
                     (e.g., "GOXTWS1125" or "VW_abc123def456")
                     Must be non-empty string
            parsed_record: Original ParsedRecord after field extraction
                          Provides context: parameter_set_id (test program),
                          facility, timestamp, type_id (equipment), etc.
            site_number: Multi-site measurement index (1-5, default=1)
                        Identifies which site this record represents in multi-site tests
            parent_mapping_id: Optional parent mapping ID if this record came from
                              multi-site expansion. Links expanded records to source.
            test_value: Optional test measurement value (e.g., "301.2", "55.1")
                       Extracted from c_value or d_value field
            wafer_family: Optional wafer family/type classification
                         (e.g., "GOXTWS" for GOXTWS1125, "VIRTUAL" for virtual IDs)
            wafer_batch: Optional wafer batch number as integer (default=0 if not present)

        Returns:
            MappingRecord: Complete bidirectional mapping with all relationships

        Raises:
            MappingError: If mapping cannot be generated due to:
                - Missing or invalid required parameters (scribe_id, lot_id, wafer_id)
                - Invalid parsed_record (missing required fields)
                - Invalid site_number (not 1-5)
                - Invalid timestamp in parsed_record

        Examples:
            >>> from scribe_lot_mapper.models import ParsedRecord, MappingRecord
            >>> generator = MappingGenerator()
            
            >>> # Create sample parsed record
            >>> record = ParsedRecord(
            ...     raw_line="test_line",
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
            
            >>> # Generate mapping
            >>> mapping = generator.generate(
            ...     scribe_id="THK_1_51_LEFT_1",
            ...     lot_id="KG4BNTCX",
            ...     wafer_id="GOXTWS1125",
            ...     parsed_record=record,
            ...     site_number=1,
            ...     test_value="301.2",
            ...     wafer_family="GOXTWS",
            ...     wafer_batch=1125
            ... )
            
            >>> assert mapping.scribe_id == "THK_1_51_LEFT_1"
            >>> assert mapping.lot_id == "KG4BNTCX"
            >>> assert mapping.wafer_id == "GOXTWS1125"
            >>> assert mapping.is_complete()
            >>> assert mapping.is_valid_lot_id()
            >>> assert not mapping.is_from_multi_site_expansion()
        """
        # Validate required parameters
        if not scribe_id or not scribe_id.strip():
            raise MappingError(
                f"scribe_id cannot be empty (received: '{scribe_id}')"
            )

        if not lot_id or not lot_id.strip():
            raise MappingError(
                f"lot_id cannot be empty (received: '{lot_id}')"
            )

        if not wafer_id or not wafer_id.strip():
            raise MappingError(
                f"wafer_id cannot be empty (received: '{wafer_id}')"
            )

        if not parsed_record:
            raise MappingError("parsed_record cannot be None")

        if not parsed_record.has_required_fields():
            raise MappingError(
                f"parsed_record missing required fields: {parsed_record}"
            )

        if not isinstance(site_number, int) or site_number < 1 or site_number > 5:
            raise MappingError(
                f"site_number must be integer between 1-5 (received: {site_number})"
            )

        if not parsed_record.timestamp:
            raise MappingError(
                f"parsed_record timestamp cannot be empty (received: '{parsed_record.timestamp}')"
            )

        # Generate unique mapping ID
        mapping_id = self.assign_mapping_id()

        # Get current timestamp for creation_at (when record was created, not when test executed)
        created_at = self._get_current_iso8601_timestamp()

        # Extract unit_id from parsed_record (may be empty)
        unit_id = parsed_record.unit_id or ""

        # Create mapping record with all relationships
        mapping_record = MappingRecord(
            # Unique identifier
            mapping_id=mapping_id,
            # Scribe information (complete scribe location)
            scribe_id=scribe_id.strip(),
            unit_id=unit_id.strip(),
            site_number=site_number,
            # Lot information
            lot_id=lot_id.strip(),
            # Wafer information (all three components)
            wafer_id=wafer_id.strip(),
            wafer_family=wafer_family.strip(),
            wafer_batch=wafer_batch,
            # Test context (from parsed record)
            test_program=parsed_record.parameter_set_id.strip(),
            test_value=test_value.strip(),
            equipment_id=parsed_record.type_id.strip(),
            facility=parsed_record.facility.strip(),
            sequence_number=parsed_record.sequence_number,
            # Timestamps (ISO 8601)
            timestamp=parsed_record.timestamp.strip(),  # Test execution time
            created_at=created_at,  # Record creation time
            # Multi-site tracking
            parent_mapping_id=parent_mapping_id,
            # Validation status (valid by default)
            validation_status="valid",
        )

        return mapping_record

    def create_bidirectional_mapping(
        self,
        scribe_id: str,
        lot_id: str,
        wafer_id: str,
        parsed_record: ParsedRecord,
        site_number: int = 1,
        parent_mapping_id: Optional[str] = None,
    ) -> MappingRecord:
        """Create bidirectional mapping from components.

        Convenience method that calls generate() with parsed_record context,
        suitable for creating mappings from fully extracted components.

        This method extracts test_value from parsed_record's c_values or d_values
        and handles wafer_family extraction automatically.

        Args:
            scribe_id: Normalized scribe position identifier
            lot_id: Manufacturing lot identifier
            wafer_id: Wafer identifier
            parsed_record: Original ParsedRecord with test context
            site_number: Multi-site measurement index (1-5, default=1)
            parent_mapping_id: Optional parent mapping ID if from expansion

        Returns:
            MappingRecord: Complete bidirectional mapping

        Raises:
            MappingError: If mapping cannot be created
        """
        # Extract test value from parsed record (prefer c_value, fall back to d_value)
        test_value = ""
        if parsed_record.c_values and parsed_record.c_values[0]:
            test_value = parsed_record.c_values[0]
        elif parsed_record.d_values and parsed_record.d_values[0]:
            test_value = parsed_record.d_values[0]

        # Extract wafer_family and batch from wafer_id
        wafer_family, wafer_batch = self._extract_wafer_info(wafer_id)

        # Use generate() with extracted components
        return self.generate(
            scribe_id=scribe_id,
            lot_id=lot_id,
            wafer_id=wafer_id,
            parsed_record=parsed_record,
            site_number=site_number,
            parent_mapping_id=parent_mapping_id,
            test_value=test_value,
            wafer_family=wafer_family,
            wafer_batch=wafer_batch,
        )

    def assign_mapping_id(self) -> str:
        """Assign unique mapping ID.

        Generates a unique mapping identifier using the configured ID strategy.
        The ID is used for auditing, tracing, and deduplication of mapping records.

        ID Strategy:
        - "uuid": Generates UUID v4 (128-bit, globally unique, non-sequential)
                  Format: "550e8400-e29b-41d4-a716-446655440000"
                  Use for distributed systems where global uniqueness is required
        - "sequential": Generates sequential numeric IDs (32-bit, ordered, compact)
                       Format: "MAP_0000000001", "MAP_0000000002", etc.
                       Use for single-threaded processing with ID compactness

        Returns:
            str: Generated mapping ID
                - UUID format if strategy is "uuid"
                - Sequential format "MAP_XXXXXXXXXX" if strategy is "sequential"

        Raises:
            ValueError: If ID strategy is invalid (should not happen if __init__ validated)

        Examples:
            >>> generator_uuid = MappingGenerator(id_strategy="uuid")
            >>> id1 = generator_uuid.assign_mapping_id()
            >>> id2 = generator_uuid.assign_mapping_id()
            >>> assert id1 != id2  # UUIDs are globally unique
            >>> len(id1) == 36  # UUID format: 8-4-4-4-12 characters
            
            >>> generator_seq = MappingGenerator(id_strategy="sequential")
            >>> id1 = generator_seq.assign_mapping_id()
            >>> id2 = generator_seq.assign_mapping_id()
            >>> assert id1 == "MAP_0000000001"
            >>> assert id2 == "MAP_0000000002"
            >>> assert id1 < id2  # Sequential IDs are ordered
        """
        if self.id_strategy == "uuid":
            return str(uuid4())
        elif self.id_strategy == "sequential":
            self._sequence_counter += 1
            return f"MAP_{self._sequence_counter:010d}"
        else:
            raise ValueError(f"Unknown ID strategy: {self.id_strategy}")

    def _extract_wafer_info(self, wafer_id: str) -> tuple[str, int]:
        """Extract wafer family and batch number from wafer identifier.

        Analyzes wafer_id to determine family classification and batch number.
        For GOXTWS pattern wafers, extracts the batch number from the numeric suffix.
        For virtual wafers, marks family as "VIRTUAL" and returns batch=0.

        Args:
            wafer_id: Wafer identifier (e.g., "GOXTWS1125", "VW_abc123")

        Returns:
            Tuple of (wafer_family, wafer_batch):
            - wafer_family: Classification string ("GOXTWS", "VIRTUAL", or empty)
            - wafer_batch: Batch number as integer (0 if not determinable)

        Examples:
            >>> generator = MappingGenerator()
            >>> family, batch = generator._extract_wafer_info("GOXTWS1125")
            >>> assert family == "GOXTWS"
            >>> assert batch == 1125
            
            >>> family, batch = generator._extract_wafer_info("GOXTWS2135")
            >>> assert family == "GOXTWS"
            >>> assert batch == 2135
            
            >>> family, batch = generator._extract_wafer_info("VW_abc123def456")
            >>> assert family == "VIRTUAL"
            >>> assert batch == 0
        """
        if not wafer_id:
            return "", 0

        # Check cache first
        if wafer_id in self._wafer_family_cache:
            return self._wafer_family_cache[wafer_id]

        wafer_family = ""
        wafer_batch = 0

        # Virtual wafer pattern (VW_*)
        if wafer_id.startswith("VW_"):
            wafer_family = "VIRTUAL"
            wafer_batch = 0

        # GOXTWS pattern
        elif wafer_id.startswith("GOXTWS"):
            wafer_family = "GOXTWS"
            # Try to extract batch number from the numeric suffix
            try:
                # Remove "GOXTWS" prefix and convert remaining to int
                batch_str = wafer_id[6:]  # Length of "GOXTWS"
                if batch_str.isdigit():
                    wafer_batch = int(batch_str)
            except (ValueError, IndexError):
                wafer_batch = 0

        # Cache result for performance
        self._wafer_family_cache[wafer_id] = (wafer_family, wafer_batch)

        return wafer_family, wafer_batch

    def _get_current_iso8601_timestamp(self) -> str:
        """Get current timestamp in ISO 8601 format.

        Returns:
            str: Current UTC timestamp in ISO 8601 format
                 Format: "2026-07-14T13:34:33Z"

        Examples:
            >>> timestamp = generator._get_current_iso8601_timestamp()
            >>> assert "T" in timestamp  # ISO 8601 format
            >>> assert timestamp.endswith("Z")  # UTC timezone marker
        """
        now = datetime.now(timezone.utc)
        return now.strftime("%Y-%m-%dT%H:%M:%SZ")
