# 12-May-2016 eric	: added rel lot conditions
# 28-Jul-2016 jgarcia 	: added copyDefectToHeader subroutine for copy Defect's common attribute to Header.
# 31-Mar-2017 eric	: create sub populateSroClot
# 04-Dec-2017 eric	: modified sub populateMeta to handle ONRMS lots
#
package PDF::DpData::HeaderLong;
use strict;
use base qw/PDF::DpData::Base/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DAO;
use PDF::WS;

sub list { qw/
        VERSION CREATION_DATE
        PROGRAM_CLASS PROGRAM RELEASE REVISION FAB TECHNOLOGY FAMILY PROCESS PRODUCT PACKAGE STEP STAGE
        STEP_GRP1 STEP_GRP2 STEP_GRP3
        LOT SOURCE_LOT LOT_CLASS DATE_CODE
        EQUIP1_ID EQUIP2_ID EQUIP3_ID EQUIP4_ID EQUIP5_ID EQUIP6_ID CFG_TESTER_TYPE
        INDEX1 INDEX2
        OPERATOR START_TIME END_TIME
        DEVICE_COUNT
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

sub checkLotMetadata {
    my $self = shift;
    my $customLot = shift // $self->LOT;
    my $customMessage = shift // "";
    my $count;
    my $lookuptable = "PP_LOT";
    if ( $self->isFinalLot ) {
        $lookuptable = "PP_FINALLOT";
        unless ( defined( $customLot ) ) {
            ERROR("Lot to lookup RefDB is null ");
            return 0;
        }		
        $count = getRefdb->getLotRecordCount( $customLot, $lookuptable );
    } else {
        unless ( defined( $customLot ) ) {
            ERROR("Lot to lookup RefDB is null ");
            return 0;
        }
        $count = getRefdb->getLotRecordCount( $customLot, $lookuptable );		
    }
    if ($count > 0) {
        INFO( ($customMessage ? "$customMessage, " : "") . "Good. match found for Lot=$customLot in $lookuptable");
        #  INFO("Metadata found for lot $customLot in $lookuptable table" . ($customMessage ? " - $customMessage" : ""));
        # INFO( "Good. Metadata Found for Lot=$self->{LOT} in $lookuptable");
        return 1;
    } else {
        INFO( ($customMessage ? "$customMessage, " : "") . "NO match found for Lot=$customLot in $lookuptable");
        # INFO("Metadata not found for lot $customLot in $lookuptable table" . ($customMessage ? " - $customMessage" : ""));
        # INFO( "Metadata not found for Lot=$self->{LOT} in $lookuptable");
        return 0;
    }

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
        if($self->{FAB} !~ /CZ4\:/i) {	
		    return 1;
        }
	}
	else
	{	
        if($self->{FAB} !~ /CZ4\:/i) {	
		    WARN("Product not available from metadata..sending to sandbox.");
		    return 0;
        }
	}
    }
    else {
        if($self->{FAB} !~ /CZ4\:/i) {
            WARN( "Bad.. Meta Not Found for Lot = " . $self->LOT ." in $lookuptable");
            return 0;
        }
    }
    if($self->{FAB} =~ /CZ4\:/i) {
        my $lot = $self->{LOT};
		my $url = $self->{ertUrl};
        $url = "${url}${lot}";
        INFO("FINAL URL=$url");
        if($url ne "" || $lot ne "") {
            my $decodedJSON = getFromERTWS($url);
            if($decodedJSON->{onLot}->{status} =~ /NO_DATA|ERROR/i) {
                INFO("metadata not found on ERT");
                return 0;
            } elsif($decodedJSON->{onLot}->{status} =~ /FOUND/i) {
                INFO( "Good. Meta Found for Lot = " . $self->LOT ." on  ERT");
                my $sl = $decodedJSON->{onLot}->{sourceLot};
                my $product = $decodedJSON->{onLot}->{product};
                $sl =~ s/\.\S$//g;
                #INFO("Source Lot=$sl");
                $self->SOURCE_LOT($sl);
                $self->PRODUCT($product);
                return 1;
            }
            #$self->SOURCE_LOT(formatSourceLot($decodedJSON->{onLot}->{sourceLot}, $self->{LOT}));
        } else {
            INFO("FAB is CZ4 url for ERT or Lotid are not provided, could use ERT and source lot maybe not correct!");
        }
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

