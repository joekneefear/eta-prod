"""CSV output generator.

Generates CSV formatted mapping output.
"""

import csv
import logging
from pathlib import Path
from typing import List

from scribe_lot_mapper.generators.base import OutputGenerator
from scribe_lot_mapper.models import MappingRecord

logger = logging.getLogger(__name__)


class CSVGenerator(OutputGenerator):
    """Generates CSV output for mapping records.

    Output includes headers and all mapping fields with proper escaping
    for special characters.

    Uses Python's csv module for robust handling of special characters,
    embedded newlines, and proper quoting.
    """

    HEADERS = [
        "mapping_id",
        "scribe_id",
        "lot_id",
        "wafer_id",
        "wafer_family",
        "wafer_batch",
        "test_program",
        "test_value",
        "equipment_id",
        "facility",
        "sequence_number",
        "site_number",
        "unit_id",
        "timestamp",
        "created_at",
        "validation_status",
    ]

    def __init__(self, output_dir: str | Path) -> None:
        """Initialize CSVGenerator.

        Args:
            output_dir: Directory for output files
        """
        super().__init__(output_dir)

    def generate(self, records: List[MappingRecord], filename: str = "mappings.csv") -> None:
        """Generate CSV output file.

        Writes mapping records to CSV file with proper escaping. Uses csv.DictWriter
        for robust handling of special characters and embedded newlines.

        Args:
            records: List of mapping records to output
            filename: Output filename (default: mappings.csv)

        Raises:
            IOError: If file cannot be written
        """
        output_path = self.get_output_path(filename)

        try:
            with open(output_path, "w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=self.HEADERS, quoting=csv.QUOTE_MINIMAL)

                # Write header row
                writer.writeheader()

                # Write data rows
                for record in records:
                    writer.writerow(self._record_to_dict(record))

            logger.info(f"Generated CSV output: {output_path} ({len(records)} records)")

        except IOError as e:
            logger.error(f"Failed to write CSV file {output_path}: {str(e)}")
            raise

    def write_headers(self) -> None:
        """Write CSV headers.

        This is a no-op for CSV generation since headers are written
        with generate() method. Provided for interface compliance.
        """
        pass

    def _record_to_dict(self, record: MappingRecord) -> dict:
        """Convert MappingRecord to dictionary for CSV output.

        Args:
            record: MappingRecord to convert

        Returns:
            Dictionary with CSV field names as keys
        """
        return {
            "mapping_id": record.mapping_id,
            "scribe_id": record.scribe_id,
            "lot_id": record.lot_id,
            "wafer_id": record.wafer_id,
            "wafer_family": record.wafer_family,
            "wafer_batch": record.wafer_batch,
            "test_program": record.test_program,
            "test_value": record.test_value,
            "equipment_id": record.equipment_id,
            "facility": record.facility,
            "sequence_number": record.sequence_number,
            "site_number": record.site_number,
            "unit_id": record.unit_id,
            "timestamp": record.timestamp,
            "created_at": record.created_at,
            "validation_status": record.validation_status,
        }
