#
#2015-Aug-26 Gilbert 	- Uppercase the lot id.
#2017-Apr-06 Eric	- populate source lot and assign as wafer name
#2017-Apr-26 eric	- return error msg as misc. some postion to site were spelled out
#2017-Jul-03 eric	- skip if site, die xy are empty
#2019-Apr-23 eric	- modified parser to be more robust to fix missing wafer and site
#2021-Jun-05 jgarcia - replace N/A to result with no value. fixed jira issue CE-340.
#2021-Nov-15 jgarcia - remove unnecessary characters from the extacted values such as new line, spaces, etc.
#                    - this is the solution for CE-578 issue .
package PDF::Parser::BKET_HP;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use v5.10;
use Data::Dumper;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

my $attr = [ qw/minX minY maxX maxY/];
sub array {
   return qw/testConditions_EPDR/;
}

__PACKAGE__->mk_accessors(array);

=pod

=cut

sub readFile{
  	my $self = shift;
  	my $infile = shift;
  	my $testPlan = shift;

  	open (INFILE, $infile);
  	my $header = new_headerLong;
  	my $wmap = new_wmap({
     		positive_x => 'R',
     		positive_y => 'D'
     	});
  	my $model = new_model({
    		header=>$header,
    		misc => {},
		wmap => $wmap,
    		dataSource => 'HP'
   	});

  	my %wfSize = (
        	4   => 100,
        	6  => 150,
        	8 => 200,
        	12 => 300,
	);
 	 my %flatDir = (
        	0   => 'T',
        	90  => 'R',
        	180 => 'B',
        	270 => 'L',
	);
  	my $wafers = {};
  	my $waferSites = {};
  	my $wafer;
  	my $testNum = 1;
  	my @sites;
  	my %data;
  	my $section = "Header";
  	my ($columns, $rows);
  	my $wfNum;
  	my $test_num;
  	my $test_num_pre;
  	my $test_units;
  	my %test_limit;
  	my $RecordType     = "";
  	my %test_limit_count;
  	my %test_limit_units;
  	my %hash_site;
  	my $test_name;
  	my %h_test;
  	my $first_sv = 1;
  	my (%test_limit_lsl, %test_limit_lol, %test_limit_hol, %test_limit_hsl) = ();
  	my (@RecordCnt,@ary_test_nam, @ary_test_no, @ary_wafer, @su)   = ();
	my $line = "";

  	while($line = <INFILE>)
  	{
		$line =~ s/\015//;
		$line =~ s/\cM\n/\n/;
		$line =~ s/^\s+//;
		$line =~ s/\s+$//;
		chomp($line);

		($RecordType, $RecordCnt[0], $RecordCnt[1], $RecordCnt[2]) = split /\s+/, $line;

  		if ($line =~ /^#HR /) {
			$section = "file";
		}
		if ($line =~ /^#SV /) {
			$section = "data";
			if ( $first_sv ){
		  		$wfNum = shift @ary_wafer;
		  		$first_sv = 0;
			}
		}
		if ($line =~ /^#HC /) {
			$section = "tester";
		}
		if ($line =~ /^#IV /) {
			$section = "tests";
		}
		if ($line =~ /^#TW /) {
			$section = "wafer";
			$first_sv =1;
		}
		if ($line =~ /^#HI /){
			$section = "wafer_id";
		}
		if ($line =~ /^#HP /){
			$section = "site_info";
		}
		if ($line =~ /^#SN /){
			$section = "tests_info";
		}
		if ($line =~ /^#SY /){
			$section = "";
			@su = ();
		}
		if ($line =~ /^#SL /) {
			$section = "limit_cnt";
		}
		if ($line =~ /^#SU /) {
			$section = "spec_limits";
		}

		if ($line =~ /^#HF /) {
			$section = "date";
		}

		if ($line =~ /^#HS /) {
			$section = "lotid";
		}

		if ($section eq "wafer_id"){

			for ( my $i=1; $i<=$RecordCnt[0]; $i++)
			{
				my $ln = <INFILE>;
				push @ary_wafer, trim($ln);

			}
			$section = "";
		}

		if ($section eq "site_info") {

			my @item = split /\s/, $line;

			my $numSites = int(trim($item[1]))/2;

			for ( my $i=1; $i<=$numSites; $i++){
				@item = split /\s/, <INFILE>;

				my $s_value = pos2Site(trim($item[1]),$i);

				$sites[$i][0] = pos2Site(trim($item[1]),$i);
				$sites[$i][1] = trim($item[0]);
				my $x_value = trim($item[0]);

				my $wk = <INFILE>;
				chomp $wk;
        $wk = trim($wk);
				my $y_value = $wk;

				$sites[$i][2] = $wk;
				$hash_site{$x_value}{$y_value} = $s_value;


			}
			$section = "";

		}

		if ($section eq "tests_info"){

			for (my $i=1; $i<=$RecordCnt[0]; $i++) {
				my $ln = <INFILE>;
				chomp $ln;
        $ln = trim($ln);
				if ($i == 1) {

				}
				elsif ($i == 2) {
					$test_name = trim($ln);

				}
				elsif ($i == 11) {

					$ln =~ s/\s+//g;
					$ln =~ s/\-/\_/g;
          $ln = trim($ln);
					my ($wk1, $wk2) = split(',', $ln);
					my ($wk3, $wk4) = split('_', $wk1);
					$test_num = trim($wk3);

                		        if ($test_num eq $test_num_pre)
                        		{
                        		       ($wk1,$wk2) = split(/\_/,$wk2);
                        		       $test_num = trim($wk1);

                        		}

					$test_num_pre = $test_num;

				}
				elsif ($i == 12) {

					my ($tmp0,$tmp1,$tmp2) = split(/\s+/,$ln);

					if ($tmp1 eq "R")
                		        {
                        		       $test_units = trim($tmp2);
                        		}
                        		else
                        		{
                        		       $test_units = trim($tmp1);
                        		}
					$test_units =~ s/\s+//g;
					$test_limit_units{$test_num} = trim($test_units);

				}

			} #end for loop

			$section = "";

		}


		if($section eq "data"){
			my $x;
			my $y;

			if ( $RecordCnt[0] == 0) {

				my $msg =  "No test data.";
				$model->misc->{err_msg} = $msg;
			}

			my $divisible = "";
			my $partcnt = "";
			if ( $RecordCnt[0] != 0) {
			 	$divisible = $RecordCnt[0] % 3;
			}

			if ( $divisible == 0 ) {
				$partcnt = $RecordCnt[0] / 3;

			}
			else {

				my $msg = "Site count does not match with number of test";

				$model->misc->{err_msg} = $msg;
			}

			for ( my $i=1; $i<=$partcnt; $i++) {
				if($i >= 0){
					$x = <INFILE>;
					$y = <INFILE>;
				  $x = trim($x);
          $y = trim($y);

				}
				my $val = <INFILE>;
				chomp $val;
        $val = trim($val);
				$data{$wfNum}{$hash_site{$x}{$y}}{$x}{$y}{$test_num} = $val;
				$h_test{$test_name} = $test_num;

			}

			$section = "";
		}

		my $i_limit = 0;

		if ( $section eq "limit_cnt"){

			for( my $i=1; $i<=$RecordCnt[0]; $i++){
				my $ln = <INFILE>;
				$ln = trim($ln);
				my ($tmp1,$tmp2) = split(/\s+/, $ln);
				$test_limit{$test_num}[$i-1] = trim($tmp1);
				$test_limit_count{$test_num} = $RecordCnt[0];
			}
			$section = "";
		}

		if ($section eq "spec_limits") {

			for( my $i=1; $i<=$RecordCnt[0]; $i++)
			{
				my $ln = <INFILE>;

				chomp ($ln);
        $ln = trim($ln);
				my($tmp1,$tmp2) = split(/\,/, $ln);
				$tmp2 = substr($tmp2,0,1);

				if ($i == 1)
				{
					$test_limit_lsl{$test_num} = $test_limit{$test_num}[$tmp1];
					$test_limit_hsl{$test_num} = $test_limit{$test_num}[$tmp2];

					if ( $RecordCnt[0] == 1 )
					{
						$test_limit_lsl{$test_num} =  -1E+21 ;
						$test_limit_hsl{$test_num} = 1E+21;
					}
				}
				elsif ($i == 2)
				{
					$test_limit_lol{$test_num} = $test_limit{$test_num}[$tmp1];
					$test_limit_hol{$test_num} = $test_limit{$test_num}[$tmp2];
				}

			}
			$section = "";
		}

		if ( $section eq "tests" ){

			for (my $i=1; $i<=$RecordCnt[0]; $i++)
			{
				my $ln = <INFILE>;
				$ln = trim($ln);

				push @ary_test_nam, repNA($ln);
			}

			$section = "";
		}

		# date
		if ($section eq "date"){
			my $date = "";
			my $time = "";

			for (my $i=1; $i<=$RecordCnt[0]; $i++)
			{
				my $ln = <INFILE>;
				$ln = trim($ln);
				if ( $i == 2) {
					$date = trim($ln);
				}
				elsif ( $i == 3 ) {
					$time = trim($ln);
				}
			}
			$header->START_TIME($date." ".$time);

			$section = "";

		}

		# lot
		if ( $section eq "lotid" ) {
			my $lotid = "";


			for (my $i=1; $i<=$RecordCnt[0]; $i++)
			{
				my $ln = <INFILE>;
				$ln = trim($ln);
				if ($i == 4) {
					$lotid = trim($ln);
					$lotid = uc($lotid);
				}

			}
			$header->LOT($lotid);
			$header->populateSrcLot;

			$section = "";
		}


		if($section eq "tester"){

			my $equip_id1 = "";
			for (my $i=1; $i<=$RecordCnt[0]; $i++)
			{
				my $ln = <INFILE>;
				$ln = trim($ln);
				my @item = split /\=/, $ln;
				if ($item[0] eq "HOSTNAME") {
					$equip_id1 = "SPECS_".$item[1];
				}
			}
			$header->EQUIP1_ID($equip_id1);

			$section = "";
		}

		if ( $section eq "file" ){

			for (my $i=1; $i<=$RecordCnt[0]; $i++)
			{
				my $ln = <INFILE>;
				$ln = trim($ln);
				my @item = split /\s/, $ln;

				if ( $item[0] eq "TESTPLAN") {
					 my @limFile = split("/",trim($item[1]));
					 @limFile = split(/\s/,@limFile[scalar(@limFile)-1]);
					 $header->PROGRAM(@limFile[0]);
				}
				elsif ( $item[0] eq "LIMIT" ) {
					my @limFile = split($header->PROGRAM,trim($item[1]));
					@limFile = split("_",@limFile[scalar(@limFile)-1]);
					$header->REVISION(@limFile[1]);
				}
			}

			$section = "";
		}

  	}

	for( my $i=0; $i<=$#ary_test_nam; $i++){
		my $test = new_test;
		$test->number($h_test{$ary_test_nam[$i]});
		$test->name(repNA($ary_test_nam[$i]));
		$test->units($test_limit_units{$i+1});
		$test->LSL(trim($test_limit_lsl{$h_test{$ary_test_nam[$i]}}));
		$test->HSL(trim($test_limit_hsl{$h_test{$ary_test_nam[$i]}}));
		$test->LOL(trim($test_limit_lol{$h_test{$ary_test_nam[$i]}}));
		$test->HOL(trim($test_limit_hol{$h_test{$ary_test_nam[$i]}}));

		#print "$test->{number},$test->{name},$test->{units},$test->{LSL},$test->{HOL},$test->{LOL},$test->{HOL}\n";

		$model->add('tests',$test);

		push @ary_test_no, $h_test{$ary_test_nam[$i]};
  	}

  	####### fill data set
  	foreach my $wfNum (keys %data){

		foreach my $site (keys %{$data{$wfNum}}){

			next if $site eq "";
			foreach my $x (keys %{$data{$wfNum}{$site}}){

				foreach my $y (keys %{$data{$wfNum}{$site}{$x}}){

					next if ($site eq "" && $x eq "" && $x eq "");
					$wafer = $model->find('wafers',{number => $wfNum});

					unless (defined $wafer){
				   		$wafer = new_wafer( { number => $wfNum } );
						if ($header->SOURCE_LOT ne "") {
							$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
						}
				   		$model->add('wafers',$wafer);
					}
          
					my $die = $wafer->find('dies',{site=>$site, x=>$x, y=>$y});


					unless (defined $die){
				   		$die = new_die( { site => $site, x=>$x, y=>$y } );
				   		$wafer->add('dies',$die);
					}

					for( my $i=0; $i<=$#ary_test_nam; $i++){
						$die->add( 'result', repNA($data{$wfNum}{$site}{$x}{$y}{$ary_test_no[$i]}));

					}
				}
			}
		}
  	}

	return $model;
}

sub FillWafer
{
	my @data = @_;
	my $die;


}

sub Print2DArray
{
	my @Arr = @_;
	for(my $i=0;$i<scalar(@Arr);$i++){
		for(my $j=0;$j<=$#{$Arr[0]};$j++){
			INFO($Arr[$i][$j]);
		}
		INFO("----------------------------------------------------------------------------------");
	}
}

sub pos2Site
{
	my $pos = shift;
	my $i = shift;

	if ($pos eq 'T' || $pos =~ /^T/i) { return 1; }
	elsif ($pos eq 'C' || $pos =~ /^C/i) { return 2; }
	elsif ($pos eq 'B' || $pos =~ /^B/i) { return 3; }
	elsif ($pos eq 'L' || $pos =~ /^L/i) { return 4; }
	elsif ($pos eq 'R' || $pos =~ /^R/i) { return 5; }
	else { return $i + 1; }
}

1;
