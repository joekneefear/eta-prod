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
# 09-27-1999 Steve Frampton  Original.  Contact Information:
#                            (207) 273-3364
#                            sframpto@fairchildsemi.com
#                            Moved from resolve_tp
# 03-15-2001 Steve Frampton  Removed reference to out:: namespace
#
# Routines for dealing with spec_rev fields and edb
# Common to next_tp and resolve_tp
#

#
# update test data EMIR record with new spec_rev
#
use Sybase::CTlib;
use Carp ;

sub update_test_data_EMIR
{
my $td_fn = shift ;
my $spec_rev = shift ;
my %emir ;
local *TD ;

#
# read file and get EMIR record
#
open TD, "<$td_fn" or confess &::lh, "Could not open test data file for update: $td_fn" ;
binmode TD ;
(my $length, my $rec_len, my $rec_typ, my $rec_sub, my $buf)
  = &::read_first_rec( \*TD, $stdf_ver ) ;
close TD ;
if ( ! ($get_record_name{$rec_typ.'_'.$rec_sub} eq 'EMIR') )
  { confess &::lh, "First record in test data file is not an EMIR" ; }
&unpack_EMIR(\$buf, \%emir) ;
#
# update EMIR record with new spec_rev
#
my $len = length($emir{spec_rev}) ;
$emir{spec_rev} = &::pad($spec_rev,"\0",$len) ; # pad to same length
return( &update_EMIR(\%emir, $td_fn) ) ;
}


#
# the subroutines below have clean interfaces and
# don't generally use global variables
#
# requires Sybase::CTlib ;


sub get_latest_tp_rev_from_edb
{
	my $EDB = shift ;  # edb db connection
	my $test_plan = shift ;
	my $test_plan_rev = shift ;
	my $max_rt = shift ;
	my @edb_test_plan_rev ;
	my $tp ;
	my @garbage ;
	my $rc ;

	my $sql = '
	declare @max_rev int 
	select @max_rev=max(convert(int,substring(test_plan_rev,charindex(".",test_plan_rev)+1,255) ))
	  from test_plan
	  where test_plan = "'.$test_plan.'"
		and test_plan_rev like "'.$test_plan_rev.'.%"
	select test_plan_rev
	  from test_plan
	  where test_plan = "'.$test_plan.'"
		and test_plan_rev like "'.$test_plan_rev.'.%"
		and convert(int,substring(test_plan_rev,charindex(".",test_plan_rev)+1,255) )=@max_rev
	' ;
	

	$EDB->ct_execute($sql) || confess &::lh, "execute failed!";

	while(($rc = $EDB->ct_results($restype)) == CS_SUCCEED)
	  {
		if ($restype == CS_CMD_FAIL || $restype == CS_CMD_SUCCEED)
		  { next; }
		if ($restype == CS_CMD_DONE)
		  {
		  $ROWCOUNT=$EDB->ct_res_info(CS_ROW_COUNT);
		   #print "ROWCOUNT == $ROWCOUNT\n";
		  next; 
		  }
		while( ( (), $tp) = $EDB->ct_fetch) 
		  { push @edb_test_plan_rev, $tp ; }
	  }
	if ($syb_error)
	  {
	  confess ;
	  }
	$edb_test_plan_rev[0] =~ s/^.+\Q.\E// ; # remove characters before '.'
	$edb_test_plan_rev[0] =~ s/ +$// ; # remove trailing spaces
	if ( $edb_test_plan_rev[0] eq ('9' x $max_rt))
	  {confess &::lh, "EDB Test Plan Revision may Overflow edb:  $edb_test_plan_rev[0]" ;}

	return ( $edb_test_plan_rev[0] ) ;
}

#
# check to make sure that revision passed in is valid
# must be all digits with none right of decimal point
# must be less than 2 significant digits left of decimal point
# decimal point is optional
#
sub format_file_rev
{
	my $rev = shift ;
	my $max_len = shift ; # maximum length of string
	my $max_rt = shift ; # maximum length of string right of decimal
	my $fixed_rev = $rev ; 

	$fixed_rev =~ s/\0//g ; # remove null characters
	$fixed_rev =~ s/^ +// ; # remove leading spaces
	$fixed_rev =~ s/ +$// ; # remove trailing spaces
	$fixed_rev =~ s/^0+// ; # remove leading 0's
	#if ( $fixed_rev =~ /\Q.\E.+/ ) 
	#  {confess &::lh, "File Test Plan Revision: no characters allowed right of decimal $rev";}
	$fixed_rev =~ s/\Q.\E.+// ; # remove trailing decimals
	my $max_lft = $max_len-$max_rt-1 ; 
	if ( length($fixed_rev) > $max_lft )
	  {confess &::lh, "File Test Plan Revision: length(".$rev.") > ",$max_lft ;}
	if ($fixed_rev eq '')
	  { $fixed_rev = '0'; } # if we stripped naked
	if ( ! ($fixed_rev =~ /^\d+$/) )
	  {confess &::lh, "File Test Plan Revision:  Invalid Characters: $rev";}
	if ( $fixed_rev eq ('9' x $max_lft))
	  {confess &::lh, "File Test Plan Revision (Test Program Revison ?) may Overflow edb:  $rev" ;}
	return ( $fixed_rev ) ;
}

return(1) ;
