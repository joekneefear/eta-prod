#!/bin/bash
#
# Extract SubCon PP_LOT Reference Data.
#
# MODIFICATION HISTORY
#
# WHEN      WHO 		WHAT
# --------- ------- ------------------------------------------
# 31-Oct-17 jgarcia initial
# 20-Feb-18 jgarcia replaced sql statemen
# 14-Mar-18 sboothby Added ZW lot class.
# 30-Mar-18 sboothby Exclude parent lots if they are shipment receipt material logged in ORN_OUT_ORACLE_TRAK and ORN_RECEIPTS.
# 03-Aug-18 sboothby When the parent lot is an inventory recipt, don't exclude the lot but instead use parent_lot=lot.
# 14-Aug-18 sboothby Assume all parent lots starting with SND* are shipment (purchased) lots.
# 03-Feb-21 jgarcia converted from csh to bash script.
# 24-Nov-21 kgabato updated ora_ip, ora_sid and connection string
# 09-Feb-22 sboothby changed connection string to exaCC DB
# 26-Aug-22 sboothby Fixed performance issue, changed method for determining fab + probe product types
# 21-Oct-22 sboothby Fixed issue causing substrate source lot to be returned when LOTG_BOM_TYPE was missing records for substrate products
# 11-Nov-22 sboothby Broadened the lot classes extracted to ensure it this query is capturing all potential FCS site material
# 28-Nov-22 sboothby Return fab product as product ID wherever possible
# 30-Mar-23 sboothby Increase default time interval to 32 hours from 16 hours.
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

if [[ !($# -eq 3 || $# -eq 5) ]]
then
   echo "NOT 3 or 5"
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
   echo "USAGE: $0: oracle-user oracle-password oracle-sid [from-date to-date]"
   echo " " 
   echo "Environment variable REFERENCE_DATA_DIR must be set to a valid directory"
   #echo "if password is YMS_PASSWORD, use value in environment variable YMS_PASSWORD"

   exit 1
fi

if [[ "$1" == "LOTGDB_USER" ]]
then
  ora_user="LOTG_READ"
else
  ora_user="$1"
fi

if [[ "$2" == "LOTGDB_PASSWORD" ]]
then
   ora_pass="prdlotgr"
else
   ora_pass="$2"
fi

ora_port="1724"

if [[ "$3" == "LOTGPRD" ]] 
then
	ora_ip="lotg-db.onsemi.com"
	ora_sid="LOTG.onsemi.com"
        connectionString="(DESCRIPTION=(ADDRESS_LIST=(LOAD_BALANCE = OFF)(FAILOVER = ON)(ADDRESS = (PROTOCOL = TCP)(HOST = exa01cl02-scan.onsemi.com)(PORT = 1521))(ADDRESS = (PROTOCOL = TCP)(HOST = exa02cl04-scan.onsemi.com)(PORT = 1521))(ADDRESS = (PROTOCOL = TCP)(HOST = exa05cl02-scan.onsemi.com)(PORT = 1521)))(CONNECT_DATA=(SERVER = DEDICATED)(SERVICE_NAME = svcLOTGPRD.onsemi.com)))"
else 
	ora_sid="$3"
        connectionString="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${ora_ip})(PORT=${ora_port}))(CONNECT_DATA=(SERVICE_NAME=${ora_sid})))"
fi

if [ "$#" -gt 3 ]
then
   from_date="$4"
   to_date="$5"
   time_interval="and POST_DATE between TO_DATE('${from_date}', 'YYYY-MM-DD') AND TO_DATE('${to_date} 23:59:59', 'YYYY-MM-DD HH24:MI:SS')"
   dateCode="${from_date}_${to_date}"
else
   time_interval="and POST_DATE >= sysdate - 32*interval '1' hour"
   dateCode=`date +"%Y%m%d_%H%M%S"`
fi

#connectionString="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${ora_ip})(PORT=${ora_port}))(CONNECT_DATA=(SID=${ora_sid})))"
#connectionString="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${ora_ip})(PORT=${ora_port}))(CONNECT_DATA=(SERVICE_NAME=${ora_sid})))"

#set rootDir = /home/dpower/project/work/sboothby/dbextract_scripts
#set rootDir = /home/dpower/project/work/jgarcia/dbextract_scripts
archiveDir=/apps/exensio_data/archives-yms/reference_data/lot
rootDir=$REFERENCE_DATA_DIR
tmpDir=$rootDir/tmp
outFile=$rootDir/SubconLotRefData-${dateCode}.subconLot
outFileTmp=$tmpDir/SubconLotRefData-${dateCode}.subconLot.tmp
logFile=$rootDir/log/$(basename $0).${dateCode}.log
tmpScript=$rootDir/tmp/$(basename $0).$$.sql

cat << eof  > ${tmpScript}
alter session set nls_date_format = 'YYYY-MM-DD HH24:MI:SS';
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
select 'LOT|PARENT_LOT|PRODUCT|LOT_OWNER|SOURCE_LOT' from DUAL;
declare lastLot varchar2(20);
BEGIN
FOR c IN (
WITH lot_classes AS
( 
SELECT /*+ MATERIALIZE */ UNIQUE LOTCLASS_CD
FROM LOTG_OWNER.LOT_CLASS
WHERE DESCRIPTION not like 'INVENTORY CONV%' 
-- LOTCLASS_CD in ('9K','U5','CK','AO','FJ','HC','HH','HV','HX','TB','TP','K0','K6','2K','Y2','7J','C1','RE','2T','L1','EB','3E','CB','EP','FP','FY','V3','K3','FP','N2','N8'
--,'TC','3E','HJ','HQ','3K','PJ','HA','BT','MT','MU','BR','MP','MQ','BQ','KP','KX','BU','SS','ST','BV','CH','CL','ZW')
)
, src_tgt_xref_with as
(
SELECT
  FROM_BANK_CODE,
  TO_BANK_CODE,
  REVERSAL_FLAG,
  FK_GENEALOGY_MAFK AS PARENT_PART_ID,
  FK_GENEALOGY_MACLA AS PARENT_LOT_CLASS,
  FK_GENEALOGY_MAIDE AS PARENT_LOT_NUM,
  FK_GENEALOGY_MANOD AS PARENT_TRANSDATE,
  FK_GENEALOGY_MANOT AS PARENT_TRANSTIME,
  FK0GENEALOGY_MAFK  AS PART_ID,
  FK0GENEALOGY_MACLA AS LOT_CLASS,
  FK0GENEALOGY_MAIDE AS LOT_NUM,
  FK1GENEALOGY_MANOD AS TRANSDATE,
  FK1GENEALOGY_MANOT AS TRANSTIME,
  POST_DATE,
  POST_TIME
  FROM LOTG_OWNER.SRC_TGT_XREF 
)
, lot_ref as (
SELECT /*+ MATERIALIZE INDEX(v SRC_POSTDATE) */ UNIQUE
       REGEXP_SUBSTR(FK0GENEALOGY_MAIDE, '([^-]+)?', 1, 1,'i') AS LOT
     , v.FK0GENEALOGY_MAFK as PART_ID
     , v.FK0GENEALOGY_MACLA as LOT_CLASS
     , REGEXP_SUBSTR(CASE WHEN FK_GENEALOGY_MACLA LIKE 'B%' or
                               COALESCE(ip.type, ppi.PART_TYPE) not in ('WFR', 'DIE', 'WAFER','BAS','Diced Part','WDQ Part','Wafer Fab Part','Wafer Post Fab Part') or
                               v.FK_GENEALOGY_MAIDE like 'SND%'
                     THEN FK0GENEALOGY_MAIDE 
                     ELSE FK_GENEALOGY_MAIDE END, '([^-]+)?', 1, 1,'i')    AS PARENT_LOT
     , CASE WHEN COALESCE(ip.type, ppi.PART_TYPE) not in ('WFR', 'DIE', 'WAFER', 'BAS','Diced Part','WDQ Part','Wafer Fab Part','Wafer Post Fab Part') or
                 FK_GENEALOGY_MACLA LIKE 'B%' or
                 v.FK_GENEALOGY_MAIDE like 'SND%' 
            THEN v.FK0GENEALOGY_MAFK 
            ELSE FK_GENEALOGY_MAFK END as PARENT_PART_ID
     , CASE WHEN lcc.DESCRIPTION like '%ENG%' THEN 'E' ELSE 'P' END  AS LOT_OWNER
     , DENSE_RANK() OVER (PARTITION BY REGEXP_SUBSTR(FK0GENEALOGY_MAIDE, '([^-]+)?', 1, 1,'i') ORDER BY v.FK1GENEALOGY_MANOD, v.FK1GENEALOGY_MANOT) as DR
from LOTG_OWNER.SRC_TGT_XREF v
  LEFT JOIN LOTG_OWNER.LOT_CLASS lcc on v.FK0GENEALOGY_MACLA = lcc.LOTCLASS_CD
  LEFT JOIN LOTG_OWNER.LOTG_BOM_TYPE ip on v.FK_GENEALOGY_MAFK = ip.PART
  JOIN LOTG_OWNER.PC_ITEM ppi on v.FK_GENEALOGY_MAFK = ppi.PART_ID
  JOIN LOTG_OWNER.PC_ITEM pi on v.FK0GENEALOGY_MAFK = pi.PART_ID
where FK0GENEALOGY_MACLA in (select LOTCLASS_CD from lot_classes)
  ${time_interval}
   --and POST_DATE >= sysdate - 24*interval '1' hour  --TO_DATE('2017-10-30', 'YYYY-MM-DD')
   --AND to_date(to_char(POST_DATE, 'YYYY-MM-DD') || ' ' || substr(POST_DATE, 1, 4), 'YYYY-MM-DD HH24MI') + CAST(substr(POST_TIME, 5, 2) AS INT)*INTERVAL '1' SECOND > sysdate - 6*interval '1' hour
   AND pi.PART_TYPE in ('Wafer Post Fab Part', 'Wafer Fab Part', 'WDQ Part')
   AND NOT (v.FROM_BANK_CODE = 'XFCS' and v.FK0GENEALOGY_MAIDE = v.FK_GENEALOGY_MAIDE)
   AND NOT EXISTS(SELECT 1 from src_tgt_xref_with vx where v.FK0GENEALOGY_MAIDE != v.FK_GENEALOGY_MAIDE AND vx.LOT_NUM = v.FK0GENEALOGY_MAIDE and vx.PARENT_LOT_NUM != v.FK_GENEALOGY_MAIDE
                        and vx.TRANSDATE = v.FK1GENEALOGY_MANOD and vx.TRANSTIME = v.FK1GENEALOGY_MANOT and vx.PART_ID = v.FK0GENEALOGY_MAFK and vx.PARENT_PART_ID = v.FK_GENEALOGY_MAFK)
   AND FK0GENEALOGY_MACLA NOT LIKE 'B%'
)
--select * from lot_ref;
, walk as
(
SELECT /*+ MATERIALIZE */ UNIQUE w.* FROM
(
SELECT LOT_NUM, LOT_CLASS, PART_ID
, PARENT_LOT_NUM, PARENT_LOT_CLASS, PARENT_PART_ID
, TRANS_DT, PARENT_TRANS_DT
, CONNECT_BY_ROOT lot_num as TOP
--, RANK() OVER (PARTITION BY LOT_NUM ORDER BY TRANS_DT) AS DR
FROM (
SELECT LOT_NUM, LOT_CLASS, PART_ID
, CASE WHEN REGEXP_LIKE(PARENT_LOT_NUM, '^M0.+\d[A-Z]\$') THEN SUBSTR(PARENT_LOT_NUM, 1, LENGTH(PARENT_LOT_NUM)-1) 
       WHEN REGEXP_LIKE(PARENT_LOT_NUM, '^PW.+\d+[A-Z]\$') THEN SUBSTR(PARENT_LOT_NUM, 1, LENGTH(PARENT_LOT_NUM)-1) 
       ELSE PARENT_LOT_NUM 
       END AS PARENT_LOT_NUM
, PARENT_LOT_CLASS, PARENT_PART_ID
, to_date(to_char(TRANSDATE, 'YYYY-MM-DD') || ' ' || substr(TRANSTIME, 1, 4), 'YYYY-MM-DD HH24MI') + CAST(substr(TRANSTIME, 5, 2) AS INT)*INTERVAL '1' SECOND as TRANS_DT
, to_date(to_char(PARENT_TRANSDATE, 'YYYY-MM-DD') || ' ' || substr(PARENT_TRANSTIME, 1, 4), 'YYYY-MM-DD HH24MI') + CAST(substr(PARENT_TRANSTIME, 5, 2) AS INT)*INTERVAL '1' SECOND as PARENT_TRANS_DT
FROM src_tgt_xref_with v
-- For WDQ transactions where part and parent part are the same, these parent/child relationships are allowed as long as there isn't a matching transaction with a different lot and the same trans_dt
WHERE NOT EXISTS(SELECT 1 from src_tgt_xref_with vx where vx.LOT_NUM = v.LOT_NUM and vx.PARENT_LOT_NUM != v.PARENT_LOT_NUM 
                        and vx.TRANSDATE = v.TRANSDATE and vx.TRANSTIME = v.TRANSTIME and vx.PART_ID = v.PART_ID and vx.PARENT_PART_ID = v.PARENT_PART_ID)
-- Disallow parent lots coming from purchased materials and transacted via a pass-through to transfer it to the MES.  These are not the foundry lot numbers but are instead artificial shipment numbers.
  --AND NOT EXISTS(SELECT 1 FROM LOTG_OWNER.ORN_OUT_ORACLE_TRAK oot JOIN LOTG_OWNER.ORN_RECEIPTS oor on oot.originator = oor.lot_num WHERE oot.LOT_ID = PARENT_LOT_NUM and oot.ORIGINATOR = LOT_NUM)
  --AND PARENT_LOT_CLASS NOT LIKE 'B%'
  AND PARENT_LOT_NUM NOT LIKE 'SND%'
) v
CONNECT BY NOCYCLE PRIOR PARENT_PART_ID = PART_ID
               AND PRIOR PARENT_LOT_NUM = LOT_NUM
START WITH EXISTS(SELECT 1 FROM lot_ref sl WHERE sl.PARENT_LOT = v.LOT_NUM and sl.DR=1)
) w
LEFT JOIN LOTG_OWNER.PC_ITEM i on w.PARENT_PART_ID = i.PART_ID
WHERE PART_TYPE not in ('Substrate Part', 'Ingot Part', 'PolySilicon Part')/*pbt.type not in ( 'EPI', 'SWFR', 'SUBST', 'SUBT', 'POLY')*/ and w.PARENT_PART_ID not like '%-BAS'
)
--select * from walk;
, translate as (
select UNIQUE
       REGEXP_SUBSTR(w.LOT_NUM, '([^-]+)?', 1, 1,'i')           AS LOT
     , LOT_CLASS
     , CASE WHEN lcc.DESCRIPTION like '%ENG%' THEN 'E' ELSE 'P' END  AS LOT_OWNER
     , REGEXP_REPLACE(case when (regexp_like(w.PART_ID, '^.+-.+-...\$') 
                             or regexp_like(w.PART_ID, '^.+-(ASM|ASY|WDQ|FAB|DSG|EPC|ECH|DFF|SCB|UTP|BMP|WFA|WBP|WPR|BSM|FSM|SWF|FTP|TST|XTD|FTD|APT|UTD|EPT|EPU|XTP|WAF|DIE|XWF|THN|FMD|XMD|EPM|BAS|DWR|NRE|XDW|GLD|XDI|XDS|EPD|DST|EPA|EPW)\$')) 
                           then substr(w.PART_ID, 1, instr(w.PART_ID, '-', -1)-1)
                      else w.PART_ID end, '-', '_') as PRODUCT
     , COALESCE(cbt.TYPE, 'UNK') as BOM_PART_TYPE                      
     , i.PART_TYPE
     , REGEXP_SUBSTR(w.PARENT_LOT_NUM, '([^-]+)?', 1, 1,'i')    AS PARENT_LOT
     , PARENT_LOT_CLASS
     , REGEXP_REPLACE(case when (regexp_like(w.PARENT_PART_ID, '^.+-.+-...\$') 
                             or regexp_like(w.PARENT_PART_ID, '^.+-(ASM|ASY|WDQ|FAB|DSG|EPC|ECH|DFF|SCB|UTP|BMP|WFA|WBP|WPR|BSM|FSM|SWF|FTP|TST|XTD|FTD|APT|UTD|EPT|EPU|XTP|WAF|DIE|XWF|THN|FMD|XMD|EPM|BAS|DWR|NRE|XDW|GLD|XDI|XDS|EPD|DST|EPA|EPW)\$')) 
                           then substr(w.PARENT_PART_ID, 1, instr(w.PARENT_PART_ID, '-', -1)-1)
                      else w.PARENT_PART_ID end, '-', '_') as PARENT_PRODUCT
     , COALESCE(pbt.TYPE, 'UNK') as PARENT_PART_TYPE                      
     , TRANS_DT
from walk w
left JOIN LOTG_OWNER.LOTG_BOM_TYPE pbt on w.PARENT_PART_ID = pbt.PART
LEFT JOIN LOTG_OWNER.PC_ITEM i on w.PART_ID = i.PART_ID
left JOIN LOTG_OWNER.LOTG_BOM_TYPE cbt on w.PART_ID = cbt.PART
LEFT JOIN LOTG_OWNER.LOT_CLASS lcc on w.LOT_CLASS = lcc.LOTCLASS_CD
--WHERE pbt.TYPE is null or pbt.type not in ( 'EPI', 'SWFR', 'SUBST', 'SUBT', 'POLY')
)
--select * from translate;
, src_lot_walk as 
(
SELECT LOT, PRODUCT, PARENT_LOT, PARENT_PRODUCT, CONNECT_BY_ROOT LOT as TOP
, RANK() OVER (PARTITION BY CONNECT_BY_ROOT LOT ORDER BY TRANS_DT) AS DR
FROM translate w
CONNECT BY NOCYCLE PRIOR PARENT_PRODUCT = PRODUCT AND PRIOR PARENT_LOT = LOT
START WITH PART_TYPE IN ('Wafer Post Fab Part', 'Wafer Fab Part', 'WDQ Part')--PART_TYPE in ('WFR', 'DIE')
UNION ALL
SELECT PARENT_LOT as LOT, PARENT_PRODUCT as PRODUCT, PARENT_LOT, PARENT_PRODUCT, PARENT_LOT as TOP, 1 as DR
FROM translate w1
WHERE NOT EXISTS (SELECT 1 FROM translate w2 where w1.PARENT_PRODUCT = w2.PRODUCT and w1.PARENT_LOT = w2.LOT)
)
--select * from src_lot_walk; --where t.lot like 'KG79WY2X%';
, src_lot as
( 
SELECT UNIQUE TOP AS LOT, PARENT_LOT AS SOURCE_LOT, PARENT_PRODUCT
FROM src_lot_walk w
WHERE DR = 1
)
--select * from src_lot;
SELECT UNIQUE l.LOT
     , LOT_CLASS
     , PARENT_LOT
     , regexp_replace(case when (regexp_like(PART_ID, '^.+-.+-...\$') 
                              or regexp_like(PART_ID, '^.+-(ASM|ASY|WDQ|FAB|DSG|EPC|ECH|DFF|SCB|UTP|BMP|WFA|WBP|WPR|BSM|FSM|SWF|FTP|TST|XTD|FTD|APT|UTD|EPT|EPU|XTP|WAF|DIE|XWF|THN|FMD|XMD|EPM|BAS|DWR|NRE|XDW|GLD|XDI|XDS|EPD|DST|EPA|EPW)\$')) 
                           then substr(PART_ID, 1, instr(PART_ID, '-', -1)-1)
                 else PART_ID end, '-', '_') as PRODUCT
     , regexp_replace(case when (regexp_like(sl.PARENT_PRODUCT, '^.+-.+-...\$')
                              or regexp_like(sl.PARENT_PRODUCT, '^.+-(ASM|ASY|WDQ|FAB|DSG|EPC|ECH|DFF|SCB|UTP|BMP|WFA|WBP|WPR|BSM|FSM|SWF|FTP|TST|XTD|FTD|APT|UTD|EPT|EPU|XTP|WAF|DIE|XWF|THN|FMD|XMD|EPM|BAS|DWR|NRE|XDW|GLD|XDI|XDS|EPD|DST|EPA|EPW)\$'))
                           then substr(sl.PARENT_PRODUCT, 1, instr(sl.PARENT_PRODUCT, '-', -1)-1)
                 else sl.PARENT_PRODUCT end, '-', '_') as PARENT_PRODUCT
     , LOT_OWNER
     , COALESCE(sl.SOURCE_LOT, PARENT_LOT, ' ' ) AS SOURCE_LOT
FROM lot_ref l
LEFT JOIN src_lot sl on l.PARENT_LOT = sl.LOT
WHERE l.DR=1
ORDER BY l.lot
)
LOOP
BEGIN
   DBMS_OUTPUT.PUT_LINE(c.LOT||'|'||c.PARENT_LOT||'|'||coalesce(c.PARENT_PRODUCT, c.PRODUCT)||'|'||c.LOT_OWNER||'|'||c.SOURCE_LOT);
END;
END LOOP;
END;
/
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
    /bin/gzip -f $archiveDir/$b_name
  fi
  /bin/mv $outFileTmp $outFile
fi

