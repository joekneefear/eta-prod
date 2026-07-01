#!/usr/bin/env perl_db
# SVN $Id: fcs_stdf_advantest_IFF.pl 2603 2020-10-07 03:57:15Z dpower $

=pod

=head1 SYNOPSIS

  fcs_stdf_IFF.pl <Input flie name>
      --out <output dir>  same dir as input file by default
      [--finallot]
      [--logfile <logfilepath>]  
      [--debug|--trace]
      [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will read BSTDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/03/09 kazukik	: Modify to use standard Meta Lookup format to standard
 2015/04/21 kazukik	: get Bin PF from PRR
 2015/05/29 grace  	: get SBin and HBin when SITE_NUM=255
 2015/05/29 grace  	: Added support for -v option.
 2015/05/29 grace  	: Added function normalizeToBaseUnit
 2015/06/02 grace  	: changed calling function from "updateBinPF" to "updatehBinPF" for hbin
 2015/06/12 grace  	: set value for input_file of PP_LIMITS
 2015/06/22 grace  	: changed dataSource from 'STDF' to 'ADVAN'
 2015/06/25 jgarcia 	: added support to cater passed in site as an argument.
 2015/06/25 jgarcia 	: split lotid from the file to lotid and test flow code and added the test flow code in the Program name.
 2015/06/25 jgarcia 	: checked for the mode appropriate test flow code to append in Program name and determine if for sandbox loading based on test flow code
	using the TestFlowCodeUtiltiy module[For HANA] .
 2015/06/25 jgarcia 	: placed the statement to confirm wmap config inside an if statement if FINALLOT to make sure the iff file generated
 	will NOT be placed into stage_sanbox if wmap info is not confirmed as there will be no wmap config to confrm for FT data .
 2015/06/25 jgarcia 	: create a model constructor at the top and initialize forSBflag and dataSource.
 2015/07/02 jgarcia 	: added to accept location in LOC as a required argument and assign the value to EQUIP6_ID.
 2015/07/13 jgarcia 	: moved updateProgram after updateWMap, sanbox if no entry in pp_wmap.
 2015/07/13 jgarcia 	: added to support to accept config args.
 2015/07/13 jgarcia 	: modified to support FT and Sort advantest datalogs.
 2015/07/16 jgarcia 	: to support for the program name changes. 
 2015/09/01 jgarcia 	: modified to support sort advantest datalog loading.
 2015/09/08 jgarcia 	: modified how test flow code will be appended in Program name.  removed prefixed underscore.
 2015/09/08 jgarcia 	: added amkor_tw_csp site.
 2015/09/30 jgarcia 	: added supprot -> failed the datalog and send a copy to /data/pmsort_advan if datalog from pmft_advan have WIR record.
 2015/11/19 eric    	: always generate but do not register limit if sandbox
 2016/01/29 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2016/04/14 eric    	: added utac_th_ft site
 2016-May-05 gilbert	: Removed dot character in lotid - amkor_tw_csp
 2016-Jun-02 eric   	: added options for atec data loading
 2016-Jun-16 eric   	: added options for mesort data loading
 2016-Jun-16 eric   	: added options for rel data loading
 2016-Jul-7 eric    	: corrected how rel lot were parsed, emptied dtype contains [0-9], emptied strdur & temp if contains [a-z]
 2017-Mar-7 eric    	: Fail & do not create iff if no test param and test results
 2017-Mar-17 eric   	: assign source lot as wafer name
 2017-Mar-22 eric   	: set wafer flag for pplogging
 2017-Apr-18 jgarcia	: modified to support pp_logging even if issues encountered in converting binary to ascii format.
 2017-Apr-18 jgarcia	: modified to support pp_logging when generated an malformed stdf ascii derrived from binary.
 2017-May-10 gilbert	: generate always a limits and dont register to refdb.
 2017-Jul-03 carmilo	: added condition to use other parser for pmft_advan, sbr2bins_v2
 2018-Jan-11 eric   	: parse ONRMS datalogs
 2019/08/09 eric     	: added nosandbox option. its purpose was not to move the file to sandbox when envoke
 2020-Jan-8 Karen	: added new site Huatian
 2020/09/01 karen       : added support to fork and qde output (IFF)/files to designated location
 2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

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
use PDF::Util::TestFlowCodeUtility qw/getTestFlowCodeMode/;
use IO::File; 
use File::Copy qw(copy);
use v5.10;
use PPLOG::PPLogger; 	# wsanopao:
use Number::Range;
use Config::Tiny;

no warnings qw/experimental::lexical_subs experimental::smartmatch/;

our $VERSION = "

1.0
";
our $TESTER  = "ADVAN";

# a hash to receive options
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

my $testFlowCode = "";
my $testMode = "";
my $mode = "";
my $sandBoxFlag = "0";
my $lotid = "";
my $location = "";
my $site = "";
my $isSort = "N";
my $reglim_flg = "Y";
my $pmSortAdvanStagingDir = "/data/pmsort_advan/";


# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions, "OUT=s", "SITE=s", "FORK=s", "LOC=s", "FACILITYFILE=s", "CONFIG=s", "FINALLOT", "RELLOT", "LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG", "NOSANDBOX", "QDE"
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

my @required_options = qw/OUT SITE LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
$location = $hOptions{LOC};
my $facility = "";
if($hOptions{FINALLOT}) {
        $facility = $config->{$location}->{finalTest};
} else {
 $facility = $config->{$location}->{probe};
}
INFO("FACILITY|EQUIP6_ID=$facility");

$site = $hOptions{SITE};
unless ( grep { $_ eq $site } qw/merel_advan mesort_advan hana_th_ft cpsort_advan amkor_tw_csp pmsort_advan pmft_advan utac_th_ft atec_ph_ft huatian_cn_sort/ ) {
    dpExit( 1, "wrong site code : $site" );
}
INFO("Site code = $site");

# check input file
my $infile = $ARGV[0];
if ( !-f $infile ) {
    pod2usage(3);
}
my $advanFile = $infile;

# wsanopao: Set Raw File ==> infile and Environment ==> $site._eagle
$PPlogger->setRawFile($infile);
$PPlogger->setEnv($site,'advan');
my ($errLot,$errWafer) = getLotWafer($infile);
INFO("ERRLOT=$errLot||ERRWAFER=$errWafer");
### check if site is pmft_advan ###
if ($site eq 'pmft_advan' || $site eq 'atec_ph_ft') {
	my $tdTxt = convertBinToAscii($infile);
	if($tdTxt =~ /Failed to convert.+/i) {
        	#$pplogger->setWaferFlag(1);
		#$header2->LOT($lotid);
		#$header2->populateMeta();
		$PPlogger->setLot($errLot);
		#$pplogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum("00");
		dpExit(1, "$tdTxt");
     	}
	
	$isSort = &checkWIRrecord($tdTxt);
	if($isSort eq "Y") {
		unlink $tdTxt;
		dpExitError($site);
	} 
}

#my $model = new_model;
my $header  = new_headerLong;
my $header2 = new_headerLong->new();
my $wmap = new_wmap;
my $model  = new_model(
	{ header => $header,
		wmap   => $wmap,
		dataSource => 'ADVAN',
		forSBflag => ''
	}
	);

# create Writer
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   basename => ( basename $infile),
        ext      => 'iff',
        outdir   => $hOptions{OUT},
	forkdir => $hOptions{FORK},
	qde => $hOptions{QDE},
	gzipIFF  => 'Y'
    }
);

my $TD_txt = convertBinToAscii($infile);
if($TD_txt =~ /Failed to convert.+/i) {
	$PPlogger->setLot($errLot);
	if ($site =~ /mesort.+|cpsort.+|pmsort.+|amkor_tw_csp/) {
		$header2->LOT($errLot);
		$header2->populateMeta();
		$PPlogger->setWaferFlag(1);
		$PPlogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum($errWafer);
	} else {
		$PPlogger->setWafNum("00");
	}
  dpExit(1, "$TD_txt");
}
my $td = readStdfAscii($TD_txt);
if($td =~ /NO_.+/i) {
	$PPlogger->setLot($errLot);
	if ($site =~ /mesort.+|cpsort.+|pmsort.+|amkor_tw_csp/) {
		$header2->LOT($errLot);
		$header2->populateMeta();
		$PPlogger->setWaferFlag(1);
		$PPlogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum($errWafer);
	} else {
		$PPlogger->setWafNum("00");
	}
  dpExit(1, "$td");
}
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());
# create parser
my $parser = PDF::Parser::Stdf::Generic->new;

$header  = new_headerLong->new( $parser->stdf2header($td) );
#hm
my $mir                = $td->MIR;
#$header->PROGRAM($mir->{TEST_COD} . $mir->{SPEC_NAM});
INFO("SPEC_NAM :$mir->{SPEC_NAM}");
INFO("TEST_COD :$mir->{TEST_COD}");
my $program = uc($mir->{TEST_COD} . $mir->{SPEC_NAM});
$header->EQUIP6_ID($facility);
$header->CFG_TESTER_TYPE($hOptions{CONFIG});
$header->isFinalLot( $hOptions{FINALLOT} );
$header->isRelLot($hOptions{RELLOT} );

## initialize program class based on finallot arg value ###
if($hOptions{FINALLOT} || $hOptions{RELLOT}) {
	$header->PROGRAM_CLASS(2);
}else {
	$header->PROGRAM_CLASS(1);
}

$lotid = $header->{LOT};

#seperated even if same logic, just in case in the future there will be differences then it is easy to implement.
given($site) {
	when('hana_th_ft') {
		INFO("LOTID>>$lotid");
		($lotid, $testFlowCode) = split('_', $lotid);
		INFO("$lotid\t$testFlowCode");
		($testMode, $mode, $sandBoxFlag) = getTestFlowCodeMode($site, $testFlowCode, $model->{dataSource});
		#$testMode = "_${testMode}";
		$model->forSBflag( $sandBoxFlag );
		$header->INDEX1($testMode);
		$header->INDEX2($mode);
		$header->LOT(uc($lotid));
		#$header->PROGRAM($program);
	}
	when('utac_th_ft') {
		my $file = basename($infile);
		my @item = split('_', $file);
		INFO("$item[1]\t$item[2]");
		($testMode, $mode, $sandBoxFlag) = getTestFlowCodeMode($site, $item[2], $model->{dataSource});
		$model->forSBflag( $sandBoxFlag );
		$header->INDEX1($testMode);
		$header->INDEX2($mode);
		$header->LOT(uc($item[1]));
	}
	when('amkor_tw_csp') {
		my $lotid = $header->LOT;
		INFO("LOTID>>$lotid");
		$lotid =~ s/\.//g;
		$header->LOT(uc($lotid));
	}
	when('atec_ph_ft') {
		#do nothing
	}
	when('mesort_advan') {
		$header->PRODUCT(uc($header->PRODUCT));
	}
	when('merel_advan') {
                $header->PRODUCT(uc($header->PRODUCT));
        }
}

# Capture Rel Attributes
if ($hOptions{RELLOT}){
        my $base_fn = basename($infile);
           $base_fn =~ s/\.STDF.*+//ig;
        my @item    = split /\_/, $base_fn;
        my $qpnum   = $item[0];
        my $devchar;
        my $lotchar;
        my $strname;
        my $strdur;
        my $temp;
        my $dtype;
	my $req_id;

        if ($site eq "merel_advan") {
		$strname = $item[1];
                $strdur = $item[2];
                $temp = $item[3];
                $dtype = $item[4];
                $dtype = "" if $dtype =~ /[0-9]/;	
		if ( $qpnum =~ /^20/) {		
                	$qpnum = substr $item[0], 0, 8;
                	$devchar = substr $item[0], 8, 1;
                	$lotchar = substr $item[0], 9, 1;
			$header->LOT($qpnum.$devchar.$lotchar);		
		}
		elsif ($qpnum =~ /^W/) {
			$qpnum = substr $item[0], 0, 6;
			$req_id = $item[0];
			$lotchar = substr $item[0], 6, 1;
			$header->LOT($req_id);
		}
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
	
	#$header->LOT($qpnum.$devchar.$lotchar);
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

# Check Program length for > 35.  Truncate and send to sandbox.
if ( grep { $_ eq $site } (qw/hana_th_ft/) ) {
	my $tM = "_${testMode}";
	if ( length($program) + length($tM) > 35 )
	{
	        INFO("PROGRAM NAME \"".$program.$tM."\" will be truncated to 35 characters.  Sending to sandbox.");
	        $wr->forSBox(1);
		$reglim_flg = "N";
	        $program = substr($program, 1, 35-length($tM)); # Leave enough room for session type
	}
	$program = "${program}${tM}";
} else {
	if ( length($program) > 35 )
	{
	        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
	        $wr->forSBox(1);
		$reglim_flg = "N";
	        $program = substr($program, 1, 35); # Leave enough room for session type
	        		
	}
}
$program =~ s/\_$//g; ### remove trailing underscore at the end if have.

$header->PROGRAM($program);
#$header->isFinalLot( $hOptions{FINALLOT} );

unless ( $header->populateMeta ) {
    	#$wr->noMeta(1);
	if (!($hOptions{NOSANDBOX})) {
		$wr->noMeta(1);
	}
	else {
		WARN("File was not sandboxed. Argument was enabled.");
	}
    	$reglim_flg = "N";
}

$model->header($header);
$PPlogger->setModelHeader($model);
###check if the model's forSBflag instance variable is equal to 1 or true. trigger the writer to output the iff file to the sanbox folder
if($model->{forSBflag} == 1) {
	$wr->forSBox(1);
	$reglim_flg = "N";
	if($site eq 'hana_th_ft') {
		INFO ("For SandBox loading because of Test Flow");
	}
}

my $sbr = $td->SBR;
my $sbr_each = $td->SBR_each;

if(@$sbr > 0)
{
	if ($site eq 'pmft_advan') {
		$sbins = $parser->sbr2bins_v2($td->SBR);
	}else {
		$sbins = $parser->sbr2bins( $td->SBR );
	}
}
elsif($sbr_each > 0)
{	
	if ($site eq 'pmft_advan') {
		$sbins = $parser->sbr2bins_v2($td->SBR);
	} else {
		$sbins = $parser->sbr2bins( $td->SBR_each );
	}
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
	my $tests;
    	$wafer->START_TIME( $header->START_TIME );
    	$wafer->END_TIME( $header->END_TIME );
    	my $waferNum = -1;
    	if ( defined $stdfWafer->WIR ) {
        	$waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
        	$wafer->number($waferNum);
		# assign source lot as wafer name
		if(!($hOptions{FINALLOT}) && !($hOptions{RELLOT}) && $header->SOURCE_LOT ne "") {
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
    	}

	if ($location eq "ATEC_PH")
	{
		$tests = $parser->res2testsV2( $stdfWafer->res );
	}
	else {
		$tests = $parser->res2tests( $stdfWafer->res );
	}	
    	$wafer->tests($tests);
    	$wafer->dies( $parser->res2dies( $stdfWafer->res, $tests ) );
    	$model->add( 'wafers', $wafer );
}

$model->sbins($sbins);
$model->hbins($hbins);
$model->wmap($wmap);

# Fail the file and do not create iff 
my $stats = $model->wafers->[0]->stats;
if ( $stats->{deviceCount} == 0 ){
        dpExit( 1, "Zero devices to create IFF (".$stats->{deviceCount}.")");
}
if ( ! (@{$model->wafers->[0]->tests})) {
        dpExit(1, "Test Parameters not found.");
}

&normalizeToBaseUnit($model);

if(!($hOptions{FINALLOT}) && !($hOptions{RELLOT})) {
	my $wmap = $model->updateWMap;
	if(defined $wmap)   {
		INFO("MAP IS DEFINED");
		unless ( !$wmap->isEmpty ){
			#$wr->wmapIsEmpty(1);
			if (!($hOptions{NOSANDBOX})){
				$wr->wmapIsEmpty(1);
			}
			else {
				WARN("File was not sandboxed. Argument was enabled.");
			}
			$reglim_flg = "N";
		}
		unless ( $wmap->confirmed ) {
			#$wr->noWMap(1);
			if (!($hOptions{NOSANDBOX})){
				$wr->noWMap(1);
			}
			else {
				WARN("File was not sandboxed. Argument was enabled.");
			}
			$reglim_flg = "N";
		}
	}
	else{
		INFO("MAP IS NOT DEFINED");
		$wmap = new_wmap;	
    		#$wr->wmapIsEmpty(1) unless ( !$wmap->isEmpty );
		#$wr->noWMap(1);
		#$reglim_flg = "N";
		unless ( !$wmap->isEmpty ){
                        if (!($hOptions{NOSANDBOX})){
                                $wr->wmapIsEmpty(1);
                        }
                        else {
                                WARN("File was not sandboxed. Argument was enabled.");
                        }
                        $reglim_flg = "N";
                }
                unless ( $wmap->confirmed ) {
                        if (!($hOptions{NOSANDBOX})){
                                $wr->noWMap(1);
                        }
                        else {
                                WARN("File was not sandboxed. Argument was enabled.");
                        }
                        $reglim_flg = "N";
                }
		$model->wmap($wmap);	
	}
}


### Use program naming rule
if ($hOptions{FINALLOT} || ($hOptions{RELLOT})){
	$model->updateProgram;
}
else {
	$model->updateProgram("MAP_PGM");
}


my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);
$formatter->dataItems([qw/x y site partid hard_bin soft_bin/]);
$formatter->printPar;

# Limits
#if ($reglim_flg eq "Y") {
#	if ( $model->isLimitNew ) {
#		$model->buildLimit;
#    		$formatter->printLimit;
#		$model->limit->input_file(basename $infile); 
#    		$model->limit->registerRefdb;
#	}
#}
#else {  # always generate but do not register limit
	$model->buildLimit;
	$formatter->printLimit;
	$model->limit->input_file(basename $infile);
#}

unlink $TD_txt unless (isLogDebug);



dpExit(0);

sub checkWIRrecord {
    	my $file = shift;
    	my $isSort = "";
    	my $num = 0;
    	open FH, "<", $file or dpExit(1,"failed to open file. $file");
    	INFO("STDF(Ascii): $file");
    	my $table = "";
    
    	while (<FH>) {
        	$num++;
        	if (/^\t(\S+) :\tREC_LEN=(\d+)$/) {
           		$table = $1;
       	 	}
		if ( $table eq 'WIR' ) {
           		$isSort = "Y";
        	 	last;
        	}
        	else {
        		$isSort = "N";
        	}
    	}
	close (FH);
    	return $isSort;
 }
 
sub dpExitError {
    	my $message = shift;
	my $site = shift;
	if ( $site eq 'pmft_advan' ) {
        	copy $advanFile, $pmSortAdvanStagingDir . ( basename $advanFile);
    		dpExit(1,"Not a Final Test data - file sent to pmsort_advan environment.");
	}
	else {
		dpExit(1,"Not a Final Test data.");
	}
}

sub getLotWafer() {
	my $file = shift;
	my ($lotid,$waferid) = "";
	
	my $script_name = "$Bin/stdf_perl/script/stdf_copy ${file} | grep LOT_ID | tr '\n' ','; echo";
  open FH, "$script_name|";
  my @ret = <FH>;
  close(FH);
  chomp($ret[0]);
  my ($item1, $item2) = split /\s*\,\s*/, $ret[0] if $ret[0] ne "";
  $item1 =~ s/^\s+|\s+$//g;
  my($junk,$prd_lot) = split /=/,$item1;
  
  $lotid = $prd_lot;
  
  my $script_name = "$Bin/stdf_perl/script/stdf_copy ${file} | grep WAFER_ID | tr '\n' ','; echo";
  open FH, "$script_name|";
  my @ret = <FH>;
  close(FH);
  chomp($ret[0]);
  my ($item1, $item2) = split /\s*\,\s*/, $ret[0] if $ret[0] ne "";
  $item1 =~ s/^\s+|\s+$//g;
  my($junk,$wafer) = split /=/,$item1;
  
  $waferid = $wafer;
  
  return ($lotid,$waferid);

}
