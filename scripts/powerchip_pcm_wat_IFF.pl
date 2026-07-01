#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS
    powerchip_pcm_wat_IFF.pl <Input flie name>
      	--out <output dir>
      	--site <PWRCHIP>
      	--metadata_source <ERT> ERT or xfcs refdb
        --force_prd if needed to force load to PRODUCTION even if metadata is not avaiable
        --pplog
      	[--logfile <logfilepath>]
      	[--debug|--trace]
  	


=head1 DESCRIPTIONS

B<This script> will translate powerchip PCM WAT data to IFF
                

=head1 AUTHOR

B<junifferallan.garcia@onsemi.com>

=head1 CHANGES

=head1 LICENSE

(C) onsemi 2023 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Getopt::Long;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Parser::PowerchipWat;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;
use v5.10;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Compress::Gzip qw(gzip $GzipError) ;
use PDF::WS;
use Data::Dumper;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;


my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}

unless ( GetOptions ( \%hOptions, "OUT=s", "FORK=s", "FACILITYFILE=s", "PLATFORM=s", "SITE=s", "METADATA_SOURCE=s", "LOGFILE=s", "PPLOG", "QDE", "FORCE_PRD", "DEBUG", "TRACE", "V") ) {
    pod2usage(3);
}

my @required_options = qw/OUT SITE FACILITYFILE/;

PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  
}

my $infile = $ARGV[0];
my $site = $hOptions{SITE};
my $metadataSource = $hOptions{METADATA_SOURCE};
$pplogger->setRawFile($infile);
$pplogger->setEnv("powertech_pcm_wat");
$pplogger->setSITE($site);
$pplogger->setScript(basename($0));
my $outdir = $hOptions{OUT};
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $facility = $config->{$site}->{probe};
my $ppLotProdURL = $config->{$site}->{ppLotProd};
my $onLotProdURL = $config->{$site}->{onLotProd};
my $ppLotQAURL = $config->{$site}->{QA_ppLotProd};
my $onLotQAURL = $config->{$site}->{QA_onLotProd};
my $epiScribeFile = $config->{$site}->{epiScribe};
INFO("RFILE=$epiScribeFile");
my $epiScribeHashData = &xlsxToHash($epiScribeFile);

#if($epiScribeFile ne "") {
#  $epiScribeHashData= &xlsxToHash($epiScribeFile);
#} 
my $parser = PDF::Parser::PowerchipWat->new;
my $model;
my $limit;
my $header;
my $programName;

my $output = $infile; 

if ($infile =~ /\.gz$/) {
	$output =~ s/\.gz$//;
	gunzip $infile => $output or die "gunzip failed: $GunzipError\n";
	INFO ("gunzipped file = $output");
}

my $wr = PDF::DpWriter->new(
         {   outdir   => $outdir,
          basename => ( basename $output),
          ext      => 'IFF',
          gzipIFF  => 'Y',
          pplogger => $pplogger
        }
    );

$model = $parser->readFile($output, $hOptions{PLATFORM}, $hOptions{SITE}, $epiScribeHashData);
#set modle->header to pplog object
$pplogger->setModelHeader($model);
#set ERT-WS URL
$model->header->ertUrl($onLotProdURL);

$model->header->FACILITY($facility);

if($metadataSource =~ /ERT/i) {
    unless ($model->header->populateMetadataERT()){
      if(!$hOptions{FORCE_PRD} ) {
        $wr->noMeta(1);
      } else {
        INFO("NO Metadata found but setup to be loaded to PRODUCTION.")
      }
    $model->header->SOURCE_LOT(formatSourceLot($model->header->{SOURCE_LOT}, $model->header->{LOT}));
    $model->header->FAB($facility);
  }
} else {
  unless ($model->header->populateMetadata()){
    if(!$hOptions{FORCE_PRD} ) {
        $wr->noMeta(1);
      } else {
        INFO("NO Metadata found but setup to be loaded to PRODUCTION.")
      }
    $model->header->SOURCE_LOT(formatSourceLot($model->header->{SOURCE_LOT}, $model->header->{LOT}));
    $model->header->FAB($facility);
  }
}

#final program nam setup
$programName = "PCM_${site}_".$model->header->{RECIPE}."_".$model->header->{RECIPE_REVISION};
INFO("Program Name=$programName");
INFO("Program Revision=".$model->header->{RECIPE_REVISION});
#set filename
$model->header->DATA_FILE_NAME(basename($output));
#constant based from mapping
$model->header->AREA("PCM/WAT");
#set program class for PCM=5
$model->header->PROGRAM_CLASS(5);
#assign program name to metadata/header
$model->header->PROGRAM($programName);


if ($model->header->SOURCE_LOT ne ""){
	$pplogger->setWaferFlag(1);
}



my $fmt = new_iff_formatter({
  model=>$model,
  writer=>$wr
});

  $fmt->dataItems([qw/x y site/]);
  $fmt->testItems([qw/number name units critical/]);
  $fmt->printParams();
  $model->buildLimit;
	$fmt->printLimit;
	$model->limit->input_file(basename $output);
  $pplogger->setLimitFile($model->limit->limit_file);
 
dpExit(0);