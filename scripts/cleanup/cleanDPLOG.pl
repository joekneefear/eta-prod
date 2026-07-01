#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  cleaanEdata.pl
    --cfgfile <cfg file>
    --test
    --logfile <log file>


=head1 DESCRIPTIONS

B<This script> will gzip x days old files , rename and delete x days old files in  $DPLOG 

=head1 AUTHOR

B<junifferallan.garcia@onsemi.com>

=head1 CHANGES

=head1 LICENSE

(C) ON Semiconductor 2021 All rights reserved.

=cut

use strict;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use MIME::Lite;
use File::Find;
use File::Basename;
use File::Copy;
use Getopt::Long;
use IPC::Open3;
use Time::Piece;
use File::stat;
use Config::Tiny;
use PDF::Log;
use PDF::DpLoad;
use File::Spec;


my (%hOptions) = ();
my $hostname = `hostname`;

unless ( GetOptions ( \%hOptions, "CFGFILE=s", "TEST", "LOGFILE=s")) {
    pod2usage(3);
}

my @requiredArguments = qw/CFGFILE/;

if(grep {!exists $hOptions{$_}} @requiredArguments) {
	pod2usage(3);
}

PDF::Log->init(\%hOptions);

my $config = Config::Tiny->read($hOptions{CFGFILE});
#foreach my $folder(@folders) {
  foreach my $section (keys %{$config}) {
    INFO("clean $config->{$section}->{days_old} days old files in $config->{$section}->{dplog}");
    cleanLogFiles($config->{$section}->{dplog}, $config->{$section}->{days_old});
    INFO("rename $config->{$section}->{rename_days_old} days old files in $config->{$section}->{dplog}");
    renameLogFiles($config->{$section}->{dplog}, $config->{$section}->{rename_days_old});
    INFO("gzip $config->{$section}->{gzip_days_old} days old files in $config->{$section}->{dplog}");
    gzipLogFiles($config->{$section}->{dplog}, $config->{$section}->{gzip_days_old});

  }
#}

dpExit(0);

sub renameLogFiles {
  my $rootDir = shift;
  my $fileAge = shift;

  if($fileAge > 0) {
    foreach my $file (`find $rootDir -maxdepth 1 -type f -name "*.log*" -mtime +$fileAge ! -iname "*.gz" ! -iname "*.zip"`) {
      chomp($file);
      next if -d $file;

      #my($vol, $dir, $fname) = File::Spec->splitpath($file);
      my($fname,$fdir,$ext) = fileparse($file, qr/\.[^.]*/);
      my $date = substr(getLoggingTime(), 0, 8);
      #my $date = &getLoggingTime();
      next  if $file =~ /$date/;
      $fname =~ s/\.log//g;
      my $newLogFile = "${rootDir}/${fname}_${date}.log";
      if($hOptions{TEST}) {
        INFO("Renaming $file to $newLogFile");
        next;
      } else {
        move($file, $newLogFile);
        if(-e $newLogFile) {
          INFO("$file was renamed to $newLogFile");
        } else {
          WARN("Unable to rename $file to $newLogFile");
        }
        next;
      }
    }
  } else { #-type f -name "*.log*" -and ! -name "*.gz" ! -size 0
    foreach my $file (`find $rootDir -maxdepth 1 -type f -name "*.log*" -and ! -iname "*.gz" ! -iname "*.zip"  ! -size 0`) {
      chomp($file);
      next if -d $file;
      #my($vol, $dir, $fname) = File::Spec->splitpath($file);
      my($fname,$fdir,$ext) = fileparse($file, qr/\.[^.]*/);
      my $date = substr(getLoggingTime(), 0, 8);
      next  if $file =~ /$date/;
      $fname =~ s/\.log//g;
      my $newLogFile = "${rootDir}/${fname}_${date}.log";
      if($hOptions{TEST}) {
        INFO("Renaming $file to $newLogFile");
        next;
      } else {
        move($file, $newLogFile);
        if(-e $newLogFile) {
          INFO("$file was renamed to $newLogFile");
        } else {
          WARN("Unable to rename $file to $$newLogFile");
        }
        next;
      }
    }
  }
}

sub gzipLogFiles {
  my $rootDir = shift;
  my $fileAge = shift;
  #INFO("Start to walk on all  $folderName under $rootDir");
  #foreach my $folder (`find $rootDir -type d -name \"$folderName\"`) {
  #  chomp($folder);
    #INFO("DIR=$folder");
   foreach my $file (`find $rootDir -maxdepth 1 -type f -name "*.log*" -mtime +$fileAge ! -iname "*.gz" ! -iname "*.zip"`) {
      chomp($file);
      next if -d $file;
      if ($hOptions{TEST}) {
        INFO("TEST: gzipping file=$file");
        next;
      } else {
        &doCompressGzip($file);
        my $newLogGzipFile = "${file}.gz";
        if(-e $newLogGzipFile) {
          INFO("Compress $file to gzip successful.");
        } else {
          WARN("Compress $file to gzip unsucessful.");
        }
        next;
      }
   } #EACH FILE
 } ### end of subroutine gzipFiles

sub cleanLogFiles {
  my $rootDir = shift;
  my $fileAge = shift;
  my $errCnt = 0;

  #INFO("Start to walk on all  $folderName folders under $rootDir");
	#foreach my $folder(`find $rootDir -type d -name \"$folderName\"`) {
  #  chomp($folder);
    #INFO("DIR=$folder");
    #INFO("Exclude wks environment folders");
	  #next if ($folder =~ /\_wks/);
    INFO("File Age = $fileAge");
		foreach my $file(`find $rootDir -maxdepth 1 -type f -name "*.log*" -mtime +$fileAge -o -mtime $fileAge`) {
		    chomp($file);
        if($hOptions{TEST}) {
          INFO("Test delete = Deleting $file");
        } else {
          my $return = unlink "$file";
          if($return == 1) {
            INFO("Deleting $file successful");
          } else {
            $errCnt++;
            WARN("Deleting $file unsuccessful");
            send_mail("Failed to delete file = $file", "junifferallan\.garcia\@onsemi\.com");
            if ($errCnt => 5) {
              send_mail("Script Aborted! Too may files not deleted. Please check.");
              WARN("Script Aborted! Too may files not deleted. Please check.");
            } else {
              next;
            }
          }
        }
  	 } #EACH FILE
}

sub send_mail {
        my $body   = shift;
        my $email  = shift;
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
