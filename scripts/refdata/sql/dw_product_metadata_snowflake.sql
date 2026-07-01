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