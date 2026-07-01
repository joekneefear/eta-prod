#!/usr/bin/env python3.12

"""
SYNOPSIS
    shedcl_ft_dts1k2k_xls_translator.py [options]

DESCRIPTION
    DTS1000/DTS2000 (JUNO) XLS/CSV Translator and Enricher for SHEDCL.
    
    Parses DTS1000/DTS2000 Excel or CSV test data files and converts
    to IFF format with metadata enrichment from RefDB.
    
    This script is specifically tuned for SHEDCL requirements:
    - Extracts Lot ID, Device, and Control from the filename.
    - Uses file modification time for Start/End timestamps.
    - Maps TestFileName to Program Name with customized revision logic.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2026-Jan-30 - Refined to match dts1000_juno_translator_enricher.py structure
"""

import sys
import os
import re
import gzip
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
    """
    # Use site-specific config file if provided, otherwise fallback to the one we created
    resource_dir = os.path.join(os.path.dirname(__file__), 'resources')
    parser_config_file = params.get(
        'parser_config',
        os.path.join(resource_dir, 'dts1k2k_custom_parsers.yaml')
    )
    
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
    config_data = {}
    if os.path.exists(config_file):
        config_data = Util.load_yaml(config_file)
    
    # Validate environment
    refdb_env = params.get('env', None)
    if refdb_env not in valid_envs and refdb_env is not None:
        Log.ERROR(f"Invalid environment: {refdb_env}")
        Util.dp_exit(1, pplogger=pplogger, error="Invalid environment: " + str(refdb_env).upper() + "!")
    
    if refdb_env is not None and site in config_data:
        db_config = config_data[site]['refdb'][refdb_env]
    
    # Get parameters
    outbox = params.get('out', '.')
    input_file = params['infile']
    
    Log.INFO(f"Input file={input_file}")
    Log.INFO(f'Outbox={outbox}')
    Log.INFO(f"Site={site}")
    
    if refdb_env is not None:
        Log.INFO(f"refdb environment={str(refdb_env).upper()}--DB type={db_type.upper()}")
    else:
        Log.INFO(f"refdb environment will be set based on what ETL server this script runs.--DB type={db_type.upper()}")
    
    # Initialize database connection
    if db_config:
        db_connection = DbConnectionFactory.create_db_connection(db_type, db_config)
        db_session = db_connection.get_session()
        pplogger.set_db(db_session)
    
    # Get facility and configure web service
    facility = 'SHEDCL'
    env = 'shedcl_dts1k2k'
    
    if site in config_data:
        # Try proper keys from YAML (finalTest only)
        facility = config_data[site].get('finalTest', 'SHEDCL')
        if facility and ':' in facility:
            facility = facility.split(':')[0]
        # Get env from config if available
        env = config_data[site].get('env', env)
    
    pplogger.set_raw_file(input_file)
    pplogger.set_program_class("2")
    pplogger.set_md5()
    pplogger.set_env(env)
    pplogger.set_site(site)
    pplogger.set_script(os.path.basename(__file__))
    
    # Configure web service URLs
    ws_url = None
    onlotprod_base_url = None
    
    if site in config_data:
        ws_url = config_data[site].get('ws_url')
        onlotprod_base_url = config_data[site].get('onLotProd')
        
    onlotprod_metadata = None
    if ws_url and os.path.exists(ws_url):
        ws_source = params.get('ws_source', 'prod')
        ws_url_ref_data = Util.load_yaml(ws_url)
        ert_urls = Util.configure_ws_urls(ws_source, ws_url_ref_data)
        
        # Override onlotprod URL if specified in site config
        if onlotprod_base_url:
            ert_urls['onlotprod'] = onlotprod_base_url
        
        # Configure web service client
        ws_retries = config_data.get('WS_Refdb_Client', {}).get('retries', 3)
        ws_backoff_factor = config_data.get('WS_Refdb_Client', {}).get('backoff_factor', 0.5)
        ws_status_forcelist = config_data.get('WS_Refdb_Client', {}).get('status_forcelist', [500, 502, 503, 504])
        ws_timeout = config_data.get('WS_Refdb_Client', {}).get('timeout', 10)
        default_onlot_prod = config_data.get('default_onlot_prod', {})
        
        ert_api_client = RefdbAPIClient(
            retries=ws_retries, 
            backoff_factor=ws_backoff_factor, 
            status_forcelist=tuple(ws_status_forcelist)
        )
        
        # We'll fetch after parsing
    
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
    
    # Initialize writer
    writer = Writer(
        outdir=outbox,
        basename=os.path.basename(output),
        ext='IFF',
        gzipIFF=True,
        pplogger=pplogger
    )
    
    # Parse file
    Log.INFO("Parsing DTS1000/DTS2000 file...")
    model = parser.parse_to_model(output)
    
    # Get metadata from web service if configured
    if 'ert_api_client' in locals() and model.header.LOT:
        # If explicit onLotProd URL is used, it might already include 'bylotid/' or similar, or it might be a base.
        # Standard ert_urls['onlotprod'] usually expects appending /<lotID>.
        # Based on config: "http://.../api/onlotprod/bylotid/" which ends in /
        # so we append the LOT.
        
        # Ensure we don't double slash if base ends with /
        base_url = ert_urls['onlotprod']
        if base_url.endswith('/'):
            onlotprod_url = f"{base_url}{model.header.LOT}"
        else:
            onlotprod_url = f"{base_url}/{model.header.LOT}"
            
        onlotprod_metadata = ert_api_client.get_metadata(onlotprod_url, default_onlot_prod, ws_timeout)
    
    model.header.TEST_FACILITY = facility
    
    # Populate metadata
    metadata_source = params.get('metadata_source', 'ERT')
    if re.search(r'ERT', metadata_source, re.IGNORECASE) and onlotprod_metadata:
        if not model.header.populate_metadata_ert(onlotprod_metadata):
            if not params.get('force_prd'):
                writer.noMeta = True
            else:
                Log.INFO("NO Metadata found but setup to be loaded to PRODUCTION.")
                Log.INFO(f"LOT={model.header.LOT}--SOURCE_LOT={model.header.SOURCE_LOT}")
    else:
        if not model.header.populate_metadata():
            if not params.get('force_prd'):
                writer.noMeta = True
            else:
                Log.INFO("NO Metadata found but setup to be loaded to PRODUCTION.")
            Log.INFO(f"LOT={model.header.LOT}")
            model.header.SOURCE_LOT = Util.formatSourceLot(model.header.SOURCE_LOT, model.header.LOT)
    
    # Set additional header fields
    model.header.DATA_FILE_NAME = os.path.basename(output)
    model.header.AREA = "FT"  # Final Test
    model.header.PROGRAM_CLASS = 2
    
    # Construct PROGRAM name: <TestFacilityCode>_<Product>_<Recipe>:<ProcessingStep>
    # Use NA as placeholder for missing values
    facility_val = model.header.TEST_FACILITY if model.header.TEST_FACILITY else 'SHEDCL'
    product_val = model.header.PRODUCT if model.header.PRODUCT else 'NA'
    recipe_val = getattr(model.header, 'RECIPE', None) or model.header.PROGRAM or 'NA'
    processing_step = getattr(model.header, 'PROCESSING_STEP', 'NA')
    
    model.header.PROGRAM = f"{facility_val}_{product_val}_{recipe_val}:{processing_step}"
    revision = getattr(model.header, 'RECIPE_REVISION', None) or getattr(model.header, 'REVISION', 'NA')
    Log.INFO(f"LOT={model.header.LOT}--PRODUCT={model.header.PRODUCT}--PROGRAM={model.header.PROGRAM}--REVISION={revision}")

    # Set wafer flag if source lot exists
    if model.header.SOURCE_LOT:
        pplogger.set_wafer_flag(True)
    
    pplogger.set_model_header(model)
    
    # Build limit and sync with header so limit has same Program, Program class, revision as IFF
    model.build_limit()
    model.limit.copy_header(model.header)
    model.limit.testItems = ['number', 'name', 'units']  # keep in sync with iff_instance.test_items
    model.limit.input_file = os.path.basename(output)  # set before print_limit so it appears in the file
    
    # Create IFF formatter
    iff_args = {
        'writer': writer,
        'model': model
    }
    
    iff_instance = IFF(iff_args)
    
    # Configure IFF output with detailed data items, test items, and bin items
    iff_instance.data_items = ['partid', 'site', 'soft_bin', 'hard_bin', 'bindesc', 'touchdown_num', 'ecid']
    iff_instance.test_items = ['number', 'name', 'units']
    iff_instance.bin_items = ['number', 'name', 'PF', 'count']
    
    # Generate IFF files
    if not params.get('refdb_only'):
        iff_instance.print_par_per_wafer_number()
        iff_instance.print_limit()
    pplogger.set_limit_file(model.limit.limit_file)
    pplogger.set_out_dir(writer.outdir)
    
    Log.INFO(f"Processing complete. Output written to {writer.outdir}")
    Log.INFO(f"Tests: {len(model.tests)}, Dies: {len(model.wafers[0].dies)}, Bins: {len(model.wafers[0].bins)}")
    
    Util.dp_exit(0, pplogger)


if __name__ == '__main__':
    main()
