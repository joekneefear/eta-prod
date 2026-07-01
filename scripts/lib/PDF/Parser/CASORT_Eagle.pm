# SVN $Id: Eagle.pm 2112 2017-04-25 08:56:04Z dpower $
#
# CHANGES
# 2014/04/20 eric 	: Capture line 125, 125_P and 145
# 2015/04/23 grace 	: Swapped HARD_BIN and SOFT_BIN
# 2015/04/27 hiroshi    : added Test Head # to EQUIP1
# 2015/04/30 jgarcia 	: generates test number from record 100 for $wafer if record 10 is not available in raw .log 
# 			file to be able to generate test result for $data hence can be loaded to db.
# 2015/05/01 jgarcia 	: modified to make sure that the parsed lotid is in uppercase
# 2015/05/06 jgarcia   	: revert back the changes made with regards to generating test number from record 100 if record 
# 			10 is not available. no record 10 datalog will not be loaded at all.
# 2015/05/13 eric 	: Improved parsing to handle multiple rec 145
# 2015-Aug-26 Gilbert	: Uppercase lot id.
# 2015-Oct-15 Eric	: get product
# 2016-Mar-29 Eric	: added sub compute_testtime
# 2016-Jun-7 Eric	: capture only the last occurrence of die tested.
# 2016-Jul-20 Eric	: capture bin summary counts from part level. generate generic bin names
# 			if rec 50 & 60 are not found.
# 2016-Jul-26 Eric	: get bin names from bin ref file. sanbox it if no rec 50 & 60
# 2016-Jul-26 Eric	: fixed conditions when generaation binnames 
# 2016-Jul-28 Eric	: capture last occurence of xy coord if pkg type eq W
# 2016-Aug-04 Eric	: rename sub get_binnames to get_ref_info. 
#			extract test info from reference file if first part tested fails.
# 2016-Aug-05 Eric	: removed options to get bin names from reference. 
# 2016-Aug-05 Eric	: exit if test name is blank.
# 2016-Aug-19 RCyr  : Some files have quotes around pkg type which must be stripped.
# 2016-Sep-14 GMiole    : Auto-generate if partno not specified but send to sandbox.
# 2016-Oct-25 Eric	: store pass count.
# 2016-Nov-03 Eric	: fixed: some amkor files not able to store pass count correctly.
# 2017-Mar-14 Eric	: check xy coordinates are present
# 2017-Mar-20 Eric      : check xy coordinates if package type P & site eq sort/csp
# 2017-Mar-27 Eric      : return model instead of exiting when error is found
# 2017-Apr-25 jgarcia : fix bug regarding pp_log enhancement on all site.

package PDF::Parser::CASORT_Eagle;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use Time::Local;
use File::Basename qw/basename dirname/;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr = [ qw/ sublot / ];

sub array {
    return qw//;
}

__PACKAGE__->mk_accessors(@$attr, array );

#__PACKAGE__->mk_accessors(array);

sub readFile {
    	my $self   = shift;
    	my $infile = shift;
	my $site   = shift;
    	my $header = new_headerLong;
    	my $wmap   = new_wmap;
    	my $model  = new_model(
        {   header => $header,
            wmap   => $wmap,
            misc   => {},
            dataSource => 'EAGLE'
        }
    	);
    	my $wafer = new_wafer;
    	$model->add( 'wafers', $wafer );

    	my ( $columns, $rows );
    	my ( $x, $y, $deviceCount ) = ( 0, 0, 0 );
    	my $data = {};
    	my @ghr = ();
    	my $die_cnt = 0; 
    	my $istdie_datetime;
    	my $prev_time;
    	my %td = {};
	my %sb_cnt = {};
	my %hb_cnt = {};
	my $pCnt;
	my %sbr = {};
	my %hbr = {};
	my $rec50_flg = "N";
	my $rec60_flg = "N";
	my $sbox_flg;
	my $pkg_type;
	my $auto_partid = 100000;       ### USE IF PARTID NOT SPECIFIED
  
    	open( INFILE, $infile );
    	while (<INFILE>) {
        	my @item = split(/,/);
        	if ( $item[0] eq "10" ) {
            		# add test 0.1 & 0.2
            		my $test = $wafer->find ('tests', {number => '0.1'});
            		unless (defined $test){
                		my $test = new_test;
                		$test->number('0.1');
                		$test->name('test_time');
                		$test->units('sec');
                		$wafer->add( 'tests', $test );
            		}
            		$test = $wafer->find ('tests', {number => '0.2'});
            		unless (defined $test){
                		my $test = new_test;
                		$test->number('0.2');
                		$test->name('elapsed_time');
                		$test->units('sec');
                		$wafer->add( 'tests', $test );
            		}

            		my $test = new_test;
            		$test->number( $item[1] );
            		$test->name( repNA( $item[6] ) );
            		$test->units( repNA( $item[5] ) );
            		$test->group( repNA( $item[2] ) );
            		$test->LSL( repNA( $item[4] ) );
            		$test->HSL( repNA( $item[3] ) );
	    		$wafer->add( 'tests', $test );

			# Exit if test name is blank
			if ( $test->name eq "" or $test->name eq "N/A") {
				my $err_msg = "Test name should not be blank.";
				$model->misc->{err_msg} = $err_msg;
				#return $model;
			}
        	}
        	if ( $item[0] eq "100" ) {
				#print "$item[1] - $item[4]\n";
            		$data->{ $item[1] } = $item[4];
        	}
        	if ( $item[0] eq "130" ) {
	    		$die_cnt++;
	    		$item[2] =~ s/\"//g;
	    		$prev_time = $item[2] if $prev_time eq "";
	    		$istdie_datetime = $item[2] if $die_cnt == 1;

	    		my ($testtime,$elapse_time) = compute_testtime($istdie_datetime,$item[2],$prev_time);
	    		$prev_time = $item[2];

            		$data->{0.1} = $testtime;     	  
	    		$data->{0.2} = $elapse_time;
	 
            		#my $die = new_die;
            		#$die->x( $item[5] );
            		#$die->y( $item[6] );
            		#$die->site( $item[1] );
            		#$die->PF($item[4]);
            		#$die->partid( $item[3] );
            		#$die->soft_bin( $item[7] );
            		#$die->hard_bin( $item[8] );
	    
            		#foreach my $test ( @{ $wafer->tests } ) {
                	#	$die->add( 'result', repNA( $data->{ $test->number } ) );
            		#}

            		#$wafer->add( 'dies', $die );
			if ($item[3] !~ /[0-9]{1,}/ && $sbox_flg eq "") {
			    $sbox_flg = 1;
			    WARN ("PartNo Not Specified..sending file to sandbox");
			}
			### AUTO-GENERATE IF PARTNO NOT SPECIFIED ###
			$item[3] = ($item[3] =~ /[0-9]{1,}/) ? $item[3] : $auto_partid++;

			my $xy = "x".$item[5]."y".$item[6];
			if ( $pkg_type eq 'P' || $pkg_type eq 'W') {

				# check xy coord if sort/csp
				#if ($site =~ /sort|_csp/i) {
				#	if ($item[5] eq "" || $item[6] eq "") {
				#		my $err_msg  = "No X/Y coordinates found.";
				#		$model->misc->{err_msg} = $err_msg;
						#return $model;
                                #	}				
				#}

				$td{$item[3]} = {
					x => $item[5],
					y => $item[6],
					partid => $item[3],
					site => $item[1],
					pf => $item[4],
					sbin => $item[7],
					hbin => $item[8],
					result => $data,
				};
			}
			#elsif ( $pkg_type eq 'W' ) {

				# check xy coord
                         #       if ($item[5] eq "" || $item[6] eq "") {
			#		my $err_msg  = "No X/Y coordinates found.";
			#		$model->misc->{err_msg} = $err_msg;
					#return $model;
                         #       }
	
			#	$td{$xy} = {
                         #               x => $item[5],
                          #              y => $item[6],
                           #             partid => $item[3],
                           #             site => $item[1],
                            #            pf => $item[4],
                             #           sbin => $item[7],
                             #           hbin => $item[8],
                              #          result => $data,
                               # };	
			#}

				foreach my $no (keys $data) {
					#print "$td{$xy}{result}->{$no}\n";
				}
            		$data = {};

            		my $date = $item[2];
            		unless ( defined $wafer->START_TIME ) {
                		$wafer->START_TIME($date);
            		}
            		$wafer->END_TIME($date);
        	}
        	if ( $item[0] eq "50" ) {
            		#my $bin = new_bin;
            		#$bin->number( $item[1] );
            		#$bin->name( trim( $item[4] ) );
            		#$bin->PF( trim( $item[2] ) );
            		#$bin->count( $item[3] );
            		#$wafer->add( 'bins', $bin );

			$rec50_flg = "Y";
			$sbr{$item[1]} = {
				name => trim($item[4])
			};
        	}
		if ( $item[0] eq "60" ) {
            		#my $bin = new_bin;
            		#$bin->number( $item[1] );
            		#$bin->name( trim( $item[4] ) );
            		#$bin->PF( trim( $item[2] ) );
            		#$bin->count( $item[3] );
            		#$wafer->add( 'hbins', $bin );

			$rec60_flg = "Y";
			$hbr{$item[1]} = {
				name => trim($item[4])
			};
        	}
        	if ( $item[0] eq "120" ) {
            		$model->misc->{120} = \@item;
            		my $lot = $item[5];
            		$lot = uc($lot);
            		$header->LOT( trim(uc($lot)) );
	    		$self->sublot( $item[6] );
            		$header->OPERATOR( trim( $item[7] ) );
            		$header->EQUIP1_ID( trim( trim( $item[2] ) . " " . trim( $item[8] ) . " " . trim( $item[1] ) ) );
        	}
        	if ( $item[0] eq "140" and $item[1] eq "2" ) {
            		$model->misc->{140_2} = \@item;
            		my $program = trim( $item[2] );
            		$program =~ s|\\|/|g;
            		$header->PROGRAM( ( split( /\./, basename($program) ) )[0] );
            		$header->REVISION( trim( $item[4] ) );
	    		$header->PRODUCT( trim( uc($item[3]) ) );
        	}
		if ( $item[0] eq "125" ) {
				$item[1] =~ s/\"//g;
	    		$model->misc->{125} = \@item;
		}	
        	if ( $item[0] eq "125" and $item[1] eq 'W' ) {
            		$model->misc->{'125_W'} = \@item;
			$pkg_type = $item[1];
        	}
		if ( $item[0] eq "125" and $item[1] eq 'P' ) {
            		$model->misc->{'125_P'} = \@item;
			$pkg_type = $item[1];
        	}
		if ( $item[0] eq "145" ) {
	    		push (@ghr, (trim( $item[1] )), (trim( $item[2] )) );
	    		$model->misc->{ghr_info} = \@ghr;
		}
	 	
    	}
    	close(INFILE);

	if ($rec50_flg eq "N" || $rec60_flg eq "N") {
		$sbox_flg = 1;
		WARN ("No record 50 or 60 found..sending file to sandbox");
	}

	foreach my $no (sort {$a<=>$b} keys %td) {
		next if !defined $td{$no};
		# store bin counts
		$sb_cnt{$td{$no}{sbin}}++;
		$hb_cnt{$td{$no}{hbin}}++;
		
		# sbin summary
		my $sbin = $wafer->find('bins', {number=>$td{$no}{sbin}});
                unless(defined $sbin) {
                	$sbin = new_bin;
                        $wafer->add( 'bins', $sbin );
                }
                $sbin->number($td{$no}{sbin});
                $sbin->name($rec50_flg eq "Y" ? $sbr{$td{$no}{sbin}}{name} : "SBIN".$td{$no}{sbin});
                $sbin->PF($td{$no}{pf});
                $sbin->count($sb_cnt{$td{$no}{sbin}});
		# store pass count
		$pCnt++ if $td{$no}{pf} =~ /P/i;
		$model->misc->{passcount} = $pCnt;
		
		#hbin summary
		my $hbin = $wafer->find('hbins', {number=>$td{$no}{hbin}});
                unless(defined $hbin) {
                        $hbin = new_bin;
                        $wafer->add( 'hbins', $hbin );
                }
                $hbin->number($td{$no}{hbin});
		$hbin->name($rec60_flg eq "Y" ? $hbr{$td{$no}{hbin}}{name} : "HBIN".$td{$no}{hbin});
                $hbin->PF($td{$no}{pf});
                $hbin->count($hb_cnt{$td{$no}{hbin}});	

		my $die = new_die;
                $die->x($td{$no}{x});
                $die->y($td{$no}{y});
                $die->site($td{$no}{site});
                $die->partid($pkg_type eq 'P' ? $no : $td{$no}{partid});
                $die->soft_bin($td{$no}{sbin});
                $die->hard_bin($td{$no}{hbin});
		
		foreach my $test ( @{ $wafer->tests } ) {
			$die->add( 'result', repNA($td{$no}{result}->{$test->number}));
			#print "$td{$no}{result}->{$test->number}\n";
            	}
			
		$wafer->add( 'dies', $die );		
	}

    	return $model, $sbox_flg;
}

sub compute_testtime {
	my $touch_time = shift;
	my $curr_time = shift;
	my $prev_time = shift;

	my($mm, $dd, $yy, $junk, $hr, $min, $sec)  = split /[\/|\s+|\:]/, $touch_time;
	my $time1 = timelocal($sec,$min,$hr,$dd,$mm - 1,$yy);

	my($mm, $dd, $yy, $junk, $hr, $min, $sec)  = split /[\/|\s+|\:]/, $curr_time;
	my $time2 = timelocal($sec,$min,$hr,$dd,$mm - 1,$yy);

	my($mm, $dd, $yy, $junk, $hr, $min, $sec)  = split /[\/|\s+|\:]/, $prev_time;
	my $time3 = timelocal($sec,$min,$hr,$dd,$mm - 1,$yy);

	my $elapse_time = $time2 - $time1;
	my $testtime = $time2 - $time3; 

	return ($testtime, $elapse_time);
}


1;
