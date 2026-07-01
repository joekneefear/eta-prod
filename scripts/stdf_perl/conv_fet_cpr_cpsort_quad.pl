#! /usr/bin/perl
#
#
# DATE	     WHO	    COMMENTS
# ---------- -------------- -------------------------------------------------------
# 12/17/2008 Ben Rommel Kho Author. 
# 02/01/2008 Ben Rommel Kho Modified for duals
# 02/27/2009 Ben Rommel Kho Read all test data for Wafermap 2
# 03/11/2009 Ben Rommel Kho Generate PIR & EPRR only on Grid, Fail Die or Wafer2.
# 03/16/2009 Ben Rommel Kho Sometimes, the seq name in CPR is short. Modified to check for 
#			    full seq filename.
# 03/17/2009 Ben Rommel Kho Fixed date bug. Obtain seq filename from map file and not cpr.
# 04/13/2009 Ben Rommel Kho Modified to look for maps in /archived dir
# 04/24/2009 Ben Rommel Kho Fixed yield issue and modified to strictly mark all non-grid dies
#			    as such regardless of it has passed/failed.
# 05/15/2009 Ben Rommel Kho Skip tests 81 and up.
# 06/03/2009 Ben Rommel Kho Log all if lotid starts w/ "E" (Engg Lot)
# 06/04/2009 Ben Rommel Kho Trap/delete file w/ no data.
# 08/28/2009 Ben Rommel Kho Allow full datalog conversion.
# 11/26/2009 Ben Rommel Kho Added probe pattern 214 (2x2).
# 12/09/2009 Ben Rommel Kho Adjusted to handle new seprobe format(not to read [EXT WAFERMAP])
# 02/02/2010 Ben Rommel Kho Fixed code the retrieves CPR's map-counterpart file.
# 02/12/2010 Ben Rommel Kho Improved map search
# 03/03/2010 Ben Rommel Kho Use the wafer number from the CPR filename if the parsed value is invalid
# 03/22/2010 Ben Rommel Kho Fixed bug affecting Quad vs Dual file detection. Quad seq name starts w/ "Q" while
# 			    "D" for Dual. 
#		            Modified to deteremine test count per site. Supposedly, the count should be the same
#			    for all sites. If there's a difference, notify sort engr.
# 05/27/2010 Ben Rommel Kho Use Find::File module to lessen CPU utilizaton and improve conversion time
#			    Utilized the file dispatched year instead of relying to the year info within the CPR.
# 06/28/2010 Ben Rommel Kho Modified map file search criteria to fix bug and limit searching to CPFETQUAD map files only.
# 07/05/2010 Ben Rommel Kho Assigned correct and unique part id to each tested die.
# 07/07/2010 Gilbert Miole  Force uppercase of test plan name.
# 08/26/2010 Ben Rommel Kho Use the old SEQ files for CPR loaded prior Aug 26, 2010. The new SEQ files have  
#			    diff XY coordinates and will misalign the data if used w/ old CPR files. 
# 10/06/2010 Ben Rommel Kho Removed "CPFETQUAD" map search criteria
# 10/15/2010 Ben Rommel Kho Fixed map search bug to ensure it is picking the correct waferid
# 11/05/2010 Gilbert Miole  Assigned a zero value if node_num is null.
# 11/17/2010 Gilbert Miole  Skip load_board and probe_card during creation of EMIR if values are null.
# 11/23/2010 Gilbert Miole  Skip load_board and probe_card during creation of EMIR if values are null for wafer map.
# 04/06/2011 Gilbert Miole  Adopted .TD & .TP STDF filenaming convention.
# 06/06/2011 Ben Rommel Kho Capture ProberID to EMIR's NODE_NAM field.
# 10/21/2011 Ben Rommel Kho Modified to scan/use map file with "SYSTEM ID Proberxx" info as per Warren.
# 07/16/2012 Gilbert Miole  Made MFT compatible.
# 08/11/2012 Gilbert Miole  Change translation of char2short, char2int, char2float for Linux.
# 08/31/2012 Rodney Cyr     Changed negative exit codes to positive (negative exit codes are not valid in unix).
# 09/27/2012 Ben Rommel Kho Convert distance into integer
# 10/15/2012 Gilbert Miole  Changed the look up path of sequence file, from ENV_CONV/seq to ENV_TP_RAW.
# 10/17/2012 Gilbert Miole  Reflect correct ENV_NAME in wm_filename.
# 10/18/2012 Gilbert Miole  Changed MFT tagging, wm=.WM to td=.WM
# 10/24/2012 Gilbert Miole  Changed the MAP file to search from .+\.MAP to .+\.MAP.+
# 11/28/2012 Reuben Capio   Temporarily commented out email functionality to avoid errors in MFT. Still finding fix. 
# 08/30/2013 Rodney Cyr     Use Gross Probes instead of Probed Dice from SE-Probe map data.
# 09/23/2013 Rodney Cyr     Fixed invalid Bin0 check when Gross Probes is not in the file.
# 10/23/2013 Rodney Cyr     Added unprobed die to part count and good die in the Wafermap.
# 05/13/2014 Gilbert Miole  Enable back email notification on failure event.
# 05/15/2014 Gilbert Miole  Removed file path in error message.
# 06/09/2014 Gilbert Miole  Removed file path in subject error message.
# 08/28/2104 Eric Alfanta   Removed $mft_flag==0 so that log file for no_seq_file can be written.
# 10/02/2014 Eric Alfanta   Changed lot type from P to blank
# 10/23/2014 Eric Alfanta   Turned off the grid sampling & turne on the grid sampling options in the summarizer.
# 05/17/2015 Rodney Cyr     Disabled searching all years in archive for wmap - performance is very bad causing backup.
# 06/06/2019 Eric Alfanta   Change email add domain to onsemi
# 11/14/2019 Glory Llego    Commented out statement to send email regarding test issue.
# 23/Apr/2021 jgarcia       modified to send email again.
# 23/Apr/2021 jgarcia       modified to support colo server. replace hardcoded TP and reference file folder location.
# 
#
# FUNCTION: Converts Cebu's FETQUAD CPR file into STDF+
# 
#
#


#################
# LOAD LIBRARIES
#################
use Carp                      ; # error messages - does not work within stdf_use.pl
use FindBin                   ;
use English                   ;
use lib "$FindBin::Bin"       ; # set up path for libraries the same as script
use lib $ENV{'STDF_PERL_LIB'} ; # look for libraries in this directory
require "stdf_use.pl"         ; # libraries that are not generated
use File::Find    	      ;
use Getopt::Long              ;
#use EDBUtil                   ;
use File::Basename	      ;
use MIME::Lite                ;
use IPC::Open3;
use File::Copy;

######################
# LOAD SPECIFICATIONS
######################
{
        package out ;
        if ( !eval(&::generate_all('stdfPL.spec')))
        { confess $@ ; }
        require 'stdfPL.pl' ;
}


###################
# GLOBAL VARIABLES
###################
our $file       = "";
my $lotid       = "";
my %td		= ();
my %sbin	= ();
my %seq		= ();
my %param       = ();
my %alt_param   = ();
my $td_filename = "";
my $wm_filename = "";
my $tp_filename = "";
my $tp_name     = "";
my $tp_rev      = 0;
my $seq_file    = "";
my $operator    = "";
my $prober      = "";
my $test_time   = "";
my $snnum       = 0;
my $snsize      = 0;
my $waferno     = 0;
my %map		= ();
my $map_data    = ();
my $xsize       = 0;
my $ysize       = 0;
my $units       = "";
my $rows        = 0;
my $cols        = 0;
my $flat        = 0;
my $wafer_size  = 0;
my $node_nam    = "";
my $node_num    = 0;
my $prober_id   = "";
my $probe_card  = "";
my $load_board  = "";
my $probed_dice = "";
my $unprobed_dice = 0;
my $bad_dice    = 0;
my $good_dice   = 0;
my $gross_probes = 0;
my $xref        = "";
my $yref        = "";
my %map_bin_summ = ();
my $min_x        = "";
my $max_x	 = "";
my $min_y	 = "";
my $max_y	 = "";
my $param_cnt_per_site = 0;
my $extra_readings     = 0;
#my $sbin_ref_file      = "$ENV{ENV_CONV_SCRIPT}/fet_sbin_ref.txt";
my $sbin_ref_file      = "$ENV{DPDATA}/data/cpsort_fet_quad/TP/fet_sbin_ref.txt";
my $site_count   = 4;
my $plant        = uc($ENV{ENV_FACILITY});     #<-- MFT ENV VAR
my $mft_flag     = ($^O=~/linux/i) ? 1 : 0;    #<-- SET 0=OTHERS; 1=LINUX
my $envname      = uc($ENV{ENV_NAME});         #<-- GET ENV NAME
my %month         = (1=>"Jan", 2=>"Feb", 3=>"Mar", 4=>"Apr", 5=>"May", 6=>"Jun", 7=>"Jul", 8=>"Aug", 9=>"Sep", 10=>"Oct", 11=>"Nov", 12=>"Dec");

my $DateTime   = `date '+%m%d%y%H%M%S'`;
chomp($DateTime);


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


################
# PARSE DATALOG
################
&pre_parse_module()    if $env_mod ne "";
&parse_datalog();
&form_bin_map();


	#######################################
	# DISPLAY PARSE VALUES (FOR DEBUGGING)
	#######################################
	&display_parsed_values();



############################
# CREATE DATALOG & WAFERMAP
############################
&create_td;
&create_map;


########################
# RETURN CONVERTED FILE
########################
print "$td_filename,$wm_filename"          if $mft_flag==0;
print "\ntd=$td_filename td=$wm_filename"  if $mft_flag==1;

exit 0;


#<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< SUBROUTINES >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
################
# PARSE DATALOG
################
sub parse_datalog
{
	##################
	# LOCAL VARIABLES
	##################
	my $in = "";

	#############
	# PARSE FILE
	#############
	open INPUT, $file or die "can't open $file\n";

	### FILE TYPE. ALWAYS "P" FOR "CPR" ###
	read INPUT, $in, 1;
        my $CPR = unpack "a", $in;
	   $CPR = uc($CPR);
		
		### VALIDATE CPR FILE ###
		if ($CPR ne "P")
		{
			print "$file is not a valid CPR file\n";
			exit 1;
		}

	###################
	# PARSE CPR HEADER
	###################
        read INPUT, $in, 1;
        #$CNUM = unpack "a", $in;

	### NUMWAF ###
        read INPUT, $in, 2;
	#$wafer_cnt = unpack "c" x 2, $in;
	#print "NUMWAF = $wafer_cnt\n";

	### CNAME ###
        read INPUT, $in, 40;
	#$CNAME = unpack "A40", $in;
	#print "CNAME = $CNAME\n";

	### CDATE ###
        read INPUT, $in, 40;
        my $CDATE = unpack "a40", $in;
           $CDATE =~ s/^[^0-9]+|[^0-9]+$//g;
	#print "CDATE = $CDATE\n";
	

		### CONVERT TIME TO UNIX ###
		my ($mm,$dd,$yy,$hr,$min,$sec) = split /\/|\s|\.|\\|\-|\:/,$CDATE;
		if ($mm ne "" && $dd ne "" && $yy ne "" && $hr ne "")
		{
			$min = 0 if $min eq "";
			$sec = 0 if $sec eq "";
                	$test_time = timegm($sec, $min, $hr, $dd, $mm - 1, $yy);
		}
		#print "Date=$mm\/$dd\/$yy $hr\:$min\:$sec\ttimegm=$test_time\n";
		#print "test_time=$test_time\n";


	### CLINE (HOLDS SEQ FILENAME. GET SEQ INFO FROM MAP SINCE IT'S MORE RELIABLE) ###
        read INPUT, $in, 16;
        #$seq_file = unpack "a16", $in;
	#$seq_file =~ s/^[^0-9A-Z]+|[^0-9A-Z]+$//ig;
	#print "CLINE = $seq_file\n";


	### COPER ###
        read INPUT, $in, 40;
        #$operator = unpack "A40", $in;
        #$operator =~ s/[^A-Za-z0-9]+//g;
	#print "COPER = $operator\n";

	### CLOT ###
        read INPUT, $in, 16;
        $lotid = unpack "A16", $in;
        $lotid =~ s/[^0-9A-Za-z]+//g;
	$lotid = uc($lotid);
	#print "lotid = $lotid\n";


		###################
		# TRAP EMPTY LOTID
		###################
        	if($lotid eq "")
        	{
			print "\ndir=no_lotid";                 ### RETURN BAD SUBDIR FOR MFT
                	&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_lotid") if $mft_flag==0;
                	exit 100;
        	}


	### CPROB ###
        read INPUT, $in, 4;
        $prober = join "", (unpack "a4", $in);
        $prober =~ s/[^0-9A-Za-z]+//g;
        $prober = uc $prober;
	#print "CPROB = $prober\n";

        read INPUT, $in, 2;
        $snnum = char2short($in);
	#print "SNNUM = $snnum\n";

        read INPUT, $in, 2;
        $snsize = char2short($in);
        #print "SNSIZE: $snsize\n";

        read INPUT, $in, 2;
        #$NUMDIE = char2short($in);
	#print "NUMDIE = $NUMDIE\n";

        read INPUT, $in, 1;
        #$F1SSEG = unpack "c", $in;
	#print "F1SSEG = $F1SSEG\n";

        read INPUT, $in, 1;
        #$F1ESEG= unpack "b", $in;
	#print "F1ESEG = $F1ESEG\n";

        read INPUT, $in, 1;
        #$WFLAG = unpack "b" x 2, $in;
	#print "WFLAG = $WFLAG\n";

	### SPARE ###
	read INPUT, $in, 1;
	
        read INPUT, $in, 2;
        #$DARCNT = char2short($in);
	#print "DARCNT = $DARCNT\n";

        ### DTNUM (CONTAINS TEST# USE IN DATALOG) ###
        my $chk_order         = 0;
	my %test_cnt_per_site = 0;
        for(my $ii=1; $ii<= 32; $ii++)
        {
                read INPUT, $in, 1;
                $TEST_NUM = unpack "c", $in;

                if($TEST_NUM != 0)
                {
                        push (@test_logged, $TEST_NUM);

                        #### ENSURE PROPER TEST# SEQ ###
                        if($TEST_NUM < $chk_order)
                        {
                                print "Test ordering is incorrect, exiting converter\n";
                                exit 1;
                        }

                        $chk_order = $TEST_NUM;

			#####################################
			# DETERMINE PARAMETER COUNT PER SITE
			#####################################
			$test_cnt_per_site{1}++ if $TEST_NUM <= 20;
			$test_cnt_per_site{2}++ if $TEST_NUM > 20 && $TEST_NUM <= 40;
			$test_cnt_per_site{3}++ if $TEST_NUM > 40 && $TEST_NUM <= 60;
			$test_cnt_per_site{4}++ if $TEST_NUM > 60 && $TEST_NUM <= 80;
			$extra_readings++       if $TEST_NUM > 80;
                }
        }
        #print "site1 test count: $test_cnt_per_site{1}\n";
        #print "site2 test count: $test_cnt_per_site{2}\n";
        #print "site3 test count: $test_cnt_per_site{3}\n";
        #print "site4 test count: $test_cnt_per_site{4}\n";
        #print "extra test count: $extra_readings\n";


        ### DTYPE (32 FUNCTION #'s OF TEST IN DL SORT) ###
        read INPUT, $in, 32;
        #@FunctionNumbers = unpack "c" x 32, $in;
	#print "FuncNum   = @FunctionNumbers\n";


	### WFTNUM ###
        for (my $ind = 0; $ind < 3; $ind++)
        {
                read INPUT, $in, 2;
                #$WFTNUM[$ind] = char2short($in);
		#print "WFTNUM $ind $WFTNUM[$ind]\n";
        }

        read INPUT, $in, 3;
        #@WFSEG = unpack "c" x 3, $in;
	#print "WFSEG = @WFSEG\n";

	### RUNNAME ###
	read INPUT, $in, 15;
	$tp_name    = unpack "a15", $in;
	$tp_name    =~ s/^[^0-9A-Z]+|[^0-9A-Z]+$//gi;
        ($tp_name,) = split /\./,$tp_name;
	$tp_name    = uc $tp_name;
        #print "RUNNAME: $tp_name\n";


	read INPUT, $in, 15;
	#$TESTNAME    = unpack "a15", $in;
	#$TESTNAME    =~ s/^[^0-9A-Z]+|[^0-9A-Z]+$//gi;
        #($TESTNAME,) = split /\./,$TESTNAME;
        #print "TESTNAME: $TESTNAME\n";


		#############################
		# TRAP MISSING TESTPLAN NAME
		#############################
        	if($tp_name eq "")
        	{
			print "\ndir=missing_testplan";                 ### RETURN BAD SUBDIR FOR MFT
                	&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/missing_testplan") if $mft_flag==0;
                	exit 100;
        	}
	
                ########################
                # TRAP NON-FETQUAD FILE
                ########################
                if ($tp_name !~ /[D|E|F|H|I|K]$/i)
                {
                        close(INPUT);
			print "$file is not a valid fetquad file\n";
                        exit 1;
                }


		##################################
		# GET ASSIGNED SBIN PER PARAMETER 
		##################################	
		#if (-e "$ENV{ENV_TP_RAW}/${tp_name}.TPL")
		#if (-e "/data/edbcp/cpsort_fet_quad/convert/tp_raw/${tp_name}.TPL")
		if (-e "$ENV{DPDATA}/data/cpsort_fet_quad/TP/${tp_name}.TPL")
		{
			&get_assigned_sbin_per_param();
		}
		else
		{
			print "\ndir=missing_testplan";                 ### RETURN BAD SUBDIR FOR MFT
                        &move_file_to_bad_dir($file, "$ENV{ENV_TP_NOCONV}/missing_testplan") if $mft_flag==0;

			#print "Error: Testplan file $tp_name is not available\n";

			### MOVE BAD FILE TO ENV_TP_NOCONV ###
                	#system "mv $file $ENV{ENV_TP_NOCONV}";

                	### ADD FILE & MISING TP TO LOG (GET'S E-MAILED DAILY)
                	#open (MISSING_TP, ">>$ENV{ENV_LOG}/Missing_testplans.txt");
			open (MISSING_TP, ">>$ENV{DPDATA}/data/cpsort_fet_quad/log/Missing_testplans.txt");
                	print MISSING_TP "$file:$tp_name\n";
                	close(MISSING_TP);

                        exit 100;
		}	

	### SPARE ###
        read INPUT, $in, 361;


        ### PASS/TOTAL COUNTS STRUCTURE: 1 CWCT(100), 2 CWCTPASS 2 CWCTTOT ###
        for ($ind = 0; $ind < 200; $ind++)
        {
                read INPUT, $in, 2;
                #$CWCT[$ind] = char2short($in);
                #print "CWCT = ".$CWCT[$ind]."\n";
        }

	### CWNAM (CONTAINS WAFER NUMBERS) ###
        read INPUT, $in, 500;
        #CWNAM = unpack "a500", $in;



	#######################
	# PARSE CPR WAFER DATA
	#######################
	# each wafer of data contained within the file:
        #   1. Individual Wafer Header Record
        #   2. Wafer Results data including
        #       a. Bin Map Data
        #       b. Data log Data.
	#
	# Note: cpfetquad collects 1 wafer data per cpr.
	#


	######################
	# WAFER HEADER RECORD 
	######################

	### UNAME (WAFER NUM) ###
        read INPUT, $in, 5;
        $waferno = unpack "a5", $in;
	$waferno =~ s/^[^0-9]+|[^0-9]+$//g;

		### USE WAFER_NUM FROM THE CPR FILENAME IF THE WAFER_NUM FROM THE UNAME IS INVALID ###
		my (@dummy)            = split /\//, $file;
		my ($tmp_lotid, $dump) = split /\_/, $dummy[$#dummy], 2;
		my $filename_waferno   = substr($tmp_lotid, length($tmp_lotid)-2);
		#$waferno = $filename_waferno if $waferno != $filename_waferno;
		$waferno = $filename_waferno if $waferno !~ /^\d{1,2}$/;


        ### UFAIL COUNTER ### 
        for (my $ind=0; $ind<250; $ind++)
        {
                read INPUT, $in, 2;
                #$UFAIL[$ind] = char2short($in);
		#print "UFAIL $ind $UFAIL[$ind]\n";
        }

	### UTFAIL COUNTER ###
        for (my $ind=0; $ind<250; $ind++)
        {
                read INPUT, $in, 2;
                #$UTFAIL[$ind] = char2short($in);
		#print "UTFAIL $ind $UTFAIL[$ind]\n";
        }
		
	### UBEST COUNTER ###
        for (my $ind=0; $ind<25; $ind++)
        {
		read INPUT, $in, 3 if $ind == 0;
                read INPUT, $in, 4 if $ind != 0;
                #$UBEST[$ind] = bcd2int($in);
		#print "UBEST $ind $UBEST[$ind]\n";
        }
		
		
	### USORT COUNTER ###
        for (my $ind = 0; $ind < 25; $ind++)
        {
                #
                # Software bin fields from this array will not be used
		# because they do not fit the EWB model, i.e. in lot S2SWO9477C, soft bin 10 = hard bin 1
                # This creates problems with the test plan data mapping, etc.
                # Rodney Cyr, David Fletcher 4/2/2002
                #
                read INPUT, $in, 4;
                #$USORT[$ind] = bcd2int($in);
                #print "USORT $ind $USORT[$ind]\n";
	}

        ### UBIN (FOR SBIN SUMMARY) ###
	my @sbin = ();
        for (my $ind=1; $ind<=25; $ind++)
        {
                read INPUT, $in, 4;
                #$sbin[$ind]      = bcd2int($in);
		#$lot_sbin[$ind] += $sbin[$ind];
		#print "UBIN $ind $sbin[$ind]\n";
        }

	### UTOT (TOTAL TOUCH-DOWN COUNT) ###
        read INPUT, $in, 4;
        my $utot = bcd2int($in);
	#print "UTOT = $utot\n";

	### 1 OF N CURRENT VAL SAVED ###
        read INPUT, $in, 2;
        #$C10FN = char2short($in);
        #print "C10FN = $C10FN\n";

	### CURRENT DATA PTR ###
        read INPUT, $in, 2;
        #$CSNX = char2short($in);
        #print "CSNX = $CSNX\n";
		
	### CONSECUTIVE COUNT ###
	read INPUT, $in,4;
	#$CCNT = bcd2int($in);
	#print "CCNT = $CCNT\n";

	### CONSECUTIVE FAIL COUNT ###
        read INPUT, $in, 2;
        #$CFCNT = char2short($in);
        #print "CFCNT = $CFCNT\n";

        read INPUT, $in, 217;
        #$SPARE1 = unpack "c217", $in;
	#print "SPARE1 = $SPARE1\n";
		

	### READ 1 DUMMY BYTE ###
	read INPUT, $in, 1;


	##########################################################
        # READ WAFER DATA (PASS WAFERID AND FILE GENERATION YEAR)
        ##########################################################
        &read_map_file($waferno, $yy);


	#####################
	# READ SEQUENCE FILE
	#####################
	if ($seq_file ne "")
        {
               &read_sequence_file();
        }
        else
        {
		print "\n1dir=no_seq_file";                 ### RETURN BAD SUBDIR FOR MFT
                &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_seq_file") if $mft_flag==0;
                exit 100;
               #print "Error: No specified sequence file\n";
        }


	#########################
	# SET CORRECT SITE COUNT
	#########################
	if ($seq_file =~ /^Q/i)
	{
		$site_count = 4;


		##############################################
                # NOTIFY ENGR IF "TEST SITE PER SITE" DIFFERS
                ##############################################
                if ($test_cnt_per_site{1} != $test_cnt_per_site{2} ||
                    $test_cnt_per_site{1} != $test_cnt_per_site{3} ||
                    $test_cnt_per_site{1} != $test_cnt_per_site{4} )
                {
                        my $msg = "Kindly review testplan \"$tp_name\.\" The number of tests per site is not consistent; site1=$test_cnt_per_site{1}, site2=$test_cnt_per_site{2}, site3=$test_cnt_per_site{3}, site4=$test_cnt_per_site{4}\. Affected file is $file\.";
			&send_email("CPFETQUAD TESTPLAN ISSUE",$msg);
		}

	}
	elsif ($seq_file =~ /^D/i)
	{
		$site_count = 2;

		
		##############################################
                # NOTIFY ENGR IF "TEST SITE PER SITE" DIFFERS
                ##############################################
                if ($test_cnt_per_site{1} != $test_cnt_per_site{2})
                {
                        my $msg = "Kindly review testplan \"$tp_name\.\" The number of tests per site is not consistent; site1=$test_cnt_per_site{1}, site2=$test_cnt_per_site{2}\. Affected file is $file\.";

			&send_email("CPFETQUAD TESTPLAN ISSUE",$msg);
                }
	}


	####################
	# WAFER DATA RECORD
	####################
	my $hash_key      = 0;
	my $rec_counter   = 0;
	my $seq_count     = keys %seq;
	my $mismatch_flag = 0;		# 0=NO MISMATCH; 1=MISMATCH BIN RESULT


	###########################
	# PARSE TEST TEST READINGS
	###########################
	for (my $unit=1; $unit<=$utot; $unit++)
        {

		### READ UNITS UP TO THE COUNT DEFINED IN THE SEQ FILE ###
		last if $unit > $seq_count;				

                ### X COORDINATE (BOGUS VALUE) ###
                read INPUT, $in, 1;
                $x = unpack "C", $in;

                ### Y COORDINATE (BOGUS VALUE) ###
                read INPUT, $in, 1;
                $y = unpack "C", $in;
                #print "x=$x\ty=$y\n" if $unit == 18;

                ### BIN RESULT FOR THE 4 SITES ###
                read INPUT, $in, 1;
                #$bin_result = unpack "c", $in;
                #$bin_result = $bin_result & 127;

		#####################################################
		# SPLIT TEST READINGS INTO 2(DUALS) or 4(QUAD) SITES
		######################################################
		for (my $site=1; $site<=$site_count; $site++) 
                {

			my %test_readings     = ();
			my %pf_flag           = ();	### 0=PASS; 1=FAIL
			my $data_logged_cnt   = 0;	### 0 MEANS NO DATA WAS LOGGED FOR THE SITE
			my $bin_cpr           = 1;		
			my $last_logged_param = 0;
			for (my $param=1; $param<=$test_cnt_per_site{$site}; $param++)
			{
				### TEST FLAG ###
                               	read INPUT, $in, 1;
                               	@test_flag = split //, unpack "B8", $in;
				#print "site=$site\tparam=$param\t@test_flag\n";
			
				### SAVE PASS/FAIL FLAG ###
				$pf_flag{$param} = $test_flag[4];	

				### GET ASSIGNED SBIN IF FAIL FLAG IS SET ###
				$bin_cpr=$param{$param} if $pf_flag{$param} == 1;

				### TEST READING ###
                               	read INPUT, $in, 4;

#print "\tunit=$unit\tx=$x\ty=$y\tsite=$site\tparam=$param\ttst_flg=@test_flag\tbin=$bin_cpr\treading=".char2float($in)."\n";
#print "\tunit=$unit\tx=$x\ty=$y\tsite=$site\tparam=$param\treading=".char2float($in)."\tbin=$bin_cpr\ttest_flag=$pf_flag{$param}\n";

				### SAVE IF "DATA LOGGED" FLAG IS SET ###
                                if ($test_flag[2] == 1)
				{
					### SAVE TEST READING ###
                               		$test_readings{$param} = char2float($in); 

					### INC DATA LOGGED COUNTER ###
					$data_logged_cnt++;
					$last_logged_param=$param;
				}
			}


			#####################
			# SKIP TESTS 81 & UP
			#####################
			if ($site == $site_count && $extra_readings >= 1 )
                        {
                                read INPUT, $in, $extra_readings * 5;
                        }


			#################
                        # GET CORRECT XY
                        #################
                        ($x, $y) = &compute_xy($site, $seq{$unit}{X}, $seq{$unit}{Y});


			##############################
			# PROCEED IF W/ TEST READINGS
			##############################
			next unless $data_logged_cnt > 0;


			#####################################
                        # EXCLUDE TEST RESULTS OF INKED DICE
                        #####################################
                        next unless $map{$x}{$y} =~ /\d+/;

			#############################################
			# USE ALT BIN ON THE FF. CONDITION:
			# 1) NON-INKED DIE
			# 2) TEST FAIL FLAG IS NOT SET
			# 3) LAST_LOGGED_PARAM != MAX_PARAM_COUNT
 			# 4) ALT_BIN VALUE IS DEFINED 
			#############################################
			my $alt_bin_key = $last_logged_param + 1;
			if ($last_logged_param<$param_cnt_per_site && $bin_cpr == 1 && exists $alt_param{$alt_bin_key})
			{
				$bin_cpr = $alt_param{$alt_bin_key};
			}

#print "\nunit=$unit\tsite=$site\tx=$x\ty=$y\tdl=$data_logged_cnt\tll=$last_logged_param\tbin=$bin_cpr\tmap=$map{$x}{$y}\tmis=$mismatch_flag\n";


			######################################################
                        # FLAG IF THERE'S A MISMATCH BET MAP & CPR BIN RESULT
                        ######################################################
                        $mismatch_flag=1 if $map{$x}{$y} == 1 && $bin_cpr != 1;
                        $mismatch_flag=1 if $map{$x}{$y} == 0 && $bin_cpr == 1;


			#######################################################################
			# CAPTURE BIN RESULT FROM CPR IF BOTH MAPXY & MISMATCH_FLAG ARE ZEROES
			#######################################################################
			if ($map{$x}{$y} == 0 && $mismatch_flag == 0)
			{
				$map{$x}{$y} = $bin_cpr;	
			}

	#exit if $mismatch_flag==1;
	#exit if $unit > 18;

			##########################
                        # BIN SUMMARY FOR TD_STDF 
                        ##########################
                        if ($sbin{$bin_cpr} eq "")
                        {
                                $sbin{$bin_cpr} = 1;
                        }
                        else
                        {
                                $sbin{$bin_cpr}++;
                        }

			######################
			# STORE TEST READINGS 
			######################
			$td{$hash_key++} = 
			{
				UNIT     => $unit,
				SITE     => $site,
				BIN      => $bin_cpr,
				X	 => $x,
				Y	 => $y,
				PF_FLAG  => {%pf_flag},
				READINGS => {%test_readings},	
			};
		}
		$rec_counter++;


		### RECORD STORAGE ALLOCATION IS ALWAYS @ 1536 BYTES. SKIP UNUSED PORTION ###
                if ($rec_counter == $snnum)
                {
                	#print "skipping record: rec_counter is @ $rec_counter\n";
                        read INPUT, $in, 1536 - ($snnum * $snsize);
                        $rec_counter = 0;
                }       
	}
	close(INPUT);


	### DELETE FILE IF IT HAS NO DATA ###
	if (keys %td == 0)
	{
		print "\ndir=no_part_data";             ### RETURN BAD SUBDIR FOR MFT
                &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_part_data") if $mft_flag==0;
                exit 100;

		#unlink $file;
		#exit 1;
	}
}


#######################
# DATA TYPE CONVERSION
#######################
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

sub bcd2int
{
        my ($IN) = @_;
        my @b = unpack  "CCCC", $IN;
        my $sTmp ="";

        #    b3         b2         b1         b0
        #  NU = not used
        # 0000|0000, 0000|0000, 0000|0000, 0000|0000
        #
        $sTmp = pack "aaaaa", $b[3] & 0x0F, $b[2] >> 4, $b[2] & 0x0F, $b[1] >> 4, $b[1] & 0x0F,$b[0] >>  4, $b[0] & 0x0F;
        my $i = $sTmp * 1;
        return $i;
}




##########################
# FIND/READ SEQUENCE FILE
##########################
sub read_sequence_file
{
	### USE OLD SEQ FILES FOR CPR PRIOR AUG 26,2010 12NN ###
	my @loc_seq_files = ();
	if ($test_time < 1282824000)
	{
		#@loc_seq_files = `ls $ENV{ENV_TP_RAW}/old/${seq_file}*.SEQ`;
		#@loc_seq_files = `ls /data/edbcp/cpsort_fet_quad/convert/seq/old/${seq_file}*.SEQ`;
		@loc_seq_files = `ls $ENV{DPDATA}/data/cpsort_fet_quad/TP/Old/${seq_file}*.SEQ`;
	}
	else
	{
		#@loc_seq_files = `ls $ENV{ENV_TP_RAW}/${seq_file}*.SEQ`;	
		#@loc_seq_files = `ls /data/edbcp/cpsort_fet_quad/convert/seq/${seq_file}*.SEQ`;	
		@loc_seq_files = `ls $ENV{DPDATA}/data/cpsort_fet_quad/TP/${seq_file}*.SEQ`;
	}
	chomp($loc_seq_files[0]);

        ###########################
        # CHECK IF SEQ FILE EXISTS
        ###########################
	if (! -e "$loc_seq_files[0]")
        {
                ### LOG MISSING SEQ FILES ###
                #open LOG, ">>$ENV{ENV_LOG}/no_seq_file.log" or die "can't create no_seq_file.log file\n"; #if $mft_flag==0;
		open LOG, ">>$ENV{DPDATA}/data/cpsort_fet_quad/log/no_seq_file.log" or die "can't create no_seq_file.log file\n";
                print LOG "${seq_file}\,${file}\n"; # if $mft_flag==0;
                close(LOG); #if $mft_flag==0;

                ### PRINT ERROR MSG ###
                #print "Sequence file not available: $seq_file\n";

                ### MOVE FILE TO BAD DIR ###
                #system "mv $file $ENV{ENV_CONV_BAD}/no_seq/.";
                #exit 1;

		print "\n2dir=no_seq_file";             ### RETURN BAD SUBDIR FOR MFT
                &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_seq_file") if $mft_flag==0;
                exit 100;
        }

        ########################################
        # GET X,Y COORDINATES FROM THE SEQ FILE
        ########################################
	open SEQ, "$loc_seq_files[0]" or die " Failed to open seq file $loc_seq_files[0]\n";
        while($line=<SEQ>)
        {
                chomp($line);
                (@dummy) = split /\s+|\,/, $line;

		$dummy[0] =~ s/ //g;
		$dummy[1] =~ s/ //g;
                $dummy[2] =~ s/ //g;
                $dummy[3] =~ s/ //g;

		### STORE TEST SEQ COORDINATES ###
                if ($dummy[0] eq "TD" && $dummy[1] > 0)
                {
                        $seq{$dummy[1]} =
                        {
                                X => $dummy[2],
                                Y => $dummy[3],
                        };
                }
		elsif ($dummy[0] =~ /PROBE_PATTERN/i)
		{
			$probe_pattern = $dummy[1];
		}
        }
        close(SEQ);

}

################
# READ MAP FILE
################
sub read_map_file
{

	my $waferid        = shift;
	   #$waferid        = substr($waferid, length($waferid) - 3);
	my $loc_lotid      = (length($lotid) > 7) ? substr($lotid,length($lotid)-6) : $lotid;
        #my $arch_dir       = "/archives/edbcp/cpsort_wmap_sep";
	my $arch_dir       = "/archives-ASIA/edbcp/cpsort_wmap_sep";
	my $file_to_search = "${loc_lotid}_0{0,2}${waferid}_.+\.MAP.+";
	my @found_maps     = ();
	my $map_file       = "";
	my $dir_to_search  = "";

#$file_to_search = "PW00026781_011_FETQUAD_PW00026781_20150811125428U_08_6_011.MAP.gz";
#push(@found_maps,$file_to_search);

	#######################################
	# CHECK MAP IN 4 DIFF FOLDER LOCATIONS
	#######################################	

	### 1) SEARCH $ENV_ARCHIVE ###
	#if ($#found_maps == -1)
	#{
	#	$dir_to_search  = "/archives/edbcp/cpsort_wmap_sep";
		#find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
	#}

	### 2) SEARCH /archives FOR CURRENT YEAR. USE DISPATCH YEAR ###
	#if ($#found_maps == -1)
	#{
	#	my (@dummy) = split /\//   , $file;
	#        (@dummy) = split /\_|\./, $dummy[$#dummy];
	#	$year    = substr($dummy[$#dummy - 1],4,4);	### GET DISPATCHED YEAR
	
	
		### USE CURRENT YEAR IF DISPATCH YEAR IS INVALID ###
	#	if ($year < 1999 && $year > 3000)	
	#	{
	#		my $year   = `date '+%Y'`;
	#		chomp($year);
	#	}
	#	$dir_to_search = "${arch_dir}/${year}";
	#	find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
	#}
		
	### 3) SEARCH /archives FOR PREV YEAR ###
	#if ($#found_file == -1)
    	#{
	#	$year          -= 1;
	#	$dir_to_search = "${arch_dir}/${year}";
	#	find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
    	#}

	### 4) SEARCH /archives FOR NEXT YEAR ###
	#if ($#found_maps == -1)
	#{
	#	$year         += 2;
	#	$dir_to_search = "${arch_dir}/${year}";
	#	find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
	#}
	if ($#found_maps == -1)
        {
                my (@dummy) = split /\//   , $file;
                (@dummy) = split /\_|\./, $dummy[$#dummy];
                my $year    = substr($dummy[$#dummy - 1],4,4);     ### GET DISPATCHED YEAR
                my $mon     = substr($dummy[$#dummy - 1],2,2);
		$mon        =~ s/^0//;
		my $arc_mon = $month{$mon};  

                ### USE CURRENT YEAR IF DISPATCH YEAR IS INVALID ###
                if ($year < 1999 && $year > 3000)
                {
                        my $year   = `date '+%Y'`;
                        chomp($year);
                }
                $dir_to_search = "${arch_dir}/${year}/${arc_mon}";
                find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);

		### SEARC PREVIOUS MONTH IF MAP IS NOt FOUND
		if ($#found_maps == -1){
			$mon = $mon - 1;
			$arc_mon = $month{$mon};
			$dir_to_search = "${arch_dir}/${year}/${arc_mon}";
			find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
		}
        }
	
	###########################################################
	# SELECT THE CORRECT MAP (WITH "SYSTEM ID  PROBERxx" DATA)
	###########################################################
	foreach my $found_map(@found_maps)
	{
		my $cp_dir  = "$ENV{DPDATA}/data/cpsort_fet_quad/temp";
		my $cp_file = basename($found_map);
		my $cp_map  = "${cp_dir}/${cp_file}";
		copy($found_map,$cp_map) or die "Failed to copy file: $!\n";
		#$found_map = EDBUtil::doUncompress($found_map) if $found_map =~ /\.gz/;
		#$found_map = &doUncompress($found_map) if $found_map =~ /\.gz/;
		$cp_map = &doUncompress($cp_map) if $cp_map =~ /\.gz/;

		#open MAP, $found_map or die "can't open map ${found_map}. $!\n";
		open MAP, $cp_map or die "can't open map ${cp_map}. $!\n";
		while(chomp($line=<MAP>))
		{
			if ($line =~ /SYSTEM ID/)
			{
				#$map_file = $found_map if $line =~ /Probe/i;
				$map_file = $cp_map if $line =~ /Probe/i;
				last;
			}
		}
		close(MAP);
		#$found_map = EDBUtil::doCompress($found_map) if $map_file eq "";
		#$found_map = &doCompress($found_map) if $map_file eq "";


		### EXIT IF MAP IS FOUND ###
		last if $map_file ne "";	
	}


	############################
        # CHECK IF MAP FILE EXISTS
        ############################
        if ($map_file eq "")
        {
                ### LOG MISSING SEQ FILES ###
                #open LOG, ">>$ENV{ENV_LOG}/no_map_file.log" or die "can't create no_map_file.log file\n" if $mft_flag==0;
		open LOG, ">>$ENV{DPDATA}/data/cpsort_fet_quad/log/no_map_file.log" or die "can't create no_map_file.log file\n";
                print LOG "${lotid}\,${waferid}\n" if $mft_flag==0;
                close(LOG) if $mft_flag==0;

                ### PRINT ERROR MSG ###
                #print STDERR "Map file not available: ${lotid}\_${waferid}\n";

                ### MOVE FILE TO BAD DIR ###
                #system "mv $file $ENV{ENV_CONV_BAD}/no_map/.";
                #exit 1;
		
		print "\ndir=no_wmap_file";             ### RETURN BAD SUBDIR FOR MFT
                &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_wmap_file") if $mft_flag==0;
                exit 100;
        }


	#################
	# READ MAP FILE
	#################
	my $xy_flag = "N";  ### Y=MEANS XY BIN RESULT
	open MAP, "$map_file" or die " Failed to open map file $map_file. $!\n";
        while($line=<MAP>)
        {
                chomp($line);
		(@dummy)  = split /\t+/, $line;
		$dummy[0] =~ s/^\s+|\s$//g;
		$dummy[1] =~ s/^\s+|\s$//g;
		$dummy[2] =~ s/^\s+|\s$//g;
		$dummy[3] =~ s/^\s+|\s$//g;	

		if ($dummy[0] =~ /\[WAFERMAP\]/i)
                {
                        $xy_flag = "Y";
                }
                elsif ($dummy[0] =~ /\[EXT\s+WAFERMAP\]/i)
                {
                        $xy_flag = "N";
                }
                elsif ($dummy[0] =~ /X\-?\d+Y\-?\d+/ && $xy_flag eq "Y")
                {
			my (@dump) = split /X|Y|\t+/, $line;
                        $map{$dump[1]}{$dump[2]} = $dump[3];

			if ($dump[1] =~ /\d/)
			{
				$min_x = $dump[1] if $min_x eq "" || $dump[1] < $min_x;
                        	$max_x = $dump[1] if $max_x eq "" || $dump[1] > $max_x;
			}

			if ($dump[2] =~ /\d/)
			{
				$min_y = $dump[2] if $min_y eq "" || $dump[2] < $min_y;
                        	$max_y = $dump[2] if $max_y eq "" || $dump[2] > $max_y;
			}
		}
		elsif ($dummy[0] eq "CMAP")
                {
                        $seq_file = uc($dummy[1]);
                }
		elsif ($dummy[0] =~ /OPERATOR/i)
                {
			$operator = uc($dummy[1]);
		}
		elsif ($dummy[0] =~ /XSIZE/i)
		{
			$xsize = $dummy[1];
		}
		elsif ($dummy[0] =~ /YSIZE/i)
		{
			$ysize = $dummy[1];
		}	
		elsif ($dummy[0] =~ /UNITS/i)                
                {
			$units = $dummy[1];
                }
		elsif ($dummy[0] =~ /ROWS/i)                
                {
			$rows = $dummy[1];
                }
                elsif ($dummy[0] =~ /COLS/i)                
                {
			$cols = $dummy[1];
                }
                elsif ($dummy[0] =~ /FLAT/i)                
                {
			$flat = $dummy[1];
			if ( $flat == 0 || $flat == 360 )
                        { $flat = "U" ;}
                        elsif ( $flat == 90 )
                        { $flat = "R" ; }
                        elsif ( $flat == 180 )
                        { $flat = "D" ; }
                        elsif ( $flat == 270 )
                        { $flat = "L" ; }
                }
                elsif ($dummy[0] =~ /WAFER SIZE/i)                
                {
			$wafer_size = $dummy[1]/10;           #<-- CONVERT FROM MM TO CM
                }
		elsif ($dummy[0] =~ /REF DIE/i)
                {
			($xref,$yref) = split /\,/, $dummy[1];		
		}
                elsif ($dummy[0] =~ /TEST SYS/i)                
                {
			$node_nam = $dummy[1];
                }
                elsif ($dummy[0] =~ /TEST STA/i)                
                {
			$node_num = $dummy[1]||0;
                }
                elsif ($dummy[0] =~ /SYSTEM ID/i)                
                {
			$prober_id = $dummy[1];
                }
		elsif ($dummy[0] =~ /PROBECARD/i)
                {
			$probe_card = $dummy[1];	
                }
                elsif ($dummy[0] =~ /LOADBOARD/i)
                {
			$load_board = $dummy[1];
                }
                elsif ($dummy[0] =~ /PROBED DICE/i)
                {
			$probed_dice = $dummy[1];
                }
                elsif ($dummy[0] =~ /BIN\s+0/i)
                {
			$bad_dice = $dummy[1];
               	}
                elsif ($dummy[0] =~ /PASS DICE/i)
                {
			$good_dice = $dummy[1];
                }
                elsif ($dummy[0] =~ /GROSS\s+PROBES/i)
                {
			$gross_probes = $dummy[1];
                }
        }
        close(MAP);


	###########
        # GZIP MAP 
        ###########
	#$map_file = EDBUtil::doCompress($map_file);
	#$map_file = &doCompress($map_file);
	unlink $map_file;


	##########################
        # CONVERT DIE WIDTH TO CM
        ##########################
        if ((($xsize/10)*$cols) > $wafer_size)
        {
                #print "converting width from mils to cm\n";
                $xsize = $xsize / 393.7 ; # convert from mils to cm
        }
        else
        {
                #print "converting width from millimeters to cm \n";
                $xsize = $xsize / 10; # convert millimeters to cm
        }

	###########################
        # CONVERT DIE HEIGHT TO CM
        ###########################
	if ((($ysize/10)*$rows) > $wafer_size)
        {
                #print "converting height from mils to cm\n";
                $ysize = $ysize / 393.7 ; # convert mils to cm
        }
        else
        {
                #print "converting height from millimeters to cm \n";
                $ysize = $ysize / 10; # convert millimeters to cm
        }

}


######################################
# PREP BIN MAP FOR WM_STDF GENERATION
######################################
sub form_bin_map
{
	for (my $r=$min_y; $r<=$max_y; $r++)
	{

		for (my $c=$min_x; $c<=$max_x; $c++)
		{

			my $bin = "*";
		   	   $bin = $map{$c}{$r} if exists $map{$c}{$r};

			### FORM BIN MAP ###
			if ($bin =~ /[0-9]/)
			{
				if ($bin == 0)
				{ $map_data .= "\x0"; }
				elsif ($bin == 1)
                        	{ $map_data .= "\x1"; }
                         	elsif ($bin == 2)
                        	{ $map_data .= "\x2"; }
                        	elsif ($bin == 3)
                        	{ $map_data .= "\x3"; }
                        	elsif ($bin == 4)
                        	{ $map_data .= "\x4"; }
                        	elsif ($bin == 5)
                        	{ $map_data .= "\x5"; }
                        	elsif ($bin == 6)
                        	{ $map_data .= "\x6"; }
                        	elsif ($bin == 7)
                        	{ $map_data .= "\x7"; }
                        	elsif ($bin == 8)
                        	{ $map_data .= "\x8"; }
                        	elsif ($bin == 9)
                        	{ $map_data .= "\x9"; }
                        	elsif ($bin == 10)
                        	{ $map_data .= "\xa"; }
                        	elsif ($bin == 11)
                        	{ $map_data .= "\xb"; }
                        	elsif ($bin == 12)
                        	{ $map_data .= "\xc"; }
                        	elsif ($bin == 13)
                        	{ $map_data .= "\xd"; }
                        	elsif ($bin == 14)
                        	{ $map_data .= "\xe"; }
                        	elsif ($bin == 15)
                        	{ $map_data .= "\xf"; }
                        	elsif ($bin == 16)
                        	{ $map_data .= "\x10"; }
                        	elsif ($bin == 17)
                        	{ $map_data .= "\x11"; }
                        	elsif ($bin == 18)
                        	{ $map_data .= "\x12"; }
                        	elsif ($bin == 19)
                        	{ $map_data .= "\x13"; }
                        	elsif ($bin == 20)
                        	{ $map_data .= "\x14"; }
                        	elsif ($bin == 21)
                        	{ $map_data .= "\x15"; }
                        	elsif ($bin == 22)
                        	{ $map_data .= "\x16"; }
                        	elsif ($bin == 23)
                        	{ $map_data .= "\x17"; }
                        	elsif ($bin == 24)
                        	{ $map_data .= "\x18"; }
                        	elsif ($bin == 25)
                        	{ $map_data .= "\x19"; }
                        	elsif ($bin == 26)
                        	{ $map_data .= "\x1a"; }
                        	elsif ($bin == 27)
                        	{ $map_data .= "\x1b"; }
                        	elsif ($bin == 28)
                        	{ $map_data .= "\x1c"; }
                        	elsif ($bin == 29)
                        	{ $map_data .= "\x1d"; }
                        	elsif ($bin == 30)
                        	{ $map_data .= "\x1e"; }
                        	elsif ($bin == 31)
                        	{ $map_data .= "\x1f"; }
                        	elsif ($bin == 32)
                        	{ $map_data .= "\x20"; }
                        	else
				{ 
					print "No hex-equivalent value assigned for bin $bin\n";
					exit 1;
				}
			}
			else	# "*"
			{
				$map_data .= "\xfd";
				#print "$x\t$y\t\*\t$bin\th=".0xfd."\n";
			}

			### FORM BIN SUMMARY FOR WM_STDF ###
			if ($map_bin_summ{$bin} eq "")
			{
				$map_bin_summ{$bin} = 1;
			}
			else
			{
				$map_bin_summ{$bin}++;
			}
	
		}
	}


	############
        # TRAPPINGS
        ############
        ### EMPTY MAP FILE ###
        if ($map_data eq "" || length($map_data) == 0)
        {
		print "\ndir=no_map_data";             ### RETURN BAD SUBDIR FOR MFT
                &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_map_data") if $mft_flag==0;
                exit 100;
                #print "Error: No Map Bin Data\n";
                #exit 1;
        }
        ### MAP SIZE LIMIT ###
        if (length($map_data) > 256000)
        {
                print "Error: STDF+ can't support map size of ".length($mapdata).". Max supported size is 256,000\n";
                exit 1;
        }
}


##############################
# COMPUTE NEW X,Y COORDINATES
##############################
sub compute_xy
{
	##################
	# LOCAL VARIABLES
	##################
	my $die_num = shift;
	my $x_ref   = shift;
	my $y_ref   = shift;

	### 1X4 PATTERN ###
	if ($probe_pattern == 25 || $probe_pattern == 8)
	{
		if ($die_num == 1)
		{
			$x_new = $x_ref;
			$y_new = $y_ref;	
		}
		elsif ($die_num == 2)
		{
			$x_new = $x_ref + 1;
			$y_new = $y_ref;
		}
		elsif ($die_num == 3)
                {
			$x_new = $x_ref + 2;
                        $y_new = $y_ref;
                }
		elsif ($die_num == 4)
                {
			$x_new = $x_ref + 3;
                        $y_new = $y_ref;
                }
	}
	### 2X2 PATTERN ###
	elsif ($probe_pattern == 201 || $probe_pattern == 6 || $probe_pattern == 214)
	{
		if ($die_num == 1)
                {
                        $x_new = $x_ref;        
                        $y_new = $y_ref;       
                }
                elsif ($die_num == 2)
                {
                        $x_new = $x_ref;
			$y_new = $y_ref - 1;
                }
                elsif ($die_num == 3)
                {
                        $x_new = $x_ref + 1;
			$y_new = $y_ref - 1;
                }
                elsif ($die_num == 4)
                {
                        $x_new = $x_ref + 1;
                        $y_new = $y_ref;
                }
	}
	else
	{
		print "unknown probe pattern \"$probe_pattern\".\n";
		exit 1; 
	}

	return ($x_new,$y_new);
}


##################################
# GET ASSIGNED SBIN PER PARAMETER
##################################
sub get_assigned_sbin_per_param
{

	###########
	# READ PRN
	###########
	#open FH, "$ENV{ENV_TP_RAW}/${tp_name}.TPL" or die "Error: can't open $ENV{ENV_TP_RAW}/${tp_name}.TPL\n";
	#open FH, "/data/edbcp/cpsort_fet_quad/convert/tp_raw/${tp_name}.TPL" or die "Error: can't open $ENV{ENV_TP_RAW}/${tp_name}.TPL\n";
	#open FH, "${tp_name}.TPL" or die "Error: can't open ${tp_name}.PRN\n";
	open FH, "$ENV{DPDATA}/data/cpsort_fet_quad/TP/${tp_name}.TPL" or die "Error: can't open $ENV{DPDATA}/data/cpsort_fet_quad/TP/${tp_name}.TPL\n";
	while($line = <FH>)
	{
		chomp($line);
		(@dummy) = split /\,/, $line;

		### REMOVE SPACES ###
		for(my $i=0; $i<$#dummy; $i++)
		{
			$dummy[$i] =~ s/ //g;
		}

		### STORE BIN & ALT_BIN TO HASH ###
		$param{$dummy[0]}     = $dummy[4];
		$alt_param{$dummy[0]} = $dummy[5] if $dummy[5] ne "";
		#print "$dummy[0]\t$dummy[4]\t$dummy[5]\n";
	}
	close(FH);
}


#######################################
# DISPLAY PARSE VALUES (FOR DEBUGGING)
#######################################
sub display_parsed_values
{
	my $show_td   = 0;
	my $show_wmap = 0;

	if ($show_wmap == 1)
	{
		print "xsize       = $xsize\n";
		print "ysize       = $ysize\n";
		print "units	   = $units\n";
		print "rows        = $rows\n";
		print "cols	   = $cols\n";
		print "flat        = $flat\n";
		print "wafer_size  = $wafer_size\n";
		print "node_nam    = $node_nam\n";
		print "node_num    = $node_num\n";
		print "prober_id   = $prober_id\n";
		print "probe_card  = $probe_card\n";
		print "load_board  = $load_board\n";
		print "probed_dice = $probed_dice\n";
		print "bad_dice    = $bad_dice\n";
		print "good_dice   = $good_dice\n";
		print "gross_probes = $gross_probes\n";

		print "\nbin map summary\n";
		foreach my $no(sort {$a<=>$b} keys %map_bin_summ)
		{
			print "\tbin $no\t$map_bin_summ{$no}\n";
		}
	}

	#####################
	# SHOW TEST READINGS
	#####################
	if ($show_td == 1)
	{
		print "lot    : $lotid\n";
		print "seq    : $seq_file\n";
		print "date   : $test_time\n";
		print "snnum  : $snnum\n";
		print "snsize : $snsize\n";
		print "oper   : $operator\n";
		print "tp     : $tp_name\n";
		print "wafer  : $waferno\n";
		print "good  parts: $CWCT[0]\n";
		print "total parts: $CWCT[1]\n";
		
		print "waferno=$waferno\n";

		### BIN SUMMARY ###
                foreach $bin(sort {$a<=>$b} keys %sbin)
                {
                       	print "\tsbin $bin $sbin{$bin}\n";
                }

		### TEST READINGS ###
		foreach my $no(sort {$a<=>$b} keys %$td)
               	{
			print "\t\tkey=$no,\t";
			print "unit=$$td{$no}{UNIT},\t";
			print "site=$$td{$no}{SITE},\t";
			print "x=$$td{$no}{X},\t";
			print "y=$$td{$no}{Y},\n";
				
			my $pf_flag  = $$td{$no}{PF_FLAG};
			my $readings = $$td{$no}{READINGS};
			foreach my $key (sort {$a<=>$b} keys %$readings)
			{
				print "\t\t\ttest=$key\tresult=$$readings{$key}\t\tpf_flag=$$pf_flag{$key}\n";
			}
	
		}
	}
}



#######################
# CREATE STDF DATAFILE
#######################
sub create_td()
{
	##########################
        # ASSIGN DATALOG FILENAME
        ##########################
	#$td_filename = "${lotid}_${waferno}_${DateTime}_${envname}_TD_STDF";
	$td_filename = "${file}.TD";
        open OUTFILE, ">$td_filename" or die "Could not open file: $!";

        ##############
        # EMIR RECORD
        ##############
        %out::emir           = %{$out::init{emir}} ;
        $out::emir{lot_type} = "";
        $out::emir{mode_cod} = "P";
        $out::emir{setup_t}  = $test_time||stdf_time();		#<-- USE DATA FILE TIME IF AVAILABLE
        $out::emir{start_t}  = $test_time||stdf_time();		#<-- USE DATA FILE TIME IF AVAILABLE
        $out::emir{lot_id}   = $lotid;
        $out::emir{facility} = "FSCP";				#<-- PLANT/SITE
        $out::emir{job_nam}  = $tp_name;
        $out::emir{job_rev}  = $tp_rev;
        $out::emir{spec_nam} = $tp_name;
        $out::emir{spec_rev} = $tp_rev;
        $out::emir{oper_nam} = $operator;			#<-- OPERATOR ID
        $out::emir{tstr_typ} = $node_nam;			#<-- TESTER TYPE
	$out::emir{node_nam} = "";
	$out::emir{stat_num} = $node_num;			#<-- TESTER STATION NO.
	$out::emir{wswb_cnt} = keys %sbin;					
        $out::emir{psum_cnt} = keys %$td;			#<-- TOTAL COUNT OF PIR RECORDS 
	$out::emir{part_typ} = $seq_file;
	$out::emir{load_brd} = $load_board if $load_board ne "";
	$out::emir{prb_card} = $probe_card if $probe_card ne "";
        print OUTFILE &out::pack_EMIR(\%out::emir);


	###################################################
        # COMPUTE DISTANCE OF GRID DIES IF TOTAL DIE > 200
        ###################################################
	my $part_count = keys %td;
        my $distance   = 1;
        if ($part_count > 200)
	{
        	$distance   = int(sqrt($part_count/200));
	   	$distance   = 5 if $distance > 5;
	}
	#print "dist=$distance\tparts=$part_count\n";


	#############
        # WIR RECORD
        #############
        %out::wir            = %{$out::init{wir}};
	$out::wir{start_t}   = $test_time||stdf_time();
        $out::wir{wafer_id}  = $waferno;
        print OUTFILE &out::pack_WIR(\%out::wir);

	my $lot_parm_count = 0;
	my $partid         = 1;
        foreach my $no(sort {$a <=> $b} keys %td)
        {

		##################
		# COMPUTE PART ID
		##################
		$partid = ($td{$no}{UNIT} * $site_count) - ($site_count - $td{$no}{SITE});
		#print "partid=$partid\t($td{$no}{UNIT}\t$td{$no}{SITE}\t$site_count\n";

		#############################################
		# GENERATE IF GRID OR FAIL DIE OR WAFER_NO=2
		#############################################
		my $grid = "0";		# 0=GRID; 1=NON-GRID
                   #$grid = "0" if ($td{$no}{X} % $distance)==0 && ($td{$no}{Y} % $distance)==0;
                   #$grid = "0" if int($waferno) == 2 || $lotid =~ /^E/i || $file =~ /\_FULL/i;
                if ($grid == 0 || $td{$no}{BIN}!=1)
		{
               		#############
               		# PIR RECORD
               		#############
               		%out::pir            = %{$out::init{pir}};
               		$out::pir{head_num}  = 1;
               		$out::pir{site_num}  = $td{$no}{SITE};
               		$out::pir{x_coord}   = $td{$no}{X};
               		$out::pir{y_coord}   = $td{$no}{Y};
               		$out::pir{part_id}   = $partid;		
               		print OUTFILE &out::pack_PIR(\%out::pir);


			#############
                        # PTR RECORD
                        #############
			my $test_flag = 0;		### 0=TEST PASS; 1=TEST FAIL;
			my $param_cnt = 0;
			my $readings  = $td{$no}{READINGS};
			my $pf_flag   = $td{$no}{PF_FLAG};
			foreach my $testnum (sort {$a<=>$b} keys %$readings)
			{
               			%out::ptr           = %{$out::init{ptr}};
                       		$out::ptr{test_num} = $testnum;
                       		$out::ptr{result}   = ${$readings}{$testnum};
                       		$out::ptr{test_flg} = $$pf_flag{$testnum}."0".$grid."00000";
                       		print OUTFILE &out::pack_PTR(\%out::ptr);

				$param_cnt++;
               		}

			### COUNT GOOD UNIT ###
			$test_flag = 1   if $td{$no}{BIN} != 1;
			$good_units++    if $td{$no}{BIN} == 1;

               		###############
               		# EPRR RECORD
               		###############
               		%out::eprr           = %{$out::init{eprr}};
               		$out::eprr{num_test} = $param_cnt;
			$out::eprr{head_num} = 1;
               		$out::eprr{site_num} = $td{$no}{SITE};
               		$out::eprr{x_coord}  = $td{$no}{X};
               		$out::eprr{y_coord}  = $td{$no}{Y};
			$out::eprr{hard_bin} = $td{$no}{BIN};
			$out::eprr{soft_bin} = $td{$no}{BIN};
               		$out::eprr{part_id}  = $partid;        
			$out::eprr{part_flg} = "0000".$test_flag."000";
               		print OUTFILE &out::pack_EPRR(\%out::eprr);
		}
	}


	######################################
	# WSBR RECORD (DATA DERIVED FROM CPR)
	######################################
	my @all_sbin_nos = values %param;
	splice(@all_sbin_nos, $#all_sbin_nos + 1, 0, values %alt_param);	# ADD ALT_SBINS 
	unshift(@all_sbin_nos,1);						# ADD SBIN1
	my $prev_sbin_no = "";
	foreach $no(sort {$a<=>$b} @all_sbin_nos)
	{
		next if $no == $prev_sbin_no;
		%out::wsbr            = %{$out::init{wsbr}};
		$out::wsbr{sbin_num}  = $no;
		$out::wsbr{sbin_cnt}  =	defined $sbin{$no} ? $sbin{$no} : 0;
		print OUTFILE &out::pack_WSBR(\%out::wsbr);
		$prev_sbin_no = $no;
	}

	######################################
        # WHBR RECORD (DATA DERIVED FROM CPR)
        ######################################
        for (my $no=1; $no<=32; $no++)
        {
               %out::whbr            = %{$out::init{whbr}};
               $out::whbr{hbin_num}  = $no;
               $out::whbr{hbin_cnt}  = defined $sbin{$no} ? $sbin{$no} : 0;
               print OUTFILE &out::pack_WHBR(\%out::whbr);
        }
	
	#############
        # WRR RECORD
        #############
        %out::wrr            = %{$out::init{wrr}};
        $out::wrr{finish_t}  = $test_time||stdf_time();         #<-- DATE & TIME THE TESTING ENDS
        $out::wrr{part_cnt}  = keys %td;                    	#<-- TOTAL PIR COUNT
        $out::wrr{good_cnt}  = $sbin{1}||0;
	$out::wrr{wafer_id}  = $waferno;
	$out::wrr{prb_card}  = $prober;
        print OUTFILE &out::pack_WRR(\%out::wrr);
	


        #############
        # MRR RECORD
        #############
        %out::mrr            = %{$out::init{mrr}};
        $out::mrr{finish_t}  = $test_time||stdf_time();		#<-- DATE & TIME THE TESTING ENDS
        $out::mrr{part_cnt}  = keys %td;			#<-- TOTAL PIR COUNT 
	$out::mrr{good_cnt}  = $sbin{1}||0;		
        print OUTFILE &out::pack_MRR(\%out::mrr);
        close OUTFILE;


	########################
        # UPDATE EMIR{PRES_CNT}
        ########################
        $out::emir{pres_cnt}  = $lot_parm_count;                 #<-- TOTAL COUNT OF PTR RECORDS
        &out::update_EMIR(\%out::emir, $td_filename) ;
}


#######################
# CREATE STDF DATAFILE
#######################
sub create_map()
{

		###########################
		# CORRECT FOR INVALID BIN0
		###########################
		### There may be invalid Bin0 qty when Probed Die > Gross Probes
		if ( $gross_probes ne "" && $gross_probes > 0 )
		{
			if ( $probed_dice > $gross_probes ) 
			{
				$probed_dice = $gross_probes;
			}
			else
			{
				$unprobed_dice = $gross_probes - $probed_dice;
			}
		}

        my $ptr_count  = 0;
        my $good_units = 0;
		my $PathToFile = dirname($file);

        ##########################
        # ASSIGN DATALOG FILENAME
        ##########################
        $wm_filename = "${PathToFile}/${lotid}_${waferno}_${DateTime}_${envname}_${PID}.WM";
        open OUTFILE, ">$wm_filename" or die "Could not open file: $!";

		#$lotid = "ZB08SD1FYB";

        ##############
        # EMIR RECORD
        ##############
        %out::emir           = %{$out::init{emir}} ;
        $out::emir{lot_type} = "";
        $out::emir{mode_cod} = "P";
        $out::emir{setup_t}  = $test_time||stdf_time();
        $out::emir{start_t}  = $test_time||stdf_time();
        $out::emir{lot_id}   = $lotid;
        $out::emir{facility} = "FSCP";                         #<-- PLANT/SITE
        $out::emir{job_nam}  = $tp_name;
        $out::emir{job_rev}  = $tp_rev;
        $out::emir{spec_nam} = $tp_name;
        $out::emir{spec_rev} = $tp_rev;
        $out::emir{oper_nam} = $operator;                       #<-- OPERATOR ID
        $out::emir{part_typ} = $seq_file;
        $out::emir{device}   = $seq_file;
        $out::emir{tstr_typ} = $node_nam;                       #<-- TESTER TYPE
        $out::emir{node_nam} = $prober_id  if $prober_id ne "";	#<-- PROBER ID
        $out::emir{stat_num} = $node_num;                       #<-- TESTER STATION NO.
        $out::emir{prb_card} = $probe_card if $probe_card ne "";
        $out::emir{load_brd} = $load_board if $load_board ne "";
        $out::emir{ssum_cnt} = 1;
        $out::emir{wsum_cnt} = 1;
        $out::emir{shwb_cnt} = 32;
        $out::emir{whwb_cnt} = 32;
        print OUTFILE &out::pack_EMIR(\%out::emir);


        ##############
        # EWCR RECORD
        ##############
        %out::ewcr           = %{$out::init{ewcr}};
        $out::ewcr{wafr_siz} = $wafer_size;
        $out::ewcr{die_ht}   = $ysize;
        $out::ewcr{die_wid}  = $xsize;
        $out::ewcr{wf_units} = 2;
        $out::ewcr{wf_flat}  = $flat;
        $out::ewcr{refpt1_x} = $xref;
        $out::ewcr{refpt1_y} = $yref;
        $out::ewcr{row_cnt}  = $rows;
        $out::ewcr{col_cnt}  = $cols;
        print OUTFILE &out::pack_EWCR(\%out::ewcr);


        #############
        # GDR RECORD
        #############
        my $rec = pack("S", 1 ) .
                  pack("C", 10 ) .
                  pack("C" ,length($tp_name) ) .
                  $tp_name ;
        my $rec_len = length ( $rec ) ;
        print OUTFILE pack("S", $rec_len) ; # REC_LEN
        print OUTFILE pack("C", 50) ;       # REC_TYP
        print OUTFILE pack("C", 10) ;       # REC_SUB
        print OUTFILE $rec ;


        #############
        # WIR RECORD
        #############
        %out::wir            = %{$out::init{wir}};
        $out::wir{wafer_id}  = $waferno;
	$out::wir{start_t}   = $test_time||stdf_time();
        print OUTFILE &out::pack_WIR(\%out::wir);


        #############
        # WMR RECORD
        #############
        %out::wmr          = %{$out::init{wmr}};
        $out::wmr{die_bin} = $map_data;
        print OUTFILE &out::pack_WMR(\%out::wmr);


        ##############
        # WHBR RECORD
        ##############
		for (my $no=0; $no<=32; $no++)
        {
                %out::whbr            = %{$out::init{whbr}};
                $out::whbr{hbin_num}  = $no;
                $out::whbr{hbin_cnt}  = defined $map_bin_summ{$no} ? $map_bin_summ{$no} : 0;
				if ($no eq 1) 
				{
					$out::whbr{hbin_cnt} = $out::whbr{hbin_cnt} + $unprobed_dice;
				}
                print OUTFILE &out::pack_WHBR(\%out::whbr);
        }

        #############
        # WRR RECORD
        #############
        %out::wrr           = %{$out::init{wrr}};
        $out::wrr{finish_t} = $test_time||stdf_time();
        $out::wrr{part_cnt} = $probed_dice + $unprobed_dice;
        $out::wrr{good_cnt} = $good_dice + $unprobed_dice;
        $out::wrr{wafer_id} = $waferno;
        print OUTFILE &out::pack_WRR(\%out::wrr);


        #############
        # HBR RECORD
        #############
        for (my $no=0; $no<=32; $no++)
        {
                %out::hbr            = %{$out::init{hbr}};
                $out::hbr{hbin_num}  = $no;
                $out::hbr{hbin_cnt}  = defined $map_bin_summ{$no} ? $map_bin_summ{$no} : 0;
				if ($no eq 1) 
				{
					$out::hbr{hbin_cnt} = $out::hbr{hbin_cnt} + $unprobed_dice;
				}
                print OUTFILE &out::pack_HBR(\%out::hbr);
        }


        #############
        # MRR RECORD
        #############
        %out::mrr            = %{$out::init{mrr}};
        $out::mrr{finish_t}  = $test_time||stdf_time();        #<-- DATE & TIME THE TESTING ENDS
        $out::mrr{part_cnt}  = $probed_dice + $unprobed_dice; 
        $out::mrr{good_cnt}  = $good_dice + $unprobed_dice;
        print OUTFILE &out::pack_MRR(\%out::mrr);
        close OUTFILE;

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



#######################
# CONVERT TO BASE UNIT 
#######################
sub convert_to_base_unit
{
        my $value      = shift;
	my $unit       = shift;
        my $multiplier = 1;

        #print "orig: unit=$unit, value=$value\n";

        if ($unit =~ /^p/)
        {
                $unit       =~ s/^p//;
                $multiplier = 1e-12;
        }
        elsif ($unit =~ /^n/)
        {
                $unit       =~ s/^n//;
                $multiplier = 1e-9;
        }
        elsif ($unit =~ /^u/)
        {
                $unit       =~ s/^u//;
                $multiplier = 1e-6;
        }
        elsif ($unit =~ /^m/)
        {
                $unit       =~ s/^m//;
                $multiplier = 1e-3;
        }
        elsif ($unit =~ /^K/)
        {
                $unit       =~ s/^K//;
                $multiplier = 1e3;
        }
        $value *= $multiplier;

        #print "new: unit=$unit , value=$value , mul=$multiplier\n"; 
        return($value, uc($unit));
}


##############################
# SEARCH DATA FILE IN ARCHIVE
##############################
sub wanted
{
        my @tmp_array = ();
        my $tmp_lotid = $lotid;
           $tmp_lotid =~ s/\?/\\w/g;
           $tmp_lotid =~ s/\*/\\w\+/g;

        #############################################
        # GET FILESIZE THEN STORE RESULT INTO A HASH
        #############################################
        if (/$tmp_lotid/i && ! exists($no_dup{$File::Find::name}) && ! /[\.\_]\w+TP|[\.\_]TP/i)
        {
                my $file = $File::Find::name;
                my $size = &get_filesize($file);
                push(@{$datafiles{$lotid}{DATAFILES}}, "${file}:${size}");

                $no_dup{$File::Find::name}=1;   ### TO TRAP SAME FILENAME BUT DIFF INODE NUMBER
        }
}

#####################
# EMAIL NOTIFICATION
#####################
sub send_email
{
	my $td_file = substr($file,rindex($file,"/") + 1);
	my $subject = shift;
        my $body    = shift;
	   $body    =~ s/$file/$td_file/;
        my $msg     = MIME::Lite->new
        (
                Subject => "$subject: $td_file",
                From    => 'dpower@onsemi.com' ,
                To      => 'yms.admins@onsemi.com',
                Type    => 'text/plain',
                Data    =>  $body
        );
        $msg->send();

}
###############################
# Uncompress a file
###############################
sub doUncompress
{
  my $file = shift;

  return $file if($file !~ /\.Z$|\.gz$/i);
  my $pid = open3(\*GZIP_IN, \*GZIP_OUT, \*GZIP_ERR, "/usr/bin/gzip -vdf $file");
  waitpid( $pid, 0 );
  while(<GZIP_ERR>)
  {
    @values = split/\s+/;
  }
  close GZIP_IN;
  close GZIP_OUT;
  close GZIP_ERR;

  return $values[$#values];
}

###############################
# Compress a file
###############################
sub doCompress
{
  my $file = shift;

  return $file if($file =~ /\.Z$|\.gz$/i);
  my $pid = open3(\*GZIP_IN, \*GZIP_OUT, \*GZIP_ERR, "/usr/bin/gzip --force -v $file");
  waitpid( $pid, 0 );
  while(<GZIP_ERR>)
  {
    @values = split/\s+/;
  }
  close GZIP_IN;
  close GZIP_OUT;
  close GZIP_ERR;

  return $values[$#values];
}

