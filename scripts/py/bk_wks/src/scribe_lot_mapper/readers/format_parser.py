"""FormatSpecParser component for parsing BCP format specifications.

Parses .bcp_fmt files to extract column definitions and field mappings.

BCP format files follow this structure:
- Lines with [field_name] = column_position, data_type, length
- Comments starting with #
- Tab-delimited field definitions

Example:
    parameter_set_id = 1, VARCHAR, 20
    facility = 5, VARCHAR, 10
"""

from pathlib import Path
from typing import Any, Dict, Optional

from scribe_lot_mapper.exceptions import ParsingError


class FormatSpecParser:
    """Parses BCP format specification files.

    BCP format specifications define field positions, types, and delimiters
    for workstream extract files. Specifications are cached for reuse.

    Attributes:
        filepath: Path to .bcp_fmt file
        spec: Parsed format specification dictionary
        _field_definitions: Cached field definitions by name
        _cache: Class-level cache for parsed specs
    """

    # Class-level cache for format specs
    _cache: Dict[str, Dict[str, Any]] = {}

    STANDARD_PHIST_FIELDS = [
        "parameter_set_id",
        "parameter_set_version",
        "date_time",
        "work_week",
        "facility",
        "parameter_name",
        "sequence_number",
        "unit_id",
        "type_id",
        "c_value_1",
        "c_value_2",
        "c_value_3",
        "c_value_4",
        "c_value_5",
        "d_value_1",
        "d_value_2",
        "d_value_3",
        "d_value_4",
        "d_value_5",
        "limits_high",
        "limits_low",
    ]

    def __init__(self, filepath: Optional[str | Path] = None) -> None:
        """Initialize FormatSpecParser.

        Args:
            filepath: Path to .bcp_fmt format specification file
                     If None, uses standard PHIST field definitions

        Raises:
            ParsingError: If specification file cannot be parsed
        """
        self.filepath = Path(filepath) if filepath else None
        self.spec: Dict[str, Any] = {}
        self._field_definitions: Dict[str, Dict[str, Any]] = {}

        if filepath:
            # Parse from file
            self._parse_file()
        else:
            # Use standard PHIST definitions
            self._use_standard_phist()

    def _use_standard_phist(self) -> None:
        """Use standard PHIST field definitions.

        This provides sensible defaults for edbws_phist file parsing
        when no explicit format spec is provided.
        """
        for idx, field_name in enumerate(self.STANDARD_PHIST_FIELDS, start=1):
            self._field_definitions[field_name] = {
                "position": idx,
                "column_index": idx - 1,  # 0-based for array indexing
                "type": "VARCHAR",
                "length": 255,
                "field_name": field_name,
            }

        self.spec = {
            "delimiter": "\t",
            "encoding": "utf-8",
            "has_header": False,
            "fields": self._field_definitions,
        }

    def _parse_file(self) -> None:
        """Parse format specification file.

        Supports formats like:
        - field_name = column_position, data_type, length
        - Delimiters are detected from content

        Raises:
            ParsingError: If format is invalid
        """
        if not self.filepath:
            raise ParsingError("No filepath provided")

        if not self.filepath.exists():
            raise ParsingError(
                f"Format spec file not found: {self.filepath}",
                file_name=str(self.filepath),
            )

        try:
            with open(self.filepath, "r", encoding="utf-8", errors="replace") as f:
                line_number = 0
                for line in f:
                    line_number += 1
                    line = line.strip()

                    # Skip comments and empty lines
                    if not line or line.startswith("#"):
                        continue

                    # Parse field definition
                    # Format: field_name = position, type, length
                    if "=" in line:
                        parts = line.split("=")
                        if len(parts) == 2:
                            field_name = parts[0].strip()
                            definition_parts = [p.strip() for p in parts[1].split(",")]

                            if len(definition_parts) >= 2:
                                try:
                                    position = int(definition_parts[0])
                                    data_type = definition_parts[1]
                                    length = (
                                        int(definition_parts[2])
                                        if len(definition_parts) > 2
                                        else 255
                                    )

                                    self._field_definitions[field_name] = {
                                        "position": position,
                                        "column_index": position - 1,  # 0-based
                                        "type": data_type,
                                        "length": length,
                                        "field_name": field_name,
                                    }
                                except (ValueError, IndexError) as e:
                                    raise ParsingError(
                                        f"Invalid field definition at line {line_number}: {line}",
                                        line_number=line_number,
                                        file_name=str(self.filepath),
                                    )

                # Populate spec dictionary
                self.spec = {
                    "delimiter": "\t",  # Default, could be enhanced
                    "encoding": "utf-8",
                    "has_header": False,
                    "fields": self._field_definitions,
                    "file_path": str(self.filepath),
                }

                if not self._field_definitions:
                    raise ParsingError(
                        f"No field definitions found in {self.filepath}",
                        file_name=str(self.filepath),
                    )

        except ParsingError:
            raise
        except Exception as e:
            raise ParsingError(
                f"Failed to parse format spec: {e}",
                file_name=str(self.filepath),
            )

    def get_fields(self) -> Dict[str, Dict[str, Any]]:
        """Get field definitions from specification.

        Returns:
            Dict[str, Dict[str, Any]]: Field definitions keyed by field name
        """
        return self._field_definitions.copy()

    def get_field_by_position(self, position: int) -> Optional[Dict[str, Any]]:
        """Get field definition by column position (1-based).

        Args:
            position: Column position (1-based)

        Returns:
            Field definition dict or None if not found
        """
        for field_def in self._field_definitions.values():
            if field_def["position"] == position:
                return field_def
        return None

    def get_field_by_index(self, index: int) -> Optional[Dict[str, Any]]:
        """Get field definition by column index (0-based).

        Args:
            index: Column index (0-based)

        Returns:
            Field definition dict or None if not found
        """
        return self.get_field_by_position(index + 1)

    def get_delimiter(self) -> str:
        """Get field delimiter from specification.

        Returns:
            str: Delimiter character or pattern (tab, space, etc.)
        """
        return self.spec.get("delimiter", "\t")

    def get_encoding(self) -> str:
        """Get file encoding from specification.

        Returns:
            str: Encoding name
        """
        return self.spec.get("encoding", "utf-8")

    def get_spec(self) -> Dict[str, Any]:
        """Get complete specification.

        Returns:
            Complete specification dictionary
        """
        return self.spec.copy()

    @classmethod
    def get_cached_spec(cls, filepath: str | Path) -> Optional[Dict[str, Any]]:
        """Retrieve cached specification if available.

        Args:
            filepath: Path to spec file to look up in cache

        Returns:
            Cached spec or None if not cached
        """
        key = str(Path(filepath).resolve())
        return cls._cache.get(key)

    @classmethod
    def cache_spec(cls, filepath: str | Path, spec: Dict[str, Any]) -> None:
        """Cache a parsed specification.

        Args:
            filepath: Path to spec file
            spec: Specification to cache
        """
        key = str(Path(filepath).resolve())
        cls._cache[key] = spec

    @classmethod
    def clear_cache(cls) -> None:
        """Clear all cached specifications."""
        cls._cache.clear()

    @classmethod
    def parse_or_use_cached(cls, filepath: Optional[str | Path] = None) -> "FormatSpecParser":
        """Parse spec file or return from cache.

        Args:
            filepath: Path to .bcp_fmt file

        Returns:
            FormatSpecParser instance with parsed or cached spec
        """
        if filepath:
            cached = cls.get_cached_spec(filepath)
            if cached:
                parser = cls(filepath)
                parser.spec = cached
                return parser

        parser = cls(filepath)

        if filepath:
            cls.cache_spec(filepath, parser.spec)

        return parser
