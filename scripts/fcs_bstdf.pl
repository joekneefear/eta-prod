#!/usr/bin/env perl_db
# SVN $Id: fcs_bstdf.pl 29 2015-03-24 00:38:41Z dpower $
=pod

=head1 SYNOPSIS

  fcs_bstdf.pl <Input flie name>
      [--out <output dir>]  same dir as input file by default
      [--temp <temporary dir for intermediate files>]  ouput_dir/temp by default
      [--logfile <logfilepath>]  
      [--debug|--trace]

=head1 DESCRIPTIONS

B<This script> will read BSTDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

2015/03/09 kazukik: Modify to use standard Meta Lookup format to standard

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut
use strict;
use FindBin;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long  qw/:config ignore_case auto_help/;
use PDF::Log;
use PDF::DpLoad;
use PDF::FCS_Common qw/getMetaString/;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);

# a hash to receive options
my (%hOptions)= (
	"TEMP" => undef,
	"OUT" => undef,
        "META" => undef,
        "WMAP" => undef,
	"DEBUG"  => undef,
	"HELP" => undef
);
# Read arguments
if ($#ARGV < 0) {
    pod2usage(3);
}
unless(GetOptions(\%hOptions, 
	"OUT=s", 
	"TEMP=s",
	"LOGFILE=s",
	"META",
	"WMAP",
	"DEBUG",
	"TRACE"))
{
  dpExit(1,"invalid options");
}
 # Initialize logging
PDF::Log->init(\%hOptions);

# check input file
my $infile  = $ARGV[0];
if (! -f $infile) {
     pod2usage(3);
}

# check output dir
validateOutDir(\%hOptions);
my $outdir=$hOptions{OUT};
#
my $temp = $hOptions{TEMP};

#
#my $perl = "perl_db";
my $perl = "perl";
my $DPSCRIPT = $ENV{'DPSCRIPT'};

 	my ($TP, $TD);
	# Convert source file to TP and TD
	my $command = "$perl -I$DPSCRIPT/stdf_perl/lib $DPSCRIPT/stdf_perl/conv_bstdf_bksort.pl -infile=$infile";
      	print "$command \n";
      	my @output = `$command`;
	if ($?) {
		print "error in $command\n";
		dpExit(1,"Failed to convert $command : $!");
	}
	if ($output[-1] =~ /td=(.*) tp=(.*)/) {
		$TD = $1;
		$TP = $2;	
		print "TD=$TD\n";
		print "TP=$TP\n";
	} else {
		dpExit(1,"Failed to convert $command : ".join("#",@output));
	}

	# Convert TD to ascii format
	$command = "$perl -Ilib $DPSCRIPT/stdf_perl/script/stdf_copy $TD > $TD.txt ";
	my $ret = system($command);
	print "$command \n ret = $ret \n";
	if ($ret) {
		print "error in $command\n";
		DpLoad_exit(1,"Failed to convert $command : $!");
	}
	# Convert TP to ascii format
	$command = "$perl -Ilib $DPSCRIPT/stdf_perl/script/stdf_copy $TP > $TP.txt ";
	my $ret = system($command);
	print "$command \n ret = $ret \n";
	if ($ret) {
		print "error in $command\n";
		DpLoad_exit(1,"Failed to convert $command : $!");
	}
	
	# Read TP in hash
	my @keywords = qw/TEST_NUM UNITS LO_LIMIT HI_LIMIT LO_CENSR HI_CENSR SBIN_NUM HBIN_NUM VCC VEE TEMP FREQ TEST_NAM SBIN_NAM HBIN_NAM TEST_TXT LOAD_VAL/;

	my $TPMap = {};
	my %epdr;
	my $test_num;
	open (FH,"TP.txt");
	while (<FH>){
		if (/EPDR :/){
			%epdr = ();
		        undef $test_num;	
		}
		if (/^\s+TEST_NUM=(.*)/){
			$test_num = $1;
		}
		foreach my $word (@keywords){
			if (/^\s+$word=(.*)/){
				$epdr{$word} = $1;
			}
		}
		#if (/OPT_FLAG=(.+)/ and not(exists($epdr{test_nam}))){
		#	s/TEST_TXT/TEST_NAM/;
		#	$epdr{test_nam} = $_;
		#}
		if (/^\s*$/){
			if (defined($test_num)){
				my %epdr_copy = %epdr; $TPMap->{$test_num}= \%epdr_copy;
			}
		}
	}
	close FH;
	
	## merge TP into TD
	my @strOut ;
	my $lot_id;
	open (IN, "$TD.txt");
	while (<IN>){
                s/\t//;
                s/\t/  /;
		if (/START_T=(.\d+)/){ #hm
                        my $timeS = strftime("%Y/%m/%d %H:%M:%S",localtime($1));
                        push @strOut ,"  START_T=$timeS\n";
		}elsif (/FINISH_T=(.\d+)/){
                        my $timeS = strftime("%Y/%m/%d %H:%M:%S",localtime($1));
                        push @strOut ,"  FINISH_T=$timeS\n";
		}else{ 
                        push @strOut ,$_;
		}
		if (/^\s+LOT_ID=(.*)/){
			$lot_id = $1;
		}
	}
	close IN;

        # get Meta data
        my $meta = getMetaString($lot_id);
	DEBUG("Meta = $meta");
	if (length($meta) < 20 ) {
	    if (defined($hOptions{META}) and defined($hOptions{OUT})){
               $outdir = $hOptions{OUT}."_noMeta";
            }
	}	
        my $outfile =  $outdir."/".(basename $infile).".merged";
	INFO("outfile = $outfile");
        open (OUT, ">","$outfile");
        print OUT $meta;
        print OUT "<BOTP>\n";
	foreach my $word (@keywords){
		print OUT $word ; 
		foreach my $test_num(sort keys(%{$TPMap})){
			print OUT ",".$TPMap->{$test_num}->{$word};
		}
		print OUT "\n" ; 
	}
	print OUT "<EOTP>\n";
	foreach (@strOut){
		print OUT;
	}
	close OUT;
        unless (PDF::Log->isLogDebug){
		INFO("remove temporaly files");
		unlink $TD or DpLoad_exit(1,"Failed to remove $TD") ;
		unlink $TP or DpLoad_exit(1,"Failed to remove $TP") ;
		unlink "$TD.txt" or DpLoad_exit(1,"Failed to remove $TD.txt") ;
		unlink "$TP.txt" or DpLoad_exit(1,"Failed to remove $TP.txt") ;
	}
dpExit(0);

