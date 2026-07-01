#!/usr/bin/env perl_db
#
# 19-Jul-2018 Eric      : new
# 15-Aug-2018 Eric      : changed sender from dpower@onsemi.com to dpower@oruxymsetl01p.fairchildsemi.com
# 			: because it was frequently blocked by proofpoint
# 15-Aug-2018 Eric	: improved find command
# 11-Jul-2019 Rodney	: Changed monitored folder to .../Processed/Processed (another job was added to process files in .../Processed.
# 04-Feb-2020 Eric	: made email as argument
# 10-May-2021 jgarcia : modified to work on colo.
#
# Function:     Checks $REFERENCE_DATA/Processed/Processed folder for the existence of recent
#               *.mes files for site codes KLMI1, PAMI1 and MEMI1 that is at least
#               one *.mes for each site less than 2 hours old

use strict;
use Getopt::Long;

my $min = "";
my $notify = "N";
my $email = "";

GetOptions("min=s" => \$min, "email=s" => \$email);

if ($min eq "" || $email eq "") {
        print "Usage: <script> -min=<input minutes> -email=<email add>\n";
        exit 1;
}

my $hr   = int($min/60);
my @code = qw/KLMI1 PAMI1/;
my $ref_dir = "/apps/exensio_data/reference_data/Processed";
my $log = "The following site code have missing extracts:\n";

foreach my $site ( @code ) {
        #my $cmd = `find $ref_dir -iname "*_$site*.mes" -cmin -$min`;
	my $cmd = `find $ref_dir -maxdepth 2 -iname "*_$site*.mes" -newermt '$min minute ago'`;
        if ($cmd eq "") {
                $notify = "Y";
                $log .= "$site\n";
        }
}

if ($notify eq "Y") {
	print "No BIWMES extracts received since the last ${hr} hour(s)\n";
	email($log,$hr);
}
else {
        print "No missing BIWMES extract!\n";
}
exit 0;

sub email {
	my $log = shift;
	my $hr = shift;
        my $subj = "No BIWMES extracts received since the last ${hr} hour(s)";

	open (MAIL, "|mailx -s \"$subj\" $email");
	print MAIL "$log\n";
        close (MAIL);

}
