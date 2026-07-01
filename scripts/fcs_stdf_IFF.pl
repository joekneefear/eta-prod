#!/usr/bin/env perl_db
# SVN $Id: fcs_stdf_IFF.pl 2196 2017-05-30 06:33:52Z dpower $

=pod

=head1 SYNOPSIS

  fcs_stdf_IFF.pl <Input flie name>
      --out <output dir>  same dir as input file by default
      --loc <location e.g CP, ISTI_TW>
      --config <config_tester_type>
      [--finallot]
      [--logfile <logfilepath>]  
      [--debug|--trace]
      [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will read BSTDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/03/09 kazukik: Modify to use standard Meta Lookup format to standard
 2015/04/21 kazukik: get Bin PF from PRR
 2015/05/13 grace  : add normalizeToBaseUnit, add desc for tests
 2015/05/13 grace  : to apply desc of tests for only stdf
 2015/05/29 grace  : Added support for -v option.
 2015/06/05 grace  : remove desc from testitem for output
 2015/07/07 eric   : added LOC arg and pass it as EQUIP6_ID.
 2015/07/09 eric   : use TP naming rule.
 2015/11/19 eric   : always generate but do not register limit if sandbox
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
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;

our $VERSION = "

1.0
";
our $TESTER  = "Stdf";

# a hash to receive options
my (%hOptions) = ();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions, "OUT=s", "LOC=s", "CONFIG=s", "FINALLOT", "LOGFILE=s", "DEBUG", "TRACE","V"
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

my @required_options = qw/OUT LOC/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions );

# check input file
my $infile = $ARGV[0];
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
my $td     = readStdfAscii($TD_txt);
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());
my $reglim_flg = "Y";

# create parser
my $parser = PDF::Parser::Stdf::Generic->new;

my $header  = new_headerLong->new( $parser->stdf2header($td) );
my $program = $header->PROGRAM;
$program = basename $program;
$header->PROGRAM($program);
$header->EQUIP6_ID($hOptions{LOC});
$header->CFG_TESTER_TYPE($hOptions{CONFIG});
$header->isFinalLot( $hOptions{FINALLOT} );
unless ( $header->populateMeta ) {
    $wr->noMeta(1);
    $reglim_flg = "N";
}

my $model = new_model;
$model->header($header);
$model->dataSource('STDF');

my $wmap = $model->updateWMap;
if (!($hOptions{FINALLOT})){
	if (defined $wmap) {
		unless ( ! $wmap->isEmpty ){
			$wr->wmapIsEmpty(1);
			$reglim_flg = "N";
		}
        	unless ( $wmap->confirmed ) {
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
}

if ($hOptions{FINALLOT}) {
	$model->updateProgram;
}
else {
	$model->updateProgram("MAP_PGM");
}

my $sbins = $parser->sbr2bins( $td->SBR );
my $hbins = $parser->hbr2bins( $td->HBR );
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
    }
	
	## wsbins
    if ( @{ $stdfWafer->WSBR } ) {
        $wsbins = $parser->sbr2bins( $stdfWafer->WSBR );
    }
		
    if ( !defined $wsbins or !@$wsbins ) {
        my $sbinHash = $parser->res2binHash( $stdfWafer->res );
        foreach my $binNumber ( sort { $a <=> $b } keys %$sbinHash ) {
            push @$wsbins, $sbinHash->{$binNumber};
        }
    }
    else {
        $wsbins = $parser->updateBinPF( $wsbins, $stdfWafer->res );
    }
	
	## whbins	
	if ( @{ $stdfWafer->WHBR } ) {
        $whbins = $parser->hbr2bins( $stdfWafer->WHBR );
    }
	
	 if ( !defined $whbins or !@$whbins ) {
        my $hbinHash = $parser->res2hbinHash( $stdfWafer->res );
        foreach my $binNumber ( sort { $a <=> $b } keys %$hbinHash ) {
            push @$whbins, $hbinHash->{$binNumber};
        }
    }
    else {
        $whbins = $parser->updatehBinPF( $whbins, $stdfWafer->res );
    }

    my $tests = $parser->res2tests( $stdfWafer->res );
    $wafer->sbins($wsbins);
    $wafer->hbins($whbins);
    $wafer->tests($tests);
    $wafer->dies( $parser->res2dies( $stdfWafer->res, $tests ) );
    $model->add( 'wafers', $wafer );
}

$model->sbins($sbins);
$model->hbins($hbins);
	
&normalizeToBaseUnit($model);

my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);

$formatter->testItems([qw/number name units /]);
$formatter->printPar;

# Limits
#if ($reglim_flg eq "Y") {
#	if ( $model->isLimitNew ) {
#	    $model->buildLimit;
#	    $formatter->printLimit;
#	    $model->limit->registerRefdb;
#	}
#}
#else {   #always generate but do not register limit if sandbox
	$model->buildLimit;
	$formatter->printLimit;
#}

unlink $TD_txt unless (isLogDebug);

dpExit(0);

