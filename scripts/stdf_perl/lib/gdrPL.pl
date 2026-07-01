# This file may be linked, or duplicated with gdrPL.pl/gdrV4.pl
# as perl will not allow same file to be loaded twice into two
# different name spaces.

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
# 02-08-2000 Steve Frampton  Original.  Contact Information:
#                            (207) 273-3364
#                            sframpto@fairchildsemi.com,
#                            sframpto@midcoast.com
# 02-21-2000 Steve Frampton  GDR.REC_LEN is updated during pack
# 04-02-2021 Jun   Garcia    modefied to remove [defined(%hash) is deprecated warnings].
#

#
#  GDR Record for all versions 3,3+, and 4.
#

#
#  Maps GDR type number, array index, to the STDF data type.
#
use Carp ;

#
# define this externally if you want V3 or PL data types
#
if ( !(@GDR_unpack_types) || !(%GDR_pack_types) )
{
@GDR_unpack_types = (
'B*0',
'U*1',
'U*2',
'U*4',
'I*1',
'I*2',
'I*4',
'R*4',
'R*8',
'Invalid_gdr_type',  # 9 does not exist in specification
'C*n',
'B*n',
'D*n',
'N*1' ) ;

%GDR_pack_types = (
'B*0'=>0,
'U*1'=>1,
'U*2'=>2,
'U*4'=>3,
'I*1'=>4,
'I*2'=>5,
'I*4'=>6,
'R*4'=>7,
'R*8'=>8,
'Invalid_gdr_type'=>9,  # 9 does not exist in specification
'C*n'=>10,
'B*n'=>11,
'D*n'=>12,
'N*1'=>13 ) ;
}

$GDR_pad = pack("C",0) ; # B*0 pad byte

sub pack_GDR
{
my $gdr = shift ;
my $header ;
my $rc ;
my $i ;
my $gen_data_bin ;
my $types ;
my $gen_data_type ;
my $len ;

  ${$gdr}{fld_cnt}=0 ;

for ($i=0; $i<=$#{@{$gdr}{gen_data}}; $i++)
  {
  if ((! defined(${$gdr}{gen_data}[$i]{type}))
    || (! defined(${$gdr}{gen_data}[$i]{data})))
      { last ; }  # stop on a truncated record
  if ((length($gen_data_bin) % 2)
     && ((${$gdr}{gen_data}[$i]{type} ne 'B*0')))  # add pad byte if needed
    {
    $gen_data_bin .= $GDR_pad ;
    ${$gdr}{fld_cnt} ++ ;
    }
  if (${$gdr}{gen_data}[$i]{type} eq 'B*0')  # user entered pad byte ?? why ?? well..ok
    {
    $gen_data_bin .= $GDR_pad ;  # append user pad byte.
    }
  else
    {
    $gen_data_type = $GDR_pack_types{${$gdr}{gen_data}[$i]{type}} ;
    (defined($gen_data_type)) || confess &lh, "Invalid GDR datatype:  ${$gdr}{gen_data}[$i]{type}" ;
    $types = 'U*1 '.${$gdr}{gen_data}[$i]{type} ;
    $rc = &::stdf_pack(
      \$types,
      \$gen_data_bin,  # automatically gets appended to
      \$gen_data_type,
      \${$gdr}{gen_data}[$i]{data} ) ;
    }
  ${$gdr}{fld_cnt} ++ ;
  if (${$gdr}{fld_cnt} > 0xFFFF)
    {
    #
    # This does not include pad bytes ! ... but we do trap it in pack
    #
    confess &lh, "Only ", 0xFFFF, "GDR.GEN_DATA fields allowed\n" ;
    }
  }
${$gdr}{rec_len} = length($gen_data_bin)+2 ;
$rc = &::stdf_pack(
  \'U*2 U*1 U*1 U*2',
  \$header,
  \${$gdr}{rec_len},
  \50,
  \10,
  \${$gdr}{fld_cnt}) ;
  
return($header . $gen_data_bin) ;
}

#
# if global $::ignore_gdr_pads is set to != 0, then gdr pad records will not
# get put into gdr data structure
#
sub unpack_GDR
{
my $record = shift ;
my $gdr = shift ;
my $i = 0 ;
my $j = 0 ;
my $rc ;
my $f ;
my $rec_len = 0 ;
my $gen_type_no ;
my $gen_type ;
my $gen_data ;

undef(${$gdr}{rec_len});
undef(${$gdr}{rec_typ});
undef(${$gdr}{rec_sub});
undef(${$gdr}{fld_cnt});
undef(${$gdr}{gen_data});
$rc = &::stdf_unpack(
  \'U*2 U*1 U*1 U*2',
  $record,
  \$i,
  \${$gdr}{rec_len},
  \${$gdr}{rec_typ},
  \${$gdr}{rec_sub},
  \${$gdr}{fld_cnt});

#
# $j is field counter
# $i is byte counter
#

$j=0 ;
while ($j<${$gdr}{fld_cnt})
  {
  $rc = &::stdf_unpack(
    \'U*1',
    $record,
    \$i,
    \$gen_type_no) ;
  $gen_type = $GDR_unpack_types[$gen_type_no] ;
  (defined($gen_type)) || confess $lh, "GDR type=$gen_type, not valid" ;
  $rc = &::stdf_unpack(
    \$gen_type,
    $record,
    \$i,
    \$gen_data ) ;
  #
  # if $::ignore_gdr_pads is set,
  # then don't put it in data structure
  # and decrement the fld_cnt
  #
  if ($gen_type_no == 0 && $::ignore_gdr_pads )
    {
    ${$gdr}{fld_cnt}-- ;
    }
  else
    {
    ${$gdr}{gen_data}[$j]{data} = $gen_data ;
    ${$gdr}{gen_data}[$j]{type} = $gen_type ;
    $j++ ;
    }
  }

return (0) ;
}

#
# stdf_copy -ascii will use this function for output
#
sub write_ascii_GDR
{
my $gdr = shift ;
my $file = shift ;
my $record_number = shift ;

my $i ;

print $file "\t", "GDR" ," :\tREC_LEN=", ${$gdr}{rec_len} ,"\n" ;
print $file "\t\t","REC_NO=", $record_number, "\n" ;
print $file "\t\t","REC_TYP=", ${$gdr}{rec_typ}, "\n" ;
print $file "\t\t","REC_SUB=", ${$gdr}{rec_sub}, "\n" ;
print $file "\t\t","FLD_CNT=", ${$gdr}{fld_cnt}, "\n" ;
#print $file "\t\t","GEN_DATA=","\n" ;

for ($i=0; $i<=$#{@{$gdr}{gen_data}}; $i++)
  {
  print $file "\t\t","GEN_DATA[$i]=",${$gdr}{gen_data}[$i]{type},",",${$gdr}{gen_data}[$i]{data},"\n" ;
  }
print $file "\n\n" ;

}

#
# stdf_copy_ascii will use this function
#
sub read_ascii_rec_GDR(@)
{
my $in = shift ;    # pointer to input file handle
my $status=undef ;  # return status to indicate EOF
my $line ;
my $type ;  # gdr gen_data type
my $fieldvalue ;  # gdr gen_data data
my $j=0 ; # index into gen_data array

$line = <$in> ;
$status = $line ;  # set up status in case we hit end of file
#
# read and parse record
#
while (! ($line =~ /^\s*$/))
  {
  chomp($line) ;
  $line =~ s/=(\s*.+)\s+$/=$1/ ;  # strip trailing whitespace from value
                                  # that contains one or more non-whitespace
				  # characters
  $line =~ s/^\s+// ; # remove leading whitespace
  if ($line =~ /FLD_CNT/)
    {
    #
    # we ignore FLD_CNT field, as pack_GDR resets it anyhow
    #
    $line = <$in> ;
    next ;
    }
  #
  # example $line format as spit out by stdf_copy:
  #   GEN_DATA[8]=I*2,32000
  # This also works:
  #   GEN_DATA[]=I*2,32000
  #
  if (!($line =~ /^GEN_DATA/) )
    { confess "Only GEN_DATA field is allowed here: $line, line: $NR" } ;

  if (!($line =~ /^GEN_DATA\Q[\E[0-9]*\Q]\E=(...),(.*)/) )
    { confess "Syntax error in GEN_DATA field: $line, line: $NR" } ;
  $type = $1 ;  # first result from () =~
  $fieldvalue = $2 ;  # secord result in () from =~

  #
  # check for a valid gdr type
  #
  if ( ! defined($GDR_pack_types{$type}) )
    { confess "Invalid GDR datatype:  $type, line: $NR" } ;

  $out::gdr{gen_data}[$j]{data} = $fieldvalue ;
  $out::gdr{gen_data}[$j]{type} = $type ;
  #
  # appears as undefined in text file, but is really default value
  #
  if (!defined($fieldvalue) || ($fieldvalue eq '') )
    {
    &::wlog(1, "Warning, GDR.GENDATA is undefined, line: $NR\n") ;
    }
  $line = <$in> ;
  $j++ ;
  if ($j > 0xFFFF)
    {
    #
    # This does not include pad bytes ! ... but we do trap it in pack
    #
    confess "Only ", 0xFFFF, "GDR.GEN_DATA fields allowed, line: $NR\n" ;
    }
  }
$status = $line ;  # set up status in case we hit end of file
$out::gdr{fld_cnt} = $j ;

return (defined($status)) ;
}

