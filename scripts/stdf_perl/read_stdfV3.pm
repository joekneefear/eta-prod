sub convert_STS(){
	$head_num = "";
	$site_num = "";
	$test_num = "";
	$exec_cnt = "";
	$fail_cnt = "";
	$alrm_cnt = "";
	$opt_flag = "";
	$pad_byte = "";
	$test_min = "";
	$test_max = "";
	$tst_mean = "";
	$tst_sdev = "";
	$tst_sums = "";
	$tst_sqrs = "";
	$test_nam = "";
	$seq_name = "";
	$test_lbl = "";
	
	$size = "";
	$tot_size = "";
	$temp_in = "";
	
	read EP, $temp_in, $rec_len;
	
	$in = substr($temp_in, 0, 1);
	$head_num = unpack("C", $in);
	
	$in = substr($temp_in, 1, 1);
	$site_num = unpack("C", $in);
	
	$in = substr($temp_in, 2, 4);
	$test_num = unpack("N", $in);
	
	$in = substr($temp_in, 6, 4);
	$exec_cnt = unpack("N", $in);
	
	$in = substr($temp_in, 10, 4);
	$fail_cnt = unpack("N", $in);
	 
	$in = substr($temp_in, 14, 4);
	$alrm_cnt = unpack("N", $in);
	 
	$in = substr($temp_in, 18, 1);
	$opt_flag = unpack("B8", $in);
 
	$in = substr($temp_in, 19, 1);
	$pad_byte = unpack("B8", $in);
 
	$in = substr($temp_in, 20, 4);
	$test_min = unpack("F", $in);
	
	$in = substr($temp_in, 24, 4);
	$test_max = unpack("F", $in);
	 
	$in = substr($temp_in, 28, 4);
	$tst_mean = unpack("F", $in);
	
	$in = substr($temp_in, 32, 4);
	$tst_sdev = unpack("F", $in);
	 
	$in = substr($temp_in, 36, 4);
	$tst_sums = unpack("F", $in);
	 
	$in = substr($temp_in, 40, 4);
	$tst_sqrs = unpack("F", $in);

	$in = substr($temp_in, 44, 1);
	$size = unpack("C", $in);
	$test_nam = substr($temp_in, 45, $size);
	$tot_size = $tot_size + $size;
	$test_nam =~ s/ +$// ; # remove trailing spaces
	
	$in = substr($temp_in, 45+$tot_size, 1);
	$size = unpack("C", $in);
	$seq_name = substr($temp_in, 46+$tot_size, $size);
	$tot_size = $tot_size + $size;
	$seq_name =~ s/ +$// ; # remove trailing spaces
	
	$in = substr($temp_in, 46+$tot_size, 1);
	$size = unpack("C", $in);
	$test_lbl = substr($temp_in, 47+$tot_size, $size);
	$test_lbl =~ s/ +$// ; # remove trailing spaces
 
	if($test_num == 1)
	{
		$TOTAL_CNT = $exec_cnt;
	}
 
	$STS{$test_num} = 
	{
		HEAD_NUM => $head_num,
		SITE_NUM => $site_num,
		TEST_NUM => $test_num,
		EXEC_CNT => $exec_cnt,
		FAIL_CNT => $fail_cnt,
		ALRM_CNT => $alrm_cnt,
		OPT_FLAG => $opt_flag,
		PAD_BYTE => $pad_byte,
		TEST_MIN => $test_min,
		TEST_MAX => $test_max,
		TST_MEAN => $tst_mean,
		TST_SDEV => $tst_sdev,
		TST_SUMS => $tst_sums,
		TST_SQRS => $tst_sqrs,
		TEST_NAM => $test_nam,
		SEQ_NAME => $seq_name,
		TEST_LBL => test_lbl,
	}; 
}

sub convert_MRR()
{
        $finish_t = "";
        $part_cnt = "";
        $rtst_cnt = "";
        $abrt_cnt = "";
        $good_cnt = "";
        $func_cnt = "";
        $disp_cod = "";
        $usr_desc = "";
        $exc_desc = "";
        $size = 0;
        $tot_size = 0;

        $temp_in = "";

        read EP, $temp_in, $rec_len;
         
        $in = substr($temp_in, 0, 4);
        $finish_t = unpack("N", $in);
        $STRING = "Finish Time: $finish_t\n";

        $in = substr($temp_in, 4, 4);
        $part_cnt= unpack("N", $in);
        $STRING = $STRING."Part Count: $part_cnt\n";

        $in = substr($temp_in, 8, 4);
        $rtst_cnt = unpack("N", $in);
        $STRING = $STRING."Retest Count: $rtst_cnt\n";
         
        $in = substr($temp_in, 12, 4);
        $abrt_cnt= unpack("N", $in);
        $STRING = $STRING."Abort Count: $abrt_cnt\n";

        $in = substr($temp_in, 16, 4);
        $good_cnt = unpack("N", $in);
        $STRING = $STRING."Good Count: $good_cnt\n";
         
        $in = substr($temp_in, 20, 4);
        $func_cnt = unpack("N", $in);
        $STRING = $STRING."Functional Count: $func_cnt\n";

	$in = substr($temp_in, 24, 1);
        $disp_cod = unpack("C", $in);
        $STRING = $STRING."Disp Code: $disp_cod\n";
	if ($disp_cod eq "")
	{
		$disp_cod = "";
	}
	
        $in = substr($temp_in, 25, 1);
        $size = unpack("C", $in);
        $tot_size = $tot_size + $size;
        $usr_desc = substr($temp_in, 26+$tot_size, $size);
        $usr_desc =~ s/ +$// ; # remove trailing spaces
        $STRING = $STRING."USER Description: $usr_desc\n";
	if ($usr_desc eq "")
	{
		$usr_desc = "";
	}
 
        $in = substr($temp_in, 26+$tot_size, 1);
        $size = unpack("C", $in);
        $exc_desc = substr($temp_in, 27+$tot_size, $size);
        $exc_desc =~ s/ +$// ; # remove trailing spaces
        $STRING = $STRING."EXC Description: $exc_desc\n";
	if ($exc_desc eq "")
	{
		$exc_desc = "";
	}

        #print $STRING."\n";

	$MRR{1} =
	{
		FINISH_T => $finish_t,
		PART_CNT => $part_cnt,
		RTST_CNT => $rtst_cnt,
		ABRT_CNT => $abrt_cnt,
		GOOD_CNT => $good_cnt,
		FUNC_CNT => $func_cnt,
		DISP_COD => $disp_cod,
		USR_DESC => $usr_desc,
		EXC_DESC => $exc_desc,
	};	
}


sub convert_SSB()
{
	local $head_num = "";
        local $site_num = "";
        local $sbin_num = "";
        local $sbin_cnt = "";
        local $sbin_nam = "";
        local $STRING   = "";

        read EP, $temp_in, $rec_len;

        $in = substr($temp_in, 0, 1);
        $head_num = unpack("C", $in);
        $STRING = "Head Num: $head_num\n";

        $in = substr($temp_in, 1, 1);
        $site_num= unpack("C", $in);
        $STRING = $STRING."Site Num: $site_num\n";

        $in = substr($temp_in, 2, 2);
        $sbin_num = unpack("n", $in);
        $STRING = $STRING."SBin Num: $sbin_num\n";

        $in = substr($temp_in, 4, 4);
        $sbin_cnt= unpack("N", $in);
        $STRING = $STRING."SBin Count: $sbin_cnt\n";

        $in = substr($temp_in, 8, 1);
        $size = unpack("C", $in);
        $sbin_nam = substr($temp_in, 9, $size);
        $sbin_nam =~ s/ +$// ; # remove trailing spaces
        $STRING = $STRING."SBin Name: $sbin_nam\n";
	if ($sbin_nam eq "")
	{
		$sbin_nam = "";
	}


	$SSB{$sbin_num} =
        {
                HEAD_NUM => $head_num,
                SITE_NUM => $site_num,
                SBIN_NUM => $sbin_num,
                SBIN_CNT => $sbin_cnt,
                SBIN_NAM => $sbin_nam,
        };
}


sub convert_SHB()
{
	local $head_num = "";
	local $site_num = "";
	local $hbin_num = "";
	local $hbin_cnt = "";
	local $hbin_nam = "";
	local $STRING   = "";
  
	read EP, $temp_in, $rec_len;

	$in = substr($temp_in, 0, 1);
	$head_num = unpack("C", $in);
	$STRING = "Head Num: $head_num\n";

	$in = substr($temp_in, 1, 1);
	$site_num= unpack("C", $in);
	$STRING = $STRING."Site Num: $site_num\n";

	$in = substr($temp_in, 2, 2);
	$hbin_num = unpack("n", $in);
	$STRING = $STRING."HBin Num: $hbin_num\n";

	$in = substr($temp_in, 4, 4);
	$hbin_cnt= unpack("N", $in);
	$STRING = $STRING."HBin Count: $hbin_cnt\n";
  
	$in = substr($temp_in, 8, 1);
	$size = unpack("C", $in);
	$hbin_nam = substr($temp_in, 9, $size);
	$hbin_nam =~ s/ +$// ; # remove trailing spaces
	$STRING = $STRING."HBin Name: $hbin_nam\n";
	
	if ($hbin_num ==1)
	{
		$TOTAL_GOOD_CNT = $hbin_cnt;
	}

	$SHB{$hbin_num} = 
	{
		HEAD_NUM => $head_num,
		SITE_NUM => $site_num,
		HBIN_NUM => $hbin_num,
		HBIN_CNT => $hbin_cnt,
		HBIN_NAM => $hbin_nam,
	};
}

sub convert_PTR()
{
        $test_num = "";
        $head_num = "";
        $site_num = "";
        $test_flg = "";
        $parm_flg = "";
        $result   = "";
        $opt_flg  = "";
        $res_scal = "";
        $res_ldig = "";
        $res_rdig = "";
        $desc_flg = "";
        $units    = "";
        $llm_scal = "";
        $hlm_scal = "";
        $llm_ldig = "";
        $llm_rdig = "";
        $hlm_ldig = "";
        $hlm_rdig = "";
        $lo_limit = "";
        $hi_limit = "";
        $test_nam = "";
        $seq_name = "";
        $test_txt = "";

        read EP, $temp_in, $rec_len;

        $in = substr($temp_in, 0, 4);
        $test_num = unpack("N", $in);

        $in = substr($temp_in, 4, 1);
        $head_num = unpack("C", $in);

        $in = substr($temp_in, 5, 1);
        $site_num = unpack("C", $in);

        $in = substr($temp_in, 6, 1);
        $test_flg = unpack("B8", $in);

        $in = substr($temp_in, 7, 1);
        $parm_flg = unpack("B8", $in);

        $in = substr($temp_in, 8, 4);
        $result = char2float($in);

	$in = substr($temp_in, 12, 1);
        $opt_flg = unpack("B8", $in);

        $in = substr($temp_in, 13, 1);
        $res_scal = unpack("c", $in);

        $in = substr($temp_in, 14, 1);
        $res_ldig = unpack("C", $in);

        $in = substr($temp_in, 15, 1);
        $res_rdig = unpack("C", $in);

        $in = substr($temp_in, 16, 1);
        $desc_flg = unpack("B8", $in);

        $in = substr($temp_in, 17, 7);
        $units = unpack("A7", $in);

        $in = substr($temp_in, 24, 1);
        $llm_scal = unpack("c", $in);

        $in = substr($temp_in, 25, 1);
        $hlm_scal = unpack("c", $in);

        $in = substr($temp_in, 26, 1);
        $llm_ldig = unpack("C", $in);

        $in = substr($temp_in, 27, 1);
        $llm_rdig = unpack("C", $in);

        $in = substr($temp_in, 28, 1);
        $hlm_ldig = unpack("C", $in);

        $in = substr($temp_in, 29, 1);
        $hlm_rdig = unpack("C", $in);

        $in = substr($temp_in, 30, 4);
        $lo_limit = unpack("F", $in);

        $in = substr($temp_in, 34, 4);
        $hi_limit = unpack("F", $in);

	$in = substr($temp_in, 38, 1);
        $size = unpack("C", $in);
        $test_nam = substr($temp_in, 39, $size);
        $tot_size = $size;
        $test_nam =~ s/ +$// ; # remove trailing spaces

        $in = substr($temp_in, 39+$tot_size, 1);
        $size = unpack("C", $in);
        $seq_name = substr($temp_in, 39+$tot_size, $size);
        $tot_size = $size;
        $seq_name =~ s/ +$// ; # remove trailing spaces

        $in       = substr($temp_in, 40+$tot_size, 1);
        $size     = unpack("C", $in);
        $test_txt = substr($temp_in, 41+$tot_size, $size);
        $tot_size = $size;
        $test_txt =~ s/ +$// ; # remove trailing spaces

        return ($test_num,
                $head_num,
                $site_num,
                $test_flg,
                $parm_flg,
                $result,
                $opt_flg,
                $res_scal,
                $res_ldig,
                $res_rdig,
                $desc_flg,
                $units,
                $llm_scal,
                $hlm_scal,
                $llm_ldig,
                $llm_rdig,
                $hlm_ldig,
                $hlm_rdig,
                $lo_limit,
                $hi_limit,
                $test_nam,
                $seq_name,
                $test_txt);
}

sub convert_WRR()
{

	read EP, $temp_in, $rec_len;

        $in = substr($temp_in, 0, 4);
        $finish_t = unpack("N", $in);
	$STRING = "Finish Time: $finish_t\n";

        $in = substr($temp_in, 4, 1);
        $head_num = unpack("C", $in);
	$STRING = $STRING."HEAD NUM: $head_num\n";

        $in = substr($temp_in, 5, 1);
        $pad_byte = unpack("B8", $in);
	$STRING = $STRING."PAD_BYTE: $pad_byte\n";

	$in = substr($temp_in, 6, 4);
	$part_cnt = unpack("N", $in);
	$STRING = $STRING."Part Count: $part_cnt\n";

	$in = substr($temp_in, 10, 4);
	$rtst_cnt = unpack("N", $in);
	$STRING = $STRING."Retest Count: $rtst_cnt\n";

	$in = substr($temp_in, 14, 4);
	$abrt_cnt = unpack("N", $in);
	$STRING = $STRING."Abort Count: $abrt_cnt\n";

	$in = substr($temp_in, 18, 4);
	$good_cnt = unpack("N", $in);
	$STRING = $STRING."Good Count: $good_cnt\n";

	$in = substr($temp_in, 22, 4);
	$func_cnt = unpack("N", $in);
	$STRING = $STRING."Functional Count: $func_cnt\n";

        $in = substr($temp_in, 26, 1);
        $size = unpack("C", $in);
        $wafer_id = substr($temp_in, 27, $size);
	$tot_size = $size;
        $wafer_id =~ s/ +$// ; # remove trailing spaces
	$STRING = $STRING."WaferID: $wafer_id\n";

        $in = substr($temp_in, 27+$tot_size, 1);
        $size = unpack("C", $in);
        $hand_id = substr($temp_in, 28+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $hand_id =~ s/ +$// ; # remove trailing spaces
	$STRING = $STRING."Handler ID: $hand_id\n";
	if ($hand_id eq "")
	{
		$hand_id = "";
	}
		
	$in = substr($temp_in, 28+$tot_size, 1);
        $size = unpack("C", $in);
        $prb_card = substr($temp_in, 29+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $prb_card =~ s/ +$// ; # remove trailing spaces
	$STRING = $STRING."Probe Card: $prb_card\n";
	if ($prb_card eq "")
	{
		$prb_card = "";
	}

	$in = substr($temp_in, 29+$tot_size, 1);
        $size = unpack("C", $in);
        $usr_desc = substr($temp_in, 30+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $usr_desc =~ s/ +$// ; # remove trailing spaces
	$STRING = $STRING."User Description: $usr_desc\n";
	if ($usr_desc eq "")
	{
		$usr_desc = "";
	}	
	
	$in = substr($temp_in, 30+$tot_size, 1);
        $size = unpack("C", $in);
        $exc_desc = substr($temp_in, 31+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $exc_desc =~ s/ +$// ; # remove trailing spaces
	$STRING = $STRING."EXC_DESC: $exc_desc\n";
	if ($exc_desc eq "")
	{
		$exc_desc = "";
	}
	
	#print $STRING."\n";

	$WRR{1} = 
	{
		FINISH_T => $finish_t,
		HEAD_NUM => $head_num,
		PAD_BYTE => $pad_byte,
		PART_CNT => $part_cnt,
		RTST_CNT => $rtst_cnt,
		ABRT_CNT => $abrt_cnt,
		GOOD_CNT => $good_cnt,
		FUNC_CNT => $func_cnt,
		WAFER_ID => $wafer_id,
		HAND_ID  => $hand_id,
		PRB_CARD => $prb_card,
		USR_DESC => $usr_desc,
		EXC_DESC => $exc_desc,
	};
}


sub convert_FAR()
{

    read EP, $temp_in, $rec_len;
    $cpu_type = "";
    $stdf_ver = "";

    $in = substr($temp_in, 0, 1);
    $cpu_type = unpack("C", $in);

    $in = substr($temp_in, 1, 1);
    $stdf_ver = unpack("C", $in);
}

sub convert_MIR()
{

        $cpu_type = "";
        $stdf_ver = "";
        $mode_cod = "";
        $stat_num = "";
        $test_cod = "";
        $rtst_cod = "";
        $prot_cod = "";
        $cmod_cod = "";
        $setup_t  = "";
        $start_t  = "";
        $lot_id   = "";
        $part_typ = "";
        $job_nam  = "";
        $oper_nam = "";
        $node_nam = "";
        $tstr_typ = "";
        $exec_typ = "";
        $supr_nam = "";
        $hand_id  = "";
        $sblot_id = "";
        $job_rev  = "";
        $proc_id  = "";
        $prb_card = "";
        $size     = "";
        $temp_in  = "";
        $tot_size = "";
	%mir      = ();

	read EP, $temp_in, $rec_len;

        $in = substr($temp_in, 0, 1);
        $cpu_type = unpack("C", $in);

        $in = substr($temp_in, 1, 1);
        $stdf_ver = unpack("C", $in);
 
        $in = substr($temp_in, 2, 1);
        $mode_cod = unpack("C", $in);
 
        $in = substr($temp_in, 3, 1);
        $stat_num = unpack("C", $in);
 
        $in = substr($temp_in, 4, 3);
        $test_cod = unpack("C3", $in);
 
        $in = substr($temp_in, 7, 1);
        $rtst_cod = unpack("C", $in);

        $in = substr($temp_in, 8, 1);
        $prot_cod = unpack("C", $in);

        $in = substr($temp_in, 9, 1);
        $cmod_cod = unpack("C", $in);
 
        $in = substr($temp_in, 10, 4);
        $setup_t = unpack("N", $in);

        $in = substr($temp_in, 14, 4);
        $start_t= unpack("N", $in);

        $in = substr($temp_in, 18, 1);
        $size = unpack("C", $in);
        $lot_id = substr($temp_in, 19, $size);
        $tot_size = $size;
        $lot_id =~ s/ +$// ; # remove trailing spaces

        $in = substr($temp_in, 19+$tot_size, 1);
        $size = unpack("C", $in);
        $part_typ = substr($temp_in, 20+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $part_typ =~ s/ +$// ; # remove trailing spaces

        $in = substr($temp_in, 20+$tot_size, 1);
        $size = unpack("C", $in);
        $job_nam = substr($temp_in, 21+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $job_nam =~ s/ +$// ; # remove trailing spaces
	$job_nam = "SZ".$job_nam;
	#print "JOB Name: $job_nam\n";

	$in = substr($temp_in, 21+$tot_size, 1);
        $size = unpack("C", $in);
        $oper_nam = substr($temp_in, 22+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $oper_nam =~ s/ +$// ; # remove trailing spaces

        $in = substr($temp_in, 22+$tot_size, 1);
        $size = unpack("C", $in);
        $node_nam = substr($temp_in, 23+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $node_nam =~ s/ +$// ; # remove trailing spaces
 
        $in = substr($temp_in, 23+$tot_size, 1);
        $size = unpack("C", $in);
        $tstr_typ = substr($temp_in, 24+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $tstr_typ =~ s/ +$// ; # remove trailing spaces
	$tstr_typ = "SZ";
	#print "Tester Type: $tstr_typ\n";

        $in = substr($temp_in, 24+$tot_size, 1);
        $size = unpack("C", $in);
        $exec_typ = substr($temp_in, 25+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $exec_typ =~ s/ +$// ; # remove trailing spaces

        $in = substr($temp_in, 25+$tot_size, 1);
        $size = unpack("C", $in);
        $supr_nam = substr($temp_in, 26+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $supr_nam =~ s/ +$// ; # remove trailing spaces

        $in = substr($temp_in, 26+$tot_size, 1);
        $size = unpack("C", $in);
        $hand_id = substr($temp_in, 27+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $hand_id =~ s/ +$// ; # remove trailing spaces

        $in = substr($temp_in, 27+$tot_size, 1);
        $size = unpack("C", $in);
        $sblot_id = substr($temp_in, 28+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $sblot_id =~ s/ +$// ; # remove trailing spaces

        $in = substr($temp_in, 28+$tot_size, 1);
        $size = unpack("C", $in);
        $job_rev = substr($temp_in, 29+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $job_rev =~ s/ +$// ; # remove trailing spaces

	$in = substr($temp_in, 29+$tot_size, 1);
        $size = unpack("C", $in);
        $proc_id = substr($temp_in, 30+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $proc_id =~ s/ +$// ; # remove trailing spaces

        $in = substr($temp_in, 30+$tot_size, 1);
        $size = unpack("C", $in);
        $prb_card = substr($temp_in, 31+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $prb_card =~ s/ +$// ; # remove trailing spaces
	if ($prb_card eq "")
	{
		$prb_card = "";
	}

        $mir{1} =
        {
                CPU_TYPE => $cpu_type,
                STDF_VER => $stdf_ver,
                MODE_COD => $mode_cod,
                STAT_NUM => $stat_num,
                TEST_COD => $test_cod,
                RTST_COD => $rtst_cod,
                PROT_COD => $prot_cod,
                CMOD_COD => $cmod_cod,
                SETUP_T  => $setup_t,
                START_T  => $start_t,
                LOT_ID   => $lot_id,
                PART_TYP => $part_typ,
                JOB_NAM  => $job_nam,
                OPER_NAM => $oper_nam,
                NODE_NAM => $node_nam,
                TSTR_TYP => $tstr_typ,
                EXEC_TYP => $exec_typ,
                SUPR_NAM => $supr_nam,
                HAND_ID  => $hand_id,
                SBLOT_ID => $sblot_id,
                JOB_REV  => $job_rev,
                PROC_ID  => $proc_id,
                PRB_CARD => $prb_card,
        };

        return %mir;
} 

sub convert_PIR
{

	read EP, $temp_in, $rec_len;

	$in = substr($temp_in, 0, 1);
        $head_num = unpack("C", $in);

	$in = substr($temp_in, 1, 1);
        $site_num = unpack("C", $in);

	$in1 = substr($temp_in, 2, 1);
	$in2 = substr($temp_in, 3, 1);
#ben	$x_coord = unpack("N", $in);
	$x_coord = bit2short($in1, $in2);

	$in1 = substr($temp_in, 4, 1);   
	$in2 = substr($temp_in, 5, 1);   
#ben    $y_coord = unpack("N", $in);
        $y_coord = bit2short($in1, $in2); 

	$y_coord = ($y_coord * -1);

	$in = substr($temp_in, 6, 1);
        $size = unpack("C", $in);
        $part_id = substr($temp_in, 7, $size);
        $part_id =~ s/ +$// ; # remove trailing spaces

	$PIR{$part_id} =
	{
		HEAD_NUM => $head_num,
		SITE_NUM => $site_num,
		X_COORD  => $x_coord,
		Y_COORD  => $y_coord,
		PART_ID  => $part_id,
	};

	return ($part_id);
}

sub convert_WIR()
{
        $head_num = "";
        $pad_byte = "";
        $start_t = "";
        $wafer_id = "";
        $temp_in = "";

        read EP, $temp_in, $rec_len;

        $in = substr($temp_in, 0, 1);
        $head_num = unpack("C", $in);

        $in = substr($temp_in, 1, 1);
        $pad_byte = unpack("B8", $in);

        $in = substr($temp_in, 2, 4);
        $start_t = unpack("N", $in);

        $in = substr($temp_in, 6, 1);
        $size = unpack("C", $in);
        $wafer_id = substr($temp_in, 7, $size);
        $wafer_id =~ s/ +$// ; # remove trailing spaces

        $WIR{1} =
        {
                HEAD_NUM => $head_num,
                PAD_BYTE => $pad_byte,
                START_T  => $start_t,
                WAFER_ID => $wafer_id,
        };

        return ($wafer_id);
}

sub convert_WCR(){

	$wafr_siz = "";
	$die_ht = "";
	$die_wid = "";
	$wf_units = "";
	$wf_flat = "";
	$center_x = "";
	$center_y = "";
	$pos_x = "";
	$pos_y = "";

	read EP, $temp_in, $rec_len;

	$in = substr($temp_in, 0, 4);
	$wafr_siz = unpack("F", $in);

	$in = substr($temp_in, 4, 4);
	$die_ht = unpack("F", $in);

	$in = substr($temp_in, 8, 4);
	$die_wid = unpack("F", $in);

	$in = substr($temp_in, 12, 1);
	$wf_units = unpack("C", $in);

	$in = substr($temp_in, 13, 1);
	$wf_flat = unpack("C", $in);

	$in = substr($temp_in, 14, 2);
	$center_x= unpack("N", $in);

	$in = substr($temp_in, 16, 2);
	$center_y= unpack("N", $in);

	$in = substr($temp_in, 18, 1);
	$pos_x= unpack("c", $in);

	$in = substr($temp_in, 19, 1);
	$pos_y= unpack("c", $in);

	$wcr{1} =
	{
		WAFER_SIZ => $wafr_siz,
		DIE_HT    => $die_ht,
		DIE_WID   => $die_wid,
		WF_UNITS  => $wf_units,
		WF_FLAT   => $wf_flat,
		CENTER_X  => $center_x,
		CENTER_Y  => $center_y,
		POS_X     => $pos_x,
		POS_Y     => $pos_y,
	};

	return %wcr;
}

sub convert_PRR()
{
        $head_num = "";
        $site_num = "";
        $num_test = "";
        $hard_bin = "";
        $soft_bin = "";
        $part_flg = "";
        $pad_byte = "";
        $x_coord= "";
        $y_coord = "";
        $part_id = "";
        $part_txt = "";
        $part_fix = "";

        $size = "";
        $tot_size = "";
        $temp_in = "";

        read EP, $temp_in, $rec_len;

        $in = substr($temp_in, 0, 1);
        $head_num = unpack("C", $in);

        $in = substr($temp_in, 1, 1);
        $site_num = unpack("C", $in);

        $in = substr($temp_in, 2, 2);
        $num_test = unpack("n", $in);

        $in = substr($temp_in, 4, 2);
        $hard_bin = unpack("n", $in);

        $in = substr($temp_in, 6, 2);
        $soft_bin = unpack("n", $in);

        $in = substr($temp_in, 8, 1);
        $part_flg = unpack("B8", $in);

        $in = substr($temp_in, 9, 1);
        $rtst_flg = unpack("B8", $in);

        $in = substr($temp_in, 10, 1);
        $pad_byte = unpack("B8", $in);

        $in1 = substr($temp_in, 11, 1);
        $in2 = substr($temp_in, 12, 1);
        $x_coord = bit2short($in1, $in2);

	$in1 = substr($temp_in, 13, 1);
	$in2 = substr($temp_in, 14, 1);
        $y_coord = bit2short($in1, $in2);
	$y_coord = ($y_coord * -1);

        $in = substr($temp_in, 15+$tot_size, 1);
        $size = unpack("C", $in);
        $part_id = substr($temp_in, 16+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $part_id =~ s/ +$// ; # remove trailing spaces

        $in = substr($temp_in, 16+$tot_size, 1);
        $size = unpack("C", $in);
        $part_txt = substr($temp_in, 17+$tot_size, $size);
        $tot_size = $tot_size + $size;
        $part_txt =~ s/ +$// ; # remove trailing spaces
	if ($part_txt eq "")
	{
		$part_txt = "";
	}

        $in = substr($temp_in, 17+$tot_size, 1);
        $size = unpack("B", $in);
        $in = substr($temp_in, 18+$tot_size, $size);
        $part_fix = unpack("B$size", $in);
        $tot_size = $tot_size + $size;
        $part_fix =~ s/ +$// ; # remove trailing spaces
	if ($part_fix eq "")
	{
		$part_fix = "";
	}
	
	$PRR{$Current_part_id} =
	{
		HEAD_NUM => $head_num,
		SITE_NUM => $site_num,
		NUM_TEST => $num_test,
		HARD_BIN => $hard_bin,
		SOFT_BIN => $soft_bin,
		PART_FLG => $part_flg,
		PAD_BYTE => $pad_byte,
		X_COORD  => $x_coord,
		Y_COORD  => $y_coord,
		PART_ID  => $part_id,
		PART_TXT => $part_txt,
		PART_FIX => $part_fix,
	};
}

sub convert_PDR(){
        $test_num = "";
        $desc_flg = "";
        $opt_flag = "";
        $res_scal = "";
        $units    = "";
        $res_ldig = "";
        $res_rdig = "";
        $llm_scal = "";
        $hlm_scal = "";
        $llm_ldig = "";
        $hlm_scal = "";
        $llm_ldig = "";
        $llm_rdig = "";
        $hlm_ldig = "";
        $hlm_rdig = "";
        $lo_limit = "";
        $hi_limit = "";
        $test_nam = "";
        $seq_name = "";

        $size = 0;
        $tot_size = 0;
        $temp_in = "";

        read EP, $temp_in, $rec_len;

        $in = substr($temp_in, 0, 4);
        $test_num = unpack("N", $in);

        $in = substr($temp_in, 4, 1);
        $desc_flg = unpack("B8", $in);

        $in = substr($temp_in, 5, 1);
        $opt_flag = unpack("B8", $in);

        $in = substr($temp_in, 6, 1);
        $res_scal = unpack("c", $in);

        $in = substr($temp_in, 7, 7);
        $units = unpack("C", $in);

        $in = substr($temp_in, 14, 1);
        $res_ldig = unpack("C", $in);

        $in = substr($temp_in, 15, 1);
        $res_rdig = unpack("C", $in);

        $in = substr($temp_in, 16, 1);
        $llm_scal = unpack("c", $in);

	$in = substr($temp_in, 17, 1);
        $hlm_scal = unpack("c", $in);

        $in = substr($temp_in, 18, 1);
        $llm_ldig = unpack("C", $in);

        $in = substr($temp_in, 19, 1);
        $llm_rdig = unpack("C", $in);

        $in = substr($temp_in, 20, 1);
        $hlm_ldig = unpack("C", $in);

        $in = substr($temp_in, 21, 1);
        $hlm_rdig = unpack("C", $in);

        $in = substr($temp_in, 22, 4);
        $lo_limit = unpack("F", $in);

        $in = substr($temp_in, 26, 4);
        $hi_limit = unpack("F", $in);

        $in = substr($temp_in, 30, 1);
        $size = unpack("C", $in);
        $tot_size = $tot_size + $size;
        $test_nam = substr($temp_in, 31, $size);
        $test_nam =~ s/ +$// ; # remove trailing spaces

        $in = substr($temp_in, 31+$tot_size, 1);
        $size = unpack("C", $in);
        $seq_name = substr($temp_in, 32+$tot_size, $size);
        $seq_name =~ s/ +$// ; # remove trailing spaces

	$PDR{$test_num} =
        {
                TEST_NUM => $test_num,
                DESC_FLG => $desc_flg,
                OPT_FLG  => $opt_flg,
                RES_SCAL => $res_scal,
                UNITS    => $units,
                RES_LDIG => $res_ldig,
                RES_RDIG => $res_rdig,
                LLM_SCAL => $llm_scal,
                HLM_SCAL => $hlm_scal,
                LLM_LDIG => $llm_ldig,
                LLM_RDIG => $llm_rdig,
                HLM_LDIG => $hlm_ldig,
                HLM_RDIG => $hlm_rdig,
                LO_LIMIT => $lo_limit,
                HI_LIMIT => $hi_limit,
                TEST_NAM => $test_nam,
                SEQ_NAME => $seq_name,
        };
}


sub bit2short
{
        my $ret = "";
        my (@b) = @_;
           $b[0]= unpack "B8", $b[0];
           $b[1]= unpack "B8", $b[1];
        $ret  = unpack "s", (pack "B16", $b[1].$b[0]) if $mft_flag==0;
        $ret  = unpack "s", (pack "B16", $b[0].$b[1]) if $mft_flag==1;
        return $ret;
}


sub char2float
{
        my ($IN) = @_;
        @b = unpack "c" x 4, $IN;
        $ret = unpack "f", (pack "cccc", $b[3], $b[2], $b[1], $b[0]) if $mft_flag==0;
        $ret = unpack "f", (pack "cccc", $b[3], $b[2], $b[1], $b[0]) if $mft_flag==1;
        return $ret;
}

return 1;
