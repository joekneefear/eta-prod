#!/usr/bin/env perl_db
my $ToolName = "oracle_stats.pl";

#
#------------------------- File Header -----------------------------------
#
# ----------------- Start CVS Section (do not modify) -------------------
#
#      $Id: oracle_stats.pl 875 2015-08-06 16:25:26Z dpower $
      my($sVersionId) = ( split(' ', '$Revision: 875 $') )[1];
# ------------------------- End CVS Section -----------------------------
#
##############################################################################
#
# 2015-08-05  Hiroshi   Added options to DBMS_STATS.gather_table_stats

# Variable declarations

use strict;
use Getopt::Long;
use DBI;
use List::Util qw(first);
# a hash to receive options
my (%hOptions)= (
	"OWNER" => "",
	"TABLE" => "",
	"DEBUG"  => undef,
	"HELP" => undef
);

my $NullString = "n/a";

my $debug = 0;                #by default the debug mode is turned off
my $db_handle;
my $ErrorMsg = $NullString;
my $ErrorCode = 0;


# Database connection details DEV 
#my $db_tns = "dbi:Oracle:YMS01DEV";
my $db_tns = $ENV{ORACLE_TNS};
my $db_user = "/";
my $db_pass = "";

# Database connection details PROD
#my $db_tns = "dbi:Oracle:YMS01PROD";
#my $db_user = "/";
#my $db_pass = "";


# Processing module
my $scanner;

##############################################################################
#                                 Main
#
##############################################################################
# command line arguments.
Initialize_argument();

# prepare connection to the database
Initialize_db();

if($hOptions{TABLE} ne ""){
	Update_table_stats();
}
elsif($hOptions{TABLE} eq ""){
	Update_schema_stats();
}

DpLoad_exit(0,"");

##############################################################################
# Subroutine: Initialize_argument
##############################################################################
sub Initialize_argument{
	
	# turn the ignorecase option on so that the options will be case-insensitive
	$Getopt::Long::ignorecase = 1;
	$Getopt::Long::debug = 0; 
	
	# get all values of the options that the user has defined
	
	MyUsage() unless(GetOptions(\%hOptions,
								"OWNER=s",
								"TABLE=s",
								"DEBUG" => \$debug,
								"HELP",
								)
					);
	
	if ($hOptions{HELP}) {MyUsage()};
	if ($hOptions{OWNER} eq ""){
		printf STDERR "Missing Owner name.\n";
		MyUsage();
	}
	
	# output the option values if the debug option is turned on
	printf STDERR "Owner : $hOptions{OWNER}\n" if $debug;
	printf STDERR "Table : $hOptions{TABLE}\n" if $debug;
	return 1;
}

##############################################################################
# Subroutine: MyUsage
##############################################################################
sub MyUsage{
	my($sUsageMsg) = <<"__END_OF_USAGE_MESSAGE__";      # Usage note
    \n$ToolName ...
           [ -owner <string> ]             Name of the schema for which stats need to be calculated.
           [ -table <string> ]             Name of the table for which stats need to be calculated.
           [ -debug ]                      Debug mode (off by default)
           [ -help ]                       Display version ID or help messages
__END_OF_USAGE_MESSAGE__
	
	die "$sUsageMsg";
}


##############################################################################
# Subroutine: Initialize_db
##############################################################################
sub Initialize_db{
	
	# In case of failing to access the schema, use the same error handling as above.
	
	my %attr = (
		PrintError => 0,
		RaiseError => 1,
		AutoCommit => 1,
	);
	eval{
		$db_handle = DBI->connect($db_tns, $db_user, $db_pass, \%attr);
	};
	
	if ($@) {
		$ErrorMsg = sprintf("Unable to connect to Oracle database! \n");
		print("$ErrorMsg \n");
		$ErrorCode = 1;
		DpLoad_exit($ErrorCode, $ErrorMsg);
	}
}


##############################################################################
# Subroutine: Update_table_stats
##############################################################################
sub Update_table_stats{
	my $status     = undef;
	my $st_handle  = undef;
	my $rResult    = undef;
	my $rHeader    = undef;
	my $refHash    = undef;
	my %DbOptions  = ();
	my $rArray     = undef;
	my $sql = "";

	# Initialize DB connections
	my %attr = (
		PrintError => 0,
		RaiseError => 1,
		AutoCommit => 1,
	);
	eval{
		$db_handle = DBI->connect($db_tns, $db_user, $db_pass, \%attr);
	};
	
	if ($@) {
		$ErrorMsg =  "ERROR: [DBI Connect] $DBI::errstr";
		print("$ErrorMsg \n");
		$ErrorCode = 1;
		DpLoad_exit($ErrorCode, $ErrorMsg);
	};
	eval {
		my $func = $db_handle->prepare("
			BEGIN
				--DBMS_STATS.gather_table_stats('$hOptions{OWNER}','$hOptions{TABLE}',cascade => true);
				dbms_stats.unlock_table_stats('$hOptions{OWNER}','$hOptions{TABLE}');
				
				--DBMS_STATS.gather_table_stats('$hOptions{OWNER}','$hOptions{TABLE}',cascade => true);
				DBMS_STATS.gather_table_stats('$hOptions{OWNER}','$hOptions{TABLE}',method_opt =>'FOR ALL INDEXED COLUMNS', cascade=> true,  estimate_percent => dbms_stats.auto_sample_size);
				
				dbms_stats.lock_table_stats('$hOptions{OWNER}','$hOptions{TABLE}');

			END;");
		$func->execute;
	};
	
	if( $@ ) {
		warn "Execution of stored procedure failed: $DBI::errstr\n";
	}
	print "Execution of stored procedure succeeded. \n";

	$db_handle->disconnect;
		
}

##############################################################################
# Subroutine: Update_schema_stats
##############################################################################
sub Update_schema_stats{
	my $status     = undef;
	my $st_handle  = undef;
	my $rResult    = undef;
	my $rHeader    = undef;
	my $refHash    = undef;
	my %DbOptions  = ();
	my $rArray     = undef;
	my $sql = "";

	# Initialize DB connections
	my %attr = (
		PrintError => 0,
		RaiseError => 1,
		AutoCommit => 1,
	);
	eval{
		$db_handle = DBI->connect($db_tns, $db_user, $db_pass, \%attr);
	};
	
	if ($@) {
		$ErrorMsg =  "ERROR: [DBI Connect] $DBI::errstr";
		print("$ErrorMsg \n");
		$ErrorCode = 1;
		DpLoad_exit($ErrorCode, $ErrorMsg);
	};
	eval {
		my $func = $db_handle->prepare("
			BEGIN
				DBMS_STATS.gather_schema_stats('$hOptions{OWNER}');
			END;");
		$func->execute;
	};
	
	if( $@ ) {
		warn "Execution of stored procedure failed: $DBI::errstr\n";
	}
	print "Execution of stored procedure succeeded. \n";

	$db_handle->disconnect;
		
}

##############################################################################
# Subroutine: DpLoad_exit
##############################################################################
sub DpLoad_exit {
 my $ErrorCode;
 my $outFile;
 my $ErrorMsg;
 my $ret_val;

 $ErrorCode = $_[0];
 $ErrorMsg = $_[1];
 $outFile = "err.jnk";
 
 $ret_val = open(OUTFILE, ">$outFile"); 
 if ($ret_val != 1) {
   $ErrorMsg = "cannot open File: $outFile";
   print("$ErrorMsg \n"); 
   $ErrorCode = 1;
   exit($ErrorCode);
 }

 print OUTFILE "$ErrorCode\t0\t$ErrorMsg\n";      
 close(OUTFILE);
 if($ErrorMsg ne ""){   print("$ErrorMsg \n"); }
 exit($ErrorCode);
}

