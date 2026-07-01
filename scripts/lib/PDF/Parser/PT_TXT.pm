#CHANGES
#  2015/08/12 grace : new_bin
#  2015/09/18 eric  : changed datasource from POWERTEC to QTEC to match datasource of its datalog (xls)
#  2015/10/20 eric  : extract rev from last char in ppid
package PDF::Parser::PT_TXT;
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


my $attr = [];
my @bins;
my $good_bin;

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

=pod
 Lot Id :
============================================================================
 PowerTech Tester        Update Time:2015-8-31 0:44:23      Auto-Clear Counter When then window be closed
 Station <M>             Counter file name: FSC\GM5840419N_LHRFT_      Log data file name: FSC\GM5840419N_LHRFT_
 FileName: <\\10.11.100.8\TestSH-Program\QTEC4000 TEST PRORAM\Final test\FSC\PFDS6679AZ-GA.ptf>
 Comment :
 Pass    :        34981  99.93 %
 Fail    :           26   0.07 %
 Total   :        35007 100.00 %

============================================================================
 M#  ItemName                      Counter                Fail     Percent
----------------------------------------------------------------------------
  1  CONT                            35007                   0       0.00 %
  2  VTH                             35007                   0       0.00 %
  3  SAME                            35007                  13       0.04 %
  4  SAME                            34994                   1       0.00 %
  5  BVDSS                           34993                   2       0.01 %
  6  SAME                            34991                   0       0.00 %
  7  IGSS                            34991                   5       0.01 %
  8  RDON                            34986                   1       0.00 %
  9  RDON                            34985                   0       0.00 %
 10  VDSON                           34985                   0       0.00 %
 11  CONT                            34985                   0       0.00 %
 12  IGSS                            34985                   0       0.00 %
 13  IDSS                            34985                   4       0.01 %
 14  IGSS                            34981                   0       0.00 %
 15  VTH                             34981                   0       0.00 %

============================================================================
 S# Bin# SortComment               Counter    Percent       Pass       Fail
----------------------------------------------------------------------------
  1    1 FDS6679AZ                   34981    99.93 %   100.00 %
  2    2 CONT1                           0     0.00 %                0.00 %
  3    3 FUNC OPEN                       0     0.00 %                0.00 %
  4    3 FUNC SHORT                     13     0.04 %               50.00 %
  5    4 VTH                             1     0.00 %                3.85 %
  6    4 FUNC BV                         2     0.01 %                7.69 %
  7    4 BVDSS                           0     0.00 %                0.00 %
  8    4 IGSSF                           5     0.01 %               19.23 %
  9    4 RDSON                           1     0.00 %                3.85 %
 10    4 VSD                             0     0.00 %                0.00 %
 11    2 CONT2                           0     0.00 %                0.00 %
 12    4 IGSSR                           0     0.00 %                0.00 %
 13    4 IDSS                            4     0.01 %               15.38 %
 14    5 POST O/S                        0     0.00 %                0.00 %
 15    2 REJECT                          0     0.00 %                0.00 %

=cut

sub readFile {
    my $self   = shift;
    my $infile = shift;
	my $platform = shift;
    my $header = new_headerLong;
    my $model  = new_model(
        {   header => $header,
            misc   => {},
            dataSource => 'QTEC'
        }
    );
    my $wafers = {};    
	my $seq = 0;    
	my $waferNum;		
	my $begin_data = 0;
	my $wafer;	
	my $test = new_test;
	my $idx_Sort 	;
	my $idx_Counter;
	my $idx_Percent	;
	
    open (INFILE, "<",$infile);
    while (<INFILE>) {
		s/\015//;
		s/\cM\n/\n/;
		chomp;
		my $line = $_;
		
		$seq++;
		
		if($line =~ /PowerTech/){
		
			if($line =~ /Update Time:(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/){
				
				my $year = $1;
				my $month = getTwoDigit($2);
				my $day = getTwoDigit($3);
				my $hour = getTwoDigit($4);
				my $minutes = getTwoDigit($5);
				my $second = getTwoDigit($6);
				
				$header->START_TIME("$year-$month-$day $hour:$minutes:$second");
				$header->END_TIME("$year-$month-$day $hour:$minutes:$second");
			}
			$header->EQUIP1_ID("PTS-4000");
		}
		elsif($line =~ /Station/){
		
			my @item = split(':', $line);
			@item = split('_', $item[1]);
			@item = split(/\\/, $item[0]);			
			$header->LOT($item[1]);			
			
			$waferNum = 0;
			$wafer = $model->find('wafers',{number => $waferNum});
            unless (defined $wafer){
               $wafer = new_wafer( { number => $waferNum } );
               $model->add('wafers',$wafer);
			}		
		}
		elsif($line =~ /FileName/){
		
			my @item = split(/\\/, $line);	
			my @wk = split(/\./, $item[-1]);
			my $rev = substr $wk[0], -1;
			$header->PROGRAM($wk[0]);
			$header->REVISION($rev);
			@item = split(/\-/, $item[-1]);			
			$item[0] =~ s/^[P|Q]//g;
						
			$header->PRODUCT($item[0]);
			INFO($header->PRODUCT);
			$header->EQUIP1_ID("PTS-4000");
			
		}
		elsif($line =~ /Pass/ and $line =~ /%/){
		
			my @item = split(/\s+/, $line);	
			$good_bin = $item[3];
			
		}
		elsif($line =~ /S#/){
			$begin_data = 1;
			$idx_Sort 	= index($line, "SortComment");
			$idx_Counter = index($line, "Counter");
			$idx_Percent = index($line, "Percent");		
		}
		elsif($begin_data){		
					
			my @item = split(/\s+/, $line);			
			my $pf = "F";
			next if($item[1] eq "");
			my $bin_number =  $item[1];
			my $bin_name = trim(substr($line, $idx_Sort, $idx_Counter-$idx_Sort));			
			my $bin_count = trim(substr($line, $idx_Counter, $idx_Percent-$idx_Counter));			
			if($good_bin eq $bin_count )
			{
				$pf = "P";
			}
			my $bin = new_bin(
							{   number => $bin_number,
								name   => $bin_name,
								count  => $bin_count,
								PF     => $pf
							}
						);
		
			$wafer->add( 'sbins', $bin );		
		}
    }			
    return $model;
}

sub getTwoDigit{

	my $value = shift;
	
	if(length($value) eq 1)
	{
		$value = "0".$value;
	}
	
	return $value;

}
1;

