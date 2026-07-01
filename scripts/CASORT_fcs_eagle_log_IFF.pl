#!/usr/bin/env perl_db
# SVN $Id: fcs_eagle_log_IFF.pl 2272 2018-01-11 00:36:40Z dpower $

=pod

=head1 SYNOPSIS

  fcs_eagle_lot_IFF.pl <Input flie name>
      	--site [szft|mtsort|pmsort|pmft|isti_tw_csp]
      	--loc <location e.g CP, SZ, ME>
      	--config <cfg_tester_type>
      	--finallot
      	--out <output dir>
        --facilityfile <$DPSCRIPT/facilityMapping.ini>
      	[--logfile <logfilepath>]
      	[--nolookup]
      	[--debug|--trace]
  	[-V Display version ID]
	[--pplog]

=head1 DESCRIPTIONS

B<This script> will read eagle log file and generate IFF file for dbascii

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2014/05/19 edwardy	: initial script. Parse FCS log file
 2015/03/04 kazukik	: Modify output format to standard IFF
 2015/03/09 kazukik	: Modify output format to standard IFF
 2015/04/09 kazukik	: use data model
 2015/04/20 ericalf	: added new site conditions for pmft and added new site cpft & hana_th_ft
 2015/04/20 jgarcia	: added new site >>gtk_tw_sort<<.
 2015/04/20 jgarcia	: used TestLimitNorm.pm utility module to normalize units[calling normalizeToBaseUnit subroutine and passing $model as an argument].
 2015/04/20 jgarcia	: exract digit after - in source lot as waferid for gtk_sort_tw.
 2015/04/29 ericalf	: added new site gtk_tw_ft
 2015/05/01 jgarcia	: modified to check for wmap reference data only if it is not FT LOT, to avoid iff being generated to 
 			stage_sanbox out folder and cannot be loaded to Prod even if Meta data found in FT reference table.
 2015/05/01 jgarcia 	: modified hana_th_ft to strip out test flow on the lotid and concatenate it in the Program name separated by an underscore.
 2015/05/04 ericalf	: improved parsing of data when extracting from filename cpft & gtk_tw_ft
 2015/05/07 ericalf	: added sites cpsort, szsort, bksort, mesort, slsort
 2015/05/08 ericalf	: added sites amkor_tw_csp
 2015/05/13 ericalf	: added sites utac_th_ft and improve parsing rec 145
 2015/05/15 ericalf	: fixed wafer id parsing for site cpsort, szsort, bksort, mesort, slsort
 2015/05/21 ericalf	: modified gtk_tw_ft to sandbox other test code conditions
 2015/05/22 ericalf	: modified hana_th_ft,utac_th_ft,isti_tw_csp,amkor_tw_csp to sandbox other test code conditions, added site atec_ph_ft, etrend_tw_ft
 2015/05/29 grace  	: Added support for -v option
 2015/06/01 eric   	: Added site aic_my_ft, meft, vgrd_tw_sort
 2015/06/04 eric   	: Use AddFlowCodetoTP module
 2015/06/04 eric   	: Parse rec 145 if exists for utac and slsort
 2015/06/04 eric   	: Use AddTestFlowtoTPUsingRef module
 2015/06/10 eric   	: get lotid from filename for gtk_tw_ft
 2015/06/21 grace  	: set value for input_file of PP_LIMITS
 2015/06/22 eric   	: extract probecard and loadboard for cpsort
 2015/06/24 grace  	: added hbin 
 2015/06/30 gilbert	: Set EQUIP6_ID value to site e.g CP, SZ and etc.
 2015/06/30 gilbert	: Set EQUIP6_ID value to site e.g CP, SZ and etc. by accepting arguments from the .cfg file
 2015/07/01 gilbert	: Added --config <cfg_tester_type>
 2015/07/01 sboothby	: Don't create an IFF if the file contains no results.
 2015/07/02 eric   	: Use new program naming rule.
 2015/07/14 jgarcia	: new program name modification.
 2015/07/16 sboothby	: Add _FT and _QA to Penang and Suzhou program names as needed.  Strip chars from UTAC after and including the underscore.
 2015/07/16 sboothby	: Match where Cebu lot contains source lot and wafer info and strip from lot ID.
 2015/07/16 sboothby	: Strip .NNN from end of SZ lot ID.  Get UTAC lot from sublot unless it's in the 145 record.
 2015/09/11 eric    	: parse correct lotid for etrend_tw_ft and gtk_tw-sort
 2015/09/22 gilbert 	: gunzip file. 
 2015/10/05 gilbert 	: removed the .gz on iff file creation.
 2015/10/15 eric    	: added arg option to bypass lot lookup
 2015/11/19 eric    	: always generate but do not register limit if sandbox
 2015/12/16 jgarcia	: modified to try to matched for metadata where lotid last char is stripped. this is done after it failed 
 			on the first metadata check with NO Stripping to lotid.
 2015/12/16 jgarcia	: added metastrip as an argument.
 2016/01/16 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2016/03/08 jgarcia 	: populate default data for WMAP section when wmap object is empty and site is bksort.
 2016/03/09 jgarcia 	: populate default data for WMAP section when wmap object is empty and site is cpsort or mesort or szsort.
 2016-Mar-14 gilbert	: send to sandbox if wrong package type instead of failing.
 2016-Mar-16 gilbert	: atec_ph_ft_eagle: capture loadborad and trim lot.
 2016-Mar-17 rcyr   	: Send to sandbox if mesort and pkg type is "P".
 2016-Apr-04 gilbert 	: Disabled the flag reglim_flg to N at WMAP Data portion.
 2016-Apr-26 eric	: added new site merel for REL loading
 2016-May-10 eric	: append orig program name to program in merel.
 2016-May-11 eric	: merel :check stress duration/temp is in rage, removed attributes in program name, 
   			: increase program name char limit from 35 to 43.
 2016-May-12 gilbert    : remove the dot character and characters after the - in the lotid for Amkor TW only
 2016-May-12 eric	: added options for rel data loading
 2016-May-16 gilbert    : added cprel_eagle
 2016-May-31 eric	: added szrel
 2016-Jul-07 eric	: corrected bug when checking if atetemp & strdur in range (removed initialization)
 2016-Jul-07 eric	: emptied dtype contains [0-9], emptied strdur & temp if contains [a-z]
 2016-Jul-07 eric       : corrected how rel lotid were parsed
 2016-Jul-26 eric	: check, move & exit if file is an ets800 bin reference
 2016-Jul-29 eric	: utac_th_ft: perform second lot lookup using lot in filename.
 2016-Aug-05 eric	: removed checking if file is an ets800 bin reference
 2016-Aug-05 jgarcia 	: fail cpsort file which lot inside the file does not match the lot indicated in the filename.
 2016-Aug-10 gilbert    : Fail if 10 or less die tested
 2016-Aug-10 gilbert    : Fail if 10 or less die tested but not for Rel data
 2016-Aug-29 rodney     : For cpsort, added filename check for SL lots, changed Mtop lot check from 1st 2 chars to only 1st char.
 2016-Aug-30 eric	: moved checking number of results after all correct lotid has been extracted.
 2016-Sep-21 GilbertM   : Instead of Fail if 10 or less die tested it will be send to sandbox.
 2016-Oct-19 eric	: removed check sum codes in wafid for ISTI
 2016-Oct-24 eric	: fixed bug in matching lotid's in filename for cpsort.
 2016-Oct-25 eric	: don't generate limit if pass count = 0
 2016-Nov-21 eric	: remove rej|retest from lotid in szft.
 2016-Dec-06 eric	: dont generate & register limit file if all parts failed.
 2017-Feb-16 GilbertM   : Generate limits always for BK only.
 2017-Feb-22 GilbertM   : Generate limits always to all env and not register to refdb.
 2017-Mar-20 eric  	: pass site value to readFile function
 2017-Mar-27 eric	: assign source lot as wafer name
 			: capture error msgs during parsing for logging 
 2017-Apr-26 GilbertM   : added its_tw_ft_eagle
 2017-May-25 eric	: fix bug to assign source lot as wafer id only when source lot is available.
 2017-Jun-29 eric	: replace 3rd character with zero for ME lots sorted in BK
 2017-Nov-02 eric	: added casort environment
 2018-Dec-18 eric	: modifield rel env's to cater ONRMS data
 2021/03/25  glory      : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
 
=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Getopt::Long qw/:config ignore_case auto_help/;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename dirname/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Parser::CASORT_Eagle;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PDF::Util::AddTestFlowtoTPUsingRef qw/addTestFlowtoTP load_testflow_ref/;
use v5.10;
use PPLOG::PPLogger; 	# wsanopao: 
use Number::Range;
use Config::Tiny;


no warnings qw/experimental::lexical_subs experimental::smartmatch/;

our $VERSION = "

1.0
";
our $TESTER  = "EAGLE";

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
}
unless (
    GetOptions(
        \%hOptions,  "OUT=s", "SITE=s", "LOC=s", "FACILITYFILE=s", "FINALLOT", "V", "CONFIG=s",
         "RELLOT", "NOLOOKUP", "LOGFILE=s", "DEBUG", "TRACE", "METASTRIP", "PPLOG"
    )
    )
{
    dpExit( 1,"invalid options" );
    pod2usage(3);
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT SITE LOC FACILITYFILE/;
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


unless ( $hOptions{SITE} ) {
    dpExit( 1, "--site must be specified" );
    pod2usage(3);
}

unless ( $hOptions{LOC} ) {
    dpExit( 1, "--loc must be specified" );
    pod2usage(3);
}

my $site = $hOptions{SITE};
unless ( grep { $_ eq $site } qw/cpft szrel szft pmft merel meft aic_my_ft atec_ph_ft etrend_tw_ft hana_th_ft gtk_tw_ft utac_th_ft mtsort pmsort casort cpsort szsort slsort mesort bksort amkor_tw_csp isti_tw_csp its_tw_ft gtk_tw_sort vgrd_tw_sort cprel its_tw_ft/ ) {
    dpExit( 1, "wrong site code : $site" );
}
INFO("Site code = $site");


my $location     = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
my $reglim_flg = "Y";
my $allFail_flg = "N";

# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile and Environment ==> $site._eagle
$pplogger->setRawFile($infile);
$pplogger->setEnv($site,'eagle');

if ( !-f $infile ) {
    dpExit( 1, "input file does not exist $infile" );
}

my $output = $infile;
if ($infile =~ /\.gz$/) {
        $output =~ s/\.gz$//;
        gunzip $infile => $output or die "gunzip failed: $GunzipError\n";
        INFO ("gunzipped file = $output");
}

# check output dir
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        basename => ( basename $output),
        ext      => 'iff',
        gzipIFF  => 'Y'
    }
);

INFO("infile  = $infile");

my $parser = PDF::Parser::CASORT_Eagle->new;

my ($model, $sbox_flg) = $parser->readFile( $output,$site );
my $testMode ="";
my $code ="";
my $misc = $model->misc;
#print "===>${misc}\n";
#print "====$misc->{err_msg}\n";
   $wr->forSBox(1) if $sbox_flg == 1;
my $header = $model->header;
$header->VERSION($VERSION);
$header->isFinalLot( $hOptions{FINALLOT} );
$header->isRelLot( $hOptions{RELLOT} );
$header->EQUIP6_ID( "$facility" );

# Reliability variables
my $qpnum   = "";
my $devchar = "";
my $lotchar = "";
my $strname = "";
my $strdur  = "";
my $temp    = "";
my $dtype   = "";

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);



# normalize results
&normalizeToBaseUnit($model);

given ($site) {
    when ('pmsort') {
        my @item = @{ $misc->{'125_W'} };
	my @pkg = @{ $misc->{125} };
        my ( $loadBoard, $probeCard ) = split( /;/, $item[5] );
	trim($pkg[1]);
        if ( $pkg[1] eq "P" ) {
	   WARN("Wrong package type:$pkg[1]. Sending to sandbox .");
	   $wr->forSBox(1);
        }

        $header->EQUIP3_ID( trim($probeCard) );
        $header->EQUIP4_ID( trim($loadBoard) );
        $header->EQUIP5_ID( trim( $item[4] ) );

        @item = @{ $misc->{120} };
        $model->wafers->[0]->number( trim( $item[6] ) );
        
        my $lot = $header->LOT;
        $lot =~ s/\.//g;
        $lot =~ s/_//g;
        $header->LOT($lot);
        $header->PROGRAM_CLASS(1);
    }
    when ('mtsort') {
        my @item = @{ $misc->{'125_W'} };
        $header->EQUIP2_ID( trim( $item[4] ) );
        $header->EQUIP3_ID( trim( $item[6] ) );
        $header->EQUIP4_ID( trim( $item[5] ) );
        $header->EQUIP5_ID( trim( $item[4] ) );
        @item = @{ $misc->{120} };
        $model->wafers->[0]->number( trim( $item[6] ) );
        $header->PROGRAM( "EL" . $header->PROGRAM );
        $header->PROGRAM_CLASS(1);
    }
    when ('isti_tw_csp') {
        my @item = @{ $misc->{120} };
        (my $lot, $testMode) = split( /-/, $item[5] );
        my ($dummy, $wafer)    = split( /-/, $item[6] );
	my ($wafer, $dummy)    = split (/[A-Z]/i, $wafer );
 	$testMode =~ s/^\"|\"$//;
        $header->LOT( trim($lot) );
        $model->wafers->[0]->number( trim($wafer) );
        $header->PROGRAM_CLASS(1);
    }
    when ('its_tw_ft') {
        my @item = @{ $misc->{120} };
        (my $lot, $testMode) = split( /-/, $item[5] );
 	$testMode =~ s/^\"|\"$//;
        $header->LOT( trim($lot) );
        $header->PROGRAM_CLASS(2);
    }
    when ('amkor_tw_csp') {
	my @item_a = @{ $misc->{120} };
	my @item_b = @{ $misc->{'125_W'} } if ( exists $misc->{'125_W'} );
	(my $lot, $testMode) = split ( /-/, $item_a[5] );
	$testMode =~ s/^\"|\"$//;
        my $new_lot = $header->LOT;
           $new_lot =~ s/\.//g;
           $new_lot =~/(\-.*)/;
           $new_lot =~ s/$1//g;
           $header->LOT($new_lot);
	$header->EQUIP4_ID( trim($item_b[5]) );
	$model->wafers->[0]->number( trim( $item_a[6] ) );
	$header->PROGRAM_CLASS(1);	
    }	
    when ('pmft') {
	my $base_fn = basename($infile);
        my @item_a = @{ $misc->{125} };
	my @item_b = @{ $misc->{ghr_info} } if ( exists $misc->{ghr_info} );
        my $lot = $header->LOT;
        $lot =~ s/\.//g;
        $lot =~ s/_//g;
        $header->LOT($lot);
	if ( $base_fn =~ /QA_ETS/ )
	{
		$header->PROGRAM( $header->PROGRAM . "_QA" );
	}
	else
	{
		$header->PROGRAM( $header->PROGRAM . "_FT" );
	}
        $header->PROGRAM_CLASS(2);
	$item_a[5] = trim($item_a[5]);  ###remove qoutes
	my $loadBoard;
        my $probeCard;
	if ( $item_a[5] ne "" ) {
		( $loadBoard, $probeCard ) = split( /;/, $item_a[5] );
		$header->EQUIP3_ID( trim($probeCard) );
        	$header->EQUIP4_ID( trim($loadBoard) );
	}
	else {
		foreach my $addr (@item_b) {
		   ( my $dummy1, $loadBoard) = split( /:/, $addr ) if $addr =~ /Loadboard/i;
		   ( my $dummy2, $probeCard) = split( /:/, $addr ) if $addr =~ /Probecard/i;	 
		}
		$header->EQUIP3_ID( trim($probeCard) );
                $header->EQUIP4_ID( trim($loadBoard) ); 	
	}
    }
    when ('szft') {
        my $lot = $header->LOT;
        $lot =~ s/^AO/A0/;
        #$lot =~ s/rej//i;
	if ($lot =~ /REJ|RETEST/i) {
		$header->INDEX2("O");
		$reglim_flg = "N";
		$lot = substr($lot, 0, 10); #remove rej|retest appended at the end
	}
	# 16-Jul-2015 S. Boothby check lot ID for lot.NNN and strip .NNN
	if ( $lot =~ /^[[:ascii:]]{10}\.\d+$/ )
	{
		my ( $zer, $new_lot, $ext ) = split /^([[:ascii:]]{10})\.(\d+)$/, $lot;
		$lot = $new_lot;
	}
        $header->LOT( trim($lot) );
        $header->PROGRAM( "EGL_" . $header->PROGRAM );
        $header->PROGRAM_CLASS(2);
        my @item = @{ $misc->{ghr_info} } if ( exists $misc->{ghr_info} );   
	foreach my $addr (@item) {
        	$header->PROGRAM( $header->PROGRAM . "_FT" ) if $addr =~ /FT Station/i;
        	$header->PROGRAM( $header->PROGRAM . "_QA" ) if $addr =~ /QA Station/i;
	}
    }
    when ('szrel') {
        $header->PROGRAM_CLASS(2);
        my $base_fn = basename($infile);
           $base_fn =~ s/\.LOG.*+//ig;
        my @item = split /\_/, $base_fn;
	$strname = $item[2];
	$strdur = $item[3];
	$temp = $item[4];
	$dtype = $item[5];
	$dtype = "" if $dtype =~ /[0-9]/;

	if ($item[1] =~ /^20/) {
	        $qpnum = substr $item[1], 0, 8;
        	$devchar = substr $item[1], 8, 1;
        	$lotchar = substr $item[1], 9, 1;
		$header->LOT($qpnum.$devchar.$lotchar);
	}
	elsif  ($item[1] =~ /^U/) {
		$qpnum = substr $item[1], 0, 6;
		$lotchar = substr $item[1], 6, 1;
                $header->LOT($qpnum.$lotchar);	
	}

	$header->PROGRAM($item[0]);

        my $range = Number::Range->new("0..1000000");
        if ( $range->inrange($strdur) && $strdur !~ /\D/) {
                #do nothing
        }
        else {
                WARN ("Stress Duration not in range =  $strdur");
		$strdur = "" if $strdur =~ /[a-z]/i;
                $wr->forSBox(1);
        }
        my $range = Number::Range->new("-1000000..1000000");
        if ( $range->inrange($temp) && $temp !~ /\D/) {
                #do nothing
        }
        else {
                WARN ("ATETemp not in range = $temp");
		$temp = "" if $temp =~ /[a-z]/i;
                $wr->forSBox(1);
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
    when ('cpft') {
	my $base_fn = basename($infile);
        my @tmp_brd = split /\_|\./, $base_fn;
        my @item = @{ $misc->{ghr_info} } if ( exists $misc->{ghr_info} );   
        my $dut_cnt = 0;
        my $dut1    = "";
        my $dut2    = "";
        foreach my $brd (@tmp_brd) {
                $header->EQUIP4_ID( trim($brd) ) if $brd =~ /^FTFAM/i;
                $dut1 = $brd if $brd =~ /^FTPIZ/i && $dut_cnt == 0;
                $dut_cnt++ if $brd  =~ /^FTPIZ/i;
                $dut2 = $brd if $brd =~ /^FTPIZ/i && $dut_cnt > 1;
        }
        $header->INDEX1( trim($dut1) ) if $dut_cnt == 1;
        $header->INDEX1( join ("-", "${dut1}", "${dut2}") ) if $dut_cnt > 1;
        $header->PROGRAM( "EGL_" . $header->PROGRAM );
	foreach my $addr (@item) {
        	$header->PROGRAM( $header->PROGRAM . "_FT" ) if $addr =~ /FT Station/i;
        	$header->PROGRAM( $header->PROGRAM . "_QA" ) if $addr =~ /QA Station/i;
	}
        $header->PROGRAM_CLASS(2);
        # 16-Jul-2015 sboothby Sometimes lot is lot_srclot1-srcwf1_srclot2-srcwf2.  If so, get lot.
        if ($header->LOT =~ /^[[:alnum:]]+_[[:alnum:]]+-[[:digit:]]+_[[:alnum:]]+-[[:digit:]]+$/)
	{
		my ($start, $new_lot, $new_sl1, $new_sw1, $new_sl2, $new_sw2) = split /^([[:alnum:]]+)_([[:alnum:]]+)-([[:digit:]]+)_([[:alnum:]]+)-([[:digit:]]+)$/, $header->LOT;
		$header->LOT($new_lot);
	}
    }	
    when ('meft') {
	$header->PROGRAM_CLASS(2);
	my $base_fn = basename($infile);
	$base_fn =~ s/\.LOG.*+//ig;
	my @item = split /\_/, $base_fn;
	$header->LOT($item[0]);
    }
    when ('merel') {
	$header->PROGRAM_CLASS(2);
	my $base_fn = basename($infile);
   	$base_fn =~ s/\.LOG.*+//ig;
	my @item = split /\_/, $base_fn; 
	$strname = $item[1];
	$strdur = $item[2];
	$temp = $item[3];
	$dtype = $item[4];
	$dtype = "" if $dtype =~ /[0-9]/;
	if ($item[0] =~ /^20/) {
		$qpnum = substr $item[0], 0, 8;
		$devchar = substr $item[0], 8, 1;
		$lotchar = substr $item[0], 9, 1;
		$header->LOT($qpnum.$devchar.$lotchar);
        }
	elsif ($item[0] =~ /^W/i) {
		$qpnum = substr $item[0], 0, 6;
		$lotchar = substr $item[0], 6, 1;
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
	}
	my $range = Number::Range->new("-1000000..1000000");
	if ( $range->inrange($temp) && $temp !~ /\D/) {
                #do nothing
        }
        else {
		WARN ("ATETemp not in range = $temp");
		$temp = "" if $temp =~ /[a-z]/i;
                $wr->forSBox(1);
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
    when ('cprel') {
	$header->PROGRAM_CLASS(2);
	my $base_fn = basename($infile);
	   $base_fn =~ s/\.LOG.*+//ig;
	my @item    = split /\_/, $base_fn; 
	$strname = $item[1];
        $strdur  = $item[2];
        $temp    = $item[3];
        $dtype   = $item[4];
        $dtype   = "" if $dtype =~ /[0-9]/;

	if ($item[0] =~ /^20/ ) {
		$qpnum   = substr $item[0], 0, 8;
		$devchar = substr $item[0], -2, 1;
		$lotchar = substr $item[0], -1, 1;
		$header->LOT($qpnum.$devchar.$lotchar);		
	}
	elsif ($item[0] =~ /^F/i) {
		$qpnum = substr $item[0], 0, 6;
		$lotchar = substr $item[0], -1, 1;
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
	}
	my $range = Number::Range->new("-1000000..1000000");
	if ( $range->inrange($temp) && $temp !~ /\D/) {
                #do nothing
        }
        else {
		WARN ("ATETemp not in range = $temp");
		$temp = "" if $temp =~ /[a-z]/i;
                $wr->forSBox(1);
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
    when ('aic_my_ft') {
	$header->PROGRAM_CLASS(2);
    }
    when ('atec_ph_ft') {
	my $Lot = $header->LOT;
	($Lot, my $dump, $testMode)  = split /\_/, $Lot;
	trim($Lot);
	trim($testMode);
        my @item_a = @{ $misc->{125} };
        $header->PROGRAM_CLASS(2);
        my $loadBoard = $item_a[6] ;
        $header->EQUIP4_ID( trim($loadBoard) );
	$header->LOT($Lot);
    }
    when ('etrend_tw_ft') {
    	my $lot   = $header->LOT;
	   $lot   =~ s/\.LOG//ig;
	my @dummy = ();
	   @dummy = split /\_/, $lot;
	   if (length($dummy[0]) >= 5){
		$lot = $dummy[0];
	   }
	   else {
		for (my $i=1; $i<=$#dummy; $i++){
			if (length($dummy[$i]) >= 5){
				$lot = $dummy[$i];
				last;
			}
		}
	   }
	$header->LOT($lot);
	$header->PROGRAM_CLASS(2);
    }
    when ('hana_th_ft') {
    	  my $tempLot = $header->LOT;
    	  ($tempLot, $testMode)  = split /\_/, $tempLot;
    	  trim($tempLot);
    	  trim($testMode);
    	  $header->LOT($tempLot);
          $header->PROGRAM_CLASS(2);
    }
    when ('gtk_tw_ft') {
	my $mode;
	my ($lot, $fablot, $sublot, $duplicatelot) = ""; 
	my @dump1 = ();
	my @dump2 = ();
	my $dup_flg = 0;
        my %seen = ();
	my $base_fn = basename($infile);
	my @arr_fn = split /\_/, $base_fn;
        foreach my $str (@arr_fn) {
                next unless $seen{$str}++;
                $dup_flg = 1;
        }
        if ( $dup_flg == 1 ) {
		($lot, $fablot, $duplicatelot, $sublot, $testMode, @dump1) = split /\_/, $base_fn;
        }
        else {
		($lot, $fablot, $sublot, $testMode, @dump2) = split /\_/, $base_fn;
        }
	$header->LOT($lot);
        $header->PROGRAM_CLASS(2);
    }	
    when ('utac_th_ft') {
	my @item = @{ $misc->{ghr_info} } if ( exists $misc->{ghr_info} );
	# Get the test flow code from the UTAC lot before checking sublot for the lot we want.
	(my $dump, $testMode) = split /\_/, $header->LOT;
	my $orig_lot = $header->LOT;
	# 16-Jul-2015 use CUST-ASSY-LOT first, then sublot, then lot
	if ( $parser->sublot !~ /^<not specified>$/ )
	{
		$header->LOT( $parser->sublot );
	}
	trim($testMode);
	foreach my $addr (@item) {
	   if ( $addr =~ /CUST-ASSY-LOT/ ) {
		my ($fld, $lot) = split /\:/, $addr;
		$header->LOT( trim($lot) );
	   }
	   elsif ( $addr =~ /HANDLER\sID\sFOR\sSITE1/ ) {
		my ($fld, $handler) = split /\:/, $addr;
                $header->EQUIP5_ID( trim($handler) );
	   }		
	}	
        # Strip lot of everything after (and including) an undersore
        my ( $prelot, $junkk ) = split /\_/, $header->LOT;
	$header->LOT( trim($prelot) );
	$header->PROGRAM_CLASS(2);
    }
    when ('gtk_tw_sort') {
    	
        my @item = @{ $misc->{120} };
        my ( $dummy, $wafer_number ) = split( /-/, $item[6] );
        $model->wafers->[0]->number( trim( $wafer_number ) );
        
        my ($lot, $testMode) = split /\-/, $header->LOT;

        $header->LOT($lot);
        $header->PROGRAM_CLASS(1);
    }
    when ('cpsort') {
	my @pkg = @{ $misc->{125} };
	my @item = @{ $misc->{120} };
	my $baseFn = basename($infile);
	my $regex = $header->{LOT};
	if ($baseFn =~ /$regex/i ) {
		INFO ("Lotid: $header->{LOT} found a match in the filename");
	}	
	else {
		dpExit(1, "Lotid: $header->{LOT} is not found in the filename");
	}

	trim($pkg[1]);
	if ( $pkg[1] eq "P" ) {
	   WARN("Wrong package type:$pkg[1]. Sending to sandbox .");
	   $wr->forSBox(1);
	}
	my @brd = split /\D+/, $pkg[5];
	$model->wafers->[0]->number( trim( $item[6] ) );
	$header->EQUIP3_ID($brd[4]);
	$header->EQUIP4_ID($brd[1]);
	$header->PROGRAM_CLASS(1);
	
    }
    when ('szsort') {
	my @pkg = @{ $misc->{125} };
	my @item = @{ $misc->{120} };
	trim($pkg[1]);
	if ( $pkg[1] eq "P" ) {
	   WARN("Wrong package type:$pkg[1]. Sending to sandbox .");
	   $wr->forSBox(1);
        }
	$model->wafers->[0]->number( trim( $item[6] ) );
        $header->PROGRAM_CLASS(1);
    }	
    when ('mesort') {
	my @item_a = @{ $misc->{120} };
        my @item_b = @{ $misc->{125} };
	trim($item_b[1]);
	if ( $item_b[1] eq "P" ) {
	   WARN("Wrong package type:$item_b[1]. Sending to sandbox .");
	   $wr->forSBox(1);
	}
	my ( $loadBoard, $probeCard ) = split( /;/, $item_b[5] );
	$model->wafers->[0]->number( trim( $item_a[6] ) );
	$header->EQUIP3_ID( trim($probeCard) );
        $header->EQUIP4_ID( trim($loadBoard) );	
	$header->EQUIP5_ID( trim($item_b[4]) );
	$header->PROGRAM_CLASS(1);
    }	
    when ('bksort') {
	my @item_a = @{ $misc->{120} };
	my @item_b = @{ $misc->{125} };
	trim($item_b[1]);
	if ( $item_b[1] eq "P" ) {
	   WARN("Wrong package type:$item_b[1]. Sending to sandbox .");
	   $wr->forSBox(1);
        }
 	elsif ( $item_b[1] eq "W" ) {
	   trim($item_b[5]);
	   $item_b[4] =~ s/[^0-9a-z]//ig;	
	   $header->EQUIP3_ID( trim($item_b[6]) );
           $header->EQUIP4_ID( trim($item_b[5]) );	
	   $header->EQUIP5_ID( trim($item_b[4]) );
	}	
	$model->wafers->[0]->number( trim( $item_a[6] ) );
	
	$header->PROGRAM_CLASS(1);
    }	
    when ('slsort') {
	my @item_a = @{ $misc->{120} };
	my @item_b = @{ $misc->{ghr_info} } if ( exists $misc->{ghr_info} );
	foreach my $addr (@item_b) {
	   if ( $addr =~ /^PCARD/ ) {
	      $addr =~ s/^PCARD_//;
	      $header->EQUIP3_ID($addr);
	   }	
	}
	$model->wafers->[0]->number( trim( $item_a[6] ) );
	$header->PROGRAM_CLASS(1);
    }
    when ('vgrd_tw_sort') {
    	my @item = @{ $misc->{120} };
	$model->wafers->[0]->number( trim( $item[6] ) );
	$header->PROGRAM_CLASS(1);
    }
    when ('casort') {
        my @pkg = @{ $misc->{125} };
        my @item = @{ $misc->{120} };
        trim($pkg[1]);
        if ( $pkg[1] eq "P" ) {
           WARN("Wrong package type:$pkg[1]. Sending to sandbox .");
           $wr->forSBox(1);
        }
        $model->wafers->[0]->number( trim( $item[6] ) );
        $header->PROGRAM_CLASS(1);
    }
}


$header->CFG_TESTER_TYPE($cfg_tstr_typ);

#### Add test flow to TP and sandbox it if invalid 
my $testFlowCode = &addTestFlowtoTP($model,$testMode,$site);

INFO("TEST FLOW CODE : $testFlowCode");
$testFlowCode = "_${testFlowCode}";
INFO("PROGRAM NAME : $header->{PROGRAM}");
my $program = $header->{PROGRAM};

### For subcon or foundry that might have test flow code ###
if ( grep { $_ eq $site } (qw/gtk_tw_ft hana_th_ft atec_ph_ft isti_tw_csp its_tw_ft amkor_tw_csp etrend_tw_ft utac_th_ft aic_my_ft gtk_tw_sort vgrd_tw_sort/) ) {
	
	# Check Program length for > 35.  Truncate and send to sandbox.
	if ( length($program) + length($testFlowCode) > 45 )
	{
	    WARN("PROGRAM NAME \"".$program.$testFlowCode."\" will be truncated to 45 characters.  Sending to sandbox.");
	    $wr->forSBox(1);
	    $reglim_flg = "N";
	    $program = substr($program, 1, 45-length($testFlowCode)); # Leave enough room for testFlowCode
	        
	}
	$program = $program.$testFlowCode;
### For site (cebu, suzhou, maine etc..) which dont have test flow code ###
}else {
	
	if ( length($program) > 45 )
	{
	        WARN("PROGRAM NAME \"".$program."\" will be truncated to 45 characters.  Sending to sandbox.");
	        $wr->forSBox(1);
		$reglim_flg = "N";
	        $program = substr($program, 1, 45); # Leave enough room for session type
	        		
	}
}

$program =~ s/\_$//g; ### remove trailing underscore at the end.

$header->PROGRAM($program);
INFO("UPDATED PROGRAM NAME:>$header->{PROGRAM}<");

if ( $model->{forSBflag} == 1 ) {
	$wr->forSBox(1);
	$reglim_flg = "N";
}
### Lot lookup
if (!($hOptions{NOLOOKUP})) {
	#$wr->noMeta(1) unless ( $header->populateMeta );
	
	if ($hOptions{LOC} eq 'BK' && $hOptions{SITE} eq 'bksort' && $hOptions{METASTRIP}) {
		
		unless ( $header->populateMeta ){
			#INFO("Performing second lot lookup..");
			my $origLot = $header->LOT;
			my $tempLot = $origLot;

			if ($tempLot =~ /^M0[a-zA-Z]/i && length($tempLot) == 10 ) {
				INFO("Performing second lot lookup by replacing 3rd character with 0.");
				my $count = 3;  
				$tempLot =~ s/(\w)/--$count == 0 ? "0":$1/ge;
				$header->LOT($tempLot);
			}
			elsif ($tempLot !~ /^M0/) {
				INFO("Performing second lot lookup by stripping the last character.");
				$tempLot = substr($tempLot, 0, -1);
				$header->LOT($tempLot);
			}

			unless ($header->populateMeta) {
				$wr->noMeta(1);
			  	$reglim_flg = "N";
			}
			$header->LOT($origLot);
		}	
		
	} 
	elsif ($hOptions{LOC} eq 'UTAC_TH' && $hOptions{SITE} eq 'utac_th_ft' && $hOptions{METASTRIP}){
		unless ( $header->populateMeta ){
                        INFO("Performing second lot lookup using lot in filename..");
                        my $fn = basename($infile);
                        my @item = split /_/, $fn;
                        $header->LOT($item[1]);
                        unless ($header->populateMeta) {
                                $wr->noMeta(1);
                                $reglim_flg = "N";
                        }
                        #$header->LOT($origLot);
                }		
	}
	else {
		unless ( $header->populateMeta ){
			$wr->noMeta(1);
			$reglim_flg = "N";
		}
	}
}


# log error msg captured during parsing
# check if some errror from Eagle parser module.
if ($misc->{err_msg} ne "") {
	$header->populateMeta();
	if(!($hOptions{FINALLOT}) && !($hOptions{RELLOT})) {
#		#my @item = @{ $misc->{120} };
#		#print "TEST=$item[6]\n";
#		if ($site eq 'isti_tw_csp'){
#                	my ($dummy, $wafer)    = split( /-/, $item[6] );
#                	my ($wafer, $dummy)    = split (/[A-Z]/i, $wafer );
#                	$model->wafers->[0]->number( trim( $wafer ) );
#        	}
#        	else {
#                	$model->wafers->[0]->number( trim( $item[6] ) );
#        	}
        	$pplogger->setWaferFlag(1);	
	}	

	dpExit( 1, "$misc->{err_msg}");
}

my $stats = $model->wafers->[0]->stats;
# S. Boothby - Don't create an IFF if the file contains no results.
if ( $stats->{deviceCount} == 0 )
{
   dpExit( 1, "Zero devices to create IFF (".$stats->{deviceCount}.")");
}
# G. Miole   - File contains 10 or less results, send to sandbox
if ( $stats->{deviceCount} <= 10 && !($hOptions{RELLOT}))
{
   WARN("Too few devices.Sending to sandbox... (".$stats->{deviceCount}.")");
       $wr->forSBox(1);
       $reglim_flg = "N";
}

# Eric - Check Pass count
if ( $misc->{passcount} == 0 || $misc->{passcount} == "") {
	WARN ("All parts tested FAILED!");
	#$reglim_flg = "N";
	$allFail_flg = "Y";
}
else {
	INFO ("$misc->{passcount} parts PASSED!");
}

####################################################
## Check for WMAP Data only if it is not FINALLOT ##
####################################################

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

	#assign source lot as wafer name
	if ($header->SOURCE_LOT ne "") {
		$model->wafers->[0]->name($header->SOURCE_LOT."_".sprintf("%02d",$model->wafers->[0]->number));
		$pplogger->setWaferFlag(1);
	}
	
}

### Use program naming rule
if ($hOptions{FINALLOT} || $hOptions{RELLOT}){
	$model->updateProgram;
}
else {
	$model->updateProgram("MAP_PGM");
}

################################################################################################################
### 2016/03/08 jgarcia : populate default info for WMAP section when wmap object is empty and site is bksort ###
### cpsort, szsort and mesort.                                                                               ###
################################################################################################################
if (!($hOptions{FINALLOT}) || !($hOptions{RELLOT})) {
  
  my $waferUnit = "";
  my $waferFlat = "";
  my $waferFlatType = "";
  my $waferSize = "";
  my $waferPositiveX = "";
  my $waferPositiveY = "";
  
  my $wmap = $model->wmap;
  
	if($wmap->isEmpty && ($site eq "bksort" || $site eq "cpsort" || $site eq "szsort" || $site eq "mesort") ) {
		
		given($site) {
			when("bksort") {
				$waferUnit = "mm";
				$waferSize = 200;
				$waferFlat = "L";
				$waferFlatType = "N";
				$waferPositiveX = "R";
  			$waferPositiveY = "D";
			}
			when("cpsort") {
				$waferUnit = "mm";
				$waferSize = 200;
				$waferFlat = "L";
				$waferFlatType = "N";
				$waferPositiveX = "R";
  			$waferPositiveY = "D";
			}
			when("szsort") {
				$waferUnit = "mm";
				$waferSize = 200;
				$waferFlat = "T";
				$waferFlatType = "N";
				$waferPositiveX = "R";
  			$waferPositiveY = "D";
			}
			when("mesort") {
				$waferUnit = "mm";
				$waferSize = 200;
				$waferFlat = "B";
				$waferFlatType = "N";
				$waferPositiveX = "R";
  			$waferPositiveY = "D";
			}
		}
		WARN("WMAP CONFIG is empty, generating with default value");
#		my %flatDir = (
#        0   => 'B',
#        90  => 'L', ##ORIG R
#        180 => 'T',
#        270 => 'R', ##ORIG L
#    );
    #my $stats = $wafer->stats;
    #my $stats = $self->wafers->[0]->stats;
    INFO("Assign $waferUnit as default WAFER UNIT value");
    $wmap->wf_units($waferUnit);
    INFO("Assign $waferSize as default WAFER SIZE value");
    $wmap->wf_size($waferSize);
    INFO("Assign $waferFlat as default WAFER FLAT value");
    $wmap->flat($waferFlat);
    INFO("Assign $waferFlatType as default WAFER FLAT_TYPE value");
    $wmap->flat_type($waferFlatType);
    $wmap->positive_x($waferPositiveX);
    $wmap->positive_y($waferPositiveY);
    $wmap->convertDieSizeToMM('AUTO',$stats);
    $wmap->calcCenterDie($stats);
    
    $model->wmap($wmap);
 
	}
		 
}


my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);

$formatter->testItems([qw/ number name units group/]);
$formatter->relItems([qw/qpnumber devchar lotchar strname strduration atetemp datalogtype/]);
$formatter->printPar;

### Limits
#if ($hOptions{SITE} eq 'bksort') {
    $model->buildLimit;
    $formatter->printLimit;
    $model->limit->input_file(basename $infile);

#} else {
#
#	if ($reglim_flg eq "Y") {
#		if ($model->isLimitNew && $allFail_flg eq "N"){
#		    $model->buildLimit;
# 		    $formatter->printLimit;
#  		    $model->limit->input_file(basename $infile); 
#  		    $model->limit->registerRefdb;
#	        }
#        }
#        else {   # always generate but do not register limit if sandbox
#	        if ($allFail_flg eq "N") {
#		    $model->buildLimit;
#		    $formatter->printLimit;
#		    $model->limit->input_file(basename $infile);
#	        }
#       }
#}
### Delete gunzipped file
unlink ($output) if $infile =~ /\.gz$/;

dpExit(0);
