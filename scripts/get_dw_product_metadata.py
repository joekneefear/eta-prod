#!/usr/bin/env python3
"""
Extract Product reference data from Snowflake (Python version of n_getDWProductMetadata.sh).

- Uses Snowflake connector (best-practice for Python Snowflake access).
- Writes pipe-delimited output compatible with legacy script.
- Produces benchmark JSONL similar to get_subcon_lot_refdata_rc10.py.

Connection behavior (default):
- Uses positional args snow_user, snow_password, snow_sid (same order as the shell script).
- Resolves Snowflake account in this order: --account, --source_odbc, $SNOWFLAKE_ACCOUNT, snow_sid.
- Optional overrides: --source_warehouse and --source_schema (database.schema).
- If --source_odbc is provided, the script uses ODBC (DSN) via pyodbc.
"""

import os
import sys
import argparse
import re
import time
import json
import gzip
import shutil
import logging
import logging.handlers
from datetime import datetime, timezone
from pathlib import Path

try:
    import snowflake.connector  # pip install snowflake-connector-python
except ImportError:
    snowflake = None

try:
    import pyodbc  # pip install pyodbc
except ImportError:
    pyodbc = None

try:
    SCRIPT_PATH = Path(__file__).resolve()
    SCRIPT_NAME = SCRIPT_PATH.name
except NameError:
    SCRIPT_PATH = None
    SCRIPT_NAME = "get_dw_product_metadata.py"

EARLY_LOG_FILE = "./log/early.log"

# ---------------------------------------------------------------------------
# Logging setup (mirrors get_subcon_lot_refdata_rc10.py style)
# ---------------------------------------------------------------------------

def setup_early_logging():
    os.makedirs("./log", exist_ok=True)
    logger = logging.getLogger("early_logger")
    logger.setLevel(logging.INFO)
    if not logger.handlers:
        fh = logging.FileHandler(EARLY_LOG_FILE, mode="a")
        fh.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        logger.addHandler(fh)
        ch = logging.StreamHandler()
        ch.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        logger.addHandler(ch)
    return logger


def remove_early_logging():
    logger = logging.getLogger("early_logger")
    for handler in logger.handlers:
        handler.close()
    logger.handlers.clear()


def setup_logging(log_dir: str, log_file: str, log_level: str = "INFO") -> None:
    os.makedirs(log_dir, exist_ok=True)
    log_path = os.path.join(log_dir, log_file)
    level = getattr(logging, log_level.upper(), logging.INFO)
    root_logger = logging.getLogger()
    for handler in root_logger.handlers[:]:
        handler.close()
        root_logger.removeHandler(handler)
    root_logger.setLevel(level)
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    file_handler = logging.handlers.RotatingFileHandler(
        log_path, maxBytes=20 * 1024 * 1024, backupCount=5
    )
    file_handler.setFormatter(formatter)
    root_logger.addHandler(file_handler)
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    root_logger.addHandler(console_handler)
    logging.info("----- Job started -----")


# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

def format_elapsed(elapsed_sec):
    mins, sec = divmod(int(elapsed_sec), 60)
    hrs, mins = divmod(mins, 60)
    result = []
    if hrs:
        result.append(f"{hrs}h")
    if mins:
        result.append(f"{mins}m")
    result.append(f"{sec}s")
    return " ".join(result)


def get_pipeline_info():
    hostname = os.getenv("HOSTNAME", os.getenv("COMPUTERNAME", "unknown")).lower()
    environment = "prod"
    if any(env_indicator in hostname for env_indicator in ["dev", "test", "uat", "stage"]):
        environment = "dev" if "dev" in hostname else "test"
    environment = os.getenv("PIPELINE_ENV", environment)
    return {
        "pipeline_name": SCRIPT_NAME,
        "script_name": SCRIPT_NAME,
        "pipeline_type": "batch",
        "environment": environment,
    }


def log_benchmark_jsonl(benchmark_log_dir: str, stats: dict) -> None:
    os.makedirs(benchmark_log_dir, exist_ok=True)
    log_file = os.path.join(benchmark_log_dir, "benchmark.jsonl")
    try:
        with open(log_file, "a", encoding="utf-8") as f:
            json.dump(stats, f)
            f.write("\n")
        logging.info(
            "Benchmark logged: pipeline=%s, rows=%s, duration=%s",
            stats.get("pipeline_name"),
            stats.get("rowcount"),
            stats.get("elapsed_human"),
        )
    except Exception as ex:
        logging.error("Could not write benchmark log: %s", ex)


def archive_and_compress(file_path, archive_dir):
    if not archive_dir:
        return None
    os.makedirs(archive_dir, exist_ok=True)
    basename = os.path.basename(file_path)
    gz_path = os.path.join(archive_dir, basename + ".gz")
    gz_path_tmp = gz_path + ".tmp"
    try:
        with open(file_path, "rb") as f_in, gzip.open(gz_path_tmp, "wb") as f_out:
            shutil.copyfileobj(f_in, f_out)
        os.replace(gz_path_tmp, gz_path)
        gz_abs = os.path.abspath(gz_path)
        logging.info("Archived and compressed %s", gz_abs)
        return gz_abs
    except Exception as e:
        logging.error("Failed to archive/compress: %s", e)
        if os.path.exists(gz_path_tmp):
            os.remove(gz_path_tmp)
        return None


# ---------------------------------------------------------------------------
# SQL builder (faithful to legacy Snowflake query)
# ---------------------------------------------------------------------------

def build_sql(product_like_regex: str | None = None):
        product_like_clause = ""
        if product_like_regex:
                product_like_clause = f"\n  AND REGEXP_LIKE(pd.MFG_PART_ID, '{product_like_regex}')"
        return fr"""
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
where pd.MFG_PART_ID is not null{product_like_clause}
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
    AND NOT REGEXP_LIKE(pd.MFG_PART_ID, '^\\d+$')
    AND NOT REGEXP_LIKE(pd.MFG_PART_ID, '^\\d+[A-Z]$')
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
ORDER BY 1
"""


def read_sql_file(sql_file: str) -> str:
    with open(sql_file, "r", encoding="utf-8") as f:
        return f.read()


def parse_params(params_json: str | None, params_file: str | None) -> dict:
    if params_json and params_file:
        raise ValueError("Use only one of --params_json or --params_file")
    if params_file:
        with open(params_file, "r", encoding="utf-8") as f:
            return json.load(f)
    if params_json:
        return json.loads(params_json)
    return {}


def prepare_sql_with_params(sql: str, params: dict) -> tuple[str, list]:
    """
    Convert :named parameters to qmark placeholders and return ordered values.
    Skips :: casts using a negative lookbehind.
    """
    param_names = []

    def repl(match: re.Match) -> str:
        name = match.group(1)
        param_names.append(name)
        return "?"

    sql_qmark = re.sub(r"(?<!:):([A-Za-z_][A-Za-z0-9_]*)", repl, sql)
    values = []
    for name in param_names:
        if name not in params:
            raise ValueError(f"Missing SQL parameter: {name}")
        values.append(params[name])
    return sql_qmark, values


# ---------------------------------------------------------------------------
# Writer
# ---------------------------------------------------------------------------

def write_results(output_path, cursor, write_header=True):
    tmp_path = output_path + ".tmp"
    rowcount = 0
    with open(tmp_path, "w", encoding="utf-8", buffering=1) as outf:
        if write_header:
            outf.write(
                "PRODUCT|ITEM_TYPE|FAB|FAB_DESC|AFM|PROCESS|FAMILY|PACKAGE|GDPW|WF_UNITS|WF_SIZE|DIE_UNITS|DIE_WIDTH|DIE_HEIGHT|LAST_CHANGED_DATE\n"
            )
        for rows in iter(lambda: cursor.fetchmany(cursor.arraysize), []):
            for row in rows:
                outf.write(f"{row[0]}\n")
                rowcount += 1
    os.replace(tmp_path, output_path)
    return rowcount


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract DW Product Metadata from Snowflake (Python version)."
    )
    parser.add_argument("snow_user", help="Snowflake user")
    parser.add_argument("snow_password", help="Snowflake password")
    parser.add_argument("snow_sid", help="Snowflake connection identifier (default account fallback)")
    parser.add_argument(
        "product_like",
        nargs="?",
        choices=["productLike0to9", "productLikeAtoM", "productLikeNtoZ"],
        help="Optional legacy filter: productLike0to9 | productLikeAtoM | productLikeNtoZ",
    )
    parser.add_argument(
        "--account",
        help="Snowflake account override (defaults to --source_odbc, $SNOWFLAKE_ACCOUNT, then snow_sid)",
    )
    parser.add_argument(
        "--source_odbc",
        help="ODBC/DSN style name (used as account fallback if --account not set)",
    )
    parser.add_argument(
        "--source_warehouse",
        help="Warehouse override (e.g. MFG_PRD_RPT_WH)",
    )
    parser.add_argument(
        "--source_schema",
        help="Database and schema in the form DATABASE.SCHEMA (e.g. ANALYTICSPRD.MFG)",
    )
    parser.add_argument(
        "--sql_file",
        help="Path to SQL file to execute (optional). Use :param placeholders for parameters.",
    )
    parser.add_argument(
        "--params_json",
        help="JSON object of SQL parameters for :param placeholders.",
    )
    parser.add_argument(
        "--params_file",
        help="Path to JSON file with SQL parameters for :param placeholders.",
    )
    parser.add_argument("--warehouse", default="application_prd_wh", help="Snowflake warehouse")
    parser.add_argument("--role", default="APPLICATIONPRD_MFG_CONSUMER_RO", help="Snowflake role")
    parser.add_argument("--secondary_roles", default="ALL", help="Snowflake secondary roles")
    parser.add_argument("--reference_data_dir", default=os.getenv("REFERENCE_DATA_DIR", ""), help="Output directory")
    parser.add_argument("--archive_dir", default="/apps/exensio_data/archives-yms/reference_data/product", help="Archive directory (gz)")
    parser.add_argument("--log_dir", default="./log", help="Log directory")
    parser.add_argument("--log_file", default="getDWProductMetadata.log", help="Log filename")
    parser.add_argument("--log_level", default="INFO", help="Log level")
    parser.add_argument("--benchmark_log_dir", default="./benchmark", help="Benchmark JSONL log dir")
    parser.add_argument("--output_prefix", default="DWProductDimProductInfo", help="Output file prefix")
    parser.add_argument("--pipeline_name", default=SCRIPT_NAME, help="Pipeline name")
    parser.add_argument("--pipeline_type", default="batch", help="Pipeline type")
    parser.add_argument("--environment", help="Environment override (prod/dev/test)")
    return parser.parse_args()


def connect_via_odbc(dsn: str, user: str, password: str):
    if not pyodbc:
        print("You must install the 'pyodbc' package to use --source_odbc", file=sys.stderr)
        sys.exit(1)
    conn_str = f"DSN={dsn};UID={user};PWD={password}"
    return pyodbc.connect(conn_str, autocommit=True)


def connect_via_connector(account: str, user: str, password: str, warehouse: str, role: str, database: str, schema: str):
    if not snowflake:
        print("You must install the 'snowflake-connector-python' package", file=sys.stderr)
        sys.exit(1)
    return snowflake.connector.connect(
        user=user,
        password=password,
        account=account,
        warehouse=warehouse,
        role=role,
        database=database,
        schema=schema,
    )


def main():
    setup_early_logging()

    try:
        args = parse_args()
        setup_logging(args.log_dir, args.log_file, args.log_level)
        remove_early_logging()

        pipeline_info = get_pipeline_info()
        if args.pipeline_name != SCRIPT_NAME:
            pipeline_info["pipeline_name"] = args.pipeline_name
        if args.pipeline_type != "batch":
            pipeline_info["pipeline_type"] = args.pipeline_type
        if args.environment:
            pipeline_info["environment"] = args.environment

        logging.info(
            "Pipeline: %s | Type: %s | Environment: %s | Script: %s",
            pipeline_info["pipeline_name"],
            pipeline_info["pipeline_type"],
            pipeline_info["environment"],
            SCRIPT_NAME,
        )

        for d in [args.reference_data_dir, args.benchmark_log_dir, args.log_dir]:
            if not d:
                logging.error("Directory argument is empty: %s", d)
                print(f"Directory argument is empty: {d}", file=sys.stderr)
                sys.exit(1)
            os.makedirs(d, exist_ok=True)

        date_code = datetime.now().strftime("%Y%m%d_%H%M%S")
        out_file = os.path.join(
            args.reference_data_dir, f"{args.output_prefix}-{date_code}.prod"
        )

        product_like_map = {
            "productLike0to9": "^[0-9].*",
            "productLikeAtoM": "^[A-M].*",
            "productLikeNtoZ": "^[N-Z].*",
        }
        product_like_regex = product_like_map.get(args.product_like) if args.product_like else None

        params = parse_params(args.params_json, args.params_file)
        if product_like_regex:
            params["product_like"] = product_like_regex

        if args.sql_file:
            sql_query = read_sql_file(args.sql_file)
        else:
            sql_query = build_sql(product_like_regex)

        sql_exec, sql_params = prepare_sql_with_params(sql_query, params) if ":" in sql_query else (sql_query, [])
        start_time = time.time()
        start_local = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        start_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        logging.info("Running Snowflake export to %s ...", out_file)

        conn = None
        rowcount = 0
        try:
            account = (
                args.account
                or args.source_odbc
                or os.getenv("SNOWFLAKE_ACCOUNT")
                or args.snow_sid
            )
            database = None
            schema = None
            if args.source_schema:
                if "." in args.source_schema:
                    database, schema = args.source_schema.split(".", 1)
                else:
                    schema = args.source_schema

            if args.source_odbc:
                conn = connect_via_odbc(args.source_odbc, args.snow_user, args.snow_password)
                cur = conn.cursor()
                if args.source_warehouse:
                    cur.execute(f"use warehouse {args.source_warehouse}")
                if args.source_schema:
                    cur.execute(f"use schema {args.source_schema}")
                if args.secondary_roles:
                    cur.execute(f"use secondary roles {args.secondary_roles}")
                if sql_params:
                    cur.execute(sql_exec, sql_params)
                else:
                    cur.execute(sql_exec)
                if cur.description is None:
                    logging.error("The executed statement returned no result set.")
                    print("The executed statement returned no result set.", file=sys.stderr)
                    sys.exit(2)
                cur.arraysize = 10000
                rowcount = write_results(out_file, cur, write_header=True)
                cur.close()
            else:
                conn = connect_via_connector(
                    account=account,
                    user=args.snow_user,
                    password=args.snow_password,
                    warehouse=args.source_warehouse or args.warehouse,
                    role=args.role,
                    database=database,
                    schema=schema,
                )
                with conn.cursor() as cur:
                    if args.source_warehouse:
                        cur.execute(f"use warehouse {args.source_warehouse};")
                    if args.source_schema:
                        cur.execute(f"use schema {args.source_schema};")
                    if args.secondary_roles:
                        cur.execute(f"use secondary roles {args.secondary_roles};")
                    if sql_params:
                        cur.execute(sql_exec, sql_params)
                    else:
                        cur.execute(sql_exec)
                    if cur.description is None:
                        logging.error("The executed statement returned no result set.")
                        print("The executed statement returned no result set.", file=sys.stderr)
                        sys.exit(2)
                    cur.arraysize = 10000
                    rowcount = write_results(out_file, cur, write_header=True)
        except Exception as e:
            logging.error("Error during export: %s", e)
            sys.exit(2)
        finally:
            if conn:
                try:
                    conn.close()
                except Exception:
                    pass

        elapsed = time.time() - start_time
        end_local = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        end_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        human_elapsed = format_elapsed(elapsed)
        archived_file = "NA"

        if os.path.exists(out_file) and rowcount > 0:
            logging.info(
                "Snowflake export succeeded: %s (%s rows)", out_file, rowcount
            )
            logging.info("Elapsed time: %s (%.3f seconds)", human_elapsed, elapsed)
            if args.archive_dir:
                archived_path = archive_and_compress(out_file, args.archive_dir)
                if archived_path:
                    archived_file = archived_path
        else:
            logging.error("Snowflake export failed or produced empty file.")
            sys.exit(2)

        stats = {
            "start_local": start_local,
            "end_local": end_local,
            "start_utc": start_utc,
            "end_utc": end_utc,
            "elapsed_seconds": round(elapsed, 3),
            "elapsed_human": human_elapsed,
            "output_file": os.path.abspath(out_file),
            "rowcount": rowcount,
            "log_file": os.path.join(args.log_dir, args.log_file),
            "archived_file": archived_file,
            "pid": os.getpid(),
            "date_code": date_code,
            "pipeline_name": pipeline_info["pipeline_name"],
            "script_name": pipeline_info["script_name"],
            "pipeline_type": pipeline_info["pipeline_type"],
            "environment": pipeline_info["environment"],
        }
        log_benchmark_jsonl(args.benchmark_log_dir, stats)
        logging.info("Benchmark log appended to %s/benchmark.jsonl", args.benchmark_log_dir)
        logging.info("----- Job finished -----")
    finally:
        pass


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        logging.critical("Uncaught error: %s", e, exc_info=True)
        print(f"Script failed: {e}", file=sys.stderr)
        sys.exit(3)
