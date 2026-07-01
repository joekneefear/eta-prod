# 2015-Jun-23 	jgarcia	modified to generate limit file using static limit values.
# 2015-Aug-26   gmiole  uppercase the lot id
#
package PDF::Parser::AMS_BKET;
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
    my $header = new_headerLong;
	my $wmap   = new_wmap;
    my $model  = new_model(
        {   header => $header,
            misc   => {},
			wmap => $wmap,
            dataSource => 'AMS'
        }
    );
	my $starttime = undef;
	my $title = undef;
	
    my $wafers = {};
    my $waferSites = {};
    my ($tUnits,$x,$y,$un) = (0,0,0,0);
    ### below are the limits used for the static program EEAMS01 rev 1 ###
    ### like EWB loading all bket_ams data files will be using this program with the limits below until ###
    ### there is no request for a change from the engineers ###
    
    my @lowSpecLimit = qw /0 0 0 89.40000153 1 1 49/;
    my @highSpecLimit = qw /3 5 10 89.59999847 6 8 53/;
    my @lowCensorLimit = qw /0 0 0 50 0 0 25/;
    my @highCensorLimit = qw /5 10 10 100 15 15 80/;
    my $arrayCounter = 0;

		$header->PROGRAM("EEAMS01");
    $header->REVISION("1");
    $header->OPERATOR("EPI");
		$header->PRODUCT("SUPREMOS");
		$header->EQUIP1_ID("AMS AMS");
	
	open (INFILE, "<",$infile);
    while (<INFILE>) {
	
		s/\n//;
	    my @wk = split(/,/);
		
		if (/LotID/)
		{
			$title = $_;			
			#print "INDEX:>>$#wk<<\n"; 
			for(my $i =6; $i<=$#wk; $i++)
			{
				my $parameter = "";
				my $unit = "";
				  
				if($wk[$i] =~ /\[(.*)\s+\[(.*)\]\]/)
				{	
					$parameter = $1;
					$unit = $2;
					  
				}
				elsif($wk[$i] =~ /\[(.*)\]/)
				{
					$parameter = $1;
				}
				else
				{
					$parameter = $wk[$i];
				}	    
				$tUnits++;					
				my $test = new_test;
				$test->number( $tUnits );
				$test->name( repNA($parameter) );
				$test->units( repNA( $unit ) );
				
				$test->HSL( repNA($highSpecLimit[$arrayCounter]));
				$test->LSL( repNA($lowSpecLimit[$arrayCounter]));
				$test->HPL( repNA(""));
				$test->LPL( repNA(""));
				$test->HOL( repNA($highCensorLimit[$arrayCounter]));
				$test->LOL( repNA($lowCensorLimit[$arrayCounter]));
				$test->LWL( repNA(""));
				$test->HWL( repNA(""));
				$test->group( repNA( "" ) );
				$model->add( 'tests', $test );	
				$arrayCounter++;
	
			}
			if($infile =~ /(\S+)_(\d{4})(\d{2})(\d{2})(\d{6})_(\d{2})(\d{2})(\d{2})/)
			{				
				$starttime = $3."/".$4."/".$2." $6:$7:$8";
			}
			
		}   
		elsif($wk[0] =~ /(\d+)_(\S+)/)
		{
			$header->LOT(uc($2));
			
			my $waferNum = $wk[1];
            my $site     = $wk[2];
			my $x		 = int($wk[3]);
			my $y		 = int($wk[4]);
            my $wafer = $model->find('wafers',{number => $waferNum});
            unless (defined $wafer){
               $wafer = new_wafer( { number => $waferNum } );
               $model->add('wafers',$wafer);
            }

            my $die = $wafer->find('dies',{site=>$site});
			
            unless (defined $die){
             
               $die = new_die;
			   $die->site($site);
			   $die->x( $x );
               $die->y( $y );
               $wafer->add('dies',$die);
			   
				for(my $i =6; $i<=$#wk; $i++)
				{			
					$die->add( 'result', $wk[$i]);
				}
            }     

			unless ( defined $wafer->START_TIME ) {
                $wafer->START_TIME($starttime);
				$wafer->END_TIME($starttime);
            }			
			
			

		}
    }
    return $model;
}
1;


