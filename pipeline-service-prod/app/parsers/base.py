"""Base parser interface for pipeline-service parser plugins."""
from typing import Optional, Dict

class ParserBase:
    """Basic parser API.

    Implementations should parse diagnostics lines and benchmark JSONL lines
    and return structured dictionaries for insertion into the pipeline DB.
    """
    def parse_diagnostics_line(self, line: str) -> Optional[Dict]:
        """Parse a single log/diagnostic line and return structured metadata.

        Return None if the line is not recognized.
        """
        raise NotImplementedError()

    def parse_benchmark_line(self, jsonl: str) -> Optional[Dict]:
        """Parse a benchmark JSONL line (string) into a dict.

        Return None if parsing fails.
        """
        raise NotImplementedError()

    def normalize_record(self, record: dict) -> dict:
        """Normalize an incoming record (from API POST or JSONL) and return
        a dict with at least `metadata` and `benchmark` keys.
        """
        # Default: preserve metadata/benchmark if present
        out = {"metadata": {}, "benchmark": {}}
        if not record:
            return out
        if "metadata" in record and isinstance(record["metadata"], dict):
            out["metadata"] = record["metadata"]
        if "benchmark" in record and isinstance(record["benchmark"], dict):
            out["benchmark"] = record["benchmark"]
        # try to parse diagnostics_line if present
        if "diagnostics_line" in record and isinstance(record["diagnostics_line"], str):
            md = self.parse_diagnostics_line(record["diagnostics_line"])
            if md:
                out["metadata"].update(md)
        # try to parse benchmark JSONL if present as string
        if "benchmark_line" in record and isinstance(record["benchmark_line"], str):
            bk = self.parse_benchmark_line(record["benchmark_line"])
            if bk:
                out["benchmark"].update(bk)
        return out
