#!/usr/bin/env perl_db
# SVN $Id: fcs_juno_xls_sum_IFF.pl 
=pod

=head1 SYNOPSIS

      fcs_juno_csv_sum_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
      --loc <location>
      --facilityfile <$DPSCRIPT/facilityMapping.ini>
      [-config <config_tester_type>]
      [--logfile <logfilepath>]
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read XLS file and output IFF file

=head1 AUTHOR

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

2015-Nov-16 Eric	: new
2016/03/02 wsanopaoi	: logging pre-processing information  to refdb.pp_log table.
2016-Oct-26 Eric	: reiterate items in filename to locate correct lotid.
2019-Aug-13 Eric	: added nosandbox option. its purpose was not to move the file to sandbox when envoked.
2020/09/01 karen        : added support to fork output (IFF)/files to designated location
2021/04/14 glory        : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

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
use PDF::Parser::Juno_Sum_csv;
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
use Config::Tiny;

our $VERSION = "

1.0
";
our $TESTER  = "DTS-2000";

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
        \%hOptions,  "OUT=s", "FORK=s", "FINALLOT",
        "LOGFILE=s", "DEBUG", "TRACE", "V", "TYPE=s", "LOC=s", "FACILITYFILE=s", "SITE=s",  "CONFIG=s", "PPLOG", "NOSANDBOX"
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
my @required_options = qw/OUT LOC SITE FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location     = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
my $site = $hOptions{SITE};
my $facility = $config->{$location}->{finalTest};
INFO("FACILITY|EQUIP6_ID=$facility");


# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);
$pplogger->setEnv($site);

if ( !-f $infile ) {
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

my $parser = PDF::Parser::Juno_Sum_csv->new;
my $model = $parser->readFile($infile,isLogDebug);
my $fn = basename $infile;
my @fnItem = split /\_|\-/, $fn;

my $header = $model->header;
   $header->isFinalLot($hOptions{FINALLOT});
   $header->VERSION($VERSION);
   $header->PROGRAM_CLASS(12);
   $header->EQUIP6_ID($facility);

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
my $ret = $header->populateMeta;
if ($ret == 0) {
        INFO ("Searching lotid using items in filename...");
        my $origLot = $header->LOT;
        foreach my $itm (@fnItem) {
                $header->LOT($itm);
                $ret = $header->populateMeta;
                last if ($ret == 1);
        }
        if ($ret == 0){
                $header->LOT($origLot);
                #$wr->noMeta(1);
		if (!($hOptions{NOSANDBOX})) {
			$wr->noMeta(1);
		}
		else {
			WARN("File was not sandboxed. Argument was enabled.");
		}
        }
}

$model->updateProgram;	

my $formatter = new_iff_formatter(
	{   model  => $model,
            writer => $wr
        }
);

$formatter->dataItems([qw/partid site hard_bin soft_bin/]);
$formatter->testItems([qw/number name units /]);
$formatter->binItems ([qw/number name PF count/]);
$formatter->printPar;

dpExit(0);
