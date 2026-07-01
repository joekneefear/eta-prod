#! /apps/exensio/pdf/exn41/bin/perl_db
##!/usr/bin/perl
#
# DATE       WHO            COMMENTS
# ---------- -------------- -----------------------------------
# 09/08/2012 Ben Rommel Kho Author
# 11/07/2012 Scott Boothby  Changed lookup method for directories in archive to avoid finding any junk files/dirs
# 12/20/2012 Ben Rommel Kho Fixed translate_env_names bug
# 01/03/2013 Scott Boothby  Print envs with no tester name.
# 02/05/2013 Ben Rommel Kho Excluded obsolete envs
# 03/11/2013 Rodney Cyr    Include searching symbolic links for site list; exclude backup site folder names with '.'.
# 01/19/2021 jgarcia       change shebang
#
#
# Purpose           : Scan & return valid archive envs and year range
# Return Data Format: env_name:hostname:plant:area:tester:site:arch_yr_start:arch_yr_end:active_flag
#
use Net::SSH::Perl;
use Config::Tiny;
############
# VARIABLES
############
my %envs          = ();
my @sites         = ();
my $arch_dir      = "/archives";
my $data_dir      = "/apps/exensio_data/data";
my $host          = `hostname`;
my $config = Config::Tiny->read('/export/home/dpower/project/scripts/dearchive/env.conf');
chomp($host);

# my $host = 'hquxewb02p.fairchildsemi.com';     #Or just IP Address
# my $user = 'edbmgr';            #Or just username
# my $pass = 'milkshak3';
# my $cmd = 'find -L /archives -maxdepth 1 -name "edb*" ! -name edbmft ! -name "*.*" -type d -print | cut -d\/ -f3';
# my $ssh = Net::SSH::Perl->new($host, options => [ "MACs +hmac-sha1" ]);
# $ssh->login($user, $pass);
# my ($out, $err, $exit) = $ssh->cmd($cmd);
# #print "==>>>$out<<<===", "\n";
# my @sites = split("\n", $out);

#print "Im here\n";
foreach my $section (keys %$config) {
	#print "[$section]";
	foreach my $key (keys %{$config->{$section}}) {
		#print "$key = $config->{$section}->{$key}";
		$envs{$key} = $config->{$section}->{$key};
	}
}
##############################
# SCAN ENVS FROM ARCHIVES DIR
##############################
#&getEnvs($config);
#getEnvs($config);

#@sites = getSites($cmd);

#&get_envs_archives(@sites);

#&get_envs_archives(\@sites);


##########################################
# CHECK EACH ENV FOR CORRESPONDING DL ENV
# MARK "Y" IF PRESENT OR "N" FOR NONE
##########################################
&check_dl_env();


####################################
# TRANSLATE ENV NAME INTO FULL NAME
####################################
&translate_env_names();


##########################################
# RETURN LIST OF ENV NAMES TO RELOAD PAGE
##########################################
&print_env_names();

exit 0;

#<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< SUBROUTINES >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

sub getEnvs {
	my $config = shift;
	print "Im here2\n";
	foreach my $section (keys %$config) {
 		print "[$section]";
 		foreach my $key (keys %{$config->{$section}}) {
  		print "$key = $config->{$section}->{$key}";
			$envs{$key} = $config->{$section}->{$key};
 		}
	}
}

######################################
# GET ENV NAME AND ARCHIVE YEAR RANGE
######################################
# sub get_envs_archives
# {
# 	############
# 	# GET SITES
# 	############
# 	my $sites = shift;
# 	#print "@sites";

	#foreach my $site(`find -L $arch_dir -maxdepth 1 -name "edb*" ! -name edbmft ! -name "*.*" -type d -print | cut -d\/ -f3`)
# 	foreach my $site (@{$sites})
# 	{
# 		#chomp($site);
# 		#print "======$site\n";
#
# 		###########
# 		# GET ENVS
# 		###########
# 		#my @e = getEnvs($site);
# 		my $cmd = "ls /archives/${site} | grep -v sybdump";
# 		#my $ssh = Net::SSH::Perl->new($host, options => [ "MACs +hmac-sha1" ]);
# 		#$ssh->login($user, $pass);
# 		my ($out, $err, $exit) = $ssh->cmd($cmd);
# 		my @envs = split("\n", $out);
# 		#foreach my $env(`ls ${arch_dir}/${site} | grep -v sybdump`)
# 		foreach my $env (@envs)	{
# 			#chomp($ev);
#
# 			###########
# 			# SKIP WKS
# 			###########
# 			next if $env=~/wks/;
# 			next if $env=~/nlost\+found/;
# 			next if $env=~/result\.txt/;
#
# 			###################
# 			# GET ARCHIVE YEAR
# 			###################
# 			#my @arch_years = `ls ${arch_dir}/${site}/${env} | egrep '^[12][0-9][0-9][0-9]\$'`;
# 			#my @arch_years = getYears($env, $site);
# 			my $cmd = "ls /archives/${site}/${env} | egrep '^[12][0-9][0-9][0-9]\$'";
# 	    #$ssh->login($user, $pass);
# 	  	my ($out, $err, $exit) = $ssh->cmd($cmd);
# 	  	my @arch_years = split("\n", $out);
# 			   @arch_years = sort {$a<=>$b} @arch_years;
# 			my $start_year = $arch_years[0];
# 			my $end_year   = $arch_years[$#arch_years];
# 			chomp($start_year);
# 			chomp($end_year);
#
# 			########################
# 			# STORE ENV INTO A HASH
# 			########################
# 			if ($#arch_years > -1)
# 			{
# 				$envs{$env} = "${site}:${start_year}:${end_year}";
# 			}
# 		}
#
# 	}
#
# }


##########################################
# CHECK EACH ENV FOR CORRESPONDING DL ENV
# MARK "Y" IF PRESENT OR "N" FOR NONE
##########################################
sub check_dl_env
{

	foreach my $env(keys %envs)
	{
		#print "==$env";
		my ($site,)  = split /\:/, $envs{$env};
		my $flag     = "N";
		   $flag     = "Y" if -e "${data_dir}/${env}/Processed";
		$envs{$env} .= ":$flag";
	}
}


####################################
# TRANSLATE ENV_NAME INTO FULL NAME
####################################
sub translate_env_names
{

	foreach my $env(sort {$a<=>$b} keys %envs)
	{
		my ($site,)   = split /\:/, $envs{$env};
		my (@dummy)   = split /\_/, uc($env);
		my $plant     = "";			### E.G. CEBU, MAINE, ETC.
		my $area      = "";			### E.G. "FSCP - SORT", ETC.
		my $tester    = "";			### E.G. EAGLE, MCT, SEPROBE
		my $proc_steps= "AST|CSP|DEF|EPI|ET|EQP|FAB|FT|SUB|BMP|SORT";
		my $data_types= "AOI|APPE|CORR|CSP|DPAT|BMP|MRG|REL|WMAP";


		###################
		# SKIP LOADER ENVS (NEEDED???)
		###################
		#next if $env=~/${proc_steps}$/i;
		#next if $env=~/${data_types}$/i;


		######################
		# DETERMINE PLANT & AREA
		######################
		if ($site eq "edbfound")
		{
			### GET SUBCON NAME ###
			$plant = shift(@dummy);

			### REMOVE "SUBCON LOCATION" ###
			shift(@dummy);

			### REMOVE "FILE-FORMAT-CODE" ###
			pop(@dummy);

			### GET "PROC_STEP" OR "PROC_STEP + DATA_TYPE" ###
			$area  =     $dummy[0] if $dummy[0] ne "";
			$area .= "_".$dummy[1] if $dummy[1] ne "";
		}
		else
		{
			### PLANT ###
			$plant =  "FS" . shift(@dummy);
			$plant =~ s/($proc_steps)//i; 	### REMOVE PROC_STEP

			### PROCESS STEP ###
			$area      = $1;

			### REMOVE "FILE-FORMAT-CODE" ###
                        pop(@dummy);

			### GET "DATA_TYPE" ###
			$area .= "_".$dummy[0] if $dummy[0] ne "";
		}

		### TESTER ###
		(my $dump, $tester) = split /${area}_/i, uc($env);

		### UPDATE ENV WITH FULL NAME ###
		$envs{$env} = "${host}:${plant}:${area}:${tester}:" . $envs{$env};

	}
}

##########################################
# RETURN LIST OF ENV NAMES TO RELOAD PAGE
##########################################
sub print_env_names
{
	foreach $env(sort {$a<=>$b} keys %envs)
	{
#		next if $envs{$env}=~/\:\:/;
		print "${env}\:$envs{$env}\n";
		#print "${env}\:$envs{$env}\n" if $envs{$env} =~ /\:Y$/;		### 02/05/2013 EXCLUDED OBSOLETED ENVS
	}
}

sub getSites {
	#my $site = shift;
	my $cmd = shift;
	my $ssh = Net::SSH::Perl->new($host, options => [ "MACs +hmac-sha1" ]);
	$ssh->login($user, $pass);
	my ($out, $err, $exit) = $ssh->cmd($cmd);
	my @sites = split("\n", $out);
	return @sites;
}

sub getEnvs {
	my $site = shift;
	my $cmd = "ls /archives/${site} | grep -v sybdump";
	my $ssh = Net::SSH::Perl->new($host, options => [ "MACs +hmac-sha1" ]);
	$ssh->login($user, $pass);
	my ($out, $err, $exit) = $ssh->cmd($cmd);
	my @envs = split("\n", $out);
	return @envs;
}

sub getYears {
	my $env = shift;
	my $site = shift;
	#${arch_dir}/${site}/${env} | egrep '^[12][0-9][0-9][0-9]\$'
	my $cmd = "ls /archives/${site}/${env} | egrep '^[12][0-9][0-9][0-9]\$'";
	my $ssh = Net::SSH::Perl->new($host, options => [ "MACs +hmac-sha1" ]);
	$ssh->login($user, $pass);
	my ($out, $err, $exit) = $ssh->cmd($cmd);
	my @years = split("\n", $out);
	return @years;
}
