#!/usr/bin/env perl_db
# SVN $Id: fcs_icos_xls_IFF.pl 
=pod

=head1 SYNOPSIS

      fcs_icos_xls_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
      --loc <location>
      [-config <config_tester_type>]
      [--logfile <logfilepath>]
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read AOI ICOS XLS file and output IFF file

=head1 AUTHOR

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

2016-Apr-18 Eric	: new
2017-May-12 Eric	: set wafer flag for pplogging
2021-Apr-07 Karen 	: get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
2021-Apr-14 jgarcia : modified to not hardcode the binrefile location instead put as an argument .

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
use PDF::Parser::ICOS_xls;
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
our $TESTER  = "ICOS";

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
        \%hOptions,  "OUT=s", "FINALLOT", "BINREFFILE=s", "FACILITYFILE=s",
        "LOGFILE=s", "DEBUG", "TRACE", "V", "TYPE=s","LOC=s",  "CONFIG=s", "PPLOG",
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
my @required_options = qw/OUT LOC FACILITYFILE BINREFFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});

my $location     = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");
my $type	 = $hOptions{TYPE};
my $reglim_flg = "Y";

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

my $parser = PDF::Parser::ICOS_xls->new;
my $model = $parser->readFile($infile, $type, $hOptions{BINREFFILE}, isLogDebug);

my $header = $model->header;
   $header->isFinalLot($hOptions{FINALLOT});
   $header->VERSION($VERSION);
   $header->PROGRAM_CLASS(12);
   $header->EQUIP6_ID( "$facility" );

my $program = $header->PROGRAM;

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

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

if (! $hOptions{FINALLOT}){
	$pplogger->setWaferFlag(1);
}

$model->updateProgram;	

my $formatter = new_iff_formatter(
	{   model  => $model,
            writer => $wr
        }
);

if ($hOptions{FINALLOT}){
	$formatter->binItems ([qw/number name PF count/]);
	$formatter->printPar_v4;
}
else {
	$formatter->binItems ([qw/number name PF count/]);
	$formatter->printPar;
}

dpExit(0);
