#!/bin/bash
#
# Extract product reference data from DW.
#
# MODIFICATION HISTORY
#
# WHEN      WHO WHAT
# --------- --- ------------------------------------------
# 16-Nov-17 JAG Initial. query provided by Scott.
# 24-Feb-18 SAB Performance Fix.  Changed query to get rows when MFG_PART_NUM uses legacy ON Style naming, converts format to ex-FSC.
# 18-Jun-18 JAG Adds _WAFER to Product if Agile product ends with -FAB.
# 06-Apr-20 JAG modified to use ONE.PC_ITEM instead of STG_PRODCENT.PART except on the query for X/Y, to make acceptable to DBA in terms of performance.
# converted from csh to bash script
# 08-Feb-21 JAG to use string alias to product like regex as script argument, to avoid issues in script not able to get correct #4 argument when cron calls the script.
# 25-Jan-22 SAB Products with missing legacy part description were excluded.  Changed query to allow missing values.
#               Added option for creating MTP products without _WAFER.

isError=0 
product_like=""

if [ -z "${REFERENCE_DATA_DIR}" ]
then
   export REFERENCE_DATA_DIR=""
   isError=1 
fi

if [ ! -d "$REFERENCE_DATA_DIR" ]
then
   isError=1 
fi

if [ $# -ne 4 ] && [ $# -ne 5 ]
then
   isError=1
fi

if [ $isError -eq 0 ] 
then
   if [ "$2" != "DW_PASSWORD" ] || [ "$2" == "" ] 
   then
      isError=1 
   fi
fi
addWaferSuffix=0
if [ $isError -eq 0 ] 
then
   if [ $# -eq 5 ]
   then
      if [ "$5" == "add-mtp-wafer-suffix" ] 
      then
         addWaferSuffix=1
      fi
   fi
fi

if [ $isError -ne 0 ] 
then
   echo "ARG1=$1||ARG2=$2||ARG3=$3||ARG4=$4"
   echo "USAGE: $(basename $0) db-user db-password db-sid product-like [add-mtp-wafer-suffix]"
   echo " " 
   echo "Environment variable REFERENCE_DATA_DIR must be set to a valid directory"
   #echo "if password is DW_PASSWORD, use value in environment variable YMS_PASSWORD"

   exit 1
fi

# When db-sid is DWPRD and Snowflake env is set, use Snowflake script (isql/ODBC) instead of Oracle (sqlplus).
if [ "$3" = "DWPRD" ] && [ -n "${SNOW_PASS}${SNOW_PASSWORD}${SNOWFLAKE_PASSWORD}" ]; then
   scriptDir="$(cd "$(dirname "$0")" && pwd)"
   exec "$scriptDir/n_getDWProductMetadata.sh"
fi

ora_user="$1"
if [ "$2" == "DW_PASSWORD" ] 
then
   ora_pass="exensio2read"
else
   ora_pass="$2"
fi

if [ "$3" == "DWPRD" ] 
then
#   ora_ip="10.100.22.74"
#   ora_sid="DWPRD"
   connectionString="DWPRD"
#   ora_ip="10.100.22.74"
#   ora_sid="DWPRD"
else 
   ora_sid="$3"
   connectionString="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${ora_ip})(PORT=${ora_port}))(CONNECT_DATA=(SID=${ora_sid})))"
fi

if [ "$4" == "productLike0to9" ]
then
  product_like='^[0-9].*'
elif [ "$4" == "productLikeAtoM" ]
then
  product_like='^[A-M].*'
elif [ "$4" == "productLikeNtoZ" ]
then
  product_like='^[N-Z].*'
else
  echo "Invalid value for product-like argument.."
  exit 1
fi

waferSuffixCaseStmt=""
if [ $addWaferSuffix -eq 1 ] 
then
   waferSuffixCaseStmt="||case when COALESCE(psp_fabsite.BOM_COMPNT_MFG_AREA_CD, psp_site.BOM_COMPNT_MFG_AREA_CD) = 'UWA' and PC_ITEM.MFG_PART_NUM NOT LIKE '%_WAFER' and pd.PART_ID like '%-FAB' then '_WAFER' else '' end"
fi

ora_port="1693"


dateCode=`date +"%Y%m%d_%H%M%S"`
# Do not add spaces around = (bash would treat rootDir/archiveDir as commands)
archiveDir=/apps/exensio_data/archives-yms/reference_data/product
rootDir=$REFERENCE_DATA_DIR
tmpDir=$rootDir/tmp
outFile=$rootDir/DWProductDimProductInfo-${dateCode}.prod
outFileTmp=$tmpDir/DWProductDim-${dateCode}.prod.tmp
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
select 'PRODUCT|ITEM_TYPE|FAB|FAB_DESC|AFM|PROCESS|FAMILY|PACKAGE|GDPW|WF_UNITS|WF_SIZE|DIE_UNITS|DIE_WIDTH|DIE_HEIGHT|LAST_CHANGED_DATE' from dual;
with bom_type as(
select /*+ MATERIALIZE */ * from (
select unique p.mfg_part_num, pd.PART_SUB_TYPE_CD
, rank() over (partition by p.mfg_part_num
               order by case when pd.part_sub_type_cd in ('POL', 'SXL', 'SPO', 'SEP') then 99 -- pre-EPI; don't want
                             when pd.part_sub_type_cd = 'EPI' then 99  -- don't want EPI type
                             when pd.part_sub_type_cd = 'BAS' then 1
                             when pd.part_sub_type_cd = 'FAB' then 2                             
                             when pd.part_sub_type_cd = 'CFA' then 3                             
                             when pd.part_sub_type_cd = 'THN' then 4
                             when pd.part_sub_type_cd = 'PF1' then 5
                             when pd.part_sub_type_cd = 'FSM' then 6
                             when pd.part_sub_type_cd = 'BSM' then 7
                             when pd.part_sub_type_cd = 'SW1' then 8
                             when pd.part_sub_type_cd = 'FSP' then 9
                             when pd.part_sub_type_cd in ( 'SWF', 'BSP') then 10
                             when pd.part_sub_type_cd = 'DWR' then 11
                             when pd.part_sub_type_cd in ( 'WCP', 'WSG') then 12
                             when pd.part_sub_type_cd = 'BMP' then 13
                             when pd.part_sub_type_cd = 'WDQ' then 14
                             when pd.part_sub_type_cd = 'DSG' then 15
                             when pd.part_sub_type_cd = 'MSA' then 16
                             when pd.part_sub_type_cd = 'SAW' then 17                             
                             when pd.part_sub_type_cd = 'ASM' then 18
                             when pd.part_sub_type_cd = 'ASY' then 19
                             when pd.part_sub_type_cd = 'TSM' then 20                             
                             when pd.part_sub_type_cd = 'MFA' then 21
                             when pd.part_sub_type_cd = 'TST' then 22
                             when pd.part_sub_type_cd = 'OPN' then 23
                             when pd.part_sub_type_cd = 'MSC' then 24
                            else 99 end) as MY_RANK
from --BIWHUB.SUPPLY_PATH_WHERE_USED wu
--join 
BIWMARTS.PART_DIM pd --on wu.part_id = pd.part_id
join ONE.PC_ITEM p on pd.part_id = p.part_no
where p.mfg_part_num is not null
AND REGEXP_LIKE(p.MFG_PART_NUM, '$product_like')
) where my_rank = 1)
, get_fab as
(
SELECT * FROM 
(
select wu.end_part_id,
        WU.BOM_COMPNT_PART_ID,
        WU.BOM_COMPNT_SUB_TYPE_CD,
        COMPNT_PD.ERP_RESOURCE_FAB_CD as BOM_COMPNT_ERP_RESOURCE_FAB_CD,
        COMPNT_PD.PART_TYPE_DESC as BOM_COMPNT_TYPE_DESC,
        WU.BOM_COMPNT_MFG_AREA_CD,
        WU.BOM_COMPNT_FE_BE_FLG,
        compnt_sd.MFG_AREA_DESC as BOM_COMPNT_MFG_AREA_DESC,
        rank() over (partition by wu.end_part_id
            order by
            --  We first prefer a FAB or FAB-like part.
                case 
                     when WU.BOM_COMPNT_SUB_TYPE_CD = 'FAB' then 1
                     when WU.BOM_COMPNT_SUB_TYPE_CD = 'WAF' then 2
                     when WU.BOM_COMPNT_SUB_TYPE_CD = 'SWF' then 3
                     when COMPNT_PD.PART_TYPE_DESC = 'Wafer Fab Part' then 4
                     when WU.BOM_COMPNT_SUB_TYPE_CD = 'BAS' then 5
                     else 99 end,
            --  We next prefer the most upstream component, then break ties
            -- by BOM_COMPNT_PART_ID.
                WU.COMPNT_LEVEL desc,
                WU.BOM_COMPNT_PART_ID)
            as compnt_rank
    from BIWHUB.SUPPLY_PATH_WHERE_USED wu
    inner join biwmarts.part_dim end_pd
        on end_pd.part_id = WU.END_PART_ID
    inner join biwmarts.part_dim compnt_pd
        on compnt_pd.part_id = WU.BOM_COMPNT_PART_ID
    inner join biwmarts.site_dim compnt_sd
        on compnt_sd.MFG_AREA_CD = WU.BOM_COMPNT_MFG_AREA_CD
        and compnt_sd.FE_BE_FLG  = WU.BOM_COMPNT_FE_BE_FLG
    where wu.mfg_area_cd != 'ZZNOSITE'
    --where END_PD.PART_TYPE_DESC = 'Wafer Post Fab Part'
) WHERE compnt_rank = 1
)
, get_fab2 as
(
SELECT * FROM 
(
select wu.end_part_id,
        WU.BOM_COMPNT_PART_ID,
        WU.BOM_COMPNT_SUB_TYPE_CD,
        COMPNT_PD.ERP_RESOURCE_FAB_CD as BOM_COMPNT_ERP_RESOURCE_FAB_CD,
        COMPNT_PD.PART_TYPE_DESC as BOM_COMPNT_TYPE_DESC,
        WU.BOM_COMPNT_MFG_AREA_CD,
        WU.BOM_COMPNT_FE_BE_FLG,
        compnt_sd.MFG_AREA_DESC as BOM_COMPNT_MFG_AREA_DESC,
        rank() over (partition by wu.end_part_id
            order by
            --  We first prefer a FAB or FAB-like part.
                case 
                     when WU.BOM_COMPNT_SUB_TYPE_CD = 'FAB' then 1
                     when WU.BOM_COMPNT_SUB_TYPE_CD = 'WAF' then 2
                     when WU.BOM_COMPNT_SUB_TYPE_CD = 'SWF' then 3
                     when COMPNT_PD.PART_TYPE_DESC = 'Wafer Fab Part' then 4
                     when WU.BOM_COMPNT_SUB_TYPE_CD = 'BAS' then 5
                     else 99 end,
            --  We next prefer the most upstream component, then break ties
            -- by BOM_COMPNT_PART_ID.
                WU.COMPNT_LEVEL desc,
                WU.BOM_COMPNT_PART_ID)
            as compnt_rank
    from BIWHUB.SUPPLY_PATH_WHERE_USED wu
    inner join biwmarts.part_dim end_pd
        on end_pd.part_id = WU.END_PART_ID
    inner join biwmarts.part_dim compnt_pd
        on compnt_pd.part_id = WU.BOM_COMPNT_PART_ID
    inner join biwmarts.site_dim compnt_sd
        on compnt_sd.MFG_AREA_CD = WU.BOM_COMPNT_MFG_AREA_CD
        and compnt_sd.FE_BE_FLG  = WU.BOM_COMPNT_FE_BE_FLG
    where wu.mfg_area_cd != 'ZZNOSITE'
    --where END_PD.PART_TYPE_DESC = 'Wafer Post Fab Part'
) WHERE compnt_rank = 1
)
, get_fam as (
SELECT UNIQUE p.MFG_PART_NUM, p.LEGACY_PART_DESCRIPTION
FROM ONE.PC_ITEM p 
WHERE p.MFG_PART_NUM is NOT NULL 
/*  and p.LEGACY_PART_DESCRIPTION IS NOT NULL*/
  AND REGEXP_LIKE(p.MFG_PART_NUM, '$product_like')
)
, get_pkg_cfg as
(
SELECT * FROM 
(
SELECT p.MFG_PART_NUM
     , CASE WHEN REGEXP_LIKE(p.PACKING_CONFIG_ID, '^.+-.+_.+_.+_.+\$') THEN SUBSTR(p.PACKING_CONFIG_ID, 1, INSTR(p.PACKING_CONFIG_ID, '_', 1, 2)-1) 
       ELSE NULL END AS PKG
     , CASE WHEN PD.CORE_PART_NO_CONFIG_ID in ( 'UNK', 'Dummy-COR') then NULL 
                WHEN PD.CORE_PART_NO_CONFIG_ID like '%-COR' THEN SUBSTR(PD.CORE_PART_NO_CONFIG_ID, 1, INSTR(PD.CORE_PART_NO_CONFIG_ID, '-')-1)
                ELSE PD.CORE_PART_NO_CONFIG_ID
            END AS FG_DEVICE
     , rank() 
       OVER (PARTITION BY p.MFG_PART_NUM 
             ORDER BY CASE WHEN REGEXP_LIKE(p.PACKING_CONFIG_ID, '^.+-.+_.+_.+_.+\$') THEN SUBSTR(p.PACKING_CONFIG_ID, 1, INSTR(p.PACKING_CONFIG_ID, '_', 1, 2)-1) ELSE NULL END NULLS LAST
                    , CASE WHEN PD.CORE_PART_NO_CONFIG_ID in ( 'UNK', 'Dummy-COR') then NULL 
                           WHEN PD.CORE_PART_NO_CONFIG_ID like '%-COR' THEN SUBSTR(PD.CORE_PART_NO_CONFIG_ID, 1, INSTR(PD.CORE_PART_NO_CONFIG_ID, '-')-1)
                           ELSE PD.CORE_PART_NO_CONFIG_ID
                           END NULLS LAST
             ) 
       as PKG_RANK
FROM ONE.PC_ITEM p
JOIN BIWMARTS.PART_DIM pd on pd.PART_ID = p.PART_NO
WHERE REGEXP_LIKE(p.MFG_PART_NUM, '$product_like')
) WHERE PKG_RANK = 1
)
, get_prod as (
select UNIQUE PD.PART_ID
     , REGEXP_REPLACE(case when (regexp_like(PC_ITEM.MFG_PART_NUM, '^.+-.+-...\$') 
                             or regexp_like(PC_ITEM.MFG_PART_NUM, '^.+-(ASM|ASY|WDQ|FAB|DSG|EPC|ECH|DFF|SCB|UTP|BMP|WFA|WBP|WPR|BSM|FSM|SWF|FTP|TST|XTD|FTD|APT|UTD|EPT|EPU|XTP|WAF|DIE|XWF|THN|FMD|XMD|EPM|BAS|DWR|NRE|XDW|GLD|XDI|XDS|EPD|DST|EPA|EPW)\$')) 
                           then substr(PC_ITEM.MFG_PART_NUM, 1, instr(PC_ITEM.MFG_PART_NUM, '-', -1)-1)
                      else PC_ITEM.MFG_PART_NUM end, '-', '_')$waferSuffixCaseStmt as PRODUCT 
     , COALESCE(case when bt.PART_SUB_TYPE_CD in ('ASM', 'MSA', 'MFM', 'TSM', 'OPN', 'ASY') THEN pk.FG_DEVICE ELSE NULL END, 
                CASE WHEN REGEXP_LIKE(PC_ITEM.MFG_PART_NUM, '^.+_.+\$') THEN SUBSTR(PC_ITEM.MFG_PART_NUM, 1, INSTR(PC_ITEM.MFG_PART_NUM, '_')-1) 
                     WHEN REGEXP_LIKE(PC_ITEM.MFG_PART_NUM, '^.+-.+\$') THEN SUBSTR(PC_ITEM.MFG_PART_NUM, 1, INSTR(PC_ITEM.MFG_PART_NUM, '-')-1) 
                     ELSE PC_ITEM.MFG_PART_NUM END) AS DEVICE
     , gf.LEGACY_PART_DESCRIPTION as PROCESS_FAMILY
     , CASE WHEN bt.PART_SUB_TYPE_CD in ('ASM', 'MSA', 'MFM', 'TSM', 'OPN', 'ASY') then 'FG' 
            WHEN bt.PART_SUB_TYPE_CD in ('SWF','WDQ','BMP','SW1', 'DSG') then 'DIE'
            WHEN bt.PART_SUB_TYPE_CD in ('THN', 'BSM') THEN 'WAFER'
            WHEN bt.PART_SUB_TYPE_CD in ('FAB', 'BSP') then 'WAFER'
            WHEN bt.PART_SUB_TYPE_CD in ('BAS') then 'MSLC'
            WHEN bt.PART_SUB_TYPE_CD in ('EPI', 'SEP', 'SPO') then 'EPI'
            ELSE bt.PART_SUB_TYPE_CD END as PART_TYPE
     , psp_site.BOM_COMPNT_mfg_area_cd
     , psp_site.BOM_COMPNT_fe_be_flg
     , COALESCE(psp_fabsite.BOM_COMPNT_MFG_AREA_CD, psp_site.BOM_COMPNT_MFG_AREA_CD) AS FAB_CD
     , COALESCE(psp_fabsite.BOM_COMPNT_MFG_AREA_DESC, psp_site.BOM_COMPNT_MFG_AREA_DESC)  AS FAB_NAME
     , pk.PKG
     , PD.PDPW_VAL
     , PD.WAFER_SIZE_VAL
     , pd.LAST_CHG_DT AS LAST_CHANGED_DATE
--Die size (with scribe) is currently available on the WDQ part.
--Die Size X With Scribe/Street (um)
--Die Size Y With Scribe/Street (um)
     , COALESCE(CAST (ds.DIE_SIZE_X_WI_SCRIBE_STR AS FLOAT), 0.0) AS DIE_SIZE_X_WI_SCRIBE_STR
     , COALESCE(CAST (ds.DIE_SIZE_Y_WI_SCRIBE_STR AS FLOAT), 0.0) AS DIE_SIZE_Y_WI_SCRIBE_STR
from BIWMARTS.PART_DIM pd
LEFT OUTER JOIN ONE.PC_ITEM ON PD.PART_ID = PC_ITEM.PART_NO
LEFT OUTER JOIN bom_type bt on PC_ITEM.MFG_PART_NUM = bt.MFG_PART_NUM
LEFT OUTER JOIN
   (SELECT wux.BOM_COMPNT_PART_ID
         , p.DIE_SIZE_X_WI_SCRIBE_STR
         , p.DIE_SIZE_Y_WI_SCRIBE_STR
    FROM BIWHUB.SUPPLY_PATH_WHERE_USED wux 
    JOIN STG_PRODCENT.PART p on wux.END_PART_ID = p.PART_NO 
    --JOIN STG_PRODCENT.PART on wux.PART_ID = p.PART_NO 
    WHERE p.part_sub_type = 'WDQ'
   ) ds on ds.BOM_COMPNT_PART_ID = pd.PART_ID
LEFT OUTER JOIN get_fab psp_site ON psp_site.end_part_id = pd.part_id
LEFT OUTER JOIN get_fab2 psp_fabsite ON psp_fabsite.BOM_COMPNT_PART_ID = pd.part_id  
LEFT OUTER JOIN get_fam gf ON PC_ITEM.MFG_PART_NUM = gf.MFG_PART_NUM
LEFT OUTER JOIN get_pkg_cfg pk ON PC_ITEM.MFG_PART_NUM = pk.MFG_PART_NUM
WHERE PD.PART_SUB_TYPE_CD != 'NRE' 
  AND REGEXP_LIKE(PC_ITEM.MFG_PART_NUM, '$product_like')
  --AND PC_ITEM.MFG_PART_NUM not like '%-%' 
  ----AND pd.LAST_CHG_DT > sysdate - 365*(interval '1' day)  -- Remove this line to run for all time
  AND NOT REGEXP_LIKE (PC_ITEM.MFG_PART_NUM, '^\d+\$') 
  AND NOT REGEXP_LIKE (PC_ITEM.MFG_PART_NUM, '^\d+[A-Z]\$')
  and PD.LIFECYCLE_PHASE_DESC != 'Obsolete'
  and PD.PART_SUB_TYPE_CD != 'UNK'
-- PRODUCT must exist in the BOM.
  AND EXISTS (SELECT 1 FROM BIWHUB.SUPPLY_PATH_WHERE_USED wuex WHERE wuex.PART_ID = pd.PART_ID and wuex.BOM_COMPNT_PART_ID not like 'BOB-%')
) 
, res as (
select UNIQUE PRODUCT
     , PART_TYPE AS ITEM_TYPE
     , max(CASE WHEN PDPW_VAL IS NULL OR PDPW_VAL = 0 THEN NULL ELSE FAB_CD END) AS FAB
     , max(CASE WHEN PDPW_VAL IS NULL OR PDPW_VAL = 0 THEN NULL ELSE FAB_NAME END) AS FAB_DESC
     , ' ' AS AFM
     , max(PROCESS_FAMILY) as PROCESS
     , DEVICE AS FAMILY
     , PKG AS "PACKAGE"
     , max(PDPW_VAL) as PDPW
     , 'MM' AS WF_UNITS
     , max(WAFER_SIZE_VAL) AS WF_SIZE
     , 'MC' AS DIE_UNITS
     , max(DIE_SIZE_X_WI_SCRIBE_STR) AS DIE_WIDTH
     , max(DIE_SIZE_Y_WI_SCRIBE_STR) AS DIE_HEIGHT
     , LAST_CHANGED_DATE
     , rank() OVER (PARTITION BY PRODUCT ORDER BY CASE WHEN PART_TYPE = 'WAFER' then 1 WHEN PART_TYPE = 'DIE' THEN 2 ELSE 3 END) as PART_RANK
FROM get_prod 
WHERE PART_TYPE = 'FG' OR (FAB_CD IS NOT NULL AND FAB_CD != ' ' AND PDPW_VAL > 0)
GROUP BY PRODUCT, DEVICE, PART_TYPE, PKG, LAST_CHANGED_DATE
)
select PRODUCT
||'|'||ITEM_TYPE
||'|'||FAB
||'|'||SUBSTR(FAB_DESC, 1, 50)
||'|'||SUBSTR(AFM, 1, 45)
||'|'||SUBSTR(PROCESS, 1, 32)
||'|'||SUBSTR(FAMILY, 1, 32)
||'|'||SUBSTR(PACKAGE, 1, 32)
||'|'||PDPW
||'|'||WF_UNITS
||'|'||WF_SIZE
||'|'||DIE_UNITS
||'|'||DIE_WIDTH
||'|'||DIE_HEIGHT
||'|'||LAST_CHANGED_DATE 
FROM res 
WHERE PART_RANK = 1 
ORDER BY PRODUCT;
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

