#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_pcm_IFF.pl <Input flie name>
      	--out <output dir>
      	[--type <Process|Product>]
      	[--logfile <logfilepath>]
      	[--debug|--trace]
  	[-V Display version ID]

=head1 DESCRIPTIONS

B<This script> will read PCM file and generate IFF file for dbascii

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/04/23 grace	: new creation
 2015/05/29 grace  	: Added support for -v option.
 2015/06/23 jgarcia 	: added code to check for limit file if new, register it to refdb.pp_limit and 
 			write it out to output on appropriate output folder[stage or stage_sandbox].
 2015/07/02 jgarcia 	: added to accept location in LOC as a required argument and assign the value to EQUIP6_ID. 
 2015/07/28 jgarcia	: initialize $header->PROGRAM_CLASS to 5.
 2015/07/28 jgarcia	: check for Program name greater than 35 chars. ang truncate if greater.
 2015/11/19 eric   	: always generate but do not register limits if sandbox.
 2015/11/23 jgarcia	: Added TYPE param to indicate if Process or Product info to be added in Program.
 2016/01/16 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2017/04/06 eric	: assign source lot as wafer name.
 16-May-2017 Gilbert    : generate limits always and dont register in refdb.pp_limits
 2020/09/01 karen       : added support to fork and qde output (IFF)/files to designated location
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
use PDF::Parser::AMS_BKET;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao: 
use Config::Tiny;

our $VERSION 	= "1.0";
our $TESTER  	= "AMS";
my (%hOptions) 	= ();
my $location 	= "";
my $reglim_flg 	= "Y";

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    	pod2usage();
    	dpExit( 1, "No input file specified" );
}
unless (
    	GetOptions( \%hOptions, "OUT=s", "FORK=s", "LOC=s", "FACILITYFILE=s", "TYPE=s", "LOGFILE=s", "DEBUG", "V",
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

my @required_options = qw/OUT LOC TYPE FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}



my $location = $hOptions{LOC};
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
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
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
{   	outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},        
	qde => $hOptions{QDE},
        basename => ( basename $infile),
        ext      => 'iff',
        gzipIFF  => 'Y'
});

INFO("infile  = $infile");

my $parser = PDF::Parser::AMS_BKET->new;

if($infile =~ /gz$/)
{
	my $command = "gunzip $infile";
	my $ret = system($command);	
}
else{

	my $model = $parser->readFile($infile);

	&normalizeToBaseUnit($model);

	my $header = $model->header;

	$header->VERSION($VERSION);
	$header->PROGRAM_CLASS(5);
	$header->EQUIP6_ID($facility);
	
	my $program = $header->PROGRAM;
	
	# wsanopao: Passing Reference of Model
	$pplogger->setModelHeader($model);

	if ( length($program) > 35 )
	{
	        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters. Sending to sandbox.");
	        $wr->forSBox(1);
		$reglim_flg = "N";
	        $program = substr($program, 1, 35); # Leave enough room for session type
	}
	
	$header->PROGRAM($program);

	unless ($header->populateMeta){
		$wr->noMeta(1);
		$reglim_flg = "N";
	}

	if ($header->SOURCE_LOT ne "") {
		$model->wafers->[0]->name($header->SOURCE_LOT."_".sprintf("%02d",$model->wafers->[0]->number));
		$pplogger->setWaferFlag(1);
	}

	$model->updateProgram($hOptions{TYPE});

	my $fmt = new_iff_formatter({
	 	model=>$model,
	  	writer=>$wr
	});

	$fmt->dataItems([qw/site x y/]);
	$fmt->testItems([qw/number name units/]);
	$fmt->printPar();

	#if ($reglim_flg eq "Y"){
	#	if ($model->isLimitNew){
  	#		my $limit = new_limit;
  	#		$limit->copyHeader($header);
  	#		$limit->tests($model->tests);
  	#		$model->limit($limit);    
  	#		$model->buildLimit;
  	#		$fmt->printLimit;
  	#		$model->limit->input_file(basename $infile); 
  	#		$model->limit->registerRefdb;
	#	}
	#}
	#else {  #always generate & do not register limit 
		my $limit = new_limit;
		$limit->copyHeader($header);
                $limit->tests($model->tests);
                $model->limit($limit);
                $model->buildLimit;
                $fmt->printLimit;
                $model->limit->input_file(basename $infile);
	#}

}

dpExit(0);
