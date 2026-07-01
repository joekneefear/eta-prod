=pod

=head1 SYNOPSIS

instantiate and use its method/subroutine and attributes.

=head1 DESCRIPTIONS

B<This script> TMT FT Cebu LSR file parser module.

=head1 AUTHOR

B<junifferallan.garcia@fairchildsemi.com>

=head1 CHANGES
2015/08/18	jgarcia	: capitalized the lotid.
2015-Sep-14  jgarcia : parse hardware bin and add to $wafer->hbin
2015-10-23  jgarcia : used the second datetime in LSR as a end_time.
2015-10-23  jgarcia : dont convert to locatime, use start and endtime as parsed from the raw files.
2017-Jun-13 gilbert : get the test plan revision in bin 1 for new test plan or with ASL1K




=head1 LICENSE

(C) Fairchild 2015 All rights reserved.

=cut

package PDF::Parser::TMTLSR;
use strict;
#use diagnostics;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use v5.10;
use PDF::Util::TestFlowCodeUtility qw/getTestFlowCodeMode/;
use IO::File;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;
use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

my $attr = [qw/LSR/];

sub array {
	return qw//;
}

__PACKAGE__->mk_accessors( @$attr, array );

sub readLSR {
	
	my $self = shift;
	my $LSR = shift;
	my $site = shift;
	
	INFO("LSR:$LSR");
	my $header = new_headerLong;
	my $wmap   = new_wmap;
	my $model  = new_model(
		{ header => $header,
			wmap   => $wmap,
			misc   => {},
			dataSource => 'TMT',
			forSBflag => ''
		}
	);
	my $wafer = new_wafer;
	$model->add( 'wafers', $wafer );
	
	my $testMode = "";
	my $mode = "";
	my $sandBoxFlag = 0;
	my $testProgramTruncateSandBoxFlag = 0;
	my $filename = basename $LSR;
	my @temp = split( /_/, $filename );
	my $date_LSR;
	my $endDate_LSR;
	my $startDate_LSR;
	my $section;
	my $num = 0;
	my $tpRevInTPNameFlag = "N";
	my $tpAssignedFlag = "";
	my $rev = "";
	my ( $dmp1, $dmp2 ) = "";
	my ( $revDmp1, $revDmp2 ) = "";
	my $binCount = "";
	my $binName = "";
	my $lotid = "";
	my $cpftTP = "";
	my $tp_rev_new = "";
	my $cpftTP_orig = "";
	my $cpftRev = "";
	my $cpftLotid = "";
	
	$num = 1;
	
	my $LSRFileHandle = IO::File->new($LSR) or dpExitError("Failed to open LSR file $LSR");
	my $LSRLineFlag = 0;
	my $line = "";
	#while (<FH_LSR>) {
	while($line = $LSRFileHandle->getline) {
		$num++;

		$line =~ s/\cM|\"//g;
		chomp($line);
		#print "$line\n";# if $line =~ /Lot\s+ID/i;
		
		if ( $line =~ /^Test\s+Program\s+:(.*?)Total\s+:\s+\d+/ ) {
			$cpftTP = trim($1);
			$cpftTP_orig = $cpftTP;
			my($dmp1, $dmp2) = split /\s+/, $cpftTP;
			#$dmp2 =~ s/[^a-zA-Z0-9]//g;
			if ($cpftTP_orig =~/ASL1K/i){

			}
			else {
			$cpftRev = chop($dmp1);
			}
			trim($cpftRev);
			$cpftTP = "${dmp1}_${dmp2}";
		}
		if ( $line =~ /Lot\s+id\s+\:(.*?)\s+?Total\s+Fail\s+:/i || $line =~ /Lot\s+id\s+\:(.*?)\_?Total\s+Fail\s+:/i){ # && ($site =~ /cpft_tmt|pmft_tmt|szft_tmt/)) {
			$lotid  = uc(trim($1));
			if ($site eq 'cpft_tmt') {
				if($lotid eq "") {
					INFO("LOTID is not available inside the file for $site LSR file, will use LOTID in filename.!!!");
					$lotid = $temp[0];
					$cpftLotid = uc($lotid);
				}
				else {
					given($site) {
						when('cpft_tmt') {
							($lotid, $dmp1, $dmp2) = split /\_/, $lotid;
							$cpftLotid = uc($lotid);
							#$header->LOT( $lotid );
						}
					}
				}
			}
		}
		if ( $line =~ /Total\s+: (\d+)/) {
			$header->DEVICE_COUNT ($1);
		}
		if ( $line =~ /^Computer\s*: (\S+) /) {
			$header->EQUIP1_ID( trim( 'TMT ' . $1 ) );
		}
		if ( $line =~ /^Handler\s*: (\S+) /) {
			$header->EQUIP5_ID( trim( $1 ) );
		}
		#if ( $num == 12 and $line =~ /\w+?\,\s+(\w{3,})\s+(\d{1,})\,\s+(\d{2,})\s+(\d{1,})\:(\d{1,})\:(\d{1,})/ ) {
		if ( $line =~ /\w+?\,\s+(\w{3,})\s+(\d{1,})\,\s+(\d{2,})\s+(\d{1,})\:(\d{1,})\:(\d{1,})/ ) {
			my ($setupDate, $endDate) = split /\//, $line;
			$endDate_LSR = formatDate($endDate);
			$startDate_LSR = formatDate($setupDate);
			DEBUG( "DATE in LSR start and end = " . $startDate_LSR ."\t" . $endDate_LSR );
		}
		$section = "BINS" if ($line =~ /SW Bins/);
		$section = "End"  if ($line =~ /SW Site/);
		if ( $section eq "BINS" ) {
			
			my @dummyLineArray = split /\%\s+/, $line;
			$dummyLineArray[1] =~ s/^\s+|\s+$//g;

			#if ( $line =~ /^\[(\d+)\](.+?)(\d+)\s+(\d+\.\d+)\s/) {
				#print "$line>>>BIN SEction\n";
			if ( $dummyLineArray[0] =~ /^\[(\d+)\](.+?)(\d+)\s+(\d+\.\d+)\s/) {

				my $bin = new_bin;
				$bin->number( $1 + 0 );
				$binName = trim($2);
				$binCount = $3;
				###print "######$bin->{number}\t$binName\t$binCount#####\n";
				### get TP Rev from the first SWBin name : jgarcia 2015-May-22 PHT ###
				if ( $binName eq '' ) {
					$binName = "SBIN" . $bin->number;
				}
				$bin->name($binName);
				#print " BINNAME ;>>$binName<<\n";
				#print "BINCOUNT : >>$binCount<<\n";
				$bin->count( $binCount + 0 );
				my $PF = 'F';
				$PF = 'P' if ( $bin->number == 1 );
				$bin->PF($PF);

				$wafer->add( 'bins', $bin );
				if ($binName =~/REV\s?\d/i){
				    $tp_rev_new = $binName;
				    $tp_rev_new =~s/REV//i;
			            if ($cpftTP_orig =~/ASL1K/i) {
				        $cpftRev     = $tp_rev_new;
				    }
				    else {
				       $tp_rev_new = "";
				    }
				}
			}
			
			if($dummyLineArray[1] =~ /\d+\s+\d+\s+\d+\.\d+/) {
				#INFO("INSIDE HBIN PROC");
				my ($number, $value, $dump) = split /\s+/, $dummyLineArray[1], 3;
				my $bin = new_bin;
				$bin->number( $number + 0 );
				$binName = "HBIN" . $bin->number;;
				$binCount = $value;
				$bin->name($binName);
				$bin->count($binCount + 0);
				my $PF = 'F';
				$PF = 'P' if ( $bin->number == 1 );
				$bin->PF($PF);
				$wafer->add( 'hbins', $bin );
			}
			
		}
	}
	#close(FH_LSR);
	undef $LSRFileHandle;
	
	#my $epoch_LSR = parseDate($date_LSR);
	$header->START_TIME($startDate_LSR);
	$header->END_TIME($endDate_LSR);
	
	my $program = "";
	
	given($site) {
		when('cpft_tmt') {
			if($cpftRev eq "") {
					dpExit(1,"INVALID OR NO TESTPLAN REVISION!!!");
			}
			$header->LOT( $cpftLotid );
			#$header->PROGRAM($cpftTP);
			if ( length($cpftTP) > 35 ) {
		        WARN("PROGRAM NAME \"".$cpftTP."\" will be truncated to 35 characters.  Sending to sandbox.");
		        $model->forSBflag( 1 );
		        $program = substr($cpftTP, 1, 35); # Leave enough room for session type
		        		
			} else {
				$program = $cpftTP;
			}
			$header->REVISION($cpftRev);
		}
	}	
	
	if ($cpftTP_orig =~/ASL1K/i && $tp_rev_new eq ''){
	    $cpftRev     = "NA";
	    $header->REVISION($cpftRev);
	}
	if ( $cpftRev eq "NA") {
	   WARN("Test Plan rev set to \"NA\". Not able to get rev.. .Sending to sandbox...");
	   $model->forSBflag( 1 );
	}
	$header->VERSION($VERSION);
	$header->PROGRAM_CLASS(2);
	$header->PROGRAM($program);
	#$header->INDEX1($testMode);
	#$header->INDEX2($mode);
	#
	return ($model);
	
}### end of readLSR method
1;

sub dpExitError {
	my $self    = shift;
	my $message = shift;
	dpExit( 1, $message );
}
