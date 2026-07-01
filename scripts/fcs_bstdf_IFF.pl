#!/usr/bin/env perl_db
# SVN $Id: fcs_bstdf_IFF.pl 2587 2020-10-06 05:48:26Z dpower $

=pod

=head1 SYNOPSIS

  	fcs_bstdf_IFF.pl <Input flie name>
      		--out <output dir>  output direcotry must exist
      		--loc <location e.g. CP,BK,ME>
      		--config<config_tester_type>
      		[--logfile <logfilepath>]  
      		[--debug|--trace]
      		[--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read BSTDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

2015/03/09 kazukik  : Modify to use standard Meta Lookup format to standard
2015/05/29 grace    : Added support for -v option.
2015/07/02 eric     : added LOC arg and pass it as EQUIP6_ID
2015/07/03 eric	    : applied new program naming rule.
2015/07/09 gilbert  : move the call to updateProgram to after the call to updateWMap and 
                    : add wmapIsEmpty function
2015/07/14 gilbert  : Truncate the test program name to 35 characters and send to sandbox if test program 
                    : name is truncated and set the header PROGRAM_CLASS
2015/09/07 eric     : Modified script cater Final Test
2015/09/30 gilbert  : gunzip incoming file.
2015/10/21 eric	    : do not parse waferid for final test.
2015/11/19 eric     : always generate but do not register limit if sandbox
2015/12/16 jgarcia  : modified to try to matched for metadata where lotid last char is stripped. 
		    : this is done after it failed on the first metadata check with NO Stripping to lotid.
2015/12/16 jgarcia  : added metastrip as an argument.
2016/02/16 wsanopao : logging pre-processing information  to refdb.pp_log table.
2017/03/13 gilbertm : Always generate limits and dont register to refdb.
2017/03/21 eric     : assign source lot as wafer name
2017/03/22 eric     : set waferflag to 1
2017/03/23 jgarcia  : trap, call dpExit method for bstdf files with no lotid instead trying to convert to TD and TP.
2019/08/09 eric	    : added nosandbox option. its purpose was not to move the file to sandbox when envoked.
2020/06/22 eric	    : pass mrr->good_cnt to sbr2bins and hbr2bins to determine pass bin.
2020/09/01 karen    : added support to fork output (IFF)/files to designated location
2021/03/25 jgarcia : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.
2023/09/27 eric	    : perform BK lot lookups by stripping characters


=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
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
#use v5.024;

our $VERSION = "1.0";
our $TESTER  = "BStdf";

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
        	\%hOptions,  "OUT=s", "FORK=s", "LOC=s", "FACILITYFILE=s", "CONFIG=s", "FINALLOT",
        	"LOGFILE=s", "DEBUG", "TRACE", "V", "METASTRIP", "PPLOG", "NOSANDBOX"
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

my @required_options = qw/OUT LOC FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
my $reglim_flg = "Y";
my $facility = "";
if($hOptions{FINALLOT}) {
	$facility = $config->{$location}->{finalTest};
} else {
 $facility = $config->{$location}->{probe};
}
INFO("FACILITY|EQUIP6_ID=$facility");

# check input file
my $infile = $ARGV[0];
my $site = "";

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);
if ($location =~ /BK/i) {
	$site = "bksort_bstdf";
	$pplogger->setEnv($site);
} elsif ($location =~ /SILAN_CN/i){
	$site = "silan_cn_sort_bstdf";
	$pplogger->setEnv($site);
} elsif ($location =~ /ASENT_TW/i) {
	$site = "asent_tw_ft_bstdf";
	$pplogger->setEnv($site);
}

if ( ! -f $infile ) {
    	ERROR("$infile does not exist");
    	pod2usage(3);
}

my $unzip_file = $infile;
if ($infile =~ /\.gz$/) {
        $unzip_file =~ s/\.gz$//;
        gunzip $infile => $unzip_file or die "gunzip failed: $GunzipError\n";
        INFO ("gunzipped file = $unzip_file");
}
my $header2 = new_headerLong->new();
my ($errLot,$errWafer) = &getLot($infile);
INFO("ERRLOT=$errLot||ERRWAFER=$errWafer");
#INFO($errLot);
if ($errLot eq "NO_LOTID") {
	$pplogger->setLot($errLot);
	if (!($hOptions{FINALLOT})) {
		$pplogger->setWaferFlag(1);
		#	$header2->LOT($errLot);
#   $header2->populateMeta();
#   $pplogger->setLot($errLot);
#   $pplogger->setSourceLot($header2->SOURCE_LOT);
		$pplogger->setWafNum($errWafer);
	} else {
		$pplogger->setWafNum("00");
	}

	dpExit( 1, "BAD FILE - NO LOTID");
}
if (!($hOptions{FINALLOT})) {
	if ($errWafer eq "") {
		$pplogger->setLot($errLot);
	
		$pplogger->setWaferFlag(1);
		$header2->LOT($errLot);
	  $header2->populateMeta();
	  $pplogger->setLot($errLot);
	  $pplogger->setSourceLot($header2->SOURCE_LOT);
		$pplogger->setWafNum($errWafer);
	
		$pplogger->setWafNum("00");
	
		dpExit( 1, "BAD FILE - NO WAFERID");
	}
}

# create Writer
INFO("Fork dir=$hOptions{FORK}");
my $wr = PDF::DpWriter->new(
    {   basename => ( basename $unzip_file),
        ext      => 'iff',
        outdir   =>  $hOptions{OUT},
		forkdir => $hOptions{FORK},
		gzipIFF  => 'Y'
    	}
);

# create Parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $perl = "perl";
my ( $TP_bin, $TD_bin );

# Convert source file to TP and TD
my $command = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_bstdf_bksort.pl -infile=$unzip_file";
INFO("$command ");
my @output = `$command`;

if ($?) {
    	#print "error in $command\n";
    	$pplogger->setLot($errLot);
    	if (!($hOptions{FINALLOT})) {
    		$pplogger->setWaferFlag(1);
    		$header2->LOT($errLot);
    	 	$header2->populateMeta();
	    	$pplogger->setSourceLot($header2->SOURCE_LOT);
				$pplogger->setWafNum($errWafer);
    	} else {
    		$pplogger->setWafNum("00");
    	}
    	dpExit( 1, "Failed to convert $command : $!" );
}
if ( $output[-1] =~ /td=(.*) tp=(.*)/ ) {
    	$TD_bin = $1;
    	$TP_bin = $2;
    	INFO("TD=$TD_bin");
    	INFO("TP=$TP_bin");
}
else {
	$pplogger->setLot($errLot);
	if (!($hOptions{FINALLOT})) {
		$pplogger->setWaferFlag(1);
		$header2->LOT($errLot);
    $header2->populateMeta();
    $pplogger->setSourceLot($header2->SOURCE_LOT);
		$pplogger->setWafNum($errWafer);
	} else {
		$pplogger->setWafNum("00");
	}
	dpExit( 1, "Failed to convert $command : " . join( "#", @output ) );
}

my $TD_txt = convertBinToAscii($TD_bin);
if($TD_txt =~ /Failed to convert.+/i) {
	$pplogger->setLot($errLot);
	if (!($hOptions{FINALLOT})) {
		$header2->LOT($errLot);
		$header2->populateMeta();
		$pplogger->setWaferFlag(1);
		$pplogger->setSourceLot($header2->SOURCE_LOT);
		$pplogger->setWafNum($errWafer);
	} else {
		$pplogger->setWafNum("00");
	}
  dpExit(1, "$TD_txt");
}
my $TP_txt = convertBinToAscii($TP_bin);
if($TP_txt =~ /Failed to convert.+/i) {
	$pplogger->setLot($errLot);
	if (!($hOptions{FINALLOT})) {
		$header2->LOT($errLot);
		$header2->populateMeta();
		$pplogger->setWaferFlag(1);
		$pplogger->setSourceLot($header2->SOURCE_LOT);
		$pplogger->setWafNum($errWafer);
	} else {
		$pplogger->setWafNum("00");
	}
  dpExit(1, "$TP_txt");
}
my $td     = readStdfAscii($TD_txt);
if($td =~ /NO_.+/i) {
	$pplogger->setLot($errLot);
	if (!($hOptions{FINALLOT})) {
		$header2->LOT($errLot);
		$header2->populateMeta();
		$pplogger->setWaferFlag(1);
		$pplogger->setSourceLot($header2->SOURCE_LOT);
		$pplogger->setWafNum($errWafer);
	} else {
		$pplogger->setWafNum("00");
	}
  dpExit(1, "$td");
}
#if ($td =~ /NO_.+/i) {
#	$pplogger->setWaferFlag(1);
#	$header2->LOT($errLot);
#  $header2->populateMeta();
#  $pplogger->setLot($errLot);
#  $pplogger->setSourceLot($header2->SOURCE_LOT);
#	$pplogger->setWafNum($errWafer);
#  dpExit( 1, "Failed to convert $command : " . join( "#", @output ) );
#}
my $tp = readStdfAscii($TP_txt);
if($tp =~ /NO_.+/i) {
	$pplogger->setLot($errLot);
	if (!($hOptions{FINALLOT})) {
		$header2->LOT($errLot);
		$header2->populateMeta();
		$pplogger->setWaferFlag(1);
		$pplogger->setSourceLot($header2->SOURCE_LOT);
		$pplogger->setWafNum($errWafer);
	} else {
		$pplogger->setWafNum("00");
	}
  dpExit(1, "$tp");
}
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());

my $header = new_headerLong->new( $parser->stdf2header($td) );
$header->EQUIP6_ID($facility);
$header->CFG_TESTER_TYPE($cfg_tstr_typ);
$header->isFinalLot( $hOptions{FINALLOT} );    ### added to cater final test

if ($hOptions{LOC} eq 'BK' && $hOptions{METASTRIP}) {
	unless ( $header->populateMeta ){
		my $origLot = $header->LOT;
		my $tempLot1 = $origLot;
		my $tempLot2 = $origLot;

		if (length($tempLot1) > 8 && $tempLot1 =~ /^KG|^KH/) {
			INFO("METASTRIP: First 8 characters.");
			$tempLot1 = substr($tempLot1,0,8);
			$header->LOT($tempLot1);
			
			unless ($header->populateMeta) {
				INFO("METASTRIP; Last character.");
				$tempLot2 = substr($tempLot2, 0, -1);
				$header->LOT($tempLot2);
				
				unless ($header->populateMeta) {
					$wr->noMeta(1);
				}
			}
			
		}
		else {
			$wr->noMeta(1);
		}	
		
		$header->LOT($origLot);
	}
		
} else {

	unless ( $header->populateMeta ){
		if (!($hOptions{NOSANDBOX})){
			$wr->noMeta(1);
		}
		else {
			WARN("File was not sandboxed. Argument was enabled.");
		}
		$reglim_flg = "N";
	}
}

# Check Program length for > 35.  Truncate and send to sandbox.
my $program = $header->PROGRAM;
if ( length($program) > 35 )
{
  	INFO("PROGRAM NAME \"$program\" will be truncated to 35 characters.  Sending to sandbox.    ");
  	$wr->forSBox(1);
  	$program = substr($program, 1, 35); # Leave enough room for session type
}
$header->PROGRAM($program);

if(!($hOptions{FINALLOT})) {
    	$header->PROGRAM_CLASS(1);
}
else {
    	$header->PROGRAM_CLASS(2);	
}

#my $bins   = $parser->sbr2bins( $td->SBR );
#my $binsTP = $parser->epdr2bins( $tp->EPDR );
#mergeBins($bins,$binsTP);

my $sbins  = $parser->sbr2bins( $td->SBR );
my $hbins  = $parser->hbr2bins( $td->HBR );
my $sbinsTP = $parser->epdr2bins( $tp->EPDR );
my $hbinsTP = $parser->epdr2hbins( $tp->EPDR );
my $good_count = $td->MRR->{GOOD_CNT};
mergeBins($sbins,$sbinsTP);
mergeBins($hbins,$hbinsTP);

my $testCond = [qw/PIN_1 PIN_2 PIN_3 SBIN_NUM HBIN_NUM
        VCC VEE TEMP FREQ PARMTYPE SEQ_NAME
        TCONDS SBIN_NAM HBIN_NAM TEST_TXT
        LOAD_VAL TEST_CAT VIEW_ORD /];
$parser->testConditions_EPDR( $testCond);
my $tests = $parser->epdr2tests( $tp->EPDR );

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

my $model = new_model({dataSource => 'BSTDF'});

$model->header($header);

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

if(!($hOptions{FINALLOT})) {
    	my $wmap = $model->updateWMap;
    	unless ( ! $wmap->isEmpty ){
		#$wr->wmapIsEmpty(1);
		if (!($hOptions{NOSANDBOX})) {
			$wr->wmapIsEmpty(1);
		}
		else {
			WARN("File was not sandboxed. Argument was enabled.");			
		}
		$reglim_flg = "N";
    	}
    	unless ( $wmap->confirmed ){
		#$wr->noWMap(1);
		if (!($hOptions{NOSANDBOX})) {
			$wr->noWMap(1);
		}
		else {
			WARN("File was not sandboxed. Argument was enabled.");
		}
		$reglim_flg = "N";
    	}
    	$model->wmap($wmap);
}	

if(!($hOptions{FINALLOT})) {
    	#$model->updateProgram("MAP_PGM");
    	$model->updateProgram("MAP_PGM_REV");
}
else {
    	$model->updateProgram;
}	

foreach my $stdfWafer ( @{ $td->wafers } ) {
    	my $wafer = new_wafer;
    	$wafer->START_TIME( $header->START_TIME );
    	$wafer->END_TIME( $header->END_TIME );
    	my $waferNum = -1;

    	if ( defined $stdfWafer->WIR && !($hOptions{FINALLOT})) {
        	$waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
        	$wafer->number($waferNum);
		#assign source lot as wafer name
		if ($header->SOURCE_LOT  ne "") {
			$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
			$pplogger->setWaferFlag(1);
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
    	}
    	if ( @{ $stdfWafer->WSBR } ) {
		$wsbins = $parser->sbr2bins( $stdfWafer->WSBR, $good_count );		
        	mergeBins($wsbins,$sbinsTP);
    	}
	if ( @{ $stdfWafer->WHBR } ) {
		$whbins = $parser->hbr2bins( $stdfWafer->WHBR, $good_count );        
        	mergeBins($whbins,$hbinsTP);
    	}

	### wsbins
        if (! defined $wsbins or ! @$wsbins) {
            	my $sbinHash = $parser->res2binHash($stdfWafer->res);
            	foreach my $binNumber (sort {$a <=> $b} keys %$sbinHash) {
                 	push @$wsbins, $sbinHash->{$binNumber};
            	}
        } 
	else {
              	# PART_FLAG in bstdf is not reliable
              	#  $bins = $parser->updateBinPF($bins,$stdfWafer->res);
        }
		
	## whbins
	if (! defined $whbins or ! @$whbins) {
            	my $binHash = $parser->res2hbinHash($stdfWafer->res);
            	foreach my $binNumber (sort {$a <=> $b} keys %$binHash) {
                 	push @$whbins, $binHash->{$binNumber};
            	}
        }
	else {
              	# PART_FLAG in bstdf is not reliable
              	#  $bins = $parser->updateBinPF($bins,$stdfWafer->res);
        }
    
    	$wafer->sbins($wsbins);
    	$wafer->hbins($whbins);
    	$wafer->tests($tests);
    	$wafer->dies( $parser->res2dies( $stdfWafer->res, $tests ) );
    	$model->add( 'wafers', $wafer );

}

$model->sbins($sbins);
$model->hbins($hbins);

#&normalizeToBaseUnit($model);
	
my $formatter = new_iff_formatter({
        model=>$model,
        writer => $wr});
$formatter->dataItems([qw/x y site partid hard_bin soft_bin/]);
$formatter->printPar;

# Limits
#if ($reglim_flg eq "Y") {
#	if($model->isLimitNew){
#  		$model->buildLimit;
#  		$model->limit->conditionNames($testCond);
#  		$formatter->printLimit;
#  		$model->limit->registerRefdb;
#	}
#}
#else {    #always generate but do not register limit if sandbox
	$model->buildLimit;
	$model->limit->conditionNames($testCond);
	$formatter->printLimit;
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
	INFO("Merging Bins with EPDR bins.");
  	for my $bin (@$binsTP) {
    		$binName{ $bin->number } = $bin->name;
		#INFO("binstp : ".$bin->number.",".$bin->name);
  	}
  	for my $bin (@$bins) {
  		#INFO("bins : ".$bin->number.",",$bin->name);
    		$bin->name( $binName{ $bin->number } );
	
  	}
}

# Delete gunzipped file
unlink ($unzip_file) if $infile =~ /\.gz$/;

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
#	read FLE,$str,1;
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
  	#$lot_id = $fn_lot;
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
	
	#print "======>LOT=$lot_id||WAFER=$fn_wafer\n";
	return($lot_id, $fn_wafer);
}
