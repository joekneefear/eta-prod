#!/usr/bin/env perl_db
# 2018-May-21 Eric	: Initial release
#
# Function: Move file to correct directory according to file extension

use strict;
use warnings;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::Log;
use PDF::DpWriter;
use PDF::Parser::Stdf;
use PDF::Parser::Stdf::Generic;
use File::Basename qw/basename dirname/;
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
my $fname = basename($infile);
my $curr_dir = dirname($infile);
my @item = split /\./, $fname;
my $ext = $item[$#item];
my $move_dir = "";
my $move_fle = "";
my $status = "";
my $tp_flg = "N";


if ( $ext =~ /HP_LMT|DAT/ig ) {
	$move_dir = $curr_dir."/TP";
}
elsif ( $ext =~ /ACCU|HP_LGA/i ) {
	$move_dir = $curr_dir."/ACCU";
}
elsif ( $ext =~ /RH_STDF|STDF/i ) {
	my $txtfile = convertBinToAscii($infile);
	my $tpname;
	my $tprev;
	open FH, $txtfile or die "can't open $txtfile: $!\n";
	while(my $line = <FH>) {
		if ($line =~ /SPEC_NAM/) {
			my @rec = split /\=/, $line;
			$tpname = cleanSTR($rec[1]);
		}
		elsif ($line =~ /SPEC_REV/) {
			my @rec = split /\=/, $line;
			$tprev = cleanSTR($rec[1]);
		}
		elsif ($line =~ /EPDR/) {
			$tp_flg = "Y";
		}
	}
	close (FH);
	
	if ($tp_flg eq "Y") {
		$move_dir = $curr_dir."/TP";	
		$fname = "${tpname}_REV_${tprev}.${ext}.TP";
	}
	elsif ($tp_flg eq "N") { 
		$move_dir = $curr_dir."/RDHM";
	}
	unless (isLogDebug) {
	    unlink $txtfile;
	}
}
else {
	ERROR ("Unregnized file extension.");
	$move_dir = $curr_dir."/NotProcessed";
}

move($infile,$move_dir."/".$fname);
$status = (-e "${move_dir}/${fname}") ? "Successful" : "Failed";
INFO ("Moving $fname to $move_dir $status");

dpExit(0);

sub cleanSTR
{
        my $str = shift;
           $str =~ s/^\s+|\s+$//g;
           $str =~ s/\,//g;
           $str =~ s/\s+/_/g;
        return($str);
}

