#!/bin/env bash
#------------------------------------------------------------------------------
#                                         IIII
#                                        IIIIII
#                                         IIII
#
#      AAA        PPPPPPPP    TTTTTTTTTT  IIII  NNNNN     NNNN        AAA
#    AAAAAAA      PPPPPPPPPP  TTTTTTTTTT  IIII  NNNNNNN   NNNN      AAAAAAA
#   AAAA AAAA     PPPP  PPPP     TTTT     IIII  NNNN NNN  NNNN     AAAA AAAA
#  AAAAAAAAAAA    PPPPPPPPPP     TTTT     IIII  NNNN  NNN NNNN    AAAAAAAAAAA
# AAAAAAAAAAAAA   PPPPPPPP       TTTT     IIII  NNNN   NNNNNNN   AAAAAAAAAAAAA
#AAAA       AAAA  PPPP           TTTT     IIII  NNNN    NNNNNN  AAAA       AAAA
#
#------------------------------------------------------------------------------
# 09/01/2021 - zbhgmt
# - update for Exensio Cloudside and historical reload
#	- removed WATCH folder input, watch suffix
#	- add BASE_FOLDER 
## kuban's small ungzip
## version 2.6 APTINA 2016-MAY-09 Jakub Sara
# - added reference file (-1 sec) for comparison (-cnewer) in find
#   this handles not to include file still under ftp transfer (no in lsof)
## version 2.5 APTINA 2016-MAR-10 Jakub Sara
# - used new multi thread mechanism
# - supports to kill subprocess if running longer that MAX_JOB_SEC
# - refactored
# - when subprocess killed sends mail
## version 2.4f APTINA 2015-DEC-21 Jakub Sara
# - files ordered by epochtime in filename
## version 2.4e APTINA 2015-OCT-20 Jakub Sara
# - multi process
# - added garbage (other) dir, watch filemask
# - sed replacing all xml chars
# - refactored
## version 2.4d APTINA 2015-SEP-3 Jakub Sara
# - logging error of apt2xml translation
## version 2.4c APTINA 2015-SEP-3 Jakub Sara
# - for enriched version
# - adds FINISH time
## version 2.4b APTINA 2015-SEP-3 Jakub Sara
# - dos2unix + preserves original file
## version 2.4a APTINA 2015-AUG-24 Jakub Sara
# - translate Aptina datalog to XML
# - add <BinInfo> section

#------------------------------------------------------------------------------
# config
BASE_FOLDER="/export/home/dpower/project/scripts/uva/"
CFG_JAVA='/apps/exensio/tomcat/jdk-11/bin/java'
CFG_APT2XML=${BASE_FOLDER}"scripts/aptina-datalogs-to-xml.jar p"
CFG_BININFO=${BASE_FOLDER}"cfg/HWSWBin.csv"
#default log file
CFG_LOG=${BASE_FOLDER}"logs/"
MAX_JOBS=4
MAX_JOB_SEC=3600 #1 hour
MAIL_RECIPIENTS=("it-cim-apps@onsemi.com")

#------------------------------------------------------------------------------
# trap function to handle SIGINT SIGTERM signals
function trap_finish { echo ">>>>>>> waiting for children processes ${JOBS_ARRAY[@]} to finish <<<<<<<"; echo "USE kill -9 $$ to KILL anyway"; wait; exit 255; }
trap trap_finish SIGINT SIGTERM

processfile () {
  THREAD=$1
  VAR_FILE_input=$2
  gzip -t ${VAR_FILE_input}
  # gzip test
  if [[ $? -eq 0 ]]
  then
    # echo "unpacking ${VAR_FILE_input}"
    VAR_FILE_ungzipped=`echo ${VAR_FILE_input} | awk '{ sub(/\'$VAR_FILESUF'$/,""); print $0; }'`
    #TRANSLATE APTINA DATALOG to XML
    VAR_FILE_APTXML="${VAR_FILE_ungzipped}xml"
    VAR_FILE_APTXML_LOG="${VAR_FILE_ungzipped}apt2xml.log"
    echo "[${THREAD}]  ... translating APTINA datalog to XML: ${VAR_FILE_input} -> ${VAR_FILE_APTXML}"
    ${CFG_JAVA} -jar ${CFG_APT2XML} ${VAR_FILE_input} ${VAR_FILE_APTXML} ${CFG_BININFO} 2>&1 | tee ${VAR_FILE_APTXML_LOG}
    KUBANPIPESTATUS=(${PIPESTATUS[@]})
    if (( ${KUBANPIPESTATUS[0]} == 0 ))
    then
      echo "[${THREAD}]  translate APTINA datalog to XML successful: ${KUBANPIPESTATUS[0]}"
      mv ${VAR_FILE_input} ${VAR_DIR_processed}
      #echo "[${THREAD}]  ... replacing back reserved XML characters &<>'"
      sed -i -e 's#\&amp;#\&#g' -e 's#\&gt;#>#g' -e 's#\&lt;#<#g' -e "s#\&quot;#'#g" -e "s#\&apos;#'#g" ${VAR_FILE_APTXML}
      rm ${VAR_FILE_APTXML_LOG}
      gzip -c "${VAR_FILE_APTXML}" > "${VAR_DIR_output}$(basename "${VAR_FILE_APTXML}").gz" | xargs -0 -i{} echo -n "[${THREAD}] {}"
      rm ${VAR_FILE_APTXML}
    elif (( (${KUBANPIPESTATUS[0]} >= 64) && (${KUBANPIPESTATUS[0]} < 128) ))
    then
      echo "[${THREAD}]  translate APTINA datalog to XML successful - but VALIDATION raised: ${KUBANPIPESTATUS[0]}"
      mv ${VAR_FILE_input} ${VAR_DIR_processed}
      #echo "[${THREAD}]  ... replacing back reserved XML characters &<>'"
      sed -i -e 's#\&amp;#\&#g' -e 's#\&gt;#>#g' -e 's#\&lt;#<#g' -e "s#\&quot;#'#g" -e "s#\&apos;#'#g" ${VAR_FILE_APTXML}
      #mv ${VAR_FILE_APTXML_LOG} ${VAR_DIR_garbage}
      gzip -c "${VAR_FILE_APTXML}" > "${VAR_DIR_garbage}$(basename "${VAR_FILE_APTXML}").gz" | xargs -0 -i{} echo -n "[${THREAD}] {}"
      rm ${VAR_FILE_APTXML}
      rm ${VAR_FILE_APTXML_LOG}
    else
      echo "[${THREAD}]  translate APTINA datalog to XML failed: ${KUBANPIPESTATUS[0]}"
      mv ${VAR_FILE_input} ${VAR_DIR_notprocessed}
      mv ${VAR_FILE_APTXML_LOG} ${VAR_DIR_notprocessed}
      rm -v ${VAR_FILE_APTXML} | xargs -0 -i{} echo -n "[${THREAD}] {}"
    fi
  else
    echo "[${THREAD}] ERROR: not valid gzip test for: ${VAR_FILE_input}"
    mv ${VAR_FILE_input} ${VAR_DIR_notprocessed}
  fi
}

notifykillmail () {
UNAME=`uname -n`
WHOAMI=`whoami`
mail -s "${WHOAMI}@${UNAME} APTINA: ungzip_apt2xml killed process" ${MAIL_RECIPIENTS[@]} << EOF
What's up Buddy,
I've just killed process listed below, it was running too long. Go, get there and check me. Thanks.

Process info:
-------------
THREAD_PID: $1
THREAD_NAME: $2
THREAD_START: $3 
INPUT_FILE: $4
PROGRAM: ${CFG_JAVA} -jar ${CFG_APT2XML} <VAR_FILE_input> <VAR_FILE_APTXML> ${CFG_BININFO}

EOF
}

#------------------------------------------------------------------------------
# Check args[]
if [[ $# -ne 7 ]]
# not 8
then
  echo "kuban's ungzip: What's up man!"
  echo "USAGE: `basename $0` inputdir outputdir garbagedir watchdir inputfilemask watchfilemask limit logFileName"
  echo "EXAMPLE: `basename $0` inbox/ outbox/ outbox_other/ outbox/ .gz 100 lfoundry_log"
  exit 1
# save paths from args[]
else
  #sed ensures that directory ends with /
  VAR_DIR_input=`echo $1 | sed '/[^\/]$/s/$/\//'`
  VAR_DIR_output=`echo $2 | sed '/[^\/]$/s/$/\//'`
  VAR_DIR_garbage=`echo $3 | sed '/[^\/]$/s/$/\//'`
  VAR_DIR_watch=`echo $4 | sed '/[^\/]$/s/$/\//'`
  VAR_FILESUF=$5
  VAR_NUMBER_limit=$6
  VAR_LOG_filename=$7
fi


CFG_LOG=${CFG_LOG}${VAR_LOG_filename}

# redirect all 1 output to log file
exec 3<&1
exec >> ${CFG_LOG} 2>&1

# Check folders
if [[(! -d ${VAR_DIR_input}) || (! -d ${VAR_DIR_output}) || (! -d ${VAR_DIR_garbage}) || (! -d ${VAR_DIR_watch}) ]]
then
  echo "Check passed dirs, some not exists:"
  echo "Input dir: ${VAR_DIR_input}"
  echo "Output dir: ${VAR_DIR_output}"
  echo "Gabage dir: ${VAR_DIR_garbage}"
  echo "Watch dir: ${VAR_DIR_watch}"
  exit 2
fi

VAR_DIR_processed="${VAR_DIR_input}Processed/"
if [[ ! -d ${VAR_DIR_processed} ]]
then
  mkdir -p ${VAR_DIR_processed}
fi
VAR_DIR_notprocessed="${VAR_DIR_input}NotProcessed/"
if [[ ! -d ${VAR_DIR_notprocessed} ]]
then
  mkdir -p ${VAR_DIR_notprocessed}
fi

# reference file for comparison not to include files under write progress (ftp) - ftp is not included in lsof
VAR_REFERENCE_time=$((`date +"%s"`-1))
VAR_REFERENCE_file=".$$_${VAR_REFERENCE_time}.reference"
touch -d @${VAR_REFERENCE_time} ${VAR_DIR_input}${VAR_REFERENCE_file} || ( echo "FAILED: touch -d @${VAR_REFERENCE_time} ${VAR_DIR_input}${VAR_REFERENCE_file}"; exit 3; )
# finds files in inbox for specified suffix, changed after this run, sorted by epoch timestamp in filename (if available)
ARR_FILES_input=(`find ${VAR_DIR_input} -maxdepth 1 -type f -name "*${VAR_FILESUF}" ! -cnewer ${VAR_DIR_input}${VAR_REFERENCE_file} | awk -F'/' '{ print(substr($NF,match($NF,/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]\./),10)"\011"$0); }' | sort -nr | awk '{ print($2); }'`)
rm ${VAR_DIR_input}${VAR_REFERENCE_file}
# get number of files in watch dir and calc how many to ungzip from input dir
VAR_NUMBER_watch=`find ${VAR_DIR_watch} -maxdepth 1 -type f -name "*${VAR_FILESUF}" | wc -l`
VAR_NUMBER_toprocess=$((VAR_NUMBER_limit-VAR_NUMBER_watch))
echo ${VAR_NUMBER_toprocess}
if (( ${#ARR_FILES_input[@]} < ${VAR_NUMBER_toprocess} ))
then
  VAR_NUMBER_toprocess=${#ARR_FILES_input[@]}
fi
# ungzip of every packages
if (( $VAR_NUMBER_toprocess >= 0 ))
then
  for (( j=0; j!=MAX_JOBS; j++ ))
  do
    THREADS_PID[j]=0
  done
  i=0
  JOBS_REMAINING=${VAR_NUMBER_toprocess}
  while (( ${JOBS_REMAINING} > 0 ))
  do
    for (( j=0; j!=MAX_JOBS; j++ ))
    do
      if (( ( ${THREADS_PID[j]} == 0 ) && (${i} < ${VAR_NUMBER_toprocess}) ))
      then
        processfile ${j} ${ARR_FILES_input[i]} &
        THREADS_PID[j]=$!
        THREADS_NAME[j]=${i}
        THREADS_START[j]=$(date +"%s")
        #echo "[${j}] ... job ${i} STARTED processid $!"
        i=$((i+1))
      else
        if (( THREADS_PID[j] > 0 ))
        then
          if kill -0 ${THREADS_PID[j]} 2>/dev/null #kill -0 returns true if process still running
          then
            CURRENT_TIME=$(date +"%s")
            if (( (${CURRENT_TIME}-${THREADS_START[j]}) > ${MAX_JOB_SEC} )) #check time how long process is running
            then
              echo "[${j}] job ${THREADS_NAME[j]} is running too long - KILLING ${THREADS_PID[j]}"
              kill ${THREADS_PID[j]}
              notifykillmail ${THREADS_PID[j]} ${THREADS_NAME[j]} ${THREADS_START[j]} ${ARR_FILES_input[${THREADS_NAME[j]}]}
            fi
          else
            #if wait ${THREADS_PID[j]} #wait returns true if process ended successfully (0)
            #then
            #  echo "[${j}] job ${THREADS_NAME[j]} finished with SUCCESS status"
            #else
            #  echo "[${j}] job ${THREADS_NAME[j]} finished with FAIL status"
            #fi
            JOBS_REMAINING=$((JOBS_REMAINING-1))
            THREADS_PID[j]=0
          fi
        fi
      fi
    done
    sleep 1 #optional/recommended to lower cpu usage
  done
else
  echo "WARNING: more files in watch dir ($VAR_NUMBER_watch) than limit ($VAR_NUMBER_limit)"
fi

exit 0
