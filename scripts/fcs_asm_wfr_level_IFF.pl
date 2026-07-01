#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_asm_IFF.pl <Input flie name>
	--out <output dir>
	--loc <location e.g CP, SZ, ME>
	[--finallot]
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> 

=head1 AUTHOR

B<sungsuk.moon@pdf.com>

=head1 CHANGES

 2015/08/12 grace   : new creation
 2015/10/13 eric    : add loc and trim ppid if > 35 chars 
 2015/11/03 gilbert : disabled get wmap config data, data comes from the fab.
 2016/02/02 eric    : modified to produce multiple iff per wafer# (printPar to printPar_v2)
 2016/02/26 wsanopao: logging pre-processing information  to refdb.pp_log table.
 2016/05/13 eric    : renamed readFile to read_wfr_level
 2017/05/12 eric    : set wafer flag for pplogging
 2020/09/01 karen   : added support to fork output (IFF)/files to designated location
 2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

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
use PDF::Parser::ASM;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao: 
use Config::Tiny;

our $VERSION = "1.0";
our $TESTER  = "ASM";
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    	pod2usage();
    	dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "FORK=s", "LOC=s", "FACILITYFILE=s", "FINALLOT", "LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG" )
    )
{
    	dpExit( 1, "invalid options" );
}
 
if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location     = $hOptions{LOC};
my $facility = "";

if($hOptions{FINALLOT}) {
	$facility = $config->{$location}->{finalTest};
} else {
	$facility = $config->{$location}->{probe};
}

INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];
INFO ("Infile = $infile");

# wsanopao: Set Raw File ==> infile 
$PPlogger->setRawFile($infile);

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


my $parser = PDF::Parser::ASM->new;
my $model = $parser->read_wfr_level($infile, isLogDebug);

&normalizeToBaseUnit($model);

my $header = $model->header;
$header->isFinalLot($hOptions{FINALLOT});
$wr->noMeta(1) unless ( $header->populateMeta );
$header->VERSION($VERSION);
$header->EQUIP6_ID($facility);
$header->PROGRAM_CLASS(3);

my $program = $header->PROGRAM;
if ( length($program) > 35 )
{
        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
        $wr->forSBox(1);
        $program = substr($program, 1, 35); # Leave enough room for session type
}

$header->PROGRAM($program);
$model->updateProgram;
$model->updateWMap;

# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);
$PPlogger->setWaferFlag(1);

#my $wmap = $model->updateWMap;

#$wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
#$wr->noWMap(1) unless ( $wmap->confirmed );

my $formatter = new_iff_formatter(
	{   model  => $model,
            writer => $wr
	}
);
		
$formatter->dataItems([qw//]);
$formatter->testItems([qw/number name units/]);
$formatter->printPar_v2;

dpExit(0);
