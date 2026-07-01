"""

SYNOPSIS

DESCRIPTION
    Qorvo PSI PARSER CSV

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2025-May-20 - jgarcia - initial
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

class QorvoPsiCrParser(Base):
    """Parser for Qorvo PSI CRSS Final Test Data."""
    def __init__(self, infile, args=None, pplogger=None):
        super().__init__(args)
        self.infile = infile
        self.data = {}
        self.pplogger = pplogger

    @staticmethod
    def extract_measuring_equipment(filename):
        """Extract tool name (TH### or TH-###) from filename and normalize to TH-### format."""
        basename = os.path.basename(filename)
        match = re.search(r'(?<=_)(TH-?\d{3})', basename, re.IGNORECASE)
        if match:
            tool = match.group(1).upper()
            if not tool.startswith("TH-"):
                tool = f"TH-{tool[2:]}"
            return tool
        return "-"
        
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


   
    def extract_header(self):
        header = Metadata()
        key_pattern = re.compile(r"^(Program|Lot Id|WAFER_ID|Operator ID|Comment|Beginning Time|Ending Time)\b", re.IGNORECASE)

        # Define regex patterns for extracting required values
        patterns = {
            "Program": r"Program:\s*(.+)",
            "Lot Id": r"Lot Id:\s*(.+)",
            "WAFER_ID": r"WAFER_ID:\s*,?\s*(.+)",
            "Operator ID": r"Operator ID:\s*,?\s*(.+)",
            "Comment": r"Comment:\s*,?\s*(.*)",
            "Beginning Time": r"(?i)\bBeginning\s*Time[:|,]?\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})",
            "Ending Time": r"(?i)\bEnding\s*Time[:|,]?\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})"
        }

        # Read and filter data from CSV
        try:
            with open(self.infile, 'r') as f:
                data = [row for row in csv.reader(f) if any(cell.strip() for cell in row) and row[0].strip() and re.match(key_pattern, row[0])]
        except csv.Error as e:
            Log.ERROR(f"Error reading CSV: {e}")
            Util.dp_exit(1, pplogger=self.pplogger, error=str(e))

        # Process filtered rows
        for row in data:
            row_str = " ".join(cell.strip() for cell in row if cell.strip())
            matches = {key: re.search(pattern, row_str, re.IGNORECASE) for key, pattern in patterns.items()}

            # Extract values using regex
            if matches["Program"]:
                full_path = matches["Program"].group(1)
                split_parts = full_path.split("\\")
                header.RECIPE = split_parts[split_parts.index("Recipe") + 1] if "Recipe" in split_parts else "NA"

            if matches["Lot Id"]:
                lot_parts = matches["Lot Id"].group(1).split("_")
                header.PRODUCT = lot_parts[1].strip() if len(lot_parts) > 1 else "NA"
                header.LOT = lot_parts[-1].strip()
                header.ALTERNATE_PRODUCT = header.PRODUCT
                header.SOURCE_LOT = f"{header.LOT}.S"

            if matches["WAFER_ID"]:
                header.SCRIBE_ID = matches["WAFER_ID"].group(1).strip() 
                # print(f"TEST_WAFERID={header.SCRIBE_ID}")
            if matches["Operator ID"]:   
                header.OPERATOR = matches["Operator ID"].group(1).strip() 
                # print(f"TEST_OPER={header.OPERATOR}")
            if matches["Comment"]:
                header.COMMENT_EQUIPMENT = matches["Comment"].group(1).strip().split(" ")[-1] 
                # print(f"TEST_ME={header.COMMENT_EQUIPMENT}")
            if matches["Beginning Time"]:
                header.START_TIME = self.parse_and_format_date(matches["Beginning Time"].group(1).strip())
            if matches["Ending Time"]:
                header.END_TIME = self.parse_and_format_date(matches["Ending Time"].group(1).strip()) 
                
        return header
    
    def extract_fourth_value(self):
        """
        Extracts the fourth value from the filename (excluding extension),
        checks if it starts with 'RB' (case insensitive), and returns it.
        Otherwise, returns 'NA'.
        """
        parts = os.path.splitext(os.path.basename(self.infile))[0].split('_')

        return parts[3] if len(parts) > 3 and parts[3].casefold().startswith('rb') else "NA"
    
    def _extract_numeric(self, value):
        match = re.search(r"-?\d+(\.\d+)?([eE][-+]?\d+)?", value)  # Fully captures numeric values
        return match.group(0) if match else "NA"  # Returns extracted number or "NA" if none found

    
    def parse_to_model(self, excluded_params=None):

        excluded_params = [p.lower() for p in (excluded_params or [])]

        header = self.extract_header()
        retest_bin = self.extract_fourth_value()
        header.RETEST_BIN = retest_bin

        # Primary: extract MeasuringEquipment from filename
        header.MEASURING_EQUIPMENT = self.extract_measuring_equipment(self.infile)
        # Fallback: if filename didn't yield a result, try Comment field
        if header.MEASURING_EQUIPMENT == "-" and hasattr(header, 'COMMENT_EQUIPMENT') and header.COMMENT_EQUIPMENT:
            header.MEASURING_EQUIPMENT = header.COMMENT_EQUIPMENT
               
        Log.INFO(f"LOT={header.LOT}--PRODUCT={header.PRODUCT}--RECIPE={header.RECIPE}--START_TIME={header.START_TIME}--END_TIME={header.END_TIME}--RETEST_BIN={header.RETEST_BIN}--ME={header.MEASURING_EQUIPMENT}")
        model = Model({
            'header': header,  # Use passed header instead of extracting it here
            'misc': {},
            'dataSource': 'PSI_CR_CSV'
        })
        self.pplogger.set_model_header(model)
        self.pplogger.set_source_lot(header.SOURCE_LOT)
        try:
            with open(self.infile, 'r') as f:
                data = [row for row in csv.reader(f) if any(cell.strip() for cell in row)]
        except csv.Error as e:
            Log.ERROR(f"Error reading CSV: {e}")
            raise

        data = [row[:-1] if row and row[-1] == '' else row for row in data if any(row)]

        # Filtering out unnecessary lines
        skip_lines = [
            'Average Test Time', 'Idle Time', 'Total Testing Time', 'Total', 'Pass', 'Fail', 'Yield', 
            'BinCode', 'Param name', 'Delay', 'Kelvin_Test', 'Crss_Test', "Date", "Main PC", "User", "Program", "Handler", "Site", "Lot Id", "WAFER_ID", "Operator ID", "Comment", "Beginning Time", "Ending Time"
        ]

        filtered_data = []
        for row in data:
            # Check for known irrelevant lines
            if any(row[0].startswith(skip) for skip in skip_lines):
                continue
            
            # Check for unwanted numeric-bin rows
            if row[0].isdigit() and any(keyword in row[1] for keyword in ['GOOD', 'CONT', 'CRSS', 'Reject']):
                continue

            filtered_data.append(row)
        # print(f"======>>>>{filtered_data}")

        wafer = Wafer({'name': f"{header.LOT}_00", 'number': 0})
        self.pplogger.set_waf_num(wafer.name, "PSI_CRSS")
        test = Test()
        
        valid_test_rows = ["SITE_NUM", "Units", "Lower Limit", "Upper Limit", "Bias1:", "Bias2:"]
        valid_test_rows_regex = [re.compile(rf"^{re.escape(row)}:?$", re.IGNORECASE) for row in valid_test_rows]
        test_parameters = {row: {} for row in valid_test_rows}  # Initialize all test parameters as empty dictionaries
        test_columns = []
        # data_section_pattern = re.compile(r"^\d+,\d+,\d+,[^,]+,\d+,\d+,\d+,\d+,.*$")
        data_section_pattern = re.compile(r"^\d+,\d+,\d+,[^,]*,\d+,\d+,\d+,\d*,.*$")

        test_number = 1
        # test_param_filtered_rows = [row for row in filtered_data if row[0] in valid_test_rows]
        test_param_filtered_rows = [row for row in filtered_data if any(regex.match(row[0].strip()) for regex in valid_test_rows_regex)
]       # test_param_filtered_rows = [row for row in filtered_data if row[0].lower() in (entry.lower() for entry in valid_test_rows)]

        # data_section_filtered_rows = [row for row in filtered_data if data_section_pattern.match(row)]
        data_section_filtered_rows = [row for row in filtered_data if data_section_pattern.match(",".join(row))]
        # data_section_filtered_rows = [row for row in filtered_data if data_section_pattern.match(",".join(row))]

        
        if test_param_filtered_rows:
            for test_param_row in test_param_filtered_rows:
                row_key = test_param_row[0]
                if row_key == "SITE_NUM":
                    # Capture indexes for column 5, column 10, and all beyond column 10
                    # test_columns = [idx for idx in range(5, len(test_param_row)) if idx == 5 or idx >= 10]
                    # test_columns = [idx for idx in range(5, len(test_param_row)) if (idx == 5 or idx >= 10) and test_param_row[idx].strip()]
                    test_columns = [idx for idx in range(5, len(test_param_row)) if (idx == 5 or idx >= 10) and test_param_row[idx].strip() and test_parameters["SITE_NUM"].get(idx, "").lower() not in excluded_params
]

                # Store column values mapped to indices for each valid test parameter row
                if row_key in test_parameters:
                    test_parameters[row_key] = {
                        idx: test_param_row[idx].strip() for idx in test_columns if test_param_row[idx].strip()
                    }
            
            for idx in test_columns:
                test_name = test_parameters["SITE_NUM"].get(idx, "")
                bias1 = test_parameters["Bias1:"].get(idx, "")
                bias2 = test_parameters["Bias2:"].get(idx, "")
                unit = test_parameters["Units"].get(idx, "NA")
                lsl = self._extract_numeric(test_parameters["Lower Limit"].get(idx, "NA"))
                hsl = self._extract_numeric(test_parameters["Upper Limit"].get(idx, "NA"))
                
                # Append Bias1 and Bias2 if available
                if bias1 and bias2:
                    composed_name = f"{test_name}_{bias1}_{bias2}"
                elif bias1:
                    composed_name = f"{test_name}_{bias1}"
                elif bias2:
                    composed_name = f"{test_name}_{bias2}"
                else:
                    composed_name = test_name  # No bias values added
                test = Test()
                test.number = test_number
                test.name = composed_name
                test.LSL = lsl
                test.HSL = hsl
                test.LPL = lsl
                test.HPL = hsl
                test.units = unit
                if test.name.lower() not in excluded_params:
                    wafer.add("tests", test)
                    test_number += 1
        else:
            Log.ERROR("Bad file format-- row with SITE_NUM which contains the test names is missing!")
            Util.dp_exit(1, pplogger=self.pplogger, error="Bad file format-- row with SITE_NUM which contains the test names is missing!")
            
        if data_section_filtered_rows:
            for data_section_row in data_section_filtered_rows:
                if not data_section_row:
                    continue
                site_num = data_section_row[0]
                part_id = data_section_row[1]
                passfg = data_section_row[3]
                hbin = data_section_row[4]

                die = Die({
                    'partid': part_id,
                    'soft_bin': hbin,
                    'hard_bin': hbin,
                    'bindesc': f"SWBin_{hbin.zfill(3)}",
                    'site': site_num,
                    'touchdown_num': "-1",
                    'ecid': part_id
                })
                for idx in test_columns:
                    res = data_section_row[idx]
                    die.add("result", Util.rep_na(res))
                
                wafer.add("dies", die)
                
                # Track sbins
                bin_name_s = f"SWBin_{hbin.zfill(3)}"
                bin_obj_s = wafer.find("sbins", {"number": hbin})
                if bin_obj_s is None:
                    bin_obj_s = Bin({
                        'number': hbin,
                        'name': bin_name_s,
                        'bindesc': bin_name_s,
                        'PF': 'P' if passfg == 'TRUE' else 'F',
                        'count': 1
                    })
                    wafer.add("sbins", bin_obj_s)
                else:
                    bin_obj_s.count += 1  # Increment count for existing bin

                # Track hbins
                bin_name_h = f"HWBin_{hbin.zfill(3)}"
                bin_obj_h = wafer.find("hbins", {"number": hbin})
                if bin_obj_h is None:
                    bin_obj_h = Bin({
                        'number': hbin,
                        'name': bin_name_h,
                        'bindesc': bin_name_h,
                        'PF': 'P' if passfg == 'TRUE' else 'F',
                        'count': 1
                    })
                    wafer.add("hbins", bin_obj_h)
                else:
                    bin_obj_h.count += 1  # Increment count for existing bin
        else:
            Log.ERROR("Bad file format--parametric results data section is missing!")
            Util.dp_exit(1, pplogger=self.pplogger, error="Bad file format--parametric results data section is missing!")
            
        # Assign completed wafer to the model
        model.add("wafers", wafer)
        return model