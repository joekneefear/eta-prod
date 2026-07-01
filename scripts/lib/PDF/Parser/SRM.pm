=pod

=head1 SYNOPSIS

instantiate and use its method/subroutine and attributes.

=head1 DESCRIPTIONS

B<This script>  SRM machine at Tape and Reel process parser module.

=head1 AUTHOR

B<gilbert.miole@fairchildsemi.com>

=head1 CHANGES
06-Sep-2016 - GMiole 	- Add the % Yld of each BIN, Maximize the # of BIN to 20 bins
            		- Add test 1 to test 8 with each total count/qty and each corresponding % Yld
            		- Add Orient, Mark2, Mark, and 3D total count/qty and each corresponding % Yld
            		- Total Total
25-Apr-2017 - GMiole    - pckg_rcp_eqpt - support dash or underscore to identify eqpt and tp name.

=head1 LICENSE

(C) Fairchild 2015 All rights reserved.

=cut

package PDF::Parser::SRM;
use strict;
#use diagnostics;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use v5.10;
use IO::File;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;
use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

my $attr = [qw/TXT/];

sub array {
	return qw//;
}

__PACKAGE__->mk_accessors( @$attr, array );

sub readTXT {
	
	my $self = shift;
	my $TXT  = shift;
	my $site = shift;
	
	INFO("SRM:$TXT");
	my $header = new_headerLong;
	my $wmap   = new_wmap;
	my $model  = new_model(
		{ header => $header,
			wmap   => $wmap,
			misc   => {},
			dataSource => 'SRM',
			forSBflag => ''
		}
	);
	my $wafer = new_wafer;
	$model->add( 'wafers', $wafer );
	
	my $filename 		= basename $TXT;
	my $date_TXT		= "";
	my $endDate_TXT		= "";
	my $startDate_TXT	= "";
	my $date 		= "";
	my $time 		= "";
	my $pckg_rcp_eqpt 	= "";
	my $bin_cnt 		= "";
	my @bin 		= ();
	my $binName 		= "";
	my $snum                = 0;
	my $bin_cnt 		= 0;
	my $lotid 		= "";
	my $tp_name 		= "";
	my $tp_rev 		= "1";
	my $eqptid        	= "";
	my $test_datetime 	= "";
	my $TXTFileHandle 	= IO::File->new($TXT) or dpExitError("Failed to open TXT file $TXT");
	my $line 		= "";
	my $sec 		= "";
	my $min 		= "";
	my $hr  		= "";
	my $mm  		= "";
	my $dd  		= "";
	my $yy  		= "";
        my $prcnt_bin           = "";
        my $test                = "";
        my $prcnt_test          = "";
        my $orient              = "";
        my $prcnt_orient        = "";
        my $mark                = "";
        my $mark2               = "";
        my $prcnt_mark          = "";
        my $prcnt_mark2         = "";
        my $d3_tot_cnt          = "";
        my $prcnt_3d_tot_cnt    = "";
        my $total               = "";

	while($line = $TXTFileHandle->getline) {

              chomp($line);
              $line =~ s/\cM//g;      ### REMOVE ^M CHARS
              #print "$line\n";

        ### FORMAT: Date, Time, Package_Recipe_EquipmentID,B1,B2,B3.,B14, Lot Number
        ### NEW FORMAT: Date, Time, Package_Recipe_EquipmentID,B1,B2,B3.,B14, Lot Number, more bins
               my @dummy   = split /,/, $line;

              ##################################
	      # REMOVE AND ASSIGN THE LAST VALUE
	      ##################################
	      if ( $line =~/\d{1,3}\.\d{2}\%\,\d{1,3}\.\d{2}\%\,\d{1,3}\.\d{2}\%\,/ ) {
		        
			$total            = pop(@dummy);
                        $prcnt_3d_tot_cnt = pop(@dummy);
                        $d3_tot_cnt       = pop(@dummy);
                        $prcnt_mark       = pop(@dummy);
                        $mark             = pop(@dummy);
                        $prcnt_mark2      = pop(@dummy);
                        $mark2            = pop(@dummy);
                        $prcnt_orient     = pop(@dummy);
                        $orient           = pop(@dummy);
	      }
	      #else {
              #  	$lotid          = pop(@dummy);
              #  	$lotid          = uc($lotid);
	      #}
              ($date, $time, $pckg_rcp_eqpt, @bin) = @dummy;

	      $header->DEVICE_COUNT($#bin + 1);
              $pckg_rcp_eqpt  =~/(\_|\-)(\D{2,5})?(\d{1,})$/;
              $eqptid         = $3;
	      $header->EQUIP1_ID($eqptid);
	      $header->EQUIP5_ID('SRM');

              ($tp_name)      = split /(\_|\-)(\D{2,5})?(\d{1,})$/,$pckg_rcp_eqpt;

              ### CONVERT DATETIME TO UNIX TIME ###
              my $date_time     = "$date" . " $time";
	         $test_datetime = $date_time;
                 ($mm, $dd, $yy, $hr, $min, $sec) = split /\/|\s+|\:/, $date_time;
                 #print "parsed date: $mm\/$dd\/$yy $hr\:$min\:$sec\n";

	}
        ##########
	# BIN DATA
	##########
	my $i    = 0;
	while ( defined(my $val = shift @bin) ){

	        next if $val eq "";
		$lotid = uc($val) if $val !~/^\d/;
		last if $val !~/^\d/;
	        next if $val !~/^\d/;
		my $bin     = new_bin;
		$bin->count($val);
		$bin->number($i + 1);
		if ($i == 0) {
		    $binName = "qty_in";
		}
		elsif ($i == 1) {
		    $binName = "jam_counter";
		}
		elsif ($i == 2) {
		    $binName = "tape";
		   }
		else {
		   $binName  = "SBIN".(2 + $snum++);
		$bin_cnt++;
		}
		$bin->name($binName);
	        $wafer->add( 'bins', $bin );
		$i++;
	}
	if ($#bin > $bin_cnt) {
	
	    my $i = 0;
	    #############
	    # PERCENT BIN
	    #############
	    while ( defined(my $val = shift @bin) ){
	
	           next if $val eq "";
		   my $bin = new_bin;
		   $bin->number($i+100);
		   $bin->count($val);
		   $binName  = "%SBIN".(1 + $i++);
		   $bin->name($binName);
	           $wafer->add( 'bins', $bin );
		   last if $bin_cnt < $i;
	    }
	    #######################
	    # TEST AND PERCENT TEST
	    #######################
	    my $j = 0;
	    my $k = 0;
	    for(my $i=0; $i<$#bin +1; $i++) {
	    #print "bin:$bin[$i]\n";
 
	           next if $bin[$i] eq "";
		   my $bin = new_bin;
		   if ($bin[$i] =~/\%/) {
		       $j++;
		       $bin->number($i+1000);
		       $bin->count($bin[$i]);
		       $binName  = "%TEST".($j);
	   	   } 
		   else {
		       $k++;
		       $bin->number($i+1000);
		       $bin->count($bin[$i]);
		       $binName  = "TEST".($k);
		   }
		   $bin->name($binName);
	        $wafer->add( 'bins', $bin );
	    }
	    ##############
	    # LAST PORTION 
	    ##############
	    for(my $i=1; $i<10; $i++) {

		my $bin     = new_bin;
		   $bin->number($i+100000);
		   if ($i == 1) {
		       $binName = "orient";
		       $bin->count($orient);
		   }
		   elsif ($i == 2) {
		       $binName = "%orient";
		       $bin->count($prcnt_orient);
		   }
		   elsif ($i == 3) {
		       $binName = "mark2";
		       $bin->count($mark2);
		   }
		   elsif ($i == 4) {
		       $binName = "%mark2";
		       $bin->count($prcnt_mark2);
		   }
		   elsif ($i == 5) {
		       $binName = "mark";
		       $bin->count($mark);
		   }
		   elsif ($i == 6) {
		       $binName = "%mark";
		       $bin->count($prcnt_mark);
		   }
		   elsif ($i == 7) {
		       $binName = "3D_total_count";
		       $bin->count($d3_tot_cnt);
		   }
		   elsif ($i == 8) {
		       $binName = "%3D_total_count";
		       $bin->count($prcnt_3d_tot_cnt);
		   }
		   elsif ($i == 9) {
		       $binName = "TOTAL_TOTAL";
		       $bin->count($total);
		   }
		   $bin->name($binName);
	        $wafer->add( 'bins', $bin );
	    }
	    #######################
	}

	undef $TXTFileHandle;
      
        if ($time =~/PM/i )
	{
		$hr  = $hr + 12 if $hr != 12;
		$test_datetime  = "/$mm/$dd/$yy $hr:$min:00";
	}
	else
	{
                $hr =~s/12/00/;
        	$test_datetime  = "/$mm/$dd/$yy $hr:$min:00";;
	} 	
	

	$endDate_TXT    = $test_datetime;
	$startDate_TXT  = $test_datetime;
	$header->START_TIME($startDate_TXT);
	$header->END_TIME($endDate_TXT);
	
	my $program = "";

	$header->LOT( $lotid );
	if ( length($tp_name) > 35 ) {
		      WARN("PROGRAM NAME \"".$tp_name."\" will be truncated to 35 characters.  Sending to sandbox.");
		        $model->forSBflag( 1 );
		        $program = substr($tp_name, 1, 35); # Leave enough room for session type
		        		
			} else {
				$program = $tp_name;
			}
			$header->REVISION($tp_rev);
	$header->VERSION($VERSION);
	$header->PROGRAM_CLASS(12);
	$header->PROGRAM($program);
	return ($model);
	
}### end of readTXT method
1;

sub dpExitError {
	my $self    = shift;
	my $message = shift;
	dpExit( 1, $message );
}
