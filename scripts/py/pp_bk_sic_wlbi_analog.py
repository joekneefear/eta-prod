#!/usr/bin/env python3.12

"""
SYNOPSIS

DESCRIPTION
    This script read and re-write the klarf defect file after removing/filtering defect list with xy coordinate not in SampleTestPlan.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-May-17 - jgarcia - initial
    2024-Sep-25 - jgarcia - updated shebang to use python3.6
    2024-Sep-26 - jgarcia - refactored to adopt RefdbAPIClient latest changes


LICENSE
    (C) onsemi 2023 All rights reserved.
"""

import pandas as pd
import csv
import sys
import os
import re
from lib.Log import Log
from lib.Util import Util
from lib.WS.RefdbAPIClient import RefdbAPIClient
from lib.PPLogger import PPLogger
from lib.Enricher.SiCWlbiEnricher import SiCWlbiEnricher
from lib.Parser.SiCWlbiParser import SiCWlbiParser
from lib.Writer import Writer
from lib.Formatter.IFF import IFF

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
    # print(f"TEST_LOG_INSIDE={log_file}")
    return log_file

def main():
    log_file = initialize_log_file()
    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)
    if len(sys.argv) < 2:
        Log.INFO(f"No input file specified!!!")
        Util.dp_exit(1,"No input file specified!!!")
    
    input_file=params['infile']
    if not Util.is_csv_file(input_file):
        Log.ERROR(f'Input file={input_file} is not a CSV file. WLBI should be a csv file!!!')
        Util.dp_exit(1,f'Wrong WLBI file provided, not a csv file!!!')

    url_config = params['ws_url']
    ws_source = params['ws_source']
    site = params['site']
    outbox = params['out']
    log_file = params['logfile']
    # Initialize PPLogger and configure Log with it so we can persist to refdb.pp_log
    pplogger = PPLogger()
    pplogger.set_to_be_logged(False)
    Log.configure_logger(log_file=log_file, pplogger=pplogger)
    Log.INFO(f"Input file={input_file}")
    Log.INFO(f'Outbox={outbox}')
    ws_url_ref_data = Util.load_yaml(url_config)
    # Log.INFO(f"WS URL Ref Data: {ws_url_ref_data['refdb'][ws_source]}")
    ws_urls = Util.configure_ws_urls(ws_source, ws_url_ref_data)
   
    
    refdb_api_client = RefdbAPIClient()
    sic_wlbi_parser = SiCWlbiParser(input_file)
    lot = sic_wlbi_parser.get_lotid_from_wlbi_csv()
    Log.INFO(f'Lot got from wlbi csv file={lot}')
    if not lot:
        Log.ERROR('No lotid found in WLBI CSV')
        try:
            pplogger.set_log_msg('No lotid found in WLBI CSV', force=True)
            pplogger.set_raw_file(input_file)
            pplogger.set_site(site)
            pplogger.set_script(os.path.basename(__file__))
            pplogger.set_to_be_logged(True)
        except Exception:
            Log.WARN('Failed to populate PPLogger for missing lot')
        Util.dp_exit(1, pplogger, error='No Lotid')
    on_lot_url = f"{ws_urls['onlot']}"
    Log.INFO(f'Try to get on_lot info from ERT WS={on_lot_url}')
    lot_metadata = sic_wlbi_parser.get_metadata_by_lot(lot, refdb_api_client, on_lot_url)
    
    # Check for error in lot_metadata and retry with alternative URL if necessary
    if lot_metadata is None or 'error' in (lot_metadata.get('status', '') or '').lower() or 'missing' in (lot_metadata.get('errorMessage', '') or '').lower():
        Log.WARN(f"Error in lot metadata: {lot_metadata} using OnLot.")
        Log.INFO(f"Retrying using with PPLOT.")
        # if ws_source.lower() == 'qa':
        #     alt_ws_target_url = yaml_data['refdb']['qa']['pp_lot']
        # elif ws_source.lower() == 'prod':
        #     alt_ws_target_url = yaml_data['refdb']['prod']['pp_lot']
        # refdb_api_client = RefdbAPIClient(alt_ws_target_url)
        pp_lot_url = f"{ws_urls['pplot']}"
        lot_metadata = sic_wlbi_parser.get_metadata_by_lot(lot, refdb_api_client, pp_lot_url)
    
    wlbi_enricher = SiCWlbiEnricher(lot, lot_metadata, site, 'NA')
    try:
        model = wlbi_enricher.enrich_wlbi_srcLot_probe_card_load_board_fill_na(input_file)
    except Exception as e:
        # Ensure pp_log captures the failure and exit
        try:
            pplogger.set_log_msg(str(e), force=True)
            pplogger.set_to_be_logged(True)
        except Exception:
            Log.WARN('Failed to populate PPLogger for lotid error')
        Util.dp_exit(1, pplogger, error=str(e))
    base_file = os.path.basename(input_file)
    fname, fext = os.path.splitext(base_file)
    fname = f"{fname.replace(' ' , '_')}"
    fext = fext.lstrip(".")
    wr_kwargs = {
        'outdir': outbox,
        'basename': fname,
        'ext': fext,
        'gzipIFF': True,
    }
    # Instantiate the Writer class and pass the values as keyword arguments
    writer_instance = Writer(**wr_kwargs)
    # Check if the API data is missing, has an error status, contains a specific error message, or lacks a 'lot' key
    if lot_metadata is None or 'error' in lot_metadata.get('status', '').lower() or 'no_data' in lot_metadata.get('status', '').lower() or 'lot' not in lot_metadata or not lot_metadata.get('lot'):
        writer_instance.noMeta = True
    iff_args = {
        'writer': writer_instance,
        'model': model
    }

    iff_instance = IFF(iff_args)
    iff_instance.save_dataframe_to_csv()

    # Populate minimal pplogger fields and enable logging to persist the record
    try:
        pplogger.set_raw_file(input_file)
        pplogger.set_site(site)
        pplogger.set_script(os.path.basename(__file__))
        pplogger.set_program_class('NA')
        # Populate additional PPLogger fields so refdb.pp_log has rich metadata
        try:
            pplogger.set_lot(lot)
            source_lot = None
            if isinstance(lot_metadata, dict):
                source_lot = lot_metadata.get('sourceLot') or lot_metadata.get('source_lot')
            pplogger.set_source_lot(source_lot)
            # ENV: use ws_source if provided, otherwise default to bk_sic_wlbi_fox_xp_csv
            pplogger.set_env(ws_source or 'bk_sic_wlbi_fox_xp_csv')
            pplogger.set_proc_code('WLBI')
            pplogger.set_out_dir(outbox)
            pplogger.set_program_name(fname)
            pplogger.set_limit_file('')
            pplogger.set_ext(fext)
            pplogger.set_path(os.path.dirname(input_file))
            # Compute MD5 if possible (will log error internally if file missing)
            pplogger.set_md5()
            # Force a concise log message about processing outcome
            pplogger.set_log_msg(f"Processed WLBI file {os.path.basename(input_file)}; out={outbox}", force=True)
        except Exception:
            Log.WARN('Partial PPLogger population failed; continuing')
        pplogger.set_to_be_logged(True)
    except Exception:
        Log.WARN('PPLogger population failed; continuing without pp_log entry')

    Util.dp_exit(0, pplogger)

if __name__ == '__main__':
    main()    
