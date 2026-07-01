#!/usr/bin/perl
#
#
# DATE        WHO            COMMENTS
# ----------  -------------- ----------------------------------
# 26-May-2015 Gilbert Miole  Author
# 18-Jun-2015 Gilbert Miole  Gzip file in NotProcessed dir.
# 10-Aug-2015 Gilbert Miole  Separate the deletion of .lim and .iff and also Processed and NotProcessed
# 25-Aug-2015 Gilbert Miole  Modified not to use config.ini and enhancement.
# 01-Jul-2016 Eric Alfanta   added functions scan_processed_wm_iff_nc & scan_dir_gzip_wm_iff_nc.
# 27-Jul-2017 Gilbert Miole  Change the deletion of limit files from 60 old days to 7 old days.
# 11-Nov-2017 Gilbert Miole  Move iff and limit files to /archives-yms.
# 27-Nov_2017 Gilbert Miole  Fixed the move of iff if the filename has space.
# 18-Jan-2017 Gilbert Miole  Replaced gilbert.miole@fairchildsemi.com with yms.admins@fairchildsemi.com
# 05-Feb-2108 Eric Alfanta   added file ext in scan_processed_dir for camstar env's
# 			     added subroutine scan_wks_processed_dir for wks env's	
# 15-Feb-2018 Eric Alfanta   added sub scan_processed_cpft_tmt_spd & scan_dir_gzip_cpft_tmt_spd and 
# 			     archve lsr_iff and spd_iff
# 27-Feb-2018 Eric Alfanta   added archive argument
# 28-Dec-2018 Eric Alfanta   added subroutine scan_warnings_dir
# 24-May-2019 Eric Alfanta   abort script if too many move and or delete failures
# 06-Jun-2019 Eric Alfanta   changed email add domain to onsemi.com
# 20-Jun-2019 Eric Alfanta   archive by year and month
# 13-Aug-2019 Rodney Cyr     Added WKS filetypes to ignore in scan_processed_dir so they can be archived.
# 06-Sep-2019 Rodney Cyr     Added .sum filetype to archive (not delete); szft_spm loader files are .sum files.
# 23-Feb-2020 Eric Alfanta   archive sandbox iff files
# 			     added delete,debug, arguments
#
# Function: Clean-up and gzip files under NotProcessed and deepest Processed folder at /data.
#
#


#################
# LOAD LIBRARIES
##################
use MIME::Lite;
use File::Find;
use File::Basename;
use File::Copy;
use Getopt::Long;
use IPC::Open3;
use Time::Piece;
use File::stat;

##################
# GLOBAL VARIABLES
##################
my $hostname = `hostname`;
chomp($hostname);
my $archive;
my $verbose;
my $debug;
my $delete;

GetOptions (	"archive" => \$archive, #perform archive iff
		"verbose" => \$verbose, #display
		"delete" => \$delete,  	#perform delete
		"debug" => \$debug ) 	#does not delete
or die ("Error in command line arguments.");

if (($archive || $delete) && $debug) {
	print "Could not perform archive and delete while debug option is turned on.\n";
	print "Please remove debug option and try agagin.\n\n";
	print "USAGE: $0 -archive -delete [verbose|debug]\n";
	exit;
}

my $mvErrCnt = 0;

##############
# MAIN ROUTINE 
##############
&scan_processed_dir;
&scan_processed_cpft_tmt_spd;
&scan_wks_processed_dir;
&scan_notprocessed_dir;
&scan_dir_clean_limit;
&scan_dir_gzip_file;
&scan_dir_gzip_cpft_tmt_spd;
&scan_dir_gzip_wm_iff_nc;
&scan_processed_wm_iff_nc;
&scan_warnings_dir;

##########################################################################
# MOVE IFF FILE AND DELETE RAW FILE IN PROCESSED DIR EXCEPT FOR LIMIT FILE
##########################################################################
sub scan_processed_dir
{

   	foreach my $data_dir(`find /data -type d -name "*Processed"`)
   	{
		chomp($data_dir);
        	next if $data_dir =~ /lost\+found/;
		next if -e "${data_dir}/Processed";
		
		my (@dummy) = split /\//, $data_dir;
		my $env	= $dummy[2];
        	next if $dummy[$#dummy] eq "NotProcessed";

		my $errCnt = 0;
		print "$data_dir\n" if ($verbose) || ($debug);
		###################################################################
		# LOOP EACH FILE AND MOVE/DELETE FILES N DAYS EXCEPT FOR LIMIT FILE
		###################################################################
		foreach my $file(`find $data_dir -maxdepth 1 -type f -mtime +7 ! -name "*.limit*"`)
		{
			chomp($file);
  			next if -d $file;
			if ( $file !~ /\.iff|\.sum|\.leh_iff|\.loss_iff|\.lotattr_iff|\.lotevent_iff|\.weh_iff|\.lsr_iff|\.fsoff|\.leh|\.latt|\.ehist|\.ltevt|\.loss|\.ltev|\.ent|\.eatr|\.fs|\.lotevent|\.EqpEvent|\.lotattr|\.weh|\.LSR_iff|\.SPD_iff|\.off/)
			{
				print "DELETE=$file\n" if ($verbose) || ($debug);
				
				if ($delete) {
			    		my $retval      = unlink "$file";
			    		my $loc_status  = ($retval==1) ? "Successful" : "Failed";
			       		if ($loc_status eq "Successful")
			       		{
			        	  	&log("...Deleting old file=$file", "$loc_status");
					  	next;
			       		}
			       		elsif ($loc_status eq "Failed")
			       		{
						$errCnt++;
			          		&log("...Deleting old file=$file", "$loc_status");
				  		&send_mail("Failed to delete this file: $file");

						if ($errCnt => 5) {
							&send_mail("Script Aborted! Too may files not deleted. Please check.");
							&log("Script Aborted! Too may files not deleted. Please check.");
							exit;
						}
						else {
				  			next;
						}
			       		}
				}

			}
			else {
				print "ARCHIVE=$file\n" if ($verbose) || ($debug);
   	                	&move_iff("$env", "$file") if ($archive);
			}
		}

		print "\nPress ENTER key to continue..." if ($debug);
		my $enterkey = <STDIN> if ($debug);
   	}
    
}

sub scan_processed_cpft_tmt_spd
{

   	foreach my $data_dir(`find /data/cpft_tmt/LSR_SPD/stage -maxdepth 2 -type d -name "*Processed"`)
   	{
        	chomp($data_dir);
		next if $data_dir =~ /lost\+found/;
        	my (@dummy)       = split /\//, $data_dir;
        	my $env           = $dummy[2];
        	next if $dummy[$#dummy] eq "NotProcessed";

		my $errCnt = 0;
		print "$data_dir\n" if ($verbose) || ($debug);
                ###################################################################
                # LOOP EACH FILE AND MOVE/DELETE FILES N DAYS EXCEPT FOR LIMIT FILE
                ###################################################################
                foreach my $file(`find $data_dir -maxdepth 1 -type f -mtime +7 ! -name "*.limit*"`)
                {
                        chomp($file);
                        next if -d $file;
                        
			if ($file !~ /\.spd_iff|\.lsr_iff/i)
                        {
				print "DELETE=$file\n" if ($verbose) || ($debug);

				if ($delete) {
                            		my $retval      = unlink "$file";
                            		my $loc_status  = ($retval==1) ? "Successful" : "Failed";
                               		if ($loc_status eq "Successful")
                               		{
                                  		&log("...Deleting old file=$file", "$loc_status");
                                  		next;
                               		}
                               		elsif ($loc_status eq "Failed")
                               		{
						$errCnt++;
                                  		&log("...Deleting old file=$file", "$loc_status");
                                  		&send_mail("Failed to delete this file:$file");
					
						if ($errCnt => 5) {
                                                	&send_mail("Script Aborted! Too may files not deleted. Please check.");
                                                	&log("Script Aborted! Too may files not deleted. Please check.");
                                                	exit;
                                        	}
                                        	else {
                                                	next;
                                        	}	
                               		}
				}
                         }
			 else {
				print "ARCHIVE=$file\n" if ($verbose) || ($debug);
                                &move_iff("$env", "$file") if ($archive);
                         }
                }
		print "\nPress ENTER key to continue..." if ($debug);
		my $enterkey = <STDIN> if ($debug);
   	}

}

sub scan_wks_processed_dir
{

   	#foreach my $data_dir(`find /data -type d -name "*Processed" -o -type d -name "*eatr" -o -type d -name "*ltev" -o -type d -name "*ent"`)
   	foreach my $data_dir(`find /data -type d -name "*Processed" -o -type d -name "*wks"`)
   	{
        	chomp($data_dir);
        	next if $data_dir =~ /lost\+found/;
        	next if -e "${data_dir}/Processed";
        	next if $data_dir !~ /\_wks/i;
        	my (@dummy)       = split /\//, $data_dir;
        	my $env           = $dummy[2];
        	next if $dummy[$#dummy] eq "NotProcessed";

		my $errCnt = 0;

		print "$data_dir\n" if ($verbose) || ($debug);
	
                ###################################################################
                # LOOP EACH FILE AND MOVE/DELETE FILES N DAYS EXCEPT FOR LIMIT FILE
                ###################################################################
                foreach my $file(`find $data_dir -maxdepth 1 -type f -mtime +7 ! -name "*.limit*"`)
                {
                        chomp($file);
                        next if -d $file;
                        if ($file !~ /\.fsoff|\.leh|\.fs|\.latt|\.ehist|\.ltevt|\.loss|\.ltev|\.ent|\.eatr|\.fs|\.off/)
                        {
				print "DELETE=$file\n" if ($verbose) || ($debug);

				if ($delete) {
                           		my $retval      = unlink "$file";
                            		my $loc_status  = ($retval==1) ? "Successful" : "Failed";
                               		if ($loc_status eq "Successful")
                               		{
                                  		&log("...Deleting old file=$file", "$loc_status");
                                  		next;
                               		}
                               		elsif ($loc_status eq "Failed")
                               		{
						$errCnt++;
                                  		&log("...Deleting old file=$file", "$loc_status");
                                  		&send_mail("Failed to delete this file:$file");
			
						if ($errCnt => 5) {
                                        	        &send_mail("Script Aborted! Too may files not deleted. Please check.");
                                        	        &log("Script Aborted! Too may files not deleted. Please check.");
                                        	        exit;
                                        	}
                                        	else {
                                                	next;
                                        	}
                               		}
				}

                        }
			else {
				print "ARCHIVE=$file\n" if ($verbose) || ($debug);
                                &move_iff("$env", "$file") if ($archive);
                         }
                }
		print "\nPress ENTER key to continue..." if ($debug);
		my $enterkey = <STDIN> if ($debug);
   	}

}

###########################################################
# DELETE OLD FILE IN NOTPROCESSED DIR EXCEPT FOR LIMIT FILE
###########################################################
sub scan_notprocessed_dir
{
	
   	foreach my $data_dir(`find /data -type d -name "*Processed"`)
   	{
		chomp($data_dir);
        	next if $data_dir =~ /lost\+found/;
		next if -e "${data_dir}/Processed";
		my (@dummy)       = split /\//, $data_dir;
        	next if $dummy[$#dummy] eq "Processed";

		print "$data_dir\n" if ($verbose) || ($debug);
		my $errCnt = 0;
		##############################################################
		# LOOP EACH FILE AND DELETE FILES N DAYS EXCEPT FOR LIMIT FILE
		##############################################################
		foreach my $file(`find $data_dir -maxdepth 1 -type f -mtime +14 ! -name "*.limit*"`)
		{
			chomp $file;
		        my $dir        = dirname($file);
		        my $fn         = substr($file, rindex($file,"/") + 1);
			                  chomp($fn);
			my $new_file   = "${dir}/${fn}";
  			next if -d $new_file;
		
			print "DELETE=$new_file\n" if ($verbose) || ($debug);

			if ($delete) {
				my $retval     = unlink "$new_file";
				my $loc_status = ($retval==1) ? "Successful" : "Failed";
				if ($loc_status eq "Successful")
				{
			        	&log("...Deleting old file=$file", "$loc_status");
					next;
				}
				if ($loc_status eq "Failed")
				{
					$errCnt++;
			        	&log("...Deleting old file=$file", "$loc_status");
					&send_mail("Failed to delete this file:$file");

					if ($errCnt => 5) {
                                		&send_mail("Script Aborted! Too may files not deleted. Please check.");
                                	        &log("Script Aborted! Too may files not deleted. Please check.");
                                	        exit;
                                	}
                                	else {
                                	        next;
                                	}
				}
			}
		}
		print "\nPress ENTER key to continue..." if ($debug);
		my $enterkey = <STDIN> if ($debug);
   	}
    
}

##############################
# DELETE / MOVE OLD LIMIT FILE
##############################
sub scan_dir_clean_limit
{
     	foreach my $data_dir(`find /data -type d -name "*Processed"`)
     	{
		chomp($data_dir);
        	next if $data_dir =~ /lost\+found/;
		my (@dummy)  = split /\//, $data_dir;
		my $env	     = $dummy[2];
		next if $dummy[$#dummy - 1] !~ /stage|stage_sandbox/i;
		
		print "$data_dir\n" if ($verbose) || ($debug);
	
		my $errCnt = 0;

		#########################################
		# LOOP EACH LIMIT FILES AND DELETE N DAYS 
		#########################################
		foreach my $file(`find $data_dir -maxdepth 1 -type f -mtime +7 -name "*.limit*"`)
		{
			chomp $file;

		        if ($file =~ /NotProcessed/)
		        {
		               my $dir         = dirname($file);
		               my $fn          = substr($file, rindex($file,"/") + 1);
			                         chomp($fn);
			       my $new_file    = "${dir}/${fn}";
  			       next if -d $new_file;

			       print "DELETE=$new_file\n" if ($verbose) || ($debug);

				if ($delete) {
			       		my $retval      = unlink "$new_file";
			       		my $loc_status  = ($retval==1) ? "Successful" : "Failed";
			       		if ($loc_status eq "Successful")
			       		{
			           		&log("...Deleting old file=$file", "$loc_status");
				   		next;
			       		}
			      	 	if ($loc_status eq "Failed")
			       		{
						$errCnt++;
			           		&log("...Deleting old file=$file", "$loc_status");
				   		&send_mail("Failed to delete this file: $file");

						if ($errCnt => 5) {
                                        	        &send_mail("Script Aborted! Too may files not deleted. Please check.");
                                        	        &log("Script Aborted! Too may files not deleted. Please check.");
                                                	exit;
                                        	}
                                        	else {
                                                	next;
                                        	}
			       		}
				}

                        }
			else {
				print "ARCHIVE=$file\n" if ($verbose) || ($debug);
                             	&move_iff("$env", "$file") if ($archive);
			}
   		}
		print "\nPress ENTER key to continue..." if ($debug);		
		my $enterkey = <STDIN> if ($debug);
     	}
}
############
# GZIP FILES  
############
sub scan_dir_gzip_file
{
   	foreach my $data_dir(`find /data -type d -name "*Processed"`)
   	{
		chomp($data_dir);
        	next if $data_dir =~ /lost\+found/;
		next if -e "${data_dir}/Processed";

		print "$data_dir\n" if ($verbose) || ($debug);

		###############################
		# LOOP EACH FILE AND GZIP FILES 
		###############################
		foreach my $file(`find $data_dir -maxdepth 1 -type f -mtime +1 ! -iname "*.gz" ! -iname "*.zip"`)
		{
			chomp($file);
			next if -d $file;
		        my $dir         = dirname($file);
		        my $fn          = substr($file, rindex($file,"/") + 1);
			                  chomp($fn);
			$file 		= "\"$file\"";
			
			print "GZIP=$file\n" if ($verbose) || ($debug);

			if ( ! $debug) {

				&doCompress($file);

				my $new_file    = "${dir}/${fn}.gz";
				my $retval      = (-e $new_file) ? "0" : "1";
				my $loc_status  = ($retval==0) ? "Successful" : "Failed";
				if ($loc_status eq "Successful")
				{
			        	&log("...gzipping file=$new_file", "$loc_status");
					next;
				}
				else
				{
					&log("...gzipping file=$file", "$loc_status");
					next;
				}
			}

		}
		print "\nPress ENTER key to continue..." if ($debug);
		my $enterkey = <STDIN> if ($debug);
    	}
}

sub scan_dir_gzip_cpft_tmt_spd {

	foreach my $data_dir(`find /data/cpft_tmt/LSR_SPD/stage -maxdepth 2 -type d -name "*Processed"`)
   	{
        	chomp($data_dir);
        	next if $data_dir =~ /lost\+found/;
        	my (@dummy)       = split /\//, $data_dir;
        	my $env           = $dummy[2];
        	next if $dummy[$#dummy] eq "NotProcessed";

		print "$data_dir\n" if ($verbose) || ($debug);
		
		foreach my $file(`find $data_dir -maxdepth 1 -type f -mtime +1 ! -iname "*.gz" ! -iname "*.zip" ! -name "*.limit"`)
                {
                        chomp($file);
                        next if -d $file;
                        my $dir         = dirname($file);
                        my $fn          = substr($file, rindex($file,"/") + 1);
                                          chomp($fn);
                        $file           = "\"$file\"";

			print "GZIP=$file\n" if ($verbose) || ($debug);
			
			if ( ! $debug) {
                        	&doCompress($file);

                        	my $new_file    = "${dir}/${fn}.gz";
                        	my $retval      = (-e $new_file) ? "0" : "1";
                        	my $loc_status  = ($retval==0) ? "Successful" : "Failed";
                        	if ($loc_status eq "Successful")
                        	{
                                	&log("...gzipping file=$new_file", "$loc_status");
                                	next;
                        	}
                        	else
                        	{
                                	&log("...gzipping file=$file", "$loc_status");
                                	next;
                        	}
			}

                }
		print "\nPress ENTER key to continue..." if ($debug);
		my $enterkey = <STDIN> if ($debug);		
  	}
}


# DELETE OLD WM_IFF_NC FILES FROM CPSORT/SLSORT FET
sub scan_processed_wm_iff_nc
{
   	foreach my $data_dir(`find /data -type d -name "*Processed"`)
   	{
        	chomp($data_dir);
        	next if $data_dir =~ /lost\+found/;
        	next if $data_dir !~ /cpsort_fet|slsort_fet/;
		my (@dummy)       = split /\//, $data_dir;
		my $env           = $dummy[2];
        	next if $dummy[$#dummy] eq "NotProcessed";

		print "$data_dir\n" if ($verbose) || ($debug);

		my $errCnt = 0;

                foreach my $file(`find $data_dir -maxdepth 1 -type f -mtime +7 -name "*.wm_iff_nc*"`)
                {
			chomp $file;
		     	if ($file !~ /\.wm_iff/i)
		     	{
                           	next if -d $file;
		
				print "DELETE=$file\n" if ($verbose) || ($debug);

				if ($delete) {
                           		my $retval      = unlink "$file";
                           		my $loc_status  = ($retval==1) ? "Successful" : "Failed";

                           		if ($loc_status eq "Successful")
                           		{
                           			&log("...Deleting old file=$file", "$loc_status");
                                		next;
                           		}
                           		if ($loc_status eq "Failed")
                           		{
						$errCnt++;
                                		&log("...Deleting old file=$file", "$loc_status");
                                		&send_mail("Failed to delete this file:$file");

						if ($errCnt => 5) {
                                			&send_mail("Script Aborted! Too may files not deleted. Please check.");
                                        		&log("Script Aborted! Too may files not deleted. Please check.");
                                        		exit;
                                		}
                                		else {
                                        		next;
                                		}
                           		}
				}

	              	}else {
				print "ARCHIVE=$file\n" if ($verbose) || ($debug);
		            	&move_iff("$env", "$file") if ($archive);
		      	}
                }
		print "\nPress ENTER key to continue..." if ($debug);
		my $enterkey = <STDIN>  if ($debug);
   	}

}

# COMPRESS OLD WM_IFF_NC FILES 
sub scan_dir_gzip_wm_iff_nc
{
   	foreach my $data_dir(`find /data -type d -name "*Processed"`)
   	{
        	chomp($data_dir);
        	next if $data_dir =~ /lost\+found/;
        	next if $data_dir !~ /cpsort_fet|slsort_fet/;

		print "$data_dir\n" if ($verbose) || ($debug);

                foreach my $file(`find $data_dir -maxdepth 1 -type f -mtime +1 -iname "*.wm_iff_nc" -iname "*.wm_iff_nc"`)
                {
                        chomp($file);
                        next if -d $file;
                        next if ($file =~ /\.gz$|\.zip$/i);
                        my $dir         = dirname($file);
                        my $fn          = substr($file, rindex($file,"/") + 1);
                                          chomp($fn);
                        $file           = "\"$file\"";
	
			print "GZIP=$file\n" if ($verbose) || ($debug);
			
			if ( ! $debug)
			{
                        	&doCompress($file);
                        	my $new_file    = "${dir}/${fn}.gz";
                       	 	my $retval      = (-e $new_file) ? "0" : "1";
                        	my $loc_status  = ($retval==0) ? "Successful" : "Failed";
                        	if ($loc_status eq "Successful")
                        	{
                                	&log("...gzipping file=$new_file", "$loc_status");
                                	next;
                        	}
                        	else
                        	{
                                	&log("...gzipping file=$file", "$loc_status");
                                	next;
                        	}
			}
                }
		print "\nPress ENTER key to continue..." if ($debug);	
		my $enterkey = <STDIN> if ($debug);
    	}
}

sub scan_warnings_dir
{
   	foreach my $data_dir(`find /data -type d -name "*Warnings"`)
   	{
        	chomp($data_dir);
        	next if $data_dir =~ /lost\+found/;
        	my (@dummy)       = split /\//, $data_dir;
        	my $env           = $dummy[2];

		print "$data_dir\n" if ($verbose) || ($debug);

		my $errCnt = 0;

                foreach my $file(`find $data_dir -maxdepth 1 -type f -mtime +14 -name "*.warn*"`)
                {
                        chomp($file);
                        next if -d $file;

			print "DELETE=$file\n" if ($verbose) || ($debug);

			if ($delete) {
                        	my $retval      = unlink "$file";
                        	my $loc_status  = ($retval==1) ? "Successful" : "Failed";
                        
				if ($loc_status eq "Successful")
                        	{
                        		&log("...Deleting old file=$file", "$loc_status");
                        	        next;
                        	}
                        	if ($loc_status eq "Failed")
                        	{
					$errCnt++;
                                	&log("...Deleting old file=$file", "$loc_status");
                                	&send_mail("Failed to delete this file:$file");

					if ($errCnt => 5) {
                                		&send_mail("Script Aborted! Too may files not deleted. Please check.");
                                        	&log("Script Aborted! Too may files not deleted. Please check.");
                                        	exit;
                                	}
                                	else {
                                        	next;
                                	}
                        	}
			}
                }
		print "\nPress ENTER key to continue..." if ($debug);
		my $enterkey = <STDIN> if ($debug);
   	}

}

##################
# COMPRESS A FILE
##################
sub doCompress
{
  	my $file = shift;

  	return $file if($file =~ /\.Z$|\.gz$/i);

  	my $pid = open3(\*GZIP_IN, \*GZIP_OUT, \*GZIP_ERR, "/usr/bin/gzip --force -v $file");
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
#################
# CREATE LOG FILE
#################
sub log
{

	my $msg        = shift;
	   chomp($msg);
	my $loc_status = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = &get_time();
	my $log_dir    = "$ENV{DPLOG}/cleanup_log";
	my $log_file   = "${log_dir}/cleanup_files.${year}-${mon}-${mday}.log";

	### CREATE LOG DIR ###
	system "mkdir $log_dir" if ! -e $log_dir;

	### LOG MSG TO FILE ###
	open LOG, ">$log_file"  or die "Failed to create $log_file file. $!\n" if ! -e $log_file;
	open LOG, ">>$log_file" or die "Failed to create $log_file file. $!\n" if   -e $log_file;
	print LOG "[${mon}/${mday}/${year} ${hour}:${min}:${sec}] $msg $loc_status\n";
	close(LOG);
     
        my $old_mday     = $mday -1; 
        my $old_log_file = "${log_dir}/cleanup_files.${year}-${mon}-${old_mday}.log";
	if ($old_log_file !~ /\.gz$/i && -e $old_log_file) {
        	system "gzip $old_log_file";
	}

}

####################
# EMAIL NOTIFICATION
####################
sub send_mail
{
	my $body   = shift;
        #my $email  = 'yms.admins@onsemi.com';	
        my $email  = 'eric.alfanta@onsemi.com';
	my $msg    = MIME::Lite->new
	(
	     #Subject => "WARNING!!! Clean-up script ABORTED: Failed to delete file",
	     Subject => "ERROR: Cleanup_files script",
	     From    => "dpower\@$hostname\.onsemi.com",
	     To      =>  $email,
	     Type    => 'text/html',
	     Encoding =>'base64',
	     Data    =>  $body
	);
	$msg->send();

}

###############################
# RETURN CURRENT DATE AND TIME
################################
sub get_time
{
     my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
        $sec   = "0".$sec  if $sec  <= 9;
	$min   = "0".$min  if $min  <= 9;
	$hour  = "0".$hour if $hour <= 9;
	$mon  += 1;
	$mon   = "0".$mon  if $mon  <= 9;
	$mday  = "0".$mday if $mday <= 9;
	$year += 1900;
	return($sec,$min,$hour,$mday,$mon,$year);

}
#################################
# MOVE IFF FILES TO /archives-yms
#################################
sub move_iff 
{

	my $env = shift;
	my $iff_file = shift;
	my $iff_fn = basename $iff_file;
	my $dir_yms = "";
	chomp($env);
        chomp($iff_file);
       
       	my $stamp = localtime( stat($iff_file)->mtime )->strftime("%Y/%b/%d");
	my ($yr,$mo,$dd) = split /\//, $stamp;

        #############################################
	# CREATE / WHICH ENVIRONMENT IN /archives-yms
	############################################# 
	if ($iff_file =~ /Prg_Product/i)
	{
		if ($iff_file =~ /sandbox/) {
			$dir_yms  = "/archives-yms/data/sandbox/${env}/Prg_Product/${yr}/${mo}";
		}
		else {
	    		$dir_yms  = "/archives-yms/data/${env}/Prg_Product/${yr}/${mo}";     
		}
	    	system "mkdir -p ${dir_yms}" if ! -e "${dir_yms}"; 
	    	#print "dir_yms:$dir_yms\n";
	}
        elsif ($iff_file =~/Prg_Process/i)
        {	
		if ($iff_file =~ /sandbox/) {
                        $dir_yms  = "/archives-yms/data/sandbox/${env}/Prg_Process/${yr}/${mo}";
                }
                else {
                        $dir_yms  = "/archives-yms/data/${env}/Prg_Process/${yr}/${mo}";
                }
	    	system "mkdir -p ${dir_yms}" if ! -e "${dir_yms}"; 
	    	#print "dir_yms:$dir_yms\n";
	}
	else
	{
		if ($iff_file =~ /sandbox/) {
                        $dir_yms  = "/archives-yms/data/sandbox/${env}/${yr}/${mo}";
                }
                else {
                        $dir_yms  = "/archives-yms/data/${env}/${yr}/${mo}";
                }
	    	system "mkdir -p ${dir_yms}" if ! -e "${dir_yms}"; 
	    	#print "dir_yms:$dir_yms\n";
	}
        ###################
	# MOVE THE IFF FILE
	###################
        my $retval = move($iff_file, "${dir_yms}/${iff_fn}");
	my $mv_status  = ($retval==1) ? "Successful" : "Failed";

	if ($mv_status eq "Successful")
	{
		&log("...moving iff file= $iff_file", "$mv_status");
		next;
	}
	else 	
	{
		$mvErrCnt++;
	       	&log("...moving iff file=$iff_file", "$mv_status");
	       	&send_mail("Failed to move iff file: $iff_file");
	
		if ($mvErrCnt > 5) {
			print "\nCleanup script aborted! Too many files were not moved to archive.";
			&log("Cleanup script aborted! Too many files not moved to archive.");	
			&send_mail("Cleanup script aborted! Too many files not moved to archive.");
			exit;
		}
		else {
	       		next;
		}
   	}

}



