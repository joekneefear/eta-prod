"""

SYNOPSIS

DESCRIPTION
    Qorvo PSI PARSER CSV

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2025-Mar-11 - jgarcia - initial
    2025-Aug-28 - jgarcia - updated to adhere updated data mapping
    2026-Jan-16 - jgarciaegrated specialized ABSDEL test name formatting with default numeric conversion
    2026-Mar-18 - jgarcia - extract equipment token from filename with normalization

LICENSE
    (C) onsemi 2025 All rights reserved.
"""

import os
import re
import csv
from dateutil import parser
from datetime import datetime
from lib.Data.Base import Base
from lib.Data.Model import Model
from lib.Data.Metadata import Metadata
from lib.Data.Wafer import Wafer
from lib.Data.Test import Test
from lib.Data.Bin import Bin
from lib.Data.Die import Die
from lib.Util import Util
from lib.Log import Log
from typing import Optional, Sequence, Tuple, Set

class QorvoPsiParser(Base):
    """Parser for Qorvo PSI QA Final Test Data."""
    def __init__(self, args=None, pplogger=None):
        super().__init__(args)
        self.args = args or {}
        self.data = {}
        self.pplogger = pplogger
    
    @staticmethod
    def extract_measuring_equipment(filename):
        """Extract TH tool token from filename and normalize to TH-###.

        Rules:
        - Token must be preceded by '_' in the filename.
        - Accepted formats are TH### or TH-### only.
        - Returned format is always TH-###.
        - If no valid token is found, return NA.
        """
        basename = os.path.basename(str(filename or ""))
        match = re.search(r'(?<=_)(TH-?\d{3})(?=(_|\.|$))', basename, re.IGNORECASE)
        if match:
            digits = re.sub(r'\D', '', match.group(1))
            if len(digits) == 3:
                return f"TH-{digits}"
        return "NA"
    
    def construct_testname(self, row):
        """Constructs testname based on item and bias conditions from a single row."""
        test_num = row.get("Test", "").strip()
        item = row.get("Item", "").strip()
        bias1 = row.get("Bias 1", "").strip()
        bias1_value = row.get("Bias 1 Value", "").strip()
        bias1_unit = row.get("Bias 1 Units", "").strip()
        bias2 = row.get("Bias 2", "").strip()
        bias2_value = row.get("Bias 2 Value", "").strip()
        bias2_unit = row.get("Bias 2 Units", "").strip()

        if item.upper() == 'ABSDEL':
            testname_parts = [item]

            def format_val(val):
                # Default to formatting for ABSDEL unless specifically told not to
                if self.args.get('skip_absdel_formatting'):
                    return val
                try:
                    f_val = float(val)
                    return str(int(f_val) if f_val.is_integer() else f_val)
                except (ValueError, TypeError):
                    return val

            if bias1.upper() == 'T#' and bias1_value and bias1_value.upper() != 'NA':
                testname_parts.append(f"T#{format_val(bias1_value)}")

            if bias2.upper() == 'T#' and bias2_value and bias2_value.upper() != 'NA':
                testname_parts.append(f"T#{format_val(bias2_value)}")

            testname = f"T{test_num}:{'_'.join(filter(None, testname_parts))}"
            # Log.INFO(f"Constructed ABSDEL testname: {testname}")
            return testname

        testname_parts = [item]

        if bias1 and bias1.upper() != 'NA' and bias1.upper() != 'T#' and bias1_value and bias1_value.upper() != 'NA':
            bias1_part = f"{bias1}={bias1_value}"
            if bias1_unit:
                bias1_part += f"_{bias1_unit}"
            testname_parts.append(bias1_part)

        if bias2 and bias2.upper() != 'NA' and bias2.upper() != 'T#' and bias2_value and bias2_value.upper() != 'NA':
            bias2_part = f"{bias2}={bias2_value}"
            if bias2_unit:
                bias2_part += f"_{bias2_unit}"
            testname_parts.append(bias2_part)

        testname = '_'.join(filter(None, testname_parts))
        # Log.INFO(f"Constructed testname: {testname}")
        return testname
    
    def parse_and_format_date(self, date_string):
        """
        Parses a date string and returns it in '%Y/%m/%d %H:%M:%S' format.
        
        Parsing rules:
        - If the string starts with a 4-digit year, assume ISO format (YYYY-MM-DD).
        - If AM/PM is present, assume MM/DD/YYYY or MM-DD-YYYY (month-first).
        - If slash-delimited:
            - If first part > 12, assume DD/MM/YYYY.
            - If second part > 12, assume MM/DD/YYYY.
            - If ambiguous, use AM/PM rule or default to DD/MM/YYYY.
        - If hyphen-delimited:
            - Same logic as slash-delimited.
        - If space-separated and ambiguous, default to DD/MM/YYYY.
        """
        try:
            # Default to day-first
            dayfirst = True

            # Extract numeric parts
            parts = list(map(int, re.findall(r'\d+', date_string)[:3]))

            # Check for AM/PM
            has_ampm = bool(re.search(r'\b(AM|PM)\b', date_string, re.IGNORECASE))

            # ISO format: starts with 4-digit year
            if re.match(r'^\s*\d{4}[-/]', date_string):
                dayfirst = False

            # Slash-delimited
            elif '/' in date_string:
                if parts[0] > 12:
                    dayfirst = True
                elif parts[1] > 12:
                    dayfirst = False
                elif has_ampm:
                    dayfirst = False  # Assume MM/DD/YYYY if AM/PM is present
                else:
                    dayfirst = True  # Ambiguous, default to DD/MM/YYYY

            # Hyphen-delimited
            elif '-' in date_string:
                if parts[0] > 12:
                    dayfirst = True
                elif parts[1] > 12:
                    dayfirst = False
                elif has_ampm:
                    dayfirst = False  # Assume MM-DD-YYYY if AM/PM is present
                else:
                    dayfirst = True  # Ambiguous, default to DD/MM/YYYY

            # Space-separated
            elif re.match(r'^\s*\d{2}\s\d{2}\s\d{4}', date_string):
                if parts[0] > 12:
                    dayfirst = True
                elif parts[1] > 12:
                    dayfirst = False
                elif has_ampm:
                    dayfirst = False
                else:
                    dayfirst = True

            # Parse and format
            parsed_date = parser.parse(date_string, dayfirst=dayfirst)
            formatted_date = parsed_date.strftime("%Y/%m/%d %H:%M:%S")
            Log.INFO(f"Formatted date = {formatted_date}")
            return formatted_date

        except (ValueError, TypeError) as e:
            Log.ERROR(f"Error parsing date: {e}")
            Util.dp_exit(1, pplogger=self.pplogger, error=f"Error parsing date: {date_string}")

    def extract_lot_device_recipe_end_time_retestbin(self, data, pStep):
        """Extracts LotId, Device, Recipe, End Time, Retest Bin, and SubconLotId from the data rows.

        Assumptions:
        - A file-name like "FT_FT_DEVICE_LOT_SUBCON..." can appear; the first token is a prefix,
            the second may also be a prefix.
        - After one or two prefixes come: device, lot_id, and optionally subcon_lot_id.
        - 'subcon_lot_id' may be absent; if present but begins with RB / 00 / DT, it's filtered to 'NA'.
        """
        lot_id = device = recipe = end_time = retest_bin = subcon_lot_id = 'NA'

        # Define row mappings based on pStep
        row_mapping = {
            "QA": {
                "CSV File Name": re.compile(r"CSV File Name", re.IGNORECASE),
                "TST File Name for DTA": re.compile(r"TST File Name for DTA", re.IGNORECASE),
                "DTA File Created Date Time": re.compile(r"DTA File Created Date Time", re.IGNORECASE),
                "Comment": re.compile(r"Comment", re.IGNORECASE)
            },
            "FT": {
                "DTA File Name": re.compile(r"DTA File Name", re.IGNORECASE),
                "TST File Name for DTA": re.compile(r"TST File Name for DTA", re.IGNORECASE),
                "DTA File Created Date Time": re.compile(r"DTA File Created Date Time", re.IGNORECASE),
                "Comment": re.compile(r"Comment", re.IGNORECASE)
            }
        }.get(pStep, {})

        # Valid prefixes that can appear in the first and possibly second token
        valid_prefixes: Set[str] = {"FT", "QA", "RG"}

        unwanted_subcon_prefixes = ('RB', '00', 'DT')  # For filtering subcon lot ids

        def strip_trailing_dta(token: str) -> str:
            """Remove a trailing 'DTA' or '.DTA' (case-insensitive) from a token."""
            token = token or ''
            return re.sub(r'(\.DTA|DTA)$', '', token, flags=re.IGNORECASE)

        def parse_filename(value: str) -> Optional[Tuple[str, str, Optional[str]]]:
            """
            Parse a file name into (device, lot_id, subcon_lot_id or None).
            Expected starts with 1–2 prefixes from valid_prefixes.
            Returns None if structure is not sufficient (device/lot not found).
            """
            if value is None:
                return None

            # Split on '_' and trim whitespace; ignore empty tokens
            parts = [p.strip() for p in str(value).split('_') if p and p.strip()]
            if not parts:
                return None

            # Normalize only for prefix checks; keep original casing for device/lot fields
            upper = [p.upper() for p in parts]

            # First token must be a valid prefix
            if upper[0] not in valid_prefixes:
                return None

            # Optionally consume a second prefix
            idx = 1
            if idx < len(parts) and upper[idx] in valid_prefixes:
                idx += 1

            # Need at least device and lot
            if len(parts) <= idx + 1:
                return None

            dev = parts[idx]
            lot = strip_trailing_dta(parts[idx + 1])

            # Optional subcon
            subcon = strip_trailing_dta(parts[idx + 2]) if len(parts) > idx + 2 else None

            # Filter unwanted subcon prefixes
            if subcon:
                if subcon.upper().startswith(unwanted_subcon_prefixes):
                    try:
                        Log.INFO(f"Filtered subcon_lot - {subcon}")
                    except Exception:
                        # If Log isn't available in some contexts, silently proceed
                        pass
                    subcon = None

            return dev, lot, subcon

        for row in data:
            # Skip malformed rows
            if not row or len(row) < 2:
                continue

            key = (row[0] or '')
            value = row[1]

            for pattern_key, pattern in row_mapping.items():
                if not pattern.match(str(key)):
                    continue

                if ((pStep == "QA" and pattern_key == "CSV File Name") or
                    (pStep == "FT" and pattern_key == "DTA File Name")):

                    parsed = parse_filename(value)
                    if parsed:
                        dev, lot, subcon = parsed
                        device = dev or device
                        lot_id = lot or lot_id
                        subcon_lot_id = (subcon if subcon is not None else 'NA')

                elif pattern_key == "TST File Name for DTA":
                    # Recipe is taken as-is
                    recipe = str(value) if value is not None else recipe

                elif pattern_key == "DTA File Created Date Time":
                    # Delegate to your existing date parser
                    end_time = self.parse_and_format_date(value)

                elif pattern_key == "Comment":
                    retest_bin = str(value) if value is not None else retest_bin

        return lot_id, device, recipe, end_time, retest_bin, subcon_lot_id

           
    def parse_to_model(self, infile, pStep=None, excluded_params=None):
        """Parse CSV into Model class object maintaining test number alignment and handling SAME values."""
        model = Model()
        
        if pStep is not None:
            model.dataSource = f"PSI_{pStep}_CSV"
        else:
            model.dataSource = "PSI_CSV"
            
        if excluded_params is None:
            excluded_params = []
        excluded_params = [p.lower() for p in excluded_params]  # Normalize excluded params

        try:
            with open(infile, 'r') as f:
                data = [row for row in csv.reader(f)]
        except csv.Error as e:
            Log.ERROR(f"Error reading CSV: {e}")
            raise

        # Extract headers and map column indices
        lot_id, device, recipe, end_time, retest_bin, subcon_lot_id = self.extract_lot_device_recipe_end_time_retestbin(data, pStep)
        Log.INFO(f"LOT={lot_id}--SUBCON_LOT={subcon_lot_id}--DEVICE={device}--RECIPE={recipe}--TIME={end_time}--RETEST_BIN={retest_bin}")
        if lot_id == 'NA':
            Util.dp_exit(1, pplogger=self.pplogger, error="BAD FILE FORMAT - NO valid Lotid={lot_id}!")
        header_data = {
            'LOT': lot_id,
            'SOURCE_LOT': f"{lot_id}.S",
            'PRODUCT': device,
            'ALTERNATE_PRODUCT': device,
            'RECIPE': recipe,
            'END_TIME': end_time,
            'START_TIME': end_time,
            'RETEST_BIN': retest_bin,
            'SUBCON_LOT': subcon_lot_id,
            'MEASURING_EQUIPMENT': self.extract_measuring_equipment(infile)
        }
        self.pplogger.set_source_lot(header_data.get('SOOURCE_LOT'))
        self.pplogger.set_wafer_flag(True)
        model.header = Metadata(header_data)
        wafer_number = "0"
        wafer = Wafer({'name': f"{lot_id}_00", 'number': wafer_number})
        # wafer.number = 0
        self.pplogger.set_waf_num(wafer.name, "PSI")

       # Locate header row indices
        row_indices = {row[0].strip().lower(): idx for idx, row in enumerate(data) if row}
        row_indices_lower = {key.lower(): value for key, value in row_indices.items()}

        # Extract relevant header rows
        test_row = data[row_indices_lower['test']]
        item_row = data[row_indices_lower['item']]
        limit_row = data[row_indices_lower['limit']]
        limit_min_max_row = data[row_indices_lower['limit min max']]
        limit_units_row = data[row_indices_lower['limit units']]
        bias_1_row = data[row_indices_lower['bias 1']]
        bias_1_value_row = data[row_indices_lower['bias 1 value']]
        bias_1_units_row = data[row_indices_lower['bias 1 units']]
        bias_2_row = data[row_indices_lower['bias 2']]
        bias_2_value_row = data[row_indices_lower['bias 2 value']]
        bias_2_units_row = data[row_indices_lower['bias 2 units']]
        time_row = data[row_indices_lower['time']]
        time_units_row = data[row_indices_lower['time units']]

        # Extract data from rows (handling missing values with 'NA')
        item_numbers = [test_row[i].strip() for i in range(2, len(test_row))]
        item_names = [item_row[i].strip() if item_row[i].strip() else 'NA' for i in range(2, len(test_row))]
        limits = [limit_row[i].strip() if limit_row[i].strip() else 'NA' for i in range(2, len(test_row))]
        limit_min_maxes = [limit_min_max_row[i].strip() if limit_min_max_row[i].strip() else 'NA' for i in range(2, len(test_row))]
        limit_units = [limit_units_row[i].strip() if limit_units_row[i].strip() else 'NA' for i in range(2, len(test_row))]
        bias1 = [bias_1_row[i].strip() if bias_1_row[i].strip() else 'NA' for i in range(2, len(test_row))]
        bias1_value = [bias_1_value_row[i].strip() if bias_1_value_row[i].strip() else 'NA' for i in range(2, len(test_row))]
        bias1_units = [bias_1_units_row[i].strip() if bias_1_units_row[i].strip() else 'NA' for i in range(2, len(test_row))]
        bias2 = [bias_2_row[i].strip() if bias_2_row[i].strip() else 'NA' for i in range(2, len(test_row))]
        bias2_value = [bias_2_value_row[i].strip() if bias_2_value_row[i].strip() else 'NA' for i in range(2, len(test_row))]
        bias2_units = [bias_2_units_row[i].strip() if bias_2_units_row[i].strip() else 'NA' for i in range(2, len(test_row))]
        time = [time_row[i].strip() if time_row[i].strip() else 'NA' for i in range(2, len(test_row))]
        time_units = [time_units_row[i].strip() if time_units_row[i].strip() else 'NA' for i in range(2, len(test_row))]

        # Initialize LSL and HSL arrays
        lsl_array = ['NA'] * len(item_numbers)
        hsl_array = ['NA'] * len(item_numbers)
        item_groups = {}
        i = 0
        while i < len(item_numbers):
            item_name = item_names[i]
            item_number = item_numbers[i]
            bias1_value_str = bias1_value[i]  # Get the Bias 1 value as a string
            bias1_value_float = float(bias1_value_str)  # Convert to non-scientific/absolute value

            if item_name.upper() == "SAME":
                # Find the non-SAME item where the item_number is equal to the bias1_value_float of SAME item
                ref_idx = next((idx for idx in range(len(item_names)) if item_names[idx].upper() != "SAME" and float(item_numbers[idx]) == bias1_value_float), None)
                if ref_idx is not None:
                    ref_item_name = item_names[ref_idx]
                    ref_item_number = item_numbers[ref_idx]
                    ref_test_value = test_row[ref_idx]
                    group_key = ref_item_number  # Use item number as the group key
                    item_groups.setdefault(group_key, []).append(i)
            else:
                group_key = item_number  # Use item number as the group key
                item_groups.setdefault(group_key, []).append(i)

            i += 1
        # # Print item groups for debugging
        # print("Item Groups:", item_groups)

        # Compute final LSL and HSL per group
        for group_name, indices in item_groups.items():
            lsl_values, hsl_values = [], []
            for i in indices:
                limit_value = limits[i] if limits[i].strip() else 'NA'
                if limit_min_maxes[i] == ">":
                    lsl_values.append(limit_value)
                elif limit_min_maxes[i] == "<":
                    hsl_values.append(limit_value)

            final_lsl = max(lsl_values, default='NA')
            final_hsl = min(hsl_values, default='NA')

            # Assign computed values to aligned LSL and HSL arrays
            for i in indices:
                lsl_array[i] = final_lsl
                hsl_array[i] = final_hsl

        test_mapping = {}
        for col_idx in range(2, len(test_row)):
            test_num = test_row[col_idx].strip()

            row_data = {
                "Test": item_numbers[col_idx - 2],
                "Item": item_names[col_idx - 2],
                "Bias 1": bias1[col_idx - 2],
                "Bias 1 Value": bias1_value[col_idx - 2],
                "Bias 1 Units": bias1_units[col_idx - 2],
                "Bias 2": bias2[col_idx - 2],
                "Bias 2 Value": bias2_value[col_idx - 2],
                "Bias 2 Units": bias2_units[col_idx - 2]
            }

            test = Test({
                'number': test_num,
                'name': self.construct_testname(row_data),
                'LPL': lsl_array[col_idx - 2],
                'HPL': hsl_array[col_idx - 2],
                'LSL': lsl_array[col_idx - 2],
                'HSL': hsl_array[col_idx - 2],
                'units': limit_units[col_idx - 2]
            })

            if item_names[col_idx - 2].lower() not in excluded_params:
                wafer.add("tests", test)
                test_mapping[test_num] = {'col_idx': col_idx}

        # Process die results
        serial_start_idx = row_indices_lower.get('serial') + 1
        
        if serial_start_idx is not None:
            for row in data[serial_start_idx:]:
                if not row:
                    continue

                partid = row[0]

                soft_bin = row[1]

                # Create or find the Die object
                die = Die({
                    'partid': partid,
                    'soft_bin': soft_bin,
                    'hard_bin': soft_bin,
                    'bindesc':  f"SWBin_{soft_bin.zfill(3)}",
                    'site': 1,
                    'touchdown_num': -1,
                    'ecid': partid
                })
                for test in wafer.tests:
                    col_idx = test_mapping[test.number]['col_idx']
                    result = row[col_idx] if col_idx < len(row) else 'NA'
                    die.add("result", Util.rep_na(result))

                wafer.add("dies", die)

                # Track sbins
                bin_name_s = f"SWBin_{soft_bin.zfill(3)}"
                bin_obj_s = wafer.find("sbins", {"number": soft_bin})
                if bin_obj_s is None:
                    bin_obj_s = Bin({
                        'number': soft_bin,
                        'name': bin_name_s,
                        'bindesc': bin_name_s,
                        'PF': 'P' if soft_bin == '1' else 'F',
                        'count': 1
                    })
                    wafer.add("sbins", bin_obj_s)
                else:
                    bin_obj_s.count += 1  # Increment count for existing bin

                # Track hbins
                bin_name_h = f"HWBin_{soft_bin.zfill(3)}"
                bin_obj_h = wafer.find("hbins", {"number": soft_bin})
                if bin_obj_h is None:
                    bin_obj_h = Bin({
                        'number': soft_bin,
                        'name': bin_name_h,
                        'bindesc': bin_name_h,
                        'PF': 'P' if soft_bin == '1' else 'F',
                        'count': 1
                    })
                    wafer.add("hbins", bin_obj_h)
                else:
                    bin_obj_h.count += 1  # Increment count for existing bin
        else:
            Log.ERROR(f"BAD FILE FORMAT - row data start's with 'Serial' is required and it is missing from row")    
            Util.dp_exit(1, pplogger=self.pplogger, error="BAD FILE FORMAT - row data start's with 'Serial' is required and it is missing from row")
     
        # Assign completed wafer to the model
        model.add("wafers", wafer)
        return model
    
    def parse_start_time(line):
        # Define the regex pattern to extract the datetime part
        pattern = re.compile(r"Start Time:DataTime:(.*)")
        match = pattern.search(line)
        if match:
            datetime_str = match.group(1).strip()
            # Parse the datetime string
            try:
                date_obj = datetime.strptime(datetime_str, "%d/%m/%Y %I:%M:%S %p")
                return date_obj.strftime("%Y-%m-%d %H:%M:%S")
            except ValueError:
                return 'NA'
        return 'NA'

    
    def extract_fields_from_data_rg(self, data):
        """
        Extracts lot_id, device, subcon_lot_id, and recipe from raw data rows.

        Change: when parsing the filename, use only the basename up to the final "dot-suffix"
        (for example: "RG_FT_UJ4C075044K4S_510008U8.CAP_D" -> "RG_FT_UJ4C075044K4S_510008U8")
        before splitting on underscores. Also still remove a trailing literal ".string"
        if the whole basename ends with it.
        """
        row_mapping = {
            "DataFileName": re.compile(r"^DataFileName", re.IGNORECASE),
            "TestFileName": re.compile(r"^TestFileName", re.IGNORECASE),
        }
        valid_prefixes: Set[str] = {"FT", "QA", "RG"}
        unwanted_subcon_prefixes = ("RB", "00", "DT")

        lot_id = device = subcon_lot_id = recipe = "NA"

        def basename(value) -> str:
            """Return last path component for either Windows or POSIX-like paths."""
            s = "" if value is None else str(value)
            s = s.rsplit("\\", 1)[-1]
            s = s.rsplit("/", 1)[-1]
            return s.strip()

        def strip_extensions(token: Optional[str]) -> str:
            """
            Remove one or more trailing file-like extensions, e.g. '.dta', '.tst', '.csv', '.gz'.
            Keeps internal dots (e.g., 'DEVX.V1') unless they are at the very end.
            """
            token = "" if token is None else str(token)
            token = re.sub(r"(?:\.[A-Za-z0-9]{1,10})+$", "", token, flags=re.IGNORECASE)
            return token.strip("_- ")

        def normalize_cell(v) -> str:
            """
            Normalize the raw cell value:
            - For tag-like objects prefer .string then .text if present and non-None.
            - Convert to str and strip whitespace.
            NOTE: Do NOT remove literal ".string" here; that removal is applied only
            when parsing filenames so the rule "remove '.string' only when it appears
            as a trailing suffix of the whole filename" is respected.
            """
            if v is None:
                return ""
            try:
                if hasattr(v, "string") and getattr(v, "string") is not None:
                    s = getattr(v, "string")
                elif hasattr(v, "text") and getattr(v, "text") is not None:
                    s = getattr(v, "text")
                else:
                    s = v
            except Exception:
                s = v

            s = "" if s is None else str(s)
            return s.strip()

        def parse_filename(value: str) -> Optional[Tuple[str, str, Optional[str]]]:
            """
            Parse a file name into (device, lot_id, subcon_lot_id or None).
            Expected: 1–2 leading prefixes from valid_prefixes, then device, lot, [subcon?].

            Behavior:
            - Work with the basename.
            - Remove trailing ".string" only when it is the suffix of the whole basename.
            - Remove the final dot-suffix (everything from the final '.' to the end),
            e.g. ".CAP_D", ".csv", ".tst.gz" (the latter will remove the last segment,
            leaving ".tst" — strip_extensions will further clean tokens).
            - Then split on underscores and extract tokens.
            """
            # get basename first
            fname = basename(value)

            # remove literal trailing ".string" only if it's a suffix of the whole filename
            fname = re.sub(r"\.string$", "", fname, flags=re.IGNORECASE)

            # remove the final dot-suffix (e.g. ".CAP_D", ".csv", ".gz", etc.)
            # This strips everything from the last '.' to the end of the basename.
            fname = re.sub(r"\.[^.]*$", "", fname)

            parts: List[str] = [p.strip() for p in fname.split("_") if p and p.strip()]
            if not parts:
                return None

            upper = [p.upper() for p in parts]

            # First token must be a valid prefix
            if upper[0] not in valid_prefixes:
                return None

            # Consume optional second prefix
            j = 1
            if len(parts) > 1 and upper[1] in valid_prefixes:
                j = 2

            # Need device and lot at least
            if len(parts) <= j + 1:
                return None

            dev = strip_extensions(parts[j])
            lot = strip_extensions(parts[j + 1])
            subcon = strip_extensions(parts[j + 2]) if len(parts) > j + 2 else None

            # Filter unwanted subcon prefixes
            if subcon and subcon.upper().startswith(unwanted_subcon_prefixes):
                try:
                    Log.INFO(f"Filtered subcon_lot - {subcon}")
                except Exception:
                    pass
                subcon = None

            return dev, lot, subcon

        for row in data:
            if not row or len(row) < 1:
                continue

            key = "" if row[0] is None else str(row[0])

            # Normalize the raw cell value as soon as we fetch it.
            raw_value = row[1] if len(row) > 1 else ""
            value = normalize_cell(raw_value)

            # DataFileName parsing
            if row_mapping["DataFileName"].match(key):
                parsed = parse_filename(value)
                if parsed:
                    dev, lot, subcon = parsed
                    device = dev
                    lot_id = lot
                    subcon_lot_id = subcon if subcon is not None else "NA"

            # TestFileName parsing
            elif row_mapping["TestFileName"].match(key):
                # Keep recipe as-is (with extension), unless you want to drop extension too
                recipe = basename(value)

        return lot_id, device, subcon_lot_id, recipe
    
    def extract_times_RG(self, data):
        for row in data:
            if row[0].startswith('Start Time:DataTime:'):
                start_time = self.parse_and_format_date(row[0].split(':', 2)[2].strip())
        return start_time
    
    def construct_testname_RG(self, row_data):
        """
        Constructs a case-insensitive test name based on the provided row data.
        Parameters:
        row_data (dict): A dictionary containing test details.
        
        Returns:
        str: The constructed test name.
        """
        # Normalize keys to lowercase for case-insensitive lookup
        row_data_normalized = {key.lower(): value for key, value in row_data.items()}
        
        test_num = row_data_normalized.get("test", "")
        item = row_data_normalized.get("item", "")
        volt = row_data_normalized.get("volt", "")
        freq = row_data_normalized.get("freq", "")
        level = row_data_normalized.get("level", "")
        
        # Construct the test name
        test_name_parts = [item]
        
        if volt:
            test_name_parts.append(f"Volt={volt}")
        if freq:
            test_name_parts.append(f"FREQ={freq}")
        if level:
            test_name_parts.append(f"Level={level}")
        
        test_name = "_".join(test_name_parts)
        
        return test_name
   
    def extract_numeric_from_str_RG(self, str_value):
        """
        Process the result value and update the test limits accordingly.
        
        Parameters:
        str_value (str): The result value to process.
        
        Returns:
        str: The processed result value.
        """
        if isinstance(str_value, str) and any(char.isdigit() for char in str_value):
            extracted_number = re.sub(r'[^\d.-]', '', str_value)
            extracted_non_digit = re.findall(r'\D+', str_value)
            
            try:
                if any(unit in extracted_non_digit for unit in ['mOhm', 'm']):
                    extracted_number = float(extracted_number) / 1000
                return str(extracted_number)
            except ValueError:
                Log.ERROR(f"Error converting {extracted_number} to float.")
                Util.dp_exit(1, pplogger=self.pplogger, error=f"Error converting {extracted_number} to float.")
                return str_value
        
        return str_value
    
    def parse_to_model_RG(self, infile, excluded_params=None):
        model = Model()
        model.dataSource = 'PSI_RG_CSV'
        excluded_params = [p.lower() for p in (excluded_params or [])]
        default_lsl = -.5
        default_hsl = .5
        try:
            with open(infile, 'r') as f:
                data = [row for row in csv.reader(f) if any(cell.strip() for cell in row)]
        except csv.Error as e:
            Log.ERROR(f"Error reading CSV: {e}")
            raise

        data = [row[:-1] if row and row[-1] == '' else row for row in data if any(row)]
         
        # Skip specific lines outside the ItemName section
        skip_lines = [
            'Total', 'Pass', 'Fail', 'Yield', 'Min', 'Max', 'Avg', 'STDEV', 'Data10%', 'Data50%', 'Data90%'
        ]
        itemname_section = False
        filtered_data = []
        for row in data:
            if row[0].startswith('ItemName'):
                itemname_section = True
            # elif any(row[0].startswith(end) for end in ['FREQ', 'Level', 'Avg', 'Function', 'Delay']):
            elif any(row[0].startswith(end) for end in ['Total']):
                itemname_section = False
            if not itemname_section and any(row[0].startswith(skip) for skip in skip_lines):
                continue
            filtered_data.append(row)
        data = filtered_data
        
        lot_id, device, subcon_lot_id, recipe = self.extract_fields_from_data_rg(data)
        start_time = self.extract_times_RG(data)
        Log.INFO(f"LOT={lot_id}--SUBCONLOT={subcon_lot_id}--DEVICE={device}--RECIPE={recipe}--STARTTIME={start_time}")
        if lot_id == 'NA':
            Util.dp_exit(1, pplogger=self.pplogger, error="BAD FILE FORMAT - NO valid Lotid={lot_id}!")
        header_data = {
            'LOT': lot_id,
            'SOURCE_LOT': f"{lot_id}.S",
            'PRODUCT': device,
            'ALTERNATE_PRODUCT': device,
            'RECIPE': recipe,
            'END_TIME': start_time,
            'START_TIME': start_time,
            'SUBCON_LOT': subcon_lot_id,
            'MEASURING_EQUIPMENT': self.extract_measuring_equipment(infile)
        }
        self.pplogger.set_source_lot(header_data.get('SOOURCE_LOT'))
        self.pplogger.set_wafer_flag(True)
        model.header = Metadata(header_data)
        wafer = Wafer({'name': f"{lot_id}_00", 'number': 0})
        self.pplogger.set_waf_num(wafer.name, "PSI")
        row_indices = {row[0].strip().lower(): idx for idx, row in enumerate(data) if row}
        row_indices_lower = {key.lower(): value for key, value in row_indices.items()}
        try:
            test_row = data[row_indices_lower['itemname']]
            volt_row = data[row_indices_lower['volt']]
            max_row = data[row_indices_lower['max']]
            min_row = data[row_indices_lower['min']]
            freq_row = data[row_indices_lower['freq']]
            level_row = data[row_indices_lower['level']]
            avg_row = data[row_indices_lower['avg']]
            function_row = data[row_indices_lower['function']]
            delay_row = data[row_indices_lower['delay']]
        except KeyError as e:
            Log.ERROR(f"Row name: '{e.args[0]} not found in RG data file.")
            Util.dp_exit(1, pplogger=self.pplogger, error=f"BAD file format!!!")
        item_names = [test_row[i].strip() for i in range(3, len(test_row))]
        volts = [volt_row[i].strip() if volt_row[i].strip() else 'NA' for i in range(3, len(test_row))]
        max_values = [max_row[i].strip() if max_row[i].strip() else 'NA' for i in range(3, len(test_row))]
        min_values = [min_row[i].strip() if min_row[i].strip() else 'NA' for i in range(3, len(test_row))]
        freqs = [freq_row[i].strip() if freq_row[i].strip() else 'NA' for i in range(3, len(test_row))]
        levels = [level_row[i].strip() if level_row[i].strip() else 'NA' for i in range(3, len(test_row))]
        avgs = [avg_row[i].strip() if avg_row[i].strip() else 'NA' for i in range(3, len(test_row))]
        functions = [function_row[i].strip() if function_row[i].strip() else 'NA' for i in range(3, len(test_row))]
        delays = [delay_row[i].strip() if delay_row[i].strip() else 'NA' for i in range(3, len(test_row))]
        
        # Ensure all lists have the same length as item_names
        def fill_missing_data(data_list, length, default='NA'):
            return data_list + [default] * (length - len(data_list))
        
        volts = fill_missing_data(volts, len(item_names))
        max_values = fill_missing_data(max_values, len(item_names))
        min_values = fill_missing_data(min_values, len(item_names))
        freqs = fill_missing_data(freqs, len(item_names))
        levels = fill_missing_data(levels, len(item_names))
        avgs = fill_missing_data(avgs, len(item_names))
        functions = fill_missing_data(functions, len(item_names))
        delays = fill_missing_data(delays, len(item_names))
        
        test_mapping = {}
        for test_index, test_name in enumerate(item_names, start=1):
            adjusted_index = test_index - 1
            
            column_index = test_index + 2
            test_mapping[test_index] = column_index
            test_number = test_index
            row_data = {
                "Test": test_number,
                "Item": test_name,
                "Volt": volts[adjusted_index],
                "FREQ": freqs[adjusted_index],
                "Level": levels[adjusted_index]
            }
            lsl = str(self.extract_numeric_from_str_RG(min_values[adjusted_index]))
            hsl = str(self.extract_numeric_from_str_RG(max_values[adjusted_index]))
            lpl = str(self.extract_numeric_from_str_RG(min_values[adjusted_index]))
            hpl = str(self.extract_numeric_from_str_RG(max_values[adjusted_index]))
            test = Test({
                'number': test_number,
                'name': self.construct_testname_RG(row_data),
                'LPL': lpl,
                'HPL': hpl,
                'LSL': lsl,
                'HSL': hsl,
                'units': 'NA'
            })
            wafer.add("tests", test)
        serial_start_idx = row_indices_lower['id'] + 1
        for row in data[serial_start_idx:]:
            if not row or len(row) < 2 or row[0].startswith('End Time:'):
                continue
            if row[0].startswith('End Time:'):
                continue
            else:
                partid = row[0]
                pass_fail = row[1]
                soft_bin = row[2]
                die = Die({
                    'partid': partid,
                    'soft_bin': soft_bin,
                    'hard_bin': soft_bin,
                    'bindesc': f"SWBin_{soft_bin.zfill(3)}",
                    'site': "1",
                    'touchdown_num': "-1",
                    'ecid': partid
                })
                test_counter = 0
                for test in wafer.tests:
                    test_number = test.number
                    col_idx = test_mapping[test_number]
                    result_value = Util.trim(row[col_idx]) if col_idx < len(row) else 'NA'
                    if result_value == "OK":
                        wafer.tests[test_counter].LSL = float(default_lsl)
                        wafer.tests[test_counter].LPL = float(default_lsl)
                        wafer.tests[test_counter].HSL = float(default_hsl)
                        wafer.tests[test_counter].HPL = float(default_hsl)
                        result_value = '0'
                    elif result_value == "NG":
                        wafer.tests[test_counter].LSL = float(default_lsl)
                        wafer.tests[test_counter].LPL = float(default_lsl)
                        wafer.tests[test_counter].HSL = float(default_hsl)
                        wafer.tests[test_counter].HPL = float(default_hsl)
                        result_value = '1'

                    elif isinstance(result_value, str) and any(char.isdigit() for char in result_value) and result_value not in ['OK', 'NG']:
                        numeric_part = re.sub(r'[^\d.-]', '', result_value)
                        extracted_non_digit = re.findall(r'\D+', result_value)
                        # print(f"Extracted numeric part: {numeric_part}")  # Debugging statement
                        # print(f"Extracted non-digit part: {extracted_non_digit}")  # Debugging statement
                        try:
                            if any(unit in extracted_non_digit for unit in ['mOhm', 'm']):
                                numeric_part = float(numeric_part) / 1000
                                # print(f"Converted numeric part: {numeric_part}")  # Debugging statement
                            result_value = str(numeric_part)
                        except ValueError:
                            Log.ERROR(f"Error converting '{numeric_part}' to float.")
                            Util.dp_exit(1, pplogger=self.pplogger, error=f"Error converting {numeric_part} to float.")
                            result_value = numeric_part

                    die.add("result", Util.rep_na(result_value))
                    test_counter = test_counter + 1
                wafer.add("dies", die)
                bin_name_s = f"SWBin_{soft_bin.zfill(3)}"
                bin_obj_s = wafer.find("sbins", {"number": soft_bin})
                if bin_obj_s is None:
                    bin_obj_s = Bin({
                        'number': soft_bin,
                        'name': bin_name_s,
                        'bindesc': bin_name_s,
                        'PF': pass_fail,
                        'count': 1
                    })
                    wafer.add("sbins", bin_obj_s)
                else:
                    bin_obj_s.count += 1
                bin_name_h = f"HWBin_{soft_bin.zfill(3)}"
                bin_obj_h = wafer.find("hbins", {"number": soft_bin})
                if bin_obj_h is None:
                    bin_obj_h = Bin({
                        'number': soft_bin,
                        'name': bin_name_h,
                        'bindesc': bin_name_h,
                        'PF': pass_fail,
                        'count': 1
                    })
                    wafer.add("hbins", bin_obj_h)
                else:
                    bin_obj_h.count += 1
        model.add("wafers", wafer)
        return model
    
    