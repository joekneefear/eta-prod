"""
SYNOPSIS

DESCRIPTION
    JND Utility Class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Dec-07 - jgarcia - initial
    2025-Sep-01 - jgarcia - enhanced get_waferid_scribe_file surpport multi lot prefix and wafer string length variant (wafer nubmer formats, e,g. "1" vs "01")

LICENSE
    (C) onsemi 2023 All rights reserved.
"""

import os
import psutil
import sys
import re
import time
import subprocess
import magic
import traceback
import yaml
import smtplib
import csv
import gzip
import shutil
import zipfile
import glob
import json
import redis
import threading
import fcntl
import pandas as pd
import mmap
from filelock import FileLock, Timeout
from datetime import datetime, timedelta
from calendar import month_abbr
from pathlib import Path
import logging.handlers as handlers
from datetime import datetime
from calendar import timegm
from time import sleep, strftime, localtime, time
from lib.Log import Log
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from pathlib import Path
from typing import Optional
from dateutil import parser
from collections import defaultdict
from lib.Util import Util

class JndUtil:
    
    @staticmethod
    def get_technology_from_lot_metadata_file(file_path):
        try:
            with open(file_path, 'r') as file:
                reader = csv.reader(file)
                last_line = None
                for last_line in reader:
                    pass
                if last_line and len(last_line) >= 17:
                    return last_line[16]
                else:
                    return "NA"
        except FileNotFoundError:
            Log.ERROR(f"File not found: {file_path}")
            return "NA"
        except Exception as e:
            Log.ERROR(f"An error occurred: {e}")
            Log.ERROR(f"ERROR in getting the Technology from the provided lot metadata file={file_path}")
            return "NA"
        
    @staticmethod
    def get_technology_and_lotType_from_lot_metadata_file(file_path):
        try:
            with open(file_path, 'r') as file:
                reader = csv.reader(file)
                last_line = None
                for last_line in reader:
                    pass
                
                if last_line and len(last_line) >= 24:
                    technology = last_line[16]
                    lot_type = last_line[23]
                    return technology, lot_type
                else:
                    Log.WARN(f"Insufficient data in the last line of {file_path}")
                    return "NA", "NA"
        except FileNotFoundError:
            Log.ERROR(f"File not found: {file_path}")
            # Util.dp_exit(1, f"File not found: {file_path}")
        except csv.Error as e:
            Log.ERROR(f"CSV parsing error in {file_path}: {e}")
            # Util.dp_exit(1, f"CSV parsing error in {file_path}: {e}")
        except Exception as e:
            Log.ERROR(f"An error occurred while processing {file_path}: {e}")
            # Util.dpexit(1, f"An error occurred while processing {file_path}: {e}")
        Log.ERROR(f"Failed to extract information from lot metadata file: {file_path}")
        # Util.dpexit(1, f"Failed to extract information from lot metadata file: {file_path}")
        return "NA", "NA"
    
    @staticmethod
    def find_first_jnd_fjm_file(folder_location: str, tpno: str) -> Optional[str]:
        """
        Finds the first .fjm file in the specified folder that matches the given pattern.

        Args:
            folder_location (str): The path to the folder where .fjm files are located.
            tpno (str): The pattern to match within the .fjm file names.

        Returns:
            Optional[str]: The path to the first matching .fjm file, or None if no match is found.
        """
        # Ensure the folder exists
        if not os.path.isdir(folder_location):
            raise FileNotFoundError(f"The folder '{folder_location}' does not exist.")
        
        # Construct the search pattern
        search_pattern = os.path.join(folder_location, f"*{tpno}*.fjm")
        
        # Find all matching .fjm files
        fjm_files = sorted(glob.glob(search_pattern))
        
        # Return the first matching file or None if no files are found
        return fjm_files[0] if fjm_files else None
 
        
    @staticmethod
    def get_jnd_lot_mother_lot_source_lot_not_refdb(lot):
        # if re.match(r'^JM.*|^SY.*', lot_holder, re.IGNORECASE):
        source_lot = "NA"
        mother_lot = "NA"
        if len(lot) >= 2 and lot[:2].isalpha():
            source_lot = f'{lot.split(".")[0]}.S'
            mother_lot = lot.split(".")[0]
        elif lot.startswith("7G"):
            if len(lot) >= 13 and lot[7] == "-":
                # Extract parts of the lot_id_value and concatenate them
                source_lot_value = lot[4:7] + lot[8:13]
                mother_lot = lot[:13]
                # source_lot_value += ".S"
                source_lot = source_lot_value + ".S"

            else:
                # If the length is less than 13 or the 8th character is not "-", use the whole lot_id_value
                # source_lot_value_without_s = lot_id_value
                mother_lot = lot
                source_lot = lot + ".S"
            # Set parent_lot_value to the first 13 characters of lot_id_value
            # parent_lot_value = lot_id_value[:13]
        # Log.INFO(f"MotherLot={mother_lot} || SourceLot={source_lot}")
        return mother_lot, source_lot

    @staticmethod
    def load_jnd_scribe_ship_scribe_and_save_to_csv(incoming_scribe_file, orig_scribe_file):
        existing_rows = set()
        
        # Read existing rows from the CSV file
        try:
            with open(orig_scribe_file, 'r', newline='') as csvfile:
                csv_reader = csv.reader(csvfile)
                for row in csv_reader:
                    if row:
                        existing_rows.add(tuple(row))
        except FileNotFoundError:
            # If the file does not exist, we will create it later
            pass
        except IOError as e:
            Log.ERROR(f"IO error while reading {orig_scribe_file}: {e}")
            return
        
        rows_inserted = 0
        rows_skipped = 0
        
        # Process the scribe file and write new entries to the CSV file
        try:
            with open(incoming_scribe_file, 'r+b') as f, open(orig_scribe_file, 'a', newline='') as csvfile:
                Log.INFO(f"Loading data from {incoming_scribe_file}")
                csv_writer = csv.writer(csvfile)
                mmapped_file = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
                
                # Lock the CSV file
                fcntl.flock(csvfile, fcntl.LOCK_EX)
                
                for line in iter(mmapped_file.readline, b""):
                    parts = line.decode().strip().split(',')
                    
                    # Check if the line does not start with "LOT" or "lot"
                    if not (parts[0].startswith("LOT") or parts[0].startswith("lot")):
                        row_tuple = tuple(parts)
                        if row_tuple not in existing_rows:
                            csv_writer.writerow(parts)
                            existing_rows.add(row_tuple)
                            rows_inserted += 1
                        else:
                            rows_skipped += 1
                
                # Unlock the CSV file
                fcntl.flock(csvfile, fcntl.LOCK_UN)
                
                Log.INFO(f"Data successfully saved to {orig_scribe_file}.")
                Log.INFO(f"Rows inserted: {rows_inserted}")
                Log.INFO(f"Rows skipped (already existed): {rows_skipped}")
        except IOError as e:
            Log.ERROR(f"IO error: {e}")

# # Example usage
# load_jnd_scribe_ship_scribe_and_save_to_csv('input_scribe_file.txt', 'output_data.csv')
      
    @staticmethod
    def load_jnd_scribe_ship_scribe_and_save_to_redis(scribe_file, redis_host='localhost', redis_port=6379, redis_db=0):
        r = redis.Redis(host=redis_host, port=redis_port, db=redis_db)
        
        try:
            with open(scribe_file, 'r', buffering=10*1024*1024) as f:
                Log.INFO(f"Loading data from {scribe_file}")
                pipeline = r.pipeline()
                for line in f:
                    parts = line.strip().split(',')
                    if len(parts) == 3:
                        # Format: key = f"{parts[0]}_{parts[1]}", value = parts[2]
                        key = f"{parts[0]}_{parts[1]}"
                        value = parts[2]
                    elif len(parts) == 5:
                        # Format: key = f"{parts[4]}_{parts[1]}", value = parts[2]
                        key = f"{parts[4]}_{parts[1]}"
                        value = parts[2]
                    else:
                        Log.WARN(f"Unexpected format in line: {line}")
                        continue
                    pipeline.set(key, value)
                pipeline.execute()
                Log.INFO(f"Data successfully saved to Redis.")
        except IOError as e:
            Log.ERROR(f"IO error: {e}")
        except redis.RedisError as e:
            Log.ERROR(f"Redis error: {e}")
    
    @staticmethod
    def load_json_jnd_scribe_to_redis(json_file, redis_host='localhost', redis_port=6379, redis_db=0):
        r = redis.Redis(host=redis_host, port=redis_port, db=redis_db)
        
        try:
            with open(json_file, 'r', buffering=10*1024*1024) as f:
                data = json.load(f)
                Log.INFO(f"Data loaded from {json_file}")
        except json.JSONDecodeError as e:
            Log.ERROR(f"JSON decoding error: {e}")
            return
        except IOError as e:
            Log.ERROR(f"IO error: {e}")
            return
        
        # Save data to Redis
        try:
            for key, value in data.items():
                r.set(key, json.dumps(value))  # Store value as JSON string
            Log.INFO(f"Data successfully saved to Redis.")
        except redis.RedisError as e:
            Log.ERRPR(f"Redis error: {e}")
    
    @staticmethod
    def retrieve_all_jnd_scribe_from_redis(redis_host='localhost', redis_port=6379, redis_db=0):
        # Connect to Redis
        r = redis.Redis(host=redis_host, port=redis_port, db=redis_db)
        
        # Initialize an empty dictionary to store the data
        data_dict = {}
        
        # Use the scan method to get all keys
        cursor = '0'
        keys = []
        while cursor != 0:
            cursor, batch_keys = r.scan(cursor=cursor, match='*', count=1000)
            keys.extend(batch_keys)
        
        # Use MGET to get all values at once
        values = r.mget(keys)
        
        # Store the retrieved values in the dictionary
        for key, value in zip(keys, values):
            try:
                # Attempt to decode the value as JSON
                data_dict[key.decode('utf-8')] = json.loads(value)
            except json.JSONDecodeError:
                # If value is not JSON, store it as a string
                data_dict[key.decode('utf-8')] = value.decode('utf-8')
        
        return data_dict

    @staticmethod
    def load_jnd_advantest_tests(file_path):
        tests = {}
        with open(file_path, 'r') as f:
            for line in f:
                # Strip whitespace and handle both quoted and unquoted formats
                line = line.strip()
                if line.startswith('"') and line.endswith('"'):
                    fields = line[1:-1].split('","')  # Remove surrounding quotes and split
                else:
                    fields = line.split(',')  # Split by comma if no quotes

                if len(fields) == 2:
                    tests[fields[0].strip()] = fields[1].strip()  # Strip any extra whitespace
        return tests

    @staticmethod
    def load_jnd_lot_metadata(lot_metadata_file):
        # Initialize lot_metadata and last_lot_metadata with keys set to None
        lot_metadata = {}
        last_lot_metadata = {}
        try:
            with open(lot_metadata_file, 'r') as f:
                fab = 'NA'
                for line in f:
                    fields = line.strip().split(',')
                    if len(fields) == 25:
                        lotid = fields[0]
                        if fields[20].startswith('7G'):
                            fab = 'JND:AIZU2 FAB (PTI)'
                        else:
                            fab = fields[20]
                        lot_metadata[lotid] = {
                            'TPNO': fields[1],
                            'AccountCode': fields[8],
                            'MBNO': fields[11],
                            'Process': fields[14],
                            'Technology': fields[16],
                            'Fab': fab,
                            'SourceLot': fields[21],
                            'ParentLot': fields[22],
                            'LotType': fields[23]
                        }
                        last_lot_metadata = lot_metadata[lotid]  # Update after adding to lot_metadata
        except FileNotFoundError:
            Log.ERROR(f"Error: The file {lot_metadata_file} was not found.")
        except Exception as e:
            Log.ERROR(f"An error occurred: {e}")
        return lot_metadata, last_lot_metadata

    @staticmethod
    def jnd_alpha_ship_lot(lot):
        ship_lot = lot.replace('.', '0')
        Log.INFO(f"Replace . to 0 in lot to derive a ship lot = {ship_lot}")
        return ship_lot
    
    @staticmethod
    def jnd_7G_to_jm(lot):
        Log.INFO(f"Try convert 7G lots to JM")
        jm_lot = JndUtil.convert_jnd_legacy_lotid(lot)
        Log.INFO(f"{jm_lot} is the converted result from lot={lot}")
        return jm_lot
        # if jm_lot:
        #     return jm_lot
        # else:
        #     return derive_and_process_ship_lot(lot)
    @staticmethod
    def jnd_alpha_parent_lot(lot):
        # ship_lot = _derive_ship_lot(lot)
        parent_lot = re.sub(r'\.\d+', '.1', lot)
        return parent_lot
        # if parent_lot:
        #     return parent_lot
        # else:
        #     return ship_lot
    @staticmethod
    def get_on_scribe_metadata_from_ERT_by_lot_wafer_number(refdb_api_client, url, default_onscribe_metadata, lot='NA', wafer_number='NA'):
       
        default_onscribe_metadata = Util.replace_dict_value(default_onscribe_metadata, 'lot', lot)
        default_onscribe_metadata = Util.replace_dict_value(default_onscribe_metadata, 'waferNum', wafer_number)
        
        try:
            Log.INFO(f"LOT={lot} || WAFER_NUMBER={wafer_number}")
            if lot not in ['NA', '', ' '] and  wafer_number not in  ['NA', '', ' ']:
                full_url = f"{url}/{lot}/{wafer_number}"
                return refdb_api_client.get_metadata(full_url, default_onscribe_metadata)
            else:
                Log.WARN(f"lot={lot} or wafer number={wafer_number} is NA or no value")
                return default_onscribe_metadata
        except Exception as e:
            Log.ERROR(f"Error retrieving metadata with: {e}\n")
            return default_onscribe_metadata
        
    @staticmethod
    def get_onlot_metadata_from_ERT_by_lot(refdb_api_client, url, default_onlot_metadata, lot='NA'):
       
        default_onlot_metadata = Util.replace_dict_value(default_onlot_metadata, 'lot', lot)
        try:
            Log.INFO(f"LOT={lot}")
            # base_url = url.get('onlot', 'NA')
            if lot not in ['NA', '', ' ']:
                full_url = f"{url}/{lot}"
                return refdb_api_client.get_metadata(full_url, default_onlot_metadata)
            # elif url_key == 'onlot' and lot != 'NA':
            #     full_url = f"{base_url}/{lot}"
            else:
                Log.WARN(f"lot is NA or no value")
                return default_onlot_metadata
            
        except Exception as e:
            Log.ERROR(f"Error retrieving metadata: {e}\n")
            return default_onlot_metadata

    @staticmethod
    def wafer_num_variants(wafer_number):
        """
        Return a list of wafer-number string variants to maximize matching without expanding the waferids map.
        Examples:
          "1"   -> ["1", "01", "001"]
          "01"  -> ["01", "1", "001"]
          1     -> ["1", "01", "001"]
        Order is deterministic and de-duplicated.
        """
        s = str(wafer_number).strip()
        try:
            n = int(s)  # normalize by removing leading zeros
        except ValueError:
            # Not numeric; return as-is
            return [s]

        # Build variants: original string, numeric (no leading zeros), 2-digit, 3-digit
        numeric = str(n)
        variants = [s, numeric, numeric.zfill(2), numeric.zfill(3)]

        # Deduplicate while preserving order
        seen = set()
        out = []
        for v in variants:
            if v not in seen:
                seen.add(v)
                out.append(v)
        return out

    @staticmethod
    def get_waferid_scribe_file(lot, wafer_number, waferids):
        """
        Resolve waferId from local scribe/ship_scribe references using several lot variants.
        Wafer-number normalization is done at lookup time (1, 01, 001), so the waferids map
        itself does not need to be expanded.

        Try, in order:
        1) Exact:            "{lot}_{wafer_number}" (with wafer-number variants)
        2) If 7G:
           - JM conversion:  "{JM_lot}_{wafer_number}"
           - 7G ship lot:    "{derived_ship_lot}_{wafer_number}"
           - 7G mother lot:  "{mother_lot_7g}_{wafer_number}"
        3) Else (alpha lots, e.g. JM/SY):
           - Parent lot .1:  "{parent_lot}_{wafer_number}"      (force .x -> .1)  [preferred first]
           - Ship lot:       "{ship_lot}_{wafer_number}"        ('.' -> '0')
           - Mother lot:     "{mother_lot}_{wafer_number}"      (trim after '.')
        Each key check tries wafer-number variants to tolerate formatting differences.
        """
        def log_waferid(lot_wafer_key, waferid):
            Log.INFO(f"Key={lot_wafer_key} is in scribe ref file, WAFERID={waferid} from SCRIBE/SHIP_SCRIBE reference file")

        def check_and_get_waferid_for_prefix(lot_prefix, wafer_number_local):
            # Try multiple wafer-number variants for the same lot prefix
            for wn in JndUtil.wafer_num_variants(wafer_number_local):
                key = f"{lot_prefix}_{wn}"
                if key in waferids:
                    waferid = waferids[key]
                    log_waferid(key, waferid)
                    return waferid
            return 'NA'

        def try_alternate_prefixes(lot_local, wafer_number_local):
            prefixes = []

            if lot_local.startswith('7G'):
                # 7G -> JM, then 7G ship, then 7G "mother lot"
                jm_lot = JndUtil.jnd_7G_to_jm(lot_local)
                if jm_lot and jm_lot.startswith('JM'):
                    prefixes.append(jm_lot)

                ship_lot_7g = JndUtil.derive_jnd_ship_lot_from_7G_lot(lot_local)
                if ship_lot_7g:
                    prefixes.append(ship_lot_7g)

                mother_lot_7g, _ = JndUtil.get_jnd_lot_mother_lot_source_lot_not_refdb(lot_local)
                if mother_lot_7g and mother_lot_7g != lot_local:
                    prefixes.append(mother_lot_7g)

            else:
                # Preferred: try .1 first (scribe files often store only .1)
                parent_lot = JndUtil.jnd_alpha_parent_lot(lot_local)  # e.g., SY61504.2 -> SY61504.1
                if parent_lot:
                    prefixes.append(parent_lot)

                # Then ship-lot if present in some sources
                ship_lot = JndUtil.jnd_alpha_ship_lot(lot_local)       # e.g., SY61504.2 -> SY6150402
                if ship_lot:
                    prefixes.append(ship_lot)

                # Finally, mother-lot (trim after '.'): e.g., SY61504.2 -> SY61504
                if '.' in lot_local:
                    mother_lot = lot_local.split('.', 1)[0]
                    if mother_lot:
                        prefixes.append(mother_lot)

            for prefix in prefixes:
                waferid = check_and_get_waferid_for_prefix(prefix, wafer_number_local)
                if waferid != 'NA':
                    return waferid
            return 'NA'

        # 1) Exact lot prefix first (with wafer-number variants)
        waferid = check_and_get_waferid_for_prefix(lot, wafer_number)
        if waferid != 'NA':
            return waferid

        # 2/3) Fallback lot prefixes
        return try_alternate_prefixes(lot, wafer_number)
 
    @staticmethod
    def get_jnd_onscribe_metadata(refdb_api_client, urls, jnd_sourceLot, waferids, lot, wafer_number, default_onscribe_metadata, default_onlot_metadata):
        base_onlot_url = urls.get('onlot', '')
        base_onscribe_url = urls.get('onscribe', '')

        def _derive_ship_lot(lot, onlot_metadata):
            ship_lot = onlot_metadata.get('mfgLot')  # No default 'NA' needed; None is handled later

            if ship_lot is None:  # Explicitly check for None
                ship_lot = lot.replace('.', '0')
                Log.INFO(f"No mfg lot from on_lot ERT. Replacing '.' with '0' in lot to derive ship lot: {ship_lot}")

            return ship_lot

        def _is_calculated_waferid_metadata(metadata):
            return metadata.get('status', '').upper() != 'MANUAL'  # Simplified

        def _is_LotG(metadata):
            return metadata.get('status', '').upper() != 'ERROR'  # Simplified

        def _get_onscribe_data(lot, wafer_number):
            return JndUtil.get_on_scribe_metadata_from_ERT_by_lot_wafer_number(
                refdb_api_client, base_onscribe_url, default_onscribe_metadata, lot, wafer_number
            )

        def process_7g_lot(lot, wafer_number):
            jm_lot = JndUtil.convert_jnd_legacy_lotid(lot)
            if jm_lot and jm_lot.startswith('JM'):
                return process_jm_lot(jm_lot, wafer_number)
            # Handle case where conversion fails; maybe fall back to original lot
            Log.WARNING(f"7G lot {lot} could not be converted to JM lot.")
            return _get_onscribe_data(lot, wafer_number), f"{lot}_{wafer_number}"

        def process_jm_lot(lot, wafer_number): # Handles JM and SY lots
            onscribe_metadata = _get_onscribe_data(lot, wafer_number)

            if not _is_calculated_waferid_metadata(onscribe_metadata):
                return onscribe_metadata, f"{lot}_{wafer_number}"

            onlot_metadata = JndUtil.get_onlot_metadata_from_ERT_by_lot(refdb_api_client, base_onlot_url, default_onlot_metadata, lot)
            
            if _is_LotG(onlot_metadata):
                ship_lot = _derive_ship_lot(lot, onlot_metadata)
                if ship_lot: # Check if ship_lot is valid
                    return _get_onscribe_data(ship_lot, wafer_number), f"{ship_lot}_{wafer_number}"
            # If no LotG or ship_lot derivation fails, no need for a separate 7G derivation here (jm_lot was already tried)
            return onscribe_metadata, f"{lot}_{wafer_number}"  # Return data for the JM/SY lot


        if lot.startswith('7G'):
            onscribe_ws_metadata, lot_wafer_key = process_7g_lot(lot, wafer_number)
        elif len(lot) >= 2 and lot[:2].isalpha():  # Covers SY and other alpha lots
            onscribe_ws_metadata, lot_wafer_key = process_jm_lot(lot, wafer_number)  # Now handles SY as well
        else:
            onscribe_ws_metadata, lot_wafer_key = _get_onscribe_data(lot, wafer_number), f"{lot}_{wafer_number}"


        onscribe_ws_metadata = Util.update_wafer_id(onscribe_ws_metadata, jnd_sourceLot, wafer_number)
        onscribe_ws_metadata['scribeId'] = onscribe_ws_metadata.get("waferId") # Direct assignment

        return onscribe_ws_metadata, lot_wafer_key



    
    @staticmethod
    def derive_jnd_ship_lot_from_7G_lot(lot):
        """
        Derives the ID from the given input string.

        Args:
        lot (str): The input string in the format '7G0FND6-95457-01'.

        Returns:
        str: The derived ID in the format 'ND69545701'.
        """
        try:
            # Split the input string by hyphens
            parts = lot.split('-')

            if len(parts) != 3 or len(parts[0]) < 7:
                Log.WARN('Unrecognized 7G lot, try to use lot as it is')
                return lot

            # Extract the relevant parts
            part1 = parts[0][4:7]  # Extract 'ND6' from '7G0FND6'
            part2 = parts[1]       # Extract '95457'
            part3 = parts[2]       # Extract '01'

            # Concatenate the parts
            derived_lot = part1 + part2 + part3

            return derived_lot
        except Exception as e:
            Log.ERROR(f"Error deriving ID: {e}")
            return None
        
    @staticmethod    
    def convert_jnd_legacy_lotid(legacy_lotid):
        legacy_len = len(legacy_lotid)
        # print(f"Legacy Lot ID: {legacy_lotid}, Length: {legacy_len}")

        if legacy_len >= 16:
            # print("Entered length >= 16 block")
            if legacy_lotid.startswith('7G') and legacy_lotid[7] == '-':
                char = legacy_lotid[8]
                # print(f"Character: {char}")
                if char in 'ABCDEFGHJK':
                    prefix = 'JM' + str(ord(char) - ord('A'))
                    suffix = legacy_lotid[9:13] + '.' + str(int(legacy_lotid[14:16]))
                    # print(f"Prefix: {prefix}, Suffix: {suffix}")
                    return prefix + suffix
        elif legacy_len == 14:
            if legacy_lotid.startswith('7G'):
                char = legacy_lotid[7]
                # print(f"CHAR={char}")
                if char in 'ABCDEFGHJK':
                    prefix = 'JM' + str(ord(char) - ord('A'))
                    suffix = legacy_lotid[8:12] + '.' + str(int(legacy_lotid[12:14]))
                    # print(f"PS={prefix}||{suffix}")
                    return prefix + suffix
        elif legacy_lotid.startswith('7G') or legacy_lotid.startswith('4E'):
            return None
        else:
            return legacy_lotid
        
    @staticmethod
    def create_dictionary_from_jnd_scribe_file(file_path):
        with open(file_path, 'r') as file:
            reader = csv.reader(file)
            scribe_dictionary = {
                (f"{fields[4]}_{fields[1]}" if len(fields) == 5 else f"{fields[0]}_{fields[1]}"): fields[2]
                for fields in reader if len(fields) in {3, 5}
            }
        return scribe_dictionary
 
    @staticmethod
    def append_to_jnd_scribe_file_if_not_exists(dictionary, file_path):
        try:
            # Read the existing content of the file
            Log.INFO(f"Opening {file_path}")
            with open(file_path, 'r') as file:
                existing_lines_set = set(line.strip() for line in file)
        except FileNotFoundError:
            # If the file does not exist, initialize an empty set for existing lines
            existing_lines_set = set()

        # Prepare the new lines to be added
        new_lines = []
        for key, value in dictionary.items():
            split_key = key.split('_')
            if len(split_key) >= 2:
                first_field = split_key[0]
                second_field = split_key[1]
                new_line = f"{first_field},{second_field},{value}\n"
                
                # Append the new line if it does not already exist
                if new_line.strip() not in existing_lines_set:
                    new_lines.append(new_line)
                    existing_lines_set.add(new_line.strip())
                    Log.INFO(f"Added: {new_line.strip()} to {file_path}")

        # Write all new lines to the file at once with file locking
        if new_lines:
            with open(file_path, 'a') as file:
                try:
                    # Lock the file for writing
                    fcntl.flock(file, fcntl.LOCK_EX)
                    file.writelines(new_lines)
                finally:
                    # Unlock the file
                    fcntl.flock(file, fcntl.LOCK_UN)
            
    @staticmethod
    def extract_lot_from_jnd_pcm_filename(filepath):
        # Extract the filename from the filepath
        filename = Path(filepath).name
        
        # Use regular expression to find the lot pattern in the filename
        match = re.search(r'_(\w+[-\w+]*)\.', filename)
        if match:
            return match.group(1)
        return None
    
    @staticmethod
    def load_ids(ids_json):
        lock_path = ids_json + '.lock'

        if os.path.exists(ids_json):
            lock = FileLock(lock_path, timeout=10)  # Timeout after 10 seconds

            try:
                with lock:
                    Log.INFO(f"Acquired lock for {ids_json}.")
                    with open(ids_json, 'r', buffering=10*1024*1024) as f:  # Use a larger buffer size
                        data = json.load(f)
                        Log.INFO(f"Data loaded from {ids_json}.")
                        return data
            except Timeout:
                Log.INFO(f"Could not acquire lock for {ids_json} within the timeout period.")
            except json.JSONDecodeError:
                Log.ERROR(f"JSON decoding error occurred while loading {ids_json}.")
            except IOError:
                Log.ERROR(f"IO error occurred while loading {ids_json}.")
            finally:
                Log.INFO(f"Released lock for {ids_json}.")
                if os.path.exists(lock_path):
                    try:
                        os.remove(lock_path)
                        Log.INFO(f"Manually removed lock file {lock_path}.")
                    except Exception as e:
                        Log.ERROR(f"Failed to remove lock file {lock_path}: {e}")
        else:
            Log.INFO(f"{ids_json} does not exist.")

        return {}
    
    @staticmethod
    def save_ids(ids_json, ids):
        lock_path = ids_json + '.lock'

        # Ensure the directory exists
        directory = os.path.dirname(ids_json)
        if directory and not os.path.exists(directory):
            os.makedirs(directory, exist_ok=True)
            Log.INFO(f"Directory {directory} created.")
        else:
            Log.INFO(f"Directory {directory} already exists.")

        lock = FileLock(lock_path, timeout=10)  # Timeout after 10 seconds

        try:
            with lock:
                Log.INFO(f"Acquired lock for {ids_json}.")
                with open(ids_json, 'w', buffering=10*1024*1024) as f:  # Use a larger buffer size
                    json.dump(ids, f)
                    Log.INFO(f"Data written to {ids_json}.")
        except Timeout:
            Log.INFO(f"Could not acquire lock for {ids_json} within the timeout period.")
        except Exception as e:
            Log.ERROR(f"An error occurred while saving ids: {e}")
        finally:
            Log.INFO(f"Released lock for {ids_json}.")
            if os.path.exists(lock_path):
                try:
                    os.remove(lock_path)
                    Log.INFO(f"Manually removed lock file {lock_path}.")
                except Exception as e:
                    Log.ERROR(f"Failed to remove lock file {lock_path}: {e}")
    
    @staticmethod
    def load_jnd_scribe_ship_scribe_and_save_to_redis(scribe_file, redis_host='localhost', redis_port=6379, redis_db=0):
        r = redis.Redis(host=redis_host, port=redis_port, db=redis_db)
        
        try:
            with open(scribe_file, 'r', buffering=10*1024*1024) as f:
                Log.INFO(f"Loading data from {scribe_file}")
                pipeline = r.pipeline()
                for line in f:
                    parts = line.strip().split(',')
                    if len(parts) == 3:
                        # Format: key = f"{parts[0]}_{parts[1]}", value = parts[2]
                        key = f"{parts[0]}_{parts[1]}"
                        value = parts[2]
                    elif len(parts) == 5:
                        # Format: key = f"{parts[4]}_{parts[1]}", value = parts[2]
                        key = f"{parts[4]}_{parts[1]}"
                        value = parts[2]
                    else:
                        Log.WARN(f"Unexpected format in line: {line}")
                        continue
                    pipeline.set(key, value)
                pipeline.execute()
                Log.INFO(f"Data successfully saved to Redis.")
        except IOError as e:
            Log.ERROR(f"IO error: {e}")
        except redis.RedisError as e:
            Log.ERROR(f"Redis error: {e}")
    
    @staticmethod
    def load_json_jnd_scribe_to_redis(json_file, redis_host='localhost', redis_port=6379, redis_db=0):
        r = redis.Redis(host=redis_host, port=redis_port, db=redis_db)
        
        try:
            with open(json_file, 'r', buffering=10*1024*1024) as f:
                data = json.load(f)
                Log.INFO(f"Data loaded from {json_file}")
        except json.JSONDecodeError as e:
            Log.ERROR(f"JSON decoding error: {e}")
            return
        except IOError as e:
            Log.ERROR(f"IO error: {e}")
            return
        
        # Save data to Redis
        try:
            for key, value in data.items():
                r.set(key, json.dumps(value))  # Store value as JSON string
            Log.INFO(f"Data successfully saved to Redis.")
        except redis.RedisError as e:
            Log.ERRPR(f"Redis error: {e}")
    
    @staticmethod
    def retrieve_all_jnd_scribe_from_redis(redis_host='localhost', redis_port=6379, redis_db=0):
        # Connect to Redis
        r = redis.Redis(host=redis_host, port=redis_port, db=redis_db)
        
        # Initialize an empty dictionary to store the data
        data_dict = {}
        
        # Use the scan method to get all keys
        cursor = '0'
        keys = []
        while cursor != 0:
            cursor, batch_keys = r.scan(cursor=cursor, match='*', count=1000)
            keys.extend(batch_keys)
        
        # Use MGET to get all values at once
        values = r.mget(keys)
        
        # Store the retrieved values in the dictionary
        for key, value in zip(keys, values):
            try:
                # Attempt to decode the value as JSON
                data_dict[key.decode('utf-8')] = json.loads(value)
            except json.JSONDecodeError:
                # If value is not JSON, store it as a string
                data_dict[key.decode('utf-8')] = value.decode('utf-8')
        
        return data_dict

    @staticmethod
    def save_non_existent_keys(data):
        # Connect to Redis
        r = redis.Redis(host='localhost', port=6379, db=0)
        
        # Prepare the data for MSETNX
        flat_data = []
        for key, value in data.items():
            flat_data.extend([key, value])
        
        # Use MSETNX to set the keys if none of them exist
        result = r.msetnx(*flat_data)
        
        if result:
            Log.INFO("All keys were set successfully.")
        else:
            Log.INFO("Some keys already exist, none were set.")

