import os
from configparser import ConfigParser
from pathlib import Path
from os import walk
from datetime import datetime
import subprocess
import argparse
import psutil
import re
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication
import socket
import time

def initArgparse():
	parser = argparse.ArgumentParser(description = 'Check missing camstar extracts.')
	parser.add_argument("-in","--input_file", required=True, help="list of staging folders")
	return parser

def main():
	if processCounter > 1:
		raise SystemExit("Already running")

	dirList = []

	# Read config file
	config = ConfigParser()
	config.read(inputfile)

	directory = config["DIRECTORY"]
	condition = config["CONDITION"]
	#fileage = condition["fileage"]
	extension = condition["ext"]
	expected_count = condition["count"]

	for key in directory:
		if os.path.isdir(directory[key]):
			file_count = count_files(directory[key],extension)
			#print(directory[key]," = ",file_count)
			if file_count != int(expected_count):
				print(directory[key], "have MISSING extracts! Number of extracts received = ",file_count)
				msgstr = f'{directory[key]} have MISSING extracts! Number of extracts received = {file_count}'
				dirList.append(msgstr)
			else:
				print(directory[key], "have complete extracts = ",file_count)

	if len(dirList) == 0:
		print("All good")
	else:
		sendEmail(dirList)		

def count_files(directory,extension):
	# Get the current time
	current_time = time.time()
	# Define the time threshold (1 day = 86400 seconds)
	time_threshold = current_time - 86400
	# Initialize the file count
	file_count = 0

	# Walk through the directory
	for root, dirs, files in os.walk(directory):
		for file in files:
			file_path = os.path.join(root, file)
			# Check if the file has a zipped extension
			if file.endswith(extension):
				# Get the file's change time
				file_change_time = os.path.getctime(file_path)
				# Check if the file's change time is within the last day
				if file_change_time > time_threshold:
					file_count += 1

	return file_count

def sendEmail(dirList):
	smtpServer='smtp.onsemi.com'
	smtpPort = 25
	fromAddr='yms.admins@onsemi.com'
	#toAddr='eric.alfanta@onsemi.com'
	toAddr='yms.admins@onsemi.com'
	hostname=socket.gethostname()
	hostname=hostname.split(".")
	msg_content = ''

	if hostname[0] == 'usaz15ls082':
		hosttype = 'PRD'
	elif hostname[0] == 'usaz15ls080':
		hosttypes = 'QA'
	elif hostname[0] == 'usaz15ls081':
		hosttype = 'DEV'
	else:
		hosttype=hostname[0]

	message = MIMEMultipart('mixed')
	message['From'] = fromAddr
	message['To'] = toAddr
	message['Subject'] = f"{hosttype}: Missing Camstar extracts!"

	msg_content = '<br>'.join(dirList)
	#for dir in dirList:
	#msg_content += f'{dir}\r\n'

	body = MIMEText(msg_content, 'html')

	message.attach(body)

	msg_full = message.as_string()

	with smtplib.SMTP(smtpServer, smtpPort) as server:
		#server.ehlo()
		#server.starttls(context=context)
		server.ehlo()
		#server.login(fromAddr, password)
		server.sendmail(fromAddr, toAddr, msg_full)
		server.quit()

if __name__ == '__main__':
	parser = initArgparse()
	args = parser.parse_args()
	inputfile = args.input_file
	processCounter = 0
	for proc in psutil.process_iter():
		cmdline = proc.cmdline()
		if re.search("camstar_extract_monitor",str(cmdline)) and inputfile in cmdline:
			processCounter += 1

	main()
