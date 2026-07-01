#!/usr/bin/perl
#
# Confidential Property of Fairchild Semiconductor Corperation
# (c) Copyright Fairchild Semiconductor Corperation, 1999
# All rights reserved
#
# MODIFICATION HISTORY:
#
# DATE        WHO             DESCRIPTION
# ___________ ______________  ____________________________________________________________
# 04-06-2002  Ben Rommel Kho  original  
# 06-13-2002  Ben Rommel Kho  modified to set PRN filename as the testplan name if there's
#			      no .TES filename available in PRN header.
# 09-11-2002  Ben Rommel Kho  if both FX test spec limits are empty then apply -/+ FLT_MAX
# 10-07-2002  Ben Rommel Kho  stripped dir_path when using PRN filename as tp name
# 04-23-2003  Ben Rommel Kho  modified to delete invalid prn file
# 01-24-2006  Ben Rommel Kho  Derived testplan name from filename.
# 06-26-2012  Ben Rommel Kho  Adjusted for MFT. Restored "FT_" tp_name prefix
# 08/31/2012  Rodney Cyr      Changed negative exit codes to positive (negative exit codes are not valid in unix).
# 
#
#
# Script Function: Converts FET's PRN testplan to STDF+
#
#


#################
# LOAD LIBRARIES
#################
use Carp                      ; # error messages - does not work within stdf_use.pl
use FindBin                   ;
use English                   ;
use lib "$FindBin::Bin"       ; # set up path for libraries the same as script
use lib $ENV{'STDF_PERL_LIB'} ; # look for libraries in this directory
require "stdf_use.pl"         ; # libraries that are not generated
use Data::Dumper	      ;
use Getopt::Long              ;
use File::Basename	      ;



######################
# LOAD SPECIFICATIONS
######################
{
	package out ;
	if ( !eval(&::generate_all('stdfPL.spec')))
        { confess $@ ; }
        require 'stdfPL.pl' ;
}


############
# VARIABLES
############
my $file           = "";
my $plant          = uc($ENV{ENV_FACILITY});     ### MFT ENV VAR
my $env_mod        = "";
my $mft_flag       = ($^O=~/linux/i) ? 1 : 0; 	### SET 0=OTHERS; 1=LINUX/MFT
my %testplan  	   = ();
my %good_bins	   = ();
my $path_to_file   = dirname($0);
my $FTFET_REF 	   = "${path_to_file}/limit_rel.ref";
my $polarity_flag  = "";
my $tp_filename	   = "";


######################
# RETRIEVE PARAMETERS
######################
$result = GetOptions ("infile=s"  => \$file,
		      "plant=s"   => \$plant,
                      "env_mod=s" => \$env_mod);
require $env_mod if $env_mod ne "";               ### LOAD OPTIONAL MODULE



#################
# DISPLAY SYNTAX
#################
if ($file eq "")
{
        print "syntax\n";
        print "\tscript -infile=<datalog file> -plant=<plant(opt)> -env_mod=$ENV{ENV_CONV_SCRIPT}/env_mod.pm(opt)>\n";
        exit 1;
}



#########################################
# LOAD TEST POLARITY REF TABLE TO A HASH
#########################################
my %ref_polarity = ();
open FH, $FTFET_REF or die "cannot open $FTFET_REF. $!\n";
while(<FH>)
{
	chomp($_);
        if (!/#/)
        {
        	($testname, $desc, $nlow, $nhi, $plow, $phi, $bias, $npol, $ppol) = split /\,/, $_;
                $testname =~ s/ |\t//g;
                $desc     =~ s/[ |\t]{0,8}//;
                $nlow     =~ s/ |\t//g;
                $nhi      =~ s/ |\t//g;
                $plow     =~ s/ |\t//g;
                $phi      =~ s/ |\t//g;
                $bias     =~ s/ |\t//g;
                $npol     =~ s/ |\t//g;
                $ppol     =~ s/ |\t//g;

                $ref_polarity{$testname} =
                {
                	DESC => $desc,
                        NLOW => $nlow,
                        NHI  => $nhi,
                        PLOW => $plow,
                        PHI  => $phi,
                        BIAS => $bias,
                        NPOL => $npol,
                        PPOL => $ppol,
                };
        }
}
close(FH);



############
# PARSE PRN 
############
parse_prn();


#################
# DETECT CHANNEL
#################
&detect_channel;


####################################
# CONVERT LIMITS FROM ABS TO SIGN
####################################
abs_to_signed_limits();


#######################
# CREATE STDF TESTPLAN
#######################
create_tp();

########################
# RETURN CONVERTED FILE
########################
print ",$tp_filename"      if $mft_flag==0;
print "\ntp=$tp_filename"  if $mft_flag==1;

exit 0;



#<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< SUBROUTINES >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
####################
# PARSE PRN ROUTINE
####################
sub parse_prn
{
	my $testname_flag = 0;

	open FH, $file or die "error msg: can't open $file. $!\n";
	while(<FH>)
	{
		
		### GET AUTHOR
		if ($_=~/COMPILED BY\:/)
		{	
			($dummy1, $oper) = split /\:/, $_;
		}
		### IF 1, WILL START COLLECTING TESTPLAN DETAILS
		elsif ($_=~/NO\./)
		{
			$testname_flag = 1;
		}	
		### GET BIN INFO  
		elsif ($_=~/DO ALL/)
                {
			### TOGGLE OFF $testname_flag
                        $testname_flag = 0;
			#====================================================================================
                        #          1         2         3         4         5         6         7         8	
			#012345678901234567890123456789012345678901234567890123456789012345678901234567890 	
			#12 POST O/S       BIN=17R   DO ALL?=NO  (OR)  TESTS:   14F 15F 16F	
			#====================================================================================
			$sbin_num = substr $_, 0, 3;
			$sbin_name= substr $_, 3,15;
			$hbin_num = substr $_,22, 4;
			$test_nums= substr $_,52;
			
			$sbin_num =~ s/\s+//g;
			$sbin_name=~ s/\s+$//;
			$sbin_name=~ s/\W//g;	 	### REMOVE NON-ALPHANUMERIC CHARS
			$hbin_num =~ s/\s+//g;
			@test_nums = split /\s+/, $test_nums;
			

			### COLLECT REJECT HW BINS 
			if ($hbin_num=~/\b\d{1,2}R\b/)
			{
				foreach (@test_nums)
				{
					$_        =~ s/F//;
					$hbin_num =~ s/R//;

					if($_ ne "")
					{
						$testplan{$_}{SBIN_NUM} = $sbin_num;
						$testplan{$_}{SBIN_NAM} = $sbin_name;
						$testplan{$_}{HBIN_NUM}	= $hbin_num;
						$testplan{$_}{HBIN_NAM} = "HWBIN".$hbin_num;
					}
				}
			}
			### COLLECT GOOD HW BINS
			elsif ($hbin_num=~/\b\d{1,2}\b/)
			{
				$good_bins{$hbin_num} =
				{
					SBIN_NUM => $sbin_num,
					SBIN_NAM => $sbin_name,
					HBIN_NAM => $sbin_name,
				};		
			
				####### Ready to Populate the GOODBIN file with the good HBINS ####
                                #
                                print GOOD_OUT "$hbin_num\n";
                                #
                                ####### Wasn't that easy #########################################
			}
                
		}
		### GET TESTPLAN DETAILS
		elsif ($testname_flag == 1 && $_=~/\w/)
		{
			#====================================================================================
			#	   1         2         3         4         5         6         7         8
			#012345678901234567890123456789012345678901234567890123456789012345678901234567890
			# 10  RDSP   ID = 2.4000A  VGS= 2.5000V  V4S= OPEN           28.000MO  49.000MO A
			#====================================================================================
			$test_num   = substr $_, 0, 4;
			$test_name  = substr $_, 5, 6;
			$test_bias1 = substr $_,12,14;	
			$test_bias2 = substr $_,26,14;
			$test_bias3 = substr $_,40,14;
			### FOR FX TEST
			if ($test_bias1=~/\=\(/)          
			{
				$test_bias1 = substr $_,12,30;
				$test_bias2 = "";
			}
			$low_limit  = substr $_,59, 9;
			$low_limit  =~ /([A-Z]+)/i;
			$low_unit   = $1;
			$hi_limit   = substr $_,69, 9;
			$hi_limit   =~ /([A-Z]+)/i;
			$hi_unit    = $1;
			$limit_type = substr $_,79, 1;
			
			$test_num   =~ s/\s+//g;
			$test_name  =~ s/\s+//g;
			$test_bias1 =~ s/\s+//g;
			$test_bias2 =~ s/\s+//g;
			$test_bias3 =~ s/\s+//g;
			$low_limit  =~ s/\s+//g;
			$low_unit   =~ s/\s+//g;
			$hi_limit   =~ s/\s+//g;
			$hi_unit    =~ s/\s+//g;

			### CHECK FOR A VALID TEST SEQ NUMBER, TESTNAME & BIAS INFO
			if ($test_num > 0 && $limit_type=~/[A|S]/)	
			{
				### CONVERT TO BASE UNIT
				$unit = "";
				if($low_limit ne "" && $low_unit ne "")
				{
                        		($unit, $low_limit) = &Convert2BaseUnit($low_unit, $low_limit);
				}

				if($hi_limit ne "" && $hi_unit ne "")
				{
                        		($unit, $hi_limit)   = &Convert2BaseUnit($hi_unit, $hi_limit);
				}

				
				### SUBSTITUTE NONE IF EMPTY. DONT USE '||', IT WILL REPLACE IF LIMIT = 0
                                $low_limit="NONE" if $low_limit eq "";
                                $hi_limit ="NONE" if $hi_limit eq "";


				### GET BIAS POLARITY
				if ($test_bias1=~/\=\-/)
				{
					$sign = "-";	
				}
				else
				{
					$sign = "+";
				}
					
				### STORE TO A HASH
				$testplan{$test_num} =
				{
					TEST_NAME => $test_name,
					BIAS1	  => $test_bias1,
					BIAS2     => $test_bias2,
					BIAS3     => $test_bias3,
					BIAS_SIGN => $sign,
					LOW_LIMIT => $low_limit,
					HI_LIMIT  => $hi_limit,
					UNIT      => $unit,
					SBIN_NUM  => "",
					SBIN_NAM  => "",
					HBIN_NUM  => "",
					HBIN_NAM  => "",
				};
			
				#print "$test_num ... $test_name ... $low_limit ... $hi_limit ... $unit\n";
			}
		}


		### GET SEGMENT RANGE (we will then calculate segment count)
		elsif($_=~/ACTIVE SEGMENTS/)
                {
                        ($trash,$SEG_CNT) = (split /=/, $_);
              
			($S_SEG, $E_SEG) = (split  / TO /, $SEG_CNT);
			$S_SEG =~s/s+//;
			$E_SEG =~s/s+//;

			$SEG_CNT = ($E_SEG - $S_SEG) +1;
			#print "SEG_CNT: $SEG_CNT\n";
		}
		
		### GET ALTERNATE SEGMENTS
                elsif($_=~/ALTERNATE SEGMENTS/)
                {
                        ($trash,$SEG_MODE) = (split /=/, $_);
                        #print "SEGMENT MODE: $SEG_MODE\n";
                }


		### NO NEED TO PROCEED AFTER THIS LINE IS ENCOUNTERED
        	elsif ($_=~/LABEL PRINTER(DISABLED)/)
        	{
			$go_on = 1;
                	last;
        	}
	}
	close(GOOD_OUT);	
	close(FH);
}

#################
# DETECT CHANNEL
#################
sub detect_channel
{
        foreach (sort {$a <=> $b} keys %testplan)
        {
                my $testname = $testplan{$_}{TEST_NAME};

                ### EXIT IF CHANNEL HAS BEEN DETERMINED
                last if $polarity_flag ne "";

                ### NEXT IF TESTNAME DOES NOT EXIST IN REF
                next if ! defined $ref_polarity{$testname};

                ### CHECK IF POLARITY COLS ARE NOT EMPTY
                if ($ref_polarity{$testname}{NPOL} ne "" && $ref_polarity{$testname}{PPOL} ne "")
                {
                        ### CHECK IF BIAS NAME MATCHES
                        if($testplan{$_}{BIAS1}=~/$ref_polarity{$testname}{BIAS}/)
                        {
                                ### CHECK IF BIAS SIGN MATCHES
                                if ($ref_polarity{$testname}{PPOL} eq $testplan{$_}{BIAS_SIGN})
                                {
                                        $polarity_flag = "P";
                                }
                                elsif ($ref_polarity{$testname}{NPOL} eq $testplan{$_}{BIAS_SIGN})
                                {
                                        $polarity_flag = "N";
                                }
                        }
                }
        }

        ### EXIT IF NOTHING MATCHES ABOVE
        if ( $polarity_flag eq "")
        {
		print "Cannot detect channel. please check testpan file.\n";
                exit 1;
        }
}


####################################
# CONVERT LIMITS FROM ABS TO SIGN
####################################
sub abs_to_signed_limits
{
	foreach (sort {$a <=> $b} keys %testplan)
        {
		my $testname = $testplan{$_}{TEST_NAME};

		$lsl_sign = $ref_polarity{$testname}{$polarity_flag."LOW"};
                $usl_sign = $ref_polarity{$testname}{$polarity_flag."HI"};
		#print "\n$_) $testname ... lsl_sign: $lsl_sign ... usl_sign: $usl_sign\n";

		### CHECK FOR FX TESTS   
		if ($testplan{$_}{BIAS1} =~ /\=\(.+\)/)
                {
                        # IF BIAS1 CONTAINS PARENTHESIS THEN TEST IS AN FX
                        # NO PROCESS WILL TAKE PLACE FOR FX TESTS. LIMITS SHOULD REMAIN THE SAME.
			$testplan{$_}{BIAS1} =~ s/\"\(\)//g;

                	#print "...before... lowlim: $testplan{$_}{LOW_LIMIT} ... hilim: $testplan{$_}{HI_LIMIT}\n";

			if ($testplan{$_}{LOW_LIMIT} eq "NONE")
			{
				$testplan{$_}{LOW_LIMIT} = 0;
			}
			elsif ($testplan{$_}{HI_LIMIT} eq "NONE")
			{
				$testplan{$_}{HI_LIMIT} = $FLT_MAX;
			}
			elsif ($testplan{$_}{LOW_LIMIT} eq "NONE" && $testplan{$_}{HI_LIMIT} eq "NONE")
			{
				$testplan{$_}{LOW_LIMIT} = -$FLT_MAX;
				$testplan{$_}{HI_LIMIT}  = $FLT_MAX;
			}	
			#print "...after... lowlim: $testplan{$_}{LOW_LIMIT} ... hilim: $testplan{$_}{HI_LIMIT} -> FX\n";
		}
		elsif(defined $ref_polarity{$testname})
		{
		 	### CONV RULES FOR EMPTY/NONE LIMITS
			###          LSL    USL   POLARITY  	  		LSL	USL
		 	### CASE1    NONE   1.0      -       - convert to ->   -1.0    	0 
			### CASE2    1.0    NONE     -       - convert to ->   -1e21   -1.0
			### CASE3    1.0    1.5      -       - convert to ->   -1.5    -1.0
			###
                        ### CASE4    NONE   1.0      +       - convert to ->    0       1.0
                        ### CASE5    1.0    NONE     +       - convert to ->    1.0	1e21
                        ### CASE6    1.0    1.5      +       - convert to ->    1.0     1.5
                        ### 
                        ### CASE7    NONE   1.0     -/+      - convert to ->   -1.0     1.0
                        ### CASE8    1.0    NONE    -/+      - convert to ->   -1.0     1.0

                	#print "...before... lowlim: $testplan{$_}{LOW_LIMIT} ... hilim: $testplan{$_}{HI_LIMIT}\n";
			### FOR "-" POLARITY 
			if ($lsl_sign eq "-" && $usl_sign eq "-")
			{
				### CASE 1
				if ($testplan{$_}{LOW_LIMIT} eq "NONE")
				{
					$testplan{$_}{LOW_LIMIT} = $testplan{$_}{HI_LIMIT} * -1;
					$testplan{$_}{HI_LIMIT}  = 0;
				}
				### CASE 2
				elsif ($testplan{$_}{HI_LIMIT} eq "NONE")
				{
					$testplan{$_}{HI_LIMIT} = $testplan{$_}{LOW_LIMIT} * -1;
					$testplan{$_}{LOW_LIMIT}= -$FLT_MAX;
				}
				### CASE 3
				else
				{
					$dummy = $testplan{$_}{HI_LIMIT};
					$testplan{$_}{HI_LIMIT}   = $testplan{$_}{LOW_LIMIT} * -1;
					$testplan{$_}{LOW_LIMIT}  = $dummy * -1;
				}	
			}
			### FOR "+" POLARITY
			elsif ($lsl_sign eq "+" && $usl_sign eq "+")
			{
				### CASE 4
				if ($testplan{$_}{LOW_LIMIT} eq "NONE")	
				{
					$testplan{$_}{LOW_LIMIT} = 0;
				}
				### CASE 5 
                                elsif ($testplan{$_}{HI_LIMIT} eq "NONE")
                                {
					$testplan{$_}{HI_LIMIT} = $FLT_MAX;
				}
				### CASE 6 ( AS IS) 
			}
			### FOR "-/+" POLARITY
			elsif ($lsl_sign eq "-" && $usl_sign eq "+")
                        {
                                ### CASE 7      
                                if ($testplan{$_}{LOW_LIMIT} eq "NONE")       
                                {
                                        $testplan{$_}{LOW_LIMIT} = $testplan{$_}{HI_LIMIT} * -1;
                                }
                                ### CASE 8 
                                elsif ($testplan{$_}{HI_LIMIT} eq "NONE")
                                {
                                        $testplan{$_}{HI_LIMIT}   = $testplan{$_}{LOW_LIMIT};
					$testplan{$_}{LOW_LIMIT} *= -1;
                                }
				else
				{
					$testplan{$_}{LOW_LIMIT} *= -1;
				}
			}	
			#print "...after... lowlim: $testplan{$_}{LOW_LIMIT} ... hilim: $testplan{$_}{HI_LIMIT}\n";
		}	
		else
		{
			print "$testname not in test polarity ref file. Please update\n";
			exit 1;
		}
	}
}



#######################
# CREATE STDF TESTPLAN
#######################
sub create_tp
{
	$tp_filename = "${file}.TP";
        open FH, ">$tp_filename" or die "error msg: $!";

	### GET TESTPLAN NAME FROM FILENAME ###
	my ($tp_name,) = split /\./, substr($file,rindex($file,"/") + 1);
	$tp_name = "FT_".$tp_name;

	#############
	# EMIR RECORD
	#############
	%out::emir              = %{$out::init{emir}};
        $out::emir{mode_cod}    = "C";
        $out::emir{setup_t}     = stdf_time();
        $out::emir{job_nam}     = $tp_name;
        $out::emir{job_rev}     = 0;
        $out::emir{spec_nam}    = $tp_name;
        $out::emir{spec_rev}    = 0;
        print FH &out::pack_EMIR(\%out::emir);

	##############
	# EPDR RECORD
	##############
	### 1) TESTS & REJECT BINS


	if($SEG_CNT > 1 && $SEG_MODE != 2)
        {

		foreach (sort {$a<=>$b} keys %testplan)
        	{
			for($ii =1; $ii<= $SEG_CNT; $ii++)
			{				
				### NEXT IF NO TESTNAME
				next if $testplan{$_}{TEST_NAME} eq "";	

				### REPLACE '"', '(' & ')' w/ SPACE 
				$testplan{$_}{BIAS1} =~ s/[\"|\(|\)]/ /g;

				$newtst_num = ($_ * 10) + $ii;

       			        %out::epdr           = %{$out::init{epdr}};
       	        		$out::epdr{test_num} = $newtst_num;
       		         	$out::epdr{units}    = $testplan{$_}{UNIT};
               		 	$out::epdr{lo_limit} = $testplan{$_}{LOW_LIMIT};
                		$out::epdr{hi_limit} = $testplan{$_}{HI_LIMIT};
				$out::epdr{pin_1}    = $ii;
                		$out::epdr{test_nam} = "T".$newtst_num."_".$testplan{$_}{TEST_NAME};
                		$out::epdr{test_txt} = $testplan{$_}{BIAS1}." ".$testplan{$_}{BIAS2}." ".$testplan{$_}{BIAS3};
                		$out::epdr{hbin_num} = $testplan{$_}{HBIN_NUM};
				$out::epdr{hbin_nam} = $testplan{$_}{HBIN_NAM};
                		$out::epdr{sbin_num} = $testplan{$_}{SBIN_NUM};
                		$out::epdr{sbin_nam} = $testplan{$_}{SBIN_NAM};
				$out::epdr{opt_flg}  = "00000000";
                		print FH &out::pack_EPDR(\%out::epdr);
			}
		} 

	}

	else
	{
		 foreach (sort {$a<=>$b} keys %testplan)
                 {	
			### NEXT IF NO TESTNAME
       		        next if $testplan{$_}{TEST_NAME} eq "";

                	### REPLACE '"', '(' & ')' w/ SPACE
                	$testplan{$_}{BIAS1} =~ s/[\"|\(|\)]/ /g;

               		%out::epdr           = %{$out::init{epdr}};
                	$out::epdr{test_num} = $_;
       		        $out::epdr{units}    = $testplan{$_}{UNIT};
                	$out::epdr{lo_limit} = $testplan{$_}{LOW_LIMIT};
                	$out::epdr{hi_limit} = $testplan{$_}{HI_LIMIT};
                	$out::epdr{test_nam} = "T".$_."_".$testplan{$_}{TEST_NAME};
                	$out::epdr{test_txt} = $testplan{$_}{BIAS1}." ".$testplan{$_}{BIAS2}." ".$testplan{$_}{BIAS3};
                	$out::epdr{hbin_num} = $testplan{$_}{HBIN_NUM};
                	$out::epdr{hbin_nam} = $testplan{$_}{HBIN_NAM};
                	$out::epdr{sbin_num} = $testplan{$_}{SBIN_NUM};
                	$out::epdr{sbin_nam} = $testplan{$_}{SBIN_NAM};
                	$out::epdr{opt_flg}  = "00000000";
	                print FH &out::pack_EPDR(\%out::epdr);
		}
	}

	### 2) GOOD BIN/S ONLY	
	foreach (sort {$a<=>$b} keys %good_bins)
	{
		%out::epdr           = %{$out::init{epdr}};
                $out::epdr{test_num} = (1000 + $_);
		$out::epdr{test_nam} = $good_bins{$_}{SBIN_NAM};
                $out::epdr{hbin_num} = $_;
                $out::epdr{hbin_nam} = $good_bins{$_}{HBIN_NAM};
                $out::epdr{sbin_num} = $good_bins{$_}{SBIN_NUM};
                $out::epdr{sbin_nam} = $good_bins{$_}{SBIN_NAM};
		$out::epdr{opt_flg}  = "00100000";
                print FH &out::pack_EPDR(\%out::epdr);
	}	

	#############
	# MRR RECORD
	#############
	%out::mrr = %{$out::init{mrr}};
        $out::mrr{finish_t} = stdf_time();
        print FH &out::pack_MRR(\%out::mrr);

        close(FH);
}




#######################
# CONVERT TO BASE UNIT
#######################
sub Convert2BaseUnit()
{
        my ($Unit, $Limit) = @_;
        my $mew = 0;

        ##### units available for conversion #####
        if ($Unit eq "%")
        {
                $mew = 1;
        }
        ### K STANDS FOR KILO & NOT A UNIT ###
        elsif ($Unit =~ /\bK\b/)
        {
                $mew  = 1e3;
                $Unit = "" ;
        }
        elsif ($Unit =~ /A\b/)
        {
                if ($Unit =~ /\bPA\b/)
                {
                        $mew = 1e-12;
                }
                elsif ($Unit =~ /\bNA\b/)
                {
                        $mew = 1e-9;
                }
                elsif ($Unit =~ /\bUA\b/)
                {
                        $mew = 1e-6;
                }
                elsif ($Unit =~ /\bMA\b/)
                {
                        $mew = 1e-3;
                }
                elsif ($Unit =~ /\bA/)
                {
                        $mew = 1;
                }
                elsif ($Unit =~ /\bKA/)
                {
                        $mew = 1e3;
                }
                $Unit = "A";
        }
	elsif ($Unit =~ /E\b/)
        {
                if ($Unit =~ /\bPE\b/)
                {
                        $mew = 1e-12;
                }
                elsif ($Unit =~ /\bNE\b/)
                {
                        $mew = 1e-9;
                }
                elsif ($Unit =~ /\bUE\b/)
                {
                        $mew = 1e-6;
                }
                elsif ($Unit =~ /\bME\b/)
                {
                        $mew = 1e-3;
                }
                elsif ($Unit =~ /\bE/)
                {
                        $mew = 1;
                }
                elsif ($Unit =~ /\bKE/)
                {
                        $mew = 1e3;
                }
                $Unit = "E";
        }
	elsif ($Unit =~ /H\b/)
        {
                if ($Unit =~ /\bPH\b/)
                {
                        $mew = 1e-12;
                }
                elsif ($Unit =~ /\bNH\b/)
                {
                        $mew = 1e-9;
                }
                elsif ($Unit =~ /\bUH\b/)
                {
                        $mew = 1e-6;
                }
                elsif ($Unit =~ /\bMH\b/)
                {
                        $mew = 1e-3;
                }
                elsif ($Unit =~ /\bH/)
                {
                        $mew = 1;
                }
                elsif ($Unit =~ /\bKH/)
                {
                        $mew = 1e3;
                }
		$Unit = "H";
	}
	elsif ($Unit =~ /N/)
        {
                if ($Unit =~ /\bPN\b/)
                {
                        $mew = 1e-12;
                }
                elsif ($Unit =~ /\bNN\b/)
                {
                        $mew = 1e-9;
                }
                elsif ($Unit =~ /\bUN\b/)
                {
                        $mew = 1e-6;
                }
                elsif ($Unit =~ /\bMN\b/)
                {
                        $mew = 1e-3;
                }
                elsif ($Unit =~ /\bN/)
                {
                        $mew = 1;
                }
                elsif ($Unit =~ /\bKN/)
                {
                        $mew = 1e3;
                }
                $Unit = "N";
        }
        elsif ($Unit =~ /V\b/)
        {
                if ($Unit =~ /\bPV\b/)
                {
                        $mew = 1e-12;
                }
                elsif ($Unit =~ /\bNV\b/)
                {
                        $mew = 1e-9;
                }
                elsif ($Unit =~ /\bUV\b/)
                {
                        $mew = 1e-6;
                }
                elsif ($Unit =~ /\bMV\b/)
                {
                        $mew = 1e-3;
                }
                elsif ($Unit =~ /\bV\b/)
                {
                        $mew = 1;
                }
                elsif ($Unit =~ /\bKV\b/)
                {
                        $mew = 1e3;
                }
                $Unit = "V";
        }
        elsif ($Unit =~ /O/)
        {

                if ($Unit =~ /\bPO\b/)
                {
                        $mew = 1e-12;
                }
                elsif ($Unit =~ /\bNO\b/)
                {
                        $mew = 1e-9;
                }
                elsif ($Unit =~ /\bUO\b/)
                {
                        $mew = 1e-6;
                }
                elsif ($Unit =~ /\bMO\b/)
                {
                        $mew = 1e-3;
                }
                elsif ($Unit =~ /\bO\b/)
                {
                        $mew = 1;
                }
                elsif ($Unit =~ /\bKO\b/)
                {
                        $mew = 1e3;
                }
                $Unit = "OHM";
        }
        elsif ($Unit =~ /M\b/)
        {

                if ($Unit =~ /\bPM\b/)
                {
                        $mew = 1e-12;
                }
                elsif ($Unit =~ /\bNM\b/)
                {
                        $mew = 1e-9;
                }
                elsif ($Unit =~ /\bUM\b/)
                {
                        $mew = 1e-6;
                }
                elsif ($Unit =~ /\bMM\b/)
                {
                        $mew = 1e-3;
                }
                elsif ($Unit =~ /\bM\b/)
                {
                        $mew = 1;
                }
                elsif ($Unit =~ /\bKM\b/)
                {
                        $mew = 1e3;
                }
                $Unit = "MHO";
        }
	elsif ($Unit =~ /U\b/)
        {

                if ($Unit =~ /\bPU\b/)
                {
                        $mew = 1e-12;
                }
                elsif ($Unit =~ /\bNU\b/)
                {
                        $mew = 1e-9;
                }
                elsif ($Unit =~ /\bUU\b/)
                {
                        $mew = 1e-6;
                }
                elsif ($Unit =~ /\bMU\b/)
                {
                        $mew = 1e-3;
                }
                elsif ($Unit =~ /\bU\b/)
                {
                        $mew = 1;
                }
                elsif ($Unit =~ /\bKU\b/)
                {
                        $mew = 1e3;
                }
                $Unit = "UNIT";
        }
        elsif ($Unit =~ /Z\b/)
        {

                if ($Unit =~ /\bPZ\b/)
                {
                        $mew = 1e-12;
                }
                elsif ($Unit =~ /\bNZ\b/)
                {
                        $mew = 1e-9;
                }
                elsif ($Unit =~ /\bUZ\b/)
                {
                        $mew = 1e-6;
                }
                elsif ($Unit =~ /\bMZ\b/)
                {
                        $mew = 1e-3;
                }
                elsif ($Unit =~ /\bZ\b/)
                {
                        $mew = 1;
                }
                elsif ($Unit =~ /\bKZ\b/)
                {
                        $mew = 1e3;
                }
                $Unit = "Z";
        }
        else
        {
		print "Undefined unit: $Unit\n";
		exit 1;
        }


        if ($mew != 0)
        {
                $Limit = $Limit * $mew;
        }

        return ($Unit, $Limit);
}
