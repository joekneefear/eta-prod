#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

 
=head1 DESCRIPTIONS

B<This script> will process SRM files.

=head1 AUTHOR

B<gilbert.miole@fairchildsemi.com>

=head1 CHANGES
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021-Apr-14 Karen	: get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

=head1 LICENSE

(C) Fairchild 2015 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use File::Basename qw/basename dirname/;
use File::Copy;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::Parser::SRM;
use PDF::DpWriter;
use PDF::Formatter;
use PPLOG::PPLogger; 	# wsanopao: 
use Config::Tiny;

our $VERSION = "1.0";
our $TESTER  = "SRM";
my $location = "";

# a hash to receive options
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}

unless ( GetOptions ( \%hOptions, "OUT=s", "FORK=s", "FACILITYFILE=s", "LOC=s", "FINALLOT", "LOGFILE=s", "DEBUG", "TRACE", "V","PPLOG" ) ) {
    pod2usage(3);
}

if($hOptions{V}) {
	print("$VERSION\n"); 
	dpExit(0);
}

my @required_options = qw/OUT LOC FACILITYFILE/;

if(grep {!exists $hOptions{$_}} @required_options) {
	pod2usage(3);
}

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
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

my $inFile = $ARGV[0];
my $parserTXT = PDF::Parser::SRM->new;
my $model;
my $wr;
my $TXT;

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($inFile);

 $TXT = $inFile;
 INFO("Fork dir=$hOptions{FORK}");
 $wr = PDF::DpWriter->new(
    {  outdir   => $hOptions{OUT},
       forkdir => $hOptions{FORK},
       basename => ( basename $TXT),
       ext      => 'iff',
       gzipIFF  => 'Y'
    }
 );

$model = $parserTXT->readTXT($TXT, $hOptions{SITE});
	
my $header = $model->header;
$header->VERSION($VERSION);
$header->PROGRAM_CLASS(12);
$header->EQUIP6_ID( "$facility");
$header->isFinalLot($hOptions{FINALLOT});

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

# get MEta from database
unless ( $header->populateMeta ) {
    $wr->noMeta(1);
}

### Use program naming rule
if ($hOptions{FINALLOT}){
	$model->updateProgram;
}
else {
	$model->updateProgram("MAP_PGM");
}

my $fmt = new_iff_formatter({
  model=>$model,
  writer=>$wr
});
  
$fmt->dataItems([qw/soft_bin hard_bin/]);
$fmt->printPar();

dpExit(0);
