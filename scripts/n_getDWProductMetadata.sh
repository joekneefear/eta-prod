#!/usr/bin/env bash
#
# Extract product reference data from DW (Snowflake).
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
# 15-Jul-25 NT transform the script to work with Snowflake query provided by Scott
# 11-Feb-26 jgarcia - Updated script to support env-based Snowflake credentials (user, password, DSN), configurable warehouse and optional schema initialization, with positional args overriding env defaults.
# 11-Feb-26 jgarcia - apply: set -euo pipefail, quoted vars, mkdir -p for tmp/log, isql exit code check, trap cleanup, remove dead comments.
# 11-Feb-26 jgarcia - Snowflake only: removed Oracle path; only --test option; Snowflake credentials from env only.
# 11-Feb-26 jgarcia - Benchmark JSONL logging (PipelineInfo fields); production and --test paths.
# 11-Feb-26 jgarcia - Benchmark logging on/off via --no-benchmark; default is on.

set -euo pipefail

# Test refdata paths: used only when --test option is provided.
TEST_REFDATA_PATH=/export/home/dpower/jag/test_refdata/DWProductMetadata
TEST_REFDATA_ARCHIVE_PATH=/export/home/dpower/jag/test_refdata/DWProductMetadataArchive
PRODUCTION_ARCHIVE_DIR=/apps/exensio_data/archives-yms/reference_data/product
BENCHMARK_LOG_PRODUCTION=/apps/exensio_data/reference_data/benchmark/benchmark.jsonl
BENCHMARK_LOG_TEST=/export/home/dpower/jag/test_refdata/benchmark/benchmark.jsonl

# Parse options; production is the default. Benchmark logging is on by default.
use_test_paths=0
benchmark_enabled=1
pipeline_name="DWProductMetadata"
pipeline_type="batch"
while [ $# -gt 0 ]; do
  case "$1" in
    --test|-t)           use_test_paths=1; shift ;;
    --no-benchmark)      benchmark_enabled=0; shift ;;
    --pipeline_name=*)   pipeline_name="${1#--pipeline_name=}"; shift ;;
    --pipeline_name)     [ $# -gt 1 ] && { pipeline_name="$2"; shift 2; } || { echo "Missing value for --pipeline_name" >&2; exit 1; } ;;
    --pipeline_type=*)   pipeline_type="${1#--pipeline_type=}"; shift ;;
    --pipeline_type)     [ $# -gt 1 ] && { pipeline_type="$2"; shift 2; } || { echo "Missing value for --pipeline_type" >&2; exit 1; } ;;
    *) break ;;
  esac
done

# No positional args; only options above are supported. Snowflake credentials from env.
if [ $# -ne 0 ]; then
  echo "USAGE: $(basename "$0") [--test] [--no-benchmark] [--pipeline_name NAME] [--pipeline_type TYPE]" >&2
  echo "  --test            Use test paths for output and archive." >&2
  echo "  --no-benchmark    Disable benchmark JSONL logging (default: on)." >&2
  echo "  --pipeline_name   Pipeline name for benchmark log (default: DWProductMetadata)." >&2
  echo "  --pipeline_type    Pipeline type for benchmark log (default: batch)." >&2
  echo "  Otherwise:        REFERENCE_DATA_DIR required; Snowflake credentials from env (SNOW_USER, SNOW_PASS, SNOW_SID, etc.)." >&2
  exit 1
fi

# Paths: --test uses test paths; else REFERENCE_DATA_DIR required. Benchmark log path when enabled.
if [ "$use_test_paths" -eq 1 ]; then
  rootDir="$TEST_REFDATA_PATH"
  archiveDir="${DW_PRODUCT_METADATA_ARCHIVE_DIR:-$TEST_REFDATA_ARCHIVE_PATH}"
  [ "$benchmark_enabled" -eq 1 ] && benchmark_log="$BENCHMARK_LOG_TEST" || benchmark_log=""
  benchmark_env="test"
else
  if [ -z "${REFERENCE_DATA_DIR:-}" ]; then
    echo "REFERENCE_DATA_DIR must be set (or use --test for test paths)." >&2
    exit 1
  fi
  if [ ! -d "$REFERENCE_DATA_DIR" ]; then
    echo "REFERENCE_DATA_DIR is not a valid directory: $REFERENCE_DATA_DIR" >&2
    exit 1
  fi
  rootDir="$REFERENCE_DATA_DIR"
  archiveDir="${DW_PRODUCT_METADATA_ARCHIVE_DIR:-$PRODUCTION_ARCHIVE_DIR}"
  [ "$benchmark_enabled" -eq 1 ] && benchmark_log="$BENCHMARK_LOG_PRODUCTION" || benchmark_log=""
  benchmark_env="${ENVIRONMENT:-${ENV:-prod}}"
fi

if [ ! -d "$rootDir" ]; then
  echo "Output directory does not exist: $rootDir" >&2
  exit 1
fi

# Snowflake credentials: from env only (same style as n_getCamstarWafer2AssemblyGenealogy.pl).
snow_user="${SNOW_USER:-${SNOWFLAKE_USER:-MFG_PRD_RPT_EXENSIO_USER}}"
snow_pass="${SNOW_PASSWORD:-${SNOW_PASS:-${SNOWFLAKE_PASSWORD:-}}}"
snow_sid="${SNOW_SID:-${SNOWFLAKE_DSN:-MART_SNOWFLAKE}}"

source_warehouse="${SOURCE_WAREHOUSE:-application_prd_wh}"
source_schema="${SOURCE_SCHEMA:-}"

dateCode=$(date +"%Y%m%d_%H%M%S")
tmpDir="$rootDir/tmp"
outFile="$rootDir/DWProductDimProductInfo-${dateCode}.prod"
outFileTmp="$tmpDir/DWProductDim-${dateCode}.prod.tmp"
logFile="$rootDir/log/$(basename "$0").${dateCode}.log"
tmpScript="${TMPDIR:-/tmp}/$(basename "$0").$$.sql"

# Benchmark: capture start time (PipelineInfo fields)
start_epoch=$(date +%s)
start_local=$(date +"%Y-%m-%d %H:%M:%S")
start_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$tmpDir" "$(dirname "$logFile")"
trap 'rm -f "$tmpScript"' EXIT

# Build session setup: warehouse (required), optional database/schema
session_setup="use warehouse ${source_warehouse};
use role APPLICATIONPRD_MFG_CONSUMER_RO;
use secondary roles all;"
if [ -n "$source_schema" ]; then
  session_setup="${session_setup}
use database ${source_schema};"
fi

cat << eof  > "${tmpScript}"
${session_setup}
with bom_type as(
select  * from (
select distinct pd.MFG_PART_ID, pd.PART_SUB_TYPE_CD
, rank() over (partition by pd.MFG_PART_ID
               order by case when pd.part_sub_type_cd in ('POL', 'SXL', 'SPO', 'SEP') then 99
                             when pd.part_sub_type_cd in ('EPI', 'FBE') then 99
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
from ANALYTICSPRD.ENTERPRISE.PART_DIM pd
) where my_rank = 1)
, get_fab as
(
SELECT * FROM
(
select wu.end_part_id,
        wu.BOM_COMPONENT_PART_ID,
        wu.BOM_COMPONENT_SUB_TYPE_CODE,
        COMPONENT_PD.ERP_RESOURCE_FAB_CODE as BOM_COMPONENT_ERP_RESOURCE_FAB_CODE,
        COMPONENT_PD.PART_TYPE_DESCRIPTION as BOM_COMPONENT_TYPE_DESC,
        WU.BOM_COMPONENT_MFG_AREA_CODE ,
        WU.BOM_COMPONENT_FRONTEND_BACKEND_FLAG,
        COMPONENT_sd.MFG_AREA_DESCRIPTION as BOM_COMPONENT_MFG_AREA_DESCRIPTION,
        rank() over (partition by wu.end_part_id
            order by
                case
                     when WU.BOM_COMPONENT_SUB_TYPE_CODE = 'FAB' then 1
                     when WU.BOM_COMPONENT_SUB_TYPE_CODE = 'WAF' then 2
                     when WU.BOM_COMPONENT_SUB_TYPE_CODE = 'SWF' then 3
                     when COMPONENT_PD.PART_TYPE_DESCRIPTION = 'Wafer Fab Part' then 4
                     when WU.BOM_COMPONENT_SUB_TYPE_CODE = 'BAS' then 5
                     when WU.BOM_COMPONENT_SUB_TYPE_CODE = 'EPI' then 6
                     else 99 end,
                WU.COMPONENT_LEVEL desc,
                WU.BOM_COMPONENT_PART_ID
                )
            as COMPONENT_rank
    from applicationprd.mfg.get_supply_path_end_part_component_site wu
    inner join ANALYTICSPRD.ENTERPRISE.PART_DIM end_pd 
        on end_pd.part_id = WU.END_PART_ID
    inner join ANALYTICSPRD.ENTERPRISE.PART_DIM COMPONENT_pd 
        on COMPONENT_pd.part_id = WU.BOM_COMPONENT_PART_ID
    inner join ANALYTICSPRD.ENTERPRISE.SITE_DIM COMPONENT_sd
        on COMPONENT_sd.MFG_AREA_CODE = WU.BOM_COMPONENT_MFG_AREA_CODE
        and COMPONENT_sd.FRONTEND_BACKEND_FLAG  = WU.BOM_COMPONENT_FRONTEND_BACKEND_FLAG
    where wu.MFG_AREA_CODE != 'ZZNOSITE'
      and wu.end_part_component_rank = 1
      and COMPONENT_pd.PART_TYPE_DESCRIPTION not in ( 'Substrate Part','Silicon Carbide Seed Part', 'Ingot Part', 'Silicon Carbide Boule Part', 'Silicon Carbide Powder Part', 'Silicon Carbide Ingot Part', 'PolySilicon Part')
) WHERE COMPONENT_rank = 1
)
, get_fam as (
SELECT distinct p.MFG_PART_ID, case when p.LEGACY_PART_DESCRIPTION = ' ' then null else p.LEGACY_PART_DESCRIPTION end as LEGACY_PART_DESCRIPTION
, dense_rank() over (partition by p.MFG_PART_ID order by wu.component_level desc) as dr
FROM ANALYTICSPRD.ENTERPRISE.PART_DIM p
JOIN applicationprd.mfg.get_supply_path_end_part_component_site wu on p.part_id = wu.part_id
WHERE p.MFG_PART_ID is NOT NULL
and wu.end_part_component_rank = 1
and p.LEGACY_PART_DESCRIPTION is not null and length(p.LEGACY_PART_DESCRIPTION) >1
)
, get_pkg_cfg as
(
SELECT * FROM
(
SELECT distinct p.MFG_PART_ID
     , CASE WHEN REGEXP_LIKE(pdp.PACKING_CONFIG_ID, '^.+-.+_.+_.+_.+$') THEN SUBSTR(pdp.PACKING_CONFIG_ID, 1, REGEXP_INSTR(pdp.PACKING_CONFIG_ID, '_', 1, 2)-1)
       ELSE NULL END AS PKG
     , CASE WHEN pdp.CORE_PART_NO_CONFIG_ID in ( 'UNK', 'Dummy-COR') then NULL
                WHEN pdp.CORE_PART_NO_CONFIG_ID like '%-COR' THEN SUBSTR(pdp.CORE_PART_NO_CONFIG_ID, 1, REGEXP_INSTR(pdp.CORE_PART_NO_CONFIG_ID, '-')-1)
                ELSE pdp.CORE_PART_NO_CONFIG_ID
            END AS FG_DEVICE
     , rank()
       OVER (PARTITION BY p.MFG_PART_ID
             ORDER BY CASE WHEN REGEXP_LIKE(pdp.PACKING_CONFIG_ID, '^.+-.+_.+_.+_.+$') THEN SUBSTR(pdp.PACKING_CONFIG_ID, 1, REGEXP_INSTR(pdp.PACKING_CONFIG_ID, '_', 1, 2)-1) ELSE NULL END NULLS LAST
                    , CASE WHEN pdp.CORE_PART_NO_CONFIG_ID in ( 'UNK', 'Dummy-COR') then NULL
                           WHEN pdp.CORE_PART_NO_CONFIG_ID like '%-COR' THEN SUBSTR(pdp.CORE_PART_NO_CONFIG_ID, 1, REGEXP_INSTR(pdp.CORE_PART_NO_CONFIG_ID, '-')-1)
                           ELSE pdp.CORE_PART_NO_CONFIG_ID
                           END NULLS LAST
             )
       as PKG_RANK
FROM ANALYTICSPRD.ENTERPRISE.PART_DIM p
JOIN applicationprd.mfg.get_supply_path_end_part_component_site wu on p.PART_ID = wu.PART_ID
JOIN ANALYTICSPRD.ENTERPRISE.PART_DIM pdp on wu.end_part_id = pdp.part_id
where pdp.PACKING_CONFIG_ID is not null and REGEXP_LIKE(pdp.PACKING_CONFIG_ID, '^.+-.+_.+_.+_.+$')
and wu.end_part_component_rank = 1
and wu.frontend_backend_flag = 'BE'
and p.part_sub_type_cd not in ( 'WDQ', 'WAF', 'DSG') 
and p.part_sub_area_code not in ('WAFER SALES')
and p.poq_container_code not in ( 'WJAR')
) WHERE PKG_RANK = 1
)
, get_prod as (
select distinct PD.PART_ID
     , REGEXP_REPLACE(case when (regexp_like(COALESCE(NULLIF(pd.MFG_PART_ID, ' '), pd.PART_ID), '^.+-.+-...$')
                             or regexp_like(COALESCE(NULLIF(pd.MFG_PART_ID, ' '), pd.PART_ID), '^.+-'||pd.part_sub_type_cd||'$'))
                           then substr(COALESCE(NULLIF(pd.MFG_PART_ID, ' '), pd.PART_ID), 1, REGEXP_INSTR(COALESCE(NULLIF(pd.MFG_PART_ID, ' '), pd.PART_ID), '[-][^-]+$')-1)
                      else COALESCE(NULLIF(pd.MFG_PART_ID, ' '), pd.PART_ID) end, '-', '_') as PRODUCT
     , REGEXP_REPLACE(case when (regexp_like(pd.PART_ID, '^.+-.+-...$') or regexp_like(pd.PART_ID, '^.+-'||pd.part_sub_type_cd||'$'))
                           then substr(pd.PART_ID, 1, REGEXP_INSTR(pd.PART_ID, '[-][^-]+$')-1)
                      else pd.PART_ID end, '-', '_') as ALT_PRODUCT
     , case when COALESCE(psp_fabsite.BOM_COMPONENT_MFG_AREA_CODE, psp_site.BOM_COMPONENT_MFG_AREA_CODE) = 'UWA' 
             and pd.MFG_PART_ID NOT LIKE '%_WAFER' and pd.PART_ID like '%-FAB' then 'Y' else 'N' end as ADD_WAFER_SUFFIX
     , COALESCE(case when bt.PART_SUB_TYPE_CD in ('ASM', 'MSA', 'MFM', 'TSM', 'OPN', 'ASY') THEN pk.FG_DEVICE ELSE NULL END,
                CASE WHEN REGEXP_LIKE(pd.MFG_PART_ID, '^.+_.+$') THEN SUBSTR(pd.MFG_PART_ID, 1, REGEXP_INSTR(pd.MFG_PART_ID, '_')-1)
                     WHEN REGEXP_LIKE(pd.MFG_PART_ID, '^.+-.+$') THEN SUBSTR(pd.MFG_PART_ID, 1, REGEXP_INSTR(pd.MFG_PART_ID, '-')-1)
                     ELSE pd.MFG_PART_ID END) AS DEVICE
     , gf.LEGACY_PART_DESCRIPTION as PROCESS_FAMILY
     , CASE WHEN bt.PART_SUB_TYPE_CD in ('ASM', 'MSA', 'MFM', 'TSM', 'OPN', 'ASY') then 'FG'
            WHEN bt.PART_SUB_TYPE_CD in ('SWF','WDQ','BMP','SW1', 'DSG') then 'DIE'
            WHEN bt.PART_SUB_TYPE_CD in ('THN', 'BSM') THEN 'WAFER'
            WHEN bt.PART_SUB_TYPE_CD in ('FAB', 'BSP') then 'WAFER'
            WHEN bt.PART_SUB_TYPE_CD in ('BAS') then 'MSLC'
            WHEN bt.PART_SUB_TYPE_CD in ('FBE', 'EPI', 'SEP', 'SPO') then 'EPI' 
            ELSE bt.PART_SUB_TYPE_CD END as PART_TYPE, bt.PART_SUB_TYPE_CD
     , COALESCE(psp_site.BOM_COMPONENT_MFG_AREA_CODE, psp_fabsite.BOM_COMPONENT_MFG_AREA_CODE) AS FAB_CD
     , COALESCE(psp_site.BOM_COMPONENT_MFG_AREA_DESCRIPTION, psp_fabsite.BOM_COMPONENT_MFG_AREA_DESCRIPTION)  AS FAB_NAME
     , pk.PKG
     , pd.PDPW_VALUE
     , pd.WAFER_SIZE_VALUE
     , pd.LAST_CHANGE_DATE AS LAST_CHANGED_DATE
     , COALESCE(CAST (case when pd.DIE_SIZE_X_WI_SCRIBE_STR = ' ' or pd.part_sub_type_cd in ('BAS', 'FBE', 'EPI', 'SEP', 'SPO', 'SCS', 'SCP', 'SCI', 'SCB', 'ING') then null else pd.DIE_SIZE_X_WI_SCRIBE_STR end AS FLOAT), CAST (ds.DIE_SIZE_X_WI_SCRIBE_STR AS FLOAT), 0.0) AS DIE_SIZE_X_WI_SCRIBE_STR
     , COALESCE(CAST (case when pd.DIE_SIZE_Y_WI_SCRIBE_STR = ' ' or pd.part_sub_type_cd in ('BAS', 'FBE', 'EPI', 'SEP', 'SPO', 'SCS', 'SCP', 'SCI', 'SCB', 'ING') then null else pd.DIE_SIZE_Y_WI_SCRIBE_STR end AS FLOAT), CAST (ds.DIE_SIZE_Y_WI_SCRIBE_STR AS FLOAT), 0.0) AS DIE_SIZE_Y_WI_SCRIBE_STR
          , rank() OVER (PARTITION BY CASE WHEN REGEXP_LIKE(PRODUCT, '^[0123456789_]+$') or FAB_CD = 'UV5' or REGEXP_LIKE(PRODUCT, '^0000.+$') then ALT_PRODUCT else PRODUCT END ORDER BY CASE WHEN PART_TYPE in ( 'WAFER', 'WAF') then 1 WHEN PART_TYPE = 'DIE' THEN 2 ELSE 3 END) as PART_RANK
, psp_site.BOM_COMPONENT_MFG_AREA_CODE as psp_site_fabcode, psp_fabsite.BOM_COMPONENT_MFG_AREA_CODE as psp_fabsite_fabcode
from ANALYTICSPRD.ENTERPRISE.PART_DIM pd 
LEFT OUTER JOIN bom_type bt on pd.MFG_PART_ID = bt.MFG_PART_ID and pd.mfg_part_id != ' '
LEFT OUTER JOIN
   (select sz.*, dense_rank() over (partition by BOM_COMPONENT_PART_ID order by rownum) as row_rank
    from    (SELECT wux.BOM_COMPONENT_PART_ID
                  , p.DIE_SIZE_X_WI_SCRIBE_STR
                  , p.DIE_SIZE_Y_WI_SCRIBE_STR
                  , dense_rank() over (partition by wux.BOM_COMPONENT_PART_ID order by case when p.part_sub_type_cd = 'WDQ'  then 1 else 2 end) as size_rank
                  , row_number() over (partition by wux.END_PART_ID order by wux.bom_component_sub_type_code) as rownum
              FROM applicationprd.mfg.get_supply_path_end_part_component_site wux
              JOIN ANALYTICSPRD.ENTERPRISE.PART_DIM p on wux.END_PART_ID = p.PART_ID
              WHERE len( p.DIE_SIZE_X_WI_SCRIBE_STR )>1 and len( p.DIE_SIZE_Y_WI_SCRIBE_STR )>1 and wux.bom_component_type_group_code not in ( 'Substrate Part','Silicon Carbide Seed Part', 'Ingot Part', 'Silicon Carbide Boule Part', 'Silicon Carbide Powder Part', 'Silicon Carbide Ingot Part', 'PolySilicon Part')
                AND wux.end_part_component_rank = 1
            ) sz 
   ) ds on ds.BOM_COMPONENT_PART_ID = pd.PART_ID and ds.size_rank = 1 and ds.row_rank = 1
LEFT OUTER JOIN get_fab psp_site ON psp_site.end_part_id = pd.part_id
LEFT OUTER JOIN get_fab psp_fabsite ON psp_fabsite.BOM_COMPONENT_PART_ID = pd.part_id
LEFT OUTER JOIN get_fam gf ON pd.MFG_PART_ID = gf.MFG_PART_ID and gf.dr = 1 and pd.mfg_part_id != ' '
LEFT OUTER JOIN get_pkg_cfg pk ON pd.MFG_PART_ID = pk.MFG_PART_ID and pd.mfg_part_id != ' '
WHERE PD.PART_SUB_TYPE_CD != 'NRE'
  AND NOT REGEXP_LIKE(pd.MFG_PART_ID, '^\d+$')
  AND NOT REGEXP_LIKE(pd.MFG_PART_ID, '^\d+[A-Z]$')
  and PD.LIFECYCLE_PHASE_DESCRIPTION != 'Obsolete'
  and PD.PART_SUB_TYPE_CD != 'UNK'
  AND EXISTS (SELECT 1 
              FROM applicationprd.mfg.get_supply_path_end_part_component_site wuex
              WHERE wuex.PART_ID = pd.PART_ID and wuex.BOM_COMPONENT_PART_ID not like 'BOB-%'
                and wuex.end_part_component_rank = 1)
)
, res as (
select trim(replace(CASE WHEN REGEXP_LIKE(PRODUCT, '^[0123456789_]+$') or FAB_CD = 'UV5' or REGEXP_LIKE(PRODUCT, '^0000.+$') then ALT_PRODUCT else PRODUCT END, CHAR(160), ' ')) as PRODUCT
     , ADD_WAFER_SUFFIX
     , PART_TYPE AS ITEM_TYPE
     , max(CASE WHEN PDPW_VALUE IS NULL OR PDPW_VALUE = 0 THEN NULL ELSE FAB_CD END) AS FAB
     , max(CASE WHEN PDPW_VALUE IS NULL OR PDPW_VALUE = 0 THEN NULL ELSE FAB_NAME END) AS FAB_DESC
     , ' ' AS AFM
     , max(PROCESS_FAMILY) as PROCESS
     , CASE WHEN FAB_CD = 'UV5' or REGEXP_LIKE(DEVICE, '^0000.+$') then ALT_PRODUCT else DEVICE END as FAMILY
     , PKG AS "PACKAGE"
     , max(PDPW_VALUE) as PDPW
     , 'MM' AS WF_UNITS
     , max(WAFER_SIZE_VALUE) AS WF_SIZE
     , 'MC' AS DIE_UNITS
     , max(DIE_SIZE_X_WI_SCRIBE_STR) AS DIE_WIDTH
     , max(DIE_SIZE_Y_WI_SCRIBE_STR) AS DIE_HEIGHT
     , UPPER(TO_CHAR(LAST_CHANGED_DATE, 'DD-MON-YY')) AS LAST_CHANGED_DATE
     , rank() OVER (PARTITION BY CASE WHEN REGEXP_LIKE(PRODUCT, '^[0123456789_]+$') or FAB_CD = 'UV5' or REGEXP_LIKE(PRODUCT, '^0000.+$') then ALT_PRODUCT else PRODUCT END ORDER BY CASE WHEN PART_TYPE in ('WAFER', 'WAF') then 1 WHEN PART_TYPE = 'DIE' THEN 2 ELSE 3 END) as PART_RANK
FROM get_prod
WHERE PART_TYPE = 'FG' OR (FAB_CD IS NOT NULL AND FAB_CD != ' ' AND PDPW_VALUE > 0)
GROUP BY CASE WHEN REGEXP_LIKE(PRODUCT, '^[0123456789_]+$') or FAB_CD = 'UV5' or REGEXP_LIKE(PRODUCT, '^0000.+$') then ALT_PRODUCT else PRODUCT END
       , ADD_WAFER_SUFFIX, CASE WHEN FAB_CD = 'UV5' or REGEXP_LIKE(DEVICE, '^0000.+$') then ALT_PRODUCT else DEVICE END
       , PART_TYPE, PKG, LAST_CHANGED_DATE
)
select concat(PRODUCT,'|',ifnull(ITEM_TYPE,' '),'|',ifnull(FAB,' '),'|',ifnull(FAB_DESC,' '),'|',ifnull(AFM,' '),'|',ifnull(PROCESS,' '),'|',ifnull(FAMILY, ' '),'|',ifnull(PACKAGE, ' '),'|',ifnull(to_char(PDPW),' '),'|',ifnull(WF_UNITS, ' '),'|',ifnull(to_char(WF_SIZE), ' '),'|',ifnull(DIE_UNITS, ' '),'|',ifnull(to_char(DIE_WIDTH), ' '),'|',ifnull(to_char(DIE_HEIGHT), ' '),'|',LAST_CHANGED_DATE)
from res
WHERE PART_RANK = 1 
union all
select concat(PRODUCT,'_WAFER','|',ifnull(ITEM_TYPE,' '),'|',ifnull(FAB,' '),'|',ifnull(FAB_DESC,' '),'|',ifnull(AFM,' '),'|',ifnull(PROCESS,' '),'|',ifnull(FAMILY, ' '),'|',ifnull(PACKAGE, ' '),'|',ifnull(to_char(PDPW),' '),'|',ifnull(WF_UNITS, ' '),'|',ifnull(to_char(WF_SIZE), ' '),'|',ifnull(DIE_UNITS, ' '),'|',ifnull(to_char(DIE_WIDTH), ' '),'|',ifnull(to_char(DIE_HEIGHT), ' '),'|',LAST_CHANGED_DATE)
from res 
where FAB = 'UWA' and ADD_WAFER_SUFFIX = 'Y' 
  and PART_RANK = 1
ORDER BY 1;

eof

if ! isql "${snow_sid}" "${snow_user}" "${snow_pass}" -b -n -dx -x0x20 < "${tmpScript}" > "${outFileTmp}" 2>> "${logFile}"; then
  echo "ERROR: isql failed (check ODBC DSN ${snow_sid}, user, and password). Log: ${logFile}" >&2
  exit 1
fi

sed -i '/SQLRowCount/d; /+-----------------/d; /IFNULL/d' "${outFileTmp}"

sed -i '1i\
PRODUCT|ITEM_TYPE|FAB|FAB_DESC|AFM|PROCESS|FAMILY|PACKAGE|GDPW|WF_UNITS|WF_SIZE|DIE_UNITS|DIE_WIDTH|DIE_HEIGHT|LAST_CHANGED_DATE
' "${outFileTmp}"

# Sanitize field values: remove single and double quotes from output
sed -i "s/[\"']//g" "${outFileTmp}"

archived_file_path=""
if [ -f "${outFileTmp}" ]; then
  if [ -d "${archiveDir}" ]; then
    b_name=$(basename "${outFileTmp}" | sed 's/\(.*\)\..*/\1/')
    cp -p "${outFileTmp}" "${archiveDir}/${b_name}"
    gzip -f "${archiveDir}/${b_name}"
    archived_file_path="${archiveDir}/${b_name}.gz"
  fi
  mv "${outFileTmp}" "${outFile}"
fi

# Benchmark: append one JSONL record (PipelineInfo-compatible) to benchmark log
if [ -n "${benchmark_log:-}" ]; then
  end_epoch=$(date +%s)
  end_local=$(date +"%Y-%m-%d %H:%M:%S")
  end_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  elapsed_sec_int=$((end_epoch - start_epoch))
  elapsed_seconds="${elapsed_sec_int}.0"
  elapsed_human=""
  [ "$elapsed_sec_int" -ge 3600 ] && elapsed_human="${elapsed_human}$((elapsed_sec_int / 3600))h "
  [ "$elapsed_sec_int" -ge 60 ] && elapsed_human="${elapsed_human}$(((elapsed_sec_int % 3600) / 60))m "
  elapsed_human="${elapsed_human}$((elapsed_sec_int % 60))s"
  rowcount=0
  [ -f "${outFile}" ] && rowcount=$(($(wc -l < "${outFile}") - 1))
  [ "$rowcount" -lt 0 ] && rowcount=0
  mkdir -p "$(dirname "$benchmark_log")"
  BENCHMARK_START_LOCAL="$start_local" BENCHMARK_START_UTC="$start_utc" \
  BENCHMARK_END_LOCAL="$end_local" BENCHMARK_END_UTC="$end_utc" \
  BENCHMARK_ELAPSED="$elapsed_seconds" BENCHMARK_ELAPSED_HUMAN="$elapsed_human" \
  BENCHMARK_OUTPUT_FILE="$outFile" BENCHMARK_ROWCOUNT="$rowcount" \
  BENCHMARK_LOG_FILE="$logFile" BENCHMARK_PID="$$" BENCHMARK_DATE_CODE="$dateCode" \
  BENCHMARK_PIPELINE_NAME="$pipeline_name" BENCHMARK_SCRIPT_NAME="$(basename "$0")" \
  BENCHMARK_PIPELINE_TYPE="$pipeline_type" BENCHMARK_ENV="$benchmark_env" \
  BENCHMARK_ARCHIVED_FILE="$archived_file_path" \
  python3 -c "
import json, os
def v(k, d=''):
    return os.environ.get(k) or d
def f(k):
    return float(v(k, '0'))
def i(k):
    return int(v(k, '0'))
print(json.dumps({
    'start_local': v('BENCHMARK_START_LOCAL'),
    'end_local': v('BENCHMARK_END_LOCAL'),
    'start_utc': v('BENCHMARK_START_UTC'),
    'end_utc': v('BENCHMARK_END_UTC'),
    'elapsed_seconds': f('BENCHMARK_ELAPSED'),
    'elapsed_human': v('BENCHMARK_ELAPSED_HUMAN'),
    'output_file': v('BENCHMARK_OUTPUT_FILE'),
    'rowcount': i('BENCHMARK_ROWCOUNT'),
    'log_file': v('BENCHMARK_LOG_FILE'),
    'pid': i('BENCHMARK_PID'),
    'date_code': v('BENCHMARK_DATE_CODE'),
    'pipeline_name': v('BENCHMARK_PIPELINE_NAME') or None,
    'script_name': v('BENCHMARK_SCRIPT_NAME') or None,
    'pipeline_type': v('BENCHMARK_PIPELINE_TYPE') or None,
    'environment': v('BENCHMARK_ENV') or None,
    'archived_file': v('BENCHMARK_ARCHIVED_FILE') or None,
}))
" >> "${benchmark_log}" 2>/dev/null || true
fi
