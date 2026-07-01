#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_bket_hp_IFF.pl <Input flie name>
	--out <output dir>
	--testplanpath <test plan file path>
	--loc<location e.g. BK, CP>
	[--logfile <logfilepath>]
	[--debug|--trace]

=head1 DESCRIPTIONS

B<This script> will read BK HP Etest file and generate IFF file for dbascii

=head1 AUTHOR

B<jason.arp@pdf.com>

=head1 CHANGES

 2015/05/12 jason	: new creation
 2015/07/06 eric	: added LOC arg and pass it as EQUIP6_ID.
 2015/07/28 jgarcia	: initialize $header->PROGRAM_CLASS to 5.
 2015/07/28 jgarcia	: check for Program name greater than 35 chars. ang truncate if greater.
 2015/08/05 eric   	: removed required argument testplanpath
 2015/11/19 eric   	: always generate but do not register limits if sandbox.
 2015/11/23 jgarcia	: Added TYPE param to indicate if Process or Product info to be added in Program.
 2016/02/16 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2017/04/06 eric	: set wafer flag for pplogging
 2017/04/26 eric	: trap datalog if no test data
 17-May-2017 Gilbert    : generate limits always and dont register in refdb.pp_limits
 2020/09/01 karen       : added support to fork and qde output (IFF)/files to designated location
 2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

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
use PDF::Parser::BKET_HP;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny; 

our $VERSION = "1.0";
our $TESTER  = "HP";

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();


# Read arguments
if ( $#ARGV < 0 ) {
    	pod2usage();
    	dpExit( 1, "No input file specified" );
}
unless (
    	GetOptions( \%hOptions, "OUT=s", "FACILITYFILE=s", "FORK=s", "TESTPLANPATH=s", "LOC=s", "TYPE=s", "LOGFILE=s", "DEBUG",
        "TRACE", "PPLOG", "QDE" )
    	)
{
    	dpExit( 1, "invalid options" );
}

my @required_options = qw/OUT LOC TYPE FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
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
my $wr = PDF::DpWriter->new({   
	outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},
	qde => $hOptions{QDE},
	basename => ( basename $infile),
        ext      => 'iff',
        gzipIFF  => 'Y'
});

INFO("infile  = $infile");

my $parser = PDF::Parser::BKET_HP->new;

# parse the file
my $model = $parser->readFile($infile);
my $misc = $model->misc;
&normalizeToBaseUnit($model);
my $header = $model->header;
$header->VERSION($VERSION);
$header->PROGRAM_CLASS(5);
$header->EQUIP6_ID($facility);

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

# trap datalog if no test data
if ($misc->{err_msg} eq "No test data.") {
        dpExit(1,"$misc->{err_msg}");
}

my $reglim_flg = "Y";
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

if ($header->SOURCE_LOT ne ""){
	$pplogger->setWaferFlag(1);
}

$model->updateProgram($hOptions{TYPE});

my $fmt = new_iff_formatter({
  	model=>$model,
  	writer=>$wr
});

$fmt->dataItems([qw/site x y/]);
$fmt->testItems([qw/number name units/]);
$fmt->printPar();

#if ($reglim_flg eq "Y") {
#	if ($model->isLimitNew){
#  		my $limit = new_limit;
#  		$limit->copyHeader($header);
#  		$limit->tests($model->tests);
#  		$model->limit($limit);    
#  		$model->buildLimit;
#  		$fmt->printLimit;
#  		$model->limit->input_file(basename $infile); 
#  		$model->limit->registerRefdb;
#	}
#}
#else {
	my $limit = new_limit;
           $limit->copyHeader($header);
           $limit->tests($model->tests);
           $model->limit($limit);
           $model->buildLimit;
           $fmt->printLimit;
           $model->limit->input_file(basename $infile);	
#}

dpExit(0);
