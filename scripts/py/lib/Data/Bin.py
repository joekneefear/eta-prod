
"""
SYNOPSIS

DESCRIPTION
    Model class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Sept-03 - jgarcia - initial
    2025-Mar-11 - jgarcia - refactored to be similarly defined to Perl version

LICENSE
    (C) onsemi 2024 All rights reserved.
"""

from lib.Data.Base import Base
from lib.Log import Log

class Bin(Base):
    ATTRS = ["number", "name", "bindesc","PF", "count"]

    def __init__(self, args=None):
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
        self._arrays["conditions"] = []

    def array(self):
        """Defines attributes that should be treated as lists."""
        return ["conditions"]

    def list(self):
        """Defines attributes that should be included in the string representation."""
        return self.ATTRS
