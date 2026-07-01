

"""
SYNOPSIS

DESCRIPTION
    Model class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Sept-03 - jgarcia - initial

LICENSE
    (C) onsemi 2024 All rights reserved.
"""

from lib.Data.Base import Base
from lib.Log import Log
from lib.Util import Util


class CustIndexes(Base):
    def __init__(self, args=None):
        super().__init__(args)
        self.index1 = None
        self.index2 = None
        self.index3 = None
        self.index4 = None
        self.index5 = None

    def array(self):
        return ['custindexes']