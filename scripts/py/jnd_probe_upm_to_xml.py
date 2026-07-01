#!/usr/bin/env python3.12

"""
SYNOPSIS

DESCRIPTION
    This script will wrap UPM java translator to translate UPM file.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
   

LICENSE
    (C) onsemi 2025 All rights reserved.
"""

import os
import sys
import subprocess
import gzip
import shutil
import subprocess
import os
import re
from lib.Log import Log
from lib.Util import Util



#------------------------------------------------------------------------------

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
    outbox = params['out'] 
    db_location = params['refdb']   
    
    input_file_gz = params['infile']
    input_file = input_file_gz[:-3] if input_file_gz.endswith('.gz') else input_file_gz
    
    cfg_java = yaml_data['UPM']['CFG_JAVA']
    translated_staging = yaml_data['UPM']['translated_staging']
    cfg_upm_to_xml = yaml_data['UPM']['CFG_UPM_TO_XML']
    user = yaml_data['UPM']['refdb'][db_location]['user']
    password = yaml_data['UPM']['refdb'][db_location]['password']
    port = yaml_data['UPM']['refdb'][db_location]['port']
    sid = yaml_data['UPM']['refdb'][db_location]['sid']
    server_name = yaml_data['UPM']['refdb'][db_location]['server_name']
    pr_list = yaml_data['UPM']['pr_list']
    db_schema = "REFDB"
    
    if input_file_gz.endswith('.gz'):
        try:
            temp_input_file = input_file + ".tmp"
            with gzip.open(input_file_gz, 'rb') as f_in:
                with open(temp_input_file, 'wb') as f_out:
                    shutil.copyfileobj(f_in, f_out)
                    f_out.flush()
                    os.fsync(f_out.fileno())
            os.replace(temp_input_file, input_file)
        except Exception as e:
            if os.path.exists(input_file + ".tmp"):
                os.remove(input_file + ".tmp")
            Log.ERROR(f"Failed to decompress file: {e}")
            Util.dp_exit(1, f"Failed to decompress file: {e}")
       
    Log.INFO("Starting JND UPM datalog to XML processing")
    Log.INFO(f"Java Path: {cfg_java}")
    Log.INFO(f"JND UPM to XML jar lib path: {cfg_upm_to_xml}")
    
    # Check if paths exist before logging
    if not os.path.isfile(cfg_java):
        Log.ERROR(f"Java Path does not exist: {cfg_java}")

    if not os.path.isfile(cfg_upm_to_xml):
        Log.ERROR(f"JND UPM to XML Path does not exist: {cfg_upm_to_xml}")
        Util.dp_exit(1, f"JND UPM to XML Path does not exist: {cfg_upm_to_xml}")
   
    Log.INFO(f"Input file={input_file}")
    Log.INFO(f'Outbox={translated_staging}')
    
    # Convert pr_list to a comma-separated string
    pr_list_str = ','.join(pr_list)
    
    # Run the Java command to convert the datalog to XML
    cmd = [
        cfg_java, '-jar', cfg_upm_to_xml, '-data',
        input_file, '-o', translated_staging, '-u', user, '-p', password, '-pn', port,
        '-sn', server_name, '-sd', sid, '-dsn', db_schema, '-prList', pr_list_str
    ]
    
    if input_file:
        Log.INFO(f"To start translating UPM .map file to xml.")
        Log.INFO(f"executing command => {cmd}")
        try:
            process = subprocess.run(cmd, check=True, capture_output=True, text=True, cwd=os.path.dirname(cfg_upm_to_xml))
            
            Log.INFO(f"stdout: {process.stdout}")
            # Log.ERROR(f"stderr: {process.stderr}")
            Log.INFO(f"Finished translating file: {input_file}")
        except subprocess.CalledProcessError as e:
            Log.ERROR(f"Java command failed: {e}")
            Log.ERROR(f"stdout: {e.stdout}")
            Log.ERROR(f"stderr: {e.stderr}")
        except Exception as e:
            Log.ERROR(f"Error translating file {input_file}: {e}")
            Util.dp_exit(1, f"Error translating file {input_file}: {e}")
        
        if process.returncode == 0:
            Log.INFO(f"Successful translation to xml of upm file={input_file}")
        else:
            Log.INFO(f"stdout: {process.stdout}")
            Log.ERROR(f"stderr: {process.stderr}") 
            Log.ERROR(f"Error translating file {input_file}: {e}")
            Util.dp_exit(1,"stdout: {process.stdout}")
    else:
        Log.INFO(f"No UPM .map file to be translated to xml..")

    Util.dp_exit(0)

if __name__ == "__main__":
    main() 