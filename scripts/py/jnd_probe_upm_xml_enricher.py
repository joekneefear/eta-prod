#!/usr/bin/env python3.12

"""
SYNOPSIS

DESCRIPTION
    This script will enrich UPM translated UPM file.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
   2026-Mar-18 - jgarcia - added error handling to enrichment to log the error and return the original content with metadata only as a fallback instead of exiting the program, this is to prevent the entire enrichment process from failing due to an error in sxml enrichment, and to allow the rest of the metadata enrichment to still be applied and returned.

LICENSE
    (C) onsemi 2025 All rights reserved.
"""

import os
import sys
import subprocess
import argparse
import time
import gzip
# import logging
import re
from lib.Log import Log
from lib.Util import Util
from lib.Utility.JndUtil import JndUtil
from lib.Parser.SxmlParser import SxmlParser
from lib.Enricher.SxmlEnricher import SxmlEnricher
from lib.Writer import Writer
from lib.Formatter.SXML import SXML
from lib.Formatter.IFF import IFF


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
    input_file = params['infile']   
    lot_metadata_location = yaml_data['UPM']['lot_metadata_location']
    scribe_file = yaml_data['UPM']['scribe']
    ship_scribe_file = yaml_data['UPM']['ship_scribe']
    Log.INFO(f"creating scribe dictonary")
    scribe_dictionary = JndUtil.create_dictionary_from_jnd_scribe_file(scribe_file)
    Log.INFO(f"creating ship scribe dictonary")
    ship_scribe_dictionary = JndUtil.create_dictionary_from_jnd_scribe_file(ship_scribe_file)
    Log.INFO(f"merging scribe and ship scribe dictonary")
    waferids = scribe_dictionary | ship_scribe_dictionary
    lot_metadata = {}
    last_lot_metadata = {}
    is_lot_metadata = False
    jnd_motherlot = None
    jnd_sourceLot = None
    lot = None
    wafer_number = None
    waferid = "NA"
           
    Log.INFO(f"Input file={input_file}")
    Log.INFO(f'Outbox={outbox}')

    lot_regex = r"^[A-Za-z]{2}.*)"
      
        
    # Define values for the attributes you want to set
    wr_kwargs = {
        'outdir': outbox,
        'basename': os.path.basename(input_file),
        'ext': 'xml',
        'gzipIFF': True,
        # 'forced_sandbox': for_sandbox
    }
    # # Instantiate the Writer class and pass the values as keyword arguments
    writer_instance = Writer(**wr_kwargs)
    
    xml_sanitizer_config = Util.get_xml_sanitizer_config(yaml_data, 'UPM')
    sxml_parser = SxmlParser(input_file, sanitizer_config=xml_sanitizer_config)

    # Log if XML was malformed but don't route to sandbox automatically
    if sxml_parser.is_malformed:
        Log.WARN("XML file required sanitization to parse correctly")
        Log.INFO("File will be processed normally (not automatically routed to SANDBOX)")

    lot = sxml_parser.get_upm_lotid()
    wafer_number = Util.format_wafer_number(sxml_parser.get_upm_wafernr())
    Log.INFO(f"LOT={lot}||WAFER_NUMBER={wafer_number} from UPM file")
    
    if lot:
        jnd_motherlot, jnd_sourceLot = JndUtil.get_jnd_lot_mother_lot_source_lot_not_refdb(lot)
        lot_metadata_file = f"{jnd_motherlot}.lot"
        lot_metadata_file_fullpath = os.path.join(lot_metadata_location, lot_metadata_file)
        Log.INFO(f"MOTHERLOT={jnd_motherlot}||SOURCELOT={jnd_sourceLot}||LOT_METADATA={lot_metadata_file}||FULLPATH={lot_metadata_file_fullpath}")
    else:
        Log.INFO(f"Not lot found lot={lot}")
        Util.dp_exit(1, "No lot found")
        
    if Util.looks_like_number(wafer_number):
        waferid = JndUtil.get_waferid_scribe_file(lot, wafer_number, waferids)
        if waferid == "NA":
            waferid = f"{jnd_motherlot}-{wafer_number}"
            writer_instance.noMeta = True
            Log.INFO(f"Waferid={waferid} not found in reference file scribe/shipScribe, SANDBOX.")
        else:
            Log.INFO(f"WAFERID from Scribe/ShipScribe reference file={waferid} will be used.")
    else:
        Log.ERROR(f"No valid wafer number={wafer_number}")
        Util.dp_exit(1, f"No valid wafer number={wafer_number}")
        
    if Util.check_file_exists(lot_metadata_file_fullpath):
        is_lot_metadata = True
        Log.INFO(f"Found!!! Loaded metadata from {lot_metadata_file_fullpath}")
        lot_metadata, last_lot_metadata = JndUtil.load_jnd_lot_metadata(lot_metadata_file_fullpath)
    else:
        is_lot_metadata = False
        lot_metadata[lot] = {
            'TPNO': 'NA',
            'AccountCode': 'NA',
            'MBNO': 'NA',
            'Process': 'NA',
            'Technology': 'NA',
            'Fab': 'JND:AIZU2 FAB (PTI)',
            'SourceLot': jnd_sourceLot,
            'ParentLot=': jnd_motherlot,
            'LotType': 'NA'
        }
        writer_instance.noMeta = True
        Log.INFO(f"Not found lot metadata={lot_metadata_file_fullpath}, SANDBOX.")
    
    upm_sxml_enricher = SxmlEnricher(input_file)
    enriched_upm_xml = upm_sxml_enricher.enrich_upm(lot, waferid, lot_metadata, last_lot_metadata)
    # print(enriched_kdf_xml)
    sxml_instance = SXML(writer=writer_instance, sxml=enriched_upm_xml)
    sxml_instance.write_list_of_line_string_to_file()
      
    Util.dp_exit(0)

if __name__ == "__main__":
    main() 