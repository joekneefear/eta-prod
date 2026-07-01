#!/usr/bin/env python3.12

"""
SYNOPSIS
    Script for JND probe Tesec.

DESCRIPTION
    This script processes the metadata for the JND probe Tesec.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Sep-2 - jgarcia - Initial version.
    2024-Nov-9 - jgarcia - Refactored; source will have no metadata. This script provides the metadata.
    2024-Jan-23 - jgarcia -Refactored(modularized, and use constants for repeated strings), fix bug on Technlolgy from lot metadata
    2025-Apr-25 -jgarica - improve in getting TPNO or chipcode from filename and from JobName for EQ lots.
    2026-Mar-18 - jgarcia - added error handling to wmc enrichment to log the error and return the original content with metadata only as a fallback instead of exiting the program, this is to prevent the entire enrichment process from failing due to an error in wmc enrichment, and to allow the rest of the metadata enrichment to still be applied and returned.

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
from lib.DbConnection import DbConnection
from lib.DbConnectionFactory import DbConnectionFactory
from lib.PPLogger import PPLogger

LOG_ARGS = ['--logfile', '--log_file', '--log']
DEFAULT_YAML_FILE = '/export/home/dpower/project/scripts/py/resources/JND_CONFIG.yaml'
DEFAULT_LOG_DIR = '/export/home/dpower/project/log'

def initialize_log_file():
    """Initialize the log file based on script name and environment variable."""
    script_name = os.path.basename(sys.argv[0])
    log_file_name = os.path.splitext(script_name)[0] + '.log'
    log_dir = os.environ.get('DPLOG', DEFAULT_LOG_DIR)
    log_file = os.path.join(log_dir, log_file_name)

    for i, arg in enumerate(sys.argv):
        for log_arg in LOG_ARGS:
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

def load_yaml_data(yaml_file):
    """Load YAML data from the specified file."""
    return Util.load_yaml(yaml_file)

def get_input_params():
    """Process command line arguments and return parameters."""
    arguments = sys.argv[1:]
    return Util.process_command_line_args(arguments)

# def get_base_filename(input_file):
#     """Extract base filename and assumed JND lot value."""
#     base_filename = os.path.splitext(os.path.basename(input_file))[0]
#     assumed_jnd_lot_value = base_filename.split('_')[0]
#     return base_filename, assumed_jnd_lot_value

# def get_tpno(assumed_jnd_lot_value):
#     """Determine TPNO based on assumed JND lot value."""
#     if len(assumed_jnd_lot_value) >= 2 and assumed_jnd_lot_value[:2].isalpha():
#         return assumed_jnd_lot_value.split('_')[1]
#     return assumed_jnd_lot_value[2:7]

def get_base_filename(input_file):
    """Extract base filename."""
    return os.path.splitext(os.path.basename(input_file))[0]

# def get_tpno(base_filename):
#     """Determine TPNO based on base filename."""
#     parts = base_filename.split('_')
#     if len(parts) > 1:
#         return parts[1]
#     return base_filename[2:7]

# def get_tpno(base_filename):
#     """Determine TPNO based on base filename and validate it."""
#     parts = base_filename.split('_')
#     if len(parts) > 1:
#         tpno_candidate = parts[1]
#         if tpno_candidate.isalnum() and len(tpno_candidate) > 1:
#             return tpno_candidate
#         else:
#             return "Invalid TPNO"
#     tpno_candidate = base_filename[2:7]
#     if tpno_candidate.isalnum() and len(tpno_candidate) > 1:
#         return tpno_candidate
#     return "Invalid TPNO"

def get_tpno(base_filename):
    """Determine TPNO based on base filename and validate it."""
    if base_filename.startswith("7G"):
        tpno_candidate = base_filename[2:7]
        if tpno_candidate.isalnum() and len(tpno_candidate) >= 4:
            return tpno_candidate
        else:
            return "Invalid TPNO"
    
    parts = base_filename.split('_')
    if len(parts) > 1:
        tpno_candidate = parts[1]
        if tpno_candidate.isalnum() and len(tpno_candidate) > 1:
            return tpno_candidate
        else:
            return "Invalid TPNO"
    
    tpno_candidate = base_filename[2:7]
    if tpno_candidate.isalnum() and len(tpno_candidate) > 1:
        return tpno_candidate
    return "Invalid TPNO"


def configure_writer(input_file, outbox, pplogger=None):
    """Configure the writer instance."""
    wr_kwargs = {
        'outdir': outbox,
        'basename': os.path.basename(input_file),
        'ext': 'xml',
        'gzipIFF': True,
        'pplogger': pplogger
    }
    return Writer(**wr_kwargs)

def main():
    """Main function to execute the script."""
    dp_exit = Util.dp_exit
    db_type = 'oracle'
    db_connection = DbConnectionFactory.create_db_connection(db_type)
    model = Model()
    log_file = initialize_log_file()
    pplogger = PPLogger()
    pplogger.set_to_be_logged(False)
    Log.configure_logger(log_file=log_file, pplogger=pplogger)
    
    params = get_input_params()
    
    if params.get('pplog'):
        pplogger.set_to_be_logged(True)
    
    if len(sys.argv) < 2:
        Log.INFO("No input file specified!")
        dp_exit(1, pplogger=pplogger, error="No input file specified!")
    
    input_file = params['infile']
    base_filename = get_base_filename(input_file)
    tpno = "Invalid TPNO"
    tpno = get_tpno(base_filename)
    Log.INFO(f"TPNO={tpno} extracted from the filename, first option")
    if not tpno.isalnum():
        Log.WARN(f"TPNO={tpno} extracted from the filename is not valid")
    fjm = None
    yaml_file = params.get('config_file', DEFAULT_YAML_FILE)
    yaml_data = load_yaml_data(yaml_file)
    
    scribe_file = yaml_data['Tesec']['scribe']
    ship_scribe_file = yaml_data['Tesec']['ship_scribe']
    Log.INFO("Creating scribe dictionary")
    scribe_dictionary = JndUtil.create_dictionary_from_jnd_scribe_file(scribe_file)
    Log.INFO("Creating ship scribe dictionary")
    ship_scribe_dictionary = JndUtil.create_dictionary_from_jnd_scribe_file(ship_scribe_file)
    Log.INFO("Merging scribe and ship scribe dictionary")
    waferids = scribe_dictionary | ship_scribe_dictionary
    new_waferids = {}
    lot_metadata_location = yaml_data['Tesec']['lot_metadata_location']
    fjm_location = yaml_data['Tesec']['fjm_location']
    ws_url = yaml_data['Tesec']['ws_url']
    ws_source = params['ws_source']
    ws_url_ref_data = Util.load_yaml(ws_url)
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
    # is_ERT = False
    default_onlot_prod = yaml_data['default_onlot_prod']
    default_onscribe_metadata = yaml_data['default_onscribe_metadata']
    default_onlot_metadata = yaml_data['default_onlot_metadata']
    Log.INFO(f"Input file = {input_file}")
    Log.INFO(f'Outbox = {outbox}')
    site = "JND"
    
    pplogger.set_raw_file(input_file)
    pplogger.set_env("jnd_probe_tesec")
    pplogger.set_site(site)
    pplogger.set_script(os.path.basename(__file__))

    writer_instance = configure_writer(input_file, outbox, pplogger)
   
    source_mapping = yaml_data['Tesec']['source_mapping']
    field_mapping = yaml_data['Tesec']['field_mapping']

    xml_sanitizer_config = Util.get_xml_sanitizer_config(yaml_data, 'Tesec')
    tesec_sxml_parser = SxmlParser(input_file, sanitizer_config=xml_sanitizer_config)
    
    # Log if XML was malformed but don't route to sandbox automatically
    if tesec_sxml_parser.is_malformed:
        Log.WARN("XML file required sanitization to parse correctly")
        Log.INFO("File will be processed normally (not automatically routed to SANDBOX)")
    
    stdml_lot_section, model = tesec_sxml_parser.get_lot_attributes_and_units()
    raw_lot = stdml_lot_section.get('LotId')
    pplogger.set_lot(raw_lot)
    raw_wafer_number = stdml_lot_section.get('SublotId')
    pplogger.set_waf_num(raw_wafer_number)
    raw_wafer_number = Util.format_wafer_number(raw_wafer_number)
    e_raw_lot_wafer_scribe = stdml_lot_section.get('UserText', 'NA')
        
    if raw_lot:
        jnd_motherlot, jnd_sourceLot = JndUtil.get_jnd_lot_mother_lot_source_lot_not_refdb(raw_lot)
        filename = f"{jnd_motherlot}.lot"
        Log.INFO(f"JND MOTHERLOT={jnd_motherlot} || JND SOURCELOT={jnd_sourceLot}")
        lot_metadata_file_fullpath = os.path.join(lot_metadata_location, filename)
    else:
        Log.INFO(f"Not lot found lot={raw_lot}")
        dp_exit(1, pplogger=pplogger, error="No lot found")
    
    if os.path.exists(lot_metadata_file_fullpath):
        is_lot_metadata = True
        lot_metadata, last_lot_metadata = JndUtil.load_jnd_lot_metadata(lot_metadata_file_fullpath)
        Log.INFO(f"Lot metadata file is available={lot_metadata_file_fullpath}")
    else:
        Log.WARN(f"Lot metadata file {lot_metadata_file_fullpath} does not exist.")
        is_lot_metadata = False
    
    onlotprod_url = f"{ws_urls['onlotprod']}/{raw_lot}"
    
    if raw_lot.startswith('7G'):
        jm_lot = JndUtil.jnd_7G_to_jm(raw_lot)
        if jm_lot:
            onlotprod_url = f"{ws_urls['onlotprod']}/{jm_lot}"
            
    Log.INFO(f"ON_LOT_PROD_URL={onlotprod_url}")
    onlotprod_metadata = refdb_api_client.get_metadata(onlotprod_url, default_onlot_prod, ws_timeout)
    if onlotprod_metadata['onLot']['status'].upper() in ['ERROR', 'NO_LOTG', 'NOLOTG', 'NO_DATA', 'NODATA'] and is_lot_metadata:
        Log.INFO("No LotG info found from refdb, will try to get from lot metadata")
               
        if raw_lot in lot_metadata:
            Log.INFO(f"Metadata from lot={raw_lot} metadata -> {filename}")
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'product', lot_metadata[raw_lot].get('TPNO'))  
            source_mapping['onLot']['product'] = "SCRIPT_LOT_METADATA"
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'parentLot', lot_metadata[raw_lot].get('ParentLot'))
            source_mapping["onLot"]["parentLot"] = "SCRIPT_LOT_METADATA"   
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'lotType', lot_metadata[raw_lot].get('LotTYpe'))   
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'fab', lot_metadata[raw_lot].get('Fab'))
            source_mapping["onLot"]["fab"] = "SCRIPT_LOT_METADATA"
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'sourceLot', lot_metadata[raw_lot].get('SourceLot'))
            source_mapping["onLot"]["sourceLot"] = "SCRIPT_LOT_METADATA"
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'process', lot_metadata[raw_lot].get('Process'))
            source_mapping["onProd"]["process"] = "SCRIPT_LOT_METADATA"
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'technology', lot_metadata[raw_lot].get('Technology'))
            source_mapping["onProd"]["technology"] = "SCRIPT_LOT_METADATA"
        elif last_lot_metadata:
            Log.INFO(f"Metadata from last lot {last_lot_metadata} metadata -> {filename}")
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
            onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, 'technology', last_lot_metadata.get('Technology'))
            source_mapping["onProd"]["technology"] = "SCRIPT_LOT_METADATA"
        else:
            Log.INFO("No LotG and no lot metadata.")
            # writer_instance.noMeta = True
    else:
        Log.INFO("OnLot, OnProd metadata found in ERT.")
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
            Log.INFO(f"No Technology from refdb and lot metadata.")
            # writer_instance.noMeta = True - commented out to load to PRODUCTION schema even if there is no Technology and/or Lot type
        
    onlotprod_metadata = Util.replace_dict_value(onlotprod_metadata, "sourceLot", jnd_sourceLot)

    lot_wafer_key = f"{raw_lot}_{raw_wafer_number}"

    default_onscribe_metadata = Util.replace_dict_value(default_onscribe_metadata, 'lot', raw_lot)
    default_onscribe_metadata = Util.replace_dict_value(default_onscribe_metadata, 'waferNum', raw_wafer_number)
    default_onlot_metadata = Util.replace_dict_value(default_onlot_metadata, 'lot', raw_lot)
    default_onlot_metadata = Util.replace_dict_value(default_onlot_metadata, "sourceLot", jnd_sourceLot)
    onscribe_metadata = default_onscribe_metadata
    onscribe_metadata = Util.update_wafer_id(onscribe_metadata, jnd_sourceLot, raw_wafer_number)
    waferid = onscribe_metadata.get('waferId', 'NA')

    if Util.looks_like_number(raw_wafer_number):
        waferid = JndUtil.get_waferid_scribe_file(raw_lot, raw_wafer_number, waferids)
        if waferid == 'NA':
            if raw_lot.startswith('EQ'):
                if e_raw_lot_wafer_scribe != "NA":
                    Log.INFO(f"Use UserText attribute value={e_raw_lot_wafer_scribe} from Lot section as scribe.")
                    waferid = e_raw_lot_wafer_scribe
                    if lot_wafer_key not in new_waferids:
                        new_waferids[lot_wafer_key] = waferid
                        Log.INFO(f"WAFERID from User/Text attribute={waferid} will be used.")
                        onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'status', "MANUAL")
                        onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'waferId', waferid)
                        source_mapping["onScribe"]["waferId"] = "SCRIPT_SXML_FILE"
                        onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'scribeId', waferid)
                        source_mapping["onScribe"]["scribeId"] = "SCRIPT_SXML_FILE"
                else:
                    Log.INFO("UserText value is NA, to SANDBOX")
                    writer_instance.noMeta = True
            else:
                onscribe_metadata, new_lot_wafer_key = JndUtil.get_jnd_onscribe_metadata(refdb_api_client, ws_urls, jnd_sourceLot, waferids, raw_lot, raw_wafer_number, default_onscribe_metadata, default_onlot_metadata)
                waferid = onscribe_metadata.get('waferId', 'NA')
                if isinstance(onscribe_metadata, dict) and onscribe_metadata['status'].upper() == 'MANUAL':
                    for key in [new_lot_wafer_key, lot_wafer_key]:
                        if key not in new_waferids:
                            new_waferids[key] = waferid
                else:
                    Log.INFO(f"for this lot={raw_lot} No waferid from ERT and reference file, CALCULATED WAFERID will be used, to SANDBOX")
                    writer_instance.noMeta = True
        else:
            Log.INFO(f"WAFERID from Scribe/ShipScribe reference file={waferid} will be used.")
            onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'status', "MANUAL")
            onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'waferId', waferid)
            source_mapping["onScribe"]["waferId"] = "SCRIPT_SCRIBE_REF_FILE"
            onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'scribeId', waferid)
            source_mapping["onScribe"]["scribeId"] = "SCRIPT_SCRIBE_REF_FILE"
    else:
        Log.INFO("Wafer number from raw file's SublotId may not be a valid number")
        dp_exit(1, pplogger=pplogger, error="Wafer number from raw file may not be a valid number")    

    if onscribe_metadata.get("scribeId") is None:
        writer_instance.noMeta = True
        Log.INFO("No scribe information, to SANDBOX")
        onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'scribeId', onscribe_metadata.get("waferId"))
        source_mapping["onScribe"]["scribeId"] = "SCRIPT_FORMATTED_SOURCELOT-WAFERNUMBER"
    
    pplogger.set_waf_num(onscribe_metadata.get("scribeId"), site)
                
    stats = model.wafers[0].stats()
    wmap = Wmap(stats)
    wmap.wf_units = yaml_data['Tesec']['WmcWaferUnits']
    wmap.flat = yaml_data['Tesec']['WmcWaferFlat']
    wmap.flat_type = yaml_data['Tesec']['WmcFlatType']
    wmap.positive_x = yaml_data['Tesec']['WmcPositiveX']
    wmap.positive_y = yaml_data['Tesec']['WmcPositiveY']
    
    
    if raw_lot.startswith('EQ'):
        recipe_from_stdf = str(stdml_lot_section.get('JobName')).upper()
        Log.INFO(f"JobName={recipe_from_stdf}")
        get_tpno_from_device = lambda recipe_from_stdf: str(recipe_from_stdf.split('-')[1].split('_')[0].split('.')[0]) if '-' in recipe_from_stdf else "Invalid format"
        tpno = get_tpno_from_device(recipe_from_stdf)
        Log.INFO(f"TPNO extracted from JobName={tpno}, indicates Lot starts with EQ={raw_lot}")
    else:
        if is_lot_metadata and (tpno == "Invalid TPNO" or not tpno.isalnum()):
            tpno = lot_metadata[raw_lot].get('TPNO')
            Log.INFO(f"TPNO={tpno} came from lot metadata={lot_metadata_file_fullpath}, indicates tpno from filename is not valid")

    if tpno.isalnum() and len(tpno) >= 4 and tpno != "Invalid TPNO":
        fjm = JndUtil.find_first_jnd_fjm_file(fjm_location, tpno)
        Log.INFO(f"FJM={fjm} || TPNO={tpno}")
    else:
        Log.WARN(f"TPNO={tpno} extracted is not valid, cant get fjm file and cant enrich with wmc.")
        writer_instance.noMeta = True
    
    if fjm:
        Log.INFO(f"Try to enrich wmc from FJM file={fjm}")
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
        
    constant_mapping_data = yaml_data['Tesec']['constant_mapping_value']
    combined_metadata = {
        **onlotprod_metadata,
        'onScribe': onscribe_metadata,
        'stdml': stdml_lot_section,
        'constant': constant_mapping_data,
        'wmc': wmc_dictionary
    }
    metadataDTO_instance = MetadataDTO(field_mapping=field_mapping, source_mapping=source_mapping)
    metadata = metadataDTO_instance.generate_metadata_xml(combined_metadata)
    tesec_sxml_enricher = SxmlEnricher(input_file)
    enriched_tesec_xml = tesec_sxml_enricher.enrich_xml(metadata)
    sxml_instance = SXML(writer=writer_instance, sxml=enriched_tesec_xml)
    sxml_instance.write_list_of_line_string_to_file()
    
    if new_waferids:
        JndUtil.append_to_jnd_scribe_file_if_not_exists(new_waferids, scribe_file)
    else:
        Log.INFO("No new waferid/s that is/are not calculated, and from ERT")

    dp_exit(0, pplogger=pplogger)

if __name__ == '__main__':
    main()