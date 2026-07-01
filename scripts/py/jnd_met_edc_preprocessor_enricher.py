#!/usr/bin/env python3.12

"""
SYNOPSIS

DESCRIPTION
    This script will preprocess/enrich JND MET/EDC file. enrich technology and scribe
    also split into by lot per file and have max lines per file which is set in JndMetEdcPreprocessConfig.yaml

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Aug-14 - jgarcia - initial
    2024-Dec-04 - jgarcia - improved processing speed.
    
LICENSE
    (C) onsemi 2024 All rights reserved.
"""


import os
import sys
import gzip
import shutil
import yaml
import re
import tempfile
from lib.Log import Log
from lib.Util import Util
from lib.Utility.JndUtil import JndUtil
from lib.WS.RefdbAPIClient import RefdbAPIClient
from lib.Parser.JndMetEdcParser import JndMetEdcParser
from lib.Enricher.Klarf12Enricher import Klarf12Enricher
from lib.Writer import Writer
from lib.Formatter.IFF import IFF
from lib.Data.Model import Model
import pprint

# baseFile = ""

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
    if len(sys.argv) < 2:
        Log.INFO("No input file specified!!!")
        Util.dp_exit(1, "No input file specified!!!")
    
    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)
    input_file = params['infile']
    ws_source = params['ws_source']
    # dat_file_location = params['dat_file_location']
    yaml_file = params.get('config_file', '/export/home/dpower/project/scripts/py/resources/JND_CONFIG.yaml')
    yaml_data = Util.load_yaml(yaml_file)
    ws_url = yaml_data['common_paths']['ws_url']
    ws_url_ref_data = Util.load_yaml(ws_url)
    ws_urls = Util.configure_ws_urls(ws_source, ws_url_ref_data)
    # print(f"TEST={ws_urls}")
    log_file = initialize_log_file()
    Log.configure_logger(log_file=log_file)
    Log.INFO(f"Input file={input_file}")
    # decompressing_staging_folder = yaml_data['Metrology']['staging_folder']
    decompressing_staging_folder = os.path.split(input_file)[0]
    decompressing_staging_folder_temp = ""
    # Check if the folder exists, and create it if it doesn't
    if not os.path.exists(decompressing_staging_folder):
        os.makedirs(decompressing_staging_folder)
        Log.INFO(f"Folder '{decompressing_staging_folder}' created.")
    else:
        Log.INFO(f"Folder '{decompressing_staging_folder}' already exists.")

    # Create a temporary directory inside the decompressing staging folder
    decompressing_staging_folder_temp = tempfile.mkdtemp(dir=decompressing_staging_folder)
    Log.INFO(f"Decompress temp folder={decompressing_staging_folder_temp}")
    Util.GLOBAL_TEMP_FOLDER = decompressing_staging_folder_temp
    lot_metadata_location = yaml_data['common_paths']['lot_metadata_location']
    # types = yaml_data.get('FILE_TYPES', [])
    # Access the FILE_TYPES from the Metrology section using get
    types = yaml_data.get('Metrology', {}).get('FILE_TYPES', [])
    lot_per_file = yaml_data['Metrology']['LOT_PER_FILE']
    out_file_location_met = yaml_data['Metrology']['KIND_SPLIT_OUT_MET']
    out_file_location_prd = yaml_data['Metrology']['KIND_SPLIT_OUT_PRD']
    out_file_location_fab = yaml_data['Metrology']['KIND_SPLIT_OUT_FAB']
    out_file_location_eqp = yaml_data['Metrology']['KIND_SPLIT_OUT_EQP']
    out_file_location_met_limit = yaml_data['Metrology']['KIND_SPLIT_OUT_MET_LIMIT']
    out_file_location_prd_limit = yaml_data['Metrology']['KIND_SPLIT_OUT_PRD_LIMIT']
    out_file_location_fab_limit = yaml_data['Metrology']['KIND_SPLIT_OUT_FAB_LIMIT']
    out_file_location_eqp_limit = yaml_data['Metrology']['KIND_SPLIT_OUT_EQP_LIMIT']
    # waferids_json = yaml_data['Metrology']['scribe_json']
    scribe_file = yaml_data['Metrology']['scribe']
    ship_scribe_file = yaml_data['Metrology']['ship_scribe']
    Log.INFO(f"preparing scribe dictionary")
    scribe_dictionary = JndUtil.create_dictionary_from_jnd_scribe_file(scribe_file)
    Log.INFO(f"preparing ship scribe dictionary")
    ship_scribe_dictionary = JndUtil.create_dictionary_from_jnd_scribe_file(ship_scribe_file)
    Log.INFO(f"merging scribe and ship scribe dictionary")
    waferids = scribe_dictionary | ship_scribe_dictionary

    generate_limits = yaml_data['Metrology']['is_generate_limits']
    use_ERT_flag = yaml_data['Metrology']['use_ERT']

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
    base_file = ""
    # model = Model()
    met_edc_parser = JndMetEdcParser(input_file, decompressing_staging_folder_temp, lot_metadata_location, types, refdb_api_client, ws_urls, waferids, generate_limits, default_onscribe_metadata, default_onlot_metadata, use_ERT_flag)
    #unzip source file
    met_edc_parser.unzip_file_main()
    
    Log.INFO("Get the EDC_SHEET file and the .DAT file")
    if os.path.isdir(decompressing_staging_folder_temp):  # Check if the directory exists
        inflatedFiles = os.listdir(decompressing_staging_folder_temp)
        if inflatedFiles:
            for inflatedFile in inflatedFiles:
                if inflatedFile.lower().endswith('.txt'):
                    met_edc_parser.edc_sheet_file = os.path.join(decompressing_staging_folder_temp, inflatedFile)
                    # pplogger.setEdcSheetFile(inflatedFile)
                    Log.INFO(f"EDC SHEET: {met_edc_parser.edc_sheet_file}")
                elif inflatedFile.lower().endswith('.dat'):
                    met_edc_parser.dat_file = os.path.join(decompressing_staging_folder_temp, inflatedFile)
                    # pplogger.setDatFile(inflatedFile)
                    Log.INFO(f"DAT File = {met_edc_parser.dat_file}")
                    base_file = os.path.basename(met_edc_parser.dat_file)
        else:
            Log.INFO(f"No .dat file and/or edc_sheet file in the extract directory folder...")
            raise Exception("No .dat file and/or edc_sheet file in the extract directory folder...")
            
    else:
        Log.ERROR(f"Cant open {decompressing_staging_folder_temp}")
        raise Exception(f"Cant open {decompressing_staging_folder_temp}")

    Log.INFO("Processing EDC Sheet File")
    met_edc_parser.get_attr_name()
    # Log.INFO("Processing Scribe File")
    # scribe_info = get_scribe_data(scribe_location)  
    
    Log.INFO("split DAT File")
    
    model, new_waferids = met_edc_parser.split_and_enrich_file()
    
    # Initialize dictionaries with array values
    met_by_lot = {}
    prd_by_lot = {}
    fab_by_lot = {}
    eqp_by_lot = {}
    met_lim ={}
    met_by_set_lots = {}
    prd_by_set_lots = {}
    fab_by_set_lots = {}
    eqp_by_set_lots = {}
    met_limit_by_set_lots = {}
    prd_limit_by_set_lots = {}
    fab_limit_by_set_lots = {}
    eqp_limit_by_set_lots = {}
     
    if model.misc['file_data']:
        Log.INFO("Processing met and edc data types")
        for type, line_array in model.misc['file_data'].items():
            Log.INFO(f"=TYPE=>>{type}")
            if line_array:
                for line in line_array:
                    lot = line.split('|', 1)[0]
                    # Log.INFO(f"Lot={lot}")
                    if lot:
                        if type == "MET":
                            # Log.INFO(f"TEST1_TYPE={type}")
                            met_by_lot.setdefault(lot, []).append(line)
                        elif type == "PRD_EDC":
                            prd_by_lot.setdefault(lot, []).append(line)
                        elif type == "FAB_EDC":
                            fab_by_lot.setdefault(lot, []).append(line)
                        elif type == "EQP_EDC":
                            eqp_by_lot.setdefault(lot, []).append(line)
            
    if met_by_lot:
        # met_by_lot = met_edc_parser.enrich_waferid_source_lot_fab_at_the_end(met_by_lot)
        met_by_set_lots = met_edc_parser.split_lot_data_with_counter(met_by_lot, lot_per_file)
    
    if met_by_set_lots:
        met_edc_parser.write_lots_to_file(met_by_set_lots, ".MET", "MET", out_file_location_met, base_file)
    else:
        Log.WARN("No MET data lines from the raw file")

    if prd_by_lot:
        # prd_by_lot = met_edc_parser.enrich_waferid_source_lot_fab_at_the_end(prd_by_lot)
        prd_by_set_lots = met_edc_parser.split_lot_data_with_counter(prd_by_lot, lot_per_file) 
    
    if prd_by_set_lots:
        met_edc_parser.write_lots_to_file(prd_by_set_lots, ".PRD_EDC", "PRD_EDC", out_file_location_prd, base_file)
    else:
        Log.WARN("No PRD_EDC data lines from the raw file")

    if fab_by_lot:
        # fab_by_lot = met_edc_parser.enrich_waferid_source_lot_fab_at_the_end(fab_by_lot)
        fab_by_set_lots = met_edc_parser.split_lot_data_with_counter(fab_by_lot, lot_per_file)
    
    if fab_by_set_lots:
        met_edc_parser.write_lots_to_file(fab_by_set_lots, ".FAB_EDC", "FAB_EDC", out_file_location_fab, base_file)
    else:
        Log.WARN("No FAB_EDC data lines from the raw file")

    if eqp_by_lot:
    #    eqp_by_lot = met_edc_parser.enrich_waferid_source_lot_fab_at_the_end(eqp_by_lot)
       eqp_by_set_lots = met_edc_parser.split_lot_data_with_counter(eqp_by_lot, lot_per_file) 

    if eqp_by_set_lots:
        met_edc_parser.write_lots_to_file(eqp_by_set_lots, ".EQP_EDC", "EQP_EDC", out_file_location_eqp, base_file)
    else:
        Log.WARN("No FAB_EDC data lines from the raw file")

    if met_edc_parser.generate_limits:
        if model.misc['met_limit_file_data']:
            met_limit_by_set_lots = met_edc_parser.split_lot_data_with_counter(model.misc['met_limit_file_data'], lot_per_file)
        
        if met_limit_by_set_lots:
            met_edc_parser.write_lots_to_file(met_limit_by_set_lots, ".MET_LIMIT", "MET_LIMIT", out_file_location_met_limit, base_file)
        else:
            Log.WARN("No MET LIMIT data lines from the raw file")

        if model.misc['prd_edc_limit_file_data']:
            prd_limit_by_set_lots = met_edc_parser.split_lot_data_with_counter(model.misc['prd_edc_limit_file_data'], lot_per_file)
        
        if prd_limit_by_set_lots:
            met_edc_parser.write_lots_to_file(prd_limit_by_set_lots, ".PRD_EDC_LIMIT", "PRD_EDC_LIMIT", out_file_location_prd_limit, base_file)
        else:
            Log.WARN("No PRD LIMIT data lines from the raw file")
        
        if model.misc['fab_edc_limit_file_data']:
            fab_limit_by_set_lots = met_edc_parser.split_lot_data_with_counter(model.misc['fab_edc_limit_file_data'], lot_per_file)
        
        if fab_limit_by_set_lots:
            met_edc_parser.write_lots_to_file(fab_limit_by_set_lots, ".FAB_EDC_LIMIT", "FAB_EDC_LIMIT", out_file_location_fab_limit, base_file)
        else:
            Log.WARN("No FAB EDC LIMIT data lines from the raw file")
        
        if model.misc['eqp_edc_limit_file_data']:
            eqp_limit_by_set_lots = met_edc_parser.split_lot_data_with_counter(model.misc['eqp_edc_limit_file_data'], lot_per_file)
        
        if eqp_limit_by_set_lots:
            met_edc_parser.write_lots_to_file(eqp_limit_by_set_lots, ".EQP_EDC_LIMIT", "EQP_EDC_LIMIT", out_file_location_eqp_limit, base_file)
        else:
            Log.WARN("No EQP EDC LIMIT data lines from the raw file")
    
    if new_waferids:
        JndUtil.append_to_jnd_scribe_file_if_not_exists(new_waferids, scribe_file)
    else:
        Log.INFO(f"no new waferids that is not calculated from ERT")

    Util.dp_exit(0)

if __name__ == '__main__':
    main()