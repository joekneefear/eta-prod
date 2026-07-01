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
# 02-10-2000 Steve Frampton  Generated Code was not passing
#                            proper reference into
#                            stdf_pack_array/stdf_unpack_array.
#                            Needed to undefine arrays
#                            before unpacking.
#                            Needed to set array counts
#                            before packing.
# 02-21-2000 Steve Frampton  Pack routines now set the rec_len
#                            fields.
# 03-27-2006 Steve Frampton  Fixed issues with packing arrays.
#                            Boundry record truncation issues.
#

#
# Module used to parse *.spec files, generate data structures, and
# routines.  Should be generated into it's own name space to
# avoid conflicts if working with two versions of stdf.
#
# Spec files are very sensitive to delimiters !
# Comment '#' lines are allowed.  # must be in first character of line.
# Single empty lines are used to delimit STDF record definitions.
# Extra empty lines will break it.
# Empty lines are not allowed before the first record, or after the last.
# Fields are delimited by tab characters.  Extra tab characters or any
# space characters will cause problems !
# There is virtually no syntax checking at all.  Be carefull.
# Use the stdf_gen utility to syntax check *.spec files.
#
# if loading this via eval, be sure that syntax is correct
#   - use stdf_gen to syntax check spec file.
#
# Be very careful if you change it !
# It is very easy to break.
#

use Carp ;

#
# given an STDF specification file name, generate everything.
#
return(1) ;

sub generate_all
{
	my $version = '1.0' ;
	my $date = &time_stamp() ;
	#my $date = `date` ;
	my $fn = get_path(shift) ;  # search @INC for fn and return full path
	my $file = read_spec( $fn ) ;
	return (
	  &generate_get_record_name_hash( $file, $version, $date ) .
	  &generate_field_order_hash( $file, $version, $date ) .
	  &generate_init_hash( $file, $version, $date ) .
	  &generate_field_type_hash( $file, $version, $date ) .
	  &generate_packs( $file, $version, $date ) .
	  &generate_unpacks( $file, $version, $date )
	  ) ;
}

#
# search @INC for fn
#
sub get_path
{
	my $fn = shift ;
	my $full_fn ;
	my $prefix ;
	#
	# first, check to see if $fn is in pwd, or if full path was supplied
	#
	if ( -f $fn )
		{ return $fn ; }
	#
	# otherwise check @INC
	#
	foreach $prefix (@INC)
	  {
	  $full_fn = "$prefix/$fn" ;
	  if ( -f $full_fn )  # if we found file in path, return
		{ return $full_fn ; }
	  }
	#
	# can't find it, confess and give hint
	#
	confess "Cannot find $fn, try setting @INC by using perl -I directive or use FindBin; use lib \"$FindBin::Bin\"; " ;
}

#
# read specification file
#
sub read_spec
{
	my $in_fn = shift ;
	#
	# there is a problem with the file handle SPEC
	# it appears to end up global
	# SPEC used to be named INPUT
	# and in this case interferes with the global INPUT used by user code
	# especially if INPUT is opened as STDIN
	#
	local *SPEC ; 

	open SPEC, "<$in_fn" or confess, &lh, "Could not open $in_fn\n" ;
	#
	# read SPEC into string $file
	#
	$file = '' ;
	while ($line = <SPEC>) {$file .= $line; }
	close( SPEC ) ;
	return $file ;
}


#
# generate pack subroutines
#
# parse out information for each record into array @records
# records are delimited by one or more empty line
# no empty line within a record is allowed
#
sub generate_packs
{
	my $file = shift ;
	my $version = shift ;
	my $date = shift ;
	my @records = split /\n\n/, $file ;
	my $subroutine ;
	my $sub_name_preamble = 'pack_' ;
	my $stdf_pack = '&::stdf_pack' ;

	for my $record (@records)
	  {
	  # parse the record into array fields. strip out comments
	  # comment is a # sign in first character of line
	  my @fields =  grep /^[^#]/, ( split /\n/, $record ) ;
	  #
	  # parse first four lines of @fields.  Header information.
	  #
	  (my $record_name, my $title) = split /\t/, shift(@fields) ;
	  (my $rec_len_field_name, my $rec_len_type, my $default) = split /\t/, $fields[0] ;
	  ($field_name, my $rec_typ_type, my $rec_typ) = split /\t/, $fields[1] ;
	  ($field_name, my $rec_sub_type, my $rec_sub) = split /\t/, $fields[2] ;
	  shift(@fields) ; # remove length from @fields
	  shift(@fields) ; # remove rec_typ from @fields
	  shift(@fields) ; # remove rec_sub from @fields
	  #
	  # start forming subroutines
	  #
	  my $hash_name = '$'.lc($record_name) ;
	  my $subroutine_name = $sub_name_preamble.$record_name ;
	  $subroutine .=
	'# Generated: '.$subroutine_name.' Version number '.$version.'  '.$date."\n".
	'sub '.$subroutine_name.'
	{
	my '.$hash_name.' = shift ;
	my $header ;
	my $record ;
	my $rc ;
	my $rec_len ;
	' ;
	  #
	  # Now make record_name lower case, as it will be used from here on
	  #
	  $record_name = lc($record_name) ;
	  my @template ;
	  my @record_list ;
	  my $array_count_set="" ;
	  for $field (@fields)
		{
		(my $field_name, my $data_type, my $default) = split /\t/, $field ;
		push @template, $data_type ;
		if ($field_name eq 'CPU_TYPE')
		  { push @record_list, '$::running_cpu_type' ; }
		else
		  {
		  if ($data_type =~ / x / ) # does it have array delimiter ?
			{
		my $array_count ;
		my $type ;
		($array_count, $type) = split / x /, $data_type ;
		# initialize the array_count to undefined
			#$subroutine .= $array_count."=undef ;\n" ;
			$subroutine .= '
	(defined('.$array_count.')) && ('.$array_count."=0) ;\n" ;
		# define the array_count
			$array_count_set .= '
	if (defined('.'${'.lc($hash_name.'}{'.$field_name).'}))
	  {
	  '.$array_count."=".'$#{@{'.lc($hash_name.'}{'.$field_name)."}} + 1 ; 
	  }
        " ;
	  # MARK ('.$array_count.'=((!defined('.$array_count.'))||('.$array_count.'>'.'$#{@{'.lc($hash_name.'}{'.$field_name).'}})) ? '.$array_count."=".'$#{@{'.lc($hash_name.'}{'.$field_name)."}} + 1 : ".$array_count."\);
		# save hash and field names for later
		push @record_list, '@{'.lc($hash_name.'}{'.$field_name).'}' ;
		}
		  else
		# save hash and field names for later
			{push @record_list, '${'.lc($hash_name.'}{'.$field_name).'}' ; }
		  }
		}
		$subroutine .= $array_count_set ;
	  { # begin local variable scope
	  my @t = (), @r = ();
	  my $isarray = 0 ;

	  while ( $template[0] )
		{
		if ( $template[0] =~ / x / )  # if we have encountered an stdf array type and previous type was not an array
		  {
		  if ( $isarray == 0 )
			{
			$isarray = 1 ;
			# form regular pack
			$subroutine .= "\$rc = ".$stdf_pack."(\n" ;
		$subroutine .= "  \\'".join(' ',@t)."',\n  \\\$record,\n  \\" . join(",\n  \\",@r) . ") ; \n" ;
		@t = () ; @r = () ;
			}
		  (my $array_size, my $type) = split / x /, $template[0] ;
		  #$subroutine .= '(!defined('.$array_size.') || !defined('.$record_list[0].')) && goto HEADER ;'."\n(\$rc = &::stdf_pack_array(\\'".$type."', \\\$record, \\".$array_size.", \\".$record_list[0]. ")) ;\n" ;
		  $subroutine .= '('.$array_size.'>0)'." && (\$rc = &::stdf_pack_array(\\'".$type."', \\\$record, \\".$array_size.", \\".$record_list[0]. ")) ;\n" ;
		  }
		else
		  {
		  $isarray = 0 ;
		  push @t, $template[0] ; push @r, $record_list[0] ;
		  }
		shift @template; shift @record_list ;
		}
	  if ($isarray == 0) # tack on the final pack call ?
		{
		$isarray = 1 ;
		$subroutine .= "\$rc = ".$stdf_pack."(\n" ;
		$subroutine .= "  \\'".join(' ',@t)."',\n  \\\$record,\n  \\" . join(",\n  \\",@r) . ") .\n" ;
		}
	  } # end local variable scope
		# remove trailing '.' and return
		$subroutine =~ s/\Q.\E\n$/;/ ;
		$subroutine .= "
	\$\{$hash_name\}\{rec_len\}=".'length($record) ;

	$rc = '.$stdf_pack."(\n  \\'".$rec_len_type.' '.$rec_typ_type.' '.$rec_sub_type."',\n  \\\$header,\n  "."\\\$\{$hash_name\}\{rec_len\}".",\n  \\".$rec_typ.",\n  \\".$rec_sub.");\n  " ;
	  $subroutine .= "
	return(\$header . \$record) ;
	}\n\n\n" ; # return, and close subroutine
	  } # end for $record
	  return ( $subroutine ) ;
} # end of generate_packs

#
# generate unpack subroutines
#
# parse out information for each record into array @records
# records are delimited by one or more empty line
# no empty line within a record is allowed
#
sub generate_unpacks
{
	my $file = shift ;
	my $version = shift ;
	my $date = shift ;
	my @records = split /\n\n/, $file ;
	my $subroutine ;
	my $sub_name_preamble = 'unpack_' ;
	my $stdf_pack = '&::stdf_unpack' ;

	for my $record (@records)
	  {
	  # parse the record into array fields. strip out comments
	  # comment is a # sign in first character of line
	  my @fields =  grep /^[^#]/, ( split /\n/, $record ) ;
	  #
	  # parse first four lines of @fields.  Header information.
	  #
	  (my $record_name, my $title) = split /\t/, shift(@fields) ;
	  (my $rec_len_field_name, my $rec_len_type, my $default) = split /\t/, $fields[0] ;
	  ($field_name, my $rec_typ_type, my $rec_typ) = split /\t/, $fields[1] ;
	  ($field_name, my $rec_sub_type, my $rec_sub) = split /\t/, $fields[2] ;
	#  shift(@fields) ; # remove length from @fields
	#  shift(@fields) ; # remove rec_typ from @fields
	#  shift(@fields) ; # remove rec_sub from @fields
	  #
	  # start forming subroutines
	  #
	  my $hash_name = '$'.lc($record_name) ;
	  my $subroutine_name = $sub_name_preamble.$record_name ;
	  $subroutine .=
	'# Generated: '.$subroutine_name.' Version number '.$version.'  '.$date."\n".
	'sub '.$subroutine_name.'
	{
	my $record = shift ;
	my '.$hash_name.' = shift ;
	my $i = 0 ;
	my $rc ;
	my $f ;
	' ;
	  #
	  # Now make record_name lower case, as it will be used from here on
	  #
	  $record_name = lc($record_name) ;
	  my @template ;
	  my @record_list ;
	  for $field (@fields)
		{
		(my $field_name, my $data_type, my $default) = split /\t/, $field ;
		push @template, $data_type ;
		if ($data_type =~ / x / )  # if it is an array
		  { push @record_list, '@{'.lc($hash_name.'}{'.$field_name).'}' ; }
		else
		  { push @record_list, '${'.lc($hash_name.'}{'.$field_name).'}' ; }
		}
	  { # begin local variable scope
	  my @t = (), @r = ();
	  my $isarray = 0 ;

	  while ( $template[0] )
		{
		if ( $template[0] =~ / x / )  # if we have encountered an stdf array type and previous type was not an array
		  {
		  if ( $isarray == 0 )
			{
			$isarray = 1 ;
		# initialize scalar values as undefined
		$subroutine .= 'undef('.join("\);\nundef\(",@r)."\);\n" ;
			# form regular unpack
		   $subroutine .= "\$rc = ".$stdf_pack."(\n" ;
		  $subroutine .= "  \\'".join(' ',@t)."',\n  \$record,\n  \\\$i,\n  \\" . join(",\n  \\",@r) . ");\n" ;
		@t = () ; @r = () ;
			}
		  # initialize array values as undefined
		  $subroutine .= 'undef('.$record_list[0]."\);\n" ;
		  (my $array_size, my $type) = split / x /, $template[0] ;
		  $subroutine .= "\$rc = &::stdf_unpack_array(\\'".$type."', \$record, \\\$i, \\".$array_size.", \\".$record_list[0]. ") ;\n" ;
		  }
		else
		  {
		  $isarray = 0 ;
		  push @t, $template[0] ; push @r, $record_list[0] ;
		  }
		shift @template; shift @record_list ;
		}
	  if ($isarray == 0) # tack on the final pack call ?
		{
	#    $isarray = 1 ;
		# initialize values as undefined
		$subroutine .= 'undef('.join("\);\nundef\(",@r)."\);\n" ;
		# form regular unpack
		$subroutine .= "\$rc = ".$stdf_pack."(\n" ;
		$subroutine .= "  \\'".join(' ',@t)."',\n  \$record,\n  \\\$i,\n  \\" . join(",\n  \\",@r) . ");\n" ;
		}
	  } # end local variable scope
		$subroutine .= '
	return (0) ;' ;
	  $subroutine .= "
	}\n\n\n" ; # close subroutine
	  } # end for $record
	  return ( $subroutine ) ;
} # end of generate_packs


#
# return an alias
# not used anywhere ?
#

sub define_alias
{
	my $from=shift ;
	my $to=shift ;
	return (
	'# Define subroutine alias
	sub '.$to.' { return ('.$from.'(@_)); }
	' ) ;
}


#
# generate init hash
#
# parse out information for each record into array @records
# records are delimited by one or more empty line
# no empty line within a record is allowed
#
sub generate_init_hash
{
	my $file = shift ;
	my $version = shift ;
	my $date = shift ;
	my @records = split /\n\n/, $file ;
	my $hash ;
	my $hash_name = '%init' ;

	$hash .=
	'# Generated: '.$hash_name.' Version number '.$version.'  '.$date."\n".
	   $hash_name.' = (' ;
	for my $record (@records)
	  {
	  # parse the record into array fields. strip out comments
	  # comment is a # sign in first character of line
	  my @fields =  grep /^[^#]/, ( split /\n/, $record ) ;
	  #
	  # parse first four lines of @fields.  Header information.
	  #
	  (my $record_name, my $title) = split /\t/, shift(@fields) ;
	  (my $field_name, my $rec_len_type, my $default) = split /\t/, $fields[0] ;
	  ($field_name, my $rec_typ_type, my $rec_typ) = split /\t/, $fields[1] ;
	  ($field_name, my $rec_sub_type, my $rec_sub) = split /\t/, $fields[2] ;
	  #
	  # start forming subroutines
	  # subroutine names are uppper case, if record_name appears that way in spec
	  #
	  #
	  # Now make record_name lower case, as it will be used from here on
	  #
	  $record_name = lc($record_name) ;
	  $hash .= "\n  ".$record_name."=>{\n" ;
	  while (@fields)
		{
		(my $field_name, my $data_type, my $default) = split /\t/, shift(@fields) ;
	#    if ($field_name eq 'CPU_TYPE')  # always use the running_cpu_type
	#      { $default = '$::running_cpu_type' ; }
		$hash .= '     '.lc($field_name).'=>'.$default.",\n" ;
		}
	  $hash =~ s/,\n$// ; # remove comma and \n from last field_name  
	  $hash .= "}," ; # close hash, close return, close subroutine
	  } # end for $record
	  $hash =~ s/,$// ; # remove comma and \n from last field_name  
	  return ( $hash . "\n);\n\n\n" ) ;
} # end of generate_init_hash ;

#
# generate get_record_name hash
# record name is uppercase
# supercedes generate_init
#
# parse out information for each record into array @records
# records are delimited by one or more empty line
# no empty line within a record is allowed
#
sub generate_get_record_name_hash
{
	my $file = shift ;
	my $version = shift ;
	my $date = shift ;
	my @records = split /\n\n/, $file ;
	my @record_composition ;
	my $hash ;
	my $hash_name = '%get_record_name' ;

	$hash .=
	'# Generated: '.$hash_name.' Version number '.$version.'  '.$date."\n".
	$hash_name.' = (
	 ' ;
	for my $record (@records)
	  {
	  # parse the record into array fields. strip out comments
	  # comment is a # sign in first character of line
	  my @fields =  grep /^[^#]/, ( split /\n/, $record ) ;
	  #
	  # parse out the header for each record
	  # don't need anything else
	  #
	  (my $record_name, my $title) = split /\t/, shift(@fields) ;
	  (my $field_name, my $rec_len_type, my $default) = split /\t/, $fields[0] ;
	  ($field_name, my $rec_typ_type, my $rec_typ) = split /\t/, $fields[1] ;
	  ($field_name, my $rec_sub_type, my $rec_sub) = split /\t/, $fields[2] ;
	  push @record_composition, "'".$rec_typ.'_'.$rec_sub.'\'=>'.$record_name ;
	  } # end for $record
	  return ( $hash . join(",\n ", @record_composition) . "\n);\n\n\n" ) ;
}  # generate_get_record_name_hash

#
# generate get_field_order_hash
# record name is uppercase
#
# parse out information for each record into array @records
# records are delimited by one or more empty line
# no empty line within a record is allowed
#
sub generate_field_order_hash
{
	my $file    = shift ;
	my $version = shift ;
	my $date    = shift ;
	my @records = split /\n\n/, $file ;
	my $hash ;
	my $hash_name = '%get_field_order' ;

	$hash .=
	'# Generated: '.$hash_name.' Version number '.$version.'  '.$date."\n".
	   $hash_name.' = (' ;
	for my $record (@records)
	  {
	  # parse the record into array fields. strip out comments
	  # comment is a # sign in first character of line
	  my @fields =  grep /^[^#]/, ( split /\n/, $record ) ;
	  #
	  # parse first four lines of @fields.  Header information.
	  #
	  (my $record_name, my $title) = split /\t/, shift(@fields) ;
	  (my $field_name, my $rec_len_type, my $default) = split /\t/, $fields[0] ;
	  ($field_name, my $rec_typ_type, my $rec_typ) = split /\t/, $fields[1] ;
	  ($field_name, my $rec_sub_type, my $rec_sub) = split /\t/, $fields[2] ;
	  #
	  # start forming subroutines
	  # subroutine names are uppper case, if record_name appears that way in spec
	  #
	  #
	  # Now make record_name lower case, as it will be used from here on
	  #
	  $record_name = lc($record_name) ;
	  $hash .= "\n  ".$record_name."=>[\n" ;
	  while (@fields)
		{
		(my $field_name, my $data_type, my $default) = split /\t/, shift(@fields) ;
		$hash .= "    '".lc($field_name)."',\n" ;
		}
	  $hash =~ s/,\n$// ; # remove comma and \n from last field_name  
	  $hash .= "]," ; # close array, close return, close subroutine
	  } # end for $record
	  $hash =~ s/,$// ; # remove comma and \n from last field_name  
	  return ( $hash . "\n);\n\n\n" ) ;
} # end of 

#
# generate get_field_type hash
# record name is lowercase
#
# parse out information for each record into array @records
# records are delimited by one or more empty line
# no empty line within a record is allowed
#
sub generate_field_type_hash
{
	my $file = shift ;
	my $version = shift ;
	my $date = shift ;
	my @records = split /\n\n/, $file ;
	my $hash ;
	my $hash_name = '%get_field_type' ;

	$hash .=
	'# Generated: '.$hash_name.' Version number '.$version.'  '.$date."\n".
	   $hash_name.' = (' ;
	for my $record (@records)
	  {
	  # parse the record into array fields. strip out comments
	  # comment is a # sign in first character of line
	  my @fields =  grep /^[^#]/, ( split /\n/, $record ) ;
	  #
	  # parse first four lines of @fields.  Header information.
	  #
	  (my $record_name, my $title) = split /\t/, shift(@fields) ;
	  (my $field_name, my $rec_len_type, my $default) = split /\t/, $fields[0] ;
	  ($field_name, my $rec_typ_type, my $rec_typ) = split /\t/, $fields[1] ;
	  ($field_name, my $rec_sub_type, my $rec_sub) = split /\t/, $fields[2] ;
	  #
	  # start forming subroutines
	  # subroutine names are uppper case, if record_name appears that way in spec
	  #
	  #
	  # Now make record_name lower case, as it will be used from here on
	  #
	  $record_name = lc($record_name) ;
	  $hash .= "\n  ".$record_name."=>{\n" ;
	  while (@fields)
		{
		(my $field_name, my $data_type, my $default) = split /\t/, shift(@fields) ;
		$hash .= "    ".lc($field_name)."=>'".$data_type."',\n" ;
		}
	  $hash =~ s/,\n$// ; # remove comma and \n from last field_name  
	  $hash .= "}," ; # close array, close return, close subroutine
	  } # end for $record
	  $hash =~ s/,$// ; # remove comma and \n from last field_name  
	  return ( $hash . "\n);\n\n\n" ) ;
} # end of 

sub time_stamp
{
	(my $sec,my $min,my $hour,
	my $mday,my $mon,my $year,
	my $wday,my $yday,my $isdst) = localtime(time) ;
	my $datestr = sprintf( "%04d%02d%02d%02d%02d%02d",
	  $year+1900,$mon+1,$mday,$hour,$min,$sec ) ;
	return($datestr) ;
}

