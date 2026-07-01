#!/bin/env perl_db
#
# 31-Aug-2021 Eric A.   initial release

use strict;
use FindBin::libs;
use PDF::Parser::SicEcofA;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use PDF::DpWriter;
use PDF::Formatter;
use PDF::WS;
use PPLOG::PPLogger;
use Getopt::Long;
use File::Basename qw(basename dirname);
use Data::Dumper qw(Dumper);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use v5.10;

our $VERSION ="1.0";

my (%hOptions) = ();
my $pplogger = new PPLOG::PPLogger();

if ( $#ARGV < 0 ) {
        print "Usage: $0 <FILENAME> <OPTIONS>\n";
        exit 1;
}
unless (
        GetOptions(
                \%hOptions,  "OUT=s", "LOGFILE=s", "DEBUG", "TRACE", "ARCHIVE=s", "DETAILS", "COORDINATES", "PUCK", "PPLOG", "BACKEND", "RAW"
        )
)
{
        print "Invalid options.\n";
        exit;
}

my @required_options = qw/OUT/;

if (grep { !exists $hOptions{$_} } @required_options) {
        print "Error! Missing required options.\n";
        exit 1;
}

PDF::Log->init(\%hOptions ,$pplogger);
if ($hOptions{PPLOG}){
        $pplogger->settobeLog(1);
}

my $infile = $ARGV[0];
my $outdir = $hOptions{OUT};
my $arcdir = $hOptions{ARCHIVE};
my $fname = basename $infile;
my @fnameArr = split /_/, $fname;

$pplogger->setRawFile($infile);

if ( ! -f $infile ) {
        dpExit(1,"Error! File does not exists.");
}


INFO ("Infile = $infile");

my $dcom_file = $infile;
if ($infile =~ /\.gz$/) {
        $dcom_file =~ s/\.gz$//;
        gunzip $infile => $dcom_file or die "gunzip failed: $GunzipError\n";
        INFO ("UnGzipped file = $dcom_file");
}
elsif ($infile =~ /\.zip$/) {
        $dcom_file =~ s/\.zip$//;
        unzip $infile => $dcom_file or die "unzip failed: $UnzipError\n";
        INFO ("UnZipped file = $dcom_file");
}

if ($hOptions{DETAILS}){
	my $parser = PDF::Parser::SicEcofA->new;
	my $wfrDetails = $parser->readWaferDetails($dcom_file);
	my $fCnt = 0;

	foreach my $partNumber ( keys %$wfrDetails ) {
		foreach my $vendorLotId (keys %{$$wfrDetails{$partNumber}}) {
			foreach my $globalWaferId (keys %{$$wfrDetails{$partNumber}{$vendorLotId}}) {
				$fCnt++;
				my $fnameOut = ($infile)."_".$fCnt;
				my $wr = PDF::DpWriter->new({ outdir => $hOptions{OUT}, basename => $fnameOut , ext => 'iff', gzipIFF => 'Y'});
				my $header = new_ecofaheaderLong;
				my $model = new_model({header => $header, misc => {}, dataSource => 'SIC_ECOFA'});

				my $waferParamNameAddr = $$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{WAFER_PARAM_NAME};
				my $unitOfMeasureAddr = $$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{UNIT_OF_MEASURE};
				my $valueAddr = $$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{VALUE};
				#my $metrologyToolAddr = $$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{METROLOGY_TOOL};
				my $specLslAddr = $$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{SPEC_LSL};
				my $specUslAddr = $$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{SPEC_USL};

				$header = $model->header;
				$header->LOT($vendorLotId);
				$header->PROGRAM($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{PART_NUMBER});
				$header->PROGRAM_CLASS(35);
				$header->PRODUCT($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{PART_NUMBER});
				$header->DATA_FILE_NAME($fname);
				$header->WAFER_SCRIBE_ID($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{WAFER_SCRIBE_ID});
				$header->GLOBAL_WAFER_ID($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{GLOBAL_WAFER_ID});
				$header->PART_NUMBER($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{PART_NUMBER});
				$header->BOULE_ID($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{BOULE_ID});
				$header->WAFER_SLICE_POSITION($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{WAFER_SLICE_POSITION});
				$header->SLOT($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{SLOT});
				$header->VENDOR_SITE($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{VENDOR_SITE});
				$header->SHIP_TO_LOC_CD($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{SHIP_TO_LOC_CD});
				$header->VENDOR_LOT_ID($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{VENDOR_LOT_ID});
				$header->MFG_DATE($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{MFG_DATE});
				$header->START_TIME($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{MFG_DATE}." 00:00:00");
				$header->END_TIME($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{MFG_DATE}." 00:00:00");

				my $wafer = $model->find('wafers',{ name => $$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{WAFER_SCRIBE_ID} });

				unless (defined $wafer){
					$wafer = new_wafer( { name => $$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{WAFER_SCRIBE_ID} } );
					$wafer->name($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{WAFER_SCRIBE_ID});
					$wafer->number($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{WAFER_SLICE_POSITION});
					$model->add('wafers',$wafer);
				}

				my $die = new_die;
				$wafer->add('dies',$die);

				my $limit = new_limit;

				for (my $i=0; $i<=$#$waferParamNameAddr; $i++){
					my $test = new_test;
					$test->number("N/A");
					$test->name(repNA($$waferParamNameAddr[$i]));
					$test->units(repNA($$unitOfMeasureAddr[$i]));
					$test->HSL(repNA($$specUslAddr[$i]));
					$test->LSL(repNA($$specLslAddr[$i]));
					$limit->add('tests', $test);
				}

				$model->tests($limit->tests); #store test num, name, unit
				my $testCnt = scalar @{$model->tests};

				my $i = 0;
				foreach my $t (@{$model->tests}) {
					#print "$$valueAddr[$i]->{$t->{name}}\n";
					$die->x("N/A");
					$die->y("N/A");
					$die->add( 'result', repNA($$valueAddr[$i]->{$t->{name}}));
					$i++;
				}

				my $formatter = new_iff_formatter({ model => $model, writer => $wr });
				$formatter->dataItems([qw/x y/]);
				$formatter->testItems([qw/number name units LSL HSL/]);
				$formatter->printPar_v3($$wfrDetails{$partNumber}{$vendorLotId}{$globalWaferId}{WAFER_SCRIBE_ID});

				#Output Limit
				#$limit->copyHeader($header);
				#$model->limit($limit);
				#$model->buildLimit;
				#$formatter->printLimit;	
			}
		}
	}
}
elsif ($hOptions{COORDINATES}){
	my $parser = PDF::Parser::SicEcofA->new;
	my $wfrCoordinates = $parser->readWaferCoordinates($dcom_file);
	my $fCnt = 0;
	
	foreach my $partNumber (keys %$wfrCoordinates) {
		foreach my $globalWaferId (keys %{$$wfrCoordinates{$partNumber}}) {
			$fCnt++;
			my $fnameOut = basename($infile)."_".$fCnt;
			my $wr = PDF::DpWriter->new({ outdir => $hOptions{OUT}, basename => $fnameOut, ext => 'iff', gzipIFF => 'Y'});
			my $header = new_ecofaheaderLong;
			my $model = new_model({header => $header, misc => {}, dataSource => 'SIC_ECOFA'});

			my $waferParamNameAddr = $$wfrCoordinates{$partNumber}{$globalWaferId}{WAFER_PARAM_NAME};
			my $unitOfMeasureAddr = $$wfrCoordinates{$partNumber}{$globalWaferId}{UNIT_OF_MEASURE};
			my $xCoordinateAddr = $$wfrCoordinates{$partNumber}{$globalWaferId}{X_COORDINATE};
			my $yCoordinateAddr = $$wfrCoordinates{$partNumber}{$globalWaferId}{Y_COORDINATE};
			my $valueAddr = $$wfrCoordinates{$partNumber}{$globalWaferId}{VALUE};
			#my $metrologyToolAddr = $$wfrCoordinates{$partNumber}{$globalWaferId}{METROLOGY_TOOL};
			my $specLslAddr = $$wfrCoordinates{$partNumber}{$globalWaferId}{SPEC_LSL};
			my $specUslAddr = $$wfrCoordinates{$partNumber}{$globalWaferId}{SPEC_USL};

			$header = $model->header;
			$header->LOT($$wfrCoordinates{$partNumber}{$globalWaferId}{VENDOR_LOT_ID});
			$header->PROGRAM($$wfrCoordinates{$partNumber}{$globalWaferId}{PART_NUMBER});
			$header->PROGRAM_CLASS(35);
			$header->PRODUCT($$wfrCoordinates{$partNumber}{$globalWaferId}{PART_NUMBER});
			$header->DATA_FILE_NAME($fname);
			$header->WAFER_SCRIBE_ID($$wfrCoordinates{$partNumber}{$globalWaferId}{WAFER_SCRIBE_ID});
			$header->GLOBAL_WAFER_ID($globalWaferId);
			$header->PART_NUMBER($$wfrCoordinates{$partNumber}{$globalWaferId}{PART_NUMBER});
			$header->BOULE_ID($$wfrCoordinates{$partNumber}{$globalWaferId}{BOULE_ID});
			$header->WAFER_SLICE_POSITION($$wfrCoordinates{$partNumber}{$globalWaferId}{WAFER_SLICE_POSITION});
			$header->SLOT($$wfrCoordinates{$partNumber}{$globalWaferId}{SLOT});
			$header->VENDOR_SITE($$wfrCoordinates{$partNumber}{$globalWaferId}{VENDOR_SITE});
			$header->SHIP_TO_LOC_CD($$wfrCoordinates{$partNumber}{$globalWaferId}{SHIP_TO_LOC_CD});
			$header->VENDOR_LOT_ID($$wfrCoordinates{$partNumber}{$globalWaferId}{VENDOR_LOT_ID});
			$header->MFG_DATE($$wfrCoordinates{$partNumber}{$globalWaferId}{MFG_DATE});
			$header->START_TIME($$wfrCoordinates{$partNumber}{$globalWaferId}{MFG_DATE}." 00:00:00");
			$header->END_TIME($$wfrCoordinates{$partNumber}{$globalWaferId}{MFG_DATE}." 00:00:00");

			my $wafer = $model->find('wafers',{ name => $$wfrCoordinates{$partNumber}{$globalWaferId}{WAFER_SCRIBE_ID}});

			unless (defined $wafer){
				$wafer = new_wafer( { name => $$wfrCoordinates{$partNumber}{$globalWaferId}{WAFER_SCRIBE_ID} } );
				$wafer->name($$wfrCoordinates{$partNumber}{$globalWaferId}{WAFER_SCRIBE_ID});
				$wafer->number($$wfrCoordinates{$partNumber}{$globalWaferId}{WAFER_SLICE_POSITION});
				$model->add('wafers',$wafer);
			}

			# set default wmap config
			my $wmap = new_wmap;
			$wmap->wf_size(150);
			$wmap->wf_units("mm");
			$wmap->flat('B');
			$wmap->flat_type('N');
			$wmap->die_width(1);
			$wmap->die_height(1);
			$wmap->center_x(0);
			$wmap->center_y(0);
			$wmap->positive_x('R');
			$wmap->positive_y('U');
			$wmap->reticle_rows(1);
			$wmap->reticle_cols(1);
			$wmap->reticle_row_offset(0);
			$wmap->reticle_col_offset(0);
			$model->wmap($wmap);

			my $limit = new_limit;
	
			for (my $i=0; $i<=$#$waferParamNameAddr; $i++){
				my $test = $limit->find('tests', { name => $$waferParamNameAddr[$i]} );
				unless (defined $test) {
					$test = new_test;
					$test->name(repNA($$waferParamNameAddr[$i]));
					$test->number("N/A");
					$test->units(repNA($$unitOfMeasureAddr[$i]));
					$test->HSL($$specUslAddr[$i]);
					$test->LSL($$specLslAddr[$i]);
					$limit->add('tests', $test);
				}
			}

			$model->tests($limit->tests); #store test num, name, unit
			my $testCnt = scalar @{$model->tests};

			for (my $i=0; $i<=$#$xCoordinateAddr; $i++) {
				my $die = new_die;
				$die->org_x($$xCoordinateAddr[$i]);
				$die->org_y($$yCoordinateAddr[$i]);
				$die->x(int($$xCoordinateAddr[$i]));  #rounded down integer
				$die->y(int($$yCoordinateAddr[$i]));  #rounded down integer

				foreach my $t (@{$model->tests}) {
					#print "$$valueAddr[$i]->{$t->{name}}\n";
					$die->add('result',repNA($$valueAddr[$i]->{$t->{name}}));
				}

				$wafer->add('dies',$die);
			}

			my $formatter = new_iff_formatter({ model => $model, writer => $wr });
			$formatter->dataItems([qw/org_x org_y x y /]);
			$formatter->testItems([qw/number name units LSL HSL/]);
			$formatter->printPar_v3($$wfrCoordinates{$partNumber}{$globalWaferId}{WAFER_SCRIBE_ID});

			#Output Limit
			#$limit->copyHeader($header);
			#$model->limit($limit);
			#$model->buildLimit;
			#$formatter->printLimit;
		}
	}
		
}
elsif ($hOptions{PUCK}) {
	my $parser = PDF::Parser::SicEcofA->new;
	my $puck = $parser->readPuck($dcom_file);
	my $fCnt = 0;

	foreach my $VendorLotId ( keys %$puck ) {
		$fCnt++;
		my $fnameOut = basename($infile)."_".$fCnt;
		my $wr = PDF::DpWriter->new({ outdir => $hOptions{OUT}, basename => $fnameOut, ext => 'iff', gzipIFF => 'Y'});
		my $header = new_ecofaheaderLong;
		my $model = new_model({header => $header, misc => {}, dataSource => 'SIC_ECOFA'});

		my $die = new_die;
		my $waferId = $VendorLotId."_00";
		my $wafer = $model->find('wafers',{ name => $waferId });

		unless (defined $wafer){
			$wafer = new_wafer( { name => $waferId } );
			$wafer->name($waferId);
			$wafer->number("N/A");
			$model->add('wafers',$wafer);
		}

		$wafer->add('dies',$die);
		
		foreach my $OnParamName ( keys %{$$puck{$VendorLotId}} ) {
			my $SpecLslAddr = $$puck{$OnParamName}{SPEC_LSL};
			my $SpecUslAddr = $$puck{$OnParamName}{SPEC_USL};
			my $specNumber = "";
			my $revision = "";
			my $partNumber = "";
			my $vendorSite = "";
			my $shipToLocCd = "";
			my $shipNumber = "";
			my $recipe = "";
			my $qty = "";
			my $shippingFromLocCd = "";
			my $grade = "";
			my $rawSiliconLotId = "";
			my $surfaceConditions = "";
			my $description = "";
			my $mfgDate = "";
			
			my $test = new_test;
			$test->number("N/A");
			$test->name(repNA($OnParamName));
			$model->add('tests',$test);

			#keep none empty headers. 
			foreach my $VendorMeasurementName ( keys %{$$puck{$VendorLotId}{$OnParamName}} ) {
				if ($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{PART_NUMBER}  ne "") {
					$partNumber = $$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{PART_NUMBER};
				}
				if ($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{SPEC_NUMBER} ne "") {
					$specNumber = $$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{SPEC_NUMBER};
				}
				if ($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{REVISION} ne "") {
					$revision = $$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{REVISION}
				}
				if ($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{VENDOR_SITE} ne "") {
					$vendorSite = $$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{VENDOR_SITE};
				}
				if ($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{SHIP_TO_LOC_CD} ne "") {
					$shipToLocCd = $$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{SHIP_TO_LOC_CD};	
				}
				if ($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{SHIP_NUMBER} ne "") {
					$shipNumber = $$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{SHIP_NUMBER};
				}
				if ($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{RECIPE} ne "") {
					$recipe = $$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{RECIPE};
				}
				if ($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{QTY} ne "") {
					$qty = $$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{QTY};
				}
				if ($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{SHIPPING_FROM_LOC_CD} ne "") {			
					$shippingFromLocCd = $$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{SHIPPING_FROM_LOC_CD};
				}
				if ($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{MFG_DATE} ne "") {
					$mfgDate = $$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{MFG_DATE};
				}
				if ($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{RAWSILICON_LOT_ID}) {
					$rawSiliconLotId = $$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{RAWSILICON_LOT_ID};
				}
				if ($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{SURFACE_CONDITIONS}) {
					$surfaceConditions = $$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{SURFACE_CONDITIONS};
				}
				if ($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{DESCRIPTION}) {
					$description = $$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{DESCRIPTION};
				}
				
			}	
			
			#in some cases parameters does not have results but has spec limits
			#foreach my $VendorMeasurementName ( keys %{$$puck{$VendorLotId}{$OnParamName}} ) {
			foreach my $VendorMeasurementName ("SPEC_LSL","SPEC_USL","ACTUAL") {
				if ($VendorMeasurementName eq "SPEC_LSL" || $VendorMeasurementName eq "SPEC_USL") {
					$test->units(repNA($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{UNIT_OF_MEASURE}));
					$test->LSL(repNA($$puck{$VendorLotId}{$OnParamName}{SPEC_LSL}{VALUE}));
					$test->HSL(repNA($$puck{$VendorLotId}{$OnParamName}{SPEC_USL}{VALUE}));
				}
				else {

					my $srclot = substr $VendorLotId, 0, 9;
					$header = $model->header;
                                	$header->LOT($VendorLotId);
					$header->SOURCE_LOT($srclot.".S");
                                	$header->PROGRAM($partNumber."::".$specNumber);
                                	$header->PROGRAM_CLASS(35);
                                	$header->REVISION($revision);
                                	$header->PRODUCT($partNumber);
                                	$header->DATA_FILE_NAME($fname);
                                	$header->PART_NUMBER($partNumber);
                                	$header->VENDOR_SITE($vendorSite);
                                	$header->SHIP_TO_LOC_CD($shipToLocCd);
                                	$header->VENDOR_LOT_ID($VendorLotId);
                                	$header->MFG_DATE($mfgDate);
                                	$header->START_TIME($mfgDate." 00:00:00");
                                	$header->END_TIME($mfgDate." 00:00:00");
                               		$header->SHIP_NUMBER($shipNumber);
                                	$header->RECIPE($recipe);
                                	$header->QTY($qty);
                                	$header->SHIPPING_FROM_LOC_CD($shippingFromLocCd);
                                	$header->SPEC_NUMBER($specNumber);
                                	$header->GRADE($grade);
                                	$header->RAWSILICON_LOT_ID($rawSiliconLotId);
					$header->SURFACE_CONDITIONS($surfaceConditions);
					$header->DESCRIPTION($description);

					$test->units(repNA($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{UNIT_OF_MEASURE}));
					
					$die->add( 'result', repNA($$puck{$VendorLotId}{$OnParamName}{$VendorMeasurementName}{VALUE}));
				}
			}
			
		}

		my $formatter = new_iff_formatter({ model => $model, writer => $wr });
		$formatter->dataItems([qw/x y/]);
		$formatter->testItems([qw/number name units LSL HSL/]);
		$formatter->printPar_v3($VendorLotId);

		#Output Limit
		##$limit->copyHeader($header);
		##$model->limit($limit);
		##$model->buildLimit;
		##$formatter->printLimit;
	}	
}
elsif ($hOptions{BACKEND}) {
	my $parser = PDF::Parser::SicEcofA->new;
	my $backend = $parser->readBackend($dcom_file);
	#print Dumper($backend);
	my $fCnt = 0;

	foreach my $VendorLotId ( keys %$backend ) {
		$fCnt++;
		my $fnameOut = basename($infile)."_".$fCnt;
		my $wr = PDF::DpWriter->new({ outdir => $hOptions{OUT}, basename => $fnameOut, ext => 'iff', gzipIFF => 'Y'});
		my $header = new_ecofaheaderLong;
		my $model = new_model({header => $header, misc => {}, dataSource => 'SIC_ECOFA'});
		
		foreach my $ShipNumber (keys %{$$backend{$VendorLotId}}) {		
			#my $fnameOut = basename($infile)."_".$fCnt;
			#my $wr = PDF::DpWriter->new({ outdir => $hOptions{OUT}, basename => $fnameOut, ext => 'iff', gzipIFF => 'Y'});
			#my $header = new_ecofaheaderLong;
			#my $model = new_model({header => $header, misc => {}, dataSource => 'SIC_ECOFA'});

			my $die = new_die;
			my $waferId = $ShipNumber;
			my $wafer = $model->find('wafers',{ name => $waferId });

			unless (defined $wafer){
				$wafer = new_wafer( { name => $waferId } );
				$wafer->name($waferId);
				$wafer->number("N/A");
				$model->add('wafers',$wafer);
			}

			$wafer->add('dies',$die);
		
			foreach my $Parameter (keys %{$$backend{$VendorLotId}{$ShipNumber}}) {
				#print"\t$Parameter\n";
				my $AverageAddr = $$backend{$Parameter}{AVERAGE};
				my $MaximumAddr = $$backend{$Parameter}{MAXIMUM};
				my $MinimumAddr = $$backend{$Parameter}{MINIMUM};
				my $StdevArr = $$backend{$Parameter}{STDEV};
				my $VendorSite = "";
				my $PartNumber = "";
				my $Qty = "";
				my $ShipToLocCd = "";
				my $ShippingFromLocCd = "";
				#my $VendorLotId = "";
				my $MetrologyTool = "";
				my $SpecNumber = "";
				my $Revision = "";
				my $MfgDate = "";
				my $VendorPartNumber = "";
				my $MotherLotNumber = "";
				my $ExpirationDate = "";
				my $Cpk = "";
				my $Result = "";
				#my $ShipNumber = "";

				my $test = new_test;
				$test->number("N/A");
				$test->name(repNA($Parameter));
				$model->add('tests',$test);

				#keep none empty headers.
				foreach my $VendorMeasurementName ( keys %{$$backend{$VendorLotId}{$ShipNumber}{$Parameter}} ) {
					#print"\t\t$VendorMeasurementName\n";
					if ($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{VENDOR_SITE} ne "") {
						$VendorSite = $$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{VENDOR_SITE};
					}

					if ($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{PART_NUMBER} ne "") {
						$PartNumber = $$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{PART_NUMBER};
					}


					if ($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{VENDOR_LOT_ID} ne "") {
						$VendorLotId = $$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{VENDOR_LOT_ID};
					}

					if ($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{QTY} ne "") {
						$Qty = $$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{QTY};
					}

					if ($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{SHIP_TO_LOC_CD} ne "") {
						$ShipToLocCd = $$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{SHIP_TO_LOC_CD};
					}

					if ($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{SHIPPING_FROM_LOC_CD} ne "") {
						$ShippingFromLocCd = $$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{SHIPPING_FROM_LOC_CD};
					}

					if ($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{METROLOGY_TOOL} ne "") {
						$MetrologyTool = $$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{METROLOGY_TOOL};
					}

					if ($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{SPEC_NUMBER} ne "") {
						$SpecNumber = $$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{SPEC_NUMBER};
					}

					if ($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{REVISION} ne "") {
						$Revision = $$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{REVISION};
					}

					if ($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{MFG_DATE} ne "") {
						$MfgDate = $$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{MFG_DATE};
					}

					if ($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{VENDOR_PART_NUMBER} ne "") {
						$VendorPartNumber = $$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{VENDOR_PART_NUMBER};
					}

					if ($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{MOTHER_LOT_NUMBER} ne "") {
						$MotherLotNumber = $$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{MOTHER_LOT_NUMBER};
					}

					if ($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{EXPIRATION_DATE} ne "") {
						$ExpirationDate = $$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{EXPIRATION_DATE};
					}
				
				}

				$header = $model->header;
				$header->PROGRAM($PartNumber."::".$SpecNumber);
				$header->PROGRAM_CLASS(35);
				$header->REVISION($Revision);
				$header->PRODUCT($PartNumber);
				$header->LOT($VendorLotId);
				$header->SOURCE_LOT($VendorLotId.".S") if $VendorLotId ne "N/A";
				$header->VENDOR_SITE($VendorSite);
				$header->VENDOR_LOT_ID($VendorLotId);
				$header->PART_NUMBER($PartNumber);
				$header->SHIP_TO_LOC_CD($ShipToLocCd);
				$header->MFG_DATE($MfgDate);
				$header->SHIP_NUMBER($ShipNumber);
				$header->QTY($Qty);
				$header->SHIPPING_FROM_LOC_CD($ShippingFromLocCd);
				$header->SPEC_NUMBER($SpecNumber);
				$header->GRADE($Result);
				$header->START_TIME($MfgDate." 00:00:00");
				$header->END_TIME($MfgDate." 00:00:00");
				$header->METROLOGY_TOOL($MetrologyTool);
				$header->VENDOR_PART_NUMBER($VendorPartNumber);
				$header->EXPIRATION_DATE($ExpirationDate);
				$header->DATA_FILE_NAME($fname);
				$header->FAB($VendorSite);
				$header->MOTHER_LOT_NUMBER($MotherLotNumber);

				foreach my $VendorMeasurementName ("MAXIMUM","AVERAGE","STDEV","MINIMUM","SPEC_LSL","SPEC_USL","RESULT","CPK") {
					if($VendorMeasurementName eq "SPEC_LSL" || $VendorMeasurementName eq "SPEC_USL"){
						$test->units(repNA($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName}{UNIT_OF_MEASURE}));
						$test->LSL(repNA($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{SPEC_LSL}{VALUE}));
						$test->HSL(repNA($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{SPEC_USL}{VALUE}));
					}
					else{
						$die->add('level',"lot");
						if($VendorMeasurementName eq "MAXIMUM"){
								$die->add('max',repNA($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{MAXIMUM}{VALUE}));
						}
						elsif($VendorMeasurementName eq "AVERAGE"){
							$die->add('mean',repNA($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{AVERAGE}{VALUE}));
						}
						elsif($VendorMeasurementName eq "STDEV"){
							$die->add('sdev',repNA($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{STDEV}{VALUE}));
						}
						elsif($VendorMeasurementName eq "MINIMUM"){
							$die->add('min',repNA($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{MINIMUM}{VALUE}));
						}
						elsif($VendorMeasurementName eq "RESULT") {
							my $pf = repNA($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{RESULT}{RESULT});
							$pf = ($pf eq "PASS") ? 0 : 1;
							$die->add('pass_fail',repNA($pf));
						}
						elsif($VendorMeasurementName eq "CPK") {
							$die->add('cpk',repNA($$backend{$VendorLotId}{$ShipNumber}{$Parameter}{CPK}{CPK}));
						}
					}
				}
			}				
		}

		my $formatter = new_iff_formatter({ model => $model, writer => $wr });
		$formatter->dataItems([qw//]);
		$formatter->testItems([qw/number name units LSL HSL/]);
		$formatter->printPar_v6($VendorLotId);
	}	
}
elsif ($hOptions{RAW}) {
	my $parser = PDF::Parser::SicEcofA->new;
	my $raw = $parser->readRaw($dcom_file);
	#print Dumper($raw);	
	
	my $fCnt = 0;

	foreach my $VendorLotId ( keys %$raw ) {
		$fCnt++;
		my $fnameOut = basename($infile)."_".$fCnt;
		my $wr = PDF::DpWriter->new({ outdir => $hOptions{OUT}, basename => $fnameOut, ext => 'iff', gzipIFF => 'Y'});
		my $header = new_ecofaheaderLong;
		my $model = new_model({header => $header, misc => {}, dataSource => 'SIC_ECOFA'});
		
		foreach my $ShipNumber (keys %{$$raw{$VendorLotId}}) {
			my $die = new_die;
			my $waferId = $ShipNumber;
			my $wafer = $model->find('wafers',{ name => $waferId });

			unless (defined $wafer){
				$wafer = new_wafer( { name => $waferId } );
				$wafer->name($waferId);
				$wafer->number("N/A");
				$model->add('wafers',$wafer);
			}
			$wafer->add('dies',$die);
		
			foreach my $Parameter (keys %{$$raw{$VendorLotId}{$ShipNumber}}) {
				my $VendorSite = "";
				#my $ShipNumber = "";
				my $PartNumber = "";
				#my $VendorLotId = "";
				my $Quantity = "";
				my $ShipToLocCd = "";
				my $ShippingFromLocCd = "";
				my $SubstrateLotId = "";
				my $SubstrateSiteId = "";
				#my $Parameter = "";
				my $Average = "";
				my $Stdev = "";
				my $Minimum = "";
				my $Maximum;
				my $SampleSize = "";
				my $SpecLsl = "";
				my $SpecUsl = "";
				my $Unit = "";
				
				my $test = new_test;
				$test->number("N/A");
				$test->name(repNA($Parameter));
				$model->add('tests',$test);

				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{VENDOR_SITE} ne "") {		
					$VendorSite = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{VENDOR_SITE};	
				}		
				#if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SHIP_NUMBER} ne "") {		
				#	$ShipNumber = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SHIP_NUMBER};	
				#}			
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{PART_NUMBER} ne "") {		
					$PartNumber = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{PART_NUMBER};	
				}		
				#if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{VENDOR_LOT_ID} ne "") {		
				#	$VendorLotId = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{VENDOR_LOT_ID};	
				#}		
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{QUANTITY} ne "") {		
					$Quantity = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{QUANTITY};	
				}		
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SHIP_TO_LOC_CD} ne "") {		
					$ShipToLocCd = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SHIP_TO_LOC_CD};	
				}		
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SHIPPING_FROM_LOC_CD} ne "") {		
					$ShippingFromLocCd = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SHIPPING_FROM_LOC_CD};	
				}		
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SUBSTRATE_LOT_ID} ne "") {		
					$SubstrateLotId = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SUBSTRATE_LOT_ID};	
				}		
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SUBSTRATE_SITE_ID} ne "") {		
					$SubstrateSiteId = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SUBSTRATE_SITE_ID};	
				}		
				#if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{PARAMETER} ne "") {		
				#	$Parameter = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{PARAMETER};	
				#}		
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{AVERAGE} ne "") {		
					$Average = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{AVERAGE};	
				}		
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{STDEV} ne "") {		
					$Stdev = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{STDEV};	
				}		
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{MINIMUM} ne "") {		
					$Minimum = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{MINIMUM};	
				}		
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{MAXIMUM} ne "") {		
					$Maximum = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{MAXIMUM};	
				}		
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SAMPLE_SIZE} ne "") {		
					$SampleSize = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SAMPLE_SIZE};	
				}		
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SPEC_LSL} ne "") {		
					$SpecLsl = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SPEC_LSL};	
				}		
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SPEC_USL} ne "") {		
					$SpecUsl = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{SPEC_USL};	
				}		
				if ($$raw{$VendorLotId}{$ShipNumber}{$Parameter}{UNIT} ne "") {		
					$Unit = $$raw{$VendorLotId}{$ShipNumber}{$Parameter}{UNIT};	
				}		

				$header = $model->header;
				$header->PROGRAM("ECOA_SILICON_".$VendorSite."_".$PartNumber);
				$header->PROGRAM_CLASS(35);
				$header->STEP("ECOA");
				$header->PRODUCT($PartNumber);
				$header->LOT($VendorLotId);
				$header->SOURCE_LOT($VendorLotId.".S") if $VendorLotId ne "N/A";
				$header->VENDOR_SITE($VendorSite);
				$header->VENDOR_LOT_ID($VendorLotId);
				$header->PART_NUMBER($PartNumber);
				$header->SHIP_TO_LOC_CD($ShipToLocCd);				
				$header->SHIP_NUMBER($ShipNumber);
				$header->QTY($Quantity);
				$header->SHIPPING_FROM_LOC_CD($ShippingFromLocCd);	
				$header->START_TIME($fnameArr[$#fnameArr]);
				$header->END_TIME($fnameArr[$#fnameArr]);				
				$header->DATA_FILE_NAME($fname);
				$header->FAB($VendorSite);
				$header->SUBSTRATE_LOT_ID($SubstrateLotId);
				$header->SUBSTRATE_SITE_ID($SubstrateSiteId);
				$header->SAMPLE_SIZE($SampleSize);
				
				$test->units(repNA($SpecLsl));
				$test->LSL(repNA($SpecUsl));
				$test->HSL(repNA($Unit));
				
				$die->add('level',"lot");
				$die->add('mean',repNA($Average));
				$die->add('max',repNA($Maximum));
				$die->add('sdev',repNA($Stdev));
				$die->add('min',repNA($Minimum));
			}
			
		}
				
		my $formatter = new_iff_formatter({ model => $model, writer => $wr });
		$formatter->dataItems([qw//]);
		$formatter->testItems([qw/number name units LSL HSL/]);
		#$formatter->printPar_v6($VendorLotId);
		$formatter->printPar_v7($VendorLotId);
	}
}
else {
	dpExit(1,"Error! DETAILS | COORDINATES | PUCK | BACKEND | RAW argument not defined.");
}

# delete residue extracted files
unlink $dcom_file if $infile =~ /\.zip/i;

dpExit(0);
