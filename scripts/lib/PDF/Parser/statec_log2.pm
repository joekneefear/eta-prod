# 18-Aug-2015  Saed    - Created
# 11-Sep-2015  Eric    - change dataSource from statec_log_cpft to STATEC
# 08-Oct-2915 jgarcia  - modified to accomodate atec_ph log2 file's header portion
#			which is different from other site. 
#                       temporarily assigned test flow code into $header->INDEX1.
# 29-Jun-2015 Eruc     - added option for bkrel data loading.
# 07-Mar-2019 jgarcia -  addes support for new tester that place lotid to different field name (Lot Id).
# 22-Nov-2019 Eric	-  removed invalid chars in results seciton for ATEC to fix the no partid error when loading
# 26-Nov-2019 Eric	- fixed to handle another variant of log2 file format

package PDF::Parser::statec_log2;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use FindBin::libs;
use File::Basename qw/basename/;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

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
my $tp_rev = "";
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
my $testFlow = "";
my $dup_ctr = 0;
my %seen;

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

sub readFile {
	
	my @tp_unit  = ();
	my @tp_hl    = ();
	my @tp_ll    = ();
	my $readings = 0;						#<-- 1 MEANS "START READING TEST LOGS"
	my $line     = "";
	my $hbin_flag= 0;
	my $sbin_flag= 0;
    	my $data = {};
    	my @ghr = ();
	my $testUnit = 1;
    	my $self   = shift;
    	my $infile = shift;
    	my $isLogDebug = shift;
    	my $site = shift;
    	my $header = new_headerLong;
	my $wmap   = new_wmap;
	
    	my $model  = new_model(
        {   header => $header,
	    wmap   => $wmap,		
            misc   => {},
            dataSource => 'STATEC'
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
		chomp($line);

		if($site eq "atec_ph_ft") {
			if ($line =~ /System/i)
			{
				$line     =~ s/ //g;
				($dummy, $model_no) = split /\:|\[|\-|\_|\]/, $line;
				$model_no   = uc($model_no);
				$header->EQUIP1_ID($model_no);
			}
			if($line =~ /Station/i) {
				@dummy = split /\:/, $line;
        			$station_no    = uc($dummy[1]);
				$station_no    =~ s/\D//g;
        			$station_no    =~ s/ //g;
        			$header->EQUIP2_ID($station_no);
			}
			elsif ($line =~ /Handler/i)
       			{
       				@dummy = split /\:/, $line;
        			$handler_no    = uc($dummy[1]);
        			$handler_no    =~ s/ //g;
        			$header->EQUIP5_ID($handler_no);
       			}
			elsif ($line =~ /Job_Name/i)
			{
				@dummy = split /\:/, $line;	
				$tp    = uc($dummy[1]);
				$tp    =~ s/ //g;
				my @array_value = split /\_/, $tp;
        			foreach my $element (@array_value) {
        				$element =~ s/^\s+|\s+$//g;
          				if($element =~ /^SR\d{1,}/) {
          					$element =~ m/SR(\d+)/;
            					$tp_rev = $1;
            					last;
          				}
        			}
        			$header->PROGRAM($tp);	
        			$header->REVISION($tp_rev);

			}
			elsif ($line =~ /Lot(_|\s+)?Id/i)
			{
				@dummy    = split /\:/, $line;	
				$dummy[1] = uc($dummy[1]);
				$dummy[1] =~ s/ //g;
				($lotno,$dierun1,$dierun2) = split /\_/, $dummy[1];
				if($lotno ne "") {
					$header->LOT($lotno);
					$header->SOURCE_LOT($lotno);
				}
				
			}
			elsif ($line =~ /Lot(_|\s+)?No/i)
			{
				@dummy    = split /\:/, $line;	
				$dummy[1] =~ s/^\s+|\s+$//g;
				(my $dump, $testFlow) = split /\_/, $dummy[1];
				$testFlow =~ s/ //g;
				$header->INDEX1($testFlow);
			}
			elsif ($line =~ /Item (.*)/)
			{
           			foreach ( split( /\'/, trim($1))  ) {
					my $test = new_test;				
					$test->number( $testNum );
					$test->name( repNA( $_ ) );
					$model->add( 'tests', $test );
					$testNum++;

           			}		
			}
			elsif ($line =~ /Unit(.*)/){
				$testNum= 0;
				foreach ( split( /\'/, trim($1) )) {
					$model->tests->[$testNum]->units(repNA($_));
					$testNum++;
				}
	
			}
    			elsif ($line =~ /HL(.*)/) {
				$testNum= 0;
				foreach ( split( /\'/, trim($1) ) ) {
					$model->tests->[$testNum]->HSL(repNA($_));				
					$testNum++;				
				}
			}
    			elsif ($line =~ /LL(.*)/) {
				$testNum= 0;
				foreach ( split( /\'/, trim($1) ) ) {
					$model->tests->[$testNum]->LSL(repNA($_));		
					$testNum++;				
				}
			}		
			elsif ($line =~ /Report\s+\:/)
			{
				my @dummy = split /\s{2,}/, $line;
				$dummy[3] =~ s/ //g;                            #<-- DATE
				$dummy[4] =~ s/ //g;                            #<-- TIME
				$wafer->START_TIME($dummy[3] . " " . $dummy[4]);
				###Oct-20-2015 jgarcia - as per YC report date is start time not end time.. thus assigned only in start_time.
				###$wafer->END_TIME($dummy[3] . " " . $dummy[4]);
			}
			else
			{
				$line  =~ s/\'//g;
				my @readings_temp = split /\s+/,$line;
                                my @readings = ();
                                my @values = grep !/\*F\*|\*FA\*/, @readings_temp;
                                push @readings, @values;
                                shift(@readings) unless $readings[0]=~/\d/;
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
					my $phbin = $wafer->find('bins',{number=>$readings[1]});	
					unless (defined $phbin){
						my $phbin = new_bin;
						$phbin->number($readings[1]);
						if ($readings[2] eq "PASS"){
							$phbin->name( "BIN_" . $readings[1]);
							$phbin->PF("P");
						}
						else{
							$phbin->name( "BIN_" . $readings[1]);						
							$phbin->PF("F");					
						}
						$wafer->add('bins',$phbin);
					}										

					$die->hard_bin($readings[1]);
					$die->soft_bin($readings[1]);
				
					if ($readings[2] eq "PASS") 	#<-- IF PASS, READING STARTS AT ARRAY 3
					{
						$start = 3;
					}
					elsif ($readings[3] eq "PASS")
					{
						$start = 4;		
					}
					elsif ($readings[2] eq "FAIL")				#<-- IF FAIL, READING STARTS AT ARRAY 4
					{
						$start = 3;
					}
					elsif ($readings[3] eq "FAIL")
					{
						$start = 4;
					}
				
					$j=0;
					for $i($start..$#readings)
					{
						$readings[$i] =	($readings[$i]) if $readings[$i]=~/\d/;
						$die->add( 'result', repNA($readings[$i]) ) if $readings[$i]=~/\d/;
						$j++;
					}
					if (($#readings - $start) < ($testNum-1)){
						for $i(($#readings - $start)..($testNum-1))
						{
							$die->add( 'result', 'N/A');
						}
					}

					$hoh{$readings[0]} = {
						LOG => \@readings
				        };	

					$unit_count++;
				}
			}
			
		} ### END OF IF STATEMENT FOR ATEC_PH_FT_STATEC SITE ###
		elsif ( $site eq "bkrel") {
			if ($line =~ /System/i)
			{
				$line     =~ s/ //g;
				($dummy, $model_no,$station_no,$handler_no) = split /\:|\-|\//, $line;
				$model_no   = uc($model_no);
				$handler_no = uc($handler_no);
				$header->EQUIP1_ID($model_no);
				$header->EQUIP5_ID($station_no . $handler_no);
			}
			elsif ($line =~ /Job_Name/i)
			{
				@dummy = split /\:/, $line;	
				$tp    = uc($dummy[1]);
				$tp    =~ s/ //g;
				$header->PROGRAM($tp);		
			}
			elsif ($line =~ /Dvc_Name/i)
			{
				@dummy = split /\:/, $line;	
				my $prod    = uc($dummy[1]);
				$prod    =~ s/ //g;
				$header->PRODUCT($prod);						
			}
			elsif ($line =~ /Lot(_|\s+)?No/i)
			{
				@dummy    = split /\:/, $line;	
				$dummy[1] = uc($dummy[1]);
				$dummy[1] =~ s/ //g;
				($lotno,$dierun1,$dierun2) = split /\_/, $dummy[1];
				if($lotno ne "") {
					$header->LOT($lotno);
					$header->SOURCE_LOT($lotno);
				}
				
			}
			elsif ($line =~ /Item (.*)/){
		           	foreach ( split( /\'/, trim($1))  ) {
					my $test = new_test;				
					$test->number( $testNum );
					$test->name( repNA( $_ ) );
					$model->add( 'tests', $test );
					$testNum++;
		            	}		
			}
			elsif ($line =~ /Unit(.*)/){
				$testNum= 0;
				foreach ( split( /\'/, trim($1) )) {
					$model->tests->[$testNum]->units(repNA($_));
					$testNum++;
				}
			}
        		elsif ($line =~ /HL(.*)/) {
				$testNum= 0;
				foreach ( split( /\'/, trim($1) ) ) {
					$model->tests->[$testNum]->HSL(repNA($_));				
					$testNum++;				
				}
			}
        		elsif ($line =~ /LL(.*)/) {
				$testNum= 0;
				foreach ( split( /\'/, trim($1) ) ) {
					$model->tests->[$testNum]->LSL(repNA($_));		
					$testNum++;				
				}
			}		
			elsif ($line =~ /Report\s+\:/)
			{
				my @dummy = split /\s{2,}/, $line;
				$dummy[3] =~ s/ //g;                            #<-- DATE
				$dummy[4] =~ s/ //g;                            #<-- TIME
				$wafer->START_TIME($dummy[3] . " " . $dummy[4]);
				$wafer->END_TIME($dummy[3] . " " . $dummy[4]);
			}
			elsif ( $line =~ /No\.\s+Bin\s+(Time\[s\])\s+Result\s+Fail_Item/ )
			{
				$testNum++;
				my $test = $model->find ('tests', {number => $testNum});
            			unless (defined $test){
                			my $test = new_test;
                			$test->number($testNum);
                			$test->name($1);
                			$test->units('sec');
                			$model->add( 'tests', $test );
            			}
			}
			else
			{
				$line  =~ s/\'//g;
				#my @readings = split /\s+/,$line;
				#some files have *F* or *FA* on the results
				my @readings_temp = split /\s+/,$line;
				my @readings = ();
				my @values = grep !/\*F\*|\*FA\*/, @readings_temp;
                        	push @readings, @values;
				shift(@readings) unless $readings[0]=~/\d/;			#<-- REMOVE BLANK
				if ($readings[0] =~ /^\d+?$/)		#<-- process line only if it starts with an integer	
				{
					# check duplicate partid
					if ($seen{$readings[0]}++) {
                				$dup_ctr++;
            				}

					my $site = $readings[0] if $readings[0]=~/\d/;
					my $die = $wafer->find('dies',{site=>$site});			
					unless (defined $die){
						$die = new_die( { site => $site } );
						$die->partid( $site );
						$die->x( "0" );
						$die->y( "0" );
						$wafer->add('dies',$die);
					}							
					my $phbin = $wafer->find('bins',{number=>$readings[1]});	
					unless (defined $phbin){
						my $phbin = new_bin;
						$phbin->number($readings[1]);
						if ($readings[3] eq "PASS"){
							$phbin->name( "BIN_" . $readings[1]);
							$phbin->PF("P");
						}
						else{
							$phbin->name( "BIN_" . $readings[1]);						
							$phbin->PF("F");					
						}
						$wafer->add('bins',$phbin);
					}										
		
					$die->hard_bin($readings[1]);
					$die->soft_bin($readings[1]);
						
					if ($readings[3] eq "PASS")	#<-- IF PASS, READING STARTS AT ARRAY 4
					{
						$start = 4
					}
					else				#<-- IF FAIL, READING STARTS AT ARRAY 5
					{
						$start = 5
					}

					# empty results to remove prev values of duplicate partid
            				@{$die->result} = () if $dup_ctr > 0;
						
					$j=0;
					for $i($start..$#readings)
					{
						$readings[$i] =	($readings[$i]) if $readings[$i] =~ /\d/;
						#$die->add( 'result', repNA($readings[$i]) ) if $readings[$i] =~ /\d/;
						#some test names have digits
						$die->add( 'result', repNA($readings[$i]) ) if $readings[$i] =~ /\d/ && $readings[$i] !~ /[A-Z]/i;
						$j++;
					}
					if (($#readings - $start) < ($testNum-2)){ # do if few tests done
						for $i(($#readings - $start)..($testNum-2))
						{
							if ($i == ($testNum - 2)){
								$die->add( 'result', repNA($readings[2]));# add time result at the end
							}
							else {
								$die->add( 'result', 'N/A');
							}	
						}
					}
					else { # add time result at the end
						$die->add( 'result', repNA($readings[2]) );
					}

					$hoh{$readings[0]} = {
				    		LOG => \@readings
				      	};	
		
					$unit_count++;
					$dup_ctr = 0;
				}
			}
		}### END OF BK REL	
		else {
			if ($line =~ /System/i)
			{
				$line     =~ s/ //g;
				($dummy, $model_no,$station_no,$handler_no) = split /\:|\-|\//, $line;
				$model_no   = uc($model_no);
				$handler_no = uc($handler_no);
				$header->EQUIP1_ID($model_no);
				$header->EQUIP5_ID($station_no . $handler_no);
			}
			elsif ($line =~ /Job_Name/i)
			{
				@dummy = split /\:/, $line;	
				$tp    = uc($dummy[1]);
				$tp    =~ s/ //g;
				$header->PROGRAM($tp);		
			}
			elsif ($line =~ /Dvc_Name/i)
			{
				@dummy = split /\:/, $line;	
				my $prod    = uc($dummy[1]);
				$prod    =~ s/ //g;
				$header->PRODUCT($prod);						
			}
			elsif ($line =~ /Lot(_|\s+)?No/i)
			{
				@dummy    = split /\:/, $line;	
				$dummy[1] = uc($dummy[1]);
				$dummy[1] =~ s/ //g;
				($lotno,$dierun1,$dierun2) = split /\_/, $dummy[1];
				if($lotno ne ""){
					$header->LOT($lotno);
					$header->SOURCE_LOT($lotno);
				}
				
					
			}
			elsif ($line =~ /Item (.*)/)
			{
		           	foreach ( split( /\'/, trim($1))  ) {
					my $test = new_test;				
					$test->number( $testNum );
					$test->name( repNA( $_ ) );
					$model->add( 'tests', $test );
					$testNum++;
		            	}		
			}
			elsif ($line =~ /Unit(.*)/)
			{
				$testNum= 0;
				foreach ( split( /\'/, trim($1) )) {
					$model->tests->[$testNum]->units(repNA($_));
					$testNum++;
				}
			
			}
        		elsif ($line =~ /HL(.*)/) 
			{
				$testNum= 0;
				foreach ( split( /\'/, trim($1) ) ) {
					$model->tests->[$testNum]->HSL(repNA($_));				
					$testNum++;				
				}
			}
        		elsif ($line =~ /LL(.*)/) {
				$testNum= 0;
				foreach ( split( /\'/, trim($1) ) ) {
					$model->tests->[$testNum]->LSL(repNA($_));		
					$testNum++;				
				}
			}		
			elsif ($line =~ /Report\s+\:/)
			{
				my @dummy = split /\s{2,}/, $line;
				$dummy[3] =~ s/ //g;                            #<-- DATE
				$dummy[4] =~ s/ //g;                            #<-- TIME
				$wafer->START_TIME($dummy[3] . " " . $dummy[4]);
				$wafer->END_TIME($dummy[3] . " " . $dummy[4]);
				}
			else
			{
				$line  =~ s/\'//g;
				my @readings = split /\s+/,$line;
				shift(@readings) unless $readings[0]=~/\d/;			#<-- REMOVE BLANK
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
					my $phbin = $wafer->find('bins',{number=>$readings[1]});	
					unless (defined $phbin){
						my $phbin = new_bin;
						$phbin->number($readings[1]);
						if ($readings[2] eq "PASS"){
							$phbin->name( "BIN_" . $readings[1]);
							$phbin->PF("P");
						}
						else{
							$phbin->name( "BIN_" . $readings[1]);						
							$phbin->PF("F");					
						}
						$wafer->add('bins',$phbin);
					}										
		
					$die->hard_bin($readings[1]);
					$die->soft_bin($readings[1]);
						
					if ($readings[2] eq "PASS")	#<-- IF PASS, READING STARTS AT ARRAY 3
					{
						$start = 3
					}
					else				#<-- IF FAIL, READING STARTS AT ARRAY 4
					{
						$start = 4
					}
						
					$j=0;
					for $i($start..$#readings)
					{
						$readings[$i] =	($readings[$i]) if $readings[$i]=~/\d/;
						$die->add( 'result', repNA($readings[$i]) ) if $readings[$i]=~/\d/;
						$j++;
					}
					if (($#readings - $start) < ($testNum-1))
					{
						for $i(($#readings - $start)..($testNum-1))
						{
							$die->add( 'result', 'N/A');
						}
					}
		
					$hoh{$readings[0]} = {
				    		LOG => \@readings
				     	};	
		
					$unit_count++;
				}
		
			}
		}### END OF ELSE 
	}
	close(FILE);
	
#######################
# MOVE FILE TO BAD DIR
# (FOR SOLARIS ONLY)
#######################
sub move_file_to_bad_dir
{
        my $loc_file = shift;
        my $loc_dir  = shift;
        my $fn       = ($loc_file=~/\//) ? substr($loc_file, rindex($loc_file,"/")+1) : $loc_file;
        system "mkdir $loc_dir" if ! -e $loc_dir;
        system "mv $loc_file $loc_dir";
        if (! -e "${loc_dir}/${fn}")
        {
                print "Failed to move $loc_file to $loc_dir dir. $!\n";
                exit 1;
        }
}

######################
# BASE UNIT CONVERTER
######################
sub convert_to_base_unit
{
	my $reading    = shift;
	my $unit       = shift;
	my $multiplier = 1;

 	#print "$reading - $unit\n";

	if ($unit =~ /^p/i)
	{
		$multiplier = 1e-12;
	}
	elsif ($unit =~ /^n/i)
	{
		$multiplier = 1e-9;
	}
	elsif ($unit =~ /^u/i)
	{
		$multiplier = 1e-6;
	}
	elsif ($unit =~ /^m/i)
	{
		$multiplier = 1e-3;
	}
	elsif ($unit =~ /^K/i)
	{
		$multiplier = 1e3;
	}

 	#print "$multiplier\n";
		

	return($reading * $multiplier);
}

    return $model;
}
1
