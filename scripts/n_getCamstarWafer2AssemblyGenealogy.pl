#!/usr/bin/env perl_db

# 2022-09-26 S. Boothby : Initial version

# Query Camstar database for wafer part consumption records
# Write two files:
# 1. Wafer to Assembly lot genealogy records (load using DBTOOLS)
# 2. Class 50 for TRACE:ASSEMBLY2WAFER and TRACE:WAFER2ASSEMBLY loading
#
# Wafer genealogy has no header but should be formatted like this:
# (PART_CNT=ASSEMBLY_PART_COUNT)
# EVENT_TYPE|STEP|EVENT_TIME|EVENT_NAME|SRC_LOT|LOT|LOT_TYPE|PROD|PART_CNT|FROM_FAB|FROM_PROD|FROM_SRC_LOT|FROM_LOT|WAFERS|WF_NUMS 
# One row per EVENT_TIME+LOT+FROM_SRC_LOT
# Use refdb web service to look up source lot from FROM_LOT.  Using the scribe ID isn't sufficient for these sites:
# CZ4, JND
#
# Key differences between Camstar deployments
# LotType:
# - Cebu and Suzhou: historymainline.ownername (is prefixed with ON for some reason)
#                    ,case when hm.ownername like 'ON%' and Len(hm.OwnerName) = 4 then SUBSTRING(hm.OwnerName, 3, 2) else hm.OwnerName end as LotType
# - All others: onsLotType.onsLotTypeName (join from A_Lotattributes.onsLotTypeId = onsLotType.onsLotTypeId)
# MaterialLotID: (this is the received lot ID, generally the lot ID at wafer sort or after backgrind & backmetal)
# - Cebu and Suzhou: Parse MaterialLotName, remove dash and wafer number
# - All others: A_Lotattributes.onsSourceLotId (lot attribute of the material/wafer lot)
#
# MODIFICATION HISTORY:
# WHEN       WHO        WHAT
# ---------- ---------- --------------------------------------------------------------
# 2023-02-07 S. Boothby Fixed Wafer ID naming for BE2 and ISMF(AB)
# 2023-02-22 S. Boothby Added leading zero to wafer number < 10 for Cebu wafers in Camstar
# 2023-02-28 S. Boothby Multiple fixes for invalid source lots, LOTG lookup
# 2023-03-31 S. Boothby Look up correct scribe when EFK wafer is consumed using a scribe containing multiple space characters
# 2026-02-10 jgarcia  Added benchmark JSONL logging and singleton lock
#
use strict;
use File::Copy;
use FindBin::libs;
use Getopt::Long qw/:config ignore_case auto_help/;
use DBI;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename dirname/;
use File::Spec;
use DateTime::Format::Strptime;
use Carp;
use PDF::Log;
use PDF::DAO;
use PDF::DpData;
use PDF::DpLoad;
use PDF::WS;
use IO::Compress::Gzip qw(gzip $GzipError) ;;
use Data::Dumper;
use Time::HiRes qw(time);
use JSON::PP;
use Fcntl qw(:flock);

my $dt = DateTime->now(time_zone => 'local');
my $currentDateTime = join '_', $dt->ymd, $dt->hms;
$currentDateTime =~ s/[:-]//g;

my $usageMsg = "Usage: $0 --source_db {source-DB} --source_warehouse {source-warehouse} --source_schema {source snowflake-db.schema} --start_hours num-hours --end_hours num-hours --logfile {log-file} --out_gen {wafer-genealogy-upload-dir} --archive_gen {wafer-genealogy-archive-dir} --out_trace {trace-upload-dir} --archive_trace {trace-archive-dir} --benchmark_log {jsonl-file} [--benchmark_include_non_archive] --lock_file {lock-file} --pipeline_name {name} --pipeline_type {type}\n";
my $onLotWSURL="http://globmfgapp.onsemi.com:61050/exensioreftables-ws/api/onlot/bylotid/";
#my $ppLotWSURL="http://globmfgapp.onsemi.com:61050/exensioreftables-ws/api/pplot/bylotid/";
my $ppLotProdWSURL="http://globmfgapp.onsemi.com:61050/exensioreftables-ws/api/pplotprod/bylotid/";
# Append lotid&waferNum=nn
#my $onScribeWSURL="http://globmfgapp.onsemi.com:61050/exensioreftables-ws/api/onscribe/bylotidsandwafernum?lotId=";

my $startHours = 2;
my $endHours   = 0;

my %hOptions = (
   "SOURCE_DB"     => undef,
   "SOURCE_WAREHOUSE" => undef,
   "LOGFILE"       => undef,
   "BENCHMARK_LOG" => undef,
	"BENCHMARK_INCLUDE_NON_ARCHIVE" => undef,
   "LOCK_FILE"     => undef,
	"PIPELINE_NAME" => undef,
	"PIPELINE_TYPE" => undef,
   "OUT_GEN"       => undef,
   "OUT_TRACE"     => undef,
   "ARCHIVE_GEN"   => undef,
   "START_HOURS"   => undef,
   "END_HOURS"     => undef,
   "ARCHIVE_GEN"   => undef,
   "ARCHIVE_TRACE" => undef
);

unless (GetOptions( \%hOptions, "SOURCE_DB=s","SOURCE_WAREHOUSE=s","SOURCE_SCHEMA=s", "START_HOURS=s", "END_HOURS=s", "OUT_GEN=s", "OUT_TRACE=s", "ARCHIVE_GEN=s", "ARCHIVE_TRACE=s", "LOGFILE=s", "BENCHMARK_LOG=s", "BENCHMARK_INCLUDE_NON_ARCHIVE!", "LOCK_FILE=s", "PIPELINE_NAME=s", "PIPELINE_TYPE=s")){
    print($usageMsg);
    dpExit( 1, "invalid options" );
}
PDF::Log->init(\%hOptions);

my $startTime = time();
my $startLocal = DateTime->now(time_zone => 'local')->strftime('%Y-%m-%d %H:%M:%S');
my $startUtc = DateTime->now(time_zone => 'UTC')->strftime('%Y-%m-%dT%H:%M:%SZ');

my $lockFile = $hOptions{LOCK_FILE};
if (!defined($lockFile) || $lockFile eq "")
{
	if (defined($hOptions{PIPELINE_NAME}) && $hOptions{PIPELINE_NAME} ne "")
	{
		my $safePipeline = $hOptions{PIPELINE_NAME};
		$safePipeline =~ s/[^a-zA-Z0-9_\-\.]/_/g;
		$lockFile = "./log/$safePipeline.lock";
	}
	else
	{
		$lockFile = "./log/n_getCamstarWafer2AssemblyGenealogy.lock";
	}
}
my $lockDir = dirname($lockFile);
if (defined($lockDir) && length($lockDir) > 0 && !-d $lockDir)
{
	mkdir($lockDir);
}
open(my $lockFH, ">>", $lockFile) or dpExit(1, "Unable to open lock file $lockFile: $!");
unless (flock($lockFH, LOCK_EX|LOCK_NB))
{
	dpExit(1, "Another instance is already running (lock: $lockFile)");
}

unless ( $hOptions{SOURCE_DB} ) {
    print($usageMsg);
    dpExit( 1, "--SOURCE_DB argument is required!" );
}
unless ( $hOptions{SOURCE_WAREHOUSE} ) {
	$hOptions{SOURCE_WAREHOUSE} = "application_prd_wh";
}
unless ( $hOptions{SOURCE_SCHEMA} ) {
	$hOptions{SOURCE_SCHEMA} = "";
}
unless ( $hOptions{OUT_GEN} ) {
    print($usageMsg);
    dpExit( 1, "OUT_GEN argument is required!" );
}
unless ( $hOptions{OUT_TRACE} ) {
    print($usageMsg);
    dpExit( 1, "OUT_TRACE argument is required!" );
}
unless ( $hOptions{ARCHIVE_GEN} ) {
    print($usageMsg);
    dpExit( 1, "--ARCHIVE_GEN argument is required!" );
}
unless ( $hOptions{ARCHIVE_TRACE} ) {
    print($usageMsg);
    dpExit( 1, "--ARCHIVE_TRACE argument is required!" );
}
if ( $hOptions{START_HOURS} )
{
	$startHours = int($hOptions{START_HOURS});
}
if ( $hOptions{END_HOURS} )
{
	$endHours = int($hOptions{END_HOURS});
}

# ODBC Data sources are defined in the file ~/.odbc.ini
my %camstarSources = ('CEBU' => {
                                 'DataSource' => q/dbi:ODBC:MSSQL-Perl/,
                                 'UserID'     => q/ymsapp_rd/,
                                 'Password'   => q/yms20150/
                                },
                      'OSV'  => {
                                 'DataSource' => q/dbi:ODBC:MSSQL-OSV/,
                                 'UserID'     => q/READ_ONLY_REPORTS/,
                                 'Password'   => q/Cosine9#3!SC/
                                },
                      'SBN'  => {
                                 'DataSource' => q/dbi:ODBC:MSSQL-SBN/,
                                 'UserID'     => q/read_only_rptusrs/,
                                 'Password'   => q/rptusrs/
                                },
                      'OSPI' => {
                                 'DataSource' => q/dbi:ODBC:MSSQL-OSPI/,
                                 'UserID'     => q/read_only_rptusrs/,
                                 'Password'   => q/rptusrs/
                                },
                      'ONSC' => {
                                 'DataSource' => q/dbi:ODBC:MSSQL-ONSC/,
                                 'UserID'     => q/READ_ONLY_REPORTS/,
                                 'Password'   => q/Sqrt9#3!SC/
                                },
                      'ONSZ' => {
                                 'DataSource' => q/dbi:ODBC:MSSQL-Suzhou/,
                                 'UserID'     => q/ymsapp_ro/,
                                 'Password'   => q/yms20150/
                                }
                     );
# Oracle data sources are defined in ~/tns/tnsnames.ora.  Perhaps we should use the refdb web service instead?
my $dwprodDataSource = q/DWPRD/;
my $lotGDataSource   = q/LOTGPRD/;

my $sourceDB = $hOptions{SOURCE_DB};
unless ( exists $camstarSources{$sourceDB} ) {
    print($usageMsg);
    dpExit( 1, "SOURCE_DB must be one of: ".join(" ",keys(%camstarSources) ));
}

my $class50Header = "LOT|ASSEMBLY_PART_COUNT|SOURCE_LOT|LOT_TYPE|PRODUCT|CONSUMPTION_DATE|FROM_PRODUCT|FROM_EXENSIO_SOURCE_LOT|FROM_EXENSIO_WAFER_ID|FROM_WAFER_NUMBER|FROM_FAB|FROM_INVENTORY_LOT|FROM_WAFER_SCRIBE|QTY_CONSUMED|QTY_REQUIRED|CONSUME_FACTOR|MATERIAL_LOT|ASSEMBLY_STEP";

my $outputGenDir    = $hOptions{OUT_GEN};
my $outputTraceDir  = $hOptions{OUT_TRACE};
my $archiveGenDir   = $hOptions{ARCHIVE_GEN};
my $archiveTraceDir = $hOptions{ARCHIVE_TRACE};

if ( not -w $outputGenDir )
{
	dpExit(1, "OUT_GEN directory does not exist or is not writable: $outputGenDir");
}
elsif ( not -w "$outputGenDir/tmp" )
{
	mkdir("$outputGenDir/tmp");
}
if ( not -w $outputTraceDir )
{
	dpExit(1, "OUT_TRACE directory does not exist or is not writable: $outputTraceDir");
}
elsif ( not -w "$outputTraceDir/tmp" )
{
	mkdir("$outputTraceDir/tmp");
}


# Get fab codes & descriptions from BIW
my %fabCodes = &getFabCodes();

my $sql = &getSQL($sourceDB);
INFO( "Querying: $sourceDB" );
my $dbhMSSQL = &odsConnect($camstarSources{$sourceDB}->{DataSource}, $camstarSources{$sourceDB}->{UserID}, $camstarSources{$sourceDB}->{Password});
my $dwsth=$dbhMSSQL->prepare($sql);
if ( !defined($dwsth) || !($dwsth) )
{
	$dbhMSSQL->disconnect;
	dpExit(1, "SQL Prepare failure for $sourceDB");
}
my $rc=$dwsth->execute;
if (! defined( $rc ))
{
	$dbhMSSQL->disconnect;
	dpExit(1, "SQL Prepare failure for $sourceDB");
}
my $isFmrFairchild = 0;
if ( $sourceDB eq "ONSZ" || $sourceDB eq "CEBU" )
{
	$isFmrFairchild = 1;
}

# Variables needed to write out records to trace and genealogy files
# genInfo key is genealogy event name
my %genInfo;
# traceInfo key is assemblyLot_exensioWafer
my %traceInfo;

my %sourceLots;
my %sourceFabs;
my %scribeIDs;

# Diagnostics counters to track data flow (aligned with E142 pattern)
my $rowsFetched = 0;
my $rowsKept = 0;
my $rowsSkipped = 0;

my ($genEventName, $genLine, $traceEventName, $traceLine);
my ($assemblyLot, $assemblySourceLot, $assemblyLotType, $assemblyProduct, $assemblyPartCount);
my ($step, $eventTime, $eventName);
my ($fabLot, $fabSourceLot, $fabProduct, $fabPartCount, $fabPartRequired, $consumeFactor, $fromFab);
my ($exensioWaferID, $fabID, $waferScribe, $str);
my $wsCall;
my %fFairchildFabs = ( 'KRG'=>1,'KRI'=>2,'KRH'=>3,'KRJ'=>4,'UWA'=>5,'CBA'=>6,'PBC'=>7,'UWB'=>8 );

my $fabReturned;
# Process the data from the Camstar DB
while( my $ref=$dwsth->fetchrow_hashref())
{
	$rowsFetched++; # Track rows from source database
	$assemblySourceLot = "";
	$assemblyPartCount = "";
	$fabSourceLot = "";
	$fabReturned = "";
	$exensioWaferID = "";
	$fromFab = "";
	$fabID = "";
	$fabPartCount = "";
	$fabPartRequired = "";
	$consumeFactor = "";
	$waferScribe = "";

	$assemblyPartCount = sprintf("%.0f", $ref->{AssemblyQty});
	$fabPartCount      = sprintf("%.0f", $ref->{QtyConsumed});
	$fabPartRequired   = sprintf("%.0f", $ref->{QtyRequired});
	$consumeFactor     = sprintf("%.0f", $ref->{ConsumeFactor});
	INFO("AssemblyLot: $ref->{AssemblyLot}, FromWaferScribe: $ref->{FromWaferScribeNumber}, Qty: $fabPartCount");

	$waferScribe = $ref->{FromWaferScribeNumber};
	if ( defined($sourceLots{$ref->{AssemblyLot}}))
	{
		$assemblySourceLot = $sourceLots{$ref->{AssemblyLot}} . ".S";
	}
	elsif ( $isFmrFairchild == 1 || $sourceDB eq "ONSC")
	{
		$assemblySourceLot = $ref->{AssemblyLot}.'.S';
		$sourceLots{$ref->{AssemblyLot}} = $ref->{AssemblyLot};
	}
	else
	{
		# Get Assembly source lot from Web Service call
		# For now just keep it like fFCS
		$assemblySourceLot = $ref->{AssemblyLot}.".S";
		$wsCall = $onLotWSURL.$ref->{AssemblyLot};
		INFO( "WS Call: $wsCall");
		my %onLot = getMetaFromRefDbWS($wsCall);
		#INFO("WS Call status: \"$onLot{status}\"");
		if ($onLot{status} =~ /no_data|error/i || length($onLot{sourceLot}) == 0) 
		{
			# The WS indicates no data found in LOTG when Status="No_Data".  For FT module lots this is common, even though results are in fact returned.
			my %lotGresult = &lotGLookup($ref->{AssemblyLot});
			if ( !defined($lotGresult{SOURCE_LOT}))
			{
				WARN("ON_LOT WS asm call for $ref->{AssemblyLot} returned no results and LOTG lookup failed ($wsCall).");
				# Use the material lot as the source lot in this case
				($fabReturned) = $ref->{MaterialLotFab} =~ /\A([^:]+)/;
				$assemblySourceLot = &checkSourceLot($ref->{MaterialLotID}, $fabReturned).".S";
			}
			else
			{
				INFO("ON_LOT WS asm call for $ref->{AssemblyLot} returned no results.  LOTG lookup returned \"$lotGresult{SOURCE_LOT}\", \"$lotGresult{FAB}\"");
				$fabReturned = $lotGresult{FAB};
				$assemblySourceLot = &checkSourceLot($lotGresult{SOURCE_LOT},$lotGresult{FAB}).".S";
				INFO("new Assembly source lot: \"$assemblySourceLot\"");
			}
		}
		else
		{
			($fabReturned) = $onLot{fab} =~ /\A([^:]+)/;
			if ( $fabReturned eq "JPF" or $fabReturned eq "SG1" )
			{
				# Earlier versions of the WS query to LOTG returned JPF as the fab when it was actually CZ4.  Check for this
				# Same for SG1
				my %lotGresult = &lotGLookup($ref->{AssemblyLot});
				if ( defined($lotGresult{FAB}) && $lotGresult{FAB} eq "CZ4:TESLA FAB" )
				{
					WARN("Incorrect source fab JPF, should be CZ4.  Substituting source lot \"$lotGresult{SOURCE_LOT}\"");
					$assemblySourceLot = &checkSourceLot($lotGresult{SOURCE_LOT}, $lotGresult{FAB}).".S";
				}
				elsif (defined($lotGresult{FAB}) and $fabReturned eq "SG1" )
				{
					$fabReturned = $lotGresult{FAB};
					$assemblySourceLot = &checkSourceLot($lotGresult{SOURCE_LOT}, $fabReturned).".S";
				}
				else
				{
					$assemblySourceLot = &checkSourceLot($onLot{sourceLot}, $fabReturned).".S";
				}
			}
			else
			{
				$assemblySourceLot = &checkSourceLot($onLot{sourceLot}, $fabReturned).".S";
			}
		}
		if (exists( $fFairchildFabs{$fabReturned} ) || $ref->{AssemblyLot}.".S" eq $assemblySourceLot)
		{
			# If the source lot is a former fairchild site, need to use source lot from below
			$sourceLots{$ref->{AssemblyLot}} = "GET";
		}
		else
		{
			$sourceLots{$ref->{AssemblyLot}} = substr($assemblySourceLot, 0, -2);
		}
	}
	
	# Look up source lot and fab info from MaterialLotID
	# There is a known problem in Suzhou for NN lots where the fab ID lot attribute is set to the material lot ID instead of the actual source fab.
	# Get the correct source fab from LOTG.
	if ($sourceDB eq "ONSZ" && $ref->{MaterialLotFab} eq $ref->{MaterialLotID})
	{
		my %lotGresult = &lotGLookup($ref->{MaterialLotID});
		if (defined($lotGresult{FAB}) && $lotGresult{FAB} ne $ref->{MaterialLotFab})
		{
			my $newFab;
			($newFab) = split(/:/,$lotGresult{FAB});
			WARN("Incorrect source fab from Camstar \"$ref->{MaterialLotFab}\".  Changing to \"$newFab\"");
			$ref->{MaterialLotFab} = $newFab;
		}
		elsif (!defined($lotGresult{FAB}))
		{
			WARN("Failed to find source fab for material lot \"$ref->{MaterialLotID}\"");
			$ref->{MaterialLotFab} = "";
		}
	} 
	if (defined($sourceLots{$ref->{MaterialLotID}}))
	{
		$fabSourceLot = $sourceLots{$ref->{MaterialLotID}};
		$fabID = $sourceFabs{$ref->{MaterialLotID}};
		($exensioWaferID, $waferScribe) = &checkWaferID($fabSourceLot, $ref->{FromWaferNumber}, $waferScribe, $fabID, $ref->{MaterialLotID});
		$fabSourceLot .= ".S";
	
		$assemblySourceLot = &checkAssemblySourceLot($ref->{AssemblyLot}, $assemblySourceLot, $fabSourceLot, $fabID);
	}
	elsif ( exists $fFairchildFabs{$ref->{MaterialLotFab}} )
	{
		# Look up source lot and fab using web service PP_LOTPROD table call
		$wsCall = $ppLotProdWSURL.$ref->{MaterialLotID};
		INFO( "WS xfcsfab Call: $wsCall");
		my %ppLot = getMetaFromRefDbWS($wsCall);
		#print Dumper(\%ppLot);
		# Earlier versions of the WS query to LOTG returned bad source lots for KRG
		if ($ppLot{status} =~ /no_data|error/i or $ppLot{fab} eq "KRG" or ($ppLot{fab} eq "UWB" && $ppLot{sourceLot} !~ /^M.*$/ )) 
		{
			my %lotGresult = &lotGLookup($ref->{MaterialLotID});
			#INFO("LGR: \"$ppLot{sourceLot}\"");
			if ( (length($lotGresult{SOURCE_LOT}) > 0 && $lotGresult{SOURCE_LOT} ne $ppLot{sourceLot}) )
			{
				$fabSourceLot = &checkSourceLot($lotGresult{SOURCE_LOT}, $ref->{MaterialLotFab}); 
				WARN( "Incorrect source lot \"$ppLot{sourceLot}\" for pp_lot \"$ref->{MaterialLotID}\".  Substituting source lot \"$fabSourceLot\"");
				$sourceLots{$ref->{MaterialLotID}} = $fabSourceLot;
				$sourceFabs{$ref->{MaterialLotID}} = $ref->{MaterialLotFab};
				($exensioWaferID, $waferScribe) = &checkWaferID($fabSourceLot, $ref->{FromWaferNumber}, $waferScribe, $ref->{MaterialLotFab}, $ref->{MaterialLotID});
				$fabSourceLot .= ".S"; 
			}
			elsif( length($ppLot{sourceLot}) > 0 && $ppLot{sourceLot} ne "N/A")
			{
				$fabSourceLot   = &checkSourceLot($ppLot{sourceLot}, $ref->{MaterialLotFab});
				$sourceLots{$ref->{MaterialLotID}} = $fabSourceLot;
				$sourceFabs{$ref->{MaterialLotID}} = $ref->{MaterialLotFab};
				($exensioWaferID, $waferScribe) = &checkWaferID($fabSourceLot, $ref->{FromWaferNumber}, $waferScribe, $ref->{MaterialLotFab}, $ref->{MaterialLotID});
				$fabSourceLot .= ".S"; 
			}
			else
			{
				if ( length($ref->{MaterialLotID}) > 8 && ( $ref->{MaterialLotFab} eq "KRH" || $ref->{MaterialLotFab} eq "KRG" ))
				{
					WARN("Source lot not found for lot \"$ref->{MaterialLotID}\", fab \"$ref->{MaterialLotFab}\".  Truncating material lot to 8 characters to retry");
					my $truncLot = substr($ref->{MaterialLotID}, 0, 8);
					$wsCall = $ppLotProdWSURL.$truncLot;
					INFO( "WS xfcsfabx Call: $wsCall");
					my %ppLot = getMetaFromRefDbWS($wsCall);
					if ($ppLot{status} =~ /no_data|error/i )
					{
						WARN("Source lot not found for lot \"$truncLot\", fab \"$ref->{MaterialLotFab}\".  Using $truncLot as source lot");
						$fabSourceLot   = $truncLot.".S";
						$sourceLots{$truncLot} = $ppLot{sourceLot};
						$sourceFabs{$truncLot} = $ref->{MaterialLotFab};
						($exensioWaferID, $waferScribe) = &checkWaferID($truncLot, $ref->{FromWaferNumber}, $waferScribe, $ref->{MaterialLotFab}, $ref->{MaterialLotID});
					}
					else
					{
						$fabSourceLot   = $ppLot{sourceLot}.".S";
						$sourceLots{$truncLot} = $ppLot{sourceLot};
						$sourceFabs{$truncLot} = $ref->{MaterialLotFab};
						($exensioWaferID, $waferScribe) = &checkWaferID($ppLot{sourceLot}, $ref->{FromWaferNumber}, $waferScribe, $ref->{MaterialLotFab}, $ref->{MaterialLotID});
					}
				}
				else
				{
					WARN("Source lot not found for lot \"$ref->{MaterialLotID}\".  Using material lot for source lot");
					$fabSourceLot   = $ref->{MaterialLotID}.".S";
					$sourceLots{$ref->{MaterialLotID}} = $ref->{MaterialLotID};
					$sourceFabs{$ref->{MaterialLotID}} = $ref->{MaterialLotFab};
					($exensioWaferID, $waferScribe) = &checkWaferID($ref->{MaterialLotID}, $ref->{FromWaferNumber}, $waferScribe, $ref->{MaterialLotFab}, $ref->{MaterialLotID});
				}
			}
		}
		else
		{
			$fabSourceLot   = &checkSourceLot($ppLot{sourceLot}, $ref->{MaterialLotFab});
			($exensioWaferID, $waferScribe) = &checkWaferID($fabSourceLot, $ref->{FromWaferNumber}, $waferScribe, $ref->{MaterialLotFab}, $ref->{MaterialLotID});
			if ( $ref->{MaterialLotFab} ne $ppLot{fab} )
			{
				WARN("MaterialLotFab \"$ref->{MaterialLotFab}\" doesn't match PP_PROD fab \"$ppLot{fab}\".");
			}
			$sourceLots{$ref->{MaterialLotID}} = $fabSourceLot;
			$sourceFabs{$ref->{MaterialLotID}} = $ref->{MaterialLotFab};
			$fabSourceLot  .= ".S";
		}
	}
	else
	{
		# Look up source lot and fab using web service ON_LOT table call
		$wsCall = $onLotWSURL.$ref->{MaterialLotID};
		INFO( "WS legonfab Call: $wsCall");
		my %onLot = getMetaFromRefDbWS($wsCall);
		#INFO( "WS legonfab status: \"$onLot{status}\"");
		if ($onLot{status} =~ /no_data|error/i || length($onLot{sourceLot}) == 0) 
		{
			WARN("ON_LOT WS call for $ref->{MaterialLotID} returned no results ($wsCall), checking LOTG");
			# Go to LOTG
			my %lotGresult = &lotGLookup($ref->{MaterialLotID});
			if ( defined(%lotGresult{SOURCE_LOT}) )
			{
				$fabSourceLot = &checkSourceLot($lotGresult{SOURCE_LOT}, $lotGresult{FAB}); 
				INFO( "Found source lot \"$fabSourceLot\" for lot \"$ref->{MaterialLotID}\"., fab \"$lotGresult{FAB}\"");
				if ( length($ref->{MaterialLotFab}) == 0 && length($lotGresult{FAB}) > 0)
				{
					# LOTG returns FAB:DESCRIPTION, need only FAB
					($fabID) = split(/:/, $lotGresult{FAB});
					INFO("Camstar material lot \"$ref->{MaterialLotID}\" fab not defined, substituting \"$fabID\" from ON_LOT");
					$ref->{MaterialLotFab} = $fabID;
				}
			}
			else
			{
				WARN("LOTG lookup for \"$ref->{MaterialLotID}\" returned no results.  Using \"$ref->{MaterialLotID}\" for source lot");
				$fabSourceLot = &checkSourceLot($ref->{MaterialLotID}, $ref->{MaterialLotFab});
			}
		}
		elsif( $onLot{fab} eq "SBN" or $onLot{fab} eq "ISMFAB" or $onLot{fab} eq "UMC" or $ref->{MaterialLotFab} eq "LFOUNDRY")
		{
			# Earlier versions of the WS query to LOTG returned bad results for lots from SBN/ISMF and UMC
			# That version of the query also has problems with HAINA fab
			# Override fab ID with LFOUNDRY if LOTG returns UVA.  UVA is finishing site but LFOUNDRY is actual fab
			if ( $ref->{MaterialLotFab} eq "LFOUNDRY" && $onLot{fab} eq "UVA" )
			{
				$fabID = $ref->{MaterialLotFab};
			}
			else
			{
				($fabID) = split(/:/,  $onLot{fab});
			}
				
			my %lotGresult = &lotGLookup($ref->{MaterialLotID});
			if ( ($lotGresult{SOURCE_LOT} ne $onLot{sourceLot}) )
			{
				WARN( "Incorrect source lot \"$onLot{sourceLot}\" for lot \"$ref->{MaterialLotID}\".  Substituting source lot \"$lotGresult{SOURCE_LOT}\"");
				($fabID) = split(/:/, $lotGresult{FAB});
				$fabSourceLot = &checkSourceLot($lotGresult{SOURCE_LOT}, $fabID); 
			}
			else
			{
				$fabSourceLot = &checkSourceLot($onLot{sourceLot}, $fabID);
			}
		}
		else
		{
			$fabSourceLot = $onLot{sourceLot};
			if ( length($ref->{MaterialLotFab}) == 0 && length($onLot{fab}) > 0)
			{
				INFO("Camstar material lot \"$ref->{MaterialLotID}\" fab not defined, substituting \"$onLot{fab}\" from ON_LOT");
				$ref->{MaterialLotFab} = $onLot{fab};
			}
			elsif ( $ref->{MaterialLotFab} ne $onLot{fab} )
			{
				WARN("MaterialLotFab \"$ref->{MaterialLotFab}\" doesn't match ON_LOT fab \"$onLot{fab}\" for lot \"$ref->{AssemblyLot}\" + wafer \"$waferScribe\".");
			}
		}
		# Trim source lot returned depending on fab.  LOTG query v21 should handle this for UV5, USR, USU, CZ4, ISMF, and JND fabs
		$fabSourceLot =~ s/\.S$//;
		my $oldSrcLot = $fabSourceLot;
		$fabSourceLot = &checkSourceLot($fabSourceLot, $ref->{MaterialLotFab});
		($exensioWaferID, $waferScribe) = &checkWaferID( $fabSourceLot, $ref->{FromWaferNumber}, $waferScribe, $ref->{MaterialLotFab}, $ref->{MaterialLotID});
		# Wafer IDs differ by site
		$sourceLots{$ref->{MaterialLotID}} = $fabSourceLot;
		$fabSourceLot .= ".S";
		if (length($fabID) == 0)
		{
			$sourceFabs{$ref->{MaterialLotID}} = $ref->{MaterialLotFab};
		}
		else
		{
			$sourceFabs{$ref->{MaterialLotID}} = $fabID;
		}

		$assemblySourceLot = &checkAssemblySourceLot($ref->{AssemblyLot}, $assemblySourceLot, $fabSourceLot, $ref->{MaterialLotFab});
	}

	if ( $sourceLots{$ref->{AssemblyLot}} eq "GET" )
	{
		$assemblySourceLot = $sourceLots{$ref->{MaterialLotID}}.".S";
		$sourceLots{$ref->{AssemblyLot}} = substr($assemblySourceLot, 0, -2);
	}
	
	if ( length($fabID) == 0 )
	{
		$fabID = $ref->{MaterialLotFab};
	}
	
	# Look up fromFab using fab code returned by Camstar
	#if ( exists $fabCodes{$ref->{MaterialLotFab}} )
	if ( exists $fabCodes{$fabID} )
	{
		$fromFab = $fabID.":".$fabCodes{$fabID};
	}
	else
	{
		WARN("Fab code \"$fabID\" not found in DWPRD");
		if ( length($ref->{MaterialLotFab}) == 0 )
		{
			$fromFab = "NA";
		}
		else
		{
			$fromFab = $ref->{MaterialLotFab};
		}
	}

        $genEventName = $ref->{AssemblyLot}.'_'.$ref->{SpecName}.'_'.$fabSourceLot;
	my $strippedDT = $ref->{txnDate};
	$strippedDT =~ s/[: -]//g;
	$traceEventName = $ref->{AssemblyLot}.':'.$fabSourceLot.':'.$exensioWaferID.':'.$strippedDT;

	if ( exists $genInfo{$genEventName} )
	{
		$genLine = $genInfo{$genEventName};
	}
	else
	{
		$genLine = "AWGEN|$ref->{SpecName}|$ref->{txnDate}|$genEventName|$assemblySourceLot|$ref->{AssemblyLot}|$ref->{LotType}|$ref->{ProductName}|".
                           "$assemblyPartCount|$fromFab|$ref->{MaterialPartName}|$fabSourceLot|$ref->{MaterialLotID}";
	}
	# Add the wafers to the genealogy line
	$genLine = $genLine . "|$exensioWaferID|$ref->{FromWaferNumber}";
	$traceLine = "$ref->{AssemblyLot}|$assemblyPartCount|$assemblySourceLot|$ref->{LotType}|$ref->{ProductName}|$ref->{txnDate}|$ref->{MaterialPartName}|".
                     "$fabSourceLot|$exensioWaferID|$ref->{FromWaferNumber}|$fromFab|$ref->{MaterialLotID}|$waferScribe|".
                     "$fabPartCount|$fabPartRequired|$consumeFactor|$ref->{MaterialLotName}|$ref->{SpecName}";

	# Don't add line of wafer ID is empty
	if (length($exensioWaferID) > 0 && length($fabSourceLot) > 0 && $fabSourceLot ne ".S" )
	{
		$rowsKept++; # Count successfully processed rows
		$genInfo{$genEventName}   = $genLine;
		$traceInfo{$traceEventName} = $traceLine;
	}
	else
	{
		$rowsSkipped++; # Count rows that didn't pass validation
		WARN("Consumption record will not be written for assembly lot $ref->{AssemblyLot}.  Invalid wafer scribe $ref->{FromWaferScribeNumber}");
	}
}
INFO("DONE.  Writing out Results.");
$dbhMSSQL->disconnect;
#my $outputGenDir    = $hOptions{OUT_GEN};
#my $outputTraceDir  = $hOptions{OUT_TRACE};
#my $archiveGenDir   = $hOptions{ARCHIVE_GEN};
#my $archiveTraceDir = $hOptions{ARCHIVE_TRACE};
my $genFile = "Assembly2Wafer.$sourceDB.$currentDateTime.a2wgen";
my $genRowsWritten = 0;
my $traceRowsWritten = 0;

INFO("\nGenealogy records:");
open OUT, ">$outputGenDir/tmp/$genFile" or dpExit(1,"Cannot write $outputGenDir/tmp/$genFile");
foreach my $k (sort keys %genInfo) 
{
	#INFO( "$k => $genInfo{$k}" );
	print OUT "$genInfo{$k}\n";
}
close OUT;
# GZIP gen file
gzip "$outputGenDir/tmp/$genFile" => "$outputGenDir/tmp/$genFile.gz" or dpExit(1, "Failed to gzip $outputGenDir/tmp/$genFile");
# Copy gzip'd file to archive and move to outgoing folders
copy("$outputGenDir/tmp/$genFile.gz",$archiveGenDir);
move("$outputGenDir/tmp/$genFile.gz",$outputGenDir);

INFO("\nTrace records:");
# For assembly2wafer program, need a separate file for each assembly lot
# For wafer2assembly program, need a separate file for each fab source lot
my $assemblyLot;
my $traceFile;
my $traceLotFile;
my @csv_files;
foreach my $k (sort keys %traceInfo) 
{
	($assemblyLot, $fabSourceLot, $exensioWaferID, $dt) = split(/:/, $k);
	#INFO( "$assemblyLot, $k => $traceInfo{$k}" );
	$traceLotFile = "Assembly2Wafer.$sourceDB.$currentDateTime.$assemblyLot.$dt.a2w.csv";
	$traceFile = "$outputTraceDir/tmp/$traceLotFile";
	if ( not -w $traceFile )
	{
		open OUT, ">$traceFile" or dpExit(1,"Cannot write $traceFile");
		print OUT "$class50Header\n";
		push @csv_files, $traceLotFile;
	}
	else
	{
		open OUT, ">>$traceFile" or dpExit(1,"Cannot write $traceFile");
	}
	print OUT "$traceInfo{$k}\n";
	close OUT;

	$fabSourceLot = substr($fabSourceLot,0,-2);
	$traceLotFile = "Wafer2Assembly.$sourceDB.$currentDateTime.$fabSourceLot.$dt.w2a.csv";
	$traceFile = "$outputTraceDir/tmp/$traceLotFile";
	if ( not -w $traceFile )
	{
		open OUT, ">$traceFile" or dpExit(1,"Cannot write $traceFile");
		print OUT "$class50Header\n";
		push @csv_files, $traceLotFile;
	}
	else
	{
		open OUT, ">>$traceFile" or dpExit(1,"Cannot write $traceFile");
	}
	print OUT "$traceInfo{$k}\n";
	close OUT;
}

# Copy to archive and move to outgoing folders
#copy("$outputTraceDir/tmp/$traceFile",$archiveTraceDir);
#move("$outputTraceDir/tmp/$traceFile",$outputTraceDir);
foreach my $fileName (@csv_files)
{
	my $sourceFile = "$outputTraceDir/tmp/$fileName";
	# GZIP the file first
	gzip $sourceFile => "$sourceFile.gz";
	unlink($sourceFile);
	$sourceFile = "$sourceFile.gz";

	my $targetFinal = "$outputTraceDir/$fileName.gz";
	my $targetArch = "$archiveTraceDir/$fileName.gz";
	copy($sourceFile, $targetArch);
	move($sourceFile, $targetFinal);
}

my $genRowsWritten = scalar(keys %genInfo);
my $traceRowsWritten = scalar(keys %traceInfo);
my $traceFilesWritten = scalar(@csv_files);

# Log total rows extracted and written (combined and separate)
my $totalRowsWritten = $genRowsWritten + $traceRowsWritten;
INFO("Camstar Genealogy/Assembly diagnostics: fetched=$rowsFetched kept=$rowsKept skipped=$rowsSkipped files_written=".($traceFilesWritten + 1));
INFO("Rows Total Count: Extracted=$rowsFetched | Written=$totalRowsWritten | Files=".($traceFilesWritten + 1));
INFO("Rows Detailed: Genealogy=$genRowsWritten | Trace=$traceRowsWritten");

if (defined($hOptions{BENCHMARK_LOG}) && length($hOptions{BENCHMARK_LOG}) > 0)
{
	my $pipelineName = $hOptions{PIPELINE_NAME} || basename($0);
	my $pipelineType = $hOptions{PIPELINE_TYPE} || "batch";
	my $endLocal = DateTime->now(time_zone => 'local')->strftime('%Y-%m-%d %H:%M:%S');
	my $endUtc = DateTime->now(time_zone => 'UTC')->strftime('%Y-%m-%dT%H:%M:%SZ');
	my $elapsed = time() - $startTime;
	my $elapsedHuman = formatElapsed($elapsed);
	
	# Environment detection - mirrored from n_refdata_extract.py (reference implementation)
	# Explicit hostname mapping: usaz15ls082=prod, usaz15ls080=qa, usaz15ls081=dev
	# Or use PIPELINE_ENV override
	my $detectedEnv = "prod";
	my $hostname = lc($ENV{HOSTNAME} || $ENV{COMPUTERNAME} || "unknown");
	if ($hostname =~ /usaz15ls082/) {
		$detectedEnv = "prod";
	} elsif ($hostname =~ /usaz15ls080/) {
		$detectedEnv = "qa";
	} elsif ($hostname =~ /usaz15ls081/) {
		$detectedEnv = "dev";
	} elsif ($hostname =~ /dev|test|uat|stage/) {
		# Fallback pattern matching for other hostnames
		$detectedEnv = ($hostname =~ /dev/) ? "dev" : "test";
	}
	my $environment = $ENV{PIPELINE_ENV} || $detectedEnv;
	
	my $includeNonArchive = $hOptions{BENCHMARK_INCLUDE_NON_ARCHIVE} ? 1 : 0;
	my $genOutFile = "$outputGenDir/$genFile.gz";
	my $genArchFile = "$archiveGenDir/$genFile.gz";
	my @traceOutFiles = map { "$outputTraceDir/$_.gz" } @csv_files;
	my @traceArchFiles = map { "$archiveTraceDir/$_.gz" } @csv_files;
	my $outputFileGen = $includeNonArchive ? $genOutFile : "";
	my $outputFilesGen = [];
	my $outputFileTrace = "";
	my $outputFilesTrace = [];
	if ($includeNonArchive)
	{
		if (scalar(@traceOutFiles) == 1)
		{
			$outputFileTrace = $traceOutFiles[0];
		}
		elsif (scalar(@traceOutFiles) > 1)
		{
			$outputFilesTrace = \@traceOutFiles;
		}
	}
	my $totalRowsWritten = $genRowsWritten + $traceRowsWritten;
	my $totalFiles = $traceFilesWritten + 1;  # genealogy file + trace files
	my %stats = (
		start_local => $startLocal,
		end_local => $endLocal,
		start_utc => $startUtc,
		end_utc => $endUtc,
		elapsed_seconds => sprintf("%.3f", $elapsed),
		elapsed_human => $elapsedHuman,
		output_file => "",
		archived_file => "",
		rowcount => $totalRowsWritten,
		# Align with models.py: rows_extracted = rows from source, rows_written = rows to output files
		rows_extracted => $rowsFetched,
		rows_written => $totalRowsWritten,
		total_files => $totalFiles,
		output_file_gen => $outputFileGen,
		output_files_gen => $outputFilesGen,
		output_file_trace => $outputFileTrace,
		output_files_trace => $outputFilesTrace,
		archived_gen_files => [ $genArchFile ],
		archived_trace_files => \@traceArchFiles,
		# Include diagnostic counters for troubleshooting no-output cases (aligned with E142)
		rows_fetched => $rowsFetched,
		rows_kept => $rowsKept,
		rows_skipped => $rowsSkipped,
		log_file => ($hOptions{LOGFILE} || ""),
		pid => $$,
		date_code => $currentDateTime,
		pipeline_name => $pipelineName,
		script_name => basename($0),
		pipeline_type => $pipelineType,
		environment => $environment,
	);
	writeBenchmark($hOptions{BENCHMARK_LOG}, \%stats);
}


dpExit(0);

##### SUBROUTINES #####

# Get DW fab code to description mapping from DWPRD
sub obs_getFabCodes() {
	my %fabCodes;
	my $dbhDWPRD = DBI->connect("dbi:Oracle:DWPRD", "BIW_EXENSIO_READ", $ENV{DW_PASS});

	if($DBI::errstr) { DpLoad_exit(1,"Unable open DB connection to BIWMES $!"); }
	my $sth=$dbhDWPRD->prepare("select unique MFG_AREA_CD, MFG_AREA_DESC from BIWMARTS.SITE_DIM order by MFG_AREA_CD");
	$sth->execute(); 
	while ( my $recs=$sth->fetchrow_hashref())
	{
		$fabCodes{$recs->{MFG_AREA_CD}} = $recs->{MFG_AREA_DESC};
	}

	$dbhDWPRD->disconnect;
	return %fabCodes;
}

#sub getFabCodes() {
#        my %fabCodes;
#        my $dbh = DBI->connect("dbi:ODBC:MART_SNOWFLAKE", $ENV{SNOW_USER}, $ENV{SNOW_PASS});
#
#        if($DBI::errstr) { DpLoad_exit(1,"Unable open DB connection to SnowFlake $!"); }
#    	$dbh->do("use warehouse $hOptions{SOURCE_WAREHOUSE};");
#        $dbh->do("use database $hOptions{SOURCE_SCHEMA};");
#
#        my $sql ="SELECT distinct sd.mfg_area_code as MFG_AREA_CD, sd.mfg_area_description as MFG_AREA_DESC
#                  FROM enterprise.site_dim sd
#                  WHERE mfg_area_code != 'N/A'
#                  AND  mfg_area_code IS NOT NULL
#                  ORDER BY mfg_area_code";
#
#        my $sth=$dbh->prepare($sql);
#        $sth->execute();
#        while ( my $recs=$sth->fetchrow_hashref())
#        {
#                $fabCodes{$recs->{MFG_AREA_CD}} = $recs->{MFG_AREA_DESC};
#        }
#
#        $dbh->disconnect;
#        return %fabCodes;
#}
sub getFabCodes {
    my %fabCodes;
	my $snowUser = $ENV{SNOW_USER} || $ENV{SNOWFLAKE_USER} || "MFG_PRD_RPT_EXENSIO_USER";
	my $snowPass = $ENV{SNOW_PASSWORD} || $ENV{SNOW_PASS} || $ENV{SNOWFLAKE_PASSWORD} || "";
	my $snowSid  = $ENV{SNOW_SID} || $ENV{SNOWFLAKE_DSN} || "MART_SNOWFLAKE";
	my $dbh = DBI->connect("dbi:ODBC:$snowSid", $snowUser, $snowPass);
        my $schema = $hOptions{SOURCE_SCHEMA};
        my $fabCodesDb = "";
        my $siteDimTable = "ANALYTICSPRD.ENTERPRISE.SITE_DIM";

		if ($schema =~ /^(\w+)\./) {
			$fabCodesDb = $1;
			$fabCodesDb = "${fabCodesDb}.ENTERPRISE";
			$siteDimTable = "${fabCodesDb}.SITE_DIM";
		}

    # Check for connection errors
    if ($DBI::errstr) {
        DpLoad_exit(1, "Unable to open DB connection to SnowFlake: $DBI::errstr");
    }

    # Use warehouse and database
    eval {
		$dbh->do("use warehouse $hOptions{SOURCE_WAREHOUSE};");
		if (defined($fabCodesDb) && length($fabCodesDb) > 0)
		{
			$dbh->do("use database $fabCodesDb;");
		}
    };
    if ($@) {
        DpLoad_exit(1, "Error using warehouse/database: $@");
    }

    # Prepare and execute SQL query
	my $sql = "SELECT DISTINCT sd.mfg_area_code AS MFG_AREA_CD, sd.mfg_area_description AS MFG_AREA_DESC
			   FROM $siteDimTable sd
               WHERE mfg_area_code != 'N/A'
               AND mfg_area_code IS NOT NULL
               ORDER BY mfg_area_code";
    my $sth = $dbh->prepare($sql);
    $sth->execute();

    # Fetch results and populate hash
    while (my $recs = $sth->fetchrow_hashref()) {
        $fabCodes{$recs->{MFG_AREA_CD}} = $recs->{MFG_AREA_DESC};
    }

    # Disconnect from database
    $dbh->disconnect;
    return %fabCodes;
}

sub odsConnect() {
        my $ds = shift;
        my $user = shift;
        my $pass = shift;

        my $dbh = DBI->connect($ds, $user, $pass, {PrintError => 0});
        if (!defined($dbh)) {
                ERROR("Error connecting to DSN '$ds'");
                ERROR("Error was: $DBI::errstr");
                dpExit(1, "Error connecting to DSN '$ds' | $DBI::errstr");
                #return 0;
        }
        return($dbh);
}

sub writeBenchmark()
{
	my $path = shift;
	my $statsRef = shift;
	$path = normalizeBenchmarkPath($path);
	return if (!defined($path) || length($path) == 0);

	my $dir = dirname($path);
	if (defined($dir) && length($dir) > 0 && !-d $dir)
	{
		mkdir($dir);
	}
	my $json = JSON::PP->new->utf8->encode($statsRef);
	if (open(my $fh, ">>", $path))
	{
		print $fh $json."\n";
		close($fh);
		INFO("Benchmark logged to $path");
	}
	else
	{
		WARN("Could not write benchmark log $path: $!");
	}
}

sub formatElapsed()
{
	my $seconds = shift;
	$seconds = 0 if (!defined($seconds) || $seconds < 0);
	my $total = int($seconds + 0.5);
	my $hours = int($total / 3600);
	my $minutes = int(($total % 3600) / 60);
	my $secs = $total % 60;
	my @parts;
	push @parts, "${hours}h" if $hours > 0;
	push @parts, "${minutes}m" if ($minutes > 0 || $hours > 0);
	push @parts, "${secs}s";
	return join(" ", @parts);
}

sub normalizeBenchmarkPath()
{
	my $path = shift;
	return "" if (!defined($path) || length($path) == 0);
	if (-d $path || $path =~ /[\\\/]$/)
	{
		return File::Spec->catfile($path, "benchmark.jsonl");
	}
	if ($path !~ /\.jsonl$/i && $path !~ /\.[A-Za-z0-9]+$/)
	{
		return File::Spec->catfile($path, "benchmark.jsonl");
	}
	return $path;
}

sub getSQL() {
	my $source = shift;
	my $lotTypeSelect = "";
	my $lotTypeJoin   = "";
	my $materialLotSelect = "";
	my $schema = "";
	if ( $source eq "SBN" || $source eq "OSPI" )
	{
		$schema = "MES_SChema.";
	}

	if ( $source eq "ONSZ" || $source eq "CEBU" )
	{
		$lotTypeSelect = "case when hm.ownername like 'ON%' and Len(hm.OwnerName) = 4 then SUBSTRING(hm.OwnerName, 3, 2) else hm.OwnerName end";
		$materialLotSelect = "substring(hd.MaterialLotName, 1, case when patindex('%-%', hd.MaterialLotName) = 0 then 40 else patindex('%-%', hd.MaterialLotName)-1 end)";
	}
	else
	{
		$lotTypeSelect = "t.onsLotTypeName"; 
		$lotTypeJoin   = "left join ${schema}onsLotType t on a.onsLotTypeId = t.onsLotTypeId";
		$materialLotSelect = "coalesce(am.onsSourceLotId, am.FabLotNumber)"; #"am.onsSourceLotId";
	}

	my $sqlStr = "with ConsumeActivityLots as
(
select distinct hm.Containerid, hm.ContainerName
from ${schema}historymainline hm
where hm.txnDate between dateadd(hour, -1*$startHours, getdate()) and dateadd(hour, -1*$endHours, getdate())
/*where (hm.txndate between '2/14/2023' and '3/27/2023' )*/
/*where hm.ContainerName = 'P002455105'*/
  and exists(select 1 from ${schema}A_ConsumeMaterialsHistory cmh 
             join ${schema}A_ConsumeMaterialsHistoryDetai hd on hd.ConsumeMaterialsHistoryID = cmh.ConsumeMaterialsHistoryID
             join ${schema}A_ConsumeMaterialsHistoryWafer amh on amh.ConsumeMaterialsHistoryDetaiId = hd.ConsumeMaterialsHistoryDetaiId
             where cmh.historyid = hm.historyid and cmh.historymainlineid = hm.historymainlineid)
)
select hm.ContainerName as AssemblyLot
, $lotTypeSelect as LotType
, hm.ProductName
, hm.historyid
, hm.Qty as AssemblyQty
, convert(varchar(19), hm.txnDate, 120) as txnDate
, am.FabLotNumber+'.S' as  FromExensioSourceLot
, case when patindex('%[ -]%', amh.FromWaferScribeNumber) = 0 then amh.FromWaferScribeNumber
  else substring(substring(amh.FromWaferScribeNumber,patindex('%[^ -][^ -][^ -][^ -]%',amh.FromWaferScribeNumber),30),1,patindex('%[ -]%',substring(amh.FromWaferScribeNumber,patindex('%[^ -][^ -][^ -][^ -]%',amh.FromWaferScribeNumber),30))-1)+'_'+case when len(amh.FromWaferNumber) = 1 then '0' else '' end +amh.FromWaferNumber
  end as FromExensioWaferID
, case when len(amh.FromWaferNumber) = 1 then '0' else '' end +amh.FromWaferNumber as FromWaferNumber
, case when am.FabPlant in ( 'MY2', 'ISMF' ) then 'ISMFAB' else am.FabPlant end as MaterialLotFab
, am.FabLotNumber
, max($materialLotSelect) as MaterialLotID
, amh.FromWaferScribeNumber
, sum(amh.QtyConsumed) as QtyConsumed
/* QtyRequired isn't set for all Camstar sites, but ConsumeFactor is*/
, case when hd.QtyRequired != 0 then hd.QtyRequired else hm.Qty * hd.ConsumeFactor end as QtyRequired
, hd.ConsumeFactor
, max(hd.MaterialLotName) as MaterialLotName
, hd.MaterialPartName, hm.SpecName
from ConsumeActivityLots al
join ${schema}historymainline hm on hm.HistoryId = al.containerid and hm.ContainerId = al.ContainerId
left join ${schema}A_Lotattributes a on al.ContainerId = a.ContainerId
join ${schema}A_ConsumeMaterialsHistory h on h.historyId = hm.historyid and h.historymainlineid = hm.historymainlineid
join ${schema}A_ConsumeMaterialsHistoryDetai hd on hd.ConsumeMaterialsHistoryID = h.ConsumeMaterialsHistoryID
join ${schema}A_ConsumeMaterialsHistoryWafer amh on amh.ConsumeMaterialsHistoryDetaiId = hd.ConsumeMaterialsHistoryDetaiId
join ${schema}A_LotAttributes am on hd.MaterialLotId = am.ContainerId
$lotTypeJoin
where $materialLotSelect is not null 
group by hm.ContainerName, $lotTypeSelect, hm.ProductName, hm.historyid, hm.Qty, convert(varchar(19), hm.txnDate, 120) , am.FabLotNumber+'.S'
       , case when patindex('%[ -]%', amh.FromWaferScribeNumber) = 0 then amh.FromWaferScribeNumber
              else substring(substring(amh.FromWaferScribeNumber,patindex('%[^ -][^ -][^ -][^ -]%',amh.FromWaferScribeNumber),30),1,patindex('%[ -]%',substring(amh.FromWaferScribeNumber,patindex('%[^ -][^ -][^ -][^ -]%',amh.FromWaferScribeNumber),30))-1) +'_'+case when len(amh.FromWaferNumber) = 1 then '0' else '' end +amh.FromWaferNumber
         end
       , case when len(amh.FromWaferNumber) = 1 then '0' else '' end +amh.FromWaferNumber
       , case when am.FabPlant in ( 'MY2', 'ISMF' ) then 'ISMFAB' else am.FabPlant end
       , am.FabLotNumber, amh.FromWaferScribeNumber
       , case when hd.QtyRequired != 0 then hd.QtyRequired else hm.Qty * hd.ConsumeFactor end
       , hd.ConsumeFactor, hd.MaterialPartName, hm.SpecName
order by hm.ProductName, hm.ContainerName, hd.MaterialPartName, amh.FromWaferScribeNumber";

INFO($sqlStr);
	return($sqlStr);
}

sub checkAssemblySourceLot() 
{
	my $assemblyLot = shift;
	my $assemblySourceLot = shift;
	my $fabSourceLot = shift;
	my $fabID = shift;
	my $str;
	# Some assembly lots don't trace source lot back to fab properly, resulting in an incorrect source lot.  Check here.
	$str = &checkSourceLot(substr($assemblySourceLot, 0, -2), $fabID) . ".S";
	if ( $str eq $fabSourceLot && $assemblySourceLot ne $fabSourceLot )
	{
		INFO("Changing assembly source lot \"$assemblySourceLot\" to \"$str\"");
		$assemblySourceLot = $str;
		$sourceLots{$assemblyLot} = substr($assemblySourceLot, 0, -2);
	}
	return($assemblySourceLot);
}

sub checkWaferID()
{
	my $sourceLot = shift;
	my $waferNum = shift;
	my $waferScribe = shift;
	my $fabID = shift;
	my $materialLotID = shift;
	my $waferID;

	if ( exists ($fFairchildFabs{$fabID}))
	{
		$waferID = $sourceLot . "_" . $waferNum;
	}
	else
	{
		if ( $fabID eq "USR" || $fabID eq "UV5" || $fabID eq "JND" || length($fabID) == 0 )
		{
			# check for UV5(EFK) fab and scribe ID containing spaces, and do not write the record if that condition is found.
			if ( $fabID eq "UV5" and $waferScribe =~ /\s/ )
			{
				# See if scribe ID was previously found in UMR
				if (defined($scribeIDs{$sourceLot}{$waferNum}))
				{
					$waferID = $scribeIDs{$sourceLot}{$waferNum};
					INFO( "Material lot ID $materialLotID consumes invalid UV5/EFK scribe ID \"$waferScribe\". Replacing with scribe $waferID (found existing in hash)");
					$waferScribe = $waferID;
				}
				else
				{
					# Lookup up EFK scribe in UMR using source lot + wafer number
					my $sql = "SELECT LASERSCRIBE FROM (SELECT UNIQUE LASERSCRIBE, DENSE_RANK() OVER (PARTITION BY MES_LOT_ID, WAFER_NUMBER ORDER BY CREATED_TIME DESC) AS DR ".
						  "FROM UMR.UMR_WAFER_MAP_MD_VALUES ".
                                                  "WHERE MES_LOT_ID like '$sourceLot.00%' AND CAST(WAFER_NUMBER as INTEGER) = $waferNum) WHERE DR=1";
					#INFO( "Querying UMR $sql" );
				        my $dbhUMR = DBI->connect("dbi:Oracle:UMRPRD", "umr_ro", $ENV{UMR_PASS});

				        if($DBI::errstr) { DpLoad_exit(1,"Unable open DB connection to UMRPRD $!"); }
				        my $sth=$dbhUMR->prepare($sql);
				        $sth->execute();
					my $laserscribe = "";
				        while ( my $recs=$sth->fetchrow_hashref())
					{
						$laserscribe = $recs->{LASERSCRIBE};
					}

			                if (length($laserscribe) == 0 )
			                {
			                        WARN("Failed to find UV5/EFK scribe in UMR for $materialLotID $sourceLot.00N wafer number $waferNum");
						$waferID = "";
			                }
					else
					{
						WARN("Material lot ID $materialLotID consumes invalid UV5/EFK scribe ID \"$waferScribe\". Replacing with scribe $laserscribe");
						$waferID = $laserscribe;
						$waferScribe = $laserscribe;

						# Save scribe as source lot + wafer to avoid future lookups to UMR.
						if (defined($scribeIDs{$sourceLot}))
						{
							$scribeIDs{$sourceLot}{$waferNum} = $laserscribe;
						}
						else
						{
							$scribeIDs{$sourceLot} = { $waferNum => $laserscribe };
						}
					}
				}
			}
			else
			{
				# Wafer ID = wafer scribe
				$waferID = $waferScribe;
			}
		}
		elsif ( $fabID eq "CZ4" || $fabID =~ /^ISMF/ ||  $fabID eq "USU" || $fabID eq "BE2" )
		{
			# Wafer number prefixed with W
			$waferID = $sourceLot . "-W" . $waferNum;
		}
		else
		{
			# Lot-wafer
			$waferID = $sourceLot . "-" . $waferNum;
		}
	}

	return ($waferID, $waferScribe);	
}

sub checkSourceLot()
{
	my $sourceLot = shift;
	my $fabID = shift;
	my $newSourceLot = $sourceLot;

	if ( $fabID =~ "^USR.*" && length($sourceLot) > 8)
	{
		$newSourceLot = substr($sourceLot, 0, 8);	
	}
	elsif ( $fabID =~ "^UV5.*" && $sourceLot =~ /.+\.0\d\d$/ && length($sourceLot) > 5)
	{
		$newSourceLot = substr($sourceLot, 0, length($sourceLot) - 4);
	}
	elsif ( ($fabID =~ "^CZ4.*" || $fabID eq "ISMFAB" || $fabID eq "LFOUNDRY") && length($sourceLot) > 7)
	{
		$newSourceLot = substr($sourceLot, 0, 7);	
	}
	elsif ( $fabID =~ "^JND.*" && $sourceLot =~ /^.+0\d$/ && length($sourceLot) > 8 )
	{
		$newSourceLot = substr($sourceLot, 0, 8);	
	}
	elsif ( ($fabID =~ "^KRI.*" || $fabID =~ "^KRH.*" || $fabID =~ "^KRG.*" ) && length($sourceLot) > 8)
	{
		$newSourceLot = substr($sourceLot, 0, 8);	
	}
	#elsif ( ($fabID =~ "^USU.*" || $fabID =~ "^ISA" ) && length($sourceLot) > 6)
	elsif ( ($fabID =~ "^USU.*"  ) && length($sourceLot) > 6)
	{
		$newSourceLot = substr($sourceLot, 0, 6);	
	}
	elsif ( $fabID =~ "^TWQ.*" && length($sourceLot) > 5)
	{
		$newSourceLot = substr($sourceLot, 0, 5);	
	}
	return $newSourceLot;
}

# Bypass web service call when needed
sub lotGLookup() {
	my $lotid = shift;
	
	my $dbhLOTGPRD = DBI->connect("dbi:Oracle:LOTGPRD", "LOTG_READ", $ENV{LOTG_PASS});

	if($DBI::errstr) { DpLoad_exit(1,"Unable open DB connection to LOTG $!"); }
	my $sth=$dbhLOTGPRD->prepare("WITH src_tgt_xref_with as
(
SELECT /* +INLINE */
  FROM_BANK_CODE,
  TO_BANK_CODE,
  REVERSAL_FLAG,
  FK_GENEALOGY_MAFK AS PARENT_PART_ID,
  FK_GENEALOGY_MACLA AS PARENT_LOT_CLASS,
  FK_GENEALOGY_MAIDE AS PARENT_LOT_NUM,
  FK_GENEALOGY_MANOD AS PARENT_TRANSDATE,
  FK_GENEALOGY_MANOT AS PARENT_TRANSTIME,
  FK0GENEALOGY_MAFK  AS PART_ID,
  FK0GENEALOGY_MACLA AS LOT_CLASS,
  FK0GENEALOGY_MAIDE AS LOT_NUM,
  FK1GENEALOGY_MANOD AS TRANSDATE,
  FK1GENEALOGY_MANOT AS TRANSTIME,
  POST_DATE,
  POST_TIME
, to_char((cast(FK1GENEALOGY_MANOD as TIMESTAMP) + (TO_TIMESTAMP(substr(FK1GENEALOGY_MANOT,1,4),'HH24MI')-trunc(TO_TIMESTAMP(substr(FK1GENEALOGY_MANOT,1,4),'HH24MI'))+(cast(substr(FK1GENEALOGY_MANOT, 5, 4) as real)/100)*interval '1'second)), 'YYYY-MM-DD HH24:MI:SS.FF' ) as TRANS_DT
, to_char((cast(FK_GENEALOGY_MANOD as TIMESTAMP) + (TO_TIMESTAMP(substr(FK_GENEALOGY_MANOT,1,4),'HH24MI')-trunc(TO_TIMESTAMP(substr(FK_GENEALOGY_MANOT,1,4),'HH24MI'))+(cast(substr(FK_GENEALOGY_MANOT, 5, 4) as real)/100)*interval '1'second)), 'YYYY-MM-DD HH24:MI:SS.FF') as PARENT_TRANS_DT
, (POST_DATE + (TO_TIMESTAMP(substr(POST_TIME,1,4),'HH24MI')-trunc(TO_TIMESTAMP(substr(POST_TIME,1,4),'HH24MI'))+(cast(substr(POST_TIME, 5, 4) as real)/100)*interval '1'second)) as POST_DT
  FROM LOTG_OWNER.SRC_TGT_XREF 
)
/* min_trans_date_lots finds the earliest transaction for a given lot ID*/
, min_trans_date_lots as
(
SELECT * 
FROM (
SELECT mt.*
, DENSE_RANK() OVER (PARTITION BY LOT_NUM ORDER BY case when ppi.PART_TYPE in ('Wafer Fab Part') then 1 
                                                   when ppi.PART_TYPE in ('Wafer Post Fab Part') then 2 
                                                   when ppi.PART_TYPE in ('WDQ Part') then 3 
                                                   when ppi.PART_TYPE in ('Assembly Part') then 4
                                                   else 5 end, TRANSDATE, TRANSTIME) as LOT_RANK
FROM src_tgt_xref_with mt
LEFT JOIN LOTG_OWNER.PC_ITEM pi on mt.PART_ID = pi.PART_ID
LEFT JOIN LOTG_OWNER.PC_ITEM ppi on mt.PARENT_PART_ID = ppi.PART_ID
/* Don't get genealogy for substrate and epi material */
WHERE pi.PART_TYPE not in ('Substrate Part', 'Ingot Part')
-- Many sites have lot IDs that repeat on 10-year cycles.  Need to avoid colliding with those
and mt.TRANSDATE > sysdate - 10*interval '1' year 
/* Don't get reference/source lot data from bonused/merged transactions */
AND NOT EXISTS(SELECT 1 from src_tgt_xref_with vx where vx.LOT_NUM = mt.LOT_NUM and vx.PARENT_LOT_NUM != mt.PARENT_LOT_NUM 
                        and vx.TRANSDATE = mt.TRANSDATE and vx.TRANSTIME = mt.TRANSTIME and vx.PART_ID = mt.PART_ID and vx.PARENT_PART_ID = mt.PARENT_PART_ID)
) tgt
WHERE tgt.LOT_RANK = 1
)
/* starting_lots determines which lots to retrieve genealogy for*/
, starting_lots as
(
SELECT LOT_NUM, LOT_CLASS, PART_ID 
, PARENT_LOT_NUM
, PARENT_PART_ID, v.PARENT_LOT_CLASS, TRANSDATE, TRANSTIME
FROM min_trans_date_lots v
/*Filter on lot here.  Need up to five lots: 
1. Original lot (no changes)
2. Remove dot (.) if it exists
3. Replace dot (.) with zero (0) 
4. Replace dot (.) with zero (0) AND remove first two characters (in case it is a lot class)
5. *IF* lot ends with .\d+[A-Z], remove dot and remove last character (e.g., RM12016.1F -> RM120161, RM12016.12Q -> RM1201612)
*/
-- Lot KG15Z1UXZAJ can't be traced back to KG15Z1UX in LOTG because the lot is converted from NF lot type to PS after it has already been split to KG15Z1UXZA
-- Regression test lots: VN39B08T (L21480768/HAINA), RM120161 (RM12016/CZ4), LM5082940A (DA35166/ISMF), PN26QF1KX (NB6F7957/JND), N19S90M09 (N0S06040/SBN),
--   21226TD9001.000 (21226TD9001/UV5),J2064102 (GAZ52111/USR),H2581001 (G73010/USU),H5979704 (GAY52079/USR),GZ020041 (H12746/USU), G0101701 (GA010170/USR),
--   FQ839281 (NI11121/BE2), DP483621 (DP48362/ISMFAB), JM6377801 (JM637780/JND), RL874471 (RL87447/CZ4), J1393601 (GA003300/USR), KH25Y8TXAA (KH25Y8TX/KRH),
--   KG224U0X (KG224U0X/KRG), KG246QUAA (KG246QUX/KRG), GZ020041 (H12746/USU), VN39B07M (L21480768/HAINA), VN34A00Q (JOV02933/VN5), L21381199 (LI2021248/HAINA)
--   L21390053A (L21390054/HAINA), L21490187A (L21490187/HAINA), KG2589HXB (KG2589HX/KRG), KG268XMDA (KG268XMX/KRG), KG15Z1UXZAJ (KG15Z1UXZA/KRG), KG2363GXA (KG2363GX/KRG),
--   KG0BGG1BA (KG0BGG1X/KRG), BJN500080 (F6F8881/TSMC), BJP070094 (J13672/USU), CPM2610067 (CPM26100/TSMC), J1121601 (E147301/JND), FR320561 (9563919/LFOUNDRY)
--   FR312191 (9428919/UVA), H2060961 (H20609/XFAB), J5758201 (J12609/USU), RM2911760 (RM29117/CZ4), NL2137601 (NL21376/BE2), PA0H483901 (PA0H4839/JND)
WHERE lot_num in ('$lotid')
/* Exclude transactions where lot and part number don't change, except when it's a starting lot */
AND NOT ( LOT_NUM = PARENT_LOT_NUM AND PART_ID = PARENT_PART_ID 
          AND NOT EXISTS (SELECT 1 from src_tgt_xref_with sl 
                          LEFT JOIN LOTG_OWNER.PC_ITEM pi on sl.PARENT_PART_ID = pi.PART_ID
                          WHERE v.LOT_NUM = sl.LOT_NUM and v.PART_ID = SL.PART_ID
                            AND pi.PART_TYPE not in ('Substrate Part', 'Ingot Part') 
                            AND sl.PARENT_LOT_CLASS NOT IN (SELECT LOTCLASS_CD FROM LOTG_OWNER.LOT_CLASS WHERE DESCRIPTION like '%ORION%')
                            AND NOT EXISTS(SELECT 1 from src_tgt_xref_with vx where vx.LOT_NUM = sl.LOT_NUM and vx.PARENT_LOT_NUM != sl.PARENT_LOT_NUM 
                                           and vx.TRANSDATE = sl.TRANSDATE and vx.TRANSTIME = sl.TRANSTIME and vx.PART_ID = sl.PART_ID and vx.PARENT_PART_ID = sl.PARENT_PART_ID)
                         )
        )
/* Exclude parent lots from the genealogy walk if they are parents in a merge transaction */
AND NOT EXISTS(SELECT 1 from src_tgt_xref_with vx where vx.LOT_NUM = v.LOT_NUM and vx.PARENT_LOT_NUM != v.PARENT_LOT_NUM 
                        and vx.TRANSDATE = v.TRANSDATE and vx.TRANSTIME = v.TRANSTIME and vx.PART_ID = v.PART_ID and vx.PARENT_PART_ID = v.PARENT_PART_ID)
AND v.LOT_RANK = 1
)
, starting_lots_ranked as
(
/* The initial lot_num filter tries several variations of the lot number to match the fab/manufacturing lot to the inventory lot */
/* Give preferential treatment to inventory lots that most closely match the manufacturing lot. */
/*  Those will be inventory lots containing the dot, or longer inventory lot IDs (no prefixes trimmed or characters removed) */ 
select s.*, dense_rank() over (order by case when regexp_like(lot_num, '^.+\.\d\$') then 1 
                                             when exists(select 1 from starting_lots s2 where regexp_like(s2.lot_num, '..'||s.lot_num)) then 4 
                                             when exists(select 1 from starting_lots s2 where length(s2.lot_num) > length(s.lot_num)) then 3 
                                             else 2 end) as sl_dr
from starting_lots s
)
, walk as
(
SELECT /*+ MATERIALIZE */ UNIQUE w.*, ppi.PART_TYPE as PARENT_PART_TYPE
FROM (
SELECT LOT_NUM, LOT_CLASS, PART_ID
, PARENT_LOT_NUM, PARENT_LOT_CLASS, PARENT_PART_ID
, TRANSDATE, TRANSTIME
, TRANS_DT, PARENT_TRANS_DT, LEVEL as LVL
, dense_rank() over (partition by LOT_NUM, PART_ID ORDER BY TO_DATE(substr(PRIOR TRANS_DT, 1, 18), 'YYYY-MM-DD HH24:MI:SS') - TO_DATE(substr(PARENT_TRANS_DT, 1, 18), 'YYYY-MM-DD HH24:MI:SS')) as RNK
FROM (
SELECT v.LOT_NUM, v.LOT_CLASS, v.PART_ID
     , v.PARENT_LOT_NUM as LOTG_PARENT_LOT_NUM
     , COALESCE(t.ORIGINATOR, v.PARENT_LOT_NUM) as PARENT_LOT_NUM
     , v.PARENT_LOT_CLASS
     , v.PARENT_PART_ID
     , TRANS_DT, PARENT_TRANS_DT
     , TRANSDATE, TRANSTIME
FROM src_tgt_xref_with v
LEFT JOIN LOTG_OWNER.ORN_OUT_ORACLE_TRAK t on v.PARENT_LOT_NUM = t.LOT_ID and v.PARENT_PART_ID = t.TARGET_ITEM and t.TARGET_ITEM not like '%-PBU'
LEFT JOIN LOTG_OWNER.ORN_RECEIPTS r on t.ORIGINATOR = r.LOT_NUM and t.TARGET_ITEM = r.PART
-- Exclude parent lots from the genealogy walk if they are parents in a merge transaction
WHERE NOT EXISTS(SELECT 1 from src_tgt_xref_with vx where vx.LOT_NUM = v.LOT_NUM and vx.PARENT_LOT_NUM != v.PARENT_LOT_NUM 
                        and vx.TRANSDATE = v.TRANSDATE and vx.TRANSTIME = v.TRANSTIME and vx.PART_ID = v.PART_ID and vx.PARENT_PART_ID = v.PARENT_PART_ID)
) v
CONNECT BY NOCYCLE (PRIOR PARENT_PART_ID = PART_ID or regexp_substr(PRIOR PARENT_PART_ID, '[^-]+[-]*[^-]+', 1) = regexp_substr(PART_ID, '[^-]+[-]*[^-]+', 1))
               AND PRIOR PARENT_LOT_NUM = LOT_NUM
               AND PRIOR PARENT_TRANS_DT >= TRANS_DT  
               AND NOT(LOT_NUM=PARENT_LOT_NUM AND PART_ID=PARENT_PART_ID AND LOT_CLASS=PARENT_LOT_CLASS)
START WITH EXISTS(SELECT 1 FROM starting_lots_ranked sl 
                  WHERE sl.LOT_NUM = v.LOT_NUM and sl.parent_lot_num = v.LOTG_PARENT_LOT_NUM and sl.TRANSDATE  = v.TRANSDATE and sl.TRANSTIME = v.TRANSTIME and sl.sl_dr = 1
                 )
) w
LEFT JOIN LOTG_OWNER.PC_ITEM ppi on w.PARENT_PART_ID = ppi.PART_ID
WHERE LVL = 1 or ((ppi.PART_TYPE not in ('Substrate Part', 'Ingot Part') and w.PARENT_PART_ID not like '%-BAS'))
)
, translate as (
SELECT UNIQUE 
       w.LOT_NUM as LOT
     , w.LOT_CLASS
     , w.LOT_CLASS as LOT_OWNER
     , w.PART_ID   as PRODUCT
     , COALESCE(cbt.TYPE, 'UNK') as PART_TYPE
     , CASE WHEN w.PARENT_PART_TYPE in ('Substrate Part', 'Ingot Part') THEN LOT_NUM ELSE PARENT_LOT_NUM END as PARENT_LOT
     , w.PARENT_LOT_CLASS
     , CASE WHEN w.PARENT_PART_TYPE in ('Substrate Part', 'Ingot Part') THEN PART_ID ELSE PARENT_PART_ID END as PARENT_PRODUCT
     , w.PARENT_PART_TYPE
     , CASE WHEN w.PARENT_PART_TYPE in ('Substrate Part', 'Ingot Part') THEN 'CHILD' ELSE 'PARENT' END as RELATIONSHIP                      
     , TRANS_DT, PARENT_TRANS_DT
from walk w
left JOIN LOTG_OWNER.LOTG_BOM_TYPE cbt on w.PART_ID = cbt.PART
)
, src_lot_walk as 
(SELECT LOT, PRODUCT
, PARENT_LOT
, PARENT_PRODUCT
, RELATIONSHIP
/* Uncomment below line to prefix lot class to source lot for die-level products
--, CASE WHEN PARENT_PART_TYPE in ('DIE','RS') then PARENT_LOT_CLASS ELSE '' END AS PARENT_LOT_CLASS
-- Comment below line if line above is uncommented*/
, '' as PARENT_LOT_CLASS
, CONNECT_BY_ROOT LOT as TOP
, RANK() OVER (PARTITION BY CONNECT_BY_ROOT LOT ORDER BY TRANS_DT) AS DR
, regexp_substr(PRIOR PARENT_PRODUCT, '[^-]+[-]*[^-]+', 1) as x1
, regexp_substr(PRODUCT, '[^-]+[-]*[^-]+', 1) as x2
FROM translate w
CONNECT BY NOCYCLE (PRIOR PARENT_PRODUCT = PRODUCT AND PRIOR PARENT_LOT = LOT AND NOT (PRODUCT = PARENT_PRODUCT and LOT = PARENT_LOT) and PRIOR PARENT_TRANS_DT >= TRANS_DT)
/* Added FG to accommodate splits in assembly or final test */
START WITH PART_TYPE in ('FG','WFR', 'WAFER', 'DIE','RS','UNK')
)
, src_lot as
( 
SELECT UNIQUE TOP AS LOT
, PARENT_LOT_CLASS||PARENT_LOT AS SOURCE_LOT
, PARENT_PRODUCT as SOURCE_PRODUCT
, RELATIONSHIP
FROM src_lot_walk w
WHERE DR = 1
)
, bom_site as
(
SELECT x.*
     , dense_rank() over (PARTITION by START_PART order by RNK, LVL DESC) as bom_rnk
FROM (
SELECT pba.PART_ID, coalesce(pisa.SITE_ID, pba.SITE_ID)||
CASE WHEN coalesce(pisa.SITE_ID, pba.SITE_ID) IS NULL then '' ELSE ':' END||
CASE WHEN coalesce(pisa.SITE_ID, pba.SITE_ID) = 'BE2' then 'BELGAN FE (ARB)' /* PC_ITEMSITE sometimes has wrong description for BE2 with older parts */
     WHEN pisa.SITE_DESC IS NULL THEN (SELECT MIN(SITE_DESC) FROM LOTG_OWNER.PC_ITEMSITE pis2 WHERE pba.SITE_ID = pis2.SITE_ID) 
ELSE pisa.SITE_DESC END 
as SITE_DESC
, CONNECT_BY_ROOT pba.PART_ID as START_PART
, LEVEL as LVL
, rank() OVER (PARTITION BY pba.PART_ID ORDER BY pba.PREFERENCE_CD, pba.ALTERNATE_BILL, pisa.SITE_DESC) as rnk
FROM LOTG_OWNER.PC_BOM pba
LEFT JOIN LOTG_OWNER.PC_ITEMSITE pisa on pba.PART_ID = pisa.PART_ID AND pba.SITE_ID = pisa.SITE_ID
CONNECT BY NOCYCLE PRIOR COMPONENT_PART_ID = pba.PART_ID AND pba.ITEM_TYPE NOT IN ('Substrate Part', 'Ingot Part')
START WITH pba.PART_ID in (select distinct SOURCE_PRODUCT from src_lot)
) x
WHERE x.rnk = 1
)
, fab_info as
(
SELECT x.LOT_NUM as LOT, x.FROM_BANK_CODE, x.rnk
, CASE 
  WHEN COALESCE(ornr.VENDOR_NAME, mbs.MFG_AREA_DESC) like '%NON%RECORDING%BANK' 
    OR (mbs.MFG_AREA_CD is not null and mbs.MFG_STAGE_CD not in ('FAB','RWF','ADJ','DCY','PP')) /*If the area code for this stage isn't fab, look it up in the BOM */
  THEN COALESCE((select unique SITE_DESC FROM bom_site bs WHERE bs.bom_rnk = 1 and bs.START_PART = x.SOURCE_PRODUCT), 'UNKNOWN')
  ELSE COALESCE(ornr.MFG_AREA_CD, mbs.MFG_AREA_CD)||':'||COALESCE(ornr.VENDOR_NAME, mbs.MFG_AREA_DESC) END as FAB_NAME
, COALESCE(mbs.MFG_STAGE_DESC, 'RECEIPT') as FAB_STAGE
, x.SOURCE_PRODUCT
FROM (SELECT sl.SOURCE_LOT as LOT_NUM, PARENT_LOT_CLASS, TRANSDATE, TRANSTIME, t.TRANSACTION_DT, b.FROM_BANK_CODE, SOURCE_PRODUCT
           , RANK() OVER (PARTITION BY sl.SOURCE_LOT ORDER BY TRANSDATE, TRANSTIME, t.TRANSACTION_DT) as RNK
      FROM src_lot sl
      LEFT JOIN src_tgt_xref_with b on ((sl.RELATIONSHIP = 'CHILD' AND sl.SOURCE_LOT = b.LOT_NUM and sl.SOURCE_PRODUCT = b.PART_ID) 
                                      or (sl.RELATIONSHIP = 'PARENT' AND sl.SOURCE_LOT = b.PARENT_LOT_NUM and sl.SOURCE_PRODUCT = b.PARENT_PART_ID ))
      LEFT JOIN LOTG_OWNER.ORN_OUT_ORACLE_TRAK t on sl.SOURCE_LOT = t.ORIGINATOR
      JOIN LOTG_OWNER.PC_ITEM i on sl.SOURCE_PRODUCT = i.PART_ID
      WHERE i.PART_TYPE not in ('Substrate Part', 'Ingot Part')
      ) x 
LEFT JOIN LOTG_OWNER.MFG_BANK_TO_STAGE mbs on x.FROM_BANK_CODE = mbs.BANK_CD
LEFT JOIN LOTG_OWNER.ORN_RECEIPTS ornr on x.LOT_NUM = ornr.lot_num and x.SOURCE_PRODUCT = ornr.PART
WHERE x.RNK = 1
)
select * from (
SELECT UNIQUE t.LOT
     , t.PARENT_LOT
     , case when regexp_like(t.PRODUCT, '^[^-]+-[^-]+-[^-]+-[^-]+-[^-][^-][^-]\$') then regexp_substr(t.PRODUCT, '^[^-]+-[^-]+-[^-]+-[^-]+') 
            when regexp_like(t.PRODUCT, '^[^-]+-[^-]+-[^-][^-][^-]\$') then regexp_substr(t.PRODUCT, '^[^-]+-[^-]+') 
            when regexp_like(t.PRODUCT, '^[^-]+-[^-][^-][^-]\$') then regexp_substr(t.PRODUCT, '^[^-]+') 
       else t.PRODUCT END as PRODUCT
     , 'NOT AVAILABLE' as LOT_OWNER
     , CASE when regexp_like(t.PARENT_PRODUCT, '^[^-]+-[^-]+-[^-]+-[^-]+-[^-][^-][^-]\$') then regexp_substr(t.PARENT_PRODUCT, '^[^-]+-[^-]+-[^-]+-[^-]+')
            WHEN regexp_like(t.PARENT_PRODUCT, '^[^-]+-[^-]+-[^-][^-][^-]\$') then regexp_substr(t.PARENT_PRODUCT, '^[^-]+-[^-]+') 
            when regexp_like(t.PARENT_PRODUCT, '^[^-]+-[^-][^-][^-]\$') then regexp_substr(t.PARENT_PRODUCT, '^[^-]+') 
            else t.PARENT_PRODUCT END as PARENT_PRODUCT
     , CASE WHEN f.FAB_NAME like 'UV5:%' 
            THEN regexp_replace(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '\.0\d\d\$','',1,1)
            WHEN f.FAB_NAME like 'USR:%'
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 8)
            WHEN f.FAB_NAME like 'USU:%'
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 6)
            WHEN f.FAB_NAME like 'JND:%' and regexp_like(sl.SOURCE_LOT, '^.+0\d\$') 
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 8)
            WHEN (f.FAB_NAME like 'MYD:%' or f.FAB_NAME like 'ISMFAB:%') and regexp_like(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '^.+\.[0-9]+[A-Z]\$') 
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, instr(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '.')-1)
            WHEN f.FAB_NAME like 'CZ4:%' or f.FAB_NAME like 'ISMFAB:%' or f.FAB_NAME like 'UVA:%' or f.FAB_NAME like 'LFOUNDRY:%' 
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 7)
            WHEN (f.FAB_NAME like 'UMC:%' or f.FAB_NAME like 'MYD:%' ) and regexp_like(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '^.+\.[0-9]+\$') 
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, instr(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '.')-1)
            WHEN sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT 
            ELSE t.PARENT_LOT 
       END as SOURCE_LOT
     , CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_PRODUCT ELSE t.PARENT_PRODUCT END as \"WAFER_PART/ALTERNATE_PRODUCT\"
     , f.FAB_NAME as FAB
     , 'NOT AVAILABLE' as LOT_TYPE
     , t.LOT_CLASS 
     , 'NOT AVAILABLE' as MASKSET  /* Need to get from Data Warehouse by product */
     , CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_PRODUCT ELSE t.PARENT_PRODUCT END as \"PRODUCT_CODE\"
     , dense_rank() over (PARTITION by CASE WHEN f.FAB_NAME like 'UV5:%' 
            THEN regexp_replace(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '\.0\d\d\$','',1,1)
            WHEN f.FAB_NAME like 'USR:%'
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 8)
            WHEN f.FAB_NAME like 'USU:%'
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 6)
            WHEN f.FAB_NAME like 'JND:%' and regexp_like(sl.SOURCE_LOT, '^.+0\d\$') 
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 8)
            WHEN (f.FAB_NAME like 'MYD:%' or f.FAB_NAME like 'ISMFAB:%') and regexp_like(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '^.+\.[0-9]+[A-Z]\$') 
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, instr(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '.')-1)
            WHEN f.FAB_NAME like 'CZ4:%' or f.FAB_NAME like 'ISMFAB:%' or f.FAB_NAME like 'UVA:%' or f.FAB_NAME like 'LFOUNDRY'
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 7)
            WHEN (f.FAB_NAME like 'UMC:%' or f.FAB_NAME like 'MYD:%' ) and regexp_like(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '^.+\.[0-9]+\$') 
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, instr(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '.')-1)
            WHEN sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT 
            ELSE t.PARENT_LOT 
       END order by TRANS_DT) as dr
FROM translate t
LEFT JOIN src_lot sl ON t.PARENT_LOT = sl.LOT
LEFT JOIN fab_info f on CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END = f.LOT
/*Filter on lot here.  Need four lots: 
1. Original lot (no changes)
2. Remove dot (.) if it exists
3. Replace dot (.) with zero (0) 
4. Replace dot (.) with zero (0) AND remove first two characters (in case it is a lot class)
5. *IF* lot ends with .\d+[A-Z], remove dot and remove last character (e.g., RM12016.1F -> RM120161, RM12016.12Q -> RM1201612)
*/
WHERE t.LOT in ('$lotid')
)
/* Always return the result with the oldest datetime to ensure the correct product is returned */
WHERE DR=1
");
	$sth->execute(); 
	# Only one row should be returned
	my %lotGresults;
	# Finish fetchrows just in case more rows, but at least to get to the end of the row fetch so no warnings/errors
	while(my $recs = $sth->fetchrow_hashref()) 
	{
		$lotGresults{SOURCE_LOT} = $recs->{SOURCE_LOT};
		$lotGresults{FAB}        = $recs->{FAB};
	}

	$dbhLOTGPRD->disconnect;
	return %lotGresults;
}
