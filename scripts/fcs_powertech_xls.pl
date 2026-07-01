#!/usr/bin/env perl_db
# 01-Sep-2015  Saed    - Created

=pod

=head1 SYNOPSIS

  fcs_static_log.pl <Input flie name>
	--out <output dir>
	--temp <unzip dir>
        --facilityfile <$DPSCRIPT/facilityMapping.ini>
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]
=head1 DESCRIPTIONS

=head1 AUTHOR

B<saed.hasan@pdf.com>

=head1 CHANGES

 2015/08/19 saed : new creation
 2015/09/18 eric : truncate ppid if > 35, use updateProgram method.
		 : use populateMeta method instead of GetMetaByLot
 2015/10/20 eric : removed default revision
 2015/11/19 eric : always generate but do not register limit if sandbox
 2016/03/02 wsanopao: logging pre-processing information  to refdb.pp_log table.
 2017/03/27 eric : notify engr's if no ptx file found.
 30-May-2017 gilbert : generate limits always and dont register in refdb.pp_limits
 2020/09/01 karen       : added support to fork output (IFF)/files to designated location
 2021/04/16 glory        : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

 
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
use PDF::DAO;
use PDF::Parser::powertech_xls;
use PDF::Formatter;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use Time::localtime;
#use POSIX qw(strftime);
use File::stat;
use Time::Piece;
use PPLOG::PPLogger; 	# wsanopao:
use Config::Tiny;


our $VERSION = "1.0";
our $TESTER  = "QTEC";
my %missingLot=();
my %lothashes=();

my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUT=s", "FORK=s", "TPDIR=s" , "TEMP=s", "FINALLOT", "LOGFILE=s", "DEBUG", 
		"TRACE", "V", "LOC=s", "FACILITYFILE=s", "PPLOG", "SITE=s", "NOTIFY" )
    )
{
    dpExit( 1, "invalid options" );
}
 
if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};

my @required_options = qw/OUT LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $facility = $config->{$location}->{finalTest};
INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);

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

my $parser = PDF::Parser::powertech_xls->new;
#my $temp = $hOptions{TEMP};
my $reglim_flg = "Y";

if($infile =~ /gz$/)
{
	my $command = "gunzip $infile";
	my $ret = system($command);	
}
else
{
		INFO("Test Program directory: ".$hOptions{TPDIR});
		my $model = $parser->readFile($infile, $hOptions{TPDIR}, isLogDebug);
		my $misc  = $model->misc;
		
		#&normalizeToBaseUnit($model);

		my $header = $model->header;
		$header->isFinalLot($hOptions{FINALLOT});
		$header->VERSION($VERSION);
		$header->PROGRAM_CLASS(2);
		$header->EQUIP6_ID($facility);
		$header->EQUIP1_ID( "PTS-4000" );
		#$header->REVISION("1.0");
		
		# wsanopao: Passing Reference of Model
		$pplogger->setModelHeader($model);
		
		#my ($source_lot,$product) = GetMetaByLot($header->LOT);			
		unless ( $header->populateMeta ){
			$wr->noMeta(1);
			$reglim_flg = "N";
		}

		# trap errors parsing
		if ($misc->{err_msg} == 4) {
			my $subj = "$hOptions{SITE}: Missing PTX file - $header->{PROGRAM}";
        		my $to   = `head -1 /data/gem_cn_ft_qtec/PTX/mail_list.txt`;

			if ($to ne "" && $hOptions{NOTIFY}) {
				&send_email($infile,$header->PROGRAM,$subj,$to);
			}
			else {
				WARN ("Distri list not found.");
			}
			dpExit(4,"Missing PTX file: $header->{PROGRAM}");	
		}
		
		
		my $source_lot = $header->SOURCE_LOT;
                my $product = $header->PRODUCT;
		if ($source_lot eq "N/A" || $source_lot eq "" ){ $source_lot = $header->LOT};
		if ($product eq "N/A" || $product eq ""){ $product = $header->PROGRAM};
		$header->SOURCE_LOT($source_lot);			
		$header->PRODUCT($product);			
		
		my $program = $header->PROGRAM;
		if (length($program) > 35) {
			INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
        		$wr->forSBox(1);
			$reglim_flg = "N";
        		$program = substr($program, 1, 35);	
		}
		$header->PROGRAM($program);
		$model->updateProgram;

		my $wafer = $model->find('wafers',{number => 0});	
		
		unless (defined $wafer){
			$wafer = new_wafer( { number => 0 } );
			$model->add('wafers',$wafer);		
		}	
	
		my $creationtime = localtime( stat($infile)->ctime )->strftime("%Y/%m/%d %H:%M:%S");

		$wafer->START_TIME( $creationtime);
		$wafer->END_TIME( $creationtime);

		
		if (!($hOptions{FINALLOT})) {
			my $wmap = $model->updateWMap;
			unless ( ! $wmap->isEmpty ){
				$wr->wmapIsEmpty(1);
				$reglim_flg = "N";
			}
			unless ( $wmap->confirmed ){
				$wr->noWMap(1);
				$reglim_flg = "N";
			}
		}
		
		
		
		my $formatter = new_iff_formatter(
			{   model  => $model,
			    writer => $wr
			}
		);
		
		$formatter->dataItems([qw/partid site hard_bin soft_bin/]);
		$formatter->testItems([qw/number name units /]);
		$formatter->binItems ([qw/number name PF /]);
		$formatter->printPar;

		# Output Limit
		#if ($reglim_flg eq "Y") {
		#	if ($model->isLimitNew){
		#    		$model->buildLimit;
		#    		$formatter->printLimit;
		#    		$model->limit->registerRefdb;
		#	}			
		#}
		#else {  # always generate but do not register limit if sandbox
			$model->buildLimit;
			$formatter->printLimit;
		#}
}
	
##############################################################################
# Subroutine: GetMetaByLot
##############################################################################
sub GetMetaByLot{
	my $lot=shift();
	my $hash=undef;
	if(defined($missingLot{$lot})){
		return ("N/A","N/A","N/A");
	}
	if(defined($lothashes{$lot})){
		$hash = $lothashes{$lot};
	}else{
		if($hOptions{FINALLOT}){
			$hash = getRefdb->getMetaDataFinalLot($lot);
		}else{
			$hash = getRefdb->getMetaData($lot);
		}
		if(keys %$hash > 0){
			$lothashes{$lot}=$hash;
		}else{
			WARN("Bad.. Meta Not Found for Lot = ".$lot);
			$missingLot{$lot}=1;
			return ("N/A","N/A","N/A");
		}
	}
	return ($hash->{source_lot},$hash->{product});
}

sub send_email {
	my $file = shift;
	my $prog = shift;
	my $subj = shift;
	my $to	 = shift;
	my $fn   = basename $file;

	open(MAIL, "|mutt -s \"$subj\" $to");
       		print MAIL "Please load the corresponding PTX for the ff file:\n" ;
		print MAIL "$fn\n";
       	close(MAIL);		
}

dpExit(0);
