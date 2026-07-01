#!/bin/bash
#
# Extract SubCon PP_FINALLOT Reference Data.
#
# MODIFICATION HISTORY
#
# WHEN      WHO 		WHAT
# --------- ------- ------------------------------------------
# 31-Oct-17 jgarcia initial
# 20-Feb-18 jgarcia replaced sql statement
# 06-Mar-18 sboothby Added lot classes 6Z, CH
# 19-Mar-18 sboothby Fixed an issue caused by some parts not present in the LOTG_BOM_TYPE table.
# 03-Feb-21 jgarcia convert from csh to bash script
# 24-Nov-21 kgabato updated ora_ip, ora_sid and connection string
# 09-Feb-22 sboothby changed connection string to exaCC DB
# 26-Aug-22 sboothby fixed performance issue, removed restrictions on some lot classes
isError=0

if [ -z "${REFERENCE_DATA_DIR}" ] 
then
   export REFERENCE_DATA_DIR=""
   isError=1 
fi

if [ ! -d $REFERENCE_DATA_DIR ] 
then
   isError=1 
fi


if [ $isError -ne 1 ]
then
   if [[ "$2" != "LOTGDB_PASSWORD" || "$2" == "" ]]
   then
      isError=1 
   fi
fi

if [ $isError -eq 1 ]
then
   echo "USAGE: $0:t oracle-user oracle-password oracle-sid [from-date to-date]"
   echo " " 
   echo "Environment variable REFERENCE_DATA_DIR must be set to a valid directory"
   #echo "if password is YMS_PASSWORD, use value in environment variable YMS_PASSWORD"

   exit 1
fi

if [ "$1" == "LOTGDB_USER" ]
then
  ora_user="LOTG_READ"
else
  ora_user="$1"
fi

if [ "$2" == "LOTGDB_PASSWORD" ]
then
   ora_pass="prdlotgr"
else
   ora_pass="$2"
fi

ora_port="1724"

if [ "$3" == "LOTGPRD" ] 
then
	ora_ip="lotg-db.onsemi.com"
	ora_sid="LOTG.onsemi.com"
	connectionString="(DESCRIPTION=(ADDRESS_LIST=(LOAD_BALANCE = OFF)(FAILOVER = ON)(ADDRESS = (PROTOCOL = TCP)(HOST = exa01cl02-scan.onsemi.com)(PORT = 1521))(ADDRESS = (PROTOCOL = TCP)(HOST = exa02cl04-scan.onsemi.com)(PORT = 1521))(ADDRESS = (PROTOCOL = TCP)(HOST = exa05cl02-scan.onsemi.com)(PORT = 1521)))(CONNECT_DATA=(SERVER = DEDICATED)(SERVICE_NAME = svcLOTGPRD.onsemi.com)))"
else 
	ora_sid="$3"
	connectionString="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${ora_ip})(PORT=${ora_port}))(CONNECT_DATA=(SERVICE_NAME=${ora_sid})))"
fi

#connectionString="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${ora_ip})(PORT=${ora_port}))(CONNECT_DATA=(SID=${ora_sid})))"
#connectionString="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${ora_ip})(PORT=${ora_port}))(CONNECT_DATA=(SERVICE_NAME=${ora_sid})))"

dateCode=`date +"%Y%m%d_%H%M%S"`
#set rootDir = /home/dpower/project/work/sboothby/dbextract_scripts
#set rootDir = /home/dpower/project/work/jgarcia/dbextract_scripts
archiveDir=/apps/exensio_data/archives-yms/reference_data/lot
rootDir=$REFERENCE_DATA_DIR
tmpDir=$rootDir/tmp
outFile=$rootDir/SubconFlotRefData-${dateCode}.subconFlot
outFileTmp=$tmpDir/SubconFlotRefData-${dateCode}.subconFlot.tmp
logFile=$rootDir/log/$(basename $0).${dateCode}.log
tmpScript=$rootDir/tmp/$(basename $0).$$.sql
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
set SERVEROUTPUT ON SIZE UNLIMITED;
set FLUSH OFF;
spool $outFileTmp;
select 'LOT|LOT_OWNER|PRODUCT|DATE_CODE' from DUAL;
WITH lot_classes AS
(
SELECT /*+ MATERIALIZE */ UNIQUE LOTCLASS_CD
FROM LOTG_OWNER.LOT_CLASS
WHERE LOTCLASS_CD in ('BT','MT','MU','BR','MP','MQ','BQ','KP','KX','BU','SS','ST','BV','CL','CH')
)
, recent_lot_classes as
(
SELECT /*+ MATERIALIZE*/ unique LOTCLASS_CD, DESCRIPTION from
(SELECT LOTCLASS_CD, DESCRIPTION
      , DENSE_RANK() over (partition by LOTCLASS_CD order by UPDATE_DATE desc) dr
from LOTG_OWNER.LOT_CLASS
) where dr=1
)
, lot_info as(
SELECT  /*+ INDEX(v SRC_POSTDATE) */
     --CASE WHEN PARENT_LOT_NUM = LOT_NUM then ' ' ELSE REGEXP_SUBSTR(PARENT_LOT_NUM, '([^-]+)?', 1, 1,'i') END AS PARENT_LOT
       REGEXP_SUBSTR(FK0GENEALOGY_MAIDE, '([^-]+)?', 1, 1,'i') AS LOT
     , CASE WHEN lcc.DESCRIPTION like '%ENG%' THEN 'E' ELSE 'P' END  AS LOT_OWNER
     , regexp_replace(case when (regexp_like(v.FK0GENEALOGY_MAFK, '^.+-.+-...\$')
                              or regexp_like(v.FK0GENEALOGY_MAFK, '^.+-(ASM|ASY|WDQ|FAB|DSG|EPC|ECH|DFF|SCB|UTP|BMP|WFA|WBP|WPR|BSM|FSM|SWF|FTP|TST|XTD|FTD|APT|UTD|EPT|EPU|XTP|WAF|DIE|XWF|THN|FMD|XMD|EPM|BAS|DWR|NRE|XDW|GLD|XDI|XDS|EPD|DST|EPA|EPW)\$'))
                           then substr(v.FK0GENEALOGY_MAFK, 1, instr(v.FK0GENEALOGY_MAFK, '-', -1)-1)
                 else v.FK0GENEALOGY_MAFK end, '-', '_') as PRODUCT
     , 'UNKNOWN' as DATE_CODE
     , DENSE_RANK() OVER (PARTITION BY REGEXP_SUBSTR(FK0GENEALOGY_MAIDE, '([^-]+)?', 1, 1,'i') order by v.post_date desc, v.post_time desc) as dr 
FROM LOTG_OWNER.SRC_TGT_XREF v
JOIN recent_lot_classes lcc on v.FK0GENEALOGY_MACLA = lcc.LOTCLASS_CD
JOIN LOTG_OWNER.PC_ITEM pi on v.FK0GENEALOGY_MAFK = pi.PART_ID
WHERE --NOT (FK0GENEALOGY_MAIDE = FK_GENEALOGY_MAIDE and exists(select 1 from lot_classes where LOTCLASS_CD = v.FK_GENEALOGY_MACLA ))
  NOT EXISTS(SELECT 1 FROM lot_classes WHERE LOTCLASS_CD = v.FK_GENEALOGY_MACLA)
  AND POST_DATE >= trunc(sysdate - 2)
  AND pi.PART_TYPE in ('Assembly Part', 'Test Part') --  'Orderable Part', 'Diced Part'
)
select LOT||'|'||LOT_OWNER||'|'||PRODUCT||'|'||DATE_CODE AS LOTS from lot_info WHERE dr=1
;
quit;
eof

sqlplus -s ${ora_user}/${ora_pass}@"${connectionString}" @${tmpScript} > $logFile

if [ -f "$tmpScript" ]
then
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

