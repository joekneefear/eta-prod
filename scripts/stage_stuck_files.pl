#!/usr/bin/env perl_db
#
# 01-Dec-2016 Eric	: create
# 09-Dec-2016 Eric	: added age command line argument
# 09-Dec-2016 Eric      : skip .scrap, wm_iff_nc files if already processed
# 13-Dec-2016 Eric	: change hrs arg to days_arg
# 21-Dec-2016 Eric	: fixed to capture day_arg.
# 06-Jun-2019 Eric	: changed email add domain to onsemi.com
#
# Function: Notifies stucked files in all staging directory

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use MIME::Lite;
use Getopt::Long;
use File::stat;
use Time::localtime;

no warnings qw/experimental::lexical_subs experimental::smartmatch/;

my $day_arg;
my $result = GetOptions ("age=i" => \$day_arg );

if ($day_arg eq "")
{
      die "Use: stage_stuck_files.pl -age=<age of file in days>"."\n";
}

#my $day_arg = $ARGV[0];
my @cfg_files = `find /home/dpower/project/load/Combined_cfg -type f -name "*.cfg"`;
my @stg_dirs  = ();
my @tmp_stg_dirs = ();

opendir (DIR, '/data') or die "Could not open directory: $!\n";
my @env_list = readdir(DIR);  # get env's

foreach my $file ( @cfg_files ) { #extract stage dir from cfg file
	#print "$file\n";
	open CFG, $file or die "Could not config file: $!\n";
	while ( my $line=<CFG>) {
		next if $line =~ /^\#/;
		next if $line =~ /fcs_cust/i;
		if ($line =~ /^\/data/i) {
			my @item = split /\:/, $line;
			push @tmp_stg_dirs, $item[0];
		}
	}		
	close (CFG);
	
}

@stg_dirs = uniq(@tmp_stg_dirs); #remove duplicate stage dir

my $cur_time = time();
foreach my $env ( @env_list ) {
	next if ($env =~ /\.|forJun|test|reference_data|naming|reloadlimit|fetch_log|lost|training|tmp|wait|OracleClient/i);
	#print "$env\n";
	my $cnt      = 0;
	my @listfile = ();
	foreach my $stg ( @stg_dirs ) {
		next if $stg !~ /$env/i;
		my @files = `find $stg -maxdepth 1 -type f -name "*.*"`;
		foreach my $file (@files) {
			$file = trim($file);
			next if ($stg =~ /stage\/Processed$|stage\_sandbox\/Processed$/i && $file =~ /\.limit/i);
			next if ($stg =~ /stage\/Processed$|stage\_sandbox\/Processed$/i && $file =~ /\.SPD_iff/i);
			next if ($stg =~ /stage\/Processed$|stage\_sandbox\/Processed$/i && $file =~ /\.scrap/i);
			next if ($stg =~ /stage\/Processed$|stage\_sandbox\/Processed$/i && $file =~ /\.wm_iff/i);
			next if ($file =~ /\.lock$/);
			my $file_tstamp = stat($file)->mtime;
                        my $file_age_mn = ($cur_time - $file_tstamp)/60;
                        my $file_age_dd = $file_age_mn/1440;   #convert min to day
                        #print "$day_arg\t$cur_time\t$file_age_dd\n";
                        if ($file_age_dd >= $day_arg) {	
				$cnt++;
				push @listfile, $file;
			}
		}
	}
	
	#send notification
	if ($cnt > 0) {
               &send_mail($env,$cnt,\@listfile);
        }	
	#last;
}

sub trim {
    my ($text) = @_;
    if ($text) {
    	$text =~ s/[\n\r]//gs;
        $text =~ s/^\s+//gs;
        $text =~ s/\s+$//gs;
        $text =~ s/\"$//gs;
        $text =~ s/^\"//gs;
        $text =~ s/[^\x09-\x7E]//gs;
    }
    return $text;
}

sub uniq {
    	my %seen;
    	grep !$seen{$_}++, @_;
}

sub send_mail {
	my $env      = shift;
	my $cnt      = shift;
	my $listfile = shift;
	   $env      = uc($env);
	my $subj     = "$env: FOUND $cnt STUCK FILE(S)";
	my $to       = "yms.admins\@onsemi.com";
	
	# list only the first 100 files
	if(scalar(@$listfile) > 100) {
		(@$listfile) = @$listfile[0..99];
	}

	open(MAIL, "|mailx -s \"$subj\" $to");
	foreach my $file (@$listfile) 
        {
        	print MAIL "$file\n";
       	}
	close(MAIL);
}
