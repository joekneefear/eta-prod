#!/bin/env perl_db
#
# 09-Dec-2019 Eric A. 	initial release
# 12-Aug-2020 Eric A	added objects to get metadata from dw
# 19-Mar-2021 Eric A	added objects to get metadata from lotg	
# 11-Mar-2022 Eric A.   modified to lookup refdb ws
# 22-Aug-2023 Eric A.	bug fixes encountered when logging

use strict;
use FindBin::libs;
use PDF::Parser::KeySightCsv;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use PDF::DpWriter;
use PDF::Formatter;
use PDF::WS;
use Getopt::Long;
use File::Basename;
use Data::Dumper;
use Config::Tiny;
use PPLOG::PPLogger;

our $VERSION ="1.0";

my (%hOptions) = ();

#Initialized PPLogger Object
 my $pplogger = new PPLOG::PPLogger();

if ( $#ARGV < 0 ) {
        print "Usage: $0 <FILENAME> <OPTIONS>\n";
        exit 1;
}
unless (
        GetOptions(
                \%hOptions,  "OUT=s", "LOGFILE=s", "RET=s", "DEBUG", "TRACE", "ALERT", "ARCHIVE=s", "QDE", "CONF=s", "PPLOG"
        )
)
{
        print "Invalid options.\n";
	exit;
}

my @required_options = qw/OUT CONF/;

#Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
        $pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

$pplogger->setScript(basename($0));


if (grep { !exists $hOptions{$_} } @required_options) {
        print "Error! Missing required options.\n";
	exit 1;
}

PDF::Log->init(\%hOptions);

my $infile = $ARGV[0];
my $outdir = $hOptions{OUT};
my $arcdir = $hOptions{ARCHIVE};
my $qde	= $hOptions{QDE};
my $alert = $hOptions{ALERT};
my $meta_flg = "Y";
my $agile_flg = "Y";
my $conffile = $hOptions{CONF};
my $fname = basename $infile;
my $ertUrl = "";

if ( ! -f $infile ) {
	dpExit(1,"Error! File does not exists.");
}

 
INFO ("$infile = $infile");

# log filename
$pplogger->setRawFile($infile);
#log site
$pplogger->setSITE("UV5");


my $config = Config::Tiny->read($conffile);

my $wr = PDF::DpWriter->new({outdir   => $hOptions{OUT},
				forkdir => $hOptions{ARCHIVE},
				qde   => $hOptions{QDE},
                                basename => (basename $infile),
                                ext      => 'iff',
			 	gzipIFF  => 'Y'});

my $parser = PDF::Parser::KeySightCsv->new;
my $model = $parser->parseFile($infile,$config);
my $header = $model->header;
my $misc = $model->misc;
my $msg = $misc->{msg};
my $tech = $misc->{tech};
my $wmap = $model->wmap;
$ertUrl = $config->{webservice}->{onlot};

INFO("ERT URL=$ertUrl");

#Passing Reference of Model
$pplogger->setModelHeader($model);

if ($header->LOT eq "") {
	dpExit(1,"Missing LOTID,");
}
my $onlotws = $config->{webservice}->{onlot}.$header->{LOT};

INFO("Searching metadata in ONLOT refdb web service for lot : $header->{LOT}");
my %onlot = getMetaFromRefDbWS($onlotws);

if ($onlot{status} =~ /no_data|error/i) {
	WARN("Sending data to SANDBOX.");
	$wr->forSBox(1);
}

if ($msg =~/Wafer Number is missing/i) {
	WARN($msg);
	WARN("Sending data to SANDBOX.");
	$wr->forSBox(1);
}

$header->ONS_LOTCLASS($onlot{lotclass});
#$header->PRODUCT($onlot{product});
$header->PRODUCT_CODE($onlot{productCode});
$header->ALTERNATE_PRODUCT($onlot{alternateProduct});
$header->LOT_TYPE($onlot{lotType});
$header->ALTERNATE_LOT($onlot{alternateLot});
$header->SUBCON_LOT_ID($onlot{subconLot});
$header->SUBCON_PRODUCT($onlot{subconProduct});
$header->DATA_FILE_NAME($fname);
$header->AREA("PCM/WAT");
$header->FAB("UV5:GF FISHKILL FE CTI");
$header->TEST_FACILITY("UV5:GF FISHKILL FE CTI");
$header->TEST_FLOOR("UV5:GF FISHKILL FE CTI");
$header->TESTER_TYPE("KEYSIGHT_4073");
$header->STAGE("WAT");
$header->ertUrl($ertUrl);

if ($header->{SOURCE_LOT} eq "" || $header->{SOURCE_LOT} eq "N/A") {
	my $srclot = uc($header->{LOT});
	$srclot =~ s/\.\d+$/\.S/;
	$header->SOURCE_LOT($srclot);
}
elsif ($header->{SOURCE_LOT} =~ /\.\d+$/) {
	my $srclot =~ s/\.\d+$/\.S/;
	$header->SOURCE_LOT($srclot);
}
else {
	$header->SOURCE_LOT($onlot{sourceLot});
}

if ($header->{SOURCE_LOT} !~ /\.S$/ig) {
	$header->SOURCE_LOT($header->SOURCE_LOT.".S");
}


if ($header->{PRODUCT} ne "" && $header->{PRODUCT} ne "N/A") {
	INFO("Searching metadata in ONPROD refdb web service for product : $header->{PRODUCT}");
	my $onprodws = $config->{webservice}->{onprod}.$header->{PRODUCT};
	my %onprod = getMetaFromRefDbWS($onprodws);

	$header->PROCESS($onprod{process});
	$header->FAMILY($onprod{family});
	$header->PTI4_PAL($onprod{pti4});
	$header->TECHNOLOGY($onprod{technology});
	$header->MASKSET($onprod{maskSet});
	$header->PACKAGE($onprod{package});
}

#use technology from file if not available in DW
if ($header->{TECHNOLOGY} eq "" || $header->{TECHNOLOGY} eq "N/A" || $header->{TECHNOLOGY} =~ /dummy/i) {
	INFO("Using technology information from file...");
	$header->TECHNOLOGY($tech);
}


#output to sandbox directory if no WMC
unless ( ! $wmap->isEmpty ){
	WARN ("Missing Wafer Map Config.");
        #$wr->wmapIsEmpty(1);
}

my $fmt = new_iff_formatter({ model=>$model, writer=>$wr });

$fmt->dataItems([qw/x y org_x org_y site/]);
$fmt->testItems([qw/number name units LSL HSL group/]);
$fmt->printPar_v5;

dpExit(0);


sub notify {
        my $fname = shift;
        my $msg = shift;

        my $subj = "Alert: EFK - PCM : Error occurred while processing file.";
        my $to = "eric.alfanta\@onsemi.com,rodney.cyr\@onsemi.com";

        open(MAIL, "|mailx -s \"$subj\" $to");
        print MAIL "$msg - $fname\n\n";
        close(MAIL);
}
