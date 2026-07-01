#!/usr/bin/env perl_db
=pod

=head1 SYNOPSIS

  fcs_defect_mini_klarf.pl <Input flie name>
	--out <output dir>
	--loc <location e.g. MT,CP>
	--movetif
	[--logfile <logfilepath>]
	[--debug|--trace]
	[--V Display version ID ] 
=head1 DESCRIPTIONS

B<This script> will read and to try to split die Klarf file and generate IFF file for dbascii

=head1 AUTHOR

B<junifferallan.garcia@fairchildsemi.com>

=head1 CHANGES

 2016-Jul-28 : new creation
 
 
=head1 LICENSE

(C) Fairchild Semiconductor. 2016 All rights reserved.

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
use PDF::Parser::MiniKlarf;
use PDF::DpWriter;
use PDF::Formatter;
use PPLOG::PPLogger; 
use PDF::DpData::Defect;


our $VERSION = "1.0";
our $TESTER  = "MINI-Klarf";
my $location = "";
my $debug;
# Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

# a hash to receive options
my (%hOptions) = ();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}

unless ( GetOptions ( \%hOptions, "OUT=s", "LOC=s", "MOVETIF", "LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG") ) {
    pod2usage(3);
}

if($hOptions{V}) {
	print("$VERSION\n"); 
	dpExit(0);
}

if($hOptions{DEBUG}) {
	
	$debug = 1;
}

my @required_options = qw/OUT LOC MOVETIF/;

if(grep {!exists $hOptions{$_}} @required_options) {
	pod2usage(3);
}

#Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);
}

#if ($hOptions{SITE} ne 'cpft_tmt' && $hOptions{SITE} ne 'cprel') {
#	dpExit( 1, "wrong site code : $hOptions{SITE}" );
#}
my $location = $hOptions{LOC};


my $TRF = $ARGV[0];
my $parser = PDF::Parser::MiniKlarf->new;
my $model;
my $header;
my $wr;
my $defect;
#my $TRF = $inFile;
my $TIF;
my @defectLineData;

## Set Raw File ==> infile 
$PPlogger->setRawFile($TRF);

#check if TRF file exists.
if ( !-f $TRF ) {
    dpExit( 1, "input file does not exist $TRF" );
}

#check if File is a TRF file
if($TRF !~ /\.TRF$/i){
	dpExit( 1, "input file is NOT TRF file" . $TRF );
}

$wr = PDF::DpWriter->new(
   {   outdir   => $hOptions{OUT},
       basename => ( basename $TRF),
       ext      => 'iff'
   }
);

# Find corresponding TIF
my $TIF = $TRF;
$TIF =~ s/\.TRF$/\.TIF/;

if ( !-f $TIF ) {
    dpExit( 4, "$TIF not found. Move to ReworkFiles folder" );
}

$model = $parser->readDefectFile($TRF);
$header = $model->header;
$defect = $model->defect;
$defect->LOCATION($location);

$PPlogger->setLot($header->{LOT});

my $resultFlag = $defect->populateDefect();

if($resultFlag == 0) {
	ERROR("Cant get STEP_ID in REFDB.PP_DEFECT!!! TRF cant be loaded without STEP_ID or Layer info.");
	dpExitError("Cant get STEP_ID in REFDB.PP_DEFECT!!!");
	$wr->noMeta(1);
} 
INFO("STEP_ID=>$defect->{STEP_ID}");
$header->copyDefectToHeader($defect);
if($defect->{DB_LOCATION} eq "Sandbox" || $defect->{DB_LOCATION} eq "") {
	$wr->forSBox(1);
}

my $fmt = new_iff_formatter({
  model=>$model,
  writer=>$wr
});

$fmt->printDefect();

if ( $hOptions{MOVETIF} ) {
    move $TIF, ( dirname $TIF) . "/Processed/" . ( basename $TIF);
}

dpExit( 0 );





# Exit with moving TIF files
sub dpExitError {
    my $message = shift;
    if ( $hOptions{MOVETIF} ) {
        move $TIF, ( dirname $TIF) . "/NotProcessed/" . ( basename $TIF);
    }
    dpExit( 1, $message );
}





