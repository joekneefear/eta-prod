package PDF::Util::Utility;

use strict;
use Exporter 'import';
use File::Find;
use File::Copy;
use IO::Handle;
use IPC::Open3;
use Cwd;
use Carp;

our @EXPORT = qw/doUncompress doCompress doUnzip doUnzipA/;
our $VERSION="1.0";


###############################
# Uncompress a file
###############################
sub doUncompress
{
        my $file = shift;

        my @values;

        return $file if($file !~ /\.Z$|\.gz$/i);

        my $pid = open3(\*GZIP_IN, \*GZIP_OUT, \*GZIP_ERR, "/usr/bin/gzip -vdf $file");
        waitpid( $pid, 0 );
        while(<GZIP_ERR>)
        {
                @values = split/\s+/;
        }
        close GZIP_IN;
        close GZIP_OUT;
        close GZIP_ERR;

        return $values[$#values];
}

###############################
# Compress a file
###############################
sub doCompress
{
        my $file = shift;

        my @values;

        return $file if($file =~ /\.Z$|\.gz$/i);

        my $pid = open3(\*GZIP_IN, \*GZIP_OUT, \*GZIP_ERR, "/usr/bin/gzip --force -v $file");
        waitpid( $pid, 0 );
        while(<GZIP_ERR>)
        {
                @values = split/\s+/;
        }
        close GZIP_IN;
        close GZIP_OUT;
        close GZIP_ERR;

        return $values[$#values];
}

###############################
# Unzip a file
###############################
sub doUnzip
{
        my $file = shift;
        my $options = shift;
        my $quiet = "";
        if ( defined( $options ) && $options == "quiet" )
        {
                $quiet = "> /dev/null";
        }
        my $orig_dir = getcwd;
        my $indx = rindex($file, "\/");
        my $dir = ($indx == -1) ? "." : substr($file,0,rindex($file,"\/") + 1);

        my @vals = ();
        if(-e $file && $file =~ /\.zip$/i )
        {
                my $zip_status = system("/usr/bin/zipinfo $file $quiet");

                return @vals if($zip_status != 0);

                chdir($dir);
                open(UNZIP, "unzip -j -o $file |");

                while(<UNZIP>)
                {
                        next if /^\s*Archive\:/i;

                        my ($junk,$filename) = split/\:\s+/;
                        push @vals, $dir.$filename;
                }
                close UNZIP;
        }
        chdir($orig_dir);

        #return @vals;
        return $vals[$#vals];
}

sub doUnzipA
{
        my $file = shift;
        my $options = shift;
        my $quiet = "";
        if ( defined( $options ) && $options == "quiet" )
        {
                $quiet = "> /dev/null";
        }
        my $orig_dir = getcwd;
        my $indx = rindex($file, "\/");
        my $dir = ($indx == -1) ? "." : substr($file,0,rindex($file,"\/") + 1);

        my @vals = ();
        if(-e $file && $file =~ /\.zip$/i )
        {
                my $zip_status = system("/usr/bin/zipinfo $file $quiet");

                return @vals if($zip_status != 0);

                chdir($dir);
                open(UNZIP, "unzip -j -o $file |");

                while(<UNZIP>)
                {
                        next if /^\s*Archive\:/i;

                        my ($junk,$filename) = split/\:\s+/;
                        push @vals, $dir.$filename;
                }
                close UNZIP;
        }
        chdir($orig_dir);

        return \@vals;
        #return $vals[$#vals];
}

1;

