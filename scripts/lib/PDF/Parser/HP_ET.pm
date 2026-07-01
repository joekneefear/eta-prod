# SVN $Id: HP_ET.pm 2232 2017-09-04 02:23:31Z dpower $
# CHANGES:
# 25-Jun-2015  RCyr    	- Capture product from LOT TYPE; to be overwritten if lot is matched in reference table.
# 26-Jun-2015  GMiole  	- Use fix-length parsing approach on site id due to space in between values and enhanced
#                         regex in capturing waferNum and site.
# 09-Jun-2015  Grace    - set product with "CUST PART NO" for EAGLE
# 10-Jun-2015  Grace    - Set the test name to be the concatenation of both lines of text in the column including 
# 			  the unit if any. Ex: "Schottky3_Leak_uA". for EAGLE
# 26-Aug-2015  Gilbert  - Uppercase lot id
# 29-Aug-2015  RCyr     - Use fixed length to get test names from TSMC ET and Vanguard ET as some may contain spaces.
# 15-Jul-2016  Eric	- Don't append unit to testnames if site = Vanguard ET and lot starts with "F"
# 22-Jul-2016  Eric	- Don't truncate testnames if site = Vanguard ET and lot starts with "F"
# 22-Jul-2016  Eric	- Don't truncate testnames if site = Vanguard ET and lot starts with "F"
# 31-Mar-2017  Eric	- remove trailing spaces for lot, product and program
# 			- look for source lot in pplot and assign as wafer name if available
# 26-May-2017  Eric	- removed conditions on how to capture testnames and unit for Vanguard
# 22-Aug-2017  Carmilo  - Added conditions to append parameters for test names that ends with space in Vanguard ET
# 30-Aug-2017  Carmilo  - Added conditions to cater historical Vanguard ET data.

package PDF::Parser::HP_ET;
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
    	my $header = new_headerLong;
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
        	if (/^ LOT ID\s+:(\S+)/) {
			my $lot = $1;
			$lot =~ s/\.//g;
            		$header->LOT(uc(trim($lot)));
			$header->populateSrcLot;  #look for source lot in pplot
        	}
        	if (/^ TYPE NO\s+:(\S+)/) {
            		$header->PRODUCT(trim($1));
        	}
        	if (/PCM SPEC:(\S+)/) {
			$header->REVISION(1);
            		$header->PROGRAM(trim($1));
        	}
        	if (/ DATE     :(\d{2}\/\d{2}\/\d{4})/) {
            		$header->START_TIME( $1 . " 00:00:00" );
            		$header->END_TIME( $1 . " 00:00:00" );
        	}
		if(/CUST PART NO:(.+)/){
			if($platform eq "EAGLE"){
				 $header->PRODUCT(trim($1));
			}			
		}
		#########################################################################################
		# USE FIX-LENGTH PARSING APPROACH ON WAFER ID AND SITE ID DUE TO SPACES	IN BETWEEN VALUES
		#########################################################################################
		if (/WAF\s+SITE \s+(.*)$/i) {
			my $line = $1;
			#if ($site eq 'tsmc_tw_et_hp' || ($site eq 'vgrd_tw_et_eagle' && $header->LOT !~ /^F/i)) {
			if ($site eq 'tsmc_tw_et_hp') {
				my $start = 13;
				my $interval = 12;
				for (my $i=1; $i<=10; $i++) {
					chomp($_);
					$_ =~ s/\015//;
					my $val = substr($_, $start, $interval);
					   $val =~ s/^\s*|\s*$//g;
					   $val =~ s/\s+/\_/g;
					   next unless $val ne "";
					   $start += $interval;
					my $test = new_test;
					   $test->number($testNum);
					   $test->name( repNA($val) );
					   $model->add('tests',$test);
					   $testNum++;

				}
			} elsif ($site eq 'vgrd_tw_et_eagle') { #carmilo
				my $flag = 0;
				my $count = 0;

				foreach (split(/\s+/, $line)) {
					if($_ =~ /^([A-Za-z])\1*$|^([0-9])\1*$|^\W\1*$|^[A-Z]{3}$|^[A-Z]{2}$|^([A-Z]{2})\([A-Z]\)$|^[a-z]{3}$/) {
						$flag = 1;
						last;
					}
				}

				if($flag == 1) {
					my @values = split(/\s+/, $line);
					for (my $i = 0; $i < scalar @values; $i++) {
						if($values[$i] =~ /^([A-Za-z])\1*$|^([0-9])\1*$|^\W\1*$/) {
							$values[$i-1] = join("",$values[$i-1],$values[$i]);
							splice @values, $i, 1;
						}elsif($values[$i] =~ /^[A-Z]{3}$|^[A-Z]{2}$|^([A-Z]{2})\([A-Z]\)$|^[a-z]{3}$/) {
							$values[$i-1] = join("_",$values[$i-1],$values[$i]);
							splice @values, $i, 1;
						}
					}
					foreach my $value (@values) {
						my $test = new_test;
						$test->number($testNum);
						$test->name(repNA($value));
						$model->add('tests',$test);
						$testNum++;
					}
				}else {
					foreach(split(/\s+/, $line)) {
						my $test = new_test;
						$test->number($testNum);
						$test->name(repNA($_));
						$model->add('tests',$test);
						$testNum++;
					}
				}
			} else {
				foreach ( split( /\s+/, $line)) {
					my $test = new_test;
					$test->number($testNum);
					$test->name( repNA($_) );
					$model->add('tests',$test);
					$testNum++;
				}
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

				if ( $site eq "vgrd_tw_et_eagle" ) {
					# EAGLE
                                        #if($platform eq "EAGLE" && $header->LOT !~ /^F/){
                                        #        $model->tests->[$tUnits]->name($model->tests->[$tUnits]->name."_". $model->tests->[$tUnits]->units);
                                        #        $model->tests->[$tUnits]->units("");
                                        #}
                                        #else{
                                                # special case if test name wraps to second line.
                                                if($model->tests->[$tUnits]->units =~ /\s/ ){
                                                        my @tmp = split /\s/, $model->tests->[$tUnits]->units;
                                                        $model->tests->[$tUnits]->name($model->tests->[$tUnits]->name." ".$tmp[0]);
                                                        $model->tests->[$tUnits]->units($tmp[1]);
                                                }
                                        #}	
				}
				else {
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
				}	
				
                	$tUnits++;
               		}
        	}
        	if (/^ SPEC HI\s+(.*)$/) {
            		foreach ( split( /\s+/, $1 ) ) {
        	        	$model->tests->[$tHI]->HSL($_);
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
				#assign source lot as wafer name
				if ($header->SOURCE_LOT ne ""){ 
					$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
					$model->misc->{wf_flg} = 1;
				}
               			$model->add('wafers',$wafer);
            		}

            		my $die = $wafer->find('dies',{site=>$site});

            		unless (defined $die){
               			$die = new_die( { site => $site } );
               			$wafer->add('dies',$die);
            		}

            		foreach ( split( /\s+/, $3 ) ) {
                		$die->add( 'result', $_ );
            		}
        	}

    	}
    	return $model;
}

#carmilo: conditions to check if split value is a valid test name
#sub validateTestName {
#	my $testName = shift;
#	my $fag = 0;
	
#	if($testName =~ /^([A-Za-z])\1*$/) {
#		$flag = 1;
#	}elsif($testName =~ /^([0-9])\1*$|([0-9]*)/) {
#		$flag = 1;
#	}elsif($testName =~ /^\W\1*$|(\W)$/) {
#		$flag = 1;
#	}elsif($testName =~ //) {
#
#	}
#}
1;






