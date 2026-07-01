#!/usr/bin/env perl_db

use strict;
use FindBin::libs;
use Getopt::Long qw/:config ignore_case auto_help/;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Parser::ISO;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao: 
use Number::Range;
use Config::Tiny;
use v5.10;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;

=pod
=head1 SYNOPSIS

  fcs_iso_log_IFF.pl <Input flie name>
      --finallot
      --out <output dir>
      --loc <location>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [-V Display version ID]

=head1 DESCRIPTIONS

B<This script> will read ISO tester log file and generate IFF file for dbascii

=head1 AUTHOR

B<gilbert.miole@onsemi.com>

=head1 CHANGES
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021-Apr-13 Karen	: get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
=head1 LICENSE

(C) ON Semiconductor. 2017 All rights reserved.


=cut

 
our $VERSION = "1.0";
our $TESTER  = "ISO";

my (%hOptions) = ();

# Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
}
unless (
    GetOptions(
        \%hOptions,  "OUT=s", "FORK=s", "FACILITYFILE=s", "FINALLOT", "V", "LOC=s", "RELLOT",
        "LOGFILE=s", "DEBUG", "TRACE", "PPLOG"
    )
    )
{
    dpExit( 1, "invalid options" );
    pod2usage(3);
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  # Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $site = $hOptions{SITE};

my $facility = "";
if($hOptions{FINALLOT}) {
	$facility = $config->{$location}->{finalTest};
}else {
	$facility = $config->{$location}->{probe};
}
INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];

# Set Raw File ==> infile
$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    	dpExit( 1, "input file does not exist $infile" );
}

# check output dir
my $fn = basename($infile);
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},
        basename => $fn,
        ext      => 'iff',
        gzipIFF  => 'Y'
    }
);

INFO("infile  = $fn");

my $parser = PDF::Parser::ISO->new;
my $model = $parser->readFile( $infile );
&normalizeToBaseUnit($model);   
my $header = $model->header;
   $header->VERSION($VERSION);
   $header->isFinalLot( $hOptions{FINALLOT} );
   $header->EQUIP6_ID( "$facility" );
my $lot = $header->LOT;
$lot =~ s/^AO/A0/;
$lot =~ s/^XO/X0/;
if ($lot =~ /REJ|RETEST/i) {
	$header->INDEX2("O");
	$lot = substr($lot, 0, 10);
}
$header->LOT( trim($lot) );

# Passing Reference of Model
$pplogger->setModelHeader($model);

my $program = $header->PROGRAM;
if ( length($program) > 235 ){
	WARN("PROGRAM NAME \"".$program."\" will be truncated to 235 characters.  Sending to sandbox.");
	$wr->forSBox(1);
	#$reglim_flg = "N";
	$program = substr($program, 0, 234); # Leave enough room for suffix (and session type if available)

}
# if (length($program) > 35) {
#         INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters. Sending to sandbox.");
#         $wr->forSBox(1);
#         $program = substr($program, 1, 35); #leave room for session type
# }

$header->PROGRAM($program);
$header->PROGRAM_CLASS(2);

unless ( $header->populateMeta ){
	$wr->noMeta(1);
}
$model->updateProgram;

## Check for WMAP Data only if it is not FINALLOT ##

if (!($hOptions{FINALLOT}) && !($hOptions{RELLOT})) {
	my $wmap = $model->updateWMap;
	unless ( $wmap->confirmed ){
		$wr->noWMap(1);
	}
}

my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);

$formatter->testItems([qw/ number name units group/]);
$formatter->dataItems([qw/x y site partid touchdown_num ecid hard_bin soft_bin/]);

$formatter->printPar;

#Limits
$model->buildLimit;
$formatter->printLimit;
$model->limit->input_file(basename $infile);

dpExit(0);
