#!/usr/bin/env python3.12
#
# Feb-04-2025	Eric	: new
#
# Function 	: Splits comma delimited with headers by column

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

def split_file_to_dict(input_file,separator,columnloc):
	data_dict = {}
	with open(input_file, 'r') as file:
		lines = file.readlines()

	# Extract header and column location index
	header = lines[0]
	header_items = header.split(",")
	header_index = header_items.index(columnloc)

	for line in lines[1:]:
		# Skip blank or empty lines
		if not line.strip():
			continue
		# Get column to split
		#line_key = line.split(separator)[columnloc]
		line_key = line.split(separator)[header_index]
		# Split the line
		line_items = line.split(separator)
		# Replace null values with "NA"
		#line_mod = ['NA' if item == '' else item for item in line_items]
		line_mod = ['NA' if item == '' or item == '[NULL]' else item for item in line_items]
		# Sanitize file separator header index
		line_mod_clean = sanitize_list(line_mod,header_index) 
		# Join lines
		#line_join = separator.join(line_mod)
		line_join = separator.join(line_mod_clean)
		# Fix if line ends with separator
		new_line = replace_char_at_end(line_join,separator)

		if line_key not in data_dict:
			data_dict[line_key] = [header]  # Initialize the list with the header
		#data_dict[line_key].append(line_join)
		data_dict[line_key].append(new_line)

	return data_dict

def create_files_from_dict(data_dict,output_dir,file_name,gzip_out):
	if not os.path.exists(output_dir):
		os.makedirs(output_dir)
	
	if gzip_out == "Y":
		for key, lines in data_dict.items():
			#output_file = os.path.join(output_dir, f"{file_name}_{key}.gz")

			cleaned_key = clean_string(key)
			output_file = os.path.join(output_dir, f"{file_name}_{cleaned_key}.gz")
			with gzip.open(output_file, 'wt') as file:
				file.writelines(lines)
				file.writelines('\n')
	else:
		for key, lines in data_dict.items():
			#output_file = os.path.join(output_dir, f"{file_name}_{key}")
			cleaned_key = clean_string(key)
			output_file = os.path.join(output_dir, f"{file_name}_{cleaned_key}")
			with open(output_file, 'wt') as file:
				file.writelines(lines)
				file.writelines('\n')
	
def replace_char_at_end(original_string, target_char):
	replacement_char = "NA" + "\n"
	if original_string.endswith(target_char + "\n"):
		return original_string[:-1] + replacement_char
	else:
		return original_string

def clean_string(string):
	# remove unwanted characters
	string = re.sub(r'[\n\$%\^&\*\{\}\[\]\|\!~\/`<>\:\;\"\,\'\(\)]', '', string)
	# Remove all whitespace (including spaces between words)
	string = re.sub(r'\s+', '', string)
	return string

def sanitize_list(lst, indx):
	if len(lst) > 2 and isinstance(lst[indx], str):
		#Remove parenthesis
		cleaned = lst[indx].replace('(', '').replace(')', '')
		# Replace one or more spaces with a single underscore
		cleaned = re.sub(r'\s+', '_', cleaned)
		lst[indx] = cleaned
	return lst	

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
	#columnloc = int(params['columnloc'])
	columnloc = params['columnloc']
	gzip_out = params['gzip_out']

	# Does Python does not accept pipe char as input arg?
	if separator == 'pipe':
		separator = '|'

	Log.INFO("*** Starting script ***")
	Log.INFO(f"Input file = {input_file}")
	Log.INFO(f"Outbox = {outbox}")
	Log.INFO(f"Separator = {separator}")
	Log.INFO(f"Column Location = {columnloc}")
	Log.INFO(f"Gzip output = {gzip_out}")
	Log.INFO(f"Log file = {log_file}")

	try:
		Log.INFO(f"Processing file: {input_file}")
		file_name = os.path.basename(input_file)
		data_dict = split_file_to_dict(input_file,separator,columnloc)
		create_files_from_dict(data_dict,outbox,file_name,gzip_out)
		Log.INFO(f"File has been split successfully.")
		Log.INFO("*** End script ***")

	except Exception as e:
		Log.ERROR(f"Error processing file {input_file}: {e}")
		Util.dp_exit(1,"Error processing file {input_file}: {e}")

if __name__ == "__main__":
	main()
