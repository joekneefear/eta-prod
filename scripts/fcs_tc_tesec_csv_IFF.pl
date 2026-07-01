#!/usr/bin/env perl_db
# SVN $Id: fcs_tc_tesec_csv_IFF.pl 
=pod

=head1 SYNOPSIS

      fcs_tc_tesec_csv_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
      --loc <location>
      --facilityfile <$DPSCRIPT/facilityMapping.ini>
      [-config <config_tester_type>]
      [--logfile <logfilepath>]
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read TakCheong Tesec CSV file and output IFF file

=head1 AUTHOR

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

2016-Apr-06 Eric	: new
2017-May-30 Gilbert     : generate limits always and dont register in refdb.pp_limits
2021-Apr-13 glory       : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

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
use PDF::Parser::TESEC_CSV;
use PDF::Formatter;
use PDF::DpWriter;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);
use Time::localtime;
use File::stat;
use Time::Piece;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;

our $VERSION = "

1.0
";
our $TESTER  = "TESEC";

# a hash to receive options
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions,  "OUT=s", "FINALLOT",
        "LOGFILE=s", "DEBUG", "TRACE", "V", "TYPE=s","LOC=s", "FACILITYFILE=s", "CONFIG=s", "PPLOG",
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

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location     = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
my $reglim_flg = "Y";
my $facility = $config->{$location}->{finalTest};
INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    dpExit( 1, "input file does not exist $infile" );
}

# check output dir
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        basename => ( basename $infile),
        ext      => 'iff',
        gzipIFF  => 'Y'
    }
);

INFO("infile  = $infile");

my $parser = PDF::Parser::TESEC_CSV->new;
my ($model, $limit) = $parser->readFile($infile,isLogDebug);
my $testCond = [qw/testCond /];

# normalization
#&normalizeToBaseUnit($model);   #do not normalized test results because it is already normalized 

my $header = $model->header;
   $header->isFinalLot($hOptions{FINALLOT});
   $header->VERSION($VERSION);
   $header->PROGRAM_CLASS(2);
   $header->REVISION(1);
   $header->EQUIP6_ID($facility);
      
if ($header->START_TIME eq "" || $header->START_TIME eq "N/A") {
	my $file_time = localtime( stat($infile)->mtime )->strftime("%Y/%m/%d %H:%M:%S");
	   $header->START_TIME($file_time);
	   $header->END_TIME($file_time);
}   

my $program = $header->PROGRAM;

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);
if ($model->{misc} eq "Can't determine tester file type.") {
	$pplogger->setLot($header->{LOT});
	if (!($hOptions{FINALLOT})) {
		$header->populateMeta();
		$pplogger->setWaferFlag(1);
		$pplogger->setSourceLot($header->SOURCE_LOT);
		#$pplogger->setWafNum();
	} else {
		$pplogger->setWafNum("00");
	}
	dpExit(1,"$model->{misc}");
}


# truncate ppid 
if (length($program) > 35) {
	INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
        $wr->forSBox(1);
	$reglim_flg = "N";
        $program = substr($program, 1, 35);
}
$header->PROGRAM($program);

# look up lotid in ref db
unless ($header->populateMeta){
	$wr->noMeta(1);
	$reglim_flg = "N";
}

$model->updateProgram;	

my $formatter = new_iff_formatter(
	{   model  => $model,
            writer => $wr
        }
);

$formatter->dataItems([qw/partid hard_bin soft_bin/]);
$formatter->testItems([qw/number name units /]);
$formatter->binItems ([qw/number name PF /]);
$formatter->printPar;

# Output Limit
#if ($reglim_flg eq "Y") {
#    if ($model->isLimitNew){
#    	&normalizeToBaseUnit($limit); # normalized only the limits
#       $model->buildLimit;
#	$model->limit->conditionNames($testCond);
#       $formatter->printLimit;
#	$model->limit->registerRefdb;
#    }
#}
#else {
	&normalizeToBaseUnit($limit);
	$model->buildLimit;
	$model->limit->conditionNames($testCond);
	$formatter->printLimit;
#}
dpExit(0);
