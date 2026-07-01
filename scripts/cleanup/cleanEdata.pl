#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS
  cleaanEdata.pl
    --cfgfile <cfg file>
    --test
    --logfile <log file>


=head1 DESCRIPTIONS

B<This script> will gzip x days old files and delete x days old files in  environment's  Processed and NotProcessed folders.
              see cleanEdataCfg.ini file for details.

=head1 AUTHOR

B<junifferallan.garcia@onsemi.com>

=head1 CHANGES
2022-Jul-13 : jgarcia : updated to use File::Find::Rule and File::Find::Rule::Age instead of native linux command in finding folder and files.
                        observed faster than using native linux command.
                      : updated to clean files first before trying to compress the files whatever left from cleanup process.
2022-Jul-14 : jgarcia : modified to make sure only one instance will be run.

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
use File::Find::Rule;
use File::Find::Rule::Age;
use Data::Dumper;
use Sys::RunAlone;


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
my @exclude_dirs = qw( log hold Processed NotProcessed ReworkFiles ); 

   foreach my $section (keys %{$config}) {
     INFO("Environment Type = $section");
      my @subdirs = File::Find::Rule
        ->mindepth(1)
        ->maxdepth(1)
        ->not_name(@exclude_dirs)
        ->directory
        ->in($config->{$section}->{dpdata});

 
     INFO("clean $config->{$section}->{processed_clean_days_old} days old files in Processed folders under root dir=$config->{$section}->{dpdata}");
     cleanFiles($config->{$section}->{dpdata}, \@subdirs, "Processed", $config->{$section}->{processed_clean_days_old}, $section);
     INFO("clean $config->{$section}->{notProcessed_clean_days_old} days old files in NotProcessed folders under root dir=$config->{$section}->{dpdata}");
     cleanFiles($config->{$section}->{dpdata}, \@subdirs, "NotProcessed", $config->{$section}->{notProcessed_clean_days_old}, $section);
     INFO("clean $config->{$section}->{warnings_gzip_days_old} days old files in Warnings folders under root dir=$config->{$section}->{dpdata}");
     cleanFiles($config->{$section}->{dpdata}, \@subdirs, "Warnings", $config->{$section}->{warnings_clean_days_old}, $section);

     INFO("gzip $config->{$section}->{processed_gzip_days_old} days old files in Processed folders under $config->{$section}->{dpdata}");
     gzipFiles($config->{$section}->{dpdata}, \@subdirs, "Processed", $config->{$section}->{processed_gzip_days_old}, $section);
     INFO("gzip $config->{$section}->{notprocessed_gzip_days_old}  days old files in NotProcessed folders under root dir=$config->{$section}->{dpdata}");
     gzipFiles($config->{$section}->{dpdata}, \@subdirs, "NotProcessed", $config->{$section}->{notProcessed_gzip_days_old},$section);
     INFO("gzip $config->{$section}->{warnings_gzip_days_old} days old files in Warnings folders under root dir=$config->{$section}->{dpdata}");
     gzipFiles($config->{$section}->{dpdata}, \@subdirs, "Warnings", $config->{$section}->{warnings_gzip_days_old}, $section);
    
   }


dpExit(0);


sub gzipFiles {
  my $rootDir = shift;
  my $dirs = shift;
  my $folderName = shift;
  my $fileAge = shift;
  my $section = shift;

  INFO("Start to walk on all  folders under $rootDir");
  #foreach my $folder (`find $rootDir -type d -name "$folderName"`) {
  foreach my $folder(@$dirs) {
    chomp($folder);
    #INFO("DIR=$folder");
    if($folder =~ /.*\_wait$/i) {
      INFO("Skipping Wait folder=$folder");
      next;
    }
   if($section eq "non_wks") {
      next if ( $folder =~ /\_wks/ );
    } else {
      next if ( $folder !~ /\_wks/ );
    }
    my $finalFolder = "${folder}/$folderName";
    INFO("FINALDIR=$finalFolder");
    my $age = "${fileAge}D";
    INFO("FileAge=$age");
    my @files = find( file => age => [older => $age ], in => $finalFolder);
    #foreach my $file (`find $folder -type f -mtime +$fileAge ! -iname "*.gz" ! -iname "*.zip" `) {
    foreach my $file(@files) {
      chomp($file);
      if($hOptions{TEST}) {
        INFO("Gzipping file=$file");
        #next;
      } else {
        if($file !~ /\.gz$/i) {
          &doCompressGzip($file);
          my $newLogGzipFile = "${file}.gz";
          if(-e $newLogGzipFile) {
            INFO("Compress $file to gzip successful.");
          } else {
            WARN("Compress $file to gzip unsucessful.");
          }
        } else {
          INFO("$file already compressed to gz!!! Skipping...");
        }
        
        #next;
      }
    }    #EACH FILE
  }    #EACH DIR
} ### end of subroutine gzipFiles

sub cleanFiles {
  my $rootDir = shift;
  my $dirs = shift;
  my $folderName = shift;
  my $fileAge = shift;
  my $section = shift;
	my $errCnt = 0;

  INFO("Start to walk on all  $folderName folders under $rootDir");
	#foreach my $folder(`find $rootDir -type d -name "$folderName"`) {
   foreach my $folder(@$dirs) {
    chomp($folder);
        
    if($folder =~ /.*\_wait$/i) {
      INFO("Skipping Wait folder=$folder");
      next;
    }
    INFO("DIR=$folder");
    if($section eq "non_wks") {
      #INFO("Exclude wks environments");
      next if ( $folder =~ /\_wks/ );
    } else {
      #INFO("Only for wks environments");
      next if ( $folder !~ /\_wks/ );
    }
    my $finalFolder = "${folder}/$folderName";
    INFO("FINALDIR=$finalFolder");
    my $age = "${fileAge}D";
    INFO("FileAge=$age");
    my @files = find( file => age => [older => $age ], in => $finalFolder);
    #print Dumper(\@files);

    # #INFO("Exclude wks environment folders");
	  # #next if ($folder =~ /\_wks/);
		  #foreach my $file(`find $folder -type f -mtime +$fileAge ! -name "*.limit*"`) {
      foreach my $file(@files) {
		     chomp($file);
         if($file =~ /.*\.limit.*/i) {
            next;
            INFO("Skipping limit file=$file");
         }
         #next if $file =~ /.*\.limit.*/i;
         
         if($hOptions{TEST}){
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
               send_mail("Cleanup script might not be working properly.Too may files not deleted. Please check.");
               WARN("Cleanup script might not be working properly.Too may files not deleted. Please check.");
             } else {
               next;
             }
           }
         }
  	  	} #EACH FILE
	  } #EACH DIR
  }

sub send_mail
{
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
__END__
