=pod

=head1 SYNOPSIS

instantiate and use its method/subroutine and attributes.

=head1 DESCRIPTIONS

B<This script> will read, parse Powerchip WAT and return a Model.pm instance.

=head1 AUTHOR

B<junifferallan.garcia@onsemi.com>

=head1 CHANGES
    2023-Sep-12 - jgarcia - use fixed-length parsing method.


=head1 LICENSE

(C) onsemi 2023 All rights reserved.

=cut

package PDF::Parser::PowerchipWat;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use IO::File;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";
my %data = {};
my $testNumData = 1;
my $arrayLength = 0;
my $withEpiScribeFlag = 0;


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
    my $epiScribeRefHashData = shift;
    
    my $header;

    if($site =~ /PWRCHIP/i) {
        $header = new_metadata;
    } else {
        $header = new_headerLong;
    }
    
    my $model  = new_model(
        {   header => $header,
            misc   => {},
            dataSource => ''
        }
    );
    # my $wafers = {};
    #my $waferSites = {};
    my ($tUnits,$tHI,$tLO,$critCounter) = (0,0,0,0);
    my $partid = 1;
    my $testNum = 1;
    my $dumpData;
    #my $waferName;
    #my $withEpiScribeFlag = 0;
    #open (INFILE, "<",$infile);
    my $fileHandle = IO::File->new($infile) or dpExit("Failed to open WAT file $infile");
    #while (<INFILE>) {
    while (my $line = $fileHandle->getline) {
        if($site =~ /PWRCHIP/i) {
            if($line =~ /TYPE NO :(.+)\s+PROCESS  :(.+)\s+PCM SPEC:(.+)\s+QTY:(.+)\s+pcs/i) {
            $header->ALTERNATE_PRODUCT(trim($1));
            $header->PROCESS(trim($2));
            #INFO("TEST=$header->{ALTERNATE_PRODUCT}||$header->{PROCESS}")
         
            }
            if($line =~ /LOT ID  :(.+)\s+DATE\s+:(.+)\s+TIME:(.+)\s+Program NAME:(.+)/i) {
                $header->LOT(trim($1));
                my $d = trim($2)." ".trim($3).":00";
                $header->START_TIME(formatDate($d));
                $header->DATE_TIME_MASK("%Y/%m/%d %H:%M:%S");
                $header->RECIPE(trim($4));
                #INFO("TEST=$header->{LOT}||$header->{START_TIME}||$header->{RECIPE}");
            }
            if($line =~ /VERSION :(.+)\s+TESTER TYPE:(.+)\s+TESTER ID:(.+)\s+PRODUCT ID:(.+)/i) {
                $header->RECIPE_REVISION(trim($1));
                $header->TESTER_TYPE(trim($2));
                $header->MEASURING_EQUIPMENT(trim($3));
                my ($product,$suffix) = split('-', trim($4));
                $header->PRODUCT(trim($product));
                #INFO("TEST=$header->{RECIPE_REVISION}||$header->{TESTER_TYPE}||$header->{MEASURING_EQUIPMENT}||$header->{PRODUCT}");
            }
            if($line =~ /OPERATOR:(.+)\s+TEST NAME:(.+)\s+TEST COUNT:(.+)\s+SPEC LIMITS:(.+)/i) {
                $header->OPERATOR(trim($1));
                #INFO("TEST=$header->{OPERATOR}");
            }

        } else {
            if ($line =~ /^ LOT ID\s+:(\S+)/) {
            $header->LOT(uc($1));
            }
            if ($line =~ /^ TYPE NO\s+:(\S+)/) {
                $header->PRODUCT($1);
            }
            if ($line =~ /PCM SPEC:(\S+)/) {
                $header->REVISION(1);
                $header->PROGRAM($1);
            }
            if ($line =~ / DATE     :(\d{2}\/\d{2}\/\d{4})/) {
                $header->START_TIME( $1 . " 00:00:00" );
                $header->END_TIME( $1 . " 00:00:00" );
            }
            
            if($line =~ /CUST PART NO:(.+)/){
            
                if($platform eq "EAGLE"){
                    $header->PRODUCT($1);
                }			
            }
        }
        
	    
        #if (/WAF\s+SITE \s+(.*)$/) {
        if ($line =~ /^\s+WAF(?:\s+SITE)?\s+.*$/) {
            my $dataLine = $line;
            $dataLine =~ s/^\s+//gs;
            $dataLine =~ s/\s+$//gs;
            my @dataLineArray = split(/\s+/, $dataLine);
            my $arrayLength = scalar(@dataLineArray);
            my $epiCol = $dataLineArray[1];
            #INFO("SCRIBEHEADER=$epiCol");
            
            if($epiCol =~ /EpiScribe/) {
                $withEpiScribeFlag = 1;
                $dumpData = shift(@dataLineArray);
                $dumpData = shift(@dataLineArray);
                $dumpData = shift(@dataLineArray);
                #INFO("TEST====>>>@dataLineArray");
            } else {
                $withEpiScribeFlag = 0;
                $dumpData = shift(@dataLineArray);
                $dumpData = shift(@dataLineArray);
                #INFO("NOWAFERTEST====>>>@dataLineArray");
            }
                       
            foreach my $item (@dataLineArray) {
                my $test = new_test;
                $test->number($testNum);
                $test->name( repNA($item) );
                $model->add('tests',$test);
                $testNum++;
            }
        }
        #########################################################################################
        # USE FIX-LENGTH PARSING APPROACH ON WAFER ID AND SITE ID DUE TO SPACES IN BETWEEN VALUES
        #########################################################################################
        if ($line =~ /ID\s+ID/i) {
            my $dataLine = $line;
            # $dataLine =~ s/^\s+//gs;
            # $dataLine =~ s/\s+$//gs;
            my $start    = 13;
            my $interval = 12;
            if($withEpiScribeFlag == 1) {
                $start = 28;
                $interval = 15;
            }
            for (my $i=1; $i<=10; $i++) {
                chomp($dataLine);
                $dataLine =~ s/\015//;
                my $val = substr($dataLine, $start, $interval);
                $val =~ s/^\s*|\s*$//g;
                $val =~ s/\s+/\_/g;
                # next unless $val ne "";
                $start += $interval;

                if (defined $model->tests->[$tUnits]) {
                    $model->tests->[$tUnits]->units($val);
                    # $model->tests->[$tUnits]->units($val);					 
                        
                        # EAGLE
                    if($platform eq "EAGLE"){
                        $model->tests->[$tUnits]->name($model->tests->[$tUnits]->name."_". $model->tests->[$tUnits]->units);
                        $model->tests->[$tUnits]->units("");									
                    } else{				
                    # special case if test name wraps to second line.
                        if($model->tests->[$tUnits]->units =~ /\s/ ){
                                
                            my @tmp = split /\s/, $model->tests->[$tUnits]->units;
                            $model->tests->[$tUnits]->name($model->tests->[$tUnits]->name." ".$tmp[0]);
                            $model->tests->[$tUnits]->units($tmp[1]);
                                                
                        }
                    }
                } else {
                        # Handle the case where the test is undefined
                        WARN("Test at index $tUnits is undefined. Unable to set 'units'.");
                        # next;
                
                
                }
                        
                $tUnits++;
            }
        }
        if ($line =~ /SPEC HI\s+.*$/) {
            my $dataLine = $line;
            $dataLine =~ s/^\s+//gs;
            $dataLine =~ s/\s+$//gs;
            my @dataLineArray = split(/\s+/, $dataLine);
            my $dumpData = shift(@dataLineArray);
            $dumpData = shift(@dataLineArray);
            my $arrayLength = scalar(@dataLineArray);
            foreach my $item (@dataLineArray) {
                # $item = repNA(trim($item));
                $model->tests->[$tHI]->HSL($item);
                $tHI++;
            }
        }
        if ($line =~ /SPEC LO\s+.*$/) {
            my $dataLine = $line;
            $dataLine =~ s/^\s+//gs;
            $dataLine =~ s/\s+$//gs;
            my @dataLineArray = split(/\s+/, $dataLine);
            my $dumpData = shift(@dataLineArray);
            $dumpData = shift(@dataLineArray);
            my $arrayLength = scalar(@dataLineArray);       
            foreach my $item (@dataLineArray) {
                # $item = repNA(trim($item));
                $model->tests->[$tLO]->LSL($item);
                $tLO++;
            }
        }

        # if ($line =~ /(SPEC HI)\s+(.*)$/) {
        #     my $type = $1;
        #     my $dataLine = $2;

        #     # Clean up leading and trailing whitespaces
        #     $dataLine =~ s/^\s+|\s+$//g;

        #     # Extract values into an array
        #     my @dataLineArray = split /\s+/, $dataLine;

        #     # Skip the first two values
        #     shift @dataLineArray for (1..2);

        #     # Process each item in the array
        #     foreach my $item (@dataLineArray) {
        #         # Your logic here
        #         # print "$type - $item\n";

        #         # Example: $model->tests->[$tHI]->HSL($item) if $type eq 'SPEC HI';
        #         # Example: $model->tests->[$tLO]->LSL($item) if $type eq 'SPEC LO';
        #         if($type eq 'SPEC HI') {
        #             $model->tests->[$tHI]->HSL($item);
        #             $tHI++;
        #         }
        #         if($type eq 'SPEC LO') {
        #             $model->tests->[$tLO]->LSL($item);
        #             $tLO++
        #         }
        #         # $tHI++ if $type eq 'SPEC HI';
        #         # $tLO++ if $type eq 'SPEC LO';
        #     }
        # }

        # if ($line =~ /(SPEC HI|SPEC LO)\s+(.*)$/) {
        #     my $type = $1;
        #     my $dataLine = $2;

        #     # Clean up leading and trailing whitespaces
        #     $dataLine =~ s/^\s+|\s+$//g;

        #     # Extract values into an array
        #     my @dataLineArray = split /\s+/, $dataLine;

        #     # Skip the first two values
        #     shift @dataLineArray for (1..2);

        #     # Process each item in the array
        #     foreach my $item (@dataLineArray) {
        #         # Your logic here
        #         # print "$type - $item\n";

        #         # Example: $model->tests->[$tHI]->HSL($item) if $type eq 'SPEC HI';
        #         # Example: $model->tests->[$tLO]->LSL($item) if $type eq 'SPEC LO';
        #         if($type eq 'SPEC HI') {
        #             $model->tests->[$tHI]->HSL($item);
        #             $tHI++;
        #         }
        #         if($type eq 'SPEC LO') {
        #             $model->tests->[$tLO]->LSL($item);
        #             $tLO++
        #         }
        #         # $tHI++ if $type eq 'SPEC HI';
        #         # $tLO++ if $type eq 'SPEC LO';
        #     }
        # }

        if ($line =~ /CRIT\s+.*$/) {
            my $dataLine = $line;
            $dataLine =~ s/^\s+//gs;
            $dataLine =~ s/\s+$//gs;
            my @dataLineArray = split(/\s+/, $dataLine);
            my $dumpData = shift(@dataLineArray);
            #$dumpData = shift(@dataLineArray);
            my $arrayLength = scalar(@dataLineArray);       
            foreach my $item (@dataLineArray) {
                # $item = repNA(trim($item));
                $model->tests->[$critCounter]->critical($item);
                $critCounter++;
            }
        }

        #if ($line =~ /(\d+)(?:([A-Z0-9]+)\s+)?-?\d+.*$/) {
        if ($line =~ /^\s+(\d{1,2})\s+(\w+)?\s+\-(\d+)\s+(.*)$/) {
            my $waferNum = $1;
            my $waferName = $2;
            my $site = $3;
            my $dataLine = $4;
            my $dump;
            if($waferName eq "") {
                INFO("EpiScribe is not avaialable from raw file, try to get from reference file perl LOT=$header->{LOT} and WAFER_NUM=$waferNum..");
                my $key = $header->{LOT}."_".$waferNum;
                $waferName = $epiScribeRefHashData->{$key};
            }
            $dataLine =~ s/^\s+//gs;
            $dataLine =~ s/\s+$//gs;
            # INFO("+++++>>>>$dataLine<<<<+++++");
            my @dataLineArray = split(/\s+/, $dataLine);
           
            # INFO("NUM=$waferNum||NAME=$waferName||SITE=$site||PARTID=$partid");
            
            #INFO("DATA ARRAY LENGTH=".scalar(@dataLineArray));
            my $wafer = $model->find('wafers',{number => $waferNum}, name => $waferName);
            unless (defined $wafer){
               $wafer = new_wafer( { number => $waferNum, name => $waferName } );
               $model->add('wafers',$wafer);
            }
            my $die = $wafer->find('dies',{site=>$site});
            unless (defined $die){
               $die = new_die( { site => $site});
               #$die->x($dieX);
               #$die->y($dieY);
               $wafer->add('dies',$die);
               $partid++;
            }
            foreach my $result (@dataLineArray) {
                $die->add( 'result', repNA($result) );
            }
            # foreach my $test ( @{ $model->tests } ) {
            #     #INFO("RESULT=>>$hashResultData{$test->number}<<<");
            #     $die->add( 'result', $hashResultData{$test->number});
            # }
             #$wafer->add('dies',$die);
        }

    }
    return $model;
}


1;

