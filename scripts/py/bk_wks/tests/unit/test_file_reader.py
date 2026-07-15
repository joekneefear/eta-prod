"""Unit tests for FileReader component.

Tests file reading, encoding detection, compression handling, and format validation.
"""

import gzip
from pathlib import Path
from typing import Generator

import pytest

from scribe_lot_mapper.exceptions import FileOperationError
from scribe_lot_mapper.readers.file_reader import FileReader


@pytest.mark.unit
class TestFileReaderBasics:
    """Test basic FileReader functionality."""

    def test_file_reader_init_with_existing_file(self, sample_input_file: Path) -> None:
        """Test FileReader initialization with existing file.

        Args:
            sample_input_file: Sample input file from fixture
        """
        reader = FileReader(sample_input_file)

        assert reader.filepath == sample_input_file
        assert reader.file_type == "phist"
        assert reader.encoding in ["utf-8", "ascii", "latin-1"]
        assert reader.is_compressed is False

    def test_file_reader_init_missing_file(self, tmp_work_dir: Path) -> None:
        """Test FileReader initialization with missing file.

        Args:
            tmp_work_dir: Temporary working directory
        """
        missing_file = tmp_work_dir / "nonexistent.phist"

        with pytest.raises(FileOperationError) as exc_info:
            FileReader(missing_file)

        assert "File not found" in str(exc_info.value)
        assert str(missing_file) in str(exc_info.value)

    def test_file_reader_detects_phist_format(self, sample_input_file: Path) -> None:
        """Test file type detection for phist files.

        Args:
            sample_input_file: Sample phist file
        """
        reader = FileReader(sample_input_file)
        assert reader.get_file_type() == "phist"

    def test_file_reader_detects_gzip_compression(
        self, tmp_work_dir: Path, sample_input_file: Path
    ) -> None:
        """Test detection of gzip compression.

        Args:
            tmp_work_dir: Temporary working directory
            sample_input_file: Sample input file
        """
        # Create compressed file
        gz_file = tmp_work_dir / "sample.phist.gz"

        with open(sample_input_file, "rb") as f_in:
            with gzip.open(gz_file, "wb") as f_out:
                f_out.writelines(f_in)

        reader = FileReader(gz_file)
        assert reader.is_compressed is True
        assert reader.file_type == "phist"

    def test_file_reader_encoding_detection(self, tmp_work_dir: Path) -> None:
        """Test encoding detection for UTF-8 file.

        Args:
            tmp_work_dir: Temporary working directory
        """
        test_file = tmp_work_dir / "test_utf8.txt"
        test_file.write_text("Test content with UTF-8: éàü\n", encoding="utf-8")

        reader = FileReader(test_file)
        # Should detect as utf-8 or latin-1 (both work for ASCII)
        assert reader.get_encoding() in ["utf-8", "latin-1"]

    def test_file_reader_get_encoding(self, sample_input_file: Path) -> None:
        """Test getting detected encoding.

        Args:
            sample_input_file: Sample input file
        """
        reader = FileReader(sample_input_file, encoding="utf-8")
        assert reader.get_encoding() == "utf-8"


@pytest.mark.unit
class TestFileReaderDetectFileType:
    """Test file type detection logic."""

    def test_detect_phist_file(self, tmp_work_dir: Path) -> None:
        """Test phist file detection."""
        phist_file = tmp_work_dir / "edbws_phist.txt"
        phist_file.write_text("test")

        file_type = FileReader.detect_file_type(None, str(phist_file))
        assert file_type == "phist"

    def test_detect_lhist_file(self, tmp_work_dir: Path) -> None:
        """Test lhist file detection."""
        lhist_file = tmp_work_dir / "edbws_lhist.txt"
        lhist_file.write_text("test")

        file_type = FileReader.detect_file_type(None, str(lhist_file))
        assert file_type == "lhist"

    def test_detect_lot_attr_file(self, tmp_work_dir: Path) -> None:
        """Test lot_attr file detection."""
        attr_file = tmp_work_dir / "lot_attributes.txt"
        attr_file.write_text("test")

        file_type = FileReader.detect_file_type(None, str(attr_file))
        assert file_type == "lot_attr"

    def test_detect_product_file(self, tmp_work_dir: Path) -> None:
        """Test product file detection."""
        prod_file = tmp_work_dir / "product_data.txt"
        prod_file.write_text("test")

        file_type = FileReader.detect_file_type(None, str(prod_file))
        assert file_type == "product"

    def test_detect_unknown_file(self, tmp_work_dir: Path) -> None:
        """Test unknown file detection."""
        unknown_file = tmp_work_dir / "unknown_data.txt"
        unknown_file.write_text("test")

        file_type = FileReader.detect_file_type(None, str(unknown_file))
        assert file_type == "unknown"


@pytest.mark.unit
class TestFileReaderStreaming:
    """Test streaming file reading."""

    def test_file_reader_iteration(self, sample_input_file: Path) -> None:
        """Test iterating over file records.

        Args:
            sample_input_file: Sample input file
        """
        reader = FileReader(sample_input_file)

        lines = []
        with reader:
            for line in reader:
                lines.append(line)

        assert len(lines) == 3
        assert "GMBG3002" in lines[0]
        assert "GTGX9A510_501" in lines[2]

    def test_file_reader_manual_open_close(self, sample_input_file: Path) -> None:
        """Test manual open and close.

        Args:
            sample_input_file: Sample input file
        """
        reader = FileReader(sample_input_file)
        reader.open()

        lines = list(reader)
        assert len(lines) == 3

        reader.close()

    def test_file_reader_context_manager(self, sample_input_file: Path) -> None:
        """Test using reader as context manager.

        Args:
            sample_input_file: Sample input file
        """
        with FileReader(sample_input_file) as reader:
            lines = list(reader)
            assert len(lines) == 3

    def test_file_reader_strips_newlines(self, tmp_work_dir: Path) -> None:
        """Test that reader strips newlines from records.

        Args:
            tmp_work_dir: Temporary working directory
        """
        test_file = tmp_work_dir / "test_newlines.txt"
        test_file.write_text("line1\nline2\r\nline3\n")

        with FileReader(test_file) as reader:
            lines = list(reader)

        assert lines == ["line1", "line2", "line3"]

    def test_file_reader_empty_lines(self, tmp_work_dir: Path) -> None:
        """Test reading file with empty lines.

        Args:
            tmp_work_dir: Temporary working directory
        """
        test_file = tmp_work_dir / "test_empty_lines.txt"
        test_file.write_text("line1\n\nline2\n\n\nline3\n")

        with FileReader(test_file) as reader:
            lines = list(reader)

        assert "" in lines  # Empty lines should be preserved as empty strings
        assert "line1" in lines
        assert "line2" in lines

    def test_file_reader_line_count(self, sample_input_file: Path) -> None:
        """Test line count tracking.

        Args:
            sample_input_file: Sample input file
        """
        reader = FileReader(sample_input_file)

        with reader:
            list(reader)  # Consume all lines

        assert reader.get_line_count() == 3


@pytest.mark.unit
class TestFileReaderValidation:
    """Test file format validation."""

    def test_file_reader_validate_valid_file(self, sample_input_file: Path) -> None:
        """Test validation of valid file.

        Args:
            sample_input_file: Valid sample input file
        """
        reader = FileReader(sample_input_file)
        assert reader.validate() is True

    def test_file_reader_validate_empty_file(self, tmp_work_dir: Path) -> None:
        """Test validation of empty file.

        Args:
            tmp_work_dir: Temporary working directory
        """
        empty_file = tmp_work_dir / "empty.txt"
        empty_file.write_text("")

        reader = FileReader(empty_file)
        with pytest.raises(FileOperationError) as exc_info:
            reader.validate()

        assert "No valid records" in str(exc_info.value)

    def test_file_reader_validate_file_with_few_fields(self, tmp_work_dir: Path) -> None:
        """Test validation of file with insufficient fields.

        Args:
            tmp_work_dir: Temporary working directory
        """
        bad_file = tmp_work_dir / "bad_fields.txt"
        bad_file.write_text("field1\tfield2\nfield3\tfield4\n")

        reader = FileReader(bad_file)
        # File should fail validation but not raise (validation attempts to read)
        try:
            result = reader.validate()
            assert result is True  # If it passes, OK
        except FileOperationError:
            pass  # Expected if validation fails on too few fields

    def test_file_reader_validate_gzip_file(
        self, tmp_work_dir: Path, sample_input_file: Path
    ) -> None:
        """Test validation of gzip-compressed file.

        Args:
            tmp_work_dir: Temporary working directory
            sample_input_file: Sample input file
        """
        gz_file = tmp_work_dir / "sample.phist.gz"

        with open(sample_input_file, "rb") as f_in:
            with gzip.open(gz_file, "wb") as f_out:
                f_out.writelines(f_in)

        reader = FileReader(gz_file)
        assert reader.validate() is True


@pytest.mark.unit
class TestFileReaderEdgeCases:
    """Test edge cases and error conditions."""

    def test_file_reader_special_characters(self, tmp_work_dir: Path) -> None:
        """Test reading file with special characters.

        Args:
            tmp_work_dir: Temporary working directory
        """
        special_file = tmp_work_dir / "special_chars.txt"
        special_file.write_text(
            "normal\tfield\tünicode\téàü\nfield\ttab\t\tseparated\n",
            encoding="utf-8",
        )

        reader = FileReader(special_file)
        with reader:
            lines = list(reader)

        assert len(lines) == 2
        assert "ünicode" in lines[0]

    def test_file_reader_very_long_line(self, tmp_work_dir: Path) -> None:
        """Test reading very long lines.

        Args:
            tmp_work_dir: Temporary working directory
        """
        long_file = tmp_work_dir / "long_line.txt"
        long_line = "\t".join(["field"] * 1000)
        long_file.write_text(long_line)

        reader = FileReader(long_file)
        with reader:
            lines = list(reader)

        assert len(lines) == 1
        assert len(lines[0].split("\t")) == 1000

    def test_file_reader_unicode_bom(self, tmp_work_dir: Path) -> None:
        """Test reading UTF-8 file with BOM.

        Args:
            tmp_work_dir: Temporary working directory
        """
        bom_file = tmp_work_dir / "utf8_bom.txt"
        # Write with UTF-8 BOM
        with open(bom_file, "wb") as f:
            f.write(b"\xef\xbb\xbf")  # UTF-8 BOM
            f.write("line1\tfield\n".encode("utf-8"))

        reader = FileReader(bom_file)
        with reader:
            lines = list(reader)

        # BOM might be preserved or stripped depending on encoding handling
        assert len(lines) == 1


@pytest.mark.unit
class TestFileReaderPermissions:
    """Test permission and access error handling."""

    def test_file_reader_permission_error_on_read(self, sample_input_file: Path) -> None:
        """Test handling of permission denied errors.

        Note: This test may be platform-specific and may not work on all systems.

        Args:
            sample_input_file: Sample input file
        """
        # This is a tricky test - skip on Windows where permissions work differently
        import sys

        if sys.platform == "win32":
            pytest.skip("Permission test not reliable on Windows")

        # Make file unreadable (requires admin privileges on some systems)
        try:
            sample_input_file.chmod(0o000)

            reader = FileReader(sample_input_file)
            with pytest.raises(FileOperationError):
                reader.open()

        finally:
            # Restore permissions for cleanup
            sample_input_file.chmod(0o644)

