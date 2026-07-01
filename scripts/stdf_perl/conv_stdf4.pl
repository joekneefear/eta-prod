#!/usr/bin/perl
#
# DATE     WHO             COMMENTS
# -------- --------------- ----------------------------------------------------
# 12/05/12 Ben Rommel Kho  Cloned from Shibasoku and modified as master script
# 2013/08/13 Rodney Cyr    Print TP= only if a testplan is created. 
#                          Create SBR/HBR records for all possible bins.
# 2013/09/17 Rodney Cyr    Added variable to set test name to sequence name from TSR.
#                          Added variable to set SW Bins from TSR bin counts.
# 2014/04/02 Rodney Cyr    Added Probe Card to EMIR.
# 2014/10/10 Eric Alfanta  Added lot_type var and set it to blank.
# 2016/05/16 Eric Alfanta  Skip part if x/y coordinates is +/-5000
# 2016/05/27 Eric	   Added bin names in eprr record. 
# 2016/08/19 Gilbert Miole Skip part if x/y coordinates is +/-5000 if wid > 0.
#			   EXIT IF REC_LEN IS ZERO and not rec_type 20_20.			   
# 2016/08/25 Gilbert Miole Exclude grav in base to unit conversion.
# 2016/10/27 Gilbert Miole Added option for MEMS product, unit "g" = "grav".
#
#
# FUNCTION: Reads part/die data from STDFv4 file to output STDFv3+ TD & TP files. 
#
#




#################
# LOAD LIBRARIES
#################
use Carp                        ;       # error messages - does not work within stdf_use.pl
use FindBin                     ;
use English                     ;
use lib "$FindBin::Bin"         ;       # set up path for libraries the same as script
use lib $ENV{'STDF_PERL_LIB'}   ;       # look for libraries in this directory
use Data::Dumper                ;
use Getopt::Long                ;
use File::Basename		;
use edb_defs			;
#use EDBUtil			;

require "stdf_use.pl"           ;       # libraries that are not generated



######################
# LOAD SPECIFICATIONS
######################
{
    package out ;
    if ( !eval(&::generate_all('stdfPL.spec')))
    {
       confess $@ ;
    }
    require 'stdfPL.pl' ;
}


##################################################
# VARIABLES
# NOTE: MIR DATA IS EXPOSED TO ENV_MOD AS $MIR{1}
##################################################
our $file          = "";
our $lotid         = "";
our %tp 	   = ();			#<-- EXPOSES EPDR DATA TO ENV_MOD
our $cfg_make_tp   = "Y";			#<-- GENERATE TESTPLAN. SET "N" TO DISABLE	 
our $tp_prefix     = "";			#<-- PREFIX TO ADD TO TESTPLAN NAME
our $td_filename   = "";			#<-- USE VARIABLE TO STORE TEST DATA FILENAME
our $tp_filename   = "";			#<-- USE VARIABLE TO STORE TESTPLAN FILENAME
our $test_mul      = 1000;			#<-- TEST NUMBER MODIFIER TO ADDRESS SBIN_NUMBER CONFLICT
our $use_seq_name  = "N";			#<-- USE TSR SEQUENCE NAME AS TEST NAME (WHEN CREATING TP)
our $swb_from_tsr  = "N";			#<-- USE TSR FAIL COUNT FOR SBIN COUNT
our $prbcard_from_suprnam  = "N";	        #<-- USE VALUE FROM MIR.SUPR_NAM FOR PROBE CARD
our $lot_type      = "";
my  $cpu_type      = "";
my  $plant         = uc($ENV{ENV_FACILITY});
my  $product       = "";
my  $env_mod       = "";			#<-- OPTIONAL ENV MODULE FOR CUSTOM ROUTINES
my  %rec_counter   = ();
my  $rec_keys      = "WAFER_ID|PART_ID|TEST_NUM|HBIN_NUM|SBIN_NUM";
my  %stdf_recs     = ();
my  %stdf_format   = ("B*1" => "B",
		      "B*n" => "B",
                      "C*1" => "A",
                      "C*n" => "A",
                      "I*1" => "c",
                      "I*2" => "s",
                      "R*4" => "f",
                      "U*1" => "C",
                      "U*2" => "S",
                      "U*4" => "L");


######################
# RETRIEVE PARAMETERS
######################
$result = GetOptions ("infile=s"   => \$file,
                      "plant=s"    => \$plant,
                      "env_mod=s"  => \$env_mod,
                      "product=s"  => \$product);
#require "$ENV{ENV_DB_SCRIPT}/$env_mod" if $env_mod ne "";               ### LOAD OPTIONAL MODULE
require "$env_mod" if $env_mod ne "";               ### LOAD OPTIONAL MODULE



#################
# DISPLAY SYNTAX
#################
if ($file eq "")
{
        print "syntax\n";
        print "\tscript -infile=<datalog file> -plant=<plant(opt)> -env_mod=env_mod.pm(opt)>\n";
        exit 1;
}


###################################
# LOAD STDFv4 TEMPLATE INTO A HASH
###################################
&load_stdfv4_template();


#######################
# PARSE STDFv4 DATALOG
#######################
&pre_parse_module()  if $env_mod ne "";     ### CALL FUNCTION FROM OPTIONAL MODULE
&parse_datalog();
&post_parse_module() if $env_mod ne "";     ### CALL FUNCTION FROM OPTIONAL MODULE


##################
# DATA VALIDATION
##################
#&data_validation();


#########################
# GENERATE TESTPLAN FILE
#########################
&create_tp() if $cfg_make_tp eq "Y";


########################
# GENERATE DATALOG FILE 
########################
&create_td();


########################
# RETURN CONVERTED FILE
########################
if ($cfg_make_tp eq "Y")
{
	print "\ntd=$td_filename tp=$tp_filename";
}
else
{
	print "\ntd=$td_filename";
}


exit 0;


#<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< SUBROUTINES >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>


#######################
# PARSE STDFv4 DATALOG
#######################
sub parse_datalog
{

	############
	# VARIABLES
	############
	my $rec_counter = "";
	my $rec_typ     = "";
	my $wid		= 0;
           $WIR{$wid}   = "";		### WAFERID=0 FOR F/T DATA

	####################
	# OPEN DATALOG FILE
	####################    
	open FH, $file or die "error msg: $!";


	##########################################
		# READ FAR FOR STDF FILE VERSION(REQUIRED)
	##########################################
	read FH, $in, 2;
	$rec_typ   = unpack_me(FH, "C", 1, "") . "_" . unpack_me(FH, "C", 1, "");
	$cpu_type  = unpack_me(FH, "C", 1, "");
	$stdf_ver  = unpack_me(FH, "C", 1, "");
	unless ($cpu_type =~ /[012]/ && $rec_typ eq "0_10")
	{
		print "\ndir=bad_file_format";                 ### RETURN BAD SUBDIR FOR MFT
				close FH;
				exit 100;
	}

	##################################
	# START PARSING DATA FILE CONTENT
	##################################
	LEVEL1: while (1)
	{
		#####################
		# READ RECORD HEADER 
		#####################
		my $rec_read = 0;	### HOLD THE NUMBER OF BYTES READ PER STDF REC
		my $rec_len  = unpack_me(FH, "S", 2, "");
		my $rec_typ  = unpack_me(FH, "C", 1, "") . "_" . unpack_me(FH, "C", 1, "");
		my $rec_name = $stdf_recs{$rec_typ}{NAME}||"";
		#print "parsing $rec_name\t$rec_typ rec_len=$rec_len\n";


		#######################################
		# EXIT IF REC_LEN IS ZERO. ASSUMES EOF
		#######################################
		last if $rec_len == 0 && $rec_typ != "20_20";                   


		###############################
		# SKIP UNWANTED STDFv4 RECORDS
		###############################
		if ($rec_name eq "")
		{
			#print "\tskipping $rec_typ\n";
			my $dummy1 = "";
			read FH, $dummy1, $rec_len;    
			next;
		}

		#########################
		# STORE DATA INTO A HASH
		#########################
		my %tmp     = ();
		my $rec_key = "";
		foreach my $line(split /\n/, $stdf_recs{$rec_typ}{FORMAT})
		{
			###############
			# FIELD FORMAT
			###############
			my ($fld_name, $fld_format, $v4_inv_val,$plus_inv_val) = split /\s+/, $line;
			my $value     = "";
			$fld_name     =~ s/ //g;
			$fld_len      =~ s/ //g;
			$v4_inv_val   =~ s/ //g;
			$plus_inv_val =~ s/ //g;
			
			###########################
			# TRAP UNKNOW FIELD FORMAT
			###########################
			if (exists($stdf_format{$fld_format}))
			{
				($junk, $fld_len) = split /\*/, $fld_format;
				$fld_format       =~ s/ //g;
				$fld_format       = $stdf_format{$fld_format};
			}
			else
			{
				print "Unknown format: ${rec_name}.${fld_name} \"$fld_format\"\n";
				exit 1;
			}
			
			##############
			# UNPACK DATA
			##############
			### FIXED REC LENGTH ###
			if ($fld_len =~ /\d+/)
			{
				$value = unpack_me(FH, $fld_format, $fld_len, $v4_inv_val, $plus_inv_val);
				$rec_read += $fld_len;
			}
			### VARIABLE REC LENGTH ###
			elsif ($fld_len eq "n")
			{
				$fld_len = unpack_me(FH, C, 1, "");
				$value   = unpack_me(FH, $fld_format, $fld_len, $v4_inv_val, $plus_inv_val);
				$rec_read += 1 + $fld_len;
			}
			#print "\t$fld_name\t$fld_format\t$fld_len\t$def_value\n";

			#########################
			# STORE DATA INTO A HASH
			#########################
			### UCASE BUT PTR.UNIT ###
			$value = uc($value) unless ($rec_name eq "PTR" && $fld_name eq "UNITS"); 
			$value =~ s/\s+/\_/g;
			$rec_key        = $value if $fld_name =~ /$rec_keys/i;
			$tmp{$fld_name} = $value;
			#print "\"$rec_name\"\t\"$fld_name\"\t=\t$value\n";

			################################
			# READ UP TO RECORD LENGTH ONLY
			################################
			last if $rec_read >= $rec_len;
		}
		#print "\n\n";


		#############
		# STORE DATA
		#############
		#
		# ########################
		# # DATA STRUCTURE FOR TD
		# ########################
		# MIR{1}{FIELD_NAME}=VALUE
		#    PCR{1}{FIELD_NAME}=VALUE
		#    WCR{1}{FIELD_NAME}=VALUE
		#    WIR{W#}{FIELD_NAME}=VALUE
		#       PIR{SEQ#}{FIELD_NAME}=VALUE		### DON'T CARE. USE PRR INSTEAD
		#	   PTR{W#}{P#}{T#}{FIELD_NAME}=VALUE
		#	   ...
		#	PRR{W#}{P#}{FIELD_NAME}=VALUE
		#    WRR{W#}{FIELD_NAME}=VALUE
		#    SBR{BIN#}{FIELD_NAME}=VALUE 
		#    HBR{BIN#}{FIELD_NAME}=VALUE 
		#    TSR{BIN#}{FIELD_NAME}=VALUE 
		# MRR{1}{FIELD_NAME}=VALUE
		#
		#
		# ########################
		# # DATA STRUCTURE FOR TP
		# ########################
		# tp{T#}{FIELD_NAME}=VALUE
		#
	
		### GET WAFERID IF PRESENT ###
		$wid = $tmp{WAFER_ID} if $rec_name eq "WIR";

		### TEMPORARILY STORE "PTR" DATA INTO "PTR_{HEAD#}_{SITE#}" HASH ###
		if ($rec_name eq "PTR")
		{
			my $head     = $tmp{HEAD_NUM};
			my $site     = $tmp{SITE_NUM};
			${"PTR_${head}_${site}"}{$rec_key} = {%tmp};	### STORE PTR. REC_KEY=TEST# 
		}
		elsif ($rec_name eq "PRR")
		{
			my $head     = $tmp{HEAD_NUM};
			my $site     = $tmp{SITE_NUM};
			${$rec_name}{$wid}{$rec_key} = {%tmp};			  ### STORES PRR. REC_KEY=PARTID
			$PTR{$wid}{$rec_key}	    = {%{"PTR_${head}_${site}"}}; ### STORES PART's PTR RECS
			%{"PTR_${head}_${site}"}    = ();			  ### ERASE PART's PTR RECS
		}
		else
		{
			$rec_key = ++$rec_counter{$rec_name} if $rec_key eq "";	  ### USE REC_COUNTER AS REC KEY
			${$rec_name}{$rec_key} = {%tmp};
		}
		

		###################
		# CREATE A TP HASH
		###################
		if ($tp{$rec_key} eq "" && $rec_name eq "PTR")
		{

			################################################
			# LO_LIMIT INVALID IF "OPT_FLAG bit 4 or 6 = 1" 
			# HI_LIMIT INVALID IF "OPT_FLAG bit 5 or 7 = 1"
			################################################
			my @bits = split //, $tmp{OPT_FLAG};


			### VALIDATE IF ALL TP INFO ARE PRESENT ###
			if ($tmp{TEST_NUM} ne "" &&	
			    $tmp{LO_LIMIT} ne "" &&
			    $tmp{HI_LIMIT} ne "")
			{

				### CLEAN TEST NAME ###
				$tmp{TEST_TXT} = &clean_string($tmp{TEST_TXT});

				### GET UNIT BASE MULTIPLIER ###
                                $tmp{UNITS}      =~ s/^G/GRAV/i if $product eq "MEMS" && $tmp{UNITS} !~ /GRAV/i;
				my ($mul, $unit) = &get_base_multiplier($tmp{UNITS});

				### ASSIGN MAX LIMIT IF INVALID ###
				$tmp{LO_LIMIT} = -$FLT_MAX if $bits[1]==1 || $bits[3]==1; #bits 4&6;
				$tmp{HI_LIMIT} =  $FLT_MAX if $bits[0]==1 || $bits[2]==1; #bits 5&7

				### FORM TESTPLAN ###
				$tp{$tmp{TEST_NUM}} =
				{
					TEST_TXT => $tmp{TEST_TXT},
					LO_LIMIT => $tmp{LO_LIMIT} * $mul,
					HI_LIMIT => $tmp{HI_LIMIT} * $mul,
					UNITS    => $unit,
					BASE_MUL => $mul,
				};
			}
		}


		########################
		# STOP AFTER MRR IS READ
		########################
		last if $rec_counter{MRR} == 1;
        }       
        close(FH);

}


###############
# CLEAN STRING
###############
sub clean_string
{
        my $str = shift;
        #   $str =~ s/^\s+|\s+$//g;
        #   $str = &EDBUtil::cleanString($str);
        #   $str =~ s/\s+/_/g;
		
        return($str);
}


##################
# DATA VALIDATION
##################
sub data_validation
{

        ########################
        # TRAPPINGS/CORRECTIONS
        ########################
        if (scalar(keys %PIR) == 0 || $rec_counter{PIR} eq "")
        {
                print "\ndir=no_part_data";                 ### RETURN BAD SUBDIR FOR MFT
                &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_part_data") if $mft_flag==0;
                exit 100;
        }
        elsif (scalar(keys %MRR) == 0)
        {
                print "\ndir=no_mrr";
                &move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_mrr") if $mft_flag==0;
                exit 100
        }

        ### USE LOTID IN FILENAME IF IT'S NOT CONSISTENT W/ THE LOTID FIELD VALUE ###
        my ($lotid_fld_value,$dump1)   = split /\_|\-|\./, uc($MIR{1}{LOT_ID});
        my (@dummy)                    = split /\//, $file;
        my ($lotid_in_filename,$dump2) = split /\_|\-|\./, uc($dummy[$#dummy]);
        $MIR{1}{LOT_ID} = $lotid_in_filename if $lotid_fld_value ne $lotid_in_filename;
        $MIR{1}{LOT_ID} =~ s/AO/A0/ig;
        $MIR{1}{LOT_ID} = substr($MIR{1}{LOT_ID},0,10) if $MIR{1}{LOT_ID}=~/^A0/i && length($MIR{1}{LOT_ID}) > 10;


        ### CHECK IF FILE IS A RETEST ###
        $retest_flag="Y" if $MIR{1}{LOT_ID}=~/REJ/i || $file=~/REJ/i;
        $MIR{1}{LOT_ID} =~ s/REJ//ig;


        ### REMOVE DECIMAL POINT FROM TESTPLAN REV ###
        $MIR{1}{JOB_REV} =~ s/\.//g;

        ### FIX TP NAME ###
        $MIR{1}{JOB_NAM} = uc($MIR{1}{JOB_NAM});
        $MIR{1}{JOB_NAM} =~ s/\s+/\_/g;

        #print "fn=$lotid_in_filename vs $fld=$lotid_fld_value\n";
        #exit 0;

}



#######################
# UNPACK BINARY RECORD
#######################
sub unpack_me()
{
        ########################
        # GET PASSED PARAMETERS 
        ########################
        $FH               = shift;
        $format           = shift;
        $count            = shift;  
	$v4_invalid_val   = shift;
	$plus_invalid_val = shift;

        ################        
        # UNPACK RECORD 
        ################
        read $FH, $in, $count;
        if ($format =~ /^B$/i)
        {
                $out = unpack("${format}".${count}*8, $in);
        }
	elsif ($format eq "f" && $cpu_type == 0)
        {
                ### THIS CODE IS CLONED FROM STEVE FRAMPTON's STDF_UNPACK.PM ###
                @vaxFlt = unpack "C" x 4, $in;

                my $XPVAXFlt4Byt1ExpMask            =0x7f ;
                my $XPVAXFlt4Byt1ExpTooSmallForIEEE =0x00 ;
                my $XPVAXFlt4Byt1SgnMask            =0x80 ;
                my $XPVAXFlt4Byt1ExpTwo             =0x01 ;
                my @ieeeFlt ;

                if ( $XPVAXFlt4Byt1ExpTooSmallForIEEE == ( $vaxFlt[1] & $XPVAXFlt4Byt1ExpMask ) )
                {
                        # too small, assume 0
                        #
                        # This should probably return FLT_MIN and preserve sign
                        # Not likely to be an issue
                        #
                        $ieeeFlt[0] = 0x00 ;
                        $ieeeFlt[1] = 0x00 | $vaxFlt[1] & $XPVAXFlt4Byt1SgnMask ;
                        $ieeeFlt[2] = 0x00 ;
                        $ieeeFlt[3] = 0x00 ;
                }
                else
                {
                        # Reorder the bytes subtract two to the exponent.
                        $ieeeFlt[0] = $vaxFlt[1] - $XPVAXFlt4Byt1ExpTwo ;
                        $ieeeFlt[1] = $vaxFlt[0] ;
                        $ieeeFlt[2] = $vaxFlt[3] ;
                        $ieeeFlt[3] = $vaxFlt[2] ;
                }
	
		if ($cpu_type =~ /[1]/)
		{
                	$out = unpack("f",pack("CCCC",($ieeeFlt[0], $ieeeFlt[1], $ieeeFlt[2], $ieeeFlt[3])));
		}
		elsif ($cpu_type =~ /[02]/)
		{
			$out = unpack("f",pack("CCCC",($ieeeFlt[3], $ieeeFlt[2], $ieeeFlt[1], $ieeeFlt[0])));
		}
	}
        elsif ($format eq "f")
        {
		my @real ;
		if ($cpu_type =~ /[1]/)
		{
                	($real[3], $real[2], $real[1], $real[0]) = unpack("CCCC",$in) ;
                	$out = unpack("f",pack("CCCC", @real)) ;
		}
		elsif ($cpu_type =~ /[02]/)
		{
			$out = unpack("f", $in);
		}
        }
        elsif ($format eq "L")
        {
                @b   = unpack "C" x 4, $in;
                $out = unpack "I", (pack "CCCC", $b[3], $b[2], $b[1], $b[0]) if $cpu_type =~ /[1]/;
                $out = unpack "I", $in					     if $cpu_type =~ /[02]/;
        }
        elsif ($format=~/S/i)
        {
                @b   = unpack "C" x 2, $in;
                $out = unpack $format, (pack "CC", $b[1], $b[0]) if $cpu_type =~ /[1]/;
                $out = unpack $format, (pack "CC", $b[0], $b[1]) if $cpu_type =~ /[02]/;
        }
        else
        {
                $out = unpack("${format}${count}", $in);
        }
        
        ########################################
        # REMOVE LEADING AND/OR TRAILING SPACES 
        ########################################
        $out =~ s/^\s+//g;      
        $out =~ s/\s+$//g;
        

	##############################
	# APPLY STDFV3+ INVALID VALUE
	##############################
	if ($v4_invalid_val ne "" && $plus_invalid_val ne "" && $v4_invalid_val==$out)
	{
		$out = $plus_invalid_val;
	}

        ########################
        # RETURN UNPACKED VALUE 
        ########################
        return ($out);
}




###############################################
# STORE VALID STDFv4 HEADER INFO TO HASH
###############################################
sub load_stdfv4_template()
{
	my $rec_typ       = "";
	my $sub_rec_typ   = "";
	my $template_file = dirname($0) ."/conv_stdf4.ref";
	open FH, $template_file or die "can't open $template_file. $!\n";
	while($line=<FH>)
	{
        	chomp($line);
		next if $line =~ /^#/;
	
        	if ($line =~ /\[.*\_START\_/i)
        	{
			my $junk = "";
			($junk, $rec_typ, $sub_rec_typ, $junk, $rec_name) = split /\[|\_|\]/, $line;
			$stdf_recs{$rec_typ."_".$sub_rec_typ}{NAME} = $rec_name;
        	}
        	elsif ($rec_typ ne "" && $sub_rec_typ ne "" && $line=~/\s+/)
        	{
			$stdf_recs{$rec_typ."_".$sub_rec_typ}{FORMAT} .= "$line\n";
        	}
	}
	close(FH);

}


#############################
# GENERATE STDF DATALOG FILE
#############################
sub create_td
{
        ####################
        # SET STDF FILENAME
        ####################
	$td_filename = "${file}.TD";
        open FH, ">${td_filename}" or die "Can't write to $td_file file: $!";


        ##############
        # EMIR RECORD
        ##############
        %out::emir           = %{$out::init{emir}} ;
        $out::emir{lot_type} = $lot_type;
        $out::emir{mode_cod} = "P";
	$out::emir{test_cod} = $MIR{1}{TEST_COD} if $MIR{1}{TEST_COD} ne "";
        $out::emir{setup_t}  = $MIR{1}{SETUP_T};
        $out::emir{start_t}  = $MIR{1}{START_T};
        $out::emir{lot_id}   = $MIR{1}{LOT_ID};
	$out::emir{sblot_id} = $MIR{1}{SBLOT_ID};
        $out::emir{tstr_typ} = $MIR{1}{TSTR_TYP};
        $out::emir{facility} = $plant if $plant ne "";
        $out::emir{job_nam}  = $tp_prefix.$MIR{1}{JOB_NAM};
        $out::emir{job_rev}  = $MIR{1}{JOB_REV};
	$out::emir{device}   = $MIR{1}{PKG_TYP}||$MIR{1}{JOB_NAM};
	$out::emir{part_typ} = $MIR{1}{PKG_TYP}||$MIR{1}{JOB_NAM};
        $out::emir{spec_nam} = substr($tp_prefix.$MIR{1}{JOB_NAM}, 0, $edb_spec_nam_len);
        $out::emir{spec_rev} = int($MIR{1}{JOB_REV});
	$out::emir{spec_rev} = pad($out::emir{spec_rev},"\0"); 
        $out::emir{oper_nam} = $MIR{1}{OPER_NAM};
        $out::emir{node_nam} = $MIR{1}{NODE_NAM}; 
        $out::emir{ssum_cnt} = 1;
        $out::emir{pres_cnt} = keys %PIR;
        $out::emir{psum_cnt} = $rec_counter{PIR};
        $out::emir{stat_num} = $MIR{1}{STAT_NUM}||0;
	$out::emir{pkg_type} = $MIR{1}{PKG_TYP}||$MIR{1}{JOB_NAM};
	$out::emir{family}   = $MIR{1}{FAMILY_ID} if $MIR{1}{FAMILY_ID} ne "";
	$out::emir{prb_card} = $MIR{1}{SUPR_NAM} if $prbcard_from_suprnam eq "Y" && $MIR{1}{SUPR_NAM} ne "";
        print FH &out::pack_EMIR(\%out::emir);

	my $SBR_CNT = 0;

	foreach my $wid(sort {$a<=>$b} keys %WIR)
	{
	
		my $WSBR_CNT = 0;

		#############
		# WIR RECORD
		#############
		if ($wid > 0)
		{
			%out::wir            = %{$out::init{wir}};
                	$out::wir{wafer_id}  = $wid;
                	$out::wir{start_t}   = $WIR{$wid}{START_T};
                	print FH &out::pack_WIR(\%out::wir);
		}	

		foreach my $pid (sort {$a<=>$b} keys %{$PRR{$wid}})
		{	
		
		        if ($wid > 0)
		        {	
			    next if $PRR{$wid}{$pid}{X_COORD} < -5000 || $PRR{$wid}{$pid}{X_COORD} > 5000;
			    next if $PRR{$wid}{$pid}{Y_COORD} < -5000 || $PRR{$wid}{$pid}{Y_COORD} > 5000;
		        }
			#############
			# PIR RECORD
			#############
			%out::pir            = %{$out::init{pir}};
                	$out::pir{part_id}   = $pid;
                	$out::pir{head_num}  = $PRR{$wid}{$pid}{HEAD_NUM};
                	$out::pir{site_num}  = $PRR{$wid}{$pid}{SITE_NUM};
                	$out::pir{x_coord}   = $PRR{$wid}{$pid}{X_COORD} if $PRR{$wid}{$pid}{X_COORD} ne "";
                	$out::pir{y_coord}   = $PRR{$wid}{$pid}{Y_COORD} if $PRR{$wid}{$pid}{Y_COORD} ne "";
                	print FH &out::pack_PIR(\%out::pir);

			
			#############
			# PTR RECORD
			#############
			my $ptr_addr = $PTR{$wid}{$pid};
			foreach $test_num (sort {$a<=>$b} keys %$ptr_addr)
			{
				%out::ptr           = %{$out::init{ptr}};
                        	$out::ptr{test_num} = $test_mul * $test_num;
                		$out::ptr{head_num} = $$ptr_addr{$test_num}{HEAD_NUM};
                		$out::ptr{site_num} = $$ptr_addr{$test_num}{SITE_NUM};
                        	$out::ptr{result}   = $$ptr_addr{$test_num}{RESULT} * $tp{$test_num}{BASE_MUL};	
				$out::ptr{test_flg} = $$ptr_addr{$test_num}{TEST_FLG};
				print FH &out::pack_PTR(\%out::ptr);
			}

			#############
			# PRR RECORD
			#############
			my $hbnum = $PRR{$wid}{$pid}{HARD_BIN};
			my $sbnum = $PRR{$wid}{$pid}{SOFT_BIN};

			%out::eprr           = %{$out::init{eprr}};
                	$out::eprr{part_id}  = $pid;
                	$out::eprr{num_test} = $PRR{$wid}{$pid}{NUM_TEST};
                	$out::eprr{head_num} = $PRR{$wid}{$pid}{HEAD_NUM};
                	$out::eprr{site_num} = $PRR{$wid}{$pid}{SITE_NUM};
                	$out::eprr{x_coord}  = $PRR{$wid}{$pid}{X_COORD} if $PRR{$wid}{$pid}{X_COORD} ne "";
                	$out::eprr{y_coord}  = $PRR{$wid}{$pid}{Y_COORD} if $PRR{$wid}{$pid}{Y_COORD} ne "";
			if ($swb_from_tsr eq "N"){
				$out::eprr{sbin_nam} = $SBR{$sbnum}{SBIN_NAM}||"SBIN".$sbnum;
			}else {
				$out::eprr{sbin_nam} = $TSR{$sbnum}{SEQ_NAME}||"SBIN".$sbnum;
			}
			$out::eprr{hbin_nam} = $HBR{$hbnum}{HBIN_NAM}||"HBIN".$hbnum;
                	$out::eprr{soft_bin} = $PRR{$wid}{$pid}{SOFT_BIN};
                	$out::eprr{hard_bin} = $PRR{$wid}{$pid}{HARD_BIN};
                	$out::eprr{part_flg} = $PRR{$wid}{$pid}{PART_FLG};
                	print FH &out::pack_EPRR(\%out::eprr);

			$WSBR_CNT = $WSBR_CNT > $PRR{$wid}{$pid}{NUM_TEST} ? $WSBR_CNT : $PRR{$wid}{$pid}{NUM_TEST};
		}


                if ($wid > 0)
                {

        		##############
        		# WHBR RECORD
        		##############
        		if (keys %HBR > 0)
        		{
                		foreach my $bin(1..32)
                		{
                        		%out::whbr           = %{$out::init{whbr}} ;
                        		$out::whbr{hbin_num} = $bin;
                        		$out::whbr{hbin_nam} = $HBR{$bin}{HBIN_NAM}||"HBIN".$bin;
                        		$out::whbr{hbin_cnt} = $HBR{$bin}{HBIN_CNT}||0;
                        		print FH &out::pack_WHBR(\%out::whbr);
                		}
        		}


        		##############
        		# WSBR RECORD
        		##############
				########################################################
				# Write the WSBR Records here
				# Note: I will use the STS Records here as wafer level
				#	WSBR records.

				# Create records for all possible bins
				$MAX_BINS = $WSBR_CNT;
				for ($i = 1; $i <= $MAX_BINS; $i++)
				{
					if ( !defined($SBR{$i}{SBIN_CNT}) )
					{
						$SBR{$i} =                
						{
							SBIN_NAM => "",
							SBIN_CNT => 0,
						};
					}
				}
				
				if ($swb_from_tsr eq "N") 
				{
					foreach my $bin(sort {$a<=>$b} keys %SBR)
					{
							%out::wsbr           = %{$out::init{wsbr}};
							$out::wsbr{sbin_num} = $bin;
							$out::wsbr{sbin_nam} = $SBR{$bin}{SBIN_NAM}||"SBIN".$bin;
							$out::wsbr{sbin_cnt} = $SBR{$bin}{SBIN_CNT}||0;
							print FH &out::pack_WSBR(\%out::wsbr);
					}
				}
				else
				{
					foreach my $testnum(sort {$a<=>$b} keys %TSR)
					{
							%out::wsbr           = %{$out::init{wsbr}};
							$out::wsbr{sbin_num} = $testnum;
							$out::wsbr{sbin_nam} = $TSR{$testnum}{SEQ_NAME}||"SBIN".$bin;
							$out::wsbr{sbin_cnt} = $TSR{$testnum}{FAIL_CNT}||0;
							print FH &out::pack_WSBR(\%out::wsbr);
					}
				}

			#############
                	# WRR RECORD
                	#############
			%out::wrr           = %{$out::init{wrr}};
                	$out::wrr{wafer_id} = $wid;
			$out::wrr{finish_t} = $WRR{$wid}{FINISH_T};
			$out::wrr{part_cnt} = $WRR{$wid}{PART_CNT};
			$out::wrr{rtst_cnt} = $WRR{$wid}{RTST_CNT};
			$out::wrr{abrt_cnt} = $WRR{$wid}{ABRT_CNT};
			$out::wrr{good_cnt} = $WRR{$wid}{GOOD_CNT};
			$out::wrr{func_cnt} = $WRR{$wid}{FUNC_CNT};
                	print FH &out::pack_WRR(\%out::wrr);

		}

		$SBR_CNT = $SBR_CNT > $WSBR_CNT ? $SBR_CNT : $WSBR_CNT;
	}
	

        #############
        # HBR RECORD
        #############
		my $hbin_total_parts = 0;
        my $hbin_total_good  = 0;
		if (keys %HBR > 0)
		{	
        	foreach my $bin(1..32)
        	{
                	%out::hbr           = %{$out::init{hbr}} ;
                	$out::hbr{hbin_num} = $bin;
                	$out::hbr{hbin_nam} = $HBR{$bin}{HBIN_NAM}||"HBIN".$bin;
                	$out::hbr{hbin_cnt} = $HBR{$bin}{HBIN_CNT}||0;
                	print FH &out::pack_HBR(\%out::hbr);

			$hbin_total_parts += $HBR{$bin}{HBIN_CNT}||0;
			$hbin_total_good  += $HBR{$bin}{HBIN_CNT} if $HBR{$bin}{HBIN_PF} eq "P";	
        	}
		}
	

        #############
        # SBR RECORD
        #############
		# Create records for all possible bins
		$MAX_BINS = $SBR_CNT;
		for ($i = 1; $i <= $MAX_BINS; $i++)
		{
			if ( !defined($SBR{$i}{SBIN_CNT}) )
			{
				$SBR{$i} =                
				{
					SBIN_NAM => "",
					SBIN_CNT => 0,
				};
			}
		}

		my $sbin_total_parts = 0;
		my $sbin_total_good  = 0;
        foreach my $bin(sort {$a<=>$b} keys %SBR)
        {
			if ($swb_from_tsr eq "N") 
			{
                %out::sbr           = %{$out::init{sbr}};
                $out::sbr{sbin_num} = $bin;
                $out::sbr{sbin_nam} = $SBR{$bin}{SBIN_NAM}||"SBIN".$bin;;
                $out::sbr{sbin_cnt} = $SBR{$bin}{SBIN_CNT}||0;
                print FH &out::pack_SBR(\%out::sbr);
			}
			$sbin_total_parts += $SBR{$bin}{SBIN_CNT}||0;
			$sbin_total_good  += $SBR{$bin}{SBIN_CNT} if $SBR{$bin}{SBIN_PF} eq "P";
        }

		if ($swb_from_tsr eq "Y") 
		{
			foreach my $testnum(sort {$a<=>$b} keys %TSR)
			{
					%out::sbr           = %{$out::init{sbr}};
					$out::sbr{sbin_num} = $testnum;
					$out::sbr{sbin_nam} = $TSR{$testnum}{SEQ_NAME}||"SBIN".$bin;
					$out::sbr{sbin_cnt} = $TSR{$testnum}{FAIL_CNT}||0;
					print FH &out::pack_SBR(\%out::sbr);
			}
		}

        #############
        # MRR RECORD
        #############
        %out::mrr            = %{$out::init{mrr}};
        $out::mrr{finish_t}  = $MRR{1}{FINISH_T};
        $out::mrr{part_cnt}  = $hbin_total_parts||$sbin_total_parts;
        $out::mrr{good_cnt}  = $hbin_total_good||$sbin_total_good;
		$out::mrr{disp_cod}  = $MRR{1}{DISP_COD} if $MRR{1}{DISP_COD} ne "";
        print FH &out::pack_MRR(\%out::mrr);
        close(FH) ;

}


##############################
# GENERATE STDF TESTPLAN FILE
##############################
sub create_tp
{
        ####################
        # SET STDF FILENAME
        ####################
		$tp_filename = "${file}.TP";
		open FH, ">${tp_filename}" or die "Can't create $tp_filename file: $!";


		#############
		# EMIR RECORD
		#############
		%out::emir              = %{$out::init{emir}};
		$out::emir{mode_cod}    = "C";
		$out::emir{setup_t}     = $MIR{1}{SETUP_T};;
		$out::emir{ssum_cnt}    = 1;
		$out::emir{job_nam}     = $tp_prefix.$MIR{1}{JOB_NAM};
		$out::emir{job_rev}     = $MIR{1}{JOB_REV};
		$out::emir{spec_nam}    = substr($tp_prefix.$MIR{1}{JOB_NAM}, 0, $edb_spec_nam_len);;
		$out::emir{spec_rev}    = int($MIR{1}{JOB_REV});
		$out::emir{spec_rev}    = pad($out::emir{spec_rev},"\0"); 
		print FH &out::pack_EMIR(\%out::emir);

		##############
		# EPDR RECORD
		##############
	### FOR SBIN ###
        foreach my $snum(sort {$a<=>$b} keys %SBR)
        {
                %out::epdr           = %{$out::init{epdr}};
                $out::epdr{test_num} = $snum;
                $out::epdr{test_nam} = $SBR{$snum}{SBIN_NAM}||"SBIN".$snum;
                $out::epdr{test_txt} = $out::epdr{test_nam};
                $out::epdr{parmtyp}  = "B";
                $out::epdr{opt_flg}  = ($SBR{$snum}{SBIN_PF} eq "P") ? "00100000" : 00000000;
                $out::epdr{sbin_num} = $snum;
                $out::epdr{sbin_nam} = $out::epdr{test_nam};
                print FH &out::pack_EPDR(\%out::epdr);
        }
	### FOR DATALOG ###
        foreach my $testnum(sort {$a<=>$b} keys %tp)
        {
				my $test_name = $tp{$testnum}{TEST_TXT}||$TSR{$testnum}{TEST_NAM};
				if ($use_seq_name eq "Y") {
					$test_name = $TSR{$testnum}{SEQ_NAME};
				}
				### SKIP IF NO TEST NAME AVAILABLE ###
				next if $test_name eq "";

                %out::epdr           = %{$out::init{epdr}};
                $out::epdr{test_num} = $test_mul * $testnum;
                $out::epdr{lo_limit} = $tp{$testnum}{LO_LIMIT};
                $out::epdr{hi_limit} = $tp{$testnum}{HI_LIMIT};
                $out::epdr{units}    = uc($tp{$testnum}{UNITS});
                $out::epdr{test_nam} = $test_name;
                $out::epdr{test_txt} = $out::epdr{test_nam};
                $out::epdr{opt_flg}  = "00000000";
                print FH &out::pack_EPDR(\%out::epdr);
        }


        #############
        # MRR RECORD
        #############
        %out::mrr = %{$out::init{mrr}};
        $out::mrr{finish_t} = $MRR{1}{FINISH_T};
        print FH &out::pack_MRR(\%out::mrr);

        close(FH);
}



##########################
# RETRIEVE TEST CONDITION
##########################
sub GetTestCondition()
{
        ################
        # GET PARAMETER 
        ################
        my $testname = shift;
        
        #################################
        # SEARCH MATCHING TEST CONDITION
        #################################
        for(1..$dtr_counter)
        {
                if($DTR{$_}{TEXT_DAT}=~/$testname/ig)
                {
                        $condition    = $DTR{$_+1}{TEXT_DAT};
                        $condition    =~ s/ //g;
                        (@conditions) = split /\,/, $condition;
                        $condition    = substr $conditions[1].", ".$conditions[2], 0, 80;       
                        #print "$testname = $condition\n";
                        return($condition);
                        last;
                }       
        }
}



#######################
# CONVERT TO BASE UNIT
#######################
sub get_base_multiplier
{

        my $unit       = shift;
        my $multiplier = 1;

        #print "orig: unit=$unit, value1=$value1, value2=$value2\n";

        if ($unit =~ /^p/)
        {
                $unit       =~ s/^p//;
                $multiplier = 1e-12;
        }
        elsif ($unit =~ /^n/)
        {
                $unit       =~ s/^n//;
                $multiplier = 1e-9;
        }
        elsif ($unit =~ /^u/)
        {
                $unit       =~ s/^u//;
                $multiplier = 1e-6;
        }
        elsif ($unit =~ /^m/ && $unit !~ /MHO/i)
        {
                $unit       =~ s/^m//;
                $multiplier = 1e-3;
        }
        elsif ($unit =~ /^K/)
        {
                $unit       =~ s/^K//;
                $multiplier = 1e3;
        }
        elsif ($unit =~ /^M/ && $unit !~ /MHO/i)
        {
                $unit       =~ s/^M//;
                $multiplier = 1e6;
        }
        elsif ($unit =~ /^G/ && $unit !~ /GRAV/i)
        {
                $unit       =~ s/^G//;
                $multiplier = 1e9;
        }

        return($multiplier, $unit);
}

