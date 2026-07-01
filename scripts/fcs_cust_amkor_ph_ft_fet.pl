#!/usr/bin/env perl_db
# 2017-Jan-23 Eric	: Initial release
#
# Function: Move file to correct directory according to file extension

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::Log;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);
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
        \%hOptions, "LOGFILE=s", "DEBUG", "TRACE", "V"
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

my @required_options = qw/ /;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions );

# check input file
my $infile = $ARGV[0];
if ( ! -f $infile ) {
    ERROR("$infile does not exist");
    pod2usage(3);
}
INFO ("Infile: $infile");

# Move file to correct directory based on file extension 
my $orig_file = $infile;
my $move_file = basename($infile);
my @env = split /\//, $infile;
my $cpr_dir = "/data/${env[2]}/CPR";
my $prn_dir = "/data/${env[2]}/PRN";
my $status;

if ($infile =~ /\.CPR$|\.CPR_MD5.+/i) {
	system "/bin/mv -f \'${infile}\' ${cpr_dir}/${move_file}";
        $status = (-e "${cpr_dir}/${move_file}") ? "Successful" : "Failed";
}
elsif ($infile =~ /\.PRN$|\.PRN_MD5.+/i ) {
	system "/bin/mv -f \'${infile}\' ${prn_dir}/${move_file}";
        $status = (-e "${prn_dir}/${move_file}") ? "Successful" : "Failed";
}

INFO ("Moving $infile $status");

dpExit(0);
