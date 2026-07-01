#!/usr/bin/env perl_db
=pod

=head1 SYNOPSIS

  
=head1 DESCRIPTIONS

B<This script> will check Registered Program if have loaded Limits in Production DB, 
								otherwise unregister the Program in PP_LIMITS

=head1 AUTHOR

B<junifferallan.garcia@onsemi.com>

=head1 CHANGES

 2016-Sep-29 : initial
 2016-Oct-25 : added mail notification and only check of Registered Program for the past 24 hours.
 2016-Oct-27 : modified to add environment to the report
 2016-Oct-27 : modified to exclude REL.
 2016-Nov-03 : modified to exclude program class 9 data and removed duplicates.
 2016-Nov-14 : add the appropriate prefix to the affected program to be able to match it equally against productio.program
	       and reliability.program.
 		 be able to distinguish which registered program to unregister between PCM and PCM for PSA.
 2019-Jun-06 Eric : changed email add domain to onsemi
 
 
=head1 LICENSE

(C) ON Semiconductor. 2016 All rights reserved.

=cut

use strict;
#use warnings;
use FindBin::libs;
use Getopt::Long qw/:config ignore_case auto_help/;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use PDF::DAO::Refdb;
use PDF::DAO::ProdDB;
use PDF::DAO;
use PDF::Log;
use Try::Tiny;
use Net::SMTP;
use MIME::Lite;
use DateTime;


# a hash to receive options
my (%hOptions) = ();

unless ( GetOptions ( \%hOptions, "LOGFILE=s", "MAIL=s","DEBUG") ) {
    pod2usage(3);
}

my @required_options = qw/LOGFILE MAIL/;

if(grep {!exists $hOptions{$_}} @required_options) {
	pod2usage(3);
}

my $dateTime = `date`;
my @dateInfo = split /\s+/, $dateTime;
my $programKey = "";
my $programName = "";
my %hash;
my @noLimitProgramArray = ();
my $logFile = $hOptions{LOGFILE};
my $emailAdd = $hOptions{MAIL};
my $OUTLOGFILE;
my $result = "";
my $errorFlag = 0;
my $program;
#my $revision;
my ($limitRev, $limitInsertTime, $prevKey) = "";
my %hashNoLimitProgram = ();
my %limits = getProductionDb->getLimit();
my $prgName = "";
my $listResult  = "";
my $body = "";
my $body2 = "";
my $dt = "";#DateTime->now(time_zone => 'local');
my $currentDateTime = "";# join ' ', $dt->ymd, $dt->hms;
my $env = "";
my $insertTime = "";
my $trimmedRevision = "";
my %hashForReport = ();
my $dupProgramName = "";
my $messageFlag = 0;



foreach my $pgName (keys %limits) {
	
	($prgName, $insertTime, $env) = split /--/, $pgName, 3;
	
	my $pgClassPrefix = &getPgClassPrefix($env);
	#print "PG CLASS = $pgClassPrefix\n";
	
	if($pgName !~ /WKS$/i && $pgName ne  "" && $pgClassPrefix ne ""  ) {
		$programKey = "";
  	$programName = "";
  	($programKey, $programName) = getProductionDb->getPGKEY($prgName, $pgClassPrefix);
		$dupProgramName = $programName."--".$insertTime."--".$env;
		
  	foreach my $revision (split /\,/, $limits{$pgName}) {
  		
  		$prevKey = "";
  		#print "REV=>$revision\n";
  		#$trimmedRevision = trim($revision);
  		#print "Trimmed=>$revision\n";	
			if ($programKey ne "") {
				($prevKey) = getProductionDb->getPrevkey($programKey, $revision);
			}
			
			#print "\nPROGRAM_KEY=>>$programKey<<||PREV_KEY=>>$prevKey<<||PROGRAM_NAME=>>$programName<<\n";
		
			if($programKey ne ""  && $prevKey ne "") {
				#try {
				 $limitInsertTime = "";
				 $errorFlag = 0;
				 $limitRev = "";
				($limitRev, $limitInsertTime, $errorFlag) = getProductionDb->runGetLimitFunction($programKey, $prevKey);
				
				 #print "Rev>>$limitRev<<||>>LIMIT Insert date>>$limitInsertTime<<||>>$errorFlag<<\n";
				#} catch {     
					#print "got Error $_\n";
				#}
				if($limitInsertTime eq "" && $errorFlag != 1) {
					#push @noLimitProgramArray,$pgName;
					$hashNoLimitProgram{$pgName} = $revision;	
					$hashForReport{$dupProgramName} = $revision;
				}
			} else {
				my ($relPgKey, $relPgName) = getProductionDb->getPGKEY_REL_DB($prgName, $pgClassPrefix);
				if($relPgKey eq "") {
					$hashNoLimitProgram{$pgName} = $revision;
					$hashForReport{$dupProgramName} = $revision;
				}
			}
	
		}#splitting revision
	}#wks skipped
}
#
$dt = DateTime->now(time_zone => 'local');
$currentDateTime = join ' ', $dt->ymd, $dt->hms;
my $logFileName = "log_".$currentDateTime;
$logFileName =~ s/\s+/\_/g;
$logFileName =~ s/\:/\-/g;
$logFile .= "/".$logFileName.".log";
open ($OUTLOGFILE, '>', $logFile) or die "Could not open file '$logFile' $!";
  
  my $dateTimeScriptRun = "report generated on $currentDateTime $dateInfo[4]";
  my $message = "There are no Registered Programs which dont have limits loaded into Production DB for the past 24 hours!!!";
  if (%hashNoLimitProgram) {
  	
  	foreach my $hKey (keys %hashNoLimitProgram) {
	
			my ($limitName,$insertTime, $env) = split /--/, $hKey, 3;
			
			#print "For Drop=>$limitName||$hashNoLimitProgram{$hKey} ";
			print $OUTLOGFILE "$limitName,$hashNoLimitProgram{$hKey},$insertTime $dateInfo[4],$currentDateTime $dateInfo[4],$env";
			#print "\nProgram=$limitName<||>Revision=$hashNoLimitProgram{$hKey}<||InsertTime=$insertTime<\n"
	                $listResult = qq(<div class="col bg-info">$limitName</div>
					 <div class="col bg-info">$hashNoLimitProgram{$hKey}</div>
					<div class"col bg-info>$insertTime $dateInfo[4]</div>
					"<div class="col bg-info">$currentDateTime $dateInfo[4]</div>
					<div class="col bg-info">$env</div>);
			### try to unregister Limits by updating the program name ###
			if ($limitName ne "" && $hashNoLimitProgram{$hKey} ne "" && $insertTime ne "" ) {
				my $rvsn = trim($hashNoLimitProgram{$hKey});
				getProductionDb->updateProgramNameInPP_LIMITS($limitName,$rvsn,$insertTime,$currentDateTime);
			}
			
			#print "\n";
			print $OUTLOGFILE "\n";
			
		}
  	
  } else {
        $messageFlag = 1;
  	$listResult = $message;
		$listResult .= qq(<hr>\n<div class="col-lg-6"><span id="reportDate">$dateTimeScriptRun</span></div>);
		print $OUTLOGFILE "$message";
		print $OUTLOGFILE "\n";
		print $OUTLOGFILE "$dateTimeScriptRun"; 
  }
	
close $OUTLOGFILE;


### send a notificatin mail
sendEmail("Program(s) registered in REFDB.PP_LIMITS with no limits loaded", $emailAdd);

exit 0;

#################### SUB ROUTINE ############################################
sub getLimits {
	
	my $limits;
	#my ($prgName, $rev);
	$limits = getProductionDb->getLimit();
	#%limits = ("Name" => $prgName, "Revision" => $rev,);
	return $limits;
	
}

sub getRegLimitsAndPGKEY {
	
	my $self = shift;
	my $hash;
	my $lookupTable = "PP_LIMTS";
	
	
}

sub sendEmail
{
       my ($subject, $emailTo) = @_;
       
       if ($messageFlag == 0) {
       		
       	   $body = qq(<!DOCTYPE html>
<html lang="en">
<head>
  <title>Bootstrap Example</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/4.4.1/css/bootstrap.min.css">
  <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.4.1/jquery.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.16.0/umd/popper.min.js"></script>
  <script src="https://maxcdn.bootstrapcdn.com/bootstrap/4.4.1/js/bootstrap.min.js"></script>
</head>
<body>

<div class="container-fluid">
  <div class="row">
    $listResult 
  </div>
          
</div>

</body>
</html>);	
       		
       } else {    
                $body = qq(<!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta http-equiv="X-UA-Compatible" content="ie=edge">
            <!-- Google Font -->
            <link href="https://fonts.googleapis.com/css?family=Nunito:200,300,400,700" rel="stylesheet">
             <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/4.4.1/css/bootstrap.min.css">
  <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.4.1/jquery.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.16.0/umd/popper.min.js"></script>
  <script src="https://maxcdn.bootstrapcdn.com/bootstrap/4.4.1/js/bootstrap.min.js"></script>

            <style>
                body {
                    font-family: "Nunito", sans-serif;
        }       }
                hr {
    border: 0;
    height: 1px;
    background-image: linear-gradient(to right, rgba(0, 0, 0, 0), rgba(0, 0, 0, 0.75), rgba(0, 0, 0, 0));
}
#reportDate {
   font-size: .2rem;
   color: red;
}

            </style>
        
            <title>Document</title>
        </head>
        <body>
            <div class="container-fluid px-0">
                <div class="d-flex flex-row justify-content-center">
                         $listResult
                </div>
        
            </div>
        
        
            <!-- Optional JavaScript -->
            <!-- jQuery first, then Popper.js, then Bootstrap JS -->
            
        </body>
        </html>);       
        
	       $messageFlag = 0; 
      }


        my $mailto = MIME::Lite->new
        (
                Subject => "$subject",
                From    => 'yms.admins@onsemi.com',
                To      => "$emailTo",
                Data    => "$body"
        );

    		$mailto->attr("content-type" => "text/html");
        $mailto->send();
        #system "echo $body | mutt -s '$subject'  -- '$emailTo'";
}

sub trim {
    my ($text) = @_;

    if ($text) {
        $text =~ s/[\n\r]//gs;
        $text =~ s/^\s+//gs;
        $text =~ s/\s+$//gs;
        $text =~ s/\"$//gs;
        $text =~ s/^\"//gs;
        $text =~ s/[^\x09-\x7E]//gs;
    }
    return $text;
}

sub getPgClassPrefix {
	my $environment = shift;
	my $pgClassPrefix = "";
	
	if ($environment =~ /ft_/) {
		$pgClassPrefix = "FT";
	} elsif ($environment =~ /sort_/) {
		$pgClassPrefix = "WS";
	} elsif ($environment =~ /et_hp$|et_ams$|et_eagle$|et_bc3$|et_bp$|et_rdhm$/) {
		$pgClassPrefix = "PCM";
	} 
	
	#print "INSIDE subroutine get pg class=$pgClassPrefix\n";
	return ($pgClassPrefix);
}

