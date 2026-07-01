#!/usr/bin/perl

###########################################################################
#
# Author:	David Fletcher
# Date:		December 1, 2000
# 
# Fairchild Semiconductor
#
# File Name: FET.pl
#
# Purpose: 	Convert Salt Lake FET test tester data to STDF+
#		 Data types handled:	
#		    - Bin Summaries
#		    - Wafer Maps
#		    - Data Log
#
# Output:
#	One STDF+ Wafer map file.
#	One STDF+ data log output file.
#
# Revision History:
#  David Fletcher 12/01/00 Original.
#  Scott Shumway  3/15/01  Changed the way TestPlan and TestPlan Rev are read in.
#  David Fletcher 01/09/02 Made the creation of the two STDF+ files functions.
#			   Added Software binning data to the datalog output.  (WSBR & SBR)
#			   Fixed various issues with bugs in bin data.
#  Rodney Cyr     03/28/02 Fixed some bugs in the generation of wafermaps involving:
#                            - calculation of number of rows and columns
#                            - initialization of map array
#                            - fixed binning to include bin 0
#  Rodney Cyr     04/23/02 Fixed overflow issue due to num_test not getting reset after
#                          each EPRR record.
#  Scott Shumway  09/11/02 Made change to make sure LOT number is upper case.
#
#  Scott Shumway  07/09/03 Check for a 0 in both the X and Y Coordinate before exiting a record.
#  Scott Shumway  09/17/03 Modified how test program and rev are determined, so that it was not
#                          dependent on a  "-" in the program name.
#  Dan Labrie     09/18/03 Modified Bin Max to 21 bins and added needed $NAMBin (16 - 31)
#  Rodney Cyr     12/31/03 Modified wafermap bins from software to hardware.
#  Scott Shumway  08/19/04 Changed the code to read hr,min,sec from the header. Previously 
#                          the time was set to a default of 00:00:00. Originally our CPR
#                          files didn't contain the time. 
#  Scott Shumway  05/12/05 Don't generate maps for tester correlation runs, by eliminating maps
#                          for results smaller than 4 by 4; 
#  Scott Shumway  07/14/05 Added PART_CNT and GOOD_CNT to the wafer map stdf files.
#  Scott Shumway  05/22/06 Added call to Init1, to change how STDF files were named. 
#                          Files from the same lot coming in together were using the same filename. 
#  Daniel Labrie  06/24/06 Modified converter to output a STDF Map file for each wafer.
#  Scott Shumway  12/21/06 Modified the converter to accept both Bin 1 and Bin 2 as good bins.
#  Tom Dixion     05/25/06 Added conditional to not load data that has not been tested.
#                          (Floating point result is 0, and "last test" flag is set)
#  Scott Shumway  09/17/08 Modifed CLINE in the header read to get an appropriate probe card value.
#  Rommel Kho     06/09/11 Modified to use Init2 to reflect Full LotID. Also, rename raw file to 
#			   reflect Full LotID as well.
#  Ben Rommel Kho 07/29/11 Removed rename feature that will reflect full lotid to raw file. 
#			   Instead, transferred feature to dispatcher.
#  Gilbert Miole  07/27/12 Made MFT compatible and change translation of char2short, char2int, char2float for Linux.
#                          Commented out &CreateDataLogSTDF, only produce wmap files.
#  Scott Boothby  08/01/12 Added PID to output file names to prevent multiple threads from producing files with the same name.
#  Gilbert Miole  08/20/12 Revert to original, &CreateDataLogSTDF and &CreateWaferMapSTDF all in one script.
#  Scott Boothby  08/20/12 Init2 needs file name to not include the path to file.
#  Rodney Cyr     08/31/12 Changed negative exit codes to positive values (neg exit codes are not valid in unix).
#
#


$BLKSize   = 1536;
$DeviceID  = 0;
$WARNING   = 0;
%XYBinData = ();

use Carp 			 			; # error messages - does not work within stdf_use.pl
###############
# set path to executable for libraries
###############
use FindBin 						;
use lib "$FindBin::Bin" 				; # set up path for libraries the same as script
use English 						;
use lib $ENV{'STDF_PERL_LIB'} 				; # look for libraries in this directory
#use EDBUtil						;
use Getopt::Long              				;
use File::Basename					;
require "stdf_use.pl" ;  # libraries that are not generated

#####################
# Load Specifications
#####################
{
package out ;
if ( !eval(&::generate_all('stdfPL.spec')))
  { confess $@ ; }
require 'stdfPL.pl' ;
}

$stdf_max_wmr_physical_die_bins = 32000 		; # set equal to STDF_MAX_WMR_PHYSICAL_DIE_BINS

my $PathToFile    = "";
our $file	  = "";
my $plant         = uc($ENV{ENV_FACILITY});     	#<-- MFT ENV VAR
my $mft_flag      = ($^O=~/linux/i) ? 1 : 0;    	#<-- SET 0=OTHERS; 1=LINUX
my ($dump, $envname, $dump) = split /\_/, uc($ENV{ENV_NAME});           #<-- GET ENV NAME
my $FileNAMES     = "";


######################
# RETRIEVE PARAMETERS
######################
$result = GetOptions ("infile=s"   => \$file,
                      "plant=s"    => \$plant,
                      "env_mod=s"  => \$env_mod);
require $env_mod if $env_mod ne "";               ### LOAD OPTIONAL MODULE



#################
# DISPLAY SYNTAX
#################
if ($file eq "")
{
        print "syntax\n";
        print "\tscript -infile=<datalog file> -plant=<plant(opt)> -env_mod=$ENV{ENV_CONV_SCRIPT}/env_mod.pm(opt)>\n";
        exit 1;
}



#################################
#---------( START MAIN )--------#
#################################
&ReadInput($file);

&CreateWaferMapSTDF();

&CreateDataLogSTDF();

########################
# RETURN CONVERTED FILE
########################
print "$FileNAME" 	        if $mft_flag==0;
print "\ntd=$FileNAME $FileNAMES" if $mft_flag==1;

exit 0;

#################################
#---------( END MAIN )--------- #
#################################



#<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< SUBROUTINES >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

sub ReadInput
{
	my ($infile) = @_;

	open (INPUT, "<$infile");

	############################################
	# Read the top most header of the data file.
	# Only one per file.
	#
	ReadCPRHeader();
	
	#
	# Loop through until the end of the file is found.
	# Upon each loop there will be the following for 
	# each wafer of data contained within the file:
	#   1. Individual Wafer Header Record
	#   2. Wafer Results data including
	#	a. Bin Map Data
	#	b. Data log Data. 
	#
	while (!eof(INPUT))
	{
		$XYBinDataREF = "";
		
		($WaferXYBinDataRef, $DataLogArrayRef, $RowCnt, $ColCnt, $maxX, $minX, $maxY, $minY,
                    $DieTested, $GoodDie) = ReadIndividualWaferHeaderRecord();
		#
		# Create a hash of hashes.
		# The struture of the HoH is to have a data structure containing all of the results 
		# of each wafer and then to have a higher layer of a hash containing
		# the hash by wafer.
		#
		# Basically, read in the data, organizie, and then upon completion, output in STDF+ format.
		#
		#  Wafer 1 -> Bin Data
		#          -> Data Log data
		#  Wafer 2 -> Bin Data
		#	   -> Data Log data
		#  ...
		#
		%XYBins = %{$WaferXYBinDataRef};
		@DLWaferResults = @{$DataLogArrayRef};
		if ($GoodDie eq "")
		{
			$GoodDie = 0;
		}
	
		$WaferBinData{$iWaferNum} =
		{
			WaferID   => $iWaferNum,
			ROWCount  => $RowCnt,
			COLCount  => $ColCnt,
                        MaxXCor   => $maxX,
                        MinXCor   => $minX,
                        MaxYCor   => $maxY,
                        MinYCor   => $minY,
			DIETested => $DieTested,
			GoodDie   => $GoodDie,
			WAFER     => { %XYBins },
			DATALOG   => [ @DLWaferResults ],
		};
		#print "Good Die: $WaferBinData{$iWaferNum}{GoodDie}\n";
		%XYBins=();
		@DLWaferResults=();

		#PrintResults();
	}
	
}


sub CreateWaferMapSTDF
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
	#	6. WHBR - (N), one for the summary of each wafer
	#	7. WRR  - (N), one for each wafer result
	#	8. HBR  - (1), Across the board summary of all wafers contained.
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
	# are for the entire lot.  This information
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
        #
        # If the map is to small don't Generate a STDF Wafer Map file.
        #
        if (($LotMAXRows < 4) and ($LotMAXCols < 4)) {return("to small");}
        #
	### Generate a seperate STDF Wafer Map for each wafer ####
	my $PathToFile = dirname($file);
        if ( $mft_flag != 1 ) { $PathToFile = "."; }
	foreach $kk (sort by_number keys %WaferBinData)
	{
		if ($kk ne "")
		{
			@LotLevelBins = ();
       			$FileNAME   = Init2($PathToFile, $file, $WaferBinData{$kk}{WaferID});
			$FileNAMES .="td=$FileNAME " if $mft_flag==1;	
        		PopulateEMIR();
        		PopulateEWCR($WaferBinData{$kk}{ROWCount}, $WaferBinData{$kk}{COLCount});
        		PopulateGDR();
        		#
        		# Loop through the HoH for creation of one STDF+ data file with all maps within.
        		#
        		$WSUM_CNT = 0;
        		$WHBR_CNT = 0;
        		$MRRPART_Cnt=0;
        		$MRRGOOD_Cnt=0;
        		$LotWHBR_CNT = 0;
        		%LotLevelWHBRCount=();
	

			#
			# Populate the WIR Record
			#
			#print "WaferID: $WaferBinData{$kk}{WaferID}\n";
			PopulateWIR($WaferBinData{$kk}{WaferID});
	
			#
			# Convert the map and write the WMR record
			#print "Wafer Number $WaferBinData{$kk}{WaferID}, $WaferBinData{$kk}{ROWCount}, $WaferBinData{$kk}{COLCount}\n";
			($mapdataref) = ConvertWaferMap(\%{$WaferBinData{$kk}{WAFER}}, 
                                                           $WaferBinData{$kk}{MaxXCor},
                                                           $WaferBinData{$kk}{MinXCor},
                                                           $WaferBinData{$kk}{MaxYCor},
                                                           $WaferBinData{$kk}{MinYCor},
                                                           $WaferBinData{$kk}{ROWCount}, $WaferBinData{$kk}{COLCount});
	        	write_wmr($$mapdataref);
			
			#
			# populate the wafer level WHBR records
			#
			$WHBRCount = PopulateWHBR(\%{$WaferBinData{$kk}{WAFER}}, $BinMax, \@LotLevelBins);
	
			#
			# Create the lot level WHBR hash, used for reporting Lot level bin summaries.
			#
			
			#SumBinCounts(\%{$WaferBinData{$kk}{WAFER}}, \%LotLevelWHBRCount);
			$LotWHBR_CNT = $LotWHBR_CNT + $WHBRCount;
				
			#
			# Populate the WRR record
			#
	        	PopulateWRR($WaferBinData{$kk}{WaferID}, $WaferBinData{$kk}{GoodDie}, $WaferBinData{$kk}{DIETested});
			$WSUM_CNT++;
                        $MRRPART_Cnt += $WaferBinData{$kk}{DIETested};
                        $MRRGOOD_Cnt += $WaferBinData{$kk}{GoodDie};  
		
			###########################################
		        # Populate the lot level HBR record count
        		#
        		$WHBRCount = PopulateHBR(\@LotLevelBins, $BinMax);
        		$LotWHBR_CNT = $LotWHBR_CNT + $WHBRCount;

        		##########################################
        		# Populate the MRR record.
        		#
        		PopulateMRR($MRRGOOD_Cnt,$MRRPART_Cnt);

        		###############################
        		# Close the output file handle
        		#
        		Close();

        		###############################
        		# Update the EMIR record with
        		# Record count statistics.
        		#
        		UPDateEMIR($FileNAME, $WSUM_CNT, $LotWHBR_CNT);


		}
	}
	#PrintSumBinCounts(\%LotLevelWHBRCount);
	
	###########################################
	# Populate the lot level HBR record count
	#
	$WHBRCount = PopulateHBR(\@LotLevelBins, $BinMax);
	$LotWHBR_CNT = $LotWHBR_CNT + $WHBRCount;
	
	##########################################
	# Populate the MRR record.
	#
	PopulateMRR($MRRGOOD_Cnt,$MRRPART_Cnt);
	
	###############################
	# Close the output file handle
	#
	Close();
	
	###############################
	# Update the EMIR record with
	# Record count statistics.
	#
	UPDateEMIR($FileNAME, $WSUM_CNT, $LotWHBR_CNT);
	
	##############################
	# Close the input file handle.
	#
	close INPUT;
	
	#PrintCPRHeader();
	#PrintResults();
	#----------------( Done: Create Wafer Map STDF+ File )--------------------#
}

sub CreateDataLogSTDF
{
	#-------------------( Create One STDF+ file for data log output )------------#
	
	#
	# initialize perl records
	#
	%out::emir = %{$out::init{emir}} ;
	%out::pir  = %{$out::init{pir}} ;
	%out::ptr  = %{$out::init{ptr}} ;
	%out::eprr = %{$out::init{eprr}} ;
	%out::mrr  = %{$out::init{mrr}} ;
	%out::wir  = %{$out::init{wir}} ;
	%out::wrr  = %{$out::init{wrr}} ;
	
	#
	# Open file
	#
	my $PathToFile = dirname($file);
        if ( $mft_flag != 1 ) { $PathToFile = "."; }
	$FileNAME = "";
        my $baseFileName = basename($file);
	$FileNAME = Init2($PathToFile, $baseFileName, "");

	
	#
	# Entire Lot Good & Part Count
	#
	$MRRGOOD_Cnt = 0;
        $MRRPART_Cnt = 0;
	
	#
	# write EMIR header record
	#
	PopulateEMIR();
	
	#
	# Loop through the entire hash of 
	# wafers, extracting the data log data
	# and populating the STDF+ file.
	#
	@LotLevelBins = ();
	$WRRCount  = 0;
	$PRES_CNT  = 0;
	$WRRCount  = 0;
	$EPRRCount = 0;
	$PartCount = 0;
	$PRRCount  = 0;
	$WSBRCount = 0;
	$WSWB_CNT  = 0;
	$SSWB_CNT  = 0;
	$SBRCount  = 0;
	foreach $k (sort by_number keys %WaferBinData)
	{
		if ($k eq "")
		{
			next;
		}
		#
		# Sort the array
		#
		@Array = map {  $_->[0] }
	        sort { $a->[4] <=> $b->[4]  # Site Number
	                        ||
	                $a->[5] <=> $b->[5] } # Test number
	
	        map { [$_, /^(.+)\t(.+)\t(.+)\t(.+)\t(.+)\t(.+)\t(.+)\t(.+)/] } @{ $WaferBinData{$k}{DATALOG} } ;
	
		# 
	        # initialize fields
	        #
	        $out::ptr{test_num} = ${out::init{ptr}{test_num}};
	        $out::pir{part_id}  = ${out::init{pir}{part_id}};
	        $out::ptr{result}   = ${out::init{ptr}{result}};
	        $out::wir{wafer_id} = ${out::init{wir}{wafer_id}};
	        $out::wir{start_t}  = ${out::init{wir}{start_t}};
	
		($out::wir{wafer_id}, $CurX, $CurY, $DeviceID, $out::ptr{test_num}, $out::ptr{result}, $BIN, $Flag) =
	                        split (/\t/, $Array[0], 8);

		#print "\nSTR: $out::wir{wafer_id}, $CurX, $CurY, $DeviceID, $out::ptr{test_num}, $out::ptr{result}, $Flag\n";
	
		#
	        # Write WIR record
	        #
	        $out::wir{start_t} =  $Start_time;
	        print OUTPUT &out::pack_WIR(\%out::wir);
	
		for ($P = 0; $P <= $#Array; $P++)
		{
			#Init Test Numbers
	                $FirstPartID = $LastPartID = $DeviceID;
	
			$out::pir{part_id}  = ${out::init{pir}{part_id}} ;
	                $out::mrr{part_cnt}++ ;  # increment part count
	
			$out::pir{x_coord} = $CurX;
	                $out::pir{y_coord} = $CurY;
	
			##########################################
	                #
	                # Write PIR record
	                #
	                $out::pir{part_id} = $DeviceID;
	                print OUTPUT &out::pack_PIR(\%out::pir) ;
	                #########################################
		
			#
	                # Reset PartID
	                #
	                $FirstPartID = $LastPartID = $DeviceID;
	
			while ( $FirstPartID == $LastPartID )
	                {
				$CurX = "";
				$CurY = "";
				$DeviceID = "";
				$out::ptr{result}   = ${out::init{ptr}{result}} ;
	                        $out::ptr{test_num} = ${out::init{ptr}{test_num}} ;
				
				($out::wir{wafer_id}, $CurX, $CurY, $DeviceID, $out::ptr{test_num}, $out::ptr{result}, $BIN, $Flag) =
	                        	split (/\t/, $Array[$P], 8);

				#print "\tMID: $out::wir{wafer_id}, $CurX, $CurY, $DeviceID, $out::ptr{test_num}, $out::ptr{result},\t$Flag\n";
				if ($out::wir{wafer_id} eq "")
	                        {
	                                print "\nWafer ID: $out::wir{wafer_id}\n"         if $mft_flag==0;
	                                print "WAFER ID CAN NOT BE BLANK: $Array[$P]\n"   if $mft_flag==0;

					print "\ndir=no_wafer_id" if $mft_flag==0;        ### RETURN BAD SUBDIR FOR MFT
                			&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_wafer_id") if $mft_flag==0;
                			exit 100;
	                        }
	
				#
				#
				#
				$out::ptr{test_num} = $out::ptr{test_num};
	                        $out::ptr{test_flg} = "01000000";
			
				$PRES_CNT++;
	
				##########################################
	                        # Write PTR record
	                        #
	                        print OUTPUT &out::pack_PTR(\%out::ptr) ;
	                        ##########################################
				$PartCount++;
	
	                        $LastPartID = $FirstPartID ;
	                        $out::eprr{num_test}++ ;
	                        $out::emir{pres_cnt}++ ;
				$LastBin = $BIN;
				$LastX = $CurX;
				$LastY = $CurY;
				
	                        $P++ ; # Increase array index
				$LastWaferID = $out::wir{wafer_id};
				($out::wir{wafer_id}, $CurX, $CurY, $DeviceID, $out::ptr{test_num}, $out::ptr{result}, $BIN, $Flag) =
	                                split (/\t/, $Array[$P], 8);
				#print "\t\tEND: $out::wir{wafer_id}, $CurX, $CurY, $DeviceID, $out::ptr{test_num}, $out::ptr{result}\n";
				$FirstPartID = $DeviceID;
			}
			$P--;
			############################################
	                # Write EPRR record
	                #
			#$out::eprr{soft_bin} = $LastBin;
			$out::eprr{x_coord}  = $LastX;
			$out::eprr{y_coord}  = $LastY;
	                $out::eprr{part_id}  = $LastPartID ;
			#
			# Set the part flag:
			#	If the $LastBin != 1, this indicatest 
			#       a part falure, therefore set bit 3 to '1'
			#
			#if ($LastBin != 1)
			#{
			#	$out::eprr{part_flg} = "00001000";
			#}
			#else
			#{
			#	$out::eprr{part_flg} = "00000000";
			#}
	                $EPRRCount++;
	                print OUTPUT &out::pack_EPRR(\%out::eprr) ;
	                ############################################
                        $out::eprr{num_test} = 0;  # reset # of tests for next EPRR record
	
		}

		#
		# Write out the WSBR records for the wafer.
		#
		$WSBRCount = PopulateWSBR(\%{$WaferBinData{$k}{WAFER}}, $BinMax, \@LotLevelBins);
		$WSWB_CNT = $WSBRCount + $WSWB_CNT;

		%out::wrr = %{$out::init{wrr}} ;
		##########################################
		# Write WRR record
		#
		$out::wrr{wafer_id} = $LastWaferID;
		$out::wrr{good_cnt} = $WaferBinData{$k}{GoodDie};
		$out::wrr{finish_t} = $Start_time;
		$out::wrr{part_cnt} = $WaferBinData{$k}{DIETested};
		print OUTPUT &out::pack_WRR(\%out::wrr) ;
		##########################################
		$MRRGOOD_Cnt = $WaferBinData{$k}{GoodDie} + $MRRGOOD_Cnt;
		$MRRPART_Cnt = $WaferBinData{$k}{DIETested} + $MRRPART_Cnt;
		$PartCount = 0;
		$PRRCount++;
	
	} # END loop through hash

	#
	# Write out the SBR records
	#
	$SBRCount = PopulateSBR(\@LotLevelBins, $BinMax);
        $SSWB_CNT = $SSWB_CNT + $SBRCount;
	# HERE
	
	#
	# write MRR
	#
	$out::mrr{finish_t} = $Start_time;
	$out::mrr{disp_cod} = "L";
	$out::mrr{good_cnt} = $MRRGOOD_Cnt;
	$out::mrr{part_cnt} = $MRRPART_Cnt;
	print OUTPUT &out::pack_MRR(\%out::mrr) ;
	close OUTPUT ;
	
	#
	# Update EMIR record with wafer summation stats.
	#
	$out::emir{setup_t}  = $Start_time;
	$out::emir{ssum_cnt} = 1;
	$out::emir{wswb_cnt} = $WSWB_CNT;
	$out::emir{sswb_cnt} = $SSWB_CNT;
	$out::emir{psum_cnt} = $EPRRCount;
	$out::emir{wsum_cnt} = $WRRCount;
	$out::emir{pres_cnt} = $PRES_CNT; #ptr record count
	$out::emir{start_t}  = $Start_time;
	
	#
	# update EMIR with count information
	#
	&out::update_EMIR(\%out::emir, $FileNAME) ;
	close (OUTPUT);
	 
	#-------------------( END: Create One STDF+ file for data log )------------#
}	

sub ConvertWaferMap
{
	local ($XYBinDataREF, $maxX, $minX, $maxY, $minY, $RowCount, $ColCount) = @_;

	for ($i = 0; $i <=9; $i++)
        {
                $NAMBin{$i} = { BIN => $i };
        }
        $NAMBin{10} = { BIN => 'A' };
        $NAMBin{11} = { BIN => 'B' };
        $NAMBin{12} = { BIN => 'C' };
        $NAMBin{13} = { BIN => 'D' };
        $NAMBin{14} = { BIN => 'E' };
        $NAMBin{15} = { BIN => 'F' };
        $NAMBin{16} = { BIN => 'G' };
        $NAMBin{17} = { BIN => 'H' };
        $NAMBin{18} = { BIN => 'I' };
        $NAMBin{19} = { BIN => 'J' };
        $NAMBin{20} = { BIN => 'K' };
        $NAMBin{21} = { BIN => 'L' };
        $NAMBin{22} = { BIN => 'M' };
        $NAMBin{23} = { BIN => 'N' };
        $NAMBin{24} = { BIN => 'O' };
        $NAMBin{25} = { BIN => 'P' };
        $NAMBin{26} = { BIN => 'Q' };   
        $NAMBin{27} = { BIN => 'R' };  
        $NAMBin{28} = { BIN => 'S' };  
        $NAMBin{29} = { BIN => 'T' };  
        $NAMBin{30} = { BIN => 'U' };
        $NAMBin{31} = { BIN => 'V' };

	#
	# Initialize the map
	#
	@Map=();

        if ($minX < 0)
	{
		$rowMax = $RowCount + (-1)*$minX;
	}
	else
	{
		$rowMax = $RowCount - $minX;
	}

	if ($minY < 0)
	{
		$colMax = $ColCount + (-1)*$minY;
	}
	else
	{
		$colMax = $ColCount - $minY;
	}

		

	#
        # Initialize the array with all '.'
        #
        for ($a = $minX; $a <= $RowCount + $minX - 1; $a++)
        {
                for ($b = $minY; $b <= $ColCount + $minY - 1; $b++)
                {
                        $Map[$a][$b] = ".";
                }
        }

	#
	# Merge in BINs
	#
	foreach $k (keys %{$XYBinDataREF} )
	{
	#	print "$$XYBinDataREF{$k}{XCor}, $$XYBinDataREF{$k}{YCor}, $NAMBin{ $$XYBinDataREF{$k}{BIN} }{BIN}\n";
		$Map[$$XYBinDataREF{$k}{XCor}][$$XYBinDataREF{$k}{YCor}] = $NAMBin{ $$XYBinDataREF{$k}{BIN} }{BIN};
	}

	#
	# Populate the map
	#
	$MapData="";
	
	for ($a = $minX; $a <= $RowCount + $minX - 1; $a++)
        {
                for ($b = $ColCount + $minY - 1; $b >= $minY; $b--)
                {
	#		print $Map[$a][$b];
                        $MapData = $MapData.$Map[$a][$b];
                }
	#	print "\n";
        }
        #print "\n";

	$map_in_1_9   = '[0-9]' ;
        $map_out_1_9   = '[\x00-\x09]' ; #  0 - 9
        $map_in_A_V   = '[A-V]' ;
        $map_out_A_V   = '[\x0a-\x1f]' ; #  10 - 31
        $map_in_ghost = '[\.]'  ;
        $map_out_ghost = '[\xfd]' ;      #  253
        $map_in_ghost1 = '[\*]';
        $map_out_ghost1 = '[\xff]' ;     #  255

        $map_input = $map_in_ghost.$map_in_ghost1.$map_in_1_9.$map_in_A_V;
        $map_output= $map_out_ghost.$map_out_ghost1.$map_out_1_9.$map_out_A_V;

        $tr_cmd = "\$MapData =~ tr /$map_input/$map_output/" ;

	#
        # execute #tr command
        #
        eval $tr_cmd ; # Convert the bins from NAM format to Numeric
	return (\$MapData);
}

sub PrintResults
{

	#  "$iWaferNum\t".
        #  "$ResultsData{$KEY}{XCor}\t".
        #  "$ResultsData{$KEY}{YCor}\t".
        #  "$ResultsData{$KEY}{DeviceID}\t".
        #  "$KEY\t".
        #  "$ResultsData{$KEY}{Result}";

	@Array = map {  $_->[0] }
         sort { $a->[1] <=> $b->[1]   # Wafer number 
                	||
                $a->[5] <=> $b->[5]   # Site Number 
			||
		$a->[4] <=> $b->[4]}  # Device ID (Test NUM) 

        map { [$_, /^(.+)\t(.+)\t(.+)\t(.+)\t(.+)\t(.+)/] } @Outputarray ;
	
	###################
	# Remove Old Array
	#@Outputarray=();

	PrintCPRHeader();
	print "\n\nWaferID XCOR    YCOR   DeviceID SiteNum     Result\n";
	for ($i = 0; $i <= $#Array; $i++)
	{
		print $Array[$i]."\n";
	}
}

sub PrintPos
{
	print "Block: tell(INPUT): ".tell(INPUT)." mod 1536 = ".(tell(INPUT)% $BLKSize)."\n";
}

sub ReadIndividualWaferHeaderRecord
{
		$iDieNumber = 0;
		$UTOT       = "";
		$CSNX       = "";
		$SPARE1     = "";
		@uFAIL      = "";
		@UTFAIL     = ();
		@iUSORT     = ();
		@iUBIN      = ();
		$C10FN      = "";
		read INPUT, $in, 4;
		@aWaferNum=();
		@aWaferNum = unpack "a" x 4, $in;

		for ($i = 0; $i <= 3; $i++)
		{
			$aWaferNum[$i] =~ s/[^0-9]//;
		}
		if ($aWaferNum[0] ne "")
		{
			$iWaferNum = $aWaferNum[0].$aWaferNum[1].$aWaferNum[2].$aWaferNum[3]; 
		}
		else
		{
			$iWaferNum = $aWaferNum[1].$aWaferNum[2].$aWaferNum[3];
		}
	
		
		for ($ind = 0; $ind < 250; $ind++)
		{
			read INPUT, $in, 2;
			$uFAIL[$ind] = char2short($in);
		}

		for ($ind = 0; $ind < 250; $ind++)
                {
			read INPUT, $in, 2;
			$UTFAIL[$ind] = char2short($in);
		}

		for ($ind = 0; $ind < 25; $ind++)
		{
			read INPUT, $in, 4;
			$iUBEST[$ind] = char2int($in);
		}

		for ($ind = 0; $ind < 25; $ind++)
                {
                        read INPUT, $in, 4;
                        $iUSORT[$ind] = char2int($in);
		}
		
		for ($ind = 0; $ind < 25; $ind++)
                {
                        read INPUT, $in, 4;
                        $iUBIN[$ind] = char2int($in);
		}
		read INPUT, $in, 4;
		$UTOT = char2int($in);
		
		read INPUT, $in, 2;
		$C10FN = char2short($in);
		#print "C10FN = $C10FN\n";
		
		read INPUT, $in, 2;
		$CSNX = char2short($in);
		#print "CSNX = $CSNX\n";
		
		read INPUT, $in, 224;
		$SPARE1 = unpack "c224", $in;
		$BinDataRef = ();
		($BinDataRef, $DataLogArrayRef, $RowCnt, $ColCnt, $maxX, $minX, $maxY, $minY,
                     $DieTested, $GoodDie) = WaferDataRecord($iWaferNum);

		#
		# Return the Reference to the hash containing the 
		# Bin results, including the X and Y Coordinates.
		#
		return ($BinDataRef, $DataLogArrayRef, $RowCnt, $ColCnt, $maxX, $minX, $maxY, $minY,
                           $DieTested, $GoodDie);
}

sub WaferDataRecord
{
		$DeviceID = 0;
		$FLAG = "";
		$emptywafer = 0;
		local $XYBinDataKey = 0;
		%XYBinData=();
		@Outputarray=();
		%ResultsData=();
		local $minX = $minY = 5000;
        	local $maxX = $maxY = -5000;
		local $DieTestedCnt = 0;
		local $GoodDieCnt   = 0;
		local $iDieCount = 0;
		$BinMax = 32;

		for ($k = 0; $k < $DARCNT; $k++)
		{
			for ($j = 0; $j < $SNNUM; $j++)
			{
				$DeviceID++;
				if (!(--$iDieCount))
				{
					next;
				}
				read INPUT, $in, 1;
				$XCOR = unpack "C", $in;
				read INPUT, $in, 1;
                                $YCOR = unpack "C", $in;
				#print "X: $XCOR - Y: $YCOR\n";
                                if (($XCOR == 0) && ($YCOR == 0))
				{
					if ($iDieNumber == 0)
					{
						$emptywafer = 1;
					}
					next;
				}

				#
				# Find out what the min and max x and y values are.
				#
				if ($XCOR > $maxX)
                		{
                        		$maxX = $XCOR;
                		}
               			if ($XCOR < $minX)
                		{
                        		$minX = $XCOR;
                		}
                		if ($YCOR > $maxY)
                		{
                        		$maxY = $YCOR;
                		}
                		if ($YCOR < $minY)
                		{
                        		$minY = $YCOR;
                		}	
	
                                #print "$maxX  $minX / $maxY $minY\n";

				read INPUT, $in, 1;
                                $BINRESULT = unpack "c", $in;
                                #print "Bin Result: ".($BINRESULT & 127)."\n";

				read INPUT, $in, 1;
				$BINResultFlag = unpack "b8", $in;
				#print "Bin Result Flag: $BINResultFlag\n";

				# Bit 1 Cover on Fail=1 
                                # Bit 2 Test Done=1 
                                # Bit 3 Test Fail=1 
                                # Bit 4 Test Over=1 
                                # Bit 5 Data Logged=1
                                # Bit 6 test Less=1
                                # Bit 7 Result Converted to Floating point=1

				read INPUT, $in, 4;
				$SEGRSL = char2float($in); #First result
				$TestNum = 1;
				$XYBinDataKey++;
				$XYBinData{$XYBinDataKey} = 
				{
					XCor     => $XCOR,
					YCor     => $YCOR,
					BIN      => ($BINRESULT & 127),
				};
				if ($XYBinData{$XYBinDataKey}{BIN} >= $BinMax)
				{
					#print "MAX: $XYBinData{$XYBinDataKey}{BIN}\n";
					$BinMax = $XYBinData{$XYBinDataKey}{BIN};
				}
				$DieTestedCnt++;
				if (($XYBinData{$XYBinDataKey}{BIN} eq "1") or ($XYBinData{$XYBinDataKey}{BIN} eq "2"))
				{
                			$GoodDieCnt++;
				}
				
				$ResultsData{$TestNum} =
				{
					Result   => $SEGRSL,
					Flag     => $BINResultFlag,
					XCor     => $XCOR,
					YCor     => $YCOR,
					DeviceID => $DeviceID,
					BIN      => $XYBinData{$XYBinDataKey}{BIN},
				};
				
				$cntSNSIZE = $SNSIZE-8;
				for ($ii=0; $ii < $cntSNSIZE; $ii = $ii + 5)
				{
					#print "'for loop' position $ii - cntSNSIZE: $cntSNSIZE - Wafer #: $iWaferNum\t";
					$TestNum++;	
					read INPUT, $in, 1;
					$FLAG = unpack("c", $in);
					
					read INPUT, $in, 4;
					$RESULT = char2float($in);
					if($FLAG & 128)
					{
					  #######################################################
					  # Do something with the $RESULT.  Must store in a Hash.
					  #######################################################
					   $ResultsData{$TestNum} =
                                           {
                                               Result   => $RESULT,
                                               Flag     => $BINResultFlag,
                                               XCor     => $XCOR,
                                               YCor     => $YCOR,
					       DeviceID => $DeviceID,
					       BIN      => $XYBinData{$XYBinDataKey}{BIN},
                                           };
					}
				}

				#####################################
				# Populate the array to hold results
				foreach $KEY (sort keys %ResultsData)
				{
					$Data = "$iWaferNum\t".
						"$ResultsData{$KEY}{XCor}\t".
						"$ResultsData{$KEY}{YCor}\t".
						"$ResultsData{$KEY}{DeviceID}\t".
						"$KEY\t".
						"$ResultsData{$KEY}{Result}\t".
						"$ResultsData{$KEY}{BIN}\t".
						"$ResultsData{$KEY}{Flag}";
					#print $Data."\n";
							
					push (@Outputarray,  $Data);
				}
 
				%ResultsData=();
			}

			#
			# Check to see if the file is corrupt and the END of file is found.
			#  Don't just loop on a file that does not contain an eof
			#  Cris Jan && David Fletcher 1/21/2002
			#
			for($Ret=1; ((tell(INPUT) % $BLKSize) != 0) && $Ret!=0; $Ret = read(INPUT, $in, 1))
			{}
			#while ((tell(INPUT) % $BLKSize) != 0)
                        #{
                        #        read INPUT, $in, 1;
                        #}
		}
	        if ($minX < 0)  
		{
       		       $RowCount = $maxX + $minX + 1;
		}
        	else 
		{
              	       $RowCount = $maxX - $minX + 1;
		}

	        if ($minY < 0)  
		{
	               $ColCount = $maxY + $minY + 1;
		}
        	else  
		{
              	       $ColCount = $maxY - $minY + 1;
		}
        
	return (\%XYBinData, \@Outputarray, $RowCount, $ColCount,  
                  $maxX, $minX, $maxY, $minY, $DieTestedCnt, $GoodDieCnt);
}

sub check
{
	my ($input, $len) = @_;

	$out = unpack "a" x $len, $input;
	print "\tASCII String Null Padded: $out\n";
	$out = unpack "A" x $len, $input;
	print "\tASCII String space padded: $out\n";

	$out = unpack "i" x $len, $input;
	print "\tSigned Integer: $out\n";
	$out = unpack "I" x $len, $input;
	print "\tUnsigned Integer: $out\n";

	$out = unpack "c" x $len, $input;
	print "\tSigned Char: $out\n";
	$out = unpack "C" x $len, $input;
	print "\tUnsigned Char: $out\n";

	print "\n";
}

sub PrintCPRHeader
{
	printf("cProbe: %s\n", $cProbe);
	printf "cNum: %s\n", $cNum;
	print "Number of wafers: $NUMWAF\n";
	print "cCNAME: $cCNAME\n";
	print "cCDATE: $cCDATE\n";
	print "cCLINE: $cCLINE\n";
	print "cOPER: $cOPER\n";
	print "cLOT: $cLOT\n";
	print "cPROBE: $cPROB\n";
	print "SNNUM: Number of die / record: $SNNUM\n";
	print "SNSIZE: Number of Bytes / Die: $SNSIZE\n";
	print "NUMDIE: Number of Die / wafer: $NUMDIE\n";	
	print "Start Segment: $F1SSEG\n";
	print "End Segment: $F1ESEG\n";
	print "SPARE: $cSPARE\n";
	print "DARCNT: Data Record Count / Wafer: $DARCNT\n";		
	print "Test Program name = $RUNNAME\n";
	print "TESTNAME = $TESTNAME\n";
	print "CWNAM = $CWNAM\n";
}

sub ReadCPRHeader
{
	# Header Length is 1536 bytes

	$cProbe = "";
	$cNum   = "";
	$NUMWAF = "";
	$cCNAME = "";
	$cCDATE = "";
	$SecondProbed = "";
	$MinuteProbed = "";
	$HourProbed   = "";
	$MonthProbed  = "";
	$DayProbed    = "";
	$YearProbed   = "";
	$Start_time   = 0;
	$cCLINE       = "";
	$cOPER        = "";
	$cLOT         = "";
	$cPROB        = "";
	$SNNUM	      = "";
        $SNSIZE       = "";
        $NUMDIE       = "";
        $F1SSEG       = "";
        $F1ESEG       = "";
        $cSPARE       = "";
        $DARCNT       = "";	
	@TestNumbers  = ();
	@FunctionNumbers = ();
	@WFSEG        = ();
	$RUNNAME      = "";
	$TESTNAME     = "";
	$TestProgName = "";
	$TestProgNameRev = "";
	$SPARE0       = "";
	$iUBEST       = "";
	@anCWCT       = ();
	@WFTNUM       = ();
	

	read INPUT, $rProbe, 1;
	$cProbe = unpack "a", $rProbe;

	read INPUT, $rNum, 1;
	$cNum = unpack "a", $rNum;

	read INPUT, $in, 2;
	$NUMWAF = unpack "c" x 2, $in;

	read INPUT, $in, 40;
	$cCNAME = unpack "A40", $in;

	read INPUT, $in, 40;
	$cCDATE = unpack "a40", $in;
	$cCDATE =~ s/^[\n]//;

	$SecondProbed = "00";
	$MinuteProbed = "00";
	$HourProbed   = "00";

	if (index($cCDATE, "\/") >= 1)
       	{  
          if (index($cCDATE, "\.") >= 1)	
       	  {
	        ($MonthProbed, $DayProbed, $YearProbed,$HourProbed,$MinuteProbed,$SecondProbed) = split(/[\/\.]/, $cCDATE);
          }
          else
          {
                ($MonthProbed, $DayProbed, $YearProbed) = split(/\//, $cCDATE);
          } 
	}
	elsif (index($cCDATE, "-") >= 1)
	{
	    if (index($cCDATE, "\.") >= 1) 
            { 
                ($MonthProbed, $DayProbed, $YearProbed,$HourProbed,$MinuteProbed,$SecondProbed) = split(/[-\.]/, $cCDATE);
            }
            else
            {
                ($MonthProbed, $DayProbed, $YearProbed) = split(/-/, $cCDATE);
            } 
	}
	if ($YearProbed eq 0)
        {
                $YearProbed = "2000";
        }

	$MonthProbed =~ s/^[^1-9]//;
	#print "$SecondProbed, $MinuteProbed, $HourProbed, $DayProbed, ($MonthProbed-1), $YearProbed\n";
	
	@trash = (split /\./, $MonthProbed);

	
	if ($MonthProbed < 1 || $MonthProbed > 12 || $MonthProbed eq "" || $#trash > 0)
	{
		print "ERROR: Month not in rage of 1..12, using current datetime\n";
                @current_time = localtime(time);
		$Start_time = timegm(@current_time);	
	} 

	elsif($DayProbed < 1 || $DayProbed > 31)
	{
		print "ERROR: Day not in rage of 1..31, using current datetime\n";
                @current_time = localtime(time);
                $Start_time = timegm(@current_time);  
	}		
	
	else
	{	
		$Start_time = timegm($SecondProbed, $MinuteProbed, $HourProbed, $DayProbed, ($MonthProbed-1), $YearProbed);
	}
	# Read Probe card information, only use last 8 charaters since "probe_card" in edb database is a varchar(8).
	read INPUT, $in, 16;
	$cCLINE = unpack "a16", $in;
        $cCLINE =~ s/[^\-_0-9a-zA-Z]//g; # get rid of unwanted charters
        if (length $cCLINE > 8) { $cCLINE = substr($cCLINE,-8);}

	read INPUT, $in, 40;
	$cOPER = unpack "A40", $in;
	$cOPER =~ s/[^A-Za-z0-9]*//g;

	read INPUT, $in, 16;
	$cLOT = unpack "A16", $in;
	$cLOT =~ s/[^0-9A-Za-z]*//g;
        $cLOT = uc($cLOT);

	# Dummy read
	read INPUT, $in, 1;

	read INPUT, $in, 3;
	$cPROB = join "", (unpack "a" x 3, $in);
	$cPROB =~ s/[^0-9A-Za-z]*//g;
	
	read INPUT, $in, 2;
	$SNNUM = char2short($in);
	
	read INPUT, $in, 2;
	$SNSIZE = char2short($in);
	
	read INPUT, $in, 2;
	$NUMDIE = char2short($in);
	
	read INPUT, $in, 1;
	$F1SSEG = unpack "c", $in;

	read INPUT, $in, 1;
	$F1ESEG= unpack "b", $in;
	
	read INPUT, $in, 2;
	$cSPARE = unpack "b" x 2, $in;
	
	read INPUT, $in, 2;
	$DARCNT = char2short($in);
	
	# 32 test #'s of data log sort
	read INPUT, $in, 32;
	@TestNumbers = unpack "c" x 32, $in;

	# 32 function #'s in dl sort
	read INPUT, $in, 32;
	@FunctionNumbers = unpack "c" x 32, $in;

	for ($ind = 0; $ind < 3; $ind++)
	{
		read INPUT, $in, 2;
		$WFTNUM[$ind] = char2short($in);
	}

	read INPUT, $in, 3;
	@WFSEG = unpack "c" x 3, $in;

	read INPUT, $in, 1;
	read INPUT, $in, 7;
	$RUNNAME = unpack "A7", $in;
	$RUNNAME =~ s/\.//;

	read INPUT, $in, 7;

	read INPUT, $in, 1;
	read INPUT, $in, 8;
	$TESTNAME = unpack "a8", $in;
	$TESTNAME =~ s/\.[0-9a-zA-Z]*//;
        $TNLeng = length ($TESTNAME);
        $TestProgName = substr($TESTNAME,0,($TNLeng-1));
        $TestProgNameRev = substr($TESTNAME,($TNLeng-1),1);
	read INPUT, $in, 6;
	
	read INPUT, $in, 361;
	$SPARE0 = unpack "a361", $in;

	#Pass/Total Counts Structure 1 CWCT(100), 2 CWCTPASS 2 CWCTTOT
	for ($ind = 0; $ind < 200; $ind++)
	{
		read INPUT, $in, 2;
		$anCWCT[$ind] = char2short($in); 
	#	print $anCWCT[$ind]."\n";
	}

	read INPUT, $in, 500;
	$CWNAM = unpack "a500", $in;
} # end of function
 
sub char2short
{
        my ($IN) = @_;
	@b = unpack "c" x 2, $IN;
        $ret = unpack "S", (pack "cc", $b[1], $b[0]) if $mft_flag==0;
        $ret = unpack "S", (pack "cc", $b[0], $b[1]) if $mft_flag==1;
        return $ret;
}

sub char2int
{
	my ($IN) = @_;
	@b = unpack "c" x 4, $IN;
	$ret = unpack "i", (pack "cccc", $b[3], $b[2], $b[1], $b[0]) if $mft_flag==0;
	$ret = unpack "i", (pack "cccc", $b[0], $b[1], $b[2], $b[3]) if $mft_flag==1;
        return $ret;

}

sub char2float
{
	my ($IN) = @_;
	@b = unpack "c" x 4, $IN;
        $ret = unpack "f", (pack "cccc", $b[3], $b[2], $b[1], $b[0])if $mft_flag==0;
        $ret = unpack "f", (pack "cccc", $b[0], $b[1], $b[2], $b[3])if $mft_flag==1;
        return $ret;
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

#######################
# MOVE FILE TO BAD DIR
# (FOR SOLARIS ONLY)
#######################
sub move_file_to_bad_dir
{
        my $loc_file = shift;
        my $loc_dir  = shift;
        my $fn       = ($loc_file=~/\//) ? substr($loc_file, rindex($loc_file,"/")+1) : $loc_file;
        system "mkdir $loc_dir" if ! -e $loc_dir;
        system "mv $loc_file $loc_dir";
        if (! -e "${loc_dir}/${fn}")
        {
                print "Failed to move $loc_file to $loc_dir dir. $!\n";
                exit 1;
        }
}


# File contains functions used by the FET.pl data convter.
# David Fletcher, Dec. 15, 2000  207-775-8809
# Scott Shumway,  Jul. 14, 2005  Added the ability to pass PART_CNT and GOOD_CNT to MRR.
# Scott Shumway,  May  22, 2006  Add Init1 for an alternative way to name files.
# Scott Shumway,  Sep. 25, 2008  Added the PRB_CARD = $cCLINE to EMIR. 
# Ben Rommel Kho, Jun  09, 2011  Added Init2 to change the way datalog and wmap files are named.
# Ben Rommel Kho  Jul  29, 2011  Modified Init2 since full lotid is already reflected to the raw filename

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
        local ($LotLevelCountREF) = @_;
        for $k (sort by_number keys %{$LotLevelCountREF} )
        {
                print "BIN: ".$k." ".$$LotLevelCountREF{$k}{Count}."\n";
        }
}

sub SumBinCounts
{
        local ($XYBinDataREF, $LotLevelCountREF) = @_;
        foreach $k (keys %{$XYBinDataREF} )
        {
                $$LotLevelCountREF{ $$XYBinDataREF{$k}{BIN} } =
                {
                        BIN => ($$LotLevelCountREF{ $$XYBinDataREF{$k}{BIN} }{Count} + $$XYBinDataREF{$k}{BIN}),
                };
                #print $$LotLevelCountREF{ $$XYBinDataREF{$k}{BIN} }{Count}."\n";
        }
}

sub PopulateMRR
{
        local ($GoodDie, $Tested) = @_;
        #
        # write MRR
        #
        %out::mrr = %{$out::init{mrr}};
        $out::mrr{finish_t} = $Start_time;
        $out::mrr{part_cnt} = $Tested;
        $out::mrr{good_cnt} = $GoodDie;
        print OUTPUT &out::pack_MRR(\%out::mrr) ;
        close OUTPUT ;
}

sub UPDateEMIR
{
        local ($FileNAME, $WSUM_Count, $WSBR_Count) = @_;
        #
        # Update EMIR record with wafer summation stats.
        #
        $out::emir{setup_t}  = $Start_time;
        $out::emir{wsum_cnt} = $WSUM_Count;
        $out::emir{whwb_cnt} = $WSBR_Count;
        $out::emir{start_t}  = $Start_time;
        &out::update_EMIR(\%out::emir, $FileNAME) ;
}

sub PopulateWSBR
{
        local ($XYBinDataREF, $MaxBin, $LotLevelBinArrayRef) = @_;
        local $WSBR_CNT=0;
	@SWBinCnt=();

        #
        # Walk through the array and create the bin counts
        #
        foreach $k (keys %{$XYBinDataREF} )
        {
                $SWBinCnt[$$XYBinDataREF{$k}{BIN}]++;
        }

	#print "WSBR_Bin1: $SWBinCnt[1]\n";

        for ($i = 1; $i <= $MaxBin; $i++)
        {
                %out::WSBR = %{$out::init{WSBR}};
                $out::WSBR{sbin_num} = $i;
                if ($SWBinCnt[$i] eq "")
                {
                        $out::WSBR{sbin_cnt} = 0;
                }
                else
                {
                       	$out::WSBR{sbin_cnt} = $SWBinCnt[$i];
			$${LotLevelBinArrayRef}[$i] = $${LotLevelBinArrayRef}[$i] + $SWBinCnt[$i];
                }
		#printf "%6s ",$out::WSBR{sbin_cnt};
                $out::WSBR{sbin_nam} = "SWBin".$i; 
                print OUTPUT &out::pack_WSBR(\%out::WSBR);
                $WSBR_CNT++;
        }
	#print "\n";
        return $WSBR_CNT;
}

sub PopulateWHBR
{
        local ($XYBinDataREF, $MaxBin, $LotLevelBinArrayRef) = @_;
        local $WHBR_CNT=0;
        @HWBinCnt=();

        #
        # Walk through the array and create the bin counts
        #
        foreach $k (keys %{$XYBinDataREF} )
        {
                $HWBinCnt[$$XYBinDataREF{$k}{BIN}]++;
        }

        #print "WHBR_Bin1: $HWBinCnt[1]\n";

        for ($i = 1; $i <= $MaxBin; $i++)
        {
                %out::WHBR = %{$out::init{WHBR}};
                $out::WHBR{hbin_num} = $i;
                if ($HWBinCnt[$i] eq "")
                {
                        $out::WHBR{hbin_cnt} = 0;
                }
                else
                {
                        $out::WHBR{hbin_cnt} = $HWBinCnt[$i];
                        $${LotLevelBinArrayRef}[$i] = $${LotLevelBinArrayRef}[$i] + $HWBinCnt[$i];
                }
                #printf "%6s ",$out::WHBR{hbin_cnt};
                $out::WHBR{hbin_nam} = "HWBin".$i;
                print OUTPUT &out::pack_WHBR(\%out::WHBR);
                $WHBR_CNT++;
        }
        #print "\n";
        return $WHBR_CNT;
}

sub PopulateSBR
{
	#
	# Lot Level
	#
        local ($LotLevelBinArrayRef, $MaxBin) = @_;
        local $SBR_CNT=0;

	#print "SBR_Bin1: $$LotLevelBinArrayRef[1]\n";

        for ($i = 1; $i <= $MaxBin; $i++)
        {
                %out::SBR = %{$out::init{SBR}};
                $out::SBR{sbin_num} = $i;
                if ($$LotLevelBinArrayRef[$i] eq "")
                {
                        $out::SBR{sbin_cnt} = 0;
			$out::SBR{sbin_nam} = "SWBin".$i;
			print OUTPUT &out::pack_SBR(\%out::SBR);
			$SBR_CNT++;
                }
                else
                {
                        $out::SBR{sbin_cnt} = $$LotLevelBinArrayRef[$i];
                	$out::SBR{sbin_nam} = "SWBin".$i;
                	print OUTPUT &out::pack_SBR(\%out::SBR);
                	$SBR_CNT++;
		}
        }
        return $SBR_CNT;
}

sub PopulateHBR
{
        #
        # Lot Level
        #
        local ($LotLevelBinArrayRef, $MaxBin) = @_;
        local $HBR_CNT=0;

        #print "HBR_Bin1: $$LotLevelBinArrayRef[1]\n";

        for ($i = 1; $i <= $MaxBin; $i++)
        {
                %out::HBR = %{$out::init{HBR}};
                $out::HBR{hbin_num} = $i;
                if ($$LotLevelBinArrayRef[$i] eq "")
                {
                        $out::HBR{hbin_cnt} = 0;
                        $out::HBR{hbin_nam} = "HWBin".$i;
                        print OUTPUT &out::pack_HBR(\%out::HBR);
                        $HBR_CNT++;
                }
                else
                {
                        $out::HBR{hbin_cnt} = $$LotLevelBinArrayRef[$i];
                        $out::HBR{hbin_nam} = "HWBin".$i;
                        print OUTPUT &out::pack_HBR(\%out::HBR);
                        $HBR_CNT++;
                }
        }
        return $HBR_CNT;
}

sub Init
{
	local ($Type, $InputFileName) = @_;
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

        $FileName0 = "${cLOT}.${Type}_${DateTime}_STDF";

        #####################
        # Make sure there is no other file of the same name in the directory
        $Cnt = 0;
        while ( -e $FileName0)
        {
                $FileName0 = "${cLOT}.${Type}_${DateTime}${Cnt}_STDF";
                $Cnt++;
        }
        #print "FileName0: $FileName0\n";

        ############################
        # Open the file.
        open (OUTPUT, ">$FileName0");

        return ($FileName0);
}

sub Init1
{
	local ($Type, $InputFileName) = @_;
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

        $FileName0 = "${Junk}.${Type}_${DateTime}_STDF";

        #####################
        # Make sure there is no other file of the same name in the directory
	#####################
        $Cnt = 0;
        while ( -e $FileName0)
        {
                $FileName0 = "${Junk}.${Type}_${DateTime}${Cnt}_STDF";
                $Cnt++;
        }
        #print "FileName0: $FileName0\n";

        ############################
        # Open the file.
        open (OUTPUT, ">$FileName0");

        return ($FileName0);
}


sub Init2
{
	local ($Path, $InputFileName, $MapID) = @_;

	### CREATE FILENAME FOR WMAP FILE ###
	if ($MapID ne "")
	{
		### GET ENV NAME ###
		my $envname  = $ENV{ENV_NAME};
         	   $envname  = uc($envname);
         	   $envname  =~ s/edb_|_v22//ig;
	     local $DateTime = `date '+%m%d%y%H%M%S'`;
             chomp($DateTime);

		### CREATE NEW WMAP NAME ###
		$InputFileName = "${cLOT}_${MapID}_${DateTime}_${PID}_${envname}.WM";

		#$InputFileName =~ s/${cLOT}/${cLOT}_${MapID}/i;
		#$InputFileName =~ s/\.CPR/\_WM.TD/i;
	}
	### CREATE FILENAME FOR TEST DATALOG FILE ###
	else
	{
		$InputFileName .= ".TD";
	}
	
        $InputFileName = ${Path} . "/" . ${InputFileName};
	### Open the file ###ToFile
        open (OUTPUT, ">$InputFileName");

	return ($InputFileName);

}

sub PopulateEMIR
{
        ############################
        # Write EMIR header record
        %out::emir = %{$out::init{emir}};

        $out::emir{lot_id}      = $cLOT;
        $out::emir{tstr_typ}    = "FET";
        $out::emir{customer}    = "Salt Lake FET";
        $out::emir{oper_nam}    = $cOPER;
	$out::emir{stat_num}    = $cPROB;
	$out::emir{node_nam}    = "";
        $out::emir{hand_id}     = $cPROB;
        $out::emir{prb_card}    = $cCLINE; 
        $out::emir{spec_nam}    = $TestProgName;
        $out::emir{job_nam}     = $TestProgName; 
        $out::emir{job_rev}     = $TestProgNameRev;
        $out::emir{spec_rev}    = $TestProgNameRev;
	$out::emir{device}      = $TestProgName;
	$out::emir{part_typ}    = $TestProgName;
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
        $out::ewcr{wf_flat} = "D";
       	$out::ewcr{pos_x} = "R";
        $out::ewcr{pos_y} = "D";
        $out::ewcr{origin} = 2;
        $out::ewcr{praxis} = -1;
        $out::ewcr{start_x} = 0;
        $out::ewcr{start_y} = 0;
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

