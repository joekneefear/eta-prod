#!/bin/bash
#
# Extract slice, boule, and eCofA ID from eCofA DB for raw silicon only
#
# MODIFICATION HISTORY
#
# WHEN      WHO WHAT
# --------- --- ------------------------------------------
# 21-Jul-22 SAB Initial. 
# 26-Dec-22 SAB Adjusted for GRWEBPRD server name.
# 25-Apr-24 SAB Performance improvements.  Added PID to output file name to avoid collision between multiple processes
# 17-May-24 SAB Added more CASE statements to return currect raw material supplier when wafer is turnkey or consigned.
# 23-Jul-24 SAB Account for invalid years starting with 00
# 22-May-25 SAB Support migration to AZ GIQAP database
. /export/home/dpower/.bashrc_oracle11client

isError=0 
product_like=""

if [ -z "${REFERENCE_DATA_DIR}" ]
then
   export REFERENCE_DATA_DIR=""
   isError=1 
fi

if [ ! -d $REFERENCE_DATA_DIR ] 
then
   isError=1 
fi

if [ $# -ne 6 ] 
then
   isError=1
fi

if [ $isError -eq 0 ] 
then
   if [ "$2" != "ECOFA_PASSWORD" ] || [ "$2" == "" ] 
   then
      isError=1 
   fi
fi

if [ $isError -ne 0 ] 
then
   echo "ARG1=$1||ARG2=$2||ARG3=$3"
   echo "Args=$#"
   echo "USAGE: $(basename $0) db-user db-password db-sid schema-owner relative-days-start relative-days-end"
   echo " " 
   echo "Environment variable REFERENCE_DATA_DIR must be set to a valid directory"
   exit 1
fi

ora_user="$1"
if [ "$2" == "ECOFA_PASSWORD" ] 
then
   ora_pass="$ECOA_PASS"
else
   ora_pass="$2"
fi

if [ "$3" == "GPWEB0" ] || [ "$3" == "GRWEBPRD" ] || [ "$3" == "GIQAQ" ] || [ "$3" == "GIQAP" ] 
then
   connectionString="$3"
else 
   ora_sid="$3"
   ora_port=1634
   connectionString="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${ora_ip})(PORT=${ora_port}))(CONNECT_DATA=(SID=${ora_sid})))"
fi
schemaOwner=$4
relStart=$5
relEnd=$6

dateCode=`date +"%Y%m%d_%H%M%S"`
#rootDir=/apps/exensio_data/reference_data2
#archiveDir=/export/home/dpower/project/work/sboothby/archive
archiveDir=/apps/exensio_data/archives-yms/reference_data/slice
rootDir=$REFERENCE_DATA_DIR
tmpDir=$rootDir/tmp
outFile=$rootDir/eCofASlice2Boule-$$-${dateCode}.slice
outFileTmp=$tmpDir/eCofASlice2Boule-$$-${dateCode}.slice.tmp
logFile=$rootDir/log/$(basename $0).${dateCode}.log
tmpScript=/tmp/$(basename $0).$$.sql

#echo "executing sql statement..."

cat << eof  > ${tmpScript}
set COLSEP |;
set TRIMOUT ON;
set TRIMSPOOL ON;
set LINESIZE 2048;
set PAGESIZE 0;
set HEADSEP OFF;
set TERMOUT OFF;
set FEEDBACK OFF;
set NEWPAGE NONE;
set NUMW 12;
set SERVEROUTPUT ON SIZE 1000000;
set FLUSH OFF;

spool $outFileTmp;
select 'SLICE|GLOBAL_WAFER_ID|PUCK_ID|RUN_ID|SLICE_SOURCE_LOT|START_LOT|FAB_WAFER_ID|FAB_SOURCE_LOT|SLICE_START_TIME|SLICE_PARTNAME|SLICE_LOTTYPE|SLICE_SUPPLIERID|PUCK_HEIGHT|SLICE_ORDER' from dual;
with recent_lots as
(
select /*+ MATERIALIZE */ *
from $schemaOwner.RAWSILICON_LOT l
where l.date_received between sysdate + (1*$relStart) and sysdate + (1*$relEnd)
AND POLYTYPE is not null AND VENDOR_SITE != 'CZ2' 
)
, recent_wafers as
(
select /*+ MATERIALIZE */
       w.WAFER_ID
     , w.WAFER_SCRIBE_ID
     , w.GLOBAL_WAFER_ID
     , w.BOULE_ID
     , w.PART_NUMBER
     , w.WAFER_SLICE_POSITION
     , l.VENDOR_SITE
     , l.VENDOR_LOT_ID
     /*, l.MFG_DATE*/
     , case when mfg_date < to_date('0100', 'YYYY') then mfg_date + 2000 * interval '1' year else mfg_date end as MFG_DATE
     , count(distinct rsl.RAWSILICON_LOT_ID) as qty_rsl
from recent_lots l
join $schemaOwner.WAFER w on l.RAWSILICON_LOT_ID = w.RAWSILICON_LOT_ID
join $schemaOwner.WAFER rsl on w.WAFER_SCRIBE_ID = rsl.WAFER_SCRIBE_ID
where w.WAFER_SCRIBE_ID not like 'CE_____-__'
group by w.WAFER_ID
     , w.WAFER_SCRIBE_ID
     , w.GLOBAL_WAFER_ID
     , w.BOULE_ID
     , w.PART_NUMBER
     , w.WAFER_SLICE_POSITION
     , l.VENDOR_SITE
     , l.VENDOR_LOT_ID
     /*, l.MFG_DATE*/
     , case when mfg_date < to_date('0100', 'YYYY') then mfg_date + 2000 * interval '1' year else mfg_date end 
)
, params as
(
SELECT /*+ MATERIALIZE */ p.*
FROM recent_wafers w
JOIN $schemaOwner.wafer_parameter p on w.WAFER_ID = p.WAFER_ID
join $schemaOwner.wafer_param_map wpm on p.wafer_param_map_id = wpm.WAFER_PARAM_MAP_ID
WHERE wpm.wafer_param_name like '%EPI%'
)
, results as
(
select WAFER_SCRIBE_ID
     , GLOBAL_WAFER_ID
     , case when VENDOR_SITE = 'CZ2' then ' ' else BOULE_ID end as PUCK_ID
     , case when BOULE_ID like 'G%' and length(BOULE_ID) = 10 then substr(BOULE_ID, 1, 9)
            when VENDOR_SITE = 'CZ2' then ' '
            else BOULE_ID end as RUN_ID
     , case when BOULE_ID like 'G%' and length(BOULE_ID) = 10 then substr(BOULE_ID, 1, 9)
            when VENDOR_SITE = 'CZ2' then ' '
            else BOULE_ID end || '.S' as SLICE_SOURCE_LOT
     , w.VENDOR_LOT_ID as START_LOT
     , ' ' as FAB_WAFER_ID
     , ' ' as FAB_SOURCE_LOT
     , to_char(w.mfg_date, 'YYYY-MM-DD HH24:MI:SS')    as SLICE_START_TIME
     , w.PART_NUMBER as SLICE_PARTNAME
     , ' ' as SLICE_LOTTYPE
     , case when w.PART_NUMBER like 'SIC_S_01%' or w.PART_NUMBER like 'SIC_S_02%' then 'CREE'
            when w.PART_NUMBER like 'SIC_S_03%' then 'SICRYSTL'
            when w.PART_NUMBER like 'SIC_S_04%' then 'SKSILTRN'
            when w.PART_NUMBER like 'SIC_S_05%' then 'II-VI'
            when w.PART_NUMBER like 'SIC_S_06%' or w.PART_NUMBER like 'SIC_S_07%' or w.PART_NUMBER like 'SIC_S_12%' or w.PART_NUMBER like 'SIC_S_13%' or w.PART_NUMBER like 'SIC_S_23%' or w.PART_NUMBER = 'W6350K01' then 'UWH'
            when w.PART_NUMBER like 'SIC_S_08%' or w.PART_NUMBER like 'SIC_S_09%' then 'TANKEBLU'
            when w.PART_NUMBER like 'SIC_S_10%'                                   then 'SHOWASUB'
            when w.PART_NUMBER like 'SIC_S_11%' or w.PART_NUMBER like 'SIC_S_31%' then 'SICC'
            when w.PART_NUMBER like 'SIC_S_14%'                                   then 'TYSIC'
            when w.PART_NUMBER like 'SIC_S_15%'                                   then 'SANANIC'
            when w.PART_NUMBER like 'SIC_S_16%' or w.PART_NUMBER like 'SIC_S_29%' then 'SYNLIGHT'
            when w.PART_NUMBER like 'SIC_S_17%'                                   then 'SOITEC'
            when w.PART_NUMBER like 'SIC_S_18%'                                   then 'TONYTECH'
            when w.PART_NUMBER like 'SIC_S_19%'                                   then 'SICOXS'
            when w.PART_NUMBER like 'SIC_S_20%' or w.PART_NUMBER like 'SIC_S_32%' then 'SEMISIC'
            when w.PART_NUMBER like 'SIC_S_21%' or w.PART_NUMBER like 'SIC_S_33%' then 'GSCS'
            when w.PART_NUMBER like 'SIC_S_22%'                                   then 'SUPERSIC'
            when w.PART_NUMBER like 'SIC_S_24%'                                   then 'NINGBO'
            when w.PART_NUMBER like 'SIC_S_25%'                                   then 'TAISIC'
            when w.PART_NUMBER like 'SIC_S_26%'                                   then 'PALLIDUS'
            when w.PART_NUMBER like 'SIC_S_27%' or w.PART_NUMBER like 'SIC_S_28%' then 'CECCS'
            when w.PART_NUMBER like 'SIC_S_30%'                                   then 'CZ2'
            when VENDOR_SITE = 'GTAT'                                             then 'UWH'
            else VENDOR_SITE
       end           as SLICE_SUPPLIERID
     , 0 as PUCK_HEIGHT
     , WAFER_SLICE_POSITION as SLICE_ORDER
from recent_wafers w 
where /* Raw SiC only*/
     (NOT EXISTS (select 1 from params wp where w.WAFER_ID = wp.WAFER_ID)
        OR (w.qty_rsl = 1 ))
)
select WAFER_SCRIBE_ID
||'|'||GLOBAL_WAFER_ID
||'|'||PUCK_ID
||'|'||RUN_ID
||'|'||SLICE_SOURCE_LOT
||'|'||START_LOT
||'| '
||'| '
||'|'||SLICE_START_TIME
||'|'||SLICE_PARTNAME
||'|'||SLICE_LOTTYPE
||'|'||coalesce(SLICE_SUPPLIERID, ' ')
||'|'||PUCK_HEIGHT
||'|'||SLICE_ORDER
from results
where puck_id is not null
order by 1;
quit;
eof

$ORACLE_HOME/bin/sqlplus -s ${ora_user}/${ora_pass}@"${connectionString}" @${tmpScript} > $logFile

if [ -f "$tmpScript" ] 
then
   #echo $tmpScript
   /bin/rm $tmpScript
fi

if [ -f $outFileTmp ] 
then
  # copy to archive first
  if [ -d $archiveDir ] 
  then
    b_name=$(basename "$outFileTmp" | sed 's/\(.*\)\..*/\1/')
    /bin/cp -p $outFileTmp $archiveDir/$b_name
    /bin/gzip $archiveDir/$b_name
  fi
  /bin/mv $outFileTmp $outFile
fi

