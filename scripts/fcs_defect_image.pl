#!/usr/bin/env perl_db
=pod

=head1 SYNOPSIS

  fcs_defect_klarf.pl <Input flie name>
	--out <output dir>
	--loc <location e.g. MT,CP>
	[--logfile <logfilepath>]
	[--debug|--trace]
	[--V Display version ID ] 
=head1 DESCRIPTIONS

B<This script> will read and to try to split die Klarf file and generate IFF file for dbascii

=head1 AUTHOR

B<junifferallan.garcia@fairchildsemi.com>

=head1 CHANGES

 2016-Jul-28 : new creation
 2016-Aug-18 : added support for defect with mulitple slots and wafers 
 
 
=head1 LICENSE

(C) Fairchild Semiconductor. 2016 All rights reserved.

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
use PDF::Parser::Klarf;
use PDF::DpData::Defect;
use PDF::Formatter;
use PDF::DAO;
use PPLOG::PPLogger; 	


our $VERSION = "1.0";
our $TESTER  = "Klarf";
my $PPlogger = new PPLOG::PPLogger();
my (%hOptions) = ();



# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "SITE=s", "LOC=s", "MOVEIMAGE", "LOGFILE=s", "DEBUG","V", "TRACE", "PPLOG" )
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

##Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  
}



my $location = $hOptions{LOC};
my $debug = 0;
if($hOptions{DEBUG}) {
	$debug = 1;
}

# Read input file
my $infile = $ARGV[0];
my $IMG = $infile;

my $baseNameImg = basename($IMG);
my $imageType = "";

my $fileType = `file $IMG`;

if($fileType =~ /TIFF/i) {
	$imageType = "TIFF";
}
if($fileType =~ /JPEG|JPG/i) {
	$imageType = "JPEG";
}
#if($baseNameImg =~ /\.JPG|JPEG$/) {
#	$imageType = "JPEG";
#} else {
#	$imageType = "TIFF";
#}


## Set Raw File ==> infile 
$PPlogger->setRawFile($infile);

if ( !-f $infile ) {
    pod2usage();
    dpExit( 1, "input file does not exist $infile" );
}

my $wr = PDF::DpWriter->new(
   {   outdir   => $hOptions{OUT},
       basename => ( basename $infile),
       ext      => 'iff'
   }
);

my $defect = PDF::DpData::Defect->new;

my $formatter = new_iff_formatter(
    {   defect  => $defect,
        writer => $wr
    }
);

$defect->IMAGE_FILENAME($baseNameImg);
$defect->IMAGE_TYPE($imageType);
my $resFlag = $defect->populateDefectIndexInfoForImageLoading();
if($resFlag == 0) {
	dpExit( 4, "Image info not found. Move to ReworkFiles folder" );
}

if($defect->{DB_LOCATION} eq "Sandbox") {
	$wr->noMeta(1);
}

$formatter->printDefectRefFile();

dpExit(0);


# Exit with moving Image files
sub dpExitError {
    my $message = shift;
    if ( $hOptions{MOVEIMAGE} ) {
        move $IMG, ( dirname $IMG) . "/NotProcessed/" . ( basename $IMG);
    }
    dpExit( 1, $message );
}

