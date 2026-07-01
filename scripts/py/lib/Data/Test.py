
"""
SYNOPSIS

DESCRIPTION
    Test class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Sept-03 - jgarcia - initial
    2025-Mar-11 - jgarcia - refactored to be similarly defined to Perl version

LICENSE
    (C) onsemi 2024 All rights reserved.
"""

from lib.Data.Base import Base
class Test(Base):
    ATTRS = [
        "name", "number", "units", "critical", "group", "LPL", "HPL", "LSL", "HSL",
        "LOL", "HOL", "LWL", "HWL", "desc", "min", "max", "avg", "std", "sum", "ss"
    ]

    def __init__(self, args=None):
        args = args or {}  # Ensure args is a dictionary
        super().__init__(args)

        # Initialize predefined attributes with defaults
        for attr in self.ATTRS:
            setattr(self, attr, args.get(attr, None))  # Use None if missing

    def array(self):
        """Defines attributes that should be treated as lists."""
        return ["conditions"]

    def list(self):
        """Defines attributes that should be included in the string representation."""
        return self.ATTRS
