package PDF::DpData::eCofAHeaderLong;
use strict;
use base qw/PDF::DpData::Base/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DAO;

sub list { qw/
	VERSION CREATION_DATE PROGRAM_CLASS PROGRAM RELEASE REVISION FAB TECHNOLOGY FAMILY PROCESS PRODUCT
	PACKAGE STEP STAGE LOT SOURCE_LOT LOT_CLASS DATE_CODE VENDOR_SITE PART_NUMBER SHIP_TO_LOC_CD 
	VENDOR_LOT_ID MFG_DATE DATA_FILE_NAME WAFER_SCRIBE_ID GLOBAL_WAFER_ID BOULE_ID WAFER_SLICE_POSITION
	SLOT START_TIME END_TIME SHIP_NUMBER RECIPE QTY SHIPPING_FROM_LOC_CD RAWSILICON_LOT_ID SPEC_NUMBER
	GRADE SURFACE_CONDITIONS DESCRIPTION METROLOGY_TOOL RAW_MATERIAL_NAME EXPIRATION_DATE VENDOR_PART_NUMBER
	MOTHER_LOT_NUMBER SUBSTRATE_LOT_ID SUBSTRATE_SITE_ID SAMPLE_SIZE
        /} 

my $attr = [
    qw/
        isFinalLot isRelLot
        /
];

__PACKAGE__->mk_accessors( list, @$attr );


sub new {
    my ($class, $args) = @_;
    foreach my $key (%$args){
      if ( $key =~ /TIME$|DATE$/ ) {
         my $value = formatDate($args->{$key}) ;
         $args->{$key} = $value;
      }
    }
    my $self= $class->SUPER::new($args );
    $self->CREATION_DATE(currentDate);
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


1;

__END__;


