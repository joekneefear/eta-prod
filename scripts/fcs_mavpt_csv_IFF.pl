#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_mavpt_csv_IFF.pl <Input flie name>
	--out <output dir>
	--loc <location e.g CP, SZ, ME>
	[--finallot]
      	[--logfile <logfilepath>]
      	[--debug|--trace]
	[--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> 

=head1 AUTHOR

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

 2016/Aug/09 eric : create
 2016/Oct/07 eric : append test code to TP 
 2016/Oct/10 eric : load rework codes
 29-May-2017 gilbert : generate limits always and dont register in refdb.pp_limits
 
=head1 LICENSE

(C) Fairchild Semiconductor Inc. 2016 All rights reserved.

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
use PDF::Parser::MavPT;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PDF::Util::AddTestFlowtoTPUsingRef qw/addTestFlowtoTP load_testflow_ref/;
use PPLOG::PPLogger; 	# wsanopao:

our $VERSION = "

1.0
";
our $TESTER  = "MAVPT2";

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "SITE=s", "LOC=s", "FINALLOT","LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG" )
    )
{
    dpExit( 1, "invalid options" );
}
 
if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT LOC/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

# Read input file
my $infile = $ARGV[0];
my $site = $hOptions{SITE};

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    pod2usage();
    dpExit( 1, "input file does not exist $infile" );
}


# check output dir
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        basename => ( basename $infile),
        ext      => 'iff'
    }
);

my $parser = PDF::Parser::MavPT->new;
my $reglim_flg = "Y";

my $model = $parser->readFile($infile, isLogDebug);

&normalizeToBaseUnit($model);

my $header = $model->header;
   $header->isFinalLot($hOptions{FINALLOT});

unless ( $header->populateMeta ){
	$wr->noMeta(1);
	$reglim_flg = "N";
}
$header->VERSION($VERSION);
$header->EQUIP6_ID($hOptions{LOC});
$header->PROGRAM_CLASS(2);

my $testMode;
my $fname = basename $infile;
my @item = split /_/,$fname;
my @tcode = &load_testflow_ref($site);
foreach my $code (@tcode) {
        my @item = `find $infile -type f -name \"*_${code}_*\"`;
        $testMode = $code if @item;
}
$testMode =~ s/^\_//i;
$testMode =~ s/\_$//i;
INFO ("Test code in file = $testMode");

#### Add test flow to TP and sandbox it if invalid
my $testFlowCode = &addTestFlowtoTP($model,$testMode,$site);
if ( $model->forSBflag == 1 ) {
        $wr->forSBox($model->forSBflag);
        $reglim_flg = "N";
}

$testFlowCode = "_${testFlowCode}";

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

my $program = $header->PROGRAM;
if ( length($program) + length($testFlowCode) > 45 )
{
        INFO("PROGRAM NAME \"".$program.$testFlowCode."\" will be truncated to 35 characters.  Sending to sandbox.");
        $wr->forSBox(1);
        $reglim_flg = "N";
        $program = substr($program, 1, 45-length($testFlowCode)); # Leave enough room for session type
}
$program = $program.$testFlowCode;
$program =~ s/\_$//g;
$header->PROGRAM($program);
$model->updateProgram;

my $formatter = new_iff_formatter(
	{   model  => $model,
            writer => $wr
	}
);
		
$formatter->dataItems([qw/site partid hard_bin soft_bin/]);
$formatter->testItems([qw/number name units/]);
$formatter->printPar;

#Limits
#if ($reglim_flg eq "Y") {
#        if ($model->isLimitNew){
#                $model->buildLimit;
#                $formatter->printLimit;
#                $model->limit->input_file(basename $infile);
#                $model->limit->registerRefdb;
#        }
#}
#else {   # always generate but do not register limit if sandbox
        $model->buildLimit;
        $formatter->printLimit;
        $model->limit->input_file(basename $infile);
#}
	
dpExit(0);
