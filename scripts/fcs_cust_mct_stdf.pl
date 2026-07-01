#!/usr/bin/env perl_db
# 2015-Nov-10 Eric	: Initial release
# 2015-Nov-11 Eric	: Added status if file move was succesful or not
# 2016-Jul-04 Eric	: Move TD file to TD dir
# 2016-Jul-05 Eric	: Rename incoming TP files to "tpname_REV_tprev.STDF.TP"
# 2016-Sep-05 Eric	: Move file to correct directory base on PIR / EPDR records
# 2016-Oct-24 Rodney : Delete the text file immediately after reading and closing the file.
#                      Some TD files only contain bin summary (no PIR). 
# 2017-Apr-10 jgarcia: Make sure  to log if convertBinToAscii is not successfull.
# Function: Move file to correct directory according to file extension

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::Log;
use PDF::Parser::Stdf;
use PDF::Parser::Stdf::Generic;
use File::Basename qw/basename dirname/;
use List::Util qw(first);
use POSIX qw(strftime);
use PDF::DpLoad;
use File::Copy;
use PPLOG::PPLogger;
use PDF::DpLoad;
use PDF::DpData;

our $VERSION = "1.0";

# a hash to receive options
my (%hOptions) = ();

my $pplogger = new PPLOG::PPLogger();
my $header2 = new_headerLong->new();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions, "LOGFILE=s", "DEBUG", "TRACE", "V"
    )
    )
{
    dpExit( 1, "invalid options" );
}

if($hOptions{V})
{
        print("$VERSION\n");
        dpExit(0);
};
# Initialize logging

my @required_options = qw/ /;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions, $pplogger );

# check input file
my $infile = $ARGV[0];
if ( ! -f $infile ) {
    ERROR("$infile does not exist");
    pod2usage(3);
}
INFO ("Infile: $infile");
$pplogger->setRawFile($infile);
# Move file to correct directory based on file extension 
my $dir = dirname($infile);
my $move_file = basename($infile);
my @fn = split /\./, $move_file;
my $tp_dir = "${dir}/TP";
my $td_dir = "${dir}/TD";
my $tpname;
my $tprev;
my $chg_flg = 0;
my $tp_flg = "N";
my $td_flg = "N";
my $status;

my $lot = getLot($infile);
# covert and open stdf file
my $txtfile = convertBinToAscii($infile);
if($txtfile =~ /Failed to convert.+/i) {
  #$pplogger->setWaferFlag(1);
	$header2->LOT($lot);
	$header2->populateMeta();
	$pplogger->setLot($lot);
	$pplogger->setSourceLot($header2->SOURCE_LOT);
	$pplogger->setWafNum("00");
	dpExit(1, "$txtfile");
}
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
	elsif ($line =~ /EPDR\s+:/) {
		$tp_flg = "Y";	
		$chg_flg = 1;
	}
	elsif ($line =~ /PIR\s+:/) {
		$td_flg = "Y";
		$chg_flg = 1;
	}

	last if $chg_flg == 1;

}
close (FH);
unless (isLogDebug) {
	unlink $txtfile;
}

if ($tp_flg eq "Y") {
	system "/bin/cp -f \'${infile}\' ${tp_dir}/${tpname}_REV_${tprev}.${fn[1]}.TP";
	$status = (-e "${tp_dir}/${tpname}_REV_${tprev}.STDF.TP") ? "Successful" : "Failed";

	INFO ("TP file renamed to: ${tpname}_REV_${tprev}.STDF.TP");
	INFO ("Copying $infile to $tp_dir $status");
}
elsif ($td_flg eq "Y" || ($td_flg eq "N" && $tp_flg eq "N")) {
	if ($td_flg eq "N" && $tp_flg eq "N") {
		WARN("File has no EPDR or PIR recoreds; may only contain Bin Summary data.");
	}
	system "/bin/cp -f \'${infile}\' ${td_dir}/${move_file}";
        $status = (-e "${td_dir}/${move_file}") ? "Successful" : "Failed";	
	INFO ("Copying $infile to $td_dir $status");
}
else {
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

sub getLot() {
	my $file = shift;
	my $lotid;
	my $waferid;
	
	#my $script_name = "$ENV{STDF_SCRIPT}/stdf_copy ${file} | grep LOT_ID | tr '\n' ','; echo";
	my $script_name = "$Bin/stdf_perl/script/stdf_copy ${file} | grep LOT_ID | tr '\n' ','; echo";
  open FH, "$script_name|";
  my @ret = <FH>;
  close(FH);
  chomp($ret[0]);
  my ($item1, $item2) = split /\s*\,\s*/, $ret[0] if $ret[0] ne "";
  $item1 =~ s/^\s+|\s+$//g;
  my ($junk,$lot) = split /=/,$item1;
  
  $lotid = $lot;
  
  
	return ($lotid);
}
