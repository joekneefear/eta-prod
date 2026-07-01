package PDF::Parser::AOS_JUNO_CSV;

use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use Data::Dumper;
use Time::localtime;
use File::stat;
use Time::Piece;

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
	my $line = "";
	my $header = new_onheaderLong;
	my $model = new_model ({header => $header});

	my $wafer = $model->find('wafers',{number => 0});
	unless (defined $wafer){
		$wafer = new_wafer( { number => 0 } );
		$model->add('wafers',$wafer);
	}

	my $fab = "XFAB";
	my $testfloor = "AOS";
	my $testfacility = "AOS";
	my $report = "";
	my $lotid = "";
	my $sourcelot = "";
	my $system = "";
	my $product = "";
	my $productcode = "";
	my $testertype = "";
	my $nodename = "";
	my $area = "Final Test";
	my $processingstep = "";
	my $retestcode = "";
	my $recipe = "";
	my $dataflag = 0;
	my @testnumber;
	my @testname;
	my @lolim;
	my @hilim;
	my @unit;
	my @bias1;
	my @bias2;
	my @bias3;
	my %swbincnt = {};
	my %hwbincnt = {};
	my @origlolim;
	my @orighilim;

	#get step from filename
	my $fname = basename $infile;
	my @arr = split /\_|\./, $fname;
	foreach my $e (@arr) {
		$e = uc $e;
		if ($e eq "FT"){
			$processingstep = "FT";
		}
		elsif ($e eq "QC"){
			$processingstep = "QC";
		}	
	}
	$header->PROCESSING_STEP($processingstep);
	
	#get file modification time
	my $lastmodifiedtime = localtime( stat($infile)->mtime )->strftime("%Y/%m/%d %H:%M:%S");
	$header->START_TIME($lastmodifiedtime);
	$header->END_TIME($lastmodifiedtime);

	#assign defaults
	$header->FAB($fab);
        $header->TEST_FACILITY($testfacility);
        $header->TEST_FLOOR($testfloor);
        $header->AREA($area);

	open CSV, $infile or die "can't open $infile\n";
	while($line=<CSV>){
		chomp($line);
		my @row = split /\,/, $line;

		if ($row[0] =~ /^JUNO Test System/) {
			my @item = split/\s/, $row[0];
			$testertype = trim($item[3]);
			$header->TESTER_TYPE($testertype);
		}
		elsif ($row[0] =~ /^Device$/i){
			$product = trim($row[2]);	
			$header->PRODUCT($product);
			$header->ALTERNATE_PRODUCT($product);
		}
		elsif ($row[0] =~ /^Lot$/i){
			my @item = split/\_/,$row[2];
			$lotid = trim($item[0]);
			$item[$#item] = trim($item[$#item]);
			$retestcode = trim($item[$#item]) if ($item[$#item] =~ m/^P\d+|^Q\d+|^R\d+/ig);
			#$lotid = trim($row[2]);
			$header->LOT($lotid);
			$sourcelot = $lotid;
			$sourcelot =~ s/\..*+$//g;
			$header->SOURCE_LOT($sourcelot.".S");
			$header->TEST_MODE($retestcode);	

			#load wafer without .xxx charactes
			$wafer->name($sourcelot."_".sprintf("%02d",$wafer->number));
		}
		elsif ($row[0] =~ /^Comment$/i){
			$nodename = trim($row[2]);
			$header->MEASURING_EQUIPMENT($nodename);
		}
		elsif ($row[0] =~ /^TestFileName$/i){
			$recipe = uc(trim($row[2]));
			$header->RECIPE($recipe)
		}
		elsif ($row[0] =~ /^Item Name$/i){
			@testname = splice(@row,2);
			# this row/line ends with comma which causes to add blank testname
			# Example: Item Name,,1 SELPIN,2 CONT,3 OPEN,4 SHORT,5 IDSS1,6 IGSS1,7 IGSSR1,8 VTH,9 VTH2,10 BVGSO,11 BVGSOR,12 VFSD,13 IDSS1,14 IDSS2,15 IDSS3,16 BVDSX,17 BVDSX,18 BVDSX,19 BVDSS,20 BVDSS2,21 IDSS4,22 IGSS2,23 IGSSR2,24 POST SHORT,
			my $dump = pop(@testname) if ($testname[$#testname] == "");
		}
		elsif ($row[0] =~ /^Bias1$/i){
			@bias1 = splice(@row,2);
                }
		elsif ($row[0] =~ /^Bias2$/i){
			@bias2 = splice(@row,2);
                }
		elsif ($row[0] =~ /^Bias3$/i){
			@bias3 = splice(@row,2);
                }
		elsif ($row[0] =~ /^Min Limit$/i){
			@origlolim = splice(@row,2);
                }
		elsif ($row[0] =~ /^Max Limit$/i){
			@orighilim = splice(@row,2);
                }
		elsif ($row[0] =~ /^Serial/i && $row[1] =~ /^Bin/i) {
			$dataflag = 1;
                }
		#elsif ($row[0] =~ /^\d{1,}$/ && $dataflag == 1) {
		elsif ($row[0] =~ /^\d{1,}$/g && $row[1] =~ /^\d{1,}$/g && $dataflag == 1) {
			my $serial = shift(@row);
			my $bin = shift(@row);
			#my $dump1 = shift(@row); 
			# this row/line ends with comma which causes to add extra blank results
			# Example: 1,1,0.000E+000,2.100E-002,4.184E+000,4.184E+000,0.000E+000,4.190E-006,4.320E-006,4.727E+000,4.291E+000,2.508E+001,2.515E+001,1.559E+000,0.000E+000,0.000E+000,5.000E-007,8.487E+002,8.489E+002,8.488E+002,8.474E+002,8.481E+002,4.000E-007,4.300E-006,4.380E-006,4.182E+000,

			#store bin counts
                        $swbincnt{$bin}++;
			$hwbincnt{$bin}++;

			my $die = new_die( { partid => $serial } );
			$die->partid($serial);
			$die->ecid($serial);
			$die->site("1");
			$die->touchdown_num("-1");
			$die->bindesc("SWBin_".sprintf("%03d",$bin));
			$wafer->add('dies',$die);

			#SWBIN
			my $swbin = $wafer->find('sbins',{ number => $bin});
			unless (defined $swbin){
				$swbin = new_bin;
				$swbin->number($bin);
				$swbin->name("SWBin_".sprintf("%03d",$bin));
				$swbin->count($swbincnt{$bin});
				if ($bin == 1) {
					$swbin->PF("P");
				}
				else {
					$swbin->PF("F");
				}
				$wafer->add('sbins',$swbin);
			}
			$swbin->count($swbincnt{$bin});
			$die->soft_bin($bin);

			#HWBIN
			my $hwbin = $wafer->find('hbins',{ number => $bin});
			unless (defined $hwbin){
				$hwbin = new_bin;
				$hwbin->number($bin);
				$hwbin->name("HWBin_".sprintf("%03d",$bin));
				$hwbin->count($hwbincnt{$bin});
				if ($bin == 1) {
					$hwbin->PF("P");
				}
				else {
					$hwbin->PF("F");
				}
				$wafer->add('hbins',$hwbin);
			}
			$hwbin->count($hwbincnt{$bin});
			$die->hard_bin($bin);	

			#store readings
			for (my $i=0; $i <= $#testname; $i++) {
				$die->add('result', repNA($row[$i]));
			}	
		}
	}
	close CSV;

	#enrich testname
	my @enrichedtestname;
	for (my $i=0; $i <= $#testname; $i++){
		$testname[$i] = trim($testname[$i]);

		#exract test number from test name
		my @item = split/\s/, $testname[$i];
		$item[0] = trim($item[0]);
		if ($item[0] =~ /^\d+$/g) {
			push(@testnumber, $item[0]);
		}
		else {
			push(@testnumber,"N/A");
		}

		$testname[$i] =~ s/^\d+\s//g;
                $bias1[$i] = repDashNA(trim($bias1[$i]));
                $bias2[$i] = repDashNA(trim($bias2[$i]));
		$bias3[$i] = repDashNA(trim($bias3[$i]));

                my $str = "";

                $str = "${testname[$i]}_${bias1[$i]}_${bias2[$i]}_${bias3[$i]}";
                #$str = "T${testnumber[$i]}:${testname[$i]}_${bias1[$i]}_${bias2[$i]}_${bias3[$i]}";
                $str =~ s/N\/A//g;
                $str =~ s/__$//g;
		$str =~ s/__/_/g;
                $str =~ s/_$//g;
                #print "$str\n";	
                push (@enrichedtestname, $str);

	}

	#check limits
	for (my $i=0; $i <= $#orighilim; $i++){
		#extract unit
		my $lolim_unit = extract_alpha($origlolim[$i]);
		my $hilim_unit = extract_alpha($orighilim[$i]);
			
		#remove strings in limits
		$origlolim[$i] =~ s/\D+$//g;
		$orighilim[$i] =~ s/\D+$//g;
		#convert limit to base unit
		$origlolim[$i] = convertToBaseUnit($lolim_unit, $origlolim[$i]);
		$orighilim[$i] = convertToBaseUnit($hilim_unit, $orighilim[$i]);

		if ($orighilim[$i] ne "" && $origlolim[$i] ne "") {
			#if ($lolim_unit eq "nA" && $hilim_unit eq "uA") {
			#	$origlolim[$i] = normalize_nA_to_uA($origlolim[$i]);				
			#}
		
			if ($orighilim[$i] < $origlolim[$i]) {
				push (@lolim, $orighilim[$i]);
			}
			else {
				push (@lolim, $origlolim[$i]);
			}

			if ($origlolim[$i] > $orighilim[$i]){
				push (@hilim, $origlolim[$i]);
                	}
                	else {
				push (@hilim, $orighilim[$i]);
                	}
		}
		else {
			push (@lolim, $origlolim[$i]);
			push (@hilim, $orighilim[$i]);	
		}	

	}

	#store tests
	for (my $i=0; $i <= $#enrichedtestname; $i++){
		#remove strings in limits
		#$lolim[$i] =~ s/\D+$//g;
		#$hilim[$i] =~ s/\D+$//g;	
		
		my $test = new_test;
                $test->number($testnumber[$i]);
                $test->name($enrichedtestname[$i]);
                $test->LSL(repDashNA($lolim[$i]));
                $test->HSL(repDashNA($hilim[$i]));
                $model->add('tests',$test);
	}
	
	return $model;
}

sub repDashNA {
    my $data = trim(shift);
    if ( ( $data eq '' ) or ( !defined($data) or $data =~ /null|undef/i) or ( $data eq '-' ) ) {
        return 'N/A';
    }
    else {
        return $data;
    }
}

sub extract_alpha {
    my $input = shift;
    $input =~ s/[^a-zA-Z]//g;  # Remove non-alphabetic characters
    return $input;
}

sub normalize_nA_to_uA {
	my $input = shift;
	my $multiplier = .001;
	my $limit = $input * $multiplier; 	
	return $limit;
}

sub convertToBaseUnit {
	my $unit = shift;
	my $limit = shift;
	my $converted_limit = "";
	my $multiplier = 1;

	if (!defined $unit || $unit eq "PF" || $unit =~ /^(P\/F|MHO|A|Pct|Percent|P\_F|GNG|GAIN|amps|volts|ang|microns)$/i || $unit eq "") {
		#do nothing
	}
	elsif ($unit =~ /^a/) {
		$multiplier = 1e-18;	
	}
	elsif ($unit =~ /^f/) {
		$multiplier = 1e-15;
	}
	elsif ($unit =~ /^p/) {
		$multiplier = 1e-12;
	}
	elsif ($unit =~ /^n/) {
		$multiplier = 1e-9;
	}
	elsif ($unit =~ /^u/) {
		$multiplier = 1e-6;
	}
	elsif ($unit =~ /^m/) {
		$multiplier = 1e-3;
	}
	elsif ($unit =~ /^K/i) {
		$multiplier = 1e3;
	}
	elsif ($unit =~ /^M/ && $unit !~ /Micron/i && $unit !~ /MHO/i) {
		$multiplier = 1e6;
	}
	elsif ($unit =~ /^G/ && $unit !~ /GNG/i && $unit !~ /GRAV/i) {
		$multiplier = 1e9;
	}
	elsif ($unit =~ /^T/) {
    		$multiplier = 1e12;
    	}
    	elsif ($unit =~ /^P/) {
    		$multiplier = 1e15;
    	}

	#only convert when there is unit
	if ( $unit ne "") {
		$limit = $limit * $multiplier;
	}

	return $limit;
}

1;
