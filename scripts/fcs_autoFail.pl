#!/usr/bin/env perl_db
#$Id

# All this script does is fail files.
# This allows the preprocessor to separate good/bad data from a single incoming file.
# The preprocessor writes the "good data" to an IFF with .iff or similar extension.
# The preprocessor also writes the "bad data" to another file with a different extension like .bad.
# This script is executed against all files with the .bad extension, returning an error code and forcing the file to NotProcessed.

use strict;
use FindBin::libs;
use Getopt::Long;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use POSIX qw(strftime);
use DateTime::Format::Strptime;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Formatter;
use v5.10;

### Check Argument
my (%hOptions) = ();

unless ( GetOptions( \%hOptions, "OUT=s" ) && (@ARGV > 0))
{
    print "USAGE: $0 <fileName> --out {output dir}\n";
    exit(1);
    #pod2usage(3);
}

#
my $infile = $ARGV[0];
my $basename = basename($infile);
my $dir    = $hOptions{OUT};

dpExit(1,"Auto-fail file with this extension");

