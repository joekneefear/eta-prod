#CHANGES
#  2015/07/28 grace : included a space before and after the "-" between the appended portions of the test name
#                     increased the end date by 1 day when the end time is earlier than the start time	
#                     auto-increment the partid for each row of readings in the Map2 sheet as well as each row of defect (bin) result in the Map sheet.   should then be able to accurately join the bin and parametric results by partid.
#  2015/08/26 jgarcia:Capitalized product and lot.
#  2015/10/04 eric   : fixed parsing of extracted file if files contains multiple wafers.
#  2017/02/21 eric   : truncate testname if greater than 64 chars
#  2017/02/21 eric   : skip lines if line start with digits+ms
#  2017/05/02 eric   : store errors as misc
#  2020/09/24 eric   : restored to previous version r2147 and set SOFT_BIN = 1001 if empty
#  2010/09/24 eric   : replace NA for empty test results.
#  2025/05/06 eric	: modified to handle old and new magazine format
#  
package PDF::Parser::AUTOV;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use Time::Local;
use File::Basename qw/basename/;
use File::Path qw(remove_tree);
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";
my $testNum = 1;

my $attr = [];
my %bin = ();
my %sbin = ();
my @bins;
my %binCount; 
my $good_bin;

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

sub getbins {

	my %unique;
	foreach my $binNum (sort keys %sbin) {
		my $bin = new_bin({
			number => $binNum,
			count => $sbin{$binNum}{COUNT},
			name => $sbin{$binNum}{NAME}
		});		
		
		$bin->PF( ($bin->count == $good_bin) ? 'P' : 'F');

		 $unique{$binNum} = $bin;
	}
	
	

    foreach my $binNum ( sort { $a <=> $b } keys %unique ) {
        push @bins, $unique{$binNum};
    }
    return \@bins;
}

sub readFile {
    my $self   = shift;
    my $inDir = shift;
    my $isLogDebug = shift;
    my $header = new_headerLong;
    my $model  = new_model(
        {   header => $header,
            misc   => {},
            dataSource => 'AV'
        }
    );
    my $wafers = {};
    my $waferSites = {};
    my ($tUnits,$tHI,$tLO) = (0,0,0);
	my $summary_file = "";
	my $map1_file = "";
	my $map2_file = "";
	my $defect_file = "";
	my $date = "";
	my @container_inx = ();	
	my %prefix = ();
	my $images_directory = "";
	
		
	#### list from CompleteExport.txt
    	#open (INFILE, "<",$inDir."/CompleteExport.txt");
	#my @complete_list = <INFILE>;
	#close (INFILE);
	####
	
	#### extracted files from temp
	opendir DIR, $inDir or die "cannot open dir $inDir: $!";
	my @file= readdir DIR;
	closedir DIR;
	
	foreach my $file (@file){
		if($file =~ /Summary.csv/){
			$summary_file = $file;
		}
		elsif($file =~ /Map.csv/){
			$map1_file = $file;
		}
		elsif($file =~ /Map2.csv/){
			$map2_file = $file;
		}
		elsif($file =~ /Defects.csv/){
			$defect_file = $file;
		}	
		elsif($file =~ /_Images$/i) {
			$images_directory = $file;				
			# Construct the full path to the subdirectory
			my $full_path = "$inDir/$images_directory";

			# Check if the subdirectory exists
			if (-d $full_path) {
				# Delete the subdirectory and all its contents
				remove_tree($full_path, {error => \my $err});
				# Check for errors
				if (@$err) {
					for my $diag (@$err) {
						my ($file, $message) = %$diag;
						if ($file) {
							WARN("Failed to delete $file: $message");
						}
						else {
							WARN("General error: $message");
						}
					}
				}
				else {
					INFO("Successfully deleted $full_path");
				}		
			}
			else {
				WARN("Subdirectory $full_path does not exist.");		
			}
		}
	}
	
	#INFO($summary_file);
	
	open (INFILE, "<",$inDir."/".$summary_file);
	while(<INFILE>)
	{
		chomp($_);
		$_ =~ s/\cM//g;

		if(/^Recipe,(.*)\\(.*)\\(.*).gr3/)
		{
			$header->REVISION(1);
			
			$header->PROGRAM($3);	
			#INFO($header->{PROGRAM});		
		}		
		elsif(/Date,(\d{2})\/(\d{2})\/(\d{4})/)
		{
			$date = "$3/$2/$1";
		}
		elsif(/^Lot Start Time,(\d{2}\:\d{2}\:\d{2})/)
		{
			$header->START_TIME($date." ". $1);			
		}
		elsif(/^Lot Completed Time,(\d{2}\:\d{2}\:\d{2})/)
		{			
			$header->END_TIME($date." ". $1);

			my $start_timelocal = gettimelocal($header->START_TIME);					
			my $end_timelocal = gettimelocal($header->END_TIME);
			
			if($start_timelocal > $end_timelocal){

				# increase the end date by 1 day when the end time is earlier than the start time
				$end_timelocal = $end_timelocal + 72000;
				$header->END_TIME($end_timelocal);

			}
			
		}
		elsif(/^Lot No,(\S+)/)
		{
			$header->LOT(uc($1));
			
			%binCount = ();
		}
		elsif(/^Machine ID,(\S+)/)
		{
			$header->EQUIP1_ID($1);
			$header->EQUIP2_ID("AutoVision");
		}
		elsif(/^Operator ID,(\S+)/)
		{
			$header->OPERATOR($1);
		}
		elsif(/^Device Name,(\S+)/)
		{
			$header->PRODUCT(uc($1));
		}
		elsif(/^Die Bonder ID,(\S+)/)
		{
			$header->EQUIP3_ID($1);						
		}
		elsif(/^Total Good Unit,(\d+)/)
		{
			$good_bin = $1;
			#INFO("good_bin=". $good_bin);
		}
		elsif(/^Wire Bonder ID,(\S+)/)
		{
			$header->EQUIP4_ID($1);						
		}		
	}
	
	close(INFILE);
	
	my $line_num = 0;
	my $ln_num = 0;
	my $waferNum = "";
	my $units = "";
	my $set_test = 0;
	my $title="";
	my $frame_idx = 0;
	my $partid_idx =1;
	my $x_idx =2;
	my $y_idx = 3;	
	my $x = "";
	my $y = "";
	my $x_pre1 = "";
	my $x_pre2 = "";
	my $partid = "";
	my $mag = "";
	my $waferName = "";
	my %data = ();
	my %soft_bin = ();
	my $auto_partid1 = 1;
	my $auto_partid2 = 1;
	
	my $bin_num = 2;
	###### BIN
	#defect_file
	open (INFILE, "<",$inDir."/".$defect_file);
	
	my $sbinNumber = 1002;
	my $VAsbinNumber = 2002;
	
	while(my $line = <INFILE>)
	{
		chomp($line);
		$line =~ s/\cM//g;		
			
		my @wk = split(',', $line);
		
		if ($wk[0] eq "Code")
		{
			next;
		}	
		if ($wk[1] =~ /Reject Criteria/i)
		{
			next;
		}
		
		#$bin{$wk[0]}{NUM} = $bin_num;
		$bin{$wk[0]}{DESC} = $wk[1];
		$bin{$wk[0]}{QTY} = $wk[2];
		$bin{$wk[0]}{YIELD} = $wk[3];
				
		if($line =~ /Total/)
		{
			$binCount{1} = $good_bin;
			#INFO("total");	
			$sbin{1001} = 
			{
				NAME  => "BIN_01",
				COUNT => $good_bin,
			};
						
			#INFO("total:".$good_bin);
		}
		elsif($wk[2] ne 0)
		{
			$binCount{$bin_num} = $wk[2];				
		}
		$bin_num++;				
		
		####################### sbin 
		
		if(length($wk[0])>0 && length($wk[1])>0 && length($wk[2])>0 && length($wk[3])>0 && length($wk[4])>0 && length($wk[5])>0 )
		{		
			$bin{$wk[0]}{NUM} = $sbinNumber;


			my $bin_name = rep_str("$wk[0]-$wk[1]");
			
			$sbin{$sbinNumber} =
				{
					NAME  => $bin_name ,
					COUNT => $wk[2],
				} ;
			
			$bin_name =	rep_str("assist-$wk[0]-$wk[1]");
				
			$sbin{$VAsbinNumber} =
				{
					NAME  => $bin_name ,
					COUNT => $wk[5],
				} ;
				$sbinNumber++;
				$VAsbinNumber++;
		}
		else
		{
			next;
		}
		
	}
	close(INFILE);
	
	###### SOFT_BIN
	#map1_file
 	open (INFILE, "<",$inDir."/".$map1_file);
 	
 	while(my $line = <INFILE>)
 	{
		$ln_num++;
		chomp($line);
		$line =~ s/\cM//g;
 		
 		my @wk = split(',', $_);
 		
 		if($line =~ /^MAG-(.*)$|^MAG(.*)/)
 		{
 			$mag = $line;	
 		}
 		elsif($line =~ /^Frame/)
 		{
 			#$title = $line;
			next;
 		}
		elsif($ln_num > 3 && $line =~ /^MAG-|^Frame|^MAG/)
		{
			next;
		}
 		else{
 			$waferName = $mag."_".$wk[$frame_idx];
 			$x = $wk[$x_idx];
 			$y = $wk[$y_idx];
 			 
 			#if($x_pre1 ne "" and 			
 			#   $x_pre1 > $x)
			if($x_pre1 ne "")
 			{
 				$auto_partid1++;
 			}
 			
 			$x_pre1 = $x;
 			
 			$partid = $auto_partid1;
 			
 			if($wk[4] eq "Fail" or $wk[4] eq "VA"){
 				$soft_bin{$waferName}{$partid}{$x}{$y} = $bin{trim($wk[5])}{"NUM"};
 				#INFO($bin{trim($wk[5])}{"NUM"}."/".$wk[5]);				
 			}
 			else{
 				$soft_bin{$waferName}{$partid}{$x}{$y} = 1001;
 			}
 		}
 		
 	}
 	close(INFILE);
	
	open (INFILE, "<",$inDir."/".$map2_file);
	
	while(my $line = <INFILE>)
	{
		$line_num++ ;
		chomp($line);
		$line =~ s/\cM//g;
		next if ($line =~ /^\d+ms\,/);
		my @wk = split(',', $line);
		
		if($line =~ /^MAG-(.*)$|^MAG(.*)/)
		{
			$mag = $line;
		}
		elsif($line =~ /^Frame/)
		{
			$title = $line;
		}

		if ($line_num eq 3)
		{
					
			my $idx =0;
			my $prefix_idx = 0;
			foreach my $value (@wk)
			{
				if($value !~ /ms/)
				{
					push @container_inx, $idx;
					$prefix{$idx} = $prefix_idx;					
				}
				elsif($value =~ /ms/){
					$prefix_idx = $idx;
				}
				
				
				$idx++;
			}			
		#print "@container_inx\n";	
			my @temp = split(',', $title);
			my $testNum = 1;
									
			foreach my $ci (@container_inx)
			{
				if(!(($temp[$ci] eq "Frame") or
					 ($temp[$ci] eq "Unit") or
					 ($temp[$ci] eq "Row") or
					 ($temp[$ci] eq "Col") or ($temp[$ci] eq "Blk")))
				{	
					my $prefix_num = $prefix{$ci};
					my $test = new_test;
					$test->number($testNum);
					$test->name( $temp[$prefix_num] ." - ".$temp[$ci]);
					if (length($test->name) > 63) {
						WARN("Test name \"".$test->{name}."\" will be truncated to 64 characters.");
						my $tmp_test = substr($test->name,0,63);
						$test->name($tmp_test);
					}
					$model->add('tests',$test);
					$testNum++;	
				}				
			}
		}
		elsif($line_num >= 3)
		{
			
			#last if($line =~ /^Frame/);
			next if ($line =~ /^Frame|^MAG-|^MAG/ || $line eq "");

			my @values = ();
			my $empty = 0;
			foreach my $ci (@container_inx)
			{
				#if($ci eq $frame_idx){
				if ($ci eq $frame_idx && $wk[$ci] !~ /MAG/i){
					$waferName = $mag."_".$wk[$ci];
				}elsif($ci eq $x_idx){
					$x = $wk[$ci];					
					
					#if($x_pre2 ne "" and 
					#   $x_pre2 > $x)
					if ($x_pre2 ne "")
					{
						$auto_partid2++;
					}
					
					$x_pre2 = $x;					#$auto_partid++;
					$partid = $auto_partid2;					
				}elsif($ci eq $y_idx){
					$y = $wk[$ci];
				}elsif($ci eq $partid_idx){
					#$partid = $wk[$ci]+1;
					

				}else{
				
					push @values, $wk[$ci];
					#if($wk[$ci] eq "")
					if ($line eq "")
					{
						$empty =1
					}
				}
			}
			
			if(! $empty)
			{
				@{$data{$waferName}{$partid}{$x}{$y}} = @values;
			}
		}
	
	}
	
		   
	my $wafer;	
	
	my $print_bin = 1;
	
	foreach my $wf (keys %data)
	{
		foreach my $pi (sort keys %{$data{$wf}})
		{
			foreach my $x (sort keys %{$data{$wf}{$pi}})
			{
				foreach my $y (sort keys %{$data{$wf}{$pi}{$x}})
				{
					my @wk = @{$data{$wf}{$pi}{$x}{$y}};
					foreach my $value(@wk)
					{						
						$wafer = $model->find('wafers',{name => $wf});
						unless (defined $wafer){
						   $wafer = new_wafer( { name => $wf } );
						   $model->add('wafers',$wafer);						 
						}
						# trap partid and xy coord
						if ($x eq "" || $y eq ""){
							my $errmsg = "No XY coordinates found.";
							my $errcod = 1;
							$model->misc->{err_msg} = $errmsg;
							$model->misc->{err_cod} = $errcod;
						}
						if ($pi eq "") {
							my $errmsg = "Part id not found.";
							my $errcod = 1;
							$model->misc->{err_msg} = $errmsg;
							$model->misc->{err_cod} = $errcod;
						}

						my $die = $wafer->find('dies',{partid=>$pi, x=>$x, y=>$y});		
					
						unless (defined $die){
						   $die = new_die( { partid => $pi, x=>$x, y=>$y } );
						   
						   my $bin_num = $soft_bin{$wf}{$pi}{$x}{$y};
						   
						   if($bin_num eq "")
						   {
							$bin_num = 1001;
						   }
						   $die->soft_bin($bin_num);						   

						   $wafer->add('dies',$die);
						}
					
						$die->add( 'result', repNA($value) );
					
					}
							
				}
			}
		}
				
	}
	
	close(INFILE);
	
	### add bin		
		
	unless($isLogDebug){
		foreach my $file (@file){
		unlink $inDir."/". $file ;
		}
	}
	
	
	return $model;
}

sub gettimelocal{
	my $starttime = shift;
	my $second ;
	my $minute ;
	my $hour ;
	my $day ;
	my $month; 
	my $year ;	
	
	if($starttime =~ /(\d{4})\/(\d{2})\/(\d{2}) (\d{2})\:(\d{2})\:(\d{2})/)
	{
		 $second = $6;
		 $minute = $5;
		 $hour = $4;
		 $day = $3;
		 $month = $2;
		 $year = $1;
	}
	
	return timelocal( $second, $minute, $hour, $day, $month - 1, $year );

}

sub rep_str{
my $str = shift;

	$str =~ s/^\s+|\s+$//g;
	$str = uc($str);
	$str =~ s/\s+/_/g;
	$str =~ s/_{2,}/_/g;
return $str;
}
1;

