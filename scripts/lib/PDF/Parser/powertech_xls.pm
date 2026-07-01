# 01-Sep-2015  Saed    - Created
# 18-Sep-2015  Eric    - Change dataSource from powertech_xls to QTEC
# 			 Exit if PTX file is not found.
# 20-Oct-2015  Eric    - extract rev from last char from ppid	
# 20-Jun-2016  jgarcia - fixed bug that extract wrong lotid for DataFileName pattern -D:\Datalog\FDS8817NZ Cu HD G_GM4B40206N_ZC04YR4SWQ_FT_141115050433_M_SDTS1007081.plf-<> 
# 17-Aug-2016  RCyr      Strip tabs at end of lines.
# 13-Jan-2017  Eric	- added subroutine readFile_JCET
# 27-Mar-2017  Eric	- capture error & return model instead of exiting
# 18-Jun-2018  Eric	- added subroutine readFile_SZ
# 22-Jun-2018  Eric	- adjusted subroutine readFile_SZ. some XLS files have different format.
# 22-Nov-2019  Eric	- parse results correctly to fix "Site not found" error when loading
#
package PDF::Parser::powertech_xls;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use FindBin::libs;
use File::Basename qw/basename/;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;
use File::stat;
use Time::localtime;

use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";
my $testNum = 1;

my $attr = [];


############
# VARIABLES
############
our $file   	    = "";
my $lotno  	    = "";
my $dierun1         = "";
my $dierun2         = "";
my $tp     	    = "";
my $rev		    = "";
my $tester          = "";					
my %hoh             = ();
my $start_test_time = "";
my $td_filename     = "";
my $unit_count      = 0;
my $model_no        = "";
my $station_no      = "";
my $handler_no      = "";
my $test_date       = "";
my $load_brd	    = "";
my $dut_brd	    = "";
my $dummy = "";
my @dummy = ();
my @unit = ();
my $start = "";
my $j = "";
my $i = "";
my $unitno = "";
my $testno ="";
my $goodunitcount = "";
my @test_plan = ();
my %hotp = ();
my %hosb = ();
my %hohb = ();

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);
 

sub readFile {
	
    my @tp_unit  = ();
    my @tp_hl    = ();
    my @tp_ll    = ();
    my $readings = 0;						
    my $line     = "";
    my $hbin_flag= 0;
    my $sbin_flag= 0;
    my $data = {};
    my @ghr = ();
    my $testUnit = 1;
    my $self   = shift;
    my $infile = shift;
    my $tpdir = shift;
    my $header = new_headerLong;
    my $wmap   = new_wmap;
	
    my $model  = new_model(
        {   header => $header,
            wmap   => $wmap,		
            misc   => {},
            dataSource => 'QTEC'
        }
    );

	
    my $wafer = $model->find('wafers',{number => 0});	
	
	unless (defined $wafer){
		$wafer = new_wafer( { number => 0 } );
		$model->add('wafers',$wafer);		
	}	
	

	my @tp_unit  = ();
	my @tp_hl    = ();
	my @tp_ll    = ();
	my $readings = 0;						#<-- 1 MEANS "START READING TEST LOGS"
	my $line     = "";
	
	
	
    open (INFILE, "<",$infile) or die "can't open $file for parsing\n";
	while($line=<INFILE>)
	{
		$line =~ s/\cM\n/\n/g;			
		$line =~ s/\t+$//;
		chomp($line);

		###########
		# TESTERNO
		###########
		if ($line =~ /PowerTECH Test System/i)
		{
			$line     =~ s/ //g;
			@dummy = split /\:|\s|\t/, $line;
			$tester   = uc($dummy[4]);
			$tester    =~ s/ //g;
			$station_no   = uc($dummy[8]);
		}
		###########
		# TESTPLAN
		###########		
		elsif ($line =~ /DataFileName/i)
		{
			@dummy = split /\\/, $line;	
			my $arraysize = @dummy;
			$lotno    = uc($dummy[$arraysize-1]);
			if($lotno =~ /\s+/) {
				$tp    =~ s/ //g;
				@dummy = split /\_/, $lotno;
				$lotno = uc($dummy[1]);
				$lotno = substr($lotno, 0, 10);
			} else {
				$tp    =~ s/ //g;
				@dummy = split /\_/, $lotno;
				$lotno    = uc($dummy[0]);
				$lotno = substr($lotno, 0, 10);
			}
			
			#print "*** Lot_id = $lotno \n";
			INFO( "*** Lot_id = ".$lotno );
			$header->LOT($lotno);
		}
		elsif ($line =~ /TestFileName/i)
		{
			@dummy = split /\\|\./, $line;	
			my $arraysize = @dummy;
			$tp    = uc($dummy[$arraysize-2]);
			$tp    =~ s/ //g;
			$rev   = substr $tp, -1;
			$header->PROGRAM($tp);
			$header->REVISION($rev);
			my $tp_file = undef;

			#Read Bias values from test plan file
			#if ($tpdir eq "") {	
			#	$tpdir = "./TP/";
			#}
			#print "Test plan file is $tpdir \n";
			foreach my $file (glob "$tpdir/*.PTX") {
				if ($file =~ /$tp/i) {
				    INFO("TP Found: ".$file);
				    $tp_file = $file;
				}
			} 
			# return model if no tp found
			unless (defined $tp_file) {
				$model->misc->{err_msg} = 4;
				return $model;
			}
				
			#my $tp_file = $tpdir . "/" . $tp . ".PTX";
			open (TPFILE, "<",$tp_file) or die "can't open $tp_file for parsing\n";
			while($line=<TPFILE>)
			{
				$line =~ s/\cM\n/\n/g;			
				chomp($line);				
				my ($testno, @test_plan) = split /,/,$line;
				$hotp{$testno} = \@test_plan;
				$hosb{$test_plan[9]} = repNA($test_plan[9]);
				$hohb{$test_plan[10]} = repNA($test_plan[11]);
				
			}
			close(FILE);	
			
		}
		### TEST NAMES
		elsif ($line =~ /Item Name(.*)/){
			foreach ( split( /\t/, trim($1))  ) {
				my($no,$nameunit) = split / /, $_;
				my ($name, $unit) = split /\(|\)/ , $nameunit;
				if ($name ne "SAME")
				{
					if (trim($hotp{$testNum}[1]) ne ""){
						$name = $name . "_" . $hotp{$testNum}[1];}
					if (trim($hotp{$testNum}[2]) ne ""){
						$name = $name . "_" . $hotp{$testNum}[2];}
					if (trim($hotp{$testNum}[3]) ne ""){
						$name = $name . "_" . $hotp{$testNum}[3];}
				}
				$name =~ s/\s+//g;
				$unit = repNA($unit);
				my $test = new_test;				
				$test->number( $testNum );
				$test->name( repNA( $name) );
				$test->units( repNA( $unit) );
				$model->add( 'tests', $test );
				$testNum++;
				#next;

            		}		
		}
		elsif ($line =~ /Bias1(.*)/){
			@dummy = split( /\t/, trim($1));
			my $size = @dummy;
			my $total_tests = $testNum-1;			
			
			if ($total_tests == $size){
				$testNum= 0;
				foreach ( split( /\t/, trim($1))  ) {
					my $bias1 = repNA($_);
					my $testname = $model->tests->[$testNum]->name;
					if ($testname eq "SAME")
					{
						my($dummy,$testRef) = split /\=/, $_;
						my $newName = $model->tests->[$testRef-1]->name;
						my $newUnit = $model->tests->[$testRef-1]->units;
						$model->tests->[$testNum]->name( repNA($newName) );
						$model->tests->[$testNum]->units( repNA($newUnit) );
						
					}
					$testNum++;
					#next;

				}
			}
			
		}
        	elsif ($line =~ /Min Limit(.*)/) {
			$testNum= 0;
           		foreach ( split( /\t/, trim($1))  ) {
				my $field = trim($_);
				my($value,$unit) = split / /, $field;
				$unit = repNA($unit);
				$model->tests->[$testNum]->LSL(repNA($value));				
				$testNum++;
			}
		}
        	elsif ($line =~ /Max Limit(.*)/) {
			$testNum= 0;
           		foreach ( split( /\t/, trim($1))  ) {
				my $field = trim($_);
				my($value,$unit) = split / /, $field;
				$unit = repNA($unit);
				#$model->tests->[$testNum]->HSL(repNA($value));	
				my $lsl = $model->tests->[$testNum]->LSL;
				if ($lsl and $value ne "N/A")
				{
					if ($lsl < $value){
						$model->tests->[$testNum]->HSL(repNA($value));	
					}
					else{
						$model->tests->[$testNum]->LSL(repNA($value));
						$model->tests->[$testNum]->HSL(repNA($lsl));
						
					}
				}
				$testNum++;
			}
		}

		################
		# TEST READINGS
		################
		else
		{
			$line  =~ s/\'//g;
			my @readings = split /\s+/,$line;
			shift(@readings) unless $readings[0]=~/\d/;			#<-- REMOVE BLANK 

			print "=@readings=\n";
			if ($readings[0] =~ /^\d+?$/)		#<-- process line only if it starts with an integer	
			{

				my $site = $readings[0] if $readings[0]=~/\d/;
			
				my $die = $wafer->find('dies',{site=>$site});			
				unless (defined $die){
					$die = new_die( { site => $site } );
					$die->partid( $site );
					$die->x( "0" );
					$die->y( "0" );
					$wafer->add('dies',$die);
				}							

				my $phbin = $wafer->find('bins',{number=>$readings[2]}) if $readings[2] =~/\d/;			
				unless (defined $phbin){
					my $phbin = new_bin;
					$phbin->number($readings[2]);
					$phbin->name( "BIN_" . $readings[2]);
					if ($hohb{$readings[2]} ne "N/A"){
						$phbin->name( $hohb{$readings[2]});
					};
					
					if ($readings[1] eq "1"){
						#$phbin->name( "BIN_" . $readings[2]);
						$phbin->PF("P");
					}
					else{
						#$phbin->name( $readings[3]);
						#$phbin->name( "BIN_" . $readings[2]);						
						$phbin->PF("F");					
					}
					$wafer->add('bins',$phbin);
				}										

				$die->hard_bin($readings[2]);
				$die->soft_bin($readings[2]);
				
				$start = 3;
				
				$j=0;
				for $i($start..$#readings)
				{
					#print "$readings[$i] \t $unit[$j] \t";						
					if ($readings[$i] =~ /\d/) {
						$readings[$i] = $readings[$i];
					}else {
						$readings[$i] = "";
					}


					$die->add( 'result', repNA($readings[$i]) );
					
					$j++;
			
				}
				if (($#readings - $start) < ($testNum-1)){
				
					for $i(($#readings - $start)..($testNum-2))
					{
						$die->add( 'result', 'N/A');
					}
				}

				#############################				
				# STORES READING INTO A HASH
				#############################						
				$hoh{$readings[0]} = {
					    		LOG => \@readings
				          	     };	

				$unit_count++;
			}

		}
	}
	close(FILE);
	
	### GET LOAD BOARD & DUT BOARD
	#($load_brd, $dut_brd) = &get_board($file);

    return $model;
}

sub readFile_JCET {
	my $self   = shift;
	my $infile = shift;
	my $tstflg = 0;
	my $sumflg = 0;
	my $dtaflg = 0;
	my $resflg = 0;
	my $seqflg = 0;
	my $hbflg  = 0;
	my $sbflg  = 0;
	my $stname = "";
	my $tstrname ="";
	my $prog = "";
	my $rev = "";
	my @testnam = ();
	my @testnum = ();
	my @tunits = ();
	my @hilim = ();
	my @lolim = ();
	my @bias = ();
	my %sbin = {};
	my %hbcnt = {};
	my $fail_cnt = "";
	my $cont_cnt = "";
	my $total_pass = "";
	my $header = new_headerLong;
	my $wmap   = new_wmap;
	my $model  = new_model (
	{	header => $header,
		wmap   => $wmap,
		misc   => {},
		dataSource => 'QTEC'

	}
	);

	my $wafer = $model->find('wafers',{number => 0});
        unless (defined $wafer){
                $wafer = new_wafer( { number => 0 } );
                $model->add('wafers',$wafer);
        }


	my $fn = basename $infile;
	my @item = split /\_|\-/, $fn;
	$header->LOT($item[0]);
	
	open FH, $infile or die "can't open $infile\n";
	while(<FH>)
	{
		chomp;
		$_ =~ s/\s+$//g;
		my (@dummy) = split /\t/,$_; 
		&trim_spaces(\@dummy);
		#print "@dummy\n";
		if ($dummy[0] =~ /SerialNo\./i && $dummy[1] =~ /ItemName/i) {
			$tstflg = 0;
			$seqflg = 0;
			$hbflg  = 0;
			$sbflg  = 1;
			$dtaflg = 0;
		}elsif ($dummy[0] =~ /\*\*\*/ && $dummy[2] =~ /Datalog/i) {
			$tstflg = 0;
			$seqflg = 0;
			$hbflg  = 0;
			$sbflg  = 0;
			$dtaflg = 1;
		}elsif ($dummy[0] =~ /Serial#/i && $dummy[1] =~ /Bin/i) {
			$resflg = 1;
		}elsif ($dummy[0] =~ /Tester Name:/) {
			$tstrname = trim($dummy[3]);
		}elsif ($dummy[0] =~ /Station Name:/) {
			$stname = trim($dummy[3]);
			$header->EQUIP1_ID($tstrname." ".$stname);
		}elsif ($dummy[0] =~ /TestFileName:/) {
			my @item = split /\\|\./, $dummy[3];
			$prog = $item[2];
			$prog =~ s/V\d+$//i;
			$rev  = substr ($item[2], rindex($item[2], "V"));
			$rev  =~ s/^V//i;
			$header->PROGRAM($prog);
			$header->REVISION($rev);
		}elsif ($dummy[0] =~ /Device:/){
			$header->PRODUCT(trim($dummy[3]));
		}elsif ($dummy[0] =~ /Operator:/){
			$header->OPERATOR(trim($dummy[3]));
		}elsif ($dummy[0] =~ /^Test$/i ){
			@testnum = splice (@dummy,2);
		}elsif ($dummy[0] =~ /^Item$/i) {
			@testnam = splice (@dummy,2);
		}elsif ($dummy[0] =~ /Min Limit/i) {
			@lolim = splice (@dummy,2);
		}elsif ($dummy[0] =~ /Max Limit/i) {
			@hilim = splice (@dummy,2);
		}elsif ($dummy[0] =~ /Limit Units/i) {
			@tunits = splice (@dummy,2);
		}elsif ($dummy[0] =~ /Bias\s[1-9]$/i){
			my @item = splice (@dummy,2);
			for (my $i=0; $i<=$#item; $i++) {
				next if $item[$i] eq "";
				$bias[$i] .= " ".$item[$i];
			}
		}elsif ($dummy[0] =~ /Bias\s[1-9]\sValue$/i){
			my @item = splice (@dummy,2);
			for (my $i=0; $i<=$#item; $i++) {
				next if $item[$i] eq "";
				$bias[$i] .= "=".$item[$i];
			}
		}elsif ($dummy[0] =~ /Bias\s[1-9]\sUnits$/i){
			my @item = splice (@dummy,2);
			for (my $i=0; $i<=$#item; $i++) {
				next if $item[$i] eq "";
				$bias[$i] .= " ".$item[$i];
			}
		}elsif ($sbflg == 1 && $dummy[0] =~ /^\d+/) {
			my $bno = $dummy[0] + 1;
			$sbin{$bno} = {
				NAME => $dummy[1],
				CNT => $dummy[2]
			};
			$cont_cnt = $cont_cnt + $dummy[2] if $dummy[1] !~ /^CONT$|^K0$|^K1$|^K2$/i;
	
		}elsif ($sbflg == 1 && $dummy[0] =~ /^Fail\:/i) {
			$fail_cnt = $dummy[1];
		}elsif ($sbflg == 1 && $dummy[0] =~ /^Pass\:/i) {
			$total_pass = $dummy[1];
		}elsif ($resflg == 1) {
			my $die = new_die;
			$die->partid(trim($dummy[0]));
			$wafer->add('dies', $die);

			my $hbin = $wafer->find('hbins',{number=>$dummy[1]});
			unless (defined $hbin) {
				my $hbin = new_bin;
				$hbin->number($dummy[1]);
				$hbin->name("BIN_".$dummy[1]);

				if($dummy[1] == 5) {
					$hbin->PF("P");
				}
				else {
					$hbin->PF("F");
				}

				$wafer->add('hbins', $hbin);
			}

			$die->hard_bin($dummy[1]);

			for (my $i=2; $i<=$#dummy; $i++) {
				$die->add( 'result', repNA($dummy[$i]) )
			}
		}

	}
	close (FH);
	
	for (my $i=0; $i<=$#testnum; $i++) {
		my $test = new_test;
		$test->number(repNA(trim($testnum[$i])));
		$test->name(repNA(trim($testnam[$i])));
		$test->units(repNA(trim($tunits[$i])));
		$test->LSL(repNA(trim($lolim[$i])));
		$test->HSL(repNA(trim($hilim[$i])));
		$test->add('conditions', repNA(trim($bias[$i])));
		$model->add('tests', $test);
	}

	my $cont_cnt = $fail_cnt - $cont_cnt;
	foreach my $no ( sort {$a<=>$b} %sbin) {
		next if $sbin{$no} eq "";
		next if $sbin{$no}{NAME} =~ /^K[0-2]$/i;
		my $bin = $wafer->find('bins', {number=>1});
		unless (defined $bin) {
			my $bin = new_bin;
			$bin->number(1);
			$bin->name("PASS");
			$bin->count($total_pass);
			$bin->PF("P");		
			$wafer->add('bins', $bin);
		}

		my $bin = new_bin;
		$bin->number($no);
		$bin->name($sbin{$no}{NAME});
		if ($sbin{$no}{NAME} =~ /^CONT$/i) {
			$bin->count($cont_cnt);
		}else {
			$bin->count($sbin{$no}{CNT});	
		}	
		$bin->PF("F");
		$wafer->add('bins', $bin);
	}

return ($model);	

}


sub readFile_SZ {
	my $self = shift;
	my $infile = shift;
	my $tstflg = 0;
	my $sumflg = 0;
	my $dtaflg = 0;
	my $resflg = 0;
	my $seqflg = 0;
	my $hbflg  = 0;
	my $sbflg  = 0;
	my $sortnameflg = 0;
	my $stname = "";
	my $tstrname ="";
	my $prog = "";
	my $rev = "";
	my @testnam = ();
	my @testnum = ();
	my @tunits = ();
	my @hilim = ();
	my @lolim = ();
	my @bias = ();
	my %sbin = {};
	my %hbin = {};
	my %hbcnt = {};
	my %sbcnt = {};
	my $fail_cnt = "";
	my $cont_cnt = "";
	my $total_pass = "";
	my $header = new_headerLong;
	my $wmap   = new_wmap;
	my $model  = new_model (
	{	header => $header,
		wmap   => $wmap,
		misc   => {},
		dataSource => 'QTEC'

	}
	);

	my $wafer = $model->find('wafers',{number => 0});
        unless (defined $wafer){
                $wafer = new_wafer( { number => 0 } );
                $model->add('wafers',$wafer);
        }

	open FH, $infile or die "can't open $infile\n";
	while(<FH>)
	{
		chomp;
		$_ =~ s/\s+$//g;
		my (@dummy) = split /\t/,$_; 
		&trim_spaces(\@dummy);
		
		if ( $dummy[0] =~ /PowerTECH Test System/i ) {
			my $tester = trim($dummy[8]);
			my $serial = trim($dummy[3]);
			my $station = trim($dummy[6]);
			$header->EQUIP1_ID($tester." ".$station." ".$serial);
		}
		elsif ( $dummy[0] =~ /DataFileName:/i ) {
		 	#print "@dummy\n";
		}
		elsif ( $dummy[0] =~ /TestFileName:/i ) {
			my @item = split /\\|\./, $dummy[2];
			$header->PROGRAM(trim($item[$#item-1]));
		}
		elsif ( $dummy[0] =~ /Device:/i ) {
			$header->PRODUCT(trim($dummy[2]));
		}
		elsif ( $dummy[0] =~ /Lot:/i ) {
			$header->LOT(trim($dummy[2]));
		}
		elsif ( $dummy[0] =~ /Tested:/i ) {
			my @item = split /\/|\s/i, $dummy[1];
			my $date_time = $item[2]."/".$item[0]."/".$item[1]." ".$item[3].":00";
			$header->START_TIME($date_time);
			$header->END_TIME($date_time);
		}
		elsif ( $dummy[0] =~ /Revision:/i ) {
			$header->REVISION(trim($dummy[1]));
		}	
		elsif ( $dummy[0] =~ /Item Name/i ) {
			my @item = ();
			if ($dummy[3] eq "") {
				$sortnameflg = 1;
				@item = splice (@dummy, 4);
			}
			else {
				$sortnameflg = 0;
				@item = splice (@dummy, 3);
			}

			for (my $i=0; $i<=$#item; $i++) {
				my ($num,$nam) = split /\s/, $item[$i];
				push @testnum, $num;
				push @testnam, $nam;		
			}
		}
		elsif ( $dummy[0] =~ /Bias[1-9]/i) {
			my @item = ();
			if ($sortnameflg == 1) {
                                @item = splice (@dummy, 4);
                        }
                        else {
                                @item = splice (@dummy, 3);
                        }	
		
			for (my $i=0; $i<=$#item; $i++) {
				next if $item[$i] eq "";
				$bias[$i] .= " ".$item[$i];
			}	
		}
		elsif ( $dummy[0] =~ /Min Limit/i ) {
			my @item = ();
			if ($sortnameflg == 1) {
                                @item = splice (@dummy, 4);
                        }
                        else {
                                @item = splice (@dummy, 3);
                        }
			
			for (my $i=0; $i<=$#item; $i++) {
				my ($val, $unit) = split /\s/, $item[$i];
				push @lolim, $val;
			}
		}
		elsif ( $dummy[0] =~ /Max Limit/i ) {
			my @item = ();
                        if ($sortnameflg == 1) {
                                @item = splice (@dummy, 4);
                        }
                        else {
                                @item = splice (@dummy, 3);
                        }
		
			for (my $i=0; $i<=$#item; $i++) {
				my ($val, $unit) = split /\s/, $item[$i];
				push @hilim, $val;
			}
		}	
		elsif ( $dummy[0] =~ /Min Result/i ) {
			#print "@dummy\n";
		}
		elsif ( $dummy[0] =~ /Max Result/i ) {
			#print "@dummy\n";	
		}
		elsif ( $dummy[0] =~ /Average/i ) {
			#print "@dummy\n";
		}
		elsif ( $dummy[0] =~ /STD DEV/i ) {
			#print "@dummy\n";
		}
		elsif ( $dummy[0] =~ /Serial#/i && $dummy[1] =~ /S#/i && $dummy[2] =~ /Bin#/i ) {
			$resflg = 1;
			my @item = ();
                        if ($sortnameflg == 1) {
                                @item = splice (@dummy, 4);
                        }
                        else {
                                @item = splice (@dummy, 3);
                        }
			
			for (my $i=0; $i<=$#item; $i++) {
				$item[$i] = trim($item[$i]);
				push @tunits, $item[$i];
			}
		}
		elsif ( $resflg == 1 && $dummy[0] =~ /^\d/) {
			my @results - ();
			if ($sortnameflg == 1) {
				@results = splice (@dummy, 4);
			}
			else {
				@results = splice (@dummy, 3);
			}

			my $die = new_die;
			$die->partid(trim($dummy[0]));
			$die->site(trim($dummy[0]));
			$wafer->add('dies', $die);
			
			$hbcnt{$dummy[2]}++;
			$sbcnt{$dummy[1]}++;	

			my $sbin = $wafer->find('sbins',{number=>$dummy[1]});
			unless (defined $sbin) {
				$sbin = new_bin;
				$wafer->add('sbins', $sbin);
			}
			$sbin->number($dummy[1]);
			$sbin->name(($sortnameflg == 1) ? $dummy[3] : "BIN".$dummy[1]);
			$sbin->count($sbcnt{$dummy[1]});
			if($dummy[1] == 1 ) {
				$sbin->PF("P");
			}
			else {
				$sbin->PF("F");
			}

			$die->soft_bin($dummy[1]);

			my $hbin = $wafer->find('hbins',{number=>$dummy[2]});
                        unless (defined $hbin) {
                                $hbin = new_bin;
                                $wafer->add('hbins', $hbin);
                        }

			$hbin->number($dummy[2]);
			$hbin->name(($sortnameflg == 1) ? $dummy[3] : "BIN".$dummy[2]);
                        $hbin->count($hbcnt{$dummy[2]});

                        if($dummy[2] == 1 ) {
                               $hbin->PF("P");
                        }
                        else {
                               $hbin->PF("F");
                        }

                        $die->hard_bin($dummy[2]);

			for (my $i=0; $i<=$#results; $i++) {
				$die->add( 'result', repNA($results[$i]) );
			}
		}

	
	}
	close FH;


	for (my $i=0; $i<=$#testnum; $i++) {
		my $test = new_test;
		$test->number(repNA(trim($testnum[$i])));
		$test->name(repNA(trim($testnam[$i])));
		$test->units(repNA(trim($tunits[$i])));
		$test->LSL(repNA(trim($lolim[$i])));
		$test->HSL(repNA(trim($hilim[$i])));
		$test->add('conditions', repNA(trim($bias[$i])));
		$model->add('tests', $test);

		
	}


return $model;
}


# REMOVE SPACES FROM VALUES IN THE ARRAY
sub trim_spaces
{
        my $addr = shift;
        for(my $i=0; $i <= $#{$addr}; $i++)
        {
                ${$addr}[$i] =~ s/^\s+|\s+$//g; #corrected to remove more spaces
        }
}

1
