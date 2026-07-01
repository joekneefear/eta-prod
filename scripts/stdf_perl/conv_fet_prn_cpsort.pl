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
# 02-09-2007  Ben Rommel Kho  Corrected SBin Parsing and remove HBin.
# 03-07-2007  Ben Rommel Kho  Append Bias Info into testname but exclude "VGS= 0.0000V" & "V4S= OPEN" 
# 03-29-2007  Ben Rommel Kho  Corrected SBIN Parsing and trap param w/o bin assignment.
#			      Parse COP & COF to determine BIN assignment as well.
# 04-05-2007  Ben Rommel Kho  Fixed bin asssignement on params w/ successive COP & COF
# 08-08-2007  Ben Rommel Kho  Remove trailing zeroes from the bias info.
# 09-12-2007  Ben Rommel Kho  Remove spaces from parameter name. Allow param/s w/o bin# on *T.PRN testplans.
# 10-02-2007  Ben Rommel Kho  Remove " and ' from bias info.
# 10-09-2007  Ben Rommel Kho  Fixed bug that remove spaces in parameter name 
# 10-28-2008  Ben Rommel Kho  Fixed test limits and unit parsing.
# 01/30/2009  Ben Rommel Kho  Allow FX Tests not to have sbin assignment
# 06/17/2010  Gilbert Miole   Exclude invalid test parameters i.e. #81 and up
# 04/11/2011  Gilbert Miole   Adopted .TD & .TP STDF filenaming convention.
# 06/18/2012  Gilbert Miole   Made MFT Compatible
# 08/31/2012  Rodney Cyr      Changed negative exit codes to positive (negative exit codes are not valid in unix).
# 05/12/2014  Gilbert Miole   Enable back the notification email when failed during conversion.
# 05/15/2014  Gilbert Miole   Removed the file path in the error message.
# 05/20/2014  Gilbert Miole   Added subject with word sort as indicator for sort area.
# 06/06/2019  Eric Alfanta    Change email add domain to onsemi
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
my $subject             = "CPSORT_FET PRN CONVERTER";
my %testplan            = ();
my %good_bins           = ();
my $site_flag           = "";  
my $bad_bin_count_flag  = 0;
my $tp_filename		= "";
#my $limit_ref_file      = "$ENV{ENV_CONV_SCRIPT}/fet_limit_ref.txt";
my $limit_ref_file      ="$ENV{DPDATA}/data/cpsort_fet/TP/fet_limit_ref.txt";
my %VL 			= ();
my %SL 			= ();
my $error_msg		= "";
our $file 		= "";
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


&pre_parse_module()    if $env_mod ne "";

###########################
# DETECT IF SINGLE OR QUAD 
###########################
my($filename,) = split /\./, $file;
$len           = (length $filename)-1;
$site_flag     = uc(substr $filename, $len, 1);     ### if 'Q' means quad



	#############################
	# Trappings:
	# DEL QUAD FILES TO $FTP_IN
	#############################
	if ($site_flag =~ /[D|E|F|K]/i)
	{
		system "/bin/rm -f $file";
		$error_msg = "$file - CPFETQUAD PRN found in CPFET env. File was deleted.";
		print "$error_msg\n";
		&send_email($error_msg);
		exit 1;
	}
	elsif ($site_flag =~ /C/i)
	{
		system "/bin/rm -f $file";
                $error_msg = "$file - CPFETCORR PRN found in CPFET env. File was deleted.";
                print "$error_msg\n";
                &send_email($error_msg);
                exit 1;
        }



###################################
# LOAD LIMIT REF TABLE INTO A HASH
###################################
&loading_limit_ref_table_into_a_hash();



############
# PARSE PRN 
############
&parse_prn();
&cop_binning();

	#############
	# TRAPPINGS: 
	#############
	### EXIT ON SINGLE SITE PRN W/ NO BIN RECORDS ###
	if ($bad_bin_count_flag == 0)
	{
		system "/bin/rm -f $file";
                $error_msg = "$file - does not contain bin info. File was deleted.";
                print "$error_msg\n";
                &send_email($error_msg);
                exit 1;
	}
	### ALL PARAMS MUST HAVE AN ASSIGNED BIN_NO ###
        foreach (sort {$a<=>$b} keys %testplan)
        {
                if ($testplan{$_}{SBIN_NUM} eq "" && $file !~ /T\.PRN$/i && $testplan{$_}{BIAS1} !~ /RESULT/i)
		{
                        $error_msg .= "$file - no sbin assignment for param $_. please check.";
                        &send_email($error_msg);
                        print "$error_msg\n";
                        exit 1;
                }
        }



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
print "$tp_filename"          if $mft_flag==0;
print "\ntp=$tp_filename"     if $mft_flag==1;


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
               print "$testplan{$_}{DATALOG}\t$testplan{$_}{FLAG}\t";
	       print "$testplan{$_}{UNIT}\n";
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
		#print "$tmp[0]\, $SL{$tmp[0]}{NEXP}\,  $SL{$tmp[0]}{NNXE}\,  $SL{$tmp[0]}{NEXN}\,  $SL{$tmp[0]}{NPXE}\n";
	}
	close(FH);
}


####################
# PARSE PRN ROUTINE
####################
sub parse_prn
{
        my $testname_flag = 0;


	open FH, $file or die "error msg: can't open $file. $!\n";
	#open FH, "$file" or die "error msg: can't open $file. $!\n";

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
                elsif ($_=~/DO ALL/ && $site_flag ne "Q")
                {
                        ### TOGGLE OFF $testname_flag
                        $testname_flag = 0;
                        #====================================================================================
                        #          1         2         3         4         5         6         7         8      
                        #012345678901234567890123456789012345678901234567890123456789012345678901234567890      
                        #12 POST O/S       BIN=17R   DO ALL?=NO  (OR)  TESTS:   14F 15F 16F     
                        #====================================================================================
                        $sbin_name= substr $_, 3,15;
                        $sbin_num = substr $_,22, 4;
                        $test_nums= substr $_,52;
                        
                        $sbin_name=~ s/\s+$//;
			$sbin_name=~ s/ /\_/g;
                        $sbin_num =~ s/\s+//g;
                        @test_nums = split /\s+/, $test_nums;
                        

                        ### COLLECT REJECT SBINS 
                        if ($sbin_num=~/\b\d{1,2}R\b/)
                        {
                                foreach (@test_nums)
                                {
					next unless $_ =~ /\d{1,2}F/;
                                        $_        =~ s/F//;
                                        $sbin_num =~ s/R//;

                                        if($_ ne "")
                                        {
                                                $testplan{$_}{SBIN_NUM} = $sbin_num;
                                                $testplan{$_}{SBIN_NAM} = $sbin_name;
						$bad_bin_count_flag = 1;
                                        }
                                }
                        }
                        ### COLLECT GOOD SBINS
                        elsif ($sbin_num=~/\b\d{1,2}\b/)
                        {
                                $good_bins{$sbin_num} =
                                {
                                        SBIN_NUM => $sbin_num,
                                        SBIN_NAM => $sbin_name,
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
			$low_limit   = substr $_,59,10;
			$low_limit   =~ s/ //g;
			$low_limit   =~ /([A-Z]+)$/;
			$low_unit    = $1;
			$low_limit   =~ s/$low_unit//i;
			#print "low: $low_limit\t$low_unit\t\t";

			$hi_limit    = substr $_,69,10;
			$hi_limit    =~ s/ //g;
			$hi_limit    =~ /([A-Z]{1,})$/i;	
			$hi_unit     = $1;
			$hi_limit    =~ s/$hi_unit//i;	
			#print "hi: $hi_limit\t$hi_unit\n";
			
                        $limit_type = substr $_,79, 1;
			$cop        = substr $_,86, 3;
			$cof        = substr $_,90, 3;
                        
                        $test_num   =~ s/\s+//g;
                        $test_name  =~ s/\s+|\^//g;
                        $test_bias1 =~ s/\s+//g;
                        $test_bias2 =~ s/\s+//g;
                        $test_bias3 =~ s/\s+//g;
                        $low_limit  =~ s/\s+//g;
                        $low_unit   =~ s/\s+//g;
                        $hi_limit   =~ s/\s+//g;
                        $hi_unit    =~ s/\s+//g;
			$cop	    =~ s/\s+//g;
			$cof        =~ s/\s+//g;

			### APPEND BIAS INFO TO TESTNAME ###
			$test_bias1 = &clean_bias_info($test_bias1);
			$test_bias2 = &clean_bias_info($test_bias2);
			$test_bias3 = &clean_bias_info($test_bias3);

                        ### CHECK FOR A VALID TEST SEQ NUMBER & LIMIT TYPE
                        if ($test_num > 0 && $test_num < 81 && $test_name ne "" && $limit_type=~/[A|S]/)      
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
					COP       => $cop||$cof,
                                };
                        }
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

#####################################
# USE COP BIN TO PARAM W/O BIN NO
####################################
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


###################################################
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
		$error_msg="$file. $test_num) $testname\, lsl\=$testplan{$test_num}{LOW_LIMIT}\, usl\=$testplan{$test_num}{HI_LIMIT}";	


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
		elsif ($testplan{$test_num}{LOW_LIMIT} =~ /^\d+/ && $testplan{$test_num}{HI_LIMIT} eq "NONE" && exists $SL{$testname}{NPXE})
                {
			$error_msg .= ", NPXE\=$SL{$testname}{NPXE}";
                        $testplan{$test_num}{HI_LIMIT} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $SL{$testname}{NPXE});
                }
		elsif ($testplan{$test_num}{LOW_LIMIT} =~ /^\-\d+/ && $testplan{$test_num}{HI_LIMIT} eq "NONE" && exists $SL{$testname}{NNXE})
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
			$error_msg = $error_msg.", lmul\=VL{$testname}{ANP}\, umul\=$VL{$testname}{AXP}";
			$testplan{$test_num}{LOW_VALID} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $VL{$testname}{ANP});
			$testplan{$test_num}{HI_VALID}  = &compute_limit($testplan{$test_num}{HI_LIMIT},  $VL{$testname}{AXP});
		}
		elsif ($testplan{$test_num}{LOW_LIMIT} < 0 && $testplan{$test_num}{HI_LIMIT} >= 0)        
                {
			$error_msg = $error_msg.", lmul\=$VL{$testname}{BNN}\, umul\=$VL{$testname}{BXP}";
                        $testplan{$test_num}{LOW_VALID} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $VL{$testname}{BNN});
                        $testplan{$test_num}{HI_VALID}  = &compute_limit($testplan{$test_num}{HI_LIMIT},  $VL{$testname}{BXP});
                }
		elsif ($testplan{$test_num}{LOW_LIMIT} < 0 && $testplan{$test_num}{HI_LIMIT} < 0)            
                {      
			$error_msg = $error_msg.", lmul\=$VL{$testname}{CNN}\, umul\=$VL{$testname}{CXN}";
                        $testplan{$test_num}{LOW_VALID} = &compute_limit($testplan{$test_num}{LOW_LIMIT}, $VL{$testname}{CNN});
                        $testplan{$test_num}{HI_VALID}  = &compute_limit($testplan{$test_num}{HI_LIMIT},  $VL{$testname}{CXN});
                }	

		##################
		# VALIDATE LIMITS
		##################
		if ($testplan{$test_num}{LOW_VALID}>$testplan{$test_num}{LOW_LIMIT} || $testplan{$test_num}{HI_LIMIT}>$testplan{$test_num}{HI_VALID})
		{
			$error_msg  = "$file. $test_num\) $testname lvl=$testplan{$test_num}{LOW_VALID} lsl=$testplan{$test_num}{LOW_LIMIT} "; 
		        $error_msg .= "usl=$testplan{$test_num}{HI_LIMIT} uvl=$testplan{$test_num}{HI_VALID} - invalid limits.";
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



#######################
# CREATE STDF TESTPLAN
#######################
sub create_tp
{
	$tp_name             = uc(substr($file, rindex($file,"/") + 1));
        my ($testplan_name,) = split /\./, $tp_name; 
        my $DateTime         = `date '+%m%d%y%H%M%S'`;
        chomp($DateTime);
	#$tp_name = $testplan_name."_".$DateTime."_CPFET_TP.STDF";
	$tp_filename = "${file}.TP";
        open FH, ">$tp_filename" or die "error msg: $!";
	#open FH, ">$tp_name" or die "error msg: $!";

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
        ### 1) TESTS & REJECT BINS
        foreach (sort {$a<=>$b} keys %testplan)
        {
		### CHECK FOR TESTNAME
                next if $testplan{$_}{TEST_NAME} eq "";

		### CONCATENATE BIAS INFO TO TESTNAME ###
		my $test_name = $testplan{$_}{TEST_NAME};
                $test_name    .= "_".$testplan{$_}{BIAS1} if $testplan{$_}{BIAS1} ne "";
                $test_name    .= "_".$testplan{$_}{BIAS2} if $testplan{$_}{BIAS2} ne "";

                %out::epdr           = %{$out::init{epdr}};
                $out::epdr{test_num} = $_;
                $out::epdr{units}    = $testplan{$_}{UNIT};
                $out::epdr{lo_limit} = $testplan{$_}{LOW_LIMIT};
                $out::epdr{hi_limit} = $testplan{$_}{HI_LIMIT};
		$out::epdr{lo_censr} = $testplan{$_}{LOW_VALID};
                $out::epdr{hi_censr} = $testplan{$_}{HI_VALID};
                $out::epdr{test_nam} = $test_name;
                $out::epdr{test_txt} = $test_name;
                $out::epdr{sbin_num} = $testplan{$_}{SBIN_NUM} if $testplan{$_}{SBIN_NUM} ne "";
                $out::epdr{sbin_nam} = $testplan{$_}{SBIN_NAM} if $testplan{$_}{SBIN_NAM} ne "";
                $out::epdr{opt_flg}  = "00000000";
                print FH &out::pack_EPDR(\%out::epdr);
        }

        ### 2) GOOD BIN/S FOR SINGLE SITE       
        foreach (sort {$a<=>$b} keys %good_bins)
        {
                %out::epdr           = %{$out::init{epdr}};
                $out::epdr{test_num} = (1000 + $_);
                $out::epdr{test_nam} = $good_bins{$_}{SBIN_NAM};
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

#######################
# EMAIL NOTIFICATION
#######################
sub send_email
{
	my $tp_file   = substr($file,rindex($file,"/") + 1);
	my $error_msg = shift;
	   $error_msg =~ s/$file/$tp_file/;
        my $msg       = MIME::Lite->new
        (
                Subject => "$subject Test Plan: $tp_file rev 0 Failed to convert",
                From    => 'dpower@onsemi.com' ,
                To      =>  $email_list,
                Type    => 'text/plain',
                Data    =>  $error_msg
        );
        $msg->send();

}
