# SVN $Id: Asc.pm 1835 2016-08-30 06:17:06Z dpower $
# 2015-Aug-26 gilbert Uppercase the lot id
# 2015-Aug-31 gilbert Enhanced parsing of lot id
# 2015-Sep-01 gilbert If no match in pp_lot use device as product
# 2016-Aug-30 eric    get die width/height and calculate center die
#
package PDF::Parser::Asc;
use strict; 
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
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
Device Name : AB6QU-SG0112M        Tested Dies   : 40
Wafer Id    : 1FT332-19            R/C No.       : 201410965847
Columns     : 86                   Total Pass    : 0
Rows        : 104                  Total Fail    : 40
Start Time  : 2014/10/09 06:02     Finish Time   : 2014/10/09 06:06
Lot No      : 1FT332-CP1Q          Test Time     :
Wafer Size  : 6_INCH               Flat Direction: 180___(Down)
Slot No     : 1                    Use Time      :
Test Program:


Yield%    Pass    Fail   Gross
   0.0       0      40      40

  BIN      31      99
  QTY      40    6297
Yield   100.0

=cut

#Device -> PRODUCT
#Wafre Id -> wafernumber 
#R/C No  
#Lot No -> Lot

sub readFile{
  	my $self = shift;
  	my $infile = shift;
	my $multiplier = 25.4;
	my $convertToMilimeterFlag = "Y";
  	open (INFILE, $infile);
  	my $header = new_headerLong;
  	my $wmap = new_wmap({
     		positive_x => 'R',
     		positive_y => 'D'
     	});
  	my $model = new_model({
    		header=>$header,
    		wmap => $wmap,
    		dataSource => 'ASC'
   	});
  	my $wafer = new_wafer;
  	$model->add('wafers',$wafer);

  	my $section = "Header";
  	my ($columns, $rows);
  	my ($x,$y,$deviceCount) = (0,0,0);
  	my $device = "";
  	while(<INFILE>) {
    		if (/Device Name : (\S+)/) {
      			$device = "$1";
      			$header->PROGRAM($device);
    		}
    		if (/Test Program: (\S+)/) {
      			$header->PROGRAM($1);
    		}
   		if (/Lot\s+No\s+\:\s{0,}(.*?)-(.*?)\s+/i) {
			$header->LOT(uc($1));
        		$model->misc($2);
		}
    		if (/Wafer Id    : (\w+)-(\d+)/) {
			$wafer->number($2);
    		}
    		if (/Columns     : (\d+)/) {
			$columns= $1;
    		}
    		if (/Rows        : (\d+)/) {
			$rows= $1;
    		}
    		if (/Start Time  : (\d{4}\/\d{2}\/\d{2} \d{2}:\d{2})/) {
        		$wafer->START_TIME($1.":00");
    		}
    		if (/Finish Time   : (\d{4}\/\d{2}\/\d{2} \d{2}:\d{2})/) {
        		$wafer->END_TIME($1.":00");
    		}
    		if (/Wafer Size  : (\d+)_(\w+)/) {
        		$wmap->wf_size($1);
        		$wmap->wf_units($2);
        		if ("$1_$2" eq "6_INCH"){
           			$wmap->flat_type('F');
        		}
			else {
				$wmap->flat_type('N');
			}
    		}
    		if (/Flat Direction: (\d+)_/) {
        		given ($1){
          			when (180){$wmap->flat('B');}
          			when (0){$wmap->flat('T');}
          			when (90){$wmap->flat('L');}
          			when (270){$wmap->flat('R');}
          			default { ERROR("invalid Flat Direction: $1");}
        		}
    		}
    		if (/  BIN \s+(.*)$/){
      			foreach (split(/\s+/,$1)){
        			my $bin = new_bin;
        			$bin->number($_);
        			$bin->name("BIN_".sprintf("%02d",$_));
        			$bin->PF( ($_ == 1) ? 'P' : 'F');
        			$wafer->add('bins',$bin);
      			}
    		}
    		if (/  QTY \s+(.*)$/){
      			my $i = 0;
      			foreach (split(/\s+/,$1)){
         			$wafer->bins->[$i]->count($_);
         			$i++;
      			}
    		}
    		if ($header->PRODUCT eq "") {
        		$header->PRODUCT($device);
    		}
    		if ($section eq "Map"){
      			$y++;
      			last if ($y > $rows);
      			$x=0;
      			foreach my $bin (split(//)){
        			$x++;
        			next if ($x > $columns);
        			next if ($bin eq  ' ');
        			my $die = new_die({
           				x => $x,
           				y => $y });
        			if ($bin eq 'M'){
           				$die->inked(1);
           				next;
        			} 
        			$header->DEVICE_COUNT($header->DEVICE_COUNT+1); 
        			$bin =~ s/\./1/ge;
        			$bin =~ s/[A-L]/ord($&)-ord("A")+10/ge;
        			$bin =~ s/[M-Z]/ord($&)-ord("A")+9/ge;
        			$bin =~ s/\$/99/ge;
        			$die->soft_bin($bin), 
        			$wafer->add('dies',$die);
      			}
    		}
    		if ($section eq "EndOfHeader"){
      			$section = "Map";
    		}
    		if (/Yield /){
      			$section = "EndOfHeader";
    		}
       
  	}
	close(INFILE);

	my $loc_waf_size = $wmap->wf_size;
	###use wafer size from file in not available in PP_PROD###
    	if($wmap->{wf_size} eq "" || $wmap->{wf_size} == 0){
        	WARN ("Wafer size not available from the database");
        	$wmap->wf_size($loc_waf_size);
        	###assume in mm already###
        	$convertToMilimeterFlag = "N";
    	}

	###convert wafer size to mm, used common fixed values otherwise multiply by 25.4### jgarcia added###
    	if($wmap->{wf_units} ne "mm" || $wmap->{wf_units} =~ /IN/i) {
        	if($convertToMilimeterFlag eq "Y") {
                	if ($wmap->{wf_size} == 5) {
                  		$wmap->wf_size(125);
                	}
                	elsif ($wmap->{wf_size} == 6) {
                  		$wmap->wf_size(150);
                	}
                	elsif ($wmap->{wf_size} == 8) {
                  		$wmap->wf_size(200);
                	}
                	else {
                  		$wmap->wf_size(floor(($wmap->{wf_size}) * $multiplier) - 2);
                	}
        	}
		$wmap->wf_units("mm");
    	}

	$wmap->die_width($wmap->wf_size / $columns);
	$wmap->die_height($wmap->wf_size / $rows);
	my $stats = $wafer->stats;
	$wmap->calcCenterDie($stats);

return $model;
}


1;
