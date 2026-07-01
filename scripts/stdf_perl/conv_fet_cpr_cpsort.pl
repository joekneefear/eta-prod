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
# Purpose: 	Convert Cebu  FET test tester data to STDF+
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
#  Scott Shumway   03/15/01  Changed the way TestPlan and TestPlan Rev are read in.
#  Rodney Cyr      10/25/01  Reset NUM_TEST to '0' after each EPRR record.
#  Ben Rommel Kho  02/11/02  Send email notification on error event 
#  David Fletcher  02/14/02  Changed flow of program from top down to function calls
#  David Fletcher  03/29/02  Moved Wafer Map STDF data file generation out to FET_waferSTDF.pm
#  		   	     Made provisions for bin 1-4 to be 'good' bins.
#
#			     NOTE: FOR ALL FET SORT DATA, BINS 1-4 ARE CONSIDERED TO BO GOOD BINS.  Gingging, Rodney CYR, David Fletcher
#  David Fletcher  4/3/02    @iUBIN is used for both hardware and software bin records.
#
#  DMF, DLabrie    4/18/02   Changed way of identifing good software bins, they now come from the Data Log Bin Result
#			     flag ($FLAG - 2nd flag, bit 8).
#
#  Dlabrie 	   6/05/02   Modified converter to open the associated PRN file to retriece the "Good Bins"
#			     Added a check to ignore empty "WIR" records and continue to the "next" wafer
#			     Changed the converter to use TESTNAME for the Test Plan instead of RUNNAME
#
#			     Added a check/sorter to make sure the proper cpr file is converted in the correct environment
#
#  RCyr            9/13/02   Added check for no wafer id; files with no wafer id were being converted and loaded
#                            causing bogus entries in EWB.
#
#  Ben Rommel Kho 10/24/05   Modified for regionalization. Query Sort's Wks DB for source lot instead of psoft files.
#  Ben Rommel Kho 08/08/07   Modified to auto-delete fetquad datalogs.
#  Ben Rommel Kho 10/31/07   CPR doesn't contain Sbin summary records. Equate sbin summary to hbin.
#  Ben Rommel Kho 05/16/08   Use filename if no lotid is found 
#  Ben Rommel Kho 07/16/08   Adjusted to use sequence file
#  Ben Rommel Kho 10/09/10   Reflect WaferID to STDF filename
#  Gilbert Miole  03/28/11   Try to get wafer id from its file name if it does not contain otherwise stop and
#                            trap datalog having no test data.
#  Gilbert Miole  04/11/11   Adopted .TD & .TP STDF filenaming convention.
#  Gilbert Miole  04/20/11   To make the file name in ENV_ARCHIVE and ENV_GOOD the same after conversion.
#  Ben Rommel Kho 02/09/12   Enable "Grid/Non-grid" feature
#  Gilbert Miole  06/15/12   Made MFT compatible
#  Gibert  Miole  08/11/12   Change translation of char2short, char2int, char2float for Linux.
#  Rodney Cyr     08/31/12   Changed negative exit codes to positive (negative exit codes are not valid in unix).
#  Gilbert Miole  10/19/12   Change look up path of sequence file from ENV_CONV/seq to ENV_TP_RAW.
#  Gilbert Miole  01/14/14   Disable the flagging of grid die and enable the option in the Summarizer.
#  Gilbert Miole  05/12/14   Enable back email notification on error event.
#  Gilbert Miole  05/15/14   Removed file path in error message.
#  Eric Alfanta	  05/13/2020 Use camstar web service to extract cmap or seq name	
# 23/Apr/2021 jgarcia       modified to support colo server. replace hardcoded TP and reference file folder location.
#
#
#
		
	

#################
# LOAD LIBRARIES
#################
use Carp 			;  # error messages - does not work within stdf_use.pl
use FindBin 			;
use lib "$FindBin::Bin" 	; # set up path for libraries the same as script
use English 			;
use lib $ENV{'STDF_PERL_LIB'} 	; # look for libraries in this directory
#use Net::FTP			;
#use File::Copy			;
use FET_STDF			;
use FET_wafermapSTDF		;
#use Sybase::CTlib       	;
require "stdf_use.pl" 		;  # libraries that are not generated
use MIME::Lite			;
use Getopt::Long              	;
#use EDBUtil                   	;
use LWP::UserAgent;

#############
# Debug level : 1 = print all commands to STDOUT, 0 = silent
#############
$debuglevel = 0;


######################
# LOAD SPECIFICATIONS
######################
{
	package out ;
	if ( !eval(&::generate_all('stdfPL.spec')))
  	{ 
		confess $@ ; 
	}
	require 'stdfPL.pl' ;
}


###################
# GLOBAL VARIABLES
###################
$stdf_max_wmr_physical_die_bins = 32000 ;               # set equal to STDF_MAX_WMR_PHYSICAL_DIE_BINS
our $file	  = "";
$BLKSize          = 1536;
$DeviceID         = 0;
$WARNING          = 0;
%XYBinData        = ();
$quad_flag        = 0;
$Wstream_reload   = "";
$subject 	  = "CPFET ERROR";
my %seq        	  = {};
my $td_filename   = "";
my $plant         = uc($ENV{ENV_FACILITY});     #<-- MFT ENV VAR
my $mft_flag      = ($^O=~/linux/i) ? 1 : 0;    #<-- SET 0=OTHERS; 1=LINUX
my $envname       = uc($ENV{ENV_NAME});         #<-- GET ENV NAME


######################
# RETRIEVE PARAMETERS
######################
$result = GetOptions ("infile=s"   => \$file,
                      "plant=s"    => \$plant,
                      "env_mod=s"  => \$env_mod);
require "$ENV{ENV_DB_SCRIPT}/$env_mod" if $env_mod ne "";       ### LOAD OPTIONAL MODULE


#################
# DISPLAY SYNTAX
#################
if ($file eq "")
{
        print "syntax\n";
        print "\tscript -infile=<datalog file> -plant=<plant(opt)> -env_mod=$ENV{ENV_CONV_SCRIPT}/env_mod.pm(opt)>\n";
        exit 1;
}

&pre_parse_module()    if $env_mod ne "";

#################################
# MAIN MAIN MAIN MAIN MAIN MAIN #
#################################
open (INPUT, "$file");


###################
# READ HEADER INFO
###################
&ReadCPRHeader();

#print "======>$cLOT======>$cCLINE\n";

$cCLINE = getSeqCamstar($cLOT);

################
# READ SEQ FILE
################
&read_sequence_file() if $cCLINE ne "";


####################
# GET SOURCE LOT ID
####################
#&GetSourceLotID();


###################
# READ TEST RESULT
###################
&ReadData();
close(INPUT);


##############################
# GENERATE STDF+ DATALOG FILE
##############################
&DatalogSTDF(@good_bins_prn);


########################
# RETURN CONVERTED FILE
########################
print "$td_filename"          if $mft_flag==0;
print "\ntd=$td_filename"     if $mft_flag==1;


exit 0;

#<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< SUBROUTINES >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

##########################
# FIND/READ SEQUENCE FILE
##########################
sub read_sequence_file
{
	my $seq_file = "${cCLINE}.SEQ";
	###########################
	# CHECK IF SEQ FILE EXISTS
	###########################
	#if (! -e "$ENV{ENV_TP_RAW}/$seq_file")
	if (! -e "$ENV{DPDATA}/data/cpsort_fet/TP/$seq_file")
	{
		### LOG MISSING SEQ FILES ###
		#open LOG, ">>$ENV{ENV_LOG}/no_seq_file.log" or die "can't create no_seq_file.log file\n";
		open LOG, ">>$ENV{DPDATA}/data/cpsort_fet/log/no_seq_file.log" or die "can't create no_seq_file.log file\n";
		print LOG "${seq_file}\t${file}\n";
		close(LOG);
	
		### PRINT ERROR MSG ###
		#print "Required SEQ File: $seq_file\n";
		
		print "\ndir=no_seq_file";                 ### RETURN BAD SUBDIR FOR MFT
                &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_seq_file") if $mft_flag==0;
                exit 100;

	}

	########################################
	# GET X,Y COORDINATES FROM THE SEQ FILE
	########################################
	#open SEQ, "$ENV{ENV_TP_RAW}/$seq_file" or die " Failed to open seq file $seq_file\n";
	open SEQ, "$ENV{DPDATA}/data/cpsort_fet/TP/$seq_file" or die " Failed to open seq file $seq_file\n";
	while($line=<SEQ>)
	{
		chomp($line);
		(@dummy) = split /\s+|\,/, $line;
		
		if ($dummy[0] eq "TD" && $dummy[1] > 0)
		{
			$dummy[1] =~ s/ //g;
			$dummy[2] =~ s/ //g;
			$dummy[3] =~ s/ //g;
			$seq{$dummy[1]} =
			{
				X => $dummy[2],
				Y => $dummy[3],
			};
		}
	}
	close(SEQ);
}


########################
# READ CPR TEST RESULTS
########################
sub ReadData
{
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
		
		($WaferXYBinDataRef, $DataLogArrayRef, $RowCnt, $ColCnt, $DieTested, $GoodDie, $SWBins, $HWBins, $GoodBins) = ReadIndividualWaferHeaderRecord();
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
		@HardWareBins   = @{$HWBins};
		@SoftWareBins   = @{$SWBins};
#		@GoodBins       = @good_bins_prn; ### OLD @{$GoodBins};
		if ($GoodDie eq "")
		{
			$GoodDie = 0;
		}

		### TRAP DATALOG WITHOUT TEST DATA ###
		if ($#DLWaferResults == -1)
		{
			print "\ndir=no_part_data";                 ### RETURN BAD SUBDIR FOR MFT
                	&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_part_data") if $mft_flag==0;
                	exit 100;
        	}


		$WaferBinData{$iWaferNum} =
		{
			WaferID   => $iWaferNum,
			ROWCount  => $RowCnt,
			COLCount  => $ColCnt,
			DIETested => $DieTested,
			GoodDie   => $GoodDie,
			WAFER     => { %XYBins },
			DATALOG   => [ @DLWaferResults ],
			SOFTBINS  => [ @SoftWareBins ],
			HARDBINS  => [ @HardWareBins ],
			#GOODBINS  => [ @GoodBins ],
		};
		%XYBins=();
		@DLWaferResults=();
		@SoftWareBins=();

 

		### TRY TO GET WAFER ID FROM ITS FILE NAME IF IT DOES NOT CONTAIN.OTHERWISE, STOP ###
		if ($iWaferNum !~ /^\d{1,2}$/)
                {
                    my $filename   = substr($file, rindex($file,"/") + 1) if $file =~ /\//;
                        (@dump)    = split /\_|\./, $filename;
                        $dump[0]   =~ /^\w+(\d\d)/i;
                        $waferid   ="$1";
                        $iWaferNum = "$waferid";

                        if ($iWaferNum eq "")
                        {
				print "\ndir=no_wafer_id";                 ### RETURN BAD SUBDIR FOR MFT
                		&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_wafer_id") if $mft_flag==0;
                		exit 100;
                        }
                }
		
	}
}


#####################
# GENERATE STDF FILE
#####################
sub DatalogSTDF
{	

	### Rename filename in Archive directory to something that can be tracked	
	#$file = rename_ID(); removed renaming, should be handled by doDispatch.pm


	#-------------------( Create One STDF+ file for data log )------------#
	
	#
	# initialize record
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
	#$FileNAME = Init("CPFET_DL", $file, $iWaferNum);
	$td_filename = Init($file);
	
	#
	# Entire LOT  Good Count
	#
	$MRRGOOD_Cnt = 0;
	
	#
	# write EMIR header record
	#
	PopulateEMIR();
	

	############################
	# WRITE LTR IF SOURCE LOTID 
	############################
	if ($source_lot ne "")
	{
		&PopulateLTR($source_lot);
	}


	#
	# Loop through the entire hash of 
	# wafer extracting the data log data
	# and populating the STDF+ file.
	#
	$WRRCount  = 0;
	$PRES_CNT  = 0;
	$WRRCount  = 0;
	$EPRRCount = 0;
	$PartCount = 0;
	$PRRCount  = 0;
	%LotLevelWSBRCount = ();
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
	
	        map { [$_, /^(.+)\t(.+)\t(.+)\t(.+)\t(.+)\t(.+)\t(.+)/] } @{ $WaferBinData{$k}{DATALOG} } ;
	
		# 
	        # initialize fields
	        #
	        $out::ptr{test_num} = ${out::init{ptr}{test_num}};
	        $out::pir{part_id}  = ${out::init{pir}{part_id}};
	        $out::ptr{result}   = ${out::init{ptr}{result}};
	        $out::wir{wafer_id} = ${out::init{wir}{wafer_id}};
	        $out::wir{start_t}  = ${out::init{wir}{start_t}};
	
		($out::wir{wafer_id}, $CurX, $CurY, $DeviceID, $out::ptr{test_num}, $out::ptr{result}, $BIN) =
	                        split (/\t/, $Array[0], 7);
	
		#print "\nSTR: $out::wir{wafer_id}, $CurX, $CurY, $DeviceID, $out::ptr{test_num}, $out::ptr{result}\n";
	
		#
	        # Write WIR record
	        #
	        $out::wir{start_t} =  $Start_time;
	       	if ($out::wir{wafer_id} eq "")
                {
                        next;
                } 


		###################################################
        	# COMPUTE DISTANCE OF GRID DIES IF TOTAL DIE > 200
        	###################################################
		my $part_count = $WaferBinData{$iWaferNum}{DIETested};
        	my $distance   = 1;
        	if ($part_count > 200)
        	{
                	$distance   = sqrt($part_count/200);
                	$distance   = 5 if $distance > 5;
        	}
		#print "dist=$distance\tparts=$part_count\n";


		print OUTPUT &out::pack_WIR(\%out::wir);
	
		for ($P = 0; $P <= $#Array; $P++)
		{
			#Init Test Numbers
	                $FirstPartID = $LastPartID = $DeviceID;
	
			#######################################
			# SKIP PART IF NOT DEFINED IN SEQ FILE 
			#######################################
			next if $seq{$DeviceID}{X} eq "" && $cCLINE ne "";

			$out::pir{part_id}  = ${out::init{pir}{part_id}} ;
	                $out::mrr{part_cnt}++ ;  # increment part count
	
			$out::pir{x_coord} = $seq{$DeviceID}{X} if $cCLINE ne ""; ### IF SEQ IS AVAILABLE
	                $out::pir{y_coord} = $seq{$DeviceID}{Y} if $cCLINE ne ""; ### IF SEQ IS AVAILABLE

			
			#########################
			# SET GRID/NON-GRID FLAG
			#########################
			my $grid  = "0";         # 0=GRID; 1=NON-GRID # Enable at Summarizer
			   #$grid = "0" if ($seq{$DeviceID}{X} % $distance)==0 && ($seq{$DeviceID}{Y} % $distance)==0;
			   #$grid = "0" if int($iWaferNum)==2 || $file =~ /^E/i || $file =~ /\_FULL/i;	

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
				
				($out::wir{wafer_id}, $CurX, $CurY, $DeviceID, $out::ptr{test_num}, $out::ptr{result}, $BIN) =
	                        	split (/\t/, $Array[$P], 7);
				#print "\tMID: $out::wir{wafer_id}, $CurX, $CurY, $DeviceID, $out::ptr{test_num}, $out::ptr{result}\n";
	
				if ($out::wir{wafer_id} eq "")
	                        {
					$error_msg = "Wafer ID: [".$out::wir{wafer_id}."]. WAFER ID CAN NOT BE BLANK: $Array[$P]";
					&send_email($error_msg);
	                		#print "$error_msg \n";
					print "\ndir=no_wafer_id";                 ### RETURN BAD SUBDIR FOR MFT
                			&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_wafer_id") if $mft_flag==0;
                			exit 100;

					
	                        }
	
				#
				#
				#
				$out::ptr{test_num} = $out::ptr{test_num};
	                        $out::ptr{test_flg} = "01" . ${grid} . "00000";
			
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
				#$LastBin = $BIN;
				$LastX = $CurX;
				$LastY = $CurY;
				
	                        $P++ ; # Increase array index
				$LastWaferID = $out::wir{wafer_id};
				($out::wir{wafer_id}, $CurX, $CurY, $DeviceID, $out::ptr{test_num}, $out::ptr{result}, $BIN) =
	                                split (/\t/, $Array[$P], 7);
				#print "\t\tEND: $out::wir{wafer_id}, $CurX, $CurY, $DeviceID, $out::ptr{test_num}, $out::ptr{result}\n";
				$FirstPartID = $DeviceID;
			}
			$P--;
			############################################
	                # Write EPRR record
	                #
			$out::eprr{x_coord} = $seq{$LastPartID}{X} if $cCLINE ne ""; ### IF SEQ IS AVAILABLE
			$out::eprr{y_coord} = $seq{$LastPartID}{Y} if $cCLINE ne ""; ### IF SEQ IS AVAILABLE
	                $out::eprr{part_id} = $LastPartID ;
	                $EPRRCount++;
	                print OUTPUT &out::pack_EPRR(\%out::eprr) ;
	                ############################################
	                $out::eprr{num_test} = 0;
		}
		#

		($WRRPART_Cnt, $WSBRCount)   = PopulateWSBR($WaferBinData{$k}{HARDBINS});
		($WRRGOOD_Cnt, $WHBRCount)   = PopulateWHBR($WaferBinData{$k}{HARDBINS});
               	
		$MRRGOOD_Cnt = $MRRGOOD_Cnt + $WRRGOOD_Cnt; 
		$LotWSBR_CNT = $LotWSBR_CNT + $WSBRCount;
		$LotWHBR_CNT = $LotWHBR_CNT + $WHBRCount;
		
		%out::wrr = %{$out::init{wrr}} ;
		##########################################
		# Write WRR record
		#
		$out::wrr{wafer_id} = $LastWaferID;
		$out::wrr{good_cnt} = $WRRGOOD_Cnt;
		$out::wrr{finish_t} = $Start_time;
		$out::wrr{part_cnt} = $WRRPART_Cnt;
		$out::wrr{rtst_cnt} = 0;
		$out::wrr{abrt_cnt} = 0;
		$out::wrr{func_cnt} = 0;
		print OUTPUT &out::pack_WRR(\%out::wrr) ;
		##########################################
		$PartCount = 0;
		$PRRCount++;
	} # END loop through hash

	##################################################
        # Populate the lot level SBR and HBR record count

	#
	# Need a function to summ all of the bin counts here!!!
	#
	my $MRRPART_Cnt = 0;
	($MRRPART_Cnt, $BinSummationsRef) = SumBinCounts(\%WaferBinData);
        $SBRCount = PopulateSBR($BinSummationsRef);
	$HBRCount = PopulateHBR($BinSummationsRef);
	
	#
	# write MRR
	#
	$out::mrr{finish_t} = $Start_time;
	$out::mrr{disp_cod} = "L";
	$out::mrr{good_cnt} = $MRRGOOD_Cnt;
	$out::mrr{part_cnt} = $MRRPART_Cnt;
	$out::mrr{rtst_cnt} = 0;
	$out::mrr{abrt_cnt} = 0;
	$out::mrr{func_cnt} = 0;
	print OUTPUT &out::pack_MRR(\%out::mrr) ;
	close OUTPUT ;
	
	#
	# Update EMIR record with wafer summation stats.
	#
	$out::emir{setup_t}  = $Start_time;
	$out::emir{ssum_cnt} = 1;
	$out::emir{psum_cnt} = $EPRRCount;
	$out::emir{wsum_cnt} = $WRRCount;
	$out::emir{sswb_cnt} = $SBRCount;
	$out::emir{whwb_cnt} = $LotWHBR_CNT; #whbr record count
	$out::emir{shwb_cnt} = $HBRCount; #hbr record count
	$out::emir{wswb_cnt} = $LotWSBR_CNT; #WSBR Records
	$out::emir{pres_cnt} = $PRES_CNT; #ptr record count
	$out::emir{start_t}  = $Start_time;

	#
	# update EMIR with count information
	#
	&out::update_EMIR(\%out::emir, $td_filename); 
	
	close (OUTPUT);
	 
	#-------------------( END: Create One STDF+ file for data log )------------#
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
	
		#read the fail counters	
		for ($ind = 0; $ind < 250; $ind++)
		{
			read INPUT, $in, 2;
			$uFAIL[$ind] = char2short($in);

		}

		#read total test counters
		for ($ind = 0; $ind < 250; $ind++)
                {
			read INPUT, $in, 2;
			$UTFAIL[$ind] = char2short($in);
	

		}

		#read best yield counters
		for ($ind = 0; $ind < 25; $ind++)
		{
			read INPUT, $in, 4;
			#$iUBEST[$ind] = char2int($in);
			$iUBEST[$ind] = bcd2int($in);	

		}

		#read sort counters SOFTWARE BIN RECORDS for single site only
		for ($ind = 0; $ind < 25; $ind++)
                {
			#
			# Software bin fields from this array will not be used
			# because they do not fit the EWB model, i.e. in lot S2SWO9477C, soft bin 10 = hard bin 1
			# This creates problems with the test plan data mapping, etc.
			# Rodney Cyr, David Fletcher 4/2/2002
			#
                        read INPUT, $in, 4;
                        $iUSORT[$ind] = bcd2int($in);
			#print "$iUSORT[$ind], ";
		}

		# read bin counters
		# read bin counters HARDWARE BIN RECORDS for "single" site only, not quad.
		# For data conversion, the hardware bins from this array will be used
		# for both hardware bin and software bin summary records.
		#
		# Rodney Cyr, David Fletcher 4/2/2002
		#
		for ($ind = 0; $ind < 25; $ind++)
                {
                        read INPUT, $in, 4;
                        $iUBIN[$ind] = bcd2int($in);
			#printf("%5d, ", $iUBIN[$ind]);
		}
		#print "\n";
	
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
		($BinDataRef, $DataLogArrayRef, $RowCnt, $ColCnt, $DieTested, $GoodDie, $GoodBins) = WaferDataRecord($iWaferNum);

		#
		# Return the Reference to the hash containing the 
		# Bin results, including the X and Y Coordinates.
		#
		#return ($BinDataRef, $DataLogArrayRef, $RowCnt, $ColCnt, $DieTested, $GoodDie, \@iUBIN, \@iUSORT, $GoodBins);
		return ($BinDataRef, $DataLogArrayRef, $RowCnt, $ColCnt, $DieTested, $GoodDie, \@iUSORT, \@iUBIN, $GoodBins);
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
		for ($k = 0; $k < $DARCNT; $k++)
		{
			for ($j = 0; $j < $SNNUM; $j++)
			{
				$DeviceID++;
				if (!(--$iDieCount))
				{
					last;
				}
				read INPUT, $in, 1;
				$XCOR = unpack "C", $in;
				if ($XCOR == 0)
				{
					if ($iDieNumber == 0)
					{
						$emptywafer = 1;
					}
					#last;
				}
				read INPUT, $in, 1;
                                $YCOR = unpack "C", $in;
				#print "X: $XCOR - Y: $YCOR\n";

				read INPUT, $in, 1;
                                $BINRESULT = unpack "c", $in;
	
				$BinBITS = unpack("B8", $in);

				read INPUT, $in, 1;
				$BINResultFlag = unpack("B8", $in) ;
			
				#print "Bin Result: ".($BINRESULT & 127 )." $BINResultFlag\n";

				read INPUT, $in, 4;
				$SEGRSL = char2float($in); #First result
				#print "First Result: $SEGRSL\n";
				$TestNum = 1;
				$XYBinDataKey++;
				$XYBinData{$XYBinDataKey} = 
				{
					XCor     => $XCOR,
					YCor     => $YCOR,
					BIN      => ($BINRESULT & 127),
				};
				$DieTestedCnt++;

				# 
				# Must Fix the GoodDieCnt Variable.
                		#	
				$GoodDieCnt++;

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
				$state_flag = 0;
			
				### Check for a bad bin ###	
				if (substr($BinBITS, 0, 1) eq "1") 
				{
					$state_flag = 1;
				}	
				

				for ($ii=0; $ii < $cntSNSIZE; $ii = $ii + 5)
				{
					$TestNum++;	
					read INPUT, $in, 1;
					$FLAG = unpack("B8", $in);
					read INPUT, $in, 4;
                                        $RESULT = char2float($in);	
			

					### Only create PTR record for a "real" test	
					if (substr($FLAG, 0, 1) eq "1")
					{

						$ResultsData{$TestNum} =
	                                         {
       		                                      Result   => $RESULT,
               		                              Flag     => $FLAG,
                       		                      XCor     => $XCOR,
                               		              YCor     => $YCOR,
						      DeviceID => $DeviceID,
                                             	      BIN      => $XYBinData{$XYBinDataKey}{BIN},
						};
				
					}
					
					
				}
			

				### Check for Good Bins ###	
				if ($state_flag == 0)
				{		
					$GoodBins[$XYBinData{$XYBinDataKey}{BIN}]++;
				}
				#print "\n";


				#####################################
				# Populate the array to hold results
				foreach $KEY (sort keys %ResultsData)
				{
					$Data = "$iWaferNum\t".
						"$ResultsData{$KEY}{XCor}\t".
						"$ResultsData{$KEY}{YCor}\t".
						"$ResultsData{$KEY}{DeviceID}\t".
						"$test_logged[$KEY -1]\t".	
						"$ResultsData{$KEY}{Result}\t".
						"$ResultsData{$KEY}{BIN}";
					#print $Data."\n";
					push (@Outputarray,  $Data);
				} 
				%ResultsData=();
			}
			my $Ret = 0;
                        for($Ret=1; ((tell(INPUT) % $BLKSize) != 0) && $Ret!=0; $Ret = read(INPUT, $in, 1))
                        {}
		}
		#print "Good Bins: ";
                #for ($i = 0; $i <= $#GoodBins; $i++)
                #{
                #	if (defined($GoodBins[$i]) && $GoodBins[$i] ne "")
                #        {
                #                print "$i ";
                #        }
                #}
                #print "\n";
	$RowCount = $maxX + $minX + 1;
        $ColCount = $maxY + $minY + 1;
	return (\%XYBinData, \@Outputarray, $RowCount, $ColCount,  $DieTestedCnt, $GoodDieCnt, \@GoodBins);
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


#######################
# READ CPR HEADER INFO
#######################
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
        	($MonthProbed, $DayProbed, $YearProbed) = split(/\/+/, $cCDATE);
		#print "mo <$MonthProbed> day <$DayProbed> yr <$YearProbed> date <$cCDATE>\n";
	}
	elsif (index($cCDATE, "-") >= 1)
	{
		($MonthProbed, $DayProbed, $YearProbed) = split(/-/, $cCDATE);
		
	}
	elsif (index($cCDATE, "\\") >= 1)
	{
		($MonthProbed, $DayProbed, $YearProbed) = split(/\\/, $cCDATE);
	}
	if ($YearProbed eq 0)
        {
                $YearProbed = "2000";
        }

	$MonthProbed =~ s/^[^1-9]//;
	($YearProbed,@trash) = (split /\./, $YearProbed);	
	
	if($YearProbed >= 1990)
	{
		#print "SMHDMY $SecondProbed, $MinuteProbed, $HourProbed, $DayProbed, ($MonthProbed-1), $YearProbed\n";	
        	$Start_time = timegm($SecondProbed, $MinuteProbed, $HourProbed, $DayProbed, ($MonthProbed-1), $YearProbed);
		#print "$Start_time  Start_time_correct\n";	
	
		$prnt_date = $MonthProbed."/".$DayProbed."/".$YearProbed;
	
	}

	else
	{
		$Start_time = time();
		print "$Start_time  Start_time\n";	
		$prnt_date = localtime();	
	}	


	read INPUT, $in, 16;
	$cCLINE = unpack "A16", $in;
	$cCLINE =~ s/^\s|\s$|[^0-9A-Z\-\_]//g;
	$cCLINE = "" if $cCLINE =~ /\_\d{1,}$/;		### "_#" MEANS PROBE CARD AND NOT SEQ FILE.
							### SEQ FILES ENDS W/ _R#, _SMART, & _LEVEL#
	read INPUT, $in, 40;
	$cOPER = unpack "A40", $in;
	$cOPER =~ s/[^A-Za-z0-9]*//g;

	read INPUT, $in, 16;
	$cLOT = unpack "A16", $in;
	$cLOT =~ s/[^0-9A-Za-z]*//g;
	$cLOT = uc $cLOT;

	### ATTEMPT TO UTILIZE FILENAME AS LOTID ###
        if ($cLOT eq "")
        {
                my (@dummy) = split /\_/, $file;
                $cLOT       = uc($dummy[0]) if length($dummy[0]) >= 5;
        }

        ### FAIL IF NO LOTID ###
	if($cLOT eq "")
	{
		print "\ndir=no_lotid";                 ### RETURN BAD SUBDIR FOR MFT
                &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_lotid") if $mft_flag==0;
                exit 100;
	}


	# Dummy read
	read INPUT, $in, 1;

	read INPUT, $in, 3;
	$cPROB = join "", (unpack "a" x 3, $in);
	$cPROB =~ s/[^0-9A-Za-z]*//g;
	$cPROB = uc $cPROB;
	
	read INPUT, $in, 2;
	$SNNUM = char2short($in);
	
	read INPUT, $in, 2;
	$SNSIZE = char2short($in);
	#print "Test_Cnt: $Test_Cnt\n";	
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
	
	###### Test #'s use in datalog ###
        $chk_order = 0;
        @duplicate_chk = 0;

        for($ii =1; $ii<= 32; $ii++)
        {
		read INPUT, $in, 1;
                $TEST_NUM = unpack "c", $in;

		if($TEST_NUM != 0)
                {
                        #print "$TEST_NUM \n";
                        push (@test_logged, $TEST_NUM);

                        ### Make sure no duplicate test numbers (typo's)
                        $duplicate_chk[$TEST_NUM] = 1;

                        #### Make sure test are in proper order.
                        if($TEST_NUM < $chk_order)
                        {
                                print "Test ordering is incorrect, exiting converter\n";
                                die;
                        }

                        $chk_order = $TEST_NUM;
                }
        }


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
	#print "OLD RUNNAME: $RUNNAME\n";
	($RUNNAME,) = split /\./,$RUNNAME;
	#print "RUNNAME: $RUNNAME\n";

	read INPUT, $in, 7;

	read INPUT, $in, 1;
	read INPUT, $in, 8;
	$TESTNAME = unpack "a8", $in;
	#print "OLD TESTNAME: $TESTNAME\n";
	($TESTNAME,) = split /\./,$TESTNAME;
	#print "TESTNAME: $TESTNAME\n";

	if($TESTNAME eq "" && $RUNNAME eq "")
	{
		print "No TestPlan Specified\n";
		die "No Testplan Specified";
	}

	### If Quad, exit converter and move file to $CONV_BAD/normal_quad
        @checkTNforQuad = ();
        @checkRNforQuad = ();


        @checkTNforQuad = (split //, $TESTNAME);
        @checkRNforQuad = (split //, $RUNNAME);
	

	if (uc $checkTNforQuad[$#checkTNforQuad] ne "S" && uc $checkTNforQuad[$#checkTNforQuad] ne "Z")
	{
		### This file does not use the new testplan naming scheme ###
	#	$TESTNAME = $RUNNAME;
	
		#print "Old naming scheme, testplan name = runname ($RUNNAME)\n";
	}

	else
	{
		#### S or Z is used, set flag so converter knows not to set testname to runname if prn not found ###	
		$quad_flag = 3;	
	}


        	############################
        	# DELETE DATALOG IF FETQUAD
        	############################
        	if ($TESTNAME =~ /[D|E|F|H|I|K]$/i)
        	{
			close(INPUT);
			print "\ndir=bad_file_format";                 ### RETURN BAD SUBDIR FOR MFT
                        &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/bad_file_format") if $mft_flag==0;
                        exit 100;

			#close(INPUT);
                	#system "rm -f $ENV{ENV_CONV_IN}/$file";
			#system "rm -f $ENV{ENV_ARCHIVE}/$file*";
                	#exit 1;
        	}

	### Now that I have the test plan name, get the "GOOD Bins" from the PRN file ###
	parse_prn($TESTNAME,$RUNNAME,  $cLOT, $cPROB);

	$pos1 = index($TESTNAME,"-");
	if ($pos1 == -1)
	{
		#
		# There is no dash extension in the Test Plan Name ($TESTNAME)
		# When there is no dash:
		#	
		#  - Check to see if last chracter is 'Q',
		#      If last char == 'Q', REV = 3rd char from right
		#  
		#      If last char != 'Q', REV = 2nd char from right
		#
		$LastChar = substr($TESTNAME, (length($TESTNAME)-1), 1);
		if ($LastChar eq 'Q')
		{
			#
			# Use the 3rd char from the right for the test plan rev
			#
			$REV = substr($TESTNAME, (length($TESTNAME)-3), 1);

		}
		else
		{
			# 
			# Use the second to the last char for test plan rev (NON Quad)
			#
			$REV = substr($TESTNAME, (length($TESTNAME)-2), 1); 
		}
		#$TestProgRevChar = substr($TESTNAME, (length($TESTNAME)-1), 1);
		$TestProgNameRev = ConvertChars2Int(uc($REV));
		#print "TestProgramRev: $TestProgNameRev\n";
		#print "TESTNAME: $TESTNAME\n";
		$TestProgName = substr($TESTNAME, 0, length($TESTNAME));
		#print "TestProgName: $TestProgName\n";
	}
	else
	{
		($TestProgName, $TestProgNameRev) = split( /-/, $TESTNAME);
		$TestProgNameRev =~ ConvertChars2Int(uc($TestProgNameRev));
	}
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
 

######################################
# RETRIEVE SOURCE LOTID FOR PROD LOTS
######################################
sub GetSourceLotID
{
	### ENGG FILES ###
	if($cLOT=~/^E/i || $cLOT=~/ENG|EON/i)
	{
        	$CebuWorkStreamSINum = $cLOT;
        	$FabDieRunNum        = $cLOT;

		### FOR DEBUGGING ONLY ###
        	#print "engg file -> $cLOT\n";
	}
	### PROD FILES ###
	else
	{
        	$source_lot = &get_complete_lotid($cLOT);
		
		### FOR DEBUGGING ONLY ###
        	#print "prod lot -> $cLOT. source lotid: $source_lot\n";
	}
}


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
        $ret = unpack "f", (pack "cccc", $b[3], $b[2], $b[1], $b[0]) if $mft_flag==0;
        $ret = unpack "f", (pack "cccc", $b[0], $b[1], $b[2], $b[3]) if $mft_flag==1;
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

sub ConvertChars2Int
{
        my ($Char) = @_;

        $Char =~ uc($Char);
        $Int = 0;

        %Vals = ('A',10,  'B',11,  'C',12,  'D',13,  'E',14,  'F',15, 'G',16,  'H',17,  'I',18,  'J',19,  'K',20,
                 'L',21,  'M',22,  'N',23,  'O',24,  'P',25,  'Q',26, 'R',27,  'S',28,  'T',29,  'U',30,  'V',31,
                 'W',32,  'X',33,  'Y',34,  'Z',35);

        @Array=();

        for ($i = 1; $i <= length($Char); $i++)
        {
                $str = substr($Char, ($i-1), 1);
                if ($str =~ /[0-9]/)
                {
                        $Array[$i] = $str;
                }
                else
                {
                        $Array[$i] = $Vals{$str};
                }
        }

        for ($i = 1; $i <= $#Array; $i++)
        {
                $Int = $Int + ($Array[$i]*(36**($#Array - $i)));
        }
        return $Int;
}

sub bcd2int
{
        my ($IN) = @_;
	my @b = unpack  "CCCC", $IN;
        my $sTmp ="";

	#    b3         b2         b1         b0
	#  NU = not used 
	# 0000|0000, 0000|0000, 0000|0000, 0000|0000
	#
	$sTmp = pack "aaaaa", $b[3] & 0x0F, $b[2] >> 4, $b[2] & 0x0F, $b[1] >> 4, $b[1] & 0x0F,$b[0] >> 4, $b[0] & 0x0F;
        my $i = $sTmp * 1;
        return $i;
}

####################
# PARSE PRN ROUTINE
####################
sub parse_prn
{
	 my ($testplan_prn, $runname_prn, $cLOT, $cPROB) = @_;
	 my $testname_flag = 0;


        ############
        # VARIABLES
        ############
        @good_bins_prn       = ();
	my $hbin_num_prn     = "";
	my $error            = 0;
 
	$testplan_prn = uc "$testplan_prn".".PRN";	
	$runname_prn = uc "$runname_prn".".PRN";
	#my $prn_path 	     = "$ENV{ENV_TP_RAW}/$testplan_prn";
	#my $Runprn_path      = "$ENV{ENV_TP_RAW}/$runname_prn";
	my $prn_path        = "$ENV{DPDATA}/data/cpsort_fet/TP/$testplan_prn";
	my $Runprn_path      = "$ENV{DPDATA}/data/cpsort_fet/TP/$runname_prn";

	my @Tmp_file_move = ();
	my $file_move = "";	

	#####################
        # CHECK IF TP EXISTS
        #####################
        if(-e $prn_path)
        {
                $raw_tp = $prn_path;
        }
        elsif(-e $Runprn_path)
        {
                $raw_tp = $Runprn_path;
        }
        else
        {
                $error_msg = "failed to convert $file. Missing testplan is $testplan_prn\n";
                &send_email($error_msg);

                ### PRINT MSG TO LOG FILE ###
                #print "$msg\n";

                ### ADD FILE & MISING TP TO LOG (GET'S E-MAILED DAILY)
		#$tp_log = "$ENV{ENV_LOG}/Missing_testplans.txt";
		$tp_log = "$ENV{DPDATA}/data/cpsort_fet/log/Missing_testplans.txt";
		open (MISSING_TP, ">>$tp_log");
		print MISSING_TP "$file:$testplan_prn\n";
		close(MISSING_TP);

		print "\ndir=missing_testplan";                 ### RETURN BAD SUBDIR FOR MFT
                &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/missing_testplan") if $mft_flag==0;
                exit 100;
        }


	##########
	# READ TP
	##########
	open FH, $raw_tp or die "Can't open testplan $prn_path\n";
	while(<FH>)
        {
                
		### GET AUTHOR
                if ($_=~/COMPILED BY\:/)
                {
                        ($dummy1, $oper) = split /\:/, $_;
                }
                ### IF 1, WILL START COLLECTING TESTPLAN DETAILS
                elsif ($_=~/NO\./)
                {
                        $testname_flag = 1;
                }
                ### GET BIN INFO
                elsif ($_=~/DO ALL/ && $site_flag ne "Q")
                {
                        ### TOGGLE OFF $testname_flag
                        $testname_flag = 0;
                        #====================================================================================
                        #          1         2         3         4         5         6         7         8
                        #012345678901234567890123456789012345678901234567890123456789012345678901234567890
                        #12 POST O/S       BIN=17R   DO ALL?=NO  (OR)  TESTS:   14F 15F 16F
                        #====================================================================================
			$hbin_num_prn = substr $_,22, 4;
                        $hbin_num_prn =~ s/\s+//g;
                        
			### COLLECT GOOD HW BINS
                        if ($hbin_num_prn =~/\b\d{1,2}\b/)
                        {
                                $good_bins_prn[$hbin_num_prn] = $hbin_num_prn; 
                       		#print "Good Bins: $hbin_num_prn\n"; 
			}
                }
        }
	close(FH);
}

#############################
# RENAME FILE IN ARCHIVE DIR
#############################
sub rename_ID
{
	my $origfilename = <$ENV{ENV_ARCHIVE}/$file*>;
	if (-e $origfilename)
	{
		$origfilename =~ s/$ENV{ENV_ARCHIVE}\///;
		my $newfilename = $cLOT."_".$origfilename;
                system "/bin/mv -f $ENV{ENV_ARCHIVE}/$origfilename $ENV{ENV_ARCHIVE}/$newfilename";
                #print "RENAMED $origfilename TO $newfilename\n";
		return $newfilename;
	}
	else
	{
		return $file;
	}
}


########################################
# NOTIFY ENGRS/AIDE OF MISSING TESTPLAN
########################################

#######################################
# QUERY SORTWKS TABLE FOR SOURCE LOTID
#######################################
sub get_complete_lotid
{
        ############
        # VARIABLES
        ############
        my $SYBASE_DATABASE = 'edb_cpsortwks_v22';
        my $SYBASE_SERVER   = 'SYB_PMEWB1';		#<-- USE FOR PRODUCTION 
	#my $SYBASE_SERVER   = 'SYB_CPEWB1'; 		#<-- USE FOR DEBUGGING
        my $SYBASE_USER     = 'EDB_GUEST';
        my $SYBASE_PASSWORD = 'dryheave';
        my $lotid           = shift;


        ################
        # SQL STATEMENT
        ################
        $lookup_sql = "select source_lot from source_lot where lot='${lotid}'\n";
        #print $lookup_sql;

        #####################
        # OPEN DB CONNECTION
        #####################
        $dbh = Sybase::CTlib ->ct_connect($SYBASE_USER, $SYBASE_PASSWORD, $SYBASE_SERVER, "Tracking");


        if (!(defined($dbh)) || length($dbh) == 0)
        {
                die "ERROR using the $SYBASE_DATABASE database, exiting.\n";
        }


        ############################
        # SEARCH FOR MATCHING LOTID
        ############################
        $dbh->ct_sql("use $SYBASE_DATABASE");
        $dbh->ct_execute($lookup_sql);

        while($dbh->ct_results($restype) == CS_SUCCEED)
        {
                if ($restype == CS_CMD_FAIL or $restype == CS_CMD_SUCCEED)
                {
                        next;
                }

                # Skip non-fetchable results:
                next unless $dbh->ct_fetchable($restype);

                # Retrieve actual data rows and store them in a hash keyed on column name:
                while(@row = $dbh->ct_fetch())
                {
                        ### RETURN SOURCE LOTID ###
                        if ($#row >=0)
                        {
                                $row[0] =~ s/\s+//;
                                return $row[0];
                        }
                }
        }

        ### RETURN EMPTY IF NO SOURCELOT ###
        return "";
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


#####################
# EMAIL NOTIFICATION
#####################
sub send_email
{
	my $td_file   = substr($file,rindex($file,"/") + 1);
        my $error_msg = shift;
           $error_msg =~ s/$file/$td_file/;
        my $msg       = MIME::Lite->new
        (
                Subject => "$subject Datalog $file Failed to convert",
                From    => 'dpower@onsemi.com',
                To      => 'yms.admins@onsemi.com',
                Type    => 'text/plain',
                Data    =>  $error_msg
        );
        $msg->send();

}

sub getSeqCamstar {
	my $lot = shift;
	my $seq = "";
	my $url = "http://cpntapp07p.fairchildsemi.com/fscSCCamstarWebService/fscTxnCall.asmx/onsGetProductRecipeParam?lot=$lot&recipeParam=product_setup";
        my $response = LWP::UserAgent->new->get($url);

        if ($response->is_success) {
		my @items = split/<|>/,$response->decoded_content;
		$seq = $items[6];
        }
        else {
                dpExit(1,$response->status_line);
        }

	return $seq;

}
