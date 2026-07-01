#! /apps/exensio/pdf/exn41/bin/perl_db
##! /usr/bin/perl
#
# DATE       WHO            COMMENTS
# ---------- -------------- --------------------------------
# 09/29/2012 Ben Rommel Kho Author
# 11/09/2015 Ben Rommel Kho Adjusted for Exensio
#
#
# Function: Display status of reloaded data.
#
#


###############
# LOAD MODULES
###############
require "init.pl";
use mod_routines;


#################################################################
# REDIRECT BACK TO THE MAIN PAGE ONCE SESSION COOKIE HAS EXPIRED
#################################################################
if (keys %{&read_cookie("envs")} == 0)
{
        print "Session values have expired. Redirecting back to the Main Page...<br>";
        &go_to_url("1_0_ask_lotid.cgi");
}


##############
# HTML HEADER
##############
print "<html>";
print "<head>";
print "<title> Exensio Web Dearchive Tool </title>";
print "<link rel='stylesheet' type='text/css' href='/ewb.css' />";
print "</head>",
      "<body>";


##################
# GET FILE STATUS
##################
my $refresh_page= "N";
my $host        = &read_cookie("host");
my $site_acct 	= &read_cookie("site_acct");
my $reload_time = &read_cookie("reload_time");
my $sel_envs    = &read_cookie("sel_envs");
my $monit_lotids= &read_cookie("monit_lotids");
my @results     = `${cgi_dir}/edbWebDearchive.pl -m $reload_time \"$sel_envs\" \"$monit_lotids\"`;


######################
# DISPLAY FILE STATUS
######################
print "<h1>RESTORING FILES<br> <font class=step>(Step 3 of 3)</font></h1>",
      "<center>",
      "<p id=status> </p>",
      "<table border=1>",
      "<tr>",
      "   <th> File Name     </th>",
      "   <th> File Size     </th>",
      "   <th> Reload Status </th>",
      "</tr>";

foreach my $result(sort @results)
{
	chomp($result);
	my ($fname, $fsize, $status, $status_color, $refresh_flag) = split /\:/, $result;
	$refresh_page = "Y" if $refresh_flag eq "Y";
	print "<tr>",
	      "<td align=left > $fname </td>",
	      "<td align=right> $fsize </td>",
	      "<td align=left > ",
	      "    <font color=$status_color>  $status </font>",
	      "</td>",
	      "</tr>";
}

### DISPLAY "BACK TO MAIN PAGE" BUTTON ###
if ($refresh_page eq "N")
{
	print "<tr>",
	      "<td colspan=3 align=middle>",
      	      input({-type   =>"button",
                     -class  =>"btn",
                     -name   =>"btnFinish",
                     -value  =>"Go back to the Main Page",
                     -onclick=>"location.href='1_0_ask_lotid.cgi'"}),
	      "</td>",
	      "</tr>";
}


print "</table>",
      "</center>";



################################################
# SET PAGE STATUS & ENABLE/DISABLE PAGE REFRESH
################################################
my $page_status = "";
if ($refresh_page eq "Y" && $monit_lotids ne "")
{
	### ENABLE PAGE REFRESH ###
	print "<META HTTP-EQUIV='Refresh' CONTENT='15'>" if $refresh_page eq "Y";

	### SET PAGE STATUS ###
	$page_status = "RESTORE PROCESS IS ONGOING. PLEASE WAIT...";
}
elsif ($refresh_page eq "N" && $monit_lotids ne "")
{
	### SET PAGE STATUS ###
        $page_status = "RESTORE PROCESS IS COMPLETE";
}
elsif ($monit_lotids eq "")
{
	$page_status = "MANUAL DATA RESTORE REQUEST HAS BEEN SENT TO YMS.Admins@onsemi.com.";
}

######################
# REFLECT PAGE STATUS
######################
print "<script>",
      "document.getElementById('status').innerHTML=\"<br><b><font color=blue>${page_status}</font></b>\"",
      "</script>";



#####################
# DISPLAY USER GUIDE
#####################
print<<"GUIDE";
   <br>
   <hr>
   <label>
   <b><u> Quick Guide: </u></b>
   <br>
   <br>
        <b>1.</b> This page will auto-refresh every 15 secs to reflect the latest restore status.
        <br>
        <b>2.</b> YMS data loading engineer will get notified whenever there's a restore failure.
        <br>
        <b>3.</b> If you encounter issues or have questions, please contact
		  <font color=blue>${support_team}</font>.
GUIDE


print "</body>";
print end_html;
