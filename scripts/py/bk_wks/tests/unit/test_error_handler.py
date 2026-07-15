"""Unit tests for ErrorHandler component.

Tests error logging, tracking, report generation, and error record writing.
Covers various error types, context tracking, and output file generation.
"""

import pytest
from pathlib import Path
from tempfile import TemporaryDirectory

from scribe_lot_mapper.services.error_handler import ErrorHandler


# ============================================================================
# Test Fixtures
# ============================================================================


@pytest.fixture
def temp_output_dir():
    """Create temporary output directory for test files."""
    with TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def error_handler(temp_output_dir) -> ErrorHandler:
    """Create ErrorHandler instance for testing."""
    return ErrorHandler(output_dir=temp_output_dir)


@pytest.fixture
def error_handler_no_dir() -> ErrorHandler:
    """Create ErrorHandler with no output directory specified."""
    return ErrorHandler()


# ============================================================================
# Test Initialization
# ============================================================================


def test_error_handler_init_with_dir(temp_output_dir):
    """Test ErrorHandler initialization with output directory."""
    handler = ErrorHandler(output_dir=temp_output_dir)
    assert handler.output_dir == temp_output_dir
    assert handler.errors == []
    assert handler.error_counts == {}


def test_error_handler_init_without_dir():
    """Test ErrorHandler initialization without output directory."""
    handler = ErrorHandler()
    assert handler.output_dir == Path(".")
    assert handler.errors == []
    assert handler.error_counts == {}


def test_error_handler_init_with_string_path(temp_output_dir):
    """Test ErrorHandler initialization with string path."""
    handler = ErrorHandler(output_dir=str(temp_output_dir))
    assert handler.output_dir == temp_output_dir


# ============================================================================
# Test log_error
# ============================================================================


def test_log_error_basic(error_handler):
    """Test basic error logging."""
    error_handler.log_error("ParsingError", "Test error message")

    assert len(error_handler.errors) == 1
    assert error_handler.errors[0]["error_type"] == "ParsingError"
    assert error_handler.errors[0]["message"] == "Test error message"
    assert error_handler.error_counts["ParsingError"] == 1


def test_log_error_with_context(error_handler):
    """Test error logging with context information."""
    context = {
        "line_number": "42",
        "field_name": "unit_id",
        "file_name": "test.phist",
    }
    error_handler.log_error("ExtractionError", "Failed to extract", context)

    assert len(error_handler.errors) == 1
    error = error_handler.errors[0]
    assert error["error_type"] == "ExtractionError"
    assert error["message"] == "Failed to extract"
    assert error["line_number"] == "42"
    assert error["field_name"] == "unit_id"
    assert error["file_name"] == "test.phist"


def test_log_error_multiple_errors(error_handler):
    """Test logging multiple errors."""
    error_handler.log_error("ParsingError", "Error 1")
    error_handler.log_error("ParsingError", "Error 2")
    error_handler.log_error("ExtractionError", "Error 3")

    assert len(error_handler.errors) == 3
    assert error_handler.error_counts["ParsingError"] == 2
    assert error_handler.error_counts["ExtractionError"] == 1


def test_log_error_increments_counts(error_handler):
    """Test that error counts are incremented correctly."""
    error_handler.log_error("ValidationError", "Error 1")
    assert error_handler.error_counts["ValidationError"] == 1

    error_handler.log_error("ValidationError", "Error 2")
    assert error_handler.error_counts["ValidationError"] == 2

    error_handler.log_error("ValidationError", "Error 3")
    assert error_handler.error_counts["ValidationError"] == 3


# ============================================================================
# Test log_parsing_error
# ============================================================================


def test_log_parsing_error_basic(error_handler):
    """Test logging parsing error."""
    error_handler.log_parsing_error(42, "Malformed record")

    assert len(error_handler.errors) == 1
    error = error_handler.errors[0]
    assert error["error_type"] == "ParsingError"
    assert error["message"] == "Malformed record"
    assert error["line_number"] == "42"


def test_log_parsing_error_with_content(error_handler):
    """Test logging parsing error with line content."""
    error_handler.log_parsing_error(
        10, "Invalid field count", line_content="a\tb\tc\td\te"
    )

    assert len(error_handler.errors) == 1
    error = error_handler.errors[0]
    assert error["line_number"] == "10"
    assert error["line_content"] == "a\tb\tc\td\te"


# ============================================================================
# Test log_extraction_error
# ============================================================================


def test_log_extraction_error_basic(error_handler):
    """Test logging extraction error."""
    error_handler.log_extraction_error("lot_id", "Invalid lot format")

    assert len(error_handler.errors) == 1
    error = error_handler.errors[0]
    assert error["error_type"] == "ExtractionError"
    assert error["field_name"] == "lot_id"
    assert error["message"] == "Invalid lot format"


def test_log_extraction_error_with_context(error_handler):
    """Test logging extraction error with record context."""
    context = {"record_id": "rec-001", "line_number": "15"}
    error_handler.log_extraction_error("equipment_id", "Unknown equipment", context)

    error = error_handler.errors[0]
    assert error["field_name"] == "equipment_id"
    assert error["record_id"] == "rec-001"
    assert error["line_number"] == "15"


# ============================================================================
# Test log_validation_error
# ============================================================================


def test_log_validation_error_single_reason(error_handler):
    """Test logging validation error with single reason."""
    error_handler.log_validation_error("map-001", ["Missing scribe_id"])

    error = error_handler.errors[0]
    assert error["error_type"] == "ValidationError"
    assert error["record_id"] == "map-001"
    assert "Missing scribe_id" in error["reasons"]


def test_log_validation_error_multiple_reasons(error_handler):
    """Test logging validation error with multiple reasons."""
    reasons = ["Missing scribe_id", "Missing lot_id", "Invalid wafer format"]
    error_handler.log_validation_error("map-002", reasons)

    error = error_handler.errors[0]
    assert error["record_id"] == "map-002"
    assert "Missing scribe_id" in error["reasons"]
    assert "Missing lot_id" in error["reasons"]
    assert "Invalid wafer format" in error["reasons"]


# ============================================================================
# Test generate_report
# ============================================================================


def test_generate_report_empty(error_handler):
    """Test generating report with no errors."""
    report = error_handler.generate_report()

    assert report["total_errors"] == 0
    assert report["error_counts"] == {}
    assert report["errors"] == []


def test_generate_report_with_errors(error_handler):
    """Test generating report with errors."""
    error_handler.log_error("ParsingError", "Error 1")
    error_handler.log_error("ParsingError", "Error 2")
    error_handler.log_error("ExtractionError", "Error 3")

    report = error_handler.generate_report()

    assert report["total_errors"] == 3
    assert report["error_counts"]["ParsingError"] == 2
    assert report["error_counts"]["ExtractionError"] == 1
    assert len(report["errors"]) == 3


# ============================================================================
# Test get_error_count
# ============================================================================


def test_get_error_count_empty(error_handler):
    """Test getting error count when no errors."""
    assert error_handler.get_error_count() == 0


def test_get_error_count_with_errors(error_handler):
    """Test getting error count with errors."""
    error_handler.log_error("ParsingError", "Error 1")
    error_handler.log_error("ParsingError", "Error 2")

    assert error_handler.get_error_count() == 2


# ============================================================================
# Test has_errors
# ============================================================================


def test_has_errors_false(error_handler):
    """Test has_errors returns False when no errors."""
    assert error_handler.has_errors() is False


def test_has_errors_true(error_handler):
    """Test has_errors returns True when errors exist."""
    error_handler.log_error("ParsingError", "Test error")
    assert error_handler.has_errors() is True


# ============================================================================
# Test write_error_report
# ============================================================================


def test_write_error_report_empty(error_handler, temp_output_dir):
    """Test writing error report with no errors."""
    report_path = error_handler.write_error_report()

    assert report_path.exists()
    assert report_path.name == "error_report.txt"
    assert report_path.parent == temp_output_dir

    content = report_path.read_text()
    assert "ERROR REPORT" in content
    assert "Total Errors: 0" in content


def test_write_error_report_with_errors(error_handler, temp_output_dir):
    """Test writing error report with errors."""
    error_handler.log_error("ParsingError", "Malformed record", {"line_number": "42"})
    error_handler.log_error("ParsingError", "Invalid field", {"line_number": "43"})
    error_handler.log_error("ExtractionError", "Unknown field", {"field_name": "unit_id"})

    report_path = error_handler.write_error_report()

    assert report_path.exists()
    content = report_path.read_text()

    assert "Total Errors: 3" in content
    assert "ERROR COUNTS BY TYPE" in content
    assert "ParsingError: 2" in content
    assert "ExtractionError: 1" in content


def test_write_error_report_custom_filename(error_handler, temp_output_dir):
    """Test writing error report with custom filename."""
    error_handler.log_error("ParsingError", "Test error")
    report_path = error_handler.write_error_report(filename="custom_errors.txt")

    assert report_path.name == "custom_errors.txt"
    assert report_path.exists()


def test_write_error_report_creates_directories(temp_output_dir):
    """Test that write_error_report creates necessary directories."""
    nested_dir = temp_output_dir / "nested" / "path"
    handler = ErrorHandler(output_dir=nested_dir)

    report_path = handler.write_error_report()

    assert nested_dir.exists()
    assert report_path.exists()


# ============================================================================
# Test write_error_records
# ============================================================================


def test_write_error_records_empty(error_handler, temp_output_dir):
    """Test writing error records with empty list."""
    error_path = error_handler.write_error_records([])

    assert error_path.exists()
    assert error_path.name == "error_records.err"
    assert error_path.read_text() == ""


def test_write_error_records_single_record(error_handler, temp_output_dir):
    """Test writing error records with single record."""
    records = [
        {
            "mapping_id": "map-001",
            "scribe_id": "THK_1_51_LEFT_1",
            "error_reason": "Missing lot_id",
        }
    ]
    error_path = error_handler.write_error_records(records)

    assert error_path.exists()
    content = error_path.read_text()
    lines = content.strip().split("\n")

    assert len(lines) == 2  # Header + 1 record
    assert "error_reason" in lines[0]
    assert "mapping_id" in lines[0]


def test_write_error_records_multiple_records(error_handler, temp_output_dir):
    """Test writing multiple error records."""
    records = [
        {"mapping_id": "map-001", "error_type": "ParsingError", "message": "Error 1"},
        {"mapping_id": "map-002", "error_type": "ExtractionError", "message": "Error 2"},
        {
            "mapping_id": "map-003",
            "error_type": "ValidationError",
            "message": "Error 3",
        },
    ]
    error_path = error_handler.write_error_records(records)

    content = error_path.read_text()
    lines = content.strip().split("\n")

    assert len(lines) == 4  # Header + 3 records


def test_write_error_records_with_special_chars(error_handler, temp_output_dir):
    """Test writing error records with special characters."""
    records = [
        {
            "mapping_id": "map-001",
            "message": "Error with\ttab and\nnewline",
        }
    ]
    error_path = error_handler.write_error_records(records)

    content = error_path.read_text()
    # Tabs and newlines should be escaped
    assert "\\t" in content or "\t" in content  # Either escaped or as field separator
    assert "\\n" in content


def test_write_error_records_custom_filename(error_handler, temp_output_dir):
    """Test writing error records with custom filename."""
    records = [{"mapping_id": "map-001", "error": "test"}]
    error_path = error_handler.write_error_records(records, filename="my_errors.err")

    assert error_path.name == "my_errors.err"
    assert error_path.exists()


def test_write_error_records_creates_directories(temp_output_dir):
    """Test that write_error_records creates necessary directories."""
    nested_dir = temp_output_dir / "nested" / "errors"
    handler = ErrorHandler(output_dir=nested_dir)

    records = [{"error_id": "e-001", "message": "Test"}]
    error_path = handler.write_error_records(records)

    assert nested_dir.exists()
    assert error_path.exists()


# ============================================================================
# Integration Tests
# ============================================================================


def test_error_handler_full_workflow(error_handler, temp_output_dir):
    """Test complete error handling workflow."""
    # Log errors
    error_handler.log_parsing_error(1, "Malformed record")
    error_handler.log_extraction_error("lot_id", "Invalid format")
    error_handler.log_validation_error("map-001", ["Missing field"])

    # Generate report
    report = error_handler.generate_report()
    assert report["total_errors"] == 3

    # Write error report
    report_path = error_handler.write_error_report()
    assert report_path.exists()

    # Write error records
    error_records = [
        {"mapping_id": "map-001", "reason": "validation failed"},
        {"mapping_id": "map-002", "reason": "extraction failed"},
    ]
    records_path = error_handler.write_error_records(error_records)
    assert records_path.exists()

    # Verify files exist
    assert report_path in temp_output_dir.glob("*.txt")
    assert records_path in temp_output_dir.glob("*.err")


def test_error_handler_tracks_multiple_error_types(error_handler):
    """Test error handler correctly tracks multiple error types."""
    for i in range(5):
        error_handler.log_error("ParsingError", f"Error {i}")
    for i in range(3):
        error_handler.log_error("ExtractionError", f"Error {i}")
    for i in range(2):
        error_handler.log_error("ValidationError", f"Error {i}")

    assert error_handler.get_error_count() == 10
    assert error_handler.error_counts["ParsingError"] == 5
    assert error_handler.error_counts["ExtractionError"] == 3
    assert error_handler.error_counts["ValidationError"] == 2
