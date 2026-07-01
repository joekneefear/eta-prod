#!/usr/bin/env perl_db
my $ToolName = "fcs_fom_scrap.pl";
#
#------------------------- File Header -----------------------------------
#
# File Name: fcs_fom_scrap.pl
#
# Description: This script will add LSR meta and summary data to SPD files, and validate data in some cases.
#
# Sccs Id:    @(#)fcs_fom_scrap.pl	1.0 16/03/2015 17:00:47
#
# Related Files/Documents:
#
# Revision History
# ________________
# Date      Author           Description
#
# 19-03-2015  Jacky     Initial Version
# 29-05-2015  grace 	Added support for -v option
# 29-06-2015  S. Boothby Use EQUIP6 instead of Fab for subcon name.
#-------------------------------------------------------------------------
# Usage:
#
# ----------------- Start CVS Section (do not modify) -------------------
#
#      $Id: fcs_fom_scrap.pl 647 2015-06-30 18:07:22Z dpower $
      my($sVersionId) = ( split(' ', '$Revision: 647 $') )[1];
	  my($VersionAndDate) = "

1.0
";
# ------------------------- End CVS Section -----------------------------
#
##############################################################################

#-------------------------------------------------------------------------
# Variable declarations
use strict;
use Getopt::Long;
use File::Basename;
use File::Spec::Functions;
use POSIX qw(strftime);
use PDF::DpData;
use PDF::DAO;
use PDF::Log;
use PDF::DpWriter;
use PDF::DpLoad;


# define the string to be used in case of null field
my $nullreplace = "NA";
# a hash to receive options
my (%hOptions)= (
    "OUTDIR" => undef,
    "EXT" => "sum",
    "DEBUG"  => undef,
    "SEPARATOR" => undef,
    "FINALLOT" => 0,
    "HELP"  => undef,
	"LOGFILE"  => undef,
	"TRACE"  => undef,
);




my @file_list=();
my %output=();
my %erroutput=();

##############################################################################
#                                 Main
#
##############################################################################
# command line arguments.

Initialize_argument();

# parse all the files in order
foreach(@file_list) {
  my $file = $_;
  INFO($file);
  if ( ! -f $file ) {    
    dpExit( 1, "input file does not exist $file" );
  }
  
  
  INFO("--> Splitting the file $file, please wait...");
  
  Split_on_single_file($file,\%hOptions);
  
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
								"LOGFILE=s",
								"FINALLOT",
								"V",
								"VERSION",
								"DEBUG",
								"TRACE",
								"HELP",
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
	#	MyUsage();
	}
	
	
	
	if ($hOptions{LOGFILE}){
		PDF::Log->init($hOptions{LOGFILE});
	} else {
		PDF::Log->init;
	}
	PDF::Log->setLevelDebug if ($hOptions{DEBUG});
	PDF::Log->setLevelTrace if ($hOptions{TRACE});
	
	# output the option values if the debug option is turned on
	DEBUG("Input file: @file_list");
	DEBUG("Output directory: $hOptions{OUTDIR}");
	DEBUG("Datatype: $hOptions{EXT}");
	INFO("IsFinalLot: $hOptions{FINALLOT}");
	
	
	return 1;
}

##############################################################################
# Subroutine: MyUsage
##############################################################################
sub MyUsage{
	my($sUsageMsg) = <<"__END_OF_USAGE_MESSAGE__";      # Usage note
fcs_fom_scrap.pl <inputfiles> ..
	[ -outdir <directory> ]         Output directory
	[ -ext <extention> ]	        Specify the extension of outputfiles
	[ -finallot ]			Specify whether the lot is final lot
	[ -debug ]                      Debug mode (off by default)
	[ -VERSION | -help ]            Display version ID or help message
	[ -logfile ]            		   Used to log 
__END_OF_USAGE_MESSAGE__
	
	die "$sUsageMsg";
}

##############################################################################
# Subroutine: Split_on_single_file
##############################################################################
sub Split_on_single_file {

  my ($file, $hOptions) = @_;
  my @work=();
  %output=();
  %erroutput=();
  my $iGotHeader = 0;
  
 
  my $lotidColumn=undef;
  my $adjustdateColumn=undef;
  my $adjusttimeColumn=undef;
  my $engnameColumn=undef;
  my $totscrapColumn=undef;
  my $testoutqtyColumn=undef;
  my $itemidColumn=undef;
  my $lottypeColumn=undef;
  my $datecodeColumn=undef;
  my $subconColumn=undef;
  my $scrapqtyColumn=undef;  
  
  
  my $bn = basename($file);
  
 
  # open the file
  open(fhIn, "<$file") || dpExit(1,"Unable to open file $file");
  
  while(<fhIn>){
		chomp;
		s/\r//;
		my $line=$_;
		@work = split(",");
		if (not $iGotHeader)
		{
			for (my $i = 0;$i <= $#work;$i++)
			{
				$work[$i] =~ s/^\s+//;
				$work[$i] =~ s/\s+$//;
				if ($work[$i] eq "LOTID")
				{
					$lotidColumn = $i;
				}
				elsif ($work[$i] eq "ADJUST_DATE")
				{
					$adjustdateColumn = $i;
				}
				elsif ($work[$i] eq "ADJUST_TIME")
				{
					$adjusttimeColumn = $i;
				}

				elsif($work[$i] eq "ENG_NAME")
				{
					$engnameColumn = $i;
				}
				elsif ($work[$i] eq "TOTSCRAP")
				{
					$totscrapColumn = $i;
				}
				elsif ($work[$i] eq "TEST_OUTQTY")
				{
					$testoutqtyColumn = $i;
				}elsif ($work[$i] eq "ITEMID")
				{
					$itemidColumn = $i;
				}
				elsif ($work[$i] eq "LOT_TYPE")
				{
					$lottypeColumn = $i;
				}
				elsif ($work[$i] eq "DATE_CODE")
				{
					$datecodeColumn = $i;
				}
				elsif ($work[$i] eq "SUBCON")
				{
					$subconColumn = $i;
				}
				elsif ($work[$i] eq "SCRAPQTY")
				{
					$scrapqtyColumn = $i;
				}
			
			}
			
			$iGotHeader = 1;
			if(defined($lotidColumn) && defined($adjustdateColumn) && defined($adjusttimeColumn) && defined($engnameColumn) 
				&& defined($totscrapColumn) && defined($testoutqtyColumn) && defined($lottypeColumn) && defined($datecodeColumn)
				&& defined($subconColumn)){
				
			}else{
				ERROR("necesary fom scrap dat columns undefined".$file);
				dpExit(1,"error necessary fom scrap dat columns undefined: ".$file);
			}
		}else{
			my $lotid=$work[$lotidColumn];
			
			if($lotid =~ /^\s*$/){
				WARN("necessary lotid undefined line in dat file--".$line);
				next;
			}
			
			my $adjustdate=$work[$adjustdateColumn];
			
			if($adjustdate  =~ /^\s*$/){
				WARN("necessary ajustdate undefined line in dat file--".$line);
				next;
			}
			
			my $adjusttime=$work[$adjusttimeColumn];
			
			if($adjusttime =~ /^\s*$/){
				WARN("necessary ajusttime undefined line in dat file--".$line);
				next;
			}
			
			my $engname=$work[$engnameColumn];
			my $totscrap=$work[$totscrapColumn];
			my $testoutqty=$work[$testoutqtyColumn];
			my $itemid=$work[$itemidColumn];
			
			my $lottype=$work[$lottypeColumn];
			my $datecode=$work[$datecodeColumn];
			my $subcon=$work[$subconColumn];
			
			my $scrapqty=$work[$scrapqtyColumn];
			
  
			my $ii = index($bn,'.');
			
			my $fname = substr($bn,0,$ii)."_".$lotid."_".$adjustdate."_".$adjusttime;
			if(defined($output{$fname}) || defined($erroutput{$fname})){
				next;
			}else{
					my $ifMissing=0;
					my $header = PDF::DpData::HeaderLong->new();
					$header->VERSION($sVersionId);
					$header->CREATION_DATE(strftime("%m/%d/%Y %H:%M:%S",localtime(time())));
					$header->LOT($lotid);
					$header->isFinalLot($hOptions{FINALLOT});
					$header->PROGRAM_CLASS(12);
					$header->PROGRAM("SCRAP_ASFT_".$subcon."_".$engname);
					
					 # get Mata from database
					 # need to use product from data file (itemid)  no need to look up PP_LOT
=head
					unless ($header->populateMeta){
						ERROR("cannot populate Meta data from refdb by lot id: ".$lotid);
					};
=cut					
					$header->PRODUCT($itemid);
					# get Mata from database
					unless ($header->populateMetaByProduct){
						ERROR("cannot populate Meta data from refdb by product id: ".$itemid);
						$ifMissing=1;
					};
					
					$header->LOT_CLASS($lottype);
					$header->DATE_CODE($datecode);
					$header->SOURCE_LOT($lotid);
#					$header->FAB($subcon."_".$engname);
					$header->EQUIP6_ID($engname);
					$header->START_TIME($adjustdate." ".$adjusttime);
					$header->END_TIME($adjustdate." ".$adjusttime);
					$header->DEVICE_COUNT($totscrap+$testoutqty);
					
					my $str_header ="<HEADER>\n";
					$str_header.=$header->toString;
					$str_header .= "</HEADER>\n";
					if($ifMissing){
						$erroutput{$fname}=$str_header;
						$erroutput{$fname} .= "<SUB_LOT>\n";
						my $sourceLot = $header->SOURCE_LOT;
						$erroutput{$fname} .= $sourceLot."_00\n";
						$erroutput{$fname} .= "</SUB_LOT>\n";
					
						$erroutput{$fname} .= "<BIN_DATA>\n";						
						$erroutput{$fname} .= "</BIN_DATA>\n";
					
						$erroutput{$fname} .= "<PAR_DATA_PID_SCRAP>\n";
						$erroutput{$fname} .= "1,FG_INQTY,".repNA($testoutqty)."\n";
						
						my $fg_outqty = $testoutqty - $totscrap;
						$erroutput{$fname} .= "2,FG_OUTQTY,".repNA($fg_outqty)."\n";
						$erroutput{$fname} .= "3,FG_LOSSQTY,".repNA($totscrap)."\n";
						my $fgyield = 0;
						
						if( (($testoutqty-$totscrap) eq 0) or ($testoutqty eq ""))
						{
							$fgyield = 0
						}
						else
						{
							$fgyield = ($testoutqty-$totscrap)/ $testoutqty;
						}

						$erroutput{$fname} .= "4,FG_YIELD,".repNA($fgyield)."\n";
												
						$erroutput{$fname} .= "</PAR_DATA_PID_SCRAP>\n";					

					}else{
						$output{$fname}=$str_header;
						$output{$fname} .= "<SUB_LOT>\n";
						my $sourceLot = $header->SOURCE_LOT;
						$output{$fname} .= $sourceLot."_00\n";
						$output{$fname} .= "</SUB_LOT>\n";
					
						$output{$fname} .= "<BIN_DATA>\n";						
						$output{$fname} .= "</BIN_DATA>\n";
					
						$output{$fname} .= "<PAR_DATA_PID_SCRAP>\n";
						$output{$fname} .= "1,FG_INQTY,".repNA($testoutqty)."\n";
						
						my $fg_outqty = $testoutqty - $totscrap;
						$output{$fname} .= "2,FG_OUTQTY,".repNA($fg_outqty)."\n";
						$output{$fname} .= "3,FG_LOSSQTY,".repNA($totscrap)."\n";
						my $fgyield = 0;
						
						if( (($testoutqty-$totscrap) eq 0) or ($testoutqty eq ""))
						{
							$fgyield = 0
						}
						else
						{
							$fgyield = ($testoutqty-$totscrap)/ $testoutqty;
						}

						$output{$fname} .= "4,FG_YIELD,".repNA($fgyield)."\n";
												
						$output{$fname} .= "</PAR_DATA_PID_SCRAP>\n";	
						
					}
					
			}

		}
  }
	OutputFiles($hOptions{EXT});

}

##############################################################################
# Subroutine: OutputFiles
##############################################################################
sub OutputFiles{
	my $ext=shift();
	my $holder=undef;
	foreach $holder (sort keys %output)
	{
		my $fn=$holder;
		$fn =~ s/ //g;
		$fn =~ s/\///g; 
		my $wr=PDF::DpWriter->new(
		{
			outdir => $hOptions{OUTDIR},
			basename => ($fn),
			ext => $ext,
		}
		);
		#$output{$holder} .= "</DATA>\n";
		$wr->open;
		$wr->put($output{$holder}); 
		$wr->close;
	}
	
	if(keys %erroutput > 0){
		foreach $holder (sort keys %erroutput){
			my $fn=$holder;
			$fn =~ s/ //g;
			$fn =~ s/\///g; 
			my $wr=PDF::DpWriter->new(
			{
				outdir => $hOptions{OUTDIR},
				basename => ($fn),
				ext => $ext,
				noMeta => 1
			}
		);
		$wr->noMeta(1);
		#$erroutput{$holder} .= "</DATA>\n";
		$wr->open;
		$wr->put($erroutput{$holder}); 
		$wr->close;
	
		}	
	
	}
}


##############################################################################
# Subroutine: dpExit
##############################################################################


=head
sub dpExit {
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
   print "$message \n"; 
   $result = 1;
   exit($result);
 }

 print OUTFILE "$result\t0\t$message\n";      
 close(OUTFILE);

 exit($result);
}
=cut
