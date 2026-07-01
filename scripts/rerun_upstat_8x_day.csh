#!/bin/csh 

if ( $#argv >= 11 ) then
   set database = $1
   set class = $2
   set start_year = $3
   set start_month = $4
   set start_day = $5
   set start_hour = $6
   set end_year = $7
   set end_month = $8
   set end_day = $9
   set end_hour = $10
   
   set catch_up = $11
   if ( $#argv == 12 ) then
      set pgm_mask = "$12"
   endif
else
   echo "USAGE: $0 class start-year start-month start-day start-hour end-year end-month end-day end-hour catch-up pgm-mask"
   echo "catch-up 1=yes 0=no"
   exit 1
endif

set months    = ( 01 02 03 04 05 06 07 08 09 10 11 12 01 )
set days = ( 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 )
set monthdays = ( 31 28 31 30 31 30 31 31 30 31 30 31 31)
set hours = ( 00 03 06 09 12 15 18 21 )
set years = ( 2015 2016 )

set first = 1
foreach year ($years)
set mi=1
set mi_n=1
while ( $mi < $#months)
@ mi_n = $mi + 1
   set di=1
   set di_n=1
   while( $di <= $#days )
@ di_n = $di + 1
      set dd = `echo $days[$di] | sed 's/^0*//'`
      set nd = `echo $monthdays[$mi] | sed 's/^0*//'`
      if ( $dd >= $nd ) then
         set endD = "$days[1]"
         set endM = "$months[$mi_n]"
      else
         set endD = "$days[$di_n]"
         set endM = "$months[$mi]"
      endif
      set mNum = $mi
      set dNum = $di
      if ( $dd <= $nd ) then
           if ( ($start_year == $end_year && $year == $start_year && (( $start_month == $end_month && $mNum == $start_month && $dd >= $start_day && $dd <= $end_day ) || ($start_month != $end_month && (($mNum == $start_month && $dd >= $start_day) || ($mNum == $end_month && $dd <= $end_day) || ($mNum > $start_month && $mNum < $end_month))))) || ($start_year != $end_year && ( $year == $start_year && (($mNum == $start_month && $dd >= $start_day) || $mNum > $start_month) || ( $year > $start_year && $year < $end_year ) || ($year == $end_year && ($mNum < $end_month || ($mNum == $end_month && $dd <= $end_day)))))) then
#         if (( $mNum == $start_month && $dd >= $start_day ) || $mNum > $start_month ) then
            # Run for past data
            set hi=1
            if ( $first == 1 ) then
               set first = 0
               while ( "$hours[$hi]" != "$start_hour" )
@ hi = $hi + 1
               end
            endif
            while ( $hi <= $#hours )
@ hi_n = $hi + 1            
               set t=`date +"Past %Y-%m-%d %H:%M:%S"`
               set startStr = "$year-$months[$mi]-$days[$di] ${hours[$hi]}:00:00"
               if ( $hi == $#hours ) then
                  set endStr = "$year-$endM-$endD 00:00:00"
               else
                  set endStr = "$year-$months[$mi]-$days[$di] ${hours[$hi_n]}:00:00"
               endif
               echo "$t -- $startStr $endStr"
               if ( $#argv == 11 ) then
                  /home/dpower/exensio_171/bin/UpStat -class $class -data_from "$startStr" -data_to "$endStr" -log_dir /home/dpower/project/log_upstat_sbx $database
               else
                  /home/dpower/exensio_171/bin/UpStat -class $class -pm "$pgm_mask" -data_from "$startStr" -data_to "$endStr" -log_dir /home/dpower/project/log_upstat_sbx $database
               endif
               # Run for new data
               if ( $catch_up == 1 ) then
                   set t=`date +"New %Y-%m-%d %H:%M:%S"`
                   echo $t
                   /home/dpower/exensio_171/bin/UpStat -class $class -log_dir /home/dpower/project/log_upstat_sbx $database
               endif
#echo "$startStr    --    $endStr"
               set hi = $hi_n
            end
         endif
      endif
@ di = $di + 1
   end
@ mi = $mi + 1
end
end
