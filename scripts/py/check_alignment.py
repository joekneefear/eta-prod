#!/usr/bin/env python3
r"""
WAT vs IFF alignment checker.

- Parses a .WAT file with PowerchipWatParser
- Scans generated IFF files (one per wafer) and checks that:
  * PAR test count matches the parser test count
  * DATA result line lengths match the parser test count
- Optionally inspects a .limit file and reports row counts vs. tests

Usage:
    py scripts\py\check_alignment.py --wat <path> --iff-dir <dir> [--limit <path>] [--wafer 01]

Outputs a short report with pass/fail per wafer and aggregate summary.
"""
import argparse
import glob
import os
import sys
from collections import Counter

# Ensure we can import project libs
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from lib.Parser.PowerchipWatParser import PowerchipWatParser
from lib.Data.Metadata import Metadata
from lib.Log import Log


def parse_wat_model(wat_path: str):
    """Parse WAT and return (model, tests_count)."""
    parser = PowerchipWatParser()
    header = parser.extract_header(wat_path)
    model = parser.read_file(wat_path, header, "", "", {})
    return model, len(model.tests)


def parse_iff_file(iff_path: str):
    """Parse PAR count, DATA result values, and data rows from an IFF file."""
    with open(iff_path, "r", encoding="utf-8", errors="ignore") as fh:
        lines = fh.readlines()

    in_par = False
    in_data = False
    par_lines = []
    result_lengths = []
    sample_values = None
    data_rows = {}  # keyed by (wafer, site) -> list of result values

    current_wafer = None
    current_site = None

    for raw in lines:
        line = raw.strip()
        if line.startswith("<PAR>"):
            in_par = True
            continue
        if line.startswith("</PAR>"):
            in_par = False
            continue
        if line.startswith("<DATA>"):
            in_data = True
            continue
        if line.startswith("</DATA>"):
            in_data = False
            continue

        if in_par:
            if line and not line.startswith("<"):
                par_lines.append(line)
        elif in_data:
            if not line:
                continue
            # Parse die attributes (wafer, site)
            if "=" in line:
                if line.startswith("WAFER="):
                    current_wafer = line.split("=", 1)[1].strip()
                elif line.startswith("SITE="):
                    current_site = line.split("=", 1)[1].strip()
                continue
            # Parse result values (comma-separated)
            vals = [v.strip() for v in line.split(",")]
            result_lengths.append(len(vals))
            if sample_values is None:
                sample_values = vals[:5]
            # Store results keyed by wafer/site for value comparison
            if current_wafer and current_site:
                key = (current_wafer, current_site)
                if key not in data_rows:
                    data_rows[key] = vals
                current_wafer = None
                current_site = None

    return len(par_lines), result_lengths, sample_values or [], data_rows


def find_iff_files(iff_dir: str, wafer_number: str):
    """Find IFF files for a wafer (02-digit) under iff_dir recursively."""
    wafer_tag = str(wafer_number).zfill(2)
    patterns = [f"*{wafer_tag}*.IFF", f"*{wafer_tag}*.iff", f"*{wafer_tag}*.IFF.gz", f"*{wafer_tag}*.iff.gz"]
    matches = []
    for pat in patterns:
        matches.extend(glob.glob(os.path.join(iff_dir, "**", pat), recursive=True))
    # Deduplicate preserving order
    seen = set()
    uniq = []
    for m in matches:
        if m not in seen:
            uniq.append(m)
            seen.add(m)
    return uniq


def parse_limit_file(limit_path: str):
    """Best-effort limit row count (used for a coarse alignment sanity check)."""
    if not limit_path or not os.path.isfile(limit_path):
        return None, []
    rows = []
    with open(limit_path, "r", encoding="utf-8", errors="ignore") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            # Treat comma or whitespace separated lines as limit rows
            if "," in line:
                rows.append([p.strip() for p in line.split(",") if p.strip()])
            else:
                parts = line.split()
                if len(parts) > 1:
                    rows.append(parts)
    row_lengths = [len(r) for r in rows]
    return len(rows), row_lengths


def check_alignment(wat_path: str, iff_dir: str, limit_path: str = None, only_wafer: str = None):
    model, expected_tests = parse_wat_model(wat_path)
    Log.INFO(f"Parsed WAT: {wat_path} | tests={expected_tests} wafers={len(model.wafers)}")

    wafers = [w for w in model.wafers if (only_wafer is None or str(w.number).zfill(2) == str(only_wafer).zfill(2))]
    issues = []
    value_mismatches = []

    for wafer in wafers:
        wafer_tag = str(wafer.number).zfill(2)
        iff_files = find_iff_files(iff_dir, wafer_tag)
        if not iff_files:
            issues.append(("missing_iff", wafer_tag, f"No IFF files found for wafer {wafer_tag}"))
            continue

        for iff_path in iff_files:
            par_count, res_lengths, sample_vals, data_rows = parse_iff_file(iff_path)
            bad_lengths = [l for l in res_lengths if l != expected_tests]
            
            if par_count != expected_tests:
                issues.append(("par_mismatch", wafer_tag, f"PAR count {par_count} != expected {expected_tests} in {iff_path}"))
            if bad_lengths:
                summary = Counter(res_lengths)
                issues.append(("data_mismatch", wafer_tag, f"Result lengths {summary} != expected {expected_tests} in {iff_path}"))
            
            # Compare actual WAT values vs IFF values for this wafer
            for die in wafer.dies:
                site_key = die.site
                # Normalize site format (strip leading +/- for comparison)
                site_display = die.misc.get('site_display', site_key) if hasattr(die, 'misc') and die.misc else site_key
                
                # Check IFF for this wafer/site
                for iff_site_key, iff_values in data_rows.items():
                    # Try to match: IFF site key might be stripped or signed differently
                    iff_wafer, iff_site = iff_site_key
                    if iff_wafer.lstrip('0') == wafer_tag.lstrip('0') and (iff_site == site_key or iff_site == site_display):
                        # Found matching site - compare values
                        wat_values = [str(r) for r in die.result]
                        if len(wat_values) == len(iff_values):
                            for col_idx, (wat_val, iff_val) in enumerate(zip(wat_values, iff_values)):
                                # Normalize for comparison (handle NA, strip whitespace)
                                wat_norm = "NA" if wat_val.upper() in ("NA", "") else wat_val.strip()
                                iff_norm = "NA" if iff_val.upper() in ("NA", "") else iff_val.strip()
                                if wat_norm != iff_norm:
                                    value_mismatches.append({
                                        "wafer": wafer_tag,
                                        "site": site_display,
                                        "column": col_idx,
                                        "wat": wat_norm,
                                        "iff": iff_norm,
                                        "iff_path": iff_path
                                    })
            
            if not bad_lengths and par_count == expected_tests and not value_mismatches:
                Log.INFO(f"Wafer {wafer_tag} OK: {iff_path} (tests={par_count}, sample={sample_vals})")

    limit_report = None
    if limit_path:
        limit_rows, row_lengths = parse_limit_file(limit_path)
        if limit_rows is not None:
            limit_report = {
                "rows": limit_rows,
                "lengths": Counter(row_lengths)
            }
            if limit_rows and limit_rows != expected_tests:
                issues.append(("limit_mismatch", "ALL", f"Limit rows {limit_rows} != expected tests {expected_tests} ({limit_path})"))

    return issues, expected_tests, limit_report, value_mismatches


def main():
    ap = argparse.ArgumentParser(description="Check alignment between WAT parse and generated IFF/limit files.")
    ap.add_argument("--wat", required=True, help="Path to WAT file")
    ap.add_argument("--iff-dir", required=True, help="Directory containing generated IFF files")
    ap.add_argument("--limit", help="Path to limit file (optional)")
    ap.add_argument("--wafer", help="Wafer number to check (02-digit). If omitted, all wafers are checked.")
    args = ap.parse_args()

    if not os.path.isfile(args.wat):
        print(f"WAT not found: {args.wat}")
        sys.exit(1)
    if not os.path.isdir(args.iff_dir):
        print(f"IFF directory not found: {args.iff_dir}")
        sys.exit(1)

    issues, expected_tests, limit_report, value_mismatches = check_alignment(args.wat, args.iff_dir, args.limit, args.wafer)

    print("\n=== ALIGNMENT SUMMARY ===")
    print(f"Expected tests: {expected_tests}")
    if limit_report:
        print(f"Limit rows: {limit_report['rows']} (row-length histogram {dict(limit_report['lengths'])})")
    
    if not issues and not value_mismatches:
        print("PASS: No alignment issues detected.")
        sys.exit(0)

    if issues or value_mismatches:
        print("FAIL: Alignment issues detected:")
        for kind, wafer_tag, msg in issues:
            print(f" - [{wafer_tag}] {kind}: {msg}")
        
        if value_mismatches:
            print(f"\nValue mismatches (WAT vs IFF): {len(value_mismatches)} detected")
            # Group by wafer/site and show first 10 mismatches
            for mismatch in value_mismatches[:10]:
                print(f"  Wafer {mismatch['wafer']}, Site {mismatch['site']}, Column {mismatch['column']}: "
                      f"WAT={mismatch['wat']} vs IFF={mismatch['iff']}")
            if len(value_mismatches) > 10:
                print(f"  ... and {len(value_mismatches) - 10} more")
        
        sys.exit(1)


if __name__ == "__main__":
    main()
