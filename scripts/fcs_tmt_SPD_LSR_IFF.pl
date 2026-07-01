#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

 
=head1 DESCRIPTIONS

B<This script> will process SPD files, and validate data in some cases.

=head1 AUTHOR

B<junifferallan.garcia@fairchildsemi.com>

=head1 CHANGES
	2015/09/10 jgarcia : check first if incoming file ends with .SPD or .LSR extension alone 
	                     otherwise the script will exit and stop the process.
	2015/11/10 eric    : always generate but do not register limit if sandbox
        2016/02/01 wsanopao: logging pre-processing information  to refdb.pp_log table.
	27-May-2016 Gilbert: Added cprel
	07-Jul-2017 Eric   : corrected how rel lot were parsed,
			     emptied dtype contains [0-9], emptied strdur & temp if contains [a-z]
        17-Feb-2017 Gilbert: Always generate limits and dont register to refdb.pp_limits.
 	2017-Apr-25 jgarcia : enhance pp script logging.
	2018-Jan-12 Eric    : parse ONRMS datalog
        2020/09/01 karen       : added support to fork output (IFF)/files to designated location
	2021-Jan-06 Karen      : added fork to LSR iff
        2021-Apr-07 Karen      : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.


=head1 LICENSE

(C) Fairchild 2015 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use File::Basename qw/basename dirname/;
use File::Copy;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::Parser::TMTSPD;
use PDF::Parser::TMTLSR;
use PDF::DpWriter;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:
use Number::Range;
use Config::Tiny;

our $VERSION = "1.0";
our $TESTER  = "TMT";
my $location = "";

# a hash to receive options
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}

unless ( GetOptions ( \%hOptions, "OUT=s", "FORK=s", "SITE=s", "LOC=s", "TPDIR=s", "FACILITYFILE=s", "FINALLOT", "LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG", "RELLOT") ) {
    pod2usage(3);
}

if($hOptions{V}) {
	print("$VERSION\n"); 
	dpExit(0);
}

my @required_options = qw/OUT SITE LOC FACILITYFILE TPDIR/;

if(grep {!exists $hOptions{$_}} @required_options) {
	pod2usage(3);
}

if ($hOptions{SITE} ne 'cpft_tmt' && $hOptions{SITE} ne 'cprel') {
	dpExit( 1, "wrong site code : $hOptions{SITE}" );
}

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});

my $inFile = $ARGV[0];
my $parserLSR=PDF::Parser::TMTLSR->new;
my $parserSPD=PDF::Parser::TMTSPD->new;
my $model;
my $wr;
my $SPD;
my $LSR;
my $location     = $hOptions{LOC};
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");
my $reglim_flg = "Y";


# wsanopao: Set Raw File ==> infile and Environment
$PPlogger->setRawFile($inFile);
$PPlogger->setEnv($hOptions{SITE},'tmt');

if($inFile !~ /\.LSR$|\.SPD$/i){
	dpExit( 1, "input file is either NOT have .SPD or .LSR extension" );
}

if ($inFile =~ /\.SPD$/i) {
	
	$SPD = $inFile;
	if ( !-f $SPD ) {
    dpExit( 1, "input file does not exist $SPD" );
	}

	 INFO("Fork dir=$hOptions{FORK}");
	 $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},
        basename => ( basename $SPD),
        ext      => 'SPD_iff',
        gzipIFF  => 'Y'
    }
	);

	
	$model = $parserSPD->readSPD($SPD, $hOptions{SITE}, $hOptions{TPDIR});
	if ($model->{misc} =~ /UNITS Inconsistent.+/ ) {
		my $header = $model->header;
		$PPlogger->setLot($header->{LOT});
		if ($hOptions{SITE} =~ /cpft.+/ || $hOptions{SITE} =~ /.+ft.+/) {
			$PPlogger->setWafNum("00");
		}
		dpExit(4, "$model->{misc}");
	} elsif ($model->{misc} =~ /Part test.+/) {
		my $header = $model->header;
		$PPlogger->setLot($header->{LOT});
		if ($hOptions{SITE} =~ /cpft.+/ || $hOptions{SITE} =~ /.+ft.+/) {
			$PPlogger->setWafNum("00");
		}
		dpExit(1, "$model->{misc}");
	} elsif ($model->{misc} eq "INVALID OR NO TESTPLAN REVISION") {
		my $header = $model->header;
		$PPlogger->setLot($header->{LOT});
		if ($hOptions{SITE} =~ /cpft.+/ || $hOptions{SITE} =~ /.+ft.+/) {
			$PPlogger->setWafNum("00");
		}
		dpExit(1, "$model->{misc}");
	}
	&normalizeToBaseUnit($model);
	
} else {
	
	$LSR = $inFile;
	if ( !-f $LSR ) {
    dpExit( 1, "input file does not exist $LSR" );
	}

	 INFO("Fork dir=$hOptions{FORK}");
	 $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK},
        basename => ( basename $LSR),
        ext      => 'LSR_iff',
        gzipIFF  => 'Y'
    }
	);

	
	$model = $parserLSR->readLSR($LSR, $hOptions{SITE});
	&normalizeToBaseUnit($model);
	
} 
my $header = $model->header;
$header->VERSION($VERSION);
$header->PROGRAM_CLASS(2);
$header->EQUIP6_ID( "$facility" );
$header->isFinalLot($hOptions{FINALLOT});
$header->isRelLot($hOptions{RELLOT});

if ($hOptions{SITE} eq "cprel") {
        my $base_fn = basename($SPD);
           $base_fn =~ s/\.SPD.*+//ig;
        my @item    = split /\_/, $base_fn;
	my $qpnum;
	my $devchar;
	my $lotchar;
        my $strname = $item[1];
        my $strdur  = $item[2];
        my $temp    = $item[3];
        my $dtype   = $item[4];
	   $dtype = "" if $dtype =~ /[0-9]/;

	if ($item[0] =~ /^20/ ) {  #fsc rel
		$qpnum   = substr $item[0],  0, 8;
		$devchar = substr $item[0], -2, 1;
		$lotchar = substr $item[0], -1, 1;
		$header->LOT($qpnum.$devchar.$lotchar);
	}
	elsif ($item[0] =~ /^F/i) {  #cprel_tmt onrms
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
# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);

# get MEta from database
unless ( $header->populateMeta ) {
    $wr->noMeta(1);
    $reglim_flg = "N";
}

### Use program naming rule
if ($hOptions{FINALLOT} || $hOptions{RELLOT}){
	$model->updateProgram;
}
else {
	$model->updateProgram("MAP_PGM");
}

### check if the model's forSBflag instance variable is equal to 1 or true.
### trigger the writer to output the iff file to the sanbox folder.
if($model->{forSBflag} == 1) {
	$wr->forSBox(1);
	$reglim_flg = "N";
	if($hOptions{SITE} eq 'gem_cn_ft') {
		INFO ("For SandBox loading because NO TP REVISION GEM only ");
		
	}
}
my $fmt = new_iff_formatter({
  model=>$model,
  writer=>$wr
});
  
$fmt->dataItems([qw/partid site soft_bin hard_bin/]);
$fmt->testItems([qw/number name units group/]);
$fmt->relItems([qw/qpnumber devchar lotchar strname strduration atetemp datalogtype/]);
$fmt->printPar();

# Output Limit

if ($SPD) {
   #if ($reglim_flg eq "Y"){
   # 	if ($model->isLimitNew){
   #	  $model->buildLimit;
   #	  $fmt->printLimit;
   #	  $model->limit->input_file(basename $SPD); 
   #	  $model->limit->registerRefdb;
   #	}	
   #}
   #else {  #always generate but do not register limit if sandbox
	$model->buildLimit;
	$fmt->printLimit;
	$model->limit->input_file(basename $SPD);
   #}
}
dpExit(0);
