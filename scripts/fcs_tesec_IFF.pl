#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_tesec_IFF.pl <Input flie name>
      --out <output dir>
      --loc <location e.g CP|SZ|ME>    
      --cfgtestertype < tester type>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [-V Display version ID]
=head1 DESCRIPTIONS

B<This script> will read AWW file and generate IFF file for dbascii

=head1 AUTHOR

B<jason.arp@pdf.com>

=head1 CHANGES

 2015/07/01 grace: new
 2015/07/14 grace : added SMAP:: to program 
 2015/07/23 eric  : move SMAP:: to FMT script. apply ppid rule

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Getopt::Long;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use POSIX qw(strftime);
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Parser::TESEC;
use PDF::Formatter;
use v5.10;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;

our $VERSION = "

1.0
";
our $TESTER  = "TESEC";

my (%hOptions) = ();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "LOGFILE=s", "DEBUG", "LOC=s", "V", "CONFIG=s",
        "FINALLOT", "TRACE", )
    )
{
    dpExit( 1, "invalid options" );
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT LOC CONFIG/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions );

unless ( $hOptions{LOC} ) {
    dpExit ( 1, "--loc must be specified" );
    pod2usage(3);
}

# Read input file
my $infile = $ARGV[0];
if ( !-f $infile ) {
    pod2usage();
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
open( INFILE, $infile );

# Start input file reading
my $parser = PDF::Parser::TESEC->new;

my $model = $parser->readFile( $infile,$hOptions{CONFIG} );
my $header = $model->header;
$header->isFinalLot($hOptions{FINALLOT});

$wr->noMeta(1) unless ( $header->populateMeta );
$header->VERSION($VERSION);
$header->EQUIP6_ID( $hOptions{LOC} );
$header->CFG_TESTER_TYPE( $hOptions{CONFIG} );

my $wmap = $model->updateWMap;
if (defined $wmap) {
        $wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
        unless ( $wmap->confirmed ) {
                $wr->noWMap(1);
        }
}
else {
        $wmap = new_wmap;
        $wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
        $wr->noWMap(1);
        $model->wmap($wmap);
}

my $program = $header->PROGRAM;
my $map_typ = "STD_";
if (length($program) + length($map_typ) > 35) {
	INFO("PROGRAM NAME \"".$map_typ.$program."\" will be truncated to 35 characters. Sending to sandbox.");
	$wr->forSBox(1);
	$program = substr($program, 1, 35-length($map_typ));
}
$header->PROGRAM($map_typ.$program);
$model->updateProgram("MAP_PGM");

my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);
$formatter->dataItems([qw/x y soft_bin/]);
$formatter->printBinmap;

dpExit(0);

