# SVN $Id: SLET_HP.pm 2087 2017-03-29 08:20:45Z dpower $
# 2015-Aug-26 Gilbert - Uppercase the lot id.
# 2017-Mar-29 Eric    - get source lot from pp_lot and assign as wafer name
package PDF::Parser::SLET_HP;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use DBIx::Simple;
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
    	my $self        = shift;
    	my $infile      = shift;
	my $limitdir	= shift;
	my $limit_file	= shift;	
    	my $header      = new_headerLong;
    	my $model       = new_model(
        {   header => $header,
            misc   => {},
            dataSource => 'HP'
        }
    	);
    	my $wafers      = {};
    	my $waferSites  = {};
    	my ($tUnits,$tHI,$tLO) = (0,0,0);
    	my $startDate   = "";
    	my $paramNum    = undef;
    	my $siteNum     = undef;
    	my $equipType   = undef;
    	my $probeCard   = undef;
    	my $lineCnt     = 1;
    	my $siteCnt     = 1;
    	my $paramCnt    = 1;
    	my $die; 
    	my $wafer;
    	my $test;
	my $limit_value = "true";
	my %waferTime   = ();
	my %hwafer    	= ();
	my $waferNumPre = undef;
	my $operator	= undef;
	#my $tns    = "dbi:Oracle:host=oruxymsora01p;port=1521;sid=YMS01PRD";
	#my $db     = DBIx::Simple->connect($tns,"exn_user","exn_user") or die DBIx::Simple->error;
	my $srclot;

    	open (INFILE, "<",$infile);
	
	my @arycontents = <INFILE>;
    	foreach my $line (@arycontents) {
        	if ($lineCnt == 1) {
			if ($line =~ /(.+)_(.+)/) {
        	        	$header->PROGRAM($1);
        	        	$header->REVISION($2);
        	    	}
        	}
        	if ($lineCnt == 3) {
            		if ($line =~ /(\d{2})-(\w{3})-(\d{2})/) {
                		$startDate = "$2 $1 20$3,"; #Jan 18 2014,  
				$operator = $line;
            		}
        	}
        	if ($lineCnt == 4) {
            		if ($line =~ /(\d{2}:\d{2}:\d{2})/) {
	        		$startDate = $startDate . " $1";	
                		$header->START_TIME( formatDate($startDate));
            		}
        	}
		if ($lineCnt == 5) {
			$header->OPERATOR($line);
		}
        	if ($lineCnt == 6) {
            		$header->LOT(uc(trim($line)));
			$srclot = &getSrcLot($header->LOT);
		}
        	if ($lineCnt == 7) {
            		if ($line =~ /(\d+)/) {
                		$paramNum = $1;
            		}
        	}
        	if ($lineCnt == 8) {
            		if ($line =~ /(.+)/) {
                		$siteNum  = $1;
            		}
        	}
        	if ($lineCnt == 9) {
            		$header->EQUIP1_ID($line);
        	}
        	if ($lineCnt == 10) {
            		if ($line =~ /(.+)/) { 
                		$probeCard = $1;
                		$header->EQUIP3_ID($probeCard);
            		}
        	}
        	if ($lineCnt == 11) {	      
                	my $waferNum = trim($line);
			if( $waferNum ne $waferNumPre) {
				if(exists $hwafer{$waferNum}){
					$hwafer{$waferNum} = $hwafer{$waferNum}+ .1;
				}
				else{
					$hwafer{$waferNum} = 0;
				}					
			}
				
			$waferNumPre = $waferNum;
            		$wafer = $model->find('wafers',{key => $waferNum+$hwafer{$waferNum}});
				
            		unless (defined $wafer){
               			$wafer = new_wafer( { key => $waferNum+$hwafer{$waferNum} } );
				$wafer->number($waferNum);
				if ($srclot ne "") {
					$wafer->name($srclot."_".sprintf("%02d",$wafer->number));
				}
               			$model->add('wafers',$wafer);
                        	$wafer->START_TIME(formatDate($startDate));
				$waferTime{$wafer}{formatDate($startDate)} = 1;
									
				my $revision = $header->REVISION ;
				$revision =~ s/\s+//g;
				#INFO($header->PROGRAM);
				my $searchPath = "$limitdir/".$header->PROGRAM."_".$revision."*";
				#INFO($searchPath);
				my ($limitfile) = glob($searchPath);
				
				unless (defined $limitfile) {
					  $limit_value = "false";
					  $$limit_file = "not";
			 	}
				
				if($limit_value =~ /true/){					
					my $limit = $self->readLimitFile($limitfile);
					$$limit_file = $limitfile;
					$wafer->tests($limit->tests);	
					$limit_value = "true";											  
				} 
            		}
        	}
        	if ($lineCnt == 12) {
            		if ($line =~ /(\d+)/) {
                		my $site = $1;
	        		$die = $wafer->find('dies',{site=>$site});
                		unless (defined $die){
                    			$die = new_die( { site => $site } );
                    			$wafer->add('dies',$die);
                		}
            		}
        	}
        	if ($lineCnt == 13) {
            		if ($line =~ /(\w+)/) {
                		$die->x(int($1)) ;
            		}
        	}
        	if ($lineCnt == 14) {
            		if ($line =~ /(\w+)/) {
                		$die->y(int($1)) ;
            		}
        	}
        	if (( $lineCnt > 14) and ($paramCnt == $paramNum) and ($siteCnt == $siteNum)) {
            		$paramCnt = 1;
            		$lineCnt = 0;
            		$siteCnt = 1;
			$die->add( 'result', trim($line) );
		}			
        	if (( $lineCnt > 14) and ($paramCnt == $paramNum)) {
                	$test = new_test;
                	$test->number($paramCnt);
                	#$model->add('tests',$test);
                	$wafer->add('tests',$test) if ($siteCnt == 1 and $limit_value eq "false");
                	$die->add( 'result', trim($line) );
            		$paramCnt = 1;
            		$lineCnt  = 10;
            		$siteCnt  = $siteCnt + 1;            	
							
        	}
        	if (( $lineCnt > 14) and ($paramCnt < $paramNum )) {
                	$test = new_test;
                	$test->number($paramCnt);
                	#$model->add('tests',$test);
                	$wafer->add('tests',$test) if ($siteCnt == 1 and $limit_value eq "false");
                	$die->add( 'result', trim($line) );
        		$paramCnt = $paramCnt + 1;			
        	}
		#        if ($siteCnt == $siteNum ) {
		#            $lineCnt = 0;
		#            $siteCnt = 1;
		#        }
        	$lineCnt++;
        }

        return $model;

=pod
        if (/LotID=(\S+?),/) {
            my $lotid = $1;
            $lotid =~ s/\.//;
            $header->LOT(uc($lotid));
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
        if (/^TestName,,(.*),/) {
            foreach ( split( /,/, $1 ) ) {
                my $test = new_test;
                $test->number('');
                $test->name( repNA($_) );
                $model->add('tests',$test);
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
        if (/^(\d{1,2}),(\d+?),(.*),/) {
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
            foreach ( split( /,/, $3 ) ) {
                $die->add( 'result', $_ );
            }
        }
=cut

}

sub readLimitFile {
	#INFO("call  limit reading");
    	my $self   = shift;
    	my $infile = shift;
    	my $limit = new_limit;    
	$limit->conditionNames([qw/testType/]);
    	my $num = 0;
	my $program = "";
	my $revision = "";
	if($infile =~/(\s+)_(\d+)/)
	{
		$program = $1;
		$revision = trim($2);
	}
    	open( INFILE, $infile );
    	while (<INFILE>) {
        	s/[\r\n]+\z//;
		if(/DESCRIPTION/)
		{
			$limit->REVISION($revision);
			$limit->PROGRAM($program);
		}
        	if (/,/) {
          		my $test = new_test;
          		my @items= split(',',$_);
		  	$items[0] =~ s/^0//;
		  	$test->number($items[0]);
		  	my $name = trim($items[1]);
		  	my $testType = "";
	  
		  	if( $name =~ /##_(.*)/)
		  	{		
				$testType = "C";
				$test->add('conditions',$testType);
		  	}
		  	else
		  	{
				$test->add('conditions',repNA(''));
		  	}

          		$test->name($name);
          		$test->LSL(trim($items[3]));
          		$test->HSL(trim($items[4]));
          		$test->LOL(trim($items[5]));
          		$test->HOL(trim($items[6]));
          		$test->units(trim($items[2]));
		  	#$test->group(repNA($critical));
         		# $test->add('conditions',(trim($items[2])));
         		# $test->add('conditions',(trim($items[7])));
          		$limit->add('tests',$test);
        	} 
    	}  
   	return $limit;
}

sub getSrcLot {
	my $lot    = shift;
	my $tns    = "dbi:Oracle:host=oruxymsora01p;port=1521;sid=YMS01PRD";
	my $db     = DBIx::Simple->connect($tns,"exn_user","exn_user") or die DBIx::Simple->error;
	my $sql    = q(select * from refdb.pp_lot where lot = ?);
	my $hash   = $db->query( $sql, $lot )->hash;
	my $srclot = $hash->{source_lot};
	
	if ($srclot eq ""){
		WARN ("Source lot not found in PP_LOT.");
	}
	return $srclot;
}

1;

