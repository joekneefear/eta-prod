#!/usr/bin/env perl_db
##! /usr/bin/perl
# 2015/Aug/12 jgarcia initial

# Rename LSR or SPD files if necessary.
# Move the files to LSR_SPD directory
# Move LSR file with zero value total to NotProcessed directory.
# Check for SPD pair in ReworkFiles directory in every LSR processed, and move the SPD to LSR_SPD directory
# 2015-11-3 jgarcia - updated to fix bugs.

use strict;
use warnings;
use diagnostics;
use FindBin qw/$Bin/;
use lib "$FindBin::Bin/..";
use IO::File;
use Getopt::Long;
use File::Copy qw(move);
use File::Basename;
#use v5.10;
use Cwd 'abs_path';
use Config::Tiny;
use PDF::Log;
use PDF::DpLoad;

my $lastRunFile = "$Bin/lastRun.txt";
my $iniFile = "$Bin/ftTMTdataLoading.ini";
my $site = "";
my $sourceFolder = "";
my $destinationFolder = "";
my $reworkFolder = "";
my $config = Config::Tiny->read($iniFile);
my $logfile = $ENV{DPLOG}."/".basename($0).".log";

PDF::Log->init($logfile);

if (-f $lastRunFile && (time - (stat($lastRunFile))[9]) < 180) {
	INFO("Please re-run after 3 mins.");
	dpExit(0);
}

# foreach my $Section (keys %$config) {
# print "[$Section]";
# foreach my $Key (keys %{$config->{$Section}}) {
#  print "$Key = $config->{$Section}->{$Key}";
# }
#}
INFO("Update $lastRunFile");
&updateLastRunFile();
INFO("Process each site LSR/SPD");
&processLSRSPD();

dpExit(0);

##############################################

sub processLSRSPD {
	
	foreach my $section (keys %$config) {
		$site = $config->{$section}->{site};
		my $source = $config->{$section}->{sourceDir};
		my $dest = $config->{$section}->{forProcessDir};
		my $rework= $config->{$section}->{reworkDir};
		
		&processFile($site, $source, $dest, $rework);
	}
}

sub processFile() {
	
	$site = shift;
	$sourceFolder = shift;
	$destinationFolder = shift;
	$reworkFolder = shift;
	
	opendir( DIR, $sourceFolder ) || die "can't opendir $sourceFolder: $!";
  foreach my $filename ( readdir(DIR) ) {
 		my $newFilename = "";
 		my $spdFilename = "";
 		  
    if($filename =~ /\.LSR$/i) {
    	$filename = basename($filename);
			my $result = &checkTotalValueLSR($sourceFolder."/".$filename);
		  if($result != 1) {
		  	move($sourceFolder."/".$filename, $sourceFolder."/NotProcessed/".$filename);
		  } else {
		  	if($site eq "pmft_tmt") {
		    	$newFilename = &pmft_tmtRename($sourceFolder."/".$filename);	
		      $spdFilename = $newFilename;
		      $spdFilename =~ s/\.LSR/\.SPD/g;
		      move($sourceFolder."/".$filename, $destinationFolder."/".$newFilename);
		      if(-e $reworkFolder."/".$spdFilename) { 
		      	move($reworkFolder."/".$spdFilename, $destinationFolder."/".$spdFilename );
		      }
		    } elsif($site eq "gem_cn_ft_tmt" || $site eq "atec_ph_ft_tmt" || $site eq "hana_th_ft_tmt") {
		    	$newFilename = &gem_cn_ft_tmtRename($sourceFolder."/".$filename);	
		      $spdFilename = $newFilename;
		      $spdFilename =~ s/\.LSR/\.SPD/g;
		      move($sourceFolder."/".$filename, $destinationFolder."/".$newFilename);
		      if(-e $reworkFolder."/".$spdFilename) {
		      	move($reworkFolder."/".$spdFilename, $destinationFolder."/".$spdFilename );
		      }  
		        		
		    } else {
					$newFilename = $filename;
				  $newFilename =~ s/\.lsr/\.LSR/;
				  move($sourceFolder."/".$filename, $destinationFolder."/".$newFilename);
				  $spdFilename = $newFilename;
				  $spdFilename =~ s/\.LSR/\.SPD/g;
				  if(-e $reworkFolder."/".$spdFilename) {
				  	move($reworkFolder."/".$spdFilename, $destinationFolder."/".$spdFilename );
				  }
		    }  
			        	
			}
		  &updateLastRunFile;

		} elsif ($filename =~ /\.SPD$/i) {
			$filename = basename($filename);
		  if($site eq "pmft_tmt") {
		  	$newFilename = &pmft_tmtRename($sourceFolder."/".$filename);	
		  } elsif ($site eq "gem_cn_ft_tmt" || $site eq "atec_ph_ft_tmt" || $site eq "hana_th_ft_tmt") {
		  	$newFilename = &gem_cn_ft_tmtRename($sourceFolder."/".$filename);
		  } else {
		  	$newFilename = $filename;
		    $newFilename =~ s/\.spd/\.SPD/;
		  } 
		  move($sourceFolder."/".$filename, $destinationFolder."/".$newFilename); 
#		        my $LSR = $newFilename;
#		        $LSR =~ s/\.SPD/\.LSR/;
#		        if(not -e sourceFolder.$LSR) {
#		        	move($sourceFolder.$newFilename, $reworkFolder.$newFilename);
#		        }
		  &updateLastRunFile;
			}
		}
    closedir(DIR);
}


sub checkInRework {
	
	my $filename = shift;
	my $existFlag = 0;
	my $SPD = "";
	
	if ($filename =~ /\.LSR$/) {
		$SPD = $filename;
		$SPD =~ s/\.LSR/\.SPD/;
	}
	
	if (-e $reworkFolder."/".$SPD) {
		move($reworkFolder."/".$SPD, $destinationFolder."/".$SPD );
	}
		
}

sub checkTotalValueLSR {
	
	my $file = shift;
	
	my $LSRFileHandle = IO::File->new($file);
	my $LSRLineFlag = 0;
	my $line = "";
	my $totalFlag = 0;
	#open FH_LSR, $file or die "Could not open $file: $!";
	#while ($line=<FH_LSR>) {
	while($line = $LSRFileHandle->getline) {
		
		$line =~ s/\cM|\"//g;
		chomp($line);
		
		if ( $line =~ /^Test Program\s*: .+ Total\s+: (.+)/ ) {
			 
				my $total = ($1);
				
				if($total != 0 || $total > 0) {
					$totalFlag = 1;
				}
				last;
		}
	
		
	}
	return($totalFlag);
	
}

sub pmft_tmtRename {
	my $file = shift;
	$file = basename($file);
	my ($fname, $ext) = split /(\.[^.]+)$/, $file;
	$ext = uc($ext);
	if($fname =~ /(\_[\d]+)$/) {
	#$fname =~ s/(\_[\d]+)$//g;
	 $fname = substr($fname, 0, -2);
	}
	my $newFilename = "${fname}${ext}";
	return($newFilename)
}

sub gem_cn_ft_tmtRename {
	my $file = shift;
	$file = basename($file);
	my ($fname, $ext) = split /(\.[^.]+)$/, $file;
	$ext = uc($ext);
	if($fname =~ /(\.[\d]+)$/) {
  	$fname =~ s/(\.[\d]+)//g;
  }
	my $newFilename = "${fname}${ext}";
	return($newFilename);
}

sub updateLastRunFile {		
	open LR, '>', $lastRunFile or die "Could not open file '$lastRunFile' $!"; ;
	print LR "1";
	close(LR);
}






