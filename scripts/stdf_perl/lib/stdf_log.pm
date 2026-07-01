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
# 04-11-2000 Steve Frampton  created open_log function
#

#
# logging functions.  wlog is primary function.
# Calling these logging functions frequenctly if costly.
#

use stdf_time "ts" ;  # load function to generate time stamps

#
# logging function
#
# First parameter is used to determine if information is to be
# output.
# All other parameters are passed off to print.
#
sub wlog
{
my $level= shift ;
if ( $level <= $loglevel || $level==0 )
  {
#  print LOG &lh,$PROGRAM_NAME,": ",$record_number,": ", @_ ;
#  print LOG &lh,$record_number,": ", @_ ;
  print LOG &lh,@_ ;
  }
return(1) ; # changing return value to 0 will screw up stdf_pack/stdf_unpack
}

#
# logging header
#
{
my @path = reverse(split '/', $PROGRAM_NAME) ;

sub lh
{
return(&ts(time).': '.$path[0].': '.$in_fn.': '.$record_number.": ") ;
}
}

#
# re-open STDERR and LOG as first parameter
#
sub open_log 
{
my $log_fn=shift ;
if ((! -e $log_fn) or (-e $log_fn and -w $log_fn))
  {
  #
  # redefine STDERR as $log_fn
  #
  close(LOG) ;     # opened by stdf_use.pl
  close(STDERR) ;  # close STDERR -- ye gods!
  if (! open STDERR, ">>$log_fn")
    {
    # Oh great - we close STDERR, and now we can't reopen
    # Oh well, why not stdout for errors till we die
    print "Could not re-open STDERR\n" ;
    exit(255) ;
    }
  STDERR->autoflush(1) ;
  if (! open LOG, ">&STDERR")
    {
    print "Could not re-open LOG\n" ;
    exit(255) ;
    }
  LOG->autoflush(1) ;
  }
else
  {
  confess "Could not open log:  $log_fn" ;
  }
}


return(1) ;
