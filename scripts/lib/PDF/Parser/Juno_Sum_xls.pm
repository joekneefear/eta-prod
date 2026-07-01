# 16-Nov-2015 Eric	: Initial release
# 01-Dec-2015 Eric	: Bin 5 is the passing bin
#
package PDF::Parser::Juno_Sum_xls;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use PDF::ExcelReader;
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
	my $dataflag = 0;	
	my %counter = ();
	my $bin;
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
	
	my @arrysheetnames = ();
        my $xls            = PDF::ExcelReader->new($infile);
           $xls->getworksheets(\@arrysheetnames);
        my $maxcol         = $xls->maxcolumncount($arrysheetnames[0]);
        my $maxrow         = $xls->maxrows($arrysheetnames[0]) + 1;

	for (my $row=1; $row<=$maxrow; $row++) {
		my $cellA = $xls->readfromcell($arrysheetnames[0], "A" . $row);
                my $cellB = $xls->readfromcell($arrysheetnames[0], "B" . $row);
                my $cellC = $xls->readfromcell($arrysheetnames[0], "C" . $row);
		#print "CELL = $cellA $cellB $cellC\n";
		if ($cellA =~ /Date/i) {
			$cellB =~ s/^\s+|\s+$//g;
			my @tm = split /\s/, $cellB;
			my $start_time = $tm[0]."/".$tm[1]."/".$tm[2]." ".$tm[3].":"."00";
			$header->START_TIME($start_time);
			$header->END_TIME($start_time);
		}
		elsif ($cellA =~ /TestFileName/i){
			my ($tp_name,$dump) = split /\./, uc(&clean_string($cellB)), 2;
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
		elsif ($cellA=~/Pass/i)
                {
                        $good_parts = &clean_string($cellB);
			$bin = new_bin;
                        $bin->number(5);
                        $bin->name(uc(trim($cellA)));
                        $bin->count($good_parts);
                        $bin->PF('P');
                        $wafer->add( 'sbins', $bin );
                }
                elsif ($cellA=~/Total/i)
                {
                        $total_parts = &clean_string($cellB);
                }
                elsif ($cellA=~/\d+/i && $cellB=~/\w+/ && $cellC=~/\d+/)
                {
                        next if $cellB =~ /PASS/i;
			$cellA =~ s/\D//;
			$sbin{$seq++} =
                        {
                                NUM  => $cellA,
                                NAME => uc(&clean_string($cellB)),
                                CNT  => $cellC,
                        };			
                        # Detect duplicate bin numbers
                        $counter{$cellA} = (!exists($counter{$cellA})) ? 1 : $counter{$cellA} + 1;
                }
	}
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

