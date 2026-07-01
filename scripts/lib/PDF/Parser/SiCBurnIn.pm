=pod

=head1 SYNOPSIS

instantiate and use its method/subroutine and attributes.

=head1 DESCRIPTIONS

B<This script> will parse SIC burn-in data from SZ.

=head1 AUTHOR

B<junifferallan.garcia@onsemi.com>

=head1 CHANGES


=head1 LICENSE

(C) ON Semiconductor 2021.  All rights reserved.

=cut

package PDF::Parser::SiCBurnIn;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use File::Find;
use PDF::Util::TestFlowCodeUtility qw/getTestFlowCodeMode/;
use IO::File;
use File::Spec;
use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

my $attr = [qw//];

sub array {
	return qw//;
}

__PACKAGE__->mk_accessors( @$attr, array );

sub readSICBurnIn {

  my $self = shift;
  my $sicBurnIn = shift;
  #INFO("SIC File=$sicBurnIn");
  my $header = new_headerLong;
  my $model  = new_model (
		{
			header => $header,
			dataSource => 'SiCBurnIn'
		}
	);
	my $wafer = new_wafer;
	$model->add( 'wafers', $wafer );


  my $fileHandle = IO::File->new($sicBurnIn) or dpExit("Failed to open SiCBurnIn file $sicBurnIn");
  my $lineFlag = 0;
  my ($IRMaxLim, $VRLim);
  my $dataFlag = 0;
  my $lineTestElementsCount;

  while (my $line = $fileHandle->getline) {
    my @item = split(/\,/, $line);
    if($item[0] eq "FilePath") {
      my @item2 = split(/\//, $item[2]);
      $header->INDEX1(trim($item2[1]));
      $lineFlag = 2;
    }
    if($item[0] eq "LotInfo") {
      $header->LOT(trim($item[1]));
      $lineFlag = 3;
    }
		if($item[0] eq "BoardInfo") {
			$header->EQUIP3_ID(trim($item[1]));
			#$wafer->number(trim($item[1]));
      $lineFlag = 5;
    }
    if($item[0] eq "FileName") {
			my ($dummy1, $dummy2) = split(/\_/, $item[1]);
			$wafer->name(trim($item[1]));
			$wafer->number($dummy2);
      $lineFlag = 5;
    }
    if($item[0] eq "DeviceName") {
			my @values = @item;
			my $dump = shift @values;
			my $product = join(',', @values);
			$header->PRODUCT($product);
			$header->PROGRAM($product);
      $lineFlag = 6;
    }
    if($item[0] =~ /Oven(.+)?/) {
      $header->EQUIP2_ID(trim($item[1]));
      $lineFlag = 7;
    }
    if($item[0] =~  /Slot(.+)?/){
      $header->INDEX2(trim($item[1]));
      $lineFlag = 8;
    }
    if($item[0] =~ /IRMax.+/i ) {
      $IRMaxLim = trim($item[1]);
      $lineFlag = 9;
    }
    if($item[0] =~ /VR.+/i) {
      $VRLim = trim($item[1]);
      $lineFlag = 10;
    }
    if($item[0] eq "No" && $item[1] eq "Date") {

      $lineFlag = 12;
      my $t = 0;
			$lineTestElementsCount = $#item;
			for (my $i = 4; $i <= $#item; $i++) {
        my ($name,$unit) = split(/\(/, $item[$i]);
        #$name =~ tr/\)//;
        $unit =~ s/\)//g;
        #INFO("Name=$name || UNIT=$unit");
				my $test = new_test;
				$test->name($name);
        $test->units($unit);
        if($name =~ /IR(.+)?/) {
          $test->HSL($IRMaxLim);
        }
        if($name =~ /VR(.+)?/) {
          $test->HSL($VRLim);
        }
				$wafer->add( 'tests', $test );
			}
    }
    if($item[0] =~ /\d{1,}/ && $item[1] =~ /\d{4}(\-|\/)\d{2}(\-|\/)\d{2}/) {
      my $numD = scalar(@item);
			my $date = "";
			my $time = "";
			if($item[2] =~ /\d{2,}\:\d{2,}$/) {
				$time = $item[2].":00";
			}
			$date = join ' ', $item[1], $time;
			$date = formatDate($date);
      if($item[0] == 1) {
				INFO("STARTTIME=$date");
				#$header->OPERATOR($date);
				$wafer->START_TIME($date);
      }
			 	my $die  = new_die;
        $die->partid(trim($item[0]));
				$die->readtime($date);
        $die->runtime(trim($item[3]));
        $die->result( @item[ 4 .. $numD - 1 ] );
        $wafer->add( 'dies', $die );


    }



  }#end of while

  return $model;

}#end of sub routine

1;
