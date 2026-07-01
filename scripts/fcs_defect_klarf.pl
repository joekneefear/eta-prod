#!/usr/bin/env perl_db
=pod

=head1 SYNOPSIS

  fcs_defect_klarf.pl <Input flie name>
	--out <output dir>
	--loc <location e.g. MT,CP>
	[--logfile <logfilepath>]
	[--debug|--trace]
	[--V Display version ID ] 
=head1 DESCRIPTIONS

B<This script> will read and to try to split die Klarf file and generate IFF file for dbascii

=head1 AUTHOR

B<junifferallan.garcia@fairchildsemi.com>

=head1 CHANGES

 2016-Jul-28 : new creation
 2016-Aug-18 : added support for defect with mulitple slots and wafers
 
=head1 LICENSE

(C) Fairchild Semiconductor. 2016 All rights reserved.

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
use PDF::Parser::Klarf;
use PDF::DpData::Defect;
use PDF::Formatter;
use PDF::DAO;
use PPLOG::PPLogger; 	


our $VERSION = "1.0";
our $TESTER  = "Klarf";
my $PPlogger = new PPLOG::PPLogger();
my (%hOptions) = ();



# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "SITE=s", "LOC=s", "LOGFILE=s", "DEBUG","V", "TRACE", "PPLOG" )
    )
{
    dpExit( 1, "invalid options" );
}
if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT LOC/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

##Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  
}

my $location = $hOptions{LOC};
my $debug = 0;
if($hOptions{DEBUG}) {
	$debug = 1;
}

# Read input file
my $infile = $ARGV[0];

## Set Raw File ==> infile 
$PPlogger->setRawFile($infile);

if ( !-f $infile ) {
    pod2usage();
    dpExit( 1, "input file does not exist $infile" );
}

my $wr = PDF::DpWriter->new(
   {   outdir   => $hOptions{OUT},
       basename => ( basename $infile),
       ext      => 'iff'
   }
);

my $parser = PDF::Parser::Klarf->new;
my $model = $parser->splitDie($infile, $debug, $location);

my $defect = $model->defect;
my $header = $model->header;

#$defect->LOCATION($location);

$PPlogger->setLot($header->{LOT});


if($model->{forSBflag}) {
	$wr->noMeta(1);
}

my $formatter = new_iff_formatter(
    {   model  => $model,
        writer => $wr
    }
);

#my @waferArray = ();
##INFO("TEST @{$model->defect->wafers}");
#foreach my $wafer (@{$model->defect->wafers}){
#		#my $key = $wafer->START_TIME ;
#		#unless (exists $group{$key}) {
#		#	$group{$key} = [];
#		#}
#		INFO("WAFER=>$wafer");
#		push @waferArray, $wafer;
#}
#my @slotArray = ();
#foreach my $slot (@{$model->defect->slots}){
#	
#		INFO("Slot=>$slot");
#		push @slotArray, $slot;
#}
#my @imageArray = ();
#foreach my $image (@{$model->defect->images}){
#		
#		INFO("Image=>$image");
#		push @imageArray, $image;
#}
#my @imageIndexes = ();
#foreach my $imgIndex (@{$model->defect->imageIndexes}){
#		
#		INFO("ImageIndex=>$imgIndex");
#		push @imageIndexes, $imgIndex;
#}
#my @defectIndexes = ();
#foreach my $defectIndex (@{$model->defect->defectIndexes}){
#		
#		INFO("DefectIndex=>$defectIndex");
#		push @defectIndexes, $defectIndex;
#}
my @waferArray = @{$model->defect->wafers};
my @slotArray = @{$model->defect->slots};
my @imageArray = @{$model->defect->images};
my @imageIndexes = @{$model->defect->imageIndexes};
my @defectIndexes = @{$model->defect->defectIndexes};

if ($debug) {
	print "DEFINDXES=>@defectIndexes\n";
	if ($#imageArray != -1) {
		INFO("Image count=>$#imageArray+1");
	} 
	if ($#imageIndexes != -1) {
		INFO("Image_Indexes count=>$#imageIndexes");
	} 
	if ($#defectIndexes != -1) {
		INFO("Defect_Indexes count=>$#defectIndexes");
	} 
	
}

my $imageExistFlag = 1;

for (my $i = 0; $i <= $#slotArray; $i++) {
	if($imageArray[0] ne "" && $imageExistFlag == 1) {
	 for(my $x = 0; $x <= $#imageArray; $x++){
	 	INFO("SLOT=$slotArray[$i], Wafer=$waferArray[$i], Image=$imageArray[$x], DefectIndex=$defectIndexes[$x], ImageIndex=$imageIndexes[$x]");
	 	INFO("With Image associated on Slot");
	 	$model->defect->registerToRefdbWithDefectInfo($slotArray[$i], $waferArray[$i], $imageArray[$x], $defectIndexes[$x], $imageIndexes[$x]);
	 }
	 $imageExistFlag = 0;
	} else {
		INFO("NO Image/s associated on Slot");
		$model->defect->registerToRefdb($slotArray[$i], $waferArray[$i]);
	}
}


$formatter->printDefect();

#$model->defect->registerToRefdb();


dpExit(0);

