#!/usr/bin/env perl_db
# SVN $Id: fcs_stdf_rdhm_et_IFF.pl 2628 2020-10-09 01:19:13Z dpower $

=pod

=head1 SYNOPSIS

  fcs_stdf_rdhm_et_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
      --loc <location>
      --tpDIR <TP location>
      [--logfile <logfilepath>]  
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read RH_STDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

28-Jun-2016  Eric    : new 
30-Jun-2017  Gilbert : generate limits always and dont register in refdb.pp_limits 
2020/09/01 karen       : added support to fork output (IFF)/files to designated location
2021/04/13 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

=head1 LICENSE

=cut

use strict;
use warnings;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::Parser::Stdf;
use PDF::Parser::Stdf::Generic;
use PDF::Formatter;
use PDF::DpWriter;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use Tie::File;
use PPLOG::PPLogger; 	# wsanopao: 
use Config::Tiny;
our $VERSION = "

1.0
";
our $TESTER  = "RH";

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
        \%hOptions,  "OUT=s", "FORK=s", "LOC=s", "FACILITYFILE=s", "TPDIR=s", "TYPE=s", "SITE=s",
        "LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG", "QDE"
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
my @required_options = qw/OUT LOC TYPE SITE FACILITYFILE/;

my $tpDir = $hOptions{TPDIR};
my $site = $hOptions{SITE};
my $reglim_flg = "Y";

pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
if($hOptions{FINALLOT}) {
	$facility = $config->{$location}->{finalTest};
} else {
	$facility = $config->{$location}->{probe};
}

INFO("FACILITY|EQUIP6_ID=$facility");

# check input file
my $infile = $ARGV[0];
if ( ! -f $infile ) {
    ERROR("$infile does not exist");
    pod2usage(3);
}

# create Writer
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   basename => ( basename $infile),
        ext      => 'iff',
        outdir   =>  $hOptions{OUT},
	forkdir => $hOptions{FORK},
	qde => $hOptions{QDE},
	gzipIFF => 'Y'
    }
);

INFO("infile  = $infile");

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);
$pplogger->setEnv($site);
# create Parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $TD_txt = convertBinToAscii($infile);
my $td 	   = readStdfAscii($TD_txt);
my $header = new_headerLong->new( $parser->stdf2header($td) );
my $model  = new_model({dataSource => 'RH'});
   $model->header($header);
#my ($tests, $testCond) = getTestsFromTP($model,$tpDir, $TD_txt);
my ($tests, $testCond) = getTestsFromTP($model,$tpDir);

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

unless ( $header->populateMeta ) {
        $wr->noMeta(1);
        $reglim_flg = "N";
}

# Check Program length for > 35.  Truncate and send to sandbox.
my $program = $header->PROGRAM;
if ( length($program) > 35 )
{
  	INFO("PROGRAM NAME \"$program\" will be truncated to 35 characters.  Sending to sandbox.    ");
  	$wr->forSBox(1);
  	$reglim_flg = "N";
  	$program = substr($program, 1, 35); # Leave enough room for session type
}
$header->PROGRAM($program);
$header->PROGRAM_CLASS(5);
$header->EQUIP6_ID($hOptions{LOC});
$model->updateProgram($hOptions{TYPE});

foreach my $stdfWafer (@{$td->wafers}) {
	my $wafer = new_wafer;
        $wafer->START_TIME( $header->START_TIME );
        $wafer->END_TIME( $header->END_TIME );
        my $waferNum = -1;
        if (defined $stdfWafer->WIR) {
            	$waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
            	$wafer->number($waferNum);
            	if ( defined $stdfWafer->WIR->{START_T} && $stdfWafer->WIR->{START_T} > 1000000000 )
            	{
                	$wafer->START_TIME($stdfWafer->WIR->{START_T});
            	}
            	if ( defined $stdfWafer->WRR->{FINISH_T} && $stdfWafer->WRR->{FINISH_T} > 1000000000 )
            	{
                	$wafer->END_TIME( $stdfWafer->WRR->{FINISH_T} );
            	}
        }	

	$wafer->tests($tests);
	$wafer->dies( $parser->res2dies_v2( $stdfWafer->res, $tests ) );
	$model->add( 'wafers', $wafer );
}

&normalizeToBaseUnit($model);

my $formatter = new_iff_formatter(
	{   model  => $model,
	    writer => $wr
	}
);
$formatter->dataItems([qw/x y site partid hard_bin soft_bin/]);
$formatter->printPar_v2;

unlink $TD_txt unless (isLogDebug);

#Limits
#if ($reglim_flg eq "Y") {
#   if ($model->isLimitNew){
#        $model->buildLimit;
#        $model->limit->conditionNames($testCond);
#        $formatter->printLimit;
#        $model->limit->input_file(basename $infile);
#        $model->limit->registerRefdb;
#   }
#}
#else {  # always generate but do not register limit if sandbox
        $model->buildLimit;
        $model->limit->conditionNames($testCond);
        $formatter->printLimit;
        $model->limit->input_file(basename $infile);
#}

sub getTestsFromTP{
  	my $model = shift;
  	my $tpDir = shift;
  	#my $TD_txt_inTemp = shift;
  	my $program = $model->header->PROGRAM;
  	my $rev = $model->header->REVISION;

  	my $regexp = "${program}_REV_$rev";
  	INFO( "TP file search pattern : $regexp");
  	my $TP = undef;
  	foreach my $file (glob "$tpDir/*.RH_STDF*.TP"){
    		if ($file =~ /$regexp/i){
       			INFO("TP Found : $file");
       			$TP = $file;
    		}
  	}

  	unless (defined $TP ) {
        	#unlink $TD_txt_inTemp unless (isLogDebug);
    		dpExit(4,"No TP found in $tpDir by pattern $regexp");
  	}

    	my $TP_txt = convertBinToAscii($TP);
    	my $tp     = readStdfAscii($TP_txt);
    	#my $header = new_headerLong->new( $parser->stdf2header($tp) );
	my $header = $model->header;
    	my $testCond = [qw/PIN_1 PIN_2 PIN_3 SBIN_NUM HBIN_NUM
        	VCC VEE TEMP FREQ PARMTYPE SEQ_NAME
        	TCONDS SBIN_NAM HBIN_NAM TEST_TXT
        	LOAD_VAL TEST_CAT VIEW_ORD /];
        $parser->testConditions_EPDR( $testCond);
    	my $tests  = $parser->epdr2tests( $tp->EPDR );

    	foreach my $test(@$tests){
        	my @pins ;
        	push @pins, (shift @{$test->conditions});
        	push @pins, (shift @{$test->conditions});
        	push @pins, (shift @{$test->conditions});
        	unshift @{$test->conditions},join(" ",@pins);
    	}

        shift @$testCond;
        shift @$testCond;
        shift @$testCond;
        unshift @$testCond,qw/TestNumber TestName Units PINS/;
    	unlink $TP_txt unless (isLogDebug);
    	return $tests, $testCond;
}

dpExit(0);
