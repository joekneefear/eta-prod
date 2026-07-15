"""BCP (Bulk Copy Program) format parser for workstream files.

Parses Sybase BCP format files using format specification to extract fields.
Handles delimited BCP records with support for various data types.

Author: Manufacturing Data Team
"""

import re
from pathlib import Path
from typing import Dict, List, Optional, Any

from scribe_lot_mapper.exceptions import ParsingError, FileOperationError


class BCPFormatSpec:
    """Represents a BCP format specification loaded from .bcp_fmt file.
    
    Format spec defines field names, types, and parsing rules for BCP files.
    Typical format line:
        1    SYBCHAR    1    255    ""    1    parameter_set_id
        |    |          |    |      |     |    |
        idx  type       min  max    delim order field_name
    """

    def __init__(self, filepath: str | Path) -> None:
        """Initialize format spec from .bcp_fmt file.
        
        Args:
            filepath: Path to .bcp_fmt format specification file
            
        Raises:
            FileOperationError: If file cannot be read
            ParsingError: If format spec is malformed
        """
        self.filepath = Path(filepath)
        self.version = None
        self.field_count = 0
        self.fields: List[Dict[str, Any]] = []
        
        self._load()

    def _load(self) -> None:
        """Load and parse format specification file."""
        if not self.filepath.exists():
            raise FileOperationError(
                f"Format spec file not found: {self.filepath}",
                file_path=str(self.filepath),
                operation="read"
            )
        
        try:
            with open(self.filepath, 'r') as f:
                lines = f.readlines()
            
            if len(lines) < 2:
                raise ParsingError(f"Format spec too short: {self.filepath}")
            
            # Line 1: version
            self.version = lines[0].strip()
            
            # Line 2: field count
            try:
                self.field_count = int(lines[1].strip())
            except ValueError:
                raise ParsingError(f"Invalid field count in format spec: {lines[1]}")
            
            # Lines 3+: field definitions
            for i, line in enumerate(lines[2:], start=1):
                line = line.strip()
                if not line:
                    continue
                
                field = self._parse_field_definition(line, i)
                if field:
                    self.fields.append(field)
            
            if len(self.fields) != self.field_count:
                raise ParsingError(
                    f"Field count mismatch: expected {self.field_count}, got {len(self.fields)}"
                )
        
        except (FileOperationError, ParsingError):
            raise
        except Exception as e:
            raise ParsingError(
                f"Failed to load format spec: {e}",
                file_name=str(self.filepath)
            )

    def _parse_field_definition(self, line: str, line_num: int) -> Optional[Dict[str, Any]]:
        """Parse a single field definition line.
        
        Format: idx type min max delimiter order field_name
        
        Args:
            line: Field definition line
            line_num: Line number for error reporting
            
        Returns:
            Dict with field metadata or None if line is invalid
        """
        parts = line.split()
        if len(parts) < 7:
            return None
        
        try:
            field = {
                "index": int(parts[0]),
                "type": parts[1],
                "min_length": int(parts[2]),
                "max_length": int(parts[3]),
                "delimiter": parts[4] if parts[4] != '""' else "",
                "order": int(parts[5]),
                "name": parts[6]
            }
            return field
        except (ValueError, IndexError) as e:
            raise ParsingError(f"Invalid field definition at line {line_num}: {line}")

    def get_field_by_name(self, name: str) -> Optional[Dict[str, Any]]:
        """Get field definition by name.
        
        Args:
            name: Field name
            
        Returns:
            Field definition dict or None if not found
        """
        for field in self.fields:
            if field["name"] == name:
                return field
        return None

    def __repr__(self) -> str:
        return f"BCPFormatSpec(version={self.version}, fields={len(self.fields)})"


class BCPParser:
    """Parses BCP format records using field specifications.
    
    Converts raw BCP records into structured field dictionaries.
    Handles:
    - Delimited fields (variable length)
    - Fixed-length fields
    - Multiple data types (SYBCHAR, SYBINT2, SYBFLT8)
    - Whitespace normalization
    """

    def __init__(self, format_spec: BCPFormatSpec) -> None:
        """Initialize parser with format specification.
        
        Args:
            format_spec: BCPFormatSpec object defining field layout
        """
        self.format_spec = format_spec
        self._detect_delimiter()

    def _detect_delimiter(self) -> None:
        """Detect the field delimiter from format spec.
        
        Most fields have empty delimiter, but some may have specific delimiters.
        Also checks for common BCP delimiters like ╔, ╝, etc.
        """
        # Common BCP delimiters
        self.delimiters = set()
        for field in self.format_spec.fields:
            delim = field.get("delimiter", "")
            if delim and delim != '""':
                self.delimiters.add(delim)
        
        # If no delimiters found in spec, use common BCP delimiters
        if not self.delimiters:
            self.delimiters = {"╔", "╚", "╝", "╗", "|", "\t"}

    def parse_record(self, raw_line: str, line_number: int = 0) -> Dict[str, str]:
        """Parse a single BCP record line into fields.
        
        Splits record by delimiter and maps fields according to format spec.
        
        Args:
            raw_line: Raw record line from BCP file
            line_number: Line number for error reporting
            
        Returns:
            Dict mapping field names to extracted values
            
        Raises:
            ParsingError: If record cannot be parsed
        """
        if not raw_line or not raw_line.strip():
            raise ParsingError(
                "Empty record line",
                line_number=line_number,
                error_code="PARSE_001"
            )
        
        try:
            # Try to split by detected delimiters
            fields = self._split_record(raw_line)
            
            if len(fields) < len(self.format_spec.fields):
                raise ParsingError(
                    f"Record has {len(fields)} fields, expected {len(self.format_spec.fields)}",
                    line_number=line_number,
                    error_code="PARSE_001"
                )
            
            # Map fields to names according to format spec
            record = {}
            for field_spec in self.format_spec.fields:
                field_idx = field_spec["index"] - 1  # Convert to 0-based index
                field_name = field_spec["name"]
                
                if field_idx < len(fields):
                    value = fields[field_idx].strip()
                    # Normalize the value
                    value = self._normalize_value(value, field_spec)
                    record[field_name] = value
                else:
                    record[field_name] = ""
            
            return record
        
        except ParsingError:
            raise
        except Exception as e:
            raise ParsingError(
                f"Failed to parse record: {str(e)}",
                line_number=line_number,
                error_code="PARSE_001"
            )

    def _split_record(self, raw_line: str) -> List[str]:
        """Split record by detected delimiter.
        
        Tries multiple delimiters in order of likelihood.
        
        Args:
            raw_line: Raw record line
            
        Returns:
            List of field values
        """
        # Try each delimiter, use the one that produces most fields
        best_split = []
        best_count = 0
        
        for delim in sorted(self.delimiters, key=lambda x: -raw_line.count(x)):
            fields = raw_line.split(delim)
            if len(fields) > best_count:
                best_split = fields
                best_count = len(fields)
            
            # If we found a delimiter with many fields, use it
            if len(fields) >= len(self.format_spec.fields):
                return fields
        
        return best_split if best_split else [raw_line]

    def _normalize_value(self, value: str, field_spec: Dict[str, Any]) -> str:
        """Normalize field value based on type and spec.
        
        Handles:
        - Whitespace trimming
        - Type-specific formatting
        - Empty value handling
        - Special character removal
        
        Args:
            value: Raw field value
            field_spec: Field specification
            
        Returns:
            Normalized value
        """
        if not value:
            return ""
        
        # Remove control characters and non-printable chars
        value = ''.join(c for c in value if ord(c) >= 32 or c in '\t\n\r')
        
        # Remove quotes
        value = value.strip('"\'')
        
        # Normalize whitespace
        value = ' '.join(value.split())
        
        # Type-specific normalization
        field_type = field_spec.get("type", "SYBCHAR")
        
        if field_type in ("SYBINT2", "SYBINT4", "SYBINT8"):
            # Remove non-numeric characters except minus sign
            value = re.sub(r'[^\d\-]', '', value)
        elif field_type in ("SYBFLT8", "SYBFLT4"):
            # Allow digits, decimal point, and minus sign
            value = re.sub(r'[^\d\.\-]', '', value)
        
        return value

    def __repr__(self) -> str:
        return f"BCPParser({self.format_spec})"
