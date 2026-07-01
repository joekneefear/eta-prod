#!/usr/bin/env python3.12

"""

SYNOPSIS

DESCRIPTION
    DTS1000/DTS2000 (JUNO) XLS/CSV Translator and Enricher
    
    Parses DTS1000/DTS2000 Excel or CSV test data files and converts
    to IFF format with metadata enrichment from RefDB.
    
    Supports custom field extraction for lot ID decomposition,
    test program parsing, and file timestamp extraction.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2026-Jan-29 - Initial implementation

LICENSE
    (C) onsemi 2026 All rights reserved.
"""


import sys
import os
import re
import gzip
import logging
from configparser import ConfigParser
from lib.Log import Log
from lib.Util import Util
from lib.Writer import Writer
from lib.Formatter.IFF import IFF
from lib.Parser.Dts1k2kXlsParser import Dts1k2kXlsParser
from lib.Config.Dts1k2kParserConfig import Dts1k2kParserConfig

from lib.PPLogger import PPLogger
from lib.WS.RefdbAPIClient import RefdbAPIClient
from lib.DbConnectionFactory import DbConnectionFactory
from lib.Data.Model import Model


def initialize_log_file():
    """Initialize log file path from command line arguments or default."""
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


def configure_parser_from_yaml(params, site):
    """
    Configure parser using YAML configuration file.
    
    Args:
        params: Dictionary of command-line parameters
        site: Site name
        
    Returns:
        Dts1k2kParserConfig configured from YAML or None for default parsing
    """
    # Get YAML config file path
    default_config = '/export/home/dpower/project/scripts/py/resources/dts1k2k_custom_parsers.yaml'
    parser_config_file = params.get('parser_config', default_config)
    
    # Ensure parser_config_file is a valid string path (not True/False from flag parsing)
    if not isinstance(parser_config_file, str) or parser_config_file is True:
        Log.WARN(f"Invalid parser config path: {parser_config_file}. Using default.")
        parser_config_file = default_config
    
    # Check if file exists
    if not os.path.exists(parser_config_file):
        Log.WARN(f"Parser config file not found: {parser_config_file}")
        Log.INFO("Using default parsing (no custom extractors)")
        return None
    
    # Create config from YAML
    Log.INFO(f"Loading parser configuration from: {parser_config_file}")
    config = Dts1k2kParserConfig(config_file=parser_config_file, site=site)
    
    return config



def main():
    dp_exit = Util.dp_exit
    db_type = 'oracle'
    
    log_file = initialize_log_file()
    pplogger = PPLogger()
    pplogger.set_to_be_logged(False)
    Log.configure_logger(log_file=log_file, pplogger=pplogger)
    
    valid_envs = {"prod", "qa", "dev"}
    db_config = None
    
    # Process command line arguments
    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)
    
    if params.get('pplog'):
        Log.INFO("Set to log into refdb pp_log")
        pplogger.set_to_be_logged(True)
    else:
        Log.INFO("Not set to be logged into refdb.pp_log")
    
    # Validate required arguments
    if len(sys.argv) < 2:
        Log.INFO("No input file specified!!!")
        dp_exit(1, pplogger=pplogger, error="No input file specified!!!")
    
    site = params.get('site', 'SHEDCL')
    
    # Load configuration
    config_file = params.get('config_file', '/export/home/dpower/project/scripts/py/resources/xFCS_FACILITY_MAPPING.yaml')
    config_data = Util.load_yaml(config_file)
    
    # Validate environment
    refdb_env = params.get('env', None)
    if refdb_env not in valid_envs and refdb_env is not None:
        Log.ERROR(f"Invalid environment: {refdb_env}")
        Util.dp_exit(1, pplogger=pplogger, error="Invalid environment: " + str(refdb_env).upper() + "!")
    
    if refdb_env is not None:
        db_config = config_data[site]['refdb'][refdb_env]
    
    # Get parameters
    outbox = params['out']
    input_file = params['infile']
    
    Log.INFO(f"Input file={input_file}")
    Log.INFO(f'Outbox={outbox}')
    Log.INFO(f"Site={site}")
    
    if refdb_env is not None:
        Log.INFO(f"refdb environment={str(refdb_env).upper()}--DB type={db_type.upper()}")
    else:
        Log.INFO(f"refdb environment will be set based on what ETL server this script runs.--DB type={db_type.upper()}")
    
    # Initialize database connection
    db_connection = DbConnectionFactory.create_db_connection(db_type, db_config)
    db_session = db_connection.get_session()
    pplogger.set_db(db_session)
    
    # Get facility and configure web service
    facility = config_data[site].get('final_test', config_data[site].get('probe', 'JUNO'))
    pplogger.set_raw_file(input_file)
    pplogger.set_program_class("5")
    pplogger.set_md5()
    pplogger.set_env("dts1000_juno")
    pplogger.set_site(site)
    pplogger.set_script(os.path.basename(__file__))
    
    # Configure web service URLs
    ws_url = config_data[site]['ws_url']
    ws_source = params['ws_source']
    ws_url_ref_data = Util.load_yaml(ws_url)
    ert_urls = Util.configure_ws_urls(ws_source, ws_url_ref_data)
    onlotprod_url = f"{ert_urls['onlotprod']}"
    
    # Configure web service client
    ws_retries = config_data['WS_Refdb_Client']['retries']
    ws_backoff_factor = config_data['WS_Refdb_Client']['backoff_factor']
    ws_status_forcelist = config_data['WS_Refdb_Client']['status_forcelist']
    ws_timeout = config_data['WS_Refdb_Client']['timeout']
    default_onlot_prod = config_data['default_onlot_prod']
    ert_api_client = RefdbAPIClient(
        retries=ws_retries, 
        backoff_factor=ws_backoff_factor, 
        status_forcelist=tuple(ws_status_forcelist)
    )
    
    # Configure parser from YAML (site-specific rules)
    parser_config = configure_parser_from_yaml(params, site)
    
    # Initialize parser with YAML configuration and pplogger
    parser = Dts1k2kXlsParser(config=parser_config, pplogger=pplogger)

    
    # Handle gzipped files
    output = input_file
    if input_file.endswith('.gz'):
        output = input_file[:-3]
        with gzip.open(input_file, 'rb') as f_in:
            with open(output, 'wb') as f_out:
                f_out.write(f_in.read())
        Log.INFO(f"gunzipped file = {output}")
    
    Log.INFO(f"INPUT FILE={output}")
    Log.INFO(f"ORIGINAL FILENAME (for metadata extraction)={input_file}")
    
    # Initialize writer
    writer = Writer(
        outdir=outbox,
        basename=os.path.basename(output),
        ext='IFF',
        gzipIFF=True,
        pplogger=pplogger
    )
    
    # Parse file - pass ORIGINAL filename for metadata extraction
    Log.INFO("Parsing DTS1000/DTS2000 file...")
    model = parser.parse_to_model(output, original_filename=input_file)
    
    # Get metadata from web service
    onlotprod_url = f"{onlotprod_url}/{model.header.LOT}"
    onlotprod_metadata = ert_api_client.get_metadata(onlotprod_url, default_onlot_prod, ws_timeout)
    model.header.TEST_FACILITY = facility
    
    # Populate metadata from ERT or RefDB
    has_meta = False
    if re.search(r'ERT', params['metadata_source'], re.IGNORECASE):
        has_meta = model.header.populate_metadata_ert(onlotprod_metadata)
    else:
        has_meta = model.header.populate_metadata()
    
    # Handle missing metadata
    if not has_meta:
        if not params.get('force_prd'):
            writer.noMeta = True
        else:
            Log.INFO("No metadata found, but configured to load to production (force_prd=True)")
        
        Log.INFO(f"Meta NOT found for LOT={model.header.LOT}")
    else:
        Log.INFO(f"Meta found for LOT={model.header.LOT}")

    # Always ensure SOURCE_LOT is formatted (fallback to LOT.S if still NA)
    model.header.SOURCE_LOT = Util.formatSourceLot(model.header.SOURCE_LOT, model.header.LOT)
    Log.INFO(f"Final SOURCE_LOT={model.header.SOURCE_LOT}")
    
    # Set additional header fields
    model.header.DATA_FILE_NAME = os.path.basename(output)
    model.header.AREA = "FT"  # Final Test
    model.header.PROGRAM_CLASS = 5
    
    # Construct program name (PPID) using specific format:
    # <TestFacilityCode>_<Product>_<Recipe>:<RecipeRevision>:<ProcessingStep>:<RetestCode>
    
    # 1. Get TestFacilityCode from facility mapping (e.g., "SHEDCL")
    facility_code = facility.split(':')[0] if ':' in facility else facility
    
    # 2. Get Product (defaulting to NA)
    product = getattr(model.header, 'PRODUCT', 'NA')
    product = product if product and product != 'None' else 'NA'
    
    # 3. Get Recipe from PROGRAM field (extracted from TestFileName by parser)
    #    If parser extracted a program name, use it as Recipe
    recipe = getattr(model.header, 'PROGRAM', 'NA')
    recipe = recipe if recipe and recipe != 'NA' else 'NA'
    
    # 4. Get RecipeRevision (extracted from TestFileName by parser)
    recipe_revision = getattr(model.header, 'RECIPE_REVISION', 'NA')
    recipe_revision = recipe_revision if recipe_revision and recipe_revision != 'NA' else 'NA'
    
    # 5. Get ProcessingStep (defaulting to NA)
    processing_step = getattr(model.header, 'PROCESSING_STEP', 'NA')
    processing_step = processing_step if processing_step and processing_step != 'NA' else 'NA'
    
    # 6. Get RetestCode (defaulting to NA)
    retest_code = getattr(model.header, 'RETEST_CODE', 'NA')
    retest_code = retest_code if retest_code and retest_code != 'NA' else 'NA'
    
    # 7. Construct the final program name string
    program_name = f"{facility_code}_{product}_{recipe}:{recipe_revision}:{processing_step}:{retest_code}"
    
    Log.INFO(f"Constructed Program Name (PPID): {program_name}")
    model.header.PROGRAM = program_name
    
    # Set wafer flag if source lot exists
    if model.header.SOURCE_LOT:
        pplogger.set_wafer_flag(True)
    
    pplogger.set_model_header(model)
    
    # Build limit
    model.build_limit()
    
    # Create IFF formatter
    iff_args = {
        'writer': writer,
        'model': model
    }
    
    iff_instance = IFF(iff_args)
    
    # Configure IFF output
    iff_instance.data_items = ['x', 'y', 'site']
    iff_instance.test_items = ['number', 'name', 'units', 'critical']
    
    # Generate IFF files
    if not params.get('refdb_only'):
        iff_instance.print_par_per_wafer_number()
        iff_instance.print_limit()
    
    model.limit.input_file = os.path.basename(output)
    pplogger.set_limit_file(model.limit.limit_file)
    pplogger.set_out_dir(writer.outdir)
    
    Log.INFO(f"Processing complete. Output written to {writer.outdir}")
    Log.INFO(f"Tests: {len(model.tests)}, Dies: {len(model.wafers[0].dies)}, Bins: {len(model.wafers[0].bins)}")
    
    Util.dp_exit(0, pplogger)


if __name__ == '__main__':
    main()
