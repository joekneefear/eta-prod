sub pre_parse_module
{

	########################
	# SET FLAGS & VARIABLES
	########################
	$req_yld_file  = "Y";		### REQUIRE YLD FILE
        $req_tfc_file  = "Y";		### REQUIRE TFC FILE
	$test_num_mod  = 0;		### USE ORIG TEST_NUM
        $byte_8_or_32  = 32;		### READ 32 BYTES FOR THE FILENAME FIELD


	#####################################
	# GET LOTID FROM THE ACTUAL FILENAME 
	#####################################
        my (@dummy) = split /\//, $file;
           (@dummy) = split /\_|\./, $dummy[$#dummy];
           $lotid   = $dummy[0];

}

sub post_parse_module
{

	################
	# CLEAN TP_NAME
	################
	($testplan,) = split /TST/i, $testplan;

	#######################
	# MODIFY TESTPLAN DATA
	#######################
	foreach my $test_num(sort {$a<=>$b} keys %tp)
	{
		### APPEND BIAS1 VALUE TO TEST_NAME ###
		my ($dump,$bias1,$dump)          = split /[=_]/, $tp{$test_num}{BIAS};
		$tp{$test_num}{LIMIT_ITEM_NAME} .= $bias1;

		### ADD SBIN NUMBER AND NAME ###
		$tp{$test_num}{SBIN_NUM} = $test_num;
		$tp{$test_num}{SBIN_NAM} = $tp{$test_num}{LIMIT_ITEM_NAME};
	}

}



1;
