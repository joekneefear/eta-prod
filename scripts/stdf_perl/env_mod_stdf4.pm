# 26-Mar-2016 Gilbert Created;
sub pre_parse_module
{
	########################
	# SET FLAGS & VARIABLES
	########################
	$cfg_make_tp	= "Y";
	$test_mul	= 1;
	$use_seq_name	= "N";
	$swb_from_tsr	= "N";
	$prbcard_from_suprnam = "Y";
}

sub post_parse_module
{
	$MIR{1}{NODE_NAM} = lc($MIR{1}{NODE_NAM});
}
1;
