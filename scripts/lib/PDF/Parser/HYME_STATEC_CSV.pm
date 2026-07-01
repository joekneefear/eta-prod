package PDF::Parser::HYME_STATEC_CSV;

use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename fileparse/;
use Data::Dumper;

use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

my $datecomparison = "2025/11/01 00:00:00";

sub readFileFT {
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
	my $testfloor = "HYME";
	my $testfacility = "HYME";
	my $report = "";
	my $lotid = "";
	my $system = "";
	my $product = "";
	my $reciperevision = "";
	my $testertype = "";
	my $nodename = "";
	my $area = "Final Test";
	my $processingstep = "FT";
	my $alternateproduct = "";
	my $jobname = "";
	my $dataflag = 0;
	my @testnumber;
	my @testname;
	my @lolim;
	my @hilim;
	my @unit;
	my @bias1;
	my @bias2;
	my %swbincnt = {};
	my %hwbincnt = {};
	my @defaultlimitidx;
	my $tmplot1 = "";
	my $tmplot2 = "";
	my $testtime = "";
	my $infocolumnflag = 0;

	#get lotid from filename
	my $fname = basename $infile;
	#($lotid,$product,$reciperevision) = extractMetaFromFilename($infile);
	#$alternateproduct = $product;
	#$header->LOT($lotid);
	#$header->PRODUCT($product);
	#$header->RECIPE_REVISION($reciperevision);
	($tmplot1,$product,$reciperevision) = extractMetaFromFilename($infile);
	$header->FAB($fab);
	$header->TEST_FACILITY($testfacility);
	$header->TEST_FLOOR($testfloor);
	$header->AREA($area);
	$header->PROCESSING_STEP($processingstep);
	#$header->ALTERNATE_PRODUCT($alternateproduct);

	open CSV, $infile or die "can't open $infile\n";
	while($line=<CSV>){
		chomp($line);
		my @row = split /\,/, $line;

		if ($row[0] =~ /System/i){
			my @item = split/\s|\[|\]/, $row[1];
			$testertype = trim($item[0]);
			$nodename = trim($item[2]);
			$nodename =~ s/\[|\]//ig;
			$header->MEASURING_EQUIPMENT($nodename);		
			$header->TESTER_TYPE($testertype);
		}
		elsif ($row[0] =~ /Job_Name/i){
			$jobname = trim($row[1]);
			$header->RECIPE($jobname);			
		}
		elsif ($row[0] =~ /Lot_Id\.|Lot Id\./) {
			$tmplot2 = trim($row[1]);
		}
		elsif ($row[0] =~ /Lot_No\.|Lot No\./) {
			#$lotid = trim($row[1]);
			#$header->LOT($lotid);
			$tmplot1 = trim($row[1]);
		}
		elsif ($row[0] =~ /Report/i){
			$report = trim($row[1]);
			$report = "${report}:00";
			$header->START_TIME($report);
			$header->END_TIME($report);	
		}
		elsif ($row[4] =~ /^Test$/i){
			@testnumber = splice(@row, 5); 
			# this row/line sometimes ends with comma which causes to add blank test number
			# Ex: ,,,,Test,T1,T2,T3,T4,T5,T6,T7,T8,T9,T10,T11,T12,T13,T14,T15,T16,T17,T18,T19,T20,T21,T22,T23,T24,T25,T26,T27,T28,T29,T30,T31,T32,T33,T34,T35,T36,T37,T38,T39,
			# remove last element
			$testnumber[$#testnumber] = trim($testnumber[$#testnumber]);
			my $dump = pop(@testnumber) if ($testnumber[$#testnumber] eq "");
		}
		elsif ($row[4] =~ /^Item$/i){
			@testname = splice(@row, 5);
			# this row/line sometimes ends with comma which causes to add blank test name
			# Ex: ,,,,Item,CONT,IDSS,ISGS,ISGS,VP,SAME,PAT_S,VP,SAME,BVGSO,SAME,BVGSO,SAME,HRDON,PAT,HVFSD,SAME,PAT_S,IDSS,IDSS,IDSS,PAT,BVDSX,SAME,BVDSX,SAME,BVDSX,SAME,HVBDSS,SAME,PAT_S,HVBDSS,SAME,IDSS,PAT,ISGS,PAT,ISGS,PAT,
			# remove last element
			$testname[$#testname] = trim($testname[$#testname]);
			my $dump = pop(@testname) if ($testname[$#testname] eq "");
                }
		elsif ($row[4] =~ /^LL$/i){
			@lolim = splice(@row, 5);
                }
		elsif ($row[4] =~ /^HL$/i){
			@hilim = splice(@row, 5);
                }
		elsif ($row[4] =~ /^Bias1$/i){
			@bias1 = splice(@row, 5);
                }
                elsif ($row[4] =~ /^Bias2$/i){
			@bias2 = splice(@row, 5);
                }
                elsif ($row[4] =~ /^Unit$/i){
			@unit = splice(@row, 5);
                }
                elsif ($row[0] =~ /^No$/i && $row[1] =~ /^Bin/i){
			$dataflag = 1;
                }	
		elsif ($row[0] =~ /^\d{1,}$/ && $dataflag == 1) {
			my $no = shift(@row);
			my $bin = shift(@row);
			my $time = shift(@row);
			my $result = shift(@row);
			my $failitem = shift(@row);

			$no = trim($no);
			$bin = trim($bin);
			$time = trim($time);
			$result = trim($result);
			$failitem = trim($failitem);

			#store bin counts
			$swbincnt{$bin}++;
			$hwbincnt{$bin}++;

			my $die = new_die( { partid => $no } );
			$die->partid($no);
			$die->ecid($no);
			$die->site("1");
			$die->touchdown_num("-1");
			$die->bindesc(repNA($failitem));
			$die->testtime(repNA($time));
			$wafer->add('dies',$die);

			#SWBins
			my $swbin = $wafer->find('sbins',{ number => $bin});
			unless (defined $swbin){
				$swbin = new_bin;
				$swbin->number($bin);
				$swbin->name("SWBin_".sprintf("%03d",$bin));
				$swbin->count($swbincnt{$bin});
				if ($result eq "PASS") {
					$swbin->PF("P");
				}
				else {
					$swbin->PF("F");
				}
				$wafer->add('sbins',$swbin);
			}
			$swbin->count($swbincnt{$bin});
			$die->soft_bin($bin);						

			#HWBins
                        my $hwbin = $wafer->find('hbins',{ number => $bin});
                        unless (defined $hwbin){
                                $hwbin = new_bin;
                                $hwbin->number($bin);
                                $hwbin->name("HWBin_".sprintf("%03d",$bin));
                                $hwbin->count($hwbincnt{$bin});
                                if ($result eq "PASS") {
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
				#Ignore any test with item name SAME or PAT	
				$testname[$i] = trim($testname[$i]);
				if ($testname[$i] =~ /SAME|PAT/ig) {
					next;
				}
				else {
					$die->add('result', repNA($row[$i]));
					# check result and flag when to set defaultlimits
					if ($row[$i] =~ /PASS|FAIL/ig) {
						unless (grep { $_ eq $i } @defaultlimitidx) {
							push @defaultlimitidx, $i;
						}
					}
				}
			}
		}
	}
	close CSV;

	#apply changes after Nov-01-2025
	#while retaining data mapping before the said data
	$testtime = $header->{START_TIME};
	if ($testtime ge $datecomparison) {
		WARN("Test time $testtime is greater than $datecomparison. Newer data mapping will be used.");
		my @item = split /\_/, $jobname;
		$product = substr($item[1],0,-1);
		$product =~ s/\.$//ig;
		$product =~ s/\-$//ig;
		$reciperevision = substr($item[1],-1);
		$alternateproduct = $product;
		$header->LOT($tmplot2);
		$header->SUBCON_LOT_ID($tmplot1);
		$header->PRODUCT($product);
		$header->RECIPE_REVISION($reciperevision);
		$header->ALTERNATE_PRODUCT($alternateproduct);
	}
	else {
		WARN("Test time $testtime is lesser than $datecomparison. Older data mapping will be used.");
		$alternateproduct = $product;
		$header->LOT($tmplot1);
		$header->PRODUCT($product);
		$header->RECIPE_REVISION($reciperevision);
		$header->ALTERNATE_PRODUCT($alternateproduct);
	}

	#enrich testname
	my @enrichedtestname;
	for (my $i=0; $i <= $#testname; $i++){
		$testname[$i] = trim($testname[$i]);
		$testnumber[$i] = trim($testnumber[$i]);
		$bias1[$i] = repDashNA(trim($bias1[$i]));
		$bias2[$i] = repDashNA(trim($bias2[$i]));
		my @b1item = split/\(|\)/, $bias1[$i];
		my @b2item = split/\(|\)/, $bias2[$i];
		my $b1str = "";
		my $b2str = "";

		if ($b1item[1] ne "" && $b1item[2] ne "") {
			 $b1str = "${b1item[1]}=${b1item[2]}";
		}
		if ($b2item[1] ne "" && $b2item[2] ne "") {
                         $b2str = "${b2item[1]}=${b2item[2]}";
                }

		my $str = "";
		
		#$str = "${testnumber[$i]}:${testname[$i]}_${b1str}_${b2str}";
		$str = "${testname[$i]}_${b1str}_${b2str}";
		$str =~ s/N\/A//g;
		$str =~ s/__$//g;
                $str =~ s/_$//g;
		$str =~ s/=$//g;
		push (@enrichedtestname, $str);
		
	}

	for (my $i=0; $i <= $#enrichedtestname; $i++){
		$lolim[$i] = trim($lolim[$i]);
		$hilim[$i] = trim($hilim[$i]);
		$lolim[$i] =~ s/>|<//ig;
		$hilim[$i] =~ s/>|<//ig;
		#Ignore any test with item name SAME or PAT
		if ($enrichedtestname[$i] =~ /SAME|PAT/ig) {
			next;
		}
		else {
			#remove last characters in limits
        	        $lolim[$i] =~ s/\D+$//g;
        	        $hilim[$i] =~ s/\D+$//g;
	
			my $test = new_test;
			$testnumber[$i] =~ s/\D//g;
			$test->number($testnumber[$i]);
			$test->name($enrichedtestname[$i]);
			$test->units(repDashNA($unit[$i]));
			if ((grep { $_ eq $i } @defaultlimitidx) && ($lolim[$i] eq "" && $hilim[$i] eq "")){
				$test->LSL(-.5);
				$test->HSL(+.5);
			}
			else {
				$test->LSL(repDashNA($lolim[$i]));
				$test->HSL(repDashNA($hilim[$i]));
			}
			$model->add('tests',$test);	
		}
	}
	
	return $model;
}

sub readFileRG {
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
        my $testfloor = "HYME";
        my $testfacility = "HYME";
        my $report = "";
        my $lotid = "";
        my $system = "";
        my $product = "";
        my $reciperevision = "";
        my $testertype = "";
        my $nodename = "";
        my $area = "Final Test";
        my $processingstep = "";
	my $alternateproduct = "";
        my $jobname = "";
        my $dataflag = 0;
        my @testnumber;
        my @testname;
        my @lolim;
        my @hilim;
        my @unit;
        my @bias1;
        my @bias2;
        my %swbincnt = {};
	my %hwbincnt = {};
	my $infocolumnflag = 0;
	my @defaultlimitidx;
	my $tmplot1 = "";
	my $tmplot2 = "";
	my $testtime = "";

        #get lotid from filename
        my $fname = basename $infile;
	#($lotid,$product,$reciperevision) = extractMetaFromFilename($infile);
	#$alternateproduct = $product;
        #$header->LOT($lotid);
        #$header->PRODUCT($product);
        #$header->RECIPE_REVISION($reciperevision);
        ($tmplot1,$product,$reciperevision) = extractMetaFromFilename($infile);
        $header->FAB($fab);
        $header->TEST_FACILITY($testfacility);
        $header->TEST_FLOOR($testfloor);
        $header->AREA($area);
	#$header->ALTERNATE_PRODUCT($alternateproduct);

        if ( $fname =~ m/RG_MOS|RG-MOS/i) {
                $processingstep = "RG_MOS";
        }
        elsif ( $fname =~ m/RG_JFET|RG-JFET/i) {
                $processingstep = "RG_JFET";
        }
        $header->PROCESSING_STEP($processingstep);

        open CSV, $infile or die "can't open $infile\n";
        while($line=<CSV>){
                chomp($line);
                my @row = split /\,/, $line;

                if ($row[0] =~ /System/i){
                        my @item = split/\s|\[|\]/, $row[1];
                        $testertype = trim($item[0]);
                        $nodename = trim($item[2]);
                        $nodename =~ s/\[|\]//ig;
                        $header->MEASURING_EQUIPMENT($nodename);
                        $header->TESTER_TYPE($testertype);
                }
                elsif ($row[0] =~ /Job_Name/i){
                        $jobname = trim($row[1]);
                        $header->RECIPE($jobname);
                }	
		elsif ($row[0] =~ /Lot_Id\.|Lot Id\./i) {
			$tmplot2 = trim($row[1]);	
		}
		elsif ($row[0] =~ /Lot_No\.|Lot No\./i) {
			#$lotid = trim($row[1]);
			#$header->LOT($lotid);
			$tmplot1 = trim($row[1]);
		}
		elsif ($row[0] =~ /Report/i){
                        $report = trim($row[1]);
                        $report = "${report}:00";
                        $header->START_TIME($report);
                        $header->END_TIME($report);
                }
                elsif ($row[4] =~ /^Test$/i || $row[5] =~ /^Test$/i){
                        #@testnumber = splice(@row, 5);
			if ($row[4] =~ /^Test$/i) {
				@testnumber = splice(@row, 5);
			}
			elsif ($row[5] =~ /^Test$/i) {
				@testnumber = splice(@row, 6);
			}
			# this row/line sometimes ends with comma which causes to add blank test number
                        # Ex: ,,,,,Test,            T1,            T2,            T3,            T4,
                        # remove last element
                        $testnumber[$#testnumber] = trim($testnumber[$#testnumber]);
			my $dump = pop(@testnumber) if ($testnumber[$#testnumber] eq "");
	
                }
                elsif ($row[4] =~ /^Item$/i || $row[5] =~ /^Item$/i){
                        #@testname = splice(@row, 5);
			if ($row[4] =~ /^Item$/i) {
				@testname = splice(@row, 5);
			}
			elsif ($row[5] =~ /^Item$/i){
				@testname = splice(@row, 6);
			}
			# this row/line sometimes ends with comma which causes to add blank test name
			# Ex:,,,,,Item,          CONT,          OPEN,         SHORT,            RG,
			# remove last element
			$testname[$#testname] = trim($testname[$#testname]);
			my $dump = pop(@testname) if ($testname[$#testname] eq "");		
                }
                elsif ($row[4] =~ /^LL$/i || $row[5] =~ /^LL$/i){
                        #@lolim = splice(@row, 5);
			if ($row[4] =~ /^LL$/i) {
				@lolim = splice(@row, 5);
			}
			elsif ($row[5] =~ /^LL$/i) {
				@lolim = splice(@row, 6);
			}
                }
                elsif ($row[4] =~ /^HL$/i || $row[5] =~ /^HL$/i){
                        #@hilim = splice(@row, 5);
			if ($row[4] =~ /^HL$/i) {
				@hilim = splice(@row, 5);
			}
			elsif ($row[5] =~ /^HL$/i) {
				@hilim = splice(@row, 6);
			}
                }
		elsif ($row[4] =~ /^Bias1$/i || $row[5] =~ /^Bias1$/i){
                        #@bias1 = splice(@row, 5);
			if ($row[4] =~ /^Bias1$/i) {
				@bias1 = splice(@row, 5);
			}
			elsif ($row[5] =~ /^Bias1$/i){
				@bias1 = splice(@row, 6);
			}
                }
                elsif ($row[4] =~ /^Bias2$/i || $row[5] =~ /^Bias2$/i){
                        #@bias2 = splice(@row, 5);
			if ($row[4] =~ /^Bias2$/i){
				@bias2 = splice(@row, 5);
			}
			elsif ($row[5] =~ /^Bias2$/i){
				@bias2 = splice(@row, 6);
			}
                }
                elsif ($row[4] =~ /^Unit$/i || $row[5] =~ /^Unit$/i){
                        #@unit = splice(@row, 5);
			if ($row[4] =~ /^Unit$/i) {
				@unit = splice(@row, 5);
			}
			elsif ($row[5] =~ /^Unit$/i){
				@unit = splice(@row, 6);	
				$infocolumnflag = 1;
			}
			$dataflag = 1;
                }
                elsif ($row[0] =~ /^\d{1,}$|^\s+\d{1,}$/ && $dataflag == 1) {
			my $no = shift(@row);
			my $info = shift(@row) if ($infocolumnflag == 1);
                        my $bin = shift(@row);
                        my $time = shift(@row);
                        my $result = shift(@row);
			my $dump = shift(@row);
			$time =~ s/\D+$//g;
			$bin = trim($bin);
			$info = trim($info);
			$time = trim($time);
			$result = trim($result);

                        #store bin counts
                        $swbincnt{$bin}++;
			$hwbincnt{$bin}++;

                        my $die = new_die( { partid => $no } );
                        $die->partid($no);
                        $die->ecid($no);
                        $die->site("1");
                        $die->touchdown_num("-1");
			$die->bindesc("SWBin_".sprintf("%03d",$bin));
			$die->testtime(repNA($time));
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
				$testname[$i] = trim($testname[$i]);
                                $die->add('result', repNA($row[$i]));
				# check result and flag when to set defaultlimits
				if ($row[$i] =~ /PASS|FAIL/ig) {
					unless (grep { $_ eq $i } @defaultlimitidx) {
						push @defaultlimitidx, $i;
					}
				}
                        }
		}
	}
	close CSV;

	#apply changes after Nov-01-2025
	#while retaining data mapping before the said data
	$testtime = $header->{START_TIME};
	if ($testtime ge $datecomparison) {
		WARN("Test time $testtime is greater than $datecomparison. Newer data mapping will be used.");
		my @item = split /\_/, $jobname;
		$product = substr($item[1],0,-1);
		$product =~ s/\.$//ig;
		$product =~ s/\-$//ig;
		$reciperevision = substr($item[1],-1);
		$alternateproduct = $product;
		$header->LOT($tmplot2);
		$header->SUBCON_LOT_ID($tmplot1);
		$header->PRODUCT($product);
		$header->RECIPE_REVISION($reciperevision);
		$header->ALTERNATE_PRODUCT($alternateproduct);
	}
	else {
		WARN("Test time $testtime is lesser than $datecomparison. Older data mapping will be used.");
		$alternateproduct = $product;
		$header->LOT($tmplot1);
		$header->PRODUCT($product);
		$header->RECIPE_REVISION($reciperevision);
		$header->ALTERNATE_PRODUCT($alternateproduct);
	}

        #enrich testname
        my @enrichedtestname;
        for (my $i=0; $i <= $#testname; $i++){
                $testname[$i] = trim($testname[$i]);
                $testnumber[$i] = trim($testnumber[$i]);
                $bias1[$i] = repDashNA(trim($bias1[$i]));
                $bias2[$i] = repDashNA(trim($bias2[$i]));

                my $str = "";

                #$str = "${testnumber[$i]}:${testname[$i]}_${bias1[$i]}_${bias2[$i]}";
                $str = "${testname[$i]}_${bias1[$i]}_${bias2[$i]}";
                $str =~ s/N\/A//g;
                $str =~ s/__$//g;
                $str =~ s/_$//g;
		$str =~ s/:$//g;
		$str =~ s/^://g;
                push (@enrichedtestname, $str);

        }

        for (my $i=0; $i <= $#enrichedtestname; $i++){
		$lolim[$i] = trim($lolim[$i]);
		$hilim[$i] = trim($hilim[$i]);
		$lolim[$i] =~ s/>|<//ig;
                $hilim[$i] =~ s/>|<//ig;
                #remove last characters in limits
                $lolim[$i] =~ s/\D+$//g;
                $hilim[$i] =~ s/\D+$//g;

                my $test = new_test;
                $testnumber[$i] =~ s/\D//g;
                $test->number($testnumber[$i]);
                $test->name($enrichedtestname[$i]);
                $test->units(repDashNA($unit[$i]));
		if ((grep { $_ eq $i } @defaultlimitidx) && ($lolim[$i] eq "" && $hilim[$i] eq "")){
			$test->LSL(-.5);
			$test->HSL(+.5);
		}
		else {
                	$test->LSL(repDashNA($lolim[$i]));
                	$test->HSL(repDashNA($hilim[$i]));
		}
                $model->add('tests',$test);
        }

        return $model;		
}

sub readFileDVDS {
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
        my $testfloor = "HYME";
        my $testfacility = "HYME";
        my $report = "";
        my $lotid = "";
        my $system = "";
        my $product = "";
        my $reciperevision = "";
        my $testertype = "";
        my $nodename = "";
	my $alternateproduct = "";
        my $area = "Final Test";
        my $processingstep = "DVDS";
        my $jobname = "";
        my $dataflag = 0;
        my @testnumber;
        my @testname;
        my @lolim;
        my @hilim;
        my @unit;
        my @bias1;
        my @bias2;
        my %swbincnt = {};
	my %hwbincnt = {};
	my $infocolumnflag = 0;
	my @defaultlimitidx;
	my $tmplot1 = "";
	my $tmplot2 = "";
	#my $datecomparison = "2025/11/01 00:00:00";
	my $testtime = "";
	my $infocolumnflag = 0;

        #get lotid from filename
        my $fname = basename $infile;
	#($lotid,$product,$reciperevision) = extractMetaFromFilename($infile);
	#$alternateproduct = $product;
        #$header->PRODUCT($product);
        #$header->RECIPE_REVISION($reciperevision);
        ($tmplot1,$product,$reciperevision) = extractMetaFromFilename($infile);
        $header->FAB($fab);
        $header->TEST_FACILITY($testfacility);
        $header->TEST_FLOOR($testfloor);
        $header->AREA($area);
        $header->PROCESSING_STEP($processingstep);
	#$header->ALTERNATE_PRODUCT($alternateproduct);

        open CSV, $infile or die "can't open $infile\n";
        while($line=<CSV>){
                chomp($line);
                my @row = split /\,/, $line;

                if ($row[0] =~ /System/i){
                        my @item = split/\s|\[|\]/, $row[1];
                        $testertype = trim($item[0]);
                        $nodename = trim($item[2]);
                        $nodename =~ s/\[|\]//ig;
                        $header->MEASURING_EQUIPMENT($nodename);
                        $header->TESTER_TYPE($testertype);
                }
                elsif ($row[0] =~ /Job_Name/i){
                        $jobname = trim($row[1]);
                        $header->RECIPE($jobname);
                }	
		elsif ($row[0] =~ /Lot_Id\.|Lot Id\./) {
			$tmplot2 = trim($row[1]);
		}
		elsif ($row[0] =~ /Lot_No\.|Lot No\./) {
			#$lotid = trim($row[1]);
			#$header->LOT($lotid);
			$tmplot1 = trim($row[1]);
		}
		elsif ($row[0] =~ /Report/i){
                        $report = trim($row[1]);
                        $report = "${report}:00";
                        $header->START_TIME($report);
                        $header->END_TIME($report);
                }
		elsif ($row[3] =~ /^Test$/i || $row[4] =~ /^Test$/i){
			if ($row[3] =~ /^Test$/i) {
                        	@testnumber = splice(@row, 4);
			}
			elsif ($row[4] =~ /^Test$/i){
				@testnumber = splice(@row, 5);
			}
			# this row/line sometimes ends with comma which causes to add blank test number
			# Ex: ,,,Test,T1,T2,T3,T4,T5,
			# remove last element
			$testnumber[$#testnumber] = trim($testnumber[$#testnumber]);
			my $dump = pop(@testnumber) if ($testnumber[$#testnumber] eq "");
                }
		elsif ($row[3] =~ /^Item$/i || $row[4] =~ /^Item$/i){

			if ($row[3] =~ /^Item$/i) {
                        	@testname = splice(@row, 4);
			}
			elsif ($row[4] =~ /^Item$/i){
				@testname = splice(@row, 5);
			}
			# this row/line sometimes ends with comma which causes to add blank test name
			# Ex: ,,,Item,CONT,SHORT,OPEN,VF1,DVF,
			# remove last element
			$testname[$#testname] = trim($testname[$#testname]);
			my $dump = pop(@testname) if ($testname[$#testname] eq "");
                }
		elsif ($row[3] =~ /^LL$/i || $row[4] =~ /^LL$/i){
			if ($row[3] =~ /^LL$/i) {
                        	@lolim = splice(@row, 4);
			}
			elsif ($row[4] =~ /^LL$/i){
				@lolim = splice(@row, 5);
			}
                }
		elsif ($row[3] =~ /^HL$/i || $row[4] =~ /^HL$/i){
			if ($row[3] =~ /^HL$/i){
                        	@hilim = splice(@row, 4);
			}
			elsif ($row[4] =~ /^HL$/i){
				@hilim = splice(@row, 5);
			}
                }
		elsif ($row[3] =~ /^Bias1$/i || $row[4] =~ /^Bias1$/i){
			if ($row[3] =~ /^Bias1$/i){
                        	@bias1 = splice(@row, 4);
			}
			elsif ($row[4] =~ /^Bias1$/i){
				@bias1 = splice(@row, 5);
			}
                }
		elsif ($row[3] =~ /^Bias2$/i || $row[4] =~ /^Bias2$/i){
			if ($row[3] =~ /^Bias2$/i){
                        	@bias2 = splice(@row, 4);
			}
			elsif ($row[4] =~ /^Bias2$/i){
				@bias2 = splice(@row, 5);
			}
                }
		elsif ($row[3] =~ /^Unit$/i || $row[4] =~ /^Unit$/i){
			if ($row[3] =~ /^Unit$/i){
                        	@unit = splice(@row, 4);
			}
			elsif ($row[4] =~ /^Unit$/i){
				@unit = splice(@row, 5);
				$infocolumnflag = 1;
			}
                }
                elsif (($row[0] =~ /^No$/i && $row[1] =~ /^BIN/i) || ($row[0] =~ /^No$/i && $row[1] =~ /^Info/i)){
                        $dataflag = 1;
                }
                elsif ($row[0] =~ /^\d{1,}$/ && $dataflag == 1) {				
			my $no = shift(@row);
			my $info = shift(@row) if ($infocolumnflag == 1);
                        my $bin = shift(@row);
                        my $time = shift(@row);
                        my $result = shift(@row);

			$no = trim($no);
			$bin = trim($bin);
			$time = trim($time);
			$result = trim($result);

                        #store bin counts
                        $swbincnt{$bin}++;
			$hwbincnt{$bin}++;

                        my $die = new_die( { partid => $no } );
                        $die->partid($no);
                        $die->ecid($no);
                        $die->site("1");
                        $die->touchdown_num("-1");
			$die->bindesc("SWBin_".sprintf("%03d",$bin));
			$die->testtime(repNA($time));
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
				$testname[$i] = trim($testname[$i]);				
                                $die->add('result', repNA($row[$i]));
				# check result and flag when to set defaultlimits
				if ($row[$i] =~ /PASS|FAIL/ig) {
					unless (grep { $_ eq $i } @defaultlimitidx) {
						push @defaultlimitidx, $i;
					}
				}	
                        }
		}
	}
	close CSV;

	#apply changes after Nov-01-2025
	#while retaining data mapping before the said data
	$testtime = $header->{START_TIME};
	if ($testtime ge $datecomparison) {
		WARN("Test time $testtime is greater than $datecomparison. Newer data mapping will be used.");
		my @item = split /\_/, $jobname;
		$product = substr($item[1],0,-1);
		$product =~ s/\.$//ig;
		$product =~ s/\-$//ig;
		$reciperevision = substr($item[1],-1);		
		$alternateproduct = $product;
		$header->LOT($tmplot2);
		$header->SUBCON_LOT_ID($tmplot1);
		$header->PRODUCT($product);
		$header->RECIPE_REVISION($reciperevision);
		$header->ALTERNATE_PRODUCT($alternateproduct);
	}
	else {
		#($tmplot1,$product,$reciperevision) = extractMetaFromFilename($infile);
		WARN("Test time $testtime is lesser than $datecomparison. Older data mapping will be used.");
		$alternateproduct = $product;
		$header->LOT($tmplot1);
		$header->PRODUCT($product);
		$header->RECIPE_REVISION($reciperevision);	
		$header->ALTERNATE_PRODUCT($alternateproduct);
	}

        #enrich testname
        my @enrichedtestname;
        for (my $i=0; $i <= $#testname; $i++){
                $testname[$i] = trim($testname[$i]);
                $testnumber[$i] = trim($testnumber[$i]);
                $bias1[$i] = repDashNA(trim($bias1[$i]));
                $bias2[$i] = repDashNA(trim($bias2[$i]));

                my $str = "";

                #$str = "${testnumber[$i]}:${testname[$i]}_${bias1[$i]}_${bias2[$i]}";
                $str = "${testname[$i]}_${bias1[$i]}_${bias2[$i]}";
                $str =~ s/N\/A//g;
                $str =~ s/__$//g;
                $str =~ s/_$//g;
                push (@enrichedtestname, $str);

        }

        for (my $i=0; $i <= $#enrichedtestname; $i++){
		$lolim[$i] = trim($lolim[$i]);
		$hilim[$i] = trim($hilim[$i]);
                #remove last characters in limits
                $lolim[$i] =~ s/\D+$//g;
                $hilim[$i] =~ s/\D+$//g;

                my $test = new_test;
                $testnumber[$i] =~ s/\D//g;
                $test->number($testnumber[$i]);
                $test->name($enrichedtestname[$i]);
                $test->units(repDashNA($unit[$i]));
		if ((grep { $_ eq $i } @defaultlimitidx) && ($lolim[$i] eq "" && $hilim[$i] eq "")){
			$test->LSL(-.5);
			$test->HSL(+.5);
		}
		else {
                	$test->LSL(repDashNA($lolim[$i]));
                	$test->HSL(repDashNA($hilim[$i]));
		}
                $model->add('tests',$test);
        }

        return $model;		
}

sub readFileEAS {
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
	my $testfloor = "HYME";
	my $testfacility = "HYME";
	my $report = "";
	my $lotid = "";
	my $system = "";
	my $product = "";
	my $reciperevision = "";
	my $alternateproduct = "";
	my $testertype = "";
	my $nodename = "";
	my $area = "Final Test";
	my $processingstep = "";
	my $jobname = "";
	my $dataflag = 0;
	my @testnumber;
	my @testname;
	my @lolim;
	my @hilim;
	my @unit;
	my @bias1;
	my @bias2;
	my %swbincnt = {};
	my %hwbincnt = {};
	my @defaultlimitidx;

	#get lotid from filename
	my $fname = basename $infile;
	$fname =~ s/\s/\_/ig;
	($lotid,$product,$reciperevision) = extractMetaFromFilename($infile);
	$alternateproduct = $product; 
	$header->LOT($lotid);
	$header->PRODUCT($product);
	$header->RECIPE_REVISION($reciperevision);
	$header->FAB($fab);
	$header->TEST_FACILITY($testfacility);
	$header->TEST_FLOOR($testfloor);
	$header->AREA($area);
	$header->ALTERNATE_PRODUCT($alternateproduct);

	#Determine processing step from filename
	if ( $fname =~ m/EAS_HC|EAS-HC/i) {
		$processingstep = "EAS_HC";
	}
	elsif ( $fname =~ m/EAS_LC|EAS-LC/i) {
		$processingstep = "EAS_LC";
	}
	elsif ( $fname =~ m/EAS\.CSV|EAS_DATA/i) {
		$processingstep = "EAS";
	}
	$header->PROCESSING_STEP($processingstep);

	open CSV, $infile or die "can't open $infile\n";
	while($line=<CSV>){
		chomp($line);
		my @row = split /\,/, $line;

		if ($row[0] =~ /System/i){
			my @item = split/\s|\[|\]/, $row[1];
			$testertype = trim($item[0]);
			$nodename = trim($item[2]);
			$nodename =~ s/\[|\]//ig;
			$header->MEASURING_EQUIPMENT($nodename);		
			$header->TESTER_TYPE($testertype);
		}
		elsif ($row[0] =~ /Job_Name/i){
			$jobname = trim($row[1]);
			$header->RECIPE($jobname);			
		}
		elsif ($row[0] =~ /Lot_No\.|Lot No\./) {
			$lotid = trim($row[1]);
			$header->LOT($lotid);
		}
		elsif ($row[0] =~ /Report/i){
			$report = trim($row[1]);
			$report = "${report}:00";
			$header->START_TIME($report);
			$header->END_TIME($report);	
		}
		elsif ($row[4] =~ /^Test$/i){
			@testnumber = splice(@row, 5); 
			# this row/line sometimes ends with comma which causes to add blank test number
			# Ex: ,,,,Test,T1,T2,T3,T4,T5,T6,T7,T8,T9,T10,T11,T12,T13,T14,T15,T16,
			# remove last element
			my $dump = pop(@testnumber) if ($testnumber[$#testnumber] eq "");
		}
		elsif ($row[4] =~ /^Item$/i){
			@testname = splice(@row, 5);
			# this row/line sometimes ends with comma which causes to add blank test name
			# Ex: ,,,,Item,VD_CHK,CONT,PRE_VD,PRE_SHORT,PRE_OPEN,IDT,IDT_OVER,ENERGY,COIL,ID,VD-DELAY,BVDS,BVDS_MIN,BVDS_MAX,COLLAPSE,POST_SHORT,
			# remove last element
			my $dump = pop(@testname) if ($testname[$#testname] eq "");
                }
		elsif ($row[4] =~ /^LL$/i){
			@lolim = splice(@row, 5);
                }
		elsif ($row[4] =~ /^HL$/i){
			@hilim = splice(@row, 5);
                }
		elsif ($row[4] =~ /^Bias1$/i){
			@bias1 = splice(@row, 5);
                }
                elsif ($row[4] =~ /^Bias2$/i){
			@bias2 = splice(@row, 5);
                }
                elsif ($row[4] =~ /^Unit$/i){
			@unit = splice(@row, 5);
			$dataflag = 1;
                }
		elsif ($row[0] =~ /^\d{1,}$|^\s+\d{1,}$/ && $dataflag == 1) {
			my $no = shift(@row);
			my $bin = shift(@row);
			my $time = shift(@row);
			my $result = shift(@row);
			my $dump = shift(@row);
			$time =~ s/\D+$//g;
			$bin = trim($bin);

			#store bin counts
			$swbincnt{$bin}++;
			$hwbincnt{$bin}++;

			my $die = new_die( { partid => $no } );
			$die->partid($no);
			$die->ecid($no);
			$die->site("1");
			$die->touchdown_num("-1");
			$die->bindesc("SWBin_".sprintf("%03d",$bin));
			$die->testtime(repNA($time));
			$wafer->add('dies',$die);

			#SWBins
			my $swbin = $wafer->find('sbins',{ number => $bin});
			unless (defined $swbin){
				$swbin = new_bin;
				$swbin->number($bin);
				$swbin->name("SWBin_".sprintf("%03d",$bin));
				$swbin->count($swbincnt{$bin});
				if ($result eq "PASS") {
					$swbin->PF("P");
				}
				else {
					$swbin->PF("F");
				}
				$wafer->add('sbins',$swbin);
			}
			$swbin->count($swbincnt{$bin});
			$die->soft_bin($bin);						

			#HWBins
                        my $hwbin = $wafer->find('hbins',{ number => $bin});
                        unless (defined $hwbin){
                                $hwbin = new_bin;
                                $hwbin->number($bin);
                                $hwbin->name("HWBin_".sprintf("%03d",$bin));
                                $hwbin->count($hwbincnt{$bin});
                                if ($result eq "PASS") {
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
				#Ignore any test with item name COIL, ID, VD-DELAYS	
				$testname[$i] = trim($testname[$i]);
				if ($testname[$i] =~ /^COIL$|^ID$|^VD-DELAY$/ig) {
					next;
				}
				else {
					$die->add('result', repNA($row[$i]));
					# check result and flag when to set defaultlimits
					if ($row[$i] =~ /PASS|FAIL/ig) {
						unless (grep { $_ eq $i } @defaultlimitidx) {
							push @defaultlimitidx, $i;
						}
					}
				}
			}
		}
	}
	close CSV;

	#enrich testname
	my @enrichedtestname;
	for (my $i=0; $i <= $#testname; $i++){
		$testname[$i] = trim($testname[$i]);
		$testnumber[$i] = trim($testnumber[$i]);

		my $str = "";
		
		#$str = "${testnumber[$i]}:${testname[$i]}";
		$str = "${testname[$i]}";
		push (@enrichedtestname, $str);
		
	}

	for (my $i=0; $i <= $#enrichedtestname; $i++){
		$lolim[$i] = trim($lolim[$i]);
		$hilim[$i] = trim($hilim[$i]);
		$unit[$i] = trim($unit[$i]);
		#Ignore any test with item name SAME or PAT
		if ($testname[$i] =~ /^COIL$|^ID$|^VD-DELAY$/ig) {
			next;
		}
		else {
			my $test = new_test;
			$testnumber[$i] =~ s/\D//g;
			$test->number($testnumber[$i]);
			$test->name($enrichedtestname[$i]);
			$test->units(repDashNA($unit[$i]));
			if ((grep { $_ eq $i } @defaultlimitidx) && ($lolim[$i] eq "" && $hilim[$i] eq "")){
				$test->LSL(-.5);
				$test->HSL(+.5);
			}
			else {
				$test->LSL(repDashNA($lolim[$i]));
				$test->HSL(repDashNA($hilim[$i]));
			}
			$model->add('tests',$test);	
		}
	}
	
	return $model;

}

sub readFileUIS {
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
	my $testfloor = "HYME";
	my $testfacility = "HYME";
	my $report = "";
	my $lotid = "";
	my $system = "";
	my $product = "";
	my $reciperevision = "";
	my $alternateproduct = "";
	my $testertype = "";
	my $nodename = "";
	my $area = "Final Test";
	my $processingstep = "";
	my $jobname = "";
	my $dataflag = 0;
	my @testnumber;
	my @testname;
	my @lolim;
	my @hilim;
	my @unit;
	my @bias1;
	my @bias2;
	my %swbincnt = {};
	my %hwbincnt = {};
	my @defaultlimitidx;
	my $infocolumnflag = 0;
	my $tmplot1 = "";
	my $tmplot2 = "";
	my $testtime = "";

	#get lotid from filename
	my $fname = basename $infile;
	#($lotid,$product,$reciperevision) = extractMetaFromFilename($infile);
	#$alternateproduct = $product;
	#$header->PRODUCT($product);
	#$header->RECIPE_REVISION($reciperevision);
	($tmplot1,$product,$reciperevision) = extractMetaFromFilename($infile);
	$header->FAB($fab);
	$header->TEST_FACILITY($testfacility);
	$header->TEST_FLOOR($testfloor);
	$header->AREA($area);
	#$header->ALTERNATE_PRODUCT($alternateproduct);

	#Determine processing step from filename
	if ( $fname =~ m/UIS_HC|UIS-HC|UIL_HC|UIL-HC/i) {
		$processingstep = "UIS_HC";
	}
	elsif ( $fname =~ m/UIS_LC|UIS-LC|UIL_LC|UIL-LC/i) {
		$processingstep = "UIS_LC";
	}
	elsif ( $fname =~ m/UIS\.CSV|UIS_DATA|UIL\.CSV|UIL_DATA/i) {
                $processingstep = "UIS";
        }
	$header->PROCESSING_STEP($processingstep);

	open CSV, $infile or die "can't open $infile\n";
	while($line=<CSV>){
		chomp($line);
		my @row = split /\,/, $line;

		if ($row[0] =~ /System/i){
			my @item = split/\s|\[|\]/, $row[1];
			$testertype = trim($item[0]);
			$nodename = trim($item[2]);
			$nodename =~ s/\[|\]//ig;
			$header->MEASURING_EQUIPMENT($nodename);		
			$header->TESTER_TYPE($testertype);
		}
		elsif ($row[0] =~ /Job_Name/i){
			$jobname = trim($row[1]);
			$header->RECIPE($jobname);			
		}
		elsif ($row[0] =~ /Lot_Id\.|Lot Id\./){
			$tmplot2 = trim($row[1]);
		}
		elsif ($row[0] =~ /Lot_No\.|Lot No\./){
			$tmplot1 = trim($row[1]);
			#$lotid = trim($row[1]);
			#$header->LOT($lotid);
		}
		elsif ($row[0] =~ /Report/i){
			$report = trim($row[1]);
			$report = "${report}:00";
			$header->START_TIME($report);
			$header->END_TIME($report);	
		}
		elsif ($row[4] =~ /^Test$/i || $row[5] =~ /^Test$/i){
			if ($row[4] =~ /^Test$/i) {
				@testnumber = splice(@row, 5); 
			}
			elsif ($row[5] =~ /^Test$/i){
				@testnumber = splice(@row, 6);
			}
			# this row/line sometimes ends with comma which causes to add blank test number
			# Ex: ,,,,Test,T1,T2,T3,T4,T5,T6,T7,T8,T9,T10,T11,T12,T13,T14,T15,T16,
			# remove last element
			$testnumber[$#testnumber] = trim($testnumber[$#testnumber]);
			my $dump = pop(@testnumber) if ($testnumber[$#testnumber] eq "");
		}
		elsif ($row[4] =~ /^Item$/i || $row[5] =~ /^Item$/i){
			if ($row[4] =~ /^Item$/i) {
				@testname = splice(@row, 5);
			}
			elsif ($row[5] =~ /^Item$/i){
				@testname = splice(@row, 6);	
			}
			# this row/line sometimes ends with comma which causes to add blank test name
			# Ex: ,,,,Item,VD_CHK,CONT,PRE_VD,PRE_SHORT,PRE_OPEN,IDT,IDT_OVER,ENERGY,COIL,ID,VD-DELAY,BVDS,BVDS_MIN,BVDS_MAX,COLLAPSE,POST_SHORT,
			# remove last element
			$testname[$#testname] = trim($testname[$#testname]);
			my $dump = pop(@testname) if ($testname[$#testname] eq "");
                }
		elsif ($row[4] =~ /^LL$/i || $row[5] =~ /^LL$/i){
			if ($row[4] =~ /^LL$/i) {
				@lolim = splice(@row, 5);
			}
			elsif ($row[5] =~ /^LL$/i){
				@lolim = splice(@row, 6);
			}
		}
		elsif ($row[4] =~ /^HL$/i || $row[5] =~ /^HL$/i){
			if ($row[4] =~ /^HL$/i){
				@hilim = splice(@row, 5);
			}
			elsif ($row[5] =~ /^HL$/i){
				@hilim = splice(@row, 6);
			}
		}
		elsif ($row[4] =~ /^Bias1$/i || $row[5] =~ /^Bias1$/i){
			if ($row[4] =~ /^Bias1$/i){
				@bias1 = splice(@row, 5);
			}
			elsif ($row[5] =~ /^Bias1$/i){
				@bias1 = splice(@row, 6);
			}
		}
		elsif ($row[4] =~ /^Bias2$/i || $row[5] =~ /^Bias2$/i){
			if ($row[4] =~ /^Bias2$/i){
				@bias2 = splice(@row, 5);
			}
			elsif ($row[5] =~ /^Bias2$/i){
				@bias2 = splice(@row, 6);
			}
		}
		elsif ($row[4] =~ /^Unit$/i || $row[5] =~ /^Unit$/i){
			if ($row[4] =~ /^Unit$/i) {
				@unit = splice(@row, 5);
			}
			elsif ($row[5] =~ /^Unit$/i){
				@unit = splice(@row, 6);
				$infocolumnflag = 1;
			}
			$dataflag = 1;
		}
		elsif ($row[0] =~ /^\d{1,}$|^\s+\d{1,}$/ && $dataflag == 1) {
			my $no = shift(@row);
			my $info = shift(@row) if ($infocolumnflag == 1);
			my $bin = shift(@row);
			my $time = shift(@row);
			my $result = shift(@row);
			my $dump = shift(@row);
			$time =~ s/\D+$//g;
			$bin = trim($bin);
			$no = trim($no);
			$result = trim($result);

			#store bin counts
			$swbincnt{$bin}++;
			$hwbincnt{$bin}++;

			my $die = new_die( { partid => $no } );
			$die->partid($no);
			$die->ecid($no);
			$die->site("1");
			$die->touchdown_num("-1");
			$die->bindesc("SWBin_".sprintf("%03d",$bin));
			$die->testtime(repNA($time));
			$wafer->add('dies',$die);

			#SWBins
			my $swbin = $wafer->find('sbins',{ number => $bin});
			unless (defined $swbin){
				$swbin = new_bin;
				$swbin->number($bin);
				$swbin->name("SWBin_".sprintf("%03d",$bin));
				$swbin->count($swbincnt{$bin});
				if ($result eq "PASS") {
					$swbin->PF("P");
				}
				else {
					$swbin->PF("F");
				}
				$wafer->add('sbins',$swbin);
			}
			$swbin->count($swbincnt{$bin});
			$die->soft_bin($bin);						

			#HWBins
                        my $hwbin = $wafer->find('hbins',{ number => $bin});
                        unless (defined $hwbin){
                                $hwbin = new_bin;
                                $hwbin->number($bin);
                                $hwbin->name("HWBin_".sprintf("%03d",$bin));
                                $hwbin->count($hwbincnt{$bin});
                                if ($result eq "PASS") {
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
				#Ignore any test with item name COIL, ID, VD-DELAYS	
				$testname[$i] = trim($testname[$i]);
				if ($testname[$i] =~ /^COIL$|^ID$|^VD-DELAY$/ig) {
					next;
				}
				else {
					$die->add('result', repNA($row[$i]));
					# check result and flag when to set defaultlimits
					if ($row[$i] =~ /PASS|FAIL/ig) {
						unless (grep { $_ eq $i } @defaultlimitidx) {
							push @defaultlimitidx, $i;
						}
					}
				}
			}
		}
	}
	close CSV;

	#apply changes after Nov-01-2025
	#while retaining data mapping before the said data
	$testtime = $header->{START_TIME};
	if ($testtime ge $datecomparison) {
		WARN("Test time $testtime is greater than $datecomparison. Newer data mapping will be used.");
		my @item = split /\_/, $jobname;
		$product = substr($item[1],0,-1);
		$product =~ s/\.$//ig;
		$product =~ s/\-$//ig;
		$reciperevision = substr($item[1],-1);
		$alternateproduct = $product;
		$header->LOT($tmplot2);
		$header->SUBCON_LOT_ID($tmplot1);
		$header->PRODUCT($product);
		$header->RECIPE_REVISION($reciperevision);
		$header->ALTERNATE_PRODUCT($alternateproduct);
	}
	else {
		WARN("Test time $testtime is lesser than $datecomparison. Older data mapping will be used.");
		$alternateproduct = $product;
		$header->LOT($tmplot1);
		$header->PRODUCT($product);
		$header->RECIPE_REVISION($reciperevision);
		$header->ALTERNATE_PRODUCT($alternateproduct);
	}

	#enrich testname
	my @enrichedtestname;
	for (my $i=0; $i <= $#testname; $i++){
		$testname[$i] = trim($testname[$i]);
		$testnumber[$i] = trim($testnumber[$i]);

		my $str = "";
		
		#$str = "${testnumber[$i]}:${testname[$i]}";
		$str = "${testname[$i]}";
		push (@enrichedtestname, $str);
		
	}

	for (my $i=0; $i <= $#enrichedtestname; $i++){
		$lolim[$i] = trim($lolim[$i]);
		$hilim[$i] = trim($hilim[$i]);
		#Ignore any test with item name SAME or PAT
		if ($testname[$i] =~ /^COIL$|^ID$|^VD-DELAY$/ig) {
			next;
		}
		else {
	
			my $test = new_test;
			$testnumber[$i] =~ s/\D//g;
			$test->number($testnumber[$i]);
			$test->name($enrichedtestname[$i]);
			$test->units(repDashNA($unit[$i]));
			if ((grep { $_ eq $i } @defaultlimitidx) && ($lolim[$i] eq "" && $hilim[$i] eq "")){
				$test->LSL(-.5);
				$test->HSL(+.5);
			}
			else {
				$test->LSL(repDashNA($lolim[$i]));
				$test->HSL(repDashNA($hilim[$i]));
			}
			$model->add('tests',$test);	
		}
	}
	
	return $model;
}

sub readFileQC {
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
	my $testfloor = "HYME";
	my $testfacility = "HYME";
	my $report = "";
	my $lotid = "";
	my $system = "";
	my $product = "";
	my $reciperevision = "";
	my $testertype = "";
	my $nodename = "";
	my $area = "Final Test";
	my $processingstep = "QC";
	my $alternateproduct = "";
	my $jobname = "";
	my $dataflag = 0;
	my @testnumber;
	my @testname;
	my @lolim;
	my @hilim;
	my @unit;
	my @bias1;
	my @bias2;
	my %swbincnt = {};
	my %hwbincnt = {};
	my @defaultlimitidx;
	my $tmplot1 = "";
	my $tmplot2 = "";
	my $testtime = "";
	my $infocolumnflag = 0;

	#get lotid from filename
	my $fname = basename $infile;
	#($lotid,$product,$reciperevision) = extractMetaFromFilename($infile);
	#$alternateproduct = $product;
	#$header->LOT($lotid);
	#$header->PRODUCT($product);
	#$header->RECIPE_REVISION($reciperevision);
	($tmplot1,$product,$reciperevision) = extractMetaFromFilename($infile);
	$header->FAB($fab);
	$header->TEST_FACILITY($testfacility);
	$header->TEST_FLOOR($testfloor);
	$header->AREA($area);
	$header->PROCESSING_STEP($processingstep);
	#$header->ALTERNATE_PRODUCT($alternateproduct);

	open CSV, $infile or die "can't open $infile\n";
	while($line=<CSV>){
		chomp($line);
		my @row = split /\,/, $line;

		if ($row[0] =~ /System/i){
			my @item = split/\s|\[|\]/, $row[1];
			$testertype = trim($item[0]);
			$nodename = trim($item[2]);
			$nodename =~ s/\[|\]//ig;
			$header->MEASURING_EQUIPMENT($nodename);		
			$header->TESTER_TYPE($testertype);
		}
		elsif ($row[0] =~ /Job_Name/i){
			$jobname = trim($row[1]);
			$header->RECIPE($jobname);			
		}
		elsif ($row[0] =~ /Lot_Id\.|Lot Id\./) {
			$tmplot2 = trim($row[1]);
		}
		elsif ($row[0] =~ /Lot_No\.|Lot No\./) {
			#$lotid = trim($row[1]);
			#$header->LOT($lotid);
			$tmplot1  = trim($row[1]);
		}
		elsif ($row[0] =~ /Report/i){
			$report = trim($row[1]);
			$report = "${report}:00";
			$header->START_TIME($report);
			$header->END_TIME($report);	
		}
		elsif ($row[4] =~ /^Test$/i){
			@testnumber = splice(@row, 5); 
			# this row/line sometimes ends with comma which causes to add blank test number
			# Ex: ,,,,Test,T1,T2,T3,T4,T5,T6,T7,T8,T9,T10,T11,T12,T13,T14,T15,T16,T17,T18,T19,T20,T21,T22,T23,T24,T25,T26,T27,T28,T29,T30,T31,T32,T33,T34,T35,T36,T37,T38,T39,
			# remove last element
			$testnumber[$#testnumber] = trim($testnumber[$#testnumber]);
			my $dump = pop(@testnumber) if ($testnumber[$#testnumber] eq "");
		}
		elsif ($row[4] =~ /^Item$/i){
			@testname = splice(@row, 5);
			# this row/line sometimes ends with comma which causes to add blank test name
			# Ex: ,,,,Item,CONT,IDSS,ISGS,ISGS,VP,SAME,PAT_S,VP,SAME,BVGSO,SAME,BVGSO,SAME,HRDON,PAT,HVFSD,SAME,PAT_S,IDSS,IDSS,IDSS,PAT,BVDSX,SAME,BVDSX,SAME,BVDSX,SAME,HVBDSS,SAME,PAT_S,HVBDSS,SAME,IDSS,PAT,ISGS,PAT,ISGS,PAT,
			# remove last element
			$testname[$#testname] = trim($testname[$#testname]);
			my $dump = pop(@testname) if ($testname[$#testname] eq "");
                }
		elsif ($row[4] =~ /^LL$/i){
			@lolim = splice(@row, 5);
                }
		elsif ($row[4] =~ /^HL$/i){
			@hilim = splice(@row, 5);
                }
		elsif ($row[4] =~ /^Bias1$/i){
			@bias1 = splice(@row, 5);
                }
                elsif ($row[4] =~ /^Bias2$/i){
			@bias2 = splice(@row, 5);
                }
                elsif ($row[4] =~ /^Unit$/i){
			@unit = splice(@row, 5);
                }
                elsif ($row[0] =~ /^No$/i && $row[1] =~ /^Bin/i){
			$dataflag = 1;
                }	
		elsif ($row[0] =~ /^\d{1,}$/ && $dataflag == 1) {
			my $no = shift(@row);
			my $bin = shift(@row);
			my $time = shift(@row);
			my $result = shift(@row);
			my $failitem = shift(@row);

			$no = trim($no);
			$bin = trim($bin);
			$time = trim($time);
			$time =~ s/'|"//g;
			$result = trim($result);
			$failitem = trim($failitem);

			#store bin counts
			$swbincnt{$bin}++;
			$hwbincnt{$bin}++;

			my $die = new_die( { partid => $no } );
			$die->partid($no);
			$die->ecid($no);
			$die->site("1");
			$die->touchdown_num("-1");
			$die->bindesc(repNA($failitem));
			$die->testtime(repNA($time));
			$wafer->add('dies',$die);

			#SWBins
			my $swbin = $wafer->find('sbins',{ number => $bin});
			unless (defined $swbin){
				$swbin = new_bin;
				$swbin->number($bin);
				$swbin->name("SWBin_".sprintf("%03d",$bin));
				$swbin->count($swbincnt{$bin});
				if ($result eq "PASS") {
					$swbin->PF("P");
				}
				else {
					$swbin->PF("F");
				}
				$wafer->add('sbins',$swbin);
			}
			$swbin->count($swbincnt{$bin});
			$die->soft_bin($bin);						

			#HWBins
                        my $hwbin = $wafer->find('hbins',{ number => $bin});
                        unless (defined $hwbin){
                                $hwbin = new_bin;
                                $hwbin->number($bin);
                                $hwbin->name("HWBin_".sprintf("%03d",$bin));
                                $hwbin->count($hwbincnt{$bin});
                                if ($result eq "PASS") {
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
				#Ignore any test with item name SAME or PAT	
				$testname[$i] = trim($testname[$i]);
				if ($testname[$i] =~ /SAME|PAT/ig) {
					next;
				}
				else {
					$die->add('result', repNA($row[$i]));
					# check result and flag when to set defaultlimits
					if ($row[$i] =~ /PASS|FAIL/ig) {
						unless (grep { $_ eq $i } @defaultlimitidx) {
							push @defaultlimitidx, $i;
						}
					}
				}
			}
		}
	}
	close CSV;

	#apply changes after Nov-01-2025
	#while retaining data mapping before the said data
	$testtime = $header->{START_TIME};
	if ($testtime ge $datecomparison) {
		WARN("Test time $testtime is greater than $datecomparison. Newer data mapping will be used.");
		my @item = split /\_/, $jobname;
		$product = substr($item[1],0,-1);
		$product =~ s/\.$//ig;
		$product =~ s/\-$//ig;
		$reciperevision = substr($item[1],-1);
		$alternateproduct = $product;
		$header->LOT($tmplot2);
		$header->SUBCON_LOT_ID($tmplot1);
		$header->PRODUCT($product);
		$header->RECIPE_REVISION($reciperevision);
		$header->ALTERNATE_PRODUCT($alternateproduct);
	}
	else {
		WARN("Test time $testtime is lesser than $datecomparison. Older data mapping will be used.");
		$alternateproduct = $product;
		$header->LOT($tmplot1);
		$header->PRODUCT($product);
		$header->RECIPE_REVISION($reciperevision);
		$header->ALTERNATE_PRODUCT($alternateproduct);
	}

	#enrich testname
	my @enrichedtestname;
	for (my $i=0; $i <= $#testname; $i++){
		$testname[$i] = trim($testname[$i]);
		$testnumber[$i] = trim($testnumber[$i]);
		$bias1[$i] = repDashNA(trim($bias1[$i]));
		$bias2[$i] = repDashNA(trim($bias2[$i]));
		my @b1item = split/\(|\)/, $bias1[$i];
		my @b2item = split/\(|\)/, $bias2[$i];
		my $b1str = "";
		my $b2str = "";

		if ($b1item[1] ne "" && $b1item[2] ne "") {
			 $b1str = "${b1item[1]}=${b1item[2]}";
		}
		if ($b2item[1] ne "" && $b2item[2] ne "") {
                         $b2str = "${b2item[1]}=${b2item[2]}";
                }

		my $str = "";
		
		#$str = "${testnumber[$i]}:${testname[$i]}_${b1str}_${b2str}";
		$str = "${testname[$i]}_${b1str}_${b2str}";
		$str =~ s/N\/A//g;
		$str =~ s/__$//g;
                $str =~ s/_$//g;
		$str =~ s/=$//g;
		push (@enrichedtestname, $str);
		
	}

	for (my $i=0; $i <= $#enrichedtestname; $i++){
		$lolim[$i] = trim($lolim[$i]);
		$hilim[$i] = trim($hilim[$i]);
		$lolim[$i] =~ s/>|<//ig;
		$hilim[$i] =~ s/>|<//ig;
		#Ignore any test with item name SAME or PAT
		if ($enrichedtestname[$i] =~ /SAME|PAT/ig) {
			next;
		}
		else {
			#remove last characters in limits
        	        $lolim[$i] =~ s/\D+$//g;
        	        $hilim[$i] =~ s/\D+$//g;
	
			my $test = new_test;
			$testnumber[$i] =~ s/\D//g;
			$test->number($testnumber[$i]);
			$test->name($enrichedtestname[$i]);
			$test->units(repDashNA($unit[$i]));
			if ((grep { $_ eq $i } @defaultlimitidx) && ($lolim[$i] eq "" && $hilim[$i] eq "")){
				$test->LSL(-.5);
				$test->HSL(+.5);
			}
			else {
				$test->LSL(repDashNA($lolim[$i]));
				$test->HSL(repDashNA($hilim[$i]));
			}
			$model->add('tests',$test);	
		}
	}
	
	return $model;
}

sub extractMetaFromFilename {
	my $infile = shift;
	my $lotid = "N/A";
	my $product = "N/A";
	my $reciperevision = "N/A";
	#my($filename,$dirs,$suffix) = fileparse($infile,qr/\.csv/i);
	#change due to adding id_file in filename
	my($filename,$dirs,$suffix) = fileparse($infile,qr/\.csv.*/i);
	$filename =~ s/\s/\_/ig;
	my @item = split /\_/, $filename;
	my $item_size = scalar @item;

	if ($item_size == 5){
		if ($item[0] =~ /^ST1/i && $item[1] =~ /^HYC/i){
			$product = substr($item[2],0,-1);
			$reciperevision = substr($item[2],-1);	
		}
	}	
	elsif (($item_size == 6 || $item_size == 7) ||(($item_size == 7 || $item_size == 8) && ($item[0] =~ /^HYC|^ST/i))){
		if ($item[1] =~ /^HYC/i){
			$product = substr($item[2],0,-1);
			$reciperevision = substr($item[2],-1);
			$lotid = trim($item[5]);		
		}
		else {
			$product = trim($item[1]);
			$reciperevision = substr($item[1],-1);
			$lotid = trim($item[4]);
		}
	}
	elsif ($item_size == 8){
		if ($item[0] =~ /^ST/i){
			$product = substr($item[2],0,-1);
			$reciperevision = substr($item[2],-1);
			$lotid = trim($item[5]);
		}
	}
	elsif ($item_size == 9){
		$product = substr($item[2],0,-1);
		$reciperevision = substr($item[2],-1);
		$lotid = trim($item[6]);
	}
	elsif ($item_size == 10){
		$product = substr($item[2],0,-1);
		$reciperevision = substr($item[2],-1);
		$lotid = trim($item[5]);
	}
	elsif ($item_size == 11){
		$product = substr($item[2],0,-1);
		$reciperevision = substr($item[2],-1);
		$lotid = "${item[5]}${item[6]}";
	}
	else {
		$product = trim($item[1]);
		$reciperevision = substr($item[1],-1);
	}

	$product =~ s/E$//ig;
	#$product =~ s/\..*//ig;
	#$product =~ s/\-.*//ig;
	$product =~ s/\.$//ig;
	$product =~ s/\-$//ig;
		

	return $lotid, $product, $reciperevision;
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

1;
