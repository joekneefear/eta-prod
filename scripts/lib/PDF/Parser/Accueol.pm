# SVN $Id: Accueol.pm 2096 2017-04-04 05:12:12Z dpower $
# 10-Jun-2015 Eric 	- Create limit file for .DAT
# 24-Jun-2015 Grace 	- Fixed missing site/die and duplicate IFF generated.
# 24-Jun-2015 Eric 	- Improved regex in searching for TP.
# 02-Aug-2015 Rodney 	- Get test names from the limits file.
# 26-Aug-2015 Gilbert 	- Uppercase the lot id. 
# 11-Dec-2015 Eric 	- Skip storing results if hash for results is not defined because some
# 			files do not wafer end time.
# 14-Dec-2015 Eric 	- some files WFT appears before test results			
# 15-Dec-2015 Eric 	- some files do not have WFT at the end of the file.
# 16-Dec-2105 Eric 	- make WST as WFT is missing
# 18-Dec-2015 Eric 	- modified how die and results were parsed and stored.
# 06-Apr-2016 Eric 	- replace results with -1E18 / 1E18 if results eq -1E21 / 1E21
# 05-Sep-2016 Eric 	- some DAT files do not have blank line in between test block
# 07-Sep-2016 Rodney 	- some DAT files have more than 1 space between *** and the test number; 
#            		replace commas in the test conditions with a space.
# 28-Oct-2016 Eric 	- parse STDF test program.            
# 04-Apr-2017 Eric	- store error codes to misc, assign source lot as wafer name
#
package PDF::Parser::Accueol;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use PDF::Parser::Stdf;
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
    	my $self	= shift;
    	my $infile	= shift;
    	my $limitdir	= shift;
    	my $limit_file	= shift;	
    	my $header	= new_headerLong;
    	my $wmap	= new_wmap;
   	 my $model	= new_model(
        {   header => $header,
            wmap   => $wmap,
            misc   => {},
            dataSource => 'ACCU'
        }
    	);
    	my ($wafer,$die) ;
    	my ( $columns, $rows );
    	my ( $x, $y, $deviceCount ) = ( 0, 0, 0 );
    	my %uniqueTest; 
    	my %binCount; 
    	my %waf_time;
    	my %dieH;
    	my $date;
	my $waferNum;
	my $dieNum;
	my $starttime;
	my $endtime;
	my $limit;
	my $limit_value = "true";

    	open( INFILE, $infile );
    	while (<INFILE>) {
        	s/[\r\n]+\z//;
        	$header->LOT(trim(uc($1))) if (/^LOT (.+)/);
        	if (/^TPN (.+) (.+)/){
           		$header->PROGRAM($1);
           		$header->REVISION($2);
        	}
        	if (/^TID (\S+) (\S+) (\S+)/){
           		$header->EQUIP1_ID("$1 $3");
        	}		
		if (/^OPE (.+)/){
	   		$header->OPERATOR("$1");
		}
		if (/^STA (.+)/){
	   		$header->EQUIP1_ID($header->EQUIP1_ID." $1");
		}
		if (/^OPR (.+)/){
	   		$header->STEP("$1");
		}
        	if (/^PBC (\S+)\s+(\S+)/){
           		$header->EQUIP3_ID("$1 $2");
        	}
        	if (/^DAT (.+)$/){
           		$date = trim($1);
        	}
        	if (/^TIM (.+)$/){
           		$header->START_TIME($date." ".$1);
        	}
        	if (/^WST\s(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/){
	   		$starttime = sprintf("%04d/%02d/%02d %02d:%02d:%02d",$1,$2,$3,$4,$5,$6);
        	}
        	if (/^WFN\s+(\d+)/){
	   		$waferNum = $1;
	   		$wafer = $model->find('wafers',{number => $waferNum});
	   		unless (defined $wafer){
				$wafer = new_wafer( { number => $waferNum } );
				$model->add('wafers',$wafer);
           		}
        	}
        	if (/^DIE\s+(\d+)/){
	   		$dieNum = $1;
        	}
        	if (/^POS\s+(\S+)\s+(\S+)/){
	   		$dieH{$waferNum}{$dieNum}{X} = $1;
	   		$dieH{$waferNum}{$dieNum}{Y} = $2;
        	}
        	if (/^VAL\s+(\d+)\s+(\S+)/){
	   		$waf_time{$waferNum}{START_T} = $starttime;
	   		#$dieH{$waferNum}{$dieNum}{$1} = $2;
	   		#unless (defined $uniqueTest{$1}){
				#$uniqueTest{$1} = 1;
			#}
	   		my $tnum = $1;
	   		my $res = $2;
	   		if ($res =~ /^-1e\+21/i){
                		$dieH{$waferNum}{$dieNum}{$tnum} = -1e+18;
           		}
	   		elsif ( $res =~ /^1e\+21/i){
                		$dieH{$waferNum}{$dieNum}{$tnum} = 1e+18;
           		}
           		else {
                		$dieH{$waferNum}{$dieNum}{$tnum} = $res;
           		}

	   		unless (defined $uniqueTest{$tnum}){
				$uniqueTest{$tnum} = 1;
	   		}
        	}
        	if (/^BIN\s+(\d+)/){
	   		$dieH{$waferNum}{$dieNum}{BIN} = $1;
	   		$binCount{$waferNum}{$1}++;
        	}
        	if (/^WFT\s(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/){
	   		$endtime = sprintf("%04d/%02d/%02d %02d:%02d:%02d",$1,$2,$3,$4,$5,$6);
	   		$waf_time{$waferNum}{END_T} = $endtime;
        	}
    	}
    	close(INFILE);

	#populate source lot for wafer name
	$header->populateSrcLot;

    	# Get Test Names from the limits file
    	my $revision = $header->REVISION ;
    	$revision =~ s/\s+//g;
    	INFO("Test Program: $header->{PROGRAM}");
    	INFO("Revision: $revision");
    	my $searchPath = "$limitdir/".$header->PROGRAM."_REV_".$revision."*";

    	#INFO($searchPath);
    	my ($limitfile) = glob($searchPath);
    	if ($limitfile eq "") {
		#$dpExit (4,"Test program not found!");
		$model->misc->{err_code} = 4;
		return $model;
    	}
		
    	unless (defined $limitfile) {
		$limit_value = "false"	;
		$$limit_file = "not";	 
    	}
			
    	if($limit_value =~ /true/){	
		INFO("Test Program found: $limitfile");
		$limit = $self->readLimitFile($limitfile);
		$$limit_file = $limitfile;
		#$model->tests($limit->tests);	
		$limit_value = "true";											  
    	} 

    	# Store test parameters into model	
    	foreach my $testNum (sort {$a<=>$b} keys %uniqueTest){
        	my $test = $limit->find('tests',{number => $testNum});
		#print "$testNum, "; 
		unless (defined $test) {
			#dpExit (4,"No test name in limit file for test number $testNum!");
			$model->misc->{err_code} = 1;
			return $model;
		}
		my $testName = $test->name;
		my $test = new_test({
 	   		number => $testNum,
	   		name => $testName,
        	});
       		$model->add('tests',$test);
    	}
	
    	# Store wafer start/end times into model
    	foreach my $wfn (sort {$a<=>$b} keys %waf_time) {
		my $wafer = $model->find('wafers',{number => $wfn});
		unless (defined $wafer){
			$wafer = new_wafer( { number => $wfn } );
			$model->add('wafers',$wafer);
		}
		$wafer->START_TIME($waf_time{$wfn}{START_T});
		if ($waf_time{$wfn}{END_T} eq "") {
			$wafer->END_TIME($waf_time{$wfn}{START_T});
		}
		else {
			$wafer->END_TIME($waf_time{$wfn}{END_T});
		}

    	}
	
    	# Store bin counts into model
    	foreach my $wfn (sort {$a<=>$b} keys %binCount) {   
		my $wafer = $model->find('wafers',{number => $wfn});
        	unless (defined $wafer){
                	$wafer = new_wafer( { number => $wfn } );
                	$model->add('wafers',$wafer);
        	}
		foreach my $binNum (sort {$a<=>$b} keys %{$binCount{$wfn}}) {
                	my $bin = new_bin;
                	$bin->number($binNum);
                	$bin->name(sprintf("BIN_%02d",$binNum));
                	$bin->count($binCount{$wfn}{$binNum});
                	$bin->PF(($binNum == 1) ? 'P' : 'F');
                	$wafer->add('bins',$bin);
        	}
    	}

    	# Store test results into model
    	foreach my $wfn (sort {$a<=>$b} keys %dieH) {
    		my $wafer = $model->find('wafers',{number => $wfn});

		if ($header->SOURCE_LOT ne "") {
                	$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
                }
		
		unless (defined $wafer){
			$wafer = new_wafer( { number => $wfn } );
			$model->add('wafers',$wafer);
		}
		foreach my $dieNum (sort {$a<=>$b} keys %{$dieH{$wfn}}) {
			next if $dieH{$wfn}{$dieNum}{BIN} eq ""; #skip if no BIN
			my $die = $model->find('dies',{site => $dieNum});
			unless (defined $die) {
				$die = new_die( {site => $dieNum});
				$wafer->add('dies',$die);
			}
			$die->site($dieNum);
			$die->x($dieH{$wfn}{$dieNum}{X});
			$die->y($dieH{$wfn}{$dieNum}{Y});
			$die->soft_bin($dieH{$wfn}{$dieNum}{BIN});
			my $cnt;
			foreach my $testNum (sort {$a<=>$b} keys %{$dieH{$wfn}{$dieNum}}) {
				$cnt++;
				$die->add('result', $dieH{$wfn}{$dieNum}{$testNum}) if $cnt > 3; #dont store first 3 values. 
			}
		}
    	}

    	return $model;
}

sub readLimitFile {
    	my $self   = shift;
    	my $infile = shift;
    	my $limit = new_limit;
    	$limit->conditionNames([qw/testCond PIN testType/]);
    	my $num = 0;
    	if ( $infile =~ /\.HP_LMT/ ) {
       		my $test;

       		open( INFILE, $infile );
       		while (<INFILE>) {
           		s/[\r\n]+\z//;
           		$num++;
           		if($num == 1){
              			$limit->REVISION($_);
           		}
           		if (/^Desc: File: (.+)\./){
              			$limit->PROGRAM($1);
           		}
           		if (/^\s*(\d+),(.+)/) {
	      			$test = new_test;
              			$test->number($1);
              			my @items= split(',',$2);
              			$test->name(trim($items[1]));
              			$test->LSL(trim($items[3]));
              			$test->HSL(trim($items[4]));
              			$test->LOL(trim($items[5]));
              			$test->HOL(trim($items[6]));
              			$test->units(trim($items[8]));
              			$test->add('conditions',(trim($items[2])));
              			$test->add('conditions',(trim($items[7])));
           		}
	   		if (/^\*\*\*\s\w.+/) {
	      			my @items= split /\s/, $_;
	      			$test->add('conditions',(trim($items[1])));
	      			$limit->add('tests',$test);
	   		}
       		}  
       		close(INFILE);
    
    	}
	elsif ( $infile =~ /\.DAT/ ) {
        	my $flag = 0;
		my $lnum = 0;
		my $line = "";
		my $i = 0;
		my $test;
		my $pin;
		my $testcond;

		open( INFILE, $infile );
		while ($line=<INFILE>) {
             		chomp;
	     		$lnum++;
	     		if ( $lnum == 1 ) {
				$limit->REVISION(trim($line));
	     		}
	     		if ( $line =~ /\*\*\*\s+\d.+/ ) {
				$flag = 1 ;
				$test = new_test;	
				my ($junk, $tnum, $tname, $junk) = split /\s+/, $line;
				$test->number(trim($tnum));
				$test->name(trim($tname));
	     		}
	     		if ( $flag == 1 ) {
				$i++;
				my ($item, $junk) = split /\s+\*/, $line;
				if ($i == 4) {
		   			my @tmp = split /\s/, $item;
		   			$pin = join ('_', @tmp);
				}
				elsif ($i == 5) {
		   			$testcond = trim($item);
		   			$testcond =~ s/,/ /g;
				}
				elsif ($i == 6) {
		   			my ($lcensor, $hcensor)  = split /\s+/, $item;
		   			$test->LOL(trim($lcensor));
		   			$test->HOL(trim($hcensor));
				}
				elsif ($i == 7) {
		   			my ($llim, $hlim) = split /\s+/, $item;
		   			$test->LSL(trim($llim));
		   			$test->HSL(trim($hlim));
				}
				elsif ($i == 10) {
		   			my ($unit, $tstype, @dump) = split /\s+/, $item, 3;
		   			$test->units(trim($unit));
					$test->add('conditions',$testcond);
		   			$test->add('conditions',(trim($pin)));
		   			$test->add('conditions',(trim($tstype)));
		   			$limit->add('tests',$test);
				}
				# stop parsing test items if test block line > 10
				elsif ($i > 10){
					$flag = 0;
					$i = 0;
				}
	     		}	
	     		#if ( $line =~ /^\s+$/ ) {
	     		#	$flag = 0;
	     		#	$i = 0;
	     		#}
		}    
		close(INFILE);
    	}
    	elsif ($infile =~ /\.STDF/) {
		my $TP_txt = convertBinToAscii($infile);
		my $test;
		my $testcond;
		my $pin;
		my $tstype;
		
		open( INFILE, $TP_txt );	
		while (my $line=<INFILE>) {
			if($line =~ /TEST_NUM=(.+)/) {
				$test = new_test;
				$test->number(trim($1));
			}
			elsif ($line =~ /UNITS=(.+)/) {
				$test->units(trim($1));
			}
			elsif ($line =~ /LO_LIMIT=(.+)/) {
				$test->LSL(trim($1));
			}
			elsif ($line =~ /HI_LIMIT=(.+)/) {
				$test->HSL(trim($1));
			}
			elsif ($line =~ /LO_CENSR=(.+)/) {
				$test->LOL(trim($1));
			}
			elsif ($line =~ /HI_CENSR=(.+)/) {
				$test->HOL(trim($1));
			}
			elsif ($line =~ /TEST_NAM=(.+)/) {
				$test->name(trim($1));
				$limit->add('tests',$test);
			}
			elsif ($line =~ /PIN\_\d\=(.+)/){
				$pin .= trim($1);
			}
			elsif ($line =~ /PARMTYP=(.+)/) {
				$tstype = trim($1);			
			}
			elsif ($line =~ /TCONDS=(.+)/) {
				$testcond = trim($1);
				$test->add('conditions', $testcond);
				$test->add('conditions', $pin);
				$test->add('conditions', $tstype);
				$limit->add('tests',$test);
				$pin = "";
				$tstype = "";
			}
		
		}
		close(INFILE);
		unlink $TP_txt unless (isLogDebug);

    	}
    	return $limit;
}
1;

