#!/usr/bin/env perl_db
# SVN $Id: fcs_sic_cree_xls_IFF.pl 
=pod

=head1 SYNOPSIS

      fcs_sic_cree_xls_IFF.pl <Input flie name>
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
2017-May-30 Gilbert     : generate limits always and dont register in refdb.pp_limits
2019-Apr-10 Eric	: load delivery number as source lot. fix bug when the file has fewer limits than parameters
2020-Apr-18 Eric	: generate limits for every lot
2020-Apr-25 Eric	: pass tpdir option
2020/09/01 karen       : added support to fork output (IFF)/files to designated location
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
use PDF::Parser::Sic_xls;
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

our $VERSION = "

1.0
";
our $TESTER  = "SIC";

# a hash to receive options
my (%hOptions) = ();
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions,  "OUT=s", "FORK=s", "FINALLOT", "PPLOG", "TPDIR=s",
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
my @required_options = qw/OUT LOC TPDIR FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions,$pplogger );
if ($hOptions{PPLOG}){
        $pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
my $tpdir = $hOptions{TPDIR};
my $reglim_flg = "Y";
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");


# Read input file
my $infile = $ARGV[0];
# wsanopao: Set Raw File ==> infile and Environment ==> $site._eagle
$pplogger->setRawFile($infile);
#$pplogger->setEnv($site,'cree');

if ( !-f $infile ) {
    dpExit( 1, "input file does not exist $infile" );
}

INFO("infile  = $infile");
INFO("tpdir = $tpdir");

my $parser = PDF::Parser::Sic_xls->new;
my ($td,$tp) = $parser->readFile($infile,$tpdir,isLogDebug);

foreach my $itemno ( sort keys %$td) {
	next if $$td{$itemno}{LOTID} eq "";

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
	$header->LOT($$td{$itemno}{LOTID});
	$header->SOURCE_LOT($$td{$itemno}{EQUIP1}); #delivery no as source lot
	$header->START_TIME($$td{$itemno}{START_T});
	$header->END_TIME($$td{$itemno}{START_T});
	$header->isFinalLot($hOptions{FINALLOT});
	$header->VERSION($VERSION);
	$header->PROGRAM($$td{$itemno}{PROGRAM});
	$header->REVISION(1);     # set default program rev
	$header->PRODUCT($$td{$itemno}{PROGRAM});
	$header->PACKAGE($$td{$itemno}{CUST});
	$header->PROGRAM_CLASS(9);
	$header->STAGE($$td{$itemno}{NO_BX_BT});
	$header->STEP($$td{$itemno}{BX_BT_NO});
	$header->EQUIP1_ID($$td{$itemno}{EQUIP1});
	$header->EQUIP2_ID($$td{$itemno}{EQUIP2});
	$header->EQUIP3_ID($$td{$itemno}{EQUIP3});
	$header->EQUIP4_ID($$td{$itemno}{EQUIP4});
	$header->EQUIP5_ID($$td{$itemno}{EQUIP5});
	$header->EQUIP6_ID($facility);

        # truncate ppid
	my $program = $header->PROGRAM;
        if (length($program) > 35) {
                INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
                $program = substr($program, 1, 35);
        }
        $header->PROGRAM($program);
        $model->updateProgram;
	
	my $wafer = $model->find('wafers',{number => 0});
        unless (defined $wafer){
               $wafer = new_wafer( { number => 0 } );
               $model->add('wafers',$wafer);
        }
	my $die = $wafer->find('dies',{site=>$itemno});
        unless (defined $die){
               $die = new_die( { site => $itemno } );
               $die->partid( $itemno );
               $wafer->add('dies',$die);
        }
		
	my $tnam_addr = $$tp{TNAM};
        my $tnum_addr = $$tp{TNUM};
        my $unit_addr = $$tp{UNIT};
        my $hlim_addr = $$tp{HLIM};
        my $llim_addr = $$tp{LLIM};

        my $limit = new_limit;
        for (my $i=0; $i<=$#$tnam_addr; $i++){
                my $test = new_test;
                $test->number(repNA(trim($$tnum_addr[$i])));
                $test->name(repNA(trim($$tnam_addr[$i])));
                $test->units(repNA(trim($$unit_addr[$i])));
                $test->HSL(repNA(trim($$hlim_addr[$i])));
                $test->LSL(repNA(trim($$llim_addr[$i])));
                $limit->add('tests', $test);
        }	

	$model->tests($limit->tests); #store test num, name, unit
	&normalizeToBaseUnit($model);
	
	my $addr = $$td{$itemno}{READINGS};
	for (my $i=0; $i<=$#$addr; $i++){
		$die->add( 'result', repNA(trim($$addr[$i])) )	
	}

	my $formatter = new_iff_formatter(
		{   model  => $model,
        	    writer => $wr
        	}
	);

	$formatter->dataItems([qw/partid/]);
	$formatter->testItems([qw/number name units/]);
	$formatter->printPar_v3($$td{$itemno}{LOTID});

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
