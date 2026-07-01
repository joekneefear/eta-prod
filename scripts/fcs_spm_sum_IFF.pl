#!/usr/bin/env perl_db
my $ToolName = "fcs_spm_sum.pl";
#
#------------------------- File Header -----------------------------------
#
# File Name: fcs_spm_sum.pl
#
# Description: 
#
# Sccs Id:    @(#)fcs_spm_sum.pl	1.0 16/03/2015 17:00:47
#
# Related Files/Documents:
#
# Revision History
# ________________
# Date      Author           Description
#
# 08-06-2015  Jacky       Initial Version
# 26-06-2015  Grace       Added pass bin to SBIN
# 29-07-2015  Eric	  Corrected ppid naming rule
# 29-07-2015  Eric	  sandbox if ppid > 35
# 30-07-2015  Eric	  added location option
# 31-07-2015  Eric	  removed product in ppid
# 27-08-2015  Gilbert     set PROGRAM_CLASS to 12
# 01-08-2016  Scott       Don't set fab
# 20-05-2016  Eric	  added options for reliability data loading
# 07-07-2016  Eric	  corrected how rel lot were parsed, 
# 			  emptied dtype contains [0-9], emptied strdur & temp if contains [a-z]
# 21-11-2016  Eric	  remove rej | retest in lotid
# 11-01-2018  Eric	  parse ONRMS datalog
# 31-10-2018  Eric	  added subroutines check2DScan and read2DFile
# 07-Mar-2019 jgarcia -  addes support for new tester that place lotid to different field name (Lot Id).
# 2020/09/03 karen       added support to fork and qde output (IFF)/files to designated location 
#2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

#-------------------------------------------------------------------------
# Usage:
#
# ----------------- Start CVS Section (do not modify) -------------------
#
#      $Id: fcs_spm_sum_IFF.pl 2617 2020-10-08 05:13:58Z dpower $
       my($sVersionId) = ( split(' ', '$Revision: 2617 $') )[1];
       my($VersionAndDate) = "1.0 - Mar 16, 2015";
# ------------------------- End CVS Section -----------------------------
#
##############################################################################

#-------------------------------------------------------------------------
# Variable declarations
use strict;
use FindBin::libs;
use Getopt::Long;
use File::Basename;
use File::Spec::Functions;
use POSIX qw(strftime);
use PDF::DpData;
use PDF::DAO;
use PDF::Log;
use PDF::DpWriter;
use PDF::DpLoad;
use Number::Range;
use Config::Tiny;
use PPLOG::PPLogger;

#Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# a hash to receive options
my (%hOptions)= (
    "OUTDIR" => undef,
    "FORK" => undef,
    "EXT" => undef,
    "FACILITYFILE" => undef,
    "FINALLOT" => 0,
    "RELLOT" => 0,
    "DEBUG"  => undef,
    "SEPARATOR" => undef,
    "HELP"  => undef,
    "LOGFILE"  => undef,
    "TRACE"  => undef,
    "LOC" => undef,
    "QDE" => undef,
    "PPLOG" => undef
);

my @file_list=();
my $facility;
my $location;

##############################################################################
#                                 Main
##############################################################################
# command line arguments.

Initialize_argument();
# parse all the files in order
foreach(@file_list) {
  	my $file = $_;
	my $scan_flg = check2Dscan($file);
  	INFO("--> Splitting the file $file, please wait...");
	if ($scan_flg eq "Y") {
		INFO ("2D Scan file detected");
		read2DFile($file,\%hOptions);	
	}
  	else {
		Split_on_single_file($file,\%hOptions);

	}
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
								"FORK=s",
								"EXT=s",
								"FACILITYFILE=s",
								"FINALLOT",
								"RELLOT",
								"LOC=s",
								"V",
								"VERSION",
								"LOGFILE=s",
								"DEBUG",
								"TRACE",
								"HELP",
								"QDE",
								"PPLOG"
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

	#Pass PPLogger object to PDF::Log
        PDF::Log->init( \%hOptions,$pplogger);
	if ($hOptions{PPLOG}){
		$pplogger->settobeLog(1);  #Set flag for pp logging
	}

	#log script name
	$pplogger->setScript(basename($0));

	#log raw filename
	$pplogger->setRawFile(@file_list);
	
	# create the outdir if it does not exist
	if (!-e $hOptions{OUTDIR}) {
		printf STDERR "Making output directory: $hOptions{OUTDIR}\n";
		my $mkdir_ret = mkdir($hOptions{OUTDIR}, 0777);
		if ($mkdir_ret != 1) {
			 dpExit(1,"Fail to make output directory $hOptions{OUTDIR}");
		}
	}else{
	#	MyUsage();
	}

	if ($hOptions{LOGFILE}){
		PDF::Log->init($hOptions{LOGFILE});
	} else {
		PDF::Log->init;
	}
	PDF::Log->setLevelDebug if ($hOptions{DEBUG});
	PDF::Log->setLevelTrace if ($hOptions{TRACE});
	
	my $config = Config::Tiny->read($hOptions{FACILITYFILE});
	$location = $hOptions{LOC};
	$facility = "";

	#log site
	$pplogger->setSITE($location);
	
	# output the option values if the debug option is turned on
	DEBUG("Input file: @file_list");
	DEBUG("Output directory: $hOptions{OUTDIR}");
	DEBUG("Datatype: $hOptions{EXT}");
	DEBUG("Location: $hOptions{LOC}");
	if($hOptions{FINALLOT}) {
		$facility = $config->{$location}->{finalTest};
	} else {
		$facility = $config->{$location}->{probe};
	}
	
	return 1;
}

##############################################################################
# Subroutine: MyUsage
##############################################################################
sub MyUsage{
	my($sUsageMsg) = <<"__END_OF_USAGE_MESSAGE__";      # Usage note
	fcs_spm_sum.pl <inputfiles> ...
       	[ -outdir <directory> ]         Output directory
	[ -ext <ext> ]		   	Specify the extension of output files
       	[ -debug ]                      Debug mode (off by default)
       	[ -VERSION | -help ]            Display version ID or help messages
   	[ -logfile ]           	  	Used to log 
__END_OF_USAGE_MESSAGE__
	
	die "$sUsageMsg";
}

##############################################################################
# Subroutine: Split_on_single_file
##############################################################################
sub Split_on_single_file {

  	my ($file, $hOptions) = @_;
  	my $entity_type     = "";
  	my $entity_no       = "";
  	my $lotno           = "";
  	my $tp              = "";
  	my $tp_rev          = "";
  	my $test_count      = 0;
  	my $good_count	  = 0;
  	my %output=();
  	my $line = undef;
  	my $outputdata = undef;
  	my @dummy = ();
  	my $hbin_flag = 0;
  	my $sbin_flag = 0;
  	my $retest_flag = "N";
  	my $nothing=undef;
  	my %hbin            = ();
  	my %sbin            = ();
	my %rel	= ();
  	my $header = PDF::DpData::HeaderLong->new();
  	my $fn = basename($file);
  	$fn =~ /^(.*)\.(\S+)$/;
  	$fn = $1;
  	INFO("basename = ".$fn);
  	# open the file
  	open(fhIn, "<$file") || dpExit(1,"Unable to open file $file");
  
  	while($line=<fhIn>){
		$line =~ s/\cM\n/\n/g;
		chomp($line);
		
        	# TESTERNO
		my $sbin_pass = 0;
        	if ($line =~ /System/i)
        	{
	    		### specific for suzhou spm tester tester model name starts with SPM###
            		if($line =~ /SPM/i) {
                		my ($dummy, $entity) = split /\:/, $line;
                		($entity_type, $entity_no) = split /\-\s/, $entity;
                		$entity_type = uc($entity_type);
                		$entity_no = uc($entity_no);
                		$entity_type =~ s/ //g;
                		$entity_no =~ s/ //g;
                		### specific for suzhou spm tester tester model name starts with AZ###

            		} 
			elsif($line =~ /AZ/i) {
                		my ($dummy, $testModel)      = split /\:/, $line;
                		($entity_type, $entity_no) = split /\s+\[/, $testModel;
                		$entity_type = uc($entity_type);
                		$entity_no = uc($entity_no);
                		$entity_type      =~ s/ //g;
                		$entity_no      =~ s/ //g;
				$entity_no    =~ s/^\[//g;
                		$entity_no    =~ s/\]$//g;

            		} 
			else {
				### original tester info parsing to assign tester name and node name ####
                        	my @dummy       = split /\:|\-/, $line;
				$entity_type    = uc($dummy[1]);
				$dummy[$#dummy] =~ /([0-9]{1,3})$/;
                        	$entity_no      = $1;
				$entity_type =~ s/ //g;
				$entity_no   =~ s/ //g;
			}
			$header->EQUIP1_ID($entity_type." ".$entity_no);
        	}
		# TESTPLAN
		elsif ($line =~ /Job Name/i)
		{
			my @dummy = split /\:/, $line;	
			$tp       = uc($dummy[1]);
			$tp       =~ s/[^0-9A-Z\-\_]//g;
			$tp       =~ /R([0-9]+)$/;
			$tp_rev   = int($1);
			$tp_rev   = 1 if $tp_rev == 0;
			$header->PROGRAM($tp);
            		$header->REVISION($tp_rev);
		}
		# LOTNO
		elsif ($line =~ /Lot Id|Lot_Id/i)
		{
			my @dummy = split /\:/, $line;	
			$dummy[1] = uc($dummy[1]);
			$dummy[1] =~ s/ //g;
			($lotno,$nothing) = split /\./, $dummy[1];
			$lotno       =~ s/[^a-zA-Z0-9]//g;
			$lotno       =~ s/AO/A0/ig;
			if ($lotno =~ /REJ|RETEST/i) {
				$header->INDEX2("O");
				$lotno = substr($lotno, 0, 10);
			}
			$lotno       = substr($lotno,0,10) if length($lotno) > 10 && $lotno =~ /^A/i;
			$header->LOT($lotno);
			$header->SOURCE_LOT($lotno);
		}
		elsif ($line =~ /Lot No|Lot_No/i)
		{
			if($lotno eq "") {
				my @dummy = split /\:/, $line;	
				$dummy[1] = uc($dummy[1]);
				$dummy[1] =~ s/ //g;
				($lotno,$nothing) = split /\./, $dummy[1];
				$lotno       =~ s/[^a-zA-Z0-9]//g;
				$lotno       =~ s/AO/A0/ig;
				if ($lotno =~ /REJ|RETEST/i) {
					$header->INDEX2("O");
					$lotno = substr($lotno, 0, 10);
				}
				$lotno       = substr($lotno,0,10) if length($lotno) > 10 && $lotno =~ /^A/i;
				$header->LOT($lotno);
				$header->SOURCE_LOT($lotno);
			}
			
		}
		# TOTAL TEST COUNT
		elsif ($line =~ /Total Test Count/i)
		{
			@dummy      = split /\:/, $line;	
			$test_count = $dummy[1];
			$test_count =~ s/ //g;
			$header->DEVICE_COUNT($test_count);
		}
		# TOTAL GOOD COUNT
		elsif ($line =~ /Total Good Count/i)
		{
			@dummy      = split /\:/, $line;	
			$good_count = $dummy[1];
			$good_count =~ s/ //g;			
		}
		# TEST START TIME 
		elsif ($line =~ /Test Start/i && $line !~ /0000/)
		{
			my @dummy = split /\s{2,}/, $line;	
			$dummy[2] =~ s/ //g;				#<-- DATE
			$dummy[3] =~ s/ //g;				#<-- TIME
			$header->START_TIME($dummy[2]." ".$dummy[3]);			
		}
		# TEST END TIME 
		elsif ($line =~ /Test End/i && $line !~ /0000/)
		{
			my @dummy = split /\s{2,}/, $line;	
			$dummy[2] =~ s/ //g;				#<-- DATE
			$dummy[3] =~ s/ //g;				#<-- TIME
			$header->END_TIME($dummy[2]." ".$dummy[3]);		
		}	
		# ENABLE PARSE HBIN FLAG
		elsif ($line =~ /TEST  BIN  REPORT/)
		{
			$hbin_flag = 1;	
		}
		# ENABLE PARSE SBIN FLAG
		elsif ($line =~ /TEST ITEM/i)
		{
			$sbin_flag = 1;
			$hbin_flag = 0;
		}	
		# HBIN SUMM INFO
		elsif ($hbin_flag == 1)
		{
			my @readings = split /\s+/,$line;
			shift(@readings);			#<-- REMOVE 1ST ELEM W/C IS BLANK
		
			# STORES READING INTO A HASH
			if ($readings[0] =~ /\d/)			
			{
				if(!defined($hbin{$readings[0]}) && $readings[1]){
					$hbin{$readings[0]} = $readings[1];
				}
				if($readings[3] =~ /\d/ && !defined($hbin{$readings[3]}) && $readings[4]){
					$hbin{$readings[3]} = $readings[4];	#<-- NO 2ND COL OF BIN INFO ON THE LAST PART.
				}							
			}
		}		
        	# SBIN SUMM INFO
        	elsif ($sbin_flag == 1)
        	{
            		my @readings = split /\s+/,$line;
            		shift(@readings);                       #<-- REMOVE 1ST ELEM W/C IS BLANK

            		# STORES READING INTO A HASH
            		if ($readings[0] =~ /\d/)
            		{
				$readings[1] =~ s/ /\_/g;
				if($good_count eq $readings[2])
				{
					$sbin_pass = 1;
					$sbin{$readings[0]} = {NAME => uc($readings[1]),COUNT => $readings[2], PF => 'P'};
				}
				else{
					$sbin{$readings[0]} = {NAME => uc($readings[1]),COUNT => $readings[2], PF => 'F'};
				}
            		}
		}	
		
		unless($sbin_pass)
		{
			$sbin{0} = {NAME => "PASS",COUNT => $good_count, PF => 'P'};
		}

	}
	close(fhIn);	

    	# TRAP EMPTY LOTID & TESTPLAN NAME
    	if ($lotno eq "")
    	{
        	dpExit(1, "no_lotid in file");
    	}
	my $wr;	
	if($hOptions{QDE} ne "") {
		  $wr = PDF::DpWriter->new(
		{  	
			outdir => $hOptions{OUTDIR},
			forkdir => $hOptions{FORK},
			qde => $hOptions{QDE},
			basename => ($fn),
			ext => $hOptions{EXT},
			gzipIFF => 'Y',
			pplogger => $pplogger
		} 
		);
	} else {
		 $wr = PDF::DpWriter->new(
		{  	
			outdir => $hOptions{OUTDIR},
			forkdir => $hOptions{FORK},
			#qde => $hOptions{QDE},
			basename => ($fn),
			ext => $hOptions{EXT},
			gzipIFF => 'Y',
			pplogger => $pplogger
		} 
		);

	}

	$header->isFinalLot($hOptions{FINALLOT});
	$header->isRelLot($hOptions{RELLOT});
	$header->EQUIP6_ID($facility);
	$header->PROGRAM_CLASS(12);

 	# Capture Rel Attributes
	if ($hOptions{RELLOT}){
		
        	my $base_fn = basename($file);
        	   $base_fn =~ s/\.SUM.*+//ig;
        	my @item = split /\_/, $base_fn;
		my $qpnum;
		my $devchar;
		my $lotchar;
        	my $strname = $item[2];
        	my $strdur  = $item[3];
        	my $temp    = $item[4];
        	my $dtype   = $item[5];
		   $dtype   = "" if $dtype =~ /[0-9]/;

		if ($item[1] =~ /^20/) {
			$qpnum = substr $item[1], 0, 8;
			$devchar = substr $item[1], 8, 1;
			$lotchar = substr $item[1], 9, 1;
			$header->LOT($qpnum.$devchar.$lotchar);
		}
		elsif ($item[1] =~ /^U/i) {
			$qpnum = substr $item[1], 0, 6;	
			$lotchar = substr $item[1], 6, 1;
			$header->LOT($qpnum.$lotchar);
		}

        	my $range = Number::Range->new("0..1000000");
        	if ( $range->inrange($strdur) && $strdur !~ /\D/) {
                	#do nothing
        	}
        	else {
                	WARN ("Stress Duration not in range =  $strdur");
			$strdur = "" if $strdur =~ /[a-z]/i;
                	$wr->forSBox(1);
        	}
        	my $range = Number::Range->new("-1000000..1000000");
        	if ( $range->inrange($temp) && $temp !~ /\D/) {
                	#do nothing
        	}
        	else {
                	WARN ("ATETemp not in range = $temp");
			$temp = "" if $temp =~ /[a-z]/i;
                	$wr->forSBox(1);
        	}

		$header->INDEX1($strname."_".$strdur."_".$temp."_".$dtype);

		$rel{qpnumber} = $qpnum;
		$rel{devchar} = $devchar;
		$rel{lotchar} = $lotchar;
		$rel{strname} = $strname;
		$rel{strduration} = $strdur;
		$rel{atetemp} = $temp;
		$rel{datalogtype} = $dtype;
	}		

	$wr->noMeta(1) unless ($header->populateMeta);

	my $program = $header->PROGRAM;
	if ( length($program) > 35) {
		INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
		$wr->forSBox(1);
		$program = substr($program, 1, 35); # Leave enough room for session type
	}
	$header->PROGRAM($program."::SPM");
	
	$outputdata = "<HEADER>\n";
	$outputdata .= $header->toString;
	$outputdata .= "</HEADER>\n";
	$outputdata .= "<WAFER>\n";
	$outputdata .= "WAFER_ID=". $header->LOT."_00\n";
	$outputdata .= "WAFER_NUMBER=00\n";
	$outputdata .= "</WAFER>\n";
	$outputdata .= "<HBIN>\n";
	my $binname=undef;
	foreach my $bn (sort keys %hbin){
	        $binname = sprintf("HWBIN_%02d",$bn);
		if($bn == 1){
			$outputdata .= $bn.",".repNA($binname).",P,".$hbin{$bn}."\n";
		}else{
			$outputdata .= $bn.",".repNA($binname).",F,".$hbin{$bn}."\n";
		}
		
	}
	$outputdata .= "</HBIN>\n";
	$outputdata .= "<SBIN>\n";
	foreach my $bn (sort keys %sbin){
		$outputdata .= $bn.",".repNA($sbin{$bn}{NAME}).",".repNA($sbin{$bn}{PF}).",".repNA($sbin{$bn}{COUNT})."\n";
	}
	$outputdata .= "</SBIN>\n";
	
	if ($hOptions{RELLOT}) {
		$outputdata .= "<REL>\n";	
			$outputdata .= repNA($rel{qpnumber}).",".repNA($rel{devchar}).",".repNA($rel{lotchar}).","
			.repNA($rel{strname}).",".repNA($rel{strduration}).",".repNA($rel{atetemp}).",".repNA($rel{datalogtype})."\n";
		$outputdata .= "</REL>\n";
	}

	$outputdata .= "<PAR_DATA>\n";
	$outputdata .= "</PAR_DATA>\n";
	
	$wr->open;
	$wr->put($outputdata);
	$wr->close;
}

sub read2DFile {

  	my ($file, $hOptions) = @_;
  	my $entity_type     = "";
  	my $entity_no       = "";
  	my $lotno           = "";
  	my $tp              = "";
  	my $tp_rev          = "";
  	my $test_count      = 0;
  	my $good_count	  = 0;
  	my %output=();
  	my $line = undef;
  	my $outputdata = undef;
  	my @dummy = ();
  	my $hbin_flag = 0;
  	my $sbin_flag = 0;
	my $site1_flg = 0;
	my $site2_flg = 0;
	my $item_flg = 0;
  	my $retest_flag = "N";
  	my $nothing=undef;
  	my %hbin            = ();
  	my %sbin            = ();
	my %rel	= ();
  	my $header = PDF::DpData::HeaderLong->new();
  	my $fn = basename($file);
  	$fn =~ /^(.*)\.(\S+)$/;
  	$fn = $1;
  	INFO("basename = ".$fn);
  	# open the file
  	open(fhIn, "<$file") || dpExit(1,"Unable to open file $file");
  
  	while($line=<fhIn>){
		$line =~ s/\cM\n/\n/g;
		chomp($line);
		
        	# TESTERNO
		my $sbin_pass = 0;
        	if ($line =~ /System/i)
        	{
	    		### specific for suzhou spm tester tester model name starts with SPM###
            		if($line =~ /SPM/i) {
                		my ($dummy, $entity) = split /\:/, $line;
                		($entity_type, $entity_no) = split /\-\s/, $entity;
                		$entity_type = uc($entity_type);
                		$entity_no = uc($entity_no);
                		$entity_type =~ s/ //g;
                		$entity_no =~ s/ //g;
                		### specific for suzhou spm tester tester model name starts with AZ###

            		} 
			elsif($line =~ /AZ/i) {
                		my ($dummy, $testModel) = split /\:/, $line;
                		($entity_type, $entity_no) = split /\s+\[/, $testModel;
                		$entity_type = uc($entity_type);
                		$entity_no = uc($entity_no);
                		$entity_type =~ s/ //g;
                		$entity_no =~ s/ //g;
				$entity_no =~ s/^\[//g;
                		$entity_no =~ s/\]$//g;

            		} 
			else {
				### original tester info parsing to assign tester name and node name ####
                        	my @dummy = split /\:|\-/, $line;
				$entity_type = uc($dummy[1]);
				$dummy[$#dummy] =~ /([0-9]{1,3})$/;
                        	$entity_no = $1;
				$entity_type =~ s/ //g;
				$entity_no =~ s/ //g;
			}
			$header->EQUIP1_ID($entity_type." ".$entity_no);
        	}
		# TESTPLAN
		elsif ($line =~ /Job Name/i)
		{
			my @dummy = split /\:/, $line;	
			$tp = uc($dummy[1]);
			$header->PROGRAM($tp);
		}
		# TP REVISION
		elsif ($line =~ /Job Rev/i)
		{
			my @dummy = split /\:/, $line;
			$tp_rev = uc($dummy[1]);
			$header->REVISION($tp_rev);
		}
		# LOTNO
		elsif ($line =~ /Lot Id|Lot_Id/i)
		{
			my @dummy = split /\:/, $line;	
			$dummy[1] = uc($dummy[1]);
			$dummy[1] =~ s/ //g;
			($lotno,$nothing) = split /\./, $dummy[1];
			$lotno =~ s/[^a-zA-Z0-9]//g;
			$lotno =~ s/AO/A0/ig;
			if ($lotno =~ /REJ|RETEST/i) {
				$header->INDEX2("O");
				$lotno = substr($lotno, 0, 10);
			}
			$lotno       = substr($lotno,0,10) if length($lotno) > 10 && $lotno =~ /^A/i;
			$header->LOT($lotno);
			$header->SOURCE_LOT($lotno);
		}
		elsif ($line =~ /Lot No|Lot_No/i)
		{
			if($lotno eq "") {
				my @dummy = split /\:/, $line;	
				$dummy[1] = uc($dummy[1]);
				$dummy[1] =~ s/ //g;
				($lotno,$nothing) = split /\./, $dummy[1];
				$lotno =~ s/[^a-zA-Z0-9]//g;
				$lotno =~ s/AO/A0/ig;
				if ($lotno =~ /REJ|RETEST/i) {
					$header->INDEX2("O");
					$lotno = substr($lotno, 0, 10);
				}
				$lotno       = substr($lotno,0,10) if length($lotno) > 10 && $lotno =~ /^A/i;
				$header->LOT($lotno);
				$header->SOURCE_LOT($lotno);
			}
			
		}
		# TOTAL TEST COUNT
		elsif ($line =~ /Total Test Count/i)
		{
			@dummy      = split /\:/, $line;	
			$test_count = $dummy[1];
			$test_count =~ s/ //g;
			$header->DEVICE_COUNT($test_count);
		}
		# TOTAL GOOD COUNT
		elsif ($line =~ /Total Good Count/i)
		{
			@dummy      = split /\:/, $line;	
			$good_count = $dummy[1];
			$good_count =~ s/ //g;			
		}
		# TEST START TIME 
		elsif ($line =~ /Test Start/i && $line !~ /0000/)
		{
			my @dummy = split /\s{2,}/, $line;	
			$dummy[2] =~ s/ //g;				#<-- DATE
			$dummy[3] =~ s/ //g;				#<-- TIME
			$header->START_TIME($dummy[2]." ".$dummy[3]);			
		}
		# TEST END TIME 
		elsif ($line =~ /Test End/i && $line !~ /0000/)
		{
			my @dummy = split /\s{2,}/, $line;	
			$dummy[2] =~ s/ //g;				#<-- DATE
			$dummy[3] =~ s/ //g;				#<-- TIME
			$header->END_TIME($dummy[2]." ".$dummy[3]);		
		}	
		# ENABLE PARSE HBIN FLAG
		elsif ($line =~ /TEST S\/W BIN REPORT/i && $site1_flg == 0 && $site2_flg == 0 && $item_flg == 0)
		{
			$sbin_flag = 1;	
		}
		# ENABLE PARSE SBIN FLAG
		elsif ($line =~ /TEST H\/W BIN REPORT/i && $site1_flg == 0 && $site2_flg == 0 && $item_flg == 0)
		{
			$sbin_flag = 0;
			$hbin_flag = 1;
		}	
		elsif ($line =~ /TEST ITEM\(S\) REPORT/i)
		{
			$item_flg = 1;
			$site1_flg = 0;
                        $site2_flg = 0;
                        $sbin_flag = 0;
                        $hbin_flag = 0;
		}
		elsif ($line =~ /TEST_SITE/i)
                {
                        $site1_flg = 1;
                        $site2_flg = 1;
                        $sbin_flag = 0;
                        $hbin_flag = 0;
                }
		# SBIN SUMM INFO
		elsif ($sbin_flag == 1)
		{
			my @readings = split /\s+/,$line;
			shift(@readings);			#<-- REMOVE 1ST ELEM W/C IS BLANK
		
			# STORES READING INTO A HASH
			if ($readings[0] =~ /\d/)			
			{
				if(!defined($sbin{$readings[0]}) && $readings[1]){
					$sbin{$readings[0]} = $readings[1];
				}
					
				if($readings[3] =~ /\d/ && !defined($sbin{$readings[3]}) && $readings[4]){
					$sbin{$readings[3]} = $readings[4];	#<-- NO 2ND COL OF BIN INFO ON THE LAST PART.
				}							

			}
		}		
        	# HBIN SUMM INFO
        	elsif ($hbin_flag == 1)
        	{
            		my @readings = split /\s+/,$line;
            		shift(@readings);                       #<-- REMOVE 1ST ELEM W/C IS BLANK

            		# STORES READING INTO A HASH
            		if ($readings[0] =~ /\d/)
            		{
				if(!defined($hbin{$readings[0]}) && $readings[1]){
                                        $hbin{$readings[0]} = $readings[1];
                                }
                                if($readings[3] =~ /\d/ && !defined($hbin{$readings[3]}) && $readings[4]){
                                        $hbin{$readings[3]} = $readings[4];     #<-- NO 2ND COL OF BIN INFO ON THE LAST PART.
                                }	
            		}
		}	
		

	}
	close(fhIn);	

    	# TRAP EMPTY LOTID & TESTPLAN NAME
    	if ($lotno eq "")
    	{
        	dpExit(1, "no_lotid in file");
    	}
	my $wr;
	if($hOptions{QDE} ne "") {
	 	 $wr = PDF::DpWriter->new(
		{
			outdir => $hOptions{OUTDIR},
			forkdir => $hOptions{FORK},
			qde => $hOptions{QDE},
			basename => ($fn),
			ext => $hOptions{EXT}
		}
		);
	} else {
		 $wr = PDF::DpWriter->new(
		{
			outdir => $hOptions{OUTDIR},
			forkdir => $hOptions{FORK},
			basename => ($fn),
			ext => $hOptions{EXT}
		}
		);
	}
	

	$header->isFinalLot($hOptions{FINALLOT});
	$header->isRelLot($hOptions{RELLOT});
	$header->EQUIP6_ID($facility);
	$header->PROGRAM_CLASS(12);

 	# Capture Rel Attributes
	if ($hOptions{RELLOT}){
		
        	my $base_fn = basename($file);
        	   $base_fn =~ s/\.SUM.*+//ig;
        	my @item = split /\_/, $base_fn;
		my $qpnum;
		my $devchar;
		my $lotchar;
        	my $strname = $item[2];
        	my $strdur  = $item[3];
        	my $temp    = $item[4];
        	my $dtype   = $item[5];
		   $dtype   = "" if $dtype =~ /[0-9]/;

		if ($item[1] =~ /^20/) {
			$qpnum = substr $item[1], 0, 8;
			$devchar = substr $item[1], 8, 1;
			$lotchar = substr $item[1], 9, 1;
			$header->LOT($qpnum.$devchar.$lotchar);
		}
		elsif ($item[1] =~ /^U/i) {
			$qpnum = substr $item[1], 0, 6;	
			$lotchar = substr $item[1], 6, 1;
			$header->LOT($qpnum.$lotchar);
		}

        	my $range = Number::Range->new("0..1000000");
        	if ( $range->inrange($strdur) && $strdur !~ /\D/) {
                	#do nothing
        	}
        	else {
                	WARN ("Stress Duration not in range =  $strdur");
			$strdur = "" if $strdur =~ /[a-z]/i;
                	$wr->forSBox(1);
        	}
        	my $range = Number::Range->new("-1000000..1000000");
        	if ( $range->inrange($temp) && $temp !~ /\D/) {
                	#do nothing
        	}
        	else {
                	WARN ("ATETemp not in range = $temp");
			$temp = "" if $temp =~ /[a-z]/i;
                	$wr->forSBox(1);
        	}

		$header->INDEX1($strname."_".$strdur."_".$temp."_".$dtype);

		$rel{qpnumber} = $qpnum;
		$rel{devchar} = $devchar;
		$rel{lotchar} = $lotchar;
		$rel{strname} = $strname;
		$rel{strduration} = $strdur;
		$rel{atetemp} = $temp;
		$rel{datalogtype} = $dtype;
	}		

	$wr->noMeta(1) unless ($header->populateMeta);

	my $program = $header->PROGRAM;
	if ( length($program) > 35) {
		INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
		$wr->forSBox(1);
		$program = substr($program, 1, 35); # Leave enough room for session type
	}
	$header->PROGRAM($program."::SPM");
	
	$outputdata = "<HEADER>\n";
	$outputdata .= $header->toString;
	$outputdata .= "</HEADER>\n";
	$outputdata .= "<WAFER>\n";
	$outputdata .= "WAFER_ID=". $header->LOT."_00\n";
	$outputdata .= "WAFER_NUMBER=00\n";
	$outputdata .= "</WAFER>\n";
	
	$outputdata .= "<HBIN>\n";
	my $binname=undef;
	foreach my $bn (sort keys %hbin){
	        $binname = sprintf("HWBIN_%02d",$bn);
		if($bn == 1){
			$outputdata .= $bn.",".repNA($binname).",P,".$hbin{$bn}."\n";
		}else{
			$outputdata .= $bn.",".repNA($binname).",F,".$hbin{$bn}."\n";
		}
		
	}
	$outputdata .= "</HBIN>\n";
	
	$outputdata .= "<SBIN>\n";
	my $sbinname=undef;
        foreach my $bn (sort keys %sbin){
                $sbinname = sprintf("SWBIN_%02d",$bn);
                if($bn == 1){
                        $outputdata .= $bn.",".repNA($sbinname).",P,".$sbin{$bn}."\n";
                }else{
                        $outputdata .= $bn.",".repNA($sbinname).",F,".$sbin{$bn}."\n";
                }

        }
	$outputdata .= "</SBIN>\n";
	
	if ($hOptions{RELLOT}) {
		$outputdata .= "<REL>\n";	
			$outputdata .= repNA($rel{qpnumber}).",".repNA($rel{devchar}).",".repNA($rel{lotchar}).","
			.repNA($rel{strname}).",".repNA($rel{strduration}).",".repNA($rel{atetemp}).",".repNA($rel{datalogtype})."\n";
		$outputdata .= "</REL>\n";
	}

	$outputdata .= "<PAR_DATA>\n";
	$outputdata .= "</PAR_DATA>\n";
	
	$wr->open;
	$wr->put($outputdata);
	$wr->close;
}

sub check2Dscan {
        my $file = shift;
        my $result = `grep "TEST_SITE[1-9]" $file`;
        my $scan_flg = ($result ne "") ? 'Y' : 'N';

        return $scan_flg;
}



