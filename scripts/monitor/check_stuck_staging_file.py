#!/usr/bin/env python3.12
#
# 2023-Jun-06 Eric initial release

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
from collections import defaultdict
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
    parser = argparse.ArgumentParser(description = 'Check stuck files in staging according to x old days.')
    parser.add_argument("-in","--input_file", required=True, help="list of staging folders")
    parser.add_argument("-fa", "--file_age", required=True, help="file age create time", type=int)
    parser.add_argument("-lg", "--logfile", required=True, help="log file")
    parser.add_argument("-at", "--age_type", required=True, help="day or hour", choices=['day','hour'])
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
                
                #insert all pp cfg files to list
                ppCfgFileList.append(ppCfgDir[0])
    fh.close()
    return ppCfgFileList

def extractStgDirFromCfgFile(cfgFileList):
    stgFolderList = []    
    for stgDir in cfgFileList:
        #interpret env variable in file
        #with fileinput.input(os.path.expandvars(stgDir)) as fh:
        with fileinput.input(stgDir) as fh:
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
                    ppStgDir = line.split(":")
                    ppStgDir[0].strip()
                    ppStgDir[0] = re.sub("^\s+|\s+$", "", ppStgDir[0], flags=re.UNICODE)

                    #interpret env variable in file
                    ppStgDir[0] = os.path.expandvars(ppStgDir[0])

                    #insert all stage dir to list
                    #some config file do not use staging folder so skip it 
                    if ppStgDir[0] == "NA":
                        logger.info(f"Skipping directory: {ppStgDir[0]}")	
                    else:
                        stgFolderList.append(ppStgDir[0])
        fh.close()
    return stgFolderList

def checkFileInStgDirByHH(stgFolderList, fileAge, logger):
    stuckFileList = []
    for stgDir in stgFolderList:
        for stgFile in os.listdir(stgDir):
            if os.path.isfile(os.path.join(stgDir, stgFile)):
                if stgFile.startswith("."):
                    pass
                else:
                    fileModificationTime = datetime.fromtimestamp(os.path.getmtime(stgDir + "/" + stgFile))                  
                    fileAgeInSeconds = checkFileAge(stgDir + "/" + stgFile) #seconds
                    fileAgeInMinutes = int(fileAgeInSeconds) / 60 #minutes
                    fileAgeInHours = fileAgeInMinutes / 60 #hours
                    
                    if fileAgeInHours >= int(fileAge):
                        stuckFile = stgDir + "/" + stgFile
                        stuckFileList.append(stuckFile)
                        logger.info(f"Stuck File Found! dir={stgDir}||file={stgFile}||timestamp={fileModificationTime}||HourDiff={fileAgeInHours}")
    return stuckFileList
    
def checkFileInStgDirByDD(stgFolderList, fileAge, logger):
    stuckFileList = []
    for stgDir in stgFolderList:
        for stgFile in os.listdir(stgDir):
            if os.path.isfile(os.path.join(stgDir, stgFile)):
                if stgFile.startswith("."):
                    pass
                else:
                    fileModificationTime = datetime.fromtimestamp(os.path.getmtime(stgDir + "/" + stgFile))
                    today = datetime.today()
                    fileDiffAge = today - fileModificationTime
                    
                    if fileDiffAge.days >= int(fileAge):
                        stuckFile = stgDir + "/" + stgFile
                        stuckFileList.append(stuckFile)
                        logger.info(f"Stuck File Found! dir={stgDir}||file={stgFile}||timestamp={fileModificationTime}||DayDiff={fileDiffAge}")
    return stuckFileList

def createAttachment(stuckFileList):
    # Dictionary to store the count of files in each directory
    directory_count = defaultdict(int)

    # attachment file
    myAttachment = '/apps/exensio_data/data/temp/stuckFilesInStageDir.txt'

    # delete old attachment	
    if os.path.exists(myAttachment):
        logger.info(f"Deleting old attachment={myAttachment}")
        os.remove(myAttachment)
    #else:
        #logger.info(f"Creating Attachment={myAttachment}")

    #Iterate over the list of files and count the number of files in each directory
    for file in stuckFileList:
        #directory = file.split('/')[4]
        directory = os.path.dirname(file)
        directory_count[directory] += 1

    logger.info(f"Creating new attachment={myAttachment}")
    #f = open(myAttachment,"w")
    #for item in stuckFileList:
    #    f.write(item)
    #    f.write('\n')
    #f.close()
    f = open(myAttachment,"w")
    for directory, count in directory_count.items():
        f.write(f'{directory} = {count}')
        f.write('\n')
    f.close() 

    return myAttachment

def sendEmail(myAttachment,numberOfFiles,fileAge,ageType):
    smtpServer='smtp.onsemi.com'
    smtpPort = 25
    fromAddr='yms.admins@onsemi.com'         
    #toAddr='eric.alfanta@onsemi.com'
    toAddr='yms.admins@onsemi.com'
    hostname=socket.gethostname()
    hostname=hostname.split(".")
    
    if hostname[0] == 'usaz15ls082' or hostname[0] == 'usaz15ls083':
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
    #message['Subject'] = f"{hosttype}: Found {numberOfFiles} stuck files in {hostname[0]} staging folder(s)"
    message['Subject'] = f"{hosttype}: Found {numberOfFiles} stuck files for over {fileAge} {ageType}(s) in {hostname[0]} staging folder(s)"	

    #msg_content = 'Hello Data Integration team,<br> Please see attachment for details.\n'
    #body = MIMEText(msg_content, 'html')
    #message.attach(body)

    #try:
    #    with open(myAttachment, "rb") as attachment:
    #        p = MIMEApplication(attachment.read(),_subtype="txt")	
    #        p.add_header('Content-Disposition', "attachment; filename= %s" % myAttachment.split("/")[-1]) 
    #        message.attach(p)
    #except Exception as e:
    #    print(str(e))
    #    logger.info(f"Error!!! {e}")

    with open (myAttachment, "r") as f:
        content = f.readlines();
        msg_content = "<br>".join(content)
        f.close()

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

def checkFileAge(filePath):
        return time.time() - os.path.getmtime(filePath)

def main():    
    logger.info(f"input file={inputfile}||file age={fileAge}")
    if processCounter > 1:
        logger.info(f"Another process of script={os.path.basename(__file__).split('/')[-1]} already running for the input file={inputfile} and file age={fileAge}, script will exit.")
        raise SystemExit("Already running")
    #read mgr file
    ppCfgFileList = extractCfgFileFromMgrFile(inputfile)
    
    #read cfg files and return stage folders
    stgFolderList = extractStgDirFromCfgFile(ppCfgFileList)
    
    #remove duplicate stage dir
    stgFolderList = list(dict.fromkeys(stgFolderList))
    
    #check stuck files in stage dir
    #stuckFileList = checkFileInStgDir(stgFolderList, fileAge, logger)
    if ageType == 'day':
        stuckFileList = checkFileInStgDirByDD(stgFolderList, fileAge, logger)
    elif ageType == 'hour':
        stuckFileList = checkFileInStgDirByHH(stgFolderList, fileAge, logger)
    
    #create attachment
    myAttachment = createAttachment(stuckFileList)

    #send email
    if len(stuckFileList) == 0:
        logger.info(f"All Good!! No stuck files found.")
    else:
        sendEmail(myAttachment, len(stuckFileList), fileAge, ageType)
        
    logger.info("###End Script###") 

if __name__ == '__main__':
    parser = initArgparse()
    args = parser.parse_args()
    inputfile = args.input_file
    fileAge = args.file_age
    ageType = args.age_type
    logfile = args.logfile
    logger = initLog(logfile)
    logger.info("###Start Script###")
    processCounter = 0
    for proc in psutil.process_iter():
        cmdline = proc.cmdline()
        if re.search("check_stuck_staging_files",str(cmdline)) and inputfile in cmdline and fileage in cmdline:
            processCounter += 1
    main()

