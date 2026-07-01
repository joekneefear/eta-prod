# 4-April-2016 Eric	: Initial release
#
package PDF::Parser::Tesec_Ksm;
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
	my $self = shift;
	my $infile = shift;
	my $line = "";
	my $line_flag = 0;
	my $lotid = "";
	my %hbin = ();
	my %sbin = ();
	my $tp_name       = "";
	my $tp_rev        = 1;
	my $td_filename   = "";
	my $tp_filename   = "";
	my $wafer_id      = "";
	my $device_id     = "";
	my $user_id       = "";
	my $eqpt_id       = "";
	my $starttime= ""; 
	my $endtime  = "";
	my $wafer = new_wafer;
	my $header = new_headerLong;
	my $model = new_model ( 
		{
			header => $header,
			wafer => $wafer,
            		misc   => {},
            		dataSource => 'TESEC'
		}
	);

	open FH, $infile or die "can't open $infile\n";
	while($line=<FH>)
	{
		chomp($line);
	   	$line =~ s/\cM//g;
		
		$line_flag = 1 if $line =~ /^S#/; 
		
	   	if ($line =~ /^LOT ID.{3}(.+)NODE.{5}(.+)/i)
		{
			$lotid 	 = uc($1);
			$lotid	 = &remove_unwanted_chars($lotid);
			$header->LOT($lotid);
			$eqpt_id = uc($2);
			$eqpt_id = &remove_unwanted_chars($eqpt_id);
			$header->EQUIP1_ID($eqpt_id);
			
		}
		elsif ($line =~ /^DEVICE.{3}(.+)USER ID.{2}(.+)/i)
		{
			$device_id = uc($1);
			$device_id = &remove_unwanted_chars($device_id);
			$user_id   = uc($2);
			$user_id   = &remove_unwanted_chars($user_id); 
			$header->OPERATOR($user_id);
		}
		elsif ($line =~	/START/i)
		{
			my @dummy = split /[\s:\/]+/, $line;
			my ($dump, $dump, $yr, $mon, $day, $hh, $nn) = @dummy;
			$starttime = $yr."/".$mon."/".$day." ".$hh.":".$nn.":"."00";		
			$header->START_TIME($starttime);	
		}
		elsif ($line =~ /END/i)
		{
			my @dummy = split /[\s:\/]+/, $line;
                        my ($dump, $dump, $yr, $mon, $day, $hh, $nn) = @dummy;
			$endtime = $yr."/".$mon."/".$day." ".$hh.":".$nn.":"."00";
			$header->END_TIME($endtime);
		} 	
		elsif ($line =~ /^FILENAME.{2}(.+)WF#.{6}(\w*)/i)
		{
			$tp_name  = uc($1);
			$tp_name  = &remove_unwanted_chars($tp_name);
			$header->PROGRAM($tp_name);
			$wafer_id = uc($2);
			$wafer = $model->find('wafers',{number => $wafer_id});
		        unless (defined $wafer){
        		       $wafer = new_wafer( { number => $wafer_id } );
        		       $model->add('wafers',$wafer);
        		}
			
		}
		elsif ($line =~ /^S\d+/ && $line_flag == 1)
		{
			$line =~ /^S(\d+)\s+(\d+)\s+(\w+.*)\s+(\d+)\s+\d+.\d+\s+\d+\s+\d+.\d+/;
			my $sbin_num	= $1;
			my $hbin_num	= $2;
			my $name 	= uc($3);
			   $name	= &remove_unwanted_chars($name);
			my $cnt 	= $4;
			
			$hbin{$hbin_num}{CNT} += $cnt;
			$hbin{$hbin_num}{NAME} = $name;

			$sbin{$sbin_num} =
			{
				NAME => $name,
				CNT => $cnt,
			};
		}
	}
	close(FH);

	foreach my $no (sort {$a<=>$b} keys %sbin){
		my $bin  = new_bin;
		$bin->number($no);
		$bin->name($sbin{$no}{NAME});
		$bin->count($sbin{$no}{CNT});
		$bin->PF($sbin{$no}{NAME} =~ /PASS|GOOD/i ? 'P' : 'F');
		$wafer->add('sbins', $bin);
	}
	
	foreach my $no (sort {$a<=>$b} keys %hbin){
                my $bin  = new_bin;
                $bin->number($no);
                $bin->name($hbin{$no}{NAME});
                $bin->count($hbin{$no}{CNT});
                $bin->PF($no eq 1 ? 'P' : 'F');
                $wafer->add('hbins', $bin);
        }

	return $model;
}

sub clean_string
{
        my $str = shift;
           $str =~ s/^\s+|\s+$//g;
           #$str = &EDBUtil::cleanString($str);  
	   $str =~ s/\,//g;	
           $str =~ s/\s+/_/g;
        return($str);
}

sub remove_unwanted_chars
{
        my $value = shift;

        $value =~ s/[^a-zA-Z0-9\-\_\.]/\-/gi;
        $value =~ s/\-{2,}/\-/g;
        $value =~ s/^\-+|\-+$//g;             ### REMOVE LEADING/TRAILING "-"

        return($value);
}
1;

