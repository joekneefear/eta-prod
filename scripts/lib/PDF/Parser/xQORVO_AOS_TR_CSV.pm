#CHANGES
#  2025/02/20 joven : new
#   
package PDF::Parser::xQORVO_AOS_TR_CSV;
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
#my %bin = ();
my $bin;
my %sbin = ();
my %hbin = ();
my @bins;
my %binCount; 
my %counter = ();
my $good_bin;

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

=pod
dVBE/VDS/VF,,VCB/,IE/,,Power,Delay,Gate,,Calcu
Lower,Upper,VDS,ID/IF,IM,Time,Time,Limit,Scan#,late,K,
  40mV,  80mV,----, 9.70A, 10mA,50.0ms,100us,-----,0,----,----,,

#Index,1,PASS,VF1:(mV),627,dVF:(mV),66,
#Index,2,PASS,VF1:(mV),627,dVF:(mV),69,
=cut

sub readFile {
    my $self   = shift;
    my $infile = shift;
	my $platform = shift;
    my $header = new_headerLong;
    my $model  = new_model(
        {   header => $header,
            misc   => {},
            dataSource => 'AOS'
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
	my $date;
	my $time;
	my $min;
	my $max;
	my $begin_data = 0;
	my $Bin;		
	my $wafer;
	my @wk;
	my @test_name;
	#my @test_low;
	#my @test_high;
	#my @test_unit;	
	my $wk ;
	my $max_item = 0;
	my $testParam = 0;
	my $testname;
	my $test_low;
	my $test_high;
	my $test_unit;	
	my $binNum;
	my $lotid;
	my $datetimeStr;
	my $sourceLot;
	my $program;
	my $parametric_data = 0;
	#@wk = split('_', basename $infile);
	#$header->EQUIP1_ID($wk[3]);
	#@wk = split('-', $wk[1]);
	#$header->LOT($wk[0]);
	
	#my $wafer = $model->find('wafers',{number => 0});
	#unless (defined $wafer){
	#	$wafer = new_wafer( { number => 0 } );
	#	$model->add('wafers',$wafer);
	#}
	
	
    open (INFILE, "<",$infile);
	
    while (<INFILE>) {
		s/\015//;
		s/\cM\n/\n/;
		chomp;
		my $line = $_;
		
		$seq++;
		
		my @item = split(/,/, $line);	
 
		if($item[0] =~ "File Name"){
			
			$program = uc($item[1]);
			#($program) = $program =~ /^(.*)\./;
			INFO ("PROGRAM = ". $program);
			$header->PROGRAM($program);
			#$header->RECIPE($item[1]);
            $waferNum = 0;		
			$wafer = $model->find('wafers',{number => $waferNum});
            unless (defined $wafer){
               $wafer = new_wafer( { number => $waferNum } );
               $model->add('wafers',$wafer);			   
			  		  
            }			
			
		}
		elsif($item[0] =~ "CreateDate"){
			
			
			#$datetimeStr->strftime "%Y/%m/%d %H:%M:%S";
			my @dummy = split /[\s:-]+/, $item[1];
			my ($hh, $nn, $ss , $day ,$mon, $yr) = @dummy;
			
			$datetimeStr = $yr."/".$mon."/". $day." ".$hh.":".$nn.":".$ss;	
			
			INFO ("START_TIME = ". $datetimeStr);
			$header->START_TIME($datetimeStr);		
			$header->END_TIME($datetimeStr);
		}
		elsif($item[0] =~ "Polarity"){
			
			$lotid = $item[6];
			$lotid =~ s/\'//g;#remove apostrophe in lot
			INFO ("LOT = ".$lotid);
			$header->LOT($lotid);
			my @tmpStr = split /\./, $lotid;
			$sourceLot = $tmpStr[0];
			#($sourceLot) = $sourceLot =~ s/[^.]*//g;
			INFO ("Source LOT = ".$sourceLot);
			$header->SOURCE_LOT($sourceLot . ".S");
		}
		elsif($item[0] =~ "All Test"){
			INFO ("PRODUCT = ".$item[6]);
			$header->PRODUCT($item[6]);		
		}
		elsif($item[0] =~ "Comment"){
			INFO ("REVISION = ".$item[1]);
			INFO ("EQUIP1_ID = ".$item[6]);
			$header->REVISION($item[1]);	
			#$header->RECIPE_REVISION($item[1]);				
			$header->EQUIP1_ID($item[6]);
		}
		elsif($item[0] =~ "Lower"){		
			
			$testParam = 1;	
		}
		elsif($testParam && !$begin_data){		
			$test_low = $item[0]; 
			$test_high = $item[1];
			# get only numeric value for low and high data
			($test_low) = $test_low =~ /(\d+)/;
			($test_high) = $test_high =~ /(\d+)/;
			$testname = $item[4];
			$testname =~ s/^\s+|\s+$//g; 
			$testname = "dVF_IM_".$testname;
			
			$test_unit = $item[0];
			
			$test_unit =~ s/[0-9]//g;
			
			$begin_data =1;
			
			INFO ("test_low = ".$test_low);
			INFO ("test_high = ".$test_high);
			INFO ("testname = " . $testname);
			INFO ("test_unit = " . $test_unit);
		}		
		elsif($begin_data && $item[1] =~ /\d+/){
		
			my $partid = $item[1];
		    my $name;
            my $cnt   = 1;
			
			$parametric_data = 1;
			
				
            
			if($item[2] =~ "PASS"){
				$binNum = 1;
				#$name="001";			
				
			}
			else{
				$binNum = 2;
				#$name="002";				
			}
			
			#INFO ("bin name = ".$name);
			#INFO ("bin num = ".$binNum);
			#INFO ("PF = ".$pf);

			#$sbin{$partid} =
			#{
			#		NUM  => $binNum,
			#		NAME => "SWBin_" . $name,
			#		CNT  => $cnt,					
			#		
			#};

			#$hbin{$partid} =
			#{
			#		NUM  => $binNum,
			#		NAME => "HWBin_" . $name,
			#		CNT  => $cnt,					
			#		
			#};			
			
			
			my $die = $wafer->find('dies',{partid=>$partid});
            unless (defined $die){
               $die = new_die( { partid => $partid } );
			   $die->soft_bin($binNum);
			   $die->hard_bin($binNum);
               $wafer->add('dies',$die);
			   $binCount{TYPE}{$binNum} = "BinInfo";
			   if (exists $binCount{CNT}{$binNum}){
					$binCount{CNT}{$binNum} = $binCount{CNT}{$binNum} +1;
			   }
			   else{
				$binCount{CNT}{$binNum} = 1;
			   }
            }

			# Detect duplicate bin numbers
			$counter{$binNum} = (!exists($counter{$binNum})) ? 1 : $counter{$binNum} + 1;
			#INFO ("Bin Count = ".$counter{$binNum} );
			#INFO ("adding result  " );     
			$die->add( 'result', repNA($item[6],$item[6]));
			#INFO ("results added  " );                        
		}
	}
	
		foreach my $wk (keys %{$binCount{TYPE}}){
		#INFO($binCount{TYPE}{$wk}."/".$wk."/".$binCount{CNT}{$wk} );
		
		if($wk ne ""){
		
			my $pf;
			
			if ($wk =~ 1) {
				$pf = "PASS";
			}else{
				$pf = "FAIL";
			}
				
			
			my $bin;
			#SoftBin
			$bin = new_bin(
								{   number => $wk,
									name   => "SWBin_00".$wk ,
									count  => $binCount{CNT}{$wk},
									PF     => $pf
								}
							);
			
			$wafer->add( 'sbins', $bin );
			
			#HardBin
			$bin = new_bin(
								{   number => $wk,
									name   => "HWBin_00".$wk ,
									count  => $binCount{CNT}{$wk},
									PF     => $pf
								}
							);
			
			$wafer->add( 'hbins', $bin );
		}
	}
	

=pod		
=cut

		#for (my $i = 0; $i<=$#test_name; $i++)
		#{
		if ($parametric_data)
		{
			
			my $test = new_test;
			#$test->number($i+1);
			$test->number(1);
			#$test->name( $test_name[$i]);
			$test->name($testname);
			$test->units( $test_unit);			
			$test->LSL($test_low);
			$test->HSL($test_high);
			$model->add('tests',$test);
			
			#INFO($test_name[$i]);
		}else{
			INFO("No Parametric Data found in the file.");
			dpExit(1, "No Parametric Data found in the file.");
			
		}
		#}
		
					
    return $model;
}
1;

