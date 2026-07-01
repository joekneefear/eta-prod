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

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

2016-Jan-25 Eric	: new
2017-May-12 Eric	: set wafer flag for pplogging
2017-Aug-10 Eric	: assign source lot as wafer name.
2020-Oct-08 Karen	: added support to fork output (IFF)/files to designated location
2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

=head1 LICENSE

(C) Fairchild Semiconductor Inc. 2015 All rights reserved.

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
 
if($hOptions{V}) {
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

PDF::Log->init( \%hOptions );

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
        gzipIFF => 'Y'
    }
);

my $parser = PDF::Parser::ASM->new;
my $model = $parser->read_lot_level($infile, isLogDebug);

#&normalizeToBaseUnit($model);

my $header = $model->header;
$header->isFinalLot($hOptions{FINALLOT});
$wr->noMeta(1) unless ( $header->populateMeta );
$header->VERSION($VERSION);
$header->EQUIP6_ID($hOptions{LOC});
$header->PROGRAM_CLASS(3);

my $program = $header->PROGRAM;
if ( length($program) > 35 )
{
        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
        $wr->forSBox(1);
        $program = substr($program, 1, 35); # Leave enough room for session type
}

#assign source lot as wafer name
if ($header->SOURCE_LOT ne "") {
	$model->wafers->[0]->name($header->SOURCE_LOT."_".sprintf("%02d",$model->wafers->[0]->number));
	$PPlogger->setWaferFlag(1);
}

$header->PROGRAM($program);
$model->updateProgram;
$model->updateWMap;

# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);
$PPlogger->setWaferFlag(1);

my $formatter = new_iff_formatter(
	{   model  => $model,
            writer => $wr
	}
);
		
$formatter->dataItems([qw//]);
$formatter->testItems([qw/number name units/]);
$formatter->printPar;

dpExit(0);
