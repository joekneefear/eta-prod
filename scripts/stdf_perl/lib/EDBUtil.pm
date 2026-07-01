#
# DATE       WHO            COMMENTS
# ---------- -------------- ---------------------------------------------------------
# 03/30/2010 Ben Rommel Kho Modified isPIDRunnning to handle envs with longer names.
# 06/19/2010 Ben Rommel Kho Modified doUncompress to perform force uncompress. Script will
#			    hang if a non-zipped-equivalent file already exists.
# 06/21/2010 Ben Rommel Kho Removed code that dumps env listing into a file.
# 19-Apr-12  S. Boothby     Removed hard-coded references to installed software
# 06/20/2012 Ben Rommel Kho Modified cleanString to allow _@#()= chars 
# 08/27/2012 Ben Rommel Kho Added "sendEmail" routine
# 27-Jun-13  S. Boothby     Added "quiet" option to doUnzip to produce no output.
#

=head1 NAME

EDBUtil - A generic set of utility functions for use in the EDB environments

=head1 SYNOPSIS

  use EDBUtil;
  EDBUtil::moveFile($fromFile, $toFile);
  EDBUtil::start($scratchDir, $processType);
  EDBUtil::stop($scratchDir, $processType);
  EDBUtil::hold($scratchDir, $processType);

=head1 DESCRIPTION

This module provides a generic set of functions that can be utilized within
the EDB environments and their associated scripts.

=head2 METHODS

=over 4

=item * processCommandLine(\@ARGV, \@validARGS)

Returns a Hashtable of the command line arguments.

=item * doAction($cmdLineHashRef, $scratch_dir, $system)

Use this to control whether the script is running, stopped or put on hold.

=item * start($scratch_dir, $process_type)

Start the script if it isn't already running.

=item * stop($scratch_dir, $process_type)

Stop the script if it is running.

=item * hold($scratch_dir, $process_type)

Hold the script from running.

=item * checkForHoldFile($scratch_dir, $process_type)

Check whether a hold file has been put into place.

=item * checkForKillFile($scratch_dir, $process_type)

Check whether a kill file has been put into place.

=item * readPIDFile($filename)

Return the process ID contained in the passed in file.

=item * isPIDRunning($process_id)

Return whether the process ID is currently running.

=item * GetEnvironmentVars($environment_file)

Returns a hashtable containing all the environment values defined in the passed in environment file.

=item * getFiles($directory, @filters)

Returns an array of files found in the directory matching any regular expression filters passed in. 

=item * doUncompress($fileName)

Returns the uncompressed file name of $fileName if the file is not a compressed file.

=item * doCompress($fileName)

Returns the compressed file name or $fileName if the file is already compressed.

=item * doUntar($fileName)

Returns an array of all the files contained within the specified tar file.

=item * doTar($fileName, @files)

Returns whether a tar file named $fileName could be created using all the files contained in @files.

=item * doUnzip($fileName)

Returns an array of all the files contained within the specified zip file.

=item * doUnrar($fileName)

Returns an array of all the files contained within the specified rar file.

=item * moveFile($fromFile, $toFile)

Moves the file specified with $fromFile to the file specified with $toFile.

=item * deleteFile($file)

Deletes the file specified with $file.

=item * copyFile($fromFile, $toFile)

Copies the file specified with $fromFile to the file specified with $toFile.

=item * renameFile($fromFile, $toFile)

Renames the file specified with $fromFile to the file specified with $toFile.

=item * cleanString($string)

Removes all leading and trailing white space as well as any illegal characters in $string.

=item * getTimeStamp()

Returns a timestamp that can be appended to file names to make them unique.

=item * getDateStamp()

Returns a date based timestamp that can be appended to a log file names and sorts in chronological order.

=item * getEnvs()

Returns a listing of all EDB environments defined as reported by pshow.

=item * openLOG(logfile)

Opens a logfile specified by $logfile.  All STDOUT and STDERR output is redirected to this file.

=back

=head1 AUTHOR

S<
Kerry Bassett  (Kerry.Bassett@fairchildsemi.com)
Andrew Prueser (Andrew.Prueser@fairchildsemi.com)
>

=head1 COPYRIGHT

S<
Confidential Property of Fairchild Semiconductor Corperation
(c) Copyright Fairchild Semiconductor Corperation, 2005
All rights reserved
>

=cut

package EDBUtil;

#
# Setup some variables that are used in all situations.
#
#BEGIN
#{
#   $ENV{SYBASE}          = "/export/home/sybase";
#   $ENV{LD_LIBRARY_PATH} = "$ENV{LD_LIBRARY_PATH}:/export/home/sybase/OCS-12_5/lib";
#   $ENV{LD_LIBRARY_PATH} = "$ENV{LD_LIBRARY_PATH}:/export/home/sybase/OCS-12_5/lib3p";
#   $ENV{STDF_PERL_LIB}   = "/data/edbmgr/stdf_perl/lib";
#}

use File::Find;
use File::Copy;
use IO::Handle;
use IPC::Open3;
use Sybase::CTlib;
use Net::SMTP;
use MIME::Lite;
use Cwd;


#
# This subroutine will split a command line that is delimited by (-) dashes
#  and return a hash with the command parameter and its value, if any.
#  
# All whitespace between words will be ignored, every (-) dash starts a new parameter.
#
# It will allow command chaining similar to the "ls -lart" example below.
# It will further allow the setting or values by the inclusion of an (=) equals sign.
# Command chaining and variable setting are mutually exclusive, so any values with an =
#   will assume that everthing after the - and before the FIRST = is the varable name. 
#       (excluding whitespace and subsequent =.)
#
# Numbers following a command flag or dash will be taken to be parameters without the need for an = 
#  if and only if there are no letters before the next dash. If you expect a number parameter like "tail -100"
#  this should be indicated by adding "NUMBER_PARAMETER" to the expected parameter list.
#
# We allow the special key words "start", "stop", "kill" on the command line without dashes, 
#  for this to work these commands must be the ONLY command on the command line.
#  To utilize this functionality the expected parameter list should contain the ACTION keyword
#
# It will compare what it found on the command line with a list of valid values passed in.
#
# It takes two parameters: 
#   The first is a reference to the ARGV array 
#   The second is a reference to an array with the acceptable values.
#
# (eg.) ls -lart         will result in a hash with 4 keys (l, a, r, and t), their values will be 1 to indicate that it was set.
# (eg.) test -input=blah will result in a hash with 1 key (input), its value will be blah.
#
sub processCommandLine
{
  my $cmdLnRef = shift;
  my $paramRef = shift;

  my $cmdLine     = "";
  my @newCmdSplit = ();

  %cmdHash          = ();
  $cmdHash{SUCCESS} = 1;

  return \%cmdHash if $#{$cmdLnRef} == -1;   # Bail out early if no parameters were entered.

  #
  # We allow the special key words "start", "stop", "hold", "restart", "validate", "monitor"  on the command line without dashes, 
  #  for this to work these commands must be the FIRST command on the command line followed by an environment file.
  #  The Path to the Environment file should be completely qualified.
  #
  if($#{$cmdLnRef} >= 0 && $$cmdLnRef[0] =~ /^start$|^stop$|^hold$|^restart$|^validate$|^monitor$/i)
  {
        if(grep(/ACTION/, @{$paramRef}))
        {
	   $cmdHash{ACTION} = lc($$cmdLnRef[0]);
	   shift @{$cmdLnRef};
        }

	my $val;
	while ( defined ($val = shift @{$cmdLnRef}) )
        {
	  if(grep(/ENVIRONMENT_FILE/, @{$paramRef}) && $val =~ /\.env$/i)
	  {
	     $cmdHash{ENVIRONMENT_FILE} = $val;
	  }
	  elsif(grep(/SYSTEM/, @{$paramRef}) && $val =~ /^dispatch$|^convert$|^summarize$|^load$|^all$/i)
	  {
	     $cmdHash{SYSTEM} = $val;
          }
          else
          {
             @{$cmdHash{ENV_AREAS}} = ($val, @{$cmdLnRef});
             return \%cmdHash;
	  }
        }
        return \%cmdHash;
  }

  #
  # Reformat the command line parameters, PERL will split ARGV on spaces by default.
  #
  foreach my $item (@{$cmdLnRef})
  {
     $cmdLine .= " " . $item;
  }

  @newCmdSplit = split /\s+\-/, $cmdLine;

  #
  # Process the command line flags.
  #
  foreach my $cmd (@newCmdSplit)
  {
      $cmd =~ s/^\-//;  # Remove the starting (-) dash.     
      $cmd =~ s/\s+//g;  # Remove all whitespace.

      next if $cmd eq "";

      # If this command is a parameter being set, store it as such.
      if($cmd =~ /\=/)
      {
        ($varName, $varVal) = split /=/, $cmd, 2;

        if(grep(/$varName/, @{$paramRef}))
        {
           $cmdHash{$varName} = $varVal;
        }
        else
        {
           warn "Unexpected Parameter detected: $varName\n";
           $cmdHash{SUCCESS} = 0;
        }
      }
      # else this is a simple command flag, or a string of flags.
      else
      {
         if($cmd =~ /^[0-9]+$/)
         {
            if(grep(/NUMBER_PARAMETER/, @{$paramRef}))
            {
               $cmdHash{NUMBER_PARAMETER} = $cmd;
            }
            else
            {
	       warn "Unexpected Number Parameter detected: $cmd\n";
               $cmdHash{SUCCESS} = 0;
            }
         }
         elsif($cmd =~ /[A-Za-z]{1}[0-9]+/)
         {
            my $param = substr($cmd, 0, 1);
            if(grep(/$param/, @{$paramRef}))
            {
               $cmdHash{$param} = substr($cmd, 1);
            }
            else
            {
	       warn "Unexpected Parameter detected: $param \n";
               $cmdHash{SUCCESS} = 0;
            }
         }
         elsif(length($cmd) > 1)
         {
            @cmds = split //, $cmd;

            foreach $cd (@cmds)
            { 
              if(grep(/$cd/, @{$paramRef}))
              {
                 $cmdHash{$cd} = 1;
              }
              else
	      {
	         warn "Unexpected Parameter detected: $cd\n";
                 $cmdHash{SUCCESS} = 0;
	      }
            }
         }
         else
         {
              if(grep(/$cmd/, @{$paramRef}))
              {
                 $cmdHash{$cmd} = 1;
              }
              else
	      {
	         warn "Unexpected Parameter detected: $cmd\n";
                 $cmdHash{SUCCESS} = 0;
	      }
         }
      }
  }

  return \%cmdHash;
}

#
# doAction - This method will take in the hash from the processCommandLine method and determine if an ACTION was called
#              and if it was, call the appropriate method to take that action.
#
sub doAction
{
	my $hashRef      = shift;
        my $scratch_dir  = shift;
        my $process_type = shift;

	return 0 if not defined $$hashRef{ACTION};

	if($$hashRef{ACTION} =~ /^start$/i)
	{ return start($scratch_dir, $process_type); }

	if($$hashRef{ACTION} =~ /^stop$/i)
	{ return stop($scratch_dir, $process_type); }

	if($$hashRef{ACTION} =~ /^hold$/i)
	{ return hold($scratch_dir, $process_type); }

	return 0;
}


#
# Start this script unless it is already running.
#
#  This method will create a PIDFILE with the PID of this process and remove any hold or kill files that may be present.
#  It will do nothing if a PID file exists with a vaild PID in it. (by valid we me running on the system.)
#
#  It will return if it started the process die otherwise.
#
sub start
{
	my $scratch_dir  = shift;
	my $process_type = shift;

           $scratch_dir  = $scratch_dir . "/" if $scratch_dir  !~ /\/$/;      

	my $PIDFILE      = $scratch_dir . "/" . ucfirst($process_type) . ".pid";
	my $HOLDFILE     = $scratch_dir . "/" . ucfirst($process_type) . ".hold";
	my $KILLFILE     = $scratch_dir . "/" . ucfirst($process_type) . ".kill";
	my $RESTARTFILE  = $scratch_dir . "/" . ucfirst($process_type) . ".restart";

        #
        # Remove the hold and kill files if they exist.
        #
        unlink $HOLDFILE if -e $HOLDFILE;
        unlink $KILLFILE if -e $KILLFILE;
        unlink $RESTARTFILE if -e $RESTARTFILE;

        #
        # Check to see if a PIDFILE exists, then check if that PID exists.
        #  If the PID exists, die without doing anything.
        #
        if( -e $PIDFILE )
        {
	    my $process_id = readPIDFile($PIDFILE);

            die "Process is already running.\n" if isPIDRunning($process_id) == 1;
        }

        #
        # If the PIDFILE does not contain information about a running process, or does not exist.
        #
        open PIDF, ">$PIDFILE" or die "Could not create PIDFILE, not starting.\n";
        print PIDF $$;
        close PIDF; 

        return 1;
}

#
# Stop this script. 
#
#  This method will read a PIDFILE with the PID of this process and kill that PID.
#  It will do nothing if a PID file does not exist or if one exists with an invaid PID in it. (by valid we me running on the system.)
#
sub stop
{
	my $scratch_dir  = shift;
	my $process_type = shift;

        $scratch_dir     = $scratch_dir . "/" if $scratch_dir  !~ /\/$/;      

	my $PIDFILE      = $scratch_dir . "/" . ucfirst($process_type) . ".pid";
	my $KILLFILE     = $scratch_dir . "/" . ucfirst($process_type) . ".kill";
	my $num_killed   = 0;

        #
        # Write a Killfile for this script, just overwrite an existing one.
        #
        open(KILLF, ">$KILLFILE") or die "Could not Create Kill File. Process will not die.\n";
        print KILLF $$;
        close KILLF;

	die "\n";
}

#
# Put this script in hold.
#
# This method will create a HOLDFILE in the given directory allowing this script later to check if it should hold processing.
#
sub hold
{
	my $scratch_dir	 = shift;
	my $process_type = shift;

	$scratch_dir	 = $scratch_dir . "/" if $scratch_dir  !~ /\/$/;

	my $HOLDFILE	 = $scratch_dir . "/" . ucfirst($process_type) . ".hold";

	#
	# Write the holdfile.
	#
	open(HOLDF, ">$HOLDFILE") or die "Could not create HOLDFILE. Process will not sleep.\n";
	print HOLDF $$;
	close HOLDF;

	die "\n";
}

#
# Check to see if a holdfile exists return True (1) if it does, else False (0).
#
sub checkForHoldFile
{
	my $scratch_dir	 = shift;
	my $process_type = shift;

        $scratch_dir     = $scratch_dir . "/" if $scratch_dir  !~ /\/$/;      

	my $HOLDFILE     = $scratch_dir . "/" . ucfirst($process_type) . ".hold";

	return 1 if -e $HOLDFILE;

	return 0;
}

#
# Check to see if a killfile exists return True (1) if it does, else False (0).
#
sub checkForKillFile
{
	my $scratch_dir	 = shift;
	my $process_type = shift;

        $scratch_dir     = $scratch_dir . "/" if $scratch_dir  !~ /\/$/;      

	my $KILLFILE     = $scratch_dir . "/" . ucfirst($process_type) . ".kill";

	return 1 if -e $KILLFILE;

	return 0;
}

#
# Small helper function to read in a PIDFILE.
#
sub readPIDFile
{
	my $filename = shift;

        open PIDF, "$filename" or return -1;

        my    $process_id = <PIDF>;
        chomp $process_id;
              $process_id =~ s/\s*//g;

        close PIDF;

	return $process_id;
}

#
# Small helper function to check if a given PID exists on the system.
#
sub isPIDRunning
{
    my $process_id = shift;
    my $name       = $main::ENV{ENV_NAME};

    open PSAWX, "/usr/ucb/ps -axww | grep $process_id | grep -v grep |" if length($name)  > 24;   ### SLOW
    open PSAWX, "/usr/ucb/ps -axw  | grep $process_id | grep -v grep |" if length($name) <= 24;   ### FAST
	
    my @running_pids = <PSAWX>;

    close PSAWX;

    foreach my $process ( @running_pids )
    {
      chomp $process;
      $process =~ s/^\s+//;

      # 
      # line[0] = pid
      # line[4] = command edbtdl
      # line[5] = environment edbtdl
      # line[6] = command (Dispatch, Convert, Summarize, Load) 
      # line[8] = environment (Dispatch, Convert, Summarize, Load)
      #
      my @line = split /\s+/, $process;

      my $cmd  = $line[6];
      my $env  = $line[8];
         $cmd  = $line[4] if($main::SYSTEM =~ /edbtdl/);
         $env  = $line[5] if($main::SYSTEM =~ /edbtdl/);
         $name = $ENV{DATABASE} if($main::SYSTEM =~ /edbtdl/);
   
      return 1 if defined $process_id && ($line[0] == $process_id && $cmd =~ /$main::SYSTEM/i && $env =~ /$name/i);
    }

    return 0;
}

#
# Read an EDB Environment file into a Hashtable.
#
sub GetEnvironmentVars
{
        my $VarFile  = shift;
        my $rec_lvl  = shift;
        my $cshCMD   = "";
        my $VAR      = "";
        my $Assigned = "";

        #
        # Get the HOME variable
        #
        $HOME = $ENV{HOME};
        $rec_lvl = 0 unless defined $rec_lvl;

        open(INPUT, "$VarFile") or die "Could not open file $!\n";

        while ($line = <INPUT>)
        {
                chomp ($line);
		$line =~ s/^\s*//;
		$line =~ s/\s*$//;

                if ($line =~ /^setenv|^source/i)
                {
                        ($cshCMD, $VAR, $Assigned) = split(/\s+/, $line, 3) if ($line =~ /^setenv/);
                        ($cshCMD, $Assigned)       = split(/\s+/, $line, 2) if ($line =~ /^source/);

                        $Assigned =~ s/\{|\}|\"$|^\"//g if defined $Assigned;

                        if( defined $Assigned && $Assigned =~ /\$/ )
			{
				while( $idx = (index($Assigned, "\$") >= 0) )
                                {
					$Assigned =~ /.*\$(\w+)[$:\/;]*/;
                                        
					$newVal = defined $ENV{$1} ? $ENV{$1} : "";
                                        $Assigned =~ s/\$$1/$newVal/;
                                }         
			}
		
			if ($line =~ /^source/ )
                        {
                          my $handle = "TMP" . $rec_lvl;
                          open($handle, "<&INPUT");
                          GetEnvironmentVars($Assigned, ++$rec_lvl);

                          open(INPUT, "<&$handle");
                          $rec_lvl--;
                        }
                        else
                        {
			  $ENV{$VAR} = $Assigned if defined $Assigned && $Assigned ne "";
                        }
                        $cshCMD = $VAR = $Assigned = "";
                }
        }
        close(INPUT);
}

###############################
# Get a list of files
###############################
sub getFiles
{
  $dir     = shift;
  @filters = @_;

  @files = ();

  return if($dir =~ /^\s*$/);

  find(\&file_handler, $dir);
  return @files;
}

###############################
# Callback function to process 
# file listings from a directory
###############################
sub file_handler
{
  if($#filters == -1)
  {
    push @files, $File::Find::name if -f $File::Find::name && $File::Find::name !~ /\.svn/;
    return;
  }

  foreach $filter (@filters)
  {
    #print "\nCHECKING FILE: $_ USING FILTER: $filter \n";
    if(/$filter/i)
    {
      push @files, $File::Find::name if -f $File::Find::name && $File::Find::name !~ /\.svn/;
    }
  }

  return;
}

###############################
# Uncompress a file
###############################
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

###############################
# Compress a file
###############################
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

###############################
# Untar a file
###############################
sub doUntar
{
  my $file = shift;

  my $orig_dir = getcwd;
  my $indx = rindex($file, "\/");
  my $dir = ($indx == -1) ? "." : substr($file,0,rindex($file,"\/") + 1);
  
  my @vals = (); 
  if(-e $file && $file =~ /\.tar$/i )
  {
    my $tar_status = system("tar -tf $file");

    return @vals if($tar_status != 0);

    chdir($dir);
    open(UNTAR, "/usr/local/bin/tar -xvf $file |");

    while(<UNTAR>)
    {
       push @vals, $_;
    }
    close UNTAR;
  }
  chdir($orig_dir);
  return @vals;  
}

###############################
# Tar a file
###############################
sub doTar
{
  my $name  = shift;
  my @files = @_;

  my $status = system("tar -cf $name @files");

  return $status;
}

###############################
# Unzip a file
###############################
sub doUnzip
{
  my $file = shift;
  my $options = shift;
  my $quiet = "";
  if ( defined( $options ) && $options == "quiet" )
  {
     $quiet = "> /dev/null";
  }
  my $orig_dir = getcwd;
  my $indx = rindex($file, "\/");
  my $dir = ($indx == -1) ? "." : substr($file,0,rindex($file,"\/") + 1);

  my @vals = (); 
  if(-e $file && $file =~ /\.zip$/i )
  {
    my $zip_status = system("/usr/bin/zipinfo $file $quiet");

    return @vals if($zip_status != 0);

    chdir($dir);
    open(UNZIP, "unzip -j -o $file |");

    while(<UNZIP>)
    {
       next if /^\s*Archive\:/i;

       ($junk,$filename) = split/\:\s+/;
       push @vals, $filename;
    }
    close UNZIP;
  }
  chdir($orig_dir);

  return @vals;  
}

###############################
# Unrar a file
###############################
sub doUnrar
{
  my $file = shift;
  my $orig_dir = getcwd;
  my $indx = rindex($file, "\/");
  my $dir = ($indx == -1) ? "." : substr($file,0,rindex($file,"\/") + 1);

  my @vals = ();
  if(-e $file && $file =~ /\.rar$/i )
  {
    my $unrar_status = system("/usr/bin/unrar t $file");

    return @vals if($unrar_status != 0);
    
    chdir($dir);
    open(UNRAR, "unrar e -ep -o+ $file |");

    while(<UNRAR>) 
    {
       next unless /^\s*Extracting\s{2}/i;

       ($junk,$filename,$junk) = split/\s+/; 
       push @vals, $filename;
    } 
    close UNRAR; 
  }
  chdir($orig_dir);

  return @vals;
}

###############################
# Move a file
###############################
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

###############################
# Delete a file
###############################
sub deleteFile
{
  $delFile = shift;

  return 0 if (-d $delFile);

  if($delFile =~ /\*|\?/) 
  {
    @files = glob $delFile;

    foreach $file (@files)
    {
      $status = unlink($file);
    }
  }
  else
  { $status = unlink( $delFile ); }

  return $status;
}

###############################
# Copy a file
###############################
sub copyFile
{
  $status   = 1;
  $fromFile = shift;
  $toFile   = shift;

  if($fromFile =~ /\*|\?/) 
  { 
    @files = glob $fromFile;

    foreach $file (@files)
    {
      $status = copy($file, $toFile); 
    }
  }
  else
  {
    $status = copy($fromFile, $toFile);
  }

  return $status;
}

###############################
# Rename a file
###############################
sub renameFile
{
  $fromFile = shift;
  $toFile   = shift;

  moveFile($fromFile, $toFile);
}

###############################
# Clean and trim string
###############################
sub cleanString
{
  my $string = shift;

  #$string =~ s/[\n\@\#\$\%\^\&\*\(\)\{\}\[\]\|\!\~\/\`\<\>\:\;\"\,\=\']//sg;
  $string =~ s/[\n\$\%\^\&\*\{\}\[\]\|\!\~\/\`\<\>\:\;\"\,\']//sg;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  
  return $string;
}

###############################
# Generate a timestamp string
###############################
sub getTimeStamp
{
  my ($fday, $fmonth, $datestring);
  my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = localtime(time);

  $month += 1; 
  $year  += 1900;

  $day   = "0".$day   if($day < 10);
  $month = "0".$month if($month < 10);
  $sec   = "0".$sec   if($sec < 10);
  $min   = "0".$min   if($min < 10);
  $hour  = "0".$hour  if($hour < 10);

  $datestring = "$day $month $year $hour $min $sec";
  $datestring =~ s/\s+//g;

  return $datestring;
}

###############################
# Generate a datestamp string
###############################
sub getDateStamp
{
  my ($fday, $fmonth, $datestring);
  my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = localtime(time);

  $month += 1; 
  $year  += 1900;

  $day   = "0".$day   if($day < 10);
  $month = "0".$month if($month < 10);

  return($year.$month.$day) ;
}

###############################
# Returns a listing of all EDB 
# environments, and their 
# environment paths defined as 
# reported by the pshow command.
#
# If a name is passed in, only
# the environment matching that
# name will be returned.
###############################
sub getEnvs
{
  $name = shift;
  %envs = ();
  $login = getpwuid($<);

  open PSHOW, "/bin/csh -c \"source /data/edbmgr/.cshrc;source /data/edbmgr/.login;pshow\" |";

  while (<PSHOW>)
  {
    next if( /^\s*$|^\s*Environment/ );

    $line = $_;
    $line =~ s/^\s*//;
    $line =~ s/\s*$//;

    my ($env_name, $product, $version, $owner, $root_dir) = split/\s+/, $line;

    next if $owner =~ /^edbmgr$/;

    $root_dir =~ s/\/$//;
    $env_dir = $root_dir;
    $env_dir =~ s/db_areas$/db_env/;
  
    if( defined $name ) 
    { 
      if ( $env_name =~ /^edb\_$name\_v22$|^$name$/i ) 
      {
        if ( $owner =~ /$login/ || $login =~ /edbmgr/ )
        {
          $envs{$env_name} = { 
				ENV_DIR  => $env_dir,
				ROOT_DIR => $root_dir,
				OWNER    => $owner
			     };
        }
        else
        {
          print STDERR "Environment $env_name is not owned by $login\n";
        }
      } 
    }
    else
    {
      if ($login =~ /^edbmgr$/) 
      { 
        $envs{$env_name} = { 
				ENV_DIR  => $env_dir,
				ROOT_DIR => $root_dir,
				OWNER    => $owner
	  	           };
      }
      else 
      { 
        if ( $owner =~ /$login/ )
        {
          $envs{$env_name} = { 
				ENV_DIR  => $env_dir,
				ROOT_DIR => $root_dir,
				OWNER    => $owner
			     };
        }
      }
    }

    if(defined $envs{$env_name})
    {
       print STDERR "Could not locate environment file for environment: $env_name\n" unless -e "$envs{$env_name}{ENV_DIR}/$env_name.env";
    }
  }

  close PSHOW;

  return %envs;
}

###########################
# Sybase callback Routines
###########################
sub msg_cb 
{
        my($layer, $origin, $severity, $number, $msg, $osmsg, $dbh) = @_;

	printf STDERR "\nOpen Client Message: (In msg_cb)\n";
	printf STDERR "Message number: LAYER = (%ld) ORIGIN = (%ld) ", $layer, $origin;
	printf STDERR "SEVERITY = (%ld) NUMBER = (%ld)\n", $severity, $number;
	printf STDERR "Message String: %s\n", $msg;

	if (defined($osmsg)) {
	    printf STDERR "Operating System Error: %s\n", $osmsg;
	}

	CS_SUCCEED;
}


sub srv_cb 
{
   my($dbh, $number, $severity, $state, $line, $server, $proc, $msg) = @_;

   # If $dbh is defined, then you can set or check attributes
   # in the callback, which can be tested in the main body
   # of the code.

   #
   # hash of server errors to ignore
   #
   %srv_cb_ignore=( 5701=>1,	    # 5701 = use messages (ie. Changed DB to ...)
                    3604=>1,	    # 3604 = Duplicate Key was Ignored Errors, this is normal, so skip them
                    3621=>1,	    # 3621 = An Error Occurred, this always follws a more explicit error and is thus redundant.
                       0=>0 );	    #	 0 = user messages sent through SQL print statements.

   #
   # If this is a message we send through the SQL call.
   #
   if($number == 0 && $severity == 10 && $state == 1)
   {
        print STDERR "	   SQL Message : $msg \n";
   }

   if ( ! defined($srv_cb_ignore{$number} ) )
   {
     printf STDERR "\nServer message: (In srv_cb)\n";
     printf STDERR "Message number: %ld, Severity %ld, ", $number, $severity;
     printf STDERR "State %ld, Line %ld\n", $state, $line;

     if (defined($server)) 
     {
	printf STDERR "Server '%s'\n", $server;
     }

     if (defined($proc)) 
     {
        printf STDERR " Procedure '%s'\n", $proc;
     }

     printf STDERR "Message String: %s\n", $msg;
   }

   CS_SUCCEED;
}

###############################
# Open a log file and redirect
# STDOUT & STDERR to that file
###############################
sub openLOG
{
  my $filename = shift;

  die "Invalid logfile name: $filename\n" if ($filename =~ /^\s*$/);

  if (defined($ENV{EDBUTIL_DEBUG}))
	{
	print STDERR "EDBUtil::openLOG: EDBUTIL_DEBUG set, no log files opened\n" ;
	return ;
	}

  my $timestamp = getTimeStamp();

  moveFile($filename, $filename . "_" . $timestamp);
  open(STDOUT, ">$filename") || die "Can't redirect stdout to $filename";
  open(STDERR, ">&STDOUT")   || die "Can't redirect stderr to $filename";

  STDERR->autoflush(1);
  STDOUT->autoflush(1);
}


##############
# SENDS EMAIL
##############
sub sendEmail
{
        my $subject   = shift;
        my $body      = shift;
        my $to        = shift;          ### ACCEPTS EMAIL ADD COMMA-DELIMTED
                                        ### OR FILE WITH LIST OF EMAIL ADDRESSES
        my $from      = shift;
        my $host      = "";

        ### GET HOST AS SMTP SERVER ###
        $host = `hostname`;
        chomp($host);

        ### USE HOSTNAME IF "FROM" IS BLANK ###
        $from = $host if $from eq "";

        ### READ IF "TO" IF A FILE ###
        if (-f $to && -e $to)
        {
                my $file = $to;
                   $to   = "";
                open MAIL, $file or print "Error: Can't open/read $file file. $!\n";
                while(my $email_add=<MAIL>)
                {
                        chomp($email_add);
                        $email_add =~ s/\s+//g;
                        next if $email_add eq "";
                        $to = ($to eq "") ? $email_add : $to .",". $email_add;
                }
                close(MAIL);
        }


        ### SEND EMAIL ###
        if ($to =~ /\@/)
        {
                my $mailto = MIME::Lite->new
                (
                        Subject => "$subject",
                        From    => "${from}@fairchildsemi.com",
                        To      => "$to",
                        Type    => 'text/plain',
                        Data    => "$body"
                );

                $mailto->send("smtp",$host);
        }
        else
        {
                print "Can't send email. Invalid addressee \"$to\".\n";
        }
}

1;
