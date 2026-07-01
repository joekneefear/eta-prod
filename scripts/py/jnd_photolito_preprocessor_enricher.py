#!/usr/bin/env python3.12

"""

SYNOPSIS

DESCRIPTION
    JND Photolito

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Oct-24 - jgarcia - initial

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
from lib.Writer import Writer
from lib.Formatter.IFF import IFF
from lib.Data.MetadataDTO import MetadataDTO
from lib.Data.Model import Model
from lib.Data.Wmap import Wmap
from lib.Parser.JndPhotolitoParser import JndPhotolitoParser

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
    
    outbox = params['out']
    input_file = params['infile']
    Log.INFO(f"Input file={input_file}")
    Log.INFO(f'Outbox={outbox}')
    yaml_file = params.get('config_file', '/export/home/dpower/project/scripts/py/resources/JND_CONFIG.yaml')
    yaml_data = Util.load_yaml(yaml_file)
    lot_metadata_location = yaml_data['PHOTOLITHO']['lot_metadata_location']
    scribe_file = yaml_data['PHOTOLITHO']['scribe']
    ship_scribe_file = yaml_data['PHOTOLITHO']['ship_scribe']
    Log.INFO(f"preparing scribe dictionary...")
    scribe_dictionary = JndUtil.create_dictionary_from_jnd_scribe_file(scribe_file)
    Log.INFO(f"preparing ship scribe dictionary...")
    ship_scribe_dictionary = JndUtil.create_dictionary_from_jnd_scribe_file(ship_scribe_file)
    Log.INFO(f"merging scribe and ship scribe dictionary...")
    waferids = scribe_dictionary | ship_scribe_dictionary
    new_waferids = {}
    ws_url = yaml_data['PHOTOLITHO']['ws_url']
    ws_source = params['ws_source']
    ws_url_ref_data = Util.load_yaml(ws_url)
    # Log.INFO(f"WS URL Ref Data: {ws_url_ref_data['refdb'][ws_source]}")
    ws_urls = Util.configure_ws_urls(ws_source, ws_url_ref_data)
    default_onscribe_metadata = yaml_data['default_onscribe_metadata']
    default_onlot_metadata = yaml_data['default_onlot_metadata']
    # Parse lot information
    # lot = input_file.split('_')[2]
    # Split by underscores
    base_filename = os.path.splitext(os.path.basename(input_file))[0]
    lot = base_filename.split('_')[2]
    ws_retries = yaml_data['WS_Refdb_Client']['retries']
    ws_backoff_factor = yaml_data['WS_Refdb_Client']['backoff_factor']
    ws_status_forcelist = yaml_data['WS_Refdb_Client']['status_forcelist']
    ws_timeout = yaml_data['WS_Refdb_Client']['timeout']
    refdb_api_client = RefdbAPIClient(retries=ws_retries, backoff_factor=ws_backoff_factor, status_forcelist=tuple(ws_status_forcelist))
    lot_metadata = {}
    last_lot_metadata = {}
    is_lot_metadata = False
    # default_onlot_prod = yaml_data['default_onlot_prod']
   # Define values for the attributes you want to set
    wr_kwargs = {
        'outdir': outbox,
        'basename': os.path.basename(input_file),
        'ext': 'xml',
        'gzipIFF': True,
    }
    # # Instantiate the Writer class and pass the values as keyword arguments
    writer = Writer(**wr_kwargs)

    #parse stdml and get also data points
    photolito_parser = JndPhotolitoParser()
    #prepare jnd_lot and jnd_sourecelot not from refdb
    jnd_motherlot, jnd_sourceLot = JndUtil.get_jnd_lot_mother_lot_source_lot_not_refdb(lot)
    lot_metadata_file = f"{jnd_motherlot}.lot"
    lot_metadata_file_fullpath = os.path.join(lot_metadata_location, lot_metadata_file)
    Log.INFO(f"MOTHERLOT={jnd_motherlot}||SOURCELOT={jnd_sourceLot}||LOT_METADATA={lot_metadata_file}||FULLPATH={lot_metadata_file_fullpath}")
    if os.path.exists(lot_metadata_file_fullpath):
        # Load the metadata
        is_lot_metadata = True
        jnd_lot_metadata, jnd_last_lot_metadata = JndUtil.load_jnd_lot_metadata(lot_metadata_file_fullpath)
        Log.INFO(f"Loaded metadata from {lot_metadata_file_fullpath}")
    else:
        Log.WARN(f"The file {lot_metadata_file_fullpath} does not exist.")
        is_lot_metadata = False
    # jnd_lot_metadata, jnd_last_lot_metadata = Util.load_jnd_lot_metadata(lot_metadata_file_fullpath)
    model = photolito_parser.read_file(input_file)
    model.metadata.LOT = lot
    if is_lot_metadata:
        if lot in jnd_lot_metadata:
            model.metadata.SOURCE_LOT = jnd_lot_metadata[lot].get('SourceLot', 'NA')
            # print(f"=======+++++{model.metadata.SOURCE_LOT}")
            model.metadata.TECHNOLOGY = jnd_lot_metadata[lot].get('Technology', 'NA')
            model.metadata.LOT_TYPE = jnd_lot_metadata[lot].get('LotType', 'NA')
            model.metadata.FAB = jnd_lot_metadata[lot].get('Fab', 'NA')
            model.metadata.MASK_SET = jnd_lot_metadata[lot].get('TPNO', 'NA')
        elif lot in jnd_last_lot_metadata:
            model.metadata.SOURCE_LOT = jnd_last_lot_metadata.get('SourceLot', 'NA')
            model.metadata.TECHNOLOGY = jnd_last_lot_metadata.get('Technology', 'NA')
            model.metadata.LOT_TYPE = jnd_last_lot_metadata.get('LotType', 'NA')
            model.metadata.FAB = jnd_last_lot_metadata.get('Fab', 'NA')
            model.metadata.MASK_SET = jnd_last_lot_metadata.get('TPNO', 'NA')
    else:
        model.metadata.SOURCE_LOT = jnd_sourceLot
        model.metadata.TECHNOLOGY = 'NA'
        model.metadata.LOT_TYPE =  'NA'
        model.metadata.FAB = "JND:AIZU2 FAB (PTI)"
        model.metadata.MASK_SET ='NA'
        writer.noMeta = True
        Log.INFO(f"No lot metadata ={lot_metadata_file_fullpath}  found for this lot={lot}")

    wafer_number = Util.format_wafer_number(model.wafers[0].number)
    default_onscribe_metadata = Util.replace_dict_value(default_onscribe_metadata, 'lot', lot)
    default_onscribe_metadata = Util.replace_dict_value(default_onscribe_metadata, 'waferNum', wafer_number)
    default_onlot_metadata =  Util.replace_dict_value(default_onlot_metadata, 'lot', lot)
    default_onlot_metadata = Util.replace_dict_value(default_onlot_metadata, "sourceLot", jnd_sourceLot)
    onscribe_metadata = default_onscribe_metadata
    onscribe_metadata = Util.update_wafer_id(onscribe_metadata, jnd_sourceLot, wafer_number)
    waferid = onscribe_metadata.get('waferId', 'NA')
    if wafer_number and lot:
        Log.INFO(f"wafer number and lot are NOT blank")
        
        lot_wafer_key = f"{lot}_{wafer_number}"
        
        if Util.looks_like_number(wafer_number):
            waferid = JndUtil.get_waferid_scribe_file(lot, wafer_number, waferids)
            if waferid == 'NA':
                onscribe_metadata, new_lot_wafer_key = JndUtil.get_jnd_onscribe_metadata(refdb_api_client, ws_urls, jnd_sourceLot, waferids, lot, wafer_number, default_onscribe_metadata, default_onlot_metadata)
                waferid = onscribe_metadata.get('waferId', 'NA')
                if isinstance(onscribe_metadata, dict) and onscribe_metadata['status'].upper() == 'MANUAL':
                    for key in [new_lot_wafer_key, lot_wafer_key]:
                        if key not in new_waferids:
                            new_waferids[key] = waferid
                else:
                    Log.INFO(f"No waferid from ERT and reference file, CALCULATED WAFERID={waferid} will be used.")
            else:
                Log.INFO(f"WAFERID from Scribe/ShipScribe reference file={waferid} will be used.")
        else:
           Log.INFO(f"No valid wafer number={wafer_number}, WAFERID{waferid} will be NA.")
                    # writer.noMeta = True

        # model.wafers[0].name = waferid
    else:
        # waferid = onscribe_metadata.get('waferId', 'NA')
        Log.ERROR(f"wafer number and lot are blank")
        writer.noMeta = True
        Util.dp_exit(1, "No lot and wafer number!!! please check raw file.")
    #set final Program value
    model.wafers[0].name = waferid
    final_program_name = model.metadata.PROGRAM
    final_program_name = f"{model.metadata.TECHNOLOGY}:{model.metadata.PROGRAM}"
    Log.INFO(f"Final program name={final_program_name}")
    model.metadata.PROGRAM = final_program_name
    iff_args = {
        'writer': writer,
        'model': model
    }
    
    iff_instance = IFF(iff_args)
    # print(iff_instance.writer.basename)
    iff_instance.data_items = ['x', 'y', 'site']
    iff_instance.test_items = ['number', 'name']
    iff_instance.print_par()

    if new_waferids:
        JndUtil.append_to_jnd_scribe_file_if_not_exists(new_waferids, scribe_file)
    else:
        Log.INFO(f"No new waferid/s that is/are not calculated, and from ERT")
    
    Util.dp_exit(0)

if __name__ == '__main__':
    main()