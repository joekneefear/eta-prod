#!/bin/env perl_db
#
#
use strict;
use MIME::Lite;
use File::Find;
use File::Basename;
use File::Copy;
use Getopt::Long;
use IPC::Open3;
use Time::Piece;
use File::stat;

my $clean;
my $test;
my $hostname = `hostname`;
my $config = "$ENV{DPEXTSCRIPT}/cleanup_data_dir.config";
my %CFG = {};

GetOptions ( "clean" => \$clean, "test" => \$test) or die ("Error in command line arguments.");

if ($clean && $test) {
	print "USAGE:\n";
        print "To execute cleanup: $0 -clean\n";
        print "To perfrom test without cleanup: $0 -test\n";
        exit;
}


read_config($config);
gzip_processed_file();
gzip_notprocessed_file();
gzip_wks_processed_file();
gzip_wks_notprocessed_file();
clean_processed_dir();
clean_notprocessed_dir();
clean_processed_lim();
clean_notprocessed_lim();
clean_warnings_dir();
clean_wks_processed_dir();
clean_wks_notprocessed_dir();

exit;

### sub routines ###

sub clean_processed_dir {

	my $data_dir = $CFG{DATA_DIR};
	my $file_age = $CFG{PROCESSED_DIR_FILE_AGE};
	my $errCnt = 0;

	foreach my $proc_dir(`find $data_dir -type d -name "Processed"`)
        {
		chomp($proc_dir);
		next if ($proc_dir =~ /\_wks/); #SKIP WKS DIR

		foreach my $file(`find $proc_dir -maxdepth 1 -type f -mtime +$file_age ! -name "*.limit*"`)
		{
			chomp($file);

			if ($clean) 
			{
				my $return = unlink "$file";
				my $status = ( $return == 1 ) ? "Successful" : "Failed";
	
				if ($status eq "Successful")
                        	{
                                	Log("...deleting file=$file $status");
                                	next;
                        	}
                        	else
                        	{
					$errCnt++;
                                	Log("...deleting file=$file $status");
					send_mail("Failed to delete file = $file");
		
					if ($errCnt => 5) 
					{
						send_mail("Script Aborted! Too may files not deleted. Please check.");
						Log("Script Aborted! Too may files not deleted. Please check.");
					}
					else 
					{
                                		next;
					}
                        	}
			}
			elsif ($test) 
			{
				print "TEST: deleting file=$file\n";
				next;				
			}
		} #EACH FILE

	} #EACH DIR	

}

sub clean_notprocessed_dir {

	my $data_dir = $CFG{DATA_DIR};
        my $file_age = $CFG{NOTPROCESSED_DIR_FILE_AGE};
	my $errCnt = 0;

        foreach my $notproc_dir(`find $data_dir -type d -name "NotProcessed"`)
        {
                chomp($notproc_dir);
		next if ($notproc_dir =~ /\_wks/); #SKIP WKS DIR

                foreach my $file(`find $notproc_dir -maxdepth 1 -type f -mtime +$file_age ! -name "*.limit*"`)
                {
                        chomp($file);

			if ($clean)
                        {
                                my $return = unlink "$file";
                                my $status = ( $return == 1 ) ? "Successful" : "Failed";

                                if ($status eq "Successful")
                                {
                                        Log("...deleting file=$file $status");
                                        next;
                                }
                                else
                                {
                                        $errCnt++;
                                        Log("...deleting file=$file $status");
                                        send_mail("Failed to delete file = $file");

                                        if ($errCnt => 5)
                                        {
                                                send_mail("Script Aborted! Too may files not deleted. Please check.");
                                                Log("Script Aborted! Too may files not deleted. Please check.");
                                        }
                                        else
                                        {
                                                next;
                                        }
                                }
                        }
                        elsif ($test)
                        {
                                print "TEST: deleting file=$file\n";
                                next;
                        }			
                } #EACH FILE
        }#EACH DIR
}

sub clean_warnings_dir {
	my $data_dir = $CFG{DATA_DIR};
	my $file_age = $CFG{WARNINGS_DIR_FILE_AGE};
	my $errCnt = 0;

	foreach my $warn_dir(`find $data_dir -type d -name "Warnings"`)
	{
		chomp($warn_dir);

		foreach my $file(`find $warn_dir -maxdepth 1 -type f -mtime +$file_age -name "*.warn*"`)
                {
                        chomp($file);
			
			if ($clean)
                        {
                                my $return = unlink "$file";
                                my $status = ( $return == 1 ) ? "Successful" : "Failed";

                                if ($status eq "Successful")
                                {
                                        Log("...deleting file=$file $status");
                                        next;
                                }
                                else
                                {
                                        $errCnt++;
                                        Log("...deleting file=$file $status");
                                        send_mail("Failed to delete file = $file");

                                        if ($errCnt => 5)
                                        {
                                                send_mail("Script Aborted! Too may files not deleted. Please check.");
                                                Log("Script Aborted! Too may files not deleted. Please check.");
                                        }
                                        else
                                        {
                                                next;
                                        }
                                }
                        }
                        elsif ($test)
                        {
                                print "TEST: deleting file=$file\n";
                                next;
                        }			
                } #EACH FILE
	}#EACH DIR
}

sub clean_processed_lim {

        my $data_dir = $CFG{DATA_DIR};
        my $file_age = $CFG{PROCESSED_DIR_LIM_AGE};
	my $errCnt = 0;

        foreach my $proc_dir(`find $data_dir -type d -name "Processed"`)
        {
                chomp($proc_dir);

                foreach my $file(`find $proc_dir -maxdepth 1 -type f -mtime +$file_age -name "*.limit*"`)
                {
                        chomp($file);

			if ($clean)
                        {
                                my $return = unlink "$file";
                                my $status = ( $return == 1 ) ? "Successful" : "Failed";

                                if ($status eq "Successful")
                                {
                                        Log("...deleting file=$file $status");
                                        next;
                                }
                                else
                                {
                                        $errCnt++;
                                        Log("...deleting file=$file $status");
                                        send_mail("Failed to delete file = $file");

                                        if ($errCnt => 5)
                                        {
                                                send_mail("Script Aborted! Too may files not deleted. Please check.");
                                                Log("Script Aborted! Too may files not deleted. Please check.");
                                        }
                                        else
                                        {
                                                next;
                                        }
                                }
                        }
                        elsif ($test)
                        {
                                print "TEST: deleting file=$file\n";
                                next;
                        }
                } #EACH FILE
        } #EACH DIR
}

sub clean_notprocessed_lim {

        my $data_dir = $CFG{DATA_DIR};
        my $file_age = $CFG{NOTPROCESSED_DIR_LIM_AGE};
	my $errCnt = 0;

        foreach my $notproc_dir(`find $data_dir -type d -name "NotProcessed"`)
        {
                chomp($notproc_dir);

                foreach my $file(`find $notproc_dir -maxdepth 1 -type f -mtime +$file_age -name "*.limit*"`)
                {
                        chomp($file);

			if ($clean)
                        {
                                my $return = unlink "$file";
                                my $status = ( $return == 1 ) ? "Successful" : "Failed";

                                if ($status eq "Successful")
                                {
                                        Log("...deleting file=$file $status");
                                        next;
                                }
                                else
                                {
                                        $errCnt++;
                                        Log("...deleting file=$file $status");
                                        send_mail("Failed to delete file = $file");

                                        if ($errCnt => 5)
                                        {
                                                send_mail("Script Aborted! Too may files not deleted. Please check.");
                                                Log("Script Aborted! Too may files not deleted. Please check.");
                                        }
                                        else
                                        {
                                                next;
                                        }
                                }
                        }
                        elsif ($test)
                        {
                                print "TEST: deleting file=$file\n";
                                next;
                        }
                } #EACH FILE



        }
}

sub clean_wks_processed_dir {

        my $data_dir = $CFG{DATA_DIR};
        my $file_age = $CFG{WKS_PROCESSED_DIR_FILE_AGE};
        my $errCnt = 0;

        foreach my $proc_dir(`find $data_dir -type d -name "Processed"`)
        {
                chomp($proc_dir);
		next if ($proc_dir !~ /\_wks/i); #SKIP NONE WKS DIR

		foreach my $file(`find $proc_dir -maxdepth 1 -type f -mtime +$file_age ! -name "*.*"`)
                {
                        chomp($file);

                        if ($clean)
                        {
                                my $return = unlink "$file";
                                my $status = ( $return == 1 ) ? "Successful" : "Failed";

                                if ($status eq "Successful")
                                {
                                        Log("...deleting file=$file $status");
                                        next;
                                }
                                else
                                {
                                        $errCnt++;
                                        Log("...deleting file=$file $status");
                                        send_mail("Failed to delete file = $file");

                                        if ($errCnt => 5)
                                        {
                                                send_mail("Script Aborted! Too may files not deleted. Please check.");
                                                Log("Script Aborted! Too may files not deleted. Please check.");
                                        }
                                        else
                                        {
                                                next;
                                        }
                                }
                        }
                        elsif ($test)
                        {
                                print "TEST: deleting file=$file\n";
                                next;
                        }
                } #EACH FILE
        }#EACH DIR
}

sub clean_wks_notprocessed_dir {

        my $data_dir = $CFG{DATA_DIR};
        my $file_age = $CFG{WKS_NOTPROCESSED_DIR_FILE_AGE};
        my $errCnt = 0;

        foreach my $notproc_dir(`find $data_dir -type d -name "NotProcessed"`)
        {
                chomp($notproc_dir);
		next if ($notproc_dir !~ /\_wks/i);  #SKIP NONE WKS DIR

		foreach my $file(`find $notproc_dir -maxdepth 1 -type f -mtime +$file_age ! -name "*.*"`)
                {
                        chomp($file);

                        if ($clean)
                        {
                                my $return = unlink "$file";
                                my $status = ( $return == 1 ) ? "Successful" : "Failed";

                                if ($status eq "Successful")
                                {
                                        Log("...deleting file=$file $status");
                                        next;
                                }
                                else
                                {
                                        $errCnt++;
                                        Log("...deleting file=$file $status");
                                        send_mail("Failed to delete file = $file");

                                        if ($errCnt => 5)
                                        {
                                                send_mail("Script Aborted! Too may files not deleted. Please check.");
                                                Log("Script Aborted! Too may files not deleted. Please check.");
                                        }
                                        else
                                        {
                                                next;
                                        }
                                }
                        }
                        elsif ($test)
                        {
                                print "TEST: deleting file=$file\n";
                                next;
                        }
                } #EACH FILE
        }#EACH DIR
}

sub gzip_processed_file {
	my $data_dir = $CFG{DATA_DIR};
        my $file_age = $CFG{PROCESSED_DIR_GZIP_FILE_AGE};

	foreach my $proc_dir(`find $data_dir -type d -name "Processed"`)
        {
                chomp($proc_dir);
		next if ($proc_dir =~ /\_wks/); #SKIP NONE WKS DIR

                foreach my $file(`find $proc_dir -maxdepth 1 -type f -mtime +$file_age ! -iname "*.gz" ! -iname "*.zip" `)
                {
                        chomp($file);
			if ($clean)
			{
				&doCompress($file);

				my $new_file = "${file}.gz";
				my $return = (-e $new_file) ? "0" : "1";
				my $status = ( $return == 0 ) ? "Successful" : "Failed";

				if ($status eq "Successful")
				{
					Log("...gzipping file=$file $status");
					next;
				}		
				else
				{
					Log("...gzipping file=$file $status");
					next;
				}
			}
			elsif ($test) 
			{
				print "TEST: gzipping file=$file\n";
				next;
			}	
			
                } #EACH FILE
        } #EACH DIR
}

sub gzip_notprocessed_file {
	my $data_dir = $CFG{DATA_DIR};
        my $file_age = $CFG{NOTPROCESSED_DIR_GZIP_FILE_AGE};

 	foreach my $notproc_dir(`find $data_dir -type d -name "NotProcessed"`)
        {
                chomp($notproc_dir);
		next if ($notproc_dir =~ /\_wks/); #SKIP NONE WKS DIR

                foreach my $file(`find $notproc_dir -maxdepth 1 -type f -mtime +$file_age ! -iname "*.gz" ! -iname "*.zip" `)
                {
                        chomp($file);
			if ($clean) 
			{
				&doCompress($file);

                        	my $new_file = "${file}.gz";
                        	my $return = (-e $new_file) ? "0" : "1";
                        	my $status = ( $return == 0 ) ? "Successful" : "Failed";

                        	if ($status eq "Successful")
                        	{
                                	Log("...gzipping file=$file $status");
                                	next;
                        	}
                        	else
                        	{
                                	Log("...gzipping file=$file $status");
                                	next;
                        	}
			}
			elsif ($test) 
			{
				print "TEST: gzipping file=$file\n";
				next;
			}
                } #EACH FILE
         }#EACH DIR
}

sub gzip_wks_processed_file {
        my $data_dir = $CFG{DATA_DIR};
        my $file_age = $CFG{WKS_PROCESSED_DIR_GZIP_FILE_AGE};

        foreach my $proc_dir(`find $data_dir -type d -name "Processed"`)
        {
                chomp($proc_dir);
		next if ($proc_dir !~ /\_wks/); #SKIP NONE WKS DIR

                foreach my $file(`find $proc_dir -maxdepth 1 -type f -mtime +$file_age ! -iname "*.gz" ! -iname "*.zip" `)
                {
                        chomp($file);
                        if ($clean)
                        {
                                &doCompress($file);

                                my $new_file = "${file}.gz";
                                my $return = (-e $new_file) ? "0" : "1";
                                my $status = ( $return == 0 ) ? "Successful" : "Failed";

                                if ($status eq "Successful")
                                {
                                        Log("...gzipping file=$file $status");
                                        next;
                                }
                                else
                                {
                                        Log("...gzipping file=$file $status");
                                        next;
                                }
                        }
                        elsif ($test)
                        {
                                print "TEST: gzipping file=$file\n";
                                next;
                        }

                } #EACH FILE
        } #EACH DIR
}

sub gzip_wks_notprocessed_file {
        my $data_dir = $CFG{DATA_DIR};
        my $file_age = $CFG{WKS_NOTPROCESSED_DIR_GZIP_FILE_AGE};

        foreach my $notproc_dir(`find $data_dir -type d -name "NotProcessed"`)
        {
                chomp($notproc_dir);
		next if ($notproc_dir !~ /\_wks/); #SKIP NONE WKS DIR

                foreach my $file(`find $notproc_dir -maxdepth 1 -type f -mtime +$file_age ! -iname "*.gz" ! -iname "*.zip" `)
                {
                        chomp($file);
                        if ($clean)
                        {
                                &doCompress($file);

                                my $new_file = "${file}.gz";
                                my $return = (-e $new_file) ? "0" : "1";
                                my $status = ( $return == 0 ) ? "Successful" : "Failed";

                                if ($status eq "Successful")
                                {
                                        Log("...gzipping file=$file $status");
                                        next;
                                }
                                else
                                {
                                        Log("...gzipping file=$file $status");
                                        next;
                                }
                        }
                        elsif ($test)
                        {
                                print "TEST: gzipping file=$file\n";
                                next;
                        }
                } #EACH FILE
         }#EACH DIR
}

sub read_config {
        my $config = shift;

	open CFG, $config or die "Could not open file $config, $!";
	while (my $line=<CFG>)
	{
		chomp $line;
		#print "$line\n";;
		my ($fld,$val) = split /=/, $line;
		$CFG{$fld} = $val;
	}
	close CFG;
}

sub doCompress
{
        my $file = shift;
	my @values;

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

sub Log {
	my $msg = shift;
	my $time = Time::Piece->new;
        my $log_time = $time->date;
        my $proc_time = $time->strftime('%Y/%m/%d %H:%M:%S');
	my $log_file = "$CFG{LOG_DIR}/cleanup_data_dir-${log_time}.log";
	
	open LOG, ">$log_file" or die "Error. Failed to create $log_file file. $!\n" if ! -e $log_file;
	open LOG, ">>$log_file" or die "Error. Failed to create $log_file file. $!\n" if -e $log_file;
	print LOG "$proc_time $msg\n";
        close LOG;
}

sub send_mail
{
        my $body   = shift;
        my $email  = 'eric.alfanta@onsemi.com';
        my $msg    = MIME::Lite->new
        (
             Subject => "ERROR: cleanup_data_dir script",
             From    => "dpower\@$hostname\.onsemi.com",
             To      =>  $email,
             Type    => 'text/html',
             Encoding =>'base64',
             Data    =>  $body
        );
        $msg->send();

}
