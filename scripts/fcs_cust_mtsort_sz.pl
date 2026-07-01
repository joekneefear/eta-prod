#!/usr/bin/env perl_db
# 2015-Oct-29 Eric	: Initial release
# 2021-Apr-07 jgarcia : change raw file staging root folder.
#
# Function: Read STDF version from the input file and move file to directtory depending on the STDF version.
 
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

# Open and check stdf version
my $cpu_type = "";
my $stdf_ver = "";
open FH, $infile or die "error msg: $!";

	my $in;
	read FH, $in, 4;
	read FH, $in, 1;
	$cpu_type  = unpack "C1", $in;
	read FH, $in, 1;
	$stdf_ver  = unpack "C1", $in;

	INFO ("CPU_TYPE: $cpu_type");
	INFO ("STDF_VER: $stdf_ver");

close(FH);

# Move file to correct directory based on STDF version
my $orig_file = $infile;
my $move_file = basename($infile);
my $v3_dir = "/apps/exensio_data/data/mtsort_sz/STDFV3";
my $v4_dir = "/apps/exensio_data/data/mtsort_sz/STDFV4";

if ($stdf_ver == 3) {
	move($orig_file, "${v3_dir}/${move_file}") or die "The move operation failed: $!";
	INFO("Moving $orig_file to $v3_dir");
}
elsif ($stdf_ver == 4) {
	move($orig_file, "${v4_dir}/${move_file}") or die "The move operation failed: $!";
	INFO("Moving $orig_file to $v4_dir");
}

dpExit(0);
