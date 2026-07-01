# 09-Aug-2016 Eric	: new
package PDF::Parser::MavPT;
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
	my $header = new_headerLong;
        my $model = new_model (
	{
        	header => $header,
                misc   => {},
                dataSource => 'MAVPT2'
        }
        );
	my $wafer = new_wafer;
	$model->add('wafers', $wafer );
	my $date;
	my $time;
	my %tp = {};
	my %td = {};
	my %bin_cnt = {};
	my %bin = {};
	my $data = {};
	my $die_cnt = 0;
	
	open FH, $infile or die "can't open $infile\n";
        while(my $line=<FH>){
		chomp($line);
		my (@dummy) = split /\,/, $line;
		#print "$line\n";
		if ($line =~ /^LOT(.+)/i){
			my $lotid = trim($1);
			$header->LOT($lotid);
		}
		elsif ($line =~ /^DATE(.+)/i){
			$date = trim($1);
			my ($dd,$mo,$yr) = split /\-/, $date;
			$date = $yr."/".$mo."/".$dd;
		}
		elsif ($line =~ /^TIME(.+)/i){
			$time = trim($1);
			$header->START_TIME($date." ".$time);
			$header->END_TIME($date." ".$time);
			#print"$header->{START_TIME}\n";
		}
		elsif ($line =~ /^OPERATOR(.+)/i){
			my $operator = trim($1);
			$header->OPERATOR($operator);
		}
		elsif ($line =~ /^TEST SYS(.+)/i){
			my $equip = trim($1);
			$header->EQUIP1_ID($equip);
		}
		elsif ($line =~ /^PROGRAM(.+)/i){
			my $program = trim($1);
			my ($prg, $rev) = split /\_/, $program;
			$header->PROGRAM($prg);
			$header->REVISION($rev);
		}
		elsif ($line =~ /^LOADBOARD(.+)/i){
			my $load_board = trim($1);
			$header->EQUIP4_ID($load_board);
		}
		elsif ($line =~ /^HANDLER(.+)/i){
			my $handler = trim($1);
			$header->EQUIP5_ID($handler);
		}
		elsif ($line =~ /^TEMPERATURE(.+)/i){
			my $temp = trim($1);
		}
		elsif ($line =~ /^Site\s\d/i) {
			$die_cnt++;
			my $site = trim($dummy[0]);
			   $site =~ s/\D//ig;
			   $site = trim($site);
			my $die  = trim($dummy[1]);
			my $tnum = trim($dummy[2]);
			my $dpin = trim($dummy[3]);
			my $tblk = trim($dummy[4]);
			my $param = trim($dummy[5]);
			my $tnam = $tblk." - ".$param." - ".$dpin;
			my $lsl  = trim($dummy[6]);
			my $val  = trim($dummy[7]);
			my $hsl  = trim($dummy[8]);
			my $unit = trim($dummy[9]);
			my $pf   = trim($dummy[10]); 
			   $pf   = $pf =~ /PASS/i ? 'P' : 'F';
			my $bno = $pf eq 'P' ? 1 : 0;	#create dummy bin number 1=pass 0=fail  

			$bin_cnt{$pf}++;   #count pass/fail
			
			#store test program info	
			$tp{$tnum}{$param}{$dpin} = {
				NUM => $tnum,
				NAME => $tnam,
				UNIT => $unit,
				LSL => $lsl,
				HSL => $hsl,
			};
			
			#store readings
			$td{$site}{$die}{$tnum}{$tnam} = {
				VAL => $val,
				BIN => $bno,
				#PF => $pf,
			};
			
			#bins	
                        my $bin = $wafer->find('bins', {number=>$bno});
                        unless (defined $bin) {
                               $bin = new_bin;
                               $wafer->add('bins',$bin);
                        }
                        $bin->number($bno);
                        $bin->name('BIN_'.$bno);
                        $bin->count($bin_cnt{$pf});
                        $bin->PF($bno == 1 ? 'P' : 'F');			
			
		}
	}
	close(FH);

	#store limits into model
	foreach my $tnum ( sort {$a<=>$b} keys %tp) {
		next if !defined $tp{$tnum};
		foreach my $param ( sort {$a<=>$b} keys %{$tp{$tnum}} ){
			foreach my $dpin ( sort {$a<=>$b} keys %{$tp{$tnum}{$param}} ){
				my $test = new_test;
                		$test->number( $tp{$tnum}{$param}{$dpin}{NUM});
                		$test->name( repNA($tp{$tnum}{$param}{$dpin}{NAME}) );
                		$test->units( repNA($tp{$tnum}{$param}{$dpin}{UNIT}) );
                		$test->LSL( repNA($tp{$tnum}{$param}{$dpin}{LSL}) );
                		$test->HSL( repNA($tp{$tnum}{$param}{$dpin}{HSL}) );
				$model->add( 'tests', $test );	
			}
		}
	}	
	#store readings into model
	foreach my $snum ( sort {$a<=>$b} keys %td) {
		next if ! defined $td{$snum};
		foreach my $dnum ( sort {$a<=>$b} keys %{$td{$snum}}) {
			my $pf_flg = 0;
                	my $die = new_die;
			$die->site($snum);
                	$die->partid($dnum);
			foreach my $test ( @{ $model->tests } ) {
				$pf_flg++ if $td{$snum}{$dnum}{$test->number}{$test->name}{BIN} == 0; #flag "F" if any test fails
                		$die->add('result',repNA($td{$snum}{$dnum}{$test->number}{$test->name}{VAL}));
			}
			$die->soft_bin($pf_flg > 0 ? 0 : 1);
			$die->hard_bin($pf_flg > 0 ? 0 : 1);
                	$wafer->add('dies',$die);
        	}
	}

return $model;
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
