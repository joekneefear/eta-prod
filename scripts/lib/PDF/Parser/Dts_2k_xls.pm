# 24-May-2019 Eric	: Initial release
#
package PDF::Parser::Dts_2k_xls;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use Spreadsheet::ParseExcel;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;


our $VERSION = "1.0";
our $mat_type = "";

my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

my %hosb = ();
my %hohb = ();
my $systemname = "";
my $station = "";


sub readFile {
	my $self   = shift;
	my $infile = shift;
	my $dataflag = 0;	
	my $header = new_headerLong;
	my $model = new_model ( 
		{
			header => $header,
            		misc   => {},
            		dataSource => 'JUNO'
		}
	);

	my $wafer = $model->find('wafers',{number => 0});
	unless (defined $wafer){
		$wafer = new_wafer( { number => 0 } );
		$model->add('wafers',$wafer);
	}

	my @testname 	= ();
	my @hilim_unit 	= ();
	my @hilim 	= ();
	my @lolim_unit 	= ();
	my @lolim 	= ();
	my @bias 	= ();
	my @readings 	= ();
	my $sortbin_flg = 0;
	my %bin_cnt	= {};

	my $parser = Spreadsheet::ParseExcel->new();
        my $workbook = $parser->parse($infile);

        if (!defined $workbook)
        {
                die $parser->error(), ".\n";
        }

        my $worksheet = $workbook->worksheet(0);
        my ($row_min, $row_max) = $worksheet->row_range();
        my ($col_min, $col_max) = $worksheet->col_range();

	for my $row ($row_min .. $row_max)
        {
                my @dummy = ();
		for my $col ($col_min .. $col_max)
                {
			my $cell = $worksheet->get_cell($row, $col);
                        next unless $cell;
                        my $cell_val = $cell->value();
                        $dummy[$col] = &clean_string($cell_val);

                }	 		
		if (($dummy[0] =~ /^\d{1,}$/ && $dataflag == 1) || ($dummy[0] =~ /^[P|F]\d{1,}$/ && $dataflag == 1)) {
			#print "@dummy\n";
			my $partid = shift(@dummy);
			   $partid =~ s/\D//ig;
			   $partid = trim($partid);

			my $bin = shift(@dummy);
			   $bin =~ s/\D//ig;  
			   $bin = trim($bin);
			   $bin_cnt{$bin}++;
			
			my $die = $wafer->find('dies',{ partid => $partid});
			unless (defined $die){
                        	$die = new_die( { partid => $partid } );
                                $die->partid( $partid );
                                $wafer->add('dies',$die);
                        }
			
			my $sbin = $wafer->find('bins',{number=>$bin});
			unless (defined $sbin){
                                $sbin = new_bin;
                                $wafer->add('bins',$sbin);
                        }
			$sbin->number($bin);
			$sbin->name("BIN_".$bin);
			$sbin->PF($bin == 1 ? "P" : "F");
			$sbin->count($bin_cnt{$bin});
                        $die->soft_bin($bin);			

			for (my $i=0; $i <= $#testname; $i++) {
				$dummy[$i] =~ s/Over|undef//i; 
				$dummy[$i] =~ s/^\D+|\D+$//ig;
				$dummy[$i] =~ trim($dummy[$i]);
				$die->add( 'result', repNA($dummy[$i]) )
			}
		}
		elsif ($dummy[0] =~ /Date/i) {
			my @item1 = split /\_/, $dummy[2];
			my @item2 = split /\_/, $dummy[5];
			$header->START_TIME($item1[1]." ".$item1[2]);
			$header->END_TIME($item2[1]." ".$item2[2]);
		}
		elsif ($dummy[0] =~ /Version/i) {
			$dummy[2] = trim($dummy[2]);
			$header->REVISION($dummy[2]);
		}
		elsif ($dummy[0] =~ /Station/i) {
			$station = trim($dummy[2]);
		}
		elsif ($dummy[0] =~ /DataFileName/i) {
			#print "@dummy\n";
		}
		elsif ($dummy[0] =~ /SystemName/i) {
			$systemname = trim($dummy[2]);
			$header->EQUIP1_ID($systemname." ".$station);
		}
		elsif ($dummy[0] =~ /DeviceName/i) {
			$dummy[2] = trim($dummy[2]);
			$header->PRODUCT($dummy[2]);
		}
		elsif ($dummy[0] =~ /LotName/i) {
			$dummy[2] = trim($dummy[2]);			
			$header->LOT($dummy[2]);
		}
		elsif ($dummy[0] =~ /OperatorName/i) {
			$dummy[2] = trim($dummy[2]);
			$header->OPERATOR($dummy[2]);
		}
		elsif ($dummy[0] =~ /TestFileName/i) {
			my @item = split /\\/, $dummy[2];
			$item[$#item] =~ s/\..+$//i;
			$header->PROGRAM($item[$#item]);
		} 	
		elsif ($dummy[1] =~ /Item\s+Name|Item\_Name/i || ($dummy[0] =~ /Item\s+Name|Item\_Name/i && $dummy[1] eq "") ){
			@testname = splice(@dummy,2);
			if ($testname[$#testname] =~ /^SortBin$/) {
				my $last_one = pop @testname;
				$sortbin_flg = 1;
			}

		}
		elsif ($dummy[0] =~ /Bias[123]/i){
			my @item = splice(@dummy,2);

			for (my $i=0; $i <= $#item; $i++) {
				if ($bias[$i] eq "" && ($item[$i] ne "" ||  $item[$i] eq "undef"))
				{
					$bias[$i] = $item[$i];
				}
				elsif ($bias[$i] ne "" && ($item[$i] ne "" || $item[$i] eq "undef"))
				{
					$bias[$i] .= "\_$item[$i]";
				}
			}
		}
		elsif ($dummy[0] =~ /Min\_Limit|Min\sLimit/i){
			my @arry = splice(@dummy,2);
			if ($sortbin_flg == 1 ){
				my $last_one = pop @arry;
			}

			foreach my $lim (@arry) {
				my $unit = $lim;
				$lim =~ s/\D+$//ig;
				$unit =~ s/[\d+|\-|\.]//ig;
				push @lolim, $lim;
				push @lolim_unit, $unit;
			}

		}
		elsif ($dummy[0] =~ /Max\_Limit|Min\sLimit/i) {
			my @arry = splice(@dummy,2);
			if ($sortbin_flg == 1 ){
				my $last_one = pop @arry;
			}

			foreach my $lim (@arry) {
                                my $unit = $lim;
                                $lim =~ s/\D+$//ig;
                                $unit =~ s/[\d+|\-|\.]//ig;
                                push @hilim, $lim;
                                push @hilim_unit, $unit;
                        }

		}
		elsif ($dummy[0] =~ /Serial/i && $dummy[1] =~ /Bin/i) {
			$dataflag = 1;
		}
		
	}

	my $limit = new_limit;
	for (my $i=0; $i <= $#testname; $i++) {
		if ($lolim_unit[$i] ne "" && $hilim_unit[$i] ne "") {
			if ($lolim_unit[$i] != $hilim_unit[$i]) {
				dpExit(1,"Error! Inconsistent unit. High Limit VS Low Limit.");
			}
		}

		my $test = new_test;
		$test->number($i+1);
		$test->name($testname[$i]);
		$test->units(($lolim_unit[$i] eq "") ? $hilim_unit[$i] : $lolim_unit[$i]);
		$test->LSL($lolim[$i]);
		$test->HSL($hilim[$i]);
		$test->add('conditions',$bias[$i]);
		$model->add('tests', $test);
		$limit->add('tests', $test);
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

