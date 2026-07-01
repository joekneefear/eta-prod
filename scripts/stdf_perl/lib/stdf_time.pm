#
# FSC Perl STDF Libraries
#
# Confidential Property of Fairchild Semiconductor Corperation
# (c) Copyright Fairchild Semiconductor Corperation, 1999
# All rights reserved
#
# MODIFICATION HISTORY:
#
# DATE       WHO             DESCRIPTION
# __________ ______________  __________________________________________________
# 11-02-1999 Steve Frampton  Original.  Contact Information:
#                            (207) 273-3364
#                            sframpto@fairchildsemi.com,
#                            sframpto@midcoast.com
# 04-06-2000 Steve Frampton  Changed stdf_mktime to use Time::Local
# 04-??-2000 Steve Frampton  Changed Time::Local back - Y2K bug
# 04-28-2000 Steve Frampton  Changed ts to use local, not gm
# 05-10-2000 Steve Frampton  Added stdf_time
#

#
# Time related functions used for stdf functions
# Some of these functions may not be in use here, but were
# included from the nam2stdf converter for completenes.
#

#
# Create a time stamp suitable for file names
#
sub ts
{
my $time = shift ;
(my $sec, my $min, my $hour, my $day, my $month, my $year,())
 = localtime($time) ;
$month++;
$year += 1900 ;
return(sprintf("%04d%02d%02d%02d%02d%02d",
  $year, $month, $day, $hour, $min, $sec)) ;
}

#
# stdf_time
# returns number of seconds since epoc, but in local time, not gwtime
# won't work for YY < 2000
#
use Time::Local qw/timegm/ ;
sub stdf_time
{
return timegm(localtime()) ;
}


#
#  stdf_mktime
#
#  Ported from stdf library to perl
#  Fixed year 2000 problem 
#  Should be valid for 1970 up to 2070
#  Year can be provided in a two digit format, but four digit is recommended
#
sub  stdf_mktime
{
my $num_days    = 0,
my $num_hours   = 0,
my $num_seconds = 0,
my $status      = 0;

#
# Parameter order to support nam format
#

# my $mm = $_[0] + 1 ;	# This was a bug in the c code from the port
my $mm = $_[0] ;
my $dd = $_[1] ;
my $yy = $_[2] ;
my $hh = $_[3] ;
my $mi = $_[4] ;
my $ss = $_[5] ;
my $i ;

if ( $yy < 100 ) # see if a two digit date was provided
  {
  if ( $yy > 70 ) # see if it is in the year 2000
	{
	$yy = $yy + 1900 ; # assume 1900 century
	}
  else
	{
	$yy = $yy + 2000 ; # assume 2000 century
	}
  }
#
# use the perl libraries instead of this other junk
#
#use Time::Local ;
#$yy=$yy-1900 ;
#$num_seconds = timegm ($ss, $mi, $hh, $dd, $mm-1, $yy) ;
#return( $num_seconds );

#
# The following loop sums the number of days that have elapsed between 
# 1970 and the START of the current year.  Leap years need to be accounted 
# for, so a well known algorithm was borrowed from K & R.  It goes 
# as follows :
# If the year IS evenly divisable by 4 AND NOT evenly divisable by 100 OR
# IS evenly divisable by 400, then the year is a leap year (366 days).
# Otherwise, obviously it's a normal 365-day year.
# 
    for ($i = 1970; $i < $yy; $i++)
		{
         if ($i % 4 == 0 && $i % 100 != 0 || $i % 400 == 0)
			{
             $num_days += 366;
			}
         else
			{
             $num_days += 365;
			}
		}

#
# Now, make a call to DAY_OF_YEAR to get the number of days elapsed so far 
# for this year.  Add this to our running total.
#
    $num_days += &day_of_year($yy, $mm, $dd) - 1;

#
# Now break down days to hours (days * 24), and hours to seconds (seconds * 3600).
# Then include the seconds from the time string.
#

    $num_hours = ($num_days * 24) + $hh;

    $num_seconds = ($num_hours * 3600) + ($mi * 60) + $ss;

return( $num_seconds );
} # stdf_mktime



#
# Ported from stdf library
#
sub day_of_year
{
my $i ;
my $leap ;
my $year=$_[0] ;
my $month=$_[1] ;
my $day=$_[2] ;

#
# Now sum the days for each month, up to but not including the current 
# month.  The days from this month are already included in the DAY 
# argument.
#
    $leap = $year % 4 == 0 && $year % 100 != 0 || $year % 400 == 0;

    for ($i = 1; $i < $month; $i++)
		{
		if ($i == 2)
			{
			if ($leap == 1)
				{
				$day += 29;
				}
			else
				{
				$day += 28;
				}
			}
		else
			{
			if ( $i==1 || $i==3 || $i==5 || $i==7 || $i==8 || $i==10 || $i==12 )
				{
				$day +=31 ;
				}
			else
				{
				$day +=30 ;
				}
			}
		}
return ( $day );
}

return(1) ;

