#!/usr/bin/env python3.12

"""
SYNOPSIS

DESCRIPTION
    This script reads and re-writes the klarf defect file after removing/filtering defect list with xy coordinates not in SampleTestPlan.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2023-Oct-12 - jgarcia - initial
    2023-Nov-03 - jgarcia - enhanced defectlist checking and if defect file really needs to undergo defect list stripping or just copy to outbox.
    2023-May-16 - jgarcia - added feature that can do enrichment for OrientationMarkLocation
    2024-Aug-16 - jgarcia - move to NotProcessed files with no defect list or with defect list but nothing left after enrich_remove_defect_list_XY_not_in_sample_test_plan
    2024-Sep-25 - jgarcia - updated shebang to use python3.6


LICENSE
    (C) onsemi 2023 All rights reserved.
"""

import os
import sys
import gzip
import shutil
import yaml
import re
from lib.Log import Log
from lib.Util import Util
from lib.Parser.Klarf12 import Klarf12
from lib.Enricher.Klarf12Enricher import Klarf12Enricher
from lib.Writer import Writer
from lib.Formatter.IFF import IFF
from lib.Data.Model import Model
import pprint


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
    outbox = params['out']
    yaml_file = params.get('yaml_file', '/export/home/dpower/project/scripts/py/lib/Klarf12Reference.yaml')
    with open(yaml_file, 'r') as file:
        yaml_data = yaml.safe_load(file)
    for_sandbox = params.get('forced_final_folder') == "SBX"
    
    log_file = initialize_log_file()
    Log.configure_logger(log_file=log_file)
    Log.INFO(f"Input file={input_file}")
    
    klarf_parser = Klarf12()
    # model = Model()
    model = klarf_parser.parse_klarf_1_2(klarf_file=input_file)
    if 'flag' not in model.misc:
        model.misc['flag'] = ""
    enrichments = {}
    
    if params.get('site') == 'OSV':
        enrichments = yaml_data.get('OSV_Klarf12', {}).get('enrichments', [])
        osv_device_ids = yaml_data['OSV_Klarf12']['device_ids']
        klarf_enricher = Klarf12Enricher(model, enrichments, osv_device_ids)
        model = klarf_enricher.apply_enrichments()
    
    if params.get('site') == "SZ":
        enrichments = yaml_data.get('SZ_Klarf12', {}).get('enrichments', [])
        klarf_enricher = Klarf12Enricher(model, enrichments)
        model = klarf_enricher.apply_enrichments()
    
    # klarf_enricher.check_defect_list(model)
       
    base_file = os.path.basename(input_file)
    fname, fext = os.path.splitext(base_file)
    fname = fname.replace(' ', '_')
    if fext == '.gz':
        fname, fext = os.path.splitext(fname)
        if fext == '.ecd':
            fext = 'ecd.gz'
        else:
            fext = fext.lstrip(".") + '.gz'
    else:
        fext = fext.lstrip(".")
    
    wr_kwargs = {
        'outdir': outbox,
        'basename': fname,
        'ext': fext,
        'gzipIFF': True,
        'forced_sandbox': for_sandbox
    }
    
    writer_instance = Writer(**wr_kwargs)
    iff_args = {
        'writer': writer_instance,
        'model': model
    }
    
    Log.INFO(f"FLAG={model.misc['flag']}")
    if model.misc['flag']:
        if "eoml" in model.misc['flag'].split('_'):
            fname += "_EOML"
        if "edl" in model.misc['flag'].split('_'):
            fname += "_EDL"
        if "rmTifExtraDef" in model.misc['flag'].split('_'):
            fname += "_rmTiffExtraDef"
        if "edlcol" in model.misc['flag'].split('_'):
            fname += "_EDLCOL"

        writer_instance.basename = fname
        writer_instance.ext = fext
        writer_instance.set_timestamp_to_basename()
        iff_instance = IFF(iff_args)
        iff_instance.write_dict_line_list_klarf12(add_new_line=False)
    else:
        Log.INFO("All Defect List is within sample test plan OR no defect list listed")
        Log.INFO(f"Just copy the input file={base_file} to outbox={outbox}")
        destination_file = writer_instance.outfile()
        if not destination_file.endswith(".gz"):
            destination_file += ".gz"
        temp_destination_file = destination_file + ".tmp"
        if os.path.exists(temp_destination_file):
            Log.WARN(f"Removing stale temp file from a previous interrupted run: {temp_destination_file}")
            os.remove(temp_destination_file)
        if Util.is_gzipped(input_file):
            with open(input_file, 'rb') as f_in, open(temp_destination_file, 'wb') as f_out:
                shutil.copyfileobj(f_in, f_out)
            with open(temp_destination_file, 'rb') as f_sync:
                os.fsync(f_sync.fileno())
            os.replace(temp_destination_file, destination_file)
        else:
            Log.INFO(f"Copy {input_file} to {destination_file} and compress to gzip")
            with open(input_file, 'rb') as f_in:
                with open(temp_destination_file, 'wb') as raw_out:
                    # filename='' prevents the temp path from being embedded in the gzip header;
                    # decompressors (incl. Windows) then use the .gz file's own name as the output.
                    with gzip.GzipFile(filename='', mode='wb', fileobj=raw_out) as f_out:
                        shutil.copyfileobj(f_in, f_out)
            # fsync AFTER close so gzip footer (CRC32+size) is written first
            with open(temp_destination_file, 'rb') as f_sync:
                os.fsync(f_sync.fileno())
            os.replace(temp_destination_file, destination_file)
                
    Util.dp_exit(0)

if __name__ == '__main__':
    main()