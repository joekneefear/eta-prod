# SVN $Id: Generic.pm 2216 2017-07-07 02:11:47Z dpower $
# 2015-04-23 hm fixed handler (HAND_ID) missing issue
# 2015-05-21 eric - make start time as end time if finish time = 0
# 2015-06-10 grace - check the value of TEST_FLG to see if the result of the test is valid, reliable and was actually executed. 
#                    If not, then the value should not be loaded.
# 2015-08-25 gilbert - uppercase LOT value always.
# 2016-02-22 eric	: modified to replace NA for blank results in sub res2dies_sum 
# 2016-03-16 eric	: added hash cnt in res2dies_sum
# 2016-04-16 eric	: rounded off R*4 conditions in EPDR that are stored in Exensio-Yield as text: VCC, VEE, TEMP, FREQ.
# 2016-06-02 eric	: added sub res2testsV2 &  res2mprTestsV2 to cater ATEC requirement
# 2016-07-01 eric	: added sub res2dies_v2 to cater ME reedholm data
# 2016-09-28 eric	: corrected $prr->{Y_COORD} to $pir->{Y_COORD} in sub res2dies_v2
# 2016-10-28 eric	: fixed parsing test names with "|" in sub res2test
# 2016-11-11 jgarcia : sanitize revision.
# 2016-11-18 eric	: fixed parsing test names with "|" in sub res2mprTests
# 2017-01-18 eric	: added subroutine epdr2sbins, epdr2hbinsV2 to handle amkor_ph_ft_fet data
# 2017-07-04 carmilo 	: added subroutine sbr2bins_v2 to handle pmft_advan data
# 2021-04-02 jgarcia : fixed defined(%hash) is deprecated on newer perl version.

package PDF::Parser::Stdf::Generic;
use strict;
use PDF::Parser::Stdf::Model;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

sub array {
    return qw/testConditions_EPDR/;
}

__PACKAGE__->mk_accessors(array);

sub epdr2tests {
    my $self = shift;
    my $epdr = shift;
    my @tests;
    foreach ( @{$epdr} ) {
        my $test = new_test;
        $test->name( $_->{TEST_NAM} );
		#INFO($test->name);
        $test->number( $_->{TEST_NUM} );
        $test->units( $_->{UNITS} );
        $test->LOL( $_->{LO_CENSR} );
        $test->HOL( $_->{HI_CENSR} );
        $test->LSL( $_->{LO_LIMIT} );
        $test->HSL( $_->{HI_LIMIT} );

        if ( defined $self->testConditions_EPDR ) {
            foreach my $key ( @{ $self->testConditions_EPDR } ) {
	        if ($key =~ /VCC|VEE|TEMP|FREQ/i) {
			($_->{$key} = sprintf "%0f\n", $_->{$key}) =~ s/\.?0+$//;
		}
                $test->add( 'conditions', $_->{$key} );
            }
        }
		
		unless($test->name =~ /^SWBin/){
			push @tests, $test;
		}
    }
    return \@tests;
}

sub sbr2bins_removeTests {
    my $self = shift;
    my $sbr  = shift;
    my $good_count  = shift;
	my $tests = shift;
    my @bins;
    my %totalCount;
    my %unique;
	my $pass = 0;
		
	#INFO("pass_count:".$good_count);
    foreach (@$sbr) {
        my $binNum   = $_->{SBIN_NUM};
        my $binCount = $_->{SBIN_CNT} + 0;

		
		
        $totalCount{$binNum} += $binCount;
		#INFO($_->{SBIN_NUM}."/".$_->{SBIN_NAM}."/".$binCount."/".$totalCount{$binNum});
        if ( exists $unique{$binNum} ) {
		
            $unique{$binNum}->count( $totalCount{$binNum} );
			
			if($good_count eq $totalCount{$binNum} )
			{
				$unique{$binNum}->PF('P');
				$pass = 1;	
				#INFO("inside 76");
			}
			
            next;
        }		
				
        my $bin = new_bin;
        $bin->number( $_->{SBIN_NUM} );
        $bin->name( $_->{SBIN_NAM} );
        $bin->count( $_->{SBIN_CNT} + 0 );
        if ( exists( $_->{SBIN_PF} ) and trim( $_->{SBIN_PF} ne '' ) ) {
            $bin->PF( $_->{SBIN_PF} );
        }
        else {
            $bin->PF('F');

			if($good_count eq $bin->count)
			{
				 $bin->PF('P');
				 $pass = 1;
				 #INFO("inside 76");
			}
			
        }
        $unique{$binNum} = $bin;
    }
	
	if($good_count ne "")
	{
		unless($pass){
			if(defined $unique{0}){
				dpExit(3, "SBR deosn't have pass bin and has '0' for fail " );
			}
			my $bin = new_bin;
			$bin->number( 0 );
			$bin->name( "PASS" );
			$bin->count( $good_count);
			$bin->PF('P');
			$unique{0} = $bin;
		}
	}
    foreach my $binNum ( sort { $a <=> $b } keys %unique ) {
	
		my $test_bin = 0;
		 foreach my $test (@$tests) {
			if( $test->{name} eq $unique{$binNum}->name) {
				$test_bin = 1;
			}
		 
		 }
		 
		 if($test_bin eq 0){
			push @bins, $unique{$binNum};
		 }
        
    }
    return \@bins;
}

sub sbr2bins_v2 {
	my $self = shift;
	my $sbr = shift;
	my $good_count = shift;
	my @bins;
	my %totalCount;
	my %unique;
	my $pass = 0;

	foreach(@$sbr) {
		my $binNum = $_->{SBIN_NUM};
		next if $binNum > 16000;
		my $binCount = $_->{SBIN_CNT} + 0;
		
		$totalCount{$binNum} += $binCount;
		
		if(exists $unique{$binNum}) {
			$unique{$binNum}->count($totalCount{$binNum});
			if($good_count eq $totalCount{$binNum}) {
				$unique{$binNum}->PF('P');
				$pass = 1;
			}elsif($binNum == 1 && $good_count eq "") {
				$unique{$binNum}->PF('P');
				$pass = 1;
			}
			next;
		}
		
		my $bin = new_bin;
		$bin->number( $_->{SBIN_NUM} );
	        $bin->name( $_->{SBIN_NAM} );
	        $bin->count( $_->{SBIN_CNT} + 0 );

		if ( exists( $_->{SBIN_PF} ) and trim( $_->{SBIN_PF} ne '' ) ) {
			$bin->PF( $_->{SBIN_PF} );
		} else {
		        $bin->PF('F');
			if($good_count eq $bin->count) {
				$bin->PF('P');
	                        $pass = 1;
			}elsif($binNum == 1 and $good_count eq "") {
				$bin->PF('P');
				$pass = 1;
			}
		}
		if($binNum ne ""){
			$unique{$binNum} = $bin;
		}
	}
	
	if($good_count ne "") {
		unless($pass){
			if(defined $unique{0}){
				dpExit(3, "SBR deosn't have pass bin and has '0' for fail " );
			}
			my $bin = new_bin;
			$bin->number( 0 );
			$bin->name( "PASS" );
			$bin->count( $good_count);
			$bin->PF('P');
			$unique{0} = $bin;
		}
	}

	foreach my $binNum ( sort { $a <=> $b } keys %unique ) {
		push @bins, $unique{$binNum};
	}

	return \@bins;
}

sub sbr2bins {
    	my $self = shift;
    	my $sbr  = shift;
    	my $good_count  = shift;
    	my @bins;
    	my %totalCount;
    	my %unique;
    	my $pass = 0;
		
    	#INFO("pass_count:".$good_count);
    	foreach (@$sbr) {
        	my $binNum   = $_->{SBIN_NUM};
		next if $binNum > 16000;
        	my $binCount = $_->{SBIN_CNT} + 0;

        	$totalCount{$binNum} += $binCount;
		
        	if ( exists $unique{$binNum} ) {
		
            		$unique{$binNum}->count( $totalCount{$binNum} );
			
			if($good_count eq $totalCount{$binNum} )
			{
				$unique{$binNum}->PF('P');
				$pass = 1;	
				#INFO("inside 76");
			}
			
            		next;
        	}		
				
        	my $bin = new_bin;
        	$bin->number( $_->{SBIN_NUM} );
        	$bin->name( $_->{SBIN_NAM} );
        	$bin->count( $_->{SBIN_CNT} + 0 );

        	if ( exists( $_->{SBIN_PF} ) and trim( $_->{SBIN_PF} ne '' ) ) {
            		$bin->PF( $_->{SBIN_PF} );
        	}
        	else {
            		$bin->PF('F');

			if($good_count eq $bin->count)
			{
				 $bin->PF('P');
				 $pass = 1;				
			}
			
        	}

		if($binNum ne ""){
			$unique{$binNum} = $bin;
		}
    	}
	
	if($good_count ne "")
	{
		unless($pass){
			if(defined $unique{0}){
				dpExit(3, "SBR deosn't have pass bin and has '0' for fail " );
			}
			my $bin = new_bin;
			$bin->number( 0 );
			$bin->name( "PASS" );
			$bin->count( $good_count);
			$bin->PF('P');
			$unique{0} = $bin;
		}
	}

    	foreach my $binNum ( sort { $a <=> $b } keys %unique ) {
        	push @bins, $unique{$binNum};
    	}

    	return \@bins;
}


sub hbr2bins {
    my $self = shift;
    my $sbr  = shift;
	my $good_count  = shift;
    my @bins;
    my %totalCount;
    my %unique;
	my $pass = 0;
	
    foreach (@$sbr) {
        my $binNum   = $_->{HBIN_NUM};
		
		next if $binNum > 16000;
		
        my $binCount = $_->{HBIN_CNT} + 0;
        $totalCount{$binNum} += $binCount;
		
		#INFO($_->{HBIN_NUM}."/".$_->{HBIN_NAM}."/".$binCount."/".$totalCount{$binNum});
		
        if ( exists $unique{$binNum} ) {
            $unique{$binNum}->count( $totalCount{$binNum} );		
            next;
        }
		
        my $bin = new_bin;
        $bin->number( $_->{HBIN_NUM} );
        $bin->name( $_->{HBIN_NAM} );
        $bin->count( $_->{HBIN_CNT} + 0 );
        if ( exists( $_->{HBIN_PF} ) and trim( $_->{HBIN_PF} ne '' ) ) {
            $bin->PF( $_->{HBIN_PF} );
        }
        else {		
            $bin->PF('F');
			
            if ( $bin->{number} == 1 ) {
                $bin->PF('P');
				$pass = 1;
            }
        }
        $unique{$binNum} = $bin;
    }
	
	if($good_count ne "")
	{
		
		unless($pass){
		
			if(defined $unique{0}){
				dpExit(3, "HBR deosn't have pass bin and has '0' for fail " );
			}
			my $bin = new_bin;
			$bin->number( 0 );
			$bin->name( "PASS" );
			$bin->count( $good_count);
			$bin->PF('P');
			$unique{0} = $bin;
		}
	}
	
    foreach my $binNum ( sort { $a <=> $b } keys %unique ) {
        push @bins, $unique{$binNum};
    }
    return \@bins;
}

sub epdr2bins {
    my $self = shift;
    my $epdr = shift;
    my @bins;
    foreach (@$epdr) {
        my $bin = new_bin;
        $bin->{number} = $_->{SBIN_NUM};
        $bin->{name}   = $_->{SBIN_NAM};
        push @bins, $bin;
    }
    return \@bins;
}

sub epdr2sbins {
    my $self = shift;
    my $epdr = shift;
    my @bins;
    foreach (@$epdr) {
        my $bin = new_bin;
        $bin->{number} = $_->{SBIN_NUM};
        $bin->{name}   = $_->{SBIN_NAM};
        if ($_->{OPT_FLG} =~ /00100000/ ) {
                $bin->PF('P');
        }
        else {
                $bin->PF('F');
        }
        push @bins, $bin;
    }
    return \@bins;
}

sub epdr2hbins {
    my $self = shift;
    my $epdr = shift;
    my @bins;
    foreach (@$epdr) {
        my $bin = new_bin;
        $bin->{number} = $_->{HBIN_NUM};
        $bin->{name}   = $_->{HBIN_NAM};
        push @bins, $bin;
    }
    return \@bins;
}

sub epdr2hbinsV2 {
    my $self = shift;
    my $epdr = shift;
    my @bins;
    foreach (@$epdr) {
        my $bin = new_bin;
        $bin->{number} = $_->{HBIN_NUM};
        $bin->{name}   = $_->{HBIN_NAM};
        if ($_->{OPT_FLG} =~ /00100000/ ) {
                $bin->PF('P');
        }
        else {
                $bin->PF('F');
        }
        push @bins, $bin;
    }
    return \@bins;
}

sub updateBinPF {
    my $self    = shift;
    my $bins    = shift;
    my $results = shift;
    my @newBins ;
    my $binHash = $self->res2binHash($results);
        foreach my $bin (@$bins) {
            if (exists $binHash->{$bin->number}){
              my $bin2 = $binHash->{ $bin->number };
              $bin->PF( $bin2->PF );
              $bin->count( $bin2->count );
              if ( defined $bin2->name and $bin2->name ne '' )
              {
                $bin->name( $bin2->name );
              }
           }
        }
        foreach my $binNumber (sort {$a <=> $b } keys %{$binHash}){
          push @newBins , $binHash->{$binNumber};
        }
    return \@newBins ;
}

sub updatehBinPF {
    my $self    = shift;
    my $bins    = shift;
    my $results = shift;
    my @newBins ;
    my $binHash = $self->res2hbinHash($results);
        foreach my $bin (@$bins) {
            if (exists $binHash->{$bin->number}){
              my $bin2 = $binHash->{ $bin->number };
              $bin->PF( $bin2->PF );
              $bin->count( $bin2->count );
              if ( defined $bin2->name and $bin2->name ne '' )
              {
                $bin->name( $bin2->name );
              }
           }
        }
        foreach my $binNumber (sort {$a <=> $b } keys %{$binHash}){
          push @newBins , $binHash->{$binNumber};		  
        }
    return \@newBins ;
}

sub res2bin {
  my $self    = shift;
  my $results = shift;
  my @bins;
  my %uniqueBin;
  foreach my $res (@$results) {
      my $prr = {};
      if ( defined $res->PRR ) {
          $prr = $res->PRR;
      }
      elsif ( defined $res->EPRR ) {
          $prr = $res->EPRR;
      }
      unless ( defined $prr ) {
          dpExit( 1, "Stdf: Neither PRR and EPRR in the  wafer" );
      }
      my $binNumber = $prr->{HARD_BIN};
      my $binName   = $prr->{HBIN_NAM};
      my $binPF     = 'F';
      if ( defined $prr->{PART_FLG}
          and ( split( //, $prr->{PART_FLG} ) )[4] eq 0 )
      {
          $binPF = 'P';
      }

      if ( exists $uniqueBin{$binNumber} ) {
          $uniqueBin{$binNumber}
              ->count( $uniqueBin{$binNumber}->count + 1 );
      }
      else {
          my $bin = new_bin;
          $bin->number($binNumber);
          $bin->name($binName);
          $bin->PF($binPF);
          $bin->count(1);
          $uniqueBin{$binNumber} = $bin;
      }
  }
  return \%uniqueBin;
}

sub res2binHash {
    my $self    = shift;
    my $results = shift;
    my @bins;
    my %uniqueBin;
    foreach my $res (@$results) {
        my $prr = {};
        if ( defined $res->PRR ) {
            $prr = $res->PRR;
        }
        elsif ( defined $res->EPRR ) {
            $prr = $res->EPRR;
        }
        unless ( defined $prr ) {
            dpExit( 1, "Stdf: Neither PRR and EPRR in the  wafer" );
        }
        my $binNumber = $prr->{SOFT_BIN};
        my $binName   = $prr->{SBIN_NAM};
        my $binPF     = 'F';
        if ( defined $prr->{PART_FLG}
            and ( split( //, $prr->{PART_FLG} ) )[4] eq 0 )
        {
            $binPF = 'P';
        }
        if ($binNumber == 10){
        DEBUG ("bin=$binNumber name=$binName, PART_FLG=".$prr->{PART_FLG}.", binPF=".$binPF);
}
        if ( exists $uniqueBin{$binNumber} ) {
            $uniqueBin{$binNumber}
                ->count( $uniqueBin{$binNumber}->count + 1 );
        }
        else {
            my $bin = new_bin;
            $bin->number($binNumber);
            $bin->name($binName);
            $bin->PF($binPF);
            $bin->count(1);
            $uniqueBin{$binNumber} = $bin;
        }
    }
    return \%uniqueBin;
}

sub res2hbinHash {
    my $self    = shift;
    my $results = shift;
    my @bins;
    my %uniqueBin;
    foreach my $res (@$results) {
        my $prr = {};
        if ( defined $res->PRR ) {
            $prr = $res->PRR;
        }
        elsif ( defined $res->EPRR ) {
            $prr = $res->EPRR;
        }
        unless ( defined $prr ) {
            dpExit( 1, "Stdf: Neither PRR and EPRR in the  wafer" );
        }
        my $binNumber = $prr->{HARD_BIN};
        my $binName   = $prr->{HBIN_NAM};
        my $binPF     = 'F';
        if ( defined $prr->{PART_FLG}
            and ( split( //, $prr->{PART_FLG} ) )[4] eq 0 )
        {
            $binPF = 'P';
        }
        if ($binNumber == 10){
        DEBUG ("bin=$binNumber name=$binName, PART_FLG=".$prr->{PART_FLG}.", binPF=".$binPF);
}
        if ( exists $uniqueBin{$binNumber} ) {
            $uniqueBin{$binNumber}
                ->count( $uniqueBin{$binNumber}->count + 1 );
        }
        else {
            my $bin = new_bin;
            $bin->number($binNumber);
            $bin->name($binName);
            $bin->PF($binPF);
            $bin->count(1);
            $uniqueBin{$binNumber} = $bin;
        }
    }
    return \%uniqueBin;
}

sub wmr2dies {
	my $self = shift;
	my $results = shift;
	my $die_x = shift;
	my $die_y = shift;
	my @dies;
	
	
	foreach my $wmr (@$results){		
	
		my $seq = 0;
		for(my $x=0; $x<$die_x; $x++){
		
			for (my $y=0; $y<$die_y; $y++){
			
				my $die_bin = "DIE_BIN[".$seq."]";		
			
				my $die = new_die;

				$die->{y} = $x * -1;
				$die->{x} = $y;

				$die->{soft_bin} = $wmr->{$die_bin};				
				
				 unless ($wmr->{$die_bin} eq 253){
					push @dies, $die;
				 }
				 
				 $seq++;
			}
		}
			
	}
	
	return \@dies;

}
sub res2dies {
    my $self    = shift;
    my $results = shift;
    my $tests   = shift;
    my @dies;
    foreach my $res (@$results) {
        my $die = new_die;
        my $prr;
        if ( defined $res->EPRR ) {
            $prr = $res->EPRR;
        }
        else {
            $prr = $res->PRR;
        }
        $die->{x}        = $prr->{X_COORD};
        $die->{y}        = $prr->{Y_COORD};
        $die->{partid}   = $prr->{PART_ID};
        $die->{site}     = $prr->{SITE_NUM};
        $die->{hard_bin} = $prr->{HARD_BIN};
        $die->{soft_bin} = $prr->{SOFT_BIN};
        my %testCnt;
        my %hash;

        foreach my $ptr ( @{ $res->PTR } ) {
		
			if($ptr->{TEST_FLG} =~ /\d{1}00\d{1}0\d{3}/){
				$hash{ $ptr->{TEST_NUM} } = $ptr->{RESULT};
			}
			else{
				$hash{ $ptr->{TEST_NUM} } = "N/A";
			}
        }
        foreach my $mpr ( @{ $res->MPR } ) {
            my $num = $mpr->{TEST_NUM};
			my $test_flg = $mpr->{TEST_FLG};
            my @resultName = sort grep {/RTN_RSLT/} keys %$mpr;
            $testCnt{$num} += 0;
            foreach my $name (@resultName) {
                my $testNum = "$num." . $testCnt{$num};
				if($test_flg =~ /\d{1}00\d{1}0\d{3}/){
					$hash{$testNum} = $mpr->{$name};
				}else{
					$hash{$testNum} = "N/A";
				}
                $testCnt{$num} += 1;
            }
        }
        foreach my $test (@$tests) {
            if ( exists $hash{ $test->number } ) {
			
				### this is affected to Mostrak only
				if($test->desc eq "reverse polarity value for Mostrak" && $hash{ $test->number } <0){
					$hash{ $test->number } *= -1;
				}
				
                $die->add( 'result', $hash{ $test->number } );
            }
            else {
                $die->add( 'result', 'N/A' );
            }
        }
        push @dies, $die;
    }
    return \@dies;
}

sub res2dies_v2 {  #get xy coord from PIR
    my $self    = shift;
    my $results = shift;
    my $tests   = shift;
    my @dies;
    foreach my $res (@$results) {
        my $die = new_die;
        my $prr;
        my $pir = $res->PIR;
        if ( defined $res->EPRR ) {
            $prr = $res->EPRR;
        }
        else {
            $prr = $res->PRR;
        }
        $die->{x}        = $pir->{X_COORD};
        $die->{y}        = $pir->{Y_COORD};
        $die->{partid}   = $prr->{PART_ID};
        $die->{site}     = $prr->{SITE_NUM};
        $die->{hard_bin} = $prr->{HARD_BIN};
        $die->{soft_bin} = $prr->{SOFT_BIN};
        my %testCnt;
        my %hash;

        foreach my $ptr ( @{ $res->PTR } ) {

                        if($ptr->{TEST_FLG} =~ /\d{1}00\d{1}0\d{3}/){
                                $hash{ $ptr->{TEST_NUM} } = $ptr->{RESULT};
                        }
                        else{
                                $hash{ $ptr->{TEST_NUM} } = "N/A";
                        }
        }
        foreach my $mpr ( @{ $res->MPR } ) {
            my $num = $mpr->{TEST_NUM};
                        my $test_flg = $mpr->{TEST_FLG};
            my @resultName = sort grep {/RTN_RSLT/} keys %$mpr;
            $testCnt{$num} += 0;
            foreach my $name (@resultName) {
                my $testNum = "$num." . $testCnt{$num};
                                if($test_flg =~ /\d{1}00\d{1}0\d{3}/){
                                        $hash{$testNum} = $mpr->{$name};
                                }else{
                                        $hash{$testNum} = "N/A";
                                }
                $testCnt{$num} += 1;
            }
        }
	foreach my $test (@$tests) {
            if ( exists $hash{ $test->number } ) {

                                ### this is affected to Mostrak only
                                if($test->desc eq "reverse polarity value for Mostrak" && $hash{ $test->number } <0){
                                        $hash{ $test->number } *= -1;
                                }

                $die->add( 'result', $hash{ $test->number } );
            }
            else {
                $die->add( 'result', 'N/A' );
            }
        }
        push @dies, $die;
    }
    return \@dies;
}	


sub res2dies_fet_sort {
    my $self    = shift;
    my $results = shift;
    my $tests   = shift;
    my @dies;
    foreach my $res (@$results) {
        my $die = new_die;
        my $prr;
        if ( defined $res->EPRR ) {
            $prr = $res->EPRR;
        }
        else {
            $prr = $res->PRR;
        }
        $die->{x}        = $prr->{X_COORD};
        $die->{y}        = $prr->{Y_COORD};
        $die->{partid}   = $prr->{PART_ID};
        $die->{site}     = $prr->{SITE_NUM};
        $die->{hard_bin} = $prr->{HARD_BIN};
        $die->{soft_bin} = $prr->{SOFT_BIN};
        my %testCnt;
        my %hash;

        foreach my $ptr ( @{ $res->PTR } ) {
		
			#if($ptr->{TEST_FLG} =~ /\d{1}00\d{1}0\d{3}/){
				$hash{ $ptr->{TEST_NUM} } = $ptr->{RESULT};
			#}
			#else{
			#	$hash{ $ptr->{TEST_NUM} } = "N/A";
			#}
        }
        foreach my $mpr ( @{ $res->MPR } ) {
            my $num = $mpr->{TEST_NUM};
			my $test_flg = $mpr->{TEST_FLG};
            my @resultName = sort grep {/RTN_RSLT/} keys %$mpr;
            $testCnt{$num} += 0;
            foreach my $name (@resultName) {
                my $testNum = "$num." . $testCnt{$num};
				#if($test_flg =~ /\d{1}00\d{1}0\d{3}/){
					$hash{$testNum} = $mpr->{$name};
				#}else{
				#	$hash{$testNum} = "N/A";
				#}
                $testCnt{$num} += 1;
            }
        }
        foreach my $test (@$tests) {
            if ( exists $hash{ $test->number } ) {
			
				### this is affected to Mostrak only
				if($test->desc eq "reverse polarity value for Mostrak" && $hash{ $test->number } <0){
					$hash{ $test->number } *= -1;
				}
				
                $die->add( 'result', $hash{ $test->number } );
            }
            else {
                $die->add( 'result', 'N/A' );
            }
        }
        push @dies, $die;
    }
    return \@dies;
}

sub res2mprTests {
    my $self    = shift;
    my $results = shift;
    my @tests;
    my %maxNum;
    my %testName;
    my %testUnits;
    my %testLimits;

    foreach my $res (@$results) {
        my %mprTestNum = ();
        foreach my $mpr ( @{ $res->MPR } ) {
            my $num = $mpr->{TEST_NUM};
			
            $mprTestNum{$num} += $mpr->{RSLT_CNT};
            if ( $mprTestNum{$num} <= $maxNum{$num} ) {
                next;
            }
            $maxNum{$num}                  = $mprTestNum{$num};
            $testName{ $mpr->{TEST_NUM} }  = $mpr->{TEST_TXT};
			
            $testUnits{ $mpr->{TEST_NUM} } = $mpr->{UNITS};
            my @opt = reverse split( //, $mpr->{OPT_FLAG} );
            my ( $lsl, $hsl, $lol, $hol ) = ( 'N/A', 'N/A', 'N/A', 'N/A' );
            unless ( $opt[4] or $opt[6] ) {
                $lsl = $mpr->{LO_LIMIT};
            }
            unless ( $opt[5] or $opt[7] ) {
                $hsl = $mpr->{HI_LIMIT};
            }
            unless ( $opt[2] ) {
                $lol = $mpr->{LO_SPEC};
            }
            unless ( $opt[3] ) {
                $hol = $mpr->{HI_SPEC};
            }
            $testLimits{ $mpr->{TEST_NUM} }
                = [ ( $lsl, $hsl, $lol, $hol ) ];
        }
    }
    foreach my $num ( keys %maxNum ) {
        for ( my $i = 0; $i < $maxNum{$num}; $i++ ) {
            my $test = new_test;
            $test->number("$num.$i");
            #$test->name( $testName{$num} . ".$i" );
			
			$test->name( $testName{$num} );
			
			
			#if($testName{$num} =~ /(\S+)\|(\S+)/)
			if($test->{name} =~ /(.+)\|(.+)/)
			{

				$test->{name} = $1;
				$test->{desc} = $2;
				
				if($2 =~ /^\_(\S+)/)
				{
					
					$test->{desc} = $1;
				}
			#}elsif($testName{$num} =~ /(\S+)\|$/)
			}elsif($test->{name} =~ /(.+)\|$/)
			{
				
				$test->{name} = $1;
			}	
			
            $test->units( $testUnits{$num} );
            my $limit = $testLimits{$num};
            $test->LSL( $limit->[0] );
            $test->HSL( $limit->[1] );
            $test->LOL( $limit->[2] );
            $test->HOL( $limit->[3] );
            push @tests, $test;
        }
    }
    my @sorted = sort { $a->number <=> $b->number } @tests;
    return \@sorted;
}

sub res2tests {
    	my $self    = shift;
    	my $results = shift;
    	my @tests;
    	my %unique;
    	foreach my $res (@$results) {
        	foreach my $ptr ( @{ $res->PTR } ) {			
            		next if ( exists $unique{ $ptr->{TEST_NUM} }  or $ptr->{TEST_NAM} eq "Not tested");
            		$unique{ $ptr->{TEST_NUM} } = 1;
            		my $test = new_test;
            		$test->{number} = $ptr->{TEST_NUM};
            		if ( exists $ptr->{TEST_NAM} ) {
                		$test->{name} = $ptr->{TEST_NAM};
            		}
            		else {
				if($ptr->{TEST_TXT} ne "Not tested" and $ptr->{TEST_TXT} ne ""){
					$test->{name} = $ptr->{TEST_TXT};
				}				
            		}
			
			### special case 
			### TEST_TXT=IDDQ_STRESS|_vec_515			
			#if($test->{name} =~ /(\S+)\|(\S+)/){
			if($test->{name} =~ /(.+)\|(.+)/){
				$test->{name} = $1;
				$test->{desc} = $2;
				
				if($2 =~ /^\_(\S+)/)
				{					
					$test->{desc} = $1;
				}
			}
			elsif($test->{name} =~ /(\S+)\|$/){
				$test->{name} = $1;
			}				

            		$test->{units} = $ptr->{UNITS};
            		my @opt = reverse split( //, $ptr->{OPT_FLAG} );
            		unless ( $opt[4] or $opt[6] ) {
                		$test->{LSL} = $ptr->{LO_LIMIT};
            		}
            		unless ( $opt[5] or $opt[7] ) {
                		$test->{HSL} = $ptr->{HI_LIMIT};
            		}
            		unless ( $opt[2] ) {
                		$test->{LOL} = $ptr->{LO_SPEC};
            		}
            		unless ( $opt[3] ) {
                		$test->{HOL} = $ptr->{HI_SPEC};
            		}
            		push @tests, $test;
        	}
    	}

    	my @tests_ptr = sort { $a->number <=> $b->number } @tests;
    	my $tests_mpr = $self->res2mprTests($results);
    	return [ ( @tests_ptr, @$tests_mpr ) ];
}

# this version captures test name up to the first space in the TEST_TXT field=ATEC requirement
sub res2mprTestsV2 {
    	my $self    = shift;
    	my $results = shift;
    	my @tests;
    	my %maxNum;
    	my %testName;
    	my %testUnits;
    	my %testLimits;

    	foreach my $res (@$results) {
        	my %mprTestNum = ();
        	foreach my $mpr ( @{ $res->MPR } ) {
            		my $num = $mpr->{TEST_NUM};

            		$mprTestNum{$num} += $mpr->{RSLT_CNT};
            		if ( $mprTestNum{$num} <= $maxNum{$num} ) {
                		next;
            		}
            		$maxNum{$num} = $mprTestNum{$num};
            		$testName{ $mpr->{TEST_NUM} } = $mpr->{TEST_TXT};

            		$testUnits{ $mpr->{TEST_NUM} } = $mpr->{UNITS};
            		my @opt = reverse split( //, $mpr->{OPT_FLAG} );
            		my ( $lsl, $hsl, $lol, $hol ) = ( 'N/A', 'N/A', 'N/A', 'N/A' );
            		unless ( $opt[4] or $opt[6] ) {
                		$lsl = $mpr->{LO_LIMIT};
            		}
            		unless ( $opt[5] or $opt[7] ) {
                		$hsl = $mpr->{HI_LIMIT};
            		}
            		unless ( $opt[2] ) {
                		$lol = $mpr->{LO_SPEC};
            		}
            		unless ( $opt[3] ) {
                		$hol = $mpr->{HI_SPEC};
            		}
            		$testLimits{ $mpr->{TEST_NUM} }
                		= [ ( $lsl, $hsl, $lol, $hol ) ];
        	}
    	}
    	foreach my $num ( keys %maxNum ) {
        	for ( my $i = 0; $i < $maxNum{$num}; $i++ ) {
            		my $test = new_test;
            		$test->number("$num.$i");
            		#$test->name( $testName{$num} . ".$i" );
			$test->name( $testName{$num} );

                        if($testName{$num} =~ /(\S+)\|(\S+)/)
                        {
                                $test->{name} = $1;
                                $test->{desc} = $2;

                                if($2 =~ /^\_(\S+)/)
                                {

                                        $test->{desc} = $1;
                                }
                        }
			elsif($testName{$num} =~ /(\S+)\|$/)
                        {
                                $test->{name} = $1;
                        }
			elsif($test->{name} =~ /(\S+)(\s.+)/)
                        {
                                $test->{name} = trim($1);
                                $test->{desc} = trim($2);
                        }

            		$test->units( $testUnits{$num} );
            		my $limit = $testLimits{$num};
            		$test->LSL( $limit->[0] );
            		$test->HSL( $limit->[1] );
            		$test->LOL( $limit->[2] );
            		$test->HOL( $limit->[3] );
            		push @tests, $test;
        	}
    	}
    	my @sorted = sort { $a->number <=> $b->number } @tests;
    	return \@sorted;
}

# this version captures test name up to the first space in the TEST_TXT field=ATEC requirement
sub res2testsV2 { 
	my $self    = shift;
    	my $results = shift;
    	my @tests;
    	my %unique;
    	foreach my $res (@$results) {
        	foreach my $ptr ( @{ $res->PTR } ) {
            		next if ( exists $unique{ $ptr->{TEST_NUM} }  or $ptr->{TEST_NAM} eq "Not tested");
            		$unique{ $ptr->{TEST_NUM} } = 1;
            		my $test = new_test;
            		$test->{number} = $ptr->{TEST_NUM};
            		if ( exists $ptr->{TEST_NAM} ) {
				$test->{name} = $ptr->{TEST_NAM};
            		}
            		else {
                		if($ptr->{TEST_TXT} ne "Not tested" and $ptr->{TEST_TXT} ne ""){
                        		$test->{name} = $ptr->{TEST_TXT};
                		}
            		}

            		### special case
            		### TEST_TXT=IDDQ_STRESS|_vec_515
            		if($test->{name} =~ /(\S+)\|(\S+)/)
            		{
				$test->{name} = $1;
                		$test->{desc} = $2;

                		if($2 =~ /^\_(\S+)/)
                		{
                			$test->{desc} = $1;
                		}
             		}
	     		elsif($test->{name} =~ /(\S+)\|$/)
             		{
                 		$test->{name} = $1;
             		}
			elsif($test->{name} =~ /(\S+)(\s.+)/)
			{
				$test->{name} = trim($1);
				$test->{desc} = trim($2);
			}

            		$test->{units} = $ptr->{UNITS};
            		my @opt = reverse split( //, $ptr->{OPT_FLAG} );
            		unless ( $opt[4] or $opt[6] ) {
                		$test->{LSL} = $ptr->{LO_LIMIT};
            		}
            		unless ( $opt[5] or $opt[7] ) {
                		$test->{HSL} = $ptr->{HI_LIMIT};
            		}
            		unless ( $opt[2] ) {
                		$test->{LOL} = $ptr->{LO_SPEC};
            		}
            		unless ( $opt[3] ) {
                		$test->{HOL} = $ptr->{HI_SPEC};
            		}
            		push @tests, $test;
        	}
	}

    	my @tests_ptr = sort { $a->number <=> $b->number } @tests;
    	my $tests_mpr = $self->res2mprTestsV2($results);
    	return [ ( @tests_ptr, @$tests_mpr ) ];
}	

sub res2tests_tsr {
    my $self    = shift;
    my $results = shift;
    my @tests;
    my %unique;
	
   foreach my $tsr ( @$results ) {	
            next if ( exists $unique{ $tsr->{TEST_NUM} }  or $tsr->{TEST_NAM} eq "Not tested");
            $unique{ $tsr->{TEST_NUM} } = 1;
            my $test = new_test;
            $test->{number} = $tsr->{TEST_NUM};
            if ( exists $tsr->{TEST_NAM} ) {
                $test->{name} = $tsr->{TEST_NAM};
            }
            else {
		if($tsr->{TEST_TXT} ne "Not tested" and $tsr->{TEST_TXT} ne ""){
			$test->{name} = $tsr->{TEST_TXT};
		}				
            }
	
	    $test->{min} = $tsr->{TEST_MIN};
	    $test->{max} = $tsr->{TEST_MAX};
	    $test->{avg} = $tsr->{TST_MEAN};
            $test->{std} = $tsr->{TST_SDEV};
	    $test->{sum} = $tsr->{TST_SUMS};
	    $test->{ss} = $tsr->{TST_SQRS};
			
	    my @opt = reverse split( //, $tsr->{OPT_FLAG} );
            unless ( $opt[4] or $opt[6] ) {
                $test->{LSL} = $tsr->{LO_LIMIT};
            }
            unless ( $opt[5] or $opt[7] ) {
                $test->{HSL} = $tsr->{HI_LIMIT};
            }		
			
            push @tests, $test;			
  }
   
  my @tests_tsr = sort { $a->number <=> $b->number } @tests;
      
  return [ ( @tests_tsr ) ];
}

sub stdf2header {
    my $self = shift;
    my $stdf = shift;
    my $mir;
    my $header = {};
    if ( defined $stdf->EMIR ) {
        $mir                = $stdf->EMIR;
        $header->{PROGRAM}  = $mir->{SPEC_NAM};
      	#$mir->{SPEC_REV}    =~ s/[^A-Za-z0-9\.\-\_\~]//g;
        $header->{REVISION} = trim($mir->{SPEC_REV});
    }
    else {
        $mir                = $stdf->MIR;
        
        $header->{PROGRAM}  = $mir->{JOB_NAM};
        #$mir->{JOB_REV}     =~ s/[^A-Za-z0-9\.\-\_]\~//g;
        $header->{REVISION} = trim($mir->{JOB_REV});
    }
    $header->{VERSION} = $VERSION;
    $header->{LOT}     = uc($mir->{LOT_ID});
    $header->{PRODUCT} = $mir->{PART_TYP};
    my $testCode = $mir->{TEST_COD};

    $header->{OPERATOR} = $mir->{OPER_NAM};
    my $testerType = $mir->{TSTR_TYP};
    my $tester     = $mir->{NODE_NAM};
    my $stat_num   = $mir->{STAT_NUM};
#    $header->{FAB}        = $mir->{FACILITY};
    $header->{EQUIP1_ID}  = trim("$testerType $tester $stat_num");
    $header->{EQUIP3_ID}  = trim( $mir->{PRB_CARD} );
    $header->{EQUIP5_ID}  = trim( $mir->{HAND_ID} );
    $header->{START_TIME} = $mir->{START_T};
    $header->{END_TIME}   = $stdf->MRR->{FINISH_T};
    if ( $header->{END_TIME} == 0 ) {
	$header->{END_TIME}   = $mir->{START_T};
    }
    return $header;
}


sub res2dies_sum {
    my $self    = shift;
    my $results = shift;
    my $tests   = shift;
    my $sum_level = shift;
    my @dies;	
    my $die = new_die;
    my %hash;
    my %hash_cnt;
    my %hash_min;
    my %hash_max;
    my %hash_mean;
    my %hash_sdev;
    my %hash_sums;
    my %hash_sqrs;

    foreach my $res (@$results) {
        my %testCnt;
	#$hash{ $res->{TEST_NUM} } = $res->{TEST_MIN}."/".$res->{TEST_MAX}."/".$res->{TST_MEAN}."/".$res->{TST_SDEV}."/".$res->{TST_SUMS}."/".$res->{TST_SQRS};
	$hash_cnt{ $res->{TEST_NUM} } = $res->{EXEC_CNT};
	$hash_min{ $res->{TEST_NUM} } = $res->{TEST_MIN};
	$hash_max{ $res->{TEST_NUM} } = $res->{TEST_MAX};
	$hash_mean{ $res->{TEST_NUM} } = $res->{TST_MEAN};
	$hash_sdev{ $res->{TEST_NUM} } = $res->{TST_SDEV};
	$hash_sums{ $res->{TEST_NUM} } = $res->{TST_SUMS};
	$hash_sqrs{ $res->{TEST_NUM} } = $res->{TST_SQRS};		
    }		
      
    foreach my $test (@$tests) {
	if($sum_level ne ""){
		$die->add( 'level', $sum_level);
		$sum_level = "";
	}
			
        if ( exists $hash_min{ $test->number } ) {
                #$die->add( 'result', $hash{ $test->number } );
		$die->add( 'cnt', $hash_cnt{ $test->number } );
                $die->add( 'min', $hash_min{ $test->number } );
                $die->add( 'max', $hash_max{ $test->number } );
		$die->add( 'mean', $hash_mean{ $test->number } );
                $die->add( 'sdev', $hash_sdev{ $test->number } );
                $die->add( 'sums', $hash_sums{ $test->number } );
                $die->add( 'sqrs', $hash_sqrs{ $test->number } );
		
        }
        else {
                #$die->add( 'result', 'N/A' );
		$die->add( 'cnt', repNA($hash_cnt{ $test->number }) );
		$die->add( 'min', repNA($hash_min{ $test->number }) );
                $die->add( 'max', repNA($hash_max{ $test->number }) );
                $die->add( 'mean', repNA($hash_mean{ $test->number }) );
                $die->add( 'sdev', repNA($hash_sdev{ $test->number }) );
                $die->add( 'sums', repNA($hash_sums{ $test->number }) );
                $die->add( 'sqrs', repNA($hash_sqrs{ $test->number }) );

        }
   }
   push @dies, $die;
    
   return \@dies;
}


1;

