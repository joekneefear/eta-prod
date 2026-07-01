#!/bin/env perl_db
#
# 23-May-2024 Eric A. 	initial release
# 24-Jun-2024 Eric A. 	modified to handle dynamic headers

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
use IO::Uncompress::Unzip qw(unzip $UnzipError);

our $VERSION ="1.0";

my (%hOptions) = ();

if ( $#ARGV < 0 ) {
        print "Usage: $0 <FILENAME> <OPTIONS>\n";
        exit 1;
}
unless (
        GetOptions(
                \%hOptions,  "OUT=s", "SEPARATOR=s", "SPLITCOLUMN=s", "LOGFILE=s", "DEBUG", "TRACE", "ALERT" 
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
#my $header = $hOptions{HEADER};
my $separator = $hOptions{SEPARATOR};
my $column = $hOptions{SPLITCOLUMN};
my $alert = $hOptions{ALERT};
my $enrfile = "";

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
elsif ($infile =~ /\.zip$/) {
        $dcom_file =~ s/\.zip$//;
	unzip $infile => $dcom_file or die "unzip failed: $UnzipError\n";
        INFO ("UnZipped file = $dcom_file");
}

my $header = getHeaderLoc($dcom_file);

my $fname = basename $dcom_file;
$enrfile = "${outdir}/${fname}";
my $grpHead = `head -${header} $dcom_file`;	#headers
my @arrHead = split /^/, $grpHead;	#split headers

#remove new line
foreach my $h (@arrHead){
	chomp $h;
	$h = trim($h);
	$h =~ s/\=$/\=NA/g;
}

my $ln_cnt = 0;
my $wafer = "";

open my $in, '<',  $dcom_file or die "Can't read input file: $dcom_file $!";
my $out;
my $fle_cnt = 0;

while(my $line = <$in>) {
	$ln_cnt++;
	my @arr = split(/[{$separator}]/, $line);
	
	#replace empty elements with NA
	foreach my $e (@arr) {
			#$e = repNA($e);
			$e = repValNA($e);
	}
	my $line_out = join($separator, @arr);
	
	if ($ln_cnt > $header) {	
		
		$arr[$column] = trim($arr[$column]);

		#start splitting
		#if ($wafer !~ /$arr[$column]/) {		
		if ($wafer ne $arr[$column]) {
			close $out if $out;
			$wafer = trim($arr[$column]);
			#print "$wafer\n";
			my $wafer_fn = $wafer;
			$wafer_fn =~ s/\s+//g;

			$fle_cnt++;

			#INFO ("Output file = ${enrfile}.${wafer_fn}.${fle_cnt}");
			INFO ("Output file = ${enrfile}.${wafer_fn}");
	
			#open $out, '>', $enrfile.".".$wafer_fn.".".$fle_cnt or die "Can't write to split file:$!";
			open $out, '>', $enrfile.".".$wafer_fn or die "Can't write to split file:$!";
			
			#output headers
			foreach my $h (@arrHead) {
				print $out $h,"\n";
			}
			
		}
		#print the rest of the line			
		#print $out $line;
		print $out $line_out,"\n";
	}


}
close $out;
close $in;

# delete residue extracted files
unlink $dcom_file if $infile =~ /\.zip/i;

dpExit(0);



sub repValNA {
	my $data = trim(shift);
	if ( ( $data eq '' ) or ( !defined($data) or $data =~ /null|undef/i) ) {
		return 'NA';
	}
	else {
		return $data;
	}	
}

sub getHeaderLoc {
	my $dcom_file = shift;
	open my $in, '<',  $dcom_file or die "Can't read input file: $dcom_file $!";
	my $linenum;

	while(my $line = <$in>) {
	    $linenum = $., last if $line =~ /^\[data\]/;
	}
	close $in;

	if (defined $linenum) {
		INFO("Found match on line $linenum");
		return $linenum + 1;
	} else {
		dpExit(1,"No [data] header found.");
	}	
}
