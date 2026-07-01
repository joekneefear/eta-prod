"""
SYNOPSIS

DESCRIPTION
    Base class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2023-Oct-12 - jgarcia - initial
    2025-Mar-11 - jgarcia - refactored to be similarly defined to Perl version and close alignment with Perl Base.pm, used of defaultdict. 

LICENSE
    (C) onsemi 2023 All rights reserved.
    
"""

from collections import defaultdict
from lib.Log import Log
# from lib.Util import Util

class Base:
    def __init__(self, args=None):
        if args is None:
            args = {}
        
        # Initialize attributes from args
        for key, value in args.items():
            setattr(self, key, value)
        
        # Initialize arrays defined in the subclass
        self._arrays = defaultdict(list)
        for attr in self.array():
            self._arrays[attr] = []

    def array(self):
        """ Should be overridden in subclasses. """
        return []

    def list(self):
        """ Should be overridden in subclasses. """
        return []
    
    def set(self, key, *values):
        """ Set an attribute with the given key and values. """
        setattr(self, key, values[0] if values else None)

    def _check_array(self, name):
        from lib.Util import Util
        """ Check if an attribute is a valid array reference. """
        if name not in self.array():
            Util.dp_exit(1, f"{name} is not an array reference")
            raise ValueError(f"{name} is not an array reference")

    def add(self, name, data):
        if name not in self._arrays:
            raise ValueError(f"{name} is not a valid array attribute")
        # Log.INFO(f"Adding {data} to {name}")
        self._arrays[name].append(data)

    def find(self, name, search_dict):
        """ Find an item in the named array based on key-value search criteria. """
        self._check_array(name)
        for item in self._arrays[name]:
            if all(getattr(item, k, None) == v for k, v in search_dict.items()):
                return item
        return None

    def toString(self):
        from lib.Util import Util
        """ Generate a string representation of the object. """
        result = []
        for attr in self.list():
            value = Util.rep_na(getattr(self, attr, 'NA'))
            Log.DEBUG(f"{attr.upper()} = {value}")
            result.append(f"{attr.upper()}={value}")
        return "\n".join(result)

    def isEmpty(self):
        """ Check if the object has any meaningful attributes. """
        return not bool(self.__dict__)
