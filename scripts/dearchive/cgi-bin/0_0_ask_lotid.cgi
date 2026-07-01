#! /apps/exensio/pdf/exn41/bin/perl_db
##! /usr/bin/env perl_db
#
# DATE       WHO            COMMENTs
# ---------- -------------- ---------------------------------------------
# 5/31/2021  jgarcia initial.


##############
# LOAD MODULE
##############
require "init.pl";
use mod_routines;
use LWP::Simple;


#################
# DISPLAY STATUS
#################
#print "Restoring files from the archive...<br>";
print "<html>";
print "<head>";
print "<title> Exensio Web Dearchive Tool </title>";
print "<link rel='stylesheet' type='text/css' href='/ewb.css' />";
#print "<script src=../https://code.jquery.com/jquery-3.5.0.js"></script>';
print '<link rel="stylesheet" type="text/css" href="../css/loading-bar.css"/>';
print '<script type="text/javascript" src="../js/loading-bar.js"></script>';
#print "<script src='../js/jquery-3.6.0.min.js'></script>";


print "</head>";
print "<body>";
#print '<table width="1200px"><td id="searching" >   <img id="loading-image" src="../images/spinner.gif" alt="Searching lot in archive..." /></td></th></table>';
print "<div>Getting available data sources.  Please wait</div>";
print '<div id="searching"> <img id="loading-image" style="padding-left: 170px;" src="../images/spinner.gif" alt="Loading env..." /> </div>';
#print '<div  class="ldBar"  data-stroke="data:ldbar/res,  stripe(#ff9,#fc9,1)"></div>';

############
# VARIABLES
############
my %pa       = %{&read_cookie("pa")};
my %envs     = %{&read_cookie("envs")};;

if (keys %envs == 0) {
  my @lines = ();
	my @rets = split /\n/, `${cgi_dir}/util_get_envs.pl`;
	#print scalar(@rets);
  push(@lines, @rets);
  my %envs    = ();
 foreach my $line(@lines) {
   my ($env, $host, $plant, $area, $tester, $site_acct, $yr_from, $yr_to, $dl_flag) = split /\:/, $line;

                ##################################
                # ASSIGN UNIQUE "PLANT & AREA" ID
                ##################################
                my $key = "${plant}_${area}";
                if (!exists($pa{$key}))
                {
                        $pa{$key} = $env;
                }
                else
                {
                        $pa{$key} .= "-" . $env;
                }

                ########################
                # SAVE "ENVS" TO COOKIE
                ########################
                $envs{$env} =
                {
                        HOST      => $host,
                        TESTER    => $tester,
                        SITE_ACCT => $site_acct,
                        YR_FROM   => $yr_from,
                        YR_TO     => $yr_to,
                        ACTIVE    => $dl_flag,
                };

        }
        &save_cookie("pa"  ,\%pa);
        &save_cookie("envs",\%envs);
  }


&go_to_url("1_0_ask_lotid.cgi");
