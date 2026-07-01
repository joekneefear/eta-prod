=pod

=head1 SYNOPSIS

	instantiate and use its method/subroutine and attributes.
	

=head1 DESCRIPTIONS
	
B<This script> Klarf/.001 parser module.

=head1 AUTHOR

B<junifferallan.garcia@fairchildsemi.com>

=head1 CHANGES
2016-Jul-28	jgarcia	: created
2016-Aug-12 jgarcia : adjusted lotid parsing inside the file, otherwise, if not get lotid inside, try to get from the filename.
2016-Aug-18 jgarcia : added support for defect with mulitple slots and wafers
2016-Sep-27 jgarcia : ensure x and y coordinate list will have single space as a separator.


=head1 LICENSE

(C) Fairchild 2016 All rights reserved.

=cut
package PDF::Parser::Klarf;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use v5.10;
#no warnings qw/experimental::smartmatch experimental::lexical_subs/;
use base qw/PDF::DpData::Base Class::Accessor/;
use POSIX;
our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}

__PACKAGE__->mk_accessors(array);


sub splitDie {
	
	my $self = shift;
	my $infile = shift;
	my $debug = shift;
	my $location = shift;
	#my $location = shift;
	my $header = new_headerLong;
#	my $defect = new_defect(
#							{ slots => [], 
#								wafers => [],
#								imageFiles => [],
#								defectIndexes => [],
#								imageIndexes => []
#							}
#	);
	my $defect = new_defect();
	my $model  = new_model(
        {   header => $header,
            defect => $defect,
            misc   => {},
            dataSource => 'Klarf'
        }
  );

  my $resultDateTime;
  my $resultDate;
  my $resultTime;
  my $slot;
  my $diex;
  my $diey;
  my $lotid;
  my $DB_dieWidth;
	my $DB_dieHieght;
	my %hMetaData;
	my $hMetaData;
	my $DB;
	my $username;
	my $password;
	my $refdb;
	my $level = -1; # Level of indentation
	my $family = "";
	my $skip_flag = 0;
	my $x_die_sep = 1;
	my $y_die_sep = 1;
	my $die_x;
	my $die_y;
	my $org_die_x;
	my $org_die_y;
	my @tmp_arr;
	my $notch = ""; # notch location

	my %SampleTestPlan = (); # SampleTestPlan count
	my %def_list = (); # DefectList coordinates hash
	my @def_data = (); # defect file data
	
	my $testplan_flg = 0;
	my $defect_flg = 0;
	my $summary_flg = 0;
	my $testplan_cnt = 0;
	my $summary_cnt = 0;
	my @inputFileLineData;
	my $defectScannerModelID;
	my $defectStepID;
	my $defectResultDate;
	my $defectResultTime;
	my $defectRestulTimestamp;
	my $defectSlot;
	my %hashMetaData;
	my $refdBDieX;
	my $refdBDieY;
	my $defectWaferID;
	my @waferArray = ();
	my @slotArray = ();
	my $imageFilename;
	my @imageArray = ();
	my $program = "";
	my @imageList = ();
	my $imageCount = 0;
	my @defectIndexList = ();
	my $defectRecordCount;
	my $defectRecFlag = 0;
	my @defectDataArray = ();
	my @tempDefectDataArray = ();
	my $defRecSpec = 0;
	my $testerType = "";
	my $imageIndexFlag = 0;
	my $imageFilename = "";
	
	
	
	my $baseFilename = (basename $infile);
	$defect->inputFile($baseFilename);
	$defect->LOCATION($location);
  #$lotid = getLotFromFilename($baseFilename);
  #$testerType = &getTesterType();
  &getWaferAndSlotCount();
  
  sub getMeta {
		#my $self = shift;
		my $lotid = shift;
		$lotid = uc($lotid);
		if($lotid ne "" && $lotid !~ /^\d{1,}.+/i) {
	  	$defect->LOT($lotid);
	  } else {
	  	INFO("LOTID inside the defect file is not valid or correct. Try to get from the filename");
	  	$lotid = getLotFromFilename($defect->{inputFile});
	  	if($lotid ne ""){
	  		$defect->LOT($lotid);
	  	} else {
	  		dpExit(1,"Lotid indicated in the raw file is not valid and No LOTID can be extracted from the filename");
	  	}
	  }
	 	unless ( $defect->populateDefectMetaData() ){
	 		$model->forSBflag(1);
	 		$defect->DB_LOCATION("Sandbox");
		} else {
			$defect->DB_LOCATION("Production");
		}
		$header->LOT($defect->{LOT});
	  $header->PRODUCT($defect->{PRODUCT});
	  $header->FAB($defect->{FAB});	
	  $header->PROCESS($defect->{PROCESS});
	  $header->FAMILY($defect->{FAMILY});
	  
	  
	  $refdBDieX = $defect->{DIE_WIDTH};
		$refdBDieY = $defect->{DIE_HEIGHT};
		
		if($refdBDieX ne "" && $refdBDieY ne "") {
			INFO("DIE_WIDTH and DIE_HEIGHT from REFDB are NOT EMPTY");
		} else {
			WARN("DIE_WIDTH and DIE_HEIGHT from REFDB are EMPTY");
		}
  }
 
 sub getWaferAndSlotCount {
 	my $waferCounter = 0;
	my $slotCounter = 0;
	
 	my $fileHandle1 = IO::File->new($infile) or dpExitError("Failed to open Defect file $infile");
 	
 		while (my $line_ = $fileHandle1->getline) {
 			
# 			if($testerType =~ /COMPLUS/i){
# 				#INFO("COMPLUS");
# 				if(!($line_ =~ m/^\s/)) {
#	 				
#	 				if($line_ =~ m/^TiffFilename/i) {
#	 					$defectRecFlag = 0;
#		 				#$imageCount = $imageCount + 1;
#					  my @ids = split / /, $line_;
#					  my $lastIndex = $#ids;
#					  my $imageFile = uc($ids[$lastIndex]);
#					  $imageFile =~ s/[^[:print:]]+//g;
#					  $imageFile =~ tr/\"\;//d;
#					  trim($imageFile);
#					  $imageFilename = $imageFile;
#					  #$waferCounter++;
#					  #push (@imageArray, $imageFile);
#					  #$defect->add('images', $imageFile);
#					  INFO("IMAGE =>$imageFile");# if $debug
#		 			} elsif ($line_ =~ m/^WaferID/) {
#		 				$defectRecFlag = 0;
#					  my @ids = split / /, $line_;
#					  my $lastIndex = $#ids;
#					  $defectWaferID = $ids[$lastIndex];
#					  $defectWaferID =~ s/[^[:print:]]+//g;
#					  $defectWaferID =~ tr/\"\;\@//d;
#					  trim($defectWaferID);
#					  $waferCounter++;
#					  #push (@waferArray, $defectWaferID);
#					  $defect->add('wafers', $defectWaferID);
#					  #$defectScannerModelID =~ s/\"$//;
#					  INFO("WaferID =>$defectWaferID || $waferCounter");# if $debug;
#					  
#					}elsif ($line_ =~ m/^Slot/) {
#						$defectRecFlag = 0;
#						$slotCounter++;
#					  my @ids = split / /, $line_;
#					  my $lastIndex = $#ids;
#					  $defectSlot = $ids[$lastIndex];
#					  $defectSlot =~ s/[^[:print:]]+//g;
#					  $defectSlot =~ tr/\"\;//d;
#					  trim($defectSlot);
#					  $defect->add('slots', $defectSlot);
#					  #$defect->SLOT($defectSlot);
#					  #push (@slotArray, $defectSlot);
#					  #$defectScannerModelID =~ s/\"$//;
#					  INFO("Slot =>$defectSlot|| $slotCounter");# if $debug;
#					  
#					} elsif($line_ =~ /DefectRecordSpec/i) {
#						$defectRecFlag = 0;
#						my @ids = split / /, $line_;
#					  my $lastIndex = $#ids;
#					  $defRecSpec = $ids[1];
#					  INFO("RecordSpecColumnCount=>$defRecSpec");
#					}	elsif($line_ =~ m/DefectList/i) {
#		 				$defectRecFlag = 1;
#		 				
#		 			} 
#	 			} elsif($defectRecFlag == 1 && ($line_ =~ /^\s\d{1,}\s\d{1,}/ || $line_ =~ /\d{1,}\s\d{1,}/) ) {
#	 				  #my $imageList = "";
#	 				  $imageIndexFlag = 0;
#	 				  my $imgIndex;
#		 				#print "IM HERE\n";
#		 				$line_ =~ s/^ //;
#		 				print "$line_\n";
#						@tempDefectDataArray = split(/ /, $line_);
#						if($#tempDefectDataArray < 2) {
#							$imageIndexFlag = 1;
#							$imgIndex = $tempDefectDataArray[0];
#							INFO("IMGINDEX=>$imgIndex");
#							push @imageList, $imgIndex;
#							$defect->add('imageIndexes', $imgIndex);
#						}
#						#print "TEST PRINT=>@tempDefectDataArray";
#						my $lastIndex = $defRecSpec;
#						INFO("ImageIndex=>$tempDefectDataArray[$lastIndex]");
#						my $imageCount = $tempDefectDataArray[$defRecSpec - 1];
#						my $imageList = $tempDefectDataArray[$lastIndex];
#						my $defIndex = $tempDefectDataArray[0];
#						
#						#$imageCount = s/[^[:print:]]+//g;
#						#$imageCount = tr/\"\;//;
#						INFO("DefIndex=>$defIndex");
#						INFO("ImageIndex=>$imgIndex");
#						INFO("ImageIndex=>$imgIndex || DefetcIndex=>$defIndex");
#						if($imageCount > 0 && $imageList > 0) {
#							#$imageIndexFlag = 1;
#							#print "IM HERE inside if\n";
#							#INFO("DefIndex=>$defIndex");
#							push @defectIndexList, $defIndex;
#							$defect->add('defectIndexes', $defIndex);
#							$defect->add('images', $imageFilename);
#							#INFO("ImageIndex=>imgIndex");
#							#if(
#							#push @imageList, $imgIndex;
#							#$defect->add('imageIndexes', $imgIndex);
#						}
#						#$defectRecFlag = 0;
#				}
##		 		} elsif($imageIndexFlag == 1) {
##		 			INFO("IM HERE!!! in Image Index");
##		 			my @tempDefectDataArray = ();
##		 			@tempDefectDataArray = split(/ /, $line_);
##		 			my $imgIndex = $tempDefectDataArray[0]; 
##		 			INFO("ImageIndex=>$imgIndex");
##					push @imageList, $imgIndex;
##					$defect->add('imageIndexes', $imgIndex);
##					#$defect->add('images', $imageFilename);
##					$imageIndexFlag = 0;
##		 		}
#	 			
#		 	} else {
		 		
		 		if(!($line_ =~ m/^\s/)) {
	 				
	 				if($line_ =~ m/^TiffFilename/i) {
		 				$imageCount = $imageCount + 1;
					  my @ids = split / /, $line_;
					  my $lastIndex = $#ids;
					  #my $secondToTheLastIndex = $lastIndex - 1;
					  my $imageFile = $ids[$lastIndex];
					  #$imageFile =~ s/[^[:print:]]+//g;
					  #$imageFile =~ tr/\"\;//d;
					  $imageFile = trim($imageFile);
					  #$waferCounter++;
					  #push (@imageArray, $imageFile);
					  $defect->add('images', $imageFile);
					  INFO("IMAGE =>$imageFile || $imageCount") if $debug;
		 			} elsif ($line_ =~ m/^WaferID/) {
					  my @ids = split / /, $line_;
					  my $lastIndex = $#ids;
					  $defectWaferID = $ids[$lastIndex];
					  $defectWaferID =~ s/[^[:print:]]+//g;
					  $defectWaferID =~ tr/\"\;\@//d;
					  trim($defectWaferID);
					  $waferCounter++;
					  #push (@waferArray, $defectWaferID);
					  $defect->add('wafers', $defectWaferID);
					  #$defectScannerModelID =~ s/\"$//;
					  INFO("WaferID =>$defectWaferID || $waferCounter") if $debug;
					  
					}elsif ($line_ =~ m/^Slot/) {
						$slotCounter++;
					  my @ids = split / /, $line_;
					  my $lastIndex = $#ids;
					  $defectSlot = $ids[$lastIndex];
					  $defectSlot =~ s/[^[:print:]]+//g;
					  $defectSlot =~ tr/\"\;//d;
					  trim($defectSlot);
					  $defect->add('slots', $defectSlot);
					  #$defect->SLOT($defectSlot);
					  #push (@slotArray, $defectSlot);
					  #$defectScannerModelID =~ s/\"$//;
					  INFO("Slot =>$defectSlot|| $slotCounter") if $debug;
					  
					} elsif($line_ =~ /DefectRecordSpec/i) {
						my @ids = split / /, $line_;
					  my $lastIndex = $#ids;
					  $defRecSpec = $ids[1];
					  INFO("RecordSpec=>$defRecSpec") if $debug;
					}	elsif($line_ =~ m/DefectList/i) {
		 				$defectRecFlag = 1;
		 				
		 			} 
	 			} elsif($defectRecFlag == 1 && $line_ =~ /^\s+\d{1,}\s\d{1,}/) {
		 				#print "IM HERE\n";
		 				$line_ =~ s/^ //;
		 				#print "$line_\n";
						@tempDefectDataArray = split(/ /, $line_);
						#print "TEST PRINT=>@tempDefectDataArray";
						my $lastIndex = $defRecSpec - 1;
						INFO("ImageIndex=>$tempDefectDataArray[$lastIndex]")if $debug;
						my $imgIndex = $tempDefectDataArray[$lastIndex];
						my $defIndex = $tempDefectDataArray[0];
						#print ">>>>>>>>>>>>>$defIndex||$tempDefectDataArray[1]\n";
						INFO("DefIndex=>$defIndex") if $debug;
						INFO("ImageIndex=>$imgIndex") if $debug;
						#$imgIndex = s/[^[:print:]]+//g;
						#$imgIndex = tr/\"\;//;
						$imgIndex = trim($imgIndex);
						INFO("ImageIndexCleaned=>$imgIndex || DefetcIndex=>$defIndex") if $debug;
						if($imgIndex > 0) {
							#print "IM HERE inside if\n";
							INFO("DefIndex=>$defIndex") if $debug;
							push @defectIndexList, $defIndex;
							$defect->add('defectIndexes', $defIndex);
							INFO("ImageIndex=>imgIndex") if $debug;
							push @imageList, $imgIndex;
							$defect->add('imageIndexes', $imgIndex);
						}
						$defectRecFlag = 0;
		 		}
		 		
		 	#}
							
 		}
 		undef $fileHandle1;
 }
 
  sub getTesterType{
	 	my $testerType = 0;
		my $slotCounter = 0;
	 	my $fileHandle1 = IO::File->new($infile) or dpExitError("Failed to open Defect file $infile");
 	
 		while (my $line_ = $fileHandle1->getline) {
 			
 			if(!($line_ =~ m/^\s/)) {
 				
 				if($line_ =~ m/^InspectionStationID/) {
				
				  my @ids = split / /, $line_;
				  my $lastIndex = $#ids;
				  $testerType = $ids[$lastIndex];
				  $testerType =~ tr/\"\;//d;
				  #$testerType =~ s/[^[:print:]]+//g;
				  trim($testerType);
				  
				  #$defectScannerModelID =~ s/\"$//;
				  #print "Scanner Model ID =>" . $defectScannerModelID."\n" if $debug;
				  #print "defectScannerID-->$defectScannerModelID<--";
				  #$header->EQUIP1_ID($defectScannerModelID);
				  
				}
			}
 				
							
 		}
 		undef $fileHandle1;
 		return $testerType;
 }

	#open .001 defect file
	my $fileHandle = IO::File->new($infile) or dpExitError("Failed to open Defect file $infile");
	
	my $tmp;
	my $x_coord;
	my $y_coord;
	
	
	while (my $line_ = $fileHandle->getline) {
		
		if($line_ =~ m/<BOM>/){
			#close(FILE);
			dpExitError ("Input file already has MetaData section! existing...");
		}
		
		if($line_ =~ m/^LotID/) {
			my @ids;
			my $splitterFlag = "off";
			$lotid = ($line_ =~ /^LotID "([\w\W]+)"/ig)[0];
			$lotid = uc($lotid);
			if($lotid =~ /\_/) {
				$splitterFlag = "on";
				@ids = split /\_/, $lotid;
			} elsif ($lotid =~ /\-/) {
				$splitterFlag = "on";
				@ids = split /\-/, $lotid;
			}else {
				if($defect->{LOCATION} eq "BK") {
					$lotid = substr($lotid, -8);
				}
			}
			
			my $lastIndex = $#ids;
			$lotid = $ids[$lastIndex] if $splitterFlag eq "on";
			#Read_Meta();
			&getMeta($lotid);
			#$myMetaData = Print_Meta();
			#printf STDERR "DB DiePitch $die_x_db $die_y_db\n" if $debug;
			INFO("Lotid inside the file: $lotid") if $debug;
		}
		
		
		
		if(!($line_ =~ m/^ +/)) {
			if($testplan_flg) {
				$tmp = scalar(@def_data)-1;
				chomp $def_data[$tmp];
				$def_data[$tmp] .= "\;\n";
			}
			$testplan_flg = 0;
			$defect_flg = 0;
			$summary_flg = 0;
			
			 if($line_ =~ m/^InspectionStationID/) {
				
				  my @ids = split / /, $line_;
				  my $lastIndex = $#ids;
				  $defectScannerModelID = $ids[$lastIndex];
				  $defectScannerModelID =~ tr/\"\;//d;
				  $defectScannerModelID =~ s/[^[:print:]]+//g;
				  trim($defectScannerModelID);
				  
				  #$defectScannerModelID =~ s/\"$//;
				  #print "Scanner Model ID =>" . $defectScannerModelID."\n" if $debug;
				  #print "defectScannerID-->$defectScannerModelID<--";
				  $header->EQUIP1_ID($defectScannerModelID);
				  
			} elsif ($line_ =~ m/^ResultTimestamp/) {
				  my @ids = split / /, $line_;
				  my $lastIndex = $#ids;
				  $defectResultDate = $ids[1];
				  #$defectResultDate =~ s/[^[:print:]]+//g;
					$defectResultDate =~ s/[^0-9a-zA-Z\s:-]//g;
					my($m,$d,$y) = split /\-/, $defectResultDate;
					$y = (
            $y < 100
            ? ( $y < 70 ? 2000 + $y : 1900 + $y )
            : $y
         );
          $defectResultDate = $y."/".$m."/".$d;
				  $defectResultTime = $ids[$lastIndex];
				  $defectResultTime =~ s/[^[:print:]]+//g;
					$defectResultTime =~ s/[^0-9a-zA-Z\s:-]//g;
				  $defectRestulTimestamp = $defectResultDate . " " . $defectResultTime;
				  $defectRestulTimestamp = formatDateToYYYYMMDD($defectRestulTimestamp);
				  trim($defectRestulTimestamp);
				  $defect->RESULT_DATETIME($defectRestulTimestamp);
				  
				  #$defectScannerModelID =~ s/\"$//;
				  INFO( "Result Timestamp=>$defectResultDate $defectResultTime") if $debug;
				  #print "defectScannerID-->$defectScannerModelID<--";
				  
			} elsif($line_ =~ m/^SetupID/) {
				$tmp = $line_;
				chomp $tmp;
				#$tmp =~ s/\"//g;
				($tmp, $family) = split(/ /, $tmp, 2);
				$family = ($family =~ /"([\d\D]*)"\s*[\d\D]*/ig)[0];
				if($defect->{DB_LOCATION} eq "Sandbox") {
					$program = $family;
					$program = "DEF::".$program;
					$defect->PROGRAM($program);
				} else {
					$program = $defect->{PRODUCT};
					$program = "DEF::".$program;
					$defect->PROGRAM($program);
				}
				
				INFO("Family inside the file: $family") if $debug;
				# FAMILY DiePitch does not exist
				#print "yes" if $family lt "FAN48630A8B";
				#if(!exists($defwaferinfo{$family}))
				if(!exists($defect->{"DIE_WIDTH"}) || !exists($defect->{"DIE_HEIGHT"})) {
					print "No diex diey got from db!\n" if $debug;
					WARN("NO die_width and die_height from REFDB");
					# jgarcia: commented to force to split if necessary even if there is no diex and diey from refdb.
					#$skip_flag = 1;
					#last;
				}
			
			} elsif ($line_ =~ m/^StepID/) {
				  my @ids = split / /, $line_;
				  my $lastIndex = $#ids;
				  $defectStepID = $ids[$lastIndex];
				  #$defectStepID =~ s/[^[:print:]]+//g;
				  $defectStepID =~ tr/\"\;//d;
				  trim($defectStepID);
				  $defect->STEP_ID($defectStepID);
				  
				  #$defectScannerModelID =~ s/\"$//;
				  INFO("Step ID =>$defectStepID") if $debug;
				  #print "defectScannerID-->$defectScannerModelID<--";
				  
			} elsif($line_ =~ m/^SampleTestPlan/) {
				$testplan_flg = 1;
				$testplan_cnt++;
			} elsif($line_ =~ m/^DefectList/) {
				$defect_flg = 1;
			} elsif($line_ =~ m/^DiePitch/) {
				$tmp = $line_;
				chomp $tmp;
				$tmp =~ s/\;$//;
				($tmp, $die_x, $die_y) = split(/ /, $tmp);
				$org_die_x = $die_x;
				$org_die_y = $die_y;
				#print "diew=>".$hMetaData{"DIE_WIDTH"}."||dieh=>".$hMetaData{"DIE_HEIGHT"}."\n";
				if(($refdBDieX eq "" || $refdBDieY eq "") || ($refdBDieX == 0 || $refdBDieY == 0)) {
				#if(!exists($header->DIE_WIDTH) || !exists($header->DIE_HEIGHT)) {
					WARN("No die_width die_height got from REFDB! or diex and diey have zero value.");
					INFO("Will be using DiePitch info from the raw file for die_width and die_height");
					#$skip_flag = 1;
					#last;
					#$hashMetaData{"DIE_WIDTH"} = $org_die_x;
				  #$hashMetaData{"DIE_HEIGHT"} = $org_die_y;
				  $refdBDieX = $org_die_x;
				  $refdBDieY = $org_die_y;
				}
			} elsif($line_ =~ m/^SummaryList/){
					$summary_flg = 1;
			} elsif($line_ =~ m/^OrientationMarkLocation/) {
				$tmp = $line_;
				chomp $tmp;
				$tmp =~ s/\;$//g;
				@tmp_arr = split(/ /, $tmp);
				$notch = $tmp_arr[1];
			} elsif($line_ =~ m/^ClassLookup/) {
				
				INFO("Original DiePitch $die_x $die_y");
				#printf STDERR "DB DiePitch $die_x_db $die_y_db\n" if $debug;
				# Supported notch location: DOWN, RIGHT
				if($notch eq "RIGHT") {
					INFO("X & Y swapped due to notch location");
					#$x_die_sep = int(($die_x/$defwaferinfo{$family}{"die_y"})+0.5);
					#$y_die_sep = int(($die_y/$defwaferinfo{$family}{"die_x"})+0.5);
					#$x_die_sep = int(($die_x/$hMetaData{"DIEY"})+0.5);
					#$y_die_sep = int(($die_y/$hMetaData{"DIEX"})+0.5);	
					#$x_die_sep = int(($die_x/$hMetaData{"DIEY"})+0.5);
					#$y_die_sep = int(($die_y/$hMetaData{"DIEX"})+0.5);
					$x_die_sep = int(($die_x/$refdBDieY)+0.5);
					$y_die_sep = int(($die_y/$refdBDieX)+0.5);						
				#} elsif($notch -eq "UP") {
				} else {
					#$x_die_sep = int(($die_x/$defwaferinfo{$family}{"die_x"})+0.5);
					#$y_die_sep = int(($die_y/$defwaferinfo{$family}{"die_y"})+0.5);
					#INFO("$x_die_sep, $y_die_sep = $hMetaData{'DIEX'} ");
					#$x_die_sep = int(($die_x/$hMetaData{"DIEX"})+0.5);
					#$y_die_sep = int(($die_y/$hMetaData{"DIEY"})+0.5);
					$x_die_sep = int(($die_x/$refdBDieX)+0.5);
					$y_die_sep = int(($die_y/$refdBDieY)+0.5);					
				}
				INFO("Sep DiePitch $x_die_sep $y_die_sep");
				if($x_die_sep != 0 && $x_die_sep != 1) {
					$die_x = $die_x/$x_die_sep;
				} else {
					$die_x = $die_x;
				}
			
				if ($y_die_sep != 0 && $y_die_sep != 1) {
					$die_y = $die_y/$y_die_sep;
				} else {
					$die_y = $die_y;
				}
				INFO("After DiePitch $die_x $die_y");# if $debug;
				
				# no split necessary
				if ($x_die_sep == 1 && $y_die_sep == 1) {
					 INFO("No Split Necessary!!!");
					 #print("No Split necessary\n");
					$skip_flag = 1;
					last;
				}
			}
			push @def_data, $line_;
		} elsif($testplan_flg) {
			
			$line_ =~ s/^ +//;
			$line_ =~ s/\;//;
			$line_ =~ s/\s+$//g;
			#$line_ =~ s/ +/ /;
			$line_ =~ s/ +/ /g;
#			if ($line_ =~ /\s+/) {
#				($x_coord, $y_coord) = split(/\s+/, $line_);
#			} else {
#				($x_coord, $y_coord) = split(/\s/, $line_);
#			} 
      #($x_coord, $y_coord) = split(/ /, $line_);
      #print "Line>>$line_<<\n";
      my @coord = split(/ /, $line_);
      $x_coord = $coord[0];
      $y_coord = $coord[1];
			#INFO("Orig Xcorrd=>$x_coord || Orig Ycorrd=>$y_coord"); 
			#INFO("X_DIE_SEP=>$x_die_sep || Y_DIE_SEP=>$y_die_sep");
			$x_coord = $x_coord * $x_die_sep;
			$y_coord = $y_coord * $y_die_sep;
			#INFO("After multiplied by x_die_sep=>$x_die_sep:=>NEW Xcorrd=>$x_coord || After multiplied by y_die_sep=>$y_die_sep:=>NEW Ycorrd=>$y_coord");
			
			for(my $i=0;$i<$x_die_sep;$i++) {
				#print "X>>$x_coord\n";
				for(my $j=0;$j<$y_die_sep;$j++) {
					#INFO("New x_coord + $i=>$x_coord+$i || New y_coord + $j=>$y_coord+$j");
					#INFO("IM HERE!!!!");
					#print("X>".$x_coord+$i."| Y>".$y_coord+$j."\n");
					#print "Y>>$y_coord\n";
					#my $testLine = sprintf(">>  %d %d  \n", $x_coord+$i, $y_coord+$j);
					#print($testLine);
					push @def_data, sprintf("  %d %d  \n", $x_coord+$i, $y_coord+$j);
					$SampleTestPlan{$testplan_cnt}++;
				}
			}
			next;
		} elsif($defect_flg) {
			my $def_str = "";
			$line_ =~ s/^ //;
			@tmp_arr = split(/ /, $line_);
			my $x_indx_adj = 0; # x multiple numbers
			my $y_indx_adj = 0; # Y multiple numbers
			
			
			# XREL (DIE shift)
			if($tmp_arr[1] > $die_x) {
				$x_indx_adj = int($tmp_arr[1] / $die_x);
				$tmp_arr[1] = $tmp_arr[1] - ($die_x * $x_indx_adj);
			}
			
			# YREL (DIE shift) 
			if($tmp_arr[2] > $die_y) {
				$y_indx_adj = int($tmp_arr[2] / $die_y);
				$tmp_arr[2] = $tmp_arr[2] - ($die_y * $y_indx_adj);
			}
			
			# XINDEX (X shift)
			if($x_die_sep != 0) {
				$tmp_arr[3] = ($tmp_arr[3] * $x_die_sep) + $x_indx_adj;
			}
			# YINDEX (Y shift)
			if($y_die_sep != 0) {
				$tmp_arr[4] = ($tmp_arr[4] * $y_die_sep) + $y_indx_adj;
			}
			
			$def_list{$tmp_arr[10]}{$tmp_arr[3]." ".$tmp_arr[4]} = 1;
			
			for(my $i = 0; $i < scalar(@tmp_arr); $i++) {
				if($i == 1 || $i == 2 || $i == 5 || $i == 6|| $i == 8) {
					$def_str .= sprintf(" %.3f", $tmp_arr[$i]);
				} elsif($i == 7) {
					$def_str .= sprintf(" %.6f", $tmp_arr[$i]);
				} else {
					$def_str .= " ".$tmp_arr[$i];
				}
			}
			push @def_data, $def_str;
		}	elsif($summary_flg) {
			$summary_cnt++;
			chomp $line_;
			$line_ =~ s/^ +//;
			$line_ =~ s/ +\;$//;
			$line_ =~ s/\s+/ /g;
			@tmp_arr = split(/ /, $line_);
			if($summary_cnt == 1) {
				$line_ = sprintf(" %d    %d    %.10e    %d    %d", $tmp_arr[0], $tmp_arr[1], $tmp_arr[2], $SampleTestPlan{$summary_cnt}, scalar(keys(%{$def_list{$summary_cnt}})));
			} else {
				$line_ = sprintf("  %d    %d    %.10e    %d    %d", $tmp_arr[0], $tmp_arr[1], $tmp_arr[2], $SampleTestPlan{$summary_cnt}, scalar(keys(%{$def_list{$summary_cnt}})));
			}
			if($summary_cnt == $testplan_cnt) {
				$line_ = $line_."  \;\n";
			} else {
				$line_ = $line_."   \n";
			}
			push @def_data, $line_;
		} else {
			push @def_data, $line_;
		}
	}
	undef $fileHandle;
	
	if($skip_flag) { 
		#printf STDERR "$DataFileName excluded for die conversion.\n" if $debug; 
		#open again the infile and loop to each line and save to an array
		#open(FILE, "$DataFile");
		INFO("$infile is excluded for die conversion.");
		my $fileHandle2 = IO::File->new($infile) or dpExitError("Failed to open Defect file $infile");
		while (my $line = $fileHandle2->getline) {
			push @inputFileLineData, $line;
		}
#		while(my $line_ = <FILE>) {
#			print OUTFILE $line_;
#		}
		#close(FILE);
		undef $fileHandle2;
#		move("$DataFile", $success);
		#assign the array of data lines to model misc 
#		=pod$defect->wafers(@waferArray);
#	  $defect->slots(@slotArray);
#		$model->misc(@inputFileLineData);=cut
#		
#		$defect->wafers(@waferArray);
#		$defect->slots(@slotArray);
#		$defect->imageFiles(@imageArray);
#		$defect->defectIndexes(@defectIndexList);
#		$defect->imageIndexes(@imageList);
		$model->misc(@inputFileLineData);
		
		return $model; # exit sub routine and return the model
	}
	
	$testplan_cnt = 1;
	foreach my $line_ (@def_data) {
		if($line_ =~ m/^DiePitch/) {
			#my @tmp = split(/ /, $line_);
			
			INFO("New DiePitch %.10e %.10e, $die_x, $die_y") if $debug;
			INFO("Split(x,y): $x_die_sep $y_die_sep") if $debug;
			#print "$line_";
			INFO("format DiePitch, to shift DiePitch");
			$line_ = sprintf("DiePitch %.10e %.10e\;\n", $die_x, $die_y);
		} elsif($line_ =~ m/^SampleCenterLocation/) {
			$tmp = $line_;
			chomp $tmp;
			$tmp =~ s/\;$//;
			my @tmp_arr = split(/ /, $tmp);
			my $center_x = $tmp_arr[1];
			my $center_y = $tmp_arr[2];
			my $center_flg = 0;
			# Origin offset
			my $origin_x_offset1 = 0;
			my $origin_y_offset1 = 0;
			# Origin offset
			my $origin_x_offset2 = 0;
			my $origin_y_offset2 = 0;
			
			# SampleCenterLocation
			if($center_x != 0) {
				$origin_x_offset1 = floor($center_x / $org_die_x) * $x_die_sep;
				$origin_x_offset2 = floor($center_x / $die_x);
			}
			if($center_y != 0) {
				$origin_y_offset1 = floor($center_y / $org_die_y) * $y_die_sep;
				$origin_y_offset2 = floor($center_y / $die_y);
			}
			
			# 
			if ($origin_x_offset1 != $origin_x_offset2) {
				my $x_adj = $origin_x_offset1 - $origin_x_offset2;
				$center_x = $center_x + ($x_adj * $die_x);
				$center_flg++;
			}
			if ($origin_y_offset1 != $origin_y_offset2) {
				my $y_adj = $origin_y_offset1 - $origin_y_offset2;
				$center_y = $center_y + ($y_adj * $die_y);
				$center_flg++;
			}
			
			# 
			if ($center_flg > 0) {
				#printf STDERR "Original $line_" if $debug;
				INFO("Original=> $line_") if $debug;
				#comment the logic to shift SampleCenterLocation
				#$line_ = sprintf("SampleCenterLocation %.10e %.10e\;\n", $center_x, $center_y);
				#print "New $line_";
			}
		}	elsif($line_ =~ m/^SampleTestPlan/) {
			$line_ = "SampleTestPlan ".$SampleTestPlan{$testplan_cnt}." \n";
			$testplan_cnt++;
		} 
		#print OUTFILE $line_; # assign defect line data array to model->misc
		push @inputFileLineData, $line_;
	}
	
#	$defect->wafers(@waferArray);
#	$defect->slots(@slotArray);
#	$defect->imageFiles(@imageArray);
#	$defect->defectIndexes(@defectIndexList);
#	$defect->imageIndexes(@imageList);
	$model->misc(@inputFileLineData);
	
	
	
	return $model;
 
  
	
}#end of sub splitDie {}

sub dpExitError {
	my $self    = shift;
	my $message = shift;
	dpExit( 1, $message );
}


sub getLotFromFilename {
	my $baseFn = shift;
	my $lot;
	my $counter = 0;
	
	if($baseFn =~ /(\w{1,8})\_\d{1,}\w+\_\d{4}\-\d{2}\-\d{2}\_\d{2}\-\d{2}\-\d{2}\_/) {
		$lot = $1;
	} elsif ($baseFn =~ /(\w{1,8})\-\w+\-\d{14}\-/) {
		$lot = $1;
	} elsif ($baseFn =~ /(\w+)\-\d{1,}\-\w+\-\d{14}\-\w+/) {
		$lot = $1;
		$lot = substr($lot, -8)
	} elsif ($baseFn =~ /\w+\-(\w{8})\-\d{1,}\-\w+\-\d{14}\-/) {
		$lot = $1;
	} elsif ($baseFn =~ /(\w+)\_\d{14}[A-Za-z]{4}/) {
		$lot = $1;
		$lot = substr($lot, -8)
	} elsif ($baseFn =~ /(\w{12}\.001$)/) {
		$lot = $1;
		$lot = substr($lot, 0, 8);
	}
	
	return $lot;
}
1;
