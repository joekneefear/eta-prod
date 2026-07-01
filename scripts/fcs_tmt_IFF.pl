#!/usr/bin/env perl_db
# SVN $Id: fcs_tmt_IFF.pl 2600 2020-10-07 03:38:21Z dpower $

=pod

=head1 SYNOPSIS

  fcs_tmt.pl <Input file name> 
      --out <output dir>
      --reffile <reference dir location (usually on TP folder)>
      [--finallot]
      [--movelsr] 
      
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will add LSR meta and summary data to SPD files, and validate data in some cases.

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/06/04 jgarcia 	: Added site as a required argument.
 2015/06/04 jgarcia 	: Modified to pass site as an argument to readfile method(subroutine) of $parser object.
 2015/06/04 jgarcia 	: Added to check model's instance variable forSBflag if 1 or true. trigger writer to output the iff file to sandbox folder if equal to 1.
 2015/05/29 grace   	: Added support for -v option.
 2015/05/25 jgarcia 	: Modified to not check wmap reference data if Final Test.
 2015-Jun-16  jgarcia 	: modified to support gem_cn_ft_tmt site
 2015/06/21 grace   	: set value for input_file of PP_LIMITS
 2015/60/23 jgarcia 	: changed from $infile to $LSR for input file of PP_LIMITS.
 2015/07/02 jgarcia 	: added to accept location in LOC as a required argument and assign the value to EQUIP6_ID. 
 2015-Jul-31  jgarcia 	: fixed bug >> test program greater that 35 char, the iff is not going to stage_sandbox.
 2015/09/16  jgarcia 	: modified to move the LSR file with SPD file in NotProcessed if processing SPD and generating IFF will encounter problem.
 2015/11/4   jgarcia 	: modified to not fail iff that dont have TP revision, rather load to sanbox and assign 0.+date as a revision.
 2015/11/19 eric    	: always generate but do not register limit if sandbox 
 2016/01/27  jgarcia 	: Log and show the test flow code when the test flow code is for Sandbox loading. 
 2016/01/29 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2017/03/06 gilbertm	: Always generate limits and dont register to refdb.
 2017/04/24 jgarcia 	: modified to support logging if there is inconsistent UNITS in all affected sites.
 2019/08/13 eric	: added nosandbox option. its purpose was not to move the file to sandbox when envoked.
 2021/02/20 eric	: fixed bug in trimming program name if program name is greater than 35
 2020/09/30 karen	: added support to fork output (IFF)/files to designated location 
 2021-Apr-13 Karen	: get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
 2021-Apr-13 jgarcia : modified to not hardcode reference file location but rather put as argument.
 2022-Dec-15 RabieSantillan : Program name length set to 235 characters max. Will load to sandbox if it exceeds 235
 2023-May-16 eric	: fix bug when nosandbox argument is used
 2023-May-17 eric	: modified to get lotid from spd for pplogging
=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use File::Basename qw/basename dirname/;
use File::Copy;
use IO::File;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::Parser::Tmt;
use PDF::DpWriter;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PDF::Util::TestFlowCodeUtility qw/getTestFlowCodeMode/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;

our $VERSION = "

1.0
";
our $TESTER  = "TMT";
my $location = "";
my $reglim_flg = "Y";

# a hash to receive options
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguemnts
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions(
        \%hOptions, "OUT=s", "FORK=s", "REFFILE=s", "FACILITYFILE=s", "MOVELSR", "SITE=s", "LOC=s", "FINALLOT", "LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG", "NOSANDBOX"
    )
    )
{
    pod2usage(3);
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};



my @required_options = qw/OUT SITE LOC FACILITYFILE REFFILE/;
pod2usage(3) if grep {!exists $hOptions{$_}} @required_options;

unless ( $hOptions{SITE} ) {
    dpExit( 1, "--site must be specified" );
    pod2usage(3);
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $site = $hOptions{SITE};
$location = $hOptions{LOC};

my $facility = "";
if($hOptions{FINALLOT}) {
	$facility = $config->{$location}->{finalTest};
}else {
	$facility = $config->{$location}->{probe};
}
INFO("FACILITY|EQUIP6_ID=$facility");

unless ( grep { $_ eq $site } qw/gtk_tw_ft hana_th_ft hana_cn_ft utac_th_ft atec_ph_ft pmft_tmt cpft_tmt szft_tmt gem_cn_ft/ ) {
    dpExit( 1, "wrong site code : $site" );
}

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

our $LSR;

# Exit with moving LSR files
sub dpExitError {
    my $message = shift;
    if ( $hOptions{MOVELSR} ) {
        move $LSR, ( dirname $LSR) . "/NotProcessed/" . ( basename $LSR);
    }
    dpExit( 1, $message );
}
#
#
# open input file
my $SPD = $ARGV[0];


if ( !-f $SPD ) {
    dpExit( 1, "input file does not exist $SPD" );
}
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},
	basename => ( basename $SPD),
        ext      => 'iff',
        gzipIFF  => 'Y'
    }
);

# Find corresponding LSR
$LSR = $SPD;
if ($SPD =~ /\.SPD$/) {
	$LSR =~ s/\.SPD$/\.LSR/;
} elsif ($SPD =~ /\.spd$/) {
	$LSR =~ s/\.spd$/\.lsr/;	
}
#$LSR =~ s/\.SPD$|.spd$/\.LSR/;
# wsanopao: Set Raw File ==> infile and Environment
$pplogger->setRawFile($SPD.";".$LSR);
$pplogger->setEnv($site,'tmt');

my $errLot;

if ($pplogger->{_ENV} eq "atec_ph_ft_tmt" ) {
	$errLot = &getLotFromSPD($SPD, $site);
}
elsif ($pplogger->{_ENV} eq "utac_th_ft_tmt") {
	$errLot = &getLotFromSPD($SPD, $site);
}
 else {
	$errLot = &getLotFromFilename($SPD, $site);
}

if ( !-f $LSR ) {
	  $pplogger->setLot($errLot);
	  if ($hOptions{FINALLOT}) {
	  	$pplogger->setWafNum("00");
	  }
	  	  
    dpExit( 4, "$LSR not found. Move to ReworkFiles folder" );
}

my $parser=PDF::Parser::Tmt->new;
my $model = $parser->readFile($SPD, $site, $hOptions{REFFILE});
if ($model->{misc} =~ /UNITS Inconsistent.+/) {
		my $header = $model->header;
		$pplogger->setLot($header->{LOT});
		if ($hOptions{SITE} =~ /.+ft.+/) {
			$pplogger->setWafNum("00");
		}
		dpExit(4, "$model->{misc}");
	}
&normalizeToBaseUnit($model);

my $header = $model->header;
   $header->VERSION($VERSION);
   $header->PROGRAM_CLASS(2);
   $header->EQUIP6_ID( "$facility" );
   $header->isFinalLot($hOptions{FINALLOT});

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

my $program = $header->PROGRAM;
my $testMode = $header->INDEX1;
$header->INDEX1("");
my $mode = "";
my $sandBoxFlag = 0;
my $tmlength = 0;
my $tplength = length($program);

INFO("Original Test Program Length = $tplength");
		
	#given($site){
		if($site eq 'gtk_tw_ft') {
			my $site = "gtk_tw_ft";
			if($header->REVISION eq "") {
				#dpExitError("INVALID OR NO TESTPLAN REVISION!!!");
				WARN("Sending to Sandbox, Cant get Testplan Revision from LSR file, assigning end_date as TP rev..");
				if (!($hOptions{NOSANDBOX})){
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
	

				$reglim_flg ="N";
				my ($tpRev, $dump) = split /\s+/, $header->END_TIME;
				$tpRev =~ s/\///g;
				$tpRev = "0.".$tpRev;
				$header->REVISION($tpRev)
			}
			($testMode, $mode, $sandBoxFlag) = getTestFlowCodeMode($site, $testMode, $model->{dataSource});
			if($sandBoxFlag == 1) {
				WARN("Sending to sandbox, $testMode test flow code was set for Sandbox loading on GTK_TW");
				if (!($hOptions{NOSANDBOX})){
					#$model->forSBflag( $sandBoxFlag );
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
			}
			
			#print "TESTMODE>>$testMode\tMODE>>$mode\tSBFlag>>$sandBoxFlag";
			my $testFlowCode = "_${testMode}";
			$tmlength = length($testFlowCode) if $testMode ne "";
			INFO("TestMode = $testMode");
			INFO ("Testmode Length + Underscore = $tmlength");
			INFO ("Original TP + Undescore + TestMode = ".($tplength+$tmlength). " characters");
			if ( length($program) + length($testFlowCode) > 235 )
			{
				WARN("PROGRAM NAME \"".$program.$testFlowCode."\" will be truncated to 235 characters.  Sending to sandbox.");
				if (!($hOptions{NOSANDBOX})){
			        	#$model->forSBflag( 1 );
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
			        $program = substr($program, 0, 235-length($testFlowCode)); # Leave enough room for testFlowCode
			        
			}
			$program .= $testFlowCode if $testMode ne "";
			
		}
		elsif($site eq 'hana_th_ft') {
			if($header->REVISION eq "") {
				WARN("Sending to Sandbox, Cant get Testplan Revision from LSR file, assigning end_date as TP rev..");
				if (!($hOptions{NOSANDBOX})){
					#dpExitError("INVALID OR NO TESTPLAN REVISION!!!");
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
				my ($tpRev, $dump) = split /\s+/, $header->END_TIME;
				$tpRev =~ s/\///g;
				$tpRev = "0.".$tpRev;
				$header->REVISION($tpRev)
			}
			($testMode, $mode, $sandBoxFlag) = getTestFlowCodeMode($site, $testMode, $model->{dataSource});
			if($sandBoxFlag == 1) {
				WARN("Sending to sandbox, $testMode test flow code was set for Sandbox loading on HANA_TH");
				if (!($hOptions{NOSANDBOX})){
					#$model->forSBflag( $sandBoxFlag );
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
			}
			#print "TESTMODE>>$testMode\tMODE>>$mode\tSBFlag>>$sandBoxFlag";
			my $testFlowCode = "_${testMode}";
			$tmlength = length($testFlowCode) if $testMode ne "";
			INFO("TestMode = $testMode");
                        INFO ("Testmode Length + Underscore = $tmlength");
                        INFO ("Original TP + Undescore + TestMode = ".($tplength+$tmlength). " characters");
			if ( length($program) + length($testFlowCode) > 235 )
			{
				WARN("PROGRAM NAME \"".$program.$testFlowCode."\" will be truncated to 235 characters.  Sending to sandbox.");
				if (!($hOptions{NOSANDBOX})){
			        	#$model->forSBflag( 1 );
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
			        $program = substr($program, 0, 235-length($testFlowCode)); # Leave enough room for testFlowCode
			        
			}
			$program .= $testFlowCode if $testMode ne "";
			
		}
		elsif($site eq 'hana_cn_ft') {
			if($header->REVISION eq "") {
				WARN("Sending to Sandbox, Cant get Testplan Revision from LSR file, assigning end_date as TP rev..");
				if (!($hOptions{NOSANDBOX})){
		  			#dpExitError("INVALID OR NO TESTPLAN REVISION!!!");
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}	
				$reglim_flg = "N";
				my ($tpRev, $dump) = split /\s+/, $header->END_TIME;
				$tpRev =~ s/\///g;
				$tpRev = "0.".$tpRev;
				$header->REVISION($tpRev)
		  }
		  ($testMode, $mode, $sandBoxFlag) = getTestFlowCodeMode($site, $testMode, $model->{dataSource});
		  if($sandBoxFlag == 1) {
				WARN("Sending to sandbox, $testMode test flow code was set for Sanbox loading on HANA_CN");
				if (!($hOptions{NOSANDBOX})){
					#$model->forSBflag( $sandBoxFlag );
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
			}
		  	#print "TESTMODE>>$testMode\tMODE>>$mode\tSBFlag>>$sandBoxFlag";
		  	my $testFlowCode = "_${testMode}";
			$tmlength = length($testFlowCode) if $testMode ne "";
			INFO("TestMode = $testMode");
                        INFO ("Testmode Length + Underscore = $tmlength");
                        INFO ("Original TP + Undescore + TestMode = ".($tplength+$tmlength). " characters");
			if ( length($program) + length($testFlowCode) > 235 )
			{
				WARN("PROGRAM NAME \"".$program.$testFlowCode."\" will be truncated to 235 characters.  Sending to sandbox.");
				if (!($hOptions{NOSANDBOX})){
			        	#$model->forSBflag( 1 );
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
			        $program = substr($program, 0, 235-length($testFlowCode)); # Leave enough room for testFlowCode
			        
			}
			$program .= $testFlowCode if $testMode ne "";
		  
 		}
		elsif($site eq 'utac_th_ft') {
			my $site = "utac_th_ft";
			if($header->REVISION eq "") {
				WARN("Sending to Sandbox, Cant get Testplan Revision from LSR file, assigning end_date as TP rev..");
				if (!($hOptions{NOSANDBOX})){
					#dpExitError("INVALID OR NO TESTPLAN REVISION!!!");
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
				my ($tpRev, $dump) = split /\s+/, $header->END_TIME;
				$tpRev =~ s/\///g;
				$tpRev = "0.".$tpRev;
				$header->REVISION($tpRev)
			}
			($testMode, $mode, $sandBoxFlag) = getTestFlowCodeMode($site, $testMode, $model->{dataSource});
			if($sandBoxFlag == 1) {
				WARN("Sending to sandbox, $testMode test flow code was set for Sanbox loading on UTAC_TH");
				if (!($hOptions{NOSANDBOX})){
					#$model->forSBflag( $sandBoxFlag );
					$wr->forSBox(1);
				}
				else {
    					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
    				}
			
				$reglim_flg = "N";
			}
			#print "TESTMODE>>$testMode\tMODE>>$mode\tSBFlag>>$sandBoxFlag";
			my $testFlowCode = "_${testMode}";
			$tmlength = length($testFlowCode) if $testMode ne "";
                        INFO("TestMode = $testMode");
                        INFO ("Testmode Length + Underscore = $tmlength");
                        INFO ("Original TP + Undescore + TestMode = ".($tplength+$tmlength). " characters");
			if ( length($program) + length($testFlowCode) > 235 )
			{
				WARN("PROGRAM NAME \"".$program.$testFlowCode."\" will be truncated to 235 characters.  Sending to sandbox.");
				if (!($hOptions{NOSANDBOX})){
			        	#$model->forSBflag( 1 );
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
			        $program = substr($program, 0, 235-length($testFlowCode)); # Leave enough room for testFlowCode
			        
			}
			$program .= $testFlowCode if $testMode ne "";
			
	
		}
		elsif($site eq 'atec_ph_ft') {
			my $site = "atec_ph_ft";
			if($header->REVISION eq "") {
				WARN("Sending to Sandbox, Cant get Testplan Revision from LSR file, assigning end_date as TP rev..");
				if (!($hOptions{NOSANDBOX})){
					#dpExitError("INVALID OR NO TESTPLAN REVISION!!!");
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
				my ($tpRev, $dump) = split /\s+/, $header->END_TIME;
				$tpRev =~ s/\///g;
				$tpRev = "0.".$tpRev;
				$header->REVISION($tpRev)
			}
			($testMode, $mode, $sandBoxFlag) = getTestFlowCodeMode($site, $testMode, $model->{dataSource});
			if($sandBoxFlag == 1) {
				WARN("Sending to sandbox, $testMode test flow code was set for Sanbox loading on ATEC_PH");
				if (!($hOptions{NOSANDBOX})){
					#$model->forSBflag( $sandBoxFlag );
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
			}
			#print "TESTMODE>>$testMode\tMODE>>$mode\tSBFlag>>$sandBoxFlag";
			my $testFlowCode = "_${testMode}";
			$tmlength = length($testFlowCode) if $testMode ne "";
                        INFO("TestMode = $testMode");
                        INFO ("Testmode Length + Underscore = $tmlength");
                        INFO ("Original TP + Undescore + TestMode = ".($tplength+$tmlength). " characters");
			if ( length($program) + length($testFlowCode) > 235 )
			{
				WARN("PROGRAM NAME \"".$program.$testFlowCode."\" will be truncated to 235 characters.  Sending to sandbox.");
				if (!($hOptions{NOSANDBOX})){
			        	#$model->forSBflag( 1 );
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
			        $program = substr($program, 0, 235-length($testFlowCode)); # Leave enough room for testFlowCode
			        
			}
			$program .= $testFlowCode if $testMode ne "";
			
		}
		elsif($site eq 'gem_cn_ft') {
			if ($header->REVISION eq "") {
				WARN("Sending to Sandbox, Cant get Testplan Revision from LSR file, assigning end_date as TP rev..");
				if (!($hOptions{NOSANDBOX})){
					#dpExit(1,"INVALID OR NO TESTPLAN REVISION!!!");
					#WARN("Sending to Sandbox, No Testplan Revision..");
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}

				$reglim_flg = "N";
				my ($tpRev, $dump) = split /\s+/, $header->END_TIME;
				$tpRev =~ s/\///g;
				$tpRev = "0.".$tpRev;
				$header->REVISION($tpRev)
			}
			#$program = $gemCNftTP;
			#my $testFlowCode = "_${testMode}";
			if ( length($program) > 235 )
			{
				WARN("PROGRAM NAME \"".$program."\" will be truncated to 235 characters.  Sending to sandbox.");
				if (!($hOptions{NOSANDBOX})){
			        	#$model->forSBflag( 1 );
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
			        $program = substr($program, 0, 235); # Leave enough room for session code
			        
			}
			#$program .= $testFlowCode;
			#$header->REVISION($gemCNftRev);
			
		}
		elsif($site eq 'cpft_tmt') {
			if($header->REVISION eq "") {
				dpExitError("INVALID OR NO TESTPLAN REVISION!!!");
			}
			
			#$header->PROGRAM($cpftTP);
			#$program = $cpftTP;
			if ( length($program) > 235 )
			{
				WARN("PROGRAM NAME \"".$program."\" will be truncated to 235 characters.  Sending to sandbox.");
				if (!($hOptions{NOSANDBOX})){
	        			#$model->forSBflag( 1 );
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
	        		$program = substr($program, 0, 235); # Leave enough room for session type
	        		
			}
			#$header->REVISION($cpftRev);
			
		}
		elsif($site eq 'pmft_tmt') {
			if($header->REVISION eq "") {
				dpExitError("INVALID OR NO TESTPLAN REVISION!!!");
			}
			#$header->LOT(uc( $pmftLotid ));
			if ( length($program) > 235 ){
				WARN("PROGRAM NAME \"".$program."\" will be truncated to 235 characters.  Sending to sandbox.");
				if (!($hOptions{NOSANDBOX})){
	      				#$model->forSBflag( 1 );
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
	        		$program = substr($program, 0, 235); # Leave enough room for session type
			}
	  }
		elsif($site eq 'szft_tmt') {
			if($header->REVISION eq "") {
				dpExitError("INVALID OR NO TESTPLAN REVISION!!!");
			}
			#$header->LOT(uc( $szftLotid ));
			if ( length($program) > 235 )
			{
				WARN("PROGRAM NAME \"".$program."\" will be truncated to 235 characters.  Sending to sandbox.");
				if (!($hOptions{NOSANDBOX})){
	        			#$model->forSBflag( 1 );
					$wr->forSBox(1);
				}
				else {
					WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
				}
				$reglim_flg = "N";
	        		$program = substr($program, 0, 235); # Leave enough room for session type
	        		
			}
			
		}
		
	#}
INFO ("Final Test Program Name = $program");
$header->PROGRAM($program);
$header->INDEX1($testMode);
$header->INDEX2($mode);


# get Mata from database
unless ( $header->populateMeta ) {
    #$wr->noMeta(1);
    if (!($hOptions{NOSANDBOX})){
	$wr->noMeta(1);
    }
    else {
	WARN("File was not sandboxed. Argument NOSANDBOX was enabled.");
    }
    $reglim_flg = "N";
}

####################################################
## Check for WMAP Data only if it is not FINALLOT ##
####################################################
if (!($hOptions{FINALLOT})) {
	my $wmap = $model->updateWMap;
	unless ( ! $wmap->isEmpty ){
		#$wr->wmapIsEmpty(1);
		if (!($hOptions{NOSANDBOX})){
			$wr->wmapIsEmpty(1);
		}
		else {
			WARN("File was not sandboxed. Argument was enabled.");
		}
		$reglim_flg = "N";
	}
	unless ( $wmap->confirmed ){
		#$wr->noWMap(1);
		if (!($hOptions{NOSANDBOX})){
			$wr->noWMap(1);
		}
		else {
			WARN("File was not sandboxed. Argument was enabled.");
		}
		$reglim_flg = "N";
	}
}


### Use program naming rule
if ($hOptions{FINALLOT}){
	$model->updateProgram;
}
else {
	$model->updateProgram("MAP_PGM");
}
#
####check if the model's forSBflag instance variable is equal to 1 or true. trigger the writer to output the iff file to the sanbox folder
#if($model->{forSBflag} == 1) {
#	$wr->forSBox(1);
#	if($site eq 'gem_cn_ft') {
#		INFO ("For SandBox loading because NO TP REVISION GEM only ");
#		
#	}
#}

my $fmt = new_iff_formatter({
  model=>$model,
  writer=>$wr
});

$fmt->dataItems([qw/partid site soft_bin hard_bin/]);
$fmt->testItems([qw/number name units group/]);
$fmt->printPar();

# Output Limit
#if ($reglim_flg eq "Y") {
#	if ($model->isLimitNew){
#		  $model->buildLimit;
#		  $fmt->printLimit;
#		  $model->limit->input_file(basename $LSR); 
#		  $model->limit->registerRefdb;
#	}
#}
#else { # always generate but do not register limit if sandbox
	$model->buildLimit;
	$fmt->printLimit;
	$model->limit->input_file(basename $LSR);
#}

if ( $hOptions{MOVELSR} ) {
    move $LSR, ( dirname $LSR) . "/Processed/" . ( basename $LSR);
}

dpExit(0);

sub getLotFromFilename() {
	my $file = shift;
	my $site = shift;
	my $baseFn = basename($file);
	my @temp = split( /_/, $file );
	my $lotid;
	
	if ( $site eq "gtk_tw_ft" ) {
		$lotid = $temp[0];
		#$testMode = $temp[3];
		#dpExitError("Unexpected filename $filename");
	}
	elsif ( $site =~ /hana.+/ ) {
		$lotid = $temp[0];
		if (length($lotid) > 10) {
			$lotid = substr($lotid, 0 , 10);
		}
		
	}
	#elsif ( $site eq "utac_th_ft" ) {
	#	$lotid = uc( $temp[1] );
		#$testMode = $temp[2];
		#dpExitError("Unexpected filename $filename");
	#}
	elsif ( $site eq "atec_ph_ft" ) {

		#$header->LOT(uc( $temp[4] ));
		#$testMode = $temp[6];
	}
	elsif ( $site eq "gem_cn_ft" ) {
		foreach my $element (@temp) {
			trim($element);
			if($element =~ /^GM\d{1,7}[a-zA-Z]{1}/) {
				$lotid = uc( $element );
			}
		}
	} elsif ($site eq "szft_tmt") {
		$lotid = $temp[0];
		if (($lotid =~ /^A0|^X\d+[A-Z]$/i) && (length($lotid) > 10)) {
			$lotid = substr($lotid,0,10);
		}
	}
	return $lotid
}

sub getLotFromSPD() {
	my $file = shift;
	my $site = shift;
	my $lotid;
	
	my $fileHandle = IO::File->new($file) or dpExitError("Failed to open SPD file $SPD", $SPD);
	while (my $line = $fileHandle->getline) {
		 $line =~ s/[\cM|\"]//g;
		 if ($line =~ /Lot ID/) {
		 		my (@lineDumpArray) = split(",", $line);
		 		$lotid = $lineDumpArray[1];
		 		my @dummy = split("_", $lotid);
				my $dummyLen = scalar @dummy;
				
				if ($site eq "utac_th_ft") {
					if ($dummyLen => 3) {
						$lotid = $dummy[1];	
					}
					else {
						$lotid = $dummy[0];
					}
				
				}				
				else {
		 			$lotid = $dummy[0];
				}

		 		last;
		 }
	}
	undef $fileHandle;
	return $lotid;
}

