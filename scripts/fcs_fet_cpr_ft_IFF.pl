#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_fet_cpr_ft_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
      --TPDIR <
      --loc <location e.g CP, SZ, ME>
      --config <cfg_tester_type>
      [--finallot]
      [--logfile <logfilepath>]  
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read STDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<eric.alfanta@onsemi.com>

=head1 CHANGES

2016/09/28 eric : copied and modified script from fcs_fet_ft_IFF.pl for AMKOR_PH loading
		: used res2dies_fet_sort to get results
29-May-2017 gilbert: generate limits always and dont register in refdb.pp_limits

=head1 LICENSE

(C) ON Semiconductior. 2016 All rights reserved.

=cut

use strict;
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
use PDF::Util::AddTestFlowtoTPUsingRef qw/addTestFlowtoTP load_testflow_ref/;
use PPLOG::PPLogger; 	# wsanopao: 
use Number::Range;

our $VERSION = "1.0";
our $TESTER  = "FET";

# a hash to receive options
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
	pod2usage(3);
}
unless (
    	GetOptions(
        	\%hOptions,  "OUT=s", "LOGFILE=s", "DEBUG", "TRACE", "V", "TPDIR=s", 
		"TYPE=s", "FINALLOT", "LOC=s", "SITE=s", "CONFIG=s", "PPLOG", "RELLOT"))
{
    	dpExit( 1, "invalid options" );
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};
# Initialize logging

my @required_options = qw/OUT LOC TPDIR/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $location     = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
my $site = $hOptions{SITE};

# check input file
my $infile = $ARGV[0];
if ( ! -f $infile ) {
    	ERROR("$infile does not exist");
    	pod2usage(3);
}

# wsanopao: Set Raw File ==> infile
$PPlogger->setRawFile($infile);

# create Writer
my $wr = PDF::DpWriter->new(
    {   basename => ( basename $infile),
        ext      => 'iff',
        outdir   =>  $hOptions{OUT}
    }
);

# create Parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $perl = "perl";
my $reglim_flg = "Y";
my ( $TP_bin, $TD_bin );

# Convert CPR file to TD
INFO("type : ". $hOptions{TYPE});
my $command = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_fet_cpr_pmft.pl -infile=$infile";	

INFO("$command ");
my @output = `$command`;
if ($?) {
    	print "error in $command\n";
    	dpExit( 1, "Failed to convert $command : $!" );
}
if ( $output[-1] =~ /td=(.*)/ ) {
    	$TD_bin = $1;
    	INFO("TD=$TD_bin");
}
else {
    	dpExit( 1, "Failed to convert $command : " . join( "#", @output ) );
}

my $TD_txt = convertBinToAscii($TD_bin);
my $td     = readStdfAscii($TD_txt);
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());
my $header = new_headerLong->new( $parser->stdf2header($td) );
my $orig_prod = $header->PRODUCT;
   $header->isFinalLot($hOptions{FINALLOT});

$header->CFG_TESTER_TYPE($cfg_tstr_typ);
$header->EQUIP6_ID( "$location" );
$header->PROGRAM_CLASS(2);

# find the corresponding PRN file
my $TP_path = $hOptions{TPDIR};
my $regexp = $header->PROGRAM;

my $PRN = undef;
foreach my $file (glob "$TP_path/*.PRN"){
  	if ($file =~ /$regexp/i){
     		INFO("PRN Found : $file");
     		$PRN = $file;
  	}
}

unless (defined $PRN ) {  
    	unless (isLogDebug) {
    		unlink $TD_bin;
    		unlink $TD_txt;
	}

    	dpExit(4,"No PRN found in $TP_path by pattern $regexp");
} 

# Convert PRN file to TP
my $command2 = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_fet_prn_pmft.pl -infile=$PRN";

INFO("$command2 ");
my @output2 = `$command2`;
if ($?) {
    	print "error in $command2\n";
    	dpExit( 1, "Failed to convert $command2 : $!" );
}
if ( $output2[-1] =~ /tp=(.*)/ ) {
    	$TP_bin = $1;
    	INFO("TP=$TP_bin");
}
else {
    	dpExit( 1, "Failed to convert $command2 : " . join( "#", @output2 ) );
}

my $TP_txt = convertBinToAscii($TP_bin);
my $tp     = readStdfAscii($TP_txt);
my $testCond = [qw/PIN_1 PIN_2 PIN_3 SBIN_NUM HBIN_NUM
        VCC VEE TEMP FREQ PARMTYPE SEQ_NAME
        TCONDS SBIN_NAM HBIN_NAM TEST_TXT
        LOAD_VAL TEST_CAT VIEW_ORD /];
$parser->testConditions_EPDR($testCond);

my $tests  = $parser->epdr2tests( $tp->EPDR );

foreach my $test(@$tests){
        my @pins;
        push @pins, (shift @{$test->conditions});
        push @pins, (shift @{$test->conditions});
        push @pins, (shift @{$test->conditions});
        unshift @{$test->conditions},join(" ",@pins);
}
shift @$testCond;
shift @$testCond;
shift @$testCond;
unshift @$testCond, qw/TestNumber TestName Units PINS/;

my $sbr = $td->SBR;
my $sbr_each = $td->SBR_each;
my $good_count;

if($good_count eq "" or $good_count == 0)
{
        $good_count = $td->MRR->{GOOD_CNT};
}

if(@$sbr > 0)
{
	$sbins = $parser->sbr2bins( $td->SBR,$good_count );
}
elsif($sbr_each > 0)
{	
	$sbins = $parser->sbr2bins( $td->SBR_each,$good_count );
}

my $hbr = $td->HBR;
my $hbr_each = $td->HBR_each;

if(@$hbr > 0)
{
	$hbins = $parser->hbr2bins( $td->HBR, $good_count );
}
elsif($hbr_each > 0)
{	
	$hbins = $parser->hbr2bins( $td->HBR_each,$good_count );
}

my $sbinsTP = $parser->epdr2sbins( $tp->EPDR );
my $hbinsTP = $parser->epdr2hbinsV2( $tp->EPDR );
mergeHBins($sbins,$sbinsTP);
mergeHBins($hbins,$hbinsTP);

my $model = new_model({dataSource => 'FET'});

$model->header($header);

#get lotid from filename
my $fname = basename $infile;
my @fn_item = split /\_|\./,$fname;
my $lot = $fn_item[0];
   $lot = substr $lot, 0,10;
   $header->LOT($lot);

unless ($header->populateMeta){
	$wr->noMeta(1);
	$reglim_flg = "N";
};

#extract test code from filename
my $testMode;
my @tcode = &load_testflow_ref($site);
foreach my $code (@tcode) {
	my @item = `find $infile -type f -iname \"*${code}\.CPR*\"`;
	$testMode = $code if @item;
} 
INFO ("Test code in file = $testMode");

# Add test flow to program name and sandbox it if invalid
my $testFlowCode = &addTestFlowtoTP($model,$testMode,$site);
if ( $model->forSBflag == 1 ) {
         $wr->forSBox($model->forSBflag);
}
$testFlowCode = "_${testFlowCode}";

my $program = $header->PROGRAM;
if (length($program) > 35) {
	INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
	$wr->forSBox(1);
	$reglim_flg = "N";
	$program = substr($program, 1, 35);
}
$program = $program.$testFlowCode;
$program =~ s/\_$//g;
$header->PROGRAM($program);
$model->updateProgram;

# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);

foreach my $stdfWafer ( @{ $td->wafers } ) {
    	my $wafer = new_wafer;
    	$wafer->START_TIME( $header->START_TIME );
    	$wafer->END_TIME( $header->END_TIME );
    	my $waferNum = -1;
    	if ( defined $stdfWafer->WIR ) {
        	$waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
        	$wafer->number($waferNum);
        	if ( defined $stdfWafer->WIR->{START_T} and $stdfWafer->WIR->{START_T} > 1000000000 )
          	{
            		$wafer->START_TIME( $stdfWafer->WIR->{START_T} );
        	}
        	if ( defined $stdfWafer->WRR->{FINISH_T} and $stdfWafer->WRR->{FINITSH_T} > 1000000000 )
        	{
            		$wafer->END_TIME( $stdfWafer->WRR->{FINISH_T} );
        	}
    	}
	 
    	$wafer->tests($tests);
	$wafer->dies( $parser->res2dies_fet_sort( $stdfWafer->res, $tests ) );
    	$model->add( 'wafers', $wafer );

}

$model->sbins($hbins);    #load hbins as sbins
$model->hbins($hbins);
&normalizeToBaseUnit($model);
	
my $formatter = new_iff_formatter({
        model=>$model,
        writer => $wr
});

$formatter->relItems([qw/qpnumber devchar lotchar strname strduration atetemp datalogtype/]);
$formatter->printPar;


# Limits
#if ($reglim_flg eq "Y") {
#	if($model->isLimitNew){
#  		$model->buildLimit;
#  		$model->limit->conditionNames($testCond);
#  		$formatter->printLimit;
#  		$model->limit->input_file(basename $infile); 
#  		$model->limit->registerRefdb;
#	}
#}
#else {   # always generate but do not register limit if sandbox
	$model->buildLimit;
	$model->limit->conditionNames($testCond);
	$formatter->printLimit;
	$model->limit->input_file(basename $infile);
#}

unless (isLogDebug) {
    	unlink $TD_bin;
    	unlink $TD_txt;
    	unlink $TP_bin;
    	unlink $TP_txt;
}

sub mergeHBins{
        my $bins = shift;
        my $binsTP = shift;
        my %binName;
        for my $bin (@$binsTP) {
                $binName{ $bin->number } = $bin->name;
        }
        for my $bin (@$bins) {
                $bin->name( $binName{ $bin->number } );
        }
}


dpExit(0);
