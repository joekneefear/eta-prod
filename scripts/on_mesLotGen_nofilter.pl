#!/usr/bin/env perl_db
#$Id

# Preprocess and load MES genealogy data into Exensio.
# NOTE: Must perform preprocessing *and* load single-threaded.
# If dbtools is processing files while the preprocessor is also running,
# the preprocessor may fail to remove genealogy history that is currently loading.
#
# Load process:
# Read the incoming *.mes files and produce two output files for each .mes file:
#   *.meslot lot reference data for loading to REFDB.
#   *.mesgen genealogy file for lot, from_lot data.
#
# Incoming .mes file columns:
# BUSINESS_UNIT, FACILITY, PARENT_LOT, CHILD_LOT, PARENT_PROD, CHILD_PROD, OWNER, TRANS, TRANSACTION_DATE_TIME, SOURCE_LOT, SOURCE_PROD, SOURCE_INV_ITEM_TYPE, PATH
#
# .meslot will consist of the unique values for CHILD_LOT (LOT), SOURCE_LOT (PARENT_LOT), SOURCE_PROD (PRODUCT), OWNER (LOT_OWNER), SOURCE_LOT (SOURCE_LOT)
# .mesgen will consist of the unique values for TRANSACTION_DATE_TIME (GEN_DATE), CHILD_LOT (LOT), SOURCE_PROD (PRODUCT), <CHILD_LOT>_<PARENT_LOT>_<SOURCE_LOT> (GEN_EVENT), 
#                                               PARENT_LOT (FROM_LOT), PARENT_PROD (FROM_PRODUCT), SOURCE_LOT (SOURCE_LOT), SOURCE_PROD (SOURCE_PRODUCT)
# ***** Verify whether fab info is needed in .mesgen *****
# When SRCLOT_LOOKUP option is included, check the REFDB PP_LOT table for lot equal to existing SOURCE_LOT, and if that lot's source lot is
# different from SOURCE_LOT, substitute PP_LOT's source lot.
#
# Option USE_CHILD_PROD indicates to use the CHILD_PROD field for PP_LOT's product field.  Otherwise use source product.
#
# Files must be loaded with the -mtime option in load.mgr.
# Preprocessor checks database for existing lot_gevent.event_name = GEN_EVENT entries.
# Only new gen events are written to output file.
# lot split times from MES data will not be the same as times from PSoft. Code accounts for this by discarding events already in DB by name, not name + date 
# Output .gen file entries must be written with earliest gen event dates first to ensure LOT2LOTGEN is properly loaded.
#
# When dbtools loads LOT2LOTGEN it looks for parents of the from lot to establish lineage.  It does not
# look at children of the child lots so load order is important.
# As of 1.7.1, dbtools does not check whether a new entry in the lot lineage already exists in LOT2LOTGEN so
# it is important to delete events already loaded to prevent duplication. 
#
# MODIFICATION HISTORY:
# WHEN        WHO             WHAT
# ----------- --------------- --------------------------------------------------------------------------------
# 30-Sep-2016 S. Boothby      Created.
# 13-Oct-2016 S. Boothby      Exclude T and TE owner codes.
# 27-Mar-2017 S. Boothby      Added support for extracts from Cebu Camstar wafer sort.
# 16-OCT-2017 J. Garcia				Added support for Camstar Sort to Assembly Genealogy (.cast) extracts from Cebu and Suzhou.
# 16-OCT-2017 J. Garcia				Exclude rows without Parent product and source lot from .cast extracts.
# 15-DEC-2017 J. Garcia				fix bug. to support again parsing .mes extracts.
# 17-JAN-2018 J. Garcia				added support for .lotGgen extracts.
# 13-MAR-2018 S. Boothby      Don't ignore entire row if source product or source lot is blank, create FINALLOT and genealogy row if able.
#                             Genealogy output was using source product for CAST files in genealogy output, should have been child product.
# 26-JUN-2019 S. Boothby      Variant with no ref table output and no filtering on genealogy based on existing data in DB.
# 05-FEB-2021 J. Garcia       write out REF file. remove SCHEMA and FMT command line arguments.
# 01-MAR-2021 J. Garcia       write out genealogy to a seprate location than ref file.
# 26-May-2022 S. Boothby      Added support for lotG2mes/lotG2mesgen files.
# 15-Nov-2022 S. Boothby      Added GENERATE_MESLOT option.
use strict;
use File::Copy;
use FindBin::libs;
use Getopt::Long;
use DBI;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename fileparse/;
use POSIX qw(strftime);
use DateTime::Format::Strptime;
use PDF::Log;
use PDF::DpLoad;
use PDF::DAO;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Formatter;
use IO::Compress::Gzip qw(gzip $GzipError);
use v5.10;

### Check Argument
my (%hOptions) = (
    "LOGFILE" => undef,
    "ARCHIVE" => undef,
    "OUT"   => undef,
	"OUTMESGEN" => undef
);
unless ( GetOptions( \%hOptions,  "OUT=s", "OUTMESGEN=s", "LOGFILE=s", "ARCHIVE=s", "SRCLOT_LOOKUP", "USE_CHILD_PROD", "GENERATE_MESFLOT", "GENERATE_MESLOT" ) && (@ARGV > 0))
{
    print "USAGE: $0 <fileName> --out {output dir} --outmesgen {mesgen output dir } --archive {archive dir} --log {log} --srclot_lookup --use_child_prod --generate_mesflot --generate_meslot\n";
    exit(1);
    #pod2usage(3);
}

PDF::Log->init( \%hOptions );
#
my $infile = $ARGV[0];
my $basename = basename($infile);
my $tns    = $ENV{ORACLE_TNS};
my $dir    = $hOptions{OUT};
my $mesgenDir = $hOptions{OUTMESGEN};
#my $forkDir = $hOptions{FORK};
my $basefile = "${dir}/${basename}";
my $baseFileMesgen = "${mesgenDir}/${basename}";
#my $forkfile = "${forkDir}/${basename}";
my $events = {};
my @exts = qw(.cast .cmes .mes .lotGgen .lotG2gen);
my ($name, $dir, $ext) = fileparse($infile, @exts);

if ( !defined($hOptions{ARCHIVE}))
{
   die "required parameter --archive";
}

my $archDir = $hOptions{ARCHIVE};

if ( -d $archDir )
{
   copy($infile,$archDir) or die "Copy to archive ($archDir) failed: $!";
}
elsif ( $archDir ne "/dev/null" )
{
   die "Directory not found: $archDir";
}

open IN, $infile or die "cannot open $infile:$!";
my $separator = qr/\|/;
my $strp=DateTime::Format::Strptime->new(pattern => '%m-%d-%Y %T', time_zone=>'local',);
my $writeTime=undef;
my %gen_data;
my %lot_ids;
my %flot_ids;

#my $mydb = DBI->connect($tns, "/", "");
#print $mydb, $DBI::errstr;
#if($DBI::errstr) { DpLoad_exit(1,"Unable open DB connection: $tns: $!"); }

my $tot_rows=0;
my $rows_written=0;
my ($busUnit, $facility, $parent_lot, $child_lot, $date_code, $parent_prod, $child_prod, $owner, $parent_owner, $trans, $transaction_date_time,
		$source_lot, $from_source_lot, $source_prod, $source_inv_item_type, $path, $event_type, $source_fab, $from_fab, $fab, $gen_event_name) = "";
		
while (<IN>){
    chomp;
    next if $. == 1 ; #skip header
    my @row = split ( $separator, $_);
    #my $rowSize = @row;
    if ($ext =~ /cast/i) {
    	# INCOMING: BUSINESS_UNIT|FACILITY|PARENT_LOT|CHILD_LOT|DATE_CODE|PARENT_PROD|CHILD_PROD|OWNER|PARENT_OWNER|TRANS|TRANSACTION_DATE_TIME|SOURCE_LOT|SOURCE_PROD|SOURCE_INV_ITEM_TYPE|PATH
    	
		#13-Mar-18 SAB only discard reference data for wafer lots if parent prod or source lot is missing.  Still used for FG lots.
	    	#next if $row[5] eq " " || $row[11] eq " ";
	    	
			    $busUnit      = $row[0];
			    $facility     = $row[1];
			    $parent_lot   = $row[2];
			    $child_lot    = $row[3];
			    $date_code		= $row[4];
			    $parent_prod  = $row[5];
			    $child_prod   = $row[6];
			    $owner        = $row[7];
			    $parent_owner = $row[8];
			    $trans        = $row[9];
			    $transaction_date_time = $row[10];
			    $source_lot   = $row[11];
			    $source_prod  = $row[12];
			    $source_inv_item_type  = $row[13];
			    $path         = $row[14]; 
		  	
    } elsif($ext =~ /\.cmes|\.mes/i) {
    	
	    	# INCOMING: BUSINESS_UNIT|FACILITY|PARENT_LOT|CHILD_LOT|PARENT_PROD|CHILD_PROD|OWNER|TRANS|TRANSACTION_DATE_TIME|SOURCE_LOT|SOURCE_PROD|SOURCE_INV_ITEM_TYPE|PATH
		    $busUnit      = $row[0];
		    $facility     = $row[1];
		    $parent_lot   = $row[2];
		    $child_lot    = $row[3];
		    $parent_prod  = $row[4];
		    $child_prod   = $row[5];
		    $owner        = $row[6];
		    $trans        = $row[7];
		    $transaction_date_time = $row[8];
		    $source_lot   = $row[9];
		    $source_prod  = $row[10];
		    $source_inv_item_type  = $row[11];
		    $path         = $row[12];
	  	
    } elsif($ext =~ /\.lotG2gen/i) {
    		#INCOMING: EVENT_TYPE|EVENT_TIME|SRC_FAB|SRC_LOT|FROM_SRC_LOT|FROM_FAB|FROM_PROD|FROM_LOT|FAB|PROD|LOT|EVENT_NAME
    		#print "===@row===\n";
    		$event_type 						= $row[0];
    		$transaction_date_time 	= $row[1];
    		$source_fab        			= $row[2];
    		$source_lot   					= $row[3];
    		$source_lot 					=~ s/\.\S//g;
    		$from_source_lot   				= $row[4];
    		$from_source_lot 				=~ s/\.\S//g;
    		$from_fab					= $row[5];
    		$parent_prod  					= $row[6];
    		$parent_lot   					= $row[7];
    		$fab 						= $row[8];
    		$child_prod   					= $row[9];
    		$child_lot    					= $row[10];
    } elsif($ext =~ /\.lotGgen/i) {
    		#INCOMING: EVENT_TYPE|EVENT_TIME|SRC_FAB|SRC_LOT|FROM_FAB|FROM_PROD|FROM_LOT|FAB|PROD|LOT|EVENT_NAME
    		#print "===@row===\n";
    		$event_type 						= $row[0];
    		$transaction_date_time 	= $row[1];
    		$source_fab        			= $row[2];
    		$source_lot   					= $row[3];
    		$source_lot 						=~ s/\.\S//g;
    		$from_fab								= $row[4];
    		$parent_prod  					= $row[5];
    		$parent_lot   					= $row[6];
    		$fab 										= $row[7];
    		$child_prod   					= $row[8];
    		$child_lot    					= $row[9];
    		#$gen_event_name         = $row[10];
    		#$gen_event_name         =~ s/\.\S//g;
    }

    $tot_rows++;

    # If SRCLOT_LOOKUP option is set, look up the SOURCE_LOT from the file in PP_LOT (as lot).  If present, use that lot's
    # source lot as the source lot.
    if (defined($hOptions{SRCLOT_LOOKUP}))
    {
    		
        my $rdb_hash = getRefdb->getMetaData($source_lot);
				if (keys %$rdb_hash > 0)
				{
			      my $new_source_lot = $rdb_hash->{source_lot};
				    $new_source_lot =~ s/\s+//g;
				    if ( $source_lot ne $new_source_lot && length($new_source_lot) > 1 )
				    {
			          INFO("Substituting source lot ".$new_source_lot." for source lot ".$source_lot.", child lot=". $child_lot);
				        $source_lot = $new_source_lot;
				    }
			#	    else
			#	    {
			#	        INFO("Found Source Lot ".$new_source_lot.", orig source_lot ".$source_lot);
			#	    }
				}
    }
    
    my $genevtName = $child_lot . "_" . $parent_lot . "_" . $source_lot . ".S";
    my $foundMeta = 0;

    if ( defined($events->{$genevtName}) )
    {
        INFO("Event ".$genevtName." already found in this file, skipping");
        $foundMeta = 1;
    }

    $events->{$genevtName} = 1;

    # Ref Data output format
    # CHILD_LOT (LOT), FROM_LOT (PARENT_LOT), SOURCE_PROD (PRODUCT), OWNER (LOT_OWNER), SOURCE_LOT (SOURCE_LOT)
    # LOT|PARENT_LOT|PRODUCT|LOT_OWNER|SOURCE_LOT
    # No .S at the end of source lot, this is reference data not Exensio DB.
    # Always overwrite data in refdb even when present.
    if ( $owner ne "T" and $owner ne "TE" ) {
    	my $lotstr;
    	if ($ext =~ /cast/i) {
    		if ($hOptions{GENERATE_MESFLOT}) {
	    		my $flotstr;
			$flotstr = "$child_lot|$owner|$child_prod|$date_code";
			$flot_ids{$child_lot} = $flotstr;
    		}
									
	    	if ($parent_prod eq " " || $source_lot eq " ") {
		 	$lotstr = " ";
		}
		elsif ( defined($hOptions{USE_CHILD_PROD})) {
			$lotstr = "$parent_lot|$source_lot|$parent_prod|$parent_owner|$source_lot";
		}
		else {
			$lotstr = "$parent_lot|$source_lot|$parent_prod|$parent_owner|$source_lot";
		}
	    } 
	    elsif($ext =~ /cmes|mes/i) {
	    	if ( defined($hOptions{USE_CHILD_PROD})) {
        	$lotstr = "$child_lot|$parent_lot|$child_prod|$owner|$source_lot";
	}
	else {
          $lotstr = "$child_lot|$parent_lot|$source_prod|$owner|$source_lot";
	}
      }
	    if ( $lotstr ne " " ) {
	    	$lot_ids{$child_lot} = $lotstr;
	}
    }

    # Genealogy output format
    # MOUT|DATE|SRC_LOT|FROM_PROD|FROM_LOT|PROD|LOT|EVENT_NAME
    if ( $foundMeta == 0 && $parent_lot ne $child_lot)
    {
        $rows_written++;
        if ($ext =~ /\.lotG2gen/i) {
        	my $str="$event_type|$transaction_date_time|$source_fab|$source_lot.S|$from_source_lot.S|$from_fab|$parent_prod|$parent_lot|$fab|$child_prod|$child_lot|$genevtName";	
        	if (exists $gen_data{$child_lot}){   
		      	push @{$gen_data{$child_lot}}, $str;
		      }   
		      else {   
		      	$gen_data{$child_lot} = [ $str ];
		      }   
        } 
        elsif ($ext =~ /\.lotGgen/i) {
        	my $str="$event_type|$transaction_date_time|$source_fab|$source_lot.S|$from_fab|$parent_prod|$parent_lot|$fab|$child_prod|$child_lot|$genevtName";	
        	if (exists $gen_data{$child_lot}){   
		      	push @{$gen_data{$child_lot}}, $str;
		      }   
		      else {   
		      	$gen_data{$child_lot} = [ $str ];
		      }   
        } 
	elsif($ext =~ /cast/i) {
		      my $str="MOUT|$transaction_date_time|$source_lot.S|$parent_prod|$parent_lot|$child_prod|$child_lot|$genevtName";
		      if (exists $gen_data{$child_lot})
		      {   
		      	push @{$gen_data{$child_lot}}, $str;
		      }   
		      else {   
		      	$gen_data{$child_lot} = [ $str ];
		      }   
	}
        else {
		      my $str="MOUT|$transaction_date_time|$source_lot.S|$parent_prod|$parent_lot|$source_prod|$child_lot|$genevtName";
		      if (exists $gen_data{$child_lot})
		      {   
		      	push @{$gen_data{$child_lot}}, $str;
		      }   
		      else {   
		      	$gen_data{$child_lot} = [ $str ];
		      }   
      	}
    }   
}
INFO("Total = $tot_rows lines read from $infile, $rows_written genealogy rows retained");

close IN;
#$mydb->disconnect();

# 26-JUN-2019 SAB Don't write out REF file.
my $newfile_ok = "";
# 05-FEB-2021 JAG - write out REF file again.
#if ( 0 )
#{
my @lot_list = ();
my @flot_list = ();
if ($ext =~ /cast/i) {
	if ($hOptions{GENERATE_MESFLOT}) {
		# Write out .mesflot file.
		$newfile_ok = "${basefile}.mesflot";
		unlink ${newfile_ok} if -e ${newfile_ok};
		open OUT, ">$newfile_ok" or die "cannot open $newfile_ok:$!";
		@flot_list = values %flot_ids;
		print OUT "LOT|LOT_OWNER|PRODUCT|DATE_CODE\n";
		print OUT join("\n", @flot_list);
		print OUT "\n";
		close OUT;
	} 
	if ($hOptions{GENERATE_MESLOT}) {
		# Write out .meslot file.
		$newfile_ok = "${basefile}.meslot";
		unlink ${newfile_ok} if -e ${newfile_ok};
		open OUT, ">$newfile_ok" or die "cannot open $newfile_ok:$!";
		@lot_list = values %lot_ids;
		print OUT "LOT|PARENT_LOT|PRODUCT|LOT_OWNER|SOURCE_LOT\n";
		print OUT join("\n", @lot_list);
		print OUT "\n";
		close OUT;
	} 
} 
elsif($ext =~ /cmes|mes/i) {
	if ($hOptions{GENERATE_MESLOT}) {
		# Write out .meslot file.
		$newfile_ok = "${basefile}.meslot";
		unlink ${newfile_ok} if -e ${newfile_ok};
		open OUT, ">$newfile_ok" or die "cannot open $newfile_ok:$!";
		@lot_list = values %lot_ids;
		print OUT "LOT|PARENT_LOT|PRODUCT|LOT_OWNER|SOURCE_LOT\n";
		print OUT join("\n", @lot_list);
		print OUT "\n";
		close OUT; 
	} 
}
#}


# Write out .mesgen file.
if ($ext =~ /\.lotG2gen/i) {
	$newfile_ok = "${baseFileMesgen}.lotG2mesgen";
	unlink ${newfile_ok} if -e ${newfile_ok};
}
elsif ($ext =~ /\.lotGgen/i) {
	$newfile_ok = "${baseFileMesgen}.lotGmesgen";
	unlink ${newfile_ok} if -e ${newfile_ok};
} else {
	$newfile_ok = "${baseFileMesgen}.mesgen";
	unlink ${newfile_ok} if -e ${newfile_ok};
}

my @final;

foreach my $key ( keys %gen_data )
{
   my @rows = @{$gen_data{$key}};
   push( @final, @rows );
}

# Sort final results and write to file.
my @sorted_final = sort @final;
open OUT, ">$newfile_ok" or die "cannot open $newfile_ok:$!";
print OUT join("\n", @sorted_final);
print OUT "\n";
close OUT;

### try to gzip .lotGmesgena and .mesgen file ####
if($newfile_ok =~ /\.(.+)?mesgen/) {
  INFO("Compress $newfile_ok with gzip");
  qx(gzip "$newfile_ok");
}

##### jgarcia added for forking but not used because directly use the file being written in out folder for forking #######
#if($newfile_ok =~ /\.lotGmesgen|\.mesgen/) {
#
# my ($filename, $ext) = split(".`", $newfile_ok);
# &forkFile($newfile_ok,$forkDir, $filename, $ext, "PRODUCTION");
#}

if ( $rows_written > 0 )
{
   INFO("#### Success ####");
#   move($newfile_ok, ${dir}."/Processed");   
}
else
{
    INFO("#### ERROR: No rows written to output file  ####");
#    move($newfile_ok, ${dir}."/NotProcessed");   
}
INFO("################  End  #############");

dpExit(0);

