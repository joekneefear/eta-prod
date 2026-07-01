"""
SYNOPSIS

DESCRIPTION
    Utility 

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2023-Sep-06 - jgarcia - initial
    2023-Sep-16 - jgarcia - added process_command_line_args
    2025-Mar-11 - jgarcia - added pplogger arg in dp_exit method

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
import tempfile
import pandas as pd
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
from lib.WS.RefdbAPIClient import RefdbAPIClient
import pybreaker
from lib.PPLogger import PPLogger


class Util:
    
    GLOBAL_TEMP_FOLDER = None
    # pplogger = None  # Initialize PPLogger
    
    @staticmethod
    def dp_exit(code=0, pplogger=None, error=None, warn=None, temp_folder=None):
        # Robustly handle case where error message is passed as second positional argument
        if isinstance(pplogger, str) and error is None:
            error = pplogger
            pplogger = None

        temp_folders = []
        error_list = []
        warn_list = []
        out_file = "err.jnk"
        trace = "\n".join(traceback.format_stack())
        

        if error:
            if isinstance(error, list):
                error_list.extend(error)
            else:
                error_list.append(error)
            error_list.append("Stack Trace:\n" + trace)

        if warn:
            if isinstance(warn, list):
                warn_list.extend(warn)
            else:
                warn_list.append(warn)

        err_count = len(error_list)
        warn_count = len(warn_list)

        try:
            with open(out_file, "w") as outfile:
                outfile.write(f"{err_count}\t{warn_count}\n")
                for msg in error_list:
                    outfile.write(f"1\t9001\tE\t0\t0\t{msg}\n")
                    if pplogger:
                        # Truncate message to avoid ORA-12899 (max 2000 chars)
                        safe_msg = msg[:2000] if msg else msg
                        pplogger.set_log_msg(safe_msg)
                    Log.ERROR(f"ERROR: {msg}")
                for msg in warn_list:
                    outfile.write(f"1\t9002\tW\t0\t0\t{msg}\n")
                    if pplogger:
                        # Truncate message to avoid ORA-12899 (max 2000 chars)
                        safe_msg = msg[:2000] if msg else msg
                        pplogger.set_log_msg(safe_msg)
                    Log.WARN(f"WARNING: {msg}")
        except Exception as e:
            Log.ERROR(f"Failed to write to {out_file}: {e}")

        temp_folder = temp_folder or Util.GLOBAL_TEMP_FOLDER

        if temp_folder and os.path.exists(temp_folder):
            try:
                shutil.rmtree(temp_folder)
                Log.INFO(f"Deleted temporary folder: {temp_folder}")
            except Exception as e:
                Log.ERROR(f"Failed to delete {temp_folder}: {e}")

        if pplogger and pplogger.set_to_be_logged:
            pplogger.pp_log_exit(code)

        Log.INFO(f"###### End {sys.argv[0]} script (code = {code}) ######")
        sys.exit(code if code not in [10, 100] else 0 if code == 100 else 10)

    @staticmethod
    def process_command_line_args(arguments):
        args_dict = {}
        if not arguments:
            return args_dict
            
        # The first argument is typically the input file
        in_file = arguments.pop(0)
        args_dict['infile'] = in_file
        
        i = 0
        while i < len(arguments):
            arg = arguments[i]
            if arg.startswith("--"):
                if "=" in arg:
                    # Handle --key=value
                    parts = arg.split("=", 1)
                    key = parts[0].replace("--", "")
                    args_dict[key] = parts[1]
                else:
                    # Handle --key value OR --key (flag only)
                    key = arg.replace("--", "")
                    # Look ahead to see if next arg is a value or another flag
                    if i + 1 < len(arguments) and not arguments[i+1].startswith("--"):
                        args_dict[key] = arguments[i+1]
                        i += 1  # Consume the value argument
                    else:
                        args_dict[key] = True
            i += 1
        return args_dict
    
    @staticmethod
    def rename_file(old_name, new_name):
        try:
            os.rename(old_name, new_name)
            Log.INFO(f"File renamed from {old_name} to {new_name} successfully.")
        except FileNotFoundError:
            Log.INFO(f"The file {old_name} was not found.")
        except Exception as e:
            Log.ERROR(f"An error occurred: {e}")
            Util.dp_exit(1,"An error occured during renaming of filename.")
    
    @staticmethod
    def is_gzip(file_path):
        mime = magic.Magic()
        file_type = mime.from_file(file_path)
        return 'gzip' in file_type
    
    @staticmethod
    def is_gzipped(file_path):
        """Check if the file is already compressed with gzip."""
        if os.path.isfile(file_path):
            with open(file_path, 'rb') as f:
                return f.read(2) == b'\x1f\x8b'  # Gzip magic number
        return False
   
    # Define a function to replace multiple spaces with a single space
    def clean_spaces(text):
        return ' '.join(text.split())

    @staticmethod
    def looks_like_number(value):
        return value.isnumeric()

    @staticmethod
    def rep_na(data):
        if not data.strip() or re.search(r'^\s*$', data) or re.search(r'null|undef', data, re.IGNORECASE):
            return 'NA'
        return data.strip()

    @staticmethod
    def current_date():
        return datetime.now().strftime("%Y%m%d_%H:%M:%S")
    
    @staticmethod
    def get_logging_time():
        now = datetime.now()
        compressed_timestamp = now.strftime("%Y%m%d%H%M%S")
        return compressed_timestamp
   
    @staticmethod
    def format_unixtime(unixtime, tz):
        if tz is not None:
            from pytz import timezone
            tz_obj = timezone(tz)
            new_date = datetime.fromtimestamp(unixtime, tz=tz_obj).strftime("%Y/%m/%d %H:%M:%S %Z")
        else:
            new_date = datetime.fromtimestamp(unixtime).strftime("%Y/%m/%d %H:%M:%S UTC")

        Log.INFO(f"input format is unixtime. {unixtime} -> {new_date}")
        return new_date

    @staticmethod
    def format_month_day_year(month_str, day, year, hour, minute, second):
        months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        month = months.index(month_str[:3].capitalize()) + 1
        new_date = f"{year}/{str(month).zfill(2)}/{str(day).zfill(2)} {str(hour).zfill(2)}:{str(minute).zfill(2)}:{str(second).zfill(2)}"
        Log.INFO(f"input format is MMM DD YYYY. {month_str} {day} {year} -> {new_date}")
        return new_date
    
    @staticmethod
    def format_day_month_year(day, month_str, year, hour, minute, second):
        months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        month = months.index(month_str[:3].capitalize()) + 1
        year = int(year)
        if year < 100:
            year += 2000
        new_date = f"{year}/{str(month).zfill(2)}/{str(day).zfill(2)} {str(hour).zfill(2)}:{str(minute).zfill(2)}:{str(second).zfill(2)}"
        Log.INFO(f"input format is DD-MMM-YY or DD-MMM-YYYY. {day} {month_str} {year} -> {new_date}")
        return new_date
    
    @staticmethod
    def format_day_month_year_long(day, month_str, year):
        months = list(month_abbr)
        month = months.index(month_str[:3].capitalize())
        year = int(year)
        if year < 100:
            year += 2000
        new_date = f"{year}/{str(month).zfill(2)}/{str(day).zfill(2)}"
        Log.INFO(f"input format is DD-MMM-YYYY. {day} {month_str} {year} -> {new_date}")
        return new_date
    
    @staticmethod
    def format_month_day_year_short(month_str, day):
        months = list(month_abbr)
        month = months.index(month_str[:3].capitalize())
        new_date = f"{datetime.now().year}/{str(month).zfill(2)}/{str(day).zfill(2)}"
        Log.INFO(f"input format is MMM-DD. {month_str} {day} -> {new_date}")
        return new_date
    
    @staticmethod
    def format_year_month_day(year, month, day):
        new_date = f"{year}/{str(month).zfill(2)}/{str(day).zfill(2)}"
        Log.INFO(f"input format is YYYY-MM-DD. {year} {month} {day} -> {new_date}")
        return new_date
    
    @staticmethod
    def format_month_day_year_numeric(month, day, year):
        new_date = f"{str(year)}/{str(month).zfill(2)}/{str(day).zfill(2)}"
        Log.INFO(f"input format is M/D/YYYY. {month} {day} {year} -> {new_date}")
        return new_date
    
    @staticmethod   
    def format_date(year, month, day, hour, minute, second):
        return f"{year}/{str(month).zfill(2)}/{str(day).zfill(2)} {str(hour).zfill(2)}:{str(minute).zfill(2)}:{str(second).zfill(2)}"
    
    @staticmethod
    def format_date_to_yyyymmdd(date, tz=None):
        if date is None:
            Log.INFO("WARN: date value is undefined")
            return None

        patterns = [
            (r"(\d{2})/(\d{2})/(\d{4})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})", lambda m: (m.group(3), m.group(2), m.group(1), m.group(4), m.group(5), m.group(6))),
            (r"(\d{4})\D(\d{1,2})\D(\d{1,2})\D+(\d{1,2})\D(\d{1,2})\D(\d{1,2})", lambda m: (m.group(1), m.group(2), m.group(3), m.group(4), m.group(5), m.group(6))),
            (r"(\d{1,2})\D(\d{1,2})\D(\d{4})\D+(\d{1,2})\D(\d{1,2})\D(\d{1,2})", lambda m: (m.group(3), m.group(1), m.group(2), m.group(4), m.group(5), m.group(6))),
            (r"^\d{10}$|^\d{9}$", lambda m: Util.format_unixtime(int(m.group(0)), tz)),
            (r"(\w+)\s+(\d{1,2})\D+(\d{4})\D+(\d{1,2})\D(\d{1,2})\D(\d{1,2})", lambda m: Util.format_month_day_year(m.group(1), m.group(2), m.group(3), m.group(4), m.group(5), m.group(6))),
            (r"(\d{1,2})\D(\w{3})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})", lambda m: Util.format_day_month_year(m.group(1), m.group(2), m.group(3), m.group(4), m.group(5), m.group(6))),
            (r"(\d{1,2})\D(\w{3})\D(\d{4})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})", lambda m: Util.format_day_month_year(m.group(1), m.group(2), m.group(3), m.group(4), m.group(5), m.group(6))),
            (r"(\d{1,2})\D(\w{3})\D(\d{1,2})", lambda m: Util.format_day_month_year(m.group(1), m.group(2), datetime.now().year, "00", "00", "00")),
            (r"(\d{4})\D(\d{1,2})\D(\d{1,2})", lambda m: (m.group(1), m.group(2), m.group(3))),
            (r"(\d{1,2})\D(\d{1,2})\D(\d{4})", lambda m: (m.group(3), m.group(1), m.group(2))),
            (r"(\d{8})", lambda m: (m.group(0)[:4], m.group(0)[4:6], m.group(0)[6:], "00", "00", "00"))  # Handle YYYYMMDD format
        ]

        for pattern, formatter in patterns:
            match = re.match(pattern, date)
            if match:
                formatted_date = Util.format_date(*formatter(match))
                return formatted_date[:4] + formatted_date[5:7] + formatted_date[8:10]  # Convert to YYYYMMDD

        if date == 'NA':
            Log.WARN("WARN: date value is NA")
        else:
            Log.WARN(f"Invalid date: {date}")

        return None
    
    @staticmethod
    def format_date_to_yyyymmdd_hms(date_str):
        if date_str:
            try:
                return datetime.strptime(date_str, '%Y-%m-%d').strftime('%Y/%m/%d %H:%M:%S')
            except ValueError:
                return date_str
        return None
    
    @staticmethod
    def convert_date_format_to_yyyymmdd_hms(date_str):
        # Parse the input date string to a datetime object
        date_obj = parser.parse(date_str)
        # Define the output format
        output_format = "%Y/%m/%d %H:%M:%S"
        # Format the datetime object to the desired output format
        formatted_date = date_obj.strftime(output_format)
        return formatted_date
   
    @staticmethod
    def parse_date(s):
        match = re.match(r"^\s*(\d{1,4})\W*0*(\d{1,2})\W*0*(\d{1,2})\W*0*(\d{0,2})\W*0*(\d{0,2})\W*0*(\d{0,2})", s)
        if match:
            year, month, day, hour, minute, second = map(int, match.groups())
            hour = hour if hour else 0
            minute = minute if minute else 0
            second = second if second else 0

            if year < 100:
                year = 2000 + year if year < 70 else 1900 + year

            return timegm((year, month, day, hour, minute, second))
        
        return -1

    @staticmethod
    def validate_out_dir(hOptions):
        outdir = hOptions.get('out')
        
        if outdir is not None:
            if not os.path.exists(outdir) or not os.path.isdir(outdir):
                Util.exit(1, f"Output directory does not exist {outdir}")

            if hOptions.get('meta') is not None and not os.path.exists(outdir + "_noMeta"):
                os.mkdir(outdir + "_noMeta")

            if hOptions.get('wmap') is not None and not os.path.exists(outdir + "_noWMap"):
                os.mkdir(outdir + "_noWMap")
                
    @staticmethod
    def formatSourceLot(sl, l):
        sourceLot = ""
        
        if sl and sl not in {"NA", "N/A"}:
            sourceLot = sl if sl.endswith(".S") else f"{sl}.S"
        else:
            if not l:
                Log.INFO("NO LotID provided.")
                sourceLot = "NA"
            else:
                sourceLot = l if l.endswith(".S") else f"{l}.S"
        
        Log.INFO(f"Formatted Source Lot=>>{sourceLot}<<||ORIG Source Lot = {sl}")
        return sourceLot

    
    @staticmethod
    def enclose_field_with_double_quotes(field):
        return '"' + field + '"'
    
    @staticmethod
    def convert_line_endings(file_path):
        try:
            subprocess.run(["dos2unix", file_path], check=True)
            Log.INFO(f"Line endings in {file_path} successfully converted to UNIX format.")
        except subprocess.CalledProcessError as e:
            Log.ERROR(f"Error converting line endings: {e}")
            Util.dp_exit(1,"Execption occured trying to issue subprocess dos2unix")
            
    @staticmethod
    def load_yaml(yaml_file):
        with open(yaml_file, 'r') as file:
            data = yaml.safe_load(file)
        return data

    @staticmethod
    def get_xml_sanitizer_config(yaml_data, section_name):
        global_config = yaml_data.get('xml_sanitizer', {})
        section_config = yaml_data.get(section_name, {}).get('xml_sanitizer', {})

        merged_config = {}
        if isinstance(global_config, dict):
            merged_config.update(global_config)
        if isinstance(section_config, dict):
            merged_config.update(section_config)
        return merged_config
        
    @staticmethod
    def is_logfile_active(logfile, minutes):
        try:
            # Get the current time
            current_time = time.time()

            # Get the last modification time of the file
            last_mod_time = os.path.getmtime(logfile)

            # Calculate the time difference in seconds
            time_diff = current_time - last_mod_time

            # Convert minutes to seconds
            time_interval = minutes * 60

            # Check if the file has been modified within the specified time interval
            if time_diff <= time_interval:
                Log.INFO(f"Log file '{logfile}' is actively being written to.")
                return True
            else:
                Log.INFO(f"Log file '{logfile}' has not been written to in the past {minutes} minutes.")
                return False

        except Exception as e:
            Log.ERROR(f"Error: {str(e)}")
            return False
   
    @staticmethod    
    def oldest_file_in_tree(rootfolder, extension):
        try:
            matching_files = []
            oldest_file = None

            if extension in ['%', 'na', 'NA']:
                # Get a list of all files in the root folder
                matching_files = [os.path.join(rootfolder, filename) for filename in os.listdir(rootfolder) if os.path.isfile(os.path.join(rootfolder, filename))]
            else:
                # Get files with the specified extension in the root folder
                matching_files = [os.path.join(rootfolder, filename) for filename in os.listdir(rootfolder) if os.path.isfile(os.path.join(rootfolder, filename)) and filename.endswith(extension)]

            if matching_files:
                oldest_file = min(matching_files, key=os.path.getmtime)
                # Log.INFO(f"Oldest file found: {oldest_file}")
            else:
                # Log.INFO("No matching files found.")
                return ""

            return oldest_file
        except Exception as e:
            return f"Error: {str(e)}"
    
    @staticmethod
    def count_files_in_folder(rootfolder, extension):
        try:
            # Normalize the path and check if the directory exists
            rootfolder = os.path.abspath(rootfolder)
            if not os.path.isdir(rootfolder):
                Log.INFO(f"Error: The specified path '{rootfolder}' is not a directory or does not exist.")
                return 0

            # List all files in the root folder
            all_files = [filename for filename in os.listdir(rootfolder) if os.path.isfile(os.path.join(rootfolder, filename))]

            # Handle special cases for extension
            if extension in ['%', 'na', 'NA']:
                # Count all files if the extension is in special cases
                matching_files = all_files
            else:
                # Prepend a dot to the extension if not already present
                if not extension.startswith('.'):
                    extension = f".{extension}"
                # Count files with the specified extension
                matching_files = [filename for filename in all_files if filename.endswith(extension)]

            file_count = len(matching_files)
            Log.INFO(f"Number of files with extension '{extension}' in folder '{rootfolder}': {file_count}")

            return file_count

        except Exception as e:
            file_count = 0
            Log.ERROR(f"Error: {str(e)}")
            Log.INFO(f"Number of files with extension '{extension}' in folder '{rootfolder}': {file_count}")
            return file_count
    
    @staticmethod    
    def send_mail(sender, recipient, body, subject):
        # Set sender, receiver, and cc emails
        sender_email = sender
        receiver_emails = [recipient]
        body_content = body
        subject_content = subject

        # Create MINE message
        mail_msg = MIMEMultipart('alternative')
        mail_msg['Subject'] = subject_content 
        mail_msg['From'] = sender_email
        mail_msg['To'] = recipient

        part1 = MIMEText(body_content, 'html')
        mail_msg.attach(part1)

        # Send email  
        with smtplib.SMTP(smtp_server) as server:
            server.sendmail(sender_email, receiver_emails, mail_msg.as_string())
    
    @staticmethod        
    def get_pid_from_file(pid_file):
        """
        Read the PID from the given file.
        
        Args:
            pid_file (str): Path to the PID file.
            
        Returns:
            int or None: The PID if read successfully, None otherwise.
        """
        try:
            with open(pid_file, 'r') as f:
                pid = int(f.readline().strip())
                return pid
        except FileNotFoundError:
            return None
        except (ValueError, TypeError):
            return None

    @staticmethod
    def is_pid_running(pid):
        """
        Check if a process with the given PID is running.
        
        Args:
            pid (int): The PID to check.
            
        Returns:
            bool: True if the process is running, False otherwise.
        """
        if pid is None:
            return False

        try:
            # psutil provides a cross-platform way to check if a process is running
            p = psutil.Process(pid)
            return p.is_running() and p.status() != psutil.STATUS_ZOMBIE
        except psutil.NoSuchProcess:
            return False
    
    @staticmethod    
    def check_file_exists(file_path: str) -> bool:
        """
        Check if a file exists at the given path.

        Args:
        file_path (str): The path to the file.

        Returns:
        bool: True if the file exists, False otherwise.
        """
        try:
            path = Path(file_path)
            return path.exists()
        except Exception as e:
            Log.ERROR(f"An error occurred: {e}")
            return False

    @staticmethod
    def is_csv_file(file_path: str) -> bool:
        """
        Check if a file is a CSV not just by file extension but by content.

        Args:
            file_path (str): The path to the file.

        Returns:
            bool: True if the file is a CSV, False otherwise.
        """
        if not Path(file_path).exists():
            return False

        try:
            with open(file_path, 'r', newline='') as file:
                # Try reading the file with csv.reader
                csv.Sniffer().sniff(file.read(1024))
                file.seek(0)
                reader = csv.reader(file)
                for row in reader:
                    # If we can read at least one row, it's likely a CSV
                    return True
        except (csv.Error, UnicodeDecodeError):
            return False

        return False

    @staticmethod
    def debug_print(*args,**kwargs):
        Log.INFO(*args,**kwargs)
    
    @staticmethod
    def identify_klarf_version(filename, debug=False):
        try:
            with open(filename, 'rb') as f:
                # Check if it's a gzip file
                if filename.lower().endswith('.gz'):
                    with gzip.open(f, 'rt') as gzipped_file:
                        lines = gzipped_file.readlines()
                # Check if it's a zip file
                elif filename.lower().endswith('.zip'):
                    with zipfile.ZipFile(f, 'r') as zipped_file:
                        # Assuming there's only one file in the zip
                        inner_filename = zipped_file.namelist()[0]
                        with zipped_file.open(inner_filename, 'r') as inner_file:
                            lines = inner_file.readlines()
                else:
                    raise ValueError("Unsupported file format. Only .gz and .zip files are supported.")
                
                for line in lines:
                    if "FileRecord" in line:
                        line = line.strip()
                        elements = line.split(" ")
                        version = elements[-1].replace('"', '')
                        break
                    elif "FileVersion" in line:
                        line = line.strip().split(";")[0]
                        elements = line.split(" ")
                        version = ".".join(elements[-2:])
                        break
                else:
                    raise ValueError("Could not identify version from file.")
                
                if debug:
                    Log.INFO("version =", version)
                
                return version
        except Exception as e:
            raise ValueError(f"Error processing file: {str(e)}")

    @staticmethod
    def is_numeric(s):
        try:
            float(s)
            return True
        except ValueError:
            return False
        

    # # Helper functions
    @staticmethod
    def rep_na(value):
        return "NA" if value in [None, "", "N/A", "NA"] else value
    
    @staticmethod
    def trim(value):
        return value.strip()

    @staticmethod
    def clean_temp_directory(temp):
        try:
            for file in os.listdir(temp):
                file_path = os.path.join(temp, file)
                if os.path.isfile(file_path):
                    os.unlink(file_path)
                elif os.path.isdir(file_path):
                    shutil.rmtree(file_path)
            Log.INFO(f"Successfully cleaned up unzip temp folder: {temp}")
        except Exception as e:
            Log.ERROR(f"Can't do clean up on unzip temp folder: {e}")
            raise SystemExit("rm command not successful")
    
   
    @staticmethod
    def find_file(filename, folder):
        try:
            for entry in os.scandir(folder):
                if entry.is_file() and entry.name == filename:
                    return entry.path
                elif entry.is_dir():
                    result = Util.find_file(filename, entry.path)
                    if result:
                        return result
        except Exception as e:
            Log.ERROR(f"An error occurred: {e}")
        return None

    @staticmethod
    def get_specific_file(directory, pattern):
        # Compile the regular expression pattern for efficiency
        regex = re.compile(pattern)
        
        # Iterate through the directory and find the first matching file
        for filename in os.listdir(directory):
            if regex.match(filename):
                return os.path.join(directory, filename)
        return None
    @staticmethod
    def configure_ws_urls(ws_source, ws_url_ref_data):
        ws_source = ws_source.lower()
        if ws_source not in ['qa', 'prod']:
            Log.ERROR(f"Invalid ws_source: {ws_source}")
            Util.dp_exit(1, f"Invalid ws_source: {ws_source}")

        return {
            'onlot': ws_url_ref_data['refdb'][ws_source].get('on_lot'),
            'onlotprod': ws_url_ref_data['refdb'][ws_source].get('on_lot_prod'),
            'onscribe': ws_url_ref_data['refdb'][ws_source].get('on_scribe'),
            'onprod': ws_url_ref_data['refdb'][ws_source].get('on_prod'),
            'pplot': ws_url_ref_data['refdb'][ws_source].get('pp_lot'),
        }
  
    @staticmethod
    def replace_dict_value(d, key, new_value):
        if key in d:
            d[key] = new_value
        for k, v in d.items():
            if isinstance(v, dict):
                Util.replace_dict_value(v, key, new_value)
        return d
    
    @staticmethod
    def format_wafer_number(wafer_number):
        """
        Formats the wafer number by zero-padding it if it is greater than 10.
        
        Args:
            wafer_number (str): The wafer number as a string.
            
        Returns:
            str: The formatted wafer number.
        """
        if wafer_number in ['NA', '', ' ']:
            return wafer_number
        return wafer_number.zfill(2) if int(wafer_number) < 10 else wafer_number
    
    @staticmethod
    def update_wafer_id(onscribe_ws_metadata, source_lot, wafer_number):
        """
        Update the waferId and waferIdSource fields in the onscribe_ws_metadata dictionary
        if waferIdSource is 'CALCULATED'.

        Args:
        onscribe_ws_metadata (dict): The metadata dictionary to update.
        source_lot (str): The source lot value.
        wafer_number (str): The wafer number value.

        Returns:
        dict: The updated metadata dictionary.
        """
        # Check if onscribe_ws_metadata is None
        if not isinstance(onscribe_ws_metadata, dict):
            Log.ERROR("onscribe_ws_metadata should be a dictionary.")
            # return None  # or handle the error as needed
            Util.dp_exit(1, "onscribe_ws_metadata shoud be a dictionary with default values")

        # Remove '.S' at the end of source_lot if it exists
        if source_lot.endswith('.S'):
            source_lot = source_lot[:-2]
            
        # Ensure wafer_number is always in two-digit format
        # if int(wafer_number) < 10:
        #     wafer_number = str(wafer_number).zfill(2)
        wafer_number = Util.format_wafer_number(wafer_number)
        
        status_value = onscribe_ws_metadata.get('status', 'Key does not exist')
        # if onscribe_ws_metadata.get('waferIdSource').upper() == 'CALCULATED' and onscribe_ws_metadata.get('status', '').upper() != 'MANUAL':
        if isinstance(onscribe_ws_metadata, dict) and status_value.upper() != 'MANUAL':
            onscribe_ws_metadata['waferId'] = f"{source_lot}-{wafer_number}"
            onscribe_ws_metadata['waferIdSource'] = 'SCRIPT_FORMATTED_SOURCELOT-WAFERNUMBER'
        
        return onscribe_ws_metadata
    
    @staticmethod
    def is_lock_active(lock_path, timeout=1):
        lock = FileLock(lock_path, timeout=timeout)
        try:
            with lock:
                # If we acquire the lock, it means no other process is holding it
                return False
        except Timeout:
            # If we get a Timeout exception, it means the lock is active
            return True
       
    @staticmethod
    def add_source_to_data(data, onlot_sources=None, onprod_sources=None, onscribe_sources=None, stdml_sources=None, constant_sources=None, wmc_sources=None):
        # Initialize the new data structure with sources
        processed_data = {
            "onLot": {},
            "onlotprod": {},
            "onProd": {},
            "onScribe": {},
            "stdml": {}, 
            "wmc": {}    
        }
        
        # Process onLot data
        if "onLot" in data:
            for key, value in data["onLot"].items():
                source = onlot_sources.get(key, "ONLOT") if onlot_sources else "ONLOT"  # Default to "ONLOT"
                processed_data["onLot"][key] = {
                    "value": value,
                    "source": source  # Use user-specified source or default
                }
        
        # Process onProd data
        if "onProd" in data:
            for key, value in data["onProd"].items():
                source = onprod_sources.get(key, "ONPROD") if onprod_sources else "ONPROD"  # Default to "ONPROD"
                processed_data["onProd"][key] = {
                    "value": value,
                    "source": source  # Use user-specified source or default
                }
        
        return processed_data
        
    @staticmethod    
    def gzip_file(file_path):
        # Guard 1: source file is already gzip data (magic bytes check)
        if Util.is_gzipped(file_path):
            Log.INFO(f"File is already gzip-compressed, skipping: {file_path}")
            return
        final_gz = file_path + '.gz'
        # Guard 2: output .gz already exists from a previous successful run
        if os.path.exists(final_gz):
            Log.INFO(f"Compressed output already exists, skipping: {final_gz}")
            return
        final_dir = os.path.dirname(final_gz) or '.'
        fd, temp_gz = tempfile.mkstemp(prefix='.tmp_', suffix='.gz.tmp', dir=final_dir)
        os.close(fd)
        try:
            with open(file_path, 'rb') as f_in:
                with open(temp_gz, 'wb') as raw_out:
                    # filename='' prevents the temp path from being embedded in the gzip header;
                    # decompressors (incl. Windows) then use the .gz file's own name as the output.
                    with gzip.GzipFile(filename='', mode='wb', fileobj=raw_out) as f_out:
                        shutil.copyfileobj(f_in, f_out)
            # fsync AFTER the gzip file is fully closed so the footer (checksum+size) is flushed
            with open(temp_gz, 'rb') as f_sync:
                os.fsync(f_sync.fileno())
            os.replace(temp_gz, final_gz)
            temp_gz = None
            os.remove(file_path)
            Log.INFO(f"Successfully gzipped the file: {file_path}")
        except Exception as e:
            if temp_gz and os.path.exists(temp_gz):
                os.remove(temp_gz)
            Log.ERROR(f"Failed to gzip the file {file_path}: {e}")
            Util.dp_exit(1, f"Failed to gzip the file {file_path}: {e}")
            
    @staticmethod
    def unzip_file(infile, temp):
        Log.INFO(f"Unzipping {infile} to {temp}")
        try:
            with zipfile.ZipFile(infile, 'r') as zip_ref:
                zip_ref.extractall(temp)
        except zipfile.BadZipFile:
            Log.ERROR("Unzip process is not successful")
            raise SystemExit(f"Unable to unzip file: {infile}")

    
    @staticmethod
    def check_file_exists(filepath):
        # Use pathlib to check if the file exists
        return Path(filepath).is_file()
    
    @staticmethod
    def get_on_lot_prod_metadata(url, client, ws_timeout, default_onlot_prod):
        """Retrieve metadata from the given URL using the provided client."""
        
        Log.DEBUG(f"URL: {url}, Timeout: {ws_timeout}, Default Metadata: {default_onlot_prod}")
        
        # Check if the circuit breaker is open
        if client.circuit_breaker.current_state == pybreaker.STATE_OPEN:
            Log.ERROR("Circuit breaker is open")
            return default_onlot_prod
        
        try:
            metadata = client.get_metadata(url, default_onlot_prod, timeout=ws_timeout)
            Log.DEBUG(f"Metadata retrieved: {metadata}")
            return metadata
        except Exception as e:
            Log.ERROR(f"Failed to get metadata from {url}: {e}", exc_info=True)
            return default_onlot_prod
    
    @staticmethod
    def get_column_count_csv(csv_file):
        try:
            with open(csv_file, 'r') as file:
                csv_reader = csv.reader(file)
                first_row = next(csv_reader, None)
                if first_row is None:
                    raise ValueError("The CSV file is empty.")
                    Util.dp_exit(1,"The CSV file is empty")
                return len(first_row)
        except FileNotFoundError:
            Log.ERROR(f"Error: The file '{csv_file}' was not found.")
            Util.dp_exit(1,f"Error: The file '{csv_file}' was not found.")
        except ValueError as ve:
            Log.ERROR(f"Error: {ve}")
            Util.dp_exit(1,f"Error: {ve}")
        except csv.Error as e:
            Log.ERROR(f"Error reading CSV file: {e}")
            Util.dp_exit(1,f"Error reading CSV file: {e}")
        except Exception as e:
            Log.ERROR(f"An unexpected error occurred: {e}")
            Util.dp_exit(1,f"An unexpected error occurred: {e}")

