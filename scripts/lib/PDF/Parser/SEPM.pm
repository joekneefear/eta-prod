# SVN $Id: SEPM.pm 1913 2016-11-07 11:03:04Z dpower $
# 2015-May-08 >> jgarcia >> set end date and time to start date and time if end date and time is not available.
# 2015-May-08 >> jgarcia >> modified the map flat orientation, set LEFT to 90 and RIGHT to 270.
# 2015-May-08 >> jgarcia >> modified to generate default Bin Names if [BINNAME_INFO] section is not available in the file.
# 2015-May-13 >> jgarcia >> modified to get the correct PRODUCT in PP_LOT table by its LOTID 
# 2015-May-13 >> jgarcia >> modified to get WAFER_SIZE and WAFER_UNIT from PP_PROD table by the PRODUCT FROM PP_LOT 
#		 if not available use WAFER_SIZE and WAFER_UNIT from the file but load the map to sandbox database.
# 2015-May-20 >> jgarcia >> modified to make the descriptive bin names as one word, to avoid making it always a Passing bin.
# 2015-Jun-11 >> grace   >> set input_file  
# 2015-Jun-23 >> gilbert >> check first if there's PROBE ENDDATE and PROBE ENDTIME field before assigning header endtime.
# 2015-Jul-22 >> jgarcia >> passed in finallot when calling populateWaferSizeWaferUnitFromPP_PROD. to be able to distinguish which table to get the PRODUCT.
#                 either PP_LOT OR PP_FINALLOT, depending on the finallot args.
# 2015-Jul-22 >> sboothby >> In Bucheon (perhaps elsewhere too) the BINNAME_INFO section may not contain bin names for every bin.  Auto-create a bin when not found.
# 2015-Jul-23 >> jgarcia >> updated to use wafer size from the file if the wafer size on the PP_PROD has the value of ZERO.
# 2015-Aug-26 Gilbert - Uppercase the lot id.
# 2015-Sep-18 Gilbert - Enhanced the parsing of XY and BIN at [WAFERMAP] section, removed
#                       these characters [ and ] and added '$' as inked die same as '*'.
# 2016-Jan-13 Eric - remove comma in binname                     
# 2016-Feb-15 Gilbert - Parse the unprobed "#" binned die as passing bin number 900 and bin name "Unprobed"
# 2016-Mar-02 Gilbert - Exclude X/Y's from the <DATA> section of the iff that have bin 65534
# 2016-Nov-07 Eric - use POSIX package PDF::Parser::SEPM
#
#
package PDF::Parser::SEPM::Model;
use strict;
use POSIX qw(floor ceil);
use PDF::Log;
use base qw/PDF::DpData::Base Class::Accessor/;

sub item {qw/ lot_data wafer_data configuration plugin_sepi_data/}

sub sessionSummary {
    my $self       = shift;
    my $psd_exists = "N";
    my ( $psd_cluster, $psd_opdesc, $psd_map_src, $psd_pat, $psd_sess_type );
    if ( defined $self->plugin_sepi_data ) {
        $psd_exists    = 'Y';
        $psd_cluster   = $self->plugin_sepi_data->{CLUSTER};
        $psd_opdesc    = $self->plugin_sepi_data->{OPDESC};
        $psd_map_src   = $self->plugin_sepi_data->{MAP_SOURCE};
        $psd_pat       = $self->plugin_sepi_data->{PAT};
        $psd_sess_type = $self->plugin_sepi_data->{SESSION_TYPE};
    }
    my $sysid = $self->configuration->{SYSTEM_ID};
    my $session_sum;
    $session_sum = "AOI"
        if ( $sysid =~ /PMBUMP/ || $sysid =~ /BUMP/ || $sysid =~ /AOI/ );

    $session_sum = "MRG"
        if $psd_opdesc
        =~ /^MERGE$/i;    ## indicates a merge between the 2 most recent maps
    $session_sum = "CLU"
        if $psd_cluster =~ /^INCLUDED$/
        && $psd_map_src
        =~ /PROBER|TESTER/i;    ## indicates a cluster detection map
    $session_sum = "PRB"
        if $psd_cluster =~ /NOT\s+INCLUDED/
        && $psd_map_src =~ /PROBER|TESTER/i
        && $psd_pat =~ /ENABLED|DISABLED|TRUE|FALSE/i
        && $psd_sess_type =~ /FULL\s+PROBE/i;
    $session_sum = "PAT"
        if $psd_pat =~ /CALCULATED/
        && $psd_map_src
        =~ /PROBER|TESTER/i;    ## indicates a part average test map
    $session_sum = "SAM"
        if $psd_sess_type
        =~ /SAMPLE\s+PROBE/i;    ## indicates a sample probe map
    $session_sum = "VRT"
        if $psd_sess_type
        =~ /VIRTUAL\s+PROBE/i;    ## indicates a virtual probe map
    $session_sum = "SMT"
        if $psd_sess_type =~ /SMART\s+PROBE/i;  ## indicates a smart probe map
    $session_sum = "UNK"
        if $psd_sess_type
        =~ /UNKNOWN/i;    ## indicates the type is "UNKNOWN" in the file
    $session_sum = "NOS"
        if $psd_exists eq "N"
        && $session_sum ne
        "AOI";    ## indicates the [PLUG_SEPI_DATA] section does not exist
    $session_sum = "BLA"
        if $psd_exists eq "Y"
        && $psd_sess_type eq ""
        && $session_sum eq "";    ## indicates the type is blank in the file
    $session_sum = "XXX"
        if $psd_exists eq "Y"
        && $psd_sess_type ne ""
        && $session_sum eq "";    ## indicates the type is undecipherable

    INFO( "Session = " . $session_sum );
    INFO(     "sess_type="
            . $psd_sess_type
            . ", cluster="
            . $psd_cluster
            . ", OPDESC="
            . $psd_opdesc
            . ", MAP SOURCE="
            . $psd_map_src
            . ", PAT="
            . $psd_pat );
    return $session_sum;
}

__PACKAGE__->mk_accessors(item);

package PDF::Parser::SEPM;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use POSIX qw(floor ceil);
use File::Basename qw/basename/;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}

__PACKAGE__->mk_accessors(array);

sub readFile {
    my $self   = shift;
    my $infile = shift;
    my $finallot = shift;
    my $header = new_headerLong;
    $header->PROGRAM_CLASS(4);
    my $wmap  = new_wmap;
    my $model = new_model(
        {   header     => $header,
            wmap       => $wmap,
            misc       => {},
            dataSource => 'SEPM'
        }
    );
    my $wafer = new_wafer;
	$wmap->input_file($infile);
    $model->add( 'wafers', $wafer );
    my %waferHash;
    my %binHash;
    my $dieUnits;
    my $unprobed_cnt = 0;
    my $section;
    my $sep = PDF::Parser::SEPM::Model->new;
    my $item;
    my $convertToMilimeterFlag = "Y";
    my $multiplier = 25.4;
    my $noBinNameInfoFlag = "Y";
    
    $header->isFinalLot($finallot);
       
    open( INFILE, $infile );
	
    while (<INFILE>) {
        if (/^\[(.*)\]/) {
            $section = $1;
            $item    = lc($1);
            $item =~ s/ /_/g;
            if ( grep { $_ eq $item } $sep->item ) {
                $sep->set( $item, {} );
            }
            else {
                $item = undef;
            }
        }
        if ( defined $item ) {
            if (/([\w ]+)\t+(.+)/) {
                my ( $key, $value ) = ( trim($1), trim($2) );
                    
                $key =~ s/ /_/g;
                my $hash = $sep->get($item);
                unless ( exists $hash->{$key} ) {
                    $hash->{$key} = $value;
                }
            }
            next;
        }
        if ( $section eq "BINNAME_INFO" ) {
        	  $noBinNameInfoFlag = "N";
            if (/^BINNAME\[(\d+)\]\t(.*)\t(.*)/) {
            	$noBinNameInfoFlag = "N";
            	  #print "$3\n";
                my $binNum  = $1;
                # my $binName = sprintf( "%02d", $binNum );
                my $binName = "";
                
               #print "$2::\t$3::\n";
               my $secondMatch = $2;
               my $thirdMatch = $3;
                
                if($thirdMatch !~ /^Bin/i && $secondMatch =~ /^Bin/i) {
                	  #print"IF\tthirdMatch\n";                	
                	  my @dummy = split /\s+/, $thirdMatch;
                	  #print "DUMMY@dummy\n";
                	 	if($dummy[$#dummy] =~ /Bin/i) {
		                	my $dmp = pop(@dummy);
		                }
		                if($dummy[0] !~ /Bin/i) {
		                	$binName = join '_', @dummy;
		                }
		                else {
		                	$binName = join '', @dummy;
		                }
                }
                else {
                	  #print"ELSE\t$secondMatch\n";
                	  my @dummy = split /\s+/, $secondMatch;
                	  #print "DUMMY>>$dummy[0]\n";
		                if($dummy[$#dummy] =~ /Bin/i) {
		                	my $dmp = pop(@dummy);
		                }
		                if($dummy[0] !~ /Bin/i) {
		                	$binName = join '_', @dummy;
		                }
		                else {
		                	$binName = join '', @dummy;
		                }
                }

		$binName =~ s/\,/\_/;    #clean bin name
        
		my $bin     = new_bin(
                    {   number => $binNum,
                        name   => $binName
                    }
                );

                $wafer->add( 'bins', $bin );
                $binHash{$binNum} = $bin;
            }
        }
	if ( $section eq "BINNING" ) 
	{
		if (/^BIN\s+(\d+)\t(\d+)\t(\d)/) 
		{
			if($noBinNameInfoFlag eq "Y") 
			{
				my $binNum  = $1;
				my $binName = "Bin".$binNum;
				my $bin     = new_bin(
				{   number => $binNum,
				    name   => $binName
				}
				);

				$wafer->add( 'bins', $bin );
				$binHash{$binNum} = $bin;
			}
            	  
	                my $bin;
			# 22-Jul-2015 S. Boothby if $bin is undefined, it probably wasn't listed in BINNAME_INFO section.
			if (exists($binHash{$1}))
			{
				$bin = $binHash{$1};
			}
			else
			{
#				INFO("AUTO-GEN FOR BIN ".$1);
				my $binNum  = $1;
				my $binName = "Bin".$binNum;
				$bin = new_bin( {number=>$binNum, name=>$binName});
				$wafer->add( 'bins', $bin );
				$binHash{$binNum} = $bin;
			}
	                $bin->count($2);
	                $bin->PF( ( $3 ? 'P' : 'F' ) );
		}
        }
        if ( $section eq "WAFERMAP" ) {
		next if $_ !~/^X/;
	        my ($XY, $res, $Status) = split( /\s+/, $_);
                
                # Split on the 'X*Y' within the string.
                my ($x, $y) = split (/X*Y/, $XY);
                    $x =~ s/^X//;
                     $res =~ s/[\[\]]//g;
                if ( $res =~ /[A-Z]/ ) {
                    $res = ord($res) - 55;
                }
		# Exclude X/Y's if bin is 65534
		next if $res == 65534;

		if ( $res eq '#' ) {
		   $res=~ s/\#/900/g;
		   $unprobed_cnt++;
		}
                my $die = new_die(
                    {   x        => $x,
                        y        => $y,
                        soft_bin => $res,
			unprobed => $unprobed_cnt
                    }
                );
                if ( $res eq '*' || $res eq '$') {
                    $die->inked(1);
                }
                $wafer->add( 'dies', $die );
                my $xy = $x ."_". $y;
                $waferHash{$xy} = $die;
        }
        if ( $section eq "EXT WAFERMAP" ) {
            if (/X(\-?\d+)Y(\-?\d+)\s+(.+)\s+(.+)\s+(.+)\s+(.+)\s+(.+)\s+(.+)\s+(.+)/) {
                my $die = $waferHash{ $1 ."_". $2 };
                if ( defined $die ) {
                    $die->site($6);
                }
            }
        }
    }
    
             ### Unprobed "#" binned die
    	     my $bin = new_bin(
	         {   number => '900',
	             name   => 'Unprobed'
	         }
	     );
	    $bin->count($unprobed_cnt);
	    $bin->PF('P');
	    $wafer->add( 'bins', $bin );

    $header->LOT(uc( $sep->lot_data->{LOT} ));
	$header->OPERATOR( $sep->lot_data->{OPERATOR} );
	#$wmap->populateWaferSizeWaferUnitFromPP_PROD($header->LOT, $header->isFinalLot);
	$wmap->populateWaferSizeWaferUnitFromPP_PROD($header->LOT, $header->isFinalLot);
	$header->PRODUCT($wmap->{product});
	if($wmap->{product} eq "") {
	  	INFO("USED THE PRODUCT FROM THE FILE, NOT AVAILABLE IN PP_PROD");
    		$header->PRODUCT( $sep->lot_data->{PRODUCT} );
  	}
    $header->START_TIME(
        $sep->lot_data->{PROBE_DATE} . " " . $sep->lot_data->{PROBE_TIME} );
    ### USE PROBE_DATE AND PROBE_TIME IF NOT AVAILABLE PROBE_ENDDATE AND PROBE_ENDTIME ### 
    if ($sep->lot_data->{PROBE_ENDDATE} eq "") {
    	$sep->lot_data->{PROBE_ENDDATE} = $sep->lot_data->{PROBE_DATE};    	
    }
    ### USE PROBE_DATE AND PROBE_TIME IF NOT AVAILABLE PROBE_ENDDATE AND PROBE_ENDTIME ### 
    if ($sep->lot_data->{PROBE_ENDTIME} eq "") {
    	 $sep->lot_data->{PROBE_ENDTIME} = $sep->lot_data->{PROBE_TIME};    	
    }
    $header->END_TIME( 
        $sep->lot_data->{PROBE_ENDDATE} . " " . $sep->lot_data->{PROBE_ENDTIME} );

    $wafer->number( $sep->lot_data->{WAFER} + 0 );

    $header->EQUIP1_ID( $sep->configuration->{TEST_SYS} . " "
            . $sep->configuration->{SYSTEM_ID} );
    $header->PROGRAM( $sep->configuration->{PROGRAM} );
    $header->EQUIP3_ID( $sep->configuration->{PROBECARD} );
    $header->EQUIP4_ID( $sep->configuration->{LOADBOARD} );
    $header->EQUIP6_ID( $sep->configuration->{CABLE} );
    foreach  my $item ($header->list) {
      if ($header->{$item} =~ /Undefined|<None>/) {
        $header->set($item,''); 
      }
    }

    $wmap->die_width( $sep->wafer_data->{XSIZE} );
    $wmap->die_height( $sep->wafer_data->{YSIZE} );
    my %flatDir = (
        0   => 'B',
        90  => 'L', ##ORIG R
        180 => 'T',
        270 => 'R', ##ORIG L
    );
    $wmap->flat( $flatDir{ $sep->wafer_data->{FLAT} } );
    
    ###$wmap->wf_size( $sep->wafer_data->{WAFER_SIZE} );
    ###use wafer size from file in not available in PP_PROD###
    if($wmap->{wf_size} eq "" || $wmap->{wf_size} == 0){
    	INFO("### USED wafer size from the file, NOT available or has zero value on PP_PROD ###");
    	$wmap->wf_size($sep->wafer_data->{WAFER_SIZE});
    	###assume in mm already###
    	$convertToMilimeterFlag = "N";
    }
    
    ###convert wafer size to mm, used common fixed values otherwise multiply by 25.4### jgarcia added###
    if($wmap->{wf_units} ne "mm" && $wmap->{wf_units} =~ /IN/i) {
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
    }
    
    $dieUnits = $sep->wafer_data->{UNITS};

    my $session_sum = $sep->sessionSummary;

    $model->misc($sep);

    # WaferMap
    $wmap->wf_units('mm');
    if ( $wmap->wf_size eq 200 ) {
    	$wmap->flat_type('N');
    }
    else {
    	$wmap->flat_type('F');
    }
    $wmap->positive_x('R');
    $wmap->positive_y('D');
    my $stats = $wafer->stats;
    $wmap->convertDieSizeToMM( $dieUnits, $stats );
    $wmap->calcCenterDie($stats);
    $wmap->device_count( $stats->{deviceCount} );
    $header->DEVICE_COUNT( $stats->{deviceCount} );
    return $model;
}
1;

