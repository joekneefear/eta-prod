"""
SYNOPSIS

DESCRIPTION
    SXML formatter

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2023-Sep-06 - jgarcia - initial


LICENSE
    (C) onsemi 2023 All rights reserved.
"""

from lib.Log import Log
from lib.Util import Util
from os.path import basename
import re
import xml.etree.ElementTree as ET

class SXML():
    def __init__(self, writer=None, sxml=None):
        self._writer = writer
        self._sxml = sxml
        # self._logger = Log.get_logger()

    @property
    def writer(self):
        return self._writer

    @writer.setter
    def writer(self, value):
        self._writer = value

    @property
    def sxml(self):
        return self._sxml

    @sxml.setter
    def sxml(self, value):
        self._sxml = value
    
    # @property
    # def logger(self):
    #     return self._logger

    # @logger.setter
    # def logger(self, value):
    #     self._logger = value
        

    def write_xml_to_file(self): #xml_data, attribute_dict, output_filename):
        import os
        wr = self.writer
        sxml_data = self.sxml

        try:
            wr.open()
            wr.put(sxml_data)
            wr.close()
                
        except Exception as e:
            Log.ERROR(f"Error writing SXML to file: {wr.outfile()}, Error: {e}")
            if hasattr(wr, 'FH'):
                try:
                    wr.cancel()
                except Exception:
                    pass
            if hasattr(wr, 'tempfile') and os.path.exists(wr.tempfile):
                os.remove(wr.tempfile)
    
    def write_list_of_line_string_to_file(self):
        wr = self.writer
        try:
            wr.open()
            for item in self.sxml:
                wr.put(item + "\n")
            wr.put("\n")
            wr.close()
        except Exception as e:
            Log.ERROR(f"An error occurred:{e}")
            Util.dp_exit(1, "An error occurred")
            raise

