#!/usr/bin/env perl_db
=pod

=head1 SYNOPSIS

  fetchFiles.pl 
      	--env [environment name e.bksort_eagle, bksort_mwap_sep]
      	--cfg < config file >
      	--logfile <logfilepath>
      	
=head1 DESCRIPTIONS

B<This script> fetch file via sftp

=head1 AUTHOR

B<junifferallan.garcia@onsemi.com>

=head1 CHANGES

 
=head1 LICENSE

(C) ON Semiconductor. 2021 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use File::Basename qw/basename dirname/;
use Net::FTP;
use File::Copy;
use MIME::Lite;
use PDF::Log;
use Config::Tiny;
use feature qw(say);
#use autodie;
use Net::SFTP::Foreign;
use PDF::Log;
use PDF::DpLoad;
#use IO::Pty;
use Text::Glob 'glob_to_regex';
use English;

my (%hOptions) = ();

unless (
    GetOptions(
        \%hOptions,  "ENV=s", "CFGFILE=s", "LOGFILE=s", "DEBUG", "TRACE", )
    )
{
    dpExit( 1,"invalid options" );
    pod2usage(3);
}

PDF::Log->init( \%hOptions);
my $config = Config::Tiny->read($hOptions{CFGFILE});
my $env = $hOptions{ENV};
my $hostname = `hostname`;
my $fileType = "";
my $fileToCheck = $hOptions{CFGFILE}.".PID";
my $pid = "";

my @required_options = qw/ENV CFGFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

chomp($hostname);

# check first if there is a fetch script for the environment cfg that is running
# do not continue if there is already running.

if( -e $fileToCheck) {
    open(FH, '<', $fileToCheck) or die $!;
	while(<FH>){
   		INFO("PID=$_");
		$pid = $_;
	}
	close(FH);
	my $owner = &is_running($pid);
	if($owner) {
		WARN("There is fetch script for that is currently runnig for this config=$config->{$env}->{cfg}, fecth script will exit.");
		dpExit(0);
	} else {
		INFO("PID config file exists=>$fileToCheck, but corresponding process is not active.");
		INFO("Process with the pid=$pid is not running anymore!!!");
		INFO("$fileToCheck will be deleted and continue..");
	}
}

open my $fh, '>', $fileToCheck ;
    print {$fh} $PID . "\n";
close $fh;

INFO("PULL_NODE: $config->{$env}->{pull_node}");
INFO("PULL_PATH: $config->{$env}->{pull_path}");
INFO("SFTP_IN  :    $config->{$env}->{sftp_in}");
INFO("SFTP_IN_WAIT: $config->{$env}->{sftp_in_wait}");

INFO("Get extension of the files to pull");
if($config->{$env}->{pull_file_type} ne "") {
	$fileType = $config->{$env}->{pull_file_type};
} else {
	INFO("File extension is not specified, will fetch all file type!!!");
	$fileType = "*.*";
}

#
# Change Directory to FTP_IN_WAIT
#
if (! chdir($config->{$env}->{sftp_in_wait}))
{
	ERROR("Could not chdir($config->{$env}->{sftp_in_wait})");
	unlink($fileToCheck);
	dpExit(1,"Could not chdir($config->{$env}->{sftp_in_wait})");
}
INFO("Starting the process to pull files.");
&pullFiles();

unlink($fileToCheck);
dpExit(0);

sub pullFiles {
	
	my @fileList = ();
	my $files;
	my $sftp = Net::SFTP::Foreign->new($config->{$env}->{pull_node}, user => $config->{env}->{pull_user}, more=>[ -i => "/export/home/dpower/.ssh/id_rsa", -o => 'PreferredAuthentications=publickey',],);
	if($sftp->die_on_error() ) {
		my $body = "ERROR $env :Fetch Script could not connect to the server"
                 . "\nCould not connect to server $config->{$env}->{pull_node} ...\n\n".$sftp->error."\n";
    &send_mail("$body");
	unlink($fileToCheck);
    dpExit(1,"Unable to establish SFTP connection");
	}
	INFO("Change directory to $config->{$env}->{pull_path}");
	#if($sftp->setcwd($config->{$env}->{sftp_in_wait})) {
	$sftp->setcwd($config->{$env}->{pull_path});
	#} else {
	if($sftp->error) {
		&send_mail("Could not change directory to $config->{$env}->{pull_path} : ". ${ \$sftp->error } ."\n");
		ERROR("Could not change directory to $config->{$env}->{pull_path} : ${ \$sftp->error }");
		unlink($fileToCheck);
		dpExit(1,"Could not change directory to $config->{$env}->{pull_path}");
	}
#	if($sftp->error) {
#		
#	}
	if($fileType ne "*.*"){
		  my @types = split /\s+/, $fileType; 

		  foreach my $type (@types) {
		   #my $list = $sftp->ls($config->{$env}->{pull_path});
		   $files = $sftp->ls(wanted => glob_to_regex($type));
		   #$files = $sftp->glob($type);
#		   my @testFiles = @{ $files };
		   #my @testFiles = @{$[0]};
		  # if($sftp->error) {
#		   if (scalar $testFiles[0] == 0) {	
#		   	 WARN("Can't get a file listing:");
#		   }
#		   my @filteredList = grep { $_ =~ $type } @$list;
#
#		   foreach my $file (@filteredList) { 
#		   		push @$file, $file; 
#		   }
		  }
	}	else {
		 #$files = $sftp->ls($config->{$env}->{pull_path});
		 $files = $sftp->ls(wanted => glob_to_regex($fileType));
		 #$files = $sftp->glob($fileType);
		 #my @testFiles = @{ $files };
		  #if (scalar $testFiles[0]  == 0) {
		 #		WARN("Can't get a file listing:");
		 #}
		 #if($sftp->error) {
		 #	WARN("Can't get a file listing:");
		 #}
	}
	#
	# Start fetching the remote files ...
	#
	
	my @testFiles = @{ $files };
	if (scalar $testFiles[0] == 0) {
			WARN("Can't get a file listing:");
	} else {
		INFO("Start fetching the remote files...");
		foreach my $file (@$files) {
			INFO("Fetching $file->{filename}");
			my $fetched_file = $sftp->get($file->{filename});
	
			if($sftp->error) {
				ERROR("Something went wrong while fetching the file $file->{filename}.. ${ \$sftp->error }");
			} else {
				 INFO("Fetched $file->{filename} successfully.");
				 #INFO("Move the file to ");
				 INFO("Deleting $file->{filename} from the Server.");
				 $sftp->remove($file->{filename}) or WARN("Could not delete $file->{filename} from the server: ${ \$sftp->error }");
			   ### MOVE FILE IMMEDIATELY ###
			   my $newfile = "$file->{filename}";
	       $newfile =~ s/\s+//g;
			   INFO("Moving $config->{$env}->{sftp_in_wait}/$file->{filename} to $config->{$env}->{sftp_in}/$newfile");
			   move("$config->{$env}->{sftp_in_wait}/$file->{filename}", "$config->{$env}->{sftp_in}/$newfile") or WARN("Could not move file to $config->{$env}->{sftp_in}: ${ \$sftp->error }!");
	       ### UPDATE FILE PERMISSION ###
			   system("chmod 775 $config->{$env}->{sftp_in}/$newfile"); 
			}
  	}
	}
}### end of sub routine
   
sub send_mail {
        my $body   = shift;
        my $email  = 'junifferallan.garcia@onsemi.com';
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

sub is_running() {
    my $pid = shift;
    my @proc_data = split(/\s+:\s+/, `ps uax | awk '{print \$1,":",\$2}' | grep $pid`);
    return (@proc_data && $proc_data[1] == $pid) ? $proc_data[0] : undef;
}


