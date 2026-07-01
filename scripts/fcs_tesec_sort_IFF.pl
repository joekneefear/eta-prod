#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_tesec_sort_IFF.pl <Input flie name>
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

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

2015-Dec-28 Eric	: new
2017-May-30 Gilbert     : generate limits always and dont register in refdb.pp_limits

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
use v5.10;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;

our $VERSION = "

1.0
";

our $TESTER  = "TESEC";
my (%hOptions) = ();
my $location = "";
my $site = "";
my $reglim_flg = "Y";
my $good_count;

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions, "OUT=s", "SITE=s", "LOC=s", "CONFIG=s", "FINALLOT", "LOGFILE=s", "DEBUG", "TRACE", "V"
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

my @required_options = qw/OUT SITE LOC/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions );

$location = $hOptions{LOC};
$site = $hOptions{SITE};

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
        outdir   => $hOptions{OUT}
    }
);

# create parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $perl = "perl";
my ( $TP_bin, $TD_bin );

# Convert source file to TP and TD
my $command = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_tesec_dta.pl -infile=$infile -env_mod=/home/dpower/project/scripts/stdf_perl/mtsort_tesec_env_mod.pm";

my @output = `$command`;
if ($?) {
    print "error in $command\n";
    dpExit( 1, "Failed to convert $command : $!" );
}
if ( $output[-1] =~ /td=(.*) tp=(.*)/ ) {
    $TD_bin = $1;
    $TP_bin = $2;
    INFO("TD=$TD_bin");
    INFO("TP=$TP_bin");
}
else {
    dpExit( 1, "Failed to convert $command : " . join( "#", @output ) );
}

my $TD_txt = convertBinToAscii($TD_bin);
my $TP_txt = convertBinToAscii($TP_bin);
my $td     = readStdfAscii($TD_txt);
my $tp     = readStdfAscii($TP_txt);

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
$header->EQUIP6_ID($location);
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
		$wafer->name(repNA($header->LOT)."_".$waferNum);
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
    if($wsbins ne "")
    {
        $wafer->sbins($wsbins);
    }
    if ( @{ $stdfWafer->WHBR } ) {
         $whbins = $parser->hbr2bins( $stdfWafer->WHBR, $good_count);
	 #$whbins = $parser->hbr2bins( $stdfWafer->WHBR);
    }
    if ($whbins ne "")
    {
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
#	    $model->buildLimit;
#	    $formatter->printLimit;
#	    $model->limit->input_file(basename $infile); 
#	    $model->limit->registerRefdb;
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

dpExit(0);
