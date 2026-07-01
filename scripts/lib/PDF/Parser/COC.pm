# 13-Nov-2015 Eric	: convert units Angstrom, micron sign to alpha representaion.
package PDF::Parser::COC;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;
use Spreadsheet::ParseExcel;


our $VERSION = "1.0";
our $mat_type = "";
my $testNum = 1;
my ($oWkS,$oWkC, $start_row, $last_col );
my $attr = [];

sub getMatType
{
	return $mat_type;
}

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

sub readFile {
    my $self   = shift;
    my $infile = shift;
	my $platform = shift;
    my $header = new_headerLong;
	my @container_model = ();
    my $model  = new_model(
        {   header => $header,
            misc   => {},
            dataSource => 'COC'
        }
    );
    my $wafers = {};
    my $waferSites = {};
    my ($tUnits,$tHI,$tLO) = (0,0,0);
	my ($waferNum, $sensor);
	
	my $xls = Spreadsheet::ParseExcel::Workbook->Parse($infile) ;
    
	#
	# look for the sheets that we need
	# sh_h is the header
	# sh_l is the detail
	# sh_s is the summary (not converted)
	#
	my ($sh_h, $sh_l) = get_sheets($xls) ;
	
	### read header sheet
	my $ord_col = $sh_h->{MinCol} ;
	my $prod_col ;
	my $iC = $sh_h->{MinCol} ;
	my $facility;
	my $delivery_num;

	for(my $iR = $ord_col ; defined $sh_h->{MaxRow} && $iR <= $sh_h->{MaxRow} ; $iR++)
	{
		$oWkC = $sh_h->{Cells}[$iR][$iC];
		
		if ($oWkC && $oWkC->Value =~ /ORDER INFORMATION/i)
		{
			$start_row = $iR ;	
		
			last ;
		}
	}
	
	if (! defined($start_row))
	{		
		print "Order Information not found" ;
		
	}
	
	for(my $iC = $ord_col ; defined $sh_h->{MaxCol} && $iC <= $sh_h->{MaxCol} ; $iC++)
	{
		$oWkC = $sh_h->{Cells}[$start_row][$iC];
		
		if ( $oWkC && $oWkC->Value =~ /Product Description/i)
		{
			$prod_col = $iC ;
			
			last ;
		}
		
	}
	if (! defined($prod_col))
	{		
		print "Product Description not found" ;
	
	}
	
	$iC = $ord_col ;
	my $blank_row = 0;
	for(my $iR = $start_row+1 ; defined $sh_h->{MaxRow} && $iR <= $sh_h->{MaxRow} && $blank_row < 4 ; $iR++)
	{
		my $nameC = $sh_h->{Cells}[$iR][$iC];
		my $valueC = $sh_h->{Cells}[$iR][$iC+1];
		if ($nameC && $valueC)
		{
			my $name=$nameC->Value ;
			my $value=$valueC->Value ;
			$name =~ s/^\s+//g;
			$name =~ s/\s+$//g;
		    
			if ($name eq "")
			{
				$blank_row++;
				next;
			}			
			
			if ($name =~ /CUSTOMER:$|CUSTOMER$/i)
			{
				$value =~ s/[\/\s\-]/_/g ;
				# try translating to a specific FSC plant
				$value = 'FSME' if $value =~ /FSME|Maine|Portland/i;
				$value = 'FSPA' if $value =~ /FSPA|Mountain|Pens|Wilkes/i;
				$value = 'FSSL' if $value =~ /FSSL|Salt|Utah|Jordan/i;
				$value = 'FSBK' if $value =~ /FSBK|FBSC|Bucheon|Korea/i;
				$value = 'CSMC' if $value =~ /CSMC/i;
		
				$header->EQUIP5_ID($value);
				
			}
			elsif ($name =~ /SPECIFICATION NUMBER/i)
			{
				$value = uc $value;

				if ($value =~ /.+[\/\s](MAT\d+R.+)/)  
				{
					# Move MAT# to the front (ex: "SPT001R3/MAT002REV2" to "MAT002REV2/SPT001R3"
					my $mat = $1;
					my $spt = substr($value,0,index($value,"MAT"));
					$value = $mat." ".$spt;
				}
				$value =~ s/[\/\s]/_/g ;				
								
				# spec name is entire$$emir{spec_nam} string up to the last occurance of REV# or R#.
				if ($value =~ s/_*REV\.?_*\.*([\d\.]+)_*$//i 
					|| $value =~ s/_*R\.?_*\.*([\d\.]+)_*$//i
					|| $value =~ s/_*-(\d+\.\d+)$//i)
				{					
					$header->REVISION($1);
					if ((my $pos=index($header->REVISION,'.')) > -1 )
					{
						
						$header->REVISION($header->REVISION * $pos * 10);
						if ($header->REVISION > 999)
						{
							INFO(" exceeds 999, the max for resolve_tp") ;
						}
					}
					$header->REVISION( $header->REVISION);
				}
				else
				{					
					$header->REVISION(1);
				}
				
				$header->PROGRAM($value);
			
			}
			elsif ($name =~ /PART NUMBER/i) # This is FSC's part number (very important)
			{
				$value =~ s/[\/\s\-]/_/g ;
			    $header->PRODUCT( $value ) ;
			
			}
			elsif ($name =~ /PRODUCT NUMBER/i && $value ne "") # This is the vender's part number (not important)
			{
				$value =~ s/[\/\s\-]/_/g ;
				#$header->PRODUCT($value) ;
			}
			elsif ($name =~ /PRODUCT LINE/i)
			{
				
				$value  =~ s/_//g ;
				$header->EQUIP1_ID($value);
				
			}
			elsif ($name =~ /DATE/i)
			{
				if ($value =~ /(\d{4})(\d{2})(\d{2})/) # change yyyymmdd to yyyy/mm/dd
				{
					$value = $1."-".$2."-".$3;
				}
				elsif ($value =~ /(\d{1,2})\/(\d{1,2})\/(\d{4})/)
				{
					print "$value\n";
					my ($a, $b, $c) = ($1, $2, $3);
					if (length($a) == 1) { $a = "0".$a; }
					if (length($b) == 1) { $b = "0".$b; }
					print "a=$a b=$b c=$c\n";
					if ($facility =~ /WFRWRK|OKMETC/i) 
					{
						$value = $c."-".$a."-".$b;  # change mm/dd/yyyy to yyyy/mm/dd
						print "value=$value\n";
					}
					else
					{
						$value = $c."-".$b."-".$a;  # change dd/mm/yyyy to yyyy/mm/dd
					}
				}
				
				$header->START_TIME($value. " 00:00:00");
				$header->END_TIME($value. " 00:00:00");
			}
			elsif ($name =~ /DELIVERY NUMBER/i)
			{
				$delivery_num = $value ;
				
			}
			
		}
	}
	
	
	#
	# find Product Descriptions
	# Populate information into EWB by using epdr records
	# test name will be parameter name
	# test txt will be parameter value
	# single "dummy" tsr is required for EWB to extract values
	#
	$mat_type = "SUB";
	my $test_num = 1 ; # starting test number
	my $test_num_incr = 1 ; # increment for test number
	{
		my $iC = $prod_col ;
		my $blank_row = 0;
		
		for(my $iR = $start_row+1 ; defined $sh_h->{MaxRow} && $iR <= $sh_h->{MaxRow} && $blank_row < 4 ; $iR++)
		{
			my $nameC = $sh_h->{Cells}[$iR][$iC];
			my $valueC = $sh_h->{Cells}[$iR][$iC+1];
			if ($nameC && $valueC)
			{
				my $name=$nameC->Value ;
				my $value=$valueC->Value ;
				$name =~ s/[^[:ascii:]]+//g;
				$name =~ s/^\s+//g ;
				$name =~ s/\s+$//g ;
				$value =~ s/[^[:ascii:]]+/_/g;
				$value =~ s/^\s+//g ;
				$value =~ s/\s+$//g ;
				if ($name eq "")
				{
					$blank_row++;
					next;
				}
				if ($name =~ /^Mater.*\s+Type\:?$/i && $value =~ /epi/i)
				{
					$mat_type = "EPI";
				}
			
			}
		}
	}
	
	
	
	
	##### read detail
	my $iC = 0 ;
	my $oWkC ;
	my ($mean, $min, $max, $sdev, $n, @dies, $wafer, $die);
	my (%hash_min, %hash_max, %hash_mean, %hash_sums,%hash_sdev, %hash_sqrs); 	
	
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
	my @td_sessions ;  # allow multiple lots per input file
	my $td_session ;  # current session
	my $emir ; # emir for current session

	my $iC ;
	my $oWkC ;
	my $field ;
	my %f ; # field index
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
	#
	# check field list
	# 
	foreach my $field ('DELY_NUM','LOT_NUMBER','LOT_QTY','PARAMETER','SPECIFICATION','MEAN','S','N','MIN','MAX')
	{
		if (! (defined($f{$field}) && ($f{$field} ne "")) )
		{
			
			INFO($field ."field not found") ;
			
		}
	}
	
	my @history = ("-","-","-") ; # initialize history to be defined
	my $min_col = $sh_l->{MinCol} ;
	my $testNumberNoMic = 1001;
	for(my $iR = $start_row+1 ; defined $sh_l->{MaxRow} && $iR <= $sh_l->{MaxRow} ; $iR++)
	{
		#
		# Check for empty cells at the bottom
		# Three consecutive cells are assumed to be the end
		# A single empty cell is skipped
		#
	
		$oWkC = $sh_l->{Cells}[$iR][$min_col+1] ; # Use Delivery column (second column)
		my $value ;
		if ($oWkC)
			{ $value = $oWkC->Value ; }
		else
			{ $value = "" ; }
		push @history,$value ; # buffer
		#last if (($history[0] eq "") && ($history[1] eq "") && ($history[2] eq "")) ;  # stop after three consecutive blank cells
		if (($history[0] eq "") && ($history[1] eq "") && ($history[2] eq ""))   # stop after three consecutive blank cells
		{
		
				INFO("dies count:". $#dies);
			
			last;
		}
		next if ($value eq "") ; # skip blank cells
		#
		# Column
		#
		# for($iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++)
		my $valueC ;

		# Capture the delivery number if not available in header sheet
		$valueC = $sh_l->{Cells}[$iR][$f{DELY_NUM}] ;		
		$value = $valueC->Value ;
		$value =~ s/^\s+//g;
		$value =~ s/\s+$//g;		
		
		#INFO("dely_num:".$value);
		
		### parameter
		my $test_num = "";
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
				#wlog(0,"Could not parse codes from MIC\n") ;
				#confess ;
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
		
		foreach my $field ('DELY_NUM','LOT_NUMBER','LOT_QTY','PARAMETER','MEAN','S','N','MIN','MAX','SPECIFICATION')
		{		
		
			$value = "";
			$valueC = $sh_l->{Cells}[$iR][$f{$field}] ;		
			$value = $valueC->Value if $valueC ;
			$value =~ s/^\s+//g;
			$value =~ s/\s+$//g;	
			
			if($field eq "DELY_NUM"){
				
				$header->LOT($value);
			}
			
			if($field eq "LOT_NUMBER"){
			
				
						
				if($waferNum ne ""  &&
				   $waferNum ne $value)
				   {			
						
						my $test = $model->tests;
						 $die = new_die;
						  my $dies;
						foreach my $tt (@$test)
						{
							#INFO("tt:".$tt->number. $hash_min{$tt->number});
							 
							$die->add( 'level', "lot");
							$die->add( 'min', $hash_min{$tt->number});							
							$die->add( 'max', $hash_max{$tt->number});							
							$die->add( 'mean', $hash_mean{$tt->number});							
							$die->add( 'sums', $hash_sums{$tt->number});							
							$die->add( 'sqrs', $hash_sqrs{$tt->number});							
							$die->add( 'sdev', $hash_sdev{$tt->number});							
						}
						 push @$dies, $die;
						 
						#$wafer->dies(@dies);
						$model->dies($dies);
						#INFO("dies count:". $#dies);						
						push @container_model, $model;
						$model = new_model(
									{   header => $header,
										misc   => {},
										dataSource => 'COC'
									}
								);
						$testNumberNoMic = 1001;
						$test_num = $testNumberNoMic;
				   }
				if($value ne ""){
					$waferNum = $value;
					
					
					$wafer = $model->find('wafers',{number => $waferNum});
					unless (defined $wafer){
						$wafer = new_wafer( { number => $waferNum } );
						$model->add('wafers',$wafer);
					}
				}				
			}			

			my ($lo_limit,$hi_limit,$units,$asdasdasd, $unit);
			if($field eq "PARAMETER"){
			
				if ($value =~ /Sub(\s+)Vendor|Sub(\s+)Lot/i) 
				{
					$value = "NONE";

				}			
				$sensor = $value;
			}
			if($field eq "MEAN"){
				$mean = $value;
			}
			if($field eq "MIN"){
				$min = $value;
			}
			if($field eq "S"){
				$sdev = $value;
			}
			if($field eq "N"){
				$n = $value;
			}
			if($field eq "MAX"){
				$max = $value;
			}
			if($field eq "SPECIFICATION"){
				
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
			
					print "Could not parse Specification: $value" ;
					
				}	
				
				if    ($units eq "MICRON")	{	$units =  "uM";		}
				elsif ($units eq "\265"."M" ) {$units =  "uM";}
				elsif ($units eq "\265"."m" ) {$units =  "um";}
				elsif ($units eq "\305" ) {$units =  "Ang";}
				elsif ($units eq "#/WAFER")	{$units =  "/WF";	}
				elsif ($units eq "PERC")	{$units =  "%";		}
				$units =~ s/\s+/_/g ; # spaces not likely
				$units =~ s/\xB0/DEG/ ; # change degree character to deg (as in angle).

				my $test = new_test;
				$test->number( repNA($test_num) );
				#$sensor =~ s/\s+//g;
				$test->name( repNA($sensor) );
				$test->units( repNA( $units ) );
				
				$test->HSL( repNA($hi_limit));
				$test->LSL( repNA($lo_limit));
				$test->HPL( repNA(""));
				$test->LPL( repNA(""));
				$test->HOL( repNA(""));
				$test->LOL( repNA(""));
				$test->LWL( repNA(""));
				$test->HWL( repNA(""));
				
				if($min eq "")
				{					
					if($mean ne ""){
						$test->{min} = $mean;
					}
				}
				else{
					$test->{min} = $min;
				}
				
				if($max eq ""){
					if($mean ne ""){
						$test->{max} = $mean;
					}
				}
				else{
					$test->{max} = $max;
				}
				
				if($mean eq ""){
					$test->{mean} = "";
				}
				else{
						$test->{mean} = $mean;
				}							
				
				if($sdev eq ""){
				
					$test->{sdev} = "";
				}
				else{
					$test->{sdev} = $sdev;
				}				
				
				if (! $n || $n < 1)
				{
					
					$test->{n} = "1" ;
					##confess ;
				}
				else
				{
					$test->{n} = $n;
				}
				
				if ($mean ne "" && $sdev ne "") 
				{
					$test->{sums} = $mean*$n;
					$test->{sqrs} = ($mean**2.0) * $n;					
				}

				#$test->{std} = ;
				
				
				$test->group( repNA( "" ) );
				unless ($sensor eq "NONE")
				{
					$model->add( 'tests', $test );									
					
					$hash_min{$test_num} = $test->{min};				
					$hash_max{$test_num} = $test->{max};					
					$hash_sdev{$test_num} = $test->{sdev};					
					$hash_mean{$test_num} = $test->{mean};					
					$hash_sums{$test_num} = $test->{sums};				
					$hash_sqrs{$test_num} = $test->{sqrs};				
				}				
			}
				
		}
				
		$testNumberNoMic++;
		
		
	}	
	
	my $test = $model->tests;
	$die = new_die;
	my $dies;
	foreach my $tt (@$test)
	{		
		$die->add( 'level', "lot");
		$die->add( 'min', $hash_min{$tt->number});							
		$die->add( 'max', $hash_max{$tt->number});							
		$die->add( 'mean', $hash_mean{$tt->number});							
		$die->add( 'sdev', $hash_sdev{$tt->number});							
		$die->add( 'sums', $hash_sums{$tt->number});							
		$die->add( 'sqrs', $hash_sqrs{$tt->number});							
	}
	push @$dies, $die;

	$model->dies($dies);
	
	push @container_model, $model;	
		
    return @container_model;
}

sub get_sheets
{
	my $oBook = shift ;
	my ($h,$l) ;
	foreach my $oWkS (@{$oBook->{Worksheet}})
	{
		# print "--------- SHEET:", $oWkS->{Name}, "\n";
		#print "owks -  $oWkS \n";
		$h = $oWkS if ((!defined($h)) && ($oWkS->{Name} =~ /_h$|_header$/i)) ;
		$l = $oWkS if ((!defined($l)) && ($oWkS->{Name} =~ /_l$|_lotstat$/i)) ;
		#$s = $oWkS if ((!defined($s)) && ($oWkS->{Name} =~ /_s$|_shipstat$/)) ; # don't need shipstat sheet
		last if (defined($h) && defined($l)) ;
	}
	die "Expecting sheet name ending in _h owks- $oWkS \n" if (!defined($h)) ;
	die "Expecting sheet name ending in _l\n" if (!defined($l)) ;
	#die "Expecting sheet name ending in _s\n" if (!defined($s)) ;
	return($h,$l) ;
}

1;

