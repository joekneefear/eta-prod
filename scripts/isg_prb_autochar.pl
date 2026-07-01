#!/bin/env perl_db
#
# 20-May-2024 Eric A.   initial release

use strict;
use FindBin::libs;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use PDF::DpWriter;
use PDF::Formatter;
use PPLOG::PPLogger;
use PDF::Parser::AutoChar;
use Getopt::Long;
use File::Basename qw(basename dirname);
use Data::Dumper qw(Dumper);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use v5.10;

our $VERSION ="1.0";

my (%hOptions) = ();
my $pplogger = new PPLOG::PPLogger();

if ( $#ARGV < 0 ) {
        print "Usage: $0 <FILENAME> <OPTIONS>\n";
        exit 1;
}
unless (
        GetOptions(
                \%hOptions,  "OUT=s", "LOGFILE=s", "DEBUG", "TRACE", "ARCHIVE=s", "PPLOG"
        )
)
{
        print "Invalid options.\n";
        exit;
}

my @required_options = qw/OUT/;

if (grep { !exists $hOptions{$_} } @required_options) {
        print "Error! Missing required options.\n";
        exit 1;
}

PDF::Log->init(\%hOptions ,$pplogger);
if ($hOptions{PPLOG}){
        $pplogger->settobeLog(1);
}

my $infile = $ARGV[0];
my $outdir = $hOptions{OUT};
my $arcdir = $hOptions{ARCHIVE};
my $fname = basename $infile;

$pplogger->setRawFile($infile);

if ( ! -f $infile ) {
        dpExit(1,"Error! File does not exists.");
}


INFO ("Infile = $infile");

my $dcom_file = $infile;
if ($infile =~ /\.gz$/) {
        $dcom_file =~ s/\.gz$//;
        gunzip $infile => $dcom_file or die "gunzip failed: $GunzipError\n";
        INFO ("UnGzipped file = $dcom_file");
}
elsif ($infile =~ /\.zip$/) {
        $dcom_file =~ s/\.zip$//;
        unzip $infile => $dcom_file or die "unzip failed: $UnzipError\n";
        INFO ("UnZipped file = $dcom_file");
}

my $parser = PDF::Parser::AutoChar->new;
my $model = $parser->parseAutoChar($dcom_file);

my $wr = PDF::DpWriter->new(
         {  outdir   => $outdir,
			basename => ( basename $infile),
			ext      => 'iff',
			gzipIFF  => 'Y'
        }
    );

my $fmt = new_iff_formatter({
		model => $model,
		writer => $wr
	});

$fmt->printAutoChar();

dpExit(0);
