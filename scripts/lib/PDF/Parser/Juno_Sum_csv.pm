# 17-Nov-2015 Eric	: Initial release
# 01-Dec-2105 Eric	: Bin 5 is the passing bin
#
package PDF::Parser::Juno_Sum_csv;
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

my %sbin = ();
my %counter = ();
my $seq = 1;
my $good_parts;
my $total_parts;

sub readFile {
	my $self = shift;
	my $infile = shift;
	my $bin_flag = 0;		
	my %counter = ();
	my $bin;
	my $line = "";
	my $header = new_headerLong;
	my $model = new_model ( 
		{
			header => $header,
            		misc   => {},
            		dataSource => 'JUNO'
		}
	);

	my $wafer = $model->find('wafers',{number => 0});
	unless (defined $wafer){
		$wafer = new_wafer( { number => 0 } );
		$model->add('wafers',$wafer);
	}

	# Get lotid from filename
	chomp($infile);
	my $fn = basename($infile);
	   $fn =~ s/^\s+|\s+$//g;
	my ($device, $lot, $source_lot, $tester_no,) = split /\_/, $fn;
	my ($lotid, $sublotid) = split /\-/, $lot;
	   INFO ("Lot in filename = $lotid");
	   $header->LOT(trim($lotid));	
	   $header->EQUIP1_ID(trim($tester_no));
	
	open FH, $infile or die "can't open $infile\n";
	while($line=<FH>)
	{
		chomp($line);
		my (@dummy) = split /\,/, $line;
		if ($dummy[0]=~/Date/i){
			$dummy[1] =~ s/^\s+|\s+$//g;
			my ($yr,$mon,$day,$hr,$min,$sec)= $dummy[1] =~ m!(\d{4})(\d\d)(\d\d)\-(\d\d):(\d\d):(\d\d)!;
			my $start_time = $yr."/".$mon."/".$day." ".$hr.":".$min.":".$sec;
			$header->START_TIME($start_time);
			$header->END_TIME($start_time);
		}
		elsif ($dummy[0]=~/DataFileName/i){

		}
		elsif ($dummy[0]=~/TestFileName/i){
			my ($tp_name,$dump) = split /\./, uc(&clean_string($dummy[1])), 2;
                        $tp_name  =~ /V(\d{1,})$/i;
                        my $loc_tp_rev = $1;
                        if ($loc_tp_rev =~ /^\d{1,}$/)
                        {
                                my $tp_rev  = $loc_tp_rev;
                                $tp_name =~ s/V${tp_rev}//;
                                $header->PROGRAM($tp_name);
                                $header->REVISION($tp_rev);
                                INFO ("Program = $tp_name Revision=$tp_rev");
                        }	
		}
		elsif ($dummy[0]=~/Pass/i)
                {	
                        $good_parts = &clean_string($dummy[1]);
			$bin = new_bin;
			$bin->number(5);
			$bin->name(uc(trim($dummy[0])));
			$bin->count($good_parts);
			$bin->PF('P');
			$wafer->add( 'sbins', $bin );
                }
                elsif ($dummy[0]=~/Total/i)
                {
                        $total_parts = &clean_string($dummy[1]);
                }
                elsif ($dummy[0]=~/Bin Counter/i)
                {
                        $bin_flag=1;
                }
                elsif ($dummy[0]=~/Measure Counter|Lot Counter/i)
                {
                        $bin_flag=0;
                }
                elsif ($dummy[0]=~/\bF\d{1,2}\b/i && $bin_flag==1)
                {	
			my ($num,) = $dummy[0] =~ m!F(\d+)\b!;
                        my $name   = uc(&clean_string($dummy[1]));
                        my $cnt    = $dummy[2];
                        next if $name =~ /PASS/i || $num !~ /\d+/;

                        $sbin{$seq++} =
                        {
                                NUM  => $num,
                                NAME => $name,
                                CNT  => $cnt,
                        };

                        # Detect duplicate bin numbers
                        $counter{$num} = (!exists($counter{$num})) ? 1 : $counter{$num} + 1;
                }
	}
	close(FH);

	# Fix duplicate bin numbers
	my %new_bin_num = ();
        foreach $seq(sort {$a<=>$b} keys %sbin)
        {
		$bin = new_bin;
                my $bin_num = $sbin{$seq}{NUM};
                if ($counter{$bin_num} > 1)
                {
                        $new_bin_num{$bin_num}  = $bin_num * 100 if !exists $new_bin_num{$bin_num};
                        $new_bin_num{$bin_num} += 1;
                        $sbin{$seq}{NUM}        = $new_bin_num{$bin_num};
                }
		$bin->number($sbin{$seq}{NUM});
                $bin->name($sbin{$seq}{NAME});
                $bin->count($sbin{$seq}{CNT});
                $bin->PF('F');
                $wafer->add( 'sbins', $bin );
         	
        }

	return $model;
}

sub clean_string
{
        my $str = shift;
           $str =~ s/^\s+|\s+$//g;
           #$str = &EDBUtil::cleanString($str);  
	   $str =~ s/\,//g;	
           $str =~ s/\s+/_/g;
        return($str);
}
1;

