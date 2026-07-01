#!/usr/bin/perl
#
# MODIFICATION HISTORY:
#
# DATE       WHO	    COMMENTS 
# ---------- -------------- ---------------------------------------------------
# 05/15/2001 David Fletcher Author
# 03/08/2007 Ben Rommel Kho Modified to remove incomplete(terminated) datalogs
# 11/19/2007 Robert Tukey   Modified to handle incomplete datalogs & invalid
#                           wafer IDs
# 04/13/2011 Gilbert Miole  Adopted .TD & .TP STDF filenaming convention.
# 06/07/2012 Gilbert Miole  Made MFT compatible
# 08/31/2012 Rodney Cyr     Changed negative exit codes to positive values (neg exit codes are not valid in unix).
#

use Carp 			; # error messages - does not work within stdf_use.pl
use FindBin 			;
use English 			;
use lib "$FindBin::Bin" 	; # set up path for libraries the same as script
use lib $ENV{'STDF_PERL_LIB'} 	; # look for libraries in this directory
require "stdf_use.pl" 		; # libraries that are not generated
use Getopt::Long              	;
#use EDBUtil                   	;


#####################
# Load Specifications
#####################
{
        package out ;
        if ( !eval(&::generate_all('stdfPL.spec')))
        { 
                confess $@ ; 
        }
        require 'stdfPL.pl' ;
}

use PrintRecords	; # Functions for printing records.
use read_stdfV3		; # Functions for reading in STDF V3 records
use v3_stdf		; # Functions to write out STDF+ records

#################
#GLOBAL VARIABLES
#################
$rec_len = 0;
%Hash = ();
%MIR=();
%MRR=();
%WCR=();
%WIR=();
%PDR=();
%PIR=();
%SSB=();
%SHB=();
%STS=();
our $file         = "";
my $td_filename   = "";                         #<-- USE VARIABLE TO STORE TEST DATA FILENAME
my $plant         = uc($ENV{ENV_FACILITY});     #<-- MFT ENV VAR
my $mft_flag      = ($^O=~/linux/i) ? 1 : 0;    #<-- SET 0=OTHERS; 1=LINUX
my ($dump, $envname, $dump) = split /\_/, uc($ENV{ENV_NAME});           #<-- GET ENV NAME


######################
# RETRIEVE PARAMETERS
######################
$result = GetOptions ("infile=s"   => \$file,
                      "plant=s"    => \$plant,
                      "env_mod=s"  => \$env_mod);
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


open(EP, $file);

$done = "NO";
$WIR_DATA = "NO";
$Current_Wafer_ID = -1;
$Current_Part_ID  = -1;
$Current_Test_ID  = -1;
$WSBRCnt = 0;
$WHBRCnt = 0;
$HBRCnt  = 0;
$SBRCnt  = 0;
$PRES_CNT= 0;
$STS_RECORD_COUNT = 0;
$SHB_COUNT = 0;
$SSB_COUNT = 0;

while ($done eq "NO")
{
	#################### REC LENGTH #######################
	$rec_len = 0;
	read EP, $in, 2;
        $rec_len = unpack ("n", $in);
	################### REC TYPE ##########################
	$rec_typ = 0;
	read EP, $in, 1;
	$rec_typ = unpack("C", $in);

	if ($rec_typ == "")
	{
		print "\ndir=bad_file_format";                 ### RETURN BAD SUBDIR FOR MFT
                &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/bad_file_format") if $mft_flg==0;
                exit 100;
	}

	################### REC SUB ###########################
	$rec_sub = 0;
	read EP, $in, 1;
	$rec_sub = unpack("C", $in);

	if ($rec_typ == 0)
	{
    		if ($rec_sub == 10)
		{
        		convert_FAR();
    		}
	}
	elsif ($rec_typ == 1)
	{
   		if ($rec_sub == 10)
		{
			%MIR = convert_MIR();
			#PrintMIR(\%MIR);
   		}
   		elsif ($rec_sub == 20)
		{
       			convert_MRR();
			$done = "YES";
   		}
   		elsif ($rec_sub == 40)
		{
       			convert_HBR();
   		}
   		elsif ($rec_sub == 50)
		{
       			convert_SBR();
   		}
   		elsif ($rec_sub == 60)
		{
       			convert_PMR();
   		}
	} 
	elsif ($rec_typ == 2)
	{
   		if ($rec_sub == 10)
		{
       			($Current_Wafer_ID) =  convert_WIR();
			$WIR_DATA = "YES";
   		}
   		elsif ($rec_sub == 20)
		{
       			convert_WRR();
   		}
   		elsif ($rec_sub == 30)
		{
       			%WCR = convert_WCR();
			#PrintWCR(\%WCR);
   		}
	} 
	elsif ($rec_typ == 5)
	{
   		if ($rec_sub == 10)
		{
       			($Current_part_id) = convert_PIR();
			#print "Current PartID: $Current_part_id\n";
   		}
   		elsif ($rec_sub == 20)
		{
                	convert_PRR();
   		}
	} 
	elsif ($rec_typ == 10)
	{
   		if ($rec_sub == 10)
		{
      			convert_PDR();
   		}
   		elsif ($rec_sub == 20)
		{
       			convert_FDR();
   		}
   		elsif ($rec_sub == 30)
		{
      			convert_TSR();
   		}
	} 
	elsif ($rec_typ == 15)
	{
   		if ($rec_sub == 10)
		{
			($test_num,
                	$head_num,
                	$site_num,
                	$test_flg,
                	$parm_flg,
                	$result,
                	$opt_flg,
                	$res_scal,
                	$res_ldig,
                	$res_rdig,
                	$desc_flg,
                	$units,
                	$llm_scal,
                	$hlm_scal,
                	$llm_ldig,
                	$llm_rdig,
                	$hlm_ldig,
                	$hlm_rdig,
                	$lo_limit,
                	$hi_limit,
                	$test_nam,
                	$seq_name,
                	$test_txt) = convert_PTR();

			#
			# Check to see if bit 2 is set to 1
			# If it is, don't load the data.
			#
			$bit2 = substr($test_flg, 5, 1);
			#print "TEST_FLG=$test_flg, BIT2=$bit2\n";
			if ($bit2 ne "1")
			{
				#
				# Don't load the data
				#

				$Data = "";
				$Data = "$Current_Wafer_ID,"."$Current_part_id,".
					"$test_num,$head_num,$site_num,$test_flg,$parm_flg,$result,$opt_flg,$res_scal,$res_ldig,".
					"$res_rdig,$desc_flg,$units,$llm_scal,$hlm_scal,$llm_ldig,$llm_rdig,$hlm_ldig,$hlm_rdig,".
					"$lo_limit,$hi_limit,$test_nam,$seq_name,$test_txt";

				#print "WID, PartID, TestNUM, HeadNUM, SiteNUM, TestFLG, ParmFlg, Result\n".$Data."\n";
				#print $Data."\n";
				push (@DLArray, $Data);
			}
   		}
   		elsif ($rec_sub == 20)
		{
       			convert_FTR();
   		}
	} 
	elsif ($rec_typ == 20)
	{
   		if ($rec_sub == 10)
		{
       			convert_BPS();
   		}
   		elsif ($rec_sub == 20)
		{
       			convert_EPS();
   		}
	} 
	elsif ($rec_typ == 25)
	{
   		if ($rec_sub == 10)
		{
       			convert_SHB();
			$SHB_COUNT++;
   		}
   		elsif ($rec_sub == 20)
		{
       			convert_SSB();
			$SSB_COUNT++;
   		}
   		elsif ($rec_sub == 30)
		{
			convert_STS();
       			$STS_RECORD_COUNT++; 
   		}
   		elsif ($rec_sub == 40)
		{
       			#convert_SCR();
   		}
	} 
	elsif ($rec_typ == 50)
	{
   		if ($rec_sub == 10)
		{
       			convert_GDR();
   		}
   		elsif ($rec_sub == 30)
		{
       			convert_DTR();
   		}
	} 
	elsif ($rec_typ == 100)
	{
   		#Histogram_Data();
	}
	elsif ($rec_typ == 105)
	{
   		#Wafer_Map_Data();
	}
	elsif ($rec_typ == 110)
	{
   		#Correlation_Data();
	}
	elsif ($rec_typ == 115)
	{
   		#Bit_Map_Data();
	}
	elsif ($rec_typ == 120)
	{
   		#Shmoo_Plot_Data();
	}
	elsif ($rec_typ == 125)
	{
   		#Trend_Data();
	}
	elsif ($rec_typ == 180)
	{
   		#Reversed_ByA500();
	}
}
close(EP);

#PrintSTS(\%STS);
#PrintPDR(\%PDR);
#PrintPIR(\%PIR);


#########################################################################################################################
# Start the STDF+ file generation here
#########################################
$Pos = rindex ($file, "/");
$FName = substr($file, $Pos+1, length($file));
($FN, $Ex) = split (/\./, $FName);
($LotIDFromFile, $TimeFromFile, $DateFromFile, $WaferIDFromFile) = split (/_/, $FN);

if ($WIR_DATA eq "NO")
{
	#$FileName = "$MIR{1}{LOT_ID}_BIN_${DateTimeFromFile}_MTSZ_STDF";
	$td_filename = "${file}.TD";
}
else
{
	if(defined($WIR{1}{WAFER_ID}) && ($WIR{1}{WAFER_ID} =~ /\d+/) && ($SHB_COUNT || $SSB_COUNT)) {
		#$FileName = "$MIR{1}{LOT_ID}_DL_$WIR{1}{WAFER_ID}_${TimeFromFile}_${DateFromFile}_MTSZ_STDF";
		$td_filename = "${file}.TD";
	} else {
		system("mv $file /data/edbpa/db_areas/edb_mtsz_v22/converter/bad");
		if(!defined($WIR{1}{WAFER_ID})) {
			print "\ndir=no_wafer_id";                 ### RETURN BAD SUBDIR FOR MFT
                	&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_wafer_id") if $mft_flg==0;
                	exit 100;
		} elsif($WIR{1}{WAFER_ID} !~ /\d+/) {
			print "\ndir=no_wafer_id";                 ### RETURN BAD SUBDIR FOR MFT
                	&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_wafer_id") if $mft_flg==0;
                	exit 100;
		} else {
			print "\ndir=no_bin_summ_data";                 ### RETURN BAD SUBDIR FOR MFT
                        &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_bin_summ_data") if $mft_flg==0;
                        exit 100;
		}
        }
}

open OUTPUT, ">$td_filename" or die "Could not open file: $!";

#############################
# Load EMIR header record
PopulateEMIR();

if ($WIR_DATA eq "YES")
{
	PopulateWIR($WIR{1}{START_T}, $WIR{1}{WAFER_ID}, $WIR{1}{HEAD_NUM});
}

$P = 0;
$PartsCounted = 0;

$Wafer_ID = "";
$Part_ID  = "";
$test_num = ""; 
$head_num = "";
$site_num = ""; 
$test_flg = "";
$parm_flg = "";
$result   = ""; 
$opt_flg  = "";
$res_scal = "";
$res_ldig = "";
$res_rdig = "";
$desc_flg = "";
$units    = "";
$llm_scal = "";
$hlm_scal = "";
$llm_ldig = "";
$llm_rdig = "";
$hlm_ldig = "";
$hlm_rdig = "";
$lo_limit = "";
$hi_limit = "";
$test_nam = "";
$seq_name = "";
$test_txt = "";

while ($P <= $#DLArray)
{
	#print "Items left to process: ".($#DLArray - $P)."\n";
        $EPRRCnt = 0;
	# Read in the first entry of the array
	(
		$Wafer_ID, $Part_ID, $test_num, $head_num,
		$site_num, $test_flg, $parm_flg, $result, 
		$opt_flg, $res_scal, $res_ldig, $res_rdig,
		$desc_flg, $units, $llm_scal, $hlm_scal,
		$llm_ldig, $llm_rdig, $hlm_ldig, $hlm_rdig,
		$lo_limit, $hi_limit, $test_nam, $seq_name,
		$test_txt,
	) = split(/,/, $DLArray[$P]);
#	print "P: $P, $DLArray[$P]\n";

	#
	# Write the PIR record
	#
	WritePIR($PIR{$Part_ID}{HEAD_NUM}, $PIR{$Part_ID}{SITE_NUM}, $PIR{$Part_ID}{X_COORD}, $PIR{$Part_ID}{Y_COORD},
		 $PIR{$Part_ID}{PART_ID});

	$M = $P + 1;
	(
                $M_Wafer_ID, $M_Part_ID, $M_test_num, $M_head_num,
                $M_site_num, $M_test_flg, $M_parm_flg, $M_result,
                $M_opt_flg, $M_opt_flg, $M_res_scal, $M_res_ldig,
                $M_res_rdig, $M_desc_flg, $M_units, 
                $M_llm_scal, $M_hlm_scal, $M_llm_rdig, $M_hlm_ldig,
                $M_hlm_rdig, $M_lo_limit, $M_hi_limit, $M_test_nam,
                $M_seq_name, $M_test_txt,
        ) = split(/,/, $DLArray[$M]);


	while ($Part_ID == $M_Part_ID && $Part_ID ne "" && $P <= $#DLArray)
        {
		#print "P:$P, $DLArray[$P]\n";
		(
                	$Wafer_ID, $Part_ID, $test_num, $head_num, $site_num,
                	$test_flg, $parm_flg, $result, $opt_flg, $res_scal,
                	$res_ldig, $res_rdig, $desc_flg, $units, $llm_scal,
                	$hlm_scal, $llm_ldig, $llm_rdig, $hlm_ldig, $hlm_rdig,
                	$lo_limit, $hi_limit, $test_nam, $seq_name, $test_txt,
        	) = split(/,/, $DLArray[$P]);

		WritePTR($test_num, $PIR{$Part_ID}{HEAD_NUM}, $PIR{$Part_ID}{SITE_NUM},  $test_flg, $parm_flg, $result,
                 	 $opt_flg, $res_scal, $res_ldig, $res_rdig, $desc_flg, $units, $llm_scal, $hlm_scal, $llm_ldig,
                 	 $llm_rdig, $hlm_ldig, $hlm_rdig, $lo_limit, $hi_limit, $test_nam, $seq_name, $test_txt);

		$P++;
			
		$PartsCounted++;
                $EPRRCnt++;
                $PRES_CNT++;
                $M = $P + 1;
	
                (	$M_Wafer_ID, $M_Part_ID, $M_test_num, $M_head_num, $M_site_num,
                	$M_test_flg, $M_parm_flg, $M_result, $M_opt_flg,
                	$M_res_scal, $M_res_ldig, $M_res_rdig, $M_desc_flg, $M_units,
                	$M_llm_scal, $M_hlm_scal, $M_llm_ldig, $M_llm_rdig, $M_hlm_ldig, $M_hlm_rdig,
                	$M_lo_limit, $M_hi_limit, $M_test_nam, $M_seq_name, $M_test_txt,
        	) = split(/,/, $DLArray[$M]);

		if ($Part_ID != $M_Part_ID)
		{
                        (	$Wafer_ID, $Part_ID, $test_num, $head_num, $site_num, 
				$test_flg,
                        	$parm_flg, $result, $opt_flg, $res_scal, $res_ldig, $res_rdig, $desc_flg,
                        	$units, $llm_scal, $hlm_scal, $llm_ldig, $hlm_ldig, $lo_limit, $hi_limit,
                        	$test_nam, $seq_name, $test_txt,
                	) = split(/,/, $DLArray[$P]);
			#print "IN WHILE - P:$P, $DLArray[$P]\n";

			WritePTR($test_num, $PIR{$Part_ID}{HEAD_NUM}, $PIR{$Part_ID}{SITE_NUM},  $test_flg, 
				  $parm_flg, $result, $opt_flg, $res_scal, $res_ldig, $res_rdig, $desc_flg,
                         	  $units, $llm_scal, $hlm_scal, $llm_ldig, $llm_rdig, $hlm_ldig, $hlm_rdig, 
			  	  $lo_limit, $hi_limit, $test_nam, $seq_name, $test_txt);
		}
		$Prev_Part_ID = $Part_ID;
	}
	#
	# Write the EPRR Record
	#
	WriteEPRR(	$PRR{$Prev_Part_ID}{HEAD_NUM}, $PRR{$Prev_Part_ID}{SITE_NUM},
			$PRR{$Prev_Part_ID}{NUM_TEST}, $PRR{$Prev_Part_ID}{HARD_BIN},
			$PRR{$Prev_Part_ID}{SOFT_BIN}, $PRR{$Prev_Part_ID}{PART_FLG},
			$PRR{$Prev_Part_ID}{PAD_BYTE}, $PRR{$Prev_Part_ID}{X_COORD},
			$PRR{$Prev_Part_ID}{Y_COORD},  $PIR{$Prev_Part_ID}{PART_ID},
			$PRR{$Prev_Part_ID}{PART_TXT}, $PRR{$Prev_Part_ID}{PART_FIX}
		);	
	$PSUM_CNT++;
	$P++;
}

$MAX_BINS = $STS_RECORD_COUNT;
########################################################
# Write the WSBR Records here
# Note: I will use the STS Records here as wafer level
#	WSBR records.
for ($i = 1; $i <= $MAX_BINS; $i++)
{
        if ( !defined($STS{$i}{TEST_NUM}) )
        {
                $STS{$i} =                
                {
			HEAD_NUM => "",
                	SITE_NUM => "",
                	TEST_NUM => $i,
                	EXEC_CNT => "",
                	FAIL_CNT => 0,
                	ALRM_CNT => "",
                	OPT_FLAG => "",
                	PAD_BYTE => "",
                	TEST_MIN => "",
                	TEST_MAX => "",
                	TST_MEAN => "",
                	TST_SDEV => "",
                	TST_SUMS => "",
                	TST_SQRS => "",
                	TEST_NAM =>"" ,
                	SEQ_NAME => "",
                	TEST_LBL => "",
                };
        
	}
}
if ($WIR_DATA eq "YES")
{
	foreach $k (sort by_number keys %STS)
	{
		$WSBRCnt = $WSBRCnt + WriteWSBR($STS{$k}{TEST_NUM}, $STS{$k}{FAIL_CNT}, $STS{$k}{SEQ_NAME});
		#print "WSBR Count: $WSBRCnt\n";
	}
}


$MAX_BINS = $SBR_COUNT;
########################################################
# Write the WHBR Records here
# Note: I will use the SBR Records here as wafer level
for ($i = 1; $i <= $MAX_BINS; $i++)
{
        if ( !defined($SHB{$i}{HBIN_NUM}) )
	{
		$SHB{$i} =
		{
			HEAD_NUM => "",
			SITE_NUM => "",
			HBIN_NUM => $i,
			HBIN_CNT => 0,
			HBIN_NAM => "",
		};
	}
}

if ($WIR_DATA eq "YES")
{
	foreach $k (sort by_number keys %SHB)
	{
		$WHBRCnt = WriteWHBR($SHB{$k}{HBIN_NUM}, $SHB{$k}{HBIN_CNT}, $SHB{$k}{HBIN_NAM});
	}
}

if ($WIR_DATA eq "YES")
{
	##########################################
	# Write WRR record
	#
	WriteWRR( $WRR{1}{FINISH_T},
		$WRR{1}{HEAD_NUM},
		$WRR{1}{PAD_BYTE},
		$TOTAL_CNT,
		$WRR{1}{RTST_CNT},
		$WRR{1}{ABRT_CNT},
		$TOTAL_GOOD_CNT,
		$WRR{1}{FUNC_CNT},
		$WRR{1}{WAFER_ID},
		$WRR{1}{HAND_ID},
		$WRR{1}{PRB_CARD},
		$WRR{1}{USR_DESC},
		$WRR{1}{EXC_DESC});
}

#########################################
# Write the HBR Records
foreach $k (sort by_number keys %SHB)
{
	$HBRCnt = $HBRCnt + WriteHBR($SHB{$k}{HBIN_NUM}, $SHB{$k}{HBIN_CNT}, $SHB{$k}{HBIN_NAM});
}


#########################################
# Write the SBR Records
foreach $k (sort by_number keys %STS)
{
        $SBRCnt = $SBRCnt + WriteSBR($STS{$k}{TEST_NUM}, $STS{$k}{FAIL_CNT}, $STS{$k}{SEQ_NAME});
}


#################################
# Now write the ending MRR Record
%out::mrr = %{$out::init{mrr}};
$out::mrr{finish_t} = $MRR{1}{FINISH_T};
$out::mrr{part_cnt} = $TOTAL_CNT;
$out::mrr{rtst_cnt} = $MRR{1}{RTST_CNT};
$out::mrr{abrt_cnt} = $MRR{1}{ABRT_CNT};
$out::mrr{good_cnt} = $TOTAL_GOOD_CNT;
$out::mrr{func_cnt} = $MRR{1}{FUNC_CNT};
$out::mrr{disp_cod} = $MRR{1}{DISP_COD};
$out::mrr{usr_desc} = $MRR{1}{USR_DESC};
$out::mrr{exc_desc} = $MRR{1}{EXC_DESC};
print OUTPUT &out::pack_MRR(\%out::mrr);

##############################
# Close the STDF output file.
close OUTPUT ;

	
#
# Update EMIR record with wafer summation stats.
#
$out::emir{setup_t}  = $MIR{1}{START_T};
$out::emir{pres_cnt} = $PRES_CNT;
$out::emir{wswb_cnt} = $WSBRCnt;
$out::emir{whwb_cnt} = $WHBRCnt;
$out::emir{shwb_cnt} = $HBRCnt;
$out::emir{sswb_cnt} = $SBRCnt;
$out::emir{wsum_cnt} = 1;
$out::emir{ssum_cnt} = 1;
$out::emir{start_t}  = $MIR{1}{START_T};
&out::update_EMIR(\%out::emir, $td_filename) ;

close(OUTPUT);


########################
# RETURN CONVERTED FILE
########################
print "$td_filename"       if $mft_flag==0;
print "\ntd=$td_filename"  if $mft_flag==1;

exit 0;

##############################################################

sub convert_HBR(){
    $hbin_num = "";
    $hbin_cnt = "";
    $hbin_nam = "";
   
    read EP, $temp_in, $rec_len;

    $in = substr($temp_in, 0, 2);
    $hbin_num = unpack("S", $in);
  
    $in = substr($temp_in, 2, 4);
    $hbin_cnt= unpack("L", $in);
   
    $in = substr($temp_in, 6, 1);
    $size = unpack("C", $in);
    $hbin_nam = substr($temp_in, 7, $size);
    $hbin_nam =~ s/ +$// ; # remove trailing spaces
}

sub convert_SBR(){
    $sbin_num = "";
    $sbin_cnt = "";
    $sbin_nam = "";
   
    read EP, $temp_in, $rec_len;
    
    $in = substr($temp_in, 0, 2);
    $sbin_num = unpack("S", $in);

    $in = substr($temp_in, 2, 4);
    $sbin_cnt = unpack("L", $in);

    $in = substr($temp_in, 6, 1);
    $size = unpack("C", $in);
    $sbin_nam = substr($temp_in, 7, $size);
    $sbin_nam =~ s/ +$// ; # remove trailing spaces
}

sub convert_PMR(){
    $chan_cnt = "";
    $name_cnt = "";
    $chan_num = "";
    $pin_name = "";

    read EP, $temp_in, $rec_len;   

    $in = substr($temp_in, 0, 2);
    $chan_cnt = unpack("S", $in);
  
    $in = substr($temp_in, 2, 2);
    $name_cnt = unpack("S", $in);

    for($count=0; $count<$chan_cnt; $count++){
        $in = substr($temp_in, 4+2*$count, 2);
        $chan_num = unpack("S", $in);
    }
    $pin_start = 6 + 2*$count;
    
    for($count=0; $count<$name_cnt; $count++){
        $in = substr($temp_in, $pin_start+$count, 1);
        $size = unpack("C", $in);
        $pin_name = substr($temp_in, $pin_start+$count+1, $size);
        $pin_name =~ s/ +$// ; # remove trailing spaces
    } 
}


close(EP);

#print_data(\%Hash);

sub print_data
{
    local ($HRef) = @_;

    foreach $KEY (sort by_number keys %$HRef) 
    {
    print " $$HRef{$KEY}{TESTNUM}".
          " $$HRef{$KEY}{TESTNAME}".
          " $$HRef{$KEY}{UNIT}".
          " $$HRef{$KEY}{TESTTYPE}".
          " $$HRef{$KEY}{VALIDLOW}".
          " $$HRef{$KEY}{SPECLOW}".
          " $$HRef{$KEY}{SPECHIGH}".
          " $$HRef{$KEY}{VALIDHIGH}".
          " $$HRef{$KEY}{VGS}".
          " $$HRef{$KEY}{VDS}".
          " $$HRef{$KEY}{IC}".
          " $$HRef{$KEY}{IG}".
          " $$HRef{$KEY}{SBNUM}".
          " $$HRef{$KEY}{SBNAME}".
          "\n"; 
    }
    return;
} 

sub by_number {
        if ($a < $b)
        {
                -1;
        }
        elsif ($a == $b)
        {
                0;
        }
        elsif ($a > $b)
        {
                1;
        }
}

#######################
# MOVE FILE TO BAD DIR
# (FOR SOLARIS ONLY)
#######################
sub move_file_to_bad_dir
{
        my $loc_file = shift;
        my $loc_dir  = shift;
        my $fn       = ($loc_file=~/\//) ? substr($loc_file, rindex($loc_file,"/")+1) : $loc_file;
        system "mkdir $loc_dir" if ! -e $loc_dir;
        system "mv $loc_file $loc_dir";
        if (! -e "${loc_dir}/${fn}")
        {
                print "Failed to move $loc_file to $loc_dir dir. $!\n";
                exit 1;
        }
}



