#!/usr/bin/env python3
#
# 2024-Feb-23 Eric:     initial release

# modules
import os
import shutil
import time
import logging
import logging.handlers as handlers
import argparse
import sys
from pathlib import Path
import re
from glob import glob, iglob
from os import walk
from os.path import splitext, join
from itertools import groupby
from operator import itemgetter
from datetime import datetime
import errno
import psutil
import fileinput
import smtplib
from email.mime.multipart import MIMEMultipart 
from email.mime.text import MIMEText 
from email.mime.application import MIMEApplication
import socket

def initLog(path):
    currentTime = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    logger = logging.getLogger("check_stuck_staging_file.py")
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
    logHandler = handlers.RotatingFileHandler(path, maxBytes=500, backupCount=0)
    logHandler.setLevel(logging.INFO)
    logHandler.setFormatter(formatter)
    errlog = path + "_err.log"
    errorHandler = handlers.TimedRotatingFileHandler(errlog, when="m", interval=1, backupCount=0)
    errorHandler.setLevel(logging.ERROR)
    errorHandler.setFormatter(formatter)
    consoleHandler = logging.StreamHandler(sys.stdout)
    consoleHandler.setFormatter(formatter)
    logger.addHandler(logHandler)
    logger.addHandler(errorHandler)
    logger.addHandler(consoleHandler)
    return logger    

def initArgparse():
    parser = argparse.ArgumentParser(description = 'Check DpLoad PIDs status if running or not.')    
    parser.add_argument("-in","--input_file", required=True, help="input MGR file")    
    parser.add_argument("-lg", "--logfile", required=True, help="log file")
    return parser

def extractCfgFileFromMgrFile(mgrFile):
    ppCfgFileList = []
    with fileinput.input(mgrFile) as fh:
        for line in fh:
            line.strip()
            if line.startswith("#"):
                #print ("--lines starts with '#' ignored--")
                pass
            elif line in ['\n', '\r', '\r\n']:
                #print ("--empty lines ignored--")
                pass
            else:
                #print (line)
                ppCfgDir = line.split(":")
                ppCfgDir[0].strip()
                ppCfgDir[0] = re.sub("^\s+|\s+$", "", ppCfgDir[0], flags=re.UNICODE)
                
                #interpret env variable in file
                ppCfgDir[0] = os.path.expandvars(ppCfgDir[0])
                #print (ppCfgDir[0])
                
                #insert all pp cfg files to list
                ppCfgFileList.append(ppCfgDir[0])
    fh.close()
    return ppCfgFileList
    
def checkCfgFilePid(cfgFileList):
    ppCfgFilePidNotRunningList = []
    for cfgFile in cfgFileList:        
        #print (cfgFile)
        cfgFilePid = cfgFile + ".pid"
        
        #check if pid file exists
        fileExists = os.path.isfile(cfgFilePid)
        
        if fileExists:            
            #extract pid by reading first line of file and strip spaces
            with fileinput.input(cfgFilePid) as fh:
                pid = fh.readline().strip()
    
            #check if pid exists
            #pidExists = checkPid(int(pid))
            
            #if pidExists:
            #    logger.info(f"Found! file={cfgFilePid}||pid={pid}||status={pidExists}")
            #else:                
            #    logger.info(f"Found! file={cfgFilePid}||pid={pid}||status={pidExists}")                
                #insert non running cfg files
            #    ppCfgFilePidNotRunningList.append(cfgFile)
            if psutil.pid_exists(int(pid)):
                logger.info(f"Found! file={cfgFilePid}||pid={pid}||status=TRUE")
            else:
                logger.info(f"Found! file={cfgFilePid}||pid={pid}||status=FALSE")
                #insert non running cfg files
                ppCfgFilePidNotRunningList.append(cfgFile)
                
    return ppCfgFilePidNotRunningList
    
def checkPid(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    else:
        return True
	
def sendEmail(cfgFilesNotRunning):
    smtpServer='smtp.onsemi.com'
    smtpPort = 25
    fromAddr='yms.admins@onsemi.com'         
    #toAddr='eric.alfanta@onsemi.com'
    toAddr='yms.admins@onsemi.com'
    hostname=socket.gethostname()
    hostname=hostname.split(".")
    
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
    message['Subject'] = f"{hosttype}: ALARM! Some config file(s) are not running"

    msg_content = "Hello Data Integration team,<br> The following config files are not running. Please check as soon as possible.<br><br>"
    for line in cfgFilesNotRunning:
        msg_content += line + "<br>"
    
    body = MIMEText(msg_content, 'html')
    message.attach(body)
    msg_full = message.as_string()

    #context = ssl.create_default_context()

    with smtplib.SMTP(smtpServer, smtpPort) as server:
        #server.ehlo()  
        #server.starttls(context=context)
        server.ehlo()
        #server.login(fromAddr, password)
        server.sendmail(fromAddr, toAddr, msg_full)
        server.quit()

    logger.info(f"Email sent successfully.")           

def main():    
    logger.info(f"input file={inputfile}")
    if processCounter > 1:
        logger.info(f"Another process of script={os.path.basename(__file__).split('/')[-1]} already running for the input file={inputfile}, script will exit.")
        raise SystemExit("Already running")
        
    #read mgr file
    ppCfgFileList = extractCfgFileFromMgrFile(inputfile)
    
    #check config file pids
    cfgFilePidNotRunningList = checkCfgFilePid(ppCfgFileList)    

    #send email
    if len(cfgFilePidNotRunningList) == 0:
        logger.info(f"All Good!! Config files are running.")
    else:
        logger.info(f"Some config files are not running. Sending notification.")
        sendEmail(cfgFilePidNotRunningList)
        
    logger.info("###End Script###") 

if __name__ == '__main__':
    parser = initArgparse()
    args = parser.parse_args()
    inputfile = args.input_file
    logfile = args.logfile
    logger = initLog(logfile)
    logger.info("###Start Script###")
    processCounter = 0
    for proc in psutil.process_iter():
        cmdline = proc.cmdline()
        if re.search("check_dpload_status",str(cmdline)) and inputfile in cmdline:
            processCounter += 1
    main()
