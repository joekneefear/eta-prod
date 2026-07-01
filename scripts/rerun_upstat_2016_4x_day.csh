#!/bin/csh 

if ( $#argv >= 5 ) then
   set class = $1
   set start_month = $2
   set start_day = $3
   set start_hour = $4
   set catch_up = $5
   if ( $#argv == 6 ) then
      set pgm_mask = "$6"
   endif
endif
else
   echo "USAGE: $0 class start-month start-day catch-up pgm-mask"
   echo "catch-up 1=yes 0=no"
   exit 1
endif

#set months    = ( 01 02 03 04 05 06 07 08 09 10 11 12 01 )
set months    = ( 01 01 )
#set days = ( 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 )
set days = ( 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 )
set monthdays = ( 31 28 31 30 31 30 31 31 30 31 30 31 31)
set hours = ( 00 06 12 18 )

set mi=1
set mi_n=1
set first = 1

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
         if (( $mNum == $start_month && $dd >= $start_day ) || $mNum > $start_month ) then
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
               set startStr = "2016-$months[$mi]-$days[$di] ${hours[$hi]}:00:00"
               if ( $hi == $#hours ) then
                  set endStr = "2016-$endM-$endD 00:00:00"
               else
                  set endStr = "2016-$months[$mi]-$days[$di] ${hours[$hi_n]}:00:00"
               endif
               echo "$t -- $startStr $endStr"
               if ( $#argv == 5 ) then
                  /home/dpower/exensio_171/bin/UpStat -class $class -data_from "$startStr" -data_to "$endStr" -log_dir /home/dpower/project/log production
               else
                  /home/dpower/exensio_171/bin/UpStat -class $class -pm "$pgm_mask" -data_from "$startStr" -data_to "$endStr" -log_dir /home/dpower/project/log production
               endif
               # Run for new data
               if ( $catch_up == 1 ) then
                   set t=`date +"New %Y-%m-%d %H:%M:%S"`
                   echo $t
                   /home/dpower/exensio_171/bin/UpStat -class $class -log_dir /home/dpower/project/log production
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
