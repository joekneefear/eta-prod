"""IFF (Internal File Format) output generator.

Generates IFF formatted output for workstream format.
"""

import logging
from pathlib import Path
from typing import List

from scribe_lot_mapper.generators.base import OutputGenerator
from scribe_lot_mapper.models import MappingRecord

logger = logging.getLogger(__name__)


class IFFGenerator(OutputGenerator):
    """Generates IFF output for workstream format.

    Output follows workstream standard with vertical tab separators and
    proper headers for integration with workstream processing systems.

    IFF (Internal File Format) uses:
    - Vertical tab (ASCII 11, \\x0B) as field separator
    - Line feed (ASCII 10, \\n) as record separator
    - Header records starting with ## for metadata
    """

    # IFF uses vertical tab (ASCII 11) as field separator
    FIELD_SEPARATOR = chr(11)
    # IFF uses line feed (ASCII 10) as record separator
    RECORD_SEPARATOR = "\n"

    # Header field names for IFF output
    HEADER_FIELDS = [
        "MAPPING_ID",
        "SCRIBE_ID",
        "LOT_ID",
        "WAFER_ID",
        "WAFER_FAMILY",
        "WAFER_BATCH",
        "TEST_PROGRAM",
        "TEST_VALUE",
        "EQUIPMENT_ID",
        "FACILITY",
        "SEQUENCE_NUMBER",
        "SITE_NUMBER",
        "UNIT_ID",
        "TIMESTAMP",
        "CREATED_AT",
        "VALIDATION_STATUS",
    ]

    def __init__(self, output_dir: str | Path) -> None:
        """Initialize IFFGenerator.

        Args:
            output_dir: Directory for output files
        """
        super().__init__(output_dir)

    def generate(self, records: List[MappingRecord], filename: str = "mappings.iff") -> None:
        """Generate IFF output file.

        Writes mapping records to IFF format with workstream-compatible headers
        and vertical tab field separators.

        Args:
            records: List of mapping records to output
            filename: Output filename (default: mappings.iff)

        Raises:
            IOError: If file cannot be written
        """
        output_path = self.get_output_path(filename)

        try:
            with open(output_path, "w", encoding="utf-8") as f:
                # Write metadata header
                self._write_metadata_header(f, len(records))

                # Write column header row
                self._write_header_row(f)

                # Write data rows
                for record in records:
                    self._write_data_row(f, record)

            logger.info(f"Generated IFF output: {output_path} ({len(records)} records)")

        except IOError as e:
            logger.error(f"Failed to write IFF file {output_path}: {str(e)}")
            raise

    def write_headers(self) -> None:
        """Write IFF headers.

        This is a no-op for IFF generation since headers are written
        with generate() method. Provided for interface compliance.
        """
        pass

    def _write_metadata_header(self, file, record_count: int) -> None:
        """Write IFF metadata header.

        Args:
            file: File object to write to
            record_count: Number of data records in output
        """
        file.write(f"## SCRIBE-LOT-WAFER MAPPING OUTPUT{self.RECORD_SEPARATOR}")
        file.write(f"## FORMAT: IFF{self.RECORD_SEPARATOR}")
        file.write(f"## TOTAL_RECORDS: {record_count}{self.RECORD_SEPARATOR}")
        file.write(f"## FIELD_SEPARATOR: VERTICAL_TAB (ASCII 11){self.RECORD_SEPARATOR}")

    def _write_header_row(self, file) -> None:
        """Write IFF column header row.

        Args:
            file: File object to write to
        """
        header_line = self.FIELD_SEPARATOR.join(self.HEADER_FIELDS)
        file.write(f"#{header_line}{self.RECORD_SEPARATOR}")

    def _write_data_row(self, file, record: MappingRecord) -> None:
        """Write single data row in IFF format.

        Args:
            file: File object to write to
            record: MappingRecord to write
        """
        values = [
            record.mapping_id,
            record.scribe_id,
            record.lot_id,
            record.wafer_id,
            record.wafer_family or "",
            str(record.wafer_batch),
            record.test_program,
            record.test_value or "",
            record.equipment_id,
            record.facility,
            str(record.sequence_number),
            str(record.site_number),
            record.unit_id or "",
            record.timestamp,
            record.created_at,
            record.validation_status,
        ]

        # Escape vertical tabs in values if present (unlikely but defensive)
        escaped_values = [v.replace(self.FIELD_SEPARATOR, " ") if isinstance(v, str) else str(v) for v in values]

        row_line = self.FIELD_SEPARATOR.join(escaped_values)
        file.write(f"{row_line}{self.RECORD_SEPARATOR}")
