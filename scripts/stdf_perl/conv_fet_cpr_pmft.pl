#!/usr/bin/perl 
#
# DATE       WHO            COMMENTS
# ---------- -------------- ------------------------------------------------------
# 08/10/2011 Ben Rommel Kho Adopted .TD filenaming scheme
# 08/07/2012 Reuben Capio   MFT Conversion.
# 08/31/2012 Rodney Cyr     Changed negative exit codes to positive (negative exit codes are not valid in unix).
# 06/11/2013 Jun Garcia     Reversed the index of the array that holds the unpacked value(Endianness)
#                            in sub routine char2short, char2float, char2int
#


use Carp ;  # error messages - does not work within stdf_use.pl
# set path to executable for libraries
use FindBin ;
use lib "$FindBin::Bin" ; # set up path for libraries the same as script
use English ;
use lib $ENV{'STDF_PERL_LIB'} ; # look for libraries in this directory
use Getopt::Long              ;
use lib "/home/dpower/project/work/eric/scripts/lib/PPLOG/";

require "stdf_use.pl" ;  # libraries that are not generated

#
# Load Specifications
#
{
        package out ;
        if ( !eval(&::generate_all('stdfPL.spec')))
        {
                confess $@ ;
        }
        require 'stdfPL.pl' ;
}


#
# Read the CPR data file
#
my $status = 0;


#### LET'S NOT HARD CODE ANY PATHS (COMMENT THEM OUT!)
my $file       = "";
my $sDierun    = ""; 
my $sLine      = "";
my $sPrgPrefix = "";
#my $sFacility  = "PMFT";
my $sFacility = "";
my $plant      = uc($ENV{ENV_FACILITY});     ### MFT ENV VAR
my $env_mod    = "";
my $mft_flag   = ($^O=~/linux/i) ? 1 : 0; 	### SET 0=OTHERS; 1=LINUX/MFT

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

$status = CPR2STDFP::CPR2STDFP($file, $sSTDFPath, $sDierun, $sLine, $sPrgPrefix, $sFacility);



########################
# RETURN CONVERTED FILE
########################
print "$file".'.TD'               if $mft_flag==0;
print "\ntd=$file".'.TD'          if $mft_flag==1;

exit 0;

######################################PACKAGES##########################################
#
# MODIFICATION HISTORY
#
# DATE       WHO            COMMENTS
# ---------- -------------- -------------------------------------------------------------------------
# 11/26/2007 BEN ROMMEL KHO Modified to lookup PMWKS for Full LotID rather that from Wks extract file
# 08/10/2011 Ben Rommel Kho Adopted TD filenaming scheme
#
package CPR2STDFP;

use Time::Local;

my $iErrCode=0;
my $sErrMsg="";
my $sErrSrc="";

sub CPR2STDFP{	
	

	my $sCPRFile  = shift;
	my $sSTDFPath = shift;
	my $sDierun   = shift;
	my $sLine = shift;
	my $sPrgPrefix = shift;
	my $sFacility=shift; #CBSORT, CBFT 
	my $sDate = "";
	my $rCPRHead;
	my $lStartTime=0;
	my $sFileName="";
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst,$i,$j,$k,$h);
	
	$oCPR = new CPR;

	if(!$oCPR->ReadCPR($sCPRFile))
	{
		$iErrCode = $oCPR->ErrCode;
		$sErrMsg  = $oCPR->ErrMsg;
		$sErrSrc  = "CPR::ReadCPR";
		$oCPR     = undef; return(0);
	}
	$rCPRHead = $oCPR->CPRHead();
	$aWafer = $oCPR->Wafer();


	######### $rCPRHead->{sLOT} is the source Lot ID, Let's rename it to $rCPRHead->{sSRC_LOT}
	#
	# Now, let's make $rCPRHead->{sLOT} equal to the "Lot ID"
	#
	#
	
	$rCPRHead->{sSRC_LOT} = $rCPRHead->{sLOT};  ### Use for LTR record
        ($rCPRHead->{sLOT}, ) = split /\_|\./, substr($sCPRFile, rindex($sCPRFile,"/") + 1);

	#
	# Now, Let's used the "partial" lot Id to find the full ID in the {soft extract	
	# Check if SourceLotID contains the full LotID, if not check Wks.
	# 
	my $tmp_lotid = substr($rCPRHead->{sLOT},length($rCPRHead->{sLOT})-8,8);		#<-- MATCH THE LAST 8 CHARS ONLY
	if (length($rCPRHead->{sSRC_LOT}) == 10 && $rCPRHead->{sSRC_LOT} =~ /$tmp_lotid/)
	{
		$rCPRHead->{sLOT} = $rCPRHead->{sSRC_LOT};
	}
	else
	{
		#$rCPRHead->{sLOT} = &Check_WKSDB_For_Full_LotID($rCPRHead->{sLOT}); 	

		### OBSOLETE. THE PSOFT FILES HAVE CONSUMED 25Gb. IT'S EFFICIENT TO CHECK PMWKS DB INSTEAD ###
		#$rCPRHead->{sLOT} =  GetIDsFromPSoftExtract($rCPRHead->{sLOT}, $rCPRHead->{sSRC_LOT});
	}

	
	#$sFileName = $rCPRHead->{sLOT}."_".$rCPRHead->{sPROB}."_".$Cnt."PMFFET"."_TD_STDF";	
	$sFileName = "${sCPRFile}.TD";
	#
	######### DONE 


	$Cnt = 0; 
	#while ( -e $sFileName){
		
	#	$sFileName = $rCPRHead->{sLOT}."_".$rCPRHead->{sPROB}."_".$Cnt."_PMFFET"."_TD_STDF";
	#	$Cnt++; 
	#}
	
	#get start date
	my $pos = 0;
	if ( ($pos = index($rCPRHead->{sSTART_DATE}, "/")) != -1)
	{
		($mon, $mday, $year) = split(/\//, $rCPRHead->{sSTART_DATE});
	}
	elsif ( ($pos = index($rCPRHead->{sSTART_DATE}, "\\")) != -1)
	{
		($mon, $mday, $year) = split(/\\/, $rCPRHead->{sSTART_DATE});	
	}
	$year =~ s/[^0-9]*//g;
	
	#print "Yr: $year MDay: $mday  Month: $mon\n";


	

	######### DATE CHECK ############
	$year_check = "";
	$mon_check = "";
	$mday_check = "";


	if ($year < 3000 && $year > 0 && $year ne "")
	{
		$year_check = "GOOD";
	}

	if ($mon <= 13 && $mon > 0 && $mon_check ne "")
	{
                $mon_check = "GOOD";
        }

	if ($mday  <= 32 && $mon > 0 && $mday_check ne "")
        {
                $mday_check = "GOOD";
        }

	
	if ($year_check ne "GOOD" || $mon_check ne "GOOD" || $mday_check ne "GOOD")
	{
		($trash, $file_time) = (split /PMFFET_/, $sCPRFile);
		($date_file,$trash) = (split /\./,$file_time);

		(@get_date) = (split //, $date_file);

		$year = $get_date[0].$get_date[1].$get_date[2].$get_date[3];
		$mon = $get_date[4].$get_date[5];
		$mday = $get_date[6].$get_date[7];

	
			if ($year < 3000 && $year > 0)
        		{
                		$year_check = "GOOD";
        		}

        		if ($mon <= 13 && $mon > 0)
        		{
                	$mon_check = "GOOD";
        		}

        		if ($mday  <= 32 && $mon > 0)
        		{
                		$mday_check = "GOOD";
        		}
	
		if ($year_check ne "GOOD" || $mon_check ne "GOOD" || $mday_check ne "GOOD")
        	{	
			
			$lStartTime = timegm(localtime);
		}
	
		else
		{	
			$lStartTime = timegm(0,0,0,$mday,$mon, $year);	
		}	
	
	}

	else
	{
		$lStartTime = timegm(0,0,0,$mday,$mon-1, $year);
	}

	### Rename filename in Archive directory to something that can be tracked
        rename_ID($rCPRHead->{sLOT},$rCPRHead->{sSRC_LOT});

	open (OUTPUT, ">$sFileName");
        
	#initialize stdf records
	%out::emir = %{$out::init{emir}};
	%out::ltr  = %{$out::init{ltr}} ;
	%out::pir  = %{$out::init{pir}} ;
	%out::ptr  = %{$out::init{ptr}} ;
	%out::mrr  = %{$out::init{mrr}} ;
	
	#populate EMIR	
	#$out::emir{lot_id}      = $rCPRHead->{sLOT};
	$out::emir{lot_id}      = $rCPRHead->{sSRC_LOT};
	$out::emir{tstr_typ}    = "FET"; #can put $rCPRHead->{$sLine} which will bear process code
	$out::emir{customer}    = $sFacility;
	$out::emir{oper_nam}    = $rCPRHead->{sOPER};
	$out::emir{stat_num}    = $rCPRHead->{sPROB};
	$out::emir{node_nam}    = $sLine;
	$out::emir{hand_id}     = $rCPRHead->{sPROB};
	#$out::emir{spec_nam}    = "FT_".$rCPRHead->{sTEST_NAME};
	$out::emir{spec_nam}    = $rCPRHead->{sTEST_NAME};
	#$out::emir{job_nam}     = "FT_".$rCPRHead->{sTEST_NAME}; 
	$out::emir{job_nam}     = $rCPRHead->{sTEST_NAME};
	$out::emir{job_rev}     = "0";
	$out::emir{spec_rev}    = "0";
	$out::emir{mode_cod}    = "P";
	$out::emir{setup_t}  	= $lStartTime;
	$out::emir{start_t}  	= $lStartTime;
	$out::emir{pres_cnt}    = 0;
	$out::emir{wswb_cnt}    = 0;
	print OUTPUT &out::pack_EMIR(\%out::emir);	
		
	# Write out an LTR record source lot ID 	 
	$out::ltr{lot_id}       = $rCPRHead->{sSRC_LOT}; 
	$out::ltr{lot_strt}     = ""; 
	$out::ltr{plant}        = ""; 
	print OUTPUT &out::pack_LTR(\%out::ltr);	

	#populate each die
	for($k=1; $k <= $aWafer->[0]{iDIE_LOGGED};$k++){
    		$out::pir{part_id}  = ${out::init{pir}{part_id}};
    
    		#encode PIR
    		$out::pir{part_id} = $k;
		print OUTPUT &out::pack_PIR(\%out::pir) ;    

		#encode PTR
		%out::eprr = %{$out::init{eprr}} ;
		for( $h=0; $h <= $rCPRHead->{iTEST_CNT}; $h++){
			$out::ptr{test_num} = ${out::init{ptr}{test_num}};
	    		$out::ptr{result}   = ${out::init{ptr}{result}};
	    		$out::ptr{test_flg} = ${out::init{ptr}{test_flg}};
			$out::ptr{test_num} = $aWafer->[$i]{rDIE}->[$k-1]{aTEST}[$h]{fTESTNUM};
			#
			# NOTE: Set $i = 1, only one wafer in final test data file
			#
			$i = 0;
			$out::ptr{result} = $aWafer->[$i]{rDIE}->[$k-1]{aTEST}[$h]{fRESULT};
			$out::ptr{test_flg} = "01000000";
			
			print OUTPUT &out::pack_PTR(\%out::ptr);
		
		}
		$out::emir{pres_cnt}++;
                $out::eprr{num_test} = $rCPRHead->{iTEST_CNT} +1;
                $out::eprr{soft_bin} = $aWafer->[$i]{rDIE}->[$k-1]{iBIN};
                $out::eprr{hard_bin} = $aWafer->[$i]{rDIE}->[$k-1]{iBIN};
		if (defined($aWafer->[$i]{rBIN}->[$k-1]))
		{
                	$BinArray[$k-1] = $aWafer->[$i]{rBIN}->[$k-1];
		}
		if (defined($aWafer->[$i]{uSORT}->[$k-1]))
		{
			$SoftBin[$k-1] = $aWafer->[$i]{uSORT}->[$k-1];
		}

	 	$out::eprr{part_id}  = $k;
		$out::emir{psum_cnt}++;
	  	print OUTPUT &out::pack_EPRR(\%out::eprr) ;
	  
	}
	for ($i = 1; $i <= 24; $i++)
	{
		%out::sbr = %{$out::init{sbr}};
		$out::sbr{sbin_num} = $i;
	
		if (!defined($BinArray[$i]))
		{	
			$out::sbr{sbin_cnt} = 0;
		}
		else
		{
			$out::sbr{sbin_cnt} = $SoftBin[$i-1];
		}
		#$out::sbr{sbin_nam} = "SWBin".$i;
		$out::emir{sswb_cnt}++;
		print OUTPUT &out::pack_SBR(\%out::sbr);

		%out::hbr = %{$out::init{hbr}};
                $out::hbr{hbin_num} = $i;

		if (!defined($BinArray[$i]))
                {
                        $out::hbr{hbin_cnt} = 0;
                }
                else
                {
                        $out::hbr{hbin_cnt} = $BinArray[$i-1];
                }
                #$out::hbr{hbin_nam} = "HWBin".$i;
                $out::emir{shwb_cnt}++;
                print OUTPUT &out::pack_HBR(\%out::hbr);

		if (defined($BinArray[$i-1]))
		{
			$MRR_PART_CNT += $BinArray[$i-1];
		}
	}	

	############ CHECK FOR ZERO QUANTITY IN #############################
        if ($MRR_PART_CNT <= 0)
        {
               	close(OUTPUT);
		#$cmd1 = "rm $sFileName"; 
		$cmd1  = "rm $file"; 
		$cmd2  = "mv $file  /data/edbpm/db_areas/edb_pmffet_v22/converter/bad/zero_qty_tested";

              	$zero_log = "/data/edbpm/db_areas/edb_pmffet_v22/log/zero_qty_log.txt";
	
		use POSIX qw(strftime);
		$time_stamp = strftime "%m/%d/%Y  %H:%M:%S",gmtime;
		
		open(zero_log, ">>$zero_log");
		print zero_log "LOT: $rCPRHead->{sLOT}   OPER: $rCPRHead->{sOPER}   PROBER: $rCPRHead->{sPROB}  DATE:  $time_stamp\n";
		
		system($cmd1); 
		system($cmd2);
		close(zero_log);
                die "Zero Quantity in (MRR PART CNT = 0)";
       		 
	}
        #####################################################################



	# write MRR
	$out::mrr{finish_t} = $lStartTime;
	$out::mrr{part_cnt} = $MRR_PART_CNT;

	#
	# Figure out the good count
	# The good count is every bin minus the good bins...
	# NOTE: There can be multiple good bin in the FET Final Test Bin File.
	#
	$out::mrr{good_cnt} = 0;
	for ($i = 1; $i <= 24; $i++)
        {
	#####	if (defined($aWafer->[0]{rGOODBIN}->[$i]) && $aWafer->[0]{rGOODBIN}->[$i] == 1)
		
		if (defined($rCPRHead->{good_bins_prn}[$i]))
		{
			$out::mrr{good_cnt} = $out::mrr{good_cnt} + $BinArray[$i-1];
			#print "GOOD BIN: $i, COUNT: $out::mrr{good_cnt}\n";
		}

	}


	$out::mrr{rtst_cnt} = 0;
	$out::mrr{abrt_cnt} = 0;
	$out::mrr{func_cnt} = 0;
	print OUTPUT &out::pack_MRR(\%out::mrr) ;
	close OUTPUT ;
	
	
	# update EMIR with count information
	&out::update_EMIR(\%out::emir, $sFileName) ;
	close (OUTPUT);

	$oCPR = undef;
	return(1);
}
1;


sub rename_ID
{
       	($rCPRHead->{sLOT},$rCPRHead->{sSRC_LOT}) = @_; 
	@oldfilename = ();
        $trash = "";
        $newfilename = "";
        $oldfileID = "";
        $CMD = "";


        (@oldfilename) = (split /\//,$ARGV[0]);
        $oldfile_name = $oldfilename[$#oldfilename];

	$oldfile_name =~ s/_WS//g;
        ($oldfileID,$trash, $timestamp) = (split /_/, $oldfile_name);

        ### Look for File in $EDB_ARCHIVE ###

        opendir DIR, "/data/edbpm/db_areas/edb_pmffet_v22/archive";

        $compress = $oldfile_name.".Z";
	
        while ($chkFile = readdir DIR)
        {
                if ($chkFile eq $compress)
                {
                        $timestamp = $timestamp.".Z";
               		$oldfile_name = $compress; 
		}
        }
        closedir(DIR);

	
        $newfilename = $rCPRHead->{sLOT}."_".$rCPRHead->{sSRC_LOT}."_".$timestamp;
        $CMD = "/bin/mv -f /data/db_areas/edb_pmffet_v22/archive/$oldfile_name  /data/edbpm/db_areas/edb_pmffet_v22/archive/$newfilename";

#	print "NEW: $newfilename\n";
#        system($CMD);
}

sub run_query
{

	my ($CPR_Lot_id,$CPR_Src_id,$Parsed_lotid,$Parsed_Char_lotid) = @_;

	#use Sybase::CTlib;


        $SYBASE_DATABASE = 'edb_pmwks_v22';
        $SYBASE_SERVER   = 'SYB_PMEWB1';
        $SYBASE_USER     = 'EDB_GUEST';
        $SYBASE_PASSWORD = 'dryheave';


	### Open a connection to the Database Server...

	$dbh = Sybase::CTlib->ct_connect($SYBASE_USER, $SYBASE_PASSWORD, $SYBASE_SERVER, "Tracking");

	if (!(defined($dbh)) || length($dbh) == 0)
	{
       		die "ERROR using the $SYBASE_DATABASE database, exiting.\n";
	}

	### Use the proper database ...
	$dbh->ct_sql("use $SYBASE_DATABASE");

	$cmd = "select s.lot
                from session s,source_lot sl
                where s.lot = sl.lot
                and (sl.source_lot = '$CPR_Src_id'
                and s.lot like '%$Parsed_lotid%') or
                s.lot like '%$Parsed_Char_lotid%'";
	
	$cmd = "select s.lot
                from session s,source_lot sl
                where s.lot = sl.lot
                and s.lot like '%$Parsed_Char_lotid%'";


	$dbh->ct_execute($cmd);

	while($dbh->ct_results($restype) == CS_SUCCEED)
        {
                        if ($restype == CS_CMD_FAIL or $restype == CS_CMD_SUCCEED)
                        {
                                         next;
                        }

                        # Skip non-fetchable results:
                        next unless $dbh->ct_fetchable($restype);

                        # Retrieve actual data rows and store them in a hash keyed on column name:

                        $wks_cnt = 0;

                        while(@row = $dbh->ct_fetch())
                        {
                               	print "@row $row[0]\n";         
				$CPR_Lot_id = $row[0];
                        }

                        print "WKS_CNT: $wks_cnt\n";
        }
	return ($CPR_Lot_id);

	close($dbh);
}

sub GetIDsFromPSoftExtract
{
        #
        # Read PSoft Extract files to determine WorkStream SI number and Fab Die Run Number
        #
        # Input:  WaferSort Data File ID = WorkStream SI#
        # Output: Fab Die Run Number
        #
        my ($CPR_Lot_id, $CPR_Src_id) = @_;
        print "SOURCE ID: $CPR_Src_id         LOT_ID: $CPR_Lot_id\n";
        #
        # Location of People Soft Data File Extract
        #
        $Extract_Dir = "/data/edbpm/ftp_in/pmftstfet_ws_extract";


        opendir(DIR, $Extract_Dir) || die "CAN NOT OPEN DIRECTORY $Extract_Dir\n";
        my $Lot_id  = "";
        my $Src_id  = "";
        my $DR_cnt  = 0;
        my @Each_char = ();
        my $Parsed_lotid = "";
	my $Parsed_Char_lotid =  "";
        my @check_exist = ();
        $Wstream_reload = "";
        @Wstream_chk = ();

        #### Check to see if this is a Wstream reload ###
        @Wstream_chk = (split /_WS/, $ARGV[0]);

        (@Each_char)  = (split //, $CPR_Lot_id);

        if ($Each_char[0] eq 'A' || $Each_char[0] eq 'B' || $Each_char[0] eq 'C' || $Each_char[0] eq 'D')
        {
                for($ii = 1; $ii <= $#Each_char; $ii++)
                {
                        $Parsed_Char_lotid = $Parsed_Char_lotid.$Each_char[$ii];
                }
        }

        else
        {
                $Parsed_Char_lotid =  $CPR_Lot_id;
        }
	
	for ($ii = $#Each_char; $ii > ($#Each_char - 6); $ii--)
        {
                $Parsed_lotid = $Each_char[$ii].$Parsed_lotid;
        }

        print "PARSED LOT ID: $Parsed_lotid or $Parsed_Char_lotid    PARSED CHAR LOT ID:   $CPR_Lot_id\n";

        my @order_dir = ();
        @order_dir = readdir(DIR);

        for ($kk=$#order_dir; $kk >= 0; $kk--)
        {

                if ($file ne "." && $file ne "..")
                {
                        open (PSFile, "$Extract_Dir/$order_dir[$kk]");
                        my $line = "";
                        while ($line = <PSFile>)
                        {
                                chomp($line);
                                my $Lot_id        = substr($line, 0, 11); #char 11 is a " ", which allows a split
                                my $Src_id        = substr($line, 335,10);
				$Src_id =~ s/\s+//g;
                                $Lot_id =~ s/\s+//g;


                                if ($Src_id eq "$CPR_Src_id")
                                {
       
                                        if($Lot_id =~ $Parsed_lotid)
                                        {
                                                $DR_cnt++;
                                                close (PSFile);
                                                closedir(DIR);
                                                print "Lot_ID in Extract FIle: $Lot_id using '$Parsed_lotid'\n";
                                                return $Lot_id;
                                        }
                                }

                                elsif ($Lot_id =~ $Parsed_Char_lotid)
                                {
                                        $DR_cnt++;
					close (PSFile);
                                        closedir(DIR);
                                        print "Lot_ID in Extract FIle: $Lot_id\n";
                                        return $Lot_id;
                                }


                        }
                        close (PSFile);
               }
        }



        if($DR_cnt == 0)
        {
                ### Failures first go to a temp directory and are reload in 24hrs.
                #  This prevents failures due to a "late" WStream Entry
		
		### IF THIS IS THE FIRST TIME THROUGH THE CONVERTER ###
                if($#Wstream_chk < 1)
                {

                        @Tmp_file_move = (split /\//, $ARGV[0]);
                        ($new_ws_file, $ext) = (split /\./, $Tmp_file_move[$#Tmp_file_move]);
                        $new_ws_file = $new_ws_file."_WS.".$ext;

                        $my_cmd = "mv $ARGV[0] /data/edbpm/db_areas/edb_pmffet_v22/converter/bad/NoWstreamID/first_failure/$new_ws_file";
                       	print "$my_cmd\n"; 
			system($my_cmd);

                        print "Failed for no WStream Match - 1st failure\n";
                        die "Failed for no WStream Match - 1st failure";
                }

                ### IF THIS IS THE SECOND TIME THROUGH THE CONVERTER ###
                elsif($#Wstream_chk > 0)
                {
                        $month = (localtime)[4] +1;
			$year = (localtime)[5] +1900;

                        $NoWstream_log = "/data/edbpm/db_areas/edb_pmffet_v22/log/NoWstream_log.txt";
                        $perm_NoWstream_log = "/data/edbpm/db_areas/edb_pmffet_v22/log/perm_NoWstream_".$month.$year;
                        @Tmp_file_move = (split /\//, $ARGV[0]);
                        $file_move = $Tmp_file_move[$#Tmp_file_move];

                        open(NoWstream_log, ">> $NoWstream_log");
                        open(PermNoWstream_log, ">> $perm_NoWstream_log");

                        print NoWstream_log "CPFTSTFET- File: $file_move   Lot ID (Wstream): $CPR_Lot_id \n";
                        print PermNoWstream_log "CPFTSTFET- File: $file_move   Lot ID (Wstream): $CPR_Lot_id \n";
                        close(NoWstream_log);
                        close(PermNoWstream_log);

                        print "NO MATCH\n";


                        return $CPR_Lot_id;
                }
	}
        closedir(DIR);

 }

#########################################
# QUERY FTSTWKS TABLE FOR COMPLETE LOTID
#########################################
sub Check_WKSDB_For_Full_LotID
{
        ############
        # VARIABLES
        ############
	my $lotid           = shift;
        my $SYBASE_DATABASE = 'edb_pmwks_v22';
        my $SYBASE_SERVER   = $ENV{DATABASE_SERVER};
        my $SYBASE_USER     = $ENV{EDB_USERNAME};
        my $SYBASE_PASSWORD = $ENV{EDB_PASSWORD};


        ################
        # SQL STATEMENT
        ################
	my $tmp_lotid = substr($rCPRHead->{sLOT},length($rCPRHead->{sLOT})-8,8);	#<-- SEARCH FOR THE LAST 8 CHARS ONLY
        $lookup_sql = "select lot from lot where lot like '%${tmp_lotid}'";

        #####################
        # OPEN DB CONNECTION
        #####################
        $dbh = Sybase::CTlib ->ct_connect($SYBASE_USER, $SYBASE_PASSWORD, $SYBASE_SERVER, "Tracking");


        if (!(defined($dbh)) || length($dbh) == 0)
        {
                die "ERROR using the $SYBASE_DATABASE database, exiting.\n";
        }


        ############################
        # SEARCH FOR MATCHING LOTID
        ############################
        $dbh->ct_sql("use $SYBASE_DATABASE");
        $dbh->ct_execute($lookup_sql);

        while($dbh->ct_results($restype) == CS_SUCCEED)
        {
                if ($restype == CS_CMD_FAIL or $restype == CS_CMD_SUCCEED)
                {
                        next;
                }

                # Skip non-fetchable results:
                next unless $dbh->ct_fetchable($restype);

                # Retrieve actual data rows and store them in a hash keyed on column name:
                $ewb_cnt = 0;
                while(@row = $dbh->ct_fetch())
                {
                        ### RETURN COMPLETE LOTID ###
                        if ($#row >=0)
                        {
                                $row[0] =~ s/\s+//;
                                return $row[0];
                        }
                }
        }

        ### JUST RETURN THE ORIGINAL LOTID IF NO FULL LOTID IS FOUND ###
        return($lotid);
}


###########################################################################
#
# Fairchild Semiconductor
#
# File Name: CPR.pm
#
# Purpose: Read CPR file
#
# Revision History: stolen from dave fletchers code.
#  Chris Jan Cortes 12/07/2001 customize, convert to oop
#  Ben Rommel Kho   03/17/2007 Enable Missing Testplan Notification
#  Gilbert Miole    08/19/2011 Display Missing test plan name needed if not available in ENV_TP_RAW
# CPR Class Structure:
# 1.Data : - hash
# 1.1 CPRHEAD{} - contains CPR Header Data
#		- sFET_ID = should contain CPR ID "P4"
#		- iNUMWAF = number of wafers on cpr file
#		- sREM = remarks
#		- sSTART_DATE = start date on mm/dd/yyyy.hh.mm.ss
#		- sLINE = production line
#		- sOPER = operator
#		- sLOT = lot number
#		- sPROB = prober name
#		- iSNNUM = number of die per record
#		- iSNSIZE = bytes per die
#		- iNUMDIE = number of die per wafer
#		- cF1SSEG = start segment ?
#		- cF1ESEG = end segment ?
#		- iDARCNT = number of records per wafer
#		- iTEST_CNT = number of tests logged per die
#		- sRUN_NAME = run file name
#		- sTEST_NAME = test file name
#		- sEND_DATE = end date
#		- aTEST_NUM = array of data logged tests
#		- aFUNC_NUM = array of function number of each test
# 1.2 WAFER[] - array of wafers,each element is a hash containing elements below
#		- [....]
#			- iWAFER_NUM = wafer number
#			-	iDIE_TESTED = total number of dies tested
#			-	rBIN = referrence to an array of bin counts 1..25
#			-	rDIE = referrence to an array of die test results
#				- [...] = 1 to iNUMDIE
#						- iSERIAL = serial number of die
#						- iBIN = bin assignment of die
#						- aTEST = array of test results
#							-[...] = 1 to iTEST_CNT
#								- bFLAG = test result flag
#								- fRESULT = test result
#			-	iDIE_LOGGED = total number of dies logged
#			-	rGOODBIN = Array of good bins contained in data file
# 2.0 Public Methods
# 2.1 new() = instantiates a new object from this class
# 2.2 ReadCPR(filename) = reads all cpr data into CPR data structure,accepts a filename
# 2.3 PrintCPRHeader() = print CPR header data
# 2.4 PrintWaferData() = print wafer data


package CPR;

#use strict;
use English ;
use constant CPR_BLK_SIZE => 1536;
use constant CPR_ID => "P4";

#TEST FLAG CONSTANTS
use constant CPR_COVER_ON_PASS => 0x01;
use constant CPR_COVER_ON_FAIL => 0x02;
use constant CPR_TEST_DONE => 0x04; #test done
use constant CPR_TEST_FAIL => 0x08; #test failed
use constant CPR_TEST_OVER => 0x10; #result over limit
use constant CPR_DATA_LOGGED => 0x20; #result data logged
use constant CPR_TEST_LESS => 0x40; #result lesser than limit
use constant CPR_RSLT_FLOAT => 0x80; #result converted to floating point

#ERROR Constants
use constant CPR_ER_OPEN_CPR => -1;
use constant CPR_ERM_OPEN_CPR => "ERROR : Unable to open CPR File";
use constant CPR_ER_NOT_CPR => -2; #not a cpr file
use constant CPR_ERM_NOT_CPR => "ERROR : Invalid CPR file";

sub new
{
	my $class = shift;
	my $self = {};

	$self->{hCPR_HEAD}={};
	$self->{aWAFER}=();
	$self->{iER_CODE}=0;
	$self->{sER_MSG}="";
	$self->{sER_SRC}="";

	bless ($self,$class);
	return $self;
}

sub CPRHead{
	my $self = shift;
	$self->{hCPR_HEAD};
}

sub Wafer{
	my $self = shift;
	$self->{aWAFER};
}

sub ErrCode{
	my $self = shift;
	$self->{iER_CODE};
}

sub ErrMsg{
	my $self = shift;
	$self->{sER_MSG};
}

sub ErrSrc{
	my $self = shift;
	$self->{sER_SRC};
}

###############################################################################
#Purpose : Read cpr file
#Assumption:
#Parameter:
#[i]$Filename - cpr file name
#Return: 0 if error, 1 is success
###############################################################################
sub ReadCPR
{
	my $self = shift;
	my ($FileName) = shift;

	my ($rUBIN,$iDieTested,$sWaferNum,$rDie,$iDieLog,$i);
	
	if(!open(INPUT, "<$FileName")){
		$self->{iER_CODE}= CPR_ER_OPEN_CPR;
		$self->{sER_MSG}= CPR_ERM_OPEN_CPR . " $FileName";
		$self->{sER_SRC}="CPR::ReadCPR";
		
		return(0);
	}

	############################################
	# Read the top most header of the data file.
	# Only one per file.	
	$self->{hCPR_HEAD} = ReadCPRHeader();
	if(!$self->{hCPR_HEAD}){
		return(0);
	}
	
	# read each wafer and put it to an array of wafer data structure
	for($i=0; $i < $self->{hCPR_HEAD}->{iNUMWAF}; $i++)
	{
		($sWaferNum,$rUBIN,$iDieTested,$rDie,$iDieLog,$rGoodBin, $SoftwareBins) = ReadWaferData($self->{hCPR_HEAD});
		if(!($sWaferNum =~ /\d+/)){$sWaferNum = "0";}
		$self->{aWAFER}[$i]= {
			iWAFER_NUM 	=> $sWaferNum * 1,		#wafer number}
			iDIE_TESTED 	=> $iDieTested,			#number of die actually tested
			rBIN 		=> $rUBIN,			#bin count summary
			uSORT           => $SoftwareBins,               #Software Bins
			rDIE 		=> $rDie,			#array of die with test results
			iDIE_LOGGED 	=> $iDieLog,			#total die logged
			rGOODBIN        => $rGoodBin,			#array of good bins
		};
	}
	#PrintWaferData($self);
	close (INPUT);
	return(1);
}


###############################################################################
#Purpose : print the cpr Header
#Assumption:
#Parameter:
#Return:
###############################################################################
sub PrintCPRHeader
{
	my $self = shift;
	my $rCPRHead = $self->{hCPR_HEAD};
	print "FET File ID : $rCPRHead->{sFET_ID}\n";
	print "Remarks : $rCPRHead->{sREM}\n";
	print "Number of wafers: $rCPRHead->{iNUMWAF}\n";
	print "Start Date : $rCPRHead->{sSTART_DATE}\n";
	print "Line : $rCPRHead->{sLINE}\n";
	print "Operator : $rCPRHead->{sOPER}\n";
	print "LOT: $rCPRHead->{sLOT}\n";
	print "Prober : $rCPRHead->{sPROB}\n";
	print "SNNUM : Number of die / record: $rCPRHead->{iSNNUM}\n";
	print "SNSIZE : Number of Bytes / Die: $rCPRHead->{iSNSIZE}\n";
	print "NUMDIE : Number of Die / wafer: $rCPRHead->{iNUMDIE}\n";	
	print "Start Segment : $rCPRHead->{cF1SSEG}\n";
	print "End Segment : $rCPRHead->{cF1ESEG}\n";
	print "DARCNT : Data Record Count / Wafer: $rCPRHead->{iDARCNT}\n";		
	print "Run file name = $rCPRHead->{sRUN_NAME}\n";
	print "Test Program name : $rCPRHead->{sTEST_NAME}\n";
	print "End Date : $rCPRHead->{sEND_DATE}\n";
	return(1);
}

###############################################################################
#Purpose : print each wafer data
#Assumption:
#Parameter:
#Return:
###############################################################################
sub PrintWaferData{
	my $self = shift;
	my ($i,$j,$iWfr);
		
	for($iWfr =0; $iWfr < $self->{hCPR_HEAD}->{iNUMWAF}; $iWfr++){
		print "SUBLOT: $self->{aWAFER}[$iWfr]{iWAFER_NUM}\n";
		for($i=1; $i<26; $i++){
			print "<bin_summary: $i $self->{aWAFER}[$iWfr]{rBIN}->[$i-1]\n";
		}
		
		for($i=1; $i <= $self->{aWAFER}[$iWfr]{iDIE_LOGGED};$i++){
			print "Device: $i ";
			print "Site: $self->{aWAFER}[$iWfr]{rDIE}->[$i-1]{iSERIAL} ";
			print "Bin: $self->{aWAFER}[$iWfr]{rDIE}->[$i-1]{iBIN}\n";
			for( $j=1; $j <= $self->{hCPR_HEAD}->{iTEST_CNT}; $j++){
				print "$j   $self->{aWAFER}[$iWfr]{rDIE}->[$i-1]{aTEST}[$j-1]{fRESULT}\n";
			}
		}			
	}
}

###############################################################################
#Purpose : read cpr header. it has size of 1536
#Assumption:
#Parameter:
#Return: returns a referrence to header hash
###############################################################################
sub ReadCPRHeader
{
	my $self = shift;
	
	# Header Length is 1536 bytes
	my $rCPRHead = {
		sFET_ID => "",	iNUMWAF => 0,	sREM => "", sSTART_DATE => "",	
		sLINE => "", sOPER => "",	sLOT => "",sPROB => "",	iSNNUM => 0, 
		iSNSIZE => 0, iNUMDIE => 0, cF1SSEG => "",	cF1ESEG => "",	
		iDARCNT => "", iTEST_CNT => 0,sRUN_NAME => "",sTEST_NAME => "", sEND_DATE => "", 
		aTEST_NUM => (), aFUNC_NUM => ()
	};
	
	my ($rProbe,$rNum,$in,$ind);
	
	read INPUT, $in, 2;
	$rCPRHead->{sFET_ID} = unpack "A2", $in;
	
	if( $rCPRHead->{sFET_ID} ne CPR_ID){
		$self->{iER_CODE}= CPR_ER_NOT_CPR;
		$self->{sER_MSG}= CPR_ERM_NOT_CPR;
		$self->{sER_SRC}="CPR::ReadCPRHeader";		
		return(0);
	}
	
	read INPUT, $in, 2;
	$rCPRHead->{iNUMWAF} = char2short($in);
	
	read INPUT, $in, 1;
	read INPUT, $in, 39;
	$rCPRHead->{sREM} = unpack "A39", $in;
	
	read INPUT, $in, 1;
	read INPUT, $in, 39;
	$rCPRHead->{sSTART_DATE} = unpack "a39", $in;
	$rCPRHead->{sSTART_DATE} =~ s/^[\n]//;
	
	read INPUT, $in, 1;
	read INPUT, $in, 15;
	$rCPRHead->{sLINE} = unpack "a15", $in;
	$rCPRHead->{sLINE} =~ s/[^A-Za-z0-9]*//g;

	read INPUT, $in, 1;
	read INPUT, $in, 39;
	$rCPRHead->{sOPER} = unpack "A39", $in;
	$rCPRHead->{sOPER} =~ s/[^A-Za-z0-9]*//g;

	
	read INPUT, $in, 1;
	
	### This is the source lot ID ###
	read INPUT, $in, 15;
	$rCPRHead->{sLOT} = unpack "A15", $in;
	$rCPRHead->{sLOT} =~ s/[^0-9A-Za-z]*//g;
	
	read INPUT, $in, 1;
	read INPUT, $in, 3;
	$rCPRHead->{sPROB} = unpack "A3", $in;
	$rCPRHead->{sPROB} =~ s/[^0-9A-Za-z]*//g;
	$rCPRHead->{sPROB} = 0 if $rCPRHead->{sPROB} >254;
	
	read INPUT, $in, 2;
	$rCPRHead->{iSNNUM} = char2short($in);
	
	read INPUT, $in, 2;
	$rCPRHead->{iSNSIZE} = char2short($in);
	
	read INPUT, $in, 2;
	$rCPRHead->{iNUMDIE} = char2short($in);
	
	read INPUT, $in, 1;
	$rCPRHead->{cF1SSEG} = unpack "c", $in;
	#print "SEG $rCPRHead->{cF1SSEG}\n";

	read INPUT, $in, 1;
	$rCPRHead->{cF1ESEG} = unpack "c", $in;
	#print "SEG $rCPRHead->{cF1ESEG}\n";

	### SEGMENT COUNT
	$SEG_COUNT = ($rCPRHead->{cF1ESEG} - $rCPRHead->{cF1SSEG}) +1;
	#print "S.E ($rCPRHead->{cF1ESEG}) - S.S ($rCPRHead->{cF1SSEG}) +1 = SEG_COUNT: $SEG_COUNT\n";
	
	read INPUT, $in, 2; #spare
	$spare = unpack "i", $in;
	
	read INPUT, $in, 2;
	$rCPRHead->{iDARCNT} = char2short($in);
	
	# 32 test #'s of data log 
	$chk_order = 0;

	@duplicate_chk = 0;
	
	for($ii =1; $ii<= 32; $ii++)
	{
		read INPUT, $in, 1;
		$rCPRHead->{aTEST_NUM} = unpack "c", $in;

		if($rCPRHead->{aTEST_NUM} != 0)
		{
			if($duplicate_chk[$rCPRHead->{aTEST_NUM}] == 1)
			{
				print "Duplicate test number! Kill Converter\n";
				die;
			}
	#		print "$rCPRHead->{aTEST_NUM}\n";
			push (@test_logged, $rCPRHead->{aTEST_NUM});

			### Make sure no duplicate test numbers (typo's)
			$duplicate_chk[$rCPRHead->{aTEST_NUM}] = 1;
		
			#### Make sure test are in proper order.
       		        if($rCPRHead->{aTEST_NUM} < $chk_order)
                	{
                        	#print "Test order is descending\n";
                	}
	
			$chk_order = $rCPRHead->{aTEST_NUM};	
		}
	}


	# 32 function #'s in dl sort
	read INPUT, $in, 32;
	$rCPRHead->{aFUNC_NUM} = unpack "c" x 32, $in;
	
	#skip test num mean 3 x short int
	read INPUT, $in, 2*3;

	#skip seg mean 3 x char
	read INPUT, $in, 3;

	#run file name
	read INPUT, $in, 1;
	read INPUT, $in, 14;
	$rCPRHead->{sRUN_NAME} = unpack "A8", $in;
	($rCPRHead->{sRUN_NAME},$in) = split(/\./,$rCPRHead->{sRUN_NAME});
	
	#test file name
	read INPUT, $in, 1;
	read INPUT, $in, 15;
	$rCPRHead->{sTEST_NAME} = unpack "A8", $in;
	($rCPRHead->{sTEST_NAME},$in) = split(/\./,$rCPRHead->{sTEST_NAME});

	#print "RUN_NAME: $rCPRHead->{sRUN_NAME}   TEST_NAME: $rCPRHead->{sTEST_NAME}\n";

	### Now that I have the test plan name, get the "GOOD Bins" from the PRN file ###
        #print "Parse using testplan name $rCPRHead->{sTEST_NAME}\n";
        $rCPRHead->{good_bins_prn} = parse_prn($rCPRHead->{sTEST_NAME}, $rCPRHead->{sLOT}, $rCPRHead->{sOPER}, $rCPRHead->{sPROB});


	#end date
	read INPUT, $in, 1;
	read INPUT, $in, 19;
	$rCPRHead->{sEND_DATE} = unpack "A19", $in;
	$rCPRHead->{sEND_DATE} =~ s/^[\n]//;
	
	#spare
	read INPUT, $in, 340;
	
	#pass count 
	read INPUT, $in, 400;
	
	#var dir
	read INPUT, $in, 500;
	
	### SET TEST COUNT ###

	if($SEG_COUNT > 1 && $SEG_MODE != 2)
        {
		### IF MULTI SEGMENTS & MODE IS NOT EQUAL TO 2 
		$rCPRHead->{iTEST_CNT} = ($#test_logged * 2) +1;  #+1 only need to worry about one '0' ex. 0-9 = 10 test  
	}
	else
	{
		$rCPRHead->{iTEST_CNT} = $#test_logged;
	}
	
	#print "TEST COUNT $rCPRHead->{iTEST_CNT}   $#test_logged\n";

	
	return $rCPRHead;

} # end of function

###############################################################################
#Purpose : read wafer header, and result data of each die
#Assumption:
#Parameter:
#Return:
###############################################################################
sub ReadWaferData{
	my $rCPRHead = shift;
	my ($sWaferNum, $rBinSum, $iDieTested, $SoftBins) = ReadWaferHeader();
	(my $rDieData, my $iDieLog, my $rGoodBin) = ReadTestResult($rCPRHead->{iDARCNT},
		$rCPRHead->{iSNNUM},$rCPRHead->{iSNSIZE},$rCPRHead->{iTEST_CNT});
	return($sWaferNum, $rBinSum, $iDieTested, $rDieData, $iDieLog, $rGoodBin, $SoftBins);
}

###############################################################################
#Purpose : read wafer header, each wafer has a header and its size is
#1536 which is equal to the block size
#Assumption:
#Parameter:
#Return:
###############################################################################
sub ReadWaferHeader
{
	my $iDieNumber = 0;
	my $iUTOT      = "";
	my $CSNX       = "";
	my $SPARE1     = "";
	my @uFAIL      = ();
	my @aiUTFAIL   = ();
	my @aiUBEST    = ();
	my @aiUSORT    = ();
	my @aiUBIN     = ();
	my $C10FN      = "";
	my($in,$i);
	
	#read wafer number
	read INPUT, $in, 1;
	read INPUT, $in, 4;
	my $sWaferNum = unpack "a4", $in;
	$sWaferNum =~ s/[^0-9]+//g;
	
	#read the fail counters
	for ($i = 0; $i < 250; $i++){
		read INPUT, $in, 2;
		#$uFAIL[$i] = char2short($in);
	}

	#read total test counters
	for ($i = 0; $i < 250; $i++){
		read INPUT, $in, 2;
		#$aiUTFAIL[$i] = char2short($in);
	}

	#read best yield counters
	for ($i = 0; $i < 25; $i++){
		read INPUT, $in, 4;
		#$aiUBEST[$i] = char2int($in);
	}

	#read sort counters
	for ($i = 0; $i < 25; $i++){
		read INPUT, $in, 4;
		$aiUSORT[$i] = bcd2int($in);
	}
	
	#read bin counters
	for ($i = 0; $i < 25; $i++){
		read INPUT, $in, 4;
		$aiUBIN[$i] = bcd2int($in);
	}

	#total die count
	read INPUT, $in, 4;
	$iUTOT = bcd2int($in);
	
	#1 of N value saved
	read INPUT, $in, 2;
	#$C10FN = char2short($in);
	#print "C10FN = $C10FN\n";
	
	#current data pointer
	read INPUT, $in, 2;
	#$CSNX = char2short($in);
	#print "CSNX = $CSNX\n";
	
	read INPUT, $in, 223;
	#$SPARE1 = unpack "c224", $in;
	
	return ($sWaferNum,\@aiUBIN,$iUTOT, \@aiUSORT);
}

###############################################################################
#Purpose : ReadTestResult
#- the cpr file separates test results with record blocks of 1536 bytes.
#- dies per record blocks  = SNNUM
#- records per wafer = DARCNT
#- bytes per die = SNSIZE
#Assumption:
#Parameter:
#Return:
###############################################################################
sub ReadTestResult
{	
	my $iRecPerWfr = shift;
	my $iDiePerRec = shift;
	my $iBytePerDie = shift;
	my $iTestCnt   = shift;
	
	my $iDieCount = 0;
	my @aDie = ();
	my @aGoodBin = ();
	my ($iTmp,$in,$k,$j,$i,$Ret);
	$Tmp_cnt = 0;

	for ($k = 0; $k < $iRecPerWfr; $k++){
		for ($j = 0; $j < $iDiePerRec; $j++){
			#get die serial number
			$Ret = read(INPUT, $in, 2);
	
			if($Ret != 2){
				if($Ret == 0){return (\@aDie, $iDieCount);}
				next;
			}
			else{	
				$iTmp = unpack "cc",$in;
			
				if($iTmp == 0 && $Tmp_cnt eq "0"){$Tmp_cnt++;} #End of Byte 1, still have byte 2
				elsif($iTmp == 0){next;} #end of Byte 2, next-
			}								
			$aDie[$iDieCount]->{iSERIAL} = char2short($in);
	
			#get die bin
			read INPUT, $in, 1;
			my $bits = "";
			$bits = unpack "B8", $in;
			$aDie[$iDieCount]->{iBIN} = (unpack "c", $in) & 127;
		
	
			if (substr($bits, 0, 1) eq "0")
			{
				$aGoodBin[$aDie[$iDieCount]->{iBIN}] = 1;
			}
			else
			{
				$aGoodBin[$aDie[$iDieCount]->{iBIN}] = 0;
			}
	
	
			### MODE DETERMINES LOOP COUNT ###
		
			if($SEG_COUNT > 1 && $SEG_MODE == 2)
			{
				$run_cnt = 1;
				### Let's set iTEST_CNT to proper value (adjusting for multi-segments)
       				$rCPRHead->{iTEST_CNT} = $#test_logged;
	
				for($i = 0; $i <=  $#test_logged; $i++)
                        	{
                                	#Test Result Flag
	                                read INPUT, $in, 1;
       		                         $aDie[$iDieCount]{aTEST}[$i]->{bFLAG} = (unpack "b8", $in);
               		                 #Test Result
                       		         read INPUT, $in, 4;
                               		
					### ONLY IF DATA EXIST ###
                                        if (substr($aDie[$iDieCount]{aTEST}[$i]->{bFLAG}, 7, 1) eq "1")
					{
				 		$aDie[$iDieCount]{aTEST}[$i]->{fRESULT} = char2float($in);
                               		 	$aDie[$iDieCount]{aTEST}[$i]->{fTESTNUM} = $test_logged[$i];
	                       		} 
					
					### INPUT BYTES FOR TEST FOR EACH SEGMENT ###
					if($run_cnt < $SEG_COUNT)
					{
						$i--;
						$run_cnt++;
					}
					else
					{
						$run_cnt = 1;
					}							
					
				}
			}
	
			elsif($SEG_COUNT > 1 && $SEG_MODE != 2)
			{
				$jj = -1;
				$run_cnt = 1;
				
				for($i = 0; $i <=  $#test_logged; $i++)
                                {
					#Test Result Flag
                                        read INPUT, $in, 1;
                                         
					$jj++;
					$aDie[$iDieCount]{aTEST}[$jj]->{bFLAG} = (unpack "b8", $in);
                                         #Test Result
                                         read INPUT, $in, 4;

                                        ### ONLY IF DATA EXIST ###
                                        if (substr($aDie[$iDieCount]{aTEST}[$jj]->{bFLAG}, 7, 1) eq "1")
                                        {
                                                $aDie[$iDieCount]{aTEST}[$jj]->{fRESULT} = char2float($in);
                                                $aDie[$iDieCount]{aTEST}[$jj]->{fTESTNUM} = ($test_logged[$i] * 10) + $run_cnt ;
                                        }
                   			
                                        ### INPUT BYTES FOR TEST FOR EACH SEGMENT ###
                                        if($run_cnt < $SEG_COUNT)
                                        {
                                                $i--;
                                                $run_cnt++;
                                        }
                                        else
                                        {
                                                $run_cnt = 1;
                                        }
                                }
			}
	

			else
			{	
				### Let's set iTEST_CNT to proper value (adjusting for multi-segments)
                                $rCPRHead->{iTEST_CNT} = $#test_logged ;
				for($i = 0; $i <=  $#test_logged; $i++)
                                {
                                        #Test Result Flag
                                        read INPUT, $in, 1;
                                         $aDie[$iDieCount]{aTEST}[$i]->{bFLAG} = (unpack "b8", $in);
                                         #Test Result
                                         read INPUT, $in, 4;
					 
					### ONLY IF DATA EXIST ###     
                                        if (substr($aDie[$iDieCount]{aTEST}[$i]->{bFLAG}, 7, 1) eq "1")
                                        {      
                                                $aDie[$iDieCount]{aTEST}[$i]->{fRESULT} = char2float($in);     
                                                $aDie[$iDieCount]{aTEST}[$i]->{fTESTNUM} = $test_logged[$i];   
					}    
                                }	
			}
			$iDieCount++;
		}
		
		#read excess bytes on record
		$Ret=1;
		while ( ((tell(INPUT) % 1536) != 0) && $Ret!=0 ){
			$Ret = read INPUT, $in, 1;
   	}
	}	
	
	#return the referrence of the Die structure and number of dies found
	return (\@aDie, $iDieCount, \@aGoodBin);
}


sub	char2short{
	my ($IN) = @_;
	my @b = unpack	"c"	x	2, $IN;
	#my $ret = unpack	"S", (pack "cc", $b[1],	$b[0]);
	my $ret = unpack	"S", (pack "cc", $b[0],	$b[1]);
	return $ret;
}

sub	char2int
{
	my ($IN) = @_;
	my @b = unpack	"c"	x	4, $IN;
	#my $ret = unpack	"i", (pack "cccc", $b[3],	$b[2], $b[1],	$b[0]);
	my $ret = unpack	"i", (pack "cccc", $b[0],	$b[1], $b[2],	$b[3]);
	return $ret;
}

sub	char2float
{
	my ($IN) = @_;
	my @b = unpack	"c"	x	4, $IN;
	#my $ret = unpack	"f", (pack "cccc", $b[3],	$b[2], $b[1],	$b[0]);
	my $ret = unpack	"f", (pack "cccc", $b[0],	$b[1], $b[2],	$b[3]);
	return $ret;
}

sub	by_number	
{
	my $a = shift;
	my $b = shift;
	if ($a < $b){
		-1;
	}
	elsif	($a	== $b){
		0;
	}
	elsif	($a	>	$b){
		1;
	}
}

##############################################################################
# Function : bcd2int
# Description : converts binary coded decimal to int data type
# ex. 9634H  ---> 9634D
# Parameters:
#	- [i]ulValue = bcd code value
# Assume:
# Return: return the decimal value
##############################################################################/
sub bcd2int{
	my ($IN) = @_;
	my @b = unpack	"C"	x	4, $IN;
	my $sTmp ="";
	$sTmp = pack "aaaaaaa", $b[3] & 0x0F, $b[2] >> 4, $b[2] & 0x0F,
	 $b[1] >> 4, $b[1] & 0x0F,$b[0] >> 4, $b[0] & 0x0F;
	my $i = $sTmp * 1;
	return $i;
}


####################
# PARSE PRN ROUTINE
####################
sub parse_prn
{
         my ($testplan_prn, $s_LOT, $s_OPER, $s_PROB) = @_;


	############
        # VARIABLES
        ############
        my $hbin_num_prn  = "";
        my $testname_flag = 0;
	

	### CHECK IF TESTPLAN EXISTS ###
	#my (@testplans)   = `find $ENV{ENV_TP_RAW} -name "${testplan_prn}*.PRN"`; 
	my (@testplans)   = `find /data/amkor_ph_ft_fet/PRN -name "${testplan_prn}*.PRN"`;
	chomp($testplans[0]);
        if (! -e "$testplans[0]")
        {
                ### MOVE DATALOG FILE TO BAD DIR ###
                #system "/bin/mv -f $file $ENV{ENV_TP_NOCONV}/.";
                #print "$file - No Raw Testplan is available. Testplan is $testplan_prn\n";
		dpExit(4, "ERROR: Test Plan file (PRN) missing!");

                #####################################################
                # ADD FILE & MISING TP TO LOG (GET'S E-MAILED DAILY)
                #####################################################
                #$tp_log = "$ENV{ENV_LOG}/Missing_testplans.txt";
                #open (MISSING_TP, ">>$tp_log");
		#(@dummy) = split /\//, $file;
                #print MISSING_TP "$dummy[$#dummy]:$testplan_prn\n";
                #close(MISSING_TP);

                exit 1;
        }

  
	###############
        # OPEN TP FILE
        ###############
	$testplan_prn = $testplans[0];
        open FH, "$testplan_prn" or die "Can't open $testplan_prn file\n";

        ############
        # PARSE PRN
        ############
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
                        $hbin_num_prn = substr $_,22, 4;
                        $hbin_num_prn =~ s/\s+//g;
			$datalog_chk = substr $_,18,8;
                        
			### COLLECT GOOD HW BINS
                        if ($hbin_num_prn =~/\b\d{1,2}\b/)
                        {
                               	$rCPRHead->{good_bins_prn}[$hbin_num_prn] = $hbin_num_prn; 
                                print "Good Bins: $rCPRHead->{good_bins_prn}[$hbin_num_prn]\n";
                        }
               
		}
       
		### GET ALTERNATE SEGMENTS 
		elsif($_=~/ALTERNATE SEGMENTS/)
		{
			($trash,$SEG_MODE) = (split /=/, $_);
			#print "SEGMENT MODE: $SEG_MODE\n"; 
		} 
		
	}
        close(FH);

	return($rCPRHead->{good_bins_prn});



}
 
1;

