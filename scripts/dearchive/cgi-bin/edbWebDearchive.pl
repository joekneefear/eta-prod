#! /apps/exensio/pdf/exn41/bin/perl_db
##! /usr/bin/perl
#
# When	     Who            Comments
# ---------- -------------- ------------------------------------
# 05/27/2009 Ben Rommel Kho Author
# 07/13/2009 Ben Rommel Kho Read stdf file to determine file type. Exclude testplan from the monitoring
# 07/14/2009 Ben Rommel Kho Fixed bug during data check in db.
# 07/22/2009 Ben Rommel Kho Log transaction to ewb_statistics db.
# 07/29/2009 Ben Rommel Kho Allow "all years" search
# 08/20/2009 Ben Rommel Kho Return both raw and stdf files.
# 08/26/2010 Ben Rommel Kho Adjusted to handle Summarized Files. Also, to display whether part or summary
#			    data is still avialable in the db
# 09/19/2012 Ben Rommel Kho Adjusted for MFT. Used DBI instead of Sybase::CTlib
# 02/05/2012 Ben Rommel Kho Use Linux find command. Group find search criteria to optimize find
#			    execution. Also, log activity into ewb_statistics.
# 02/06/2013 Ben Rommel Kho Search lot in "/data/<plant>/trash" if not in IN, BAD, or GOOD dir.
#			    Improved lot monitoring search routine.
# 10/28/2015 Ben Rommel Kho Modified for Exensio
# 29-Sep-2016 Gilbert Miole Removed the STDF in stdf_filter RETURN RESULT portion.
# 14-Oct-2016 Gilbert Miole Fixed issue if old file archived don't have MD5 tag.
# 15-Sep-2022 jgarcia use hquxewb02p.onsemi.com for getting file location in archive for faster response.
#
#
# Purpose: To be used along with the EWB Dearchive Web Page
#
# Script Functions:
#	1) Search data file in archive dir.
#	2) Check if lot data if still in EWB DB
#	3) Reload data file and provide status



###############
# LOAD MODULES
###############
use File::Find	  ;
#use lib "/data/edbmgr/edb_root/stdf_v2.2.0/lib";
#use EDBUtil;
use DBI	   ;
use IPC::Open3;
use File::Copy;
use mod_routines;


#################
# DISPLAY SYNTAX
#################
if (! $ARGV[0])
{
	print "syntax:\n";
	print "\tscript -s(to search archive) <plant> <lot info 1>,<lot info n>\n";
	print "\t      where: <lot info> consist of <lotid>:<envnames '-' delimited>:<year|all>:<month|all>\n";
	print "\tscript -r(to reload files) <path/lotid>\n";
	print "\tscript -l(log restore trans to db) <plant> <userid> <restored_file_count>\n";
	print "\tscript -m(to monitor reloaded files) <monit_time> \"<env 1>:<env n>\" \"<lotid 1>:<lotid n>\" <n>\n";
	exit -1;
}


###################
# GLOBAL VARIABLES
###################
my $arch_dir    = "/archives";
my $lotid       = "";
my %datafiles   = ();
my $no_dup      = ();
my %result	= ();
my $monit_time  = "";
   $SYB_EWBAP_DEV = "ewb-syb-ap-dev";	### FOR DEFERENCING. DON'T DECLARE WITH "my"
   $SYB_EWBAP     = "ewb-syb-ap";
   $SYB_EWBUS_DEV = "ewb-syb-us-dev";
   $SYB_EWBUS     = "ewb-syb-us";



#########################
# SEARCH FILE IN ARCHIVE
#########################
if ($ARGV[0] eq "-s")
{
	my $plant       = $ARGV[1];
	my (@lotinfos)  = split /\,/, $ARGV[2];
	my $tmp_params  = ();
	my %find_params = ();
	my $all_flag    = "N";		# "Y" MEANS ALL ENVS, YR & MONTH.

	#######################################
	# OPTIMIZE FIND CRITERIA BEFORE SEARCH
	#######################################
	### SCENARIO #1: FOR ENV=ALL; YEAR=ALL; MONTH=ALL ###
	if ($ARGV[2]=~/\w+?\-\w+?\:All/i)
	{
		my $path         = "";
		my $lot_criteria = "";
		my @lots         = ();
		foreach my $lotinfo(@lotinfos)
		{
			my ($lotid, $envs, $year, $month) = split /\:/, $lotinfo;

			### FORM ARCH_DIR PATH PER ENV ###
			$path = join " ", map("$arch_dir/$plant/$_", split /\-/, $envs) if $path eq "";

			### PUSH LOTID ###
			push(@lots, $lotid);

			### CREATE LOT SEARCH CRITERIA ###
			$lot_criteria .= ($lot_criteria eq "") ? "-name \"*${lotid}\*\" " : "-o -name \"*${lotid}\*\" ";
		}

		### SEARCH ARCHIVE ###
		&search_archives($path, $lot_criteria, \@lots);
	}
	### SCENARIO #2: A MIX COMBINATION OF ENV, YEAR, & MONTH
	else
	{
		my @lots          = ();
		my %find_criteria = ();
		my %env_all_all   = ();

		# SORT TO BETTER ANALYZE & FUSE LOT SEARCH CRITERIA
		# -------------------------------------------------
		# PRIORITY 1: YR==ALL & MONTH==ALL
		# PRIORITY 2: YR!=ALL & MONTH==ALL
		# PRIORITY 3: YR!=ALL & MONTH!=ALL
		my @priority1 = ();
		my @priority2 = ();
		my @priority3 = ();
		foreach my $line(@lotinfos)
		{
        		my ($lot, $env, $yr, $mo) = split /\:/, $line;
			if ($yr=~/All/i && $mo=~/All/i)
			{	push(@priority1, $line);	}
			elsif ($yr!~/All/i && $mo=~/All/i)
			{	push(@priority2, $line);	}
			else
			{	push(@priority3, $line);	}
		}
		@lotinfos = ();
		push(@lotinfos, @priority1);
		push(@lotinfos, @priority2);
		push(@lotinfos, @priority3);


		### GROUP SIMILAR SEARCH CRITERIA ###
		foreach my $lotinfo(@lotinfos)
        	{
			### FORMAT: $lotid, $env, $year, $month ###
			my ($lotid, @others) 		 = split /\:/, $lotinfo;
			pop(@others) if $others[$#others]=~/All/i;	### REMOVE MONTH IF ALL
			pop(@others) if $others[$#others]=~/All/i;	### REMOVE YEAR  IF ALL

			# KEY GENERATION LOGIC:
			# ---------------------
			# 1) USE "ENV" AS KEY, IF ENV/ALL/ALL OR ENV/2012/JAN.
			# 2) USE "ENV/2012" AS KEY, IF "ENV/2012/JAN"
			# 3) OTHERWISE, USE "ENV:YR:MONTH" AS KEY
			my $key = join  ":", @others;
			if (exists($find_criteria{$others[0]}))
                        {
                                $key = $others[0];			### SCENARIO 1
                        }
			elsif (exists($find_criteria{"$others[0]:$others[1]"}))
			{
				$key = "$others[0]:$others[1]";		### SCENARIO 2
			}

			### SKIP DUPLICATE LOTID ###
			next if $find_criteria{$key} =~ /$lotid/i;

			### STORE TO HASH FOR LATER SEARCH )###
			if (! exists($find_criteria{$key}))
			{
				$find_criteria{$key} = "-name \"*${lotid}*\" ";
			}
			else
			{
				$find_criteria{$key} .= "-o -name \"*${lotid}*\" ";
			}

			### KEEP LOT LIST ###
			push(@lots, $lotid);
		}
		### EXECUTE EACH FIND COMMAND ###
		foreach my $key (keys %find_criteria)
		{
			my ($env, $yrmo) = split /\:/, $key, 2;
			   $yrmo =~ s/\:/\//g;			### REPLACE : with /
			   $yrmo =~ s|/All/|/\*|i;		### REPLACE "ALL YEAR" WITH ASTERISK
			my $path = join " ", map("$arch_dir/$plant/$_/${yrmo}", split /\-/, $env); ### HANDLES SINGLE OR MULTIPLE ENVS
			&search_archives($path, $find_criteria{$key}, \@lots);
		}
	}

        ####################################
        # CHECK IF LOT DATA ARE STILL IN DB
        ####################################
        #foreach $lotid(sort {$a<=>$b} keys %datafiles)
        #{
        #        $datafiles{$lotid}{DB_STAT} = &check_data_in_db($plant, $genv, $lotid);
        #}


        ################
        # RETURN RESULT
        ################
        foreach $lotid(sort {$a<=>$b} keys %datafiles)
        {
                #print "lotid prn=$lotid\n";

                ### SEARCH RESULT IS IN "FILENAME:FILESIZE" FORMAT ###
		#<<< 10/29/2015 DISABLED STDF FOR THE MEANTIME >>>#
		#GilbertM<<< 29-Sep-2016 ENABLE BACK STDF >>>#
                #my $stdf_filter = "[\.\_]TD|[\.\_]STDF";
                my $stdf_filter  = "[\.\_]TD";
                #<<< my @stdf_files  = grep /$stdf_filter/i, @{$datafiles{$lotid}{DATAFILES}};
                #my @raw_files   = grep !/$stdf_filter/i, @{$datafiles{$lotid}{DATAFILES}};
								my @raw_files   = @{$datafiles{$lotid}{DATAFILES}};

                ### RETURN HEADER INFO ###
                my $stdf_count = $#stdf_files + 1;
                my $raw_count  = $#raw_files  + 1;
                #print "$lotid|$raw_count|$stdf_count\n";
								print "$lotid|db_status|$datafiles{$lotid}{DB_STAT}|$raw_count|$stdf_count\n";
								#print "$lotid|$raw_count|$stdf_count\n";

                #<<< if ($#stdf_files > -1)
                #<<< {
                #<<<         foreach my $file(@stdf_files)
                #<<<         {
                #<<<                 print "$lotid|stdf|$file\n";
                #<<<         }
                #<<< }
                if ($#raw_files > -1)
                {
                        foreach my $file(@raw_files)
                        {
                                print "$lotid|raw|$file\n";
                        }
                }
        }

}
###########################################
# OLD ARCHIVE SEARCH ROUTINE (UNOPTIMIZED)
###########################################
elsif ($ARGV[0] eq "-s_old")
{
	my $plant      = $ARGV[1];
	my (@lotinfos) = split /\,/, $ARGV[2];
	my @dirs       = ();
	my $genv       = "";			### CAPTURE LAST ENV FROM FOR LOOP

	#######################################
	# PARSE PARAMETERS THEN SEARCH ARCHIVE
	#######################################
	foreach $lotinfo(@lotinfos)
	{
		my $envs  = "";
		my $year  = "";
		my $month = "";
		($lotid, $envs, $year, $month) = split /\:/, $lotinfo;

		### CHECK/CLEAN ARGUMENTS ###
		$month = ($month=~/ALL/i) ? "" : "/$month";
		$lotid =~ s/\\//g; 				### REMOVE "\" (ESCAPE CHAR)

		### INITIALIZE HASH ###
		$datafiles{$lotid}{DB_STAT}       = "";
		@{$datafiles{$lotid}{DATA_FILES}} = ();

		### CREATE SEARCH PATH ###
        	foreach $env(split /\-/, $envs)
        	{

			my $env_path = "${arch_dir}/${plant}/${env}";

			### ALL ARCHIVE YEARS ###
			if ($year =~ /ALL/i)
			{
				my @years = `ls $env_path`;
				foreach $tmpyr (@years)
				{
					chomp($tmpyr);
					if ($tmpyr =~ /\d{4}/ && -d "${env_path}/$tmpyr")
					{
						#print "${env_path}/${tmpyr}${month}\n";
						push (@dirs,"${env_path}/${tmpyr}${month}");
					}
				}
			}
			### SINGLE ARCHIVE YEAR ###
			else
			{
				#print "${env_path}/${year}${month}\n";
                		push (@dirs,"${env_path}/${year}${month}");
			}

			### CAPTURE LAST ENV ###
			$genv = $env;
        	}


		### SEARCH FILE IN ARCHIVE ###
		find({wanted => \&wanted, follow_fast => 1}, @dirs);
	}


	####################################
        # CHECK IF LOT DATA ARE STILL IN DB
        ####################################
	foreach $lotid(sort {$a<=>$b} keys %datafiles)
	{
		$datafiles{$lotid}{DB_STAT} = &check_data_in_db($plant, $genv, $lotid);
	}


	################
	# RETURN RESULT
	################
	foreach $lotid(sort {$a<=>$b} keys %datafiles)
        {
		#print "lotid prn=$lotid\n";

		### SEARCH RESULT IS IN "FILENAME:FILESIZE" FORMAT ###
		#my $stdf_filter = "[\.\_]TD\:\|[\.\_]TD\.gz\:\|[\.\_]STDF\:\|[\.\_]STDF\.gz\:\|\_SUMM\.\*TD\|\_SUMM\.\*STDF";
		my $stdf_filter = "[\.\_]TD|[\.\_]STDF";
		my @stdf_files  = grep /$stdf_filter/i, @{$datafiles{$lotid}{DATAFILES}};
		my @raw_files   = grep !/$stdf_filter/i, @{$datafiles{$lotid}{DATAFILES}};

		### RETURN HEADER INFO ###
		my $stdf_count = $#stdf_files + 1;
		my $raw_count  = $#raw_files  + 1;
		print "$lotid|db_status|$datafiles{$lotid}{DB_STAT}|$raw_count|$stdf_count\n";

		if ($#stdf_files > -1)
        	{
                	foreach my $file(@stdf_files)
                	{
                        	print "$lotid|stdf|$file\n";
                	}
        	}
		if ($#raw_files > -1)
		{
			foreach my $file(@raw_files)
                	{
                       		print "$lotid|raw|$file\n";
                	}
		}
	}
}
###################
# RELOAD DATA FILE
###################
elsif ($ARGV[0] eq "-r")
{
	#my $pid      = $ARGV[1];
	my $file     = $ARGV[1];
	my $cur_time = time;
	my ($junk1, $junk2, $site, $envname, $yr, $mo, $filename, $junk3)  = split /\/|\_MD5/i, $file;
	   $filename .= ".gz" if ($file=~/\.gz/i && $filename!~/\.gz/i);


#print "DEBUG SPLIT: JUNK1=$junk1\nJUNK3=$junk2\nSITE=$site\nENV=$envname\nYR=$yr\nMO=$mo\nFILE:$filename\nJUNK3=$junk3\n\n";
	##########################
	# CREATE DEARCHIVE FOLDER
	##########################
	my $dearchive_dir = "/apps/exensio_data/data/${envname}/dearchive";
	my $final_dir     = "/apps/exensio_data/data/${envname}";
	system "/bin/mkdir -p $dearchive_dir" if ! -e $dearchive_dir;


	##############
	# RELOAD FILE
	##############
	&copy_file("$file","${dearchive_dir}/${filename}");
	&doUncompress("${dearchive_dir}/${filename}") if $filename =~/\.gz/i;
	$filename =~s/\.gz//i if $filename =~/\.gz/i;
	&moveFile("${dearchive_dir}/${filename}", $final_dir);


	########################################################################
	# RETURN CURRENT TIME TO LIMIT MONITORING TO RESENTLY LOADED FILES ONLY
	########################################################################
	print "$cur_time";
}
##########################
# MONITOR LOAD DATA FILES
##########################
elsif ($ARGV[0] eq "-m")
{
	   $monit_time = $ARGV[1];
	my $dirs       = join " ", map("/apps/exensio_data/data/$_", split(/\:/, $ARGV[2]));
	my $dirs2       = join " ", map("/archives-yms/data/$_", split(/\:/, $ARGV[2]));
	my (@lotids)   = split(/\:/, $ARGV[3]);
	my $lotids     = "";
	my $filter     = "";
	my @files      = ();
	my $trash_lots = "";
	my $mainFile = "";
	#my $envFolder = $_;
  #print("$envFolder\n");
  #print "$dirs\n";
	#######################
	# FORM SEARCH CRITERIA
	#######################
	foreach my $loclotid (@lotids)
	{
		$lotids .= ($lotids ne "") ? " -o -name \"\*$loclotid\*\"" : " -name \"\*$loclotid\*\"" ;
	}

	######################################
        # SEARCH LOADED LOTS(EXCEPT TESTPLANS)
        ######################################
	@files = `/usr/bin/find $dirs \\\( $lotids \\\) ! -name "*.TP*" ! -name "*.err"`;


	##################################
  	# DETERMINE AND PRINT FILE STATUS
	##################################
	foreach $file(sort @files)
	{
		chomp($file);


		##################
		# DET FILE STATUS
		##################
		$mainFile = $file;
		my $size         = (stat($file))[7];
		my $status       = "";
		my $refresh_flag = "N";      ### Y=REFRESH PAGE; ALL N=DONE. STOP REFRESHING PAGE
		my $status_color = "";
		my (@dummy)      = split /\//, $file;
		my $fname        = pop @dummy;
		my $envFolder    = $dummy[$#dummy];
		my $dir          = join "/", @dummy;
			#print "$dir\n";

		### MONITOR RECENTLY-LOADED FILES ONLY ###
		next if (stat($file))[9] < $monit_time || $size < 1;
		#next if $dummy[$#dummy] =~ /^Processed/i && $dummy[$#dummy - 1] !~ /stage|Processed/i;
    #print "$dummy[$#dummy]||$dummy[3]|$dummy[4]||scalar(@dummy)==4\n";
		######################
		# CONV OR LOAD FAILED
		######################
		if ($dummy[$#dummy] =~ /NotProcessed/i)
		{
			#if ($dir !~ /stage/i)				# BEFORE STAGE
			#{
				$status       = "conv failed";
				$status_color = "red";
			#}
			#elsif ($dummy[$#dummy-1] =~ /stage/i)		# IMMEDIATELY AFTER STAGE
		#	{
		#		$status       = "load failed";
		#		$status_color = "red";
		#	}
			# elsif ($dummy[$#dummy-1] =~ /Processed/)	# AFTER PROCESSED DIR
			# {
			# 	$status       = 'loaded_w/o_bin';
			# 	$status_color = "black";
			# }
			# $refresh_flag = "N";
		}
		#################################
		# REWORK(REQUIRES DEPENDECY FILE)
		#################################
		elsif ($dummy[$#dummy] =~ /ReworkFiles/i)
		{
			$status       = "conv failed(lack of file)";
			$status_color = "red";
			$refresh_flag = "N";
		}
		########################
		# LOADED OR BIN LOADING
		########################
		elsif ($dummy[$#dummy] =~ /^Processed/i) {

			# ### NEXT LEVEL "PROCESSED" DIR EXISTS ###
			# if (-e "${dir}/Processed")
			# {
			# 	$status       = "bin loading";
			# 	$status_color = "green";
			# 	$refresh_flag = "Y";
			# }
			# ### LAST "PROCESSED" DIR ###
			# else
			# {
				#$status       = "loaded successfully";
				#print "IM HERE\n";
				#my @files = `/usr/bin/find $dirs2 \\\( $lotids \\\) ! -name "*.TP*" ! -name "*limit*"`;
				#foreach my $file (@files) {
				#	chomp($file);
				#	print "$file\n";
					##################
					# DET FILE STATUS
					##################
					# if($mainFile eq $file) {
					# 	my $size         = (stat($file))[7];
					# 	my $status       = "";
					# 	my $refresh_flag = "N";      ### Y=REFRESH PAGE; ALL N=DONE. STOP REFRESHING PAGE
					# 	my $status_color = "";
					# 	my (@dummy)      = split /\//, $file;
					# 	my $fname        = pop @dummy;
					# 	my $lastFolder    = $dummy[$#dummy];
					# 	my $dir          = join "/", @dummy;
					# 	if($lastFolder =~ /PRODUCTION/) {
					# 		$status = "IFF successfully generated, will be loaded into PRODUCTION";
					# 	} elsif($lastFolder =~ /SANDBOX/) {
					# 		$status = "IFF successfully generated, will be loaded into SANDBOX";
					# 	} else {
					# 		$status = "IFF successfully generated, will be loaded into QDE";
					# 	}
						$status       = "Please check Exensio Cloudsite after 15 mins as the data needs to be transmitted via FTP and loaded on Cloudsite.";
						$status_color = "black";
						$refresh_flag = "N";



			#}
		}
		###################################
		# STAGE FOR PARAM LOADING STATUS
		# 3 FOR CONV IN /data/env
		# 4 FOR CONV IN /data/env/env
		###################################
		#print "$dummy[$#dummy]||$dummy[3]|$dummy[4]\n";
	        elsif ($dummy[$#dummy] =~ $envFolder)
		{

		   #	$status       = ($file=~/stage/i) ? "param loading" : "for conv";
			 	$status       = "for conv";
			$status_color = "green";
			$refresh_flag = "Y";
		}
		#########################
		# UNKNOWN PROCESS FOLDER
		#########################
		else
		{
			$status       = "unknown state($dummy[$#dummy])";
			$status_color = "green";
			$refresh_flag = "Y";
		}


		##############
		# ADD SANDBOX
		##############
		#$status .= "(sandbox)" if $file =~/sandbox/i;

		#####################
		# RETURN FILE STATUS
		#####################
		print "$fname:$size:$status:$status_color:$refresh_flag\n";
	}
}
####################
# LOG RESTORED DATA
####################
elsif ($ARGV[0] eq "-l")
{
	my $username   = $ARGV[1];
	  ($username,) = split /\@/, $username if $username=~/\@/;
	   $username   = "UNKNOWN" if $username eq "";
	   $username   =~ s/\s+/\_/g;
	my $envname    = $ARGV[2];
	my $filecnt    = $ARGV[3];
	my $db_uid     = "EWB_LOG";
	my $db_pwd     = "passalog";
	my $db_name    = "ewb_statistics";
	my $db_svr     = $SYB_EWBUS;
        my $dsn        = "DBI:Sybase:database=${db_name};host=$db_svr;port=2025";
	my $dbh        = DBI->connect($dsn, $db_uid, $db_pwd ) or return("Failed DB Connection");
	my $date       = `date '+%m/%d/%y %H:%M:%S'`;
	chomp($date);
        my $sql        = "insert into web_dearchive_log
		          values (\"$date\", \"$envname\", \"$username\", $filecnt)";

	### ADD REC TO THE DB ###
	my $sth = $dbh->prepare($sql);
	$sth->execute() or die $DBI::errstr;
 	$sth->finish();
}

#<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< SUBROUTINE/S >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

sub check_data_in_db
{

	##################
	# LOCAL VARIABLES
	##################
        my $plant     = shift;
        my $env       = shift;
        my $lotid     = shift;
	   $lotid     =~ s/[\?\*]/\%/g;
	my $lotfilter = ($lotid =~ /\%/) ? "s.lot like \"$lotid\"" : "s.lot = \"$lotid\"";
	my $userid    = "EDB_OWNER";
	my $pwd       = "edbPWN3D";
        my $sql       = "";
        my $found     = "";
        #my ($d1,$d2,$db) = split /\s+/, `grep EDB_DATABASE /data/${plant}/env_variables/${env}.csh`;
        #my ($d3,$d4,$svr)= split /\s+/, `grep EDB_SERVER   /data/edbmgr/env_variables/mftConfig.csh`;
	chomp($svr);
	chomp($db);
        my $dsn       = "DBI:Sybase:database=${db};host=$$svr;port=2025";


	#########################
	# TRAP MISSING DB/SERVER
	#########################
	#return ("Undefined DB server. GOIT to manual intervene.") if $db eq "";
	#return ("Undefined DB. GOIT to manual intervene. ")       if $db eq "";
	return("") if $db eq "" || $svr eq "";


	#####################
	# OPEN DB CONNECTION
        #####################
        my $dbh = DBI->connect($dsn, $userid, $pwd ) or return("Failed DB Connection");
	# or die $DBI::errstr;


	#########################
	# 1) CHECK FOR PART DATA
	#########################
	$sql  = "select "
  	      . " s.lot "
              . "from   "
              . " session s inner join part p    "
	      . " on s.session_key=p.session_key "
	      . "where       "
	      . " $lotfilter "
	      . "union all   "
	      . "select "
	      . " s.lot "
	      . "from   "
	      . " session s inner join wafer_map wm "
	      . " on s.session_key=wm.session_key "
	      . "where      "
	      . " $lotfilter";

	my $sth = $dbh->prepare($sql);
           $sth->execute() or die $DBI::errstr;
        my @row = $sth->fetchrow_array();
	if ($#row > -1)
	{
		$found = "Part data is still available in EWB DB.";
        }
	$sth->finish();



	##########################################################
	# 2) CHECK FOR SESSION DATA IF PART DATA IS NOT AVAILABLE
	##########################################################
	if ($found eq "")
	{
		$sql = "select "
		     . " s.lot "
	  	     . "from   "
		     . " session s inner join session_synopsis ss "
		     . " on s.session_key=ss.session_key          "
		     . "where "
		     . " $lotfilter";

		my $sth = $dbh->prepare($sql);
		   $sth->execute() or die $DBI::errstr;
		my @row = $sth->fetchrow_array();
		if ($#row > -1)
		{
                	$found = "Summary data is still available in EWB DB." if $row[0] ne "";
		}
		$sth->finish();
	}

	return($found);
}



############################################
# SEARCH ARCHIVED DATA USING LINUX FIND CMD
############################################
sub search_archives
{
	my $path     = shift;
	my $criteria = shift;
	my $lotids   = shift;
	#my @files = `/usr/bin/find $path \\\( $criteria \\\)`;
	$cmd = "/usr/bin/find $path \\\( $criteria \\\)";
	my @files = runSSHcmd("hquxewb02p.fairchildsemi.com", "edbmgr", "milkshak3", $cmd);
#	my @files = `ssh edbmgr@hquxewb05p.fairchildsemi.com '/usr/bin/find $path \\\( $criteria \\\')`;

	foreach my $file(@files)
	{
		chomp($file);


		### SKIP TESTPLAN ###
		# next if $file =~ /[\.\_]\w*?TP/;	### ORIG TP FILTER
		next if $file =~ /[\.\_]TP/;

		### SKIP DUP FILE ###
		my $fn = substr($file, rindex($file, "/") + 1);
		next if exists($no_dup{$fn});

		### STORE RESULT INTO A HASH ###
		$no_dup{$fn} = 1;
		my $size     = &get_filesize($file);
		foreach my $lotid(@$lotids)
		{
			next if $fn !~ /$lotid/i;
			push(@{$datafiles{$lotid}{DATAFILES}}, "${file}:${size}");
			last;
		}

	}
}




##############################
# SEARCH DATA FILE IN ARCHIVE
##############################
sub wanted
{
	my @tmp_array = ();
        my $tmp_lotid = $lotid;
           $tmp_lotid =~ s/\?/\\w/g;	### REPLACE WILD CHAR "?" WITH PERL-EQUIVALENT "\w"
           $tmp_lotid =~ s/\*/\\w\+/g;  ### REPLACE WILD CHAR "*" WITH PERL-EQUIVALENT "\w+"


	#############################################
	# GET FILESIZE THEN STORE RESULT INTO A HASH
	#############################################
	#if (/$tmp_lotid/i && ! exists($no_dup{$File::Find::name}) && ! /[\.\_]\w+TP|[\.\_]TP/i)
	if (/$tmp_lotid/i && ! exists($no_dup{$File::Find::name}) && ! /[\.\_]TP/i)
	{
		my $file = $File::Find::name;
		my $size = &get_filesize($file);
                push(@{$datafiles{$lotid}{DATAFILES}}, "${file}:${size}");

		$no_dup{$File::Find::name}=1;	### TO TRAP SAME FILENAME BUT DIFF INODE NUMBER
	}
}

############################
# RESTORE FILE FROM ARCHIVE
############################
sub copy_file
{
	my $src_file = shift;
	my $dst_file = shift;
	my $status   = "Y";

	### ATTEMPT TO COPY THE FILE 3X ###
	foreach (my $i=0; $i<3; $i++)
	{
		system "cp $src_file $dst_file";
		if (-e $dst_file)
		{
			last;
		}
		elsif (! -e $dst_file && $i==2)
		{
			$status = "N";
		}
	}
	return ($status);
}


#####################
# DETERMINE FILESIZE
#####################
sub get_filesize
{
	my $loc_file = shift;
	my $size     = 0;
	if ($loc_file !~ /\.gz$/i)
        {
                my (@dummy) = stat($loc_file);
                $size = $dummy[7];
        }
        else
        {
               $result  = `gunzip -l "$loc_file"`;
               (@dummy) = split /\s+|\n/, $result;
               $size    = $dummy[6];
        }

        ### SHORTEN FILESIZE ###
        my $gb   = 1073741824;
        my $mb   = 1048576;
        my $kb   = 1024;
        my $unit = "";

        if ($size >= $gb)
        {
                $size /= $gb;
                $unit  = "Gb";
        }
        elsif ($size >= $mb)
        {
                $size /= $mb;
                $unit  = "Mb";
        }
        elsif ($size >= $kb)
        {
                $size /= $kb;
                $unit  = "Kb";
        }

        ### GET 1ST DECIMAL VALUE ONLY ###
        $dot = index($size,".");
        if ($dot > 0)
        {
                $size = substr($size,0,$dot+2);
        }
        $size .= $unit;

        return($size);
}


#######################
# CHECK STDF FILE TYPE
#######################
sub check_stdf_file_type
{
	my $loc_file = shift;
	my $type = "";

	open FH, $loc_file;
	read FH, $in, 6;
	my ($dump,$dump,$rec_typ,$rec_sub,$dump,$stdf_ver) = unpack "C" x 6, $in;
	close(FH);

	#print "typ: $rec_typ\n";
	#print "sub: $rec_sub\n";
	#print "stdf_ver: $stdf_ver\n";

	### STDFv3+ FILE ###
	if($rec_typ == 1 && $rec_sub == 200)
	{
        	#print "stdfv3+ file\n";
		$type = 2;
	}
	### STANDARD STDFv3/4 FILE ###
	else
	{
        	#print "std stdfv3/4\n";
		$type = 1;
	}
	return($type);

}
###################
# Uncompress a file
###################
sub doUncompress
{
  my $file = shift;

  return $file if($file !~ /\.Z$|\.gz$/i);

  my $pid = open3(\*GZIP_IN, \*GZIP_OUT, \*GZIP_ERR, "/usr/bin/gzip -vdf $file");
  waitpid( $pid, 0 );
  while(<GZIP_ERR>)
  {
    @values = split/\s+/;
  }
  close GZIP_IN;
  close GZIP_OUT;
  close GZIP_ERR;

  return $values[$#values];
}
#############
# Move a file
#############
sub moveFile
{
  $status   = 1;
  $fromFile = shift;
  $toFile   = shift;

  return 0 if (-d $fromFile);

  if($fromFile =~ /\*|\?/)
  {
    @files = glob $fromFile;

    foreach $file (@files)
    {
      $status = move($file, $toFile);
    }
  }
  else
  {
    $status = move($fromFile, $toFile);
  }

  return $status;
}
