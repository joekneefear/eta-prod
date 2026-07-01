# 27-Nov-2018 Eric	: new
# 31-Feb-2019 Eric	: added sub routine formatDateTime
# 31-Feb-2019 Eric	: reflect NA for empty result	
package PDF::Parser::CZ;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

sub readFile {
        my $self = shift;
        my $infile = shift;
	my %td = ();
	my %tp = ();
	my %res;
	my @testname = ();
	my @testnum = ();
	my @testcond = ();
	my @testunit = ();
	my @hilim = ();
	my @lolim = ();
	my $lolim_flg = 0;
	my $hilim_flg = 0;
	my $data_flg = 0;
	my $lcnt = 0;

	open CSV, $infile or die "can't open $infile\n";
        while(my $line=<CSV>){
		$lcnt++;
		#print "$line\n";
		chomp $line;
		$line       =~ s/\"|\cM//g;
		
		my @item = split /\,/, $line;

		if ($item[13] =~ /USL/i && $lcnt == 4) {
			 my @arr = splice (@item, 14);

			 foreach my $usl (@arr) {
				$usl =~ s/\D{1,}$//ig;
				$usl =~ s/\s+$//;
				push @hilim, $usl;
			 }

		}
		elsif ($item[13] =~ /LSL/i && $lcnt == 5) {
			my @arr = splice (@item, 14);
			
			foreach my $lsl (@arr) {
				$lsl =~ s/\D{1,}$//ig;
				$lsl =~ s/\s+$//;
				push @lolim, $lsl;
			}

		}
		elsif ($item[13] =~ /TEST NUM/i && $lcnt == 6) {
			@testnum = splice (@item, 14);
		}
		elsif ($item[13] =~ /UNITS/i && $lcnt == 7){
			@testunit = splice (@item, 14);

		}
		elsif ($item[0] =~ /Row/i) {
			$data_flg = 1;
			my @arr = splice (@item, 14);
			foreach my $param (@arr) {
				my ($tname,$tcond) = split /_(.*+)/, $param, 2;
				#push @testname, $tname;
				push @testname, $param;
				push @testcond, $tcond;
			}

		}
		elsif ($item[0] =~ /\d+/ && $data_flg == 1) {
			my @tmp_arr = splice (@item, 14);
			my @readings = ();

			for (my $j=0; $j<=$#testname; $j++) {
				push @readings, $tmp_arr[$j];
			}

			$item[6] =~ m/(.+)\_(.+)\.(.+)/;   #ex. NTW080N120SC1_1.TST
			my $prg = $1;
			my $rev = $2;
			my $ext = $3;

	                my $stime = formatDateTime($item[8]);
	                my $etime = formatDateTime($item[9]);

	                if ($stime eq "" && $etime ne "") {
				$stime = $etime;
        	        }
                	elsif ($etime eq "" && $stime ne "") {
				$etime = $stime;
                	}

			$td{$item[11]}{$item[12]} = {
				FAMILY => $item[1],
				TECHNOLOGY => $item[2],
				PROCESS => $item[3],
				MASKSET => $item[4],
				PRODUCT => $item[5],
				PROGRAM => $prg,
				REVISION => $rev,
				LOT_TYP => $item[7],
				START_T => $stime,
				END_T => $etime,
				SOURCE_LOT => $item[10],
				RESULT => [@readings]
			};

			$tp{$item[11]} = {
				TEST_NAM => [@testname],
				TEST_NUM => [@testnum],
				TEST_COND => [@testcond],
				HILIM => [@hilim],
				LOLIM => [@lolim],
				TEST_UNIT => [@testunit]
			};
		}
	}
	close(CSV);
	

return \%td, \%tp;

}

sub formatDateTime {
	my $DateTime = shift;
	my $yr = "";
	my $mm = "";
	my $dd = "";
	my $hh = "";
	my $mn = "";
	my $ss = "";
	
	if ($DateTime =~ /^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})/){  #2018-11-06 12:00:00
		$yr = $1;
		$mm = $2;
		$dd = $3;
		$hh = $4;
		$mn = $5;
		$ss = $6;
		
	}
	elsif ($DateTime =~ /^(\d{4})\/(\d{1,2})\/(\d{1,2})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})/){ #2018/11/06 12:00:00
		$yr = $1;
                $mm = $2;
                $dd = $3;
                $hh = $4;
                $mn = $5;
                $ss = $6;	
	}
	elsif ($DateTime =~ /^(\d{1,2})-(\d{1,2})-(\d{4})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})/){ #11-6-2018  12:00:00
		$yr = $3;
                $mm = $1;
                $dd = $2;
                $hh = $4;
                $mn = $5;
                $ss = $6;
	}
	elsif ($DateTime =~ /^(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})/){ #11/6/2018  12:00:00
                $yr = $3;
                $mm = $1;
                $dd = $2;
                $hh = $4;
                $mn = $5;
                $ss = $6;
        }
	elsif ($DateTime =~ /^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{1,2})/) { #2018-11-06 12:00
		$yr = $1;
             	$mm = $2;
                $dd = $3;
                $hh = $4;
                $mn = $5;
		$ss = ($ss ne "") ? $ss : "00";
	}
	elsif ($DateTime =~ /^(\d{4})\/(\d{1,2})\/(\d{1,2})\s+(\d{1,2}):(\d{1,2})/) { #2018/11/06 12:00
                $yr = $1;
                $mm = $2;
                $dd = $3;
                $hh = $4;
                $mn = $5;
		$ss = 00;
        }
	elsif ($DateTime =~ /^(\d{1,2})-(\d{1,2})-(\d{4})\s+(\d{1,2}):(\d{1,2})/){ #11-6-2018  12:00
                $yr = $3;
                $mm = $1;
                $dd = $2;
                $hh = $4;
                $mn = $5;
                $ss = 00;
        }
	elsif ($DateTime =~ /^(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{1,2})/){ #11/6/2018  12:00
                $yr = $3;
                $mm = $1;
                $dd = $2;
                $hh = $4;
                $mn = $5;
                $ss = 00;
	}

	if ($DateTime ne "") {
		$DateTime = "${yr}/${mm}/${dd} ${hh}:${mn}:${ss}";
	}

	return $DateTime;
}

1;
