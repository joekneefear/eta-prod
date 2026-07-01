#!/usr/bin/env perl_db
# SVN $Id: fcs_hp_jazz_et_IFF.pl 2193 2017-05-29 09:32:16Z dpower $

=pod

=head1 SYNOPSIS

  fcs_hp_et_jazz_IFF.pl <Input flie name>
      --loc <location e.g CP, SZ, ME>
      --out <output dir>
      --type Process or Product
      --facilityfile <$DPSCRIPT/facilityMapping.ini>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will read HP Etest file and generate IFF file for dbascii

=head1 AUTHOR

B<hiroshi@pdf.com>

=head1 CHANGES

 2015/04/11 hiroshi 	: new creation
 2015/05/29 grace   	: Added support for -v option.
 2015/06/21 grace   	: set value for input_file of PP_LIMITS
 2015/06/30 grace   	: added tests number  
 2015/06/30 grace   	: partid will be used to lookup the product attributes from pp_prod as backup when the lot is not matched in pp_lot.
 2015/07/02 gilbert 	: Added --loc <location e.g CP, SZ, ME>
 2015/07/09 grace   	: Fixed following issue
	          	the last result from the last test from the last wafer is always loaded as 0
 2015/07/13 grace   	: Changed data source from "HP_JAZZ" to "HP"
 2015/07/21 eric    	: sandbox if ppid > 35
 2015/11/19 eric    	: always generate but do not register limit if sandbox
 2015/11/23 jgarcia	: Added TYPE param to indicate if Process or Product info to be added in Program.
 2016/03/02 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2017/04/06 eric	: set wafer flag for  pplogging
 29-May-2017 gilbert    : generate limits always and dont register in refdb.pp_limits
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
use PDF::Parser::HP_JAZZ_ET;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;


our $VERSION = "1.0";
our $TESTER  = "HP_ET";
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    	pod2usage();
    	dpExit( 1, "No input file specified" );
}
unless (
    	GetOptions( \%hOptions, "LOC=s", "FACILITYFILE=s", "OUT=s", "LOGFILE=s", "TYPE=s", "DEBUG", "V",
        "TRACE", "PPLOG", )
    	)
{
    	dpExit( 1, "invalid options" );
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/LOC OUT TYPE FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
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
my $wr = PDF::DpWriter->new({   	
	outdir   => $hOptions{OUT},
    	basename => ( basename $infile),
    	ext      => 'iff',
        gzipIFF  => 'Y'

});

INFO("infile  = $infile");
my $reglim_flg = "Y";
my $parser = PDF::Parser::HP_JAZZ_ET->new;
my $model = $parser->readFile($infile);
&normalizeToBaseUnit($model);
my $header = $model->header;
   $header->VERSION($VERSION);
   $header->EQUIP6_ID($facility);
my $program = $header->PROGRAM;

if(length($program) > 35) {
	INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
	$wr->forSBox(1);
	$reglim_flg = "N";
	$program = substr($program, 1, 35); # Leave enough room for session type
}

$header->PROGRAM($program);
$header->PROGRAM_CLASS(5);

unless ($header->populateMeta)
{
	$wr->noMeta(1);
	$reglim_flg = "N";
	$header->populateMetaByProduct;	
}

$model->updateProgram($hOptions{TYPE});

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);
if ($header->SOURCE_LOT ne "") {
	$pplogger->setWaferFlag(1);
}

my $fmt = new_iff_formatter({
  	model=>$model,
  	writer=>$wr
});

$fmt->dataItems([qw/site x y/]);
$fmt->testItems([qw/number name units/]);
$fmt->printPar();

#Limits
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

dpExit(0);
