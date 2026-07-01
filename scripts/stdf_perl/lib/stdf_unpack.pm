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
# 02-02-2000 Steve Frampton  Fixed I*4 and R*8 bugs. 
# 02-03-2000 Steve Frampton  Added documentation concerning
#                            Infinity.
# 02-07-2000 Steve Frampton  Initialization Related Changes:
#                             Added init_swap_cnv.
#                             Added primitive types from stdfV4.pl.
#                              Moved from stdf_read_first
#                              Moved implied begin block to
#                              top of file.
#                              Moved platform checking stuff
#                               from stdf_use to implied begin
#                               block at top of file
#                            Added specific xpFlt4VAXtoIEEE
#                             R*4 VMS functions.  Ported 
#                             from util C lib
# 02-10-2000 Steve Frampton  Added stdf_unpack_array function
# 02-15-2000 Steve Frampton  Force R*4 Infinity to MAX on PC Platform
#                            as this is lowest #.  Truncated sig dig
#                            to 4.  Actual change made in stdf_use.pl
#                            Force higher values to MAX.
#

#
# Module to make the translation from binary formats to
# internal perl representation.
#
# stdf_gen creates routines labled as stdf_unpack_XXX
# where XXX is a record type for example, stdf_unpack_FAR
# The stdf_unpackXXX routine, then calls stdf_unpack.
#
# If stdf_pack encounters an end of buffer, then the record
# unpacking stops.  Use this feature to truncate stdf records.
# Make sure you don't forget to define all of the values you
# want when you pack !
#
#
# Nearly all of the platform dependent (both file and platform)
# live in this module.
#

#
# Constants as defined in /usr/include/values.h
# or similar in float.h
#
# also could have been defined in stdf_pack.pm
#

use POSIX() ;

if (0) {
if (! defined($::FLT_MAX))
  { $FLT_MAX = &POSIX::constant("FLT_MAX") ; }
if (! defined($::DBL_MAX))
  { $DBL_MAX = &POSIX::constant("DBL_MAX") ; }
}

#
# Because of unpacking, and packing, max can
# change, and we not longer recognize as max
# +- delta to compensate
#
if ( ! defined($::FLT_MAX_NEG_CHECK))
  {
  $FLT_MAX_NEG_CHECK = -$FLT_MAX/2 ;
  }
if ( ! defined($::FLT_MAX_POS_CHECK))
  {
  $FLT_MAX_POS_CHECK = $FLT_MAX/2  ; 
  }


#
# set up running platform depencencies
#
# platform dependent variables
if (lc($OSNAME) eq 'solaris')
  { $running_cpu_type = 1 ; }
elsif (lc($OSNAME) eq 'linux' )
  { $running_cpu_type = 2 ; }
elsif (lc($OSNAME) =~ /.*win.*/)
  { $running_cpu_type = 2 ; }
else
  { 
  $running_cpu_type = 2 ; print STDERR "don't know $OSNAME, assuming intel\n" ;
  }

#
# some constants
# to be compared with $main::vms_conversion
#
$VMS2IEEE = 1 ;
$IEEE2VMS = 2 ;

#
# Init to something reasonable
# This will change after stdf_read_first
#
$file_cpu_type = $running_cpu_type ;  
$do_int_byte_swap = 0 ;
$do_real_byte_swap = 0 ;

#
# primitive types  used by stdfV4.pl and stdfPL.pl and ???
# Any type that could be byte swapped is unpacked as character string first
# then converted, hence the 's' after some of the types.
#
{
$U1 = "C" ;
$U2 = "S" ;
$U2s = "CC" ;
$U4 = "I" ;
$U4s = "CCCC" ;
$I1 = "c" ;
$I2 = "s" ;
$I2s = "CC" ;
$I4 = "i" ;
$I4s = "CCCC" ;
$R4 = "f" ;
$R4s = "CCCC" ;
$B1 = "B8" ;
$C7 = "A7" ;
$C = 'a' ;
}

#
# set globals
# do_int_byte_swap, do_real_byte_swap, main::vms_conversion variables
# based on
# $cpu_type - usually from file
# $running_cpu_type - determined within stdf_use
#
sub init_swap_cnv
{
$cpu_type = shift ;  # usually called with $file_cpu_type
$running_cpu_type = shift ;
if ($cpu_type == 0 and $running_cpu_type==1 )    # Running on Solaris, VMS File
  {
  $do_int_byte_swap = 1 ;
  $do_real_byte_swap = 0 ;
  $main::vms_conversion = $VMS2IEEE ;
  }
elsif ($cpu_type == 2 and $running_cpu_type==1 )   # Running on Solaris, PC File
  {
  $do_int_byte_swap = 1 ;
  $do_real_byte_swap = 1 ;
  $main::vms_conversion = 0 ;
  }
elsif ($cpu_type == 1 and $running_cpu_type==2 )   # Running on PC, Solaris File
  {
  $do_int_byte_swap = 1 ;
  $do_real_byte_swap = 1 ;
  $main::vms_conversion = 0 ;
  }
elsif ($cpu_type == 0 and $running_cpu_type==2 )   # Running on PC, VMS File
  {
  $do_int_byte_swap = 0 ;
  $do_real_byte_swap = 1 ;
  $main::vms_conversion = $VMS2IEEE ;
  }
elsif ($cpu_type == $running_cpu_type )   # Native, no translations
  {
  $do_int_byte_swap = 0 ;
  $do_real_byte_swap = 0 ;
  $main::vms_conversion = 0 ;
  }
else
  {
  confess &lh, "cpu_type conversion $cpu_type to $running_cpu_type not supported. REC_TYP: $rec_typ REC_SUB: $rec_sub CPU_TYPE: $cpu_type STDF_VER:  $stdf_ver";
  }
}

#
# initialize byte ordering for pack/unpack
# all output variables are global
# Called by read_first_rec
#
sub init_byte_order
{
my $int_swap = shift ;
my $real_swap = shift ;
if ($int_swap)
  {
  $U2_0 = $I2_0 = 1 ;
  $U2_1 = $I2_1 = 0 ;

  $U4_0 = $I4_0 = 3 ;
  $U4_1 = $I4_1 = 2 ;
  $U4_2 = $I4_2 = 1 ;
  $U4_3 = $I4_3 = 0 ;
  }
else 
  {
  $U2_0 = $I2_0 = 0 ;
  $U2_1 = $I2_1 = 1 ;

  $U4_0 = $I4_0 = 0 ;
  $U4_1 = $I4_1 = 1 ;
  $U4_2 = $I4_2 = 2 ;
  $U4_3 = $I4_3 = 3 ;
  }

if ($real_swap)
  {
  $R4_0 = 3 ;
  $R4_1 = 2 ;
  $R4_2 = 1 ;
  $R4_3 = 0 ;

  $R8_0 = 7 ;
  $R8_1 = 6 ;
  $R8_2 = 5 ;
  $R8_3 = 4 ;
  $R8_4 = 3 ;
  $R8_5 = 2 ;
  $R8_6 = 1 ;
  $R8_7 = 0 ;
  }
else
  {
  $R4_0 = 0 ;
  $R4_1 = 1 ;
  $R4_2 = 2 ;
  $R4_3 = 3 ;

  $R8_0 = 0 ;
  $R8_1 = 1 ;
  $R8_2 = 2 ;
  $R8_3 = 3 ;
  $R8_4 = 4 ;
  $R8_5 = 5 ;
  $R8_6 = 6 ;
  $R8_7 = 7 ;
  }
}


#
# Damn Global variables !
# Calls stdf_unpack, but does not do any byte translations
# A slight bit of a hack, this makes stdf_unpack non-reentrant with
# mixed platforms !
#
# Used by resolve_tp.
#
sub stdf_native_unpack
{
my $sav_file_cpu_type=$file_cpu_type ;
$file_cpu_type=$running_cpu_type ;

init_byte_order(0, 0) ;
my @values = stdf_unpack(@_) ;
$file_cpu_type=$sav_file_cpu_type ;

init_byte_order($do_int_byte_swap, $do_real_byte_swap) ;
return( @values ) ;
}

#
# In line code so that it runs faster, not to look pretty
#
# Ordering is tuned for STDFV4 datalog files
#
#
# VMS floating point conversions for IEE taken from util xplatfunc.c
# VMS floating point conversions to or from vms assume non-vms is IEE
#
# caller may want to check for undefined return values, which
# occurs if there is not enought buffer for all of the codes.
#
# need:  use POSIX (ceil) ; external
#
#
sub stdf_unpack
{
my $template = $_[0] ;  # list of space delmited stdf codes
my $buff = $_[1] ;      # buffer of data to convert
                        # significant overhead with the size of buff
			# both with passing in an substr functions
			# don't pass in a buff that is larger than what is
			# going to be unpacked.
my $i = ${$_[2]} ;	        # index into $buff that is passed back on return	
my @struct = @_[3..$#_] ; # list of values that will be passed back
my $code ;              # temporary loop variable that contains
                        # an element of @code             
my @array ;
my $array_cnt ;

my @codes = split(/ /, ${$template}) ; # STDF data codes in @codes

my $bufflen = length($$buff) ;

my $j = 0 ;

#
# loop thru and unpack all @codes into @struct
#
for $code (@codes)
  {
  $array_cnt = 0 ;
  #
  # check for kx
  #
#  if (substr($code,0,1) eq 'k')
#    {
#    ($array_cnt, my $tmp_code) = split(/\Qx\E/, $code ) ;
#    confess, &lh, "$code stdf data type not supported" ;
#    $code=$tmp_code ;
#    }
    # get type and size. examples C*n, C*12
    (my $type, my $size) = split (/\Q*\E/, $code) ;
#    $size=lc($size) ;  # tolerate C*N as well as C*n
#    print "unpack $type $size \n" ;
    if ( $code eq 'U*1' )
      {
      ($bufflen-$i < $size) && last ;
      ${$struct[$j]} = unpack("C",substr($$buff,$i,1)) ;
      $i += $size ;
      }
    elsif ( $type eq 'C')   # begin C* type processing
      {
      if ( $size eq 'n') # variable length string
        {
        ($bufflen-$i < 1) && last ;
        $size = unpack("C",substr($$buff,$i,1)) ;
	$i += 1 ;
        ($bufflen-$i < $size) && last ;
	$str =  substr($$buff,$i,$size) ;
	$str =~ s/ +$// ; # remove trailing spaces
        ${$struct[$j]} = $str ;
	$i += $size ;
	}
      elsif ( $size < 255 && $size >= 0 ) # Fixed length string
        {
        ($bufflen-$i < $size) && last ;
	my $str =  substr($$buff,$i,$size) ;
	$str =~ s/ +$// ; # remove trailing spaces
        ${$struct[$j]} = $str ;
	$i += $size ;
	}
      else
        {
	confess, &lh, "$code stdf data type not supported" ;
	}
      }  # end C* type processing
    #
    # begin R*4
    #
    elsif ( $code eq 'R*4' )
      {
      ($bufflen-$i < $size) && last ;
      if (! $main::vms_conversion )  # assume an IEEE platform or VMS file + VMS platform
        {
        my @real ;
        ($real[$R4_0], $real[$R4_1], $real[$R4_2], $real[$R4_3]) = unpack("CCCC",substr($$buff,$i,4)) ;
        ${$struct[$j]}=unpack("f",pack("CCCC", @real)) ;
        $i += 4 ;
        }
      elsif ($main::vms_conversion == $VMS2IEEE)
          {  # if vax file and not running on vax
	  #
	  # if it turns out this section of code gets run often,
	  # then inline function will run much faster
	  # for now, code maintenance wins.
	  #
          ${$struct[$j]} = xpFlt4VAXtoIEEE (substr($$buff,$i,4)) ;
	  $i += 4 ;
	  }
      elsif ($main::vms_conversion == $IEEE2VMS)
          {
          # coded, but not tested.
#          ${$struct[$j]} = xpFlt4IEEEtoVAX (substr($$buff,$i,4)) ;
#          $i += 4 ;
          confess ("$code stdf data conversion to vax not supported, values set to default of 0\n" ) ;
	  }
      else
          {
          confess ("$code stdf data conversion not supported\n" ) ;
	  }
      #
      # The strings Infinity and -Infinity are specifc to solaris
      # see test_pack utility for other platforms.
      # Windows 95 uses 1.#INF and - 1.#INF, which won't pack
      # properly.  Also, SAS can't read infinity.
      # 
      # Please note similar functionality in stdfPL.pl and stdfV4_no_vms.pl
      # should be consistent.
      # 

     if ((${$struct[$j]} eq 'Infinity')
        || (${$struct[$j]} eq 'NaN')
	|| (${$struct[$j]} eq '1.#INF' )
	|| (${$struct[$j]} > $FLT_MAX_POS_CHECK ))
        {
#	wlog($log_IEEEfloat_unpack_error, "$code:  upacking Infinity\n") ;
        ${$struct[$j]} = $FLT_MAX ;
	}
      elsif ((${$struct[$j]} eq '-Infinity')
        || (${$struct[$j]} eq '-NaN')
	|| (${$struct[$j]} eq '-1.#INF' )
	|| (${$struct[$j]} < $FLT_MAX_NEG_CHECK ))
        {
#	wlog($log_IEEEfloat_unpack_error, "$code:  upacking -Infinity\n") ;
        ${$struct[$j]} = -$FLT_MAX ;
	}
      } # end R*4
    elsif ( $type eq 'B' ) # begin B*
      {
      if ( $size eq 'n') # variable length binary
        {
        ($bufflen-$i < 1) && last ;
        $size = unpack("C",substr($$buff,$i,1)) ;
        $i += 1 ;
        ($bufflen-$i < $size) && last ;
        ${$struct[$j]}=unpack('B'.($size*8), substr($$buff,$i,$size) ) ;
        $i += $size ;
	}
      elsif ( $size < 255 && $size >= 0) # Fixed length binary
        {
        ($bufflen-$i < $size) && last ;
        ${$struct[$j]}=unpack('B'.($size*8), substr($$buff,$i,$size) ) ;
        $i += $size ;
	}
      else
        {
	confess &lh, "$code stdf data type not supported" ;
	}
      } # end B*
    elsif ( $code eq 'I*1' )
      {
      ($bufflen-$i < $size) && last ;
      ${$struct[$j]}=unpack("c",substr($$buff,$i,1)) ;
      $i += $size ;
      }
    elsif ( $code eq 'U*2' )
      {
      ($bufflen-$i < $size) && last ;
      my @_U2 ;
      ($_U2[$U2_0], $_U2[$U2_1]) = unpack("CC",substr($$buff,$i,2)) ;
      ${$struct[$j]}=unpack("S",pack("CC", @_U2)) ;
      $i += $size ;
      }
    elsif ( $code eq 'U*4' )
      {
      ($bufflen-$i < $size) && last ;
      my @_U4 ;
      ($_U4[$U4_0], $_U4[$U4_1], $_U4[$U4_2], $_U4[$U4_3]) = unpack("CCCC",substr($$buff,$i,4)) ;
      ${$struct[$j]}=unpack("I",pack("CCCC", @_U4)) ;
      $i += $size ;
      }
    elsif ( $code eq 'I*2' )
      {
      ($bufflen-$i < $size) && last ;
      my @_I2 ;
      ($_I2[$I2_0], $_I2[$I2_1]) = unpack("CC",substr($$buff,$i,2)) ;
      ${$struct[$j]}=unpack("s",pack("CC", @_I2)) ;
      $i += $size ;
      }
    elsif ( $code eq 'I*4' )
      {
      ($bufflen-$i < $size) && last ;
      my @_I4 ;
      ($_I4[$I4_0], $_I4[$I4_1], $_I4[$I4_2], $_I4[$I4_3]) = unpack("CCCC",substr($$buff,$i,4)) ;
      ${$struct[$j]}=unpack("i",pack("CCCC", @_I4)) ;
      $i += $size ;
      }
    #
    # begin R*8
    #
    elsif ( $code eq 'R*8' )
      # Defined in STDF V4 standard
      # Only allowed in GDR records, although may not be used.
      # Should work for cross platform with INTEL, Sparc no VMS files !
      # Does not support VMS in any way including VMS files.
      # ...Well may run on VMS with files created on VMS...
      {
      ($bufflen-$i < $size) && last ;
      my @real ;
      ($real[$R8_0], $real[$R8_1], $real[$R8_2], $real[$R8_3],
      $real[$R8_4], $real[$R8_5], $real[$R8_6], $real[$R8_7])
        = (unpack("CCCCCCCC",substr($$buff,$i,8))) ;
      ${$struct[$j]}=unpack("d",pack("CCCCCCCC", @real)) ;
      ( $main::vms_conversion != 0 ) &&
        confess ("$code stdf data conversion to/from vax not supported, values set to default of 0\n" ) ;
      $i += $size ;
      } # end R*8
    elsif ( $code eq 'D*n' )
      {
      ($bufflen-$i < 2) && last ;
      # unpack the length
      my @_U2 ;
      ($_U2[$U2_0], $_U2[$U2_1]) = unpack("CC",substr($$buff,$i,2)) ;
      $size=unpack("S",pack("CC", @_U2)) ;
      $i += 2 ;
      my $byte_size = ceil($size/8) ;
      ($bufflen-$i < $byte_size) && last ;
      my $stored_bit_size=$byte_size*8 ;
      my $stored_bits = unpack('B'.$stored_bit_size, substr($$buff,$i,$byte_size)) ;
      ${$struct[$j]}=substr($stored_bits,($stored_bit_size-$size)) ;
      $i += $byte_size ;
      }
    elsif ( $type eq 'N' )
      {
        ( $size  > 65535 || $size < 0 ) && confess &lh, "$code nibble length $size of $struct[0] is greater than 65535 or < 0" ;
        ($bufflen-$i < ceil($size/2)) && last ;

        # We unpack the nibbles low order nibble first
        ${$struct[$j]}= unpack('h'.$size, substr($$buff,$i,ceil($size/2)));

        # Round up the number of nibbles / 2 to get bytes
        $i += ceil($size/2);
      }
    elsif ( $code eq 'V*n' )
      {
      confess &lh, "$code stdf data type not supported" ;
      }
    elsif ( $size eq 'f') # Does not seem to be part of an STDF 4 record
      {
      confess, &lh, "$code stdf data type not supported" ;
      }
    else
      {
      confess &lh, "$code stdf data type not supported" ;
      }
   $j ++ ;  # index into @struct
  }  # until $array_cnt > 0 ;
${$_[2]} = $i ;	  # index into $$buff, usually length($$buff) or there abouts
return ;
}

#
# Convert VMS R*4 to IEEE
# ported from util_v22 xplatfunc.c, including any bugs
#
sub  xpFlt4VAXtoIEEE 

{  # if vax file and not running on vax 
          my $buf = shift ;
          my @vaxFlt ; # temporary value for binary array
	  (unpack("I",$buf) == 0 ) && return(0) ;  # If all bytes are 0
          # unpack to solaris byte order, which how the masks are specified
          @vaxFlt = unpack("CCCC",$buf) ;
          my $XPVAXFlt4Byt1ExpMask            =0x7f ;
          my $XPVAXFlt4Byt1ExpTooSmallForIEEE =0x00 ;
          my $XPVAXFlt4Byt1SgnMask            =0x80 ;
          my $XPVAXFlt4Byt1ExpTwo             =0x01 ;
          my @ieeeFlt ;	
          if ( $XPVAXFlt4Byt1ExpTooSmallForIEEE == ( $vaxFlt[1] & $XPVAXFlt4Byt1ExpMask ) )
            { # too small, assume 0
	    #
	    # This should probably return FLT_MIN and preserve sign
	    # Not likely to be an issue
	    #
            $ieeeFlt[1] = 0x00 | $vaxFlt[1] & $XPVAXFlt4Byt1SgnMask ;
            $ieeeFlt[0] = 0x00 ;
            $ieeeFlt[2] = 0x00 ;
	    $ieeeFlt[3] = 0x00 ;
            }
          else
            { # Reorder the bytes subtract two to the exponent.
	    $ieeeFlt[0] = $vaxFlt[1] - $XPVAXFlt4Byt1ExpTwo ;
	    $ieeeFlt[1] = $vaxFlt[0] ;
	    $ieeeFlt[2] = $vaxFlt[3] ;
	    $ieeeFlt[3] = $vaxFlt[2] ;
            }
#          return(unpack("f",pack("CCCC", @ieeeFlt))) ;
          return(unpack("f",pack("CCCC",
                ($ieeeFlt[$R4_0], $ieeeFlt[$R4_1], $ieeeFlt[$R4_2], $ieeeFlt[$R4_3]) ))) ;
}

sub xpFlt4IEEEtoVAX
{ # if running on vax and not vax file and non-zero bytes - not tested 
          my $buf = shift ;
          my @ieeeFlt ; # temporary value for binary array
	  (unpack("I",$buf) == 0 ) && return(0) ;  # If all bytes are 0
	  # byte order might be wrong on @ieeeFlt for unpack
          @ieeeFlt = unpack("CCCC",$buf) ;
          my $XPIEEEFlt4Byt0ExpMask           =0x7f ;
          my $XPIEEEFlt4Byt0ExpTooLargeForVAX =0x7f ;
          my $XPIEEEFlt4Byt0SgnMask           =0x80 ;
          my $XPIEEEFlt4Byt0ExpTwo            =0x01 ;
          if ( $XPIEEEFlt4Byt0ExpTooLargeForVAX == ( $ieeeFlt[0] & $XPIEEEFlt4Byt0ExpMask ) )
            { # if the byte 0 exponent is too large
            $vaxFlt[1] = 0x7f | $ieeeFlt[0] & $XPIEEEFlt4Byt0SgnMask ;
            $vaxFlt[0] = 0xff ;
            $vaxFlt[2] = 0xff ;
	    $vaxFlt[3] = 0xff ;
	    confess &lh,"Overflow error converting from four byte IEE floating point to Vax\nValue set to ".unpack("f",pack("CCCC",@vaxFlt)) ;
            } #if too large
          else
            {    
            # Reorder the bytes add two to the exponent.
	    $vaxFlt[0] = $ieeeFlt[1] ;
	    $vaxFlt[1] = $ieeeFlt[0] + $XPIEEEFlt4Byt0ExpTwo ;
	    $vaxFlt[2] = $ieeeFlt[3] ;
	    $vaxFlt[3] = $ieeeFlt[2] ;
            } # if too large
	  # byte order might be wrong on @vaxFlt for unpack
          return(unpack("f",pack("CCCC", 
          ($vaxFlt[$R4_0], $vaxFlt[$R4_1], $vaxFlt[$R4_2], $vaxFlt[$R4_3]) ))) ;
} # if running on vax and not vax file and non-zero bytes - not tested ??
	

sub log_bad_unpack_double
{
my $real = shift ;
my $real_str = shift ;
my $code = 'R*4' ;
my $hex_str ;
my $pack_code ;

$hex_str = sprintf("\"\\x%x\\x%x\\x%x\\x%x\"",unpack"CCCC",$real_str) ;
$pack_code = 'f' ;

wlog($log_IEEEfloat_unpack_error, "$code:  unpack($pack_code, ". $hex_str. ") returned $real\n") ;
return(1) ;
}

sub stdf_unpack_array
{
my $code = $_[0] ;
my $record = $_[1] ;
my $i = $_[2] ;
my $array_count = $_[3] ;
my $array = $_[4] ;
my $j ;
my $len = length($$record) ;
my $rc=0 ;

if (defined(${$array_count}))
 {
  my ($type, $size) = split (/\Q*\E/, ${$code}) ;

  # Handle nibbles in a special case.
  # Unpack them all at once and then store them.
  if($type =~ "N")
  {
     my $new_code = "N*$$array_count";
     $rc = stdf_unpack(\$new_code, $record, $i, \${${$array}}[0] ) ;

     my @nibbles = split //, ${${$array}}[0];

     for ($j=0; $j < ${$array_count}; $j++)
     {
        ${${$array}}[$j] = $nibbles[$j];
     }
  }
  else
  {
	  for ($j=0; $j < ${$array_count}; $j++)
	    {
	    if ($len-${$i} < $size)
	      {
	      wlog(0,"Warning: array size=${$array_count}, to big for record\n") ;
	      last ;
	      }
	    $rc = stdf_unpack($code, $record, $i, \${${$array}}[$j] ) ;
	    }
  }
 }
return($rc) ;
}

return(1) ;
