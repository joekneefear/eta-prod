#! /apps/exensio/pdf/exn41/bin/perl_db
##! /usr/bin/perl
#
# DATE       WHO            COMMENTs
# ---------- -------------- ---------------------------------------------
# 09/24/2012 Ben Rommel Kho Author
# 10/11/2012 Ben Rommel Kho Modified to dynamically detect/assign cgi dir
# 02/01/2013 Ben Rommel Kho Modified to log reload activity into ewb_statistics db
# 02/05/2013 Ben Rommel Kho Log "UNKNONW" if no email add provided
# 11/09/2015 Ben Rommel Kho Adjustd for Exensio
#
#

##############
# LOAD MODULE
##############
require "init.pl";
use mod_routines;
use LWP::Simple;


#################
# DISPLAY STATUS
#################
print "Restoring files from the archive...<br>";


############
# VARIABLES
############
my $host          = &read_cookie("host");
my $site_acct     = &read_cookie("site_acct");
my $data_type     = param("cmboType");
my $arch_proc     = ($data_type eq "RAW") ? "Convert" : "Load";
my %arch_envs     = ();
my $file          = "";
my $monit_lotids  = "";
my %search_result = %{&read_cookie("search_result")};
my %data_selected = %{&read_cookie("data_selected")};
my $reload_time   = "";
my $email_to      = "yms.admins\@fairchildsemi.com";
my $email_from    = &read_cookie("txtUsername");
my $email_subject = "Reload Page: Request to restore data from obsolete env";
my $email_body    = "";


#############################################
# EMAIL FILES TO RESTORE FROM OBSOLETED ENVS
#############################################
$obsEnvFound = 0;
foreach my $lotid (sort keys %data_selected)
{

        next if $data_selected{$lotid}{ACTIVE} eq "Y";
        $email_body .= "LOTID: $lotid\nISSUE: $search_result{$lotid}{REASON}\n";
        foreach my $file (@{$data_selected{$lotid}{$data_type}})
        {

        #       my ($name, $size) = split /\:/, $file;
        #       $name         =~ s/\.gz//;
                if($file ne "")
                {
                        $email_body .= "$file\n";
                        $obsEnvFound = 1;
                }
        }
        $email_body .= "\n";
}
&sendEmail($email_subject, $email_body, $email_to, $email_from) if $obsEnvFound == 1;



########################
# RELOAD SELECTED FILES
########################
foreach my $lotid(keys %data_selected)
{
	### RELOAD DATA FROM ACTIVE ENVS ###
	next if $data_selected{$lotid}{ACTIVE} eq "N";

	### GET LOTS TO MONITOR ###
	$monit_lotids .= ($monit_lotids eq "") ? $lotid : ":" . $lotid; 		
	
	### RELOAD FILES ###
	foreach my $data (@{$data_selected{$lotid}{$data_type}})
	{
		my $file = (split /\:/, $data)[0];	### GET FILENAME ONLY
		my $env  = (split /\//, $file)[3];   	### GET ENV FROM FULL PATH FILENAME      
		$arch_envs{$env} = 1;			### DETERMINE ENVS TO MONITOR

		### COPY FILES TO DESIGNATED DEARCHIVE FOLDER FOR MFT PUSH ###
		my $ret =  `${cgi_dir}/edbWebDearchive.pl -r $file`;
	
		### GET RELOAD TIME OF THE 1ST FILE ###
		$reload_time = $ret if ($reload_time eq "");
	}
}
$monit_lotids =~ s/([\?\*])/\\$1/g;		### ESCAPED WILD CHARS
&save_cookie("monit_lotids", $monit_lotids);
&save_cookie("reload_time" , $reload_time);


############################
# DETERMINE ENVS TO MONITOR
############################
my $sel_envs = join ":", keys %arch_envs;
&save_cookie("sel_envs", $sel_envs);

### DISABLED ON NOV 11,2015: TRIGGER MFT MANUAL PUSH ONLY ###
#get "http://${host}:8080/MFTServer-Dispatch/MFTDispatch/dearchive/${env}/${arch_proc}/${arch_pid}";


###########################################
# LOG RELOAD ACTIVITY TO EWB_STATISTICS DB
###########################################
#my $username  = &read_cookie("txtUsername")||"UNKNOWN";
#my $plantarea = &read_cookie("cmboPlantArea");
#my $filecnt   = keys %data_selected;
#system "${cgi_dir}/edbWebDearchive.pl -l \"$username\", \"$plantarea\", \"$filecnt\""; 


############################
# REDIRECT TO THE NEXT PAGE
############################
&go_to_url("3_0_monitor_files.cgi");
