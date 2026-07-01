#!/usr/bin/perl
#------------------------- File Header -----------------------------------
#
# File Name: splitbycolumn.pl
#
# Description: This script splits a data file into several smaller files
#              based on a user defined several column numbers. All the lines
#              that have the same combination of the specified column value(s)
#              will be written to the same file.
#
# Sccs Id:    @(#)split_by_fields.pl	1.3 02/22/01 16:22:47
#
# Related Files/Documents:
#
# Revision History
# ________________
# Date      Author           Description
#
# 02-22-01  B. Almasri       Initial Version
# 06-30-04  Shane Handy      Added support for writing out headers line
#			     of varying number.  Changed the filename to
#			     use the value in the column being split.
#			     Usage:  splitbycolumn.pl filename headerLine dataType
#				where: filename = file to be split
#				       headerLine = number of lines
#				       in filename that are the header
#				       information (starting from the top
#				       of the file) that will be written
#				       to the start of each output file.
#				       dataType = the type of data, bin, pcm, leh
#			     Outputs: Outputs one file (with headers) for
#				      each unique combination of columns
#				      Output filename =
# 				        inputFilename_columnValue_dataType.split
#
#		note: not very efficient at this point as the program opens
#		and closes the file for each line being written.  Needs to be
#		updated to open the file(s) once and close them when the
#		program is done.  sgh.
#
#		Also, this verion only tested for delimited files.
# 07-12-04  Shane Handy
#		1) Added additional splitcolumn option for split column
#			splitcolumn = the column number to be splitted - 1
#		2) Added additional outdir option for output files to go to
# 10-08-06  Tuo Xu
#       1) Modified with command line options
#       2) Modified with a list of columns to split on, instead of defining 1,2 and 3
#       3) Defined a buffer with a certain amount of lines for every time of outputting, Now write to a certain file every certain
#           amount of lines, so there'll be never so many times of file operations (opening, writing to, closing files), and also
#           much more memory will be available (instead of being consumed by the splitting process) even splitting very large files.
#  10-13-06 Tuo Xu
#       1) Created the output directory if it does not exist
# 10-24-07 Saib Nashashibi
#       1) Add the option to exclude column(s) from being outputted
#       2) Replace any missing field with the value in $nullreplace variable
#       3) If more that one separator is used, the first separator will be used in the output file
#       4) Fix some bugs in the logic of splittings the input lines. Multiple consequence separators used to considered as one separator
#       5) so many times of writes to the disk whenever splitting large files
#-------------------------------------------------------------------------
# Usage:
#   To run the splitbycolumn program, the command line option would be:
#   perl splitbycolumn.pl <inputfile(s)> -outdir output/ -ext "split" -splitcolumn  1,2,3 -excludecolumn 4,5,6 -header 1 -separator \, -debug
#   i.e. split the files by column 1,2,3 and output files to output/ directory with 1 header line and the comma as the separator,
#   and also, when the debug option is turn on, we can see the debug information.
#   Also, the -separator, -header,-excludecolumn, -debug options are optional. By default the split columns are separated by comma (1,2,3),
#   and the default value for header is 1, separator is comma, and debug is off.
#   When you're setting the separator option, just add a backslash before the separator, like \\t, \;.
#
# user defined values
# Note: the characters and columns (words) start with the value 0
# Note: to exclude a column, set col?_start or col?_column to -1
# ----------------- Start CVS Section (do not modify) -------------------
#
#      $Id: splitbycolumn.pl 15 2015-03-19 11:07:17Z dpower $
      my($sVersionId) = ( split(' ', '$Revision: 15 $') )[1];
# ------------------------- End CVS Section -----------------------------
#
#******************************************************************************
#-------------------------------------------------------------------------
# Variable declarations

use strict;
use Getopt::Long;
use File::Basename;
use File::Spec::Functions;
sub Split_on_single_file;
sub Output_lines;

#******************************************************************************
#                                 Main
#
#******************************************************************************

# define the size of each output to certain files
our $OUTPUT_SIZE = 10000;
# define the string to be used in case of null field
my $nullreplace = "NA";
# a hash to receive options
my (%hOptions)= (
    "OUTDIR" => undef,
    "HEADER" => undef,
    "EXT" => undef,
    "SPLITCOLUMN" => undef,
    "EXCLUDECOLUMN" => undef,
    "DEBUG"  => undef,
    "SEPARATOR" => undef,
    "HELP"  => undef,
	"CUSTOM"  => undef,
);

my $debug = 0;                #by default the debug mode is turned off
my $separator = ",";          #by default the separator is the comma
my $header = 1;               #by default the number of the header is 1
my $exclude = "0";            #by default exclude nothing
my $custom = 0;               #by default custom is zero

my($sUsageMsg) = <<"__END_OF_USAGE_MESSAGE__";      # Usage note
splitbycolumn.pl <inputfiles> ...
       [ -outdir <directory> ]         Output directory
       [ -header <number> ]            Numbers of headers you would like to keep
       [ -ext <tp> ]                   Type of data (bin, pcm, leh)
       [ -splitcolumn <number> ]       Numbers that you want to split on (start from 1), separated by comma
       [ -excludecolumn <number> ]     Numbers that you want to exclude from being outputed (start from 1), separated by comma
       [ -debug ]                      Debug mode (off by default)
       [ -separator ]                  Separator of columns (comma by default), if more than one separator have been used
                                       the first separator will be used as output separator
       [ -VERSION | -help ]            Display version ID or help messages
	   [ -custom ]            		   Used to rename the split files
__END_OF_USAGE_MESSAGE__

# turn the ignorecase option on so that the options will be case-insensitive
$Getopt::Long::ignorecase = 1;

if($#ARGV<0) {die($sUsageMsg);}
# get all values of the options that the user has defined
die "$sUsageMsg" unless ( GetOptions(\%hOptions,
               "OUTDIR=s",
               "HEADER=s",
			   "CUSTOM=s",
               "EXT=s",
               "SPLITCOLUMN=s",
               "EXCLUDECOLUMN=s",
               "SEPARATOR=s",
               "DEBUG" => \$debug,
               "HELP" => sub { print $sUsageMsg; exit },
               ));

# and also get all the names of the files that the user would like to split
my @file_list = @ARGV;

# set the header, separator, and excludecolumn values of the option hash to be the default if they were not defined yet
$hOptions{HEADER} = $header unless defined($hOptions{HEADER});
$hOptions{CUSTOM} = $custom unless defined($hOptions{CUSTOM});
$hOptions{SEPARATOR} = $separator unless defined($hOptions{SEPARATOR});
$hOptions{EXCLUDECOLUMN} = $exclude unless defined($hOptions{EXCLUDECOLUMN});
# output separator will be the first separator in case of multiple separators.
#my $out_separator = substr($hOptions{SEPARATOR}, 0, 1);
my $out_separator = $hOptions{SEPARATOR};


# create the outdir if it does not exist
if (!-e $hOptions{OUTDIR}) {
    printf STDERR "Making output directory: $hOptions{OUTDIR}\n" if $debug;
    my $mkdir_ret = mkdir($hOptions{OUTDIR}, 0777);
    if ($mkdir_ret != 1) {
        printf STDERR "Fail to make output directory $hOptions{OUTDIR}\n" if $debug;
        exit(1);
    }
}

# output the option values if the debug option is turned on
printf STDERR "Input file: @file_list\n" if $debug;
printf STDERR "Output directory: $hOptions{OUTDIR}\n" if $debug;
printf STDERR "Number of headers you want to keep: $hOptions{HEADER}\n" if $debug;
printf STDERR "Datatype: $hOptions{EXT}\n" if $debug;
printf STDERR "Separator: $hOptions{SEPARATOR}\n" if $debug;
my $split_col = $hOptions{SPLITCOLUMN};
$split_col =~ s/,/\ /g;                                                         #why change the , into space?
printf STDERR "Split column(s): $split_col\n" if $debug;
my $exclude_col = $hOptions{EXCLUDECOLUMN};
$exclude_col =~ s/,/\ /g;                                                        #why change the , into space?
printf STDERR "Exclude column(s): $exclude_col\n" if $debug;

# parse all the files in order
foreach(@file_list) {
  my $file = $_;
  printf STDERR "\n --> Splitting the file $file, please wait...\n";
  
  Split_on_single_file($file,\%hOptions);
  
  printf STDERR " --> Done with splitting the file $file.\n";
}

printf STDERR " --> Done!\n";

1;


sub Split_on_single_file {
#******************************************************************************
# Split_on_single_file - Subroutine to split on a single file
#
#******************************************************************************
  my ($file, $hOptions) = @_;
  
  # the hash to store output key-value pairs, with the keys as
  # output filenames, and the values as the split content
  my %output;
  my %f_names;
  my %line_cnt;
  my $fname;

  my $hd_count;
  my @aHead;

  my $split_col = $hOptions->{SPLITCOLUMN};
  # the numbers of split columns are separated by comma as we asked
  my $split_col_separator = ",";
  # get the list of columns the user would like to split on
  my @split_col_arr = split(/[${split_col_separator}]+/,$split_col);
  # minus by 1 on the columns, so for example, 1 for the first column now
  foreach(@split_col_arr) {
    $_ -= 1;
  }
  my $exclude_col = $hOptions->{EXCLUDECOLUMN};
  # the numbers of exclude columns are separated by comma as we asked
  my $exclude_col_separator = ",";
  # get the list of columns the user would like to exclude
  my @exclude_col_arr = split(/[${exclude_col_separator}]+/,$exclude_col);
  # minus by 1 on the columns, so for example, 1 for the first column now
  foreach(@exclude_col_arr) {
    $_ -= 1;
  }
  
  # open the file
  open(fhIn, "<$file") || die "Unable to open file $file\n";

  # read in the head lines information, store in an array for later write, if there excludecolumn option is used, exclude the header for the requested column
  if ($hOptions->{HEADER} > 0 && $exclude_col == "0" ) {
    $hd_count = 0;
    while (<fhIn>) {
      $hd_count++;
      chop;
      push @aHead, $_;
      print "HeadLine: $_\n" if $debug;
      if ($hd_count == $hOptions->{HEADER}) {
        # all headers read, exit the loop
        last;
      }  # exit loop
    } # end while
  } # number of head lines greater than 0 and no columns to exlude
  
  elsif ($hOptions->{HEADER} > 0 ) {
  
    $hd_count = 0;
    while (<fhIn>) {
      $hd_count++;
      chop;
      my $hdrline = $_;
      # split header fieldes and stor in an array
      my @hdrwords = split(/[{$separator}]/, $hdrline);
      # remove elements from the header array that are header for the excluded columns
      my @excludecol_arr = @exclude_col_arr;
      for(my $i = 0; $i <= $#excludecol_arr; $i++) {
      splice(@hdrwords, ($excludecol_arr[$i] - $i), 1);
      }
      # reconstruct the header using the first specified separator if multi separators was used
      $_ = join($out_separator, @hdrwords);
      push @aHead, $_;
      print "HeadLine: $_\n" if $debug;
      if ($hd_count == $hOptions->{HEADER}) {
        # all headers read, exit the loop
        last;
      }  # exit loop
    } # end while
  } # number of head lines greater than 0 and no columns to exlude and there is columns to be excluded

  my $separator = $hOptions->{SEPARATOR};
  # now read the file contents, file pointer should be at first
  while (<fhIn>) {
    my $combined_value = "";
    my $line = $_;
    my @col_arr = @split_col_arr;

    # replace all null fields with the null replacement. All the below replace statmens should be use
	$line =~ s/^\s+$//g;
	$line =~ s/\//-/g; #replace / with - to avoid writing error.-hiro
    $line =~ s/^[$separator]/$nullreplace$out_separator/g;
    $line =~ s/[$separator][$separator][$separator]/$out_separator$nullreplace$out_separator$nullreplace$out_separator/g;
    $line =~ s/[$separator][$separator]/$out_separator$nullreplace$out_separator/g;

    chomp $line;

    # get the values of corresponding columns
    my @words = split(/[{$separator}]/, $line);
    if ($col_arr[0] >= 0) {
      my $col1_val = $words[$split_col_arr[0]];
      $combined_value .= $col1_val;
      shift @col_arr;
    }
    while(@col_arr) {
      my $col_val = $words[$col_arr[0]];
      $combined_value .= '_'.$col_val;
      shift @col_arr;
    }

    $combined_value =~ s/\s+//g;
    $combined_value =~ s/\"//g;

    # if the combined value of columns on which the user splits on is already defined in the hash as the key, then use its value
    if (defined($f_names{$combined_value})) {
        $fname = $f_names{$combined_value};
    } else {
        # else define the key-value pair in the hash and add the header lines to the output string to this file
        #$fname = basename($file) . "_" . $combined_value . "_" . "split." . $hOptions->{EXT};
        #$fname = basename($file) . "_" . $combined_value . "." . $hOptions->{EXT};
		my $string = basename($file);
		my $ii = index($string,'.');
		#print "ii: $ii\n";
        $fname = substr($string,$hOptions->{CUSTOM},$ii-$hOptions->{CUSTOM})."_" . $combined_value . "." . $hOptions->{EXT};
        $fname = canonpath(catfile($hOptions->{OUTDIR}, $fname));
        
        $f_names{$combined_value} =  $fname;

        # create the file and write in the headers unless it exists.
        if ((! -e $fname) && ($hOptions->{HEADER} > 0)) {
            for (my $i = 0; $i < @aHead; $i++) {
                $output{$fname} .= "$aHead[$i]\n";
                $line_cnt{$fname} += 1;
            }  # end for
        } # if headers need to be written
    }
    # remove elements from the column array that are in an excluded columns
    my @excludecol_arr = @exclude_col_arr;
    if($exclude_col != "0") {
      for(my $i = 0; $i <= $#excludecol_arr; $i++) {
      splice(@words, ($excludecol_arr[$i] - $i), 1);
      }
      $line = join($out_separator, @words);
    }
    # add the current line to the output string and increment the line counter
	
    #if($line !~ /^\s+$/) 
    $output{$fname} .= "$line\n";
    $line_cnt{$fname} += 1;
    
    # when line counter of certain output file reaches every output_size, then
    # we output them and clear the output store for that output
    if ($line_cnt{$fname}%$OUTPUT_SIZE == 0) {
        Output_lines($fname, $output{$fname});
        $output{$fname} = "";
    }
  }
  
  # and then output all the rest lines to their corresponding files
  foreach my $key (keys(%output)) {
    Output_lines($key, $output{$key});
  }
  close(fhIn);
}


sub Output_lines {
#******************************************************************************
# Output_lines - Subroutine to output lines to the output file by appending
#
#******************************************************************************
    my ($outfile, $output) = @_;
    open(fOutput, ">>$outfile") || die "Unable to open file $outfile: $!\n";
    print fOutput $output;
    close(fOutput);
}

