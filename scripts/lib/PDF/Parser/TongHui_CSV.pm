# 18-May-2017 Eric	: new
package PDF::Parser::TongHui_CSV;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use v5.10;
use POSIX;
use Time::Local;
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
	my $mm = "";
	my $dd = "";
	my $yy = "";
	my $hh = "";
	my $min = "";
	my $sec = 00; 
	my $ins_start_time = 0;
	my $ins_end_time   = 0;
	my $tst_start_time = POSIX::LONG_MAX;
	my $tst_end_time   = 0;
	my %lim = {};
	my @lim_lbl = ();
	my @con_lbl = ();
	my @con_val = ();
	my @die_lim = ();
	my @tname = ();
	my %bincnt = {};
	my @pf_val = ();
	my $p_cnt = 0;
	my $f_cnt = 0;

	my $header = new_headerLong;
        my $model = new_model (
	{
        	header => $header,
                misc   => {},
                dataSource => 'TH'
        }
        );

	my $wafer = new_wafer;
	   $model->add('wafers', $wafer );
	
	my $fname = basename $infile;
	my @item  = split /\_/, $fname;
	$header->LOT($item[0]);
	
	open FH, $infile or die "can't open $infile\n";
        while(my $line=<FH>){
		#print "$line\n";
		chomp $line;
		$line =~ s/\"|\cM//g;
		my @ln_arr = split /\,/, $line;
		if ($line =~ /limit/i) {
			@lim_lbl = splice @ln_arr, 3;
			@con_lbl = splice @ln_arr, 1, 2;
		}
		elsif($line =~ /^die/i) {
			@die_lim = splice @ln_arr, 3;
			@con_val = splice @ln_arr, 1, 2;
			for (my $i=0; $i<=$#lim_lbl; $i++) {
				$lim{$ln_arr[0]}{$lim_lbl[$i]} = $die_lim[$i];
			}

		}
		elsif($line =~ /Setup File/i) {
			my ($prog, $rev) = split /\_/, $ln_arr[1];
			$rev = substr $rev, -1;
			#convert char to number
			$rev = ord(uc($rev))-64 if $rev=~/[A-Z]/i;
			#convert rev to integer
			$rev = int($rev) if $rev ne "";

			#$header->PROGRAM($prog);
			$header->PROGRAM(trim($ln_arr[1]));
			$header->REVISION($rev);
		}
		elsif ($line =~ /Instrument NO/i) {
			$header->EQUIP1_ID("TH2829X"." ".$ln_arr[1]);
		}
		elsif ($line =~ /^SN/i) {
			@tname = splice @ln_arr, 1, -2;
		}
		elsif ($line =~ /^\d/) {
			($yy, $mm, $dd, $hh, $min) = split /[\/\s\:]+/, $ln_arr[$#ln_arr];
			$ins_start_time = timegm($sec, $min, $hh, $dd, $mm-1, $yy);
			$ins_end_time = timegm($sec, $min, $hh, $dd, $mm-1, $yy);
	
			if ($tst_start_time >= $ins_start_time)   # GET EARLIEST TIME
                        {
                                $tst_start_time = $ins_start_time;
				$header->START_TIME($ln_arr[$#ln_arr].":".$sec)
                        }
			if ($ins_end_time >= $tst_end_time)     #GET LATEST TIME
                        {
                                $tst_end_time = $ins_end_time;
				$header->END_TIME($ln_arr[$#ln_arr].":".$sec)					
                        }
			
			my @res = splice @ln_arr, 1, -2;
			my $die = new_die;
			$die->partid($ln_arr[0]);
			$die->site($ln_arr[0]);
			# soft bin info was assumed since info available
			$die->soft_bin($ln_arr[$#ln_arr-1] =~ /pass/i ? '1':'2');

			foreach my $r (@res) {
				$die->add('result', $r);
			}
			$wafer->add('dies', $die);

			#count passing/failing die
			if ($line =~ /pass/i) {
				$p_cnt++;
			}
			else {
				$f_cnt++;
			}
			push @pf_val , $ln_arr[$#ln_arr-1];
		}

	}
	close(FH);
	
	#store limits
	my $tnum = 0;
	my $limit = new_limit;
	$limit->conditionNames([qw/testCond /]);
	foreach my $test (@tname) {
		$tnum++;
		my ($a,$b,$c) = split /\(|\)/, $test;
		my $test = new_test;
		$test->name($a."_".$b);
		$test->number($tnum);
		$test->units(trim($c));

		foreach my $die (sort {$a<=>$b} keys %lim) {
			foreach my $lbl (sort {$a<=>$b} keys %{$lim{$die}}) {
				my ($d,$e,$f) = split /\s/, $lbl;
				if ($test->name =~ /$die/i && $a =~ /$d/i ){
					if ($lbl =~ /low/i) {
						$test->LSL($lim{$die}{$lbl});
					}
					if ($lbl =~ /high/i) {
						$test->HSL($lim{$die}{$lbl});
					}
				}
			}
		}
		$test->add('conditions',$con_lbl[0]."=".$con_val[0]." ".$con_lbl[1]."=".$con_val[1]);
		$model->add('tests', $test);
		$limit->add('tests', $test);
	}
	
	foreach my $val (@pf_val) {
		#bin numbers were assumed because no info available.
		if ($val =~ /pass/i) {
			my $bin = $wafer->find('bins',{number=>'1'});
			unless (defined $bin) {
				my $bin = new_bin;
				$bin->number('1');
				$bin->name("BIN".$bin->number);
				$bin->PF('P');
				$bin->count($p_cnt);
				$wafer->add('bins',$bin);
			}
		}
		else {
			my $bin = $wafer->find('bins',{number=>'2'});
                        unless (defined $bin) {
                                my $bin = new_bin;
                                $bin->number('2');
                                $bin->name("BIN".$bin->number);
                                $bin->PF('F');
                                $bin->count($f_cnt);
                                $wafer->add('bins',$bin);
                        }			
		}
	}
	
return $model;
}

1;
