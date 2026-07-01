#!/usr/bin/perl
#
# Date		Who		Remarks
# 06-Feb-2018 	Eric		initial release
#
# Function: Reprocess files in ReworkFiles directory and move to NotProcessed if x days old
#

use strict;
use File::Copy;
use File::Basename;
use Getopt::Long qw/:config ignore_case auto_help/;

my $mv_age = "";

my $result = GetOptions (
		"mvage=i" => \$mv_age,
	);

if ($mv_age eq "") {
        die "\nUsage: reprocessed_reworkfiles_dir.pl -mvage=<file age to move to notprocessed dir>"."\n";
}
	
# Main Routine
&scan_reworkfiles_dir;

exit 0;

sub scan_reworkfiles_dir {
	foreach my $rwk_dir (`find /data -type d -name "ReworkFiles"` ) {
		chomp $rwk_dir;
		next if $rwk_dir =~ /ft_tmt/i;  # skip FT TMT's has separate process
		
		my $stg_dir = dirname $rwk_dir;
		my $npr_dir = "$stg_dir/NotProcessed";
		system "mkdir $npr_dir" if ! -e $npr_dir;

		foreach my $rwk_file(`find $rwk_dir -maxdepth 1 -type f `) {
			chomp $rwk_file;
			my $base_fn = basename $rwk_file;
			my $file_age = -M $rwk_file;
			
			if ( $file_age > $mv_age) {
				move($rwk_file, "${npr_dir}/${base_fn}");
			}
			else {
				move($rwk_file, "${stg_dir}/${base_fn}");
			}
		}
	}
}
