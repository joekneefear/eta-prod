#!/usr/bin/env perl_db
# 2015-Nov-10 Eric	: Initial release
# 2015-Nov-24 Eric	: Added status after moving file
# 2016-Jan-18 Eric	: added condition for ET file
# 2021-Apr-10 jgarcia : replace hardcoded env location to server's env variable for env's folder location.
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
#my $ad3_dir = "/data/bket_hp/ad3";
my $ad3_dir = "$ENV{DPDATA}/data/bket_hp/ad3";
#my $bstdf_dir = "/data/bket_hp/bstdf";
my $bstdf_dir = "$ENV{DPDATA}/data/bket_hp/bstdf";
#my $et_dir = "/data/bket_hp/et";
my $et_dir = "$ENV{DPDATA}/data/bket_hp/et";
#my $txt_dir = "/data/bket_hp/TP";
my $txt_dir = "$ENV{DPDATA}/data/bket_hp/TP";
my $status;

if ($infile =~ /\.AD3$|\.AD3_MD5.+/i) {
	system "/bin/mv -f \'${infile}\' ${ad3_dir}/${move_file}";
        $status = (-e "${ad3_dir}/${move_file}") ? "Successful" : "Failed";
        INFO ("Moving $infile $status");	
}
elsif ($infile =~ /\.BSTDF$|\.BSTDF_MD5.+/i ) {
	system "/bin/mv -f \'${infile}\' ${bstdf_dir}/${move_file}";
        $status = (-e "${bstdf_dir}/${move_file}") ? "Successful" : "Failed";
        INFO ("Moving $infile $status");
}
elsif ($infile =~ /\.TXT$/i ) {
	system "/bin/mv -f \'${infile}\' ${txt_dir}/${move_file}";
        $status = (-e "${txt_dir}/${move_file}") ? "Successful" : "Failed";
        INFO ("Moving $infile $status");
}
elsif ($infile =~ /\.ET$|\.ET_MD5.+/i ) {
        system "/bin/mv -f \'${infile}\' ${et_dir}/${move_file}";
        $status = (-e "${et_dir}/${move_file}") ? "Successful" : "Failed";
        INFO ("Moving $infile $status");
}

dpExit(0);
