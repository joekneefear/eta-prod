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
my $listResult;
my $body = "";
my $body2 = "";
my $dt = "";#DateTime->now(time_zone => 'local');
my $currentDateTime = "";# join ' ', $dt->ymd, $dt->hms;
my $env = "";
my $insertTime = "";
my $trimmedRevision = "";
my %hashForReport = ();
my $dupProgramName = "";



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
			#print "\nProgram=$limitName<||>Revision=$hashNoLimitProgram{$hKey}<||InsertTime=$insertTime<\n";
			$listResult  .= "<tr>"
									 .  "<td colspan='' width='450'>$limitName</td>"."<td colspan=''width='90'>$hashNoLimitProgram{$hKey}</td>"
									 .  "<td colspan='' width='170'>$insertTime $dateInfo[4]</td>"."<td colspan='' width='170'>$currentDateTime $dateInfo[4]</td>"
									 .  "<td colspan='' width='150'>$env</td>"
									 .  "</tr>";
			### try to unregister Limits by updating the program name ###
			if ($limitName ne "" && $hashNoLimitProgram{$hKey} ne "" && $insertTime ne "" ) {
				my $rvsn = trim($hashNoLimitProgram{$hKey});
				getProductionDb->updateProgramNameInPP_LIMITS($limitName,$rvsn,$insertTime,$currentDateTime);
			}
			
			#print "\n";
			print $OUTLOGFILE "\n";
			
		}
  	
  } else {
  	$listResult .= "<tr>"."<td colspan='6' width=''>$message</td>"."</tr>";
  	$listResult .= "<tr>"."</tr>";
		$listResult .= "<tr>"."<td colspan='6' width=''>$dateTimeScriptRun</td>"."</tr>";
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
       
       if ($listResult =~ /.+Registered Programs.+/i) {
       		
       		$body = '<!DOCTYPE html>'
	                    . '<html>'
	                    . '<head>'
	                    . '<style type="text/css">'
	                    . 'table, th, td'
	                    . '{'
	                    . 'font-family: Tahoma;'
	                    . 'font-size: 12px;'
	                    . 'text-align: left;'
	                    . 'white-space: nowrap;'
					            #. 'tr{background: #b8d1f3;}'
					            #. 'tr:nth-child(odd){background: #b8d1f3;}'
					            #. 'tr:nth-child(even){background: #dae5f4;}'
					                    . '}'
					                    . "table"
					                    . "{ width: 650px;}"
					                    . "th, {style=color:initial;}"
					            . ".odd{background-color:white;}"
					            . ".even{background-color:gray;}"
					                    . "</style>"
					            . '<script>'
					            . 'function doAlternate(row, i){'
					            . 'if(i % 2 == 0){'
					            . 'row.className = "even";'
					            . '}else{'
					            . 'row.className = "odd";'
					            . '}'
					            . '}'
					            . 'function alternate(id){'
					            . 'method = document.methodSelector.selector[document.methodSelector.selector.selectedIndex].value;'
					                    . 'if(document.getElementById){'
					            . 'var table = document.getElementById(id);'
					            . 'var rows = table.getElementsByTagName("tr");'
					            . 'for(i = 0; i < rows.length; i++){'           
					            . 'doAlternate(rows[i], i);'
					            #. "    if(method == "doAlternate") doAlternate(rows[i], i);"
					            #. "    if(method == "doMultiple") doMultiple(rows[i], i);"
					            #. "    if(method == "doGradient") doGradient(rows[i]);"
					            . '}'
					                . '}'
					                    . '}'
					            . '</script>'
					                    . '</head>'
					                    . '<body onload="alternate(\'thetable\')">'
					                    . '<table id="thetable" width="" border="0" cellpadding="">'
					            . '<thead>'
					#                    .    "<tr nowrap style='background-color:#00E6E6;'>"
					#                    .       "<th colspan='2' width=''>Program Name</th>"
					#                    .       "<th colspan='2' width=''>Revision</th>"
					#                    .       "<th colspan='2' width=''>Insert Time in PP_LIMITS</th>" 
					#                    .       "<th colspan='2' width=''>Update Time in PP_LIMITS</th>"                                       
					#                     .    "</tr>"
							            .  '</thead>'
							            .  '<tbody>'
									    ."<tr><td></td></tr>"
									    . $listResult
									                      
							        		.  '</tbody>'
							         . '</table>'
							        . '</hr></br>'
							        . '</body>'
							        . '</html>';
       		
       		
       } else {           
        
        	$body = '<!DOCTYPE html>'
                    . '<html>'
                    . '<head>'
                    . '<style type="text/css">'
                    . 'table, th, td'
                    . '{'
                    . 'font-family: Tahoma;'
                    . 'font-size: 12px;'
                    . 'text-align: left;'
                    . 'white-space: nowrap;'
				            #. 'tr{background: #b8d1f3;}'
				            #. 'tr:nth-child(odd){background: #b8d1f3;}'
				            #. 'tr:nth-child(even){background: #dae5f4;}'
				                    . '}'
				                    . "table"
				                    . "{ width: 750px;}"
				                    . "th, {style=color:initial;}"
				            . ".odd{background-color:white;}"
				            . ".even{background-color:gray;}"
				                    . "</style>"
				            . '<script>'
				            . 'function doAlternate(row, i){'
				            . 'if(i % 2 == 0){'
				            . 'row.className = "even";'
				            . '}else{'
				            . 'row.className = "odd";'
				            . '}'
				            . '}'
				            . 'function alternate(id){'
				            . 'method = document.methodSelector.selector[document.methodSelector.selector.selectedIndex].value;'
				                    . 'if(document.getElementById){'
				            . 'var table = document.getElementById(id);'
				            . 'var rows = table.getElementsByTagName("tr");'
				            . 'for(i = 0; i < rows.length; i++){'           
				            . 'doAlternate(rows[i], i);'
				            #. "    if(method == "doAlternate") doAlternate(rows[i], i);"
				            #. "    if(method == "doMultiple") doMultiple(rows[i], i);"
				            #. "    if(method == "doGradient") doGradient(rows[i]);"
				            . '}'
				                . '}'
				                    . '}'
				            . '</script>'
				                    . '</head>'
				                    . '<body onload="alternate(\'thetable\')">'
				                    . '<table id="thetable" width="" border="0" cellpadding="">'
				            . '<thead>'
				                    .    "<tr nowrap style='background-color:#235A92;color:white;'>"
				                    .       "<th width='400'>Program Name</th>"
				                    .       "<th width='90'>Revision</th>"
				                    .       "<th width='170'>Date Registered</th>" 
				                    .       "<th width='170'>Date Unregistered</th>" 
				                    .       "<th colspan='' width='150'>Environment</th>"                                      
				                    #.       "<th width='200'>Site</th>"
				                    .    "</tr>"
				            .  '</thead>'
				            .  '<tbody>'
								    #."<tr><td></td></tr>"
								    . $listResult
								                     
						        		.  '</tbody>'
						         . '</table>'
						        . '</hr></br>'
						        . '</body>'
						        . '</html>';
	        
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

