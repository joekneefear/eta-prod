#!/usr/bin/env perl_db
my $ToolName = "fcs_fom_pidclose.pl";
#
#------------------------- File Header -----------------------------------
#
# File Name: fcs_fom_pidclose.pl
#
# Description: This script will add LSR meta and summary data to SPD files, and validate data in some cases.
#
# Sccs Id:    @(#)fcs_fom_pidclose.pl	1.0 16/03/2015 17:00:47
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
#      $Id: fcs_fom_pidclose.pl 647 2015-06-30 18:07:22Z dpower $
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
use PDF::Log;
use PDF::DAO;
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
fcs_fom_pidclose.pl <inputfiles> ...
       [ -outdir <directory> ]         Output directory
	   [ -ext <extension]
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
  
 
  my $lotidColumn=undef;
  my $testoutdateColumn=undef;
  
  my $subconnameColumn=undef;
  my $itemidColumn=undef;
  my $pidColumn=undef;
  my $lottypeColumn=undef;
  my $startdateColumn=undef;
  
  my $datecodeColumn=undef;
  my $initialqtyColumn=undef;
  my $assylossqtyColumn=undef;
  my $assyoutqtyColumn=undef;
  my $testinqtyColumn=undef;
  my $testlossColumn=undef;
  my $testoutqtyColumn=undef;
  my $complotidColumn=undef;
  my $multiColumn=undef;
  
  my $subconColumn=undef;
  my $shipqtyColumn=undef;
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
				elsif ($work[$i] eq "DATE_CODE")
				{
					$datecodeColumn = $i;
				}
				elsif ($work[$i] eq "INITIAL_QTY")
				{
					$initialqtyColumn = $i;
				}
				elsif ($work[$i] eq "ASSYLOSSQTY")
				{
					$assylossqtyColumn = $i;
				}elsif ($work[$i] eq "ASSYOUTQTY")
				{
					$assyoutqtyColumn = $i;
				}
				elsif ($work[$i] eq "TESTINQTY")
				{
					$testinqtyColumn = $i;
				}
				elsif ($work[$i] eq "TESTLOSS")
				{
					$testlossColumn = $i;
				}
				elsif ($work[$i] eq "TESTOUTQTY")
				{
					$testoutqtyColumn = $i;
				}
				elsif ($work[$i] eq "COMPLOT")
				{
					$complotidColumn = $i;
				}elsif ($work[$i] eq "SUBCON")
				{
					$subconColumn = $i;
				}elsif ($work[$i] eq "SHIPQTY")
				{
					$shipqtyColumn = $i;
				}
				elsif ($work[$i] eq "MULTI")
				{
					$multiColumn = $i;
				}
			}
			
			$iGotHeader = 1;
			if(defined($lotidColumn) && defined($testoutdateColumn) && defined($subconnameColumn) && defined($itemidColumn) 
				&& defined($pidColumn) && defined($lottypeColumn) && defined($startdateColumn) && defined($datecodeColumn)
				&& defined($initialqtyColumn) && defined($assylossqtyColumn) && defined($assyoutqtyColumn) && defined($testinqtyColumn)
				&& defined($testlossColumn) && defined($testoutqtyColumn) && defined($complotidColumn) && defined($subconColumn)
				&& defined($shipqtyColumn)&& defined($multiColumn)){
				
			}else{
				ERROR("necesary fom pidclose dat columns undefined".$file);
				dpExit(1,"error necessary fom pidclose dat columns undefined: ".$file);
			}
		}else{
			my $lotid=$work[$lotidColumn];
			
			if($lotid =~ /^\s*$/){
				WARN("necessary LOTID undefined line in dat file--".$line);
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
			my $datecode=$work[$datecodeColumn];
			my $initialqty=$work[$initialqtyColumn];
			my $assylossqty=$work[$assylossqtyColumn];
			my $assyoutqty=$work[$assyoutqtyColumn];
			my $testinqty=$work[$testinqtyColumn];
			my $testloss=$work[$testlossColumn];
			my $testoutqty=$work[$testoutqtyColumn];
			my $complotid=$work[$complotidColumn];
			my $subcon=$work[$subconColumn];
			my $shipqty=$work[$shipqtyColumn];
			my $multi=$work[$multiColumn];
			my @ary_multi = split("-", $multi);
			my $ii = index($bn,'.');
			
			my $fname = substr($bn,0,$ii)."_".$lotid."_".$testoutdate;
			if($ary_multi[0] eq $ary_multi[1])
			{
					my $ifMissing=0;
					my $header = PDF::DpData::HeaderLong->new();
					$header->VERSION($sVersionId);
					$header->CREATION_DATE(strftime("%m/%d/%Y %H:%M:%S",localtime(time())));
					$header->LOT($pid);
					$header->isFinalLot($hOptions{FINALLOT});
					$header->PROGRAM_CLASS(12);
					$header->PROGRAM("PIDCLOSE_".$subcon."_".$subconname);
					
					 # get Mata from database  
					 # need to use product from data file (itemid)  no need to look up PP_LOT
=head
					unless ($header->populateMeta){
						ERROR("cannot populate Meta data from refdb by lot id: ".$pid);
						
					};
=cut
					$header->PRODUCT($itemid);
					unless ($header->populateMetaByProduct){
						ERROR("cannot populate Meta data from refdb by product id: ".$itemid);
						$ifMissing=1;
					};
					#$header->EQUIP6_ID($subcon."_".$subconname);
					$header->EQUIP6_ID($subconname);
					
					
					
					
					#$header->SOURCE_LOT($complotid);
					$header->SOURCE_LOT($header->LOT);
					$header->LOT_CLASS($lottype);
					$header->DATE_CODE($datecode);
					$header->START_TIME($startdate." 00:00:00");
					$header->END_TIME($testoutdate);
					$header->DEVICE_COUNT($initialqty);
					
					my $str_header ="<HEADER>\n";
					$str_header.=$header->toString;
					$str_header .= "</HEADER>\n";
					if($ifMissing){
						$erroutput{$fname}=$str_header;
						$erroutput{$fname} .= "<SUB_LOT>\n";
					
					#my $hash = getRefdb->getSourceLot($pid);
					#my $sourceLot = $hash->{source_lot};
						my $sourceLot = $header->SOURCE_LOT;
						$erroutput{$fname} .= $sourceLot."_00\n";
						$erroutput{$fname} .= "</SUB_LOT>\n";
					
						$erroutput{$fname} .= "<BIN_DATA>\n";
						$erroutput{$fname} .= "</BIN_DATA>\n";
												
						$erroutput{$fname} .= "<PAR_DATA_PID_ASSEMBLY>\n";
						$erroutput{$fname} .= "1,FG_INQTY,".repNA($initialqty)."\n";
						$erroutput{$fname} .= "2,FG_OUTQTY,".repNA($assyoutqty)."\n";
						$erroutput{$fname} .= "3,FG_LOSSQTY,".repNA($assylossqty)."\n";
						
						my $fg_yield_ass = 100*$assyoutqty/($assyoutqty+$assylossqty);
						
						$erroutput{$fname} .= "4,FG_YIELD,".repNA($fg_yield_ass)."\n";										
						$erroutput{$fname} .= "</PAR_DATA_PID_ASSEMBLY>\n";
	
					
						$erroutput{$fname} .= "<PAR_DATA_PID_TEST>\n";
						$erroutput{$fname} .= "1,FG_INQTY,".repNA($testinqty)."\n";
						$erroutput{$fname} .= "2,FG_OUTQTY,".repNA($testoutqty)."\n";
						$erroutput{$fname} .= "3,FG_LOSSQTY,".repNA($testloss)."\n";
						my $fg_yield_test = 100*$testoutqty/($testoutqty+$testloss);
						$erroutput{$fname} .= "4,FG_YIELD,".repNA($fg_yield_test)."\n";
						$erroutput{$fname} .= "</PAR_DATA_PID_TEST>\n";
				
						$erroutput{$fname} .= "<PAR_DATA_PID_CLOSE>\n";
						$erroutput{$fname} .= "1,FG_INQTY,".repNA($testoutqty)."\n";
						$erroutput{$fname} .= "2,FG_OUTQTY,".repNA($shipqty)."\n";						
						$erroutput{$fname} .= "</PAR_DATA_PID_CLOSE>\n";
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
						
						
						$output{$fname} .= "<PAR_DATA_PID_ASSEMBLY>\n";
						$output{$fname} .= "1,FG_INQTY,".repNA($initialqty)."\n";
						$output{$fname} .= "2,FG_OUTQTY,".repNA($assyoutqty)."\n";
						$output{$fname} .= "3,FG_LOSSQTY,".repNA($assylossqty)."\n";
						
						my $fg_yield_ass = 100*$assyoutqty/($assyoutqty+$assylossqty);
						
						$output{$fname} .= "4,FG_YIELD,".repNA($fg_yield_ass)."\n";										
						$output{$fname} .= "</PAR_DATA_PID_ASSEMBLY>\n";
	
					
						$output{$fname} .= "<PAR_DATA_PID_TEST>\n";
						$output{$fname} .= "1,FG_INQTY,".repNA($testinqty)."\n";
						$output{$fname} .= "2,FG_OUTQTY,".repNA($testoutqty)."\n";
						$output{$fname} .= "3,FG_LOSSQTY,".repNA($testloss)."\n";
						my $fg_yield_test = 100*$testoutqty/($testoutqty+$testloss);
						$output{$fname} .= "4,FG_YIELD,".repNA($fg_yield_test)."\n";
						$output{$fname} .= "</PAR_DATA_PID_TEST>\n";
				
						$output{$fname} .= "<PAR_DATA_PID_CLOSE>\n";
						$output{$fname} .= "1,FG_INQTY,".repNA($testoutqty)."\n";
						$output{$fname} .= "2,FG_OUTQTY,".repNA($shipqty)."\n";						
						$output{$fname} .= "</PAR_DATA_PID_CLOSE>\n";
						
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
	#	$output{$holder} .= "</DATA>\n";
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
	#	$output{$holder} .= "</DATA>\n";
		$wr->open;
		$wr->put($erroutput{$holder}); 
		$wr->close;
	
		}	
	
	}
}


