#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS
    fcs_metadtaVerifier.pl <Input flie name>
        --out <output dir>
        --env <dataflow enrivonment name e.g bksort_wmap_nam>
        --fileage <desired number of days and will be used to be compared against the lastest modification date of the input file>
        --handler_cfg <yaml file with hanlder class name per environment and other info like lots to be skipped.
        --TP <Testplan folder currently not used>
        --reffile <reference file for future use, currently not used>
        --type <type or may tester type, currently not used>
        --finallot <if environment is a finallot>
        --pplog
        [--logfile <logfilepath>]
        [--debug|--trace]
        


=head1 DESCRIPTIONS

B<This script> The Metadata verifier would parse the NAM file to get the lot ID.  
                If the lot ID exists in PP_LOT, the file is moved to the translator inbound folder for preprocessing [IFF generation].  
                                

=head1 AUTHOR

B<junifferallan.garcia@onsemi.com>

=head1 CHANGES
       2023-Aug-17 - jgarcia    - remove the process to rename the file if needs to ge staged until threshold is met.
                                - use exit code 10 for DpLoad.pl to not accept the file and to remain in the staging folder
                                - dont log information to pp_log when file is being staged for reprocessing until threshold is met.
                                
       2023-Sep-14 - gmllego    - added gtk_tw_sort_mosaic_bk_wmap_nam
       2024-Apr-12 - jgarcia    - added lot modification for second or third query for bksort_wmap_nam environment via factory pattern.
       2024-Apr-25 - jgarcia    - activated lots skipping from a listed on the yaml file. equal value, lots like regex and lots starts with regex.
 
       
       
=head1 LICENSE

(C) onsemi 2023 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Getopt::Long;
use PDF::Log;
use PPLOG::PPLogger;
use PDF::DpParser;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename dirname fileparse/;
use File::Copy;
use PDF::DpLoad;
use PDF::DpData;
use Config::Tiny;
use Switch;
use File::stat;
use File::Spec;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Compress::Gzip qw(gzip $GzipError);
use v5.10;
use YAML::XS 'LoadFile';
use Data::Dumper;
use PDF::MetadataVerifier::LotHandlerFactory;
use PDF::MetadataVerifier::BkSortNamLotHandler;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;


our $VERSION = "1.0";

# a hash to receive options
my %hOptions = ();

my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ($#ARGV < 0) {
    pod2usage(3);
    dpExit(1, "No input file specified");
}

unless (
    GetOptions(
        \%hOptions, "OUT=s", "ENV=s", "FILEAGE=s", "HANDLER_CFG=s", "TP=s", "REFFILE=s", "TYPE=s", "LOGFILE=s", "FINALLOT", "PPLOG", "DEBUG", "TRACE", "V"
    )
  )
{
    dpExit(1, "invalid options");
    pod2usage(3);
}

my @required_options = qw/OUT ENV/;

if (grep { !exists $hOptions{$_} } @required_options) {
    pod2usage(3);
}

PDF::Log->init(\%hOptions, $pplogger);
if ($hOptions{PPLOG}) {
    $pplogger->settobeLog(1);
}

my $infile = $ARGV[0];
my $inFileAge = (-M $infile);
my $parser;
my $model;
my $header;
my $env = $hOptions{ENV};
my $lot_handler_cfg = $hOptions{HANDLER_CFG};
my ($site, $dump) = split('_', $env, 2);
my $referenceFile = $hOptions{REFFILE};
my $TP = $hOptions{TP};
my $type = $hOptions{TYPE};
my $fileage = $hOptions{FILEAGE};
my $lot_handler_config_info;
my $lots_to_skip;
my $lots_like_to_skip;
my $lots_starts_with_to_skip;


if ($fileage eq "") {
    WARN("No file age provided. Files not matching lot metadata will not be staged and move immediately to preprocessing. lot or file could be loaded to Sandbox");
    $pplogger->setOutDir($hOptions{OUT});
    dpExit(0)
}

# Check file age before proceeding
if (defined $fileage) {
    my $fileage_in_days;
    if ($fileage =~ /(\d+)H$/i) {
        # Convert hours to days
        $fileage_in_days = $1 / 24;
    } elsif ($fileage =~ /(\d+)D$/i || $fileage =~ /(\d+)$/i) {
        # Already in days or no suffix provided (default to days)
        $fileage_in_days = $1;
    } else {
        dpExit(1,"Invalid fileage format. Please use 'NN' or 'NND' for NN days, or 'NNH' for NN hours.");
    }

    if ($inFileAge > $fileage_in_days) {
        INFO("Skipping lot verification as the input file age ($inFileAge days) exceeds the specified file age ($fileage_in_days days)");
        $pplogger->setOutDir($hOptions{OUT});
        dpExit(100);
    }
}

if($lot_handler_cfg) {
    INFO("configured with lot handler, will be using lot handler factory");
    $lot_handler_config_info = LoadFile($lot_handler_cfg);
    # INFO("$lot_handler_config_info");
    $lots_to_skip = $lot_handler_config_info->{dont_verify}->{lots} || [];
    $lots_like_to_skip = $lot_handler_config_info->{dont_verify}->{lots_like} || [];
    $lots_starts_with_to_skip = $lot_handler_config_info->{dont_verify}->{lots_start_with} || [];
} else {
    INFO("Lot Handler is NOT passed as parameter, configured without lot handler. DpLoad.checkMetadataByLotMoveToPreprocessingFolder subroutine will be used.");
}

my $output = $infile;
if ($infile =~ /\.gz$/) {
    $output =~ s/\.gz$//;
    gunzip $infile => $output or die "gunzip failed: $GunzipError\n";
    INFO("gunzipped file = $output");
}
my %params = (
    'infile'    => $output,
    'outdir'    => $hOptions{OUT},
    'fileAge'   => $fileage,
    'inFileAge' => $inFileAge,
    'env'       => $env,
    'filename'  => basename(withoutExt($output)),
    'ext'       => extOnly($output),
    'finallot'  => $hOptions{FINALLOT},
    'skip_lots' => $lots_to_skip // [],
    'skip_lots_like' => $lots_like_to_skip // [],
    'skip_lots_starts_with' => $lots_starts_with_to_skip // [],
);
$pplogger->setWaferFlag(1);
$pplogger->setScript(basename($0));
$pplogger->setRawFile($output);
$pplogger->setEnv($env);

my $returnCode;
my $flag = "";
my $origLot = "";

# Load configuration
my $lot_handler_config;
my $factory;
my $handler;
my $parentDir = dirname($output);


switch($env) {
    case "bksort_wmap_nam" {
        $parser = new_nam_parser;
        $model = $parser->readFile($output);
        $pplogger->setModelHeader($model);
    }
    case "gtk_tw_sort_mosaic_bk_wmap_nam" {
        $parser = new_nam_parser;
        $model = $parser->readFile($output);
        $pplogger->setModelHeader($model);
        $returnCode = checkMetadataByLotMoveToPreprocessingFolder($model, \%params);
    }
    case "cpsort_wmap_sep" {
        $parser = new_sepm_parser;
        $model = $parser->readFile($output);
        $pplogger->setModelHeader($model);
        $returnCode = checkMetadataByLotMoveToPreprocessingFolder($model, \%params);
    }
    case "cpcsp_wmap_nam" {
        $parser = new_nam_parser;
        $model = $parser->readFile($output);
        $pplogger->setModelHeader($model);
        $returnCode = checkMetadataByLotMoveToPreprocessingFolder($model, \%params);
    }
    case "cpsort_eagle" {
        $parser = new_eagle_parser;
        ($model, $flag) = $parser->readFile($output, $site);
        $pplogger->setModelHeader($model);
        $returnCode = checkMetadataByLotMoveToPreprocessingFolder($model, \%params);
    }
    case "cpft_eagle" {
        $parser = new_eagle_parser;
        ($model, $flag) = $parser->readFile($output, $site);
        $pplogger->setModelHeader($model);
        $returnCode = checkMetadataByLotMoveToPreprocessingFolder($model, \%params);
    }
    case "cpft_statec" {
        $parser = new_statec_log2_parser;
        $model = $parser->readFile($output);
        $pplogger->setModelHeader($model);
        $returnCode = checkMetadataByLotMoveToPreprocessingFolder($model, \%params);
    }
    case "cpft_icos" {
        $parser = new_statec_log2_parser;
        $model = $parser->readFile($output, $type, $referenceFile);
        $pplogger->setModelHeader($model);
        $returnCode = checkMetadataByLotMoveToPreprocessingFolder($model, \%params);
    }
}

if($lot_handler_config_info) {
     # Create factory
    $factory = PDF::MetadataVerifier::LotHandlerFactory->new(handler_config => $lot_handler_config_info);
    # Get handler and handle lot
    $handler = $factory->get_handler($env, $model, \%params, $pplogger);
    $returnCode = $handler->handle_lot() if $handler;
} 

if ($returnCode == 10) {
    # since we used DpLoad.pl to take advantage of the folder and file management and other built-in options and capabilities,
    # we dont log information to pp_log when file is being staged for reprocessing until threshold is met.
    # use exit code 10 for DpLoad.pl to not accept the file and to remain in the staging folder.
    # exit(10);
    $pplogger->setOutDir($parentDir);
    dpExit($returnCode);
} elsif($returnCode  == 100) {
    dpExit(100);

} elsif($returnCode == 1011) {
    my $outDir = "${parentDir}/ReworkFiles";
    $pplogger->setOutDir($outDir);
    moveFile($infile, $outDir, $params{filename}, $params{ext});
    if(-e $output) {
        unlink $output;
    }
    dpExit($returnCode);
} else {
    $pplogger->setOutDir($hOptions{OUT});
    dpExit($returnCode);
}
