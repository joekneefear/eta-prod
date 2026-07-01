#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_tesec_sort_IFF.pl <Input flie name>
  --out <output dir>  output direcotry must exist	  
  --loc <location e.g CP, SZ, ME>
  --config <cfg_tester_type>
  --facilityfile <$DPSCRIPT/facilityMapping.ini>
  [--finallot]
  [--logfile <logfilepath>]  
  [--debug|--trace]
  [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read STDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

2015-Dec-28 Eric	: new
2016-Apr-20 Eric	: modified to handle Stockholm data. Load test condition 
2017-Apr-24 jgarcia: modified to support pp_logging even if issues encountered in converting binary to ascii format.
2017-Apr-24 jgarcia: modified to support pp_logging when generated an malformed stdf ascii derrived from binary.
2017-May-30 Gilbert     : generate limits always and dont register in refdb.pp_limits
2021/04/07 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

=head1 LICENSE

(C) Fairchild Semiconductor Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::Parser::Stdf;
use PDF::Parser::Stdf::Generic;
use PDF::Formatter;
use PDF::DpWriter;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PDF::Util::TestFlowCodeUtility qw/getTestFlowCodeMode/;
use PPLOG::PPLogger;    # wsanopao
use v5.10;
use Config::Tiny;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;

our $VERSION = "1.0";
our $TESTER  = "TESEC";
my (%hOptions) = ();
my $location = "";
my $site = "";
my $reglim_flg = "Y";
my $good_count;
# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    	pod2usage(3);
}
unless (
    	GetOptions(
        	\%hOptions, "OUT=s", "SITE=s", "LOC=s", "FACILITYFILE=s", "CONFIG=s", "FINALLOT", "LOGFILE=s", "DEBUG", "TRACE", "PPLOG", "V"
    	)
	)
{
    	dpExit( 1, "invalid options" );
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

# Initialize logging

my @required_options = qw/OUT SITE LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions,$pplogger);

$location = $hOptions{LOC};
$site = $hOptions{SITE};
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");


# wsanopao: Pass PPLogger object to PDF::Log
if ($hOptions{PPLOG}){
        $pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

# check input file
my $infile = $ARGV[0];
if ( !-f $infile ) {
    	ERROR("$infile does not exist");
    	pod2usage(3);
}

# create Writer
my $wr = PDF::DpWriter->new(
    {   basename => ( basename $infile),
        ext      => 'iff',
        outdir   => $hOptions{OUT},
        gzipIFF  => 'Y'
    }
);

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);
my $header2 = new_headerLong->new();

# create parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $perl = "perl";
my ( $TP_bin, $TD_bin );

# Convert source file to TP and TD
my ($errLot,$errWafer,$errTestplan) = getLotWaferTestplan($infile);
INFO("LOT=$errLot||WAFER=$errWafer||TESTPLAN=$errTestplan");

my $command;
if ($location eq "MT") {
	$command = "$perl -I/export/home/dpower/project/scripts/stdf_perl/lib /export/home/dpower/project/scripts/stdf_perl/conv_tesec_dta.pl -infile=$infile -env_mod=/export/home/dpower/project/scripts/stdf_perl/mtsort_tesec_env_mod.pm";
}
elsif ($location eq "ST") {
	$command = "$perl -I/export/home/dpower/project/scripts/stdf_perl/lib /export/home/dpower/project/scripts/stdf_perl/conv_tesec_dta.pl -infile=$infile -env_mod=/export/home/dpower/project/scripts/stdf_perl/stsort_tesec_env_mod.pm";
}
INFO("$command");

my @output = `$command`;
if ($?) {
    	#print "error in $command\n";
    	$pplogger->setLot($errLot);
    	if ($site =~ /sort/) {
    		$pplogger->setWaferFlag(1);
    		$header2->LOT($errLot);
				$header2->populateMeta();
				$pplogger->setSourceLot($header2->SOURCE_LOT);
				$pplogger->setWafNum($errWafer);
			} else {
				$pplogger->setWafNum("00");
			}
    	dpExit( 1, "Failed to convert $command : $!" );
}
if ( $output[-1] =~ /td=(.*) tp=(.*)/ ) {
    	$TD_bin = $1;
    	$TP_bin = $2;
    	INFO("TD=$TD_bin");
    	INFO("TP=$TP_bin");
}
else {
			$pplogger->setLot($errLot);
    	if ($site =~ /sort/) {
    		$pplogger->setWaferFlag(1);
    		$header2->LOT($errLot);
				$header2->populateMeta();
				$pplogger->setSourceLot($header2->SOURCE_LOT);
				$pplogger->setWafNum($errWafer);
			} else {
				$pplogger->setWafNum("00");
			}
    	dpExit( 1, "Failed to convert $command : " . join( "#", @output ) );
}

my $TD_txt = convertBinToAscii($TD_bin);
if($TD_txt =~ /Failed to convert.+/i) {
	$pplogger->setLot($errLot);
	if ($site =~ /sort/) {
		$pplogger->setWaferFlag(1);
		$header2->LOT($errLot);
		$header2->populateMeta();
		$pplogger->setSourceLot($header2->SOURCE_LOT);
		$pplogger->setWafNum($errWafer);
	} else {
		$pplogger->setWafNum("00");
	}
 	dpExit(1, "$TD_txt");
}
my $TP_txt = convertBinToAscii($TP_bin);
if($TP_txt =~ /Failed to convert.+/i) {
	$pplogger->setLot($errLot);
	if ($site =~ /sort/) {
		$pplogger->setWaferFlag(1);
		$header2->LOT($errLot);
		$header2->populateMeta();
		$pplogger->setSourceLot($header2->SOURCE_LOT);
		$pplogger->setWafNum($errWafer);
	} else {
		$pplogger->setWafNum("00");
	}
 	dpExit(1, "$TP_txt");
}
my $td     = readStdfAscii($TD_txt);
if ($td =~ /NO_.+/i) {
	$pplogger->setLot($errLot);
	if ($site =~ /sort/) {
		$pplogger->setWaferFlag(1);
		$header2->LOT($errLot);
		$header2->populateMeta();
		$pplogger->setSourceLot($header2->SOURCE_LOT);
		$pplogger->setWafNum($errWafer);
	} else {
		$pplogger->setWafNum("00");
	}
 	dpExit(1, "$td");		
}
my $tp     = readStdfAscii($TP_txt);
if ($tp =~ /NO_.+/i) {
	$pplogger->setLot($errLot);
	if ($site =~ /sort/) {
		$pplogger->setWaferFlag(1);
		$header2->LOT($errLot);
		$header2->populateMeta();
		$pplogger->setSourceLot($header2->SOURCE_LOT);
		$pplogger->setWafNum($errWafer);
	} else {
		$pplogger->setWafNum("00");
	}
 	dpExit(1, "$tp");		
}
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());
# create parser
#my $parser = PDF::Parser::Stdf::Generic->new;

my $testCond = [qw/PIN_1 PIN_2 PIN_3 SBIN_NUM HBIN_NUM
        VCC VEE TEMP FREQ PARMTYPE SEQ_NAME
        TCONDS SBIN_NAM HBIN_NAM TEST_TXT
        LOAD_VAL TEST_CAT VIEW_ORD /];
$parser->testConditions_EPDR( $testCond);

my $tests = $parser->epdr2tests( $tp->EPDR );

foreach my $test(@$tests){
  	my @pins ; 
  	push @pins, (shift @{$test->conditions});
  	push @pins, (shift @{$test->conditions});
  	push @pins, (shift @{$test->conditions});
  	unshift @{$test->conditions},join(" ",@pins);
}
shift @$testCond; 
shift @$testCond; 
shift @$testCond; 
unshift @$testCond,qw/TestNumber TestName Units PINS/;

my $header = new_headerLong->new( $parser->stdf2header($td) );
my $mir = $td->EMIR;
my $program = $mir->{SPEC_NAM};

$header->PRODUCT($mir->{SPEC_NAM}) if ($header->{PRODUCT} eq "");
$header->EQUIP6_ID($facility);
$header->CFG_TESTER_TYPE($hOptions{CONFIG});
$header->PROGRAM_CLASS(1);
$header->PROGRAM($program);
$header->isFinalLot( $hOptions{FINALLOT} );

unless ( $header->populateMeta ) {
    	$wr->noMeta(1);
    	$reglim_flg = "N";
}
my $model = new_model({dataSource => 'TESEC'});
   $model->header($header);

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

my $wmap = $model->updateWMap;
if(defined $wmap)   {
	unless ( !$wmap->isEmpty ){
		$wr->wmapIsEmpty(1);
		$reglim_flg = "N";
	}
	unless ( $wmap->confirmed ) {
		$wr->noWMap(1);
		$reglim_flg = "N";
	}
}
else{
        $wmap = new_wmap;
        $wr->wmapIsEmpty(1) unless ( !$wmap->isEmpty );
        $wr->noWMap(1);
        $reglim_flg = "N";
        $model->wmap($wmap);
}

### Use program naming rule
$model->updateProgram("MAP_PGM");

foreach my $stdfWafer ( @{ $td->wafers } ) {
    	my $wafer = new_wafer;
    	$wafer->START_TIME( $header->START_TIME );
    	$wafer->END_TIME( $header->END_TIME );
    	my $waferNum = -1;
    	if ( defined $stdfWafer->WIR ) {
        	$waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
        	$wafer->number($waferNum);
		#$wafer->name(repNA($header->LOT)."_".$waferNum);
		# assign sourec lot as wafer name
		if ($header->SOURCE_LOT ne "") {
			$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
			$pplogger->setWaferFlag(1);
		}
        	if ( defined $stdfWafer->WIR->{START_T}
            	and $stdfWafer->WIR->{START_T} > 1000000000 )
        	{
            		$wafer->START_TIME( $stdfWafer->WIR->{START_T} );
        	}
        	if ( defined $stdfWafer->WRR->{FINISH_T}
            	and $stdfWafer->WRR->{FINITSH_T} > 1000000000 )
        	{
            		$wafer->END_TIME( $stdfWafer->WRR->{FINISH_T} );
        	}
		if(defined $stdfWafer->WRR->{GOOD_CNT})
        	{
            		$good_count =  $stdfWafer->WRR->{GOOD_CNT};
        	}
    	}
    	if ( @{ $stdfWafer->WSBR } ) {
        	$wsbins = $parser->sbr2bins( $stdfWafer->WSBR,$good_count );
		#$wsbins = $parser->sbr2bins( $stdfWafer->WSBR);
    	}
    	if($wsbins ne ""){
        	$wafer->sbins($wsbins);
    	}
    	if ( @{ $stdfWafer->WHBR } ) {
         	$whbins = $parser->hbr2bins( $stdfWafer->WHBR, $good_count);
	 	#$whbins = $parser->hbr2bins( $stdfWafer->WHBR);
    	}
    	if ($whbins ne ""){
        	$wafer->hbins($whbins);
    	}

    	$wafer->tests($tests);
    	$wafer->dies( $parser->res2dies_fet_sort( $stdfWafer->res, $tests ) );
    	$model->add( 'wafers', $wafer );
}

$model->sbins($sbins);
$model->hbins($hbins);
$model->wmap($wmap);

&normalizeToBaseUnit($model);

my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);
$formatter->printPar;

# Limits
#if ($reglim_flg eq "Y") {
#	if ( $model->isLimitNew ) {
#	    	$model->buildLimit;
#	    	$model->limit->conditionNames($testCond);
#	    	$formatter->printLimit;
#	    	$model->limit->input_file(basename $infile); 
#	    	$model->limit->registerRefdb;
#	}
#}
#else {    #always generate but do not register limit if sandbox
	$model->buildLimit;
	$model->limit->conditionNames($testCond);
	$formatter->printLimit;
	$model->limit->input_file(basename $infile);
#}

unless (isLogDebug) {
    	unlink $TD_bin;
    	unlink $TD_txt;
    	unlink $TP_bin;
    	unlink $TP_txt;
}

dpExit(0);

sub getLotWaferTestplan() {
	my $file = shift;
	my $byte_8_or_32  = 32;
	my ($lot, $wafer, $testplan);
	my @wafers = ();
	
	my $in = "";

	###############
	# FILE PARSING
	###############
	open FH, $file or die "can't open $file\n";
	
	#########################################	
		# 1) Read Label Area (Length: 128 bytes) 
	#########################################	
		
		### FILE CREATION DATE & TIME ###
		read FH, $in, 1;
		#	$year  = unpack "c", $in;
		#(@dummy) = split //, $year;
		#$year  = $dummy[$#dummy-1].$dummy[$#dummy];	
		read FH, $in, 1;
		#	$month = unpack "c", $in;
		#	$month = $month + 1;			#<-- Value is 0-11
		#$month = "0".$month if $month < 10;
		read FH, $in, 1;
		#	$day   = unpack "c", $in;
		#$day   = "0".$day if $day < 10;
		#read FH, $in, 1;
		#	$hour  = unpack "c", $in;
		#$hour  = "0".$hour if $hour < 10;
		read FH, $in, 1;
		#	$minute = unpack "c", $in;
		#$minute = "0".$minute if $minute < 10;
		read FH, $in, 1;
		#	$second = unpack "c", $in;
		#$second = "0".$second if $second < 10;

#		if ($use_file_date eq "Y") 
#		{
#			$session_datetime  = (stat($file))[9]||&stdf_time();
#		}
#		else
#		{
#			### CONVERT DATE & TIME TO UNIX ###
#			$file_datetime = "$month\/$day\/$year $hour\:$minute\:$second";
#			if ($site eq "FSST") {
#				print"$site\n";
#				$session_datetime = timegm($second, $minute, $hour, $day+1, $month-1, $year);
#			}
#			else {
#				$session_datetime = timegm($second, $minute, $hour, $day, $month-1, $year);
#			}
#			#print "file_datetime=$file_datetime\n";
#		}
		### READ FILENAME, DEVICE, & OPERATOR FIELDS AS ONE(CONTAINS TESTPLAN NAME)### 
		if ($byte_8_or_32 == 8)
		{
			read FH, $in, 8;
                	$testplan    = unpack "A8", $in;
		}
		elsif ($byte_8_or_32 == 32)
		{
			read FH, $in, 32;
			$testplan    = unpack "A32", $in;
		}
		$testplan    =~ s/[^a-zA-Z0-9]//g;
		$testplan    = substr($testplan, 0, 35);
		print "Test plan is:$testplan\n";

#
#			### TRAP MISSING TP NAME ###
#                        if ($testplan eq "")
#                        {
#                                print "No testplan name.\ndir=missing_testplan";
#				&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/missing_testplan") if $mft_flag==0;
#                                exit 100;
#				#dpExit (1, "missing test program");
#                        }
#		
		### DEVICE ###
		read FH, $in, 10;
		#$device = unpack "a10", $in;
		#$device =~ s/[\W\-_]//g;
		#print "device = \"$device\"\n";
		### OPERATOR ###
    read FH, $in, 10;
		#$operator = unpack "A10", $in;
		#print "operator=$operator\n";
		### TESTING MODE ###
		read FH, $in, 1;
		### STATION NAME ###
		read FH, $in, 1;
		#$station =  unpack "A", $in;
		#print "station=$station\n";
		### LOT NAME (NOT USED)###
		read FH, $in, 10;
		$lot = unpack "A10", $in;
		### COMMENT ###
		if ($byte_8_or_32 == 8)
                {
			read FH, $in, 50;
			#$comment = unpack "A50", $in;
		}
		elsif ($byte_8_or_32 == 32)
		{
			read FH, $in, 26;
			#$comment = unpack "A26", $in;
		}
		#print "comment=$comment\n";
		### TIME POINT ??? ###
		read FH, $in, 2;
		#$time_point = unpack "v2", $in;
		### SET QUANTITY ###
		read FH, $in, 2;
		#$set_qty = unpack "v2", $in;	
		#print "set_qty=$set_qty\n";
		### LOGGING RATE ??? ###
		read FH, $in, 2;
		#$log_rate = unpack "v2", $in;
		### TEST MAX ###
		read FH, $in, 2;
		my $test_max = unpack "v2", $in;
		#print "test_max=$test_max\n";
	
		### DATE BLOCK NUMBER (NOT USED) ###
		read FH, $in, 2;
		### LOGGED QTY ###
		read FH, $in, 2;
		#$logged_qty = unpack "v2", $in;
		#print "logged_qty=$logged_qty\n";

			#############################
			# EXIT IF LOGGED QTY IS ZERO 
			#############################
#			if ($logged_qty == 0)
#			{
#				print "file doesn't contain test data.\ndir=no_part_data";
#				&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_part_data") if $mft_flag==0;
#				exit 100;
#				#dpExit (1, "no part data");
#			}

		### INDEX MAX ??? ###
		read FH, $in, 2;
		my $index_max = unpack "v2", $in;
		#print "index_max=$index_max\n";

		### RESERVED/NO DATA ###
		read FH, $in, 18;

	
	#####################################################
	# 2) READ TEST ITEM AREA (Size: 64 x Test Max Bytes)
	#####################################################
	for(my $i=0; $i < $test_max; $i++)
	{
	        ### TEST NUMBER ###
                read FH, $in, 1;
                #$test_num  = unpack "C", $in;
                #$test_num  =~ s/[^A-Za-z0-9]*//g;
		#$test_num += $test_num_mod;

		### ITEM GROUP CODE ###
                read FH, $in, 1;
                #$group_code = unpack "C", $in;
		#$tp{$test_num}{GROUP_CODE} = $group_code;

		### ITEM CODE ###
                read FH, $in, 2;
                #$item_code = uc(unpack "H2", $in); 
		#$tp{$test_num}{ITEM_CODE} = $item_code;

		### BE CONDITION & FLAGS ###
                read FH, $in, 1;
                #$be_cond    = unpack "B8", $in;
                #@limit_sign = (split //,$be_cond);
		#$tp{$test_num}{BE_COND} = $be_cond;

		### RESULT AS BIAS FLAGS ###
                read FH, $in, 1;
                #result = unpack "B8", $in;
		#$tp{$test_num}{RESULT} = $result;

		### LIMIT ITEM NAME  ###
                read FH, $in, 6;
                #$limit_item = unpack "a6", $in;
                #$limit_item =~ s/[^A-Za-z0-9]*//g;
		#$tp{$test_num}{LIMIT_ITEM_NAME} = uc($limit_item);
		#if(uc($limit_item) =~ /XLOC|YLOC/i && $XLocFlag ne "On") {
			#$XYLocFlag = "On";
		#}

		### LIMIT UNIT ###
                read FH, $in, 2;
                #$limit_unit = unpack "a", $in;
		#$tp{$test_num}{LIMIT_UNIT} = $limit_unit;

		###  LIMIT VALUE ###
                read FH, $in, 4;
                #$limit_value = char2float($in);
		#$tp{$test_num}{LIMIT_VALUE} = $limit_value;



		#print "$limit_item\n";
		#$val = unpack "d", $in;
		#print "\td=$val\n";
		#$val = unpack "f", $in;
                #print "\tf=$val\n";

		### MIN LOGGED VALUE ###
                read FH, $in, 4;
		#$lolim = char2float($in);

		### MAX LOGGED VALUE ###
                read FH, $in, 4;
		#$hilim = char2float($in);


		### BIAS 1 NAME ###
                read FH, $in, 4;
               # my $bias1_name = unpack "a4", $in;
                 #  $bias1_name =~ s/[^A-Za-z0-9]*//g;

		### BIAS 1 UNIT ###
                read FH, $in, 2;
              #  my $bias1_unit = unpack "a", $in;

		### BIAS 1 VALUE ###
                read FH, $in, 4;
               # my $bias1_value = char2float($in);
		#$tp{$test_num}{BIAS1} = $bias1_value;
		
		### BIAS 2 NAME ###
                read FH, $in, 4;
                #my $bias2_name = unpack "a4", $in;
		  # $bias2_name =~ s/[^A-Za-z0-9]*//g;

		### BIAS 2 UNIT ###
                read FH, $in, 2;
               # my $bias2_unit = unpack "a", $in;

		### BIAS 2 VALUE ###
                read FH, $in, 4;
               ## my $bias2_value = char2float($in);


#			### CONCATENATE BIAS INFO ###
#			$tp{$test_num}{BIAS} = "";
#			if ($bias1_value != 0)
#			{
#				my $short_bias1_val  = &shorten_bias_value($bias1_value);
#				$tp{$test_num}{BIAS} = $bias1_name."=".$short_bias1_val.$bias1_unit;
#			}
#			if ($bias2_value != 0)
#                        {
#				my $short_bias2_val  = &shorten_bias_value($bias2_value);
#				$tp{$test_num}{BIAS}.= "_".$bias2_name."=".$short_bias2_val.$bias2_unit;
#			}
#
#
#			### SET LOWER & UPPER SPEC LIMITS TO BLANK ###
#			$tp{$test_num}{LOW_SPEC_LIM} = "";
#			$tp{$test_num}{HI_SPEC_LIM}  = "";


			############################
			# CAPTURE TP_REV FROM "DEF" 
			############################
#			if ($limit_item eq "DEF" && ($test_num==1 || $test_num==$test_max))
#			{
#                        	$testplan_rev 		     = $limit_value;
#				$tp{$test_num}{HI_SPEC_LIM}  =  1e20;
#				$tp{$test_num}{LOW_SPEC_LIM} = -1e20;
#				#print "test plan rev is:$testplan_rev\n";
#			}
#
#
#			########################
#			# RECOMPUTE LIMIT VALUE
#			########################
#			# LIMIT UNIT IS "R" OR LIMIT_ITEM=RDON 
#			if ($tp{$test_num}{LIMIT_UNIT} eq "R" || $tp{$test_num}{LIMIT_ITEM_NAME} eq "RDON")
#			{
#				$tp{$test_num}{LIMIT_VALUE} = $limit_value / $bias1_value;
#			}
#			# HFE & GMP TESTS
#			if ($tp{$test_num}{LIMIT_ITEM_NAME}=~/\b(HFE|HHFE|GMP)\b/)
#                	{
#                        	$tp{$test_num}{LIMIT_VALUE} = $bias2_value / $limit_value;
#                	}
#                	# RIV TEST 
#                	if ($tp{$test_num}{LIMIT_ITEM_NAME} eq 'RIV')
#                	{
#                        	$tp{$test_num}{LIMIT_VALUE} = $bias1_value / $limit_value;
#
#                	}
#			# CONT
#			if ($tp{$test_num}{LIMIT_ITEM_NAME} eq 'CONT')
#			{
#				$tp{$test_num}{HI_SPEC_LIM} =1;
#				$tp{$test_num}{LOW_SPEC_LIM}=1;
#			}


		### TIME CONDITION NAME ###
                read FH, $in, 4;
                #$time_cond = unpack "a4", $in;
		#$tp{$test_num}{TIME_COND} = $time_cond;	
		
		### TIME UNIT ###
                read FH, $in, 2;
                #$time_unit = unpack "a2", $in;
		#$tp{$test_num}{TIME_UNIT} = $time_unit;

		### TIME VALUE ###
                read FH, $in, 4;
                #$time_value = char2float($in);
		#$tp{$test_num}{TIME_VALUE} = $time_value;

		### RESERVED ###
                read FH, $in, 8;
	}



	###############################################################
        # 3) TEST DATA AREA (Size: 6 x Qty x (6 + 6 + Test Max) Bytes)
        ###############################################################
	my $w 	      = "";
	my $wafer_num = "";
	do	{
        	### ALWAYS W ###
        	read FH, $in, 1;
		$w = unpack "a", $in;

        	### WAFER NUMBER ###
        	read FH, $in, 1;
        	$wafer_num = unpack "C", $in;
        	push	@wafers, $wafer_num;


		#$wafer_num = 0 if $data_type eq "FT"; #FORCE ZERO VALUE AS SOME FILES HAVE WAFER_NUM VALUE OF ONE EVEN IF DATA_TYPE IS FT.

        	### NUMBER OF DEVICES/NO. OF UNITS TESTED ###
        	read FH, $in, 2;
        	my $num_devices = unpack "v2", $in;


			### SOMETIMES, THE DEVICE COUNT IN F/T IS ZERO. HENCE, USE LOGGED QTY  ###
			#$num_devices = $logged_qty if $num_devices==0 && $data_type eq "FT";

			
        	### RESERVED  ###
        	read FH, $in, 2;

		for(my $i=0; $i < $num_devices; $i++)		{
			### ALWAYS D ###
                	read FH, $in, 1;

                	### ALWAYS 00 ###
                	read FH, $in, 1;

                	### SERIAL NUMBER ###
                	read FH, $in, 2;
                	#$serial_num = unpack "v2", $in;

                	### BIN NUMBER ###
                	read FH, $in, 2;
                	#$bin_num = unpack "C2", $in;
			#print "bin: $bin_num\n";


			my %readings = ();
			for(my $j=0; $j<$test_max; $j++){	
				### TEST NUMBER ###
				read FH, $in, 1;
				#$test_no = unpack "c", $in;
				#$test_no += $test_num_mod;
		
				### TEST FLAG ###
				read FH, $in, 1;
				#$flag = unpack "B8", $in;
				#(@flag) = split //, $flag;

				### TEST READING (ALREADY IN BASE UNIT) ###
				read FH, $in, 4;
				#next if $test_no == 0;	  # TEST_NUM=0 MEANS UNTESTED 
	
				### NO_DATA_BIT(3): 0=WITH DATA; 1=NONE. CONT FLAG(5) MUST BE ZERO ###
#				if ($flag[3] == 0 && $flag[5] == 0)
#				{
#					$readings{$test_no} = char2float($in);
#	
#					### STORE RESULT TO DETERMINE UPPER/LOWER SPEC LIMITS ###
#					if (! exists($pf{$test_no}) && $readings{$test_no}!=$tp{$test_no}{LIMIT_VALUE})
#					{
#						$pf{$test_no} = 
#						{
#							READING => $readings{$test_no},
#							PF      => $flag[0],
#						};
#					}
#				}
#				### CONT DATA: 0=NO DATA; 1=WITH DATA ###
#				elsif ($flag[5] == 1)
#				{
#					### SET PASS=1/FAIL=0 ###
#					$readings{$test_no} = ($flag[0]==0) ? 1 : 0;
#				}

			}

			################################
			# STORE TEST READINGS TO A HASH
			################################
#			if ( (($wafer_num > 0 && $data_type eq "WS") 
#			   || ($wafer_num ==0 && $data_type eq "FT")) 
#			   && $serial_num > 0)
#			{
#				$td{$wafer_num}{$serial_num} = 
#				{
#					BIN      => $bin_num,
#					READINGS => {%readings},
#				};
#			}


			##################################
			# CREATE BIN SUMMARY(WAFER LEVEL)
			##################################
#			if ($dta_whbin{wafer_num}{$bin_num} eq "")
#			{ 
#				$dta_whbin{$wafer_num}{$bin_num} = 1;
#			}
#			else
#			{
#				$dta_whbin{$wafer_num}{$bin_num}++;
#			}
#	
#			################################
#                        # CREATE BIN SUMMARY(LOT LEVEL)
#                        ################################
#			if ($dta_hbin{$bin_num} eq "")
#                        {
#                                $dta_hbin{$bin_num} = 1;
#				$dta_max_hbin_num   = $bin_num if $dta_max_hbin_num < $bin_num;
#                        }
#                        else
#                        {
#                                $dta_hbin{$bin_num}++;
#                        }
#        	}
#		
#		###############
#		# COUNT WAFERS
#		###############
#		$wafer_cnt++ if $wafer_num >= 1 && $num_devices > 0;

}
} 
	while($w eq "W" && $wafer_num >= 1);


$wafer = $wafers[0];
$testplan = uc($testplan);
return ($lot,$wafer,$testplan);
}
