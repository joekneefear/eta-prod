#!/usr/bin/env perl_db
# 2016-Jun-27 Eric	: Initial release
#
# Function: Move file to correct directory according to file extension

use strict;
use warnings;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::Log;
use PDF::Parser::Stdf;
use PDF::Parser::Stdf::Generic;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);
use PDF::DpLoad;
use File::Copy;
use Time::Local;

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
my $move_file = basename($infile);
my @fn = split /\./, $move_file;
my $accu_dir = "/apps/exensio_data/data/meet/ACCU";
my $rdhm_dir = "/apps/exensio_data/data/meet/RDHM";
my $tp_dir = "/apps/exensio_data/data/meet/TP";
my $status;

if ($infile =~ /\.HP_LMT.+$|\.DAT.+$/i) {
	system "/bin/cp -f \'${infile}\' ${tp_dir}/${move_file}";
        $status = (-e "${tp_dir}/${move_file}") ? "Successful" : "Failed";
}
elsif ($infile =~ /\.ACCU.+$/i ) {
	system "/bin/cp -f \'${infile}\' ${accu_dir}/${move_file}";
        $status = (-e "${accu_dir}/${move_file}") ? "Successful" : "Failed";
}
elsif ($infile =~ /\.RH_STDF.+$/i ) {
	my $txtfile = convertBinToAscii($infile);
	my $tp_flg = "N";
	my $tpname;
	my $tprev;
	open FH, $txtfile or die "can't open $txtfile: $!\n";
	while(my $line = <FH>) {
		if ($line =~ /SPEC_NAM/) {
			my @item = split /\=/, $line;
			$tpname = cleanSTR($item[1]);
		}
		elsif ($line =~ /SPEC_REV/) {
			my @item = split /\=/, $line;
			$tprev = cleanSTR($item[1]);
		}
		elsif ($line =~ /EPDR/) {
			$tp_flg = "Y";
		}
	}
	close (FH);
	
	if ($tp_flg eq "Y") {
		system "/bin/cp -f \'${infile}\' ${tp_dir}/${fn[0]}_REV_${tprev}.${fn[1]}.TP";
        	$status = (-e "${tp_dir}/${fn[0]}_REV_${tprev}.${fn[1]}.TP") ? "Successful" : "Failed";
	}
	elsif ($tp_flg eq "N") { 
		system "/bin/cp -f \'${infile}\' ${rdhm_dir}/${move_file}";
        	$status = (-e "${rdhm_dir}/${move_file}") ? "Successful" : "Failed";
	}
	unless (isLogDebug) {
	    unlink $txtfile;
	}
}

INFO ("Copying $infile $status");


sub cleanSTR
{
        my $str = shift;
           $str =~ s/^\s+|\s+$//g;
           $str =~ s/\,//g;
           $str =~ s/\s+/_/g;
        return($str);
}

dpExit(0);
