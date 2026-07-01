#!/bin/env perl_db
#
# 21-Jun-2024 Eric A. 	initial release
# 26-Sep-2024 Eric A.	modified to handle files that were edited and save from Excel
# 21-Oct-2024 Eric A.	removd control characters and improve parsing the CSV file sometimes does not match the number of commas in the results section to the number of test parameter causing the data to be mis-aligned when loaded to Exensio
# 17-Dec-2025 Eric A.	removed results that are not aligned to the test parameter.

use strict;
use FindBin::libs;
use PDF::DpData;
use PDF::DpLoad;
use PDF::DAO;
use PDF::Log;
use PDF::DpWriter;
use PDF::Formatter;
use PDF::WS;
use Getopt::Long;
use File::Basename;
use Data::Dumper;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Compress::Gzip qw(gzip $GzipError);
#use IO::Uncompress::Unzip qw(unzip $UnzipError);

our $VERSION ="1.0";

my (%hOptions) = ();

if ( $#ARGV < 0 ) {
        print "Usage: $0 <FILENAME> <OPTIONS>\n";
        exit 1;
}
unless (
        GetOptions(
                \%hOptions,  "OUT=s", "SEPARATOR=s", "LOGFILE=s", "DEBUG", "TRACE" 
        )
)
{
        print "Invalid options.\n";
	exit;
}

my @required_options = qw/OUT SEPARATOR/;

if (grep { !exists $hOptions{$_} } @required_options) {
        print "Error! Missing required options.\n";
	exit 1;
}

PDF::Log->init(\%hOptions);

my $infile = $ARGV[0];
my $outdir = $hOptions{OUT};
my $separator = $hOptions{SEPARATOR};
my $enrfile = "";
my $comp_file = "";

if ( ! -f $infile ) {
	dpExit(1,"Error! File does not exists.");
}
 
INFO ("Input file = $infile");

my $dcom_file = $infile;

if ($infile =~ /\.gz$/) {
        $dcom_file =~ s/\.gz$//;
	gunzip $infile => $dcom_file or die "gunzip failed: $GunzipError\n";
        INFO ("UnGzipped file = $dcom_file");
}
#elsif ($infile =~ /\.zip$/) {
#        $dcom_file =~ s/\.zip$//;
#	unzip $infile => $dcom_file or die "unzip failed: $UnzipError\n";
#        INFO ("UnZipped file = $dcom_file");
#}

my $fname = basename $dcom_file;
$enrfile = "${outdir}/${fname}";
$comp_file = "${outdir}/${fname}.gz";
my @serialArr;

my $ln_cnt = 0;
my $splitFlg = "N";

open my $in, '<',  $dcom_file or die "Can't read input file: $dcom_file $!";

my $out;
open $out, '>', $enrfile or die "Can't write to split file:$!";

while(my $line = <$in>) {
	#print $line, "\n";
	chomp $line;
	$line =~ s/\cM//g;
	$ln_cnt++;
	$line =~ s/:,/:NA,/g;
	
	if ($line =~ /^SerialNumber/) {
		$splitFlg = "Y";		
		@serialArr = split(/[{$separator}]/, $line);
	}

	if ($splitFlg eq "Y") {
		my @arr = split(/[{$separator}]/, $line);
		my @new_arr = ();
		my $i = 0;
		foreach my $e (@serialArr){
			$new_arr[$i] = repValNA($arr[$i]);
			$i++;
		}
		$line = join($separator, @new_arr);
	}

	print $out $line,"\n";
}
close $out;
close $in;

gzip $enrfile => $comp_file or dpExit(1,"gzip failed: $GzipError");

INFO("Output file = $enrfile");
INFO("Gzipped Output file = $comp_file");

# delete residue extracted files
#unlink $dcom_file if $infile =~ /\.zip/i;
unlink $enrfile; 
unlink $dcom_file if $infile =~ /\.gz/i;

dpExit(0);

#### sub routine ####

sub repValNA {
	my $data = trim(shift);
	if ( ( $data eq '' ) or ( !defined($data) or $data =~ /null|undef/i) ) {
		return 'NA';
	}
	else {
		return $data;
	}	
}

