#!/usr/bin/env perl_db
# SVN $Id: fcs_bstdf_et_IFF.pl 2592 2020-10-06 07:03:16Z dpower $

=pod

=head1 SYNOPSIS

  fcs_bstdf_et_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
      --loc <location>
      --tpDIR <TP location>
      [--logfile <logfilepath>]  
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read BSTDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

2015/11/04 Eric 	: new 
2015/11/10 Eric 	: if next test is SAME and is 0.0, set limit to -1e12 and 1e12
                	: if next test is not SAME, compare the upper and lower limits of the current test and swap them if needed
2015/11/19 Eric 	: always generate but do not register limit if sandbox
2015/11/23 jgarcia	: Added TYPE param to indicate if Process or Product info to be added in Program.
2016/02/16 wsanopao	: logging pre-processing information  to refdb.pp_log table.
2017/03/29 jgarcia 	: added trapping if Stdf raw file is not well-formed and log it to pp_log.
		 	readStdfAscii will now return error message if Stdf is not well-formed.
2017/04/28 eric		: assign sourece lot as wafer name
2017-May-10 gilbert     : generate limits always and dont register in refdb.
2020/09/01 karen        : added support to fork and qde output (IFF)/files to designated location
2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

=head1 LICENSE

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
use Tie::File;
use PPLOG::PPLogger; 	# wsanopao: 
use Config::Tiny;

our $VERSION = "

1.0
";
our $TESTER  = "BSTDF";

# a hash to receive options
my (%hOptions) = ();

# wsanopao: Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions,  "OUT=s", "FACILITYFILE=s", "FORK=s", "LOC=s", "TPDIR=s", "TYPE=s",
        "LOGFILE=s", "DEBUG", "TRACE", "V", "PPLOG", "QDE"
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
my @required_options = qw/OUT LOC TPDIR TYPE FACILITYFILE/;

my $tpDir = $hOptions{TPDIR};
my $reglim_flg = "Y";

pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $location = $hOptions{LOC};
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");


# check input file
my $infile = $ARGV[0];
if ( ! -f $infile ) {
    ERROR("$infile does not exist");
    pod2usage(3);
}

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);
if ($hOptions{LOC} =~ /BK/i) {
	$pplogger->setEnv("bket_hp");
}

# create Writer
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   basename => ( basename $infile),
        ext      => 'iff',
        outdir   =>  $hOptions{OUT},
	forkdir => $hOptions{FORK},
	qde => $hOptions{QDE},
	gzipIFF  => 'Y'
    }
);
my $header2 = new_headerLong->new();
# create Parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $perl = "perl";

my ( $TP_bin, $TD_bin , $TP_txt,  $TD_txt, %bin_TP);

my ($errLot, $errWafer) = &getLot($infile);
my $waferNumber = "";
#print "LOT=$errLot||WAFER=$errWafer\n"; exit 0;
if ($errLot eq "NO_LOTID") {
	$pplogger->setWaferFlag(1);
	$pplogger->setLot($errLot);
	#$header2->LOT($errLot);
	#$header2->populateMeta();
	#$pplogger->setLot($errLot);
	#$pplogger->setSourceLot($header2->SOURCE_LOT);
	$pplogger->setWafNum($errWafer);
	dpExit( 1, "BAD FILE - NO LOTID");
}
if ($errWafer eq "") {
	$pplogger->setWaferFlag(1);
	$pplogger->setLot($errLot);
	$header2->LOT($errLot);
  	$header2->populateMeta();
  	$pplogger->setLot($errLot);
  	$pplogger->setSourceLot($header2->SOURCE_LOT);
	$pplogger->setWafNum($errWafer);
	dpExit( 1, "BAD FILE - NO WAFERID");
}

# Convert source file to TD
my $command = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_hp_bstdf_bket.pl -infile=$infile";
INFO("$command ");
my @output = `$command`;
if ($?) {
    	print "error in $command\n";
    	$pplogger->setWaferFlag(1);
    	$header2->LOT($errLot);
    	$header2->populateMeta();
    	$pplogger->setLot($errLot);
    	$pplogger->setSourceLot($header2->SOURCE_LOT);
	$pplogger->setWafNum($errWafer);
    	dpExit( 1, "Failed to convert $command : $!" );
}
if ( $output[-1] =~ /td=(.*)/ ) {
    	$TD_bin = $1;
    	$TD_bin =~ s/\s+//;	
    	INFO("TD = $TD_bin");	
}
else {
	$pplogger->setWaferFlag(1);
    	$header2->LOT($errLot);
    	$header2->populateMeta();
    	$pplogger->setLot($errLot);
    	$pplogger->setSourceLot($header2->SOURCE_LOT);
	$pplogger->setWafNum($errWafer);
    	dpExit( 1, "Failed to convert $command : " . join( "#", @output ) );
}

$TD_txt = convertBinToAscii($TD_bin);
if($TD_txt =~ /Failed to convert.+/i) {
  	$pplogger->setWaferFlag(1);
	$header2->LOT($errLot);
	$header2->populateMeta();
	$pplogger->setLot($errLot);
	$pplogger->setSourceLot($header2->SOURCE_LOT);
	$pplogger->setWafNum($errWafer);
	dpExit(1, "$TD_txt");
}
INFO("TD_TXT = $TD_txt");
my $td = readStdfAscii($TD_txt);
if ($td =~ /NO_.+/i) {
	$pplogger->setWaferFlag(1);
	$header2->LOT($errLot);
  	$header2->populateMeta();
  	$pplogger->setLot($errLot);
  	$pplogger->setSourceLot($header2->SOURCE_LOT);
	$pplogger->setWafNum($errWafer);
  	dpExit( 1, "$td" );
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

my $model = new_model(
   {
	dataSource => 'BSTDF',
   }
);


$header->EQUIP6_ID( $facility);

$model->header($header);

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);
#$pplogger->{_WAF_NUM} = $errWafer;

my $program = $header->PROGRAM;
if (length($program) > 35) {
        INFO("PROGRAM NAME \"".$program."\" will be truncated to 35 characters. Sending to sandbox.");
        $wr->forSBox(1);
	$reglim_flg = "N";
        $program = substr($program, 1, 35); #leave room for session type
}
$header->PROGRAM($program);
$header->PROGRAM_CLASS(5);

my $tests = getTestsFromTP($model,$tpDir, $TD_txt);

$model->updateProgram($hOptions{TYPE});

foreach my $stdfWafer ( @{ $td->wafers } ) {
    	my $wafer = new_wafer;
    	$wafer->START_TIME( $header->START_TIME );
    	$wafer->END_TIME( $header->END_TIME );
    	my $waferNum = -1;
    	if ( defined $stdfWafer->WIR ) {
        	$waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
        	$waferNumber = $waferNum;
        	$wafer->number($waferNum);
		#assign source lot as wafer name
		if ($header->SOURCE_LOT ne "") {
			$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
			$pplogger->setWaferFlag(1);
		}
        	if ( defined $stdfWafer->WIR->{START_T} and $stdfWafer->WIR->{START_T} > 1000000000 )
        	{
            		$wafer->START_TIME( $stdfWafer->WIR->{START_T} );
        	}
        	if ( defined $stdfWafer->WRR->{FINISH_T} and $stdfWafer->WRR->{FINITSH_T} > 1000000000 )
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
    	if($wsbins ne ""){
		$wafer->sbins($wsbins);		
    	}		
    	if ( @{ $stdfWafer->WHBR } ) {
		$whbins = $parser->hbr2bins( $stdfWafer->WHBR, $good_count );			        
    	}
    	if($whbins ne ""){
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
#  		$model->buildLimit;
#  		$model->limit->tests($tests);
#  		$formatter->printLimit;
#  		$model->limit->input_file(basename $infile); 
#  		$model->limit->registerRefdb;
#	}
#}
#else {  # always generate but do not register limit
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
		}
		else{
			$hbins = $parser->hbr2bins( $bin, $g_cnt );
		}	
  	}
  	elsif(@$bin_each > 0)
  	{	
		if($mode eq "sbr"){
			$sbins = $parser->sbr2bins( $bin_each, $good_count );
		}
		else{
			$hbins = $parser->hbr2bins( $bin_each, $good_count );
		}
  	}
}

sub getTestsFromTP{
  	my $model = shift;
  	my $tpDir = shift;
  	my $TD_txt_inTemp = shift;
  	my $program = $model->header->PROGRAM;
  	my $rev = $model->header->REVISION;
  

  	my $regexp = "${program}_${rev}.*\.TXT";
  	INFO( "TP file search pattern : $regexp");
  	my $TP = undef;
  	foreach my $file (glob "$tpDir/*.TXT"){
    		if ($file =~ /$regexp/i){
       			INFO("TP Found : $file");
       			$TP = $file;
    		}
		last if (defined $TP);
  	}
 
  	unless (defined $TP ) {  
    		unlink $TD_txt_inTemp unless (isLogDebug);
    		#$pplogger->setSourceLot($header->SOURCE_LOT);
    		$pplogger->setWaferFlag(1);
    		$pplogger->setWafNum($errWafer);
    		dpExit(4,"No TP found in $tpDir by pattern $regexp");
  	} 

  	return readTestsFile( $TP );
    
}

sub readTestsFile {
    	my $infile = shift;
    	tie my @file, 'Tie::File', $infile or die $!;
    	my $tests_ary;
    	my $test;
    	for my $linenr (0 .. $#file) {
		next if $linenr == 0;
		$test = new_test;
        	my @items = split /\:/, $file[$linenr];
	   	$items[1] =~ s/^_//g;
           	$items[1] =~ s/^\s//g;
	   	$items[1] =~ s/_/-/g;

           	$test->number(trim($items[0]));
 	   	$test->name(trim($items[1]));
	   	$test->desc(trim($items[2]));
	   	$test->units(trim($items[3]));
	   	$test->LOL(trim($items[6]));
	   	$test->HOL(trim($items[7]));
           	trim($items[4]);
	   	trim($items[5]);
	   	# Check if next test eq SAME
	   	if ($file[$linenr + 1] !~ /SAME/ && $file[$linenr] !~ /SAME/ && $linenr <= $#file) {
	       		if ($items[4] > $items[5]){
                       		$test->LSL($items[5]);
                       		$test->HSL($items[4]);
               		}
               		else {
               	        	$test->LSL($items[4]);
                       		$test->HSL($items[5]);
              	 	}			
	   	}	
	   	else {
	       		$items[4] = ($items[4] =~ /^0\.0*/) ? -1e12 : $items[4];
	       		$items[5] = ($items[5] =~ /^0\.0*/) ? 1e12 : $items[5];
               		$test->LSL($items[4]);
               		$test->HSL($items[5]);
	   	}
	   	push @$tests_ary, $test;		
    	}	
    	untie @file;
    	return $tests_ary;
}

sub RemoveMultibyte
{
    	my $test_desc = shift;
    	my $i;
    	my $temp='';
    	my $temp2 ='';
    	my @Array;
    	my $arr;
    	my $toprint;
    	my $hex;
    	my $dec;
    	for($i=0;$i < length($test_desc) ;$i++)
    	{
         	$arr =  sprintf "0x%x,", ord(substr($test_desc,$i,1));
         	$temp2 = $temp2.$arr;
    	}

    	@Array = split(/,/, $temp2);
    	for($i=0;$i< scalar(@Array)-1 ;$i++)
    	{
        	if($Array[$i] ge "0xa1" && $Array[$i] le "0xfe")
        	{
        		if($Array[$i+1] ge "0xa1" && $Array[$i] le "0xfe")
        		{
        			$Array[$i] = '';
                		$Array[$i+1] = '';
                		$i++;
         		}
        	}
    	}
    	$test_desc = '';
    	for($i=0;$i< scalar(@Array) - 1;$i++)
    	{
       		$hex  =  hex($Array[$i]);
       		$test_desc = $test_desc.chr($hex);
    	}
}

dpExit(0);

sub getLot() {
	
	my $file = shift;
	
	# Get lot from filename
	my $fn     = basename($file);
	my @item   = split /\_/, $fn;
	my $fn_lot = $item[3];
	my $fn_wafer;
  	my ($str, $lot_id, $lot_len, $tmp_lot, $tmp_str, $i, $tmp);
  
  	for (my $i = 0; $i <= $#item; $i++) {
  	 	if ($item[$i] =~ /^W\d{2}$/ || $item[$i] =~ /^\d{2}$/) {
  	 		$fn_wafer = $item[$i];
  	 		$fn_wafer =~ s/W//g;
  	 	}
  	}

	open(FLE,"$file");
	#  read FLE,$str,1;
	#  read FLE,$str,1;
	#  read FLE,$str,4;
	#  read FLE,$str,4;
	#  read FLE,$str,4;
	#  read FLE,$str,4;
	#  read FLE,$str,1;
	#  read FLE,$str,1;
	#  read FLE,$str,2;
	#  read FLE,$str,2;
	#  read FLE,$str,1;
	read FLE,$str,25;
  	read FLE,$str,20;

  	$lot_id  = unpack("A20",$str);
  	close(FLE);
  	if ($lot_id eq "") {
  		#print "NOT LOTID INSIDE THE FILE INDICATED=$lot_id\n";
  		#$fn_wafer = $item[3];
		#$fn_wafer =~ s/\W//g;
  		return ("NO_LOTID", $fn_wafer);
  	}
  	$lot_len = length($lot_id);
   	$tmp_lot = "";
    	for($i=0; $i<$lot_len; $i++) {
       		$tmp_str = substr($lot_id,$i,1);
       		$tmp = ord($tmp_str);

       		if( ($tmp >= 48 && $tmp <= 57 ) || ($tmp >= 65 && $tmp <= 90) || ($tmp >= 97 && $tmp <= 122) )
       		{
          		$tmp_lot .= $tmp_str;
          		$tmp_lot =~ s/\s+//g;
       		}
    	}
    	$lot_id = $tmp_lot;
	#print "l=$lot_id\tf=$fn_lot\n";
	# Assign lotid from fname if blank
	#$lot_id = $fn_lot if $lot_id eq "";
	#print "LOT=$lot_id||WAFER=$fn_wafer\n";
	return($lot_id, $fn_wafer);
}
