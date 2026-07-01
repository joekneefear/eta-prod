# SVN $Id: Tmt.pm 2512 2019-11-13 07:42:09Z dpower $


=pod

=head1 SYNOPSIS
lotid
instantiate and use its method/subroutine and attributes.

=head1 DESCRIPTIONS

B<This script> TMT parser module.

=head1 AUTHOR

B<hiroshi>

=head1 CHANGES

# 2015-May-22  jgarcia : Modified to get TP revision from first SW Bin name, if not available, use the TP rev in TP name if availabe, otherwise assign 'N/A'.
# 2015-May-25  jgarcia : Modified process Hana's test flow from filename
# 2015-Jun-04  jgarcia : Added to received site argument on readFile method/subroutine.
# 2015-Jun-04  jgarcia : Used the passed site info to determine how to get the lotid, test flow in each site and how data columns are located.
# 2015-Jun-04  jgarcia : Added to initialize forSBflag attibute/instance variable in the model constructor declaration.
# 2015-Jun-04  jgarcia : Added to process test flow code and lotid from the filename based on each site.
# 2015-Jun-04  jgarcia : Used IO::File module's getline method to traverse the file line by line on SPD and LSR file.
# 2015-Jun-04  jgarcia : Modified how SPD file is parsed[ dont make use fixed line number indicator to get the needed information/data ].
# 2015-Jun-04  jgarcia : Modified to handle STD files in each site that have different format structure.
# 2015-Jun-04  jgarcia : Modified to use Module to get its appropriate test_flow mode and if for sandbox based on test_flow code.(code is made ready to use of test flow
#                        in reference file style).
# 2015-Jun-04  jgarcia : Modified to get lotid inside the file for cpft, pmft, and szft. if not available or applicable, use from the filename.
# 2015-Jun-04  jgarcia : Modified to get testplan revision in each site which is located differently.
#	2015-Jun-04	 jgarcia : Modified to terminate the processing if there is no REVISION or INVALID REVISION by calling dpExit;
#												 This is to make sure the limmit file will not be created, and no program  name will be registered
#												 to pp_limit.. after all we will not load iff and limit file with NO REvision or have invalid one.
# 2015-Jun-06  jgarcia : Added to capture Loardboard and Probecard if available and load it if NOT equal to NODATA.
# 2015-Jun-07  jgarcia : Added support to process hana_cn_ft_tmt files.
# 2015-Jun-11  jgarcia : Enhanced regex to match SRxx|Sxx variants of revision.
# 2015-Jun-16  jgarcia : modified to support gem_cn_ft_tmt site
# 2015-Jul-02  jgarcia : modified to support gem_cn_ft revision as well as cebu.
# 2015-Jul-27  jgarcia : updated to check Program lenght if more than 35 chars and truncate if necessary.
# 2015-Jul-27  jgarcia : get lotid and test flow code for atec_ph_ft inside the file. not from the filename..
# 2015-Jul-31  jgarcia : fixed bug >> test program greater thatn 35 char, the iff is not going to stage_sandbox.
# 2015-Aug-07  jgarcia : skipped row data that have 0 or 0.0000 test result value specifically.
# 2015-Aug-26  gilbert : uppercase the lot id.
# 2015-Sep-10  jgarcia : parse hardware bin and add to $wafer->hbin
# 2015/09/15  jgarcia : modified to parse part data properly. fixed bug -> generates iff with blank DATA section. no part data.
# 2015/09/16  jgarcia : transfered checking in each site's program name length, revision, lotid, test flow mode and code, and etc to preprocessor script -> fcs_tmt_IFF.pl 
# 2015-10-23  jgarcia : used the second datetime in LSR as a end_time.
# 2015-10-23  jgarcia : dont convert to locatime, use start and endtime as parsed from the raw files.
# 2016-01-25  jgarcia : fixed gtk_ft_tmt's data value not aligned to test parameter.
# 2016-01-27  jgarcia : modified to replace spaces to single underscore, replace open and close parenthesis to an underscore in Program name. - GTK Taiwan only.
# 2016-01-27  jgarcia : Remove last trailing underscore in Program name.  
# 2016-Apr-21 gilbert : Test Part 1 of the datalog is Bin 1 create a reference of units and used it if Bin is not 1 in Test Part 1. faild if Part test data is 10 or less and Send to Rework direcotry for Test Part 1 of the datalog is NOT Bin 1 and no reference file found.
# 2016-Sep-21 Send to sandbox if Part tested data is 10 or less.
# 2017-Apr-24 jgarcia : modified to not call dpExit when there is incosistent UNITS issue with the raw file. just add the message to $mdoel->misc and return the $model.
# 2019-Oct -28 kgabato: modified Loadboard to Loadboard:
#  2021-Apr-13 jgarcia : modified to receive a ref file folder location from the caller  instead of hardcoding it.
#  2023-May-16 eric	: modified how to get exact lotid in filename for utac
#  2023-May-17 eric	: modified to get lotid from LSR for utac
#  2023-May-23 eric	: modiifed to parse operator

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut


package PDF::Parser::Tmt;
use strict;
#use diagnostics;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use v5.10;
use PDF::Util::TestFlowCodeUtility qw/getTestFlowCodeMode/;
use IO::File;
use File::Basename;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

my $attr = [qw/SPD LSR moveLSR/];

my $testProgram = "";

sub array {
	return qw//;
}

__PACKAGE__->mk_accessors( @$attr, array );

sub dpExitError {
	my $self    = shift;
	my $message = shift;
	if ( $self->moveLSR ) {
		move $self->LSR,
		( dirname $self->LSR )
		. "/NotProcessed/"
		. ( basename $self->LSR );
	}
	dpExit( 1, $message );
}

sub readFile {
	my $self = shift;
	my $SPD  = shift;
	my $site = shift;
	my $ref_dir = shift; 
	my $LSR  = $SPD;
	if ($SPD =~ /\.SPD$/) {
		$LSR =~ s/\.SPD$/\.LSR/;
	} elsif ($SPD =~ /\.spd$/) {
		$LSR =~ s/\.spd$/\.lsr/;	
	}
	#$LSR =~ s/\.SPD$/\.LSR/;
	$self->LSR($LSR);

	INFO("SPD:$SPD");
	INFO("LSR:$LSR");
	my $header = new_headerLong;
	my $wmap   = new_wmap;
	my $model  = new_model(
	{   header => $header,
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
	my $filename = basename $SPD;
	my @temp = split( /_/, $filename );
	my $gemLotid = "";


	if ( $site eq "gtk_tw_ft" ) {
		$header->LOT(uc( $temp[0] ));
		$testMode = $temp[3];
		#dpExitError("Unexpected filename $filename");
	}
	elsif ( $site =~ /hana/ ) {
		my $hanaLotid = $temp[0];
		if (length($hanaLotid) > 10) {
			$hanaLotid = substr($hanaLotid, 0 , 10);
		}
		$header->LOT(uc( $hanaLotid ));
		$testMode = $temp[2];
	}
	elsif ( $site eq "utac_th_ft" ) {
		#$header->LOT(uc( $temp[1] ));
		#$testMode = $temp[2];
		#dpExitError("Unexpected filename $filename");
	}
	elsif ( $site eq "atec_ph_ft" ) {

		#$header->LOT(uc( $temp[4] ));
		#$testMode = $temp[6];
	}
	elsif ( $site eq "gem_cn_ft" ) {
		foreach my $element (@temp) {
			trim($element);
			if($element =~ /^GM\d{1,7}[a-zA-Z]{1}/) {
				$header->LOT(uc( $element ));
			}
		}
	}


	my ( $date_SPD, $date_LSR );
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
	my $cpftRev = "";
	my $cpftLotid = "";
	my $szftLotid = "";
	my $pmftLotid = "";
	my $gemCNftTP = "";
	my $gemCNftRev = "";
	my @testNum = ();
	my @testName = ();
	my @testHSL = ();
	my @testLSL = ();
	
	my $LSRFileHandle = IO::File->new($LSR) or dpExitError("Failed to open LSR file $LSR");
	my $LSRLineFlag = 0;
	my $line = "";
	#while (<FH_LSR>) {
	while($line = $LSRFileHandle->getline) {
		$num++;

		
		
		$line =~ s/\cM|\"//g;
		chomp($line);
		#print "$line\n" if $line =~ /Lot\s+ID/i;
		if($site ne "cpft_tmt" || $site ne "gem_cn_ft") {

			if ( $line =~ /^Test Program\s*: (.+) Total/ ) {
				
				my $program = trim($1);
				#print "$program\n"; 
				#my $rev;
				if ($program =~ /(.+)_rev(\S*)\s{0,1}(.*)/i){
					$program = $1.$3;
					$rev = trim($2);
					if($rev ne "" || defined($rev))  {
						INFO("TP Rev also available in TP Name, If Tp rev is available in SW Bin, this TP Rev will not be used, TP Rev from SW Bin will prevail!!!");
						
						$tpRevInTPNameFlag = "Y";
					}
				}
				elsif ($program =~ /.+_.+_SR(\d+)_.+/i || $program =~ /.+_SR(\d+)_.+/i || $program =~ /.+_.+_S(\d+)_.*/i || $program =~ /.+_S(\d+)_.+/i) {
	
					$rev = trim($1);
	
					if($rev ne "" || defined($rev))  {
						INFO("TP Rev also available in TP Name with SR variant, if TP rev is available in SW Bin, this will not be used, TP Rev from SW Bin will prevail!!!");
						$tpRevInTPNameFlag = "Y";
					}
				}
				if ($site eq "gtk_tw_ft") {
					$program =~ s/\s+|\(|\)/_/g;
					$program =~ s/_+/_/g;
				}
				$header->PROGRAM($program);
				#$header->REVISION( $rev);
			}
		}

		if($site eq "cpft_tmt") {
	
			if ( $line =~ /^Test\s+Program\s+:(.*?)Total\s+:\s+\d+/ ) {
				$cpftTP = trim($1);
				my($dmp1, $dmp2) = split /\s+/, $cpftTP;
				#$dmp2 =~ s/[^a-zA-Z0-9]//g;
				$cpftRev = chop($dmp1);
				trim($cpftRev);
				$cpftTP = "${dmp1}_${dmp2}";
				$header->PROGRAM($cpftTP);
				$header->REVISION( $cpftRev);
				
			}
		}
		
		if($site eq "gem_cn_ft") {
			if ( $line =~ /^Test\s+Program\s+:(.*?)Total\s+:\s+\d+/ ) {
				$gemCNftTP = trim($1);
				my($dmp1, $dmp2) = split /\s+/, $gemCNftTP;
				#$dmp2 =~ s/[^a-zA-Z0-9]//g;
				$gemCNftRev = chop($dmp1);
				trim($gemCNftRev);
				$gemCNftTP = "${dmp1}_${dmp2}";
				$header->PROGRAM($gemCNftTP);
				$header->REVISION( $gemCNftRev);
			}
		}
		
		if ( $line =~ /Lot\s+id\s+\:(.*?)\s+?Total\s+Fail\s+:/i || $line =~ /Lot\s+id\s+\:(.*?)\_?Total\s+Fail\s+:/i){ # && ($site =~ /cpft_tmt|pmft_tmt|szft_tmt/)) {
			$lotid  = uc(trim($1));
			if ($site =~ /cpft_tmt|pmft_tmt|szft_tmt/) {
				if($lotid eq "") {
					INFO("LOTID is not available inside the file fo $site LSR file, will use LOTID in filename.!!!");
					$lotid = $temp[0];
					#$cpftLotid = $lotid;
					#$szftLotid = $lotid;
					#$pmftLotid = $lotid;
					$header->LOT( $lotid );
				}
				else {
					given($site) {
						when('pmft_tmt') {
							($lotid, $dmp1, $dmp2) = split /\_/, $lotid;
							$lotid  = substr($lotid,0,10) if $lotid =~ /^H|^P/i;
							#print "lotid=$lotid\n";
							#$pmftLotid = $lotid;
							$header->LOT( $lotid );
						}
						when('cpft_tmt') {
							($lotid, $dmp1, $dmp2) = split /\_/, $lotid;
							#$cpftLotid = $lotid;
							$header->LOT( $lotid );
						}
						when('szft_tmt') {
							($lotid, $dmp1, $dmp2) = split /\_/, $lotid;
							$lotid =~ s/AO/A0/ig;
							if (($lotid =~ /^A0|^X\d+[A-Z]$/i) && (length($lotid) > 10)) {
								INFO("LOTID>>$lotid<< length is more than 10 chars. last char will be stripped off to make it ten chars!!!"); 
								$lotid = substr($lotid,0,10) if $lotid =~ /^A0|^X\d+[A-Z]$/i && length($lotid) > 10;
								INFO("LOTID to be matched in Reference DB is now >>$lotid<< after removing the last char!!!");
							}
							#$szftLotid = $lotid;
							$header->LOT( $lotid );
						}
					}
				}
				
			}
			elsif ($site =~ /atec_ph_ft/) {
				($lotid, $dmp1, $dmp2) = split /\_/, $lotid;
				$lotid  = substr($lotid,0,10);
				$header->LOT(uc( $lotid ));
				$testMode = $dmp2 if $dmp2 =~ /^P\d{1,}$|^R\d{1,}$|^Q\d{1,}$/;
				$testMode =~ s/^\s+|\s+$//g;
			}
			elsif ($site =~ /utac_th_ft/) {
				my @arr = split /\_/, $lotid;
				my $arrLen = scalar @arr;
				INFO ("Parsed LSR Lot Id seciton = @arr");
				if ($arrLen == 3) {
					$header->LOT(uc($arr[1]));
					$testMode = uc($arr[2]);
				}
				else {
					$header->LOT(uc($arr[0]));
					$testMode = uc($arr[1]);
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
		if ( $line =~ /^Operator\s*: (\S+) /) {
			$header->OPERATOR( trim( $1 ) );
		}
		if ( $num == 12
		and $line =~
		/\w+?\,\s+(\w{3,})\s+(\d{1,})\,\s+(\d{2,})\s+(\d{1,})\:(\d{1,})\:(\d{1,})/
		)
		{
			my ($setupDate, $endDate) = split /\//, $line;
			$date_LSR = formatDate($endDate);
			DEBUG( "DATE in LSR = " . $date_LSR );
		}
		$section = "BINS" if ($line =~ /SW Bins/);
		$section = "End"  if ($line =~ /SW Site/);
		if ( $section eq "BINS" ) {
			
			my @dummyLineArray = split /\%\s+/, $line;
			#print"@dummyLineArray\n";
			#INFO($dummyLineArray[1]);
			$dummyLineArray[1] =~ s/$\s+|\s+$//g;
			#print "$dummyLineArray[1]\n";

			#if ( $line =~ /^\[(\d+)\](.+?)(\d+)\s+(\d+\.\d+)\s/) {
			if ( $dummyLineArray[0] =~ /^\[(\d+)\](.+?)(\d+)\s+(\d+\.\d+)\s/) {
				#INFO("INSIDE SBIN PROC");
				#print "$line>>>BIN SEction\n";
				my $bin = new_bin;
				$bin->number( $1 + 0 );
				$binName = trim($2);
				$binCount = $3;
				#print "######$bin->{number}\t$binName\t$binCount#####\n";
				
				### get TP Rev from the first SWBin name : jgarcia 2015-May-22 PHT ###
				if($site ne "cpft_tmt") {
	
					if($binName =~ /Rev(\S*)|_v(\S*)/i && $bin->number == 1) {
						#my ($dmp, $revDmp) = split /\_/, $binName;
						$revDmp1 = trim($1);
						$revDmp2 = trim($2);
						$revDmp1 =~ s/[^a-zA-Z0-9\.\-]//g;
						$revDmp2 =~ s/[^a-zA-Z0-9\.\-]//g;
						if($revDmp1 ne "") {
							INFO("REV = $revDmp1 >> from the first SW Bin [REVxxx variant]");
							$header->REVISION($revDmp1);
							$tpAssignedFlag = "Y";
						}
						elsif ($revDmp1 eq "" && $revDmp2 ne "") {
							INFO("REV = $revDmp2 >> from the first SW Bin [Vxxx variant]");
							$header->REVISION($revDmp2);
							$tpAssignedFlag = "Y";
						}
						else{
	
							WARN("TP Rev is not available in SW Bin, will be using TP Name Rev info if available");
						}
					}
					if ($tpAssignedFlag ne "Y" && $tpRevInTPNameFlag eq "Y") {
						if($rev ne "" && $bin->number == 1){
							INFO("Using TP revision at TP Name, TP rev in first SW Bin is not available");
							$header->REVISION($rev);
						}
					}
				}


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
				$wafer->add( 'sbins', $bin );
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
	undef $LSRFileHandle;
	$num = 1;
	my $fileHandle = IO::File->new($SPD) or dpExitError("Failed to open SPD file $SPD", $SPD);
	
	my $lineFlag = 0;
	my $dataValue1 = 0;
	my $dataValue2 = 0.0000;
	my $dataValue3 = "";
        my $unit_ref = "";
        my $test_unit_flg = "";
        my $unit_cnt = "";
        my $part_cnt = "";
	while (my $line = $fileHandle->getline) {
		 $line =~ s/[\cM|\"]//g;
		 
		 #if($line !~ /Date|Test\,?/){
			#$line =~ s/\s+//g;
		 #}
     $line =~ s/\s+//g if $line !~ /Date/i;

		my (@lineDumpArray) = split /\,/, $line;
		DEBUG("num in SPD = $num");
		if ($lineFlag == 7 && $lineDumpArray[0] =~ /\d/ && $lineDumpArray[1] =~ /\d/) {
			$part_cnt++;
			given($site) {
				when('atec_ph_ft') {
					my @data = map { trim($_) } (split(',',$line));
					my $numD = scalar(@data);
					my @test = @data;
          splice @test, 0, 3;
          my $skipRowData = 0;
          if (@test == grep { ($_ == $dataValue1) || ($_ == $dataValue2) } @test) {
 						$skipRowData = 1;
					}
					next if $skipRowData == 1;
					my $die  = new_die;
					$die->partid( $data[0] );
					$die->soft_bin( $data[1] );
					$die->hard_bin( $data[1] );
					$die->site( 1 );
					$die->result ( @data[ 3 .. $numD - 1 ]);
					$wafer->add( 'dies', $die );
				}
				when('gtk_tw_ft') {
					my @data = map { trim($_) } (split(',',$line));
					my $numD = scalar(@data);
					my @test = @data;
          splice @test, 0, 3;
          my $skipRowData = 0;
          if (@test == grep { ($_ == $dataValue1) || ($_ == $dataValue2) } @test) {
 						$skipRowData = 1;
					}
					next if $skipRowData == 1;
					my $die  = new_die;
					$die->partid( $data[0] );
					$die->soft_bin( $data[1] );
					$die->hard_bin( $data[1] );
					$die->site( int( $data[3] ) );
					$die->result ( @data[ 3 .. $numD - 1 ]);
					$wafer->add( 'dies', $die );
				}
				default {
					my @data = map { trim($_) } split(",",$line);
					my $numD = scalar(@data); 
					my @test = @data;
          splice @test, 0, 2;
          my $skipRowData = 0;
          if (@test == grep { ($_ == $dataValue1) || ($_ == $dataValue2) } @test) {
 						$skipRowData = 1;
					}
					next if $skipRowData == 1;
					my $die  = new_die;
					$die->partid( $data[0] );
					$die->soft_bin( $data[1] );
					$die->hard_bin( $data[1] );
					$die->site( 1 );
					$die->result ( @data[ 2 .. $numD - 1 ]);
					$wafer->add( 'dies', $die );

				}
			}
		}
		elsif ($line =~ m|^Date:,(\d{2})/(\d{2})/(\d{2}) (\d{2}):(\d{2}):(\d{2}),|) {
			
			$date_SPD
			= "20"
			. $3 . "/"
			. $1 . "/"
			. $2 . " "
			. $4 . ":"
			. $5 . ":"
			. $6;
			DEBUG( "Date in SPD = " . $date_SPD );
		
			### Check PartID 1 is BIN 1 ###
		        my $grep_result = `grep -iA 1 "^Serial" $SPD | grep "^1,1,"`;
                        $test_unit_flg = "Y" if $grep_result ne "";
			$lineFlag = 1;
		}
		elsif ($line =~ /Loadboard:/i) {
			
			trim($lineDumpArray[1]);
			if($lineDumpArray[1] !~ /NODATA/i) {
				$header->EQUIP4_ID($lineDumpArray[1]);
			}
			$lineFlag = 1;
		}
		elsif ($line =~ /Probecard/i) {
			trim($lineDumpArray[1]);
			if($lineDumpArray[1] !~ /NODATA/i) {
				$header->EQUIP3_ID($lineDumpArray[1]);
			}
			$lineFlag = 1;
		}
		elsif ( $lineFlag == 1 && $line =~ /\d+\.\d+\./ ) {
			my $t = 0;
			given($site) {
				when('atec_ph_ft') {
		
					for (my $i = 3; $i <= $#lineDumpArray; $i++) {
						my $test = new_test;
						$test->number($lineDumpArray[$i]);
						$model->add( 'tests', $test );
					}
		
				}
				when('gtk_tw_ft') {
		
					for (my $i = 3; $i <= $#lineDumpArray; $i++) {
						my $test = new_test;
						$test->number($lineDumpArray[$i]);
						$model->add( 'tests', $test );
					}
				}
				default {
						for (my $i = 2; $i <= $#lineDumpArray; $i++) {
						my $test = new_test;
						$test->number($lineDumpArray[$i]);
						$model->add( 'tests', $test );
					}
				}
			}
			$lineFlag = 2;
		}
		elsif ($lineFlag == 2 && $line =~ /[A-Z]/i ) {
			my $t = 0;
		
			given($site) {
				when('atec_ph_ft') {
					for (my $i = 3; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->name($lineDumpArray[$i]);
						#print "T=>$t";
						$t++;
					}
				}
				when('gtk_tw_ft') {
					for (my $i = 3; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->name($lineDumpArray[$i]);
						$t++;
					}
				}
				default {
					for (my $i = 2; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->name($lineDumpArray[$i]);
						$t++;
					}
				}
			}
			$lineFlag = 3;
		
		}
		elsif ($lineFlag == 3 && $line =~ /\,|[0-9\.]/i) {
			my $t = 0;
		
			given($site) {
				when('atec_ph_ft') {
					for (my $i = 3; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->group($lineDumpArray[$i]);
						$t++;
					}
				}
				when('gtk_tw_ft') {
					for (my $i = 3; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->group($lineDumpArray[$i]);
						$t++;
					}
				}
				default {
					for (my $i = 2; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->group($lineDumpArray[$i]);
						$t++;
					}
				}
			}
			$lineFlag = 4;
		
		}
		elsif ($lineFlag == 4 && $line =~ /none\,|\,\-?\d+\.\d+\,|\,\-?\d+\,|^\,+\-\d+/i) {
			my $t = 0;
		
			given($site) {
				when('atec_ph_ft') {
					for (my $i = 3; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->HSL($lineDumpArray[$i]);
						$t++;
					}
				}
				when('gtk_tw_ft') {
					for (my $i = 3; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->HSL($lineDumpArray[$i]);
						$t++;
					}
				}
				default {
					for (my $i = 2; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->HSL($lineDumpArray[$i]);
						$t++;
					}
				}
			}
			$lineFlag = 5;
		
		}
		elsif ($lineFlag == 5 && $line =~ /none\,|\,+\-?\d+\.\d+\,|\,+\-?\d+\,/i) {
			my $t = 0;
		
			given($site) {
				when('atec_ph_ft') {
					for (my $i = 3; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->LSL($lineDumpArray[$i]);
						$t++;
					}
				}
				when('gtk_tw_ft') {
					for (my $i = 3; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->LSL($lineDumpArray[$i]);
						$t++;
					}
				}
				default {
					for (my $i = 2; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->LSL($lineDumpArray[$i]);
						$t++;
					}
				}
			}
			$lineFlag = 6;
		
		}
		elsif ($lineFlag == 6 &&  $line =~ /Serial\#/i) {
               
 		      #my $directory    = dirname($SPD);
		       #  $directory    =~/\/data\/(.*)\//;
		      #my $dir          = $1;
		      #my (@env)        = split /\//, $dir;
	              #my $ref_dir      = "/data/${env[0]}/TP";
                      my $tp_name   = $header->PROGRAM;
                      my $tp_rev    = $header->REVISION; 
                      my $ref_file  = "${ref_dir}/${tp_name}_${tp_rev}.TXT";
                      my @new_units = ();
                      if (! -e "$ref_file" && $test_unit_flg eq "")
                      {
                      	 $model->misc("UNITS Inconsistent:Test Part 1 of the datalog is NOT Bin 1 and no reference file found..Sending to Rework directory.");
                         #dpExit( 4, "UNITS Inconsistent:Test Part 1 of the datalog is NOT Bin 1 and no reference file found..Sending to Rework directory.");
                         return ($model);
                      }
		      ### use reference unit file if partid 1 is not bin 1 ###
                      if ( -e "$ref_file" && $test_unit_flg eq "")
                      {
                         open FH, $ref_file or die "can't open $ref_file\n";
                             my $tmp_line=<FH>;
                                 chomp($tmp_line);
                             my ($dump, $tmp_units) = split /\=/, $tmp_line;
                                 @new_units         = split /\,/, $tmp_units;
                         close(FH);

		
			   my $t = 0;
			   given($site) {
				when('atec_ph_ft') {
					for (my $i = 1; $i <= $#new_units; $i++) {
						$model->tests->[$t]->units($new_units[$i]);
						$t++;
					}
				}
				when('gtk_tw_ft') {
					for (my $i = 1; $i <= $#new_units; $i++) {
						$model->tests->[$t]->units($new_units[$i]);
						$t++;
					}
				}
				default {
					for (my $i = 1; $i <= $#new_units; $i++) {
						$model->tests->[$t]->units($new_units[$i]);
						$t++;
					}
				}
			   }
                       }
	               else {

			   my $t = 0;
			   given($site) {
				when('atec_ph_ft') {
					for (my $i = 3; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->units($lineDumpArray[$i]);
						$t++;
						$unit_ref .= "\,$lineDumpArray[$i]";
                                                $unit_cnt++;
					}
				}
				when('gtk_tw_ft') {
					for (my $i = 3; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->units($lineDumpArray[$i]);
						$t++;
						$unit_ref .= "\,$lineDumpArray[$i]";
                                                $unit_cnt++;
					}
				}
				default {
					for (my $i = 2; $i <= $#lineDumpArray; $i++) {
						$model->tests->[$t]->units($lineDumpArray[$i]);
						$t++;
						$unit_ref .= "\,$lineDumpArray[$i]";
                                		$unit_cnt++;
					}
				}
			   }


		       }
			$lineFlag = 7;
	                &create_ref_units($unit_cnt, $tp_name, $tp_rev, $date_SPD, $SPD, $unit_ref, $ref_dir) if $test_unit_flg eq "Y";	
		}
		$num++;
	}
	#close FH_SPD;
	undef $fileHandle;
	
        if ( $part_cnt == 0) {
             dpExit( 1, "Part test data is 0 .");
        }
        if ( $part_cnt <= 10) {
             WARN("Part test data is 10 or less.Sending to sandbox...");
	     $model->forSBflag( 1 );
        }

	my $epoch_SPD = parseDate($date_SPD);
	my $epoch_LSR = parseDate($date_LSR);
	if ( $epoch_SPD > $epoch_LSR ) {
		$header->START_TIME($date_LSR);
		$header->END_TIME($date_SPD);
	}
	else {
		$header->START_TIME($date_SPD);
		$header->END_TIME($date_LSR);
	}

sub create_ref_units
{
       my $tp_cnt       = shift;
       my $tp_name      = shift;
       my $tp_rev       = shift;
       my $date_time    = shift;
       my $file_name    = shift;
       my $ref_units    = shift;
       my $ref_dir      = shift;
       my($directory, $filename) = $file_name  =~m/(.*\/)(.*)$/;
          $directory    =~/\/data\/(.*)\//;
       my $dir          = $1;
       my (@env)        = split /\//, $dir;
      # my $ref_dir      = "/data/${env[0]}/TP";
       my $ref_filename = "${ref_dir}/${tp_name}_${tp_rev}.TXT";

       system "mkdir $ref_dir" if ! -e $ref_dir;

       if ( -e $ref_filename ) {
            open FH, $ref_filename or die "can't open $ref_filename\n";
               my $tmp_line=<FH>;
               chomp($tmp_line);
               my ($cnt, $dump) = split /\:/, $tmp_line;
            close(FH);
            unlink $ref_filename if ($tp_cnt > $cnt);
       }
   
       open REF, ">$ref_filename" or die "Failed to create $ref_filename. $!\n" if ! -e $ref_filename;
       print REF "${tp_cnt}:${tp_name}_${tp_rev} ${date_time} ${filename}=${ref_units}";
       close(REF);

}
	
$testProgram = $header->PROGRAM;
if ($testProgram =~ /\_$/) {
	$testProgram =~ s/_$//g;
}
$header->PROGRAM($testProgram);
$header->INDEX1($testMode);
return ($model);
}
1;
