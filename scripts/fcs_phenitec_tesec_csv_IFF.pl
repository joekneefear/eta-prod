#!/usr/bin/env perl_db
# SVN $Id: fcs_phenitec_tesec_csv_IFF.pl 
=pod

=head1 SYNOPSIS

      fcs_phenitec_tesec_csv_IFF.pl <Input flie name>
      --out <output dir>  output direcotry must exist
      --loc <location>
      --facilityfile <$DPSCRIPT/facilityMapping.ini>
      [-config <config_tester_type>]
      [--logfile <logfilepath>]
      [--debug|--trace]
      [--V Display version ID ]

=head1 DESCRIPTIONS

B<This script> will read XLS file and output IFF file

=head1 AUTHOR

B<eric.alfanta@fairchildsemi.com>

=head1 CHANGES

2016-Jul-15 Eric	: new
2016-Aug-10 Eric	: added wmap to model
2017-Mar-22 eric	: assign source lot as wafer name
2017-May-29 Gilbert     : generate limits always and dont register in refdb.pp_limits
2019-Aug-09 Eric	: added nosandbox option. its purpose was not to move the file to sandbox when envoked.
2020/09/01 karen        : added support to fork output (IFF)/files to designated location
2021/04/16 glory        : get new Facility name from $DPSCRIPT/facilityMapping.ini and compress IFF file to gzip after.

=head1 LICENSE

(C) Fairchild Semiconductor Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DAO;
use PDF::Parser::TESEC_CSV_SORT;
use PDF::Formatter;
use PDF::DpWriter;
use File::Basename qw/basename/;
use List::Util qw(first);
use POSIX qw(strftime);
use Time::localtime;
use File::stat;
use Time::Piece;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use PPLOG::PPLogger;
use Config::Tiny;


our $VERSION = "

1.0
";
our $TESTER  = "SIC";

# a hash to receive options
my (%hOptions) = ();
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions,  "OUT=s", "FORK=s", "FINALLOT", "PPLOG", "NOLOOKUP", "NOSANDBOX",
        "LOGFILE=s", "DEBUG", "TRACE", "V", "TYPE=s", "LOC=s", "FACILITYFILE=s", "CONFIG=s",
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

PDF::Log->init( \%hOptions,$pplogger );
if ($hOptions{PPLOG}){
        $pplogger->settobeLog(1);  
}

my $config = Config::Tiny->read($hOptions{FACILITYFILE});
my $location     = $hOptions{LOC};
my $cfg_tstr_typ = $hOptions{CONFIG};
my $reglim_flg = "Y";
my $facility = $config->{$location}->{probe};
INFO("FACILITY|EQUIP6_ID=$facility");

# Read input file
my $infile = $ARGV[0];
$pplogger->setRawFile($infile);

if ( !-f $infile ) {
    dpExit( 1, "input file does not exist $infile" );
}

INFO("infile  = $infile");

my $parser = PDF::Parser::TESEC_CSV_SORT->new;
my ($td, $tp, $sbr) = $parser->readFile($infile,isLogDebug);
my $file_time = localtime( stat($infile)->mtime )->strftime("%Y/%m/%d %H:%M:%S");

#loop each lot
foreach my $lotno ( sort keys %$td) {
	INFO("Fork dir=$hOptions{FORK}");
	my $wr = PDF::DpWriter->new(
    	{   
		outdir   => $hOptions{OUT},
		forkdir => $hOptions{FORK},
        	basename => ( basename $infile),
        	ext      => 'iff',
                gzipIFF  => 'Y'

    	}
	);

	my $header = new_headerLong;
	my $limit = new_limit;
	my $wmap   = new_wmap;
	my $model = new_model (
                {
                        header => $header,
			wmap   => $wmap,
                        misc   => {},
                        dataSource => 'TESEC'
                }
        );

	# insert limits 
	my $tnum_addr = $$tp{$lotno}{TNUM};
	my $tnam_addr = $$tp{$lotno}{TNAME};
	my $unit_addr = $$tp{$lotno}{UNIT};
	my $cond_addr = $$tp{$lotno}{COND};
	my $hsl_addr = $$tp{$lotno}{HSL};
	my $lsl_addr = $$tp{$lotno}{LSL};
	for (my $j=0; $j<=$#$tnum_addr; $j++) {
		my $test = new_test;
		$test->number($$tnum_addr[$j]);
		$test->name(repNA($$tnam_addr[$j]));
		$test->units(repNA($$unit_addr[$j]));
		$test->HSL(repNA($$hsl_addr[$j]));
		$test->LSL(repNA($$lsl_addr[$j]));
		$test->add('conditions',$$cond_addr[$j]);
		$limit->add('tests',$test);
	}
	$model->tests($limit->tests);  	
	&normalizeToBaseUnit($model);
	
	foreach my $wafno (sort {$a<=>$b} keys %{$$td{$lotno}}) {
		my $wafer = $model->find('wafers', {number=>$wafno});
		unless (defined $wafer){
			$wafer = new_wafer( { number => $wafno } );
			if ($header->SOURCE_LOT ne "") {
				$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
				$pplogger->setWaferFlag(1);
			}
			$model->add('wafers',$wafer);
		}	
		foreach my $partno (sort {$a<=>$b} keys %{$$td{$lotno}{$wafno}}) {
			$header->LOT($lotno);
			$header->EQUIP6_ID($facility);
			$header->CFG_TESTER_TYPE($cfg_tstr_typ);
			$header->PROGRAM($$td{$lotno}{$wafno}{$partno}{TPNAME});
			$header->REVISION($$td{$lotno}{$wafno}{$partno}{TPREV});
			$header->PROGRAM_CLASS(1);
			$header->PRODUCT($$td{$lotno}{$wafno}{$partno}{PROD});
			$header->START_TIME($file_time);
			$header->END_TIME($file_time);

			my $die = $wafer->find('dies',{partid=>$partno});
			unless (defined $die){
				$die = new_die( { partid => $partno } );
				$die->partid($partno);
				$die->soft_bin($$td{$lotno}{$wafno}{$partno}{SBIN});
				$wafer->add('dies',$die);			
			}
			my $addr = $$td{$lotno}{$wafno}{$partno}{RESULT};
			for (my $i=0; $i<=$#$addr; $i++){
				$die->add('result', repNA(trim($$addr[$i])) );
			}
		} #end of loop (PARTNO)
		
		#insert bins
		foreach my $binno (sort {$a<=>$b} keys %{$$sbr{$lotno}{$wafno}}) {
			my $bin = $wafer->find('bins', {number=>$binno});
			unless (defined $bin) {
				$bin = new_bin;
				$wafer->add( 'bins',$bin);
			}
			$bin->number($binno);
			$bin->name("BIN_".$binno);
			$bin->PF($$sbr{$lotno}{$wafno}{$binno}{PF});
			$bin->count($$sbr{$lotno}{$wafno}{$binno}{CNT});
		}
		
	} # end of loop (WAFER)

	$pplogger->setModelHeader($model);

	#if (!($hOptions{NOLOOKUP})) {
	#	unless ( $header->populateMeta ){
	#		$wr->noMeta(1);
        #	}
	#}	

	unless ( $header->populateMeta ){
		if (!($hOptions{NOSANDBOX})){
			$wr->noMeta(1);
		}
		else {
			WARN("File was not sandboxed. Argument was enabled.");
		}
	}

	$wmap = $model->updateWMap;
        unless ( ! $wmap->isEmpty ){
                #$wr->wmapIsEmpty(1);
		if (!($hOptions{NOSANDBOX})){
			$wr->wmapIsEmpty(1);
		}
		else {
			WARN("File was not sandboxed. Argument was enabled.");
		}
                $reglim_flg = "N";
        }
        unless ( $wmap->confirmed ){
        	#$wr->noWMap(1);
		if (!($hOptions{NOSANDBOX})){
			$wr->noWMap(1);
		}
		else {
			WARN("File was not sandboxed. Argument was enabled.");
		}
                #$reglim_flg = "N";
        }
	$model->updateProgram("MAP_PGM");

	my $formatter = new_iff_formatter(
        {   model  => $model,
            writer => $wr
        }
        );

	$formatter->dataItems([qw/partid soft_bin/]);
        $formatter->printPar_v3($lotno);

	#if ($reglim_flg eq "Y") {
	#	if ($model->isLimitNew){
	#		$limit->copyHeader($header);
	#		$limit->conditionNames([qw/testCond/]);
	#		$model->limit($limit);
	#		$model->buildLimit;
       	#		$formatter->printLimit;
	#		$model->limit->registerRefdb;
	#	}
	#}
	#else {	
		$limit->copyHeader($header);
		$limit->conditionNames([qw/testCond/]);
		$model->limit($limit);
		$model->buildLimit;
		$formatter->printLimit;
	#}	
	
} #end of loop (LOT) 

dpExit(0);
