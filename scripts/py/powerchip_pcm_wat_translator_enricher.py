#!/usr/bin/env python3.12

"""

SYNOPSIS

DESCRIPTION
    POWERCHIP WAT

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2025-April-03 - jgarcia - initial

LICENSE
    (C) onsemi 2025 All rights reserved.
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
from lib.Parser.PowerchipWatParser import PowerchipWatParser
from lib.PPLogger import PPLogger
from lib.WS.RefdbAPIClient import RefdbAPIClient
from lib.DbConnectionFactory import DbConnectionFactory
from lib.Service.PowerchipEpiScribeService import PowerchipEpiScribeService
from lib.Data.Model import Model

def initialize_log_file():
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

def main():
    dp_exit = Util.dp_exit
    db_type = 'oracle'
    
    log_file = initialize_log_file()
    pplogger = PPLogger()
    pplogger.set_to_be_logged(False)
    Log.configure_logger(log_file=log_file, pplogger=pplogger)
    insert_epi_scribe_flag = False
    platform = ""
    valid_envs = {"prod", "qa", "dev"}
    db_config = None
    
    
    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)
    
    if params.get('pplog'):
        Log.INFO(f"set to log into refdb pp_log")
        # print(f"set to log into refdb pp_log")
        pplogger.set_to_be_logged(True)
    else:
        Log.INFO(f"Not set be to logged into refdb.pp_log")
        
    
    if len(sys.argv) < 2:
        Log.INFO("No input file specified!!!")
        dp_exit(1, pplogger=pplogger, error="No input file specified!!!")
    
    site = params['site']
    
    config_file = params.get('config_file', '/export/home/dpower/project/scripts/py/resources/xFCS_FACILITY_MAPPING.yaml')
    config_data = Util.load_yaml(config_file)
    
    refdb_env = params.get('env', None)
    if refdb_env not in valid_envs and refdb_env is not None:
        Log.ERROR(f"Invalid environment: {refdb_env}")
        Util.dp_exit(1, pplogger=pplogger, error="Invalid environment: " + str(refdb_env).upper() + "!")
    
    if refdb_env is not None:
        db_config = config_data[site]['refdb'][refdb_env]
    
    if params.get('insert_scribe'):
        Log.INFO(f"Set to insert scribe info to refdb.on_scribe")
        insert_epi_scribe_flag = True
    
    outbox = params['out']
    input_file = params['infile']
    Log.INFO(f"Input file={input_file}")
    Log.INFO(f'Outbox={outbox}')
    Log.INFO(f"Site={site}")
    if refdb_env is not None:
        Log.INFO(f"refdb environment={str(refdb_env).upper()}--DB type={db_type.upper()}")
    else:
        Log.INFO(f"refdb environment will be set based on what ETL server this script runs.--DB type={db_type.upper()}")
    
    
    
    db_connection = DbConnectionFactory.create_db_connection(db_type, db_config)
    db_session = db_connection.get_session()
    pplogger.set_db(db_session)
    powerchip_epi_scribe_service = PowerchipEpiScribeService(db_session, pplogger)
    
    if params.get('platform'):
        platform = params['platform']
        
    facility = config_data[site]['probe']
    pplogger.set_raw_file(input_file)
    pplogger.set_program_class("5")
    pplogger.set_md5()
    pplogger.set_env("powerchip_pcm_wat")
    pplogger.set_site(site)
    pplogger.set_script(os.path.basename(__file__))
    # pplogger.set_program_class(5)
    ws_url = config_data[site]['ws_url']
    ws_source = params['ws_source']
    ws_url_ref_data = Util.load_yaml(ws_url)
    ert_urls = Util.configure_ws_urls(ws_source, ws_url_ref_data)
    onlotprod_url = f"{ert_urls['onlotprod']}"
    epiScribeFile = config_data[site]['epiScribe']
    Log.INFO(f"REF_FILE={epiScribeFile}")
    # epiScribeHashData = Util.xlsx_to_hash(epiScribeFile)
    ws_retries = config_data['WS_Refdb_Client']['retries']
    ws_backoff_factor = config_data['WS_Refdb_Client']['backoff_factor']
    ws_status_forcelist = config_data['WS_Refdb_Client']['status_forcelist']
    ws_timeout = config_data['WS_Refdb_Client']['timeout']
    default_onlot_prod = config_data['default_onlot_prod']
    ert_api_client = RefdbAPIClient(retries=ws_retries, backoff_factor=ws_backoff_factor, status_forcelist=tuple(ws_status_forcelist))
    model = Model()
    
    parser = PowerchipWatParser(pplogger=pplogger)
    epiScribeHashData = parser.epi_scribe_file_to_dict(epiScribeFile)
    
    output = input_file
    if input_file.endswith('.gz'):
        output = input_file[:-3]
        with gzip.open(input_file, 'rb') as f_in:
            with open(output, 'wb') as f_out:
                f_out.write(f_in.read())
        Log.INFO(f"gunzipped file = {output}")
    Log.INFO(f"INPUT FILE={output}")
    
    writer = Writer(
        outdir=outbox,
        basename=os.path.basename(output),
        ext='IFF',
        gzipIFF=True,
        pplogger=pplogger
    )

    header = parser.extract_header(output)
    onlotprod_url = f"{onlotprod_url}/{header.LOT}"
    # Log.INFO(f"ON_LOT_PROD_URL={onlotprod_url}")
    onlotprod_metadata = ert_api_client.get_metadata(onlotprod_url, default_onlot_prod, ws_timeout)
    header.TEST_FACILITY = facility
  
    if re.search(r'ERT', params['metadata_source'], re.IGNORECASE):
        if not header.populate_metadata_ert(onlotprod_metadata):
            if not params.get('force_prd'):
                writer.noMeta = True
            else:
                Log.INFO("NO Metadata found but setup to be loaded to PRODUCTION.")
                Log.INFO(f"LOT={header.LOT}--SOURCE_LOT={header.SOURCE_LOT}")
    else:
        if not header.populate_metadata():
            if not params.get('force_prd'):
                writer.noMeta = True
            else:
                Log.INFO("NO Metadata found but setup to be loaded to PRODUCTION.")
            Log.INFO(f"LOT={header.LOT}")
            header.SOURCE_LOT = Util.formatSourceLot(header.SOURCE_LOT, header.LOT)

    model = parser.read_file(output, header, platform, site, epiScribeHashData)
    
    # model.header.SOURCE_LOT = Util.formatSourceLot(model.header.SOURCE_LOT, model.header.LOT)
    program_name = f"PCM_{site}_{model.header.RECIPE}_{model.header.RECIPE_REVISION}"
    Log.INFO(f"Program Name={program_name}")
    # print(f"Program Name={program_name}")
    Log.INFO(f"Program Revision={model.header.RECIPE_REVISION}")
    # print(f"Program Revision={model.header.RECIPE_REVISION}")
    model.header.DATA_FILE_NAME = os.path.basename(output)
    model.header.AREA = "PCM/WAT"
    model.header.PROGRAM_CLASS = 5
    model.header.PROGRAM = program_name
    if not model.header.FAB or model.header.FAB == 'NA':
        model.header.FAB = "POWERCHIP"
    # model.wafers[0].name = waferid
    if model.header.SOURCE_LOT:
        pplogger.set_wafer_flag(True)
    
    pplogger.set_model_header(model)
    # fmt = IFF(model=model, writer=writer)
    # print(f"{model.wafers}")
    model.misc
    model.build_limit()
    
    iff_args = {
        'writer': writer,
        'model': model
    }
    
    iff_instance = IFF(iff_args)
    
    iff_instance.data_items = ['x', 'y', 'site']
    iff_instance.test_items = ['number', 'name', 'units', 'critical']
    if not params.get('refdb_only'):
        iff_instance.print_par_per_wafer_number()
        iff_instance.print_limit()
    
    # iff_instance.print_limit()
    model.limit.input_file = os.path.basename(output)
    pplogger.set_limit_file(model.limit.limit_file)
    pplogger.set_out_dir(writer.outdir)
    
    if model.misc and insert_epi_scribe_flag:
        powerchip_epi_scribe_service.insert_epi_scribe_data(model)
    else:
        if not model.misc:
            Log.INFO(f"PCM raw file doesn't have epi scribe information.")
        else:
            Log.INFO(f"Not setup to insert epi scribe infor to refdb.on_scribe.")

    Util.dp_exit(0, pplogger)

if __name__ == '__main__':
    main()
