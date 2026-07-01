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
# 02-03-2000 Steve Frampton  Added documentation concerning
#                            Infinity.
#                            $float_infinity was multipled by 16
#                            just to be sure it is large enough
#                            to pack as infinity.
# 02-09-2000 Steve Frampton  Added B*0 as valid data type to support GDR
#                            Allow N*1 with 0 length data as '0' - GDR
#                            Wrote stdf_pack_array function.
# 02-15-2000 Steve Frampton  Force R*4 Infinity to MAX on PC Platform
#                            as this is lowest #.  Truncated sig dig
#                            to 4.  Actual change made in stdf_use.pl
#

#
# Module to make the translation from stdf Data Type Codes to
# binary format native to the platform.
#

#
# Ordering is tuned for stdf+ datalog files 
# Even small changes here may have a significant performance
# impact.  Especially calls to other routines.
#

#
# Constants as defined in /usr/include/values.h
# or similar in float.h
#
# private posix function float will retrieve
#  I just hate having to discover undocumented features !
#
# Should cover IEEE systems
# Need to be redefined for VMS if running on VMS
# and values would overflow
#
# also could have been defined in stdf_unpack.pm
#

use POSIX ;
#use POSIX ();
#use POSIX qw(:float_h);

if (0) {
if (! defined($::FLT_MAX_EXP)) {
   $FLT_MAX_EXP = &POSIX::constant("FLT_MAX_EXP") ; 
}
if (! defined($::FLT_RADIX))
  { $FLT_RADIX = &POSIX::constant("FLT_RADIX") ; }
if (! defined($::DBL_MAX_EXP))
  { $DBL_MAX_EXP = &POSIX::constant("DBL_MAX_EXP") ; }
}
if (! defined($::FLT_MAX)) {
    #$FLT_MAX = &POSIX::constant("FLT_MAX") ; 
    $FLT_MAX = 0;
  }
#
# Because of unpacking, and packing, max can
# change, and we not longer recognize as max
# +- delta to compensate
#
if ( ! defined($::FLT_MAX_NEG_CHECK))
  {
#  $FLT_MAX_NEG_CHECK = -$FLT_MAX/2 ;
  $FLT_MAX_NEG_CHECK = -0 ;
  }
if ( ! defined($::FLT_MAX_POS_CHECK))
  {
#  $FLT_MAX_POS_CHECK = $FLT_MAX/2  ; 
   $FLT_MAX_POS_CHECK = 0;
  }

  

#
# works on solaris without the * 16
#
#$float_Infinity = ($FLT_RADIX ** $FLT_MAX_EXP)*16 ;
#$double_Infinity = $FLT_RADIX ** $DBL_MAX_EXP ; 


#
# stdf_gen creates routines labled as stdf_pack_XXX
# where XXX is a record type for example, stdf_pack_FAR
# The stdf_packXXX routine, then calls stdf_pack.
#
# If stdf_pack encounters an undefined value, then the record
# packing stops.  Use this feature to truncate stdf records.
# Make sure you don't forget to define all of the values you
# want packed !
#
sub stdf_pack
{
my $template = shift ;  # list of space delmited stdf codes
my $buff = shift ;      # existing buffer will be appended to
# @_     is used for the data structure variables.
my $struct0 ;           # temporary value for ${$@_[0]}

my $code ;              # temporary loop variable that contains
                        # an element of @code             

my @codes = split(/ /, ${$template}) ; # STDF data codes in @codes
my $rc=0 ;

#
# make sure that number of codes matches number of variables
#
if ($#codes != $#_)
  {
  confess_pack( "number of codes = $#codes not equal number of variables = $#_" ) ;
  }
#
# loop thru and unpack all @codes into @_
#
for $code (@codes)
  {
  # break out of loop if undefined variable
  # this allows writting out a truncated stdf record as allowed by V4
  # for V3+, always make sure that defined variables are passed in !
  defined(${$_[0]}) || last ;
    # get type and size. examples C*n, C*12
    (my $type, my $size) = split (/\Q*\E/, $code) ;
    $rc ++ ;  # count the number of codes, only used to return error
#    print "pack $type $size \n" ;
#    $size=lc($size);  # tolerate C*N
    if ( $code eq 'U*1' )
      {
      ( ${$_[0]} <= 0xFF ) || confess_pack("$code overflow ${$_[0]}") ;
      ${$buff} .= pack("C", ${$_[0]}) ;
      }
    elsif ( $type eq 'B' ) # begin B*
      {
      $struct0 = ${$_[0]} ;
      ( $struct0 =~ /^[01]*$/) || confess_pack("$code invalid bit string: \"$struct0\"" ) ;
      if ( $size eq 'n') # variable length binary
        {
	my $size = ceil(length($struct0)/8.0) ;
	my $bitsize = $size*8 ;
	( $size <= 255 ) || confess_pack("$code bit length $size of $struct0 is greater than 255 or = 0" );
	# perl pack with 'B' type does not properly pad significant leading 0
	# calculate number of signficant 0 bits to match $bitsize
	$struct0 =~ s/^0+// ; # strip off leading significant bits of 0
	my $num_of_pad_bits = $bitsize-length($struct0) ;
	# form padding for most significant 0 bits
	my $sig_bit_pad = "0"x$num_of_pad_bits ;
	#
	# first pack the length in bytes
	# then cat the translation from string to bytes
        ${$buff} .=   pack("C", $size)
	            . pack('B'. $bitsize, $sig_bit_pad.$struct0 ) ;
	}
      elsif ( $size < 255 && $size > 0) # Fixed length binary
        {
	my $bitsize = $size*8 ; # the number of bits to be packed
	# perl pack with 'B' type does not properly pad significant leading 0
	$struct0 =~ s/^0+// ; # strip off leading significant bits of 0
	# calculate number of signficant 0 bits to match $bitsize
	my $num_of_pad_bits = $bitsize-length($struct0) ;
	($num_of_pad_bits >= 0 ) || confess_pack("$code bit overflow $struct0 " );
	# form padding for most significant 0 bits
	my $sig_bit_pad = "0"x$num_of_pad_bits ;
	# pack the size in bytes as a bitstring
        ${$buff} .= pack('B'. $bitsize, $sig_bit_pad . $struct0 ) ;
	}
      elsif ( $size == 0) # GDR Pad Bit, any data is ignored
        {
	${$buff} .= pack("C",0) ;
	}
      else
        {
	confess_pack("$code stdf data type not supported" );
	}
      } # end B*
    elsif ( $code eq 'U*2' )
      {
      ( ${$_[0]}<= 0xFFFF ) || confess_pack("$code overflow ${$_[0]}" );
      ${$buff} .= pack("S", ${$_[0]}) ;
      }
    elsif ( $code eq 'R*4' )
      {
      my $f ;
      #
      # The strings Infinity and -Infinity are specifc to solaris
      # see test_pack utility for other platforms.
      # NT uses -NaN and NaN
      # Windows 95 uses 1.#INF and - 1.#INF, which won't pack
      # properly.  Also, SAS can't read infinity
      #
      # Before changing this, note similar functionality in
      # stdfPL.pl and stdfV4_no_vms.pl.  It should all be consistent
      #
      if ((${$_[0]} eq 'Infinity')
        || (${$_[0]} eq 'NaN')
	|| (${$_[0]} eq '1.#INF' )
	|| (${$_[0]} > $FLT_MAX_POS_CHECK ))
        {
#	wlog($log_IEEEfloat_pack_error, "$code:  packing Infinity\n") ;
        $f = pack("f", $FLT_MAX) ;
        ${$buff} .= $f ;
	}
      elsif ((${$_[0]} eq '-Infinity')
        || (${$_[0]} eq '-NaN')
	|| (${$_[0]} eq '-1.#INF' )
	|| (${$_[0]} < $FLT_MAX_NEG_CHECK ))
        {
#	wlog($log_IEEEfloat_pack_error, "$code:  packing -Infinity\n") ;
        $f = pack("f", -$FLT_MAX) ;
        ${$buff} .= $f ;
	}
      else
        {
        $f = pack("f", ${$_[0]}) ;
        ${$buff} .= $f ;
	}
      } 
    elsif ( $code eq 'U*4' )
      {
      ( ${$_[0]}<= 0xFFFFFFFF ) || confess_pack("$code overflow ${$_[0]}" );
      ${$buff} .= pack("I", ${$_[0]}) ;
      }
    elsif ( $type eq 'C')   # begin C* type processing
      {
      $struct0 = ${$_[0]} ;  # make a copy, since we modify 
      if ( $size eq 'n') # variable length string
        {
	$struct0 =~ s/ +$// ; # remove trailing spaces
#	( length($struct0) > 255 ) && ($struct0 = substr($struct0,1,254)) ;
	( length($struct0) > 255 ) && ($struct0 = substr($struct0,0,254)) ;
        ${$buff} .= pack("C",length($struct0)) . $struct0 ;
	}
      elsif ( $size < 255 && $size > 0 ) # Fixed length string
        {
	# pad with spaces for fixed length string
	$struct0 = $struct0.(' ' x ($size-length($struct0))) ;
        ${$buff} .= pack('A'.$size, $struct0) ;
	}
      else
        {
	confess_pack("$code stdf data type not supported" );
	}
      }  # end C* type processing
    elsif ( $code eq 'I*2' )
      {
      ( ${$_[0]}<= 0xFFFF/2 ) || confess_pack("$code overflow ${$_[0]}" );
      ( ${$_[0]}>= -0xFFFF/2-1 ) || confess_pack("$code underflow ${$_[0]}" );
      ${$buff} .= pack("s", ${$_[0]}) ;
      }
    elsif ( $code eq 'I*1' )
      {
      ( ${$_[0]}<= 0xFF/2 ) || confess_pack("$code overflow ${$_[0]}" );
      ( ${$_[0]}>= -0xFF/2-1 ) || confess_pack("$code underflow ${$_[0]}" );
      ${$buff} .= pack("c", ${$_[0]}) ;
      }
    elsif ( $code eq 'I*4' )
      {
      ( ${$_[0]}<= 0xFFFFFFFF/2 ) || confess_pack("$code overflow ${$_[0]}" );
      ( ${$_[0]}>= -0xFFFFFFFF/2-1 ) || confess_pack("$code underflow ${$_[0]}" );
      ${$buff} .= pack("i", ${$_[0]}) ;
      }
    elsif ( $code eq 'D*n' )
      {
      ( ${$_[0]}=~ /^[01]*$/) || confess_pack("$code invalid bit string: \"${$_[0]}\"" );
      $size = length(${$_[0]}) ;
      ! ( $size  > 65535 || $size < 0 ) || confess_pack("$code bit length $size of ${$_[0]}is greater than 65535 or < 0" );
      my $byte_size = ceil($size/8) ;
      my $stored_bit_size = $byte_size * 8 ;
      # perl pack with 'B' type does not properly pad significant leading 0
      # calculate number of signficant 0 bits to match $bitsize
      my $num_of_pad_bits = $stored_bit_size-length(${$_[0]}) ;
      # form padding for most significant 0 bits
      my $sig_bit_pad = "0"x$num_of_pad_bits ;
      ${$buff} .= pack('S',$size) . pack('B'.$stored_bit_size, $sig_bit_pad.${$_[0]}) ;
      }
    elsif ( $code eq 'R*8' )
      # Defined in STDF V4 standard
      # Only allowed in GDR records, although may not be used.
      # unpack does not support all platforms 
      {
      my $f = pack("d", ${$_[0]}) ;
      my $r = unpack("d", $f) ;
      my $ok_delta = ${$_[0]} * 0.05 ;  # if we are off by >5%, assume overflow
      (abs(${$_[0]}-$r) <= abs($ok_delta) ) || confess_pack("$code overflow ${$_[0]}" );
      ${$buff} .= $f ;
      } 
    elsif ( $type eq 'N' )
      #
      # Native Perl Nibble is implemented using hex digit string
      # each character in that string represents a nibble
      # bit (nibble of) deviation from stdf spec
      # used only with V4 MPR record
      # user must keep track of nibble length by doing a length on
      # the returned value.
      # The length is stored in anothe fields, e.g. V4 MPR.RTN_ICNT
      # assuming that the size will only ever be a U*2
      #
      # We don't exactly follow the standard, because of complexity of
      # writting to the nearest byte.  We use for example N*65 instead of
      # 65xN*1
      #
      # The length is passed as a formality
      # It does not really need to be for pack
      # but we do this to be consistent with unpack, which needs
      # the length.
      #
      {
      $struct0 = ${$_[0]} ;
      my $len = length($struct0) ;
      if (length($struct0) != $size )
        {
	if (length($struct0) == 0 && $size == 1)
	  {
	  $struct0 = '0' ;  # Allow a default of 0 for B*1 - GDR consistency
	  }
	else
	  {
          confess_pack("$code nibble string length: $len not equal $size of format specifier:  $struct0" );
	  }
	}
      ! ( $size  > 65535 || $size < 0 ) || confess_pack("$code nibble length $size of $struct0 is greater than 65535 or < 0" );
      $struct0 = lc ( $struct0) ; # convert to lower case
      ( $struct0 =~ /^[0-9a-f]*$/) || confess_pack("$code invalid nibble (hex) string: \"$struct0\"" );
      ${$buff} .= pack('H'.$size, $struct0) ;
      }
    elsif ( $code eq 'V*n' )
      {
      confess_pack("$code stdf data type not supported" );
      }
    elsif ( $size eq 'f') # Does not seem to be part of an STDF 4 record
      {
      confess_pack("$code stdf data type not supported" );
      }
    else
      {
      confess_pack("$code stdf data type not supported" );
      }
  shift @_ ;
  }
return(0) ;
}

#
# wrapper for Carp to either exit or return
# default to to exit
# application can set return_pack_error to pass errors back up the stack
#
sub confess_pack
{
wlog(0, @_) ;
confess ;
}

sub stdf_pack_array
{
my $code = $_[0] ;
my $record = $_[1] ;
my $array_count = $_[2] ;
my $array = $_[3] ;
my $j ;
my $rc=0 ;

for ($j=0; $j < ${$array_count}; $j++)
  {
  $rc = stdf_pack($code, $record, \${${$array}}[$j] ) ;
  }
return($rc) ;
}

return(1) ;
