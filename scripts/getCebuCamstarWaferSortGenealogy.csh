#!/bin/csh
#
# Extract Cebu Camstar wafer sort genealogy data.
#
# MODIFICATION HISTORY
#
# WHEN      WHO WHAT
# --------- --- ------------------------------------------
# 27-Mar-17 SAB Initial version.
# 28-Mar-18 SAB Correct product IDs that look like ON Semi products or contain a dash character.
# 07-Sep-2022 jgarcia references to PSoft table is removed.
# 07-Sep-2022 jgarcia added feature to not generate final query output if it has an SQL ERROR and send an email notification.
# 08-Sep-2022 jgarcia added the exclusion of Cebu modeled pre-assembly steps as wafer sort.
#
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
#set archiveDir = /apps/exensio_data/archives-yms/reference_data/mes_test
set archiveDir = /apps/exensio_data/archives-yms/reference_data/mes
set rootDir = $REFERENCE_DATA_DIR
set tmpDir  = $rootDir/tmp
set outFile    = $rootDir/CebuCamstarWaferSortGenealogy-${dateCode}.cmes
set outFileTmp = $tmpDir/CebuCamstarWaferSortGenealogy-${dateCode}.cmes.tmp
set logFile = $rootDir/log/$0:t.${dateCode}.log
set tmpScript = /tmp/$0:t.$$.sql

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

SELECT 'BUSINESS_UNIT|FACILITY|PARENT_LOT|CHILD_LOT|PARENT_PROD|CHILD_PROD|OWNER|TRANS|TRANSACTION_DATE_TIME|SOURCE_LOT|SOURCE_PROD|SOURCE_INV_ITEM_TYPE|PATH' from DUAL;
WITH WIPLTH_RECENT_LOTS AS
(
SELECT DISTINCT wl.BUSINESS_UNIT, s.OBJECTTYPE as AREA, p.PRODUCTNAME, wl.LOT_NUMBER, wl.OWNERNAME
, a.FABLOTNUMBER as PARENT_LOT, COALESCE(substr(a.LOT_NUMBER, 1, instr(a.LOT_NUMBER, '-')-1), a.LOT_NUMBER) as CHILD_LOT
-- See if PSoft has a better source lot than Camstar.  Sometimes the fab lot # in camstar is equal to the lot #.
-- Remove PSoft's table referencing
,coalesce(wls.SOURCE_LOT, a.FABLOTNUMBER) as SOURCE_LOT, coalesce(wls.SOURCE_PROD, p.PRODUCTNAME) as SOURCE_PROD
FROM BIWMES.CAMSTAR_WIPLTH wl
JOIN BIWMES.CAMSTAR_SPEC s ON wl.SPECKEY = s.SPECKEY and wl.BUSINESS_UNIT = s.BUSINESS_UNIT
JOIN BIWMES.CAMSTAR_PRODUCT p on wl.PRODUCTKEY = P.PRODUCTKEY and wl.BUSINESS_UNIT = p.BUSINESS_UNIT
JOIN BIWMES.CAMSTAR_LOTATTRIBUTES a ON wl.BUSINESS_UNIT = a.BUSINESS_UNIT and wl.LOT_NUMBER = a.LOT_NUMBER
-- Remove PSoft's table referencing
--LEFT JOIN BIWSTAGE.PS_SF_COMP_QTY c on c.BUSINESS_UNIT = 'YBMI1' and wl.LOT_NUMBER = c.PRODUCTION_ID
LEFT JOIN (SELECT wls.CHILD_LOT, wls.SOURCE_LOT, wls.SOURCE_PROD
           FROM BIWMES.WKSM_WIPLTH_SUM wls
           WHERE wls.TRANS IN ('CRLT', 'SPLT')
             AND wls.TRANSACTION_DATE_TIME = (SELECT MIN(TRANSACTION_DATE_TIME)
                                              FROM BIWMES.WKSM_WIPLTH_SUM wlsm
                                              WHERE wlsm.CHILD_LOT = wls.CHILD_LOT AND wlsm.TRANS = wls.TRANS)
          ) wls ON a.FABLOTNUMBER = wls.CHILD_LOT
WHERE wl.TXNDATE > (sysdate - INTERVAL '$ora_hours' HOUR)
  AND s.OBJECTTYPE in ('WAFERSORT')
  AND s.SPECNAME NOT LIKE '%VIS%INSP%'
  AND s.DESCRIPTION NOT LIKE '%Assem%'
  AND s.SPECNAME not like '%ASY'
)
, WIPLTH_FIRST_DATE AS (
SELECT wl.BUSINESS_UNIT, wr.AREA, wr.PRODUCTNAME, wl.LOT_NUMBER, wr.PARENT_LOT, wr.CHILD_LOT, min(wl.TXNDATE) as MIN_TXNDATE, wr.OWNERNAME, wr.SOURCE_LOT, wr.SOURCE_PROD
FROM BIWMES.CAMSTAR_WIPLTH wl
JOIN WIPLTH_RECENT_LOTS wr ON wr.BUSINESS_UNIT = wl.BUSINESS_UNIT and wr.LOT_NUMBER = wl.LOT_NUMBER
JOIN BIWMES.CAMSTAR_SPEC s ON wl.SPECKEY = s.SPECKEY AND wl.BUSINESS_UNIT = s.BUSINESS_UNIT and wr.AREA = s.OBJECTTYPE
group by wl.BUSINESS_UNIT, wr.AREA, wr.PRODUCTNAME, wl.LOT_NUMBER, wr.PARENT_LOT, wr.CHILD_LOT, wr.OWNERNAME, wr.SOURCE_LOT, wr.SOURCE_PROD
)
/*
SELECT wl.BUSINESS_UNIT, ' ' as FACILITY, wfd.PARENT_LOT, wfd.CHILD_LOT, ' ' as PARENT_PROD, wfd.PRODUCTNAME as CHILD_PROD, wfd.OWNERNAME as OWNER, wl.TXN as TRANS
     , wfd.MIN_TXNDATE AS TRANSACTION_DATE_TIME, wfd.SOURCE_LOT, wfd.SOURCE_PROD, ' ' as SOURCE_INV_ITEM_TYPE, ' ' as PATH
*/
SELECT wl.BUSINESS_UNIT
||'|'||' '
||'|'||COALESCE(wfd.PARENT_LOT, wfd.CHILD_LOT)
||'|'||wfd.CHILD_LOT
||'|'||' '
||'|'||REGEXP_REPLACE(case when (regexp_like(wfd.PRODUCTNAME, '^.+-.+-...\$')
                             or regexp_like(wfd.PRODUCTNAME, '^.+-(ASM|ASY|WDQ|FAB|DSG|EPC|ECH|DFF|SCB|UTP|BMP|WFA|WBP|WPR|BSM|FSM|SWF|FTP|TST|XTD|FTD|APT|UTD|EPT|EPU|XTP|WAF|DIE|XWF|THN|FMD|XMD|EPM|BAS|DWR|NRE|XDW|GLD|XDI|XDS|EPD|DST|EPA|EPW)\$'))
                           then substr(wfd.PRODUCTNAME, 1, instr(wfd.PRODUCTNAME, '-', -1)-1)
                           else wfd.PRODUCTNAME end, '-', '_')
||'|'||wfd.OWNERNAME
||'|'||wl.TXN
||'|'||TO_CHAR(wfd.MIN_TXNDATE, 'YYYY-MM-DD HH24:MI:SS')
||'|'||wfd.SOURCE_LOT
||'|'||REGEXP_REPLACE(case when (regexp_like(wfd.SOURCE_PROD, '^.+-.+-...\$')
                             or regexp_like(wfd.SOURCE_PROD, '^.+-(ASM|ASY|WDQ|FAB|DSG|EPC|ECH|DFF|SCB|UTP|BMP|WFA|WBP|WPR|BSM|FSM|SWF|FTP|TST|XTD|FTD|APT|UTD|EPT|EPU|XTP|WAF|DIE|XWF|THN|FMD|XMD|EPM|BAS|DWR|NRE|XDW|GLD|XDI|XDS|EPD|DST|EPA|EPW)\$'))
                           then substr(wfd.SOURCE_PROD, 1, instr(wfd.SOURCE_PROD, '-', -1)-1)
			   else wfd.SOURCE_PROD end, '-', '_')
||'|'||' '
||'|'||' '
FROM BIWMES.CAMSTAR_WIPLTH wl
JOIN WIPLTH_FIRST_DATE wfd on wl.BUSINESS_UNIT = wfd.BUSINESS_UNIT and wl.LOT_NUMBER = wfd.LOT_NUMBER and wl.TXNDATE = wfd.MIN_TXNDATE
;
quit;
eof

sqlplus -s ${ora_user}/${ora_pass}@${ora_sid} @${tmpScript} > $logFile

if ( -f ${tmpScript} ) then
   /bin/rm ${tmpScript}
endif

if ( -f $outFileTmp ) then
  # check first if the output file dont have SQL Error
  set errorLine = `grep -r 'ERROR' $outFileTmp`
  set errorCause = `grep -r 'ORA' $outFileTmp`
  set errorString = "$errorLine cause by $errorCause"
  if ( "$errorLine" == "" && "$errorCause" == "" ) then
    # copy to archive first
    if ( -d $archiveDir ) then
      /bin/cp -p $outFileTmp $archiveDir/$outFileTmp:t:r
      /bin/gzip $archiveDir/$outFileTmp:t:r
    endif
    /bin/mv $outFileTmp $outFile
  else
    #send email that the query has ERROR.
    echo "$errorString" | mail -s "getCebuCamstarWaferSortGenealogy.csh script query ERROR" yms.admins@onsemi.com
  endif
endif
