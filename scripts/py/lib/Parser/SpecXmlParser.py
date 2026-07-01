import sys
import gzip
from io import BytesIO
from lib.Util import Util
from lib.Log import Log
import re

class SpecXmlParser:

    def __init__(self, xml_data):
        # Check if the data is compressed
        if xml_data.endswith('.gz'):
            # Data is compressed, decompress it
            with gzip.open(xml_data, 'rb') as f:
                self.data = f.read().decode('ascii')  # Read as ASCII
        else:
            # Data is not compressed
            with open(xml_data, 'rb') as f:
                self.data = f.read().decode('ascii')  # Read as ASCII

        # No XML parsing, just store the data
        # self.root = ET.fromstring(xml_data)  # Removed XML parsing

        self.filename = None
        self.waferids = None
    
    def get_lot_value(self):
        """
        Extracts the 'Lot' value from the stored data.
        
        :return: Lot value as a string or None if not found
        """
        try:
            # Use self.data instead of reading from a file
            content = self.data
            
            # Use regex to find the Id value from the <Lot> tag
            match = re.search(r'Lot[^>]*Id="([^"]*)"', content)  # Updated regex to capture Id
            if match:
                return match.group(1).strip()
            else:
                Log.INFO("Lot Id value not found.")
                return None
        except Exception as e:
            Log.ERROR(f"An error occurred: {e}")
            return None