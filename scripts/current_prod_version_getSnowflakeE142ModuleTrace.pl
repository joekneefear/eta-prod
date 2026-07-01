#!/usr/bin/env perl_db

# 2022-12-02 S. Boothby : Initial version
# 2023-11-21 S. Boothby : End date -> Metamodifieddate
#                         One wafer per file
#                         Fixed bug excluding certain wafer results 
# 2023-12-22 S. Boothby : Add maximum time range command-line option.

# Query Snowflake for E142 die trace

use strict;
use File::Copy;
use FindBin::libs;
use Getopt::Long qw/:config ignore_case auto_help/;
use DBI;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use DateTime::Format::Strptime;
use Carp;
use PDF::Log;
use PDF::DAO;
use PDF::DpData;
use PDF::DpLoad;
use PDF::WS;
use IO::Compress::Gzip qw(gzip $GzipError) ;;
use Data::Dumper;

my $dt = DateTime->now(time_zone => 'local');
my $currentDateTime = join '_', $dt->ymd, $dt->hms;
$currentDateTime =~ s/[:-]//g;

my $usageMsg = "Usage: $0 --source_odbc {source-ODBC-cx} --source_warehouse {source-warehouse} --source_schema {source snowflake-db.schema} --view_name {snowflake-view-name} --flow {B1T|PIM} --get_product --stage {WAFER|DIEBOND|SINGULATION|LEADFRAME_ATTACH|INTERNAL2DID|TEST} [--modfile last-meta-modified-file] [--max_hours max-hours]|[--start_hours num-hours --end_hours num-hours] --logfile {log-file} --out_trace {trace-upload-dir} --prod_not_regexp {regex-str}\n";
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
   "OUT_TRACE"     => undef,
   "VIEW_NAME"     => undef,
   "MODFILE"       => undef,
   "MAX_HOURS"     => undef,
   "START_HOURS"   => undef,
   "END_HOURS"     => undef
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

unless (GetOptions( \%hOptions, "SOURCE_ODBC=s", "SOURCE_WAREHOUSE=s", "SOURCE_SCHEMA=s", "FLOW=s", "GET_PRODUCT", "STAGE=s", "VIEW_NAME=s", "MODFILE=s", "MAX_HOURS=s", "START_HOURS=s", "END_HOURS=s", "OUT_TRACE=s", "LOGFILE=s", "PROD_NOT_REGEXP=s")){
    print($usageMsg);
    dpExit( 1, "invalid options" );
}
PDF::Log->init(\%hOptions);

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
my $dwsth=$dbhMSSQL->prepare($sql);
if ( !defined($dwsth) || !($dwsth) )
{
	$dbhMSSQL->disconnect;
	dpExit(1, "SQL Prepare failure for $sourceODBC");
}
my $rc=$dwsth->execute;
if (! defined( $rc ))
{
	$dbhMSSQL->disconnect;
	dpExit(1, "SQL Prepare failure for $sourceODBC");
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
	}
}
$dbhMSSQL->disconnect;

#print Dumper(\%backendLotData);
#print Dumper(\%fabTestLotData);

# Write out files
my ($fileName, $lastFileName);
my @csv_files;
if ( $sourceStage ne "WAFER" )
{
	while( my ($key, $val) = each %backendLotData )
	{
		$fileName = $outputTraceDir . "/tmp/E142_${backendFacilityCode}_${flow}-$sourceStage-$currentDateTime-$key.$backwardExtensions{$sourceStage}";
		INFO("Writing: $fileName");
		open OUT, ">$fileName" or dpExit(1, "Cannot write $fileName");
		print OUT "$class53Header\n";
		push @csv_files, $fileName;

		@arr = @{$val};
		while( my ($i, $arrstr) = each @arr )
		{
			print OUT "$arrstr\n";
		}
		close OUT;
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
			push @csv_files, $fileName;
			@arr = @{$val};
			while( my ($i, $arrstr) = each @arr )
			{
				#INFO( "$arrstr");
				print OUT "$arrstr\n";
			}
			$lastFileName = $fileName;
			close OUT;
		}
	}
}
# Gzip and move files to output folder
foreach my $fileName (@csv_files)
{
	# GZIP the file first
	gzip $fileName => "$fileName.gz";
	unlink($fileName);

	move("$fileName.gz", $outputTraceDir);
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
sub getFabCodes() {
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
