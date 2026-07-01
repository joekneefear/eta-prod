#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_sz_csp_IFF.pl <Input flie name>
      --out <output dir>
	  --cfgtestertype
      [--logfile <logfilepath>]
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read ASC binmap file and generate IFF file for dbascii

=head1 AUTHOR

B<sungsuk.moon@pdf.com>

=head1 CHANGES

 2015/04/24 grace	: new creation
 2015/05/13 grace	: send iff to sandbox if no data in db
 2015/05/29 grace  	: Added support for -v option.
 2015/07/08 eric	: use new program naming rule.
 2015/07/22 eric	: reverted to r696 to fix cfg_id not showing in ppid. move updatProgram
 			  after updateWMAP and sandbox if ppid >35
 2016/02/26 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2017/05/03 eric	: assign source lot as wafer name
 2021/04/07 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
 2022-Sep-26 : jgarcia : always format the SourceLot to not have NA or N/A or blank values regardless if Production or Sandbox.

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
use PDF::Parser::Sz;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;

our $VERSION = "1.0";
our $TESTER  = "SZ";
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    	pod2usage();
    	dpExit( 1, "No input file specified" );
}
unless (
    	GetOptions( \%hOptions, "OUT=s", "FACILITYFILE=s", "LOGFILE=s", "DEBUG", "V", "CONFIG=s", "LOC=s",
        	"TRACE","PPLOG" )
    	)
{
    	dpExit( 1, "invalid options" );
}

if($hOptions{V})
{
	print("$VERSION\n");
	dpExit(0);
};

my @required_options = qw/OUT CONFIG LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);

if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $location = $hOptions{LOC};
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$PPlogger->setRawFile($infile);

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

my $parser = PDF::Parser::Sz->new;

if($infile =~ /gz$/)
{
	my $command = "gunzip $infile";
	my $ret = system($command);
}
else{

	my $model = $parser->readFile($infile, $hOptions{CONFIG});

	&normalizeToBaseUnit($model);
	my $header = $model->header;
	$header->VERSION($VERSION);
	$header->CFG_TESTER_TYPE( $hOptions{CONFIG} );
	$header->EQUIP6_ID( $facility );
	$header->PROGRAM_CLASS(4);

	$wr->noMeta(1) unless ($header->populateMeta);

	my $program = $header->PROGRAM;

	# wsanopao: Passing Reference of Model
	$PPlogger->setModelHeader($model);

	if (length($program) > 35) {
		INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters. Sending to sandbox.");
		$wr->forSBox(1);
		$program = substr($program, 1, 35);
	}
	$header->PROGRAM($program);

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

	#assign source lot as wafer name
	my $wafer = $model->wafers;

	#2022-Jul-01 : jgarcia : always format the SourceLot to not have NA or N/A or blank values regardless if Production or Sandbox.
	$header->SOURCE_LOT(formatSourceLot($header->{SOURCE_LOT}, $header->{LOT}));

	if ($header->SOURCE_LOT ne "" && !($hOptions{FINALLOT})) {
    my $sourceLot = $header->{SOURCE_LOT};
    $sourceLot =~ s/\.S$//;
	  $wafer->[0]->name($sourceLot."_".sprintf("%02d",$wafer->[0]->number));
		$PPlogger->setWaferFlag(1);
	}

	$model->updateProgram("MAP_PGM");

	my $formatter = new_iff_formatter({
	  	model=>$model,
	  	writer=>$wr
	});

	$formatter->dataItems([qw/x y soft_bin/]);
	$formatter->printBinmap;
}
dpExit(0);
