=pod

=head1 SYNOPSIS

	instantiate and use its method/subroutine and attributes.
	

=head1 DESCRIPTIONS
	
B<This script> MiniKlarf/.TRF parser module.

=head1 AUTHOR

B<junifferallan.garcia@fairchildsemi.com>

=head1 CHANGES

	2016-Jul-28	jgarcia	: created

=head1 LICENSE

(C) Fairchild 2016 All rights reserved.

=cut
package PDF::Parser::MiniKlarf;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use Time::Local;
use File::Basename qw/basename/;
use IO::File;
use v5.10;
#no warnings qw/experimental::smartmatch experimental::lexical_subs/;
use base qw/PDF::DpData::Base Class::Accessor/;
use PDF::DpData::Defect;

our $VERSION = "1.0";

my $attr = [ qw/ / ];



sub array {
    return qw/ /;
}

__PACKAGE__->mk_accessors(@$attr, array );

sub readDefectFile {
	my $self		= shift;
	my $TRF	= shift;
	my $header	= new_headerLong;
	my $defect	= new_defect;
	my @defectLine = ();
	my $model  = new_model(
        {   header => $header,
            defect => $defect,
            misc   => [],
            dataSource => 'MiniKlarf'
        }
  );
  my $resultDateTime;
  my $resultDate;
  my $resultTime;
  my $slot;
  
  
  #open( INFILE, $infile );
  #while(<INFILE>) {
  my $fileHandle = IO::File->new($TRF) or dpExitError("Failed to open TRF file $TRF");	
  my ($resultDate, $resultTime);
  my ($d, $lotid);
  my $lineCounter = 1;
  
  while ( my $line = $fileHandle->getline ) {
  	#$line =~ s/[\cM|\"]//g;
  	#INFO("$line");
  	
  	#$defect->add('defects', \$line );
  	#push $model->defect, \$line;
  	#$model->{misc} = \$line;
  	#push $self->defectLine, $\line;
  	
  	#$defectData->defectLineData($line);
  	#$model->add('defects', $defectData);
  	push @defectLine, $line;
  	  
	  if ($line =~ m/^ResultTimestamp/) {
  		my @ids = split / /, $line;
			my $lastIndex = $#ids;
			$resultDate = $ids[1];
			trim($resultDate);
			$resultDate =~ s/[^[:print:]]+//g;
			$resultDate =~ s/[^0-9a-zA-Z\s:-]//g;
			my($m,$d,$y) = split /\-/, $resultDate;
					$y = (
            $y < 100
            ? ( $y < 70 ? 2000 + $y : 1900 + $y )
            : $y
         );
      $resultDate = $y."/".$m."/".$d;
			$resultTime = $ids[$lastIndex];
			trim($resultTime);
			$resultTime =~ s/[^[:print:]]+//g;
			$resultTime =~ s/[^0-9a-zA-Z\s:-]//g;
			$resultDateTime = $resultDate . " " . $resultTime;
			$resultDateTime = formatDateToYYYYMMDD($resultDateTime);
			$defect->RESULT_DATETIME($resultDateTime);
			#INFO("DATE=>$defect->{RESULT_DATETIME}");	
			
  	}
  	
  	if ($line =~ m/^LotID/) {
  		#if($lotid == "") {
				#$lotid = ($line =~ /^LotID "([\w\W]+)"/ig)[0];
				my @ids = split / /, $line;
				my $lastIndex = $#ids;
				$lotid = $ids[$lastIndex];
				trim($lotid);
			  $lotid =~ s/[^[:print:]]+//g;
				$lotid =~ tr/\"\;//d;
				INFO("$lotid");
				
				if($lotid =~ m/.+_.{8}/) {
					
					($d, $lotid) = split /\_/, $lotid, 2;
				} else {
					
					$lotid = substr($lotid, -8);
				}
				#$lotid =~ s/[^[:print:]]+//g;
				$defect->LOT($lotid);		
				#INFO("LOTID:=>" . $defect->LOT);	
				#printf "Line get lot id: $lotid\n" ;
			#}
  	}
  	
  	if ($line =~ m/^Slot/) {
  		my @ids = split / /, $line;
			my $lastIndex = $#ids;
			$slot = $ids[$lastIndex];
			$slot =~ tr/\"\;//d;
			trim($slot);
			#$slot =~ s/[^[:print:]]+//g;
			$defect->SLOT(trim($slot));
			#INFO("SLOT=>".$defect->SLOT);
		}
  	$lineCounter = $lineCounter + 1;
  }
  undef $fileHandle;
  $model->misc(@defectLine);
	return $model, ;
}

sub dpExitError {
	my $self    = shift;
	my $message = shift;
	dpExit( 1, $message );
}

#sub formatDateYYYYMMDD_H24MINSEC {
#	
#	our @months = qw( JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC );
#	my $date = shift;
#	my ($d, $t) = split /\s/, $date, 2;
#    my ($mon, $day, $year) = split /\-/, $d;
#    my $monIndex = $mon - 1;
#    my $month;
#    my $monthName;
#    
#    $monthName = $months[$monIndex];
#    print $monthName;
#    
#    $year = (
#            $year < 100
#            ? ( $year < 70 ? 2000 + $year : 1900 + $year )
#            : $year
#        );
#        
#    my $monthNumber = first_index { $_ eq uc(substr($monthName, 0, 3 )) } @months;
#        if ( $monthNumber < 0 ) {
#            dpExit( 1, "Invalid date :$date Month is not valid: $monthName->$month" );
#        }
#    my ($H24, $MIN, $SEC) = split /\:/, $t;
#    
#    my $newDate = sprintf( "%04d/%02d/%02d %02d:%02d:%02d", $year, ($monthNumber + 1), $day, $H24, $MIN, $SEC );
#    
#    return $newDate;
#}
1;