=pod

=head1 NAME

PDF::DpData::Defect - Defect object. lookup and populate PP_DEFECT table

=head1 SYNOPSIS

=head1 Attributes  -- target of toString
  DIE_WIDTH
  DIE_HEIGHT
  LOT
  SLOT
  STEP_ID
  RESULT_DATETIME 
  PRODUCT 
  FAMILY 
  FAB 
  PROCESS 
  DATE 
  LOCATION
=head1 Attributes

	inputFile 
	DB_LOCATION
	
=head1 METHODS
	populateDefectMetaData
	registerToRefdb
	populateDefect
=head2 

=head2 

=head1 AUTHOR

B<junifferallan.garcia@fairchildsemi.com>

=head1 CHANGES

 2016-Jul-28 jgarcia : 1st version
 2016-Aug-18 jgarcia : added support for defect with mulitple slots and wafers 
 

=head1 LICENSE

(C) Fairchild Semiconductor. 2016 All rights reserved.

=cut
package PDF::DpData::Defect;
use strict;
use base qw/PDF::DpData::Base/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DAO;
#use POSIX qw(floor ceil);
sub list {qw/ DIE_WIDTH DIE_HEIGHT LOT WAFER SLOT STEP_ID RESULT_DATETIME PRODUCT FAMILY FAB PROCESS DATE LOCATION PROGRAM DEFECT_INDEX
	            IMAGE_INDEX IMAGE_FILENAME IMAGE_TYPE /}

my $attr = [qw /inputFile  DB_LOCATION  imageFile /];

sub array{
  return qw/ slots wafers images defectIndexes imageIndexes/;
}


__PACKAGE__->mk_accessors(list, @$attr, array);


sub new {
    my ($class, $args) = @_;
    foreach my $key (%$args){
      if ( $key =~ /TIME$|DATE$/ ) {
         my $value = formatDate($args->{$key}) ;
         $args->{$key} = $value;
      }
    }
    my $self= $class->SUPER::new($args );
    $self->DATE(currentDate);
    return $self;
}
sub set {
    my ( $self, $key ) = splice( @_, 0, 2 );
    if ( $key =~ /TIME$|DATE$/ ) {
        my $value = shift @_;
        push( @_, formatDateToYYYYMMDD($value) );
    }
    $self->SUPER::set( $key, @_ );
}

sub populateDefectMetaData{
  my $self =shift;
  my $hash;
  #my $lot = shift;
  my $lookuptable = "PP_LOT, PP_PROD" ;
  unless (defined($self->LOT)){
    ERROR("Defect:LOT to lookup RefDB is null ");
    return 0;
  }
  $hash = getRefdb->getMetaDataForDefect($self->{LOT});
  if ( defined($hash ) and %$hash) {
 		INFO("Good. DieSize Found DIE_WIDTH=>$hash->{die_width}, DIE_HEIGHT=>$hash->{die_height} from refdb for defect LOT = ".$self->{LOT});
 	
	 	#SLOT STEP_ID RESULT_DATETIME DIE_WIDTH DIE_HEIGHT
#	 	foreach my $key (keys %$hash) {
#		 	INFO("KEY=>$key");
#		 	INFO("VALUE=>$hash->{$key}");
#		}
		$self->LOT($hash->{lot});
  	$self->PRODUCT($hash->{product});
  	$self->FAB($hash->{fab});	
  	$self->PROCESS($hash->{process});
  	$self->FAMILY($hash->{family});
  	$self->DIE_WIDTH($hash->{die_width});
  	$self->DIE_HEIGHT($hash->{die_height});
 
    return 1;
    
  }else {
  	WARN ( "Bad.. Meta Not Found for Lot = " . $self->{LOT}." in $lookuptable ");
    return 0;
  } 
}

sub registerToRefdb{
  my $self = shift;
  my $slot = shift;
  my $wafer = shift;
  #my $self    = shift;
  my $values  = {%$self};
  
   unless (defined $self->LOT and defined $self->STEP_ID  and defined $slot and defined $wafer and defined $self->RESULT_DATETIME){
   ERROR("Defect:SLOT or STEP_ID or RESULT_DATETIME is null. This Defect will not be registered in Refdb");
  } else {

  	 	getRefdb->checkAndInsertDefect($values, $slot, $wafer); 

  }
}


sub registerToRefdbWithDefectInfo{
  my $self = shift;
  my $slot = shift;
  my $wafer = shift;
  my $imageFile = shift;
  my $defectIndex = shift;
  my $imageIndex = shift;
  #my $self    = shift;
  my $values  = {%$self};
  
   unless (defined $self->LOT and defined $self->STEP_ID and defined $wafer and defined $slot and defined $self->RESULT_DATETIME){
   ERROR("Defect:SLOT or STEP_ID or RESULT_DATETIME is null. This Defect will not be registered in Refdb");
  } else {

  	 	getRefdb->checkAndInsertDefect2($values, $slot, $wafer, $imageFile, $defectIndex, $imageIndex, ); 

  }
}

sub populateDefect {
    my $self = shift;
    #my $slot = shift;
    #my $wafer = shift;
    my $hash ;
    my $lookuptable = "PP_DEFECT" ;
    #my @slotArray = shift;
    #my $slotCount;
    #my $counter = 0;
     
   
    unless ( defined( $self->LOT ) and defined( $self->SLOT) and defined( $self->RESULT_DATETIME ) ) {
       ERROR ("Lot to lookup RefDB is null ");
       return 0 ;
    }
    	#INFO("INSIDE populateDefectMeta");
    	INFO("LOT>>$self->{LOT}\tSLOT>>$self->{SLOT}\tRESULT_DATETIME>>$self->{RESULT_DATETIME}");
   
      	$hash = getRefdb->getDefectData ( $self->LOT, $self->SLOT, $self->RESULT_DATETIME );
     
        if ( defined($hash ) and %$hash) {
        	INFO ( "Good. Defect Data Found for Lot = " . $self->LOT ." in $lookuptable ");
          #INFO("$hash->{STEP_ID}");  
#        foreach my $key (keys %$hash) {
#        	INFO("$key=>$hash->{$key}");
#        }   
          #$self->LOT($hash->{LOT});
					$self->PRODUCT($hash->{product});
					$self->FAB($hash->{fag});	
					$self->PROCESS($hash->{process});
					$self->FAMILY($hash->{family});
					$self->DIE_WIDTH($hash->{die_width});
					$self->DIE_HEIGHT($hash->{die_height});
					$self->SLOT ($hash->{slot});
					$self->STEP_ID($hash->{step_id});
					$self->RESULT_DATETIME($hash->{result_datetime});
					$self->DB_LOCATION($hash->{db_location});
#					if($hash->{DIE_WIDTH} == 0 || $hash->{DIE_HEIGHT} == 0) {
#						WARN("DIE_WIDTH OR/AND V HAVE ZERO VALUE!!!");
#						return 0;
#					}
					return 1;
          
        } else {
              WARN ( "Bad.. Meta Not Found for Lot = " . $self->LOT ." in $lookuptable ");
               return 0 ;
        }
}

sub populateDefectIndexInfoForImageLoading {
    my $self = shift;
    my $hash ;
    my $lookuptable = "PP_DEFECT" ;
    #my @slotArray = shift;
    #my $slotCount;
    #my $counter = 0;
     
   
    unless ( defined( $self->IMAGE_FILENAME ) ) {
       ERROR ("Lot to lookup RefDB is null ");
       return 0 ;
    }
    	#INFO("INSIDE populateDefectIndexInfoForImageLoading");
    	INFO("IMAGE FILE>>$self->{IMAGE_FILENAME}");
   
      	$hash = getRefdb->getDefectImageData ( $self->IMAGE_FILENAME );
     
        if ( defined($hash ) and %$hash) {
        	INFO ( "Good. Defect Image Info Found for Image = " . $self->IMAGE_FILENAME ." in $lookuptable ");
          #INFO("$hash->{STEP_ID}");  
#        foreach my $key (keys %$hash) {
#        	INFO("$key=>$hash->{$key}");
#        }   
          #$self->LOT($hash->{LOT});
					$self->DEFECT_INDEX($hash->{defect_index});
					$self->IMAGE_INDEX($hash->{image_index});	
					$self->DB_LOCATION($hash->{db_location});
					$self->SLOT ($hash->{slot});
					$self->WAFER ($hash->{wafer});
					$self->STEP_ID($hash->{step_id});
					$self->RESULT_DATETIME($hash->{result_datetime});
					$self->LOT($hash->{lot});
#					if($hash->{DIE_WIDTH} == 0 || $hash->{DIE_HEIGHT} == 0) {
#						WARN("DIE_WIDTH OR/AND V HAVE ZERO VALUE!!!");
#						return 0;
#					}
					return 1;
          
        } else {
              WARN ( "Bad.. Image Info Not Found for Image = " . $self->IMAGE_FILENAME ." in $lookuptable ");
               return 0 ;
        }
}




1;

__END__;