#!/usr/bin/env python3.12

"""
SYNOPSIS

DESCRIPTION

This script will preprocess/enrich JND LEH file. will also generate lot medata file.

AUTHOR

junifferallan.garcia@onsemi.com

CHANGES
2024-Jul-16 - jgarcia - initial
2024-Sep-25 - jgarcia - updated shebang to use python3.6

LICENSE

(C) onsemi 2023 All rights reserved.
"""

import os
import sys
import glob
from lib.Log import Log
from lib.Util import Util
from lib.Parser.JndLehParser import JndLehParser
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
    if len(sys.argv) < 2:
        #Log.info(f"No input Sxml file specified!!!")
        Util.dp_exit(1,"No input Probe Tesec SXML file specified!!!")

    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)
    input_file=params['infile']
    outbox = params['out']
       
    log_file = initialize_log_file()
    Log.configure_logger(log_file=log_file)
    Log.INFO(f"Input file={input_file}")
    
    #create JndLehParser instance  
    leh_parser = JndLehParser()
    model = leh_parser.create_lot_metadata(input_file)

    wr_kwargs = {
        'outdir': outbox,
        'ext': "lot",
        'gzipIFF': False
    }

    # Instantiate the Writer class and pass the values as keyword arguments
    writer_instance = Writer(**wr_kwargs)
    iff_args = {
        'writer': writer_instance,
        'model': model
    }
    iff_instance = IFF(iff_args)
    # Log.INFO(f'TEST={model.misc}')
    iff_instance.write_jnd_lot_metadata()
    
    Util.dp_exit(0)
    
if __name__ == '__main__':
    main()