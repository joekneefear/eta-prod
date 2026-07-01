#!/usr/bin/env python3.12

import os
import sys
import subprocess
import argparse
import time
import gzip
# import logging
import re
import html
import xml.etree.ElementTree as ET
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


def normalize_xml_entities_atomic(file_path):
    temp_path = file_path + ".norm.tmp"
    try:
        with open(file_path, 'rb') as source_file:
            content = source_file.read()

        root = ET.fromstring(content)

        for element in root.iter():
            if element.text:
                element.text = html.unescape(element.text)
            if element.tail:
                element.tail = html.unescape(element.tail)
            if element.attrib:
                element.attrib = {key: html.unescape(value) for key, value in element.attrib.items()}

        normalized = ET.tostring(root, encoding='utf-8', xml_declaration=True)

        with open(temp_path, 'wb') as temp_file:
            temp_file.write(normalized)
            temp_file.flush()
            os.fsync(temp_file.fileno())

        os.replace(temp_path, file_path)
    except Exception:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        raise

def main():
    log_file = initialize_log_file()
    Log.configure_logger(log_file=log_file)
    
    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)
    
    if len(sys.argv) < 2:
        Log.INFO("No input file specified!!!")
        Util.dp_exit(1, "No input file specified!!!")
    
    yaml_file = params.get('config_file', '/export/home/dpower/project/scripts/py/resources/APTINA_CONFIG.yaml')
    yaml_data = Util.load_yaml(yaml_file)
    outbox = params['out']
    input_file = params['infile']  
    area=params['area']
    site=params['site']
    cfg_java = yaml_data[area][site]['CFG_JAVA']
    cfg_apt2xml = yaml_data[area][site]['CFG_APT2XML']
    bin_info = yaml_data[area][site]['CFG_BININFO']
    design_info = yaml_data[area][site]['CFG_DESIGNID']
    Log.INFO("Starting Aptina datalog to XML processing")
    Log.INFO(f"Java Path: {cfg_java}")
    Log.INFO(f"Aptina to XML Path: {cfg_apt2xml}")
    Log.INFO(f"Bin Info Path: {bin_info}")
    Log.INFO(f"Design ID Path: {design_info}")
    
    # Check if paths exist before logging
    if not os.path.isfile(cfg_java):
        Log.ERROR(f"Java Path does not exist: {cfg_java}")
        Util.dp_exit(1, f"Java Path does not exist: {cfg_java}")
    Log.INFO(f"Java Path: {cfg_java}")

    if not os.path.isfile(cfg_apt2xml):
        Log.ERROR(f"Aptina to XML Path does not exist: {cfg_apt2xml}")
        Util.dp_exit(1, f"Aptina to XML Path does not exist: {cfg_apt2xml}")
    Log.INFO(f"Aptina to XML Path: {cfg_apt2xml}")

    if not os.path.isfile(bin_info):
        Log.ERROR(f"Bin Info Path does not exist: {bin_info}")
        Util.dp_exit(1, f"Bin Info Path does not exist: {bin_info}")
    Log.INFO(f"Bin Info Path: {bin_info}")

    if not os.path.isfile(design_info):
        Log.ERROR(f"Design ID Path does not exist: {design_info}")
        Util.dp_exit(1, f"Design ID Path does not exist: {design_info}")
    Log.INFO(f"Design ID Path: {design_info}")

    
    Log.INFO(f"Input file={input_file}")
    Log.INFO(f'Outbox={outbox}')

    try:
        Log.INFO(f"Processing file: {input_file}")
        # input_file = os.path.join(WATCH_DIR, input_file)
        basenamefile = os.path.basename(input_file)
        # output_file = os.path.join(outbox, f"{os.path.splitext(basenamefile)[0]}.xml")
        basenamefile = basenamefile.replace('.gz', '', 1)
        output_file = os.path.join(outbox, f"{basenamefile}.xml")
        
        # Run the Java command to convert the datalog to XML
        cmd = [
            cfg_java, '-jar', cfg_apt2xml, 'fx', 
            input_file, output_file, 
            bin_info, design_info
        ]
        subprocess.run(cmd, check=True)
        
        normalize_xml_entities_atomic(output_file)
        
        # Gzip the output file
        Util.gzip_file(output_file)
        
        Log.INFO(f"Finished processing file: {input_file}")
    except subprocess.CalledProcessError as e:
        Log.ERROR(f"Java command failed: {e}")
        # Util.dp_exit(1,f"Java cmd Error processing file {input_file}: {e}")
    except Exception as e:
        Log.ERROR(f"Error processing file {input_file}: {e}")
        Util.dp_exit(1,"Error processing file {input_file}: {e}")

if __name__ == "__main__":
    main() 