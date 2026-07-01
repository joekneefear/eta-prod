

"""
SYNOPSIS

DESCRIPTION
    Rel class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Sept-03 - jgarcia - initial

LICENSE
    (C) onsemi 2024 All rights reserved.
"""

from lib.Data.Base import Base
# from lib.Log import Log
# from lib.Util import Util

class Rel(Base):
    ATTRS = [
        "qpnumber", "devchar", "lotchar", "strname", "strduration",
        "atetemp", "datalogtype"
    ]

    def __init__(self, args=None):
        super().__init__(args or {})  # Ensure args is a dictionary

        # Initialize predefined attributes with defaults
        for attr in self.ATTRS:
            setattr(self, attr, args.get(attr, None))  # Use None if missing

    def array(self):
        """Defines attributes that should be treated as lists."""
        return ["reliability"]

    def list(self):
        """Defines attributes that should be included in the string representation."""
        return self.ATTRS
