
"""
SYNOPSIS

DESCRIPTION
    Die class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Sep-03 - jgarcia - initial
    2025-Mar-11 - jgarcia - refactored to be similarly defined to Perl version

LICENSE
    (C) onsemi 2024 All rights reserved.
"""

from lib.Data.Base import Base
# from lib.Log import Log
# from lib.Util import Util

class Die(Base):
    ATTRS = [
        "x", "y", "site", "partid", "touchdown_num", "ecid",
        "soft_bin", "hard_bin", "bindesc", "indexes", "inked", "notest",
        "hash", "unprobed", "org_x", "org_y", "ecid",
        "runtime", "readtime"
    ]

    def __init__(self, args=None):
        """Initialize Die instance with predefined attributes and dynamic support."""
        args = args or {}  # Ensure args is a dictionary
        super().__init__(args)
        # super().__init__(args or {})  # Ensure args is a dictionary

        # Initialize predefined attributes with defaults
        for attr in self.ATTRS:
            setattr(self, attr, args.get(attr, None))  # Use None if missing
            
        # Initialize list attributes using a helper function
        self.initialize_list_attributes()

    def initialize_list_attributes(self):
        """Helper function to initialize list attributes."""
        self._arrays["result"] = []
        self._arrays["min"] = []
        self._arrays["max"] = []
        self._arrays["mean"] = []
        self._arrays["sdev"] = []
        self._arrays["sums"] = []
        self._arrays["sqrs"] = []
        self._arrays["cnt"] = []
        self._arrays["level"] = []
        
    @property
    def result(self):
        return self._arrays["result"]
    
    @property
    def min(self):
        return self._arrays["min"]
    
    @property
    def max(self):
        return self._arrays["max"]

    def array(self):
        """Defines attributes that should be treated as lists."""
        return ["result", "min", "max", "mean", "sdev", "sums", "sqrs", "cnt", "level"]
    
    def list(self):
        """Defines attributes that should be included in the string representation."""
        return self.ATTRS