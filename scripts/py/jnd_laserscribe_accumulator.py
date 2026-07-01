#!/usr/bin/env python3.12

"""

SYNOPSIS

DESCRIPTION
    JND Scribe and Ship Scribe into into file

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Dec-03 - jgarcia - initial

LICENSE
    (C) onsemi 2024 All rights reserved.
"""

import csv
import sys
import os
import re
import subprocess
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
from lib.Log import Log
from lib.Util import Util
from lib.Utility.JndUtil import JndUtil
from pathlib import Path

def initialize_log_file():
    script_name = os.path.basename(sys.argv[0])  # get the script filename
    log_file_name = os.path.splitext(script_name)[0] + '.log'  # remove extension and add .log

    log_dir = os.environ.get('DPLOG', '/export/home/dpower/project/log')  # get DPLOG environment variable, with a default
    log_file = os.path.join(log_dir, log_file_name)  # join directory and filename

    log_args = ['--logfile', '--log_file', '--log']  # list of possible log file arguments
    for i, arg in enumerate(sys.argv):
        for log_arg in log_args:
            if arg.startswith(log_arg):
                if '=' in arg:
                    log_file = arg.split('=')[1]
                else:
                    log_file_index = i + 1
                    if log_file_index < len(sys.argv):
                        log_file = sys.argv[log_file_index]
                    else:
                        log_file = sys.argv[log_file_index - 1]
                break
    return log_file

def process_file(input_file, scribe_file, ship_scribe_file):
    column_count = Util.get_column_count_csv(input_file)
    
    if column_count is not None and column_count <= 3:
        JndUtil.load_jnd_scribe_ship_scribe_and_save_to_csv(input_file, scribe_file)
    elif column_count is not None:
        JndUtil.load_jnd_scribe_ship_scribe_and_save_to_csv(input_file, ship_scribe_file)
        
def decrypt_and_extract(infile, passphrase, scribe_file, ship_scribe_file):
    extracted_files = []
    
    if infile.lower().endswith('.gpg'):
        Log.INFO("Decrypting file...")
        dfile = infile[:-4]  # Remove .gpg extension
        
        # Construct the command as a single string
        command = f"gpg -v --batch --passphrase {passphrase} -o {dfile} -d {infile}"

        # Use subprocess.run with shell=True
        result = subprocess.run(command, shell=True, capture_output=True, text=True)
        
        # Log the output and error messages
        Log.INFO(f"Decryption stdout: {result.stdout}")
        Log.ERROR(f"Decryption stderr: {result.stderr}")
        
        if result.returncode != 0:
            Util.dp_exit(1, "Decryption failed.")
        
        if os.path.exists(dfile) and dfile.lower().endswith('.zip'):
            Log.INFO("Decrypted file successfully.")
            ext_dir = Path(dfile).parent
            try:
                with zipfile.ZipFile(dfile, 'r') as zip_ref:
                    zip_ref.extractall(ext_dir)
                    extracted_files.extend(zip_ref.namelist())
                Log.INFO(f"Extracted files to {ext_dir}")
                # Clean up the .zip file after extraction
                os.remove(dfile)
                Log.INFO(f"Deleted zip file: {dfile}")
            except zipfile.BadZipFile:
                Util.dp_exit(1, "Extracting file failed.")
    
    elif infile.lower().endswith('.zip'):
        ext_dir = Path(infile).parent
        try:
            with zipfile.ZipFile(infile, 'r') as zip_ref:
                zip_ref.extractall(ext_dir)
                extracted_files.extend(zip_ref.namelist())
            Log.INFO(f"Extracted files to {ext_dir}")
            # Clean up the .zip file after extraction
            os.remove(infile)
            Log.INFO(f"Deleted zip file: {infile}")
        except FileNotFoundError:
            Util.dp_exit(1, f"The file '{infile}' was not found.")
        except zipfile.BadZipFile:
            Util.dp_exit(1, "Extracting file failed.")
    
    elif infile.lower().endswith('.txt'):
        Log.INFO(f"Extracted file = {infile}")
        extracted_files.append(infile)

    # Process each extracted file that is not .zip or .gpg
    for extracted_file in extracted_files:
        if not extracted_file.lower().endswith(('.zip', '.gpg')):
            full_path = os.path.join(ext_dir if 'ext_dir' in locals() else '', extracted_file)
            try:
                process_file(full_path, scribe_file, ship_scribe_file)
                # Clean up the file after successful processing
                os.remove(full_path)
                Log.INFO(f"Deleted processed file: {full_path}")
            except Exception as e:
                Log.ERROR(f"Error processing file {full_path}: {e}")
                Util.dp_exit(1, f"Error processing file {full_path}: {e}")

def main():
    log_file = initialize_log_file()
    Log.configure_logger(log_file=log_file)
    
    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)
    
    if len(sys.argv) < 2:
        Log.INFO("No input file specified!!!")
        Util.dp_exit(1, "No input file specified!!!")
    
    yaml_file = params.get('config_file', '/export/home/dpower/project/scripts/py/resources/JND_CONFIG.yaml')
    yaml_data = Util.load_yaml(yaml_file)
    scribe_file = yaml_data['common_paths']['scribe']
    ship_scribe_file = yaml_data['common_paths']['ship_scribe']
    input_file = params['infile']
    Log.INFO(f"Input file={input_file}")
    password = "P\\@ssw0rd"
    decrypt_and_extract(input_file, password, scribe_file, ship_scribe_file)
    
        
    
    Util.dp_exit(0)

if __name__ == '__main__':
    main()