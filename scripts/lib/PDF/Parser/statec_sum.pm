# 18-Aug-2015  Saed    - Created
# 11-Sep-2015  Eric    - change dataSource from statec_sum_cpft to STATEC
# 08-Oct-2915 jgarcia  - modified to accomodate atec_ph sum file's header portion
#													which is different from other site.  
#                         temporarily assigned test flow code into $header->INDEX1.
# 07-Mar-2019 jgarcia -  addes support for new tester that place lotid to different field name (Lot Id).

package PDF::Parser::statec_sum;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
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
our $file            = "";
my $lotno            = "";
my $dierun1          = "";
my $dierun2          = "";
my $tp               = "";
my $prod            = "";
my $test_count       = 0;
my $good_count       = 0;
my $total_hbin_count = 0;
my $setup_time       = 0;
my $start_test_time  = 0;
my $end_test_time    = 0;
my %hbin             = ();
my %sbin	     = ();
my $td_filename      = "";
my $model_no         = "";
my $station_no       = "";
my $handler_no       = "";
my $load_brd	     = "";
my $dut_brd	     = "";
my $dummy = "";
my @dummy = ();
my $testFlow = "";
my $tp_rev = "";

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
    my $model  = new_model(
        {   header => $header,
        	  dataSource => 'STATEC',
            misc   => {},
            dataSource => 'STATEC'
        }
    );

	
    my $wafer = $model->find('wafers',{number => 0});			
	unless (defined $wafer){
		$wafer = new_wafer( { number => 0 } );
		$model->add('wafers',$wafer);		
	}	
	my $psbin = new_bin;
	$psbin->number( 0 );
	$psbin->name("SBIN_00");
	#$bin->name( sprintf("BIN%02d",$binnumber) );
	$psbin->PF("P");
    $psbin->count(0);
	$wafer->add( 'sbins', $psbin );

	
    open (INFILE, "<",$infile);
	while (<INFILE>) {
	{
		$line = $_;		
		$line =~ s/\cM\n/\n/g;
		chomp($line);
			
		if ($site eq "atec_ph_ft") {
			
		###########
		# TESTERNO
		###########
		if ($line =~ /System/i)
		{
			
			$line     =~ s/ //g;
      ($dummy, $model_no) = split /\:|\-|\_|\[|\]/, $line;
      $model_no   = uc($model_no);
      #print "model=$model_no\n";
			#print "$model_no\t$station_no\t$handler_no\n";
			$header->EQUIP1_ID($model_no);
				
		}
		# STATIONNO
    ###########
    elsif ($line =~ /Station/i)
    {
    	@dummy = split /\:/, $line;
      $station_no    = uc($dummy[1]);
			$station_no    =~ s/\D//g;
      $station_no    =~ s/ //g;
      $header->EQUIP5_ID($station_no);
      #print "station=$station_no\n";
    }	
		elsif ($line =~ /Handler/i)
		{
			@dummy = split /\:/, $line;	
			$handler_no    = uc($dummy[1]);
			$handler_no    =~ s/ //g;
			$header->EQUIP5_ID($handler_no);
			#print "handler= $handler_no\n"; 
		}	
		###########
		# TESTPLAN
		###########		
		elsif ($line =~ /Job Name/i)
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
		elsif ($line =~ /Lot(\_|\s+)?Id/i)
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
		
		elsif ($line =~ /Lot No/i)
			{
				@dummy    = split /\:/, $line;	
				#$dummy[1] = uc($dummy[1]);
				$dummy[1] =~ s/^\s+|\s+$//g;
				(my $dump, $testFlow) = split /\_/, $dummy[1];
				#$testFlow =~ s/ //g;
				$header->INDEX1($testFlow);
				INFO("TEST FLOW CODE ". $testFlow)
			}
		
		###################
		# TOTAL TEST COUNT
		###################
		elsif ($line =~ /Total Test Count/i)
		{
			@dummy      = split /\:/, $line;	
			$test_count = $dummy[1];
			$test_count =~ s/ //g;
			my $stats = $wafer->stats;
			$stats->{devicecount} = $test_count;
			$stats->{$test_count};
			$header->DEVICE_COUNT( $test_count );
			#print "test_count = $test_count \n"; 	
		}
		###################
		# TOTAL GOOD COUNT
		###################
		elsif ($line =~ /Total Good Count/i)
		{
			@dummy      = split /\:/, $line;	
			$good_count = $dummy[1];
			$good_count =~ s/ //g;
			$psbin->count($good_count);

			#print "good_count = $good_count \n"; 	
		}
		#############
		# SETUP TIME 
		#############
		elsif ($line =~ /Setup/i && $line !~ /0000/)
		{			
			#$setup_time =  $line;
			my @dummy = split /\s{2,}/, $line;	
			$dummy[2] =~ s/ //g;				#<-- DATE
			$dummy[3] =~ s/ //g;				#<-- TIME				
			$header->DATE_CODE($dummy[2] . $dummy[3]);
			#print "setup time = $setup_time \n"; 	
		}
		##################
		# TEST START TIME 
		##################
		elsif ($line =~ /Test Start/i && $line !~ /0000/)
		{
			$wafer->START_TIME($line);
			
		}
		################
		# TEST END TIME 
		################
		elsif ($line =~ /Test End/i && $line !~ /0000/)
		{
			$wafer->END_TIME($line);			
		}	
		#########################
		# ENABLE PARSE HBIN FLAG
		#########################
		elsif ($line =~ /TEST  BIN  REPORT/)
		{
			$hbin_flag = 1;	
		}
		#########################
		# ENABLE PARSE SBIN FLAG
		#########################
		elsif ($line =~ /TEST ITEM/i)
		{
			$sbin_flag = 1;
			$hbin_flag = 0;
		}
		################
		# HBIN SUMM INFO
		################
		elsif ($hbin_flag == 1)
		{
			my @readings = split /\s+/,$line;
			shift(@readings);			#<-- REMOVE 1ST ELEM W/C IS BLANK
		
			#############################				
			# STORES READING INTO A HASH
			#############################						
			if ($readings[0] =~ /\d/)			
			{
				$hbin{$readings[0]} = $readings[1];
				$hbin{$readings[3]} = $readings[4] if $readings[3] =~ /\d/;	#<-- NO 2ND COL OF BIN INFO ON THE LAST PART.			          	     
				$total_hbin_count  += $readings[1];
			}
		}
		################
		# SBIN SUMM INFO
		################
		elsif ($sbin_flag == 1)
		{
			my @readings = split /\s+/,$line;
			shift(@readings);                       #<-- REMOVE 1ST ELEM W/C IS BLANK

			#############################
			# STORES READING INTO A HASH
			#############################
			if ($readings[0] =~ /\d/)
			{
				$sbin{$readings[0]} = $readings[2];
				
				my $psbin = new_bin;
				$psbin->number($readings[0]);
				$psbin->name($readings[1]);
				#$bin->name( sprintf("BIN%02d",$binnumber) );
				$psbin->PF("F");
				if ($_ eq ("1")){
					$psbin->PF("P");
				}	 				
				$psbin->count($readings[2]);
				$wafer->add( 'sbins', $psbin );
				
				
			}
		}
			
		} else {
			
			###########
		# TESTERNO
		###########
		if ($line =~ /System/i)
		{
			$line     =~ s/ //g;
            ($dummy, $model_no,$station_no,$dummy,$handler_no) = split /\:|\-|\_/, $line;
			
			($dummy, $model_no,$station_no,$handler_no) = split /\:|\-|\//, $line;
			$model_no   = uc($model_no);
			#$station_no =~ s/\D//g;
			$handler_no = uc($handler_no);
			#print "$model_no\t$station_no\t$handler_no\n";
			$header->EQUIP1_ID($model_no);
			#$header->EQUIP2_ID($station_no);
			$header->EQUIP5_ID($station_no . $handler_no);
			#$header->REVISION($rev);				
		}
		###########
		# TESTPLAN
		###########		
		elsif ($line =~ /Job Name/i)
		{
			@dummy = split /\:/, $line;	
			$tp    = uc($dummy[1]);
			$tp    =~ s/ //g;
			$header->PROGRAM($tp);		
			
		}
		###########
		# device name
		###########		
		elsif ($line =~ /Dvc Name/i)
		{
			@dummy = split /\:/, $line;	
			$prod    = uc($dummy[1]);
			$prod    =~ s/ //g;
			
			$header->PRODUCT($prod);						
		}
		
		########
		# LOTNO
		########
		elsif ($line =~ /Lot(_|\s+)?No/i)
		{
			@dummy    = split /\:/, $line;	
			$dummy[1] = uc($dummy[1]);
			$dummy[1] =~ s/ //g;
			($lotno,$dierun1,$dierun2) = split /\_/, $dummy[1];
			#print "$dummy[1] lotno= $lotno dierun1=$dierun1 dierun=$dierun2\n"; 	
			if($lotno ne "") {
				$header->LOT($lotno);
				$header->SOURCE_LOT($lotno);
			}
			
			
		}
		###################
		# TOTAL TEST COUNT
		###################
		elsif ($line =~ /Total Test Count/i)
		{
			@dummy      = split /\:/, $line;	
			$test_count = $dummy[1];
			$test_count =~ s/ //g;
			my $stats = $wafer->stats;
			$stats->{devicecount} = $test_count;
			$stats->{$test_count};
			$header->DEVICE_COUNT( $test_count );
			#print "test_count = $test_count \n"; 	
		}
		###################
		# TOTAL GOOD COUNT
		###################
		elsif ($line =~ /Total Good Count/i)
		{
			@dummy      = split /\:/, $line;	
			$good_count = $dummy[1];
			$good_count =~ s/ //g;
			$psbin->count($good_count);

			#print "good_count = $good_count \n"; 	
		}
		#############
		# SETUP TIME 
		#############
		elsif ($line =~ /Setup/i && $line !~ /0000/)
		{			
			#$setup_time =  $line;
			my @dummy = split /\s{2,}/, $line;	
			$dummy[2] =~ s/ //g;				#<-- DATE
			$dummy[3] =~ s/ //g;				#<-- TIME				
			$header->DATE_CODE($dummy[2] . $dummy[3]);
			#print "setup time = $setup_time \n"; 	
		}
		##################
		# TEST START TIME 
		##################
		elsif ($line =~ /Test Start/i && $line !~ /0000/)
		{
			$wafer->START_TIME($line);
			
		}
		################
		# TEST END TIME 
		################
		elsif ($line =~ /Test End/i && $line !~ /0000/)
		{
			$wafer->END_TIME($line);			
		}	
		#########################
		# ENABLE PARSE HBIN FLAG
		#########################
		elsif ($line =~ /TEST  BIN  REPORT/)
		{
			$hbin_flag = 1;	
		}
		#########################
		# ENABLE PARSE SBIN FLAG
		#########################
		elsif ($line =~ /TEST ITEM/i)
		{
			$sbin_flag = 1;
			$hbin_flag = 0;
		}
		################
		# HBIN SUMM INFO
		################
		elsif ($hbin_flag == 1)
		{
			my @readings = split /\s+/,$line;
			shift(@readings);			#<-- REMOVE 1ST ELEM W/C IS BLANK
		
			#############################				
			# STORES READING INTO A HASH
			#############################						
			if ($readings[0] =~ /\d/)			
			{
				$hbin{$readings[0]} = $readings[1];
				$hbin{$readings[3]} = $readings[4] if $readings[3] =~ /\d/;	#<-- NO 2ND COL OF BIN INFO ON THE LAST PART.			          	     
				$total_hbin_count  += $readings[1];
			}
		}
		################
		# SBIN SUMM INFO
		################
		elsif ($sbin_flag == 1)
		{
			my @readings = split /\s+/,$line;
			shift(@readings);                       #<-- REMOVE 1ST ELEM W/C IS BLANK

			#############################
			# STORES READING INTO A HASH
			#############################
			if ($readings[0] =~ /\d/)
			{
				$sbin{$readings[0]} = $readings[2];
				
				my $psbin = new_bin;
				$psbin->number($readings[0]);
				$psbin->name($readings[1]);
				#$bin->name( sprintf("BIN%02d",$binnumber) );
				$psbin->PF("F");
				if ($_ eq ("1")){
					$psbin->PF("P");
				}	 				
				$psbin->count($readings[2]);
				$wafer->add( 'sbins', $psbin );
				
				
			}
		}
			
			
		}### end of while loop

		
		
	}
	close(FILE);	
	### GET LOAD BOARD & DUT BOARD FROM FILENAME ###
	#($load_brd, $dut_brd) = &get_board($file);	
	#$header->EQUIP4_ID($infile);
}


#######################
# Now Create HBIN Objects
#######################

my $hbin_cnt = 0;
foreach (sort {$a<=>$b} keys %hbin)
{

	my $phbin = new_bin;
	$phbin->number($_);
	$phbin->name( "HWBIN_" . $_);
	#$bin->name( sprintf("BIN%02d",$binnumber) );
	if ($_ eq "1"){
		$phbin->PF("P");
	}	
	else {
		$phbin->PF("F");
	}				
	$phbin->count($hbin{$_});
	$wafer->add( 'hbins', $phbin );
	#$hbin_cnt = $_;

}			
#}

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

    return $model;
}
1
