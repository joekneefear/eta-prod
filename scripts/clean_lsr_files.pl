#!/usr/bin/env perl_db
# 2016-Dec-09 Eric      : create
# 2016-Dec-15 Eric	: parse lot for cp,sz,pm site. change server to prod
# 2018-Feb-08 Eric	: move +X days old spd files to NotProcessed.
#
# Function: Move 7+ day old LSR file to NotProcessed folder and log to pp_log 

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use File::Basename;
use File::Copy;
use IO::File;
use PPLOG::PPLogger;
use DBIx::Simple;

my $env      = "";
my $age      = "";
my @tmt_dirs = ();

my $result = GetOptions ("env=s" => \$env,
                         "age=i" => \$age,
			 );

my @tmp_dirs = `find /data -maxdepth 1 -type d -iname "*tmt"`;

if ($age eq "" || $env eq "") {
	die "Usage: fcs_cust_tmt.pl -env=[ALL|utac_th_ft_tmt|gtk_tw_ft_tmt] -age=<days old>"."\n";
}
elsif ($env =~ /sort/) {
	die "Not a valid FT TMT site: $env"."\n";
}
elsif ($env eq "ALL"){
	@tmt_dirs = @tmp_dirs;
}
elsif (grep /$env/, @tmp_dirs) {
	push @tmt_dirs, "/data/".$env;
}

my $user      = "exn_admin";
my $pass      = "exn_admin";
#my $tns       = "dbi:Oracle:host=oruxymsora01d;port=1521;sid=YMS01DEV";
my $tns       = "dbi:Oracle:host=oruxymsora01p;port=1521;sid=YMS01PRD";
my $db        = DBIx::Simple->connect($tns,$user,$pass) or die DBIx::Simple->error;
my $datex     = &getdatetime();
my $err_code  = "E1012";
my $pro_code  = 1;
my $lsrmsg    = "No matching SPD file available.";
my $spdmsg    = "No matching LSR file available.";
my $out_dir   = "NotProcessed";
my $time_zone = "America/New_York";

foreach my $edir (@tmt_dirs) {
	$edir = trim($edir);
	my @lsr_files = `find $edir/LSR_SPD -maxdepth 1 -type f -iname \"*.LSR*\" -mtime +$age`;
	my @spd_files = `find $edir/LSR_SPD/ReworkFiles -maxdepth 1 -type f -iname \"*.SPD*\" -mtime +$age`;	

#=pod
        foreach my $lsr (@lsr_files) {
                $lsr = trim($lsr);
		my $site = "";
		my $fenv = "";
		my $status;
		my $fn = basename $lsr;
		my $fdir = dirname $lsr;
		my $err_file = "$fdir/NotProcessed/$fn.err";
		#print "$lsr\n";
		if ($env eq "ALL" ) {
			my @item = split /\//, $fdir;
			$site = uc(substr($item[2],0,2));
			$fenv = $item[2];
		}
		else {
			$site = uc(substr($env,0,2));
			$fenv = $env;
		}

		#Adjust time zone
		unless (grep { $_ eq $site } qw/ME MT SL/ ){
		       $time_zone = "Asia/Hong_Kong";
		}

		#extract lot from file.
		my $lot = readLSR($lsr, $fenv);
		
		my $sql = qq/insert into refdb.pp_log
                (LOT,WAFER_NUM,ENVIRONMENT,PROCESS_DATETIME,
                PROCESS_CODE,FILE_NAME,OUTPUT_DIRECTORY,LOG_MESSAGE,
                INSERT_ID,MAP_ID,ERROR_CODE,PROGRAM_CLASS,SITE,
                PROCESS_DATETIME_ADJUST,LIMIT_FILE_NAME,PROGRAM_NAME,EXTENSION,MD5,PATH)
                values
                ('$lot','','$fenv',TO_DATE('$datex','yyyy\/mm\/dd hh24:mi:ss'),
                '$pro_code','$fn','$out_dir','$lsrmsg','','',
                '$err_code','','$site',
                FROM_TZ(CAST(TO_DATE('$datex','yyyy\/mm\/dd hh24:mi:ss') AS TIMESTAMP),'America\/New_York')AT TIME ZONE '$time_zone',
                '','','','','')
                /;
		
		#log to log to refdb.pp_log
		$db->query($sql);	
		
		#move file to NotProcessed
		move ($lsr, "${fdir}/NotProcessed/${fn}");
		$status = (-e "${fdir}/NotProcessed/${fn}") ? "Successful" : "Failed";

		#create err file
		if ($status eq "Successful") {
			open ERR, ">$err_file" if ! -e $err_file ;
				print ERR "1\t1\n";
				print ERR "1\t$err_code\tE\t0\t0\t$lsrmsg\n";
			close ERR;
		}

        }

#=cut

	foreach my $spd (@spd_files) {
                $spd = trim($spd);
                my $site = "";
                my $fenv = "";
                my $status;
                my $fn = basename $spd;
                my $fdir = dirname $spd;
		$fdir = dirname $fdir;
                my $err_file = "$fdir/NotProcessed/$fn.err";
                #print "$spd $fdir\n";
                if ($env eq "ALL" ) {
                        my @item = split /\//, $fdir;
                        $site = uc(substr($item[2],0,2));
                        $fenv = $item[2];
                }
                else {
                        $site = uc(substr($env,0,2));
                        $fenv = $env;
                }

                #Adjust time zone
                unless (grep { $_ eq $site } qw/ME MT SL/ ){
                       $time_zone = "Asia/Hong_Kong";
                }

		#extract lot from file.
                my $lot = readSPD($spd, $fenv);

		my $sql = qq/insert into refdb.pp_log
                (LOT,WAFER_NUM,ENVIRONMENT,PROCESS_DATETIME,
                PROCESS_CODE,FILE_NAME,OUTPUT_DIRECTORY,LOG_MESSAGE,
                INSERT_ID,MAP_ID,ERROR_CODE,PROGRAM_CLASS,SITE,
                PROCESS_DATETIME_ADJUST,LIMIT_FILE_NAME,PROGRAM_NAME,EXTENSION,MD5,PATH)
                values
                ('$lot','','$fenv',TO_DATE('$datex','yyyy\/mm\/dd hh24:mi:ss'),
                '$pro_code','$fn','$out_dir','$spdmsg','','',
                '$err_code','','$site',
                FROM_TZ(CAST(TO_DATE('$datex','yyyy\/mm\/dd hh24:mi:ss') AS TIMESTAMP),'America\/New_York')AT TIME ZONE '$time_zone',
                '','','','','')
                /;

                #log to log to refdb.pp_log
                $db->query($sql);

                #move file to NotProcessed
                move ($spd, "${fdir}/NotProcessed/${fn}");
                $status = (-e "${fdir}/NotProcessed/${fn}") ? "Successful" : "Failed";

		#create err file
                if ($status eq "Successful") {
                        open ERR, ">$err_file" if ! -e $err_file ;
                                print ERR "1\t1\n";
                                print ERR "1\t$err_code\tE\t0\t0\t$spdmsg\n";
                        close ERR;
                }
	}	

}

$db->disconnect;

exit;

sub getdatetime{
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
        my $datex = sprintf("%04d/%02d/%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
        return $datex;
}

sub readLSR {
        my $infile = shift;
        my $env = shift;
        my $fn = basename $infile;
	my @item = split /\_/, $fn;
	my $final_lot = "";

        if ($env =~ /hana/) {
                my $lot = $item[0];
                if (length($lot) > 10) {
                        $lot = substr($lot, 0 , 10);
                }
		$final_lot = $lot;
        }
        elsif ($env =~ /atec|cpft|szft|pmft/) {
                my $LSRFileHandle = IO::File->new($infile) or die "Can't open file - $infile : $!";
                my $line = "";
                while($line = $LSRFileHandle->getline) {
                        $line =~ s/\cM|\"//g;
                        chomp($line);
                        if ( $line =~ /Lot\s+id\s+\:(.*?)\s+?Total\s+Fail\s+:/i || $line =~ /Lot\s+id\s+\:(.*?)\_?Total\s+Fail\s+:/i){
                                my $tmp_lot  = uc(trim($1));
				if ($env =~ /atec/i) {
                                	my ($lot, $dmp1, $dmp2) = split /\_/, $tmp_lot;
                                	$lot  = substr($lot,0,10);
					$final_lot = $lot;
				}
				elsif($env =~ /cpft/i) {
					my ($lot, $dmp1, $dmp2) = split /\_/, $tmp_lot;
					$final_lot = $lot;	
				}
				elsif($env =~ /szft/i) {
					my ($lot, $dmp1, $dmp2) = split /\_/, $tmp_lot;
					$lot =~ s/AO/A0/ig;	
					if (($lot =~ /^A0|^X\d+[A-Z]$/i) && (length($lot) > 10)) {
						$lot = substr($lot,0,10) if $lot =~ /^A0|^X\d+[A-Z]$/i && length($lot) > 10;
					}
					$final_lot = $lot;
				}
				elsif($env =~ /pmft/i) {
					my ($lot, $dmp1, $dmp2) = split /\_/, $tmp_lot;
                                        $lot  = substr($lot,0,10) if $lot =~ /^H|^P/i;	
					$final_lot = $lot;
				}
                        }
                }
        }
        elsif ($env =~ /gtk/) {
		$final_lot = uc( $item[0] );
        }
        elsif ($env =~ /gem/) {
                foreach my $element (@item) {
                        trim($element);
                        if($element =~ /^GM\d{1,7}[a-zA-Z]{1}/) {
				$final_lot = uc( $element );
                        }
                }
        }
        elsif ($env =~ /utac/) {
		$final_lot = uc( $item[1] );
        }

return $final_lot;
}

sub readSPD {
	my $infile = shift;
        my $env = shift;
        my $fn = basename $infile;
        my @item = split /\_/, $fn;
        my $final_lot = "";

	if ($env =~ /hana/) {
		my $lot = $item[0];
                if (length($lot) > 10) {
                        $lot = substr($lot, 0 , 10);
                }
		$final_lot = $lot;
	}
	elsif ($env =~ /atec|cpft|szft|pmft/) {
		my $SPDFileHandle = IO::File->new($infile) or die "Can't open file - $infile : $!";
		while (my $line = $SPDFileHandle->getline) {
			if ($line =~ /^Lot/i) {
				my @arr1 = split /\,/, $line;
				my @arr2 = split /\_/, $arr1[1];
				$final_lot = $arr2[0];
			}
			last if $final_lot ne "";
		}	
	}
	elsif ($env =~ /gtk/) {
		$final_lot = uc( $item[0] );
	}
	elsif ($env =~ /gem/) {
		foreach my $element (@item) {
                        trim($element);
                        if($element =~ /^GM\d{1,7}[a-zA-Z]{1}/) {
				$final_lot = uc( $element );
                        }
                }		
	}
	elsif ($env =~ /utac/) {
		$final_lot = uc( $item[1] );
	}

	return $final_lot;
}
