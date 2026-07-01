#!/usr/bin/env perl_db
#
# 08-Apr-2020 Eric Alfanta : new
# 12-Oct-2020 Karen 	   : Added fork location
# 30-Apr-2021 jgarcia : modified to be able to work on colo server.
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


my (%hOptions) = ();

if ( $#ARGV < 0 ) {
        pod2usage();
        dpExit(1, "No input file specified.");
}
unless (
        GetOptions(\%hOptions,  "OUT=s", "LOGFILE=s", "REF=s", "EXT=s", "FORK=s", "DELSOURCE")
)
{
        dpExit(1, "Invalid options.");
}

my @required_options = qw/OUT REF/;

if (grep { !exists $hOptions{$_} } @required_options) {
        pod2usage(4);
}

#initialize logging
PDF::Log->init(\%hOptions);

my $infile = $ARGV[0];
my $outdir = $hOptions{OUT}."/PRODUCTION";
my $reffile  = $hOptions{REF};
my $ext = $hOptions{EXT};
my $del = $hOptions{DELSOURCE};
my $forkDir = $hOptions{FORK};

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
INFO("Reference file = $reffile");
INFO("Extension = $ext");


my $hdr = loadREF($reffile, $ext);

my $fname = basename $infile;
my $dname = dirname $infile;
my $outfile = "${outdir}/${fname}";
my $hdrCnt = 0;


open my $in, '<', $infile or die "Can't read input file: $!";
open my $out, '>', $outfile or die "Can't write to new file: $!";

while(my $line = <$in>) {
	#print $line if $line =~ /$hdr/;
	if ($line =~ /$hdr/) {
		$hdrCnt++;
	}

	if ($line =~ /$hdr/ && $hdrCnt > 1) {
		WARN("Duplicate headers found!");
		next;
	}

        print $out $line;
}
close $out;

if (-e $outfile) {
        INFO("Success!");
	if($forkDir ne "") {
		#my $forkFilename = "${forkDir}/${fname}";
		forkFile($outfile, $forkDir, $fname, "", "PRODUCTION");

	} else {
		INFO("Not setup to fork file to specified location.");
    INFO("Compress $outfile with gzip");
		my $gzOutfile = $outfile.".gz";
		if(-e $gzOutfile) {
			INFO("$gzOutfile already exist");
			INFO("Delete $gzOutfile");
			unlink $gzOutfile;
		}
		qx(gzip "$outfile");
	}
    if ($del) {
		unlink $infile;   #delete orig file if success
	}
}
else {
        ERROR("Failed!");

}

dpExit(0);


sub loadREF {
	my $ref = shift;
	my $ext = shift;
	my $hdr = "";

	open REF, "<$ref" or die "Could not open reference file. $!";
	while (my $line=<REF>) {
		chomp $line;
		my($field,$val) = split/\=/, $line;

		if ($field eq $ext) {
			$hdr = $val;
			last;
		}
	}
	close REF;

	return $hdr;
}
