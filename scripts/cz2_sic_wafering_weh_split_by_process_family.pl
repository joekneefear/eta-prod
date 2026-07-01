#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS


=head1 DESCRIPTIONS

B<This script> will process split by process_family LEH/WEH data from CZ2

=head1 AUTHOR

B<junifferallan.garcia@onsemi.com>

=head1 CHANGES
	2020/06/20 jgarcia : initial


=head1 LICENSE

(C) onsemi 2020 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use File::Basename qw/basename dirname/;
use PDF::Formatter;
use PDF::Log;
use PDF::DpLoad;
use PDF::Parser::CZ2Weh;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

# a hash to receive options
my (%hOptions) = ();

#Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

unless ( GetOptions ( \%hOptions, "OUT=s", "FORK=s",  "LOGFILE=s", "DEBUG", "TRACE", "V") ) {
    pod2usage(3);
}

my @required_options = qw/OUT/;

PDF::Log->init( \%hOptions, $pplogger);
if ($hOptions{PPLOG}){
  $pplogger->settobeLog(1);  #Set flag for pp logging
}

my $outdir = $hOptions{OUT};
my $infile = $ARGV[0];
my $uncompressedFile = $infile;
my $parser = PDF::Parser::CZ2Weh->new;

if($uncompressedFile =~ /\.gz$/i) {
  $uncompressedFile =~ s/\.gz$//g;
  gunzip $infile => $uncompressedFile or dpExit("$GunzipError");
}

my $model = $parser->readPerLineAndSplitByProcessFamily($uncompressedFile);

my $wr = PDF::DpWriter->new(
         {   outdir   => $outdir,
          basename => ( basename $infile),
          ext      => 'txt',
          gzipIFF  => 'Y'
        }
    );

  my $fmt = new_iff_formatter({
      model=>$model,
      writer=>$wr
  });

  $fmt->printLineHashArray();

dpExit(0);
