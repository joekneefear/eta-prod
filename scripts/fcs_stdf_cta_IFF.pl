#!/usr/bin/env perl_db
# SVN $Id: fcs_stdf_cta_IFF.pl 

=pod

=head1 SYNOPSIS

  fcs_stdf_cta_IFF.pl <Input flie name>
      --out <output dir>  same dir as input file by default
      [--finallot]
      [--logfile <logfilepath>]  
      [--debug|--trace]
      [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will read BSTDF file (Binary) and write to stdf like text file

=head1 AUTHOR

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

 2015/11/19 eric	: new
 2016/03/18 wsanopao	: logging pre-processing information  to refdb.pp_log table.
 2017/03/21 eric   	: assign source lot as wafer name
 2017/03/22 eric   	: set wafer flag for pplogging
 2017-Apr-18 jgarcia	: modified to support pp_logging even if issues encountered in converting binary to ascii format.
 2017-Apr-18 jgarcia	: modified to support pp_logging when generated an malformed stdf ascii derrived from binary.
 2017-May-30 gilbert 	: generate limits always and dont register in refdb.pp_limits
 2019-Aug-09 eric	: added nosandbox option. its purpose was not to move the file to sandbox when envoked.
 2021/04/09  glory      : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

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
our $TESTER  = "CTA";

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
        	\%hOptions, "OUT=s", "FINALLOT", "LOC=s", "FACILITYFILE=s", "CONFIG=s", "SITE=s", "LOGFILE=s", "DEBUG", "TRACE","V", "PPLOG", "NOSANDBOX"
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
my @required_options = qw/OUT LOC CONFIG FACILITYFILE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# wsanopao: Pass PPLogger object to PDF::Log
PDF::Log->init( \%hOptions,$pplogger);
if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Warren: Set flag for pp logging
}
my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location = $hOptions{LOC};
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");

# check input file
my $infile = $ARGV[0];
my $site;
my $header2 = new_headerLong->new();

# wsanopao: Set Raw File ==> infile
$pplogger->setRawFile($infile);

if ( ! -f $infile ) {
	dpExit( 1, "input file does not exist $infile" );
    	pod2usage(3);
}

# create Writer
my $wr = PDF::DpWriter->new(
{   	basename => ( basename $infile),
       	ext      => 'iff',
       	outdir   => $hOptions{OUT},
        gzipIFF  => 'Y'
} 
);
if ($hOptions{LOC} =~ /SILAN_CN/i) {
	$site = "silan_cn_sort_cta";
}

$pplogger->setEnv($site);

my ($errLot,$errWafer) = getLotWafer($infile);
INFO("ERRLOT=$errLot||ERRWAFER=$errWafer");
my $TD_txt = convertBinToAscii($infile);
if($TD_txt =~ /Failed to convert.+/i) {
	$pplogger->setLot($errLot);
	if ($site =~ /sort/) {
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
my $td  = readStdfAscii($TD_txt);
if($td =~ /NO_.+/i) {
	$pplogger->setLot($errLot);
	if ($site =~ /sort/) {
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
my ($sbins,$hbins,$wsbins,$whbins) =((),(),(),());
my $reglim_flg = "Y";

# create parser
my $parser = PDF::Parser::Stdf::Generic->new;
my $header  = new_headerLong->new( $parser->stdf2header($td) );
my @wk = split('-', $header->LOT);

$header->LOT($wk[0]);
$header->EQUIP6_ID($facility);
$header->CFG_TESTER_TYPE($hOptions{CONFIG});

#Use ppid naming rule
my $program = substr($header->PROGRAM, rindex($header->PROGRAM,"\\") +1);
($program, my $dump) = split /\./, $program;

if (length($program) + length($wk[1]) > 35) {
	INFO("PROGRAM NAME \"".$program.$wk[1]."\" will be truncated to 35 characters.  Sending to sandbox.");
	$wr->forSBox(1);
	$reglim_flg = "N";
	$program = substr($program, 1, 35-length($wk[1])); # Leave enough room for session type
}
$header->PROGRAM_CLASS(1);
$header->PROGRAM($program);
$header->isFinalLot( $hOptions{FINALLOT} );

unless ( $header->populateMeta ) {
    	#$wr->noMeta(1);
	if (!($hOptions{NOSANDBOX})) {
		$wr->noMeta(1);
	}
	else {
		 WARN("File was not sandboxed. Argument was enabled.");
	}
    	$reglim_flg = "N";
}

my $model = new_model;
$model->header($header);
$model->dataSource('CTA');

# wsanopao: Passing Reference of Model
$pplogger->setModelHeader($model);

my $wmap = $model->updateWMap;
if (defined $wmap) {
    	unless ( ! $wmap->isEmpty ) {
		#$wr->wmapIsEmpty(1);
		if (!($hOptions{NOSANDBOX})) {
			$wr->wmapIsEmpty(1);
		}
		else {
			WARN("File was not sandboxed. Argument was enabled.");
		}
		$reglim_flg = "N";
    	}
    	unless ( $wmap->confirmed ) {
    		#$wr->noWMap(1);
		if (!($hOptions{NOSANDBOX})) {
			$wr->noWMap(1);
		}
		else {
			WARN("File was not sandboxed. Argument was enabled.");
		}
		$reglim_flg = "N";
    	}
}
else {
    	$wmap = new_wmap;
    	$wr->wmapIsEmpty(1) unless ( ! $wmap->isEmpty );
    	$wr->noWMap(1);
    	$reglim_flg = "N";
    	$model->wmap($wmap);
}
$model->updateProgram("MAP_PGM");

my $sbins;
my $hbins;
getBinSummary($td->SBR, $td->SBR_each, 'sbr');
getBinSummary($td->HBR, $td->HBR_each, 'hbr');

my $str_limit;

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
    	if ( defined $td->WCR ) {
		$wmap->wf_units($td->WCR->{WF_UNIT});
        	$wmap->wf_size($td->WCR->{WAFR_SIZ});
        	$wmap->flat($td->WCR->{WF_FLAT});
        	$wmap->die_width($td->WCR->{DIE_WID});
        	$wmap->die_height($td->WCR->{DIE_HT});
        	$wmap->center_x($td->WCR->{CENTER_X});
        	$wmap->center_y($td->WCR->{CENTER_Y});
        	$wmap->positive_x($td->WCR->{POS_X});
        	$wmap->positive_y($td->WCR->{POS_Y});		
    	}
	
    	## wsbins
    	if(@$sbins < 0)	{
       		if ( @{ $stdfWafer->WSBR } ) {
            		$wsbins = $parser->sbr2bins( $stdfWafer->WSBR );
       		}
       		if ( !defined $wsbins or !@$wsbins ) {
            		my $sbinHash = $parser->res2binHash( $stdfWafer->res );		
          		foreach my $binNumber ( sort { $a <=> $b } keys %$sbinHash ) {
                 		push @$wsbins, $sbinHash->{$binNumber};
            		}
       		}
       		else {
            		$wsbins = $parser->updateBinPF( $wsbins, $stdfWafer->res );
       		}
		$wafer->sbins($wsbins);
	}
	## whbins
	if(@$hbins < 0) {
       		if ( @{ $stdfWafer->WHBR } ) {
             		$whbins = $parser->hbr2bins( $stdfWafer->WHBR );
       		}
       		if ( !defined $whbins or !@$whbins ) {
             		my $hbinHash = $parser->res2hbinHash( $stdfWafer->res );
             		foreach my $binNumber ( sort { $a <=> $b } keys %$hbinHash ) {
                 		push @$whbins, $hbinHash->{$binNumber};
             		}
       		}
       		else {
             		$whbins = $parser->updatehBinPF( $whbins, $stdfWafer->res );
       		}
	
       		$wafer->hbins($whbins);
    	}

    	my $tests = $parser->res2tests( $stdfWafer->res );  # get test parameters
    	$wafer->tests($tests);
    	$wafer->dies( $parser->res2dies( $stdfWafer->res, $tests ) );
    	$model->add( 'wafers', $wafer );
}

$model->sbins($sbins);
$model->hbins($hbins);
	
&normalizeToBaseUnit($model);

my $formatter = new_iff_formatter(
{   	model  => $model,
        writer => $wr
}
);

$formatter->testItems([qw/number name units/]);
$formatter->dataItems([qw/x y site partid hard_bin soft_bin/]);
$formatter->printPar;

# Limits
#if ($reglim_flg eq "Y") {
#	if ( $model->isLimitNew ) {
#   		$model->buildLimit;
#    		$formatter->printLimit;
#		$model->limit->input_file(basename $infile); 
#    		$model->limit->registerRefdb;
#	}
#}
#else {  # always generate but do not register limit if sandbox
	$model->buildLimit;
	$formatter->printLimit;
	$model->limit->input_file(basename $infile);
#}


unlink $TD_txt unless (isLogDebug);

sub getBinSummary{
  	my $bin = shift;
  	my $bin_each = shift;
  	my $mode = shift;
  	my $bins;
  
  	if(@$bin > 0) {
		if($mode eq "sbr"){
			$sbins = $parser->sbr2bins( $bin );
		}
		else{
			$hbins = $parser->hbr2bins( $bin );
		}	
  	}
 	elsif(@$bin_each > 0) {	
		if($mode eq "sbr"){
			$sbins = $parser->sbr2bins( $bin_each );
		}
		else{
			$hbins = $parser->hbr2bins( $bin_each );
		}
  	}
}

dpExit(0);

sub getLotWafer() {
	my $file = shift;
	my ($lotid,$waferid) = "";
	
	my $script_name = "$Bin/stdf_perl/script/stdf_copy ${file} | grep LOT_ID | tr '\n' ','; echo";
  open FH, "$script_name|";
  my @ret = <FH>;
  close(FH);
  chomp($ret[0]);
  my ($item1, $item2) = split /\s*\,\s*/, $ret[0] if $ret[0] ne "";
  $item1 =~ s/^\s+|\s+$//g;
  my($junk,$prd_lot) = split /=/,$item1;
  
  $lotid = $prd_lot;
  
  my $script_name = "$Bin/stdf_perl/script/stdf_copy ${file} | grep WAFER_ID | tr '\n' ','; echo";
  open FH, "$script_name|";
  my @ret = <FH>;
  close(FH);
  chomp($ret[0]);
  my ($item1, $item2) = split /\s*\,\s*/, $ret[0] if $ret[0] ne "";
  $item1 =~ s/^\s+|\s+$//g;
  my($junk,$wafer) = split /=/,$item1;
  
  $waferid = $wafer;
  
  return ($lotid,$waferid);

}

