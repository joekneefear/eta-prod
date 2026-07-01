#!/usr/bin/env perl_db
# SVN $Id: fcs_fet_stdf_IFF.pl 2624 2020-10-08 07:47:50Z dpower $

=pod

=head1 SYNOPSIS

  fcs_fet_stdf_IFF.pl <Input flie name>
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

 2018/01/25 eric 	: new creation
 2018/02/08 eric	: extract lot from filename
 2018/05/15 eric	: make source lot as wafer name
 2018/05/15 eric	: fix bug for parsing wafer name	
 2018/09/21 eric	: use zip archive filename for iff output file
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

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
our $TESTER  = "FET";

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
        \%hOptions, "LOC=s", "OUT=s", "FORK=s", "FACILITYFILE=s", "FINALLOT", "LOGFILE=s", "DEBUG", "TRACE", "DATASOURCE=s","CONFIG=s", "PPLOG"
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
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");

# check input file
my $infile = $ARGV[0];
$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    pod2usage(3);
}

# unzip file
my $stdf = "";
my $ext_dir = dirname $infile;
	
my $ae = Archive::Extract->new(archive => $infile);
my $ok = $ae->extract( to => $ext_dir) or die->error;

foreach my $file (@{$ae->files}) {
	if ($file =~ /\.stdf/i) {
		$stdf = "${ext_dir}/${file}";
	}
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

my $TD_txt = convertBinToAscii($stdf);
my $td = readStdfAscii($TD_txt);

my $good_count;
my $reglim_flg = "Y";

# create parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $header  = new_headerLong->new( $parser->stdf2header($td) );
my $cfg_tstr_typ = $hOptions{CONFIG};
my $program = $header->PROGRAM;
   $program =~ s/\.TES//i;
   $header->PROGRAM($program);
   $header->EQUIP6_ID($facility);
   $header->PROGRAM_CLASS(1);
   $header->CFG_TESTER_TYPE($cfg_tstr_typ);
   $header->isFinalLot( $hOptions{FINALLOT} );

# extract lot from filename
my $base_fn = basename $infile;
my @fn_item = split /\_/, $base_fn;
$header->LOT(trim($fn_item[0]));

unless ( $header->populateMeta ) {
    	$wr->noMeta(1);
    	$reglim_flg = "N";
}

my $model = new_model;
   $model->header($header);
   $model->dataSource("FET");
   $pplogger->setModelHeader($model);

my $wmap = $model->updateWMap;
if (defined $wmap) {	
    	unless ( ! $wmap->isEmpty ){
        	$wr->wmapIsEmpty(1);
        	$reglim_flg = "N";
	}

    	unless ( $wmap->confirmed ){
        	$wr->noWMap(1);
        	$reglim_flg = "N";
    	}
}
else {
        $wmap = new_wmap;
        $wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
        $wr->noWMap(1);
        $reglim_flg = "N";
        $model->wmap($wmap);
}

$model->updateProgram("MAP_PGM");

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
	else {
		$waferNum = $td->MIR->{SBLOT_ID};
		$wafer->number($waferNum);
		if(!($hOptions{FINALLOT}) && $header->SOURCE_LOT ne "") {
                        $wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
                        $pplogger->setWaferFlag(1);
                }
		$wafer->START_TIME( $td->MIR->{START_T});
		$wafer->END_TIME($td->MIR->{FINISH_T});
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
$formatter->dataItems([qw/x y site partid hard_bin soft_bin/]);
$formatter->binItems ([qw/number name PF count/]);
$formatter->printPar;

# generate limits
$model->buildLimit;
$formatter->printLimit;
$model->limit->input_file(basename $infile);

#remove temp file
unlink $TD_txt unless (isLogDebug);

#remove extracted files after assigning
foreach my $file (@{$ae->files}) {
	$file = "${ext_dir}/${file}";
        unlink $file;
}


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


