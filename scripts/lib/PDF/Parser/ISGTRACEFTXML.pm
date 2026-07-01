package PDF::Parser::ISGTRACEFTXML;

use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use IO::File;
use DateTime;
use List::MoreUtils qw/first_index any uniq/;
use XML::LibXML;
use Data::Dumper;

use base qw/PDF::DpData::Base Class::Accessor/;

my $attr = [];
my $context;

sub array {
    return qw//;
}

__PACKAGE__->mk_accessors(array);

sub parseISGFTXML() {
  my $self = shift;
  my $inputFile = shift;
  my $eventType = shift;
  my $step = shift;
  my $threshold = shift;
  my %linePerStartimeLot;
  my $header = new_headerLong;
  my $model  = new_model(
    {
      misc       => {},
      dataSource => ''
    }
  );
  my $passBins = getPassBin($inputFile);
  my ($wafersPerEidLot, $eidLotList) = getWafers($inputFile);
  my @uniqueEidLots = uniq @$eidLotList;
  my $eidLotListSize = @uniqueEidLots;

  INFO("Total unique eid lots = $eidLotListSize");
  #INFO(scalar(@$eidLotList));
  #INFO(scalar(@uniqueEidLots));
  #print "@$eidLotList\n";
  #print "Distinct Eid_Lots=@uniqueEidLots\n";
  if($eidLotListSize > $threshold) {
    dpExit(1, "File has unique source lots exceeds the threshold=$threshold. source lots distinct count in the file => $eidLotListSize");
  }
  my $fileHandle = IO::File->new($inputFile) or dpExitError("Failed to open Text file $inputFile");

  while(my $line = $fileHandle->getline) {
    chomp($line);

    my @fields = ();
    
    if($line =~ /\<Stage\s+LOG.*/i) {
      $line =~ s/<Stage\s+//g;
      $line =~ s/\"//g;
      $line =~ s/\>$//;
      processLine($line);
      last;
    }
    if($line =~ /\<Lot LOT\=.*/i) {
      $line =~ s/<Lot\s+//g;
      $line =~ s/\"//g;
      $line =~ s/\>$//;
      processLine($line);
    }
  }#end of while loop
  undef $fileHandle;
  my $eventTime; 
  my $lot = $context->{'LOT'};
  if($lot =~ /(\w+)\+.*/) {
    $lot = $1;
  }
  my $sourceLot = "${lot}.S";
  my $fromSourceLot = "";
  my $fromLot = "";
  my $eventName =  ""; 
  my $partType = repNA($context->{'PART_TYPE'});
  my $testFacility = repNA($context->{'TEST_FACILITY'});
  my $waferNumber;
  my $waferId;
  my $key; 
  my $headerLineData = "${eventType}|${step}|${partType}|${testFacility}";

  if(%{$wafersPerEidLot}) {
    for my $key (keys %{$wafersPerEidLot}) {
        my $waferLineData = "";
        my $eidLot = $wafersPerEidLot->{$key}->{FSLOT};
        if($wafersPerEidLot->{$key}->{FSLOT} ne "") {
          $fromSourceLot = repNA($wafersPerEidLot->{$key}->{FSLOT}).".S";
          $fromLot = repNA($wafersPerEidLot->{$key}->{FSLOT}).".001";
        }
        if($wafersPerEidLot->{$key}->{TIME} ne "") {
          $eventTime = repNA($wafersPerEidLot->{$key}->{TIME});
        }
        if($wafersPerEidLot->{$key}->{WAFERNUM}) {
          $waferNumber = repNA($wafersPerEidLot->{$key}->{WAFERNUM});
          $waferId = repNA($wafersPerEidLot->{$key}->{FSLOT})."-".formatWaferNum($waferNumber);
        }
        if($key ne "") {
          $eventName = "${lot}_${fromLot}_${eventTime}";
          if($waferLineData eq "") {
            $waferLineData = $eventTime."|".uc($eventName)."|".uc($fromSourceLot)."|".uc($fromLot)."|".uc($lot)."|".uc($sourceLot)."|".uc($waferId)."|".$waferNumber;
            my $lineData = $headerLineData."|".$waferLineData;
            push(@{ $linePerStartimeLot{$key} }, $lineData);
          }
        } 
    }
  } else {
    ERROR("No valid unit found in the xml file to be able to generated a genealogy file.");
    dpExit(1,"No valid unit found in the xml file to be able to generated a genealogy file");
  }
  $model->misc(\%linePerStartimeLot);
  return $model;
}#end of sub parseFTKYECXML

sub getWafers() {
  my $inputFile = shift;
  my %wafersPerEidLot;
  my @eidLots = ();
  my $data;
  my $validUnitCounter = 0;
  my $passBins = getPassBin($inputFile);
  my $fileHandle = IO::File->new($inputFile) or dpExitError("Failed to open Text file $inputFile");
  my $insertionId;
  
  while(my $line = $fileHandle->getline) {
    chomp($line);
    #<Unit HD="0" ST="0" x="0" y="0" HardBin="1" SoftBin="111" Bin="1" Bit="1" Eid="0000000000000000B2C2645C3AAD17F8" Eid_X="-4" Eid_Y="15" Eid_Lot="9295619" Eid_Wafer="21">
    if($line =~ /\<Insertion\s+Id\=\"(\d+)\".*/i) {
      $insertionId = $1;
      $line =~ s/<Insertion\s+//g;
      $line =~ s/\"//g;
      $line =~ s/\>$//g;
      my @fields = split(/\s+/, $line);
      foreach my $field (@fields) {
        my ($key,$value) = split('=', $field);
        if($key eq "Time_Conv") {
          $data->{$key} = repNA($value);
        }
      }
    }
    if($line =~ /\<Unit\s+\H\D.*HardBin\=\"(\d+)\".*/i) {
      my $hardBin = $1;
      $line =~ s/<Unit\s+//g;
      $line =~ s/\"//g;
      $line =~ s/\>$//;
      if(any {$_ == $hardBin} @$passBins) {
        my @fields = split(/\s+/, $line);
        foreach my $field (@fields) {
          my ($key,$value) = split('=', $field);
          if($key eq "Eid_Lot" || $key eq "Eid_Wafer") {
            if($key eq "Eid_Wafer") {
              if($value <= 0 || $value >= 50) {
                #WARN("Eid_Wafer is <= 0 OR >= 50 => Eid_Wafer=$value... will not be included in the genealogy!!!");
                next;
              } else {
                $data->{$key} = repNA($value)
              }
            }
            if($key eq "Eid_Lot") {
              if($value eq "0" || $value eq "00") {
                #WARN("Eid_Lot has either 0 or 00 Eid_Lot=$value... will not be included in the genealogy!!!");
                next;
              } else {
                $data->{$key} = repNA($value);
                #$wafersPerEidLot{$value}++;
                push(@eidLots, repNA($value));
              }
            }
            my $key;
            my $keyEid;
            if($data->{'Eid_Lot'} ne "" && $data->{'Eid_Wafer'} ne "") {
              $key = $data->{'Eid_Lot'}."_".$data->{'Eid_Wafer'};
              
              #push(@{$wafersPerEidLot{$key}}, $data->{'Eid_Wafer'});
              if($wafersPerEidLot{$key}{TIME} ne "" ) {
                if($data->{'Time_Conv'} < $wafersPerEidLot{$key}{TIME}) {
                  $wafersPerEidLot{$key}{TIME} = $data->{'Time_Conv'};
                } 
              } else {
                $wafersPerEidLot{$key}{TIME} = $data->{'Time_Conv'};
              }
              $wafersPerEidLot{$key}{WAFERNUM} = $data->{'Eid_Wafer'};
              $wafersPerEidLot{$key}{FSLOT} = $data->{'Eid_Lot'};
              if($wafersPerEidLot{$key}{TIME} =~ /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/) {
                my $year = $1;
                my $mon = $2;
                my $day = $3;
                my $hour= $4;
                my $min = $5;
                my $sec = $6;
                $wafersPerEidLot{$key}{TIME} = "${year}-${mon}-${day} ${hour}:${min}:${sec}";
              }
              
            }
          }
        }

      }
      
    }
  } #end fo while loop
  undef $fileHandle;
  return (\%wafersPerEidLot, \@eidLots);
} #end of getWafers subroutine

sub getPassBin() {
  my $inputFile = shift;
  my @passBins;
  my $data;
  my $fileHandle = IO::File->new($inputFile) or dpExitError("Failed to open Text file $inputFile");
  my $validUnitCounter = 0;
  while(my $line = $fileHandle->getline) {
    chomp($line);
    if($line =~ /\<Bin\s+Number\="(\d+)\".*Type\=\"Hardware.*PassFail\=\"P\"\s+Count\=\"(\d+)\".*/i) {
      my $binNumber = $1;
      my $count = $2;
      $line =~ s/<Bin\s+//g;
      $line =~ s/\"//g;
      $line =~ s/\>$//;
      if($count > 0) {
        push(@passBins, $binNumber);
      }
    }
  } #end fo while loop

  undef $fileHandle;
  return \@passBins;
} #

sub processLine() {
  my $line = shift;
  my @fields = split(/\s+/, $line);
  foreach my $field (@fields) {
    my ($key,$value) = split('=', $field);
    if($key eq "LOT" || $key eq "PART_TYPE" || $key eq "TEST_FACILITY") {
      $context->{$key} = repNA($value);
    }
  }
}#end of sub subroutine processLine

sub formatWaferNum() {
  my $number = shift;
  if($number < 10 && $number =~ /\d{1}/) {
    $number = "0".$number;
  }
  return $number;
}

1;
