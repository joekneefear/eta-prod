sub pre_parse_module
{
	### SETTINGS ###
	$test_num_mod = 0;	### USE TEST NUMBER AS IS
	$use_dta_bin  = "Y";	### GENERATE HBR FROM DTA BIN DATA
	$data_type    = "FT";
}


sub post_parse_module
{

	#####################################
	# GET LOTID FROM THE ACTUAL FILENAME 
	#####################################
        my (@dummy) = split /\//, $file;
           (@dummy) = split /\_|\./, $dummy[$#dummy];
           $lotid   = $dummy[0];
	   $lotid   = substr($lotid,0,10) if ($lotid =~ /^A0/i && length($lotid) > 10);

	
        #######################
        # MODIFY TESTPLAN DATA
        #######################
        foreach my $test_num(sort {$a<=>$b} keys %tp)
        {
	
                ### UPPER VALID LIMIT ###
                if ($tp{$test_num}{HI_SPEC_LIM} < 0)
                {
                        $tp{$test_num}{HI_CENSOR} = $tp{$test_num}{HI_SPEC_LIM} - ($tp{$test_num}{HI_SPEC_LIM}/2);
                }
                elsif ($tp{$test_num}{HI_SPEC_LIM} > 0 && $tp{$test_num}{HI_SPEC_LIM} != 1e20)
                {
                        $tp{$test_num}{HI_CENSOR} = $tp{$test_num}{HI_SPEC_LIM} + ($tp{$test_num}{HI_SPEC_LIM}/2);
                }

                ### LOWER VALID LIMIT ###
                if ($tp{$test_num}{LOW_SPEC_LIM} < 0 && $tp{$test_num}{LOW_SPEC_LIM} != -1e20)
                {
                        $tp{$test_num}{LOW_CENSOR} = $tp{$test_num}{LOW_SPEC_LIM} + ($tp{$test_num}{LOW_SPEC_LIM}/2);
                }
                elsif ($tp{$test_num}{LOW_SPEC_LIM} > 0)
                {
                        $tp{$test_num}{LOW_CENSOR} = $tp{$test_num}{LOW_SPEC_LIM} - ($tp{$test_num}{LOW_SPEC_LIM}/2);
                }

                ### ADD SBIN NUMBER AND NAME ###
                $tp{$test_num}{SBIN_NUM} = $test_num;
                $tp{$test_num}{SBIN_NAM} = $tp{$test_num}{LIMIT_ITEM_NAME};
        }

}


1;
