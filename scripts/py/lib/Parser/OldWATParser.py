"""
SYNOPSIS

DESCRIPTION
    POWERCHIP PCM PARSER - Powerchip WAT parser with robust SPEC parsing and configurable SITE sign handling.
    This version restores immediate inline parsing behavior for UNITS, SPEC HI, SPEC LO and CRIT
    (whitespace split and assign) to maintain original semantics.

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
    
LICENSE
    (C) onsemi 2025 All rights reserved.

"""
from typing import Dict, List, Optional, Tuple, Any
import re
import statistics
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
        self.fixed_width_field_size = 15

        # preserve site sign option: default False (strip leading +/-)
        self.preserve_site_sign = False

        if isinstance(args, dict):
            self.pad_token = args.get('pad_token', self.pad_token)
            self.fixed_width_enabled = args.get('fixed_width_enabled', self.fixed_width_enabled)
            self.fixed_width_field_size = int(args.get('fixed_width_field_size', self.fixed_width_field_size))
            self.preserve_site_sign = bool(args.get('preserve_site_sign', self.preserve_site_sign))

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
        if not header_param_area or param_count <= 0:
            return None
        matches = list(re.finditer(r'\S+', header_param_area))
        if len(matches) < param_count:
            return None
        starts = [m.start() for m in matches[-param_count:]]
        bounds: List[Tuple[int, Optional[int]]] = []
        for i, s in enumerate(starts):
            e = starts[i+1] if i+1 < len(starts) else None
            bounds.append((s, e))
        return bounds

    def _heuristic_insert_na_between_tokens(self, row_param_area: str, expected: int) -> List[str]:
        if expected <= 0:
            return row_param_area.split()
        tokens_spans = [(m.group(0), m.start(), m.end()) for m in re.finditer(r'\S+', row_param_area)]
        if not tokens_spans:
            return [self.pad_token] * expected
        if len(tokens_spans) >= expected:
            return [t for t, s, e in tokens_spans[:expected]]
        gaps = []
        for i in range(len(tokens_spans) - 1):
            gaps.append(tokens_spans[i+1][1] - tokens_spans[i][2])
        first_gap = tokens_spans[0][1]
        positive_gaps = [g for g in gaps if g > 0]
        median_gap = int(statistics.median(positive_gaps)) if positive_gaps else max(1, first_gap)
        threshold = max(int(median_gap * 1.5), 2)
        result: List[str] = []
        tok_idx = 0
        last_assigned_end = None
        for col_idx in range(expected):
            remaining_slots = expected - col_idx
            remaining_tokens = len(tokens_spans) - tok_idx
            if tok_idx >= len(tokens_spans):
                result.append(self.pad_token)
                continue
            token_text, token_start, token_end = tokens_spans[tok_idx]
            if last_assigned_end is None:
                if token_start >= threshold and remaining_slots > remaining_tokens:
                    result.append(self.pad_token)
                    continue
                else:
                    result.append(token_text)
                    last_assigned_end = token_end
                    tok_idx += 1
                    continue
            else:
                gap_before = token_start - last_assigned_end
                if gap_before >= threshold and remaining_slots > remaining_tokens:
                    result.append(self.pad_token)
                    continue
                else:
                    result.append(token_text)
                    last_assigned_end = token_end
                    tok_idx += 1
                    continue
        if len(result) < expected:
            result.extend([self.pad_token] * (expected - len(result)))
        elif len(result) > expected:
            result = result[:expected]
        return result

    def _rejoin_numeric_fragments(self, tokens: List[str]) -> List[str]:
        if not tokens:
            return tokens
        num_re = re.compile(r'^[+-]?\d+(?:\.\d+)?(?:[Ee][+-]?\d+)?$')
        merged: List[str] = []
        i = 0
        n = len(tokens)
        while i < n:
            t = tokens[i]
            if i + 1 < n:
                next_t = tokens[i+1]
                candidate = t + next_t
                candidate_clean = candidate.replace(',', '')
                if num_re.match(candidate_clean):
                    merged.append(candidate_clean)
                    i += 2
                    continue
                candidate2 = t + next_t.lstrip(',')
                if num_re.match(candidate2.replace(',', '')):
                    merged.append(candidate2.replace(',', ''))
                    i += 2
                    continue
            merged.append(t)
            i += 1
        return merged

    def _smart_rejoin_to_expected(self, tokens: List[str], expected: int) -> List[str]:
        if expected <= 0 or len(tokens) <= expected:
            return tokens
        tokens_work = list(tokens)
        num_re = re.compile(r'^[+-]?\d+(?:\.\d+)?(?:[Ee][+-]?\d+)?$')
        while len(tokens_work) > expected:
            merged_this_pass = False
            i = 0
            while i < len(tokens_work) - 1 and len(tokens_work) > expected:
                a = tokens_work[i]
                b = tokens_work[i+1]
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

    def _process_site_value(self, site_raw: str) -> str:
        """
        Process captured SITE value according to preserve_site_sign setting.
        """
        if not site_raw:
            return site_raw
        site = _normalize_line_for_signs(site_raw)
        site = re.sub(r'^([+-])\s+(\d+)$', r'\1\2', site)
        site = site.strip()
        if not self.preserve_site_sign:
            site = site.lstrip('+-')
        return site

    def _find_spec_line_param_start(self, raw_line: str, label: str) -> Optional[int]:
        """
        Find where the first parameter value starts in a SPEC HI/LO/CRIT line.
        This accounts for the different prefix length compared to data rows.
        
        Args:
            raw_line: The raw line containing the SPEC information
            label: The label prefix (e.g., "SPEC HI", "SPEC LO", "CRIT")
        
        Returns:
            Index where first parameter value starts, or None if not found
        """
        line = _normalize_line_for_signs(raw_line)
        # Find the label and skip past it
        label_match = re.search(re.escape(label), line, re.I)
        if not label_match:
            return None
        
        # Find the first numeric value after the label
        # Look for pattern: optional whitespace, then a number (with optional sign, decimal, scientific notation)
        after_label = line[label_match.end():]
        # Match: optional whitespace, then number (can start with +/-, have decimal, scientific notation, or be "NA")
        num_pattern = re.compile(r'\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][+-]?\d+)?|NA)')
        num_match = num_pattern.match(after_label)
        if num_match:
            # Return the absolute position where the number starts
            return label_match.end() + num_match.start()
        
        return None

    def _extract_fixed_width_values(self, raw_line: str, expected: int, absolute_param_start_index: Optional[int] = None, data_row_param_start: Optional[int] = None) -> List[str]:
        """
        Extract values from a line using fixed-width column alignment.
        Used for SPEC HI/LO/CRIT and other summary rows that need to align with test parameters.
        
        Args:
            raw_line: The raw line to parse
            expected: Expected number of parameter values
            absolute_param_start_index: Start index from header line (may not align for SPEC lines)
            data_row_param_start: Start index from data row (better alignment for SPEC lines)
        """
        if expected <= 0:
            return []
        
        line = _normalize_line_for_signs(raw_line)
        result: List[str] = []
        
        # For SPEC HI/LO/CRIT lines, prefer data_row_param_start if available
        # because their prefix length differs from header line
        preferred_start = data_row_param_start if data_row_param_start is not None else absolute_param_start_index
        
        # Use fixed-width parsing if enabled and we have a start index
        if self.fixed_width_enabled and preferred_start is not None:
            start = preferred_start
            width = self.fixed_width_field_size
            needed_len = start + width * expected
            if len(line) < needed_len:
                line_padded = line + ' ' * (needed_len - len(line))
            else:
                line_padded = line
            
            for i in range(expected):
                s = start + i * width
                e = s + width
                chunk = line_padded[s:e]
                token = chunk.strip()
                if token:
                    token = re.sub(r'([+-])\s+(\d)', r'\1\2', token)
                result.append(token if token != "" else self.pad_token)
        else:
            # Fallback to token-based extraction
            # Find the label (e.g., "SPEC HI", "SPEC LO", "CRIT", "STD DEV")
            # and extract values after it
            tokens = line.split()
            if len(tokens) > 1:
                # Detect label length: common patterns are 1-2 words
                # "CRIT" = 1 word, "SPEC HI" = 2 words, "STD DEV" = 2 words
                label_end = 1
                if len(tokens) >= 2 and tokens[0].upper() in ['SPEC', 'STD']:
                    label_end = 2
                # Take values after the label
                values = tokens[label_end:]
                for val in values[:expected]:
                    val_clean = val.strip().strip(',')
                    if val_clean:
                        val_clean = re.sub(r'([+-])\s+(\d)', r'\1\2', val_clean)
                    result.append(val_clean if val_clean != "" else self.pad_token)
            
            # Pad or trim to expected length
            if len(result) < expected:
                result.extend([self.pad_token] * (expected - len(result)))
            elif len(result) > expected:
                result = result[:expected]
        
        return result

    # ---------------- Robust SPEC parsing (token regex fallback kept) ----

    def _parse_spec_line_by_tokens(self, raw_line: str, label_pattern: str, count: int) -> List[str]:
        """
        (Kept for fallback use.) Parse SPEC lines with numeric token regex extraction.
        Caller in this version uses immediate whitespace-split assignment by default,
        but this helper is available if you want to switch to regex extraction.
        """
        if count <= 0:
            return []

        line = _normalize_line_for_signs(raw_line)
        line = re.sub(r'([+-])\s+(\d)', r'\1\2', line)

        label_match = re.search(label_pattern, line, re.I)
        if not label_match:
            return []

        values_str = line[label_match.end():].strip()
        token_re = re.compile(r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][+-]?\d+)?|NA|[^\s]+')
        raw_tokens = token_re.findall(values_str)

        cleaned: List[str] = []
        for t in raw_tokens:
            tt = t.strip().strip(',')
            if tt:
                tt = re.sub(r'([+-])\s+(\d)', r'\1\2', tt)
            cleaned.append(tt if tt != '' else self.pad_token)
        return cleaned

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

        data_line_counter = 0
        cache: Dict[str, Optional[str]] = {}

        # counters for inline spec assignment (original behavior)
        t_units = 0
        t_hi = 0
        t_lo = 0
        crit_counter = 0
        
        # Track where parameter values actually start in data rows (for SPEC line alignment)
        data_row_param_start_index: Optional[int] = None
        
        # Track which tests belong to the current section (for SPEC HI/LO assignment)
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
            'data_row': re.compile(r'^\s*(\d+)\s+(?:(\S+)\s+)?([+-]?\d+)\s+(.*)$'),
            'spec_hi': re.compile(r"\bSPEC\s+HI\b", re.I),
            'spec_lo': re.compile(r"\bSPEC\s+LO\b", re.I),
            'crit': re.compile(r"\bCRIT\b", re.I),
            'waf_epi_scribe': re.compile(r'WAF(?:\s+EpiScribe)?\s+SITE', re.I)
        }

        padded_rows = trimmed_rows = 0
        malformed_examples = []
        nonmatching_row_count = 0

        DEBUG_GROUP_PRINTS = 0

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
                    site_match = re.search(r'\bSITE\b', param_line_raw, re.I)
                    if site_match:
                        param_region_start = site_match.end()
                        header_param_area = param_line_raw[param_region_start:]
                        header_param_len = len(header_param_area)
                    else:
                        header_param_area = param_line_raw
                        header_param_len = len(header_param_area)

                    data_line_array = line.split()[3:] if with_epi_scribe_flag else line.split()[2:]
                    param_count = len(data_line_array)
                    first_param_name = data_line_array[0] if data_line_array else None

                    absolute_param_start_index = None
                    if param_line_raw and first_param_name:
                        idx = param_line_raw.find(first_param_name)
                        if idx != -1:
                            absolute_param_start_index = idx

                    if header_param_area and param_count > 0:
                        param_rel_bounds = self._compute_param_rel_bounds(header_param_area, param_count)
                    else:
                        param_rel_bounds = None

                    # Reset data_row_param_start_index for new section
                    data_row_param_start_index = None
                    
                    # Track where current section's tests start
                    current_section_test_start_index = len(model.tests)

                    # register tests WITHOUT resetting numbering: preserve numbering by using len(model.tests)+1
                    for item in data_line_array:
                        num = len(model.tests) + 1
                        test = Test({'number': num, 'name': item})
                        model.add('tests', test)

                    model.misc['param_count'] = param_count
                    model.misc['param_line'] = param_line
                    model.misc['header_param_line_raw'] = param_line_raw
                    model.misc['absolute_param_start_index'] = absolute_param_start_index
                    model.misc['fixed_width_field_size'] = self.fixed_width_field_size
                    model.misc['preserve_site_sign'] = self.preserve_site_sign

                    continue

                # units line - inline whitespace-split assignment (original style)
                if regex_patterns['units_start'].search(line):
                    data_line_array = line.split()[2:]
                    t_units = 0
                    for val in data_line_array:
                        val = val.strip()
                        if t_units < len(model.tests):
                            model.tests[t_units].units = val
                        t_units += 1
                    continue

                # SPEC HI - token-based parsing (simpler and more reliable for SPEC lines)
                if regex_patterns['spec_hi'].search(line):
                    expected = param_count if param_count and param_count > 0 else len(model.tests) if hasattr(model, 'tests') and model.tests else 0
                    if expected > 0:
                        # Use token-based extraction: split on whitespace and take values after "SPEC HI"
                        tokens = line.split()
                        # Skip "SPEC" and "HI" (2 tokens), then take the rest
                        values = tokens[2:] if len(tokens) > 2 else []
                        # Apply to tests from current section only
                        test_idx = current_section_test_start_index
                        for val in values[:expected]:
                            val_clean = val.strip().strip(',')
                            if val_clean:
                                val_clean = re.sub(r'([+-])\s+(\d)', r'\1\2', val_clean)
                            if test_idx < len(model.tests):
                                model.tests[test_idx].HSL = Util.rep_na(val_clean if val_clean != "" else self.pad_token)
                            test_idx += 1
                    continue

                # SPEC LO - token-based parsing (simpler and more reliable for SPEC lines)
                if regex_patterns['spec_lo'].search(line):
                    expected = param_count if param_count and param_count > 0 else len(model.tests) if hasattr(model, 'tests') and model.tests else 0
                    if expected > 0:
                        # Use token-based extraction: split on whitespace and take values after "SPEC LO"
                        tokens = line.split()
                        # Skip "SPEC" and "LO" (2 tokens), then take the rest
                        values = tokens[2:] if len(tokens) > 2 else []
                        # Apply to tests from current section only
                        test_idx = current_section_test_start_index
                        for val in values[:expected]:
                            val_clean = val.strip().strip(',')
                            if val_clean:
                                val_clean = re.sub(r'([+-])\s+(\d)', r'\1\2', val_clean)
                            if test_idx < len(model.tests):
                                model.tests[test_idx].LSL = Util.rep_na(val_clean if val_clean != "" else self.pad_token)
                            test_idx += 1
                    continue

                # CRIT - token-based parsing (simpler and more reliable for SPEC lines)
                if regex_patterns['crit'].search(line):
                    expected = param_count if param_count and param_count > 0 else len(model.tests) if hasattr(model, 'tests') and model.tests else 0
                    if expected > 0:
                        # Use token-based extraction: split on whitespace and take values after "CRIT"
                        tokens = line.split()
                        # Skip "CRIT" (1 token), then take the rest
                        values = tokens[1:] if len(tokens) > 1 else []
                        # Apply to tests from current section only
                        test_idx = current_section_test_start_index
                        for val in values[:expected]:
                            val_clean = val.strip().strip(',')
                            if val_clean:
                                val_clean = re.sub(r'([+-])\s+(\d)', r'\1\2', val_clean)
                            if test_idx < len(model.tests):
                                model.tests[test_idx].critical = val_clean if val_clean != "" else self.pad_token
                            test_idx += 1
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
                
                # Track where parameter values start in data rows (first data row only)
                # This is used for aligning SPEC HI/LO/CRIT lines
                if data_row_param_start_index is None and m.lastindex >= 4:
                    span4 = m.span(4)
                    if span4 and span4[0] is not None:
                        # Find where the first numeric value starts in the parameter area
                        param_area = raw_line_no_nl[span4[0]:]
                        # Look for first numeric value (with optional sign, decimal, scientific notation)
                        num_match = re.search(r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][+-]?\d+)?', param_area)
                        if num_match:
                            data_row_param_start_index = span4[0] + num_match.start()

                if wafer_num is not None:
                    wafer_num = wafer_num.strip().zfill(2)

                if site_raw is not None:
                    site = self._process_site_value(site_raw)
                else:
                    site = ""

                if wafer_name is not None:
                    wafer_name = wafer_name.strip()
                    epi_scribe_key = f"{header.SOURCE_LOT.removesuffix('.S') if hasattr(header,'SOURCE_LOT') and header.SOURCE_LOT else header.LOT}-{wafer_num}"
                    model.misc[epi_scribe_key] = wafer_name

                if wafer_name is None:
                    key = f"{header.SOURCE_LOT.removesuffix('.S') if hasattr(header,'SOURCE_LOT') and header.SOURCE_LOT else header.LOT}-{wafer_num}"
                    wafer_name = get_wafer_name(key) or key

                full_row = raw_line_no_nl
                expected = param_count if param_count and param_count > 0 else len(model.tests) if hasattr(model, 'tests') and model.tests else 0
                result_line_array: List[str] = []

                # fixed-width primary parsing (data rows)
                if self.fixed_width_enabled and absolute_param_start_index is not None and expected > 0:
                    start = absolute_param_start_index
                    width = self.fixed_width_field_size
                    needed_len = start + width * expected
                    if len(full_row) < needed_len:
                        full_row_padded = full_row + ' ' * (needed_len - len(full_row))
                    else:
                        full_row_padded = full_row
                    for i in range(expected):
                        s = start + i * width
                        e = s + width
                        chunk = full_row_padded[s:e]
                        token = chunk.strip()
                        if token:
                            token = re.sub(r'([+-])\s+(\d)', r'\1\2', token)
                        result_line_array.append(token if token != "" else self.pad_token)
                else:
                    # fallback header-relative slicing or heuristic
                    span4 = m.span(4)
                    row_param_area = full_row[span4[0]:] if span4 and span4[0] is not None else ''
                    if header_param_area and param_count > 0:
                        if len(row_param_area) < header_param_len:
                            row_param_area = row_param_area + ' ' * (header_param_len - len(row_param_area))
                        param_rel_bounds_local = self._compute_param_rel_bounds(header_param_area, param_count)
                        if param_rel_bounds_local:
                            for s_rel, e_rel in param_rel_bounds_local[:expected]:
                                if s_rel >= len(row_param_area):
                                    chunk = ""
                                else:
                                    chunk = row_param_area[s_rel:e_rel] if e_rel is not None else row_param_area[s_rel:]
                                token = chunk.strip()
                                result_line_array.append(token if token != "" else self.pad_token)
                        else:
                            result_line_array = self._heuristic_insert_na_between_tokens(row_param_area, expected)
                            result_line_array = self._rejoin_numeric_fragments(result_line_array)
                    else:
                        result_line_array = self._heuristic_insert_na_between_tokens(row_param_area, expected)
                        result_line_array = self._rejoin_numeric_fragments(result_line_array)

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
                        'site': site,
                        'expected': expected,
                        'actual': len(result_line_array),
                        'sample': result_line_array[:10]
                    })

                model.misc.setdefault('aligned_rows', []).append({
                    'line_no': data_line_counter,
                    'wafer': wafer_num,
                    'site': site,
                    'values': result_line_array.copy()
                })

                wafer = model.find('wafers', {'number': wafer_num})
                if not wafer:
                    wafer = Wafer({'number': wafer_num, 'name': wafer_name})
                    model.add('wafers', wafer)

                die = wafer.find('dies', {'site': site})
                if not die:
                    die = Die({'site': site})
                    wafer.add('dies', die)

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
            'absolute_param_start_index': absolute_param_start_index,
            'fixed_width_field_size': self.fixed_width_field_size,
            'preserve_site_sign': self.preserve_site_sign
        })

        try:
            sanitized_final = self._sanitize_misc({
                'padding_summary': model.misc.get('padding_summary', {}),
                'aligned_rows_count': len(model.misc.get('aligned_rows', [])),
                'param_count': model.misc.get('param_count'),
                'preserve_site_sign': self.preserve_site_sign
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