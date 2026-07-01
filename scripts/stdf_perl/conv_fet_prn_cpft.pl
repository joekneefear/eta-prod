#!/usr/bin/perl
#
# Confidential Property of Fairchild Semiconductor Corperation
# (c) Copyright Fairchild Semiconductor Corperation, 1999
# All rights reserved
#
# MODIFICATION HISTORY:
#
# DATE        WHO             DESCRIPTION
# ___________ ______________  __________________________________________________
# 04-06-2002  Ben Rommel Kho  original  
# 04-17-2002  Ben Rommel Kho  modified to trap full quad files & inconsistent filenames 
# 06-06-2002  Ben Rommel Kho  set specific value on valid limits
# 08-21-2002  Ben Rommel Kho  modified to use spec limits as valid limits on FX tests 
#			      that carries no upper & lower spec limits in a testplan.
# 09-12-2002  Ben Rommel Kho  add new spec limit case scenarios for FX tests.
# 11-15-2002  Ben Rommel Kho  used open valid limits for open spec limits
# 11-11-2003  Ben Rommel Kho  Move Corr Testplans to CPFETCORR's $FTP_IN dir.
# 07-19-2005  Ben Rommel Kho  Changed Valid Limit Rules: 
#			       1) On -LSL & -USL, UVL is 0
#			       2) On +LSL & +USL, LVL is 0
# 10-27-2005  Ben Rommel Kho  Modified for regionalization
# 01-25-2007  Ben Rommel Kho  Modified to auto-assign correct Valid & Spec Limits.
#			      Remove T# testname prefix
# 03-17-2007  Ben Rommel Kho  Added "FT_" prefix to testname
# 03-29-2007  Ben Rommel Kho  Corrected SBIN Parsing and trap param w/o bin assignment.
#                             Parse COP & COF to determine BIN assignment as well.
# 04-05-2007  Ben Rommel Kho  Fixed bin asssignement on params w/ successive COP & COF
# 08-07-2007  Ben Rommel Kho  Removed trailing zeroes from bias info
# 09-12-2007  Ben Rommel Kho  Remove spaces from param name.
# 10-02-2007  Ben Rommel Kho  Remove " and ' from bias info.
# 10-09-2007  Ben Rommel Kho  Fixed bug that remove spaces in parameter name
# 04-28-2008  Ben Rommel Kho  Fixed to support dual die. Test Number becomes "XY" 
#			      where X is Test # while Y is the die segment #.
# 10-10-2008  Ben Rommel Kho  Generate TP_STDF in $ENV_CONV_IN instead of $ENV_CONV_GOOD
# 08-25-2009  Ben Rommel kho  Allowed parameters not to have bin assignment
# 09-14-2010  Ben Rommel Kho  Fixed bug that prevented dual segment detection.
# 03-17-2011  Gilbert Miole   Enhanced mail notification, make use of the .forward file. 
# 04-07-2011  Gilbert Miole   Adopted .TD & .TP STDF filenaming convention.
# 06-22-2012  Ben Rommel Kho  Adjusted for MFT
# 06-28-2012  Gilbert Miole   Remove file path in the tp_name
# 07-20-2012  Reuben Capio    Added checking for correct value format before populating array
# 08/31/2012  Rodney Cyr      Changed negative exit codes to positive (negative exit codes are not valid in unix).
# 05/13/2014  Gilbert Miole   Added email notification on error event.
# 05/14/2014  Gilbert Miole   Removed the file path in the error message of the test plan file.
#
#
#
# Script Function: Converts FET's PRN testplan to STDF+. This is intended for single site & quad(not full binning) 
#                  only.                        
#
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
#use MIME::Lite                ;


######################
# Load Specifications
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
my $file                = "";
my $plant               = uc($ENV{ENV_FACILITY});     ### MFT ENV VAR
my $env_mod             = "";
my $mft_flag            = ($^O=~/linux/i) ? 1 : 0; 	### SET 0=OTHERS; 1=LINUX/MFT
my %testplan            = ();
my %good_bins           = ();
my $site_flag           = "";  
my $bad_bin_count_flag  = 0;
my $tp_filename		= "";
my $path_to_file        = dirname($0);
my $limit_ref_file      = "${path_to_file}/limit.ref";
my %VL 			= ();
my %SL 			= ();
my $die_cnt             = 1; 
my $error_msg		= "";


######################
# RETRIEVE PARAMETERS
######################
$result = GetOptions ("infile=s"  => \$file,
		      "plant=s"   => \$plant,
                      "env_mod=s" => \$env_mod);
require "$ENV{ENV_DB_SCRIPT}/$env_mod" if $env_mod ne "";       ### LOAD OPTIONAL MODULE


#################
# DISPLAY SYNTAX
#################
if ($file eq "")
{
        print "syntax\n";
        print "\tscript -infile=<datalog file> -plant=<plant(opt)> -env_mod=$ENV{ENV_CONV_SCRIPT}/env_mod.pm(opt)>\n";
        exit 1;
}



###################################
# LOAD LIMIT REF TABLE INTO A HASH
###################################
&loading_limit_ref_table_into_a_hash();



############
# PARSE PRN 
############
&pre_parse_module()    if $env_mod ne "";
&parse_prn();
&cop_binning();



########################################################
# SET VALID LIMITS & ASSIGN VALUE TO A BLANK SPEC LIMIT
########################################################
&assign_limits();


        ############################################
        # DISPLAY TESTPLAN (FOR DEBUGGING PURPOSES)
        ############################################
        #&display_testplan();


#######################
# CREATE STDF TESTPLAN
#######################
create_tp();



########################
# RETURN CONVERTED FILE
########################
print "$tp_filename,"      if $mft_flag==0;
print "\ntp=$tp_filename"  if $mft_flag==1;


exit 0;



#<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< SUBROUTINES >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

########################
# DISPLAY PARSED VALUES
########################
sub display_testplan
{
	print "Active Segment: $die_cnt\n";

        foreach (sort {$a<=>$b} keys %testplan)
        {
               print "$_\t $testplan{$_}{TEST_NAME}\t";
               print "$testplan{$_}{BIAS1}\t";
               print "$testplan{$_}{BIAS2}\t";
               print "$testplan{$_}{BIAS3}\t";
               print "$testplan{$_}{LOW_VALID}\t$testplan{$_}{LOW_LIMIT}\t";
               print "$testplan{$_}{HI_LIMIT}\t$testplan{$_}{HI_VALID}\t";
               print "$testplan{$_}{SBIN_NUM}\t$testplan{$_}{SBIN_NAM}\t";
               print "$testplan{$_}{DATALOG}\t$testplan{$_}{FLAG}\n";
        }
}


###################################
# LOAD LIMIT REF TABLE INTO A HASH
###################################
sub loading_limit_ref_table_into_a_hash
{
	open FH, $limit_ref_file or die "can't open $limit_ref_file file\n";
	while($line=<FH>)
	{
        	chomp($line);
        	$line=~ s/\s+//g;
        	next if $line =~ /\#/;

        	(@tmp) = split /\,/,$line;
        	$VL{$tmp[0]} =
        	{
                	ANP => $tmp[1],
                	AXP => $tmp[2],
                	BNN => $tmp[3],
                	BXP => $tmp[4],
                	CNN => $tmp[5],
                	CXN => $tmp[6]
        	};

        	$SL{$tmp[0]} =
        	{
                	NEXP => $tmp[7],
                	NNXE => $tmp[10],
                	NEXN => $tmp[11],
                	NPXE => $tmp[14]
        	};
	}
	close(FH);
}


####################
# PARSE PRN ROUTINE
####################
sub parse_prn
{
        my $testname_flag = 0;


	open FH, "$file" or die "error msg: can't open $file. $!\n";
        while(<FH>)
        {
		chomp;

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
                elsif ($_=~/DO ALL/ && $site_flag ne "Q")
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
                        $sbin_name=~ s/\W//g;           ### REMOVE NON-ALPHANUMERIC CHARS
                        $hbin_num =~ s/\s+//g;
                        
                        #POPULATE ARRAY ONLY IF LINE HAS VALUES WITH CORRECT FORMAT
                        if ($test_nums =~ /\dF/)
                        {
                                @test_nums = split /\s+/, $test_nums;
                        } 

                        ### COLLECT REJECT HW BINS 
                        if ($hbin_num=~/\b\d{1,2}R\b/)
                        {
                                foreach (@test_nums)
                                {
                                        $_           =~ s/F//;
                                        $hbin_num    =~ s/R//;

                                        if($_ ne "")
                                        {
                                                $testplan{$_}{SBIN_NUM} = $sbin_num;
                                                $testplan{$_}{SBIN_NAM} = $sbin_name;
                                                $testplan{$_}{HBIN_NUM} = $hbin_num;
                                                $testplan{$_}{HBIN_NAM} = "HWBIN".$hbin_num;

						$bad_bin_count_flag = 1;
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
                       
			}
                }
                ### GET TESTPLAN DETAILS
                elsif ($testname_flag == 1 && $_=~/\w/)
                {
                
                        
                        #====================================================================================
                        #          1         2         3         4         5         6         7         8
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
                        $low_limit  = substr $_,59, 7;
                        $low_unit   = substr $_,66, 2;
                        $hi_limit   = substr $_,69, 7;
                        $hi_unit    = substr $_,76, 2;
                        $limit_type = substr $_,79, 1;
			$cop        = substr $_,86, 3;
                        $cof        = substr $_,90, 3;
                        
                        $test_num   =~ s/\s+//g;
                        $test_name  =~ s/\s+|\^//g;
                        $test_bias1 =~ s/\s+//g;
                        $test_bias2 =~ s/\s+//g;
                        $test_bias3 =~ s/\s+//g;
                        $low_limit  =~ s/\s+//g;
                        $low_unit   =~ s/\s+|\d+//g;
                        $hi_limit   =~ s/\s+//g;
                        $hi_unit    =~ s/\s+|\d+//g;
			$cop        =~ s/\s+//g;
                        $cof        =~ s/\s+//g;

        
			### APPEND BIAS INFO TO TESTNAME ###
                        $test_bias1 = &clean_bias_info($test_bias1);
                        $test_bias2 = &clean_bias_info($test_bias2);
                        $test_bias3 = &clean_bias_info($test_bias3);


                        ### CHECK FOR A VALID TEST SEQ NUMBER & LIMIT TYPE
                        if ($test_num > 0 && $test_name ne "" && $limit_type=~/[A|S]/)      
                        {
				#print "$test_num\, $test_name\, $low_limit\, $hi_limit\, $low_unit\, $hi_unit\n";
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
                                        BIAS1     => $test_bias1,
                                        BIAS2     => $test_bias2,
                                        BIAS3     => $test_bias3,
                                        BIAS_SIGN => $sign,
                                        LOW_LIMIT => $low_limit,
                                        HI_LIMIT  => $hi_limit,
					LOW_VALID => "",
					HI_VALID  => "",
                                        UNIT      => $unit,
                                        LIM_TYPE  => $limit_type,
                                        SBIN_NUM  => "",
                                        SBIN_NAM  => "",
                                        HBIN_NUM  => "",
                                        HBIN_NAM  => "",
					COP       => $cop||$cof,
                                };
                        }
                }
                ### SINGLE/DUAL DIE ###
		elsif  ($_=~/ACTIVE SEGMENTS/)
                {
			my ($dump, $tmp_die_cnt) = split /TO/,$_;
			$tmp_die_cnt =~ s/\D//g;
			$die_cnt     = $tmp_die_cnt if $tmp_die_cnt =~ /^[2-9]$/;
                        $go_on = 1;
                        last;
                }
        }
	close(FH);


	#############
        # TRAPPINGS:
        #############
	if ($bad_bin_count_flag == 0)
	{
                print "File no bin info\n";
		#&send_email("File no bin info\n");
                exit 1;
	}
}



#########################################
# CLEAN BIAS INFO FROM UNNECCESSARY INFO
#########################################
sub clean_bias_info()
{
        my $loc_bias = shift;
        
        ### REMOVE UNNECCESSARY INFO ###
        $loc_bias    =~ s/VGS\=0\.0000V|V4S\=OPEN|VBE\=0\.0000V//g;  
        
        ### REMOVE TRAILING ZEROES ###
        $loc_bias    =~ s/0{1,}([a-zA-Z]*)$/\1/g;
        $loc_bias    =~ s/\.([a-zA-Z]*)$/\1/g;

	### REMOVE ", ', ( & ) ###
        $loc_bias    =~ s/\"|\'|\(|\)//g;

        return ($loc_bias);
}


##################################
# USE COP BIN TO PARAM W/O BIN NO
##################################
sub cop_binning
{
         foreach (reverse sort {$a<=>$b} keys %testplan)
        {
                if ($testplan{$_}{SBIN_NUM} eq "" && $testplan{$_}{COP} =~ /\d{1,2}/)
                {
                        my $cop = $testplan{$_}{COP};
                        $testplan{$_}{SBIN_NUM} = $testplan{$cop}{SBIN_NUM};
                        $testplan{$_}{SBIN_NAM} = $testplan{$cop}{SBIN_NAM};
                }
        }
}


##################################################
# ASSIGN VALUE TO VALID LIMITS & BLANK SPEC LIMIT
##################################################
sub assign_limits
{

	##########################
	# LOOP TO EACH PARAMETERS
	##########################
	foreach my $test_num(keys %testplan)
	{

		my $testname = $testplan{$test_num}{TEST_NAME};
		next if $testname eq "";
		$error_msg="$file . $test_num) $testname , $testplan{$test_num}{LOW_LIMIT} , $testplan{$test_num}{HI_LIMIT}";	


		#####################################
		# ASSIGN VALUE TO A BLANK SPEC LIMIT
		#####################################
		if ($testplan{$test_num}{LOW_LIMIT} eq "NONE" && $testplan{$test_num}{HI_LIMIT} =~ /^\d+/)
		{
			$error_msg = $error_msg.", speclim=NONE & + ";	
			$testplan{$test_num}{LOW_LIMIT} = &compute_limit($testplan{$test_num}{HI_LIMIT}, $SL{$testname}{NEXP});	
		}
		elsif ($testplan{$test_num}{LOW_LIMIT} eq "NONE" && $testplan{$test_num}{HI_LIMIT} =~ /^\-\d+/)
		{
			$error_msg = $error_msg.", speclim=NONE & - ";
			$testplan{$test_num}{LOW_LIMIT} = &compute_limit($testplan{$test_num}{HI_LIMIT}, $SL{$testname}{NEXN});
		}
		elsif ($testplan{$test_num}{LOW_LIMIT} =~ /^\d+/ && $testplan{$test_num}{HI_LIMIT} eq "NONE")
                {
			$error_msg = $error_msg.", speclim=+ & NONE ";
                        $testplan{$test_num}{HI_LIMIT} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $SL{$testname}{NPXE});
                }
		elsif ($testplan{$test_num}{LOW_LIMIT} =~ /^\-\d+/ && $testplan{$test_num}{HI_LIMIT} eq "NONE")
                {
			$error_msg = $error_msg.", speclim=- & NONE ";
                        $testplan{$test_num}{HI_LIMIT} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $SL{$testname}{NNXE});
                }
		elsif ($testplan{$test_num}{LOW_LIMIT} eq "NONE" && $testplan{$test_num}{HI_LIMIT} eq "NONE") 
                {      
			$error_msg = $error_msg.", speclim=ALL FLT_MAX ";
			$testplan{$test_num}{LOW_LIMIT} = -$FLT_MAX;
			$testplan{$test_num}{HI_LIMIT}  = $FLT_MAX;
		}			
	
		######################
		# ASSIGN VALID LIMITS	
		######################
		if ($testplan{$test_num}{LOW_LIMIT} == -$FLT_MAX && $testplan{$test_num}{HI_LIMIT} == $FLT_MAX)
		{
			$error_msg = $error_msg." , vallim=ALL FLT_MAX ";
			$testplan{$test_num}{LOW_VALID} = -$FLT_MAX;
			$testplan{$test_num}{HI_VALID}  = $FLT_MAX;
		}
		elsif ($testplan{$test_num}{LOW_LIMIT} >= 0 && $testplan{$test_num}{HI_LIMIT} >= 0)
		{
			$error_msg = $error_msg." , vallim=MPXP ( $VL{$testname}{ANP} \; $VL{$testname}{AXP} )";
			$testplan{$test_num}{LOW_VALID} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $VL{$testname}{ANP});
			$testplan{$test_num}{HI_VALID}  = &compute_limit($testplan{$test_num}{HI_LIMIT},  $VL{$testname}{AXP});
		}
		elsif ($testplan{$test_num}{LOW_LIMIT} < 0 && $testplan{$test_num}{HI_LIMIT} >= 0)        
                {
			$error_msg = $error_msg." , vallim=MNXP ( $VL{$testname}{BNN} \; $VL{$testname}{BXP} )";
                        $testplan{$test_num}{LOW_VALID} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $VL{$testname}{BNN});
                        $testplan{$test_num}{HI_VALID}  = &compute_limit($testplan{$test_num}{HI_LIMIT},  $VL{$testname}{BXP});
                }
		elsif ($testplan{$test_num}{LOW_LIMIT} < 0 && $testplan{$test_num}{HI_LIMIT} < 0)            
                {      
			$error_msg = $error_msg." , vallim=MNXN = $VL{$testname}{CNN} \; $VL{$testname}{CXN} )";
                        $testplan{$test_num}{LOW_VALID} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $VL{$testname}{CNN});
                        $testplan{$test_num}{HI_VALID}  = &compute_limit($testplan{$test_num}{HI_LIMIT},  $VL{$testname}{CXN});
                }	

		##################
		# VALIDATE LIMITS
		##################
		if ($testplan{$test_num}{LOW_VALID} > $testplan{$test_num}{LOW_LIMIT} || $testplan{$test_num}{HI_LIMIT}  > $testplan{$test_num}{HI_VALID})
		{
			$error_msg = "$file. $test_num\) $testname lvl=$testplan{$test_num}{LOW_VALID} lsl=$testplan{$test_num}{LOW_LIMIT} usl=$testplan{$test_num}{HI_LIMIT} uvl=$testplan{$test_num}{HI_VALID} - invalid limits.";
                        print "$error_msg\n";
			#&send_email($error_msg);
                        exit 1;
		}
	}
}



################
# COMPUTE LIMIT
################
sub compute_limit()
{
	my $limit_value = shift;
	my $modifier    = shift;
	my $oper	= substr($modifier,0,1);
	my $modifier    = substr($modifier,1);
	my $result	= "";
	
	if ($oper eq "+")
	{ $result = $limit_value + $modifier; }
	elsif ($oper eq "-")
	{ $result = $limit_value - $modifier; }
	elsif ($oper eq "*")
        { $result = $limit_value * $modifier; }
	elsif ($oper eq "c")
        { $result = $modifier; }
	else
	{
		$error_msg = $error_msg." - invalid limit modifier";
                print "$error_msg\n";
		#&send_email($error_msg);
                exit 1;
        }

	return ($result);
}



#######################
# CREATE STDF TESTPLAN
#######################
sub create_tp
{
        $tp_filename = "${file}.TP";
        open FH, ">$tp_filename" or die "error msg: $!";

        ### GET TESTPLAN NAME FROM FILENAME ###
        my ($testplan_name,) = split /\./, substr($file,rindex($file,"/") + 1);
        $testplan_name = "FT_".$testplan_name;

        #############
        # MIR RECORD
        #############
        %out::emir              = %{$out::init{emir}};
        $out::emir{mode_cod}    = "C";
        $out::emir{setup_t}     = stdf_time();
        $out::emir{job_nam}     = $testplan_name;
        $out::emir{job_rev}     = 0;
        $out::emir{spec_nam}    = $testplan_name;
        $out::emir{spec_rev}    = 0;
	$out::emir{spec_rev}    = pad($out::emir{spec_rev},"\0");
        print FH &out::pack_EMIR(\%out::emir);

        ##############
        # EPDR RECORD
        ##############
        ### 1) TESTS & REJECT BINS
        foreach (sort {$a<=>$b} keys %testplan)
        {
		### CHECK FOR TESTNAME
                next if $testplan{$_}{TEST_NAME} eq "";

		### CONCATENATE BIAS INFO TO TESTNAME ###
		my $test_name = $testplan{$_}{TEST_NAME};
                $test_name    .= "_".$testplan{$_}{BIAS1} if $testplan{$_}{BIAS1} ne "";
                $test_name    .= "_".$testplan{$_}{BIAS2} if $testplan{$_}{BIAS2} ne "";

		
		my $subtest = "";
		for(my $i=1; $i <= $die_cnt; $i++)
		{
			$subtest = $i if $die_cnt > 1;	#<-- FOR DUAL DIE ONLY
		

                	%out::epdr           = %{$out::init{epdr}};
                	$out::epdr{test_num} = $_.$subtest;
                	$out::epdr{units}    = $testplan{$_}{UNIT};
                	$out::epdr{lo_limit} = $testplan{$_}{LOW_LIMIT};
                	$out::epdr{hi_limit} = $testplan{$_}{HI_LIMIT};
			$out::epdr{lo_censr} = $testplan{$_}{LOW_VALID};
                	$out::epdr{hi_censr} = $testplan{$_}{HI_VALID};
                	$out::epdr{test_nam} = $test_name;
                	$out::epdr{test_txt} = $test_name;
                	$out::epdr{hbin_num} = $testplan{$_}{HBIN_NUM} if $testplan{$_}{HBIN_NUM} ne "";
                	$out::epdr{hbin_nam} = $testplan{$_}{HBIN_NAM};
                	$out::epdr{sbin_num} = $testplan{$_}{SBIN_NUM} if $testplan{$_}{SBIN_NUM} ne "";
                	$out::epdr{sbin_nam} = $testplan{$_}{SBIN_NAM};
                	$out::epdr{opt_flg}  = "00000000";
                	print FH &out::pack_EPDR(\%out::epdr);
		}
        }

        ### 2) GOOD BIN/S FOR SINGLE SITE       
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
        my ($unit, $limit) = @_;
        my $multiplier     = 1;

        if ($unit =~ /^P/ && $unit !~ /^P$/)
        {
                $unit       =~ s/^P//;
                $multiplier = 1e-12;
        }
        elsif ($unit =~ /^N/ && $unit !~ /^N$/)
        {
                $unit       =~ s/^N//;
                $multiplier = 1e-9;
        }
        elsif ($unit =~ /^U/ && $unit !~ /^U$/)
        {
                $unit       =~ s/^U//;
                $multiplier = 1e-6;
        }
        elsif ($unit =~ /^M/ && $unit !~ /^M$/ && $unit !~ /MHO/i)
        {
                $unit       =~ s/^M//;
                $multiplier = 1e-3;
        }
        elsif ($unit =~ /^K/)
        {
                $unit       =~ s/^K//;
                $multiplier = 1e3;
        }
	
	$limit *= $multiplier;
	return ($unit, $limit);
}

#####################
# EMAIL NOTIFICATION
#####################
sub send_email
{
	my $tp_file = substr($file,rindex($file,"/") + 1);
        my $body    = shift;
	   $body    =~ s/$file/$tp_file/;
        my $msg     = MIME::Lite->new
        (
                Subject => "FET FT Test Plan: $tp_file rev 0 Failed to convert",
                From    => 'dpower@onsemi.com' ,
                To      =>  $email_list,
                Type    => 'text/plain',
                Data    =>  $body
        );
        $msg->send();

}
