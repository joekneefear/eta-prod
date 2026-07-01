#!/bin/bash
#
# Extract slice, puck, and starting lot ID from CZ PROMIS TORRENT DB.
#
# MODIFICATION HISTORY
#
# WHEN      WHO WHAT
# --------- --- ------------------------------------------
# 09-Mar-22 SAB Initial. 
# 14-Apr-22 SAB Updated SQL to handle upcoming changes to CZ2 SiC tracking and improve parsing of puck ID from lot comment
# 14-Jun-22 SAB Fix existing CZ2 extract script to resolve conflicts with wafer-level tracking changes
# 21-Jul-22 SAB Added Global Wafer ID and slice order (note: global wafer ID = slice for CZ lots)
# 18-Mar-24 SAB Fixes to support 200mm material and address gaps in TE and NS type lots.
# 10-Jun-24 SAB Changes to improve CZ2 tracking and handle both 1:1 and 1:24 lot:wafer tracking in torrent DB.
# 02-Oct-24 SAB Complete SQL overhaul to work around source data issues with tracking data in TORRENT DB.
isError=0 
product_like=""

if [ -z "${REFERENCE_DATA_DIR}" ]
then
   export REFERENCE_DATA_DIR=""
   isError=1 
fi

if [ ! -d $REFERENCE_DATA_DIR ] 
then
   isError=1 
fi

if [ $# -ne 5 ] 
then
   isError=1
fi

if [ $isError -eq 0 ] 
then
   if [ "$2" != "CZT_PASSWORD" ] || [ "$2" == "" ] 
   then
      isError=1 
   fi
fi

if [ $isError -ne 0 ] 
then
   echo "ARG1=$1||ARG2=$2||ARG3=$3"
   echo "USAGE: $(basename $0) db-user db-password db-sid relative-days-start relative-days-end"
   echo " " 
   echo "Environment variable REFERENCE_DATA_DIR must be set to a valid directory"
   exit 1
fi

ora_user="$1"
if [ "$2" == "CZT_PASSWORD" ] 
then
   ora_pass="appuser"
else
   ora_pass="$2"
fi

if [ "$3" == "TEROTORR" ] 
then
   connectionString="TEROTORR"
else 
   ora_sid="$3"
   ora_port=1534
   connectionString="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${ora_ip})(PORT=${ora_port}))(CONNECT_DATA=(SID=${ora_sid})))"
fi

relStart=$4
relEnd=$5

dateCode=`date +"%Y%m%d_%H%M%S"`
#rootDir=/apps/exensio_data/reference_data2
#archiveDir=/export/home/dpower/project/work/sboothby/archive
archiveDir=/apps/exensio_data/archives-yms/reference_data/slice
rootDir=$REFERENCE_DATA_DIR
tmpDir=$rootDir/tmp
outFile=$rootDir/CZSlice2Puck-${dateCode}.slice
outFileTmp=$tmpDir/CZSlice2Puck-${dateCode}.slice.tmp
outFileTmp2=$tmpDir/CZSlice2Puck-${dateCode}.gwid.slice.tmp
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
select 'SLICE|PUCK_ID|RUN_ID|SLICE_SOURCE_LOT|START_LOT|FAB_WAFER_ID|FAB_SOURCE_LOT|SLICE_START_TIME|SLICE_PARTNAME|SLICE_LOTTYPE|SLICE_SUPPLIERID|PUCK_HEIGHT|SLICE_ORDER|GLOBAL_WAFER_ID' from dual;
with evtime_lots as 
(
  select /*+ MATERIALIZE INDEX(a PK_ACTL)*/ distinct aev.lotid
  from torrent.actlevcount aev
  join actl a on aev.LOTID = a.lotid
  join torrent.catg cg on a.partname = cg.partprcdname and a.partversion = cg.PARTPRCDVERSION and cg.categorytype = 'P' and cg.catgnumber = '07' and cg.CATEGORY = 'SIC'
  where a.curmainqty <= 1 and a.startmainqty = 1 and evendmainqty <= 1
    and evtype = 'NEOS' and stage = 'KCLASER'
    and evtime between sysdate + (1*$relStart) and sysdate + (1*$relEnd)
  union
  select /*+ MATERIALIZE INDEX(h PK_HIST) */ distinct hev.lotid 
  from torrent.histevcount hev
  join hist h on h.lotid = hev.lotid and h.timerev = hev.timerev
  join actl ac on ac.lotid = hev.lotid
  join torrent.catg cg on h.partname = cg.partprcdname and h.partversion = cg.PARTPRCDVERSION and cg.categorytype = 'P' and cg.catgnumber = '07' and cg.CATEGORY = 'SIC'
  where h.curmainqty <= 1 and ac.startmainqty = 1 and evendmainqty <= 1
    and evtime between sysdate + (1*$relStart) and sysdate + (1*$relEnd)
    and evtype = 'NEOS' and h.stage = 'KCLASER'
)
, lot_1_1_activity as
(
select /*+ MATERIALIZE */ distinct apv.parmval as SLICE, v.lotid, v.evtime, v.timerev, v.partname, v.lottype
, dense_rank() over (partition by apv.parmval order by apv.parmname desc, v.evtime, v.timerev) as dr
from evtime_lots l
join torrent.event_view v on l.lotid = v.lotid
join TORRENT.ACTLLOTPARMCOUNT apv on l.lotid =apv.lotid and apv.parmname in ('\$SIC_SCRIBEBS', '\$SIC_GLWAFID') 
where v.evendmainqty <= 1
  and v.evtype = 'NEOS' /* Normal End of Step*/
  and v.stage = 'KCLASER' 
)
, lot_trace_1_1 as 
(
select CONNECT_BY_ROOT a.lotid as start_lot, a.lotid, a.parentid
, LEVEL  as lvl, dense_rank() over (partition by CONNECT_BY_ROOT a.lotid order by LEVEL DESC) as dr
from actl a
CONNECT BY nocycle a.lotid = prior a.parentid
start with a.lotid in (select lotid from evtime_lots)
)
, start_lot_trace_1_1 as 
(
select /*+ MATERIALIZE */ lt.start_lot, lt.parentid as puck_lot, ap.parmval as puckid
from lot_trace_1_1 lt
join torrent.actllotparmcount ap on lt.parentid = ap.lotid and ap.parmname = '\$SIC_LOTXTAL'
where dr = 1
)
, lot_comp_activity as
(
select /*+ MATERIALIZE */ distinct ps.parmval as SLICE, po.PARMVAL as start_lotid, v.prodfamily
, TRIM(REGEXP_SUBSTR(v.evvariant_complete, '[^' || CHR(7) || ']+', 1, 1)) as COMPID
from torrent.event_view v 
join torrent.walpparmcount p on TRIM(REGEXP_SUBSTR(v.evvariant_complete, '[^' || CHR(7) || ']+', 1, 1)) = p.compid
join torrent.walpparmcount ps on p.compid =  ps.compid and ps.parmname = '\$SIC_SCRIBEBS'
left join torrent.walpparmcount po on p.compid =  po.compid and po.parmname = '\$SIC-ORIGIN_LOT'
where v.PRODFAMILY = 'SIC'
  and v.evtime between sysdate + (1*$relStart) and sysdate + (1*$relEnd)
  and length(TRIM(REGEXP_SUBSTR(v.evvariant_complete, '[^' || CHR(7) || ']+', 1, 1)))>1 
  and v.evtype in ('MIDC', 'CCPR', 'IDCO')
  and v.evvariant_complete like '%'||CHR(7)||'A'||CHR(7)||'\$SIC_SCRIBEBS%' 
)
, comp_multiples as
(
select /*+ MATERIALIZE */ distinct a.slice, p.compid, a.start_lotid
from lot_comp_activity a
join torrent.walpparmcount p on a.slice = p.parmval and p.PARMNAME = '\$SIC_SCRIBEBS'
where not exists (select 1 from lot_1_1_activity act where act.slice = a.slice)
)
, comp_defs as
(
select /*+ MATERIALIZE */ lotid, TRIM(REGEXP_SUBSTR(hev.evvariant, '[^' || CHR(7) || ']+', 1, 1)) as compid, evtime, timerev
from torrent.histevcount hev
where hev.evtype = 'CCPR' and hev.evtime > to_date('20240615', 'YYYYMMDD')
and hev.evvariant like '%'||CHR(7)||'A'||CHR(7)||'\$SIC_SCRIBEBS%' 
)
, actl_info as
(
select /*+ MATERIALIZE */ aps.parmval as slice
     , v.evtime
     , v.timerev
     , apsl.PARMVAL as slotid
     , v.partname
     , v.lotid
     , v.lottype
     , dense_rank() over (partition by aps.parmval order by evtime, timerev, apsl.PARMVAL) as dr
from lot_comp_activity lca
join torrent.actllotparmcount aps on aps.parmval = lca.SLICE
join actl a on aps.lotid = a.lotid 
join torrent.event_view v on a.lotid = v.lotid
left join torrent.actllotparmcount apsl on aps.lotid = apsl.lotid and apsl.parmname in ( '\$SIC_SLOTID')
where a.startmainqty = 1 and v.evendmainqty <= 1
  and aps.parmname in ('\$SIC_SCRIBEBS', '\$SIC_GLWAFID') 
  and v.evtype = 'NEOS' and v.stage ='KCLASER' 
)
, actl_info_lot_trace_1_1 as 
(
select CONNECT_BY_ROOT a.lotid as start_lot, a.lotid, a.parentid
, LEVEL  as lvl, dense_rank() over (partition by CONNECT_BY_ROOT a.lotid order by LEVEL DESC) as dr
from actl a
CONNECT BY nocycle a.lotid = prior a.parentid
start with a.lotid in (select lotid from actl_info)
)
, actl_info_start_lot_trace_1_1 as 
(
select /*+ MATERIALIZE */ lt.start_lot, lt.parentid as puck_lot
from actl_info_lot_trace_1_1 lt
where dr = 1
)
, lot_comp_multiple_comp_history as
(
select /*+ MATERIALIZE */ 
       distinct m.slice, m.compid, coalesce(t.puck_lot, start_lotid) as start_lotid, coalesce(v.partname, h.partname) as partname
     , cd.lotid, coalesce(v.lottype, h.lottype) as lottype, coalesce(v.evtime, cd.evtime) as evtime, v.slotid as slotid
     , dense_rank() over (partition by m.slice order by v.evtime, cd.evtime , v.timerev, cd.timerev) as dr
from comp_multiples m
left join comp_defs cd on m.compid = cd.compid 
left join hist h on h.lotid = cd.lotid and h.timerev = cd.timerev
/* also check 1:1 to see if wafer was converted to 25:1 from 1:1.  Use slot ID and event time from 1:1 if split occurred during 1:1 processing*/
left join actl_info v on m.slice = v.slice and v.dr = 1
left join actl_info_start_lot_trace_1_1 t on t.start_lot = v.lotid
)
, all_sics as
(
select distinct 
       ls.slice
     , coalesce(ap.parmval, pk.parmval)    as PUCK_ID
     , ls.start_lotid                      as START_LOT
     , ls.evtime                           as SLICE_START_TIME
     , ls.partname                         as SLICE_PARTNAME
     , ls.lottype                          as SLICE_LOTTYPE
     , coalesce(pss.parmval, a.supplierid) as SLICE_SUPPLIERID
     , a.startmainqty                      as PUCK_HEIGHT
     , pn.parmval                          as SLICE_ORDER
     , coalesce(ls.slotid, psl.parmval)    as SLOTID
     , cast(1 as int)                      as d_rank
from lot_comp_multiple_comp_history ls
join torrent.actl a on ls.start_lotid = a.lotid
left join torrent.walpparmcount pk  on ls.compid = pk.compid  and pk.parmname  = '\$SIC_LOTXTAL'  /* puck */
left join torrent.walpparmcount pn  on ls.compid = pn.compid  and pn.parmname  = '\$SIC_ORDERID'
left join torrent.walpparmcount psl on ls.compid = psl.compid and psl.parmname = '\$SIC_SLOTID'
left join torrent.walpparmcount pss on ls.compid = pss.compid and pss.parmname = '\$SIC_SUPPLYID'
left join torrent.actllotparmcount ap on ls.start_lotid = ap.lotid and ap.parmname  = '\$SIC_LOTXTAL' /* Origin lot puck, if defined */
where ls.dr = 1
union all
select distinct
       la.slice
     , coalesce(sl.puckid, apk.parmval)     as PUCK_ID
     , sl.puck_lot                          as START_LOT
     , la.evtime                            as SLICE_START_TIME
     , la.partname                          as SLICE_PARTNAME
     , la.lottype                           as SLICE_LOTTYPE
     , coalesce(apsp.parmval, a.supplierid) as SLICE_SUPPLIER_ID
     , a.startmainqty                       as PUCK_HEIGHT
     , coalesce(apn.parmval, wpo.parmval)   as SLICE_ORDER
     , coalesce(apsl.parmval, wpsl.parmval) as SLOTID
     , dense_rank() over (partition by la.slice order by asl.starttime, aps.parmname desc) as d_rank
from lot_1_1_activity la
join start_lot_trace_1_1 sl on la.lotid = sl.start_lot
join torrent.actl a on sl.puck_lot = a.lotid
join torrent.actllotparmcount aps  on la.lotid = aps.lotid  and aps.parmname  in ('\$SIC_SCRIBEBS', '\$SIC_GLWAFID')
left join torrent.actllotparmcount apk  on la.lotid = apk.lotid  and apk.parmname  = '\$SIC_LOTXTAL'  /* puck */
left join torrent.actllotparmcount apn  on la.lotid = apn.lotid  and apn.parmname  = '\$SIC_ORDERID'
left join torrent.actllotparmcount apsl on la.lotid = apsl.lotid and apsl.parmname = '\$SIC_SLOTID'
left join torrent.actllotparmcount apsp on la.lotid = apsp.lotid and apsp.parmname = '\$SIC_SUPPLYID'
/* Just check walpparmcount in case it defines slice order and/or slot but actllotparmcount doesn't.*/
left join torrent.walpparmcount wps  on la.slice = wps.parmval and wps.parmname  = '\$SIC_SCRIBEBS'
left join torrent.walpparmcount wpo  on wps.compid = wpo.compid and wpo.parmname = '\$SIC_ORDERID'
left join torrent.walpparmcount wpsl on wpsl.compid = wps.compid and wpsl.parmname = '\$SIC_SLOTID'
left join torrent.actl asl on wpsl.lotid = asl.lotid
where la.DR = 1
)
, final as 
(
select distinct SLICE 
     , PUCK_ID
     , START_LOT
     , SLICE_START_TIME
     , SLICE_PARTNAME
     , SLICE_LOTTYPE
     , case when SLICE_PARTNAME like 'SIC_S_31%' or SLICE_PARTNAME like 'SIC_S_11%' then 'SICC'
            when SLICE_PARTNAME like 'SIC_S_04%'                                    then 'SKSILTRN'
            when SLICE_PARTNAME like 'SIC_S_05%'                                    then 'II-VI'
            when SLICE_PARTNAME like 'SIC_S_09%' or SLICE_PARTNAME like 'SIC_S_08%' then 'TANKEBLU'
            when SLICE_PARTNAME like 'SIC_S_10%'                                    then 'SHOWASUB'
            when SLICE_PARTNAME like 'SIC_S_11%' or SLICE_PARTNAME like 'SIC_S_31%' then 'SICC'
            when SLICE_PARTNAME like 'SIC_S_14%'                                    then 'TYSIC'
            when SLICE_PARTNAME like 'SIC_S_15%'                                    then 'SANANIC'
            when SLICE_PARTNAME like 'SIC_S_16%' or SLICE_PARTNAME like 'SIC_S_29%' then 'SYNLIGHT'
            when SLICE_PARTNAME like 'SIC_S_17%'                                    then 'SOITEC'
            when SLICE_PARTNAME like 'SIC_S_18%'                                    then 'TONYTECH'
            when SLICE_PARTNAME like 'SIC_S_19%'                                    then 'SICOXS'
            when SLICE_PARTNAME like 'SIC_S_20%' or SLICE_PARTNAME like 'SIC_S_32%' then 'SEMISIC'
            when SLICE_PARTNAME like 'SIC_S_01%' or SLICE_PARTNAME like 'SIC_S_01%' then 'CREE'
            when SLICE_PARTNAME like 'SIC_S_21%' or SLICE_PARTNAME like 'SIC_S_33%' then 'GSCS' /* Summit*/
            when SLICE_PARTNAME like 'SIC_S_22%'                                    then 'SUPERSIC'
            when SLICE_PARTNAME like 'SIC_S_24%'                                    then 'NINGBO'
            when SLICE_PARTNAME like 'SIC_S_25%'                                    then 'TAISIC'
            when SLICE_PARTNAME like 'SIC_S_26%'                                    then 'PALLIDUS'
            when SLICE_PARTNAME like 'SIC_S_27%' or SLICE_PARTNAME like 'SIC_S_28%' then 'CECCS'
            when SLICE_PARTNAME like 'SIC_S_30%'                                    then 'CZ2'
            when SLICE_PARTNAME like 'SIC_S_06%' or SLICE_PARTNAME like 'SIC_S_07%' 
              or SLICE_PARTNAME like 'SIC_S_12%' or SLICE_PARTNAME like 'SIC_S_13%' 
              or SLICE_PARTNAME like 'SIC_S_23%' or SLICE_PARTNAME = 'W6350K01' 
              or regexp_like(SLICE_PARTNAME, '^SIC6SDEV[123]\$') or SLICE_SUPPLIERID = 'GTAT' then 'UWH'
            else SLICE_SUPPLIERID end as SLICE_SUPPLIERID     
     , PUCK_HEIGHT
     , SLICE_ORDER
     , SLOTID
from all_sics
where d_rank = 1
)
select distinct slice
||'|'||puck_id
||'|'||case when SLICE_SUPPLIERID = 'UWH' then substr(puck_id, 1, length(puck_id)-1) else puck_id end
||'|'||case when SLICE_SUPPLIERID = 'UWH' then substr(puck_id, 1, length(puck_id)-1) else puck_id end || '.S'
||'|'||start_lot
||'| '
||'| '
||'|'||to_char(slice_start_time, 'YYYY-MM-DD HH24:MI:SS') 
||'|'||slice_partname
||'|'||slice_lottype
||'|'||coalesce(slice_supplierid, ' ')
||'|'||puck_height
||'|'||case when regexp_like(SLICE_ORDER, '^\d+\$') then cast(SLICE_ORDER as integer) else 0 end
from final 
where puck_id is not null and slice is not null 
order by 1;
quit;
eof

sqlplus -s ${ora_user}/${ora_pass}@"${connectionString}" @${tmpScript} > $logFile

if [ -f "$tmpScript" ] 
then
   /bin/rm $tmpScript
fi

if [ -f $outFileTmp ] 
then
  # Look up global wafer ID from eCofA.  If not found, use the slice ID.  Only do this if the scribe ID is > 11 characters.  Otherwise gwid=scribeid.
   while read f; do
     slice=$(echo "$f" | cut -d\| -f1)
     if [[ "$slice" == "SLICE" ]]; then
        #echo "First line: $f"
        line="$f"
     elif (( ${#slice} > 11)); then
        # Look up slice in eCofA DB.
        sql="select global_wafer_id from cofcadm.wafer where wafer_scribe_id='$slice';"
        #echo "Looking up slice: $slice ($sql)"
        sqlOut=$(echo "select global_wafer_id from cofcadm.wafer where wafer_scribe_id='$slice';" | sqlplus -s $ECOA_USER/$ECOA_PASS@GRWEBPRD | tr "\n" " ")
        # output must contain GLOBAL_WAFER_ID and ------------ or not valid.
        if [[ $sqlOut == *"GLOBAL_WAFER_ID"* ]]  && [[ $sqlOut == *"---------"* ]]; then
           globalWaferID=$(echo "$sqlOut" | cut -d\   -f4)
           echo "Found GWID for $slice : $globalWaferID"
           line="$f|$globalWaferID"
        else
           echo "No GWID found for $slice"
           line="$f|$slice"
        fi
     else
        line="$f|$slice"
     fi

     echo "$line" >> $outFileTmp2
   done < $outFileTmp

  # copy to archive first
  if [ -f $outFileTmp2 ] && [ -d $archiveDir ]; then
    b_name=$(basename "$outFileTmp2" | sed 's/\(.*\)\..*/\1/')
    /bin/cp -p $outFileTmp2 $archiveDir/$b_name
    /bin/gzip $archiveDir/$b_name
    echo "$archiveDir/$b_name"
  fi
  /bin/mv $outFileTmp2 $outFile
fi

