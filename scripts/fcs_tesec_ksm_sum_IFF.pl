#!/usr/bin/env perl_db
# SVN $Id: fcs_tesec_ksm_sum_IFF.pl 
=pod

=head1 SYNOPSIS

      fcs_tesec_ksm_sum_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
      --loc <location>
      [-config <config_tester_type>]
      [--logfile <logfilepath>]
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read KSM file and output IFF file

=head1 AUTHOR

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

2016-Apr-04 Eric	: new
2017-Mar-23 Eric	: assign source lot as wafer name

=head1 LICENSE

(C) Fairchild Semiconductor Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DAO;
use PDF::Parser::Tesec_Ksm;
use PDF::Formatter;
use PDF::DpWriter;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);
use Time::localtime;
use File::stat;
use Time::Piece;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:

our $VERSION = "1.0";
our $TESTER  = "TESEC";

# a hash to receive options
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions,  "OUT=s", "FINALLOT",
        "LOGFILE=s", "DEBUG", "TRACE", "V", "TYPE=s","LOC=s",  "CONFIG=s", "PPLOG"
    )
    )
{
    dpExit( 1, "invalid options" );
}

if($hOptions{V})
{
        print("$VERSION\n");
        dpExit(0);
};

# Initialize logging
my @required_options = qw/OUT LOC/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $location     = $hOptions{LOC};

# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    dpExit( 1, "input file does not exist $infile" );
}

# check output dir
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        basename => ( basename $infile),
        ext      => 'iff'
    }
);

INFO("infile  = $infile");

my $parser = PDF::Parser::Tesec_Ksm->new;

my $model = $parser->readFile($infile,isLogDebug);

my $header = $model->header;
   $header->isFinalLot($hOptions{FINALLOT});
   $header->VERSION($VERSION);
   $header->REVISION(1);
   $header->PROGRAM_CLASS(12);
   $header->EQUIP6_ID( $hOptions{LOC} );

my $program = $header->PROGRAM;

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

# truncate ppid 
if (length($program) > 35) {
	INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
        $wr->forSBox(1);
        $program = substr($program, 1, 35);
}
$header->PROGRAM($program);

# look up lotid in ref db
$wr->noMeta(1) unless ($header->populateMeta);

# assign source lot as wafer name
if ($header->SOURCE_LOT ne "") {
	$model->wafers->[0]->name($header->SOURCE_LOT."_".sprintf("%02d",$model->wafers->[0]->number));	
	$pplogger->setWaferFlag(1);
}
$model->updateProgram;


my $formatter = new_iff_formatter(
	{   model  => $model,
            writer => $wr
        }
);

$formatter->testItems([qw/number name units /]);
$formatter->printPar;

dpExit(0);
