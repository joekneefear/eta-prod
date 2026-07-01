#!/usr/bin/env perl_db
# SVN $Id: fcs_stdfv4_szsort_IFF.pl 2583 2020-10-06 01:45:56Z dpower $

=pod

=head1 SYNOPSIS

  fcs_stdf_szsort_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
      --loc <location>
      --config <config_tester_type>
      [--logfile <logfilepath>]  
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read STDFV4 file (Binary) and write to stdf like text file

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

2015/06/18 grace : new 
2015/06/21 grace : set value for input_file of PP_LIMITS
2015/06/26 grace : HBR has wrong pass bin count sometimes so, need to use raw data to calculate bin count by Scott 2015.06.26
2015/07/20 eric  : apply new ppid rules.
2015/11/19 eric  : always generate but do not register limit if sandbox
2016/02/26 wsanopao: logging pre-processing information  to refdb.pp_log table.
2016/05/23 eric	 : modified to load hbin summary intead of sbin to correct bin name issue 
2016/06/21 eric	 : load sbin summary from eprr/prr
2016/06/23 eric  : load sbin summary from wsbr
2017/03/20 eric  : assign source lot as wafer name
2017/03/22 eric  : set wafer flag for pplogging
2017/04/24 jgarcia: modified to support pp_logging even if issues encountered in converting binary to ascii format.
2017/04/24 jgarcia: modified to support pp_logging when generated an malformed stdf ascii derrived from binary.
2017-May-30 gilbert : generate limits always and dont register in refdb.pp_limits
2020/09/01 karen       : added support to fork output (IFF)/files to designated location
2021/04/07 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

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
use PDF::Parser::Stdf;
use PDF::Parser::Stdf::Generic;
use PDF::Formatter;
use PDF::DpWriter;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao: 
use Config::Tiny;

our $VERSION = "

1.0
";
our $TESTER  = "Stdf";

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
        	\%hOptions,  "OUT=s", "FORK=s", "LOC=s", "FACILITYFILE=s", "CONFIG=s",
        	"LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG"
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

my @required_options = qw/OUT LOC CONFIG FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $location = $hOptions{LOC};
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");

# check input file
my $infile = $ARGV[0];

my @dummy = split("/", $hOptions{LOC});
my $site = $dummy[1];

# wsanopao: Set Raw File ==> infile 
$PPlogger->setRawFile($infile);

if ( ! -f $infile ) {
    	ERROR("$infile does not exist");
    	pod2usage(3);
}


# create Writer
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
	{   	basename => ( basename $infile),
	       	ext      => 'iff',
	        outdir   =>  $hOptions{OUT},
		forkdir => $hOptions{FORK},
		gzipIFF  => 'Y'
	}
);

&loadSTDFV4Template();
my($lot,$wafer, $sblotid) = &getLotWaferFromSTDFV4RawFile($infile);
my $waferFromLot = "";
my $header2 = new_headerLong->new();

# create Parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $perl = "perl";
my $reglim_flg = "Y";
my ( $TP_bin, $TD_bin );

# Convert source file to TP and TD
my $command = "$perl -I/export/home/dpower/project/scripts/stdf_perl/lib /export/home/dpower/project/scripts/stdf_perl/conv_stdf4.pl -infile=$infile -env_mod=/export/home/dpower/project/scripts/stdf_perl/env_mod_mtsort_sz.pm";
INFO("$command ");
my @output = `$command`;
if ($?) {
    	#print "error in $command\n";
    	$PPlogger->setLot($lot);
    	if ($site =~ /sort/) {
    		$PPlogger->setWaferFlag(1);
    		$header2->LOT($lot);
    		$header2->populateMeta();
    		$PPlogger->setSourceLot($header2->SOURCE_LOT);
	  		$PPlogger->setWafNum($wafer);
    	}else {
    		$PPlogger->setWafNum("00");
    	}
     	dpExit( 1, "Failed to convert $command : $!" );
}
if ( $output[-1] =~ /td=(.*) tp=(.*)/ ) {
    	$TD_bin = $1;
    	$TP_bin = $2;
    	INFO("TD=$TD_bin");
    	INFO("TP=$TP_bin");
}
else {
			$PPlogger->setLot($lot);
    	if ($site =~ /sort/) {
    		$PPlogger->setWaferFlag(1);
    		$header2->LOT($lot);
    		$header2->populateMeta();
    		$PPlogger->setSourceLot($header2->SOURCE_LOT);
	  		$PPlogger->setWafNum($wafer);
    	}else {
    		$PPlogger->setWafNum("00");
    	}
    	dpExit( 1, "Failed to convert $command : " . join( "#", @output ) );
}

my $TD_txt = convertBinToAscii($TD_bin);
if($TD_txt =~ /Failed to convert.+/i) {
	$PPlogger->setLot($lot);
	if ($site =~ /sort/) {
		$PPlogger->setWaferFlag(1);
		$header2->LOT($lot);
		$header2->populateMeta();
		$PPlogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum($wafer);
	} else {
		$PPlogger->setWafNum("00");
	}
 	dpExit(1, "$TD_txt");
}
my $TP_txt = convertBinToAscii($TP_bin);
if($TP_txt =~ /Failed to convert.+/i) {
	$PPlogger->setLot($lot);
	if ($site =~ /sort/) {
		$PPlogger->setWaferFlag(1);
		$header2->LOT($lot);
		$header2->populateMeta();
		$PPlogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum($wafer);
	} else {
		$PPlogger->setWafNum("00");
	}
 	dpExit(1, "$TP_txt");
}
my $td     = readStdfAscii($TD_txt);
if ($td =~ /NO_.+/i) {
	$PPlogger->setLot($lot);
	if ($site =~ /sort/) {
		$PPlogger->setWaferFlag(1);
		$header2->LOT($lot);
		$header2->populateMeta();
		$PPlogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum($wafer);
	} else {
		$PPlogger->setWafNum("00");
	}
 	dpExit(1, "$td");		
}
my $tp     = readStdfAscii($TP_txt);
if ($tp =~ /NO_.+/i) {
	$PPlogger->setLot($lot);
	if ($site =~ /sort/) {
		$PPlogger->setWaferFlag(1);
		$header2->LOT($lot);
		$header2->populateMeta();
		$PPlogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum($wafer);
	} else {
		$PPlogger->setWafNum("00");
	}
 	dpExit(1, "$tp");		
}
my $good_count;
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());
my $header = new_headerLong->new( $parser->stdf2header($td) );

unless ( $header->populateMeta ) {
    	$wr->noMeta(1);
    	$reglim_flg = "N";
}

my $testCond = [qw/PIN_1 PIN_2 PIN_3 SBIN_NUM HBIN_NUM
        VCC VEE TEMP FREQ PARMTYPE SEQ_NAME
        TCONDS SBIN_NAM HBIN_NAM TEST_TXT
        LOAD_VAL TEST_CAT VIEW_ORD /];
$parser->testConditions_EPDR( $testCond);
my $tests = $parser->epdr2tests( $tp->EPDR );
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

my $model = new_model({dataSource => 'SZ'});

$header->EQUIP3_ID($td->EMIR->{SUPR_NAM});
$header->EQUIP6_ID( $facility );
$header->CFG_TESTER_TYPE( $hOptions{CONFIG} );

$model->header($header);

# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);

my $program = $header->PROGRAM;
if (length($program) > 35) {
	INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters. Sending to sandbox.");
	$wr->forSBox(1);
	$reglim_flg = "N";
	$program = substr($program, 1, 35); #leave room for session type
}
$header->PROGRAM($program);
$header->PROGRAM_CLASS(1);

my $wmap = $model->updateWMap;

if(defined $wmap)   {
	unless ( $wmap->confirmed ) {
		$wr->noWMap(1);
		$reglim_flg = "N";
	}
}
else{
	$wmap = new_wmap;	
	$wr->noWMap(1);
	$reglim_flg = "N";
	$model->wmap($wmap);	
}

$model->updateProgram("MAP_PGM");

foreach my $stdfWafer ( @{ $td->wafers } ) {
    	my $wafer = new_wafer;
	my @whbr_arr = ();
    	$wafer->START_TIME( $header->START_TIME );
    	$wafer->END_TIME( $header->END_TIME );
    	my $waferNum = -1;
    	if ( defined $stdfWafer->WIR ) {
        	$waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
        	$wafer->number($waferNum);
		#assign soure lot as waferid
		if ($header->SOURCE_LOT ne "") {
			$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
			$PPlogger->setWaferFlag(1);
		}
        	if ( defined $stdfWafer->WIR->{START_T} and $stdfWafer->WIR->{START_T} > 1000000000 )
        	{
            		$wafer->START_TIME( $stdfWafer->WIR->{START_T} );
        	}
        	if ( defined $stdfWafer->WRR->{FINISH_T} and $stdfWafer->WRR->{FINITSH_T} > 1000000000 )
        	{
            		$wafer->END_TIME( $stdfWafer->WRR->{FINISH_T} );
        	}
		if(defined $stdfWafer->WRR->{GOOD_CNT})
		{
			$good_count =  $stdfWafer->WRR->{GOOD_CNT};
		}		
    	}	
	# get hbins from eprr/prr
        if ( !defined $whbins or !@$whbins ) {
                my $binHash = $parser->res2hbinHash( $stdfWafer->res );
                foreach my $binNumber ( sort { $a <=> $b } keys %$binHash ) {
                        push @$whbins, $binHash->{$binNumber};
                }
        }
	# get sbins from wsbr 
	if ( @{$stdfWafer->WSBR} ) {
                $wsbins = $parser->sbr2bins( $stdfWafer->WSBR,$good_count );
        }
        if ($whbins ne "")
        {
                $wafer->hbins($whbins);
        }
	if ($wsbins ne "")
        {
                $wafer->sbins($wsbins);
        }
	
    $wafer->tests($tests);
    $wafer->dies( $parser->res2dies( $stdfWafer->res, $tests ) );
    $model->add( 'wafers', $wafer );
}


&normalizeToBaseUnit($model);
	
my $formatter = new_iff_formatter({
        model=>$model,
        writer => $wr});
$formatter->dataItems([qw/x y site partid hard_bin soft_bin/]);
$formatter->printPar;

# Limits

#if($model->isLimitNew){
  	$model->buildLimit;
  	$model->limit->conditionNames($testCond);
  	$formatter->printLimit;
  	$model->limit->input_file(basename $infile); 
  	#$model->limit->registerRefdb if ($reglim_flg eq "Y");
#}

unless (isLogDebug) {
    unlink $TD_bin;
    unlink $TD_txt;
    unlink $TP_bin;
    unlink $TP_txt;
}

sub updateBinName{
	my $bin = shift;
	my $wbin = shift;
	my %binName;
	
	foreach my $wk (@$bin){
		$binName{ $wk->number } = $wk->name;		
	}
	
	foreach my $wk (@$wbin){
		$wk->name($binName{$wk->number});
	}
}

sub mergeBins{
  	my $bins = shift;
  	my $binsTP = shift;
  	my %binName;
  	for my $bin (@$binsTP) {
    		$binName{ $bin->number } = $bin->name;
		INFO("binstp : ".$bin->number.",".$bin->name);
  	}
  	for my $bin (@$bins) {
  		INFO("bins : ".$bin->number.",",$bin->name);
    		$bin->name( $binName{ $bin->number } );
  	}
}

sub getBinSummary{
  	my $bin = shift;
  	my $bin_each = shift;
  	my $g_cnt = shift;
  	my $mode = shift;
  	my $bins;
  
  	if(@$bin > 0)
  	{
		if($mode eq "sbr"){
			$sbins = $parser->sbr2bins( $bin, $g_cnt );
		}else{
			$hbins = $parser->hbr2bins( $bin, $g_cnt );
		}	
  	}
  	elsif(@$bin_each > 0)
  	{	
		if($mode eq "sbr"){
			$sbins = $parser->sbr2bins( $bin_each, $good_count );
		}else{
			$hbins = $parser->hbr2bins( $bin_each, $good_count );
		}
  	}
}

dpExit(0);

