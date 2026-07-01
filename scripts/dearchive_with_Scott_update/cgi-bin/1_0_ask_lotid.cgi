#!/apps/exensio/pdf/exn41/bin/perl_db
##!/usr/bin/env perl_db
##! /usr/bin/perl
#
# DATE        WHO            COMMENTS
# ----------  -------------- ---------------------------------------------
# 09/06/2012  Ben Rommel Kho Author
# 10/11/2012  Ben Rommel Kho Modified to dynamically detect/assign cgi dir
# 02/05/2013  Ben Rommel Kho Removed "All" year option. Fixed year display bug
# 02/06/2013  Ben Rommel Kho Require "Username". Disable buttons during lot search
# 02/08/2013  Ben Rommel Kho Fixed bug re storing of username to cookie
# 10/01/2015  Gilbert Miole  Added button to download search result
# 10/26/2015  Gilbert Miole  Commented the download button and modified for YMS migration
# 11/05/2015  Ben Rommel Kho Adjusted for Exensio
#
#


###############
# LOAD MODULES
###############
require "init.pl";
use mod_routines;


############
# VARIABLES
############
my %pa       = %{&read_cookie("pa")};
my %envs     = %{&read_cookie("envs")};
my $disabled = "disabled";
my $pa_val   = param("cmboPlantArea")||&read_cookie("cmboPlantArea");



##############
# HTML HEADER
##############
#print "Content-type: text/html\n\n";
print "<html>";
print "<head>";
print "<title> Exensio Web Dearchive Tool </title>";
print "<link rel='stylesheet' type='text/css' href='/ewb.css' />";


#################################################################
# CREATE JAVASCRIPT-BASED "ENV_BEGIN_YR & ENV_END_YR" SWITCH CASE
#################################################################
my $cases      = "";
my $all_yr_min = "";
my $all_yr_max = "";
foreach my $env(split /\-/, $pa{$pa_val})
{
	$cases .= "case \"$env\":";
	$cases .= "begin_yr=$envs{$env}{YR_FROM} ;";
	$cases .= "end_yr  =$envs{$env}{YR_TO}   ;";
	$cases .= "break;";

	$all_yr_min = $envs{$env}{YR_FROM} if $all_yr_min eq "" || $all_yr_min > $envs{$env}{YR_FROM};
	$all_yr_max = $envs{$env}{YR_TO}   if $all_yr_max eq "" || $all_yr_max < $envs{$env}{YR_TO};
}
if ($all_yr_min ne "" && $all_yr_max ne "")
{
	$cases  = "switch (eqpt) { $cases ";
	$cases .= "default:";
	$cases .= "begin_yr=$all_yr_min ;";
	$cases .= "end_yr  =$all_yr_max ;";
	$cases .= "break;";
	$cases .= "}";
}


############################
# CLIENT-SIDE SCRIPTS(START)
############################
print <<"JAVASCRIPT";

<script language="javascript">

    // ENABLE BUTTONS BY DEFAULT
    document.addEventListener("DOMContentLoaded", function() { 
       document.getElementById("btnNext").disabled = false;
       document.getElementById("btnSubmit").disabled = false;
       document.getElementById("btnReset").disabled = false;
    });

    //############
    // RESET FORM
    //############
    function reset_form()
    {
        if (confirm("Would you like to erase your entries and reset the form?") == true)
        {
            frmMain.action = "?Reset=Yes";
            frmMain.submit();
        }
    }

    //######################
    // CLEAR "RESULT" FIELD
    //######################
    function clear_result(i)
    {
        //### CLEAR RESULT FIELD ###
        document.getElementById("txtSearchResult" + i).value = "";

        //### CLEAR IF WILDCARD CHAR ONLY ###
        if (document.getElementById("txtLotID" + i).value == "*" || document.getElementById("txtLotID" + i).value == "?")
        {
            alert("Invalid search string '" + document.getElementById("txtLotID" + i).value + ".' Please correct.");
            document.getElementById("txtLotID" + i).value = "";
        }
    }

    //########################
    // CASCADE COMBOBOX VALUE
    //########################
    function cascade_value(strComboName,intSeq)
    {
        var idx = document.getElementById(strComboName + intSeq).selectedIndex;
        var val = document.getElementById(strComboName + intSeq).options[idx].value;
        var txt = document.getElementById(strComboName + intSeq).options[idx].text;
        if (confirm("Would you like to set all succeeding comboboxes' value to '" + txt + "'?") == true)
        {
            for (i=intSeq+1; i <= 10; i++)
            {
                document.getElementById(strComboName + i).selectedIndex = idx;
            }

	    if (strComboName == "cmboTester")
	    {
		reload_me();
            }
        }
    }

    //###############
    // SEARCH ARCHIVE
    //###############
    function search_archive()
    {
        var proceed = "no";
        var field = "";
        for (i=1; i <= 10 ; i++)
        {
            //field = frmMain("txtLotID"+i).value();
            field = document.getElementById("txtLotID"+i).value
            if (field != "")
            {
                proceed = "yes";
            }
        }

	// CHECK USERNAME
	//if (frmMain("txtUsername").value == "")
	if (document.getElementsByName("txtUsername").value == "")
	{
		alert("Please type your complete name in case of GOIT support");
		proceed = "out";
	}

	// CHECK IF LOT HAS BEEN PROVIDED
	if (proceed == "no")
        {
            alert("Please specify a lot number to search. Thank you.");
        }


        if (proceed == "yes")
        {
            if (confirm("Do you want to search the archive now?") == true)
            {
		// DISABLE BUTTONS
		document.getElementById("btnSubmit").disabled = true;
		document.getElementById("btnReset").disabled = true;
		document.getElementById("btnNext").disabled = true;

		// START LOT SEARCH
		frmMain.action = "1_1_search_archive.cgi";
		//frmMain.action = "test.cgi";
		frmMain.submit();
            }
        }
    }

    //##################################
    // RELOAD LOAD WITHOUT QUERY STRING
    //##################################
    function reload_me()
    {
        frmMain.action = "1_0_ask_lotid.cgi";
        frmMain.submit();
    }


    //#####################
    // UPDATE "YEAR" COMBO
    //#####################
    function update_year_list(seq)
    {
        var eqpt     = document.getElementById("cmboTester" + seq).value;
        var begin_yr = "";
        var end_yr   = "";
	var sel_yr   = document.getElementById("cmboYear" + seq).value;	//### GET USER SELECTED YEAR

	//### SET APPROPRAITE BEGIN_ARCH_YEAR AND END_ARCH_YEAR ###
	$cases

        //### REMOVE EXISTING VALUES ###
        for(j=document.getElementById("cmboYear" + seq).length; j >= 0; j--)
        {
            document.getElementById("cmboYear" + seq).remove(j);
        }

	//### ADD "ALL" OPTION ###
        //var yr = document.createElement('option')
        //    yr.text  = "All";
        //    yr.value = "All";
        //frmMain('cmboYear' + seq).add(yr)


        //### ADD ARCHIVE YEARS TO COMBO ###
	var i=0
        for(j=0; begin_yr <= end_yr; j++)
        {
            var yr = document.createElement('option')
                yr.text = begin_yr
                yr.value= begin_yr
            document.getElementById('cmboYear' + seq).add(yr)

	    //### GET SELECTED YEAR INDEX ###
	    if (sel_yr == begin_yr)
	    { i=j+1; }

            begin_yr++
        }

	//### SET COMBO TO SELECTED YEAR ###
	document.getElementById('cmboYear' + seq).selectedIndex=i;
    }

</script>
JAVASCRIPT
print "</head>";
print "<body>";

###########################
# CLIENT-SIDE SCRIPTS(END)
###########################



#####################
# REQUIRE IE BROWSER
#####################
#if ($ENV{HTTP_USER_AGENT} !~ /MSIE|Trident.*rv[ :]*11\./)
#{
#        print "<br><br>";
#        print "<center>PLEASE USE THE <u>INTERNET EXPLORER</u> BROWSER. THANK YOU.</center>";
#        exit 0;
#}


#############
# RESET FORM
#############
if ($qs{"Reset"} eq "Yes")
{

	%pa = ();
	&clear_cookies("pa","envs","cmboPlantArea");

	for (my $i=1; $i<=$max_rows; $i++)
	{
		### CLEAR ALL COOKIES ###
		&clear_cookies("txtLotID${i}","cmboTester${i}","cmboMonth${i}","cmboYear${i}","txtSearchResult${i}");
		### RESET PARAMETERS ###
		param("cmboPlantArea","");
		param("txtLotID${i}","");
		param("cmboTester${i}","");
		param("cmboMonth${i}","");
		param("cmboYear${i}","");
		param("txtSearchResult${i}","");
	}
}



#####################
# GET PLANT AND AREA
#####################
if (keys %pa == 0 ||keys %envs == 0)
{

        my @lines = ();
	my @rets = split /\n/, `${cgi_dir}/util_get_envs.pl`;
        push(@lines, @rets);

        my %envs    = ();
        foreach my $line(@lines)
        {
                #print "$line\n";
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

	### RESET ALL COOKIES AND PARAMS VALUES ###
	&clear_cookies("cmboPlantArea");
	param("cmboPlantArea","");

        for (my $i=1; $i<=$max_rows; $i++)
        {
                ### CLEAR ALL COOKIES ###
                &clear_cookies("txtLotID${i}","cmboTester${i}","cmboMonth${i}","cmboYear${i}","txtSearchResult${i}");
                ### RESET PARAMETERS ###
                param("cmboPlantArea","");
                param("txtLotID${i}","");
                param("cmboTester${i}","");
                param("cmboMonth${i}","");
                param("cmboYear${i}","");
                param("txtSearchResult${i}","");
        }

}


#############
# START FORM
#############
print "<form name='frmMain' method='POST'>";


##############
# START TABLE
##############
print "<h1>SEARCH FOR FILES IN THE EXENSIO ARCHIVES <br> <font class=step>(Step 1 of 3)</font></h1>";

############################
# DISPLAY PLANT & AREA LIST
############################
my $plant_prev = "";

print "<center>",
      "<table border=0 width='770px'>",
      "<tr><align=left valign=middle height=35px>",
      "<td align=left valign=middle height=35px>",
      "<strong><font style='font-size:13px'>PLANT & AREA:</strong> &nbsp;",
      "<select name='cmboPlantArea' id='cmboPlantArea' onchange='reload_me()' style='font-size:13px'>";

      ### PRINT "(REQUIRED)" ###
      print "<option selected style='color:red;font-style:italic;'>( REQUIRED )</option>" if $pa_val eq "";

foreach my $pa(sort keys %pa)
{
	my ($plant,$area) = split /\_/, $pa, 2;
	next if $plant eq "" || $area eq "";


	### PRINT PLANT OPTGROUP(START) ###
	if ($plant_prev eq "")
	{
		print "<optgroup label=$plant>";
                $plant_prev = $plant;
	}
	elsif ($plant ne $plant_prev)
	{
		print "</optgroup>";
                print "<optgroup label=$plant>";
                $plant_prev = $plant;
	}

	### PRINT AREA ###
	my $sel = ($pa_val eq $pa) ? "selected" : "";
	print "<option value=$pa ${sel}>$plant - $area</option>";

	### PRINT PLANT OPTGROUP(END) ###
	if ($pa eq $pa[$#pa])
        {
                print "</optgroup>";
        }
}
print "</select>",
      "</td>";


###############
# DISPLAY USER
###############
my $username = param("txtUsername")||&read_cookie("txtUsername");
   $username =~ s/\W+/\_/g;
   $username =~ s/\_+/\_/g;
   $username =~ s/^\_+|\_+$//g;
print "<td align=right>",
      "<font color=blue><b>YOUR NAME: </b></fonr> &nbsp; &nbsp;",
      textfield({-name =>"txtUsername",
	         -size =>40,
		 -title=>"Please type your name so that YMS Admin can support your request in case manual intervention is necessary.",
		 -value=>$username}),
      "</td>",
      "</tr>",
      "</table>";

### SAVE USERNAME AS COOKIE TO PC ###
&save_js_cookie("txtUsername", $username) if $username ne "";

### READ PC COOKIE VALUE INTO A FORM ELEMENT ###
&read_js_cookie("txtUsername","frmMain.txtUsername.value");




###############
# DISPLAY FORM
###############
print "<table border=1>",
      "<tr>",
         "<th> Seq           </th>",
         "<th> LotID         </th>",
         "<th> Tester Type   </th>",
         "<th> Month         </th>",
         "<th> Year          </th>",
         "<th> Search Result </th>",
      "</tr>";

for(my $i=1; $i<=$max_rows; $i++)
{
	################
	# DISPLAY "SEQ"
	################
	print "<tr>",
 	      "<td align=center> $i </td>";


	###################
	# DISPLAY "LOT ID"
	###################
	my $lotid = param("txtLotID".$i)||&read_cookie("txtLotID".$i);
	print "<td>",
	      input({-type    =>"text",
		     -name    =>"txtLotID". $i,
		     -id      =>"txtLotID". $i,
		     -value   =>"$lotid",
		     -onchange=>"clear_result($i)"}),
	      "</td>";


        ########################
	# DISPLAY "TESTER TYPE"
        ########################
   	my @envs    = split /\-/, $pa{$pa_val};
	my $env_def = param("cmboTester${i}")||&read_cookie("cmboTester${i}")||"All";
	print "<td>",
	      qq(<select id="cmboTester${i}" name="cmboTester${i}" onchange="update_year_list($i)">);
	if ($#envs > -1)
	{
		unshift(@envs, "All");
		foreach my $env(@envs)
		{
			my $sel = ($env eq $env_def) ? "selected" : "";
			my $val = ($env eq "All") ? "All" : $envs{$env}{TESTER};
        		print "<option value=$env ${sel}> $val </option>";
		}
		&save_cookie("cmboTester${i}");

	}
	print "</select>",
              "&nbsp;",
	      "<img src='../images/arrow3.jpg' height=13px width=10px onclick='cascade_value(\"cmboTester\",$i)'>",
 	      "</td>";
	&save_cookie("area_envs", $pa{$pa_val}) if $pa_val ne "";



	##################
	# DISPLAY "MONTH"
	##################
	my @mos    = qw(All Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	my $mo_def = param("cmboMonth${i}")||&read_cookie("cmboMonth${i}")||"All";
	print "<td>",
              qq(<select name="cmboMonth${i}">);
	foreach my $mo(@mos)
	{
		my $sel = ($mo eq $mo_def) ? "selected" : "";
		print "<option value=$mo ${sel}>$mo</option>";
	}
	print "</select>",
              "&nbsp;",
	      "<img src='../images/arrow3.jpg' height=13px width=10px onclick='cascade_value(\"cmboMonth\",$i)'>",
              "</td>";



	#################
	# DISPLAY "YEAR"
	#################
	$envs{"All"}{YR_FROM} = $all_yr_min if $all_yr_min ne "";
	$envs{"All"}{YR_TO}   = $all_yr_max if $all_yr_max ne "";
	#my $yr_def = param("cmboYear${i}")||&read_cookie("cmboYear${i}")||"All";
	my $yr_def = param("cmboYear${i}")||&read_cookie("cmboYear${i}");
	my @yrs    = ();
	#push(@yrs, "All");
	foreach my $yr($envs{$env_def}{YR_FROM}..$envs{$env_def}{YR_TO}) {push(@yrs, $yr);}
	print "<td>",
	      "<select id=cmboYear${i} name=cmboYear${i}>";
	foreach my $yr (@yrs)
	{
		my $sel = ($yr eq $yr_def) ? "selected" : "";
		print "<option value=$yr ${sel}>$yr</option>";
	}
	print "</select>",
              "&nbsp;",
	      "<img src='../images/arrow3.jpg' height=13px width=10px onclick='cascade_value(\"cmboYear\",$i)'>",
	      "</td>";



	###################
	# DISPLAY "RESULT"
	###################
	my $result = param("txtSearchResult${i}")||&read_cookie("txtSearchResult${i}")||"";
	my $color  = ($result =~ /Obsoleted/i) ? "red" : "blaok";
	print "<td>",
	      input({-type    =>"text",
		     -name    =>"txtSearchResult".$i ,
		     -id      =>"txtSearchResult".$i ,
		     -value   =>$result,
		     -style   =>"color:$color",
		     -readonly=>true,
		     -size    =>"65"}),
	      "</td>",
	      "</tr>";


	########################################
	# ENABLE "NEXT" BUTTON IF DATA IS FOUND
	########################################
	$disabled="" if $result =~ /Raw|STDF/i;

}


##################
# DISPLAY BUTTONS
##################
print "<tr>",
         "<td colspan=6 align=center>",
            "<table border=0 width=100%>",
            "<tr>",
               "<td width=200px align=left>",
               input({-type   =>"reset",
                      -class  =>"btn",
		      -name   =>"btnReset",
		      -id     =>"btnReset",
		      -value  =>"Reset Form",
		      -onclick=>"reset_form()"}),
               "</td>",
               "<td align=right>",
	       input({-type   =>"button",
                      -class  =>"btn",
                      -name   =>"btnSubmit",
                      -id     =>"btnSubmit",
                      -value  =>"Search Archive",
                      -onclick=>"search_archive()"}),
	       "<input id='btnNext' type='button' class=btn name='btnNext'     value=' Next Step ' $disabled onclick=\"location.href='2_0_review_files.cgi'\">",
               "</td>",
            "</tr>",
	    "</table>",
        "</td>",
      "</tr>";



###########
# END FORM
###########
print "</table>",
      "</center>",
      "</form>";


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

   <font color="red">* Note: </font> WorkStream data can not be reloaded via this page.
        Please contact your local YMS data loading engineer <br><br>

        <b>1.</b> You will be prompted for your name the first time you use this page.
                  This will be saved on your computer for up to 1 year.
        <br>
        <b>2.</b> Select the plant and area where the lot was tested.
        <br>
        <b>3.</b> Type the lot number to search in the LotID field. The use of wildcard
                  char is permitted, use a "<font color=red>?</font>" to match any single
                  char or "<font color=red>*</font>" for multiple chars
                  ( e.g. C<font color="red">?</font>23456789 & C<font color="red">*</font>456789).
                  There's no need to enclose the lotid with asterisk. The search script will enclose
                  it automatically (e.g.*C?23456789*).
        <br>
        <b>4.</b> Select the Tester Type, Month and Year the lot was tested.  You can select "ALL" in
                  the Tester, Month or Year field if this information is unknown.  Selecting "ALL"
                  will increase wait times.
        <br>
        <b>5.</b> Press the "Search Archive" button to start the archive search.  The results of the
                  search are displayed in the "Search Results" field.
        <br>
        <b>6.</b> Makes changes as desired or press the "Next Step" button.
        <br>
        <b>7.</b> If you encounter issues or have questions, please contact <font color=blue>${support_team}</font>.
   </label>
GUIDE

print end_html;
