#!/usr/bin/env python3.6

"""
SYNOPSIS

DESCRIPTION
    This script try to decrypt if file is .gpg and unzip if file is .zip then put into wmc_fjm folder.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES 
    2023-Oct-06 - jgarcia - initial
    2024-Sep-25 - jgarcia - updated shebang to use python3.6
 
LICENSE
    (C) onsemi 2023 All rights reserved.
"""

import sys
import os
import subprocess
import shutil
import zipfile
import re
from lib.Log import Log
from lib.Util import Util

def decrypt_and_handle_output(file_path, final_output_folder, gpg_passphrase):
    _, file_extension = os.path.splitext(file_path)
    
    Log.INFO(f"File extension={file_extension}")
    # Create a new folder for the final output
    output_folder = os.path.join(final_output_folder, 'wmc_fjm')
    os.makedirs(output_folder, exist_ok=True)
    Log.INFO(f"Final Output folder={output_folder}")
        
    fjm_file = os.path.join(final_output_folder, file_path)
    decrypted_fjm_file_without_extension, _ = os.path.splitext(fjm_file)
             
    # if file_extension == '.gpg':
    if re.match(r"\.gpg", file_extension, re.IGNORECASE):
        # GPG decrypt the file
        Log.INFO(f"INPUT FILE={file_path}")
        # Remove ".gpg" extension
        
        Log.INFO(f"Decrypted File={fjm_file}")
        decrypt_command = ['gpg', '-v', '--batch', '--passphrase', gpg_passphrase, '--output', decrypted_fjm_file_without_extension, file_path]
        try:
            subprocess.run(decrypt_command)
        except Exception as e:
            Log.ERROR(f"Execption occured: {e}")

        # Check if the decrypted file is a zip file
        if zipfile.is_zipfile(decrypted_fjm_file_without_extension):
            # Unzip the decrypted file to the final folder
            Log.INFO(f"file is zipped={decrypted_fjm_file_without_extension} will try to unzip.")
            try:
                shutil.unpack_archive(decrypted_fjm_file_without_extension, output_folder)
                msg = f"Extraction is successful"
                Log.INFO(msg)
                Log.INFO(f"remove/cleanup archive file{decrypted_fjm_file_without_extension}")
                os.remove(decrypted_fjm_file_without_extension)
            except Exception as e:
                msg = f"Extraction is not successful: {e}"
                print(msg)
                Log.INFO(msg)
                Util.dp_exit(1, msg)
    elif re.match(r"\.zip", file_extension, re.IGNORECASE):
        # Unzip the  file to the final folder
        Log.INFO(f"file is zipped={decrypted_fjm_file_without_extension} will try to unzip.")
        try:
            shutil.unpack_archive(file_path, output_folder)
            msg = f"Extraction is successful"
            Log.INFO(msg)
        except Exception as e:
            msg = f"Extraction is not successful: {e}"
            print(msg)
            Log.INFO(msg)
            Util.dp_exit(1, msg)
    elif re.match(r".fjm", file_extension, re.IGNORECASE):
         # Move the decrypted file to the final folder
        Log.INFO(f"File is not zipped, will move directly to the final ouput folder={output_folder}")
        shutil.move(file_path, output_folder)
    else:
        Util.dp_exit(1,"Unsupported format!!!")
    

def main():
    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)
    if len(sys.argv) < 2:
        #Log.info(f"No input Sxml file specified!!!")
        Util.dp_exit(1,"No FJM file specified!!!")
        
    input_file=params['infile']
    outbox = params['out']
    log_file = params['logfile']
    gpg_passphrase = 'P@ssw0rd'
    Log.configure_logger(log_file=log_file)
    Log.INFO(f"Log file={log_file}")
    Log.INFO(f"Input file={input_file}")
    Log.INFO(f"Convert line endings, issue dos2unix")
    Util.convert_line_endings(input_file)

    try:
        decrypt_and_handle_output(input_file, outbox, gpg_passphrase)
    except Exception as e:
        Log.ERROR(f"Error: {e}")
        Util.dp_exit(1,"Exception occured")
        
    Util.dp_exit(0)
        
if __name__ == '__main__':
    main()
