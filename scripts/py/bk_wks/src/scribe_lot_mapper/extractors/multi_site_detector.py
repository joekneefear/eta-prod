"""MultiSiteDetector component for detecting and expanding multi-site records.

Detects when a single record contains measurements from multiple scribe sites
and expands into separate records.

This component identifies records that contain measurements from multiple test
sites (up to 5 sites per record) and creates separate mapping records for each
site. This ensures that each scribe/die position is correctly mapped to its
corresponding lot and wafer number.

Example:
    A single workstream record might contain test values for 5 different scribes
    (c_value_1=55.1, c_value_2=4.9, c_value_3=5.7, c_value_4=5.7, c_value_5=5.4).
    The detector identifies 5 sites and expands into 5 separate records, one for
    each measurement, preserving all context (lot, wafer, equipment) for each.

Author: Manufacturing Data Team
"""

from typing import List

from scribe_lot_mapper.models import ParsedRecord


class MultiSiteDetector:
    """Detects and expands multi-site measurement records.

    A multi-site record is a single workstream record that contains test
    measurements for multiple scribe sites (1-5 sites). This is common in
    parallel test scenarios where multiple dice are tested simultaneously.

    The detector:
    - Identifies how many sites are in a record by counting non-empty c_value
      and d_value fields (max 5)
    - Expands multi-site records into N separate single-site records
    - Preserves all context (lot, wafer, equipment, test program, etc.)
    - Maintains parent-child relationships via parent_mapping_id for traceability

    Multi-Site Detection Logic:
    1. Count non-empty c_value fields (c_value_1 through c_value_5)
    2. Count non-empty d_value fields (d_value_1 through d_value_5)
    3. Site count = max(c_value count, d_value count)
    4. If site count > 1, record is multi-site and must be expanded

    Expansion Process:
    1. For each site index (0 to site_count-1):
       - Extract the value at that site index from each array
       - Create new ParsedRecord with:
         * All original fields preserved
         * c_values and d_values reduced to single value (that site's value)
         * site_number set to sequential index (1-5)
    2. Return list of expanded records (typically 1-5 records)

    Examples:
        >>> detector = MultiSiteDetector()
        
        # Single-site record - no expansion needed
        >>> single_site_record = ParsedRecord(
        ...     raw_line="...", parameter_set_id="GMBG3002",
        ...     c_values=["301.2"], d_values=["301.2"], ...
        ... )
        >>> expanded = detector.expand(single_site_record)
        >>> len(expanded)
        1
        
        # Multi-site record - expands to 5 records
        >>> multi_site = ParsedRecord(
        ...     raw_line="...", parameter_set_id="GMBG3002",
        ...     c_values=["55.1", "4.9", "5.7", "5.7", "5.4"],
        ...     d_values=["55.1", "4.9", "5.7", "5.7", "5.4"], ...
        ... )
        >>> expanded = detector.expand(multi_site)
        >>> len(expanded)
        5
        >>> expanded[0].c_values
        ['55.1']
        >>> expanded[1].c_values
        ['4.9']

    Attributes:
        MAX_SITES: Maximum number of sites per record (hardcoded to 5 per spec)
    """

    MAX_SITES = 5

    def __init__(self) -> None:
        """Initialize MultiSiteDetector."""
        pass

    def detect(self, record: ParsedRecord) -> int:
        """Detect number of sites in a record.

        Counts non-empty c_value and d_value fields to determine site count.
        Site count is the maximum of the two counts to handle cases where
        only text or only numeric values are present.

        Args:
            record: Parsed workstream record

        Returns:
            int: Number of sites detected (1-5, where 1 = single-site)
                 Returns minimum of 1 for empty or None records
        """
        if record is None:
            return 1

        c_count = sum(1 for v in record.c_values if v and v.strip())
        d_count = sum(1 for v in record.d_values if v and v.strip())
        return max(c_count, d_count, 1)

    def is_multi_site(self, record: ParsedRecord) -> bool:
        """Check if record is multi-site.

        A record is multi-site if it contains measurements from more than
        one scribe site (site count > 1).

        Args:
            record: Parsed workstream record

        Returns:
            bool: True if record contains multiple sites, False otherwise
        """
        return self.detect(record) > 1

    def expand(self, record: ParsedRecord) -> List[ParsedRecord]:
        """Expand multi-site record into separate records.

        Creates one record per detected site, preserving all context except
        site-specific values (c_values and d_values).

        For single-site records (or records with only 1 site detected), returns
        a list containing the original record unchanged.

        For multi-site records, creates N records (N = site count, max 5),
        each containing:
        - All original fields preserved (parameter_set_id, facility, unit_id, etc.)
        - c_values and d_values reduced to single value (that site's measurement)
        - site_number set to sequential index (1 through N)

        Expansion Example:
        Input: record with c_values=["55.1", "4.9", "5.7", "5.7", "5.4"]
               (5 sites)
        Output: 5 records with:
          - Record 1: c_values=["55.1"], d_values=["55.1"], site_number=1
          - Record 2: c_values=["4.9"], d_values=["4.9"], site_number=2
          - Record 3: c_values=["5.7"], d_values=["5.7"], site_number=3
          - Record 4: c_values=["5.7"], d_values=["5.7"], site_number=4
          - Record 5: c_values=["5.4"], d_values=["5.4"], site_number=5

        Args:
            record: Parsed workstream record (may be single or multi-site)

        Returns:
            List[ParsedRecord]: List of expanded records (1+ records)
                               If single-site: returns [record] (unchanged)
                               If multi-site: returns N records (one per site)

        Examples:
            >>> detector = MultiSiteDetector()
            
            # Single-site expansion (no change)
            >>> single = ParsedRecord(
            ...     raw_line="test", parameter_set_id="GMBG3002",
            ...     c_values=["301.2"], d_values=["301.2"],
            ...     parameter_set_version="", date_time="", facility="FB6",
            ...     parameter_name="", sequence_number=1, unit_id="LEFT",
            ...     type_id="THK-1-51T", limits_high="", limits_low="",
            ...     timestamp="2026-07-14T03:00:00Z"
            ... )
            >>> expanded = detector.expand(single)
            >>> len(expanded)
            1
            >>> expanded[0] is single
            True
            
            # Multi-site expansion (5 records)
            >>> multi = ParsedRecord(
            ...     raw_line="test", parameter_set_id="GMBG3002",
            ...     c_values=["55.1", "4.9", "5.7", "5.7", "5.4"],
            ...     d_values=["55.1", "4.9", "5.7", "5.7", "5.4"],
            ...     parameter_set_version="", date_time="", facility="FB6",
            ...     parameter_name="TEST", sequence_number=1, unit_id="",
            ...     type_id="THK-1-51T", limits_high="", limits_low="",
            ...     timestamp="2026-07-14T03:00:00Z"
            ... )
            >>> expanded = detector.expand(multi)
            >>> len(expanded)
            5
            >>> expanded[0].c_values
            ['55.1']
            >>> expanded[1].c_values
            ['4.9']
        """
        if record is None:
            return []

        site_count = self.detect(record)

        # If single-site, return original record unchanged
        if site_count == 1:
            return [record]

        # Multi-site: expand into N records
        expanded_records = []
        for site_index in range(site_count):
            expanded_record = self._create_expanded_record(
                original=record,
                site_index=site_index,
                site_number=site_index + 1,  # Convert 0-based to 1-based
            )
            expanded_records.append(expanded_record)

        return expanded_records

    def extract_site_values(
        self, record: ParsedRecord, site_index: int
    ) -> dict:
        """Extract values for a specific site from a record.

        Retrieves the measurement values (c_value and d_value) for a specific
        site index from the c_values and d_values arrays.

        Args:
            record: Parsed workstream record
            site_index: Site index (0-based, 0-4 for 5 sites)

        Returns:
            dict: Dictionary containing:
                - 'c_value': Text value from c_values[site_index] or empty string
                - 'd_value': Numeric value from d_values[site_index] or empty string
                - 'site_index': The site_index parameter

        Examples:
            >>> detector = MultiSiteDetector()
            >>> record = ParsedRecord(
            ...     c_values=["55.1", "4.9", "5.7"],
            ...     d_values=["55.1", "4.9", "5.7"],
            ...     # ... other required fields
            ... )
            >>> values_site_0 = detector.extract_site_values(record, 0)
            >>> values_site_0['c_value']
            '55.1'
            >>> values_site_0['d_value']
            '55.1'
            
            >>> values_site_1 = detector.extract_site_values(record, 1)
            >>> values_site_1['c_value']
            '4.9'
        """
        c_value = ""
        d_value = ""

        # Extract c_value if index is within bounds
        if site_index < len(record.c_values):
            c_value = record.c_values[site_index] or ""

        # Extract d_value if index is within bounds
        if site_index < len(record.d_values):
            d_value = record.d_values[site_index] or ""

        return {
            "c_value": c_value,
            "d_value": d_value,
            "site_index": site_index,
        }

    def _create_expanded_record(
        self,
        original: ParsedRecord,
        site_index: int,
        site_number: int,
    ) -> ParsedRecord:
        """Create expanded record for a specific site.

        Creates a new ParsedRecord with all original fields preserved except
        c_values and d_values, which are reduced to a single value (the site's
        measurement). This ensures each expanded record represents a single site.

        Args:
            original: Original multi-site record
            site_index: Index of site in value arrays (0-based, 0-4)
            site_number: Site number for output (1-based, 1-5)

        Returns:
            ParsedRecord: Expanded record for single site with:
                - All original fields preserved
                - c_values reduced to [site_c_value]
                - d_values reduced to [site_d_value]

        Examples:
            >>> detector = MultiSiteDetector()
            >>> record = ParsedRecord(
            ...     raw_line="test", parameter_set_id="GMBG3002",
            ...     c_values=["55.1", "4.9", "5.7"],
            ...     d_values=["55.1", "4.9", "5.7"],
            ...     parameter_set_version="v1", date_time="JUL 14 2026",
            ...     facility="FB6", parameter_name="TEST", sequence_number=1,
            ...     unit_id="", type_id="THK-1-51T", limits_high="",
            ...     limits_low="", timestamp="2026-07-14T03:00:00Z"
            ... )
            >>> expanded_1 = detector._create_expanded_record(record, 0, 1)
            >>> expanded_1.c_values
            ['55.1']
            >>> expanded_1.d_values
            ['55.1']
            
            >>> expanded_2 = detector._create_expanded_record(record, 1, 2)
            >>> expanded_2.c_values
            ['4.9']
            >>> expanded_2.d_values
            ['4.9']
        """
        # Extract site-specific values
        site_values = self.extract_site_values(original, site_index)
        c_value = site_values["c_value"]
        d_value = site_values["d_value"]

        # Create expanded record with single site values
        expanded = ParsedRecord(
            raw_line=original.raw_line,
            parameter_set_id=original.parameter_set_id,
            parameter_set_version=original.parameter_set_version,
            date_time=original.date_time,
            facility=original.facility,
            parameter_name=original.parameter_name,
            sequence_number=original.sequence_number,
            unit_id=original.unit_id,
            type_id=original.type_id,
            c_values=[c_value] if c_value else [],
            d_values=[d_value] if d_value else [],
            limits_high=original.limits_high,
            limits_low=original.limits_low,
            timestamp=original.timestamp,
        )

        return expanded
