package PDF::DpData::WMap;
# SVN $Id: WMap.pm 1618 2016-05-12 08:02:05Z dpower $
# 2015-May-08 >> jgarcia >> added sub routine (populateWaferSizeWaferUnitFromPP_PROD). 
use strict;
use base qw/PDF::DpData::Base/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DAO;
use POSIX qw(floor ceil);
sub list {qw/
    wf_units wf_size flat_type flat die_width die_height center_x center_y
    positive_x positive_y reticle_rows reticle_cols reticle_row_offset reticle_col_offset 
  /}

my $attr = [qw/
	confirmed tester_type product device_count input_file location cfg_id isFinalLot isRelLot
   /];

__PACKAGE__->mk_accessors(list, @$attr);


sub new_from_refdb{
   my $class = shift;
   my $product = shift;  
   my $cfg_tester_type= shift;
   my $location   = shift;
   
   my $hash = getRefdb->getWMap($product, $cfg_tester_type, $location);
   return $class->new($hash);
}

sub register_refdb{
  my $self = shift;
  unless (defined $self->product and defined $self->tester_type and defined $self->location){
   ERROR("WMap:Product or TesterType is null. This WMAP will not be registered in Refdb");
  } else {
    getRefdb->insertWMap($self); 
  }
}

sub confirmed_flag{
  my $self = shift;
  unless (defined $self->product and defined $self->tester_type and  defined $self->location){
   ERROR("WMap:Product or TesterType is null. This WMAP will not be registered in Refdb");
  } else {
   
  my $hash = getRefdb->getCompareSize($self->product);
  if(keys %$hash >0){
	if($hash->{compared}){
		# 07-Jul-15 SAB Don't auto-confirm maps, but do update wfr size from PP_PROD if needed.
#		if($hash->{wf_size} eq "match"){
#			if(getRefdb->confirm_WMap($self, 'match'))
#			{
#				INFO("auto confirmed");
#			};
#		}
		if ($hash->{wf_size} ne "match" ){
			if(getRefdb->confirm_WMap($self, $hash->{wf_size}))
			{
				INFO("wfr size from pp_prod");
			};
		}
		 
	}
  }
    
  }
}

sub populateDieSize{
  my $self =shift;
  unless (defined($self->product)){
    ERROR("WMAP:PRODUCT to lookup RefDB is null ");
    return 0;
  }
  my $hash = getRefdb->getProduct($self->product);
  if (keys %$hash > 0){
	INFO("Good. DieSize Found for Product = ".$self->product);
  	$self->die_width($hash->{die_width});
  	$self->die_height($hash->{die_height});	
	
        return 1;
  }else {
        return 0;
  } 
}
##join PP_LOT and PP_PROD###
#sub populateWaferSizeWaferUnitFromPP_PROD {
#	my $self = shift;
#	my $lotidFromFile = shift;
#	unless(defined($lotidFromFile)){
#		ERROR("WMAP: LOT to lookup RefDB PP_LOT and PP_PROD by lotid is null ");
#		return 0;
#	}
#	my $hash = getRefdb->getProductInfobyLotidFromFileOnPP_LOTandPP_PROD($lotidFromFile);
#	if(keys %$hash > 0) {
#		INFO("Good. pp_lot.lot, pp_prod.product, pp_prod.wf_size, pp_prod.wf_units = ".$lotidFromFile);
#		#$self->lot($hash->{$lot});
#		$self->product($hash->{PRODUCT});
#		$self->wf_size($hash->{wf_size});
#		$self->wf_units($hash->{wf_units});
#		#$self->die_width($hash->{die_width});
#		#$self->die_height($hash->{die_height});
#		return 1;
#	}
#	else {
#		return 0;
#	}
#}


sub populateWaferSizeWaferUnitFromPP_PROD {
	my $self = shift;
	my $lotidFromFile = shift;
	my $finalLotFlag = shift;
	my $lookuptable = "PP_LOT";
	my $hash;
	
	if ( $finalLotFlag ) {
        $lookuptable = "PP_FINALLOT";
        unless ( defined( $lotidFromFile ) ) {
            ERROR("Lot to lookup RefDB.".$lookuptable." is null ");
            return 0;
        }		
        $hash = getRefdb->getProductbyLotidFromPP_FINALLOT( $lotidFromFile );
    }
    else {
        unless ( defined( $lotidFromFile ) ) {
            ERROR("Lot to lookup RefDB.${lookuptable} is null ");
            return 0;
        }
        $hash = getRefdb->getProductbyLotidFromPP_LOT( $lotidFromFile );		
    }
		if(defined($hash->{product})){
		INFO("WMAP: Good. PRODUCT Found for Lot = " . $lotidFromFile ." in ${lookuptable}");
		}else {
			INFO($hash->{product}. "NOT FOUND in ${lookuptable}");
			return 0;
		}
	### if product is not empty ###
	my $hash = getRefdb->getProductInfoByProductInPP_PROD($hash->{product});
	if(keys %$hash > 0) {
		INFO("Good. pp_lot.lot, pp_prod.product, pp_prod.wf_size, pp_prod.wf_units = ".$hash->{product});
		#$self->lot($hash->{$lot});
		$self->product($hash->{product});
		$self->wf_size($hash->{wf_size});
		$self->wf_units($hash->{wf_units});
		#$self->die_width($hash->{die_width});
		#$self->die_height($hash->{die_height});
		return 1;
	}
	else {
		return 0;
	}
}


sub convertDieSizeToMM{
  my $self = shift;
  my $unit = shift;
  my $stats = shift;
  my $cols = $stats->{columns};
  my $rows = $stats->{rows};
  my $die_width = $self->die_width;
  my $die_height = $self->die_height;
  my $factor = 1.0;
  if(uc($unit) eq 'MILS'){
     $factor = 25.4 * 0.001;
  }elsif (uc($unit) eq 'AUTO'){
     # assume the unit is mm
     my $diamX = $self->die_width * $cols;
     my $diamY = $self->die_height * $rows;
     if ($diamX > $self->wf_size or $diamY > $self->wf_size){
       INFO("Die unit must be milli inch");
       $factor = 25.4*0.001
     } 
  }
  $self->die_width($factor*$die_width);
  $self->die_height($factor*$die_height);
}

sub calcCenterDie{
  my $self = shift;
  my $stats = shift;
  my $minX = $stats->{minX};
  my $minY = $stats->{minY};
  my $maxX = $stats->{maxX};
  my $maxY = $stats->{maxY};
  INFO("DIE Range Column: $minX -- $maxX Rows: $minY -- $maxY");
  INFO("DIE Size Width=".$self->die_width." Height=".$self->die_height);
  my $numX = $maxX-$minX + 1;
  my $numY = $maxY-$minY + 1;
  my $radius;
  my $diamX = $numX * $self->die_width;
  my $diamY = $numY * $self->die_height;
  if ($self->flat eq 'B' or $self->flat eq 'T'){
    $radius = $diamX/2.0;
  } else {
    $radius = $diamY/2.0;
  }
  my $distanceX = $radius;
  my $distanceY = $radius;
  my $centerX = ceil($numX/2.0);
  my $centerY = ceil($numY/2.0);
  if ($self->flat_type eq 'F'){
    if ($self->flat eq 'T'){
      $distanceY = $diamY - $radius;
    }
    if ($self->flat eq 'L'){
      $distanceX = $diamX - $radius;
    }
    INFO("FLAT = ".$self->flat.", diamX = $diamX, diamY = $diamY, radius = $radius wafersize = ".$self->wf_size." ".$self->wf_units);
    $centerX = ceil($distanceX / $self->die_width);
    $centerY = ceil($distanceY / $self->die_height);
  }
  if (($numX % 2 ==0 ) and $self->positive_x eq 'R') {
    $centerX ++;
  }
  if (($numY % 2 ==0 ) and $self->positive_y eq 'U') {
    $centerY ++;
  }

  INFO("relative center X = $centerX Y = $centerY");
  INFO("absolute center X = ".($minX+$centerX-1)." Y = ".($minY+$centerY-1));
  $self->center_x($minX + $centerX-1);
  $self->center_y($minY + $centerY-1);
}

1;

__END__;

=pod

=head1 NAME

PDF::DpData::WMap - WMap object. lookup and populate PP_WMAP table

=head1 SYNOPSIS

  my $wmap = PDF::DpData::WMap->new_from_refdb( $header->PRODUCT, $TESTER );
  if ( $wmap->isEmpty ) {
    $wmap = PDF::DpData::WMap->new;
    $wmap->product( $header->PRODUCT );
    $wmap->tester_type($TESTER);
    $wmap->wf_units('mm');
    $wmap->wf_size($waferSize);
    if ( $waferSize eq 200 ) {
      $wmap->flat_type('N');
    } else {
      $wmap->flat_type('F');
    }
    my %flatDir = (
        0   => 'B',
        90  => 'R',
        180 => 'T',
        270 => 'L',
    );
    $wmap->flat( $flatDir{$flat} );
    $wmap->die_width($dieSizeX);
    $wmap->die_height($dieSizeY);
    $wmap->convertDieSizeToMM($dieSizeUnit);
    $wmap->positive_x('R');
    $wmap->positive_y('D');
    $wmap->calcCenterDie( $minX, $minY, $maxX, $maxY );
    $wmap->register_refdb;
  }
  $str_wmap = "<WMAP>\n";
  $str_wmap .= $wmap->toString;
  $str_wmap .= "</WMAP>\n";

=head1 Attributes  -- target of toString
  
  wf_units
  wf_size 
  flat_type 
  flat 
  die_width 
  die_height 
  center_x 
  center_y
  positive_x 
  positive_y 
  reticle_rows 
  reticle_cols 
  reticle_row_offset 
  reticle_col_offset

=head1 Attributes

  confirmed 
  tester_type 
  product
  deviceCount
  location
  cfg_id

=head1 METHODS

=head2 toString()

return string formated as <Attribute>=<Value>\n
order by listed above attributes section in each class
null value will be replaced to "NA"
    VERSION=1.0
    CREATION_DATE=2015/03/18 04:01:55
    PROGRAM_CLASS=1
    PROGRAM=ULSG0125WSX4_13_EAGLE
    RELEASE=NA
    ....

=head2 new_from_refdb($product,$testerType)

Look up Refdb.PP_WMAP by Product and Tester_Type.
If found, return new object with found data populated.
If not found, return undef

=head2 register_refdb

Insert into Refdb.PP_WMAP

=head2 calcCenterDie($wafer->stats)

calculate CenterDie and store the result into self->CENTER_X and self->CENTER_Y. Following attribute must be set before call this method.

  wf_size
  flat
  flat_type
  die_width
  die_height

=head2 convertDieSizeToMM(Unit, $wafer->stats)

convert DIE_WIDTH and DIE_HEIGHT to millimeter according to given unit.
 MILS : Milli Inch
 AUTO : automatically calcualte. Columns and Rows required in parameter
  1st assume the die size unit is "mm", then check is total die area is laterger than wafer size. If the size is too large, assume the die size unit is "milli inch"

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2014/05/21 edwardy: 1st version
 2015/03/10 kazukik: output IFF format
 2015/03/30 kazukik: new_from_refdb, register_refdb added
 2015/04/20 kazukik: update calcCenterDie logic
 2015/07/22 jgarcia: modified populateWaferSizeWaferUnitFromPP_PROD subroutine to lookup PRODUCT either in PP_LOT or PP_FINALLOT.

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

