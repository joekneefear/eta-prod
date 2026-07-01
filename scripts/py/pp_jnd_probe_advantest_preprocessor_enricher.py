#!/usr/bin/env python3.12

"""
SYNOPSIS
    Script for JND probe Advantest.

DESCRIPTION
    This script processes the metadata for the JND probe Advantest.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Sep-2 - jgarcia - Initial version.
    2024-Sep-25 - jgarcia - Updated shebang to use python3.6.
    2026-Mar-18 - jgarcia - added error handling to enrichment to log the error and return the original content with metadata only as a fallback instead of exiting the program, this is to prevent the entire enrichment process from failing due to an error in sxml enrichment, and to allow the rest of the metadata enrichment to still be applied and returned.

LICENSE
    (C) onsemi 2024 All rights reserved.
"""

import os
import sys
import re
import csv

import pandas as pd

from lib.Log import Log
from lib.Util import Util
from lib.Utility.JndUtil import JndUtil
from lib.WS.RefdbAPIClient import RefdbAPIClient
from lib.Enricher.SxmlEnricher import SxmlEnricher
from lib.Parser.SxmlParser import SxmlParser
from lib.Writer import Writer
from lib.Formatter.SXML import SXML
from lib.Formatter.IFF import IFF
from lib.Data.MetadataDTO import MetadataDTO
from lib.Parser.FJMParser import FJMParser
from lib.Data.Model import Model
from lib.Data.Wmap import Wmap

def initialize_log_file():
    """Initialize the log file based on script name and environment variable."""
    script_name = os.path.basename(sys.argv[0])
    log_file_name = os.path.splitext(script_name)[0] + '.log'
    log_dir = os.environ.get('DPLOG', '/export/home/dpower/project/log')
    log_file = os.path.join(log_dir, log_file_name)

    log_args = ['--logfile', '--log_file', '--log']
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

def get_metadata(url, client):
    """Retrieve metadata from the given URL using the provided client."""
    try:
        return client.get_metadata(url)
    except Exception as e:
        Log.ERROR(f"Failed to get metadata from {url}: {e}")
        return {}

def main():
    """Main function to execute the script."""
    log_file = initialize_log_file()
    Log.configure_logger(log_file=log_file)
    
    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)
    
    if len(sys.argv) < 2:
        Log.INFO("No input file specified!")
        Util.dp_exit(1, "No input file specified!")
    
    input_file = params['infile']
    base_filename = os.path.splitext(os.path.basename(input_file))[0]
    assumed_jnd_lot_value = base_filename.split('_')[0]
    if len(assumed_jnd_lot_value) >= 2 and assumed_jnd_lot_value[:2].isalpha():
        tpno = base_filename.split('_')[1]
    else:
        tpno = assumed_jnd_lot_value[2:7]

    test_lookup_pattern = rf"{tpno}_\d+\.csv"
    Log.INFO(f"TEST_LOOKUP_PATTERN => {test_lookup_pattern}")
    yaml_file = params.get('config_file', '/export/home/dpower/project/scripts/py/resources/JND_CONFIG.yaml')
    yaml_data = Util.load_yaml(yaml_file)
    scribe_file = yaml_data['Tesec']['scribe']
    ship_scribe_file = yaml_data['Tesec']['ship_scribe']
    Log.INFO(f"creating scribe dictonary")
    scribe_dictionary = JndUtil.create_dictionary_from_jnd_scribe_file(scribe_file)
    Log.INFO(f"creating ship scribe dictonary")
    ship_scribe_dictionary = JndUtil.create_dictionary_from_jnd_scribe_file(ship_scribe_file)
    Log.INFO(f"merging scribe and ship scribe dictonary")
    waferids = scribe_dictionary | ship_scribe_dictionary
    new_waferids = {}
    lot_metadata_location = yaml_data['Advantest']['lot_metadata_location']
    test_lookup_location = yaml_data['Advantest']['test_lookup']
    test_lookup_file = Util.get_specific_file(test_lookup_location, test_lookup_pattern)
    Log.INFO(f"TEST_LOOKUP_FILE = {test_lookup_file}")
    tests = {}
    if test_lookup_file:
        tests = JndUtil.load_jnd_advantest_tests(test_lookup_file)
    else:
        Log.ERROR('No test lookup file.')
        Util.dp_exit(1, "No test lookup file!")

    fjm_location = yaml_data['Advantest']['fjm_location']
    fjm = JndUtil.find_first_jnd_fjm_file(fjm_location, tpno)
    ws_url = yaml_data['Advantest']['ws_url']
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
    default_onlot_prod = yaml_data['default_onlot_prod']
    default_onscribe_metadata = yaml_data['default_onscribe_metadata']
    default_onlot_metadata = yaml_data['default_onlot_metadata']
    Log.INFO(f"Input file = {input_file}")
    Log.INFO(f'Outbox = {outbox}')
    Log.INFO(f"FJM = {fjm} || TPNO = {tpno}")

    wr_kwargs = {
        'outdir': outbox,
        'basename': os.path.basename(input_file),
        'ext': 'xml',
        'gzipIFF': True,
    }
    writer_instance = Writer(**wr_kwargs)
   
    source_mapping = yaml_data['Advantest']['source_mapping']
    field_mapping = yaml_data['Advantest']['field_mapping']

    xml_sanitizer_config = Util.get_xml_sanitizer_config(yaml_data, 'Advantest')
    advantest_sxml_parser = SxmlParser(input_file, sanitizer_config=xml_sanitizer_config)
    
    # Log if XML was malformed but don't route to sandbox automatically
    if advantest_sxml_parser.is_malformed:
        Log.WARN("XML file required sanitization to parse correctly")
        Log.INFO("File will be processed normally (not automatically routed to SANDBOX)")

    stdml_lot_section, model = advantest_sxml_parser.get_lot_attributes_and_units()
    if 'MEAS_END' not in stdml_lot_section or stdml_lot_section['MEAS_END'] == "":
        stdml_lot_section['MEAS_END'] = stdml_lot_section.get('MEAS_START')
    raw_lot = stdml_lot_section.get('LOT_NO')
    raw_wafer_number = stdml_lot_section.get('WAFER_NO')
    raw_wafer_number = Util.format_wafer_number(raw_wafer_number)
    # if int(raw_wafer_number) < 10:
    #     raw_wafer_number = raw_wafer_number.zfill(2)
    raw_tester_name = stdml_lot_section.get('TEST_NAME')
    if raw_lot:
        jnd_motherlot, jnd_sourceLot = JndUtil.get_jnd_lot_mother_lot_source_lot_not_refdb(stdml_lot_section.get('LOT_NO'))
        Log.INFO(f"JND MOTHERLOT={jnd_motherlot} || JND SOURCELOT={jnd_sourceLot}")
        filename = f"{jnd_motherlot}.lot"
        lot_metadata_file_fullpath = os.path.join(lot_metadata_location, filename)
    else:
        Log.INFO(f"Not lot found lot={raw_lot}")
        Util.dp_exit(1, "No lot found")
    
    if os.path.exists(lot_metadata_file_fullpath):
        # Load the metadata
        is_lot_metadata = True
        lot_metadata, last_lot_metadata = JndUtil.load_jnd_lot_metadata(lot_metadata_file_fullpath)
        Log.INFO(f"Lot metadata file is available={lot_metadata_file_fullpath}")
    else:
        Log.WARN(f"The file {lot_metadata_file_fullpath} does not exist.")
        is_lot_metadata = False
    # lot_metadata, last_lot_metadata = Util.load_jnd_lot_metadata(lot_metadata_file_fullpath)
    onlotprod_url = f"{ws_urls['onlotprod']}/{raw_lot}"
    

    if raw_lot.startswith('7G'):
        jm_lot = JndUtil.jnd_7G_to_jm(raw_lot)
        if jm_lot:
            onlotprod_url = f"{ws_urls['onlotprod']}/{jm_lot}"
            
    Log.INFO(f"ON_LOT_PROD_URL={onlotprod_url}")       
    onlotprod_metadata = refdb_api_client.get_metadata(onlotprod_url, default_onlot_prod, ws_timeout)
    if onlotprod_metadata['onLot']['status'].upper() in ['ERROR', 'NO_LOTG', 'NOLOTG', 'NO_DATA', 'NODATA'] and is_lot_metadata:
   
        Log.INFO(f"No LotG info found from refdb, will try to get from lot metadata")
               
        if raw_lot in lot_metadata:
            Log.INFO(f"metadata from lot={raw_lot} metadata -> {filename}")
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'product', lot_metadata[raw_lot].get('TPNO', 'NA'))  
            source_mapping['onLot']['product'] = "SCRIPT_LOT_METADATA"
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'parentLot', lot_metadata[raw_lot].get('ParentLot', 'NA'))
            source_mapping["onLot"]["parentLot"] = "SCRIPT_LOT_METADATA"   
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'lotType', lot_metadata[raw_lot].get('LotTYpe', 'NA'))   
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'fab', lot_metadata[raw_lot].get('Fab', 'NA'))
            source_mapping["onLot"]["fab"] = "SCRIPT_LOT_METADATA"
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'sourceLot', lot_metadata[raw_lot].get('SourceLot', 'NA'))
            source_mapping["onLot"]["sourceLot"] = "SCRIPT_LOT_METADATA"
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'process', lot_metadata[raw_lot].get('Process', 'NA'))
            source_mapping["onProd"]["process"] = "SCRIPT_LOT_METADATA"
        elif last_lot_metadata:
            Log.INFO(f"metadata from last lot{raw_lot} metadata -> {filename}")
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'product', last_lot_metadata.get('TPNO', 'NA'))  
            source_mapping["onLot"]["product"] = "SCRIPT_LOT_METADATA"
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'parentLot', last_lot_metadata.get('ParentLot', 'NA'))
            source_mapping["onLot"]["parentLot"] = "SCRIPT_LOT_METADATA"   
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'lotType', last_lot_metadata.get('LotTYpe', 'NA'))   
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'fab', last_lot_metadata.get('Fab', 'NA'))
            source_mapping["onLot"]["fab"] = "SCRIPT_LOT_METADATA"
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'sourceLot', last_lot_metadata.get('SourceLot', 'NA'))
            source_mapping["onLot"]["sourceLot"] = "SCRIPT_LOT_METADATA"
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'process', last_lot_metadata.get('Process', 'NA'))
            source_mapping["onProd"]["process"] = "SCRIPT_LOT_METADATA"
        else:
            Log.INFO(f"No LotG and no lot metadata, to SANDBOX")
            writer_instance.noMeta = True
    else:
        Log.INFO(f"OnLot, OnProd metadata found in ERT.")
        # if onlotprod_metadata.get("onProd", {}).get("technology") in [None, 'None'] and is_lot_metadata:
        technology_from_ERT = onlotprod_metadata.get("onProd", {}).get("technology")
        if ((technology_from_ERT in [None, 'None', 'Null', 'null', ''] or 'dummy' in str(technology_from_ERT).strip().lower()) and is_lot_metadata):
            Log.INFO("No Technology info from refdb, will try to get from lot metadata")
            tech_from_lot_metadata, lot_type = JndUtil.get_technology_and_lotType_from_lot_metadata_file(lot_metadata_file_fullpath)
            Log.INFO(f"Technology={tech_from_lot_metadata}||LotType={lot_type} from lot metadata will be used.")
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'technology', tech_from_lot_metadata)
            source_mapping["onProd"]["technology"] = "SCRIPT_LOT_METADATA"
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, "lotType", lot_type)
            source_mapping["onLot"]["lotType"] = "SCRIPT_LOT_METADATA"
        else:
            Log.INFO(f"No Technology from refdb and lot metadata, - SANDBOX.")
            writer_instance.noMeta = True
    
    onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, "sourceLot", jnd_sourceLot)
    
    lot_wafer_key = f"{raw_lot}_{raw_wafer_number}"
   
    default_onscribe_metadata = Util.replace_dict_value(default_onscribe_metadata, 'lot', raw_lot)
    default_onscribe_metadata = Util.replace_dict_value(default_onscribe_metadata, 'waferNum', raw_wafer_number)
    default_onlot_metadata =  Util.replace_dict_value(default_onlot_metadata, 'lot', raw_lot)
    default_onlot_metadata = Util.replace_dict_value(default_onlot_metadata, "sourceLot", jnd_sourceLot)
    onscribe_metadata = default_onscribe_metadata
    onscribe_metadata = Util.update_wafer_id(onscribe_metadata, jnd_sourceLot, raw_wafer_number)
    waferid = onscribe_metadata.get('waferId', 'NA')
    if Util.looks_like_number(raw_wafer_number):
        waferid = JndUtil.get_waferid_scribe_file(raw_lot, raw_wafer_number, waferids)
        if waferid == 'NA':
            onscribe_metadata, new_lot_wafer_key = JndUtil.get_jnd_onscribe_metadata(refdb_api_client, ws_urls, jnd_sourceLot, waferids, raw_lot, raw_wafer_number, default_onscribe_metadata, default_onlot_metadata)
            waferid = onscribe_metadata.get('waferId', 'NA')
            if isinstance(onscribe_metadata, dict) and onscribe_metadata['status'].upper() == 'MANUAL':
                Log.INFO(f"WAFERID from ERT={waferid} to be used.")
                for key in [new_lot_wafer_key, lot_wafer_key]:
                    if key not in new_waferids:
                        new_waferids[key] = waferid
            else:
                Log.INFO(f"No waferid from ERT and reference file, CALCULATED WAFERID={waferid} to be used, to SANDBOX")
                writer_instance.noMeta = True
        else:
            Log.INFO(f"WAFERID from Scribe/ShipScribe reference file={waferid} will be used.")
            onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'status', "MANUAL")
            onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'waferId', waferid)
            source_mapping["onScribe"]["waferId"] = "SCRIPT_SCRIBE_REF_FILE"
            onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'scribeId', waferid)
            source_mapping["onScribe"]["scribeId"] = "SCRIPT_SCRIBE_REF_FILE"
    else:
        Log.INFO(f"Wafer number from raw file may not be a valid number")
        Util.dp_exit(1, "Wafer number from raw file may not be a valid number")         
        # writer_instance.noMeta = True

    # onscribe_metadata = Util.update_wafer_id(onscribe_metadata, jnd_sourceLot, raw_wafer_number)
    if onscribe_metadata.get("scribeId") is None:
        writer_instance.noMeta = True
        onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'scribeId', onscribe_metadata.get("waferId"))
        source_mapping["onScribe"]["scribeId"] = "SCRIPT_FORMATTED_SOURCELOT-WAFERNUMBER"
        # source_mapping["onScribe"]["waferId"] = "SCRIPT_SOURCELOT_WAFERNUMBER"
    
    stats = model.wafers[0].stats()
    wmap = Wmap(stats)
    wmap.wf_units = yaml_data['Advantest']['WmcWaferUnits']
    wmap.flat = yaml_data['Advantest']['WmcWaferFlat']
    wmap.flat_type = yaml_data['Advantest']['WmcFlatType']
    wmap.positive_x = yaml_data['Advantest']['WmcPositiveX']
    wmap.positive_y = yaml_data['Advantest']['WmcPositiveY']
    
    if fjm:
        fjm_wmc_generator = FJMParser(fjm, wmap)
        wmc_dictionary = fjm_wmc_generator.get_wmc_in_dictionary()
        
        wmc_dictionary['maskSet'] = fjm_wmc_generator.get_mask_info()
    else:
        Log.WARN(f"FJM file = {fjm} is not found")
        writer_instance.noWMap = True
        wmc_dictionary = {}
    
    center_x = wmc_dictionary.get('center_x', None)
    center_y = wmc_dictionary.get('center_y', None)   
     
    if center_x is None or center_y is None:
        writer_instance.noWMap = True
     
    if onlotprod_metadata.get("onProd", {}).get("maskSet") in [None, 'None']:
        if fjm:
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'maskSet', fjm_wmc_generator.get_mask_info())
            source_mapping["onProd"]["maskSet"] = "SCRIPT_FJM_FILE"
        
    constant_mapping_data = yaml_data['Advantest']['constant_mapping_value']
    combined_metadata = {
        **onlotprod_metadata,
        'onScribe': onscribe_metadata,
        'stdml': stdml_lot_section,
        'constant': constant_mapping_data,
        'wmc': wmc_dictionary
    }
    metadataDTO_instance = MetadataDTO(field_mapping=field_mapping, source_mapping=source_mapping)
    metadata = metadataDTO_instance.generate_metadata_xml(combined_metadata)
    asc_sxml_enricher = SxmlEnricher(input_file)
    enriched_asc_xml = asc_sxml_enricher.enrich_xml(metadata, tests)
    sxml_instance = SXML(writer=writer_instance, sxml=enriched_asc_xml)
    sxml_instance.write_list_of_line_string_to_file()
    
    if new_waferids:
        JndUtil.append_to_jnd_scribe_file_if_not_exists(new_waferids, scribe_file)
    else:
        Log.INFO(f"No new waferid/s that is/are not calculated, and from ERT")

    Util.dp_exit(0)

if __name__ == '__main__':
    main()