#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_njrc_IFF.pl <Input flie name>
      --out <output dir>
      --type Process or Product
      --loc<location e.g. NJRC_JP, CP, ME>
      --DEVICECFG <jnrc_device.txt>
      --limitDir <limit file look up direcotry>
      --facilityfile <$DPSCRIPT/facilityMapping.ini>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will read PCM file and generate IFF file for dbascii

=head1 AUTHOR

B<sungsuk.moon@pdf.com>

=head1 CHANGES

 2015/04/28 grace : new creation
 2015/05/29 grace : Added support for -v option.
 2015/06/08 grace : set fab as "NJRC_JP"
				    add limit
 2015/06/21 grace : set value for input_file of PP_LIMITS					
 2015/07/06 eric  : added LOC arg and pass it as EQUIP6_ID.
 2015/11/03 eric  : added program class 5
 2015/11/19 eric  : always generate but do not register limit if sandbox
 2015/11/23 jgarcia: Added TYPE param to indicate if Process or Product info to be added in Program.
 2016/01/25 eric : do not set FAB
 2016/03/02 wsanopao: logging pre-processing information  to refdb.pp_log table.
 2021/04/12 glory   : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after. 

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
use PDF::Parser::NJRC;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;

our $VERSION = "

1.0
";
our $TESTER  = "NJRC";

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "LOC=s", "FACILITYFILE=s", "LIMITDIR=s", "SITE=s", "TYPE=s", "DEVICECFG=s", "LOGFILE=s", "DEBUG", "TRACE", "V","PPLOG" )
    )
{
    dpExit( 1, "invalid options" );
}
 
if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT DEVICECFG LIMITDIR LOC TYPE SITE FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $site = $hOptions{SITE};
my $reglim_flg = "Y";
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");


# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);
$pplogger->setEnv($site);
if ( !-f $infile ) {
    pod2usage();
    dpExit( 1, "input file does not exist $infile" );
}


# check limit lookup dir
my $limitdir = $hOptions{LIMITDIR};
if ( ! -d $limitdir ) {
    ERROR("limit lookup dir does not exist $limitdir");
    pod2usage();
}


# check output dir
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        basename => ( basename $infile),
        ext      => 'iff',
        gzipIFF  => 'Y'
    }
);


my $parser = PDF::Parser::NJRC->new;
my $program_short;

if($infile =~ /gz$/)
{
	my $command = "gunzip $infile";
	my $ret = system($command);	
}
else{
	my $model = $parser->readFile($infile, $hOptions{DEVICECFG});
	my $header = $model->header;

	$header->VERSION($VERSION);
	$header->EQUIP6_ID($facility);
	$header->PROGRAM_CLASS(5);
	$program_short = $header->PROGRAM;
	
	unless ($header->populateMeta) {
		$wr->noMeta(1);
		$reglim_flg = "N";
	}

	#$header->FAB("NJRC_JP");
	
	$model->updateProgram($hOptions{TYPE});
	
	# wsanopao: Passing Reference of Model
	$pplogger->setModelHeader($model);
	
	my $fmt = new_iff_formatter({
	  model=>$model,
	  writer=>$wr
	});

	$fmt->dataItems([qw/site x y/]);
	$fmt->testItems([qw/number name units/]);
	
	########### limit tests
	my $searchPath = "$limitdir/NJRCBP_TESTPLANS.csv";
	my ($limitfile) = glob($searchPath);
	
	my $limit;
	
	if(-f $searchPath)
	{
		$limit = $parser->readLimitFile($limitfile,$program_short,$header->PROGRAM,$header->REVISION);
	}
	########### limit tests
	my $tests_2;
	my $tests = $model->tests;	
	
	foreach my $test (@$tests)
	{				
		$test->number(getLimitTest($test->name, $limit->tests,"number"));
		$test->units(getLimitTest($test->name, $limit->tests,"units"));
			
	}	
	$model->tests($tests);
	
	&normalizeToBaseUnit($model);
	
	$fmt->printPar();	
	
	#if ($model->isLimitNew){
	   	   
	   unless (defined $limitfile) {
		  dpExit(4,"Limit file not found : $searchPath");
	   }
	   my $limit = $parser->readLimitFile($limitfile,$program_short,$header->PROGRAM,$header->REVISION);
	   $limit->copyHeader($header);
	   &normalizeToBaseUnit($limit);
	   $model->limit($limit);
	   $fmt->printLimit;
	   $model->limit->input_file(basename $infile); 
	   $limit->registerRefdb if ($reglim_flg eq "Y");
	#}
	
}
  
  
sub getLimitTest
{
	my $test_name = shift;
	my $limit = shift;
	my $value = shift;
	my %new_test;
	foreach my $test (@$limit){
	
		if(trim($test->name) eq trim($test_name))
		{
			if($value eq "number"){
			
				return $test->number;
			}
			elsif($value eq "units"){
				return $test->units;
			}
			
		}
	}

}

dpExit(0);

