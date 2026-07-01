#!/usr/bin/perl
#
# DATE     WHO		  COMMENT
# -------- -------------- ---------------------------------------------------------------------
# 12/04/03 Ben Rommel Kho Author
# 06/20/05 Ben Rommel Kho Corrected a bug which limits IGBT test readings to 9 units only
# 06/22/05 Ben Rommel Kho Modified LotID DB search to specify date range based on DL generation
#			  date to reflect correct LotID
# 06/28/05 Ben Rommel Kho Modified to use current date as probed date if date is null 
# 10/27/05 Ben Rommel Kho Modified for regionalization
# 01/31/06 Ben Rommel Kho Modified to trap empty dl - no test readings.
# 10/26/06 Ben Rommel Kho Modified for FET Autorecipe ver 03.00.00.
# 11/15/06 Ben Rommel Kho Modified to output Missing_Testplan.log
# 03/17/07 Ben Rommel Kho Fixed Date Parsing.
# 09/17/08 Ben Rommel Kho Retrieve LotID from Wks only if the reference lotid is >= 7 chars long
# 10/10/08 Ben Rommel Kho Corrected file parsing method.
# 01/29/09 Ben Rommel Kho Changed to move empty data files into $ENV_CONV_BAD/no_data dir.
# 06/04/10 Ben Rommel Kho Fixed bug affecting the PTR generation of multi-segment data.
# 06/05/10 Ben Rommel Kho Reflected the correct env name to the converted file.
# 06/07/10 Gilbert Miole  Excluded GRR or COR files.
# 06/09/10 Gilbert Miole  Excluded file name contains GRR or COR 
# 11/30/10 Ben Rommel Kho Reflect full lotid to archived file
# 01/10/11 Ben Rommel Kho Revised method in reflecting full lotid to archived file(gunzip before renaming)
# 01/11/11 Ben Rommel Kho Improved code that parses operator-encoded date. If invalid, use file modified date. 
# 01/27/11 Ben Rommel Kho Check for full lotid in filename before checking it from Wks.
# 02/02/11 Ben Rommel Kho Reflect PIR count to MRR's part_cnt in case bin summary is not available.
# 03/30/11 Ben Rommel Kho Modified to parse REMARKS data as: <dierun> <fet id> <lotid> <user id> <handler id>
# 04/07/11 Gilbert Miole  Adopted .TD & .TP STDF filenaming convention.
# 05/24/11 Gilbert Miole  To reflect lotid and original filename on the converted file to match with ENV_ARCHIVE & for traceability. 
# 07/23/11 Ben Rommel Kho Fixed bug caused by the prepending of correct lotid to the raw filename 
#			  causing the converted files to remain in the conv_in dir.
# 09/27/11 Ben Rommel Kho Disregard DIERUN from REMARKS field w/ "NONE" value. Prepare to capture DIERUN from
#			  the DATE field. Expected value is either "<DATE>" or "<DATE> <DIERUN>"
#			  Also, fixed file renaming bug to prevent duplicate lotid in filename, and
#			  removed "FT_" from device and product field.
# 			  Fixed bug that removes special chars from dierun.
# 10/06/11 Ben Rommel Kho FET Autorecipe has removed handler from remarks due to lenght issue. 
#			  Modified to make handler info optional. Also, trap/discard dierun="N" - 
#			  a short value for "NONE".
# 06/21/12 Ben Rommel Kho Adjusted for MFT. Moved "reflect_full_lotid_to_filename" routine to dispatcher.
# 06/29/12 Gilbert Miole  Corrected lotid not to include file extension if full lotid not available in remarks.
# 07/11/12 Reuben Capio   Corrected spelling of $mft_flg to $mft_flag.
# 08/31/12 Rodney Cyr     Changed negative exit codes to positive (negative exit codes are not valid in unix).
# 10/30/12 Ben Rommel Kho Changed from CTLib to DBI
# 01/22/12 Ben Rommel Kho Fixed bug affecting "Good Bin" detection. The bug caused incomplete 
#			  MRR rec generation starting at GOOD_CNT field.
# 04/11/13 Jun Garcia     Modified char2float sub routine (reversed the array index).  
# 10/03/13 Jun Garcia     Modified char2short sub routine (reversed the array index).
# 10/03/13 Jun Garcia     Fixed bug in reading serial/unit number in part data .  
# 10/03/13 Jun Garcia     Modified unpacking template parameter used bits from B to b, fixed BIN result issue. 
# 10/03/13 Jun Garcia     Modified to still read part data even if serial number is =  0 and assigns unit_count + 1 as serial number.  
# 10/03/13 Jun Garcia     Added variable to hold actual bytes per unit, check for the difference between serial size vs acutal bytes used in every unit or part data and read out if true.
# 10/03/13 Jun Garcia     Modified to get test number from test plan instead in data log file header because of having test number = 0 even if it has test values.
# 10/07/13 Jun Garcia     Exclude unit num that is equal to zero with zero results for all the test numbers. 
# 07/15/2016 Gilbert Miole Added different TP directory for cprel_fet
# 08/08/2016 Eric Alfanta uncomment loading of sbin & hbin in eprr
#
# Script Function: Convert FET's DAT file to STDF+ format
#
# Version: 01.03.02
#


#################
# LOAD LIBRARIES
#################
use Carp 		;  	# error messages - does not work within stdf_use.pl
use FindBin 		;
use lib "$FindBin::Bin" ; 	# set up path for libraries the same as script
use English 		;
use lib $ENV{'STDF_PERL_LIB'} ; # look for libraries in this directory
# use EDBUtil		;
require "stdf_use.pl" 	;  	# libraries that are not generated
use Getopt::Long        ;
# use DBI			;

#############
# LOAD SPECS
#############
{
        package out ;
        if ( !eval(&::generate_all('stdfPL.spec')))
        {
                confess $@ ;
        }
        require 'stdfPL.pl' ;
}

############
# VARIABLES
############
my $file          = "";
my $plant         = "";     ### MFT ENV VAR
my $env_mod       = "";
my $mft_flag      = ($^O=~/linux/i) ? 1 : 0; 	### SET 0=OTHERS; 1=LINUX/MFT
my $unit_count 	  = 0;
my $seg_count     = 0;
my @store_sb      = ();
my @sbin_summ	  = ();
my @hbin_summ  	  = ();
my @test_numbers  = ();
my @logged_param  = ();
my $good_bin_num  = "";
my $bin_cnt_summ  = "";
my %HOH		  = ();
my $MonthProbed   = "";
my $DayProbed     = "";
my $YearProbed    = "";
my $lotid         = "";	
my $correct_lotid = "";
my $badgeid       = "";
my $td_filename   = "";
my $skip_padded_bytes = 0;
my $dierun        = "";
my $testerno      = "";
my $handler	  = "";
my $tp_dir        = "";

######################
# RETRIEVE PARAMETERS
######################
$result = GetOptions ("infile=s"  => \$file,
		      "plant=s"   => \$plant,
                      "env_mod=s" => \$env_mod);
require $env_mod if $env_mod ne "";               ### LOAD OPTIONAL MODULE



#################
# DISPLAY SYNTAX
#################
if ($file eq "")
{
        print "syntax\n";
        print "\tscript -infile=<datalog file> -plant=<plant(opt)> -env_mod=env_mod.pm(opt)>\n";
        exit 1;
}
###############
# DEFINE TP DIR
###############
if ($plant eq "REL")
{
   $tp_dir = "$ENV{DPDATA}/data/cprel_fet/TP";
}
else
{
   $tp_dir = "$ENV{DPDATA}/data/cpft_fet/TP";
}
#################
# PARSE .DAT FILE 
#################
&parse_datalog();


################
# READ TESTPLAN
################
&parse_prn($TESTNAME);
	
	
################
# GENERATE STDF 
################
&generate_STDF();


########################
# RETURN CONVERTED FILE
########################
print ",$td_filename"       if $mft_flag==0;
print "\ntd=$td_filename"  if $mft_flag==1;


	
exit 0;



#<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< SUBROUTINES >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
###################
# READ .DAT HEADER 
###################
sub parse_datalog()
{

	open(INPUT,"$file") || die "Could not open $file\n";


	###############
        # PARSE HEADER
        ###############

	### DATA FILE 'D' ###
	$ret = read INPUT, $in, 1;
	$data_file = unpack "a", $in;
	#print"DATA_FILE=>$data_file\n";

	### 9400 DATA FILE ###
	read INPUT, $in, 1;
	$version = unpack "a", $in;
	#print"VERSION=>$version\n";

	
	### START SN ###
	read INPUT, $in, 1;
        $sn_bit1 = unpack "b8", $in;
        read INPUT, $in, 1;
        $sn_bit2 = unpack "b8", $in;
        $bit = join "",$sn_bit1,$sn_bit2;
        $start_sn = unpack "s", (pack "b16", $bit);
        #print "STAR SN: $start_sn\n";
	

	### END SN ###
	read INPUT, $in, 1;
        $bit1 = unpack "b8", $in;
	read INPUT, $in, 1;
        $bit2 = unpack "b8", $in;
	$bit = join "",$bit1,$bit2;
	$end_sn = unpack "s", (pack "b16", $bit);
	#print "END SN: $end_sn\n";

	### NUMBER OF SERIAL PER 1536 BYTES ###
	read INPUT, $in, 1;
	$sn_per_rec = unpack "c", $in;
	#print"# of SN / 1536 bytes=>$sn_per_rec\n";

	### NUMBER OF SN's ###
	$SN_cnt = ($end_sn - $start_sn) + 1;

	### SN SIZE ###
	read INPUT, $in, 1;
	$snsize_bit1 = unpack "b8", $in;
	read INPUT, $in, 1;
	$snsize_bit2 = unpack "b8", $in;
	$snsize_bytes = join "", $snsize_bit1, $snsize_bit2;
	$SN_size = unpack "s", (pack "b16", $snsize_bytes);
	#print"SN SIZE=>$SN_size\n";

		### ABORT IF SN SIZE IS ZERO ###
		if ($SN_size < 1)
		{
			print "file doesn't contain test data.\ndir=no_part_data";
                	&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_data") if $mft_flag==0;
                	exit 100;
		}
	
		$die_per_record    = int (1536 / $SN_size);
		$skip_padded_bytes = 1536 - ($die_per_record * $SN_size);
		$to_be_skipped_bytes = 1536 - ($sn_per_rec * $SN_size);
		

		#print "SN SIZE $SN_size\n";
		#print "DIE/REC $die_per_record\n";
		#print "PADDED BYTES: $skip_padded_bytes\n";
		#print "TO BE SKIPPED BYTES: $to_be_skipped_bytes\n";


	### READ OUT TEST #'s USED IN DL ###
        for($ii = 1; $ii <= 32; $ii++)
        {
                read INPUT, $in, 1;
                $TEST_NUM = unpack "c", $in;
		#print"TEST_NUM=>$TEST_NUM\n";
        }

	### READ OUT BYTES IN TEST NUMBERS ###
#        read INPUT, $in, 32;
#        $_cnts = unpack "c32", $in;


	### FCN #'s ###
        read INPUT, $in, 32;
#       $fcn_cnts = unpack "c32", $in;
	#print "FCN #'s: $fcn_cnts\n";


	### DATA FILE REMARKS = DEVICEID & TESTERNO ###
	read INPUT, $in, 1; ### UNWANTED CHAR
	read INPUT, $in, 39;
	$data_rem = unpack "a39", $in;
	$data_rem =~ s/^\s*|\s*$//g;
	$data_rem = uc($data_rem);
	($dierun, $testerno, $correct_lotid, $badgeid, $handler) = split /\s+/, $data_rem;
	$dierun        =~ s/[^A-Z0-9\_\-]//ig;
	$testerno      =~ s/[^0-9\/\-\_]//g;
	$correct_lotid =~ s/[^A-Z0-9\_\-]//g;	
	$badgeid       =~ s/\D//g;
	$handler       =~ s/\D//g;

		#################################################################################
		# NOTE: "REMARKS" SHOULD CONTAIN THE BELOW DATA. OTHERWISE, RESET VARIABLES
		#	<dierun> <fet id> <lotid> <user id> <handler id>
		##################################################################################
		if ($dierun eq "" || $testerno eq "" || $correct_lotid eq "" || $badgeid eq "")
		{
			$dierun        = "";
        		$testerno      = "";
        		$correct_lotid = "";
        		$badgeid       = "";
        		$handler       = "";
		}


		if ($testerno ne "")
		{
			$testerno = "FET-".$testerno;
		}
		else
		{
			$testerno = "FET-0";
		}


	### DATA FILE DATE ###
	read INPUT, $in, 40;
	$data_date  = unpack "A40", $in;
	chomp($data_date);
	my (@dummy) = split /\s+/, $data_date;	### EITHER "<DATE>" OR "<DATE> <PRODUCT>"
	&convert_date($dummy[0]);
	# $dierun     = uc(EDBUtil::cleanString($dummy[1])) if $dummy[1] ne "";
	$dierun     =~ s/NONE|^N$//i;	### TRANSFERRED PRODUCT ID TO DATE FIELD
	#print "remarks: $data_rem\n";
	#print "dierun=$dierun  tester#=$testerno lotid=$correct_lotid badgeid=$badgeid handler=$handler\n";


	### START & END SEGMENT (N/A) ###
	read INPUT, $in, 1;
	@s_seg = split //, (unpack "b8", $in);
	#print"@s_seg\n";
	$start_segment = unpack "c", (pack "b8", (join "", @s_seg));
	#print"START SEGMENT=>$start_segment\n";

	read INPUT, $in, 1;
	@e_seg = split //, (unpack "b8", $in);
	#print"@e_seg\n";
	$end_segment = unpack "c", (pack "b8", (join "", @e_seg));
	#print"END SEGMENT=>$end_segment\n";

	$seg_count = 0;

	for(my $i = $start_segment; $i <= $end_segment; $i++)
	{
		$seg_count = $i;
	}
	#print "seg_count: $seg_count\n";

	#### SKIP RECORDS (NOT NEEDED) ####
	#bytes 156 for DFG1 Flags Bit (0)
	#bytes 157 SCX Binary
	#bytes 158 SCY Binary
	#bytes 159 ECX Binary
	#bytes 160 ECY Binary
	#bytes 161 - 164 Spare
	read INPUT, $in, 9;
	
	
	### READ RUN FILENAME AT CREATION TIME ###
	read INPUT, $in, 15;
	$run_filename = unpack "a", $in;
	#print"Run filename at creation time => $run_filename\n";
	
	
	
	### TEST NAME #####
	read INPUT, $in, 1; 	# <-- REMOVE SPECIAL CHAR 
        read INPUT, $in, 14;
        $TESTNAME = unpack "A14", $in;
        $TESTNAME =~ s/\.TES//;
        $TESTNAME =~ s/[^a-zA-Z0-9\_]*//g; 
	#print "TEST NAME : $TESTNAME\n";


		### UNLINK IF TEST NAME CONTAINS GRR OR COR ###
                if ($TESTNAME =~/GRR/i || $TESTNAME=~/COR/i)
                {
                        #print "Invalid data(GRR/COR) file\n";
                        exit 1;
                }

	### LOT SUMM: GET HBIN COUNT ###
	for($i=1; $i<26; $i++)
	{
		$result = "";
		for($j=1;$j<=4;$j++)
		{
			read INPUT, $in, 1;
			$dummy1 = unpack "H", ${in};
			$dummy2 = unpack "h", ${in};
			$result = ${dummy1}.${dummy2}.${result};
		}
		$hbin_summ[$i] = int ${result};
		#print "hbin $i $hbin_summ[$i]\n";

		### REMOVE UNWANTED INFO ###
		read INPUT, $in, 1;
	}
	
	### LOT SUMM: GET SBIN COUNT ### 
	for($i=1;$i<26;$i++)
        {
                $result = "";
                for($j=1; $j<=4; $j++)
                {
                        read INPUT, $in, 1;
                        $dummy1 = unpack "H", ${in};
                        $dummy2 = unpack "h", ${in};
                        $result = ${dummy1}.${dummy2}.${result};
                }
		$sbin_summ[$i] = int $result;
		#print "sbin $i $sbin_summ[$i]\n";
        }
	
	### LOT SUMM: TOTAL COUNT ###
	$result = "";
        for($j=1; $j<=4; $j++)
        {
                read INPUT, $in, 1;
                $dummy1 = unpack "H", ${in};
                $dummy2 = unpack "h", ${in};
                $result = ${dummy1}.${dummy2}.${result};
        }
	$bin_cnt_summ = int $result;
	#print "bin_cnt $bin_cnt_summ \n";


	### RESERVED SPACE ###
        read INPUT, $in, 1113;

	########################################
        # GET TEST DL TEST NUMBER FROM TEST PLAN
        ########################################
	
	@test_numbers = &get_test_number_in_testplan($TESTNAME);
	#print"test_numbers=>@test_numbers\n";

	### TEST COUNT ###
        $test_cnt = $#test_numbers + 1;
	#print "TEST CNT $test_cnt\n";	

	######################
	# PARSE TEST READINGS
	######################
	
	### INITIALIZE SERIAL COUNTER TO ZERO ###
	my $SN_counter = 0;

	### COMPUTE TOTAL ACTUAL BYTES USED PER SERIAL ###
	my $bytes_per_serial = ($test_cnt * $seg_count * 5) + 3;
	#print"Bytes per serial => $bytes_per_serial\n";

	### GET THE DIFFERENCE BETWEEN SERIAL SIZE AND ACTUAL BYTES USED PER SERIAL ###
	my $difference_SN_size_bytes_per_serial = $SN_size - $bytes_per_serial;

	### CHECK IF DIFFERENCE BETWEEN SERIAL SIZE AND ACTUAL BYTES USED PER SERIAL IS GREATER THAN ZERO ###
	### ASSIGNS 1 FOR TRUE IF GREATER | 0 FOR FALSE ###
	my $diff_greater_zero = $difference_SN_size_bytes_per_serial > 0 ? 1 : 0;
	#print"diff_greater_zero=> $diff_greater_zero\n";

	my $unit_num_flag = 0;
        my $test_data_flag = 0;

	### LOOP THROUGH EACH SERIAL/UNIT AND GET/READ DATA ###
	for($unit = 1; $unit <= $SN_cnt; $unit++)
	{
		$unit_num_flag = 0;
		$test_data_flag = 0;
	
		### GET SERIAL NUMBER|UNIT NUMBER ###
		### USED b for unpacking for bits to be left to righ order ###
                read INPUT, $in, 1;
                my $byte1    = unpack "b8", $in;
                read INPUT, $in, 1;
                my $byte2    = unpack "b8", $in;
                my $unit_num = join "", $byte1, $byte2;
                   $unit_num = unpack "s", (pack "b16", $unit_num);
		#print "unit_num: $unit_num\n";

		### COUNT SERIAL NUMBER READ ###
                $SN_counter++;

		### CHECK IF SERIAL NUMBER IS EQUAL TO ZERO ###
		### ASSGNS $unit_count + 1 FOR SERIAL NUMBER ###
		if($unit_num == 0)# && $sn_per_rec == $SN_counter)
		{
			$unit_num_flag = 1;
			$unit_num = $unit_count + 1;
			#print"orig unit_num is zero\n";
		}

		### GET BIN RESULT BITS ###
		read INPUT, $in, 1;
		my @bin        = split //, (unpack "b8", $in);
                my $bin_result = unpack "c", (pack "b7", (join "", @bin));
                #print "unit_num: $unit_num\tbin_result: $bin_result\n";
		
		### LOOP THRU EACH TEST ###
		my @TEST_RESULT = ();
		my $counter = 0;
		foreach $test_number(@test_numbers)
		{
			### LOOP THRU EACH SEGMENT ###
			for(my $segment = 1; $segment <= $seg_count; $segment++)
			{
				### FLAG TEST ###
				read INPUT, $in, 1;
				@test_flag_bits = split //, (unpack "b8", $in);
				#print"@test_flag_bits\n";
				$pass_fail_bit = $test_flag_bits[3];
	                	#print "pass_fail_bit=$pass_fail_bit\t";

				### GET RESULT ###
				read INPUT, $in, 4;
				$result = char2float($in);
	                	#print "test $test_number - segment $segment - result: $result\n";
					
				### SAVE SEGMENT TEST RESULT ###
                                $TEST_RESULT[$segment][$test_number] = $result;
				if($TEST_RESULT[$segment][$test_number] == 0 || $TEST_RESULT[$segment][$test_number] eq "")
                        	{
                                	$counter = $counter + 1;
                        	}

			}
		}

		#print"COUNTER=$counter\n";
		
                if($counter  == $#TEST_RESULT)
                {
                        $test_data_flag = 1;
			$counter = 0;
                }

		### CHECK IF DIFFERENCE OF SN SIZE VS ACTUAL BYTES USED PER SERIAL IS GREATER THAN 0 ###
		### IF TRUE READ OUT DIFFERENCE ###
		if($diff_greater_zero)
		{			 
			read INPUT, $in, $difference_SN_size_bytes_per_serial;
			#print "BYTE_COUNT_INSIDE_CHECKER=>$difference_SN_size_bytes_per_serial\n";
		}

		### SAVE UNIT TEST RESULT ###
		if($unit_num_flag != 1 && $test_data_flag != 1)
                {

	                $HOH{$unit_num} =
        	        {
                	        ARRY_ADD => \@TEST_RESULT,
                        	HBIN     => $bin_result
                	};
		}

                ### DET SAMPLE SIZE ###
		### SERIAL NUMBER READ COUNTER
		$unit_count++;
                #print "die_per_record=$die_per_record vs SN_counter=$SN_counter\n";
		
		### SKIP PADDED BYTES / die per record IF TRUE###
		if($die_per_record == $SN_counter)
		{
			read INPUT, $in, $skip_padded_bytes;
			$SN_counter = 0;
		}
	}

        close(INPUT);

	
	##############################
	# TRAP FILE W/ NO TEST READINGS
	################################
        if ($unit_count == 0)
 
       {
		print "data file doesn't contain test data.\ndir=no_part_data";
                &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_data") if $mft_flag==0;
                exit 100;
        }

}

####################################
# GET TEST NUMBER IN TEST PLAN
####################################
sub get_test_number_in_testplan
{
	### VARIABLES ###
        my ($testname) = @_;
        my $testplan  = uc("$testname").".PRN";
	my $tp_file   = "${tp_dir}/$testplan";
	#my $tp_file   = "$ENV{ENV_TP_RAW}/$testplan";
	#my $tp_file   = "/data/edbmgr/code/site/edbcp/scripts/cpft_fet/$testplan";
	my @test_numbers = ();
	my @test_numbers2 = ();
	my $flag = 0;


	### CHECK IF TESTPLAN EXISTS ###
	if (! -e $tp_file)
	{

		#####################################################
                # ADD FILE & MISING TP TO LOG (GET'S E-MAILED DAILY)
                #####################################################
                $tp_log = "$ENV{ENV_LOG}/Missing_testplans.txt";
                open (MISSING_TP, ">>$tp_log");
                print MISSING_TP "$file:$testplan\n";
                close(MISSING_TP);
	
		print "Missing testplan $testname.\ndir=missing_testplan";
                &move_file_to_bad_dir($file, "$ENV{ENV_TP_NOCONV}") if $mft_flag==0;
		exit 100;
	}
	 
	###############
	# OPEN TP FILE
	###############
	open FH, $tp_file or die "Can't open $tp_file file\n";

	############
	# PARSE PRN
	############
        while(<FH>)
        {
		if($_ =~ /DL\s+DATA\sLOG\s+ DO ALL\?\=/)
		{
			$flag = 1;
			$line = $_;
			#print"LINE=>$line\n"; 
			chomp($line);
			#print"LINE=>$line\n";
			$line =~ s/^\s+|\s+$//;
			$line = substr($line, 52);
			chomp($line);
			$line =~ s/^\s+|\s+$//;
  			#print"LINE=>$line\n";
			$line =~ s/\D / /g;
  			#print"LINE=>$line\n";
			@test_numbers = split /\s+/, $line;
  			#print"=>@test_numbers\n";
		}
		if(($_ =~ /\s{54,}/) && ($flag == 1))
                {
                        #print"IM HERE2\n";
                        $line = $_;
			chomp($line);
			$line =~ s/^\s+|\s+$//;
			$line =~ s/\D / /g;
			#print"LINE=>$line\n"; 

                        @test_numbers2 = split /\s+/, $line;
                        #print"=>@test_numbers2\n";
                }

	}
	close(FH);
		
	for(my $i = 0; $i <= $#test_numbers2; $i++)
	{
		push(@test_numbers, $test_numbers2[$i]);
	}

	return(@test_numbers);
}

####################
# PARSE PRN ROUTINE
####################
sub parse_prn
{
        ### VARIABLES ###
        my ($testname) = @_;
        my $testplan  = uc("$testname").".PRN";
	my $tp_file   = "${tp_dir}/$testplan";
	#my $tp_file   = "$ENV{ENV_TP_RAW}/$testplan";
	#my $tp_file   = "/data/edbmgr/scratch/jgarcia/dev_fet/cpft_fet/test2/$testplan";


	### CHECK IF TESTPLAN EXISTS ###
	if (! -e $tp_file)
	{

		#####################################################
                # ADD FILE & MISING TP TO LOG (GET'S E-MAILED DAILY)
                #####################################################
                $tp_log = "$ENV{ENV_LOG}/Missing_testplans.txt";
                open (MISSING_TP, ">>$tp_log");
                print MISSING_TP "$file:$testplan\n";
                close(MISSING_TP);
	
		print "Missing testplan $testname.\ndir=missing_testplan";
                &move_file_to_bad_dir($file, "$ENV{ENV_TP_NOCONV}") if $mft_flag==0;
		exit 100;
	}
	 
	###############
	# OPEN TP FILE
	###############
	open FH, $tp_file or die "Can't open $tp_file file\n";

	############
	# PARSE PRN
	############
        while(<FH>)
        {
		#########################
                # GET ALTERNATE SEGMENTS
		#########################
                if($_=~/ALTERNATE SEGMENTS/)
                {
                        ($trash,$SEG_MODE) = (split /=/, $_);
                        #print "SEGMENT MODE: $SEG_MODE\n";
                }
		######################## 
		# GET LOGGED PARAMETERS
		########################
		elsif ($_=~/25 DL\s+DATA LOG/)
		{	
			chomp($line1 = substr($_,52));
			$_ = <FH>;
			chomp($line2 = substr($_,52));
			$line1 =~ s/^\s+|\s+$//;	#<-- REMOVE LEADING/TRAILING SPACES
			$line2 =~ s/^\s+|\s+$//;
			$line1 =~ s/\D / /g;		#<-- REMOVE NON-NUMERIC SUFFIXES
		 	$line2 =~ s/\D / /g;
			(@logged_param) = split /\s+/, $line1." ".$line2;  			
			#print "logged param: @logged_param\n";	
			last;	
		}
		###############
		# GET BIN INFO
		###############
                elsif ($_=~/DO ALL\?\=/)
                {
			chomp($line=$_);
                        #====================================================================================
                        #          1         2         3         4         5         6         7         8
                        #012345678901234567890123456789012345678901234567890123456789012345678901234567890
                        #12 POST O/S       BIN=17R   DO ALL?=NO  (OR)  TESTS:   14F 15F 16F
                        #====================================================================================
                        $sbin_num = substr $line, 0, 3;
                        $sbin_name= substr $line, 3,15;
                        $hbin_num = substr $line,22, 4;
			$test_nums= substr $_,52;

                        $sbin_num =~ s/\s+//g;
                        $sbin_name=~ s/\s+$//;
                        $sbin_name=~ s/\W//g;           ### REMOVE NON-ALPHANUMERIC CHARS
                        $hbin_num =~ s/\s+//g;
			@test_nums= split /\s+/, $test_nums;
			next if $hbin_num !~ /^\d{1,2}/;

                        ### REMOVE 'R' FROM  REJECT HW BIN NUMBERS
			if ($hbin_num =~ /R/)
			{
                        	$hbin_num =~ s/R//;
			}
			### DET GOOD HBIN ###
			else
			{
				$good_bin_num = $hbin_num;
				#print "good bin: $good_bin_num\n";
			}

			### STORE SBIN EQUIV FOR EACH HBIN ###	
			$store_sb[$hbin_num] = $sbin_num;	
		} 
	}
        close(FH);



        #####################
        # GET COMPLETE LOTID
        #####################
        my (@dummy) = split /\//, $file;
        ($lotid)    = split /_/,$dummy[$#dummy] if $dummy[$#dummy] =~ /\_/;
        ($lotid)    = split /\./,$dummy[$#dummy] if $dummy[$#dummy] !~ /\_/;
        $lotid      = uc $lotid;
        #print "old lotid: $lotid\n";

        ### QUERY WKS FOR COMPLETE LOTID IF NOT AVAILABLE IN COMMENT FIELD ###
	if ($lotid eq "")
        {
                print "Missing lotid. Aborting script\ndir=no_lotid";
                exit 100;
        }
        # elsif ($correct_lotid eq "" && (length($lotid) >= 7 && length($lotid) < 10))
        # {
        #         $ret_value     = &get_complete_lotid($lotid);
        #         $correct_lotid = $ret_value if $ret_value ne "";
        # }
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
        system "mv $file $loc_dir";
        if (! -e "${loc_dir}/${fn}")
        {
                print "Failed to move $loc_file to $loc_dir dir. $!\n";
                exit 1;
        }
}

###########################
# CHAR TO FLOAT CONVERSION
###########################
sub char2float
{
        my ($IN) = @_;
        @b = unpack "c" x 4, $IN;
	$ret = unpack "f", (pack "cccc", $b[0], $b[1], $b[2], $b[3]);
        #$ret = unpack "f", (pack "cccc", $b[3], $b[2], $b[1], $b[0]);
        return $ret;
}


################
# GENERATE STDF 
################
sub generate_STDF
{
	$PSUM_CNT   = 0;
	$PRES_CNT   = 0;
	@pir_chk    = ();
	@eprr_chk   = ();
	$first_time = 0;

	### OPEN A FILE FOR WRITING ###
	$td_filename  = "${file}.TD";
	open OUTPUT, ">$td_filename" or die "can't create an stdf file $td_filename. $!\n";

	##############
	# EMIR RECORD 
	##############
	%out::emir 	     	= %{$out::init{emir}};
        $out::emir{setup_t}  	= stdf_time();
        $out::emir{start_t}  	= $Start_time;
	$out::emir{mode_cod} 	= "P";
        $out::emir{spec_nam} 	= "FT_".$TESTNAME;
        $out::emir{spec_rev} 	= 0;
	$out::emir{spec_rev}    = pad($out::emir{spec_rev},"\0");
	$out::emir{device}	= $TESTNAME;
	$out::emir{part_typ} 	= $TESTNAME;
        $out::emir{lot_id}   	= ($correct_lotid ne "") ? $correct_lotid : $lotid;
	$out::emir{ssum_cnt} 	= 1;
	$out::emir{psum_cnt} 	= $unit_count;
	$out::emir{pres_cnt} 	= $unit_count * $seg_count * $test_cnt;	
        $out::emir{tstr_typ} 	= $testerno if $testerno ne "";
	$out::emir{hand_id}     = $handler  if $handler  ne "";
	$out::emir{oper_nam} 	= $badgeid  if $badgeid  ne "";
	$out::emir{facility} 	= $plant    if $plant    ne "";
        print OUTPUT &out::pack_EMIR(\%out::emir);

	if ($dierun ne "")
	{
		%out::ltr         = %{$out::init{ltr}};
                $out::ltr{lot_id} = $dierun;
                print OUTPUT &out::pack_LTR(\%out::ltr);
	}

	### LOOP THRU EACH UNIT ###	
	foreach $unit_no(sort {$a <=> $b} keys %HOH)
        {
		$arry = $HOH{$unit_no}{ARRY_ADD};
                $hbin = $HOH{$unit_no}{HBIN};


		#############
                # PIR RECORD
                #############
                %out::pir          = %{$out::init{pir}};        
                $out::pir{part_id} = $unit_no; 			#$part_id_cnt++;       
                print OUTPUT &out::pack_PIR(\%out::pir) ;   

		### LOOP THRU EACH TEST ###
		foreach my $test_num(@test_numbers)
                {
			### LOOP THRU EACH SEGMENT ###
			if ($seg_count > 1)
			{
				################################
				# PTR RECORD FOR MULTLE SEGMENT
				################################
                		for(my $seg=1; $seg<=$seg_count; $seg++)
                		{
					%out::ptr 	    = %{$out::init{ptr}};
                			$out::ptr{test_num} = $test_num.$seg;
                			$out::ptr{test_flg} = 01000000;
                			$out::ptr{result}   = $$arry[$seg][$test_num];
                			print OUTPUT &out::pack_PTR(\%out::ptr) ;	
                        	}
			}
			else
			{
				################################
                                # PTR RECORD FOR SINGLE SEGMENT
                                ################################
                                %out::ptr           = %{$out::init{ptr}};
                                $out::ptr{test_num} = $test_num;
                                $out::ptr{test_flg} = 01000000;
                                $out::ptr{result}   = $$arry[1][$test_num];
                                print OUTPUT &out::pack_PTR(\%out::ptr) ;
			}
		}	
		
		##############
		# EPRR RECORD
		##############
		%out::eprr           = %{$out::init{eprr}};
                $out::eprr{part_id}  = $unit_no; 		#$part_id_cnt;
                $out::eprr{num_test} = $test_cnt;
                $out::eprr{hard_bin} = $hbin if $hbin ne "";
                $out::eprr{soft_bin} = $store_sb[$hbin] if $store_sb[$hbin] ne "";
                print OUTPUT &out::pack_EPRR(\%out::eprr);
               
        }


	### BIN INFO ### 
	for ($i=1; $i<=24; $i++)
        {
		##############
		# HBIN RECORD
		##############
		%out::hbr 	    = %{$out::init{hbr}};
               	$out::hbr{hbin_num} = $i;
		$out::hbr{hbin_cnt} = $hbin_summ[$i];
               	print OUTPUT &out::pack_HBR(\%out::hbr);
		
		##############
		# SBIN RECORD
		##############
		%out::sbr 	    = %{$out::init{sbr}};
                $out::sbr{sbin_num} = $i;
                $out::sbr{sbin_cnt} = $sbin_summ[$i];
                print OUTPUT &out::pack_SBR(\%out::sbr);
	}
	
	#############
	# MRR RECORD
	#############
	%out::mrr           = %{$out::init{mrr}};
        $out::mrr{part_cnt} = $bin_cnt_summ||keys %HOH;
	$out::mrr{good_cnt} = $hbin_summ[${good_bin_num}] if exists $hbin_summ[${good_bin_num}];
        $out::mrr{finish_t} = $Start_time;
        print OUTPUT &out::pack_MRR(\%out::mrr);
	close(OUTPUT);
}



#########################
# CONVERT .DAT FILE DATE
#########################
sub convert_date
{
	### 1) ATTEMPT TO USE PS ENCODED DATE ###
	($MonthProbed, $DayProbed, $YearProbed) = split /\//, shift;
	$MonthProbed  =~ s/\D//g;
	$DayProbed    =~ s/\D//g;
	$YearProbed   =~ s/\D//g;
	$YearProbed  += 1900 if length($YearProbed)==2 && $YearProbed > 80;
	$YearProbed  += 2000 if length($YearProbed)==2 && $YearProbed < 80;
	#print "DL DATE $data_date -> $MonthProbed $DayProbed $YearProbed\n";
	
	### 2) IF INVALID, USE FILE MODIFIED DATE INSTEAD ###
	if ($YearProbed < 1990 || $YearProbed > 3000 || $DayProbed < 1 || $DayProbed > 31 || $MonthProbed < 0 || $MonthProbed > 12)
	{
		($sec,$min,$hour,$DayProbed,$MonthProbed,$YearProbed,$wday,$yday,$isdst) = gmtime((stat($file))[9]);
		$MonthProbed += 1;
		$YearProbed  += 1900;
	}
	
	$Start_time = timegm(00, 00, 12, $DayProbed, $MonthProbed - 1, $YearProbed);
	#print "Converted Date: $Start_time - $MonthProbed\/$DayProbed\/$YearProbed\n";
}


sub char2short
{
        my ($IN) = @_;
        my @b    = unpack  "c" x 2, $IN;
        #my $ret  = unpack "S", (pack "cc", $b[1], $b[0]);
        my $ret  = unpack "S", (pack "cc", $b[0], $b[1]);
        return $ret;
}


#########################################
# QUERY FTSTWKS TABLE FOR COMPLETE LOTID
#########################################
sub get_complete_lotid
{
        ############
        # VARIABLES
        ############
        my $lotid     = shift;
	   $lotid     = substr($lotid, length($lotid) - 6); ### GET THE LAST 6 CHARS
	my $new_lotid = "";
        my $db        = "edb_cpast_wks";
        my $host      = "ewb-syb-ap";
        my $uid       = $ENV{EDB_USERNAME};
        my $pwd       = $ENV{EDB_PASSWORD};


	###############
	# QUERY WKS DB
        ###############
#       	my $dsn = "DBI:Sybase:database=${db};host=${host};port=2025";
#        my $dbh = DBI->connect($dsn, $uid, $pwd ) or die $DBI::errstr;
#	my $sql = "select lot from lot where lot like \"%$lotid\" order by lot";
#	my $sth = $dbh->prepare($sql);
#           $sth->execute() or die $DBI::errstr;
#        my @row = $sth->fetchrow_array();
#	if ($#row > -1)
#	{
#		$new_lotid = $row[0];
#        } 
#	$sth->finish();
	
#	return($new_lotid);
}




################
# WRITE TO FILE
################
sub write_to_file()
{
	($filename, $msg) = @_;
	open FH, ">${filename}" or die "failed to log no wksid msg in $filename file\n";
	print FH "$msg";
	close FH;
}
