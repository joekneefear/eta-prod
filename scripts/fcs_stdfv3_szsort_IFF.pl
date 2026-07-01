#!/usr/bin/env perl_db
# SVN $Id: fcs_stdfv3_szsort_IFF.pl 2582 2020-10-06 01:43:05Z dpower $

=pod

=head1 SYNOPSIS

  fcs_stdf3_szsort_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
      --loc <location>
      --config <config_tester_type>
	  --tpDIR <TP location>
      [--logfile <logfilepath>]  
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read STDFV3 file (Binary) and write to stdf like text file

=head1 AUTHOR

B<sungsuk.moon@pdf.com>

=head1 CHANGES

2015/09/04 grace : new 
2015/10/29 eric  : truncate ppid if > 35, corrected regex in searching test program
2015/11/19 eric  : always generate but do not register limit if sandbox
2016/02/26 wsanopao: logging pre-processing information  to refdb.pp_log table.
2017/03/20 eric  : assign source lot as wafer name
2017/03/22 eric  : set wafer flag for pplogging
2017/03/28 jgarcia: try to get the lot and wafer from the file which to be used 
										in pp_logging if converting the raw stdfV3 file to asccii is not successful.
2017/04/24 jgarcia: modified to support pp_logging even if issues encountered in converting binary to ascii format.
2017/04/24 jgarcia: modified to support pp_logging when generated an malformed stdf ascii derrived from binary.
2017/04/27 jgarcia: fix bug on getting lot and wafer for stdfv3.
2017-May-30 gilbert : generate limits always and dont register in refdb.pp_limits
2020/09/01 karen       : added support to fork output (IFF)/files to designated location
2021/04/07 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

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
use Config::Tiny;

our $VERSION = "

1.0
";
our $TESTER  = "Stdf3";

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
        	\%hOptions,  "OUT=s", "FORK=s", "LOC=s", "FACILITYFILE=s", "CONFIG=s", "TPDIR=s",
        	"LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG"
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

my @required_options = qw/OUT LOC TPDIR CONFIG FACILITYFILE/;

my $tpDir = $hOptions{TPDIR};

pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $location = $hOptions{LOC};
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");

# check input file
my $infile = $ARGV[0];

my @dummy = split("/", $hOptions{LOC});
my $site = $dummy[1];

# wsanopao: Set Raw File ==> infile 
$PPlogger->setRawFile($infile);
#$PPlogger->setWaferFlag(1);

my $header2 = new_headerLong->new();

my $lot = &getLot($infile);
my $wafer = &getWafer($infile);
#print "=====LOT=$lot||WAFER=$wafer\n"; exit;


if ( ! -f $infile ) {
    	ERROR("$infile does not exist");
    	pod2usage(3);
}

# create Writer
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    	{   	basename => ( basename $infile),
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
my ( $TP_bin, $TD_bin , $TP_txt,  $TD_txt, %bin_TP);

# Convert source file to TD
my $command  = "$perl -I/export/home/dpower/project/scripts/stdf_perl/lib /export/home/dpower/project/scripts/stdf_perl/conv_sz_std_mtsort.pl -infile=$infile -env_mod=/export/home/dpower/project/scripts/stdf_perl/env_mod_mtsort_sz.pm";
INFO("$command ");
my @output = `$command`;
if ($?) {
    	#print "error in $command\n";
    	$PPlogger->setLot($lot);
    	if ($site =~ /sort/) {
    		$PPlogger->setWaferFlag(1);
    		$header2->LOT($lot);
    		$header2->populateMeta();
    		$PPlogger->setSourceLot($header2->SOURCE_LOT);
	  		$PPlogger->setWafNum($wafer);
    	} else {
    		$PPlogger->setWafNum("00");
    	}
    	dpExit( 1, "Failed to convert $command : $!" );
}
if ( $output[-1] =~ /td=(.*)/ ) {
    	$TD_bin = $1;
    	INFO("TD=$TD_bin");	
}
else {
			$PPlogger->setLot($lot);
    	if ($site =~ /sort/) {
    		$PPlogger->setWaferFlag(1);
    		$header2->LOT($lot);
    		$header2->populateMeta();
    		$PPlogger->setSourceLot($header2->SOURCE_LOT);
	  		$PPlogger->setWafNum($wafer);
    	} else {
    		$PPlogger->setWafNum("00");
    	}
    	dpExit( 1, "Failed to convert $command : " . join( "#", @output ) );
}

$TD_txt = convertBinToAscii($TD_bin);
if($TD_txt =~ /Failed to convert.+/i) {
	$PPlogger->setLot($lot);
	if ($site =~ /sort/) {
		$PPlogger->setWaferFlag(1);
		$header2->LOT($lot);
		$header2->populateMeta();
		$PPlogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum($wafer);
	} else {
		$PPlogger->setWafNum("00");
	}
 	dpExit(1, "$TD_txt");
}
my $td  = readStdfAscii($TD_txt);
if ($td =~ /NO_.+/i) {
	$PPlogger->setLot($lot);
	if ($site =~ /sort/) {
		$PPlogger->setWaferFlag(1);
		$header2->LOT($lot);
		$header2->populateMeta();
		$PPlogger->setSourceLot($header2->SOURCE_LOT);
		$PPlogger->setWafNum($wafer);
	} else {
		$PPlogger->setWafNum("00");
	}
 	dpExit(1, "$td");		
}
my $good_count;
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());
my $header = new_headerLong->new( $parser->stdf2header($td) );

unless ( $header->populateMeta ) {
    	$wr->noMeta(1);
    	$reglim_flg = "N";
}

my $sbins;
my $hbins;

getBinSummary($td->SBR, $td->SBR_each, $good_count, 'sbr');

my $model = new_model({dataSource => 'SZ'});

$header->EQUIP3_ID($td->EMIR->{PRB_CARD});
$header->EQUIP6_ID( $facility );
$header->CFG_TESTER_TYPE( $hOptions{CONFIG} );

$model->header($header);

my $program = $header->PROGRAM;

# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);

if (length($program) > 35) {
        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters. Sending to sandbox.");
        $wr->forSBox(1);
	$reglim_flg = "N";
        $program = substr($program, 1, 35); #leave room for session type
}
$header->PROGRAM($program);
$header->PROGRAM_CLASS(1);

my $tests = getTestsFromTP($model,$tpDir, $TD_txt);

my $wmap = $model->updateWMap;

if(defined $wmap)   {
	unless ( $wmap->confirmed ) {
		$wr->noWMap(1);
		$reglim_flg = "N";
	}
}
else{
	$wmap = new_wmap;	
	$wr->noWMap(1);
	$reglim_flg = "N";
	$model->wmap($wmap);	
}

$model->updateProgram("MAP_PGM");

foreach my $stdfWafer ( @{ $td->wafers } ) {
    	my $wafer = new_wafer;
    	$wafer->START_TIME( $header->START_TIME );
    	$wafer->END_TIME( $header->END_TIME );
    	my $waferNum = -1;
    	if ( defined $stdfWafer->WIR ) {
        	$waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
        	$wafer->number($waferNum);
		# assign source lot as wafer id
		if ($header->SOURCE_LOT ne "") {
                        $wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
			$PPlogger->setWaferFlag(1);
                }
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
		
		if(defined $stdfWafer->WRR->{GOOD_CNT})
		{
			$good_count =  $stdfWafer->WRR->{GOOD_CNT};
		}		
    	}	

	if ( @{ $stdfWafer->WSBR } ) {
		$wsbins = $parser->sbr2bins( $stdfWafer->WSBR, $good_count );			        
	}
		
	if($wsbins ne "")
	{
		$wafer->sbins($wsbins);		
	}	
		
	if ( @{ $stdfWafer->WHBR } ) {
		$whbins = $parser->hbr2bins( $stdfWafer->WHBR, $good_count );			        
	}
		
	if($whbins ne "")
	{
		$wafer->hbins($whbins);		
	}	

    	$wafer->tests($tests);
    	$wafer->dies( $parser->res2dies( $stdfWafer->res, $tests ) );
    	$model->add( 'wafers', $wafer );
}


if($good_count eq "" or $good_count == 0)
{
	$good_count = $td->MRR->{GOOD_CNT};
}


if ($wsbins eq ""){
	getBinSummary($td->SBR, $td->SBR_each, $good_count, 'sbr');
	$model->sbins($sbins);
}

if ($whbins eq ""){
	getBinSummary($td->HBR, $td->HBR_each, $good_count, 'hbr');
	$model->hbins($hbins);
}

my $formatter = new_iff_formatter({
        model=>$model,
        writer => $wr});
$formatter->dataItems([qw/x y site partid hard_bin soft_bin/]);
$formatter->printPar;

# Limits
&normalizeToBaseUnit($model);
#if ($reglim_flg eq "Y") {
#	if($model->isLimitNew){
#		  $model->buildLimit;
#		  $model->limit->tests($tests);
#		  $formatter->printLimit;
#		  $model->limit->input_file(basename $infile); 
#		  $model->limit->registerRefdb;
#	}
#}
#else { # always generate but do not register limit if sandbox
	$model->buildLimit;
	$model->limit->tests($tests);
	$formatter->printLimit;
	$model->limit->input_file(basename $infile);
#}

unless (isLogDebug) {
    	unlink $TD_bin;
    	unlink $TD_txt;
    	unlink $TP_bin;
    	unlink $TP_txt;
}

sub getBinSummary{
  	my $bin = shift;
  	my $bin_each = shift;
  	my $g_cnt = shift;
  	my $mode = shift;
  	my $bins;
  
  	if(@$bin > 0)
  	{
		if($mode eq "sbr"){
			$sbins = $parser->sbr2bins( $bin, $g_cnt );
		}else{
			$hbins = $parser->hbr2bins( $bin, $g_cnt );
		}	
  	}
  	elsif(@$bin_each > 0)
  	{	
		if($mode eq "sbr"){
			$sbins = $parser->sbr2bins( $bin_each, $good_count );
		}else{
			$hbins = $parser->hbr2bins( $bin_each, $good_count );
		}
  	}
}

##############
sub getTestsFromTP{
  	my $model = shift;
  	my $tpDir = shift;
  	my $TD_txt_inTemp = shift;
  	my $program = $model->header->PROGRAM;
  	my $rev = $model->header->REVISION;
  	my $regexp = "${program}_${rev}.*\.TPL";
  	INFO( "TP file search pattern : $regexp");
  	my $TP = undef;

  	foreach my $file (glob "$tpDir/*.TPL"){
    		if ($file =~ /$regexp/i){
       			INFO("TP Found : $file");
       			$TP = $file;
    		}
  	}
 
  	unless (defined $TP ) {  
		unlink $TD_txt_inTemp unless (isLogDebug);
		
        	dpExit(4,"No TP found in $tpDir by pattern $regexp");
  	} 

	return readTestsFile( $TP );
    
}

sub readTestsFile {
    	my $infile = shift;
    	my $tests_ary;
    	my $num = 0;
	my @items = ();
    	if ( $infile =~ /\.TPL/ ) {
       		my $test;
       		open( INFILE, $infile );
       		while (<INFILE>) {
           		s/[\r\n]+\z//;
           		$num++;
		   	@items = split(/\,/, $_);
		   
		   	if(trim($items[0]) ne "Test Num")
		   	{
				$test = new_test;
				$test->number(trim($items[0]));             
				$test->name(trim($items[1]));
				$test->LSL(trim($items[2]));
				$test->HSL(trim($items[3]));
				$test->LOL(trim($items[4]));
				$test->HOL(trim($items[5]));
				$test->units(trim($items[6]));	

				$bin_TP{$items[10]} = $items[9];
			  
				push @$tests_ary, $test;
		  	}
	   	}
       	}  
       	close(INFILE);
    
    	return $tests_ary;
}

dpExit(0);

sub getLot() {
	my $file = shift;
	my ($lot, $wafer);
	my ($rec_len, $rec_typ, $rec_sub, $in);
	my %MIR = ();
	my %WIR = ();
	my $readFlag = 1;
	my $cpu_type = "";
  my  $lot_id   = "";
  my  $size     = "";
  my  $temp_in  = "";
  my  $tot_size = "";
  my %mir  = ();
  my ($rec_len, $in);
  my $wafer_id;

	    
	open(EP, $file);
	while($readFlag == 1) {
		$rec_len = 0;
		read EP, $in, 2;
	   $rec_len = unpack ("n", $in);
	   #print "=RECLEN=$rec_len\n";
		################### REC TYPE ##########################
		$rec_typ = 0;
		read EP, $in, 1;
		$rec_typ = unpack("C", $in);
		#print "RECTYP=$rec_typ\n";
		################### REC SUB ###########################
		$rec_sub = 0;
		read EP, $in, 1;
		$rec_sub = unpack("C", $in);
		#print "RECSUB=$rec_sub\n";
		if ($rec_typ == 1) {
			if ($rec_sub == 10)	{
				read EP, $temp_in, $rec_len;
        $in = substr($temp_in, 0, 1);
        #$cpu_type = unpack("C", $in);
        $in = substr($temp_in, 1, 1);
        #$stdf_ver = unpack("C", $in);
        $in = substr($temp_in, 2, 1);
        #$mode_cod = unpack("C", $in);
        $in = substr($temp_in, 3, 1);
        #$stat_num = unpack("C", $in);
        $in = substr($temp_in, 4, 3);
        #$test_cod = unpack("C3", $in);
        $in = substr($temp_in, 7, 1);
        #$rtst_cod = unpack("C", $in);
        $in = substr($temp_in, 8, 1);
        #$prot_cod = unpack("C", $in);
        $in = substr($temp_in, 9, 1);
        #$cmod_cod = unpack("C", $in);
        $in = substr($temp_in, 10, 4);
        #$setup_t = unpack("N", $in);
        $in = substr($temp_in, 14, 4);
        #$start_t= unpack("N", $in);
        $in = substr($temp_in, 18, 1);
        $size = unpack("C", $in);
        $lot_id = substr($temp_in, 19, $size);
        $tot_size = $size;
        $lot_id =~ s/ +$// ; # remove trailing spaces
        #print "LOT=$lot_id\n";
			}
			last;
		}
		
	}
	close EP;
	
	$lot = $lot_id;
	#$wafer = $wafer_id;
	return($lot);
}

sub getWafer() {
	my $file = shift;
	my ($wafer);
	my ($rec_len, $rec_typ, $rec_sub, $in);
	my %MIR = ();
	my %WIR = ();
	my $readFlag = 1;
	my $cpu_type = "";
  my  $size     = "";
  my  $temp_in  = "";
  my  $tot_size = "";
	my %mir  = ();
	my ($rec_len, $in);
	my $wafer_id;
	    
	open(EP, $file);
	while($readFlag == 1) {
		$rec_len = 0;
		read EP, $in, 2;
	   $rec_len = unpack ("n", $in);
	   #print "=RECLEN=$rec_len\n";
		################### REC TYPE ##########################
		$rec_typ = 0;
		read EP, $in, 1;
		$rec_typ = unpack("C", $in);
		#print "RECTYP=$rec_typ\n";
		################### REC SUB ###########################
		$rec_sub = 0;
		read EP, $in, 1;
		$rec_sub = unpack("C", $in);
		#print "RECSUB=$rec_sub\n";
		if ($rec_typ == 2){
	   		if ($rec_sub == 10){
	        read EP, $temp_in, $rec_len;

	        $in = substr($temp_in, 0, 1);
	        #$head_num = unpack("C", $in);
	        $in = substr($temp_in, 1, 1);
	        #$pad_byte = unpack("B8", $in);
	        $in = substr($temp_in, 2, 4);
	        #$start_t = unpack("N", $in);
	        $in = substr($temp_in, 6, 1);
	        $size = unpack("C", $in);
	        $wafer_id = substr($temp_in, 7, $size);
	        $wafer_id =~ s/ +$// ; # remove trailing spaces
	        #print "WAFER=$wafer_id\n";
        	$readFlag = 0;
        	last;
				}
				
		}
		
	}
	close EP;
	
	#$lot = $lot_id;
	$wafer = $wafer_id;
	return($wafer);
}

