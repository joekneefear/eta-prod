package PDF::DpData::ONHeaderLong;
use strict;
use base qw/PDF::DpData::Base/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DAO;

sub list { qw/
ALTERNATE_LOT ALTERNATE_PRODUCT APPLICATION_BOARD AREA BANK_LOT CABLE_ID CREATION_DATE DATA_FILE_NAME 
DATE_CODE DUT_BOARD EBR_NUMBER END_TIME FAB FAMILY HANDLER LOAD_BOARD LOAD_BOARD_TYPE LOT LOT_TYPE 
MASKSET MEASURING_EQUIPMENT ONS_LOTCLASS OPERATOR PACKAGE PDS_FILE PDS_FILE_VERSION PERFORMANCE_BOARD 
PROBE_CARD PROBE_CARD_TYPE PROCESS PROCESSING_STEP PRODUCT PRODUCT_CODE PROGRAM PROGRAM_CLASS PTI4_PAL 
RECIPE RECIPE_REVISION RELEASE REVISION SCRIBE_ID SOURCE_LOT STAGE START_TIME SUBCON_LOT_ID 
SUBCON_PRODUCT TECHNOLOGY TEMPERATURE TESTER_HOSTNAME TESTER_SOFTWARE TESTER_SOFTWARE_VERSION 
TESTER_TYPE TEST_FACILITY TEST_FLOOR TEST_MODE VERSION
        /} 

my $attr = [
    qw/
        isFinalLot isRelLot ertUrl
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

sub populateMetaByProduct {
    my $self = shift;
    my $hash;
    unless ( defined( $self->PRODUCT ) ) {
        ERROR("Lot to lookup RefDB is null ");
        return 0;
    }
    $hash = getRefdb->getProduct( $self->PRODUCT );
    unless ( defined( $hash ) ) {
        WARN( "Bad.. Meta Not Found for Product = " . $self->PRODUCT );
        return 0;
    }
    if (%$hash) {
        INFO( "Good. Meta Found for Product = " . $self->PRODUCT );
        $self->FAMILY( $hash->{family} );
        $self->PROCESS( $hash->{process} );
        $self->PACKAGE( $hash->{package} );
	if ( !$self->isFinalLot and ($hash->{fab_desc} ne "" and $hash->{fab_desc} ne "N/A"))
	{
        	$self->FAB( $hash->{fab_desc} );
	}
        return 1;
    }
    else {
        WARN( "Bad.. Meta Not Found for Product = " . $self->PRODUCT );
        return 0;
    }
}

sub populateMeta {
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
    elsif ( $self->isRelLot ) {
        if ($self->LOT =~ /^20/) {
    		$lookuptable = "IREL";
		unless ( defined( $self->LOT ) ) {
			ERROR("Lot to lookup RefDB is null ");
			return 0;
		}
		$hash = getRefdb->getMetaDataRelLot( $self->LOT );
	}
	else {
		$lookuptable = "ONRMS";
		unless ( defined( $self->LOT ) ) {
			ERROR("Lot to lookup RefDB is null ");
			return 0;
		}
		my $hash1 = {};
		my $hash2 = {};
		$hash1 = getRmsdb->getMetaDataRmsLot( $self->LOT );
		$self->LOT( $hash1->{lot} );
		my $rms_product =  $hash1->{fld_device};
		$hash2 = getRefdb->getProduct($rms_product);

		#merge hashes
    		if ( defined $hash2) {
        		$hash = {%$hash1, %$hash2};
		} else {
			$hash = $hash1;
		}

	}
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
	if($hash->{product} ne "")
	{
		$self->PRODUCT( $hash->{product} );
	}
	elsif($hash->{PRODUCT_ID} ne "" )
	{
		$self->PRODUCT( $hash->{PRODUCT_ID} );
	}
	else{
		INFO(" no product in db so original should be ".$self->PRODUCT);
	}
        $self->PACKAGE( $hash->{package} );
	if ( $hash->{fab_desc} ne "" and $hash->{fab_desc} ne "N/A" )
	{
        	$self->FAB( $hash->{fab_desc} );
	}
        $self->LOT_CLASS( $hash->{lot_class} );
        $self->DATE_CODE( $hash->{date_code} );
	if ( $self->isRelLot ) {
		if ($self->LOT =~ /^20/ ) {   #irel
			$self->SOURCE_LOT( $hash->{ASSEMBLY_LOT_NUM} );
		} 
		else { #onrms
			$self->SOURCE_LOT( $hash->{fld_assembly_lot} );
		}
	}
	else {
        	$self->SOURCE_LOT( $hash->{source_lot} );
	}
		
	# if no product in PP_PROD, move iff to sandbox
	if ($hash->{product_prod} ne "" || $hash->{PRODUCT_ID} ne "" || $hash->{fld_device} ne "")
	{		
		return 1;
	}
	else
	{		
		WARN("Product not available from metadata..sending to sandbox.");
		return 0;
	}
    }
    else {
        WARN( "Bad.. Meta Not Found for Lot = " . $self->LOT ." in $lookuptable");
        return 0;
    }
}

sub copyDefectToHeader {
    my $self   = shift;
    my $defect = shift;
    #$self->VERSION( $defect->VERSION );
    $self->CREATION_DATE( $defect->DATE );
    $self->LOT( $defect->LOT );
    $self->PRODUCT( $defect->PRODUCT );
    $self->FAB( $defect->FAB );
    $self->PROCESS( $defect->PROCESS );
    $self->FAMILY( $defect->FAMILY );
    return 1;
}

sub populateSrcLot {
	my $self = shift;
	my $hash;
    	my $lookuptable = "PP_LOT";

	unless ( defined( $self->LOT ) ) {
            	ERROR("Lot to lookup RefDB is null ");
            	return 0;
        }
        $hash = getRefdb->getSrcLot( $self->LOT );

	if (defined($hash) and %$hash) {
        	INFO( "Good. Source Lot Found for Lot = " . $self->LOT ." in $lookuptable");
		$self->SOURCE_LOT( $hash->{source_lot} );
		return 1;
	}
	else {
		WARN( "Bad.. Source Lot Not Found for Lot = " . $self->LOT ." in $lookuptable");
        	return 0;		
	}
}

sub populatePlmMetaBySearchedLotPart {
        my $self = shift;
        my $hash;

        unless ( defined( $self->PRODUCT ) ) {
                ERROR("Product to lookup Agile DW is null ");
                return 0;
        }

        $hash = getDWPlm->getPlmPartIdMetaData( $self->PRODUCT );

        unless ( defined( $hash ) ) {
                WARN( "Bad.. Meta Not Found for Product = " . $self->PRODUCT );
                return 0;
        }

        if (%$hash) {
                INFO( "Good. Meta Found for Product = " . $self->PRODUCT );

                $self->FAB($hash->{fab});
                $self->PROCESS($hash->{process});
                $self->TECHNOLOGY($hash->{technology});
                $self->PRODUCT($hash->{product});
                $self->MASKSET($hash->{fab_mask});
                $self->MASKSET($hash->{maskset});
                #$self->PTI4($hash->{pti4});
                #$self->EQUIP6_ID($hash->{facility});
                $self->PTI4_PAL($hash->{pti4});
		$self->TEST_FACILITY($hash->{facility});

                return 1;
        }
        else {
                WARN( "Bad.. Meta Not Found for Product = " . $self->PRODUCT );
                return 0;
        }
}

sub populateMaskSetByWaferPart {
        my $self = shift;
        my $hash;

        unless ( defined( $self->PRODUCT_CODE) ) {
                ERROR("WaferPart to lookup DW is null ");
                return 0;
        }

        $hash = getDWPlm->getMaskSet( $self->PRODUCT_CODE ) ;

        unless ( defined( $hash ) ) {
                WARN( "Bad.. Maskset Not Found for WaferPart = " . $self->PRODUCT_CODE );
                return 1;
        }

        if (%$hash) {
                INFO( "Good. Maskset Found for WaferPart = ". $self->PRODUCT_CODE );
                $self->MASKSET( $hash->{wfr_fab_mask_config_id});
                return 0;
        }
        else {
                WARN( "Bad.. Maskset Not Found for WaferPart = " . $self->PRODUCT_CODE );
                return 0;
        }
}

sub populateFabByLotFab {
        my $self = shift;
        my $hash;

        unless ( defined( $self->FAB) ) {
                ERROR("LotFab to lookup DW is null ");
                return 0;
        }

        $hash = getDWPlm->getFab( $self->FAB );

        unless ( defined( $hash ) ) {
                WARN( "Bad.. Fab Not Found for LotFab = " . $self->FAB );
                return 1;
        }

        if (%$hash) {
                INFO( "Good..Fab Found for LotFab = ". $self->FAB );
                $self->FAB($hash->{mfg_area_cd}.":".$hash->{mfg_area_desc});
                return 0;
        }
        else {
                WARN( "Bad..Fab Not Found for LotFab = ". $self->FAB );
                return 0;
        }
}


1;

__END__;

=pod

=head1 NAME

PDF::DpData - Header object for lot level data type.
 WSort, BinMap, FinalTest, FinalSummary, LossData

=head1 SYNOPSIS

    # create header 
  use PDF::DpData
  my $header = PDF::DpData::HeaderLong->new;
  $header->VERSION($VERSION);
  $header->PROGRAM_CLASS(4);
  $header->PROGRAM($program."_SPEM");
  $header->REVISION();
  $header->PRODUCT($product);
  $header->EQUIP1_ID($tsyst.$sysid);
  $header->EQUIP2_ID();
  $header->EQUIP3_ID($probecd);
  $header->EQUIP4_ID($loadbd);
  $header->EQUIP5_ID();
  $header->EQUIP6_ID($cable);
  $header->CFG_TESTER_TYPE($cfg_tstr_typ);
  $header->LOT($lotid);
  $header->START_TIME($sdate);
  $header->END_TIME($edate);
  $header->OPERATOR();

    # get Meta data from database
  $header->populateMet
   
    # get String to output to IFF
  my $str  = "<HEADER>\n";
  my $str .=  $header->toString;
  my $str .=  "</HEADER>\n";

=head1 Attribute  -- target of toString
  
  VERSION 
  CREATION_DATE  -- YYYY/MM/DD HH24:MI:SS (Default=current datetime)
  PROGRAM_CLASS  -- program class number 
  PROGRAM        -- No prefix 
  RELEASE 
  REVISION 
  FAB
  TECHNOLOGY 
  FAMILY      
  PROCESS 
  PRODUCT
  PACKAGE 
  STEP 
  STEP_GRP1
  STEP_GRP2
  STEP_GRP3
  STAGE
  LOT 
  SOURCE_LOT   -- No surfix(S)
  LOT_CLASS    -- PROD or ENG
  DATE_CODE
  EQUIP1_ID    -- Tester (Type + ID)
  EQUIP2_ID    -- Prober
  EQUIP3_ID    -- ProbeCard
  EQUIP4_ID    -- LoadBoard
  EQUIP5_ID    -- Handler
  EQUIP6_ID    -- CableID
  CFG_TESTER_TYPE -- for lookup where to get the config data from
  INDEX1       -- DUTBoard
  INDEX2       -- PerformanceBoard
  OPERATOR 
  START_TIME   -- YYYY/MM/DD HH24:MI:SS 
  END_TIME     -- YYYY/MM/DD HH24:MI:SS
  DEVICE_COUNT -- for FinalTest Summary

=head1 Attribute

  isFinalLot     -- 1: yes, 0 or undef : no   

=head1 METHODS

=head2 toString

inherit from L<PDF::DpData::Base.pm/toString>

=head2 populateMeta()  

LOT attibute must be set before calling this method.

=over 4

=item isFinalLot = I<false>  (other than 1)

It accesss REFDB and get data from PP_PROD, PP_LOT and PP_LOTCLASS and populate to following attribute.
  FAMILY,PROCESS,PRODUCT,PACKAGE,FAB,LOT_CLASS,DATE_CODE,SOURCE_LOT

The SOURCE_LOT is found by PDF::DAO::Refdbget->SourceLot

=item isFinalLot = I<true>  ( == 1)
 
It accesss REFDB and get data from PP_PROD, PP_FINALLOT and PP_LOTCLASS and populate to following attribute.
  FAMILY,PROCESS,PRODUCT,PACKAGE,FAB,LOT_CLASSS,DATE_CODE
SOURCE_LOT will NOT be populated for FinalLot.

=back

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2014/05/21 edwardy: 1st version
 2015/03/10 kazukik: output IFF format
 2015/03/30 kazukik: refactor modules 
 2015/07/01 gilbert: added CFG_TESTER_TYPE
 2016/01/05 sboothby: Set fab

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

