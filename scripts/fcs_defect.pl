#!/usr/bin/perl
my $ToolName = "fcs_defect.pl";
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
# 29-05-2015  Grace 			Added support for -v option
#-------------------------------------------------------------------------
# Usage:
#
# ----------------- Start CVS Section (do not modify) -------------------
#
#      $Id: fcs_defect.pl 482 2015-06-03 06:03:18Z dpower $
      my($sVersionId) = ( split(' ', '$Revision: 482 $') )[1];
#	  $sVersionId = ( split(' ', '$Revision: 482 $') )[1];
	  my($VersionAndDate) = "

2.0
";
# ------------------------- End CVS Section -----------------------------
#
use File::Copy;
use File::Basename;
use Getopt::Long;
use File::Spec;
use DBI;
use POSIX;
use List::Util qw(first);
use PDF::DpLoad;

# a hash to receive options
my (%hOptions)= (
	"OUT" => undef,
	"DB" => undef,
	"username" => undef,
	"password" => undef,
	"DEBUG"  => undef,
	"HELP" => undef
);
my %hMetaData;

#my $waferinfo = "/data/foundry/lookup/defect_waferinfo.tbl";
#my $waferinfo = "./defect_waferinfo.tbl";

#my %defwaferinfo=();
#my $die_x_db = 10;
#my $die_y_db = 10;
my $myMetaData;

my $ErrorCode = 0;
my $ErrorMsg = 0;

my $DataFileName;
my $DataFile;
my $out = "./out/";
my $outbox;
my $success;

my $lot_id;

my $DB;
my $username = "refdb";
my $password = "refdb";

my $debug = 0;                #by default the debug mode is turned off
my $message;
my $result;



##############################################################################
#                                 Main
#
##############################################################################
# command line arguments.
Initialize_argument();

# Read wafer information
#Read_WaferInfo();

# remove (delete) extracted Meta data (file)
Die_Split();

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
								"OUT=s",
								"DB=s",
								"USERNAME=s",
								"PASSWORD=s",
								"V",
								"VERSION",
								"DEBUG",
								"HELP"
								)
					);
	if($hOptions{V} || $hOptions{VERSION} || $hOptions{help}) 
	{
	    print("$VersionAndDate\n"); 
	    dpExit(0);
	};
	
	if($hOptions{HELP}) {MyUsage();}
	#unless (defined($hOptions{RDIR})) {print"Missing Meta Directory!\n"; MyUsage();}
	$DataFile = shift(@ARGV);
	unless (defined($DataFile)) {MyUsage();}
	
	if($hOptions{DEBUG}) {
		$debug = 1;
	}
	printf STDERR "In debug mode or not: $debug\n" if $debug;
	printf STDERR "Input file: $DataFile\n" if $debug;
	
	$hOptions{OUT} = $out unless defined($hOptions{OUT});
	$out = $hOptions{OUT};	
#	$outbox = "$out/mid/";
#	$success = "$out/arcbox/split_DF/";
	
	if(defined($hOptions{DB})) {
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

	# Build Meta file names out of data files
	my ($volume,$directories,$file) = File::Spec->splitpath( $DataFile );
	$DataFileName = $file;
	
	return 1;
}
##############################################################################
# Subroutine: MyUsage
##############################################################################
sub MyUsage{
	my($sUsageMsg) = <<"__END_OF_USAGE_MESSAGE__";      # Usage note
    \n$ToolName <data file> ...
		[ -out <string> ]              Directory where the file to output
		[ -db <string> ]                DB connection info, ex: "host=serverip;port=1521;sid=exensio"
		[ -username <string> ]          DB connection username, follows -db
		[ -password <string> ]          DB connection password, follows -db
		[ -debug ]                      Debug mode (off by default)
		[ -help ]                       Display version ID or help messages
__END_OF_USAGE_MESSAGE__
	
	die "$sUsageMsg";
}

##############################################################################
# Subroutine: Initialize_db
##############################################################################
sub Read_Meta{
	my $FoundMeta = 0;

	my $metadb = DBI->connect("dbi:Oracle:".$DB, $username, $password);

	if($DBI::errstr) { DpLoad_exit(1,"Unable open Meta DB: $DB: $!"); }
	my $sth=$metadb->prepare("select * from PP_PROD p, PP_LOT l where l.LOT_ID = ? and p.PROD(+) = l.PROD");
	$sth->execute($lot_id);
	if(my $recs=$sth->fetchrow_hashref()) {
		$FoundMeta = 1;
		foreach my $key (keys %$recs) {		
			$hMetaData{$key}=$recs->{$key};
			#if($key eq "DIEX") {
			#	$die_x_db = $recs->{$key};
			#}
			#if($key eq "DIEY") {
			#	$die_y_db = $recs->{$key};
			#}			
		}
	}
	#print STDERR "From db DIEX: $die_x_db, DIEY: $die_y_db\n" if $debug;
	$sth->finish();
	$metadb->disconnect();
	
	# Check if meta data have been found, else, exit with error
	if($FoundMeta != 1){
		DpLoad_exit(1,"Unable to find Meta data for data file: $lot_id: $!");
	}
	
	if($debug) {
		pretty_print($hMetaData);
	}
}

##############################################################################
# Subroutine: Read_WaferInfo
##############################################################################
#sub Read_WaferInfo{
#	open(WIFILE, $waferinfo);
#	while(my $line_ = <WIFILE>) {
#		chomp $line_;
#		if($line_ =~ m/^#/) { next; } # comment line
#		$line_ =~ s/\s+$//g; #remove chars
#		# 01L2_LC2_160407,1110,17280
#		my @tmp = split(/,/, $line_);
#		#$defwaferinfo{$tmp[0]}{die_x} = $tmp[1];
#		#$defwaferinfo{$tmp[0]}{die_y} = $tmp[2];
#		$defwaferinfo{$tmp[0]} = {"die_x" => $tmp[1], "die_y" => $tmp[2]};
#		#print $tmp[0].$defwaferinfo{$tmp[0]}."\n";
#	}
#	close(WIFILE);
#}

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
	$MetaOut .= "<EOM>\n\n\n";
	if($debug){
		print ("\n_____________Meta Section______________\n");
		pretty_print($MetaOut);
	}
	return $MetaOut;

}

##############################################################################
# Subroutine: Die_Split
##############################################################################
sub Die_Split {
	open(FILE, "$DataFile");
	printf STDERR "Input: $DataFile\n" if $debug;
	
	my $family = "";
	my $skip_flag = 0;
	my $x_die_sep = 1;
	my $y_die_sep = 1;
	my $die_x;
	my $die_y;
	my $org_die_x;
	my $org_die_y;
	my @tmp_arr;
	my $notch = ""; # notch location

	my %SampleTestPlan = (); # SampleTestPlan count
	my %def_list = (); # DefectList coordinates hash
	my @def_data = (); # defect file data
	
	my $testplan_flg = 0;
	my $defect_flg = 0;
	my $summary_flg = 0;
	my $testplan_cnt = 0;
	my $summary_cnt = 0;
	
	while(my $line_ = <FILE>) {
		my $tmp;
		my $x_coord;
		my $y_coord;
		
		if($line_ =~ m/<BOM>/){
			close(FILE);
			die "Input file already has MetaData section! existing...";
		}
		if($line_ =~ m/^LotID/) {
			$lot_id = ($line_ =~ /^LotID "([\w\W]+)"/ig)[0];
			Read_Meta();
			$myMetaData = Print_Meta();
			#printf STDERR "DB DiePitch $die_x_db $die_y_db\n" if $debug;
			printf STDERR "Line get lot id: $lot_id\n" if $debug;
		}
		
		if(!($line_ =~ m/^ +/))
		{
			if($testplan_flg) {
				$tmp = scalar(@def_data)-1;
				chomp $def_data[$tmp];
				$def_data[$tmp] .= "\;\n";
			}
			$testplan_flg = 0;
			$defect_flg = 0;
			$summary_flg = 0;
			
			if($line_ =~ m/^SetupID/) {
				$tmp = $line_;
				chomp $tmp;
				#$tmp =~ s/\"//g;
				($tmp, $family) = split(/ /, $tmp, 2);
				$family = ($family =~ /"([\d\D]*)"\s*[\d\D]*/ig)[0];
				
				printf STDERR "Family: $family\n" if $debug;
				# FAMILY DiePitch does not exist
				#print "yes" if $family lt "FAN48630A8B";
				#if(!exists($defwaferinfo{$family}))
				if(!exists($hMetaData{"DIEX"}) || !exists($hMetaData{"DIEY"}))
				{
					print "No diex diey got from db!" if debug;
					$skip_flag = 1;
					last;
				}
				

				
			}
			elsif($line_ =~ m/^SampleTestPlan/){
				$testplan_flg = 1;
				$testplan_cnt++;
			}
			elsif($line_ =~ m/^DefectList/){
				$defect_flg = 1;
			}
			elsif($line_ =~ m/^DiePitch/){
				$tmp = $line_;
				chomp $tmp;
				$tmp =~ s/\;$//;
				($tmp, $die_x, $die_y) = split(/ /, $tmp);
				$org_die_x = $die_x;
				$org_die_y = $die_y;
			}
			elsif($line_ =~ m/^SummaryList/){
				$summary_flg = 1;
			}
			elsif($line_ =~ m/^OrientationMarkLocation/){
				$tmp = $line_;
				chomp $tmp;
				$tmp =~ s/\;$//g;
				@tmp_arr = split(/ /, $tmp);
				$notch = $tmp_arr[1];
			}
			elsif($line_ =~ m/^ClassLookup/){
				
				printf STDERR "Original DiePitch $die_x $die_y\n" if $debug;
				#printf STDERR "DB DiePitch $die_x_db $die_y_db\n" if $debug;
				# Supported notch location: DOWN, RIGHT
				if($notch eq "RIGHT")
				{
					printf STDERR "X & Y swapped due to notch location.\n" if $debug;
					#$x_die_sep = int(($die_x/$defwaferinfo{$family}{"die_y"})+0.5);
					#$y_die_sep = int(($die_y/$defwaferinfo{$family}{"die_x"})+0.5);
					$x_die_sep = int(($die_x/$hMetaData{"DIEY"})+0.5);
					$y_die_sep = int(($die_y/$hMetaData{"DIEX"})+0.5);					
				#} elsif($notch -eq "UP") {
				}
				else
				{
					#$x_die_sep = int(($die_x/$defwaferinfo{$family}{"die_x"})+0.5);
					#$y_die_sep = int(($die_y/$defwaferinfo{$family}{"die_y"})+0.5);
					$x_die_sep = int(($die_x/$hMetaData{"DIEX"})+0.5);
					$y_die_sep = int(($die_y/$hMetaData{"DIEY"})+0.5);					
				}
				printf STDERR "Sep DiePitch $x_die_sep $y_die_sep\n" if $debug;
				if($x_die_sep != 0 && $x_die_sep != 1)
				{
					$die_x = $die_x/$x_die_sep;
				}
				else
				{
					$die_x = $die_x;
				}
			
				if ($y_die_sep != 0 && $y_die_sep != 1)
				{
					$die_y = $die_y/$y_die_sep;
				}
				else
				{
					$die_y = $die_y;
				}
				printf STDERR "After DiePitch $die_x $die_y\n" if $debug;
				
				# no split necessary
				if ($x_die_sep == 1 && $y_die_sep == 1)
				{
					$skip_flag = 1;
					last;
				}
			}
			push @def_data, $line_;
		} 
		elsif($testplan_flg){
			$line_ =~ s/^  //;
			$line_ =~ s/\;//;
			$line_ =~ s/ +$//;
			($x_coord, $y_coord) = split(/ /, $line_);
			$x_coord = $x_coord * $x_die_sep;
			$y_coord = $y_coord * $y_die_sep;
			
			for(my $i=0;$i<$x_die_sep;$i++){
				for(my $j=0;$j<$y_die_sep;$j++){
					push @def_data, sprintf("  %d %d  \n", $x_coord+$i, $y_coord+$j);
					$SampleTestPlan{$testplan_cnt}++;
				}
			}
			next;
		}
		elsif($defect_flg){
			my $def_str = "";
			$line_ =~ s/^ //;
			@tmp_arr = split(/ /, $line_);
			my $x_indx_adj = 0; # x multiple numbers
			my $y_indx_adj = 0; # Y multiple numbers
			
			# XREL (DIE shift)
			if($tmp_arr[1] > $die_x) {
				$x_indx_adj = int($tmp_arr[1] / $die_x);
				$tmp_arr[1] = $tmp_arr[1] - ($die_x * $x_indx_adj);
			}
			
			# YREL (DIE shift)
			if($tmp_arr[2] > $die_y) {
				$y_indx_adj = int($tmp_arr[2] / $die_y);
				$tmp_arr[2] = $tmp_arr[2] - ($die_y * $y_indx_adj);
			}
			
			# XINDEX (X shift)
			if($x_die_sep != 0){
				$tmp_arr[3] = ($tmp_arr[3] * $x_die_sep) + $x_indx_adj;
			}
			# YINDEX (Y shift)
			if($y_die_sep != 0){
				$tmp_arr[4] = ($tmp_arr[4] * $y_die_sep) + $y_indx_adj;
			}
			
			$def_list{$tmp_arr[10]}{$tmp_arr[3]." ".$tmp_arr[4]} = 1;
			
			for(my $i = 0; $i < scalar(@tmp_arr); $i++) {
				if($i == 1 || $i == 2 || $i == 5 || $i == 6|| $i == 8) {
					$def_str .= sprintf(" %.3f", $tmp_arr[$i]);
				} elsif($i == 7) {
					$def_str .= sprintf(" %.6f", $tmp_arr[$i]);
				} else {
					$def_str .= " ".$tmp_arr[$i];
				}
			}
			push @def_data, $def_str;
		}
		elsif($summary_flg){
			$summary_cnt++;
			chomp $line_;
			$line_ =~ s/^ +//;
			$line_ =~ s/ +\;$//;
			$line_ =~ s/\s+/ /g;
			@tmp_arr = split(/ /, $line_);
			if($summary_cnt == 1) {
				$line_ = sprintf(" %d    %d    %.10e    %d    %d", $tmp_arr[0], $tmp_arr[1], $tmp_arr[2], $SampleTestPlan{$summary_cnt}, scalar(keys(%{$def_list{$summary_cnt}})));
			} else {
				$line_ = sprintf("  %d    %d    %.10e    %d    %d", $tmp_arr[0], $tmp_arr[1], $tmp_arr[2], $SampleTestPlan{$summary_cnt}, scalar(keys(%{$def_list{$summary_cnt}})));
			}
			if($summary_cnt == $testplan_cnt) {
				$line_ = $line_."  \;\n";
			} else {
				$line_ = $line_."   \n";
			}
			push @def_data, $line_;
		}
		else{
			push @def_data, $line_;
		}
	}
	close(FILE);
	
#	Read_Meta();
#	my $myMetaData = Print_Meta();
#	$myMetaData = Print_Meta();
	
	open(OUTFILE, "> $out/$DataFileName");
	printf STDERR "Output: $out/$DataFileName\n" if $debug;
	
	print OUTFILE $myMetaData;
	
	if($skip_flag) { 
		printf STDERR "$DataFileName excluded for die conversion.\n" if $debug; 
		open(FILE, "$DataFile");
		while(my $line_ = <FILE>) {
			print OUTFILE $line_;
		}
		close(FILE);
#		move("$DataFile", $success);
		return; 
	}
	
	$testplan_cnt = 1;
	foreach my $line_ (@def_data) {
		if($line_ =~ m/^DiePitch/) {
			#my @tmp = split(/ /, $line_);
			
			print STDERR sprintf("New DiePitch %.10e %.10e\n", $die_x, $die_y) if $debug;
			printf STDERR "Split(x,y): $x_die_sep $y_die_sep\n" if $debug;
			#print "$line_";
			# format DiePitch, to shift DiePitch
			$line_ = sprintf("DiePitch %.10e %.10e\;\n", $die_x, $die_y);
		}
		elsif($line_ =~ m/^SampleCenterLocation/) {
			$tmp = $line_;
			chomp $tmp;
			$tmp =~ s/\;$//;
			my @tmp_arr = split(/ /, $tmp);
			my $center_x = $tmp_arr[1];
			my $center_y = $tmp_arr[2];
			my $center_flg = 0;
			# Origin offset
			my $origin_x_offset1 = 0;
			my $origin_y_offset1 = 0;
			# Origin offset
			my $origin_x_offset2 = 0;
			my $origin_y_offset2 = 0;
			
			# SampleCenterLocation
			if($center_x != 0) {
				$origin_x_offset1 = floor($center_x / $org_die_x) * $x_die_sep;
				$origin_x_offset2 = floor($center_x / $die_x);
			}
			if($center_y != 0) {
				$origin_y_offset1 = floor($center_y / $org_die_y) * $y_die_sep;
				$origin_y_offset2 = floor($center_y / $die_y);
			}
			
			# 
			if ($origin_x_offset1 != $origin_x_offset2) {
				my $x_adj = $origin_x_offset1 - $origin_x_offset2;
				$center_x = $center_x + ($x_adj * $die_x);
				$center_flg++;
			}
			if ($origin_y_offset1 != $origin_y_offset2) {
				my $y_adj = $origin_y_offset1 - $origin_y_offset2;
				$center_y = $center_y + ($y_adj * $die_y);
				$center_flg++;
			}
			
			# 
			if ($center_flg > 0) {
				printf STDERR "Original $line_" if $debug;
				#comment the logic to shift SampleCenterLocation
				#$line_ = sprintf("SampleCenterLocation %.10e %.10e\;\n", $center_x, $center_y);
				#print "New $line_";
			}
		}
		elsif($line_ =~ m/^SampleTestPlan/) {
			$line_ = "SampleTestPlan ".$SampleTestPlan{$testplan_cnt}." \n";
			$testplan_cnt++;
		} 
		print OUTFILE $line_;
	}
	
	close(OUTFILE);
#	move("$DataFile", $success);
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
    printf STDERR "${spaces}$_[0]\n" if $debug;
}
