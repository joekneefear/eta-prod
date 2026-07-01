# 18-Aug-2015  Saed    - Created

package PDF::Parser::statec_log_cpft;
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
    my $header = new_headerLong;
	my $wmap   = new_wmap;
	
    my $model  = new_model(
        {   header => $header,
			wmap   => $wmap,		
            misc   => {},
            dataSource => 'statec_log_cpft'
        }
    );

	
    my $wafer = $model->find('wafers',{number => 0});	
	
	unless (defined $wafer){
		$wafer = new_wafer( { number => 0 } );
		$model->add('wafers',$wafer);		
	}	

	#my $psbin = new_bin;
	#$psbin->number( 1 );
	#$psbin->name("BIN_1");
	#$bin->name( sprintf("BIN%02d",$binnumber) );
	#$psbin->PF("P");
    #$psbin->count(0);
	#$wafer->add( 'sbins', $psbin );

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

		###########
		# TESTERNO
		###########
		if ($line =~ /System/i)
		{
			$line     =~ s/ //g;
            #($dummy, $model_no,$station_no,$dummy,$handler_no) = split /\:|\-|\_/, $line;
			
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
		elsif ($line =~ /Job_Name/i)
		{
			@dummy = split /\:/, $line;	
			$tp    = uc($dummy[1]);
			$tp    =~ s/ //g;
			$header->PROGRAM($tp);		
			#print "XXXX Program $tp \n";
		}
		###########
		# device name
		###########		
		elsif ($line =~ /Dvc_Name/i)
		{
			@dummy = split /\:/, $line;	
			my $prod    = uc($dummy[1]);
			$prod    =~ s/ //g;
			
			$header->PRODUCT($prod);						
		}
		
		########
		# LOTNO
		########
		elsif ($line =~ /Lot_No/i)
		{
			@dummy    = split /\:/, $line;	
			$dummy[1] = uc($dummy[1]);
			$dummy[1] =~ s/ //g;
			($lotno,$dierun1,$dierun2) = split /\_/, $dummy[1];
			#print "$dummy[1] lotno= $lotno dierun1=$dierun1 dierun=$dierun2\n"; 	

			
			$header->LOT($lotno);
			$header->SOURCE_LOT($lotno);
			
		}

		### TEST NAMES
		elsif ($line =~ /Item (.*)/){
		
           foreach ( split( /\'/, trim($1))  ) {
				my $test = new_test;				
				$test->number( $testNum );
				$test->name( repNA( $_ ) );
				$model->add( 'tests', $test );
				$testNum++;

            }		
		}

		### TEST UNITS
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
				#$wafer->add( 'tests', $test );
				#print "%%%%% TestNo , HL  $testNum , $_ \n";				
				$testNum++;				
			}
		}
        elsif ($line =~ /LL(.*)/) {
			$testNum= 0;
			foreach ( split( /\'/, trim($1) ) ) {
				$model->tests->[$testNum]->LSL(repNA($_));		
				#$wafer->add( 'tests', $test );
				$testNum++;				
			}
		}		
		############
		# TEST DATE
		############
		elsif ($line =~ /Report\s+\:/)
		{
			my @dummy = split /\s{2,}/, $line;
			$dummy[3] =~ s/ //g;                            #<-- DATE
			$dummy[4] =~ s/ //g;                            #<-- TIME
			$wafer->START_TIME($dummy[3] . " " . $dummy[4]);
			$wafer->END_TIME($dummy[3] . " " . $dummy[4]);
		}
		################
		# TEST READINGS
		################
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
						#$phbin->name( $readings[3]);
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
					#print "$readings[$i] \t $unit[$j] \t";						
					#$readings[$i] =	&convert_to_base_unit($readings[$i],$unit[$j]) if $readings[$i]=~/\d/;
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
