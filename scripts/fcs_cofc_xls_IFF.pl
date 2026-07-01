#!/usr/bin/env perl_db
# SVN $Id: fcs_cofc_xls_IFF.pl
=pod

=head1 SYNOPSIS

      fcs_cofc_xls_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
      --loc <location>
      --facilityfile <$DPSCRIPT/facilityMapping.ini>
      [-config <config_tester_type>]
      [--logfile <logfilepath>]
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read XLS file and output IFF file

=head1 AUTHOR

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

2016-Feb-18 Eric	: new
2016-May-3  Eric	: pass location in reading file
2017-May-18 Gilbert     : generate limits always and dont register in refdb.pp_limits
2017-Aug-18 Eric	: fixed script to handle misaligned specs against the measurement data
2017-Aug-24 Eric	: use product number as product for GLOBITECH
2019-Jun-07 Eric	: append delivery number to lot id
2020/09/01 karen        : added support to fork output (IFF)/files to designated location
2021/04/14 glory        : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

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
use PDF::DAO;
use PDF::Parser::COFC_xls;
use PDF::Formatter;
use PDF::DpWriter;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);
use Time::localtime;
use File::stat;
use Time::Piece;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger;
use Config::Tiny;

our $VERSION = "1.0";
our $TESTER  = "COC";

# a hash to receive options
my (%hOptions) = ();
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions,  "OUT=s", "FORK=s", "FINALLOT", "PPLOG",
        "LOGFILE=s", "DEBUG", "TRACE", "V", "TYPE=s", "LOC=s", "FACILITYFILE=s", "CONFIG=s",
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
my @required_options = qw/OUT LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions,$pplogger );
if ($hOptions{PPLOG}){
        $pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location     = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");


# Read input file
my $infile = $ARGV[0];
# wsanopao: Set Raw File ==> infile and Environment ==> $site._eagle
$pplogger->setRawFile($infile);
#$pplogger->setEnv($site,'substrate');

if ( !-f $infile ) {
    dpExit( 1, "input file does not exist $infile" );
}

INFO("infile  = $infile");

my $parser = PDF::Parser::COFC_xls->new;
#my ($td, $limit) = $parser->readFile($infile,$location,isLogDebug);
my $td = $parser->readFile($infile,$location,isLogDebug);
my $lot_cnt= 0;
foreach my $itemno ( sort keys %$td) {
	#next if $$td{$itemno}{LOTID} eq "";
	$lot_cnt++;
	INFO("Fork dir=$hOptions{FORK}");
	my $wr = PDF::DpWriter->new(
    	{
		outdir   => $hOptions{OUT},
		forkdir => $hOptions{FORK},
        	basename => ( basename $infile),
        	ext      => 'iff',
                gzipIFF  => 'Y'
    	}
	);

	my $header = new_headerLong;
	my $model = new_model (
    	{
        	header => $header,
        	misc   => {},
        	dataSource => 'COC'
    	}
    	);

	$header = $model->header;
	$header->LOT($itemno."_".$$td{$itemno}{EQUIP2});
	$header->START_TIME($$td{$itemno}{START_T});
	$header->END_TIME($$td{$itemno}{END_T});
	$header->PROGRAM($$td{$itemno}{PROG});
	$header->REVISION($$td{$itemno}{REV});
	if ($location eq "GLOBITECH_US" ) {
		$header->PRODUCT($$td{$itemno}{PRODUCT_NUM});
	}
	else {
		$header->PRODUCT($$td{$itemno}{PRODUCT});
	}
	$header->EQUIP1_ID($$td{$itemno}{EQUIP1});
	$header->EQUIP2_ID($$td{$itemno}{EQUIP2});
	$header->EQUIP5_ID($$td{$itemno}{EQUIP5});
	$header->EQUIP6_ID($facility);
  $header->FAB($$td{$itemno}{VENDOR});
  $header->INDEX1($$td{$itemno}{SUBCONLOT});

    	# truncate ppid
	my $program = $header->PROGRAM;
	my $mat_type = "_".$$td{$itemno}{MAT_TYPE};
    	if (length($program) > 235) {
        	INFO("PROGRAM NAME \"".$program.$mat_type."\" will be truncated to 35 characters.  Sending to sandbox.");
        	$wr->forSBox(1);
        	$program = substr($program, 0, 235-length($mat_type));
    	}
    	$header->PROGRAM_CLASS(9);
    	$model->updateProgram;
	$header->PROGRAM($header->PROGRAM.$mat_type);

	my $wafer = $model->find('wafers',{number => 0});
    	unless (defined $wafer){
        	$wafer = new_wafer( { number => 0 } );
        	$model->add('wafers',$wafer);
    	}

	my $die = new_die;
	my $min_addr = $$td{$itemno}{MIN};
	my $max_addr = $$td{$itemno}{MAX};
	my $mean_addr = $$td{$itemno}{MEAN};
	my $sums_addr = $$td{$itemno}{SUMS};
	my $sqrs_addr = $$td{$itemno}{SQRS};
	my $sdev_addr = $$td{$itemno}{SDEV};
	my $cnt_addr = $$td{$itemno}{CNT};

	my $tnum_addr = $$td{$itemno}{TNUM};
	my $tnam_addr = $$td{$itemno}{TNAM};
	my $unit_addr = $$td{$itemno}{UNIT};
	my $hlim_addr = $$td{$itemno}{HLIM};
	my $llim_addr = $$td{$itemno}{LLIM};

	my $limit = new_limit;
        for (my $i=0; $i<=$#$tnum_addr; $i++){
                my $test = new_test;
                $test->number(repNA(trim($$tnum_addr[$i])));
                $test->name(repNA(trim($$tnam_addr[$i])));
                $test->units(repNA(trim($$unit_addr[$i])));
                $test->HSL(repNA(trim($$hlim_addr[$i])));
                $test->LSL(repNA(trim($$llim_addr[$i])));
                $limit->add('tests', $test);
        }

	$model->tests($limit->tests); #store test num, name, unit
	my $test_cnt = scalar @{$model->tests};

	#for (my $i=0; $i<=$#$min_addr; $i++){
	for (my $i=0; $i<=$test_cnt-1; $i++){
		$die->add('level',"lot");
		$die->add('min', repNA(trim($$min_addr[$i])));
		$die->add('max', repNA(trim($$max_addr[$i])));
		$die->add('mean', repNA(trim($$mean_addr[$i])));
		$die->add('sums', repNA(trim($$sums_addr[$i])));
		$die->add('sqrs', repNA(trim($$sqrs_addr[$i])));
		$die->add('sdev', repNA(trim($$sdev_addr[$i])));
		$die->add('cnt', repNA(trim($$cnt_addr[$i])));
	}
	$model->add('dies',$die);

	my $formatter = new_iff_formatter(
	{   	model  => $model,
        	writer => $wr
    	}
	);

	$formatter->dataItems([qw//]);
	$formatter->testItems([qw/number name units/]);
	#$formatter->printPar_v3($itemno);
	$formatter->printPar_v3($header->LOT);

	# Output Limit
	#if ($model->isLimitNew){
		$limit->copyHeader($header);
		$model->limit($limit);
		$model->buildLimit;
    		$formatter->printLimit;
	#	$model->limit->registerRefdb;
	#}
} #end of foreach

dpExit(0);
