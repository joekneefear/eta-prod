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
# 05 Jul  2005  SJ Hwang        Added to delete the "S" character in the lot name of the discrete product.
# 05 Aug  2005  SJ Hwang        Remove the changing bin number.
# 25 Jun  2010  Zed Hwang       Modify the creation for out file name
# 27 Aug  2012  Reuben Capio    MFT Conversion
# 05 Nov  2013  Eric Alfanta    Return no_lotid subdir for MFT.
# 02 Oct  2014  Gilbert Miole   Set the EMIR.LOT_TYPE to blank (" ").
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
use Getopt::Long              ;

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

my $FILENAME="";
my ($i,$key)="";
my ($week,$month,$day,$tmp,$year)=split(/\s+/,localtime());
my ($hour,$minute,$second)=split(/:/,$tmp);
my ($wafer_no,$key,$lot_len)=0;
my ($tmp_lot,$lot_no,$job_name,$job_name_old,$tmp_str)="";
my ($filename1, $filename2) = "";
my %tst_rlt ;
my $file          = "";
my $plant         = uc($ENV{ENV_FACILITY});     ### MFT ENV VAR
my $env_mod       = "";
my $mft_flag      = ($^O=~/linux/i) ? 1 : 0; 	### SET 0=OTHERS; 1=LINUX/MFT
my $print         = "";

#print "Current Time: $year.$month.$day.$tmp \n"; #COMMENTED OUT FOR MFT
# param set 2002/11/18



######################
# RETRIEVE PARAMETERS
######################
$result = GetOptions ("infile=s"  => \$file,
                      "plant=s"   => \$plant,		 
                      "print=s"   => \$print);
require $env_mod if $env_mod ne "";               ### LOAD OPTIONAL MODULE

$FILENAME=$file;     #Target File Name;  


if(!-e $FILENAME || $file eq '') { 
        print "syntax\n";
        print "\tscript -infile=<datalog file> -plant=<PLANT>(opt) -print=1(opt)\n";
        exit(1);
}
else {
        #print "Input File: $FILENAME \n"; #COMMENTED OUT FOR MFT
}

($filename1, $filename2)=split(/\./,$file);

%tst_rlt=ReadFile($FILENAME); ## Reading the Result File;   

if($print == 1) {        ## Printing Mood;
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
   
#   my $outfile  = $lot_no."_".$wafer_no."_STDF";   ## File name for STDF+ ##
   my $time = time();
#   my $outfile  = $lot_no."_".$sblot_id."_".$job_name."_".$time."_STDF";   ### by Rodney Cyr 20030801
   #my $outfile  = $filename1."_BCET.TD";
   my $outfile  = "${file}.TD";
   $outfile =~ s/\-/\_/;       # 2004. 07. 15 SJ Hwang  Remove the special character in lot name.
   $outfile =~ s/\s+//;        # 2005. 03. 18 SJ Hwang  Remove the space character in lot name.
   my $OUTFLE   = $outfile;

   my $SSWB_CNT = 0;
   my $SHWB_CNT = 0;
   my $WSUM_CNT = 0;
   my $WSWB_CNT = 0;
   my $WHWB_CNT = 0;
   my $PSUM_CNT = 0;
   my $PRES_CNT = 0;

   open(OUT,">$OUTFLE");                           ## Open the Output File ##
   #print "$OUTFLE is opened \n"; #COMMENTED OUT FOR MFT


   #########################################################
   ###   Write the EMIR Record                           ###
   #########################################################
   %out::emir = %{$out::init{emir}};
   $out::emir{mode_cod} = "P";    ##"P" for Production;
   $out::emir{stat_num} = $$lot_head{$wafer_no}{STATION};

#   print "SETUP_TIME:$$lot_head{$wafer_no}{SETUPTIME}\n";
#   print "START_TIME:$$lot_head{$wafer_no}{STARTTIME}\n";

   $out::emir{setup_t}  = get_sastime($$lot_head{$wafer_no}{SETUPTIME});
   $out::emir{start_t}  = get_sastime($$lot_head{$wafer_no}{STARTTIME});

   
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
   $out::emir{lot_type} = "";    ##"P" for Production;
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
           #print "x=$$die_info{$part_id}{X_COORD} \n\ty=$$die_info{$part_id}{Y_COORD}\n\tpart=$part_id\n\n";
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
   #print "$OUTFLE is closed \n"; #COMMENTED OUT FOR MFT

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

   &out::update_EMIR(\%out::emir, $outfile) ;

   print "td=$OUTFLE \n";
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
      $out::emir{lot_type} = "";    ##"P" for Production;
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
      #print "$OUTFLE is closed \n"; #COMMENTED OUT FOR MFT
      print "td=$OUTFLE \n";
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
    #print "FILE NAME:$file_name \n"; #COMMENTED OUT FOR MFT
    my $lot_id    = $parameter[3];
    
    # delete the "S" character in the lot name of the discrete product.
    $tmp_lot = substr($lot_id,0,1);
    if ($tmp_lot eq "S")
    {
    	$lot_len = length($lot_id);
    	$lot_id = substr($lot_id,1,$lot_len);
	}
        
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
    read FLE,$str,1;
    $mode_cod = unpack("C",$str);
    read FLE,$str,2;
    $spec_cnt = char2short(reverse($str),"S");
    read FLE,$str,2;
    $map_cnt  = char2short(reverse($str),"S");
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

    # delete the "S" character in the lot name of the discrete product.
    $tmp_lot = substr($lot_id,0,1);
    if ($tmp_lot eq "S")
    {
    	$lot_len = length($lot_id);
    	$lot_id = substr($lot_id,1,$lot_len);
	}

    read FLE,$str,20;
    $part_type= unpack("A20",$str);
    
    # delete the "S" character in the part name of the discrete product.
    $tmp_lot = substr($part_type,0,1);
    if ($tmp_lot eq "S")
    {
    	$lot_len = length($part_type);
    	$part_type = substr($part_type,1,$lot_len);
	}
    
    read FLE,$str,20;
    $node_name= unpack("A20",$str);
    read FLE,$str,10;
    $tstr_typ = unpack("A10",$str);
    read FLE,$str,10;
    $job_name = unpack("A10",$str);
    $job_name =~ s/\-/\_/g;

    read FLE,$str,10;
    $job_rev  = unpack("A10",$str);

#   김형선대리 요청으로 입력된 REVISION을 사용하기로 함.
#    if($job_rev !=~/^[a-zA-Z]e/)   # 2003/1/28 append float to decimal and not char 
#    {
#        $job_rev  = sprintf("%d", $job_rev);
#    }
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
    $wafr_siz = char2float(reverse($str));

    read FLE,$str,4;
    $die_ht = char2float(reverse($str));

    read FLE,$str,4;
    $die_width = char2float(reverse($str));

    read FLE,$str,10;
    $wf_units = unpack("A10",$str);

    read FLE,$str,1;
    $wf_flat  = unpack("A",$str);

    read FLE,$str,1;
    $pedding=unpack("C",$str);

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
        SPEC_NAM  => $spec_nam,
        SPEC_VER  => $spec_ver,
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
    for($i=1;$i<=$spec_cnt;$i++) {
       read FLE,$str,4;
       $test_no = char2long(reverse($str));

       read FLE,$str,2;
       $res_scal = char2short(reverse($str),"s");    # modified unsigned short -> short

       read FLE,$str,2;
       $llm_scal = char2short(reverse($str),"s");    # modified unsigned short -> short

       read FLE,$str,2;
       $hlm_scal = char2short(reverse($str),"s");    # modified unsigned short -> short

       read FLE,$str,10;
       $units = unpack("A10",$str);

       read FLE,$str,4;
       $lo_limit = char2float(reverse($str));

       read FLE,$str,4;
       $hi_limit = char2float(reverse($str));

       read FLE,$str,4;
       $lo_spec = char2float(reverse($str));

       read FLE,$str,4;
       $hi_spec = char2float(reverse($str));

       read FLE,$str,20;
       $test_text = unpack("A20",$str);
       
       read FLE,$str,1;                         # appended field - skip
       read FLE,$str,1;                         # appended field - skip
       read FLE,$str,18;                        # appended field - skip       

       ###############################################
       ###      Read TRR                           ###
       ###############################################
       read FLE,$str,2;
       $item_code=char2short(reverse($str),"S");

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
   
       read FLE,$str,10;
       $bias2_unit = unpack("A10",$str);

       read FLE,$str,10;
       $timec_unit = unpack("A10",$str);

       read FLE,$str,2;
       $pedding2 = unpack("A2",$str);

       read FLE,$str,4;
       $bias1_value = char2float(reverse($str));

       read FLE,$str,4;
       $bias2_value = char2float(reverse($str));

       read FLE,$str,4;
       $timec_value = char2float(reverse($str)); 


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
       $head_num = char2short(reverse($str),"S");

       read FLE,$str,2;
       $site_num = char2short(reverse($str),"S");

       read FLE,$str,2;
       $num_test = char2short(reverse($str),"S");
 
       read FLE,$str,2;
       $hard_bin = char2short(reverse($str),"S");
 
       read FLE,$str,2;
       $soft_bin = char2short(reverse($str),"S");

       read FLE,$str,2;
       $x_coord = char2short(reverse($str),"s");

       read FLE,$str,2;
       $y_coord = char2short(reverse($str),"s");

       read FLE,$str,2;
       $pedding = unpack("C",$str);

       read FLE,$str,4;
       $test_t = char2long(reverse($str));

       read FLE,$str,20;           ## Modified by SJ HWANG  2003. 12. 01
#       $part_id = unpack("A20",$str);
       $part_id = $i;

       read FLE,$str,1;
       $part_flg = unpack("b16",reverse($str));

       read FLE,$str,3;
       $pedding2 = unpack("A2",$str);           

       for ($j=1;$j<=$num_test;$j++) {
           read FLE,$str,4;
           $test_no=char2long(reverse($str));

           read FLE,$str,2;
           $head_num=char2short(reverse($str),"S"); 

           read FLE,$str,2;
           $site_num=char2short(reverse($str),"S");

           read FLE,$str,4;
           $result=char2float(reverse($str));

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
    $executed_cnt = char2long(reverse($str));
    read FLE,$str,4;
    $rtst_cnt = char2long(reverse($str));    
    read FLE,$str,4;
    $abrt_cnt = char2long(reverse($str));
    read FLE,$str,4;
    $good_cnt = char2long(reverse($str));


    ###############################################
    ###      Read BC_SBR                        ###
    ###############################################
    for($i=1;$i<=256;$i++) { #Reading the information of Software bin counter.
       read FLE,$str,4;
       $sbin_cnt{$i} = char2long(reverse($str));
    }
   
#    Modified by SJ Hwang 2005.08.05
# 
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
       $hbin_cnt{$i} = char2long(reverse($str));
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
       $test_number = char2short(reverse($str));
       read FLE,$str,2;
       $test_pad    = unpack("A2",$str);
       read FLE,$str,4;
       $exec_cnt    = char2long(reverse($str));
       read FLE,$str,4;
       $fail_cnt    = char2long(reverse($str));
       read FLE,$str,4;
       $alrm_cnt    = char2long(reverse($str));
       read FLE,$str,4;
       $test_min    = char2float(reverse($str));
       read FLE,$str,4;
       $test_max    = char2float(reverse($str));
       read FLE,$str,4;
       $test_sums   = char2float(reverse($str));
       read FLE,$str,4;
       $test_sqrs   = char2float(reverse($str));
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
    if($isnam eq "Y") { ## Reading NamData
        read FLE,$str,20;
        $lot_nm = unpack("A20",$str);
        read FLE,$str,2;
        $wafer_no = char2short(reverse($str),"S");
        read FLE,$str,2;
        $tot_cnt_wafer = char2short(reverse($str),"S");
        read FLE,$str,2;
        $rows = char2short(reverse($str),"S");
        read FLE,$str,2;
        $columns = char2short(reverse($str),"S");
        read FLE,$str,20;
        $product = unpack("A20",$str);
        read FLE,$str,4;      ## Probe Start TIME ##
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
        $prb_tm=$year.$month.$day.$hour.$minute.$second; 

        read FLE,$str,4;      ## Conversion Time ## 
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
        $convert_tm=$year.$month.$day.$hour.$minute.$second;

        read FLE,$str,2;
        $total_die = char2short(reverse($str),"S");

        for($i=0;$i<33;$i++) {
            read FLE,$str,2;
            $bin_rlt{$i}=char2short(reverse($str),"S");
        } ##for-i end;

        read FLE, $str,2;
        $wafer_size=char2short(reverse($str),"S");
        read FLE,$str,2;
        $wafer_fat = char2short(reverse($str),"S");
        read FLE,$str,4;
        $x_size = char2float(reverse($str));
        read FLE,$str,4;
        $y_size = char2float(reverse($str));
        read FLE,$str,20;
        $oper_name = unpack("A20",$str);
        read FLE,$str,20;
        $tst_systm_id=unpack("A20",$str); 
        read FLE,$str,20;
        $probe_typ = unpack("A20",$str);
        read FLE,$str,20;
        $system_id = unpack("A20",$str);
        read FLE,$str,2;
        $station_no = char2short(reverse($str),"S");
        read FLE,$str,2;
        $pad_data = char2short(reverse($str),"S");
        read FLE,$str,20;
        $test_pgm_nm = unpack("A20",$str);
        read FLE,$str,20;
        $prob_card_id=unpack("A20",$str);

        read FLE,$str,20;
        $cable_id = unpack("A20",$str);
        read FLE,$str,20;
        $load_nm = unpack("A20",$str);
        read FLE,$str,20;
        $softrev = unpack("A20",$str);
        
        $map_count = 1;
        for($i=1;$i<=$rows;$i++) {
            for($j=1;$j<=$columns;$j++) {
                read FLE, $str,1;
                $map_data{$map_count}=unpack("c",$str);
                $map_count++;
            } ##for-j end;
        } ##for-i end;

        $nam_data{$wafer_id}={
            LOT_NM        => $lot_nm,
            TOT_CNT_WAFER => $tot_cnt_wafer,
            ROWS          => $rows,
            COLUMNS       => $columns,
            PRODUCT       => $product,
            PRB_TM        => $prb_tm, 
            CONVERT_TM    => $convert_tm,
            TOTAL_DIE     => $total_die,
            BIN_RLT       => {%bin_rlt},
            WAFER_SIZE    => $wafer_size,
            WAFER_FAT     => $wafer_fat,
            X_SIZE        => $x_size,
            Y_SIZE        => $y_size,
            OPER_NAME     => $oper_name,
            TST_SYSTM_ID  => $tst_systm_id,
            PROBE_TYP     => $probe_typ,
            SYSTEM_ID     => $system_id,
            STATION_NO    => $station_no,
            PAD_DATA      => $pad_data,
            TEST_PGM_NO   => $test_pgm_no,
            PROB_CARD_ID  => $prob_card_id,
            CABLE_ID      => $cable_id,
            LOAD_ID       => $load_nm,
            SOFT_REV      => $soft_rev,
            MAP_DATA      => {%map_data} 
        };

    } ## If end;

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


sub char2short
{
        my $IN     = shift;
	my $format = shift;
        @b = unpack "c" x 2, $IN;

        $ret = unpack $format, (pack "cc", $b[0], $b[1]); 
        return $ret;
}


sub char2float
{
        my ($IN) = @_;
        @b = unpack "c" x 4, $IN;
        $ret = unpack "f", (pack "cccc", $b[3], $b[2], $b[1], $b[0]) if $mft_flag==0;
        $ret = unpack "f", (pack "cccc", $b[0], $b[1], $b[2], $b[3]) if $mft_flag==1;
        return $ret;
}


sub char2long
{
        my ($IN) = @_;
        @b = unpack "c" x 4, $IN;
        $ret = unpack "L", (pack "cccc", $b[3], $b[2], $b[1], $b[0]) if $mft_flag==0;
        $ret = unpack "L", (pack "cccc", $b[0], $b[1], $b[2], $b[3]) if $mft_flag==1;
        return $ret;
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
        system "mv $file $loc_dir";
        if (! -e "${loc_dir}/${fn}")
        {
                print "Failed to move $loc_file to $loc_dir dir. $!\n";
                exit 1;
        }
}
