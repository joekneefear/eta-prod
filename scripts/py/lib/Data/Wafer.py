"""
SYNOPSIS

DESCRIPTION
    Wafer class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Sept-03 - jgarcia - initial
    2025-Feb-18  - jgarcia - updated to adhere Base class settings and intention
    2025-Mar-11 - jgarcia - refactored to be similarly defined to Perl version

LICENSE
    (C) onsemi 2024 All rights reserved.
"""

from lib.Data.Base import Base

class Wafer(Base):
    ATTRS = ["key", "number", "START_TIME", "END_TIME", "name"]  # Explicit attributes

    def __init__(self, args=None):
        """Initialize Wafer instance with predefined attributes and dynamic support."""
        args = args or {}  # Ensure args is a dictionary
        super().__init__(args)

        # Initialize predefined attributes with defaults
        for attr in self.ATTRS:
            setattr(self, attr, args.get(attr, None))  # Use None if missing
        
        # Initialize list attributes using a helper function
        self.initialize_list_attributes()
        
    def initialize_list_attributes(self):
        """Helper function to initialize list attributes."""
        self._arrays["tests"] = []
        self._arrays["bins"] = []
        self._arrays["dies"] = []
        self._arrays["hbins"] = []
        self._arrays["sbins"] = []
        self._arrays["rels"] = []
        self._arrays["custindexes"] = []
    
    @property
    def tests(self):
        return self._arrays["tests"]
    
    @property
    def bins(self):
        return self._arrays["bins"]
    
    @property
    def sbins(self):
        return self._arrays["sbins"]
    
    @property
    def hbins(self):
        return self._arrays["hbins"]
    
    @property
    def dies(self):
        return self._arrays["dies"]

    def array(self):
        """Defines attributes that should be treated as lists."""
        return ["tests", "bins", "dies", "hbins", "sbins", "rels", "custindexes"]

    def stats(self):
        """Calculate wafer statistics."""
        min_x, min_y, max_x, max_y = 99999, 99999, -99999, -99999
        device_count = 0

        for die in self._arrays.get("dies", []):  # Access dies array
            if getattr(die, "inked", False):  # Skip inked dies
                continue
            device_count += 1
            min_x = min(min_x, getattr(die, "x", min_x))
            min_y = min(min_y, getattr(die, "y", min_y))
            max_x = max(max_x, getattr(die, "x", max_x))
            max_y = max(max_y, getattr(die, "y", max_y))

        columns = max_x - min_x + 1
        rows = max_y - min_y + 1

        return {
            "minX": min_x,
            "minY": min_y,
            "maxX": max_x,
            "maxY": max_y,
            "deviceCount": device_count,
            "columns": columns,
            "rows": rows,
        }