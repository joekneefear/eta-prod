# SVN $Id: WAT.pm 960 2015-08-26 11:39:44Z dpower $
# CHANGES:
# 25-Jun-2015  RCyr    - Capture product from LOT TYPE; to be overwritten if lot is matched in reference table.
# 26-Jun-2015  GMiole  - Use fix-length parsing approach on site id due to space in between values and enhanced
#                        regex in capturing waferNum and site.
# 09-Jun-2015  Grace    - set product with "CUST PART NO" for EAGLE
# 10-Jun-2015  Grace    - Set the test name to be the concatenation of both lines of text in the column including the unit if any. Ex: "Schottky3_Leak_uA". for EAGLE
# 26-Aug-2015 Gilbert  - Uppercase the lot id.

package PDF::Parser::WAT;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";
my $testNum = 1;

my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

sub readFile {
    my $self   = shift;
    my $infile = shift;
	my $platform = shift;
    my $site = shift;
    my $header;
    if($site =~ /PWRCHIP/i) {
        $header = new_metadata;
    } else {
        $header = new_headerLong;
    }
    
    my $model  = new_model(
        {   header => $header,
            misc   => {},
            dataSource => 'HP'
        }
    );
    my $wafers = {};
    my $waferSites = {};
    my ($tUnits,$tHI,$tLO) = (0,0,0);
    open (INFILE, "<",$infile);
    while (<INFILE>) {
        if($site =~ /PWRCHIP/i) {
            if($_ =~ /TYPE NO :(.+)\s+PROCESS  :(.+)\s+PCM SPEC:(.+)\s+QTY:(.+)\s+pcs/i) {
            $header->ALTERNATE_PRODUCT(trim($1));
            $header->PROCESS(trim($2));
            #INFO("TEST=$header->{ALTERNATE_PRODUCT}||$header->{PROCESS}")
         
            }
            if($_ =~ /LOT ID  :(.+)\s+DATE\s+:(.+)\s+TIME:(.+)\s+Program NAME:(.+)/i) {
                $header->LOT(trim($1));
                my $d = trim($2)." ".trim($3).":00";
                $header->START_TIME(formatDate($d));
                $header->DATE_TIME_MASK("%Y/%m/%d %H:%M:%S");
                $header->RECIPE(trim($4));
                #INFO("TEST=$header->{LOT}||$header->{START_TIME}||$header->{RECIPE}");
            }
            if($_ =~ /VERSION :(.+)\s+TESTER TYPE:(.+)\s+TESTER ID:(.+)\s+PRODUCT ID:(.+)/i) {
                $header->RECIPE_REVISION(trim($1));
                $header->TESTER_TYPE(trim($2));
                $header->MEASURING_EQUIPMENT(trim($3));
                my ($product,$suffix) = split('-', trim($4));
                $header->PRODUCT(trim($product));
                #INFO("TEST=$header->{RECIPE_REVISION}||$header->{TESTER_TYPE}||$header->{MEASURING_EQUIPMENT}||$header->{PRODUCT}");
            }
            if($_ =~ /OPERATOR:(.+)\s+TEST NAME:(.+)\s+TEST COUNT:(.+)\s+SPEC LIMITS:(.+)/i) {
                $header->OPERATOR(trim($1));
                #INFO("TEST=$header->{OPERATOR}");
            }

        } else {
            if (/^ LOT ID\s+:(\S+)/) {
            $header->LOT(uc($1));
            }
            if (/^ TYPE NO\s+:(\S+)/) {
                $header->PRODUCT($1);
            }
            if (/PCM SPEC:(\S+)/) {
                $header->REVISION(1);
                $header->PROGRAM($1);
            }
            if (/ DATE     :(\d{2}\/\d{2}\/\d{4})/) {
                $header->START_TIME( $1 . " 00:00:00" );
                $header->END_TIME( $1 . " 00:00:00" );
            }
            
            if(/CUST PART NO:(.+)/){
            
                if($platform eq "EAGLE"){
                    $header->PRODUCT($1);
                }			
            }
        }
        
	#########################################################################################
        # USE FIX-LENGTH PARSING APPROACH ON WAFER ID AND SITE ID DUE TO SPACES IN BETWEEN VALUES
        #########################################################################################
    if (/WAF\s+SITE \s+(.*)$/) {
        foreach ( split( /\s+/, $1 ) ) {
            my $test = new_test;
            $test->number($testNum);
            $test->name( repNA($_) );
            $model->add('tests',$test);
            $testNum++;
        }
    }
	if (/ID\s+ID/i) {
                my $start    = 13;
                my $interval = 12;
              for (my $i=1; $i<=10; $i++) {
		       chomp($_);
		         $_ =~ s/\015//;
                    my $val = substr($_, $start, $interval);
                       $val =~ s/^\s*|\s*$//g;
				       $val =~ s/\s+/\_/g;
                       next unless $val ne "";
                       $start += $interval;
                       $model->tests->[$tUnits]->units($val);					 
				
				# EAGLE
				if($platform eq "EAGLE"){
					$model->tests->[$tUnits]->name($model->tests->[$tUnits]->name."_". $model->tests->[$tUnits]->units);
					$model->tests->[$tUnits]->units("");									
				}
				else{				
					# special case if test name wraps to second line.
					if($model->tests->[$tUnits]->units =~ /\s/ ){
					
						my @tmp = split /\s/, $model->tests->[$tUnits]->units;
						$model->tests->[$tUnits]->name($model->tests->[$tUnits]->name." ".$tmp[0]);
						$model->tests->[$tUnits]->units($tmp[1]);
									
					}
				}
				
                $tUnits++;
               }
        }
        if ($_ =~ /^ SPEC HI\s+(.*)$/) {
            foreach my $item ( split( /\s+/, $1 ) ) {
                $item = repNA(trim($item));
                $model->tests->[$tHI]->HSL($item);
                $tHI++;
            }
        }
        if (/^ SPEC LO\s+(.*)$/) {
            foreach ( split( /\s+/, $1 ) ) {
                $model->tests->[$tLO]->LSL($_);
                $tLO++;
            }
        }
        if (/^\s{1,2}(\d{1,2})\s+\-(\d+)\s+(.*)$/) {
            my $waferNum = $1;
            my $site     = $2;
            my $wafer = $model->find('wafers',{number => $waferNum});
            unless (defined $wafer){
               $wafer = new_wafer( { number => $waferNum } );
               $model->add('wafers',$wafer);
            }
            my $die = $wafer->find('dies',{site=>$site});
            unless (defined $die){
               $die = new_die( { site => $site } );
               $wafer->add('dies',$die);
            }

            foreach ( split( /\s+/, $3 ) ) {
                $die->add( 'result', repNA($_) );
            }
        }

    }
    return $model;
}
1;

