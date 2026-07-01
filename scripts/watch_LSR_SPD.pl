#! /usr/bin/env perl_db
# 2015-Aug-10 jgarcia initial

use strict;
use warnings;
use diagnostics;
use IO::File;
use Getopt::Long;
use File::Copy qw(move);
#use File::Path qw(make_path);
use File::Basename;
use v5.10;
use Cwd qw();

my $sourceFolder  = "";
my $destinationFolder = "";
my $site = "";
my $reworkFolder = "";
my $reworkExistFlag = "";
my $SPD = "";
my $badLSRFolder = "";
my $currentDir;
my $workingDir = Cwd::abs_path();
my $lastRunFile = "lastRun.txt";

my (%hOptions) = ();
 
unless (GetOptions(\%hOptions,  "SOURCE=s", "SITE=s", "BADLSR=s", "FORPROCESS=s", "REWORKFOLDER=s"))
{
    print "syntax\n";
    print "\tscript -source=<source folder> \t";
    print "\tscript -forprocess=<destination folder> \t";
    print "\tscript -reworkfolder=<rework files location> \n";
    print "\tscript -site=<site> \n";
    exit 1;
}


if(-f $workingDir.$lastRunFile && (time - (stat($lastRunFile))[9]) < 180) {
	print"\n\tPlease try to run after 3 mins!!!\n\n";
	exit 0;
}

 $sourceFolder = $hOptions{SOURCE};
 $site = $hOptions{SITE};
 $badLSRFolder = $hOptions{BADLSR};
 $destinationFolder = $hOptions{FORPROCESS};
 $reworkFolder = $hOptions{REWORKFOLDER};


    opendir( DIR, $sourceFolder ) || die "can't opendir $sourceFolder: $!";
    foreach my $filename ( readdir(DIR) ) {
 			my $newFilename = "";
 		  my $spdFilename = "";
 		  #print "$filename";
    		  if($filename =~ /\.LSR$/i) {
		        #$filename = basename($filename);
		        
		        my $result = &checkTotalValueLSR($sourceFolder.$filename);
		        #print"RESULT>>>$result\n";
		        if($result != 1) {
		        	move($sourceFolder.$filename, $badLSRFolder.$filename);
		        } else {
		        	
		        	if($site eq "pmft_tmt") {
		        			$newFilename = &pmft_tmtRename($sourceFolder.$filename);	
		        			$spdFilename = $newFilename;
		        			$spdFilename =~ s/\.LSR/\.SPD/g;
		        			move($sourceFolder.$filename, $destinationFolder.$newFilename);
		        			if(-e $reworkFolder.$spdFilename) { 
		        				move($reworkFolder.$spdFilename, $destinationFolder.$spdFilename );
		        			}  
		        	} elsif($site eq "gem_cn_ft" || $site eq "atec_ph_ft") {
		        		  $newFilename = &gem_cn_ft_tmtRename($sourceFolder.$filename);	
		        			$spdFilename = $newFilename;
		        			$spdFilename =~ s/\.LSR/\.SPD/g;
		        			move($sourceFolder.$filename, $destinationFolder.$newFilename);
		        			if(-e $reworkFolder.$spdFilename) {
		        				move($reworkFolder.$spdFilename, $destinationFolder.$spdFilename );
		        			}  
		        		
		        	} else {
				        	$newFilename = $filename;
				        	$newFilename =~ s/\.lsr/\.LSR/;
				        	move($sourceFolder.$filename, $destinationFolder.$newFilename);
				        	$spdFilename = $newFilename;
				        	$spdFilename =~ s/\.LSR/\.SPD/g;
				        	if(-e $reworkFolder.$spdFilename) {
				        			move($reworkFolder.$spdFilename, $destinationFolder.$spdFilename );
				        	}
		        	}  
			        	
		        }
		        &updateLastRunFile;

		      } elsif ($filename =~ /\.SPD$/i) {
		      	$filename = basename($filename);
		      	#my $newFilename = "";
		      	
		      	if($site eq "pmft_tmt") {
		      		
		        		$newFilename = &pmft_tmtRename($sourceFolder.$filename);	
		        		#move($sourceFolder.$filename, $destinatioFolder.$newFilename); 
		        } elsif ($site eq "gem_cn_ft" || $site eq "atec_ph_ft") {
		        		$newFilename = &gem_cn_ft_tmtRename($sourceFolder.$filename);
		        } else {
		        	$newFilename = $filename;
		        	$newFilename =~ s/\.spd/\.SPD/;
		        } 
		        move($sourceFolder.$filename, $destinationFolder.$newFilename); 
#		        my $LSR = $newFilename;
#		        $LSR =~ s/\.SPD/\.LSR/;
#		        if(not -e sourceFolder.$LSR) {
#		        	move($sourceFolder.$newFilename, $reworkFolder.$newFilename);
#		        }
		      	&updateLastRunFile;
					}
		}
    closedir(DIR);



sub checkInRework {
	
	my $filename = shift;
	my $existFlag = 0;
	my $SPD = "";
	
	if ($filename =~ /\.LSR$/) {
		$SPD = $filename;
		$SPD =~ s/\.LSR/\.SPD/;
	}
	
	if (-f $reworkFolder.$SPD) {
		move($reworkFolder.$SPD, $destinationFolder.$SPD );
	}
		
}

sub checkTotalValueLSR {
	
	my $file = shift;
	
	#my $LSRFileHandle = IO::File->new($file);
	my $LSRLineFlag = 0;
	my $line = "";
	my $totalFlag = 0;
	open FH_LSR, $file or die "Could not open $file: $!";
	while ($line=<FH_LSR>) {
	#while($line = $LSRFileHandle->getline) {
		
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
	close(FH_LSR);
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
  	$fname =~ s/(\.[\d]+)$//g;
  }
	my $newFilename = "${fname}${ext}";
	return($newFilename);
}

sub updateLastRunFile
{		
	open LR, '>', $lastRunFile or die "Could not open file '$workingDir.$lastRunFile' $!"; ;
	print LR "1";
	close(LR);
}
