#!/usr/bin/env perl_db
# SVN $Id: fcs_fet_ft_IFF.pl 2632 2020-10-09 03:01:40Z dpower $

=pod

=head1 SYNOPSIS

  fcs_fet_ft_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
      --TPDIR <
      --loc <location e.g CP, SZ, ME>
      --config <cfg_tester_type>
      [--finallot]
      [--logfile <logfilepath>]  
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script will read STDF file (Binary) and write to stdf like text file>

=head1 AUTHOR

B<jason.arp@pdf.com>

=head1 CHANGES

2015/06/22 jason 	: new
2015/07/17 grace 	: set product from the lot lookup in pp_lot. Removed FT_ from program
2015/08/04 eric  	: use ppid naming rule email from Rodney 
	           	: The conv_fet_dat_cpft.pl script uses the program as the product. 
		   	: The FET parser should overwrite it with the product found from the lot lookup in pp_lot
		   	: The conv_fet_dat_cpft.pl script adds the prefix "FT_" to the program name. 
		   	: The converter can be changed to not do this or the FET parser should strip this from the program name.
2015/11/19 eric    	: always generate but do not register limit if sandbox
2016/02/01 wsanopao	: logging pre-processing information  to refdb.pp_log table.			
2016/07/06 gilbert 	: Adjust for reliability data
2016/08/10 eric		: use rellot arg to extract rel info. 
2017/03/07 eric 	: fail and do not create iff if no test param and results
2017/03/22 eric 	: removed residue files (TD/txt) if no result or parameters
2017/04/25 jgarcia 	: enhance pp script logging.
2017/05/29 gilbert	: generate limits always and dont register in refdb.pp_limits
2018/01/12 eric		: parse onrms datalog
2020/09/01 karen        : added support to fork output (IFF)/files to designated location
2021/04/07 karen	: get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::Parser::Stdf;
use PDF::Parser::Stdf::Generic;
use PDF::Formatter;
use PDF::DpWriter;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger; 	# wsanopao: 
use Number::Range;
use Config::Tiny;

our $VERSION = "1.0";
our $TESTER  = "FET";

# a hash to receive options
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $PPlogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    	pod2usage(3);
}
unless (
    	GetOptions(
       	 	\%hOptions,  "OUT=s", "FORK=s", "FACILITYFILE=s", "LOGFILE=s", "DEBUG", "TRACE", "V", "TPDIR=s", 
		"TYPE=s", "FINALLOT", "LOC=s",  "CONFIG=s", "PPLOG", "RELLOT", "SITE=s"))
{
   	dpExit( 1, "invalid options" );
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};
# Initialize logging

my @required_options = qw/OUT LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});

my $location     = $hOptions{LOC};
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");
my $cfg_tstr_typ = $hOptions{CONFIG};
my $site	 = $hOptions{SITE};

# check input file
my $infile = $ARGV[0];
if ( ! -f $infile ) {
    	ERROR("$infile does not exist");
    	pod2usage(3);
}

# wsanopao: Set Raw File ==> infile
$PPlogger->setRawFile($infile);

# create Writer
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   basename => ( basename $infile),
        ext      => 'iff',
        outdir   =>  $hOptions{OUT},
	forkdir => $hOptions{FORK},
        gzipIFF  => 'Y'
    }
);

# create Parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $perl = "perl";
my $reglim_flg = "Y";
my ( $TP_bin, $TD_bin );

# Convert source file to TD
my $command;
my $command2;

INFO("type : ". $hOptions{TYPE});

my $errLot = "";
if($hOptions{TYPE} eq "FT"){
	$errLot = getLot($infile);
	INFO("LOT=$errLot"); 
	$command = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_fet_dat_cpft.pl -infile=$infile";
}elsif($hOptions{TYPE} eq "SORT"){
	$command = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_fet_cpr_slsort.pl -infile=$infile";
}elsif($hOptions{TYPE} eq "REL"){
	$command = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_fet_dat_cpft.pl -infile=$infile -plant=REL";
}

INFO("$command ");
my @output = `$command`;
if ($?) {
    #print "error in $command\n";
    $PPlogger->setLot($errLot);
    if ($hOptions{TYPE} eq "FT") {
    	$PPlogger->setWafNum("00");
    }
    dpExit( 1, "Failed to convert $command : $!" );
}
if ( $output[-1] =~ /td=(.*)/ ) {
    $TD_bin = $1;
    INFO("TD=$TD_bin");
}
else {
	  $PPlogger->setLot($errLot);
    if ($hOptions{TYPE} eq "FT") {
    	$PPlogger->setWafNum("00");
    }
    dpExit( 1, "Failed to convert $command : " . join( "#", @output ) );
}

my $TD_txt = convertBinToAscii($TD_bin);
if($TD_txt =~ /Failed to convert.+/i) {
	$PPlogger->setLot($errLot);
	if ($hOptions{TYPE} eq "FT") {
		#$pplogger->setWaferFlag(1);
 		#$header2->LOT($lotid);
 		#$header2->populateMeta();
		
		#$pplogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum("00");
	}
 
	dpExit(1, "$TD_txt");
}
my $td     = readStdfAscii($TD_txt);
if($td =~ /NO_.+/i) {
	$PPlogger->setLot($errLot);
	if ($hOptions{TYPE} eq "FT") {
		#$header2->LOT($errLot);
		#$header2->populateMeta();
		#$PPlogger->setWaferFlag(1);
		#$PPlogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum("00");
	}
	
  dpExit(1, "$td");
}
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());
my $header = new_headerLong->new( $parser->stdf2header($td) );
my $orig_prod = $header->PRODUCT;
   $header->isFinalLot($hOptions{FINALLOT});
   $header->isRelLot($hOptions{RELLOT});

unless ( $header->populateMeta ) {
    $wr->noMeta(1);
    $reglim_flg = "N";
}
$header->CFG_TESTER_TYPE($cfg_tstr_typ);
$header->EQUIP6_ID( "$facility" );
$header->PROGRAM_CLASS(2);

# find the corresponding PRN file
my $TP_path = $hOptions{TPDIR};
my $regexp = $orig_prod.".*\.PRN";

my $PRN = undef;
foreach my $file (glob "$TP_path/*.PRN"){
  if ($file =~ /$regexp/i){
     INFO("PRN Found : $file");
     $PRN = $file;
  }
}

unless (defined $PRN ) {  
    unless (isLogDebug) {
    unlink $TD_bin;
    unlink $TD_txt;
	}
	 	$PPlogger->setLot($errLot);
    if ($hOptions{TYPE} eq "FT") {
    	$PPlogger->setWafNum("00");
    }
    dpExit(1,"No PRN found in $TP_path by pattern $regexp");
} 

if($hOptions{TYPE} eq "REL"){
   $command2 = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_fet_prn_cprel.pl -infile=$PRN";
}
else {
  $command2 = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_fet_prn_cpft.pl -infile=$PRN";
}

INFO("$command2 ");
my @output2 = `$command2`;
if ($?) {
    #print "error in $command2\n";
    $PPlogger->setLot($errLot);
    if ($hOptions{TYPE} eq "FT") {
    	$PPlogger->setWafNum("00");
    }
    dpExit( 1, "Failed to convert $command2 : $!" );
}
if ( $output2[-1] =~ /tp=(.*)/ ) {
    $TP_bin = $1;
    INFO("TP=$TP_bin");
}
else {
		$PPlogger->setLot($errLot);
    if ($hOptions{TYPE} eq "FT") {
    	$PPlogger->setWafNum("00");
    }
    dpExit( 1, "Failed to convert $command2 : " . join( "#", @output2 ) );
}

my $TP_txt = convertBinToAscii($TP_bin);
if($TP_txt =~ /Failed to convert.+/i) {
	$PPlogger->setLot($errLot);
	if ($hOptions{TYPE} eq "FT") {
		#$pplogger->setWaferFlag(1);
 		#$header2->LOT($lotid);
 		#$header2->populateMeta();
		
		#$pplogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum("00");
	}
 
	dpExit(1, "$TP_txt");
}
INFO($TP_txt);
my $tp     = readStdfAscii($TP_txt);
if($tp =~ /NO_.+/i) {
	$PPlogger->setLot($errLot);
	if ($hOptions{TYPE} eq "FT") {
		#$header2->LOT($errLot);
		#$header2->populateMeta();
		#$PPlogger->setWaferFlag(1);
		#$PPlogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum("00");
	}
	
  dpExit(1, "$tp");
}
my $tests  = $parser->epdr2tests( $tp->EPDR );


my $sbr = $td->SBR;
my $sbr_each = $td->SBR_each;

if(@$sbr > 0)
{
	$sbins = $parser->sbr2bins( $td->SBR );
}
elsif($sbr_each > 0)
{	
	$sbins = $parser->sbr2bins( $td->SBR_each );
}

my $hbr = $td->HBR;
my $hbr_each = $td->HBR_each;

if(@$hbr > 0)
{
	$hbins = $parser->hbr2bins( $td->HBR );
}
elsif($sbr_each > 0)
{	
	$hbins = $parser->hbr2bins( $td->HBR_each );
}

my $sbinsTP = $parser->epdr2bins( $tp->EPDR );
my $hbinsTP = $parser->epdr2hbins( $tp->EPDR );
mergeBins($sbins,$sbinsTP);
mergeBins($hbins,$hbinsTP);


my $testCond = [qw/PIN_1 PIN_2 PIN_3 SBIN_NUM HBIN_NUM
        VCC VEE TEMP FREQ PARMTYPE SEQ_NAME
        TCONDS SBIN_NAM HBIN_NAM TEST_TXT
        LOAD_VAL TEST_CAT VIEW_ORD /];
$parser->testConditions_EPDR( $testCond);

foreach my $test(@$tests){
  	my @pins ; 
  	push @pins, (shift @{$test->conditions});
  	push @pins, (shift @{$test->conditions});
  	push @pins, (shift @{$test->conditions});
  	unshift @{$test->conditions},join(" ",@pins);
}
shift @$testCond; 
shift @$testCond; 
shift @$testCond; 
unshift @$testCond,qw/TestNumber TestName Units PINS/;

my $model = new_model({dataSource => 'FET'});

$model->header($header);

INFO("original product:".$header->PRODUCT);
INFO("original program :".$header->PROGRAM);

if ($hOptions{RELLOT}){
        my $base_fn = basename($infile);
           $base_fn =~ s/\.DAT.*+//ig;
        my @item    = split /\_/, $base_fn;
	my $qpnum;
	my $devchar;
	my $lotchar;
        my $strname = $item[1];
        my $strdur  = $item[2];
        my $temp    = $item[3];
        my $dtype   = $item[4];

	if ($item[0] =~ /^20/) {  #fsc rel
		$qpnum   = substr $item[0],  0, 8;
		$devchar = substr $item[0], -2, 1;
		$lotchar = substr $item[0], -1, 1;
		$header->LOT(uc($qpnum.$devchar.$lotchar));
	}
	elsif ($item[0] =~ /^F/i){   #cprel_fet onrms
		$qpnum   = substr $item[0],  0, 6;
		$lotchar = substr $item[0], -1, 1;
		$header->LOT(uc($qpnum.$lotchar));
	}

        my $range = Number::Range->new("0..1000000");
        if ( $range->inrange($strdur) && $strdur !~ /\D/) {
                #do nothing
        }
        else {
                WARN ("Stress Duration not in range =  $strdur");
                $strdur = "";
                $wr->forSBox(1);
		$reglim_flg = "N";
        }
        my $range = Number::Range->new("-1000000..1000000");
        if ( $range->inrange($temp) && $temp !~ /\D/) {
                #do nothing
        }
        else {
                WARN ("ATETemp not in range = $temp");
                $temp = "";
                $wr->forSBox(1);
		$reglim_flg = "N";
        }
	
	$header->INDEX1($strname."_".$strdur."_".$temp."_".$dtype);

        my $rel = new_rel;
        $rel->qpnumber($qpnum);
        $rel->devchar($devchar);
        $rel->lotchar($lotchar);
        $rel->strname($strname);
        $rel->strduration($strdur);
        $rel->atetemp($temp);
        $rel->datalogtype($dtype);
        $model->add('rels', $rel);
}

$header->PRODUCT("");
#####  The conv_fet_dat_cpft.pl script uses the program as the product.  The FET parser should overwrite it with the product found from the lot lookup in pp_lot.
unless ($header->populateMeta){
	ERROR("cannot populate Meta data from refdb by lot id: ".$header->LOT);
};
my $program = $header->PROGRAM;
$program =~ s/FT\_//;

if (length($program) > 35) {
	INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters.  Sending to sandbox.");
	$wr->forSBox(1);
	$reglim_flg = "N";
	$program = substr($program, 1, 35);
}
$header->PROGRAM($program);

INFO("product:".$header->PRODUCT);
INFO("program:".$header->PROGRAM);

$model->updateProgram;

# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);

#my $wmap = $model->updateWMap;
#unless ( $wmap->confirmed ) {
#    $wr->noWMap(1);
#}

foreach my $stdfWafer ( @{ $td->wafers } ) {
    my $wafer = new_wafer;
    $wafer->START_TIME( $header->START_TIME );
    $wafer->END_TIME( $header->END_TIME );
    my $waferNum = -1;
    if ( defined $stdfWafer->WIR ) {
        $waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
        $wafer->number($waferNum);
        if ( defined $stdfWafer->WIR->{START_T}
            and $stdfWafer->WIR->{START_T} > 1000000000 )
        {
            $wafer->START_TIME( $stdfWafer->WIR->{START_T} );
        }
        if ( defined $stdfWafer->WRR->{FINISH_T}
            and $stdfWafer->WRR->{FINITSH_T} > 1000000000 )
        {
            $wafer->END_TIME( $stdfWafer->WRR->{FINISH_T} );
        }
    }
	 
    $wafer->tests($tests);
    $wafer->dies( $parser->res2dies( $stdfWafer->res, $tests ) );
    $model->add( 'wafers', $wafer );

}

$model->sbins($sbins);
$model->hbins($hbins);

# fail and do no create iff
my $stats = $model->wafers->[0]->stats;
if ( $stats->{deviceCount} == 0 ){
	unless (isLogDebug) {
    		unlink $TD_bin;
    		unlink $TD_txt;
    		unlink $TP_bin;
    		unlink $TP_txt;
	}
        dpExit( 1, "Zero devices to create IFF (".$stats->{deviceCount}.")");
}
if ( ! (@{$model->wafers->[0]->tests})) {
	unless (isLogDebug) {
                unlink $TD_bin;
                unlink $TD_txt;
                unlink $TP_bin;
                unlink $TP_txt;
        }
        dpExit(1, "Test Parameters not found.");
}

&normalizeToBaseUnit($model);
	
my $formatter = new_iff_formatter({
        model=>$model,
        writer => $wr});
$formatter->dataItems([qw/x y site partid hard_bin soft_bin/]);
$formatter->relItems([qw/qpnumber devchar lotchar strname strduration atetemp datalogtype/]);
$formatter->printPar;


# Limits
#if ($reglim_flg eq "Y") {
#	if($model->isLimitNew){
#  		$model->buildLimit;
#  		$model->limit->conditionNames($testCond);
#  		$formatter->printLimit;
#  		$model->limit->input_file(basename $infile); 
#  		$model->limit->registerRefdb;
#	}
#}
#else {   # always generate but do not register limit if sandbox
	$model->buildLimit;
	$model->limit->conditionNames($testCond);
	$formatter->printLimit;
	$model->limit->input_file(basename $infile);
#}

unless (isLogDebug) {
    unlink $TD_bin;
    unlink $TD_txt;
    unlink $TP_bin;
    unlink $TP_txt;
}

sub mergeBins{
  my $bins = shift;
  my $binsTP = shift;
  my %binName;
  for my $bin (@$binsTP) {
    $binName{ $bin->number } = $bin->name;
  }
  for my $bin (@$bins) {
    $bin->name( $binName{ $bin->number } );	
  }
}

dpExit(0);


sub getLot() {
	my $file = shift;
	my $in;
	my $data_rem;
	open(INPUT,"$file") || die "Could not open $file\n";
	###############
  # PARSE HEADER
  ###############

	### DATA FILE 'D' ###
	read INPUT, $in, 1;
	#$data_file = unpack "a", $in;
	#print"DATA_FILE=>$data_file\n";

	### 9400 DATA FILE ###
	read INPUT, $in, 1;
	#$version = unpack "a", $in;
	#print"VERSION=>$version\n";

	
	### START SN ###
	read INPUT, $in, 1;
  #$sn_bit1 = unpack "b8", $in;
  read INPUT, $in, 1;
  #$sn_bit2 = unpack "b8", $in;
  #$bit = join "",$sn_bit1,$sn_bit2;
  #$start_sn = unpack "s", (pack "b16", $bit);
        #print "STAR SN: $start_sn\n";
	

	### END SN ###
	read INPUT, $in, 1;
  #$bit1 = unpack "b8", $in;
	read INPUT, $in, 1;
  #$bit2 = unpack "b8", $in;
	#$bit = join "",$bit1,$bit2;
	#$end_sn = unpack "s", (pack "b16", $bit);
	#print "END SN: $end_sn\n";

	### NUMBER OF SERIAL PER 1536 BYTES ###
	read INPUT, $in, 1;
	#$sn_per_rec = unpack "c", $in;
	#print"# of SN / 1536 bytes=>$sn_per_rec\n";

	### NUMBER OF SN's ###
	#$SN_cnt = ($end_sn - $start_sn) + 1;

	### SN SIZE ###
	read INPUT, $in, 1;
	#$snsize_bit1 = unpack "b8", $in;
	read INPUT, $in, 1;
	#$snsize_bit2 = unpack "b8", $in;
	#$snsize_bytes = join "", $snsize_bit1, $snsize_bit2;
	#$SN_size = unpack "s", (pack "b16", $snsize_bytes);
	#print"SN SIZE=>$SN_size\n";

		### ABORT IF SN SIZE IS ZERO ###
		#if ($SN_size < 1)
		#{
			#print "file doesn't contain test data.\ndir=no_part_data";
      #          	&move_file_to_bad_dir($file, "$ENV{ENV_CONV_BAD}/no_data") if $mft_flag==0;
      #          	exit 100;
		#}
	
		#$die_per_record    = int (1536 / $SN_size);
		#$skip_padded_bytes = 1536 - ($die_per_record * $SN_size);
		#$to_be_skipped_bytes = 1536 - ($sn_per_rec * $SN_size);
		

		#print "SN SIZE $SN_size\n";
		#print "DIE/REC $die_per_record\n";
		#print "PADDED BYTES: $skip_padded_bytes\n";
		#print "TO BE SKIPPED BYTES: $to_be_skipped_bytes\n";


	### READ OUT TEST #'s USED IN DL ###
        for(my $ii = 1; $ii <= 32; $ii++)
        {
                read INPUT, $in, 1;
                #$TEST_NUM = unpack "c", $in;
		#print"TEST_NUM=>$TEST_NUM\n";
        }

	### READ OUT BYTES IN TEST NUMBERS ###
#        read INPUT, $in, 32;
#        $_cnts = unpack "c32", $in;


	### FCN #'s ###
        read INPUT, $in, 32;
#       $fcn_cnts = unpack "c32", $in;
	#print "FCN #'s: $fcn_cnts\n";


	### DATA FILE REMARKS = DEVICEID & TESTERNO ###
	read INPUT, $in, 1; ### UNWANTED CHAR
	read INPUT, $in, 39;
	$data_rem = unpack "a39", $in;
	$data_rem =~ s/^\s*|\s*$//g;
	$data_rem = uc($data_rem);
	my ($dierun, $testerno, $correct_lotid, $badgeid, $handler) = split /\s+/, $data_rem;
	#$dierun        =~ s/[^A-Z0-9\_\-]//ig;
	#$testerno      =~ s/[^0-9\/\-\_]//g;
	$correct_lotid =~ s/[^A-Z0-9\_\-]//g;	
	#$badgeid       =~ s/\D//g;
	#$handler       =~ s/\D//g;
	close INPUT;
	return $correct_lotid;
}
