# 06-Jan-2022 Eric Alfanta      : initial release
# 08-Mar-2024 Eric Alfanta 	: change separator in parsing puck data because some values have commas.

package PDF::Parser::SicEcofA;

use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use List::MoreUtils qw(first_index);
use Data::Dumper;

use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

sub readWaferDetails {
	my $self = shift;
	my $infile = shift;

	my %hash;
	my %fieldHash;
	my $field;
	my $lnCnt = 0;
	my $lotCnt = 0;
	my $wfrCnt = 0;

	my $waferKey;
	my $waferScribeId;
	my $globalWaferId;
	my $partNumber;
	my $bouleId;
	my $waferSlicePosition;
	my $slot;
	my $vendorSite;
	my $shipToLocCd;
	my $vendorLotId;
	my $waferParamName;
	my $unitOfMeasure;
	my $value;
	my $mfgDate;	
	my $metrologyTool;
	my $specLsl;
	my $specUsl;

	my @waferKeyArr;
	my @waferScribeIdArr;
	my @globalWaferIdArr;
	my @partNumberArr;
	my @bouleIdArr;
	my @waferSlicePositionArr;
	my @slotArr;
	my @vendorSiteArr;
	my @shipToLocCdArr;
	my @vendorLotIdArr;
	my @waferParamNameArr;
	my @unitOfMeasureArr;
	my @valueArr;
	my @mfgDateArr;
	my @metrologyToolArr;
	my @specLslArr;
	my @specUslArr;

	open(DETAILS, "<$infile") or dpExit(1,"Couldn't open $infile");
	while(my $line = <DETAILS>) {
		chomp $line;
		next if $line =~ /^\s+$/;
		$lnCnt++;

		my @arr = split /\,/, $line;

		#print $line ,"\n";
		
		if ($lnCnt == 1) {
			# Get column fields
			for (my $i=0; $i<=$#arr; $i++) {
				my $field = trim($arr[$i]);
				$fieldHash{$field} = $i;
			}	

			foreach my $field ('WAFER_KEY','WAFER_SCRIBE_ID','GLOBAL_WAFER_ID','PART_NUMBER','BOULE_ID','WAFER_SLICE_POSITION','SLOT','VENDOR_SITE','SHIP_TO_LOC_CD','VENDOR_LOT_ID','WAFER_PARAM_NAME','UNIT_OF_MEASURE','VALUE','SPEC_LSL','SPEC_USL','MFG_DATE') {
				# Check if required eolumn fields exists
				if ( exists $fieldHash{$field} ) {
					INFO ("$fieldHash{$field} : $field field exists");
				}
				else {
					dpExit(1,"$field field not found.");
				}
			
			}

		}
		elsif ($lnCnt > 1 ) {

			#initialize
			my %valueHash;

			if ( exists $fieldHash{WAFER_KEY} ) {
				my $arrValue = trim($arr[$fieldHash{WAFER_KEY}]);
				$waferKey = repNA($arrValue);
			}
			# WAFER_SCRIBE_ID
			if ( exists $fieldHash{WAFER_SCRIBE_ID} ) {
				my $arrValue = trim($arr[$fieldHash{WAFER_SCRIBE_ID}]);
				$waferScribeId = repNA($arrValue);
			} 		

			# GLOBAL_WAFER_ID
			if ( exists $fieldHash{GLOBAL_WAFER_ID} ) {
				my $arrValue = trim($arr[$fieldHash{GLOBAL_WAFER_ID}]);
				$globalWaferId = repNA($arrValue);
			}

			# PART_NUMBER
			if ( exists $fieldHash{PART_NUMBER} ) {
				my $arrValue = trim($arr[$fieldHash{PART_NUMBER}]);
				$partNumber = repNA($arrValue);
			}

			# BOULE_ID
			if ( exists $fieldHash{BOULE_ID} ) {
				my $arrValue = trim($arr[$fieldHash{BOULE_ID}]);
				$bouleId = repNA($arrValue);
			}

			# WAFER_SLICE_POSITION
			if ( exists $fieldHash{WAFER_SLICE_POSITION} ) {
				my $arrValue = trim($arr[$fieldHash{WAFER_SLICE_POSITION}]);
				$waferSlicePosition = repNA($arrValue);
			}

			# SLOT
			if ( exists $fieldHash{SLOT} ) {
				my $arrValue =  trim($arr[$fieldHash{SLOT}]);
				$slot = repNA($arrValue);
			}

			# VENDOR_SITE
			if ( exists $fieldHash{VENDOR_SITE} ) {
				my $arrValue = trim($arr[$fieldHash{VENDOR_SITE}]);
				$vendorSite = repNA($arrValue);
			}
			
			# SHIP_TO_LOC_CD
			if ( exists $fieldHash{SHIP_TO_LOC_CD} ) {
				my $arrValue = trim($arr[$fieldHash{SHIP_TO_LOC_CD}]);
				$shipToLocCd = repNA($arrValue);
			}

			# VENDOR_LOT_ID
			if ( exists $fieldHash{VENDOR_LOT_ID} ) {
				my $arrValue = trim($arr[$fieldHash{VENDOR_LOT_ID}]);
				$vendorLotId = repNA($arrValue);
			}

			# WAFER_PARAM_NAME
			if ( exists $fieldHash{WAFER_PARAM_NAME} ) {
				my $arrValue = trim($arr[$fieldHash{WAFER_PARAM_NAME}]);
				$waferParamName = repNA($arrValue);
			}

			# METROLOGY_TOOL
			#if ( exists $fieldHash{METROLOGY_TOOL} ) {
			#	my $arrValue = trim($arr[$fieldHash{METROLOGY_TOOL}]);
			#	$metrologyTool = repNA($arrValue);
			#}

			# UNIT_OF_MEASURE
			if ( exists $fieldHash{UNIT_OF_MEASURE} ) {
				my $arrValue = trim($arr[$fieldHash{UNIT_OF_MEASURE}]);
				$unitOfMeasure = repNA($arrValue);
			}

			# VALUE
			if ( exists $fieldHash{VALUE} ) {
				my $arrValue = trim($arr[$fieldHash{VALUE}]);
				$value = repNA($arrValue);
			}

			# SPEC_LSL
			if ( exists $fieldHash{SPEC_LSL} ) {
				my $arrValue = trim($arr[$fieldHash{SPEC_LSL}]);
				$specLsl = repNA($arrValue);
			}

			# SPEC_USL
			if ( exists $fieldHash{SPEC_USL} ) {
				my $arrValue = trim($arr[$fieldHash{SPEC_USL}]);
				$specUsl = repNA($arrValue);
			}

			# MFG_DATE
			if ( exists $fieldHash{MFG_DATE} ) {
				my $arrValue = trim($arr[$fieldHash{MFG_DATE}]);
				$mfgDate = repNA($arrValue);
			}

			#print "$waferScribeId,$globalWaferId,$partNumber,$bouleId,$waferSlicePosition,$slot,$vendorSite,$shipToLocCd,$vendorLotId,$waferParamName,$unitOfMeasure,$value,$mfgDate\n";

			$valueHash{$waferParamName} = $value;

			push @{$waferParamNameArr[$waferKey]}, $waferParamName;
			push @{$unitOfMeasureArr[$waferKey]}, $unitOfMeasure;
			push @{$valueArr[$waferKey]}, \%valueHash;
			#push @{$metrologyToolArr[$waferKey]}, $metrologyTool;
			push @{$specLslArr[$waferKey]}, $specLsl;
			push @{$specUslArr[$waferKey]}, $specUsl;

			#$hash{$vendorLotId}{$globalWaferId} = {
			$hash{$partNumber}{$vendorLotId}{$globalWaferId} = {
				WAFER_SCRIBE_ID => $waferScribeId,
				GLOBAL_WAFER_ID => $globalWaferId,
				PART_NUMBER => $partNumber,
				BOULE_ID => $bouleId,
				WAFER_SLICE_POSITION => $waferSlicePosition,
				SLOT => $slot,
				VENDOR_SITE => $vendorSite,
				SHIP_TO_LOC_CD => $shipToLocCd,
				VENDOR_LOT_ID => $vendorLotId,
				WAFER_PARAM_NAME => @{waferParamNameArr[$waferKey]},
				UNIT_OF_MEASURE => @{unitOfMeasureArr[$waferKey]},
				VALUE => @{valueArr[$waferKey]},
				MFG_DATE => $mfgDate,
				#METROLOGY_TOOL => @{metrologyToolArr[$waferKey]},
				SPEC_LSL => @{specLslArr[$waferKey]},
				SPEC_USL => @{specUslArr[$waferKey]}
			};	

		}		
	}	
	close DETAILS;	
	
	return \%hash;
}

sub readWaferCoordinates {
	my $self = shift;
	my $infile = shift;

	my %hash;
	my %fieldHash;
	my %duplicates;
	my $field;
	my $lnCnt = 0;
	my $lotCnt = 0;
	my $wfrCnt = 0;
	my $parCnt = 0;
	my $wKeyCnt = 0;

	my $waferKey;
	my $waferScribeId;
	my $globalWaferId;
	my $partNumber;
	my $bouleId;
	my $waferSlicePosition;
	my $slot;
	my $vendorSite;
	my $shipToLocCd;
	my $vendorLotId;
	my $waferParamName;
	my $unitOfMeasure;
	my $xCoordinate;
	my $yCoordinate;
	my $value;
	my $mfgDate;
	my $metrologyTool;
	my $specLsl;
	my $specUsl;

	my @waferKeyArr;
	my @waferScribeIdArr;
	my @globalWaferIdArr;
	my @partNumberArr;
	my @bouleIdArr;
	my @waferSlicePositionArr;
	my @slotArr;
	my @vendorSiteArr;
	my @shipToLocCdArr;
	my @vendorLotIdArr;
	my @waferParamNameArr;
	my @unitOfMeasureArr;
	my @xCoordinateArr;
	my @yCoordinateArr;
	my @valueArr;
	my @mfgDateArr;
	my @metrologyToolArr;
	my @specLslArr;
	my @specUslArr;

	open(COORDINATES, "<$infile") or dpExit(1,"Couldn't open $infile");
	while(my $line = <COORDINATES>) {
		chomp $line;
		next if $line =~ /^\s+$/;
		$lnCnt++;

		my @arr = split /\,/, $line;

		#print $line ,"\n";

		if ($lnCnt == 1) {
			# Get column fields
			for (my $i=0; $i<=$#arr; $i++) {
				my $field = trim($arr[$i]);
				$fieldHash{$field} = $i;
			}

			foreach my $field ('WAFER_KEY','VENDOR_SITE','SHIP_TO_LOC_CD','VENDOR_LOT_ID','WAFER_SCRIBE_ID','GLOBAL_WAFER_ID','BOULE_ID','WAFER_SLICE_POSITION','SLOT','PART_NUMBER','WAFER_PARAM_NAME','UNIT_OF_MEASURE','X_COORDINATE','Y_COORDINATE','VALUE','SPEC_LSL','SPEC_USL','MFG_DATE') {
				# Check if required eolumn fields exists
				if ( exists $fieldHash{$field} ) {
					INFO ("$fieldHash{$field} : $field field exists");
				}
				else {
					dpExit(1,"$field field not found.");
				}

			}

		}
		elsif ($lnCnt > 1 ) {
			
			#initialize
			my %valueHash;

			if ( exists $fieldHash{WAFER_KEY} ) {
				my $arrValue = trim($arr[$fieldHash{WAFER_KEY}]);
				$waferKey = repNA($arrValue);
				$duplicates{$waferKey}++;
			}

			# WAFER_SCRIBE_ID
			if ( exists $fieldHash{WAFER_SCRIBE_ID} ) {
				my $arrValue = trim($arr[$fieldHash{WAFER_SCRIBE_ID}]);
				$waferScribeId = repNA($arrValue);
			} 

			# GLOBAL_WAFER_ID
			if ( exists $fieldHash{GLOBAL_WAFER_ID} ) {
				my $arrValue = trim($arr[$fieldHash{GLOBAL_WAFER_ID}]);
				$globalWaferId = repNA($arrValue);
			}

			# PART_NUMBER
			if ( exists $fieldHash{PART_NUMBER} ) {
				my $arrValue = trim($arr[$fieldHash{PART_NUMBER}]);
				$partNumber = repNA($arrValue);
			}

			# BOULE_ID
			if ( exists $fieldHash{BOULE_ID} ) {
				my $arrValue = trim($arr[$fieldHash{BOULE_ID}]);
				$bouleId = repNA($arrValue);
			}

			# WAFER_SLICE_POSITION
			if ( exists $fieldHash{WAFER_SLICE_POSITION} ) {
				my $arrValue = trim($arr[$fieldHash{WAFER_SLICE_POSITION}]);
				$waferSlicePosition = repNA($arrValue);
			}

			# SLOT
			if ( exists $fieldHash{SLOT} ) {
				my $arrValue =  trim($arr[$fieldHash{SLOT}]);
				$slot = repNA($arrValue);
			}

			# VENDOR_SITE
			if ( exists $fieldHash{VENDOR_SITE} ) {
				my $arrValue = trim($arr[$fieldHash{VENDOR_SITE}]);
				$vendorSite = repNA($arrValue);
			}

			# SHIP_TO_LOC_CD
			if ( exists $fieldHash{SHIP_TO_LOC_CD} ) {
				my $arrValue = trim($arr[$fieldHash{SHIP_TO_LOC_CD}]);
				$shipToLocCd = repNA($arrValue);
			}

			# VENDOR_LOT_ID
			if ( exists $fieldHash{VENDOR_LOT_ID} ) {
				my $arrValue = trim($arr[$fieldHash{VENDOR_LOT_ID}]);
				$vendorLotId = repNA($arrValue);
			}

			# WAFER_PARAM_NAME
			if ( exists $fieldHash{WAFER_PARAM_NAME} ) {
				my $arrValue = trim($arr[$fieldHash{WAFER_PARAM_NAME}]);
				$waferParamName = repNA($arrValue);
			}

			# METROLOGY_TOOL
			#if ( exists $fieldHash{METROLOGY_TOOL} ) {
			#	my $arrValue = trim($arr[$fieldHash{METROLOGY_TOOL}]);
			#	$metrologyTool = repNA($arrValue);	
			#}

			# UNIT_OF_MEASURE
			if ( exists $fieldHash{UNIT_OF_MEASURE} ) {
				my $arrValue = trim($arr[$fieldHash{UNIT_OF_MEASURE}]);
				$unitOfMeasure = repNA($arrValue);
			}

			# X_COORDINATE
			if ( exists $fieldHash{X_COORDINATE} ) {
				my $arrValue = trim($arr[$fieldHash{X_COORDINATE}]);
				$xCoordinate = repNA($arrValue);
			}

			# Y_COORDINATE
			if ( exists $fieldHash{Y_COORDINATE} ) {
				my $arrValue = trim($arr[$fieldHash{Y_COORDINATE}]);
				$yCoordinate = repNA($arrValue);
			}

			# VALUE
			if ( exists $fieldHash{VALUE} ) {
				my $arrValue = trim($arr[$fieldHash{VALUE}]);
				$value = repNA($arrValue);
			}

			if ( exists $fieldHash{SPEC_LSL} ) {
				my $arrValue = trim($arr[$fieldHash{SPEC_LSL}]);
				$specLsl = repNA($arrValue);
			}

			if ( exists $fieldHash{SPEC_USL} ) {
				my $arrValue = trim($arr[$fieldHash{SPEC_USL}]);
				$specUsl = repNA($arrValue);
			}

			# MFG_DATE
			if ( exists $fieldHash{MFG_DATE} ) {
				my $arrValue = trim($arr[$fieldHash{MFG_DATE}]);
				$mfgDate = repNA($arrValue);
			}

			#print "$waferScribeId,$globalWaferId,$partNumber,$bouleId,$waferSlicePosition,$slot,$vendorSite,$shipToLocCd,$vendorLotId,$waferParamName,$unitOfMeasure,$xCoordinate,$yCoordinate,$value,$mfgDate\n";

			$valueHash{$waferParamName} = $value;

			push @{$waferParamNameArr[$waferKey]}, $waferParamName;
			push @{$unitOfMeasureArr[$waferKey]}, $unitOfMeasure;
			push @{$xCoordinateArr[$waferKey]}, $xCoordinate;
			push @{$yCoordinateArr[$waferKey]}, $yCoordinate;
			push @{$valueArr[$waferKey]}, \%valueHash;
			#push @{$metrologyToolArr[$waferKey]}, $metrologyTool;
			push @{$specLslArr[$waferKey]}, $specLsl;
			push @{$specUslArr[$waferKey]}, $specUsl;

			#$hash{$globalWaferId} = {
			$hash{$partNumber}{$globalWaferId} = {
				WAFER_SCRIBE_ID => $waferScribeId,
				GLOBAL_WAFER_ID => $globalWaferId,
				PART_NUMBER => $partNumber,
				BOULE_ID => $bouleId,
				WAFER_SLICE_POSITION => $waferSlicePosition,
				SLOT => $slot,
				VENDOR_SITE => $vendorSite,
				SHIP_TO_LOC_CD => $shipToLocCd,
				VENDOR_LOT_ID => $vendorLotId,
				WAFER_PARAM_NAME => @{waferParamNameArr[$waferKey]},
				UNIT_OF_MEASURE => @{unitOfMeasureArr[$waferKey]},
				X_COORDINATE => @{xCoordinateArr[$waferKey]},
				Y_COORDINATE => @{yCoordinateArr[$waferKey]},
				VALUE => @{valueArr[$waferKey]},
				MFG_DATE => $mfgDate,
				#METROLOGY_TOOL => @{metrologyToolArr[$waferKey]},
				SPEC_LSL => @{specLslArr[$waferKey]},
				SPEC_USL => @{specUslArr[$waferKey]}
			};


		}
	}
	close COORDINATES;

	return \%hash;
}

sub readPuck {
	
	my $self = shift;
	my $infile = shift;

	my %hash;
	my %fieldHash;
	my %duplicates;
	my $field;
	my $lnCnt = 0;
	my $lotCnt = 0;
	my $wfrCnt = 0;
	my $parCnt = 0;

	my $RawsiliconLotId;
	my $VendorSite;
	my $OnSite;
	my $PartNumber;
	my $ShipNumber;
	my $Recipe;
	my $Qty;
	my $ShipToLocCd;
	my $ShippingFromLocCd;
	my $VendorLotId;
	my $OnParamName;
	my $VendorMeasurementName;
	my $ParamMapId;
	my $Value;
	my $UnitOfMeasure;
	my $SpecNumber;
	my $Revision;
	my $Grade;
	my $MfgDate;
	my $SurfaceConditions;
	my $Description;

	my @RawsiliconLotIdArr;
	my @VendorSiteArr;
	my @OnSiteArr;
	my @PartNumberArr;
	my @ShipNumberArr;
	my @RecipeArr;
	my @QtyArr;
	my @ShipToLocCdArr;
	my @ShippingFromLocCdArr;
	my @VendorLotIdArr;
	my @OnParamNameArr;
	my @VendorMeasurementNameArr;
	my @ParamMapIdArr;
	my @ValueArr;
	my @UnitOfMeasureArr;
	my @SpecNumberArr;
	my @RevisionArr;
	my @GradeArr;
	my @MfgDateArr;	
	my @SurfaceConditionsArr;
	my @DescriptionArr;

	open(PUCK, "<$infile") or dpExit(1,"Couldn't open $infile");
	while(my $line = <PUCK>) {
		chomp $line;
		$line =~ s/\"\,\"/\"\|\"/g;
		next if $line =~ /^\s+$/;
		$lnCnt++;

		#my @arr = split /\,/, $line;
		my @arr = split /\|/, $line;

		#print $line ,"\n";

		if ($lnCnt == 1) {
			# Get column fields
			for (my $i=0; $i<=$#arr; $i++) {
				my $field = trim($arr[$i]);
				$fieldHash{$field} = $i;
			}

			foreach my $field ('RAWSILICON_LOT_ID','VENDOR_SITE','ON_SITE','PART_NUMBER','SHIP_NUMBER','RECIPE','QTY','SHIP_TO_LOC_CD','SHIPPING_FROM_LOC_CD','VENDOR_LOT_ID','ON_PARAM_NAME','VENDOR_MEASUREMENT_NAME','PARAM_MAP_ID','VALUE','UNIT_OF_MEASURE','SPEC_NUMBER','REVISION','GRADE','SURFACE_CONDITIONS','DESCRIPTION'){
				# Check if required eolumn fields exists
				if ( exists $fieldHash{$field} ) {
					INFO ("$fieldHash{$field} : $field field exists");
				}
				else {
					dpExit(1,"$field field not found.");
				}
			}
		}
		elsif ($lnCnt > 1 ) {

			if ( exists $fieldHash{RAWSILICON_LOT_ID} ) {
				my $arrValue = trim($arr[$fieldHash{RAWSILICON_LOT_ID}]);
				$RawsiliconLotId = repNA($arrValue);
			}

			if ( exists $fieldHash{VENDOR_SITE} ) {
				my $arrValue = trim($arr[$fieldHash{VENDOR_SITE}]);
				$VendorSite = repNA($arrValue);
			}

			if ( exists $fieldHash{ON_SITE} ) {
				my $arrValue = trim($arr[$fieldHash{ON_SITE}]);
				$OnSite = repNA($arrValue);
			}

			if ( exists $fieldHash{PART_NUMBER} ) {
				my $arrValue = trim($arr[$fieldHash{PART_NUMBER}]);
				$PartNumber = repNA($arrValue);
			}

			if ( exists $fieldHash{SHIP_NUMBER} ) {
				my $arrValue = trim($arr[$fieldHash{SHIP_NUMBER}]);
				$ShipNumber = repNA($arrValue);
			}

			if ( exists $fieldHash{RECIPE} ) {
				my $arrValue = trim($arr[$fieldHash{RECIPE}]);
				$Recipe = repNA($arrValue);
			}

			if ( exists $fieldHash{QTY} ) {
				my $arrValue = trim($arr[$fieldHash{QTY}]);
				$Qty = repNA($arrValue);
			}

			if ( exists $fieldHash{SHIP_TO_LOC_CD} ) {
				my $arrValue = trim($arr[$fieldHash{SHIP_TO_LOC_CD}]);
				$ShipToLocCd = repNA($arrValue);
			}

			if ( exists $fieldHash{SHIPPING_FROM_LOC_CD} ) {
				my $arrValue = trim($arr[$fieldHash{SHIPPING_FROM_LOC_CD}]);
				$ShippingFromLocCd = repNA($arrValue);
			}

			if ( exists $fieldHash{VENDOR_LOT_ID} ) {
				my $arrValue = trim($arr[$fieldHash{VENDOR_LOT_ID}]);
				$VendorLotId = repNA($arrValue);
			}

			if ( exists $fieldHash{ON_PARAM_NAME} ) {
				my $arrValue = trim($arr[$fieldHash{ON_PARAM_NAME}]);
				$OnParamName = repNA($arrValue);
			}

			if ( exists $fieldHash{VENDOR_MEASUREMENT_NAME} ) {
				my $arrValue = trim($arr[$fieldHash{VENDOR_MEASUREMENT_NAME}]);
				$VendorMeasurementName = repNA($arrValue);
			}

			if ( exists $fieldHash{PARAM_MAP_ID} ) {
				my $arrValue = trim($arr[$fieldHash{PARAM_MAP_ID}]);
				$ParamMapId = repNA($arrValue);
			}

			if ( exists $fieldHash{VALUE} ) {
				my $arrValue = trim($arr[$fieldHash{VALUE}]);
				$Value = repNA($arrValue);
			}

			if ( exists $fieldHash{UNIT_OF_MEASURE} ) {
				my $arrValue = trim($arr[$fieldHash{UNIT_OF_MEASURE}]);
				$UnitOfMeasure = repNA($arrValue);
			}
			
			if ( exists $fieldHash{SPEC_NUMBER} ) {
				my $arrValue = trim($arr[$fieldHash{SPEC_NUMBER}]);
				$SpecNumber = repNA($arrValue);
			}

			if ( exists $fieldHash{REVISION} ) {
				my $arrValue = trim($arr[$fieldHash{REVISION}]);
				$Revision = repNA($arrValue);
			}

			if ( exists $fieldHash{GRADE} ) {
				my $arrValue = trim($arr[$fieldHash{GRADE}]);
				$Grade = repNA($arrValue);
			}

			if ( exists $fieldHash{MFG_DATE} ) {
				my $arrValue = trim($arr[$fieldHash{MFG_DATE}]);
				$MfgDate = repNA($arrValue);
			}

			if ( exists $fieldHash{SURFACE_CONDITIONS} ) {
				my $arrValue = trim($arr[$fieldHash{SURFACE_CONDITIONS}]);
				$SurfaceConditions = repNA($arrValue);
			}

			if ( exists $fieldHash{DESCRIPTION} ) {
				my $arrValue = trim($arr[$fieldHash{DESCRIPTION}]);
				$Description = repNA($arrValue);
			}

			#print "$RawsiliconLotId, $VendorSite, $OnSite, $PartNumber, $ShipNumber, $Recipe, $Qty, $ShipToLocCd, $ShippingFromLocCd, $VendorLotId, $OnParamName, $VendorMeasurementName, $ParamMapId, $Value, $UnitOfMeasure, $SpecNumber, $Revision, $Grade, $MfgDate\n" if $VendorLotId eq "GT0180070B";		
			$hash{$VendorLotId}{$OnParamName}{$VendorMeasurementName} = {
				RAWSILICON_LOT_ID => $RawsiliconLotId,
                                VENDOR_SITE => $VendorSite,
                                ON_SITE => $OnSite,
                                PART_NUMBER => $PartNumber,
                                SHIP_NUMBER => $ShipNumber,
                                RECIPE => $Recipe,
                                QTY => $Qty,
                                SHIP_TO_LOC_CD => $ShipToLocCd,
                                SHIPPING_FROM_LOC_CD => $ShippingFromLocCd,
				VENDOR_LOT_ID => $VendorLotId,
				SPEC_NUMBER => $SpecNumber,
                                REVISION => $Revision,
                                GRADE => $Grade,
                                MFG_DATE => $MfgDate,
				ON_PARAM_NAME => $OnParamName,
				VENDOR_MEASUREMENT_NAME => $VendorMeasurementName,
				PARAM_MAP_ID => $ParamMapId,
				VALUE => $Value,
				UNIT_OF_MEASURE => $UnitOfMeasure,
				SURFACE_CONDITIONS => $SurfaceConditions,
				DESCRIPTION => $Description
			};

		}
	}
	close PUCK;

	return \%hash;
}

sub readBackend {
	
	my $self = shift;
	my $infile = shift;
	
	my %hash;
	my %fieldHash;
	my %duplicates;
	my $field;
	my $lnCnt = 0;
	my $lotCnt = 0;
	my $wfrCnt = 0;
	my $parCnt = 0;

	my $VendorSite;
	my $PartNumber;
	my $ShipNumber;
	my $Qty;
	my $ShipToLoc;
	my $ShippingFromLoc;
	my $VendorLotId;
	my $MetrologyTool;
	my $SpecNumber;
	my $Revision;
	my $MfgDate;
	my $VendorPartNumber;
	my $MotherLotNumber;
	my $ExpirationDate;
	my $Parameter;
	my $NewParameter;
	my $UnitOfMeasure;
	my $VendorMeasurementName;
	my $ParamMapId;
	my $Value;
	my $Cpk;
	my $Result;

	my @VendorSiteArr;
	my @PartNumberArr;
	my @ShipNumberArr;
	my @QtyArr;
	my @ShipToLocArr;
	my @ShippingFromLocArr;
	my @VendorLotIdArr;
	my @MetrologyToolArr;
	my @SpecNumberArr;
	my @RevisionArr;
	my @MfgDateArr;
	my @VendorPartNumberArr;
	my @MotherLotNumberArr;
	my @ExpirationDateArr;
	my @ParameterArr;
	my @UnitOfMeasureArr;
	my @VendorMeasurementNameArr;
	my @ParamMapIdArr;
	my @ValueArr;
	my @CpkArr;
	my @ResultArr;

	open(BACKEND, "<$infile") or dpExit(1,"Couldn't open $infile");
	while(my $line = <BACKEND>) {
		chomp $line;
		#$line =~ s/\"\,\"/\"\|\"/g;
		next if $line =~ /^\s+$/;
		next if $line eq "";
		$lnCnt++;

		my @arr = split /\,/, $line;
		#my @arr = split /\|/, $line;

		#print $line ,"\n";

		if ($lnCnt == 1) {

			for (my $i=0; $i<=$#arr; $i++) {
				my $field = trim($arr[$i]);
				$fieldHash{$field} = $i;
			}

			foreach my $field ('VENDOR_SITE','PART_NUMBER','SHIP_NUMBER','QTY','SHIP_TO_LOC_CD','SHIPPING_FROM_LOC_CD','VENDOR_LOT_ID','METROLOGY_TOOL','SPEC_NUMBER','REVISION','MFG_DATE','VENDOR_PART_NUMBER','MOTHER_LOT_NUMBER','EXPIRATION_DATE','PARAMETER','UNIT_OF_MEASURE','VENDOR_MEASUREMENT_NAME','PARAM_MAP_ID','VALUE','CPK','RESULT'){
				# Check if required eolumn fields exists
				if ( exists $fieldHash{$field} ) {
					INFO ("$fieldHash{$field} : $field field exists");
				}
				else {
					dpExit(1,"$field field not found.");
				}
			}
		}
		elsif ($lnCnt > 1 ) {

			if ( exists $fieldHash{VENDOR_SITE} ) {	
				my $arrValue = trim($arr[$fieldHash{VENDOR_SITE}]);	
				$VendorSite = repNA($arrValue);
			}

			if ( exists $fieldHash{PART_NUMBER} ) {	
				my $arrValue = trim($arr[$fieldHash{PART_NUMBER}]);	
				$PartNumber = repNA($arrValue);
			}

			if ( exists $fieldHash{SHIP_NUMBER} ) {	
				my $arrValue = trim($arr[$fieldHash{SHIP_NUMBER}]);	
				$ShipNumber = repNA($arrValue);
			}

			if ( exists $fieldHash{QTY} ) {
				my $arrValue = trim($arr[$fieldHash{QTY}]);
				$Qty = repNA($arrValue);
			}

			if ( exists $fieldHash{SHIP_TO_LOC_CD} ) {	
				my $arrValue = trim($arr[$fieldHash{SHIP_TO_LOC_CD}]);	
				$ShipToLoc = repNA($arrValue);
			}

			if ( exists $fieldHash{SHIPPING_FROM_LOC_CD} ) {	
				my $arrValue = trim($arr[$fieldHash{SHIPPING_FROM_LOC_CD}]);	
				$ShippingFromLoc = repNA($arrValue);
			}

			if ( exists $fieldHash{VENDOR_LOT_ID} ) {	
				my $arrValue = trim($arr[$fieldHash{VENDOR_LOT_ID}]);	
				$VendorLotId = repNA($arrValue);
			}

			if ( exists $fieldHash{METROLOGY_TOOL} ) {	
				my $arrValue = trim($arr[$fieldHash{METROLOGY_TOOL}]);	
				$MetrologyTool = repNA($arrValue);
			}

			if ( exists $fieldHash{SPEC_NUMBER} ) {	
				my $arrValue = trim($arr[$fieldHash{SPEC_NUMBER}]);	
				$SpecNumber = repNA($arrValue);
			}

			if ( exists $fieldHash{REVISION} ) {	
				my $arrValue = trim($arr[$fieldHash{REVISION}]);	
				$Revision = repNA($arrValue);
			}

			if ( exists $fieldHash{MFG_DATE} ) {	
				my $arrValue = trim($arr[$fieldHash{MFG_DATE}]);	
				$MfgDate = repNA($arrValue);
			}

			if ( exists $fieldHash{VENDOR_PART_NUMBER} ) {
				my $arrValue = trim($arr[$fieldHash{VENDOR_PART_NUMBER}]);
				$VendorPartNumber = repNA($arrValue);
			}

			if ( exists $fieldHash{MOTHER_LOT_NUMBER} ) {	
				my $arrValue = trim($arr[$fieldHash{MOTHER_LOT_NUMBER}]);	
				$MotherLotNumber = repNA($arrValue);
			}

			if ( exists $fieldHash{EXPIRATION_DATE} ) {	
				my $arrValue = trim($arr[$fieldHash{EXPIRATION_DATE}]);	
				$ExpirationDate = repNA($arrValue);
			}

			if ( exists $fieldHash{PARAMETER} ) {	
				my $arrValue = trim($arr[$fieldHash{PARAMETER}]);	
				$Parameter = repNA($arrValue);
			}

			if ( exists $fieldHash{UNIT_OF_MEASURE} ) {
				my $arrValue = trim($arr[$fieldHash{UNIT_OF_MEASURE}]);
				$UnitOfMeasure = repNA($arrValue);
			}

			if ( exists $fieldHash{VENDOR_MEASUREMENT_NAME} ) {
				my $arrValue = trim($arr[$fieldHash{VENDOR_MEASUREMENT_NAME}]);
				$VendorMeasurementName = repNA($arrValue);
			}

			if ( exists $fieldHash{PARAM_MAP_ID} ) {
				my $arrValue = trim($arr[$fieldHash{PARAM_MAP_ID}]);
				$ParamMapId = repNA($arrValue);
			}

			if ( exists $fieldHash{VALUE} ) {
				my $arrValue = trim($arr[$fieldHash{VALUE}]);
				$Value = repNA($arrValue);
			}

			if ( exists $fieldHash{CPK} ) {
				my $arrValue = trim($arr[$fieldHash{CPK}]);
				#$VendorMeasurementName = "CPK";
				$Cpk = repNA($arrValue);
			}
			
			if ( exists $fieldHash{RESULT} ) {	
				my $arrValue = trim($arr[$fieldHash{RESULT}]);	
				#$VendorMeasurementName = "RESULT";
				$Result = repNA($arrValue);
			}

			if ($MetrologyTool ne "NA") {
				$Parameter = "${Parameter}_${MetrologyTool}";		
			}

			#print "$VendorSite, $PartNumber, $PartDescription, $ShipNumber, $Quantity, $ShipToLoc, $ShippingFromLoc, $VendorLotId, $MetrologyTool, $SpecNumber, $Revision, $MfgDate, $RawMaterialName, $MotherLotNumber, $ExpirationDate, $Parameter, $Unit, $Category, $Value, $CpkPpk, $Result\n";
			#$hash{$ShipNumber}{$Parameter}{$VendorMeasurementName} = {
			$hash{$VendorLotId}{$ShipNumber}{$Parameter}{$VendorMeasurementName} = {
				VENDOR_SITE => $VendorSite,
				PART_NUMBER => $PartNumber,
				QTY => $Qty,
				SHIP_TO_LOC_CD => $ShipToLoc,
				SHIPPING_FROM_LOC_CD => $ShippingFromLoc,
				VENDOR_LOT_ID => $VendorLotId,
				METROLOGY_TOOL => $MetrologyTool,
				SPEC_NUMBER => $SpecNumber,
				REVISION => $Revision,
				MFG_DATE => $MfgDate,
				VENDOR_PART_NUMBER => $VendorPartNumber,
				MOTHER_LOT_NUMBER => $MotherLotNumber,
				EXPIRATION_DATE => $ExpirationDate,
				PARAMETER => $Parameter,
				UNIT_OF_MEASURE => $UnitOfMeasure,
				PARAM_MAP_ID => $ParamMapId,
				VALUE => $Value,
				#CPK => $Cpk,
				#RESULT => $Result,
				SHIP_NUMBER => $ShipNumber
			};

			$hash{$VendorLotId}{$ShipNumber}{$Parameter}{RESULT} = {
				RESULT => $Result
			};

			$hash{$VendorLotId}{$ShipNumber}{$Parameter}{CPK} = {
				CPK => $Cpk
			};

		}
	}
	close BACKEND;

	return \%hash;
}

sub readRaw {
	my $self = shift;
	my $infile = shift;
	
	my %hash;	
	my %fieldHash;
	my $lnCnt = 0;
	
	my $VendorSite;
	my $ShipNumber;
	my $PartNumber;
	my $VendorLotId;
	my $Quantity;
	my $ShipToLocCd;
	my $ShippingFromLocCd;
	my $SubstrateLotId;
	my $SubstrateSiteId;
	my $Parameter;
	my $Average;
	my $Stdev;
	my $Minimum;
	my $Maximum;
	my $SampleSize;
	my $SpecLsl;
	my $SpecUsl;
	my $Unit;

	my @VendorSiteArr;
	my @ShipNumberArr;
	my @PartNumberArr;
	my @VendorLotIdArr;
	my @QuantityArr;
	my @ShipToLocCdArr;
	my @ShippingFromLocCdArr;
	my @SubstrateLotIdArr;
	my @SubstrateSiteIdArr;
	my @ParameterArr;
	my @AverageArr;
	my @StdevArr;
	my @MinimumArr;
	my @MaximumArr;
	my @SampleSizeArr;
	my @SpecLslArr;
	my @SpecUslArr;
	my @UnitArr;

	open(RAW, "<$infile") or dpExit(1,"Couldn't open $infile");
	while(my $line = <RAW>) {
		chomp $line;
		next if $line =~ /^\s+$/;
		next if $line eq "";
		$lnCnt++;
		
		#print "$line\n";
		
		my @arr = split /\,/, $line;
		
		if ($lnCnt == 1) {

			for (my $i=0; $i<=$#arr; $i++) {
				my $field = trim($arr[$i]);
				$fieldHash{$field} = $i;
			}

			foreach my $field ('VENDOR_SITE','SHIP_NUMBER','PART_NUMBER','VENDOR_LOT_ID','QUANTITY','SHIP_TO_LOC_CD','SHIPPING_FROM_LOC_CD','SUBSTRATE_LOT_ID','SUBSTRATE_SITE_ID','PARAMETER','AVERAGE','STDEV','MINIMUM','MAXIMUM','SAMPLE_SIZE','SPEC_LSL','SPEC_USL','UNIT'){
				# Check if required eolumn fields exists
				if ( exists $fieldHash{$field} ) {
					INFO ("$fieldHash{$field} : $field field exists");
				}
				else {
					dpExit(1,"$field field not found.");
				}
			}
		}
		elsif ($lnCnt > 1 ) {
			if ( exists $fieldHash{VENDOR_SITE} ) {
				my $arrValue = trim($arr[$fieldHash{VENDOR_SITE}]);	
				$VendorSite = repNA($arrValue);
			}
			if ( exists $fieldHash{SHIP_NUMBER} ) {
				my $arrValue = trim($arr[$fieldHash{SHIP_NUMBER}]);	
				$ShipNumber = repNA($arrValue);
			}
			if ( exists $fieldHash{PART_NUMBER} ) {
				my $arrValue = trim($arr[$fieldHash{PART_NUMBER}]);	
				$PartNumber = repNA($arrValue);
			}
			if ( exists $fieldHash{VENDOR_LOT_ID} ) {
				my $arrValue = trim($arr[$fieldHash{VENDOR_LOT_ID}]);	
				$VendorLotId = repNA($arrValue);
			}
			if ( exists $fieldHash{QUANTITY} ) {
				my $arrValue = trim($arr[$fieldHash{QUANTITY}]);	
				$Quantity = repNA($arrValue);
			}
			if ( exists $fieldHash{SHIP_TO_LOC_CD} ) {
				my $arrValue = trim($arr[$fieldHash{SHIP_TO_LOC_CD}]);	
				$ShipToLocCd = repNA($arrValue);
			}
			if ( exists $fieldHash{SHIPPING_FROM_LOC_CD} ) {
				my $arrValue = trim($arr[$fieldHash{SHIPPING_FROM_LOC_CD}]);	
				$ShippingFromLocCd = repNA($arrValue);
			}
			if ( exists $fieldHash{SUBSTRATE_LOT_ID} ) {
				my $arrValue = trim($arr[$fieldHash{SUBSTRATE_LOT_ID}]);	
				$SubstrateLotId = repNA($arrValue);
			}
			if ( exists $fieldHash{SUBSTRATE_SITE_ID} ) {
				my $arrValue = trim($arr[$fieldHash{SUBSTRATE_SITE_ID}]);	
				$SubstrateSiteId = repNA($arrValue);
			}
			if ( exists $fieldHash{PARAMETER} ) {
				my $arrValue = trim($arr[$fieldHash{PARAMETER}]);	
				$Parameter = repNA($arrValue);
			}
			if ( exists $fieldHash{AVERAGE} ) {
				my $arrValue = trim($arr[$fieldHash{AVERAGE}]);	
				$Average = repNA($arrValue);
			}
			if ( exists $fieldHash{STDEV} ) {
				my $arrValue = trim($arr[$fieldHash{STDEV}]);	
				$Stdev = repNA($arrValue);
			}
			if ( exists $fieldHash{MINIMUM} ) {
				my $arrValue = trim($arr[$fieldHash{MINIMUM}]);	
				$Minimum = repNA($arrValue);
			}
			if ( exists $fieldHash{MAXIMUM} ) {
				my $arrValue = trim($arr[$fieldHash{MAXIMUM}]);	
				$Maximum = repNA($arrValue);
			}
			if ( exists $fieldHash{SAMPLE_SIZE} ) {
				my $arrValue = trim($arr[$fieldHash{SAMPLE_SIZE}]);	
				$SampleSize = repNA($arrValue);
			}
			if ( exists $fieldHash{SPEC_LSL} ) {
				my $arrValue = trim($arr[$fieldHash{SPEC_LSL}]);	
				$SpecLsl = repNA($arrValue);
			}
			if ( exists $fieldHash{SPEC_USL} ) {
				my $arrValue = trim($arr[$fieldHash{SPEC_USL}]);	
				$SpecUsl = repNA($arrValue);
			}
			if ( exists $fieldHash{UNIT} ) {
				my $arrValue = trim($arr[$fieldHash{UNIT}]);	
				$Unit = repNA($arrValue);
			}
			
			$hash{$VendorLotId}{$ShipNumber}{$Parameter} = {
				VENDOR_SITE => $VendorSite,
				SHIP_NUMBER => $ShipNumber,
				PART_NUMBER => $PartNumber,
				VENDOR_LOT_ID => $VendorLotId,
				QUANTITY => $Quantity,
				SHIP_TO_LOC_CD => $ShipToLocCd,
				SHIPPING_FROM_LOC_CD => $ShippingFromLocCd,
				SUBSTRATE_LOT_ID => $SubstrateLotId,
				SUBSTRATE_SITE_ID => $SubstrateSiteId,
				PARAMETER => $Parameter,
				AVERAGE => $Average,
				STDEV => $Stdev,
				MINIMUM => $Minimum,
				MAXIMUM => $Maximum,
				SAMPLE_SIZE => $SampleSize,
				SPEC_LSL => $SpecLsl,
				SPEC_USL => $SpecUsl,
				UNIT => $Unit
			};
			
		}
	}	
	close RAW;
	
	return \%hash;
}

1;
