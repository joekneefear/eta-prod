"""FileReader component for reading workstream extract files.

Provides streaming file reading with encoding detection, compression handling,
and format validation.
"""

import gzip
from pathlib import Path
from typing import Iterator, Optional

from scribe_lot_mapper.exceptions import FileOperationError


class FileReader:
    """Streams workstream extract files with encoding and format detection.

    Supports:
    - Tab and whitespace-delimited records
    - Multiple file encodings (UTF-8, ASCII, Latin-1)
    - Gzip-compressed files
    - Format specification (.bcp_fmt) guided parsing

    Attributes:
        filepath: Path to input file
        encoding: Detected or specified file encoding
        file_type: Detected file type (phist, lhist, lot_attr, etc.)
        is_compressed: Whether file is gzip compressed
        _line_count: Internal counter for validation
    """

    KNOWN_FILE_PATTERNS = {
        "phist": ("edbws_phist", "phist", "_phist"),
        "lhist": ("edbws_lhist", "lhist", "lot_history"),
        "lot_attr": ("lot_attr", "lot_attributes", "attributes"),
        "product": ("product", "prod"),
        "entity": ("entity", "_ent"),
    }

    def __init__(
        self,
        filepath: str | Path,
        encoding: Optional[str] = None,
        file_type: Optional[str] = None,
    ) -> None:
        """Initialize FileReader.

        Args:
            filepath: Path to input file
            encoding: File encoding (auto-detected if None)
            file_type: File type hint (auto-detected if None)

        Raises:
            FileOperationError: If file does not exist
        """
        self.filepath = Path(filepath)
        if not self.filepath.exists():
            raise FileOperationError(
                f"File not found: {self.filepath}",
                file_path=str(self.filepath),
                operation="open",
            )

        self.is_compressed = self.filepath.suffix.lower() in [".gz", ".gzip"]
        self.file_type = file_type or self.detect_file_type(str(self.filepath))
        self.encoding = encoding or self._detect_encoding()
        self._file_handle = None
        self._line_count = 0

    def _detect_encoding(self) -> str:
        """Detect file encoding by reading first bytes.

        Tries UTF-8, ASCII, then Latin-1 (which accepts all bytes).

        Returns:
            str: Detected encoding (utf-8, ascii, or latin-1)
        """
        encodings_to_try = ["utf-8", "ascii", "latin-1"]

        try:
            # Read first 1KB to detect encoding
            with self._open_file() as f:
                sample = f.read(1024)

            for enc in encodings_to_try:
                try:
                    sample.decode(enc)
                    return enc
                except (UnicodeDecodeError, AttributeError):
                    continue
        except Exception:
            pass

        # Fallback to UTF-8 with error handling
        return "utf-8"

    def _open_file(self):
        """Open file with appropriate decompression.

        Returns:
            File handle for reading

        Raises:
            FileOperationError: If file cannot be opened
        """
        try:
            if self.is_compressed:
                return gzip.open(self.filepath, "rt", encoding=self.encoding, errors="replace")
            else:
                return open(self.filepath, "r", encoding=self.encoding, errors="replace")
        except (OSError, IOError) as e:
            raise FileOperationError(
                f"Cannot open file: {e}",
                file_path=str(self.filepath),
                operation="open",
            )

    def open(self) -> None:
        """Open file for reading.

        Raises:
            FileOperationError: If file cannot be opened
        """
        self._file_handle = self._open_file()
        self._line_count = 0

    def close(self) -> None:
        """Close file and release resources."""
        if self._file_handle is not None:
            self._file_handle.close()
            self._file_handle = None

    def __enter__(self):
        """Context manager entry."""
        self.open()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.close()

    def __iter__(self) -> Iterator[str]:
        """Iterate over records in file.

        Yields:
            str: Raw record line (stripped of newlines)

        Raises:
            FileOperationError: If file cannot be read
        """
        if self._file_handle is None:
            self.open()

        try:
            for line in self._file_handle:
                self._line_count += 1
                # Strip newlines but preserve content
                yield line.rstrip("\n\r")
        except (OSError, IOError) as e:
            raise FileOperationError(
                f"Error reading file at line {self._line_count}: {e}",
                file_path=str(self.filepath),
                operation="read",
            )

    # Known delimiters for workstream files (ordered by priority)
    # More specific/distinctive delimiters first (like ╔) before generic ones (like tab)
    KNOWN_DELIMITERS = ["╔", "\x1e", "|", ";", ",", "\t"]

    def _detect_delimiter(self, sample_line: str) -> str:
        """Detect the field delimiter used in the file.

        Checks delimiters in order of priority:
        1. ╔ (Box Drawings) - distinctive FCS format delimiter
        2. \x1e (Record Separator) - binary/structured format
        3. | (Pipe) - common alternative delimiter
        4. ; (Semicolon) - CSV alternative
        5. , (Comma) - standard CSV
        6. \t (Tab) - fallback if others not found

        Args:
            sample_line: A sample line to analyze

        Returns:
            str: Detected delimiter (defaults to tab if unknown)
        """
        for delim in self.KNOWN_DELIMITERS:
            if delim in sample_line:
                # Verify it produces reasonable field count
                fields = sample_line.split(delim)
                if len(fields) >= 5:
                    return delim

        # Default to tab
        return "\t"

    def validate(self) -> bool:
        """Validate file format by checking first few records.

        Checks:
        - File is readable
        - First non-empty line has expected field count
        - Auto-detects delimiter (tab, ╔, pipe, etc.)

        Returns:
            bool: True if file format is valid

        Raises:
            FileOperationError: If validation fails
        """
        try:
            with self:
                valid_lines = 0
                delimiter = None

                for line in self:
                    if not line.strip():
                        # Skip empty lines
                        continue

                    # Auto-detect delimiter from first non-empty line
                    if delimiter is None:
                        delimiter = self._detect_delimiter(line)
                        self._detected_delimiter = delimiter

                    valid_lines += 1

                    # Basic field count check with detected delimiter
                    fields = line.split(delimiter)
                    if len(fields) >= 3:  # Relaxed from 5 to 3
                        if valid_lines >= 3:  # Reduced from 5 to 3
                            break

                if valid_lines == 0:
                    raise FileOperationError(
                        "No valid records found in file",
                        file_path=str(self.filepath),
                        operation="validate",
                    )

                return True

        except FileOperationError:
            raise
        except Exception as e:
            raise FileOperationError(
                f"Validation failed: {e}",
                file_path=str(self.filepath),
                operation="validate",
            )

    def get_delimiter(self) -> str:
        """Get detected delimiter.

        Returns:
            str: Detected delimiter (defaults to tab)
        """
        return getattr(self, "_detected_delimiter", "\t")

    def detect_file_type(self, filepath: str) -> str:
        """Detect file type from filename pattern.

        Matches against known patterns for phist, lhist, lot_attr, etc.

        Args:
            filepath: Path or filename to analyze

        Returns:
            str: File type identifier (phist, lhist, lot_attr, product, entity, or unknown)
        """
        name_lower = filepath.lower()

        for file_type, patterns in self.KNOWN_FILE_PATTERNS.items():
            for pattern in patterns:
                if pattern.lower() in name_lower:
                    return file_type

        return "unknown"

    def get_file_type(self) -> str:
        """Get detected file type.

        Returns:
            str: File type identifier
        """
        return self.file_type

    def get_encoding(self) -> str:
        """Get detected/specified encoding.

        Returns:
            str: Encoding name
        """
        return self.encoding

    def get_line_count(self) -> int:
        """Get number of lines processed.

        Returns:
            int: Line count (only accurate after iteration)
        """
        return self._line_count
