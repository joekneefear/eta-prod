"""JSON output generator.

Generates JSON formatted mapping output with hierarchical structure.
"""

import json
import logging
from pathlib import Path
from typing import List

from scribe_lot_mapper.generators.base import OutputGenerator
from scribe_lot_mapper.models import MappingRecord

logger = logging.getLogger(__name__)


class JSONGenerator(OutputGenerator):
    """Generates JSON output for mapping records.

    Output includes hierarchical structure organizing mappings by relationships.
    Provides both flat array format (for compatibility) and nested format
    (for relationship clarity).
    """

    def __init__(self, output_dir: str | Path, indent: int = 2) -> None:
        """Initialize JSONGenerator.

        Args:
            output_dir: Directory for output files
            indent: JSON indentation level (default: 2)
        """
        super().__init__(output_dir)
        self.indent = indent

    def generate(self, records: List[MappingRecord], filename: str = "mappings.json") -> None:
        """Generate JSON output file.

        Writes mapping records to JSON file with hierarchical structure.
        Groups by scribe, then by lot/wafer relationships.

        Args:
            records: List of mapping records to output
            filename: Output filename (default: mappings.json)

        Raises:
            IOError: If file cannot be written
        """
        output_path = self.get_output_path(filename)

        try:
            # Convert records to hierarchical structure
            hierarchy = self._build_hierarchy(records)

            with open(output_path, "w", encoding="utf-8") as f:
                json.dump(hierarchy, f, indent=self.indent, ensure_ascii=False)

            logger.info(f"Generated JSON output: {output_path} ({len(records)} records)")

        except IOError as e:
            logger.error(f"Failed to write JSON file {output_path}: {str(e)}")
            raise
        except (TypeError, ValueError) as e:
            logger.error(f"Failed to serialize JSON for {output_path}: {str(e)}")
            raise

    def write_headers(self) -> None:
        """Write JSON headers (no-op for JSON).

        JSON format doesn't require separate headers. Provided for interface compliance.
        """
        pass

    def _build_hierarchy(self, records: List[MappingRecord]) -> dict:
        """Build hierarchical structure from flat records.

        Groups records by scribe → lot/wafer relationships, providing
        both navigational structure and context.

        Args:
            records: List of mapping records

        Returns:
            Dictionary with hierarchical organization:
            {
              "metadata": {...},
              "by_scribe": {
                "scribe_id": {
                  "lots": [
                    {
                      "lot_id": "...",
                      "wafers": [...],
                      "mappings": [...]
                    }
                  ]
                }
              },
              "mappings": [...]  # Flat array for compatibility
            }
        """
        scribe_map = {}

        # Build nested structure
        for record in records:
            if record.scribe_id not in scribe_map:
                scribe_map[record.scribe_id] = {}

            scribe_info = scribe_map[record.scribe_id]
            lot_key = record.lot_id

            if lot_key not in scribe_info:
                scribe_info[lot_key] = {"lot_id": lot_key, "wafers": set(), "mappings": []}

            scribe_info[lot_key]["wafers"].add(record.wafer_id)
            scribe_info[lot_key]["mappings"].append(self._record_to_dict(record))

        # Convert nested structure to output format
        by_scribe = {}
        for scribe_id, lot_data in scribe_map.items():
            lots_list = []
            for lot_id, lot_info in lot_data.items():
                lots_list.append(
                    {
                        "lot_id": lot_info["lot_id"],
                        "wafers": sorted(list(lot_info["wafers"])),
                        "mappings": lot_info["mappings"],
                    }
                )
            by_scribe[scribe_id] = {"lots": lots_list}

        return {
            "metadata": {
                "total_records": len(records),
                "unique_scribes": len(scribe_map),
                "unique_lots": len(set(r.lot_id for r in records)),
                "unique_wafers": len(set(r.wafer_id for r in records)),
            },
            "by_scribe": by_scribe,
            "mappings": [self._record_to_dict(r) for r in records],
        }

    def _record_to_dict(self, record: MappingRecord) -> dict:
        """Convert MappingRecord to dictionary for JSON output.

        Args:
            record: MappingRecord to convert

        Returns:
            Dictionary representation of record
        """
        return {
            "mapping_id": record.mapping_id,
            "scribe": {
                "id": record.scribe_id,
                "equipment": record.equipment_id,
                "unit_id": record.unit_id,
                "site_number": record.site_number,
            },
            "lot": {
                "id": record.lot_id,
                "wafer": record.wafer_id,
                "wafer_family": record.wafer_family,
                "wafer_batch": record.wafer_batch,
            },
            "test": {
                "program": record.test_program,
                "value": record.test_value,
                "sequence_number": record.sequence_number,
                "timestamp": record.timestamp,
            },
            "metadata": {
                "facility": record.facility,
                "validation_status": record.validation_status,
                "created_at": record.created_at,
            },
        }
