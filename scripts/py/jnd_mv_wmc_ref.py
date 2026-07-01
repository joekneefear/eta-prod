#!/usr/bin/env python3.6

"""
SYNOPSIS

DESCRIPTION
    This script try to decrypt if file is .gpg and unzip if file is .zip then put into wmc_fjm folder.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2023-Oct-07 - jgarcia - initial
    2023-Oct-11 - jgarcia - modified to just insert the new ref file(expected to in csv format) to original(allow duplicates for now)
                      - dont insert new line or blank line (values)
    2024-Sep-25 - jgarcia - updated shebang to use python3.6
LICENSE
    (C) onsemi 2023 All rights reserved.
"""

import os
import sys
import csv
import io
from lib.Log import Log
from lib.Util import Util

def insert_data(input_file, output_file):
    with open(input_file, 'r') as infile, open(output_file, 'a+', newline='') as outfile:
        reader = csv.reader(infile)
        writer = csv.writer(outfile)

        # Find the position to insert data
        current_position = outfile.tell()  # Get the current position in the output file

        # Check if the file is not empty
        if current_position > 0:
            # Get the file size
            file_size = os.path.getsize(output_file)

            # Move back to the last non-newline character
            while file_size > 0:
                file_size -= 1
                outfile.seek(file_size, io.SEEK_SET)
                last_char = outfile.read(1)

                if last_char != b'\n':
                    # If the last character is not a newline, break
                    break

            # Move back to the original position
            outfile.seek(current_position, io.SEEK_SET)

        for row in reader:
            # Skip empty rows
            if not any(row):
                continue
            
            data_to_insert = process_data(row)
            # Strip any unwanted characters from the line before writing
            cleaned_data = [cell.strip() for cell in data_to_insert]
            writer.writerow(cleaned_data)

        # Move back to the original position after writing the new data
        outfile.seek(current_position, io.SEEK_SET)



def process_data(row):
    # Customize this function to process and transform data from the input file if needed
    return row

def main():
    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)
    
    if len(sys.argv) < 2:
        Util.dp_exit(1, "No new Tesec WMC ref file specified!!!")

    csv_to_append_path = params['infile']
    tesec_wmc_ref_file = params['ref_file']
    log_file = params['logfile']

    Log.configure_logger(log_file=log_file)
    Log.INFO(f"Log file={log_file}")
    Log.INFO(f"TESEC WMC Ref file to append={csv_to_append_path}")
    Log.INFO("Convert line endings, issue dos2unix")
    Util.convert_line_endings(csv_to_append_path)

    Log.INFO(f"Process, insert data from new tesec wmc ref csv file={csv_to_append_path}, and write the data into existing ref file={tesec_wmc_ref_file}")
    insert_data(csv_to_append_path, tesec_wmc_ref_file)

    Util.dp_exit(0)

if __name__ == '__main__':
    main()
