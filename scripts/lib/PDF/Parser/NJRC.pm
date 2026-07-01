#
# 2015-Aug-26 Gilbert - Uppercase the lot id.
#
package PDF::Parser::NJRC;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

sub readFile {
    my $self   = shift;
    my $infile = shift;
	my $device_cfg = shift; 
    my $header = new_headerLong;
	my $wmap   = new_wmap;
    my $model  = new_model(
        {   header => $header,
            misc   => {},
			wmap => $wmap,
            dataSource => 'NJRC'
        }
    );
	my $starttime = undef;
	my $title = undef;
	my $lot = undef;
	
    my $wafers = {};
    my $waferSites = {};
    my ($tUnits,$x,$y,$un) = (0,0,0,0);
	my @data = ();
	my @title = ();
	my $wafer = "";
	my $filename = basename($infile);
	my %hdevice = ();
	my $program = undef;
	
	
	##  read device config
	open (RH, "<", $device_cfg);
	while (<RH>) {		
		my $line = $_;
		chop $line;
		my @wk = split(',', $line);		
		$hdevice{trim($wk[0])} = trim($wk[1]);
	}
		
	open (INFILE, "<",$infile);

	
	if($filename =~ /(.*)_(.*).TXT/)    #### njrc_jp_et_bp
	{
		my $line = <INFILE>;
		
		$lot = $1;
	
		my @wk = split(/\015/, $line);
		
		foreach $line (@wk)
		{		
			$line =~ s/\"//g;
			
			my @cols = split(/,/, $line);
			
			if($line =~ /^DATE/)
			{
				for(my $i=12; $i<=$#cols; $i++)
				{
					my $parameter = "";
					my $unit = "";
					if($cols[$i] =~ /(.*)\((.*)\)/)
					{	
						$parameter = $1;
						$unit = $2;
						  
					}
					#elsif($cols[$i] =~ /(.*)\((.*)/)
					#{
					#	$parameter = $1;
					#	$unit = $2;
					#}
					elsif($cols[$i] =~ /(.*)/)
					{
						$parameter = $cols[$i];
					}	         
					
					my $test = new_test;
					$test->number( "" );
					$test->name( repNA($parameter) );
					$test->units( repNA( $unit ) );
					
					$test->HSL( repNA(""));
					$test->LSL( repNA(""));
					$test->HPL( repNA(""));
					$test->LPL( repNA(""));
					$test->HOL( repNA(""));
					$test->LOL( repNA(""));
					$test->LWL( repNA(""));
					$test->HWL( repNA(""));
					
					$test->group( repNA( "" ) );
					$model->add( 'tests', $test );	

					$tUnits++;		
				}
			}
			else{
				
				$header->REVISION("3");
				
				$header->EQUIP2_ID($cols[5]);
				
				if($hdevice{$cols[6]} eq "12V"){
					$program = "NJRC12V";
				}
				elsif($hdevice{$cols[6]} eq "40V"){
					$program = "NJRC40V";
				}
				
				$header->PROGRAM($program);
				
				$header->INDEX1($cols[6]);
				
				$header->INDEX2($cols[7]);
				
				$header->LOT(uc($lot));
				
				if($cols[0] =~ /(\d{2})(\d{2})(\d{2})/)
				{
					$starttime = "20".$1."/".$2."/".$3." 00:00:00";					
				}
				
				my $waferNum = $cols[2];
				my $site     = $cols[3];
			
				my $wafer = $model->find('wafers',{number => $waferNum});
				
				unless (defined $wafer){
					$wafer = new_wafer( { number => $waferNum } );
					$model->add('wafers',$wafer);
				}
				
				my $die = $wafer->find('dies',{site=>$site});
				
				unless (defined $die){
				 
					$die = new_die;
					$die->site($site);
					#$die->x( $x );
					#$die->y( $y );
					$wafer->add('dies',$die);
				   
					for(my $i=12; $i<=$#cols; $i++)
					{
								
						$die->add( 'result', $cols[$i]);
					}
						 
				}
				
				unless ( defined $wafer->START_TIME ) {
				
					$wafer->START_TIME($starttime);
					$wafer->END_TIME($starttime);
				}			
				
			}
		}
	}
	elsif($filename =~ /(.*).TXT/ or $filename =~ /(.*).txt/)
	{
		my @line = <INFILE>;
		
		INFO($infile);
		
		$lot = $1;
		
		$header->LOT(uc($lot));
		
		my $row = $#line+1;
		my @wk = split(/\t/, $line[0]);
		my $col = "";
		
		INFO($row.",".$col);
		
		#### parameter		
	
		my $idx = 0;
		
		for (my $i=0;$i<=$#line; $i++)
		{
			$idx++;
			$line[$i] =~ s/\n//;
			my @wk = split(/\t/, $line[$i]);
			
			unless($wk[0] =~ /Lot #/)
			{
				@{$data[$idx]} = @wk[1..$#wk];
				
			}	
			else{
				@title = @wk[1..$#wk];	
				$col = $#title+1;
			}

		}
		
		for (my $c = 0; $c <= $col; $c++)
		{
			for (my $r = 2; $r <= $row; $r++)
			{
				#if($c eq 1)
				if($title[$c] eq "Device")
				{
					$header->INDEX1($data[$r][$c]);
				}
				elsif($title[$c] eq "Item")
				{	
					
					my $parameter = $data[$r][$c];
					my $unit = "";
					my $para_num = $data[$r][$c-1];
					
					my $test = new_test;
					$test->number( repNA($para_num) );
					$test->name( repNA($parameter) );
					$test->units( repNA( $unit ) );
					
					$test->HSL( repNA(""));
					$test->LSL( repNA(""));
					$test->HPL( repNA(""));
					$test->LPL( repNA(""));
					$test->HOL( repNA(""));
					$test->LOL( repNA(""));
					$test->LWL( repNA(""));
					$test->HWL( repNA(""));
					
					$test->group( repNA( "" ) );
					$model->add( 'tests', $test );	
				}
				elsif($title[$c] eq "Wafer #")
				{					
					my $waferNum = $data[$r][$c];
					$wafer = $model->find('wafers',{number => $waferNum});
					unless (defined $wafer){
						$wafer = new_wafer( { number => $waferNum } );
						$model->add('wafers',$wafer);
						INFO($waferNum."r: $r, c : $c");
					}
				}
				elsif($title[$c] =~ /Site (\d)/)
				{
					my $site = $1;
					
					my $die = $wafer->find('dies',{site=>$site});
				
					unless (defined $die){
					 
						$die = new_die;
						$die->site($site);
						#$die->x( $x );
						#$die->y( $y );
						$wafer->add('dies',$die);
						
					   }
						$die->add( 'result', $data[$r][$c]);
					}							
			}
		}
		
		
	}
    return $model;
}



sub readLimitFile {
    my $self   = shift;
    my $infile = shift;
	my $program_short = shift;
	my $program = shift;
	my $revision = shift;
	
	my @ary_title = qw/TESTPLAN_NAME TESTPLAN_REV TEST_NUM TEST_TYPE TEST_NAME HI_LIM LO_LIM TEST_TXT UNITS /;
	
	my %hash_title;
	
    my $limit = new_limit;
    #$limit->conditionNames([qw/testCond PIN/]);
    my $num = 0;
	INFO("program_short:".$program_short. ",". $program.",".$revision);
    open( INFILE, $infile );
    while (<INFILE>) {
        s/[\r\n]+\z//;
        $num++;		

		if($_ =~ /^# (.+)/){
			
			my @wk = split(',', $1);			
			my $i = 0;			
			foreach my $title (@wk){	
			
				$title = trim($title);
				for(my $j=0; $j<=$#ary_title; $j++){

					if($ary_title[$j] eq $title){
					
						$hash_title{$title} = $i;						
					}					
				}
				
				$i++;				
			}			
		}
		elsif( $_ =~ /#####/){
			
		}
		else{
			
			my @wk = split(',', $_);
			
			if($wk[$hash_title{"TESTPLAN_NAME"}] eq  $program_short and $wk[$hash_title{"TESTPLAN_REV"}] eq $revision)
			{
				$limit->REVISION($revision);
				$limit->PROGRAM($program);
				
				my $test = new_test;
				$test->number($wk[$hash_title{"TEST_NUM"}]);
				my $parameter = $wk[$hash_title{"TEST_NAME"}];
				my $unit = "";
				#INFO("	$parameter");
				if($parameter =~ /(.*)\((.*)\)/){	
					$parameter = $1;
				}
				#elsif($parameter =~ /(.*)\((.*)/){
				#	$parameter = $1;
				#}
				elsif($parameter =~ /(.*)/){
					$parameter = $1;
				}	         
					
				$test->name($parameter);
				$test->LSL($wk[$hash_title{"LO_LIM"}]);
				$test->HSL($wk[$hash_title{"HI_LIM"}]);
				$test->units($wk[$hash_title{"UNITS"}]);
				$limit->add('tests',$test);
				
				INFO("parser : ".$test->name. ",".$test->number.",".$test->units);
			}
		}
    }  
   return $limit;
}


1;


