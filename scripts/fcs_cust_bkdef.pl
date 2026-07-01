#!/usr/bin/env perl_db
# 2016-Aug-01 jgarcia      : Initial
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
        \%hOptions, "LOGFILE=s", "DIR_KLARF=s", "DIR_MINIKLARF=s", "DEBUG", "TRACE", "V"
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

my @required_options = qw/DIR_KLARF DIR_MINIKLARF/;
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
my $dirTRF_TIF = $hOptions{'DIR_MINIKLARF'};
my $moveStatus;

# Move file to their  corresponding directory 
if ($file =~ m/\.001$/) {
	INFO ("Moving $infile to $dir001");
	move($file, "${dir001}/${baseFile}");
	$moveStatus = (-e "${dir001}/${baseFile}") ? "Move process Successful" : "Move process Failed";
	INFO ("$infile: $moveStatus");
	
}
else {
	INFO ("Moving $infile to $dirTRF_TIF");
	move($file, "${dirTRF_TIF}/${baseFile}");
	$moveStatus = (-e "${dirTRF_TIF}/${baseFile}") ? "Move process Successful" : "Move process Failed";
	INFO ("$infile: $moveStatus");
}


dpExit(0);
