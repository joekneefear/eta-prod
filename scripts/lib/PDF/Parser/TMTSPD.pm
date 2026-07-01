=pod

=head1 SYNOPSIS

instantiate and use its method/subroutine and attributes.

=head1 DESCRIPTIONS

B<This script> TMT Cebu SPD file parser module.

=head1 AUTHOR

B<junifferallan.garcia@fairchildsemi.com>

=head1 CHANGES
2015/08/18	jgarcia	: capitalized the lotid.
2015/08/18 	jgarcia :	if total count of group is not aligned in test param use test param's total count as array index in populating the group.
2015-Aug-26     gilbert : uppercase the lot id.
2015/09/15  jgarcia : modified to parse part data properly. fixed bug -> generates iff with blank DATA section. no part data.
2015-10-28  jgarcia : dont convert to locatime, use start and endtime as parsed from the raw files.
02-Apr-2016 gilbert : Test Part 1 of the datalog is Bin 1 create a reference of units and used it if Bin
                      is not 1 in Test Part 1.
07-Apr-2016 gilbert : Added SPD filename of the created reference unit file.
20-Apr-2016 gilbert : Additional checking on reference unit, faild if Part test data is 10 or less and
                      Send to Rework direcotry for Test Part 1 of the datalog is NOT Bin 1 and no reference file found.
27-May-2016 gilbert : Added cprel
12-Aug-2016 gilbert : Added test_unit_flg is always true for  TMTFT-068|TMTFT-062|TMTFT-073 Cebu FT only
25-Aug-2016 gilbert : fail if Part test data is 10 or less but exclue Rel data.
21-Sep-2016 GilbertM: Send to sandbox if Part test data is 10 or less but exclue Rel data.
27-Oct-2016 jgarcia : remove one of the $ref_dir class variable declaration since it was declared twice with initialization.
27-Oct-2016 jgarcia : check and assign appropriate value to $ref_dir variable depending to what is the $site value.
											--this will fix the bug to the script that won't be able to locate the created reference file.
											  and raise an exception error 4 that will send the file to Rework.
17-May-2017 jgarcia : handle exception raised on line code 318 which caused to exit abnormally and not be able to log vital info like lotid in refdb.pp_log.
08-Jun-2017 gilbert : new program with ASLK1, get the test program revision in its equivalent .LSR file.
											enclose the affected statement in eval.
18-May-2018 eric    : improve tp rev extraction from LSR
23-May-2018 eric    : improve tp rev extraction from LSR
30-May-2018 eric    : improve tp rev extraction from LSR
28-Jan-2020 eric    : fix bug to locate LSR in gz format.
11-Feb-2022 jgarcia : disable searching of lsr file, just assumed that the lsr file will always be in /apps/exensio_data/data/cpft_tmt or
											/apps/exensio_data/data/cpft_tmt/LSR_SPD or /apps/exensio_data/data/cpft_tmt/LSR_SPD/Processed or
											/apps/exensio_data/data/cpft_tmt/LSR_SPD/NotProcessed
										:	check ALS1K tester with the external file so that it can be updated without modifying code.


=head1 LICENSE

(C) Fairchild 2015 All rights reserved.

=cut

package PDF::Parser::TMTSPD;
use strict;
#use diagnostics;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use File::Find;
use v5.10;
use PDF::Util::TestFlowCodeUtility qw/getTestFlowCodeMode/;
use IO::File;
use File::Spec;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;
use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

my $attr = [qw/SPD/];

sub array {
	return qw//;
}

__PACKAGE__->mk_accessors( @$attr, array );

sub readSPD {

	my $self = shift;
	my $SPD  = shift;
	my $site = shift;
	my $ref_dir = shift;
	my $als1kTesterListFile = "${ref_dir}/TESTER.ini";
  my $config = Config::Tiny->read($als1kTesterListFile);
  my $als1kTesters = $config->{$site}->{ALS1K_Tester};


	INFO("SPD:$SPD");
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
	my $filename = basename $SPD;
	my @temp = split( /_/, $filename );
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
	my $lineTestElementsCount = 0;
        my $unit_ref = "";
	my $test_unit_flg = "";
	my $unit_cnt = "";
	my $part_cnt = "";
	#my $ref_dir  = "";
	#my $ref_dir  = "/data/cprel_tmt/TP" if $site eq "cprel";

	#if ($site eq "cpft_tmt") {
	#	$ref_dir = "/data/cpft_tmt/TP";
	#} elsif ($site eq "cprel_tmt") {
	#	$ref_dir  = "/data/cprel_tmt/TP";
	#}

	$num = 1;
	my $fileHandle = IO::File->new($SPD) or dpExitError("Failed to open SPD file $SPD");
	my $lineFlag = 0;
        my $line_flg2 = 0;
	my $dataValue1 = 0;
	my $dataValue2 = 0.0000;
	my $dataValue3 = "";

	while (my $line = $fileHandle->getline) {

		$line =~ s/[\cM|\"]//g;
		if($line !~ /Date|Test\,?/){
			$line =~ s/\s+//g;
		}

		my (@lineDumpArray) = split(",", $line);

		DEBUG($line);
		DEBUG("num in SPD = $num");
		DEBUG(@lineDumpArray);
		if ($lineFlag == 7 && $lineDumpArray[0] =~ /\d/ && $lineDumpArray[1] =~ /\d/) {

					my @data = map { trim($_) } split(",",$line);
					my $numD = scalar(@data);
					my @test = @data;
          splice @test, 0, 2;
          ### SKIP ROW DATA WITH ALL 0 OR 0.0000 VALUES IN EACH TEST ###
          my $skipRowData = 0;
          if ((@test == grep { ($_ == $dataValue2)  } @test) || (@test == grep { ($_ == $dataValue1)  } @test)) {
 						$skipRowData = 1;
					}
					next if $skipRowData == 1;
					####
					my $die  = new_die;
					$die->partid( $data[0] );
					$die->soft_bin( $data[1] );
					$die->hard_bin( $data[1] );
					$die->site( 1 );
					$die->result ( @data[ 2 .. $numD - 1 ]);
					$wafer->add( 'dies', $die );
		                        $part_cnt++;

		}
		elsif ($line =~ /Test\,?\s+Program/i) {
			if($lineDumpArray[0] =~ /Program\:/i){
				$cpftTP = $lineDumpArray[1];
				$cpftTP = trim($cpftTP);
			} elsif ($lineDumpArray[1] =~ /Program/i) {
				$cpftTP = $lineDumpArray[2];
				$cpftTP = trim($cpftTP);
			}
			my ($dumpText1, $dumpText2) = split /\s+/, $cpftTP;
			#INFO(">>>>$dumpText1<<<\t>>>>$dumpText2<<<");
			     if ($cpftTP  =~/ASL1K/i){
			         INFO("ASLIK Test Programs used. Exctracting revison from LSR file.");
			         $cpftRev = &get_tprev_frm_lsr($SPD, $site);
				 $cpftRev = "NA" if $cpftRev eq "";
				 $cpftTP  = "${dumpText1}_${dumpText2}";
			     }
			     else {
				 $cpftRev = chop($dumpText1);
				 trim($cpftRev);
				 $cpftTP = "${dumpText1}_${dumpText2}";
			     }
			INFO("TP=$cpftTP");
			INFO("TP_REVISION=$cpftRev");

			my $grep_result   = `grep -iA 1 "^Serial" $SPD | grep "^1,1,"`;
		           $test_unit_flg = "Y" if $grep_result ne "";

		}
		elsif ($line =~ /LotID/) {
			if($site eq 'cpft_tmt') {
				if($lineDumpArray[0] =~ /ID\:/i) {
					$lotid = $lineDumpArray[1];
					$lotid = trim($lotid);
				} elsif ($lineDumpArray[1] =~ /ID\:/i) {
					$lotid = $lineDumpArray[2];
					$lotid = trim($lotid);
				}
				my ($lotid, $dmp1, $dmp2) = split /\_/, $lotid;
				$cpftLotid = uc($lotid);
			}
		}
		elsif ($lineDumpArray[0] =~ /Computer\:/) {
			$header->EQUIP1_ID( trim( 'TMT ' . $lineDumpArray[1] ) );
			#if ($lineDumpArray[1] =~ /TMTFT-068|TMTFT-062|TMTFT-073|ASL1000-01/i && $site eq "cpft_tmt")
			if ($lineDumpArray[1] =~ /$als1kTesters/i && $site eq "cpft_tmt")
			{
				INFO("CP TMT ALS1K Testers ref file=$als1kTesterListFile");
			  INFO("CP TMT ALS1K Testers = $als1kTesters");
				$test_unit_flg = "Y";
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

			$lineFlag = 1;
		}
		elsif ($line =~ /Loadboard/i) {
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
			$lineTestElementsCount = $#lineDumpArray;
			for (my $i = 2; $i <= $#lineDumpArray; $i++) {
				my $test = new_test;
				$test->number($lineDumpArray[$i]);
				$model->add( 'tests', $test );
			}
			$lineFlag = 2;
		}
		elsif ($lineFlag == 2 && $line =~ /[A-Z]/i ) {
			my $t = 0;
			for (my $i = 2; $i <= $#lineDumpArray; $i++) {
				$model->tests->[$t]->name($lineDumpArray[$i]);
				$t++;
			}
			$lineFlag = 3;
		}
		elsif ($lineFlag == 3 && $line =~ /\,|[0-9\.]/i) {
			my $t = 0;
			my $lastIndex = $#lineDumpArray;
			if ($lastIndex > $lineTestElementsCount) {
				$lastIndex = $lineTestElementsCount
			}
			for (my $i = 2; $i <= $lastIndex; $i++) {
				$model->tests->[$t]->group($lineDumpArray[$i]);
				$t++;
			}
			$lineFlag = 4;
		}
		elsif ($lineFlag == 4 && $line =~ /none\,|\,\-?\d+\.\d+\,|\,\-?\d+\,|^\,+\-\d+/i) {
			my $t = 0;
			for (my $i = 2; $i <= $#lineDumpArray; $i++) {
				$model->tests->[$t]->HSL($lineDumpArray[$i]);
				$t++;
			}
			$lineFlag = 5;
		}
		elsif ($lineFlag == 5 && $line =~ /none\,|\,+\-?\d+\.\d+\,|\,+\-?\d+\,/i) {
			my $t = 0;
		  for (my $i = 2; $i <= $#lineDumpArray; $i++) {
				$model->tests->[$t]->LSL($lineDumpArray[$i]);
				$t++;
			}
			$lineFlag = 6;

		}
		elsif ($lineFlag == 6 &&  $line =~ /Serial\#/i) {

		      my $ref_file = "${ref_dir}/${cpftTP}_${cpftRev}.TXT";
		      INFO("REF_FILE=$ref_file");
		      my @new_units = ();
		      if (! -e "$ref_file" && $test_unit_flg eq ""){
		      	### 2017-Apr-10:jgarcia: make sure to log to refdb.pp_log if units are inconsistend
		      	if ($site eq "cpft_tmt") {
		      		$header->LOT(uc($cpftLotid));
		      	 } else {
		      	 	$header->LOT(uc($lotid))
		      	 }

		      	 $model->misc("UNITS Inconsistent:Test Part 1 of the datalog is NOT Bin 1 and no reference file found..Sending to Rework directory.");
		      	 #return ($model);#,"UNITS Inconsistent:Test Part 1 of the datalog is NOT Bin 1 and no reference file found..Sending to Rework directory.");
		         #dpExit( 4, "UNITS Inconsistent:Test Part 1 of the datalog is NOT Bin 1 and no reference file found..Sending to Rework directory.");
		      }
                      if ( -e "$ref_file" && $test_unit_flg eq "")
                      {
			 open FH, $ref_file or die "can't open $ref_file\n";
                         my $tmp_line=<FH>;
                         {
                                chomp($tmp_line);
                             my ($dump, $tmp_units) = split /\=/, $tmp_line;
                                 @new_units         = split /\,/, $tmp_units;
                         }
                         close(FH);

                         my $t = 0;
                         for (my $i = 1; $i <= $#new_units; $i++) {
                                 eval {$model->tests->[$t]->units($new_units[$i])};
                                 $t++;
                         }
                      }
                      else
                      {
			my $t = 0;
			for (my $i = 2; $i <= $#lineDumpArray; $i++) {
				$model->tests->[$t]->units($lineDumpArray[$i]);
				$t++;
                                $unit_ref .= "\,$lineDumpArray[$i]";
				$unit_cnt++;
			}
		      }
			$lineFlag = 7;
			&create_ref_units($unit_cnt, $cpftTP, $cpftRev, $date_SPD, $SPD, $unit_ref, $site, $ref_dir) if $test_unit_flg eq "Y";
		}
		$num++;
	}
	#close FH_SPD;
	undef $fileHandle;

	if ( $part_cnt == 0 ) {
		   if ($site eq "cpft_tmt") {
		   		$header->LOT(uc($cpftLotid));
		   } else {
		    	$header->LOT(uc($lotid))
		   }

		   $model->misc("Part test data is 0");
		   #return ($model);
	     #dpExit( 1, "Part test data is 0 .");
	}
	if ( $part_cnt <= 10 && $site ne "cprel") {
	     WARN("Part test data is 10 or less.Sending to sandbox...");
	     $model->forSBflag( 1 );
	}

	if ( $cpftRev eq "NA") {
	     WARN("Test Plan rev set to \"NA\". No .LSR file or not able to get rev.. .Sending to sandbox...");
	     $model->forSBflag( 1 );
	}

	#my $epoch_SPD = parseDate($date_SPD);
	$header->START_TIME($date_SPD);
	$header->END_TIME($date_SPD);

	my $program = "";

	given($site) {
		when('cpft_tmt') {
			if($cpftRev eq "") {
				  if ($site eq "cpft_tmt") {
						$header->LOT(uc($cpftLotid));
					} else {
						$header->LOT(uc($lotid))
					}
					$model->misc("INVALID OR NO TESTPLAN REVISION");
					#return ($model);
					#dpExit(1,"INVALID OR NO TESTPLAN REVISION!!!");
			}
			$header->LOT(uc( $cpftLotid ));
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
		when ('cprel') {
			if($cpftRev eq "") {
     			    dpExit(1,"INVALID OR NO TESTPLAN REVISION!!!");
			}
			if ( length($cpftTP) > 45 ) {
		             WARN("PROGRAM NAME \"".$cpftTP."\" will be truncated to 35 characters.  Sending to sandbox.");
		        $model->forSBflag( 1 );
		        $program = substr($cpftTP, 1, 45); # Leave enough room for session type

			} else {
				$program = $cpftTP;
			}
		        $header->REVISION($cpftRev);
		}
	}
	$header->VERSION($VERSION);
	$header->PROGRAM_CLASS(2);
	$header->PROGRAM($program);
	#$header->INDEX1($testMode);
	#$header->INDEX2($mode);
	#
	return ($model);
}###end of the readSPD method###
1;

sub create_ref_units
{
       my $tp_cnt       = shift;
       my $tp_name      = shift;
       my $tp_rev       = shift;
       my $date_time    = shift;
       my $file_name    = shift;
       my $ref_units    = shift;
       my $site         = shift;
       my $ref_dir      = shift;
           #if ($site eq "cpft_tmt") {
           #    $ref_dir = "/data/cpft_tmt/TP";
	   #}
	   #else {
	    #   $ref_dir = "/data/cprel_tmt/TP";
	   #}
       my $ref_filename = "${ref_dir}/${tp_name}_${tp_rev}.TXT";
       my($directory, $filename) = $file_name  =~m/(.*\/)(.*)$/;
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
sub get_tprev_frm_lsr
{
      	my $SPD_file = shift;
				my $site = shift;
				my $tp_rev_new  = "";
      	my $lsr_file = "";
      	my ($dir_dump, $tmpfilename) = $SPD_file =~m/(.*\/)(.*)$/;
      	my ($SPDfilename, $dump)     = split /\.spd/i, $tmpfilename;
				my $rootEnvDir = $ENV{DPDATA};
				my ($volume,$dir,$file) = File::Spec->splitpath( $SPD_file );
				INFO("DIR=$dir||FILE=$file");
				my $lsr_file = $SPD_file;
				if($file =~ /.+\.SPD$/) {
					$file =~ s/\.SPD/\.LSR/g;
					$lsr_file =~ s/\.SPD/\.LSR/g;
				} elsif($file =~ /.+\.spd$/) {
					$file =~ s/\.spd/\.lsr/g;
					$lsr_file =~ s/\.spd/\.lsr/g;
				}
				INFO("Expected LSR file = $file");
				#my $lsr_file = $SPD_file;
				#$lsr_file =~ s/\.SPD/\.LSR/g;
				if(!(-e $lsr_file)) {
					$lsr_file = "${dir}NotProcessed/${file}";
				}
				if(!(-e $lsr_file)) {
					$lsr_file = "${dir}Processed/${file}";
				}
				if(!(-e $lsr_file)) {
					#$lsr_file = $ENV{DPDATA}."/data/${site}/LSR_SPD/${file}";
					$lsr_file = "${dir}${file}";
				}
				if(!(-e $lsr_file)) {
					$lsr_file = $ENV{DPDATA}."/data/${site}/${file}";
				}
				if(!(-e $lsr_file)) {
					$lsr_file = "";
				}
				#INFO("DIR=$dir||LSR=$lsrFile");
				#$lsr_file = "${dir}"

      	### LOOK LSR FILE IN /data/cpft_tmt
      	#my ($lsr_file) = `find /data/cpft_tmt -type f -iname \"$SPDfilename\.LSR\" -o -iname \"$SPDfilename\.LSR_MD5-*\"`;

      	#INFO ("Searching LSR file using regex = $SPDfilename");

      	#my @lsr = `find /data/cpft_tmt -type f -iname \"$SPDfilename*\.LSR\" -o -iname \"$SPDfilename*\.LSR_MD5-*\"`;
      	#my @lsr = `find /apps/exensio_data/data/cpft_tmt -type f -iname \"$SPDfilename*\.LSR\" -o -iname \"$SPDfilename*\.LSR.gz\" -o -iname \"$SPDfilename*\.LSR_MD5-*\"`;

      	#foreach my $l (@lsr) {
      	#   	next if $l =~ /\_iff/i;
	   	#$lsr_file = $l;
      #	}

         if ($lsr_file ne "") {

	 	INFO("Matching LSR file found = $lsr_file");
            	chomp($lsr_file);
            	#$lsr_file = `gunzip $lsr_file` if $lsr_file =~ /\.gz$/;

                #my $grep_result1 = `grep -iA 0 "REV" $lsr_file`;
                my $grep_result1 = "";

		if ($lsr_file =~ /\.gz$/i) {
			$grep_result1 = `zgrep -iA 0 "REV" $lsr_file`;
		}
		else {
			$grep_result1 = `grep -iA 0 "REV" $lsr_file`;
		}

		chomp($grep_result1);
		INFO("Grep result = $grep_result1");

		if ($grep_result1 =~ /^\[\d+\]\s+REV\s+(\d+\.\d+)\s+.+/i){   #[1]    REV 12.0  495    99.00 %
			$tp_rev_new = $1;
		}
		elsif ($grep_result1 =~ /^\[\d+\]\s+REV(\d+\.\d+)\s+.+/i) { #[1]    REV7.0  500   100.00 %
			$tp_rev_new = $1;

		}elsif ($grep_result1 =~ /^\[\d+\]\s+REV(\d+)\s+.+/i) { #[1]    REV7 21107    94.16 %
			$tp_rev_new = $1;
		}
		elsif ($grep_result1 =~ /^\[\d+\]\s+REV\s+(\d+)\s+.+/i){ #[3]    REV 22   0     0.00 %   6   0     0.00 %
			$tp_rev_new = $1;
		}
		else {
			my (@dummy) = split /\s+/, $grep_result1;
			$tp_rev_new = $dummy[1];
			$tp_rev_new =~ s/REV//i;
		}

		chomp($tp_rev_new);
		INFO("TP Revision extracted from LSR = $tp_rev_new");

         }
	 else {
		WARN("NO matching LSR file found.");
	 }
	 return($tp_rev_new);
}
sub dpExitError {
	my $self    = shift;
	my $message = shift;
	dpExit( 1, $message );
}
