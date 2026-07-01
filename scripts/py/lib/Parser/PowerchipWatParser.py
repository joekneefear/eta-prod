"""
SYNOPSIS

DESCRIPTION
    POWERCHIP PCM PARSER - Powerchip WAT parser with fixed-width parsing (15-char columns).
    This version utilizes a strict positional strategy with a 28-character anchor for 
    UNITS, SPEC HI, SPEC LO, CRIT, and data rows to ensure consistent alignment.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2025-Mar-31 - jgarcia - initial
    2025-Nov-19 - jgarcia - Added preserve_site_sign option
    2025-Nov-20 - jgarcia - FIX: SPEC HI/LO/CRIT alignment (dynamic detection)
    2025-Nov-20 - jgarcia - FIX: Ensure signs are included in SPEC values
    2025-Nov-21 - jgarcia - IMP: Robust numeric token extraction and fallback
    2025-Nov-21 - jgarcia - Separate and pad/spec assignment refactor
    2025-Nov-22 - jgarcia - Restore immediate inline spec parsing (units/spec hi/spec lo/crit)
    2026-Jan-08 - jgarcia - ENH: Fixed-width data row parsing (15-char columns in data/SPEC rows)
    2026-Jan-08 - jgarcia - FIX: Header uses whitespace separation, data rows use fixed-width
    2026-Jan-08 - jgarcia - IMP: Prioritize fixed-width method for data/SPEC row alignment
    2026-Jan-15 - jgarcia - ENH: Add site_sign_mode (default stripped) with preserve_site_sign compatibility
    2026-Jan-15 - jgarcia - REF: Modularized gap detection and quality logic to lib.Utility
    2026-Jan-16 - jgarcia - ENH: Refined fixed-width parsing anchor (fixed 28-char offset)
    2026-Jan-16 - jgarcia - REM: Removed diagnostic 'Suspicious parse row' warnings (strict fixed-width confirmed)
    
LICENSE
    (C) onsemi 2025 All rights reserved.

"""
from typing import Dict, List, Optional, Tuple, Any
import re
import json
import pandas as pd
from dateutil import parser as dateparser
from lib.Data.Base import Base
from lib.Data.Model import Model
from lib.Data.Metadata import Metadata
from lib.Data.Wafer import Wafer
from lib.Data.Test import Test
from lib.Data.Die import Die
from lib.Util import Util
from lib.Log import Log

# Characters to normalize for minus/dash and spaces
_UNICODE_MINUS_CHARS = {
    '\u2212',  # minus sign
    '\u2013',  # en dash
    '\u2014',  # em dash
    '\u2010',  # hyphen
}
_UNICODE_SPACE_CHARS = {
    '\u00A0',  # no-break space
    '\u2007',  # figure space
    '\u202F',  # narrow no-break space
    '\u2009',  # thin space
    '\u2002',  # en space
    '\u2003',  # em space
}


def _normalize_line_for_signs(s: str) -> str:
    """
    Replace common Unicode minus/dash characters with ASCII '-', and normalize
    odd whitespace characters to regular space ' ' so regex matching works reliably.
    """
    if not s:
        return s
    for ch in _UNICODE_MINUS_CHARS:
        if ch in s:
            s = s.replace(ch, '-')
    for sp in _UNICODE_SPACE_CHARS:
        if sp in s:
            s = s.replace(sp, ' ')
    return s


class PowerchipWatParser(Base):
    VERSION = "2.0"

    def __init__(self, args=None, pplogger=None):
        super().__init__(args)
        self.pplogger = pplogger
        self.pad_token = "NA"
        self.fixed_width_enabled = True
        self.fixed_width_anchor = 28
        self.fixed_width_field_size = 15
        self.suppress_summary = False

        # preserve site sign option: default False (strip leading +/- unless overridden)
        self.preserve_site_sign = False
        # explicit site sign mode for clarity ("signed"|"stripped")
        self.site_sign_mode = "stripped"

        if isinstance(args, dict):
            self.pad_token = args.get('pad_token', self.pad_token)
            self.fixed_width_enabled = args.get('fixed_width_enabled', self.fixed_width_enabled)
            self.fixed_width_anchor = int(args.get('fixed_width_anchor', self.fixed_width_anchor))
            self.fixed_width_field_size = int(args.get('fixed_width_field_size', self.fixed_width_field_size))
            self.preserve_site_sign = bool(args.get('preserve_site_sign', self.preserve_site_sign))
            # preserve_site_sign kept for backward compatibility; takes priority if provided
            self.site_sign_mode = args.get('site_sign_mode', "signed" if self.preserve_site_sign else self.site_sign_mode)
            self.suppress_summary = bool(args.get('suppress_summary', self.suppress_summary))

    # ---------------- Sanitization helper --------------------------------

    def _sanitize_misc(self, misc: Dict[str, Any], max_len: int = 2000) -> Dict[str, Any]:
        """
        Convert model.misc contents into a safe dict for logging/pp_log.
        Keeps primitives, JSON-serializes complex objects (truncated).
        """
        safe: Dict[str, Any] = {}
        for k, v in (misc or {}).items():
            try:
                key_name = str(k)
            except Exception:
                key_name = repr(k)
            if v is None or isinstance(v, (str, int, float, bool)):
                if isinstance(v, str) and len(v) > max_len:
                    safe[key_name] = v[:max_len] + "..."
                else:
                    safe[key_name] = v
                continue
            try:
                dumped = json.dumps(v, default=str)
                if len(dumped) > max_len:
                    dumped = dumped[:max_len] + "..."
                safe[key_name] = dumped
                continue
            except Exception:
                pass
            try:
                r = repr(v)
                if len(r) > max_len:
                    r = r[:max_len] + "..."
                safe[key_name] = r
            except Exception:
                safe[key_name] = "<unserializable>"
        return safe

    # ---------------- Header Extraction ---------------------------------

    def extract_header(self, infile: str) -> Metadata:
        """
        Read file and extract metadata: LOT, SOURCE_LOT, START_TIME, PRODUCT, etc.
        """
        header = Metadata()
        regex_patterns = {
            "header_1": re.compile(r'TYPE NO :(.+?)\s+PROCESS  :(.+?)\s+PCM SPEC:(.+?)\s+QTY:(.+?)\s+pcs', re.I),
            "header_2": re.compile(r'LOT\s+ID\s*:\s*(.+?)\s+DATE\s*:\s*(.+?)\s+TIME\s*:\s*(.+?)\s+Program NAME\s*:\s*(.+)', re.I),
            "header_3": re.compile(r'VERSION\s*:\s*(.+?)\s+TESTER TYPE\s*:\s*(.+?)\s+TESTER ID\s*:\s*(.+?)\s+PRODUCT ID\s*:\s*(.+)', re.I),
        }

        try:
            with open(infile, 'r') as fh:
                lines = fh.readlines()
        except FileNotFoundError:
            Log.ERROR(f"File '{infile}' not found.")
            Util.dp_exit(1, pplogger=self.pplogger, error=f"File '{infile}' not found.")
        except Exception as e:
            Log.ERROR(f"Error opening '{infile}': {e}")
            Util.dp_exit(1, pplogger=self.pplogger, error=str(e))

        for raw in lines:
            line = raw.strip()
            if not line:
                continue
            if regex_patterns["header_1"].search(line):
                m = regex_patterns["header_1"].match(line)
                if m:
                    header.ALTERNATE_PRODUCT, header.PROCESS = map(str.strip, m.groups()[:2])
            elif regex_patterns["header_2"].search(line):
                m = regex_patterns["header_2"].match(line)
                if m:
                    header.LOT, date_part, time_part, header.RECIPE = map(str.strip, m.groups())
                    if not header.LOT or header.LOT.upper() == "NA":
                        error_message = "LOT is blank or NA. Please check the raw file."
                        Log.ERROR(error_message)
                        Util.dp_exit(1, pplogger=self.pplogger, error=error_message)
                    header.SOURCE_LOT = f"{header.LOT}.S"
                    try:
                        dt = dateparser.parse(f"{date_part} {time_part}")
                        header.START_TIME = dt.strftime("%Y/%m/%d %H:%M:%S")
                        header.DATE_TIME_MASK = "%Y/%m/%d %H:%M:%S"
                    except Exception:
                        header.START_TIME = None
            elif regex_patterns["header_3"].search(line):
                m = regex_patterns["header_3"].match(line)
                if m:
                    header.RECIPE_REVISION, header.TESTER_TYPE, header.MEASURING_EQUIPMENT, product = map(str.strip, m.groups())
                    header.PRODUCT = product.split('-', 1)[0]
        return header

    # ---------------- Helpers -------------------------------------------

    def _compute_param_rel_bounds(self, header_param_area: str, param_count: int) -> Optional[List[Tuple[int, Optional[int]]]]:
        """
        Compute relative column bounds from header parameter area.
        
        NOTE: Header uses simple whitespace separation (params can be >15 chars).
        This returns the starting position of the first parameter, which is then
        used with fixed-width parsing (15 chars per column) for data rows.
        
        Args:
            header_param_area: The header line area containing parameter names (after SITE)
            param_count: Number of parameters expected
        
        Returns:
            List with single tuple indicating where first parameter starts, or None if invalid
        """
        if not header_param_area or param_count <= 0:
            return None
        
        # Find the first parameter token position
        match = re.search(r'\S+', header_param_area)
        if not match:
            return None
        
        first_param_start = match.start()
        
        # For fixed-width data rows, we only need the starting offset
        # Data rows use 15-char columns starting from this position
        if self.fixed_width_enabled:
            bounds: List[Tuple[int, Optional[int]]] = []
            for i in range(param_count):
                s = first_param_start + (i * self.fixed_width_field_size)
                e = s + self.fixed_width_field_size
                bounds.append((s, e))
            return bounds
        
        # Fallback: use header token positions (less reliable for data rows)
        matches = list(re.finditer(r'\S+', header_param_area))
        if len(matches) < param_count:
            return None
        starts = [m.start() for m in matches[-param_count:]]
        bounds = []
        for i, s in enumerate(starts):
            e = starts[i+1] if i+1 < len(starts) else None
            bounds.append((s, e))
        return bounds

    def _extract_tokens_with_positions(self, text: str) -> List[Tuple[str, int, int]]:
        """
        Extract all non-whitespace tokens with their start and end positions.
        Returns list of (token_text, start_pos, end_pos) tuples.
        """
        return [(m.group(0), m.start(), m.end()) for m in re.finditer(r'\S+', text)]
    

    def _clean_numeric_value(self, value: str) -> str:
        """
        Clean a numeric value by removing commas and extra whitespace.
        This ensures values don't have embedded commas or whitespace.
        """
        if not value:
            return value
        # Remove all commas and ALL whitespace (internal and external)
        # to prevent column-bleed artifacts like "4.,55928E-06" or "0. 7366".
        cleaned = value.replace(',', '')
        cleaned = re.sub(r"\s+", "", cleaned)
        return cleaned
    
    def _is_valid_numeric(self, value: str) -> bool:
        """
        Validate that a value is a properly formatted number.
        Accepts: integers, decimals, scientific notation (e.g., 2.5e-05, -0.08664463).
        Rejects: empty strings, NA tokens, invalid formats like "..5" or "1e+" or "e05".
        """
        if not value or value == self.pad_token:
            return False
        num_pattern = re.compile(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][+-]?\d+)?$')
        return bool(num_pattern.match(value.strip()))
    
    def _is_all_na_result(self, result: List[str]) -> bool:
        """
        Check if result is entirely NA values (worst case for parsing quality).
        Used to penalize methods that produce no useful data.
        """
        return all(v == self.pad_token or not v for v in result)
    
    def _rejoin_numeric_fragments(self, tokens: List[str]) -> List[str]:
        if not tokens:
            return tokens
        num_re = re.compile(r'^[+-]?\d+(?:\.\d+)?(?:[Ee][+-]?\d+)?$')
        merged: List[str] = []
        i = 0
        n = len(tokens)
        while i < n:
            t = self._clean_numeric_value(tokens[i])
            if i + 1 < n:
                next_t = self._clean_numeric_value(tokens[i+1])
                candidate = t + next_t
                candidate_clean = candidate.replace(',', '').strip()
                if num_re.match(candidate_clean):
                    merged.append(candidate_clean)
                    i += 2
                    continue
                candidate2 = t + next_t.lstrip(',')
                if num_re.match(candidate2.replace(',', '').strip()):
                    merged.append(candidate2.replace(',', '').strip())
                    i += 2
                    continue
            # Clean the token before appending (remove commas and whitespace)
            merged.append(self._clean_numeric_value(t))
            i += 1
        return merged

    def _smart_rejoin_to_expected(self, tokens: List[str], expected: int) -> List[str]:
        if expected <= 0 or len(tokens) <= expected:
            return tokens
        tokens_work = [t.strip() for t in tokens]
        num_re = re.compile(r'^[+-]?\d+(?:\.\d+)?(?:[Ee][+-]?\d+)?$')
        while len(tokens_work) > expected:
            merged_this_pass = False
            i = 0
            while i < len(tokens_work) - 1 and len(tokens_work) > expected:
                a = tokens_work[i].strip()
                b = tokens_work[i+1].strip()
                candidate = a + b
                candidate_clean = candidate.replace(',', '')
                if num_re.match(candidate_clean):
                    tokens_work[i:i+2] = [candidate_clean]
                    merged_this_pass = True
                    i = 0
                    continue
                candidate2 = a + b.lstrip(',')
                if num_re.match(candidate2.replace(',', '')):
                    tokens_work[i:i+2] = [candidate2.replace(',', '')]
                    merged_this_pass = True
                    i = 0
                    continue
                i += 1
            if not merged_this_pass:
                break
        return tokens_work

    def _process_site_value(self, site_raw: str) -> Tuple[str, str]:
        """
        Normalize SITE and return both forms (signed, stripped). Caller chooses
        which to expose based on site_sign_mode/preserve_site_sign.
        """
        if not site_raw:
            return "", ""
        site = _normalize_line_for_signs(site_raw)
        site = re.sub(r'^([+-])\s+(\d+)$', r'\1\2', site)
        site_signed = site.strip()
        site_stripped = site_signed.lstrip('+-')
        return site_signed, site_stripped
    
    def _parse_fixed_width_columns(self, row_param_area: str, expected: int, 
                                   start_offset: int = 0) -> List[str]:
        """
        Parse data row using strict fixed-width columns (15 chars each by default).
        This is the most robust method for WAT files with consistent column widths.
        
        Args:
            row_param_area: The parameter area of the data row
            expected: Expected number of columns
            start_offset: Offset from beginning of row_param_area to first column
        
        Returns:
            List of parsed values with proper alignment
        """
        if expected <= 0:
            return []
        
        width = self.fixed_width_field_size
        result = []
        
        # Pad the row if needed to accommodate all columns
        needed_len = start_offset + (width * expected)
        if len(row_param_area) < needed_len:
            row_padded = row_param_area + ' ' * (needed_len - len(row_param_area))
        else:
            row_padded = row_param_area
        
        for i in range(expected):
            col_start = start_offset + (i * width)
            col_end = col_start + width
            
            if col_start >= len(row_padded):
                # Beyond the row - empty column
                result.append(self.pad_token)
            else:
                chunk = row_padded[col_start:col_end]
                token = chunk.strip()
                
                if not token or token == "":
                    # Empty column
                    result.append(self.pad_token)
                else:
                    # Clean and validate the token
                    token = re.sub(r'([+-])\s+(\d)', r'\1\2', token)
                    token = self._clean_numeric_value(token)
                    result.append(token)
        
        return result




    # ---------------- Main read_file ------------------------------------

    def read_file(
        self,
        infile: str,
        header: Metadata,
        platform: str,
        site: str,
        epi_scribe_ref_hash_data: Dict[str, str],
    ) -> Model:
        """
        Build Model from WAT file.
        SPEC rows (HI/LO/CRIT/UNITS) are now parsed inline using whitespace-splitting
        and immediate assignment to model.tests (original style).
        """
        param_count = 0
        param_line = ""
        param_line_raw = None
        first_param_name = None

        absolute_param_start_index: Optional[int] = None
        header_param_area: Optional[str] = None
        header_param_len = 0
        param_rel_bounds: Optional[List[Tuple[int, Optional[int]]]] = None

        data_line_counter = 0
        cache: Dict[str, Optional[str]] = {}

        # counter for inline units assignment (original behavior)
        t_units = 0

        # track whether current section header includes EpiScribe column (shifts units offset)
        current_with_epi_scribe = False
        
        # Track test start index for the current section
        current_section_test_start_index = 0

        def get_wafer_name(key):
            if key in cache:
                return cache[key]
            wafer_name = epi_scribe_ref_hash_data.get(key, None)
            cache[key] = wafer_name
            return wafer_name

        model = Model({'header': header, 'misc': {}, 'dataSource': ''})

        # Sanitize minimal misc before set_model_header to avoid pp_log warnings
        if self.pplogger:
            try:
                sanitized_misc = self._sanitize_misc(model.misc)
                Log.INFO("model.misc keys before set_model_header: " + ", ".join(list(sanitized_misc.keys())) or "(none)")
                orig_misc = model.misc
                model.misc = sanitized_misc
                try:
                    self.pplogger.set_model_header(model)
                except Exception:
                    Log.WARN("pplogger.set_model_header failed (suppressed details)")
                model.misc = orig_misc
            except Exception:
                Log.WARN("Failed to sanitize model.misc before set_model_header (suppressed details)")

        try:
            with open(infile, 'r') as fh:
                raw_lines = fh.readlines()
        except FileNotFoundError:
            Log.ERROR(f"File '{infile}' not found.")
            Util.dp_exit(1, pplogger=self.pplogger, error=f"File '{infile}' not found.")
        except Exception as e:
            Log.ERROR(f"Error reading file '{infile}': {e}")
            Util.dp_exit(1, pplogger=self.pplogger, error=str(e))

        regex_patterns = {
            'units_start': re.compile(r'ID\s+ID', re.I),
            # data_row: wafer number, optional wafer name (only if it has letters), site (signed int), rest of params
            'data_row': re.compile(r'^\s*(\d+)\s+(?:(?P<wname>(?=.*[A-Za-z])\S+)\s+)?([+-]?\d+)\s+(.*)$'),
            'spec_hi': re.compile(r"\bSPEC\s+HI\b", re.I),
            'spec_lo': re.compile(r"\bSPEC\s+LO\b", re.I),
            'crit': re.compile(r"\bCRIT\b", re.I),
            'waf_epi_scribe': re.compile(r'WAF(?:\s+EpiScribe)?\s+SITE', re.I)
        }

        padded_rows = trimmed_rows = 0
        malformed_examples = []
        nonmatching_row_count = 0

        for raw_line in raw_lines:
            raw_line_no_nl = raw_line.rstrip("\n")
            raw_line_no_nl = _normalize_line_for_signs(raw_line_no_nl)
            line = raw_line_no_nl.strip()
            wafer_name = wafer_num = epi_scribe_key = None

            try:
                # header parameters line
                if regex_patterns['waf_epi_scribe'].search(line):
                    param_line = line
                    param_line_raw = raw_line_no_nl
                    with_epi_scribe_flag = "WAF EpiScribe".lower() in line.lower()
                    current_with_epi_scribe = with_epi_scribe_flag
                    
                    # Parameters start after SITE. SITE is the 3rd column if EpiScribe is present, otherwise 2nd.
                    # We split the line by space and take everything after the SITE column.
                    tokens = line.split()
                    if with_epi_scribe_flag:
                        # WAF EpiScribe SITE PARAM1 PARAM2...
                        data_line_array = tokens[3:]
                    else:
                        # WAF SITE PARAM1 PARAM2...
                        data_line_array = tokens[2:]
                    
                    param_count = len(data_line_array)
                    first_param_name = data_line_array[0] if data_line_array else None
                    
                    # Track where current section's tests start
                    current_section_test_start_index = len(model.tests)

                    # Register tests
                    for item in data_line_array:
                        num = len(model.tests) + 1
                        test = Test({'number': num, 'name': item})
                        model.add('tests', test)

                    model.misc['param_count'] = param_count
                    model.misc['param_line'] = param_line
                    model.misc['fixed_width_anchor'] = self.fixed_width_anchor
                    model.misc['fixed_width_field_size'] = self.fixed_width_field_size
                    continue

                # units line - simple whitespace split (param names can overlap header spacing)
                if regex_patterns['units_start'].search(line):
                    section_test_count = len(model.tests) - current_section_test_start_index
                    unit_values = self._parse_fixed_width_columns(
                        raw_line_no_nl,
                        section_test_count,
                        start_offset=self.fixed_width_anchor,
                    )

                    for t_idx in range(section_test_count):
                        test_idx = current_section_test_start_index + t_idx
                        unit_val = unit_values[t_idx].strip() if t_idx < len(unit_values) else self.pad_token
                        if test_idx < len(model.tests) and unit_val and unit_val != self.pad_token:
                            model.tests[test_idx].units = unit_val
                    continue

                # SPEC HI - simple whitespace split (param names can overlap header spacing)
                if regex_patterns['spec_hi'].search(line):
                    section_test_count = len(model.tests) - current_section_test_start_index
                    if section_test_count > 0:
                        spec_values = self._parse_fixed_width_columns(
                            raw_line_no_nl,
                            section_test_count,
                            start_offset=self.fixed_width_anchor,
                        )

                        for t_idx in range(section_test_count):
                            test_idx = current_section_test_start_index + t_idx
                            if t_idx < len(spec_values):
                                val = spec_values[t_idx]
                                model.tests[test_idx].HSL = Util.rep_na(val)
                    continue

                # SPEC LO - simple whitespace split (param names can overlap header spacing)
                if regex_patterns['spec_lo'].search(line):
                    section_test_count = len(model.tests) - current_section_test_start_index
                    if section_test_count > 0:
                        spec_values = self._parse_fixed_width_columns(
                            raw_line_no_nl,
                            section_test_count,
                            start_offset=self.fixed_width_anchor,
                        )

                        for t_idx in range(section_test_count):
                            test_idx = current_section_test_start_index + t_idx
                            if t_idx < len(spec_values):
                                val = spec_values[t_idx]
                                model.tests[test_idx].LSL = Util.rep_na(val)
                    continue

                # CRIT - simple whitespace split (param names can overlap header spacing)
                if regex_patterns['crit'].search(line):
                    section_test_count = len(model.tests) - current_section_test_start_index
                    if section_test_count > 0:
                        crit_values = self._parse_fixed_width_columns(
                            raw_line_no_nl,
                            section_test_count,
                            start_offset=self.fixed_width_anchor,
                        )

                        for t_idx in range(section_test_count):
                            test_idx = current_section_test_start_index + t_idx
                            if t_idx < len(crit_values):
                                val = crit_values[t_idx]
                                model.tests[test_idx].critical = val
                    continue

                # data row
                m = regex_patterns['data_row'].match(raw_line_no_nl)
                if not m:
                    nonmatching_row_count += 1
                    if len(malformed_examples) < 5:
                        malformed_examples.append({'type': 'nonmatch', 'sample': repr(raw_line_no_nl)})
                    continue

                data_line_counter += 1
                wafer_num, wafer_name, site_raw, _ = m.groups()

                if wafer_num is not None:
                    wafer_num = wafer_num.strip().zfill(2)

                if site_raw is not None:
                    site_signed, site_stripped = self._process_site_value(site_raw)
                else:
                    site_signed, site_stripped = "", ""

                if wafer_name is not None:
                    wafer_name = wafer_name.strip()
                    epi_scribe_key = f"{header.SOURCE_LOT.removesuffix('.S') if hasattr(header,'SOURCE_LOT') and header.SOURCE_LOT else header.LOT}-{wafer_num}"
                    model.misc[epi_scribe_key] = wafer_name

                if wafer_name is None:
                    key = f"{header.SOURCE_LOT.removesuffix('.S') if hasattr(header,'SOURCE_LOT') and header.SOURCE_LOT else header.LOT}-{wafer_num}"
                    wafer_name = get_wafer_name(key) or key

                # Determine which site value to expose in final data (display) vs. preserved (signed)
                site_display = site_signed if (self.preserve_site_sign or self.site_sign_mode == "signed") else site_stripped
                site_key = site_signed if (self.preserve_site_sign or self.site_sign_mode == "signed") else site_stripped

                full_row = raw_line_no_nl
                expected = param_count if param_count and param_count > 0 else len(model.tests) if hasattr(model, 'tests') and model.tests else 0
                result_line_array = []

                # Parse data row using fixed-width columns starting from the anchor
                if expected > 0:
                    result_line_array = self._parse_fixed_width_columns(
                        raw_line_no_nl,
                        expected,
                        start_offset=self.fixed_width_anchor,
                    )


                actual = len(result_line_array)
                if actual > expected:
                    result_line_array = self._smart_rejoin_to_expected(result_line_array, expected)
                    actual = len(result_line_array)
                if actual > expected:
                    result_line_array = result_line_array[:expected]
                    trimmed_rows += 1
                elif actual < expected:
                    pad_count = expected - actual
                    result_line_array.extend([self.pad_token] * pad_count)
                    padded_rows += 1

                if len(result_line_array) != expected and len(malformed_examples) < 10:
                    malformed_examples.append({
                        'line_no': data_line_counter,
                        'wafer': wafer_num,
                        'site': site_display,
                        'site_signed': site_signed,
                        'expected': expected,
                        'actual': len(result_line_array),
                        'sample': result_line_array[:10]
                    })

                model.misc.setdefault('aligned_rows', []).append({
                    'line_no': data_line_counter,
                    'wafer': wafer_num,
                    'site': site_display,
                    'site_signed': site_signed,
                    'values': result_line_array.copy()
                })

                wafer = model.find('wafers', {'number': wafer_num})
                if not wafer:
                    wafer = Wafer({'number': wafer_num, 'name': wafer_name})
                    model.add('wafers', wafer)

                # Use site_key (signed when preserve_site_sign=True, otherwise sign-stripped) for die lookup
                die = wafer.find('dies', {'site': site_key})
                if not die:
                    die = Die({'site': site_key})
                    # Store display site (sign-stripped if requested) in misc for downstream use
                    try:
                        die.misc = getattr(die, 'misc', {}) or {}
                        die.misc['site_display'] = site_display
                        die.misc['site_signed'] = site_signed
                    except Exception:
                        pass
                    wafer.add('dies', die)

                # Add results to die (already cleaned by chosen method)
                for res in result_line_array:
                    die.add('result', Util.rep_na(res))

            except Exception as e:
                Log.ERROR(f"Unexpected error processing line (suppressed content): {e}")
                Util.dp_exit(1, pplogger=self.pplogger, error=str(e))

        model.misc.setdefault('padding_summary', {})
        model.misc['padding_summary'].update({
            'padded_rows': padded_rows,
            'trimmed_rows': trimmed_rows,
            'nonmatching_rows': nonmatching_row_count,
            'malformed_examples': malformed_examples[:10],
            'param_count': param_count,
            'param_line': param_line,
            'fixed_width_anchor': self.fixed_width_anchor,
            'fixed_width_field_size': self.fixed_width_field_size,
            'preserve_site_sign': self.preserve_site_sign,
            'site_sign_mode': self.site_sign_mode
        })

        if not self.suppress_summary:
            try:
                sanitized_final = self._sanitize_misc({
                    'padding_summary': model.misc.get('padding_summary', {}),
                    'aligned_rows_count': len(model.misc.get('aligned_rows', [])),
                    'param_count': model.misc.get('param_count'),
                    'preserve_site_sign': self.preserve_site_sign,
                    'site_sign_mode': self.site_sign_mode
                })
                Log.INFO("Parsing summary: " + json.dumps(sanitized_final))
            except Exception:
                Log.INFO("Parsing completed (summary suppressed)")

        return model

    # ---------------- epi_scribe_file_to_dict ----------------------------

    def epi_scribe_file_to_dict(self, file_path: str) -> Dict[str, str]:
        """
        Read epi scribe file (Excel or CSV) and return mapping LOT-WAFER -> scribe value.
        Expected columns: [lot, wafer_number, ..., value] with value at index 3 (0-based).
        """
        if not isinstance(file_path, str) or not file_path.strip():
            Log.ERROR("Invalid file path provided for epi scribe reference.")
            Util.dp_exit(1, pplogger=self.pplogger, error="Invalid epi scribe file path.")

        Log.INFO(f"Processing epi scribe reference file: {file_path}")
        file_extension = file_path.split('.')[-1].lower()

        try:
            if file_extension in ('xls', 'xlsx'):
                df = pd.read_excel(file_path)
            elif file_extension == 'csv':
                df = pd.read_csv(file_path)
            else:
                Log.ERROR(f"Unsupported epi scribe file format: {file_extension}")
                Util.dp_exit(1, pplogger=self.pplogger, error=f"Unsupported file format: {file_extension}")

            if df.shape[1] < 4:
                Log.ERROR(f"Epi scribe file '{file_path}' missing expected columns (need >=4).")
                Util.dp_exit(1, pplogger=self.pplogger, error=f"Invalid epi scribe format: {file_path}")

            data: Dict[str, str] = {}
            for _, row in df.iterrows():
                try:
                    lot = str(row.iloc[0]).strip()
                    wafer_num = str(row.iloc[1]).strip()
                    value = str(row.iloc[3]).strip()
                    key = f"{lot}-{wafer_num}"
                    data[key] = value
                except Exception:
                    continue

            Log.INFO(f"Processed {len(data)} epi-scribe entries from '{file_path}'.")
            return data

        except FileNotFoundError:
            Log.ERROR(f"Epi scribe file not found: {file_path}")
            Util.dp_exit(1, pplogger=self.pplogger, error=f"Epi scribe file not found: {file_path}")
        except pd.errors.EmptyDataError:
            Log.ERROR(f"Epi scribe file is empty or corrupted: {file_path}")
            Util.dp_exit(1, pplogger=self.pplogger, error=f"Epi scribe file empty or corrupted: {file_path}")
        except Exception as e:
            Log.ERROR(f"Unexpected error processing epi scribe file '{file_path}': {e}")
            Util.dp_exit(1, pplogger=self.pplogger, error=str(e))