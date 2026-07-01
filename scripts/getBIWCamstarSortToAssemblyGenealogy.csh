#!/bin/csh 
#
# Extract BIW Camstar Sort to Assembly Genealogy extract.
#
# MODIFICATION HISTORY
#
# WHEN      : WHO : WHAT
# --------- : --- : ------------------------------------------
# 20-Ocr-17 : JAG : initial.
# 20-Oct-17 : JAG : replace the sql query given by Scott to generate BIW Camstar Sort to Assembly Genealogy extract.
# 23-Oct-18 : SAB : # of hours back input was being ignored.  Time period was hard-coded to 2 hours back.
# 20-Sep-23 : JAG : with USE_HASH hint. pprod_lookup section
set isError = 0

if (! $?REFERENCE_DATA_DIR) then
   setenv REFERENCE_DATA_DIR ""
   set isError = 1 
endif

if ( ! -d $REFERENCE_DATA_DIR ) then
   set isError = 1 
endif

if ($#argv != 4 ) then
   set isError = 1
endif

if ( ! $isError ) then
   if ( "$2" == "YMS_PASSWORD" && ! $?YMS_PASSWORD ) then
      set isError = 1 
   endif
endif

if ( $isError ) then
   echo "USAGE: $0:t oracle-user oracle-password oracle-sid number-of-hours-back"
   echo " " 
   echo "Environment variable REFERENCE_DATA_DIR must be set to a valid directory"
   echo "if password is YMS_PASSWORD, use value in environment variable YMS_PASSWORD"

   exit(1)
endif

set ora_user = "$1"
if ( "$2" == "YMS_PASSWORD" ) then
   set ora_pass = "$YMS_PASSWORD"
else
   set ora_pass = "$2"
endif

set ora_sid  = "$3"
set ora_hours  = "$4"

set dateCode = `date +"%Y%m%d_%H%M%S"`
#set rootDir = /home/dpower/project/work/sboothby/dbextract_scripts
#set rootDir = /home/dpower/project/work/jgarcia/dbextract_scripts
set archiveDir = /apps/exensio_data/archives-yms/reference_data/mes
set rootDir = $REFERENCE_DATA_DIR
set tmpDir  = $rootDir/tmp
set outFile    = $rootDir/BIWCamstarSortToAssemblyGenealogy-${dateCode}.cast
set outFileTmp = $tmpDir/BIWCamstarSortToAssemblyGenealogy-${dateCode}.cast.tmp
set logFile = $rootDir/log/$0:t.${dateCode}.log
set tmpScript = $rootDir/tmp/$0:t.$$.sql

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
SELECT 'BUSINESS_UNIT|FACILITY|PARENT_LOT|CHILD_LOT|DATE_CODE|PARENT_PROD|CHILD_PROD|OWNER|PARENT_OWNER|TRANS|TRANSACTION_DATE_TIME|SOURCE_LOT|SOURCE_PROD|SOURCE_INV_ITEM_TYPE|PATH' from DUAL;
-- assembly starts genealogy.
WITH active_lots as (
SELECT BUSINESS_UNIT, LOT_NUMBER, max(OWNERNAME) as OWNERNAME, max(TXN) as TRANS
FROM BIWMES.CAMSTAR_WIPLTH lh
-- Get data less than 2 hours old
WHERE lh.TXNDATE > sysdate - ${ora_hours}*interval '1' hour
  AND lh.TXNDATE = (SELECT max(x.TXNDATE) from BIWMES.CAMSTAR_WIPLTH x
                   WHERE x.BUSINESS_UNIT = lh.BUSINESS_UNIT and x.LOT_NUMBER = lh.LOT_NUMBER
                     and x.TXNDATE > sysdate - ${ora_hours}*interval '1' hour)
GROUP BY BUSINESS_UNIT, LOT_NUMBER
)                   
, gen as (
SELECT UNIQUE C.BUSINESS_UNIT 
              , ' ' as FACILITY
              , c.SOURCELOTID as PARENT_LOT
              , c.LOT_NUMBER AS CHILD_LOT
              , aa.FSC7DIGITDATECODE AS DATE_CODE
              , REGEXP_REPLACE(COALESCE(spd.PRODUCTNAME, swp.INV_ITEM_ID, swl.PROD),'-', '_') as PARENT_PROD
              , COALESCE(spd.OWNERNAME, swl.OWNER, al.ownername) as PARENT_OWNER
              , C.PRODUCTNAME AS CHILD_PROD
              , al.OWNERNAME as OWNER
              , al.TRANS
              , C.TXNDATE as TRANSACTION_DATE_TIME
              , A.FABLOTNUMBER as SOURCE_LOT
              , REGEXP_REPLACE(COALESCE(spd.PRODUCTNAME, swp.INV_ITEM_ID, swl.PROD),'-', '_') as SOURCE_PROD
              , ' ' as SOURCE_INV_ITEM_TYPE
              , ' ' as PATH
FROM BIWMES.CAMSTAR_LOTCOMP c 
JOIN active_lots al on c.LOT_NUMBER = al.LOT_NUMBER and c.BUSINESS_UNIT = al.BUSINESS_UNIT
-- to get fab/sort lot number
LEFT JOIN BIWMES.CAMSTAR_LOTATTRIBUTES aa on C.BUSINESS_UNIT = aa.BUSINESS_UNIT and C.LOT_NUMBER = aa.LOT_NUMBER
-- to get source lot
LEFT JOIN BIWMES.CAMSTAR_LOTATTRIBUTES a on C.BUSINESS_UNIT = A.BUSINESS_UNIT and C.SOURCELOTID = A.LOT_NUMBER
-- to restrict query to non-split transactions
LEFT JOIN BIWMES.CAMSTAR_WIPLTH spd on c.BUSINESS_UNIT = spd.BUSINESS_UNIT AND c.SOURCELOTID = spd.LOT_NUMBER
-- See if the fab/sort lot was transacted in WKS to get product ID if available
LEFT JOIN BIWMES.WKSM_WIPLOT swl on c.SOURCELOTID = swl.LOT_NUMBER
LEFT JOIN ( SELECT UNIQUE x.BUSINESS_UNIT, x.PROD, x.INV_ITEM_ID FROM BIWMES.WKSM_PRODUCT x ) swp 
            on swl.BUSINESS_UNIT = swp.BUSINESS_UNIT and swl.PROD = swp.PROD
-- NOT EXISTS is to exclude source material from a combine lot transaction.
WHERE al.TRANS != 'TerminateLot'
-- There's a mismatch between WIPLTH and COMPLOT syncs in BIW so restrict to no more than 10 hours forward (note: Asia-Pac time is +12 or +13 ET)
  AND C.TXNDATE < sysdate + 10*interval '1' hour
  AND NOT EXISTS (SELECT 1 FROM biwmes.camstar_wiplth lh WHERE c.business_unit = lh.business_unit AND c.lot_number = lh.lot_number AND c.txndate = lh.txndate and lh.txn = 'CombineLot')
-- Exclude splits
  AND (spd.TXNDATE IS NULL OR 
       spd.TXNDATE = (SELECT MAX(TXNDATE) FROM BIWMES.CAMSTAR_WIPLTH x
                     WHERE spd.BUSINESS_UNIT = x.BUSINESS_UNIT AND spd.LOT_NUMBER = x.LOT_NUMBER
                     AND x.TXN NOT IN ('SplitLot')))
  AND (swl.DATE_ENTERED_FAC IS NULL OR
       swl.DATE_ENTERED_FAC = (SELECT MAX(DATE_ENTERED_FAC) FROM BIWMES.WKSM_WIPLOT y
                               WHERE swl.LOT_NUMBER = y.LOT_NUMBER))
)
, pprod_lookup as (
SELECT /*+ USE_HASH(l) */ UNIQUE l.BUSINESS_UNIT, REGEXP_SUBSTR(l.lot_number, '^(.+)(-\d\d)\$', 1, 1, '', 1) AS LOT, l.PRODUCTNAME
FROM BIWMES.CAMSTAR_WIPLTH l 
WHERE EXISTS(select * from gen g where g.BUSINESS_UNIT = l.business_unit and g.parent_lot = substr(l.lot_number, 1, length(l.lot_number)-3))
)
SELECT g.BUSINESS_UNIT 
||'|'||' ' 
||'|'||g.PARENT_LOT 
||'|'||g.CHILD_LOT 
||'|'||g.DATE_CODE 
||'|'||COALESCE(g.PARENT_PROD, pl.PRODUCTNAME, ' ') 
||'|'||g.CHILD_PROD 
||'|'||g.OWNER
||'|'||g.PARENT_OWNER 
||'|'||g.TRANS 
||'|'||TO_CHAR(g.TRANSACTION_DATE_TIME, 'YYYY-MM-DD HH24:MI:SS') 
||'|'||COALESCE(g.SOURCE_LOT, g.PARENT_LOT, ' ') 
||'|'||COALESCE(g.SOURCE_PROD, g.PARENT_PROD, pl.PRODUCTNAME, ' ') 
||'|'||' ' 
||'|'||' ' 
FROM gen g LEFT JOIN pprod_lookup pl on g.PARENT_LOT = pl.LOT and pl.BUSINESS_UNIT = g.BUSINESS_UNIT 
ORDER BY g.BUSINESS_UNIT, g.CHILD_LOT, g.TRANSACTION_DATE_TIME
;
quit;
eof

sqlplus -s ${ora_user}/${ora_pass}@${ora_sid} @${tmpScript} > $logFile

if ( -f ${tmpScript} ) then
  /bin/rm ${tmpScript}
endif

if ( -f $outFileTmp ) then
  # copy to archive first
  if ( -d $archiveDir ) then
    /bin/cp -p $outFileTmp $archiveDir/$outFileTmp:t:r
    /bin/gzip $archiveDir/$outFileTmp:t:r
  endif
  /bin/mv $outFileTmp $outFile
endif
