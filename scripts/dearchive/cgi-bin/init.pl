#!/apps/exensio/pdf/exn41/bin/perl_db
##! /usr/bin/perl
#
#
# DATE        WHO	    COMMENTS
# ----------  -------------- ---------------------------------------------
# 09/10/2012  Ben Rommel Kho Author
# 10/11/2012  Ben Rommel Kho Modified to dynamically detect/assign cgi dir
# 10/18/2012  Ben Rommel Kho Detect whether to use prod or dev server
# 10/26/2015 Gilbert Miole  Migrated to YMS Server
# 11/05/2015  Ben Rommel Kho Adjusted for Exensio
# 1/10/2021   jgarcia changed shebang and hostname
#
#

###############
# LOAD MODULES
###############
use CGI qw(:standard);
use CGI::Session;
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Net::SMTP;
use MIME::Lite;
use File::Basename;
use Cwd;

###################
# GLOBAL VARIABLES
###################
our $server       = (`hostname`=~/usaz15ls082/) ? "usaz15ls082@onsemi.com" : "usaz15ls081@onsemi.com";
our $dpower_id    = "dpower";
our $max_rows     = 10;
our %qs           = &qs_to_hash if $ENV{QUERY_STRING} ne "";
our $support_team = "<b>IT CIM YQS DataIntegration <IT-CIM-YQS-DataIntegration@onsemi.com></b>";
our $cgi_dir      = Cwd::abs_path(dirname($0));



################
# ENABLE COOKIE
################
our $cookie = CGI::Session->new();
print $cookie->header();
