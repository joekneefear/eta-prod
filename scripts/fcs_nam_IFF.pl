#!/usr/bin/env perl_db
# SVN $Id: fcs_nam_IFF.pl 2586 2020-10-06 03:00:28Z dpower $

=pod

=head1 SYNOPSIS

  fcs_nam_IFF.pl <Input flie name>
      --out <output dir>
      --loc <location e.g. CP,PM,MT>
	  --facilityfile </export/home/dpower/project/scripts/facilityMapping.ini>
      --config<config_tester_type>
      [--finallot]
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will read National ArrayMap file and generate IFF file for dbascii

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/03/17 kazukik	: output IFF format
 2015/05/13 grace  	: add normalizeToBaseUnit
 2015/05/29 grace  	: Added support for -v option.
 2015/07/01 eric   	: Added LOC arg and pass it as EQUIP6_ID
 2015/07/03 eric   	: applied new program naming rule
 2015/07/13 jgarcia	: moved updateProgram after updateWMap, sanbox if no entry in pp_wmap.
 2015/07/14 eric   	: sandbox if ppid > 35.
 2015-07-21 jgarcia	: assigned Product as Program name.
 2015-07-21 jgarcia  	: add the Product in the Program name which is the SYSTEM ID. >>PRODUCT_SYSTEM ID<<
 2015-07-24 jgarcia 	: use only Product as Program name if strip map, final modification implemented for non strip map NAM.
 2016-02-05 eric 	: added arg option type to add "dpat" to ppid for dpat maps
 2016/02/26 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2016/09/15 eric 	: get map type from misc
 2017/05/03 eric	: assign source lot as wafer name.
 2019/09/16 eric	: get passtype to determine klarf defect maps
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
 2022-Aug-10 jgarcia : remove systemID in the program name as per Tom Grein - CE-779
 2023/06/15 jgarcia : modified to get SourceLot-(CZ4 fab)value from On_Lot refdb.
 2023/08/23 gmllego : Modified to add metastrip of LotId from GTK_TW site.
 2023/09/28 eric	: perform BK lot lookups by stripping characters
 2025/09/10 gmllego     : Added new Lot lookup rule for BK Probe Lot starts with 'L', ends with 'A' (more than 5 characters long).

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Getopt::Long;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use POSIX qw(strftime);
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Parser::NAM;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use Config::Tiny;
use v5.10;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;
use PPLOG::PPLogger; 	# wsanopao:

our $VERSION = "1.0";
our $TESTER  = "NAM";
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    	pod2usage();
    	dpExit( 1, "No input file specified" );
}
unless (
    	GetOptions( \%hOptions, "OUT=s", "FORK=s", "LOC=s", "SITE=s", "FACILITYFILE=s", "CONFIG=s", "FINALLOT", "STRIPMAP", "LOGFILE=s", "DEBUG", "V",
        	"TYPE=s", "TRACE", "PPLOG", "NOSANDBOX", "METASTRIP" )
    	)
{
    	dpExit( 1, "invalid options" );
}

if($hOptions{V})
{
	print("$VERSION\n");
	dpExit(0);
};

my @required_options = qw/OUT LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
my $map_type = $hOptions{TYPE};
my $facility = "";
my $site = $hOptions{SITE};
my $ertUrl = "";
if($hOptions{FINALLOT}) {
        $facility = $config->{$location}->{finalTest};
} else {
 	$facility = $config->{$location}->{probe};
 	$ertUrl = $config->{$location}->{onLotProd};
	INFO("ERT URL=$ertUrl");
}
INFO("FACILITY|EQUIP6_ID=$facility");
# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$PPlogger->setRawFile($infile);
$PPlogger->setEnv($site);
$PPlogger->setSITE($site);
$PPlogger->setScript(basename($0));
if ( !-f $infile ) {
    	pod2usage();
    	dpExit( 1, "input file does not exist $infile" );
}

# check output dir
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},
        basename => ( basename $infile),
        ext      => 'iff',
		gzipIFF  => 'Y'
    }
);

INFO("infile  = $infile");
open( INFILE, $infile );

# Start input file reading
my $parser = PDF::Parser::NAM->new;

my $model = $parser->readFile( $infile);
my $comment  = $model->misc->{COMMENT};
my $passtype = $model->misc->{PASSTYPE};

   if ($comment =~ /ICOS/i) {
	$map_type = 'ICOS';
   }
   elsif ($passtype =~ /KLARF_DEFECT_DOWNGRADED/i) {
	$map_type = 'DEFDG';
   }
   else {
	$map_type = $map_type;
   }
   INFO("MAP TYPE = $map_type");

&normalizeToBaseUnit($model);

my $header = $model->header;
#my ($program, $systemID) = split(',', $header->PROGRAM);
my $program  = $header->PROGRAM;

$header->EQUIP6_ID($facility);
$header->CFG_TESTER_TYPE($cfg_tstr_typ);
$header->isFinalLot($hOptions{FINALLOT});
$header->ertUrl($ertUrl);
#$wr->noMeta(1) unless ( $header->populateMeta );
#unless ( $header->populateMeta ) {
#	if (!($hOptions{NOSANDBOX})) {
#		$wr->noMeta(1);
#	}
#	else {
#		WARN("File was not  sandboxed. Argument was enabled.");
##	}
#}
if (!($hOptions{NOSANDBOX})) {
	if ($hOptions{LOC} eq 'GTK_TW' && $hOptions{SITE} eq 'gtk_tw_sort' && $hOptions{METASTRIP}) {
		unless ( $header->populateMeta ) {
			my $origLot = $header->LOT;
			my $tempLot1 = $origLot;
			my $tempLot2 = $origLot;

			if ( length($tempLot1) > 8 && $tempLot1 =~ /^KG|^KH/i ) {
				INFO("Performing second lot lookup using first 8 characters of KG|KH lots.");
				$tempLot1 = substr($tempLot1,0,8);
				$header->LOT($tempLot1);

				unless ($header->populateMeta) {
					INFO("Performing third lot lookup by stripping last character of KG|KH lots.");
					$tempLot2 = substr($tempLot2, 0, -1);
					$header->LOT($tempLot2);

					unless ($header->populateMeta) {
							$wr->noMeta(1);
					}
				}
			}
			else {
				$wr->noMeta(1);
			}
				$header->LOT($origLot);
		}

	} elsif ($hOptions{LOC} eq 'BK' && $hOptions{SITE} eq 'bksort' && $hOptions{METASTRIP}) {
		unless ( $header->populateMeta ) {
				my $origLot = $header->LOT;
				my $tempLot1 = $origLot;
				my $tempLot2 = $origLot;

			if ($tempLot1 =~ /^M0[a-zA-Z]/i && length($tempLot1) == 10 ) {
				INFO("Performing second lot lookup by replacing 3rd character with 0.");
				my $count = 3;
				$tempLot1 =~ s/(\w)/--$count == 0 ? "0":$1/ge;
				$header->LOT($tempLot1);

				unless ($header->populateMeta) {
						$wr->noMeta(1);
				}
			} elsif ($tempLot1 =~ /^M/i) {
				INFO("Performing second lot lookup by dropping 'M' and processing the remainder.");
				$tempLot1 = substr($tempLot1, 1);
				$header->LOT($tempLot1);

				unless ($header->populateMeta) {
					INFO("Performing third lot lookup by stripping to 8 characters.");
					$tempLot2 = substr($tempLot1, 0, 8);
					$header->LOT($tempLot2);

					unless ($header->populateMeta) {
						$wr->noMeta(1);
					}
				}
			} elsif ( length($tempLot1) > 8 && $tempLot1 =~ /^KG|^KH/i ) {
				INFO("Performing second lot lookup using first 8 characters of KG|KH lots.");
				$tempLot1 = substr($tempLot1,0,8);
				$header->LOT($tempLot1);

				unless ($header->populateMeta) {
					INFO("Performing third lot lookup by stripping last character of KG|KH lots.");
					$tempLot2 = substr($tempLot2, 0, -1);
					$header->LOT($tempLot2);

					unless ($header->populateMeta) {
							$wr->noMeta(1);
					}

				}
                # New rule: Lot starts with 'L', ends with 'A', and is longer than 5 characters
                       } elsif ($origLot =~ /^L/i && $origLot =~ /A$/i && length($origLot) > 5) {
                               INFO("Performing lot lookup by removing last character from L...A lot.");
                               my $trimmedLot = substr($origLot, 0, -1);
                                  $header->LOT($trimmedLot);

                               unless ($header->populateMeta) {
                                       $wr->noMeta(1);
                               }                

			} else {
				$wr->noMeta(1);
			}
			$header->LOT($origLot);
		}

	} else {
		unless ( $header->populateMeta ){
			$wr->noMeta(1);
		}
	}

} else {
	WARN("File was not  sandboxed. Argument was enabled.");
}


# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);

### intialized systemID to N/A if no info. ###
#if($systemID eq "" || $systemID =~ /^\?+$/) {
#WARN("SYSTEM ID is blank or has a value of ???, will be replaced by N/A");
#	$systemID = "N/A";
#}

if($hOptions{STRIPMAP}) {
	INFO("STRIP MAP NAM TYPE");
	if($header->{PRODUCT} ne "") {
		INFO("STRIP MAP NAM data type, Using PRODUCT =[\"".$header->{PRODUCT}."\"]as a PROGRAM name");
		$program = $header->{PRODUCT};
	} else {
		dpExit( 1, "STRIP MAP NAM data type, can't get PRODUCT from PP_FINALLOT which will be used as PROGRAM");
	}
} else {
	INFO("NORMAL MAP NAM TYPE");
	if(($program eq "" || $program =~ /^\?+$/) && $header->{PRODUCT} eq "") {
		dpExit( 1, "NORMAL NAM MAP data type, No PROGRAM available in the file and unable to look up PRODUCT");
	} elsif (($program eq "" || $program =~ /^\?+$/) && $header->{PRODUCT}  ne ""){
		INFO("PROGRAM IS NOT AVAILABLE, USING PRODUCT =[\"".$header->{PRODUCT}."\"] AS A PROGRAM NAME");
		$program = $header->{PRODUCT};
	} else {
		INFO("PROGRAM NAME IS AVAILABE IN THE FILE.. USING IT.");
		$program = $program;
	}

}

### CHECK PROGRAM NAME LENGTH, TRIM IF NECESSARY ###
if ( length($program) > 35 )
{
        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
        $wr->forSBox(1);
        $program = substr($program, 1, 35-length($map_type)); # Leave enough room for session type
}

#INFO("Concatenate PROGRAM_NAME=${program} with SYSTEM_ID=${systemID} as the final PROGRAM NAME = [${program}_${systemID}]");
if($map_type ne "") {
  $header->PROGRAM($program."_".$map_type);
} else {
  $header->PROGRAM($program);
}


$header->VERSION($VERSION);

my $wmap = $model->updateWMap;
#$wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );

unless ( ! $wmap->isEmpty ) {
	if (!($hOptions{NOSANDBOX})) {
		$wr->wmapIsEmpty(1);
	}
	else {
		WARN("File was not sandboxed. Argument was enabled.");
	}
}

unless ( $wmap->confirmed ) {
	if (!($hOptions{NOSANDBOX})) {
    		$wr->noWMap(1);
	}
	else {
		WARN("File was not sandboxed. Argument was enabled.");
	}
}

#assign source lot as wafer name
my $wafer = $model->wafers;
$header->SOURCE_LOT(formatSourceLot($header->{SOURCE_LOT}, $header->{LOT}));
if ($header->SOURCE_LOT ne "" && !($hOptions{FINALLOT})) {
  my $sourceLot = $header->{SOURCE_LOT};
	$sourceLot =~ s/\.S$//;
  $wafer->[0]->name($sourceLot."_".sprintf("%02d",$wafer->[0]->number));
  $PPlogger->setWaferFlag(1);
}

$model->updateProgram("MAP_PGM");

my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);
$formatter->dataItems([qw/x y soft_bin/]);
$formatter->printBinmap;


dpExit(0);
