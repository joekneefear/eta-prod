# 15-Jul-2016 Eric	: create
#
package PDF::Parser::TESEC_CSV_SORT;
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
	my $self   = shift;
	my $infile = shift;
	my $lotid  = "";
	my $tpname = "";
	my $tprev  = "";
	my $product = "";
	my %td	   = ();
	my %tp	   = ();
	my @tnum   = ();
	my @tname  = ();
	my @tunit  = ();
	my @hilim  = ();
	my @lolim  = ();
	my @condition = ();
	my %sbin   = ();
	my %sb_cnt = ();
	my @readings = ();
	my $session_flg = 0;

	open FH, $infile or die "can't open $infile\n";
	while (<FH>) {
		s/\cM\n/\n/g;
		my @fields = split /\,/;
		next if( $fields[0] =~ /^\s*$/ ); 
			
		if( $fields[0] =~ /^Item/i ){
			$session_flg = 1;
			my $tst_num = 1;
			foreach( @fields[7..$#fields] ) {
				next if( /^\s*$/ );
				my $name = trim($_);
				push @tnum, $tst_num;
				push @tname, $name; 
				$tst_num++;
			}
		}
		elsif ( $fields[0] =~ /^Unit/i ){
			foreach( @fields[7..$#fields] ) {
				next if( /^\s*$/ );
				my $unit = trim($_);
				push @tunit, $unit;
			}
		}
		elsif( $fields[0] =~ /^USL/i ) {
			foreach( @fields[7..$#fields] ){
				next if( /^\s*$/ );
				my $usl = trim($_);
				   $usl =~ s/^\-$//;
				push @hilim, $usl;
			}	
		}
		elsif( $fields[0] =~ /^LSL/i ) {
			foreach( @fields[7..$#fields] )
			{
				next if( /^\s*$/ );
				my $lsl = trim($_);
				   $lsl =~ s/^\-$//;
				push @lolim, $lsl;
			}
		}
		elsif( $fields[0] =~ /^COND/i ) {
			foreach( @fields[7..$#fields] ) {
				next if( /^\s*$/ );
				my $cond = trim($_);
				   $cond =~ s/^\-$//;
				push @condition, $cond;
			}
		}
		elsif( $fields[0] =~ /^Data/i ) {
			my $product_testprogram = trim($fields[1]);
			my ($product, $testprogram) = split /\s+/, $product_testprogram, 2;
			   $product = trim($product);
			   $testprogram =~ s/\(|\)//g;
			my ($tpname, $tprev) = split /\s+/, $testprogram, 2;
			   $tpname = trim($tpname);
			   $tprev = trim($tprev);
			my $lotid = trim($fields[2]);
    			   $lotid =~ s/\-//g;
			my $wafno = int(trim($fields[4]));
			my $partno = int(trim($fields[5]));
			my $binno = trim($fields[6]);
			   $binno =~ s/[a-z]//ig;
			my $pf = trim($fields[6]);
			   $pf =~ s/\d+//g;

			$sb_cnt{$lotid}{$wafno}{$binno}++;

			foreach( @fields[7..$#fields] ) {
				next if( /^\s*$|^\s*F\s*$|^\s*\*\s*$|^\s*\?\s*$|^\s*\-\s*$/ );;
				next if( /^\s*\-+\s*$/ );
				my $value = trim($_);
				push @readings, $value;
			}
	
			# store data into hash
			$td{$lotid}{$wafno}{$partno} = {
				PROD   => $product,
				TPNAME => $tpname,
				TPREV  => $tprev,
				SBIN   => $binno,
				PF     => $pf,
				RESULT => [@readings],				
			};
			
			# store tp info into hash
			if ( $session_flg == 1) {
				$tp{$lotid} = {
					TNUM  => [@tnum],
					TNAME => [@tname],
					UNIT  => [@tunit],
					HSL   => [@hilim],
					LSL   => [@lolim],
					COND  => [@condition]
				};
			}

			#store bin info into hash
			$sbin{$lotid}{$wafno}{$binno} = {
				CNT  => $sb_cnt{$lotid}{$wafno}{$binno},
				PF   => $pf
			};
			
			# clear data for next set
			$product = "";
			$tpname = "";
			$tprev = "";
			$binno = "";
			$pf = "";
			@readings = ();

			@tnum  = ();
			@tname = ();
			@tunit = ();
			@hilim = ();
			@lolim = ();
			@condition = ();
			# reset session
			$session_flg = 0;
		}
	}	
	close (FH);			
	return \%td, \%tp, \%sbin;

}

sub remove_unwanted_chars
{
        my $value = shift;
        $value =~ s/[^a-zA-Z0-9\-\_\.]/\-/gi;
        $value =~ s/\-{2,}/\-/g;
        $value =~ s/^\-+|\-+$//g;             ### REMOVE LEADING/TRAILING "-"
        return($value);
}

sub clean_string
{
        my $str = shift;
           $str =~ s/^\s+|\s+$//g;
	   $str =~ s/\,//g;	
           $str =~ s/\s+/_/g;
        return($str);
}

1;

