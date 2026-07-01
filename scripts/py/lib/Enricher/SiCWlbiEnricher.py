"""
SYNOPSIS
    SiC WLBI Enricher (Site-Aware)

DESCRIPTION
    Class to enrich WLBI (Winbond/SiC) CSV files by appending probe/load,
    facility and source-lot information. Designed to be tolerant of
    missing RefDB data and driven by constructor parameters.

AUTHOR
    jgarcia

CHANGES
    2026-Mar-19 - add module header and normalize .S handling
"""

import re
import pandas as pd
import csv
import sys
import os
from lib.Log import Log
from lib.Util import Util
from lib.Data.Model import Model

class SiCWlbiEnricher:
    
    def __init__(self, lotid, api_data, site, fill_with):
        self.lotid = lotid
        self.refdb_data = api_data
        self.site = site
        self.fill_with = fill_with
        self.sets_of_columns = None
        
    def fill_empty_with_na(self, df):
        df = df.replace(r'^\s*$', 'NA', regex=True)
        df = df.fillna('NA')
        return df
    
    def append_str_src_lot(self, current_set, strSrcLot):
        """Appends the strSrcLot row to the current set of data."""
        # Always append the source lot value; convert None/null to the configured fill value
        value = strSrcLot if strSrcLot is not None else self.fill_with
        new_row = ['strSrcLot', str(value)]
        current_set.append(new_row)
        Log.INFO(f'Appended strSrcLot: {value}')
    
    def append_probe_and_load_values(self, current_set, strWaferID_line):
        """Append probe card and load board values to the current set."""
        parts = strWaferID_line.split('/')
        if len(parts) > 1:
            probe_card_value = parts[0].strip()
            load_board_value = parts[1].strip()
        else:
            probe_card_value = self.fill_with
            load_board_value = self.fill_with
        current_set.append(['strProbeCard', probe_card_value])
        current_set.append(['strLoadBoard', load_board_value])
        Log.INFO(f'Appended strProbeCard: {probe_card_value}')
        Log.INFO(f'Appended strLoadBoard: {load_board_value}')

    def read_wblbi_data_and_enrich_first_set(self, csv_file_path):
        try:
            ref = self.refdb_data or {}
            strSrcLot = ref.get('sourceLot') or self.fill_with
            strFacility = ref.get('fab') or 'KRI:BUCHEON PROBE (BSF)'
            # lotid = self.refdb_data.get('lot', self.fill_with)
            # Normalize source lot: prefer API sourceLot, else fall back to provided lotid.
            # If neither is present, do NOT exit; log a warning and use the configured fill value
            # (typically 'NA') so the run can still be recorded to pp_log.
            if strSrcLot and strSrcLot != 'NA':
                strSrcLot = re.sub(r'\.S$', '', str(strSrcLot), flags=re.IGNORECASE) + '.S'
            elif self.lotid and self.lotid != 'NA':
                strSrcLot = re.sub(r'\.S$', '', str(self.lotid), flags=re.IGNORECASE) + '.S'
            else:
                # No lot ID available here; parser/driver should handle fatal behavior.
                # Log a warning and continue using the configured fill value so
                # the enricher remains non-fatal and downstream callers control exit.
                Log.WARN('No lotid found in refdb_data or constructor; using fill value')
                strSrcLot = self.fill_with

            data = []
            strWaferID_line = ""
            first_set_completed = False

            with open(csv_file_path, 'r') as file:
                reader = csv.reader(file)
                current_set = []

                for row in reader:
                    if len(row) == 0:
                        if current_set:
                            if not first_set_completed:
                                self.append_probe_and_load_values(current_set, strWaferID_line)
                                current_set.append(['strFacility', str(strFacility)])
                                Log.INFO(f'Appended strFacility: {strFacility}')
                                first_set_completed = True
                            data.append(current_set)
                            current_set = []
                    else:
                        current_set.append(row)
                        if row[0].startswith('strLotName'):
                            self.append_str_src_lot(current_set, strSrcLot)
                        if row[0].startswith('strWaferID'):
                            strWaferID_line = row[1]
                            Log.INFO(f'strWAFERID_LINE={strWaferID_line}')

                if current_set:  # Handle the last set if not empty
                    if not first_set_completed:
                        self.append_probe_and_load_values(current_set, strWaferID_line)
                        current_set.append(['strFacility', str(strFacility)])
                        Log.INFO(f'Appended strFacility: {strFacility}')
                    data.append(current_set)

            return data
        except FileNotFoundError:
            Log.ERROR('File not found: ' + csv_file_path)
            Util.dp_exit(1, f'File not found {csv_file_path}')
        except Exception as e:
            Log.ERROR(f'Exception occurred: {e}')
            Util.dp_exit(1, f'Exception occurred: {e}')
    
    def enrich_wlbi_srcLot_probe_card_load_board_fill_na(self, wlbi_file):
        model = Model()
        model.misc = [] # Initialize as an empty list
        try:
            # base_file = os.path.basename(wlbi_file)
            # fname, fext = os.path.splitext(base_file)
            # output_file = os.path.join(outbox, f"{fname}")
            sets_of_columns = self.read_wblbi_data_and_enrich_first_set(wlbi_file) if self.refdb_data else self.fill_with
            # Process each set of columns
            for idx, set_of_columns in enumerate(sets_of_columns):
                if set_of_columns:  # Check if set_of_columns is not empty
                    # Convert the list of lists to a pandas DataFrame
                    headers = set_of_columns.pop(0)  # Define 'headers' here
                    max_cols = max(len(row) for row in set_of_columns) if set_of_columns else 0
                    headers += ['DUMP_HEADER'] * (max_cols - len(headers))
                    # If there is no data, add a row of 'NA'
                    if not set_of_columns:
                        set_of_columns = [['NA'] * len(headers)]
                    df = pd.DataFrame(set_of_columns, columns=headers)
                    # Debugging: Print the type of df
                    # print(f"DataFrame {idx} type: {type(df)}")
                    # Fill empty fields with 'NA'
                    df = self.fill_empty_with_na(df)
           
                    model.misc.append(df)
                    # Save the modified DataFrame to a new CSV file
                    # output_file = os.path.splitext(output_file)[0] + f"_added_NA_to_blank_value_{idx}.csv"
                    # df.to_csv(output_file, mode='a', index=False, header=True)
                    # Add a blank row to separate sets of columns
                    # with open(output_file, 'a') as file:
                    #     file.write('\n')
            # Log.INFO(f'Enriched {wlbi_file} file and saved to {output_file} successfully.')
            return model
        except FileNotFoundError:
            Log.ERROR('File not found!')
            Util.dp_exit(1, f'File not found {wlbi_file}')
        except Exception as e:
            Log.ERROR(f'Exception occurred: {e}')
            Util.dp_exit(1, f'Exception occurred: {e}')
