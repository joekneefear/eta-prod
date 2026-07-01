##!/usr/bin/perl
#
# Confidential Property of Fairchild Semiconductor Corperation
# (c) Copyright Fairchild Semiconductor Corperation, 1999
# All rights reserved
#
# MODIFICATION HISTORY:
#
# DATE        WHO             DESCRIPTION
# ___________ ______________  __________________________________________________
# 02-01-2007  Ben Rommel Kho  Cloned from cpfet. Added auto-SBIN assignment 
# 03-07-2007  Ben Rommel Kho  Append Bias Info into testname but exclude "VGS= 0.0000V" & "V4S= OPEN"
# 08-06-2007  Ben Rommel Kho  Auto-generate TPL and FTP(put) to Sort server.
#			      Remove trailing zeroes from bias info
# 08-14-2007  Ben Rommel Kho  Changed the 1st column in TPL to reflect correct test# 
# 08-17-2007  Ben Rommel Kho  Corrected test number seq to match DL Converter. Seq starts w/ 1 & w/ incr of 1.
# 10-02-2007  Ben Rommel Kho  Remove " and ' from bias info.
# 10-09-2007  Ben Rommel Kho  Eliminated fusing of param & bias as it causes error to the cpfetquad converter.
# 10-11-2007  Ben Rommel Kho  Limit bias infor to 14 chars max in TPL so CPFETQUAD converter won't fail
# 10-23-2007  Ben Rommel Kho  Limit param name to 20 chars max in TPL
# 01-07-2008  Ben Rommel Kho  Modified to read in parameters w/ test nos > 80.
# 01-08-2008  Ben Rommel Kho  Fixed bug. Ensure numeric test number to read in valid params only.
# 01-19-2009  Ben Rommel Kho  Save TPL into $ENV_TP_RAW as reference.
# 05-06-2011 Gilbert Miole    Adopted .TD & .TP STDF filenaming convention.
# 07-16-2012 Gilbert Miole    Made MFT compatible.
# 08/31/2012 Rodney Cyr       Changed negative exit codes to positive (negative exit codes are not valid in unix).
# 05-13-2014 Gilbert Miole    Enable back email notification on failure event.
# 05-15-2014 Gilbert Miole    Removed file path in error message.
# 06-06-2019 Eric Alfanta     Changed email add domain to onsemi
# 23/Apr/2021 jgarcia       modified to support colo server. replace hardcoded TP and reference file folder location.
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
use MIME::Lite                ;
use Getopt::Long              ;
#use EDBUtil                   ;



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
our $file		= "";
my $subject             = "CPFETQUAD PRN CONVERTER";
my %testplan            = ();
my @testplan 		= ();
my %good_bins           = ();
my $site_flag           = "";  
my $bad_bin_count_flag  = 0;
my %datalog		= (); 
my @datalog		= ();
#my $limit_ref_file      = "$ENV{ENV_CONV_SCRIPT}/fet_limit_ref.txt";
#my $sbin_ref_file 	= "$ENV{ENV_CONV_SCRIPT}/fet_sbin_ref.txt";
my $limit_ref_file      = "$ENV{DPDATA}/data/cpsort_fet_quad/TP/fet_limit_ref.txt";
my $sbin_ref_file      = "$ENV{DPDATA}/data/cpsort_fet_quad/TP/fet_sbin_ref.txt";
my %VL 			= ();
my %SL 			= ();
my $error_msg		= "";
my $tp_type		= 1;		#(1=QUAD; 2=DUALS)
my $plant         	= uc($ENV{ENV_FACILITY});     #<-- MFT ENV VAR
my $mft_flag      	= ($^O=~/linux/i) ? 1 : 0;    #<-- SET 0=OTHERS; 1=LINUX
my ($dump, $envname, $dump) = split /\_/, uc($ENV{ENV_NAME});           #<-- GET ENV NAME



######################
# RETRIEVE PARAMETERS
######################
$result = GetOptions ("infile=s"   => \$file,
                      "plant=s"    => \$plant,
                      "env_mod=s"  => \$env_mod);
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



##############################
# LOAD REF TABLE INTO A HASHE
##############################
&loading_limit_ref_table_into_a_hash();
&loading_sbin_into_a_hash();
&pre_parse_module()    if $env_mod ne "";

############
# PARSE PRN 
############
&parse_prn();


########################################################
# SET VALID LIMITS & ASSIGN VALUE TO A BLANK SPEC LIMIT
########################################################
&assign_limits();


##############
# ASSIGN SBIN
##############
&assign_sbin();

	###################################
	# SPECIAL SBIN ASSIGNMENT ON DUALS
	###################################
	&assign_sbin_if_duals if $#datalog > 8;


##########################
# ASSIGN ALTERNATIVE SBIN
##########################
&assign_alt_sbin();


	############################################
        # DISPLAY TESTPLAN (FOR DEBUGGING PURPOSES)
        ############################################
        #&display_testplan();

#######################
# CREATE STDF TESTPLAN
#######################
&create_tp();


############################################
# GENERATE TPL FILE FOR CPFETQUAD CONVERTER
############################################
&generate_tpl();


########################
# RETURN CONVERTED FILE
########################
print "$tp_filename"       if $mft_flag==0;
print "\ntp=$tp_filename"  if $mft_flag==1;

exit 0;


#<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< SUBROUTINES >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

########################
# DISPLAY PARSED VALUES
########################
sub display_testplan
{
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


##################################
# LOAD SBIN REF TABLE INTO A HASH
##################################
sub loading_sbin_into_a_hash
{
        open FH, $sbin_ref_file or die "can't open $limit_ref_file file\n";
        while($line=<FH>)
        {
                chomp($line);
                $line=~ s/\s+//g;
                next if $line =~ /\#/;

                (@tmp) = split /\,/,$line;
                $SBIN{$tmp[0]} =
                {
                        NUM => $tmp[1],
			NAM => $tmp[2],
                };
        }
        close(FH);

}



####################
# PARSE PRN ROUTINE
####################
sub parse_prn
{
	my $i 		  = 0;
        my $testname_flag = 0;

	#open FH, "$ENV{ENV_CONV_IN}/$ARGV[0]" or die "error msg: can't open $ARGV[0]. $!\n";
	open FH, "$file" or die "error msg: can't open $file. $!\n";

        while(<FH>)
        {
                ### GET AUTHOR ###
                if ($_=~/COMPILED BY\:/)
                {       
                        ($dummy1, $oper) = split /\:/, $_;
                }
                ### START COLLECTING PARAMETERS ###
                elsif ($_=~/NO\./)
                {
                        $testname_flag = 1;
                }       
		### STOP COLLECTING PARAMETERS ###		
		elsif ($_=~/BIN\=/i && $_=~/DO ALL\?\=/)
		{
			$testname_flag = 0;
		}
                ### GET PARAMTER DETAILS ###
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
                        if ($test_bias1=~/RESULT\=\(/)          
                        {
                                $test_bias1 = substr $_,12,41;
                                $test_bias2 = "";
                        }
                        $low_limit  = substr $_,59, 7;
                        $low_unit   = substr $_,66, 2;
                        $hi_limit   = substr $_,69, 7;
                        $hi_unit    = substr $_,76, 2;
                        $limit_type = substr $_,79, 1;
                        
                        $test_num   =~ s/\s+//g;
                        $test_name  =~ s/\s+|\^//g;
                        $test_bias1 =~ s/\s+//g;
                        $test_bias2 =~ s/\s+//g;
                        $test_bias3 =~ s/\s+//g;
                        $low_limit  =~ s/\s+//g;
                        $low_unit   =~ s/\s+//g;
                        $hi_limit   =~ s/\s+//g;
                        $hi_unit    =~ s/\s+//g;

			$test_bias1 = &clean_bias_info($test_bias1);
                        $test_bias2 = &clean_bias_info($test_bias2);
                        $test_bias3 = &clean_bias_info($test_bias3);
        
			### STOP PARSING AFTER TEST NUM 20 ###
			my $save_to_hash = 1;					#<== 0=don't save;1=save
                        if ($test_num > 20 && $test_num <= 80)
			{
				$save_to_hash = 0;
				next;
			}

                        ### CHECK FOR A VALID TEST SEQ NUMBER & LIMIT TYPE ###
                        if ($test_num=~/[1-9]{1,}/ && $save_to_hash == 1 && $test_name ne "" && $limit_type=~/[A|S]/) 
                        {
				#print "saving $test_num\t$test_name\$low_limit\t$hi_limit\t$hi_unit\n";
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
					ALT_SBIN_NUM => "",
					ALT_SBIN_NAM => "",
					DATALOG      => "NO",
					FLAG         => "",
                                };

				$testplan[$i] = $test_num;
				$i = $i + 1;	
                        }

                }
		### DETERMINE USED PARAMETERS ###
		elsif ($_=~ /25 DL\s+DATA LOG/)
		{
			
			my $datalog = "";

			($dummy,$datalog) = split /\:/, $_;
			($datalog,$dummy) = split /2[1-9]/,$datalog;
			$datalog =~ s/^\s+|$\s+//g;
			(@datalog) = split /\s+/,$datalog;

			### IDENTIFY DATALOG PARAMETERS ###
			foreach (@datalog)
			{
				$testplan{$_}{DATALOG}="YES";
			}

			### DET LAST & 2ND TO THE LAST TESTS ##
			if ($#datalog <= 7) 
			{
				$l_testnum  = $testplan[$#testplan];
				$ll_testnum = $testplan[$#testplan - 1];
			}
			else
			{
				$tp_type    = 2 ;
				$last_param = $#testplan/2;
				$l_testnum  = $testplan[$last_param];
                                $ll_testnum = $testplan[$last_param - 1];
			}
			$testplan{$l_testnum}{FLAG}  = "L";		#<-- IDENTIFY TEST AS LAST TEST
			$testplan{$ll_testnum}{FLAG} = "2L";		#<-- IDENTIFY TEST AS 2ND TO THE LAST TEST
			
		}

                ### EXIT ON THIS LINE
                elsif ($_=~/DATA LOG INFORMATION/)
                {
                        $go_on = 1;
                        last;
                }
        }
	close(FH);
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


###################################################
# ASSIGN VALUE TO VALID LIMITS & BLANK SPEC LIMIT
##################################################
sub assign_limits
{

	##########################
	# LOOP TO EACH PARAMETERS
	##########################
	foreach $test_num(sort {$a<=>$b} keys %testplan)
	{

		my $testname = $testplan{$test_num}{TEST_NAME};
		next if $testname eq "";
		$error_msg="$file. $test_num) $testname , $testplan{$test_num}{LOW_LIMIT} , $testplan{$test_num}{HI_LIMIT}";	

		#print "$test_num \) $testname \n";
		#print "\t old: spec limits: $testplan{$test_num}{LOW_LIMIT} \; $testplan{$test_num}{HI_LIMIT} \n";

		#####################################
		# ASSIGN VALUE TO A BLANK SPEC LIMIT
		#####################################
		if ($testplan{$test_num}{LOW_LIMIT} eq "NONE" && $testplan{$test_num}{HI_LIMIT} =~ /^\d+/)
		{
			$error_msg .= ", NEXP\=$SL{$testname}{NEXP}";
			$testplan{$test_num}{LOW_LIMIT} = &compute_limit($testplan{$test_num}{HI_LIMIT}, $SL{$testname}{NEXP});	
		}
		elsif ($testplan{$test_num}{LOW_LIMIT} eq "NONE" && $testplan{$test_num}{HI_LIMIT} =~ /^\-\d+/)
		{
			$error_msg .= ", NEXN\=$SL{$testname}{NEXN}";
			$testplan{$test_num}{LOW_LIMIT} = &compute_limit($testplan{$test_num}{HI_LIMIT}, $SL{$testname}{NEXN});
		}
		elsif ($testplan{$test_num}{LOW_LIMIT} =~ /^\d+/ && $testplan{$test_num}{HI_LIMIT} eq "NONE")
                {
			$error_msg .= ", NPXE\=$SL{$testname}{NPXE}";
                        $testplan{$test_num}{HI_LIMIT} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $SL{$testname}{NPXE});
                }
		elsif ($testplan{$test_num}{LOW_LIMIT} =~ /^\-\d+/ && $testplan{$test_num}{HI_LIMIT} eq "NONE")
                {
			$error_msg .= ", NNXE\=$SL{$testname}{NNXE}";
                        $testplan{$test_num}{HI_LIMIT} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $SL{$testname}{NNXE});
                }
		elsif ($testplan{$test_num}{LOW_LIMIT} eq "NONE" && $testplan{$test_num}{HI_LIMIT} eq "NONE") 
                {      
			$testplan{$test_num}{LOW_LIMIT} = -$FLT_MAX;
			$testplan{$test_num}{HI_LIMIT}  = $FLT_MAX;
		}			
	
		### TRAP EMPTY SPEC LIMIT ###
                if ($testplan{$test_num}{LOW_LIMIT} eq "NONE" || $testplan{$test_num}{HI_LIMIT} eq "NONE")
                {
                        $error_msg .= " - failed to assign a blank spec limit";
                        &send_email($error_msg);
                        print "$error_msg\n";
                        exit 1;
                }

	
		######################
		# ASSIGN VALID LIMITS	
		######################
		if ($testplan{$test_num}{LOW_LIMIT} == -$FLT_MAX && $testplan{$test_num}{HI_LIMIT} == $FLT_MAX)
		{
			$testplan{$test_num}{LOW_VALID} = -$FLT_MAX;
			$testplan{$test_num}{HI_VALID}  = $FLT_MAX;
		}
		elsif ($testplan{$test_num}{LOW_LIMIT} >= 0 && $testplan{$test_num}{HI_LIMIT} >= 0)
		{
			$error_msg .= ", lmul\=VL{$testname}{ANP}\, umul\=$VL{$testname}{AXP}";
			$testplan{$test_num}{LOW_VALID} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $VL{$testname}{ANP});
			$testplan{$test_num}{HI_VALID}  = &compute_limit($testplan{$test_num}{HI_LIMIT},  $VL{$testname}{AXP});
		}
		elsif ($testplan{$test_num}{LOW_LIMIT} < 0 && $testplan{$test_num}{HI_LIMIT} >= 0)        
                {
			$error_msg .= ", lmul\=$VL{$testname}{BNN}\, umul\=$VL{$testname}{BXP}";
                        $testplan{$test_num}{LOW_VALID} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $VL{$testname}{BNN});
                        $testplan{$test_num}{HI_VALID}  = &compute_limit($testplan{$test_num}{HI_LIMIT},  $VL{$testname}{BXP});
                }
		elsif ($testplan{$test_num}{LOW_LIMIT} < 0 && $testplan{$test_num}{HI_LIMIT} < 0)            
                {      
			$error_msg .= ", lmul\=$VL{$testname}{CNN}\, umul\=$VL{$testname}{CXN}";
                        $testplan{$test_num}{LOW_VALID} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $VL{$testname}{CNN});
                        $testplan{$test_num}{HI_VALID}  = &compute_limit($testplan{$test_num}{HI_LIMIT},  $VL{$testname}{CXN});
                }	
		#print "\t new: valid limits: $testplan{$test_num}{LOW_VALID} \; $testplan{$test_num}{HI_VALID} \n";

		##################
		# VALIDATE LIMITS
		##################
		if ($testplan{$test_num}{LOW_VALID} > $testplan{$test_num}{LOW_LIMIT} || $testplan{$test_num}{HI_LIMIT}  > $testplan{$test_num}{HI_VALID})
		{
			$error_msg = "$file. $test_num\) $testname lvl=$testplan{$test_num}{LOW_VALID} lsl=$testplan{$test_num}{LOW_LIMIT} usl=$testplan{$test_num}{HI_LIMIT} uvl=$testplan{$test_num}{HI_VALID} - invalid limits.";
                        &send_email($error_msg);
                        print "$error_msg\n";
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
		$error_msg .= " - invalid limit modifier";
                &send_email($error_msg);
                print "$error_msg\n";
                exit 1;
        }

	return ($result);
}


##############
# ASSIGN SBIN
##############
sub assign_sbin
{
	foreach $testnum(sort {$a<=>$b} keys %testplan)
        {
		$testname = $testplan{$testnum}{TEST_NAME};
		next if $testname eq "";
		#print "$testnum\) $testname";

		#########################
		# DIRECT SBIN ASSIGNMENT
		#########################
		if ($SBIN{$testname} =~ /\d/) 	
		{
			$testplan{$testnum}{SBIN_NUM} = $SBIN{$testname}{NUM};
			$testplan{$testnum}{SBIN_NAM} = $SBIN{$testname}{NAM};
		}
		##########################
		# SPECIAL SBIN ASSIGNMENT 
		##########################
		else
		{
			if ($testname eq "HFB")
                        {
                                if ($testnum == 2)
                                {
                                        $testplan{$testnum}{SBIN_NUM} = 5;
                                        $testplan{$testnum}{SBIN_NAM} = "PRE O/S";
                                }
				elsif ($testnum > 2 && $testplan{$testnum}{FLAG} eq "")
                                {
                                        $testplan{$testnum}{SBIN_NUM} = 7;
                                        $testplan{$testnum}{SBIN_NAM} = "HFE1";
                                }
                                elsif ($testplan{$testnum}{FLAG} eq "L" || $testplan{$testnum}{FLAG} eq "2L")
                                {
                                        $testplan{$testnum}{SBIN_NUM} = 13;
                                        $testplan{$testnum}{SBIN_NAM} = "POST O/S";
                                }
                        }
			elsif ($testname eq "IGSS")
                        {
                                ### DEFAULT VALUE ###
                                $testplan{$testnum}{SBIN_NUM} = 7;
                                $testplan{$testnum}{SBIN_NAM} = "IGSSR";

                                if ($testnum == 2)
                                {
                                        $testplan{$testnum}{SBIN_NUM} = 9;
                                        $testplan{$testnum}{SBIN_NAM} = "GSHRT";
                                }
				elsif ($testplan{$testnum}{FLAG} eq "L")
				{
					$testplan{$testnum}{SBIN_NUM} = 10;
                                        $testplan{$testnum}{SBIN_NAM} = "POST O/S";
				}
                                elsif ($testplan{$testnum}{BIAS1} eq "RESULT=(T2)")
                                {
                                        $testplan{$testnum}{SBIN_NUM} = 7;
                                        $testplan{$testnum}{SBIN_NAM} = "IGSSR";
                                }
                                elsif ($testnum > 2 && $testplan{$testnum}{BIAS1} =~ /VGS/i)
                                {
                                        ### GET TEST#2 BIAS#1 VALUE ###
                                        $tp = $testplan{2}{BIAS1};
                                        $tp =~ s/VGS\=|\D$//g;

                                        ### GET CURRENT TEST BIAS#1 VALUE ###
                                        $tc = $testplan{$testnum}{BIAS1};
                                        $tc =~ s/VGS\=|\D$//g;

                                        if ($tc == $tp)
                                        {
                                                $testplan{$testnum}{SBIN_NUM} = 7;
                                                $testplan{$testnum}{SBIN_NAM} = "IGSSR";
                                        }
                                        elsif ($tc == abs($tp) && $tp < 0)
                                        {
                                                $testplan{$testnum}{SBIN_NUM} = 5;
                                                $testplan{$testnum}{SBIN_NAM} = "IGSS";
                                        }
                                        elsif (abs($tc) > abs($tp))
                                        {
                                                $testplan{$testnum}{SBIN_NUM} = 13;
                                                $testplan{$testnum}{SBIN_NAM} = "GSTRS";
                                        }
				
					### SPECIAL COND: UPDATE ALT SBIN ##
					if ($testnum == $datalog[0] && abs($tc) > abs($tp))
					{
						$testplan{$prev_testnum}{SBIN_NUM} = 9;
                                                $testplan{$prev_testnum}{SBIN_NAM} = "GSHRT";
					}	
                                }
                        }
			elsif ($testname eq "VBCF")
                        {
                                ### DEFAULT VALUE ###
                                $testplan{$testnum}{SBIN_NUM} = 15;
                                $testplan{$testnum}{SBIN_NAM} = "VBE";

                                if ($testnum == 2)
                                {
                                        $testplan{$testnum}{SBIN_NUM} = 9;
                                        $testplan{$testnum}{SBIN_NAM} = "PRE O/S";
                                }
                                elsif ($testplan{$testnum}{FLAG} eq "L")
                                {
                                        $testplan{$testnum}{SBIN_NUM} = 14;
                                        $testplan{$testnum}{SBIN_NAM} = "POST O/S";
                                }
                        }
			elsif ($testname eq "VGSF")
			{
				if ($testnum == 1)
				{
					$testplan{$testnum}{SBIN_NUM} = 9;	
					$testplan{$testnum}{SBIN_NAM} = "PRE O/S";

				}
				else
				{
					$testplan{$testnum}{SBIN_NUM} = 14;
					$testplan{$testnum}{SBIN_NAM} = "POST O/S";
				}
			}
		}
		#print "-- \t num=$testplan{$testnum}{SBIN_NUM} \, name=$testplan{$testnum}{SBIN_NAM}\n";


		#######################
		# GET PREV TEST NUMBER
		#######################
		$prev_testnum = $testnum;


		###############################
		# ERROR IF NO SBIN NUM OR NAME
		###############################
		if ($testplan{$testnum}{SBIN_NUM} eq "" || $testplan{$testnum}{SBIN_NAM} eq "")
		{
			$error_msg = "$filename\: $testnum\) $testname - no assigned bin no and/or name";
                	&send_email($error_msg);
                	print "$error_msg\n";
                	exit 1;
		}

		#####################
		# EXIT ON LAST PARAM
		#####################
		last if $testplan{$testnum}{FLAG} eq "L";
        }
}



###############################################
# SPECIAL SBIN ASSIGNMENT ON DUAL TEST PROGRAM
###############################################
sub assign_sbin_if_duals
{
	my $i = 0;			#<-- POINTS TO THE 1ST PARAM OF 1ST PARAM SET 
	my $j = ($#testplan+1)/2;	#<-- POINTS TO THE 1ST PARAM OF 2ND PARAM SET
	for($j..$#testplan)
	{
		#print "updating $_ w/ $i\n";
		$testnum_orig = $testplan[$i];
		$testnum_clon = $testplan[$_];
		$testplan{$testnum_clon}{SBIN_NUM} = $testplan{$testnum_orig}{SBIN_NUM};
		$testplan{$testnum_clon}{SBIN_NAM} = $testplan{$testnum_orig}{SBIN_NAM};
	
		$i = $i + 1;
	}
}



##################
# ASSIGN ALT SBIN
##################
sub assign_alt_sbin
{
        my $prev_param  = "";
	my $curr_param  = "";
	my $prev_dl_testnum = 0;

        foreach $testnum(sort {$a<=>$b} keys %testplan)
        {

		#print "altbin = $testnum \n";
		if ($testplan{$testnum}{DATALOG} eq "YES")
		{
			$testnum_diff = $testnum - $prev_dl_testnum;
			$testname     = $testplan{$testnum}{TEST_NAME};

                	#
                	# GET SBIN NUM & NAME OF PREV DATALOG PARAM ONLY IF THE DL TESTNUM DIFF IS > 1
                	#
                	if ($testnum_diff > 1)
                	{
				$testplan{$prev_testnum}{DATALOG}   = "YES";
                        	$testplan{$prev_testnum}{TEST_NAME} = "ALT_".$testplan{$prev_testnum}{TEST_NAME};
                	}
			
			### GET PREV DL TESTNUM ###
			$prev_dl_testnum = $testnum;
		}

		### GET PREV TEST PARAM NUMBER ### 
		$prev_testnum = $testnum;

		### STOP ON LAST PARAM ###
		last if $testplan{$testnum}{FLAG} eq "L";
        }
}



#######################
# CREATE STDF TESTPLAN
#######################
sub create_tp
{
	 my $testplan_name       = uc(substr($file, rindex($file,"/") + 1));
        ($testplan_name,$dummy) = split /\./, $testplan_name;
        #my ($testplan_name,) = split /\./, $file; 
	#$testplan_name       = uc $testplan_name;
        my $DateTime         = `date '+%m%d%y%H%M%S'`;
        chomp($DateTime);
	#$tp_name = $testplan_name."_".$DateTime."_CPFETQUAD_TP.STDF";
        #open FH, ">$ENV{ENV_CONV_GOOD}/$tp_name" or die "error msg: $!";
	$tp_filename = "${file}.TP";
        open FH, ">$tp_filename" or die "error msg: $!";

        #############
        # MIR RECORD
        #############
        %out::emir              = %{$out::init{emir}};
        $out::emir{mode_cod}    = "C";
        $out::emir{setup_t}     = stdf_time();
        $out::emir{job_nam}     = $testplan_name;
        $out::emir{job_rev}     = 0;
	$out::emir{spec_nam}    = substr($testplan_name, 0, 20);
        $out::emir{spec_rev}    = 0;
        print FH &out::pack_EMIR(\%out::emir);

        ##############
        # EPDR RECORD
        ##############
	$testnum = 1;

	### LOAD PRIMARY SBIN FIRST ###
        foreach (sort {$a<=>$b} keys %testplan)
        {
		### CHECK FOR TESTNAME
                next if $testplan{$_}{DATALOG} ne "YES";
	
		### PROCESS PRIMARY SBIN FIRST ###
		next if $testplan{$_}{TEST_NAME} =~ /^ALT\_/i;

		### CONCATENATE BIAS INFO TO TESTNAME ###
		my $test_name = $testplan{$_}{TEST_NAME};
		$test_name    .= "_".$testplan{$_}{BIAS1} if $testplan{$_}{BIAS1} ne "";
		$test_name    .= "_".$testplan{$_}{BIAS2} if $testplan{$_}{BIAS2} ne "";

                %out::epdr           = %{$out::init{epdr}};
                $out::epdr{test_num} = $testnum++;
                $out::epdr{units}    = $testplan{$_}{UNIT};
                $out::epdr{lo_limit} = $testplan{$_}{LOW_LIMIT};
                $out::epdr{hi_limit} = $testplan{$_}{HI_LIMIT};
		$out::epdr{lo_censr} = $testplan{$_}{LOW_VALID};
                $out::epdr{hi_censr} = $testplan{$_}{HI_VALID};
                $out::epdr{test_nam} = $test_name;
                $out::epdr{test_txt} = $test_name;
                $out::epdr{sbin_num} = $testplan{$_}{SBIN_NUM};
                $out::epdr{sbin_nam} = $testplan{$_}{SBIN_NAM};
                $out::epdr{opt_flg}  = "00000000";
                print FH &out::pack_EPDR(\%out::epdr);
	}

	### LOAD ALT SBIN HERE ###
        foreach (sort {$a<=>$b} keys %testplan)
        {
                ### CHECK FOR TESTNAME
                next if $testplan{$_}{DATALOG} ne "YES";
        
                ### PROCESS PRIMARY SBIN FIRST ###
                next if $testplan{$_}{TEST_NAME} !~ /^ALT\_/i;

		### CONCATENATE BIAS INFO TO TESTNAME ###
                my $test_name = $testplan{$_}{TEST_NAME};
                $test_name    .= "_".$testplan{$_}{BIAS1} if $testplan{$_}{BIAS1} ne "";
                $test_name    .= "_".$testplan{$_}{BIAS2} if $testplan{$_}{BIAS2} ne "";

                %out::epdr           = %{$out::init{epdr}};
                $out::epdr{test_num} = $testnum++;
                $out::epdr{units}    = $testplan{$_}{UNIT};
                $out::epdr{lo_limit} = $testplan{$_}{LOW_LIMIT};
                $out::epdr{hi_limit} = $testplan{$_}{HI_LIMIT};
                $out::epdr{lo_censr} = $testplan{$_}{LOW_VALID};
                $out::epdr{hi_censr} = $testplan{$_}{HI_VALID};
                $out::epdr{test_nam} = $test_name;
                $out::epdr{test_txt} = $test_name;
                $out::epdr{sbin_num} = $testplan{$_}{SBIN_NUM};
                $out::epdr{sbin_nam} = $testplan{$_}{SBIN_NAM};
                $out::epdr{opt_flg}  = "00000000";
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


############################################
# GENERATE TPL FILE FOR CPFETQUAD CONVERTER
############################################
sub generate_tpl()
{
	my $testplan_name       = uc(substr($file, rindex($file,"/") + 1));
        ($testplan_name,$dummy) = split /\./, $testplan_name;
	open FH, ">$ENV{DPDATA}/data/cpsort_fet_quad/TP/${testplan_name}.TPL" or die "error msg: $!";
        #open FH, ">$ENV{ENV_TP_RAW}/${testplan_name}.TPL" or die "error msg: $!";
        #open FH, ">/data/edbcp/cpsort_fet_quad/convert/tp_raw/${testplan_name}.TPL" or die "error msg: $!";
	#open FH, ">${testplan_name}.TPL" or die "error msg: $!";


	##############
        # EPDR RECORD
        ##############
	my $i        = 1;
	my $alt_sbin = "";
        foreach (sort {$a<=>$b} keys %testplan)
        {
                ### CHECK FOR TESTNAME
                next if $testplan{$_}{DATALOG} ne "YES";
		if ($testplan{$_}{TEST_NAME} =~ /ALT\_/)
		{
			$alt_sbin = $testplan{$_}{SBIN_NUM};
			next;
		}

		### LIMIT PARAM NAME + BIAS INFO TO 20 CHARS SO CPFETQUAD CONVERTER WON'T FAIL ###	
		my $param_desc = "T".$_."_".$testplan{$_}{TEST_NAME};
		$param_desc   .= " ".$testplan{$_}{BIAS1} if $testplan{$_}{BIAS1} ne "";
                $param_desc   .= " ".$testplan{$_}{BIAS2} if $testplan{$_}{BIAS2} ne "";
                $param_desc    = substr $param_desc, 0, 19;

		my $testnum = sprintf ("%-4d", $i++);
		my $lsl     = sprintf ("%-.2e", $testplan{$_}{LOW_LIMIT});
		my $usl     = sprintf ("%-.2e", $testplan{$_}{HI_LIMIT});
		my $desc    = sprintf ("%-19s", $param_desc);
		my $lvl     = sprintf ("%-.2e", $testplan{$_}{LOW_VALID});
		my $uvl     = sprintf ("%-.2e", $testplan{$_}{HI_VALID});
		my $unit    = sprintf ("%-5s",  $testplan{$_}{UNIT});
		print FH "$testnum ,$lsl ,$usl ,$desc ,$testplan{$_}{SBIN_NUM} ,$alt_sbin , , ,$lvl ,$uvl , $unit\n";

		### RESET AFTER USE ###
		$alt_sbin = "";
        }
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
	elsif ($Unit =~ /F\b/)
        {
                if ($Unit =~ /\bPF\b/)
                {
                        $mew = 1e-12;
                }
                elsif ($Unit =~ /\bNF\b/)
                {
                        $mew = 1e-9;
                }
                elsif ($Unit =~ /\bUF\b/)
                {
                        $mew = 1e-6;
                }
                elsif ($Unit =~ /\bMF\b/)
                {
                        $mew = 1e-3;
                }
                elsif ($Unit =~ /\bF/)
                {
                        $mew = 1;
                }
                elsif ($Unit =~ /\bKF/)
                {
                        $mew = 1e3;
                }
                $Unit = "F";
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
                $error_msg = "undefined unit: $Unit. Affected file: $file.";
                &send_email($error_msg);
                print "$error_msg\n";
                exit 1;
        }


        if ($mew != 0)
        {
                $Limit = $Limit * $mew;
        }

        return ($Unit, $Limit);
}

#####################
# EMAIL NOTIFICATION
#####################
sub send_email
{
	my $tp_file   = substr($file,rindex($file,"/") + 1);
        my $error_msg = shift;
	   $error_msg =~ s/$file/$tp_file/;
        my $msg       = MIME::Lite->new
        (
                Subject => "$subject Test Plan: $file rev 0 Failed to convert",
                From    => 'dpower@onsemi.com' ,
                To      =>  $email_list,
                Type    => 'text/plain',
                Data    =>  $error_msg
        );
        $msg->send();

}
