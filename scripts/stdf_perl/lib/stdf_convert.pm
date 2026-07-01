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
# 05-08-2000 Steve Frampton  Changed to support STDFPL 104
# 09-15-2006 Steve Frampton  Added %skip_convert variable
#                            which disables unpack and convert if set
#                            for the record type.
#                            Performance enhancement for sampling.

#
# User Routines to convert data
#

my %skip_convert = () ;  # user defined variable to disable unpacking and conversion.  Performance enhancement
# $skip_unpack{15}=1 ;  # would disable unpacking and convert of PTR and FTR records

#
# Main file processing loop
# Reads stdf file
#   Unpacks records into stdf record structures within name space in.
#   Calls convert_NNN functions created by user.
#     NNN is the record name, eg MIR, MRR
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
  #
  # skip_convert is a performance enhancement, generally used for sampling situations.
  # skip_convert value determines when the next records of $rec_typ will be unpacked and converted.
  #
  if (! defined($main::skip_convert{$rec_typ}))
	{
  	$rc = &stdf_convert( $total_bytes_read, $rec_len, $rec_typ, $rec_sub, $buf) ;
	}
  elsif ($main::skip_convert{$rec_typ} <= 0)
	{
	$rc = &stdf_convert( $total_bytes_read, $rec_len, $rec_typ, $rec_sub, $buf) ;
	}
  else
	{
	$main::skip_convert{$rec_typ} -- ;
	}
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

$fname=$in::get_record_name{$rec_typ.'_'.$rec_sub} ;
$cname='convert_'.$fname ;
$uname='in::unpack_'.$fname ;

if ($fname eq '' )
  {
  warn &lh, "Don't know this record type" ;
  stdf_write_hex( $total_bytes_read, $rec_len, $rec_typ, $rec_sub, $buf, \*STDERR );
  if (! $debug) { exit 1 ; }
  }
elsif ( ! defined(&{$cname}))
  {
  if ($debug)
    {
    warn &lh, "No user function: $cname to convert input record" ;
    # create the function to suppress warnings for other records
    eval "sub $cname {}" ;
    }
  else
    {
    # if no warning, then simply ignore the record
    # assumption is that user does not need to process the record
    # speeds execution as record is only unpacked if needed
    }
  }
else # user function was found
  {
  if (!defined(&{$uname}) ) # don't know how to unpack
    {
    warn &lh, "Don't know how to unpack record" ;
    stdf_write_hex( $total_bytes_read, $rec_len, $rec_typ, $rec_sub, $buf, \*STDERR );
    if (! $debug) { exit 1 ; }
    }
  else
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
# scan a file and create a hash for a record type
# assumes namespace in for unpack and record variables
#
# example:
# %in::tsr_hash = create_record_hash(\*INPUT,\%in::tsr_hash, 'tsr', 'test_num' ) ;
# will create a hash of hashes %in::tsr_hash
# 
# might be useful create multiple hashes with a single pass
# but no apparent need right now
#
# This routine may be broken ... It is not currently in use.
#
sub create_record_hash
{
my ($status, $rec_len, $rec_typ, $rec_sub, $buf, $stdf_ver) ;
my $total_bytes_read ;
my $input = shift ;  # input file handle
my $record_hash = shift ; # hash for created values
my $record_name = shift ; # record name 

# variable to use for hash key, less $ or namespace
my $key_name = shift ;
my $fname ; # variable used for function prefix
my $uname ; # variable used for unpack function name
my $vname ; # global variable that unpack function returns
#
# read first record
#
($status, $rec_len, $rec_typ, $rec_sub, $buf ) = read_first_rec( $input, $stdf_ver ) ;
$total_bytes_read = $status ;

#
# check the version of the input specification
# remove this since it is specific to version 4 ??
#
if ($stdf_ver!=4)
  { confess &lh, "STDF Version 4 file expected,  Version $stdf_ver found" ; }

#
# create name of unpack function and check for it
#
$uname='in::unpack_'.uc($record_name) ;
if (!defined(&{$uname}) ) # don't know how to unpack
  { confess &lh, "Don't know how to unpack record, no function $uname" ; }

#
# create name of variable that unpack function returns
#
$vname='in::'.lc($record_name) ;

#
# read the remaining records
#
while ( $status )
  {
  $fname=${'in::get_record_name'}{$rec_typ.'_'.$rec_sub} ;
  # if we have correct record, then create hash
  if (lc($fname) eq $record_name)
    {
    &{$uname}(\$buf, \%{$vname}) ;  # unpack into %$vname
    my $key = $in::{$record_name}{$key_name} ; # create the key into the hash
#    $in::tsr_hash{$key} = { %in::tsr } ; # an explicid example for tsr record
    ${$record_hash}{$key} = { %{$vname} } ; # create the hash of hashes
    }
  ($status, $rec_len, $rec_typ, $rec_sub, $buf) = read_rec( $input ) ;
  $total_bytes_read += $status ;
  }
}



#
# for assigning required values
# assign $_[0] = $_[1]
# if $_[1] is undefined or = to $_[2] return non-zero
#
sub setr
{
# $_[0] is the value to set
# $_[1] is the to assign
# $_[2] is the default value
#
# The eq should work for numeric comparisons as well as string
# but, "1.00" is not equal to "1" !
# so be careful with useage
#
defined ($_[0]=$_[1]) && ! ($_[0] eq $_[2]) && return(1) ;
return (0) ;
}

#
# for assigning optional values
# if second parameter is defined, set first parameter to second parameter
# otherwise, set first parameter to third parameter and return
#
sub seto
{
return defined($_[0]=$_[1]) || defined($_[0]=$_[2]) ;
}

#
# Pad characters to end of string
#
sub pad
{
my $st = shift ;
my $pd = substr(shift,0,1) ; # only pad with one character
my $len = shift ;
if ( ! defined($len) ) { $len = 20 } ;
return $st . ($pd x ($len-length($st))) ;
}

return(1)

