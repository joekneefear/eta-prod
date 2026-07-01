# File contains functions used by the FET.pl data convter.
# David Fletcher, Mar. 29, 2002  207-775-8809

sub WaferMapSTDF
{
	#-------------------------( Create Wafer Map STDF+ File )--------------------------------#
	
	#####################################
	#
	# Wafer Map STDF+ file needs to contain the follwing STDF records:
	#	1. EMIR - (1)
	#	2. EWCR - (1)
	#	3. GDR  - (1)
	# 	4. WIR  - (N), one for each wafer result
	#	5. WMR  - (N), one for each wafer result (MAP)
	#	6. WSBR - (N), one for the summary of each wafer
	#	7. WRR  - (N), one for each wafer result
	#	8. WSBR - (1), Across the board summary of all wafers contained.
	#	9. MRR  - (1)
	#
	#
	#####################################
	# Generate one (1) STDF+ file for all 
	# wafers contained within the data 
	# file.
	#
	
	#
	# Figure out what the max Row and column counts
	# are for the eniter lot.  This information
	# goes into the EWCR record + all wafer will 
	# use these max row and column counts when
	# generateing the map records.
	#
	$LotMAXRows = -1;
	$LotMAXCols = -1;
	foreach $k (keys %WaferBinData)
	{
		#print "Wafer: $WaferBinData{$k}{WaferID}, Row: $WaferBinData{$k}{ROWCount}, Col: $WaferBinData{$k}{COLCount}\n";
		if ($WaferBinData{$k}{ROWCount} > $LotMAXRows)
		{
			$LotMAXRows = $WaferBinData{$k}{ROWCount};
		}
		if ($WaferBinData{$k}{COLCount} > $LotMAXCols)
		{
			$LotMAXCols = $WaferBinData{$k}{COLCount};
		}
	}
	#print "---------------------------------------\n";
	#print "MAXRow: $LotMAXRows, MAXCol: $LotMAXCols\n";
	
	$FileNAME = Init("FET_MAP", $FileName);
	PopulateEMIR();
	PopulateEWCR($LotMAXRows, $LotMAXCols);
	PopulateGDR();
	#
	# Loop through the HoH for creation of one STDF+ data file with all maps within.
	#
	$WSUM_CNT = 0;
	$WSBR_CNT = 0;
	$LotWSBR_CNT = 0;
	%LotLevelWSBRCount=();
	foreach $k (sort by_number keys %WaferBinData)
	{
		if ($k ne "")
		{
			#
			# Populate the WIR Record
			#
			#print "WaferID: $WaferBinData{$k}{WaferID}\n";
			PopulateWIR($WaferBinData{$k}{WaferID});
	
			#
			# Convert the map and write the WMR record
			#print "Wafer Number $WaferBinData{$k}{WaferID}, $WaferBinData{$k}{ROWCount}, $WaferBinData{$k}{COLCount}\n";
			($mapdataref) = ConvertWaferMap(\%{$WaferBinData{$k}{WAFER}}, $LotMAXRows, $LotMAXCols);
	        	write_wmr($$mapdataref);
	
			#
			# populate the wafer level WSBR records
			#        
			$WSBRCount = PopulateWSBR(\%{$WaferBinData{$k}{WAFER}});
	
			#
			# Create the lot level WSBR hash, used for reporting Lot level bin summaries.
			#
			SumBinCounts(\%{$WaferBinData{$k}{WAFER}}, \%LotLevelWSBRCount);
			$LotWSBR_CNT = $LotWSBR_CNT + $WSBRCount;
		
			#
			# Populate the WRR record
			#
	        	PopulateWRR($WaferBinData{$k}{WaferID}, $WaferBinData{$k}{GoodDie}, $WaferBinData{$k}{DIETested});
			$WSUM_CNT++;
		}
	}
	#PrintSumBinCounts(\%LotLevelWSBRCount);
	
	###########################################
	# Populate the lot level sbr record count
	#
	$WSBRCount = PopulateSBR(\%LotLevelWSBRCount);
	$LotWSBR_CNT = $LotWSBR_CNT + $WSBRCount;
	
	##########################################
	# Populate the MRR record.
	#
	PopulateMRR();
	
	###############################
	# Close the output file handle
	#
	Close();
	
	###############################
	# Update the EMIR record with
	# Record count statistics.
	#
	UPDateEMIR($FileNAME, $WSUM_CNT, $LotWSBR_CNT);
	
	##############################
	# Close the input file handle.
	#
	close INPUT;
	
	#PrintCPRHeader();
	#PrintResults();
	#----------------( Done: Create Wafer Map STDF+ File )--------------------#
}

return 1;	
