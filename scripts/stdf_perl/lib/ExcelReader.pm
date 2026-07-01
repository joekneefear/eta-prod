#!/usr/bin/perl -w

#-----------------------------------------------------------------------------#
#-----------------------------------------------------------------------------#
# ExcelReader -
#	This module can be used to access data from an Excel Spread Sheet
#
# Confidential Property of Fairchild Semiconductor Corperation
# (c) Copyright Fairchild Semiconductor Corperation, 1999
# All rights reserved
#
# MODIFICATION HISTORY:
#
# DATE        WHO             DESCRIPTION
# ___________ ______________  __________________________________________________
# 27 Aug 2002 Seetha V.Shetty  Original
#
#-----------------------------------------------------------------------------#
#-----------------------------------------------------------------------------#

use strict;


package ExcelReader;

use Carp;
use Spreadsheet::ParseExcel; 

#-----------------------------------------------------------------------------#
#Create a new instance of ExcelReader 
#-----------------------------------------------------------------------------#
	sub new
	{
		  shift;
		  my $file = shift;
		  my $oExcel = new Spreadsheet::ParseExcel;
		  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse($file);
		  return bless $oBook;
	}
#-----------------------------------------------------------------------------#
#Method to access the name of the file
#-----------------------------------------------------------------------------#
	sub filename
	{
		  my $oBook = shift;
		  return $oBook->{File};
	}
#-----------------------------------------------------------------------------#
#Method to access the count of sheets in the file
#-----------------------------------------------------------------------------#
	sub sheetcount
	{
		  my $oBook = shift;
		  return $oBook->{SheetCount};
	 }
#-----------------------------------------------------------------------------#
#Method to access the author of the file
#-----------------------------------------------------------------------------#
	sub author
	{
		  my $oBook = shift;
		  return $oBook->{Author};
	}
#-----------------------------------------------------------------------------#
#Method to access the max populated columns in the worksheet in letters
#-----------------------------------------------------------------------------#
	sub maxcolumns
	{
		 my $oBook = shift;
		 my $worksheet = shift;
		 return int2col($worksheet->{MaxCol});
	}
#-----------------------------------------------------------------------------#
#Method to access the max populated rows in the worksheet 
#-----------------------------------------------------------------------------#
	sub maxrows
	{
		 my $oBook = shift;
		 my $worksheet = shift;
		 return ($worksheet->{MaxRow});
	}
#-----------------------------------------------------------------------------#
#Method to access the max populated columns in the worksheet
#-----------------------------------------------------------------------------#
	sub maxcolumncount
	{
		 my $oBook = shift;
		 my $worksheet = shift;
		 return ($worksheet->{MaxCol});
	}
#-----------------------------------------------------------------------------#
#Method to access the max populated columns in the worksheet
#-----------------------------------------------------------------------------#
	sub convert2letter
	{
		 my $oBook   = shift;
		 my $integer = shift;
		 return int2col($integer);
	}
#-----------------------------------------------------------------------------#
#Method to access the max populated columns in the worksheet
#-----------------------------------------------------------------------------#
	sub convert2int
	{
		 my $oBook   = shift;
		 my $letter  = shift;
		 return col2int($letter);
	}
#-----------------------------------------------------------------------------#
#Method to access the value in the specified cell of a worksheet in the file
#-----------------------------------------------------------------------------#
	sub readfromcell
	{
		  my $oBook     = shift;
		  my $worksheet = shift;
		  my $cellpos   = shift;
			
		  my @cell      = sheetRef($cellpos);
		  my $col       = 0;
          my $row       = 0;
		  $row          = $cell[0];
		  $col          = $cell[1];	

		  my $cell  = $worksheet->{Cells}[$row][$col];
		  		  
		  if(defined $cell)
		  { return $cell->Value; }
		  else
		  { return "undef"; }
	}
#-----------------------------------------------------------------------------#
#Method to access the value in the specified cell of a worksheet in the file
#-----------------------------------------------------------------------------#
        sub readvalfromcell 
        {
                  my $oBook     = shift;
                  my $worksheet = shift;
                  my $cellpos   = shift;
                        
                  my @cell      = sheetRef($cellpos);
                  my $col       = 0;
          my $row       = 0;
                  $row          = $cell[0];
                  $col          = $cell[1];
 
                  my $cell  = $worksheet->{Cells}[$row][$col];
                                 
                  if(defined $cell)
                  { return $cell->{Val}; }
                  else  
                  { return "undef"; }
        }            

 #-----------------------------------------------------------------------------#
 #Method to get all the worksheet names in the given file
 #-----------------------------------------------------------------------------#
	sub getworksheets
	{
		my $oBook              = shift;
		my $worksheetptrarray  = shift;

		my ($wsheetnum,$wsheetnam);
		my ($tempsheetnum,$tempsheetnam);
		my $undefined =0;
		foreach my $oWkS (@{$oBook->{Worksheet}}) {

			push @$worksheetptrarray, $oWkS;
		}

		#once I have data have another foreach and change the names
		#undef on name and undef and sheet num,if not defined cells 
		foreach my $wsheet (@$worksheetptrarray) {
			if(!defined $wsheet->{Cells})
			{
				$wsheetnum = $wsheet->{_SheetNo};
				$wsheetnam = $wsheet->{Name};
				undef $wsheet->{_SheetNo};
				undef $wsheet->{Name};
				$undefined = 1;
				next;
			}
			if($undefined)
			{
				$tempsheetnum = $wsheet->{_SheetNo};
				$tempsheetnam = $wsheet->{Name};
				$wsheet->{_SheetNo}  = $wsheetnum;
				$wsheet->{Name}      = $wsheetnam;
				$wsheetnum = $tempsheetnum;
				$wsheetnam = $tempsheetnam;
			}

		}
		#foreach my $oWkS (@$worksheetptrarray) {
		#	foreach my $key (sort keys %$oWkS)
		#	{
		#		print "$key     =>    $oWkS->{$key}\n";
		#	}
		#	print "\n";
		#}
		return;
	}

 #-----------------------------------------------------------------------------#
 #Method to access the values of cells in a given range
 #This is a manipulated version of code taken from Utility.pm
 #-----------------------------------------------------------------------------#
	sub extractrange 
	{
		 #ex:(A1:B2 for sheet 1)
		 my $oBook     = shift;
		 my $worksheet = shift;
		 my $regions   = shift;
		 my $matrix    = shift;

		 my $output    = "" ;   
		
		# extract worksheet number 
	      $worksheet   = $worksheet - 1 ;
		 
		# now extract the start and end regions
		  $regions =~ m/(.*):(.*)/ ;

	    #worksheet out of range
		if($worksheet < 0 || ($worksheet > $oBook->{SheetCount}))
		{
			return "unavailable as worksheet number is out of range\n" ;
		}
		if(!$regions) {
			print STDERR "Bad Params\nFormat = A1:R6\n";
			return "" ;
		}

	    my @start = sheetRef( $1) ;
	    my @end   = sheetRef( $2) ;

	    if( !@start) {
			print STDERR "Bad coorinates - $1\n";
			return "" ;
	    }
	    if( !@end) {
			print STDERR "Bad coorinates - $2\n";
			return "" ;
	    }
	   
	   if( $start[1] > $end[1]) {

			print STDERR "Bad COLUMN ordering\n";
			print STDERR "Start column " . int2col($start[1]);
			print STDERR " after end column " . int2col($end[1]) . "\n";
			return "" ;
	   }
	   if( $start[0] > $end[0]) {

			print STDERR "Bad ROW ordering\n";
			print STDERR "Start row " . ($start[0] + 1);
			print STDERR " after end row " . ($end[0] + 1) . "\n";
			exit ;
	   }
	   
	   my $oWkS = $oBook->{Worksheet}[ $worksheet] ;

	   # now check that the region exists in the file
	   # if not trucate to the possible region
	   # output a warning msg
	   if( $start[1] < $oWkS->{MinCol}) {
			print STDERR int2col( $start[1]) . " < min col " . int2col( $oWkS->{MinCol}) . " Resetting\n";
			$start[1] = $oWkS->{MinCol} ;
	   }
	   if( $end[1] > $oWkS->{MaxCol}) {
			print STDERR int2col( $end[1]) . " > max col " . int2col( $oWkS->{MaxCol}) . " Resetting\n";
			$end[1] = $oWkS->{MaxCol} ;
	   }
	   if( $start[0] < $oWkS->{MinRow}) {
			print STDERR "" . ($start[0] + 1) . " < min row " . ($oWkS->{MinRow} + 1) . " Resetting\n";
			$start[0] = $oWkS->{MinCol} ;
	   }
	   if( $end[0] > $oWkS->{MaxRow}) {
			print STDERR "" . ($end[0] + 1) . " > max row " . ($oWkS->{MaxRow} + 1) . " Resetting\n";
			$end[0] = $oWkS->{MaxRow} ;
	   
	   }

	   my $x1 = $start[1] ;
	   my $y1 = $start[0] ;
	   my $x2 = $end[1] ;
	   my $y2 = $end[0] ;
	   
	#	my $colwidth = ();
		for( my $y = $y1 ; $y <= $y2 ; $y++) 
		{
			$output = "[ ";
		   for( my $x = $x1 ; $x <= $x2 ; $x++) 
		   {
			  my $cell = $oWkS->{Cells}[$y][$x] ;
			  $output .=  $cell->Value if(defined $cell);
			  $output .= "," if( $x != $x2) ;

	#		  if($x == 0)
	#		  {
	#			  $colwidth[$y] = length($cell->Value);
	#		  }
	#		  if(length($cell->Value) > $colwidth[$y])
	#		  {
	#			  $colwidth[$y] = length($cell->Value);
	#		  }
		   }
		   $output .= " ]\n" ;
		   push @$matrix,$output;
		   
		   $output = "";
		}
		return ;
}
	
 # -----------------------------------------------------------------------------
 # sheetRef (for Spreadsheet::ParseExcel::Utility) #code taken from Utility.pm
 #------------------------------------------------------------------------------
 # -----------------------------------------------------------------------------
 # sheetRef
 # convert an excel letter-number address into a useful array address
 # @note that also Excel uses X-Y notation, we normally use Y-X in arrays
 # @args $str, excel coord eg. A2
 # @returns an array - 2 elements - column, row, or undefined
 #
	sub sheetRef {
		my $str = shift ;
		my @ret ;

		$str =~ m/^(\D+)(\d+)$/ ;

		if( $1 && $2) {
			push( @ret, $2 -1, col2int($1)) ;
		}
		if( $ret[0] < 0) {
			undef @ret ;
		}

		return @ret ;
}


 # -----------------------------------------------------------------------------
 # col2int (for Spreadsheet::ParseExcel::Utility) #code taken from Utility.pm
 #------------------------------------------------------------------------------
 # converts a excel row letter into an int for use in an array
	sub col2int {
		my $result = 0 ;
		my $str = shift ;
		my $incr = 0 ;
		for(my $i = length($str) ; $i > 0 ; $i--) {
			my $char = substr( $str, $i-1) ;
			my $curr += ord(lc($char)) - ord('a') + 1;
			$curr *= $incr if( $incr) ;
			$result += $curr ;
			$incr += 26 ;
		}
		# this is one out as we range 0..x-1 not 1..x
		$result-- ;

    return $result ;
 }
 # -----------------------------------------------------------------------------
 # int2col (for Spreadsheet::ParseExcel::Utility)
 #------------------------------------------------------------------------------
 # int2col
 # convert a column number into column letters
 # @note this is quite a brute force coarse method
 #  does not manage values over 701 (ZZ)
 # @arg number, to convert
 # @returns string, column name
 #
	sub int2col {
	   my $out = "" ;
	   my $val = shift ;
	   
	   do {
		  $out .= chr(( $val % 26) + ord('A')) ;
		  $val = int( $val / 26) - 1 ;
	   } while( $val >= 0) ;
	   
	   return reverse $out ;
 }
 #-----------------------------------------------------------------------------#
 #-----------------------------------------------------------------------------#
	
	
return 1;



