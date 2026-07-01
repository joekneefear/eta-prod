#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_cdep_csv_IFF.pl <Input flie name>
	--out <output dir>
	--loc <location e.g CP, SZ, ME>
        --facilityfile <$DPSCRIPT/facilityMapping.ini>
      	[--logfile <logfilepath>]
      	[--debug|--trace]
	[--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> 

=head1 AUTHOR

B<eric.alfanta@onsemi.com>

=head1 CHANGES

 2018-Nov-27 eric       : create
 2020/09/01 karen       : added support to fork and qde output (IFF)/files to designated location
 2021/04/20 glory        : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
 

=head1 LICENSE

(C) ON Semiconductor Inc. 2016 All rights reserved.

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
use PDF::Parser::CZ;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PDF::Util::AddTestFlowtoTPUsingRef qw/addTestFlowtoTP load_testflow_ref/;
use PPLOG::PPLogger; 	
use Config::Tiny;

our $VERSION = "1.0";
our $TESTER  = "CZ";
my (%hOptions) = ();
my $pplogger = new PPLOG::PPLogger();
my $reglim_flg = "Y";

# Read arguments
if ( $#ARGV < 0 ) {
    	pod2usage();
    	dpExit( 1, "No input file specified" );
}
unless (
    	GetOptions( \%hOptions, "OUT=s","FORK=s", "SITE=s", "LOC=s", "FACILITYFILE=s", "FINALLOT","LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG", "QDE" )
    	)
{
    	dpExit( 1, "invalid options" );
}
 
if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1); 
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $facility = $config->{$location}->{finalTest};
INFO("FACILITY|EQUIP6_ID=$facility");


# Read input file
my $infile = $ARGV[0];
my $site = $hOptions{SITE};

INFO ("Infile = $infile");

$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    	pod2usage();
    	dpExit( 1, "input file does not exist $infile" );
}


my $parser = PDF::Parser::CZ->new;
my ($td,$tp) = $parser->readFile($infile, isLogDebug);

foreach my $lot ( sort keys %$td) {
	INFO("Fork dir=$hOptions{FORK}");
	my $wr = PDF::DpWriter->new(
    	{   
		outdir   => $hOptions{OUT},
		forkdir => $hOptions{FORK},
        	qde => $hOptions{QDE},
		basename => ( basename $infile),
        	ext      => 'iff',
                gzipIFF  => 'Y'
    	});

	my $header = new_headerLong;
	my $model = new_model ({
		header => $header,
		misc => {},
		dataSource => 'CZ'
	});

	my $wafer = new_wafer;
	$model->add('wafers', $wafer );

	foreach my $unitid (sort keys %{$$td{$lot}}) {
		$header = $model->header;
		$header->VERSION($VERSION);
		$header->isFinalLot($hOptions{FINALLOT});
		$header->LOT($lot);
		$header->FAMILY($$td{$lot}{$unitid}{FAMILY});
		$header->TECHNOLOGY($$td{$lot}{$unitid}{TECHNOLOGY});
		$header->PROCESS($$td{$lot}{$unitid}{PROCESS});
		$header->PRODUCT($$td{$lot}{$unitid}{PRODUCT});
		$header->PROGRAM($$td{$lot}{$unitid}{PROGRAM});
		$header->REVISION($$td{$lot}{$unitid}{REVISION});
		$header->PROGRAM_CLASS(2);
		$header->START_TIME($$td{$lot}{$unitid}{START_T});
		$header->END_TIME($$td{$lot}{$unitid}{END_T});
		$header->SOURCE_LOT($$td{$lot}{$unitid}{SOURCE_LOT});
		$header->EQUIP1_ID("CZ");
                $header->EQUIP6_ID($facility);


		$pplogger->setModelHeader($model);

		my $die = $wafer->find('dies',{partid=>$unitid});
                unless (defined $die){
                	$die = new_die( { partid => $unitid } );
                        $die->partid($unitid);
                        $wafer->add('dies',$die);
                 }

		my $res_addr = $$td{$lot}{$unitid}{RESULT};

		for (my $j=0; $j<=$#$res_addr; $j++) {
			$die->add('result',repNA(trim($$res_addr[$j])));
		}

	}  #end unitid loop

	unless ( $header->populateMeta ){
		$wr->noMeta(1);
	}

	if (!($hOptions{FINALLOT})) {
        	my $wmap = $model->updateWMap;
        	unless ( ! $wmap->isEmpty ){
                	$wr->wmapIsEmpty(1);
                	$reglim_flg = "N";
        	}
        	unless ( $wmap->confirmed ){
                	$wr->noWMap(1);
                	#$reglim_flg = "N";
        	}

        	#assign source lot as wafer name
        	if ($header->SOURCE_LOT ne "") {
                	$model->wafers->[0]->name($header->SOURCE_LOT."_".sprintf("%02d",$model->wafers->[0]->number));
                	$pplogger->setWaferFlag(1);
        	}

	}

	my $program = $header->PROGRAM;

	if ( length($program) > 45 )
	{
	        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
	        $wr->forSBox(1);
	        $program = substr($program, 1, 45); # Leave enough room for session type
	}

	$header->PROGRAM($program);

	if ($hOptions{FINALLOT}){
		$model->updateProgram;
	}
	else {
	        $model->updateProgram("MAP_PGM");
	}

	my $tnam_addr = $$tp{$lot}{TEST_NAM};
	my $tnum_addr = $$tp{$lot}{TEST_NUM};
        my $tcon_addr = $$tp{$lot}{TEST_COND};
        my $hlim_addr = $$tp{$lot}{HILIM};
        my $llim_addr = $$tp{$lot}{LOLIM};
	my $unit_addr = $$tp{$lot}{TEST_UNIT};

        my $limit = new_limit;
        #for (my $i=0; $i<=$#$tnam_addr; $i++){
	for (my $i=0; $i<=$#$tnum_addr; $i++){
        	my $test = new_test;
                #$test->number($i+1);
		$test->number(repNA(trim($$tnum_addr[$i])));
                $test->name(repNA(trim($$tnam_addr[$i])));
                $test->HSL(repNA(trim($$hlim_addr[$i])));
                $test->LSL(repNA(trim($$llim_addr[$i])));
                $test->units(repNA(trim($$unit_addr[$i])));
                $test->add('conditions',repNA(trim($$tcon_addr[$i])));
                $limit->add('tests', $test);
                $model->add('tests', $test);
        }

        #&normalizeToBaseUnit($model);

	my $formatter = new_iff_formatter({
	   	model  => $model,
        	writer => $wr
    	});


	$formatter->dataItems([qw/partid/]);
	$formatter->testItems([qw/number name units/]);
	$formatter->printPar_v3($lot);   #create iff per lot

	#generate limit
	$model->buildLimit;
	$model->limit->conditionNames([qw/testCond /]);
	$formatter->printLimit;
	$model->limit->input_file(basename $infile);

} #end lot loop
	
dpExit(0);
