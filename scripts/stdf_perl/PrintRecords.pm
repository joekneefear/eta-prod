sub PrintSTS
{
	my ($STSHRef) = @_;

	print "########## STS ###############\n";
	foreach $k (keys %$STSHRef)
	{
		print "HEAD_NUM=".$$STSHRef{$k}{HEAD_NUM}."\n";
		print "SITE_NUM=".$$STSHRef{$k}{SITE_NUM}."\n";
		print "TEST_NUM=".$$STSHRef{$k}{TEST_NUM}."\n";
		print "EXEC_CNT=".$$STSHRef{$k}{EXEC_CNT}."\n";
		print "FAIL_CNT=".$$STSHRef{$k}{FAIL_CNT}."\n";
		print "ALRM_CNT=".$$STSHRef{$k}{ALRM_CNT}."\n";
		print "OPT_FLAG=".$$STSHRef{$k}{OPT_FLAG}."\n";
		print "PAD_BYTE=".$$STSHRef{$k}{PAD_BYTE}."\n";
		print "TEST_MIN=".$$STSHRef{$k}{TEST_MIN}."\n";
		print "TEST_MAX=".$$STSHRef{$k}{TEST_MAX}."\n";
		print "TST_MEAN=".$$STSHRef{$k}{TST_MEAN}."\n";
		print "TST_SDEV=".$$STSHRef{$k}{TST_SDEV}."\n";
		print "TST_SUMS=".$$STSHRef{$k}{TST_SUMS}."\n";
		print "TST_SQRS=".$$STSHRef{$k}{TST_SQRS}."\n";
		print "TEST_NAM=".$$STSHRef{$k}{TEST_NAM}."\n";
		print "SEQ_NAME=".$$STSHRef{$k}{SEQ_NAME}."\n";
		print "TEST_LBL=".$$STSHRef{$k}{SEQ_NAME}."\n";

	}
	print "\n";
}

sub PrintMIR
{
	my ($MIR_HR) = @_;

	print "########### MIR ###############\n";
	foreach $k (keys %$MIR_HR)
	{
		print "CPU_TYPE=".$$MIR_HR{$k}{CPU_TYPE}."\n";
                print "STDF_VER=".$$MIR_HR{$k}{STDF_VER}."\n"; 
                print "MODE_COD=".$$MIR_HR{$k}{MODE_COD}."\n";
                print "STAT_NUM=".$$MIR_HR{$k}{STAT_NUM}."\n";
                print "TEST_COD=".$$MIR_HR{$k}{TEST_COD}."\n";
                print "RTST_COD=".$$MIR_HR{$k}{RTST_COD}."\n";
                print "PROT_COD=".$$MIR_HR{$k}{PROT_COD}."\n";
                print "CMOD_COD=".$$MIR_HR{$k}{CMOD_COD}."\n";
                print "SETUP_T=".$$MIR_HR{$k}{SETUP_T}."\n";
                print "START_T=".$$MIR_HR{$k}{START_T}."\n";
                print "LOT_ID=".$$MIR_HR{$k}{LOT_ID}."\n";
                print "PART_TYP=".$$MIR_HR{$k}{PART_TYP}."\n";
                print "JOB_NAM=".$$MIR_HR{$k}{JOB_NAM}."\n";
                print "OPER_NAM=".$$MIR_HR{$k}{OPER_NAM}."\n";
                print "NODE_NAM=".$$MIR_HR{$k}{NODE_NAM}."\n";
                print "TSTR_TYP=".$$MIR_HR{$k}{TSTR_TYP}."\n";
                print "EXEC_TYP=".$$MIR_HR{$k}{EXEC_TYP}."\n";
                print "SUPR_NAM=".$$MIR_HR{$k}{SUPR_NAM}."\n";
                print "HAND_ID=".$$MIR_HR{$k}{HAND_ID}."\n";
                print "SBLOT_ID=".$$MIR_HR{$k}{SBLOT_ID}."\n";
                print "JOB_REV=".$$MIR_HR{$k}{JOB_REV}."\n";
                print "PROC_ID=".$$MIR_HR{$k}{PROC_ID}."\n";
                print "PRB_CARD=".$$MIR_HR{$k}{PRB_CARD}."\n";
	}
	print "\n";
}

sub PrintWCR
{
	my ($WCR_HR) = @_;

	print "########### WCR ###############\n";
	foreach $k (keys %$WCR_HR)
	{
		print "WAFER_SZ=".$$WCR_HR{$k}{WAFER_SIZ}."\n";
        	print "DIE_HT=".$$WCR_HR{$k}{DIE_HT}."\n";
        	print "DIE_WID=".$$WCR_HR{$k}{DIE_WID}."\n";
        	print "WF_UNITS=".$$WCR_HR{$k}{WF_UNITS}."\n";
        	print "WF_FLAT=".$$WCR_HR{$k}{WF_FLAT}."\n";
        	print "CENTER_X=".$$WCR_HR{$k}{CENTER_X}."\n";
        	print "CENTER_Y=".$$WCR_HR{$k}{CENTER_Y}."\n";
        	print "POS_X=".$$WCR_HR{$k}{POS_X}."\n";
        	print "POS_Y=".$$WCR_HR{$k}{POS_Y}."\n";
	}
	print "\n";
}

sub PrintPDR
{
	my ($PDR_HR) = @_;
	foreach $k (sort by_number keys %$PDR_HR)
	{
		print 	"$$PDR_HR{$k}{TEST_NUM}, ".
                      	"$$PDR_HR{$k}{DESC_FLG}, ".
                	"$$PDR_HR{$k}{OPT_FLG}, ".
                	"$$PDR_HR{$k}{RES_SCAL}, ".
                	"$$PDR_HR{$k}{UNITS}, ".
                	"RES_LDIG:$$PDR_HR{$k}{RES_LDIG}, ".
                	"RES_RDIG:$$PDR_HR{$k}{RES_RDIG}, ".
                	"LLM_SCAL:$$PDR_HR{$k}{LLM_SCAL}, ".
                	"HLM_SCAL:$$PDR_HR{$k}{HLM_SCAL}, ".
                	"$$PDR_HR{$k}{LLM_LDIG}, ". 
                	"$$PDR_HR{$k}{LLM_RDIG}, ".
                	"$$PDR_HR{$k}{HLM_LDIG}, ".
                	"$$PDR_HR{$k}{HLM_RDIG}, ".
                	"$$PDR_HR{$k}{LO_LIMIT}, ".
                	"$$PDR_HR{$k}{HI_LIMIT}, ".
                	"$$PDR_HR{$k}{TEST_NAM}, ".
                	"$$PDR_HR{$k}{SEQ_NAME}\n";
	}
}

sub PrintPIR
{
	my ($PIR_HR) = @_;
	foreach $k (keys %$PIR_HR)
	{
		print   "$$PIR_HR{$k}{HEAD_NUM}, ".
			"$$PIR_HR{$k}{SITE_NUM}, ".
			"$$PIR_HR{$k}{X_COORD}, ".
			"$$PIR_HR{$k}{Y_COORD}, ".
			"$$PIR_HR{$k}{PART_ID}\n";	
	}
}

sub by_number
{
        if ($a < $b)
        {
                -1;
        }
        elsif ($a == $b)
        {
                0;
        }
        elsif ($a > $b)
        {
                1;
        }
}
return 1;
