#!/usr/bin/env perl_db
# SVN $Id: fcs_fet_sort_IFF.pl 2193 2017-05-29 09:32:16Z dpower $

=pod

=head1 SYNOPSIS

  	fcs_fet_ft_IFF.pl <Input flie name>
      		--out <output dir>  output direcotry must exist
	  	--TPDIR <
	   	--config <cfg_tester_type>
	   	--loc <location e.g CP, SZ, ME>
	   	--limitDir <limit file look up direcotry>
      		[--logfile <logfilepath>]  
      		[--debug|--trace]
	  	[--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read STDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<jason.arp@pdf.com>

=head1 CHANGES

2015/06/26 grace   : new
2015/07/02 jgarcia : added to accept location in LOC as a required argument and assign the value to EQUIP6_ID. 
2015/07/17 grace   : swamped x and y coordinates 
		   : added option 'limitDir' 
2015/08/18 eric	   : process WM first and register it and add cfg_id into ppid. 
2015/08/20 eric    : fixed testnames issue, get bin summary from wsbr.
2015/11/18 eric    : always generate but do not register limit if sandbox
2016/02/26 wsanopao: logging pre-processing information  to refdb.pp_log table.
2017/03/23 eric    : assign source lot as wafer name
29-May-2017 gilbert: generate limits always and dont register in refdb.pp_limits

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

our $VERSION = "1.0";
our $TESTER  = "FET";
my $location = "";

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
        \%hOptions,  "OUT=s", "LIMITDIR=s", "LOC=s", "CONFIG=s",
        "LOGFILE=s", "DEBUG", "TRACE", "V", "TPDIR=s", "TYPE=s", "PPLOG"
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

my @required_options = qw/OUT TPDIR LOC/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$PPlogger);
if ($hOptions{PPLOG}){
	$PPlogger->settobeLog(1);  #Warren: Set flag for pp logging
}

my $location = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
#my $limitdir = $hOptions{LIMITDIR};
my $reglim_flg = "Y";

# check input file
my $infile = $ARGV[0];

# wsanopao: Set Raw File ==> infile 
$PPlogger->setRawFile($infile);

if ( ! -f $infile ) {
    ERROR("$infile does not exist");
    pod2usage(3);
}

# create Writer
my $wr = PDF::DpWriter->new(
    {   basename => ( basename $infile),
        ext      => 'iff',
        outdir   =>  $hOptions{OUT}
    }
);

# create Parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $perl = "perl";
my ( $TP_bin, $TD_bin );

# Convert source file to TD
my $command = "$perl -I$Bin/stdf_perl/lib $Bin/stdf_perl/conv_fet_cpr_slsort.pl -infile=$infile";
my @output = `$command`;
my @binMap = ();

foreach my $out_file (@output){
	my @wk = split('td=', $out_file);
	
	foreach my $td_file (@wk)
	{	
		if($td_file =~ /.TD/){
			$TD_bin	 = $td_file;
			$TD_bin =~ s/ //;			
		}
		else
		{			
			$td_file =~ s/\015//;
			$td_file =~ s/ //;
			$td_file =~ s/\cM\n//;
			$td_file =~ s/\r//;
			$td_file =~ s/\n//;			
			
			print "start".$td_file."\n";	
			
			if($td_file !~ / /)
			{			
				push @binMap, $td_file ;							
			}
		}
	}
}
##### PROCESS WM FILE FILE FIRST TO GET CFG_ID#####
foreach my $bin (@binMap){
        if($bin ne "") {
                my $bin_txt = convertBinToAscii($bin);
                my $bin_td = readStdfAscii_WM($bin_txt);
                WriteBinMap($bin_td, $bin);
                unlink $bin_txt;
        }
}

##### PROCESS TD FILE #####
my $TD_txt = convertBinToAscii($TD_bin);
INFO("TD_txt ===>". $TD_txt);

my $td     = readStdfAscii($TD_txt);
my $good_count;
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());
my $header = new_headerLong->new( $parser->stdf2header($td) );
   $header->EQUIP6_ID($location);
   $header->CFG_TESTER_TYPE($cfg_tstr_typ);

unless ( $header->populateMeta ) {
    	$wr->noMeta(1);
    	$reglim_flg = "N";
}

my $spec_nam = $td->EMIR->{SPEC_NAM};
my $spec_rev = $td->EMIR->{SPEC_REV};

# find the corresponding TP file
my $TP_path = $hOptions{TPDIR};
 
#my $TP_path = "/data/cpft_fet/TP";  # generalize later
my $regexp = $spec_nam.$spec_rev.".*\.TP";

my $TP = undef;
foreach my $file (glob "$TP_path/*.TP"){
  	if ($file =~ /$regexp/i){
     		INFO("TP Found : $file");
     		$TP = $file;
  	}
}
unless (defined $TP ) {  
	unless (isLogDebug) {
        	unlink $TD_bin;
        	unlink $TD_txt;
        	unlink $TP_bin;
		unlink $TP;
	}
    	dpExit(4,"No TP found in $TP_path by pattern $regexp");
} 
my $TP_txt = convertBinToAscii($TP);

INFO($TP_txt);
my $tp     = readStdfAscii_fet_sort($TP_txt, "fet_sort");
my $tests  = $parser->epdr2tests( $tp->EPDR );
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
$header->PROGRAM_CLASS(1);
$model->header($header);

my $wmap = $model->updateWMap;

# wsanopao: Passing Reference of Model
$PPlogger->setModelHeader($model);

if(defined $wmap)   {
    	unless ( !$wmap->isEmpty ){
		$wr->wmapIsEmpty(1);
		$reglim_flg = "N";
    	}
    	unless ( $wmap->confirmed ) {
    		$wr->noWMap(1);
		$reglim_flg = "N";
   	}
}
else{
    	$wmap = new_wmap;
    	$wr->wmapIsEmpty(1) unless ( !$wmap->isEmpty );
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
		#assign source lot as wafer name
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
        	$wsbins = $parser->sbr2bins( $stdfWafer->WSBR,$good_count );
    	}
    	if($wsbins ne "")
    	{
        	$wafer->sbins($wsbins);
    	}
    	if ( @{ $stdfWafer->WHBR } ) {
         	$whbins = $parser->hbr2bins( $stdfWafer->WHBR, $good_count);
    	}
    	if ($whbins ne "")
    	{
        	$wafer->hbins($whbins);
    	}	    
	 
    	$wafer->tests($tests);
    	$wafer->dies( $parser->res2dies_fet_sort( $stdfWafer->res, $tests ) );
    	$model->add( 'wafers', $wafer );

}

if($good_count eq "" or $good_count == 0)
{
        $good_count = $td->MRR->{GOOD_CNT};
}

$model->sbins($sbins);
$model->hbins($hbins);
&normalizeToBaseUnit($model);

my $formatter = new_iff_formatter({
        model=>$model,
        writer => $wr});
$formatter->printPar;

# Limits
#if ($reglim_flg eq "Y") {
#    	if($model->isLimitNew){
#		$model->buildLimit;
#        	$formatter->printLimit;
#        	$model->limit->input_file(basename $infile);
#        	$model->limit->registerRefdb;	
#    	}
#}
#else {  #always generate but do not register limit if sandbox
	$model->buildLimit;
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

sub WriteBinMap{
	my $td_wm = shift;
	my $infile = shift;

	# create Writer
	my $wr_wm = PDF::DpWriter->new(
    	{   	basename => ( basename $infile),
        	ext      => 'iff',
        	outdir   =>  $hOptions{OUT}
    	}
	);
	
	my $ewcr = $td_wm->EWCR;
	my $row_cnt = $ewcr->{ROW_CNT};
	my $col_cnt = $ewcr->{COL_CNT};
	my $wmap_wm = new_wmap; 

	my $header = new_headerLong->new( $parser->stdf2header($td_wm) );
   	$header->EQUIP6_ID($location);
   	$header->CFG_TESTER_TYPE($cfg_tstr_typ);
   	$header->PROGRAM_CLASS(4);	

   	unless ( $header->populateMeta ) {
     		$wr->noMeta(1);
   	}

	my $model_wm = new_model(
   	{
   		dataSource => 'FET', 
		wmap => $wmap_wm,
  	}
	);
   	$model_wm->header($header);

	foreach my $stdfWafer ( @{ $td_wm->wafers } ) {
    		my $wafer = new_wafer;
    		$wafer->START_TIME( $header->START_TIME );
    		$wafer->END_TIME( $header->END_TIME );
    		my $waferNum = -1;
   	 	if ( defined $stdfWafer->WIR ) {
        		$waferNum = $stdfWafer->WIR->{WAFER_ID} + 0;
        		$wafer->number($waferNum);
			#assign source lot as wafer name
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
    		}
    		if ( defined $td_wm->EWCR ) {
			$wmap_wm->wf_units($td_wm->EWCR->{WF_UNIT});
        		$wmap_wm->wf_size($td_wm->EWCR->{WAFR_SIZ});
        		$wmap_wm->flat($td_wm->EWCR->{WF_FLAT});
        		$wmap_wm->die_width($td_wm->EWCR->{DIE_WID});
        		$wmap_wm->die_height($td_wm->EWCR->{DIE_HT});
        		$wmap_wm->center_x($td_wm->EWCR->{CENTER_X});
        		$wmap_wm->center_y($td_wm->EWCR->{CENTER_Y});
        		$wmap_wm->positive_x($td_wm->EWCR->{POS_X});
        		$wmap_wm->positive_y($td_wm->EWCR->{POS_Y});
    		}
	
    		$hbins = $parser->hbr2bins( $stdfWafer->WHBR );
    		$wafer->hbins($hbins);
    		$wafer->tests($tests);
    		$wafer->dies( $parser->wmr2dies( $stdfWafer->WMR, $row_cnt, $col_cnt) );
    		$model_wm->add( 'wafers', $wafer );

	}	

my $wmap = $model_wm->updateWMap;
if (defined $wmap) {
    	$wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
    	unless ( $wmap->confirmed ) {
    		$wr->noWMap(1);
    	}
}
else {
    	$wmap = new_wmap;
    	$wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
    	$wr->noWMap(1);
    	$model_wm->wmap($wmap);
}
$model_wm->updateProgram("MAP_PGM");


my $formatter = new_iff_formatter({
        model=>$model_wm,
        writer => $wr_wm});
	$wr_wm->ext("wm_iff");
	$wr_wm->noMeta($wr->noMeta);
	$wr_wm->noWMap($wr->noWMap);	

$formatter->dataItems([qw/x y soft_bin/]);
$formatter->printBinmap;

unless (isLogDebug) {
	unlink $td_wm;
}

unlink $infile;

}

sub readLimitFile {   
    	my $infile = shift;
    	my $limit = new_limit;
   	# $limit->conditionNames([qw/testCond PIN testType/]);
    	my $num = 0;
    	if ( $infile =~ /\.TPL/ ) {
       		my $test;
       		open( INFILE, $infile );
       		while (<INFILE>) {
           		s/[\r\n]+\z//;
           		$num++;          
	      		$test = new_test;
             
              		my @items= split(',',$_);
			my @names = split(' ', $items[3]);
			  
			$test->number($items[0]);
              		$test->name(trim($names[1]));
              		$test->LSL(trim($items[1]));
              		$test->HSL(trim($items[2]));
              		$test->LOL(trim($items[8]));
              		$test->HOL(trim($items[9]));
              		$test->units(trim($items[10]));            
        
			INFO("test : ". $test->name);
	      		$limit->add('tests',$test);
	   
       		}  
       		close(INFILE);
    
    	}
    	return $limit;
}

dpExit(0);

