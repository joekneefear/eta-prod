#!/usr/bin/env perl_db
=pod

=head1 SYNOPSIS

  fcs_shiba_ft_IFF.pl <Input flie name>
      --out <output dir>
      --loc <location e.g CP, SZ, ME>
      [--finallot]
      [--logfile <logfilepath>]
      [--debug|--trace]
      [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script>

=head1 AUTHOR

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

 2015-Nov-24 Eric	: new
 2016-Feb-16 wsanopao   : logging pre-processing information  to refdb.pp_log table.
 2016-Jul-07 Eric	: pass RELLOT arg for reliability data processing.
 2017-Apr-26 jgarcia    : check model->misc if states No bin reference and call dpExit. 
 2017-May-30 Gilbert    : generate limits always and dont register in refdb.pp_limits
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021-Apr-13 jgarcia	: get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
 2021-Apr-13 jgarcia : modified to not hardcode bin ref file but as arguments.

=head1 LICENSE

(C) Fairchild Semiconductor. 2015 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Getopt::Long;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Parser::Shiba;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao: 
use Config::Tiny;

our $VERSION = "

1.0
";
our $TESTER  = "SHIBA";

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "BINREFFILE=s", "OUT=s", "FORK=s", "FACILITYFILE=s", "LOC=s", "FINALLOT", "RELLOT", "LOGFILE=s", "DEBUG", "TRACE", "V","PPLOG" )
    )
{
    dpExit( 1, "invalid options" );
}

if($hOptions{V})
{
        print("$VERSION\n");
        dpExit(0);
};

my @required_options = qw/OUT LOC FACILITYFILE BINREFFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $facility = "";
if($hOptions{FINALLOT}) {
	$facility = $config->{$location}->{finalTest};
}else {
	$facility = $config->{$location}->{probe};
}

INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);
if ($hOptions{FINALLOT} && $hOptions{LOC} eq "SZ") {
	$pplogger->setEnv("szft_shiba");
}

if ( !-f $infile ) {
    pod2usage();
    dpExit( 1, "input file does not exist $infile" );
}


# check output dir
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK}, 
        basename => ( basename $infile),
        ext      => 'iff',
        gzipIFF  => 'Y'
    }
);

INFO("infile  = $infile");

# Peek into file and check if valid DLG
my $flag = "N";
my $scan_code_err_flag = 0;
open FH, $infile;
        while(my $line=<FH>)
        {
                chomp($line);
                $line =~ s/^\s+|\s+$//g;
		my (@dummy) = split /\s+/, $line;	
		# Capture test readings;
		if ($line =~ /Scan\s+Code\s+Error/i){
			$scan_code_err_flag = 1;
		}
		elsif ($dummy[0]=~/\d/ && $line=~/\s+Lo\s+/i && $line=~/\s+Hi\s+/i && $scan_code_err_flag==0){
                        $flag = "Y";
                        last;
                }
        }
close(FH);

if ($flag eq "N"){
        dpExit(1, "Not a valid DLG file");
}

my $parser = PDF::Parser::Shiba->new;
my $reglim_flg = "Y";
my $model = $parser->readFile($infile, $hOptions{RELLOT}, $hOptions{BINREFFILE}, isLogDebug);

&normalizeToBaseUnit($model);

my $header = $model->header;
   $header->isFinalLot($hOptions{FINALLOT});
   $header->isRelLot($hOptions{RELLOT});

unless ( $header->populateMeta ){
        $wr->noMeta(1);
        $reglim_flg = "N";
}
$header->VERSION($VERSION);
$header->EQUIP6_ID( $facility );
$header->PROGRAM_CLASS(2);

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);
if ($model->{misc} eq "No bin reference") {
	dpExit(1,"$model->{misc}");
}

my $program = $header->PROGRAM;
if ( length($program) > 35 )
{
        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
        $wr->forSBox(1);
        $reglim_flg = "N";
        $program = substr($program, 1, 35); # Leave enough room for session type
}

$header->PROGRAM($program);
$model->updateProgram;

my $formatter = new_iff_formatter(
        {   model  => $model,
            writer => $wr
        }
);

$formatter->dataItems([qw/site x y soft_bin hard_bin partid/]);
$formatter->testItems([qw/number name units/]);
$formatter->binItems ([qw/number name PF count/]);
$formatter->printPar;

#Limits
#if ($reglim_flg eq "Y") {
#        if ($model->isLimitNew){
#		$model->buildLimit;
#        	$formatter->printLimit;
#	        $model->limit->registerRefdb;
#        }
#}
#else {  #always generate but do not register limit if sandbox
        $model->buildLimit;
        $formatter->printLimit;
        $model->limit->input_file(basename $infile);
#}
dpExit(0);

sub getLot() {
	my $file = shift;
	my $lotid;
	my $line;
	
	
	open FH, $file or die "can't open $infile\n";
	while($line=<FH>)
	{
		chomp($line);
		$line =~ s/^\s+|\s+$//g;
		my (@dummy) = split /\s+/, $line;
		if ($dummy[0] =~ /LOT/i && $dummy[2] =~ /NAME/i && $lotid eq ""){
			$lotid = trim($dummy[1]);
			#$tp_name = trim($dummy[3]);
			
			# check if data is a retest
			if ($lotid =~ /REJ/i || $infile =~ /REJ/i) {
				$lotid =~ s/REJ//i;
				#$tp_name = $tp_name."_"."R";	
			}
			 last;
		}
	}
	close FH;
	
	return $lotid;
		
}
