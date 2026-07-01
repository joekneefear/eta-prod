#! /usr/bin/env perl_db
#
#
# Date       Who            Comment
# ---------- -------------- ----------------------------------------------------------------------
# 03/04/2008 Ben Rommel Kho Author. Monitor/report if disk usage is beyond the specified threshold
# 06/26/2010 Ben Rommel Kho Excluded CDROM device and utilized the edbmgr .forward for the notification
# 01/19/2012 Gilbert Miole  Modify email notification
# 01/09/2013 Gilbert Miole  Modify to work in Linux and enhanced report
# 01/10/2013 Rodncye Cyr    Implement separate threshold for /data partition.
# 02/01/2014 Gilbert Miole  Exclude /archives-nas2 from the monitor.
# 06/10/2014 Gilbert Miole  Fixed bug and corrected variable spelling.
# 06/16/2014 Gilbert Miole  Adjust threshold from 90% to 95%.
# 05/19/2015 Gilbert Miole  Ported to Exensio.
# 04/10/2016 Eric Alfanta   Use arguments for easier maintenance
# 06/06/2019 Eric Alfanta   Changed email add domain to onsemi.com
# 05/10/2021 jgarcia        modified to work on colo server
#


use MIME::Lite;
use Getopt::Long;

###################
# GLOBAL VARIABLES
###################
my $header     		= "";
my $details    		= "";
#my $alarm      		= 100;
#my $threshold  		= 95;
#my $threshold_data_part = 75;
my $alarm = "";
my $threshold = "";
my $threshold_data_part = "";
my $body       		= "";
my $email      		= "";
my $hostname 	        = `hostname`;
                          chomp($hostname);

######################
# RETRIEVE PARAMETERS
######################
$result = GetOptions ("email=s" => \$email,
		      "alarm=s" => \$alarm,
		      "threshold=s" => \$threshold,
		      "data_threshold=s" => \$threshold_data_part);

#use defaults if arguments are not specified
if ($alarm eq "") {
	$alarm  = 100;
}

if ($threshold eq "") {
	$threshold = 95;
}

if ($threshold_data_part eq "") {
	$threshold_data_part = 75;
}

########################
# READ PARTITION STATUS
########################
foreach $partition(`df -h`)
{
	chomp($partition);
 # print("$partition\n");
	### GET COLUMN HEADER ###
	$header = $partition if $header eq "";

	### READ VALID PARTITION ONLY ###
	next unless $partition =~ /^\s+\d+/;
	#next if     $partition =~ /(\/archives\-nas)/i;

	### CHECK FOR UTILIZATION ###
	my (@dummy) = split /\s+/, $partition;
	  $dummy[4] =~ s/\%//;
    	if ( $dummy[5] eq "/apps/exensio_data" )
	{
		$details = $partition if $dummy[4] > $threshold_data_part;
		$alarm   = $threshold_data_part;
	}
	else
	{
		$details = $partition if $dummy[4] > $threshold;
		$alarm   = $threshold;
	}

	##############
	# SAVE RESULT
	##############
	if ($details ne "")
	{
		my ($dummy, $size, $used, $avail, $use, $mounted) = split /\s+/,$details;
			$body 	    .=	"<tr>"
						.	    "<td nowrap>$size</td>"
						.	    "<td widtd='20px'></td>"
						.	    "<td nowrap>$used</td>"
						.	    "<td widtd='20px'></td>"
						.	    "<td nowrap>$use</td>"
						.	    "<td widtd='20px'></td>"
						.	    "<td nowrap>$mounted</td>"
						.	    "<td widtd='20px'></td>"
						.	    "<td nowrap>>$alarm%</td>"
						.	    "<td widtd='20px'></td>"
						.	"</tr>";
		$details = "";
	}
}

###################################################
# REPORT PARTITION/S ABOVE THE SPECIFIED THRESHOLD
###################################################
if ($body ne "")
{
	   $hostname 	= uc($hostname);

	   $body    = "<!DOCTYPE html>"
                    . "<html>"
                    . "<body>"
                    . "<table border='0' cellpadding='3px'>"
                    .    "<tr>"
                    .       "<th nowrap>Size</th>"
                    .       "<th width='20px'></th>"
                    .       "<th nowrap>Used</th>"
                    .       "<th width='20px'></th>"
                    .       "<th nowrap>Use%</th>"
                    .       "<th width='20px'></th>"
                    .       "<th nowrap>Mounted on</th>"
                    .       "<th width='20px'></th>"
                    .       "<th nowrap>Alarm%</th>"
                    .       "<th width='20px'></th>"
                    .    "</tr>"
		    .     $body
                    . "</table>"
                    . "</body>"
                    . "</html>";


	my $msg = MIME::Lite->new
        (
		Subject => "WARNING!!! $hostname\'s Disk Partition(s) Over Utilized",
                From    => "dpower\@$hostname\.onsemi.com",
                To      =>  $email,
                Type    => 'text/html',
                Encoding =>'base64',
                Data    =>  $body
	);
        $msg->send();

	### PRINT REPORT ###
	#print "$header\n$details\n";

}

exit 0;
