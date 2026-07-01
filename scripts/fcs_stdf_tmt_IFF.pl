#!/usr/bin/env perl_db
# SVN $Id: fcs_stdf_tmt_IFF.pl 2588 2020-10-06 05:51:49Z dpower $

=pod

=head1 SYNOPSIS

  fcs_stdf_IFF.pl <Input flie name>
      --out <output dir>  same dir as input file by default
      --loc <location e.g. CP, ISTI_TW>
      --config<config_tester_type>
      [--nolookup]
      [--finallot]
      [--logfile <logfilepath>]  
      [--debug|--trace]
      [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will read STDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/03/09 kazukik: Modify to use standard Meta Lookup format to standard
 2015/04/21 kazukik: get Bin PF from PRR
 2015/05/13 grace  : add normalizeToBaseUnit, add desc for tests
 2015/05/13 grace  : to apply desc of tests for only stdf
 2015/05/29 grace  : Added support for -v option.
 2015/06/05 grace  : copy fdc_stdf_eagle_IFF.pl and changed  parameter name
					 delete x, y, site, program revision probe, dut board from tests
 2015/06/21 grace  : set value for input_file of PP_LIMITS
 2015/07/02 eric   : added LOC arg and pass it as EQUIP6_ID
 2015/07/10 eric   : use TP naming rule.
 2015/07/16 eric   : sandbox if ppid > 35.
 2015/09/02 gilbert: Customize for BK where to get testplan revision.
 2015/19/09 gilbert: Set revison to 5 as default if no test plan revison can be found inside the data file for SZ site.
 2015/21/09 gilbert: For CP get the test plan revision $ptr{1}{1}{result} if TEST_TXT=PROGREV and
                     wafer id in the file name.
 2015/15/10 Eric   : added arg option to bypass lot lookup
 2015/10/23 Eric   : peek into file to extract node_nam
 2015/11/18 Gilbert: For SZ the same process flow of getting test plan revision in BK but 
                     load to sandbox if all fails to get the revision
 2015/11/19 Eric   : always generate but do not register limit if sandbox	
 2015/11/23 Gilbert: Fixed bug in getting the wafer id if not found in MIR.LOT_ID
 2015/12/16 jgarcia: modified to try to matched for metadata where lotid last char is stripped. this is done after it failed on the first metadata check with NO Stripping to lotid.
 2015/12/16 jgarcia: added metastrip as an argument.
 2016/01/07 Rcyr   : Fixed bug resulting in wafer# 00 for some CP wafers.
 2016/01/29 wsanopao: logging pre-processing information to refdb.pp_log table.
 01-Mar-2016 Gilbert: BK site instead of failing, load to sandbox if all fails to get the revision.
                      If it failed because of No Test Plan revision delete thep TD_txt output file of stdf_copy.
 02-Jun-2016 Gilbert: Added ISTI_TW in METASTRIP.
 12-Jul-2016 Gilbert: Capturing test program revision in $ptr{1}{1}{result} if TEST_TXT=PROGREV
                     or PROGRAM REV to have it case insensitive
 03-Mar-2017 jgarcia: parse Lot and Wafer first from STDF V4 raw file.
 03-Mar-2017 jgarcia: modifed to not call dpExit if no TP revision. just assign N/A and load to sandbox.   
 03-Mar-2017 jgarcia: make sure to log lot, wafer, and env when dpExit will called to make sure lot and wafer will be persisted to refdb.pp_log.                  
 03-Mar-2017 jgarcia: modified to properly get the correct wafer from the file and properly sanitize it - for Cebu site.
 03-Mar-2017 jgarcia: modified for BK and SZ when waferid not available in WIR and in SBLOT_ID, check and get it from LOTID.
 03-Mar-2017 jgarcia: modified to assign endtime as TP revision when it is not available and load in Sandbox -> Cebu site.
 06-Mar-2017 gilbertm: Always generate limit but dont register.
 20-Mar-2017 eric   : assign source lot as wafer name.
 22-Mar-2017 eric   : set wafer flag for pplogging.
 24-Mar-2017 jgarcia: trap and force exit with logging if raw file processed have no test number parameter.
 24-Mar-2017  jgarcia : get source lot when raw file have issue which to be used in logging as wafer concatenated with wafer#.
 27-Jun-2017 gilbert: made adjustment for PM site.
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
 2023/07/21 rmsantillan : get erturl if facility is BK
 2023/08/2023 gmllego : Modified to add metastrip of LotId from GTK_TW and when waferid not available in WIR and in SBLOT_ID, check and get it from LOTID.
 2023/09/28 eric	: perform BK lot lookups by stripping characters
 2024/04/10 eric	: need to define data items to align data in exensio

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
my $site;
my $root_path = $ENV{'DPDATA'};

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
        	\%hOptions, "OUT=s","FORK=s", "LOC=s", "FACILITYFILE=s", "FACILITYFILE=s", "CONFIG=s", "FINALLOT", "LOGFILE=s",
		"NOLOOKUP", "DEBUG", "TRACE","V", "METASTRIP", "PPLOG"
    	)
    	)
{
    	dpExit( 1, "invalid options" );
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
}
# Initialize logging

my @required_options = qw/OUT LOC CONFIG FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $facility = $config->{$location}->{probe};
my $ertURL = $config->{$location}->{onLotProd};
INFO("FACILITY|EQUIP6_ID=$facility");

# check input file
my $infile = $ARGV[0];
if ( !-f $infile ) {
    	pod2usage(3);
}

# wsanopao: Set Raw File ==> infile
$PPlogger->setRawFile($infile);
if($hOptions{LOC} eq "CP") {
	$site = "cpsort_tmt";
	$PPlogger->setEnv($site);
	$PPlogger->setWaferFlag(1);
} elsif ($hOptions{LOC} eq "PM") {
	$site = "pmsort_tmt";
	$PPlogger->setWaferFlag(1);
	$PPlogger->setEnv($site);
} elsif ($hOptions{LOC} eq "BK") {
	$site = "bksort_tmt";
	$PPlogger->setWaferFlag(1);
	$PPlogger->setEnv($site);
} elsif ($hOptions{LOC} eq "SZ") {
	$site = "szsort_tmt";
	$PPlogger->setWaferFlag(1);
	$PPlogger->setEnv($site);
} elsif ($hOptions{LOC} eq "ISTI_TW") {
	$site = "isti_tw_sort_tmt";
	$PPlogger->setWaferFlag(1);
	$PPlogger->setEnv($site);
} elsif ($hOptions{LOC} eq "GTK_TW") {
        $site = "gtk_tw_sort";
        $PPlogger->setWaferFlag(1);
        $PPlogger->setEnv($site);
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

&loadSTDFV4Template();
my($lot,$wafer, $sblotid) = &getLotWaferFromSTDFV4RawFile($infile);
my $waferFromLot = "";
my $header2 = new_headerLong->new();
$header2->ertUrl($ertURL);

#INFO("LOT=$lot||WAFER=$wafer||SBLOT_ID=$sblotid");
if ($lot =~ /\_|-/) {
	my $dump = "";
	($lot,$waferFromLot) = split /\_|-/, $lot, 2;
}
if ($wafer eq "" || $wafer !~ /\d{1,}/) {
	if($hOptions{LOC} eq "BK" || $hOptions{LOC} eq "SZ" || $hOptions{LOC} eq "GTK_TW") {
		$wafer = $sblotid;
		if ($wafer eq "") {
			$wafer = $waferFromLot;
		}
	} else {
		if ($waferFromLot ne "") {
			$wafer = $waferFromLot;
		} else {
			my $f = basename($infile);
			my @waferArray = (split /_/, $f);
			$wafer = $waferArray[1];
			$wafer =~s/\_|\-//g;
			if ($wafer =~ /(\D|^)\d{1,2}(\D|$)/) {
				$wafer = $wafer;
			} else {
				$wafer = substr($wafer, 0, 2);
			}
		}
	}
}

INFO("LOT=$lot||WAFER=$wafer||SBLOT_ID=$sblotid");
my $TD_txt = convertBinToAscii($infile, $hOptions{DEBUG});

# peek into the file and look for node_nam type
my $node = "";
my $reglim_flg = "Y";

if($TD_txt ne "") {
	if($TD_txt =~ /Failed to convert.+/i) {
		$PPlogger->setLot($lot);
		if ($site =~ /.+sort.+/) {
			$PPlogger->setWaferFlag(1);
			$header2->LOT($lot);
			$header2->populateMeta();
			$PPlogger->setSourceLot($header2->SOURCE_LOT);
			$PPlogger->setWafNum($wafer);
		} else {
			$PPlogger->setWafNum("00");
		}
    dpExit(1, "$TD_txt");
  } else {
		open FH, $TD_txt; ##or die "can't open $TD_txt: $!\n";
		while(my $line = <FH>) {
			chomp($line);
			$line =~ s/\"|\cM//g;
			if ($line =~ /NODE_NAM=(.*)/) {
				$node = $1;
				INFO("NODE NAME = ".$node);
			}
			last if $node ne "";
		}
		close(FH);
	}
} else {
	#$PPlogger->setWaferFlag(1);
	$header2->LOT($lot);
	if ($hOptions{LOC} eq "BK" || $hOptions{LOC} eq "GTK_TW") {
		unless ( $header2->populateMeta() ){
			my $origLot = $header2->LOT;
			my $tempLot1 = $origLot;
			my $tempLot2 = $origLot;
			
			if ($tempLot1 =~ /^M0[a-zA-Z]/i && length($tempLot1) == 10 ) {
				INFO("Performing second lot lookup by replacing 3rd character with 0.");
				my $count = 3;
				$tempLot1 =~ s/(\w)/--$count == 0 ? "0":$1/ge;
				$header2->LOT($tempLot1);
				$header2->populateMeta();
			}
			elsif (length($tempLot1) > 8 && $tempLot1 =~ /^KG|^KH/i) {
				INFO("Performing second lot lookup using first 8 characters of KG|KH lots.");
				$tempLot1 = substr($tempLot1,0,8);
				$header2->LOT($tempLot1);
				unless ( $header2->populateMeta() ){
					INFO("Performing third lot lookup by stipping last character if KG|KH lots.");
					$tempLot2 = substr($tempLot2, 0, -1);
					$header2->LOT($tempLot2);
					$header2->populateMeta();		
				}
			}

			$header2->LOT($origLot);
			
		}
		#$PPlogger->setLot($lot);
		#$PPlogger->setSourceLot($header2->SOURCE_LOT);
		# $PPlogger->setWafNum($wafer);
		#dpExit(1,"Conversion from the raw binary STDF file to ASCII was NOT successfull!!!");
	} else {
		$header2->populateMeta();
	}
		$PPlogger->setLot($lot);
		$PPlogger->setSourceLot($header2->SOURCE_LOT);
	  	$PPlogger->setWafNum($wafer);
		dpExit(1,"Conversion from the raw binary STDF file to ASCII was NOT successfull!!!");
	
}



my $td;
if ($node =~ /^TS/i && $hOptions{LOC} eq "BK"){
	$td = readStdfAscii_bksort_tmt($TD_txt);
	if ($td =~ /NO_.+/i) {
		$PPlogger->setWaferFlag(1);
		$header2->LOT($lot);
		$header2->populateMeta();
		$PPlogger->setLot($lot);
		$PPlogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum($wafer);
		dpExit( 1, "$td" );
	}
}else {
	$td = readStdfAscii($TD_txt);
	if ($td =~ /NO_.+/i) {
		$PPlogger->setWaferFlag(1);
		$header2->LOT($lot);
		$header2->populateMeta();
		$PPlogger->setLot($lot);
		$PPlogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum($wafer);
		dpExit( 1, "$td" );
	}
}
#my $td     = readStdfAscii($TD_txt);
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());

# create parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $header  = new_headerLong->new( $parser->stdf2header($td) );
$header->ertUrl($ertURL);
my $program = $header->PROGRAM;

my @wk = split('-|_', $header->LOT);
   $wk[1] = "_".$wk[1] if $hOptions{LOC} ne "BK";
   $wk[1] = "_".$wk[1] if $hOptions{LOC} ne "SZ";
   $wk[1] = "_".$wk[1] if $hOptions{LOC} ne "GTK_TW";

$header->LOT($wk[0]);

($program, my $dump) = split /\./, $program;

if (length($program) + length($wk[1]) > 35) {
	INFO("PROGRAM NAME \"".$program.$wk[1]."\" will be truncated to 35 characters. Sending to sandbox.");
	$wr->forSBox(1);
	$reglim_flg = "N";
	$program = substr($program, 1, 35-length($wk[1])); #leave room for session type
}

$header->PROGRAM($program.$wk[1]) if $hOptions{LOC} ne "BK";
$header->PROGRAM($program.$wk[1]) if $hOptions{LOC} ne "SZ";
$header->PROGRAM($program.$wk[1]) if $hOptions{LOC} ne "GTK_TW";
$header->PROGRAM($program);
$header->PROGRAM_CLASS(1);
$header->EQUIP6_ID( $facility );
$header->CFG_TESTER_TYPE( $hOptions{CONFIG} );
$header->isFinalLot( $hOptions{FINALLOT} );

if ($header->REVISION eq "" && $hOptions{LOC} eq "BK"){
   	my $ref_file    = "ASL1000_TP_REV.DAT";
   	
   	my $ref_dir     = "${root_path}/data/bksort_tmt/TP";
   	if(! -e "${ref_dir}/${ref_file}") {
   		unless ( $header->populateMeta() ){
			my $origLot = $header->LOT;
			my $tempLot1 = $origLot;
			my $tempLot2 = $origLot;

			if ($tempLot1 =~ /^M0[a-zA-Z]/i && length($tempLot1) == 10 ) {
				INFO("Performing second lot lookup by replacing 3rd character with 0.");
				my $count = 3;
				$tempLot1 =~ s/(\w)/--$count == 0 ? "0":$1/ge;
				$header->LOT($tempLot1);
				$header->populateMeta();
			}
			elsif (length($tempLot1) > 8 && $tempLot1 =~ /^KG|^KH/i ) {
				INFO("Performing second lot lookup using first 8 characters of KG|KH lots.");
				$tempLot1 = substr($tempLot1,0,8);
				$header->LOT($tempLot1);

				unless ( $header->populateMeta() ){
					INFO("Performing third lot lookup by stipping last character if KG|KH lots.");
                                        $tempLot2 = substr($tempLot2, 0, -1);
                                        $header2->LOT($tempLot2);
                                        $header2->populateMeta();					
				}
			}

			$header->LOT($origLot);
		}

   	  	$PPlogger->setLot($header->LOT);

      		if ($wafer eq "") {
      			$wafer = $sblotid;
      		}

	      	$PPlogger->setSourceLot($header->SOURCE_LOT);
	      	$PPlogger->setWafNum($wafer);
	      	dpExit (1, "Test Plan reference file ${ref_dir}/${ref_file}:No such file or directory");
    	}

   	my $grep_tprev = `grep \^$program\, ${ref_dir}/${ref_file}`;
   	chomp($grep_tprev);
   	my ($testplan_name, $tprev) = split/\,/, $grep_tprev;

   	if ($grep_tprev eq ""){
     		WARN("Sending to Sandbox, Cant get Testplan Revision, assigning end_date as TP rev..");
		$wr->forSBox(1);
		$reglim_flg = "N";
		($tprev, $dump) = split /\s+/, $header->END_TIME;
		$tprev =~ s/\///g;
		$tprev = "0.".$tprev;
   	}
   	$header->REVISION($tprev);	
}
if ($header->REVISION eq "" && $hOptions{LOC} eq "SZ"){
   	my $ref_file    = "ASL1000_TP_REV_SZ.DAT";
   	my $ref_dir     = "${root_path}/data/szsort_tmt/TP";
   	if(! -e "${ref_dir}/${ref_file}"){
   		    $PPlogger->setWaferFlag(1);
      		$PPlogger->setLot($header->LOT);
      		if ($wafer eq "") {
      			$wafer = $sblotid;
      		}
      $header->populateMeta();
      $PPlogger->setSourceLot($header->SOURCE_LOT);
  		$PPlogger->setWafNum($wafer);
      dpExit (1, "Test Plan reference file ${ref_dir}/${ref_file}:No such file or directory");
   	}
   	my $grep_tprev = `grep \^$program\, ${ref_dir}/${ref_file}`;
   	chomp($grep_tprev);
   	my ($testplan_name, $tprev) = split/\,/, $grep_tprev;
   	if ($grep_tprev eq ""){
     		WARN("Sending to Sandbox, Cant get Testplan Revision, assigning end_date as TP rev..");
		$wr->forSBox(1);
		$reglim_flg = "N";
		($tprev, $dump) = split /\s+/, $header->END_TIME;
		$tprev =~ s/\///g;
		$tprev = "0.".$tprev;
   	}
   	$header->REVISION($tprev);	
}

# Lot lookup
if(!($hOptions{NOLOOKUP})){
	if (($hOptions{LOC} eq 'BK' || $hOptions{LOC} eq 'ISTI_TW' || $hOptions{LOC} eq 'GTK_TW') && $hOptions{METASTRIP}) {
		unless ( $header->populateMeta ){
			my $origLot = $header->LOT;
			my $tempLot1 = $origLot;
			my $tempLot2 = $origLot;

			if ($tempLot1 =~ /^M0[a-zA-Z]/i && length($tempLot1) == 10 ) {
				INFO("Performing second lot lookup by replacing 3rd character with 0.");
				my $count = 3;
				$tempLot1 =~ s/(\w)/--$count == 0 ? "0":$1/ge;
				$header->LOT($tempLot1);

				unless ( $header->populateMeta ){
					$wr->noMeta(1);
					$reglim_flg = "N";
				}
			}
			elsif (length($tempLot1) > 8 && $tempLot1 =~ /^KG|^KH/) {
				INFO("Performing second lot lookup using first 8 characters of KG|KH lots.");	
				$tempLot1 = substr($tempLot1,0,8);
				$header->LOT($tempLot1);

				unless ( $header->populateMeta ){
					INFO("Performing third lot lookup by stipping last character if KG|KH lots.");
					$tempLot2 = substr($tempLot2, 0, -1);
					$header->LOT($tempLot2);

					unless ( $header->populateMeta ){
						$wr->noMeta(1);
						$reglim_flg = "N";
					}							
				}
			}
			else {
				$wr->noMeta(1);
				$reglim_flg = "N";
			}

			$header->LOT($origLot);

		}
		
	} else {
		unless ( $header->populateMeta ) {
	    		$wr->noMeta(1);
			$reglim_flg = "N";
		}
  	}
}


my $model = new_model;
   $model->header($header);
   $model->dataSource('TMT');
my $wmap = $model->updateWMap;

if (defined $wmap) {
	unless ( ! $wmap->isEmpty ) {
		$wr->wmapIsEmpty(1);
		$reglim_flg = "N";
	}
	unless ( $wmap->confirmed ) {
		$wr->noWMap(1);
		$reglim_flg = "N";
	}
}
else {
	$wmap = new_wmap;
	$wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
	$wr->noWMap(1);
	$reglim_flg = "N";
	$model->wmap($wmap);
}

if ($location eq "BK") {
	$model->updateProgram("MAP_PGM_REV"); #add revision to program name
}
else {
	$model->updateProgram("MAP_PGM");
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
my @noneTestNumber;

foreach my $stdfWafer ( @{ $td->wafers } ) {
    	my $wafer = new_wafer;
    	$wafer->START_TIME( $header->START_TIME );
    	$wafer->END_TIME( $header->END_TIME );
    	my $mir = $td->MIR;
    	my $waferNum = -1;
    	if ( defined $stdfWafer->WIR ) {
		if($stdfWafer->WIR->{WAFER_ID} =~ /(\S+)-(\d{2})/){
			$waferNum = $2;
			$waferNum =~s/\_//g;
		}
		else{
			$waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
			$waferNum =~s/\_//g;
		}
	        
	       	$waferNum = "$wk[1]" if $hOptions{LOC} eq "BK"; 
		$waferNum =~s/\_//g;
		if ($hOptions{LOC} eq "SZ") {
			$waferNum = "$wk[1]";     
			$waferNum =~s/\_//g;
		}
		if ($waferNum eq "" && $hOptions{LOC} eq "BK" ) {
			$waferNum = $mir->{SBLOT_ID};
			$waferNum =~s/\_//g;
		}
		if ($waferNum eq "" && $hOptions{LOC} eq "SZ") {
			$waferNum = $mir->{SBLOT_ID};
			$waferNum =~s/\_//g;
		}
                $waferNum = "$wk[1]" if $hOptions{LOC} eq "GTK_TW";
                $waferNum =~s/\_//g;
                if ($hOptions{LOC} eq "GTK_TW") {
                        $waferNum = "$wk[1]";
                        $waferNum =~s/\_//g;
                }
                if ($waferNum eq "" && $hOptions{LOC} eq "GTK_TW" ) {
                        $waferNum = $mir->{SBLOT_ID};
                        $waferNum =~s/\_//g;
                }


		#INFO("wafer=".$waferNum);
		INFO("STDF_WAFER=".$stdfWafer->WIR->{WAFER_ID}) if $hOptions{LOC} ne "BK";
		INFO("STDF_WAFER=".$stdfWafer->WIR->{WAFER_ID}) if $hOptions{LOC} ne "SZ";
                INFO("STDF_WAFER=".$stdfWafer->WIR->{WAFER_ID}) if $hOptions{LOC} ne "GTK_TW";
		#INFO("wir=\"".$stdfWafer->WIR->{WAFER_ID}."\" get wafer number in MIR.LOT_ID|MIR.SBLOT_ID|FILE_NAME.");
		if ($waferNum eq "0" && ($hOptions{LOC} eq "CP" || $hOptions{LOC} eq "PM")) {
			my @file_path    = (split /\//, $infile);
			my @wafer_number = (split /_/, $file_path[$#file_path]);
			($waferNum, $dump)  = split /\./, $wafer_number[1];
			$waferNum =~s/\_|\-//g;
			if ($waferNum =~ /(\D|^)\d{1,2}(\D|$)/) {
				$waferNum = $waferNum;
			} else {
				$waferNum = substr($waferNum, 0, 2);
			}
				INFO("wafer=".$waferNum);
		}
	
	    	$wafer->number($waferNum);
	    	if ( defined $stdfWafer->WIR->{START_T} and $stdfWafer->WIR->{START_T} > 1000000000 ){
	            	$wafer->START_TIME( $stdfWafer->WIR->{START_T} );
	    	}
	    	if ( defined $stdfWafer->WRR->{FINISH_T} and $stdfWafer->WRR->{FINITSH_T} > 1000000000 ){
	            	$wafer->END_TIME( $stdfWafer->WRR->{FINISH_T} );
	    	}
	}
	else {
		if ($hOptions{LOC} eq "CP" || $hOptions{LOC} eq "PM") {
			my @file_path    = (split /\//, $infile);
			my @wafer_number = (split /_/, $file_path[$#file_path]);
			($waferNum, $dump)  = split /\./, $wafer_number[1];
			$waferNum =~s/\_|\-//g;
			if ($waferNum =~ /(\D|^)\d{1,2}(\D|$)/) {
				$waferNum = $waferNum;
			} 
			else {
				$waferNum = substr($waferNum, 0, 2);
			}
				INFO("wafer=".$waferNum);
				$wafer->number($waferNum);
			}
	}
	if ($waferNum eq "00") {
		$PPlogger->setWaferFlag(1);
		$PPlogger->setLot($lot);
  	$PPlogger->setWafNum($waferNum);
    dpExit (1, "Invalid wafer id: ${waferNum}");### if $waferNum eq "00";
	}
	
		
	#assign source lot as wafername
	if ($header->SOURCE_LOT ne "") {
		$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
		$PPlogger->setWaferFlag(1);
	}
	## wsbins
=pod	
    	if ( @{ $stdfWafer->WSBR } ) {
        	$wsbins = $parser->sbr2bins( $stdfWafer->WSBR );
    	}
		
    	if ( !defined $wsbins or !@$wsbins ) {
        	my $sbinHash = $parser->res2binHash( $stdfWafer->res );
        	foreach my $binNumber ( sort { $a <=> $b } keys %$sbinHash ) {
            		push @$wsbins, $sbinHash->{$binNumber};
        	}
    	}
    	else {
        	$wsbins = $parser->updateBinPF( $wsbins, $stdfWafer->res );
    	}
	
	## whbins	
	if ( @{ $stdfWafer->WHBR } ) {
        	$whbins = $parser->hbr2bins( $stdfWafer->WHBR );
    	}
	if ( !defined $whbins or !@$whbins ) {
        	my $hbinHash = $parser->res2hbinHash( $stdfWafer->res );
        	foreach my $binNumber ( sort { $a <=> $b } keys %$hbinHash ) {
            		push @$whbins, $hbinHash->{$binNumber};
        	}
    	}
    	else {
        	$whbins = $parser->updatehBinPF( $whbins, $stdfWafer->res );
    	}
=cut	
 	my $tests = $parser->res2tests( $stdfWafer->res );
	my $revision = undef;
	my $probeCard = undef;
	my $dutBoard = undef;
	my @tests_new = undef;
	my $i = 0;
	foreach my $test (@$tests) {
		if($test->name =~ /,/){
			my @wk = split(',', $test->name);   ##### ex)  VCIN_PreOS_LK  , Bin 14
			$test->name($wk[0]);
		}
		if(trim($test->name) eq "X"){
			push @noneTestNumber, $test->number;
		}
		elsif(trim($test->name) eq "Y"){
			push @noneTestNumber, $test->number;
		}
		elsif(trim($test->name) eq "SITE"){
			push @noneTestNumber, $test->number;
		}
		elsif(trim($test->name) =~/Program Rev/i){			
			$revision = $test->number;
			push @noneTestNumber, $test->number;
		}
		elsif(trim($test->name) =~/PROGREV/i){			
			$revision = $test->number;
			push @noneTestNumber, $test->number;
		}
		elsif(trim($test->name) eq "Probe Card ID"){
			push @noneTestNumber, $test->number;
			$probeCard = $test->number;
		}
		elsif(trim($test->name) eq "Dut Board ID"){
			push @noneTestNumber, $test->number;
			$dutBoard = $test->number;
		}
		else {			
				
		}		
		
		$i++;
	}

	my $h_res = $stdfWafer->res;
	
	foreach my $ptr ( @{ $$h_res[0]->PTR } ) {
		if($ptr->{TEST_NUM} eq $revision){			
			$revision = $ptr->{RESULT};
			$header->REVISION($revision);
		}
		elsif($ptr->{TEST_NUM} eq $probeCard){			
			$probeCard = $ptr->{RESULT};
			$header->EQUIP3_ID($probeCard);
		}
		elsif($ptr->{TEST_NUM} eq $dutBoard){			
			$dutBoard = $ptr->{RESULT};
			$header->INDEX1($dutBoard);
		}		
	}
	
	my $tests_2 = undef;
	
	foreach my $test (@$tests){		
		if(! chkTestParameter($test->number))	{
			push @$tests_2 , $test;			
		}
	}	

    	$wafer->tests($tests_2);    
    	$wafer->dies( $parser->res2dies( $stdfWafer->res, $tests_2 ) );
    	$model->add( 'wafers', $wafer );
    	
			if($model->wafers->[0]->tests eq "") {
				#$PPlogger->setWaferFlag(1);
				$PPlogger->setLot($header->LOT);
				$PPlogger->setSourceLot($header->SOURCE_LOT);
  			$PPlogger->setWafNum($waferNum);
				dpExit(1, "Missing  TEST NUMBERS");
			}

}

if ($header->REVISION eq ""){
     	#unlink $TD_txt;
     	my ($tprev, $dump) = split /\s+/, $header->END_TIME;
 	$tprev =~ s/\///g;
	$tprev = "0.".$tprev;
     	$header->REVISION($tprev);
     	$wr->forSBox(1);
     	INFO("No Testplan revision, assigned endTime \"$tprev\" as a Testplan revision. For Sandbox loading.");
     	#dpExit (1, "No Test Plan revision");
}

$model->sbins($sbins);
$model->hbins($hbins);

	&normalizeToBaseUnit($model);


my $formatter = new_iff_formatter(
    	{   model  => $model,
    	    writer => $wr
    	}
);

$formatter->dataItems([qw/x y site partid hard_bin soft_bin/]);
$formatter->testItems([qw/number name units/]);
$formatter->printPar;

# Limits
#if ($reglim_flg eq "Y") {
#	if ( $model->isLimitNew ) {
#	    $model->buildLimit;
#	    $formatter->printLimit;
#	    $model->limit->input_file(basename $infile); 
#	    $model->limit->registerRefdb;
#	}
#}
#else { # always generate but do not register limit if sandbox
	$model->buildLimit; 
	$formatter->printLimit;
	$model->limit->input_file(basename $infile);
#}

unlink $TD_txt unless (isLogDebug);

# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);

dpExit(0);


sub chkTestParameter
{
	my $testnum = shift;	
	my $result = 0;
	foreach my $tn (@noneTestNumber){
		if($tn eq $testnum){
			$result = 1;
		}		
	}
	
	return $result;

}
