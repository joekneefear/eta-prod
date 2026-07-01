#CHANGES
#  2015/08/20 grace : new_bin
package PDF::Parser::ItecSum;
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

=pod
Station=3 JOB=\\ITEC-0JR10LYCVK\C$\ITEC\SITE\JOB\ SSCK2N7002V3.job Machine=?   

Summary counters:

+---+----------+-----+-------+-------+---+----------+-----+-------+-------+
|typ|pass name |  bin|  count|      %|typ|fail name |  bin|  count|      %|
+---+----------+-----+-------+-------+---+----------+-----+-------+-------+
|P00|PKG:SOT-23|     |      0|  0.0 %|F01|CONT      |1    |    102|  1.0 %|
|P01|PASS      |5    |   9972| 98.3 %|F02|PRE-O/S   |2    |     31|  0.3 %|
|   |          |     |       |       |F03|VTH-FAIL  |3    |      0|  0.0 %|
|   |          |     |       |       |F04|BV-FAIL   |3    |     19|  0.2 %|
|   |          |     |       |       |F05|IO-FAIL   |3    |     11|  0.1 %|
|   |          |     |       |       |F06|RDON-FAIL |3    |      0|  0.0 %|
|   |          |     |       |       |F07|VDSON-FAIL|3    |      0|  0.0 %|
|   |          |     |       |       |F08|GMP-FAIL  |3    |      0|  0.0 %|
|   |          |     |       |       |F09|VF-FAIL   |3    |      0|  0.0 %|
|   |          |     |       |       |F10|POST-O/S  |3    |      0|  0.0 %|
|   |          |     |       |       |F28|Exception |3    |     13|  0.1 %|
|   |          |     |       |       |F29|Not oper. |3    |      0|  0.0 %|
|   |          |     |       |       |F30|Osc/brkdwn|3    |      0|  0.0 %|
|   |          |     |       |       |F31|M overflow|1    |      0|  0.0 %|
+---+----------+-----+-------+-------+---+----------+-----+-------+-------+

Total tested=10148 pass=9972 ( 98.3 %) fail=176 (  1.7 %) not present=407

=cut

sub readFile {
    my $self   = shift;
    my $infile = shift;
	my $platform = shift;
    my $header = new_headerLong;
    my $model  = new_model(
        {   header => $header,
            misc   => {},
            dataSource => 'ITEC'
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
	my $bin;	
	my %BinCount;
	my $wafer;
	my @wk;
	my @test_name;
	my @test_low;
	my @test_high;
	my @test_unit;	
	my $wk ;
	
	@wk = split('_', basename $infile);
	$header->EQUIP2_ID($wk[0]);
	$header->EQUIP1_ID($wk[3]);
	@wk = split('-', $wk[1]);
	$header->LOT($wk[0]);
		
    open (INFILE, "<",$infile);
	
    while (<INFILE>) {
		s/\015//;
		s/\cM\n/\n/;
		chomp;
		my $line = $_;
		
		$seq++;
		
		my @item = split(/\|/, $line);	

		if($line =~ /JOB/){
			if($line =~ /\\JOB\\ (\S+)V(\d{1}).job/){
				$header->PROGRAM($1);
				$header->REVISION($2);			
			}
			
			$waferNum = 0;		
			$wafer = $model->find('wafers',{number => $waferNum});
            unless (defined $wafer){
               $wafer = new_wafer( { number => $waferNum } );
               $model->add('wafers',$wafer);
			   
            }
		}
		else{
		
		
			if($item[1] =~ /P(\d+)/){
				#INFO($1."/".$item[2]."/".$item[3]);
				
				my $bin_num = $1;
				
				if(!($item[1] =~ /P00/))
				{
					if($bin_num eq "01"){
						$bin_num = "00";
					}				
				  #INFO("BIN_NUM=$bin_num||BIN_NAME=$item[2]||BIN_COUNT=$item[4]||PF=P");
					$bin = new_bin(
										{   number => $bin_num,
											name   => $item[2],
											count  => $item[4],
											PF     => "P"
										}
									);
				
					
				$wafer->add( 'sbins', $bin );
				
				}
			}
			
			if($item[6] =~ /F(\d+)/){
				#INFO($1."/".$item[7]."/".$item[8]);
				my $bin_num = $1;
				#INFO("BIN_NUM=$bin_num||BIN_NAME=$item[7]||BIN_COUNT=$item[9]||PF=F");
				$bin = new_bin(
						{   number => $bin_num,
										name   => $item[7],
										count  => $item[9],
										PF     => "F"
						}
						);
				
				$wafer->add( 'sbins', $bin );
									
			}
			
		
		
		}
	}
    return $model;
}
1;

