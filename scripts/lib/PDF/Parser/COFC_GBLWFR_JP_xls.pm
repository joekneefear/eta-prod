# 14-Jun-2017  Eric	: create
# 17-Aug-2017  Eric	: fixed script to handle misaligned specs against the measurement data
# 04-May-2018  Eric	: removed replacement/default values if N,MIN,MAX statistics are empty
# 08-May-2018  Eric     : Support Loading CoC data with new Specification with alpha-based revision and actual Customer values
# 12-Jan-2020  Glory    : Added support to parse sample data and compute its CNT,AVG,STDEV,MIN and MAX.
package PDF::Parser::COFC_GBLWFR_JP_xls;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use Spreadsheet::ParseExcel;
use Spreadsheet::ParseExcel::Utility qw(ExcelFmt);
use Statistics::Descriptive;
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
	my @models = ();
	my %uniqueTest;
	my $lot_cnt = 0;
	my $deliverynum = "";
	my $fname = basename $infile;
	my @fn_item = split /\_|\./, $fname;

	#get delivery num from filename
	foreach my $itm (@fn_item) {
		$deliverynum = $itm if ($itm =~ /^\d+[a-zA-Z]$/);
		last if $deliverynum ne "";
	}
		
	my $parser = Spreadsheet::ParseExcel->new();
	my $workbook = $parser->parse($infile);

    	if ( !defined $workbook ) {
        	die "Error ", $parser->error_code, ".\n";
    	}

    	for my $worksheet ( $workbook->worksheets() ) {
		my $customer = "";
		my $partno = "";
		my $proddate = "";
		my $spec = "";
		my $method = "";
		my $type = "";
		my $orientation = "";
		my $notch = "";
		my $frontsurf = "";
		my $backsurf = "";
		my $edgeprofile = "";
		my $qty = "";
		my $tpname = "";
		my $rev = "";
		my $lot = "";
		my $start_t = "";
		my $end_t = "";
		my @item = ();
		my $name = $worksheet->get_name();
		#print "SHEET = $name\n";
        	my ( $row_min, $row_max ) = $worksheet->row_range();
        	my ( $col_min, $col_max ) = $worksheet->col_range();

        	for my $row ( $row_min .. $row_max ) {
			my $datefmt = 'yyyy-mm-dd';
            	for my $col ( $col_min .. $col_max ) {
                	my $cell = $worksheet->get_cell( $row, $col );
                		next unless $cell;
				#$item[$col] = $cell->value();
				#print "$row, $col = $item[$col]\n";
				if (defined $cell->{Type} && $cell->{Type} eq 'Date') {
				    	#my $value = ExcelFmt($datefmt, $cell->{Val});
				    	#print "DATA=$value\n";
					$item[$col] = ExcelFmt($datefmt, $cell->{Val});
					#print "$row, $col = $item[$col]\n";
				}
				else {
					$item[$col] = $cell->value();
					#print "$row, $col = $item[$col]\n";
				}
            		}		
			if ($item[0] =~ /Customer\:/i) {
				$customer = $item[1];
				$method = $item[6];
				$frontsurf = $item[9];
				#print "$customer $method $frontsurf\n";
			}
			elsif ($item[0] =~ /Part No\./i) {
				$partno = $item[1];
				$type = remove_unwanted_chars($item[6]);
				$backsurf = $item[9];
				#print "$partno $type $backsurf\n";
			}
			elsif ($item[0] =~ /Production Date\:/i) {
				$proddate = $item[1];
				$orientation = $item[6];
				$edgeprofile = $item[9];
				$proddate = $proddate." "."00:00:00";
				$start_t = $proddate;
				$end_t = $proddate;
				#print "$proddate $orientation $edgeprofile\n";
			}	
			elsif ($item[0] =~ /Specification\:/i && $row == 6) {
				$spec = $item[1];
				$notch = $item[6];
				$qty = $item[9];
				$qty =~ s/\D+//i;
				if ($spec =~ /\//) {
					($tpname, $rev) = split /\//, $spec;
					$rev =~ s/\D+//;
				}
			        else {
					$rev = substr $spec, -1;
					$tpname = $spec;
				}
			}
			elsif ($item[0] =~ /Parameter/i) {
				$lot = $item[6];
				$lot_cnt++;			
			}
        	}

		my $start_row;
		my $last_col;
		my $iC = 0;
		my $oWkC;
		for(my $iR = $worksheet->{MinCol}; defined $worksheet->{MaxRow} && $iR <= $worksheet->{MaxRow}; $iR++) {
			$oWkC = $worksheet->{Cells}[$iR][$iC];
			if ($oWkC && $oWkC->Value =~ /Parameter/i) {
				$start_row = $iR+1;  #next row after "Parameter"
				last;
			}
		}

		my $iC;
		my $oWkC;
		my $field;
		my %f;
		for($iC = $worksheet->{MinCol}; defined $worksheet->{MaxCol} && $iC <= $worksheet->{MaxCol}; $iC++) {
			$oWkC = $worksheet->{Cells}[$start_row][$iC];
			if ($oWkC) {
				next if $oWkC->Value eq "";
				$field = $oWkC->Value;
				$field = uc($field);
				$f{$field} = $iC;
				#print "FIELD = $field\n";
			}
		}
		$last_col = $iC;

		foreach my $field ('N','X','S','MAX','MIN') {
			if ( ! (defined($f{$field}) && ($f{$field} ne ""))) {
				WARN ("$field field not found");
			}
		}

		my @history = ("-","-","-");
		my $min_col = $worksheet->{MinCol};
		my $tnum = 1;
		my $test_num = 0;
		my ($n, $s, $x, $min, $max, $sums, $sqrs);
		my (@n_arr, @s_arr, @x_arr, @min_arr, @max_arr, @sqrs_arr, @sums_arr, @cnt_arr);
		my (@tnum_arr, @tnam_arr, @unit_arr, @hlim_arr, @llim_arr);
		my $rawValue;
	        my $rawDataSampleFlag = 0;
		my @rawDataArray = ();
		my $sampleCell;
                my ($cell2,$cell3,$cell4) = "";
		my ($cell2Value,$cell3Value,$cell4Value);
		for (my $iR = $start_row+1; defined $worksheet->{MaxRow} && $iR <= $worksheet->{MaxRow}; $iR++) {
			shift @history; #buffer
			#$oWkC = $worksheet->{Cells}[$iR][$min_col+1]; # Use Delivery column (second column)
			$oWkC = $worksheet->{Cells}[$iR][$min_col];

			###Check each cellValue
=pod
			$cell2 = $worksheet->{Cells}[$iR][$min_col+1];
			$cell3 = $worksheet->{Cells}[$iR][$min_col+2];
			$cell4 = $worksheet->{Cells}[$iR][$min_col+3];
			if($cell2) {
			  $cell2Value = $cell2->unformatted;
			} else {
			  $cell2Value = "";
			}
			if($cell3) {
			  $cell3Value = $cell3->unformatted;
			} else {
			  $cell3Value = "";
			}
			if($cell4) {
			  $cell4Value = $cell4->unformatted;
			} else {
			  $cell4Value = "";
			}
=cut
                        ### Start loop cellValue
			if($worksheet->{Cells}[$iR][$min_col+6]) {
			  $sampleCell = $worksheet->{Cells}[$iR][$min_col+6]->Value;
			}
			
			my $value;
			if ($oWkC){
				$value = $oWkC->Value;
			}
			else
			{ 
				$value = "";
			}
			push @history,$value ; # buffer

                        ###  Start read sample raw data
			if(($value eq "") && ($sampleCell =~ /SAMPLE/i)) {
			  $rawDataSampleFlag = 1;
			}
                      
		        ###Stop loop  after REMARK 
	                last if ($value  =~ /remark/i);
		        next if ($value eq "") ; # skip blank cells

			my $valueC;	
			my $test_nam;
			my $unit;
			my $lo_limit;
			my $hi_limit;
			my ($colMin, $colMax) = $worksheet->col_range();

			#parameter
			#($valueC = $worksheet->{Cells}[$iR][$f{PARAMETER}]);
			($valueC  = $worksheet->{Cells}[$iR][$min_col]);
			my $value = uc($valueC->Value) ;
			$value =~ s/\.$// ;  # trailing .
			$value =~ s/[\(\)]//g ; # some are trailing
			$value =~ s/\,//g;
			$value =~ s/[^[:ascii:]]+/_/g;
			$test_nam = $value;		
			$test_num++;
			
			#unit
			($valueC  = $worksheet->{Cells}[$iR][$min_col+1]);		
			my $value = $valueC->Value;
			$unit     = $value;

			#lo limit
			($valueC  = $worksheet->{Cells}[$iR][$min_col+2]);
			my $value = $valueC->Value;
			$lo_limit = $value;
			#$lo_limit = "-1E20" if $lo_limit eq "";

			#hi limit
			($valueC  = $worksheet->{Cells}[$iR][$min_col+4]);
			my $value = $valueC->Value;
			$hi_limit = $value;
			#$hi_limit = "1E20" if $hi_limit eq "";

			#N	
			($valueC  = $worksheet->{Cells}[$iR][$min_col+5]);
			my $value = $valueC->Value;
			$n        = $value;
	                #$n	  = 1 if $n eq "" || $n < 1;

			#X=MEAN		
			($valueC  = $worksheet->{Cells}[$iR][$min_col+6]);
                        my $value = $valueC->Value;
                        $x        = $value;

			#S
			($valueC  = $worksheet->{Cells}[$iR][$min_col+7]);
                        my $value = $valueC->Value;
                        $s        = $value;

			#MAX
			($valueC  = $worksheet->{Cells}[$iR][$min_col+8]);
                        my $value = $valueC->Value;
                        $max      = $value;
			#$max	  = $n if $max eq "" && $n ne "";  

			#MIN
			($valueC  = $worksheet->{Cells}[$iR][$min_col+9]);
                        my $value = $valueC->Value;
                        $min      = $value;
			#$min      = $n if $min eq "" && $n ne "";

			###Compute if sampleFlag = 1
			if($rawDataSampleFlag == 1) {
			     my $colStart = $colMin+5;
			for my $col($colStart .. $colMax){
			     my $cell = $worksheet->get_cell($iR, $col);
		        next unless $cell;
			     my $cellValue = &clean_string(&cleanValue($cell->unformatted()));
			if($cellValue ne '') {
			     push(@rawDataArray, $cellValue); 
			    }
			  }
			  ($n,$x,$min,$max,$s) = &getStats(\@rawDataArray);
     			  @rawDataArray = ();
			}

			### Compute sums and sqrs
			if ($x ne "" && $s ne "") {
				$sums = $x * $n;
				$sqrs = ($x**2.0) * $n;
			}
				
			#print "TEST===$test_num $test_nam $unit $lo_limit $hi_limit $n $x $s $max $min $sums $sqrs\n";

			push @{$x_arr[$lot]}, $x;
			push @{$s_arr[$lot]}, $s;
			push @{$n_arr[$lot]}, $n;
			push @{$min_arr[$lot]}, $min;
			push @{$max_arr[$lot]}, $max;
			push @{$sums_arr[$lot]}, $sums;
			push @{$sqrs_arr[$lot]}, $sqrs;
			push @{$cnt_arr[$lot]}, $qty;	

			push @{$tnum_arr[$lot]}, $test_num;
			push @{$tnam_arr[$lot]}, $test_nam;
			push @{$unit_arr[$lot]}, $unit;
			push @{$hlim_arr[$lot]}, $hi_limit;
			push @{$llim_arr[$lot]}, $lo_limit;
			@rawDataArray = ();

			$td{$lot} = {
				CUSTOMER => $customer,
				METHOD 	 => $method,
				FRONT	 => $frontsurf,
				PARTNO   => $partno,
				TYPE     => $type,
				BACK     => $backsurf,
				PRDDATE  => $proddate,
				START_T  => $proddate,
				END_T	 => $proddate,
				ORIENT   => $orientation,
				EDGE	 => $edgeprofile,
				PROG     => $tpname,
				REV	 => $rev,
				NOTCH 	 => $notch,
				DELYNUM  => $deliverynum,
				QTY	 => $qty,
				MIN 	 => @{min_arr[$lot]},
				MAX 	 => @{max_arr[$lot]},
				SDEV 	 => @{s_arr[$lot]},
				MEAN 	 => @{x_arr[$lot]},
				SUMS 	 => @{sums_arr[$lot]},
				SQRS 	 => @{sqrs_arr[$lot]},
				#CNT 	 => @{cnt_arr[$lot]},
				CNT     => @{n_arr[$lot]},

				TNUM 	 => @{tnum_arr[$lot]},
				TNAM	 => @{tnam_arr[$lot]},
				UNIT	 => @{unit_arr[$lot]},
				HLIM	 => @{hlim_arr[$lot]},
				LLIM 	 => @{llim_arr[$lot]},
			};

		}

    	}#end worksheet

return \%td;

}
###Clean Value before & after
sub cleanValue() {
    my $value = shift;
       $value =~ s/^\<=|^\>=|^\=//g;
       return $value;
}

###Compute Standard Deviation.
sub getStats {
     my @rawData = @{$_[0]};
     my $stat = Statistics::Descriptive::Full->new();
     my $size = @rawData;
     my ($count, $x, $min, $max, $s);

  if($size > 1 ) {
     $stat->add_data(@rawData);
     $count = $stat->count();
     $x = $stat->mean();
     $min = $stat->min();
     $max = $stat->max();
     $s = $stat->standard_deviation();

} else {
     $x = $rawData[0];
     $min = $rawData[0];
     $max = $rawData[0];
     $s = 0;
     $count = $size;
} 
     @rawData = ();
      return($count,$x, $min, $max, $s);
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

1;

