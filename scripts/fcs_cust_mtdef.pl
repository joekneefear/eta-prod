#!/usr/bin/env perl_db
# 2016-Aug-19 jgarcia      : Initial
#
# Function: move incoming files to appropriate process folder.

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::Log;
use File::Basename qw/basename/;
use PDF::DpLoad;
use File::Copy;

our $VERSION = "1.0";

# a hash to receive options
my (%hOptions) = ();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions, "LOGFILE=s", "DIR_KLARF=s", "DIR_MINIKLARF=s", "DIR_DEFECT_IMAGE=s", "DEBUG", "TRACE", "V"
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

my @required_options = qw/DIR_KLARF DIR_MINIKLARF DIR_DEFECT_IMAGE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions );

# check input file
my $infile = $ARGV[0];
if ( ! -f $infile ) {
    ERROR("$infile does not exist");
    pod2usage(3);
}

INFO ("Infile: $infile");

my $file = $infile;
my $baseFile = basename($infile);
my $dir001 = $hOptions{'DIR_KLARF'};
my $dirTRF_TIF =  $hOptions{'DIR_MINIKLARF'};
my $dirDefectWithImage = $hOptions{'DIR_DEFECT_IMAGE'};
my $moveStatus;
my $imageInDefectFile = "false";

if($file =~ /\.001|\.000|\.TXT/i) {
 $imageInDefectFile = &checkForImageInfo($file);
}


# Move file to their  corresponding directory 
if($imageInDefectFile eq "true" || $file =~ /\.T0.+|\.00I$/i) {
	INFO ("Moving $infile to $dirDefectWithImage");
	move($file, "${dirDefectWithImage}/${baseFile}");
	$moveStatus = (-e "${dirDefectWithImage}/${baseFile}") ? "Move process Successful" : "Move process Failed";
	INFO ("$infile: $moveStatus");
} elsif ($file =~ m/\.001/i) {
	INFO ("Moving $infile to $dir001");
	move($file, "${dir001}/${baseFile}");
	$moveStatus = (-e "${dir001}/${baseFile}") ? "Move process Successful" : "Move process Failed";
	INFO ("$infile: $moveStatus");
} elsif ($file =~ /\.TRF|\.TIF/i) {
	INFO ("Moving $infile to $dirTRF_TIF");
	move($file, "${dirTRF_TIF}/${baseFile}");
	$moveStatus = (-e "${dirTRF_TIF}/${baseFile}") ? "Move process Successful" : "Move process Failed";
	INFO ("$infile: $moveStatus");
}


dpExit(0);

sub checkForImageInfo {
	
	my $file = shift;
	my $result = "";
	
	my $fileHandle = IO::File->new($infile) or dpExitError("Failed to open Defect file $infile");
 	while (my $line_ = $fileHandle->getline) {
 		
 		if ($line_ =~ /^TiffFilename.+/i) {
 			$result = "true";
 			last;
 		}
 		
 	}
 	
 	undef $fileHandle;
 	return $result;
	
}
