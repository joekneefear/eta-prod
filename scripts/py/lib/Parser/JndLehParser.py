"""
SYNOPSIS

DESCRIPTION

JND LEH file parser

AUTHOR

    junifferallan.garcia@onsemi.com

CHANGES
    2024-Jul-16 - jgarcia - initial

LICENSE
    (C) onsemi 2023 All rights reserved.

"""

import pandas as pd
import numpy as np
import os
import re
from lib.Data import Base, Model
from lib.Util import Util

class JndLehParser:

    def create_lot_metadata(self, infile: str):
        model = Model()
        model.misc = {}
        parent_lots = {}
        n_parent_lots = {}
        key = ""

        try:
            df = pd.read_csv(infile)

            # Replace blank values with NaN and then NaN with 'NA'
            df = df.replace(r'^\s*$', np.nan, regex=True)
            df = df.fillna("NA")
            
            for index, row in df.iterrows():
                fab = ""
                source_lot = ""
                parent_lot = ""
                lot_type = ""
                wf_status_25 = ""
                
                if re.match(r"^[0-9A-Z]{7}-[0-9A-Z]{5}-[0-9A-Z]{2}", row.iloc[0]):
                    fab = str(row.iloc[0][:2])
                    source_lot_1 = str(row.iloc[0][4:7]) 
                    source_lot_2 = str(row.iloc[0][8:13]) 
                    source_lot = source_lot_1 + source_lot_2 + ".S"
                    parent_lot = str(row.iloc[0][:13])
                    # LOTTYPE - Account Code derived
                    if re.match(r"^HA", row.iloc[10]):
                        lot_type = "PRD"
                    elif re.match(r"^HE", row.iloc[10]):
                        lot_type = "ENG"
                    else:
                        lot_type = "TRY"
                # elif re.match(r"^JM.*|^SY.*", row.iloc[0]):
                elif re.match(r"^[A-Z].*", row.iloc[0]):
                    fab = "JND:AIZU2 FAB (PTI)"
                    root_value = row.iloc[0].split(".")
                    source_lot = str(root_value[0]) + ".S"
                    parent_lot = str(row.iloc[17])
                    lot_type = str(row.iloc[10])

                # WFSTATUS right trim to 25 wafers
                wf_status_25 = str(row.iloc[20][:25])
                
                row = [str(item) for item in row]
                enriched_row = ','.join(row) + f',{fab},{source_lot},{parent_lot},{lot_type},{wf_status_25}'

                enriched_row_columns = enriched_row.split(',')
                num_columns = len(enriched_row_columns)

                if num_columns == 34 and len(enriched_row_columns) > 6 and re.match(r'^[0-9]{4}/[0-9]{1,2}/[0-9]{2} [0-9]{1,2}:[0-9]{2}$', enriched_row_columns[6]):
                    if len(enriched_row_columns) > 31:
                        key = str(enriched_row_columns[31]).split('.')[0]
                        if n_parent_lots.get(key, 0) > 0:
                            parent_lots[key] += '\n'

                        selected_fields_for_lot_metadata = [enriched_row_columns[i] for i in [0, 1, 2, 3, 4, 5, 6, 9, 10, 11, 13, 14, 15, 17, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33]]

                        lot_metadata = ','.join(selected_fields_for_lot_metadata)
                    
                    if key not in parent_lots:
                        parent_lots[key] = []
                    parent_lots[key].append(lot_metadata)
            model.misc.update(parent_lots)
            return model
        except FileNotFoundError:
            Util.dp_exit(1, f"File '{infile}' not found.")
        except Exception as e:
            Util.dp_exit(1, f"An error occurred: {e}")
            
    def process_enrich_for_leh(self, infile: str):
        model = Model()
        splits = {}  # Store splits in a dictionary
        model.misc = {}
        technology = {}
        flow = {}
        flowno = {}

        try:
            df = pd.read_csv(infile)

            # Replace blank values with NaN and then NaN with 'NA'
            df = df.replace(r'^\s*$', np.nan, regex=True)
            df = df.fillna("NA")

            # Extract the filename without the path
            filename = infile.split('/')[-1]

            for index, row in df.iterrows():
                fab = ""
                source_lot = ""
                parent_lot = ""
                lot_type = ""
                wf_status_25 = ""
                
                # Use iloc for positional indexing
                if re.match(r"^[0-9A-Z]{7}-[0-9A-Z]{5}-[0-9A-Z]{2}", row.iloc[0]):
                    fab = str(row.iloc[0][:2])
                    source_lot_1 = str(row.iloc[0][4:7]) 
                    source_lot_2 = str(row.iloc[0][8:13]) 
                    source_lot = source_lot_1 + source_lot_2 + ".S"
                    parent_lot = str(row.iloc[0][:13])
                    if re.match(r"^HA", row.iloc[10]):
                        lot_type = "PRD"
                    elif re.match(r"^HE", row.iloc[10]):
                        lot_type = "ENG"
                    else:
                        lot_type = "TRY"
                elif re.match(r"^[A-Z].*", row.iloc[0]):
                    fab = "JND:AIZU2 FAB (PTI)"
                    root_value = row.iloc[0].split(".")
                    source_lot = str(root_value[0]) + ".S"
                    parent_lot = str(row.iloc[17])
                    lot_type = str(row.iloc[10])

                wf_status_25 = str(row.iloc[20][:25])
                key = f"{row.iloc[25]}_{row.iloc[23]}_{str(row.iloc[24]).lstrip('.')}"

                # Convert row to a list after using iloc
                row_list = ['"' + str(col) + '"' if pd.notnull(col) else '"NA"' for col in row]
                enriched_row = ','.join(row_list) + f',"{fab}","{source_lot}","{parent_lot}","{lot_type}","{wf_status_25}"'
                num_columns = len(enriched_row.split(','))
                final_row = f'"{num_columns}",' + enriched_row

                if key not in splits:
                    splits[key] = []  # Initialize an empty list for the key if not exists
                    # Insert the filename and number of values followed by technology, flow, and flowno
                    splits[key].append(f'"1","{filename}"')
                    splits[key].append(f'"1",{str(row.iloc[25])}' if str(row.iloc[25]).startswith('"') else f'"1","{str(row.iloc[25])}"') 
                    splits[key].append(f'"1",{str(row.iloc[23])}' if str(row.iloc[23]).startswith('"') else f'"1","{str(row.iloc[23])}"') 
                    splits[key].append(f'"1",{str(row.iloc[24])}' if str(row.iloc[24]).startswith('"') else f'"1","{str(row.iloc[24])}"')

                splits[key].append(final_row)  # Append the enriched row

                # Store Technology, Flow, and Flow No
                technology[key] = row.iloc[25]
                flow[key] = row.iloc[23]
                flowno[key] = row.iloc[24]

            # Update splits with the total number of entries
            for key in splits:
                total_entries = len(splits[key])
                splits[key].insert(0, f'"{total_entries}"')

            model.misc.update(splits)
            return model
        except FileNotFoundError:
            Util.dp_exit(1, f"File '{infile}' not found.")
        except Exception as e:
            Util.dp_exit(1, f"An error occurred: {e}")
            
            
            
