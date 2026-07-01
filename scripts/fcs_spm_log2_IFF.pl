#!/usr/bin/env perl_db

use strict;
use FindBin::libs;
use Getopt::Long qw/:config ignore_case auto_help/;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Parser::SPM_LOG2;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao: 
use Number::Range;
use Config::Tiny;
use v5.10;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;

=pod
=head1 SYNOPSIS

  fcs_spm_log2_IFF.pl <Input flie name>
      --finallot
      --out <output dir>
      --loc <location>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [-V Display version ID]

=head1 DESCRIPTIONS

B<This script> will read log2 file and generate IFF file for dbascii

=head1 AUTHOR

B<linjie.zhu@pdf.com>

=head1 CHANGES

 2015/06/25 Jacky : new creation
 2015/07/06 grace : disable normalizing the data and limits to base units by Rodney's request
		    Rodney said some of the data doesn't normalize correctly because the units are all uppercase, 
		    which causes normalization to mistaken 'milli-' for 'mega-'.  
 2015/07/27 grace : Changed dataSource SPM_LOG2 to SPM by Rodney's request
 2015/07/29 eric  : Corrected ppid naming rule
 2015/07/29 eric  : sandbox if ppid > 35
 2015/07/30 eric  : added location option
 2015/11/19 eric  : always generate but do not register limit if sandbox
 2016/02/16 wsanopao: logging pre-processing information  to refdb.pp_log table.
 2016/05/20 eric  : added options for reliability data loading
 2016/07/07 eric  : corrected bug when checking if atetemp & strdur in range
 2016/07/07 eric  : corrected how rel lot were parsed
 2016/11/21 eric  : remove rej | retest from lotid
 2017/04/11 jgarcia: checked $model->misc for error message and do the logging before calling dpExit.
 2017/05/30 gilbert : generate limits always and dont register in refdb.pp_limits
 2018/01/11 eric  : parse ONRMS datalog
 2018/01/16 eric  : exit if invalid soft bin number found.
 2018/10/31 eric  : modified to check 2D scan info
 2020/09/01 karen       : added support to fork and qde output (IFF)/files to designated location
 2021-Apr-12 Karen      : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
 2025-04-23 Eric	: specify dataItems to output iff

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.


=cut

 
our $VERSION = "1.0";
our $TESTER  = "SPM_LOG2";

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
}
unless (
    GetOptions(
        \%hOptions,  "OUT=s", "FORK=s", "FACILITYFILE=s", "FINALLOT", "V", "LOC=s", "RELLOT",
        "LOGFILE=s", "DEBUG", "TRACE", "PPLOG", "QDE"
    )
    )
{
    dpExit( 1, "invalid options" );
    pod2usage(3);
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $facility = $config->{$location}->{finalTest};
INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    	dpExit( 1, "input file does not exist $infile" );
}

# check output dir
my $fn = basename($infile);
$fn =~ /^(.*)\.(\S+)$/;
$fn = $1;
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},
	qde => $hOptions{QDE},
        basename => $fn,
        ext      => 'iff',
        gzipIFF  => 'Y',
	pplogger => $pplogger
    }
);

INFO("infile  = $fn");

my $parser = PDF::Parser::SPM_LOG2->new;
my $reglim_flg = "Y";
my $model;

my $scan_flg = $parser->check2Dscan($infile);

if ($scan_flg eq "Y") {
	INFO ("2D Scan File Detected!");
	$model = $parser->read2DFile($infile);
}
else {
	$model = $parser->readFile($infile);
}
# disabled by Rodney's request 
#&normalizeToBaseUnit($model);   
my $header = $model->header;
   $header->VERSION($VERSION);
   $header->isFinalLot( $hOptions{FINALLOT} );
   $header->isRelLot( $hOptions{RELLOT} );
   $header->EQUIP6_ID( $facility );
my $lot = $header->LOT;
$lot =~ s/^AO/A0/;
if ($lot =~ /REJ|RETEST/i) {
	$header->INDEX2("O");
	$reglim_flg = "N";
	$lot = substr($lot, 0, 10);
}
$header->LOT( trim($lot) );

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);
if ($model->{misc} =~ /NO.+/ || $model->{misc} =~ /INVALID/) {
	dpExit(1, "$model->{misc}");
}

my $program = $header->PROGRAM;
if (length($program) > 35) {
        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters. Sending to sandbox.");
        $wr->forSBox(1);
	$reglim_flg = "N";
        $program = substr($program, 1, 35); #leave room for session type
}

$header->PROGRAM($program);
$header->PROGRAM_CLASS(2);

# Capture Rel Attributes
if ($hOptions{RELLOT}){
        my $base_fn = basename($infile);
           $base_fn =~ s/\.LOG2.*+//ig;
        my @item = split /\_/, $base_fn;
	my $qpnum;
	my $devchar;
	my $lotchar;
        my $strname = $item[2];
        my $strdur = $item[3];
        my $temp = $item[4];
        my $dtype = $item[5];
	   $dtype = "" if $dtype =~ /[0-9]/;

	if ($item[1] =~ /^20/) {
		$qpnum = substr $item[1], 0, 8;
		$devchar = substr $item[1], 8, 1;
		$lotchar = substr $item[1], 9, 1;
		$header->LOT($qpnum.$devchar.$lotchar);
	}
	elsif ( $item[1] =~ /^U/i) {
		$qpnum = substr $item[1], 0, 6;
		$lotchar = substr $item[1], 6, 1;
		$header->LOT($qpnum.$lotchar);	
	}

        my $range = Number::Range->new("0..1000000");
        if ( $range->inrange($strdur) && $strdur !~ /\D/) {
                #do nothing
        }
        else {
                WARN ("Stress Duration not in range =  $strdur");
		$strdur = "" if $strdur =~ /[a-z]/i;
                $wr->forSBox(1);
        }
        my $range = Number::Range->new("-1000000..1000000");
        if ( $range->inrange($temp) && $temp !~ /\D/) {
                #do nothing
        }
        else {
                WARN ("ATETemp not in range = $temp");
		$temp = "" if $temp =~ /[a-z]/i;
                $wr->forSBox(1);
        }

	$header->INDEX1($strname."_".$strdur."_".$temp."_".$dtype);

        my $rel = new_rel;
        $rel->qpnumber($qpnum);
        $rel->devchar($devchar);
        $rel->lotchar($lotchar);
        $rel->strname($strname);
        $rel->strduration($strdur);
        $rel->atetemp($temp);
        $rel->datalogtype($dtype);
        $model->add('rels', $rel);
}

unless ( $header->populateMeta ){
	$wr->noMeta(1);
	$reglim_flg = "N";
}
$model->updateProgram;
## Check for WMAP Data only if it is not FINALLOT ##
if (!($hOptions{FINALLOT}) && !($hOptions{RELLOT})) {
	my $wmap = $model->updateWMap;
	unless ( $wmap->confirmed ){
		$wr->noWMap(1);
		$reglim_flg = "N";
	}
}

my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);

$formatter->testItems([qw/ number name units group/]);
$formatter->dataItems([qw/site partid soft_bin hard_bin/]);
$formatter->printPar;
$model->buildLimit;
$formatter->printLimit;
$model->limit->input_file(basename $infile);
dpExit(0);

