#!/usr/bin/env perl_db
my $ToolName = "fcs_camstar_lot_event.pl";
#
#------------------------- File Header -----------------------------------
#
# File Name: fcs_camstar_lot_event.pl
#
# Description: This script will add LSR meta and summary data to SPD files, and validate data in some cases.
#
# Sccs Id:    @(#)fcs_camstar_lot_event.pl	1.0 16/03/2015 17:00:47
#
# Related Files/Documents:
#
# Revision History
# ________________
# Date      Author           Description
#
# 19-03-2015  Jacky      Initial Version
# 22-05-2015  Grace      Delete sequence_number (by Scott's requirment)
# 22-05-2015  Grace      Change program name 
# 29-05-2015  Grace 	 Added support for -v option
# 30-05-2015  S. Boothby Support for latest format of lot event file.
# 06-06-2015  S. Boothby Latest LotEvent format from camstar.
# 06-06-2015  S. Boothby If technology not in file, get from product lookup
# 20-07-2015  S. Boothby Populate source lot from meta lookup, not file.
# 15-08-2020  jgarcia added support to fork output (IFF)/files to designated location.
# 15-04-2021  kgabato	get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
#-------------------------------------------------------------------------
# Usage:
#
# ----------------- Start CVS Section (do not modify) -------------------
#
#      $Id: fcs_camstar_lot_event.pl 2636 2020-10-12 05:39:10Z dpower $
      my($sVersionId) = ( split(' ', '$Revision: 2636 $') )[1];
	  my($VersionAndDate) = "

1.0
";
# ------------------------- End CVS Section -----------------------------
#
##############################################################################

#-------------------------------------------------------------------------
# Variable declarations
use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Getopt::Long;
use File::Basename;
use File::Spec::Functions;
use POSIX qw(strftime);
use PDF::DpData;
use PDF::DpWriter;
use PDF::DAO;
use PDF::Log;
use PDF::DpLoad;
use Config::Tiny;
use PPLOG::PPLogger;

#Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();
# define the string to be used in case of null field
my $nullreplace = "NA";
my $fileIx = undef;
# a hash to receive options
my (%hOptions)= (
    "OUTDIR" => undef,
	"FORK" => undef,
	"FACILITYFILE" => undef,
	"FINALLOT" => 0,
    "EXT" => undef,
    "DEBUG"  => undef,
    "HELP"  => undef,
	"LOGFILE"  => undef,
	"TRACE"  => undef,
);




my @file_list=();
my %missingProduct=();
my %familyhash=();
my %processhash=();
my %missingLot=();
my %lothashes=();
my %output=();
my %erroutput=();
my $facility;
my $location;

##############################################################################
#                                 Main
#
##############################################################################
# command line arguments.

Initialize_argument();

# parse all the files in order
foreach(@file_list) {
  my $file = $_;
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
								"FORK=s",
								"EXT=s",
								"FACILITYFILE=s",
								"LOGFILE=s",
								"FINALLOT",
								"V",
								"VERSION",
								"DEBUG",
								"TRACE",
								"HELP",
								)
					);
	
	#Pass PPLogger object to PDF::Log
    PDF::Log->init( \%hOptions,$pplogger);
    if ($hOptions{PPLOG}){
                $pplogger->settobeLog(1);  #Set flag for pp logging
    }
    $pplogger->setScript(basename($0));
	
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
	
	my $config = Config::Tiny->read($hOptions{FACILITYFILE});
        $location = $hOptions{LOC};
        $facility = "";
	
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
  
 
  my $techonologyColumn=undef;
  
  my $productColumn=undef;
  my $stageColumn=undef;
  my $stepColumn=undef;  
  my $lotColumn=undef;
  my $onHoldDateColumn=undef;
  my $holdDurationColumn=undef;
  my $sourceLotColumn=undef;
  my $operatorIdColumn=undef;

  my $commentsColumn=undef;
  my $holdReasonDescColumn=undef;
  my $holdReasonCodeColumn=undef;
  
  my $startTimeColumn=undef;
  my $eventTypeColumn=undef;
  my $eventDescColumn=undef;

  
  
 
  
  
  my $bn = basename($file);
  my @words=split(/[_.]/,$bn);
  if($#words<0){
	 dpExit(1,"Unable to get facility code from filename:".$bn);		
  }
  
  my $fab=$words[1];
  $fileIx=$words[2];
 
  # open the file
  open(fhIn, "<$file") || dpExit(1,"Unable to open file $file");
  
  while(<fhIn>){
		chomp;
		
		s/\r//;
		my $line=$_;
		s/~//g;
		
		@work = split("\\|");
		if (not $iGotHeader)
		{
			
			for (my $i = 0;$i <= $#work;$i++)
			{
				
				if ($work[$i] eq "technology")
				{
					$techonologyColumn = $i;
				}
				elsif ($work[$i] eq "product")
				{
					$productColumn = $i;
				}
				elsif ($work[$i] eq "stage")
				{
					$stageColumn = $i;
				}

				elsif($work[$i] eq "step")
				{
					$stepColumn = $i;
				}				
				elsif ($work[$i] eq "lot")
				{
					$lotColumn = $i;
				}
				elsif ($work[$i] eq "OnHoldDate")
				{
					$onHoldDateColumn = $i;
				}
				elsif ($work[$i] eq "holdDuration")
				{
					$holdDurationColumn = $i;
				}
				elsif ($work[$i] eq "sourceLot")
				{
					$sourceLotColumn = $i;
				}
				elsif ($work[$i] eq "startTime")
				{
					$startTimeColumn = $i;
				}
				elsif ($work[$i] eq "EventType")
				{
					$eventTypeColumn = $i;
				}elsif ($work[$i] eq "EventDesc")
				{
					$eventDescColumn = $i;
				}
				elsif ($work[$i] eq "comments")
				{
					$commentsColumn = $i;
				}
				elsif ($work[$i] eq "username")
				{
					$operatorIdColumn = $i;
				}
				elsif ($work[$i] eq "holdReasonDesc")
				{
					$holdReasonDescColumn = $i;
				}
				elsif ($work[$i] eq "fcsWksHoldReasonCode")
				{
					$holdReasonCodeColumn = $i;
				}
			}
			
			$iGotHeader = 1;
			if(defined($techonologyColumn) && defined($productColumn) && defined($stageColumn) && defined($stepColumn) 
				&& defined($lotColumn) && defined($sourceLotColumn) && defined($onHoldDateColumn) && defined($holdDurationColumn)
				&& defined($operatorIdColumn) && defined($startTimeColumn) 
				&& defined($eventTypeColumn) && defined($eventDescColumn)){
				
			}else{
				ERROR("necesary camstar lot_event dat columns undefined".$file);
				dpExit(1,"error necessary camstar lot_event columns undefined: ".$file);
			}
		}else{
			my $technology=$work[$techonologyColumn];
			
			my $lot=$work[$lotColumn];
			
			if($lot =~ /^\s*$/){
				WARN("necessary lot undefined line in dat file--".$line);
				next;
			}
			
			my $product=$work[$productColumn];
			my $stage=$work[$stageColumn];
			my $step=$work[$stepColumn];			
			my $sourceLot=$work[$sourceLotColumn];
			my $operatorId=$work[$operatorIdColumn];
			# If datetime is YYYY/MM/DD, convert to MM/DD/YYYY
			#my $onHoldDate=convertDate($work[$onHoldDateColumn]);
			my $onHoldDate=$work[$onHoldDateColumn];
			my $holdDuration=$work[$holdDurationColumn];
			# If datetime is YYYY/MM/DD, convert to MM/DD/YYYY
			#my $startTime=convertDate($work[$startTimeColumn]);
			my $startTime=$work[$startTimeColumn];
			
			my $eventType=$work[$eventTypeColumn];
			my $eventDesc=$work[$eventDescColumn];
			my $comments=$work[$commentsColumn];
			my $holdReasonDesc=$work[$holdReasonDescColumn];
			my $holdReasonCode=$work[$holdReasonCodeColumn];
			
			
			my ($family, $process)=GetProductInfo($product);
			INFO( "GetProductInfo Returned ". $product . " ".$family." ". $process );
			my ($source_lot,$lot_owner,$lot_class) = GetMetaByLot($lot);
			if($technology =~ /^\s*$/)
			{
                                $technology=$process;
				if ($technology =~ /^\s*$/)
				{
				    WARN("necessary technology undefined line in dat file--".$line);
				    next;
				}
			}
			
			my $ii = index($bn,'.');
			my $technology_ff = $technology;
			$technology_ff =~ tr/ /-/;
			my $fname = substr($bn,0,$ii).".".$fileIx.".".$technology_ff;
			
			
			if(defined($missingLot{$lot})   || defined($missingProduct{$product}) ){
				if(defined($erroutput{$fname})){
				
				}else{
					$erroutput{$fname} = "<HEADER>\n";
					$erroutput{$fname} .= "VERSION=".$sVersionId."\n";
					$erroutput{$fname} .= "CREATION_DATE=".strftime("%m/%d/%Y %H:%M:%S",localtime(time()))."\n";
					$erroutput{$fname} .= "PROGRAM_CLASS=15\n";
					$erroutput{$fname} .= "PROGRAM=".$technology."::".$fab."::CAM\n";
					$erroutput{$fname} .= "FAB=".$fab."\n";
					$erroutput{$fname} .= "PROCESS=".$technology."\n";
					$erroutput{$fname} .= "</HEADER>\n";
					
					$erroutput{$fname} .= "<DATA>\n";
					
					$erroutput{$fname} .= join("|",("product","family","stage","step","lot","sourceLot","onHoldDate","holdDuration","operatorId","startTime","EventType","EventDesc","comments","holdReasonDesc","holdReasonCode","LOT_OWNER","LOT_CLASS"))."\n";
				}
			
				$erroutput{$fname} .= join("|",(FormatField($product),FormatField($family),FormatField($stage),FormatField($step)
								,FormatField($lot),formatSourceLot($sourceLot, $lot),FormatField($onHoldDate),FormatField($holdDuration)
								,FormatField($operatorId),FormatField($startTime)
								,FormatField($eventType),FormatField($eventDesc),FormatField($comments)
								,FormatField($holdReasonDesc),FormatField($holdReasonCode)
								,FormatField($lot_owner),FormatField($lot_class)))."\n";
			}else{
				if(defined($output{$fname})){
				
				}else{
					$output{$fname} = "<HEADER>\n";
					$output{$fname} .= "VERSION=".$sVersionId."\n";
					$output{$fname} .= "CREATION_DATE=".strftime("%m/%d/%Y %H:%M:%S",localtime(time()))."\n";
					$output{$fname} .= "PROGRAM_CLASS=15\n";
					$output{$fname} .= "PROGRAM=".$technology."::".$fab."::CAM\n";
					$output{$fname} .= "FAB=".$fab."\n";
					$output{$fname} .= "PROCESS=".$technology."\n";
					$output{$fname} .= "</HEADER>\n";
					
					$output{$fname} .= "<DATA>\n";
					
					$output{$fname} .= join("|",("product","family","stage","step","lot","sourceLot","onHoldDate","holdDuration","operatorId","startTime","EventType","EventDesc","comments","holdReasonDesc","holdReasonCode","LOT_OWNER","LOT_CLASS"))."\n";
				}
			
				$output{$fname} .= join("|",(FormatField($product),FormatField($family),FormatField($stage),FormatField($step)
								,FormatField($lot),formatSourceLot($source_lot, $lot),FormatField($onHoldDate),FormatField($holdDuration)
								,FormatField($operatorId),FormatField($startTime)
								,FormatField($eventType),FormatField($eventDesc),FormatField($comments)
								,FormatField($holdReasonDesc),FormatField($holdReasonCode)
								,FormatField($lot_owner),FormatField($lot_class)))."\n";
								
			
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
			forkdir => $hOptions{FORK},
			basename => ($fn),
			ext => $ext,
			gzipIFF => 'Y',
		}
		);
		$output{$holder} .= "</DATA>\n";
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
				forkdir => $hOptions{FORK},
				basename => ($fn),
				ext => $ext,
				noMeta => 1,
				gzipIFF => 'Y'
			}
		);
		$wr->noMeta(1);
		$erroutput{$holder} .= "</DATA>\n";
		$wr->open;
		$wr->put($erroutput{$holder}); 
		$wr->close;
	
		}	
	
	}
}


##############################################################################
# Subroutine: GetMetaByLot
##############################################################################
sub GetMetaByLot{
	my $lot=shift();
	my $hash=undef;
	if(defined($missingLot{$lot})){
		return ("N/A","N/A","N/A");
	}
	if(defined($lothashes{$lot})){
		$hash = $lothashes{$lot};
	}else{
		if($hOptions{FINALLOT}){
			$hash = getRefdb->getMetaDataFinalLot($lot);
		}else{
			$hash = getRefdb->getMetaData($lot);
		}
		if(keys %$hash > 0){
			$lothashes{$lot}=$hash;
		}else{
			WARN("Bad.. Meta Not Found for Lot = ".$lot);
			$missingLot{$lot}=1;
			return ("N/A","N/A","N/A");
		}
	}
	return ($hash->{source_lot},$hash->{lot_owner},$hash->{lot_class});
}
##############################################################################
# Subroutine: GetProductInfo
##############################################################################
sub GetProductInfo{
	my $prod=shift();
	
	if(defined($missingProduct{$prod})){
		return ("N/A", "N/A" );
	}
	if(defined($familyhash{$prod})){
		return ($familyhash{$prod},$processhash{$prod});
	}else{
		my $hash = getRefdb->getProduct($prod);
		if(keys %$hash > 0){
			$familyhash{$prod}=$hash->{family};
			$processhash{$prod}=$hash->{process};
			return ($familyhash{$prod},$processhash{$prod});
		}else{
			ERROR("Bad.. Meta Not Found for Product = ".$prod);
			$missingProduct{$prod}=1;
			return ("N/A", "N/A" );
		}
	}
}
##############################################################################
# Subroutine: FormatField
##############################################################################
sub FormatField{
	my $va=shift();
	my $NA="N/A";
	if($va =~ /^\s*$/){
		return($NA);
	}else{
		return($va);
	}
	
}

sub convertDate
{
my $curDate = shift;
my ($dt1, $dt2, $dt3, $hh, $mm, $ss, $ampm) = split("/|:| ", $curDate);
my $newDate = undef;
if ( $ampm == "" )
{
   if ( $hh < 12 )
   {
      if ( $hh == 0 )
      {
         $hh = 12;
      }
      $ampm = "AM";
   }
   elsif ( $hh == 12 )
   {
      $ampm = "PM";
   }
   else
   {
      $ampm = "PM";
      $hh = $hh - 12;
      if ( $hh < 10 )
      {
         $hh = "0$hh";
      }
   }
}
if (length($dt1) == 4)
{
   $newDate = "$dt2/$dt3/$dt1 $hh:$mm:$ss $ampm";
}
else
{
   $newDate = $curDate;
}

return $newDate;
}


