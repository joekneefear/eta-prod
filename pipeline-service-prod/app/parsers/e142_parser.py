"""Parser for E142 script diagnostics and benchmark lines."""
import re
import json
from typing import Optional, Dict
from .base import ParserBase


class E142Parser(ParserBase):
    DIAG_REGEX = re.compile(
        r"E142 extraction diagnostics:\s*"
        r"fetched=(?P<fetched>\d+)\s+"
        r"kept=(?P<kept>\d+)\s+"
        r"dropped_status=(?P<dropped_status>\d+)\s+"
        r"dropped_no_backend_lot=(?P<dropped_no_backend_lot>\d+)\s+"
        r"dropped_prod_regex=(?P<dropped_prod_regex>\d+)\s+"
        r"files_written=(?P<files_written>\d+)\s+"
        r"stage=(?P<stage>\S+)\s+"
        r"flow=(?P<flow>\S+)\s+"
        r"view=(?P<view>\S+)",
        re.IGNORECASE,
    )

    def parse_diagnostics_line(self, line: str) -> Optional[Dict]:
        m = self.DIAG_REGEX.search(line)
        if not m:
            return None
        out = {}
        # Convert numeric fields to ints
        for k in ["fetched", "kept", "dropped_status", "dropped_no_backend_lot", "dropped_prod_regex", "files_written"]:
            try:
                out[k] = int(m.group(k))
            except Exception:
                out[k] = None
        # Non-numeric fields
        out["stage"] = m.group("stage")
        out["flow"] = m.group("flow")
        out["view"] = m.group("view")
        return out

    def parse_benchmark_line(self, jsonl: str) -> Optional[Dict]:
        try:
            data = json.loads(jsonl)
            # Keep as-is but ensure keys are JSON-serializable primitives
            return data
        except Exception:
            return None

    def normalize_record(self, record: dict) -> dict:
        base = super().normalize_record(record)
        # If script_name/script identifier present, attach it
        if record.get("script_name"):
            base["metadata"]["script_name"] = record.get("script_name")
        # If benchmark object present with out_files/out_files_trace, normalize keys
        bench = base.get("benchmark", {})
        if isinstance(bench, dict):
            # unify common key names
            if "rows_extracted" in bench and "rows_written" not in bench:
                bench.setdefault("rows_written", bench.get("rows_extracted"))
        return {"metadata": base.get("metadata", {}), "benchmark": base.get("benchmark", {})}
