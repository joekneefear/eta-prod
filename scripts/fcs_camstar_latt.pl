#!/usr/bin/env perl_db
my $ToolName = "fcs_camstar_leh.pl";
#
#------------------------- File Header -----------------------------------
#
# File Name: fcs_camstar_leh.pl
#
# Description: This script will add LSR meta and summary data to SPD files, and validate data in some cases.
#
# Sccs Id:    @(#)fcs_camstar_leh.pl	1.0 16/03/2015 17:00:47
#
# Related Files/Documents:
#
# Revision History
# ________________
# Date      Author           Description
#
# 19-03-2015  Jacky      Initial Version
# 28-05-2015  S. Boothby Added support for -v option.
#                        Sandbox output files had additional .iff extension added after command-line extension.
# 01-06-2015  S. Boothby Strip single quotes from attribute file.
# 15-08-2020  jgarcia added support to fork output (IFF)/files to designated location.
# 15-04-2021	kgabato	 get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
#-------------------------------------------------------------------------
# Usage:
#
# ----------------- Start CVS Section (do not modify) -------------------
#
#      $Id: fcs_camstar_latt.pl 2637 2020-10-12 05:40:18Z dpower $
      my($sVersionId) = ( split(' ', '$Revision: 2637 $') )[1];
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
    "EXT" => "latt",
     "FACILITYFILE" => undef,
	"FINALLOT" => 0,
    "DEBUG"  => undef,
    "HELP"  => undef,
	"LOGFILE"  => undef,
	"V"  => undef,
	"TRACE"  => undef,
);




my @file_list=();


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
fcs_camstar_latt.pl <inputfiles> ...
       [ -outdir <directory> ]         Output directory
	   [ -ext <extension> ]			   Output file extension
       [ -finallot ]                   Use PP_FINALLOT instead of PP_LOT for reference data.
       [ -debug ]                      Debug mode (off by default)
       [ -VERSION | -help | -V]            Display version ID or help messages
	   [ -logfile ]            		   Used to log 
__END_OF_USAGE_MESSAGE__
	
	die "$sUsageMsg";
}

##############################################################################
# Subroutine: Split_on_single_file
##############################################################################
sub Split_on_single_file {

  my ($basefile, $hOptions) = @_;
  my @work=();
  %output=();
  %erroutput=();
  my $iGotHeader = 0;

  my $headerline=undef;
 
  #my $ifcomplete=undef;
  my $line = undef;
  my $ifstart=0;
  my $ifend=0;
  my $fileix=1;
  my $fileix_sbx=1;
  my $num=0;
  my $num_sbx=0;

  my $basename=basename($basefile);
  # open the file
  open(fhIn, "<$basefile") || dpExit(1,"Unable to open file $basefile");
  
  while(<fhIn>){
		chomp;
		my $curname = $basename."-".$fileix;
		my $curname_sbx = $basename."-".$fileix_sbx;
		
		s/\r//;
		$_ =~ tr/'//d; # Strip single quotes from text
		if($_ =~ /~$/){
			#$ifcomplete=1;
			if(!$ifstart){
				$line = $_;
			}else{
				$line .= $_;
				$ifstart = 0;
			}
		}else{
			#$ifcomplete=0;
			if(!$ifstart){
				$ifstart=1;
				$line = $_;
			}else{
				$line .= $_;
			}
			
			next;
			
			
		}
		
		#s/~//g;
		
		
		
		if (not $iGotHeader)
		{
			if($line =~ /ContainerName/){
				$iGotHeader = 1;
				$headerline=$line;
				$headerline =~ s/~//g;
				
			}
		}else{
			#@work = split("\\|");
			@work=split("~\\|~",$line);
			if($#work >= 1){
				my $lot = $work[0];
				$lot =~ s/\s+$//;
				$line =~ s/~//g;
				if($lot =~ /^\s*$/){
					WARN("lot undefined in line: ".$line);
				}else{
					my($sourcelot,$lotowner,$lotclass) = GetMetaByLot($lot);
					if(defined($missingLot{$lot})){
						if(defined($erroutput{$curname_sbx})){
						}else{
							$erroutput{$curname_sbx} = $headerline."SOURCE_LOT|LOT_OWNER\n";
						}
						$erroutput{$curname_sbx} .= $line.formatSourceLot($sourcelot, $lot)."|".FormatField($lotowner)."\n";
						$num_sbx++;
						if ( $num_sbx >= 100 )
						{
							$num_sbx = 0;
							$fileix_sbx++;
						}
					}else{
						if(defined($output{$curname})){
						}else{
							$output{$curname} = $headerline."SOURCE_LOT|LOT_OWNER\n";
						}
						$output{$curname} .= $line.formatSourceLot($sourcelot, $lot)."|".FormatField($lotowner)."\n";
						$num++;
						if ( $num >= 100 )
						{
							$num = 0;
							$fileix++;
						}
					}
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
			forkdir => $hOptions{FORK},
			basename => ($fn),
			ext => $ext,
			gzipIFF => 'Y',
		}
		);
		
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



