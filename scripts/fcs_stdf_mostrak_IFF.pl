#!/usr/bin/env perl_db
# SVN $Id: fcs_stdf_mostrak_IFF.pl 2618 2020-10-08 05:32:49Z dpower $

=pod

=head1 SYNOPSIS

  fcs_stdf_IFF.pl <Input flie name>
      --out <output dir>  same dir as input file by default
      --loc <location e.g. SZ,CP,BK>
      [--finallot]
      [--logfile <logfilepath>]  
      [--debug|--trace]
      [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will read BSTDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/03/09 kazukik: Modify to use standard Meta Lookup format to standard
 2015/04/21 kazukik: get Bin PF from PRR
 2015/05/13 grace  : add normalizeToBaseUnit, add desc for tests
 2015/05/13 grace  : to apply desc of tests for only stdf
 2015/05/29 grace  : Added support for -v option.
 2015/06/05 grace  : remove desc from testitem for output
 2015/06/10 grace  : Copy fcs_stdf_IFF.pl to fcs_stdf_mostrak_IFF.pl
 2015/06/21 grace  : set value for input_file of PP_LIMITS
 2015/06/22 grace  : to reverse the polarity of the upper limit and result value for these tests
 2015/06/26 eric   : uncomment section to check if limit is new.
 2015/07/02 eric   : added LOC arg and pass it as EQUIP6_ID.
 2015/07/07 rodney : Don't do wmap lookup if finallot.
 2015/08/20 gilbert: If program name > 35 truncate and send to sandbox. Set PROGRAM_CLASS 
 2015/11/19 eric   : always generate but do not register limit if sandbox
 2015/11/20 eric   : prefixed family_id to ppid.
 2016/02/16 wsanopao: logging pre-processing information  to refdb.pp_log table.
 2016/07/08 eric   : added options for rel data loading
 2017/03/12 eric   : do create iff if no test results and/or parameters
 2017/05/30 gilbert : generate limits always and dont register in refdb.pp_limits
 2018/01/11 eric   : parse ONRMS datalog
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
 2021/06/03 karen   : adding tmp_lot to fix the / that where added in limit and iff files.

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
use PDF::DpData::Base;
use PDF::Parser::Stdf;
use PDF::Parser::Stdf::Generic;
use PDF::Formatter;
use PDF::DpWriter;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao: 
use Number::Range;
use Config::Tiny;

our $VERSION = "

1.0
";
our $TESTER  = "Stdf";

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
        \%hOptions, "OUT=s", "FORK=s", "LOC=s", "FACILITYFILE=s", "FINALLOT", "RELLOT", "LOGFILE=s", "DEBUG", "TRACE","V", "PPLOG"
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

my @required_options = qw/OUT LOC FACILITYFILE/;
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

my $header2 = new_headerLong->new();

# check input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    pod2usage(3);
}

# create Writer
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   basename => ( basename $infile),
        ext      => 'iff',
        outdir   => $hOptions{OUT},
			forkdir => $hOptions{FORK},
			gzipIFF  => 'Y'
    }
);

my ($lot, $wafer) = &getLotWafer($infile);

my $TD_txt = convertBinToAscii($infile);
if($TD_txt =~ /Failed to convert.+/i) {
  	if (!($hOptions{FINALLOT})) {
  		$pplogger->setWaferFlag(1);
  	}
  
		$header2->LOT($lot);
		$header2->populateMeta();
		$pplogger->setLot($lot);
		$pplogger->setSourceLot($header2->SOURCE_LOT);
		if (!($hOptions{FINALLOT})) {
  		$pplogger->setWafNum($wafer);
  	} else {
  		$pplogger->setWafNum("00");
  	}
		
		dpExit(1, "$TD_txt");
}
my $td     = readStdfAscii($TD_txt);
  if ($td =~ /NO_.+/i) {
		if (!($hOptions{FINALLOT})) {
  		$pplogger->setWaferFlag(1);
  	}
		$header2->LOT($lot);
	  $header2->populateMeta();
	  $pplogger->setLot($lot);
	  $pplogger->setSourceLot($header2->SOURCE_LOT);
		if (!($hOptions{FINALLOT})) {
  		$pplogger->setWafNum($wafer);
  	} else {
  		$pplogger->setWafNum("00");
  	}
	  dpExit( 1, "$td");
	}
my $reglim_flg = "Y";
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());

# create parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $header  = new_headerLong->new( $parser->stdf2header($td) );
my $program = $header->PROGRAM;
   $program = basename $program;
my $mir = $td->MIR;
my $family = $mir->{FAMILY_ID};
   $program = $family."-".$program;
my $tmp_lot = $header->LOT;
   $tmp_lot =~ s/[\n\$\%\^\&\*\{\}\[\]\|\!\~\/\`\<\>\:\;\"\,\'\\]//sg;
   $header->LOT($tmp_lot);
 
# Check Program length for > 35.  Truncate and send to sandbox.
if ( length($program) > 35 )
{
  	INFO("PROGRAM NAME \"$program\" will be truncated to 35 characters.  Sending to sandbox.    ");
  	$wr->forSBox(1);
  	$reglim_flg = "N";
  	$program = substr($program, 1, 35); # Leave enough room for session type
}
$header->PROGRAM($program);
$header->PROGRAM_CLASS(2);
$header->REVISION($mir->{SPEC_VER});
$header->EQUIP6_ID($facility);
$header->isFinalLot( $hOptions{FINALLOT} );
$header->isRelLot( $hOptions{RELLOT} );

my $model = new_model;
   $model->header($header);
   $model->dataSource('MSTRK');

# do if RELLOT
if ($hOptions{RELLOT}){
	my $base_fn = basename($infile);
        $base_fn    =~ s/\.STD.*+//ig;
        my @item    = split /\_|\./, $base_fn;
        my $qpnum;
        my $devchar;
        my $lotchar;
        my $strname = uc($item[1]);
        my $strdur = $item[2];
        my $temp = $item[3];
        my $dtype = uc($item[4]);
           $dtype = "" if $dtype =~ /[0-9]/;

 	if ($item[0] =~ /^20/) {
		$qpnum = substr $item[0], 0, 8;
		$devchar = uc(substr $item[0], 8, 1);
		$lotchar = uc(substr $item[0], 9, 1);
		$header->LOT($qpnum.$devchar.$lotchar);
	}
	elsif ($item[0] =~ /^U/i){
		$qpnum = substr $item[0], 0, 6;
		$lotchar = uc(substr $item[0], 6, 1);
		$header->LOT($qpnum.$lotchar);
	}

        my $range = Number::Range->new("0..1000000");
        if ( $range->inrange($strdur) && $strdur !~ /\D/) {
                #do nothing
        }
        else {
                WARN ("Stress Duration not in range =  $strdur");
                $strdur = "" if $strdur =~ /[a-z]/i;
                $wr->forSBox(1);
                $reglim_flg = "N";
        }
        my $range = Number::Range->new("-1000000..1000000");
        if ( $range->inrange($temp) && $temp !~ /\D/) {
                #do nothing
        }
        else {
                WARN ("ATETemp not in range = $temp");
                $temp = "" if $temp =~ /[a-z]/i;
                $wr->forSBox(1);
                $reglim_flg = "N";
        }

        $header->INDEX1($strname."_".$strdur."_".$temp."_".$dtype);

        my $rel = new_rel;
        $rel->qpnumber($qpnum);
        $rel->devchar($devchar);
        $rel->lotchar($lotchar);
        $rel->strname($strname);
        $rel->strduration($strdur);
        $rel->atetemp($temp);
        $rel->datalogtype($dtype);
        $model->add('rels', $rel);
}

unless ( $header->populateMeta ) {
    $wr->noMeta(1);
    $reglim_flg = "N";
}

#my $model = new_model;
#   $model->header($header);
#   $model->dataSource('MSTRK');
$model->updateProgram;

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

#unless ( $hOptions{FINALLOT} && $hOptions{RELLOT} ) {
#    my $wmap = $model->updateWMap;
#    unless ( $wmap->confirmed ) {
#        $wr->noWMap(1);
#	$reglim_flg = "N";
#    }
#}

if (!($hOptions{FINALLOT}) && !($hOptions{RELLOT})) {
        my $wmap = $model->updateWMap;
        unless ( ! $wmap->isEmpty ){
                $wr->wmapIsEmpty(1);
                $reglim_flg = "N";
        }
        unless ( $wmap->confirmed ){
                $wr->noWMap(1);
                #$reglim_flg = "N";
        }

}

my $sbins;
my $hbins;

my $sbr = $td->SBR;
my $sbr_each = $td->SBR_each;

if(@$sbr > 0)
{
	$sbins = $parser->sbr2bins( $td->SBR );
}
elsif($sbr_each > 0)
{	
	$sbins = $parser->sbr2bins( $td->SBR_each );
}

my $hbr = $td->HBR;
my $hbr_each = $td->HBR_each;

if(@$hbr > 0)
{
	$hbins = $parser->hbr2bins( $td->HBR );
}
elsif($sbr_each > 0)
{	
	$hbins = $parser->hbr2bins( $td->HBR_each );
}

my $str_limit;

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

    	my $tests = $parser->res2tests( $stdfWafer->res );
	my $tests_tsr = $parser->res2tests_tsr( $td->TSR );

	###  update tests name	
	foreach my $test (@$tests) {
		if($test->{name} =~ "")
		{		
			my $testname = getNameTsr($test->{number}, $tests_tsr);
			
			if($testname =~ /IGSS|IDSS/i){			
				if( $test->{HSL} <0){
					$test->HSL($test->{HSL} * -1);
					$test->desc("reverse polarity value for Mostrak");
				}	
				if( $test->{HOL} <0){
					$test->HOL($test->{HOL} * -1);
					$test->desc("reverse polarity value for Mostrak");
				}					
			}
			
			$test->name ($testname);
		}		
	}	
		
    	$wafer->tests($tests);
    	$wafer->dies( $parser->res2dies( $stdfWafer->res, $tests ) );
    	$model->add( 'wafers', $wafer );
}

$model->sbins($sbins);
$model->hbins($hbins);

# do not create iff 
my $stats = $model->wafers->[0]->stats;
if ( $stats->{deviceCount} == 0 ){
	
	dpExit( 1, "Zero devices to create IFF (".$stats->{deviceCount}.")");
}
if ( ! (@{$model->wafers->[0]->tests})) {
	dpExit(1, "Test Parameters not found.");
}
	
&normalizeToBaseUnit($model);

my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);

$formatter->testItems([qw/number name units /]);
$formatter->dataItems([qw/x y site partid hard_bin soft_bin/]);
$formatter->printPar;

# Limits
#if ($reglim_flg eq "Y") {
#	if ( $model->isLimitNew ) {
#    		$model->buildLimit;
#    		$formatter->printLimit;
#		$model->limit->input_file(basename $infile); 
#		$model->limit->registerRefdb;
#	}
#}
#else {   # always generate but do not register limit if sandbox
	$model->buildLimit;
	$formatter->printLimit;
	$model->limit->input_file(basename $infile);
#}

unlink $TD_txt unless (isLogDebug);

dpExit(0);

sub getNameTsr{
	my $testnum = shift;
	my $tests_tsr = shift;
	my $testnam = "";
	foreach my $test (@$tests_tsr) 
	{
		if($test->number eq $testnum)
		{
			$testnam = $test->name;
		}
	}
	
	return $testnam;
}

sub getLotWafer() {
	my $file = shift;
	my $lotid;
	my $waferid;
	
	#my $script_name = "$ENV{STDF_SCRIPT}/stdf_copy ${file} | grep LOT_ID | tr '\n' ','; echo";
	my $script_name = "$Bin/stdf_perl/script/stdf_copy ${file} | grep LOT_ID | tr '\n' ','; echo";
  open FH, "$script_name|";
  my @ret = <FH>;
  close(FH);
  chomp($ret[0]);
  my ($item1, $item2) = split /\s*\,\s*/, $ret[0] if $ret[0] ne "";
  $item1 =~ s/^\s+|\s+$//g;
  my ($junk,$lot) = split /=/,$item1;
  
  $lotid = $lot;
  
  my $script_name = "$Bin/stdf_perl/script/stdf_copy ${file} | grep WAFER_ID | tr '\n' ','; echo";
  open FH, "$script_name|";
  my @ret = <FH>;
  close(FH);
  chomp($ret[0]);
  my ($item1, $item2) = split /\s*\,\s*/, $ret[0] if $ret[0] ne "";
  $item1 =~ s/^\s+|\s+$//g;
  my ($junk,$wafer) = split /=/,$item1;
  
  $waferid = $wafer;
  
	return ($lotid, $waferid);
}
