#!/usr/bin/env python3
"""
DW Product with Snowflake SiteDim Metadata Extraction.

- Uses Snowflake via connector or ODBC DSN.
- Uses embedded SQL query (static by default, supports :param placeholders).
- Writes pipe-delimited output and benchmark JSONL.

AUTHOR
   Scott Boothby (SQL Query)
   jgarcia (wrapper script)

CHANGES
    2026-Mar-06 - initial implementation
"""

import os
import sys
import argparse
import time
import json
import gzip
import shutil
import logging
import logging.handlers
import re
from datetime import datetime, timezone
from pathlib import Path

try:
    from filelock import FileLock, Timeout  # pip install filelock
except ImportError:
    print("You must install the 'filelock' package: pip install filelock")
    sys.exit(1)


DW_PRODUCT_METADATA_SQL = r"""
with bom_type as(
select  * from (
select distinct pd.MFG_PART_ID, pd.PART_SUB_TYPE_CD
, rank() over (partition by pd.MFG_PART_ID
               order by case when pd.part_sub_type_cd in ('POL', 'SXL', 'SPO', 'SEP') then 99 -- pre-EPI; don't want
                             when pd.part_sub_type_cd in ('EPI', 'FBE') then 99  -- don't want EPI type
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
where pd.MFG_PART_ID is not null
												
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
            --  We first prefer a FAB or FAB-like part.
                case when COMPONENT_PD.PART_TYPE_DESCRIPTION in ( 'Substrate Part','Silicon Carbide Seed Part', 'Ingot Part', 'Silicon Carbide Boule Part', 'Silicon Carbide Powder Part', 'Silicon Carbide Ingot Part', 'PolySilicon Part') then 2
                else 1 end,
                case
                     when WU.BOM_COMPONENT_SUB_TYPE_CODE = 'FAB' then 1
                     when WU.BOM_COMPONENT_SUB_TYPE_CODE = 'WAF' then 2
                     when WU.BOM_COMPONENT_SUB_TYPE_CODE = 'SWF' then 3
                     when COMPONENT_PD.PART_TYPE_DESCRIPTION = 'Wafer Fab Part' then 4
                     when WU.BOM_COMPONENT_SUB_TYPE_CODE = 'BAS' then 5
                     when WU.BOM_COMPONENT_SUB_TYPE_CODE = 'EPI' then 6
                     else 99 end,
            -- We next prefer the most upstream component, then break ties
            -- by BOM_COMPONENT_PART_ID.
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
     , COALESCE(case when p.part_sub_type_cd not in ('DSG') and p.CORE_PART_NO_CONFIG_ID not in ( 'UNK', 'Dummy-COR') then REGEXP_REPLACE(p.CORE_PART_NO_CONFIG_ID, '-COR$', '') else null end, 
            CASE WHEN pdp.CORE_PART_NO_CONFIG_ID in ( 'UNK', 'Dummy-COR') then NULL
            ELSE  REGEXP_REPLACE(pdp.CORE_PART_NO_CONFIG_ID, '-COR$', '')
            END) AS FG_DEVICE
     , rank()
       OVER (PARTITION BY REGEXP_REPLACE(case when (regexp_like(COALESCE(NULLIF(p.MFG_PART_ID, ' '), p.PART_ID), '^.+-.+-...$')
                             or regexp_like(COALESCE(NULLIF(p.MFG_PART_ID, ' '), p.PART_ID), '^.+-'||p.part_sub_type_cd||'$'))
                           then substr(COALESCE(NULLIF(p.MFG_PART_ID, ' '), p.PART_ID), 1, REGEXP_INSTR(COALESCE(NULLIF(p.MFG_PART_ID, ' '), p.PART_ID), '[-][^-]+$')-1)
                      else COALESCE(NULLIF(p.MFG_PART_ID, ' '), p.PART_ID) end, '-', '_')
             ORDER BY CASE p.PART_SUB_TYPE_CD 
                      WHEN 'OPN' then 1
                      WHEN 'TST' then 2
                      WHEN 'ASY' then 3
                      WHEN 'ASM' then 4
                      WHEN 'MSA' then 5
                      WHEN 'MFM' then 6
                      ELSE 5 END
                    , CASE WHEN REGEXP_LIKE(pdp.PACKING_CONFIG_ID, '^.+-.+_.+_.+_.+$') THEN SUBSTR(pdp.PACKING_CONFIG_ID, 1, REGEXP_INSTR(pdp.PACKING_CONFIG_ID, '_', 1, 2)-1) ELSE NULL END NULLS LAST
														  
                    , REGEXP_COUNT(wu.DPS_COMPONENT_PART_PATH, '/') DESC NULLS LAST
            )
       as PKG_RANK, p.PART_SUB_TYPE_CD, p.part_id, wu.end_part_id
FROM ANALYTICSPRD.ENTERPRISE.PART_DIM p
JOIN applicationprd.mfg.get_supply_path_end_part_component_site wu on p.PART_ID = wu.PART_ID
JOIN ANALYTICSPRD.ENTERPRISE.PART_DIM pdp on wu.end_part_id = pdp.part_id
																								  
where wu.end_part_component_rank = 1
and wu.frontend_backend_flag = 'BE'
and p.part_sub_type_cd not in ( 'WDQ', 'WAF', 'DSG') /* WLCSP*/
and p.mfg_part_id not like '%-XTD' and p.mfg_part_id not like ('%-XTP') -- Shipped parts
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
     , case when 
            case when psp_site.BOM_COMPONENT_TYPE_DESC in ( 'Substrate Part','Silicon Carbide Seed Part', 'Ingot Part', 'Silicon Carbide Boule Part', 'Silicon Carbide Powder Part', 'Silicon Carbide Ingot Part', 'PolySilicon Part') and psp_fabsite.BOM_COMPONENT_TYPE_DESC not in ( 'Substrate Part','Silicon Carbide Seed Part', 'Ingot Part', 'Silicon Carbide Boule Part', 'Silicon Carbide Powder Part', 'Silicon Carbide Ingot Part', 'PolySilicon Part') 
                 then psp_fabsite.BOM_COMPONENT_MFG_AREA_CODE 
                 else COALESCE(psp_site.BOM_COMPONENT_MFG_AREA_CODE, psp_fabsite.BOM_COMPONENT_MFG_AREA_CODE) 
                  end  = 'UWA' 
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
            ELSE bt.PART_SUB_TYPE_CD END as PART_TYPE
     , bt.PART_SUB_TYPE_CD
     , case when psp_site.BOM_COMPONENT_TYPE_DESC in ( 'Substrate Part','Silicon Carbide Seed Part', 'Ingot Part', 'Silicon Carbide Boule Part', 'Silicon Carbide Powder Part', 'Silicon Carbide Ingot Part', 'PolySilicon Part') and psp_fabsite.BOM_COMPONENT_TYPE_DESC not in ( 'Substrate Part','Silicon Carbide Seed Part', 'Ingot Part', 'Silicon Carbide Boule Part', 'Silicon Carbide Powder Part', 'Silicon Carbide Ingot Part', 'PolySilicon Part') then psp_fabsite.BOM_COMPONENT_MFG_AREA_CODE 
        else COALESCE(psp_site.BOM_COMPONENT_MFG_AREA_CODE, psp_fabsite.BOM_COMPONENT_MFG_AREA_CODE) 
        end as FAB_CD
     , case when psp_site.BOM_COMPONENT_TYPE_DESC in ( 'Substrate Part','Silicon Carbide Seed Part', 'Ingot Part', 'Silicon Carbide Boule Part', 'Silicon Carbide Powder Part', 'Silicon Carbide Ingot Part', 'PolySilicon Part') and psp_fabsite.BOM_COMPONENT_TYPE_DESC not in ( 'Substrate Part','Silicon Carbide Seed Part', 'Ingot Part', 'Silicon Carbide Boule Part', 'Silicon Carbide Powder Part', 'Silicon Carbide Ingot Part', 'PolySilicon Part') then psp_fabsite.BOM_COMPONENT_MFG_AREA_DESCRIPTION else COALESCE(psp_site.BOM_COMPONENT_MFG_AREA_DESCRIPTION, psp_fabsite.BOM_COMPONENT_MFG_AREA_DESCRIPTION) end as FAB_NAME
     , pk.PKG
     , pd.PDPW_VALUE
     , pd.WAFER_SIZE_VALUE
     , pd.LAST_CHANGE_DATE AS LAST_CHANGED_DATE
--Die size (with scribe) is currently available on the WDQ part.
--Die Size X With Scribe/Street (um)
--Die Size Y With Scribe/Street (um)
     , COALESCE(CAST (case when pd.DIE_SIZE_X_WI_SCRIBE_STR = ' ' or pd.part_sub_type_cd in ('BAS', 'FBE', 'EPI', 'SEP', 'SPO', 'SCS', 'SCP', 'SCI', 'SCB', 'ING') then null else pd.DIE_SIZE_X_WI_SCRIBE_STR end AS FLOAT), CAST (ds.DIE_SIZE_X_WI_SCRIBE_STR AS FLOAT), 0.0) AS DIE_SIZE_X_WI_SCRIBE_STR
     , COALESCE(CAST (case when pd.DIE_SIZE_Y_WI_SCRIBE_STR = ' ' or pd.part_sub_type_cd in ('BAS', 'FBE', 'EPI', 'SEP', 'SPO', 'SCS', 'SCP', 'SCI', 'SCB', 'ING') then null else pd.DIE_SIZE_Y_WI_SCRIBE_STR end AS FLOAT), CAST (ds.DIE_SIZE_Y_WI_SCRIBE_STR AS FLOAT), 0.0) AS DIE_SIZE_Y_WI_SCRIBE_STR
          , rank() OVER (PARTITION BY CASE WHEN (PART_TYPE != 'FG' and (REGEXP_LIKE(PRODUCT, '^[0123456789_]+$') or FAB_CD = 'UV5')) or REGEXP_LIKE(PRODUCT, '^0000.+$') 
                                           THEN ALT_PRODUCT 
                                           ELSE PRODUCT END 
                         ORDER BY  pd.PDPW_VALUE desc
                                 , CASE WHEN PART_TYPE in ( 'WAFER', 'WAF') then 1 
                                        WHEN PART_TYPE in ('WSG') THEN 2
                                        WHEN PART_TYPE = 'DIE' THEN 3 
                                        ELSE 4 
                                   END
                                 , psp_site.COMPONENT_RANK
                                 , ifnull(psp_fabsite.COMPONENT_RANK, 999)
                                 , pk.PKG NULLS LAST
                                 , CASE WHEN bt.PART_SUB_TYPE_CD in ('ASM', 'MSA', 'MFM', 'TSM', 'OPN', 'ASY') THEN pk.FG_DEVICE ELSE NULL END NULLS LAST
                                 , CASE WHEN PART_TYPE = 'FG' 
                                        THEN CASE WHEN psp_site.BOM_COMPONENT_TYPE_DESC in ( 'Substrate Part','Silicon Carbide Seed Part', 'Ingot Part', 'Silicon Carbide Boule Part', 'Silicon Carbide Powder Part', 'Silicon Carbide Ingot Part', 'PolySilicon Part') and psp_fabsite.BOM_COMPONENT_TYPE_DESC not in ( 'Substrate Part','Silicon Carbide Seed Part', 'Ingot Part', 'Silicon Carbide Boule Part', 'Silicon Carbide Powder Part', 'Silicon Carbide Ingot Part', 'PolySilicon Part') 
                                                  THEN psp_fabsite.BOM_COMPONENT_MFG_AREA_CODE 
                                                  ELSE COALESCE(psp_site.BOM_COMPONENT_MFG_AREA_CODE, psp_fabsite.BOM_COMPONENT_MFG_AREA_CODE) 
                                        END
                                   ELSE NULL
                                   END NULLS LAST -- FAB_CD, but only when item type = FG.  Multiple fabs will create multiple rows in output but we don't record fab code for FG parts
                        ) as PART_RANK
, psp_site.BOM_COMPONENT_TYPE_DESC psps_bcts, psp_site.end_part_id psp_epi, psp_site.BOM_COMPONENT_MFG_AREA_CODE psps_ac, psp_fabsite.BOM_COMPONENT_PART_ID as psp_bcpi, psp_fabsite.BOM_COMPONENT_MFG_AREA_CODE psp_ac, psp_site.COMPONENT_RANK psp_cr, psp_fabsite.COMPONENT_RANK as pspfs_cr
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
/* PRODUCT must exist in the BOM. */
  AND EXISTS (SELECT 1 
              FROM applicationprd.mfg.get_supply_path_end_part_component_site wuex
              WHERE wuex.PART_ID = pd.PART_ID and wuex.BOM_COMPONENT_PART_ID not like 'BOB-%'
                and wuex.end_part_part_component_rank = 1
                )
)
, res as (
select trim(replace(CASE WHEN (PART_TYPE != 'FG' and (REGEXP_LIKE(PRODUCT, '^[0123456789_]+$') or FAB_CD = 'UV5')) or REGEXP_LIKE(PRODUCT, '^0000.+$') then ALT_PRODUCT else PRODUCT END, CHAR(160), ' ')) as PRODUCT
     , ADD_WAFER_SUFFIX
     , PART_TYPE AS ITEM_TYPE
     , max(CASE WHEN PDPW_VALUE IS NULL OR PDPW_VALUE = 0 THEN NULL ELSE FAB_CD END) AS FAB
     , max(CASE WHEN PDPW_VALUE IS NULL OR PDPW_VALUE = 0 THEN NULL ELSE FAB_NAME END) AS FAB_DESC
     , ' ' AS AFM
     , max(PROCESS_FAMILY) as PROCESS
     , CASE WHEN (PART_TYPE != 'FG' and (REGEXP_LIKE(DEVICE, '^[0123456789_]+$') or FAB_CD = 'UV5')) or REGEXP_LIKE(DEVICE, '^0000.+$') then ALT_PRODUCT else DEVICE END as FAMILY
     , PKG AS "PACKAGE"
     , max(PDPW_VALUE) as PDPW
     , 'MM' AS WF_UNITS
     , max(WAFER_SIZE_VALUE) AS WF_SIZE
     , 'MC' AS DIE_UNITS
     , max(DIE_SIZE_X_WI_SCRIBE_STR) AS DIE_WIDTH
     , max(DIE_SIZE_Y_WI_SCRIBE_STR) AS DIE_HEIGHT
     , MAX(UPPER(TO_CHAR(LAST_CHANGED_DATE, 'DD-MON-YY'))) AS LAST_CHANGED_DATE
     , rank() OVER (PARTITION BY CASE WHEN (PART_TYPE != 'FG' AND (REGEXP_LIKE(PRODUCT, '^[0123456789_]+$') or FAB_CD = 'UV5')) or REGEXP_LIKE(PRODUCT, '^0000.+$') then ALT_PRODUCT else PRODUCT END ORDER BY CASE WHEN PART_TYPE in ('WAFER', 'WAF') then 1 WHEN PART_TYPE = 'DIE' THEN 2 ELSE 3 END) as PART_RANK
FROM get_prod g
WHERE (PART_TYPE = 'FG' OR (FAB_CD IS NOT NULL AND FAB_CD != ' ' AND PDPW_VALUE > 0)) and g.part_rank = 1
GROUP BY CASE WHEN (PART_TYPE != 'FG' and (REGEXP_LIKE(PRODUCT, '^[0123456789_]+$') or FAB_CD = 'UV5')) or REGEXP_LIKE(PRODUCT, '^0000.+$') then ALT_PRODUCT else PRODUCT END
       , ADD_WAFER_SUFFIX, CASE WHEN (PART_TYPE != 'FG' and (REGEXP_LIKE(DEVICE, '^[0123456789_]+$') or FAB_CD = 'UV5')) or REGEXP_LIKE(DEVICE, '^0000.+$') then ALT_PRODUCT else DEVICE END
       , PART_TYPE, PKG
)
select replace(concat(PRODUCT,'|',ifnull(ITEM_TYPE,' '),'|',ifnull(FAB,' '),'|',ifnull(FAB_DESC,' '),'|',ifnull(AFM,' '),'|',ifnull(PROCESS,' '),'|',ifnull(FAMILY, ' '),'|',ifnull(PACKAGE, ' '),'|',ifnull(to_char(PDPW),' '),'|',ifnull(WF_UNITS, ' '),'|',ifnull(to_char(WF_SIZE), ' '),'|',ifnull(DIE_UNITS, ' '),'|',ifnull(to_char(DIE_WIDTH), ' '),'|',ifnull(to_char(DIE_HEIGHT), ' '),'|',LAST_CHANGED_DATE), '"', '') as "PRODUCT|ITEM_TYPE|FAB|FAB_DESC|AFM|PROCESS|FAMILY|PACKAGE|GDPW|WF_UNITS|WF_SIZE|DIE_UNITS|DIE_WIDTH|DIE_HEIGHT|LAST_CHANGED_DATE"
from res
WHERE PART_RANK = 1 and product is not null
union all
select replace(concat(PRODUCT,'_WAFER','|',ifnull(ITEM_TYPE,' '),'|',ifnull(FAB,' '),'|',ifnull(FAB_DESC,' '),'|',ifnull(AFM,' '),'|',ifnull(PROCESS,' '),'|',ifnull(FAMILY, ' '),'|',ifnull(PACKAGE, ' '),'|',ifnull(to_char(PDPW),' '),'|',ifnull(WF_UNITS, ' '),'|',ifnull(to_char(WF_SIZE), ' '),'|',ifnull(DIE_UNITS, ' '),'|',ifnull(to_char(DIE_WIDTH), ' '),'|',ifnull(to_char(DIE_HEIGHT), ' '),'|',LAST_CHANGED_DATE), '"', '') as "PRODUCT|ITEM_TYPE|FAB|FAB_DESC|AFM|PROCESS|FAMILY|PACKAGE|GDPW|WF_UNITS|WF_SIZE|DIE_UNITS|DIE_WIDTH|DIE_HEIGHT|LAST_CHANGED_DATE"
from res 
where FAB = 'UWA' and ADD_WAFER_SUFFIX = 'Y' 
  and PART_RANK = 1 and product is not null
ORDER BY 1;
"""

try:
    import snowflake.connector  # pip install snowflake-connector-python
except ImportError:
    snowflake = None

try:
    import pyodbc  # pip install pyodbc
except ImportError:
    pyodbc = None

try:
    import oracledb  # pip install oracledb
except ImportError:
    oracledb = None

try:
    import yaml  # pip install pyyaml
except ImportError:
    yaml = None

try:
    SCRIPT_PATH = Path(__file__).resolve()
    SCRIPT_NAME = SCRIPT_PATH.name
except NameError:
    SCRIPT_PATH = None
    SCRIPT_NAME = "get_dw_product_sf_sitedim_metadata.py"

EARLY_LOG_FILE = "./log/early.log"


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


def log_benchmark_to_oracle(stats: dict, dsn: str, user: str = None, password: str = None) -> None:
    """
    Insert benchmark data into Oracle pipeline_runs table.
    
    Args:
        stats: Benchmark statistics dictionary
        dsn: Oracle TNS name or connection string
        user: Oracle username (defaults to 'refdb' if not provided)
        password: Oracle password (defaults to hardcoded value if not provided)
    """
    if not oracledb:
        logging.warning("oracledb package not installed, skipping Oracle benchmark insert")
        return
    
    # Use default credentials if not provided
    if not user:
        user = "refdb"
        password = 'br#^gox66312sdAB'
        logging.info("Using default benchmark database credentials (user: %s)", user)
    
    if not password:
        logging.warning("Oracle password not provided, skipping Oracle benchmark insert")
        return
    
    conn = None
    try:
        conn = oracledb.connect(user=user, password=password, dsn=dsn)
        cursor = conn.cursor()
        
        # Prepare metadata JSON
        metadata = {
            "source_name": stats.get("source_name"),
            "output_name": stats.get("output_name"),
            "rows_fetched": stats.get("rows_fetched", 0),
            "rows_kept": stats.get("rows_kept", 0),
            "rows_skipped": stats.get("rows_skipped", 0),
        }
        
        # Serialize arrays/objects to JSON strings for CLOB columns
        metadata_json = json.dumps(metadata)
        benchmark_json = json.dumps(stats)
        
        # Parse timestamps for Oracle (convert ISO 8601 to Oracle format)
        start_local = stats.get("start_local", "")
        end_local = stats.get("end_local", "")
        start_utc = stats.get("start_utc", "")
        end_utc = stats.get("end_utc", "")
        
        sql = """
            INSERT INTO pipeline_runs (
                start_local, end_local, start_utc, end_utc,
                elapsed_seconds, elapsed_human, output_file, rowcount, log_file,
                pid, date_code, pipeline_name, script_name, pipeline_type, environment,
                archived_file, rows_extracted, rows_written, total_files, metadata, benchmark,
                output_files_trace, archived_gen_files, archived_trace_files, out_files,
                status, error_message, hostname, run_args
            ) VALUES (
                TO_TIMESTAMP(:start_local, 'YYYY-MM-DD HH24:MI:SS'),
                TO_TIMESTAMP(:end_local, 'YYYY-MM-DD HH24:MI:SS'),
                TO_TIMESTAMP_TZ(:start_utc, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                TO_TIMESTAMP_TZ(:end_utc, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                :elapsed_seconds, :elapsed_human, :output_file, :rowcount, :log_file,
                :pid, :date_code, :pipeline_name, :script_name, :pipeline_type, :environment,
                :archived_file, :rows_extracted, :rows_written, :total_files, :metadata, :benchmark,
                :output_files_trace, :archived_gen_files, :archived_trace_files, :out_files,
                :status, :error_message, :hostname, :run_args
            )
        """
        
        # Get hostname and run arguments
        import socket
        hostname = socket.gethostname()
        run_args = " ".join(sys.argv)
        
        cursor.execute(sql, {
            "start_local": start_local or "N/A",
            "end_local": end_local or "N/A",
            "start_utc": start_utc or "N/A",
            "end_utc": end_utc or "N/A",
            "elapsed_seconds": stats.get("elapsed_seconds") or 0.0,
            "elapsed_human": stats.get("elapsed_human") or "N/A",
            "output_file": stats.get("output_file") or "N/A",
            "rowcount": stats.get("rowcount") or 0,
            "log_file": stats.get("log_file") or "N/A",
            "pid": stats.get("pid") or 0,
            "date_code": stats.get("date_code") or "N/A",
            "pipeline_name": stats.get("pipeline_name") or "N/A",
            "script_name": stats.get("script_name") or "N/A",
            "pipeline_type": stats.get("pipeline_type") or "N/A",
            "environment": stats.get("environment") or "N/A",
            "archived_file": stats.get("archived_file") or "N/A",
            "rows_extracted": stats.get("rows_extracted") or 0,
            "rows_written": stats.get("rows_written") or 0,
            "total_files": stats.get("total_files") or 0,
            "metadata": metadata_json,
            "benchmark": benchmark_json,
            "output_files_trace": "[]",
            "archived_gen_files": "[]",
            "archived_trace_files": "[]",
            "out_files": json.dumps(stats.get("out_files", [])),
            "status": stats.get("status", "success"),
            "error_message": stats.get("error_message", ""),
            "hostname": hostname,
            "run_args": run_args,
        })
        
        conn.commit()
        logging.info("Benchmark data inserted into Oracle pipeline_runs table")
        
    except Exception as ex:
        logging.error("Failed to insert benchmark into Oracle: %s", ex)
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


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
    param_names: list[str] = []

    # We must ignore :tokens that appear inside single-quoted string literals
    # (e.g. the Oracle format 'HH24:MI:SS' contains :MI which is NOT a param).
    out_chars: list[str] = []
    i = 0
    L = len(sql)
    in_sq = False
    while i < L:
        ch = sql[i]
        if ch == "'":
            # enter or exit single-quote literal; handle doubled quotes
            in_sq = not in_sq
            out_chars.append(ch)
            i += 1
            # copy until closing quote (respect doubled single quotes)
            while i < L and in_sq:
                out_chars.append(sql[i])
                if sql[i] == "'":
                    # if next char is also a quote it's an escaped quote
                    if i + 1 < L and sql[i + 1] == "'":
                        # keep both and advance
                        out_chars.append(sql[i + 1])
                        i += 2
                        continue
                    else:
                        in_sq = False
                        i += 1
                        break
                i += 1
            continue

        # match :name when not preceded by ':' (skip :: casts) and not in quote
        if ch == ":" and not in_sq and i + 1 < L and sql[i - 1:i] != ":":
            m = re.match(r":([A-Za-z_][A-Za-z0-9_]*)", sql[i:])
            if m:
                name = m.group(1)
                param_names.append(name)
                out_chars.append("?")
                i += 1 + len(name)
                continue

        out_chars.append(ch)
        i += 1

    sql_qmark = "".join(out_chars)
    values: list = []
    for name in param_names:
        if name not in params:
            raise ValueError(f"Missing SQL parameter: {name}")
        values.append(params[name])
    return sql_qmark, values


def collect_named_params(sql: str) -> list[str]:
    """
    Collect named bind params from SQL, ignoring tokens inside single-quoted literals
    and skipping :: casts. Returns unique names in first-seen order.
    """
    names: list[str] = []
    seen = set()
    i = 0
    L = len(sql)
    in_sq = False
    while i < L:
        ch = sql[i]
        if ch == "'":
            in_sq = not in_sq
            i += 1
            while i < L and in_sq:
                if sql[i] == "'":
                    if i + 1 < L and sql[i + 1] == "'":
                        i += 2
                        continue
                    in_sq = False
                    i += 1
                    break
                i += 1
            continue

        if ch == ":" and not in_sq and i + 1 < L and sql[i - 1:i] != ":":
            m = re.match(r":([A-Za-z_][A-Za-z0-9_]*)", sql[i:])
            if m:
                name = m.group(1)
                if name not in seen:
                    names.append(name)
                    seen.add(name)
                i += 1 + len(name)
                continue
        i += 1
    return names


def connect_via_odbc(dsn: str, user: str, password: str):
    if not pyodbc:
        print("You must install the 'pyodbc' package to use --source_odbc", file=sys.stderr)
        sys.exit(1)
    conn_str = f"DSN={dsn};UID={user};PWD={password}"
    return pyodbc.connect(conn_str, autocommit=True)


def connect_via_oracle(tns: str, user: str, password: str):
    if not oracledb:
        print("You must install the 'oracledb' package to use Oracle TNS connections", file=sys.stderr)
        sys.exit(1)
    try:
        return oracledb.connect(user=user, password=password, dsn=tns)
    except Exception as e:
        print(f"Oracle connection failed: {e}", file=sys.stderr)
        raise


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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Universal refdata extract runner.")
    parser.add_argument(
        "snow_user",
        nargs="?",
        default=os.getenv("SNOW_USER") or os.getenv("SNOWFLAKE_USER") or "MFG_PRD_RPT_EXENSIO_USER",
        help="Snowflake user (default from $SNOW_USER/$SNOWFLAKE_USER)",
    )
    parser.add_argument(
        "snow_password",
        nargs="?",
        default=os.getenv("SNOW_PASSWORD") or os.getenv("SNOW_PASS") or os.getenv("SNOWFLAKE_PASSWORD") or "",
        help="Snowflake password (default from $SNOW_PASSWORD/$SNOWFLAKE_PASSWORD)",
    )
    parser.add_argument(
        "snow_sid",
        nargs="?",
        default=os.getenv("SNOW_SID") or os.getenv("SNOWFLAKE_DSN") or "MART_SNOWFLAKE",
        help="Snowflake connection identifier (default from $SNOW_SID/$SNOWFLAKE_DSN)",
    )
    parser.add_argument("--test", "-t", action="store_true", help="Run in test mode (routes outputs to test directories)")
    parser.add_argument("--no-benchmark", action="store_true", help="Disable benchmark JSONL and Oracle logging entirely")
    parser.add_argument("--no-archive", action="store_true", help="Skip creating a .gz archive of the output file")
    parser.add_argument("--account", help="Snowflake account override")
    parser.add_argument("--source_odbc", help="ODBC/DSN style name (uses ODBC when set)")
    parser.add_argument("--source_warehouse", help="Warehouse override")
    parser.add_argument("--source_schema", help="Database and schema DATABASE.SCHEMA")
    parser.add_argument("--warehouse", default="application_prd_wh", help="Snowflake warehouse")
    parser.add_argument("--role", default="APPLICATIONPRD_MFG_CONSUMER_RO", help="Snowflake role")
    parser.add_argument("--secondary_roles", default="ALL", help="Snowflake secondary roles")
    parser.add_argument("--params_json", help="JSON object of SQL parameters")
    parser.add_argument("--params_file", help="Path to JSON file with SQL parameters")
    parser.add_argument("--reference_data_dir", default=os.getenv("REFERENCE_DATA_DIR", ""), help="Output directory")
    parser.add_argument("--archive_dir", default="/apps/exensio_data/archives-yms/reference_data/product", help="Archive directory (gz)")
    parser.add_argument("--log_dir", default="./log", help="Log directory")
    parser.add_argument("--log_file", default="refdata_extract.log", help="Log filename")
    parser.add_argument("--log_level", default="INFO", help="Log level")
    parser.add_argument("--benchmark_log_dir", default="./benchmark", help="Benchmark JSONL log dir")
    parser.add_argument("--benchmark_db_dsn", default=os.getenv("BENCHMARK_DB_DSN") or "exnqa-db.onsemi.com:1740/EXNQA.onsemi.com", help="Oracle DSN for benchmark persistence (optional)")
    parser.add_argument("--benchmark_db_user", nargs="?", const="", default=os.getenv("BENCHMARK_DB_USER"), help="Oracle user for benchmark (default: refdb if flag present)")
    parser.add_argument("--benchmark_db_pass", default=os.getenv("BENCHMARK_DB_PASS"), help="Oracle password for benchmark (optional)")
    parser.add_argument("--output_prefix", default="DWProductMetadata", help="Output file prefix")
    parser.add_argument("--output-file", "-o", help="Direct path to output file (overrides directory/prefix logic)")
    parser.add_argument("--pipeline_name", default=SCRIPT_NAME, help="Pipeline name")
    parser.add_argument("--pipeline_type", default="batch", help="Pipeline type")
    # accept dashed form as an alias for compatibility with existing CLI usage
    parser.add_argument("--pipeline-type", dest="pipeline_type", help=argparse.SUPPRESS)
    parser.add_argument("--environment", help="Environment override (prod/dev/test)")
    parser.add_argument(
        "--header",
        default="PRODUCT|ITEM_TYPE|FAB|FAB_DESC|AFM|PROCESS|FAMILY|PACKAGE|GDPW|WF_UNITS|WF_SIZE|DIE_UNITS|DIE_WIDTH|DIE_HEIGHT|LAST_CHANGED_DATE",
        help="Optional header line to write as first row. (Defaults to standard DW Product fields)"
    )
    parser.add_argument("--oracle_tns", help="Oracle TNS name or connection string (optional)")
    parser.add_argument("--oracle_user", help="Oracle user (optional)")
    parser.add_argument("--oracle_password", help="Oracle password (optional)")
    parser.add_argument("--column_collapse", help="JSON dict for column fallback/collapse: {output_col: [col_indices]}")
    parser.add_argument("--delimiter", default="|", help="Output field delimiter (default: |)")
    parser.add_argument("--pipeline-name", dest="pipeline_name", help=argparse.SUPPRESS)
    return parser.parse_args()


def resolve_password(raw_password: str) -> str:
    if raw_password == "DW_PASSWORD":
        return os.getenv("DW_PASS") or os.getenv("YMS_PASSWORD") or os.getenv("DW_PASSWORD") or ""
    return raw_password


def sanitize_component(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("_")


def load_sources(args: argparse.Namespace) -> list[dict]:
    return [
        {
            "name": args.pipeline_name or "Snowflake DW Product Metadata",
            "snow_user": args.snow_user,
            "snow_password": args.snow_password,
            "snow_sid": args.snow_sid,
            "account": args.account,
            "source_odbc": args.source_odbc,
            "source_warehouse": args.source_warehouse,
            "source_schema": args.source_schema,
            "warehouse": args.warehouse,
            "role": args.role,
            "secondary_roles": args.secondary_roles,
            "reference_data_dir": args.reference_data_dir,
            "archive_dir": args.archive_dir,
            "output_prefix": args.output_prefix,
            "params": {},
            "outputs": [
                {
                    "name": args.output_prefix or "DWProductMetadata",
                    "sql_query": DW_PRODUCT_METADATA_SQL,
                    "output_prefix": args.output_prefix,
                    "reference_data_dir": args.reference_data_dir,
                    "archive_dir": args.archive_dir,
                    "header": args.header,
                    "params": {},
                    "explicit_output_prefix": True,
                }
            ],
            "explicit_output_prefix": True,
        }
    ]


def write_results(output_path, cursor, write_header=True, header_line: str | None = None,
                  column_collapse: dict | None = None, delimiter: str = "|"):
    """
    Write query results to file.
    Supports single-column legacy mode and multi-column output with optional collapse rules.
    """
    tmp_path = output_path + ".tmp"
    rowcount = 0
    header_cols = [c.strip() for c in header_line.split(delimiter)] if header_line else []
    collapse_keys_upper = {str(k).upper() for k in (column_collapse or {}).keys()}
    desc_names = [str(d[0]).strip() for d in (cursor.description or [])]
    desc_index = {name.upper(): i for i, name in enumerate(desc_names)}
    with open(tmp_path, "w", encoding="utf-8", buffering=1) as outf:
        if write_header and header_line:
            outf.write(header_line.rstrip("\n") + "\n")
        for rows in iter(lambda: cursor.fetchmany(cursor.arraysize), []):
            for row in rows:
                # Single column legacy behavior
                if len(row) == 1 and not column_collapse:
                    value = "" if row[0] is None else str(row[0])
                    value = value.replace("'", "").replace('"', "")
                    outf.write(f"{value}\n")
                    rowcount += 1
                else:
                    if column_collapse:
                        # If header is provided, emit all header columns and only apply collapse
                        # rules to mapped columns (e.g. PRODUCT). Otherwise keep legacy collapse-only output.
                        if header_cols:
                            out_fields = []
                            for col_name in header_cols:
                                key = col_name.upper()
                                val = ""
                                if key in collapse_keys_upper:
                                    # find matching collapse rule regardless of key case
                                    rule_key = next(k for k in column_collapse.keys() if str(k).upper() == key)
                                    for idx in column_collapse.get(rule_key, []):
                                        if isinstance(idx, int) and idx < len(row) and row[idx] is not None:
                                            val = str(row[idx])
                                            break
                                elif key in desc_index:
                                    i = desc_index[key]
                                    v = row[i] if i < len(row) else None
                                    val = "" if v is None else str(v)
                                out_fields.append(val.replace("'", "").replace('"', ""))
                            line = delimiter.join(out_fields)
                        else:
                            out_fields = []
                            for out_col, fallbacks in column_collapse.items():
                                val = ""
                                for idx in fallbacks:
                                    if isinstance(idx, int) and idx < len(row) and row[idx] is not None:
                                        val = str(row[idx])
                                        break
                                out_fields.append(val)
                            line = delimiter.join(out_fields)
                    else:
                        fields = [("" if v is None else str(v)).replace("'", "").replace('"', "") for v in row]
                        line = delimiter.join(fields)
                    outf.write(f"{line}\n")
                    rowcount += 1
    os.replace(tmp_path, output_path)
    return rowcount


def acquire_lock(lock_file_path):
    """
    Acquire an exclusive lock using Python's filelock library (cross-platform).
    Returns the FileLock object if successful, exits if another instance is running.
    """
    lock_dir = os.path.dirname(lock_file_path)
    if lock_dir and not os.path.exists(lock_dir):
        os.makedirs(lock_dir, exist_ok=True)
    
    try:
        lock = FileLock(lock_file_path, timeout=0)
        lock.acquire()
        return lock
    except Timeout:
        logging.error(f"Another instance is already running (lock: {lock_file_path})")
        print(f"Another instance is already running (lock: {lock_file_path})", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        logging.error(f"Failed to acquire lock: {e}")
        sys.exit(1)


def release_lock(lock):
    """Release the lock."""
    if lock:
        try:
            lock.release()
        except Exception:
            pass


def main():
    setup_early_logging()
    lock_fh = None
    
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

        # Try to acquire a lock to ensure only one instance of this script runs at a time
        lock_file = f"./log/{SCRIPT_NAME}.lock"
        lock_fh = acquire_lock(lock_file)
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

        # Apply test directory overrides if --test flag is passed
        if args.test:
            args.reference_data_dir = "/export/home/dpower/jag/test_refdata"
            args.archive_dir = "/export/home/dpower/jag/test_refdata/archive"
            args.benchmark_log_dir = "/export/home/dpower/jag/test_refdata/benchmark"
            pipeline_info["environment"] = "test"

        for d in [args.reference_data_dir, args.benchmark_log_dir, args.log_dir]:
            if not d:
                logging.error("Directory argument is empty: %s", d)
                print(f"Directory argument is empty: {d}", file=sys.stderr)
                sys.exit(1)
            os.makedirs(d, exist_ok=True)

        date_code = datetime.now().strftime("%Y%m%d_%H%M%S")

        if not args.source_odbc and not args.account:
            args.source_odbc = (
                os.getenv("SOURCE_ODBC")
                or os.getenv("SNOWFLAKE_DSN")
                or os.getenv("SNOW_SID")
                or args.snow_sid
            )

        base_params = parse_params(args.params_json, args.params_file)
        sources = load_sources(args)
        multi_source = len(sources) > 1

        for source in sources:
            source_name = source.get("name") or source.get("source_odbc") or source.get("account") or "source"
            safe_source_name = sanitize_component(str(source_name)) or "source"
            if not source["source_odbc"] and not source["account"]:
                source["source_odbc"] = (
                    os.getenv("SOURCE_ODBC")
                    or os.getenv("SNOWFLAKE_DSN")
                    or os.getenv("SNOW_SID")
                    or source["snow_sid"]
                )

            for output in source["outputs"]:
                output_name = output.get("name", "output")
                safe_output_name = sanitize_component(str(output_name)) or "output"
                output_prefix = output["output_prefix"]
                if multi_source and not output["explicit_output_prefix"]:
                    output_prefix = f"{output_prefix}-{safe_source_name}"
                elif output_name != "default" and not output["explicit_output_prefix"]:
                    output_prefix = f"{output_prefix}-{safe_output_name}"

                if args.output_file:
                    out_file = args.output_file
                else:
                    out_file = os.path.join(
                        output["reference_data_dir"], f"{output_prefix}-{date_code}.prod"
                    )

                sql_query = output["sql_query"]
                params = dict(base_params)
                if source.get("params"):
                    params.update(source["params"])
                # Ensure optional date params exist so SQL can bind NULL and use fallback window
                params.setdefault("from_date", None)
                params.setdefault("to_date", None)
                if output.get("params"):
                    params.update(output["params"])
                sql_exec, sql_params = (
                    prepare_sql_with_params(sql_query, params) if ":" in sql_query else (sql_query, [])
                )

                start_time = time.time()
                start_local = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                start_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

                logging.info("Running export for %s/%s to %s ...", source_name, output_name, out_file)

                conn = None
                rowcount = 0
                rows_fetched = 0
                rows_kept = 0
                rows_skipped = 0
                try:
                    if not source["snow_user"] or not source["snow_sid"]:
                        logging.error("Missing Snowflake user or DSN/account.")
                        print("Missing Snowflake user or DSN/account.", file=sys.stderr)
                        sys.exit(1)

                    password = resolve_password(source["snow_password"])
                    if not password:
                        logging.error("Password resolution failed for DW_PASSWORD.")
                        print("Password resolution failed for DW_PASSWORD.", file=sys.stderr)
                        sys.exit(1)
                    account = (
                        source["account"]
                        or source["source_odbc"]
                        or os.getenv("SNOWFLAKE_ACCOUNT")
                        or source["snow_sid"]
                    )
                    database = None
                    schema = None
                    if source["source_schema"]:
                        if "." in source["source_schema"]:
                            database, schema = source["source_schema"].split(".", 1)
                        else:
                            schema = source["source_schema"]

                    # Determine connection type: ODBC, Oracle (LOTG/override), or Snowflake connector
                    is_oracle = False
                    oracle_tns = None
                    # Per-source indicator: if source_odbc is the special LOTGDB marker, treat as Oracle
                    if source.get("source_odbc") and str(source.get("source_odbc")).upper().startswith("LOTG"):
                        is_oracle = True
                        oracle_tns = source.get("oracle_tns") or args.oracle_tns or source.get("snow_sid") or args.snow_sid
                    # CLI-level SID indicating LOTGPRD or similar
                    elif args.snow_sid and "LOTG" in str(args.snow_sid).upper():
                        is_oracle = True
                        oracle_tns = args.oracle_tns or args.snow_sid

                    collapse_config = None
                    if output.get("column_collapse") or args.column_collapse:
                        collapse_json = output.get("column_collapse") or args.column_collapse
                        collapse_config = json.loads(collapse_json) if isinstance(collapse_json, str) else collapse_json

                    if source.get("source_odbc") and not is_oracle:
                        conn = connect_via_odbc(source["source_odbc"], source["snow_user"], password)
                        cur = conn.cursor()
                        if source["source_warehouse"]:
                            cur.execute(f"use warehouse {source['source_warehouse']}")
                        if source["source_schema"]:
                            cur.execute(f"use schema {source['source_schema']}")
                        if source["secondary_roles"]:
                            cur.execute(f"use secondary roles {source['secondary_roles']}")
                        if sql_params:
                            cur.execute(sql_exec, sql_params)
                        else:
                            cur.execute(sql_exec)
                        if cur.description is None:
                            logging.error("The executed statement returned no result set.")
                            print("The executed statement returned no result set.", file=sys.stderr)
                            sys.exit(2)
                        cur.arraysize = 10000
                        rowcount = write_results(
                            out_file,
                            cur,
                            write_header=True,
                            header_line=output.get("header") or args.header,
                            column_collapse=collapse_config,
                            delimiter=output.get("delimiter") or args.delimiter,
                        )
                        # Align diagnostics
                        rows_fetched = rowcount 
                        rows_kept = rowcount
                        rows_skipped = 0
                        cur.close()
                    elif is_oracle and oracle_tns:
                        # Oracle connection
                        # Handle LOTGDB_USER special-case similar to get_subcon_lot_refdata_rc10.py
                        u = source.get("snow_user") or args.snow_user
                        p = source.get("snow_password") or args.snow_password
                        if u == "LOTGDB_USER":
                            oracle_user = "LOTG_READ"
                            oracle_pwd = os.getenv("LOTG_PASS") or "prdlotgr"
                        else:
                            oracle_user = source.get("oracle_user") or args.oracle_user or u
                            oracle_pwd = source.get("oracle_password") or args.oracle_password or p
                        conn = connect_via_oracle(oracle_tns, oracle_user, oracle_pwd)
                        cur = conn.cursor()
                        # Oracle uses named binds, not qmark positional binds.
                        oracle_sql = sql_query.strip()
                        # Script files often end with ';' or '/' (SQL*Plus style), which oracledb
                        # treats as invalid SQL text and can raise ORA-00933.
                        oracle_sql = re.sub(r"[\s;]+$", "", oracle_sql)
                        if oracle_sql.endswith("/"):
                            oracle_sql = oracle_sql[:-1].rstrip()

                        oracle_bind_names = collect_named_params(oracle_sql)
                        if oracle_bind_names:
                            oracle_params = {k: params.get(k) for k in oracle_bind_names}
                            cur.execute(oracle_sql, oracle_params)
                        else:
                            cur.execute(oracle_sql)
                        if cur.description is None:
                            logging.error("The executed statement returned no result set.")
                            print("The executed statement returned no result set.", file=sys.stderr)
                            sys.exit(2)
                        cur.arraysize = 10000
                        rowcount = write_results(
                            out_file,
                            cur,
                            write_header=True,
                            header_line=output.get("header") or args.header,
                            column_collapse=collapse_config,
                            delimiter=output.get("delimiter") or args.delimiter,
                        )
                        # Align diagnostics
                        rows_fetched = rowcount 
                        rows_kept = rowcount
                        rows_skipped = 0
                        cur.close()
                    else:
                        conn = connect_via_connector(
                            account=account,
                            user=source["snow_user"],
                            password=password,
                            warehouse=source["source_warehouse"] or source["warehouse"],
                            role=source["role"],
                            database=database,
                            schema=schema,
                        )
                        with conn.cursor() as cur:
                            if source["source_warehouse"]:
                                cur.execute(f"use warehouse {source['source_warehouse']};")
                            if source["source_schema"]:
                                cur.execute(f"use schema {source['source_schema']};")
                            if source["secondary_roles"]:
                                cur.execute(f"use secondary roles {source['secondary_roles']};")
                            if sql_params:
                                cur.execute(sql_exec, sql_params)
                            else:
                                cur.execute(sql_exec)
                            if cur.description is None:
                                logging.error("The executed statement returned no result set.")
                                print("The executed statement returned no result set.", file=sys.stderr)
                                sys.exit(2)
                            
                            cur.arraysize = 10000
                            rowcount = write_results(
                                out_file,
                                cur,
                                write_header=True,
                                header_line=output.get("header") or args.header,
                                column_collapse=collapse_config,
                                delimiter=output.get("delimiter") or args.delimiter,
                            )
                            # Align diagnostics: for this simple extract, handled rows and written rows are same
                            rows_fetched = rowcount 
                            rows_kept = rowcount
                            rows_skipped = 0 # No active filtering in this script yet
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
                    logging.info("Export succeeded: %s (%s rows)", out_file, rowcount)
                    logging.info("Elapsed time: %s (%.3f seconds)", human_elapsed, elapsed)
                    if output["archive_dir"]:
                        archived_path = archive_and_compress(out_file, output["archive_dir"])
                        if archived_path:
                            archived_file = archived_path
                else:
                    logging.error("Export failed or produced empty file.")
                    sys.exit(2)

                out_files = [{"path": os.path.abspath(out_file), "rows": rowcount}]
                if archived_file != "NA":
                    out_files.append({"path": os.path.abspath(archived_file), "rows": rowcount})

                stats = {
                    "start_local": start_local,
                    "end_local": end_local,
                    "start_utc": start_utc,
                    "end_utc": end_utc,
                    "elapsed_seconds": round(elapsed, 3),
                    "elapsed_human": human_elapsed,
                    "output_file": os.path.abspath(out_file),
                    "rowcount": rowcount,
                    # Align with models.py: rows_extracted = rows from source, rows_written = rows to output
                    "rows_extracted": rows_fetched,
                    "rows_written": rows_kept,
                    "rows_fetched": rows_fetched,
                    "rows_kept": rows_kept,
                    "rows_skipped": rows_skipped,
                    "total_files": len(out_files),
                    "out_files": out_files,
                    "log_file": os.path.join(args.log_dir, args.log_file),
                    "archived_file": archived_file if archived_file != "NA" else None,
                    "pid": os.getpid(),
                    "date_code": date_code,
                    "pipeline_name": pipeline_info["pipeline_name"],
                    "script_name": pipeline_info["script_name"],
                    "pipeline_type": pipeline_info["pipeline_type"],
                    "environment": pipeline_info["environment"],
                    # Optional metadata fields for future extensibility
                    "source_name": source_name if source_name != "default" else "Snowflake DW Product Metadata",
                    "output_name": os.path.basename(out_file),
                }
                try:
                    log_benchmark_jsonl(args.benchmark_log_dir, stats)
                    
                    # Write to Oracle DB if credentials provided
                    if args.benchmark_db_dsn:
                        # Handle the nargs='?' pattern: if --benchmark_db_user is present but empty, use defaults
                        oracle_user = args.benchmark_db_user if args.benchmark_db_user is not None else None
                        oracle_pass = args.benchmark_db_pass
                        log_benchmark_to_oracle(stats, args.benchmark_db_dsn, oracle_user, oracle_pass)

                    logging.info("Benchmark log appended to %s/benchmark.jsonl", args.benchmark_log_dir)
                except Exception as b_err:
                    logging.warning("Non-critical failure while writing benchmark stats: %s", b_err)

        logging.info("----- Job finished -----")
    finally:
        release_lock(lock_fh)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        logging.critical("Uncaught error: %s", e, exc_info=True)
        print(f"Script failed: {e}", file=sys.stderr)
        sys.exit(3)
