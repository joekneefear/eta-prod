#! /apps/exensio/pdf/exn41/bin/perl_db
##! /usr/bin/perl
#
# DATE       WHO            COMMENTS
# ---------- -------------- ---------------------------------------------
# 09/19/2012 Ben Rommel Kho Author
# 10/11/2012 Ben Rommel Kho Modified to dynamically detect/assign cgi dir
# 02/06/2012 Ben Rommel Kho Modified "Username" sanization method.
# 10/26/2015 Gilbert Miole  Modified for YMS migration
# 11/05/2015 Ben Rommel Kho Modified for Exensio
#


###############
# LOAD MODULES
###############
require "init.pl";
use mod_routines;



#################
# DISPLAY STATUS
#################
#print "Searching for lot data in archive...<br>";

#print "Content-type: text/html\n\n";
print "<html>";
print "<head>";
print "<title> Exensio Web Dearchive Tool </title>";
print "<link rel='stylesheet' type='text/css' href='/ewb.css' />";
#print "<script src=../https://code.jquery.com/jquery-3.5.0.js"></script>';
#print "<script src='../js/jquery-3.6.0.min.js'></script>";
print "</head>";
print "<body>";
#print '<table width="1200px"><td id="searching" >   <img id="loading-image" src="../images/spinner.gif" alt="Searching lot in archive..." /></td></th></table>';
print "Searching Lot/s from archive..";
print '<div id="searching"> <img id="loading-image" style="padding-left:170px;" src="../images/searching.gif" alt="Searching lot in archive..." /> </div>';
#print '<div > <img src="../images/Search_Animation.gif" style="padding-left:100px;" alt="Searching lot in archive..." /> </div>';
#print '<div class="loader">Loading...</div>';
#print '<div class="loader">Loading...</div>';
#print '<script src="../js/jquery-3.6.0.min.js"></script>';
#print '<div id="coverScreen"  class="LockOn"></div>';
# print<<"JS";
# $('body').append('<div style="" id="loadingDiv"><div class="loader">Loading...</div></div>');
# $(window).on('load', function(){
#   setTimeout(removeLoader, 2000); //wait for page load PLUS two seconds.
# });
# function removeLoader(){
#     $( "#loadingDiv" ).fadeOut(500, function() {
#       // fadeOut complete. Remove the loading div
#       $( "#loadingDiv" ).remove(); //makes page more lightweight
#   });
# }
# JS

#print '<table > <tr> <th><div id="loading"> <img id="loading-image" src="../images/5.gif" alt="Loading..." /></div></th> </tr></table>';
# print "<<HTML";
#   <html>
#   <head>
#   <title>Page Title</title>
#   </head>
#   <body>
#
#   <h1>This is a Heading</h1>
#   <p>This is a paragraph.</p>
#
#   </body>
#   </html>
# HTML


############
# VARIABLES
############
my %envs           = %{&read_cookie("envs")};
my $host           = "";
my $site_acct      = "";
my $param          = "";
my %lot            = ();
my $total_stdf_cnt = 0;
my $total_raw_cnt  = 0;


###########################################
# RESET "DATA SELECTED & EXCLUDED" COOKIES
###########################################
&clear_cookies("data_selected","data_excluded");


##################################
# SAVE SEARCH CRITERIA TO COOKIES
##################################
my $username =  param("txtUsername");
   $username =~ s/\W+/\_/g;
   $username =~ s/\_+/\_/g;
   $username =~ s/^\_+|\_+$//g;
&save_cookie("txtUsername"  , $username) if $username ne "";
&save_cookie("cmboPlantArea", param("cmboPlantArea"));
for(my $i=1; $i<=$max_rows; $i++)
{
	##############
	# CLEAN LOTID
	##############
	my $tmp_lotid = param("txtLotID${i}");
	   $tmp_lotid =~ s/\s//g;		   # REMOVE SPACES
	   $tmp_lotid =~ s/^[\*\?]+|[\*\?]+$//g;   # REMOVE LEADING/TRAILING WILD CHARS
	   $tmp_lotid =~ s/([\?\*])/\\$1/g;	   # ESCAPED IN-BETWEEN WILD CHARS


	############################
	# SAVE LOT DETAILS TO COOKIE
	############################
	if ($tmp_lotid ne "")
	{
		### SAVE CLEANED LOTID BACK TO PARAM ###
		param("txtLotID${i}", $tmp_lotid);

		### SAVE TO COOKIE ###
		&save_cookie("txtLotID${i}"       , $tmp_lotid);
		&save_cookie("cmboTester${i}"     , param("cmboTester${i}"));
		&save_cookie("cmboMonth${i}"      , param("cmboMonth${i}"));
		&save_cookie("cmboYear${i}"       , param("cmboYear${i}"));
		&save_cookie("txtSearchResult${i}", param("txtSearchResult${i}"));
	}
	#######################################
	# IF NO LOTID, CLEAR RESPECTIVE COOKIES
	#######################################
	else
	{
		&clear_cookies("txtLotID${i}");
		&clear_cookies("cmboTester${i}");
		&clear_cookies("cmboMonth${i}");
		&clear_cookies("cmboYear${i}");
		&clear_cookies("txtSearchResult${i}");
	}
}



##########################
# CREATE SCRIPT PARAMETER
##########################
for(my $i=1; $i<=$max_rows; $i++)
{
	next if param("txtLotID${i}") eq "";

	$param .= "," if $param ne "";
	$param .= param("txtLotID${i}") . ":";
	$param .= (param("cmboTester${i}") eq "All") ? &read_cookie("area_envs") . ":" : param("cmboTester${i}") . ":";
	$param .= param("cmboYear${i}") . ":";
	$param .= param("cmboMonth${i}");


	### GET ENV's HOSTNAME ###
	if ($host eq "")
	{
		my ($env,@dump) = split /\-/, &read_cookie("area_envs"); #if param("cmboTester${i}") eq "All";
		$host      = $envs{$env}{HOST};
		$site_acct = $envs{$env}{SITE_ACCT};
		&save_cookie("host", $host);
		&save_cookie("site_acct",$site_acct);
	}
}

#################
# SEARCH ARCHIVE
################
foreach my $line (split /\n/, `${cgi_dir}/edbWebDearchive.pl -s $site_acct "$param"`)
{
	chomp($line);
	my (@dummy) = split /\|/, $line;
	my $lotid   = $dummy[0];
	if ($dummy[1] eq "db_status")
	{
		### FORMAT: LOTID|DATA_TYPE|DB_STATUS|RAW_CNT|STDF_CNT ###
		$lot{$lotid}{DB_STATUS} = $dummy[2];
		$lot{$lotid}{RAW_CNT}   = $dummy[3];
		$lot{$lotid}{STDF_CNT}  = $dummy[4];

		### TOTAL FILE COUNT ###
		$total_raw_cnt  += $dummy[3];
		$total_stdf_cnt += $dummy[4];
	}
	elsif ($dummy[1] eq "raw")
	{
		### FORMAT: LOTID|DATA_TYPE|FILENAME:FILESIZE ###
		push(@{$lot{$lotid}{RAW}}, $dummy[2]);
	}
	elsif ($dummy[1] eq "stdf")
	{
		### FORMAT: LOTID|DATA_TYPE|FILENAME:FILESIZE ###
		push(@{$lot{$lotid}{STDF}}, $dummy[2]);
	}

	### SET "Y" IF ENV IS ACTIVE. OTHERWISE, "N" FOR OBSOLETED ###
	if ($dummy[1] =~ /raw|stdf/i)
	{
		my ($dump1, $arch, $plant, $env, $dump2) = split /\//, $dummy[2], 5;
    #print "$dump1 || $arch || $plant || $env || $dump2\n";
		$lot{$lotid}{ACTIVE} = $envs{$env}{ACTIVE};
	}
}
&save_cookie("total_raw_cnt" ,$total_raw_cnt);
&save_cookie("total_stdf_cnt",$total_stdf_cnt);


#################################
# SAVE "SEARCH RESULT" TO COOKIE
#################################
for(my $i=1; $i<=$max_rows; $i++)
{
        next if param("txtLotID${i}") eq "";

	my $lotid  = param("txtLotID${i}");
	my $result = "";
	if ($lot{$lotid}{RAW_CNT} > 0 || $lot{$lotid}{STDF_CNT} > 0)
	{
		$result  = "Found ";
		$result .= $lot{$lotid}{RAW_CNT} . " raw files"    if $lot{$lotid}{RAW_CNT}  > 0;
		$result .= " & " if $lot{$lotid}{RAW_CNT}  > 0 && $lot{$lotid}{STDF_CNT} > 0;
		$result .= $lot{$lotid}{STDF_CNT} . " stdf files." if $lot{$lotid}{STDF_CNT} > 0;
	        $result .= ". $lot{$lotid}{DB_STATUS}"             if $lot{$lotid}{DB_STATUS} ne "";
		$result .= ". Obsoleted. GOIT to manual restore."  if $lot{$lotid}{ACTIVE} eq "N";


		### SET "REASON" FOR INACTIVE LOT ###
		if ($lot{$lotid}{DB_STATUS} =~ /Undefined/i)
		{
			$lot{$lotid}{ACTIVE} = "N";
			$lot{$lotid}{REASON} = "Undefined DB or DB server";
		}
		else
		{
			$lot{$lotid}{REASON} = "Obsoleted env";
		}
	}
	else
	{
		$result = "No match found.";
	}
	&save_cookie("txtSearchResult${i}", $result);
}
&save_cookie("search_result" ,\%lot);

#print '<script src="https://ajax.googleapis.com/ajax/libs/jquery/2.1.1/jquery.min.js"></script>';
#print '<script src="../js/jquery-3.6.0.min.js" </script>';
#print '<script> $(window).on('load', function () { $("#coverScreen").hide(); }); </script>';
print<<"JS";
  <script>
    $(window).load(function() {
      $('#loading').hide();
    });
  </script>
JS
print "</body>";
print "</html>";
#######################
# GO BACK TO MAIN PAGE
#######################
&go_to_url("1_0_ask_lotid.cgi");

1;
