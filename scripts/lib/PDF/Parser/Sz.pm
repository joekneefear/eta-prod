####  2015/06/11 grace   : set input_file 
#     2015-Aug-26 Gilbert - Upppercase the lot id.

package PDF::Parser::Sz;
use strict; 
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;


use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

my $attr = [ qw/minX minY maxX maxY/];
sub array {
   return qw/testConditions_EPDR/;
}

__PACKAGE__->mk_accessors(array);

=pod
LOT ID: LHNTC
WAFER ID: 01
ROWS: 43
COLUMNS: 35
PRODUCT ID: 75545BA
PROBE DATE: 04/21/2015
PROBE TIME: 22:48:40
DIE PROBED: 0
WAFER SIZE: 200
FLAT PROBED:
X SIZE: 5.720
Y SIZE: 4.600
OPERATOR: 98497
SYSTEM ID: fab8sz3
PROBER:
TEST SYSTEM: fab8sz3
TEST STATION:
PROGRAM: 75545
PROBECARD: 7xx50  1
CABLE:
LOADBOARD:

X:   11, Y:   14, Bin:    1
X:   10, Y:   14, Bin:    1
X:   12, Y:   15, Bin:    1
=cut

my ($minX, $minY, $maxX, $maxY) = ("","","","");

sub readFile{
  my $self = shift;
  my $infile = shift;
  my $cfg_tester_type = shift;
  open (INFILE, $infile);
  my $header = new_headerLong;
  my $wmap   = new_wmap;
  my $model = new_model({
    header=>$header,
    wmap => $wmap,
    dataSource => 'SZ',
	cfg_tester_type => $cfg_tester_type
   });
  my $wafer = new_wafer;  
  $wmap->input_file(basename $infile);
  $model->add('wafers',$wafer);

  my $section = "Header";
  my ($columns, $rows);
  my ($x,$y,$deviceCount) = (0,0,0);
  my $tmpdate = undef;
  my %binCount; 
  my $equipment = undef;
  
  while(<INFILE>) {
    s/\n//;
	my @wk = split(":", $_);
	
	if($wk[0] =~/PROGRAM/){
		$header->PROGRAM(trim($wk[1]));
		$header->EQUIP6_ID("location_test");
	}
    if ($wk[0] =~ /PRODUCT ID/) {
      $header->PRODUCT(trim($wk[1]));	  
    }
	if ($wk[0] =~ /SYSTEM ID/){
		$equipment = trim($wk[1]);
	}
	if ($wk[0] =~ /TEST STATION/) {
		if(trim($wk[1]) eq "")
        {
			$header->EQUIP1_ID($equipment);
		}
		else{
			$header->EQUIP1_ID(trim($wk[1]));
		}		
    }
    if ($wk[0] =~ /LOT ID/) {		
		$header->LOT(uc(trim($wk[1])));
		%binCount = ();
    }
	if ($wk[0] =~ /WAFER ID/) {
		$wafer->number(trim($wk[1]));	
    }
	if ($wk[0] =~ /OPERATOR/)
	{
		$header->OPERATOR(trim($wk[1]));
	}
	if ($wk[0] =~ /FLAT PROBED/){
		if($wk[1] eq "L" or $wk[1] eq "R" or $wk[1] eq "B" or $wk[1] eq "U"){
			$wmap->flat(trim($wk[1]));	
		}
		else{
			$wmap->flat("L");
		}		
	
    }
	if ($wk[0] =~ /PROBECARD/) {
        $header->EQUIP3_ID(trim($wk[1]));       
    }
    if ($wk[0] =~ /COLUMNS/) {
		$columns= $wk[1];
    }
	if ($wk[0] =~ /WAFER SIZE/) {
		$wmap->wf_size(trim($wk[1]));
		$wmap->wf_units("mm");
		$wmap->flat_type("F");
		$wmap->positive_x("R");
		$wmap->positive_y("D");
	}
	if ($wk[0] =~ /X SIZE/) {
		$wmap->die_width(trim($wk[1]));	
	}
	if ($wk[0] =~ /Y SIZE/) {
		$wmap->die_height(trim($wk[1]));		
	}
    if ($wk[0] =~ /ROWS/) {
		$rows= $wk[1];
    }
    if ($wk[0] =~ /PROBE DATE/){
	
		if($_ =~/(\d{2}\/\d{2}\/\d{4})/){
			$tmpdate = $1;   
		}
    }
    if ($wk[0] =~ /PROBE TIME/){	
		if($_ =~ /(\d{2}\:\d{2}\:\d{2})/){
			$wafer->START_TIME($tmpdate." ".$1);
			$wafer->END_TIME($tmpdate." ".$1);
		}		
	}

    if ($wk[0] =~ /X/){
		if( $_ =~ /X:(\s+)(\S+), Y:(\s+)(\S+), Bin:(\s+)(\S+)/)
		{					
			$header->DEVICE_COUNT($header->DEVICE_COUNT+1); 
			my $die = new_die;
			my $x = trim($2);
			my $y = trim($4);
			
			$die->x($x); 
			$die->y($y); 
			$die->soft_bin($6);
			$wafer->add('dies',$die);   
			$binCount{$6} += 1;	
				
			if($minX eq "")
			{
				$minX = $x;
				$minY = $y;
				$maxX = $x;
				$maxY = $y;				
			}
			
			$minX = ($minX > $x) ? $x : $minX;
			$minY = ($minY > $y) ? $y : $minY;
			$maxX = ($maxX < $x) ? $x : $maxX;
			$maxY = ($maxY < $y) ? $y : $maxY;	

		}
		
	}

	if (/^EOF/){ 
				
		my $center_x = sprintf("%02d",($maxX-$minX)/2+$minX);
		my $center_y = sprintf("%02d",($maxY-$minY)/2+$minY);
		
		if($center_y < 0){
			$center_y = $center_y * -1;
		}
		
		$wmap->center_x($center_x);
		$wmap->center_y($center_y);

	   foreach my $binNum (sort keys %binCount) {
			my $bin = new_bin({
				number => $binNum,
				count => $binCount{$binNum}
			});			
			$bin->name(sprintf("BIN_%02d",$binNum));
			$bin->PF( ($binNum == 1) ? 'P' : 'F');
			$wafer->add('bins',$bin);
		   }
		}	
  }
return $model;
}



1;

