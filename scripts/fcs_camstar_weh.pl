#!/usr/bin/env perl_db
my $ToolName = "fcs_camstar_weh.pl";
#
#------------------------- File Header -----------------------------------
#
# File Name: fcs_camstar_weh.pl
#
# Description: This script will add LSR meta and summary data to SPD files, and validate data in some cases.
#
# Sccs Id:    @(#)fcs_camstar_weh.pl	1.0 16/03/2015 17:00:47
#
# Related Files/Documents:
#
# Revision History
# ________________
# Date      Author           Description
#
# 19-03-2015  Jacky        Initial Version
# 31-05-2015  S. Boothby   Use passed-in exension for sandbox IFF, not ".iff".
# 30-07-2015  S. Boothby   Add file IX to output file name(s).
# 15-08-2020  jgarcia added support to fork output (IFF)/files to designated location.
# 15-04-2021  kgabato       get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
#-------------------------------------------------------------------------
# Usage:
#
# ----------------- Start CVS Section (do not modify) -------------------
#
#      $Id: fcs_camstar_weh.pl 2635 2020-10-12 05:37:53Z dpower $
      my($sVersionId) = ( split(' ', '$Revision: 2635 $') )[1];
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
use PDF::DAO;
use PDF::DpWriter;
use PDF::DpLoad;
use PDF::Log;
use Config::Tiny;
use PPLOG::PPLogger;


#Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();
# define the string to be used in case of null field
my $nullreplace = "NA";
# a hash to receive options
my (%hOptions)= (
    "OUTDIR" => undef,
	"FORK" => undef,
    "EXT" => "weh",
     "FACILITYFILE" => undef,
	"FINALLOT" => 0,
    "DEBUG"  => undef,
    "HELP"  => undef,
	"LOGFILE"  => undef,
	"TRACE"  => undef,
);


my $fileIx=undef;

my @file_list=();

my %prodhashes=();
my %missingLot=();
my %missingProduct=();
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
INFO("Fork dir = $hOptions{FORK}");

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
								"FINALLOT",
								"V",
								"VERSION",
								"LOGFILE=s",
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
fcs_camstar_weh.pl <inputfiles> ...
       [ -outdir <directory> ]         Output directory
       [ -ext <extension> ]            Specify the extension of the output files, default is weh
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
  
 
  my $waferColumn=undef;
  
  my $productColumn=undef;
  my $stageColumn=undef;
  my $stepColumn=undef;
  my $sequenceNumberColumn=undef;
  my $lotColumn=undef;
  my $sourceLotColumn=undef;
  my $recipeColumn=undef;
  my $processEquipIdColumn=undef;
  my $operatorIdColumn=undef;
  my $trackInColumn=undef;
  my $trackOutColumn=undef;

  
  #my $headerline=undef;
  #my $errorlines=undef;
  
  
  
  
  
  my $bn = basename($file);
  my @words=split(/[_|\.]/,$bn);
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
			#$headerline=$line;
			for (my $i = 0;$i <= $#work;$i++)
			{
				
				if ($work[$i] eq "wafer")
				{
					$waferColumn = $i;
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
				elsif ($work[$i] eq "sequence_number")
				{
					$sequenceNumberColumn = $i;
				}
				elsif ($work[$i] eq "lot")
				{
					$lotColumn = $i;
				}elsif ($work[$i] eq "sourceLot")
				{
					$sourceLotColumn = $i;
				}
				elsif ($work[$i] eq "recipe")
				{
					$recipeColumn = $i;
				}

				elsif($work[$i] eq "processEquipId")
				{
					$processEquipIdColumn = $i;
				}
				elsif ($work[$i] eq "operatorId")
				{
					$operatorIdColumn = $i;
				}
				elsif ($work[$i] eq "trackIn")
				{
					$trackInColumn = $i;
				}elsif ($work[$i] eq "trackOut")
				{
					$trackOutColumn = $i;
				}
			}
			
			$iGotHeader = 1;
			if(defined($waferColumn) && defined($productColumn) && defined($stageColumn) && defined($stepColumn) 
				&& defined($sequenceNumberColumn) && defined($lotColumn) && defined($sourceLotColumn) && defined($recipeColumn)
				&& defined($processEquipIdColumn) && defined($operatorIdColumn) && defined($trackInColumn) && defined($trackOutColumn)){
				
			}else{
				ERROR("necesary camstar leh dat columns undefined".$file);
				dpExit(1,"error necessary camstar leh columns undefined: ".$file);
			}
		}else{
			my $wafer=$work[$waferColumn];
=head	
			if($technology =~ /^\s*$/){
				WARN("necessary technology undefined line in dat file--".$line);
				next;
			}
=cut			
			my $lot=$work[$lotColumn];
			
			if($lot =~ /^\s*$/){
				WARN("necessary lot undefined line in dat file--".$line);
				next;
			}
			
			
			#my $source_lot = $hash->{SOURCE_LOT};
			#my $lot_owner = $hash->{LOT_OWNER};
			
			my ($source_lot,$lot_owner,$lot_class) = GetMetaByLot($lot);
			
			my $product=$work[$productColumn];
			my ($family,$process)=GetMetaByProduct($product);
			$process =~ s/ /_/g;
			
			my $stage=$work[$stageColumn];
			my $step=$work[$stepColumn];
			my $sequenceNumber=$work[$sequenceNumberColumn];
			my $sourceLot=$work[$sourceLotColumn];
			my $recipe=$work[$recipeColumn];
			my $processEquipId=$work[$processEquipIdColumn];
			my $operatorId=$work[$operatorIdColumn];
			my $trackIn=$work[$trackInColumn];
			my $trackOut=$work[$trackOutColumn];
			
			my $ii = index($bn,'.');
			
			my $fname = substr($bn,0,$ii).".".$fileIx.".".$process;
			
			
			#my $family = $hash->{FAMILIY};
			
			if(defined($missingLot{$lot}) || defined($missingProduct{$product})){
				if(defined($erroutput{$fname})){
				
				}else{
					$erroutput{$fname} = "<HEADER>\n";
					$erroutput{$fname} .= "VERSION=".$sVersionId."\n";
					$erroutput{$fname} .= "CREATION_DATE=".strftime("%m/%d/%Y %H:%M:%S",localtime(time()))."\n";
					$erroutput{$fname} .= "PROGRAM_CLASS=13\n";
					$erroutput{$fname} .= "PROGRAM=".$process."::".$fab."::CAM"."\n";
					$erroutput{$fname} .= "FAB=".$fab."\n";
					$erroutput{$fname} .= "PROCESS=".$process."\n";
					$erroutput{$fname} .= "</HEADER>\n";
					
					$erroutput{$fname} .= "<DATA>\n";
					
					$erroutput{$fname} .= join("|",("technology","product","family","stage","step","sequence_number","lot","wafer","sourceLot","recipe","processEquipId","operatorId","trackIn","trackOut","SOURCE_LOT","LOT_OWNER","LOT_CLASS"))."\n";
				}
			
				$erroutput{$fname} .= join("|",(FormatField($process),FormatField($product),FormatField($family),FormatField($stage),FormatField($step)
								,FormatField($sequenceNumber),FormatField($lot),FormatField($wafer),FormatField($sourceLot),FormatField($recipe),FormatField($processEquipId)
								,FormatField($operatorId),FormatField($trackIn),FormatField($trackOut),formatSourceLot($source_lot, $lot)
								,FormatField($lot_owner),FormatField($lot_class)))."\n";
			}else{
			
			
			
			
				if(defined($output{$fname})){
				
				}else{
					$output{$fname} = "<HEADER>\n";
					$output{$fname} .= "VERSION=".$sVersionId."\n";
					$output{$fname} .= "CREATION_DATE=".strftime("%m/%d/%Y %H:%M:%S",localtime(time()))."\n";
					$output{$fname} .= "PROGRAM_CLASS=13\n";
					$output{$fname} .= "PROGRAM=".$process."::".$fab."::CAM"."\n";
					$output{$fname} .= "FAB=".$fab."\n";
					$output{$fname} .= "PROCESS=".$process."\n";
					$output{$fname} .= "</HEADER>\n";
					
					$output{$fname} .= "<DATA>\n";
					
					$output{$fname} .= join("|",("technology","product","family","stage","step","sequence_number","lot","wafer","sourceLot","recipe","processEquipId","operatorId","trackIn","trackOut","SOURCE_LOT","LOT_OWNER","LOT_CLASS"))."\n";
				}
			
				$output{$fname} .= join("|",(FormatField($process),FormatField($product),FormatField($family),FormatField($stage),FormatField($step)
								,FormatField($sequenceNumber),FormatField($lot),FormatField($wafer),FormatField($sourceLot),FormatField($recipe),FormatField($processEquipId)
								,FormatField($operatorId),FormatField($trackIn),FormatField($trackOut),formatSourceLot($source_lot, $lot)
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
		if($hOptions{FINALLOT}){
			return ($lot,"N/A","N/A");
		}else{
			return ("N/A","N/A","N/A");
		}
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
			if($hOptions{FINALLOT}){
				return ($lot,"N/A","N/A");
			}else{
				return ("N/A","N/A","N/A");
			}
		}
	}
	if($hOptions{FINALLOT}){
		return ($lot,$hash->{lot_owner},$hash->{lot_class});
	}else{
		return ($hash->{source_lot},$hash->{lot_owner},$hash->{lot_class});
	}
}

##############################################################################
# Subroutine: GetMetaByProduct
##############################################################################
sub GetMetaByProduct{
	my $prod=shift();
	my $hash=undef;
	if(defined($missingProduct{$prod})){
		return ("N/A","N/A");
	}
	
	if(defined($prodhashes{$prod})){
		 $hash=$prodhashes{$prod};
	}else{
		$hash = getRefdb->getProduct($prod);
		if(keys %$hash > 0){

			#$familyhash{$prod}=$hash->{family};
			$prodhashes{$prod} = $hash;
			
		}else{
			ERROR("Bad.. Meta Not Found for Product = ".$prod);
			$missingProduct{$prod}=1;
			return ("N/A","N/A");
		}
	}
	return ($hash->{family},$hash->{process});
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



