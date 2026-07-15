"""ErrorHandler component for centralized error handling and reporting.

Manages error logging, tracking, and report generation.
"""

from pathlib import Path
from typing import Dict, List, Optional

from scribe_lot_mapper.exceptions import ScribeLotMapperError


class ErrorHandler:
    """Centralizes error handling, logging, and reporting.

    Tracks error counts by type, generates error reports, and writes
    error records to separate .err output files.
    """

    def __init__(self, output_dir: Optional[str | Path] = None) -> None:
        """Initialize ErrorHandler.

        Args:
            output_dir: Optional directory for error output files
        """
        self.output_dir = Path(output_dir) if output_dir else Path(".")
        self.errors: List[Dict[str, str]] = []
        self.error_counts: Dict[str, int] = {}

    def log_error(
        self,
        error_type: str,
        message: str,
        context: Optional[Dict[str, str]] = None,
    ) -> None:
        """Log an error with context.

        Tracks error with type, message, and optional context information.
        Increments error count for the error type.

        Args:
            error_type: Type of error (ParsingError, ExtractionError, etc.)
            message: Error message
            context: Optional context dict (line_number, field_name, etc.)
        """
        error_record: Dict[str, str] = {
            "error_type": error_type,
            "message": message,
        }

        if context:
            error_record.update(context)

        self.errors.append(error_record)

        # Increment error count for this type
        if error_type not in self.error_counts:
            self.error_counts[error_type] = 0
        self.error_counts[error_type] += 1

    def log_parsing_error(
        self,
        line_number: int,
        message: str,
        line_content: Optional[str] = None,
    ) -> None:
        """Log a parsing error.

        Args:
            line_number: Line number where error occurred
            message: Error message
            line_content: Optional line content that caused error
        """
        context = {
            "error_type": "ParsingError",
            "line_number": str(line_number),
        }
        if line_content:
            context["line_content"] = line_content
        self.log_error("ParsingError", message, context)

    def log_extraction_error(
        self,
        field_name: str,
        message: str,
        record_context: Optional[Dict[str, str]] = None,
    ) -> None:
        """Log an extraction error.

        Args:
            field_name: Name of field that failed extraction
            message: Error message
            record_context: Optional context from record
        """
        context = {
            "error_type": "ExtractionError",
            "field_name": field_name,
        }
        if record_context:
            context.update(record_context)
        self.log_error("ExtractionError", message, context)

    def log_validation_error(
        self,
        record_id: str,
        reasons: List[str],
    ) -> None:
        """Log a validation error.

        Args:
            record_id: Identifier of record that failed validation
            reasons: List of validation failure reasons
        """
        context = {
            "error_type": "ValidationError",
            "record_id": record_id,
            "reasons": "; ".join(reasons),
        }
        self.log_error("ValidationError", "Validation failed", context)

    def write_error_report(self, filename: str = "error_report.txt") -> Path:
        """Write error report to file.

        Generates a summary report with error counts, error types, and sample errors.
        Report format: text file with error statistics and details.

        Args:
            filename: Output filename (default: error_report.txt)

        Returns:
            Path: Path to written error report file
        """
        report_path = self.output_dir / filename
        report_path.parent.mkdir(parents=True, exist_ok=True)

        with open(report_path, "w") as f:
            f.write("=" * 80 + "\n")
            f.write("ERROR REPORT\n")
            f.write("=" * 80 + "\n\n")

            # Summary statistics
            f.write("SUMMARY\n")
            f.write("-" * 80 + "\n")
            f.write(f"Total Errors: {len(self.errors)}\n")
            f.write(f"Error Types: {len(self.error_counts)}\n\n")

            # Error counts by type
            f.write("ERROR COUNTS BY TYPE\n")
            f.write("-" * 80 + "\n")
            for error_type, count in sorted(
                self.error_counts.items(), key=lambda x: -x[1]
            ):
                f.write(f"  {error_type}: {count}\n")
            f.write("\n")

            # Sample errors (first 10)
            f.write("SAMPLE ERRORS (First 10)\n")
            f.write("-" * 80 + "\n")
            for i, error in enumerate(self.errors[:10], 1):
                f.write(f"\nError #{i}:\n")
                for key, value in error.items():
                    f.write(f"  {key}: {value}\n")
            f.write("\n")

            f.write("=" * 80 + "\n")

        return report_path

    def write_error_records(
        self,
        error_records: List[dict],
        filename: str = "error_records.err",
    ) -> Path:
        """Write error records to .err file.

        Writes error records in CSV format (TSV with tab delimiters) to support
        integration with workstream processing tools.

        Args:
            error_records: List of error record dictionaries
            filename: Output filename (default: error_records.err)

        Returns:
            Path: Path to written error records file
        """
        error_path = self.output_dir / filename
        error_path.parent.mkdir(parents=True, exist_ok=True)

        if not error_records:
            return error_path

        # Get all unique keys from error records (for headers)
        all_keys: set = set()
        for record in error_records:
            all_keys.update(record.keys())
        headers = sorted(list(all_keys))

        # Write TSV format (tab-separated values)
        with open(error_path, "w") as f:
            # Write header row
            f.write("\t".join(headers) + "\n")

            # Write error records
            for record in error_records:
                values = []
                for key in headers:
                    value = record.get(key, "")
                    # Escape tabs and newlines in values
                    if isinstance(value, str):
                        value = value.replace("\n", "\\n").replace("\t", "\\t")
                    else:
                        value = str(value)
                    values.append(value)
                f.write("\t".join(values) + "\n")

        return error_path

    def generate_report(self) -> Dict[str, int | List[Dict]]:
        """Generate error report summary.

        Returns:
            Dict[str, int | List[Dict]]: Report with counts and details
        """
        return {
            "total_errors": len(self.errors),
            "error_counts": self.error_counts,
            "errors": self.errors,
        }

    def get_error_count(self) -> int:
        """Get total error count.

        Returns:
            int: Total number of errors logged
        """
        return len(self.errors)

    def has_errors(self) -> bool:
        """Check if any errors have been logged.

        Returns:
            bool: True if errors exist
        """
        return len(self.errors) > 0
