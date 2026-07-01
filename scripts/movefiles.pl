#!/usr/bin/env perl_db
# 10-Nov-2015 Eric	:Initial release
#
# Function : reads list of files inside the file and move each file up one directory
use strict;
use Getopt::Long;
use Pod::Usage qw/pod2usage/;
use File::Basename;
use File::Spec;
use File::Touch;
use POSIX qw(strftime);
use Tie::File;
use File::Copy;
use v5.10;

my $infile = "";
my $result      = GetOptions ("infile=s"   => \$infile);
		
if($infile eq "")
{
        print "\nUsage: movefiles.pl -infile=<FULL-PATH-TO-FILE>";
        exit (1);
}
tie my @file, 'Tie::File', $infile  or die $!;

for my $linenr (0 .. $#file) {
	#print "$file[$linenr]\n";
	my $dir    = dirname($file[$linenr]);
	my $mv_dir = dirname($dir);
	my $mv_fn     = basename($file[$linenr]);
	system "/bin/mv -f \'${file[$linenr]}\' ${mv_dir}/${mv_fn}";
        my $status = (-e "${mv_dir}/${mv_fn}") ? "Successful" : "Failed";
        print"Moving $file[$linenr] $status \n";
        next if $status eq "Failed";
	#last;
}
untie @file;
