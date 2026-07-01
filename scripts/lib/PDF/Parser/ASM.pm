#CHANGES
#  2015/08/12 grace 	: new_bin
#  2015/11/11 jgarcia 	: check if a succeding wafer test result count is not more than the test param captured from the first wafer 
#												otherwise the raw file is a bad file.
#  2015/12/11 jgarcia 	: modified the parsing section to cater files with line entry without carriage return wether it is the first line or not.
                        # still check the succeeding test result if it matches the number of test param created from the first wafer test result.
#  2016/01/26 eric 	: added sub read_lot_level. modified sub readFile to spit also by "L,".
#  2016/01/27 eric 	: extract correct lot level start/end time
#  2016/01/28 eric 	: get only the first occurence of "Reticle"
#  2016/02/18 eric 	: extract wafer start/end times
#  2016/05/13 eric 	: renamed readFile to read_wfr_level
#  2017/05/12 eric	: assign source lot as waferid
#  2020/08/22 eric	: added new parsing combination for spliting lot and wafer data
                       
package PDF::Parser::ASM;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use Time::Local;
use File::Basename qw/basename/;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";
my $testNum = 1;

my $attr = [];
my %bin = ();
my %sbin = ();
my @bins;
my %binCount; 
my $good_bin;

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);


sub read_wfr_level{
    	my $self   = shift;
    	my $infile = shift;
    	my $platform = shift;
    	my $header = new_headerLong;
    	my $model  = new_model(
    	{   header => $header,
            misc   => {},
            dataSource => 'ASM'
    	}
    	);
    	my $wafers = {};
    	my $waferSites = {};
    	my $seq = 0;
    	my ($tUnits,$tHI,$tLO) = (0,0,0);
    	my $waferNum;
    	my $site;
    	my $saveTest = 0;
    	my $testNum = 1;
    	my $totalTestCount = 0;
    	my $totalParamCount = 0;
    	my $start_time;
	my $end_time;
    	my @lineArray = ();
    	my $line = "";
    	my $set = "";
    	open (INFILE, "<",$infile);
    	while (<INFILE>) {
    		push (@lineArray, $_);
    	}
	close(INFILE);

	foreach $line (@lineArray) {
	  	#unshift @item, 'R' if ($item[0] =~ /WaferNumber/i);
	  	foreach $set (split /^R,|,R,|^L,|,L,/, $line) {
	  		#print "$set\n";
	  		$seq++;
	  		my @item = split(/,/, $set);
	  		if($item[0] eq "") {
	  			shift(@item);
	  		}
	  		if ($item[0] =~ /WaferNumber=\d+/i) {
	  			unshift (@item, 'R');
	  		}
	  		 
	  		if ($seq eq 1) {
				print "@item\n";
	  			INFO($item[0]."/".$item[1]);
				$header->LOT($item[1]);
				$header->PROGRAM($item[2]);
				$header->EQUIP3_ID($item[2]);
				$header->OPERATOR($item[3]);
				$header->STEP($item[8]);
				$header->REVISION(1);
				$header->EQUIP2_ID("PHOTO ASM::".$item[0]);
				if($item[9] =~ /(\d{4})(\d{2})(\d{2}) (\d{2}:\d{2}:\d{2})/){
					$start_time = $1."/".$2."/".$3." ".$4;
				
		  		}
				$header->populateSrcLot;
			}
			elsif ($item[0] eq 'R') {
			  	if($item[1] =~ /WaferNumber=(\d+)/){
					$waferNum = $1;
				}
				if($item[2] =~ /Status=(\S+)/){
					$site = $1;				
				}
						
            			my $wafer = $model->find('wafers',{number => $waferNum});
            			unless (defined $wafer){
               				$wafer = new_wafer( { number => $waferNum } );
					if ($header->SOURCE_LOT ne "") {
						$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
					}
              				$model->add('wafers',$wafer);
			   		$wafer->START_TIME($start_time);
			   		#$wafer->END_TIME($start_time);
            			}
			
            			my $die = $wafer->find('dies',{site=>$site});
            			unless (defined $die){
               				$die = new_die( { site => $site } );
               				$wafer->add('dies',$die);
            			}

            			foreach ( split( /\s+/, $3 ) ) {
                			$die->add( 'result', $_ );
            			}
			
				if($item[3] =~ /Date_Time=(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/){			
					#$wafer->START_TIME( "20".$1."/".$2."/".$3." ".$4.":".$5.":".$6 );
					#$wafer->END_TIME( "20".$1."/".$2."/".$3." ".$4.":".$5.":".$6 );
					$end_time = "20".$1."/".$2."/".$3." ".$4.":".$5.":".$6;
					#$wafer->START_TIME($start_time);
					$wafer->END_TIME($end_time);
				}
			
				if(! $saveTest){
					for(my $i=4; $i<=$#item; $i++){
						#print "1--->$item[$i]\n";
						my @wk = split("=", $item[$i]);
						my $test = new_test;
						$test->number($testNum);
						$test->name( $wk[0] );
						$model->add('tests',$test);
						$testNum++;		
					}
					$saveTest = 1;				
				}
				$totalTestCount = $testNum + 3;
				$totalParamCount = $#item + 1;
				for(my $i=4; $i<=$#item; $i++){
					#print "SAVETEST=>$saveTest \t TOTAL_TEST_COUNT=>$totalTestCount \t TOTAL_PARAM_COUNT=>$totalParamCount\n";
					# 2015-11-11 jgarcia : 
					if ($saveTest == 1 && $totalTestCount < $totalParamCount) {
						dpExit(1, "Bad file format: $infile : certain wafer have more test parameters|test results compared to the first wafer:");
					}
					my @wk = split("=", $item[$i]);
					$die->add( 'result', $wk[1] );								
				}
			  }###END OF ELSIF ITEM EQ 'R'
	  		#print "@item\n";
	  	}##END OF FOREACH SET
	  }##END OF FOREACH LINE
    return $model;
}

sub read_lot_level {
	my $self   = shift;
	my $infile = shift;
	my $start_time;
        my @lineArray = ();
	my $testNum = 1;
	my $seq = 0;
	my $line = "";
	my $set = "";
	my $site;
	my $reticle_dup_flg = 0;
	my $header = new_headerLong;
	my $model  = new_model(
        {   header => $header,
            misc   => {},
            dataSource => 'ASM'
        }
        );
	my $wafer = $model->find('wafers',{number => 0});
        unless (defined $wafer){
                $wafer = new_wafer( { number => 0 } );
                $model->add('wafers',$wafer);
        }
	
	open (INFILE, "<",$infile);
        while (<INFILE>) {
                push (@lineArray, $_);
        }
	close(INFILE);

	my $die = new_die;
        foreach $line (@lineArray) {
		my @ln_set = split /^R,|,R,|^L,|,L,/, $line;
		foreach $set (@ln_set){
		#foreach $set (split /R,/, $line) {
			#print "$set\n";
                        $seq++;
                        my @item = split(/,/, $set);			
			if ($seq eq 1) {
				$header->LOT($item[1]);
				$header->PROGRAM($item[2]);
				$header->EQUIP3_ID($item[2]);
				$header->OPERATOR($item[3]);
				$header->STEP($item[8]);
				$header->REVISION(1);
				$header->EQUIP2_ID("PHOTO ASM::".$item[0]);
				if($item[9] =~ /(\d{4})(\d{2})(\d{2}) (\d{2}:\d{2}:\d{2})/){
					$start_time = $1."/".$2."/".$3." ".$4;
					$header->START_TIME($start_time);
			  	}	
				$header->populateSrcLot;
			}
			if ($item[0] !~ /^R\,/ && $item[0] =~ /^reticle/i){
				$reticle_dup_flg++;
				if ($reticle_dup_flg == 1) {       # Get only the first occurence of "Reticle"
					for (my $i=0; $i<=$#item; $i++){
						my @wk = split ("=", $item[$i]);
						my $test = new_test;
						$test->number($testNum);
						$test->name(trim($wk[0])); 
						$die->add('result',repNA(trim($wk[1])));
						$model->add('tests',$test);
						$testNum++;
					}
				}
			}
			elsif ($item[0] eq 'L' || $item[0] =~ /^Date_Time/) {
				if ($item[0] =~ /Date_Time=(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/){
					$header->END_TIME("20".$1."/".$2."/".$3." ".$4.":".$5.":".$6 );
				}
				elsif ($item[1] =~ /Date_Time=(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/){	
					$header->END_TIME("20".$1."/".$2."/".$3." ".$4.":".$5.":".$6 );
				}
				for (my $i=0; $i<=$#item; $i++){
                                        my @wk = split ("=", $item[$i]);
					next if $wk[0] =~ /^L$|Date_Time/;
                                        my $test = new_test;
                                        $test->number($testNum);
                                        $test->name(trim($wk[0]));
                                        $die->add('result',repNA(trim($wk[1])));
                                        $model->add('tests',$test);
                                        $testNum++;
                                }
			}
		}
	}	
	$wafer->add('dies',$die);
	
return $model;
}
1;

