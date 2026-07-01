#!/usr/bin/env perl_db
# SVN $Id: fcs_asc_csp_IFF.pl 2613 2020-10-08 02:13:16Z dpower $

=pod

=head1 SYNOPSIS

  fcs_asc_csp_IFF.pl <Input flie name>
      --out <output dir>
      --loc <location e.g. ISTI_TW, CP, ME>
      --config <config_tester_type>
      --facilityfile <$DPSCRIPT/facilityMapping.ini>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [-V Display version ID]
=head1 DESCRIPTIONS

B<This script> will read ASC binmap file and generate IFF file for dbascii

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/04/07 kazukik	: new creation
 2015/04/21 jason  	: changed program definition to include test session name between program and product.
 2015/07/01 eric   	: Added LOC arg & pass it as EQUIP6_ID.
 2015/07/03 eric   	: applied new program naming rule.
 2015/07/09 gilbert	: add $wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
 2015/07/14 eric   	: fix duplicate "BIN" in PPid & sandbox if > 35 chars.
 2015/07/15 eric   	: added test flow code to PPID.
 2015/07/15 eric   	: leave enough room for session type in ppid.
 2015/09/01 gilbert	: removed anything after . at the lot id and added to fail if no lot id
 2016/03/02 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2016/08/05 eric   	: perform second lot lookup by stripping last char.
 2017/05/03 eric	: assign source lot as wafer name
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021/04/06 glory       : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Getopt::Long;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Parser::Asc;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;


our $VERSION = "1.0";
our $TESTER  = "ASC";
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    	pod2usage();
    	dpExit( 1, "No input file specified" );
}
unless (
    	GetOptions( \%hOptions, "OUT=s", "FORK=s", "LOC=s", "FACILITYFILE=s", "CONFIG=s", "LOGFILE=s", "DEBUG",
        	"METASTRIP", "TRACE", "PPLOG",)
    	)
{
    	dpExit( 1, "invalid options" );
}

my @required_options = qw/OUT LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
my $config = Config::Tiny->read($hOptions{FACILITYFILE});

if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $location = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    	pod2usage();
    	dpExit( 1, "input file does not exist $infile" );
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

my $parser = PDF::Parser::Asc->new;
my $model = $parser->readFile($infile);
&normalizeToBaseUnit($model);
my $header = $model->header;
$header->VERSION($VERSION);
$header->EQUIP6_ID($facility);
$header->CFG_TESTER_TYPE($cfg_tstr_typ);

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

my $lot = $header->LOT;
   dpExit( 1, "NO Lot ID" ) if $lot eq "";
   $lot =~/\.(.*?)$/;
   $lot =~s/\.$1//g;
   $header->LOT($lot);

#$wr->noMeta(1) unless ($header->populateMeta);
if ($hOptions{LOC} eq 'ISTI_TW' && $hOptions{METASTRIP}) {
	unless ( $header->populateMeta ){
        	INFO("Performing second lot lookup by stripping last character..");
                my $origLot = $header->LOT;
                my $tempLot = $origLot;
                $tempLot = substr($tempLot, 0, -1);
                $header->LOT($tempLot);
                unless ($header->populateMeta) {
        	        $wr->noMeta(1);
                }
                        $header->LOT($origLot);
        }
} 
else {
	unless ( $header->populateMeta ) {
        	$wr->noMeta(1);
        }
}

my $program = $header->PROGRAM;
my $test_flow = "_".$model->misc;
if (length($program) + length($test_flow) > 35 ){
	INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters. Sending to sandbox.");
	$wr->forSBox(1);
	$program = substr($program, 1, 35-length($test_flow)); #leave enough room for ppid
}
$header->PROGRAM($program.$test_flow);
$header->PROGRAM_CLASS(4);

my $wmap = $model->updateWMap;
$wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
$wr->noWMap(1) unless ($wmap->confirmed);

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

my $formatter = new_iff_formatter({
  model=>$model,
  writer=>$wr
  });
$formatter->dataItems([qw/x y soft_bin/]);
$formatter->printBinmap;

dpExit(0);

