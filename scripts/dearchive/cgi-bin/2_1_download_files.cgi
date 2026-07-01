#! /apps/exensio/pdf/exn41/bin/perl_db
##! /usr/bin/perl
#
# DATE       WHO            COMMENTs
# ---------- -------------- ---------------------------------------------
# 11/11/2015 Ben Rommel Kho Author
#
#
# PURPOSE: Download selected files
#

###############
# LOAD MODULES
###############
use CGI qw(:standard);
use CGI::Session;
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use mod_routines;



##################
# CREATE ZIP FILE
##################
my $files     = param("txtSelFiles");
my $zip_name  = "Exensio_Files_" . time . ".zip";
my $zip_file  = "/apps/exensio_data/tmp/${zip_name}";
my $ret       = `/usr/bin/zip -j $zip_file $files`;
if (! -e $zip_file)
{
        print "Zipping of files failed. Please try again<br>";
        exit 0;
}

#########################
# PRINT OUT FILE CONTENT
#########################
print "Content-Type:application/zip; name=\"$zip_name\"\r\n";
print "Content-Disposition: attachment; filename=\"$zip_name\"\r\n\n";
open( FILE, "<$zip_file" );
binmode FILE;
read(FILE, $buffer, (stat("$zip_file"))[7]);
print $buffer;
close(FILE);


##################
# DELETE ZIP FILE
##################
unlink $zip_file;
