#!/bin/env perl_db
#
# 2020-Mar-26 Eric Alfanta       : new
#


use strict;
use FindBin::libs;
use PDF::DpLoad;
use PDF::Log;
use PDF::Util::Utility;
use Getopt::Long;
use File::Basename;
use File::Copy;
use Pod::Usage qw/pod2usage/;

our $VERSION ="1.0";

my (%hOptions) = ();

if ( $#ARGV < 0 ) {
        print "Usage: $0 <FILENAME> --OUT1 <DESTINATION_DIR1> --OUT2 <DESTINATION_DIR2>\n";
        exit 1;
}
unless (
        GetOptions(
                \%hOptions,  "OUT1=s", "OUT2=s", "LOGFILE=s", "DEBUG", "TRACE"
        )
)
{
	print "Invalid options.\n";
        exit;
}

my @required_options = qw/OUT1 OUT2/;

if (grep { !exists $hOptions{$_} } @required_options) {
        print "Error! Missing required options.\n";
        exit 1;
}

PDF::Log->init(\%hOptions);

my $infile = $ARGV[0];

if ( ! -f $infile ) {
        dpExit(1,"Error! File does not exists.");
}

INFO ("Infile = $infile");

my $des1_dir = $hOptions{OUT1};
my $des2_dir = $hOptions{OUT2};


if ($infile =~ /\.zip$/) {
        my $dcom_file = doUnzipA($infile);

        
	foreach my $ext_file (@$dcom_file) {
        	$ext_file = trim ($ext_file);
		INFO("Extracted file = $ext_file");
=pod
        	my $fname = basename $ext_file;
		my $mv_fname = "";

        	system  "mkdir -p $des1_dir" if ( !-e $des1_dir );
		system  "mkdir -p $des2_dir" if ( !-e $des2_dir );
	
		if ($ext_file =~ /\.xml$|\.csv$/i) {
        		$mv_fname = "${des1_dir}/${fname}";
			move($ext_file, $mv_fname);
                	my $status = ( -e $mv_fname) ? "Successful" : "Fail";
                	INFO("Moving $fname to $des1_dir : $status");
		}
		elsif ($ext_file =~ /\.wmxml$|\.ret$|\.waf$/i) {
			$mv_fname = "${des2_dir}/${fname}";
			move($ext_file, $mv_fname);
                	my $status = ( -e $mv_fname) ? "Successful" : "Fail";
                	INFO("Moving $fname to $des2_dir : $status");
		}
=cut
		moveFileByExt($ext_file,$des1_dir,$des2_dir);

	}

	unlink $infile;

}
elsif ($infile =~ /\.gz$/) {
	my $dcom_file = $infile;
	$dcom_file = doUncompress($infile);
	$dcom_file = trim($dcom_file);

	INFO ("UnGzipped file = $dcom_file");

=pod
	my $fname = basename $dcom_file;
	
	system  "mkdir -p $des1_dir" if ( !-e $des1_dir );
	system  "mkdir -p $des2_dir" if ( !-e $des2_dir );

	if ($ext_file =~ /\.xml$|\.csv$/i) {
		$mv_fname = "${des1_dir}/${fname}";
		move($ext_file, $mv_fname);
		my $status = ( -e $mv_fname) ? "Successful" : "Fail";
		INFO("Moving $fname to $des1_dir : $status");
	}
	elsif ($ext_file =~ /\.wmxml$|\.ret$|\.waf$/i) {
		$mv_fname = "${des2_dir}/${fname}";
		move($ext_file, $mv_fname);
		my $status = ( -e $mv_fname) ? "Successful" : "Fail";
		INFO("Moving $fname to $des2_dir : $status");
	}

=cut
	
	moveFileByExt($dcom_file,$des1_dir,$des2_dir);

	
}
else {
	#my $notprocessed = "${des1_dir}/NotProcessed";
	#my $fname = basename $infile;
	#system  "mkdir -p $notprocessed" if ( !-e $notprocessed );

	#move($infile,"${notprocessed}/${fname}");
	dpExit(1,"Invalid zipped archive format");
}


dpExit(0);


sub moveFileByExt {
	my $fle = shift;
	my $des1_dir = shift;
	my $des2_dir = shift;

	my $fname = basename $fle;
	my $des3_dir = dirname $fle;
	   $des3_dir = "${des3_dir}/UnknownFiles";
	my $mv_fname = "";

	system  "mkdir -p $des1_dir" if ( !-e $des1_dir );
        system  "mkdir -p $des2_dir" if ( !-e $des2_dir );
	system  "mkdir -p $des3_dir" if ( !-e $des3_dir );

	if ($fle =~ /\.xml$|\.csv$/i) {
		$mv_fname = "${des1_dir}/${fname}";
		move($fle, $mv_fname);
		my $status = ( -e $mv_fname) ? "Successful" : "Fail";
		INFO("Moving $fname to $des1_dir : $status");
	}
	elsif ($fle =~ /\.wmxml$|\.ret$|\.waf$/i) {
		$mv_fname = "${des2_dir}/${fname}";
		move($fle, $mv_fname);
		my $status = ( -e $mv_fname) ? "Successful" : "Fail";
		INFO("Moving $fname to $des2_dir : $status");
	}
	else {
		$mv_fname = "${des3_dir}/${fname}";
		move($fle, $mv_fname);
		my $status = ( -e $mv_fname) ? "Successful" : "Fail";
		INFO("Moving $fname to $des2_dir : $status");		
	}
	
}
