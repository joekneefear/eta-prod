#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS
  isg_assembly_genealogy_ft.pl <Input file>
      	--out <output dir>
      	--event_type <event type eg. WGEN>
      	--step <step eg. TEST>
      	--fork
      	[--logfile <logfilepath>]
      	[--debug|--trace]
  	


=head1 DESCRIPTIONS

B<This script> will generate wafer level assembly genealogy file from ISG FT XML

=head1 AUTHOR

B<junifferallan.garcia@onsemi.com>

=head1 CHANGES
	2022/11/21 jgarcia : initial


=head1 LICENSE

(C) onsemi 2023 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use File::Basename qw/basename dirname/;
use PDF::Formatter;
use PDF::Log;
use PDF::DpLoad;
use PDF::Parser::ISGTRACEFTXML;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

# a hash to receive options
my (%hOptions) = ();

my $pplogger = new PPLOG::PPLogger();

unless ( GetOptions ( \%hOptions, "OUT=s", "EVENT_TYPE=s", "STEP=s", "FORK=s", "THRESHOLD=s", "LOGFILE=s", "DEBUG", "TRACE", "V") ) {
    pod2usage(3);
}

my @required_options = qw/OUT EVENT_TYPE STEP/;

PDF::Log->init( \%hOptions, $pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  
}

my $outdir = $hOptions{OUT};
my $eventType = $hOptions{EVENT_TYPE};
my $step = $hOptions{STEP};
my $infile = $ARGV[0];
my $uncompressedFile = $infile;
my $parser = PDF::Parser::ISGTRACEFTXML->new;
my $model;
my $threshold = $hOptions{THRESHOLD};

if($uncompressedFile =~ /\.gz$/i) {
  $uncompressedFile =~ s/\.gz$//g;
  gunzip $infile => $uncompressedFile or dpExit("$GunzipError");
}
$model = $parser->parseISGFTXML($uncompressedFile, $eventType, $step, $threshold);
#INFO("TEST----");
#dpExit 0;

my $wr = PDF::DpWriter->new(
         {   outdir   => $outdir,
          basename => ( basename $infile),
          ext      => 'isgtrace',
          gzipIFF  => 'Y'
        }
    );

  my $fmt = new_iff_formatter({
      model=>$model,
      writer=>$wr
  });

  $fmt->printLineHashArray();

dpExit(0);
