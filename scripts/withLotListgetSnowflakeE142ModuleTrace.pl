#!/usr/bin/env perl_db

# 2022-12-02 S. Boothby : Initial version
# 2023-11-21 S. Boothby : End date -> Metamodifieddate
#                         One wafer per file
#                         Fixed bug excluding certain wafer results 
# 2023-12-22 S. Boothby : Add maximum time range command-line option.
# 2026-02-16 jgarcia  : Added singleton lock feature and benchmarking - jsonl.
# 2026-03-06 jgarcia  : Added Oracle benchmarking, decoupled JSONL, itemized row counting, and added execution metadata

# Query Snowflake for E142 die trace

use strict;
use File::Copy;
use FindBin::libs; 
use Getopt::Long qw/:config ignore_case auto_help/;
use DBI;
use Pod::Usage qw/pod2usage/;
use File::Basename qw(basename dirname);
use Time::HiRes qw(gettimeofday tv_interval);
use JSON::PP;
use DateTime::Format::Strptime;
use Carp;
use PDF::Log;
use PDF::DAO;
use PDF::DpData;
use PDF::DpLoad;
use PDF::WS;
use IO::Compress::Gzip qw(gzip $GzipError) ;;
use Data::Dumper;
use Fcntl qw(:flock);             # Added for singleton locking

my $dt = DateTime->now(time_zone => 'local');
my $currentDateTime = join '_', $dt->ymd, $dt->hms;
$currentDateTime =~ s/[:-]//g;

# Benchmark start - Record initial time for performance tracking
my $bench_t0 = [gettimeofday];
my $bench_start_dt = $dt;

my $usageMsg = "Usage: $0 --source_odbc {source-ODBC-cx} --source_warehouse {source-warehouse} --source_schema {source snowflake-db.schema} --view_name {snowflake-view-name} --flow {B1T|PIM} --get_product --stage {WAFER|DIEBOND|SINGULATION|LEADFRAME_ATTACH|INTERNAL2DID|TEST} [--modfile last-meta-modified-file] [--max_hours max-hours]|[--start_hours num-hours --end_hours num-hours] [--lot_list comma-separated-lots] --logfile {log-file} --out_trace {trace-upload-dir} --prod_not_regexp {regex-str}\n";
my $onScribeWSURL="http://globmfgapp.onsemi.com:61050/exensioreftables-ws/api/onscribe/byscribeid/";
my $onLotWSURL="http://globmfgapp.onsemi.com:61050/exensioreftables-ws/api/onlot/bylotid/";
my $ppLotProdWSURL="http://globmfgapp.onsemi.com:61050/exensioreftables-ws/api/pplotprod/bylotid/";
my $modfile = "";
my $modfileDate = "";
my $maxHours = 2;
my $startHours = 2;
my $endHours   = 0;
my $prodNotRegexp = "";
my $getProduct = 0;

my %hOptions = (
   "SOURCE_ODBC"   => undef,
   "SOURCE_WAREHOUSE" => undef,
   "FLOW"          => undef,
   "GET_PRODUCT"   => undef,
   "LOGFILE"       => undef,
	"BENCHMARK_LOG" => undef,
	"BENCHMARK_INCLUDE_NON_ARCHIVE" => undef,
	"BENCHMARK_DB_DSN"  => undef,
	"BENCHMARK_DB_USER" => undef,
	"BENCHMARK_DB_PASS" => undef,
	"PIPELINE_NAME" => undef,
	"PIPELINE_TYPE" => undef,
   "OUT_TRACE"     => undef,
   "VIEW_NAME"     => undef,
   "MODFILE"       => undef,
   "MAX_HOURS"     => undef,
   "START_HOURS"   => undef,
   "END_HOURS"     => undef,
   "LOT_LIST"      => undef,
   "LOCK_FILE"     => undef
);

my %forwardExtensions = ( "WAFER"          => "w2f"
);
my %backwardExtensions = ( "DIEBOND"          => "a2w"
                         , "SINGULATION"      => "s2w"
                         , "LEADFRAME_ATTACH" => "fa2w"
                         , "CASESCREW_ATTACH" => "c2w"
                         , "INTERNAL2DID"     => "id2w"
                         , "TEST"             => "f2w"
);

unless (GetOptions( \%hOptions, "SOURCE_ODBC=s", "SOURCE_WAREHOUSE=s", "SOURCE_SCHEMA=s", "FLOW=s", "GET_PRODUCT", "STAGE=s", "VIEW_NAME=s", "MODFILE=s", "MAX_HOURS=s", "START_HOURS=s", "END_HOURS=s", "LOT_LIST=s", "OUT_TRACE=s", "LOGFILE=s", "BENCHMARK_LOG=s", "BENCHMARK_INCLUDE_NON_ARCHIVE!", "BENCHMARK_DB_DSN=s", "BENCHMARK_DB_USER:s", "BENCHMARK_DB_PASS:s", "PIPELINE_NAME=s", "PIPELINE_TYPE=s", "PROD_NOT_REGEXP=s", "LOCK_FILE=s")){
    print($usageMsg);
    dpExit( 1, "invalid options" );
}
PDF::Log->init(\%hOptions);

# Singleton Lock Implementation - Prevents concurrent execution of the script
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
		$lockFile = "./log/getSnowflakeE142ModuleTrace.lock";
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

unless ( $hOptions{SOURCE_ODBC} ) {
    print($usageMsg);
    dpExit( 1, "--SOURCE_ODBC argument is required!" );
}
unless ( $hOptions{SOURCE_WAREHOUSE} ) {
    print($usageMsg);
    dpExit( 1, "--SOURCE_WAREHOUSE argument is required!" );
}
unless ( $hOptions{SOURCE_SCHEMA} ) {
    print($usageMsg);
    dpExit( 1, "--SOURCE_SCHEMA argument is required!" );
}
unless ( $hOptions{FLOW} ) {
    print($usageMsg);
    dpExit( 1, "--FLOW argument is required!" );
}
unless ( $hOptions{STAGE} ) {
    print($usageMsg);
    dpExit( 1, "--STAGE argument is required!" );
}
unless ( $hOptions{VIEW_NAME} ) {
    print($usageMsg);
    dpExit( 1, "--VIEW_NAME argument is required!" );
}
unless ( $hOptions{OUT_TRACE} ) {
    print($usageMsg);
    dpExit( 1, "OUT_TRACE argument is required!" );
}
if ( $hOptions{GET_PRODUCT} )
{
    $getProduct = 1;
}

if ( $hOptions{MODFILE} )
{
	$modfile = $hOptions{MODFILE};
}
if ( $hOptions{MAX_HOURS} )
{
	$maxHours = int($hOptions{MAX_HOURS});
}
else
{
	$maxHours = 48;
}
if ( $hOptions{START_HOURS} )
{
	if ( $hOptions{MODFILE} )
	{
		WARN("--modfile setting overrides START_HOURS");
	}
	$startHours = int($hOptions{START_HOURS});
}
if ( $hOptions{END_HOURS} )
{
	if ( $hOptions{MODFILE} )
	{
		WARN("--modfile setting overrides END_HOURS");
	}
	$endHours = int($hOptions{END_HOURS});
}
if ( $hOptions{PROD_NOT_REGEXP} )
{
	$prodNotRegexp = $hOptions{PROD_NOT_REGEXP};
}

my $snowflakeSvcAcct = "$ENV{SNOW_USER}";
my $snowflakePass = "$ENV{SNOW_PASS}";

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
my $pipelineEnv = $ENV{PIPELINE_ENV} || $detectedEnv;

# Oracle data sources are defined in ~/tns/tnsnames.ora.  Perhaps we should use the refdb web service instead?
my $dwprodDataSource = q/DWPRD/;
my $lotGDataSource   = q/LOTGPRD/;

my $sourceODBC   = $hOptions{SOURCE_ODBC};
my $sourceWarehouse = $hOptions{SOURCE_WAREHOUSE};
my $sourceSchema = $hOptions{SOURCE_SCHEMA};
my $viewName     = $hOptions{VIEW_NAME};
my $flow         = $hOptions{FLOW};
my $sourceStage  = $hOptions{STAGE};
my $stepColumn;

if ( $sourceStage eq "WAFER" )
{
	$stepColumn = "DIEBOND";
}
else
{
	$stepColumn = $sourceStage;
}

my $class53Header;

if ( $flow eq "B1T" )
{ 
	$class53Header = "FLOW|FACILITY|BACKEND_SOURCE_LOT|BACKEND_LOT|BACKEND_PRODUCT|DIEBOND_LOT|DIEBOND_PRODUCT|DIEBOND_MACHINE|DIEBOND_CREATE_DATE|DIEBOND_FILENAME|PANEL_ID|DBC_ID|DBC_X|DBC_Y|DBC_BIN|DBC_BIN_DESCRIPTION|DBC_BIN_QUALITY|DBC_BIN_PICK|DIE_TYPE|WAFER_FAB|EXENSIO_LOT|EXENSIO_SOURCELOT|FAB_PRODUCT|EXENSIO_WAFERID|WAFER_NUMBER|LASERSCRIBE|LASERSCRIBE_START_TIME|LASERSCRIBE_END_TIME|BONDER_X|BONDER_Y|DIE_X|DIE_Y|WAFER_BIN|WAFER_BIN_DESCRIPTION|WAFER_BIN_QUALITY|WAFER_BIN_PICK|SINGULATION_LOT|SINGULATION_PRODUCT|SINGULATION_MACHINE|SINGULATION_CREATE_DATE|SINGULATION_FILENAME|SINGULATION_ID|SINGULATION_X|SINGULATION_Y|SINGULATION_BIN|SINGULATION_BIN_DESCRIPTION|SINGULATION_BIN_QUALITY|SINGULATION_BIN_PICK|LEADFRAME_LOT|LEADFRAME_ATTACH_PRODUCT|LEADFRAME_ATTACH_MACHINE|LEADFRAME_ATTACH_CREATE_DATE|LEADFRAME_ATTACH_FILENAME|LEADFRAME_ID|LEADFRAME_X|LEADFRAME_Y|LEADFRAME_BIN|LEADFRAME_BIN_DESCRIPTION|LEADFRAME_BIN_QUALITY|LEADFRAME_BIN_PICK|INTERNAL2DID_LOT|INTERNAL2DID_PRODUCT|INTERNAL2DID_MACHINE|INTERNAL2DID_CREATE_DATE|INTERNAL2DID_FILENAME|INTERNAL2DID_ID|INTERNAL2DID_X|INTERNAL2DID_Y|INTERNAL2DID_BIN|INTERNAL2DID_BIN_DESCRIPTION|INTERNAL2DID_BIN_QUALITY|INTERNAL2DID_BIN_PICK|TEST_LOT|STEP_START_TIME|STEP_END_TIME|TEST_PRODUCT|TEST_MACHINE|TEST_CREATE_DATE|TEST_FILENAME|TEST_ID|TEST_X|TEST_Y|TEST_BIN|TEST_BIN_DESCRIPTION|TEST_BIN_QUALITY|TEST_BIN_PICK|BACKSIDESCRIBE|GLOBALWAFERID|PUCKID|SLICEORDER|PUCKHEIGHT|RUNID|RAWWAFERSUPPLIER|RAWSILICONPRODUCT|RAWSILICONLOTID|RAWSILICONLOTTYPE|RAWWAFERSTARTDATE|EPISUPPLIERNAME|EPIPRODUCT|EPILOTID|EPISTARTDATE|EPISLOT|FABPRODUCT|FABSTARTDATE|FABLOTTYPE";
}
elsif ( $flow eq "PIM" )
{
	$class53Header = "FLOW|FACILITY|BACKEND_SOURCE_LOT|BACKEND_LOT|BACKEND_PRODUCT|DIEBOND_LOT|DIEBOND_PRODUCT|DIEBOND_MACHINE|DIEBOND_CREATE_DATE|DIEBOND_FILENAME|PANEL_ID|DBC_ID|DBC_X|DBC_Y|DBC_BIN|DBC_BIN_DESCRIPTION|DBC_BIN_QUALITY|DBC_BIN_PICK|DIE_TYPE|WAFER_FAB|EXENSIO_LOT|EXENSIO_SOURCELOT|FAB_PRODUCT|EXENSIO_WAFERID|WAFER_NUMBER|LASERSCRIBE|LASERSCRIBE_START_TIME|LASERSCRIBE_END_TIME|BONDER_X|BONDER_Y|DIE_X|DIE_Y|WAFER_BIN|WAFER_BIN_DESCRIPTION|WAFER_BIN_QUALITY|WAFER_BIN_PICK|CSA_LOT|CSA_PRODUCT|CSA_MACHINE|CSA_CREATE_DATE|CSA_FILENAME|CSA_ID|CSA_LAYOUT|CSA_BIN|CSA_BIN_DESCRIPTION|CSA_BIN_QUALITY|CSA_BIN_PICK|TEST_LOT|STEP_START_TIME|STEP_END_TIME|TEST_PRODUCT|TEST_MACHINE|TEST_CREATE_DATE|TEST_FILENAME|TEST_ID|TEST_BIN|TEST_BIN_DESCRIPTION|TEST_BIN_QUALITY|TEST_BIN_PICK|BACKSIDESCRIBE|GLOBALWAFERID|PUCKID|SLICEORDER|PUCKHEIGHT|RUNID|RAWWAFERSUPPLIER|RAWSILICONPRODUCT|RAWSILICONLOTID|RAWSILICONLOTTYPE|RAWWAFERSTARTDATE|EPISUPPLIERNAME|EPIPRODUCT|EPILOTID|EPISTARTDATE|EPISLOT|FABPRODUCT|FABSTARTDATE|FABLOTTYPE";
}

my $outputTraceDir  = $hOptions{OUT_TRACE};

if ( not -w $outputTraceDir )
{
	dpExit(1, "OUT_TRACE directory does not exist or is not writable: $outputTraceDir");
}
elsif ( not -w "$outputTraceDir/tmp" )
{
	mkdir("$outputTraceDir/tmp");
}

# Get the last modified date from the modfile
if ( -e $modfile )
{
	open my $mf, $modfile or dpExit(2, "Failed to read $modfile for last modified date");
	while ( my $line = <$mf>)
	{
		$modfileDate = $line;
		chomp($modfileDate); # Remove newline
	}
}
else
{
	# Default to 2000-01-01 00:00:00
	$modfileDate = "2000-01-01 00:00:00";
}

# Get fab codes & descriptions from BIW
my %fabCodes = &getFabCodes();

my $sql = &getSQL($sourceODBC, $flow);
INFO( "Querying: $sourceODBC flow: $flow" );
my $dbhMSSQL = &odsConnect($sourceODBC, $sourceWarehouse, $snowflakeSvcAcct, $snowflakePass);
my $dwsth;
eval {
	$dwsth = $dbhMSSQL->prepare($sql);
};
if ( !defined($dwsth) )
{
	my $err = $DBI::errstr || "unknown error";
	$dbhMSSQL->disconnect if defined $dbhMSSQL;
	ERROR("SQL prepare failed: $err");
	dpExit(1, "SQL Prepare failure for $sourceODBC: $err");
}
my $rc = $dwsth->execute();
if (! defined( $rc ))
{
	my $err = $DBI::errstr || "unknown error";
	$dbhMSSQL->disconnect;
	ERROR("SQL execute failed: $err");
	dpExit(1, "SQL Execute failure for $sourceODBC: $err");
}
my $isFmrFairchild = 0;

my %sourceLots;
my %sourceProducts;
my %sourceFabs;
my %scribes;

# Variables needed to write out records to trace files
#
# Store results in a hash of arrays for assembly & test data
# 1st level hash = Assembly lot
my %assemblyLotData = ();
my %backendLotData = ();
# Store results in a hash of hashes of arrays for wafer to assemby & test data
# 1st level hash = fab source lot
# 2nd level hash = exensio wafer
# Input data is ordered by time, so always add new entries to the end of the array
my %fabAssemblyLotData = ();
my %fabTestLotData = ();

# Diagnostics counters to explain no-output runs
my $rowsFetched = 0;
my $rowsStatusSkipped = 0;
my $rowsDroppedNoBackendLot = 0;
my $rowsDroppedProdRegex = 0;
my $rowsKept = 0;

my ($backendLot, $assemblyLot, $testLot, $backendSourceLot, $assemblySourceLot, $testSourceLot, $assemblyLotType, $backendProduct, $assemblyProduct, $testProduct );
my ($step, $backendFacilityCode, $backendFacility);
my ($fabLot, $fabSourceLot, $fabProduct, $fromFab, $snowflakeProduct);
my ($laserScribe, $exensioWaferID, $fabID, $str, $wstr, $wnum);
my ($snowflakeFabSourceLot);
my $lastMetaModifiedDate = "";
my $wsCall;
my @arr;
my %fFairchildFabs = ( 'KRG'=>1,'KRI'=>2,'KRH'=>3,'KRJ'=>4,'UWA'=>5,'CBA'=>6,'PBC'=>7,'UWB'=>8 );

my $fabReturned;
# Process the data from the Snowflake DB
while( my $ref=$dwsth->fetchrow_hashref())
{
	$rowsFetched++;
	# Get facility ID (backend site creating the E142 files)
	$backendFacilityCode = $ref->{FACILITY};
	if (exists( $fabCodes{$backendFacilityCode}))
	{
		$backendFacility = $backendFacilityCode.":".$fabCodes{$backendFacilityCode};
	}
	else
	{
		WARN("Backend facility code \"$backendFacilityCode\" not found in DWPRD");
		$backendFacility = $backendFacilityCode;
	}

	# Get source lot for assembly and test lots
	$assemblyLot = $ref->{DIEBOND_LOT};
	$testLot     = $ref->{TEST_LOT};
	my $backendLotColumn = $stepColumn . "_LOT";
	$backendLot  = $ref->{$backendLotColumn};
	($assemblySourceLot, $assemblyProduct) = &backendMetadata($assemblyLot, $backendFacilityCode, $onLotWSURL);
	if ( length($testLot) > 0 )
	{
		($testSourceLot, $testProduct) = &backendMetadata($testLot, $backendFacilityCode, $onLotWSURL);
	}	
	else
	{
		$testSourceLot = "";
	}
	($backendSourceLot, $backendProduct) = &backendMetadata($backendLot, $backendFacilityCode, $onLotWSURL);

	my $backendProductColumn = $stepColumn . "_PRODUCT";
	$snowflakeProduct = $ref->{$backendProductColumn};
	
	#
	# Check whether source lot returned by Snowflake matches the REFDB source lot
	$laserScribe = $ref->{LASERSCRIBE};
	$snowflakeFabSourceLot = $ref->{EXENSIO_SOURCELOT}; 
	$fabLot = substr($snowflakeFabSourceLot, 0, -2); # Remove .S

	# Check if Fab lot is the same as diebond lot.  If so, this means the view identified these as non-Bucheon lots.
	# In this case, get the fab/probe lot and wafer number information from the OnScribe web service
	my $status = 0;
	my $waferIdFmt = 0; # 0=srclot_##; 1=waferid<->scribe; 2=srclot-W## 3=srclot-##
	if ( $fabLot eq $assemblyLot )
	{
		($fabLot, $wnum, $status) = &waferScribeMetadata($laserScribe, $onScribeWSURL);
		$waferIdFmt = 1;
	}
	
	if ( $status == 0 )
	{
		($fabSourceLot, $fabProduct, $fabID) = &frontendMetadata($fabLot, $onLotWSURL, $ppLotProdWSURL);
		if ( $waferIdFmt == 0 )
		{
			($wstr, $wnum) = split( '_', $ref->{EXENSIO_WAFERID});
			$exensioWaferID = substr($fabSourceLot, 0, -2) . "_" . $wnum;
		}
		elsif( $waferIdFmt == 1 )
		{
			$exensioWaferID = $laserScribe;
		}
		elsif( $waferIdFmt == 2 )
		{
			($wstr, $wnum) = split( '-', $ref->{EXENSIO_WAFERID});
			$wnum = substr($wnum, 1);
			$exensioWaferID = substr($fabSourceLot, 0, -2) . "-W" . $wnum;
		}
		elsif( $waferIdFmt == 3 )
		{
			($wstr, $wnum) = split( '-', $ref->{EXENSIO_WAFERID});
			$exensioWaferID = substr($fabSourceLot, 0, -2) . "-" . $wnum;
		}

		if ( $flow eq "B1T" )
		{
			$str = &createOutputString($ref->{FLOW}, $backendFacility, $backendSourceLot, $backendLot, $backendProduct,
	                                $assemblyLot, $ref->{DIEBOND_PRODUCT}, $ref->{DIEBOND_MACHINE}, $ref->{DIEBOND_CREATE_DATE},
					$ref->{DIEBOND_FILENAME}, $ref->{PANEL_ID}, $ref->{DBC_ID}, $ref->{DBC_X}, $ref->{DBC_Y}, $ref->{DBC_BIN}, $ref->{DBC_BIN_DESCRIPTION},
					$ref->{DBC_BIN_QUALITY}, $ref->{DBC_BIN_PICK}, $ref->{DIE_TYPE}, $fabID, $fabLot, $fabSourceLot, $fabProduct, $exensioWaferID, $wnum,
					$laserScribe, $ref->{LASERSCRIBE_START_TIME}, $ref->{LASERSCRIBE_END_TIME}, $ref->{BONDER_X}, $ref->{BONDER_Y}, $ref->{DIE_X}, $ref->{DIE_Y},
	                                $ref->{WAFER_BIN}, $ref->{WAFER_BIN_DESCRIPTION},$ref->{WAFER_BIN_QUALITY}, $ref->{WAFER_BIN_PICK},
	                                $ref->{SINGULATION_LOT}, $ref->{SINGLUATION_PRODUCT},$ref->{SINGULATION_MACHINE}, $ref->{SINGULATION_CREATE_DATE},
					$ref->{SINGULATION_FILENAME}, $ref->{SINGULATION_ID}, $ref->{SINGULATION_X}, $ref->{SINGULATION_Y}, $ref->{SINGULATION_BIN},
					$ref->{SINGULATION_BIN_DESCRIPTION}, $ref->{SINGULATION_BIN_QUALITY}, $ref->{SINGULATION_BIN_PICK}, $ref->{LEADFRAME_LOT},$ref->{LEADFRAME_ATTACH_PRODUCT},
					$ref->{LEADFRAME_ATTACH_MACHINE}, $ref->{LEADFRAME_ATTACH_CREATE_DATE}, $ref->{LEADFRAME_ATTACH_FILENAME}, $ref->{LEADFRAME_ID},
					$ref->{LEADFRAME_X}, $ref->{LEADFRAME_Y}, $ref->{LEADFRAME_BIN}, $ref->{LEADFRAME_BIN_DESCRIPTION}, $ref->{LEADFRAME_BIN_QUALITY},
					$ref->{LEADFRAME_BIN_PICK}, $ref->{INTERNAL2DID_LOT}, $ref->{INTERNAL2DID_PRODUCT}, $ref->{INTERNAL2DID_MACHINE}, $ref->{INTERNAL2DID_CREATE_DATE},
					$ref->{INTERNAL2DID_FILENAME}, $ref->{INTERNAL2DID_ID}, $ref->{INTERNAL2DID_X}, $ref->{INTERNAL2DID_Y},
					$ref->{INTERNAL2DID_BIN}, $ref->{INTERNAL2DID_BIN_DESCRIPTION}, $ref->{INTERNAL2DID_BIN_QUALITY}, $ref->{INTERNAL2DID_BIN_PICK},
					$testLot, $ref->{STEP_START_TIME}, $ref->{STEP_END_TIME}, $ref->{TEST_PRODUCT}, $ref->{TEST_MACHINE}, $ref->{TEST_CREATE_DATE},
	                                $ref->{TEST_FILENAME}, $ref->{TEST_ID}, $ref->{TEST_X}, $ref->{TEST_Y},
					$ref->{TEST_BIN}, $ref->{TEST_BIN_DESCRIPTION}, $ref->{TEST_BIN_QUALITY}, $ref->{TEST_BIN_PICK},
					$ref->{BACKSIDESCRIBE}, $ref->{GLOBALWAFERID}, $ref->{PUCKID}, $ref->{SLICEORDER}, $ref->{PUCKHEIGHT}, $ref->{RUNID},
					$ref->{RAWWAFERSUPPLIER}, $ref->{RAWSILICONPRODUCT}, $ref->{RAWSILICONLOTID}, $ref->{RAWSILICONLOTTYPE}, $ref->{RAWWAFERSTARTDATE},
					$ref->{EPISUPPLIERNAME}, $ref->{EPIPRODUCT}, $ref->{EPILOTID}, $ref->{EPISTARTDATE}, $ref->{EPISLOT},
	                                $ref->{FABPRODUCT}, $ref->{FABSTARTDATE}, $ref->{FABLOTTYPE});
		}
		elsif ( $flow eq "PIM" )
		{
			$str = &createOutputString($ref->{FLOW}, $backendFacility, $backendSourceLot, $backendLot, $backendProduct,
	                                $assemblyLot, $ref->{DIEBOND_PRODUCT}, $ref->{DIEBOND_MACHINE}, $ref->{DIEBOND_CREATE_DATE},
					$ref->{DIEBOND_FILENAME}, $ref->{PANEL_ID}, $ref->{DBC_ID}, $ref->{DBC_X}, $ref->{DBC_Y}, $ref->{DBC_BIN}, $ref->{DBC_BIN_DESCRIPTION},
					$ref->{DBC_BIN_QUALITY}, $ref->{DBC_BIN_PICK}, $ref->{DIE_TYPE}, $fabID, $fabLot, $fabSourceLot, $fabProduct, $exensioWaferID, $wnum,
					$laserScribe, $ref->{LASERSCRIBE_START_TIME}, $ref->{LASERSCRIBE_END_TIME}, $ref->{BONDER_X}, $ref->{BONDER_Y}, $ref->{DIE_X}, $ref->{DIE_Y},
	                                $ref->{WAFER_BIN}, $ref->{WAFER_BIN_DESCRIPTION},$ref->{WAFER_BIN_QUALITY}, $ref->{WAFER_BIN_PICK},
	                                $ref->{CSA_LOT}, $ref->{CSA_PRODUCT}, $ref->{CSA_MACHINE}, $ref->{CSA_CREATE_DATE}, $ref->{CSA_FILENAME}, $ref->{CSA_ID}, $ref->{CSA_LAYOUT}, $ref->{CSA_BIN},
					$ref->{CSA_BIN_DESCRIPTION}, $ref->{CSA_BIN_QUALITY}, $ref->{CSA_BIN_PICK},
					$testLot, $ref->{STEP_START_TIME}, $ref->{STEP_END_TIME}, $ref->{TEST_PRODUCT}, $ref->{TEST_MACHINE}, $ref->{TEST_CREATE_DATE},
	                                $ref->{TEST_FILENAME}, $ref->{TEST_ID}, $ref->{TEST_BIN}, $ref->{TEST_BIN_DESCRIPTION}, $ref->{TEST_BIN_QUALITY}, $ref->{TEST_BIN_PICK},
					$ref->{BACKSIDESCRIBE}, $ref->{GLOBALWAFERID}, $ref->{PUCKID}, $ref->{SLICEORDER}, $ref->{PUCKHEIGHT}, $ref->{RUNID},
					$ref->{RAWWAFERSUPPLIER}, $ref->{RAWSILICONPRODUCT}, $ref->{RAWSILICONLOTID}, $ref->{RAWSILICONLOTTYPE}, $ref->{RAWWAFERSTARTDATE},
					$ref->{EPISUPPLIERNAME}, $ref->{EPIPRODUCT}, $ref->{EPILOTID}, $ref->{EPISTARTDATE}, $ref->{EPISLOT},
	                                $ref->{FABPRODUCT}, $ref->{FABSTARTDATE}, $ref->{FABLOTTYPE});
		}
		$lastMetaModifiedDate = $ref->{METAMODIFIEDDATE};
	#INFO("W2T: $str");
#my %assemblyLotData;
#my %backendLotData;
# Store results in a hash of hashes of arrays for wafer to assemby & test data
# # 1st level hash = fab source lot
# # 2nd level hash = exensio wafer
# # Input data is ordered by time, so always add new entries to the end of the array
		my $hashKey;
		# Exclude backend products regex matching $prodNotRegexp string
		# Only exclude backend product if supplied test/diebond product is null/empty 
		# (this means that the product wasn't supplied in the e142 and the data may be incorrect)
		if ( length($backendLot) > 0 && not ( length($snowflakeProduct) == 0 && length($prodNotRegexp) > 0 && $backendProduct =~ $prodNotRegexp ))
		{
			$rowsKept++;
			#backendLotData
			# Key for backendLotData is "$backendFacilityCode-$backendLot"
			$hashKey = $backendFacilityCode . "-" . $backendLot;
			if ( not defined($backendLotData{$hashKey}))
			{
				$backendLotData{$hashKey} = [];
			}
			# Add string to end of the array
			push(@{$backendLotData{$hashKey}}, $str);
	
			#fabTestLotData
			# Key for fabTestLotData is "$backendFacilityCode-$fabSourceLot"
			# Only generate Wafer2All records when stage = WAFER
			if ( $sourceStage eq "WAFER")
			{
				$hashKey = $backendFacilityCode . "-" . $fabSourceLot;
				if ( not defined($fabTestLotData{$hashKey}))
				{
					#INFO("Adding $backendFacilityCode-$fabSourceLot to hash");
					$fabTestLotData{$hashKey} = {};
				}
				my $waferHashKey = $backendFacilityCode . "-" . $exensioWaferID;
				if ( not defined ($fabTestLotData{$hashKey}{$waferHashKey}))
				{
					#INFO("Adding $waferHashKey to hash");
					$fabTestLotData{$hashKey}{$waferHashKey} = [];
				}
				push(@{$fabTestLotData{$hashKey}{$waferHashKey}}, $str);
			}
		}
		else
		{
			if (length($backendLot) == 0)
			{
				$rowsDroppedNoBackendLot++;
			}
			elsif (length($snowflakeProduct) == 0 && length($prodNotRegexp) > 0 && $backendProduct =~ $prodNotRegexp)
			{
				$rowsDroppedProdRegex++;
			}
		}
	}
	else
	{
		$rowsStatusSkipped++;
	}
}
$dbhMSSQL->disconnect;

#print Dumper(\%backendLotData);
#print Dumper(\%fabTestLotData);

# Write out files
my ($fileName, $lastFileName);
my @csv_files;
my %out_files_info = ();
my $filesWritten = 0;
if ( $sourceStage ne "WAFER" )
{
	while( my ($key, $val) = each %backendLotData )
	{
		$fileName = $outputTraceDir . "/tmp/E142_${backendFacilityCode}_${flow}-$sourceStage-$currentDateTime-$key.$backwardExtensions{$sourceStage}";
		INFO("Writing: $fileName");
		open OUT, ">$fileName" or dpExit(1, "Cannot write $fileName");
		print OUT "$class53Header\n";
		# track this file and row count
		$out_files_info{$fileName} = 0;
		push @csv_files, $fileName;

		@arr = @{$val};
		while( my ($i, $arrstr) = each @arr )
		{
			$out_files_info{$fileName}++;
			print OUT "$arrstr\n";
		}
		close OUT;
		$filesWritten++;
	}
}
if ( $sourceStage eq "WAFER" )
{
	while( my ($srclot, $srclothash) = each %fabTestLotData )
	{
		while( my ($wfr, $val) = each %{$srclothash})
		{
			$fileName = $outputTraceDir . "/tmp/E142_${backendFacilityCode}_${flow}-$sourceStage-$currentDateTime-$wfr.$forwardExtensions{$sourceStage}";
			INFO("Writing: $fileName");
			open OUT, ">$fileName" or dpExit(1, "Cannot write $fileName");
			print OUT "$class53Header\n";
			$out_files_info{$fileName} = 0;
			push @csv_files, $fileName;
			@arr = @{$val};
			while( my ($i, $arrstr) = each @arr )
			{
				$out_files_info{$fileName}++;
				#INFO( "$arrstr");
				print OUT "$arrstr\n";
			}
			$lastFileName = $fileName;
			close OUT;
			$filesWritten++;
		}
	}
}

# Diagnostics summary for troubleshooting no-output cases
INFO("E142 extraction diagnostics: fetched=$rowsFetched kept=$rowsKept dropped_status=$rowsStatusSkipped dropped_no_backend_lot=$rowsDroppedNoBackendLot dropped_prod_regex=$rowsDroppedProdRegex files_written=$filesWritten stage=$sourceStage flow=$flow view=$sourceSchema.$viewName");
if ($rowsFetched > 0 && $rowsKept == 0)
{
	WARN("No rows passed post-query filters. Check --modfile window, onScribe availability (status skips), and --prod_not_regexp behavior.");
}
if ($rowsFetched == 0)
{
	WARN("No rows fetched from Snowflake query. Check time window criteria and source view population.");
}
# Gzip and move files to output folder
foreach my $fileName (@csv_files)
{
	# GZIP the file first
	gzip $fileName => "$fileName.gz";
	unlink($fileName);

	move("$fileName.gz", $outputTraceDir);
}

# If benchmark logging or Oracle DSN is requested, emit stats
# This section records execution stats for monitoring and performance evaluation
my $benchmarkDsn = $hOptions{BENCHMARK_DB_DSN} || $ENV{BENCHMARK_DB_DSN};
if ((defined $hOptions{BENCHMARK_LOG} && length($hOptions{BENCHMARK_LOG})) || (defined $benchmarkDsn && length($benchmarkDsn)))
{
		my $bench_end_dt = DateTime->now(time_zone => 'local');
		my $elapsed = tv_interval($bench_t0);
		my $elapsed_human = sprintf("%dm %ds", int($elapsed/60), int($elapsed%60));

		# Build outputs arrays for benchmarking
		my @output_files_trace = ();
		my @out_files = ();
		my %file_type_counts = ();
		my %file_type_rows = ();
		my $total_rows = 0;
		my $total_files = 0;
		foreach my $f (@csv_files)
		{
			my $base = basename($f);
			my $final_path = "$outputTraceDir/" . $base . ".gz";
			push @output_files_trace, $final_path;
			my $rows = $out_files_info{$f} || 0;
			$total_rows += $rows;
			$total_files++;
			push @out_files, { path => $final_path, rows => $rows };

			# Extract file type from filename extension (e.g., .w2f.gz -> w2f)
			if ($base =~ /\.(\w+)\.csv$/) # The original @csv_files have .csv, they are gzipped later
			{
				my $file_type = $1;
				$file_type_counts{$file_type} = ($file_type_counts{$file_type} || 0) + 1;
				$file_type_rows{$file_type} = ($file_type_rows{$file_type} || 0) + $rows;
			}
		}

		# Log total rows extracted and written
		INFO("Rows Total Count: Extracted=$total_rows | Written=$total_rows | Files=$total_files");

	# For multi-file outputs, use first file as representative output_file
	# Initialize to N/A since we only need out_trace (multiple files)
	my $representative_output = ($total_files > 0 && @output_files_trace) ? $output_files_trace[0] : "N/A";
	
	my %bench = (
		start_local    => $bench_start_dt->strftime('%F %T'),
		end_local      => $bench_end_dt->strftime('%F %T'),
		start_utc      => $bench_start_dt->clone->set_time_zone('UTC')->strftime('%FT%TZ'),
		end_utc        => $bench_end_dt->clone->set_time_zone('UTC')->strftime('%FT%TZ'),
		elapsed_seconds=> $elapsed + 0.0,
		elapsed_human  => $elapsed_human,
		output_file    => $representative_output,
		rowcount       => $total_rows,
		rows_extracted => $total_rows,
		rows_written   => $total_rows,
		total_files    => $total_files,
		log_file       => ($hOptions{LOGFILE} || ""),
		pid            => $$,
		date_code      => $currentDateTime,
		pipeline_name  => ($hOptions{PIPELINE_NAME} || "getSnowflakeE142ModuleTrace"),
		script_name    => basename($0),
		pipeline_type  => ($hOptions{PIPELINE_TYPE} || "batch"),
		environment    => $pipelineEnv,
		output_files_trace => \@output_files_trace,
		out_files      => \@out_files,
		rows_fetched   => $rowsFetched,
		rows_kept      => $rowsKept,
		rows_dropped_status => $rowsStatusSkipped,
		rows_dropped_no_backend_lot => $rowsDroppedNoBackendLot,
		rows_dropped_prod_regex => $rowsDroppedProdRegex,
		status => "success",
		error_message => "",
		hostname => $hostname,
		run_args => join(' ', $0, @ARGV),
		file_type_counts => \%file_type_counts,
		file_type_rows => \%file_type_rows,
	);

	# Write to JSONL file (best effort - don't fail if this errors)
	eval {
		writeBenchmark($hOptions{BENCHMARK_LOG}, \%bench);
	};
	if ($@)
	{
		warn "WARN: Failed to write benchmark to JSONL: $@\n";
	}
	
	# Write to Oracle DB if credentials or environment provided (best effort - don't fail if this errors)
	if (defined($benchmarkDsn) && length($benchmarkDsn) > 0)
	{
		eval {
			writeBenchmarkToOracle(\%hOptions, \%bench);
		};
		if ($@)
		{
			warn "WARN: Failed to write benchmark to Oracle: $@\n";
		}
	}
}

# Write out last metamodifieddate if --modfile option was provided
if ( $hOptions{MODFILE} && length($lastMetaModifiedDate) > 19)
{
	open(MF, ">$modfile") or dpExit(2, "Failed to open $modfile for overwrite");
	print MF "$lastMetaModifiedDate\n";
	close MF;
}

dpExit(0);

##### SUBROUTINES #####

sub writeBenchmarkToOracle()
{
	my $optionsRef = shift;
	my $statsRef = shift;
	
	my $dsn = $optionsRef->{BENCHMARK_DB_DSN} || $ENV{BENCHMARK_DB_DSN};
	my $user = $optionsRef->{BENCHMARK_DB_USER} || $ENV{BENCHMARK_DB_USER} || "";
	my $pass = $optionsRef->{BENCHMARK_DB_PASS} || $ENV{BENCHMARK_DB_PASS} || "";
	
	# If benchmark_db_user flag is present (even if empty), use default credentials
	if (exists($optionsRef->{BENCHMARK_DB_USER}) && length($user) == 0)
	{
		$user = "refdb";
		$pass = 'br#^gox66312sdAB';
		INFO("Using default benchmark database credentials (user: $user)");
	}
	
	if (!defined($dsn) || length($dsn) == 0)
	{
		WARN("BENCHMARK_DB_DSN not provided, skipping Oracle benchmark insert");
		return;
	}
	
	if (length($user) == 0 || length($pass) == 0)
	{
		WARN("BENCHMARK_DB_USER or BENCHMARK_DB_PASS not provided, skipping Oracle benchmark insert");
		return;
	}
	
	my $dbh;
	eval {
		$dbh = DBI->connect("dbi:Oracle:$dsn", $user, $pass, {
			PrintError => 0,
			RaiseError => 1,
			AutoCommit => 0
		});
	};
	if ($@ || !defined($dbh))
	{
		WARN("Failed to connect to Oracle benchmark DB: $@");
		return;
	}
	
	# Use pre-calculated stats from statsRef for metadata
	my %metadata = (
		rows_fetched => $statsRef->{rows_fetched} || 0,
		rows_kept => $statsRef->{rows_kept} || 0,
		rows_dropped_status => $statsRef->{rows_dropped_status} || 0,
		rows_dropped_no_backend_lot => $statsRef->{rows_dropped_no_backend_lot} || 0,
		rows_dropped_prod_regex => $statsRef->{rows_dropped_prod_regex} || 0,
		file_type_counts => $statsRef->{file_type_counts} || {},
		file_type_rows => $statsRef->{file_type_rows} || {},
	);
	
	my %benchmark = %$statsRef;
	
	# Serialize arrays/objects to JSON strings for CLOB columns
	my $outputFilesTraceJson = JSON::PP->new->utf8->encode($statsRef->{output_files_trace} || []);
	my $outFilesJson = JSON::PP->new->utf8->encode($statsRef->{out_files} || []);
	my $metadataJson = JSON::PP->new->utf8->encode(\%metadata);
	my $benchmarkJson = JSON::PP->new->utf8->encode(\%benchmark);
	
	# Parse timestamps for Oracle
	my $startLocalTs = $statsRef->{start_local};
	my $endLocalTs = $statsRef->{end_local};
	my $startUtcTs = $statsRef->{start_utc};
	my $endUtcTs = $statsRef->{end_utc};
	
	# Convert ISO 8601 UTC format to Oracle timestamp format
	
	my $sql = q{
		INSERT INTO pipeline_runs (
			start_local, end_local, start_utc, end_utc,
			elapsed_seconds, elapsed_human, output_file, rowcount, log_file,
			pid, date_code, pipeline_name, script_name, pipeline_type, environment,
			output_files_trace, rows_extracted, rows_written, total_files, out_files,
			status, error_message, hostname, run_args, metadata, benchmark
		) VALUES (
			TO_TIMESTAMP(:start_local, 'YYYY-MM-DD HH24:MI:SS'),
			TO_TIMESTAMP(:end_local, 'YYYY-MM-DD HH24:MI:SS'),
			TO_TIMESTAMP_TZ(:start_utc, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
			TO_TIMESTAMP_TZ(:end_utc, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
			:elapsed_seconds, :elapsed_human, :output_file, :rowcount, :log_file,
			:pid, :date_code, :pipeline_name, :script_name, :pipeline_type, :environment,
			:output_files_trace, :rows_extracted, :rows_written, :total_files, :out_files,
			:status, :error_message, :hostname, :run_args, :metadata, :benchmark
		)
	};
	
	my $sth;
	eval {
		$sth = $dbh->prepare($sql);
		$sth->bind_param(':start_local', $startLocalTs);
		$sth->bind_param(':end_local', $endLocalTs);
		$sth->bind_param(':start_utc', $startUtcTs);
		$sth->bind_param(':end_utc', $endUtcTs);
		$sth->bind_param(':elapsed_seconds', $statsRef->{elapsed_seconds});
		$sth->bind_param(':elapsed_human', $statsRef->{elapsed_human});
		$sth->bind_param(':output_file', $statsRef->{output_file} || "N/A");
		$sth->bind_param(':rowcount', $statsRef->{rowcount});
		$sth->bind_param(':log_file', $statsRef->{log_file});
		$sth->bind_param(':pid', $statsRef->{pid});
		$sth->bind_param(':date_code', $statsRef->{date_code});
		$sth->bind_param(':pipeline_name', $statsRef->{pipeline_name});
		$sth->bind_param(':script_name', $statsRef->{script_name});
		$sth->bind_param(':pipeline_type', $statsRef->{pipeline_type});
		$sth->bind_param(':environment', $statsRef->{environment});
		$sth->bind_param(':output_files_trace', $outputFilesTraceJson);
		$sth->bind_param(':rows_extracted', $statsRef->{rows_extracted});
		$sth->bind_param(':rows_written', $statsRef->{rows_written});
		$sth->bind_param(':total_files', $statsRef->{total_files});
		$sth->bind_param(':out_files', $outFilesJson);
		$sth->bind_param(':status', $statsRef->{status});
		$sth->bind_param(':error_message', $statsRef->{error_message});
		$sth->bind_param(':hostname', $statsRef->{hostname});
		$sth->bind_param(':run_args', $statsRef->{run_args});
		$sth->bind_param(':metadata', $metadataJson);
		$sth->bind_param(':benchmark', $benchmarkJson);
		
		$sth->execute();
		$dbh->commit();
		INFO("Benchmark data inserted into Oracle pipeline_runs table");
	};
	if ($@)
	{
		WARN("Failed to insert benchmark into Oracle: $@");
		eval { $dbh->rollback(); };
	}
	
	eval { $sth->finish() if defined($sth); };
	eval { $dbh->disconnect(); };
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

sub waferScribeMetadata()
{
	my $laserScribe   = shift;
	my $onScribeWSURL = shift;
	my $wsCall;
	my $wnum;
	my $fabLot;
	my $status = 0;

	if ( defined($scribes{$laserScribe}))
	{
		$fabLot=$scribes{$laserScribe}{lot};
		$wnum  =$scribes{$laserScribe}{wnum};
		#INFO( "SCRIBE $laserScribe found $fabLot, $wnum");
	}
	else
	{
		$wsCall = $onScribeWSURL.$laserScribe;
		my %onScribe = getMetaFromRefDbWS($wsCall);
		if ($onScribe{status} =~ /no_data|error/i || length($onScribe{lot}) == 0)
		{
			WARN("onScribe call for $laserScribe returned no results.  This wafer will not be processed for output");
			WARN($wsCall);
			$status = 1;
		}
		else
		{
			$fabLot = $onScribe{lot};
			$wnum   = $onScribe{waferNum};
			$scribes{$laserScribe} = { lot => $fabLot, wnum => $wnum };
		}
	}

	return( $fabLot, $wnum, $status );
}

sub backendMetadata()
{
	my $backendLot          = shift;
	my $backendFacilityCode = shift;
	my $onLotWSURL          = shift;
	my ($backendSourceLot, $backendProduct, $wsCall) = ("", "", "");
	
	if ( defined($sourceLots{$backendLot}))
	{
		$backendSourceLot = $sourceLots{$backendLot};
		$backendProduct   = $sourceProducts{$backendLot};
	}
	else
	{
		# Get source lot from PP_FINALLOT first, then Web Service call 
		# Default to backend lot with .S suffix
		if ( $backendFacilityCode eq "CPA" )
		{
			($backendSourceLot, $backendProduct) = &getPPFinallotMeta($backendLot);
		}
		if ( length($backendSourceLot) <= 2)
		{
			$backendSourceLot = $backendLot . ".S";
			$wsCall = $onLotWSURL.$backendLot;
			#INFO("beWS=$wsCall");
			my %onLot = getMetaFromRefDbWS($wsCall);
		        if ($onLot{status} =~ /no_data|error/i || length($onLot{sourceLot}) == 0)
		        {
				WARN("ON_LOT WS asm call for $backendLot returned no results.  Setting source lot to $backendLot.S and product to blank");
				$backendSourceLot = $backendLot . ".S";
				$backendProduct   = "";
		        }
			else
			{
				if ( $backendFacilityCode eq "CPA" )
				{
					# Suzhou
					$backendSourceLot = $backendLot . ".S";
				}
				else
				{
					$backendSourceLot = $onLot{sourceLot}.".S";
				}
				$backendProduct   = $onLot{product};
			}
		}
		$sourceLots{$backendLot}     = $backendSourceLot;
		$sourceProducts{$backendLot} = $backendProduct;
	}
	return ($backendSourceLot, $backendProduct);
}

sub frontendMetadata()
{
	my $frontendLot = shift;
	my $onLotWSURL = shift;
	my $ppLotProdWSURL = shift;

	my ($frontendSourceLot, $frontendProduct, $frontendFabID, $frontendFab);

	if ( defined($sourceLots{$frontendLot}))
	{
		$frontendSourceLot = $sourceLots{$frontendLot};
		$frontendProduct   = $sourceProducts{$frontendLot};
		$frontendFab       = $sourceFabs{$frontendLot};
	}
	else
	{
		$wsCall=$onLotWSURL.$frontendLot;
		my %onLot = getMetaFromRefDbWS($wsCall);
		if ($onLot{status} =~ /no_data|error/i || length($onLot{sourceLot}) == 0)
		{
			my $wsCall = $ppLotProdWSURL.$frontendLot;
			#INFO("feWS=$wsCall");
			# Check xFairchild REFDB first
			my %ppLot = getMetaFromRefDbWS($wsCall);
			if ($ppLot{status} =~ /no_data|error/i or length($ppLot{sourceLot}) == 0)
			{
				WARN("No source lot found in REFDB from PP_LOT or ON_LOT for $frontendLot.  Using Snowflake source lot");
				# Put a check for .### suffix in lot ID and remove it (EFK lot)
				if ( $frontendLot =~ /^.+\.\d\d\d$/ )
				{
					$frontendSourceLot = $frontendLot;
					$frontendSourceLot =~ s/\.\d\d\d$//g;
					$frontendSourceLot .= ".S";
				}
				else
				{
					$frontendSourceLot = $frontendLot . ".S";
				}
				$frontendProduct = "";
				if ( $frontendSourceLot =~ /^K.+$/)
				{
					$frontendFabID = "KRG";
				}
				else
				{
					$frontendFabID = "";
				}
			}
			else
			{
				if ( $ppLot{sourceLot} ne $frontendLot )
				{
					WARN("Source lot \"$ppLot{sourceLot}\" from PP_LOT does not match Snowflake source lot \"$frontendLot\". Using PP_LOT source lot.");
					# Put a check for .### suffix in lot ID and remove it (EFK lot)
					if ( $ppLot{sourceLot} =~ /^.+\.\d\d\d$/ )
					{
						$frontendSourceLot = $ppLot{sourceLot};
						$frontendSourceLot =~ s/\.\d\d\d$//g;
						$frontendSourceLot .= ".S";
					}
					else
					{
						$frontendSourceLot = $ppLot{sourceLot} . ".S";
					}
				}
				else
				{
					# Put a check for .### suffix in lot ID and remove it (EFK lot)
					if ( $frontendLot =~ /^.+\.\d\d\d$/ )
					{
						$frontendSourceLot = $frontendLot;
						$frontendSourceLot =~ s/\.\d\d\d$//g;
						$frontendSourceLot .= ".S";
					}
					else
					{
						$frontendSourceLot = $frontendLot . ".S";
					}
				}
				$frontendProduct = $ppLot{product};
				$frontendFab     = $ppLot{fab};
				($frontendFabID, $str) = split(/:/, $frontendFab);
			}
		}
		else
		{
			my $srclot = $onLot{sourceLot};
			if ( $srclot =~ /\.S$/ )
			{
				$srclot =~ s/\.S$//g; 
			}
			if ( $srclot ne $frontendLot )
			{
				WARN("Source lot \"$srclot\" from ON_LOT does not match Snowflake source lot \"$frontendLot\". Using ON_LOT source lot.");
				$frontendSourceLot = $srclot . ".S";
			}
			else
			{
				$frontendSourceLot = $frontendLot . ".S";
			}
			$frontendProduct = $onLot{product};
			$frontendFabID   = $onLot{fab};
		}
		if ( exists($fabCodes{$frontendFabID}))
		{
			$frontendFab = $frontendFabID.":".$fabCodes{$frontendFabID};
		}
		else
		{
			$frontendFab = $frontendFabID;
		}

		$sourceLots{$frontendLot}     = $frontendSourceLot;
		$sourceProducts{$frontendLot} = $frontendProduct;
		$sourceFabs{$frontendLot}     = $frontendFab;
	}
	return ($frontendSourceLot, $frontendProduct, $frontendFab);
}

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


# sub getFabCodes() {
#         my %fabCodes;
#         my $dbh = DBI->connect("dbi:ODBC:MART_SNOWFLAKE", $ENV{SNOW_USER}, $ENV{SNOW_PASS});

#         if($DBI::errstr) { DpLoad_exit(1,"Unable open DB connection to SnowFlake $!"); }
#         $dbh->do("use warehouse $hOptions{SOURCE_WAREHOUSE};");
# 	$dbh->do("use database $hOptions{SOURCE_SCHEMA};");

#         my $sql ="SELECT distinct sd.mfg_area_code as MFG_AREA_CD, sd.mfg_area_description as MFG_AREA_DESC
#                   FROM enterprise.site_dim sd
#                   WHERE mfg_area_code != 'N/A'
#                   AND  mfg_area_code IS NOT NULL
#                   ORDER BY mfg_area_code";

#         my $sth=$dbh->prepare($sql);
#         $sth->execute();
#         while ( my $recs=$sth->fetchrow_hashref())
#         {
#                 $fabCodes{$recs->{MFG_AREA_CD}} = $recs->{MFG_AREA_DESC};
#         }

#         $dbh->disconnect;
#         return %fabCodes;
# }
sub getFabCodes {
	my %fabCodes;
	# Use odsConnect so connection attributes match other scripts (warehouse, DSN, etc.)
	my $dbh = odsConnect("MART_SNOWFLAKE", $hOptions{SOURCE_WAREHOUSE}, $snowflakeSvcAcct, $snowflakePass);
	my $schema = $hOptions{SOURCE_SCHEMA};
	my $fabCodesDb = "";
	my $dbName = undef;

	if ($schema =~ /^(\w+)\./) {
		$dbName = $1;
		$fabCodesDb = $dbName . ".ENTERPRISE";
	}

	if (defined $dbName) {
		eval {
			$dbh->do("use database $dbName;");
			$dbh->do("use schema $fabCodesDb;");
		};
		if ($@) { DpLoad_exit(1, "Error setting Snowflake database/schema to $dbName/$fabCodesDb: $@"); }
	}

	my $sql = "SELECT DISTINCT sd.mfg_area_code AS MFG_AREA_CD, sd.mfg_area_description AS MFG_AREA_DESC
			   FROM enterprise.site_dim sd
			   WHERE mfg_area_code != 'N/A'
			   AND mfg_area_code IS NOT NULL
			   ORDER BY mfg_area_code";

	my $sth = eval { $dbh->prepare($sql) };
	if (!defined $sth) {
		my $err = $DBI::errstr || $@ || 'unknown error';
		$dbh->disconnect;
		ERROR("getFabCodes: prepare failed for SQL: $err");
		dpExit(1, "getFabCodes: SQL prepare failure: $err");
	}

	my $exec_rc = eval { $sth->execute() };
	if (! defined $exec_rc) {
		my $err = $DBI::errstr || $@ || 'unknown error';
		$dbh->disconnect;
		ERROR("getFabCodes: execute failed: $err");
		dpExit(1, "getFabCodes: SQL execute failure: $err");
	}

	while (my $recs = $sth->fetchrow_hashref()) {
		$fabCodes{$recs->{MFG_AREA_CD}} = $recs->{MFG_AREA_DESC};
	}

	$dbh->disconnect;
	return %fabCodes;
}


# Lookup lot ID and product in PP_FINALLOT
sub getPPFinallotMeta {
	my ($lot, $sourceLot, $product);  
	$lot = shift;

	my $dbhEXN = DBI->connect("dbi:Oracle:EXNPRD", "EXN_READ", "S1x-3e45b-z");

	if($DBI::errstr) { DpLoad_exit(1,"Unable open DB connection to EXNPRD $!"); }
	my $sth=$dbhEXN->prepare("select unique lot, lot||'.S' as \"sourceLot\", product as \"product\" from REFDB.PP_FINALLOT where LOT = '$lot'");
	$sth->execute(); 
	while ( my $recs=$sth->fetchrow_hashref())
	{
		$sourceLot = $recs->{sourceLot};
		$product   = $recs->{product};
		INFO( "PP_FINALLOT $lot SrcLot=$sourceLot, Product=$product");
	}

	$dbhEXN->disconnect;
	return ($sourceLot, $product);
}

sub odsConnect() {
        my $ds = shift;
        my $wh = shift;
        my $user = shift;
        my $pass = shift;

        my $dbh = DBI->connect("dbi:ODBC:".$ds, $user, $pass, {PrintError => 0});
        if (!defined($dbh)) {
                ERROR("Error connecting to DSN '$ds'");
                ERROR("Error was: $DBI::errstr");
                dpExit(1, "Error connecting to DSN '$ds' | $DBI::errstr");
                #return 0;
        }
	$dbh->do("use warehouse $wh;");

	# If SNOW_ROLE is set in environment, try to use it so dependent objects are visible
	if (defined $ENV{SNOW_ROLE} && length $ENV{SNOW_ROLE}) {
		eval { $dbh->do("use role $ENV{SNOW_ROLE};"); };
		if ($@) { WARN("Failed to set role $ENV{SNOW_ROLE}: $@"); }
	}

	# If SOURCE_SCHEMA is provided (format DB.SCHEMA), switch to that database/schema
	if (defined $hOptions{SOURCE_SCHEMA} && $hOptions{SOURCE_SCHEMA} =~ /^(\w+)\.(\w+)$/) {
		my ($db, $schema) = ($1, $2);
		eval {
			$dbh->do("use database $db;");
			$dbh->do("use schema $schema;");
		};
		if ($@) {
			ERROR("Error setting Snowflake database/schema to $db/$schema: $@");
			dpExit(1, "Error setting Snowflake database/schema to $db/$schema: $@");
		}
	}

	return($dbh);
}

sub getSQL() {
	my $sourceODBC = shift;
	my $flow       = shift;
	my $groupBy;
	my $startTimeField;
	my $existsSQL;
	my $joinTable;

	my $criteria = "";
	my $lotCriteria = "";
	my $lotFilter = "";

	if ( $hOptions{LOT_LIST} )
	{
		# Parse comma-separated lot list into a quoted string for SQL IN clause
		my @lots = split(/,/, $hOptions{LOT_LIST});
		my $quotedLots = join(',', map { "'$_'" } @lots);
		
		# Define the lot criteria based on the stage
		if ($sourceStage eq "WAFER") {
			$lotFilter = "and v.EXENSIO_SOURCELOT in ($quotedLots)";
		} else {
			$lotFilter = "and v.${startTimeField}_LOT in ($quotedLots)";
		}
		
		# When lots are explicitly provided, we optionally widen the time criteria if modfile isn't explicitly used
		# However, keeping original logic: it still needs a time window. We just add the lot filter.
	}

	if ( $hOptions{MODFILE} )
	{
		#$criteria = "> TO_TIMESTAMP('".$modfileDate."', 'YYYY-MM-DD HH24:MI:SS.FF3')";
		#$criteria = "TO_TIMESTAMP('".$modfileDate."', 'YYYY-MM-DD HH24:MI:SS.FF3') as start_ts, dateadd(hour, 0, current_timestamp) as end_ts";
		$criteria = "TO_TIMESTAMP('".$modfileDate."', 'YYYY-MM-DD HH24:MI:SS.FF3') as start_ts, timestampadd(hour, $maxHours, TO_TIMESTAMP('".$modfileDate."', 'YYYY-MM-DD HH24:MI:SS.FF3')) as end_ts";
	}
	else
	{
		#$criteria = "between timestampadd(hour, $startHours, current_timestamp()) and dateadd(hour, $endHours, current_timestamp())";
		$criteria = "timestampadd(hour, $startHours, current_timestamp()) as start_ts, dateadd(hour, $endHours, current_timestamp()) as end_ts";
	}
	if ( $sourceStage eq "WAFER" )
	{
		$groupBy = "LASERSCRIBE";
		$startTimeField = "DIEBOND";
		$joinTable = "laserscribe_times";
		$existsSQL = "and exists(select 1 from laserscribe_times m where v.LASERSCRIBE = m.LASERSCRIBE and LASERSCRIBE_END_TIME between (select start_ts from recent_material) and (select end_ts from recent_material))";
	}
	else
	{
		$groupBy = ${sourceStage} . "_LOT";
		$startTimeField = ${sourceStage};
		$joinTable = "test_lot_times";
		$existsSQL = "and exists(select 1 from test_lot_times tt where v.${sourceStage}_LOT = tt.${sourceStage}_LOT and step_end_time between (select start_ts from recent_material) and (select end_ts from recent_material))";
	}

	my $sqlStr = "with recent_material as (
select $criteria
)
, laserscribe_times as (
select LASERSCRIBE, min(${startTimeField}_CREATE_DATE) as LASERSCRIBE_START_TIME, to_char(max(METAMODIFIEDDATE), 'YYYY-MM-DD HH24:MI:SS') as LASERSCRIBE_END_TIME
from $sourceSchema.$viewName t
group by LASERSCRIBE
)
, test_lot_times as (
select ${startTimeField}_LOT, min(${startTimeField}_CREATE_DATE) as STEP_START_TIME, to_char(max(METAMODIFIEDDATE), 'YYYY-MM-DD HH24:MI:SS') as STEP_END_TIME
from $sourceSchema.$viewName t
group by ${startTimeField}_LOT
)
";
	my ($diebond_product, $csa_product, $singulation_product, $leadframe_product, $internal2did_product, $test_product) = ("'' as DIEBOND_PRODUCT,", "'' as CSA_PRODUCT,", "'' as SINGULATION_PRODUCT,", "'' as LEADFRAME_ATTACH_PRODUCT,", "'' as INTERNAL2DID_PRODUCT,", "'' as TEST_PRODUCT,");
	if ( $getProduct )
	{
	    ($diebond_product, $csa_product, $singulation_product, $leadframe_product, $internal2did_product, $test_product) = ("DIEBOND_PRODUCT,", "CSA_PRODUCT,", "SINGULATION_PRODUCT,", "LEADFRAME_ATTACH_PRODUCT,", "INTERNAL2DID_PRODUCT,", "TEST_PRODUCT,");
	}

	if ( $flow eq "B1T" )
	{
		$sqlStr .= "select FLOW,case when FACILITY = 'OSV' then 'VN5' else FACILITY end as FACILITY
      ,v.DIEBOND_LOT,${diebond_product}DIEBOND_MACHINE,DIEBOND_CREATE_DATE,DIEBOND_FILENAME,PANEL_ID,DBC_ID,DBC_X,DBC_Y,DBC_BIN,DBC_BIN_DESCRIPTION
      ,DBC_BIN_QUALITY,DBC_BIN_PICK,DIE_TYPE ,EXENSIO_SOURCELOT,EXENSIO_WAFERID,v.LASERSCRIBE,BONDER_X,BONDER_Y,DIE_X,DIE_Y,WAFER_BIN,WAFER_BIN_DESCRIPTION
      ,WAFER_BIN_QUALITY,WAFER_BIN_PICK,v.SINGULATION_LOT,${singulation_product}SINGULATION_MACHINE,SINGULATION_CREATE_DATE,SINGULATION_FILENAME
      ,SINGULATION_ID,SINGULATION_X,SINGULATION_Y,SINGULATION_BIN,SINGULATION_BIN_DESCRIPTION,SINGULATION_BIN_QUALITY
      ,SINGULATION_BIN_PICK,v.LEADFRAME_LOT,${leadframe_product}LEADFRAME_ATTACH_MACHINE,LEADFRAME_ATTACH_CREATE_DATE,LEADFRAME_ATTACH_FILENAME,LEADFRAME_ID
      ,LEADFRAME_X,LEADFRAME_Y,LEADFRAME_BIN,LEADFRAME_BIN_DESCRIPTION,LEADFRAME_BIN_QUALITY,LEADFRAME_BIN_PICK,v.INTERNAL2DID_LOT
      ,INTERNAL2DID_MACHINE,INTERNAL2DID_CREATE_DATE,INTERNAL2DID_FILENAME,INTERNAL2DID_ID,INTERNAL2DID_X,INTERNAL2DID_Y
      ,${internal2did_product}INTERNAL2DID_BIN,INTERNAL2DID_BIN_DESCRIPTION,INTERNAL2DID_BIN_QUALITY,INTERNAL2DID_BIN_PICK
      ,v.TEST_LOT,${test_product}TEST_MACHINE,TEST_CREATE_DATE,TEST_FILENAME
      ,TEST_ID,TEST_X,TEST_Y,TEST_BIN,TEST_BIN_DESCRIPTION,TEST_BIN_QUALITY,TEST_BIN_PICK
      ,TO_CHAR(METAMODIFIEDDATE, 'YYYY-MM-DD HH24:MI:SS.FF3') as METAMODIFIEDDATE
      ,LASERSCRIBE_START_TIME,LASERSCRIBE_END_TIME,STEP_START_TIME,STEP_END_TIME
      ,BACKSIDESCRIBE,GLOBALWAFERID,PUCKID,SLICEORDER,PUCKHEIGHT,RUNID
      ,RAWWAFERSUPPLIER,RAWSILICONPRODUCT,RAWSILICONLOTID,RAWSILICONLOTTYPE,RAWWAFERSTARTDATE
      ,EPISUPPLIERNAME,EPIPRODUCT,EPILOTID,EPISTARTDATE,EPISLOT,FABPRODUCT,FABSTARTDATE,FABLOTTYPE
";
	}
	elsif ( $flow eq "PIM" )
	{
		$sqlStr .= "select FLOW,case when FACILITY = 'MY1' then 'SBN' else FACILITY end as FACILITY
       ,v.DIEBOND_LOT,${diebond_product}DIEBOND_MACHINE,DIEBOND_CREATE_DATE,DIEBOND_FILENAME
       ,PANEL_ID,DBC_ID,DBC_X,DBC_Y,DBC_BIN,DBC_BIN_DESCRIPTION,DBC_BIN_QUALITY,DBC_BIN_PICK
       ,DIE_TYPE,EXENSIO_SOURCELOT,EXENSIO_WAFERID,v.LASERSCRIBE,BONDER_X,BONDER_Y,DIE_X,DIE_Y
       ,WAFER_BIN,WAFER_BIN_DESCRIPTION,WAFER_BIN_QUALITY,WAFER_BIN_PICK
       ,CSA_LOT,${csa_product}CSA_MACHINE,CSA_CREATE_DATE,CSA_FILENAME,CSA_ID,CSA_LAYOUT,CSA_BIN,CSA_BIN_DESCRIPTION,CSA_BIN_QUALITY,CSA_BIN_PICK
       ,v.TEST_LOT,${test_product}TEST_MACHINE,TEST_CREATE_DATE,TEST_FILENAME,TEST_ID,TEST_BIN,TEST_BIN_DESCRIPTION,TEST_BIN_QUALITY,TEST_BIN_PICK
       ,TO_CHAR(METAMODIFIEDDATE, 'YYYY-MM-DD HH24:MI:SS.FF3') as METAMODIFIEDDATE
       ,LASERSCRIBE_START_TIME,LASERSCRIBE_END_TIME,STEP_START_TIME,STEP_END_TIME
       ,BACKSIDESCRIBE,GLOBALWAFERID,PUCKID,SLICEORDER,PUCKHEIGHT,RUNID
       ,RAWWAFERSUPPLIER,RAWSILICONPRODUCT,RAWSILICONLOTID,RAWSILICONLOTTYPE,RAWWAFERSTARTDATE
       ,EPISUPPLIERNAME,EPIPRODUCT,EPILOTID,EPISTARTDATE,EPISLOT,FABPRODUCT,FABSTARTDATE,FABLOTTYPE
";
	}

$sqlStr .= "from $sourceSchema.$viewName v
join laserscribe_times lt on v.LASERSCRIBE = lt.LASERSCRIBE
join test_lot_times tt on v.${startTimeField}_LOT = tt.${startTimeField}_LOT 
where ${startTimeField}_CREATE_DATE IS NOT NULL
${lotFilter}
${existsSQL}
order by METAMODIFIEDDATE";

INFO($sqlStr);
	return($sqlStr);
}

sub createOutputString 
{
	my $outStr="";
	foreach my $inStr (@_)
	{
		if (length($outStr) > 0)
		{
			$outStr .= "|";
		}

		if (length($inStr) > 0)
		{
			$outStr .= $inStr;
		}
		else
		{
			$outStr .= "NA";
		}
	}
	return $outStr;
}

