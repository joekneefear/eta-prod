#!/usr/bin/perl
#
# Confidential Property of Fairchild Korea Semiconductor Corperation
# (c) Copyright Fairchild Korea Semiconductor Corperation, 2002
# All rights reserved
#
# MODIFICATION HISTORY:
#
# DATE          WHO             DESCRIPTION
# ____________  ______________  __________________________________________________
# 16 July 2002  Hyunnam Lee     Original
# 07 Aug  2003  Jongho Kim      End of LOT ID numeric clear.
# 22 Aug  2003  Andrew Prueser  Modified starting bin number from 1 to 0.
# 29 Oct  2003  SJ Hwang        Modified starting bin number from 0 to 1.
# 08 Nov  2003  SJ Hwang        Modified get_sastime function. 
# 28 Nov  2003  SJ Hwang        Converted to value of bin by discrete product. (SP20 : Tester) 
# 12 Apr  2005  SJ Hwang        Added to delete the special character in the LOT name.
# 27 May  2005  CHANGWON LIM    Added logic to make auto testplan file
# 26 Jul  2005  SJ Hwang        Modified logic to make start time and valid limit 
# 29 Jul  2005  SJ Hwang        Modified logic to make testplan of FX tester
# 23 Aug  2005  SJ Hwang        Modified logic to make allowances for unit of test.
#                               Modified both H/W bin_no and H/W bin_name. 
# 07 Apr  2011  Ben Rommel Kho  Adopted .TD STDF filenaming convention.
# 08 Aug  2012  Ben Rommel Kho  Adjusted for MFT and to directly oupput TP in STDF instead of DAT.
#				Removed "reverse" function when unpacking formats S,s,L,f
# 06 Sep  2012  Ben Rommel Kho  "Change length of the JOB_NAME from 10 to 20" by SJ
# 26 Oct  2012  Reuben Capio    Added file path to TD for MFT.
# 14-Oct  2013  Rodney Cyr      Removed hardcoded EDB username and password for testplan lookup.
# 21-Oct  2013  Eric Alfanta    Improved trappings for no lot id error for MFT compatibility
# 27-Jan  2014  Eric Alfanta    Trapped files if rows & columns exceeds 10000 & lotid eq blank 
# 28-Jan  2014  Eric Alfanta    Removed trappings to check if row/cols exceeds 10000. 
# 19-May  2014  Eric Alfanta	Commented out to read BC_NAM
#
#
# Program to read in an SORT raw data file and convert to STDF+
# for loading into EDB/EWB. 
#
#########################################################
###        Include perl libraries                     ###
#########################################################
use Time::Local;
use Carp;
use FindBin;
use English;
use lib "$FindBin::Bin";
use lib $ENV{'STDF_PERL_LIB'};
#use Sybase::CTlib;
use Getopt::Long;
use File::Basename;

require "stdf_use.pl";
{
    package out;
    if (!eval(&::generate_all('stdfPL.spec')))
        {
             confess $@;
        }
    require 'stdfPL.pl';
}

#########################################################
###   Declaring Variable                              ###
#########################################################
my ($at_device, $at_program, $at_revision, $at_unit, $at_testname, $at_swbin_name) = "";
my ($at_testno, $at_swbin, $at_spec_low, $at_spec_high, $at_hwbin) = 0;
my ($at_hwbin_name, $at_outfile, $at_system, $LOGFLE, $i, $key)= "";
my $at_valid_low = -1E+21 ;
my $at_valid_high = 1E+21 ;
my $at_default = "0";
my ($wafer_no,$key,$lot_len,$at_PTR_Cnt) = 0;
my %at_test_spec;   #Hash of Testing information;
                    #KEY:Wafer number VALUE:Spec of testing;

my ($week,$month,$day,$tmp,$year)=split(/\s+/,localtime());
my ($hour,$minute,$second)=split(/:/,$tmp);
my ($tmp_lot,$lot_no,$job_name,$job_name_old,$tmp_str)="";
my %tst_rlt 	  = ();
my $file          = "";
my $plant         = uc($ENV{ENV_FACILITY});     ### MFT ENV VAR
my $env_mod       = "";
my $td_filename   = "";
my $tp_filename   = "";
my $envname       = uc($ENV{ENV_NAME});
   $envname       =~ s/edb_|_v22//ig;


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
        print "\tscript -infile=<datalog file> -plant=<plant(opt)>\n";
        exit 1;
}



#########################################################
###   Auto Testplan Output Format                     ###
#########################################################
# COLUMN LENGTH : 15,7,25,8,9,15,15,15,15,9,15,9,15,7,8,20,20,50
format ATOUT =
 @<<<<<<<<<<<<<< @>>>>>> @<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<< @>>>>>>>> @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<< @<<<<<<<<<<<<<< @<<<<<<<< @<<<<<<<<<<<<<< @>>>>>> @>>>>>>> @<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $at_program, $at_testno, $at_testname, $at_unit, $at_default, $at_valid_low, $at_valid_high, $at_spec_low, $at_spec_high, $at_testno, $at_swbin_name, $at_hwbin, $at_hwbin_name, $at_default, $at_default, $at_default, $at_default, $at_default
.


#########################################################
###   Tester Type Find                                ###
#########################################################
if ($file =~ /\/LF|^LF/)
{
	$at_system = "FX";
}
elsif ($file =~ /\/LB|^LB/)
{
    $at_system = "A360";
}
elsif ($file =~ /\/T[AB]|^T[AB]/)
{
    $at_system = "SP20";
}
elsif ($file =~ /\/LW|^LW/)
{
    $at_system = "WL8000";
}
else
{
    $at_system = "OTHER";
}


#########################################################
###   Reading the Result File                         ###
#########################################################
%tst_rlt=ReadFile($file);    

if($ARGV[1] eq "-p") {        ## Printing Mood;
   ptr_rlt(%tst_rlt);
} 
else {                        ## Normal Mood; 
   #########################################################
   ###   Created the OUT file                            ###
   #########################################################
   ($wafer_no,) = keys(%tst_rlt);
   my $lot_head = $tst_rlt{$wafer_no}{DT_HEADER};
   $lot_no      = $$lot_head{$wafer_no}{LOT_NO};
   $lot_len     = length($lot_no);
   $tmp_lot     = "";

   #### If Lot ID is blank, die ####
   if($lot_no eq "")
   {
	print "\ndir=no_lotid";
	exit 100;
   }

   # Added by SJ Hwang  2005.04.19 
   # Added to delete the special character in the LOT name 
   # ASCII CODE: 35(#),40((),41()),42(*),43(+),44(,),45(-),46(.)
   # ASCII CODE:,48~57(0~9),65~90(A~Z),95(_),97~122(a~z) 

   for($i=0;$i<$lot_len;$i++) {
      $tmp_str = substr($lot_no,$i,1);
      $tmp = ord($tmp_str);
      
      if( ($tmp >= 48 && $tmp <= 57 ) || ($tmp >= 65 && $tmp <= 90) || ($tmp >= 97 && $tmp <= 122) )
      {
         $tmp_lot .= $tmp_str;
         $tmp_lot =~ s/\s+//g;
      }
   }
   $lot_no = $tmp_lot;

   my $time = time();
   #my $outfile  = $lot_no."_".$sblot_id."_".$job_name."_".$time."_STDF";   ### by Rodney Cyr 20030801
   #$outfile =~ s/\-/\_/;       # 2004. 07. 15 SJ Hwang  Remove the special character in lot name.
   #$outfile =~ s/\s+//;        # 2005. 03. 18 SJ Hwang  Remove the space character in lot name.
   my $td_filename = "${file}.TD"; # 2011/04/07 Ben Rommel Kho. Adopted <raw_filename>.TD convention.

   my $SSWB_CNT = 0;
   my $SHWB_CNT = 0;
   my $WSUM_CNT = 0;
   my $WSWB_CNT = 0;
   my $WHWB_CNT = 0;
   my $PSUM_CNT = 0;
   my $PRES_CNT = 0;

   open(OUT,">$td_filename");                           ## Open the Output File ##

   #########################################################
   ###   Check Testplan                                  ###
   #########################################################
#   &Look_For_Testplan ($job_name, $job_rev, "bcsort");
&CreateTestPlan_STDF();

   #########################################################
   ###   Write the EMIR Record                           ###
   #########################################################
   %out::emir = %{$out::init{emir}};
   $out::emir{mode_cod} = "P";    ##"P" for Production;
   $out::emir{stat_num} = $$lot_head{$wafer_no}{STATION};

#   print "SETUP_TIME:$$lot_head{$wafer_no}{SETUPTIME}\n";
#   print "START_TIME:$$lot_head{$wafer_no}{STARTTIME}\n";

   $out::emir{setup_t}  = get_sastime($$lot_head{$wafer_no}{SETUPTIME});
   $out::emir{start_t}  = get_sastime($$lot_head{$wafer_no}{SETUPTIME});
#   $out::emir{start_t}  = get_sastime($$lot_head{$wafer_no}{STARTTIME});
   
   $out::emir{lot_id}   = $lot_no;
   $out::emir{part_typ} = $$lot_head{$wafer_no}{PART_TYP};
   $out::emir{job_nam}  = uc $$lot_head{$wafer_no}{JOB_NAME};
   $out::emir{oper_nam} = $$lot_head{$wafer_no}{OPER_NAM};
   $out::emir{node_nam} = $$lot_head{$wafer_no}{NODE_NUM};
   $out::emir{tstr_typ} = $$lot_head{$wafer_no}{TSTR_TYP};
   $out::emir{exec_typ} = $$lot_head{$wafer_no}{EXEC_TYP};
   $out::emir{hand_id}  = $$lot_head{$wafer_no}{HAN_ID};
#   $out::emir{sblot_id} = $$lot_head{$wafer_no}{SBLOT_ID};
   $out::emir{job_rev}  = $$lot_head{$wafer_no}{JOB_REV};
   $out::emir{prb_card} = $$lot_head{$wafer_no}{CARD_ID};
   $out::emir{oper_id}  = $$lot_head{$wafer_no}{OPER_NAM};
   $out::emir{spec_nam} = uc $$lot_head{$wafer_no}{JOB_NAME};
   $out::emir{spec_rev} = $$lot_head{$wafer_no}{JOB_REV};
   $out::emir{load_brd} = $$lot_head{$wafer_no}{LOAD_ID};
   $out::emir{lot_type} = "P";    ##"P" for Production;
   $out::emir{device}   = $$lot_head{$wafer_no}{PART_TYP};
   print OUT &out::pack_EMIR(\%out::emir);


   #########################################################
   ###   Write the WIR Record                            ###
   #########################################################
   my $wafer_nm = $wafer_no +0;
   %out::wir = %{$out::init{wir}};
   
#   print "START_TIME:$$lot_head{$wafer_no}{STARTTIME}\n";

   $out::wir{start_t}  = get_sastime($$lot_head{$wafer_no}{STARTTIME});
   #  $out::wir{wafer_id} = $wafer_nm;          
   $out::wir{wafer_id} = $sblot_id;         # 2003/03/26 DS kang
   print OUT &out::pack_WIR(\%out::wir);


   #########################################################
   ###   Write the PIR Record                            ###
   #########################################################
   my $die_info = $tst_rlt{$wafer_no}{CHIP_INFO};
   my @temp;
   foreach $part_id (sort by_number keys %$die_info) {
           %out::pir = %{$out::init{pir}};
           $out::pir{x_coord} = $$die_info{$part_id}{X_COORD};
           $out::pir{y_coord} = $$die_info{$part_id}{Y_COORD};
           $out::pir{part_id} = $part_id;
           print OUT &out::pack_PIR(\%out::pir);
           $output = $$die_info{$part_id}{TEST_RESULT};
           #########################################################
           ###   Write the PTR Record                            ###
           #########################################################
           @temp = keys %$output;      #### 2003/04/07  When PTR not exist 
           if(! $temp[0])              ####  add by DS kang
           {
                %out::ptr = %{$out::init{ptr}};
                print OUT &out::pack_PTR(\%out::ptr);
                $PRES_CNT++;
           }
           foreach $tnum (sort by_number keys %$output) {
                   %out::ptr = %{$out::init{ptr}};
                   $out::ptr{test_num} = $tnum;
                   $out::ptr{result}   = $$output{$tnum}{RESULT};
                   $out::ptr{head_num} = $$output{$tnum}{HEAD_NUM};
                   print OUT &out::pack_PTR(\%out::ptr);
		   $PRES_CNT++;
           }
 

           #########################################################
           ###   Write the EPRR Record                           ###
           #########################################################
           %out::eprr = %{$out::init{eprr}};
           $out::eprr{head_num} = $$die_info{$part_id}{HEAD_NUM};
           $out::eprr{num_test} = $$die_info{$part_id}{NUM_TEST};
           $out::eprr{hard_bin} = $$die_info{$part_id}{HARD_BIN};
           $out::eprr{soft_bin} = $$die_info{$part_id}{SOFT_BIN};
           $out::eprr{x_coord}  = $$die_info{$part_id}{X_COORD};
           $out::eprr{y_coord}  = $$die_info{$part_id}{Y_COORD};
           $out::eprr{part_id}  = $part_id;
           print OUT &out::pack_EPRR(\%out::eprr);
	   $PSUM_CNT++;
   }


   #########################################################
   ###   Write the WSBR Record                           ###
   #########################################################
   
   my $smmry=$tst_rlt{$wafer_no}{SMMRY_TST};
   my $softbin=$$smmry{$wafer_no}{SBIN_CNT};           ## 2003/04/07  modified by DS kang

   $out::wsbr{sbin_num} = 0;                ## Modified by SJ Hwang   2003/10/29
   $out::wsbr{sbin_cnt} = 0;
   print OUT &out::pack_WSBR(\%out::wsbr); 

   foreach $bin_nm (sort by_number keys %$softbin) {   #  BIN  256 -> 31
           if($WSWB_CNT <=31)
           {
           	%out::wsbr = %{$out::init{wsbr}};
           	$out::wsbr{sbin_num} = $bin_nm - 1;
           	$out::wsbr{sbin_cnt} = $$softbin{$bin_nm};
           }
           else
           {
                $out::wsbr{sbin_cnt} = $out::wsbr{sbin_cnt} + $$softbin{$bin_nm} + 0;
           } #end if
           if($WSWB_CNT < 31 || $WSWB_CNT == 256)
           { 
              if($out::wsbr{sbin_num} > 0)
              {	print OUT &out::pack_WSBR(\%out::wsbr); }
           }
	   $WSWB_CNT++;
   }
   $WSWB_CNT = 31;
   
   #########################################################
   ###   Write the WHBR Record                           ###
   #########################################################
   my $hardbin=$$smmry{$wafer_no}{HBIN_CNT};

   $out::whbr{hbin_num} = 0;                ## Modified by SJ Hwang   2003/10/29
   $out::whbr{hbin_cnt} = 0;
   print OUT &out::pack_WHBR(\%out::whbr); 

   foreach $bin_nm (sort by_number keys %$hardbin) {
           if($WHWB_CNT <= 31)
           {
               %out::whbr = %{$out::init{whbr}};
               $out::whbr{hbin_num} = $bin_nm - 1;
               $out::whbr{hbin_cnt} = $$hardbin{$bin_nm};
           }
           else
           {
              $out::whbr{hbin_cnt} =$out::whbr{hbin_cnt} + $$hardbin{$bin_nm} + 0; 
           } # end if
            
           if($WHWB_CNT < 31 || $WHWB_CNT == 256)
           {
              if($out::whbr{hbin_num} > 0) 
              { print OUT &out::pack_WHBR(\%out::whbr); }
           }
	   $WHWB_CNT++;
   }
   $WHWB_CNT = 31;

   #########################################################
   ###   Write the WRR Record                            ###
   #########################################################
   %out::wrr = %{$out::init{wrr}};

#   print "FINISH_TIME:$$smmry{$wafer_no}{FINISH_TM}\n";

   $$out::wrr{finish_t}=get_sastime($$smmry{$wafer_no}{FINISH_TM});
   $out::wrr{part_cnt}=$$smmry{$wafer_no}{EXECUTED_CNT};
   $out::wrr{abrt_cnt}=$$smmry{$wafer_no}{ABRT_CNT};
   $out::wrr{good_cnt}=$$smmry{$wafer_no}{GOOD_CNT};
   # $out::wrr{wafer_id}=$wafer_nm;
   $out::wrr{wafer_id}=$sblot_id;                    # 2003/03/26 DS kang 
   $out::wrr{prb_card}=$$lot_head{$wafer_no}{CARD_ID};
   print OUT &out::pack_WRR(\%out::wrr);
   $WSUM_CNT++;


   #########################################################
   ###   Write the SBR Record                            ###
   #########################################################
   my $sbin = $$smmry{$wafer_no}{SBIN_CNT};

   $out::sbr{sbin_num} = 0;                  ## Modified by SJ Hwang   2003/10/29
   $out::sbr{sbin_cnt} = 0;
   print OUT &out::pack_SBR(\%out::sbr); 

   foreach $binkey (sort by_number keys %$sbin) {
           if($SSWB_CNT <= 31)
           {
           	%out::sbr = %{$out::init{sbr}};
           	$out::sbr{sbin_num} = $binkey - 1;
           	$out::sbr{sbin_cnt} = $$sbin{$binkey};
           }
           else
           {
		$out::sbr{sbin_cnt} = $out::sbr{sbin_cnt} + $$sbin{$binkey} + 0;
           }  # end if
           if($SSWB_CNT < 31 || $SSWB_CNT == 256)
           {
              if($out::sbr{sbin_num} > 0)
              {	print OUT &out::pack_SBR(\%out::sbr); }
           }
	   $SSWB_CNT++;
   }
   $SSWB_CNT=31;
   #########################################################
   ###   Write the HBR Record                            ###
   #########################################################
   my $hbin = $$smmry{$wafer_no}{HBIN_CNT};

   $out::hbr{hbin_num} = 0;                  ## Modified by SJ Hwang   2003/10/29
   $out::hbr{hbin_cnt} = 0;
   print OUT &out::pack_HBR(\%out::hbr); 

   foreach $binkey (sort by_number keys %$hbin) {
           if($SHWB_CNT <= 31)
           { 
                 %out::hbr = %{$out::init{hbr}};
                 $out::hbr{hbin_num} = $binkey - 1;
                 $out::hbr{hbin_cnt} = $$hbin{$binkey};
           }
           else
           {
                $out::hbr{hbin_cnt} = $out::hbr{hbin_cnt} + $$hbin{$binkey} + 0;
           } # end if  
           if($SHWB_CNT < 31 || $SHWB_CNT == 256) 
           {
              if($out::hbr{hbin_num} > 0)
              {  print OUT &out::pack_HBR(\%out::hbr); }
           }
	   $SHWB_CNT++;
   }
   $SHWB_CNT=31;

   #########################################################
   ###   Write the MRR Record                            ###
   #########################################################
   %out::mrr = %{$out::init{mrr}};
   $out::mrr{finish_t} = get_sastime($$smmry{$wafer_no}{FINISH_TM});
   $out::mrr{part_cnt} = $$smmry{$wafer_no}{EXECUTED_CNT};
   $out::mrr{rtst_cnt} = $$smmry{$wafer_no}{RTST_CNT};
   $out::mrr{abrt_cnt} = $$smmry{$wafer_no}{ABRT_CNT};
   $out::mrr{good_cnt} = $$smmry{$wafer_no}{GOOD_CNT};
   print OUT &out::pack_MRR(\%out::mrr);
   close(OUT); ## The Result File of SORT is closed;

   #
   # Update the EMIR record
   #
   $out::emir{ssum_cnt} = 1;
   $out::emir{sswb_cnt} = $SSWB_CNT;
   $out::emir{shwb_cnt} = $SHWB_CNT;
   $out::emir{wsum_cnt} = $WSUM_CNT;
   $out::emir{wswb_cnt} = $WSWB_CNT;
   $out::emir{whwb_cnt} = $WHWB_CNT;
   $out::emir{psum_cnt} = $PSUM_CNT;
   $out::emir{pres_cnt} = $PRES_CNT;
   &out::update_EMIR(\%out::emir, $td_filename);


   ########################
   # RETURN CONVERTED FILE
   ########################
   print "\ntd=$td_filename" 		     if $tp_filename eq "";
   print "\ntd=$td_filename tp=$tp_filename" if $tp_filename ne "";
   exit 0;
   
   if($$lot_head{$wafer_no}{NAM} eq "Y") {
      %wf_unit = qw (
                      unknown 0
                      inches  1
                      cm      2
                      mm      3
                      mils    4
                      microns 222
                    );
   
      print "##The Log for SORT Wafer Map \n";
      $mapfile=$lot_no."_".$wafer_no."_map".".stdf"; 
#      $mapfle=$MPATH.$mapfile;
      $mapfle=$mapfile;
      open(MOUT,">$mapfle");
      print "$mapfle is opened \n";
   
      #########################################################
      ###   Write the EMIR Record for Wafer Map Data        ###
      #########################################################
      my $wfmap = $tst_rlt{$wafer_no}{NAM_DATA};
      %out::emir = %{$out::init{emir}};
      $out::emir{mode_cod} = "P";    ##"P" for Production;
      $out::emir{stat_num} = $$wfmap{$wafer_no}{STATION_NO};
      $out::emir{setup_t}  = get_sastime($$lot_head{$wafer_no}{SETUPTIME});
      $out::emir{start_t}  = get_sastime($$lot_head{$wafer_no}{STARTTIME});
      $out::emir{wsum_cnt} = 1;
      $out::emir{lot_id}   = $lot_no;
      $out::emir{part_typ} = $$lot_head{$wafer_no}{PART_TYP};
      $out::emir{job_nam}  = $$lot_head{$wafer_no}{JOB_NAME};
      $out::emir{oper_nam} = $$wfmap{$wafer_no}{OPER_NAME};
      $out::emir{node_nam} = $$lot_head{$wafer_no}{NODE_NUM};
      $out::emir{tstr_typ} = $$lot_head{$wafer_no}{TSTR_TYP};
      $out::emir{exec_typ} = $$lot_head{$wafer_no}{EXEC_TYP};
      $out::emir{hand_id}  = $$lot_head{$wafer_no}{HAN_ID};
      $out::emir{job_rev}  = $$lot_head{$wafer_no}{JOB_REV};
      $out::emir{prb_card} = $$lot_head{$wafer_no}{CARD_ID};
      $out::emir{oper_id}  = $$lot_head{$wafer_no}{OPER_NAM};
      $out::emir{spec_nam} = $$lot_head{$wafer_no}{JOB_NAME};
      $out::emir{spec_rev} = $$lot_head{$wafer_no}{JOB_REV};
      $out::emir{load_brd} = $$wfmap{$wafer_no}{LOAD_ID};
      $out::emir{lot_type} = "P";    ##"P" for Production;
      print MOUT &out::pack_EMIR(\%out::emir);
     
   
      #########################################################
      ###   Write the EWCR Record for Wafer Map Data        ###
      #########################################################
      %out::ewcr = %{$out::init{ewcr}};
      $out::ewcr{wafr_siz} = 6;
      $out::ewcr{die_ht}    = $$lot_head{$wafer_no}{DIE_HT};
      $out::ewcr{die_wid}   = $$lot_head{$wafer_no}{DIE_WIDTH};
      my $wfunt = $$lot_head{$wafer_no}{WF_UNIT};
      $wfunt    =~ tr/A-Z/a-z/;
      $out::ewcr{wf_units}  = $wf_unit{$wfunt};
      $out::ewcr{start_x}   = 1;
      $out::ewcr{start_y}   = 1;
      $out::ewcr{row_cnt}   = $$wfmap{$wafer_no}{ROWS};
      $out::ewcr{col_cnt}   = $$wfmap{$wafer_no}{COLUMNS};
      print MOUT &out::pack_EWCR(\%out::ewcr);

    
      #########################################################
      ###   Write the WIR Record for Wafer Map Data        ###
      #########################################################
      $wafer_nm = $wafer_no +0;
      %out::wir = %{$out::init{wir}};
      $out::wir{start_t}  = get_sastime($$lot_head{$wafer_no}{STARTTIME});
      $out::wir{wafer_id} = $wafer_nm;
      print MOUT &out::pack_WIR(\%out::wir);
   
   
      #########################################################
      ###   Write the WMR Record for Wafer Map Data        ###
      #########################################################
      my $totchip = $$wfmap{$wafer_no}{ROWS}*$$wfmap{$wafer_no}{COLUMNS};
      my $totval  = ($totchip-($totchip%32767))/32767 ;
      $namdata = $$wfmap{$wafer_no}{MAP_DATA};
      for($i=0;$i<=$totval;$i++) {
          if($i < $totval) {
             $exechip=32767;
          }
          else {
             $exechip=$totchip-32767*$i;
          }
          %out::wmr = %{$out::init{wmr}};
          $out::wmr{die_cnt} = $exechip; 
   
          for($j=1;$j<=$exechip;$j++) {
              $out::wmr{$die_bin}=$$namdata{$j};
          }
          print MOUT &out::pack_WMR(\%out::wmr);
      } #For-End;
   
      %out::wmr = %{$out::init{wmr}};
      $out::wmr{die_cnt}=0;
      print MOUT &out::pack_WMR(\%out::wmr);
   
      #########################################################
      ###   Write the WHBR Record for Wafer Map Data        ###
      #########################################################
      my $hbin_rlt = $$wfmap{$wafer_no}{BIN_RLT};
      foreach $bin_no (sort by_number keys %$hbin_rlt ) {
              %out::whbr = %{$out::init{whbr}};
              $out::whbr{hbin_num}=$bin_no - 1;
              $out::whbr{hbin_cnt}=$$hbin_rlt{$bin_no};
              print MOUT &out::pack_WHBR(\%out::whbr);
      }
   
      #########################################################
      ###   Write the WRR Record for Wafer Map Data        ###
      #########################################################
      %out::wrr = %{$out::init{wrr}};
      $out::wrr{finish_t} = get_sastime($$smmry{$wafer_no}{FINISH_TM});
      $out::wrr{part_cnt} = $$smmry{$wafer_no}{EXECUTED_CNT};
      $out::wrr{rtst_cnt} = $$smmry{$wafer_no}{RTST_CNT};
      $out::wrr{abrt_cnt} = $$smmry{$wafer_no}{ABRT_CNT};
      $out::wrr{good_cnt} = $$smmry{$wafer_no}{GOOD_CNT};
      $out::wrr{wafer_id} = $wafer_nm;
      $out::wrr{hand_id}  = $$lot_head{$wafer_no}{HAN_ID};
      $out::wrr{prb_card} =  $$lot_head{$wafer_no}{CARD_ID};
      print MOUT &out::pack_WRR(\%out::wrr);
   
      #########################################################
      ###   Write the HBR Record for Wafer Map Data        ###
      #########################################################
      my $hbin_rlt = $$wfmap{$wafer_no}{BIN_RLT};
      foreach $bin_no (sort by_number keys %$hbin_rlt ) {
              %out::hbr = %{$out::init{hbr}};
              $out::hbr{hbin_num}=$bin_no - 1;
              $out::hbr{hbin_cnt}=$$hbin_rlt{$bin_no};
              print MOUT &out::pack_HBR(\%out::hbr);
      }
   
   
      #########################################################
      ###   Write the MRR Record                            ###
      #########################################################
      %out::mrr = %{$out::init{mrr}};
      $out::mrr{finish_t} = get_sastime($$smmry{$wafer_no}{FINISH_TM});
      $out::mrr{part_cnt} = $$smmry{$wafer_no}{EXECUTED_CNT};
      $out::mrr{rtst_cnt} = $$smmry{$wafer_no}{RTST_CNT};
      $out::mrr{abrt_cnt} = $$smmry{$wafer_no}{ABRT_CNT};
      $out::mrr{good_cnt} = $$smmry{$wafer_no}{GOOD_CNT};
      print MOUT &out::pack_MRR(\%out::mrr);
      close(OUT); ## The Result File of SORT is closed;
      print "$OUTFLE is closed \n";
   } #if-End;
   else {
      print "Wafer Map File does not exist. \n";
   }
   
   close(MOUT);
} ## END Normal Mood;   
  
sub ReadFile {
    my ($file)=@_;
    my ($flg,$str)="";
    my ($dummy,$year,$month,$day,$week,$setup_tm,$start_tm)=""; 
    my ($minute,$second,$hour,$time)="";
   
    my %dt_head;        #Hash for the Header of result data;
                        #KEY:Wafer_no Value:Header information;

    my %test_spec;      #Hash of Testing information;
                        #KEY:Wafer number VALUE:Spec of testing;

    my %sortdata;       #Hash for saving the result of Testing;
                        #KEY:wafer number VALUE:measured value;

    my %test_result;    #Hash for Result value a chip;
                        #KEY:Test numbser VALUE:Test result per chip;

    my %chip_info;      #Hash for Tested chip Information;
                        #KEY:part_id VALUE:Information of the tested chip;

    my %sbin_cnt;       #Hash for saving the Software bin count
                        #KEY:BIN number VALUE:Bin counter

    my %hbin_cnt;       #Hash for saving the Hardware bin count
                        #KEY:BIN Number VALUE:Bin counter

    my %test_sum;       #Hash for Testing Summary per test
                        #KEY:Test Number VALUE:Summary of Die Testing

    my %bin_rlt;        #Hash which is saved bin result for Nam Data.
                        #KEY:Bin Number VALUE: The Number of bin per bin number.

    my %map_data;       #Hash for Map data
                        #KEY:Sequencial Number VALUE: map data

    my %nam_data;       #Hash for the total of Nam data
                        #KEY:Wafer number VALUE:Total Nam data

    my %smmry_tst;       #Hash for the summary data

    my $file_name = `basename $file`;    
    chomp($file_name);
    my @parameter = split(/_/,$file);
    print "FILE NAME:$file_name \n";
    my $lot_id    = $parameter[3];
    my $wafer_id  = $parameter[4];

    $flg=open(FLE,"$file");  #Targer File Open;


    ###########################################
    ###      Read STDF_FAR                  ###
    ###########################################
    read FLE,$str,1;
    $cpu_type = unpack("C",$str);
    read FLE,$str,1;
    $stdf_ver = unpack("C",$str);

    ###########################################
    ###      Read MIR                       ###
    ###########################################
    read FLE,$str,4;      ## SETUP TIME ## 
    $date = unpack("b32",$str);
    $dumy =TakeTime(substr($date,0,4));
    $year =TakeTime(substr($date,4,12));
    $month=TakeTime(substr($date,16,4));
    $day  =TakeTime(substr($date,20,8));
    $week =TakeTime(substr($date,28,4));

    read FLE,$str,4;
    $time =unpack("b32",$str);
    $dummy=TakeTime(substr($time,0,8));
    $hour=TakeTime(substr($time,8,8));
    $minute=TakeTime(substr($time,16,8));
    $second=TakeTime(substr($time,24,8));
    $setup_tm=$year.$month.$day.$hour.$minute.$second;

    read FLE,$str,4;      ## START TIME ##
    $date = unpack("b32",$str);
    $dumy2 =TakeTime(substr($date,0,4));
    $year2 =TakeTime(substr($date,4,12));
    $month2=TakeTime(substr($date,16,4));
    $day2  =TakeTime(substr($date,20,8));
    $week2 =TakeTime(substr($date,28,4));
 
    read FLE,$str,4;
    $time =unpack("b32",$str);
    $dummy2=TakeTime(substr($time,0,8));
    $hour2=TakeTime(substr($time,8,8));
    $minute2=TakeTime(substr($time,16,8));
    $second2=TakeTime(substr($time,24,8));
    $start_tm=$year2.$month2.$day2.$hour2.$minute2.$second2;

    read FLE,$str,1;
    $stat_num = unpack("A",$str);
    #print "statname[$stat_num]\n";

    read FLE,$str,1;
    $mode_cod = unpack("C",$str);
    read FLE,$str,2;
    $spec_cnt = unpack("S",$str);
    read FLE,$str,2;
    $map_cnt  = unpack("S",$str);
    read FLE,$str,1;
    $rtest_cod= unpack("A",$str);
    read FLE,$str,20;
    $lot_id   = unpack("A20",$str);

    $lot_len = length($lot_id);
    $tmp_lot = "";

    # Added by SJ Hwang  2005.04.19
    # Added to delete the special character in the LOT name
    # ASCII CODE: 35(#),40((),41()),42(*),43(+),44(,),45(-),46(.)
    # ASCII CODE:,48~57(0~9),65~90(A~Z),95(_),97~122(a~z)

    for($i=0;$i<$lot_len;$i++) {
       $tmp_str = substr($lot_id,$i,1);
       $tmp = ord($tmp_str);

       if( ($tmp >= 48 && $tmp <= 57 ) || ($tmp >= 65 && $tmp <= 90) || ($tmp >= 97 && $tmp <= 122) )
       {
          $tmp_lot .= $tmp_str;
          $tmp_lot =~ s/\s+//g;
       }
    }
    $lot_id = $tmp_lot;

    read FLE,$str,20;
    $part_type= unpack("A20",$str);
    read FLE,$str,20;
    $node_name= unpack("A20",$str);
    read FLE,$str,10;
    $tstr_typ = unpack("A10",$str);

	if ($stdf_ver eq "2" || $stdf_ver == 2)
    	{
        	#print "STDF_VER = 2\n";
            	read FLE,$str,10;
            	$job_name = unpack("A10",$str);
        }
        else
        {
        	#print "STDF_VER = 3\n";
            	read FLE,$str,20;
            	$job_name = unpack("A20",$str);
        }
    	$job_name =~ s/\-/\_/g;

    read FLE,$str,10;
    $job_rev  = unpack("A10",$str);
    
    # 김형선대리 요청으로 Revision 값은 입력된 그대로 조치하기로 함. Modified by SJ Hwang 2005.09.13
    #if($job_rev !=~/^[a-zA-Z]e/)   # 2003/1/28 append float to decimal and not char 
    #{
    #    $job_rev  = sprintf("%d", $job_rev);
    #}
    
    read FLE,$str,10;
    $sblot_id = unpack("A10",$str);
    read FLE,$str,20;
    $oper_nam = unpack("A20",$str);
    read FLE,$str,10;
    $exec_typ = unpack("A10",$str);
    read FLE,$str,10;
    $exec_ver = unpack("A10",$str);
    read FLE,$str,20;
    $family_id = unpack("A20",$str);
    read FLE,$str,10;
    $spec_nam = unpack("A10",$str);
    read FLE,$str,10;
    $spec_ver = unpack("A10",$str);
    read FLE,$str,1;
    $isnam    = unpack("A",$str);

    ###########################################
    ###     Read SDR                        ###
    ###########################################
    read FLE,$str,10;
    $hand_typ = unpack("A10",$str);
    read FLE,$str,10;
    $hand_id  = unpack("A10",$str);
    read FLE,$str,20;
    $card_id = unpack("A20",$str);
    read FLE,$str,20;
    my $load_id = unpack("A20",$str);
    read FLE,$str,20;
    $cabl_id = unpack("A20",$str);

    ###########################################
    ###       Read WCR                      ###
    ###########################################
    read FLE,$str,4;
    $wafr_siz = unpack("f",$str);

    read FLE,$str,4;
    $die_ht = unpack("f",$str);

    read FLE,$str,4;
    $die_width = unpack("f",$str);

    read FLE,$str,10;
    $wf_units = unpack("A10",$str);

    read FLE,$str,1;
    $wf_flat  = unpack("A",$str);

    read FLE,$str,1;
    $pedding=unpack("C",$str);
    
    # Added by SJ Hwang  2005.04.19
    # Added to delete the special character in the Job Name
    # ASCII CODE: 35(#),40((),41()),42(*),43(+),44(,),45(-),46(.)
    # ASCII CODE:,48~57(0~9),65~90(A~Z),95(_),97~122(a~z)

    my $spec_len = 0;
    $spec_len = length($job_name);
    $job_name = "\U$job_name";
	$tmp_lot = "";

    for($i=0;$i<$spec_len;$i++) {
       $tmp_str = substr($job_name,$i,1);
       $tmp = ord($tmp_str);

       if( ($tmp >= 48 && $tmp <= 57 ) || ($tmp >= 65 && $tmp <= 90) || ($tmp == 95) || ($tmp == 45) )
       {
          $tmp_lot .= $tmp_str;
          $tmp_lot =~ s/\s+//g;
       }
    }
    # $job_name = $tmp_lot;
    $spec_len = length($job_name);

	# Test program Name
	$f = substr $tmp_lot, 6, 2;  # F1800AXXR  (F:FX Tester, 1800:제품코드, A:revision, XX:series 제품을 표시하는 key, R:test 방법) 
    $f  = "\U$f";  # 대문자로 변환   
    
    if (($at_system eq "FX") && ($f eq "XX"))
    {
    	$spec_len = $spec_len - 6;    	
    	$f = substr $part_type, 7, 2;
    	
    	if ($spec_len > 0)
    	{
    		$job_name = substr($tmp_lot,0,4).$f.substr($tmp_lot,6,$spec_len);
    	}
    	else
    	{
    		$job_name = substr($tmp_lot,0,4).$f;
    	}
    }

    ###################################################
    ### Creating the Hash for the header of result  ###
    ### --Included: BC_FAR, BC_MIR, BC_SDR, BC_WCR  ### 
    ###################################################
    $dt_head{$wafer_id} = {
        CPUTYPE   => $cpu_type,
        STDFVER   => $stdf_ver,
        SETUPTIME => $setup_tm,
        STARTTIME => $start_tm,
        STATION   => $stat_num,
        MODE_COD  => $mode_cod,
        SPEC_CNT  => $spec_cnt,
        MAP_CNT   => $map_cnt,
        RTEST_COD => $rtest_cod,
        LOT_NO    => $lot_id,
        PART_TYP  => $part_type,
        NODE_NUM  => $node_name,
        TSTR_TYP  => $tstr_typ,
        JOB_NAME  => $job_name,
        JOB_REV   => $job_rev,
#        SBLOT_ID  => $sblot_id,
        OPER_NAM  => $oper_nam,
        EXEC_TYP  => $exec_typ,
        EXEC_VER  => $exec_ver,
        FAMILY_ID => $family_id,
#        SPEC_NAM  => $spec_nam,
#        SPEC_VER  => $spec_ver,
        SPEC_NAM  => $job_name,
        SPEC_VER  => $job_rev,
        NAM       => $isnam,
        HAN_TYP   => $hand_typ,
        HAN_ID    => $hand_id,
        CARD_ID   => $card_id,
        LOAD_ID   => $load_id,
        CABLE_ID  => $cabl_id,
        WAFER_SIZ => $wafr_siz,
        DIE_HT    => $die_ht,
        DIE_WIDTH => $die_width,
        WF_UNIT   => $wf_units,
        WF_FLAT   => $wf_flat,
        PEDDING   => $pedding
    };
 
    ############################################
    ###      Read PTR2                       ###
    ############################################
    $at_PTR_Cnt = $spec_cnt;

    for($i=1;$i<=$spec_cnt;$i++) {
       read FLE,$str,4;
       $test_no = unpack("L",$str);

       read FLE,$str,2;
       $res_scal = unpack("s",$str);    # modified unsigned short -> short

       read FLE,$str,2;
       $llm_scal = unpack("s",$str);    # modified unsigned short -> short

       read FLE,$str,2;
       $hlm_scal = unpack("s",$str);    # modified unsigned short -> short

       read FLE,$str,10;
       $units = unpack("A10",$str);
       $units =~ s/\s+//g;
       $units = "\U$units";  # 대문자로 변환   

       read FLE,$str,4;
       $lo_limit = unpack("f",$str);

       read FLE,$str,4;
       $hi_limit = unpack("f",$str);

       read FLE,$str,4;
       $lo_spec = unpack("f",$str);

       read FLE,$str,4;
       $hi_spec = unpack("f",$str);

       read FLE,$str,20;
       $test_text = unpack("A20",$str);

       ## For AUTO TESTPLAN ------------------------------------------------------

       # TEST_NUM (Test no, S/W Bin)
       $at_testno=$test_no;
       $at_swbin =$test_no;

       # UNITS (Unit)
       $at_unit=$units;

       # 2005.09.06 김형선대리 요청으로 lo_limit, hi_limit 값을 SPEC으로 이용함.
       # LO_SPEC (Spec Low)
       $at_spec_low = $lo_limit;

       # HI_SPEC (Spec High)
       $at_spec_high = $hi_limit;

       # TEST_TEXT (Test Name, S/W Bin Name)
       $at_testname = $test_text;
       $at_swbin_name = $test_text;

       # SKIP
       read FLE,$str,1;  # Pass Bin 에서 Fail Bin으로 대체됨. 김형선대리 요청건 2005.08.23
       
       # pBin (H/W Bin)
       read FLE,$str,1;
       $at_hwbin=unpack("C",$str);

       # SORT_TEXT (H/W Bin Name)
       read FLE,$str,18;
       $at_hwbin_name=unpack("A18",$str);
       $at_hwbin_name =~ s/\s+//g;
       
       if ($at_hwbin_name eq "")
       {
       	 $at_hwbin_name = $test_text;
       }
       
       ###############################################
       ###      Read TRR                           ###
       ###############################################
       read FLE,$str,2;
       $item_code=unpack("S",$str);

       read FLE,$str,1;
       $becond_flag = unpack("C",$str);

       read FLE,$str,1;
       $pedding1 = unpack("C",$str);

       read FLE,$str,20;
       $bias1_nam = unpack("A20",$str);

       read FLE,$str,20;
       $bias2_nam = unpack("A20",$str);

       read FLE,$str,20;
       $timec_nam = unpack("A20",$str);

       read FLE,$str,10;
       $bias1_unit = unpack("A10",$str);
       $bias1_unit =~ s/\s+//g;
       $bias1_unit = "\U$bias1_unit";  # 대문자로 변환   
   
       read FLE,$str,10;
       $bias2_unit = unpack("A10",$str);
       $bias2_unit =~ s/\s+//g;
       $bias2_unit = "\U$bias2_unit";  # 대문자로 변환   

       read FLE,$str,10;
       $timec_unit = unpack("A10",$str);

       read FLE,$str,2;
       $pedding2 = unpack("A2",$str);

       read FLE,$str,4;
       $bias1_value = unpack("f",$str);

       read FLE,$str,4;
       $bias2_value = unpack("f",$str);

       read FLE,$str,4;
       $timec_value = unpack("f",$str); 
       
       # bias1, bias2 추출시 UNIT 감안 Added by SJ Hwang  2005.08.23
       # testname에 조건 추가 김형선대리요청건 3005.09.06

	   if ($tstr_typ eq "SP20") # SP20 일 경우만 조건을 붙임 Added by SJ Hwang 2005.09.13
	   {
	       my $tmp_units = '';
       
    	   $tmp_units = substr($bias1_unit,0,1);
       
	       if ($tmp_units eq "P")
    	   {
        	  $bias1_value = $bias1_value * 1000000000000;
	       }
    	   elsif ($tmp_units eq "N")
	       {
    	      $bias1_value = $bias1_value * 1000000000;
	       }
    	   elsif ($tmp_units eq "U")
	       {
    	      $bias1_value = $bias1_value * 1000000;
	       }
    	   elsif ($tmp_units eq "M")
	       {
    	      $bias1_value = $bias1_value * 1000;
	       }
    	   else
	       {
    	      $bias1_value = $bias1_value * 1;
	       }

	       $tmp_units = substr($bias2_unit,0,1);
       
    	   if ($tmp_units eq "P")
	       {
    	      $bias2_value = $bias2_value * 1000000000000;
	       }
    	   elsif ($tmp_units eq "N")
           {
              $bias2_value = $bias2_value * 1000000000;
           }
           elsif ($tmp_units eq "U")
           {
              $bias2_value = $bias2_value * 1000000;
           }
           elsif ($tmp_units eq "M")
           {
              $bias2_value = $bias2_value * 1000;
           }
           else
           {
              $bias2_value = $bias2_value * 1;
           }
    	
           # TESTNAME에 조건 포함.
           $bias1_value = sprintf("%8.2f",$bias1_value);
           $bias1_value = substr($bias1_value, 0, 8);
    
           $bias2_value = sprintf("%8.2f",$bias2_value);
           $bias2_value = substr($bias2_value, 0, 8);
    
           $at_testname = $at_testname."_".$bias1_value.$bias1_unit."_".$bias2_value.$bias2_unit;
           $at_testname =~ s/\s+//g;
       }

       $at_test_spec{$i}={
           TEST_NO	=> $at_testno,
           SW_BIN	=> $at_testno,
           UNIT		=> $at_unit,
           LO_SPEC	=> $at_spec_low,
           HI_SPEC	=> $at_spec_high,
           TEST_NAME	=> $at_testname,
           SW_BIN_NAME	=> $at_swbin_name,
           HW_BIN	=> $at_hwbin,
           HW_BIN_NAME	=> $at_hwbin_name
       };

#       print "$at_program $at_testno $at_testname $at_unit $at_null $at_null $at_null \n";
#       print "$at_spec_low $at_spec_high $at_hwbin $at_hwbin_name\n";
#       print "$bias1_unit $bias2_unit $bias1_value $bias2_value \n\n";

       ## ----------------------------------------------------------------------

       ###################################################
       ### Creating the Hash for the Testing Spec      ###
       ### --Included: BC_PTR2, BC_TRR                 ### 
       ###################################################
       $test_spec{$test_no}={
           RES_SCAL    => $res_scal,
           LLM_SCAL    => $llm_scal,
           HLM_SCAL    => $hlm_scal,
           LO_LIMIT    => $lo_limit,
           HI_LIMIT    => $hi_limit,
           UNIT        => $units,
           LO_SPEC     => $lo_spec,
           HI_SPEC     => $hi_spec,
           TEST_TEXT   => $test_text, 
           ITEM_CODE   => $item_code,
           BECOND_FLAG => $becond_flag,
           PEDDING1    => $pedding1,
           BIAS1_NAM   => $bias1_nam,
           BIAS2_NAM   => $bias2_nam,
           TIMEC_NAM   => $timec_nam,
           BIAS1_UNIT  => $bias1_unit,
           BIAS2_UNIT  => $bias2_unit,
           TIMEC_UNIT  => $timec_unit,
           PEDDING2    => $pedding2,
           BIAS1_VALUE => $bias1_value,
           BIAS2_VALUE => $bias2_value,
           TIMEC_VALUE => $timec_value
       };
    }  ## i-for end;

    ###############################################
    ###      Read BC_PIRPRR,BC_PTR1             ###
    ###############################################
    for($i=1;$i<=$map_cnt;$i++) {
       read FLE,$str,2;
       $head_num = unpack("S",$str);

       read FLE,$str,2;
       $site_num = unpack("S",$str);

       read FLE,$str,2;
       $num_test = unpack("S",$str);
 
       read FLE,$str,2;
       $hard_bin = unpack("S",$str);
 
       read FLE,$str,2;
       $soft_bin = unpack("S",$str);

       read FLE,$str,2;
       $x_coord = unpack("s",$str);

       read FLE,$str,2;
       $y_coord = unpack("s",$str);

       read FLE,$str,2;
       $pedding = unpack("C",$str);

       read FLE,$str,4;
       $test_t = unpack("L",$str);

       read FLE,$str,20;           ## Modified by SJ HWANG  2003. 12. 01
#       $part_id = unpack("A20",$str);
       $part_id = $i;

       read FLE,$str,1;
       $part_flg = unpack("b16",reverse($str));

       read FLE,$str,3;
       $pedding2 = unpack("A2",$str);           

       for ($j=1;$j<=$num_test;$j++) {
           read FLE,$str,4;
           $test_no=unpack("L",$str);

           read FLE,$str,2;
           $head_num=unpack("S",$str); 

           read FLE,$str,2;
           $site_num=unpack("S",$str);

           read FLE,$str,4;
           $result=unpack("f",$str);

           read FLE,$str,1;
           $test_flg=unpack("C",reverse($str));
            
           read FLE,$str,1;
           $parm_flg=unpack("C",reverse($str));


           read FLE,$str,2;
           $pedding=unpack("A2",$str);

           $test_result{$test_no} = {
              HEAD_NUM => $head_num,
              SITE_NUM => $site_num,
              RESULT   => $result,
              TEST_FLG => $test_flg,
              PARM_FLG => $parm_flg,
              PEDDING  => $pedding
           };
       } #j-for end;


       ###################################################
       ### Creating the Hash for the Tested Data       ###
       ### --Included: BC_PIRPRR, BC_STDF_PTR1         ### 
       ###################################################

       $chip_info{$part_id} = {
           HEAD_NUM    => $head_num,
           SITE_NUM    => $site_num,
           NUM_TEST    => $num_test,
           HARD_BIN    => $hard_bin,
           SOFT_BIN    => $soft_bin,
           X_COORD     => $x_coord,
           Y_COORD     => $y_coord,
           TEST_T      => $test_t,
           PART_FLG    => $part_flg,
           TEST_RESULT => {%test_result}
       };

       undef%test_result;
    } ## MAP i-for end ## 


    ################################################################
    ###  Reading the Summary information after the Die testing   ###
    ################################################################

    ###############################################
    ###      Read WRR_PCR                       ###
    ###############################################
    read FLE,$str,4;      ## FINISH TIME ## 
    $date = unpack("b32",$str);
    $dumy=substr($date,0,4);
    $dumy =TakeTime($dumy);
    $year = substr($date,4,12);
    $year =TakeTime($year);
    $month=substr($date,16,4);
    $month=TakeTime($month);
    $day=substr($date,20,8); 
    $day  =TakeTime($day);
    $week = substr($date,28,4);
    $week =TakeTime($week);
 
    read FLE,$str,4;
    $time =unpack("b32",$str);
    $dummy = substr($time, 0,8);
    $dummy=TakeTime($dummy);
    $hour=substr($time,8,8);
    $hour=TakeTime($hour);
    $minute=substr($time,16,8);
    $minute=TakeTime($minute);
    $second=substr($time,24,8);
    $second=TakeTime($second);
    $finish_tm=$year.$month.$day.$hour.$minute.$second;

    read FLE,$str,4;
    $executed_cnt = unpack("L",$str);
    read FLE,$str,4;
    $rtst_cnt = unpack("L",$str);    
    read FLE,$str,4;
    $abrt_cnt = unpack("L",$str);
    read FLE,$str,4;
    $good_cnt = unpack("L",$str);


    ###############################################
    ###      Read BC_SBR                        ###
    ###############################################
    for($i=1;$i<=256;$i++) { #Reading the information of Software bin counter.
       read FLE,$str,4;
       $sbin_cnt{$i} = unpack("L",$str);
    }
    
#    if ($tstr_typ eq "SP20") ## (Discrete product) Converted to values of bin , SJ HWANG 2003.11.28
#    {
#       for($i=1;$i<=35;$i++) {
#          $tmp_sbin_cnt{$i} = $sbin_cnt{$i};
#       }
#
#       $sbin_cnt{1} = 0 + $tmp_sbin_cnt{21};
#       $sbin_cnt{2} = 0 + $tmp_sbin_cnt{22};
#       $sbin_cnt{3} = 0 + $tmp_sbin_cnt{23};
#       $sbin_cnt{4} = 0 + $tmp_sbin_cnt{24};
#       $sbin_cnt{5} = 0 + $tmp_sbin_cnt{1};
#       $sbin_cnt{6} = 0 + $tmp_sbin_cnt{2};
#       $sbin_cnt{7} = 0 + $tmp_sbin_cnt{3};
#       $sbin_cnt{8} = 0 + $tmp_sbin_cnt{4};
#       $sbin_cnt{9} = 0 + $tmp_sbin_cnt{5} + $tmp_sbin_cnt{6} + $tmp_sbin_cnt{7};
#       $sbin_cnt{10} = 0 + $tmp_sbin_cnt{8} + $tmp_sbin_cnt{9} + $tmp_sbin_cnt{10};
#       $sbin_cnt{11} = 0 + $tmp_sbin_cnt{11};
#       $sbin_cnt{12} = 0 + $tmp_sbin_cnt{12};
#       $sbin_cnt{13} = 0 + $tmp_sbin_cnt{13};
#       $sbin_cnt{14} = 0 + $tmp_sbin_cnt{14};
#       $sbin_cnt{15} = 0 + $tmp_sbin_cnt{15} + $tmp_sbin_cnt{16} + $tmp_sbin_cnt{17} + $tmp_sbin_cnt{18} + $tmp_sbin_cnt{19} + $tmp_sbin_cnt{25} + $tmp_sbin_cnt{26} + $tmp_sbin_cnt{27} + $tmp_sbin_cnt{28} + $tmp_sbin_cnt{29} + $tmp_sbin_cnt{30} + $tmp_sbin_cnt{31} + $tmp_sbin_cnt{32};
#
#       for($i=16;$i<=32;$i++) {
#          $sbin_cnt{$i} = 0;
#       }
#    }
#    else                     ## (Analog product) Modified by SJ Hwang  2003.10.28
#    {
#       $sbin_cnt{1} = 0 + $sbin_cnt{1} + $sbin_cnt{21};
#       $sbin_cnt{2} = 0 + $sbin_cnt{2} + $sbin_cnt{22};
#       $sbin_cnt{3} = 0 + $sbin_cnt{3} + $sbin_cnt{23};
#       $sbin_cnt{4} = 0 + $sbin_cnt{4} + $sbin_cnt{24};
#       $sbin_cnt{21} = 0;
#       $sbin_cnt{22} = 0;
#       $sbin_cnt{23} = 0;
#       $sbin_cnt{24} = 0;
#    }
#

    ###############################################
    ###      Read BC_HBR                        ###
    ###############################################
    for($i=1;$i<=256;$i++) { #Reading the information of Hardware bin counter.
       read FLE,$str,4;
       $hbin_cnt{$i} = unpack("L",$str);
    }
    
#    if ($tstr_typ eq "SP20") ## (Discrete product) Converted to values of bin , SJ HWANG 2003.11.28
#    {
#       for($i=1;$i<=35;$i++) {
#          $tmp_hbin_cnt{$i} = $hbin_cnt{$i};
#       }
#
#       $hbin_cnt{1} = 0 + $tmp_hbin_cnt{21};
#       $hbin_cnt{2} = 0 + $tmp_hbin_cnt{22};
#       $hbin_cnt{3} = 0 + $tmp_hbin_cnt{23};
#       $hbin_cnt{4} = 0 + $tmp_hbin_cnt{24};
#       $hbin_cnt{5} = 0 + $tmp_hbin_cnt{1};
#       $hbin_cnt{6} = 0 + $tmp_hbin_cnt{2};
#       $hbin_cnt{7} = 0 + $tmp_hbin_cnt{3};
#       $hbin_cnt{8} = 0 + $tmp_hbin_cnt{4};
#       $hbin_cnt{9} = 0 + $tmp_hbin_cnt{5} + $tmp_hbin_cnt{6} + $tmp_hbin_cnt{7};
#       $hbin_cnt{10} = 0 + $tmp_hbin_cnt{8} + $tmp_hbin_cnt{9} + $tmp_hbin_cnt{10};
#       $hbin_cnt{11} = 0 + $tmp_hbin_cnt{11};
#       $hbin_cnt{12} = 0 + $tmp_hbin_cnt{12};
#       $hbin_cnt{13} = 0 + $tmp_hbin_cnt{13};
#       $hbin_cnt{14} = 0 + $tmp_hbin_cnt{14};
#       $hbin_cnt{15} = 0 + $tmp_hbin_cnt{15} + $tmp_hbin_cnt{16} + $tmp_hbin_cnt{17} + $tmp_hbin_cnt{18} + $tmp_hbin_cnt{19} + $tmp_hbin_cnt{25} + $tmp_hbin_cnt{26} + $tmp_hbin_cnt{27} + $tmp_hbin_cnt{28} + $tmp_hbin_cnt{29} + $tmp_hbin_cnt{30} + $tmp_hbin_cnt{31} + $tmp_hbin_cnt{32};
#
#       for($i=16;$i<=32;$i++) {
#          $hbin_cnt{$i} = 0;
#       }
#    }
#    else                     ## (Analog product) Modified by SJ Hwang  2003.10.28
#    {
#       $hbin_cnt{1} = 0 + $hbin_cnt{1} + $hbin_cnt{21};
#       $hbin_cnt{2} = 0 + $hbin_cnt{2} + $hbin_cnt{22};
#       $hbin_cnt{3} = 0 + $hbin_cnt{3} + $hbin_cnt{23};
#       $hbin_cnt{4} = 0 + $hbin_cnt{4} + $hbin_cnt{24};
#       $hbin_cnt{21} = 0;
#       $hbin_cnt{22} = 0;
#       $hbin_cnt{23} = 0;
#       $hbin_cnt{24} = 0;
#    }
#
    ###############################################
    ###      Read BC_TSR                        ###
    ###############################################
    for($i=1;$i<=$spec_cnt;$i++) {
       read FLE,$str,2;
       $test_number = unpack("S",$str);
       read FLE,$str,2;
       $test_pad    = unpack("A2",$str);
       read FLE,$str,4;
       $exec_cnt    = unpack("L",$str);
       read FLE,$str,4;
       $fail_cnt    = unpack("L",$str);
       read FLE,$str,4;
       $alrm_cnt    = unpack("L",$str);
       read FLE,$str,4;
       $test_min    = unpack("f",$str);
       read FLE,$str,4;
       $test_max    = unpack("f",$str);
       read FLE,$str,4;
       $test_sums   = unpack("f",$str);
       read FLE,$str,4;
       $test_sqrs   = unpack("f",$str);
       read FLE,$str,20;
       $test_name   = unpack("A20",$str);
       read FLE,$str,20;
       $seq_name    = unpack("A20",$str);

       $test_sum{$test_number} = {
             TEST_PAD   =>  $test_pad,
             EXEC_CNT   =>  $exec_cnt,
             FAIL_CNT   =>  $fail_cnt,
             ALRM_CNT   =>  $alrm_cnt,
             TEST_MIN   =>  $test_min,
             TEST_MAX   =>  $test_max,
             TEST_SUM   =>  $test_sums,
             TEST_SQRS  =>  $test_sqrs,
             TEST_NAME  =>  $test_name,
             SEQ_NAME   =>  $seq_name
        }; 
    } #for-i end;


    #########################################################
    ### Creating the Hash for the Test result per a test  ###
    ### --Included:WRRPCR,BC_SBR,BC_HBR,BC_TSR            ### 
    #########################################################
    $smmry_tst{$wafer_id} = {
       FINISH_TM    => $finish_tm,
       EXECUTED_CNT => $executed_cnt,
       RTST_CNT     => $rtst_cnt,
       ABRT_CNT     => $abrt_cnt,
       GOOD_CNT     => $good_cnt,
       SBIN_CNT     => {%sbin_cnt},
       HBIN_CNT     => {%hbin_cnt},
       TEST_SUM     => {%test_sum}
    };


    ###############################################
    ###      Read BC_NAM                        ###
    ###############################################
#    if($isnam eq "Y") { ## Reading NamData
#        read FLE,$str,20;
#        $lot_nm = unpack("A20",$str);
#        read FLE,$str,2;
#        $wafer_no = unpack("S",$str);
#        read FLE,$str,2;
#        $tot_cnt_wafer = unpack("S",$str);
#        read FLE,$str,2;
#        $rows = unpack("S",$str);
#        read FLE,$str,2;
#        $columns = unpack("S",$str);
#        read FLE,$str,20;
#        $product = unpack("A20",$str);
#
#        read FLE,$str,4;      ## Probe Start TIME ##
#        $date = unpack("b32",$str);
#
#        $dumy =TakeTime(substr($date,0,4));
#        $year =TakeTime(substr($date,4,12));
#        $month=TakeTime(substr($date,16,4));
#        $day  =TakeTime(substr($date,20,8));
#        $week =TakeTime(substr($date,28,4));
#        read FLE,$str,4;
#        $time =unpack("b32",$str);
#        $dummy=TakeTime(substr($time,0,8));
#        $hour=TakeTime(substr($time,8,8));
#        $minute=TakeTime(substr($time,16,8));
#        $second=TakeTime(substr($time,24,8));
#        $prb_tm=$year.$month.$day.$hour.$minute.$second; 
#
#        read FLE,$str,4;      ## Conversion Time ## 
#        $date = unpack("b32",$str);
#        $dumy =TakeTime(substr($date,0,4));
#        $year =TakeTime(substr($date,4,12));
#        $month=TakeTime(substr($date,16,4));
#        $day  =TakeTime(substr($date,20,8));
#        $week =TakeTime(substr($date,28,4));
#        read FLE,$str,4;
#        $time =unpack("b32",$str);
#        $dummy=TakeTime(substr($time,0,8));
#        $hour=TakeTime(substr($time,8,8));
#        $minute=TakeTime(substr($time,16,8));
#        $second=TakeTime(substr($time,24,8));
#        $convert_tm=$year.$month.$day.$hour.$minute.$second;
#
#        read FLE,$str,2;
#        $total_die = unpack("S",$str);
#
#        for($i=0;$i<33;$i++) {
#            read FLE,$str,2;
#            $bin_rlt{$i}=unpack("S",$str);
#        } ##for-i end;
#
#        read FLE, $str,2;
#        $wafer_size=unpack("S",$str);
#        read FLE,$str,2;
#        $wafer_fat = unpack("S",$str);
#        read FLE,$str,4;
#        $x_size = unpack("f",$str);
#        read FLE,$str,4;
#        $y_size = unpack("f",$str);
#        read FLE,$str,20;
#        $oper_name = unpack("A20",$str);
#        read FLE,$str,20;
#        $tst_systm_id=unpack("A20",$str); 
#        read FLE,$str,20;
#        $probe_typ = unpack("A20",$str);
#        read FLE,$str,20;
#        $system_id = unpack("A20",$str);
#        read FLE,$str,2;
#        $station_no = unpack("S",$str);
#        read FLE,$str,2;
#        $pad_data = unpack("S",$str);
#        read FLE,$str,20;
#        $test_pgm_nm = unpack("A20",$str);
#        read FLE,$str,20;
#        $prob_card_id=unpack("A20",$str);
#
#        read FLE,$str,20;
#        $cable_id = unpack("A20",$str);
#        read FLE,$str,20;
#        $load_nm = unpack("A20",$str);
#        read FLE,$str,20;
#        $softrev = unpack("A20",$str);
#        
#        $map_count = 1;
#        for($i=1;$i<=$rows;$i++) {
#            for($j=1;$j<=$columns;$j++) {
#                read FLE, $str,1;
#                $map_data{$map_count}=unpack("c",$str);
#                $map_count++;
#            } ##for-j end;
#        } ##for-i end;
#
#        $nam_data{$wafer_id}={
#            LOT_NM        => $lot_nm,
#            TOT_CNT_WAFER => $tot_cnt_wafer,
#            ROWS          => $rows,
#            COLUMNS       => $columns,
#            PRODUCT       => $product,
#            PRB_TM        => $prb_tm, 
#            CONVERT_TM    => $convert_tm,
#            TOTAL_DIE     => $total_die,
#            BIN_RLT       => {%bin_rlt},
#            WAFER_SIZE    => $wafer_size,
#            WAFER_FAT     => $wafer_fat,
#            X_SIZE        => $x_size,
#            Y_SIZE        => $y_size,
#            OPER_NAME     => $oper_name,
#            TST_SYSTM_ID  => $tst_systm_id,
#            PROBE_TYP     => $probe_typ,
#            SYSTEM_ID     => $system_id,
#            STATION_NO    => $station_no,
#            PAD_DATA      => $pad_data,
#            TEST_PGM_NO   => $test_pgm_no,
#            PROB_CARD_ID  => $prob_card_id,
#            CABLE_ID      => $cable_id,
#            LOAD_ID       => $load_nm,
#            SOFT_REV      => $soft_rev,
#            MAP_DATA      => {%map_data} 
#        };
#
#    } ## If end;

    $sortdata{$wafer_id} = {
          DT_HEADER  => {%dt_head},
          TEST_SPEC  => {%test_spec},
          CHIP_INFO  => {%chip_info},
          SMMRY_TST  => {%smmry_tst},
          NAM_DATA   => {%nam_data}     
    };

    close(FLE);
    return(%sortdata);
}


sub ptr_rlt {
    my (%rawdata) = @_;
    my ($wf_no,)= keys(%rawdata);
    my $lot_tmp = $rawdata{$wf_no}{DT_HEADER};
    my $lot_id  = $$lot_tmp{$wf_no}{LOT_NO};
    my $ptrlog  = "/exceed/edbmgr/scripts/test/".$lot_id."_".$wf_no.".txt";
    open(PTR,">$ptrlog");
    print "log=[$ptrlog]\n";

    print PTR "********** BC HEAD **********\n";
    print PTR "    ***** BC_FAR*****\n";
    print PTR "CPU Type: $$lot_tmp{$wf_no}{CPUTYPE}\n";
    print PTR "STDF_VER: $$lot_tmp{$wf_no}{STDFVER}\n";
    print PTR "\n\n     ***** BC_MIR *****\n";
    print PTR "SETUP TIME    : $$lot_tmp{$wf_no}{SETUPTIME}\n";
    print PTR "START TIME    : $$lot_tmp{$wf_no}{STARTTIME}\n";
    print PTR "STATION Number: $$lot_tmp{$wf_no}{STATION}\n";
    print PTR "MODE CODE     : $$lot_tmp{$wf_no}{MODE_COD}\n";
    print PTR "SPEC_CNT      : $$lot_tmp{$wf_no}{SPEC_CNT}\n";
    print PTR "MAP_CNT       : $$lot_tmp{$wf_no}{MAP_CNT}\n";
    print PTR "RTEST_COD     : $$lot_tmp{$wf_no}{RTEST_COD}\n";
    print PTR "LOT_NO        : $$lot_tmp{$wf_no}{LOT_NO}\n";
    print PTR "PART_TYP      : $$lot_tmp{$wf_no}{PART_TYP}\n";
    print PTR "NODE_NUM      : $$lot_tmp{$wf_no}{NODE_NUM}\n";
    print PTR "TSTR_TYP      : $$lot_tmp{$wf_no}{TSTR_TYP}\n";
    print PTR "JOB_NAME      : $$lot_tmp{$wf_no}{JOB_NAME}\n";
    print PTR "JOB_REV       : $$lot_tmp{$wf_no}{JOB_REV}\n";
#    print PTR "SBLOT_ID      : $$lot_tmp{$wf_no}{SBLOT_ID}\n";
    print PTR "OPER_NAM      : $$lot_tmp{$wf_no}{OPER_NAM}\n";
    print PTR "EXEC_TYPE     : $$lot_tmp{$wf_no}{EXEC_TYPE}\n";
    print PTR "EXEC_VER      : $$lot_tmp{$wf_no}{EXEC_VER}\n";
    print PTR "FAMILY_ID     : $$lot_tmp{$wf_no}{FAMILY_ID}\n";
    print PTR "SPEC_NAM      : $$lot_tmp{$wf_no}{SPEC_NAM}\n";
    print PTR "SPEC_VER      : $$lot_tmp{$wf_no}{SPEC_VER}\n";
    print PTR "NAM           : $$lot_tmp{$wf_no}{NAM}\n";
    print PTR "\n     ***** BC_SDR ***** \n";
    print PTR "Hander Type   : $$lot_tmp{$wf_no}{HAN_TYP}\n";
    print PTR "Hander ID     : $$lot_tmp{$wf_no}{HAN_ID}\n";
    print PTR "Prober CARD_ID: $$lot_tmp{$wf_no}{CARD_ID}\n";
    print PTR "LOAD Board    : $$lot_tmp{$wf_no}{LOAD_ID}\n";
    print PTR "CABLE_ID      : $$lot_tmp{$wf_no}{CABLE_ID}\n";
    print PTR "\n     ***** BC_WCR ***** \n";
    print PTR "WAFER_SIZE    : $$lot_tmp{$wf_no}{WAFER_SIZ}\n";
    print PTR "Die Height    : $$lot_tmp{$wf_no}{DIE_HT}\n";
    print PTR "Die Width     : $$lot_tmp{$wf_no}{DIE_WIDTH}\n";
    print PTR "Wafer Units   : $$lot_tmp{$wf_no}{WF_UNIT}\n";
    print PTR "Wafer Flatt   : $$lot_tmp{$wf_no}{WF_FLAT}\n";
    print PTR "PEDDING       : $$lot_tmp{$wf_no}{PEDDING}\n";

    print PTR "\n\n********** BC_SPEC **********\n";
    my $tspec=$rawdata{$wf_no}{TEST_SPEC};
    foreach $tstnum (sort by_number keys %$tspec) {
            print PTR "\n     ***** BC_PTR2 *****\n";
            print PTR "Test Number   : $tstnum \n";
            print PTR "SCALE         : $$tspec{$tstnum}{RES_SCAL}\n";
            print PTR "LLM_SCAL      : $$tspec{$tstnum}{LLM_SCAL}\n";
            print PTR "HLM_SCAL      : $$tspec{$tstnum}{HLM_SCAL}\n";
            print PTR "LO_LIMIT      : $$tspec{$tstnum}{LO_LIMIT}\n";
            print PTR "HI_LIMIT      : $$tspec{$tstnum}{HI_LIMIT}\n";
            print PTR "UNIT          : $$tspec{$tstnum}{UNIT}\n";
            print PTR "LO_SPEC       : $$tspec{$tstnum}{LO_SPEC}\n";
            print PTR "HI_SPEC       : $$tspec{$tstnum}{HI_SPEC}\n";
            print PTR "TEST_TEXT     : $$tspec{$tstnum}{TEST_TEXT}\n";
            print PTR "\n     ***** BC_TRR *****\n";
            print PTR "ITEM_CODE     : $$tspec{$tstnum}{ITEM_CODE} \n";
            print PTR "BECOND_FLAG   : $$tspec{$tstnum}{BECOND_FLAG} \n";
            print PTR "PEDDING1      : $$tspec{$tstnum}{PEDDING1} \n";
            print PTR "BIAS1_NAM     : $$tspec{$tstnum}{BIAS1_NAM} \n";
            print PTR "BIAS2_NAM     : $$tspec{$tstnum}{BIAS2_NAM} \n";
            print PTR "TIMEC_NAM     : $$tspec{$tstnum}{TIMEC_NAM} \n";
            print PTR "BIAS1_UNIT    : $$tspec{$tstnum}{BIAS1_UNIT} \n";
            print PTR "BIAS2_UNIT    : $$tspec{$tstnum}{BIAS2_UNIT} \n";
            print PTR "TIMEC_UNIT    : $$tspec{$tstnum}{TIMEC_UNIT} \n";
            print PTR "PEDDING2      : $$tspec{$tstnum}{PEDDING2} \n";
            print PTR "BIAS1_VALUE   : $$tspec{$tstnum}{BIAS1_VALUE} \n";
            print PTR "BIAS2_VALUE   : $$tspec{$tstnum}{BIAS2_VALUE} \n";
            print PTR "TIMEC_VALUE   : $$tspec{$tstnum}{TIMEC_VALUE} \n";
    }

    print PTR "\n\n********** BC_MAP **********\n";
    my $dieinfo = $rawdata{$wf_no}{CHIP_INFO};
    foreach $die (sort by_number keys %$dieinfo) {
            print PTR "     ***** BC_PIR_PRR *****\n";
            print PTR "HEAD NUMBER   : $$dieinfo{$die}{HEAD_NUM} \n";
            print PTR "SITE NUMBER   : $$dieinfo{$die}{SITE_NUM} \n";
            print PTR "PART_FLG      : $$dieinfo{$die}{PART_FLG} \n";
            print PTR "NUMBER OF TEST: $$dieinfo{$die}{NUM_TEST} \n";
            print PTR "HARD_BIN      : $$dieinfo{$die}{HARD_BIN} \n";
            print PTR "SOFT_BIN      : $$dieinfo{$die}{SOFT_BIN} \n";
            print PTR "X_COORD       : $$dieinfo{$die}{X_COORD} \n";
            print PTR "Y_COORD       : $$dieinfo{$die}{Y_COORD} \n";
            print PTR "TIME_T        : $$dieinfo{$die}{TIME_T} \n";
            print PTR "Part_id       : $die \n";

            print PTR "\n********** BC_DATA ***********\n";
            $tstout = $$dieinfo{$die}{TEST_RESULT};
            foreach $tst_no (sort by_number keys %$tstout) {
                    print PTR "***** BC_PTR1 *****\n";
                    print PTR "Test Number   : $tst_no \n";
                    print PTR "HEAD_NUM      : $$tstout{$tst_no}{HEAD_NUM} \n"; 
                    print PTR "SITE_NUM      : $$tstout{$tst_no}{SITE_NUM} \n";
                    print PTR "RESULT        : $$tstout{$tst_no}{RESULT} \n";
                    print PTR "TEST_FLG      : $$tstout{$tst_no}{TEST_FLG} \n";
                    print PTR "PARM_FLG      : $$tstout{$tst_no}{PARM_FLG} \n";
                    print PTR "PEDDING       : $$tstout{$tst_no}{PEDDING} \n";
            }
    }

    print PTR "\n\n********** BC_SUMMARY **********\n\n";
    print PTR "     ***** BC_WRR_PCR *****\n";
    my $smmry = $rawdata{$wf_no}{SMMRY_TST};
    print PTR "Finish Time   : $$smmry{$wf_no}{FINISH_TM}\n";
    print PTR "Part Count    : $$smmry{$wf_no}{EXECUTED_CNT}\n";
    print PTR "Retest Count  : $$smmry{$wf_no}{RTST_CNT}\n";
    print PTR "Abort Count   : $$smmry{$wf_no}{ABRT_CNT}\n";
    print PTR "Good Count    : $$smmry{$wf_no}{GOOD_CNT}\n";

    my $sbincnt = $$smmry{$wf_no}{SBIN_CNT};
    print PTR "\n     ***** BC_SBR *****\n";
    foreach $sbinno (sort by_number keys %$sbincnt) {
            printf PTR (" %3d",$$sbincnt{$sbinno});
            if($sbinno%20 == 0) {
               print PTR "\n";
            }
    }

    my $hbincnt = $$smmry{$wf_no}{HBIN_CNT};
    print PTR "\n\n     ***** BC_HBR *****\n";
    foreach $hbinno (sort by_number keys %$hbincnt) {
            printf PTR (" %3d",$$hbincnt{$hbinno});
            if($hbinno%20 == 0) {
               print PTR "\n";
            }
    }

    print PTR "\n";
    my $tst_sum = $$smmry{$wf_no}{TEST_SUM};
    foreach $tst_id (sort by_number keys %$tst_sum) {
            print PTR "\n     ***** BC_TSR *****\n";
            print PTR "TEST NUMBER   : $tst_id \n";
            print PTR "TEST PAD      : $$tst_sum{$tst_id}{TEST_PAD}\n";
            print PTR "Execution Count: $$tst_sum{$tst_id}{EXEC_CNT}\n";
            print PTR "Fail Count    : $$tst_sum{$tst_id}{FAIL_CNT}\n";
            print PTR "Alrm_Count    : $$tst_sum{$tst_id}{ALRM_CNT}\n";
            print PTR "Test Name     : $$tst_sum{$tst_id}{TEST_NAME}\n";
            print PTR "Sequence Name : $$tst_sum{$tst_id}{SEQ_NAME}\n";
            print PTR "Test Minimum  : $$tst_sum{$tst_id}{TEST_MIN}\n";
            print PTR "Test Maximum  : $$tst_sum{$tst_id}{TEST_MAX}\n";
            print PTR "Test SUM      : $$tst_sum{$tst_id}{TEST_SUM}\n";
            print PTR "Test Sqrs     : $$tst_sum{$tst_id}{TEST_SQRS}\n";
    }

    if ($$lot_tmp{$wf_no}{NAM} eq "Y") {
        my $wf_map = $rawdata{$wf_no}{NAM_DATA};
        print PTR "\n\n********** BC_NAM **********\n";
        print PTR "Lot Number    : $$wf_map{$wf_no}{LOT_NM}\n";   
        print PTR "Wafer Number  : $wf_no \n";
        print PTR "Total counted wafer: $$wf_map{$wf_no}{TOT_CNT_WAFER} \n";
        print PTR "Rows          : $$wf_map{$wf_no}{ROWS} \n";
        print PTR "Columns       : $$wf_map{$wf_no}{COLUMNS} \n";
        print PTR "Product       : $$wf_map{$wf_no}{PRODUCT} \n";
        print PTR "Convert Time  : $$wf_map{$wf_no}{CONVERT_TM} \n";
        print PTR "Total Die     : $$wf_map{$wf_no}{TOTAL_DIE} \n\n";

        my $mpdata = $$wf_map{$wf_no}{MAP_DATA};
        foreach $mp_cnt (sort by_number keys %$mpdata) {
                printf PTR ("%2d ",$$mpdata{$mp_cnt});
                if ($mp_cnt%$$wf_map{$wf_no}{ROWS} eq 0 ) {
                   print PTR "\n";
                }
        }

        print PTR "\n\n***** BIN SUMMARY *****\n";
        my $bin_rlt = $$wf_map{$wf_no}{BIN_RLT} ;
        foreach $bin_no (sort by_number keys %$bin_rlt) {
                printf PTR ("BIN %2d : %d \n", $bin_no,$$bin_rlt{$bin_no}); 
        }
        print PTR "Wafer Size    : $$mpdata{$wf_no}{WAFER_SIZE} \n";
        print PTR "Wafer Fat     : $$mpdata{$wf_no}{WAFER_FAT} \n";
        print PTR "X_Size        : $$mpdata{$wf_no}{X_SIZE} \n";
        print PTR "Y_Size        : $$mpdata{$wf_no}{Y_SIZE} \n";
        print PTR "Oper Name     : $$mpdata{$wf_no}{OPER_NAME} \n";
        print PTR "Tester System ID : $$mpdata{$wf_no}{TST_SYSTM_ID} \n";
        print PTR "Prober Type   : $$mpdata{$wf_no}{PROBE_TYP} \n";
        print PTR "System ID     : $$mpdata{$wf_no}{SYSTEM_ID} \n";
        print PTR "Station NO    : $$mpdata{$wf_no}{STATION_NO} \n";
        print PTR "PAD Data      : $$mpdata{$wf_no}{PAD_DATA} \n";
        print PTR "Test PGM NO   : $$mpdata{$wf_no}{TEST_PGM_NO} \n";
        print PTR "Prober Card ID: $$mpdata{$wf_no}{PROB_CARD_ID} \n";
        print PTR "Cable ID      : $$mpdata{$wf_no}{CABLE_ID} \n";
        print PTR "Load ID       : $$mpdata{$wf_no}{LOAD_ID} \n";
        print PTR "Soft Rev.     : $$mpdata{$wf_no}{SOFT_REV} \n";
    }
    else {
       print PTR "\n\n### Nam File does not exist\n";
    }

    print "Print Mood Only \n";
    close(PTR);
}

sub TakeTime {
    my ($bitstr)=@_;
    my $Decimal = reverse($bitstr);
    $Decimal = BinToDec($Decimal);
    return($Decimal);
}

 
sub BinToDec {
    my ($bincod)=@_;
    my $lngbin = length($bincod);
    my ($value,$flg,$i)  = "";
    for($i=0;$i < $lngbin;$i++) {
        $flg   = substr($bincod,$lngbin-$i-1,1);
        $value += (2**$i)*$flg;
    }
    my $cdlng = length($value);
    if($cdlng%2 eq 1) {
       $value = "0".$value;
    }
    return($value);
}

sub by_number
{
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

sub get_sastime {
    my ($read_tm) = @_;
    my $sastime = "";    ## Modify by SJ Hwang  2003.11.07

    my $sub_read_tm = substr($read_tm,0,1);   ## Modify by SJ HWANG  2004.03.08
                                              ## If time value is "0000000000" then SKIP  
    
    if (($read_tm ne "")&&($sub_read_tm eq "2")) {
       my $year    = substr($read_tm,0,4);
       my $month   = substr($read_tm,4,2);
       my $day     = substr($read_tm,6,2);
       my $hour    = substr($read_tm,8,2);
       my $minute  = substr($read_tm,10,2);
       my $second  = substr($read_tm,12,2);
       $sastime = timegm($second,$minute,$hour,$day,$month-1,$year);
       
    }
    else {
       $sastime = ""; 
    }
    
    return($sastime);
}

## For AUTO TESTPLAN --------------------------------------------------------------------------

sub Look_For_Testplan
{
        my ($TESTPLAN, $REV) = @_;

	#FMFM50 Development Server
	#$SERVER   = "SYB_EWBDEV1";
        #$DATABASE = "edb_bctest1_v22";
	#$USERNAME = "EDB_GUEST";
	#$PASSWORD = "dryheave";

	#FPMEWB2 Production Server
        $SERVER   = $ENV{EDB_SERVER};
        $DATABASE = $ENV{EDB_DATABASE};
        $USERNAME = $ENV{EDB_USERNAME};
        $PASSWORD = $ENV{EDB_PASSWORD};
        $STATUS   = 0;

        $Tdbh = Sybase::CTlib->ct_connect($USERNAME, $PASSWORD, $SERVER);

        if (!(defined($Tdbh)) || length($Tdbh) == 0)
        {
                print "ERROR\n";
                exit 1;
        }

	my $cmd = "";
	$cmd ="select test_plan from ${DATABASE}..test_plan where test_plan = UPPER('$TESTPLAN') AND test_plan_rev = '$REV'";
        $STATUS = $Tdbh->ct_execute($cmd) or die "execute failed!";

        while(($rc = $Tdbh->ct_results($restype)) == CS_SUCCEED)
        {
                if ($restype == CS_CMD_DONE)
                {
                        my $ROWCOUNT = 0;
                        $ROWCOUNT = $Tdbh->ct_res_info(CS_ROW_COUNT);

                        if ($ROWCOUNT == 0)
                        {
                                #print "Test Plan: $TESTPLAN, Rev: $REV  is NOT loaded into the $DATABASE Database\n";
							&CreateTestPlan_STDF();
						}
						elsif ($ROWCOUNT > 0)
                        {
                                #print "Test Plan: $TESTPLAN, Rev: $REV  is loaded into the $DATABASE Database\n";
                        }
                        next;
                }

		while(@dat = $Tdbh->ct_fetch)
                {
                }
        }

        close Tdbh;
}


#########################
# OUTPUT "STDF" TESTPLAN
#########################
sub CreateTestPlan_STDF
{
        ##########################
        # ASSIGN TESTPLAN FILENAME
        ##########################
        my $path_to_file = dirname($file); 
        $tp_filename     = "$path_to_file/${job_name}_${job_rev}_${envname}.TP";
        open FH, ">$tp_filename" or die "error msg: $!";


        #############
        # EMIR RECORD
        #############
        %out::emir              = %{$out::init{emir}};
        $out::emir{mode_cod}    = "C";
        $out::emir{setup_t}     = stdf_time();
        $out::emir{start_t}     = stdf_time();
        $out::emir{job_nam}     = $job_name;
        $out::emir{job_rev}     = $job_rev;
        $out::emir{spec_nam}    = $job_name;
        $out::emir{spec_rev}    = $job_rev;
        $out::emir{spec_rev}    = pad($out::emir{spec_rev},"\0");
        print FH &out::pack_EMIR(\%out::emir);


        ##############
        # EPDR RECORD
        ##############
	my %loc_hbin = ();
	for (my $n = 1 ; $n <= $at_PTR_Cnt ; $n++)
        {
                ### EXCLUDE TESTS WITHOUT ASSIGNED PARAMETER NAME ###
                next if $at_test_spec{$n}{TEST_NO} !~ /\d+/ || $at_test_spec{$n}{TEST_NAME} eq "";

		### RETAINED ORIG CODE (START) ###
		my $valid_limit_check = 0;
		if ($at_test_spec{$n}{LO_SPEC} > -1e+21) # Added by SJ Hwang  2005.08.25
                {
                	$at_test_spec{$n}{LO_SPEC} = sprintf("%40.30f", $at_test_spec{$n}{LO_SPEC});
                        $valid_limit_check++;
                }
		$at_test_spec{$n}{LO_SPEC} = substr($at_test_spec{$n}{LO_SPEC}, 0, 40);
		 
		if ($at_test_spec{$n}{HI_SPEC} < 1e+21) # Added by SJ Hwang  2005.08.25
                {
                        $at_test_spec{$n}{HI_SPEC} = sprintf("%40.30f", $at_test_spec{$n}{HI_SPEC});
                        $valid_limit_check++;
                }
                $at_test_spec{$n}{HI_SPEC} = substr($at_test_spec{$n}{HI_SPEC}, 0, 40);


		### COMPUTE FOR CENSOR LIMITS ###
		my $at_valid_low  = -1E+21;
		my $at_valid_high =  1E+21;
		if ($valid_limit_check == 2)
                {
			$at_valid_low  = ( $at_test_spec{$n}{LO_SPEC} - ( ( $at_test_spec{$n}{HI_SPEC} - $at_test_spec{$n}{LO_SPEC} ) * 4 ) );
			$at_valid_high = ( $at_test_spec{$n}{HI_SPEC} + ( ( $at_test_spec{$n}{HI_SPEC} - $at_test_spec{$n}{LO_SPEC} ) * 4 ) );
                }
		### RETAINED ORIG CODE (END) ###
		

		### GET UNIQUE HBIN NUMBER AND NAME ###
		if (! exists($loc_hbin{$at_test_spec{$n}{HW_BIN}}))
		{
			$loc_hbin{$at_test_spec{$n}{HW_BIN}} = uc $at_test_spec{$n}{HW_BIN_NAME};
		}


                %out::epdr           = %{$out::init{epdr}};
                $out::epdr{test_num} = $at_test_spec{$n}{TEST_NO};
                $out::epdr{units}    = $at_test_spec{$n}{UNIT};
                $out::epdr{lo_limit} = $at_test_spec{$n}{LO_SPEC};
                $out::epdr{hi_limit} = $at_test_spec{$n}{HI_SPEC};
                $out::epdr{lo_censr} = $at_valid_low;
                $out::epdr{hi_censr} = $at_valid_high;
                $out::epdr{test_nam} = uc $at_test_spec{$n}{TEST_NAME};
                $out::epdr{sbin_num} = $at_test_spec{$n}{HW_BIN};
                $out::epdr{sbin_nam} = $loc_hbin{$at_test_spec{$n}{HW_BIN}};
                $out::epdr{hbin_num} = $at_test_spec{$n}{HW_BIN};
                $out::epdr{hbin_nam} = $loc_hbin{$at_test_spec{$n}{HW_BIN}};
                $out::epdr{opt_flg}  = 00000000;
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


########################
# OUTPUT "DAT" TESTPLAN 
# (DEPRECATED)
########################
sub CreateTestPlan_DAT
{
        ## Get System Name
    my $valid_limit_check = 0;    
    my $tpfilename = "";
        
	@f_list = split (/\//, $ARGV[0]);
	foreach $_ (@f_list)
	{
		$f = $_;
	}

        # DEVICE CODE
        $at_device=$part_type;
        #$at_device=~ s/^\s+|\s+$//g;

        # PROGRAM
        $at_program=$job_name;

        # REVISION
        $at_revision=$job_rev;

        ## Create Testplan File
	$at_date = `date +%Y%m%d%H%M%S`;
	$at_date = substr $at_date, 0, 14;
        $at_outfile = $at_program."_$at_revision.DAT";
        $tpfilename = "/data/edbbk/db_areas/edb_bcsort_v22/converter/in/".$at_outfile;
                
        if( -e $tpfilename ) { 
        	print "$tpfilename is a directory.\n"; 
        }
        else {
        
	        open (ATOUT, ">$at_outfile");
	
		# COLUMN LENGTH : 20,15,15,20
	        print ATOUT " DEVICE               SYSTEM          PROGRAM         REVISION\n";
	        print ATOUT " -------------------- --------------- --------------- --------------------\n";
	
	        # Fitting length
	        while (length($at_device) < 20){
	                $at_device = $at_device." ";
	        }
	        while (length($at_system) < 15){
	                $at_system = $at_system." ";
	        }
	        while (length($at_program) < 15){
	                $at_program = $at_program." ";
	        }
	        while (length($at_revision) < 20){
	                $at_revision = $at_revision." ";
	        }
	
	        print ATOUT " $at_device $at_system $at_program $at_revision\n\n";
	        #write(ATOUT);
	
	        # COLUMN LENGTH : 15,7,25,8,9,15,15,15,15,9,15,9,15,7,8,20,20,50
	        print ATOUT " PROGRAM         TEST_NO TEST_NAME                 UNIT     TEST_TYPE VALID_LOW       ";
	        print ATOUT "VALID_HIGH      SPEC_LOW                                 SPEC_HIGH                                ";
	        print ATOUT "SW_BIN_NO SW_BIN_NAME     HW_BIN_NO HW_BIN_NAME     CONTROL CRITICAL PINS                 ";
	        print ATOUT "VCC                  REMARK                                            \n";
	        print ATOUT " --------------- ------- ------------------------- -------- --------- ---------------------------------------- ";
	        print ATOUT "---------------------------------------- ---------------------------------------- ---------------------------------------- ";
	        print ATOUT "--------- --------------- --------- --------------- ------- -------- -------------------- ";
	        print ATOUT "-------------------- --------------------------------------------------\n";
	
	        for ($n = 1 ; $n <= $at_PTR_Cnt ; $n++)
	        {
	                $at_testno     = 0;
	                $at_testname   = "";
	                $at_unit       = "";
	                $at_spec_low   = 0;
	                $at_spec_high  = 0;
	                $at_hwbin_name = "";
	                $valid_limit_check = 0;
	
	                $at_testno     = $at_test_spec{$n}{TEST_NO};
	                $at_unit       = $at_test_spec{$n}{UNIT};
	                $at_hwbin      = $at_test_spec{$n}{HW_BIN};
	                $at_hwbin_name = $at_test_spec{$n}{HW_BIN_NAME};
	                $at_swbin_name = $at_test_spec{$n}{SW_BIN_NAME};
	                $at_testname   = $at_test_spec{$n}{TEST_NAME};
	                $at_spec_low   = $at_test_spec{$n}{LO_SPEC};
	
	                if ($at_spec_low > -1e+21) # Added by SJ Hwang  2005.08.25
	                {
	                	$at_spec_low = sprintf("%40.30f",$at_spec_low);
	                	$valid_limit_check++;    
	                }	
	                $at_spec_low   = substr($at_spec_low, 0, 40);
	                $at_spec_high  = $at_test_spec{$n}{HI_SPEC};
	                if ($at_spec_high < 1e+21) # Added by SJ Hwang  2005.08.25
	                {
	                	$at_spec_high = sprintf("%40.30f",$at_spec_high);
	                	$valid_limit_check++;    
	                }	
	                $at_spec_high  = substr($at_spec_high, 0, 40);
	
					# 김형선대리 요청건으로 VALID LIMIT 계산식 적용 2005.09.27 Modified by SJ Hwang
					# Low-High Limit Spec 존재시 Valid Limit 산출하고 그외는 Default 값 (-1E+21, 1E+21)
					# VALID Limit Low : Spec_Low - (Spec_High  - Spec_Low) * 4
					# VALID Limit High: Spec_High + (Spec_High  - Spec_Low) * 4
	              
					if ($valid_limit_check == 2)
					{
						$at_valid_low  = ( $at_spec_low - ( ( $at_spec_high - $at_spec_low ) * 4 ) );
						$at_valid_high = ( $at_spec_high + ( ( $at_spec_high - $at_spec_low ) * 4 ) );
					}
					else
					{
						$at_valid_low = -1E+21 ;
						$at_valid_high = 1E+21 ;	
					}
	
	                #print ATOUT "$at_program $at_testno $at_testname $at_unit $at_null $at_null $at_null ";
	                #print ATOUT "$at_spec_low $at_spec_high $at_testno $at_swbin_name $at_hwbin $at_hwbin_name\n\n";
	                write(ATOUT);
	        }
	
	        close (ATOUT);
	}
}
                              
