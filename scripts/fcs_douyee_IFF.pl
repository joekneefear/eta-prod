#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_douyee_IFF.pl <Input flie name>
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

 2015/08/12 grace : new creation
 2015/08/27 grace : disabled base unit normalization by Rodney's request
 2015/09/08 eric  : disabled updateWMap because it is Final Test, truncate ppid to 35, parsed location
                    create limit file.
 2015/09/10 eric  : disable lotid lookup because lotid naming is customize and cannot be found in refdb. 		    
 2015/11/19 eric  : always generate but do not register limit if sandbox
 2016/02/01 wsanopao: logging pre-processing information  to refdb.pp_log table.
 2016/03/31 eric  : changed prog class from 2 to 23
 2017-May-23 gilbert : generate limits always and dont register in refdb.pp_limits
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021-Apr-14 Karen	: get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
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
use PDF::Parser::Douyee;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;

our $VERSION = "

1.0
";
our $TESTER  = "DOUYEE";

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "FORK=s", "FACILITYFILE=s", "LOC=s", "FINALLOT", "LOGFILE=s", "DEBUG", "TRACE", "V","PPLOG" )
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

my $location = $hOptions{LOC};
my $site = $hOptions{SITE};

my $facility = "";
if($hOptions{FINALLOT}) {
        $facility = $config->{$location}->{finalTest};
}else {
        $facility = $config->{$location}->{probe};
}
INFO("FACILITY|EQUIP6_ID=$facility");


# Read input file
my $infile = $ARGV[0];
if ( !-f $infile ) {
    pod2usage();
    dpExit( 1, "input file does not exist $infile" );
}

# wsanopao: Set Raw File ==> infile
$PPlogger->setRawFile($infile);


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


my $parser = PDF::Parser::Douyee->new;

my $model = $parser->readFile($infile, isLogDebug);


# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);

#20150827 by Rodney's request
#&normalizeToBaseUnit($model);

my $reglim_flg = "Y";
my $header = $model->header;
$header->isFinalLot($hOptions{FINALLOT});
# $wr->noMeta(1) unless ( $header->populateMeta );   
$header->VERSION($VERSION);
$header->PROGRAM_CLASS(23);
$header->EQUIP6_ID( "$facility");

my $program = $header->{PROGRAM};
if (length($program) > 35) {
	INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
	$wr->forSBox(1);
	$reglim_flg = "N";
	$program = substr($program, 1, 35);
}
$header->PROGRAM($program);

$model->updateProgram;

my $formatter = new_iff_formatter(
	{   model  => $model,
            writer => $wr
	}
);
		
$formatter->dataItems([qw/site x y partid soft_bin/]);
$formatter->testItems([qw/number name units/]);
$formatter->printPar;

# create limit
#if ($reglim_flg eq "Y") { 
#	if ($model->isLimitNew){
#     		$model->buildLimit;
#     		$formatter->printLimit;
#     		$model->limit->input_file(basename $infile);
#     		$model->limit->registerRefdb;	
# 	}
#}
#else {   # always generate but do not register limit
	$model->buildLimit;
	$formatter->printLimit;
	$model->limit->input_file(basename $infile);
#}

dpExit(0);
