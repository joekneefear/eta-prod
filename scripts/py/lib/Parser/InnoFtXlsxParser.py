"""
SYNOPSIS
    Parser for INNO Final Test (FT) Excel format test data

DESCRIPTION
    Parses .xlsx files produced by INNO test equipment.
    Extracts header metadata and test results into a Model object.
    Header block contains metadata labels (Program, Product, etc.)
    Test table contains test names, limits, units, and die data.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2026-Jul-02 - Initial Python implementation

LICENSE
    (C) onsemi 2026 All rights reserved.
"""

import os
import re
from typing import Optional, List, Dict, Any, Tuple
from openpyxl import load_workbook

from lib.Data.Model import Model
from lib.Data.Wafer import Wafer
from lib.Data.Test import Test
from lib.Data.Die import Die
from lib.Data.Bin import Bin
from lib.Data.Metadata import Metadata
from lib.Log import Log
from lib.Util import Util


class InnoFtXlsxParser:
    """
    Parser for INNO Final Test (FT) Excel format.
    
    Parses xlsx files with:
    - Header block: key-value pairs (label in col A, value in col B or C)
    - Test table: test names, limits (LL/HL), units, and die data rows
    
    Outputs a Model with:
    - model.header: Metadata with parsed fields (raw_header stored as _raw attr)
    - model.tests: List of Test objects with limits and units
    - model.wafers[0].dies: List of Die objects with test results
    - model.wafers[0].sbins/hbins: Bin objects with counts
    """
    
    # Compiled regex patterns for performance
    _PATTERNS = {
        'numeric_row': re.compile(r'^\d+$'),
        'test_param': re.compile(r'Test\s*Parameter', re.IGNORECASE),
        'll_limit': re.compile(r'^LL$', re.IGNORECASE),
        'hl_limit': re.compile(r'^HL$', re.IGNORECASE),
        'unit_row': re.compile(r'^Unit$', re.IGNORECASE),
        'test_table_marker': re.compile(r'^No$', re.IGNORECASE),
        'test_num_row': re.compile(r'^Test#$', re.IGNORECASE),
        'whitespace': re.compile(r'^\s*$'),
    }
    
    # Known header labels to capture
    _HEADER_LABELS = {
        'Program', 'Product', 'WaferModle', 'LotID', 'TesterId', 'Handler',
        'Device Name', 'Test temp', 'TestDate', 'Sub LotID', 'Operator ID'
    }
    
    def __init__(self, pplogger=None):
        """
        Initialize parser.
        
        Args:
            pplogger: Optional PPLogger instance for logging (not used in this phase)
        """
        self.pplogger = pplogger
        self.logger = Log()
    
    def parse_to_model(self, infile: str) -> Model:
        """
        Parse Excel file into Model object.
        
        Args:
            infile: Path to .xlsx file to parse
            
        Returns:
            Model object with parsed data
            
        Raises:
            FileNotFoundError: If input file doesn't exist
            Exception: If Excel file is invalid or parsing fails
        """
        if not os.path.exists(infile):
            error_msg = f"File not found: {infile}"
            self.logger.ERROR(error_msg)
            Util.dp_exit(1, pplogger=self.pplogger, error=error_msg)
        
        self.logger.INFO(f"Parsing INNO FT XLSX file: {infile}")
        
        # Initialize model
        header = Metadata()
        model = Model({
            'header': header,
            'misc': {},
            'dataSource': 'INNO_FT_XLSX'
        })
        
        # Initialize wafer (wafer number 0 for discrete device testing)
        # Set START_TIME and END_TIME to None initially (will be set by enricher)
        wafer = Wafer({
            'number': 0,
            'START_TIME': None,
            'END_TIME': None
        })
        model.add('wafers', wafer)
        
        # Parse Excel file
        self._parse_excel_file(infile, model, wafer, header)
        
        # Log parsed metadata
        self.logger.INFO(
            f"LOT={header.LOT}--DEVICE={header.PRODUCT}--PROGRAM={header.RECIPE}--"
            f"RECIPE_REVISION={header.RECIPE_REVISION}--TIME={header.START_TIME}"
        )
        
        self.logger.INFO(
            f"Parsing complete: {len(model.tests)} tests, {len(wafer.dies)} dies, "
            f"{len(wafer.sbins)} sbins, {len(wafer.hbins)} hbins"
        )
        
        return model
    
    def _parse_excel_file(self, infile: str, model: Model, wafer: Wafer, 
                          header: Metadata) -> None:
        """
        Parse Excel file and populate model, wafer, and header.
        
        Args:
            infile: Path to Excel file
            model: Model object to populate
            wafer: Wafer object to populate
            header: Metadata object to populate
        """
        try:
            workbook = load_workbook(infile, data_only=True, read_only=True)
            worksheet = workbook.worksheets[0]
        except Exception as e:
            error_msg = f"Failed to load Excel file: {e}"
            self.logger.ERROR(error_msg)
            Util.dp_exit(1, pplogger=self.pplogger, error=error_msg)
        
        # Parse state
        raw_header: Dict[str, str] = {}
        test_names: List[str] = []
        lo_limits: List[str] = []
        hi_limits: List[str] = []
        units: List[str] = []
        data_flag = False
        
        rows = list(worksheet.iter_rows(values_only=True))
        
        for row_idx, row in enumerate(rows):
            # Skip empty rows
            if not row or not row[0]:
                continue
            
            # Clean row data
            row_data = [self._clean_cell(cell) for cell in row]
            col_a = row_data[0] if row_data else ''
            col_b = row_data[1] if len(row_data) > 1 else ''
            col_c = row_data[2] if len(row_data) > 2 else ''
            
            # Check for test table start marker
            if self._PATTERNS['test_table_marker'].match(col_a):
                self.logger.INFO(f"Found test table marker at row {row_idx + 1}: {col_a}")
                data_flag = True
                continue
            
            # Parse header block (before test table)
            if not data_flag:
                # Try to match known header labels
                if col_a in self._HEADER_LABELS:
                    # Header format: [Label, empty, Value] or [Label, Value]
                    value = col_c if col_c else col_b
                    value = Util.trim(value) if value else 'NA'
                    # Replace whitespace-only with NA
                    if self._PATTERNS['whitespace'].match(str(value)):
                        value = 'NA'
                    raw_header[col_a] = value
                    self.logger.INFO(f"Parsed header: {col_a}={value}")
                    continue
            
            # Parse test table rows
            if data_flag:
                # Debug: log col_a to see what we're trying to match
                self.logger.DEBUG(f"Processing row with col_a='{col_a}', data_flag={data_flag}")
                
                # Test# row: Structure is blank/Test#/blank/T1/T2/T3...
                # Test names start from column D (index 3) because of blank column C
                if col_b and self._PATTERNS['test_num_row'].match(col_b):
                    test_names = [self._clean_cell(c) for c in row_data[3:]]
                    self.logger.INFO(f"Found {len(test_names)} test IDs: {test_names}")
                    continue

                # Test Parameter row: blank/Test Parameter/blank/Vth_HT/Igss_HT...
                if col_b and self._PATTERNS['test_param'].match(col_b):
                    test_names = [self._clean_cell(c) for c in row_data[3:]]
                    self.logger.INFO(f"Found {len(test_names)} test names: {test_names}")
                    continue
                
                # LL (Low Limit) row: blank/LL/blank/1/-10000/120...
                if col_b and self._PATTERNS['ll_limit'].match(col_b):
                    lo_limits = [self._clean_cell(c) for c in row_data[3:]]
                    self.logger.INFO(f"Found {len(lo_limits)} low limits")
                    continue
                
                # HL (High Limit) row: blank/HL/blank/3.5/508000/220...
                if col_b and self._PATTERNS['hl_limit'].match(col_b):
                    hi_limits = [self._clean_cell(c) for c in row_data[3:]]
                    self.logger.INFO(f"Found {len(hi_limits)} high limits")
                    continue
                
                # Unit row: blank/Unit/blank/V/nA/mohm...
                if col_b and self._PATTERNS['unit_row'].match(col_b):
                    units = [self._clean_cell(c) for c in row_data[3:]]
                    self.logger.INFO(f"Found {len(units)} units")
                    continue
                
                # Data row: col_a is numeric (die index), col_b is BIN
                if col_a and self._PATTERNS['numeric_row'].match(col_a):
                    self._parse_die_data(row_data, wafer, test_names)
        
        # Set raw_header on model.header
        header._raw = raw_header
        
        # Set LOT from raw_header
        header.LOT = raw_header.get('LotID', 'NA')
        
        # Create Test objects only if test_names were found
        if test_names:
            self._create_tests(model, wafer, test_names, lo_limits, hi_limits, units)
        else:
            self.logger.WARN("No test names found - skipping test creation")
    
    def _clean_cell(self, value: Any) -> str:
        """
        Clean cell value: handle None, convert to string, strip whitespace.
        
        Args:
            value: Cell value from Excel
            
        Returns:
            Cleaned string
        """
        if value is None or str(value).lower() == 'nan':
            return ''
        
        return str(value).strip()
    
    def _parse_die_data(self, row_data: List[str], wafer: Wafer, 
                        test_names: List[str]) -> None:
        """
        Parse one data row into a Die object.
        
        Column mapping for INNO FT Excel data rows:
          col[0] = die index (No: 1, 2, 3...)
          col[1] = BIN value (1, 1, 1...)
          col[2] onwards = test results aligned to test_names
        
        Note: Data rows have different structure than header rows.
        Header rows: blank | label | blank | data...
        Data rows: No | BIN | data... (no blank column before data)
        
        Args:
            row_data: Cleaned row data
            wafer: Wafer object to add die to
            test_names: List of test names for result alignment
        """
        if len(row_data) < 2:
            return
        
        die_index = row_data[0] if row_data else '0'
        soft_bin = row_data[1] if len(row_data) > 1 else '0'
        
        # Extract numeric part of bin
        bin_numeric = re.sub(r'\D', '', soft_bin)
        if not bin_numeric:
            bin_numeric = '0'
        
        # Determine pass/fail
        pass_fail = 'P' if bin_numeric == '1' else 'F'
        
        # Use die_index as partid
        partid = die_index
        
        die = Die({
            'partid': partid,
            'soft_bin': bin_numeric,
            'hard_bin': bin_numeric,
            'bindesc': f"SWBin_{bin_numeric.zfill(3)}",
            'site': 1,
            'touchdown_num': -1,
            'ecid': partid,
        })
        
        # Parse test results starting from column C (index 2) - data rows don't have blank column
        for i in range(len(test_names)):
            col_idx = 2 + i
            if col_idx < len(row_data):
                result_val = row_data[col_idx]
                cleaned = self._clean_cell(result_val)
                # Remove common markers like 'Over', 'undef'
                cleaned = re.sub(r'(Over|undef)', '', cleaned, flags=re.IGNORECASE)
                cleaned = cleaned.strip()
                die.add('result', Util.rep_na(cleaned))
            else:
                die.add('result', 'NA')
        
        wafer.add('dies', die)
        
        # Track sbins
        bin_name_s = f"SWBin_{bin_numeric.zfill(3)}"
        bin_obj_s = wafer.find("sbins", {"number": bin_numeric})
        if bin_obj_s is None:
            wafer.add("sbins", Bin({
                'number': bin_numeric,
                'name': bin_name_s,
                'bindesc': bin_name_s,
                'PF': pass_fail,
                'count': 1,
            }))
        else:
            bin_obj_s.count += 1
        
        # Track hbins
        bin_name_h = f"HWBin_{bin_numeric.zfill(3)}"
        bin_obj_h = wafer.find("hbins", {"number": bin_numeric})
        if bin_obj_h is None:
            wafer.add("hbins", Bin({
                'number': bin_numeric,
                'name': bin_name_h,
                'bindesc': bin_name_h,
                'PF': pass_fail,
                'count': 1,
            }))
        else:
            bin_obj_h.count += 1
    
    def _create_tests(self, model: Model, wafer: Wafer, test_names: List[str],
                      lo_limits: List[str], hi_limits: List[str],
                      units: List[str]) -> None:
        """
        Create Test objects from parsed header rows.
        
        Args:
            model: Model to add tests to
            wafer: Wafer to add tests to
            test_names: List of test names
            lo_limits: List of low limit values
            hi_limits: List of high limit values
            units: List of unit strings
        """
        self.logger.INFO(
            f"Creating tests: {len(test_names)} names, {len(lo_limits)} lo_limits, "
            f"{len(hi_limits)} hi_limits, {len(units)} units"
        )
        
        for i, name in enumerate(test_names):
            if not name:
                continue
            lsl = lo_limits[i] if i < len(lo_limits) else ''
            hsl = hi_limits[i] if i < len(hi_limits) else ''
            unit = units[i] if i < len(units) else ''
            
            # Create Test object with dictionary initialization (like Qorvo)
            test = Test({
                'number': i + 1,
                'name': name,
                'units': unit.strip() if unit else '',
                'LPL': lsl,
                'HPL': hsl,
                'LSL': lsl,
                'HSL': hsl,
                'LOL': '',
                'HOL': '',
                'LWL': '',
                'HWL': ''
            })
            
            model.add('tests', test)
            wafer.add('tests', test)



