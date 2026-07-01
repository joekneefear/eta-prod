#!/bin/bash 
#
## Extract LOTG Genealogy Data.
#
## MODIFICATION HISTORY
#
# WHEN          WHO 		WHAT
# ------------  ------- ------------------------------------------
# 14-Dec-2017   jgarcia initial
# 01-Mar-2018   jgarcia replaced sql statement. ad
# 05-Mar-2018   sboothby Added lot class 6Z and CH.
# 14-Mar-2018   sboothby WALK query STARTS WITH clause join changed to sl.LOT_NUM instead of sl.PARENT_LOT_NUM.
# 02-Apr-2018   sboothby Disallow parent lots coming from purchased materials and transacted via a pass-through to transfer it to the MES.  
#                        These are not the foundry lot numbers but are instead artificial shipment numbers.
# 03-Feb-2021   jgarcia convert to bash from csh
# 24-Nov-2021   kgabato updated ora_ip, ora_sid and connection string
# 09-Feb-2022   sboothby changed connection string to exaCC DB
# 17-May-2022   sboothby Added lot classes for Suzhou
#                        Remove '.0\d\d' from end of source lot (EFK lot #)
#                        Fixed fab name for EFK
#                        Added prefix to fab name
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

#if ($#argv != 4 ) then
#   set isError = 1
#endif

#if ( ! $isError ) then
#   if ( "$2" != "LOTG_PASSWORD" || "$2" == "" ) then
#      set isError = 1 
#   endif
#endif



if [ "$1" == "LOTGDB_USER" ] 
then
	ora_user="LOTG_READ"
else
 isError=1 
fi

if [ "$2" == "LOTGDB_PASSWORD" ]
then
   ora_pass="prdlotgr"
else
   isError=1
fi

if [ "$3" == "LOTGPRD" ]
then
	ora_ip="lotg-db.onsemi.com"
	ora_sid="LOTG.onsemi.com"
else 
	isError=1
fi

if [ $isError -ne 0 ] 
then
   echo "USAGE: $0:t oracle-user oracle-password oracle-sid"
   echo " " 
   echo "Environment variable REFERENCE_DATA_DIR must be set to a valid directory"
   #echo "if password is YMS_PASSWORD, use value in environment variable YMS_PASSWORD"

   exit 1
fi

ora_port="1724"

#set connectionString = "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=10.253.117.69)(PORT=1534))(CONNECT_DATA=(SID=RHYP01)))"
#connectionString="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${ora_ip})(PORT=${ora_port}))(CONNECT_DATA=(SID=${ora_sid})))"
#connectionString="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${ora_ip})(PORT=${ora_port}))(CONNECT_DATA=(SERVICE_NAME=${ora_sid})))"
connectionString="(DESCRIPTION=(ADDRESS_LIST=(LOAD_BALANCE = OFF)(FAILOVER = ON)(ADDRESS = (PROTOCOL = TCP)(HOST = exa01cl02-scan.onsemi.com)(PORT = 1521))(ADDRESS = (PROTOCOL = TCP)(HOST = exa02cl04-scan.onsemi.com)(PORT = 1521))(ADDRESS = (PROTOCOL = TCP)(HOST = exa05cl02-scan.onsemi.com)(PORT = 1521)))(CONNECT_DATA=(SERVER = DEDICATED)(SERVICE_NAME = svcLOTGPRD.onsemi.com)))"

dateCode=`date +"%Y%m%d_%H%M%S"`
archiveDir=/apps/exensio_data/archives-yms/reference_data/genealogy
rootDir=$REFERENCE_DATA_DIR
tmpDir=$rootDir/tmp
outFile=$rootDir/LOTGGenealogy-${dateCode}.lotG2gen
outFileTmp=$tmpDir/LOTGGenealogy-${dateCode}.lotG2gen.tmp
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
BEGIN
FOR c IN (
WITH src_tgt_xref_with as
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
, starting_lots as
(
SELECT LOT_NUM, LOT_CLASS, v.PART_ID 
, CASE WHEN REGEXP_LIKE(PARENT_LOT_NUM, '^M0.+\d[A-Z]\$') THEN SUBSTR(PARENT_LOT_NUM, 1, LENGTH(PARENT_LOT_NUM)-1)
       WHEN REGEXP_LIKE(PARENT_LOT_NUM, '^PW.+\d+[A-Z]\$') THEN SUBSTR(PARENT_LOT_NUM, 1, LENGTH(PARENT_LOT_NUM)-1)
       ELSE PARENT_LOT_NUM
       END AS PARENT_LOT_NUM
, PARENT_PART_ID, v.PARENT_LOT_CLASS
FROM src_tgt_xref_with v
left JOIN LOTG_OWNER.PC_ITEM pi on v.PART_ID = pi.PART_ID
WHERE POST_DATE >= trunc(sysdate) - 24*interval '1' hour  --TO_DATE('2017-10-30', 'YYYY-MM-DD')
  AND to_date(to_char(POST_DATE, 'YYYY-MM-DD') || ' ' || substr(POST_DATE, 1, 4), 'YYYY-MM-DD HH24MI') + CAST(substr(POST_DATE, 5, 2) AS INT)*INTERVAL '1' SECOND > sysdate - 6*interval '1' hour
--and
--lot_num = '1AT654O'--'1AS022Q'--'1AT654O'
--lot_num like 'BPP4890A' and parent_lot_num = 'BPP4890A'
AND NOT ( LOT_NUM = PARENT_LOT_NUM AND v.PART_ID = PARENT_PART_ID)
-- Don't track Orderable Part Numbers (OPNs)
AND (pi.PART_SUBTYPE is NULL or pi.PART_SUBTYPE != 'OPN')
-- Exclude parent lots from the genealogy walk if they are parents in a merge transaction
AND NOT EXISTS(SELECT 1 from src_tgt_xref_with vx where vx.LOT_NUM = v.LOT_NUM and vx.PARENT_LOT_NUM != v.PARENT_LOT_NUM
                        and vx.TRANSDATE = v.TRANSDATE and vx.TRANSTIME = v.TRANSTIME and vx.PART_ID = v.PART_ID and vx.PARENT_PART_ID = v.PARENT_PART_ID)
-- Disallow parent lots coming from purchased materials and transacted via a pass-through to transfer it to the MES.  These are not the foundry lot numbers but are instead artificial shipment numbers.
AND NOT EXISTS(SELECT 1 FROM LOTG_OWNER.ORN_OUT_ORACLE_TRAK oot WHERE oot.LOT_ID = PARENT_LOT_NUM and oot.ORIGINATOR = LOT_NUM)
AND PARENT_LOT_CLASS NOT LIKE 'B%'
and LOT_CLASS in ('ZW','9K','U5','CK','AO','FJ','HC','HH','HV','HX','KP','TB','WE','ST','SS','SH','PH','FH','H1','RK','RW','RD','FN','TP','K0','K6','2K','Y2','7J','C1','RE','2T','L1','EB','3E','CB','EP','FP','FY','V3','K3','FP','N2','N8','TC','3E','HJ','HQ','3K','PJ','HA', '6Z', 'CH', 'CL')
)
--select * from starting_lots;
, walk as
(
SELECT /*+ MATERIALIZE */ UNIQUE w.* FROM
(
SELECT LOT_NUM, LOT_CLASS, PART_ID
, PARENT_LOT_NUM, PARENT_LOT_CLASS, PARENT_PART_ID
, TRANS_DT, PARENT_TRANS_DT
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
-- Exclude parent lots from the genealogy walk if they are parents in a merge transaction
WHERE NOT EXISTS(SELECT 1 from src_tgt_xref_with vx where vx.LOT_NUM = v.LOT_NUM and vx.PARENT_LOT_NUM != v.PARENT_LOT_NUM
                        and vx.TRANSDATE = v.TRANSDATE and vx.TRANSTIME = v.TRANSTIME and vx.PART_ID = v.PART_ID and vx.PARENT_PART_ID = v.PARENT_PART_ID)
-- Disallow parent lots coming from purchased materials and transacted via a pass-through to transfer it to the MES.  These are not the foundry lot numbers but are instead artificial shipment numbers.
AND NOT EXISTS(SELECT 1 FROM LOTG_OWNER.ORN_OUT_ORACLE_TRAK oot WHERE oot.LOT_ID = PARENT_LOT_NUM and oot.ORIGINATOR = LOT_NUM)
AND PARENT_LOT_CLASS NOT LIKE 'B%'
) v
CONNECT BY NOCYCLE PRIOR PARENT_PART_ID = PART_ID
               AND PRIOR PARENT_LOT_NUM = LOT_NUM
START WITH EXISTS(SELECT 1 FROM starting_lots sl
                  WHERE sl.LOT_NUM = v.LOT_NUM AND sl.PART_ID = v.PART_ID
                 )
) w
LEFT JOIN LOTG_OWNER.LOTG_BOM_TYPE pbt on w.PARENT_PART_ID = pbt.PART
LEFT JOIN LOTG_OWNER.PC_ITEM pi on w.PARENT_PART_ID = pi.PART_ID
--WHERE pbt.TYPE is null or pbt.type not in ( 'EPI', 'SWFR', 'SUBST', 'SUBT', 'POLY') and w.PARENT_PART_ID not like '%-BAS'
WHERE (pbt.TYPE is null or pbt.type not in ( 'EPI', 'SWFR', 'SUBST', 'SUBT', 'POLY')) and w.PARENT_PART_ID not like '%-BAS'
  AND (pi.PART_TYPE is null or pi.PART_TYPE not in ('PolySilicon Part', 'Ingot Part', 'Substrate Part'))

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
     , COALESCE(pi.PART_SUBTYPE, cbt.TYPE, 'UNK') as PART_TYPE
     , REGEXP_SUBSTR(w.PARENT_LOT_NUM, '([^-]+)?', 1, 1,'i')    AS PARENT_LOT
     , PARENT_LOT_CLASS
     , REGEXP_REPLACE(case when (regexp_like(w.PARENT_PART_ID, '^.+-.+-...\$')
                             or regexp_like(w.PARENT_PART_ID, '^.+-(ASM|ASY|WDQ|FAB|DSG|EPC|ECH|DFF|SCB|UTP|BMP|WFA|WBP|WPR|BSM|FSM|SWF|FTP|TST|XTD|FTD|APT|UTD|EPT|EPU|XTP|WAF|DIE|XWF|THN|FMD|XMD|EPM|BAS|DWR|NRE|XDW|GLD|XDI|XDS|EPD|DST|EPA|EPW)\$'))
                           then substr(w.PARENT_PART_ID, 1, instr(w.PARENT_PART_ID, '-', -1)-1)
                      else w.PARENT_PART_ID end, '-', '_') as PARENT_PRODUCT
     , COALESCE(ppi.PART_SUBTYPE, pbt.TYPE, 'UNK') as PARENT_PART_TYPE
     , TRANS_DT
from walk w
left JOIN LOTG_OWNER.LOTG_BOM_TYPE pbt on w.PARENT_PART_ID = pbt.PART
left JOIN LOTG_OWNER.LOTG_BOM_TYPE cbt on w.PART_ID = cbt.PART
left JOIN LOTG_OWNER.PC_ITEM pi on w.PART_ID = pi.PART_ID
left JOIN LOTG_OWNER.PC_ITEM ppi on w.PARENT_PART_ID = ppi.PART_ID
LEFT JOIN LOTG_OWNER.LOT_CLASS lcc on w.LOT_CLASS = lcc.LOTCLASS_CD
)
--select * from translate;
, src_lot_walk as
(
SELECT LOT, PRODUCT, PARENT_LOT, PARENT_PRODUCT, CONNECT_BY_ROOT LOT as TOP
, RANK() OVER (PARTITION BY CONNECT_BY_ROOT LOT ORDER BY TRANS_DT) AS DR
FROM translate w
CONNECT BY NOCYCLE PRIOR PARENT_PRODUCT = PRODUCT AND PRIOR PARENT_LOT = LOT
--START WITH PART_TYPE in ('WFR', 'DIE', 'SWF', 'BSM', 'WDQ')
UNION
SELECT PARENT_LOT as LOT, PARENT_PRODUCT as PRODUCT, PARENT_LOT, PARENT_PRODUCT, PARENT_LOT as TOP, 1 as DR
FROM translate w1
WHERE NOT EXISTS (SELECT 1 FROM translate w2 where w1.PARENT_PRODUCT = w2.PRODUCT and w1.PARENT_LOT = w2.LOT)
)
--select * from src_lot_walk; --where t.lot like 'KG79WY2X%';
, src_lot as
(
SELECT UNIQUE TOP AS LOT, PARENT_LOT AS SOURCE_LOT
FROM src_lot_walk w
WHERE DR = 1
)
--select * from src_lot;
, fab_info as
(
SELECT x.LOT_NUM as LOT, x.FROM_BANK_CODE, coalesce(ornr.MFG_AREA_CD, mbs.MFG_AREA_CD)||':'||COALESCE(ornr.VENDOR_NAME, mbs.MFG_AREA_DESC) as FAB_NAME
FROM (SELECT LOT_NUM, TRANSDATE, TRANSTIME, FROM_BANK_CODE
           , RANK() OVER (PARTITION BY LOT_NUM ORDER BY TRANSDATE, TRANSTIME) as RNK
      FROM src_lot sl
      JOIN src_tgt_xref_with b on sl.SOURCE_LOT = b.LOT_NUM
      LEFT JOIN LOTG_OWNER.MFG_BANK_TO_STAGE mbs2 on b.TO_BANK_CODE = mbs2.BANK_CD
      /* Exclude EFK lots originating from non-recording bank.  Ensures correct fab name found */
      WHERE NOT (b.from_bank_code like '000%' and mbs2.MFG_AREA_DESC = 'GF FISHKILL FE CTI')
      ) x
LEFT JOIN LOTG_OWNER.MFG_BANK_TO_STAGE mbs on x.FROM_BANK_CODE = mbs.BANK_CD
LEFT JOIN LOTG_OWNER.ORN_RECEIPTS ornr on x.LOT_NUM = ornr.lot_num 
WHERE x.RNK = 1
)
--select * from fab_info;
SELECT UNIQUE t.LOT, t.LOT_CLASS, t.LOT_OWNER, t.PRODUCT, t.PART_TYPE
     , t.PARENT_LOT, t.PARENT_LOT_CLASS, t.PARENT_PRODUCT, t.PARENT_PART_TYPE, t.TRANS_DT
     , CASE WHEN t.PART_TYPE in ('ASY', 'ACP', 'ASM', 'AS1', 'TST', 'TSD', 'TSM', 'TS1', 'TS2', 'TM1', 'PBU', 'MSA', 'MS1', 'MS2', 'DSG')
            THEN t.LOT
            WHEN f.FAB_NAME like 'UV5:%'
            THEN regexp_replace(CASE when fsl.SOURCE_LOT IS NOT NULL THEN fsl.SOURCE_LOT ELSE t.PARENT_LOT END, '\.0\d\d\$','',1,1)
            ELSE CASE when fsl.SOURCE_LOT IS NOT NULL THEN fsl.SOURCE_LOT ELSE t.PARENT_LOT END
       END as SOURCE_LOT
     , CASE WHEN t.PARENT_PART_TYPE in ('ASY', 'ACP', 'ASM', 'AS1', 'TST', 'TSD', 'TSM', 'TS1', 'TS2', 'TM1', 'PBU', 'MSA', 'MS1', 'MS2')
            THEN t.PARENT_LOT
            WHEN f.FAB_NAME like 'UV5:%'
            THEN regexp_replace(CASE when fsl.SOURCE_LOT IS NOT NULL THEN fsl.SOURCE_LOT ELSE t.PARENT_LOT END, '\.0\d\d\$','',1,1)
            ELSE CASE when fsl.SOURCE_LOT IS NOT NULL THEN fsl.SOURCE_LOT ELSE t.PARENT_LOT END
       END as FROM_SOURCE_LOT
     , CASE WHEN t.PART_TYPE in ('ASY', 'ACP', 'ASM', 'AS1', 'TST', 'TSD', 'TSM', 'TS1', 'TS2', 'TM1', 'PBU', 'MSA', 'MS1', 'MS2')
            THEN ''
       ELSE f.FAB_NAME 
       END as FAB_NAME
     , CASE WHEN t.PARENT_PART_TYPE in ('ASY', 'ACP', 'ASM', 'AS1', 'TST', 'TSD', 'TSM', 'TS1', 'TS2', 'TM1', 'PBU', 'MSA', 'MS1', 'MS2')
            THEN ''
       ELSE f.FAB_NAME 
       END as FROM_FAB_NAME
     , t.PARENT_LOT_CLASS AS SOURCE_LOT_CLASS
FROM translate t
LEFT JOIN src_lot sl ON t.LOT = sl.LOT
LEFT JOIN src_lot fsl ON t.PARENT_LOT = fsl.LOT
LEFT JOIN fab_info f on CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END = f.LOT
WHERE t.LOT != t.PARENT_LOT
/* Exclude Nampa/ISG lots until I sort out how to set fab name */
and (f.FAB_NAME is null or f.FAB_NAME not like 'UVA:%')
ORDER BY t.LOT
)
LOOP
BEGIN
--EVENT_TYPE|EVENT_TIME|SRC_FAB|SRC_LOT|FROM_SRC_LOT|FROM_FAB|FROM_PROD|FROM_LOT|FAB|PROD|LOT|EVENT_NAME
DBMS_OUTPUT.PUT_LINE('MOUT|'||TO_CHAR(c.TRANS_DT, 'YYYY-MM-DD HH24:MI:SS')||'|'||c.FROM_FAB_NAME||'|'||c.SOURCE_LOT||'.S|'||c.FROM_SOURCE_LOT||'.S|'||c.FAB_NAME||'|'||c.PARENT_PRODUCT||'|'||c.PARENT_LOT||'|'||c.FAB_NAME||'|'||c.PRODUCT||'|'||c.LOT||'|'||c.LOT||'_'||c.PARENT_LOT||'_'||c.FROM_SOURCE_LOT||'.S');
END;
END LOOP;
END
;
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
    /bin/gzip $archiveDir/$b_name
  fi
  #printf "TEST"
  /bin/mv $outFileTmp $outFile
fi
