#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS


=head1 DESCRIPTIONS

B<This script> will translate  SIC BURN-IN files to IFF.

=head1 AUTHOR

B<junifferallan.garcia@onsemi.com>

=head1 CHANGES

=head1 LICENSE

(C) ON Semiconductor 2021 All rights reserved.

=cut

use strict;
use Getopt::Long;
use PDF::Log;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename dirname/;
use File::Copy;
use PDF::DpLoad;
use PDF::DpData;
use PDF::Parser::SiCBurnIn;
use PDF::DpWriter;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger;
use Number::Range;
use Config::Tiny;


our $VERSION = "1.0";

# a hash to receive options
my %hOptions = {};
my $pplogger = new PPLOG::PPLogger();


# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
    dpExit( 1, "No input file specified" );
}

unless (
    GetOptions (
        \%hOptions, "OUT=s", "SITE=s", "LOC=s", "FACILITYFILE=s", "LOGFILE=s", "FINALLOT", "DEBUG", "TRACE", "V", "PPLOG"
    )
)
{
  dpExit( 1,"invalid options" );
  pod2usage(3);
}

# if($hOptions{V}) {
# 	print("$VERSION\n");
# 	dpExit(0);
# }

my @required_options = qw/OUT SITE LOC FACILITYFILE/;

if(grep {!exists $hOptions{$_}} @required_options) {
	pod2usage(3);
}

PDF::Log->init(\%hOptions, $pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);
}

my $infile = $ARGV[0];
my $location = $hOptions{LOC};
my $site = $hOptions{SITE};
my $facility;
my $ret;
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
if($hOptions{FINALLOT}) {
  $facility = $config->{$location}->{finalTest};
} else {
  $facility = $config->{$location}->{probe};
}
INFO("FACILITY|EQUIP6_ID=$facility");

# check output dir
#INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
    		basename => ( basename $infile),
        ext      => 'iff',
        gzipIFF  => 'Y'
    }
);


if($infile =~ /\.gz$/i)
{
	my $command = "gunzip $infile";
	$ret = system($command);
}

if($ret == 0)	{
  $infile =~ s/\.gz$//g;
  INFO("infile = $infile");

  my $parser = PDF::Parser::SiCBurnIn->new;
  my $model = $parser->readSICBurnIn( $infile );
  my $header = $model->header;
  $header->isFinalLot(1);
  $header->EQUIP6_ID( $facility );
  $header->PROGRAM_CLASS(2);
  $model->header($header);

  $pplogger->setModelHeader($model);
  $pplogger->setLot($header->{LOT});
  $pplogger->setRawFile($infile);
  $pplogger->setEnv($site,'SICBurnIn');

  # get MEta from database
  unless ( $header->populateMeta ) {
      $wr->noMeta(1);
  }

  ### Use program naming rule

  $model->updateProgram;

  my $fmt = new_iff_formatter({
    model=>$model,
    writer=>$wr
  });

  $fmt->testItems([qw/ name units /]);
  $fmt->dataItems([qw/ partid readtime runtime ecid /]);
  $fmt->printPar();

  $model->buildLimit;
  $fmt->printLimit;
  $model->limit->input_file(basename $infile);
}



dpExit(0);
