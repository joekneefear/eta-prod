#!/usr/bin/env perl_db
# 2016-Jul-14 Eric	: Initial release
#2021-Apr-16  glory     : not to hardcode directory ang change it to Colo location.
# Function: Move file to correct directory according to file extension

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::Log;
use File::Basename qw/basename dirname/;
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
my $dir = dirname($infile);
my $log2_dir = "${dir}/LOG2/inbox";
my $sum_dir = "${dir}/SUM/inbox";
my $status;

if ($infile =~ /\.LOG2$|\.LOG2_MD5.+/i) {
	system "/bin/mv -f \'${infile}\' ${log2_dir}/${move_file}";
        $status = (-e "${log2_dir}/${move_file}") ? "Successful" : "Failed";
}
elsif ($infile =~ /\.SUM$|\.SUM_MD5.+/i ) {
	system "/bin/mv -f \'${infile}\' ${sum_dir}/${move_file}";
        $status = (-e "${sum_dir}/${move_file}") ? "Successful" : "Failed";
}

INFO ("Moving $infile $status");

dpExit(0);
