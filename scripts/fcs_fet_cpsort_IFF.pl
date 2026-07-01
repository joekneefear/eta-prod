#!/usr/bin/env perl_db
# SVN $Id: fcs_fet_cpsort_IFF.pl 2629 2020-10-09 01:54:22Z dpower $

=pod

=head1 SYNOPSIS

  fcs_fet_ft_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
	  --TPDIR <
	   --config <cfg_tester_type>
	   --loc <location e.g CP, SZ, ME>
	   --limitDir <limit file look up direcotry>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read STDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<jason.arp@pdf.com>

=head1 CHANGES

2015/08/28 eric : new
2015/09/04 eric : modified script to cater cpsort_fet_quad
2015/09/04 eric : display TYPE INFO
2015/11/19 eric : always generate but do not register limit if sandbox
2016/01/29 wsanopao: logging pre-processing information  to refdb.pp_log table.
2017/02/23 jgarcia : added getDateProbedLotWaferTestplanSequence subroutine
2017/02/23 jgarcia added trapping of error when converting raw cpr file with EWB converter have some issue.
2017/02/24 jgarcia added trapping of error when converting raw cpr QUAD file with EWB converter have some issue.
2017/02/24 jgarcia : for Quad CPR, get lot,wafer and testplan name, then process first the PRN to generate TPL
#                    to be used in converting CPR to TD.
2017/02/25 jgarcia : for QUAD CPR check first the existence of the correct SEPPROBE wafermap and dpExit 4 if there is
#										 none found.
2017/03/02 jgarcia : modified to make sure to exit when it will not find SEPROBE map for the date month and the previous month.
2017/03/15 eric    : user source lot as wafer name
2017/03/17 eric    : make sure source lot is not blank before assigning as wafer id
2017/03/22 eric    : set wafer flag for pplogging
2017/03/23 jgarcia : get source lot when raw file have issue which to be used in logging as wafer concatenated with wafer#.
2017/03/23 jgarcia : fixed bug on no logs for No Sequence file in TP folder.make sure to trap NO Sequence file before to try to search and process for a PRN file and log.
2017/05/03 jgarcia : fixed bug unable to look for sequence file.
2017/05/03 jgarcia : fixed bug on logged wafer number value.
2017/05/22 jgarcia : fixed bug - unable to show sequence filename if it has sequence file not found error for cpsor_fet single.
29-May-2017 gilbert: generate limits always and dont register in refdb.pp_limits
13-May-2020 eric	use camstar web service to get cmap or seq name
2020/09/01 karen       : added support to fork output (IFF)/files to designated location
2021-Apr-15 karen      : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
2021-Apr-15 jgarcia : modified not to hardcode SEQ file location and hardcoded temp folders.
2021-May-06 jgarcia : fix to gzip wm_iff files generated and wm_iff EQUIP6_ID = facility value .

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
use Time::Local;
use File::Find;
use IPC::Open3;
use File::Copy;
use LWP::UserAgent;
use Config::Tiny;

our $VERSION = "1.0";
our $TESTER  = "FET";
my $location = "";
my $site;

# HASH TO RECEIVE OPTIONS
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# READ ARGUMENTS
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions,  "OUT=s", "FORK=s", "FACILITYFILE=s", "LIMITDIR=s", "LOC=s", "CONFIG=s",
        "LOGFILE=s", "DEBUG", "TRACE", "V", "TPDIR=s", ,"TYPE=s", "PPLOG"
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

# INITIALIZED LOGGING

my @required_options = qw/OUT TPDIR LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});

my $location = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
my $facility = "";
if($hOptions{FINALLOT}) {
        $facility = $config->{$location}->{finalTest};
} else {
        $facility = $config->{$location}->{probe};
}

INFO("FACILITY|EQUIP6_ID=$facility");

my $seqLoc1 = "$hOptions{TPDIR}/";
my $seqLoc2 = "$hOptions{TPDIR}/Old/";
INFO("SEQ Location1 = $seqLoc1 || SEQ Location2 = $seqLoc2");

# CHECK INPUT FILE
my $infile = $ARGV[0];
if ( ! -f $infile ) {
    ERROR("$infile does not exist");
    pod2usage(3);
}

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);


# CREATE WRITER
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   basename => ( basename $infile),
        ext      => 'iff',
        outdir   =>  $hOptions{OUT},
	forkdir => $hOptions{FORK},
        gzipIFF  => 'Y'
    }
);

# CREATE PARSER
my $parser = PDF::Parser::Stdf::Generic->new;
my $perl = "perl_db";

my ( $TP_bin, $TD_bin );
my $conv_TD;
my $conv_TP;
my $reglim_flg = "Y";
my ($lotid,$waferno,$tp_name,$mapFile,$sequence);
my $header2 = new_headerLong->new();
my $flag = 0;

INFO("TYPE = $hOptions{TYPE}");
$pplogger->setWaferFlag(1);

# CONVERT SOURCE FILE TO td
if ($hOptions{TYPE} eq "SINGLE") {
	#$seqLoc1 = "/apps/exensio_data/data/cpsort_fet/TP";
	#$seqLoc2 = "/apps/exensio_data/data/cpsort_fet/TP/Old";
	# wsanopao: Set Environment
	$pplogger->setEnv('cpsort_fet');
	#my ($errLot,$errWafer,$errTestplan,$errSequence, $mapFile, $errTPL);
	#($errLot,$errWafer,$errTestplan,$errSequence) = &getLotWaferTestplanSequence($infile);
	#&testCPRSingle($infile, $seqLoc1, $seqLoc2);
	&testCPRSingle($infile,$seqLoc1);
  $conv_TD = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_fet_cpr_cpsort.pl -infile=$infile";
}
elsif ($hOptions{TYPE} eq "QUAD") {
	#$seqLoc1 = "$hOptions{TPDIRQUAD}/";
	#$seqLoc2 = "$hOptions{TPDIRQUAD}/Old/";
	#$seqLoc1 = "/apps/exensio_data/data/cpsort_fet_quad/TP";
	#$seqLoc2 = "/apps/exensio_data/data/cpsort_fet_quad/TP/Old";
	# wsanopao: Set Environment
	$pplogger->setEnv('cpsort_fet_quad');
	### get LOT, WAFER and TP Name first
	($lotid,$waferno,$tp_name) = &getLotWaferTestplanName($infile);
	if (length($waferno) < 2 && $waferno < 10) {
		$waferno = "0"."$waferno";
	}
	INFO("LOT=$lotid||WAFER=$waferno||TP=$tp_name");
	if($lotid eq "NO_LOTID") {
			$pplogger->setLot($lotid);
			$pplogger->{_WAF_NUM} = $waferno;
			dpExit(1,"$lotid indicated in the file");
	}
	if($waferno eq "NO_WAFERID") {
			$pplogger->setLot($lotid);
			$header2->LOT($lotid);
			$header2->populateMeta();
			$pplogger->setSourceLot($header2->SOURCE_LOT);
			#$pplogger->setWafNum($errWafer);
			$pplogger->{_WAF_NUM} = $waferno;
			dpExit(1,"$waferno indicated in the file");
	}
	if($tp_name eq "NO_TESTPLAN") {
			$pplogger->setLot($lotid);
			$header2->LOT($lotid);
			$header2->populateMeta();
			$pplogger->setSourceLot($header2->SOURCE_LOT);
			#$pplogger->setWafNum($errWafer);
			$pplogger->{_WAF_NUM} = $waferno;
			dpExit(1,"$tp_name indicated in the file");
	}

	($mapFile, $sequence) = &checkCorrectMapExistAndGetSequenceName($waferno,$lotid,$infile);
	my $errSeq = $sequence.".SEQ";
	#$errSeq = "${sequenceLocation}/${errSeq}";
	#print "-----$errSeq||$sequence\n";
	#print "EXIT\n";	exit 0; dpExit(1,"TEST");
	#print "---------------------------->$mapFile<\n";
	$header2->LOT($lotid);
	$header2->populateMeta();
	if( $mapFile eq "" ) {
		$pplogger->setLot($lotid);
		$pplogger->setSourceLot($header2->SOURCE_LOT);
		#my $waf = "$errLot"."_"."$errWafer";

		$pplogger->setWafNum($waferno);
		#unlink $TP unless (isLogDebug);
	    	dpExit(4,"No SEPORBE Map file found in archive of cpsort_wmap_sep environment.");
	}
	###03-23-2017:jgarcia: added trapping
	if($sequence ne "") {

			if (!(-e "$seqLoc1"."$errSeq")) {
				$flag = 1;
				$pplogger->setLot($lotid);
				#$header2->LOT($lotid);
				#$header2->populateMeta();
				$pplogger->setSourceLot($header2->SOURCE_LOT);
				$pplogger->setWafNum($waferno);
				#$pplogger->{_WAF_NUM} = $waferno;
				#dpExit (1, "NO sequence file=\"$errSeq\" exist in $seqLoc1 ");
			}
			if ($flag == 1 ) {
				if (!(-e "$seqLoc2"."$errSeq")) {
					$flag = 1;
					$pplogger->setLot($lotid);
					#$header2->LOT($lotid);
					#$header2->populateMeta();
					$pplogger->setSourceLot($header2->SOURCE_LOT);
					$pplogger->setWafNum($waferno);
					#$pplogger->{_WAF_NUM} = $waferno;
					#dpExit (1, "NO sequence file=\"$errSeq\" exist in $seqLoc1 ");
				}
				$flag = 0;
			}
			if ($flag == 1) {
				dpExit (1, "NO sequence file=\"$errSeq\" exist in $seqLoc1 or $seqLoc2 ");
			}



	} else {
		$pplogger->setLot($lotid);
		#$header2->LOT($lotid);
		#$header2->populateMeta();
		$pplogger->setSourceLot($header2->SOURCE_LOT);
		$pplogger->setWafNum($waferno);
		#$pplogger->{_WAF_NUM} = $waferno;
		dpExit (1, "NO sequence file indicated from the MAP file. ");
	}

	#print "---TESTLOT=$lotid\t---TESTWAFER=$waferno\t----TESTPLAN=$tp_name\n";
	# FIND THE CORRESPONDING PRN FILE
	my $TP_path = $hOptions{TPDIR};
	my $regexp = $tp_name."\.PRN";

	my $TP = undef;
	my $foundTPFlag = 0;
	foreach my $file (glob "$TP_path/*.PRN"){
	  if ($file =~ /$regexp/i){
	  	 $foundTPFlag = 1;
	     INFO("PRN Found : $file");
	     $TP = $file;
	     my $firstAttemptConvTP = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_fet_prn_cpsort_quad.pl -infile=$TP";
	     my @output3 = `$firstAttemptConvTP`;
	     if (@output3[-1] =~ /tp=(.*)/ ) {
			 $TP_bin = $1;
			 INFO("TP = $TP_bin");
			 } else {

					dpExit(1, "Failed to convert PRN $conv_TP : " . join("#", @output3 ));
			 }
			 if($foundTPFlag == 1) {
	  			last;
	  	 }
	  }
	}
	unless (defined $TP ) {
		$pplogger->setLot($lotid);
		#my $waf = "$errLot"."_"."$errWafer";
		$pplogger->setWafNum($waferno);
		unlink $TP unless (isLogDebug);
	    	dpExit(4,"No TP found in $TP_path by pattern $regexp");
	}

    $conv_TD = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_fet_cpr_cpsort_quad.pl -infile=$infile";
}

my @output = `$conv_TD`;

if ($?) {
	#2017-02-23 jgarcia added trapping of error when converting raw cpr file with EWB converter have some issue.
	#print("Failed command - $conv_TD\n");
	$flag = 0;
	my ($errLot,$errWafer,$errTestplan,$errSequence, $mapFile, $errTPL);
	if ($hOptions{TYPE} eq "SINGLE") {
		&testCPRSingle($infile, $seqLoc1);

	} elsif ($hOptions{TYPE} eq "QUAD") {
		#$seqLoc1 = "/data/cpsort_fet_quad/TP/";
		#$seqLoc2 = "/data/cpsort_fet_quad/TP/Old/";
		###($errLot,$errWafer,$errTestplan,$errSequence,$mapFile) = &getDateProbedLotWaferTestplanSequence_QUAD($infile);
		$errTPL = $tp_name;
		$pplogger->setLot($lotid);
		#my $waf = "$errLot"."_"."$errWafer";

		#print "$errWafer\n";
		$pplogger->setWafNum($waferno);
		#print "---$sequence\n";
		$errSequence = "$sequence".".SEQ";
		$errTestplan  = "$tp_name".".PRN";
		$errTPL = "$errTPL".".TPL";
		#print "-----LOT=$errLot\tWAFER=$errWafer\tTP=$errTestplan\tSEQ=$errSequence\tTPL=$errTPL\n";
		#print "----$flag\n";
		if($errSequence ne "") {
			if (!(-e "$seqLoc1"."$errSequence")) {
				$flag = 1;
				$pplogger->setLot($lotid);
				#$header2->LOT($lotid);
				#$header2->populateMeta();
				$pplogger->setSourceLot($header2->SOURCE_LOT);
				$pplogger->setWafNum($waferno);
				#$pplogger->{_WAF_NUM} = $waferno;
				#dpExit (1, "NO sequence file=\"$errSeq\" exist in $seqLoc1 ");
			}
			if ($flag == 1 ) {
				if (!(-e "$seqLoc2"."$errSequence")) {
					$flag = 1;
					$pplogger->setLot($lotid);
					#$header2->LOT($lotid);
					#$header2->populateMeta();
					$pplogger->setSourceLot($header2->SOURCE_LOT);
					$pplogger->setWafNum($waferno);
					#$pplogger->{_WAF_NUM} = $waferno;
					#dpExit (1, "NO sequence file=\"$errSeq\" exist in $seqLoc1 ");
				}
				$flag = 0;
			}
			if ($flag == 1) {
				dpExit (1, "NO sequence file=\"$errSequence\" exist in $seqLoc1 or $seqLoc2 ");
			}
#			if (! (-e "$seqLoc1"."$errSequence" || ! -e "$seqLoc2"."$errSequence" )) {
#				dpExit (1, "Failed to convert CPR file $infile : NO sequence file=\"$errSequence\" exist in /data/cpsort_fet_quad/TP/ ");
#			}
		} elsif ($errTestplan ne "") {
			if (! (-e "$seqLoc1"."$errTestplan")) {
				dpExit (1, "Failed to convert CPR file $infile : NO Testplan=\"$errTestplan\" exist in $ENV{DPDATA}/data/cpsort_fet_quad/TP/ ");
			}
		} elsif ($errTPL ne "") {
			#print "-------------------INSIDE ERRTPL-------------------\n";
			if (! (-e "$seqLoc1"."$errTPL")) {
				dpExit (1, "Failed to convert CPR file $infile : NO TPL file=\"$errTPL\" exist in $ENV{DPDATA}/data/cpsort_fet_quad/TP/ ");
			}
		} elsif ($mapFile eq "") {
			#if (! -e "/data/cpsort_fet_quad/TP/${errTestplan}") {
				dpExit (1, "Failed to convert CPR file $infile : NO Map File found.");
			#}
		} elsif( $errLot eq "") {
			dpExit (1, "Failed to convert CPR file $infile : NO Lotid indicated inside the raw file");
		} elsif( $errWafer eq "") {
			dpExit (1, "Failed to convert CPR file $infile : NO Wafer number indicated inside the raw file");
		} elsif( $errSequence eq "") {
				dpExit (1, "Failed to convert CPR file $infile : NO Sequence filename indicated inside the raw file");
		} elsif( $errTestplan eq "") {
				dpExit (1, "Failed to convert CPR file $infile : NO Testplan name indicated inside the raw file");
		}

		dpExit(1, "$?")


	} ### QUAD






}

my @binMap = ();
foreach my $out_file (@output){
        my @wk = split('td=', $out_file);
        foreach my $td_file (@wk)
        {
                if($td_file =~ /.TD/){
                        $TD_bin  = $td_file;
                        $TD_bin =~ s/ //;
                }
                else
                {
                        $td_file =~ s/\015//;
                        $td_file =~ s/ //;
                        $td_file =~ s/\cM\n//;
                        $td_file =~ s/\r//;
                        $td_file =~ s/\n//;

                        INFO("WM FILE: $td_file");

                        if($td_file !~ / /)
                        {
                                push @binMap, $td_file ;
                        }
                }
        }
}

# PROCESS WM FILE FILE FIRST TO GET CFG_ID
if (scalar(@binMap) > 0) {
    foreach my $bin (@binMap){
        if($bin ne "") {
                my $bin_txt = convertBinToAscii($bin);
              	if($bin_txt =~ /Failed to convert.+/i) {
              		$pplogger->setWaferFlag(1);
									$header2->LOT($lotid);
								  $header2->populateMeta();
								  $pplogger->setLot($lotid);
								  $pplogger->setSourceLot($header2->SOURCE_LOT);
									$pplogger->setWafNum($waferno);
									dpExit(1, "$bin_txt");
              	}
                my $bin_td = readStdfAscii_WM($bin_txt);
                if ($bin_td =~ /NO_.+/i) {
									$pplogger->setWaferFlag(1);
									$header2->LOT($lotid);
								  $header2->populateMeta();
								  $pplogger->setLot($lotid);
								  $pplogger->setSourceLot($header2->SOURCE_LOT);
									$pplogger->setWafNum($waferno);
								  dpExit( 1, "$bin_td" );
								}
                WriteBinMap($bin_td, $bin);
                unlink $bin_txt;
        }
    }
}

# PROCESS TD FILE
my $TD_txt = convertBinToAscii($TD_bin);
if($TD_txt =~ /Failed to convert.+/i) {
	$pplogger->setWaferFlag(1);
	$header2->LOT($lotid);
	$header2->populateMeta();
	$pplogger->setLot($lotid);
	$pplogger->setSourceLot($header2->SOURCE_LOT);
	$pplogger->setWafNum($waferno);
	dpExit(1, "$TD_txt");
}
INFO("TD_txt = ". $TD_txt);

#my $td = readStdfAscii($TD_txt);
my $td = readStdfAscii_fet_sort($TD_txt, "fet_sort");
if ($td =~ /NO_.+/i) {
	$pplogger->setWaferFlag(1);
	$header2->LOT($lotid);
  $header2->populateMeta();
  $pplogger->setLot($lotid);
  $pplogger->setSourceLot($header2->SOURCE_LOT);
	$pplogger->setWafNum($waferno);
  dpExit( 1, "$td" );
}
my $good_count;
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());
my $header = new_headerLong->new( $parser->stdf2header($td) );
   $header->EQUIP6_ID("$facility");
   $header->CFG_TESTER_TYPE($cfg_tstr_typ);
   $header->PROGRAM_CLASS(1);

unless ( $header->populateMeta ) {
    $wr->noMeta(1);
    $reglim_flg = "N";
}

my $spec_nam = $td->EMIR->{SPEC_NAM};
my $spec_rev = $td->EMIR->{SPEC_REV};

my $model = new_model({dataSource => 'FET'});
   $model->header($header);

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);


	my $TP_path = $hOptions{TPDIR};
	my $regexp = $spec_nam."\.PRN";
	my $TP = undef;
### FIND THE CORRESPONDING PRN FILE for SINGLE
if ($hOptions{TYPE} eq "SINGLE") {
	foreach my $file (glob "$TP_path/*.PRN"){
	  if ($file =~ /$regexp/i){
	     INFO("PRN Found : $file");
	     $TP = $file;
	  }
	}
	unless (defined $TP ) {
		unlink $TP unless (isLogDebug);
	    	dpExit(4,"No TP found in $TP_path by pattern $regexp");
	}
} ###end of finding PRN for SINGLE

# CONVERT PRN FILE TO TP
if ($hOptions{TYPE} eq "SINGLE") {
    $conv_TP = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_fet_prn_cpsort.pl -infile=$TP";

		#elsif ($hOptions{TYPE} eq "QUAD") {
		#    $conv_TP = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_fet_prn_cpsort_quad.pl -infile=$TP";
		#}

		my @output2 = `$conv_TP`;

		if ($?) {
		        print "error in $conv_TP\n";
		        dpExit (1, "Failed to convert PRN file $TP : $!");
		}

		if (@output2[-1] =~ /tp=(.*)/ ) {
			$TP_bin = $1;
			INFO("TP = $TP_bin");
		}
		else {

			dpExit(1, "Failed to convert PRN $conv_TP : " . join("#", @output2 ));
		}
}

my $TP_txt = convertBinToAscii($TP_bin);
if($TP_txt =~ /Failed to convert.+/i) {
	$pplogger->setWaferFlag(1);
#	$header2->LOT($errLot);
#	$header2->populateMeta();
#	$pplogger->setLot($errLot);
#	$pplogger->setSourceLot($header2->SOURCE_LOT);
	$pplogger->{_WAF_NUM} = $waferno;
	dpExit(1, "$TP_txt");
}

INFO("TP_text=$TP_txt");
my $tp      = readStdfAscii_fet_sort($TP_txt, "fet_sort");
if ($tp =~ /NO_.+/i) {
	$pplogger->setWaferFlag(1);
#	$header2->LOT($errLot);
#	$header2->populateMeta();
#	$pplogger->setLot($errLot);
#	$pplogger->setSourceLot($header2->SOURCE_LOT);
	$pplogger->{_WAF_NUM} = $waferno;
	dpExit( 1, "$tp" );
}
my $tests   = $parser->epdr2tests( $tp->EPDR );
my $sbinsTP = $parser->epdr2bins( $tp->EPDR );

my $testCond = [qw/PIN_1 PIN_2 PIN_3 SBIN_NUM HBIN_NUM
        VCC VEE TEMP FREQ PARMTYPE SEQ_NAME
        TCONDS SBIN_NAM HBIN_NAM TEST_TXT
        LOAD_VAL TEST_CAT VIEW_ORD /];
$parser->testConditions_EPDR( $testCond);

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



my $wmap = $model->updateWMap;
if(defined $wmap)   {
    unless ( !$wmap->isEmpty ){
	$wr->wmapIsEmpty(1);
	$reglim_flg = "N";
    }
    unless ( $wmap->confirmed ) {
    	$wr->noWMap(1);
	$reglim_flg = "N";
    }
}
else{
    $wmap = new_wmap;
    $wr->wmapIsEmpty(1) unless ( !$wmap->isEmpty );
    $wr->noWMap(1);
    $reglim_flg = "N";
    $model->wmap($wmap);
}
$model->updateProgram("MAP_PGM");

foreach my $stdfWafer ( @{ $td->wafers } ) {
    my $wafer = new_wafer;
    $wafer->START_TIME( $header->START_TIME );
    $wafer->END_TIME( $header->END_TIME );
    my $waferNum = -1;
    if ( defined $stdfWafer->WIR ) {
        $waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
        $wafer->number($waferNum);
	if ($header->SOURCE_LOT ne "") {
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
	if(defined $stdfWafer->WRR->{GOOD_CNT})
        {
            $good_count =  $stdfWafer->WRR->{GOOD_CNT};
        }
    }
    if ( @{ $stdfWafer->WSBR } ) {
        $wsbins = $parser->sbr2bins( $stdfWafer->WSBR,$good_count );
	mergeBins($wsbins,$sbinsTP);
    }
    if($wsbins ne "")
    {
        $wafer->sbins($wsbins);
    }
    if ( @{ $stdfWafer->WHBR } ) {
         $whbins = $parser->hbr2bins( $stdfWafer->WHBR, $good_count);
    }
    if ($whbins ne "")
    {
        $wafer->hbins($whbins);
    }

    $wafer->tests($tests);
    $wafer->dies( $parser->res2dies_fet_sort( $stdfWafer->res, $tests ) );
    $model->add( 'wafers', $wafer );

}

if($good_count eq "" or $good_count == 0)
{
        $good_count = $td->MRR->{GOOD_CNT};
}

$model->sbins($sbins);
$model->hbins($hbins);
&normalizeToBaseUnit($model);

my $formatter = new_iff_formatter({
        model=>$model,
        writer => $wr});
$formatter->printPar;

# CREATE LIMITS
#if ($reglim_flg eq "Y") {
#    if($model->isLimitNew){
#	$model->buildLimit;
#        $formatter->printLimit;
#        $model->limit->input_file(basename $infile);
#        $model->limit->registerRefdb;
#    }
#}
#else {  # always generate but do not register limit if sandbox
	$model->buildLimit;
	$formatter->printLimit;
	$model->limit->input_file(basename $infile);
#}

unless (isLogDebug) {
    unlink $TD_bin;
    unlink $TD_txt;
    unlink $TP_bin;
    unlink $TP_txt;
}

sub mergeBins{
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

sub WriteBinMap{

my $td_wm = shift;

my $infile = shift;

# create Writer
my $wr_wm = PDF::DpWriter->new(
    {   basename => ( basename $infile),
        ext      => 'iff',
        outdir   =>  $hOptions{OUT},
        gzipIFF  => 'Y'
    }
);

my $ewcr = $td_wm->EWCR;
my $row_cnt = $ewcr->{ROW_CNT};
my $col_cnt = $ewcr->{COL_CNT};
my $wmap_wm = new_wmap;

my $header = new_headerLong->new( $parser->stdf2header($td_wm) );
   $header->EQUIP6_ID($facility);
   $header->CFG_TESTER_TYPE($cfg_tstr_typ);
   $header->PROGRAM_CLASS(4);
   unless ( $header->populateMeta ) {
     $wr->noMeta(1);
   }

my $model_wm = new_model(
   {
        dataSource => 'FET',
        wmap => $wmap_wm,
   }
);
   $model_wm->header($header);

foreach my $stdfWafer ( @{ $td_wm->wafers } ) {
    my $wafer = new_wafer;
    $wafer->START_TIME( $header->START_TIME );
    $wafer->END_TIME( $header->END_TIME );
    my $waferNum = -1;
    if ( defined $stdfWafer->WIR ) {
        $waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
        $wafer->number($waferNum);
	if ($header->SOURCE_LOT ne "") {
		$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
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
    if ( defined $td_wm->EWCR ) {
        $wmap_wm->wf_units($td_wm->EWCR->{WF_UNIT});
        $wmap_wm->wf_size($td_wm->EWCR->{WAFR_SIZ});
        $wmap_wm->flat($td_wm->EWCR->{WF_FLAT});
        $wmap_wm->die_width($td_wm->EWCR->{DIE_WID});
        $wmap_wm->die_height($td_wm->EWCR->{DIE_HT});
        $wmap_wm->center_x($td_wm->EWCR->{CENTER_X});
        $wmap_wm->center_y($td_wm->EWCR->{CENTER_Y});
        $wmap_wm->positive_x($td_wm->EWCR->{POS_X});
        $wmap_wm->positive_y($td_wm->EWCR->{POS_Y});
    }

    $hbins = $parser->hbr2bins( $stdfWafer->WHBR );
    $wafer->hbins($hbins);
    $wafer->tests($tests);
    $wafer->dies( $parser->wmr2dies( $stdfWafer->WMR, $row_cnt, $col_cnt) );
    $model_wm->add( 'wafers', $wafer );

}

my $wmap = $model_wm->updateWMap;
if (defined $wmap) {
    $wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
    unless ( $wmap->confirmed ) {
    $wr->noWMap(1);
    }
}
else {
    $wmap = new_wmap;
    $wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
    $wr->noWMap(1);
    $model_wm->wmap($wmap);
}
$model_wm->updateProgram("MAP_PGM");


my $formatter = new_iff_formatter({
        model=>$model_wm,
        writer => $wr_wm});
        $wr_wm->ext("wm_iff");
        $wr_wm->noMeta($wr->noMeta);
        $wr_wm->noWMap($wr->noWMap);

$formatter->dataItems([qw/x y soft_bin/]);
$formatter->printBinmap;

unless (isLogDebug) {
        unlink $td_wm;
}

unlink $infile;

}


dpExit(0);


#sub getLotFromRawFile {
#
#	my $file = shift;
#	my $lot = "";
#	my $wafer = "";
#	my $in;
#
#	open FH, $file;
#  read FH, $in, 140;     ### Skip unwanted records
#  read FH, $in, 16;
#  $lot = unpack "A16", $in;
#  $lot =~ s/[^0-9A-Za-z]*//g;
#  $lot = uc($lot);
#  #print "\tfull lotid: $lot\n" if $lot ne "";
#  read FH, $in, 83;     ### Skip unwanted records
#  read FH, $in, 15;
#  my $tp_name    = unpack "a15", $in;
#  $tp_name    =~ s/^[^0-9A-Z]+|[^0-9A-Z]+$//gi;
#  ($tp_name,) = split /\./,$tp_name;
#   $tp_name    = uc $tp_name;
#   print "RUNNAME: $tp_name\n";
#
#	close FH;
#	return $lot;
#}
#
#
#sub getWaferFromFile {
#
#	my $file = shift;
#	my $wafer = "";
#	my $in;
#	my @aWaferNum=();
#	my $i;
#
#open FH, $file;
#
#read FH, $in, 1;
#read FH, $in, 1;
#read FH, $in, 2;
#read FH, $in, 40;
#read FH, $in, 40;
#read FH, $in, 16;
#read FH, $in, 40;
#read FH, $in, 16;
#read FH, $in, 1;
#read FH, $in, 3;
#read FH, $in, 2;
#read FH, $in, 2;
#read FH, $in, 2;
#read FH, $in, 1;
#read FH, $in, 1;
#read FH, $in, 2;
#read FH, $in, 2;
#for(my $ii =1; $ii<= 32; $ii++){
#	read FH, $in, 1;
#}
#read FH, $in, 32;
#for (my $ind = 0; $ind < 3; $ind++){
#		read FH, $in, 2;
#
#	}
#read FH, $in, 3;
#read FH, $in, 1;
#read FH, $in, 7;
#read FH, $in, 7;
#read FH, $in, 1;
#read FH, $in, 8;
#read FH, $in, 6;
#read FH, $in, 361;
#for (my $ind = 0; $ind < 200; $ind++){
#		read FH, $in, 2;
#
#	}
#read FH, $in, 500;
#
#
#
##############################
#	read FH, $in, 4;
#	@aWaferNum = unpack "a" x 4, $in;
#	for ($i = 0; $i <= 3; $i++){
#			$aWaferNum[$i] =~ s/[^0-9]//;
#	}
#		if ($aWaferNum[0] ne ""){
#			$wafer = $aWaferNum[0].$aWaferNum[1].$aWaferNum[2].$aWaferNum[3];
#		}
#		else{
#			$wafer = $aWaferNum[1].$aWaferNum[2].$aWaferNum[3];
#		}
#
#
#	#$file = basename($file);
#
#	#my @dump = split /\_|\./, $file;
#  #$dump[0] =~ /^\w+(\d\d)/i;
#  #$wafer   ="$1";
#  print "$wafer\n";
#  close FH;
#
#  return $wafer;
#
#}
#
#sub getTestplanFromFile {
#
#	my $file = shift;
#	my $testplan = "";
#	my $in;
#
#read INPUT, $in, 1;
#read INPUT, $in, 1;
#read INPUT, $in, 2;
#read INPUT, $in, 40;
#read INPUT, $in, 40;
#my $cCDATE = unpack "a40", $in;
#my 	$cCDATE =~ s/^[\n]//;
#
#my 	$SecondProbed = "00";
#my 	$MinuteProbed = "00";
#my 	$HourProbed   = "00";
#my ($MonthProbed, $DayProbed, $YearProbed);
#my $Start_time;
#my $prnt_date;
#my @trash;
#
#	if (index($cCDATE, "\/") >= 1)
#	{
#        ($MonthProbed, $DayProbed, $YearProbed) = split(/\/+/, $cCDATE);
#		#print "mo <$MonthProbed> day <$DayProbed> yr <$YearProbed> date <$cCDATE>\n";
#	}
#	elsif (index($cCDATE, "-") >= 1)
#	{
#		($MonthProbed, $DayProbed, $YearProbed) = split(/-/, $cCDATE);
#
#	}
#	elsif (index($cCDATE, "\\") >= 1)
#	{
#		($MonthProbed, $DayProbed, $YearProbed) = split(/\\/, $cCDATE);
#	}
#	if ($YearProbed eq 0)
#        {
#                $YearProbed = "2000";
#        }
#
#	$MonthProbed =~ s/^[^1-9]//;
#	($YearProbed,@trash) = (split /\./, $YearProbed);
#
#	if($YearProbed >= 1990)
#	{
#		#print "SMHDMY $SecondProbed, $MinuteProbed, $HourProbed, $DayProbed, ($MonthProbed-1), $YearProbed\n";
#        	$Start_time = timegm($SecondProbed, $MinuteProbed, $HourProbed, $DayProbed, ($MonthProbed-1), $YearProbed);
#		#print "$Start_time  Start_time_correct\n";
#
#		$prnt_date = $MonthProbed."/".$DayProbed."/".$YearProbed;
#
#	}
#
#	else
#	{
#		$Start_time = time();
#		print "$Start_time  Start_time\n";
#		$prnt_date = localtime();
#	}
#read INPUT, $in, 16;
#read INPUT, $in, 40;
#read INPUT, $in, 16;
#read INPUT, $in, 3;
#read INPUT, $in, 2;
#read INPUT, $in, 2;
#read INPUT, $in, 2;
#read INPUT, $in, 1;
#read INPUT, $in, 1;
#read INPUT, $in, 2;
#for(my $ii =1; $ii<= 32; $ii++) {
#	read INPUT, $in, 1;
#}
#read INPUT, $in, 32;
#for (my $ind = 0; $ind < 3; $ind++) {
#		read INPUT, $in, 2;
#}
#read INPUT, $in, 3;
#read INPUT, $in, 1;
#read INPUT, $in, 7;
#my $runname = unpack "A7", $in;
#print "OLD RUNNAME: $runname\n";
#($runname,) = split /\./,$runname;
#print "RUNNAME: $runname\n";
#read INPUT, $in, 7;
#read INPUT, $in, 1;
#read INPUT, $in, 8;
#$testplan = unpack "a8", $in;
#print "OLD TESTNAME: $testplan\n";
#($testplan,) = split /\./,$testplan;
#print "TESTNAME: $testplan\n";
#
#if($testplan eq "" && $runname eq ""){
#	print "No TestPlan Specified\n";
##	die "No Testplan Specified";
#}
#
#return $testplan;
#
#
#}

sub getLotWaferTestplanSequence {

	my $file = shift;
	my $in;
	my $lot = "";
	my $dateProbed = "";
	my $wafer = "";
	my $testplan = "";
	my $sequence  = "";
	my @trash;
	my ($MonthProbed, $DayProbed, $YearProbed);
	my $Start_time;
	my $prnt_date;
	my ($cCDATE, $cCLINE, $ind, $i);

	open FH, $file;
	read FH, $in , 44;


	read FH, $in, 40;
#	$cCDATE = unpack "a40", $in;
#	my $cCDATE =~ s/^[\n]//;
#
#	my $SecondProbed = "00";
#	my $MinuteProbed = "00";
#	my $HourProbed   = "00";
#
#	if (index($cCDATE, "\/") >= 1){
#    ($MonthProbed, $DayProbed, $YearProbed) = split(/\/+/, $cCDATE);
#		#print "mo <$MonthProbed> day <$DayProbed> yr <$YearProbed> date <$cCDATE>\n";
#	}	elsif (index($cCDATE, "-") >= 1){
#		($MonthProbed, $DayProbed, $YearProbed) = split(/-/, $cCDATE);
#	}	elsif (index($cCDATE, "\\") >= 1)	{
#		($MonthProbed, $DayProbed, $YearProbed) = split(/\\/, $cCDATE);
#	}
#	if ($YearProbed eq 0){
#  	$YearProbed = "2000";
#  }
#
#	$MonthProbed =~ s/^[^1-9]//;
#	($YearProbed,@trash) = (split /\./, $YearProbed);
#
#	if($YearProbed >= 1990){
#		print "SMHDMY $SecondProbed, $MinuteProbed, $HourProbed, $DayProbed, ($MonthProbed-1), $YearProbed\n";
#        	$Start_time = timegm($SecondProbed, $MinuteProbed, $HourProbed, $DayProbed, ($MonthProbed-1), $YearProbed);
#		print "$Start_time  Start_time_correct\n";
#
#		$prnt_date = $MonthProbed."/".$DayProbed."/".$YearProbed;
#
#	}	else{
#		$Start_time = time();
#		#print "$Start_time  Start_time\n";
#		$prnt_date = localtime();
#	}

	read FH, $in, 16;
	$sequence = unpack "A16", $in;
	$sequence =~ s/^\s|\s$|[^0-9A-Z\-\_]//g;
	$sequence = "" if $cCLINE =~ /\_\d{1,}$/;		### "_#" MEANS PROBE CARD AND NOT SEQ FILE.
							### SEQ FILES ENDS W/ _R#, _SMART, & _LEVEL#

	read FH, $in, 40;#oper
	read FH, $in, 16;
	$lot = unpack "A16", $in;
	$lot =~ s/[^0-9A-Za-z]*//g;
	$lot = uc $lot;

	read FH, $in, 83;     ### Skip unwanted records
 	read FH, $in, 15;
  	$testplan    = unpack "a15", $in;
  	$testplan    =~ s/^[^0-9A-Z]+|[^0-9A-Z]+$//gi;
  	($testplan,) = split /\./,$testplan;
  	$testplan    = uc $testplan;
  	#print "RUNNAME: $testplan\n";

  	read FH, $in, 7;

	read FH, $in, 1;
	read FH, $in, 8;
	my $TESTNAME = unpack "a8", $in;
	#print "OLD TESTNAME: $TESTNAME\n";
	($TESTNAME,) = split /\./,$TESTNAME;
	#print "TESTNAME: $TESTNAME\n";

  	read FH, $in, 6;
	read FH, $in, 361;

	for ($ind = 0; $ind < 200; $ind++){
		read FH, $in, 2;
	}
	read FH, $in, 500;

	read FH, $in, 4;
	my @aWaferNum = unpack "a" x 4, $in;
	for ($i = 0; $i <= 3; $i++){
			$aWaferNum[$i] =~ s/[^0-9]//;
	}
		if ($aWaferNum[0] ne ""){
			$wafer = $aWaferNum[0].$aWaferNum[1].$aWaferNum[2].$aWaferNum[3];
		}
		else{
			$wafer = $aWaferNum[1].$aWaferNum[2].$aWaferNum[3];
		}


	#$file = basename($file);

	#my @dump = split /\_|\./, $file;
  	#$dump[0] =~ /^\w+(\d\d)/i;
  	#$wafer   ="$1";
  	INFO("--LOT=$lot\tWAFER=$wafer\tTP=$testplan\tSEQ=$sequence");
	#print "----$Start_time\t$prnt_date\n";
	close FH;

	my $url = "http://cpntapp07p.fairchildsemi.com/fscSCCamstarWebService/fscTxnCall.asmx/onsGetProductRecipeParam?lot=$lot&recipeParam=product_setup";
	my $response = LWP::UserAgent->new->get($url);

	if ($response->is_success) {
		INFO("Camstar web service is UP!");
		$sequence = extract_seq_name($response->decoded_content);
		INFO("Sequence file from Camstar = $sequence");
	}
	else {
	        ERROR("Camstar web service is DOWN!");
		dpExit(1,$response->status_line);
	}

	if ($lot eq "") {
		$lot = "NO_LOTID";
	}
	if ($wafer eq "") {
		$wafer = "NO_WAFERID";
	}
	if ($testplan eq "") {
		$testplan = "NO_TESTPLAN";
	}
	if ($sequence eq "") {
		$sequence = "NO_SEQUENCE";
	}

	return $lot,$wafer,$testplan,$sequence;


}#end of getDateProbedLotWaferTestplanSequence


#### Not being used subroutine but please do not delete
#sub getDateProbedLotWaferTestplanSequence_QUAD {
#my $file       = shift;
#my $lotid       = "";
#my %td		= ();
#my %sbin	= ();
#my %seq		= ();
#my %param       = ();
#my %alt_param   = ();
#my $td_filename = "";
#my $wm_filename = "";
#my $tp_filename = "";
#my $tp_name     = "";
#my $tp_rev      = 0;
#my $seq_file    = "";
#my $operator    = "";
#my $prober      = "";
#my $test_time   = "";
#my $snnum       = 0;
#my $snsize      = 0;
#my $waferno     = 0;
#my %map		= ();
#my $map_data    = ();
#my $xsize       = 0;
#my $ysize       = 0;
#my $units       = "";
#my $rows        = 0;
#my $cols        = 0;
#my $flat        = 0;
#my $wafer_size  = 0;
#my $node_nam    = "";
#my $node_num    = 0;
#my $prober_id   = "";
#my $probe_card  = "";
#my $load_board  = "";
#my $probed_dice = "";
#my $unprobed_dice = 0;
#my $bad_dice    = 0;
#my $good_dice   = 0;
#my $gross_probes = 0;
#my $xref        = "";
#my $yref        = "";
#my %map_bin_summ = ();
#my $min_x        = "";
#my $max_x	 = "";
#my $min_y	 = "";
#my $max_y	 = "";
#my $param_cnt_per_site = 0;
#my $extra_readings     = 0;
##my $sbin_ref_file      = "$ENV{ENV_CONV_SCRIPT}/fet_sbin_ref.txt";
#my $sbin_ref_file      = "/data/cpsort_fet_quad/TP/fet_sbin_ref.txt";
#my $site_count   = 4;
#my $plant        = uc($ENV{ENV_FACILITY});     #<-- MFT ENV VAR
#my $mft_flag     = ($^O=~/linux/i) ? 1 : 0;    #<-- SET 0=OTHERS; 1=LINUX
#my $envname      = uc($ENV{ENV_NAME});         #<-- GET ENV NAME
#my %month         = (1=>"Jan", 2=>"Feb", 3=>"Mar", 4=>"Apr", 5=>"May", 6=>"Jun", 7=>"Jul", 8=>"Aug", 9=>"Sep", 10=>"Oct", 11=>"Nov", 12=>"Dec");
#
#my $DateTime   = `date '+%m%d%y%H%M%S'`;
#chomp($DateTime);
#
#my $sequence;
#
#
#	##################
#	# LOCAL VARIABLES
#	##################
#	my $in = "";
#
#	#############
#	# PARSE FILE
#	#############
#	open INPUT, $file or die "can't open $file\n";
#
#	### FILE TYPE. ALWAYS "P" FOR "CPR" ###
#	read INPUT, $in, 1;
#        my $CPR = unpack "a", $in;
#	   $CPR = uc($CPR);
#
#		### VALIDATE CPR FILE ###
#		if ($CPR ne "P")
#		{
#			print "$file is not a valid CPR file\n";
#			exit 1;
#		}
#
#	###################
#	# PARSE CPR HEADER
#	###################
#        read INPUT, $in, 1;
#        #$CNUM = unpack "a", $in;
#
#	### NUMWAF ###
#        read INPUT, $in, 2;
#	#$wafer_cnt = unpack "c" x 2, $in;
#	#print "NUMWAF = $wafer_cnt\n";
#
#	### CNAME ###
#        read INPUT, $in, 40;
#	#$CNAME = unpack "A40", $in;
#	#print "CNAME = $CNAME\n";
#
#	### CDATE ###
#        read INPUT, $in, 40;
#        my $CDATE = unpack "a40", $in;
#           $CDATE =~ s/^[^0-9]+|[^0-9]+$//g;
#	#print "CDATE = $CDATE\n";
#
#
#		### CONVERT TIME TO UNIX ###
#		my ($mm,$dd,$yy,$hr,$min,$sec) = split /\/|\s|\.|\\|\-|\:/,$CDATE;
#		if ($mm ne "" && $dd ne "" && $yy ne "" && $hr ne "")
#		{
#			$min = 0 if $min eq "";
#			$sec = 0 if $sec eq "";
#                	$test_time = timegm($sec, $min, $hr, $dd, $mm - 1, $yy);
#		}
#		#print "Date=$mm\/$dd\/$yy $hr\:$min\:$sec\ttimegm=$test_time\n";
#		#print "test_time=$test_time\n";
#
#
#	### CLINE (HOLDS SEQ FILENAME. GET SEQ INFO FROM MAP SINCE IT'S MORE RELIABLE) ###
#        read INPUT, $in, 16;
#        #$seq_file = unpack "a16", $in;
#	#$seq_file =~ s/^[^0-9A-Z]+|[^0-9A-Z]+$//ig;
#	#print "CLINE = $seq_file\n";
#
#
#	### COPER ###
#        read INPUT, $in, 40;
#        #$operator = unpack "A40", $in;
#        #$operator =~ s/[^A-Za-z0-9]+//g;
#	#print "COPER = $operator\n";
#
#	### CLOT ###
#        read INPUT, $in, 16;
#        $lotid = unpack "A16", $in;
#        $lotid =~ s/[^0-9A-Za-z]+//g;
#	$lotid = uc($lotid);
#	#print "lotid = $lotid\n";
#
#
#		###################
#		# TRAP EMPTY LOTID
##		###################
##        	if($lotid eq "")
##        	{
###			print "\ndir=no_lotid";                 ### RETURN BAD SUBDIR FOR MFT
###                	&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_lotid") if $mft_flag==0;
###                	exit 100;
##        	}
#
#
#	### CPROB ###
#        read INPUT, $in, 4;
#        $prober = join "", (unpack "a4", $in);
#        $prober =~ s/[^0-9A-Za-z]+//g;
#        $prober = uc $prober;
#	#print "CPROB = $prober\n";
#
#        read INPUT, $in, 2;
#        #$snnum = char2short($in);
#	#print "SNNUM = $snnum\n";
#
#        read INPUT, $in, 2;
#        #$snsize = char2short($in);
#        #print "SNSIZE: $snsize\n";
#
#        read INPUT, $in, 2;
#        #$NUMDIE = char2short($in);
#	#print "NUMDIE = $NUMDIE\n";
#
#        read INPUT, $in, 1;
#        #$F1SSEG = unpack "c", $in;
#	#print "F1SSEG = $F1SSEG\n";
#
#        read INPUT, $in, 1;
#        #$F1ESEG= unpack "b", $in;
#	#print "F1ESEG = $F1ESEG\n";
#
#        read INPUT, $in, 1;
#        #$WFLAG = unpack "b" x 2, $in;
#	#print "WFLAG = $WFLAG\n";
#
#	### SPARE ###
#	read INPUT, $in, 1;
#
#        read INPUT, $in, 2;
#        #$DARCNT = char2short($in);
#	#print "DARCNT = $DARCNT\n";
#
#        ### DTNUM (CONTAINS TEST# USE IN DATALOG) ###
#        my $chk_order         = 0;
#        my $TEST_NUM;
#        my @test_logged;
#	my %test_cnt_per_site = 0;
#        for(my $ii=1; $ii<= 32; $ii++)
#        {
#                read INPUT, $in, 1;
#                $TEST_NUM = unpack "c", $in;
#
#                if($TEST_NUM != 0)
#                {
#                        push (@test_logged, $TEST_NUM);
#
#                        #### ENSURE PROPER TEST# SEQ ###
#                        if($TEST_NUM < $chk_order)
#                        {
#                                print "Test ordering is incorrect, exiting converter\n";
#                                exit 1;
#                        }
#
#                        $chk_order = $TEST_NUM;
#
#			#####################################
#			# DETERMINE PARAMETER COUNT PER SITE
#			#####################################
#			$test_cnt_per_site{1}++ if $TEST_NUM <= 20;
#			$test_cnt_per_site{2}++ if $TEST_NUM > 20 && $TEST_NUM <= 40;
#			$test_cnt_per_site{3}++ if $TEST_NUM > 40 && $TEST_NUM <= 60;
#			$test_cnt_per_site{4}++ if $TEST_NUM > 60 && $TEST_NUM <= 80;
#			$extra_readings++       if $TEST_NUM > 80;
#                }
#        }
#        #print "site1 test count: $test_cnt_per_site{1}\n";
#        #print "site2 test count: $test_cnt_per_site{2}\n";
#        #print "site3 test count: $test_cnt_per_site{3}\n";
#        #print "site4 test count: $test_cnt_per_site{4}\n";
#        #print "extra test count: $extra_readings\n";
#
#
#        ### DTYPE (32 FUNCTION #'s OF TEST IN DL SORT) ###
#        read INPUT, $in, 32;
#        #@FunctionNumbers = unpack "c" x 32, $in;
#	#print "FuncNum   = @FunctionNumbers\n";
#
#
#	### WFTNUM ###
#        for (my $ind = 0; $ind < 3; $ind++)
#        {
#                read INPUT, $in, 2;
#                #$WFTNUM[$ind] = char2short($in);
#		#print "WFTNUM $ind $WFTNUM[$ind]\n";
#        }
#
#        read INPUT, $in, 3;
#        #@WFSEG = unpack "c" x 3, $in;
#	#print "WFSEG = @WFSEG\n";
#
#	### RUNNAME ###
#	read INPUT, $in, 15;
#	$tp_name    = unpack "a15", $in;
#	$tp_name    =~ s/^[^0-9A-Z]+|[^0-9A-Z]+$//gi;
#        ($tp_name,) = split /\./,$tp_name;
#	$tp_name    = uc $tp_name;
#  #print "RUNNAME: $tp_name\n";
#
#
#	read INPUT, $in, 15;
#	my $TESTNAME    = unpack "a15", $in;
#	$TESTNAME    =~ s/^[^0-9A-Z]+|[^0-9A-Z]+$//gi;
#  ($TESTNAME,) = split /\./,$TESTNAME;
#  #print "TESTNAME: $TESTNAME\n";
#
#
#		#############################
#		# TRAP MISSING TESTPLAN NAME
#		#############################
##        	if($tp_name eq "")
##        	{
###			print "\ndir=missing_testplan";                 ### RETURN BAD SUBDIR FOR MFT
###                	&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/missing_testplan") if $mft_flag==0;
###                	exit 100;
###dpExit (1, "Failed to convert CPR file $infile : NO Testplan name indicated inside the raw file");
##        	}
##
###                ########################
###                # TRAP NON-FETQUAD FILE
###                ########################
###                if ($tp_name !~ /[D|E|F|H|I|K]$/i)
###                {
###                        close(INPUT);
###			print "$file is not a valid fetquad file\n";
###                        exit 1;
###                }
#
#
#		##################################
#		# GET ASSIGNED SBIN PER PARAMETER
#		##################################
##		#if (-e "$ENV{ENV_TP_RAW}/${tp_name}.TPL")
##		#if (-e "/data/edbcp/cpsort_fet_quad/convert/tp_raw/${tp_name}.TPL")
##		if (-e "/data/cpsort_fet_quad/TP/${tp_name}.TPL")
##		{
##			#&get_assigned_sbin_per_param();
##		}
##		else
##		{
#			#print "\ndir=missing_testplan";                 ### RETURN BAD SUBDIR FOR MFT
#      #                  &move_file_to_bad_dir($file, "$ENV{ENV_TP_NOCONV}/missing_testplan") if $mft_flag==0;
#
#			#print "Error: Testplan file $tp_name is not available\n";
#
#			### MOVE BAD FILE TO ENV_TP_NOCONV ###
##                	#system "mv $file $ENV{ENV_TP_NOCONV}";
##
##                	### ADD FILE & MISING TP TO LOG (GET'S E-MAILED DAILY)
##                	#open (MISSING_TP, ">>$ENV{ENV_LOG}/Missing_testplans.txt");
##			open (MISSING_TP, ">>/data/cpsort_fet_quad/log/Missing_testplans.txt");
##                	print MISSING_TP "$file:$tp_name\n";
##                	close(MISSING_TP);
##
##                        exit 100;
##		}
#
#	### SPARE ###
#        read INPUT, $in, 361;
#
#
#        ### PASS/TOTAL COUNTS STRUCTURE: 1 CWCT(100), 2 CWCTPASS 2 CWCTTOT ###
#        for (my $ind = 0; $ind < 200; $ind++)
#        {
#                read INPUT, $in, 2;
#                #$CWCT[$ind] = char2short($in);
#                #print "CWCT = ".$CWCT[$ind]."\n";
#        }
#
#	### CWNAM (CONTAINS WAFER NUMBERS) ###
#        read INPUT, $in, 500;
#        #CWNAM = unpack "a500", $in;
#
#
#
#	#######################
#	# PARSE CPR WAFER DATA
#	#######################
#	# each wafer of data contained within the file:
#        #   1. Individual Wafer Header Record
#        #   2. Wafer Results data including
#        #       a. Bin Map Data
#        #       b. Data log Data.
#	#
#	# Note: cpfetquad collects 1 wafer data per cpr.
#	#
#
#
#	######################
#	# WAFER HEADER RECORD
#	######################
#
#	### UNAME (WAFER NUM) ###
#        read INPUT, $in, 5;
#        $waferno = unpack "a5", $in;
#	$waferno =~ s/^[^0-9]+|[^0-9]+$//g;
#
#		### USE WAFER_NUM FROM THE CPR FILENAME IF THE WAFER_NUM FROM THE UNAME IS INVALID ###
#		my (@dummy)            = split /\//, $file;
#		my ($tmp_lotid, $dump) = split /\_/, $dummy[$#dummy], 2;
#		my $filename_waferno   = substr($tmp_lotid, length($tmp_lotid)-2);
#		#$waferno = $filename_waferno if $waferno != $filename_waferno;
#		$waferno = $filename_waferno if $waferno !~ /^\d{1,2}$/;
#
#
#        ### UFAIL COUNTER ###
#        for (my $ind=0; $ind<250; $ind++)
#        {
#                read INPUT, $in, 2;
#                #$UFAIL[$ind] = char2short($in);
#		#print "UFAIL $ind $UFAIL[$ind]\n";
#        }
#
#	### UTFAIL COUNTER ###
#        for (my $ind=0; $ind<250; $ind++)
#        {
#                read INPUT, $in, 2;
#                #$UTFAIL[$ind] = char2short($in);
#		#print "UTFAIL $ind $UTFAIL[$ind]\n";
#        }
#
#	### UBEST COUNTER ###
#        for (my $ind=0; $ind<25; $ind++)
#        {
#		read INPUT, $in, 3 if $ind == 0;
#                read INPUT, $in, 4 if $ind != 0;
#                #$UBEST[$ind] = bcd2int($in);
#		#print "UBEST $ind $UBEST[$ind]\n";
#        }
#
#
#	### USORT COUNTER ###
#        for (my $ind = 0; $ind < 25; $ind++)
#        {
#                #
#                # Software bin fields from this array will not be used
#		# because they do not fit the EWB model, i.e. in lot S2SWO9477C, soft bin 10 = hard bin 1
#                # This creates problems with the test plan data mapping, etc.
#                # Rodney Cyr, David Fletcher 4/2/2002
#                #
#                read INPUT, $in, 4;
#                #$USORT[$ind] = bcd2int($in);
#                #print "USORT $ind $USORT[$ind]\n";
#	}
#
#        ### UBIN (FOR SBIN SUMMARY) ###
#	my @sbin = ();
#        for (my $ind=1; $ind<=25; $ind++)
#        {
#                read INPUT, $in, 4;
#                #$sbin[$ind]      = bcd2int($in);
#		#$lot_sbin[$ind] += $sbin[$ind];
#		#print "UBIN $ind $sbin[$ind]\n";
#        }
#
#	### UTOT (TOTAL TOUCH-DOWN COUNT) ###
#        read INPUT, $in, 4;
#        my $utot = bcd2int($in);
#	#print "UTOT = $utot\n";
#
#	### 1 OF N CURRENT VAL SAVED ###
#        read INPUT, $in, 2;
#        #$C10FN = char2short($in);
#        #print "C10FN = $C10FN\n";
#
#	### CURRENT DATA PTR ###
#        read INPUT, $in, 2;
#        #$CSNX = char2short($in);
#        #print "CSNX = $CSNX\n";
#
#	### CONSECUTIVE COUNT ###
#	read INPUT, $in,4;
#	#$CCNT = bcd2int($in);
#	#print "CCNT = $CCNT\n";
#
#	### CONSECUTIVE FAIL COUNT ###
#        read INPUT, $in, 2;
#        #$CFCNT = char2short($in);
#        #print "CFCNT = $CFCNT\n";
#
#        read INPUT, $in, 217;
#        #$SPARE1 = unpack "c217", $in;
#	#print "SPARE1 = $SPARE1\n";
#
#
#	### READ 1 DUMMY BYTE ###
#	read INPUT, $in, 1;
#
#
#	##########################################################
#        # READ WAFER DATA (PASS WAFERID AND FILE GENERATION YEAR)
#        ##########################################################
#        my $mapFile;
#        ($sequence,$mapFile)  = &read_map_file($waferno, $lotid, $file);
#
#
#	#####################
#	# READ SEQUENCE FILE
##	#####################
##	if ($seq_file ne "")
##        {
##               #&read_sequence_file();
##        }
##        else
##        {
##		print "\n1dir=no_seq_file";                 ### RETURN BAD SUBDIR FOR MFT
##    #            &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_seq_file") if $mft_flag==0;
##    #            exit 100;
##               #print "Error: No specified sequence file\n";
##        }
#
#
##	#########################
##	# SET CORRECT SITE COUNT
##	#########################
##	if ($seq_file =~ /^Q/i)
##	{
##		$site_count = 4;
##
##
##		##############################################
##                # NOTIFY ENGR IF "TEST SITE PER SITE" DIFFERS
##                ##############################################
##                if ($test_cnt_per_site{1} != $test_cnt_per_site{2} ||
##                    $test_cnt_per_site{1} != $test_cnt_per_site{3} ||
##                    $test_cnt_per_site{1} != $test_cnt_per_site{4} )
##                {
##                        my $msg = "Kindly review testplan \"$tp_name\.\" The number of tests per site is not consistent; site1=$test_cnt_per_site{1}, site2=$test_cnt_per_site{2}, site3=$test_cnt_per_site{3}, site4=$test_cnt_per_site{4}\. Affected file is $file\.";
##			&send_email("CPFETQUAD TESTPLAN ISSUE",$msg);
##		}
##
##	}
##	elsif ($seq_file =~ /^D/i)
##	{
##		$site_count = 2;
##
##
##		##############################################
##                # NOTIFY ENGR IF "TEST SITE PER SITE" DIFFERS
##                ##############################################
##                if ($test_cnt_per_site{1} != $test_cnt_per_site{2})
##                {
##                        my $msg = "Kindly review testplan \"$tp_name\.\" The number of tests per site is not consistent; site1=$test_cnt_per_site{1}, site2=$test_cnt_per_site{2}\. Affected file is $file\.";
##
##			&send_email("CPFETQUAD TESTPLAN ISSUE",$msg);
##                }
##	}
#
#
##	####################
##	# WAFER DATA RECORD
##	####################
##	my $hash_key      = 0;
##	my $rec_counter   = 0;
##	my $seq_count     = keys %seq;
##	my $mismatch_flag = 0;		# 0=NO MISMATCH; 1=MISMATCH BIN RESULT
##
##
##	###########################
##	# PARSE TEST TEST READINGS
##	###########################
##	my ($x, $y);
##	for (my $unit=1; $unit<=$utot; $unit++)
##        {
##
##		### READ UNITS UP TO THE COUNT DEFINED IN THE SEQ FILE ###
##		last if $unit > $seq_count;
##
##                ### X COORDINATE (BOGUS VALUE) ###
##                read INPUT, $in, 1;
##                 $x = unpack "C", $in;
##
##                ### Y COORDINATE (BOGUS VALUE) ###
##                read INPUT, $in, 1;
##                $y = unpack "C", $in;
##                #print "x=$x\ty=$y\n" if $unit == 18;
##
##                ### BIN RESULT FOR THE 4 SITES ###
##                read INPUT, $in, 1;
##                #$bin_result = unpack "c", $in;
##                #$bin_result = $bin_result & 127;
##
##		#####################################################
##		# SPLIT TEST READINGS INTO 2(DUALS) or 4(QUAD) SITES
##		######################################################
##		for (my $site=1; $site<=$site_count; $site++)
##                {
##
##			my %test_readings     = ();
##			my %pf_flag           = ();	### 0=PASS; 1=FAIL
##			my $data_logged_cnt   = 0;	### 0 MEANS NO DATA WAS LOGGED FOR THE SITE
##			my $bin_cpr           = 1;
##			my $last_logged_param = 0;
##			my @test_flag;
##			for (my $param=1; $param<=$test_cnt_per_site{$site}; $param++)
##			{
##				### TEST FLAG ###
##                               	read INPUT, $in, 1;
##                               	@test_flag = split //, unpack "B8", $in;
##				#print "site=$site\tparam=$param\t@test_flag\n";
##
##				### SAVE PASS/FAIL FLAG ###
##				$pf_flag{$param} = $test_flag[4];
##
##				### GET ASSIGNED SBIN IF FAIL FLAG IS SET ###
##				$bin_cpr=$param{$param} if $pf_flag{$param} == 1;
##
##				### TEST READING ###
##                               	read INPUT, $in, 4;
##
###print "\tunit=$unit\tx=$x\ty=$y\tsite=$site\tparam=$param\ttst_flg=@test_flag\tbin=$bin_cpr\treading=".char2float($in)."\n";
###print "\tunit=$unit\tx=$x\ty=$y\tsite=$site\tparam=$param\treading=".char2float($in)."\tbin=$bin_cpr\ttest_flag=$pf_flag{$param}\n";
##
##				### SAVE IF "DATA LOGGED" FLAG IS SET ###
##                                if ($test_flag[2] == 1)
##				{
##					### SAVE TEST READING ###
##                               		$test_readings{$param} = char2float($in);
##
##					### INC DATA LOGGED COUNTER ###
##					$data_logged_cnt++;
##					$last_logged_param=$param;
##				}
##			}
##
##
##			#####################
##			# SKIP TESTS 81 & UP
##			#####################
##			if ($site == $site_count && $extra_readings >= 1 )
##                        {
##                                read INPUT, $in, $extra_readings * 5;
##                        }
##
##
##			#################
##                        # GET CORRECT XY
##                        #################
##                        ($x, $y) = &compute_xy($site, $seq{$unit}{X}, $seq{$unit}{Y});
##
##
##			##############################
##			# PROCEED IF W/ TEST READINGS
##			##############################
##			next unless $data_logged_cnt > 0;
##
##
##			#####################################
##                        # EXCLUDE TEST RESULTS OF INKED DICE
##                        #####################################
##                        next unless $map{$x}{$y} =~ /\d+/;
##
##			#############################################
##			# USE ALT BIN ON THE FF. CONDITION:
##			# 1) NON-INKED DIE
##			# 2) TEST FAIL FLAG IS NOT SET
##			# 3) LAST_LOGGED_PARAM != MAX_PARAM_COUNT
## 			# 4) ALT_BIN VALUE IS DEFINED
##			#############################################
##			my $alt_bin_key = $last_logged_param + 1;
##			if ($last_logged_param<$param_cnt_per_site && $bin_cpr == 1 && exists $alt_param{$alt_bin_key})
##			{
##				$bin_cpr = $alt_param{$alt_bin_key};
##			}
##
###print "\nunit=$unit\tsite=$site\tx=$x\ty=$y\tdl=$data_logged_cnt\tll=$last_logged_param\tbin=$bin_cpr\tmap=$map{$x}{$y}\tmis=$mismatch_flag\n";
##
##
##			######################################################
##                        # FLAG IF THERE'S A MISMATCH BET MAP & CPR BIN RESULT
##                        ######################################################
##                        $mismatch_flag=1 if $map{$x}{$y} == 1 && $bin_cpr != 1;
##                        $mismatch_flag=1 if $map{$x}{$y} == 0 && $bin_cpr == 1;
##
##
##			#######################################################################
##			# CAPTURE BIN RESULT FROM CPR IF BOTH MAPXY & MISMATCH_FLAG ARE ZEROES
##			#######################################################################
##			if ($map{$x}{$y} == 0 && $mismatch_flag == 0)
##			{
##				$map{$x}{$y} = $bin_cpr;
##			}
##
##	#exit if $mismatch_flag==1;
##	#exit if $unit > 18;
##
##			##########################
##                        # BIN SUMMARY FOR TD_STDF
##                        ##########################
##                        if ($sbin{$bin_cpr} eq "")
##                        {
##                                $sbin{$bin_cpr} = 1;
##                        }
##                        else
##                        {
##                                $sbin{$bin_cpr}++;
##                        }
##
##			######################
##			# STORE TEST READINGS
##			######################
##			$td{$hash_key++} =
##			{
##				UNIT     => $unit,
##				SITE     => $site,
##				BIN      => $bin_cpr,
##				X	 => $x,
##				Y	 => $y,
##				PF_FLAG  => {%pf_flag},
##				READINGS => {%test_readings},
##			};
##		}
##		$rec_counter++;
##
##
##		### RECORD STORAGE ALLOCATION IS ALWAYS @ 1536 BYTES. SKIP UNUSED PORTION ###
##                if ($rec_counter == $snnum)
##                {
##                	#print "skipping record: rec_counter is @ $rec_counter\n";
##                        read INPUT, $in, 1536 - ($snnum * $snsize);
##                        $rec_counter = 0;
##                }
##	}
#	close(INPUT);
#
#
##	### DELETE FILE IF IT HAS NO DATA ###
##	if (keys %td == 0)
##	{
##		print "\ndir=no_part_data";             ### RETURN BAD SUBDIR FOR MFT
##                &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_part_data") if $mft_flag==0;
##                exit 100;
##
##		#unlink $file;
##		#exit 1;
#   #}
#
#	return $lotid,$waferno,$tp_name,$sequence,$mapFile;
#} #END of method

#######################
# DATA TYPE CONVERSION
#######################
#sub char2short
#{
#        my ($IN) = @_;
#        my @b = unpack "c" x 2, $IN;
#        #my $ret = unpack "S", (pack "cc", $b[1], $b[0]) if $mft_flag==0;
#        #$ret = unpack "S", (pack "cc", $b[0], $b[1]) if $mft_flag==1;
#        return $ret;
#}
#
#sub char2int
#{
#        my ($IN) = @_;
#        my @b = unpack "c" x 4, $IN;
#        #my $ret = unpack "i", (pack "cccc", $b[3], $b[2], $b[1], $b[0]) if $mft_flag==0;
#        #$ret = unpack "i", (pack "cccc", $b[0], $b[1], $b[2], $b[3]) if $mft_flag==1;
#        return $ret;
#
#}
#
#sub char2float
#{
#        my ($IN) = @_;
#        my @b = unpack "c" x 4, $IN;
#        #my $ret = unpack "f", (pack "cccc", $b[3], $b[2], $b[1], $b[0]) if $mft_flag==0;
#        #$ret = unpack "f", (pack "cccc", $b[0], $b[1], $b[2], $b[3]) if $mft_flag==1;
#        return $ret;
#}

sub bcd2int
{
        my ($IN) = @_;
        my @b = unpack  "CCCC", $IN;
        my $sTmp ="";

        #    b3         b2         b1         b0
        #  NU = not used
        # 0000|0000, 0000|0000, 0000|0000, 0000|0000
        #
        $sTmp = pack "aaaaa", $b[3] & 0x0F, $b[2] >> 4, $b[2] & 0x0F, $b[1] >> 4, $b[1] & 0x0F,$b[0] >>  4, $b[0] & 0x0F;
        my $i = $sTmp * 1;
        return $i;
}

sub read_map_file{

	my $waferid        = shift;
	my $lotid = shift;
	my $file = shift;
	   #$waferid        = substr($waferid, length($waferid) - 3);
	my $loc_lotid      = (length($lotid) > 7) ? substr($lotid,length($lotid)-6) : $lotid;
        #my $arch_dir       = "/archives/edbcp/cpsort_wmap_sep";
	my $arch_dir       = "/archives-ASIA/edbcp/cpsort_wmap_sep";
	my $file_to_search = "${loc_lotid}_0{0,2}${waferid}_.+\.MAP.+";
	my @found_maps     = ();
	my $map_file       = "";
	my $dir_to_search  = "";
	my %month         = (1=>"Jan", 2=>"Feb", 3=>"Mar", 4=>"Apr", 5=>"May", 6=>"Jun", 7=>"Jul", 8=>"Aug", 9=>"Sep", 10=>"Oct", 11=>"Nov", 12=>"Dec");

#$file_to_search = "PW00026781_011_FETQUAD_PW00026781_20150811125428U_08_6_011.MAP.gz";
#push(@found_maps,$file_to_search);

	#######################################
	# CHECK MAP IN 4 DIFF FOLDER LOCATIONS
	#######################################

	### 1) SEARCH $ENV_ARCHIVE ###
	#if ($#found_maps == -1)
	#{
	#	$dir_to_search  = "/archives/edbcp/cpsort_wmap_sep";
		#find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
	#}

	### 2) SEARCH /archives FOR CURRENT YEAR. USE DISPATCH YEAR ###
	#if ($#found_maps == -1)
	#{
	#	my (@dummy) = split /\//   , $file;
	#        (@dummy) = split /\_|\./, $dummy[$#dummy];
	#	$year    = substr($dummy[$#dummy - 1],4,4);	### GET DISPATCHED YEAR


		### USE CURRENT YEAR IF DISPATCH YEAR IS INVALID ###
	#	if ($year < 1999 && $year > 3000)
	#	{
	#		my $year   = `date '+%Y'`;
	#		chomp($year);
	#	}
	#	$dir_to_search = "${arch_dir}/${year}";
	#	find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
	#}

	### 3) SEARCH /archives FOR PREV YEAR ###
	#if ($#found_file == -1)
    	#{
	#	$year          -= 1;
	#	$dir_to_search = "${arch_dir}/${year}";
	#	find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
    	#}

	### 4) SEARCH /archives FOR NEXT YEAR ###
	#if ($#found_maps == -1)
	#{
	#	$year         += 2;
	#	$dir_to_search = "${arch_dir}/${year}";
	#	find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
	#}
	if ($#found_maps == -1)
        {
                my (@dummy) = split /\//   , $file;
                (@dummy) = split /\_|\./, $dummy[$#dummy];
                my $year    = substr($dummy[$#dummy - 1],4,4);     ### GET DISPATCHED YEAR
                my $mon     = substr($dummy[$#dummy - 1],2,2);
		$mon        =~ s/^0//;
		my $arc_mon = $month{$mon};

                ### USE CURRENT YEAR IF DISPATCH YEAR IS INVALID ###
                if ($year < 1999 && $year > 3000)
                {
                        my $year   = `date '+%Y'`;
                        chomp($year);
                }
                $dir_to_search = "${arch_dir}/${year}/${arc_mon}";
                find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);

		### SEARC PREVIOUS MONTH IF MAP IS NOt FOUND
		if ($#found_maps == -1){
			$mon = $mon - 1;
			$arc_mon = $month{$mon};
			$dir_to_search = "${arch_dir}/${year}/${arc_mon}";
			find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
		}
        }

	###########################################################
	# SELECT THE CORRECT MAP (WITH "SYSTEM ID  PROBERxx" DATA)
	###########################################################
	foreach my $found_map(@found_maps)
	{
		my $cp_dir  = "$ENV{DPDATA}/data/cpsort_fet_quad/temp";
		my $cp_file = basename($found_map);
		my $cp_map  = "${cp_dir}/${cp_file}";
		copy($found_map,$cp_map) or die "Failed to copy file: $!\n";
		#$found_map = EDBUtil::doUncompress($found_map) if $found_map =~ /\.gz/;
		#$found_map = &doUncompress($found_map) if $found_map =~ /\.gz/;
		$cp_map = &doUncompress($cp_map) if $cp_map =~ /\.gz/;

		#open MAP, $found_map or die "can't open map ${found_map}. $!\n";
		#print "MAP FILE=$cp_map\n";
		open MAP, $cp_map or die "can't open map ${cp_map}. $!\n";
		my $line;
		while(chomp($line=<MAP>))
		{
			if ($line =~ /SYSTEM ID/)
			{
				#$map_file = $found_map if $line =~ /Probe/i;
				$map_file = $cp_map if $line =~ /Probe/i;
				#print "correct map file $map_file\n";
				last;
			}
		}
		close(MAP);
		#$found_map = EDBUtil::doCompress($found_map) if $map_file eq "";
		#$found_map = &doCompress($found_map) if $map_file eq "";


		### EXIT IF MAP IS FOUND ###
		last if $map_file ne "";
	}


#	############################
#        # CHECK IF MAP FILE EXISTS
#        ############################
#        if ($map_file eq "")
#        {
#                ### LOG MISSING SEQ FILES ###
##                #open LOG, ">>$ENV{ENV_LOG}/no_map_file.log" or die "can't create no_map_file.log file\n" if $mft_flag==0;
##		open LOG, ">>/data/cpsort_fet_quad/log/no_map_file.log" or die "can't create no_map_file.log file\n";
##                print LOG "${lotid}\,${waferid}\n" if $mft_flag==0;
##                #close(LOG) if $mft_flag==0;
#
#                ### PRINT ERROR MSG ###
#                #print STDERR "Map file not available: ${lotid}\_${waferid}\n";
#
#                ### MOVE FILE TO BAD DIR ###
#                #system "mv $file $ENV{ENV_CONV_BAD}/no_map/.";
#                #exit 1;
#
#		print "\ndir=no_wmap_file";             ### RETURN BAD SUBDIR FOR MFT
#    #            &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_wmap_file") if $mft_flag==0;
#    #            exit 100;
#        }


	#################
	# READ MAP FILE
	#################
	my $xy_flag = "N";  ### Y=MEANS XY BIN RESULT
	my $line;
	my $seq_file;
	open MAP, "$map_file" or die " Failed to open map file $map_file. $!\n";
  while($line=<MAP>) {
       chomp($line);
			my (@dummy)  = split /\t+/, $line;
			$dummy[0] =~ s/^\s+|\s$//g;
			$dummy[1] =~ s/^\s+|\s$//g;
			$dummy[2] =~ s/^\s+|\s$//g;
			$dummy[3] =~ s/^\s+|\s$//g;
		if ($dummy[0] eq "CMAP"){
    	$seq_file = uc($dummy[1]);
    	#$sequence = $seq_file;
    }
  }
#		if ($dummy[0] =~ /\[WAFERMAP\]/i) {
#        my $xy_flag = "Y";
#    } elsif ($dummy[0] =~ /\[EXT\s+WAFERMAP\]/i){
#      my $xy_flag = "N";
#    } elsif ($dummy[0] =~ /X\-?\d+Y\-?\d+/ && $xy_flag eq "Y"){
#			my (@dump) = split /X|Y|\t+/, $line;
#                        $map{$dump[1]}{$dump[2]} = $dump[3];
#
#			if ($dump[1] =~ /\d/)
#			{
#				$min_x = $dump[1] if $min_x eq "" || $dump[1] < $min_x;
#                        	$max_x = $dump[1] if $max_x eq "" || $dump[1] > $max_x;
#			}
#
#			if ($dump[2] =~ /\d/)
#			{
#				$min_y = $dump[2] if $min_y eq "" || $dump[2] < $min_y;
#                        	$max_y = $dump[2] if $max_y eq "" || $dump[2] > $max_y;
#			}
#		}
#		elsif ($dummy[0] eq "CMAP")
#                {
#                        $seq_file = uc($dummy[1]);
#                }
#		elsif ($dummy[0] =~ /OPERATOR/i)
#                {
#			$operator = uc($dummy[1]);
#		}
#		elsif ($dummy[0] =~ /XSIZE/i)
#		{
#			$xsize = $dummy[1];
#		}
#		elsif ($dummy[0] =~ /YSIZE/i)
#		{
#			$ysize = $dummy[1];
#		}
#		elsif ($dummy[0] =~ /UNITS/i)
#                {
#			$units = $dummy[1];
#                }
#		elsif ($dummy[0] =~ /ROWS/i)
#                {
#			$rows = $dummy[1];
#                }
#                elsif ($dummy[0] =~ /COLS/i)
#                {
#			$cols = $dummy[1];
#                }
#                elsif ($dummy[0] =~ /FLAT/i)
#                {
#			$flat = $dummy[1];
#			if ( $flat == 0 || $flat == 360 )
#                        { $flat = "U" ;}
#                        elsif ( $flat == 90 )
#                        { $flat = "R" ; }
#                        elsif ( $flat == 180 )
#                        { $flat = "D" ; }
#                        elsif ( $flat == 270 )
#                        { $flat = "L" ; }
#                }
#                elsif ($dummy[0] =~ /WAFER SIZE/i)
#                {
#			$wafer_size = $dummy[1]/10;           #<-- CONVERT FROM MM TO CM
#                }
#		elsif ($dummy[0] =~ /REF DIE/i)
#                {
#			($xref,$yref) = split /\,/, $dummy[1];
#		}
#                elsif ($dummy[0] =~ /TEST SYS/i)
#                {
#			$node_nam = $dummy[1];
#                }
#                elsif ($dummy[0] =~ /TEST STA/i)
#                {
#			$node_num = $dummy[1]||0;
#                }
#                elsif ($dummy[0] =~ /SYSTEM ID/i)
#                {
#			$prober_id = $dummy[1];
#                }
#		elsif ($dummy[0] =~ /PROBECARD/i)
#                {
#			$probe_card = $dummy[1];
#                }
#                elsif ($dummy[0] =~ /LOADBOARD/i)
#                {
#			$load_board = $dummy[1];
#                }
#                elsif ($dummy[0] =~ /PROBED DICE/i)
#                {
#			$probed_dice = $dummy[1];
#                }
#                elsif ($dummy[0] =~ /BIN\s+0/i)
#                {
#			$bad_dice = $dummy[1];
#               	}
#                elsif ($dummy[0] =~ /PASS DICE/i)
#                {
#			$good_dice = $dummy[1];
#                }
#                elsif ($dummy[0] =~ /GROSS\s+PROBES/i)
#                {
#			$gross_probes = $dummy[1];
#                }
#        }
       close(MAP);
       #print "SEQ FILE = $seq_file\n";

#
#
#	###########
#        # GZIP MAP
#        ###########
#	#$map_file = EDBUtil::doCompress($map_file);
#	#$map_file = &doCompress($map_file);
unlink $map_file;

#
#	##########################
#        # CONVERT DIE WIDTH TO CM
#        ##########################
#        if ((($xsize/10)*$cols) > $wafer_size)
#        {
#                #print "converting width from mils to cm\n";
#                $xsize = $xsize / 393.7 ; # convert from mils to cm
#        }
#        else
#        {
#                #print "converting width from millimeters to cm \n";
#                $xsize = $xsize / 10; # convert millimeters to cm
#        }
#
#	###########################
#        # CONVERT DIE HEIGHT TO CM
#        ###########################
#	if ((($ysize/10)*$rows) > $wafer_size)
#        {
#                #print "converting height from mils to cm\n";
#                $ysize = $ysize / 393.7 ; # convert mils to cm
#        }
#        else
#        {
#                #print "converting height from millimeters to cm \n";
#                $ysize = $ysize / 10; # convert millimeters to cm
#        }
   return $seq_file, $map_file;
}###END of read map file


sub checkCorrectMapExistAndGetSequenceName{

	my $waferid        = shift;
	my $lotid = shift;
	my $file = shift;
	   #$waferid        = substr($waferid, length($waferid) - 3);
	my $loc_lotid      = (length($lotid) > 7) ? substr($lotid,length($lotid)-6) : $lotid;
        #my $arch_dir       = "/archives/edbcp/cpsort_wmap_sep";
	my $arch_dir       = "/archives/edbcp/cpsort_wmap_sep";
	my $file_to_search = "${loc_lotid}_0{0,2}${waferid}_.+\.MAP.+";
	my @found_maps     = ();
	my $map_file       = "";
	my $dir_to_search  = "";
	my %month         = (1=>"Jan", 2=>"Feb", 3=>"Mar", 4=>"Apr", 5=>"May", 6=>"Jun", 7=>"Jul", 8=>"Aug", 9=>"Sep", 10=>"Oct", 11=>"Nov", 12=>"Dec");

#$file_to_search = "PW00026781_011_FETQUAD_PW00026781_20150811125428U_08_6_011.MAP.gz";
#push(@found_maps,$file_to_search);

	#######################################
	# CHECK MAP IN 4 DIFF FOLDER LOCATIONS
	#######################################

	### 1) SEARCH $ENV_ARCHIVE ###
	#if ($#found_maps == -1)
	#{
	#	$dir_to_search  = "/archives/edbcp/cpsort_wmap_sep";
		#find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
	#}

	### 2) SEARCH /archives FOR CURRENT YEAR. USE DISPATCH YEAR ###
	#if ($#found_maps == -1)
	#{
	#	my (@dummy) = split /\//   , $file;
	#        (@dummy) = split /\_|\./, $dummy[$#dummy];
	#	$year    = substr($dummy[$#dummy - 1],4,4);	### GET DISPATCHED YEAR


		### USE CURRENT YEAR IF DISPATCH YEAR IS INVALID ###
	#	if ($year < 1999 && $year > 3000)
	#	{
	#		my $year   = `date '+%Y'`;
	#		chomp($year);
	#	}
	#	$dir_to_search = "${arch_dir}/${year}";
	#	find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
	#}

	### 3) SEARCH /archives FOR PREV YEAR ###
	#if ($#found_file == -1)
    	#{
	#	$year          -= 1;
	#	$dir_to_search = "${arch_dir}/${year}";
	#	find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
    	#}

	### 4) SEARCH /archives FOR NEXT YEAR ###
	#if ($#found_maps == -1)
	#{
	#	$year         += 2;
	#	$dir_to_search = "${arch_dir}/${year}";
	#	find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
	#}
	if ($#found_maps == -1){
  		my (@dummy) = split /\//   , $file;
    		(@dummy) = split /\_|\./, $dummy[$#dummy];
    		my $year    = substr($dummy[$#dummy - 1],4,4);     ### GET DISPATCHED YEAR
    		my $mon     = substr($dummy[$#dummy - 1],2,2);
		$mon        =~ s/^0//;
		my $arc_mon = $month{$mon};

    		### USE CURRENT YEAR IF DISPATCH YEAR IS INVALID ###
    		if ($year < 1999 && $year > 3000){
    			my $year   = `date '+%Y'`;
      			chomp($year);
    		}

    		$dir_to_search = "${arch_dir}/${year}/${arc_mon}";
    		find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);

		### SEARC PREVIOUS MONTH IF MAP IS NOt FOUND
		if ($#found_maps == -1){
			$mon = $mon - 1;
			$arc_mon = $month{$mon};
			$dir_to_search = "${arch_dir}/${year}/${arc_mon}";
			find(sub { push(@found_maps, $File::Find::name) if /$file_to_search/i;}, $dir_to_search);
		}
		if ($#found_maps == -1) {
			return;
		}
  	}

	###########################################################
	# SELECT THE CORRECT MAP (WITH "SYSTEM ID  PROBERxx" DATA)
	###########################################################
	foreach my $found_map(@found_maps){
		my $cp_dir  = "$ENV{DPDATA}/data/cpsort_fet_quad/temp";
		my $cp_file = basename($found_map);
		my $cp_map  = "${cp_dir}/${cp_file}";

		if ($found_map ne "") {
			copy($found_map,$cp_map) or die "Failed to copy file: $!\n";
			$cp_map = &doUncompress($cp_map) if $cp_map =~ /\.gz/;

		}


    		if ($cp_map ne "") {
    			open MAP, $cp_map or die "can't open map ${cp_map}. $!\n";
			my $line;
			while(chomp($line=<MAP>)){
				if ($line =~ /SYSTEM ID/){
					$map_file = $cp_map if $line =~ /Probe/i;
					last;
				}
			}
			close(MAP);
			### EXIT IF MAP IS FOUND ###
			last if $map_file ne "";
    		}

	}



	#################
	# READ MAP FILE
	#################
	#my $xy_flag = "N";  ### Y=MEANS XY BIN RESULT
	my $line;
	my $seq_file;
	if($map_file ne "") {
		open MAP, "$map_file" or die " Failed to open map file $map_file. $!\n";
	  	while($line=<MAP>) {
	       	chomp($line);
		my (@dummy)  = split /\t+/, $line;
		$dummy[0] =~ s/^\s+|\s$//g;
		$dummy[1] =~ s/^\s+|\s$//g;
		$dummy[2] =~ s/^\s+|\s$//g;
		$dummy[3] =~ s/^\s+|\s$//g;
		if ($dummy[0] eq "CMAP"){
	    		$seq_file = uc($dummy[1]);
	    		#$sequence = $seq_file;
	    		last;
	    	}

	  	}
	  	close MAP;
	}


	$map_file = &doCompress($map_file);
	unlink $map_file;


   	return $map_file, $seq_file;
}# END of checkCorrectMapExistAndGetSequenceName

###############################
# Uncompress a file
###############################
sub doUncompress
{
  	my $file = shift;
  	my @values;
  	return $file if($file !~ /\.Z$|\.gz$/i);
  	my $pid = open3(\*GZIP_IN, \*GZIP_OUT, \*GZIP_ERR, "/usr/bin/gzip -vdf $file");
  	waitpid( $pid, 0 );
  	while(<GZIP_ERR>)
  	{
    		@values = split/\s+/;
  	}
  	close GZIP_IN;
  	close GZIP_OUT;
  	close GZIP_ERR;

  	return $values[$#values];
}

###############################
# Compress a file
###############################
sub doCompress
{
  	my $file = shift;
  	my @values;
  	return $file if($file =~ /\.Z$|\.gz$/i);
  	my $pid = open3(\*GZIP_IN, \*GZIP_OUT, \*GZIP_ERR, "/usr/bin/gzip --force -v $file");
  	waitpid( $pid, 0 );
  	while(<GZIP_ERR>)
  	{
    		@values = split/\s+/;
  	}
  	close GZIP_IN;
  	close GZIP_OUT;
  	close GZIP_ERR;

  	return $values[$#values];
}

sub getLotWaferTestplanName {

	my $file = shift;
	my $in;
	my $lotid;
	my $waferno;
	my $tp_name;

	open INPUT, $file or die "can't open $file\n";

	### FILE TYPE. ALWAYS "P" FOR "CPR" ###
	read INPUT, $in, 1;
  	read INPUT, $in, 1;
  	read INPUT, $in, 2;
	read INPUT, $in, 40;
	read INPUT, $in, 40;
  	read INPUT, $in, 16;
  	read INPUT, $in, 40;
  	read INPUT, $in, 16;
  	$lotid = unpack "A16", $in;
  	$lotid =~ s/[^0-9A-Za-z]+//g;
	$lotid = uc($lotid);
	#print "lotid = $lotid\n";

	#prober
  	read INPUT, $in, 4;
  	#$prober = join "", (unpack "a4", $in);
  	#$prober =~ s/[^0-9A-Za-z]+//g;
  	#$prober = uc $prober;
	#print "CPROB = $prober\n";

  	read INPUT, $in, 2;
  	#$snnum = char2short($in);
	#print "SNNUM = $snnum\n";

  	read INPUT, $in, 2;
  	#$snsize = char2short($in);
  	#print "SNSIZE: $snsize\n";

  	read INPUT, $in, 2;
  	#$NUMDIE = char2short($in);
	#print "NUMDIE = $NUMDIE\n";

  	read INPUT, $in, 1;
  	#$F1SSEG = unpack "c", $in;
	#print "F1SSEG = $F1SSEG\n";

  	read INPUT, $in, 1;
  	#$F1ESEG= unpack "b", $in;
	#print "F1ESEG = $F1ESEG\n";

  	read INPUT, $in, 1;
  	#$WFLAG = unpack "b" x 2, $in;
	#print "WFLAG = $WFLAG\n";
	### SPARE ###

	read INPUT, $in, 1;
  	read INPUT, $in, 2;
  	#$DARCNT = char2short($in);
	#print "DARCNT = $DARCNT\n";

  	### DTNUM (CONTAINS TEST# USE IN DATALOG) ###
	#  my $chk_order         = 0;
	#  my $TEST_NUM;
	#  my @test_logged;
	# my %test_cnt_per_site = 0;
	#
  	for(my $ii=1; $ii<= 32; $ii++){
  		read INPUT, $in, 1;
		#$TEST_NUM = unpack "c", $in;
		#if($TEST_NUM != 0) {
    			#push (@test_logged, $TEST_NUM);
      			#### ENSURE PROPER TEST# SEQ ###
      			#if($TEST_NUM < $chk_order){
               		#print "Test ordering is incorrect, exiting converter\n";
               	        #exit 1;
               		#}

               		#$chk_order = $TEST_NUM;

			#####################################
			# DETERMINE PARAMETER COUNT PER SITE
			#####################################
			#$test_cnt_per_site{1}++ if $TEST_NUM <= 20;
			#$test_cnt_per_site{2}++ if $TEST_NUM > 20 && $TEST_NUM <= 40;
			#$test_cnt_per_site{3}++ if $TEST_NUM > 40 && $TEST_NUM <= 60;
			#$test_cnt_per_site{4}++ if $TEST_NUM > 60 && $TEST_NUM <= 80;
			#$extra_readings++       if $TEST_NUM > 80;
		#}
  	}
        #print "site1 test count: $test_cnt_per_site{1}\n";
        #print "site2 test count: $test_cnt_per_site{2}\n";
        #print "site3 test count: $test_cnt_per_site{3}\n";
        #print "site4 test count: $test_cnt_per_site{4}\n";
        #print "extra test count: $extra_readings\n";

   	### DTYPE (32 FUNCTION #'s OF TEST IN DL SORT) ###
   	read INPUT, $in, 32;
   	#@FunctionNumbers = unpack "c" x 32, $in;
	#print "FuncNum   = @FunctionNumbers\n";

   	### WFTNUM ###
   	for (my $ind = 0; $ind < 3; $ind++){
    		 read INPUT, $in, 2;
       		#$WFTNUM[$ind] = char2short($in);
		#print "WFTNUM $ind $WFTNUM[$ind]\n";
   	}

   	read INPUT, $in, 3;
   	#@WFSEG = unpack "c" x 3, $in;
	#print "WFSEG = @WFSEG\n";

	### RUNNAME ###
	read INPUT, $in, 15;
	$tp_name    = unpack "a15", $in;
	$tp_name    =~ s/^[^0-9A-Z]+|[^0-9A-Z]+$//gi;
        ($tp_name,) = split /\./,$tp_name;
	$tp_name    = uc $tp_name;
  	#print "RUNNAME: $tp_name\n";


	read INPUT, $in, 15;
	my $TESTNAME    = unpack "a15", $in;
	$TESTNAME    =~ s/^[^0-9A-Z]+|[^0-9A-Z]+$//gi;
  	($TESTNAME,) = split /\./,$TESTNAME;
  	#print "TESTNAME: $TESTNAME\n";

	### SPARE ###
  	read INPUT, $in, 361;


   	### PASS/TOTAL COUNTS STRUCTURE: 1 CWCT(100), 2 CWCTPASS 2 CWCTTOT ###
   	for (my $ind = 0; $ind < 200; $ind++){
      		read INPUT, $in, 2;
                #$CWCT[$ind] = char2short($in);
                #print "CWCT = ".$CWCT[$ind]."\n";
   	}

	### CWNAM (CONTAINS WAFER NUMBERS) ###
  	read INPUT, $in, 500;
  	#CWNAM = unpack "a500", $in;

	######################
	# WAFER HEADER RECORD
	######################

	### UNAME (WAFER NUM) ###
  	read INPUT, $in, 5;
  	$waferno = unpack "a5", $in;
	$waferno =~ s/^[^0-9]+|[^0-9]+$//g;

	### USE WAFER_NUM FROM THE CPR FILENAME IF THE WAFER_NUM FROM THE UNAME IS INVALID ###
	my (@dummy)            = split /\//, $file;
	my ($tmp_lotid, $dump) = split /\_/, $dummy[$#dummy], 2;
	my $filename_waferno   = substr($tmp_lotid, length($tmp_lotid)-2);
	#$waferno = $filename_waferno if $waferno != $filename_waferno;
	$waferno = $filename_waferno if $waferno !~ /^\d{1,2}$/;


 	close INPUT;

	if ($lotid eq "") {
		$lotid = "NO_LOTID";
	}
	if ($waferno eq "") {
		$waferno = "NO_WAFERID";
	}
	if ($tp_name eq "") {
		$tp_name = "NO_TESTPLAN";
	}
	return $lotid,$waferno,$tp_name;

} ###END of getLotWaferTestplanName method


sub testCPRSingle() {
	my $infile = shift;
	my $seqLoc1 = shift;
	#my $seqLoc2 = shift;
	my ($errLot,$errWafer,$errTestplan,$errSequence,$errTPL,$mapFile) = &getLotWaferTestplanSequence($infile);
		if (length($errWafer) < 2 && $errWafer < 10) {
			$errWafer = "0"."$errWafer";
		}
		INFO("LOT=$errLot||WAFER=$errWafer||TP=$errTestplan||SEQ=$errSequence||MAPFILE=$mapFile||TPL=$errTPL");
		#$seqLoc1 = "/data/cpsort_fet/TP/";
		#$seqLoc2 = "/data/cpsort_fet/TP/Old/";
		#print "==================LOT=$errLot\n";
		if($errLot eq "NO_LOTID") {
			$pplogger->setLot($errLot);
			$header2->LOT($errLot);
			$header2->populateMeta();
			$pplogger->setSourceLot($header2->SOURCE_LOT);
			#$pplogger->setWafNum($errWafer);
			$pplogger->{_WAF_NUM} = $errWafer;
			dpExit(1,"$errLot indicated inside the file");
		}
		if($errWafer eq "NO_WAFERID") {
			$pplogger->setLot($errLot);
			$header2->LOT($errLot);
			$header2->populateMeta();
			$pplogger->setSourceLot($header2->SOURCE_LOT);
			#$pplogger->setWafNum($errWafer);
			$pplogger->{_WAF_NUM} = $errWafer;
			dpExit(1,"$errWafer indicated inside the file");
		}
		if ($errTestplan eq "NO_TESTPLAN") {
			$pplogger->setLot($errLot);
			$header2->LOT($errLot);
			$header2->populateMeta();
			$pplogger->setSourceLot($header2->SOURCE_LOT);
			#$pplogger->setWafNum($errWafer);
			$pplogger->{_WAF_NUM} = $errWafer;
			dpExit(1,"$errTestplan indicated inside the file.");
		}
		if ($errSequence eq "NO_SEQUENCE") {
			$pplogger->setLot($errLot);
			$header2->LOT($errLot);
			$header2->populateMeta();
			$pplogger->setSourceLot($header2->SOURCE_LOT);
			#$pplogger->setWafNum($errWafer);
			$pplogger->{_WAF_NUM} = $errWafer;
			dpExit(1,"$errSequence indicated inside the file.");
		}
		$pplogger->setLot($errLot);
		$header2->LOT($errLot);
		$header2->populateMeta();
		$pplogger->setSourceLot($header2->SOURCE_LOT);

		#my $waf = "$errLot"."_"."$errWafer";
		$pplogger->setWafNum($errWafer);
		$errSequence = "$errSequence".".SEQ";
		$errTestplan  = "$errTestplan".".PRN";
		if($errSequence ne "") {
			if (!(-e "$seqLoc1"."$errSequence")) {
				$flag = 1;
				$pplogger->setLot($lotid);
				#$header2->LOT($lotid);
				#$header2->populateMeta();
				$pplogger->setSourceLot($header2->SOURCE_LOT);
				$pplogger->setWafNum($waferno);
				#$pplogger->{_WAF_NUM} = $waferno;
				#dpExit (1, "NO sequence file=\"$errSeq\" exist in $seqLoc1 ");
				#print "im here1\n";
			}
			# if ($flag == 1 ) {
				# if (!(-e "$seqLoc2"."$errSequence")) {
					# $flag = 1;
					# $pplogger->setLot($lotid);
					# $header2->LOT($lotid);
					# $header2->populateMeta();
					# $pplogger->setSourceLot($header2->SOURCE_LOT);
					# $pplogger->setWafNum($waferno);
					# $pplogger->{_WAF_NUM} = $waferno;
					# dpExit (1, "NO sequence file=\"$errSequence\" exist in $seqLoc1 ");
					# print "im here2\n";
				# } else {
					# $flag = 0;
				# }
			# }
			if ($flag == 1) {
				dpExit (1, "NO sequence file=\"$errSequence\" exist in $seqLoc1 or $seqLoc2 ");
			}
		} elsif ($errTestplan ne "") {
			if (! (-e "$seqLoc1"."$errTestplan")) {
				dpExit (1, "Failed to convert CPR file $infile : NO Testplan=\"$errTestplan\" exist in $ENV{DPDATA}/data/cpsort_fet/TP/ ");
			}
		}
}


sub extract_seq_name {
        my $content = shift;
        my @items = split/<|>/, $content;
        return $items[6];
}
