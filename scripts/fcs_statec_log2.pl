#!/usr/bin/env perl_db
# 18-Aug-2015  Saed    - Created

=pod

=head1 SYNOPSIS

  fcs_static_log.pl <Input flie name>
	--out <output dir>
	--temp <unzip dir>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]
=head1 DESCRIPTIONS

=head1 AUTHOR

B<saed.hasan@pdf.com>

=head1 CHANGES

 2015/08/19 saed 	: new creation
 2015/09/11 eric 	: truncate ppid if > 35, use lot lookup method, use updateProgram method.
 2015/10/08 jgarcia 	: modified to support atec_ph_ft statec log2 file.
 2015/10/08 jgarcia 	: modified to accept site as parameter and passed it in calling 
                      	readFile method of statec_log.pm module.
 2015/10/08 jgarcia 	: modified to process test flow code for atec_ph site.
 2015/11/19 eric    	: always generate but do not register limit if sandbox
 2016/01/29 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2016/06/29 eric    	: added options for bkrel loading
 2016/07/07 eric    	: corrected how rel lot were parsed,
 			emptied dtype contains [0-9], emptied strdur & temp if contains [a-z]
 2017-May-30 gilbert 	: generate limits always and dont register in refdb.pp_limits
 2018-Jan-12 eric	: parse ONRMS datalog
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021-Apr-08 Karen      : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Getopt::Long;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Parser::statec_log2;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PDF::Util::TestFlowCodeUtility qw/getTestFlowCodeMode/;
use PPLOG::PPLogger; 	# wsanopao: 
use Number::Range;
use Config::Tiny;

our $VERSION = "1.0";
our $TESTER  = "STATEC";

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "FORK=s", "FACILITYFILE=s", "TEMP=s", "FINALLOT", "RELLOT", "LOGFILE=s", "DEBUG", "TRACE", "V", "LOC=s", "SITE=s", "PPLOG" )
    )
{
    dpExit( 1, "invalid options" );
}
 
if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});

# Read input file
my $infile = $ARGV[0];
if ( !-f $infile ) {
    pod2usage();
    dpExit( 1, "input file does not exist $infile" );
}

my $site = $hOptions{SITE};

# wsanopao: Set Raw File ==> infile 
$PPlogger->setRawFile($infile);


# check output dir
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},
        basename => ( basename $infile),
        ext      => 'iff',
        gzipIFF  => 'Y'
    }
);


my $parser = PDF::Parser::statec_log2->new;
#my $temp = $hOptions{TEMP};
my $location     = $hOptions{LOC};
my $facility = "";
if($hOptions{FINALLOT}) {
        $facility = $config->{$location}->{finalTest};
} else {
 $facility = $config->{$location}->{probe};
}
INFO("FACILITY|EQUIP6_ID=$facility");
my $reglim_flg = "Y";

if($infile =~ /gz$/)
{
	my $command = "gunzip $infile";
	my $ret = system($command);	
}
else
{
		
	my $model = $parser->readFile($infile, isLogDebug, $hOptions{SITE});
	
	#&normalizeToBaseUnit($model);

	my $header = $model->header;
	$header->isFinalLot($hOptions{FINALLOT});
	$header->isRelLot( $hOptions{RELLOT} );
	$header->VERSION($VERSION);
	$header->PROGRAM_CLASS(2);
	$header->EQUIP6_ID( "$facility" );
		
	# wsanopao: Passing Reference of Model
	$PPlogger->setModelHeader($model);
	
 	my $program = $header->PROGRAM;
 	my $testMode = $header->INDEX1;
 	$header->INDEX1("");
	my $mode = "";
	my $sandBoxFlag = "";

	# Capture Rel Attributes
	if ($hOptions{RELLOT}){
        	my $base_fn = basename($infile);
           	$base_fn =~ s/\.LOG2.*+//ig;
        	my @item = split /\_/, $base_fn;
		my $qpnum;
	        my $devchar;
	        my $lotchar;
        	my $strname = $item[1];
        	my $strdur = $item[2];
        	my $temp = $item[3];
        	my $dtype = $item[4];
		   $dtype = "" if $dtype =~ /[0-9]/; 

		if ($item[0] =~ /^20/) {   #fsc rel
                	$qpnum = substr $item[0], 0, 8;
                	$devchar = uc(substr $item[0], 8, 1);
                	$lotchar = uc(substr $item[0], 9, 1);
                	$header->LOT($qpnum.$devchar.$lotchar);
        	}
        	elsif ($item[0] =~ /^K/i){  #bkrel_statec onrms
                	$qpnum = substr $item[0], 0, 6;
                	$lotchar = uc(substr $item[0], 6, 1);
                	$header->LOT($qpnum.$lotchar);
        	}	

        	my $range = Number::Range->new("0..1000000");
        	if ( $range->inrange($strdur) && $strdur !~ /\D/) {
                	#do nothing
        	}
        	else {
                	WARN ("Stress Duration not in range =  $strdur");
			$strdur = "" if $strdur =~ /[a-z]/i;
                	$wr->forSBox(1);
			$reglim_flg = "N";
        	}
        	my $range = Number::Range->new("-1000000..1000000");
        	if ( $range->inrange($temp) && $temp !~ /\D/) {
                	#do nothing
        	}
        	else {
                	WARN ("ATETemp not in range = $temp");
			$temp = "" if $temp =~ /[a-z]/i;
                	$wr->forSBox(1);
			$reglim_flg = "N";
        	}

		#$header->LOT($qpnum.$devchar.$lotchar);
		$header->INDEX1($strname."_".$strdur."_".$temp."_".$dtype);

        	my $rel = new_rel;
        	$rel->qpnumber($qpnum);
        	$rel->devchar($devchar);
        	$rel->lotchar($lotchar);
        	$rel->strname($strname);
        	$rel->strduration($strdur);
        	$rel->atetemp($temp);
        	$rel->datalogtype($dtype);
        	$model->add('rels', $rel);
	}		
		
	if($hOptions{SITE} eq "atec_ph_ft") {
		if($header->REVISION eq ""){
			# wsanopao: Capture this message before Exit
			dpExit( 1, "Invalid or No Testplan Revision");
		}
		($testMode, $mode, $sandBoxFlag) = getTestFlowCodeMode($hOptions{SITE}, $testMode, $model->{dataSource});
		if($sandBoxFlag == 1) {
			WARN("Sending to sandbox, unknown test flow code");
			#$model->forSBflag( $sandBoxFlag );
			$wr->forSBox(1);
			$reglim_flg = "N";
		}
		my $testFlowCode = "_${testMode}";
		if ( length($program) + length($testFlowCode) > 35 )
		{
		        WARN("PROGRAM NAME \"".$program.$testFlowCode."\" will be truncated to 35 characters.  Sending to sandbox.");
		        #$model->forSBflag( 1 );
			$wr->forSBox(1);
			$reglim_flg = "N";
		        $program = substr($program, 1, 35-length($testFlowCode)); # Leave enough room for testFlowCode
			        
		}
			$program .= $testFlowCode;
			$header->PROGRAM($program);
			$header->INDEX1($testMode);
			$header->INDEX2($mode);
	} 
	else {
		if (length($program) > 35) {
        		INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters. Sending to sandbox.");
        		$wr->forSBox(1);
			$reglim_flg = "N";
        		$program = substr($program, 1, 35); 
		}			

		$header->PROGRAM($program);
	}
		
	unless ( $header->populateMeta ){
		$wr->noMeta(1);
		$reglim_flg = "N";
	}

	if (!($hOptions{FINALLOT})&& !($hOptions{RELLOT})) {
		my $wmap = $model->updateWMap;
		unless ( ! $wmap->isEmpty ){
			$wr->wmapIsEmpty(1);
			$reglim_flg = "N";
		}
		unless ( $wmap->confirmed ){
			$wr->noWMap(1);
			$reglim_flg = "N";
		}
	}

	$model->updateProgram;
	
	my $formatter = new_iff_formatter(
		{   model  => $model,
		    writer => $wr
		}
	);
		
	$formatter->dataItems([qw/partid site hard_bin soft_bin/]);
	$formatter->testItems([qw/number name units /]);
	$formatter->binItems ([qw/number name PF count/]);
	$formatter->printPar;

	# Output Limit
	#if ($reglim_flg eq "Y") {
	#	if ($model->isLimitNew){
	#  		$model->buildLimit;
	#  		$formatter->printLimit;
	#     		$model->limit->registerRefdb;
	# 	}			
	#}
	#else {  #always generate but do not register limit if sandbox
		$model->buildLimit;
		$formatter->printLimit;
	#}
}

dpExit(0);



