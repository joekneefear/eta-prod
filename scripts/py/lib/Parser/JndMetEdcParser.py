"""
SYNOPSIS

DESCRIPTION

JND MET/EDC file parser

AUTHOR

    junifferallan.garcia@onsemi.com

CHANGES
    2024-Jul-16 - jgarcia - initial
    2024-Dec-04 - jgarcia - use mulitprocessing  Pool to improve processing speed

LICENSE
    (C) onsemi 2024 All rights reserved.

"""

import pandas as pd
import numpy as np
import os
import re
import shutil
import subprocess
import gzip
import json
import csv
import gc
import dask.dataframe as dd
from concurrent.futures import ProcessPoolExecutor
from functools import lru_cache
from lib.Data import Base, Model
from lib.Util import Util
from lib.Log import Log
from typing import Dict, List
from lib.Util import Util
from lib.Utility.JndUtil import JndUtil
from multiprocessing import Pool, cpu_count
from io import StringIO

class JndMetEdcParser:

    def __init__(self, file_path, decompressing_staging_folder, lot_metadata_location, types, refdb_api_client, ws_urls, waferids, generate_limits, default_onscribe_metadata, default_onlot_metadata, use_ERT):
        self.file_path = file_path
        self.decompressing_staging_folder = decompressing_staging_folder
        self.lot_metadata_location = lot_metadata_location
        self.types = types
        self.refdb_api_client = refdb_api_client
        self.ws_urls = ws_urls
        self.edc_sheet_file = None
        self.dat_file = None
        self.edc_info = {}
        self.waferids = waferids 
        self.new_waferids = {}
        self.generate_limits = generate_limits
        self.default_onscribe_metadata = default_onscribe_metadata
        self.default_onlot_metadata = default_onlot_metadata
        self.use_ERT = use_ERT

    def get_attr_name(self):
        attr_name_list = []
        edc_info = {}
        line_data = ""
        
        met_flag, fab_edc_flag, prd_edc_flag, eqp_edc_flag = "", "", "", ""
        
        if self.types:
            for type_ in self.types:
                if "MET" in type_:
                    met_flag = type_
                elif "PRD_EDC" in type_:
                    prd_edc_flag = type_
                elif "FAB_EDC" in type_:
                    fab_edc_flag = type_
                elif "EQP_EDC" in type_:
                    eqp_edc_flag = type_
                # print(f"TYPE===>>>{type_}")
        else:
            Log.ERROR("ERROR: No specified Type to be processed")
            Util.dp_exit(1, "ERROR: No specified Type to be processed")

        try:
            with open(self.edc_sheet_file, 'r', encoding='utf-8', errors='ignore') as file_handle:
                for line in file_handle:
                    line_data = line.strip()
                    elements = line_data.split(',')
                    type_ = elements[1].strip()
                    if (type_ == "MET" and type_ == met_flag) or \
                    (type_ == "FAB_EDC" and type_ == fab_edc_flag) or \
                    (type_ == "PRD_EDC" and type_ == prd_edc_flag) or \
                    (type_ == "EQP_EDC" and type_ == eqp_edc_flag):
                        if elements[0] != "ATTR_NAME":
                            if type_ not in edc_info:
                                edc_info[type_] = []
                            edc_info[type_].append(elements[0].strip())
            # return edc_info
            self.edc_info = edc_info
        except IOError:
            Log.ERROR(f"ERROR: Failed to open EDC SHEET file={self.edc_sheet}")
            Util.dp_exit(1, "ERROR: Failed to open EDC SHEET file={edc_sheet}")

    @lru_cache(maxsize=None)
    def get_technology(self, df, mother_lot):
        # Filter the DataFrame for the specific condition
        matching_row = df[(df['Column0'].str.strip() == Util.trim(df['Column0'])) & 
                        (df['Column4'].str.strip() == "Estl_Std_Process")]
        
        if not matching_row.empty:
            return matching_row.iloc[0]['Column5']
        
        filename = f"{mother_lot}.lot"
        lot_file_fullpath = os.path.join(self.lot_metadata_location, filename)
        
        # Load the CSV file into a DataFrame
        lot_df = pd.read_csv(lot_file_fullpath)
        
        # Find the row that matches your condition in the lot file
        lot_matching_row = lot_df[(lot_df['Column0'].str.strip() == Util.trim(df['Column0'])) & 
                                (lot_df['Column4'].str.strip() == "Estl_Std_Process")]
        
        if not lot_matching_row.empty:
            return lot_matching_row.iloc[0]['Column5']
        
        # If no matching row is found, return None or handle accordingly
        return 'NA'
    
    def process_waferid(self, lot_holder, wafer_number, jnd_sourceLot):
        # wafer_number = Util.format_wafer_number(wafer_number)
        lot_wafer_key = f"{lot_holder}_{wafer_number}"
                  
        onlot_metadata = self.default_onlot_metadata
        onscribe_metadata = self.default_onscribe_metadata
        onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'lot', lot_holder)
        onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'waferNum', wafer_number)
        onlot_metadata =  Util.replace_dict_value(onlot_metadata, 'lot', lot_holder)
        onlot_metadata = Util.replace_dict_value(onlot_metadata, "sourceLot", jnd_sourceLot)
        # onscribe_metadata = Util.update_wafer_id(onscribe_metadata, jnd_sourceLot, wafer_number)
        # waferid = onscribe_metadata.get('waferId', 'NA')
        waferid = "NA"       
        if Util.looks_like_number(wafer_number):
            # lot_wafer_key = f"{lot_holder}_{wafer_number}"
            waferid = JndUtil.get_waferid_scribe_file(lot_holder, wafer_number, self.waferids)
            if waferid == 'NA':
                if self.use_ERT:
                    # onscribe_ws_url = self.ws_urls.get('onscribe', '')
                    onscribe_metadata, new_lot_wafer_key = JndUtil.get_jnd_onscribe_metadata(self.refdb_api_client, self.ws_urls, jnd_sourceLot, self.waferids, lot_holder, wafer_number, onscribe_metadata, onlot_metadata)
                    waferid = onscribe_metadata.get('waferId', 'NA')
                    if isinstance(onscribe_metadata, dict) and onscribe_metadata['status'].upper() == 'MANUAL':
                        Log.INFO(f"WAFERID from ERT={waferid} will be used.")
                        for key in [new_lot_wafer_key, lot_wafer_key]:
                            if key and key not in self.new_waferids:
                                self.new_waferids[key] = waferid
                    else:
                        Log.INFO(f"CALCULATED WAFERID from ONSCRIBE={waferid} will be used.")
                else:
                    onscribe_metadata = Util.update_wafer_id(onscribe_metadata, jnd_sourceLot, wafer_number)
                    waferid = onscribe_metadata.get('waferId', 'NA')
            else:
                Log.INFO(f"WAFERID from Scribe/ShipScribe reference file={waferid} will be used.")
        else:
           Log.INFO(f"No valid wafer number={wafer_number}, WAFERID{waferid} will be NA.")
     
            
        return waferid, lot_wafer_key

    def process_line(self, row):
        rep_fields = ['NA' if item in ['', ' '] else str(item) for item in row]
        waferid = "NA"
        wafer_number = ""

        if len(rep_fields) not in [26,27]:
            Log.ERROR(f"ERROR: Expected {expected_columns} columns, but got {len(rep_fields)}")
            Util.dp_exit(1, f"ERROR: Expected {expected_columns} columns, but got {len(rep_fields)}")

        item_name = rep_fields[4]
        lot_holder = rep_fields[0]
        jnd_mother_lot, jnd_sourceLot = JndUtil.get_jnd_lot_mother_lot_source_lot_not_refdb(lot_holder)
        fab = "JND:AIZU2 FAB (PTI)"
        wafer_number = rep_fields[6]
                       
        limit_key = f"{rep_fields[0]}_{rep_fields[4]}"
        line_data = f"{'|'.join(rep_fields)}"

        if len(rep_fields) < 27:
            technology = self.get_technology(rep_fields, jnd_mother_lot)
            line_data = f"{line_data}|{technology}"
        else:  # expected_columns == 27
            technology = rep_fields[26]
            # line_data = f"{'|'.join(rep_fields)}|{technology}"

        # if wafer_number not in ['NA', '', ' '] or Util.looks_like_number(wafer_number):
        if wafer_number not in ['NA', '', ' ']:
            wafer_number = Util.format_wafer_number(wafer_number)
            waferid, lot_wafer_key = self.process_waferid(lot_holder, wafer_number, jnd_sourceLot)
        else:
            Log.INFO(f"No wafer number could be a lot metrology, wafer number={wafer_number}, waferid will be NA - WAFERID={waferid}")                   

        line_data = f"{line_data}|{waferid}|{jnd_sourceLot}|{fab}"

        limit_line = self.create_limit_line(rep_fields, technology) if self.generate_limits else ""

        return item_name, line_data, limit_line, limit_key

    def split_and_enrich_file(self):
        # Initialize variables
        model = Model()
        model.misc = {
            'file_data': {},
            'met_limit_file_data': {},
            'prd_edc_limit_file_data': {},
            'fab_edc_limit_file_data': {},
            'eqp_edc_limit_file_data': {}
        }

        if self.dat_file is None:  # Check if dat_file is None
            Log.ERROR("ERROR: dat_file is not set.")
            Util.dp_exit(1, "ERROR: dat_file is not set.")

        try:
            with open(self.dat_file, 'r', encoding='utf-8', errors='replace') as file_handle:
                if not self.edc_info:
                    Log.ERROR("EDC Sheet is not processed properly")
                    Util.dp_exit(1, "EDC Sheet is not processed properly")

                Log.INFO("Enriching and splitting the MET/EDC file")

                # Use csv.reader to read the file
                reader = csv.reader(file_handle)
                
                # # Determine the number of columns from the first row
                # first_row = next(reader)
                # expected_columns = len(first_row)
                
                # if expected_columns not in [26, 27]:
                #     Log.ERROR(f"ERROR: Unexpected number of columns: {expected_columns}")
                #     Util.dp_exit(1, f"Unexpected number of columns: {expected_columns}")

                # # Process the first row
                # result = self.process_line(first_row, expected_columns, self.waferids, self.refdb_api_client, self.ws_urls)
                # item_name, line_data, limit_line, limit_key = result
                # self.update_model_data(model, item_name, line_data, limit_line, limit_key)

                # Process the remaining rows
                for row in reader:
                    result = self.process_line(row)
                    item_name, line_data, limit_line, limit_key = result
                    self.update_model_data(model, item_name, line_data, limit_line, limit_key)

                return model, self.new_waferids

        except UnicodeDecodeError as e:
            Log.ERROR(f"Unicode decode error: {e}")
            Util.dp_exit(1, f"Unicode decode error: {e}")

        except IOError:
            Log.ERROR(f"Failed to open {self.dat_file}")
            Util.dp_exit(1, f"Failed to open {self.dat_file}")

        except StopIteration:
            Log.ERROR("No more rows to read from the file.")
            Util.dp_exit(1, "No data or no lines in the raw file. Please check!")

   
    def get_lot_info_not_refdb(self, lot_holder):
        # if re.match(r'^JM.*|^SY.*', lot_holder, re.IGNORECASE):
        source_lot = "NA"
        mother_lot = "NA"
        if len(lot_holder) >= 2 and lot_holder[:2].isalpha():
            source_lot = f'{lot_holder.split(".")[0]}.S'
            mother_lot = lot_holder.split(".")[0]
        elif lot_holder.startswith("7G"):
            if len(lot_holder) >= 13 and lot_holder[7] == "-":
                # Extract parts of the lot_id_value and concatenate them
                source_lot_value = lot_holder[4:7] + lot_holder[8:13]
                mother_lot = lot_holder[:13]
                source_lot_value += ".S"
            else:
                # If the length is less than 13 or the 8th character is not "-", use the whole lot_id_value
                # source_lot_value_without_s = lot_id_value
                mother_lot = lot_holder
                source_lot_value = lot_holder + ".S"
            # Set parent_lot_value to the first 13 characters of lot_id_value
            # parent_lot_value = lot_id_value[:13]
        # Log.INFO(f"MotherLot={mother_lot} || SourceLot={source_lot}")
        return mother_lot, source_lot
  

    def get_onscribe_info(self, lot, wafer_number):
        onscribe_url = f"{self.ws_urls['onscribe']}/{lot}/{wafer_number}"
        onscribe_metadata = self.refdb_api_client.get_metadata(onscribe_url)
        return onscribe_metadata
    
    def get_onlot_info(self, lot):
        lot_data = self.refdb_api_client['onlot'].get_lot_metadata_by_lotid(lot)
        return lot_data


    def get_source_lot_value(self, mother_lot):
        lot_data = self.refdb_api_client.get_lot_metadata_by_lotid(mother_lot)
        source_lot_ws = ""
        if lot_data is None:
            Log.INFO('Lot metadata data not found')
            sl, slws, pl = self.get_source_lot_without_metadata(mother_lot) 
            return sl, slws

        source_lot = lot_data.get('sourceLot', 'NA')
        source_lot_ws = source_lot.split('.')[0]
        # Log.INFO(f'WaferId={waferid}')

        return source_lot, source_lot_ws

    def get_source_lot_without_metadata(self, lot_id_value):
        starts_with = lot_id_value[:2]
        source_lot_value_without_s = ""
        if starts_with == "7G":
            if len(lot_id_value) >= 13 and lot_id_value[7] == "-":
                # Extract parts of the lot_id_value and concatenate them
                source_lot_value = lot_id_value[4:7] + lot_id_value[8:13]
                source_lot_value_without_s = source_lot_value
                source_lot_value += ".S"
            else:
                # If the length is less than 13 or the 8th character is not "-", use the whole lot_id_value
                source_lot_value_without_s = lot_id_value
                source_lot_value = lot_id_value + ".S"
            # Set parent_lot_value to the first 13 characters of lot_id_value
            parent_lot_value = lot_id_value[:13]
        else:
            # For other cases, process the lot_id_value before the first "."
            source_lot_value = lot_id_value.split('.')[0]
            parent_lot_value = source_lot_value
            source_lot_value += ".S"

        return source_lot_value, source_lot_value_without_s, parent_lot_value


    def create_limit_line(self, rep_fields, technology):
        return f"{rep_fields[0]}|{rep_fields[4]}|{technology}|{rep_fields[2]}|{rep_fields[9]}|{rep_fields[18]}|{rep_fields[19]}|{rep_fields[20]}|{rep_fields[21]}|{rep_fields[22]}|{rep_fields[23]}|{rep_fields[24]}|{rep_fields[25]}"

    def update_model_data(self, model, item_name, line_data, limit_line, limit_key):
        added_limits = set()
        
        for key, addr in self.edc_info.items():
            if item_name in addr:
                model.misc['file_data'].setdefault(key, []).append(line_data)
                
                if self.generate_limits:
                    if "MET" in key:
                        hash_lim_key = "MET_LIMIT"
                        if limit_line not in added_limits:
                            model.misc['met_limit_file_data'].setdefault(hash_lim_key, []).append(limit_line)
                            added_limits.add(limit_line)
                    
                    elif "PRD_EDC" in key:
                        hash_lim_key = "PRD_EDC_LIMIT"
                        if limit_line not in added_limits:
                            model.misc['prd_edc_limit_file_data'].setdefault(hash_lim_key, []).append(limit_line)
                            added_limits.add(limit_line)
                    
                    elif "FAB_EDC" in key:
                        hash_lim_key = "FAB_EDC_LIMIT"
                        if limit_line not in added_limits:
                            model.misc['fab_edc_limit_file_data'].setdefault(hash_lim_key, []).append(limit_line)
                            added_limits.add(limit_line)
                    
                    elif "EQP_EDC" in key:
                        hash_lim_key = "EQP_EDC_LIMIT"
                        if limit_line not in added_limits:
                            model.misc['eqp_edc_limit_file_data'].setdefault(hash_lim_key, []).append(limit_line)
                            added_limits.add(limit_line)
    
    def process_files(self, base_zip_filename):
        try:
            for inflated_file in os.listdir(self.decompressing_staging_folder):
                inflated_file_path = os.path.join(self.decompressing_staging_folder, inflated_file)
                if inflated_file.lower().endswith('.txt'):
                    self.process_txt_file(inflated_file, inflated_file_path, base_zip_filename)
                elif inflated_file.lower().endswith('.dat'):
                    self.process_dat_file(inflated_file, inflated_file_path, base_zip_filename)
        except Exception as e:
            Log.ERROR(f"Can't open {self.decompressing_staging_folder}: {e}")
            raise SystemExit(f"Can't open {self.decompressing_staging_folder}")

    def process_txt_file(self, inflated_file, inflated_file_path, base_zip_filename):
        Log.INFO(f"EDC_SHEET={inflated_file}")
        new_filename = f"{base_zip_filename}-{inflated_file}"
        new_file_path = os.path.join(self.decompressing_staging_folder, new_filename)
        shutil.move(inflated_file_path, new_file_path)

    def process_dat_file(self, inflated_file, inflated_file_path, base_zip_filename):
        Log.INFO(f"Executing dos2unix against {inflated_file_path}")
        try:
            subprocess.run(['dos2unix', inflated_file_path], check=True)
        except subprocess.CalledProcessError as e:
            Log.ERROR(f"dos2unix command failed: {e}")
            raise SystemExit("dos2unix command not successful")
        new_filename = f"{base_zip_filename}-{inflated_file}"
        new_file_path = os.path.join(self.decompressing_staging_folder, new_filename)
        shutil.move(inflated_file_path, new_file_path)

    def unzip_file_main(self):
        base_infile = os.path.basename(self.file_path)
        base_zip_filename = base_infile.replace('.', '_')

        if os.listdir(self.decompressing_staging_folder):
            Util.clean_temp_directory(self.decompressing_staging_folder)

        try:
            Util.unzip_file(self.file_path, self.decompressing_staging_folder)
        except SystemExit:
            Log.ERROR(f"Error while unzipping file={self.file_path}")
            Util.dp_exit(1, "Unzipping Error!")
            raise

        self.process_files(base_zip_filename)

    def write_lots_to_file(self, data_dict: List[Dict[str, List[str]]], file_extension: str, prefix: str, out_file_location: str, base_file: str):
        if data_dict:
            for lot_dict in data_dict:
                for lot, line_array in lot_dict.items():
                    if line_array:
                        filename = f"{prefix}_{lot}_{base_file}{file_extension}"
                        outfile = os.path.join(out_file_location, filename)
                        temp_outfile = outfile + ".tmp"
                        gz_outfile = outfile + '.gz'
                        temp_gz_outfile = gz_outfile + '.tmp'

                        # Ensure the output directory exists
                        os.makedirs(out_file_location, exist_ok=True)

                        with open(temp_outfile, 'w') as file_handle:
                            file_handle.write("<DATA>\n")
                            for line in line_array:
                                file_handle.write(line.strip() + "\n")
                            file_handle.write("</DATA>\n")
                            file_handle.flush()
                            os.fsync(file_handle.fileno())
                        os.replace(temp_outfile, outfile)

                        Log.INFO(f"Compress {outfile} with gzip")
                        # Added gzip compression
                        with open(outfile, 'rb') as f_in, gzip.open(temp_gz_outfile, 'wb') as f_out:
                            shutil.copyfileobj(f_in, f_out)
                            f_out.flush()
                            os.fsync(f_out.fileobj.fileno())
                        os.replace(temp_gz_outfile, gz_outfile)
                        os.remove(outfile)
        else:
            Log.WARN(f"No data lines from the raw file for {prefix}")

    def distribute_lots(self, data_dict, lot_per_file):
        set_counter = 1
        counter = 1
        result_dict = {}
        Log.INFO(f"Lot per file is set to={lot_per_file}")

        for lot, line_array in data_dict.items():
            my_key = f"set_{set_counter}"
            if line_array:
                if counter <= lot_per_file:
                    result_dict.setdefault(my_key, []).extend(line_array)
                else:
                    set_counter += 1
                    my_key = f"set_{set_counter}"
                    counter = 1
                    result_dict.setdefault(my_key, []).extend(line_array)
            counter += 1

        return result_dict
    

    def split_lot_data_with_counter(self, lot_data: Dict[str, List[str]], lot_per_file: int) -> List[Dict[str, List[str]]]:
        split_data = []
        
        for lot, lines in lot_data.items():
            split_counter = 1
            for i in range(0, len(lines), lot_per_file):
                subset_key = f"{lot}_split_{split_counter}"
                subset = {subset_key: lines[i:i + lot_per_file]}
                split_data.append(subset)
                split_counter += 1
        
        return split_data
    
    @lru_cache(maxsize=None)
    def get_wafer_number_from_line(self, line: str, delimiter: str) -> str:
        columns = line.split(delimiter)
        wafer_number = columns[6]

        return str(wafer_number).zfill(2)

    

       
