 # SVN $Id: HP_ET_CSV.pm
 # 29-Nov-2019	Karen	Newly created parser to load WAT file in csv format from Vanguard
 

package PDF::Parser::HP_ET_CSV;
use strict;
use Getopt::Long;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";
my $testNum = 1;


my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

sub readFile {
	my $self   = shift;
    	my $infile = shift;
	my $platform = shift;
	my $site = shift;
    	my $header = new_headerLong;
    	my $model  = new_model(
        {   header => $header,
            misc   => {},
            dataSource => 'HP'
        }
    	);
	
	
	my @hilim;
	my @lolim;
	my @units;
	my @testnames;
	my %hash;

	open (INFILE, "<",$infile);
    	
	while (my $line=<INFILE>) {
		$line =~ s/,\s*$//;
		my @arr = split /\,/, $line;
		chomp $line;  

		if ($line =~ /^VIS Lot ID:/i) {
			 my $lot = $arr[1]; 
			 $lot =~ s/^\s+|\s+$//g;

			 $header->LOT($lot);
		}

		 if ($line =~ /^Process:/i) {
		 	my $program = $arr[3];
			$program =~ s/^\s+|\s+$//g;
	   	 
		 	$header->PROGRAM($program);
		 }
		 
		 if ($line =~ /^Customer Product ID:/i) {
			my $product = $arr[1];		
		 	$product =~ s/^\s+|\s+$//g;

			$header->PRODUCT($product);
		}

		 if ($line =~ /^WAT Date:/i) { 
		 	my $date = $arr[1];
		 	$date =~ s/^\s+|\s+$//g;

			$header->START_TIME( $date . " 00:00:00" );
			$header->END_TIME( $date . " 00:00:00" );
		 }
		
		if ($line =~ /^Wafer/i) {
			@testnames = splice @arr, 2;
		}	

		if ($line =~ /^ID/i) {
			@units = splice @arr, 2;
		}	
		
		if ($line =~ /^Spec High/i) {
			@hilim = splice @arr, 2;
		}
		
		if ($line =~ /^Spec Low/i) {
			@lolim = splice @arr, 2;
		}

 	 	if ($line =~ /^\d+/ && ($arr[1] =~ /^\d+/ || $arr[1] =~ /^\s+\d+/) ) {
	 		my $wafer_num = shift @arr;
  	 		$wafer_num = trim($wafer_num);
			my $site = shift @arr;
			$site = trim($site);
	
			$hash{$wafer_num}{$site} = {result => \@arr};
		}
	}

close(INFILE);
my $wafer;
foreach my $wafer_num (sort keys %hash) {
	$wafer = $model->find('wafers',{number => $wafer_num});
	 unless (defined $wafer){        
	 	$wafer = new_wafer;
				 #assign source lot as wafer name
                                if ($header->SOURCE_LOT ne ""){
                                        $wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
                                        $model->misc->{wf_flg} = 1;
                                }	
		
		$wafer->number($wafer_num);    
		$model->add('wafers',$wafer);
	}
	
		foreach my $site (sort keys %{ $hash{$wafer_num} }) {
			my $die = new_die;
			$die->site($site);
			my $result = $hash{$wafer_num}{$site}{result};
				foreach my $resu (@{$result}) {
				      $die->add( 'result', repNA($resu));
				} 
				      $wafer->add('dies',$die);
		}

}

for (my $i=0; $i <= $#testnames; $i++) { 

	my $test = new_test;
	$test->number($i+1);
	$test->name(trim($testnames[$i]));
	$test->units(trim($units[$i]));
	$test->HSL(trim($hilim[$i]));
	$test->LSL(trim($lolim[$i]));

	$model->add('tests',$test);
}


return $model;

}
1;
