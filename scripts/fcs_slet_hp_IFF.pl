#!/usr/bin/env perl_db
# SVN $Id: fcs_slet_hp_IFF.pl 1454 2016-02-26 08:09:18Z dpower $

=pod

=head1 SYNOPSIS

  fcs_hp_et_jazz_IFF.pl <Input flie name>
      --out <output dir>
      --limitDir <limit file look up direcotry>	  
      --loc <location e.g. SL, CP>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will read HP Etest file and generate IFF file for dbascii

=head1 AUTHOR

B<hiroshi@pdf.com>

=head1 CHANGES

 2015/04/11 hiroshi : new creation
 2015/05/29 grace  	: Added support for -v option.
 2015/06/09 grace   : Changed operator, measuring equipment, probe card by Scott's request
 2015/06/21 grace   : set value for input_file of PP_LIMITS
 2015/06/24 grace   : comment out normalizeToBaseUnit by Rodney's request
					  addded data type 'C' 
 2015/07/06 eric    : added LOC arg and pass it as EQUIP6_ID.	
 2015/07/28 jgarcia: initialize $header->PROGRAM_CLASS to 5.
 2015/07/28 jgarcia: check for Program name greater than 35 chars. ang truncate if greater.				  
 2015/11/19 eric   : always generate but do not register limit if sandbox
 2015/11/23 jgarcia: Added TYPE param to indicate if Process or Product info to be added in Program.
 2015/12/03 jgarcia: changed to move the file to NotProcessed instead to ReworkFiles if no limit found.
 2016/02/26 wsanopao: logging pre-processing information  to refdb.pp_log table.
 
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
use PDF::Parser::SLET_HP;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao: 

our $VERSION = "

1.0
";
our $TESTER  = "SLET_HP";

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "LIMITDIR=s", "LOC=s", "TYPE=s", "LOGFILE=s", "DEBUG", "V",
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

my @required_options = qw/OUT LIMITDIR LOC TYPE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $location = $hOptions{LOC};

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
        ext      => 'iff'
    }
);

# check limit lookup dir
my $limitdir = $hOptions{LIMITDIR};
if ( ! -d $limitdir ) {
    ERROR("limit lookup dir does not exist $limitdir");
    pod2usage();
}

INFO("infile  = $infile");

my $parser = PDF::Parser::SLET_HP->new;
my $limit_file = "";
my $reglim_flg = "Y";
my $model = $parser->readFile($infile, $limitdir, \$limit_file);

#Rodney said 'no use it for slet hp'
#&normalizeToBaseUnit($model); 
  
my $header = $model->header;
$header->VERSION($VERSION);
$header->EQUIP6_ID($location);
$header->PROGRAM_CLASS(5);

my $program = $header->PROGRAM;

# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);

if ( length($program) > 35 )
{
        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
        $wr->forSBox(1);
	$reglim_flg = "N";
        $program = substr($program, 1, 35); # Leave enough room for session type
}
	
	$header->PROGRAM($program);

unless ($header->populateMeta){
	$wr->noMeta(1);
	$reglim_flg = "N";
}
#$header->EQUIP1_ID("HP");

$model->updateProgram($hOptions{TYPE});

my $fmt = new_iff_formatter({
  model=>$model,
  writer=>$wr
});

$fmt->dataItems([qw/site x y/]);
$fmt->testItems([qw/number name units/]);
$fmt->printPar();

# Limits
if($limit_file eq "not")
{
	dpExit( 1, "Limit file not found ");
}

if ($reglim_flg eq "Y") {
	if ($model->isLimitNew){
   		#my $searchPath = "$limitdir/PT90NOS300_3.DESC";
   		my $revision = $header->REVISION;
   		$revision =~ s/\s+//g;
   		my $searchPath = "$limitdir/".$model->programOrg."_".$revision."*";
   		my ($limitfile) = glob($searchPath);
   
   		unless (defined $limitfile) {
   		   dpExit(4,"Limit file not found : $searchPath");
   		}
   
   		my $limit = $parser->readLimitFile($limitfile);   
   		$limit->copyHeader($header);
   
 		# Rodney said 'no use it for slet hp'
 		# &normalizeToBaseUnit($limit);   
   		$model->limit($limit);
   		$limit->testItems([qw/number name units /]);
   		$fmt->printLimit;
   		$model->limit->input_file(basename $infile); 
   		$limit->registerRefdb;
	}
}
else {   #always generate but do not register limit if sandbox
                my $revision = $header->REVISION;
                $revision =~ s/\s+//g;
                my $searchPath = "$limitdir/".$model->programOrg."_".$revision."*";
                my ($limitfile) = glob($searchPath);

                unless (defined $limitfile) {
                   dpExit(4,"Limit file not found : $searchPath");
                }

                my $limit = $parser->readLimitFile($limitfile);
                $limit->copyHeader($header);
                $model->limit($limit);
                $limit->testItems([qw/number name units /]);
                $fmt->printLimit;
                $model->limit->input_file(basename $infile);
}

dpExit(0);

