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
# 02-10-2000 Steve Frampton  Modified write_ascii to do arrays
# 03-28-2006 Steve Frampton  Re-wrote write_stdf_hex to fix bug.
#                            Did not display last line in str format.
#                            Added strip_bin option
# 08-06-2006 Steve Frampton  Added pattern match option for record


#
# Routines used by stdf_copy, stdf_copy_ascii
# and who ever wants to use them
# All the routines in this file assume that the input
# specification and the output specification are the same
#

#
# passing in a file is optional
# if $in::get_record_name is defined for record, and unpack
# routine exists for record unpack and print, otherwise, hex dump
#
sub stdf_write_ascii
{
	my $total_bytes_read = shift ;
	my $rec_len = shift ;
	my $rec_typ = shift ;
	my $rec_sub = shift ;
	my $buf = shift ;
	my $file = shift ;
	my $record_number = shift ;
	my $match = shift ;
	my $fname ; # name in uppercase for function names
	my $vname ; #name in lowercase for hash names

	if (! defined($file) ) { $file = \*STDOUT ; }

	if (! defined($fname=$in::get_record_name{$rec_typ.'_'.$rec_sub}) 
	   || !defined(&{'in::unpack_'.$fname}) )
	  { stdf_write_hex( $total_bytes_read, $rec_len, $rec_typ, $rec_sub, $buf, $file );}
	else
	  {
	  $vname=lc($fname) ;
	  &{'in::unpack_'.$fname}(\$buf, \%{'in::'.$vname}) ;
	  if (defined(&{'in::write_ascii_'.$fname}))
		{
		#
		# Custom way to print a record, if defined
		#
		&{'in::write_ascii_'.$fname}(\%{'in::'.$vname}, $file, $record_number) ;
		}
	  else
		{
		#
		# The generic way to print a record
		#
		my $outstr ;
		$outstr = "\t".$fname." :\tREC_LEN=".$rec_len."\n" ;
		$outstr .= "\t\tREC_NO=".$record_number."\n" ;
		my $array_len = $#{$in::get_field_order{$vname}} ;
		foreach my $field ( @{$in::get_field_order{$vname}}[1..$array_len] )
		  {
		  if ( $in::get_field_type{$vname}{$field} =~ / x / )
			{
			#
			# Print out an array
			#
			if (defined(@{'in::'.$vname}{$field}) )
				{
				for (my $j=0; $j <= $#{@{'in::'.$vname}{$field}} ; $j++ )
				  {
				  $outstr.="\t\t".uc($field)."[$j]=".${'in::'.$vname}{$field}[$j]."\n" ;
				  }
				}
			else
				{
				$outstr.="\t\t".uc($field)."="."[]\n" ;
				}
			}
		  else
			{
		#
		# Print scalar
		#
			my $outfield = ${'in::'.$vname}{$field} ;
			( defined(${'in::'.$vname}{$field}) ) || last ;
			# optionally strip out any binary characters
			# for use with diff utility
			# especially NULLs in EMIR.SPEC_REV
			($strip_bin) && ($outfield =~ s/[^[:print:]]+//g ) ;
			
			$outstr.="\t\t".uc($field)."=".$outfield."\n" ;
			}
		  }
		return if (defined($match) && (!($outstr =~ /$match/s))) ;
		print $file $outstr."\n\n" ;
		}
	  }
}


#
# hex dump a record
# for error messages and utilities
#
sub stdf_write_hex
{
	my $total_bytes_read = shift ;
	my $rec_len = shift ;
	my $rec_typ = shift ;
	my $rec_sub = shift ;
	my $buf = shift ;
	my $file = shift ;
	my $record_number = shift ;
	my $byte_count = 0 ;
	my $name ;

	if (! defined($file) ) { $file = \*STDOUT ; }
	if (defined($name=$in::get_record_name{$rec_typ.'_'.$rec_sub}))
	  {
	  print $file "Record Name:  $name\n" ;
	  }
	else
	  {
	  print $file "Record Name:  Undefined in input specification\n" ;
	  }
	printf $file "file position:   %5d\n", $total_bytes_read ;
	printf $file "file position: %7x\n", $total_bytes_read ;
	printf $file "REC_LEN: %4d REC_TYP: %3d REC_SUB: %3d\n",
			 $rec_len, $rec_typ, $rec_sub ;
	printf $file "REC_LEN: %4x REC_TYP:  %2x REC_SUB:  %2x\n",
			 $rec_len, $rec_typ, $rec_sub ;
	print $file "REC_NO=", $record_number, "\n" ;

	my @lines ;
	# pad hex string to this length
	#                 16 characters
	#                      2 hex digits per characters
	#                                add a space every 4 hex digits
	$hexstrprint_len=(0x10*2+(0x10*2/4)) ;  # adds up to 40
	# split buf into @lines of 16 characters
	for (my $i=0;$i<length($buf);$i+=0x10)
		{
		push @lines,substr($buf,$i,0x10) ;	
		}
	# format and print each line
	foreach my $line (@lines)
		{
		# format hex string
		my $hexstrprint ;
		for (my $i=0;$i<length($line);$i++)
			{
			# get two character hex representation
			$hexstrprint.=unpack(H2,substr($line,$i,1)) ;
			# add a space every 2 bytes, or 4 hex digits
			if ($i % 2)
				{
				$hexstrprint.=" " ;
				}
			}
		# padd out string to $hexstrprint_len with spaces
		$hexstrprint.=" "x($hexstrprint_len-length($hexstrprint)) ;
		# form printable character representation
		my $chstrprint = $line ;
		$chstrprint =~ s/[\t\n\r\f]/\./g ; # change these characters to '.'
		$chstrprint =~ s/[^[:print:]]/\./g ; # change non-printable characters to '.'
		printf $file "\n%7x %s    %s",$byte_count,$hexstrprint."    ",$chstrprint ;
		$byte_count+=0x10 ;
		}
print $file "\n\n\n" ;
}


#
# passing in a file is optional
# Use for stdf to stdf copy when input and output are the same
# versions.
# Use for record stripper ?
# Use to translate to local cpu format.
#
sub stdf_write_binary
{
	my $total_bytes_read = shift ;
	my $rec_len = shift ;
	my $rec_typ = shift ;
	my $rec_sub = shift ;
	my $buf = shift ;
	my $file = shift ;
	my $fname ; # name in uppercase for function names
	my $vname ; #name in lowercase for hash names

	if (! defined($file) ) { $file = \*STDOUT ; }

	if (! defined($fname=$in::get_record_name{$rec_typ.'_'.$rec_sub}) 
	   || !defined(&{'in::unpack_'.$fname}) || !defined(&{'in::pack_'.$fname} ) )
	  { stdf_write_hex( $total_bytes_read, $rec_len, $rec_typ, $rec_sub, $buf, \*STDERR );}
	else
	  {
	  #
	  # unpack record
	  #
	  $vname=lc($fname) ;
	  &{'in::unpack_'.$fname}(\$buf, \%{'in::'.$vname}) ;
	  #
	  # pack record and output
	  #
	  my $outbuf = &{'in::pack_'.$fname}(\%{'in::'.$vname}) ;
	  print $file $outbuf ;
	  }
}

return(1) ;
