#!/usr/bin/env perl_db
# 2016-Apr-19 Eric      : Initial release
# 2017-Dec-05 Eric	: Improved REL lot identification. Added filter to identify ONRMS lots
#
# Function: Identifies incoming LOG files if it came from REL or Sort 

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DAO;
use PDF::Log;
use File::Basename qw/basename/;
use File::Path;
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

my $orig_file = $infile;
my $root_file = basename($infile);
my $rel_dir   = "/apps/exensio_data/data/merel_eagle/REL";
my $ft_dir    = "/apps/exensio_data/data/meft_eagle/FT";
my $rstg_dir = "/apps/exensio_data/data/merel_eagle/REL/stage";
my $fstg_dir = "/apps/exensio_data/data/meft_eagle/FT/stage"; 
#my $rel_dir = "/home/dpower/project/work/eric/data/merel_eagle/REL";
#my $ft_dir = "/home/dpower/project/work/eric/data/meft_eagle/FT";
#my $rstg_dir = "/home/dpower/project/work/eric/data/merel_eagle/REL/stage";
#my $fstg_dir = "/home/dpower/project/work/eric/data/meft_eagle/FT/stage";

# extract data type at record 125
my ($rec_type, $data_type, $junk) = split /,/, `head -5 $infile|grep "^125,"`, 3;
my $status;

my @item    = split /\_|\./, $root_file;
my $lot     = $item[0];
my $devchar = substr $item[0], 8, 1;
my $lotchar = substr $item[0], 9, 1;
my $lot_len = length($lot);
#print "$qpnum=$devchar=$lotchar=$req_id=$lot_len\n";

if ($lot =~ /^20/ && $lot_len == 10 && $devchar =~ /^[A-Z]/i && $lotchar =~ /^[A-Z]/i && $data_type eq "P") {
	if (! -e $rel_dir) {
		mkpath($rel_dir);
		mkpath($rstg_dir);
	}	
	move($orig_file, "${rel_dir}/${root_file}");
	$status = (-e "${rel_dir}/${root_file}") ? "Successful" : "Failed";
	INFO ("Moving $infile to $rel_dir - $status");		
}
elsif ( $lot =~ /^W/ && $data_type eq "P" && $lot_len == 7 ) {
	if (! -e $rel_dir) {
                mkpath($rel_dir);
                mkpath($rstg_dir);
        }
	move($orig_file, "${rel_dir}/${root_file}");
        $status = (-e "${rel_dir}/${root_file}") ? "Successful" : "Failed";
        INFO ("Moving $infile to $rel_dir - $status");
}
else {
	if (! -e $ft_dir) {
                mkpath($ft_dir);
                mkpath($fstg_dir);
        }
	move($orig_file, "${ft_dir}/${root_file}");
	$status = (-e "${ft_dir}/${root_file}") ? "Successful" : "Failed";
	INFO ("Moving $infile to $ft_dir - $status");	
}

dpExit(0);
