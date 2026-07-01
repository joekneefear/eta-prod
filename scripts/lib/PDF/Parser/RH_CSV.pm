# 06-Apr-2016 Eric      : initial release
# 29-Jul-2016 Eric	: removed error codes from Reedholm tester are shown as numbers in the range of 1e20
# 28-Mar-2017 Eric	: declared $wmap
#
package PDF::Parser::RH_CSV;
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
	my $unit 	 = "";
	my @test_numbers = ();
	my @test_names   = ();
	my @upper_limits = ();
	my @lower_limits = ();
	my @test_units   = ();
	my $part_flag    = 0;
	my $sbin_flag    = 0;
	my $hbin_flag    = 0;
	my %td = ();
	my %tp = ();
	my %hbin = ();
	my %sbin = ();
	my $dump         = "";
	my $header = new_headerLong;
	my $wafer = new_wafer;
	my $wmap  = new_wmap;
        my $model = new_model (
                {
                        header => $header,
			wmap => $wmap,
                        misc   => {},
                        dataSource => 'RH'
                }
        );
	
	open FH, $infile or die "can't open $infile\n";
        while(my $line=<FH>){
		chomp($line);
		my (@dummy) = split /\,/, $line;
		#print "$line\n";
		if ($dummy[0]=~/PartID/i)
		{
			$part_flag = 1;
		}
		elsif ($dummy[0]=~/^Bin Number$/i)
		{
			$part_flag = 0;
			$hbin_flag = 1;
			$sbin_flag = 0;
		}
		elsif ($dummy[0]=~/^SW Bin Number$/i)
                {
                        $part_flag = 0;
                        $hbin_flag = 0;
                        $sbin_flag = 1;
                }
		# part data
		if($dummy[0]=~/\b\d{1,}\b/ && $dummy[1]=~/\b\d{1,}\b/ && $part_flag == 1)
		{
			my ($partid, $bin, $x, $y, @readings) = @dummy;
			
			# new bin column from a "SWBin/HWBin" (Nov 27, 2012
			my $sbin 	  = $bin;
			my $hbin 	  = 0;
			   ($sbin, $hbin) = split /\//, $bin if $bin=~/\//;

			next if $partid !~ /\d{1,}/;

			my $die = $wafer->find('dies',{partid => $partid});
                	unless (defined $die){
                        	$die = new_die({ partid => $partid });
                        	$die->partid( $partid );
                        	$die->x($x);
                        	$die->y($y);
				$die->hard_bin($hbin);
                        	$die->soft_bin($sbin);
                        	$wafer->add('dies',$die);
                	}
			for (my $i=0; $i <= $#readings; $i++) {
				$readings[$i] =~ s/^\d+\.\d+E\+2.+$//g if $readings[$i] =~ /E\+2.+$/; #pos
				$readings[$i] =~ s/^\d+\.\d+E\-2.+$//g if $readings[$i] =~ /E\-2.+$/; #neg
                                $die->add( 'result', repNA($readings[$i]) );
                        }
			
		}
		# hbin data
                elsif ($dummy[0]=~/\b\d{1,}\b/ && $hbin_flag == 1)
                {
			my $hbin = new_bin;
			$hbin->number($dummy[0]);	
			$hbin->name(uc(&clean_string($dummy[1])));
			$hbin->count($dummy[2]);
			$hbin->PF(($dummy[0]==1) ? 'P' : 'F');
			$wafer->add( 'hbins', $hbin );
                }
		# sbin data
		elsif ($dummy[0]=~/\b\d{1,}\b/ && $sbin_flag == 1)
		{
			my $sbin = new_bin;
                        $sbin->number($dummy[0]);
                        $sbin->name(uc(&clean_string($dummy[1])));
                        $sbin->count($dummy[2]);
                        $sbin->PF(($dummy[0]==1) ? 'P' : 'F');
                        $wafer->add( 'sbins', $sbin );
		}
		# header info
		elsif ($dummy[0]=~/LOT ID/i)
		{
			my $lotid = uc(&clean_string($dummy[1]));
			   $lotid = substr($lotid, 0, 11) if length($lotid) > 11;
			   $header->LOT($lotid);
		}
		elsif($dummy[0]=~/TEST PROGRAM$/i)
		{
			my $tp_name = uc(&clean_string($dummy[1]));
		           $tp_name = substr($tp_name,0,35) if length($tp_name) > 35;
			   $header->PROGRAM($tp_name);
		}
		elsif($dummy[0]=~/TEST PROGRAM REV/i)
		{
			my $tp_rev = $dummy[1];
			   $tp_rev = 1 if $tp_rev=~/[^\d\.]/;
			   $header->REVISION($tp_rev);
		}
		elsif($dummy[0]=~/DATE/i)
		{
			my ($mon, $day, $yr, $hr, $min) = split /[\/\s\:]/, $dummy[1];
			my $test_datetime = $yr."/".$mon."/".$day." ".$hr.":".$min.":"."00";
			   $header->START_TIME($test_datetime);
			   $header->END_TIME($test_datetime);			
		}
		elsif($dummy[0]=~/WAFER NUMBER/i)
		{
			my $wafer_id = uc(&clean_string($dummy[1]));
		   	$wafer_id = "" if $wafer_id !~ /\b\d{1,3}\b/;
			$wafer = $model->find('wafers',{number => $wafer_id});
		        unless (defined $wafer){
                		$wafer = new_wafer( { number => $wafer_id } );
                		$model->add('wafers',$wafer);
        		}	
		}
		elsif($dummy[0]=~/COMPUTER/i)
		{
			my $eqpt_id = uc(&clean_string($dummy[1]));
			   $header->EQUIP1_ID($eqpt_id);
		}
		elsif($dummy[0]=~/SOURCE LOT/i)
		{
			my $src_lotid = uc(&clean_string($dummy[1]));
		}
		elsif($dummy[0]=~/OPERATOR/i)
		{
			my $user_id = uc(&clean_string($dummy[1]));
			   $header->OPERATOR($user_id);
		}
		elsif($dummy[0]=~/DEVICE/i)
		{
			my $device_id = uc(&clean_string($dummy[1]));
			my $prod_id   = $device_id;
		}
		# limits info
		elsif($dummy[0]=~/TEST SEQ NUMBER/i)
		{
			($dump,$dump,$dump,$dump,@test_numbers) = @dummy;
		}
		elsif($dummy[0]=~/TEST NAME/i)
		{
			($dump,$dump,$dump,$dump,@test_names) = @dummy;
		}
		elsif($dummy[0]=~/UPPER SPEC/i)
		{
			($dump,$dump,$dump,$dump,@upper_limits) = @dummy;
		}
		elsif($dummy[0]=~/LOWER SPEC/i)
		{
			($dump,$dump,$dump,$dump,@lower_limits) = @dummy;
		}
		elsif($dummy[0]=~/TEST UNIT/i)
		{
			($dump,$dump,$dump,$dump,@test_units) = @dummy;

			for(my $i=0; $i<=$#test_numbers; $i++)
                        {
				next if $test_numbers[$i] !~ /\b\d{1,}\b/ || $test_names[$i] eq "";
				# change test number to start at 1000
				my ($test_num, $sub_test_num) = split /\./, $test_numbers[$i];
                                my $new_test_num = ($test_num * 1000) + $sub_test_num;
			
				my $test_name = uc(&clean_string($test_names[$i]));
				my $test_unit = uc(&clean_string($test_units[$i]));
	
				# assign default limit if blank
				$upper_limits[$i] =  1e18 if $upper_limits[$i] eq "";
				$lower_limits[$i] = -1e18 if $lower_limits[$i] eq "";

				my $test = new_test;
				$test->number($new_test_num); 
				$test->name($test_name);
				$test->units($test_unit);
				$test->HSL($upper_limits[$i]);
				$test->LSL($lower_limits[$i]);
				$model->add('tests', $test);
			}
		}

	}
	close(FH);
	

return $model;
}

sub clean_string
{
        my $str = shift;
           $str =~ s/^\s+|\s+$//g;
           $str =~ s/\,//g;
           $str =~ s/\s+/_/g;
        return($str);
}


1;
