#!/usr/bin/env perl_db
my $ToolName = "res_file_reload.pl";
#
#------------------------- File Header -----------------------------------
#
# File Name: fcs_set_res_meta.pl
#
# Description: This script will update the following metadata in a dpexport RES file:
#    - Source Lot
#
# TODO: FOR Class 5, set program name depending on program group ("PCM for PSA" or "PCM")
#
# Sccs Id:    @(#)fcs_set_res_meta.pl	1.0 16/03/2015 17:00:47
#
# Related Files/Documents:
#
# Revision History
# ________________
# Date      Author           Description
#
# 2016-05-10  S. Boothby  Initial version.
#-------------------------------------------------------------------------
# Usage:
#
# ----------------- Start CVS Section (do not modify) -------------------
#
#      $Id: res_file_reload.pl 2233 2017-09-05 02:22:25Z dpower $
      my($sVersionId) = ( split(' ', '$Revision: 2233 $') )[1];
	  my($VersionAndDate) = "

1.0
";
# ------------------------- End CVS Section -----------------------------
#
##############################################################################

#-------------------------------------------------------------------------
# Variable declarations
use strict;
use Switch;
use Getopt::Long;
use File::Basename;
use File::Spec::Functions;
use POSIX qw(strftime);
use PDF::DpData;
use PDF::DAO;
use PDF::DpWriter;
use PDF::DpLoad;
use PDF::Log;
use PPLOG::PPLogger;


# define the string to be used in case of null field
my $nullreplace = "NA";

# a hash to receive options
my (%hOptions)= (
    	"OUTDIR" => undef,
    	"EXT" => undef,
    	"DEBUG"  => undef,
    	"HELP"  => undef,
	"LOGFILE"  => undef,
	"TRACE"  => undef,
	"PPLOG" => 0,
);


my $fileIx = undef;
my @file_list=();
my $class=undef;
my %familyhash=();
my %missingLot=();
my %missingCfg=();
my %missingProduct=();
my %lothashes=();
my %cfghashes=();
my %output=();
my $metaFound = "YES";
my $prefix=undef;
my $metahash=undef;

my $pplogger = new PPLOG::PPLogger();

##############################################################################
#                                 Main
##############################################################################
# command line arguments.

Initialize_argument();

# parse all the files in order
foreach(@file_list) {
  	my $file = $_;
  	INFO("--> Splitting the file $file, please wait...");
  
  	modify_dpexport_file($file,\%hOptions);
  
  	INFO(" --> Done with splitting the file $file");
}

INFO(" --> Done!");

dpExit(0);

##############################################################################
# Subroutine: Initialize_argument
##############################################################################
sub Initialize_argument{
	
	# turn the ignorecase option on so that the options will be case-insensitive
	$Getopt::Long::ignorecase = 1;
	$Getopt::Long::debug = 0; 

	# get all values of the options that the user has defined
	MyUsage() unless(GetOptions(\%hOptions,
				"OUTDIR=s",
				"EXT=s",
				"V",
				"VERSION",
				"LOGFILE=s",
				"DEBUG",
				"TRACE",
				"HELP",
				"PPLOG",
			)
		);
	if($hOptions{V} || $hOptions{VERSION} || $hOptions{help}) 
	{
	    	print("$VersionAndDate\n"); 
	    	dpExit(0);
	};

	if($hOptions{HELP}) {MyUsage();}
	
	if($#ARGV<0) {MyUsage();}
	
	# and also get all the names of the files that the user would like to split
	@file_list = @ARGV;

	# create the outdir if it does not exist
	if (!-e $hOptions{OUTDIR}) {
		printf STDERR "Making output directory: $hOptions{OUTDIR}\n";
		my $mkdir_ret = mkdir($hOptions{OUTDIR}, 0777);
		if ($mkdir_ret != 1) {
			 dpExit(1,"Fail to make output directory $hOptions{OUTDIR}");
		}
	}else{
		#MyUsage();
	}
	

	PDF::Log->init( \%hOptions,$pplogger);

	$pplogger->settobeLog(1) if ($hOptions{PPLOG});
	PDF::Log->setLevelDebug if ($hOptions{DEBUG});
	PDF::Log->setLevelTrace if ($hOptions{TRACE});
	
	# output the option values if the debug option is turned on
	DEBUG("Input file: @file_list");
	DEBUG("Output directory: $hOptions{OUTDIR}");
	#DEBUG("Class: $class");
	DEBUG("Datatype: $hOptions{EXT}");

	return 1;
}

##############################################################################
# Subroutine: MyUsage
##############################################################################
sub MyUsage{
	my($sUsageMsg) = <<"__END_OF_USAGE_MESSAGE__";      # Usage note
res_file_reload.pl <inputfiles> ...
       [ -outdir <directory> ]         Output directory
       [ -debug ]                      Debug mode (off by default)
       [ -VERSION | -help ]            Display version ID or help messages
       [ -logfile ]            		   Used to log 
__END_OF_USAGE_MESSAGE__
	
	die "$sUsageMsg";
}

##############################################################################
# Subroutine: modify_dpexport_file
##############################################################################
sub modify_dpexport_file {

  my ($file, $hOptions) = @_;
  my @work=();
  %output=();
  my %wcl_records;
  
  my $separator=undef; # Separator
  my $lot=undef;       # Lot
  my $sourceLot=undef; # SrcLotId
  my $product=undef;   # Product
  my $program=undef;   # Product
  my $process=undef;   # Process (process/package)
  my $package=undef;   # Process (process/package)
  my $family=undef;    # Family (device)
  my $fab=undef;       # Fab
  my $location=undef;  # Location	
  my $progclasskey=undef;
  my $cfg=undef;
  my $tester=undef;
  my $program_orig=undef;
  
  my $progClassKey=undef;
  my $new_lotOwner=undef; 
  my $new_lotClass=undef; 
  my $new_sourceLot=undef; # SrcLotId
  my $new_waferPfx=undef;
  my $old_waferID=undef;
  my $new_waferID=undef;
  my $new_product=undef;   # Product
  my $new_process=undef;   # Process (process/package)
  my $new_package=undef;   # Process (process/package)
  my $new_family=undef;    # Family (device)
  my $new_fab=undef;       # Fab
  my $new_cfg=undef;
  
  my $writeNL=1;
  my $inHDR=0; # BOH/EOH
  my $fname = basename($file);

  $pplogger->setRawFile($file);
  
  # First locate the program class and lot info then rewind and search again
  my $finished = 0;
  open(fhIn, "<$file") || dpExit(1,"Unable to open file $file");
  WH: while(<fhIn>)
  {
	chomp;
	s/\r//;
	my $line=$_;
	if ( /^ProgClassKey\,/ ) {
		@work = split("\\,");
		$progclasskey = $work[1];
	}
	if ( /^Program\,/ ) {
                @work = split("\\,");
		$program_orig = $work[1];
		my @item = split /\:\:/, $work[1];
		$prefix = $item[0];
		$program = $item[1];
		$tester = $item[$#item];
		#if ($progclasskey == 1 || $progclasskey ==  4 || ($prefix =~ /^WS\-/ && $progclasskey == 12)){
		#	$cfg = $item[2];
		#	my @item = split /\-NC/, $tester;
		#	$tester = $item[0];
		#	$new_cfg = GetConfigID($cfg);
		#}	
		#print "$prefix-$program-$cfg-$tester\n";
        }
	if ( /^Lot\,/ )
	{
		@work = split("\\,");
		$lot = $work[1];
		$metahash = GetMetaDataByLot($lot,$progclasskey);
	}
	if ( /^Process\,/ ) 
	{
		@work = split("\\,");
		$process = $work[1];
	}
	if ( /^Product\,/ ){
		@work = split("\\,");
		$product = $work[1];
	}
	if ( /^Package\|/ )
	{
		@work = split("\\,");
                $package = $work[1];	
	}
	if ( /^Family\,/ )
	{
		@work = split("\\,");
                $family = $work[1];
	}
	if ( /^Fab\,/ )
	{
		@work = split("\\,");
                $fab = $work[1];
	}
	if ( /^Equip6\,/ ) {
                @work = split("\\,");
                $location = $work[1];
        }	
	if ( /^SrcLotId\,/)
	{
		@work = split("\\,");
		my @tmp = split /\./, $work[1];
		$sourceLot = $tmp[0];
	}
  }
  $inHDR=0;
  close(fhIn);

  if ( %$metahash > 0 ) {
	$new_sourceLot = ($metahash->{source_lot} ne "") ? $metahash->{source_lot} : $sourceLot;
	$new_product   = ($metahash->{product} ne "") ? $metahash->{product} : $product;
	$new_process   = ($metahash->{process} ne "") ? $metahash->{process} : $process;
	$new_package   = ($metahash->{package} ne "") ? $metahash->{package} : $package;
	$new_family    = ($metahash->{family} ne "") ? $metahash->{family} : $family;
	$new_fab       = ($metahash->{fab_desc} ne "") ? $metahash->{fab_desc} : $fab;				
	INFO ("Updating wafer id using source lot = ".$new_sourceLot);
  }
  else { #retain old meta value extracted from res
  	WARN ("Retaining old wafer id..");
	$new_sourceLot = $sourceLot;
	$new_product   = $product;
	$new_process   = $process;
	$new_package   = $package;
	$new_family    = $family;
	$new_fab       = $fab;
  }

  $pplogger->setLot($lot);
  $pplogger->setSourceLot($new_sourceLot);
  $pplogger->setProgramClass($progclasskey);
  $pplogger->setProgramName($program_orig);


  open(fhIn, "<$file") || dpExit(1,"Unable to open file $file");
  while(<fhIn>){
	chomp;
	s/\r//;
	my $line=$_;

	#if ($line =~ /$program_orig/i && $cfg ne $new_cfg && ($progclasskey == 1 || $progclasskey == 4 || ($prefix =~ /^WS\-/ && $progclasskey == 12))){
        #       my @fields = split /\|/, $_;
        #       foreach my $field (@fields) {
        #               if ($field =~ /\:\:$cfg\:\:/i) {
        #                       $field =~ s/\:\:$cfg\:\:/\:\:$new_cfg\:\:/i;
        #               }
        #       }
        #       my $out_line = join("\|", @fields);
        #       $output{$fname} .= $out_line."\n";
        #}
	#elsif ($line =~ /^Process\|/) {
	#	$output{$fname} .= "Process|".$new_process."\n";
	#}
	#elsif ($line =~ /^Product\|/) {
	#	$output{$fname} .= "Product|".$new_product."\n";
        #}
	#elsif ($line =~ /^Package\|/) {
	#	$output{$fname} .= "Package|".$new_package."\n";
        #}
	#elsif ($line =~ /^Family\|/) {
	#	$output{$fname} .= "Family|".$new_family."\n";
        #}
	#elsif ($line =~ /^Fab\|/) {
	#	$output{$fname} .= "Fab|".$new_fab."\n";
        #}
	if ($line =~ /$sourceLot/i || $line =~ /$lot\_\d{1,2}/i) { #replace old source lot found in each line
		my @fields = split /\,/, $_;
		foreach my $field (@fields) {
			if ($field =~ /$sourceLot/i || $field =~ /$lot\_\d{1,2}/i) {
				if ($field =~ /\_/i) {
					my @item = split /\_/, $field;
					$field = $new_sourceLot."_".$item[1];
					$pplogger->setWaferFlag(1);
					$pplogger->setWafNum($item[1]);
				}		
				elsif ($field =~ /\./ && $field !~ /$lot\_\d{1,2}/i) {
					my @item = split /\./, $field;
					$field = $new_sourceLot.".".$item[1];				
				}
				else {
					$field =~ s/$sourceLot/$new_sourceLot/i;
				}
			}	
		}
		my $out_line = join("\,", @fields);
		$output{$fname} .= $out_line."\n";
	}
	else {
		$output{$fname} .= $_."\n";
	}
   } # while(<fhIn>)
   close(fhIn);

   OutputFiles($hOptions{EXT});
}

sub OutputFiles{
	my $ext=shift();
	my $holder=undef;
	foreach $holder (sort keys %output)
	{
		my $fn = $holder;
		   $fn =~ s/ //g;
		   $fn =~ s/\///g; 
		my $ext = $prefix."_res";
		my $wr=PDF::DpWriter->new(
		{
			outdir => $hOptions{OUTDIR},
			basename => ($fn),
			ext => $ext,
		}
		);

		#$wr->forSBox(1) if $metaFound eq "NO";
		$wr->open;
		$wr->put($output{$holder}); 
		$wr->close;
	}
}

sub GetMetaDataByLot {
	my $lot = shift;
	my $progclasskey = shift;
	my $hash=undef; 

	if ($progclasskey == 2){
                $hash = getRefdb->getMetaDataFinalLot($lot);
        }
        else {
                $hash = getRefdb->getMetaData($lot);
        }

        if (keys %$hash > 0) {
                INFO ("Good. Meta Found for Lot = ".$lot);
        }
        else {
                WARN("Bad.. Meta Not Found for Lot = ".$lot);
                #$metaFound = "NO";
        }	

	return $hash;
}
