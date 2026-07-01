# 18-Feb-2016 Eric	: create
# 3-May-2016  Eric	: accept facility option
# 18-Aug-2017 Eric	: fixed script to handle misaligned specs against the measurement data
# 24-Aug-2017 Eric	: add product number to td hash.
# 04-May-2018 Eric	: remove replacement/defualt values if N,MIN,MAX statistics are empty
# 08-May-2018 Eric	: Support Loading CoC data with new Specification with alpha-based revision and actual Customer values
# 			: fixed parsing of equip5
# 			: accept new date formats
# 27-Jun-2018 Rodney    : Added EPIWORLD_US
# 27-Jan-2023 jgarcia   : supported sheet name that ends with capital I
package PDF::Parser::COFC_xls;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use Spreadsheet::ParseExcel;

use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

my $oWkS;

sub readFile {
	my $self   = shift;
	my $infile = shift;
	my $facility = shift;
	my %td = ();
	my %tp = ();
	my $lot;
        my $prev_lot;
        my $equip5;
        my $equip1;
        my $equip2;
        my $tpname;
        my $tprev;
        my $product;
	my $product_num;
        my $start_t;
        my $end_t;
	my $delivery_num;
	my @models = ();
	my $mat_type = "SUB";
	my %uniqueTest;

	my $xls = Spreadsheet::ParseExcel::Workbook->Parse($infile);
        my ($sh_h, $sh_l) = get_sheets($xls);
	my ($sh_h_row_min, $sh_h_row_max) = $sh_h->row_range();
	my ($sh_h_col_min, $sh_h_col_max) = $sh_h->col_range();
	my ($sh_l_row_min, $sh_l_row_max) = $sh_l->row_range();
        my ($sh_l_col_min, $sh_l_col_max) = $sh_l->col_range();

	my @h_dummy = ();
	my @l_dummy = ();
  my $vendor = "";
  my $subconLot = "";

	## HEADER
	for my $row ($sh_h_row_min .. $sh_h_row_max) {
		for my $col ($sh_h_col_min .. $sh_h_col_max) {
			my $cell = $sh_h->get_cell($row, $col);
			next unless $cell;
			my $cell_val = $cell->value();
			$h_dummy[$col] = &clean_string($cell_val);
			#print "Hrow=$row Hcol=$col\t$h_dummy[$col]\n";
		}
		if ($h_dummy[0] =~ /CUSTOMER:$|CUSTOMER$/i) {
			my @new_arr = &clean_row(@h_dummy);
			$equip5 = $new_arr[1];
			$equip5 = "" if $equip5 =~ /Material_Type:/i;

			if ($new_arr[3]  =~ /epi/i){
                               $mat_type = "EPI";
                       }
		}
		if ($h_dummy[0] =~ /SPECIFICATION_NUMBER/i) {
			my @new_arr = &clean_row(@h_dummy);
			if ($new_arr[1] =~ /.+[\/\s](MAT\d+R.+)/) {
                        	# Move MAT# to the front (ex: "SPT001R3/MAT002REV2" to "MAT002REV2/SPT001R3"
                                my $mat = $1;
                                my $spt = substr($new_arr[1],0,index($new_arr[1],"MAT"));
                                $new_arr[1] = $mat." ".$spt;
                        }
			$tpname = $new_arr[1];
			#INFO ("BEFORE TP = $tpname");

                        if ($tpname =~ /\D$/) {   #TP ENDS IN NON DIGIT
                                if ($tpname =~ /(\S*)Rev\_(\w)$/i) { #409-4-W43057_Rev_C
                                        $tpname = $1;
                                        $tprev = $2;
                                        $tpname =~ s/\_$//i;
                                }
                                elsif ($tpname =~ /(\S*)00(\w)$/i) { #52AON60871G00E
                                        $tpname = $1;
                                        $tprev = $2;
                                        $tpname =~ s/\_$//i;
                                }
                                elsif ($tpname =~ /(\S*\D)REV\D(\w)$/) { #52MON04604D REV.E
                                        $tpname = $1;
                                        $tprev = $2;
                                        $tpname =~ &clean_string($tpname);
                                }
                                else {   #LAST CHAR
                                        $tprev = substr $tpname, -1;
                                        #$tpname = substr $tpname, 0, length($tpname)-1;
                                }

                        }
			elsif ($tpname =~ /\d$/) {  #TP ENDS IN DIGIT
                                if ( $tpname =~ /(\S*)Rev\D+(\d+\.\d+)$/i) {   #409-4-W43058_Rev_1.0
                                        $tpname = $1;
                                        $tprev = $2;
                                }
                                elsif ( $tpname =~ /(\S*)Rev\D(\d+)$/i ) {  #FSC-SPT-10150_Rev_4
                                        $tpname = $1;
                                        $tprev = $2;
                                }
                                elsif( $tpname =~ /(\S*)00(\d+)$/i) { #52AON60871G002
                                        $tpname = $1;
                                        $tprev = $2;
                                }
                                elsif ( $tpname =~ /(\S*)\-(\d+\.\d+)$/i) {  # MAT-WFR-0179-6.0
                                        $tpname = $1;
                                        $tprev = $2;
                                }
                                elsif ( $tpname =~ /(\S*)\-00(\d+)$/i) {  #MAT-WFR-0171-001
                                        $tpname = $1;
                                        $tprev = $2;
                                }
                                elsif ($tpname =~ /(\S*)\_REV\D+(\d+)$/i) {  #SPT-10152_REV._4
                                        $tpname = $1;
                                        $tprev = $2;
                                }
                                elsif ($tpname =~ /(\S*)\_REV\D+(\d+\.\d+)$/i) {
                                        $tpname = $1;
                                        $tprev = $2;
                                }
                                elsif ($tpname =~ /(\S*)R(\d+)$/i) { # MAT0004R3 SPT10214R2
                                        $tpname = $1;
                                        $tprev = $2;
                                }
                                elsif ($tpname =~ /(\S*)R(\d+\.\d+)$/i) {
                                        $tpname = $1;
                                        $tprev = $2;
                                }
                                else { #LAST CHAR
                                        $tprev = substr $tpname, -1;
                                        #$tpname = substr $tpname, 0, length($tpname)-1;
                                }
			}
                        $tpname =~ s/\-$|\_$|\/$|\\$//ig;
			INFO( "TPNAME=$tpname REV=$tprev");
		}
		if ($h_dummy[0] =~ /PART_NUMBER/i){
			my @new_arr = &clean_row(@h_dummy);
			$new_arr[1] =~ s/[\/\s\-]/_/g ;
                        if ($new_arr[1] eq "")
                        {
                        	$new_arr[1] = "UNKNOWN";
                        }
			$product = $new_arr[1];
		}
		if ($h_dummy[0] =~ /PRODUCT_NUMBER/i && $h_dummy[1] ne ""){
			my @new_arr = &clean_row(@h_dummy);
			$product_num = $h_dummy[1];
		}
		if ($h_dummy[0] =~ /PRODUCT_LINE/i && $h_dummy[1] ne ""){
			my @new_arr = &clean_row(@h_dummy);
			$equip1 = $new_arr[1];
		}
		if ($h_dummy[0] =~ /DATE/i) {
			my @new_arr = &clean_row(@h_dummy);
			if ($new_arr[1] =~ /(\d{4})\-(\d{2})\-(\d{2})/) # change yyyymmdd to yyyy/mm/dd
			{
				$new_arr[1] = $1."-".$2."-".$3;
				$start_t = $new_arr[1] . " 00:00:00";
                        	$end_t  = $new_arr[1] . " 00:00:00";
			}
			elsif ($new_arr[1] =~ /(\d{1,2})\-(\d{1,2})\-(\d{4})/)
			{
				my ($a, $b, $c) = ($1, $2, $3);
				if (length($a) == 1) { $a = "0".$a; }
				if (length($b) == 1) { $b = "0".$b; }
				if ($facility =~ /WFRWRKS_TW|OKMETIC_US/i)
				{
					$new_arr[1] = $c."-".$a."-".$b;  # change mm/dd/yyyy to yyyy/mm/dd
				}
				elsif ($facility =~ /SUNEDISON_US/i)
				{
					if ($a > 12) {
						$new_arr[1] = $c."-".$a."-".$b;
					}
					else {
						$new_arr[1] = $c."-".$b."-".$a;  # change dd/mm/yyyy to yyyy/mm/dd
					}
				}
				else
				{
					$new_arr[1] = $c."-".$b."-".$a;  # change dd/mm/yyyy to yyyy/mm/dd
				}
				$start_t = $new_arr[1] . " 00:00:00";
                        	$end_t  = $new_arr[1] . " 00:00:00";
			}
			elsif ($new_arr[1] =~ /(\d{1,2})\/(\d{1,2})\/(\d{4})/)
                        {
				my ($a, $b, $c) = ($1, $2, $3);
                                if (length($a) == 1) { $a = "0".$a; }
                                if (length($b) == 1) { $b = "0".$b; }
				if ($facility =~ /EPIWORLD_US|SUNEDISON_US|WFRWRKS_TW|SILT_US/i)
                                {
                                        if ($a > 12) {
                                                $new_arr[1] = $c."-".$b."-".$a;
                                        }
                                        else {
                                                $new_arr[1] = $c."-".$a."-".$b;  # change dd/mm/yyyy to yyyy/mm/dd
                                        }
                                }
                                else
                                {
                                        $new_arr[1] = $c."-".$b."-".$a;  # change dd/mm/yyyy to yyyy/mm/dd
                                }
                                $start_t = $new_arr[1] . " 00:00:00";
                                $end_t  = $new_arr[1] . " 00:00:00";
			}
		 	elsif ($new_arr[1] =~ /(\d{4})(\d{1,2})(\d{1,2})/) {  #20140910
				my ($a, $b, $c) = ($1, $2, $3);
				$new_arr[1] = $a."-".$b."-".$c;
				$start_t = $new_arr[1] . " 00:00:00";
                                $end_t  = $new_arr[1] . " 00:00:00";
			}
			else {
				#WARN ("DATE not defined");
			}
			#$start_t = $new_arr[1] . " 00:00:00";
			#$end_t	= $new_arr[1] . " 00:00:00";
		}
		elsif ($h_dummy[0] =~ /DELIVERY_NUMBER/i){
			my @new_arr = &clean_row(@h_dummy);
			$delivery_num = $new_arr[1];
		}
	}
	## Parse LOT sheet
	my $start_row ;
	my $last_col ;
	my $iC = 0 ;
	my $oWkC ;
	my ($mean, $min, $max, $sdev, $n, $sqrs, $sums, $cnt);
	my (@mean_arr, @min_arr, @max_arr, @sdev_arr, @n_arr, @sqrs_arr, @sums_arr, @cnt_arr);
	my (@tnum_arr, @tnam_arr, @unit_arr, @hlim_arr, @llim_arr);
	my $lot_cnt = 0;
	for(my $iR = $sh_l->{MinCol} ; defined $sh_l->{MaxRow} && $iR <= $sh_l->{MaxRow} ; $iR++)
	{
		$oWkC = $sh_l->{Cells}[$iR][$iC];
		if ($oWkC && $oWkC->Value =~ /PRODUCT NUMBER/i)
		{
			$start_row = $iR ;
			last ;
		}
	}
	if (! defined($start_row))
	{
		print "Titles not found.  Looking for Product Number" ;
	}

	my $iC ;
	my $oWkC ;
	my $field ;
	my %f ; # field index
	my $lot_id;
	for($iC = $sh_l->{MinCol} ; defined $sh_l->{MaxCol} && $iC <= $sh_l->{MaxCol} ; $iC++)
	{
		$oWkC = $sh_l->{Cells}[$start_row][$iC];
		if ($oWkC)
		{
			$field = $oWkC->Value ;
			$field =~ s/^\s+// ; # strip leading white space
			$field =~ s/\s+$// ; # strip trailing white space
			$field =~ s/\.+// ;   # strip periods
			$field = uc($field) ; # make it uppercase
			$field =~ s/S P E C I F I C A T I O N/SPECIFICATION/i ;
			$field =~ s/DELIVERY/DELY/i;
			$field =~ s/\s+/_/g ; # change white space to '_'
			$f{$field} = $iC ;  # define field
			#print "field=$field\n";
		}
	}
	$last_col = $iC ;

	foreach my $field ('DELY_NUM','LOT_NUMBER','LOT_QTY','PARAMETER','SPECIFICATION','MEAN','S','N','MIN','MAX')
	{
		if (! (defined($f{$field}) && ($f{$field} ne "")) )
		{
			print "$field field not found" ;
		}
	}

	my @history = ("-","-","-") ; # initialize history to be defined
	my $min_col = $sh_l->{MinCol} ;
	my $testNumberNoMic = 1001;
	for(my $iR = $start_row+1 ; defined $sh_l->{MaxRow} && $iR <= $sh_l->{MaxRow} ; $iR++)
	{
		shift @history ;  # buffer
		$oWkC = $sh_l->{Cells}[$iR][$min_col+1] ; # Use Delivery column (second column)
		my $value ;
		if ($oWkC)
			{ $value = $oWkC->Value ; }
		else
			{ $value = "" ; }
		push @history,$value ; # buffer
		last if (($history[0] eq "") && ($history[1] eq "") && ($history[2] eq "")) ;  # stop after three consecutive blank cells
		next if ($value eq "") ; # skip blank cells

		my $valueC ;
		# Delivery/Dely Num
		($valueC = $sh_l->{Cells}[$iR][$f{DELY_NUM}]) ;
		if (!defined $valueC)
		{
			print "Delivery Number not defined" ;
		}
		my $value = $valueC->Value ;
		$value =~ s/^\s+//g;
		$value =~ s/\s+$//g;
		if ($delivery_num eq "")
		{
			$delivery_num = $value;
		}
		# end of Delivery/Dely Num
		# LOT QTY
		($valueC = $sh_l->{Cells}[$iR][$f{LOT_QTY}]) ;
		if (!defined $valueC)
		{
			print "Lot Qty not defined";
		}
		my $value = $valueC->Value ;
		$value =~ s/^\s+//g;
                $value =~ s/\s+$//g;
		$cnt = $value;
		# end of LOT QTY

		{ # LOT NUMBER
			($valueC = $sh_l->{Cells}[$iR][$f{LOT_NUMBER}]) ;
			if (!defined $valueC)
			{
				print "Lot Number not defined" ;
			}
			my $value = $valueC->Value ;
			$value =~ s/\s//g ;
			$value =~ s/[\-\/\\]/_/g ;

			if ($value ne $lot_id) # Check for a new lot
			{
				$testNumberNoMic = 1001;
				$lot_id = $value;
				$lot_cnt++,
			}

		} # end lot field

		my $test_num = "";
		my $test_nam;
		if (defined $sh_l->{Cells}[$iR][$f{MIC}])
		{
			($valueC = $sh_l->{Cells}[$iR][$f{MIC}]) ;
			if (!defined $valueC)
			{
				print "MIC not defined" ;
			}
			$value = uc($valueC->Value) ;  # we make it upper case to minimize ascii value for single character
			$value =~ s/^\s+//g;
			$value =~ s/\s+$//g;
			if (! ($value =~ /^\s*[A-Z][A-Z]([A-Z])(.)(\d\d\d\d)\s*$/))
			{
				WARN("Could not parse codes from MIC");
				$value = "";
			}
			else
			{
				my $c3 = $1 ;
				my $c4 = $2 ;
				my $numeric = $3 ;
				$c3 = substr("00".ord($c3),-2) ;
				$c4 = substr("00".ord($c4),-2) ;
				$test_num = $c3.$c4.$numeric ;
			}
		}

		if($test_num eq "" || $test_num eq "0000")
		{
			$test_num = $testNumberNoMic;
		}

		{# Parameter
			($valueC = $sh_l->{Cells}[$iR][$f{PARAMETER}]) ;
			if (!defined $valueC)
			{
				print "Parameter field not defined" ;
			}
			my $value = uc($valueC->Value) ;
			$value =~ s/\.$// ;  # trailing .
			$value =~ s/[\(\)]//g ; # some are trailing
			$value =~ s/\,//g;
			$value =~ s/[^[:ascii:]]+/_/g;

			#if ($value =~ /Sub(\s+)Vendor|Sub(\s+)Lot/i)
			#{
			#	$value = "NONE";
			#}

			$test_nam = $value;

		}# end Parameter

		my ($lo_limit,$hi_limit,$units,$asdasdasd, $unit);

		{ # Specification
			my $value = "";
			($valueC = $sh_l->{Cells}[$iR][$f{SPECIFICATION}]);
			if (!defined $valueC )
			{
				$value = "NONE" ;
			}
			else
			{
				$value = $valueC->Value ;
			}
			$value = uc($value) ;
			$value =~ s/^\s+//g;
			$value =~ s/\s+$//g;
			$value =~ s/\,//g;


			if ($value =~ /^\s*([\d\.\-\+E]+)\s*[\-~]\s*([\d\.\-\+E]+)\s*(.+)\s*$/) # Ex: "6.00000 - 20.00000 ppma", "3~100ohm-cm"
			{
				$lo_limit = $1 ;
				$hi_limit = $2 ;
				#($units,$asdasdasd)= split(" ",$3) ;
				$units = $3 ;
				$units =~ s/\s*//g ;
			}
			elsif (  ($value =~ /^\s*([\d\.\-\+E]+)\s+MAX\.?\s+(.+)\s*$/) # Ex: "10 MAX PERC"
			      || ($value =~ /^\s*MAX\s+([\d\.\-\+E]+)\.?\s+(.+)\s*$/) # Ex: "MAX 10 PERC"
				  )
			{
				$lo_limit = "-1E20" ;
				$hi_limit = $1 ;
				($units,$asdasdasd)= split(" ",$2) ;
			}
			elsif (  ($value =~ /^\s*([\d\.\-\+E]+)\s+MIN\.?\s+(.+)\s*$/) # Ex: "10 MIN PERC"
			      || ($value =~ /^\s*MIN\s+([\d\.\-\+E]+)\.?\s+(.+)\s*$/) # Ex: "10 MIN PERC"
				  )
			{
				$lo_limit = $1 ;
				$hi_limit = "1E20" ;
				($units,$asdasdasd)= split(" ",$2) ;
			}
			elsif ($value =~ /^\s*NA\s*(.+)\s*$/) # Ex: "NAum"
			{
				$lo_limit = "-1E20" ;
				$hi_limit = "1E20" ;
				($units,$asdasdasd)= split(" ",$1) ;
			}
			elsif ($value =~ /[^\d]/) # Ex: "NONE", "um"
			{
				$lo_limit = "-1E20" ;
				$hi_limit = "1E20" ;
				($units,$asdasdasd)= $value ;
			}
			else
			{
				WARN( "Could not parse Specification: $value");
			}

			if    ($units eq "MICRON")	{	$units =  "uM";		}
			elsif ($units eq "µM" )		{	$units =  "uM";		}
			elsif ($units eq "Å")		{	$units =  "Ang";	}
			elsif ($units eq "#/WAFER")	{	$units =  "/WF";	}
			elsif ($units eq "PERC")	{	$units =  "%";		}
			$units =~ s/\s+/_/g ; # spaces not likely
			$units =~ s/\xB0/DEG/ ; # change degree character to deg (as in angle).

			if ($test_nam =~ /Sub(\s+)Vendor/i)
			{
        #$vendorIndexCounter= $iR;
        $vendor  = $value;
				$units = "";
			}
      if($test_nam =~ /Sub(\s+)Lot/i) {
        #$subconLotIndex = $iR;
        $subconLot = $value;
      }


		}# end Specification

		# Mean

		if ( defined $sh_l->{Cells}[$iR][$f{MEAN}] )
		{
			($valueC = $sh_l->{Cells}[$iR][$f{MEAN}]);
			my $value = $valueC->Value ;
			$value =~ s/^[^0-9.-]+//;
			if ($value eq "")
			{
				WARN("Mean value not defined at $iR") ;
				$mean = "";
			}
			else
			{
				$mean = $value;
			}
		}
		else
		{
			$mean = "";
		}
		# end Mean
		# S
		if ( defined $sh_l->{Cells}[$iR][$f{S}] )
		{
			($valueC = $sh_l->{Cells}[$iR][$f{S}]);
			my $value = $valueC->Value ;
			$value =~ s/^[^0-9.-]+//;
			if ($value eq "")
			{
				WARN("S value not defined") ;
				$sdev = "";
			}
			else
			{
				$sdev = $value ;
			}
		}
		else
		{
			$sdev = "" ;
		}
		# end S
		# N
		if ( defined $sh_l->{Cells}[$iR][$f{N}] )
		{
			($valueC = $sh_l->{Cells}[$iR][$f{N}]);
			my $value = $valueC->Value ;
			if (! $value || $value < 1)
			{
				WARN("Mean value not defined or less than 1");
				#$n = "1";
				$n = "";
			}
			else
			{
				$n = $value ;
			}
		}
		else
		{
			#$n = "1" ;
			$n = "";
		}
		#end N
		# MIN
		if ( defined $sh_l->{Cells}[$iR][$f{MIN}] )
		{
			($valueC = $sh_l->{Cells}[$iR][$f{MIN}]);
			my $value = $valueC->Value ;
			$value =~ s/^[^0-9.-]+//;
			if ($value eq "")
			{
				WARN("MIN value not defined") ;
				#if ( $mean ne "" )
				#{
				#	$min = $mean;
				#}
				$min = "";
			}
			else
			{
				$min = $value ;
			}
		}
		else
		{
			#if ( $mean ne "" )
			#{
			#	$min = $mean;
			#}
			$min = "";
		}
		# end min
		# MAX
		if ( defined $sh_l->{Cells}[$iR][$f{MAX}] )
		{
			($valueC = $sh_l->{Cells}[$iR][$f{MAX}]);
			my $value = $valueC->Value ;
			$value =~ s/^[^0-9.-]+//;
			if ($value eq "")
			{
				WARN("MAX value not defined") ;
				#if ( $mean ne "" )
				#{
				#	$max = $mean;
				#}
				$max = "";
			}
			else
			{
				$max = $value ;
			}
		}
		else
		{
			#if ( $mean ne "" )
			#{
			#	$max = $mean;
			#}
			$max = "";
		}
		# end MAX
		# Compute SUMS and SQRS
		if ($mean ne "" && $sdev ne "")
		{
			$sums = $mean * $n;
			$sqrs = ($mean**2.0) * $n;
		}
		# end SUMS and SQRS

		#print "STATS=$mean\t$sdev\t$n\t$min\t$max\t$sums\t$sqrs\n";
    if($test_nam !~ /Sub(\s+)Vendor|Sub(\s+)Lot/i) {
      push @{$mean_arr[$lot_cnt]}, $mean;
  		push @{$sdev_arr[$lot_cnt]}, $sdev;
  		push @{$n_arr[$lot_cnt]}, $n;
  		push @{$min_arr[$lot_cnt]}, $min;
  		push @{$max_arr[$lot_cnt]}, $max;
  		push @{$sums_arr[$lot_cnt]}, $sums;
  		push @{$sqrs_arr[$lot_cnt]}, $sqrs;
  		push @{$cnt_arr[$lot_cnt]}, $cnt;

  		push @{$tnum_arr[$lot_cnt]},$test_num;
  		push @{$tnam_arr[$lot_cnt]},$test_nam;
  		push @{$unit_arr[$lot_cnt]},$units;
  		push @{$hlim_arr[$lot_cnt]},$hi_limit;
  		push @{$llim_arr[$lot_cnt]},$lo_limit;
    }


		$td{$lot_id} = {
			PROG => $tpname,
			REV => $tprev,
			START_T => $start_t,
			END_T => $end_t,
			EQUIP1 => $equip1,
			EQUIP2 => $delivery_num,
			EQUIP5 => $equip5,
			PRODUCT => $product,
			PRODUCT_NUM => $product_num,
			MAT_TYPE => $mat_type,
      VENDOR => $vendor,
      SUBCONLOT => $subconLot,
			MIN => @{min_arr[$lot_cnt]},
			MAX => @{max_arr[$lot_cnt]},
			SDEV => @{sdev_arr[$lot_cnt]},
			MEAN => @{mean_arr[$lot_cnt]},
			SUMS => @{sums_arr[$lot_cnt]},
			SQRS => @{sqrs_arr[$lot_cnt]},
			#CNT => @{cnt_arr[$lot_cnt]},
			CNT => @{n_arr[$lot_cnt]},

			TNUM => @{tnum_arr[$lot_cnt]},
			TNAM => @{tnam_arr[$lot_cnt]},
			UNIT => @{unit_arr[$lot_cnt]},
			HLIM => @{hlim_arr[$lot_cnt]},
			LLIM => @{llim_arr[$lot_cnt]},
		};

		$testNumberNoMic++;
	} #end for loop

return \%td;

}

sub remove_unwanted_chars
{
        my $value = shift;
        $value =~ s/[^a-zA-Z0-9\-\_\.]/\-/gi;
        $value =~ s/\-{2,}/\-/g;
        $value =~ s/^\-+|\-+$//g;             ### REMOVE LEADING/TRAILING "-"
        return($value);
}

sub clean_string
{
        my $str = shift;
           $str =~ s/^\s+|\s+$//g;
	   $str =~ s/\,//g;
           $str =~ s/\s+/_/g;
        return($str);
}

sub clean_row
{
	my @arr     = @_;
	my @new_arr = ();
	foreach (@arr)
        {
        	if ($_ ne "undef" && $_ ne "")
                {
                	push (@new_arr, $_);
                }
        }
	return(@new_arr);
}

sub get_sheets
{
        my $oBook = shift ;
        my ($h,$l,$s) ;
        foreach my $oWkS (@{$oBook->{Worksheet}})
        {
                # print "--------- SHEET:", $oWkS->{Name}, "\n";
                #print "owks -  $oWkS \n";
				INFO("-------- SHEET:$oWkS->{Name}");
                $h = $oWkS if ((!defined($h)) && ($oWkS->{Name} =~ /_h$|_header$|header/i)) ;
                $l = $oWkS if ((!defined($l)) && ($oWkS->{Name} =~ /_l$|_I$|_lotstat$|lot/i)) ;
                #$s = $oWkS if ((!defined($s)) && ($oWkS->{Name} =~ /_s$|_shipstat$/)) ; # don't need shipstat sheet
                last if (defined($h) && defined($l)) ;
        }
        #die "Expecting sheet name ending in _h owks- $oWkS \n" if (!defined($h)) ;
        #die "Expecting sheet name ending in _l\n" if (!defined($l)) ;
	dpExit (1, "Expecting sheet name ending in _h owks- $oWkS") if (!defined($h)) ;
	dpExit (1, "Expecting sheet name ending in _l\n") if (!defined($l)) ;
        #die "Expecting sheet name ending in _s\n" if (!defined($s)) ;
        return($h,$l) ;
}
1;
