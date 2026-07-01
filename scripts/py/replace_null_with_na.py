#!/usr/bin/env python3.12
#
# Jan-31-2025	Eric	: initial release
#
# Function	: Accepts command delimited file and replaces empty or null values with NA

import os
import sys
import subprocess
import argparse
import time
import gzip
import re
from lib.Log import Log
from lib.Util import Util

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

def replace_null_with_na(input_file,separator):
	data_list = []
	#with open(input_file, 'r') as file:
	with open(input_file, 'r', encoding='latin-1') as file:
		lines = file.readlines()

	for line in lines:
		# Split the line
		line_items = line.split(separator)
		# Replace null values with "NA"
		line_mod = ['NA' if item == '' or item == '[NULL]' else item for item in line_items]
		# Join lines
		line_join = separator.join(line_mod)
		# Fix if line ends with separator
		new_line = replace_char_at_end(line_join,separator)
		# Strip new lines 
		#line_join.strip
		new_line.strip
		# Insert line into list
		#data_list.append(line_join)	
		data_list.append(new_line)

	return data_list

def replace_char_at_end(original_string, target_char):
	replacement_char = "NA" + "\n"
	if original_string.endswith(target_char + "\n"):
		return original_string[:-1] + replacement_char
	else:
		return original_string

def create_files_from_list(data_list,output_dir,file_name,gzip_out):
	if not os.path.exists(output_dir):
		os.makedirs(output_dir)

	if gzip_out == "Y":
		output_file = os.path.join(output_dir, f"{file_name}.gz")
		with gzip.open(output_file, 'wt') as file:
			for lines in data_list:
				file.writelines(lines)
	else:
		output_file = os.path.join(output_dir, f"{file_name}")
		with open(output_file, 'wt') as file:
			for lines in data_list:
				file.writelines(lines)

def main():
	log_file = initialize_log_file()
	Log.configure_logger(log_file=log_file)

	arguments = sys.argv[1:]
	params = Util.process_command_line_args(arguments)

	if len(sys.argv) < 2:
		Log.INFO("No input file specified!!!")
		Util.dp_exit(1, "No input file specified!!!")

	outbox = params['out']
	input_file = params['infile']
	separator = params['separator']
	gzip_out = params['gzip_out']

	# Does Python does not accept pipe char as input arg?
	if separator == 'pipe':
		separator = '|'

	Log.INFO("*** Starting script ***")
	Log.INFO(f"Input file = {input_file}")
	Log.INFO(f"Outbox = {outbox}")
	Log.INFO(f"Separator = {separator}")
	Log.INFO(f"Gzip output = {gzip_out}")
	Log.INFO(f"Log file = {log_file}")

	try:
		Log.INFO(f"Processing file: {input_file}")
		file_name = os.path.basename(input_file)
		data_list = replace_null_with_na(input_file,separator)
		create_files_from_list(data_list,outbox,file_name,gzip_out)
		Log.INFO(f"File has been processed successfully.")
		Log.INFO("*** End script ***")

	except Exception as e:
		Log.ERROR(f"Error processing file {input_file}: {e}")
		Util.dp_exit(1,"Error processing file {input_file}: {e}")

if __name__ == "__main__":
	main()
