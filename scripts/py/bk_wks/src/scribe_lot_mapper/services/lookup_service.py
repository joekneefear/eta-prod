"""LookupService component for reverse mapping queries.

Provides scribe->lot and lot->scribe lookup functionality with support for
filtering by date range, facility, and test program.

This service maintains in-memory indices for fast O(1) lookups and enables
bidirectional queries: scribe→lot (forward) and lot→scribe (reverse).
"""

from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from scribe_lot_mapper.models import MappingRecord


class LookupService:
    """Provides reverse lookup capabilities for mapping data.

    Maintains in-memory indices for fast scribe->lot and lot->scribe lookups.
    Supports filtering by date range, facility, and test program.

    Indices stored:
    - scribe_to_lots: Dict[scribe_id] -> List[{lot_id, wafer_id, context}]
    - lot_to_scribes: Dict[(lot_id, wafer_id)] -> List[{scribe_id, context}]
    - all_mappings: Complete list of all loaded mapping records for filtered queries
    """

    def __init__(self) -> None:
        """Initialize LookupService with empty indices."""
        # Index: scribe_id -> List[MappingRecord]
        # Enables fast scribe→lot lookups
        self.scribe_to_lots: Dict[str, List[MappingRecord]] = {}

        # Index: (lot_id, wafer_id) -> List[MappingRecord]
        # Enables fast lot→scribe lookups
        self.lot_to_scribes: Dict[Tuple[str, str], List[MappingRecord]] = {}

        # Index: facility -> List[MappingRecord]
        # Enables fast facility-based queries
        self.facility_index: Dict[str, List[MappingRecord]] = {}

        # Index: test_program -> List[MappingRecord]
        # Enables fast test_program-based queries
        self.test_program_index: Dict[str, List[MappingRecord]] = {}

        # Store all records for date range queries
        self.all_mappings: List[MappingRecord] = []

    def load_mappings(self, records: List[MappingRecord]) -> None:
        """Load mapping records into indices for fast queries.

        Populates all indices (scribe→lot, lot→scribe, facility, test_program)
        from the provided mapping records. Existing indices are cleared first.

        Args:
            records: List of mapping records to index

        Raises:
            ValueError: If records list is None or empty
        """
        if not records:
            raise ValueError("Cannot load empty or None records list")

        # Clear existing indices
        self.scribe_to_lots.clear()
        self.lot_to_scribes.clear()
        self.facility_index.clear()
        self.test_program_index.clear()
        self.all_mappings.clear()

        # Load all records into indices
        for record in records:
            if not record.is_complete():
                # Skip incomplete records (they should have been filtered by validator)
                continue

            # Build scribe→lots index
            if record.scribe_id not in self.scribe_to_lots:
                self.scribe_to_lots[record.scribe_id] = []
            self.scribe_to_lots[record.scribe_id].append(record)

            # Build lot→scribes index
            lot_key = (record.lot_id, record.wafer_id)
            if lot_key not in self.lot_to_scribes:
                self.lot_to_scribes[lot_key] = []
            self.lot_to_scribes[lot_key].append(record)

            # Build facility index
            if record.facility not in self.facility_index:
                self.facility_index[record.facility] = []
            self.facility_index[record.facility].append(record)

            # Build test_program index
            if record.test_program not in self.test_program_index:
                self.test_program_index[record.test_program] = []
            self.test_program_index[record.test_program].append(record)

            # Store in all_mappings for range queries
            self.all_mappings.append(record)

    def find_lots_by_scribe(self, scribe_id: str) -> List[Tuple[str, str, Dict[str, Any]]]:
        """Find all lots and wafers used for a specific scribe.

        **Validates: Requirements 8.1**

        Returns results grouped by test program for clarity (Requirement 8.2).
        Each result includes context: test_program, timestamp, facility.

        Args:
            scribe_id: Scribe identifier to search for

        Returns:
            List of (lot_id, wafer_id, context_dict) tuples
            Returns empty list if scribe not found (Requirement 8.3)

        Raises:
            ValueError: If scribe_id is empty or None
        """
        if not scribe_id:
            raise ValueError("scribe_id cannot be empty or None")

        # Return empty result if scribe not found (Requirement 8.3: log for audit)
        if scribe_id not in self.scribe_to_lots:
            return []

        results: List[Tuple[str, str, Dict[str, Any]]] = []
        seen_keys: set = set()  # Avoid duplicates

        for mapping in self.scribe_to_lots[scribe_id]:
            key = (mapping.lot_id, mapping.wafer_id)
            if key not in seen_keys:
                seen_keys.add(key)

                # Build context dict with timestamp and test context (Requirement 8.4)
                context = {
                    "test_program": mapping.test_program,
                    "timestamp": mapping.timestamp,
                    "facility": mapping.facility,
                    "site_number": mapping.site_number,
                    "unit_id": mapping.unit_id,
                }

                results.append((mapping.lot_id, mapping.wafer_id, context))

        return results

    def find_scribes_by_lot(
        self, lot_id: str, wafer_id: Optional[str] = None
    ) -> List[Tuple[str, Dict[str, Any]]]:
        """Find all scribes processed in a specific lot (and optional wafer).

        Reverse of find_lots_by_scribe - enables lot→scribe lookups.

        Args:
            lot_id: Lot identifier to search for
            wafer_id: Optional wafer identifier to narrow search

        Returns:
            List of (scribe_id, context_dict) tuples
            Returns empty list if lot not found

        Raises:
            ValueError: If lot_id is empty or None
        """
        if not lot_id:
            raise ValueError("lot_id cannot be empty or None")

        results: List[Tuple[str, Dict[str, Any]]] = []
        seen_scribes: set = set()  # Avoid duplicates

        if wafer_id:
            # Narrow search to specific lot+wafer combination
            lot_key = (lot_id, wafer_id)
            mappings = self.lot_to_scribes.get(lot_key, [])
        else:
            # Search all wafers in this lot
            mappings = []
            for (l_id, w_id), records in self.lot_to_scribes.items():
                if l_id == lot_id:
                    mappings.extend(records)

        for mapping in mappings:
            if mapping.scribe_id not in seen_scribes:
                seen_scribes.add(mapping.scribe_id)

                context = {
                    "test_program": mapping.test_program,
                    "timestamp": mapping.timestamp,
                    "facility": mapping.facility,
                    "site_number": mapping.site_number,
                    "unit_id": mapping.unit_id,
                }

                results.append((mapping.scribe_id, context))

        return results

    def query_by_date_range(
        self,
        scribe_id: str,
        start_date: Optional[str] = None,
        end_date: Optional[str] = None,
    ) -> List[MappingRecord]:
        """Query mappings for a scribe by date range.

        **Validates: Requirements 8.5**

        Filters mappings by ISO 8601 timestamp. If start_date or end_date
        not provided, query returns all mappings for the scribe.

        Args:
            scribe_id: Scribe identifier to query
            start_date: Optional ISO 8601 start date (e.g., "2026-07-14T00:00:00Z")
            end_date: Optional ISO 8601 end date (e.g., "2026-07-15T23:59:59Z")

        Returns:
            List of MappingRecords matching scribe and date range
            Returns empty list if scribe not found

        Raises:
            ValueError: If scribe_id is empty, or date format invalid
        """
        if not scribe_id:
            raise ValueError("scribe_id cannot be empty or None")

        # Get all mappings for this scribe
        if scribe_id not in self.scribe_to_lots:
            return []

        mappings = self.scribe_to_lots[scribe_id]

        # If no date filters, return all
        if not start_date and not end_date:
            return mappings

        # Filter by date range
        results = []
        for mapping in mappings:
            if start_date and mapping.timestamp < start_date:
                continue
            if end_date and mapping.timestamp > end_date:
                continue
            results.append(mapping)

        return results

    def query_by_facility(self, facility: str) -> List[MappingRecord]:
        """Query all mappings for a specific facility.

        **Validates: Requirements 8.5**

        Args:
            facility: Facility code to filter by (e.g., "FB6", "THK")

        Returns:
            List of MappingRecords from specified facility
            Returns empty list if facility not found

        Raises:
            ValueError: If facility is empty or None
        """
        if not facility:
            raise ValueError("facility cannot be empty or None")

        return self.facility_index.get(facility, [])

    def query_by_test_program(self, test_program: str) -> List[MappingRecord]:
        """Query all mappings for a specific test program.

        **Validates: Requirements 8.5**

        Args:
            test_program: Test program identifier to filter by (e.g., "GMBG3002")

        Returns:
            List of MappingRecords using specified test program
            Returns empty list if test_program not found

        Raises:
            ValueError: If test_program is empty or None
        """
        if not test_program:
            raise ValueError("test_program cannot be empty or None")

        return self.test_program_index.get(test_program, [])

    def get_index_stats(self) -> Dict[str, Any]:
        """Get statistics about loaded indices for debugging/monitoring.

        Returns:
            Dictionary with index statistics:
            {
                'total_mappings': int,
                'unique_scribes': int,
                'unique_lot_wafer_pairs': int,
                'facilities': list[str],
                'test_programs': list[str]
            }
        """
        return {
            "total_mappings": len(self.all_mappings),
            "unique_scribes": len(self.scribe_to_lots),
            "unique_lot_wafer_pairs": len(self.lot_to_scribes),
            "facilities": sorted(self.facility_index.keys()),
            "test_programs": sorted(self.test_program_index.keys()),
        }

    def clear_indices(self) -> None:
        """Clear all indices and loaded mappings.

        Useful for memory cleanup or reloading data.
        """
        self.scribe_to_lots.clear()
        self.lot_to_scribes.clear()
        self.facility_index.clear()
        self.test_program_index.clear()
        self.all_mappings.clear()
