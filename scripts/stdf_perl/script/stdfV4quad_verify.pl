#!/usr/bin/perl
$adv_debug = 1 ;
#
# FSC Perl STDF Libraries
#
# Confidential Property of Fairchild Semiconductor Corperation
# (c) Copyright Fairchild Semiconductor Corperation, 1999
# All rights reserved
#
# Diagnose Missing PIR/PRR record issues with V4 files
#
# MODIFICATION HISTORY:
#
# DATE       WHO             DESCRIPTION
# __________ ______________  __________________________________________________
#
# 08-15-2006 Steve Frampton  Created


$useage = 'verify_V4.pl V4FileName
' ;

#
# default log level
#
$loglevel = 3 ;

#
# Load libraries
#
use Carp ;  # error messages - does not work within stdf_use.pl
# set path to executable for libraries
use FindBin ; 
use lib "$FindBin::Bin" ; # set up path for libraries the same as script
use lib $ENV{'STDF_PERL_LIB'} ; # look for libraries in this directory
use lib $ENV{'ENV_CONV_SCRIPT'} ; # look for libraries in this directory
use English ;


#
# contents of stdf_use, less stdf_convert.pm
#

# standard perl libraries
# use Carp ;  # error messages, for some reason this does not work here
# open seems to be available but POSIX complains about it's explicit use
# use POSIX ("ceil","isprint","open","close","write") ;  # required for unpack D*n, hexdump, emir counts (r/w)
use POSIX ("ceil","isprint","close","write") ;  # required for unpack D*n, hexdump, emir counts (r/w)
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
# use stdf_convert ;
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
open OUTPUT, ">&STDOUT" or confess "Could not open STDOUT\n" ;
open LOG, ">&STDERR" or confess "Could not open STDERR\n" ;
LOG->autoflush(1) ;


#
# Load Specifications
#
$in_spec='stdfV4.spec';
#
# stdfV4.pl and stdfPL.pl are loaded over
# routines from generate_all
#

{
package in ;
use Carp ;
if ( !eval(&::generate_all($::in_spec )))
  { confess $@ ; }
require 'stdfV4.pl' ;
}



# Open Datafile




#
# Parse command line arguments
#
$cmd = $PROGRAM_NAME." ". join(" ", @ARGV) ;  # save cmd line
my $DFileName ;

if ($ARGV[0])
  {
  $in_fn = shift ;
  if ( $in_fn eq $tp_fn )
    { confess &lh, "Inputfilename=TestPlanfilename: $in_fn " ; }
  if ($in_fn =~ /\.gz$/)
	{
        open INPUT, "gzcat $in_fn|" or confess &lh, "Could not open input file name $in_fn\n" ;
	my @path = split /\//,$in_fn;
	$DFileName = $path[$#path] ;
	$DFileName =~ s/\.gz$// ;
	}
  else
	{
  	open INPUT, "<$in_fn" or confess &lh, "Could not open input file name $in_fn\n" ;
	}
  }
binmode INPUT ;

#
# call loop to convert records
#
convert_file(\*INPUT) ;

close DATAFILE;
close TPDATAFILE;

exit 0;

#
# Mapping subroutines that get called within convert_file calling tree
# From here to end of file
#

sub convert_MIR  # empty sub required to force Engine to unpack
                 # see convert_SDR
{
for (my $site=1;$site <=4;$site++) { $pir{$site} = "" ; }
for (my $site=1;$site <=4;$site++) { $prr{$site} = "" ; }
for (my $site=1;$site <=4;$site++) { $test{$site} = "" ; }
for (my $site=1;$site <=4;$site++) { $part_id{$site} = "" ; }
for (my $site=1;$site <=4;$site++) { $missing_pir{$site} = 0 ; }
for (my $site=1;$site <=4;$site++) { $missing_prr{$site} = 0 ; }
$reading_prr = 0 ;
$reading_pir = -1 ;

$unpack_test_records = 1 ;
$spec_nam=$in::mir{test_cod}.$in::mir{spec_nam} ;
print "V3P+,V4 File,,SITE_ID=1,,SITE_ID=2,,SITE_ID=3,,SITE_ID=4,,Total\n" ;
print "SPEC_NAM,Name,Rec Type,REC_NO,PART_ID,REC_NO,PART_ID,REC_NO,PART_ID,REC_NO,PART_ID,Missing\n" ;
}

sub convert_PIR # forces record to be unpacked, see convert_PRR
{
$reading_prr = 0 ;
my $site_num=$in::pir{site_num} ||confess &lh, 'pir{site_num} not defined'; # U*1, U*1
$pir{$site_num} = $record_number ;
if ($reading_pir == 0)
	{
	print "$spec_nam,$DFileName,TEST,$test{1},,$test{2},,$test{3},,$test{4},\n" ;
	print "$spec_nam,$DFileName,PRR,$prr{1},$part_id{1},$prr{2},$part_id{2},$prr{3},$part_id{3},$prr{4},$part_id{4}\n\n" ;
	for (my $site=1;$site <=4;$site++) { $missing_prr{$site}++ if (!$prr{$site}); }
	
	for (my $site=1;$site <=4;$site++) { $prr{$site} = "" ; }
	for (my $site=1;$site <=4;$site++) { $part_id{$site} = "" ; }
	for (my $site=1;$site <=4;$site++) { $test{$site} = "" ; }
	}
$reading_pir = 1 ;
}

sub convert_TEST  # any test record
{
$reading_test = 0 ;
my $site_num=$in::test{site_num} ||confess &lh, 'test{site_num} not defined'; # U*1, U*1
$test{$site_num} = $record_number if ($test{$site_num} eq "") ;
}


sub convert_PRR
{
$reading_pir = 0 ;
my $site_num=$in::prr{site_num} ||confess &lh, 'pir{site_num} not defined'; # U*1, U*1
$prr{$site_num} = $record_number ;
$part_id{$site_num} = $in::prr{part_id} ;
if ($reading_prr == 0)
	{
	print "$spec_nam,$DFileName,PIR,$pir{1},,$pir{2},,$pir{3},,$pir{4},,\n" ;
	for (my $site=1;$site <=4;$site++) { $missing_pir{$site}++ if (!$pir{$site}); }
	for (my $site=1;$site <=4;$site++) { $pir{$site} = "" ; }
	}
$reading_prr = 1 ;
}

sub convert_MRR
{
if ($reading_pir == 1)
	{
	print "$spec_nam,$DFileName,PIR,$pir{1},,$pir{2},,$pir{3},,$pir{4},,\n" ;
	}
if ($reading_prr == 1)
	{
	print "$spec_nam,$DFileName,PRR,$prr{1},$part_id{1},$prr{2},$part_id{2},$prr{3},$part_id{3},$prr{4},$part_id{4}\n" ;
	}
print "\n" ;
my $missing_pir =  $missing_pir{1}+$missing_pir{2}+$missing_pir{3}+$missing_pir{4} ;
my $missing_prr =  $missing_prr{1}+$missing_prr{2}+$missing_prr{3}+$missing_prr{4} ;
#print "$spec_nam,$DFileName,Missing PIR Count,$missing_pir{1},,$missing_pir{2},,$missing_pir{3},,$missing_pir{4},,$missing_pir\n" ;
#print "$spec_nam,$DFileName,Missing PRR Count,$missing_prr{1},,$missing_prr{2},,$missing_prr{3},,$missing_prr{4},,$missing_prr\n" ;
#print "$spec_nam,$DFileName,Total Missing PIR Count,,,,,,,,,$missing_pir\n" ;
#print "$spec_nam,$DFileName,Total Missing PRR Count,,,,,,,,,,$missing_prr\n" ;
}


#
# modified from stdf_convert.pm
# to partially unpack test records
# and call convert_test
#

sub convert_file
{
my ($status, $rec_len, $rec_typ, $rec_sub, $buf, $stdf_ver) ;
my $total_bytes_read ;
my $input = shift ;  # pointer to file handle
my $rc=0 ; # pass back up
$record_number = 0 ;  # global

#
# read first record
#
($status, $rec_len, $rec_typ, $rec_sub, $buf) = read_first_rec( $input, $stdf_ver ) ;
$total_bytes_read = $status ;


#
# check the version of the input specification
# assumes that the input specification has
# a default value for the FAR record
# For V3 and PL specs, make sure EMIR/MIR, FAR have same stdf_ver
#
# Technically, we only support 202, but 104 is hard coded here
# This is to support old MRL_TO_STDF output
# use 104 at your own risk !
#
if ( $stdf_ver != ${in::init{far}{stdf_ver}} && $stdf_ver != 104 && $stdf_ver != 200 && $stdf_ver != 201 && $stdf_ver != 202 )
  { warn &lh, "STDF Version ",${in::init{far}{stdf_ver}}," file expected,  Version $stdf_ver found" ; }
#
# read the remaining records
#
while ( $status )
  {
  $record_number++ ;  # global variable for the record_number
  $rc = &stdf_convert( $total_bytes_read, $rec_len, $rec_typ, $rec_sub, $buf) ;
  ($status, $rec_len, $rec_typ, $rec_sub, $buf) = read_rec( $input, $stdf_ver ) ;
  $total_bytes_read += $status ;
  }
return($rc) ;

}


#
# calls user defined conversion routine if it exists
# otherwise log a message
#
sub stdf_convert
{
my $total_bytes_read = shift ;
my $rec_len = shift ;
my $rec_typ = shift ;
my $rec_sub = shift ;
my $buf = shift ;
# my $debug = shift ; # = 0 fatal if record type is unknown
                    #     fatal if no unpack function exists
		    # = 1 prints warning if user conversion
		    #     function is undefined for record
my $fname ; # name in uppercase for function names
my $vname ; # name in lowercase for hash names
my $cname ; # function name to convert
my $uname ; # function name to unpack
my $rc=0 ; # pass return code back up

#
# If it is a test record,
# unpack up to the site_num
# and call convert_TEST routine
#
if ($rec_typ == 15 && $unpack_test_records) # 
	{
	#
	# unpack test record to site_num
	#
	unpack_TEST(\$buf, \%in::test) ;
	#
	# pass control to user function
	#
	$rc = convert_TEST ;
	}
else
	{ 
	$fname=$in::get_record_name{$rec_typ.'_'.$rec_sub} ;
	$cname='convert_'.$fname ;
	$uname='in::unpack_'.$fname ;

	if (defined(&{$cname}))
		{
		#
		# unpack record
		#
		$vname=lc($fname) ;
		&{$uname}(\$buf, \%{'in::'.$vname}) ;
		#
		# pass control to user function
		#
		$rc = &{$cname} ;
		}
	}
return($rc) ;
}

#
# unpack to the site_num
# borrowed from unpack_PTR
#
sub unpack_TEST
{
	my $record = shift ;
	my $test = shift ;
	undef(${$test}{rec_len});
	undef(${$test}{rec_typ});
	undef(${$test}{rec_sub});
	undef(${$test}{test_num});
	undef(${$test}{head_num});
	undef(${$test}{site_num});
	my $i=0 ;  # index into ${$record}
	my $bufflen = length(${$record}) ;  # length of data including header
	my @_U2 ;
	# header
	($_U2[$::U2_0], $_U2[$::U2_1] , 
	  ${$test}{rec_typ},
	  ${$test}{rec_sub})
	  = unpack($::U2s.$::U1.$::U1, substr(${$record},$i,4) ) ;
	${$test}{rec_len} = unpack($::U2,pack($::U2s, @_U2)) ;
	$i += 4 ;
	# test_num
	($bufflen-$i < 4) && return(0) ;
	my @_U4 ;
	($_U4[$::U4_0], $_U4[$::U4_1], $_U4[$::U4_2], $_U4[$::U4_3])
	  = unpack($::U4s, substr(${$record},$i,4) ) ; 
	${$test}{test_num} = unpack($::U4,pack($::U4s, @_U4)) ;
	$i += 4 ;
	# head_num
	($bufflen-$i < 1) && return(0) ;
	(${$test}{head_num})
	  = unpack($::U1, substr(${$record},$i,1) ) ; 
	$i += 1 ;
	# site_num
	($bufflen-$i < 1) && return(0) ;
	(${$test}{site_num})
	  = unpack($::U1, substr(${$record},$i,1) ) ; 
	$i += 1 ;
	return(0) ;
}
