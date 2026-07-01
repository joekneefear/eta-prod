#
#
# Date       Who	    Comments
# ---------- -------------- ------------------------------------------------
# 12/09/2009 Ben Rommel Kho Assigned ProductID to part_typ and device fields
#
#

sub WriteWSBR
{
	my ($sbin_number, $sbin_count, $sbin_name) = @_;

	%out::wsbr = %{$out::init{wsbr}};

	$out::wsbr{sbin_num} = $sbin_number;
	$out::wsbr{sbin_cnt} = $sbin_count;
	$out::wsbr{sbin_nam} = "";
	
	print OUTPUT &out::pack_WSBR(\%out::wsbr);
	
	return (1);
}


sub WriteSBR
{
        my ($sbin_number, $sbin_count, $sbin_name) = @_;

        %out::sbr = %{$out::init{sbr}};

	if ($sbin_number eq "1")
	{
		$sbin_count =~ $sbin_count + 16384;
	}
        $out::sbr{sbin_num} = $sbin_number;
        $out::sbr{sbin_cnt} = $sbin_count;
        $out::sbr{sbin_nam} = "";

        print OUTPUT &out::pack_SBR(\%out::sbr);

        return (1);
}


sub WriteWHBR
{
        my ($hbin_number, $hbin_count, $hbin_name) = @_;

	if ($hbin_number eq "1")
        {
                # Don't include the good bin counts
		return 0;
	}

        %out::whbr = %{$out::init{whbr}};

        $out::whbr{hbin_num} = $hbin_number;
        $out::whbr{hbin_cnt} = $hbin_count;
        $out::whbr{hbin_nam} = "";

        print OUTPUT &out::pack_WHBR(\%out::whbr);
        $WHBRCnt++;

        return ($WHBRCnt);
}

sub WriteHBR
{
        my ($hbin_number, $hbin_count, $hbin_name) = @_;

	if ($hbin_number eq "1")
	{
		# Don't include the good bin counts
		return 0;
	}
        %out::hbr = %{$out::init{hbr}};

        $out::hbr{hbin_num} = $hbin_number;
        $out::hbr{hbin_cnt} = $hbin_count;
        $out::hbr{hbin_nam} = "";

        print OUTPUT &out::pack_HBR(\%out::hbr);

        return 1;
}



sub PopulateEMIR
{
	%out::emir = %{$out::init{emir}};

	$out::emir{lot_id}      = $MIR{1}{LOT_ID};
	$out::emir{stat_num}    = $MIR{1}{STAT_NUM};
	$out::emir{customer}    = "FSMT";
	$out::emir{sblot_id}    = $MIR{1}{SBLOT_ID};
	$out::emir{hand_id}     = $MIR{1}{HAND_ID};
	$out::emir{spec_nam}    = $MIR{1}{JOB_NAM};
	$out::emir{job_nam}     = $MIR{1}{JOB_NAM};
	$out::emir{setup_t}     = $MIR{1}{SETUP_T};
	$out::emir{start_t}     = $MIR{1}{START_T};
	$out::emir{oper_nam}    = $MIR{1}{OPER_NAM};
	$out::emir{prb_card}    = $MIR{1}{SUPR_NAM};
	$out::emir{mode_cod}    = "P";
	$out::emir{tstr_typ}    = $MIR{1}{TSTR_TYP};
	$out::emir{node_nam}    = $MIR{1}{NODE_NAM};
	$out::emir{part_typ}    = uc $MIR{1}{PART_TYP} if $MIR{1}{PART_TYP} ne "";
        $out::emir{device}      = uc $MIR{1}{PART_TYP} if $MIR{1}{PART_TYP} ne "";


	if ($MIR{1}{JOB_REV} eq "")
	{
        	$out::emir{job_rev} = 0;
        	$out::emir{spec_rev} = 0;
	}
	else
	{
        	$out::emir{job_rev}     = $MIR{1}{JOB_REV};
        	$out::emir{spec_rev}    = $MIR{1}{JOB_REV};
	}
	print OUTPUT &out::pack_EMIR(\%out::emir);
}

sub PopulateWIR
{
	my ($WIR_START_TIME, $WIR_Wafer_ID, $WIR_NODE_NAM) = @_;
	%out::wir  = %{$out::init{wir}};

	$out::wir{node_nam} = $WIR_NODE_NAM;
	$out::wir{start_t} =  $WIR_START_TIME;
        $out::wir{wafer_id} = $WIR_Wafer_ID;
        print OUTPUT &out::pack_WIR(\%out::wir) ;		
}

sub WritePIR
{
        my ($HeadNum, $SiteNum, $X, $Y, $PartID) = @_;

	if ($HeadNum eq "")
	{
		$HeadNum = "";
	}
        %out::pir           = %{$out::init{pir}} ;
	$out::pir{head_num} = $HeadNum;
        $out::pir{site_num}  = $SiteNum;
	$out::pir{x_coord}  = $X;
	$out::pir{y_coord}  = $Y;
	$out::pir{part_id}  = $PartID;
        ##########################################
        #
        # Write PIR record
        #
        print OUTPUT &out::pack_PIR(\%out::pir) ;
        ##########################################
}

sub WritePTR
{
        my (	$test_num, $head_num, $site_num, $test_flg, $parm_flg, $result, $opt_flg, $res_scal, $res_ldig,
		$res_rdig, $desc_flg, $units, $llm_scal, $hlm_scal, $llm_ldig, $llm_rdig, $hlm_ldig, $hlm_rdig,
		$lo_limit, $hi_limit, $test_nam, $seq_name, $test_txt
	   ) = @_;

        %out::ptr = %{$out::init{ptr}} ;

        $out::ptr{test_num} = $test_num;
	$out::ptr{head_num} = $head_num;
        $out::ptr{site_num} = $site_num;
        $out::ptr{test_flg} = $test_flg;
	$out::ptr{parm_flg} = $parm_flg;
        $out::ptr{result}   = $result;
	$out::ptr{opt_flg}  = $opt_flg; 
	$out::ptr{res_scal} = $res_scal;
	$out::ptr{res_ldig} = $res_ldig;
	$out::ptr{res_rdig} = $res_rdig;
	$out::ptr{desc_flg} = $desc_flg;
        $out::ptr{units}    = $unit;
	$out::ptr{llm_scal} = $llm_scal;
	$out::ptr{hlm_scal} = $hlm_scal;
	$out::ptr{llm_ldig} = $llm_ldig;
	$out::ptr{llm_rdig} = $llm_rdig;
	$out::ptr{hlm_ldig} = $hlm_ldig;
	$out::ptr{hlm_rdig} = $hlm_rdig;
	$out::ptr{lo_limit} = $lo_limit;
	$out::ptr{hi_limit} = $hi_limit;
        $out::ptr{test_nam} = $test_nam;
	$out::ptr{seq_name} = $seq_name;
        $out::ptr{test_txt} = $$test_txt;

        ##########################################
        # Write PTR record
        #
        print OUTPUT &out::pack_PTR(\%out::ptr) ;
        ##########################################
}

sub WriteEPRR
{
        my (
		$Head_Num,
		$Site_Num,
		$Num_Test,
		$Hard_Bin,
		$Soft_Bin,
		$Part_Flg,
		$Pad_Byte,
		$X,
		$Y,
		$Part_Id,
		$Part_Txt,
		$Part_Fix) = @_;

        %out::eprr = %{$out::init{eprr}};
	$out::eprr{head_num} = $Head_Num;
        $out::eprr{site_num} = $Site_Num;
        $out::eprr{num_test} = $Num_Test;
        $out::eprr{hard_bin} = $Hard_Bin;
        $out::eprr{soft_bin} = $Soft_Bin;
        $out::eprr{part_flg} = $Part_Flg;
        $out::eprr{pad_byte} = $Pad_Byte;
        $out::eprr{x_coord}  = $X;
        $out::eprr{y_coord}  = $Y;
	$out::eprr{part_id}  = $Part_Id;
        $out::eprr{part_txt} = $Part_Txt;
        $out::eprr{part_fix} = $Part_Fix;
        print OUTPUT &out::pack_EPRR(\%out::eprr);
}

sub WriteWRR
{
	my ($finish_t, $head_num, $pad_byte, $part_cnt, $rtst_cnt, $abrt_cnt, $good_cnt, $func_cnt,
	 	$wafer_id, $hand_id, $prb_card, $usr_desc, $exc_desc) = @_;

	%out::wrr = %{$out::init{wrr}};

	$out::wrr{finsih_t} = $finish_t;
	$out::wrr{head_num} = $head_num;
	$out::wrr{pad_byte} = $pad_byte;
	$out::wrr{part_cnt} = $part_cnt;
	$out::wrr{rtst_cnt} = $rtst_cnt;
        $out::wrr{abrt_cnt} = $abrt_cnt;
        $out::wrr{good_cnt} = $good_cnt;
        $out::wrr{func_cnt} = $func_cnt;
	$out::wrr{wafer_id} = $wafer_id;
        $out::wrr{hand_id}  = $hand_id;
        $out::wrr{prb_card} = $prb_card;
        $out::wrr{usr_desc} = $usr_desc;
	$out::wrr{exc_desc} = $exc_desc;
	print OUTPUT &out::pack_WRR(\%out::wrr) ;
}

return 1;
