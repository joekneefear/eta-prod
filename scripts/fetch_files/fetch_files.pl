#!/usr/bin/env perl_db
##!/usr/bin/perl 
#
#
# Confidential Property of Fairchild Semiconductor Corperation
# (c) Copyright Fairchild Semiconductor Corperation, 1999
# All rights reserved
#
# MODIFICATION HISTORY:
#
# DATE        WHO             DESCRIPTION
# ___________ ______________  __________________________________________________
# MAY 2001    Andrew Prueser  Original
# Feb 18 2002 Andrew Prueser  Certain FTP Servers will not allow an ls with multiple 
#				file extensions. (eg, ls *.wsm *.wat) this was causing
#				this script to return "NO files found" errors when files
#				actually existed. Changed the script to do a seperate listing
#				for each file type in the environment variable $PULL_FILE_TYPE.
#				( File types should be delimited by spaces for this variable to work.)
# MAR 24 2005 SJ Hwang        Modified
# AUG 09 2006 SJ Hwang        Modified the logic for sending E-mail
# APR 04 2011 Ben Rommel Kho  Modified to immediately push data after a successful fetch. This is to
#			      prevent data accumulation. hence, eliminates loading delays and network 
#			      congestion due to mass file transfer. 
#			      Also, added feature to move files from ENV_WAIT i.e. older than 3hrs.
# SEP 18 2015 Gilbert Miole   Make it work in YMS ETL server and use MIME in sending email.		
# MAY 30 2019 Eric Alfanta    Use return message as basis for successfull file transfer 
#
# Use the CPAN Net::FTP module, this is part of the libnet module.
#

#BEGIN { unshift(@INC, '/export/home/dpower/project/work/jag/CE-277/scripts/fetch_files/libnet-1.19'); }
use Net::FTP;
use File::Copy;
use MIME::Lite;

%ENVHash=();
$EDB_ENV_UP  ="";
my $body     = "";
my $hostname = `hostname`;
                chomp($hostname);

# 
# Debug level : 1 = print all commands to STDOUT, 0 = silent
$debuglevel = 0;

if (!defined($ARGV[0]))
{
	print "Usage:   $0  'Need environment variable - source env file'  \n";
	exit -1;
}
else
{
	#
	# Check if the given ENV file exists ...
	#
	 die "The file $ARGV[0] does not exist: $!\n" unless (-e $ARGV[0]);

	#
	# Read in the db_token.env file.
	#
	%ENVHash = GetEnviormentVars($ARGV[0]);		
}

# Uncomment this to print the FTP related environment variables.
PrintFTPData();

$EDB_ENV_UP = uc($ENVHash{EDB_ENV}{VALUE});

#
# Change Directory to FTP_IN_WAIT
#
if (! chdir($ENVHash{FTP_IN_WAIT}{VALUE}))
{
	print "Could not chdir($ENVHash{FTP_IN_WAIT}{VALUE})\n";
	exit -1;
}


#
# Get the extension of the files to pull
#
if(defined $ENVHash{PULL_FILE_TYPE}{VALUE})
{
 $FILETYPE = $ENVHash{PULL_FILE_TYPE}{VALUE};
 chomp($FILETYPE);
}
else
{ $FILETYPE = "*"; }

#
# Get the system time to use in the log file.
#
$logstart = `date +%Y%m%d%H%M%S`;
chomp $logstart;

$LFile = "$ENVHash{EDB_LOG}{VALUE}/fetch_files".".log.".substr("$logstart", 0, 8);

#
# Open the file handle to the log file
#
open (LOGFILE, ">>$LFile");
printf LOGFILE "==== FTP Fetch Start at $logstart ====\n";

#
# FTP the files (Get Them)
#

printf LOGFILE " *** Starting File fetch ***\n";

FTPCmd();

printf LOGFILE " *** Ending File fetch ***\n";

$logfinish = `date +%Y%m%d%H%M%S`;
chomp $logfinish;
printf LOGFILE "==== FTP Fetch finish at $logfinish ====\n";

#
# Exit the program with success
#
exit 0;
##################( Exit )######################


sub FTPCmd
{
	@files = ();

	#
	# Open the FTP connection ..
	#
	$connection = Net::FTP->new($ENVHash{PULL_NODE}{VALUE}, Debug => $debuglevel, Passive => 1);
		
	 # Trap connection failed errors, send an email and die ...
	 if($@)
         {
           $body = "ERROR $ENVHash{EDB_ENV}{VALUE}:Fetch Script could not connect to the server"
                 . "\nCould not connect to server $ENVHash{PULL_NODE}{VALUE} ...\n\n"
                 . $@, "\n";
	   &send_mail("$body");
           die;
         }

	#
	# If the connect attempt succeded ...
	#
	if(defined $connection)
	{
		if($connection->login($ENVHash{PULL_USER}{VALUE}, $ENVHash{PULL_PASS}{VALUE})==0)
                {
                  $body = "ERROR $ENVHash{EDB_ENV}{VALUE}:Fetch Script could not authenticate to the server"
                        . "\nCould not authenticate to server $ENVHash{PULL_NODE}{VALUE} as"
		        .  "\n\t user:$ENVHash{PULL_USER}{VALUE}\n\t password: $ENVHash{PULL_PASS}{VALUE}";
                  &send_mail("$body");
                  die "Could not authenticate to server as user: $ENVHash{PULL_USER}{VALUE} password: $ENVHash{PULL_PASS}{VALUE}, stopping ";
                }

		# Change the directory to PULL_PATH ..
		$connection->cwd($ENVHash{PULL_PATH}{VALUE})
			or die &send_mail("Could not change directory to $ENVHash{PULL_PATH}{VALUE}: $!\n");

		#
		# Get a listof the remote files ..
		# Check $FILETYPE for file types to fetch, fetch * if no types are given.
		#
		if($FILETYPE ne "*")
		{
		  @types = split /\s+/, $FILETYPE; 

		  foreach $type (@types)
		  {
		   @list = $connection->ls($type) or warn "Can't get a file listing: $!\n";

		   foreach $file (@list)
		   { push @files, $file; }
		  }
		}
		else
		{ @files = $connection->ls() or warn "Can't get a file listing: $!\n"; }
	
		#
		# Set connection type ..
		#
		if(lc $ENVHash{PULL_MODE}{VALUE} =~ /as/) 
		{ $connection->ascii(); }
		elsif(lc $ENVHash{PULL_MODE}{VALUE} =~ /bin/)
		{ $connection->binary(); }

		#
		# Start fetching the remote files ...
		#
		  foreach $file (@files)
		  {
		    print "Fetching $file \n";
		    $fetched_file = $connection->get("$file");
		    
		    $res =  $connection->message();
		    print LOGFILE "$res\n";
		    #
                    # Check to see if we fetched the file successfully, if so delete it from the server
                    #   and move it to the FTP_IN Directory.
                    #
		    # 30-May-2019 Eric : Use return message as basis for success
		     
		    #if("$fetched_file" eq "$file")
		    if ($res =~ /successfull|transfer complete|Ok to send data|File receive OK|File send OK/i)	
		    {
		      print LOGFILE "Fetched $file successfully.\n"; 

		      # Move the file to the $PUSH_PATH Directory on wanftp instead of deleting it.

		      print LOGFILE "Deleting $file from the Server.\n";
		      $connection->delete("$file") or warn "Could not delete $file from the server: $!";

		      ### MOVE FILE IMMEDIATELY ###
		      my $newfile = "$file";
                         $newfile =~ s/\s+//g;
		      print LOGFILE "Moving $file to $ENVHash{FTP_IN}{VALUE}/$newfile\n";
		      move("$ENVHash{FTP_IN_WAIT}{VALUE}/$file", "$ENVHash{FTP_IN}{VALUE}/$newfile") or warn "Could not move file to $ENVHash{FTP_IN}{VALUE}: $!\n";

		      ### UPDATE FILE PERMISSION ###
		      system("chmod 775 $ENVHash{FTP_IN}{VALUE}/$newfile"); 

		      
		    }
		    else 
		    { print LOGFILE "ERROR : Something went wrong fetching $file. \n";
                    }
		  }

	}
	$connection->quit() or warn "Could not close the connection cleanly, OH WELL!\n";

	
	### LOAD FILES THAT REMAINED IN THE ENV_WAIT DIR FOR >3HRS ###
	print LOGFILE "Scanning ENV_WAIT dir for old files...\n";

        foreach $file (`ls $ENVHash{FTP_IN_WAIT}{VALUE}`)
        {
              	chomp $file;
		
		print LOGFILE "Checking file in $ENVHash{FTP_IN_WAIT}{VALUE}: $file\n";
		my $newfile = "$ENVHash{FTP_IN}{VALUE}/$file";
		   $newfile =~ s/\s+//g;

		   $file      = "$ENVHash{FTP_IN_WAIT}{VALUE}/$file";
		my $file_time = (-M "$file") * 24;
		next if $file_time < 3;

                print LOGFILE "Moving >3-hr-old-file $file to $newfile\n";
                move("$file", "$newfile") or warn "Could not move file to $ENVHash{FTP_IN}{VALUE}: $!\n";
                system("chmod 775 $newfile");

        }
	
}

sub PrintFTPData
{
	print "PULL_NODE: $ENVHash{PULL_NODE}{VALUE}\n";
	print "PULL_USER: $ENVHash{PULL_USER}{VALUE}\n";
	print "PULL_PASS: $ENVHash{PULL_PASS}{VALUE}\n";
	print "PULL_PATH: $ENVHash{PULL_PATH}{VALUE}\n";
	print "PULL_MODE: $ENVHash{PULL_MODE}{VALUE}\n";
	print "FTP_IN:    $ENVHash{FTP_IN}{VALUE}\n";
	print "FTP_IN_WAIT: $ENVHash{FTP_IN_WAIT}{VALUE}\n";
}

sub GetEnviormentVars
{
        my ($VarFile) = @_;
        local %EnvHash=();
        local $cshCMD   = "";
        local $VAR      = "";
        local $Assigned = "";

        #
        # Get the HOME variable
        #
        $HOME = $ENV{HOME};
        $EnvHash{HOME} =
        {
                VALUE => $HOME,
        };

        open(INPUT, "$VarFile");
        while ($line = <INPUT>)
        {
		chomp ($line);
                if (uc(substr($line, 0, length("setenv"))) eq uc("setenv"))
                {
                        ($cshCMD, $VAR, $Assigned) = split(/\s+/, $line, 3);
			$P = index($Assigned, "\$");
                        if ($P == 0)
                        {
                                # If there is a '$' char, then the varable should
                                # have been identified earlier, therefor find the Hash
                                # ref and subsitute.
                                $POS = index($Assigned, "/");
                                if ($POS > 0)
                                {
                                        $var = substr($Assigned, 0, $POS);
                                        $EndStr = substr($Assigned, $POS, length($Assigned));
                                        # Get the value of the variable from the hash
                                        $var =~ s/^\$//;
                                        $Value = $EnvHash{$var}{VALUE};
                                        $Assigned=$Value.$EndStr;
                                }
                                else
                                {
                                        $var =~ s/^\$//;
                                        $Value = $EnvHash{$var}{VALUE};
                                        $Assigned=$Value;
                                }
                                #print $Assigned."\n";
                        }
			elsif ($P > 0)
			{
				#
				# Check to see if there are "{" or "}"
				#
				$B1Pos = index($Assigned, "{");
				$PREFIX = substr($Assigned, 0, $B1Pos -1);
				$B2Pos = index($Assigned, "}");
				$Diff = $B2Pos - $B1Pos;
				$SUFFIX = substr($Assigned, $B2Pos + 1, length($Assigned));
				$String = substr($Assigned, $B1Pos + 1, $Diff - 1);
				$Value = $EnvHash{$String}{VALUE};
				$Assigned = $PREFIX.$Value.$SUFFIX;
			}

			#
			# Strip the quotes from around the variable ..
			#
			$Assigned =~ s/^\"//;
			$Assigned =~ s/\"$//;

                       	$EnvHash{$VAR} =
                       	{
                               	VALUE => $Assigned,
                       	};
                       	$cshCMD = $VAR = $Assigned = "";
                }
        }
        close(INPUT);
        return (%EnvHash);
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
             Subject => "WARNING!!! FETCH SCRIPT ABORTED: Please check",
             From    => "dpower\@$hostname\.onsemi.com",
             To      =>  $email,
             Type    => 'text/html',
             Encoding =>'base64',
             Data    =>  $body
        );
        $msg->send();

}
