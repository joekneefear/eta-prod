# 26-May-2014 Eric Alfanta	set node_nam to lower case and defaulted tstr_typ to "SZ";
sub pre_parse_module
{
	########################
	# SET FLAGS & VARIABLES
	########################
	$cfg_make_tp	= "Y";
	$test_mul	= 1;
	$use_seq_name	= "Y";
	#$tp_prefix	= "SZ";
	$swb_from_tsr	= "Y";
	$prbcard_from_suprnam = "Y";
}

sub post_parse_module
{
	$MIR{1}{NODE_NAM} = lc($MIR{1}{NODE_NAM});
	$MIR{1}{TSTR_TYP} = "SZ";
}



1;
