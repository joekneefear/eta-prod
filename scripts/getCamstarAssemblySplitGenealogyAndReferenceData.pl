#!/usr/bin/env perl_db
# 2017-12-05 : jgarcia : initial
# 2018-06-07 : jgarcia : replace the $flotSQL with the new sql statement provided by Scott Boothby. this is include all finished good lots with activity in Camstar, not just the splits or lots with consumed (wafer sort) material.
# 2018-06-08 : jgarcia : modified $flotSQL query, change where clause criteria “and hm.Qty2=0.0 “ to “and hm.Qty2=0.0 “.
# 2021-02-08 : jgarcia : dont load genealogy to Exensio DB.
# 2021-02-22 : jgarcia : gzip gen file.
# 2021-03-01 : jgarcia : copy castSplitGen file to cloudsite-upload.
# 2025-11-24 : sboothby : add ".S" after source lot ID to be consistent with other scripts writing this format.  Fixed source lot lookup.
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
use PDF::DpLoad;
use IO::Compress::Gzip qw(gzip $GzipError) ;;
use Data::Dumper;

my %hOptions = ();

unless (GetOptions( \%hOptions, "OUT=s", "OUTMESGEN=s", "ARCHIVE_GEN=s", "ARCHIVE_FLOT=s", "LOGFILE=s", "START_HOURS=s", "END_HOURS=s")){
#	  print("Invalid Options");
    dpExit( 1, "invalid options" );
}
PDF::Log->init(\%hOptions);

unless ( $hOptions{ARCHIVE_GEN} ) {
    dpExit( 1, "--ARCHIVE_GEN argument is required!" );
    pod2usage(3);
}
unless ( $hOptions{ARCHIVE_FLOT} ) {
    dpExit( 1, "ARCHIVE_FLOT argument is required!" );
    #pod2usage(3);
}
unless ( $hOptions{OUT} ) {
    dpExit( 1, "--OUT argument is required!" );
    #pod2usage(3);
}
unless ( $hOptions{OUTMESGEN} ) {
    dpExit( 1, "--OUTMESGEN argument is required!" );
    #pod2usage(3);
}
unless ( $hOptions{START_HOURS} ) {
    dpExit( 1, "--START_HOURS argument is required!" );
    #pod2usage(3);
}
unless ( $hOptions{END_HOURS} ) {
    dpExit( 1, "--END_HOURS argument is required!" );
    #pod2usage(3);
}

my $outputLocation = $hOptions{OUT};
my $archiveDirGen = $hOptions{ARCHIVE_GEN};
my $archiveDirLot = $hOptions{ARCHIVE_FLOT};
my $cloudsiteUpload = $hOptions{OUTMESGEN};
my $startHours = $hOptions{START_HOURS};
my $endHours = $hOptions{END_HOURS};

my $cebuDataSource = q/dbi:ODBC:MSSQL-Perl/;
my $szDataSource = q/dbi:ODBC:MSSQL-Suzhou/;
my $cpUser = q/ymsapp_rd/;
my $szUser = q/ymsapp_ro/;
my $password = q/yms20150/;
my $dbh;

#my $headerInfoGen = "GEN_DATE|LOT|PRODUCT|FAB|GEN_EVENT|FROM_LOT|FROM_PRODUCT|FROM_FAB|SOURCE_LOT|SOURCE_PRODUCT|SOURCE_FAB\n";
my $headerInfoRef = "LOT|LOT_OWNER|PRODUCT|DATE_CODE\n";
my %lotStr = ();
#my $archiveDirGen = "/archives-yms/reference_data/genealogy";
#my $archiveDirLot = "/archives-yms/reference_data/lot";
my $generatedFile;


my $genSQL = qq/with sourceLotCTE as 
(
    select c.containername as from_containername
         , shd.tocontainername as to_containername
         , 1 as q_level
         , c.containername as first_from_containername
         , shd.tocontainername as start_containername
    from splithistory sh
    join container c on sh.fromcontainerid = c.containerid
    join splithistorydetails shd on sh.splithistoryid = shd.splithistoryid
    join historymainline hm on sh.historymainlineid = hm.historymainlineid
    where hm.txndate >= dateadd(HOUR, $startHours, getdate()) and hm.txndate <= dateadd(HOUR, $endHours, getdate())
    union all
    select c.containername as from_containername
         , shd.tocontainername as to_containername
         , sl.q_level + 1 as q_level
         , sl.first_from_containername as first_from_containername
         , sl.start_containername as start_containername
    from splithistory sh
    join container c on sh.fromcontainerid = c.containerid
    join splithistorydetails shd on sh.splithistoryid = shd.splithistoryid
    join sourceLotCTE sl on shd.tocontainername = sl.from_containername
)
, source_lots as
(
    select from_containername as source_lot
         , first_from_containername as from_lot
         , start_containername as lot
         , dense_rank()  OVER (PARTITION by START_CONTAINERNAME ORDER BY q_level DESC) as DR
    from sourceLotCTE
)
select hm.TXNDATE AS GEN_DATE
     , shd.tocontainername AS LOT
     , hm.productname      AS PRODUCT
     , ' '                 AS FAB
     , shd.tocontainername + '_' + sl.from_lot + '_' + sl.source_lot + '.S' AS GEN_EVENT
     , sl.from_lot         AS FROM_LOT
     , isnull(replace(fa.opn, '-', '_'), hm.productname) AS FROM_PRODUCT
     , ' '                 AS FROM_FAB
     , sl.source_lot       AS SOURCE_LOT
     , isnull(replace(fa.opn, '-', '_'), hm.productname) AS SOURCE_PRODUCT
     , ' '                 AS SOURCE_FAB
from splithistory sh
join container c on sh.fromcontainerid = c.containerid
join splithistorydetails shd on sh.splithistoryid = shd.splithistoryid
join historymainline hm on sh.historymainlineid = hm.historymainlineid
join workflowstep ws on hm.workflowstepid = ws.workflowstepid
join workflow w on ws.workflowid = w.workflowid
join container fc on c.containername = fc.containername
join A_LotAttributes fa on fc.containerid = fa.containerid
join source_lots sl on shd.tocontainername = sl.lot and sl.DR = 1
where hm.txndate >= dateadd(HOUR, $startHours, getdate()) and hm.txndate <= dateadd(HOUR, $endHours, getdate())
  and w.objecttype = 'ASSEMBLY'
order by hm.txndate/;

=pod
my $flotSQL = qq/select shd.tocontainername AS LOT
, hm.ownername        AS LOT_OWNER
, hm.productname      AS PRODUCT
, a.fsc7DigitDateCode AS DATE_CODE
from splithistory sh
join splithistorydetails shd on sh.splithistoryid = shd.splithistoryid
join historymainline hm on sh.historymainlineid = hm.historymainlineid
join workflowstep ws on hm.workflowstepid = ws.workflowstepid
join workflow w on ws.workflowid = w.workflowid
join container toc on shd.tocontainername = toc.containername
join A_LotAttributes a on toc.containerid = a.containerid
where hm.txndate >= dateadd(HOUR, $startHours, getdate()) and hm.txndate <= dateadd(HOUR, $endHours, getdate())
and w.objecttype = 'ASSEMBLY'
order by shd.tocontainername/;
=cut

my $flotSQL = qq/with materialactivity as
(
select distinct 
       hm.containername as LOT
     , coalesce(fa.onsLotType, 
           case when hm.ownername in ('CPROD', 'ONPS') then 'PS' 
                when hm.ownername = 'ONNN' then 'NN'
                when hm.ownername = 'ONNS' then 'NS'
                when hm.ownername = 'ONPN' then 'PN'
                when hm.ownername = 'ONTE' then 'TE'
                else hm.ownername
           end) as LOT_OWNER
     , replace(case when patindex('_%-_%-___', hm.productname) > 0
                      or (patindex('_%-___', hm.productname) > 0 AND REVERSE(SUBSTRING(REVERSE(hm.productname),0,CHARINDEX('-',REVERSE(hm.productname)))) in 
                      ('ASM','ASY','WDQ','FAB','DSG','EPC','ECH','DFF','SCB','UTP','BMP','WFA','WBP','WPR','BSM'
                      ,'FSM','SWF','FTP','TST','XTD','FTD','APT','UTD','EPT','EPU','XTP','WAF','DIE','XWF','THN'
                      ,'FMD','XMD','EPM','BAS','DWR','NRE','XDW','GLD','XDI','XDS','EPD','DST','EPA','EPW'))
               then SUBSTRING(hm.productname,0, LEN(hm.productname)-CHARINDEX('-',REVERSE(hm.productname)))
               else hm.productname end
               , '-','_') as PRODUCT
, fa.fsc7DigitDateCode as DATE_CODE
--, fa.*
--, c.*
--, hm.*
from historymainline hm
join container c on hm.containerid = c.containerid
join workflowstep ws on hm.workflowstepid = ws.workflowstepid
join workflow w on ws.workflowid = w.workflowid
left join A_LotAttributes fa on hm.containerid = fa.containerid
where hm.txndate >= dateadd(HOUR, $startHours, getdate()) and hm.txndate <= dateadd(HOUR, $endHours, getdate())
and hm.containername not like 'PR%'
and w.objecttype = 'ASSEMBLY' --not in ('MATERIAL', 'DIEBANK')
and UOMName = 'UNIT'
and hm.ownername not like 'CPREA'
and hm.Qty2!=1.0 -- Indicates assembly part vs. pre-saw wafer
)
-- ref data has header row LOT|LOT_OWNER|PRODUCT|DATE_CODE
, splitinfo as ( 
select distinct 
       shd.tocontainername AS LOT
     --, hm.ownername        AS LOT_OWNER
     , coalesce(a.onsLotType, 
           case when hm.ownername in ('CPROD', 'ONPS') then 'PS' 
                when hm.ownername = 'ONNN' then 'NN'
                when hm.ownername = 'ONNS' then 'NS'
                when hm.ownername = 'ONPN' then 'PN'
                when hm.ownername = 'ONTE' then 'TE'
                else hm.ownername
           end) as LOT_OWNER
     --, hm.productname      AS PRODUCT
     , replace(case when patindex('_%-_%-___', hm.productname) > 0
                      or (patindex('_%-___', hm.productname) > 0 AND REVERSE(SUBSTRING(REVERSE(hm.productname),0,CHARINDEX('-',REVERSE(hm.productname)))) in 
                      ('ASM','ASY','WDQ','FAB','DSG','EPC','ECH','DFF','SCB','UTP','BMP','WFA','WBP','WPR','BSM'
                      ,'FSM','SWF','FTP','TST','XTD','FTD','APT','UTD','EPT','EPU','XTP','WAF','DIE','XWF','THN'
                      ,'FMD','XMD','EPM','BAS','DWR','NRE','XDW','GLD','XDI','XDS','EPD','DST','EPA','EPW'))
               then SUBSTRING(hm.productname,0, LEN(hm.productname)-CHARINDEX('-',REVERSE(hm.productname)))
               else hm.productname end
               , '-','_') as PRODUCT
     , a.fsc7DigitDateCode AS DATE_CODE 
from splithistory sh
join splithistorydetails shd on sh.splithistoryid = shd.splithistoryid
join historymainline hm on sh.historymainlineid = hm.historymainlineid
join workflowstep ws on hm.workflowstepid = ws.workflowstepid
join workflow w on ws.workflowid = w.workflowid
join container toc on shd.tocontainername = toc.containername
join A_LotAttributes a on toc.containerid = a.containerid
where hm.txndate >= dateadd(HOUR, $startHours, getdate()) and hm.txndate <= dateadd(HOUR, $endHours, getdate())
  and w.objecttype = 'ASSEMBLY'
)
select * from splitinfo
union 
select * from materialactivity ma;/;

my $genRowsWritten = 0;
my $dateTime = &currentDate();
$dateTime =~ s/\/|\://g;
$dateTime =~ s/\s+/\_/g;
my $extractFilenameGen = "${cloudsiteUpload}/CamstarAssemblySplitGenealogy-${dateTime}.castSplitGen";
my $extractFilenameRef = "${outputLocation}/CamstarAssemblyReferenceData-${dateTime}.castSplitFlot";

INFO("Connecting to Cebu Camstar ODS ");
my $dbh = &odsConnect($cebuDataSource, $cpUser, $password);
if ($dbh) {
	INFO("Connected succesfully to CP camstar ODS!!!");
}
INFO("Retrieving data from Camstar ODS using SQL to retrieve assembly split data");
%lotStr = &retrieveRows($genSQL);
INFO("Call writeExtractToFile subroutine");
INFO("Generate .castSplitGen file from Cebu Camstar ODS");
$generatedFile = &writeExtractToFile($extractFilenameGen, "", "CP");
INFO("Copy $generatedFile to archive");
&copyToArchive($generatedFile);
INFO("Gzip gen file");
qx(gzip "$generatedFile");
unlink $generatedFile;
#INFO("Load the generated file");
#&loadGenFile($generatedFile);

INFO("Retrieving data from Camstar ODS using SQL to retrieve reference data");
%lotStr = &retrieveRows($flotSQL);
INFO("Call writeExtractToFile subroutine");
INFO("Generate .castSplitFlot file from Cebu Camstar ODS");
$generatedFile = &writeExtractToFile($extractFilenameRef, $headerInfoRef, "CP");
INFO("Copy $generatedFile to archive");
&copyToArchive($generatedFile);
$dbh->disconnect;
INFO("##################################################################################################################");

INFO("Connecting to Suzhou Camstar ODS ");
$dbh = &odsConnect($szDataSource, $szUser, $password);
if ($dbh) {
	INFO("Connected succesfully to Suzhou camstar ODS!!!");
}

INFO("Retrieving data from Suzhou Camstar ODS using SQL to get assembly split data");
%lotStr = &retrieveRows($genSQL);
#print Dumper(%lotStr);
INFO("Call writeExtractToFile subroutine");
INFO("Generate .castSplitGen file from Suzhou Camstar ODS");
$generatedFile = &writeExtractToFile($extractFilenameGen, "", "SZ");
INFO("Copy $generatedFile to archive");
&copyToArchive($generatedFile);
INFO("Gzip gen file");
qx(gzip "$generatedFile");
unlink $generatedFile;
#INFO("Load the generated file");
#&loadGenFile($generatedFile);

INFO("Retrieving data from Suzhou Camstar ODS using SQL to extract Flot ref data");
%lotStr = &retrieveRows($flotSQL);
INFO("Call writeExtractToFile subroutine");
INFO("Generate .castSplitFlot file from Suzhou Camstar ODS");
$generatedFile = &writeExtractToFile($extractFilenameRef, $headerInfoRef, "SZ");
INFO("Copy $generatedFile to archive");
&copyToArchive($generatedFile);
$dbh->disconnect;


dpExit(0);

##### SUBROUTINES ######


=pod
sub loadGenFile() {
	
	my $file = shift;
	if ($genRowsWritten > 0) {
		
		INFO("Running DBTOOLS to load $file");
    system("$ENV{DPBIN}/dbtools -n 29 -db $schema -fmt $formatReader -infile $file");
    my $rc=$?;
    if ( $rc == 0 ){
       INFO("#### DBTOOLS Exited Successfully ####");
       move($file, ${outputLocation}."/Processed");   
    }
    else {
       INFO("#### DBTOOLS Completed With Error ####");
       move($file, ${outputLocation}."/NotProcessed");   
    }
    
	}
	
}
=cut

sub copyToArchive() {
	my $file = shift;
	my $destinationFilename;
	if (-e $file) {
		if ($file =~ /\.castSplitGen$/) {
			$destinationFilename = basename($file);
			my $archivedFile = "${archiveDirGen}/${destinationFilename}.gz";
			INFO("Check if $archivedFile already exist");
			if(-e $archivedFile) {
				INFO("$archivedFile already exist");
				INFO("Delete $archivedFile");
				unlink $archivedFile;
			} else {
				INFO("$archivedFile cant be found in archive folder");
			}
			copy("$file", "${archiveDirGen}/${destinationFilename}");
			my $gzFile = "${archiveDirGen}/${destinationFilename}";
			qx(gzip "$gzFile");
			#my $status = gzip "${archiveDirGen}/${destinationFilename}" => "${archiveDirGen}/${destinationFilename}.gz";
			#my $status = gzip "$file" => "${archiveDirGen}/${destinationFilename}.gz";
			#gx(gzip $gzFile);
			#print "$status";
			
		} elsif ($file =~ /\.castSplitFlot$/) {
			$destinationFilename = basename($file);
			my $archivedFile = "${archiveDirLot}/${destinationFilename}.gz";
			INFO("Check if $archivedFile already exist");
			if(-e $archivedFile) {
				INFO("$archivedFile already exist");
				INFO("Delete $archivedFile");
				unlink $archivedFile;
			} else {
				INFO("$archivedFile cant be found in archive folder");
			}
			copy("$file", "${archiveDirLot}/${destinationFilename}");
			my $gzFile = "${archiveDirLot}/${destinationFilename}";
		    qx(gzip "$gzFile");
			#my $status = gzip "${archiveDirLot}/${destinationFilename}" => "${archiveDirLot}/${destinationFilename}.gz";
			#my $status = gzip "$file" => "${archiveDirLot}/${destinationFilename}.gz";
			#print "$status";
		}
		
	}
}


sub writeExtractToFile() {
	#my %result = shift;
	my $extractFileFilename = shift;
	my $header = shift;
	my $site = shift;
	my $OUTFILE;
	
	#$extractFileFilename = "$hOptions{OUT}/${site}_${extractFileFilename}";
	my ($fname, $ext) = split(/\./, $extractFileFilename, 2);
	$extractFileFilename = "${fname}_${site}.${ext}";
	INFO("Open file $extractFileFilename");
	open($OUTFILE, '>', $extractFileFilename) or dpExit(1, "Could not open file $extractFileFilename $!");
	my @resultArray = values %lotStr;
	INFO("Writing Header");
	print $OUTFILE $header;
	INFO("Writing line data");
	print $OUTFILE join("\n", @resultArray);
	print $OUTFILE "\n";
	close $OUTFILE;
	INFO("Done Writing to $extractFileFilename.");
	INFO("Close file $extractFileFilename");
	return($extractFileFilename);
}

sub odsConnect() {
	my $ds = shift;
	my $user = shift;
	my $pass = shift;
	
	$dbh = DBI->connect($ds, $user, $pass, {PrintError => 0});
	if (!defined($dbh)) {
		ERROR("Error connecting to DSN '$ds'");
		ERROR("Error was: $DBI::errstr");
		dpExit(1, "Error connecting to DSN '$ds' | $DBI::errstr");
		#return 0;
	}
	return($dbh);
}

sub querySQL() {
	my $sql = shift;
	my $dataSource = shift;
	my $usr = shift;
	my $pass = shift;
	my ($sth, $rc);
	

	if (!($sql)) {
		ERROR("Must pass SQL statement to querySQL!");
		dpExit(1, "No SQL statement");
	}

	###Verify that we are connectd to the database
	if (!($dbh) || !($sth = $dbh->prepare("GO"))) {

		###Attemp to reconnect to the database
		$dbh = DBI->connect($dataSource, $usr, $pass, {PrintError => 0});
		if (!($dbh)) {
			ERROR("Unable to connect to database");
			dpExit(1, "Could not connect databse!!!");
		}
	} else {
		$sth->execute;
		$sth->finish;
	}

	$sth = $dbh->prepare($sql);

	if (!defined($sth) || !($sth)) {
		ERROR("Failed to prepare SQL statement: $DBI::errstr");
		
		#
		# Check for a connection error -- should not occur
		#
		if ($DBI::errstr =~ /Connection failure/i){
			$dbh = DBI->connect($dataSource, $usr, $pass, {PrintError => 0});
			if (!($dbh)) {
				ERROR("Unable to connect to database");
				#dpExit(1, "Could not connect database!!!");
			} else	{
				INFO("Database connection re-established, attempting to prepare again.");
				$sth = $dbh->prepare($sql);
			}
		}
		#
		# Check to see if we recovered
		#
		if ( ! defined( $sth ) || ! ($sth) ) {
			ERROR("Unable to prepare SQL statement:");
			INFO("$sql");
			#dpExit(1, "Unable to prepare SQL statement, there might be an issue with the connection...");;
		}

	}

	# Attempt to execute our prepared statement
	#
	$rc = $sth->execute;

	if (! defined( $rc ) ) {
		#
		# We failed, print the error message for troubleshooting
		#
		ERROR("Unable to execute prepared SQL statement: $DBI::errstr");
		INFO("$sql");

		dpExit(1, "Unable to execute prepared SQL statement: $DBI::errstr");
	}

	#
	# All is successful, return the statement handle
	#

	return ($sth);

}

sub retrieveRows() {

	my ($sql, $sth, $type);
	my %hashRow = ();
	$sql = shift;
		
	if ($sql =~ /AS GEN_DATE/i) {
		INFO("Generating .castSplitGen extract.");
		$type = "castSplitGen";
	} elsif($sql =~ /AS DATE_CODE/i) {
		INFO("Generating .castSplitFlot extract.");
		$type = "refDataFlot";
	}
	#print ">>$sql<<";
	$sth = &querySQL($sql);  # Pass the SQL statement to the server

	#
	# Check that we received a statement handle
	#
	if (! ($sth) ) {
		return 0;
	}

	#
	# Retrieve the rows from the SQL server
	#

	while( my $ref = $sth->fetchrow_hashref() ) {
		my $line;
		if ($type =~ /castSplitGen/i) {
			#GEN_DATE|LOT|GEN_EVENT|FROM_LOT|SOURCE_LOT
			$ref->{GEN_DATE} =~ s/\.000$//g;
			$line = "MOUT|$ref->{GEN_DATE}|$ref->{SOURCE_LOT}.S|$ref->{FROM_PRODUCT}|$ref->{FROM_LOT}|$ref->{PRODUCT}|$ref->{LOT}|$ref->{GEN_EVENT}";
			$genRowsWritten++;
		} elsif($type =~ /refDataFlot/i) {
			$line = "$ref->{LOT}|$ref->{LOT_OWNER}|$ref->{PRODUCT}|$ref->{DATE_CODE}";
		}

		$hashRow{$ref->{LOT}} = $line;
		#push(@resultArray, [@$ref]);

	}
	
	return %hashRow;
}


