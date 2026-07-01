package PDF::Parser::AutoChar;

use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use List::MoreUtils qw(first_index);
use Data::Dumper;
use Array::Utils qw/array_diff/;
#use POSIX qw/strftime/;
use Time::Piece;

use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

sub parseAutoChar {
	my $self = shift;
	my $infile = shift;
	my $ln_cnt = 0;
	my %autoCharData;
	my $header = new_headerLong;
	my $model  = new_model({
		misc => {},
		dataSource => ''
	});
	
	my $fname = basename $infile;	
	#$fname =~ s/\.csv.*$/\.csv/;
	my $headerFlg = 1;
	my $dataFlg = 0;
	my $paramFlg = 0;
	my %fieldHash;	
	my %results;
	my @testnames = ();
	my @testNameArrIndx = ();		
	my @colHeaders = ();	
	my @indexRefArr = ('LOTID','WAFER','WAFER_LONG','DIE','X','Y','FID','T_[C]','COLOR','GAIN','RETICLE','REGION','BOOTUP','COLUMN_GAIN','DBLC','DCG','EFFECTIVE_GAIN','FNUM','FRAMECOUNT','FRAMESETNAME','GAIN_LEVEL','PARAMID','PEDESTALS','REGIONDESC','REPEAT','SPECTRUM','VAA_[V]','VAA-PIX_[V]','VDD_[V]','VDD-IO_[V]','VDD-PHY_[V]','VDD-SLVS_[V]','VDUTIO_[V]','XP','YP','HCG/LCG_RATIO','POWERSET','CORRECTIONS','SHOWDARKRC');
	my @exnIndexRefArr = ('WAFER_LONG','DIE','X','Y','FID','T_[C]','COLOR','GAIN','RETICLE','REGION','BOOTUP','COLUMN_GAIN','DBLC','DCG','EFFECTIVE_GAIN','FNUM','FRAMECOUNT','FRAMESETNAME','GAIN_LEVEL','PARAMID','PEDESTALS','REGIONDESC','REPEAT','SPECTRUM','VAA_[V]','VAA-PIX_[V]','VDD_[V]','VDD-IO_[V]','VDD-PHY_[V]','VDD-SLVS_[V]','VDUTIO_[V]','XP','YP','HCG/LCG_RATIO','POWERSET','CORRECTIONS','SHOWDARKRC');
	my $lotid = "";
	my $wafernumber = "";

	push @colHeaders, "DATAFILENAME"."=".$fname; #add datafilename meta index
	
	open FH, $infile or die "can't open $infile\n";
	while(my $line=<FH>){
		$ln_cnt++;			
		chomp $line;
		#print $line, "\n";
		if ($line =~ /^\[data\]/i) { 
			#print $line, "\n";
			$dataFlg = 1;
			$headerFlg = 0
		}
		elsif ($line =~ /^LotId/i && $dataFlg == 1) { #parameters
			#print $line, "\n";
			$paramFlg = 1;
			$headerFlg = 0;
			my @arr = split (/\,/, $line);
						
			for (my $i=0; $i<=$#arr; $i++) {
				my $field = trim($arr[$i]);
				$field =~ s/\s+/\_/g;
				$field = uc $field;
				$fieldHash{$field} = $i;
								
				unless ( grep { $_ eq $field } @indexRefArr ) {
					push @testNameArrIndx, $i;					
					#print "$field\n";
					push @testnames, $field;
				}							
			}			
								
			#print Dumper \%fieldHash;						
			#print "@testNameArrIndx\n";
			#print "@testnames\n";
						
		}
		elsif ($headerFlg == 1 && $dataFlg == 0 && $paramFlg == 0) { #headers
			#print $line, "\n";
			my $str = "";
			my @arr = split (/\=/, $line);			
			$arr[0] =~ s/\s+/\_/g;
			$arr[0] = uc($arr[0]);			
			
			if($arr[0] eq "FILE_CREATED"){ #format date time from 7/19/2023 9:34:18 PM to %Y/%m/%d %H:%M:%S
				my $t = Time::Piece->strptime($arr[1], "%m/%d/%Y %l:%M:%S %p");
				#print "$arr[1]--->",$t->strftime("%Y/%m/%d %H:%M:%S"),"\n";
				$arr[1] = $t->strftime("%Y/%m/%d %H:%M:%S");
			}

			$str = $arr[0]."=".$arr[1];
			push @colHeaders, $str;
			#print join ("\n", @colHeaders);
		}
		else { #readings
			#print $line, "\n";			
			$line =~ s/(\([-]*\d{1,})(\,)([-]*\d{1,}\))/$1|$3/g;
			$line =~ s/=//g;
			#print $line, "\n";
			my @arr = split (/\,/, $line);
								
			my @readings = ();
			my @idxreadings = ();
			my @foundExnIdx = ();
						
			foreach my $k (sort {$fieldHash{$a} <=> $fieldHash{$b}} keys %fieldHash){  #sort hash by numerical value of values
				#print "$k = $fieldHash{$k}\n";
				if (my ($matched) = grep $_ eq $fieldHash{$k}, @testNameArrIndx) { #get parametric readings
					#print "$ln_cnt = $k = $arr[$matched]\n";
					push @readings, $arr[$matched];
				}
				
				if (my ($matched) = grep $_ eq $k, @exnIndexRefArr) { # get index readings
					#print "found it = $ln_cnt = $k = $matched = $arr[$fieldHash{$k}]\n";
					push @idxreadings, $matched."=".$arr[$fieldHash{$k}];
					push @foundExnIdx, $matched;
				}
										
			}
			
			my @notFoundExnIdx = array_diff(@exnIndexRefArr, @foundExnIdx); #get not found indexes
			
			foreach my $e (@notFoundExnIdx){ #put NA value to not found indexes
				my $str = $e."="."NA";
				push @idxreadings, $str;
			}
			my @sortedIdxReadings = sort @idxreadings;
			
			if ( exists $fieldHash{LOTID} ) {
				my $arrValue = trim($arr[$fieldHash{LOTID}]);
				$lotid = repNA($arrValue);
			}
			if ( exists $fieldHash{WAFER} ) {
				my $arrValue = trim($arr[$fieldHash{WAFER}]);
				$wafernumber = repNA($arrValue);
			}	
						
			#print "@foundExnIdx\n";
			#print "@notFoundExnIdx\n";
			#print "$ln_cnt = @readings\n";
			#print "$ln_cnt = @idxreadings\n";			
			
			$results{$ln_cnt}{VAL} = [@readings];			
			$results{$ln_cnt}{IDX} = [@sortedIdxReadings];
			
			$autoCharData{LOT} = $lotid;
			$autoCharData{WFN} = $wafernumber;
			$autoCharData{RES} = \%results;
			$autoCharData{HED} = [@colHeaders];
			$autoCharData{PAR} = [@testnames];
		}
		
		
	}
	close FH;
	
	#print Dumper \%autoCharData;
	
	$model->misc(\%autoCharData);
	
	return $model;
	
}

1;
