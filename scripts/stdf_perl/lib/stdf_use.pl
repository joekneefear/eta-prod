#!/usr/bin/perl
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
# 02-07-2000 Steve Frampton  Moved platform dependent stuff to stdf_unpack.pm
# 02-15-2000 Steve Frampton  Defined $FLT_MAX to 9.999E+36.  Min of PC, VMS,
#                            Solaris Platoforms
# 04-10-2000 Steve Frampton  Added $S file delimiter.
#                            Turned off buffering for file LOG.
# 06-06-2000 Steve Frampton  Changed $FLT_MAX to 1E+21.  Existing test plan will
#                            rev
# 10-25-2012 Scott Boothby   Changed LOG default destination to stdout, created ERROR handle for STDERR.
# 
# 04-02-2021 Jun   Garcia    remove to use POSIX::isprint as it was removed on newer version of perl.
$S = '/' ;  # file directory delimiter for unix
            # only used by resolve_tp
#
# General setup file that defines which libraries to use
# and initializes all of the global variables used by the
# libraries
#

use English ;

# standard perl libraries
# use Carp ;  # error messages, for some reason this does not work here
# open seems to be available but POSIX complains about it's explicit use
# use POSIX ("ceil","isprint","open","close","write") ;  # required for unpack D*n, hexdump, emir counts (r/w)
use POSIX ("ceil","close","write") ;  # required for unpack D*n, hexdump, emir counts (r/w)
use IO::Handle ;
STDERR->autoflush(1) ;
STDOUT->autoflush(1) ;

# stdf libraries
# use stdf_unpack ;

#
# Over-ride defaults of pack/unpack
# The use stdf_pack, stdf_unpack get run before this code
#
#$FLT_MAX=9.999999E+36 ;  # Min of Solaris, PC, VMS
$FLT_MAX=1E+21 ;  # EDB Standard
# used as threshold value.  If > or < , value is reset to MAX/MIN
# should be slightly > or < $FLT_MAX
$FLT_MAX_NEG_CHECK =-0.99E+21  ;
$FLT_MAX_POS_CHECK =0.99E+21  ; 

use stdf_pack ;
use stdf_unpack ;
use stdf_read ;
use stdf_write ;
use stdf_convert ;
use stdf_time; 
use stdf_gen ;
use stdf_log ;
use edb_defs ; 

#
# global variables
#

# logging
$err_fmt = "" ;

# default files
open INPUT, "<&STDIN" or confess "Could not open STDIN\n" ;
open OUTPUT, ">&STDOUT" or confess "Could not open STDOUT for OUTPUT\n" ;
open ERROR, ">&STDERR" or confess "Could not open STDERR for ERROR\n" ;
#open LOG, ">&STDERR" or confess "Could not open STDERR\n" ;
open LOG, ">&STDOUT" or confess "Could not open STDOUT for LOG\n" ;
ERROR->autoflush(1) ;
LOG->autoflush(1) ;

return(1) ;
