#!/usr/bin/env perl_db
#
# 04-Jul-2023 Eric Alfanta : new
#

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use PDF::Log;
use PDF::DpLoad;
use Getopt::Long qw/:config ignore_case auto_help/;
use Pod::Usage qw/pod2usage/;
use File::Basename;
use IO::Compress::Gzip qw(gzip $GzipError) ;
use File::Copy;


my (%hOptions) = ();

if ( $#ARGV < 0 ) {
        pod2usage();
        dpExit(1, "No input file specified.");
}
unless (
        GetOptions(\%hOptions,  "OUTDIR=s", "LOGFILE=s")
)
{
        dpExit(1, "Invalid options.");
}

my @required_options = qw/OUTDIR/;

if (grep { !exists $hOptions{$_} } @required_options) {
        pod2usage(4);
}

#initialize logging
PDF::Log->init(\%hOptions);

my $infile = $ARGV[0];
my $outdir = $hOptions{OUTDIR}."/PRODUCTION";

if ( ! -f $infile ) {
        pod2usage();
        dpExit(1,"Input file does not exists.");
}

if(!(-e $outdir)) {
	unless ( mkdir($outdir, 0777) ) {
		dpExit(1,"Unable to create $outdir");
	}
}

INFO("Infile = $infile");
INFO("Output Dir = $outdir");

my $filename = basename $infile;
my $filedir = dirname $infile;
my $outfile = "${outdir}/${filename}.gz";

#compress file
gzip $infile => $outfile or WARN ("gzip failed: $GzipError");

my $status = (-e $outfile) ? "Successful" : "Failed";

INFO ("Copying $infile to $outdir - $status");

dpExit(0);
