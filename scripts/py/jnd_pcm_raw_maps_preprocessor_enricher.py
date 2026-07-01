#!/usr/bin/env python3.12

"""

SYNOPSIS

DESCRIPTION
    JND PCM RAW MAPS 

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Oct-31 - jgarcia - initial

LICENSE
    (C) onsemi 2024 All rights reserved.
"""

import csv
import sys
import os
import re
from lib.Log import Log
from lib.Util import Util
from lib.Utility.JndUtil import JndUtil
from lib.WS.RefdbAPIClient import RefdbAPIClient
from lib.Enricher.SpecXmlEnricher import SpecXmlEnricher
from lib.Parser.SpecXmlParser import SpecXmlParser
from lib.Writer import Writer
from lib.Formatter.SXML import SXML
from lib.Formatter.IFF import IFF
from lib.Data.MetadataDTO import MetadataDTO
from lib.Parser.FJMParser import FJMParser
from lib.Data.Model import Model
from lib.Data.Wmap import Wmap

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
    
    input_file = params['infile']
    # Get the base filename without the extension
    base_filename = os.path.splitext(os.path.basename(input_file))[0]
    yaml_file = params.get('config_file', '/export/home/dpower/project/scripts/py/resources/JND_CONFIG.yaml')
    yaml_data = Util.load_yaml(yaml_file)
    lot_metadata_location = yaml_data['RAW_MAPS']['lot_metadata_location']
    scribe_file = yaml_data['Tesec']['scribe']
    ship_scribe_file = yaml_data['Tesec']['ship_scribe']
    Log.INFO(f"creating scribe dictonary")
    scribe_dictionary = JndUtil.create_dictionary_from_jnd_scribe_file(scribe_file)
    Log.INFO(f"creating ship scribe dictonary")
    ship_scribe_dictionary = JndUtil.create_dictionary_from_jnd_scribe_file(ship_scribe_file)
    Log.INFO(f"merging scribe and ship scribe dictonary")
    waferids = scribe_dictionary | ship_scribe_dictionary
    new_waferids = {}
    ws_url = yaml_data['RAW_MAPS']['ws_url']
    ws_source = params['ws_source']
    ws_url_ref_data = Util.load_yaml(ws_url)
    # Log.INFO(f"WS URL Ref Data: {ws_url_ref_data['refdb'][ws_source]}")
    ws_urls = Util.configure_ws_urls(ws_source, ws_url_ref_data)
    outbox = params['out']
    ws_retries = yaml_data['WS_Refdb_Client']['retries']
    ws_backoff_factor = yaml_data['WS_Refdb_Client']['backoff_factor']
    ws_status_forcelist = yaml_data['WS_Refdb_Client']['status_forcelist']
    ws_timeout = yaml_data['WS_Refdb_Client']['timeout']
    refdb_api_client = RefdbAPIClient(retries=ws_retries, backoff_factor=ws_backoff_factor, status_forcelist=tuple(ws_status_forcelist))
    lot_metadata = {}
    last_lot_metadata = {}
    is_lot_metadata = False
    default_onscribe_metadata = yaml_data['default_onscribe_metadata']
    default_onlot_metadata = yaml_data['default_onlot_metadata']
    Log.INFO(f"Input file={input_file}")
    Log.INFO(f'Outbox={outbox}')

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

    #parse stdml and get also data points
    raw_maps_sxml_parser = SpecXmlParser(input_file)
    lot = raw_maps_sxml_parser.get_lot_value()
    #prepare jnd_lot and jnd_sourecelot not from refdb
    if lot:
        jnd_motherlot, jnd_sourceLot = JndUtil.get_jnd_lot_mother_lot_source_lot_not_refdb(lot)
        lot_metadata_file = f"{jnd_motherlot}.lot"
        lot_metadata_file_fullpath = os.path.join(lot_metadata_location, lot_metadata_file)
        Log.INFO(f"MOTHERLOT={jnd_motherlot}||SOURCELOT={jnd_sourceLot}||LOT_METADATA={lot_metadata_file}||FULLPATH={lot_metadata_file_fullpath}")
    else:
        Log.INFO(f"Not lot found lot={lot}")
        Util.dp_exit(1, "No lot found")
        
    if Util.check_file_exists(lot_metadata_file_fullpath):
        is_lot_metadata = True
        lot_metadata, last_lot_metadata = JndUtil.load_jnd_lot_metadata(lot_metadata_file_fullpath)
        Log.INFO(f"Found!! Loaded metadata from {lot_metadata_file_fullpath}")
    else:
        Log.WARN(f"Not found!!! The file {lot_metadata_file_fullpath} does not exist.")
        Log.INFO(f"Try to use lot from filename")
        lot = JndUtil.extract_lot_from_jnd_pcm_filename(input_file)
        jnd_motherlot, jnd_sourceLot = JndUtil.get_jnd_lot_mother_lot_source_lot_not_refdb(lot)
        lot_metadata_file = f"{jnd_motherlot}.lot"
        lot_metadata_file_fullpath = os.path.join(lot_metadata_location, lot_metadata_file)
        Log.INFO(f"MOTHERLOT={jnd_motherlot}||SOURCELOT={jnd_sourceLot}||LOT_METADATA={lot_metadata_file}||FULLPATH={lot_metadata_file_fullpath}")
        if Util.check_file_exists(lot_metadata_file_fullpath):
            is_lot_metadata = True
            lot_metadata, last_lot_metadata = JndUtil.load_jnd_lot_metadata(lot_metadata_file_fullpath)
            Log.INFO(f"Found!! Loaded metadata from {lot_metadata_file_fullpath}")
        else:
            is_lot_metadata = False
            lot_metadata[lot] = {
                'TPNO': 'NA',
                'AccountCode': 'NA',
                'MBNO': 'NA',
                'Process': 'NA',
                'Technology': 'NA',
                'Fab': default_jnd_fab,
                'SourceLot': jnd_sourceLot,
                'ParentLot=': jnd_motherlot,
                'LotType': 'NA'
            }
    raw_maps_sxml_enricher = SpecXmlEnricher(input_file, refdb_api_client, ws_urls, default_onscribe_metadata, default_onlot_metadata)
    enriched_raw_maps_xml, new_waferids = raw_maps_sxml_enricher.enrich(lot, jnd_motherlot, jnd_sourceLot, lot_metadata_file_fullpath, waferids)
    # print(enriched_kdf_xml)
    sxml_instance = SXML(writer=writer_instance, sxml=enriched_raw_maps_xml)
    sxml_instance.write_list_of_line_string_to_file()
    
    if new_waferids:
        JndUtil.append_to_jnd_scribe_file_if_not_exists(new_waferids, scribe_file)
    else:
        Log.INFO(f"No new waferid/s that is/are not calculated, and from ERT")

    Util.dp_exit(0)

if __name__ == '__main__':
    main()