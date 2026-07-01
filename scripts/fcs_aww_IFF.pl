#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_aww_IFF.pl <Input flie name>
      --out <output dir>
      --loc <location e.g CP|SZ|ME>
      --site [szft|mtsort|pmsort|pmft|isti_tw_csp]
      --config <cfg_tester_type>
      --facilityfile <$DPSCRIPT/facilityMapping.ini>
      [--nolookup]
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [-V Display version ID]
=head1 DESCRIPTIONS

B<This script> will read AWW file and generate IFF file for dbascii

=head1 AUTHOR

B<jason.arp@pdf.com>

=head1 CHANGES

 2015/05/12 jason  : output IFF format
 2015/05/20 gilbert: added option site and apply test code specific to amkor
 2015/05/23 gilbert: removed NA as default test code for gtk_tw_sort
 2015/05/29 grace  : Added support for -v option.
 2015/06/30 gilbert: Set EQUIP6_ID value to site e.g CP, SZ, etc
 2015/07/02 gilbert: Added --config <cfg_tester_type> and update progra naming
 2015/07/03 jgarcia: adopt new program naming [calling updateProgram subroutine in mode with args 'MAP_PGM'].
 2015/07/08 gilbert: Added $wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
 2015/07/15 eric   : sandbox if ppid > 35
 2015/08/18 jgarica: modified to support passing site as an argument when calling PDF::Parser::AWW->readFile method/subroutine.
 2015/10/08 jgarcia: assign mod date to start time and endtime if no value.
 2015/10/15 eric   : added arg option to bypass lot lookup
 2016/03/02 wsanopao: logging pre-processing information  to refdb.pp_log table.
 2016-Mar-09 gilbert: removed "." in the lot id for amkor site only and moved the pp_lot lookup after some conditions.
 2016-Apr-05 eric: added stsort site
 2016-Apr-05 gilbert: get date and time from the filename if present as start time. 
                      YYYYMMDDHHMMSS format which Amkor implemented.
 2016-Apr-20 gilbert: get the start time from the filename with additional validation.
 2016-Jul-27 gilbert: Added amkor_kr_csp
 2016-Sep-01 rodney : Added CP2, CP2-CD test codes for amkor_tw_ft site.
 2017-May-09 eric   : assign source lot as wafer id
 2020/09/01 karen   : added support to fork output (IFF)/files to designated location
 2021/04/06  glory  : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
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
use PDF::Parser::AWW;
use PDF::Formatter;
use v5.10;
use DateTime;
use Time::Local;
#use File::stat;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;


our $VERSION     = "1.0";
our $TESTER      = "AWW";
my $fileModTime  = "";
my $new_end_time = "";
my (%hOptions)   = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
#$fileModTime = ctime(stat($ARGV[0])->mtime);
#INFO("TIME :".$fileModTime);
unless (
    GetOptions( \%hOptions, "OUT=s", "FORK=s", "LOGFILE=s", "DEBUG", "SITE=s", "LOC=s", "FACILITYFILE=s", "CONFIG=s", "V",
        "NOLOOKUP", "TRACE", "PPLOG", )
    )
{
    dpExit( 1, "invalid options" );
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT SITE LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);

my $config = Config::Tiny->read($hOptions{FACILITYFILE});


if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

unless ( $hOptions{SITE} ) {
    dpExit ( 1, "--site must be specified" );
    pod2usage(3);
}

unless ( $hOptions{LOC} ) {
    dpExit ( 1, "--loc must be specified" );
    pod2usage(3);
}

my $site =$hOptions{SITE};
unless ( grep { $_ eq $site} qw/ amkor_tw_ft gtk_tw_sort stsort amkor_kr_csp/ ) {
    dpExit (1, "wrong site code: $site");
}

my $location = $hOptions{LOC};
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");

INFO("Site code = $site");

# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);

$fileModTime = (stat $infile)[9];
#print"test-------:$fileModTime\n";
if ( !-f $infile ) {
    pod2usage();
    dpExit( 1, "input file does not exist $infile" );
}

    my ($tmp_time, $dump)  = split(/\.aww/i, $infile); 
        chomp($tmp_time);
    my  @tmp_end_time      = split(/\_|\./, $tmp_time);
        $tmp_end_time[$#tmp_end_time] =~ /^(\d{14})$/; 
    my  $end_time          = $1; 
if ($end_time ne "")
{
       $end_time       =~/(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/;
    my $year           = $1;
    my $mon            = $2;
    my $day            = $3;
    my $hour	       = $4;
    my $min            = $5;
    my $sec            = $6;
       if ( eval {DateTime->new(year=> $year ,month=> $mon,  day=> $day)} ) {
            $new_end_time   = "${year}-${mon}-${day}-${hour}-${min}-${sec}";
       } 
       else {
            $new_end_time   = "";
       }
}
if ($new_end_time eq "")
{
    my ($tmp_time1, $dump1)  = split(/\.aww/i, $infile);
        chomp($tmp_time1);
    my  @tmp_end_time1       = split(/\_|\./, $tmp_time1);
        $tmp_end_time1[$#tmp_end_time1 - 1] =~ /^(\d{14})$/;
    my  $end_time1           = $1;
    if ($end_time1 ne "")
    {
          $end_time1      =~/(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/;
       my $year           = $1;
       my $mon            = $2;
       my $day            = $3;
       my $hour           = $4;
       my $min            = $5;
       my $sec            = $6;
          if ( eval {DateTime->new(year=> $year ,month=> $mon,  day=> $day)}) {
               $new_end_time   = "${year}-${mon}-${day}-${hour}-${min}-${sec}";
          }
         else {
              $new_end_time = "";
         }
    }
}
# check output dir
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},
        basename => ( basename $infile),
        ext      => 'iff',
        gzipIFF  => 'Y'
        
    }
);

INFO("infile  = $infile");
open( INFILE, $infile );

# Start input file reading
my $parser = PDF::Parser::AWW->new;

my $model = $parser->readFile( $infile, $site);
my $header = $model->header;


$header->VERSION($VERSION);
$header->EQUIP6_ID($facility);
$header->CFG_TESTER_TYPE( $hOptions{CONFIG} );
if($header->START_TIME eq "" && $new_end_time ne "") {
	$header->START_TIME($new_end_time);
}
else {
	$header->START_TIME($fileModTime);
}
if($header->END_TIME eq "" && $new_end_time ne "") {
	$header->END_TIME($new_end_time);
}
else {
	$header->END_TIME($fileModTime);
}
my $program = $header->PROGRAM;
my $test_flow = "";

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

given ($site) {
    when ('amkor_tw_ft') {
        my $lot = $header->LOT;
	   $lot =~ s/\.//g;
        $header->LOT($lot);

	my $fn = basename($infile);
	my @tmp_fn = split ( /\_|\./, $fn );
	my $found = 0;
	foreach my $code (@tmp_fn) {
		if ( grep { $_ eq $code } (qw/CP1-CD CP2 CP2-CD DAOI/)) {
			$test_flow = "_".$code;
			$found = 1;
		}
		last if $found == 1;
	}
	$test_flow = "_CP1" if $found == 0;
    }
    when ('amkor_kr_csp') {
	my $fn = basename($infile);
	my @tmp_fn = split ( /\_|\./, $fn );
	my $found = 0;
	foreach my $code (@tmp_fn) {
		if ( grep { $_ eq $code } (qw/BAOI/)) {
			$test_flow = "_".$code;
			$found = 1;
		}
		last if $found == 1;
	}
	$test_flow = "" if $found == 0;
    }
    when ('gtk_tw_sort') {
    }
    when ('stsort') {
    }
}
if (length($program) + length($test_flow) > 35 ){
        INFO("PROGRAM NAME \"".$program.$test_flow."\" will be truncated to 35 characters. Sending to sandbox.");
        $wr->forSBox(1);
        $program = substr($program, 1, 35-length($test_flow)); #leave room for session type
}
$header->PROGRAM($program.$test_flow);

# Lot lookup
if (!($hOptions{NOLOOKUP})){
	$wr->noMeta(1) unless ( $header->populateMeta );
}

my $wmap = $model->updateWMap;
$wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
unless ( $model->wmap->confirmed ) {
    	$wr->noWMap(1);
}

#assign source lot as wafer name
my $wafer = $model->wafers;

#2022-Jul-01 : jgarcia : always format the SourceLot to not have NA or N/A or blank values regardless if Production or Sandbox.
$header->SOURCE_LOT(formatSourceLot($header->{SOURCE_LOT}, $header->{LOT}));

if ($header->SOURCE_LOT ne "" && !($hOptions{FINALLOT})) {
    my $sourceLot = $header->{SOURCE_LOT};
	$sourceLot =~ s/\.S$//;   
    $wafer->[0]->name($sourceLot."_".sprintf("%02d",$wafer->[0]->number));
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

dpExit(0);
