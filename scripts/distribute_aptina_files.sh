#!/bin/bash

INPUTDIR=$1
LOGFILE=$2
FILE_LIMIT=$3
TARGETDIR=$4

echo "INPUTDIR $INPUTDIR"
echo "LOGFILE $LOGFILE"
echo "FILE_LIMIT $FILE_LIMIT"
echo "TARGETDIR $TARGETDIR"

excess=0

cd $INPUTDIR

# Count files in the current directory
FILE_COUNT=$(find . -maxdepth 1 -not -path '*/.*' -type f -print | wc -l)

echo "Number of files in the current directory (including hidden): $FILE_COUNT"

if [ "$FILE_COUNT" -gt "$FILE_LIMIT" ]; then
  echo "FILE_LIMIT $FILE_COUNT is greater than $FILE_LIMIT" >> $LOGFILE
  excess=$((FILE_COUNT - FILE_LIMIT))
  echo "excess $excess"
fi


#INPUTDIR="/apps/exensio_data/data/APTINA_DLOG/PRB_NAMPA/inbox" # Replace with your target directory

for (( i=0; i<excess; i++ ))
     do
       
       for files in "$INPUTDIR"/*; do
          echo "move $(basename "$files") to inbox_2" >> "$LOGFILE" # Prints only the file/directory name
          mv "$files" "$TARGETDIR/"  
          break   
       done
       #echo "Counter: $i"
       
done