#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_rh_mt_IFF.pl <Input flie name>
	--out <output dir>
	--testplanpath <test plan file path>
	--loc <location e.g. MT,CP>
	--type Process or Product
	[--logfile <logfilepath>]
	[--debug|--trace]
	[--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will read Reedholm Etest file and generate IFF file for dbascii

=head1 AUTHOR

B<jason.arp@pdf.com>

=head1 CHANGES

 2015/04/22 jason	: new creation
 2015/05/29 grace  	: Added support for -v option.
 2015/06/21 grace  : set value for input_file of PP_LIMITS
 2015/07/02 eric   : added LOC arg and pass it as EQUIP6_ID
 2015/07/28 jgarcia: initialize $header->PROGRAM_CLASS to 5.
 2015/07/28 jgarcia: check for Program name greater than 35 chars. ang truncate if greater.
 2015/11/19 eric   :  always generate but do not register limit if sandbox
 2015/11/23 jgarcia: Added TYPE param to indicate if Process or Product info to be added in Program.
 2016/02/26 wsanopao: logging pre-processing information  to refdb.pp_log table.
 30-May-2017 gilbert: generate limits always and dont register in refdb.pp_limits
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021-May-01 jgarcia	: get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
 2021-May-01 jgarcia : made sure that location is in Uppercase.
=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

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
use PDF::Parser::RH_MT;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;

our $VERSION = "

1.0
";
our $TESTER  = "REEDHOLM";

my (%hOptions) = ();
my $location    = "";

# wsanopao: Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "FORK=s", "LOC=s", "TESTPLANPATH=s", "FACILITYFILE=s", "TYPE=s", "LOGFILE=s", "DEBUG","V",
        "TRACE", "PPLOG", "QDE" )
    )
{
    dpExit( 1, "invalid options" );
}
if($hOptions{V})
{
	print("$VERSION\n");
	dpExit(0);
};

my @required_options = qw/OUT TESTPLANPATH LOC TYPE FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $testPlanDir = $hOptions{TESTPLANPATH};
my $location = uc($hOptions{LOC});

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$PPlogger->setRawFile($infile);

if ( !-f $infile ) {
    pod2usage();
    dpExit( 1, "input file does not exist $infile" );
}

# check output dir
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},
	qde => $hOptions{QDE},
        basename => ( basename $infile),
        ext      => 'iff',
        gzipIFF  => 'Y'
    }
);

INFO("infile  = $infile");

my $reglim_flg = "Y";
my $parser = PDF::Parser::RH_MT->new;
# peek in the file and get needed field to lookup test plan file
my $searchPath = "$testPlanDir/".$parser->GetProgramRev($infile)."*";
my @testPlans = glob($searchPath);
my $testPlanFile = "";
if(scalar(@testPlans) > 0){
	$testPlanFile = $testPlans[0];
}
# read the test plan to use later
my $testPlan = $parser->readTestPlanFile($testPlanFile);
if(!defined($testPlan)){
	$wr->noMeta(1);
	$reglim_flg = "N";
}

# parse the file
my $model = $parser->readFile($infile,$testPlan);
&normalizeToBaseUnit($model);
my $header = $model->header;
$header->VERSION($VERSION);
$header->EQUIP6_ID("$facility");
$header->PROGRAM_CLASS(5);

# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);

my $program = $header->PROGRAM;

if ( length($program) > 35 )
{
        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
        $wr->forSBox(1);
	$reglim_flg = "N";
        $program = substr($program, 1, 35); # Leave enough room for session type

}
$header->PROGRAM($program);

unless ($header->populateMeta) {
	$wr->noMeta(1);
	$reglim_flg = "N";
}
$model->updateProgram($hOptions{TYPE});

my $fmt = new_iff_formatter({
  model=>$model,
  writer=>$wr
});

$fmt->dataItems([qw/site x y/]);
$fmt->testItems([qw/number name units/]);
$fmt->printPar();

#Limits
#if ($reglim_flg eq "Y") {
#	if ($model->isLimitNew){
#  		$model->buildLimit;
#  		$fmt->printLimit;
#  		$model->limit->input_file(basename $infile);
#  		$model->limit->registerRefdb;
#	}
#}
#else { # always generate but do not register limit if sandbox
	$model->buildLimit;
	$fmt->printLimit;
	$model->limit->input_file(basename $infile);
#}
dpExit(0);
