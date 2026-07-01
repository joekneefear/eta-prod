#!/usr/bin/env perl_db
#$Id

# 1. Extract wafer to slice mapping from WorkStream lot attributes
# 2. Extracts from refdb.on_slice table to get ONHD and CZ slice + puck information
# 3. Merges wafer to slice with slice + puck to create Wafer-level genealogy tracking to load to exensio
# 4. Writes reference table loading file with wafer to slice data included

# MODIFICATION HISTORY:
# WHEN        WHO             WHAT
# ----------- --------------- --------------------------------------------------------------------------------
# 10-Mar-2022 S. Boothby      Created.
# 03-May-2022 S. Boothby      Fixed epi_info query to check for BK epi sourced from WKS raw SiC inventory
# 04-Aug-2022 S. Boothby      Added ecofa DB as data source for turnkey epi and SiC puck and product information
#                             Fixed several issues with tracking to epi and SiC product and supplier
#                             Changed output format and file extensions: 
#                             fab2slice(f2s)->fab2puck(f2p)
#                             slice2fab(s2f)->puck2fab(p2f)
#                             epi2slice(e2s)->epi2puck(e2p)
#                             slice2epi(s2e)->Discontinued (same as epi2puck)
# 26-Dec-2022 S. Boothby      Fixed issue with SQL that occurred after upgrade to Oracle 12 from 11.
# 07-Apr-2023 S. Boothby      Multiple resutls sometimes returned for an epi slice due to lot existing in multiple facilities
# 20-Sep-2023 jgarcia         added ORDERED hint 
# 25-Apr-2024 S. Boothby      Performance improvements and changes to support 200mm SiC wafers.
#                             Account for deleted lot attributes which is how BK corrects frontside to backside mapping
#                             Fixed bug in EPI2PUCK retrieval for CZ which excluded vendor wafers
# 18-Jul-2024 S. Boothby      
# 23-Jul-2024 S. Boothby      Bug fixes: Source year century sometimes = 00, epi start date incorrectly formatted,set NA value for null.
# 27-Feb-2025 S. Boothby      Reduced search for fab starts to CRLT only (not including splits)
#                             Performance tweaks to CZ2 queries to reduce run time
#                             Only count lot deletes if they are done manually; e.g., not by purging data which is identified by COMETS delete category
# 03-Mar-2025 S. Boothby      Handle TERMed or scrapped CZ TORRENT transactions for epi retrievals
# 05-Mar-2025 S. Boothby      Exclude CZ2 epi material from eCofA epi lookup
#                             Start day starts at midnight of Nth day ago and end day ends at 23:59:59 of the end day.
#                             Corrected BK epi SQL to account for epi material moved to BBLS facility.
# 24-Apr-2025 S. Boothby      Fix SQL error in conversion of slice order to integer
# 29-Apr-2025 S. Boothby      Added options slicelist and lotlist to enable searching for specific lots/slices
#                             Added option to specify eCofA schema name for upcoming migration.
# 09-May-2025 S. Boothby      Added USEDOLDTRACKING option to apply original wafer naming/tracking algorithm when searching wafers.
#                             Preferentially get epi info from eCofA if fab trace indicates BK as the epi supplier.
# 12-Aug-2025 S. Boothby      Get lot ID at epi reactor when possible.  If epi defect scan only, return epi scan lot ID.
# 28-Aug-2028 S. Boothby      Handle lots transferred to S1 facility.  Update mismatching fab wafers when found in REFDB.
use strict;
use File::Copy;
use FindBin::libs;
use Getopt::Long;
use DBI;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename fileparse/;
use POSIX qw(strftime);
use DateTime::Format::Strptime;
use PDF::Log;
use PDF::DpLoad;
use PDF::DAO;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Formatter;
use v5.10;

sub get_eCofA_sliceInfo {
   my ($ecoaschema, $wafer_scribe_id, $global_wafer_id) = @_;
   my $sqlStr = "";
   my $filter = "";
   my $lot_filter = "";
   if (length($wafer_scribe_id) > 0)
   {
      $filter = "w1.WAFER_SCRIBE_ID = '$wafer_scribe_id'";
      $lot_filter = "AND " . $filter;
   }
   elsif (length($global_wafer_id) > 0)
   {
      $filter = "(w1.GLOBAL_WAFER_ID = '$global_wafer_id' or w1.WAFER_SCRIBE_ID = '$global_wafer_id')";
      $lot_filter = "AND " . $filter;
   }

   $sqlStr = "
select s.WAFER_SCRIBE_ID
     , s.GLOBAL_WAFER_ID
     , case when r.VENDOR_SITE = 'CZ2' or s.WAFER_SCRIBE_ID like 'CE_____-__' then ' ' else r.BOULE_ID end as PUCK_ID
     , el.VENDOR_LOT_ID       as EPI_LOT
     , e.SLOT                 as EPI_SLOT
     , to_char(el.MFG_DATE, 'YYYYMMDD') as EPI_START_DATE
     , e.PART_NUMBER          as EPI_PARTNAME
     , el.VENDOR_SITE         as EPI_SUPPLIERID
     , r.PART_NUMBER          as RAW_PARTNAME
     , case when r.PART_NUMBER = 'SIC6S002' then 'CREE'
            when r.PART_NUMBER = 'SIC6S003' then 'SICRYSTL'
            when r.PART_NUMBER = 'SIC6S011' then 'SICC'
            when r.PART_NUMBER = 'SIC6S016' then 'SYNLIGHT'
            else r.VENDOR_SITE 
       end                    as RAW_SUPPLIERID
     , r.WAFER_SLICE_POSITION as RAW_SLICE_ORDER
     , count(*) as qty
from $ecoaschema.wafer s 
left join $ecoaschema.WAFER e on s.WAFER_SCRIBE_ID = e.WAFER_SCRIBE_ID and EXISTS (select 1 from $ecoaschema.wafer w
              join $ecoaschema.rawsilicon_lot_parameter lp on w.RAWSILICON_LOT_ID = lp.RAWSILICON_LOT_ID 
              join $ecoaschema.rawsilicon_param_map lpm on lp.PARAM_MAP_ID = lpm.PARAM_MAP_ID
              where e.RAWSILICON_LOT_ID = lp.RAWSILICON_LOT_ID and lpm.VENDOR_PARAM_NAME like '%EPI%')
left join $ecoaschema.RAWSILICON_LOT el on e.RAWSILICON_LOT_ID = el.RAWSILICON_LOT_ID
left join (select * 
           from (select w1.wafer_scribe_id, w1.wafer_slice_position, w1.part_number, w1.boule_id, rl.vendor_site
                      , dense_rank() over (partition by wafer_scribe_id order by date_processed desc) as dr
                 from $ecoaschema.WAFER w1 
                 join $ecoaschema.RAWSILICON_LOT rl on w1.RAWSILICON_LOT_ID = rl.RAWSILICON_LOT_ID
                 where NOT EXISTS (select 1 from $ecoaschema.rawsilicon_lot_parameter lp
                                   join $ecoaschema.rawsilicon_param_map lpm on lp.PARAM_MAP_ID = lpm.PARAM_MAP_ID
                                   where w1.RAWSILICON_LOT_ID = lp.RAWSILICON_LOT_ID and lpm.VENDOR_PARAM_NAME like '%EPI%' )
                 $lot_filter
           )where dr = 1) r on s.WAFER_SCRIBE_ID = r.WAFER_SCRIBE_ID
where s.WAFER_SCRIBE_ID in (select WAFER_SCRIBE_ID from $ecoaschema.wafer w1
                            join $ecoaschema.rawsilicon_lot l1 on w1.RAWSILICON_LOT_ID = l1.RAWSILICON_LOT_ID
                            where $filter)
-- Exclude epi from CZ2, get it from TORRENT database 
-- Need CZ2 info by slice to get global wafer ID.  Data returned for CZ2-sourced EPI should only use the GWID returned.
--  and coalesce(el.VENDOR_SITE,'UNKNOWN') != 'CZ2'
group by s.WAFER_SCRIBE_ID, s.GLOBAL_WAFER_ID
     , case when r.VENDOR_SITE = 'CZ2' or s.WAFER_SCRIBE_ID like 'CE_____-__' then ' ' else r.BOULE_ID end
     , el.VENDOR_LOT_ID
     , e.SLOT
     , to_char(el.MFG_DATE, 'YYYYMMDD')
     , e.PART_NUMBER
     , el.VENDOR_SITE
     , r.PART_NUMBER
     , case when r.PART_NUMBER = 'SIC6S002' then 'CREE'
            when r.PART_NUMBER = 'SIC6S003' then 'SICRYSTL'
            when r.PART_NUMBER = 'SIC6S011' then 'SICC'
            when r.PART_NUMBER = 'SIC6S016' then 'SYNLIGHT'
            else r.VENDOR_SITE 
       end
     , r.WAFER_SLICE_POSITION
order by s.WAFER_SCRIBE_ID
";

#   INFO("$sqlStr");

   return $sqlStr;
}

sub get_eCofA_sliceInfoByDate {
   my ($ecoaschema, $startD, $endD, $sliceL) = @_;
   my $sqlStr = "";

   $sqlStr = "
select el.VENDOR_SITE         as FACILITY
     , case when r.VENDOR_SITE = 'CZ2' or s.WAFER_SCRIBE_ID like 'CE_____-__' then ' ' else r.BOULE_ID||'.S' end as SOURCE_LOT 
     , s.WAFER_SCRIBE_ID      as WAFER
     , 0                      as ATTR_NUMBER
     , e.PART_NUMBER          as FAB_PRODUCT
     , ' '                    as LOT_TYPE
     , to_char(el.MFG_DATE, 'YYYYMMDD') as LOT_START_DATE /* EPI_START_DATE */
     , s.WAFER_SCRIBE_ID      as SIC_SLICE
     , s.GLOBAL_WAFER_ID
     , case when r.PART_NUMBER = 'SIC6S002' then 'CREE'
            when r.PART_NUMBER = 'SIC6S003' then 'SICRYSTL'
            when r.PART_NUMBER = 'SIC6S011' then 'SICC'
            when r.PART_NUMBER = 'SIC6S016' then 'SYNLIGHT'
            else r.VENDOR_SITE 
       end                    as RAW_SIC_SUPPLIER
     , el.VENDOR_LOT_ID       as EPI_LOT
     , e.PART_NUMBER          as EPI_PRODUCT
     , e.SLOT                 as EPI_SLOT
     , 0                      as EPI_ATTR_NUMBER 
     , to_char(el.MFG_DATE, 'YYYYMMDD') as EPI_START_DATE /* EPI_START_DATE */
     , el.VENDOR_SITE         as EPI_SUPPLIER
     , case when r.VENDOR_SITE = 'CZ2' or s.WAFER_SCRIBE_ID like 'CE_____-__' then ' ' else r.BOULE_ID end       as PUCK_ID
     , r.PART_NUMBER          as RAW_PARTNAME
     , r.WAFER_SLICE_POSITION as RAW_SLICE_ORDER
     , count(*) as qty
from $ecoaschema.wafer s 
join $ecoaschema.WAFER e on s.WAFER_SCRIBE_ID = e.WAFER_SCRIBE_ID and EXISTS (select 1 from $ecoaschema.wafer w
              join $ecoaschema.rawsilicon_lot_parameter lp on w.RAWSILICON_LOT_ID = lp.RAWSILICON_LOT_ID 
              join $ecoaschema.rawsilicon_param_map lpm on lp.PARAM_MAP_ID = lpm.PARAM_MAP_ID
              where e.RAWSILICON_LOT_ID = lp.RAWSILICON_LOT_ID and lpm.VENDOR_PARAM_NAME like '%EPI%')
join $ecoaschema.RAWSILICON_LOT el on e.RAWSILICON_LOT_ID = el.RAWSILICON_LOT_ID
join (select * 
           from (select w1.wafer_scribe_id, w1.wafer_slice_position, w1.part_number, w1.boule_id, rl.vendor_site
                      , dense_rank() over (partition by wafer_scribe_id order by date_processed desc) as dr
                 from $ecoaschema.WAFER w1 
                 join $ecoaschema.RAWSILICON_LOT rl on w1.RAWSILICON_LOT_ID = rl.RAWSILICON_LOT_ID
                 where NOT EXISTS (select 1 from $ecoaschema.rawsilicon_lot_parameter lp
                                   join $ecoaschema.rawsilicon_param_map lpm on lp.PARAM_MAP_ID = lpm.PARAM_MAP_ID
                                   where w1.RAWSILICON_LOT_ID = lp.RAWSILICON_LOT_ID and lpm.VENDOR_PARAM_NAME like '%EPI%' )
           )where dr = 1) r on s.WAFER_SCRIBE_ID = r.WAFER_SCRIBE_ID
where s.WAFER_SCRIBE_ID in (select WAFER_SCRIBE_ID from $ecoaschema.wafer w1
                            join $ecoaschema.rawsilicon_lot l1 on w1.RAWSILICON_LOT_ID = l1.RAWSILICON_LOT_ID
                            where POLYTYPE is not null ";
if (defined($sliceL) && length($sliceL) > 1)
{
   $sqlStr= $sqlStr . "and WAFER_SCRIBE_ID in ($sliceL))";
}
else
{
   $sqlStr= $sqlStr . "and l1.DATE_RECEIVED between trunc(sysdate + (1*$startD)) and trunc(sysdate + (1*$endD)) + 1)";
}
$sqlStr= $sqlStr . "
-- Exclude epi from CZ2, got from TORRENT database already
  and el.VENDOR_SITE != 'CZ2'
group by el.VENDOR_SITE
     , case when r.VENDOR_SITE = 'CZ2' or s.WAFER_SCRIBE_ID like 'CE_____-__' then ' ' else r.BOULE_ID||'.S' end
     , s.WAFER_SCRIBE_ID, e.PART_NUMBER
     , to_char(el.MFG_DATE, 'YYYYMMDD')
     , s.WAFER_SCRIBE_ID, s.GLOBAL_WAFER_ID
     , case when r.PART_NUMBER = 'SIC6S002' then 'CREE'
            when r.PART_NUMBER = 'SIC6S003' then 'SICRYSTL'
            when r.PART_NUMBER = 'SIC6S011' then 'SICC'
            when r.PART_NUMBER = 'SIC6S016' then 'SYNLIGHT'
            else r.VENDOR_SITE
       end
     , el.VENDOR_LOT_ID, e.PART_NUMBER, e.SLOT
     , to_char(el.MFG_DATE, 'YYYYMMDD') 
     , el.VENDOR_SITE
     , case when r.VENDOR_SITE = 'CZ2' or s.WAFER_SCRIBE_ID like 'CE_____-__' then ' ' else r.BOULE_ID end
     , r.PART_NUMBER, r.WAFER_SLICE_POSITION
order by s.WAFER_SCRIBE_ID
";
#   INFO("$sqlStr");

   return $sqlStr;
}

sub getEpiOrFabTraceSQL {
   my ($sqlType, $startD, $endD, $sliceL, $lotL) = @_;
   my $sqlStr = "";
   my $facilities = "";
   my $business_units = "";
   my $epiFacilityJoin = "";
   my $select_facility_a = "";
   my $select_facility_wl = "";
   if ($sqlType eq "epi")
   {
      $select_facility_a  = "case when a.facility = 'BBLS' then 'FBEPI' else a.facility end";
      $select_facility_wl = "case when wl.facility = 'BBLS' then 'FBEPI' else wl.facility end";
      $facilities = "'FM4045', 'FBEPI', 'BBLS'";
      $business_units = "'KLMI1', 'MEMI1'";
      $epiFacilityJoin = "and ei.facility = $select_facility_wl";
   } else
   {
      # Assume fab
      #$select_facility_a  = "a.facility";
      $select_facility_a  = "case when a.facility = 'S1' and a.lot_number like 'KG%' then 'FB6' 
        when a.facility = 'S1' and a.lot_number like 'KH%' then 'FB8'
        when a.facility = 'S1' then 'FBEPI'
        else a.facility end";
      $select_facility_wl = "wl.facility";
      $facilities = "'FB6','FB8','S1'";
      $business_units = "'KLMI1'";
   }

   $sqlStr = "with ";
   if (defined($sliceL) && length($sliceL) > 1)
   {
      $sqlStr .= "starts as (select /*+ MATERIALIZE INDEX(l WKSM_WIPLOT_IDX01) */ distinct a.business_unit
 , case when a.facility = 'S1' and a.lot_number like 'KG%' then 'FB6' 
        when a.facility = 'S1' and a.lot_number like 'KH%' then 'FB8'
        when a.facility = 'S1' then 'FBEPI'
        else a.facility end as facility
, a.lot_number
from biwmes.wksm_lotattributes a
join biwmes.wksm_wiplot l on a.facility = l.facility and a.LOT_NUMBER = l.LOT_NUMBER and a.business_unit = l.business_unit
where (a.attr_number between 3051 and 3074 or a.attr_number between 801 and 825) 
  and not (a.lot_del_flag = 'Y' and l.delete_category not in ( 'COMETS', '2904', '3005', '3004'))
  and a.alp_attr_val in ($sliceL)
  and a.facility in ($facilities)
  and a.business_unit in ($business_units))
,";
   }
   $sqlStr .= "attrs as 
(
select /*+ MATERIALIZE */ unique a.business_unit, $select_facility_a as facility, a.lot_number
";
  if (defined($sliceL) && length($sliceL) > 1)
  {
     $sqlStr .= "from starts a
";
  }
  else
  {
     $sqlStr .= "from biwmes.wksm_lotattributes a
";
  }
  $sqlStr .="join biwmes.wksm_wiplth lth on a.lot_number = lth.lot_number and $select_facility_a = case when lth.facility_old = 'MPS' then 'FM4045' else lth.facility_old end ";
  if (defined($sliceL) && length($sliceL) > 1)
  {
     $sqlStr .= "join starts s on a.lot_number = s.lot_number ";
  }
  $sqlStr .= "where lth.TRANS = 'CRLT'
";
  if (!(defined($sliceL) && length($sliceL) > 1))
  {
     $sqlStr .= " and a.attr_number in (761,3050)
";
  }
  if (defined($lotL) && length($lotL) > 1)
  {
      $sqlStr = $sqlStr . " and a.lot_number in ($lotL)
";
  }
  elsif ((defined($sliceL) && length($sliceL) > 1))
  {
      $sqlStr .= "and not exists(select 1 from biwmes.wksm_wiplot wl where a.business_unit = wl.business_unit and a.lot_number = wl.lot_number and wl.deleted = 'Y' and wl.DELETE_CATEGORY not in ( 'COMETS', '2904', '3005', '3004'))";
  }
  else 
  {
      $sqlStr = $sqlStr . " and lth.transaction_date_time between trunc(sysdate + (1*$startD)) and trunc(sysdate + (1*$endD))+1
  and lth.lot_hist_seq_date between TO_CHAR(trunc(sysdate + (1*$startD)), 'YYYYMMDD') and TO_CHAR(trunc(sysdate)+1 + (1*$endD), 'YYYYMMDD')
  and a.alp_attr_val in ('Y', 'y')
  and not (a.LOT_DEL_FLAG = 'Y' and exists(select 1 from biwmes.wksm_wiplot wl where a.business_unit = wl.business_unit and a.lot_number = wl.lot_number and wl.DELETE_CATEGORY not in ( 'COMETS', '2904', '3005', '3004'))) 
  /* Use a.facility in ('FB6') for fab-to-epi and f.facility in ('FM4045', 'FBEPI') for just epi */
  and lth.facility_old in ($facilities)
  and lth.business_unit in ($business_units)
";
  }
  $sqlStr .= " and exists(select 1 from biwmes.wksm_wiplot l where a.business_unit = l.business_unit and a.lot_number = l.lot_number )
)
/*
** Info determines the mapping of slice ID to wafer number for all lots identified in the ATTRS subquery.
*/ 
, info as
(
SELECT /*+ MATERIALIZE */ unique a.business_unit, $select_facility_a as facility, a.lot_number /******* CHECK *******/
, regexp_substr(n.attr_name, '[0-9][0-9]', 1, 1) as slot
, a.attr_number
, case when regexp_like(a.alp_attr_val, '^CE..\\d+\$') then substr(a.alp_attr_val, 1, 7)||'-'||substr(a.alp_attr_val, 8, 100) 
       else a.alp_attr_val end as sic_slice
, case when length(regexp_replace(a.alp_attr_val, '-', '', 1, 0)) < 11 then regexp_replace(a.alp_attr_val, '-', '', 1, 0) else substr(regexp_replace(a.alp_attr_val, '-', '', 1, 0),1,10) end as adjusted_slice
/* If a slice appears multiple times, take only the first one */
, dense_rank() over (partition by a.facility, a.lot_number, a.alp_attr_val order by a.attr_number) as slice_rank
FROM biwmes.wksm_lotattributes a
JOIN attrs src on $select_facility_a = src.facility and a.lot_number = src.lot_number and a.business_unit = src.business_unit 
JOIN biwmes.wksm_attrname n ON $select_facility_a = n.facility AND a.attr_number = n.attr_number
WHERE REGEXP_LIKE(n.attr_name, '^(EPI SLOT |)[0-9][0-9]\$') ";
  if (defined($sliceL) && length($sliceL) > 1)
  {
     $sqlStr .= " AND case when regexp_like(a.alp_attr_val, '^CE..\\d+\$') then substr(a.alp_attr_val, 1, 7)||'-'||substr(a.alp_attr_val, 8, 100)
       else a.alp_attr_val end in ($sliceL)";
  }
  $sqlStr .= "AND a.BUSINESS_UNIT in ($business_units) and a.facility in ($facilities)
)
, epi_info1 as
(
select /*+ MATERIALIZE INDEX(a2 WKSM_LOTATTRIBUTES_IDX01) INDEX(a3 WKSM_LOTATTRIBUTES_IDX01) INDEX(a4 WKSM_LOTATTRIBUTES_IDX01) INDEX(wl WKSM_WIPLOT_IDX02)*/
 unique $select_facility_wl as facility, a.lot_number, wl.prod as epi_product, a.alp_attr_val as sic_slice
, a.attr_number as epi_attr_number
, regexp_substr(n.attr_name, '[0-9][0-9]', 1, 1) as epi_slot
, wl.creation_date as epi_start_date
, case when a.facility in ('FM4045', 'FM3000') then 'UWB'
       when a.facility not in ('FB6', 'FB8','S1') 
        and not exists (select 1 from biwmes.wksm_wiplth wl
                        join biwmes.wksm_route r on wl.facility_old = r.facility and wl.route_old = r.route
                        where wl.facility_old = case when a.facility = 'BBLS' then 'FBEPI' else a.facility end and wl.lot_number = a.lot_number
                          and wl.facility_old = 'FBEPI' and r.DESCRIPTION like '%EXTERNAL%EPI%') then 'KRJ'
       else coalesce(a4.alp_attr_val, a3.alp_attr_val, a2.alp_attr_val) end as epi_location
, dense_rank() over (partition by a.alp_attr_val order by wl.creation_date desc, a.lot_number desc) as ei_rank
from biwmes.wksm_lotattributes a
join info i on a.alp_attr_val = i.sic_slice
JOIN biwmes.wksm_attrname n ON a.business_unit = n.business_unit and $select_facility_a = n.facility AND a.attr_number = n.attr_number
JOIN biwmes.wksm_wiplot wl on a.lot_number = wl.lot_number
LEFT JOIN biwmes.wksm_lotattributes a2 on a.business_unit = a2.business_unit and a.facility = a2.facility and a.lot_number = a2.lot_number  and a2.attr_number = 2011
LEFT JOIN biwmes.wksm_lotattributes a3 on a.business_unit = a3.business_unit and a.facility = a3.facility and regexp_replace(a.alp_attr_val, '-', '') = a3.lot_number  and a3.attr_number = 1011
LEFT JOIN biwmes.wksm_lotattributes a4 on a.business_unit = a4.business_unit and a.facility = a4.facility and a.lot_number = a4.lot_number  and a4.attr_number = 1011
where a.facility in ( 'FBEPI', 'FM4045', 'BBLS') and wl.business_unit in ('KLMI1', 'MEMI1')
and i.slice_rank = 1
and REGEXP_LIKE(n.attr_name, '^(EPI SLOT |)[0-9][0-9]\$')
  /* Exclude Silicon Scanned Substrates (part type SPO) */
 /* and not exists (select 1 from biwmes.wksm_wiplot l where l.business_unit = 'KLMI1' and a.lot_number = l.lot_number and l.prod like '%-SPO')*/
)
, epi_info as 
(
select /*+ MATERIALIZE */ a.* 
from epi_info1 a
-- exclude lots that were scrapped or bought out: can tell if wafer qty goes to 0 on anything other than a ship transaction
-- Maine
where not (a.facility = 'FM4045' and exists(select /*+ INDEX(wlth WKSM_WIPLTH_IDX01) */ 1 from biwmes.wksm_wiplth wlth where a.lot_number = wlth.lot_number and a.facility = wlth.facility_old and wlth.quantity_1_new = 0 and trans not in ( 'SHLT')))
-- Bucheon
  and not (a.facility = 'FBEPI' and exists(select /*+ INDEX(wlth WKSM_WIPLTH_IDX01) */ 1 from biwmes.wksm_wiplth wlth where a.lot_number = wlth.lot_number and a.facility = wlth.facility_old and wlth.quantity_1_new = 0 and not (trans in ( 'SHLT', 'MRLT') or (trans in 'TRLT' and a.facility = 'FBEPI'))))
)
, nonprod_epi as
(
select /*+ MATERIALIZE INDEX(wl WKSM_WIPLOT_IDX01 */ unique 
       i.lot_number
     , i.sic_slice
     , i.adjusted_slice
     , wl.OWNER as LOT_TYPE
     , wl.PROD  as PRODUCT
     , wl.CREATION_DATE as epi_start_date
     , case when regexp_like(a.alp_attr_val, '^CE..\\d+\$') then substr(a.alp_attr_val, 1, 7)||'-'||substr(a.alp_attr_val, 8, 100) 
       else a.alp_attr_val end as epi_sic_slice
     , regexp_substr(n.attr_name, '[0-9][0-9]', 1, 1) as epi_slot
     , a.attr_number as epi_attr_number
     , case when not exists (select 1 from biwmes.wksm_wiplth wl
                        join biwmes.wksm_route r on wl.facility_old = r.facility and wl.route_old = r.route
                        where wl.lot_number = l.lot_number
                          and wl.facility_old = 'FBEPI' and r.DESCRIPTION like '%EXTERNAL%EPI%') then 'KRJ'
       when l.facility in ('FM4045') then 'UWB' 
       else coalesce(l.alp_attr_val, 'KRJ')  end as EPI_LOCATION
from info i
JOIN biwmes.wksm_wiplot wl on i.adjusted_slice = wl.lot_number
LEFT JOIN biwmes.wksm_lotattributes a on wl.facility = a.facility and wl.lot_number = a.lot_number and a.attr_number between 3051 and 3074
LEFT JOIN biwmes.wksm_attrname n on $select_facility_a = n.facility and a.attr_number = n.attr_number
left join biwmes.wksm_lotattributes l on wl.facility = l.facility and wl.lot_number = l.lot_number and l.attr_number = 1011
WHERE wl.FACILITY not in ( 'FB6', 'FB8','S1' )
  and wl.BUSINESS_UNIT in ('KLMI1', 'MEMI1')
)
/* BK is transacting nonprod 200mm SiC epi without setting lot attributes */
, bk_epi_lots_without_attributes as
(
 select /*+ MATERIALIZE INDEX(wl WKSM_WIPLOT_IDX02)*/ unique wl.facility as facility
, wl.lot_number
, wl.prod as epi_product
, i.sic_slice as sic_slice
, 3051 as epi_attr_number
, '01' as epi_slot
, wl.creation_date as epi_start_date
, 'KRJ' as epi_location
, dense_rank() over (partition by i.sic_slice order by wl.creation_date, wlth.transaction_date_time desc) as ei_rank
from info i
join biwmes.wksm_wiplot wl on i.adjusted_slice = wl.lot_number
join biwmes.wksm_wiplth wlth on wl.lot_number = wlth.lot_number and wlth.facility_old = wl.facility and wl.business_unit = wlth.business_unit
join biwmes.wksm_ntcent e on wlth.facility_old = e.facility and wlth.EQUIPMENT_ID = e.ENTITY and e.USER_DEF_SMALL_DATA_1 = 'EPI_REACTOR'
where wl.facility = 'FBEPI' and wl.business_unit = 'KLMI1' --and regexp_like(wl.prod, '^(6|8)S.*-E(6|8)X\$')
  and wlth.trans = 'LVNE' and wlth.\"COMMENT\" like 'RECIPE_ID%'
)
/*
** WALK searches the from/to genealogy backward to find the source/starting lot in the fab.  The source lot will be used to build the exensio source lot ID
*/
, walk as
(select /*+ MATERIALIZE  INDEX(wl WKSM_WIPLTH_IDX01)*/ facility_old as facility, lot_number, from_to_lot, transaction_date_time, LEVEL as lvl, connect_by_root lot_number as start_lot
from biwmes.wksm_wiplth wl
where trans = 'SPLT'
  and from_to = 'F'
connect by nocycle prior facility_old = facility_old and prior from_to_lot = lot_number and prior transaction_date_time > transaction_date_time and trans = 'SPLT' and from_to = 'F'
start with exists (select 1 from info a where a.facility = wl.facility_old and a.lot_number = wl.lot_number)
)
/*
** Exensio source_lot is source lot ID plus an underscore, then two-digit wafer number prefixed by 0 if < 9. 
*/
, source_lot as
(select /*+ MATERIALIZE */ distinct start_lot, from_to_lot as src_lot
from (select start_lot, from_to_lot, dense_rank() over (partition by start_lot order by transaction_date_time) as dr from walk)
where dr = 1
)
/*
** Output is mapping of exensio wafer ID to slice ID, plus the vendor ID and puck lot ID from CZ.
** Rules for translating slice ID to CZ lot ID are in the CASE statement.
*/
, changed_wafers as 
(
select distinct a.business_unit
         , a.facility
         , a.lot_number
         , a.lot_number||case when n.attr_name is not null then '_' else null end||regexp_substr(n.attr_name, '[0-9][0-9]', 1, 1) as changed_wafer
         , a.alp_attr_val
           from biwmes.wksm_lotattributes a
left join biwmes.wksm_attrname n on a.facility = n.facility and a.attr_number = n.attr_number
where a.LOT_DEL_FLAG = 'Y' and not regexp_like(a.lot_number, '^K.......[0-2][0-9]\$')
)
, wafers as (
select /*+ INDEX(wl WKSM_WIPLOT_IDX01) */ distinct
  i.facility
, coalesce(src_lot, i.lot_number)||'.S' as source_lot
, coalesce(src_lot, i.lot_number)||'_'||slot as wafer
, i.attr_number
, wl.prod as fab_product
, wl.owner as lot_type
, wl.creation_date as lot_start_date
, case when ne.epi_sic_slice is not null and ne.epi_sic_slice != i.sic_slice then ne.epi_sic_slice else i.sic_slice end as sic_slice
, ' ' as global_wafer_id
, ' ' as raw_sic_supplier
, coalesce(ei.lot_number, case when i.facility = 'FM4045' then i.lot_number else ne.adjusted_slice end, lewa.lot_number)              as epi_lot
, coalesce(ei.epi_product, case when i.facility = 'FM4045' then wl.prod else ne.product end, lewa.epi_product)                        as epi_product
, coalesce(ei.epi_slot, case when i.facility = 'FM4045' then slot else ne.epi_slot end, lewa.epi_slot)                                as epi_slot
, coalesce(ei.epi_attr_number, case when i.facility = 'FM4045' then i.attr_number else ne.epi_attr_number end, lewa.epi_attr_number)  as epi_attr_number
, coalesce(ei.epi_start_date, case when i.facility = 'FM4045' then wl.creation_date else ne.epi_start_date end, lewa.epi_attr_number) as epi_start_date
, coalesce(ei.epi_location, ne.epi_location, lewa.epi_location) as epi_supplier
, a.changed_wafer
from info i
left join nonprod_epi ne on i.sic_slice =ne.sic_slice 
left join source_lot sl on i.lot_number = sl.start_lot
left join epi_info ei on i.sic_slice = ei.sic_slice and ei.ei_rank = 1
left join bk_epi_lots_without_attributes lewa on lewa.lot_number = i.adjusted_slice and lewa.ei_rank = 1
left join biwmes.wksm_wiplot wl on coalesce(src_lot, i.lot_number) = wl.lot_number $epiFacilityJoin 
left join changed_wafers a on a.facility = i.facility
              and a.ALP_ATTR_VAL = case when ne.epi_sic_slice is not null and ne.epi_sic_slice != i.sic_slice then ne.epi_sic_slice else i.sic_slice end 
              and substr(a.lot_number, 1, length(i.lot_number)) != i.lot_number
where i.slice_rank = 1
  and wl.business_unit in ('KLMI1', 'MEMI1')
)
select w.facility
     , w.source_lot
     , w.wafer
     , w.attr_number
     , w.fab_product
     , w.lot_type
     , w.lot_start_date
     , to_single_byte(w.sic_slice) as sic_slice
     , w.global_wafer_id
     , w.raw_sic_supplier
     , w.epi_lot
     , w.epi_product
     , w.epi_slot
     , w.epi_attr_number
     , w.epi_start_date
     , w.epi_supplier
     , listagg(w.changed_wafer, ',') within group (order by w.wafer) as changed_wafers
from wafers w
";
  if ((defined($sliceL) && length($sliceL) > 1))
  {
     $sqlStr .= "where w.sic_slice in ($sliceL)
";
  }
  $sqlStr .="group by w.facility
, w.source_lot
, w.wafer
, w.attr_number
, w.fab_product
, w.lot_type
, w.lot_start_date
, to_single_byte(w.sic_slice)
, w.global_wafer_id
, w.raw_sic_supplier
, w.epi_lot
, w.epi_product
, w.epi_slot
, w.epi_attr_number
, w.epi_start_date
, w.epi_supplier
order by 1, 2, 3
";
#INFO("$sqlStr");
   if ($sqlType eq "epi")
   {
#INFO("$sqlStr");
   }

   return $sqlStr;
}

sub getCZEpiSQLWithEpiLot {
   my ($useArchive, $useMultiWafer, $startD, $endD, $slice, $sliceL) = @_;
   my $sqlStr = "";
   my $archStr = "";
   if ($useArchive eq "Y")
   {
      $archStr = "_ARCH";
   }

   $sqlStr = "with evtime as
(
  select /*+ INDEX(aev ACTLEVCOUNT_1_INDEX) */ counter, aev.lotid, a.parentid, a.lottype, a.EQPID, a.EQPTYPE, null timerev, evtime, trackouttime, evreason, evendmainqty, stage, a.location, evtype, evuser, evstate, evvariant, a.partname, cg.CATEGORY as prodfamily
  from torrent$archStr.actlevcount$archStr aev
  join torrent$archStr.actl$archStr a on aev.LOTID = a.lotid
  join torrent.catg cg on a.partname = cg.partprcdname and a.partversion = cg.PARTPRCDVERSION and cg.categorytype = 'P' and cg.catgnumber = '07'
  union all
  select /* + INDEX(hev HISTEVCOUNT_1_INDEX) */ counter, hev.lotid, h.parentid, h.lottype, h.EQPID, h.EQPTYPE, hev.timerev, evtime, trackouttime, evreason, evendmainqty, stage, h.location, evtype, evuser, evstate, evvariant, h.partname, cg.CATEGORY as prodfamily
  from torrent$archStr.histevcount$archStr hev
  join torrent$archStr.hist$archStr h on h.lotid = hev.lotid and h.timerev = hev.timerev
  join torrent.catg cg on h.partname = cg.partprcdname and h.partversion = cg.PARTPRCDVERSION and cg.categorytype = 'P' and cg.catgnumber = '07'
)
, evtime_lots as
(
  select /*+ INDEX(a PK_ACTL)*/ counter, aev.lotid, a.lottype, a.EQPID, a.EQPTYPE, null timerev, evtime, trackouttime, evreason, evendmainqty, stage, a.location, evtype, evuser, evstate, evvariant, a.partname, cg.CATEGORY as prodfamily
  from torrent$archStr.actlevcount$archStr aev
  join torrent$archStr.actl$archStr a on aev.LOTID = a.lotid
  join torrent.catg cg on a.partname = cg.partprcdname and a.partversion = cg.PARTPRCDVERSION and cg.categorytype = 'P' and cg.catgnumber = '07'
  union all
  select /*+ INDEX(h PK_HIST) */ counter, hev.lotid, h.lottype, h.EQPID, h.EQPTYPE, hev.timerev, evtime, trackouttime, evreason, evendmainqty, stage, h.location, evtype, evuser, evstate, evvariant, h.partname, cg.CATEGORY as prodfamily
  from torrent$archStr.histevcount$archStr hev
  join torrent$archStr.hist$archStr h on h.lotid = hev.lotid and h.timerev = hev.timerev
  join torrent.catg cg on h.partname = cg.partprcdname and h.partversion = cg.PARTPRCDVERSION and cg.categorytype = 'P' and cg.catgnumber = '07'
)
, evsimple as
(
  select counter, aev.lotid, a.lottype, a.EQPID, a.EQPTYPE, null timerev, evtime, trackouttime, evreason, evendmainqty, stage, a.location, evtype, evuser, evstate, evvariant, a.partname, a.partversion
  from torrent$archStr.actlevcount$archStr aev
  join torrent$archStr.actl$archStr a on aev.LOTID = a.lotid
  union all
  select counter, hev.lotid, h.lottype, h.EQPID, h.EQPTYPE, hev.timerev, evtime, trackouttime, evreason, evendmainqty, stage, h.location, evtype, evuser, evstate, evvariant, h.partname, h.partversion
  from torrent$archStr.histevcount$archStr hev
  join torrent$archStr.hist$archStr h on h.lotid = hev.lotid and h.timerev = hev.timerev
)
";
   if ($useMultiWafer eq "Y")
   {
      $sqlStr .= ", epicomps as -- for 1:25 lot:wafer tracking by time
(
select /*+ MATERIALIZE */ distinct ev.partname, ev.lotid, ev.evtime, ev.timerev, ev.lottype, ev.evtype, ev.counter, ev.prodfamily, tc.compid, p.parmval as waferid, ev.eqpid, eq.description as eq_desc
, dense_rank() over (partition by tc.compid order by evtime desc, timerev desc, ev.counter desc) as wafer_rank
from evtime ev
JOIN TABLE (rptm.rm_comp.getHistComp(ev.lotid, ev.evtime, ev.timerev, ev.counter, ev.evtype) )tc ON 1 = 1
join torrent.walpparmcount p on tc.compid = p.compid and p.parmname = '\$SIC_SCRIBEBS'
left join torrent.equn eq on ev.eqpid = eq.eqpid
where prodfamily = 'SIC_EPI'
  and ((ev.evtype = 'SPRT' and (ev.partname like '%-EPI' or ev.partname like '_SMPE%' )) -- Part grading
    or (ev.evtype in ('SCRP', 'TERM', 'MOUT','SPRT', 'NTKO','DTKO') and ev.location in ( 'KTEST', 'KPACK', 'KTPACKEPI', 'KEPITAXY', 'KEPITAXY2', 'ESHIPPING') and ev.eqpid = ev.evvariant)) -- Activity at a tool (reactor or inspection)
  and ((eq.description is null and ev.evtype = 'SPRT' and (ev.partname like '%-EPI' or ev.partname like '_SMPE%' )) or upper(eq.description) like 'SIC EPI REACTOR%' or upper(eq.description) like 'SIC EPI REACTOR%')
";
      if (!defined($slice) && !defined($sliceL) && defined($startD) && defined ($endD))
      {
         $sqlStr .= "  and ev.evtime between trunc(sysdate) + (1*$startD) and trunc(sysdate) + 1 + (1*$endD)
";
      }
      $sqlStr .= ")
, epicomps_slice as  -- for 1:25 lot:wafer tracking by wafer ID
(
select /*+ MATERIALIZE */ distinct ev.partname, ev.eqpid, ev.lotid, ev.evtime, ev.timerev, ev.lottype, ev.evtype, ev.counter, ev.prodfamily, p.compid, p.parmval as waferid, eq.description as eq_desc
, dense_rank() over (partition by p.compid order by evtime desc, timerev desc, ev.counter desc) as wafer_rank
from evtime_lots ev
left join torrent.equn eq on ev.eqpid = eq.eqpid
join torrent.walpparmcount p on ev.lotid = p.lotid and p.parmname = '\$SIC_SCRIBEBS'
";
      if ((defined($sliceL) && length($sliceL) > 1))
      {
         $sqlStr .= "where p.parmval in ($sliceL)
";
      }
      elsif (defined($slice))
      {
         $sqlStr .= "where p.parmval = '$slice'
";
      }
      $sqlStr .= ")
, find_epi_start_lot (start_lotid, lotid, waferid, compid, fromlot, tolot, evtype, prodfamily, evtime, end_evtime, timerev, counter, lvl) as
(
select /*+ MATERIALIZE */ ec.lotid as start_lotid
, ec.lotid
, ec.waferid
, ec.compid as compid
, ec.lotid as fromlot
, ec.lotid as tolot
, ec.evtype
, ec.prodfamily
, ec.evtime, ec.evtime as end_evtime, ec.timerev, ec.counter, 1 as lvl
";
      if ((defined($sliceL) && length($sliceL) > 1) || defined($slice))
      {
         $sqlStr .= "from epicomps_slice ec
";
      }
      else
      {
         $sqlStr .= "from epicomps ec
";
      }
      $sqlStr .= "where ec.wafer_rank = 1
union all 
select /*+ ORDERED MATERIALIZE */ ec2.start_lotid
, ev2.lotid
, ec2.waferid
, TRIM(REGEXP_SUBSTR(ev2.evvariant, '[^' || CHR(7) || ']+', 1, 1)) as compid
, TRIM(REGEXP_SUBSTR(ev2.evvariant, '[^' || CHR(7) || ']+', 1, 2)) as fromlot
, TRIM(REGEXP_SUBSTR(ev2.evvariant, '[^' || CHR(7) || ']+', 1, 3)) as tolot
, ev2.evtype
, cg.\"CATEGORY\" as prodfamily
, ev2.evtime, ec2.evtime as end_evtime, ev2.timerev, ev2.counter, lvl + 1 as lvl
from find_epi_start_lot ec2
join evsimple ev2 on ev2.lotid = ec2.fromlot and ec2.compid = TRIM(REGEXP_SUBSTR(ev2.evvariant, '[^' || CHR(7) || ']+', 1, 1)) 
join torrent.catg cg on ev2.partname = cg.partprcdname and ev2.partversion = cg.PARTPRCDVERSION and cg.categorytype = 'P' and cg.catgnumber = '07'
where ev2.EVTYPE = 'MIDC'
  and (cg.CATEGORY = 'SIC_EPI' or ec2.prodfamily = 'SIC_EPI')
  and ev2.lotid = TRIM(REGEXP_SUBSTR(ev2.evvariant, '[^' || CHR(7) || ']+', 1, 3)) 
  and lvl <= 20
) CYCLE fromlot, tolot set is_cycle to 'Y' default 'N'
, lot_trace as
( 
select /*+ MATERIALIZE */ start_lotid, waferid, t.compid, et.evtype, et.eqpid, et.evtime, et.timerev, a.partname, et.lottype, t.lotid
from find_epi_start_lot t
join ";
      if ((defined($sliceL) && length($sliceL) > 1) || defined($slice))
      {
         $sqlStr .= "evtime ";
      } 
      else
      {
         $sqlStr .= "evtime_lots ";
      }
      $sqlStr .= "et on t.lotid = et.lotid
join torrent.equn e on et.eqpid = e.eqpid 
join torrent.walpparmcount pc on t.compid = pc.compid and pc.parmname = '\$SIC_SCRIBEBS'
join torrent$archStr.actl$archStr a on pc.lotid = a.lotid 
where et.eqpid = et.evvariant and upper(e.description) like 'SIC EPI REACTOR%'
  and et.evtime between t.evtime and t.end_evtime
  and et.evtype in ('NTKO', 'DTKO')
)
, epislices as
(
select /*+ MATERIALIZE */ unique
       l.lotid as lot 
     , l.eqpid 
     , l.waferid as slice
     , pg.parmval as global_wafer_id
     , pk.parmval as puck_id
     , po.parmval as START_LOT
     , to_char(l.evtime, 'YYYYMMDD') as SLICE_START_TIME
     , l.partname as SLICE_PARTNAME
     , l.lottype  as SLICE_LOTTYPE
     , case when l.partname like 'SIC_S_31%' or l.partname like 'SIC_S_11%' or regexp_like(l.partname, '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)1.*') then 'SICC'
            when l.partname like 'SIC_S_09%' or l.partname like 'SIC_S_08%' or regexp_like(l.partname, '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)(8|9).*') then 'TANKEBLU'
            when l.partname like 'SIC_S_20%' or l.partname like 'SIC_S_32%' or regexp_like(l.partname, '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)G.*') then 'SEMSIC'
            when l.partname like 'SIC_S_01%' or l.partname like 'SIC_S_01%' or regexp_like(l.partname, '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)0.*') then 'CREE'
            when l.partname like 'SIC_S_16%' or l.partname like 'SIC_S_29%' or regexp_like(l.partname, '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)D.*') then 'SYNLIGHT'
            when l.partname like 'SIC_S_21%' or l.partname like 'SIC_S_33% 'or regexp_like(l.partname, '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)H.*') then 'GSCS' /* Summit*/
            when l.partname like 'SIC_S_06%' or l.partname like 'SIC_S_07%' or l.partname like 'SIC_S_12%'  or l.partname like 'SIC_S_13%' or regexp_like(l.partname, '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)(4|5|7|K).*') then 'UWH'
            else pss.parmval end as SLICE_SUPPLIERID
     , coalesce(a.STARTMAINQTY, 0) as PUCK_HEIGHT -- Need to find puck lot to get this
     , cast(regexp_substr(pn.parmval, '\\d+') as integer) as SLICE_ORDER
     , coalesce(rptm.get_wafparm_hist(l.compid, '\$SIC_SLOTID', l.evtime), psl.parmval ) as slotid
from lot_trace l
left join torrent.walpparmcount pk  on l.compid = pk.compid  and pk.parmname  = '\$SIC_LOTXTAL'  /* puck */
left join torrent.walpparmcount pn  on l.compid = pn.compid  and pn.parmname  = '\$SIC_ORDERID'
left join torrent.walpparmcount psl on l.compid = psl.compid and psl.parmname = '\$SIC_SLOTID'
left join torrent.walpparmcount pss on l.compid = pss.compid and pss.parmname = '\$SIC_SUPPLYID'
left join torrent.walpparmcount po  on l.compid = po.compid  and po.parmname  = '\$SIC-ORIGIN_LOT'
left join torrent$archStr.actl$archStr a on po.parmval = a.lotid
left join torrent.walpparmcount pg  on l.compid = pg.compid  and pg.parmname  = '\$SIC_GLWAFID'
)
select 'CZ2'            as \"FACILITY\"
     , case when SLICE_SUPPLIERID in( 'GTAT', 'UWH') then substr(puck_id, 1, length(puck_id)-1) else puck_id end || '.S' as \"SOURCE_LOT\"
     , slice            as \"WAFER\"
     , slice_partname   as \"FAB_PRODUCT\"
     , slice_lottype    as \"LOT_TYPE\"
     , slice_start_time as \"LOT_START_DATE\"
     , slice            as \"SIC_SLICE\"
     , case when length(slice) <= 11 then slice else global_wafer_id end as \"GLOBAL_WAFER_ID\"
     , puck_id          as \"PUCK_ID\"
     , case when slice_supplierid = 'GTAT' then 'UWH' else slice_supplierid end as \"RAW_SIC_SUPPLIER\"
     , lot              as \"EPI_LOT\"
     , slice_partname   as \"EPI_PRODUCT\"
     , slotid           as \"EPI_SLOT\"
     , slice_start_time as \"EPI_START_DATE\"
     , 'CZ2'            as \"EPI_SUPPLIER\"
     , SLICE_ORDER      as \"SLICE_ORDER\"
     , 0                as \"ATTR_NUMBER\"
     , 0                as \"EPI_ATTR_NUMBER\"
from epislices
where puck_id is not null and length(puck_id) > 1
";
   }
   else
   {
      $sqlStr .= ", actlwafers as  -- For 1:1 lot:wafer tracking
(
select /*+ MATERIALIZE */ a.partname, ev.eqpid, eq.description as eqpdesc, ev.eqptype, ev.lotid, ev.lottype, ev.evtime, apc.parmval as waferid
, dense_rank() over (partition by apc.parmval order by case when upper(eq.description) like 'SIC EPI REACTOR%' then 1 else 2 end, evtime desc, timerev desc) as wafer_rank 
from evtime ev
join torrent$archStr.actllotparmcount$archStr apc on ev.lotid = apc.lotid
join torrent$archStr.actl$archStr a on ev.lotid = a.lotid
left join torrent.equn eq on ev.eqpid = eq.eqpid
where prodfamily = 'SIC_EPI' and ev.evendmainqty in (0,1)
  and ((ev.evtype = 'SPRT' and (ev.partname like '%-EPI' or ev.partname like '_SMPE%' )) or (ev.evtype in ('SCRP', 'TERM', 'MOUT', 'SPRT', 'NTKO', 'DTKO') and ev.location in ( 'KTEST', 'KPACK', 'KTPACKEPI', 'KEPITAXY', 'KEPITAXY2', 'ESHIPPING') and ev.eqpid = ev.evvariant)) -- Activity at a tool (reactor or inspection)
  and ((ev.evtype = 'SPRT' and (ev.partname like '%-EPI' or ev.partname like '_SMPE%' )) or upper(eq.description) like 'SIC EPI REACTOR%')
  and (apc.PARMNAME = '\$SIC_SCRIBEBS' or (apc.PARMNAME = '\$SIC_GLWAFID' and length(apc.PARMVAL) <= 11)) /* Sometimes only SIC_GLWAFID is set, but we can't use it if it's all we have and it differs from wafer ID */
";
      if (!defined($slice) && !defined($sliceL) && defined($startD) && defined ($endD))
      {
         $sqlStr .= "  and ev.evtime between trunc(sysdate) + (1*$startD) and trunc(sysdate) + 1 + (1*$endD)
";
      }
      elsif ((defined($sliceL) && length($sliceL) > 1))
      {
         $sqlStr .= "  and apc.parmval in ($sliceL)
";
      }
      elsif (defined($slice))
      {
         $sqlStr .= "  and apc.parmval = '$slice'
";
      }
      $sqlStr .= ")
, setpart as 
(
select /*+ MATERIALIZE INDEX(apc ACTLLOTPARMCOUNT_IDX2) */ unique apc.parmval as waferid
     , ev.partname
from actlwafers w
join torrent$archStr.actllotparmcount$archStr apc on w.WAFERID = apc.parmval
join evtime_lots ev on ev.lotid = apc.lotid
join torrent$archStr.actl$archStr a on ev.lotid = a.lotid
where prodfamily = 'SIC_EPI' and ev.evendmainqty in (0,1)
  and ev.evtype = 'SPRT' 
  and ev.partname like '%-EPI' 
  and (apc.PARMNAME = '\$SIC_SCRIBEBS' or (apc.PARMNAME = '\$SIC_GLWAFID' and length(apc.PARMVAL) <= 11)) /* Sometimes only SIC_GLWAFID is set, but we can't use it if it's all we have and it differs from wafer ID */
)
, actlepislices as
(
select /*+ MATERIALIZE */ unique
       l.lotid as lot --l.lotid as lot
     , l.eqpid  
     , l.eqpdesc
     , l.waferid as slice
     , coalesce(pg.parmval, case when length(l.waferid) <= 11 then l.waferid else null end) as global_wafer_id
     , coalesce(pk.parmval, ppk.parmval) as puck_id
     , coalesce(po.parmval, a.parentid) as START_LOT
     , to_char(l.evtime, 'YYYYMMDD') as SLICE_START_TIME  -->
     , coalesce(sp.partname, l.partname) as SLICE_PARTNAME -->
     , l.lottype  as SLICE_LOTTYPE
     , case when coalesce(sp.partname, l.partname) like 'SIC_S_31%' or coalesce(sp.partname, l.partname) like 'SIC_S_11%' or regexp_like(coalesce(sp.partname, l.partname), '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)1.*') then 'SICC'
            when coalesce(sp.partname, l.partname) like 'SIC_S_09%' or coalesce(sp.partname, l.partname) like 'SIC_S_08%' or regexp_like(coalesce(sp.partname, l.partname), '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)(8|9).*') then 'TANKEBLU'
            when coalesce(sp.partname, l.partname) like 'SIC_S_20%' or coalesce(sp.partname, l.partname) like 'SIC_S_32%' or regexp_like(coalesce(sp.partname, l.partname), '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)G.*') then 'SEMSIC'
            when coalesce(sp.partname, l.partname) like 'SIC_S_01%' or coalesce(sp.partname, l.partname) like 'SIC_S_01%' or regexp_like(coalesce(sp.partname, l.partname), '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)0.*') then 'CREE'
            when coalesce(sp.partname, l.partname) like 'SIC_S_16%' or coalesce(sp.partname, l.partname) like 'SIC_S_29%' or regexp_like(coalesce(sp.partname, l.partname), '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)D.*') then 'SYNLIGHT'
            when coalesce(sp.partname, l.partname) like 'SIC_S_21%' or coalesce(sp.partname, l.partname) like 'SIC_S_33% 'or regexp_like(coalesce(sp.partname, l.partname), '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)H.*') then 'GSCS' /* Summit*/
            when coalesce(sp.partname, l.partname) like 'SIC_S_06%' or coalesce(sp.partname, l.partname) like 'SIC_S_07%' or coalesce(sp.partname, l.partname) like 'SIC_S_12%'  or coalesce(sp.partname, l.partname) like 'SIC_S_13%' or regexp_like(coalesce(sp.partname, l.partname), '^(6|8|T)(S|D|M)\\d\\d\\d\\d..(0|A)(4|5|7|K).*') then 'UWH'
            else pss.parmval end as SLICE_SUPPLIERID
     , coalesce(ap.STARTMAINQTY, a.STARTMAINQTY, 0) as PUCK_HEIGHT -- Need to find puck lot to get this
     , cast(regexp_substr(pn.parmval, '\\d+') as integer) as SLICE_ORDER
     , psl.parmval as slotid
from actlwafers l
left join setpart sp on l.waferid = sp.waferid
left join torrent$archStr.actl$archStr a on a.lotid = l.lotid
left join torrent$archStr.actllotparmcount$archStr pk  on l.lotid = pk.lotid  and pk.parmname  = '\$SIC_LOTXTAL'  /* puck */
left join torrent$archStr.actllotparmcount$archStr pn  on l.lotid = pn.lotid  and pn.parmname  = '\$SIC_ORDERID'
left join torrent$archStr.actllotparmcount$archStr psl on l.lotid = psl.lotid and psl.parmname = '\$SIC_SLOTID'
left join torrent$archStr.actllotparmcount$archStr pss on l.lotid = pss.lotid and pss.parmname = '\$SIC_SUPPLYID'
left join torrent$archStr.actllotparmcount$archStr po  on l.lotid = po.lotid  and po.parmname  = '\$SIC-ORIGIN_LOT'
left join torrent$archStr.actl$archStr ap on ap.lotid = coalesce(po.parmval, a.parentid)
left join torrent$archStr.actllotparmcount$archStr ppk on ap.lotid = ppk.lotid and ppk.parmname  = '\$SIC_LOTXTAL' /* Parent puck for 1:1 */
left join torrent$archStr.actllotparmcount$archStr pg  on l.lotid = pg.lotid  and pg.parmname  = '\$SIC_GLWAFID'
where l.wafer_rank = 1
)
select 'CZ2'            as \"FACILITY\"
     , case when SLICE_SUPPLIERID in( 'GTAT', 'UWH') then substr(puck_id, 1, length(puck_id)-1) else puck_id end || '.S' as \"SOURCE_LOT\"
     , slice            as \"WAFER\"
     , slice_partname   as \"FAB_PRODUCT\"
     , slice_lottype    as \"LOT_TYPE\"
     , slice_start_time as \"LOT_START_DATE\"
     , slice            as \"SIC_SLICE\"
     , case when length(slice) <= 11 then slice else global_wafer_id end as \"GLOBAL_WAFER_ID\"
     , puck_id          as \"PUCK_ID\"
     , case when slice_supplierid = 'GTAT' then 'UWH' else slice_supplierid end as \"RAW_SIC_SUPPLIER\"
     , lot              as \"EPI_LOT\"
     , slice_partname   as \"EPI_PRODUCT\"
     , slotid           as \"EPI_SLOT\"
     , slice_start_time as \"EPI_START_DATE\"
     , 'CZ2'            as \"EPI_SUPPLIER\"
     , SLICE_ORDER      as \"SLICE_ORDER\"
     , 0                as \"ATTR_NUMBER\"
     , 0                as \"EPI_ATTR_NUMBER\"
from actlepislices
where puck_id is not null and length(puck_id) > 1
";
   }
#   if ( $useMultiWafer eq "N") {
#   INFO("$sqlStr");
#}
   return $sqlStr;
}

my $dt = DateTime->now(time_zone => 'local');
my $currentDateTime = join '_', $dt->ymd, $dt->hms;
$currentDateTime =~ s/[:-]//g;



### Check Argument
my (%hOptions) = (
    "LOGFILE" => undef,
    "OUT"   => undef,
    "ECOASCHEMA" => undef,
    "ARCHIVEDIR" => undef,
    "DELETESFILE" => undef,
    "MEEPIFILE" => undef,
    "USEARCHIVE" => undef,
    "START" => undef,
    "END" => undef,
    "SLICELIST" => undef,
    "LOTLIST" => undef
);

unless ( GetOptions( \%hOptions, "OUT=s", "ECOASCHEMA=s", "LOGFILE=s", "START=s", "END=s", "USEARCHIVE=s", "ARCHIVEDIR=s", "DELETESFILE=s", "MEEPIFILE=s", "SLICELIST=s", "LOTLIST=s" ))
{
    print %hOptions . "\n";
    print "USAGE: $0 --out {output dir} --logfile {log} --start {rel-days-start] --end {rel-days-end} [--usearchive Y|N] [--archivedir directory] --meepifile [Maine Epi attributes file] [--deletesfile {wks attr deletes file}] --ecoaschema [ecoa-schema-name] --slicelist {GWIDs-and/or-backside-scribe-list} --lotlist {fab-lot-list}\n";
    print "slicelist and lotlist must be a comma-separated (NO SPACES) list of single-qoted backside scribe/GWIDs or lots.  Empty string (\"\") when no wafers/lots to specify.\n";
    exit(1);
}

PDF::Log->init( \%hOptions );
PDF::Log->setLevelDebug;

my $tns      = $ENV{REFDB_TNS};
my $ecofa_tns = $ENV{ECOA_TNS};

my @csv_files = ();

my $useArchive = "N";
if ( defined($hOptions{USEARCHIVE}))
{
    $useArchive=$hOptions{USEARCHIVE};
}

my $archiveDir = "";
if ( defined($hOptions{ARCHIVEDIR}))
{
   $archiveDir=$hOptions{ARCHIVEDIR};
   if ( not -w $archiveDir )
   {
      ERROR("--archivedir directory does not exist or is not writable: $archiveDir");
      exit(1);
   }
}
my $outDir = $hOptions{OUT};

if ( !defined($hOptions{OUT}))
{
   die "required parameter --out";
}
my $outDir = $hOptions{OUT};
# Check if outDir exists and is writable
if ( not -w $outDir )
{
    ERROR("--out directory does not exist or is not writable: $outDir");
    exit(1);
}
my $outDirTmp = "$outDir/tmp";
if (not -w $outDirTmp )
{
    mkdir($outDirTmp);
}

if ( !defined($hOptions{ECOASCHEMA}))
{
   die "required parameter --ecoaschema";
}
if ( !defined($hOptions{START}))
{
   die "required parameter --start";
}
if ( !defined($hOptions{END}))
{
   die "required parameter --end";
}
if ( !defined($hOptions{MEEPIFILE}))
{
   die "required parameter --meepifile";
}
my $ecoaschema= $hOptions{ECOASCHEMA};
my $startDays = $hOptions{START};
my $endDays   = $hOptions{END};

my %attrDeletes;
my $lot;
my $attrnum;
my $slice;
my $slice_list;
my $lot_list;

# Need to write two files for each fab2slice: 
# 1. file with wafers all started in the same source lot 
# 2. file with wafers all from the same source puck
my %byFabPuck;
my %byFabPuckDate;
my %byFabSourceLot;
my %byFabSourceLotDate;

# Need to write two files for each fab2slice: 
# 1. file with wafers all started in the same source lot 
# 2. file with wafers all from the same source puck
my %byEpiSourceLot;
my %byEpiSourceLotDate;

if ( defined($hOptions{SLICELIST}) && length($hOptions{SLICELIST}) > 1)
{
    $slice_list = $hOptions{SLICELIST}
}
if ( defined($hOptions{LOTLIST}) && length($hOptions{LOTLIST}) > 1)
{
    $lot_list = $hOptions{LOTLIST}
}
# Read list of deleted lot attributes
if ( defined($hOptions{DELETESFILE}))
{
    my $deletesFile = $hOptions{DELETESFILE};
    open IN, $deletesFile or die "Cannot open deletesfile: $deletesFile\n";
    my $separator = qr/,/;
    while (<IN>)
    {
        chomp;
        next if $. == 1 ; #skip header
        my @row = split ($separator, $_);
        $lot     = $row[2]; $lot =~ s/^\s+|\s+$//g;
        $attrnum = $row[3]; $attrnum =~s/^\s+|\s+$//g;
        $slice   = $row[4]; $slice =~s/^\s+|\s+$//g;

	# Need to identify if the slice attribute was deleted for a given lot
        #if ( $lot eq "M000844092" ) { print ("Adding to deletes: " . $lot . '-' . $slice . "\n");}
	$attrDeletes{$lot . '-' . $attrnum . '-' . $slice} = 1;
    } 
    close IN;
}

my %maineEpiAttributes = ();
if ( defined($hOptions{MEEPIFILE}))
{
    my $epiFile = $hOptions{MEEPIFILE};
    open IN, $epiFile or die "Cannot open meepifile $epiFile\n";
    my $separator = qr/,/;
    my ($product, $lot, $wafer, $lotType, $slot, $slice, $raw_sic_product, $raw_sic_supplier, $puck, $create_time);
    while (<IN>)
    {
        chomp;
        next if $. == 1 ; #skip header
        my @row = split ($separator, $_);
        $product          = $row[0]; $product =~ s/^\s+|\s+$//g;
        $lot              = $row[1]; $lot =~ s/^\s+|\s+$//g;
        $wafer            = $row[2]; $wafer =~s/^\s+|\s+$//g;
        $lotType          = $row[3]; $lotType =~s/^\s+|\s+$//g;
        $slot             = $row[4]; $slot =~s/^\s+|\s+$//g;
        $slice            = $row[5]; $slice =~s/^\s+|\s+$//g;
        $raw_sic_product  = $row[6]; $raw_sic_product =~s/^\s+|\s+$//g;
        $raw_sic_supplier = $row[7]; $raw_sic_supplier =~s/^\s+|\s+$//g;
        $puck             = $row[8]; $puck =~s/^\s+|\s+$//g;
        $create_time      = $row[9]; $create_time =~s/^\s+|\s+$//g;

	$maineEpiAttributes{$slice} = { product => $product, lot => $lot, wafer => $wafer, lottype => $lotType, slot => $slot,
                                        raw_sic_product => $raw_sic_product, raw_sic_supplier => $raw_sic_supplier, puck => $puck, create_time => $create_time };
    } 
    close IN;
}

# Read list of Maine Lot Attributes

# Connect to BIWMES to get most recent wafer to slice mapping
my $biwmes = DBI->connect("dbi:Oracle:BIWPRD", "YMS", $ENV{YMS_PASSWORD});
#print $biwmes, $DBI::errstr;
if($DBI::errstr) { DpLoad_exit(1,"Unable open DB connection to BIWMES $!"); }

# Get ME WKS RDB to look for deleted lot attributes 
# ME processes epi wafers in batches of 3.  After inspection, one or more wafers may
# be split to a new lot and downgraded.  When this split is done, the child lot
# inherits all parent attributes including the slice to slot mapping.
# After the split, attributes are deleted from both the parent and child lots
# leaving only those that identify the wafers in the splits
# **** When ME WKSM is no longer available this activity must be discontinued ****

# Connect to refdb
my $refdb = DBI->connect($tns, $ENV{REFDB_USER}, $ENV{REFDB_PASS});
#print $refdb, $DBI::errstr;
if($DBI::errstr) { DpLoad_exit(1,"Unable open REFDB DB connection: $tns: $!"); }

# Connect to eCofA DB
my $ecofa_db = DBI->connect($ecofa_tns, $ENV{ECOA_USER}, $ENV{ECOA_PASS});
#print $refdb, $DBI::errstr;
if($DBI::errstr) { DpLoad_exit(1,"Unable open eCofA DB connection: $ecofa_tns: $!"); }
#
# Connect to TORRENT DB 
my $torrent = DBI->connect("dbi:Oracle:TEROTORR", "appuser", "appuser");
if($DBI::errstr) { DpLoad_exit(1,"Unable open DB connection to TORRENT DB $!"); }

# Query BIWMES for recently added fab-to-epi-to-slice data
if (!defined($lot_list) || (defined($lot_list) && length($lot_list) > 1))
{
my $sth=$biwmes->prepare(getEpiOrFabTraceSQL("fab", $startDays, $endDays, $slice_list, $lot_list));
INFO("Fab Trace SQL, $startDays, $endDays " . strftime("%Y-%m-%d %H:%M:%S", localtime));
$sth->execute();
INFO("Query 1 completed at " . strftime("%Y-%m-%d %H:%M:%S", localtime));
my $qi = 0;
while ( my $recs=$sth->fetchrow_hashref()) 
{
    my $line;
    my $fab_source_lot = $recs->{SOURCE_LOT};
    my $fab_wafer      = $recs->{WAFER};
    my $fab_product    = $recs->{FAB_PRODUCT};
    my $lot_type       = $recs->{LOT_TYPE};
    my $slice          = $recs->{SIC_SLICE};
    my $global_wafer_id  = $recs->{GLOBAL_WAFER_ID};
    my $attr_number    = $recs->{ATTR_NUMBER};
    my $raw_sic_supplier = $recs->{RAW_SIC_SUPPLIER}; $raw_sic_supplier =~s/^\s+|\s+$//g;
    my $epi_supplier   = $recs->{EPI_SUPPLIER};       $epi_supplier     =~s/^\s+|\s+$//g;
    #INFO("ES0: \"$epi_supplier\"");
    my $epi_lot        = $recs->{EPI_LOT};            $epi_lot          =~s/^\s+|\s+$//g;
    my $epi_product    = $recs->{EPI_PRODUCT};        $epi_product      =~s/^\s+|\s+$//g;
    my $epi_slot       = $recs->{EPI_SLOT};           $epi_slot         =~s/^\s+|\s+$//g;
    my $epi_start_date = $recs->{EPI_START_DATE};     $epi_start_date   =~s/^\s+|\s+$//g;
    my $changed_wafers = $recs->{CHANGED_WAFERS};     $changed_wafers   =~s/^\s+|\s+$//g;
    my $skip = 0;
    # Variables for eCofA slice data
    my ($ecofa_slice, $ecofa_global_wafer_id, $ecofa_puck_boule, $ecofa_epi_lot, $ecofa_epi_lot_type, $ecofa_epi_slot, $ecofa_raw_partid, $ecofa_epi_partid, $ecofa_raw_supplier, $ecofa_epi_supplier, $ecofa_slice_order, $ecofa_epi_start_date);

    # Look up epi information from CZ, eCofA.  If initial query identifies BK epi, still need to check for GWID.
    #INFO("Fab processing: $slice, fab wafer: $fab_wafer");
    my $me_sic_product;
    my $me_sic_supplier;
    $qi = $qi + 1;
    #INFO("getEpiOrFabTraceSQL $qi start");
    if ( exists ( $maineEpiAttributes{$slice}))
    {
        INFO("found $slice in Maine Epi: $maineEpiAttributes{$slice}{lot} $maineEpiAttributes{$slice}{product}\n");
        $epi_supplier   = "UWB";
        $epi_lot        = $maineEpiAttributes{$slice}{lot};
        $epi_product    = $maineEpiAttributes{$slice}{product};
        $epi_slot       = $maineEpiAttributes{$slice}{slot};
        $epi_start_date = $maineEpiAttributes{$slice}{create_time};
        $me_sic_product  = $maineEpiAttributes{$slice}{raw_sic_product};
        $me_sic_supplier = $maineEpiAttributes{$slice}{raw_sic_supplier};
    }
    if ( $epi_supplier eq "UWB" )
    {
        my $akey = $epi_lot . '-' . $attr_number . '-' . $slice;
        if ( exists($attrDeletes{$akey}))
        {
            INFO("Skipping epi lot $epi_lot, attribute number $attr_number, slice $slice : deleted lot attribute");
            $skip = 1;
        }
    }
    if ( $skip == 0 )
    {
        # Get eCofA slice info 
	# Slice in BK WorkStream is the global wafer ID.  Look up wafer scribe by the global wafer ID.
        my $ech=$ecofa_db->prepare(get_eCofA_sliceInfo($ecoaschema, "", $slice, 0, 0));
        INFO("get_eCofA_sliceInfo $slice " . strftime("%Y-%m-%d %H:%M:%S", localtime));
        $ech->execute();
        #INFO("Query 2 completed at " . strftime("%Y-%m-%d %H:%M:%S", localtime));
        my $erows = $ech->rows;
        my $erecs=$ech->fetchrow_hashref();
        my $eoutStr = "";
        if ( defined($erecs) )
        {
             $slice                 = $erecs->{WAFER_SCRIBE_ID};
             INFO("Found eCofA data for slice $slice, supplierid \"$erecs->{EPI_SUPPLIERID}\"");
             if ( $erecs->{EPI_SUPPLIERID} ne "CZ2" )
             {
                 $ecofa_slice           = $erecs->{WAFER_SCRIBE_ID};
                 $ecofa_global_wafer_id = $erecs->{GLOBAL_WAFER_ID};
                 $ecofa_puck_boule      = $erecs->{PUCK_ID};       $ecofa_puck_boule =~ s/^\s+|\s+$//g;
                 $ecofa_epi_lot         = $erecs->{EPI_LOT};
                 $ecofa_epi_lot_type    = $erecs->{LOT_TYPE};
                 $ecofa_raw_partid      = $erecs->{RAW_PARTNAME};
                 $ecofa_epi_partid      = $erecs->{EPI_PARTNAME};
                 $ecofa_raw_supplier    = $erecs->{RAW_SUPPLIERID} eq "CZ2" ? "GTAT" : $erecs->{RAW_SUPPLIERID};
                 $ecofa_epi_supplier    = $erecs->{EPI_SUPPLIERID};
                 $ecofa_epi_slot        = $erecs->{EPI_SLOT};
                 $ecofa_slice_order     = $erecs->{RAW_SLICE_ORDER};
                 $ecofa_epi_start_date  = $erecs->{EPI_START_DATE};
             }
             
             #print "ecofa: $ecofa_slice GWID=$ecofa_global_wafer_id BOULE=$ecofa_puck_boule RAW_PART=$ecofa_raw_partid RAW_SUPPLIER=$ecofa_raw_supplier EPI_PART=$ecofa_epi_partid EPI_SUPPLIER=$ecofa_epi_supplier WSO=$ecofa_slice_order\n";
        }
        else
        {
            INFO("No eCofA data found for slice $slice, fab wafer $fab_wafer (1)");
            ($ecofa_slice, $ecofa_global_wafer_id, $ecofa_puck_boule, $ecofa_epi_lot, $ecofa_epi_lot_type, $ecofa_epi_slot, $ecofa_raw_partid, $ecofa_epi_partid, $ecofa_raw_supplier, $ecofa_epi_supplier, $ecofa_slice_order, $ecofa_epi_start_date) = ("","","","","","","","","","","","");
        }
        # If no eCofA record found, check CZ2.
        # eCofA record will return rawsilicon but no epi when BK does the epi.  Don't look up in CZ if this is the case.
        if (( !defined($erecs) || (defined($erecs) && (!defined($epi_supplier) || (defined($epi_supplier) && $epi_supplier ne "KRJ" )))))
        {
            # Check CZ2 DB to see if epi was done there
            # First check 1:25
            # There is no 1:25 in the archive so ignore the setting
            my $sth=$torrent->prepare(getCZEpiSQLWithEpiLot("N","Y",undef,undef,$slice));
            INFO("getCZEpiSQLWithEpiLot 1:25 $slice " . strftime("%Y-%m-%d %H:%M:%S", localtime));
            $sth->execute();
            #INFO("Query 3 completed at " . strftime("%Y-%m-%d %H:%M:%S", localtime));
            my $erows = $sth->rows;
            my $erecs=$sth->fetchrow_hashref();
            if ( !defined($erecs) )
            {
                #INFO("No 1:25 lot:wafer epi record in CZ2 for slice $slice, checking 1:1");
                my $sth=$torrent->prepare(getCZEpiSQLWithEpiLot($useArchive,"N",undef,undef,$slice));
                INFO("getCZEpiSQLWithEpiLot 1:1 $slice " . strftime("%Y-%m-%d %H:%M:%S", localtime));
                $sth->execute();
                #INFO("Query 3 completed at " . strftime("%Y-%m-%d %H:%M:%S", localtime));
                $erows = $sth->rows;
                $erecs=$sth->fetchrow_hashref();

                # Check 1:1 TORRENT_ARCH schema & tables if not found in 1:1 TORRENT schema
                if ( !defined($erecs) && $useArchive eq "N" )
                {
                    #INFO("No 1:1 lot:wafer epi record in CZ2 for slice $slice, checking TORRENT_ARCH 1:1");
                    my $sth=$torrent->prepare(getCZEpiSQLWithEpiLot("Y","N",undef,undef,$slice));
                    INFO("getCZEpiSQLWithEpiLot 1:1 $slice " . strftime("%Y-%m-%d %H:%M:%S", localtime));
                    $sth->execute();
                    #INFO("Query 3 completed at " . strftime("%Y-%m-%d %H:%M:%S", localtime));
                    $erows = $sth->rows;
                    $erecs=$sth->fetchrow_hashref();
                }
            }
            if ( defined($erecs) )
            {
                INFO("Found epi record in CZ2 for slice $slice, CZ2 lot=$erecs->{EPI_LOT}");
                $ecofa_slice           = $erecs->{SIC_SLICE};
                $slice                 = $ecofa_slice;
                $ecofa_global_wafer_id = defined($ecofa_global_wafer_id) ? $ecofa_global_wafer_id : $erecs->{GLOBAL_WAFER_ID};
                $ecofa_puck_boule      = defined($ecofa_puck_boule)      ? $ecofa_puck_boule      : $erecs->{PUCK_ID};       $ecofa_puck_boule =~ s/^\s+|\s+$//g;
                $ecofa_epi_lot         = $erecs->{EPI_LOT};
                $ecofa_epi_lot_type    = $erecs->{EPI_LOT_TYPE};
                $ecofa_raw_partid      = defined($ecofa_raw_partid)      ? $ecofa_raw_partid : undef;
                $ecofa_epi_partid      = $erecs->{EPI_PRODUCT};
                $ecofa_raw_supplier    = defined($ecofa_raw_supplier)    ? $ecofa_raw_supplier : $erecs->{RAW_SIC_SUPPLIER};
                $ecofa_epi_supplier    = $erecs->{EPI_SUPPLIER};
                $ecofa_epi_slot        = $erecs->{EPI_SLOT};
                $ecofa_slice_order     = $erecs->{SLICE_ORDER};
                $ecofa_epi_start_date  = $erecs->{EPI_START_DATE};
            }
        }
        my $global_wid_guess = $slice; 
        if ( length($global_wid_guess) > 10 ) 
        {
            my $global_wid_nodash =~s/-//g;
            if ( length($global_wid_nodash) <= 10 )
            {
                $global_wid_guess = $global_wid_nodash;
            }
            else
            {
                $global_wid_guess = substr($global_wid_nodash, 1, 10);
            }
        }

        # Get row from refdb for slice
        INFO("Get row from refdb for slice $slice ($qi) " . strftime("%Y-%m-%d %H:%M:%S", localtime));
        my $rfh=$refdb->prepare("select slice, global_wafer_id, puck_id, run_id, slice_source_lot, start_lot, fab_wafer_id, fab_source_lot, to_char(slice_start_time, 'YYYY-MM-DD HH24:MI:SS') as slice_start_time, slice_partname, slice_lottype, slice_supplierid, puck_height, slice_order from refdb.on_slice where slice = '$slice' or global_wafer_id = '$slice'");
        $rfh->execute();
        #INFO("Query 4 completed at " . strftime("%Y-%m-%d %H:%M:%S", localtime));
        my $rows = $rfh->rows;
        my $rfrecs=$rfh->fetchrow_hashref();
        if ( !defined($rfrecs))
        { 
		INFO("Failed to locate REFDB record for $slice")
        } 
	
	# Verify if the REFDB matched on global wafer ID instead of slice.  If so, set slice to actual scribe/slice
	if ( $slice eq $rfrecs->{GLOBAL_WAFER_ID} && $rfrecs->{GLOBAL_WAFER_ID} ne $rfrecs->{SLICE} && length($rfrecs->{SLICE}) > 0 && length($rfrecs->{GLOBAL_WAFER_ID}) > 0 )
        {
            INFO("Global Wafer ID found in ON_SLICE.  Changing slice from $slice to $rfrecs->{SLICE}");
            $slice = $rfrecs->{SLICE};
        }
        my $outStr = "";

        # The CHANGED_WAFERS column is a comma-separated list of wafer IDs that were previously defined as being associated with the current slice.
        # The attribute defining that wafer/slice association was deleted (LOT_DEL_FLAG set to 'Y') and a new attribute was defined.
        # When CHANGED_WAFERS is not null, need to do the following:
        # 1. update ON_SLICE for the current backside scribe/slice to indicate the new wafer/slice mapping, but
        #    only if the existing wafer/slice mapping matches one of the wafers listed in the CHANGED_WAFERS list.
        # 2. If the FAB_WAFER_ID associated with this slice was assigned previously to some other slice, the fab wafer ID field for that slice should be nulled/deleted.
        my $replace_fab_wafer_id = 0;
	if ( $changed_wafers ne "") 
	{
	    #INFO("Changed wafers: $changed_wafers \$rfrecs->{FAB_WAFER_ID}='$rfrecs->{FAB_WAFER_ID}', \$fab_wafer='$fab_wafer'");
	}
        # 2025-08-28 SAB  If new wafer doesn't match old wafer, replace it regardless of whether it is in the changed_wafers list.
        if ($changed_wafers ne "" && defined($rfrecs) && $rfrecs->{FAB_WAFER_ID} ne "" && $fab_wafer ne "" && $rfrecs->{FAB_WAFER_ID} ne $fab_wafer)
        {
            foreach my $changed_wafer (split(",", $changed_wafers))
            {
	        #INFO("Changed wafer: $changed_wafer, FAB WAFER ID: $rfrecs->{FAB_WAFER_ID}");
                if ($rfrecs->{FAB_WAFER_ID} eq $changed_wafer)
                {
                    INFO("Replacing ON_SLICE fab wafer ID $changed_wafer for slice $slice.  New fab wafer=$fab_wafer");
                    $replace_fab_wafer_id = 1;
                }
            }
        }
        elsif ($rfrecs->{FAB_WAFER_ID} ne "" && $fab_wafer ne "" && $rfrecs->{FAB_WAFER_ID} ne $fab_wafer)
        {
            WARN("Slice $slice fab wafer \"$rfrecs->{FAB_WAFER_ID}\" does not match new wafer $fab_wafer from MES, updating ON_SLICE");
            $replace_fab_wafer_id = 1;
        }
        
        # See if refdb update is needed for fab lot
        # Both wafer ID and source lot must be null for record to be updated
        if (defined($rfrecs) && (($replace_fab_wafer_id == 1 || ($rfrecs->{FAB_WAFER_ID} eq "" && $rfrecs->{FAB_SOURCE_LOT} eq "" && $fab_wafer ne "" && $fab_source_lot ne ""))
         || ($rfrecs->{GLOBAL_WAFER_ID} eq "" && length($ecofa_global_wafer_id) > 0 )
         || ($rfrecs->{SLICE_LOTTYPE} eq "" && length($lot_type) > 0 )
         || (!defined($rfrecs->{SLICE_ORDER}) && length($ecofa_slice_order) > 0 )
           ))
        {
            my $wfid_sql = "";
            my $ord_sql = "";
            my $ltyp_sql = "";
            if (($replace_fab_wafer_id == 1 || $rfrecs->{SLICE_LOTTYPE} eq "") && length($lot_type) > 0 )
            {
                $ltyp_sql = ", slice_lottype = '$lot_type'";
            }
            if (($replace_fab_wafer_id == 1 || $rfrecs->{GLOBAL_WAFER_ID} eq "") && length($ecofa_global_wafer_id) > 0 )
            {
                $wfid_sql = ", global_wafer_id = '$ecofa_global_wafer_id'";
            }
            if (($replace_fab_wafer_id == 1 || !defined($rfrecs->{SLICE_ORDER})) && length($ecofa_slice_order) > 0 && $ecofa_slice_order =~ '^\d+$' )
            {
                $ord_sql = ", slice_order = $ecofa_slice_order";
            }
            INFO("Updating $slice refdb fab wafer=$fab_wafer, source lot=$fab_source_lot" . $wfid_sql . $ord_sql . $ltyp_sql);
            my $upStr="update refdb.on_slice set fab_wafer_id = '$fab_wafer', fab_source_lot = '$fab_source_lot' $wfid_sql $ord_sql $ltyp_sql where slice = '$slice'";
            #print "str=\"$upStr\"" . "\n";
            my $rfh2=$refdb->prepare($upStr);
            $rfh2->execute();
            #INFO("Query 5 completed at " . strftime("%Y-%m-%d %H:%M:%S", localtime));
            my $nRows = $rfh2->rows;
            if ( $nRows != 1 )
            {
                WARN("Unexpected number of rows updated for $slice : $nRows");
                WARN($upStr);
            }
        }
        elsif ($rfrecs->{FAB_WAFER_ID} ne "")
        {
            #INFO("Found existing fab wafer \"$rfrecs->{FAB_WAFER_ID}\", source lot \"$rfrecs->{FAB_SOURCE_LOT}\" for slice $slice, no update needed");
        }
        # Build string to write to FAB2SLICE file(s)
        # FAB2SLICE/SLICE2FAB columns:
        # Original:
        # SOURCE_LOT,WAFER,FAB_PRODUCT,LOT_TYPE,LOT_START_DATE,SIC_SLICE,FAB_SRC_VENDOR,
        # EPI_LOCATION,EPI_LOT,EPI_PRODUCT,EPI_SLOT,EPI_START_DATE,EPI_SRC_VENDOR,
        # WORKSTREAM_ERASE_FLAG,LOTID,PARTNAME,LOTTYPE,PUCKID,RUNID,SUPPLIERID,PUCK_HEIGHT,CZ_LOT_START_DATE
        # New:
        # SOURCE_LOT,WAFER,FAB_PRODUCT,LOT_TYPE,LOT_START_DATE,SIC_SLICE,GLOBAL_WAFER_ID,
        # RAW_SIC_SUPPLIER,EPI_SUPPLIER,EPI_LOT,EPI_PRODUCT,EPI_SLOT,EPI_START_DATE,
        # LOTID,RAW_WAFER_PRODUCT,LOTTYPE,PUCKID,RUNID,PUCK_HEIGHT,SLICE_ORDER,CZ_LOT_START_DATE
        # Preference order between REFDB & eCofA lookup:
        # - If REFDB query returned a value, use it. 
        # - Otherwise, if eCofA query returned a value, use that value
        # - Finally, if neither query returned a value, use string "NA" which equates to null when loading into exensio
	
        my $write_global_wafer_id = (length($rfrecs->{GLOBAL_WAFER_ID}) > 0 ? $rfrecs->{GLOBAL_WAFER_ID} :
                                     (length($ecofa_global_wafer_id) > 0 ? $ecofa_global_wafer_id :
                                       length($global_wid_guess) > 0 ? $global_wid_guess : "NA"));
        my $write_raw_sic_supplier= (length($rfrecs->{SLICE_SUPPLIERID}) > 0 ? $rfrecs->{SLICE_SUPPLIERID} :
                                     (length($ecofa_raw_supplier) > 0 ? $ecofa_raw_supplier :
                                      length($me_sic_supplier) > 0 ? $me_sic_supplier : "NA"));
        my $write_epi_supplier;
        my $write_epi_product;
        my $write_epi_slot;
        my $write_epi_start_date;

	# BK will receive epi from turnkey or consigned epi suppliers. If there is an eCofA record for the wafer, use it for epi supplier info
        if ( length($epi_supplier) > 0 && $epi_supplier ne "UWB" && length($ecofa_epi_supplier) > 0 )
        {
            #INFO("ES1: \"$epi_supplier\"");
            $write_epi_supplier = (length($ecofa_epi_supplier) > 0 ? $ecofa_epi_supplier : (length($epi_supplier) > 0 ? $epi_supplier : "NA"));
            $write_epi_product= length($ecofa_epi_partid) > 0 ? $ecofa_epi_partid : (length($epi_product) > 0 ? $epi_product : "NA");
            $write_epi_slot= (length($ecofa_epi_slot) > 0 ? $ecofa_epi_slot : (length($epi_slot) > 0 ? $epi_slot : "NA"));
            $write_epi_start_date= (length($ecofa_epi_start_date) > 0 ? $ecofa_epi_start_date : (length($epi_start_date) > 0 ? $epi_start_date : "NA"));
        }
        else
        {
            #INFO("ES2: \"$epi_supplier\"");
            $write_epi_supplier = (length($epi_supplier) > 0 ? $epi_supplier : (length($ecofa_epi_supplier) > 0 ? $ecofa_epi_supplier : "NA"));
            $write_epi_product= length($epi_product) > 0 ? $epi_product : length($ecofa_epi_partid) > 0 ? $ecofa_epi_partid : "NA";
            $write_epi_slot= (length($epi_slot) > 0 ? $epi_slot : (length($ecofa_epi_slot) > 0 ? $ecofa_epi_slot : "NA"));
            $write_epi_start_date= (length($epi_start_date) > 0 ? $epi_start_date : (length($ecofa_epi_start_date) > 0 ? $ecofa_epi_start_date : "NA"));
        }
        my $write_slice_partname=(length($rfrecs->{SLICE_PARTNAME}) > 0 ? $rfrecs->{SLICE_PARTNAME} : (length($me_sic_product) > 0 ? $me_sic_product : "NA"));
        my $write_epi_lot;
        # Use the MES lot if from Bucheon, KR (KRJ) or Maine (UWB)
        if ( $write_epi_supplier eq "KRJ" || $write_epi_supplier eq "UWB" )
        {
            $write_epi_lot = length($epi_lot) > 0 ? $epi_lot : (length($ecofa_epi_lot) > 0 ? $ecofa_epi_lot : "NA");
        }
        else
        {
            $write_epi_lot = length($ecofa_epi_lot) > 0 ? $ecofa_epi_lot : length($recs->{EPI_LOT}) > 0 ? $recs->{EPI_LOT} : "NA";
        }

        my $write_slice_order      = (length($rfrecs->{SLICE_ORDER}) > 0 ? $rfrecs->{SLICE_ORDER} : (length($ecofa_slice_order) > 0 ? $ecofa_slice_order : "NA"));
        my $write_start_lot        = length($rfrecs->{START_LOT}) > 0 ? $rfrecs->{START_LOT} : "NA";
        my $write_slice_lottype    = length($rfrecs->{SLICE_LOTTYPE}) > 0 ? $rfrecs->{SLICE_LOTTYPE} : "NA";
        my $write_puck_id          = length($rfrecs->{PUCK_ID}) > 0 ? $rfrecs->{PUCK_ID} :
                                      $write_raw_sic_supplier ne "GTAT" && length($slice) > 0 && $slice =~ /^[^-]+-[0-9]+$/ ? substr($slice, 1, index($slice, "-")-1) : "NA";
        # If run ID is missing: If raw sic supplier is GTAT, remove last character from puck and call it run ID.  Otherwise it is the puck id.
        my $chopped_puck_id = $write_puck_id;
        chop($chopped_puck_id);
        my $write_run_id           = length($rfrecs->{RUN_ID}) > 0 ? $rfrecs->{RUN_ID} : 
                                     $write_raw_sic_supplier ne "GTAT" ? $write_puck_id : $write_puck_id ne "NA" ? $chopped_puck_id : "NA";
        my $write_puck_height      = length($rfrecs->{PUCK_HEIGHT}) > 0 ? $rfrecs->{PUCK_HEIGHT} : "NA";
        my $write_slice_start_time = length($rfrecs->{SLICE_START_TIME}) > 0 ? $rfrecs->{SLICE_START_TIME} : "NA";

        $outStr = $fab_source_lot . ',' . $fab_wafer . ',' . $fab_product . ',' . $lot_type . ',' . $recs->{LOT_START_DATE} . ',' .
                  $slice . ',' . $write_global_wafer_id . ',' . $write_raw_sic_supplier . ',' . $write_epi_supplier . ',' . $write_epi_lot . ',' .
                  $write_epi_product . ',' . $write_epi_slot . ',' . $write_epi_start_date . ',' . 
                  $write_start_lot . ',' . $write_slice_partname . ',' . $write_slice_lottype . ',' .
                  $write_puck_id . ',' . $write_run_id . ',' . $write_puck_height . ',' .  $write_slice_order . ',' . $write_slice_start_time;

	# Since we have the epi2puck info as well, create a record for that
	my $epiOutStr = "";
        my $write_epi_source_lot = (length($rfrecs->{SLICE_SOURCE_LOT}) > 0 ? $rfrecs->{SLICE_SOURCE_LOT} : (length($ecofa_puck_boule) > 0 ? $ecofa_puck_boule : $write_global_wafer_id) . '.S');
        my $write_epi_wafer=$slice;
        my $write_epi_lot_type= length($ecofa_epi_lot_type) > 0 ? $ecofa_epi_lot_type : (length($rfrecs->{SLICE_LOTTYPE}) > 0 ? $rfrecs->{SLICE_LOTTYPE} : "NA");
        $epiOutStr = $write_epi_source_lot . ',' . $write_epi_wafer . ',' . $write_epi_product . ',' . $write_epi_lot_type . ',' . $write_epi_start_date . ',' .
                     $slice . ',' . $write_global_wafer_id . ',' . $write_raw_sic_supplier . ',' . $write_epi_supplier . ',' . $write_epi_lot . ',' . $write_epi_product . ',' .
                     $write_epi_slot . ',' . $write_epi_start_date . ',' . $rfrecs->{START_LOT} . ',' . $write_slice_partname . ',' . $write_epi_lot_type . ',' .
                     $write_puck_id . ',' . $write_run_id . ',' .  $write_puck_height . ',' . $write_slice_order . ',' .
                     $write_slice_start_time;

        my $baseSourceLot = $fab_source_lot;
        $baseSourceLot =~ s/\.S$//g;

	#my $puck_idx = $write_puck_id . "-" . $baseSourceLot;
	my $puck_idx = $write_puck_id;
        if ( length($write_puck_id) > 0 && $write_puck_id ne "NA" )
        {
            if (exists($byFabPuck{$puck_idx}))
            {
                if ( exists($byFabPuck{$puck_idx}{$slice}))
                {
                    WARN("Duplicate slice $slice for: $outStr");
                    WARN("Duplicate of: $byFabPuck{$puck_idx}{$slice}");
                }
                else
                {
                    $byFabPuck{$puck_idx}{$slice} = $outStr;
                }
            }
            else
            {
                my %new_hash;
                $new_hash{$slice} = $outStr;
                $byFabPuck{$puck_idx} = \%new_hash;
                $byFabPuckDate{$puck_idx} = $rfrecs->{SLICE_START_TIME};
            }
        }

        if (exists($byFabSourceLot{$baseSourceLot}))
        {
            if ( exists($byFabSourceLot{$baseSourceLot}{$slice}))
            {
                WARN("Duplicate slice $slice for: $outStr");
                WARN("Duplicate of: $byFabSourceLot{$baseSourceLot}{$slice}");
            }
            else
            {
                $byFabSourceLot{$baseSourceLot}{$slice} = $outStr;
            }
                      #$byFabSourceLot{$baseSourceLot} = $byFabSourceLot{$baseSourceLot} . "\n" . $outStr;
        }
        else
        {
            my %new_hash;
            $new_hash{$slice} = $outStr;
            $byFabSourceLot{$baseSourceLot} = \%new_hash;
            #$byFabSourceLot{$baseSourceLot} = $outStr;
            $byFabSourceLotDate{$baseSourceLot} = $recs->{LOT_START_DATE};
        }

	# Write e2p info now.  If epi part and epi supplier could not be identified, do not add the record to e2p.
        my $baseSourceLot = $write_epi_source_lot;
        $baseSourceLot =~ s/\.S$//g;

        if ( length($baseSourceLot) > 1 && not (defined($write_epi_product) && $write_epi_product eq "NA" && defined($write_epi_supplier) && $write_epi_supplier eq "NA" ) )
        {
            if (exists($byEpiSourceLot{$baseSourceLot}))
            {
                if ( !exists($byEpiSourceLot{$baseSourceLot}{$slice}))
                {
                    $byEpiSourceLot{$baseSourceLot}{$slice} = $epiOutStr;
                }
            }
            else
            {
                my %new_hash;
                $new_hash{$slice} = $epiOutStr;
                $byEpiSourceLot{$baseSourceLot} = \%new_hash;
                $byEpiSourceLotDate{$baseSourceLot} = $write_epi_start_date;
            }
        }
        elsif (length($baseSourceLot) == 0)
        {
            WARN("No puck found for slice $slice for: $outStr");
        }
    }
}
}

if (!defined($slice_list) || (defined($slice_list) && length($slice_list) > 1))
{
# Query BIWMES for epi from BK, then TORRENT for CZ, then eCofA for epi from all other locations
my @iters = (1..4);
for my $iter (@iters) 
{
    # Query BIWMES for recently added epi-to-slice data
    my $sth;
    if ( $iter == 1 )
    {
        $sth=$biwmes->prepare(getEpiOrFabTraceSQL("epi", $startDays, $endDays, $slice_list, $lot_list));
    }
    elsif ( $iter == 2)
    {
        #1:25 lot:wafer
        $sth=$torrent->prepare(getCZEpiSQLWithEpiLot($useArchive, "Y", $startDays, $endDays, undef, $slice_list));
    }
    elsif ( $iter == 3)
    {
        #1:25 lot:wafer
        $sth=$torrent->prepare(getCZEpiSQLWithEpiLot($useArchive, "N", $startDays, $endDays, undef, $slice_list));
    }
    else
    {
        print "Getting e2s/s2e from ecofa\n";
        $sth=$ecofa_db->prepare(get_eCofA_sliceInfoByDate($ecoaschema, $startDays, $endDays, $slice_list));
    }
    INFO("Executing $iter, $startDays, $endDays " . strftime("%Y-%m-%d %H:%M:%S", localtime));
    $sth->execute();
    INFO("Query 6 completed at  " . strftime("%Y-%m-%d %H:%M:%S", localtime));
    my $qi = 0;
    my $cz_epi_lot = "";
    while ( my $recs=$sth->fetchrow_hashref()) 
    {
        #INFO("query $iter loop number $qi start");
        $qi = $qi + 1;
        my $line;
        my $epi_source_lot = $recs->{SOURCE_LOT};
        my $epi_wafer      = $recs->{WAFER};
        my $fab_product    = $recs->{FAB_PRODUCT};
        my $lot_type       = $recs->{LOT_TYPE};      $lot_type=~s/^\s+|\s+$//g;
        my $slice          = $recs->{SIC_SLICE};
        my $global_wafer_id  = $recs->{GLOBAL_WAFER_ID};
        my $epi_lot        = $recs->{EPI_LOT};
        if ( $iter == 2 )
        {
           $cz_epi_lot = $epi_lot;
        }
        my $epi_product    = $recs->{EPI_PRODUCT};
        my $raw_sic_supplier = $recs->{RAW_SIC_SUPPLIER};
        my $epi_supplier   = $recs->{EPI_SUPPLIER};
        my $epi_slot       = $recs->{EPI_SLOT};
        my $attr_number    = $recs->{ATTR_NUMBER};
        my $epi_start_date = $recs->{EPI_START_DATE};
 
        # Variables for eCofA slice data
        my ($ecofa_slice, $ecofa_global_wafer_id, $ecofa_puck_boule, $ecofa_epi_lot, $ecofa_epi_slot, $ecofa_raw_partid, $ecofa_epi_partid, $ecofa_raw_supplier, $ecofa_epi_supplier, $ecofa_slice_order, $ecofa_epi_start_date);
        my $skip = 0;

#    if ( $iter == 3 ) {print("ecofa slice $slice\n")};
        #INFO("Epi iteration: $iter Processing: $slice");
        my $me_sic_product;
        my $me_sic_supplier;
        if ( exists ( $maineEpiAttributes{$slice}))
        {
            INFO("found $slice in Maine Epi: $maineEpiAttributes{$slice}{lot} $maineEpiAttributes{$slice}{product}");
            $epi_supplier   = "UWB";
            $epi_lot        = $maineEpiAttributes{$slice}{lot};
            $epi_product    = $maineEpiAttributes{$slice}{product};
            $epi_slot       = $maineEpiAttributes{$slice}{slot};
            $epi_start_date = $maineEpiAttributes{$slice}{create_time};
            $me_sic_product  = $maineEpiAttributes{$slice}{raw_sic_product};
            $me_sic_supplier = $maineEpiAttributes{$slice}{raw_sic_supplier};
        }
        if ( $epi_supplier eq "UWB" )
        {
            my $akey = $epi_lot . '-' . $attr_number . '-' . $slice;
            #if ( $epi_lot eq "M000844092" ) { print ("Checking deletes: " . $epi_lot . '-' . $slice . "\n");}
            if ( exists($attrDeletes{$akey}))
            {
                INFO("Skipping epi lot $epi_lot, attribute $attr_number, slice $slice : deleted lot attribute");
                $skip = 1;
            }
        }
        if ( $skip == 0 )
        {
            # Get eCofA slice info
            # Slice in BK WorkStream is the global wafer ID.  Look up wafer scribe by the global wafer ID.
            my $ech=$ecofa_db->prepare(get_eCofA_sliceInfo($ecoaschema, "", $slice, 0, 0));
            INFO("Executing ecofa_db for $slice " . strftime("%Y-%m-%d %H:%M:%S", localtime));
            $ech->execute();
            #INFO("Query 7 completed at " . strftime("%Y-%m-%d %H:%M:%S", localtime));
            my $erows = $ech->rows;
            my $erecs=$ech->fetchrow_hashref();
            my $eoutStr = "";
            if ( defined($erecs) )
            {
                $slice                 = $erecs->{WAFER_SCRIBE_ID};
                if ( $erecs->{EPI_SUPPLIERID} ne "CZ2" )
                {
                    $ecofa_slice           = $erecs->{WAFER_SCRIBE_ID};
                    $ecofa_global_wafer_id = $erecs->{GLOBAL_WAFER_ID};
                    $ecofa_puck_boule      = $erecs->{PUCK_ID};     $ecofa_puck_boule =~ s/^\s+|\s+$//g;
                    $ecofa_epi_lot         = $erecs->{EPI_LOT};
                    $ecofa_raw_partid      = $erecs->{RAW_PARTNAME};
                    $ecofa_epi_partid      = $erecs->{EPI_PARTNAME};
                    $ecofa_raw_supplier    = $erecs->{RAW_SUPPLIERID} eq "CZ2" ? "GTAT" : $erecs->{RAW_SUPPLIERID};
                    $ecofa_epi_supplier    = $erecs->{EPI_SUPPLIERID};
                    $ecofa_epi_slot        = $erecs->{EPI_SLOT};
                    $ecofa_slice_order     = $erecs->{RAW_SLICE_ORDER};
                    $ecofa_epi_start_date  = $erecs->{EPI_START_DATE};
                }              
                 #print "ecofa2: $ecofa_slice GWID=$ecofa_global_wafer_id BOULE=$ecofa_puck_boule RAW_PART=$ecofa_raw_partid RAW_SUPPLIER=$ecofa_raw_supplier EPI_PART=$ecofa_epi_partid EPI_SUPPLIER=$ecofa_epi_supplier WSO=$ecofa_slice_order\n";
            }
            else
            {
                INFO("No eCofA data found for slice $slice (2)");
                ($ecofa_slice, $ecofa_global_wafer_id, $ecofa_puck_boule, $ecofa_epi_lot, $ecofa_epi_slot, $ecofa_raw_partid, $ecofa_epi_partid, $ecofa_raw_supplier, $ecofa_epi_supplier, $ecofa_slice_order, $ecofa_epi_start_date) = ("","","","","","","","","","","");
            }

            my $global_wid_guess = $slice; 
            if ( length($global_wid_guess) > 10 ) 
            {
                my $global_wid_nodash =~s/-//g;
                if ( length($global_wid_nodash) <= 10 )
                {
                    $global_wid_guess = $global_wid_nodash;
                }
                else
                {
                    $global_wid_guess = substr($global_wid_nodash, 1, 10);
                }
            }
    
            # Get row from refdb for slice
            my $rfh=$refdb->prepare("select slice, global_wafer_id, puck_id, run_id, slice_source_lot, start_lot, fab_wafer_id, fab_source_lot, to_char(slice_start_time, 'YYYY-MM-DD HH24:MI:SS') as slice_start_time, slice_partname, slice_lottype, slice_supplierid, puck_height, slice_order from refdb.on_slice where slice = '$slice' or global_wafer_id = '$slice'");
    
            INFO("Get row (2) from refdb for slice $slice ($qi) " . strftime("%Y-%m-%d %H:%M:%S", localtime));
            $rfh->execute();
            #INFO("Query 8 completed at " . strftime("%Y-%m-%d %H:%M:%S", localtime));
            my $rows = $rfh->rows;
            my $rfrecs=$rfh->fetchrow_hashref();
            my $outStr = "";
            if ( defined($rfrecs))
            {
                # Refdb update only needed for fab wafer, not epi
                # Build string to write to EPI2SLICE file(s)
                # EPI2SLICE/SLICE2EPI columns:
                # Original:
                # SOURCE_LOT,WAFER,FAB_PRODUCT,LOT_TYPE,LOT_START_DATE,SIC_SLICE,FAB_SRC_VENDOR,
                # EPI_LOCATION,EPI_LOT,EPI_PRODUCT,EPI_SLOT,EPI_START_DATE,EPI_SRC_VENDOR,
                # WORKSTREAM_ERASE_FLAG,LOTID,PARTNAME,LOTTYPE,PUCKID,RUNID,SUPPLIERID,PUCK_HEIGHT,CZ_LOT_START_DATE
                # New
                # SOURCE_LOT,WAFER,FAB_PRODUCT,LOT_TYPE,LOT_START_DATE,SIC_SLICE,GLOBAL_WAFER_ID
                # RAW_SIC_SUPPLIER,EPI_SUPPLIER,EPI_LOT,EPI_PRODUCT,EPI_SLOT,EPI_START_DATE,
                # LOTID,RAW_WAFER_PRODUCT,LOTTYPE,PUCKID,RUNID,PUCK_HEIGHT,SLICE_ORDER,CZ_LOT_START_DATE
                # Preference order between REFDB & eCofA lookup:
                # - If REFDB query returned a value for the slice, use it for the raw wafer slice. 
                # - For epi, use the value provided by the query
                # - Finally, if neither query returned a value, use string "NA" which equates to null when loading into exensio
	
	        # Verify if the REFDB matched on global wafer ID instead of slice.  If so, set slice to actual scribe/slice
                if ( $slice eq $rfrecs->{GLOBAL_WAFER_ID} && $rfrecs->{GLOBAL_WAFER_ID} ne $rfrecs->{SLICE} && length($rfrecs->{SLICE}) > 0 && length($rfrecs->{GLOBAL_WAFER_ID}) > 0)
                {
                    INFO("Global Wafer ID found in ON_SLICE.  Changing slice from $slice to $rfrecs->{SLICE}");
                    $slice = $rfrecs->{SLICE};
                }

                my $write_global_wafer_id = (length($rfrecs->{GLOBAL_WAFER_ID}) > 0 ? $rfrecs->{GLOBAL_WAFER_ID} :
                                             (length($ecofa_global_wafer_id) > 0 ? $ecofa_global_wafer_id :
                                              length($global_wid_guess) > 0 ? $global_wid_guess : "NA"));
                my $write_epi_source_lot = (length($rfrecs->{SLICE_SOURCE_LOT}) > 0 ? $rfrecs->{SLICE_SOURCE_LOT} : (length($ecofa_puck_boule) > 0 ? $ecofa_puck_boule : $write_global_wafer_id) . '.S');
                my $write_raw_sic_supplier= (length($rfrecs->{SLICE_SUPPLIERID}) > 0 ? $rfrecs->{SLICE_SUPPLIERID} : 
                                             (length($ecofa_raw_supplier) > 0 ? $ecofa_raw_supplier : 
                                              (length($recs->{RAW_SIC_SUPPLIER}) > 0 ? $recs->{RAW_SIC_SUPPLIER} :
                                                length($me_sic_supplier) > 0 ? $me_sic_supplier : "NA" )));
                my $write_epi_supplier= (length($recs->{EPI_SUPPLIER}) > 0 ? $recs->{EPI_SUPPLIER} : (length($ecofa_epi_supplier) > 0 ? $ecofa_epi_supplier : "NA"));
                my $write_slice_partname=(length($rfrecs->{SLICE_PARTNAME}) > 0 ? $rfrecs->{SLICE_PARTNAME} : (length($me_sic_product) > 0 ? $me_sic_product : "NA"));
                my $write_epi_lot;
                if ( $write_epi_supplier eq "KRJ" || $write_epi_supplier eq "UWB")
                {
                    $write_epi_lot = length($epi_lot) > 0 ? $epi_lot : (length($ecofa_epi_lot) > 0 ? $ecofa_epi_lot : "NA");
                } 
                elsif ( $write_epi_supplier eq "CZ2" )
                {
                    $write_epi_lot = length($cz_epi_lot) > 0 ? $cz_epi_lot : length($epi_lot) > 0 ? $epi_lot : (length($ecofa_epi_lot) > 0 ? $ecofa_epi_lot : "NA");
                } 
                else
                {
                    $write_epi_lot = length($ecofa_epi_lot) > 0 ? $ecofa_epi_lot : length($recs->{EPI_LOT}) > 0 ? $recs->{EPI_LOT} : "NA";
                } 
                #my $write_epi_wafer=$write_epi_supplier eq "KRJ" ? $epi_wafer : $slice;
                my $write_epi_wafer=$slice;
		
                my $write_epi_product;
                my $write_epi_slot;
                my $write_epi_start_date;

	        # BK will receive epi from turnkey or consigned epi suppliers. If there is an eCofA record for the wafer, use it for epi supplier info
                if ( $iter == 1 and length($epi_supplier) > 0 && $epi_supplier ne "UWB" && length($ecofa_epi_supplier) > 0 )
                {
                    $write_epi_supplier = (length($ecofa_epi_supplier) > 0 ? $ecofa_epi_supplier : (length($recs->{EPI_SUPPLIER}) > 0 ? $recs->{EPI_SUPPLIER} : "NA"));
                    $write_epi_product= length($ecofa_epi_partid) > 0 ? $ecofa_epi_partid : (length($epi_product) > 0 ? $epi_product : "NA");
                    $write_epi_slot= (length($ecofa_epi_slot) > 0 ? $ecofa_epi_slot : (length($epi_slot) > 0 ? $epi_slot : "NA"));
                    $write_epi_start_date= (length($ecofa_epi_start_date) > 0 ? $ecofa_epi_start_date : (length($epi_start_date) > 0 ? $epi_start_date : "NA"));
                }
                else
                {
                    $write_epi_product= length($epi_product) > 0 ? $epi_product : length($ecofa_epi_partid) > 0 ? $ecofa_epi_partid : "NA";
                    $write_epi_slot= (length($epi_slot) > 0 ? $epi_slot : (length($ecofa_epi_slot) > 0 ? $ecofa_epi_slot : "NA"));
                    $write_epi_start_date= (length($epi_start_date) > 0 ? $epi_start_date : (length($ecofa_epi_start_date) > 0 ? $ecofa_epi_start_date : "NA"));
                }
                #my $write_epi_lot_type= (length($rfrecs->{SLICE_LOTTYPE}) > 0 ? $rfrecs->{SLICE_LOTTYPE} : (length($lot_type) > 0 ? $lot_type : "NA"));
                my $write_epi_lot_type= length($lot_type) > 0 ? $lot_type : (length($rfrecs->{SLICE_LOTTYPE}) > 0 ? $rfrecs->{SLICE_LOTTYPE} : "NA");
                my $write_slice_order= (length($rfrecs->{SLICE_ORDER}) > 0 ? $rfrecs->{SLICE_ORDER} : 
                                        (length($recs->{SLICE_ORDER}) > 0 ? $recs->{SLICE_ORDER} :
                                         (length($ecofa_slice_order) > 0 ? $ecofa_slice_order : "NA")));
                $outStr = $write_epi_source_lot . ',' . $write_epi_wafer . ',' . $write_epi_product . ',' . $write_epi_lot_type . ',' . $recs->{LOT_START_DATE} . ',' .
                          $slice . ',' . $write_global_wafer_id . ',' . $write_raw_sic_supplier . ',' . $write_epi_supplier . ',' . $write_epi_lot . ',' . $write_epi_product . ',' .
                          $write_epi_slot . ',' . $write_epi_start_date . ',' . $rfrecs->{START_LOT} . ',' . $write_slice_partname . ',' . $write_epi_lot_type . ',' .
                          $rfrecs->{PUCK_ID} . ',' . $rfrecs->{RUN_ID} . ',' .  $rfrecs->{PUCK_HEIGHT} . ',' . $write_slice_order . ',' .
                          $rfrecs->{SLICE_START_TIME};
    
                my $baseSourceLot = $write_epi_source_lot;
                $baseSourceLot =~ s/\.S$//g;
                if (length($baseSourceLot) > 1 && exists($byEpiSourceLot{$baseSourceLot}))
                {
                    if ( exists($byEpiSourceLot{$baseSourceLot}{$slice}))
                    {
                        # Don't warn for ecofa-sourced duplicates 
                        # Duplicates are likely from data sourced from BK or CZ2 epi
                        if ( $iter != 3 )
                        {
                            WARN("Duplicate slice: $slice for: $outStr");
                            WARN("Duplicate of: $byEpiSourceLot{$baseSourceLot}{$slice}");
                        }
                    }
                    else
                    {
                        $byEpiSourceLot{$baseSourceLot}{$slice} = $outStr;
                    }
                    #$byEpiSourceLot{$baseSourceLot} = $byEpiSourceLot{$baseSourceLot} . "\n" . $outStr;
                }
                elsif (length($baseSourceLot) > 1)
                {
                    my %new_hash;
                    $new_hash{$slice} = $outStr;
                    $byEpiSourceLot{$baseSourceLot} = \%new_hash;
                    #$byEpiSourceLot{$baseSourceLot} = $outStr;
                    $byEpiSourceLotDate{$baseSourceLot} = $recs->{LOT_START_DATE};
                }
                else
                {
                     WARN("No puck for slice: $slice for: $outStr");
                }
            }
            else
            {
                INFO("Slice $slice not found in refdb");
                # Build string to write to SLICE2EPI file(s)
                # FAB2SLICE/SLICE2FAB columns:
                # Original:
                # SOURCE_LOT,WAFER,FAB_PRODUCT,LOT_TYPE,LOT_START_DATE,SIC_SLICE,FAB_SRC_VENDOR,
                # EPI_LOCATION,EPI_LOT,EPI_PRODUCT,EPI_SLOT,EPI_START_DATE,EPI_SRC_VENDOR,
                # WORKSTREAM_ERASE_FLAG,LOTID,PARTNAME,LOTTYPE,PUCKID,RUNID,SUPPLIERID,PUCK_HEIGHT,CZ_LOT_START_DATE
                # New
                # SOURCE_LOT,WAFER,FAB_PRODUCT,LOT_TYPE,LOT_START_DATE,SIC_SLICE,GLOBAL_WAFER_ID
                # RAW_SIC_SUPPLIER,EPI_SUPPLIER,EPI_LOT,EPI_PRODUCT,EPI_SLOT,EPI_START_DATE,
                # LOTID,RAW_WAFER_PRODUCT,LOTTYPE,PUCKID,RUNID,PUCK_HEIGHT,SLICE_ORDER,CZ_LOT_START_DATE
                my $write_global_wafer_id = length($ecofa_global_wafer_id) > 0 ? $ecofa_global_wafer_id : 
                                             length($global_wid_guess) > 0 ? $global_wid_guess : "NA";
		my ($wgid) = $write_global_wafer_id =~ /^([^-]+)-/;
		my ($wslc) = $slice =~ /^([^-]+)-/;
                my $write_epi_source_lot = (length($ecofa_puck_boule) > 0 ? $ecofa_puck_boule : length($write_global_wafer_id) > 0 ? $wgid : $wslc ) . '.S';
                if ( $write_epi_source_lot eq "NA.S" )
                {
                    INFO( "No Puck info for slice $slice, skipping" );
                }
                else
                {
                    my $write_raw_sic_supplier= length($ecofa_raw_supplier) > 0 ? $ecofa_raw_supplier : length($me_sic_supplier) > 0 ? $me_sic_supplier : "NA";
                    my $write_epi_supplier= length($ecofa_epi_supplier) > 0 ? $ecofa_epi_supplier : "NA";
                    my $write_epi_lot= length($epi_lot) > 0 ? $epi_lot : length($ecofa_epi_lot) > 0 ? $ecofa_epi_lot : "NA";
                    my $write_epi_lot_type= length($lot_type) > 0 ? $lot_type : "NA";
                    #my $write_epi_wafer=$write_epi_supplier eq "KRJ" ? $epi_wafer : $slice;
                    my $write_epi_wafer=$slice;
	            # BK will receive epi from turnkey or consigned epi suppliers. If there is an eCofA record for the wafer, use it for epi supplier info
                    my $write_epi_product;
                    my $write_epi_slot;
                    my $write_epi_start_date;

                    if ( $iter == 1 and length($epi_supplier) > 0 && $epi_supplier ne "UWB" && length($ecofa_epi_supplier) > 0 )
                    {
                        $write_epi_supplier = (length($ecofa_epi_supplier) > 0 ? $ecofa_epi_supplier : (length($recs->{EPI_SUPPLIER}) > 0 ? $recs->{EPI_SUPPLIER} : "NA"));
                        $write_epi_product= length($ecofa_epi_partid) > 0 ? $ecofa_epi_partid : (length($epi_product) > 0 ? $epi_product : "NA");
                        $write_epi_slot= (length($ecofa_epi_slot) > 0 ? $ecofa_epi_slot : (length($epi_slot) > 0 ? $epi_slot : "NA"));
                        $write_epi_start_date= (length($ecofa_epi_start_date) > 0 ? $ecofa_epi_start_date : (length($epi_start_date) > 0 ? $epi_start_date : "NA"));
                    }
                    else
                    {
                        $write_epi_product= length($epi_product) > 0 ? $epi_product : length($ecofa_epi_partid) > 0 ? $ecofa_epi_partid : "NA";
                        $write_epi_slot= length($epi_slot) > 0 ? $epi_slot : length($ecofa_epi_slot) > 0 ? $ecofa_epi_slot : "NA";
                        $write_epi_start_date= length($epi_start_date) > 0 ? $epi_start_date : length($ecofa_epi_start_date) > 0 ? $ecofa_epi_start_date : "NA";
                    }
                    $outStr = $write_epi_source_lot . ',' . $write_epi_wafer . ',' . $write_epi_product . ',' . $write_epi_lot_type . ',' . $write_epi_start_date . ',' .
                              $slice . ',' . $write_global_wafer_id . ',' . $write_raw_sic_supplier . ',' . $write_epi_supplier . ',' . $write_epi_lot . ',' .
                              $write_epi_product . ',' . $write_epi_slot . ',' . $write_epi_start_date . ',' . 
                              'NA' . ',' . 'NA' . ',' . 'NA' . ',' .
                              'NA' . ',' . 'NA' . ',' . 'NA' . ',' . 'NA' . ',' . 'NA';
    
                    # Puck info not found in REFDB so only store info by source lot
                    my $baseSourceLot = $write_epi_source_lot;
                    $baseSourceLot =~ s/\.S$//g;
                    if (length($baseSourceLot) > 1 && exists($byEpiSourceLot{$baseSourceLot}))
                    {
                        if ( exists($byEpiSourceLot{$baseSourceLot}{$slice}))
                        {
                            # Don't warn for ecofa-sourced duplicates 
                            # Duplicates are likely from data sourced from BK or CZ2 epi
                            if ( $iter != 3 )
                            {
                                WARN("Duplicate slice: $slice for: $outStr");
                                WARN("Duplicate of $byEpiSourceLot{$baseSourceLot}{$slice}");
                            }
                        }
                        else
                        {
                            $byEpiSourceLot{$baseSourceLot}{$slice} = $outStr;
                        }
                        #$byEpiSourceLot{$baseSourceLot} = $byEpiSourceLot{$baseSourceLot} . "\n" . $outStr;
                    }
                    elsif (length($baseSourceLot) > 1 )
                    {
                        my %new_hash;
                        $new_hash{$slice} = $outStr;
                        $byEpiSourceLot{$baseSourceLot} = \%new_hash;
                        #$byEpiSourceLot{$baseSourceLot} = $outStr;
                    }
                    else
                    {
                         WARN("No puck found for slice: $slice for: $outStr");
                    }
                }
                #print $outStr . "\n";
            }
        }
        #INFO("query $iter loop number $qi end");
    }
}
}
# Query BIWMES for recently added epi-to-slice data
#print getEpiOrFabTraceSQL("epi", 1) . "\n";

# Close database connection
$refdb->disconnect();
$biwmes->disconnect();
$ecofa_db->disconnect();
$torrent->disconnect();

# Write all files to outdir
# To ensure files are not picked up until processing is finished, 
# Write to a tmp folder then rename to output destination when finished writing.
#print "byFabPuck:\n";
#use Data::Dumper;
#print Dumper \%byFabPuck;
#print "$_\n$byFabPuck{$_}\n" for (keys %byFabPuck);
#print "\nbyFabSourceLot\n";
#print "$_\n$byFabSourceLot{$_}\n" for (keys %byFabSourceLot);

#print "byEpiPuck:\n";
#print "$_\n$byEpiPuck{$_}\n" for (keys %byEpiPuck);
#print "\nbyEpiSourceLot\n";
#print "$_\n$byEpiSourceLot{$_}\n" for (keys %byEpiSourceLot);

# programs to file extensions:
# slice2fab (by puck): s2f.csv
# fab2slice (by source lot): f2s.csv
# slice2epi (by puck): s2e.csv
# epi2slice (by source lot): e2s.csv

my $writeFile = 1;
my $printOut  = 0;

if ( $printOut == 1 )
{
    print "p2f:\n\n\n\n";
}
foreach my $puck (keys %byFabPuck)
{
    my $puck2fab = $outDirTmp . "/PUCK2FAB." . $puck . "." . $currentDateTime . ".p2f.csv";
    if ( $writeFile == 1 )
    {
        #print $puck2fab . "\n";
        open OUT, ">$puck2fab" or die "cannot write $puck2fab:$!";
        push @csv_files, $puck2fab;
    }
    foreach my $slice ( keys %{$byFabPuck{$puck}} )
    {
        if ( $printOut == 1 )
        {
            print "$byFabPuck{$puck}{$slice}\n";
        }
        if ( $writeFile == 1 )
        {
            print OUT $byFabPuck{$puck}{$slice} . "\n";
        }
    }

    close OUT;
}
if ( $printOut == 1 )
{
    print "f2p:\n\n\n\n\n\n\n\n\n\n";
}
foreach my $sourceLot (keys %byFabSourceLot)
{
    my $fab2puck = $outDirTmp . "/FAB2PUCK." . $sourceLot . "." . $currentDateTime . ".f2p.csv";
    if ( $writeFile == 1 )
    {
        #print $fab2puck . "\n";
        open OUT, ">$fab2puck" or die "cannot write $fab2puck:$!";
        push @csv_files, $fab2puck;
    }
    foreach my $slice ( keys %{$byFabSourceLot{$sourceLot}} )
    {
        if ( $printOut == 1 )
        {
            print "$byFabSourceLot{$sourceLot}{$slice}\n";
        }
        if ( $writeFile == 1 )
        {
            print OUT $byFabSourceLot{$sourceLot}{$slice} . "\n";
        }
    }
    close OUT;
}
#if ( $printOut == 1 )
#{
#    print "p2e:\n\n\n\n\n\n\n\n\n\n";
#}
#foreach my $puck (keys %byEpiPuck)
#{
#    foreach my $slice ( keys %{$byEpiPuck{$puck}} )
#    {
#        if ( $printOut == 1 )
#        {
#            print "$byEpiPuck{$puck}{$slice}\n";
#        }
#        if ( $writeFile == 1 )
#        {
#            my $puck2epi = $outDirTmp . "/PUCK2EPI." . $puck . "." . $currentDateTime . ".p2e.csv";
#            #print $puck2epi . "\n";
#            open OUT, ">$puck2epi" or die "cannot write $puck2epi:$!";
#            push @csv_files, $puck2epi;
#            print OUT $byEpiPuck{$puck}{$slice} . "\n";
#        }
#    }
#    close OUT;
#}
if ( $printOut == 1 )
{
    print "e2p\n\n\n\n\n\n\n\n\n\n";
}
foreach my $sourceLot (keys %byEpiSourceLot)
{
    foreach my $slice ( keys %{$byEpiSourceLot{$sourceLot}} )
    {
        if ( $printOut == 1 )
        {
            print "$byEpiSourceLot{$sourceLot}{$slice}\n";
        }
        if ( $writeFile == 1 )
        {
            my $epi2puck = $outDirTmp . "/EPI2PUCK." . $sourceLot . "." . $currentDateTime . ".e2p.csv";
            push @csv_files, $epi2puck;
            #print $epi2puck . "\n";
            open OUT, ">>$epi2puck" or die "cannot write $epi2puck$!";
            print OUT $byEpiSourceLot{$sourceLot}{$slice} . "\n";
            close OUT;
        }
    }
}

# Copy data to archive and put in primary folder
foreach my $path (@csv_files)
{
    my $fileName = basename($path);
    my $targetFinal = "$outDir/$fileName";
    if (length($archiveDir) > 0 )
    {
        my $targetArch = "$archiveDir/$fileName";
        copy($path, $targetArch);
    }
    move($path, $targetFinal);
}

INFO("Job completed at  " . strftime("%Y-%m-%d %H:%M:%S", localtime));
