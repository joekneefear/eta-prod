#!/usr/bin/env perl_db
my $ToolName = "fcs_metadata.pl";
#
#------------------------- File Header -----------------------------------
#
# File Name: fcs_metadata.pl
#
# Description: This script will add meta data to data files, and validate data in some cases.
#
# Sccs Id:    @(#)fcs_metadata.pl	2.0 06/02/2015 17:00:47
#
# Related Files/Documents:
#
# Revision History
# ________________
# Date      Author           Description
#
# 12-09-2013  S. Nashashibi     Initial Version
# 06-02-2015  Yin Zhang	        Add more features for meta input and data type
#-------------------------------------------------------------------------
# Usage:
#
# ----------------- Start CVS Section (do not modify) -------------------
#
#      $Id: fcs_metadata.pl 482 2015-06-03 06:03:18Z dpower $
      my($sVersionId) = ( split(' ', '$Revision: 482 $') )[1];
	  $sVersionId = ( split(' ', '$Revision: 482 $') )[1];
	  my($VersionAndDate) = "

2.0
";
# ------------------------- End CVS Section -----------------------------
#
##############################################################################

# Variable declarations

#use strict;
use Getopt::Long;
use File::Basename;
use File::Spec;
use DBI;
use List::Util qw(first);

# a hash to receive options
my (%hOptions)= (
	"RDIR" => undef,
	"MFILE" => undef,
	"DB" => undef,
	"username" => undef,
	"password" => undef,
	"type" => undef,
	"SEPARATOR" => undef,
	"DEBUG"  => undef,
	"HELP" => undef
);
my %hMetaData;
my $ErrorCode = 0;
my $ErrorMsg = 0;

my $metatype;
my $DataFileName;
my $DataFile;
my $type;
my $lot_id;
my $product_id;
my $meta_sql_type;

my $MetaFile = "WET_META.csv";

my $DB;
my $username = "FILEREPORT";
my $password = "x";

my $debug = 0;                #by default the debug mode is turned off
my $separator = ",";          #by default the separator is the commamy 
my $message;
my $result;

##############################################################################
#                                 Main
#
##############################################################################
# command line arguments.
Initialize_argument();

# Read Meta data from meta info file
#Read_Meta();

# Append Meta data to data file
Add_Meta();

# remove (delete) extracted Meta data (file)
Remove_Meta();

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
								"RDIR=s",
								"MFILE=s",
								"DB=s",
								"username=s",
								"password=s",
								"type=s",
								"SEPARATOR=s",
								"DEBUG" => \$debug,
								"HELP"
								)
					);
	
	if($hOptions{HELP}) {MyUsage();}
	#unless (defined($hOptions{RDIR})) {print"Missing Meta Directory!\n"; MyUsage();}
	$DataFile = shift(@ARGV);
	unless (defined($DataFile)) {MyUsage();}
	printf STDERR "Input file: $DataFile\n" if $debug;
	
	if(defined($hOptions{RDIR})) {
		print "Using file as meta data input!\n";
		$metatype=1;
		$hOptions{SEPARATOR} = $separator unless defined($hOptions{SEPARATOR});
		$separator = $hOptions{SEPARATOR};
		
		if ($hOptions{'MFILE'} ne "")	{$MetaFile = $hOptions{'MFILE'}};
		$MetaFile = "$hOptions{RDIR}/$MetaFile";
		
		printf STDERR "Meta dir: $hOptions{RDIR}\n" if $debug;
		printf STDERR "Meta input file: $MetaFile\n" if $debug;
		printf STDERR "Separator: $hOptions{SEPARATOR}\n" if $debug;
	}
	elsif(defined($hOptions{DB})) {
		print "Using database as meta data input!\n";
		$metatype=2;		
		$DB = $hOptions{DB};
		$hOptions{username} = $username unless defined($hOptions{username});
		$username = $hOptions{username};
		$hOptions{password} = $password unless defined($hOptions{password});
		$password = $hOptions{password};
		
		printf STDERR "Meta db info: $hOptions{DB}\n" if $debug;
		printf STDERR "Meta db username: $hOptions{username}\n" if $debug;
		printf STDERR "Meta db password: $hOptions{password}\n" if $debug;
	}
	else {
		MyUsage();
	}
	
	unless (defined($hOptions{type})) {print"Missing data file type!\n"; MyUsage();}
	$type = $hOptions{type};

	# set the separator
	#$hOptions{SEPARATOR} = $separator unless defined($hOptions{SEPARATOR});
	
	# Build Meta file names out of data files
	my ($volume,$directories,$file) = File::Spec->splitpath( $DataFile );
	$DataFileName = $file;
	
	# get meta file name from argument if defined
	#if ($hOptions{'MFILE'} ne "")	{$MetaFile = $hOptions{'MFILE'}};
		

	#$MetaFile = "$hOptions{RDIR}/$MetaFile";
	
	# output the option values if the debug option is turned on
	#printf STDERR "Input file: $DataFile\n" if $debug;
	#printf STDERR "Meta dir: $hOptions{RDIR}\n" if $debug;
	#printf STDERR "Meta input file: $MetaFile\n" if $debug;
	#printf STDERR "Separator: $hOptions{SEPARATOR}\n" if $debug;

	return 1;
}

##############################################################################
# Subroutine: MyUsage
##############################################################################
sub MyUsage{
	my($sUsageMsg) = <<"__END_OF_USAGE_MESSAGE__";      # Usage note
    \n$ToolName <inputfiles> ...
		You can choose 2 types of meta data source
		TYPE 1:
			[ -rdir <string> ]              Directory where the Meta data files exist
			[ -mfile <string> ]             Meta Lookup file name
		TYPE 2:
			[ -db <string> ]                DB connection info, ex: "host=serverip;port=1521;sid=exensio"
			[ -username <string> ]          DB connection username, follows -db
			[ -password <string> ]          DB connection password, follows -db
		SHARE OPTIONS:
			[ -type ]                       Data type
			[ -debug ]                      Debug mode (off by default)
			[ -help ]                       Display version ID or help messages
__END_OF_USAGE_MESSAGE__
	
	die "$sUsageMsg";
}

##############################################################################
# Subroutine: Initialize_dir
##############################################################################
sub Read_Meta{
	my $FoundMeta = 0;
	if($metatype == 1) {
		open(INPUTFILE, "$MetaFile") || DpLoad_exit(1,"Unable open Meta File: $MetaFile: $!");
		# Read Header line
		my $line = <INPUTFILE>;
		
		# remove white spaces and CR from end of line
		$line =~ s/[\s\r\n]+$//g;
		
		# Split the lines using separator
		my @Header = split(/[{$separator}]/, $line);
		while (($line = <INPUTFILE>) && ($FoundMeta != 1)) {
			# remove white spaces and CR from end of line
			$line =~ s/[\s\r\n]+$//g;
			
			# Split the lines using separator
			my @words = split(/[{$separator}]/, $line);
			
			# Fill the %hMetaData hash
			# Get Key for the Meta hash. For now it's data file name
			my $thislot_id = shift(@words);
			print STDERR "lot id in meta is: $thislot_id\n";
			if($thislot_id eq $lot_id){
				# Remove "FileName" word from Header
				shift(@Header);
				$FoundMeta = 1;
				#my %tempHash = undef;
				#@tempHash{@Header} = @words;
				@hMetaData{@Header} = @words;
				if($debug){
					print ("\n_____________Meta Header______________\n");
					pretty_print(@Header);
					print ("\n_____________Meta Date______________\n");
					pretty_print(@words);
					print ("\n_____________Meta Hash______________\n");
					pretty_print(%hMetaData);
				}
			}
		}
		close(INPUTFILE);
	}
	elsif($metatype == 2) {
		#my @filesplit = split("_", $DataFileName);
		#my $lot_id = $filesplit[3];
		my $metadb = DBI->connect("dbi:Oracle:".$DB, $username, $password);
		#print $metadb, $DBI::errstr;
		#print STDERR $lot_id;
		if($DBI::errstr) { DpLoad_exit(1,"Unable open Meta DB: $DB: $!"); }
		my $sth;
		if($meta_sql_type == 1) {
			$sth=$metadb->prepare("select * from PP_PROD p, PP_LOT l where l.LOT_ID = ? and p.PROD(+) = l.PROD");
			$sth->execute($lot_id);
		}
		elsif($meta_sql_type == 2) {
			$sth=$metadb->prepare("select * from PP_PROD p where p.PROD = ?");
			$sth->execute($product_id);			
		}
		if(my $recs=$sth->fetchrow_hashref()) {
			$FoundMeta = 1;
			foreach my $key (keys %$recs) {		
				$hMetaData{$key}=$recs->{$key};
			}
		}
		$sth->finish();
		$metadb->disconnect();
	}
	
	# Check if meta data have been found, else, exit with error
	if($FoundMeta != 1){
		DpLoad_exit(1,"Unable to find Meta data for data file: $lot_id: $!");
	}
	
}

##############################################################################
# Subroutine: AddMetaData
##############################################################################
sub Add_Meta{
	my $OutPutData = undef;
	# Open data File
	open(INPUTFILE, $DataFile) || DpLoad_exit(1,"Unable open Data File: $DataFile: $!");
	
	#$OutPutData = Print_Meta();
	# Read data file and append to output tring.
	my $regex;
	my $isFromBelowLine = 0;
	my $isItemSet = 0;
	my $hitItemLine = 0;
	
	$meta_sql_type = 1;

	if(lc($type) eq lc("NAM")) {
		$regex = "LOT ID";  #LOT ID  H013837744
	}
	elsif(lc($type) eq lc("SEPROBE")) {
		#$regex = "LOT";     #Lot,M0A0774336
		$regex = "Lot";     
	}
	elsif(lc($type) eq lc("WAT")) {
		$regex = 'LOT ID';  #LOT ID  :1FT924
	}
	elsif(lc($type) eq lc("EAGLE")) {
		$regex = "Lot";     #Lot, (first field on next line)
		$isFromBelowLine = 1;
	}
	elsif(lc($type) eq lc("CAMSTAR")) {
		$regex = "product";     #product, (first field on next line)
		$isFromBelowLine = 1;
		$meta_sql_type = 2;
	}
	elsif(lc($type) eq lc("MEET")) {
		$regex = "LOT";     #LOT M0A0774336
	}
	elsif(lc($type) eq lc("CSPMAP")) {
		$regex = "Lot No";     #Lot No      : 1FT754-CP1Q
	}
	else {
		DpLoad_exit(1,"Unknown data type : $type: $!");
	}
	
	while (<INPUTFILE>){
		if($_ =~ m/<BOM>/){
			close(INPUTFILE);
			#close(OUTPUT);
			#unlink($tempFile);
			die "Input file already has MetaData section! existing...";
		}
		$OutPutData .= $_;
		
		if(!$isItemSet) {
			if($_ =~ m/$regex/) {
				if(!$isFromBelowLine) {
					#$lot_id = ($_ =~ /^$regex\s*(\w*)\s*/ig)[0]; 
					#$lot_id = ($_ =~ /$regex\s*:?(\w*)\s*/ig)[0]; 
                                        #$lot_id = ($_ =~ /^$regex,?\s*(\w*)\s 
					#$lot_id = ($_ =~ /$regex\s*:?([A-Za-z0-9_\.]*)-*\s*/ig)[0]; 
					#$lot_id = ($_ =~ /$regex\s*[:,]?([A-Za-z0-9_\.]*)/ig)[0]; 
					$lot_id = ($_ =~ /$regex\s*[:,]?\s*([A-Za-z0-9_\.]*)/ig)[0]; 
					$isItemSet = 1;
					print STDERR "Lot id: [$lot_id] is got within current line\n"; #if $debug;
				}
				else {
					$hitItemLine = 1;
					print STDERR "Hit Item line and get Item id from next line\n" if $debug;
				}
			}
			elsif($hitItemLine) {
				if($meta_sql_type == 1) {
					$lot_id = (split(',', $_, 2))[0];
					$lot_id = ($lot_id =~ /([A-Za-z0-9_\.]*)-*\s*/ig)[0]; #1234-CP1
					print STDERR "Lot id: [$lot_id] is got within data line\n" if $debug;
				}
				elsif($meta_sql_type == 2) {
					$product_id = (split('\|', $_))[1];
					$product_id = ($product_id =~ /~([A-Za-z0-9_\.]*)~/ig)[0];
					print STDERR "Product id: [$product_id] is got within data line\n" if $debug;
				}
				
				$isItemSet = 1;
			}
		}
	}
	close(INPUTFILE);
	#print STDERR "lot id in data file is: $lot_id\n";
	
	Read_Meta();
	my $myMetaData = Print_Meta();
	
	# Open Temp File
	my $tempFile = "$DataFile.tmp";
	open(OUTPUT, '>' , $tempFile) || DpLoad_exit(1,"Unable to create Temp File: $lot_id : $!");

	print OUTPUT $myMetaData;	
	print OUTPUT $OutPutData;

	close(OUTPUT);
	#rename($DataFile,"$DataFile.bak") or die "Unable to rename: $!";
	rename($tempFile,$DataFile) or die "Unable to rename: $!";
}
##############################################################################
# Subroutine: Remove_Meta
##############################################################################

sub Remove_Meta {
	#Need to add the code to clean META file
}

##############################################################################
# Subroutine: Print_Meta
##############################################################################

sub Print_Meta {
	my $MetaOut = "<Meta generated by $ToolName Version $VersionAndDate>\n";
	$MetaOut .= "<BOM>\n";
	#$MetaOut .= "ErrorCode = $ErrorCode\n";
	#$MetaOut .= "ErrorMsg = $ErrorMsg\n";
	foreach my $key (sort keys %hMetaData){
		my $line = $key;
		$line .= " = " . $hMetaData{$key};
		$MetaOut .= "$line\n";
	}
	$MetaOut .= "<EOM>\n";
	if($debug){
		print ("\n_____________Meta Section______________\n");
		pretty_print($MetaOut);
	}
	return $MetaOut;

}

##############################################################################
# Subroutine: DpLoad_exit
##############################################################################

sub DpLoad_exit {
 my $result;
 my $outFile;
 my $message;
 my $ret_val;

 $result = $_[0];
 $message = $_[1];
 $outFile = "err.jnk";
 
 $ret_val = open(OUTFILE, ">$outFile"); 
 if ($ret_val != 1) {
   $message = "cannot open File: $outFile";
   print("$message \n"); 
   $result = 1;
   exit($result);
 }

 print OUTFILE "$result\t0\t$message\n";      
 close(OUTFILE);

 exit($result);
}

##############################################################################
# All the following subroutines are for debugging only.
##############################################################################

my $level = -1; # Level of indentation

sub pretty_print {
    my $var;
    foreach $var (@_) {
        if (ref ($var)) {
            print_ref($var);
        } else {
            print_scalar($var);
        }
    }
}

sub print_scalar {
    ++$level;
    my $var = shift;
    print_indented ($var);
    --$level;
}


sub print_ref {
    my $r = shift;
    my %already_seen;
    if (exists ($already_seen{$r})) {
        print_indented ("$r (Seen earlier)");
        return;
    } else {
        $already_seen{$r}=1;
    }
    my $ref_type = ref($r);
    if ($ref_type eq "ARRAY") {
        print_array($r);
    } elsif ($ref_type eq "SCALAR") {
        print "Ref -> $r";
        print_scalar($$r);
    } elsif ($ref_type eq "HASH") {
        print_hash($r);
    } elsif ($ref_type eq "REF") {
        ++$level;
        print_indented("Ref -> ($r)");
        print_ref($$r);
        --$level;
    } else {
        print_indented ("$ref_type (not supported)");
    }
}

sub print_array {
    my ($r_array) = @_;
    my $var;
    ++$level;
    #print_indented ("[ # $r_array");
    foreach $var (@$r_array) {
        if (ref ($var)) {
            print_ref($var);
        } else {
            print_scalar($var);
        }
    }
    print_indented ("]");
    --$level;
}

sub print_hash {
    my($r_hash) = @_;
    my($key, $val);
    ++$level; 
    #print_indented ("{ # $r_hash");
    while (($key, $val) = each %$r_hash) {
        $val = ($val ? $val : '""');
        ++$level;
        if (ref ($val)) {
            print_indented ("$key => ");
            print_ref($val);
        } else {
            print_indented ("$key => $val");
        }
        --$level;
    }
    print_indented ("}");
    --$level;
}

sub print_indented {
    my $spaces;
    $spaces = ":  " x $level;
    print "${spaces}$_[0]\n";
}
