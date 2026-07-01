#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_rs75_csv_IFF.pl <Input flie name>
	--out <output dir>
	--loc <location e.g CP, SZ, ME>
	--xyref <xy coord ref file.
	[--finallot]
      	[--logfile <logfilepath>]
      	[--debug|--trace]
	[--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> 

=head1 AUTHOR

B<eric.alfanta@onsemi.com>

=head1 CHANGES

 2017/May/09 eric       : create
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021-Apr-21 Karen	: get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
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
use PDF::Parser::RS75;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PDF::Util::AddTestFlowtoTPUsingRef qw/addTestFlowtoTP load_testflow_ref/;
use PPLOG::PPLogger; 	
use Config::Tiny;

our $VERSION = "1.0";
our $TESTER  = "RS75";
my (%hOptions) = ();
my $pplogger = new PPLOG::PPLogger();
my $location    = "";

# Read arguments
if ( $#ARGV < 0 ) {
    	pod2usage();
    	dpExit( 1, "No input file specified" );
}
unless (
    	GetOptions( \%hOptions, "OUT=s", "FORK=s", "FACILITYFILE=s", "XYREF=s", "SITE=s", "LOC=s", "LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG" )
    	)
{
    	dpExit( 1, "invalid options" );
}
 
if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT LOC FACILITYFILE XYREF/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1); 
}
my $location = $hOptions{LOC};
my $xyref = $hOptions{XYREF};
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $facility = $config->{$location}->{probe};
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

my $parser = PDF::Parser::RS75->new;
my $model = $parser->readFile($infile, $xyref, isLogDebug);

&normalizeToBaseUnit($model);

my $header = $model->header;

unless ( $header->populateMeta ){
	$wr->noMeta(1);
}

if ($header->SOURCE_LOT ne ""){
	$model->wafers->[0]->name($header->SOURCE_LOT."_".sprintf("%02d",$model->wafers->[0]->number));
}

$header->VERSION($VERSION);
$header->EQUIP1_ID("RS75");
$header->EQUIP6_ID("$facility");
$header->PROGRAM_CLASS(23);

if ( $model->forSBflag == 1 ) {
        $wr->forSBox($model->forSBflag);
}

$pplogger->setModelHeader($model);
$pplogger->setWaferFlag(1);

my $program = "PEPI_RS"."::".$header->PROCESS;
my $rev	= 0;

if ( length($program) > 45 )
{
        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
        $wr->forSBox(1);
        $program = substr($program, 1, 45); # Leave enough room for session type
}

$header->PROGRAM($program);
$header->REVISION($rev);
$model->updateProgram;

my $formatter = new_iff_formatter(
	{   model  => $model,
            writer => $wr
	}
);
		
$formatter->dataItems([qw/site partid x y/]);
$formatter->testItems([qw/number name units/]);
$formatter->printPar;

#generate limit
$model->buildLimit;
$formatter->printLimit;
$model->limit->input_file(basename $infile);
	
dpExit(0);
