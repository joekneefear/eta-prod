#!/usr/bin/env python3.12

"""

SYNOPSIS

DESCRIPTION
    Qorvo PSI CSV Parser

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2025-Mar-11 - jgarcia - initial
    2026-Jan-16 - jgarcia - updated parser instantiation to pass command line arguments (args=params)
    2026-Mar-18 - jgarcia - extract equipment token from filename with normalization

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
from lib.Parser.QorvoPsiParser import QorvoPsiParser
from lib.WS.RefdbAPIClient import RefdbAPIClient
from lib.Data.Model import Model
from lib.DbConnection import DbConnection
from lib.DbConnectionFactory import DbConnectionFactory
from lib.PPLogger import PPLogger

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
    db_config = None
    # db_connection = DbConnectionFactory.create_db_connection(db_type)
    db_connection = DbConnectionFactory.create_db_connection(db_type, db_config)
    db_session = db_connection.get_session()
   
    model = Model()
    log_file = initialize_log_file()
    pplogger = PPLogger()
    pplogger.set_to_be_logged(False)
    is_apply_exclude_params = False
    Log.configure_logger(log_file=log_file, pplogger=pplogger)
    model = Model()
    
    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)
    
    if params.get('pplog'):
        Log.INFO(f"set to log into refdb pp_log")
        # print(f"set to log into refdb pp_log")
        pplogger.set_to_be_logged(True)
        pplogger.set_db(db_session)
    else:
        Log.INFO(f"Not set be to logged into refdb.pp_log")
    
    if len(sys.argv) < 2:
        Log.INFO("No input file specified!!!")
        dp_exit(1, pplogger=pplogger, error="No input file specified!!!")
    
    fabsite = params['site']
    fab, site = fabsite.split('_')
    outbox = params['out']
    processing_step = params['pstep']
    processing_step = Util.rep_na(processing_step)
    if params.get('exclude_params'):
        is_apply_exclude_params = True
    input_file = params['infile']
    config_file = params.get('config_file', '/export/home/dpower/project/scripts/py/resources/xFCS_FACILITY_MAPPING.yaml')
    config_data = Util.load_yaml(config_file)
    env = config_data[fabsite][processing_step]['env']
    excluded_parameter_list = None
    
    if is_apply_exclude_params:
        excluded_parameter_list = config_data[fabsite][processing_step]['excluded_parameters']
        Log.INFO(f"Excluded Parameters={excluded_parameter_list}")
    
    Log.INFO(f"Input file={input_file}")
    Log.INFO(f'Outbox={outbox}')
    pplogger.set_raw_file(input_file)
    pplogger.set_env(env)
    pplogger.set_site(site)
    pplogger.set_script(os.path.basename(__file__))
    
    parser = QorvoPsiParser(args=params, pplogger=pplogger)
   
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
        ext='iff',
        gzipIFF=True,
        pplogger=pplogger
    )
    
    if processing_step == 'QA' or processing_step == "FT":
        model = parser.parse_to_model(output, processing_step, excluded_parameter_list)
    elif processing_step == 'RG':
        model = parser.parse_to_model_RG(output, excluded_parameter_list)
    
    model.header.PROCESSING_STEP = processing_step
    model.header.FAB = fab
    model.header.FACILITY = site
    model.header.TEST_FACILITY = site
    program_name = f"{site}_{model.header.PRODUCT}_{model.header.RECIPE}_{model.header.PROCESSING_STEP}"
    Log.INFO(f"Program Name={program_name}")
    Log.INFO(f"Program Revision={model.header.RECIPE_REVISION}")
    model.header.DATA_FILE_NAME = os.path.basename(output)
    model.header.AREA = "FT"
    model.header.PROGRAM_CLASS = 2
    model.header.PROGRAM = program_name

    pplogger.set_model_header(model)
    # pplogger.set_waf_num(model.wafers[0].name)
    model.build_limit()

    iff_args = {
        'writer': writer,
        'model': model
    }
    
    iff_instance = IFF(iff_args)
    
    iff_instance.data_items = ['partid', 'site', 'soft_bin', 'hard_bin', 'bindesc', 'touchdown_num', 'ecid']
    iff_instance.test_items = ['number', 'name', 'units']
    iff_instance.bin_items = ['number', 'name', 'PF', 'count']
    iff_instance.print_par()
    iff_instance.print_limit()
    pplogger.set_limit_file(model.limit.limit_file)

    # Util.dp_exit(0, pplogger)
    dp_exit(0, pplogger=pplogger)

if __name__ == '__main__':
    main()
