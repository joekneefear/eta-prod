#CHANGES
#  2015/08/12 grace : new_bin
#  2015/09/08 eric  : parse HSL & LSL
#  2017/02/20 eric  : skip line if blank to resolve partid not found issue.
package PDF::Parser::Douyee;
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
DATE,2015-06-22
TIME,16:29
FILE,20150622_SW_IHS-044_SOT6_1
PRESET,DATA
MEMO1,1892/SW
MEMO2,FULL TAPE TEST
SPEED,300mm/min
FRQNCY,HIGH
Wdisp,gf
RANGE,20-60
SPECIFIED,0-100
MAX,37.1
MIN,22.9
AVE,30.63
STD,2.44
CPK,OFF
CPK,
Device,
Lot,
Seal,
Run,
Operator,4532
Temp,175
MachineNo,
POINT,DATA
1,33.7
2,34.1
3,35.8
4,37.1
5,36.7
6,36
7,36.3
=cut

sub readFile {
    my $self   = shift;
    my $infile = shift;
	my $platform = shift;
    my $header = new_headerLong;
    my $model  = new_model(
        {   header => $header,
            misc   => {},
            dataSource => 'DOUYEE'
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
	my %BinCount;
	my $wafer;
	my $test_num = 0;
	my $test = new_test;
	
    open (INFILE, "<",$infile);
    while (<INFILE>) {
		s/\015//;
		s/\cM\n/\n/;
		chomp;
		my $line = $_;
		next if $line =~ /^$/;		
		$seq++;
		
		my @item = split(/,/, $line);		
		
		if($item[0] eq "DATE"){
			$date = $item[1];
			INFO($date);
		}
		elsif($item[0] eq "TIME"){
			$time = $item[1];
		}
		elsif($item[0] eq "FILE"){
		
			if($item[1] =~ /_(\S{3}-\d{3})_/)
			{
				INFO($1);
				$header->EQUIP1_ID($1);
			}
			
			if($item[1] =~ /(\d{2})(\d{2})(\d{4})(\S+)/){
			
				$header->LOT($3.$2.$4);
			
			}
			
			$header->START_TIME($date." ".$time.":00");
		}
		elsif($item[0] eq "Operator"){
			$header->OPERATOR($item[1]);
		}
		elsif($item[0] eq "RANGE"){
			my @wk = split('-', $item[1]);
			
			$header->PROGRAM("TP.".$wk[0].".".$wk[1]);		
			$min = $wk[0];
			$max = $wk[1];
			$test->LSL($wk[0]);
			$test->HSL($wk[1]);
		}
		elsif($item[0] eq "Wdisp"){
			$test_num++;			
            		$test->number( $test_num );
            		$test->name( uc($item[1])) ;
            		$test->units( uc($item[1])) ;
                   
		}
		elsif($item[0] eq "POINT"){
			$begin_data = 1;
			$waferNum = 0;
			$wafer = $model->find('wafers',{number => $waferNum});
            		unless (defined $wafer){
               			$wafer = new_wafer( { number => $waferNum } );
               			$model->add('wafers',$wafer);
			   	$wafer->add( 'tests', $test );
            		}
			
			$BinCount{1} = 0;
			$BinCount{2} = 0;
			
		}elsif($begin_data){
			
			my $Result = $item[1];
			
			
			if (($Result > $min) && ($Result < $max))
			{
				$Bin          = 1;	
				$BinCount{1} += 1;
			}
			else
			{
				$Bin          = 2;
				$BinCount{2} += 1;
			}

			my $die = new_die;
            		$die->soft_bin( $Bin );
            		$die->partid( $item[0] );
			$die->add( 'result', $item[1]);
			$wafer->add( 'dies', $die );
		}	
    }
	
	my $bin;
	$bin = new_bin(
		{   number => 1,
		    name   => "Bin_01",
		    count  => $BinCount{1},
		    PF     => "P"
		}
	);
	
	$wafer->add( 'sbins', $bin );
		
	if($BinCount{2} = 0){
		$bin = new_bin(
			{   number => 2,
			    name   => "Bin_02",
			    count  => "0",
			    PF     => "F"
			}
		);
	}
	else{
		$bin = new_bin(
			{   number => 2,
			    name   => "Bin_02",
			    count  =>  $BinCount{2},
			    PF     => "F"
			}
		);
	}
	
	$wafer->add( 'sbins', $bin );			
				
    return $model;
}
1;

