#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_et_bket_IFF.pl <Input flie name>
      --out <output dir>
      [--type <Process|Product>]
      [--logfile <logfilepath>]
      [--debug|--trace]
      [-V Display version ID]

=head1 DESCRIPTIONS

B<This script> will read ET file and generate IFF file for dbascii

=head1 AUTHOR

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

 	2016-Jan-12 eric	: new
	2016-Feb-16 wsanopao    : logging pre-processing information  to refdb.pp_log table.
	2017-May-02 eric	: use misc for error trappping, return limit
	2017-May-23 gilbert     : generate limits always and dont register in refdb.pp_limits
	2020/09/01 karen        : added support to fork and qde output (IFF)/files to designated location
	2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

=head1 LICENSE

(C) Fairchild Semiconductor Inc. 2015 All rights reserved.

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
use PDF::Parser::ET_BKET;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use Time::Local;
use Tie::File;
use PPLOG::PPLogger; 	# wsanopao: 
use Config::Tiny;

our $VERSION = "

1.0
";
our $TESTER  = "ET";

my (%hOptions) = ();
my $location = "";
my $reglim_flg = "Y";

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "FACILITYFILE=s", "FORK=s", "LOC=s", "TYPE=s", "LOGFILE=s", "DEBUG", "V",
        "TRACE", "TPDIR=s", "PPLOG", "QDE" )
    )
{
    dpExit( 1, "invalid options" );
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT LOC TYPE TPDIR FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $location = $hOptions{LOC};
my $tpDir = $hOptions{TPDIR};
my @dummy = split("/", $hOptions{LOC});
my $site = $dummy[1];
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
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
	qde => $hOptions{QDE},
        basename => ( basename $infile),
        ext      => 'iff',
        gzipIFF  => 'Y'
    }
);

INFO("infile  = $infile");

my $parser = PDF::Parser::ET_BKET->new;

if($infile =~ /gz$/)
{
	my $command = "gunzip $infile";
	my $ret = system($command);	
}
else{
	my ($model,$limit) = $parser->readFile($infile,$tpDir);
	my $misc  = $model->misc;
	#&normalizeToBaseUnit($model);

	my $header = $model->header;

	$header->VERSION($VERSION);
	$header->PROGRAM_CLASS(5);
	$header->EQUIP6_ID($facility);
	$header->START_TIME(timegm(localtime()));
	$header->END_TIME(timegm(localtime()));	
	
	# wsanopao: Passing Reference of Model
	$pplogger->setModelHeader($model);
	
	my $program = $header->PROGRAM;
	my $rev = $header->REVISION;

	if ( length($program) > 35 )
	{
	        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
	        $wr->forSBox(1);
		$reglim_flg = "N";
	        $program = substr($program, 1, 35); # Leave enough room for session type
		        		
	}
	
	$header->PROGRAM($program);

	unless ($header->populateMeta){
		$wr->noMeta(1);
		$reglim_flg = "N";
	}

	if ($misc->{err_msg} ne "") {
		$pplogger->setWaferFlag(1);
		dpExit($misc->{err_cod}, "$misc->{err_msg}");
	}

	$model->updateProgram($hOptions{TYPE});

	my $fmt = new_iff_formatter({
		model=>$model,
	  	writer=>$wr
        });
	$fmt->dataItems([qw/site x y/]);
	$fmt->testItems([qw/number name units/]);
	$fmt->printPar;

	#if ($reglim_flg eq "Y"){
	#	if ($model->isLimitNew){
  	#		$limit->copyHeader($header);
  	#		$model->limit($limit);    
  	#		$model->buildLimit;
  	#		$fmt->printLimit;
  	#		$model->limit->input_file(basename $infile); 
  	#		$model->limit->registerRefdb;
	#	}
	#}
	#else {  #always generate & do not register limit if sandbox
		$limit->copyHeader($header);
                $model->limit($limit);
                $model->buildLimit;
                $fmt->printLimit;
                $model->limit->input_file(basename $infile);
	#}
}

dpExit(0);
