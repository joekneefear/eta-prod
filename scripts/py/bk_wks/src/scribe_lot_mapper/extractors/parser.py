"""Parser component for extracting and normalizing record fields.

Parses individual workstream records according to format specification and
normalizes field values.
"""

import re
from typing import Any, Dict, List, Optional

from scribe_lot_mapper.exceptions import ParsingError
from scribe_lot_mapper.models import ParsedRecord


class Parser:
    """Extracts and normalizes fields from workstream records.

    Handles:
    - Field extraction according to format spec
    - Whitespace and special character normalization
    - Empty value handling
    - Field type conversion
    - Multi-value field parsing (c_value, d_value arrays)

    Attributes:
        format_spec: Format specification for field positions/types
        empty_marker: Value to use for empty fields
    """

    def __init__(
        self, format_spec: Optional[Dict[str, Any]] = None, empty_marker: str = "N/A"
    ) -> None:
        """Initialize Parser.

        Args:
            format_spec: Format specification dictionary with field definitions
            empty_marker: Marker for empty fields (default: "N/A")
        """
        self.format_spec = format_spec or {}
        self.empty_marker = empty_marker

    def parse_bcp_record(
        self, bcp_fields: dict, line_number: int = 0
    ) -> ParsedRecord:
        """Parse a BCP-extracted field dictionary into a ParsedRecord.
        
        Used when BCP parser has already extracted fields according to format spec.
        
        Args:
            bcp_fields: Dictionary of field names to values from BCP parser
            line_number: Line number for error reporting
            
        Returns:
            ParsedRecord with extracted fields
            
        Raises:
            ParsingError: If record cannot be constructed
        """
        try:
            # Extract multi-value fields (c_value, d_value arrays)
            c_values = []
            for i in range(1, 6):
                key = f"c_value_{i}"
                c_values.append(bcp_fields.get(key, ""))
            
            d_values = []
            for i in range(1, 6):
                key = f"d_value_{i}"
                d_values.append(bcp_fields.get(key, ""))
            
            # Create ParsedRecord
            record = ParsedRecord(
                raw_line="",  # BCP already parsed, no raw line
                parameter_set_id=bcp_fields.get("parameter_set_id", ""),
                parameter_set_version=bcp_fields.get("parameter_set_version", ""),
                date_time=bcp_fields.get("date_time", ""),
                facility=bcp_fields.get("facility", ""),
                parameter_name=bcp_fields.get("parameter_name", ""),
                sequence_number=self._parse_int(bcp_fields.get("sequence_number", "1")),
                unit_id=bcp_fields.get("unit_id", ""),
                type_id=bcp_fields.get("type_id", ""),
                c_values=c_values,
                d_values=d_values,
                limits_high=bcp_fields.get("high_shutdown_limit", ""),
                limits_low=bcp_fields.get("low_shutdown_limit", ""),
                timestamp=bcp_fields.get("date_time", ""),
            )
            
            return record
        
        except Exception as e:
            raise ParsingError(
                f"Failed to parse BCP record: {str(e)}",
                line_number=line_number,
                error_code="PARSE_001"
            ) from e

    def parse_record(
        self, line: str, delimiter: str = "\t", line_number: int = 0
    ) -> ParsedRecord:
        """Parse a single record line into structured fields.

        Splits the line by delimiter, extracts fields according to format spec,
        normalizes values, and handles multi-value fields (c_value, d_value arrays).

        Args:
            line: Raw record line from file
            delimiter: Field delimiter (default: tab)
            line_number: Line number for error reporting (optional)

        Returns:
            ParsedRecord: Parsed and extracted fields

        Raises:
            ParsingError: If record cannot be parsed or required fields missing
        """
        try:
            # Split record by delimiter
            fields = line.split(delimiter)

            # Extract individual fields from parsed columns
            extracted = self._extract_fields_from_line(fields, line_number)

            # Extract multi-value fields (c_value_1-5, d_value_1-5)
            c_values = self._extract_c_values(extracted)
            d_values = self._extract_d_values(extracted)

            # Create ParsedRecord with all extracted fields
            record = ParsedRecord(
                raw_line=line,
                parameter_set_id=extracted.get("parameter_set_id", ""),
                parameter_set_version=extracted.get("parameter_set_version", ""),
                date_time=extracted.get("date_time", ""),
                facility=extracted.get("facility", ""),
                parameter_name=extracted.get("parameter_name", ""),
                sequence_number=self._parse_int(extracted.get("sequence_number", "1")),
                unit_id=extracted.get("unit_id", ""),
                type_id=extracted.get("type_id", ""),
                c_values=c_values,
                d_values=d_values,
                limits_high=extracted.get("limits_high", ""),
                limits_low=extracted.get("limits_low", ""),
                timestamp=extracted.get("timestamp", ""),
            )

            return record

        except ParsingError:
            raise
        except Exception as e:
            raise ParsingError(
                f"Failed to parse record: {str(e)}",
                line_number=line_number,
                error_code="PARSE_001",
            ) from e

    def parse_field(
        self, field_value: str, field_type: str = "VARCHAR"
    ) -> Any:
        """Parse a single field according to its type.

        Handles type conversion and validation for different field types.

        Args:
            field_value: Raw field value from record
            field_type: Data type identifier (VARCHAR, INT, FLOAT, DATETIME, etc.)

        Returns:
            Parsed field value with appropriate type

        Raises:
            ParsingError: If type conversion fails
        """
        # Normalize first
        normalized = self.normalize_value(field_value)

        if normalized == self.empty_marker or normalized == "":
            return normalized

        # Type-specific parsing
        if field_type.upper() == "INT" or field_type.upper() == "INTEGER":
            return self._parse_int(normalized)
        elif field_type.upper() == "FLOAT" or field_type.upper() == "DECIMAL":
            return self._parse_float(normalized)
        elif field_type.upper() == "DATETIME":
            return normalized  # Keep as string, timestamp normalization is separate
        else:
            # Default: VARCHAR - return normalized string
            return normalized

    def normalize_value(self, value: str) -> str:
        """Normalize field value (whitespace, special chars, etc.).

        Handles:
        - Empty or whitespace-only values
        - Leading/trailing whitespace removal
        - Special character normalization
        - Preserves quoted content

        Args:
            value: Raw field value

        Returns:
            str: Normalized value

        Raises:
            ParsingError: If value cannot be normalized
        """
        if not value:
            return self.empty_marker

        # Strip leading/trailing whitespace
        normalized = value.strip()

        # Handle empty after strip
        if not normalized:
            return self.empty_marker

        # Remove quotes if present (both single and double)
        if (normalized.startswith('"') and normalized.endswith('"')) or (
            normalized.startswith("'") and normalized.endswith("'")
        ):
            normalized = normalized[1:-1].strip()

        # Handle tabs and other whitespace within field
        # Preserve single spaces, collapse multiple spaces
        normalized = re.sub(r"\s+", " ", normalized)

        # Final empty check after all normalization
        if not normalized:
            return self.empty_marker

        return normalized

    def _extract_fields_from_line(
        self, fields: List[str], line_number: int = 0
    ) -> Dict[str, str]:
        """Extract fields from parsed line according to format spec.

        Maps field positions to field names using format specification.

        Args:
            fields: List of field values from line split
            line_number: Line number for error reporting

        Returns:
            Dict mapping field names to their values
        """
        extracted: Dict[str, str] = {}

        # If no format spec, use position-based extraction
        if not self.format_spec or "fields" not in self.format_spec:
            # Use standard positions for PHIST format
            position_map = {
                0: "parameter_set_id",
                1: "parameter_set_version",
                2: "date_time",
                3: "work_week",
                4: "facility",
                5: "parameter_name",
                6: "sequence_number",
                7: "unit_id",
                8: "type_id",
                9: "c_value_1",
                10: "c_value_2",
                11: "c_value_3",
                12: "c_value_4",
                13: "c_value_5",
                14: "d_value_1",
                15: "d_value_2",
                16: "d_value_3",
                17: "d_value_4",
                18: "d_value_5",
                19: "limits_high",
                20: "limits_low",
            }

            for idx, field_name in position_map.items():
                if idx < len(fields):
                    extracted[field_name] = self.normalize_value(fields[idx])
                else:
                    extracted[field_name] = self.empty_marker

        else:
            # Use format spec to map fields
            for field_name, field_def in self.format_spec.get("fields", {}).items():
                # Get field position (1-based from spec, convert to 0-based index)
                position = field_def.get("column_index", field_def.get("position", 1) - 1)

                if position < len(fields):
                    field_value = fields[position]
                    field_type = field_def.get("type", "VARCHAR")
                    extracted[field_name] = self.parse_field(field_value, field_type)
                else:
                    extracted[field_name] = self.empty_marker

        return extracted

    def _extract_c_values(self, extracted: Dict[str, str]) -> List[str]:
        """Extract c_value array (1-5) from extracted fields.

        Args:
            extracted: Dictionary of extracted fields

        Returns:
            List of c_value strings (empty values included)
        """
        c_values = []
        for i in range(1, 6):
            key = f"c_value_{i}"
            if key in extracted:
                c_values.append(extracted[key])
            else:
                c_values.append(self.empty_marker)
        return c_values

    def _extract_d_values(self, extracted: Dict[str, str]) -> List[str]:
        """Extract d_value array (1-5) from extracted fields.

        Args:
            extracted: Dictionary of extracted fields

        Returns:
            List of d_value strings (empty values included)
        """
        d_values = []
        for i in range(1, 6):
            key = f"d_value_{i}"
            if key in extracted:
                d_values.append(extracted[key])
            else:
                d_values.append(self.empty_marker)
        return d_values

    def _parse_int(self, value: str) -> int:
        """Parse integer field value.

        Args:
            value: String value to parse

        Returns:
            int: Parsed integer

        Raises:
            ParsingError: If value cannot be converted to int
        """
        if not value or value == self.empty_marker:
            return 0

        try:
            return int(value.strip())
        except ValueError:
            # Try to extract leading digits
            match = re.match(r"^(-?\d+)", value.strip())
            if match:
                return int(match.group(1))
            return 0

    def _parse_float(self, value: str) -> float:
        """Parse float field value.

        Args:
            value: String value to parse

        Returns:
            float: Parsed float

        Raises:
            ParsingError: If value cannot be converted to float
        """
        if not value or value == self.empty_marker:
            return 0.0

        try:
            return float(value.strip())
        except ValueError:
            # Try to extract leading float
            match = re.match(r"^(-?\d+\.?\d*)", value.strip())
            if match:
                return float(match.group(1))
            return 0.0
