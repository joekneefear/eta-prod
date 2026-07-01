#!/usr/bin/env perl_db
# SVN $Id: fcs_mct_stdf_IFF.pl 2597 2020-10-07 03:27:52Z dpower $

=pod

=head1 SYNOPSIS

  fcs_mct_stdf_IFF.pl <Input flie name>
      --out <output dir>  output directory must exists
      --tpDir <TP file look up directory>
      --loc <location e.g. CP,PM,HANA_TH>
      --config<config_tester_type>
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
2015/05/13 grace  : Add normalizeToBaseUnit
2015/05/27 grace  : delete file in temp directory when TP invalid in tpDir 
2015/05/29 grace  : Added support for -v option.
2015/06/02 rcyr   : Moved isFinalLot before populateMeta. Model WMAP only if lot is not finallot.
2015/06/04 gilbert: Added option --site but not required, trim number of lot to spicific site
		  : apply test code on the program for specific site  
2015/06/09 gilbert: apply retest mode code 
2015/06/21 grace  : set value for input_file of PP_LIMITS
2015/07/02 eric   : added LOC arg and pass it as EQUIP6_ID
2015/07/09 eric   : use TP naming rule.
2015/07/23 gilbert: Truncate the test program name to 35 characters and send to sandbox if test
		    program name is truncated and set the header PROGRAM_CLASS
2015/27/23 gilbert: Removed program prefix WSBIN and FTBIN
2015/07/28 grace  : changed wrong number from 1600 to 16000 for bin
2015/09/10 gilbert: Set the value to blank for load_brd and handler if value is "....."
2015/10/21 eric   : extract lotid from fn for gtk_tw_ft
2015/10/21 eric   : extract lotid & test code for atec_ph_ft
2015/10/23 eric   : extract lotid from fn for utac_th_ft
2015/10/27 eric	  : extract and add test code to ppid
2015/11/19 eric	  : always generate but do not register limit if sandbox
2016/02/16 wsanopao: logging pre-processing information  to refdb.pp_log table.
2016/04/13 eric	  : load test conditions from TP file
2016/07/04 eric	  : added options for rel data loading
		  : modified regex pattern for seaching TP
2016/07/07 eric   : corrected bug when checking if atetemp & strdur in range (removed initialization)
2016/07/07 eric   : emptied dtype contains [0-9], emptied strdur & temp if contains [a-z]
2016/07/07 eric   : corrected how rel lot were parsed.
2017/03/13 eric   : do not create iff if zero parts tested
2017/03/17 eric	  : make source lot as wafer name
2017/03/22 eric   : set wafer flag for pplogging
2017/05/29 gilbert: generate limits always and dont register in refdb.pp_limits
2018/01/11 eric	  : parse ONRMS datalogs
2018/01/16 eric	  : delete txt file if error occurs during processing
2018/06/18 eric	  : parse correct legacy ON lotid's for HANA and ATEC
2019/08/13 eric	  : added nosandbox option. its purpose was not to move the file to sandbox when envoked.
2020/09/01 karen  : added support to fork output (IFF)/files to designated location
2021/08/04 karen  : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

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
use PDF::DpWriter;
use PDF::Formatter;
use File::Basename qw/basename dirname/;
use List::Util qw(first);
use POSIX qw(strftime);
use Time::Local;
use File::stat;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use v5.10;
use PPLOG::PPLogger; 	# wsanopao: 
use Number::Range;
use Config::Tiny;

no warnings qw/experimental::lexical_subs experimental::smartmatch/;

our $VERSION = "

1.0
";
our $TESTER  = "MCT_Stdf";

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
        \%hOptions,  "OUT=s", "FORK=s", "TPDIR=s", "FACILITYFILE=s", "LOC=s", "CONFIG=s", "FINALLOT", "V",
        "RELLOT", "LOGFILE=s", "DEBUG", "TRACE", "SITE=s", "PPLOG", "NOSANDBOX")
    )
{
    dpExit( 1, "invalid options" );
}


if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my ($sbins,$hbins,$wsbins,$whbins, $good_count ) =((),(),(),(),());

# Initialize logging

my @required_options = qw/OUT TPDIR LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

my $site =$hOptions{SITE};

INFO("Site code = $site");
if ($site =~ /cpft/) {
	$site = "cpft_mct";
	$pplogger->setEnv($site);
}


# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});

# check input file
my $infile = $ARGV[0];
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

INFO("infile  = $infile");

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);

my $header2 = new_headerLong->new();
my $tpDir = $hOptions{TPDIR};
if (! -d $tpDir ){
    	ERROR("TP lookup dir does not exist : $tpDir");
    	pod2usage();
}
my $location     = $hOptions{LOC};
my $facility = "";
if($hOptions{FINALLOT}) {
        $facility = $config->{$location}->{finalTest};
} else {
 $facility = $config->{$location}->{probe};
}

INFO("FACILITY|EQUIP6_ID=$facility");
my $reglim_flg = "Y";
my $parser = PDF::Parser::Stdf::Generic->new;

if($infile =~ /gz$/)
{
	my $command = "gunzip $infile";
	my $ret = system($command);	
}
else{
  	my ($lot, $wafer) = getLotWafer($infile);
  
  	my $TD_txt = convertBinToAscii($infile);
  	if($TD_txt =~ /Failed to convert.+/i) {
  		$pplogger->setLot($lot);
  		if (!($hOptions{FINALLOT})) {
  			$pplogger->setWaferFlag(1);
  			$header2->LOT($lot);
			$header2->populateMeta();
			$pplogger->setSourceLot($header2->SOURCE_LOT);
			$pplogger->setWafNum($wafer);
  		}
		else {
  			$pplogger->setWafNum("00");
  		}
		
		unlink $TD_txt unless (isLogDebug);
		dpExit(1, "$TD_txt");
	}

	INFO("td_txt:".$TD_txt);
 
 	my $td     = readStdfAscii($TD_txt);
 	if ($td =~ /NO_.+/i) {
  		$pplogger->setLot($lot);
		if (!($hOptions{FINALLOT})) {
  		 	$pplogger->setWaferFlag(1);
  		  	$header2->LOT($lot);
		  	$header2->populateMeta();
			$pplogger->setSourceLot($header2->SOURCE_LOT);
		  	$pplogger->setWafNum($wafer);
  		} 
		else {
  			$pplogger->setWafNum("00");
  		}

		unlink $TD_txt unless (isLogDebug);
		dpExit( 1, "$td");
	}
	
	$good_count = $td->MRR->{GOOD_CNT};	
    	my $header = new_headerLong->new( $parser->stdf2header($td) );
    	my $model = new_model({dataSource => 'MCT'});
      	$model->header($header);
	$pplogger->setModelHeader($model);
    	my ($tests, $testCond) = getTestsFromTP($model,$tpDir, $TD_txt);
    	
	if ($tests =~ /NO_TESTPLAN_FOUND/i) {
    		$pplogger->setLot($lot);
		if (!($hOptions{FINALLOT})) {
			$pplogger->setWaferFlag(1);
	  		$header2->LOT($lot);
			$header2->populateMeta();
			$pplogger->setSourceLot($header2->SOURCE_LOT);
			$pplogger->setWafNum($wafer);
			}
			else {
		  		$pplogger->setWafNum("00");
		  	}
			unlink $TD_txt unless (isLogDebug);			
    			dpExit(4,"$tests");
    	}
	
	# wsanopao: Passing Reference of Model
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

	given ($site) {
    	when ('hana_th_ft') {
     		my $lot         = $header->LOT;
     		my $program     = $header->PROGRAM;
     		my $str_len     = length($lot);
     		my $test_code   = ""; 
		my $time_stmp   = stat($infile)->mtime;
	
		if ($time_stmp <= 1512066031) { #10-CHAR FSC LOTID <= NOV-30-2017
		INFO ("Using xFSC Lot ID = $lot");
     			if ($str_len == 12) {
     	   			$test_code 	= substr ($lot, 10);
     	   			$lot         =~ s/$test_code$//g;
       	   			my ($dump,$final_code,$load_status, $retest_mode) = getTestCode("$test_code", "HANA_FT_Test_Code.txt", "hana_th_ft_mct");
	   			chomp($final_code);
	   			$program .="_$final_code";
	   			$header->LOT($lot);
	   			$header->PROGRAM($program);
	   			$header->INDEX2($retest_mode) if $retest_mode ne "";
			
	   			if ($load_status =~/Sandbox/)
	   			{
	      				$wr->forSBox(1);
	      				$reglim_flg = "N";
	      				INFO("Test Code for SandBox or not in the list = $final_code");
 	   			}
     			}
     			else {
				unlink $TD_txt unless (isLogDebug);
           			dpExit (1, "LOT + Test Code length is not equal to 12 characters");
     			}
		}
		elsif ($time_stmp > 1512066031){  #STARTED USING 9-CHAR ON LOTID > NOV-30-2017
			INFO ("Using Legacy ON Lot ID = $lot");
			if ($str_len == 11 || $str_len == 12 ) {
                                $test_code      = substr ($lot, 9);
                                $lot         =~ s/$test_code$//g;
                                my ($dump,$final_code,$load_status, $retest_mode) = getTestCode("$test_code", "HANA_FT_Test_Code.txt", "hana_th_ft_mct");
                                chomp($final_code);
                                $program .="_$final_code";
                                $header->LOT($lot);
                                $header->PROGRAM($program);
                                $header->INDEX2($retest_mode) if $retest_mode ne "";

                                if ($load_status =~/Sandbox/)
                                {
                                        $wr->forSBox(1);
                                        $reglim_flg = "N";
                                        INFO("Test Code for SandBox or not in the list = $final_code");
                                }
                        }
                        else {
                                unlink $TD_txt unless (isLogDebug);
                                dpExit (1, "LOT + Test Code length is not equal to 12 characters");
                        }		
		}
    	}
    	when ('gtk_tw_ft') {
    		# get lotid from fn
		my $fn  = basename($infile);
		my @arr = split /\_/, $fn;
		my $lot = $arr[0];
		$header->LOT($lot);
    	}
    	when ('atec_ph_ft'){
		# get lotid & test code
		my $lot       = $header->LOT;
		my $program   = $header->PROGRAM;
		my $str_len   = length($lot);
		my $test_code = "";
		my $time_stmp = stat($infile)->mtime;

		if ($time_stmp <= 1510726897) {  #xFSC id used <= 15-Nov-2017
			if ($str_len == 12 && $lot =~ /^AP/i) {
				INFO ("Using xFSC Lot ID = $lot");
           			$test_code   = substr ($lot, 10);
           			$lot         =~ s/$test_code$//g;
           			my ($dump,$final_code,$load_status, $retest_mode) = getTestCode("$test_code", "ATEC_PH_FT_Test_Code.txt", "atec_ph_ft_mct");
           			chomp($final_code);
           			$program .="_$final_code";
           			$header->LOT($lot);
           			$header->PROGRAM($program);
           			$header->INDEX2($retest_mode) if $retest_mode ne "";
			
           			if ($load_status =~/Sandbox/) {
              				$wr->forSBox(1);
	     	 			$reglim_flg = "N";
              				INFO("Test Code for SandBox or not in the list = $final_code");
           			}
        		}	
			elsif ($str_len == 11 && $lot =~ /^CU/i) { #some used ON lotid < 15-Nov-2017
				INFO ("Using Legacy On Lot ID = $lot");
                                $test_code   = substr ($lot, 9);
                                $lot         =~ s/$test_code$//g;
                                my ($dump,$final_code,$load_status, $retest_mode) = getTestCode("$test_code", "ATEC_PH_FT_Test_Code.txt", "atec_ph_ft_mct");
                                chomp($final_code);
                                $program .="_$final_code";
                                $header->LOT($lot);
                                $header->PROGRAM($program);
                                $header->INDEX2($retest_mode) if $retest_mode ne "";

                                if ($load_status =~/Sandbox/) {
                                        $wr->forSBox(1);
                                        $reglim_flg = "N";
                                        INFO("Test Code for SandBox or not in the list = $final_code");
                                }
                        }
        		else {
				unlink $TD_txt unless (isLogDebug); 
           			dpExit (1, "LOT + Test Code length is not equal to 12 characters");
        		}
		}
		elsif ( $time_stmp > 1510726897) { #started using ON lotid > 15-Nov-2017
			INFO ("Using Legacy ON Lot ID = $lot");
			if ($str_len == 11) {
                                $test_code   = substr ($lot, 9);
                                $lot         =~ s/$test_code$//g;
                                my ($dump,$final_code,$load_status, $retest_mode) = getTestCode("$test_code", "ATEC_PH_FT_Test_Code.txt", "atec_ph_ft_mct");
                                chomp($final_code);
                                $program .="_$final_code";
                                $header->LOT($lot);
                                $header->PROGRAM($program);
                                $header->INDEX2($retest_mode) if $retest_mode ne "";

                                if ($load_status =~/Sandbox/) {
                                        $wr->forSBox(1);
                                        $reglim_flg = "N";
                                        INFO("Test Code for SandBox or not in the list = $final_code");
                                }
                        }
                        else {
                                unlink $TD_txt unless (isLogDebug);
                                dpExit (1, "LOT + Test Code length is not equal to 12 characters");
                        }	
		}
    	}
    	when ('utac_th_ft'){
		# get lotid from fn
		my $fn  = basename($infile);
        	my @arr = split /\_/, $fn;
        	my $lot = $arr[1];
		my $test_code = $arr[2];
           	$header->LOT($lot);
		my $program = $header->PROGRAM;
		my ($dump,$final_code,$load_status, $retest_mode) = getTestCode("$test_code", "UTAC_TH_FT_Test_Code.txt", "utac_th_ft_mct");
		chomp($final_code);
		$program .="_$final_code";
		$header->PROGRAM($program);
		$header->INDEX2($retest_mode) if $retest_mode ne "";	

		if ($load_status =~/Sandbox/) {
			$wr->forSBox(1);
			$reglim_flg = "N";
			INFO("Test Code for SandBox or not in the list = $final_code");
		}	
    	}
}

    $header->EQUIP6_ID( "$facility" );
    $header->CFG_TESTER_TYPE( $hOptions{CONFIG} );

 my $handler  = $header->EQUIP5_ID;
    $handler  = "" if $handler  =~/^\.\.\.\.\.\./;
    $header->EQUIP5_ID($handler);

 my $load_brd = $header->EQUIP4_ID;
    $load_brd = "" if $load_brd =~/^\.\.\.\.\.\./;
    $header->EQUIP4_ID($load_brd);

    $header->isFinalLot( $hOptions{FINALLOT} );
    $header->isRelLot( $hOptions{RELLOT} );

    # do if RELLOT
    if ($hOptions{RELLOT}){
	my $base_fn = basename($infile);
        $base_fn =~ s/\.TD.*+//ig;
        my @item = split /\_|\./, $base_fn;
	my $qpnum;
	my $devchar;
	my $lotchar;
	my $strname;
	my $strdur;
	my $temp;
	my $dtype;
	my $req_id;

	if ($site =~ /merel_mct/i ) {
		$qpnum = $item[0];
		$strname = $item[1];
        	$strdur = $item[2];
        	$temp = $item[3];
        	$dtype = $item[4];
           	$dtype = "" if $dtype =~ /[0-9]/;

		if ($qpnum =~ /^20/) {
			$qpnum = substr $item[0], 0, 8;
       			$devchar = substr $item[0], 8, 1;
        		$lotchar = substr $item[0], 9, 1;
			$header->LOT($qpnum.$devchar.$lotchar);	
		}
		elsif ($qpnum =~ /^W/i) {
			$req_id = $item[0];
			$qpnum = substr $item[0], 0, 6;
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

##################################################
# Check for WMAP Data only if it is not FINALLOT #
##################################################
if(!($hOptions{FINALLOT}) && !($hOptions{RELLOT})) {
my $wmap = $model->updateWMap;
        if(defined $wmap)   {
                INFO("MAP IS DEFINED");
    		unless ( !$wmap->isEmpty ){
			#$wr->wmapIsEmpty(1);
			if (!($hOptions{NOSANDBOX})) {
				$wr->wmapIsEmpty(1);
			}
			else {
				WARN("File was not sandboxed. Argument was enabled.");
			}
			$reglim_flg = "N";
		}
                unless ( $wmap->confirmed ) {
                        #$wr->noWMap(1);
			if (!($hOptions{NOSANDBOX})) {
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
    		#i#$wr->wmapIsEmpty(1) unless ( !$wmap->isEmpty );
                #$wr->noWMap(1);
		#$reglim_flg = "N";
		unless ( !$wmap->isEmpty ){
                        #$wr->wmapIsEmpty(1);
                        if (!($hOptions{NOSANDBOX})) {
                                $wr->wmapIsEmpty(1);
                        }
                        else {
                                WARN("File was not sandboxed. Argument was enabled.");
                        }
                        $reglim_flg = "N";
                }
                unless ( $wmap->confirmed ) {
                        #$wr->noWMap(1);
                        if (!($hOptions{NOSANDBOX})) {
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
    if ($hOptions{FINALLOT} || $hOptions{RELLOT}) {
        $header->PROGRAM_CLASS(2);
    	$model->updateProgram;
    }
    else {
        $header->PROGRAM_CLASS(1);
	$model->updateProgram("MAP_PGM");
    }


    my $pgm = "";
    my $str_limit;
	
    $pgm = $header->PROGRAM;

    foreach my $stdfWafer ( @{ $td->wafers } ) {
        my $wafer = new_wafer;
        $wafer->START_TIME( $header->START_TIME );
        $wafer->END_TIME( $header->END_TIME );
        my $waferNum = -1;
        if ( defined $stdfWafer->WIR ) {
            	$waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
            	$wafer->number($waferNum);
		#source lot as wafer name
		if(!($hOptions{FINALLOT}) && !($hOptions{RELLOT}) && $header->SOURCE_LOT ne "") {
			$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
			$pplogger->setWaferFlag(1);
		}
            	if ( defined $stdfWafer->WIR->{START_T}
                and $stdfWafer->WIR->{START_T} > 1000000000 )
            	{
                	$wafer->START_TIME( $stdfWafer->WIR->{START_T} );
            	}
            	if ( defined $stdfWafer->WRR->{FINISH_T}
                and $stdfWafer->WRR->{FINITSH_T} > 1000000000 )
            	{
                	$wafer->END_TIME( $stdfWafer->WRR->{FINISH_T} );
            	}
			
        }
	if(defined $stdfWafer->WRR)
	{
		if(defined $stdfWafer->WRR->{GOOD_CNT})
		{
			$good_count =  $stdfWafer->WRR->{GOOD_CNT};
		}
	}		
		
	if ( @{ $stdfWafer->WSBR } ) {
		$header->PROGRAM($pgm);
		my $sbr_record = $stdfWafer->WSBR;
		my @ary_sbr = ();
		my %h_sbr=();
		foreach (@$sbr_record){
			if($_->{SBIN_NUM} < 1600){					
				my $bin = new_bin;
				$bin->{SBIN_NUM} = $_->{SBIN_NUM};
				$bin->{SBIN_NAM} = $_->{SBIN_NAM};
				$bin->{SBIN_CNT} = $_->{SBIN_CNT};
				$bin->{SBIN_PF} = $_->{SBIN_PF};	
				$h_sbr{$_->{SBIN_NUM}} = $bin;
			}
			if($_->{SBIN_NUM} ne ""){
				push @ary_sbr, $h_sbr{$_->{SBIN_NUM}};	
			}				
		}
		
		#INFO("ary_sbr :". $#ary_sbr."/". $good_count);
		$wsbins = $parser->sbr2bins( \@ary_sbr, $good_count );		
			
	}
		
		
		
	##### hbins for wafer
	if ( @{ $stdfWafer->WHBR } ) {
		my $sbr_record = $stdfWafer->WHBR;
		my @ary_hbr = ();
		my %h_hbr=();
		foreach (@$sbr_record){
			if($_->{HBIN_NUM} < 1600){
				INFO("less 1600:".$_->{HBIN_NUM} );
				my $bin = new_bin;
				$bin->{HBIN_NUM} = $_->{HBIN_NUM};
				$bin->{HBIN_NAM} = $_->{HBIN_NAM};
				$bin->{HBIN_CNT} = $_->{HBIN_CNT};
				$bin->{HBIN_PF} = $_->{HBIN_PF};	
				$h_hbr{$_->{HBIN_NUM}} = $bin;
			}
			if($_->{HBIN_NUM} ne ""){
				push @ary_hbr, $h_hbr{$_->{HBIN_NUM}};	
			}
				
		}
			
		INFO("ary_hbr count".$#ary_hbr);
		$whbins = $parser->hbr2bins( \@ary_hbr, $good_count );					
	}
		
	$wafer->sbins($wsbins);
	$wafer->hbins($whbins);		
       
        $wafer->tests($tests);
        $wafer->dies( $parser->res2dies( $stdfWafer->res, $tests ) );
        $model->add( 'wafers', $wafer );
    }

	if($wsbins eq "" ){

		my $sbr_record = $td->SBR;
		my $sbr_record_each = $td->SBR_each;
		
		if(! (@$sbr_record > 0))
		{
			if(@$sbr_record_each > 0){
				$sbr_record = $td->SBR_each;
			}
		}
		
		my @ary_sbr = ();
		my %h_sbr=();
		foreach (@$sbr_record){
		
		INFO($_->{SBIN_NUM});
			if($_->{SBIN_NUM} < 16000){					
			
				my $bin = new_bin;
				$bin->{SBIN_NUM} = $_->{SBIN_NUM};
				$bin->{SBIN_NAM} = $_->{SBIN_NAM};
				$bin->{SBIN_CNT} = $_->{SBIN_CNT};
				$bin->{SBIN_PF} = $_->{SBIN_PF};	

				$h_sbr{$_->{SBIN_NUM}} = $bin;
			}
			if($_->{SBIN_NUM} ne ""){
				push @ary_sbr, $h_sbr{$_->{SBIN_NUM}};	
			}				
		}
		$sbins = $parser->sbr2bins( \@ary_sbr, $good_count );	
		
		$model->sbins($sbins);
		$header->PROGRAM($pgm);
		
	}
	
	if($whbins eq ""){
				
		my $hbr_record = $td->HBR;
		my $hbr_record_each = $td->HBR_each;
		
		if(! (@$hbr_record > 0))
		{
			if(@$hbr_record_each > 0){
				$hbr_record = $td->HBR_each;
			}
		}
		
		my @ary_sbr = ();
		my %h_sbr=();
		foreach (@$hbr_record){
		
		INFO($_->{HBIN_NUM});
			if($_->{HBIN_NUM} < 16000){					
			
				my $bin = new_bin;
				$bin->{HBIN_NUM} = $_->{HBIN_NUM};
				$bin->{HBIN_NAM} = $_->{HBIN_NAM};
				$bin->{HBIN_CNT} = $_->{HBIN_CNT};
				$bin->{HBIN_PF} = $_->{HHIN_PF};	

				$h_sbr{$_->{HBIN_NUM}} = $bin;
			}
			if($_->{HBIN_NUM} ne ""){
				push @ary_sbr, $h_sbr{$_->{HBIN_NUM}};	
			}				
		}
		$hbins = $parser->hbr2bins( \@ary_sbr, $good_count );	
		
		$model->hbins($hbins);
	}	

	# do not create iff
	my $stats = $model->wafers->[0]->stats;
	if ( $stats->{deviceCount} == 0 ){
		unlink $TD_txt unless (isLogDebug);
		dpExit( 1, "Zero devices to create IFF (".$stats->{deviceCount}.")");
	}

    	&normalizeToBaseUnit($model);
	
    	my $formatter = new_iff_formatter(
        {   model  => $model,
            writer => $wr
        }
    	);
	$formatter->dataItems([qw/x y site partid hard_bin soft_bin/]);
    	$formatter->printPar;
    	unlink $TD_txt unless (isLogDebug);

	#Limits
	#if ($reglim_flg eq "Y") {
   	#	if ($model->isLimitNew){
	#		$model->buildLimit;
	#		$model->limit->conditionNames($testCond);
	#		$formatter->printLimit;
	#		$model->limit->input_file(basename $infile); 
	#		$model->limit->registerRefdb;
   	#	}
	#}
	#else {  # always generate but do not register limit if sandbox
		$model->buildLimit;
		$model->limit->conditionNames($testCond);
		$formatter->printLimit;
		$model->limit->input_file(basename $infile);
	#}

}

dpExit(0);

##############
sub getTestsFromTP {
  	my $model = shift;
  	my $tpDir = shift;
  	my $TD_txt_inTemp = shift;
  	my $program = $model->header->PROGRAM;
  	my $rev = $model->header->REVISION;
 
  	my $prog1 = (split('-',$program))[0];
  	my $prog2 = "";
  
  	if ($program =~ /-/){
     		$prog2 = (split('-',$program))[1];
  	}
  
  	#my $regexp = "${prog1}[-]{0,1}${prog2}_.*${rev}_.*\.TP";
  	my $regexp = "${program}_REV_$rev.*\.TP";
  	INFO( "TP file search pattern : $regexp");
  	my $TP = undef;

  	foreach my $file (glob "$tpDir/*.TP*"){
    		if ($file =~ /$regexp/i){
       			INFO("TP Found : $file");
       			$TP = $file;
    	}
  	}
 
  	unless (defined $TP ) {  
		unlink $TD_txt_inTemp unless (isLogDebug);
		return("NO_TESTPLAN_FOUND", "");	
     		#dpExit(4,"No TP found in $tpDir by pattern $regexp");
  	} 
	
    	my $TP_txt = convertBinToAscii($TP);
    	my $tp     = readStdfAscii($TP_txt);
    	my $header = new_headerLong->new( $parser->stdf2header($tp) );
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

sub getTestCode
{
   	my $test_code   = shift;
    my $ref_file = shift;
   	my $env_name = shift; 
    my $ref_dir ="$ENV{DPDATA}/data/${env_name}/TestCode";

      	if(! -e "${ref_dir}/${ref_file}")
      	{
   	  	dpExit (1, "Test Code reference file ${ref_dir}/${ref_file}:No such file or directory");
                             
      	}
        INFO("TEST CODE=$ref_file");

   	my $grep_code = `grep \^$test_code\, ${ref_dir}/${ref_file}`;
      	chomp($grep_code);
      	$grep_code =~s/\s+//g;
   	my ($code, $add_code, $status, $retest_mode) = split/\,/, $grep_code;
      	
	if ($grep_code eq "")
      	{
          	$code     	= $test_code;
          	$add_code 	= $test_code;
          	$status   	= "Sandbox";
	  	$retest_mode  = "";
      	}
      	
	return ($code, $add_code, $status, $retest_mode);
}

sub getBinSummary{
  	my $bin = shift;
  	my $bin_each = shift;
  	my $g_cnt = shift;
  	my $mode = shift;
  	my $tests = shift;
  	my $bins;
  
  	if(@$bin > 0)
  	{
		if($mode eq "sbr"){
			$sbins = $parser->sbr2bins( $bin, $g_cnt );
		}
		else{
			$hbins = $parser->hbr2bins( $bin, $g_cnt );
		}	
  	}
  	elsif(@$bin_each > 0)
  	{	
		if($mode eq "sbr"){
			$sbins = $parser->sbr2bins( $bin_each, $g_cnt );
		}
		else{
			$hbins = $parser->hbr2bins( $bin_each, $g_cnt );
		}
  	}
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
  
   	if($wafer < 10) {
		$wafer = "0"."$wafer";
	}
  
  	$waferid = $wafer;
  
	return ($lotid, $waferid);
}
