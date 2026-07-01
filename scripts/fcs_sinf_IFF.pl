#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_sinf_IFF.pl <Input flie name>
      --out <output dir>
      --loc <location e.g CP|SZ|ME>
      --config <cfg_tester_type>
      --facilityfile <$DPSCRIPT/facilityMapping.ini>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [-V Display version ID]
=head1 DESCRIPTIONS

B<This script> will read SINF file and generate IFF file for dbascii

=head1 AUTHOR

B<jason.arp@pdf.com>

=head1 CHANGES

 2015/08/03 grace  : new
 2015/09/14 eric   : use product from mapping table if product eq N/A or blank
 13-Jul-2016 gilbert: logging pre-processing information  to refdb.pp_log table.
 2019/28/10 glory  : get the datetime from filename and use it as a startTime and dateTime if not available in the raw file. 
 2021/04/09 glory  : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
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
use PDF::Parser::SINF;
use PDF::Formatter;
use v5.10;
use PPLOG::PPLogger;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;
use Config::Tiny;

our $VERSION = "1.0";
our $TESTER  = "SINF";

my (%hOptions) = ();

my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "LOGFILE=s", "DEBUG", "SITE=s", "LOC=s", "FACILITYFILE=s", "CONFIG=s", "V",
        "TRACE", "PPLOG",)
    )
{
    dpExit( 1, "invalid options" );
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
        $pplogger->settobeLog(1);
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];
my $basefileName = basename($infile);
my @arr = split("-", $basefileName);
my $dateTime = pop (@arr);
my $startTime = "";

if ($dateTime=~ /\d{14}/) {
 my $year = substr ($dateTime,0,4);
 my $mon = substr ($dateTime,4,2);
 my $dd = substr ($dateTime,6,2);
 my $hour = substr ($dateTime,8,2);
 my $min = substr ($dateTime,10,2);
 my $sec = substr ($dateTime,12,2);

 $startTime = $year."/".$mon."/".$dd." ". $hour.":".$min.":".$sec;
}else{
	WARN("possibly invalid datetime extracted from filename=$dateTime");

}


# Set Raw File ==> infile
$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    pod2usage();
    dpExit( 1, "input file does not exist $infile" );
}

# check output dir
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        basename => ( basename $infile),
        ext      => 'iff',
        gzipIFF  => 'Y'
    }
);

INFO("infile  = $infile");
open( INFILE, $infile );

# Start input file reading
my $parser = PDF::Parser::SINF->new;

my %prod_ref = ();
my $model = $parser->readFile( $infile);
my $header = $model->header;

$model->wafers->[0]->START_TIME($startTime);
$model->wafers->[0]->END_TIME($startTime);

if($model->wafers->[0]->{START_TIME} eq "" || $model->wafers->[0]->{START_TIME} eq "N/A"){
	$model->wafers->[0]->START_TIME($startTime);

}
if($model->wafers->[0]->{END_TIME} eq "" || $model->wafers->[0]->{END_TIME} eq "N/A"){
	$model->wafers->[0]->END_TIME($startTime);


}



# load prod ref mapping table
&load_prod_ref() if $hOptions{LOC} ne "KYEC_TW";

$wr->noMeta(1) unless ( $header->populateMeta );

my $device = $header->PROGRAM;
my $product = "";
if ($header->PRODUCT eq 'N/A' || $header->PRODUCT eq '') {
	$product = $prod_ref{$device} if exists($prod_ref{$device});	
	$header->PRODUCT($product);
	INFO("Use product from product mapping table = $product");
}
$header->VERSION($VERSION);
$header->EQUIP6_ID($facility);
$header->CFG_TESTER_TYPE( $hOptions{CONFIG} );

# Passing Reference of Model
$pplogger->setModelHeader($model);

my $program = $header->PROGRAM;

my $wmap = $model->updateWMap;
$wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
unless ( $model->wmap->confirmed ) {
    $wr->noWMap(1);
}

#assign source lot as wafer name
my $wafer = $model->wafers;
if ($header->SOURCE_LOT ne ""){
        $wafer->[0]->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->[0]->number));
        $pplogger->setWaferFlag(1);
}

$model->updateProgram("MAP_PGM");

my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);
$formatter->dataItems([qw/x y soft_bin/]);
$formatter->printBinmap;

sub load_prod_ref
{
	my $ref_file = "/data/vgrd_tw_sort_wmap_sinf/TP/tsmc_fsc_prod_mapping.txt";
        open REF, $ref_file or die "can't open prd mapping file: $?\n";
        while( my $line=uc(<REF>))
        {
                next if $line=~/^\#/;

                $line           =~ s/\s+//g;
                my ($tsmc,$fsc) = split /\,/, $line;
                next if $tsmc eq "" || $fsc eq "";
                $prod_ref{$tsmc}=$fsc;
        }
        close(REF);
}
dpExit(0);

