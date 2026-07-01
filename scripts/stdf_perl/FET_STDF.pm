# File contains functions used by the FET.pl data convter.
#
# MODIFICATION HISTORY
#
# WHEN      WHO             WHAT
# --------- --------------  ------------------------------------------
# 15-Dec-00 David Fletcher  Created
# 02-Nov-12 Scott Boothby   Increased test_plan length to 35 from 20.
#

sub SumBinCounts
{
	my ($DataHash) = @_;
	my $good_cnt = 0;
	my $part_cnt = 0;
	my @BinSums  = ();
	my $i        = 0;
	my $k        = 0;

	foreach $k (sort by_number keys %{$DataHash})
        {
                if ($k eq "")
                {
                        next;
                }
		my @TempArray = @{$$DataHash{$k}{HARDBINS} };
		for ($i = 0; $i <= 23; $i++)
		{
			$BinSums[$i] = $BinSums[$i] + $TempArray[$i];
			
			$part_cnt = $part_cnt + $TempArray[$i];
		}
	}
	#print "SumBinCounts($good_cnt, $part_cnt, \@BinSums)\n";	
	return ($part_cnt, \@BinSums);
}

sub write_header
{
        my $rec_len = $_[0] ;
        my $rec_typ = $_[1] ;
        my $rec_sub = $_[2] ;

        print OUTPUT pack("S", $rec_len) ; # REC_LEN
        print OUTPUT pack("C", $rec_typ) ; # REC_TYP
        print OUTPUT pack("C", $rec_sub) ; # REC_SUB

        return(0) ;
}

sub write_wmr
{
        my $map_data ;  # Input - Contains only the DIE_BINs.  All other info is derived.
                        # Warning!! local variable may be changed
        my $rec_len ;   # local
        my $die_cnt  ;  # local

        $map_data = $_[0] ;

        $die_cnt = length( $map_data ) ;     # Count the number of die
        while ( $die_cnt > 0 )
        {
                if ( $die_cnt > $stdf_max_wmr_physical_die_bins )
                {
                        #
                        # We have greater than 32k wafer data left to write
                        #
                        $rec_len = $stdf_max_wmr_physical_die_bins + 2 ;
                        &write_header( $rec_len, 105, 200 ) ;
                        print OUTPUT pack("s", $stdf_max_wmr_physical_die_bins ) ;              # die count for record
                        print OUTPUT substr($map_data,0,$stdf_max_wmr_physical_die_bins) ;      # die for record
                        $map_data = substr($map_data,$stdf_max_wmr_physical_die_bins,$die_cnt) ;
                        $die_cnt = $die_cnt - $stdf_max_wmr_physical_die_bins ;
                }
                else
                {
                        #
                        # We have less than 32k wafer data left to write
                        #
                        $rec_len = $die_cnt + 2 ;
                        &write_header( $rec_len, 105, 200 ) ;
                        print OUTPUT pack("s", $die_cnt ) ; # DIE_CNT
                        print OUTPUT $map_data ;            # DIE_BINs
                        $len = length($map_data) ;
                        if ( $die_cnt !=  $len )
                        {
                                print LOG "scr:  wmr_write:  error:  die_count left over = $die_cnt, map data left over len(map_data) = $len\n" ;
                        }
                        $die_cnt = 0 ;
                }
        }
        #
        # Output termining WMR record with 0 die count
        #
        write_header( 2, 105, 200 ) ;
        print OUTPUT pack("s", 0 ) ; # DIE_CNT

        return ( 0 ) ;
}


sub PrintSumBinCounts
{
        my ($LotLevelCountREF) = @_;
        for $k (sort by_number keys %{$LotLevelCountREF} )
        {
                print "BIN: ".$k." ".$$LotLevelCountREF{$k}{Count}."\n";
        }
}

sub PopulateLTR
{
	my ($src_lot) = @_;
	#
	# Write LTR
	#
	%out::ltr = %{$out::init{ltr}};
	$out::ltr{lot_id} = $src_lot;
	print OUTPUT &out::pack_LTR(\%out::ltr) ;

}

sub PopulateMRR
{
        #
        # write MRR
        #
        %out::mrr = %{$out::init{mrr}};
        $out::mrr{finish_t} = $Start_time;
        print OUTPUT &out::pack_MRR(\%out::mrr) ;
        close OUTPUT ;
}

sub UPDateEMIR
{
        local ($td_filename, $WSUM_Count, $WSBR_Count) = @_;
        #
        # Update EMIR record with wafer summation stats.
        #
        $out::emir{setup_t}  = $Start_time;
        $out::emir{wsum_cnt} = $WSUM_Count;
        $out::emir{whwb_cnt} = $WSBR_Count;
        $out::emir{start_t}  = $Start_time;
        &out::update_EMIR(\%out::emir, $td_filename) ;
}

sub PopulateWHBR
{
	my ($HardBinRef) = @_;
        my $WHBR_CNT     = 0;
	my $WRRGOOD_Cnt  = 0;
	my $WRRPART_Cnt  = 0;


	if($#good_bins_prn < 0)
	{
		die "ERROR: There are no good HBins specified, stopping converter\n";
	}

        for ($i = 0; $i <= 23; $i++)
        {
                %out::whbr = %{$out::init{whbr}};
                $out::whbr{hbin_num} = $i+1;

                if (@{$HardBinRef}[$i] eq "")
                {
                        $out::whbr{hbin_cnt} = 0;
                }
                else
                {
			

			if (defined($good_bins_prn[$i]) && $good_bins_prn[$i] ne "")
                        {
                                $WRRGOOD_Cnt = $WRRGOOD_Cnt + @{$HardBinRef}[$i - 1];
                        }
	
       	                $out::whbr{hbin_cnt} = @{$HardBinRef}[$i];
                }
                $out::whbr{hbin_nam} = "";
                print OUTPUT &out::pack_WHBR(\%out::whbr);
                $WHBR_CNT++;
        }

        return ($WRRGOOD_Cnt, $WHBR_CNT);
}

sub PopulateWSBR
{
        my ($SoftBinRef) = @_;
        my $WSBR_CNT     = 0;
	my $WRRGOOD_Cnt  = 0;
        my $WRRPART_Cnt  = 0;

	for ($i = 0; $i <= 23; $i++)
        {
		%out::wsbr = %{$out::init{wsbr}};
                $out::wsbr{sbin_num} = $i+1;

		if (@{$SoftBinRef}[$i] eq "")
		{
			$out::wsbr{sbin_cnt} = 0;
		}
		else
		{
                        $WRRPART_Cnt = $WRRPART_Cnt + @{$SoftBinRef}[$i];

			$out::wsbr{sbin_cnt} = @{$SoftBinRef}[$i];
		}
		$out::wsbr{sbin_nam} = "";
                print OUTPUT &out::pack_WSBR(\%out::wsbr);
		$WSBR_CNT++;
	}
	return ($WRRPART_Cnt, $WSBR_CNT);
}

sub PopulateHBR
{
        #
        # Lot Level
        #
	my ($BinArrayRef, $GoodBinsRef) = @_;
        my $HBR_CNT=0;

        for ($i = 0; $i <= 23; $i++)
        {
                %out::hbr = %{$out::init{hbr}};
                $out::hbr{hbin_num} = ($i+1);
                if ($$BinArrayRef[$i] eq "")
                {
                        $out::hbr{hbin_cnt} = 0;
                }
                else
                {
                        $out::hbr{hbin_cnt} = $$BinArrayRef[$i];
                }
                $out::hbr{hbin_nam} = "";
                print OUTPUT &out::pack_HBR(\%out::hbr);
                $HBR_CNT++;
        }
        return ($HBR_CNT);
}


sub PopulateSBR
{
	#
	# Lot Level
	#
	my ($BinArrayRef) = @_;
        my $SBR_CNT=0;

        for ($i = 0; $i <= 23; $i++)
        {
                %out::sbr = %{$out::init{sbr}};
                $out::sbr{sbin_num} = ($i+1);
                if ($$BinArrayRef[$i] eq "")
                {
                        $out::sbr{sbin_cnt} = 0;
                }
		else
		{
                       	$out::sbr{sbin_cnt} = $$BinArrayRef[$i];
		}
               	$out::sbr{sbin_nam} = "";
               	print OUTPUT &out::pack_SBR(\%out::sbr);
               	$SBR_CNT++;
        }
        return $SBR_CNT;
}

sub Init
{
	local ($Type, $InputFileName, $WaferID) = @_;
        ############################
        # Create Output file

        $dir_ix = rindex($InputFileName, "/") + 1;
        if ($dir_ix >= 0)
                {
                $InputFileLen  = length($InputFileLen);
                $InputFileName = substr($InputFileName, $dir_ix);
                }

	($Junk, $DateTime_And_Ext) = split(/\_/, $InputFileName, 2);
	($DateTime, $Ext) = split(/\./, $DateTime_And_Ext); 
	$DateTime = time;

        #$FileName0 = "$ENV{ENV_CONV_GOOD}/${cLOT}_${WaferID}_"."${Type}_${DateTime}_STDF";
        #$FileName0 = "${cLOT}_"."${file}.TD";
	$FileName0 = "${file}.TD";


        ############################
        # Open the file.
        open (OUTPUT, ">$FileName0");

        return ($FileName0);
}

sub PopulateEMIR
{
        ############################
        # Write EMIR header record
        %out::emir = %{$out::init{emir}};

        $out::emir{lot_id}      = $cLOT;
        $out::emir{tstr_typ}    = "FET";
        $out::emir{customer}    = "Cebu FET";
        $out::emir{oper_nam}    = $cOPER;
	$out::emir{stat_num}    = $cPROB if ($cPROB < 10); ### CONDITION IS SET TO PREVENT OVERFLOW (FIELD TYPE = U1)
	$out::emir{node_nam}    = "";
        $out::emir{hand_id}     = $cPROB; 
        $out::emir{spec_nam}    = substr($TestProgName, 0, 35);
        $out::emir{job_nam}     = $TestProgName; 
        $out::emir{job_rev}     = 0;
	$out::emir{device}      = $TestProgName;
	$out::emir{part_typ}    = $TestProgName;
        $out::emir{spec_rev}    = 0;
        $out::emir{mode_cod}    = "P";
        print OUTPUT &out::pack_EMIR(\%out::emir);
}

sub PopulateEWCR
{
        local ($RowCount, $ColCount) = @_;
        ########################
        # Write the EWCR record
        local $WaferSize = 10.0;
	if ($RowCount eq "" || $RowCount == 0)
	{
		$RowCount = 1;
	}
	if ($ColCount eq "" || $ColCount == 0)
	{
		$ColCount = 1;
	}
        %out::ewcr = %{$out::init{ewcr}};
        $out::ewcr{wafr_sz} = $WaferSize;
        $out::ewcr{die_ht}  = $WaferSize/$RowCount;
        $out::ewcr{die_wid} = $WaferSize/$ColCount;
        $out::ewcr{wf_units}= 2;
        $out::ewcr{wf_flat} = "B";
        $out::ewcr{row_cnt} = $RowCount;
        $out::ewcr{col_cnt} = $ColCount;
        $out::ewcr{refpt1_x}= 0;
        $out::ewcr{refpt1_y}= 0;
        $out::ewcr{def_unit}= "";
        print OUTPUT &out::pack_EWCR(\%out::ewcr);
}

sub PopulateGDR
{
        ######################
        # Write the gdr
        $cmap_name = "";
        $gdr{"num_item"} = 1;
        $gdr{"data_type"} = 10;
        $rec = pack("S", 1 ) .
               pack("C", 10 ) .
               pack("C" ,length($cmap_name) ) .
               $cmap_name ;

        $rec_len = length ( $rec ) ;
        &write_header ( $rec_len, 50, 10 ); #.$rec;
        print OUTPUT $rec ;

}

sub PopulateWIR
{
        local $WaferID = shift;
        #####################
        # Write the wir
        %out::wir = %{$out::init{wir}};
        $out::wir{start_t} =  $Start_time;
        $out::wir{wafer_id} = $WaferID;
        print OUTPUT &out::pack_WIR(\%out::wir);
}

sub Close
{
        close OUTPUT;
}

sub PopulateWRR
{
        local ($ID, $GoodDie, $Tested) = @_;

        %out::wrr = %{$out::init{wrr}};
        ##################################
        # Populate WRR Record
        $out::wrr{finish_t} = $Start_time;
        $out::wrr{rtst_cnt} = 0;
        $out::wrr{abrt_cnt} = 0;
        $out::wrr{func_cnt} = 0;
        $out::wrr{part_cnt} = $Tested;
        $out::wrr{good_cnt} = $GoodDie;
        $out::wrr{wafer_id} = $ID;
        print OUTPUT &out::pack_WRR(\%out::wrr);
}

return (1);
