#!/usr/bin/env perl_db
my $ToolName = "fcs_camstarloss.pl";
#
#------------------------- File Header -----------------------------------
#
# File Name: fcs_camstarloss.pl
#
# Description: This script will add LSR meta and summary data to SPD files, and validate data in some cases.
#
# Sccs Id:    @(#)fcs_camstarloss.pl	1.0 16/03/2015 17:00:47
#
# Related Files/Documents:
#
# Revision History
# ________________
# Date      Author           Description
#
# 16-03-2015  Jacky       Initial Version
# 22-05-2015  Grace       Added qtyIn, qtyOut for parameter
# 29-05-2015  S. Boothby  Don't treat loss codes named BINnn differently from other loss codes.
#                         Get total fail qty from _TOTAL_LOSS bin.
# 05-06-2015  S. Boothby  Added file index to output file names to ensure uniqueness.
# 21-06-2015  S. Boothby  Removed iff extension from sandbox file name.
# 24-06-2015  S. Boothby  Detect merge bin operation and add to step name.
# 20-07-2015  S. Boothby  Populate source lot from meta lookup, not file.
#                         Send to sandbox if lot meta lookup fails.
# 29-09-2015  S. Boothby  When present, process operator, route, area and start_time columns.
# 30-09-2015  S. Boothby  Changed wafer to use lot instead of source lot.
# 13-07-2016  S. Boothby  Added -qvalid option to zero out (N) or retain (Y) qtyIn,qtyOut values for rows containing valid equipment.
# 08-04-2020  E. Alfanta  Skip duplicate header lines
# 02-09-2020  K. Gabato   added support to fork output (IFF)/files to designated location.
# 2021/Apr/15 jgarcia :	  get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
# 2021/Apr/15 jgarcia : fixed "Experimental values on scalar is now forbidden" issue.
#-------------------------------------------------------------------------
# Usage:
#
# ----------------- Start CVS Section (do not modify) -------------------
#
#      $Id: fcs_camstarloss.pl 2634 2020-10-12 05:36:31Z dpower $
my ($sVersionId)     = ( split( ' ', '$Revision: 2634 $' ) )[1];
my ($VersionAndDate) = "

1.0
";

# ------------------------- End CVS Section -----------------------------
#
##############################################################################

#-------------------------------------------------------------------------
# Variable declarations
use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use DateTime;
use Getopt::Long;
use File::Basename;
use File::Spec::Functions;
use POSIX qw(strftime);
use PDF::DpData;
use PDF::DAO;
use PDF::Log;
use PDF::DpWriter;
use PDF::DpLoad;
use Config::Tiny;
use PPLOG::PPLogger;

# define the string to be used in case of null field
my $nullreplace = "NA";

#Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# a hash to receive options
my (%hOptions) = (
    "OUTDIR"       => undef,
    "FORK"         => undef,
    "FACILITYFILE" => undef,
    "EXT"          => undef,
    "FINALLOT"     => 0,
    "LOC"          => undef,
    "QVALID"       => undef,
    "DEBUG"        => undef,
    "SEPARATOR"    => undef,
    "HELP"         => undef,
    "LOGFILE"      => undef,
    "TRACE"        => undef,
);

my $separator     = ",";     #by default the separator is the comma
my $header        = 1;       #by default the number of the header is 1
my $exclude       = "0";     #by default exclude nothing
my $custom        = 0;       #by default custom is zero
my $fileIx        = undef;
my $location      = undef;
my $qtyValid      = undef;
my @file_list     = ();
my $out_separator = undef;
my %toolHash;
my $facility;
my $location;
my $ertUrl 	 = undef;
my $config       = undef;

##############################################################################
#                                 Main
#
##############################################################################
# command line arguments.

Initialize_argument();

# parse all the files in order
foreach (@file_list) {
    my $file = $_;
    INFO("--> Splitting the file $file, please wait...");

    Split_on_single_file( $file, \%hOptions );

    INFO(" --> Done with splitting the file $file");
}

INFO(" --> Done!");

dpExit(0);

##############################################################################
# Subroutine: Initialize_argument
##############################################################################
sub Initialize_argument {

    # turn the ignorecase option on so that the options will be case-insensitive
    $Getopt::Long::ignorecase = 1;
    $Getopt::Long::debug      = 0;

    # get all values of the options that the user has defined

    MyUsage()
      unless (
        GetOptions(
            \%hOptions,       "OUTDIR=s", "FORK=s",   "EXT=s",
            "FACILITYFILE=s", "LOC=s",    "QVALID=s", "SEPARATOR=s",
            "FINALLOT",       "V",        "VERSION",  "LOGFILE=s",
            "DEBUG",          "TRACE",    "HELP",
        )
      );

    #Pass PPLogger object to PDF::Log
    PDF::Log->init( \%hOptions,$pplogger);
    if ($hOptions{PPLOG}){
                $pplogger->settobeLog(1);  #Set flag for pp logging
    }
    $pplogger->setScript(basename($0));
    if ( $hOptions{V} || $hOptions{VERSION} || $hOptions{help} ) {
        print("$VersionAndDate\n");
        dpExit(0);
    }

    if ( $hOptions{HELP} ) { MyUsage(); }

    if ( $#ARGV < 0 ) { MyUsage(); }

    # and also get all the names of the files that the user would like to split
    @file_list = @ARGV;

    $hOptions{SEPARATOR} = $separator unless defined( $hOptions{SEPARATOR} );

    $out_separator = $hOptions{SEPARATOR};

    # create the outdir if it does not exist
    if ( !-e $hOptions{OUTDIR} ) {
        printf STDERR "Making output directory: $hOptions{OUTDIR}\n";
        my $mkdir_ret = mkdir( $hOptions{OUTDIR}, 0777 );
        if ( $mkdir_ret != 1 ) {
            dpExit( 1, "Fail to make output directory $hOptions{OUTDIR}" );
        }
    }
    else {
        #	MyUsage();
    }

    if ( !defined( $hOptions{QVALID} ) ) {
        dpExit( 1, "Required option -qvalid=[Y|N] not supplied." );
    }
    $qtyValid = $hOptions{QVALID};

    if ( !defined( $hOptions{LOC} ) ) {
        dpExit( 1, "Required option -loc=LOC not supplied." );
    }
    $location = $hOptions{LOC};

    if ( $hOptions{LOGFILE} ) {
        PDF::Log->init( $hOptions{LOGFILE} );
    }
    else {
        PDF::Log->init;
    }
    PDF::Log->setLevelDebug if ( $hOptions{DEBUG} );
    PDF::Log->setLevelTrace if ( $hOptions{TRACE} );

    my $config = Config::Tiny->read( $hOptions{FACILITYFILE} );
    $location = $hOptions{LOC};
    $ertUrl = $config->{$location}->{ppLotProd};
    $facility = "";

    # output the option values if the debug option is turned on
    DEBUG("Input file: @file_list");
    DEBUG("Output directory: $hOptions{OUTDIR}");
    DEBUG("Datatype: $hOptions{EXT}");
    DEBUG("Separator: $hOptions{SEPARATOR}");
    DEBUG("Location: $hOptions{LOC}");
    if ( $hOptions{OUTDIR} =~ /.+sort.+/i ) {
        $facility = $config->{$location}->{probe};
    }
    else {
        $facility = $config->{$location}->{finalTest};
    }
    INFO("FACILITY || EQUIP6 = >>$facility<<");

    return 1;
}

##############################################################################
# Subroutine: MyUsage
##############################################################################
sub MyUsage {
    my ($sUsageMsg) = <<"__END_OF_USAGE_MESSAGE__";    # Usage note
fcs_camstarloss.pl <inputfiles> ...
       [ -outdir <directory> ]         Output directory
	   [ -ext <ext> ]				   Specify the extension of output files
       [ -debug ]                      Debug mode (off by default)
       [ -separator ]                  Separator of columns (comma by default), if more than one separator have been used
                                       the first separator will be used as output separator
       [ -VERSION | -help ]            Display version ID or help messages
	   [ -logfile ]            		   Used to log
__END_OF_USAGE_MESSAGE__

    die "$sUsageMsg";
}

sub addSeconds {

    # Add one second to time passed in
    my $time_str    = shift;
    my $num_seconds = shift;

    my ( $yy, $mt, $dd, $hh, $mm, $ss ) = split( "-|:| ", $time_str );
    my $dt = DateTime->new(
        year   => $yy,
        month  => $mt,
        day    => $dd,
        hour   => $hh,
        minute => $mm,
        second => $ss,
    );
    $dt->add( seconds => $num_seconds );
    my $new_time_str = sprintf(
        "%d-%02d-%02d %02d:%02d:%02d",
        $dt->year, $dt->month,  $dt->day,
        $dt->hour, $dt->minute, $dt->second
    );
    return $new_time_str;
}

sub getOffset {
    my $thisTool    = shift;
    my $thisXactKey = shift;

    if ( $thisTool eq "" or $thisTool eq " " ) {
        return 0;
    }
    if ( !exists $toolHash{$thisXactKey} ) {
        $toolHash{$thisXactKey} = { $thisTool => 1 };
        return 1;
    }
    else {
        my $curTools = $toolHash{$thisXactKey};

        if ( !exists $curTools->{$thisTool} ) {
            my $qty = keys( %{$curTools} ) + 1;
            $curTools->{$thisTool} = $qty;
            return ( keys( %{$curTools} ) );
        }
        else {
            return $curTools->{$thisTool};
        }
    }
}

##############################################################################
# Subroutine: Split_on_single_file
##############################################################################
sub Split_on_single_file {

    my ( $file, $hOptions ) = @_;
    my @work                = ();
    my $DEVICE_COUNT_DEFAUT = "<DEVICECOUNTVALUE>";
    my %output              = ();
    my %headers             = ();
    my $iGotHeader          = 0;

    my $areaColumn        = undef;
    my $routeColumn       = undef;
    my $stepColumn        = undef;
    my $productColumn     = undef;
    my $lotColumn         = undef;
    my $equipColumn       = undef;
    my $operatorColumn    = undef;
    my $txndateColumn     = undef;
    my $startdateColumn   = undef;
    my $lqtyColumn        = undef;
    my $lrnColumn         = undef;
    my $lrdColumn         = undef;
    my $qtyInColumn       = undef;
    my $qtyOutColumn      = undef;
    my $waferColumn       = undef;
    my $autoBinLossColumn = undef;

    my $bn = basename($file);

    my @words = split( /_|\./, $bn );
    if ( $#words < 0 ) {
        dpExit( 1, "Unable to get facility code from filename:" . $bn );
    }

    my $facilityCode = $words[1];
    $fileIx = $words[2];

    # open the file
    open( fhIn, "<$file" ) || dpExit( 1, "Unable to open file $file" );

    while (<fhIn>) {
        chomp;
        s/\r//;
        s/~//g;
        my $line = $_;
        @work = split("\\|");
        if ( not $iGotHeader ) {
            for ( my $i = 0 ; $i <= $#work ; $i++ ) {
                INFO( $i . "=" . $work[$i] );
                if ( $work[$i] eq "area" ) {
                    $areaColumn = $i;
                }
                elsif ( $work[$i] eq "route" ) {
                    $routeColumn = $i;
                }
                elsif ( $work[$i] eq "step" ) {
                    $stepColumn = $i;
                }
                elsif ( $work[$i] eq "product" ) {
                    $productColumn = $i;
                }

                elsif ( $work[$i] eq "lot" ) {
                    $lotColumn = $i;
                }
                elsif ( $work[$i] eq "equipmentName" ) {
                    $equipColumn = $i;
                }
                elsif ( $work[$i] eq "operator" ) {
                    $operatorColumn = $i;
                }
                elsif ( $work[$i] eq "startTime" ) {
                    $startdateColumn = $i;
                }
                elsif ( $work[$i] eq "txndate" ) {
                    $txndateColumn = $i;
                }
                elsif ( $work[$i] eq "lossQty" ) {
                    $lqtyColumn = $i;
                }
                elsif ( $work[$i] eq "LossReasonName" ) {
                    $lrnColumn = $i;
                }
                elsif ( $work[$i] eq "LossReasonDesc" ) {
                    $lrdColumn = $i;
                }
                elsif ( $work[$i] eq "qtyIn" ) {
                    $qtyInColumn = $i;
                }
                elsif ( $work[$i] eq "qtyOut" ) {
                    $qtyOutColumn = $i;
                }
                elsif ( $work[$i] eq "WaferNumber" ) {
                    $waferColumn = $i;
                }
                elsif ( $work[$i] eq "autoBinLossStep" ) {
                    $autoBinLossColumn = $i;
                }
            }

            $iGotHeader = 1;
            if (   defined($areaColumn)
                && defined($stepColumn)
                && defined($productColumn)
                && defined($lotColumn)
                && defined($equipColumn)
                && defined($operatorColumn)
                && defined($txndateColumn)
                && defined($lqtyColumn)
                && defined($lrnColumn)
                && defined($lrdColumn)
                && defined($qtyInColumn)
                && defined($qtyOutColumn) )
            {

            }
            else {
                ERROR( "necessary camstar dat columns undefined" . $file );
                dpExit( 1,
                    "error parminfo necessary columns undefined: " . $file );
            }
        }
        else {
            my $step = $work[$stepColumn];

            if ( $step =~ /^\s*$/ ) {
                WARN( "necessary step undefined line in oper file--" . $line );
                next;
            }

            my $lot = $work[$lotColumn];

            if ( $lot =~ /^\s*$/ ) {
                WARN( "necessary lot undefined line in oper file--" . $line );
                next;
            }

            my $txndate = $work[$txndateColumn];
            if ( $txndate =~ /^\s*$/ ) {
                WARN(
                    "necessary txndate undefined line in oper file--" . $line );
                next;
            }

            ## Apr-08-2020 Eric: Skip multiple header
            my $tmpStartDate = $work[$startdateColumn];
            if ( $tmpStartDate eq "startTime" ) {
                WARN( "Duplicate headers encountered in line--" . $line );
                next;
            }

            my $start_date = $txndate;
            if ( defined($startdateColumn) ) {
                $start_date = $work[$startdateColumn];
                if ( $start_date =~ /^\s*$/ ) {
                    $start_date = $txndate;
                }
            }

# To ensure separate rows for _GOOD and _TOTAL_LOSS,
# set end_date equal to txndate for rows with loss codes, txndate+1s for _GOOD, TOTAL_LOSS
            my $end_date = $txndate;

            my $area = $work[$areaColumn];
            if ( defined($area) && $area eq "NULL" ) {
                $area = "N/A";
            }
            my $route = undef;
            if ( defined($routeColumn) ) {
                $route = $work[$routeColumn];
            }
            my $operator             = $work[$operatorColumn];
            my $qtyIn                = $work[$qtyInColumn];
            my $qtyOut               = $work[$qtyOutColumn];
            my $lqty                 = $work[$lqtyColumn];
            my $wafer                = $work[$waferColumn];
            my $prod                 = $work[$productColumn];
            my $lrn                  = $work[$lrnColumn];
            my $equip                = $work[$equipColumn];
            my $autoBinLossOperation = undef;

            if ( defined($autoBinLossColumn) ) {
                $autoBinLossOperation = $work[$autoBinLossColumn];
            }

#if ( $lrn =~ /GOOD/ || $lrn =~ /TOTAL_LOSS/ || $equip =~ /^\s*$/ || $equip eq "n/a" )
            if ( $equip =~ /^\s*$/ || $equip eq "n/a" ) {
                $equip = "N/A";
            }
            elsif ( $qtyValid ne "Y" ) {
                $qtyIn  = "";
                $qtyOut = "";
            }
            my $lrd = $work[$lrdColumn];

            my $ii = index( $bn, '.' );

            my $fname =
                substr( $bn, 0, $ii ) . "."
              . $fileIx . "."
              . $step . "_"
              . $lot . "_"
              . $txndate;
            INFO("$bn, $ii, $fname");
            if ( defined( $headers{$fname}{"HEADER"} ) ) {
            }
            else {
                my $header = PDF::DpData::HeaderLong->new();
                $header->VERSION($sVersionId);
                $header->CREATION_DATE(
                    strftime( "%m/%d/%Y %H:%M:%S", localtime( time() ) ) );
                $header->LOT($lot);
		$header->ertUrl($ertUrl);
                $header->isFinalLot( $hOptions{FINALLOT} );
                $header->PROGRAM_CLASS(12);
                if ( defined($autoBinLossOperation)
                    && $autoBinLossOperation eq "Y" )
                {
                    $header->PROGRAM( "LOSS::"
                          . $step
                          . " (Mrg Bin Oper)::"
                          . $facilityCode
                          . "::CAM" );
                }
                else {
                    $header->PROGRAM( "LOSS::" . $facilityCode . "::CAM" );
                }

                # get Mata from database
                unless ( $header->populateMeta ) {
                    ERROR( "cannot populate Meta data from refdb by lot id: "
                          . $lot );
                    $headers{$fname}{"MISSING"} = 1;
                }

                $header->PRODUCT($prod);
                unless ( $header->populateMetaByProduct ) {
                    ERROR(
                        "cannot populate Meta data from refdb by product id: "
                          . $prod );
                    $headers{$fname}{"MISSING"} = 1;
                }

                # if (   $header->SOURCE_LOT eq "N/A"
                #     || $header->SOURCE_LOT =~ /^\s*$/ )
                # {
                #     $header->SOURCE_LOT($lot);
                # }
                $header->SOURCE_LOT(formatSourceLot($header->{SOURCE_LOT}, $header->{LOT}));
                $header->FAB($facilityCode);
                $header->STEP($step);

                if ( defined($route) ) {
                    $header->STAGE($route);
                }
                else {
                    $header->STAGE($area);
                }
                if ( defined($area) ) {
                    $header->STEP_GRP1($area);
                }
                $header->EQUIP1_ID($equip);
                $header->OPERATOR($operator);
                INFO( "START_TIME=" . $start_date );
                $header->START_TIME($start_date);
                $header->END_TIME($end_date);
                $header->DEVICE_COUNT($DEVICE_COUNT_DEFAUT);
                $header->EQUIP6_ID("$facility");

                my $str_header = "<HEADER>\n";
                $str_header .= $header->toString;
                $str_header .= "</HEADER>\n";

                $headers{$fname}{"HEADER"}     = $str_header;
                $headers{$fname}{"SOURCE_LOT"} = $header->SOURCE_LOT;
                $headers{$fname}{"LOT"}        = $header->LOT;

            }

            my $wafernumber = undef;
            if ( $wafer =~ /^\s*$/ ) {
                $wafernumber = "00";
                $headers{$fname}{"DEVICE_COUNT"} = $qtyIn;
            }
            else {
                $wafernumber = sprintf( "%02d", $wafer );
                $headers{$fname}{"DEVICE_COUNT"} += $qtyIn;
            }

            if ( defined( $output{$fname}{$wafernumber}{$equip} ) ) {

            }
            else {
                $output{$fname}{$wafernumber}{$equip}{"PAR_DATA"} = "";
            }

            my $binnumber = undef;
            my $binname   = undef;
            my $binvalue  = undef;
            if ( $lrn =~ /^\s*$/ && $lrd =~ /^\s*$/ ) {
                dpExit( 1,
                        "LossReasonName and LossReasonDesc are null: "
                      . $line
                      . " in the file:"
                      . $file );
            }
            else {

                if ( $lrd =~ /^\s*$/ ) {
                    $binname = $lrn;
                }
                else {
                    $binname = $lrd;
                }

                if ( $lrn =~ /TOTAL_LOSS/ ) {
                    $binvalue = $lqty;
                    $output{$fname}{$wafernumber}{$equip}{"BIN_DATA"} .=
                      $binname . "," . $binvalue . "\n";
                    $output{$fname}{$wafernumber}{$equip}{"FAIL_COUNT"} =
                      $binvalue;
                }
                elsif ( $lrn =~ /GOOD/ ) {
                    $binvalue = $lqty;
                    $output{$fname}{$wafernumber}{$equip}{"BIN_DATA"} .=
                      $binname . "," . $binvalue . "\n";
                    $output{$fname}{$wafernumber}{$equip}{"PASS_COUNT"} =
                      $binvalue;

                    $output{$fname}{$wafernumber}{$equip}{"BIN_DATA"} .=
                      "qtyIn," . $qtyIn . "\n";
                    $output{$fname}{$wafernumber}{$equip}{"BIN_DATA"} .=
                      "qtyOut," . $qtyOut . "\n";

                }
                else {

                    $binvalue = $lqty;
                    $output{$fname}{$wafernumber}{$equip}{"PAR_DATA"} .=
                      $binname . "," . $binvalue . "\n";
                }
            }
        }
    }
    my $holder = undef;
    foreach $holder ( sort keys %headers ) {
        my $fn = $holder;
        $fn =~ s/ //g;
        $fn =~ s/\///g;

#INFO("$holder, grace, $DEVICE_COUNT_DEFAUT,   $headers{$holder}{'DEVICE_COUNT'} ");
        my $headerdata = $headers{$holder}{"HEADER"};
        $headerdata =~
          s/$DEVICE_COUNT_DEFAUT/$headers{$holder}{"DEVICE_COUNT"}/;

        my $outputdata = $headerdata;

        my $wn   = undef;
        my %tmph = %{ $output{$holder} };
        foreach $wn ( sort keys %tmph ) {

            $outputdata .= "<SUB_LOT>\n";

            #		$outputdata .= $headers{$holder}{"SOURCE_LOT"}."_".$wn."\n";
            $outputdata .= $headers{$holder}{"LOT"} . "_" . $wn . "\n";
            $outputdata .= "</SUB_LOT>\n";

            my %tmpe = %{ $tmph{$wn} };
            my $eq   = undef;
            foreach $eq ( sort keys %tmpe ) {
                $outputdata .= "<EQUIP1_ID>\n";
                $outputdata .= $eq . "\n";
                $outputdata .= "</EQUIP1_ID>\n";

                my %bpds  = %{ $tmpe{$eq} };
                my $yield = 0;
                if (   ( $bpds{"PASS_COUNT"} eq "" )
                    or ( $bpds{"PASS_COUNT"} eq 0 ) )
                {
                    $yield = 0;
                }
                elsif ( $bpds{"FAIL_COUNT"} eq "" ) {
                    $yield = 100;
                }
                else {
                    $yield = 100 * $bpds{"PASS_COUNT"} /
                      ( $bpds{"PASS_COUNT"} + $bpds{"FAIL_COUNT"} );
                }

                $outputdata .= "<PAR_DATA>\n";
                if ( ( $bpds{"PASS_COUNT"} ne "" and $bpds{"FAIL_COUNT"} ne "" )
                  )
                {
                    $outputdata .= "yield,$yield\n";
                }
                $outputdata .= $bpds{"BIN_DATA"};
                $outputdata .= $bpds{"PAR_DATA"};
                $outputdata .= "</PAR_DATA>\n";
            }
        }
        my $wr = PDF::DpWriter->new(
            {
                outdir   => $hOptions{OUTDIR},
                forkdir  => $hOptions{FORK},
                basename => ($fn),
                ext      => $hOptions{EXT},
                gzipIFF  => 'Y'
            }
        );
        if ( defined( $headers{$holder}{"MISSING"} ) ) {
            $wr->noMeta(1);
            $wr->ext( $hOptions{EXT} );
        }
        $wr->open;
        $wr->put($outputdata);
        $wr->close;
    }
}
