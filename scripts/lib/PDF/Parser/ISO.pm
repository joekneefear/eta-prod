# 
# 2017-Feb-02 GMiole - Original.
# 2020-Aug-05 Gmllego - change start and end date DD-MM-YYYY to MM-DD-YYYY. Added support for 2DID as the added parameters. 
# 
package PDF::Parser::ISO;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use DateTime;
use Date::Parse;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}

__PACKAGE__->mk_accessors(array);

sub readFile {
    my $self               = shift;
    my $infile             = shift;
    my $retest_flag        = "N";
    my $nothing            = undef;	
    my @parameter          = ();
    my @lolim              = ();
    my @hilim              = ();
    my @unit               = ();
    my $tp     	           = "";
    my $lotno  	           = "";
    my $line               = undef;
    my @values             = ();
    my $tp_rev	           = "";
    my $entity_type        = "";
    my $entity_no          = "";
    my $pf		   = "";
    my $fail_cnt	   = "";
    my $pass_cnt 	   = "";
    my $stp_cnt		   = "";
    my $othr_cnt	   = "";
    my $with_test_readings = 0;	# 0 if none. 1 if available.
    my %binhash            =();
    my %binnamehash        =();
	my $die_cnt = 0;
	my $touchdownNum = 0;
	my $currentPartTestTime;
    my $firstPartTestTimeSec;
    my $prevPartTestTime;
    my $testTime;
    my $elapsedTime;
    my $prevPartTestTimeSec;
    my $currentPartTestTimeSec;
    my $firstPartTestTime;
	my %data= {};
    my $header             = new_headerLong;
    my $wmap               = new_wmap;
    my $model  = new_model(
        {   header => $header,
            wmap   => $wmap,
            misc   => {},
            dataSource => 'ISO'
        }
    );
    my $wafer = new_wafer;
    $model->add( 'wafers', $wafer );
   
    open( INFILE, $infile );
    while ($line=<INFILE>) {
		$line =~ s/\cM\n/\n/g;			
		chomp($line);
		$line  =~ s/^\s+|\s$//g;
		
        ################
        # TEST READINGS
        ################
	if (($line =~ /^\d{1,}\,\s+?\d{1,}\,\s+?\d{2}\//) || ($line =~ /^\d{1,}\,\d{1,}\,\d{2}\//)) 
        {
			$die_cnt++;
			my @readings = ();
			my @readings = split /\,/,$line;
			my $readingsLength = scalar(@readings);
			my $id2dResult;
			#INFO("ReadingLenght=>$readingsLength");
			if($readingsLength > 7) {
              $id2dResult = splice(@readings, 3, 1);
			  #INFO("=========2D_ID=$id2dResult");
			  #splice(@readings, 6, 0, $id2dResult);
			  #INFO(">>>>@readings<<<<"); 
			}
			
			###print "@readings\n";
			my $no_id      = shift(@readings);
			my $st_no      = shift(@readings);
			my $date_time  = shift(@readings);
			$date_time = formatDate($date_time);
			my $test_time  = shift(@readings);
			#my $cont_check = shift(@readings);
			
			my $result     = pop(@readings);
			# my $cont = shift(@readings);
			# $data{'1'} = $cont;
			# my $data = shift(@readings);
			# $data{'2'} = $data;
			my $time = str2time($date_time);
			#INFO("DATE=$date_time||EPOCH=$time");
			if ( $prevPartTestTimeSec eq "" ) {
                $prevPartTestTimeSec = $time;#convertDateTimeToSeconds( $item[2] );
            }
            $currentPartTestTimeSec = $time; #convertDateTimeToSeconds( $item[2] );

            #my($testTime, $elapsedTime) = "";
            if ( $die_cnt == 1 ) {
                $touchdownNum         = 1;
                $firstPartTestTimeSec = $time;#convertDateTimeToSeconds( $item[2] );
                $prevPartTestTime = $currentPartTestTimeSec - $prevPartTestTimeSec;

            }

            if ( $currentPartTestTimeSec == $prevPartTestTimeSec ) {
                $testTime = $prevPartTestTime;
            } else {
                $testTime = $currentPartTestTimeSec - $prevPartTestTimeSec;
                $prevPartTestTime = $testTime;
                $touchdownNum++;
            }

            $elapsedTime = $currentPartTestTimeSec - $firstPartTestTimeSec;

            # $data{'0.1'} = $testTime;
            # $data{'0.2'} = $elapsedTime;

			

            $prevPartTestTimeSec = $time; #convertDateTimeToSeconds( $item[2] );
			#INFO("===========>>>>@readings<<<<"); 
			unshift(@readings, $testTime, $elapsedTime);
			
			if ($result =~/PASS/i){	
			    $pf = 1;
			    $pass_cnt++;
			} elsif ($result =~/FAIL/i){
			    $pf = 2;
			    $fail_cnt++;
			} elsif ($result =~/STOP/i) {
			    $pf = 3;
			    $stp_cnt++;
			} else {
			    $pf = 4;
			    $othr_cnt++;
			}

			### SKIP UNIT DATA IF NO PASS/FAIL FLAG ###
			next if $#readings == -1;
			
			### CONVERT TEST READINGS TO BASE UNIT ###
			my $die = new_die;
			$die->site( $st_no );
			$die->partid($no_id);
			$die->ecid($id2dResult);
			$die->soft_bin( $pf );
			$die->hard_bin( $pf );
			# foreach my $test ( @{ $wafer->tests } ) {
            #     $die->add( 'result', repNA( $data{ $test->number } ) );
            # }
			for (my $i=0; $i<=$#parameter; $i++) {
				#INFO("====RESULT=$readings[$i]");
				if($i <= $#readings ){
					#INFO("====RESULT=$readings[$i]");
					$die->add('result',$readings[$i]);
				}else{
					$die->add('result',"N/A");
				}
            }
			$with_test_readings = 1;
            $wafer->add( 'dies', $die );
	}
	#################
        # PARAMETER NAME 
        #################
        elsif ($line =~ /^No\,ST\,\s+Date/i)
        {
            @parameter = split /\,/, $line;
			my $parametersLength = scalar(@parameter);
			#INFO("parametersLength=>$parametersLength");
			my $id2dParamName;
			if($parametersLength > 7) {
              $id2dParamName = splice(@parameter, 3, 1);
			  #INFO("@parameter)=====2D_ID_Param=$id2dParamName");
			  #splice(@parameter, 6, 0, $id2dParamName);
			  #INFO(">>>>=======@parameter=====<<<<");
			}

            shift(@parameter);                       #<-- REMOVES THE "No"         WORD
            shift(@parameter);                       #<-- REMOVES THE "ST"         WORD
            shift(@parameter);                       #<-- REMOVES THE "Date Time"  WORD
            shift(@parameter);                       #<-- REMOVES THE "Test Time"  WORD
            #shift(@parameter);                       #<-- REMOVES THE "CONT CHECK" WORD
            pop(@parameter);                       #<-- REMOVES THE "RESULT    " WORD
			unshift(@parameter,"test_time", "elapsed_time");

			#INFO("===========>>>>Param=".scalar(@parameter));
        }
	##############
        # LOWER LIMIT
        ##############
        elsif ($line =~ /LOW\s+LIMIT/i)
        {
            @lolim = split /\,/, $line;
			my $lolimLength = scalar(@lolim);
			#INFO("lolimLength=>$lolimLength");
			my $lolim;
			if($lolimLength > 7) {
              $lolim = splice(@lolim, 3, 1);
			  #INFO("==============lolim=$lolim");
			  #splice(@lolim, 6, 0, $lolim);
			  #INFO(">>>>@lolim<<<<");
			}
            shift(@lolim);                           #<-- REMOVES THE " "         WORD
            shift(@lolim);                           #<-- REMOVES THE " "         WORD
            shift(@lolim);                           #<-- REMOVES THE "LOW LIMIT" WORD
            shift(@lolim);                           #<-- REMOVES THE " "         WORD
            #shift(@lolim); 
			if($lolim[0] =~ /0x.*/i) {
				$lolim[0] = hex($lolim[0]);
			}                          #<-- REMOVES THE "0x0000000" WORD
			# my $contLolim = shift(@lolim);
			# if($contLolim =~ /0x.*/i) {
			# 	$contLolim = "N/A";
			# }
			# $data{'contLolim'} = $contLolim;
			# my $dataLolim = shift(@lolim);
			# $data{'dataLolim'} = $dataLolim;
            pop(@lolim);                           #<-- REMOVES THE " "         WORD
			unshift(@lolim,"N/A", "N/A");
			#INFO(">>>>LOLIM scalar(@lolim)");
        }
	##############
        # UPPER LIMIT
        ##############
        elsif ($line =~ /HIGH\s+LIMIT/i)
        {
            @hilim = split /\,/, $line;
			my $hilimLength = scalar(@hilim);
			#INFO("hilimLength=>$hilimLength");
			my $hilim;
			if($hilimLength > 7) {
              $hilim = splice(@hilim, 3, 1);
			  #INFO("===================hilim=$hilim");
			  #splice(@hilim, 6, 0, $hilim);
			  #INFO(">>>>@hilim<<<<");
			}
            shift(@hilim);                           #<-- REMOVES THE " "          WORD
            shift(@hilim);                           #<-- REMOVES THE " "          WORD
            shift(@hilim);                           #<-- REMOVES THE "HIGH LIMIT" WORD
            shift(@hilim);                           #<-- REMOVES THE " "          WORD
            #shift(@hilim);                           #<-- REMOVES THE "0x00000000" WORD
			if($hilim[0] =~ /0x.*/i) {
				$hilim[0] = hex($hilim[0]);
			}
			# my $contHilim = shift(@hilim);
			# if($contHilim =~ /0x.*/i) {
			# 	$contHilim = "N/A";
			# }
			# $data{'contHilim'} = $contHilim;
			# my $dataHilim = shift(@hilim);
			# $data{'dataHilim'} = $dataHilim;
            pop(@hilim);      
			unshift(@hilim,"N/A", "N/A");                     #<-- REMOVES THE " "          WORD
			#INFO(">>>>HILIM scalar(@hilim)");
        }
        #############
	# TEST UNITS
	#############
	elsif ($line =~ /UNIT/i)
	{
	    @unit = split /\,/, $line;
		my $unitLength = scalar(@unit);
		#INFO("unitLength=>$unitLength");
		my $unit;
		if($unitLength > 7) {
           $unit = splice(@unit, 3, 1);
		   #INFO("================UNIT=>>$unit<<");
		   #splice(@unit, 6, 0, $unit);
		  #INFO(">>>>@unit<<<<");
		}
  	    shift(@unit);			     #<-- REMOVES " "    WORD
  	    shift(@unit);			     #<-- REMOVES " "    WORD
  	    shift(@unit);			     #<-- REMOVES "UNIT" WORD
  	    shift(@unit);			     #<-- REMOVES "S"    WORD
  	    #shift(@unit);			     #<-- REMOVES " "    WORD
		# my $contUnit = repNA(shift(@unit));
		# $data{'contUnit'} = $contUnit;
		# my $dataUnit = shift(@unit);
		# $data{'dataUnit'} = $dataUnit;
  	    pop(@unit);			     #<-- REMOVES " "    WORD
		unshift(@unit,"", "");   
		#INFO(">>>>Unit scalar(@unit)");

		# my $test = $wafer->find( 'tests', { number => '0.1' } );
        #     unless ( defined $test ) {
        #         my $test = new_test;
        #         $test->number('0.1');
        #         $test->name('test_time');
        #         $test->units('sec');
        #         $wafer->add( 'tests', $test );
        #     }
        #     $test = $wafer->find( 'tests', { number => '0.2' } );
        #     unless ( defined $test ) {
        #         my $test = new_test;
        #         $test->number('0.2');
        #         $test->name('elapsed_time');
        #         $test->units('sec');
        #         $wafer->add( 'tests', $test );
        #     }

        #     my $test = new_test;
        #     $test->number( $item[1] );
        #     $test->name( repNA( $item[6] ) );
        #     $test->units( repNA( $item[5] ) );
        #     $test->group( repNA( $item[2] ) );
        #     $test->LSL( repNA( $item[4] ) );
        #     $test->HSL( repNA( $item[3] ) );
        #     $wafer->add( 'tests', $test );


			my $testNum = 0;
			for(my $i=0; $i<=$#parameter; $i++)
			{
				$parameter[$i] =~ s/ //g;
				$hilim[$i]     =~ s/ //g;
				$lolim[$i]     =~ s/ //g;
				$unit[$i]      =~ s/\s|\-//g;
				
				my $test = new_test;
				
				if($parameter[$i] eq "test_time" && $i == 0) {
					$test = $wafer->find( 'tests', { number => '0.1' } );
					unless ( defined $test ) {
						my $test = new_test;
						$test->number('0.1');
						$test->name('test_time');
						$test->units('sec');
						$wafer->add( 'tests', $test );
					}
				} elsif($parameter[$i] eq "elapsed_time" && $i == 1) {
					 $test = $wafer->find( 'tests', { number => '0.2' } );
					unless ( defined $test ) {
						my $test = new_test;
						$test->number('0.2');
						$test->name('elapsed_time');
						$test->units('sec');
						$wafer->add( 'tests', $test );
					}

				} elsif($parameter[$i] =~ /CONT.*/i && $i == 2){
					#INFO(">>>>>>>>>>>>PARAM=$parameter[$i]||HILIM=$hilim[$i]||LOLIM=$lolim[$i]||UNIT=$unit[$i]");
					
					$test = $wafer->find( 'tests', { number => '2' } );
					unless ( defined $test ) {
						my $test = new_test;
						$test->number( 2 );
						$test->name( uc(trim($parameter[$i])));
						$test->units($unit[$i]);
						$test->LSL($lolim[$i]);
						$test->HSL($hilim[$i]);
						$wafer->add('tests', $test );
					}


				} elsif($parameter[$i] =~ /DATA.*/i && $i == 3){
					#INFO(">>>>>>>>>>>>PARAM=$parameter[$i]||HILIM=$hilim[$i]||LOLIM=$lolim[$i]||UNIT=$unit[$i]");
					
					$test = $wafer->find( 'tests', { number => '1' } );
					unless ( defined $test ) {
						my $test = new_test;
						$test->number( 1 );
						$test->name( uc(trim($parameter[$i])));
						$test->units($unit[$i]);
						$test->LSL($lolim[$i]);
						$test->HSL($hilim[$i]);
						$wafer->add('tests', $test );
					}


				}		
				
			}
	}
        elsif ( $line =~ /HOST/i ) {
                my ($dummy, $entity) = split(/:/, $line, 2);
                #print"$entity\n";
		$header->EQUIP1_ID($entity);
        }
	###########
	# TESTPLAN
	###########	
        if ( $line =~ /Program/i) {
	     my ($dummy, $test_plan)    = split(/:/, $line, 2);
	     $tp = $test_plan;
             $tp =~ s/[^0-9A-Z\-\_]//g;
             $header->PROGRAM($tp);
        }
	###########
	# Revision 
	###########	
        if ( $line =~ /Version/i) {
	     my ($dummy, $tp_rev)    = split(/\:/, $line, 2);
             $header->REVISION($tp_rev);
        }
	########
	# LOTNO
	########
	elsif ($line =~ /LotNo/i)
	{
	    my ($dummy, $lotid)    = split(/\:/, $line, 2);
	        $lotno       = $lotid;
		$lotno       =~ s/[^a-zA-Z0-9]//g;
	        $lotno       =~ s/AO/A0/ig;
	        $lotno       =~ s/XO/X0/ig;
		$retest_flag = "Y" if $lotno=~/REJ/i || $infile=~/REJ/i; ### CHECK IF RETEST DATA
		$lotno       =~ s/REJ//gi;
		$lotno       = substr($lotno,0,10) if length($lotno) > 10 && $lotno =~ /^A/i;
		$header->LOT(uc($lotno));
                ###print "lotno=$lotno\n";
        }
	###################
        # TEST DATE & TIME
        ###################
        elsif ($line =~ /Test\s+Start/i)
        {
        	my ($dummy, $test_start) = split(/\.\.\s+/, $line, 2);
		    $test_start =~ s/^\s+|\s$//g;
		    $test_start =~ s/\s+/ /g;
			$test_start = formatDate($test_start);
		    $header->START_TIME($test_start);
        }
        elsif ($line =~ /Test\s+End/i)
        {
        	my ($dummy, $test_end) = split (/\.\.\s+/, $line, 2);
		    $test_end =~ s/^\s+|\s$//g;
		    $test_end =~ s/\s+/ /g;
			$test_end = formatDate($test_end);
		    $header->END_TIME($test_end);
        }
	 	
    }

	for(1..4)
	{
	   my $hbin = new_bin;
	   if ($_ ==1) {
               $hbin->number(1);
	       $hbin->name("PASS");
	       $hbin->PF("P");
	       $hbin->count($pass_cnt);
	   } elsif ($_ ==2) {
               $hbin->number(2);
	       $hbin->name("FAIL");
	       $hbin->PF("F");
	       $hbin->count($fail_cnt);
	   } elsif ($_ ==3) {
               $hbin->number(3);
	       $hbin->name("STOP");
	       $hbin->PF("F");
	       $hbin->count($stp_cnt);
	   } else {
               $hbin->number(4);
	       $hbin->name("OTHER");
	       $hbin->PF("F");
	       $hbin->count($othr_cnt);
	   }
	   $wafer->add('hbins',$hbin);
	}

    close(INFILE);
    ###################################
    # TRAP EMPTY LOTID & TESTPLAN NAME
    ###################################
    if ($lotno eq "")
    {
        dpExit(1, "no_lotid in file");
    }
	elsif ($tp eq "")
	{
		dpExit(1, "missing testplan in file");
	}
	### MUST HAVE TEST READINGS ###
	if ($with_test_readings == 0)
	{
		dpExit(1, "no_part_data in file");
	}
    return $model;
}
1;
