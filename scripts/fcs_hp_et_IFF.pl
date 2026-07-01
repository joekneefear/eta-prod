#!/usr/bin/env perl_db
# SVN $Id: fcs_hp_et_IFF.pl 2595 2020-10-07 01:29:44Z dpower $

=pod

=head1 SYNOPSIS

  fcs_hp_et_IFF.pl <Input flie name>
   --out <output dir>
   --loc <location e.g CP, SZ, ME>
   --platform <tester platform>
   --facilityfile <$DPSCRIPT/facilityMapping.ini>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will read HP Etest file and generate IFF file for dbascii

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/04/11 kazukik	: new creation
 2015/04/24 jason	: generalized to work with other ET types.  Added  --platform argument to specify tester type.
 2015/05/29 grace  	: Added support for -v option.
 2015/06/21 grace       : set value for input_file of PP_LIMITS
 2015/06/24 gilbert     : Set Acceptance Rules for MXIC
 2015/06/26 gilbert     : Removed "." from the Lot number 
 2015/07/02 gilbert     : Set EQUIP6_ID value to site/location e.g CP, SZ, ME, and etc and required it
 2015/07/28 jgarcia	: initialize $header->PROGRAM_CLASS to 5.
 2015/07/28 jgarcia	: check for Program name greater than 35 chars. ang truncate if greater.
 2015/07/31 jgarcia	: load in production schema if the product does not match, but load into the sandbox if the product 
 			: in the file is missing and load with product as "NA".
 2015/08/10 eric	: replaced arg[1] with platform.
 2015/09/04 rodney  	: Made SITE a required option.
 2015/10/16 eric 	: bypass lot lookup for VGRD_TW
 2015/11/19 eric	: always generate but do not register limit if sandbox
 2015/11/23 jgarcia	: Added TYPE param to indicate if Process or Product info to be added in Program.
 2016/03/02 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2016/07/15 eric	: changed INFO to WARN msgs for product errors
 2017/03/31 eric        : counter check product in pplot if not available in ppprod
 29-May-2017 gilbert    : generate limits always and dont register in refdb.pp_limits
 2017/08/22 carmilo	: added condition to not normalize Vanguard ET data
 2019/11/29 karen	: added condition for new parser if file is csv
 2020/09/01 karen       : added support to fork and qde output (IFF)/files to designated location
 2021/04/12 glory       : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

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
use PDF::Parser::HP_ET;
use PDF::Parser::HP_ET_CSV;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use v5.10;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;

our $VERSION = "

1.0
";

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();


# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "FORK=s", "LOC=s", "FACILITYFILE=s", "PLATFORM=s", "TYPE=s", "LOGFILE=s", "DEBUG", "V",
        "TRACE", "SITE=s", "PPLOG", "QDE" )
    )
{
    dpExit( 1, "invalid options" );
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT LOC PLATFORM SITE TYPE FACILITYFILE/;
pod2usage(4) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");


my $site=$hOptions{SITE};

# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    	pod2usage();
    	dpExit( 1, "input file does not exist $infile" );
}


our $tester = $hOptions{PLATFORM};
INFO("Platform = ".$hOptions{PLATFORM});
# check output dir
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},
	qde => $hOptions{QDE},
        basename => ( basename $infile),
        ext      => 'iff',
        gzipIFF  => 'Y'
    }
);

INFO("infile  = $infile");

#my $parser = PDF::Parser::HP_ET->new;

#my $model = $parser->readFile($infile, $hOptions{PLATFORM}, $hOptions{SITE});

#karen
my $model;
my $parser;

if ($infile =~ /\.csv$/i){
	$parser = PDF::Parser::HP_ET_CSV->new;
	$model = $parser->readFile($infile, $hOptions{PLATFORM}, $hOptions{SITE});

}
else {
 	$parser = PDF::Parser::HP_ET->new;
	$model = $parser->readFile($infile, $hOptions{PLATFORM}, $hOptions{SITE});
}

my $misc  = $model->misc;
#=pod

#carmilo
if(!($hOptions{SITE} eq 'vgrd_tw_et_eagle')) {
	&normalizeToBaseUnit($model);
}

my $header = $model->header;
$header->VERSION($VERSION);

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);
if ($misc->{wf_flg} == 1) {
	$pplogger->setWaferFlag(1);
}

my $location     = $hOptions{LOC};
my $reglim_flg = "Y";

$header->EQUIP6_ID( "$facility" );

my $lot = $header->LOT;
   $lot =~ s/\.//g;
   $header->LOT($lot);

given ($site) {
    	when ('mxic_tw') {
		### Lot Naming rules ###
		my $lot     = $header->LOT;
		my $str_len = length($lot);
		if (($str_len != 6 &&  $str_len != 8) ||  $lot !~/^1/)
		{
	   		$wr->forSBox(1);
	   		$reglim_flg = "N";
           		INFO("LotID should be 6 or 8 characters and begins with 1 LotID:$lot");			
		}																
     	}
}

if ($location ne "MXIC_TW" && $location ne "MAXCHIP_TW" && $location ne "TSMC_TW" && $location ne "VGRD_TW"){
   	unless ($header->populateMeta){
		$wr->noMeta(1);
		$reglim_flg = "N";
   	}
}

if($header->{PRODUCT} ne "") {
	### check product from file to refdb ###
	my $flag = $header->populateMetaByProduct;
	if($flag == 0) {
		#WARN("Generating IFF using product id from file = ".$header->PRODUCT);
		INFO ("Lookup product in PP_LOT.");
		$flag = $header->populateMeta;
		if ($flag == 1){
			$header->populateMetaByProduct;
		}
		else {
			WARN("Generating IFF using product id from file = ".$header->PRODUCT);
		}
	}
} else {
	WARN("Product not found in file and in database..sending file to Sandbox");
	$header->PRODUCT("NA");
	$wr->forSBox(1);
	$reglim_flg = "N";
}

$header->EQUIP1_ID($tester);
$model->dataSource($tester);
$header->PROGRAM_CLASS(5);

my $program = $header->PROGRAM;

if ( length($program) > 35 )
{
        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
        $wr->forSBox(1);
	$reglim_flg = "N";
        $program = substr($program, 1, 35); # Leave enough room for session type
}

$header->PROGRAM($program);

$model->updateProgram($hOptions{TYPE});
INFO("Test Program = ".$header->PROGRAM);
my $fmt = new_iff_formatter({
  	model=>$model,
  	writer=>$wr
});
 

$fmt->dataItems([qw/site x y/]);
$fmt->testItems([qw/number name units/]);
$fmt->printPar();

# Limits
#if ($reglim_flg eq "Y") {
#	if ($model->isLimitNew){
#  		$model->buildLimit;
#  		$fmt->printLimit;
#  		$model->limit->input_file(basename $infile); 
#  		$model->limit->registerRefdb;
#	}
#}
#else {   # always generate but do not register limit if sandbox
	$model->buildLimit;
	$fmt->printLimit;
	$model->limit->input_file(basename $infile);
#}
#=cut

dpExit(0);
