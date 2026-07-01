#!/usr/bin/env perl_db

use Net::SSH::Perl;
use Data::Dumper;
use Config::Tiny;
use File::Copy;

my $host = 'hquxewb02p.fairchildsemi.com';     #Or just IP Address
my $user = 'edbmgr';            #Or just username
my $pass = 'milkshak3';
my $cmd = 'find -L /archives -maxdepth 1 -name "edb*" ! -name edbmft ! -name "*.*" -type d -print | cut -d\/ -f3';
my %envs = {};
my $Config = Config::Tiny->new();
my $confFile = $ENV{DPSCRIPT}."/dearchive/env.conf";

##############################
## SCAN ENVS FROM ARCHIVES DIR
###############################
if(-e $confFile) {
  unlink $confFile;
}
open(FH, '>', $confFile) or die $!;
print(FH "[envs]\n");
# my $ssh = Net::SSH::Perl->new($host, options => [ "MACs +hmac-sha1" ]);
# $ssh->login($user, $pass);
# my ($out, $err, $exit) = $ssh->cmd($cmd);
#my $out = `find -L /archives -maxdepth 1 -name "edb*" ! -name edbmft ! -name "*.*" -type d -print | cut -d\/ -f3`
my $out = `find -L /archives -maxdepth 1 -name "edb*" ! -name edbmft ! -name "*.*" -type d -print | cut -d\/ -f3`;
print "==>>>$out<<<===", "\n"; #exit 1;
my @sites = split("\n", $out);
#print "$envs[0]||$envs[1]||$envs[2]||$envs[3]||$envs[4]\n";
foreach my $site (@sites) {
  print "=>$site\n";
  chdir "/archives/${site}";
  my $cmd = "ls /archives/${site} | grep -v sybdump";
	#my $ssh = Net::SSH::Perl->new($host, options => [ "MACs +hmac-sha1" ]);
	#$ssh->login($user, $pass);
	#my ($out, $err, $exit) = $ssh->cmd($cmd);
 # my $out = `ls /archives/${site} | grep -v sybdump`;
  my $out = `/bin/find . -maxdepth 1 -type d | cut -d/ -f2`;
	my @envs = split("\n", $out);
  foreach my $env(@envs) {
    #print "ENV=$env||SITE=$site\n";
    my $cmd = "ls /archives/${site}/${env} | egrep '^[12][0-9][0-9][0-9]\$'";
    #$ssh->login($user, $pass);
  	#my ($out, $err, $exit) = $ssh->cmd($cmd);
    my $out = `ls /archives/${site}/${env} | egrep '^[12][0-9][0-9][0-9]\$'`;
  	my @years = split("\n", $out);
    @arch_years = sort {$a<=>$b} @years;
    my $start_year = $arch_years[0];
    my $end_year   = $arch_years[$#arch_years];
    chomp($start_year);
    chomp($end_year);

    ########################
    # STORE ENV INTO A HASH`
    ########################
    if ($#arch_years > -1)    {
      #$envs{$env} = "${site}:${start_year}:${end_year}";
      #$Config->{newsection} = { this => 'that' }; # Add a section
      my $value = "$env=${site}:${start_year}:${end_year}";
      #$Config->{'envs'} = {$env => $value};
      #$Config->write($confFile);
      print FH $value;
      print FH "\n";

    }

  }

	#my $ssh = Net::SSH::Perl->new($host, options => [ "MACs +hmac-sha1" ]);

}
#print Dumper(\%envs);
close(FH);

my $reloaderPath = "/apps/exensio_data/xfcs-reloader/env.conf";
print "Copying $confFile to $reloaderPath...\n";
copy($confFile, $reloaderPath) or warn "Could not copy $confFile to $reloaderPath: $!";

exit 0;
