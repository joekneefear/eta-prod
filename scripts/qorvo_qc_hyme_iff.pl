#!/bin/env perl_db
#
# 25-Feb-2025 Eric A.   initial release

use strict;
use FindBin::libs;
use PDF::Parser::HYME_STATEC_CSV;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use PDF::DpWriter;
use PDF::Formatter;
use PDF::WS;
use PPLOG::PPLogger;
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
                \%hOptions,  "OUT=s", "LOGFILE=s", "DEBUG", "TRACE", "DATATYPE=s", "PPLOG" 
        )
)
{
        print "Invalid options.\n";
        exit;
}

my @required_options = qw/OUT DATATYPE/;

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
my $datatype = $hOptions{DATATYPE}; 
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

my $writer = PDF::DpWriter->new({ outdir => $hOptions{OUT}, basename => $fname, ext => 'iff', gzipIFF => 'Y', appendTimestampInFilename => 0});
my $parser = PDF::Parser::HYME_STATEC_CSV->new;
#my $model = $parser->readFile($infile,isLogDebug);
my $model;
if ($datatype eq "FT") {
	$model = $parser->readFileFT($infile,isLogDebug);
}
elsif ($datatype eq "RG") {
	$model = $parser->readFileRG($infile,isLogDebug);
}
elsif ($datatype eq "DVDS") {
	$model = $parser->readFileDVDS($infile,isLogDebug);
}
elsif ($datatype eq "EAS") {
	$model = $parser->readFileEAS($infile,isLogDebug);
}
elsif ($datatype eq "UIS") {
	$model = $parser->readFileUIS($infile,isLogDebug);
}
elsif ($datatype eq "QC") {
	$model = $parser->readFileQC($infile,isLogDebug);
}
else {
	dpExit(1,"Invalid datatype argument: $datatype");
}

my $header = $model->header;
$header->SOURCE_LOT($header->{LOT}.".S");

$pplogger->setModelHeader($model);

my $formatter = new_iff_formatter({ model => $model, writer => $writer });
$formatter->dataItems([qw/partid soft_bin hard_bin bindesc touchdown_num ecid site testtime/]);
$formatter->testItems([qw/number name units LSL HSL/]);
$formatter->binItems ([qw/number name PF count/]);
$formatter->printPar();
#$model->buildLimit;
#$formatter->printLimit;

# delete residue extracted files
unlink $dcom_file if $infile =~ /\.zip/i;

dpExit(0);
