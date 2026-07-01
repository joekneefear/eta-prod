#!/usr/bin/env perl_db
# 04-Jul-2016 Eric	: create
# 
#use strict;
#use warnings;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long;
use PDF::Log;
use PDF::Parser::Stdf;
use PDF::Parser::Stdf::Generic;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);
use PDF::DpLoad;
use File::Copy;
use Time::Local;

my $tp_dir = "";
my $hold_dir = "";
my $result = GetOptions ("tpdir=s"   => \$tp_dir,
			 "hold_dir=s" => \$hold_dir);
if ($tp_dir eq "" || $hold_dir eq "")
{
        print "syntax:\n";
        print "\tscript -hold_dir=<dir_name> -tpdir=<dir_name>\n";
        dpExit(1);
}

# check if directories exists
chdir $tp_dir or die "Error - Please check that $tp_dir exists and is accessible.\n";
chdir $hold_dir or die "Error - Please check that $hold_dir exists and is accessible.\n";

my @files =  glob '*STDF';
my $status;

#foreach my $infile (glob "$tp_dir/*.TP") {
foreach my $infile (glob "$hold_dir/*.TP") {
	chomp($infile);
	my $new_file = $infile;
	my @fn = split /\./, $infile;
	my $txtfile = convertBinToAscii($infile);
        my $tpname = "";
        my $tprev = "";

        open FH, $txtfile or die "can't open $txtfile: $!\n";
        while(my $line = <FH>) {
                if ($line =~ /SPEC_NAM/) {
                        my @item = split /\=/, $line;
                        $tpname = cleanSTR($item[1]);
                }
                elsif ($line =~ /SPEC_REV/) {
                        my @item = split /\=/, $line;
                        $tprev = cleanSTR($item[1]);
                }
		last if ($tpname ne "" && $tprev ne "");
        }
        close (FH);

	$new_file = "${tp_dir}/${tpname}_REV_${tprev}\.STDF\.TP";
	system "mv $infile $new_file";
	$status = (-e "${tp_dir}/${tpname}_REV_${tprev}\.STDF\.TP") ? "Successful" : "Failed";

	print "Renaming $infile to $new_file - $status\n";

        unless (isLogDebug) {
            unlink $txtfile;
        }
#last;
}

sub cleanSTR
{
        my $str = shift;
           $str =~ s/^\s+|\s+$//g;
           $str =~ s/\,//g;
           $str =~ s/\s+/_/g;
        return($str);
}

dpExit(0);

