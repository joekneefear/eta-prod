#!/usr/bin/env perl_db
my $ToolName = "fcs_fom_sortclose.pl";
#
#------------------------- File Header -----------------------------------
#
# File Name: fcs_fom_sortclose.pl
#
# Description: This script will add LSR meta and summary data to SPD files, and validate data in some cases.
#
# Sccs Id:    @(#)fcs_fom_sortclose.pl	1.0 16/03/2015 17:00:47
#
# Related Files/Documents:
#
# Revision History
# ________________
# Date      Author           Description
#
# 19-03-2015  Jacky     Initial Version
# 29-05-2015  grace 	Added support for -v option
# 29-06-2015  S. Boothby Use EQUIP6 instead of Fab for foundry name.
# 23-06-2016  R. Cyr     Include PID in the output filename to make the file unique to the lot.
#-------------------------------------------------------------------------
# Usage:
#
# ----------------- Start CVS Section (do not modify) -------------------
#
#      $Id: fcs_fom_sortclose.pl 1694 2016-06-23 20:01:51Z dpower $
      my($sVersionId) = ( split(' ', '$Revision: 1694 $') )[1];
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
    "EXT" => undef,
    "FINALLOT" => 0,
    "DEBUG"  => undef,
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

	
	
	return 1;
}

##############################################################################
# Subroutine: MyUsage
##############################################################################
sub MyUsage{
	my($sUsageMsg) = <<"__END_OF_USAGE_MESSAGE__";      # Usage note
splitbycolumn.pl <inputfiles> ...
       [ -outdir <directory> ]         Output directory

       [ -debug ]                      Debug mode (off by default)
       [ -VERSION | -help ]            Display version ID or help messages
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
  
 
  my $compitemidColumn=undef;
  my $testoutdateColumn=undef;
  
  my $subconnameColumn=undef;
  my $itemidColumn=undef;
  my $pidColumn=undef;
  my $lottypeColumn=undef;
  my $startdateColumn=undef;
  my $refqtyColumn=undef;
  my $comqtyColumn=undef;
  my $testoutqtyColumn=undef;
  my $closerefqtyColumn=undef;
  my $testlossColumn=undef;
  my $shipqtyColumn=undef;
  my $shiprefqtyColumn=undef;
  my $complotidColumn=undef;
  
  my $subconColumn=undef; 
  my $closeqtyColumn=undef;

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
				if ($work[$i] eq "COMP_ITEMID")
				{
					$compitemidColumn = $i;
				}
				elsif ($work[$i] eq "TESTOUTDATE")
				{
					$testoutdateColumn = $i;
				}
				elsif ($work[$i] eq "SUBCONNAME")
				{
					$subconnameColumn = $i;
				}

				elsif($work[$i] eq "ITEMID")
				{
					$itemidColumn = $i;
				}
				elsif ($work[$i] eq "PID")
				{
					$pidColumn = $i;
				}
				elsif ($work[$i] eq "LOT_TYPE")
				{
					$lottypeColumn = $i;
				}elsif ($work[$i] eq "START_DATE")
				{
					$startdateColumn = $i;
				}
				elsif ($work[$i] eq "REF_QTY")
				{
					$refqtyColumn = $i;
				}
				elsif ($work[$i] eq "COMP_QTY")
				{
					$comqtyColumn = $i;
				}
				elsif ($work[$i] eq "TEST_OUTQTY")
				{
					$testoutqtyColumn = $i;
				}elsif ($work[$i] eq "CLOSE_REFQTY")
				{
					$closerefqtyColumn = $i;
				}
				elsif ($work[$i] eq "TESTLOSS")
				{
					$testlossColumn = $i;
				}
				elsif ($work[$i] eq "SHIPQTY")
				{
					$shipqtyColumn = $i;
				}
				elsif ($work[$i] eq "SHIPREFQTY")
				{
					$shiprefqtyColumn = $i;
				}
				elsif ($work[$i] eq "COMP_LOTID")
				{
					$complotidColumn = $i;
				}elsif ($work[$i] eq "SUBCON")
				{
					$subconColumn = $i;
				}
				elsif ($work[$i] eq "CLOSEQTY")
				{
					$closeqtyColumn = $i;
				}


			}
			
			$iGotHeader = 1;
			if(defined($compitemidColumn) && defined($testoutdateColumn) && defined($subconnameColumn) && defined($itemidColumn) 
				&& defined($pidColumn) && defined($lottypeColumn) && defined($startdateColumn) && defined($refqtyColumn)
				&& defined($comqtyColumn) && defined($testoutqtyColumn) && defined($closerefqtyColumn) && defined($testlossColumn)
				&& defined($shipqtyColumn) && defined($shiprefqtyColumn) && defined($complotidColumn) && defined($subconColumn)
				&& defined($closeqtyColumn)){
				
			}else{
				ERROR("necesary fom sortclose dat columns undefined".$file);
				dpExit(1,"error necessary fom sortclose dat columns undefined: ".$file);
			}
		}else{
			my $compitem=$work[$compitemidColumn];
			
			if($compitem =~ /^\s*$/){
				WARN("necessary COMP_ITEMID undefined line in dat file--".$line);
				next;
			}
			
			my $testoutdate=$work[$testoutdateColumn];
			
			if($testoutdate =~ /^\s*$/){
				WARN("necessary TESTOUTDATE undefined line in dat file--".$line);
				next;
			}
			
			my $subconname=$work[$subconnameColumn];
			my $itemid=$work[$itemidColumn];
			my $pid=$work[$pidColumn];
			if($pid =~ /^\s*$/){
				WARN("necessary PID undefined line in dat file--".$line);
			}
			my $lottype=$work[$lottypeColumn];
			my $startdate=$work[$startdateColumn];
			my $refqty=$work[$refqtyColumn];
			my $comqty=$work[$comqtyColumn];
			my $testoutqty=$work[$testoutqtyColumn];
			my $closerefqty=$work[$closerefqtyColumn];
			my $testloss=$work[$testlossColumn];
			my $shipqty=$work[$shipqtyColumn];
			my $shiprefqty=$work[$shiprefqtyColumn];
			my $complotid=$work[$complotidColumn];
			my $subcon=$work[$subconColumn];		
			my $closeqty=$work[$closeqtyColumn];	
			
			
			my $ii = index($bn,'.');
			
			my $fname = substr($bn,0,$ii)."_".$pid."_".$compitem."_".$testoutdate;
			$fname =~ s/://g;
			if(defined($output{$fname}) || defined($erroutput{$fname})){
				next;
			}else{
					my $ifMissing=0;
					my $header = PDF::DpData::HeaderLong->new();
					$header->VERSION($sVersionId);
					$header->CREATION_DATE(strftime("%m/%d/%Y %H:%M:%S",localtime(time())));
					$header->LOT($pid);
					$header->isFinalLot($hOptions{FINALLOT});
					$header->PROGRAM_CLASS(12);
					$header->PROGRAM("SORTCLOSE_".$subcon."_".$subconname);

					 # get Mata from database
					 
									 
					unless ($header->populateMeta){
						ERROR("cannot populate Meta data from refdb by lot id: ".$pid);
						$ifMissing=1;
					};
					
					$header->PRODUCT($itemid);
					unless ($header->populateMetaByProduct){
						ERROR("cannot populate Meta data from refdb by product id: ".$itemid);
						$ifMissing=1;
					};	
					
					#$header->FAB($subcon."_".$subconname);
					$header->EQUIP6_ID($subconname);

					#$header->SOURCE_LOT($complotid);				
					$header->LOT_CLASS($lottype);
					$header->START_TIME($startdate." 00:00:00");
					$header->END_TIME($testoutdate);
					$header->DEVICE_COUNT($refqty+$comqty);
					
					my $str_header ="<HEADER>\n";
					$str_header.=$header->toString;
					$str_header .= "</HEADER>\n";
					
					#for testing 
					#$ifMissing = 1;
					if($ifMissing){
						$erroutput{$fname}=$str_header;
						$erroutput{$fname} .= "<SUB_LOT>\n";
					
					#my $hash = getRefdb->getSourceLot($pid);
					#my $sourceLot = $hash->{source_lot};
						my $sourceLot = repNA($header->SOURCE_LOT);
						$erroutput{$fname} .= $sourceLot."_00\n";
						$erroutput{$fname} .= "</SUB_LOT>\n";
				
						$erroutput{$fname} .= "<BIN_DATA>\n";
						$erroutput{$fname} .= "</BIN_DATA>\n";
					
						$erroutput{$fname} .= "<PAR_DATA_SORT_TEST>\n";
						$erroutput{$fname} .= "1,DIE_INQTY,".repNA($refqty)."\n";
						$erroutput{$fname} .= "2,DIE_OUTQTY,".repNA($testoutqty)."\n";
						$erroutput{$fname} .= "3,DIE_LOSSQTY,".repNA($testloss)."\n";
						$erroutput{$fname} .= "4,DIE_YIELD,".100*$testoutqty/($testoutqty+$testloss)."\n";					
						$erroutput{$fname} .= "</PAR_DATA_SORT_TEST>\n";
						
						
						$erroutput{$fname} .= "<PAR_DATA_SORT_CLOSE>\n";
						$erroutput{$fname} .= "1,DIE_INQTY,".repNA($testoutqty)."\n";
						$erroutput{$fname} .= "2,DIE_OUTQTY,".repNA($closeqty)."\n";
						my $die_lossqty = $testoutqty - $closeqty;
						$erroutput{$fname} .= "3,DIE_LOSSQTY,$die_lossqty\n";
						$erroutput{$fname} .= "4,DIE_YIELD,".100*$closeqty/$testoutqty."\n";						
						$erroutput{$fname} .= "5,WFR_INQTY,".repNA($comqty)."\n";
						
						my $wfr_outqty = "N/A";
						my $wfr_lossqty = "N/A";
						if($closerefqty != $closeqty)
						{
							$wfr_outqty = $closerefqty; 
							$wfr_lossqty = $comqty - $closerefqty; 
							
						}
						$erroutput{$fname} .= "6,WFR_OUTQTY,".repNA($wfr_outqty)."\n";						
						$erroutput{$fname} .= "7,WFR_LOSSQTY,".repNA($wfr_lossqty)."\n";						
						$erroutput{$fname} .= "8,WFR_YIELD,".(100*$closerefqty/$comqty)."\n";
						$erroutput{$fname} .= "</PAR_DATA_SORT_CLOSE>\n";
						
						
						$erroutput{$fname} .= "<PAR_DATA_SORT_SHIP>\n";
						$erroutput{$fname} .= "1,DIE_INQTY,".repNA($closeqty)."\n";
						$erroutput{$fname} .= "2,DIE_OUTQTY,".repNA($shipqty)."\n";
						
						my $die_lossqty = $closeqty - $shipqty;
												
						if((repNA($closeqty) eq "N/A" || repNA($shipqty) eq "N/A") or ($closeqty eq "0" || $shipqty eq "0"))
						{
							$erroutput{$fname} .= "3,DIE_LOSSQTY,N/A\n";
							$erroutput{$fname} .= "4,DIE_YIELD,N/A\n";								
						}
						else
						{
							$erroutput{$fname} .= "3,DIE_LOSSQTY,".repNA($die_lossqty)."\n";
							$erroutput{$fname} .= "4,DIE_YIELD,".repNA(100*$shipqty/$closeqty)."\n";	
								
						}
						

						
						my $wfr_inqty = "N/A";
						my $wrf_yield = "N/A";
						if($closerefqty != $closeqty)
						{
							$wfr_inqty = $closerefqty; 
							if($closerefqty eq "" or $closerefqty == 0)
							{
								$wrf_yield = 0;
							}
							else
							{
								$wrf_yield = 100*$shiprefqty/$closerefqty;
							}
							
						}
						
						$erroutput{$fname} .= "5,WFR_INQTY,".repNA($wfr_inqty)."\n";
						$erroutput{$fname} .= "6,WFR_OUTQTY,".repNA($shiprefqty)."\n";						
						
						my $wfr_lossqty = $closerefqty - $shiprefqty;
						
						$erroutput{$fname} .= "7,WFR_LOSSQTY,".repNA($wfr_lossqty)."\n";						
						$erroutput{$fname} .= "8,WFR_YIELD,".repNA($wrf_yield)."\n";
						$erroutput{$fname} .= "</PAR_DATA_SORT_SHIP>\n";	
						

					}else{
						$output{$fname}=$str_header;
						$output{$fname} .= "<SUB_LOT>\n";
					
					#my $hash = getRefdb->getSourceLot($pid);
					#my $sourceLot = $hash->{source_lot};
						my $sourceLot = $header->SOURCE_LOT;
						$output{$fname} .= $sourceLot."_00\n";
						$output{$fname} .= "</SUB_LOT>\n";
					
						$output{$fname} .= "<BIN_DATA>\n";
						$output{$fname} .= "</BIN_DATA>\n";
					
					
						$output{$fname} .= "<PAR_DATA_SORT_TEST>\n";
						$output{$fname} .= "1,DIE_INQTY,".repNA($refqty)."\n";
						$output{$fname} .= "2,DIE_OUTQTY,".repNA($testoutqty)."\n";
						$output{$fname} .= "3,DIE_LOSSQTY,".repNA($testloss)."\n";
						$output{$fname} .= "4,DIE_YIELD,".repNA(100*$testoutqty/($testoutqty+$testloss))."\n";					
						$output{$fname} .= "</PAR_DATA_SORT_TEST>\n";
						
						
						$output{$fname} .= "<PAR_DATA_SORT_CLOSE>\n";
						$output{$fname} .= "1,DIE_INQTY,".repNA($testoutqty)."\n";
						$output{$fname} .= "2,DIE_OUTQTY,".repNA($closeqty)."\n";
						my $die_lossqty = $testoutqty - $closeqty;
						$output{$fname} .= "3,DIE_LOSSQTY,".repNA($die_lossqty)."\n";
						$output{$fname} .= "4,DIE_YIELD,".repNA(100*$closeqty/$testoutqty)."\n";						
						$output{$fname} .= "5,WFR_INQTY,".repNA($comqty)."\n";
						
						my $wfr_outqty = "N/A";
						my $wfr_lossqty = "N/A";
						if($closerefqty != $closeqty)
						{
							$wfr_outqty = $closerefqty; 
							$wfr_lossqty = $comqty - $closerefqty; 
							
						}
						$output{$fname} .= "6,WFR_OUTQTY,".repNA($wfr_outqty)."\n";						
						$output{$fname} .= "7,WFR_LOSSQTY,".repNA($wfr_lossqty)."\n";						
						$output{$fname} .= "8,WFR_YIELD,".repNA((100*$closerefqty/$comqty))."\n";
						$output{$fname} .= "</PAR_DATA_SORT_CLOSE>\n";
						
						
						$output{$fname} .= "<PAR_DATA_SORT_SHIP>\n";
						$output{$fname} .= "1,DIE_INQTY,".repNA($closeqty)."\n";
						$output{$fname} .= "2,DIE_OUTQTY,".repNA($shipqty)."\n";
						
						my $die_lossqty = $closeqty - $shipqty;
						
						if((repNA($closeqty) eq "N/A" || repNA($shipqty) eq "N/A") or ($closeqty eq "0" || $shipqty eq "0"))
						{
							$output{$fname} .= "3,DIE_LOSSQTY,N/A\n";
							$output{$fname} .= "4,DIE_YIELD,N/A\n";								
						}
						else
						{
							$output{$fname} .= "3,DIE_LOSSQTY,".repNA($die_lossqty)."\n";
							$output{$fname} .= "4,DIE_YIELD,".repNA(100*$shipqty/$closeqty)."\n";	
								
						}
						
						my $wfr_inqty = "N/A";
						my $wrf_yield = "N/A";
						if($closerefqty != $closeqty)
						{
							$wfr_inqty = $closerefqty; 
							if($closerefqty eq "" or $closerefqty == 0)
							{
								$wrf_yield = 0;
							}
							else
							{
								$wrf_yield = 100*$shiprefqty/$closerefqty;
							}
							
						}
						
						$output{$fname} .= "5,WFR_INQTY,".repNA($wfr_inqty)."\n";
						$output{$fname} .= "6,WFR_OUTQTY,".repNA($shiprefqty)."\n";						
						
						my $wfr_lossqty = $closerefqty - $shiprefqty;
						
						$output{$fname} .= "7,WFR_LOSSQTY,".repNA($wfr_lossqty)."\n";						
						$output{$fname} .= "8,WFR_YIELD,".repNA($wrf_yield)."\n";
						$output{$fname} .= "</PAR_DATA_SORT_SHIP>\n";	
						
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




