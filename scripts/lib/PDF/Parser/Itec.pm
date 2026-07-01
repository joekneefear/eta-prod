#CHANGES
#  2015/08/13 grace : new_bin
#  2021/Apr/15 jgarcia : fixed "Experimental values on scalar is now forbidden" issue.
package PDF::Parser::Itec;
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
JOB=\\ITEC-0JR10LYCVK\C$\ITEC\SITE\JOB\SSCK2N7002V3.job

devicenr,type,bin,Fkelvin_c,Akelvin_c,Fkelvin_e,Fkelvin_b,Fvth,Fvth1,Fbvdss,Fbvdss1,Fbvdss2,Fdelta,Figss,Frdson1,Frdson2,Fvdson,Fvdson1,Fgmp,Fvfsd,Figss1,Fidss,Figss3,Fvth2,Akelvin_e,Akelvin_b,Avth,Avth1,Abvdss,Abvdss1,Abvdss2,Adelta,Aigss,Ardson1,Ardson2,Avdson,Avdson1,Agmp,Avfsd,Aigss1,Aidss,Aigss3,Avth2,HEADCODE,R1,R2,R3,Check
low limit,,, 1.0000E-02, 1.0000E-02, 1.0000E-02, 1.0000E-02, 3.0000E-01, 1.0250E+00, 4.5000E+01, 6.1200E+01, 6.1200E+01,,-8.0000E-08,,,,, 8.4000E-02, 2.0000E-01,-8.0000E-08,-1.0000E-07,-1.0000E-07, 1.0000E+00, 1.0000E-02, 1.0000E-02, 3.0000E-01, 1.0250E+00, 4.5000E+01, 6.1200E+01, 6.1200E+01,,-8.0000E-08,,,,, 8.4000E-02, 2.0000E-01,-8.0000E-08,-1.0000E-07,-1.0000E-07, 1.0000E+00,,,,,
high limit,,, 1.0000E-01, 1.0000E-01, 1.0000E-01, 1.0000E-01, 2.8000E+00, 2.4380E+00,, 9.3000E+01, 9.3000E+01, 5.0000E+00, 8.0000E-08, 7.3500E+00, 7.3500E+00, 1.4250E+00, 3.5630E+00,, 1.4250E+00, 8.0000E-08, 1.0000E-07, 1.0000E-07, 2.5000E+00, 1.0000E-01, 1.0000E-01, 2.8000E+00, 2.4380E+00,, 9.3000E+01, 9.3000E+01, 5.0000E+00, 8.0000E-08, 7.3500E+00, 7.3500E+00, 1.4250E+00, 3.5630E+00,, 1.4250E+00, 8.0000E-08, 1.0000E-07, 1.0000E-07, 2.5000E+00,,,,,
unit,,,V,V,,,V,V,V,V,V,,A,Ohm,Ohm,V,V,Mho,V,A,A,A,V,,,V,V,V,V,V,,A,Ohm,Ohm,V,V,Mho,V,A,A,A,V,,,,,
1,P01,5, 3.4480E-02, 3.2160E-02, 3.4520E-02, 3.2960E-02, 2.1154E+00, 2.1162E+00, 7.9168E+01, 7.8424E+01, 7.9001E+01,-5.7718E-01, 1.9037E-09, 1.6512E+00, 1.1208E+00, 8.2780E-02, 5.7086E-01, 3.0024E-01, 7.5202E-01, 9.8605E-10, 1.7960E-09, 7.9348E-10, 2.1004E+00, 3.2400E-02, 3.1780E-02, 2.1144E+00, 2.1146E+00, 7.9189E+01, 7.9147E+01, 7.9394E+01,-2.4754E-01, 1.8077E-09, 1.6300E+00, 1.1332E+00, 8.1820E-02, 5.7660E-01, 3.0199E-01, 7.5646E-01, 2.8934E-12,-2.7647E-09, 8.7319E-10, 2.1004E+00, 7.0000E+01, 3.4927E+00, 3.5565E+00, 3.4241E+00, 4.8118E-03
2,P01,5, 3.4500E-02, 3.2380E-02, 4.1360E-02, 3.3200E-02, 2.1158E+00, 2.1160E+00, 7.8318E+01, 7.8280E+01, 7.8129E+01, 1.5082E-01, 1.6792E-09, 1.6504E+00, 1.1242E+00, 8.3120E-02, 5.7286E-01, 2.9931E-01, 7.5166E-01, 1.0867E-09, 1.7054E-09, 6.6263E-10, 2.1032E+00, 3.2600E-02, 3.1520E-02, 2.1100E+00, 2.1104E+00, 7.7903E+01, 7.7877E+01, 7.7816E+01, 6.0463E-02, 2.9657E-09, 1.6476E+00, 1.1378E+00, 8.2540E-02, 5.8000E-01, 2.9983E-01, 7.5354E-01, 1.0703E-09, 4.6070E-09, 1.2659E-09, 2.0970E+00, 7.0000E+01, 3.4989E+00, 3.5644E+00, 3.4310E+00, 2.2619E-03
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
	my $Bin;		
	my $wafer;
	my @wk;
	my @test_name;
	my @test_low;
	my @test_high;
	my @test_unit;	
	my $wk ;
	my $max_item = 0;
	
	@wk = split('_', basename $infile);
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
		
		my @item = split(/,/, $line);	

		if($item[0] =~ /JOB/){
			if($item[0] =~ /JOB\\(\S+)V(\d{1}).job/){
				$header->PROGRAM($1);
				$header->REVISION($2);			
			}
			
			$waferNum = 0;		
			$wafer = $model->find('wafers',{number => $waferNum});
            unless (defined $wafer){
               $wafer = new_wafer( { number => $waferNum } );
               $model->add('wafers',$wafer);
			   
			   $wafer->START_TIME(timegm(localtime()));
			   $wafer->END_TIME(timegm(localtime()));			  
            }
		}
		elsif($item[0] =~ "devicenr"){		
			if($#test_name < 0)
			{			
				for(my $i=3; $i<=$#item; $i++){
					push @test_name, $item[$i];
				}			
			}			
		}
		elsif($item[0] =~ "low limit"){		
			if($#test_low < 0)
			{			
				for(my $i=3; $i<=$#item; $i++){
					push @test_low, $item[$i];
				}			
			}			
		}
		elsif($item[0] =~ "high limit"){		
			if($#test_high < 0)
			{			
				for(my $i=3; $i<=$#item; $i++){
					push @test_high, $item[$i];
				}			
			}			
		}
		elsif($item[0] =~ "unit"){		
			if($#test_unit < 0)
			{			
				for(my $i=3; $i<=$#item; $i++){
					push @test_unit, $item[$i];
				}			
			}

			$begin_data =1;
		}
		elsif($begin_data && $item[0] =~ /\d+/){
		
			my $partid = $item[0];
			my $die = $wafer->find('dies',{partid=>$partid});
            unless (defined $die){
               $die = new_die( { partid => $partid } );
			   $die->soft_bin( $item[2]);
               $wafer->add('dies',$die);
			   $binCount{TYPE}{$item[2]} = $item[1];
			   if (exists $binCount{CNT}{$item[2]}){
					$binCount{CNT}{$item[2]} = $binCount{CNT}{$item[2]} +1;
			   }
			   else{
				$binCount{CNT}{$item[2]} = 1;
			   }
            }
			
			if($max_item < $#item){
				$max_item = $#item
			}			
		
            for(my $i=3; $i<=$max_item; $i++){
				
				
			    $die->add( 'result', repNA($item[$i]));
			}                        
		}
	}
	
	foreach my $wk (keys %{$binCount{TYPE}}){
		#INFO($binCount{TYPE}{$wk}."/".$wk."/".$binCount{CNT}{$wk} );
		
		if($wk ne ""){
		
			my $pf = substr($binCount{TYPE}{$wk},0, 1);
			
			my $bin;
			$bin = new_bin(
								{   number => $wk,
									name   => "Bin".$wk ,
									count  => $binCount{CNT}{$wk},
									PF     => $pf
								}
							);
			
			$wafer->add( 'sbins', $bin );
		}
	}
=pod		
=cut

		for (my $i = 0; $i<=$#test_name; $i++)
		{
			my $test = new_test;
			$test->number($i+1);
			$test->name( $test_name[$i]);
			$test->units( $test_unit[$i]);			
			$test->LSL($test_low[$i]);
			$test->HSL($test_high[$i]);
			$model->add('tests',$test);
			
			#INFO($test_name[$i]);
		}
		
					
    return $model;
}
1;

