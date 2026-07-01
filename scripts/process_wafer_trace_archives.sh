#!/bin/bash
#
# Process wafer trace files sent to archive folder by son_SiCwaferTrace.pl.
#
# MODIFICATION HISTORY
#
# WHEN      WHO WHAT
# --------- --- ------------------------------------------
# 30-Aug-22 SAB Initial.

inDir=/apps/exensio_data/archives-yms/reference_data/wafer_trace
archDir=/apps/exensio_data/archives-yms/reference_data/wafer_trace_archive
mdlDir=/apps/exensio_data/archives-yms/reference_data/wafer_trace_upload_to_mdl

dateCode=$(date +"%Y%m%d")

logFile=$DPLOG/process_wafer_trace_archives.$dateCode.log

cd $inDir

nFiles=0
while read -r -d '' line; do
    ((nFiles++))
    base=$(basename $line)
    /bin/gzip $base
    /bin/cp $base.gz $mdlDir/
    /bin/mv $base.gz $archDir/
done < <(find . -mmin +5 -name "*.f2p.csv" -print0)
# Files should be older than 5 minutes to ensure you don't archive while the file is being written
curTime=$(date +"%Y-%m-%d %H:%M:%S")
echo "$curTime Processed $nFiles FAB2PUCK files" >> $logFile

nFiles=0
while read -r -d '' line; do
    ((nFiles++))
    base=$(basename $line)
    /bin/gzip $base
    /bin/cp $base.gz $mdlDir/
    /bin/mv $base.gz $archDir/
done < <(find . -mmin +5 -name "*.e2p.csv" -print0)
# Files should be older than 5 minutes to ensure you don't archive while the file is being written
curTime=$(date +"%Y-%m-%d %H:%M:%S")
echo "$curTime Processed $nFiles EPI2PUCK files" >> $logFile

# PUCK2FAB is archived only, not sent to MDL
nFiles=0
while read -r -d '' line; do
    ((nFiles++))
    base=$(basename $line)
    /bin/gzip $base
    #/bin/cp $base.gz $mdlDir/
    /bin/mv $base.gz $archDir/
done < <(find . -mmin +5 -name "*.p2f.csv" -print0)
# Files should be older than 5 minutes to ensure you don't archive while the file is being written
curTime=$(date +"%Y-%m-%d %H:%M:%S")
echo "$curTime Processed $nFiles PUCK2FAB files" >> $logFile
