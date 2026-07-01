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
# 02-07-2000 Steve Frampton  Moved init_swap_cnv stuff from
#                            stdf_read_first into stdf_unpack.pm
#                            as init_swap_cnv
#                            Changed read_rec to not report
#                            error for extra bytes at end of file
#                            (VMS)
# 02-09-2000 Steve Frampton  split read_ascii_rec into two functions:
#                            read_ascii_head and read_ascii_rec
#                            functions are very similar - could me more
#                            modular, less convoluted.
# 02-11-2000 Steve Frampton  Added array functionality to read_ascii_rec
# 04-15-2006 Steve Frampton  Added specific check fo array '[]'
# 05-09-2006 Steve Frampton  Commented out some debug code.
# 01-03-2013 Scott Boothby   Added a subroutine for pulling the STDF version from a file.
# 06-26-2015 Scott Boothby   Fixed a bug with PTR read from v4.
# 04-02-2021 Jun   Garcia    fixed to remove defined(%hash) is deprecated warnings.
#

#
# Routines to read stdf records from file into a binary format
# that can then be unpacked.
#

#
# read_ascii_rec, and read_ascii_head is used to convert an stdf_copy ascii
# dump to binary format.
#


#
# read the first record of the file
# only use if file cpu type is not known
# and stdf version is not known
#
# set up platform translations
# and return buffer with first record
# supports stdf V3, V4, and V+ and ??
#   assumes that the first record is structured as follows
#   REC_LEN U*2
#   REC_TYP U*1
#   REC_SUB U*1
#   CPU_TYPE U*1
#   STDF_VER U*1
#   + Whatever ELSE
#
# returns the bytes left to read from first record
# and the raw bytes read from the file
#
# Sets up platform dependencies 
# used by unpack routines:
# $do_int_byte_swap
# $do_real_byte_swap
# $file_cpu_type
# index variables used for byte swapping
#
sub read_first_rec(@)
{
my $in = $_[0] ;    # pointer to input file handle
my $len = 6 ;       #number of bytes to read
my $header_len = 4 ; # length of header
my $buf ;        # buffer ;
my $buf_remaining ;        # buffer ;
my $rec_len; my $rec_typ; my $rec_sub; my $cpu_type; my $stdf_ver ;
my $bytes_left ;    # bytes left to read in record after header and first 4 bytes
my $status ;  # return number of bytes eof is fatal here
my $i ; # unpack buffer index


$status = read ($in, $buf, $len) ;
if ($status != $len)
  { confess &lh, "Cannot read first $len bytes of file"; }

$i = 0 ;
init_byte_order(0, 0) ;                         # get rid of warnings (shouldn't affect functionality)
stdf_unpack( \"U*2 U*1 U*1 U*1 U*1", \$buf, \$i, \$rec_len, \$rec_typ, \$rec_sub, \$cpu_type, \$stdf_ver) ;

#HP Testers list CPU types as 128 ... treat this as a unix(solaris) type ..
if($cpu_type == 128)
{
	$cpu_type = 1;
}

$file_cpu_type = $cpu_type ;
#
# set up global byte swapping variables
# and vms conversion variables
#
init_swap_cnv($file_cpu_type, $running_cpu_type) ;
#
# set up indices used for unpack to determine byte ordering
# based on do_int_byte_swap and do_real_byte_swap
#
init_byte_order($do_int_byte_swap, $do_real_byte_swap) ;
#
# convert $rec_len from $file_cpu_type to $running_cpu_type 
#
#print "header_len: $header_len len: $len\n" ;
$i = 0 ;
stdf_unpack(\"U*2", \$buf, \$i, \$rec_len ) ;
#
# read the rest of the raw record
# note that for the first record, it is not $rec_len
#
$bytes_left = $rec_len - $len + $header_len ;
if ( $bytes_left > 0 )
  {
  my $bytes_read =  read ($in, $buf_remaining, $bytes_left) ;
  if ($bytes_read != $bytes_left)
    { confess &lh, "Cannot read $bytes_left bytes; REC_LEN: $rec_len REC_TYP: $rec_typ REC_SUB: $rec_sub CPU_TYPE: $cpu_type STDF_VER:  $stdf_ver"; }
  $status += $bytes_read ;
  }
#
# return header plus raw record info
# $buf has raw header and raw record info.
#
#print "REC_LEN: $rec_len REC_TYP: $rec_typ REC_SUB: $rec_sub CPU_TYPE: $cpu_type STDF_VER:  $stdf_ver\n";
$_[1] = $stdf_ver ;
return ( $status, $rec_len, $rec_typ, $rec_sub, $buf . $buf_remaining ) ;
}

#
# read in a record and return status, rec_len, rec_type, rec_sub, buf
# buf is raw input data stream
# status = 0 is EOF
# otherwise status = total bytes read, rec_len + 4
# all errors are trapped internally and result in a confess
#
sub read_rec(@)
{
my $in = $_[0] ;            # pointer to input file handle
my $header_len = 4 ;        # number of bytes in header
my $rec_len ;               # record length to be read in
my $rec_sub ;               # record sub type to be read in
my $head_buf ;              # raw data buffer for header
my $buf ;                   # raw data buffer for record
my $status ;                # return status to check for EOF
my $i = 0 ;
my $stdf_ver = $_[1];       #STDF version
my $read_rec_buf ;   	    # buffer for return result
my $reading_wmr_records=0;  # variable used to indicate if we are
                            # in the process of reading a wmr record

do  # while $reading_wmr_records
{
$status = read ($in, $head_buf, $header_len) ;
if ($status != $header_len)
  {
  #
  # End of file,
  # Extra byte at end of file (VMS),
  # Or an error
  # No matter what, we are done.
  #
  #if (! defined($status))
  #  {
  #  confess &lh, "Error reading file." ;
  #  }
  return(0) ; # End of file or extra byte VMS at end of file
  }
#
# unpack record header
#
$i = 0 ;
stdf_unpack(\"U*2 U*1 U*1", \$head_buf, \$i, \$rec_len, \$rec_typ, \$rec_sub ) ;
#
# read the rest of the raw record
#
my $chars_read = read ($in, $buf, $rec_len) ;
($chars_read == $rec_len) || confess &lh, "Cannot read $rec_len bytes; REC_LEN: $rec_len REC_TYP: $rec_typ REC_SUB: $rec_sub";
$status += $chars_read ;


if(($rec_typ == 10) && ($rec_sub == 200) && ($stdf_ver == 202 || $stdf_ver == 104)) # STDF V3+,V1.4 EPDR Record
{
#	wlog(1, "V3+ EPDR\n");
	my $tmp_buf = $buf;
        my $total_bytes = 22; # we start 22 bytes into the record.  This skips everything up to the first 
			      # variable-length char string
	my $tmp_buf2;
		
	$tmp_buf = substr($buf,$total_bytes,$rec_len);

	my $lo_limit;
	if( ! $main::vms_conversion )
	{
		my @_real;
	        ($_real[$R4_0], $_real[$R4_1], $_real[$R4_2], $_real[$R4_3]) = unpack("CCCC",substr($tmp_buf,0,4));
       		$lo_limit = unpack("f",pack("CCCC", @_real));
	}
	elsif ( $main::vms_conversion == $VMS2IEEE)
	{
		$lo_limit = xpFlt4VAXtoIEEE (substr($tmp_buf,0,4));
	}
	elsif ($main::vms_conversion == $IEEE2VMS)
	{
		$lo_limit = xpFlt4IEEEtoVAX (substr($tmp_buf,0,4));
	}
	else
        {
        	confess ("$code stdf data conversion not supported\n" ) ;
        }
	
	if( $lo_limit < -1e20 )
	{
		wlog(1, "Lo Spec Limit Out Of EWB Range...\n");
		$lo_limit = -1e20;

		if ($main::vms_conversion == $VMS2IEEE)
		{
			$lo_limit = xpFlt4IEEEtoVAX(pack("CCCC", unpack("CCCC", pack("f", $lo_limit))));
		}
		elsif ($main::vms_conversion == $IEEE2VMS)
		{
			$lo_limit = xpFlt4VAXtoIEEE(pack("CCCC", unpack("CCCC", pack("f", $lo_limit))));
		}
	
		$tmp_buf2 = substr($buf,0,$total_bytes);
		if($R4_0 == 3)
		{
			$tmp_buf2 .= pack("CCCC",reverse unpack("CCCC", pack("f", $lo_limit)));
		}
		else
		{
			$tmp_buf2 .= pack("CCCC", unpack("CCCC", pack("f", $lo_limit)));
		}
		$tmp_buf2 .= substr($buf,$total_bytes+4,$rec_len);
		$buf = $tmp_buf2;
	}
	$total_bytes += 4;

	$tmp_buf = substr($buf,$total_bytes,$rec_len);
	
	my $hi_limit;
	if(! $main::vms_conversion )
	{
		my @_real;
       		($_real[$R4_0], $_real[$R4_1], $_real[$R4_2], $_real[$R4_3]) = unpack("CCCC",substr($tmp_buf,0,4));
    		$hi_limit = unpack("f",pack("CCCC", @_real));
	}
	elsif ($main::vms_conversion == $VMS2IEEE)
	{
		$hi_limit = xpFlt4VAXtoIEEE (substr($tmp_buf,0,4));
	}
	elsif ($main::vms_conversion == $IEEE2VMS)
	{
		$hi_limit = xpFlt4IEEEtoVAX (substr($tmp_buf,0,4));
	}
	else
        {
        	confess ("$code stdf data conversion not supported\n" ) ;
        }

	if( $hi_limit > 1e20 )
	{
		wlog(1, "Hi Spec Limit Out Of EWB Range...\n");
		$hi_limit = 1e20;
		
		if ($main::vms_conversion == $VMS2IEEE)
		{
			$hi_limit = xpFlt4IEEEtoVAX(pack("CCCC", unpack("CCCC", pack("f", $hi_limit))));
		}
		elsif ($main::vms_conversion == $IEEE2VMS)
		{
			$hi_limit = xpFlt4VAXtoIEEE(pack("CCCC", unpack("CCCC", pack("f", $hi_limit))));
		}

		$tmp_buf2 = substr($buf,0,$total_bytes);
		if($R4_0 == 3)
		{
			$tmp_buf2 .= pack("CCCC",reverse unpack("CCCC", pack("f", $hi_limit)));
		}
		else
		{
			$tmp_buf2 .= pack("CCCC", unpack("CCCC", pack("f", $hi_limit)));
		}
		$tmp_buf2 .= substr($buf,$total_bytes+4,$rec_len);
		$buf = $tmp_buf2;
	}
        $total_bytes += 4;

	$tmp_buf = substr($buf,$total_bytes,$rec_len);

	my $lo_censr;
	if (! $main::vms_conversion )
	{	
		my @_real;
        	($_real[$R4_0], $_real[$R4_1], $_real[$R4_2], $_real[$R4_3]) = unpack("CCCC",substr($tmp_buf,0,4));
        	$lo_censr = unpack("f",pack("CCCC", @_real));
	}
	elsif ($main::vms_conversion == $VMS2IEEE)
	{
		$lo_censr = xpFlt4VAXtoIEEE (substr($tmp_buf,0,4));
	}
	elsif ($main::vms_conversion == $IEEE2VMS)
	{
		$lo_censr = xpFlt4IEEEtoVAX (substr($tmp_buf,0,4));
       	}
	else
        {
        	confess ("$code stdf data conversion not supported\n" ) ;
        }

 
	if( $lo_censr < -1e20 )
	{
		wlog(1, "Lo Censor Limit Out Of EWB Range...\n");
		$lo_censr = -1e20;
		
		if ($main::vms_conversion == $VMS2IEEE)
		{
			$lo_censr = xpFlt4IEEEtoVAX(pack("CCCC", unpack("CCCC", pack("f", $lo_censr))));
		}
		elsif ($main::vms_conversion == $IEEE2VMS)
		{
			$lo_censr = xpFlt4VAXtoIEEE(pack("CCCC", unpack("CCCC", pack("f", $lo_censr))));
		}
		
		$tmp_buf2 = substr($buf,0,$total_bytes);
		if($R4_0 == 3)
		{
			$tmp_buf2 .= pack("CCCC",reverse unpack("CCCC", pack("f", $lo_censr)));
		}
		else
		{
			$tmp_buf2 .= pack("CCCC", unpack("CCCC", pack("f", $lo_censr)));
		}
		$tmp_buf2 .= substr($buf,$total_bytes+4,$rec_len);
		$buf = $tmp_buf2;
	}
	$total_bytes += 4;

	$tmp_buf = substr($buf,$total_bytes,$rec_len);
	
	my $hi_censr;
	if( ! $main::vms_conversion )
	{
		my @_real;
       		($_real[$R4_0], $_real[$R4_1], $_real[$R4_2], $_real[$R4_3]) = unpack("CCCC",substr($tmp_buf,0,4));
    		$hi_censr = unpack("f",pack("CCCC", @_real));
	}
	elsif ( $main::vms_conversion == $VMS2IEEE)
	{
		$hi_censr = xpFlt4VAXtoIEEE (substr($tmp_buf,0,4));
	}
	elsif( $main::vms_conversion == $IEEE2VMS)
	{
		$hi_censr = xpFlt4IEEEtoVAX (substr($tmp_buf,0,4));
	}
	else
	{
		confess("$code stdf data conversion not supported.\n");
	}
	
	if( $hi_censr > 1e20 )
	{
		wlog(1, "Hi Censor Limit Out Of EWB Range...\n");
		$hi_censr = 1e20;
		
		if ($main::vms_conversion == $VMS2IEEE)
		{
			$hi_censr = xpFlt4IEEEtoVAX(pack("CCCC", unpack("CCCC", pack("f", $hi_censr))));
		}
		elsif ($main::vms_conversion == $IEEE2VMS)
		{
			$hi_censr = xpFlt4VAXtoIEEE(pack("CCCC", unpack("CCCC", pack("f", $hi_censr))));
		}
	
		$tmp_buf2 = substr($buf,0,$total_bytes);
		if($R4_0 == 3)
		{
			$tmp_buf2 .= pack("CCCC",reverse unpack("CCCC", pack("f", $hi_censr)));
		}
		else
		{
			$tmp_buf2 .= pack("CCCC", unpack("CCCC", pack("f", $hi_censr)));
		}
		$tmp_buf2 .= substr($buf,$total_bytes+4,$rec_len);
		$buf = $tmp_buf2;
	}
}
elsif(($rec_typ == 10) && ($rec_sub == 10) && $stdf_ver == 3) # STDF V3 PDR Record
{
	# wlog(1, "V3 PDR\n");
	my $tmp_buf = $buf;
        my $total_bytes = 22; # we start 12 bytes into the record.  This skips everything up to the first 
			      # variable-length char string
	
	$tmp_buf = substr($buf,$total_bytes,$rec_len);

	my $lo_limit;
	if (! $main::vms_conversion )
	{
		my @_real;
        	($_real[$R4_0], $_real[$R4_1], $_real[$R4_2], $_real[$R4_3]) = unpack("CCCC",substr($tmp_buf,0,4));
        	$lo_limit = unpack("f",pack("CCCC", @_real));
	}
	elsif ($main::vms_conversion == $VMS2IEEE)
	{
		$lo_limit = xpFlt4VAXtoIEEE (substr($tmp_buf,0,4));
	}
	elsif ($main::vms_conversion == $IEEE2VMS)
	{
		$lo_limit = xpFlt4IEEEtoVAX (substr($tmp_buf,0,4));
	}
	else
	{
		confess ("$code stdf data conversion not supported\n");	
	}

	if( $lo_limit < -1e20 )
	{
		wlog(1, "Lo Spec Limit Out Of EWB Range...\n");
		$lo_limit = -1e20;
		
		if ($main::vms_conversion == $VMS2IEEE)
		{
			$lo_limit = xpFlt4IEEEtoVAX(pack("CCCC", unpack("CCCC", pack("f", $lo_limit))));
		}
		elsif ($main::vms_conversion == $IEEE2VMS)
		{
			$lo_limit = xpFlt4VAXtoIEEE(pack("CCCC", unpack("CCCC", pack("f", $lo_limit))));
		}
	
		$tmp_buf2 = substr($buf,0,$total_bytes);
		if($R4_0 == 3)
		{
			$tmp_buf2 .= pack("CCCC",reverse unpack("CCCC", pack("f", $lo_limit)));
		}
		else
		{
			$tmp_buf2 .= pack("CCCC", unpack("CCCC", pack("f", $lo_limit)));
		}
		$tmp_buf2 .= substr($buf,$total_bytes+4,$rec_len);
		$buf = $tmp_buf2;

	}
	$total_bytes += 4;

	$tmp_buf = substr($buf,$total_bytes,$rec_len);

	my $hi_limit;
	if (! $main::vms_conversion )
	{
		my @_real;
        	($_real[$R4_0], $_real[$R4_1], $_real[$R4_2], $_real[$R4_3]) = unpack("CCCC",substr($tmp_buf,0,4));
        	$hi_limit = unpack("f",pack("CCCC", @_real));
	}
	elsif ($main::vms_conversion == $VMS2IEEE)
	{
		$hi_limit = xpFlt4VAXtoIEEE (substr($tmp_buf,0,4));
	}	
	elsif ($main::vms_conversion == $IEEE2VMS)
	{
		$hi_limit = xpFlt4IEEEtoVAX (substr($tmp_buf,0,4));
	}
	else
        {
        	confess ("$code stdf data conversion not supported\n" ) ;
        }

	if( $hi_limit > 1e20 )
	{
		wlog(1, "Hi Spec Limit Out Of EWB Range...\n");
		$hi_limit = 1e20;
		
		if ($main::vms_conversion == $VMS2IEEE)
		{
			$hi_limit = xpFlt4IEEEtoVAX(pack("CCCC", unpack("CCCC", pack("f", $hi_limit))));
		}
		elsif ($main::vms_conversion == $IEEE2VMS)
		{
			$hi_limit = xpFlt4VAXtoIEEE(pack("CCCC", unpack("CCCC", pack("f", $hi_limit))));
		}

		$tmp_buf2 = substr($buf,0,$total_bytes);
		if($R4_0 == 3)
		{
			$tmp_buf2 .= pack("CCCC",reverse unpack("CCCC", pack("f", $hi_limit)));
		}
		else
		{
			$tmp_buf2 .= pack("CCCC", unpack("CCCC", pack("f", $hi_limit)));
		}
		$tmp_buf2 .= substr($buf,$total_bytes+4,$rec_len);
		$buf = $tmp_buf2;
	}
}
elsif(($rec_typ == 15) && ($rec_sub == 10) && $stdf_ver == 4) # STDF V4 PTR Record
{
	#wlog(1, "V4 PTR\n");
	my $tmp_buf = $buf;
        my $total_bytes = 12; # we start 12 bytes into the record.  This skips everything up to the first 
			      # variable-length char string

        $tmp_buf = substr($buf,$total_bytes,$rec_len);

	my $size = unpack("C",substr($tmp_buf,0,1));
	$total_bytes += 1;
	($rec_len - $total_bytes < $size) && next;
	$total_bytes += $size;

	$tmp_buf = substr($buf,$total_bytes,$rec_len);

        if ( $total_bytes < $rec_len ) 
        {
	my $size = unpack("C",substr($tmp_buf,0,1));
	$total_bytes += 1;
	($rec_len - $total_bytes < $size) && next;
	$total_bytes += $size;

	# skip all fields up to the lo limit field
	$total_bytes += 4;
	$tmp_buf = substr($buf,$total_bytes,$rec_len);

	my $lo_limit;
	if (! $main::vms_conversion )
	{
		my @_real;
        	($_real[$R4_0], $_real[$R4_1], $_real[$R4_2], $_real[$R4_3]) = unpack("CCCC",substr($tmp_buf,0,4));
        	$lo_limit = unpack("f",pack("CCCC", @_real));
	}
	elsif ($main::vms_conversion == $VMS2IEEE)
	{
		$lo_limit = xpFlt4VAXtoIEEE (substr($tmp_buf,0,4));
	}
	elsif ($main::vms_conversion == $IEEE2VMS)
	{
		$lo_limit = xpFlt4IEEEtoVAX (substr($tmp_buf,0,4));
	}
	else
        {
        	confess ("$code stdf data conversion not supported\n" ) ;
        }

	if( $lo_limit < -1e20 )
	{
		wlog(1, "Lo Spec Limit Out Of EWB Range...\n");
		$lo_limit = -1e20;
		
		if ($main::vms_conversion == $VMS2IEEE)
		{
			$lo_limit = xpFlt4IEEEtoVAX(pack("CCCC", unpack("CCCC", pack("f", $lo_limit))));
		}
		elsif ($main::vms_conversion == $IEEE2VMS)
		{
			$lo_limit = xpFlt4VAXtoIEEE(pack("CCCC", unpack("CCCC", pack("f", $lo_limit))));
		}
		
		$tmp_buf2 = substr($buf,0,$total_bytes);
		if($R4_0 == 3)
		{
			$tmp_buf2 .= pack("CCCC",reverse unpack("CCCC", pack("f", $lo_limit)));
		}
		else
		{
			$tmp_buf2 .= pack("CCCC", unpack("CCCC", pack("f", $lo_limit)));
		}
		$tmp_buf2 .= substr($buf,$total_bytes+4,$rec_len);
		$buf = $tmp_buf2;

	}
	$total_bytes += 4;

	$tmp_buf = substr($buf,$total_bytes,$rec_len);

	my $hi_limit;
	if (! $main::vms_conversion )
	{
		my @_real;
        	($_real[$R4_0], $_real[$R4_1], $_real[$R4_2], $_real[$R4_3]) = unpack("CCCC",substr($tmp_buf,0,4));
        	$hi_limit = unpack("f",pack("CCCC", @_real));
	}
	elsif ($main::vms_conversion == $VMS2IEEE)
	{
		$hi_limit = xpFlt4VAXtoIEEE (substr($tmp_buf,0,4));
	}
	elsif ($main::vms_conversion == $IEEE2VMS)
	{
		$hi_limit = xpFlt4IEEEtoVAX (substr($tmp_buf,0,4));
	}
	else
        {
        	confess ("$code stdf data conversion not supported\n" ) ;
        }

	if( $hi_limit > 1e20 )
	{
		wlog(1, "Hi Spec Limit Out Of EWB Range...\n");
		$hi_limit = 1e20;
		
		if ($main::vms_conversion == $VMS2IEEE)
		{
			$hi_limit = xpFlt4IEEEtoVAX(pack("CCCC", unpack("CCCC", pack("f", $hi_limit))));
		}
		elsif ($main::vms_conversion == $IEEE2VMS)
		{
			$hi_limit = xpFlt4VAXtoIEEE(pack("CCCC", unpack("CCCC", pack("f", $hi_limit))));
		}


		$tmp_buf2 = substr($buf,0,$total_bytes);
		if($R4_0 == 3)
		{
			$tmp_buf2 .= pack("CCCC",reverse unpack("CCCC", pack("f", $hi_limit)));
		}
		else
		{
			$tmp_buf2 .= pack("CCCC", unpack("CCCC", pack("f", $hi_limit)));
		}
		$tmp_buf2 .= substr($buf,$total_bytes+4,$rec_len);
		$buf = $tmp_buf2;
	}
        $total_bytes += 4;
	
	$tmp_buf = substr($buf,$total_bytes,$rec_len);

	my $size = unpack("C",substr($tmp_buf,0,1));
	$total_bytes += 1;
	#($rec_len - $total_bytes < $size) && last;
	$total_bytes += $size;

	$tmp_buf = substr($buf,$total_bytes,$rec_len);
	
	my $size = unpack("C",substr($tmp_buf,0,1));
	$total_bytes += 1;
	#($rec_len - $total_bytes < $size) && last;
	$total_bytes += $size;

	$tmp_buf = substr($buf,$total_bytes,$rec_len);

	my $size = unpack("C",substr($tmp_buf,0,1));
	$total_bytes += 1;
	#($rec_len - $total_bytes < $size) && last;
	$total_bytes += $size;

	$tmp_buf = substr($buf,$total_bytes,$rec_len);

	my $size = unpack("C",substr($tmp_buf,0,1));
	$total_bytes += 1;
	#($rec_len - $total_bytes < $size) && last;
	$total_bytes += $size;

	$tmp_buf = substr($buf,$total_bytes,$rec_len);

	my $lo_censr;
	if (! $main::vms_conversion )
	{
		my @_real;
        	($_real[$R4_0], $_real[$R4_1], $_real[$R4_2], $_real[$R4_3]) = unpack("CCCC",substr($tmp_buf,0,4));
        	$lo_censr = unpack("f",pack("CCCC", @_real));
	}
	elsif ($main::vms_conversion == $VMS2IEEE)
	{
		$lo_censr = xpFlt4VAXtoIEEE (substr($tmp_buf,0,4));
	}
	elsif ($main::vms_conversion == $IEEE2VMS)
	{
		$lo_censr = xpFlt4IEEEtoVAX (substr($tmp_buf,0,4));
	}
	else
	{
		confess ("$code stdf data conversion not supported\n");
	}

	if( $lo_censr < -1e20 )
	{
		wlog(1, "Lo Censor Limit Out Of EWB Range...\n");
		$lo_censr = -1e20;

		if ($main::vms_conversion == $VMS2IEEE)
		{
			$lo_censr = xpFlt4IEEEtoVAX(pack("CCCC", unpack("CCCC", pack("f", $lo_censr))));
		}
		elsif ($main::vms_conversion == $IEEE2VMS)
		{
			$lo_censr = xpFlt4VAXtoIEEE(pack("CCCC", unpack("CCCC", pack("f", $lo_censr))));
		}


		$tmp_buf2 = substr($buf,0,$total_bytes);
		if($R4_0 == 3)
		{
			$tmp_buf2 .= pack("CCCC",reverse unpack("CCCC", pack("f", $lo_censr)));
		}
		else
		{
			$tmp_buf2 .= pack("CCCC", unpack("CCCC", pack("f", $lo_censr)));
		}
		$tmp_buf2 .= substr($buf,$total_bytes+4,$rec_len);
		$buf = $tmp_buf2;
	}
        $total_bytes += 4;

	$tmp_buf = substr($buf,$total_bytes,$rec_len);

	my $hi_censr;
	if (! $main::vms_conversion )
	{
		my @_real;
        	($_real[$R4_0], $_real[$R4_1], $_real[$R4_2], $_real[$R4_3]) = unpack("CCCC",substr($tmp_buf,0,4));
        	$hi_censr = unpack("f",pack("CCCC", @_real));
	}
	elsif ($main::vms_conversion == $VMS2IEEE)
	{
		$hi_censr = xpFlt4VAXtoIEEE (substr($tmp_buf,0,4));
	}
	elsif ($main::vms_conversion == $IEEE2VMS)
	{
		$hi_censr = xpFlt4IEEEtoVAX (substr($tmp_buf,0,4));
	}
	else
	{
		confess ("$code stdf data conversion not supported\n");
	}

	if( $hi_censr > 1e20 )
	{
		wlog(1, "Hi Censor Limit Out Of EWB Range...\n");
		$hi_censr = 1e20;

		if ($main::vms_conversion == $VMS2IEEE)
		{
			$hi_censr = xpFlt4IEEEtoVAX(pack("CCCC", unpack("CCCC", pack("f", $hi_censr))));
		}
		elsif ($main::vms_conversion == $IEEE2VMS)
		{
			$hi_censr = xpFlt4VAXtoIEEE(pack("CCCC", unpack("CCCC", pack("f", $hi_censr))));
		}


		$tmp_buf2 = substr($buf,0,$total_bytes);
		if($R4_0 == 3)
		{
			$tmp_buf2 .= pack("CCCC",reverse unpack("CCCC", pack("f", $hi_censr)));
		}
		else
		{
			$tmp_buf2 .= pack("CCCC", unpack("CCCC", pack("f", $hi_censr)));
		}
		$tmp_buf2 .= substr($buf,$total_bytes+4,$rec_len);
		$buf = $tmp_buf2;
	}
	}
}

if (($rec_typ == 105) && ($rec_sub == 200 ))
  {
  #
  # we are reading an STDF+ wmr record.
  # which may be made up for multiple physical wmr records
  # followed by a terminating wmr record
  #
  # note:  this code does not support STDF+ Version < 202
  #
  if ($rec_len == 2)
    {
    #
    # we assume that the bin_cnt field is 0, if it is not, we are hosed anyhow
    # the null physical wmr record signals the end of the logical wmr record
    $reading_wmr_record=0 ;
    }
  else
    {
    $reading_wmr_record=1 ;
    }
  }

$read_rec_buf .= $head_buf.$buf ; # buffer for return result
                                  # appending will only occur for wmr

} while ($reading_wmr_record ) ;
#
# return the rec_typ, rec_sub and raw record
#
return ($status, $rec_len, $rec_typ, $rec_sub, $read_rec_buf ) ;
}

#
# read a record out of an ascii dump file generated from stdf_copy - ascii
#
# special syntax and conditions are needed for the first record in a file
#   spec should not be been loaded into namespace out
#   second parameter is used to return the stdf version
# see stdf_ascii_copy for proper use
# 
# 
sub read_ascii_head(@)
{
my $in = shift ;    # pointer to input file handle
my $dont_init_record = shift ;  # optional argument
my $rec_typ ;       # record sub type to be read in
my $rec_sub ;       # record sub type to be read in
my $status=undef ;  # return status to indicate EOF
my $recordname ;
my $fieldname ;
my $fieldvalue ;
my $stdf_ver ;
my $cpu_type ;
my $line ;

#
# go to begining of record
#
$line = <$in> ;

while (defined($line) && $line =~ /^\s*$/)
  {$line = <$in> ;}
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
  if ($line =~ /REC_LEN/)
    {
    ($recordname,()) = split /(\s|:)/, $line ;
    $recordname = lc($recordname) ;
    if (! $dont_init_record)  # stdf_copy_ascii inits records
      { undef %{'out::'.$recordname} ; }
    ${'out::'.$recordname}{'rec_len'}=0 ;
    $line = <$in> ;
    next ;
    }
  if ($line =~ /REC_NO=/)  # record number in file is not part of stdf
    {
    $line = <$in> ;
    next ;
    }
  undef $fieldname ;
  undef $fieldvalue ;
  $fieldname = substr($line, 0,index($line,'=')) ;
  $fieldvalue = substr($line, index($line,'=')+1) ;
  $fieldname=lc($fieldname) ;
  if (! defined($recordname))
    {
    confess "Error, record type undefined, line: $NR \n" ;
    }
  if ((%out::get_field_type) && (! ($out::get_field_type{$recordname}{$fieldname})) )
    { confess "$recordname.$fieldname is not valid, line: $NR" ; }
  #
  # appears as undefined in text file, but is really default value
  #
  if (!defined($fieldvalue) || ($fieldvalue eq '') )
    {
    wlog(1, "Warning, $recordname.$fieldname=undefined, setting to default, line: $NR\n") ;
    if (%out::init)
      {
      #
      # if not first record
      #
      if ( !defined($out::init{$recordname}{$fieldname}))
        {
        wlog(0, "Warning, $recordname.$fieldname=undefined, setting to default, line: $NR") ;
        confess "default value not defined" ;
        }
      else
        {
        # for some reason, if this code is executed before %out::init
        # is defined, then %out::init becomes defined !!
        ${'out::'.$recordname}{$fieldname} = $out::init{$recordname}{$fieldname} ;
}
        }
    else
      #
      # we don't have any default values yet
      # make it undefined, but existing hash element
      # caller is responsible for patching in defaults
      #
      {
      ${'out::'.$recordname}{$fieldname} = undef ;
      }
    }
  else
    { ${'out::'.$recordname}{$fieldname} = $fieldvalue ; }
  if ($fieldname eq 'rec_sub')
    {
    # initialize header information
    $rec_typ = ${'out::'.$recordname}{'rec_typ'} ;
    $rec_sub = ${'out::'.$recordname}{'rec_sub'} ;
    if ( %out::get_record_name )
      {
      my $tmp_recordname = lc($out::get_record_name{$rec_typ.'_'.$rec_sub}) ;
      if ( ! ($tmp_recordname eq $recordname) )
        {
        confess "Error, recordname=$recordname inconsistent with rec_typ=$rec_typ and rec_sub=$rec_sub " ;
        }
      }
    return (defined($status), $recordname ) ;
    }
    if ( (!defined($rec_typ) || !defined($rec_sub) || !defined($rec_len))
      && ! ($fieldname =~ /rec_len|rec_typ|rec_sub/) )
      { confess "Field before header, line: $NR \n" ; }
    $line = <$in> ;
#    $status = $line ;  # set up status in case we hit end of file
  }
return (defined($status), $recordname ) ;
}

#
# The EMIR record sucks because we don't have the initialization values until
# a spec had been read in, yet the EMIR allows blank values, but undefined values cause record truncation as designed
# user must set undefined values in the first record to defaults after call
#
sub read_ascii_rec(@)
{
my $in = shift ;    # pointer to input file handle
#my $rec_typ = shift ;       # record sub type to be read in
my $rec_typ ;       # record sub type to be read in
#my $rec_sub = shift ;       # record sub type to be read in
my $rec_sub ;       # record sub type to be read in
my $status=undef ;  # return status to indicate EOF
my $recordname = shift ;
my $fieldname ;
my $arrayfieldname ;
my $fieldvalue ;
my $stdf_ver ;
my $cpu_type ;
my $line ;
my $setvalue ;
my $last_field = '' ;
my $j = 0 ;

#
# go to begining of record
#
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
  if ($line =~ /REC_LEN/ || $line =~ /REC_NO=/ ||
     $line =~ /REC_TYP/ || $line =~ /REC_SUB/)
    { confess "Header needs to be read by read_ascii_head, not read_ascii_rec, line: $NR" ; }
  undef $fieldname ;
  undef $fieldvalue ;
  undef $arrayfieldname ;
  $fieldname = substr($line, 0,index($line,'=')) ;
  $arrayfieldname = lc($fieldname) ; # save the complete field name in case it
                                 # is an array
  $fieldname =~ s/\Q[\E.*// ;    # strip off array indexes if they exist
  $fieldvalue = substr($line, index($line,'=')+1) ;
  $fieldname=lc($fieldname) ;
  if ( ! defined($recordname))
    {
    confess "Error, record type undefined, line: $NR \n" ;
    }
  #
  # if get_field_type is not defined, we probably
  # have not loaded a specification file yet
  # somehow there is a way this hash gets set without reading the
  # specification ?? perl bug
  #
  if ((%out::get_field_type) && (! ($out::get_field_type{$recordname}{$fieldname})) )
    { confess "$recordname.$fieldname is not valid, line: $NR" ; }
  #
  # appears as undefined in text file, but is really default value
  #
  if (!defined($fieldvalue) || ($fieldvalue eq '') )
    {
    wlog(1, "Warning, $recordname.$fieldname=undefined, setting to default, line: $NR\n") ;
    if (%out::init)
      {
      #
      # if not first record
      #
      if ( !defined($out::init{$recordname}{$fieldname}))
        {
        wlog(0, "Warning, no default defined, $recordname.$fieldname='' $NR \n") ;
        $setvalue = $fieldvalue ;
#        confess "default value not defined" ;
        }
      else
        {
        # for some reason, if this code is executed before %out::init
        # is defined, then %out::init becomes defined !!
        $setvalue = $out::init{$recordname}{$fieldname} ;
        }
      }
    else
      #
      # we don't have any default values yet
      # make it undefined, but existing hash element
      # caller is responsible for patching in defaults
      #
      {
      $setvalue = undef ;
      }
    }
  else
    { $setvalue = $fieldvalue ; }
  #
  # if get_field_type is not defined, we probably
  # have not loaded a specification file yet
  # somehow there is a way this hash gets set without reading the
  # specification ?? perl bug
  #
  if ($last_field ne $fieldname)
    {
    $j = 0 ;  # reset array pointer
    $last_field = $fieldname ;
    }
  if ( (%out::get_field_type)
    && $out::get_field_type{$recordname}{$fieldname} =~ / x / )
    {
    if ($setvalue eq '[]') # an array of size 0
	{ @{'out::'.$recordname}{$fieldname}=[] ; } # set entire array
    else
	{ ${'out::'.$recordname}{$fieldname}[$j] = $setvalue ; } # set element of array
    $j++ ;
    }  
  else
    {  
    if ( $fieldname ne $arrayfieldname)
      {
      confess "Syntax error, array specified for non-array field, line: $NR" ;
      }
    ${'out::'.$recordname}{$fieldname} = $setvalue ;
    }
  $line = <$in> ;
  }
# $status = $line ;  # set up status in case we hit end of file

$stdf_ver = ${'out::'.$recordname}{'stdf_ver'} ;
$cpu_type = ${'out::'.$recordname}{'cpu_type'} = $running_cpu_type ;
if ( !(%out::get_record_name) )
  {
  if ( !defined($stdf_ver) )
    { confess "first record does not have STDF_VER" ; }
  if ( !defined($cpu_type) )
    { confess "first record does not have CPU_TYPE" ; }
  }
return (defined($status), $stdf_ver) ;
}

# Read the specified STDF file and return the STDF version.
sub get_stdf_version(@)
{
my $stdf_ver;
my $in = $_[0] ;    # pointer to input file name
my $len = 6 ;       #number of bytes to read
my $header_len = 4 ; # length of header
my $buf ;        # buffer ;
my $buf_remaining ;        # buffer ;
my $rec_len; my $rec_typ; my $rec_sub; my $cpu_type; my $stdf_ver ;
my $bytes_left ;    # bytes left to read in record after header and first 4 bytes
my $status ;  # return number of bytes eof is fatal here
my $i ; # unpack buffer index

open STDF_VIN, "<$in" or confess &lh, "Could not open STDF+ file for input $in\n" ;
binmode STDF_VIN ;

$status = read (STDF_VIN, $buf, $len) ;
if ($status != $len) { confess &lh, "Cannot read first $len bytes of file"; }

$i = 0 ;
init_byte_order(0, 0) ;                         # get rid of warnings (shouldn't affect functionality)
stdf_unpack( \"U*2 U*1 U*1 U*1 U*1", \$buf, \$i, \$rec_len, \$rec_typ, \$rec_sub, \$cpu_type, \$stdf_ver) ;

#HP Testers list CPU types as 128 ... treat this as a unix(solaris) type ..
if($cpu_type == 128)
{
	$cpu_type = 1;
}

$file_cpu_type = $cpu_type ;
#
# set up global byte swapping variables
# and vms conversion variables
#
init_swap_cnv($file_cpu_type, $running_cpu_type) ;
#
# set up indices used for unpack to determine byte ordering
# based on do_int_byte_swap and do_real_byte_swap
#
init_byte_order($do_int_byte_swap, $do_real_byte_swap) ;
#
# convert $rec_len from $file_cpu_type to $running_cpu_type 
#
#print "header_len: $header_len len: $len\n" ;
if ( $stdf_ver == 204 )
{
	$status = read (STDF_VIN, $buf, 2) ;
	if ($status != 2) { confess &lh, "Cannot read next 2 bytes of file"; }
	$i = 0 ;
	stdf_unpack(\"U*2", \$buf, \$i, \$stdf_ver ) ;
}
close( STDF_VIN );

return ( $stdf_ver ) ;
}
return(1) ;

