package PDF::DpData::MetaData;
use strict;
use base qw/PDF::DpData::Base/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DAO;
use PDF::WS;
use Data::Dumper;

sub list { qw/
    PROGRAM_CLASS VERSION CREATION_DATE ALTERNATE_LOT ALTERNATE_PRODUCT AREA CABLE_ID DATA_FILE_NAME
    DATE_TIME_MASK DEFAULT_MAPPING_VERSION DEFAULT_MAPPING_DATE DUT_BOARD END_TIME FACILITY FAMILY
    HANDLER LOAD_BOARD LOAD_BOARD_TYPE LOT_TYPE FAB LOT MASK_SET MEASURING_EQUIPMENT ONS_LOT_CLASS
    OPERATOR PDS_FILE PROBE_CARD PROBE_CARD_TYPE PROGRAM PROCESS PROCESSING_STEP PRODUCT PRODUCT_CODE
    PTI_2 PTI_4_PAL RECIPE RECIPE_REVISION RESULT_TIME SCRIBE_ID SLOT SOURCE_LOT START_TIME STEP SUBCON_LOT
    SUBCON_PRODUCT TECHNOLOGY TEMPERATURE TESTER_HOST_NAME TESTER_ID TESTER_SOFTWARE TESTER_SOFTWARE_VERSION
    TESTER_TYPE TEST_FACILITY TEST_FLOOR TEST_MODE DATE_CODE WMC_CENTER_X WMC_CENTER_Y WMC_DIE_HEIGHT
    WMC_DIE_WIDTH WMC_FLAT_TYPE WMC_POSITIVE_X WMC_POSITIVE_Y WMC_RETICLE_COL_OFFSET WMC_RETICLE_COLS
    WMC_RETICLE_ROW_OFFSET WMC_RETICLE_ROWS WMC_WAFER_FLAT WMC_WAFER_SIZE WMC_WAFER_UNITS
/ }

my $attr = [ qw/ isFinalLot isRelLot ertUrl / ];

__PACKAGE__->mk_accessors( list, @$attr );

sub new {
    my ($class, $args) = @_;
    foreach my $key (%$args){
        if ( $key =~ /TIME$|DATE$/ ) {
            my $value = formatDate($args->{$key});
            $args->{$key} = $value;
        }
    }
    my $self = $class->SUPER::new($args);
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

sub populateMetadata {
    my $self = shift;
    my $hash;
    my $lookuptable = "PP_LOT";
    if ( $self->isFinalLot ) {
        $lookuptable = "PP_FINALLOT";
        unless ( defined( $self->LOT ) ) {
            ERROR("Lot to lookup RefDB is null ");
            return 0;
        }
        $hash = getRefdb->getMetaDataFinalLot( $self->LOT );
    }
    else {
        unless ( defined( $self->LOT ) ) {
            ERROR("Lot to lookup RefDB is null ");
            return 0;
        }
        $hash = getRefdb->getMetaData( $self->LOT );
    }
    if (defined($hash) and %$hash) {
        INFO( "Good. Meta Found for Lot = " . $self->LOT ." in $lookuptable");

        $self->FAMILY( $hash->{family} );
        $self->PROCESS( $hash->{process} );

        # if no product in pp_lot, need to use product from data file.
        if($hash->{product} ne "") {
            $self->PRODUCT( $hash->{product} );
        } elsif($hash->{PRODUCT_ID} ne "" ) {
            $self->PRODUCT( $hash->{PRODUCT_ID} );
        } else {
            INFO(" no product in db so original should be ".$self->PRODUCT);
        }

        $self->PACKAGE( $hash->{package} );

        if ( $hash->{fab_desc} ne "" and $hash->{fab_desc} ne "N/A" ){
            $self->FAB( $hash->{fab_desc} );
        }
        $self->ONS_LOT_CLASS( $hash->{lot_class} );
        $self->DATE_CODE( $hash->{date_code} );
        $self->SOURCE_LOT( formatSourceLot($hash->{source_lot}, $self->{LOT}) );

        # if no product in PP_PROD, move iff to sandbox
        if ($hash->{product_prod} ne "" || $hash->{PRODUCT_ID} ne "" || $hash->{fld_device} ne "") {
            return 1;
        } else {
            WARN("Product not available from metadata..sending to sandbox.");
            return 0;
        }
    }
    else {
        WARN( "Bad.. Meta Not Found for Lot = " . $self->LOT ." in $lookuptable");
        return 0;
    }
}

sub populateMetadataERT {
    my $self = shift;

    my $lot = $self->LOT;
    my $base_url = $self->ertUrl;

    unless (defined $lot && length $lot && defined $base_url && length $base_url) {
        WARN("LOT or ERT URL is not initialized");
        return 0;
    }

    my $url = $base_url . $lot;
    INFO("FINAL URL=$url");

    my $resp = eval { getFromERTWS($url) };
    if ($@) {
        WARN("ERT request failed: $@");
        return 0;
    }
    unless (defined $resp && ref($resp) eq 'HASH' && ref($resp->{onLot}) eq 'HASH' && ref($resp->{onProd}) eq 'HASH') {
        WARN("Invalid ERT response shape");
        return 0;
    }

    my $onLot  = $resp->{onLot};
    my $onProd = $resp->{onProd};

    # ensure the returned lot matches the requested lot if present
    if (defined $onLot->{lot} && length $onLot->{lot} && $onLot->{lot} ne $lot) {
        WARN("ERT response lot '$onLot->{lot}' does not match requested lot '$lot'");
        return 0;
    }

    # based on presence of usable data, not on any textual status
    my $has_lot     = defined($onLot->{lot}) && $onLot->{lot} ne '';
    my $has_product = (defined($onProd->{product}) && $onProd->{product} ne '')
                   || (defined($onLot->{product})  && $onLot->{product}  ne '');

    unless ($has_lot && $has_product) {
        my $msg = $onLot->{errorMessage} // $onProd->{errorMessage} // "metadata not found on REFDB.ON_LOT";
        INFO($msg);
        return 0;
    }

    INFO("Good. Meta Found for Lot = " . $self->LOT . " on REFDB.ON_LOT");
    $self->processDecodedJsonOnLotProd($resp);
    return 1;
}

sub processDecodedJsonOnLotProd {
    my $self = shift;
    my $decodedJSON = shift // {};
    my $onLot  = (ref($decodedJSON->{onLot})  eq 'HASH') ? $decodedJSON->{onLot}  : {};
    my $onProd = (ref($decodedJSON->{onProd}) eq 'HASH') ? $decodedJSON->{onProd} : {};

    # Core fields
    $self->FAB( repNA($onLot->{fab}) );
    $self->SOURCE_LOT( formatSourceLot($onLot->{sourceLot}, $self->{LOT}) );
    $self->FAMILY( repNA($onProd->{family}) );
    $self->LOT_TYPE( repNA($onLot->{lotType}) );
    $self->ONS_LOT_CLASS( repNA($onLot->{lotClass}) );
    $self->PTI_4_PAL( repNA($onProd->{pti4}) );
    $self->TECHNOLOGY( repNA($onProd->{technology}) );

    # Additional mappings available from the API payload
    $self->ALTERNATE_PRODUCT( repNA($onLot->{alternateProduct}) );
    $self->PRODUCT_CODE( repNA($onLot->{productCode}) );
    $self->MASK_SET( repNA($onProd->{maskSet}) );

    # Product fallback: prefer onProd.product, then onLot.product,
    # only if current PRODUCT is empty or marked as N/A
    my $existing = eval { $self->PRODUCT } // $self->{PRODUCT} // "";
    if (!defined $existing || $existing eq "" || $existing =~ /^N\/?A$/i) {
        my $candidate = $onProd->{product};
        $candidate = $onLot->{product} if (!defined $candidate || $candidate eq "");
        $self->PRODUCT( repNA($candidate) );
    }
}

1;

__END__;