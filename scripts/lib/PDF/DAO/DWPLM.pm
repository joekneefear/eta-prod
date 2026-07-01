package PDF::DAO::DWPLM;
use strict;
use File::Basename qw/basename/;
use PDF::Log;
use PDF::DpLoad;
use base qw/DBIx::Simple/;
our $VERSION = "1.0";

sub connect {
    my ( $class, @args ) = @_;
    return $class->SUPER::connect(@args);
}

sub getPlmPartIdMetaData {
	my $self = shift;
	my $product = shift;
	
	my $sql = q(select TECH.FAB_SITE_ID as fab,
	ENG.ENG_WFR_TECH_TYPE_ID as technology,
	PART.PART_ID as product,
	PART.MFG_PART_ID as mfg_part_id,
	PART.WFR_FAB_MASK_CONFIG_ID as fab_mask,
	TECH.WFR_TECH_IMPL_ID as process,
	PART.PAL4_CD as pti4,
	AREA.MFG_AREA_DESC as facility
	FROM BIWHUB.PDM_PART_MV PART
	LEFT JOIN BIWHUB.PDM_WAFER_TECH_IMPL_MV TECH ON PART.WFR_TECH_IMPL_1_ID = TECH.WFR_TECH_IMPL_ID
	LEFT JOIN BIWHUB.PDM_WAFER_TECH_VARIANT_MV VAR on TECH.WFR_TECH_VARIANT_ID = VAR.WFR_TECH_VARIANT_ID
	LEFT JOIN BIWHUB.PDM_ENG_WAFER_TECH_TYPE_MV ENG on VAR.WFR_TECH_TYPE_ID = ENG.ENG_WFR_TECH_TYPE_ID
	LEFT JOIN BIWHUB.PDM_ENG_WAFER_TECH_FAM_MV FAM on ENG.ENG_WFR_TECH_FAM_ID = FAM.ENG_WFR_TECH_FAM_ID
	LEFT JOIN MFG_AREA AREA on TECH.FAB_SITE_ID = AREA.MFG_AREA_CD
	WHERE PART.PART_ID = ?
	);

	my $hash = $self->query( $sql,$product )->hash;
	return $hash;
} 

sub getMaskSet {
	my $self = shift;
	my $product_code = shift;

	my $sql = q(select WFR_FAB_MASK_CONFIG_ID from BIWHUB.PDM_PART_MV where PART_ID = ? );

	my $hash = $self->query( $sql, $product_code )->hash;
	return $hash;
}

sub getFab {
	my $self = shift;
	my $lotfab = shift;

	my $sql = q(select mfg_area_cd,mfg_area_desc from mfg_area where mfg_area_cd = ? );
	
	my $hash = $self->query( $sql, $lotfab )->hash;
	
	return $hash;
}

1;
