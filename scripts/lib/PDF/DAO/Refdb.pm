# SVN $Id: Refdb.pm 2271 2018-01-11 00:34:35Z dpower $
# 2015-May-08	jgarcia	: added getProductInfobyLotidFromFileOnPP_LOTandPP_PROD subroutine.
# 2015-May-08	jgarcia : added getProductbyLotidFromPP_LOT subroutine.
# 2015-May-08	jgarcia : added getProductInfoByProductInPP_PROD subroutine
# 2015-Jul-22	jgarcia : added getProductbyLotidFromPP_FINALLOT subroutine
# 2016-Jan-05	sboothby: Get fab for PP_LOT only.
# 2016-Jul-28	jgarcia : added checkAndInsertDefect subroutine for defect data registration to REFDB.PP_DEFECT.
# 2016-Jul-28	jgarcia : added checkDefectIfRegistered subroutine to query REFDB.PP_DEFECT based on defect lot, slot and result_datetime.
# 2016-Jul-28	jgarcia : added getMetaDataForDefect subroutine to get diex_width and die_height and other info based on Product
#			from the PP_LOT which will be joined to PP_PROD by PRODUCT.
#			diex_width and die_height will be used for splitting die if necessary.
# 2016-Jul-28	jgarcia : added getDefectData subroutine to get defect info used as Meta Data for mini-klarf/TRF file.
# 2016-Sep-14 	eric    : get device, process/package info from pp_prod for reliability loading.
# 2016-Oct-06 	sboothby: If lot class lookup returns NULL, assume ENG.
# 2016-Nov-08 	jgarcia : added support for defect registration with mulitple slots and wafers - changes are on defect related methods.
# 2016-Nov-10 	jgarcia : added $defecIndex param for checkDefectIfRegistered2 sub routine to fix issue of duplicate registration of defect.
# 31-Mar-2017 	eric	: create sub getSrcLot
# 04-Dec-2017 	eric	: added sub getMetaDataRmsLot
# 18-Mar-2021   jgarcia : modified getMetaData sub routine to include FAB in the FAB DESC.
# 14-May-2022   jgarcia : added getLEHSmetadata subroutine.
#
package PDF::DAO::Refdb;
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

#
sub getMetaString {
    my $self = shift;
    my $lot  = shift;
    my $hash = $self->getMetaData($lot);
    my $meta = "<BOM>\n";
    foreach my $key ( sort keys(%$hash) ) {
        $meta .= uc($key) . "=" . repNA( $hash->{$key} ) . "\n";
        INFO( uc($key) . "=" . repNA( $hash->{$key} ) );
    }
    $meta .= "<EOM>\n";
    return $meta;
}

sub getSourceLot {
    my $self = shift;
    my $lot  = shift;
    my $lot_org    = $lot;
    my $sql_srclot = q(
   select * from PP_LOT L
   left join PP_LOTCLASS C on L.lot_owner = C.lot_owner
   where L.LOT = ?
  );
    my $lot_hash;
    my $srclot;
    my $lot_hash   = $self->query( $sql_srclot, $lot )->hash;
    my $parent_lot = $lot_hash->{parent_lot};
    my $source_lot = $lot_hash->{source_lot};

    unless (%$lot_hash) {
        WARN("getSourceLot: lot=$lot not found in PP_LOT");
        return $lot_hash;
    }
    if ($source_lot ne '') {
      return $lot_hash;
    }

    my $loop = 1;
    while ( $loop < 5 ) {
	INFO(
	    "Loop:$loop, LOT =$lot, PARENT_LOT = $parent_lot, SOURCE_LOT = $source_lot"
	);
	if ( $source_lot ne '' or $lot eq $parent_lot or $parent_lot eq '' ) {
	    INFO( "Stop searching and update SOURCE_LOT");
	    $lot_hash->{source_lot} = $lot;
	    $self->update( 'PP_LOT', { SOURCE_LOT => $lot }, { LOT => $lot_org });
	    last;
	}
	else {
	    $lot = $parent_lot;
	    my $parent_hash = $self->query( $sql_srclot, $lot )->hash;
	    $parent_lot = $parent_hash->{parent_lot};
	    $source_lot = $parent_hash->{source_lot};
	}
	$loop++;
    }
    return $lot_hash;
}

sub getMetaData {
    my $self   = shift;
    my $lot    = shift;
    my $srclot = $self->getSourceLot($lot)->{SOURCE_LOT};
=pod
    my $sql    = q(select L.*, P.*, C.*
    from PP_LOT L
    left join PP_PROD P on P.PRODUCT = L.PRODUCT
    left join PP_LOTCLASS C on L.LOT_OWNER = C.LOT_OWNER
    where L.LOT = ?
  );
=cut

my $sql    = q(select  L.LOT, L.PRODUCT, L.SOURCE_LOT, P.PRODUCT as PRODUCT_PROD, P.PROCESS, P.FAB||':'||P.FAB_DESC AS FAB_DESC, P.FAMILY, P.PACKAGE
, COALESCE(C.LOT_CLASS, 'ENG') AS LOT_CLASS
    from PP_LOT L
    left join PP_PROD P on P.PRODUCT = L.PRODUCT
    left join PP_LOTCLASS C on L.LOT_OWNER = C.LOT_OWNER
    where L.LOT = ?
   );

    my $hash = $self->query( $sql, $lot )->hash;
    return $hash;
}

sub getMetaDataFinalLot {
    my $self = shift;
    my $lot  = shift;

 my $sql = "";

=pod
   $sql  = q(select L.*, P.*, C.*
    from PP_FINALLOT L
    left join PP_PROD P on P.PRODUCT = L.PRODUCT
    left join PP_LOTCLASS C on L.LOT_OWNER = C.LOT_OWNER
    where L.LOT = ?
  );
=cut

   $sql  = q(select L.LOT, L.LOT AS SOURCE_LOT, L.PRODUCT, L.DATE_CODE, P.PRODUCT as PRODUCT_PROD, P.PROCESS, '' as FAB_DESC, P.FAMILY, P.PACKAGE, COALESCE(C.LOT_CLASS, 'ENG') AS LOT_CLASS
    from PP_FINALLOT L
    left join PP_PROD P on P.PRODUCT = L.PRODUCT
    left join PP_LOTCLASS C on L.LOT_OWNER = C.LOT_OWNER
    where L.LOT = ?
  );

    my $hash = $self->query( $sql, $lot )->hash;
    return $hash;
}

sub getMetaDataRelLot {
    my $self = shift;
    my $lot  = shift;

 my $sql = "";

=pod
   $sql  = q(select SUBSTR(qp.FILE_NUMBER,2,8) || p.PRODUCT_LABEL || s.SUBGROUP as lot
           , p.product_id, s.assembly_lot_num, s.FAB_LOT_NUM
   FROM IREL.QUAL_PLAN qp
   JOIN irel.qp_product p on p.qp_id = qp.qp_id
   JOIN IREL.QP_SUBGROUP s on qp.qp_id = s.qp_id and p.product_label = s.product_label
   WHERE SUBSTR(qp.FILE_NUMBER,2,8) || p.PRODUCT_LABEL || s.SUBGROUP =
  );
=cut

   $sql  = q(select SUBSTR(qp.FILE_NUMBER,2,8) || p.PRODUCT_LABEL || s.SUBGROUP as lot
           , p.product_id, s.assembly_lot_num, s.FAB_LOT_NUM
   FROM IREL.QUAL_PLAN qp
   JOIN irel.qp_product p on p.qp_id = qp.qp_id
   JOIN IREL.QP_SUBGROUP s on qp.qp_id = s.qp_id and p.product_label = s.product_label
   WHERE SUBSTR(qp.FILE_NUMBER,2,8) || p.PRODUCT_LABEL || s.SUBGROUP =
  );
  $sql = $sql . "'" . $lot . "'";
   # This Perl uses the Oracle 12 client which can't access the iRel Oracle 9i database directly.
   # Need to call a special command-line script to execute the SQL and return the needed info.
#    my $hash = $self->query( $sql, $lot )->hash;
    my $sql_file = "/tmp/rel_lot_lookup.$$.sql";
    open( my $fh, ">", $sql_file ) or die "Failed to create temp file for connect to rel DB\n";
    print $fh $sql."\n";
    close $fh;

    my $cmd = $ENV{'DPEXTSCRIPT'}."/rel_lookup.csh " . $sql_file . " |";
    #my $cmd = $ENV{'DPWORK'}."/sboothby/DPHOME/ext_script"."/rel_lookup.csh " . $sql_file . " |";
    open( RES, $cmd) || die "Failed to connect to rel DB\n";
    my $i = 0;
    #my %hash = ();
    my $hash1 = {};
    my $hash2 = {};
    my $hash3 = {};
    my @colnames;
    my $line = undef;
    while (defined($line=<RES>) )
    {
       # Parse the output of rel_lookup.csh
       # First line is column header.
       if ( $i == 0 )
       {
          @colnames = split(/\|/,$line);
       }
       else
       {
	  my $c = 0;
          my @values = split(/\|/,$line);
          foreach my $col (@colnames)
	  {
	     $col =~ s/\s+$//;
	     my $colval = $values[$c];
	     $colval =~ s/\s+$//;
	     $hash1->{$col} = $colval;
	     $c++;
	  }
       }
       $i++;
    }
    close RES;

    unlink $sql_file;

    my $irel_product = $hash1->{PRODUCT_ID};
    my $sql2 = q(select * from PP_PROD where PRODUCT = ?);
    $hash2 = $self->query($sql2, $irel_product)->hash;

    #merge hashes
    if ( defined $hash2) {
    	$hash3 = {%$hash1, %$hash2};
    	return $hash3;
    }
    else {
	return $hash1;
    }
}

sub getMetaDataRmsLot {
    my $self = shift;
    my $lot = shift;
    my $ltyp = $lot;

    # rms lots is 6 characters long + lot type
    $lot = substr $lot, 0, 6;  #rms lot
    $ltyp = substr $ltyp, 6;   #lot type

    INFO ("RMS Lot = $lot Lot type = $ltyp");

    my $sql = "";

    my $hash = {};

    $sql = q(select concat(R.FLD_REQUEST_ID,LT.FLD_LOT_TYPE_NAME) as lot, R.FLD_DEVICE, L.FLD_ASSEMBLY_LOT, LT.FLD_LOT_TYPE_NAME
        from RMS.TBL_REQUEST R, RMS.TBL_LOT L, RMS.LTBL_LOT_TYPE LT
        where L.FLD_RID = R.FLD_RID
	and L.FLD_LOT_TYPE_ID = LT.FLD_LOT_TYPE_ID
        and R.FLD_REQUEST_ID = ?
        and LT.FLD_LOT_TYPE_NAME = ?);

     $hash = $self->query($sql, $lot, $ltyp)->hash;
     return  $hash;

}

sub getLotRecordCount {
    my $self    = shift;
    my $lot = shift;
    my $lookuptable = shift;
    INFO("Lookup $lookuptable by Lot=$lot");
    my $keyValues = {
	lot => $lot
	};
    my $count = $self->select("$lookuptable", 'count(*)', $keyValues)->list;
    return $count;
}

## Limit

sub isNewLimit{
    my $self = shift;
    my $limit = shift;
    my $keyValues = {
	program => $limit->{PROGRAM},
	revision => $limit->{REVISION},
	};
    my ($count) = $self->select('PP_LIMITS','count(*)',$keyValues)->list;
    return ($count == 0) ;
}

# Check and insert limit using passed in Limits object.
# Return either the passed in limits object (if it is not in the database) or a limits object matching the data already in the database.
sub checkAndInsertLimitGetInfo {
    my $self       = shift;
    my $obj = shift;
    my $keyValues = {
	program => $obj->{PROGRAM},
	revision => $obj->{REVISION},
	};

    my ($db_start_time, $db_pp_script, $db_limit_file, $db_input_file) = $self->select('PP_LIMITS','START_TIME, PP_SCRIPT, LIMIT_FILE, INPUT_FILE',$keyValues)->list;
    if (defined($db_start_time) && length($db_start_time) > 0) {
        INFO("Limit PROGRAM=".$keyValues->{program}.",REVISION=".$keyValues->{revision}." is already in PP_LIMITS (start_time=\"$db_start_time\").");
        my $db_limit = PDF::DpData::Limit->new();
        $db_limit->PROGRAM($obj->{PROGRAM});
	$db_limit->REVISION($obj->{REVISION});
	$db_limit->DATE($db_start_time);
	$db_limit->limit_file($db_limit_file);
	$db_limit->input_file($db_input_file);
	return (0, $db_limit);
    }
    my $date = formatDateToYYYYMMDD($obj->{DATE});
    my $values = {
          program => $obj->{PROGRAM},
	  revision => $obj->{REVISION},
	  start_time => \["to_date(?,'YYYY/MM/DD HH24:MI:SS')",$date],
	  pp_script => (basename $0),
          limit_file => $obj->{limit_file},
	  input_file => $obj->{input_file},
    };
    $self->insert('PP_LIMITS',$values);
    return (1, $obj);
}

sub checkAndInsertLimit {
    my $self       = shift;
    my $obj = shift;

    my ( $rc, $limit) = $self->checkAndInsertLimitGetInfo($obj);
    return $rc;
}
###Defect
#sub checkAndInsertDefect {
#    my $self       = shift;
#    my $obj = shift;
#    my $keyValues = {
#			LOT => $obj->{LOT},
#			SLOT => $obj->{SLOT},
#			STEP_ID => $obj->{STEP_ID},
#			RESULT_DATETIME => $obj->{RESULT_DATETIME}
#		};
#
#    my $count = $self->checkDefectIfRegistered($obj->{LOT}, $obj->{SLOT}, $obj->{RESULT_DATETIME});#$self->select('PP_DEFECT','count(*)',$keyValues)->list;
#    if( $count > 0 ) {
#        INFO("Defect = ".$keyValues->{LOT}. ", SLOT = ". $keyValues->{SLOT} .", STEP_ID = ".$keyValues->{STEP_ID}.", RESULT_DATETIME = ". $keyValues->{RESULT_DATETIME}. " is already in PP_DEFECT.");
#        INFO("DEFECT is already REGISTERED to REFDB.PP_DEFECT");
#        return 0;
#    } else {
#    	my $date = formatDateToYYYYMMDD($obj->{DATE});
#    	my $values = {
#			  LOT => $obj->{LOT},
#			  SLOT => $obj->{SLOT},
#			  RESULT_DATETIME => \["to_date(?,'YYYY/MM/DD HH24:MI:SS')",$obj->{RESULT_DATETIME}],
#			  STEP_ID => $obj->{STEP_ID},
#			  LOCATION => $obj->{LOCATION},
#			  PRODUCT => $obj->{PRODUCT},
#			  FAMILY => $obj->{FAMILY},
#			  PROCESS => $obj->{PROCESS},
#			  INPUTFILE => $obj->{inputFile},
#			  FAB => $obj->{FAB},
#			  PROCESS => $obj->{PROCESS},
#			  DIE_WIDTH => $obj->{DIE_WIDTH},
#			  DIE_HEIGHT => $obj->{DIE_HEIGHT},
#			  DB_LOCATION => $obj->{DB_LOCATION},
#			  INSERT_TIME => \["to_date(?,'YYYY/MM/DD HH24:MI:SS')",$date],
#
#		  };
#        $self->insert('PP_DEFECT',$values);
#        INFO("DEFECT will be REGISTERED to REFDB.PP_DEFECT");
#        return 1;
#
## 	my $hash = {%$defect};
##    $self->insert( 'PP_DEFECT', $hash ) or do {
##        ERROR( "Failed to insert into PP_WMAP: " . $self->error );
##        return 0;
##    };
##       return 1;
#    }
#}

sub checkAndInsertDefect {
    my $self       = shift;
    my $obj = shift;
    my $slot = shift;
    my $wafer = shift;
    my $count;


    	my $keyValues = {
				LOT => $obj->{LOT},
				SLOT => $slot,
				WAFER => $wafer,
				STEP_ID => $obj->{STEP_ID},
				RESULT_DATETIME => $obj->{RESULT_DATETIME}
			};
			$count = $self->checkDefectIfRegistered($obj->{LOT}, $slot, $wafer, $obj->{RESULT_DATETIME});#$self->select('PP_DEFECT','count(*)',$keyValues)->list;
			 if( $count > 0 ) {
        INFO("Defect = ".$keyValues->{LOT}. ", SLOT = ". $keyValues->{SLOT} .", STEP_ID = ".$keyValues->{STEP_ID}.", WAFER = ".$keyValues->{WAFER}.", RESULT_DATETIME = ". $keyValues->{RESULT_DATETIME}. " is already in PP_DEFECT.");
        INFO("DEFECT is already REGISTERED to REFDB.PP_DEFECT");

        	return 0;

    } else {
    	my $date = formatDateToYYYYMMDD($obj->{DATE});
    	my $values = {
			  LOT => $obj->{LOT},
			  SLOT => $slot,
			  RESULT_DATETIME => \["to_date(?,'YYYY/MM/DD HH24:MI:SS')",$obj->{RESULT_DATETIME}],
			  STEP_ID => $obj->{STEP_ID},
			  LOCATION => $obj->{LOCATION},
			  PRODUCT => $obj->{PRODUCT},
			  FAMILY => $obj->{FAMILY},
			  PROCESS => $obj->{PROCESS},
			  INPUTFILE => $obj->{inputFile},
			  FAB => $obj->{FAB},
			  PROCESS => $obj->{PROCESS},
			  DIE_WIDTH => $obj->{DIE_WIDTH},
			  DIE_HEIGHT => $obj->{DIE_HEIGHT},
			  DB_LOCATION => $obj->{DB_LOCATION},
			  INSERT_TIME => \["to_date(?,'YYYY/MM/DD HH24:MI:SS')",$date],
			  WAFER => $wafer,
			  PROGRAM => $obj->{PROGRAM},

		  };
        $self->insert('PP_DEFECT',$values);
        INFO("DEFECT will be REGISTERED to REFDB.PP_DEFECT");

        	return 1;

    }





# 	my $hash = {%$defect};
#    $self->insert( 'PP_DEFECT', $hash ) or do {
#        ERROR( "Failed to insert into PP_WMAP: " . $self->error );
#        return 0;
#    };
#       return 1;


}

sub checkAndInsertDefect2 {
    my $self       = shift;
    my $obj = shift;
    my $slot = shift;
    my $wafer = shift;
    my $imageFile = shift;
    my $defectIndex = shift;
    my $imageIndex = shift;

    #my $count;

    $imageFile = uc($imageFile);
    $imageIndex = $imageIndex + 0;
    $defectIndex = $defectIndex + 0;


    	my $keyValues = {
				LOT => $obj->{LOT},
				SLOT => $slot,
				WAFER => $wafer,
				STEP_ID => $obj->{STEP_ID},
				RESULT_DATETIME => $obj->{RESULT_DATETIME},
				IMAGE_FILE => $imageFile
			};
			my $count = $self->checkDefectIfRegistered2($obj->{LOT}, $slot, , $wafer, $obj->{RESULT_DATETIME}, $imageFile, $defectIndex);#$self->select('PP_DEFECT','count(*)',$keyValues)->list;
			 if( $count > 0 ) {
        INFO("Defect = ".$keyValues->{LOT}. ", SLOT = ". $keyValues->{SLOT} .", STEP_ID = ".$keyValues->{STEP_ID}.", RESULT_DATETIME = ". $keyValues->{RESULT_DATETIME}. ", IMAGE_FILE = ". $keyValues->{IMAGE_FILE}." is already in PP_DEFECT.");
        INFO("DEFECT is already REGISTERED to REFDB.PP_DEFECT");

        	return 0;

    } else {
    	my $date = formatDateToYYYYMMDD($obj->{DATE});
    	my $values = {
			  LOT => $obj->{LOT},
			  SLOT => $slot,
			  RESULT_DATETIME => \["to_date(?,'YYYY/MM/DD HH24:MI:SS')",$obj->{RESULT_DATETIME}],
			  STEP_ID => $obj->{STEP_ID},
			  LOCATION => $obj->{LOCATION},
			  PRODUCT => $obj->{PRODUCT},
			  FAMILY => $obj->{FAMILY},
			  PROCESS => $obj->{PROCESS},
			  INPUTFILE => $obj->{inputFile},
			  FAB => $obj->{FAB},
			  PROCESS => $obj->{PROCESS},
			  DIE_WIDTH => $obj->{DIE_WIDTH},
			  DIE_HEIGHT => $obj->{DIE_HEIGHT},
			  DB_LOCATION => $obj->{DB_LOCATION},
			  INSERT_TIME => \["to_date(?,'YYYY/MM/DD HH24:MI:SS')",$date],
			  WAFER => $wafer,
			  PROGRAM => $obj->{PROGRAM},
			  IMAGE_FILE => $imageFile,
			  IMAGE_INDEX => $imageIndex,
			  DEFECT_INDEX => $defectIndex

		  };
        $self->insert('PP_DEFECT',$values);
        INFO("DEFECT will be REGISTERED to REFDB.PP_DEFECT");

        	return 1;

    }





# 	my $hash = {%$defect};
#    $self->insert( 'PP_DEFECT', $hash ) or do {
#        ERROR( "Failed to insert into PP_WMAP: " . $self->error );
#        return 0;
#    };
#       return 1;


}

#sub isNewDefect{
#    my $self = shift;
#    my $defect = shift;
##    my $keyValues = {
##			LOT => $defect->{LOT},
##			SLOT => $defect->{SLOT},
##			RESULT_DATETIME => \["to_date(?,'YYYY/MM/DD HH24:MI:SS')",$defect->{RESULT_DATETIME}]
##		};
#		#my $date = \["to_date(?,'YYYY/MM/DD HH24:MI:SS')",$defect->{RESULT_DATETIME}];
#		#to_char(d.result_timestamp,'yyyy\/mm\/dd hh24:mi:ss') = '$resultDateTime'
#		my $sql = q(select count(*) from pp_defect where (LOT = '$defect->{LOT}' and SLOT = '$defect->{SLOT}' and to_char(RESULT_DATETIME,'yyyy\/mm\/dd hh24:mi:ss') = '$defect->{RESULT_DATETIME}'));
#		my $h = $self->query($sql)->list;
#    #my ($count) = $self->select('PP_DEFECT','count(*)',$keyValues)->list;
##    if ( defined($hash ) and %$hash) {
##    	return 1;
##    } else {
##    	return
##    }
#		#if(keys %$h > 0) {
#    #	return (1) ;
#    #} else {
#    #	return 0;
#    #}
#    if($h > 0) {
#    	return 1;
#    } else {
#    	return 0;
#    }
#}


#### WaferMap
sub getWMap {
    my $self       = shift;
    my $product    = repNA(shift);
	my $cfg_tester_type= repNA(shift);
	my $location   = repNA(shift);

	my $sql = q(
		select * from PP_WMAP
		where PRODUCT = ?
		and TESTER_TYPE = ?
		and LOCATION = ?
	);

	my $hash = $self->query($sql, $product, $cfg_tester_type, $location)->hash;

	return $hash;
}


sub getProduct {
    my $self    = shift;
    my $product = shift;
    INFO("Lookup PP_PROD by Product  = $product");
    my $sql = q(
   select * from PP_PROD
    where PRODUCT = ?
  );
    my $hash = $self->query( $sql, $product )->hash;
    return $hash;
}


sub getCompareSize {
    my $self    = shift;
    my $product = shift;

    INFO("Lookup die_width, die_height between pp_wmap and pp_prod by Product  = $product");

    my $sql = q(
    select sign(decode(wm_die_width, pd_die_width,decode(wm_die_height,pd_die_height,1,0),0) + decode(wm_die_width, pd_die_height,decode(wm_die_height,pd_die_width,1,0),0)) compared,
		   decode(wm_wf_size, pd_wf_size, 'match' , pd_wf_size) wf_size,
		   pd_die_width, pd_die_height, wm_die_width, wm_die_height
	from (
			SELECT wm.product,wm.wf_size wm_wf_size, wm.wf_units, wm.die_width, wm.die_height, pd.item_type, pd.die_units, pd.die_width, pd.die_height,
				   round( decode(die_units, 'MC', 1000, 'MM', 1, 'MLL', 39.37, 'MIL', 39.37, 'ML', 39.37, 'IN', 0.03937) * wm.die_width,0) wm_die_width,
				   round( decode(die_units, 'MC', 1000, 'MM', 1, 'MLL', 39.37, 'MIL', 39.37, 'ML', 39.37, 'IN', 0.03937) * wm.die_height,0) wm_die_height,
				   round(pd.die_width,0) pd_die_width,
				   round(pd.die_height,0) pd_die_height,
				   decode(pd.wf_units, 'IN', 25, 1)* pd.wf_size pd_wf_size
			from pp_wmap wm, pp_prod pd
			where wm.product = pd.product
			and wm.product = ?
	)
  );
    my $hash = $self->query( $sql, $product )->hash;
    return $hash;
}



sub insertWMap {
    my $self = shift;
    my $wmap = shift;
    INFO(     "insert into PP_WMAP PRODUCT = "
            . $wmap->product
            . ", TESTER_TYPE = "
            . $wmap->tester_type
			. ", LOCATION = "
			. $wmap->location);
    unless ( defined $wmap->product and defined $wmap->tester_type and defined $wmap->location) {
        dpExit( 1, "Product is empty in wmap" );
    }
    my $hash = {%$wmap};
    $self->insert( 'PP_WMAP', $hash ) or do {
        ERROR( "Failed to insert into PP_WMAP: " . $self->error );
        return 0;
    };
    # 13-Jul-2015 S. Boothby  Select row back out to get CFG_ID.
    my $new_wmap = $self->getWMap($wmap->product, $wmap->tester_type, $wmap->location);
    INFO("CFG_ID=".$new_wmap->{cfg_id});
    $wmap->{cfg_id} = $new_wmap->{cfg_id};

    return 1;
}


sub confirm_WMap{
	my $self = shift;
    my $wmap = shift;
	my $wf_size =shift;

    unless ( defined $wmap->product and defined $wmap->tester_type  and defined $wmap->location  ) {
        dpExit( 1, "Product or tester_type or location is empty in wmap" );
    }

    my $hash = {%$wmap};
	my $sql = "";

	# 07-Jul-15 SAB Don't auto-confirm any more, but do update wafer size if needed.
#	if( $wf_size eq "match")
#	{
#		INFO(     " update PP_WMAP "
#				. " set confirmed =1  "
#				. " WHERE PRODUCT = "
#				. $wmap->product
#				. " AND TESTER_TYPE = ". $wmap->tester_type
#				. " AND LOCATION = ". $wmap->location
#				);
#
#		$sql = q(
#		update PP_WMAP set confirmed =1, confirm_time = sysdate, comments = 'auto confirmed'
#		where product = ?
#		and tester_type = ?
#		and location = ?
#		);
#
#		$self->query( $sql, $wmap->product , $wmap->tester_type, $wmap->location) or do {
#			ERROR( "Failed to updatePP_WMAP: " . $self->error );
#			return 0;
#		};
#	}
	if ( $wf_size ne "match" )
	{
		INFO(     " update PP_WMAP "
#				. " set confirmed =1  "
				. " set wf_size = $wf_size  "
				. " WHERE PRODUCT = "
				. $wmap->product
				. " AND TESTER_TYPE = ". $wmap->tester_type
				. " AND LOCATION = ". $wmap->location

				);

		$sql = q(
		update PP_WMAP set comments = 'wfr size from pp_prod', wf_size = ?
		where product = ?
		and tester_type = ?
		and location = ?
		);

		$self->query( $sql, $wf_size, $wmap->product, $wmap->tester_type, $wmap->location ) or do {
			ERROR( "Failed to updatePP_WMAP: " . $self->error );
			return 0;
		};
	}

    return 1;
}

sub getProductInfobyLotidFromFileOnPP_LOTandPP_PROD {
	my $self = shift;
	my $lotidFromFile = shift;
	INFO("Lookup PP_LOT.LOT, PP_LOT.PRODUCT, PP_PROD.WAFER_SIZE, PP_PROD.WAFER_UNIT where PP_LOT.LOT = $lotidFromFile and PP_PROD.PRODUCT = PP_LOT.PRODUCT");
	my $sql = q(
	select PP_LOT.LOT, PP_PROD.PRODUCT, PP_PROD.WF_SIZE, PP_PROD.WF_UNITS from PP_LOT, PP_PROD
	where PP_LOT.LOT = ? and PP_PROD.PRODUCT = PP_LOT.PRODUCT
	);
	my $hash = $self->query( $sql, $lotidFromFile)->hash;
	return $hash;
}

sub getProductInfoByProductInPP_PROD {
    my $self    = shift;
    my $productFromPP_LOT = shift;
    INFO("Lookup PP_PROD by PRODUCT from PP_LOT or PP_FINALLOT  = $productFromPP_LOT");
    my $sql = q(
    select PP_PROD.PRODUCT, PP_PROD.WF_SIZE, PP_PROD.WF_UNITS, PP_PROD.DIE_WIDTH, PP_PROD.DIE_HEIGHT FROM PP_PROD
    where PRODUCT = ?
  );
    my $hash = $self->query( $sql, $productFromPP_LOT )->hash;
    return $hash;
}

sub getProductbyLotidFromPP_LOT {
	my $self = shift;
	my $lotidFromFile = shift;
	INFO("Lookup PRODUCT ON PP_LOT by LOT from File  = $lotidFromFile");
	my $sql = q(
    select PRODUCT from PP_LOT
    where PP_LOT.LOT = ?
  );
    my $hash = $self->query( $sql, $lotidFromFile )->hash;
    return $hash;
}

### added 05142022 jgarcia ###
sub getBKLEHSmetadata {
	my $self = shift;
	my $lotidFromFile = shift;
	#INFO("Lookup PRODUCT, SOURCELOT, PROCESS ON PP_LOT, PP_PROD by LOT from File  = $lotidFromFile");
	my $sql = q(
      select  L.LOT, coalesce(L.PRODUCT,'NA') as PRODUCT, coalesce(L.SOURCE_LOT,'NA') as SOURCE_LOT, coalesce(P.PROCESS,'NA') as PROCESS
      from PP_LOT L
      left join PP_PROD P on P.PRODUCT = L.PRODUCT
      where L.LOT = ?
  );
    my $hash = $self->query( $sql, $lotidFromFile )->hash;
    return $hash;
}

### added 07222015 jgarcia ###
sub getProductbyLotidFromPP_FINALLOT {
	my $self = shift;
	my $lotidFromFile = shift;
	INFO("Lookup PRODUCT ON PP_FINALLOT by LOT from File  = $lotidFromFile");
	my $sql = q(
    select PRODUCT from PP_FINALLOT
    where PP_FINALLOT.LOT = ?
  );
    my $hash = $self->query( $sql, $lotidFromFile )->hash;
    return $hash;
}


sub getMetaDataForDefect {
    my $self   = shift;
    my $lot    = shift;
    #my $srclot = $self->getSourceLot($lot)->{SOURCE_LOT};
=pod
    my $sql    = q(select L.*, P.*, C.*
    from PP_LOT L
    left join PP_PROD P on P.PRODUCT = L.PRODUCT
    left join PP_LOTCLASS C on L.LOT_OWNER = C.LOT_OWNER
    where L.LOT = ?
  );


    my $sql    = q(select  L.LOT, L.PRODUCT, L.SOURCE_LOT, P.PRODUCT as PRODUCT_PROD, P.PROCESS, P.FAB_DESC, P.FAMILY, P.PACKAGE, C.LOT_CLASS
    from PP_LOT L
    left join PP_PROD P on P.PRODUCT = L.PRODUCT
    left join PP_LOTCLASS C on L.LOT_OWNER = C.LOT_OWNER
    where L.LOT = ?
  );
=cut
  my $sql = q(select * from PP_PROD p, refdb.PP_LOT l where l.LOT = ? and p.PRODUCT(+) = l.PRODUCT);


    my $hash = $self->query( $sql, $lot )->hash;
   #INFO("DIEX=$hash->{DIE_WIDTH}"};
    return $hash;
}

sub checkDefectIfRegistered {
    my $self    = shift;
    my $lot     = shift;
    my $slot = shift;
    my $wafer = shift;
    my $resultDateTime = shift;
    #my $srclot = $self->getSourceLot($lot)->{SOURCE_LOT};
    #my $date = formatDateToYYYYMMDD($resultDateTime);

    #my $sql     = q( select * from PP_DEFECT d where d.LOT = ? and d.slot = ? and to_char(d.result_timestamp,'yyyy\/mm\/dd hh24:mi:ss') = ? );
    #my $sql    = q(select * from PP_DEFECT d where d.LOT = '$lot' and d.slot = '$slot' and d.result_timestamp = TO_DATE('$resultDateTime','yyyy\/mm\/dd hh24:mi:ss'));
    #my $sql    = q(select * from PP_DEFECT d where d.LOT = '$lot' and d.slot = '$slot' and d.result_timestamp,'yyyy\/mm\/dd hh24:mi:ss' = to_date('$resultDateTime','yyyy\/mm\/dd hh24:mi:ss'));
    my $sql = qq/ select count(*) from PP_DEFECT d where d.LOT = '$lot' and d.slot = '$slot' and d.wafer = '$wafer' and to_char(d.result_datetime,'yyyy\/mm\/dd hh24:mi:ss') = '$resultDateTime' /;
    #my $hash = $self->query( $sql, $lot, $slot, $resultDateTime )->hash;
    my ($count) = $self->query( $sql )->list;
    #INFO(">>>>$count<<<");
    return $count;
}

sub checkDefectIfRegistered2 {
    my $self    = shift;
    my $lot     = shift;
    my $slot = shift;
    my $wafer = shift;
    my $resultDateTime = shift;
    my $imageFile = shift;
    my $defectIndex = shift;
    #my $srclot = $self->getSourceLot($lot)->{SOURCE_LOT};
    #my $date = formatDateToYYYYMMDD($resultDateTime);

    #my $sql     = q( select * from PP_DEFECT d where d.LOT = ? and d.slot = ? and to_char(d.result_timestamp,'yyyy\/mm\/dd hh24:mi:ss') = ? );
    #my $sql    = q(select * from PP_DEFECT d where d.LOT = '$lot' and d.slot = '$slot' and d.result_timestamp = TO_DATE('$resultDateTime','yyyy\/mm\/dd hh24:mi:ss'));
    #my $sql    = q(select * from PP_DEFECT d where d.LOT = '$lot' and d.slot = '$slot' and d.result_timestamp,'yyyy\/mm\/dd hh24:mi:ss' = to_date('$resultDateTime','yyyy\/mm\/dd hh24:mi:ss'));
    my $sql = qq/ select count(*) from PP_DEFECT d where d.LOT = '$lot' and d.slot = '$slot' and d.wafer = '$wafer' and to_char(d.result_datetime,'yyyy\/mm\/dd hh24:mi:ss') = '$resultDateTime' and d.image_file = '$imageFile' and d.defect_index = '$defectIndex'/;
    #my $hash = $self->query( $sql, $lot, $slot, $resultDateTime )->hash;
    my ($count) = $self->query( $sql )->list;
    #INFO(">>>>$count<<<");
    return $count;
}

sub getDefectData {
    my $self    = shift;
    my $lot     = shift;
    my $slot = shift;
    #my $wafer  =shift;
    my $resultDateTime = shift;
    #my $srclot = $self->getSourceLot($lot)->{SOURCE_LOT};
    #my $date = formatDateToYYYYMMDD($resultDateTime);
		#\[ "to_date(?, 'YYYYMMDD HH24:MM:SS')", "$start 00:00:00" ]
    #my $sql     = q( select * from PP_DEFECT d where d.LOT = ? and d.slot = ? and to_char(d.result_timestamp,'yyyy\/mm\/dd hh24:mi:ss') = ? );
    #my $sql    = q(select * from PP_DEFECT d where d.LOT = '$lot' and d.slot = '$slot' and d.result_timestamp = TO_DATE('$resultDateTime','yyyy\/mm\/dd hh24:mi:ss'));
    #my $sql    = q(select * from PP_DEFECT d where d.LOT = '$lot' and d.slot = '$slot' and d.result_timestamp,'yyyy\/mm\/dd hh24:mi:ss' = to_date('[$resultDateTime','yyyy\/mm\/dd hh24:mi:ss'));
    my $sql = qq/ select d.lot, d.slot, d.wafer, to_char(d.result_datetime,'yyyy\/mm\/dd hh24:mi:ss'), d. step_id, d.location, d.product, d.family,
    							d.process, d.fab, d.die_width, d.die_height, d.db_location from PP_DEFECT d
    							where d.LOT = '$lot' and d.slot = '$slot' and to_char(d.result_datetime,'yyyy\/mm\/dd hh24:mi:ss') = '$resultDateTime'/;
    #my $hash = $self->query( $sql, $lot, $slot, $resultDateTime )->hash;
    my $hash = $self->query( $sql )->hash;
    return $hash;
}
sub getDefectImageData {
    my $self    = shift;
    my $imageFile     = shift;
    #my $slot = shift;
    #my $resultDateTime = shift;
    #my $srclot = $self->getSourceLot($lot)->{SOURCE_LOT};
    #my $date = formatDateToYYYYMMDD($resultDateTime);
		#\[ "to_date(?, 'YYYYMMDD HH24:MM:SS')", "$start 00:00:00" ]
    #my $sql     = q( select * from PP_DEFECT d where d.LOT = ? and d.slot = ? and to_char(d.result_timestamp,'yyyy\/mm\/dd hh24:mi:ss') = ? );
    #my $sql    = q(select * from PP_DEFECT d where d.LOT = '$lot' and d.slot = '$slot' and d.result_timestamp = TO_DATE('$resultDateTime','yyyy\/mm\/dd hh24:mi:ss'));
    #my $sql    = q(select * from PP_DEFECT d where d.LOT = '$lot' and d.slot = '$slot' and d.result_timestamp,'yyyy\/mm\/dd hh24:mi:ss' = to_date('[$resultDateTime','yyyy\/mm\/dd hh24:mi:ss'));
    my $sql = qq/ select d.defect_index, d.image_index, d.db_location, d.slot, d.wafer, d.step_id, to_char(d.result_datetime,'yyyy\/mm\/dd hh24:mi:ss'),
     							d.lot from PP_DEFECT d where d.IMAGE_FILE = '$imageFile'/;
    #my $hash = $self->query( $sql, $lot, $slot, $resultDateTime )->hash;
    my $hash = $self->query( $sql )->hash;
    return $hash;
}

sub getSrcLot {
	my $self   = shift;
    	my $lot    = shift;
	my $sql    = q(select LOT, SOURCE_LOT from PP_LOT where LOT = ?);

	my $hash = $self->query( $sql, $lot )->hash;
	return $hash;
}
##################

1;

__END__

=pod

=head1 NAME

PDF::DAO::Refdb - Data Access Object for REFDB schame

=head1 SYNPSIS

  use PDF::DAO;
  my $db = getRefdb;
  $db->method_defined_in_PDF::DAO::Refdb

=head1 METHODS

=head2 getSourceLot(lot)

=over 4

=item 1. Search PP_LOT table keyed by LOT.

=item 2. In the found row, if SOURCE_LOT is not null. return the row in hash

=item 3. elsif LOT=PARENT_LOT or PARENT_LOT is null, update PP_LOT set SOURCE_LOT = LOT, and return the row in hash.

=item 4. else Search PP_LOT table where LOT = Parent LOT in previous step. then repeat 2 and 3

=back

Repeat untill search to PP_LOT exceed 5 times.

=head2 getProduct($product)

search PP_PROD where product = $product.
Retrun as hash reference (key = lower case of column name)

=head2 getMetaData($lot)

search source lot by getSourceLot and join PP_PROD.
Retrun as hash reference (key = lower case of column name)

=head2 getMetaDataFinalLot($lot)

search PP_FINALLOT where lot = $lot.
Retrun as hash reference (key = lower case of column name)

=head2 checkAndInsertLimit($limit)

$limit must be L<PDF::DpData::Limit.pm>

=over 4

=item 1. Search PP_LIMITS where program = $limit->program and revision = $limit->revision

=item 2. If found, do nothing, B<return 0>

=item 3. if not found, insert into PP_LIMITS, and B<return 1>

=back

=head2 getWMap($product, $tester_type, $location)

Search PP_WMAP where product = $product and tester_type = $tester_type
Retrun as hash reference (key = lower case of column name)

=head2 insertWMap($wmap)

Insert into WMAP table

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

2015/03/28 kazukik: new creation
2015/07/22 jgarcia: added getProductbyLotidFromPP_FINALLOT subroutine

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut
