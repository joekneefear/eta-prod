# 06-Apr-2016 Eric      : initial release
package PDF::Parser::TESEC_CSV;
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
	my $session = shift;
	my $lotid       = "";
	my %td          = ();		
	my $tp_name     = "";	
	my $tp_rev      = 1;
	my $device	= "";
	my $test_time   = "";
	my $operator    = "";
	my $part_cnt    = 0;
	my $station     = "";
	my @test_numbers= ();
	my @test_names  = ();
	my @low_lim     = ();
	my @hi_lim      = ();
	my @single_limit= ();
	my @units       = ();
	my @bias        = ();
	my @good_parts = ();
	my $def_low_spec= -1e18;
	my $def_hi_spec = 1e18;
	my $file_type   = "";	# 2 datalog formmats: 3620 & 971
	my $env_mod       = "";
	my $myFilename    = "";
	my @myFilenameArray = ();
	my $counter = 0;
	my $lotidFlag = "Off";
	my $data_type = "H";
	my %months    = ( "Jan"=>"0", "Feb"=>"1","Mar"=>"2","Apr"=>"3","May"=>"4","Jun"=>"5","Jul"=>"6","Aug"=>"7","Sep"=>"8","Oct"=>"9","Nov"=>"10","Dec"=>"11");
	my $header = new_headerLong;
        my $model = new_model (
                {
                        header => $header,
                        misc   => {},
                        dataSource => 'TESEC'
                }
        );

	my $wafer = $model->find('wafers',{number => 0});
        unless (defined $wafer){
                $wafer = new_wafer( { number => 0 } );
                $model->add('wafers',$wafer);
        }
	
	# Get Lot, TesterNode, Device from Filename
	my $fNameLotid = "";
	my $fNameDevice = "";
	my $fNameTesterNode = "";
	my($myFilename, $dump) = split /\.CSV/i, $infile;
	$myFilename   = substr($myFilename, rindex($myFilename, "/") + 1);
	@myFilenameArray = split /\_|\-/, $myFilename;
	
	for(my $i = 0; $i <= $#myFilenameArray; $i++) {
		if($myFilenameArray[$i] =~ /^T/i && $myFilenameArray[$i] !~ /^TESEC/i) {
			
			$counter = $i;
			$fNameLotid = $myFilenameArray[$i];
			last;
		}
	}

	if($myFilenameArray[0] ne $myFilenameArray[$counter-1]) {
		 
		$fNameDevice = "${myFilenameArray[0]}_${myFilenameArray[$counter-1]}";
	}
	else{
		$fNameDevice = "${myFilenameArray[0]}";
	}
	$fNameTesterNode = "${myFilenameArray[$#myFilenameArray - 1]}_${myFilenameArray[$#myFilenameArray]}";
	
	$fNameDevice =~ s/^\s+|\s+$//g;
	$fNameLotid =~ s/^\s+|\s+$//g;
	$fNameTesterNode =~ s/^\s+|\s+$//g;
	$header->LOT($fNameLotid);

	open FH, $infile or die "can't open $infile\n";
        while(my $line=<FH>)
        {
		chomp($line);
		$line =~ s/\cM//g;
		my (@dummy) = split /\:\,|\,/, $line;			

		#identify data type 
		$data_type = "T" if $dummy[0]=~/Test\s?Number|Measure\#/i;
		$data_type = "D" if $line=~/\,BIN\,|\,BIN/i;

		# detect tester type
		if ($file_type eq "")
		{
			$file_type=971	if $line=~/TESEC.+971/i;
			$file_type=3620 if $line=~/FILENAME.+OPERATOR.+CREATED/i;
		}
		
		if ($data_type eq "H" && $file_type ne "")
		{
			# get test program
			if ($file_type==971 && $dummy[0]=~/FileName/i && $tp_name eq "")
			{
				$tp_name = clean_string(uc($dummy[1]));
				$tp_name =~ s/\.tst//i;
				$tp_name = clean_string($tp_name);
				$tp_name =~ s/\s+/\_/g;
				if($tp_name eq "") {
					$tp_name = $fNameDevice;
				}
				$header->PROGRAM($tp_name);
			}
			elsif ($file_type==3620 && $dummy[0]=~/Device/i && $tp_name eq "")
			{
				$tp_name = clean_string(uc($dummy[2]));
				$tp_name =~ s/\s+/\_/g;
				$tp_name = substr($tp_name, length($tp_name) - 20) if length($tp_name) > 20;
				if($tp_name eq "") {
					$tp_name = $fNameDevice;
                                }
				$device  = $tp_name;
				$header->PROGRAM($tp_name);
			}
			# get device
			$device = clean_string(uc($dummy[1])) if $dummy[0]=~/Device/i && $file_type==971;
			if($device eq "") {
				$device = $fNameDevice;
			}
			# operator
			$operator = clean_string(uc($dummy[5])) if $dummy[4]=~/Operator/i; ### 3620
			$operator = clean_string(uc($dummy[4])) if $dummy[3]=~/Operator/i; ### 971	
			$header->OPERATOR($operator);
			
			# lotid
			$lotid = clean_string(uc($dummy[5])) if $dummy[4]=~/Lot\s?Name/i; ### 3620
			$lotid = clean_string(uc($dummy[4])) if $dummy[3]=~/Lot\s?Name/i; ### 971
			if($lotid eq "") {
				$lotid = $fNameLotid;
			}
			$header->LOT($lotid);
						
			# station
			if ($dummy[0] =~ /Station/i)
			{
				$station = $dummy[1]||$dummy[2];
				#$station = ord(uc($station)) - 64 if $station  =~ /[A-Z]/i; # translate to numeric
				#$station = ""			  if $station  !~ /^\d+$/;  # set to blank if non-numeric
				#$header->EQUIP1_ID($station);
				$header->EQUIP1_ID($fNameTesterNode."_".$station);
			}
			# test time
			if ($dummy[7] =~ /CREATED/i)
            		{
                        	$file_type = 3620;
				my $hh = 00;
				my $mm = 00;
				my $ss = 00;
                        	my ($day, $mon, $yr) = split /\-/, $dummy[8];
				$mon = $months{$mon};
                        	$yr       +=  2000 if $yr < 100;
				$test_time = sprintf("%04d/%02d/%02d %02d:%02d:%02d",$yr,$mon+1,$day,$hh,$mm,$ss);
				$header->START_TIME($test_time);
				$header->END_TIME($test_time);
			}
		}
		# limits info
		elsif ($data_type eq "T" && $file_type ne "")
		{
			if ($dummy[0]=~/TEST\s?NUMBER|Measure\#/i)
			{
				@test_numbers = @dummy;
				foreach my $no(0..$#test_numbers)	
				{ 
					$test_numbers[$no]=~s/^T// if $test_numbers[$no]=~/^T\d/;
				}	
			}	
			elsif ($dummy[0] =~ /TEST\s?ITEM|Item\s?Name/i)
			{
				(@test_names) = map(clean_string(uc($_)),@dummy);
			}
			# lower spec limit (971)
			elsif ($dummy[0] =~ /^Min\s?Limit$/i && $file_type==971)
			{
				for my $no(0..$#test_numbers)
				{
					my $value = ($test_numbers[$no]=~/^\d+$/) ? $dummy[$no]||$def_low_spec : "";
					push (@low_lim, $value);
				}
			}
			# upper spec limit (971)
			elsif ($dummy[0] =~ /^Max\s?Limit$/i && $file_type==971)
			{
                               	for my $no(0..$#test_numbers)
                               	{
					my $value = ($test_numbers[$no]=~/^\d+$/) ? $dummy[$no]||$def_hi_spec : "";
                                       	push (@hi_lim, $value);
                               	}
			}
			# spec limit (3620)
			elsif ($dummy[0]=~/^LIMIT$/i && $file_type==3620)
			{
				for my $no(0..$#test_numbers)
                                {
					my $value = "";
					my $unit  = "";
					if ($test_numbers[$no]=~/\d/)
					{
						$value = $dummy[$no];
						$value =~ s/\s+//g;
				   		$value =~ /(\D+)$/;    	# get unit if available
        					$unit  = $1;
           					$value =~ s/$unit//; 	# remove unit from limit value
					}
					push (@single_limit, $value);
					push (@units	   , $unit);
				}
			}
			# bias info
			elsif ($dummy[0] =~ /Bias\s?\d/i)
			{
				my $lbl = uc($dummy[0]);
				   $lbl =~ s/\s+//g;
				for my $no(0..$#test_numbers)
				{
					my $value = "";
					if ($test_numbers[$no]=~/^\d+$/ && $dummy[$no] ne "" && $dummy[$no]!=0)
					{
						$value = "$lbl\=$dummy[$no]";
					   	$value =~ s/\s+//g;
						$bias[$no] = ($bias[$no] eq "") ? $value : "$bias[$no]_$value";
					}
				}
			}
		} #end limits info				
			
		elsif ($data_type eq "D" && $dummy[0]=~/\d+/ && $file_type ne "")
                {
			# fix shifted data. data column count must be equal to the test number (971 ONLY)
			if ($#dummy > $#test_numbers && $file_type==971)
			{
				my @new_dummy    = ();
				my $shifted_data = $#dummy - $#test_numbers;
				for my $no(0..$#dummy)
				{
					#$dummy[$no]=~ s/\s+//g;
					next if $dummy[$no] eq "" && $shifted_data-- != 0;
					push(@new_dummy, $dummy[$no]); 
				}
				@dummy = @new_dummy;
			}

			# change good bin 7(3620) & 10(971) to bin 1
			$dummy[2]=1 if ($file_type==971  && $dummy[2]==10);
			$dummy[1]=1 if ($file_type==3620 && $dummy[1]==7);
			
			if ($file_type==971) {
				my $die = $wafer->find('dies',{partid=>$dummy[1]});
        	        	unless (defined $die){
                	        	$die = new_die( { partid => $dummy[1]} );
                	        	$die->partid( $dummy[1] );
                        		$wafer->add('dies',$die);
                		}
				my $bin = $wafer->find('bins',{number=>$dummy[2]});
                        	unless (defined $bin){
                                	my $bin = new_bin;
                                	$bin->number($dummy[2]);
                                	$bin->name("BIN_".$dummy[2]);
					$bin->PF( ($dummy[1] eq "1") ? 'P' : 'F');
                                	$wafer->add('bins',$bin);
                        	}

                        	$die->hard_bin($dummy[2]);
                        	$die->soft_bin($dummy[2]);
			}
			elsif ($file_type==3620) {
				my $die = $wafer->find('dies',{partid=>$dummy[0]});
                                unless (defined $die){
                                        $die = new_die( { partid => $dummy[0]} );
                                        $die->partid( $dummy[0] );
                                        $wafer->add('dies',$die);
                                }
				my $bin = $wafer->find('bins',{number=>$dummy[1]});
                                unless (defined $bin){
                                        my $bin = new_bin;
                                        $bin->number($dummy[1]);
                                        $bin->name("BIN_".$dummy[1]);
                                        $bin->PF( ($dummy[1] eq "1") ? 'P' : 'F');
                                        $wafer->add('bins',$bin);
                                }

                                $die->hard_bin($dummy[1]);
                                $die->soft_bin($dummy[1]);

			}
			
			# save test data into hash
			$td{$dummy[0]} = [@dummy];	
			# collect bin 1 parts for upper/lower spec detection
			push(@good_parts, $dummy[0]) if $dummy[1]==1;
                }# end data type d		
		
	} #end while
	close(FH);

	# trap unknown file type
	if ($file_type eq "") {
		$model->{misc} = "Can't determine tester file type."; 
		return($model, "");
		#dpExit(1, "Can't determine tester file type.");
	}

	# create appropriate upper/lower spec limits (for 3620 only)
	my $prev_col_num = "";
	for my $no (0..$#test_numbers)
	{
		last if $file_type==971;
		next unless $test_numbers[$no]=~/\d/;
		
		# if paramete is "SAME", use the prev limit to determine the lower/upper spec limit
		if ($test_names[$no] =~ /SAME/i)
		{
			$test_names[$no] = $test_names[$prev_col_num];
			$bias[$no]       = $bias[$prev_col_num];
			$units[$no]      = $units[$prev_col_num];
			
			if ($single_limit[$no] > $single_limit[$prev_col_num])
			{
				$hi_lim[$no]  = $single_limit[$no];
				$low_lim[$no] = $single_limit[$prev_col_num];
		
				$hi_lim[$prev_col_num]  = $single_limit[$no];
				$low_lim[$prev_col_num] = $single_limit[$prev_col_num];
			}
			else
			{
				$hi_lim[$no]  = $single_limit[$prev_col_num];
				$low_lim[$no] = $single_limit[$no];
		
				$hi_lim[$prev_col_num]  = $single_limit[$prev_col_num];
				$low_lim[$prev_col_num] = $single_limit[$no];
			}
		}
		# set limit individual parameter 
		else
		{
			# compare limit agains the test result of a good part
			foreach my $serial (sort {$a<=>$b} keys %td)
			{
				# compare only with good bin
                                next unless $td{$serial}[1]==1;

				# set to upper limit if limit is greater than the reading
				if ($single_limit[$no] > $td{$serial}[$no])
				{
					$hi_lim[$no]  = $single_limit[$no];
					$low_lim[$no] = $def_low_spec;
					last;
				}
				# set to lower limit if limit is less than the reading 
				elsif ($single_limit[$no] < $td{$serial}[$no])
				{
					$hi_lim[$no]  = $def_hi_spec;
					$low_lim[$no] = $single_limit[$no];
					last;
				}
				# set the same spec limit for param with "PASS" or "FAIL" DATA
				elsif ($td{$serial}[$no] =~ /PASS|FAIL/i)
                		{
                        		$hi_lim[$no]  = $single_limit[$no];     # usually set to zero
                        		$low_lim[$no] = $single_limit[$no];     # usually set to zero
					last;
				}
			}
		}
		$prev_col_num = $no;
	}# end for loop

	# store test values into model
	my $prev_test_name = "";
	my $limit = new_limit;
	$limit->conditionNames([qw/testCond/]);
	for my $no (0..$#test_numbers)
	{
		next unless $test_numbers[$no]=~/\d/;
		my $test = new_test;
		$test->number($test_numbers[$no]);
		my $test_name = ($test_names[$no]=~/SAME/i) ? $prev_test_name : $test_names[$no];
		$test->name(($test_names[$no]=~/SAME/i) ? $prev_test_name : $test_names[$no]);
		$test->units($units[$no]);
		$test->LSL($low_lim[$no]);
		$test->HSL($hi_lim[$no]);
		$test->add('conditions',$bias[$no]);
		$limit->add('tests', $test);
		$model->add('tests', $test);
		#$model->add('tests',$limit);
			
		# apply prev testname for "SAME" parameteres
		$prev_test_name = $test_names[$no] if $test_names[$no]!~/SAME/i;
	}

	# store test results into model
	foreach my $serial(sort {$a <=> $b} keys %td)
        {
		my $die = $wafer->find('dies',{partid=>$serial});
		unless (defined $die){
                	$die = new_die( { partid => $serial } );
                        $die->partid( $serial );
                        $wafer->add('dies',$die);
                }	

		my $addr = $td{$serial};
		for my $no (0..$#test_numbers)
		{
			next if $test_numbers[$no] !~ /^\d+$/;
			my $result = "";
			   $result = $$addr[$no]      if $$addr[$no]=~/\d/;
			   $result = 0		      if $$addr[$no]=~/PASS/i;
			   $result = 1                if $$addr[$no]=~/FAIL/i;
			   $result = $hi_lim[$no] + 1 if $$addr[$no]=~/OVER/i;
			next if $result eq "";

			$die->add( 'result', repNA($result) );
		}
	}


return $model, $limit;
}

sub clean_string
{
        my $str = shift;
           $str =~ s/^\s+|\s+$//g;
           $str =~ s/\,//g;
           $str =~ s/\s+/_/g;
        return($str);
}

sub clean_row
{
	my @arr     = @_;
	my @new_arr = ();
	foreach (@arr)
        {
        	if ($_ =~ /TEST\s?NUMBER|Measure\#/i || $_ ne "")
                {
                	push (@new_arr, $_);
                }
        }
	return(@new_arr);	
}
1;
