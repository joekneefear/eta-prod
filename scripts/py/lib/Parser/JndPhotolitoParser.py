from pathlib import Path
from typing import Dict
import logging
import csv
import re
import pandas as pd
from io import StringIO
from lib.Data.Model import Model  # Importing the new Model class
from lib.Data.Metadata import Metadata  # Importing the Metadata class
from lib.Data.Wafer import Wafer  # Importing the Wafer class
from lib.Data.Test import Test  # Importing the Test class
from lib.Data.Die import Die  # Importing the Die class
from lib.Util import Util
from lib.Log import Log


class JndPhotolitoParser:
    def __init__(self):
        # self.logger = logging.getLogger(__name__)
        self.model = Model()  # Initialize model as per JndLehParser structure

    @staticmethod
    def _clean_value(value: str) -> str:
        """Replace N/A with empty string and strip whitespace."""
        return "" if value.strip().upper() == "N/A" else value.strip()
    

    def read_file(self, input_file: str) -> Model:
        """Read and parse photolito data file."""
        # model = self.model
        metadata = Metadata()  # Initialize Metadata
        wafer = Wafer()  # Initialize Wafer
        self.model.header = metadata
        # self.model.wafers = []  # Initialize wafers in the model
        
        # Define regex pattern for the entire line
        header_pattern = re.compile(r'(\d{2}-[A-Z]{3}-\d{4}), (\d{2}:\d{2}:\d{2}), ([^,]+), ([^,]+),*')
        
        with open(input_file, 'r') as file:
            for line in file:
                # Strip whitespace and double quotes from each element in the line
                line = line.strip().replace('"', '')
                # Split the line into columns
                row = line.split(',')
                
                # Debug: Print the row being processed
                # print(f"Processing row: {row}")
                
                if len(row) > 1 and row[1].lower().startswith('wafer'):
                    # print("============================================TEST=================================================")
                    # Parse test information
                    test = wafer.find('tests', {'number': '1'})
                    if test is None:
                        test = Test()
                        test.number = '1'
                        test.name = row[5]
                        wafer.add('tests', test)

                    test = wafer.find('tests', {'number': '2'})
                    if test is None:
                        test = Test()
                        test.number = '2'
                        test.name = row[6]
                        wafer.add('tests', test)

                elif len(row) > 1 and row[1].isdigit() and not header_pattern.match(row[0]):
                    # Parse die and wafer information
                    # wafer
                    wafer.number = row[1]
                    result_dictionary = {'1': row[5], '2': row[6]}
                    die = Die()
                    die.site = row[2]
                    die.x = row[3]
                    die.y = row[4]
                    for test in wafer.tests:
                        result = Util.rep_na(result_dictionary.get(test.number))
                        die.add('result', result)
                    wafer.add('dies', die)

                elif header_pattern.match(line):
                    # print("Matched row:+++++++++++++++++++++++++++++", row)
                    # Parse header information
                    match = header_pattern.match(line)
                    date = f"{match.group(1)} {match.group(2)}"
                    date = Util.convert_date_format_to_yyyymmdd_hms(date)
                    wafer.start_time = date
                    wafer.end_time = date
                    metadata.START_TIME = date
                    metadata.END_TIME = date
                    
                    if len(row) > 2 and "/" in row[2]:
                        product, program = row[2].split("/")
                        step = f"<{program}>:OVERLAY"
                        
                        metadata.PROGRAM = program
                        metadata.PRODUCT = product.strip()
                        metadata.MEASURING_EQUIPMENT = str(row[3]).strip()
                        metadata.EQUIP1_ID = metadata.MEASURING_EQUIPMENT
                        metadata.STEP = step.strip()
                        self.model.metadata = metadata  # Assign metadata to the model
                    else:
                        Log.WARN(f"Unexpected format in row[2]: {row[2]}")
                
            self.model.add("wafers", wafer)
        
        return self.model  # Return the model
