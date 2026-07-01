#!/usr/bin/perl
#
#
# DATE        WHO            COMMENTS
# ----------  -------------- --------------------------------------------------
# 21-Dec-2015 Gilbert Miole  Author
# 23-Dec-2015 Gilbert Miole  Compress any uncompressed log files older
# 			     than 1 day (*.log.* and *.log, but not *.gz)
# 			     Delete any log files older than 30 days (*.log.*)
# 21-Jun-2016 Rodney Cyr     Compress all log files regardless of modified age.
# 30-Jun-2016 Rodney Cyr     Revert to compressing files 1 or more days old; If the log file is compressed when the loader is logging to it, 
#                              the logging will be lost.
# 07-Jul-2016 Rodney Cyr     Rename all log files (regardless of age) that don't already have the date; the loader will continue to log to 
#                              the renamed file until it is finished.
# 18-Jan-2018 Gilbert Miole  Replaced gilbert.miole@fairchildsemi.com with yms.admins@fairchildsemi.com
# 06-Jun-2018 Eric	     Changed email add domain to onsemi.com
# 			     
#
# Function: Clean-up and gzip log files under $DPLOG.
#
#


#################
# LOAD LIBRARIES
##################
use MIME::Lite;
use File::Find;
use File::Basename;
use Getopt::Long;
use IPC::Open3;
use File::Copy;

##################
# GLOBAL VARIABLES
##################
my $hostname         = `hostname`;
chomp($hostname);

##############
# MAIN ROUTINE 
##############
&scan_log_dir_del_log_files;
&scan_log_dir_rename_log_files;
&scan_log_dir_gzip_log_files;

######################
# DELETE OLD LOG FILES
######################
sub scan_log_dir_del_log_files
{
	
   foreach my $file(`find /home/dpower/project/log -type f -name "*.log.*" -mtime +30 -o -mtime 30`)
   {
       	chomp($file);
	next if -d $file;
	my $retval      = unlink "$file";
	my $loc_status  = ($retval==1) ? "Successful" : "Failed";
	if ($loc_status eq "Successful")
	{
	    &log("...Deleting old file=$file", "$loc_status");
	    next;
	}
	if ($loc_status eq "Failed")
	{
	    &log("...Deleting old file=$file", "$loc_status");
	    &send_mail("Failed to delete this file:$file");
	    next;
	}
   }
    
}
################
# GZIP LOG FILES  
################
sub scan_log_dir_rename_log_files 
{
   foreach my $file(`find /home/dpower/project/log -type f -name "*.log*" -and ! -name "*.gz" ! -size 0`)
   {
		chomp($file);
		next if -d $file;
		my $dir         = dirname($file);
		my $fn          = substr($file, rindex($file,"/") + 1);
		my $date        = `date \+\"\%Y\-\%m\-\%d\"`;
		chomp($date);
		next if $file =~ /$date/;
		$fn             =~ s/\.log//g;
		$fn             = "${fn}.${date}.log";
		my $new_fn      = "${dir}/${fn}";
	#	print "file: $file renamed to $new_fn\n";
		&moveFile($file, $new_fn);
		my $retval      = (-e $new_fn) ? "0" : "1";
		my $loc_status  = ($retval==0) ? "Successful" : "Failed";
		if ($loc_status eq "Successful")
		{
			&log("original file=$file renamed to new file=$new_fn", "$loc_status");
			next;
		}
	}
}
################
# GZIP LOG FILES  
################
sub scan_log_dir_gzip_log_files 
{
   #foreach my $file(`find /home/dpower/project/log -type f -name "*.log.*" -name "*.log" -mtime +1 -o -mtime 1 ! -name "*.gz" ! -size 0`)
   foreach my $file(`find /home/dpower/project/log -type f -name "*.log*" -and ! -name "*.gz" -mtime +1 -o -mtime 1 ! -size 0`)
   {
	chomp($file);
	next if -d $file;
	&doCompress($file);
	my $new_file    = "${file}.gz";
	my $retval      = (-e $new_file) ? "0" : "1";
	my $loc_status  = ($retval==0) ? "Successful" : "Failed";
	if ($loc_status eq "Successful")
	{
            &log("original file=$file gzipped to new file=$new_file", "$loc_status");
            next;
	}
	else
	{
	    &log("...gzipping file=$file", "$loc_status");
	    next;
	}
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
#################
# CREATE LOG FILE
#################
sub log
{

	my $msg        = shift;
	   chomp($msg);
	my $loc_status = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = &get_time();
	my $log_dir    = "$ENV{DPLOG}";
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
        my $email  = 'yms.admins@onsemi.com';	
	my $msg    = MIME::Lite->new
	(
	     Subject => "WARNING!!! Clean-up script ABORTED: Failed to delete file",
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
