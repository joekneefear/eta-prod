#!/usr/bin/env perl_db
# SVN $Id: fcs_se_probe_IFF.pl 2580 2020-10-06 01:31:56Z dpower $

=pod

=head1 SYNOPSIS

  fcs_seprobe_log.pl <Input flie name>
      --out <output dir>
      --site [mtsort|*]
      --loc <location CP, MT, SZ>
	  --facilityfile </export/home/dpower/project/scripts/facilityMapping.ini>
      --config <cfg_tester_type>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will read seprobe log file and generate IFF file for dbascii

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2014/05/21 edwardy 	: 1st version
 2015/03/10 kazukik 	: output IFF format
 2015/04/14 kazukik 	: use data model
 2015/04/22 jason	: reject files with PROGRAM==Undefined.
 2015/05/29 grace  	: Added support for -v option.
 2015/07/01 eric   	: added LOC arg and pass it as EQUIP6_ID.
 2015/07/03 eric   	: apply new program naming rule.
 2015/07/08 eric   	: moved updateProgram after updateWMap, sanbox if no entry in pp_wmap.
 2015/07/22 jgarcia 	: added finallot args for csp map look up.
 2015/07/22 jgarcia 	: passed in finallot args when calling readfile subroutine to be able to determine if finallot lookup in SEPM module.
 2015/07/30 rcyr   	: Don't set noMeta flag when program is empty, product will be used, so don't send to sandbox.
 2015/08/10 eric   	: gunzipped incoming gz file.
 2015/10/01 gilbert	: Fail FET-Quad SE-Probe map (CP site) and removed .gz in iff cretion
 2015/12/16 jgarcia	: modified to try to matched for metadata where lotid last char is stripped. 
 			this is done after it failed on the first metadata check with NO Stripping to lotid.
 2015/12/16 jgarcia	: added metastrip as an argument.
 2016/01/29 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2016/04/15 eric    	: replace config tester type from SEPM to SEPM_AOI if wmap is an AOI wmap
 2016/05/11 eric    	: replace config tester type from SEPM to SEPM_ITC if config name starts with ITC
 2016/06/23 eric    	: replace config tester type from SEPM to SEPM_ITC if test sys eq IT and loc BK
 2017/05/03 eric	: assign source lot as wafer name
 2018/02/22 eric	: replace 3rd character with zero for ME lots sorted in BK
 2018/03/14 eric	: replace config tester type from SEPM to SEPM_ITC if cmap starts with ITC_ and loc MT
 2018/05/10 eric	: replace config tester type from SEPM to SEPM_ITC if systemid contains ITC and loc MT
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
 2023/09/28 eric	: perform BK lot lookup by stripping characters
 2025/04/24 eric	: remove special characters in program name
 2025/09/10 gmllego     : Added new Lot lookup rule for BK Probe Lot starts with 'L', ends with 'A' (more than 5 characters long).

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Getopt::Long;
use Pod::Usage qw/pod2usage/;
use PDF::Log;
use PDF::DpLoad;
use File::Basename qw/basename/;
use PDF::DpData;
use PDF::DpWriter;
use PDF::DAO;
use PDF::Parser::SEPM;
use PDF::Formatter;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Compress::Gzip qw(gzip $GzipError) ;
use v5.10;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;

no warnings qw/experimental::lexical_subs experimental::smartmatch/;

our $VERSION = "1.0";
our $TESTER  = "SEPM";
my (%hOptions) = ();



# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    	pod2usage();
    	dpExit( 1, "No input file specified" );
}
unless (
    	GetOptions( \%hOptions, "OUT=s", "FORK=s", "SITE=s", "FINALLOT", "LOC=s", "FACILITYFILE=s", "CONFIG=s", "LOGFILE=s", "DEBUG", "V",
        	"TRACE", "METASTRIP", "PPLOG" )
    	)
{
    	dpExit( 1, "invalid options" );
}
if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT SITE FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
my $facility = $config->{$location}->{probe};
my $ertUrl = "";
$ertUrl = $config->{$location}->{onLotProd};
INFO("ERT URL=$ertUrl");
INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];

if ( !-f $infile ) {
    	dpExit( 1, "input file does not exist $infile" );
}

my $site = $hOptions{SITE};

INFO("infile  = $infile");

# wsanopao: Set Raw File ==> infile and Environment ==> $site._eagle
$pplogger->setRawFile($infile);
$pplogger->setEnv($site,'wmap_sep');

my $output = $infile; 
if ($infile =~ /\.gz$/) {
	$output =~ s/\.gz$//;
	gunzip $infile => $output or die "gunzip failed: $GunzipError\n";
	INFO ("gunzipped file = $output");
}

# check output dir
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},
        basename => ( basename $output),
        ext      => 'iff',
				gzipIFF  => 'Y'
    }
);

if ($location eq "CP") 
{
     	### GET CMAP INFO ###
     	my $cmap       = "";
     	my $merged_map = "N";
     	my $line       = "";
     	open FH, $output;
     	while ($line=<FH>)
     	{
           	chomp($line);
           	my ($label,$value) = split /\t+/, $line;
           	next unless $label =~ /\w+/;
           	$label =~ s/\s//g;
           	$value =~ s/\s//g;
           	if ($label eq "CMAP")
           	{
               		$cmap = $value;
           	}
           	elsif ($label eq "OPDESC" && $value=~/MERGE/i)
           	{
              		$merged_map = "Y";
           	}
     	}
     	close(FH);

     	$cmap  =~ s/[^A-Z0-9]*$//i;
     	if ($cmap!~/^QF|^DF|^QC/i || ($cmap=~/^QF|^DF|^QC/i && $merged_map eq "Y") )
     	{

     	}
     	else
     	{
		unlink ($output) if $infile =~ /\.gz$/;
		dpExit( 1, "Identified a FET-Quad SE-Probe map");
     	}
 
}

my $parser = PDF::Parser::SEPM->new;

#my $model = $parser->readFile( $infile, $hOptions{FINALLOT}  );
my $model 	= $parser->readFile( $output, $hOptions{FINALLOT}  );
my $header 	= $model->header;
my $sep 	= $model->misc;
my $systemid 	= $sep->configuration->{SYSTEM_ID};
my $testsys 	= $sep->configuration->{TEST_SYS};
my $config_name = $sep->lot_data->{CONFIGURATION_NAME};
my $proc_step 	= $sep->lot_data->{PROCESS_STEP};
my $cmap_id	= $sep->lot_data->{CMAP};

$header->EQUIP6_ID($facility);
$header->ertUrl($ertUrl);
#$header->EQUIP6_ID($location);

if ($location eq "ME" && ($systemid =~ /MEBUMP/ || $systemid=~ /BUMP/ || $systemid =~ /AOI/)) {
	$header->CFG_TESTER_TYPE("SEPM_AOI");
}
elsif (($location eq "CP" || $location eq "SZ") && ($config_name =~ /^ITC/i || $proc_step =~ /^ITC/i)) {
	$header->CFG_TESTER_TYPE("SEPM_ITC");
}
elsif ($location eq "BK" && $testsys =~ /^TI/i) {
	$header->CFG_TESTER_TYPE("SEPM_ITC");
}
elsif ($location eq "MT" && ($cmap_id =~ /^ITC_/i || $systemid=~ /ITC/i)) {
	$header->CFG_TESTER_TYPE("SEPM_ITC");
}
else {
	$header->CFG_TESTER_TYPE($cfg_tstr_typ);
}

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

if ($site eq 'mtsort'){
  	if (exists $sep->lot_data->{READER}){
    		 $header->LOT( (split('-',$sep->lot_data->{READER}))[0]);
  	}
}

#$wr->noMeta(1) unless ( $header->populateMeta );
if ($hOptions{LOC} eq 'BK' && $hOptions{SITE} eq 'bksort' && $hOptions{METASTRIP}) {
	unless ( $header->populateMeta ){
		my $origLot = $header->LOT;
		my $tempLot = $origLot;
		my $tempLot2 = $origLot;

		if ($tempLot =~ /^M0[a-zA-Z]/i && length($tempLot) == 10 ) {
                	INFO("Performing second lot lookup by replacing 3rd character with 0.");
                        my $count = 3;
                        $tempLot =~ s/(\w)/--$count == 0 ? "0":$1/ge;
                        $header->LOT($tempLot);

			unless ($header->populateMeta) {
				$wr->noMeta(1);
			}

                }
                elsif ( length($tempLot) > 8 && $tempLot !~ /^M0/i ) {
                       	INFO("Performing second lot lookup using first 8 characters of KG|KH lots.");
                       	$tempLot = substr($tempLot,0,8);
			$header->LOT($tempLot);

			unless ($header->populateMeta) {
				INFO("Performing third lot lookup by stipping last character if KG|KH lots.");
				$tempLot2 = substr($tempLot2, 0, -1);
				$header->LOT($tempLot2);

				unless ($header->populateMeta) {
					$wr->noMeta(1);
				}
			}
                }
                        # New rule: Lot starts with 'L', ends with 'A', and is longer than 5 characters
                        elsif ($origLot =~ /^L/i && $origLot =~ /A$/i && length($origLot) > 5) {
                               INFO("Performing lot lookup by removing last character from L...A lot.");
                               my $trimmedLot = substr($origLot, 0, -1);
                                  $header->LOT($trimmedLot);

                                unless ($header->populateMeta) {
                                          $wr->noMeta(1);
                                }
                        }
		else {
			$wr->noMeta(1);
		}

		$header->LOT($origLot);
	}
		
} else {
	unless ( $header->populateMeta ){
		$wr->noMeta(1);
	}
}

my $program = $header->PROGRAM;

#remove special characters in program name
$program =~ s/[\@\#\$\%\/\&\'\}\{\*\"\[\]\>\<]//g;

if ($program eq ''){
	# dpExit( 1, "PROGRAM is empty or Undefined" );
	#$wr->noMeta(1);   # Will use product as program, don't set noMeta. -- RCyr 20150730
}
if ($program eq 'N/A' || $program eq ''){
 	INFO("Program name is blank or N/A. set product name to program :".$header->PRODUCT);
  	$program = $header->PRODUCT;
}
# Check Program length for > 35.  Truncate and send to sandbox.
my $ssum = "_".$sep->sessionSummary;
if ( length($program) + length($ssum) > 35 )
{
        INFO("PROGRAM NAME \"".$program.$ssum."\" will be truncated to 35 characters.  Sending to sandbox.");
        $wr->forSBox(1);
        $program = substr($program, 1, 35-length($ssum)); # Leave enough room for session type
}

$header->PROGRAM(uc($program.$ssum));
$header->VERSION($VERSION);
my $wmap = $model->updateWMap;
$wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty ); 

unless ( $wmap->confirmed ) {
    	$wr->noWMap(1);
}
#assign source lot as wafer name
my $wafer = $model->wafers;
#2022-Jul-01 : jgarcia : always format the SourceLot to not have NA or N/A or blank values regardless if Production or Sandbox.
$header->SOURCE_LOT(formatSourceLot($header->{SOURCE_LOT}, $header->{LOT}));

if ($header->SOURCE_LOT ne "" && !($hOptions{FINALLOT})) {
	my $sourceLot = $header->{SOURCE_LOT};
	$sourceLot =~ s/\.S$//;
	$wafer->[0]->name($sourceLot."_".sprintf("%02d",$wafer->[0]->number));
	$pplogger->setWaferFlag(1);
}

$model->updateProgram("MAP_PGM");

my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);
$formatter->dataItems([qw/x y site soft_bin/]);
$formatter->printBinmap;


# Delete gunzipped file
unlink ($output) if $infile =~ /\.gz$/;

#gzip IFF file
# my $gzipIFF = "$wr->{openedfile}.gz";
# gzip $wr->{openedfile} => "$gzipIFF" or WARN("Unable to gzip $wr->{openedfile}");
# if(-e $gzipIFF) {
# 	INFO("gzip IFF file = $gzipIFF");
# 	unlink($wr->openedfile);
# }

dpExit(0);

