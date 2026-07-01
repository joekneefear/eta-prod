#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_tesec_dta_ft_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist	  
      --loc <location e.g CP, SZ, ME>
      --config <cfg_tester_type>
      [--finallot]
      [--logfile <logfilepath>]  
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read STDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<sungsuk.moon@pdf.com>

=head1 CHANGES

2015/09/03 grace	: new
2015/10/23 Gilbert	: changed /home/dpower/EWB_converters to /home/dpower/project/scripts/stdf_perl 
2015/11/19 eric   	: always generate but do not register limit if sandbox
2016/02/16 wsanopao	: logging pre-processing information  to refdb.pp_log table.
2016/05/18 eric	  	: added options for reliability data loading
2016/06/16 eric		: modified to cater bk rel loading. 
2016/07/07 eric		: corrected how rel lot were parsed,
			emptied dtype contains [0-9], emptied strdur & temp if contains [a-z]
2016/08/30 rodney   	: Message from convert command was not displayed in the log.
2017/04/17 jgarcia 	: added getLotFromFilename sub routine.
2017/04/17 jgarcia 	: make sure to log if something wrong in processing the raw file using ewb converter
2017/04/17 jgarcia 	: make sure to log if something wrong in converting bin to ascii.
2017/04/17 jgarcia 	: make sure to log if something wrong in reading STDF Ascii.
2017/05/30 gilbert     	: generate limits always and dont register in refdb.pp_limits
2018/01/11 eric		: parse ONRMS datalog
2020/09/01 karen       : added support to fork output (IFF)/files to designated location
2021/04/12 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

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
use Number::Range;
use PPLOG::PPLogger; 	# wsanopao: 
use v5.10;
use Config::Tiny;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;

our $VERSION = "

1.0
";
our $TESTER  = "TESEC";

# a hash to receive options
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

my $testFlowCode = "";
my $testMode = "";
my $mode = "";
my $sandBoxFlag = "0";
#my $lotid = "";
my $location = "";
my $site = "";
my $reglim_flg = "Y";

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions, "OUT=s", "FORK=s", "SITE=s", "LOC=s", "FACILITYFILE=s", "CONFIG=s", "FINALLOT", "RELLOT", "LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG"
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

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});

$location = $hOptions{LOC};
$site = $hOptions{SITE};

my $facility = "";
if($hOptions{FINALLOT}) {
	$facility = $config->{$location}->{finalTest};
}else {
	$facility = $config->{$location}->{probe};
}
INFO("FACILITY|EQUIP6_ID=$facility");

if ($site eq "szft") {
	$pplogger->setEnv("szft_tesec");
}

# check input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);


if ( !-f $infile ) {
    pod2usage(3);
}
#my $model = new_model;

my $header  = new_headerLong;
my $wmap = new_wmap;
my $perl = "perl_db";
my ( $TP_bin, $TD_bin );

my $model  = new_model(
	{ header => $header,
		wmap   => $wmap,
		dataSource => 'TESEC',
		forSBflag => ''
	}
	);

# create Writer
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   basename => ( basename $infile),
        ext      => 'iff',
        outdir   => $hOptions{OUT},
	forkdir => $hOptions{FORK},
	gzipIFF  => 'Y'
	
    }
);

my $errLot = &getLotFromFilename($infile);
my $errWafer = "";
# Convert source file to TP and TD
my $command;
if ( $site eq "szft" || $site eq "szrel" ) {
	$command = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_tesec_dta.pl -infile=$infile -env_mod=/export/home/dpower/project/scripts/stdf_perl/szft_tesec_env_mod.pm";
}
elsif ( $site eq "bkrel" ) {
	$command = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_tesec_dta.pl -infile=$infile -env_mod=/export/home/dpower/project/scripts/stdf_perl/bkrel_tesec_env_mod.pm";
}
INFO ("$command");

my @output = `$command`;
if ($?) {
	    if ($site eq "szft") {
	    	
	    	$pplogger->setLot($errLot);	
	    	$pplogger->setWafNum("00");
	    }
    	print "error in $command\n";
    	dpExit( 1, "Failed to convert: $! $output[0]" );
}
if ( $output[-1] =~ /td=(.*) tp=(.*)/ ) {
    	$TD_bin = $1;
    	$TP_bin = $2;
    	INFO("TD=$TD_bin");
    	INFO("TP=$TP_bin");
}
else {
			if ($site eq "szft") {
				
	    	$pplogger->setLot($errLot);	
	    	$pplogger->setWafNum("00");
	    }
    	dpExit( 1, "Failed to convert $command : " . join( "#", $output[0] ) );
}

my $TD_txt = convertBinToAscii($TD_bin);
if($TD_txt =~ /Failed to convert.+/i) {
	#$pplogger->setWaferFlag(1);
	$pplogger->setLot($errLot);
	if ($hOptions{FINALLOT}) {
		$pplogger->setWafNum("00");
	} else {
		$pplogger->setWafNum($errWafer);
	}
	
	dpExit(1, "$TD_txt");
}
my $TP_txt = convertBinToAscii($TP_bin);
if($TP_txt =~ /Failed to convert.+/i) {
	#$pplogger->setWaferFlag(1);
	$pplogger->setLot($errLot);
	if ($hOptions{FINALLOT}) {
		$pplogger->setWafNum("00");
	} else {
		$pplogger->setWafNum($errWafer);
	}
	dpExit(1, "$TP_txt");
}
my $td = readStdfAscii($TD_txt);
if ($td =~ /NO_.+/i) {
	$pplogger->setLot($errLot);
  if ($hOptions{FINALLOT}) {
		$pplogger->setWafNum("00");
	} else {
		$pplogger->setWafNum($errWafer);
	}
  dpExit( 1, "$td" );
}
my $tp = readStdfAscii($TP_txt);
if ($tp =~ /NO_.+/i) {
	$pplogger->setLot($errLot);
  if ($hOptions{FINALLOT}) {
		$pplogger->setWafNum("00");
	} else {
		$pplogger->setWafNum($errWafer);
	}
  dpExit( 1, "$tp" );
}
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());
# create parser
my $parser = PDF::Parser::Stdf::Generic->new;

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

$header = new_headerLong->new( $parser->stdf2header($td) );
my $mir = $td->EMIR;
my $program = $mir->{SPEC_NAM};

$header->PRODUCT($mir->{SPEC_NAM}) if ($header->{PRODUCT} eq "");
$header->EQUIP6_ID( "$facility" );
$header->CFG_TESTER_TYPE($hOptions{CONFIG});

## initialize program class based on finallot arg value ###
if($hOptions{FINALLOT} || $hOptions{RELLOT}) {
	$header->PROGRAM_CLASS(2);
}else {
	$header->PROGRAM_CLASS(1);
}

#$lotid = $header->{LOT};
$header->PROGRAM($program);
$header->isFinalLot( $hOptions{FINALLOT} );
$header->isRelLot( $hOptions{RELLOT} );

# Capture Rel Attributes
if ($hOptions{RELLOT}){
	my $base_fn = basename($infile);
           $base_fn =~ s/\.DTA.*+//ig;
        my @item = split /\_/, $base_fn;
	my $qpnum;
        my $devchar;
        my $lotchar;
        my $strname;
        my $strdur;
        my $temp;
        my $dtype;

	if ($site eq "szrel") {
        	$strname = $item[1];
        	$strdur = $item[2];
        	$temp = $item[3];
        	$dtype = $item[4];
		$dtype = "" if $dtype =~ /[0-9]/;
		if ($item[0] =~ /^20/) {
			$qpnum = substr $item[0], 0, 8;
			$devchar = substr $item[0], 8, 1;
			$lotchar = substr $item[0], 9, 1;
			$header->LOT($qpnum.$devchar.$lotchar);
		}
		elsif ($item[0] =~ /^U/ ) {
			$qpnum = substr $item[0], 0, 6;
			$lotchar = substr $item[0], 6, 1;
			$header->LOT($qpnum.$lotchar);
		}
	}
	elsif ($site eq "bkrel") {
                $strname = $item[1];
                $strdur = $item[2];
                $temp = $item[3];
                $dtype = $item[4];	
		$dtype = "" if $dtype =~ /[0-9]/;
		if ($item[0] =~ /^20/) {
			$qpnum = substr $item[0], 0, 8;
			$devchar = substr $item[0], 8, 1;
			$lotchar = substr $item[0], 9, 1;
			$header->LOT($qpnum.$devchar.$lotchar);
		}
		else {
			$qpnum = substr $item[0], 0, 6;
			if ($item[0] =~ /^K/i ){
				$lotchar = substr $item[0], 6, 1;
			}
			else {
				$lotchar = substr $item[0], 5, 1;
			}
			$header->LOT($qpnum.$lotchar);
		}
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

unless ( $header->populateMeta ) {
    	$wr->noMeta(1);
    	$reglim_flg = "N";
}

$model->header($header);

my $sbr = $td->SBR;
my $sbr_each = $td->SBR_each;

if(@$sbr > 0)
{
	$sbins = $parser->sbr2bins( $td->SBR );
}
elsif($sbr_each > 0)
{	
	$sbins = $parser->sbr2bins( $td->SBR_each );
}

my $hbr = $td->HBR;
my $hbr_each = $td->HBR_each;

if(@$hbr > 0)
{
	$hbins = $parser->hbr2bins( $td->HBR );
}
elsif($sbr_each > 0)
{	
	$hbins = $parser->hbr2bins( $td->HBR_each );
}

my $str_limit;

foreach my $stdfWafer ( @{ $td->wafers } ) {
    	my $wafer = new_wafer;
    	$wafer->START_TIME( $header->START_TIME );
    	$wafer->END_TIME( $header->END_TIME );
    	my $waferNum = -1;
    	if ( defined $stdfWafer->WIR ) {
        	$waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
        	$wafer->number($waferNum);
		$wafer->name(repNA($header->LOT)."_".$waferNum);
        	if ( defined $stdfWafer->WIR->{START_T} and $stdfWafer->WIR->{START_T} > 1000000000 )
        	{
            		$wafer->START_TIME( $stdfWafer->WIR->{START_T} );
        	}
        	if ( defined $stdfWafer->WRR->{FINISH_T} and $stdfWafer->WRR->{FINITSH_T} > 1000000000 )
        	{
            		$wafer->END_TIME( $stdfWafer->WRR->{FINISH_T} );
        	}
    	}
	
    	if ( @{ $stdfWafer->WSBR } ) {
        	$wsbins = $parser->sbr2bins( $stdfWafer->WSBR );
    	}
	else{
		$wsbins = ();
	}
	
	my $sbinHash = $parser->res2binHash($stdfWafer->res);

	foreach my $binNumber (sort {$a <=> $b} keys %$sbinHash) {
		 push @$wsbins, $sbinHash->{$binNumber};
	}

    	$wafer->sbins($wsbins);
    	$wafer->tests($tests);
    	$wafer->dies( $parser->res2dies_fet_sort( $stdfWafer->res, $tests ) );
    	$model->add( 'wafers', $wafer );
}

$model->sbins($sbins);
$model->hbins($hbins);
$model->wmap($wmap);

&normalizeToBaseUnit($model);

if(!($hOptions{FINALLOT}) && !($hOptions{RELLOT})) {
	my $wmap = $model->updateWMap;
	if(defined $wmap)   {
		INFO("MAP IS DEFINED");
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
		INFO("MAP IS NOT DEFINED");
		$wmap = new_wmap;	
		$wr->wmapIsEmpty(1) unless ( !$wmap->isEmpty );
		$wr->noWMap(1);
		$reglim_flg = "N";
		$model->wmap($wmap);	
	}
}



### Use program naming rule
if ($hOptions{FINALLOT} || $hOptions{RELLOT}){
	$model->updateProgram;
}
else {
	$model->updateProgram("MAP_PGM");
}


my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);
$formatter->dataItems([qw/x y site partid hard_bin soft_bin/]);
$formatter->printPar;

# Limits
#if ($reglim_flg eq "Y") {
#	if ( $model->isLimitNew ) {
#	    	$model->buildLimit;
#	    	$formatter->printLimit;
#	    	$model->limit->input_file(basename $infile); 
#	    	$model->limit->registerRefdb;
#	}
#}
#else {    #always generate but do not register limit if sandbox
	$model->buildLimit;
	$formatter->printLimit;
	$model->limit->input_file(basename $infile);
#}

unless (isLogDebug) {
    	unlink $TD_bin;
    	unlink $TD_txt;
    	unlink $TP_bin;
    	unlink $TP_txt;
}

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

dpExit(0);

sub getLotFromFilename() {
	my $file = shift;
	my $base_fn = basename($file);
	my @dummy = split /\_|\./, $base_fn;
	my $lotid = $dummy[0];
	if ($lotid =~ /^A0/i && length($lotid) > 10) {
		$lotid   = substr($lotid,0,10);
	}
  return $lotid;
}

