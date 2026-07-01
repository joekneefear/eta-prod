# SVN $Id: HP_JAZZ_ET.pm 2097 2017-04-06 01:25:11Z dpower $
# 2015-Aug-26 Gilbert 	- Uppercase lot id
# 2017-Apr-06 Eric	- populate source lot and assign as wafer name
#
package PDF::Parser::HP_JAZZ_ET;
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
    	my $model  = new_model(
        {   header => $header,
            misc   => {},
            dataSource => 'HP'
        });
    	my $wafers = {};
    	my $waferSites = {};
    	my ($tUnits,$tHI,$tLO) = (0,0,0);
    	my $starttime = "";
    	open (INFILE, "<",$infile);
    	while (<INFILE>) {
        	if (/LotID=(\S+?),/) {
            		my $lotid = $1;
            		$lotid =~ s/\.//;
            		$header->LOT(uc($lotid));
			$header->populateSrcLot;
        	}
		if (/PartID=(\S+?),/) {
            		my $partid = $1;
            		$partid =~ s/\.//;
            		$header->PRODUCT($partid);
        	}
        	if (/TestProgramName=(\S+?),/) {
            		$header->PROGRAM($1);
        	}
        	if (/TesterId=(\S+?),/) {
            		$header->EQUIP1_ID($1);
        	}
        	if (/Date=(\d{2}\/\d{2}\/\d{4}),/) {
            		$starttime = $1;
        	}
        	if (/Time=(\d{2}:\d{2}:\d{2}),/) {
            		$header->START_TIME( $starttime . " $1");
            		$header->END_TIME( $starttime . " $1");
        	}
		
		my $i= 1;
        	if (/^TestName,,(.*),/) {
            		foreach ( split( /,/, $1 ) ) {
                		my $test = new_test;
                		$test->number($i);
                		$test->name( repNA($_) );
                		$model->add('tests',$test);
				$i++;
            		}
        	}
        	if (/^Wafer#,Die#,(.*),/) {
            		foreach ( split( /,/, $1 ) ) {
                		$model->tests->[$tUnits]->units($_);
                		$tUnits++;
            		}
        	}
        	if (/^UpperLimit,,(.*),/) {
            		foreach ( split( /,/, $1 ) ) {
                		$model->tests->[$tHI]->HSL($_);
                		$tHI++;
            		}
        	}
        	if (/^LowerLimit,,(.*),/) {
            		foreach ( split( /,/, $1 ) ) {
                		$model->tests->[$tLO]->LSL($_);
                		$tLO++;
         		}
        	}
        	if (/^(\d{1,2}),(\d+?),(.*)/) {
            		my $waferNum = $1;
            		my $site     = $2;
            		my $wafer = $model->find('wafers',{number => $waferNum});
            		unless (defined $wafer){
               			$wafer = new_wafer( { number => $waferNum } );
				if ($header->SOURCE_LOT ne "") {
					$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
				}
               			$model->add('wafers',$wafer);
            		}
            		my $die = $wafer->find('dies',{site=>$site});
            		unless (defined $die){
               			$die = new_die( { site => $site } );
               			$wafer->add('dies',$die);
            		}
				
            		foreach ( split( /,/, $3 ) ) {            
                		$die->add( 'result', $_ );
            		}
        	}

    	}
    	$header->REVISION("NA");
    	return $model;
}
1;

