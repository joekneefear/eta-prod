#!/usr/bin/env perl_db
# Reads Fairchild WorkStream format files using reference bcp_fmt file.
# USAGE: read_wksm.pl fmt-file-name extract-file-name
# read_format expects format file to contain tab-separated values; reader will fail if spaces are used.
#
# 16-Jun-2015 S. Boothby   Strip CR and LF from text.
# 21-Aug-2015 S. Boothby   Strip single and double quotes from text.

use English;
use Switch;

my ($format_file, $input_file);
my ($eof, $rc);
my @format_info = ();

$format_file = $ARGV[0];
$input_file  = $ARGV[1];

sub read_format
{
    open FMT, "< $format_file" or die "Failed to open $format_file\n";
    $eof = 0;

    $version = <FMT>;
    chomp($version);
    $column_count = <FMT>;
    chomp($column_count);
    $pos=0;
    for( $i=0; $i<scalar($column_count); $i++)
    {
       $line=<FMT>;
       chomp($line);
       my($col_num, $type, $pfx, $len, $delim, $cc, $col_name) = split(/\t/, $line);
       push @format_info, { col_num => $col_num, type => $type, pfx => $pfx, len => $len, col_name => $col_name};
#print "COL==$col_num NAME==$col_name TYPE==$type PFX==$pfx LEN==$len \n";
    }

    close FMT;
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
          return(unpack("f",pack("CCCC", ($ieeeFlt[3], $ieeeFlt[2], $ieeeFlt[1], $ieeeFlt[0]) ))) ;
}

sub read_data
{
   my @struct = @_[3..$#_] ; # list of values that will be passed back
   my $j = 0;

   $eof = 0;
   for( $c=0; $c<scalar @format_info; $c++)
   {
      $col_name = $format_info[$c]{col_name};
      if ( $c > 0 ) {print ","};
      print "\"$col_name\"";
   }
   print "\n";
   open READ, "< $input_file" or die "Failed to open";

   while( ! $eof )
   {
      for( $r=0; $r<scalar @format_info && ! $eof; $r++)
      {
         $col_num  = $format_info[$r]{col_num};
         $col_type = $format_info[$r]{type};
         $col_len  = $format_info[$r]{len};
         $col_pfx  = $format_info[$r]{pfx};
         $col_name = $format_info[$r]{col_name};

         if ( $r > 0 ) {print ","};
         switch( $col_type )
         {
            case "SYBCHAR"
            {
               if ( $col_pfx == 1 )
               {
                  $rc=read READ, $packed_field_len, 1;
                  if ( $rc > 0 ) 
                  {
                     $field_len = unpack "C", $packed_field_len;
                  }
                  else { $eof = 1; }
               }
               else {$field_len = $col_len};
               if ( $col_pfx == 1 && $field_len > $col_len )
               {
                  $field_len = $col_len;
               }

               if ( $field_len > 0 && ! $eof)
               {
                  $rc = read READ, $field_txt, $field_len;
                  if ( $rc == 0 ) { $eof = 1;}
               }
               else { $field_txt = ""; }
               if ( ! $eof )
               {
		  # Strip non-ASCII chars
		  $field_txt =~ s/[^[:ascii:]]//g;
		  # Strip CR LF (\r or \n)
		  $field_txt =~ s/[\x0A\x0D\x00]//g;
		  # Strip single and double-quotes 
                  chomp($field_txt);
                  $field_txt =~ tr/"'//d;
                  print "\"$field_txt\"";
               }
            }
            case "SYBINT2"
            {
               $rc=read READ, $packed_int2, 2;
               if ( $rc == 2 ) 
               {
                  $int2 = unpack "v", $packed_int2; # VMS 2-byte
                  print "$int2";
               }
            }
            case "SYBINT4"
            {
               if ( $col_pfx == 1 ) 
               {   
                  $rc=read READ, $packed_field_len, 1;
                  if ( $rc > 0 ) 
                  {   
                     $field_len = unpack "C", $packed_field_len;
                  }   
                  else { $eof = 1; }
               }   
               else { $field_len = 4 };
               if ( $field_len > 0 ) 
               {   
                  $rc=read READ, $packed_int4, 4;
                  if ( $rc == 4 ) 
                  {   
                     $int4 = unpack "V", $packed_int4;
                     print "$int4";
                  }   
               }   
            }
            case "SYBFLT8"
            {
               if ( $col_pfx == 1 )
               {
                  $rc=read READ, $packed_field_len, 1;
                  if ( $rc > 0 ) 
                  {
                     $field_len = unpack "C", $packed_field_len;
                  }
                  else { $eof = 1; }
               }
               else { $field_len = 8 };
               
               if ( $field_len > 0 )
               {
                  $rc=read READ, $packed_flt8, $field_len;
                  # In the extract, last 4 bytes of 8-byte floats are "fillers" (all-zero).  Ignore.
                  $flt4 = xpFlt4VAXtoIEEE(pack('CCCC', unpack('CCCC', $packed_flt8 )));
                  if ( $rc == $field_len ) 
                  {
                     print "$flt4";
                  }
               }
            }
         }
      }
      if ( ! $eof )
      {
         print "\n";
      }
   }
   close READ;
}

read_format();
read_data();

