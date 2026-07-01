#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_itec_sum_IFF.pl <Input flie name>
	--out <output dir>
	--loc <location e.g CP, SZ, ME>
        --facilityfile <$DPSCRIPT/facilityMapping.ini>
	[--finallot]
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> 

=head1 AUTHOR

B<sungsuk.moon@pdf.com>

=head1 CHANGES

 2015/08/13 grace 	: new creation
 2015/10/13 eric  	: use ppid naming rule, disable updateWmap since this FT data
 2015/10/20 eric  	: parse location
 2016/03/02 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2019/08/13 eric	: added nosandbox option. its purpose was not to move the file to sandbox when envoked
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021/04/15 glory        : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after. 

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
use PDF::Parser::ItecSum;
use PDF::Formatter;
use Time::Local;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;


our $VERSION = "

1.0
";
our $TESTER  = "ITEC";

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "FORK=s", "LOC=s", "FACILITYFILE=s", "FINALLOT", "LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG", "NOSANDBOX" )
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

my $parser = PDF::Parser::ItecSum->new;

my $model = $parser->readFile($infile, isLogDebug);

&normalizeToBaseUnit($model);

my $header = $model->header;
$header->isFinalLot($hOptions{FINALLOT});
#$wr->noMeta(1) unless ( $header->populateMeta );

unless ( $header->populateMeta ) {
	if (!($hOptions{NOSANDBOX})) {
		$wr->noMeta(1)
	}
	else {
		WARN("File was not sandboxed. Argument was enabled.");
	}
}

$header->VERSION($VERSION);
$header->EQUIP6_ID($facility);
$header->PROGRAM_CLASS(12);
$header->START_TIME(timegm(localtime()));
$header->END_TIME(timegm(localtime()));

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

my $program = $header->PROGRAM;
if ( length($program) > 35 )
{
        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
        $wr->forSBox(1);
        $program = substr($program, 1, 35); # Leave enough room for session type
}

$header->PROGRAM($program);
$model->updateProgram;
#$model->updateWMap;

#my $wmap = $model->updateWMap;

#$wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
#$wr->noWMap(1) unless ( $wmap->confirmed );

my $formatter = new_iff_formatter(
	{   model  => $model,
            writer => $wr
	}
);
		
$formatter->dataItems([qw/site x y soft_bin/]);
$formatter->testItems([qw/number name units/]);
$formatter->printPar;

dpExit(0);
