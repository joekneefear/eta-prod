#!/usr/bin/env perl_db

=pod

=head1 SYNOPSIS

  fcs_autov_IFF.pl <Input flie name>
	--out <output dir>
        --temp <unzip dir>	
	--facilityfile <$DPSCRIPT/facilityMapping.ini>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will gunzip *.gz and get 4 csv file and generate IFF file for dbascii

=head1 AUTHOR

B<sungsuk.moon@pdf.com>

=head1 CHANGES

 2015/06/18 grace : new creation
 2015/07/20 grace : changed following 
	          : get from "Operator ID" field in the Summary sheet 
		  : get from pp_lot lookup, otherwise use value in "Device Name" field in the Summary sheet.
		    Added prefix to test name
 2015/08/20 jgarcia : added support to accept LOCATION as arg and support to add AREA on Program name if data processed is from CP,PM, SZ
 2015/08/26 jgarcia : removed "INS-INS-" in the Program name.
 2015/08/26 jgarcia : modified to truncate Program and load to sandbox if greater than 45 chars instead of 35 chars.
 2015/08/26 jgarcia : do not include area in counting total length of Program.
 2015/09/17 eric    : accept site argument to pick up correct lot for subcon/foundry
 2016/01/29 wsanopao: logging pre-processing information  to refdb.pp_log table.
 2017/03/13 eric    : changed object from printPar to printPar_v5 to fix the
		      Number of wafers exceeded the maximum allowed wafers per lot which is <128>
 2017/05/02 eric    : do not create iff if errors found
 2020/09/01 karen   : added support to fork output (IFF)/files to designated location
 2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
 2025/05/06 eric	: modified to handle both old and new magazine format
 

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

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
use PDF::Parser::AUTOV;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny; 

our $VERSION = "

1.0
";
our $TESTER  = "AV";

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

my $area = "";

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "CONFIG=s", "LOC=s", "FACILITYFILE=s", "FINALLOT", "OUT=s", "FORK=s", "TEMP=s", "LOGFILE=s", "DEBUG", "TRACE", "V", "SITE=s", "PPLOG" )
    )
{
    dpExit( 1, "invalid options" );
}
 
if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT TEMP LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);

my $config = Config::Tiny->read($hOptions{FACILITYFILE});

if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $site = $hOptions{SITE};
if($hOptions{LOC} =~ /CP|PM|SZ|GTK_TW/ ) {
			$area = "::AST";
}
my $location = $hOptions{LOC};

my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];
INFO("Infile = $infile");
if ( !-f $infile ) {
    pod2usage();
    dpExit( 1, "input file does not exist $infile" );
}

# wsanopao: Set Raw File ==> infile
$PPlogger->setRawFile($infile);

# check output dir
INFO("Fork dir = $hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUT},
        forkdir => $hOptions{FORK}, 
        basename => ( basename $infile),
        ext      => 'iff',
        gzipIFF  => 'Y'
    }
);


my $parser = PDF::Parser::AUTOV->new;
my $temp = $hOptions{TEMP};


if($infile =~ /gz$/)
{
	my $command = "gunzip $infile";
	my $ret = system($command);	
}
else{

	my $command = "unzip -o $infile -d $temp";
	my $ret = system($command);
	
	if($ret eq 0)
	{
		my $model = $parser->readFile($temp, isLogDebug);
		my $misc = $model->misc;
		
		&normalizeToBaseUnit($model);
		
		
		my $header = $model->header;
		$header->isFinalLot($hOptions{FINALLOT});
		$header->VERSION($VERSION);
		$header->PROGRAM_CLASS(1);
		$header->EQUIP6_ID( "$facility" );
		$header->CFG_TESTER_TYPE( $hOptions{CONFIG} );
		
		# wsanopao: Passing Reference of Model
		$PPlogger->setModelHeader($model);
		
		if ($site eq "gtk_tw_ast") {
		    my $tmp_lot = $header->LOT;
		    my ($lot, @dump) = split /\_/, $tmp_lot;
		    $header->LOT($lot);
		}

		$wr->noMeta(1) unless ( $header->populateMeta );
		
		my $program = $header->PROGRAM;
		#if($hOptions{LOC} =~ /CP/) {
		$program =~ s/^INS_INS-//g;
		#}
		
		if ( length($program) > 45 ){		
			
			INFO("PROGRAM NAME \"".$program."\" will be truncated to 45 characters.  Sending to sandbox.");
		  $wr->forSBox(1);
		  $program = substr($program, 1, 45); # Leave enough room for session type
		        		
		}
		
		$program = $program.$area;
		
		$header->PROGRAM($program);
	
  		$model->updateProgram;
		
		#trap errors
		if ($misc->{err_msg} ne "") {
			dpExit ($misc->{err_cod}, "$misc->{err_msg}");
		}	
 	
		my $formatter = new_iff_formatter(
		{   model  => $model,
				writer => $wr
		}
		);
		
		my $sbins = $parser->getbins( );
			
		$model->sbins($sbins);
			
		$formatter->dataItems([qw/soft_bin partid x y/]);
		$formatter->testItems([qw/number name units/]);
		#$formatter->printPar;
		$formatter->printPar_v5;
		
	}

}

dpExit(0);
  
  
sub getLimitTest
{
	my $test_name = shift;
	my $limit = shift;
	my $value = shift;
	my %new_test;
	foreach my $test (@$limit){
	
		if(trim($test->name) eq trim($test_name))
		{
			if($value eq "number"){
			
				return $test->number;
			}
			elsif($value eq "units"){
				return $test->units;
			}
			
		}
	}

}

dpExit(0);
