# 2016-Nov-17 Eric	: extracting lotid from filename no longer applies.
sub pre_parse_module
{
        #$test_num_mod = 1000;
        #$byte_8_or_32 = 32;
        #$data_type    = "WS";
	$use_file_date = "N";		
	$site	       = "FSST";
}

sub post_parse_module
{
        my @dummy = ();
        my $fn    = $file;

        ### GET LOTID AND SRC_LOTID FROM THE ACTUAL FILENAME ###
	$fn                              =~ s/\.NOEXT//i;
        $fn                              =~ s/\.dta//i;
        (@dummy)                         = split /\//, $fn;
        (@dummy)                         = split /\_/, $dummy[$#dummy];
        #($glob_src_lot, $testrun)        = split /\-/, $dummy[0]; #TESTRUN VALUE e.g. FT1 or FT2 or FT2A

        ###############################################################################################
        #PSI_LOT_ID HAS TO BE 4 OR MORE CHARACTERS AND IT SHOULD START WITH A LETTER FIRST THEN AT
        #LEAST ONE NUMBER SHOULD FOLLOW IN THE SUCCEEDING CHARACTERS - FOR IT BE BE USED AS
        #EMIR.LOTID. ELSE FAIRCHILD_LOT_ID WILL BE USED AS EMIR.LOTID.
        ###############################################################################################
	#$dummy[2] =~ s/\.+//g; #REMOVE TRAILING DOTS IN NAME
        #if (length($dummy[2]) >= 4 && $dummy[2] =~ /^[a-zA-Z]+\d+/)
        #{
        #        #GET THE FIRST 8 CHARACTERS FROM THE 2ND PARAMETER#
        #        $lotid   = substr($dummy[2],0,8);
        #}
        #else
        #{
        #        $lotid   = $glob_src_lot;
        #}
	#$lotid =~ s/\.+//g; #REMOVE TRAILING DOTS IN NAME
	#############################################################################################
	$glob_part_type = $dummy[1];
	#$lotid = $dummy[2];
	#$lotid =~ s/\.+//g; #REMOVE TRAILING DOTS IN NAME	

	#########################
	# CLEAN TP_NAME & DEVICE
	#########################
	($testplan,) = split /TST/i, $testplan;
	($device,)   = split /TST/i, $device;
	
}



1;

