#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  xqorvo_aos_tr_csv_data_IFF.pl <Input flie name>
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

B<jovenkarlo.sorallo@onsemi.com>

=head1 CHANGES

 2025/02/20 joven 	: new
 

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
use PDF::Parser::xQORVO_AOS_TR_CSV;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;
use POSIX qw(strftime);
use Time::localtime;
use File::stat;
use Time::Piece;

our $VERSION = "

1.0
";
our $TESTER  = "AOS";

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

my @required_options = qw/OUT LOC/;
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

INFO("infile = $infile");
if($infile =~ /(_RT_\d+.)/)
{	
	INFO("skip files with _RT_,<Number>.csv $infile");
    dpExit( 1, "skip files with _RT_,<Number>.csv $infile" );
}

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

my $parser = PDF::Parser::xQORVO_AOS_TR_CSV->new;
my $reglim_flg = "Y";

my $model = $parser->readFile($infile, isLogDebug);

#&normalizeToBaseUnit($model);

my $header = $model->header;

   #$header->isFinalLot($hOptions{RAWLOT});
    
#unless ( $header->populateMeta ){
#	#$wr->noMeta(1);
#	if (!($hOptions{NOSANDBOX})) {
#		$wr->noMeta(1);
#	}
#	else {
#		WARN("File was not sandboxed. Argument was enabled.");
#	}
#	$reglim_flg = "N";
#}
$header->VERSION($VERSION);
$header->EQUIP6_ID($facility);
$header->PROGRAM_CLASS(2);
$header->FAB("AOS");
# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);


#my $file_time = localtime( stat($infile)->mtime )->strftime("%Y/%m/%d %H:%M:%S");
#   $header->START_TIME($file_time);
#   $header->END_TIME($file_time);
#   $header->END_TIME($file_time);
   
my $lotid = $header->LOT;   
INFO("LOT data" .$lotid );
if ($lotid eq "")
{
	 dpExit( 1, "No Lot Id Data" );
}
my $program = $header->PROGRAM;
my $recipe_revision = $header->REVISION;
my $product = $header->PRODUCT;
if ( length($program) > 35 )
{
	INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
	$wr->forSBox(1);
	$reglim_flg = "N";
	$program = substr($program, 1, 35); # Leave enough room for session type
}


$program = "AOS_" . $product . "_" . $program . "_". $recipe_revision . "_TR";
INFO("PROGRAM NAME " .$program );



$header->STEP("TR");
$header->PROGRAM($program);
#$model->updateProgram;
#$model->updateWMap;

#my $wmap = $model->updateWMap;

#$wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
#$wr->noWMap(1) unless ( $wmap->confirmed );

my $formatter = new_iff_formatter(
	{   model  => $model,
            writer => $wr
	}
);
		
$formatter->dataItems([qw/site x y soft_bin hard_bin partid/]);
$formatter->testItems([qw/number name units/]);
$formatter->printPar;

#Limits
#if ($reglim_flg eq "Y") {
#	if ($model->isLimitNew){
#	   my $limit = new_limit;
#	   $limit->copyHeader($header);
#	   $limit->tests($model->tests);
#	   $model->limit($limit);
#	   $model->buildLimit;
#	   $formatter->printLimit;
#	   $model->limit->input_file(basename $infile); 
#	   $limit->registerRefdb;
#	  	   	
#	}
#}	
#else {  #always generate but do not register limit if sandbox
my @limitsArr = model->tests;
	if (@limitsArr){
		#INFO("LIMITS  is not empty" );
		my $limit = new_limit;
		$limit->copyHeader($header);
		$limit->tests($model->tests);	
		$model->limit($limit);
		$model->buildLimit;
		$formatter->printLimit;
		$model->limit->input_file(basename $infile);
	
		
	}else{
		
		INFO("LIMITS  is  empty" );
		dpExit("LIMITS  is  empty" );
	}

#}
	
dpExit(0);
