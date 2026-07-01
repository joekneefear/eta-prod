#!/usr/bin/env perl_db
# 2017-Feb-06 Eric	: Initial release
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
my $data_dir = "/data/${env[2]}/CSV";
my $sum_dir = "/data/${env[2]}/TXT";
my $status;

if ($infile =~ /\.CSV$|\.CSV_MD5.+/i) {
	system "/bin/mv -f \'${infile}\' ${data_dir}/${move_file}";
        $status = (-e "${data_dir}/${move_file}") ? "Successful" : "Failed";
}
elsif ($infile =~ /\.TXT$|\.TXT_MD5.+/i ) {
	system "/bin/mv -f \'${infile}\' ${sum_dir}/${move_file}";
        $status = (-e "${sum_dir}/${move_file}") ? "Successful" : "Failed";
}
else {
	dpExit( 1, "invalid file" );
}

INFO ("Moving $infile $status");

dpExit(0);
