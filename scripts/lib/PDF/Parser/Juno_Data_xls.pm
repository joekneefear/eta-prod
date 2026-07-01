# 11-Nov-2015 Eric	: Initial release
# 01-Dec-2015 Eric	: Bin 5 is the passing bin
#
package PDF::Parser::Juno_Data_xls;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use PDF::ExcelReader;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;


our $VERSION = "1.0";
our $mat_type = "";

my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

my %hosb = ();
my %hohb = ();

sub readFile {
	my $self   = shift;
	my $infile = shift;
	my $dataflag = 0;	
	my $header = new_headerLong;
	my $model = new_model ( 
		{
			header => $header,
            		misc   => {},
            		dataSource => 'JUNO'
		}
	);

	my $wafer = $model->find('wafers',{number => 0});
	unless (defined $wafer){
		$wafer = new_wafer( { number => 0 } );
		$model->add('wafers',$wafer);
	}

	# Get lotid from filename
	chomp($infile);
	my $fn = basename($infile);
	   $fn =~ s/^\s+|\s+$//g;
	my ($device, $lot, $source_lot, $tester_no,) = split /\_/, $fn;
	my ($lotid,$sublotid) = split /\-/, $lot;
	   INFO ("Lot in filename = $lotid");
	   $header->LOT(trim($lotid));	
	   $header->EQUIP1_ID(trim($tester_no));

	my @arrysheetnames = ();
	my $xls = PDF::ExcelReader->new($infile);
	   $xls->getworksheets(\@arrysheetnames);
	my $maxcol = $xls->maxcolumncount($arrysheetnames[1]);
	my $maxrow = $xls->maxrows($arrysheetnames[1]) + 1;
	
	my @testname = ();
	my @hilim = ();
	my @lolim = ();
	my @bias = ();
	my @readings =();

 	for (my $row=1; $row<=$maxrow; $row++)
        {
                my @dummy = ();
                for(my $col=0; $col<=$maxcol; $col++)
                {
                        my $l1          = ($col > 25) ? int($col/26) - 1 : "";  ### 1ST LETTER
                        my $l2          = $col % 26;                            ### 2ND LETTER
                        my $colchar     = ($l1 eq "") ? chr($l2 + 65) : chr($l1 + 65) . chr($l2 + 65);
                        my $cellval     = $xls->readfromcell($arrysheetnames[1], $colchar . $row);

                        if ($cellval ne "undef" || $cellval ne "")
                        {
                           $dummy[$col] = &clean_string($cellval);
                        }

                }	 		
		if ($dummy[0] =~ /^\d{1,}$/ && $dataflag == 1) {
			my $site = shift(@dummy);
			my $bin = shift(@dummy);
			   $bin =~ s/\D//;  
			my $die = $wafer->find('dies',{site=>$site});
			unless (defined $die){
                        	$die = new_die( { site => $site } );
                                $die->partid( $site );
                                $die->x( "0" );
                                $die->y( "0" );
                                $wafer->add('dies',$die);
                        }
			
			my $phbin = $wafer->find('bins',{number=>$bin});
			unless (defined $phbin){
                                my $phbin = new_bin;
                                $phbin->number($bin);
                                $phbin->name("BIN_".$bin);
                                if ($hohb{$bin} ne "N/A"){
					$phbin->name("BIN_".$bin);
                                };

                                if ($bin eq "5"){
                                        $phbin->PF("P");
                                }
                                else{
                                        $phbin->PF("F");
                                }
                                $wafer->add('bins',$phbin);
                        }

			$die->hard_bin($bin);
                        $die->soft_bin($bin);			

			for (my $i=0; $i <= $#dummy; $i++) {
				$dummy[$i] =~ s/Over|undef//i; 
				$die->add( 'result', repNA($dummy[$i]) )
			}
		}
		elsif ($dummy[0] =~ /TestFileName/i && $dummy[2] ne ""){
			my ($tp_name, $dump) = split /\./, uc($dummy[2]);
			$tp_name         =~ /V(\d{1,})$/i;
			my $loc_tp_rev = $1;
			if ($loc_tp_rev =~ /^\d{1,}$/)
			{
		        	my $tp_rev  = $loc_tp_rev;
				$tp_name =~ s/V${tp_rev}//;
				$header->PROGRAM($tp_name);
				$header->REVISION($tp_rev);
				INFO ("Program = $tp_name Revision=$tp_rev");
			}	
			
		} 	
		elsif ($dummy[0] =~ /Item\s+Name|Item\_Name/i){
			@testname = splice(@dummy,2);
		}
		elsif ($dummy[0] =~ /Bias[123]/i){
			my @dummy = splice(@dummy,2);
			for (my $i=0; $i <= $#dummy; $i++) {
				if ($dummy[$i] =~ /Value/i)
				{
					$dummy[$i] =~ /(\d+)$/i;	
					$dummy[$i] = $dummy[$1 - 1];	
				}

				if ($dummy[$i] =~ /^M\d{1,}/)
				{
					$dummy[$i] =~ /(\d+)$/i;
                                	$dummy[$i] = $dummy[$1 - 1];
				}	

				if ($bias[$i] eq "" && $dummy[$i] ne "")
				{
					$bias[$i] = $dummy[$i];
				}
				elsif ($bias[$i] ne "" && $dummy[$i] ne "")
				{
					$bias[$i] .= "\_$dummy[$i]";
				}
			}
		}
		elsif ($dummy[0] =~ /Min\_Limit/i){
			@lolim = splice(@dummy,2);
		}
		elsif ($dummy[0] =~ /Max\_Limit/i) {
			@hilim = splice(@dummy,2);
			my $flag = 0;
			my $lastname = "";
			my $lastval = "";
			for (my $i=0; $i <= $#testname; $i++){
				my $test = new_test;
				my $orig_unit = "";
				my ($tnumber, $tname) = split /\_/, $testname[$i];	
				$flag    = 1        if $tname =~ /SAME/i;
				$flag    = 0        if $tname !~ /SAME/i;
			  	$tname    = $lastval if $flag == 1;	
				$lastval = $tname;
				
				if ($lolim[$i] eq ""){
					$lolim[$i] = -1e20;
					$orig_unit = "";
				}
				else {
					$lolim[$i] =~ /([a-z]{1,})$/i;
					$orig_unit = $1;
					$lolim[$i] =~ s/\s*$orig_unit//gi;
				}	
				my ($lolim, $lo_unit) = &convert_to_base_unit($lolim[$i], $orig_unit);

				if ($hilim[$i] eq "")
				{
					$hilim[$i] = 1e20;
					$orig_unit = "";
				} else {
					$hilim[$i] =~ /([a-z]{1,})$/i;
					$orig_unit = $1;
					$hilim[$i] =~ s/\s*$orig_unit//gi;
				}
				my ($hilim, $hi_unit) = &convert_to_base_unit($hilim[$i], $orig_unit);

				# reverse limit if test eq "SAME"
				if ( $hilim[$i] < $lolim[$i] ) {
					($hilim[$i] , $lolim[$i]) = ($lolim[$i], $hilim[$i]); 
				}
				if ($tnumber =~ /\d/i && $tname ne "") {
					$test->number($tnumber);
					$test->name($tname."_".$bias[$i]);
					$test->units(($lo_unit eq "") ? $hi_unit : $lo_unit);
					$test->LSL($lolim);
					$test->HSL($hilim);
					$model->add( 'tests', $test );
				}
			}
		}
		elsif ($dummy[0] =~ /Serial/i && $dummy[1] =~ /Bin/i) {
			$dataflag = 1;
		}
		
	}
	return $model;
}

sub convert_to_base_unit
{
        my $value      = shift;
        my $unit       = shift;
        my $multiplier = 1;

        #print "orig: unit=$unit, value=$value\n";
        if ($unit =~ /^a/)
        {
                $unit       =~ s/^a//;
                $multiplier = 1e-18;
        }
        elsif ($unit =~ /^f/)
        {
                $unit       =~ s/^f//;
                $multiplier = 1e-15;
        }
        elsif ($unit =~ /^p/)
        {
                $unit       =~ s/^p//;
                $multiplier = 1e-12;
        }
        elsif ($unit =~ /^n/)
        {
                $unit       =~ s/^n//;
                $multiplier = 1e-9;
        }
        elsif ($unit =~ /^u/)
        {
                $unit       =~ s/^u//;
                $multiplier = 1e-6;
        }
        elsif ($unit =~ /^m/)
        {
                $unit       =~ s/^m//;
                $multiplier = 1e-3;
        }
        elsif ($unit =~ /^K/)
        {
                $unit       =~ s/^K//;
                $multiplier = 1e3;
        }
        elsif ($unit =~ /^M/)
        {
                $unit       =~ s/^M//;
                $multiplier = 1e6;
        }
        elsif ($unit =~ /^G/)
        {
                $unit       =~ s/^G//;
                $multiplier = 1e9;
        }
        elsif ($unit =~ /^T/)
        {
                $unit       =~ s/^T//;
                $multiplier = 1e12;
        }
	 elsif ($unit =~ /^P/)
        {
                $unit       =~ s/^P//;
                $multiplier = 1e15;
        }

        $value *= $multiplier;
        #print "new: unit=$unit , value=$value , mul=$multiplier\n";
        return($value, uc($unit));
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
1;

