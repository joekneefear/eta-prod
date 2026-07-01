#!/usr/bin/env perl_db
# SVN $Id: fcs_accueol_IFF.pl 2627 2020-10-09 01:15:51Z dpower $

=pod

=head1 SYNOPSIS

  fcs_accueol_IFF.pl <Input flie name>
      --out <output dir>
      --limitDir <limit file look up direcotry>
      --loc <location e.g CP, SZ, ME>
      [--finallot]
      [--type <Process|Product>]
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [-V Display version ID]

=head1 DESCRIPTIONS

B<This script> will read Accueol Etest file and generate IFF file for dbascii

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/04/15 kazukik	: new creation
 2015/05/29 grace  	: Added support for -v option.
 2015/06/21 grace  	: set value for input_file of PP_LIMITS
 2015/07/01 eric   	: added LOC argument and pass it as EQUIP6_ID
 2015/07/22 rodney 	: set program class in header (model expects it)
 2015/08/02 rodney 	: Pass the limits file to the parser to acquire test names.
 2015/08/05 rodney 	: Always generate and load a limit file (tests may be turned on and off across data files). 
 2015/11/23 jgarcia	: Added TYPE param to indicate if Process or Product info to be added in Program.
 2016/02/26 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2017/12/27 eric	: get error codes from misc for trapping
 			: set wafer flag for pplog
 2020/09/01 karen	: added support to fork and qde output (IFF)/files to designated location			
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
use PDF::Parser::Accueol;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao: 
use Config::Tiny;
use PDF::WS;

our $VERSION = "

1.0
";
our $TESTER  = "ACCUEOL";

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "FACILITYFILE=s", "FORK=s", "LIMITDIR=s", "LOC=s", "SITE=s", "FINALLOT", "TYPE=s", "LOGFILE=s", "DEBUG","V",
        "TRACE", "PPLOG", "QDE" )
    )
{
    dpExit( 1, "invalid options" );
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT LIMITDIR LOC TYPE SITE FACILITYFILE/;
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
my $ertUrl = "";
if($hOptions{FINALLOT}) {
	$facility = $config->{$location}->{finalTest};
        $ertUrl = $config->{$location}->{onLotProd};
        INFO("ERT URL=$ertUrl");
} else {
	$facility = $config->{$location}->{probe};
        $ertUrl = $config->{$location}->{onLotProd};
        INFO("ERT URL=$ertUrl");
}

INFO("FACILITY|EQUIP6_ID=$facility");
# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile 
$PPlogger->setRawFile($infile);
$PPlogger->setEnv($site);

if ( !-f $infile ) {
    	ERROR("input file does not exist $infile");
    	pod2usage();
}

# check output dir
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
{   	outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},
	qde => $hOptions{QDE},
    	basename => ( basename $infile),
    	ext      => 'iff',
    	gzipIFF  => 'Y'
}
);

# check limit lookup dir
my $limitdir = $hOptions{LIMITDIR};
if ( ! -d $limitdir ) {
    	ERROR("limit lookup dir does not exist $limitdir");
    	pod2usage();
}

INFO("infile  = $infile");

my $parser = PDF::Parser::Accueol->new;
my $limit_file = "";
my $model = $parser->readFile($infile, $limitdir, \$limit_file);
my $misc = $model->misc;

# normalize units
&normalizeToBaseUnit($model);

my $header = $model->header;
$header->isFinalLot($hOptions{FINALLOT});
$header->VERSION($VERSION);
$header->EQUIP6_ID($facility);
$header->PROGRAM_CLASS(5);
my $lot = $header->{LOT};
INFO($header->{LOT}."|".$lot);
#$wr->noMeta(1) unless ($header->populateMeta);
unless ( $header->populateMeta ){
        my $url = "${ertUrl}${lot}";
        INFO("FINAL URL=$url");
        my $decodedJSON = getFromERTWS($url);
        $header->SOURCE_LOT(formatSourceLot($decodedJSON->{onLot}->{sourceLot}, $header->{LOT}));
        $header->PRODUCT($decodedJSON->{onLot}->{product});
        #$header->REVISION($decodedJSON->{onLot}->{revision});
        #$header->TEST_PROGRAM($decodedJSON->{onLot}->{testProgram});
        $header->LOT_CLASS($decodedJSON->{onLot}->{lotClass});
        if ($decodedJSON->{onLot}->{sourceLot} = ""){
                $wr->noMeta(1);
        }
}                                                       
$model->updateProgram($hOptions{TYPE});

# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);
if ($header->SOURCE_LOT ne "") {
	$PPlogger->setWaferFlag(1);
}

if ($misc->{err_code} == 4) {
       dpExit (4, "Test program not found = $model->{programOrg}");
}
elsif ($misc->{err_code} == 1) {
       dpExit (1, "Test name should not be blank.");
}

my $fmt = new_iff_formatter({
  	model=>$model,
  	writer=>$wr
});
$fmt->dataItems([qw/x y site soft_bin/]);
$fmt->testItems([qw/number name units/]);
$fmt->printPar();

if($limit_file eq "not")
{
	dpExit(4,"Limit file not found ");
}

### Always generate and load a limit file; otherwise, tests not in initial data file will not have limits loaded.
#if ($model->isLimitNew){  
my $searchPath = "$limitdir/".$model->programOrg."_REV_".$header->REVISION."*";
my ($limitfile) = glob($searchPath);

unless (defined $limitfile) {
	dpExit(4,"Limit file not found : $searchPath");
}

my $limit = $parser->readLimitFile($limitfile);
$limit->copyHeader($header);
$model->limit($limit);
$fmt->printLimit;
$model->limit->input_file(basename $infile); 
#$limit->registerRefdb;
#}

dpExit(0);

