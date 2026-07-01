#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_tesec_IFF.pl <Input flie name>
      --out <output dir>
      --loc <location e.g CP|SZ|ME>    
      --cfgtestertype < tester type>
      --facilityfile <$DPSCRIPT/facilityMapping.ini>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [-V Display version ID]
=head1 DESCRIPTIONS

B<This script> will read AWW file and generate IFF file for dbascii

=head1 AUTHOR

B<jason.arp@pdf.com>

=head1 CHANGES

 2015/07/01 grace: new
 2015/07/14 grace : added SMAP:: to program 
 2015/07/23 eric  : move SMAP:: to FMT script. apply ppid rule
 2015/07/24 eric  : change from updateProgram("MAP_PGM") to updateProgram;
 2016/07/12 eric  : get start/end time from file timestamp;
 2016/07/13 eric  : log pre-processing information to refdb.pp_log table
 2021/04/12 glory : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Getopt::Long;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use POSIX qw(strftime);
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Parser::TESEC;
use PDF::Formatter;
use PPLOG::PPLogger;
use v5.10;
use Config::Tiny;

no warnings qw/experimental::lexical_subs experimental::smartmatch/;

our $VERSION = "

1.0
";
our $TESTER  = "TESEC";

my (%hOptions) = ();
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "LOGFILE=s", "DEBUG", "LOC=s", "FACILITYFILE=s", "V", "CONFIG=s",
        "FINALLOT", "TRACE", "PPLOG" )
    )
{
    dpExit( 1, "invalid options" );
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions,$pplogger );
if ($hOptions{PPLOG}){
        $pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

unless ( $hOptions{LOC} ) {
    dpExit ( 1, "--loc must be specified" );
    pod2usage(3);
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $facility = $config->{$location}->{ast};
INFO("FACILITY|EQUIP6_ID=$facility");
# Read input file
my $infile = $ARGV[0];

$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    pod2usage();
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
open( INFILE, $infile );

# Start input file reading
my $parser = PDF::Parser::TESEC->new;
my $file_time = (stat $infile)[9];
my $model = $parser->readFile( $infile,$hOptions{CONFIG} );
my $header = $model->header;
$header->isFinalLot($hOptions{FINALLOT});

$wr->noMeta(1) unless ( $header->populateMeta );
$header->VERSION($VERSION);
$header->EQUIP6_ID( $facility );
$header->CFG_TESTER_TYPE( $hOptions{CONFIG} );

# Get start/end times
if($header->START_TIME eq "") {
	$header->START_TIME($file_time);
}
if($header->END_TIME eq ""){
	$header->END_TIME($file_time);
}

if (!($hOptions{FINALLOT})) {
   $model->updateWMap;
   unless ( $model->wmap->confirmed ) {
	$wr->noWMap(1);
   }
}   

my $program = $header->PROGRAM;
my $map_typ = "STD_";
if (length($program) + length($map_typ) > 35) {
	INFO("PROGRAM NAME \"".$map_typ.$program."\" will be truncated to 35 characters. Sending to sandbox.");
	$wr->forSBox(1);
	$program = substr($program, 1, 35-length($map_typ));
}
$header->PROGRAM($map_typ.$program);
$model->updateProgram;

$pplogger->setModelHeader($model);

my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);
$formatter->dataItems([qw/x y soft_bin/]);
$formatter->printBinmap;

dpExit(0);

