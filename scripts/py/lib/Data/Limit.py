
"""
SYNOPSIS

DESCRIPTION
    Die class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2025-Mar-11 - jgarcia - initial

LICENSE
    (C) onsemi 2024 All rights reserved.
"""

import re
from datetime import datetime
from lib.Data.Base import Base
from lib.Log import Log
# from lib.Util import Util

class Limit(Base):
    ATTRIBUTES = [
        "VERSION", "CREATION_DATE", "PROGRAM_CLASS", "PROGRAM",
        "REVISION", "DATE", "PROCESS", "PRODUCT", "AREA", "LOT", "scriptName",
        "input_file", "limit_file"
    ]

    def __init__(self, args=None):
        super().__init__(args)
        if args is None:
            args = {}
        for attr in self.ATTRIBUTES:
            setattr(self, attr, args.get(attr))
        self.initialize_list_attributes()
        self.CREATION_DATE = datetime.now().strftime("%Y-%m-%d")
        self.testItems = ["number", "name", "units"]

    def initialize_list_attributes(self):
        self._arrays["tests"] = []
        self._arrays["testItems"] = []
        self._arrays["conditionNames"] = []

    @property
    def tests(self):
        return self._arrays["tests"]

    @property
    def conditionNames(self):
        return self._arrays["conditionNames"]

    @property
    def testItems(self):
        return self._arrays["testItems"]

    @testItems.setter
    def testItems(self, value):
        self._arrays["testItems"] = value

    def format_date(self, value):
        if not value:
            return None
        try:
            return datetime.strptime(str(value), "%Y-%m-%d %H:%M:%S").strftime("%Y%m%d")
        except ValueError:
            print(f"Invalid date format: {value}")
            return None

    def set(self, key, *values):
        if re.search(r"DATE$", key) and values:
            values = (self.format_date(values[0]),) + values[1:]
            # values = Util.format_date_to_yyyymmdd(values[0] + " " + values[1:])
        super().set(key, *values)

    def copy_header(self, header):
        """
        Copies header attributes from a Metadata object.

        Args:
            header (Metadata): The Metadata object to copy attributes from.

        Returns:
            bool: True after copying the attributes.
        """
        self.VERSION = getattr(header, "VERSION", 'NA')
        self.CREATION_DATE = getattr(header, "CREATION_DATE", "NA")
        self.PROGRAM_CLASS = getattr(header, "PROGRAM_CLASS", "NA")
        self.PROGRAM = getattr(header, "PROGRAM", "NA")
        self.REVISION = getattr(header, "RECIPE_REVISION", None) or getattr(header, "REVISION", "NA")
        self.PROCESS = getattr(header, "PROCESS", "NA")
        self.PRODUCT = getattr(header, "PRODUCT", "NA")
        self.AREA = getattr(header, "AREA", "NA")
        self.DATE = getattr(header, "START_TIME", "NA")
        self.LOT = getattr(header, "LOT", "NA")
        return True

    @property
    def limit_file(self):
        """
        Property getter for limit_file. Generates the file name if not already set.

        Returns:
            str: The limit file name.
        """
        if self._limit_file is None:
            # Generate the limit file name
            self._limit_file = self.generate_limit_file()
        return self._limit_file

    @limit_file.setter
    def limit_file(self, value):
        """
        Property setter for limit_file.

        Args:
            value (str): The new limit file name.
        """
        self._limit_file = value

    def generate_limit_file(self):
        """
        Generates a limit file name based on object attributes.

        Returns:
            str: The generated limit file name.

        Raises:
            ValueError: If PROGRAM is not defined.
        """
        date = str(self.DATE).replace(":", "").replace(" ", "").replace("/", "") if self.DATE else "NA"
        lot = str(self.LOT)
        lot = re.sub(r"[\n\$\%\^\&\*\{\}\|\!\~\/\`\<\>\:\;\"\,\']", "", lot).strip().replace(" ", "_") if self.LOT else ""
        program = str(self.PROGRAM)
        revision = str(self.REVISION or "NA")

        if not program:
            raise ValueError("Cannot create limit file because PROGRAM is not defined")

        revision = re.sub(r"\W", "", revision).replace(" ", "")
        program = re.sub(r"\W", "", program)

        return f"LIMIT_{program}_{revision}_{lot}_{date}"

    def to_string(self):
        """
        Convert the limit object to a string representation for use in limit files.

        Returns:
            str: String representation of the limit.
        """
        result = []
        
        # Add all defined regular attributes
        for attr in self.ATTRIBUTES:
            value = getattr(self, attr, None)
            if value is not None:
                result.append(f"{attr}={value}")
        
        return "\n".join(result)

