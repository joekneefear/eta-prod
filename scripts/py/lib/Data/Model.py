"""
SYNOPSIS

DESCRIPTION
    Model class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2023-Oct-12 - jgarcia - initial
    2025-Mar-11 - jgarcia - refactored to be similarly defined to Perl version
    2025-Mar-11 - jgarcia - added function to build a limit

LICENSE
    (C) onsemi 2023 All rights reserved.
"""

from lib.Data.Base import Base  
from lib.Log import Log
from lib.Data.Limit import Limit 
from lib.Data.Wmap import Wmap 
# from lib.Util import Util

class Model(Base):
    ATTRS = ["header", "wmap", "limit", "misc", "dataSource", "forSBflag", "programOrg", "cfg_tester_type", "defect", "raw_headers", "test_mapping"]

    def __init__(self, args=None):
        args = args or {}  # Ensure args is a dictionary
        super().__init__(args)
        for attr in self.ATTRS:
            setattr(self, attr, args.get(attr, None))  # Initialize attributes 
            
        self.initialize_list_attributes()

    def initialize_list_attributes(self):
        self._arrays["wafers"] = []
        self._arrays["tests"] = []
        self._arrays["sbins"] = []
        self._arrays["hbins"] = []
        self._arrays["dies"] = []
        self._arrays["rels"] = []
        self._arrays["custindexes"] = []

    def array(self):
        return ["wafers", "tests", "sbins", "hbins", "dies", "rels", "custindexes"]
    
    @property
    def tests(self):
        return self._arrays["tests"]
    
    @property
    def wafers(self):
        return self._arrays["wafers"]
    
    @property
    def sbins(self):
        return self._arrays["sbins"]
    
    @property
    def hbins(self):
        return self._arrays["hbins"]
    
    @property
    def dies(self):
        return self._arrays["dies"]
    

    def updateProgram(self, applyPGM):
        """Update the program name based on various conditions."""
        if not self.header or not hasattr(self.header, "PROGRAM"):
            Util.dp_exit(1, "PROGRAM_CLASS not defined in header.")
        
        program = self.header.PROGRAM
        progrev = self.header.REVISION
        self.programOrg = program

        if hasattr(self.header, "PROGRAM_CLASS") and self.header.PROGRAM_CLASS == 5:
            if "Product" in applyPGM:
                program += f"::{self.header.PRODUCT}"
            elif "Process" in applyPGM:
                process = self.header.PROCESS.replace(" ", "_") if self.header.PROCESS else "UNKNOWN"
                program += f"::{process}"

        pgm_ext = ""
        cfg_id = ""

        if self.wmap:
            cfg_id = self.wmap.cfg_id
            if self.wmap.isEmpty() or self.wmap.confirmed == 0:
                pgm_ext = "-NC"

        if applyPGM == "MAP_PGM":
            program += f"::{cfg_id}::{self.dataSource}{pgm_ext}"
        elif applyPGM == "MAP_PGM_REV":
            if progrev and progrev != "NA":
                Log.INFO(f"{applyPGM} option is used. Adding program revision to program name.")
                program += f"::{cfg_id}::{progrev}::{self.dataSource}{pgm_ext}"
            else:
                program += f"::{cfg_id}::{self.dataSource}{pgm_ext}"
        else:
            program += f"::{self.dataSource}"

        self.header.PROGRAM = program.replace("'", "")
        return program

    def updateWMap(self):
        """Update wafer map data."""
        Log.INFO("Get WMAP from REFDB")

        if self.header and self.header.CFG_TESTER_TYPE not in ["N/A", "NA"]:
            wmap = Wmap.new_from_refdb(self.header.PRODUCT, self.header.CFG_TESTER_TYPE, self.header.EQUIP6_ID)

            if self.dataSource in ["SEPM", "SZ", "AWW", "NAM", "ASC", "SINF", "FET"] and wmap.isEmpty():
                wmap = self.wmap
                if wmap:
                    wmap.product = self.header.PRODUCT
                    wmap.tester_type = self.header.CFG_TESTER_TYPE
                    wmap.location = self.header.EQUIP6_ID
                    wmap.register_refdb()
                    wmap.confirmed_flag()

            elif wmap.isEmpty():
                Log.INFO(f"WMAP NOT found PRODUCT = {self.header.PRODUCT}")
            else:
                Log.INFO(f"WMAP found PRODUCT = {self.header.PRODUCT}, CFG_TESTER_TYPE = {self.header.CFG_TESTER_TYPE}, LOCATION = {self.header.EQUIP6_ID}")
                self.wmap = wmap

        else:
            Log.INFO("Using WMAP from file")

        return self.wmap

    # def isLimitNew(self):
    #     """Check if the program and revision limits are new in refdb."""
    #     if getRefdb().isNewLimit({"PROGRAM": self.header.PROGRAM, "REVISION": self.header.REVISION}):
    #         Log.INFO(f"Limit: PROGRAM={self.header.PROGRAM}, REVISION={self.header.REVISION} is New")
    #         return True
    #     else:
    #         Log.INFO(f"Limit: PROGRAM={self.header.PROGRAM}, REVISION={self.header.REVISION} is Not New")
    #         return False

    def build_limit(self):
        if self.limit:
            Log.INFO("Limit already initialized.")
            return self.limit

        limit = Limit()
        limit.copy_header(self.header)

        if self.tests:
            # Log.INFO("Adding tests from model")
            for test in self.tests:
                # Log.INFO(f"Adding test: {test.number} - {test.name}")
                limit.add("tests", test)
        elif self.wafers and self.wafers[0].tests:
            # Log.INFO("Adding tests from wafer")
            for test in self.wafers[0].tests:
                # Log.INFO(f"Adding test: {test.number} - {test.name} - {test.LSL} - {test.HSL} - {test.units}")
                
                limit.add("tests", test)
                # mytests = limit.tests
                # Log.INFO(f">>>>{mytests}")
                # ctr = ctr + 1
        else:
            Log.INFO("No tests found in model or wafer.")

        # Log.INFO(f"built_limit=>{limit.tests}")
        self.limit = limit
        return limit