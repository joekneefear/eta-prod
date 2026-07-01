# 2015-Aug-26 Gilbert - Uppercase the lot id.
# 2017-Apr-11 jgarcia - modified to not call dpExit if there is issues with the raw file like
#                       no lotid, no testplan and no part data. just initialize $model->misc with
#                       the appropriate error messages and return the model.
# 2018-Jan-16 Eric    - added error msg for invalid bin number for failed soft bins
# 2018-Oct-31 Eric    - added subroutines check2DScam and read2DFile 
# 07-Mar-2019 jgarcia -  addes support for new tester that place lotid to different field name (Lot Id).
package PDF::Parser::SPM_LOG2;
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
    	my $retest_flag = "N";
	my $nothing = undef;	
	my @parameter = ();
	my @lolim = ();
	my @hilim = ();
	my @unit = ();
	my $tp = "";
	my $lotno = "";
	my $line = undef;
	my @values = ();
        my $tp_rev = "";
	my $entity_type = "";
	my $entity_no = "";
	my $with_test_readings = 0;	# 0 if none. 1 if available.
	my %binhash = ();
	my %binnamehash = ();
    	my $header = new_headerLong;
    	my $wmap   = new_wmap;
    	
	my $model  = new_model({
	   	header => $header,
            	wmap   => $wmap,
            	misc   => {},
            	dataSource => 'SPM'
        });
    	
	my $wafer = new_wafer;
    	$model->add( 'wafers', $wafer );
	
	my $phbin = new_bin;
	$phbin->number( 1 );
	$phbin->name("PASS");
	$phbin->PF("P");
    	$phbin->count(-1);
	$wafer->add( 'hbins', $phbin );
	
	my $psbin = new_bin;
	$psbin->number( 1 );
	$psbin->name("PASS");
	$psbin->PF("P");
    	$psbin->count(-1);
	$wafer->add( 'sbins', $psbin );
  
    	open( INFILE, $infile );
    	while ($line=<INFILE>) {
		$line =~ s/\cM\n/\n/g;			
		chomp($line);
		$line  =~ s/\'//g;
		$line  =~ s/^\s+|\s$//g;
		
        	# TEST READINGS
		if ($line =~ /^\d{1,}\s+\d/) 
        	{
			my @readings_temp = split /\s+/,$line;
			my @readings = ();
			@values = grep !/\*F\*|\*FA\*/, @readings_temp;
			push @readings, @values;
			
			#print "@readings\n";
			my $unitid   = shift(@readings);
			my $binnumber = shift(@readings);
			my $timevalue = shift(@readings);
			
			# REMOVE UNWANTED(IN-BETWEEN) VALUES 
			my $dummy = "";
			do
			{
				$dummy = shift(@readings);
			} until ($dummy =~ /FAIL|PASS/i || $#readings == -1);
			
			#i SKIP UNIT DATA IF NO PASS/FAIL FLAG
			next if $#readings == -1;
			
			if(($binnumber != 1) && !defined($binhash{$binnumber})){
				my $bin = new_bin;
				$bin->number( $binnumber );
				$bin->name(sprintf("HWBIN_%02d",$binnumber));
				$bin->PF(substr($dummy,0,1));
				$bin->count(-1);
				$binhash{$binnumber} = $bin;
				
			}
			
			my $binname = undef;
			my $testnumber = -1;
			
			if($readings[0] =~ /^\d+/  || $dummy =~ /PASS/){
				#do nothing       
			}
			else{
			        $binname = shift(@readings);
				if(defined($binnamehash{$binname})){
					$testnumber = $binnamehash{$binname};
				}
				else{
				    	for(my $i=0; $i<=$#parameter; $i++){
						if($binname eq $parameter[$i]){
						    	$testnumber = $i+2;
							last;
						}
				    	}
					$binnamehash{$binname} = $testnumber;
				    	
				   }
				
				if ($testnumber == -1 && $binname ne "") {
					$model->{misc} = "INVALID_SOFT_BIN = $testnumber $binname";
				}
			}
			
			# CONVERT TEST READINGS TO BASE UNIT
			# NOTE: SOMETIMES, DATALOG HAS MORE TEST RESULTS COLUMNS THAN PARAMTERS
			my $die = new_die;
			$die->partid($unitid);
			$die->hard_bin($binnumber);
			
			if($dummy =~ /PASS/){
				$die->soft_bin(1);
			}else{
				if ( $testnumber > 0 ){
					$die->soft_bin($testnumber);
				}
			}
			$die->add('result',$timevalue);
			for (my $i=0; $i<=$#parameter; $i++)
            		{
				if($i <= $#readings){
					$die->add('result',$readings[$i]);
					
				}else{
					$die->add('result',"N/A");
				}
				$with_test_readings = 1;
            		}
			
            		$wafer->add( 'dies', $die );
		}
        	# PARAMETER NAME 
        	elsif ($line =~ /^Item\s+/i)
        	{
            		@parameter = split /\s+/, $line;
            		shift(@parameter); #<-- REMOVES THE "Item" WORD
        	}
        	# LOWER LIMIT
        	elsif ($line =~ /LL/)
        	{
            		@lolim = split /\s+/, $line;
            		shift(@lolim);  #<-- REMOVES THE "LL" WORD
        	}
        	# UPPER LIMIT
        	elsif ($line =~ /HL/)
        	{
            		@hilim = split /\s+/, $line;
            		shift(@hilim);  #<-- REMOVES THE "HL" WORD
        	}
		# TEST UNITS
		elsif ($line =~ /Unit/i)
		{
			@unit = split /\s+/, $line;
  			shift(@unit);	#<-- REMOVES "Unit"

			# STORE TESTPLAN INTO A HASH
			my $ttest = new_test;
			$ttest->number( 0 );
			$ttest->name("Time");
			$ttest->units("s");
			$wafer->add('tests', $ttest );
			
			for(my $i=0; $i<=$#parameter; $i++)
			{
				$parameter[$i] =~ s/ //g;
				$hilim[$i] =~ s/ //g;
				$lolim[$i] =~ s/ //g;
				$unit[$i] =~ s/\s|\-//g;	
				my $test_num = $i+1;
				
				my $test = new_test;
				$test->number( $test_num );
				$test->name( uc($parameter[$i]));
				$test->units($unit[$i]);
				
				$test->LSL($lolim[$i]);
				$test->HSL($hilim[$i]);
				$wafer->add('tests', $test );

				my $sbin = new_bin;
				$sbin->number($test_num+1);
				$sbin->name(uc($parameter[$i]));
				$sbin->PF("F");
				$sbin->count(-1);
				$wafer->add('sbins',$sbin);
			}
		}
        	elsif ( $line =~ /System/i ) {
			# specific for suzhou spm tester tester model name starts with SPM
			if($line =~ /SPM/i) {
                		my ($dummy, $entity) = split /\:/, $line;
                		($entity_type, $entity_no) = split /\-\s/, $entity;
                		$entity_type = uc($entity_type);
                		$entity_no = uc($entity_no);
                		$entity_type =~ s/ //g;
                		$entity_no =~ s/ //g;
                		
            		} elsif($line =~ /AZ/i) {
				my ($dummy, $testModel) = split /\:/, $line;
				($entity_type, $entity_no) = split /\s+\[/, $testModel;
                		$entity_type = uc($entity_type);
                		$entity_no = uc($entity_no);
                		$entity_type =~ s/ //g;
                		$entity_no =~ s/ //g;
                		$entity_no =~ s/^\[//g;
                		$entity_no =~ s/\]$//g;
                	
            		}else {
				# original tester info parsing to assign tester name and node name
				my @dummy = split /\:|\-/, $line;
                		$entity_type = uc($dummy[1]);
                		$entity_no = uc($dummy[$#dummy]);
                		$entity_type =~ s/ //g;
                		$entity_no =~ s/ //g;
			}
			$header->EQUIP1_ID($entity_type." ".$entity_no);
        	}
		# TESTPLAN
        	if ( $line =~ /Job_Name/i) {
			my @dummy = split /\:/, $line;
            		$tp = uc($dummy[1]);
            		$tp =~ s/[^0-9A-Z\-\_]//g;
            		$tp =~ /R([0-9]+)$/;
            		$tp_rev = int($1);
            		$tp_rev = 1 if $tp_rev == 0;
            		$header->PROGRAM($tp);
            		$header->REVISION($tp_rev);
        	}
		# LOTNO
		elsif ($line =~ /Lot Id|Lot_Id/i)
		{
			my @dummy = split /\:/, $line;
            		$dummy[1] = uc($dummy[1]);
            		$dummy[1] =~ s/ //g;
            		($lotno,$nothing) = split /\./, $dummy[1];
			$lotno =~ s/[^a-zA-Z0-9]//g;
	  	  	$lotno =~ s/AO/A0/ig;
			$retest_flag = "Y" if $lotno=~/REJ/i || $infile=~/REJ/i; ### CHECK IF RETEST DATA
			$lotno =~ s/REJ//gi;
			$lotno = substr($lotno,0,10) if length($lotno) > 10 && $lotno =~ /^A/i;
			$header->LOT(uc($lotno));
			
		}
		elsif ($line =~ /Lot No|Lot_No/i)
		{
			if($lotno eq "") {
				my @dummy = split /\:/, $line;
            	$dummy[1] = uc($dummy[1]);
            	$dummy[1] =~ s/ //g;
            	($lotno,$nothing) = split /\./, $dummy[1];
				$lotno =~ s/[^a-zA-Z0-9]//g;
		  	  	$lotno =~ s/AO/A0/ig;
				$retest_flag = "Y" if $lotno=~/REJ/i || $infile=~/REJ/i; ### CHECK IF RETEST DATA
				$lotno =~ s/REJ//gi;
				$lotno = substr($lotno,0,10) if length($lotno) > 10 && $lotno =~ /^A/i;
				$header->LOT(uc($lotno));
				
			}
			
			
		}
        	# TEST DATE & TIME
        	elsif ($line =~ /Report\s+\:/i)
        	{
			$line =~ s/Report\s+\://ig;
			$line =~ s/^\s+|\s$//g;
			$line =~ s/\s+/ /g;
			$header->START_TIME($line);
			$header->END_TIME($line);
        	}
	 	
	}

	foreach my $holder (sort { $a <=> $b} keys %binhash){
		$wafer->add( 'hbins', $binhash{$holder} );
	}

	close(INFILE);
	
    	# TRAP EMPTY LOTID & TESTPLAN NAME
    	if ($lotno eq "")
    	{	
    		$model->{misc} = "NO_LOTID";
    	}
	elsif ($tp eq "")
	{
		$model->{misc} = "NO_TESTPLAN";
	}
	# MUST HAVE TEST READINGS
	if ($with_test_readings == 0)
	{
		$model->{misc} = "NO_PART_DATA";
	}

    	return $model;
}

sub read2DFile {
    	my $self = shift;
    	my $infile = shift;
    	my $retest_flag = "N";
	my $nothing = undef;	
	my @parameter = ();
	my @lolim = ();
	my @hilim = ();
	my @unit = ();
	my $tp = "";
	my $lotno = "";
	my $line = undef;
	my @values = ();
        my $tp_rev = "";
	my $entity_type = "";
	my $entity_no = "";
	my $with_test_readings = 0;	# 0 if none. 1 if available.
	my %binhash = ();
	my %binnamehash = ();
    	my $header = new_headerLong;
    	my $wmap   = new_wmap;

	my $model  = new_model({
        	header => $header,
        	wmap   => $wmap,
              	misc   => {},
            	dataSource => 'SPM'
        });
    	
	my $wafer = new_wafer;
    	$model->add( 'wafers', $wafer );
	
	my $phbin = new_bin;
	$phbin->number( 1 );
	$phbin->name("PASS");
	$phbin->PF("P");
    	$phbin->count(-1);
	$wafer->add( 'hbins', $phbin );
	
	my $psbin = new_bin;
	$psbin->number( 1 );
	$psbin->name("PASS");
	$psbin->PF("P");
    	$psbin->count(-1);
	$wafer->add( 'sbins', $psbin );
  
    	open( INFILE, $infile );
    	while ($line=<INFILE>) {
		$line =~ s/\cM\n/\n/g;			
		chomp($line);
		$line  =~ s/\'//g;
		$line  =~ s/^\s+|\s$//g;
        
        	# TEST READINGS
		#if ($line =~ /^\d{1,}\s+\d/) 
		if ($line =~ /^\d+\<\d+.*\>/) # 1<20180911_175538,S1: NFVA34065L32548J28Q0001306 / S2: NFVA34065L32548J28Q0001306,S1:  / S2: ,S1: 30.3 / S2: 30.5>
        	{
			$line =~ s/\<\d+.*\>//;  # remove 2D scan results, not loading as of this time
			my @readings_temp = split /\s+/,$line;
			my @readings = ();
			@values = grep !/\*F\*|\*FA\*/, @readings_temp;
			push @readings, @values;
			
			#print "@readings\n";
			my $unitid   = shift(@readings);
			my $binnumber = shift(@readings);
			my $timevalue = shift(@readings);
		 
		 	# REMOVE UNWANTED(IN-BETWEEN) VALUES
			my $dummy = "";
			do
			{
				$dummy = shift(@readings);
			} until ($dummy =~ /FAIL|PASS/i || $#readings == -1);
			#print "@readings\n";
			
			# SKIP UNIT DATA IF NO PASS/FAIL FLAG 
			next if $#readings == -1;
			
			if(($binnumber != 1) && !defined($binhash{$binnumber})){
				my $bin = new_bin;
				$bin->number( $binnumber );
				$bin->name(sprintf("HWBIN_%02d",$binnumber));
				$bin->PF(substr($dummy,0,1));
				$bin->count(-1);
				$binhash{$binnumber} = $bin;
			}
			
			my $binname = undef;
			my $testnumber = -1;
			
			if($readings[0] =~ /^\d+/ || $dummy =~ /PASS/){
				#do nothing       
			}
			else{
			        $binname = shift(@readings);
				
				if (defined($binnamehash{$binname})){
					$testnumber = $binnamehash{$binname};
				}
				else{
				    	for(my $i=0; $i<=$#parameter; $i++){
						if($binname eq $parameter[$i]){
						    	$testnumber = $i+2;
							last;
						}
				    	}
					$binnamehash{$binname} = $testnumber;
				    	
				   }
				
				if ($testnumber == -1 && $binname ne "") {
					$model->{misc} = "INVALID_SOFT_BIN = $testnumber $binname";
				}
			}
			
			# CONVERT TEST READINGS TO BASE UNIT 
			# NOTE: SOMETIMES, DATALOG HAS MORE TEST RESULTS COLUMNS THAN PARAMTERS
			my $die = new_die;
			$die->partid($unitid);
			$die->hard_bin($binnumber);
			
			if($dummy =~ /PASS/){
				$die->soft_bin(1);
			}else{
				if ( $testnumber > 0 ){
					$die->soft_bin($testnumber);
				}
			}
			$die->add('result',$timevalue);
			
			for (my $i=0; $i<=$#parameter; $i++)
            		{
				if($i <= $#readings){
					$die->add('result',$readings[$i]);
					
				}else{
					$die->add('result',"N/A");
				}
				$with_test_readings = 1;
            		}
			
            		$wafer->add( 'dies', $die );
		}

        	# PARAMETER NAME 
        	elsif ($line =~ /^Item\s+/i)
        	{
            		@parameter = split /\s+/, $line;
            		shift(@parameter); #<-- REMOVES THE "Item" WORD
        	}
        	# LOWER LIMIT
        	elsif ($line =~ /LL/)
        	{
            		@lolim = split /\s+/, $line;
            		shift(@lolim);  #<-- REMOVES THE "LL" WORD
        	}
        	# UPPER LIMIT
        	elsif ($line =~ /HL/)
        	{
            		@hilim = split /\s+/, $line;
            		shift(@hilim);  #<-- REMOVES THE "HL" WORD
        	}
		# TEST UNITS
		elsif ($line =~ /Unit/i)
		{
			@unit = split /\s+/, $line;
  			shift(@unit);	#<-- REMOVES "Unit"

			# STORE TESTPLAN INTO A HASH
			my $ttest = new_test;
			$ttest->number( 0 );
			$ttest->name("Time");
			$ttest->units("s");
			$wafer->add('tests', $ttest );
			
			for(my $i=0; $i<=$#parameter; $i++)
			{
				$parameter[$i] =~ s/ //g;
				$hilim[$i] =~ s/ //g;
				$lolim[$i] =~ s/ //g;
				$unit[$i] =~ s/\s|\-//g;	
				my $test_num = $i+1;
				
				my $test = new_test;
				$test->number( $test_num );
				$test->name( uc($parameter[$i]));
				$test->units($unit[$i]);
				
				$test->LSL($lolim[$i]);
				$test->HSL($hilim[$i]);
				$wafer->add('tests', $test );

				my $sbin = new_bin;
				$sbin->number($test_num+1);
				$sbin->name(uc($parameter[$i]));
				$sbin->PF("F");
				$sbin->count(-1);
				$wafer->add('sbins',$sbin);
			}
		}
        	elsif ( $line =~ /System/i ) {
			# specific for suzhou spm tester tester model name starts with SPM
			if($line =~ /SPM/i) {
                		my ($dummy, $entity) = split /\:/, $line;
                		($entity_type, $entity_no) = split /\-\s/, $entity;
                		$entity_type = uc($entity_type);
                		$entity_no = uc($entity_no);
                		$entity_type =~ s/ //g;
                		$entity_no =~ s/ //g;
				# specific for suzhou spm tester tester model name starts with AZ
                		
            		} elsif($line =~ /AZ/i) {
				my ($dummy, $testModel) = split /\:/, $line;
				($entity_type, $entity_no) = split /\s+\[/, $testModel;
                		$entity_type = uc($entity_type);
                		$entity_no = uc($entity_no);
                		$entity_type =~ s/ //g;
                		$entity_no =~ s/ //g;
                		$entity_no =~ s/^\[//g;
                		$entity_no =~ s/\]$//g;
                	
            		}else {
				# original tester info parsing to assign tester name and node name
				my @dummy = split /\:|\-/, $line;
                		$entity_type = uc($dummy[1]);
                		$entity_no = uc($dummy[$#dummy]);
                		$entity_type =~ s/ //g;
                		$entity_no =~ s/ //g;
			}
			$header->EQUIP1_ID($entity_type." ".$entity_no);
        	}
		# TESTPLAN
        	if ( $line =~ /Job Name/i) {
			my @dummy = split /\:/, $line;
            		$tp = uc($dummy[1]);
            		$tp =~ s/[^0-9A-Z\-\_]//g;
            		$tp =~ /R([0-9]+)$/;
            		#$tp_rev = int($1);
            		#$tp_rev = 1 if $tp_rev == 0;
            		$header->PROGRAM($tp);
            		#$header->REVISION($tp_rev);
        	}
		# TP REVISION
                if ( $line =~ /Job Rev/i) {
                        my @dummy = split /\:/, $line;
                        $tp_rev = $dummy[1];
			$header->REVISION($tp_rev);
                }
		# LOTNO
		elsif ($line =~ /Lot Id|Lot_Id/i)
		{
			my @dummy = split /\:/, $line;
            		$dummy[1] = uc($dummy[1]);
            		$dummy[1] =~ s/ //g;
            		($lotno,$nothing) = split /\./, $dummy[1];
			$lotno =~ s/[^a-zA-Z0-9]//g;
	  	  	$lotno =~ s/AO/A0/ig;
			$retest_flag = "Y" if $lotno=~/REJ/i || $infile=~/REJ/i; ### CHECK IF RETEST DATA
			$lotno =~ s/REJ//gi;
			$lotno = substr($lotno,0,10) if length($lotno) > 10 && $lotno =~ /^A/i;
			$header->LOT(uc($lotno));
			
		}
		elsif ($line =~ /Lot No|Lot_No/i)
		{
			if($lotno eq "") {
				my @dummy = split /\:/, $line;
            	$dummy[1] = uc($dummy[1]);
            	$dummy[1] =~ s/ //g;
            	($lotno,$nothing) = split /\./, $dummy[1];
				$lotno =~ s/[^a-zA-Z0-9]//g;
		  	  	$lotno =~ s/AO/A0/ig;
				$retest_flag = "Y" if $lotno=~/REJ/i || $infile=~/REJ/i; ### CHECK IF RETEST DATA
				$lotno =~ s/REJ//gi;
				$lotno = substr($lotno,0,10) if length($lotno) > 10 && $lotno =~ /^A/i;
				$header->LOT(uc($lotno));
			}
			
			
		}
        	# TEST DATE & TIME
        	elsif ($line =~ /Report\s+\:/i)
        	{
			$line =~ s/Report\s+\://ig;
			$line =~ s/^\s+|\s$//g;
			$line =~ s/\s+/ /g;
			$header->START_TIME($line);
			$header->END_TIME($line);
        	}
	 	
	}

	foreach my $holder (sort { $a <=> $b} keys %binhash){
		$wafer->add( 'hbins', $binhash{$holder} );
	}

	close(INFILE);
	
    	# TRAP EMPTY LOTID & TESTPLAN NAME
    	if ($lotno eq "")
    	{	
    		$model->{misc} = "NO_LOTID";
    	}
	elsif ($tp eq "")
	{
		$model->{misc} = "NO_TESTPLAN";
	}
	# MUST HAVE TEST READINGS 
	if ($with_test_readings == 0)
	{
		$model->{misc} = "NO_PART_DATA";
	}

    	return $model;
}

sub check2Dscan {
        my $self = shift;
        my $infile = shift;

        my $result = `head -40 $infile | grep "[1-9]<[1-9].*>"`;
        my $scan_flg = ($result ne "") ? 'Y' : 'N';

        return $scan_flg;

}

1;
