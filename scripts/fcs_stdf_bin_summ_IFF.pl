#!/usr/bin/env perl_db
# SVN $Id: fcs_stdf_bin_summ_IFF.pl 2196 2017-05-30 06:33:52Z dpower $

=pod

=head1 SYNOPSIS

  fcs_stdf_bin_sum_IFF.pl <Input flie name>
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

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/04/30 grace :  new creation
 2015/06/25 grace :  When SBIN doesn't have pass, need to get pass from HBIN  by Rodney's request  (for SZTESTER)
 2015/07/07 grace :  if there isn't pass from HBIN, Use WRR.GOOD_CNT as the bin qty when there is wafer data and MRR.GOOD_CNT when there is no wafer data.
 2015/07/06 jgarcia : added to accept location.
 2015/07/27 grace :  Added config option
 2015/11/19 eric  : always generate but do not register limit if sandbox
 2016/02/22 eric  : modified to handle finallot arg. use pplog
 2017-May-30 gilbert : generate limits always and dont register in refdb.pp_limits
 
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
use PPLOG::PPLogger;    # wsanopao:

our $VERSION = "1.0";
our $TESTER  = "Stdf";

# a hash to receive options
my (%hOptions) = ();
my $hbins = ();
my $sbins = ();
my $wsbins = ();
my $whbins = ();
my $location = "";

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions, "LOC=s", "OUT=s", "FINALLOT", "LOGFILE=s", "DEBUG", "TRACE", "DATASOURCE=s","CONFIG=s", "PPLOG"
    )
    )
{
    dpExit( 1, "invalid options" );
}

# Initialize logging

my @required_options = qw/OUT LOC/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions,$pplogger );
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

$location = $hOptions{LOC};

# check input file
my $infile = $ARGV[0];
# wsanopao: Set Raw File ==> infile and Environment ==> $site._eagle
$pplogger->setRawFile($infile);
#$pplogger->setEnv($site,'eagle');

if ( !-f $infile ) {
    pod2usage(3);
}

# create Writer
my $wr = PDF::DpWriter->new(
    {   basename => ( basename $infile),
        ext      => 'iff',
        outdir   => $hOptions{OUT}
    }
);

my $TD_txt = convertBinToAscii($infile);
my $td = readStdfAscii($TD_txt);

my $good_count;
my $reglim_flg = "Y";
# = $td->MRR->{GOOD_CNT};

# create parser
my $parser = PDF::Parser::Stdf::Generic->new;

my $header  = new_headerLong->new( $parser->stdf2header($td) );
my $cfg_tstr_typ = $hOptions{CONFIG};
my $program = $header->PROGRAM;
   $program = basename $program;
   $header->PROGRAM($program);
   $header->EQUIP6_ID($location);
   $header->PROGRAM_CLASS(8);
   $header->CFG_TESTER_TYPE($cfg_tstr_typ);
   $header->isFinalLot( $hOptions{FINALLOT} );

unless ( $header->populateMeta ) {
    $wr->noMeta(1);
    $reglim_flg = "N";
}


my $sbins;
my $hbins;
my $tests = $parser->res2tests_tsr( $td->TSR );	
my $model = new_model;
   $model->header($header);
   $model->dataSource($hOptions{DATASOURCE});

   # wsanopao: Passing Reference of Model
   $pplogger->setModelHeader($model);

if (!($hOptions{FINALLOT})) {
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

### Use program naming rule
if ($hOptions{FINALLOT}){
    $model->updateProgram;
}
else {
    $model->updateProgram("MAP_PGM");
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
	}

	if ( !defined $wsbins or !@$wsbins ) {
		my $binHash = $parser->res2binHash( $stdfWafer->res );
		foreach my $binNumber ( sort { $a <=> $b } keys %$binHash ) {
			push @$wsbins, $binHash->{$binNumber};
		}
	}

	if($wsbins ne "")
	{
		$wafer->sbins($wsbins);		
	}

	if ( @{ $stdfWafer->WHBR } ) {
		$whbins = $parser->hbr2bins( $stdfWafer->WHBR, $good_count);
	}
	
	if ( !defined $whbins or !@$whbins ) {		
		my $binHash = $parser->res2hbinHash( $stdfWafer->res );
		foreach my $binNumber ( sort { $a <=> $b } keys %$binHash ) {
			push @$whbins, $binHash->{$binNumber};
		}
	}		

	if ($whbins ne "")
	{
		$wafer->hbins($whbins); 
	}
	
	if(@$tests <0)
	{
		$tests = $parser->res2tests_tsr( $stdfWafer->WTSR );	
	}
	$wafer->tests($tests);

=pod	
logic:
only TSR, load it
only WTSR, load it
TSR + WTSR for 1 wafer, load WTSR only
TSR + WTSR for full lot, load both

=cut
	if(@{$stdfWafer->WTSR} eq 0){
		$wafer->dies( $parser->res2dies_sum( $td->TSR, $tests ,"lot") );		
	}
	else{
		$wafer->dies( $parser->res2dies_sum( $stdfWafer->WTSR, $tests ,"wafer") );		
	}
	
	if(@{ $td->wafers }  > 1){
		$model->dies(  $parser->res2dies_sum( $td->TSR, $tests ,"lot"))
	}
	
	#INFO("wtsr count:".@{$stdfWafer->WTSR});
	#INFO("TSR count:".@{$td->TSR});
	#INFO("wafer count:". @{ $td->wafers } );
    
    $model->add( 'wafers', $wafer );
}	

if($good_count eq "" or $good_count == 0)
{
	$good_count = $td->MRR->{GOOD_CNT};
}

if ($whbins eq "")
{
	getBinSummary($td->HBR, $td->HBR_each, $good_count, 'hbr');	
	$model->hbins($hbins);
}

if ($wsbins eq ""){
	getBinSummary($td->SBR, $td->SBR_each, $good_count, 'sbr');
	$model->sbins($sbins);
}

	
my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);

$formatter->binItems ([qw/number name PF count/]);
$formatter->printPar;

# Limits
#if ($reglim_flg eq "Y") {
#	if($model->isLimitNew){
#		$model->buildLimit;
#		$formatter->printLimit;
#		$model->limit->input_file(basename $infile); 
#		$model->limit->registerRefdb;
#	}
#}
#else { # always generate but do not register limit if sandbox
	$model->buildLimit;
	$formatter->printLimit;
	$model->limit->input_file(basename $infile);
#}

unlink $TD_txt unless (isLogDebug);

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
	}else{
		$hbins = $parser->hbr2bins( $bin_each, $good_count );
	}
  }
}

dpExit(0);

