"""
SYNOPSIS

DESCRIPTION

KLA reference file (Klarf file) parser

AUTHOR

    junifferallan.garcia@onsemi.com

CHANGES
    2023-Oct-16 - jgarcia - initial
    2023-Oct-23 - jgarcia - updated parse_klarf_1_2_and_filter_defect_list method to hanlde both .gz or uncompressed.
    2023-Nov-03 - jgarcia - enchance checking for defectlist
    2023-Dec-14 - jgaria  - still send klarf files without defect list regardless if it is because of stripping process or not.
                            Tom wanted to load these type of klarf files which will be handled by the defect loader.
    2023-Dec-20 - jgarcia - updated to parse the klarf file and put the parsed value to model.misc['klarf_1_2'] list consisting of each lines.
                            Also parse the sample test plan and put in model.misc['sample_test_plan_coordinates'].

LICENSE

    (C) onsemi 2023 All rights reserved.

"""

import pandas as pd
import gzip
import re
from lib.Util import Util
from lib.Log import Log
from lib.Data.Model import Model


class Klarf12:
    def __init__(self):
        self.klarf_version = None
        self.sample_size = None
        self.die_pitch = None
        self.die_origin = None
        self.center_location = None
        self.sample_test_plan_coordinates = {}
        self.defect_list = pd.DataFrame()
        
    def parse_klarf_1_2(self, klarf_file, name=None):
        model = Model()
        model.misc = {'klarf_1_2': [], 'sample_test_plan_coordinates': {}, 'sample_test_plan_count': None}

        # Determine if the file is compressed (.gz) or uncompressed
        if klarf_file.endswith('.gz'):
            with gzip.open(klarf_file, 'rt') as file:
                lines = [i for i in file.readlines()]
        else:
            with open(klarf_file, 'r') as file:
                lines = [i for i in file.readlines()]

        inside_sample_test_plan = False
        sample_test_plan_value = None

        # Append each line to model.misc['klarf_1_2'] and parse Sample Test Plan
        for line in lines:
            model.misc['klarf_1_2'].append(line)  # Keep the original newline character

            if 'SampleTestPlan' in line:
                inside_sample_test_plan = True
                sample_test_plan_value = int(line.split()[-1])
                model.misc['sample_test_plan_count'] = sample_test_plan_value
                # Check if the key exists, if not, create it
                if sample_test_plan_value not in model.misc['sample_test_plan_coordinates']:
                    model.misc['sample_test_plan_coordinates'][sample_test_plan_value] = []
                # Log.INFO(f"Sample Test Plan dict KEY={sample_test_plan_value}")
            elif inside_sample_test_plan:
                if line.startswith(' ') and not line.endswith(';'):
                    sample_test_plan_line_value = line.strip()
                    model.misc['sample_test_plan_coordinates'][sample_test_plan_value].append(sample_test_plan_line_value)
                elif line.startswith(' ') and line.endswith(';'):
                    # Assign to dictionary and end of SampleTestPlan when encountering a line ending with semicolon
                    sample_test_plan_line_value = line.strip().lstrip(';')
                    model.misc['sample_test_plan_coordinates'][sample_test_plan_value].append(sample_test_plan_line_value)
                    inside_sample_test_plan = False
                # Switch off inside_sample_test_plan if encountering specific lines
                elif 'AreaPerTest' in line or 'InspectionTest' in line:
                    inside_sample_test_plan = False  # End of sample test plan

        return model