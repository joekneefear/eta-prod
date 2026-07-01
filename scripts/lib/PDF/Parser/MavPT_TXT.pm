# 19-Sep-2016 Eric	: new
# 21-Apr-2017 jgarcia : modify to not call dpExit if zero parts tested. just return the model and assign
#                       the error message to $model->misc
package PDF::Parser::MavPT_TXT;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use Time::Local;
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
	my %month = ("JANUARY"=>1,"FEBRUARY"=>2,"MARCH"=>3,"APRIL"=>4,"MAY"=>5,"JUNE"=>6,
		     "JULY"=>07,"AUGUST"=>8,"SEPTEMBER"=>9,"OCTOBER"=>10,"NOVEMBER"=>11,"DECEMBER"=>12);
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

	my $hb_flg  = "N";
	my $sw_flg  = "N";
	my $start_t = "";
	my $end_t   = "";
	my $s_hr    = "";
	my $s_mn    = "";
	my $s_ss    = "";
	my $e_hr    = "";
	my $e_mn    = "";
	my $e_ss    = "";

	open FH, $infile or die "can't open $infile\n";
        while(my $line=<FH>){
		$line =~ s/\cM\n/\n/g;
		chomp($line);
		next if $line =~ /^\.+/;
		next if $line =~ /Bin Name|Total\s+\d+.+/i;
		next if $line =~ /\s+\-+/;
		my @item = split /\:/, $line;

		if ( $line =~ /SUMMARY OF INTERFACE BIN/i ) {
			$hb_flg = "Y";
			$sw_flg = "N";
		}
		elsif ( $line =~ /SUMMARY OF SOFTWARE BIN/i ) {
			$sw_flg = "Y";
			$hb_flg = "N";
		}
		elsif ( $line =~ /TEST PROGRAM/i ) {
			$item[1] = trim($item[1]);
			my @arr = split /\_/, $item[1];
			$header->PROGRAM($arr[0]);
			$header->REVISION($arr[1]);
		}
		elsif ( $line =~ /START DATE/i ) {
			my @arr = split /\,/, $item[1];
			$arr[0] = trim($arr[0]);
			$arr[1] = trim($arr[1]);
			my $dd = substr $arr[0], 0, 2;
			my $yy = substr $arr[0], -4;
			my $mon = uc($arr[0]);
			$mon =~ s/\d//g;
			$mon = trim($mon);	
			$mon = $month{$mon};
			$s_hr  = $item[1];
			$s_mn  = $item[2];
			$s_ss  = $item[3];
			$start_t = timegm($item[3],$item[2],$arr[1],$dd,$mon-1,$yy);
			#$header->START_TIME($start_t);
		}
		elsif ( $line =~ /STOP DATE/i ) {
			my @arr = split /\,/, $item[1];
			$arr[0] = trim($arr[0]);
                        $arr[1] = trim($arr[1]);
                        my $dd = substr $arr[0], 0, 2;
                        my $yy = substr $arr[0], -4;
                        my $mon = uc($arr[0]);
                        $mon =~ s/\d//g;
			$mon = trim($mon);
			$mon = $month{$mon};
			$e_ss = $item[1];
			$e_mn = $item[2];
			$e_ss = $item[3];
			my $add_sec = "";

			#my $add_sec = $s_mn - $e_mn;	#get diff between second values
			#   $add_sec =~ s/^\-//;       	#remove negative result
			if ($s_ss != $e_ss) {
				$add_sec = $s_ss - $e_ss;
			}
			elsif ($s_mn != $e_mn) {
				$add_sec = $s_mn - $e_mn;
			}
			elsif ($s_hr != $e_hr) {
				$add_sec = $s_hr - $e_hr;
			}
		 	$start_t = $start_t + $add_sec;	#add result to start time	
			$end_t = timegm($item[3],$item[2],$arr[1],$dd,$mon-1,$yy);
			$header->START_TIME($start_t);
			$header->END_TIME($end_t);
		}
		elsif ( $line =~ /TESTER ID/i ) {
			$header->EQUIP1_ID(trim($item[1]));
		}
		elsif ( $line =~ /HANDLER ID/ ) {
			$header->EQUIP5_ID(trim($item[1]));
		}
		elsif ( $line =~ /CUSTOMER LOT ID/i ) {
			$header->LOT(trim($item[1]));
		}
		elsif ( $line =~ /EMPLOYEE ID/i ) {
			$header->OPERATOR(trim($item[1]));
		}
		elsif ( $line =~ /TESTED :/i ) {
			$item[0] = trim($item[0]);
			$item[1] = trim($item[1]);
			if ($item[1] == 0) {
				$model->{misc} = "Zero part/s tested (".$item[1].")";
				return $model;
				#dpExit (1,"Zero part/s tested (".$item[1].")");
			}
		}
		elsif ( $hb_flg eq "Y" && $sw_flg eq "N" ) {
			my @item = split /\s+/, $line;
			my $hbin = new_bin;
			$hbin->number($item[2]);
			$hbin->name($item[1]);
			$hbin->count($item[5]);
			$hbin->PF($item[2] == 1 ? 'P' : 'F');
			$wafer->add('hbins', $hbin);
		}
		elsif ( $sw_flg eq "Y" && $hb_flg eq "N" ) {
			my @item = split /\s+/, $line;
			my $sbin = new_bin;
                        $sbin->number($item[2]);
                        $sbin->name($item[1]);
                        $sbin->count($item[5]);
                        $sbin->PF($item[2]== 1 ? 'P' : 'F');
                        $wafer->add('bins', $sbin);		
		}
		
	}
	close(FH);

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
