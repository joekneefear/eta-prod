#!/usr/bin/env perl_db
# SVN $Id: fcs_powertech_stdf_IFF.pl 2622 2020-10-08 05:46:01Z dpower $

=pod

=head1 SYNOPSIS

  fcs_powertech_stdf_IFF.pl <Input flie name>
      --out <output dir>  same dir as input file by default
      --datasource 
      [--config <cfg_tester_type>]
      [--loc <location site>]
      [--finallot]
      [--logfile <logfilepath>]  
      [--debug|--trace]

=head1 DESCRIPTIONS

B<This script> will read STDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<eric.alfanta@onsemi.com>

=head1 CHANGES

 2018/05/25 eric 	: new creation
 2020/02/26 eric	: added else condition for CP site
 2020/07/23 eric	: identify CP prod lot by removing postfixes
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021-Apr-08 Karen	: get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
 2025-Jul-28 eric	: remove _POST from lotid so it can be loaded to production
=head1 LICENSE

(C) ON Semiconductor Inc. 2018 All rights reserved.

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
use File::Basename qw/basename dirname/;
use List::Util qw(first);
use POSIX qw(strftime);
use Archive::Extract;
use File::Copy;
use PPLOG::PPLogger;    
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use Config::Tiny;

our $VERSION = "1.0";
our $TESTER  = "QTEC";

# a hash to receive options
my (%hOptions) = ();
my $location = "";

# Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions, "LOC=s", "FORK=s", "OUT=s", "FACILITYFILE=s", "FINALLOT", "LOGFILE=s", "DEBUG", "TRACE", "DATASOURCE=s","CONFIG=s", "PPLOG"
    )
    )
{
    dpExit( 1, "invalid options" );
}

# Initialize logging
my @required_options = qw/OUT LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions,$pplogger );
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});

$location = $hOptions{LOC};

# check input file
my $infile = $ARGV[0];
$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    pod2usage(3);
}

# create Writer
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    	{   	
		basename => ( basename $infile),
        	ext      => 'iff',
        	outdir   => $hOptions{OUT},
		forkdir => $hOptions{FORK},
                gzipIFF  => 'Y' 
    	}
);

my $TD_txt = convertBinToAscii($infile);
my $td = readStdfAscii($TD_txt);
my $mir = $td->MIR;

my $good_count;
my $location     = $hOptions{LOC};
#my $site = $hOptions{SITE}
my $facility = "";
if($hOptions{FINALLOT}) {
	$facility = $config->{$location}->{finalTest};
}else {
	$facility = $config->{$location}->{probe};
}
INFO("FACILITY|EQUIP6_ID=$facility");

my $reglim_flg = "Y";

# create parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $header  = new_headerLong->new( $parser->stdf2header($td) );
my $cfg_tstr_typ = $hOptions{CONFIG};
   $header->EQUIP1_ID($header->{EQUIP1_ID}." ".$mir->{SERL_NUM});
   $header->EQUIP6_ID( "$facility" );
   $header->PROGRAM_CLASS(2);
   $header->CFG_TESTER_TYPE($cfg_tstr_typ);
   $header->isFinalLot( $hOptions{FINALLOT} );

if ($location eq "CP") {
	my $rev = $header->REVISION;
	my $lot = $header->LOT;
	
	if ($lot =~ /\_FT|\_QA|\_RESCREEN|\_POST/i) {
		my @item = split/\_/, $lot;
		$lot =  trim($item[0]);
		$header->LOT($lot);
		INFO("New Lot ID : $header->{LOT}");
	}

	INFO ("Test Program Revision pattern = $rev");
	if ($rev =~ /[A-Z]/i && $rev =~ /[0-9]/) {
		$rev =~ s/[A-Z]//ig;
	}
	else {
		$rev = $rev;
	}
	$rev = trim($rev);
	INFO ("New Test Program Revision = $rev");
	$header->REVISION($rev);
}

unless ( $header->populateMeta ) {
    	$wr->noMeta(1);
    	$reglim_flg = "N";
}

my $model = new_model;
   $model->header($header);
   $model->dataSource("QTEC");
   $pplogger->setModelHeader($model);

$model->updateProgram;

# Get sbin / hbin  information
my $sbins;
my $hbins;
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
		if(!($hOptions{FINALLOT}) && $header->SOURCE_LOT ne "") {
			$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
			$pplogger->setWaferFlag(1);
		}
        	if ( defined $stdfWafer->WIR->{START_T} && $stdfWafer->WIR->{START_T} > 1000000000 )
        	{
            		$wafer->START_TIME( $stdfWafer->WIR->{START_T} );
        	}
        	if ( defined $stdfWafer->WRR->{FINISH_T} && $stdfWafer->WRR->{FINITSH_T} > 1000000000 )
        	{
            		$wafer->END_TIME( $stdfWafer->WRR->{FINISH_T} );
        	}
		
    	}

	# Get test parameter from ptr
	my $tests = $parser->res2tests( $stdfWafer->res );
	$wafer->tests($tests);

	# Readings
	$wafer->dies( $parser->res2dies( $stdfWafer->res, $tests ) );
    
    	$model->add( 'wafers', $wafer );
}	

# store bins into model
$model->sbins($sbins);
$model->hbins($hbins);

# normalize unit and readings
&normalizeToBaseUnit($model);
	
# generate IFF
my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);

$formatter->dataItems([qw/site partid soft_bin hard_bin/]);
$formatter->binItems ([qw/number name PF count/]);
$formatter->printPar;

# generate limits
$model->buildLimit;
$formatter->printLimit;
$model->limit->input_file(basename $infile);

#remove temp file
unlink $TD_txt unless (isLogDebug);


dpExit(0);

sub getBinSummary{
  
  	my $bin = shift;
  	my $bin_each = shift;
  	my $g_cnt = shift;
  	my $mode = shift;
  	my $bins;
  
  	if(@$bin > 0)
  	{
		if($mode eq "sbr"){
			$bins = $parser->sbr2bins( $bin, $g_cnt );
		}
		else{
			$bins = $parser->hbr2bins( $bin, $g_cnt );
		}		
  	}
  	elsif(@$bin_each > 0)
  	{	
		if($mode eq "sbr"){
			$sbins = $parser->sbr2bins( $bin_each, $good_count );
		}
		else{
			$hbins = $parser->hbr2bins( $bin_each, $good_count );
		}
  	}
}


