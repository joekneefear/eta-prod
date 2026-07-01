"""
SYNOPSIS

DESCRIPTION

Sxml Enricher class

AUTHOR

junifferallan.garcia@onsemi.com

CHANGES
2024-06-18 - jgarcia - initial
2024-06-18 - jgarcia - added update_orientation_mark_location, enrich_defect_columns, enrich_remove_defect_list_XY_not_in_sample_test_plan, apply_enrichments
                        check_defect_list functions
2024-Aug-28 - jgarcia - added remove_tiffFilename_and_DefectList_lines function


LICENSE

(C) onsemi 2024 All rights reserved.
"""

from lib.Util import Util
from lib.Log import Log
import re

class Klarf12Enricher:
    def __init__(self, model, enrichments, device_data=None):
        # Ensure device_data is a list of dictionaries or None
        if device_data is None or (isinstance(device_data, list) and all(isinstance(item, str) for item in device_data)):
            self.device_data = [{'id': item} for item in device_data] if device_data else []
        else:
            self.device_data = device_data

        self.model = model
        self.device_ids_pattern = re.compile('|'.join(re.escape(device['id']) + '.*' for device in self.device_data))
        self.device_id = None
        self.defect_record_spec_columns = 0
        self.required_enrichments = enrichments

    def count_columns(self, line):
        if line.startswith('DefectRecordSpec'):
            columns = line.rstrip(';\n').split()[2:]  # Skip 'DefectRecordSpec' and the number
            return len(columns)
        return 0

    def update_orientation_mark_location(self): 
        klarf_data = self.model.misc['klarf_1_2']  
        updated_lines = []
        for line in klarf_data:
            try:
                if not line.strip():
                    continue  # Skip empty lines
                key, *value = line.rstrip(';\n').split(maxsplit=1)
                value = ' '.join(value).replace('"', '') if value else None  # remove double quotes

                if key == 'DeviceID':
                    self.device_id = value
                    Log.INFO(f'KEY={key}||VALUE={value}')
                elif key == 'OrientationMarkLocation' and self.device_id and isinstance(self.device_id, str) and self.device_ids_pattern.match(self.device_id):
                    device_info = next((device for device in self.device_data if re.match(re.escape(device['id']) + '.*', self.device_id)), None)
                    if device_info and device_info.get('orientation_mark_location') == 'RIGHT':
                        Log.INFO(f'DeviceID={self.device_id} requires "RIGHT" update for OrientationMarkLocation')
                        line = "OrientationMarkLocation RIGHT;\n"
                        # fname_suffix = self.model.misc.get('flag', '')
                        # if 'eoml' not in fname_suffix:  # Check if 'eoml' is already in flag
                        #     self.model.misc['flag'] = f'{fname_suffix}_eoml' if fname_suffix else 'eoml'
                        if 'eoml' not in self.model.misc.get('flag', ''):
                            self.model.misc['flag'] += '_eoml'  # Append 'eoml' if not present
                        
                updated_lines.append(line)
            except Exception as e:
                Log.ERROR(f'Error processing line: {line}. Error: {e}')
        self.model.misc['klarf_1_2'] = updated_lines
        # return self.model  # Return the updated instance

    def enrich_defect_columns(self):  
        klarf_data = self.model.misc['klarf_1_2']  
        inside_defect_list = False
        updated_lines = []
        for line in klarf_data:
            try:
                if 'DefectList' in line:
                    inside_defect_list = True
                elif 'DefectRecordSpec' in line:
                    line_copy = line.strip().rstrip(';\n')
                    columns = line_copy.split()
                    defect_id_index = columns.index('DEFECTID')
                    self.defect_record_spec_columns = len(columns[defect_id_index:])
                elif inside_defect_list and re.match(r'^[ \t\d]', line):
                    leading_spaces = re.match(r'^\s*', line).group()
                    line_copy = line.strip().rstrip(';\n')
                    columns = line_copy.strip().split()
                    if len(columns) - self.defect_record_spec_columns == 2:
                        Log.INFO(f"Removing columns from defect list: {line}")
                        columns.pop(-3)  # Remove third to the last
                        columns.pop(-1)  # Remove last
                        line = f'{leading_spaces}{" ".join(columns)};\n'
                        if 'edlcol' not in self.model.misc.get('flag', ''):
                            self.model.misc['flag'] += '_edlcol'  # Append 'edl_col' if not present
                    elif len(columns) > self.defect_record_spec_columns and len(columns) - self.defect_record_spec_columns != 2:
                        Log.ERROR(f'actual defect list column count={len(columns)} is greater than defect list record specified column=>{self.defect_record_spec_columns} and the difference is not equal to 2, for this type no mapping was provided and cannot decide how to handle, thus moving to NotProcessed')
                        Util.dp_exit(1, "actual defect list column is greater than defect list record specified and the difference is not equal to 2, moved to NotProcessed")
                updated_lines.append(line)
            except Exception as e:
                Log.ERROR(f'Error processing line in enrich_defect_columns function: {line}. Error: {e}')
        self.model.misc['klarf_1_2'] = updated_lines
        # return self.model

    def enrich_remove_defect_list_XY_not_in_sample_test_plan(self): 
        inside_defect_list = False
        sample_test_plan_count = self.model.misc['sample_test_plan_count']
        lines_to_remove = []  # Collect lines to remove

        for index, line in enumerate(self.model.misc['klarf_1_2']):
            try:
                if 'DefectList' in line:
                    inside_defect_list = True
                elif 'Summary' in line:
                    inside_defect_list = False
                    break
                elif inside_defect_list and re.match(r'^[ \t\d]', line):
                    line_copy = line.rstrip(';\n')
                    columns = line_copy.strip().split()
                    if len(columns) > 7 and all(Util.is_numeric(col) for col in columns):
                        joined_value = f"{columns[3]} {columns[4]}"
                        matching_keys = [key for key in self.model.misc['sample_test_plan_coordinates'][sample_test_plan_count] if joined_value in key]
                        if not matching_keys and joined_value:
                            Log.INFO(f"DefectList's XY coordinate = {joined_value} is not in sample test plan. Removing defect list line: {line}")
                            if index > 1 and re.match(r'DefectList', self.model.misc['klarf_1_2'][index - 1]) and re.match(r'TiffFileName', self.model.misc['klarf_1_2'][index - 2]):
                                lines_to_remove.extend([index - 2, index - 1, index])
                            else:
                                lines_to_remove.append(index)
                            if 'edl' not in self.model.misc.get('flag', ''):
                                self.model.misc['flag'] += '_edl'
            except Exception as e:
                Log.ERROR(f'Error processing line in enrich_remove_defect_list_XY_not_in_sample_test_plan function : {line}. Error: {e}')

        # Remove lines in reverse order to avoid index shifting issues
        for index in sorted(lines_to_remove, reverse=True):
            del self.model.misc['klarf_1_2'][index]

        # return self.model  # Return the updated klarf_1_2 data
    
    def apply_enrichments(self): 
        # mdl = self.model
        try:
            if 'update_orientation_mark_location' in self.required_enrichments:
                Log.INFO(f"Applying enrichment function=>update_orientation_mark_location")
                self.update_orientation_mark_location()  

            if 'enrich_remove_defect_list_XY_not_in_sample_test_plan' in self.required_enrichments:
                Log.INFO(f"Applying enrichment function=>enrich_remove_defect_list_XY_not_in_sample_test_plan")
                self.enrich_remove_defect_list_XY_not_in_sample_test_plan()  
                
            if 'remove_tiffFilename_and_DefectList_lines' in self.required_enrichments:
                Log.INFO(f"Applying enrichment function=>remove_tiffFilename_and_DefectList_lines")
                self.remove_tiffFilename_and_DefectList_lines()

            if 'enrich_defect_columns' in self.required_enrichments:
                Log.INFO(f"Applying enrichment function=>enrich_defect_columns")
                self.enrich_defect_columns()  
           
        except Exception as e:
            Log.ERROR(f'Error applying enrichments. Error: {e}')
            Util.dp_exit(1, "Error in enrichment {e}")

        return self.model  # Return the updated model
    
    def check_defect_list(self, model):
        klarf_data = model.misc['klarf_1_2']
        inside_defect_list = False
        found_defect_list = False
        valid_defect_lines = []

        for line in klarf_data:
            if 'DefectList' in line:
                inside_defect_list = True
                found_defect_list = True  # Mark that we found 'DefectList'
            elif inside_defect_list and re.match(r'^\s*\d', line):  # Check for line starting with space and digits
                Log.INFO(f"Found valid defect line: {line.strip()}")
                valid_defect_lines.append(line.strip())
            elif inside_defect_list and 'Summary' in line:
                inside_defect_list = False  # Exit defect list when encountering 'Summary'
           
        # Use valid_defect_lines for decision making
        if found_defect_list:
            if not valid_defect_lines:
                Log.ERROR("Only 'DefectList' found without valid defect lines below it.")
                Util.dp_exit(1, "Only 'DefectList' found without valid defect lines below it.")
                # return False
            Log.INFO(f"DefectList found with {len(valid_defect_lines)} valid defect lines.")
            # return True
        else:
            Log.INFO("DefectList was not found")
            Util.dp_exit(1, "DefectList was not found")
            # return False

    def remove_tiffFilename_and_DefectList_lines(self):
        cleaned_lines = []
        skip_next_line = False
        defect_list_needed = False
        defect_list_added = False  # Track if DefectList has been added

        for line in self.model.misc['klarf_1_2']:
            stripped_line = line.strip()
            if not stripped_line:  # Skip empty lines
                continue
            if stripped_line.startswith("TiffFileName"):
                skip_next_line = True
                if 'rmTifExtraDef' not in self.model.misc.get('flag', ''):
                    self.model.misc['flag'] += '_rmTifExtraDef'  # Append 'rmTifExtraDef' if not present
                continue
            if skip_next_line:
                if stripped_line.startswith("DefectList"):
                    skip_next_line = False
                    continue
            if cleaned_lines and cleaned_lines[-1].startswith("DefectRecordSpec"):
                defect_list_needed = True
            if defect_list_needed and not stripped_line.startswith("DefectList") and not defect_list_added:
                cleaned_lines.append("DefectList\n")
                defect_list_added = True  # Mark that DefectList has been added
                defect_list_needed = False  # Reset after adding
            elif stripped_line.startswith("DefectList"):
                # if 'rmTifExtraDef' not in self.model.misc.get('flag', ''):
                #     self.model.misc['flag'] += '_rmTifExtraDef'  # Append 'rmTifExtraDef' if not present
                continue  # Skip additional DefectList lines
            skip_next_line = False
            cleaned_lines.append(line)

        self.model.misc['klarf_1_2'] = cleaned_lines
       








