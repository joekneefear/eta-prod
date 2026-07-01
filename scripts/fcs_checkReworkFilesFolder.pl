#!/usr/bin/env perl_db
=pod
=head1 SYNOPSIS

fcs_metadtaVerifier.pl <Input flie name> --out <output dir> --env <dataflow enrivonment name e.g bksort_wmap_nam> --fileage <desired number of days and will be used to be compared against the lastest modification date of the input file> --finallot <if environment is a finallot> --pplog [--logfile <logfilepath>] [--debug|--trace]

=head1 DESCRIPTIONS

B<This script> will use the DpLoad.pl->move_oldest_file subroutine that accepts source, desitination folder and an optional file age in days/hour as paramters. it will check the files in the source dir for the oldest file and move destination folder, if file age is passed, it will check first if the mtime of the oldest file is greater than the file age before it will move the file to the destination folder.

=head1 AUTHOR

B<junifferallan.garcia@onsemi.com>

=head1 CHANGES

2034-April-19 - jgarcia - initial

=head1 LICENSE

(C) onsemi 2023 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Getopt::Long;
use PDF::Log;
use PPLOG::PPLogger;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename dirname fileparse/;
use File::Copy;
use PDF::DpLoad;

our $VERSION = "1.0";

# a hash to receive options
my %hOptions = ();
my $pplogger = new PPLOG::PPLogger();

unless (GetOptions( \%hOptions, "SOURCE=s", "DESTINATION=s", "FILEAGE=s", "LOGFILE=s", "PPLOG", "DEBUG", "TRACE", "V" )) {
    dpExit(1, "invalid options");
    pod2usage(3);
}

my @required_options = qw/SOURCE DESTINATION/;
if (grep { !exists $hOptions{$_} } @required_options) {
    pod2usage(3);
}

PDF::Log->init(\%hOptions, $pplogger);

if ($hOptions{PPLOG}) {
    $pplogger->settobeLog(1);
}

my $sourceFolder = $hOptions{SOURCE};
my $destination  = $hOptions{DESTINATION};
my $fileAge      = $hOptions{FILEAGE};

# Parse the file age to handle both days and hours
my ($age, $unit) = $fileAge =~ /(\d+)(\w*)/;
$unit = lc $unit;
if ($unit eq 'h') {
    $fileAge = $age * 3600; # Convert hours to seconds
} elsif ($unit eq 'd') {
    $fileAge = $age * 86400; # Convert days to seconds
} else {
    $fileAge = $age * 86400; # Assume days if no unit is provided
}

my $age_str = format_age($fileAge);

INFO("Source folder=$sourceFolder || Destination folder=$destination || File Age=$age_str");

move_files_by_age($sourceFolder, $destination, $fileAge);
# move_oldest_file($sourceFolder, $destination, $fileAge);

dpExit(0);