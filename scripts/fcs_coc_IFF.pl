#!/usr/bin/env perl_db
# SVN $Id: fcs_coc_IFF.pl 2174 2017-05-18 10:13:34Z dpower $

=pod

=head1 SYNOPSIS

  fcs_coc_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
      --loc <location>
      --config <config_tester_type>
      [--logfile <logfilepath>]  
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read STDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

2015/07/21 grace : new 
2015/09/04 eric  : truncate ppid if > 35
2016/03/02 wsanopao: logging pre-processing information  to refdb.pp_log table.
18-May-2017 gilbert: generate limits always and dont register in refdb.pp_limits

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::Parser::COC;
use PDF::Formatter;
use PDF::DpWriter;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:

our $VERSION = "

1.0
";
our $TESTER  = "COC";

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
        \%hOptions,  "OUT=s",
        "LOGFILE=s", "DEBUG", "TRACE", "V", "TYPE=s","LOC=s",  "CONFIG=s", "PPLOG"
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

my @required_options = qw/OUT LOC/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $location     = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};

# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    dpExit( 1, "input file does not exist $infile" );
}

INFO("infile  = $infile");

my $parser = PDF::Parser::COC->new;

my @models = $parser->readFile($infile);
my $header_program = "";
my $i_loop = 0;


my $limit = new_limit;


foreach my $model (@models)
{		
	# check output dir
	my $wr = PDF::DpWriter->new(
		{   outdir   => $hOptions{OUT},
			basename => ( basename $infile),
			ext      => 'iff'
		}
	);
	# Rodney said 
	# Please disable the unit normalization.  The unit values from CofC files can vary widely, so the unit normalization routine may not normalize the data correctly.
	#&normalizeToBaseUnit($model);
	my $header = $model->header;
	$header->VERSION($VERSION);
	
	# wsanopao: Passing Reference of Model
	$pplogger->setModelHeader($model);
	
	if($header_program eq ""){
		$header_program = $header->PROGRAM;
	}
	
	$header->PROGRAM ($header_program);
		
	# Rodney said
	# The lot id and product id in these files will not be found in the reference tables refdb.pp_lot and refdb.pp_prod, so the meta lookup will always fail.  Please disable the meta lookup so the data will load into the production schema.
	#$wr->noMeta(1) unless ( $header->populateMeta );

	$header->PROGRAM_CLASS(9);
	my $location     = $hOptions{LOC};
	$header->EQUIP6_ID( "$location" );

	my $program = $header->PROGRAM;
	my $mattype = "_".$parser->getMatType;
	if ((length($program) + length($mattype)) > 35) {
		INFO("PROGRAM NAME \"".$program.$mattype."\" will be truncated to 35 characters.  Sending to sandbox.");
		$wr->forSBox(1);
		$program = substr($program, 1, 35-length($mattype));
	}
	$header->PROGRAM($program);

	$model->updateProgram;
	#$header->PROGRAM($header->PROGRAM."_".$parser->getMatType);
	$header->PROGRAM($header->PROGRAM.$mattype);
	INFO("Program-->".$header->PROGRAM);
	my $fmt = new_iff_formatter({
		model=>$model,
	  	writer=>$wr
	});
	#$fmt->dataItems([qw/site x y/]);
	$fmt->testItems([qw/number name units/]);
	$fmt->printPar();		
		
	INFO("i_loop:".$i_loop);
	
	#if ($model->isLimitNew and $i_loop ne $#models ){
	if ( $i_loop ne $#models ){
		my $model_t = $model->tests;
		foreach my $test (@$model_t){
			if(! chkTests($test->number, $test->name, $limit)){
				$limit->add( 'tests', $test);
			}
		}			
	}
	#elsif ( $i_loop eq $#models){
	elsif ($model->isLimitNew and $i_loop eq $#models){
	   	my $revision = $header->REVISION;
	   	$revision =~ s/\s+//g;
	   
	   	my $model_t = $model->tests;
	   	foreach my $test (@$model_t){
			if(! chkTests($test->number, $test->name, $limit)){
				$limit->add( 'tests', $test);
			}
		}	
			
	   	$limit->copyHeader($header);		   
	   	$model->limit($limit);
		   
	  	$model->buildLimit;
	  	$fmt->printLimit;
	  	$model->limit->input_file(basename $infile);
	  	#$model->limit->registerRefdb;
  
		# $limit->testItems([qw/number name units /]);
	}
			
	$i_loop++;
}

INFO("models count:".$#models);


sub chkTests{
my $test_num = shift;
my $test_nam = shift;
my $limit_u = shift;
my $value = 0;
#INFO("test_num:".$test_num);
#INFO("test_nam:".$test_nam);
my $limit_test = $limit_u->tests;
foreach my $wk (@$limit_test){

	
	if(($wk->number eq $test_num ) and
		($wk->name eq $test_nam))
		{
			$value = 1;
		}		
}

return $value;

}

dpExit(0);

