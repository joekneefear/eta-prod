#! /usr/bin/env perl

use feature qw(say);
use strict;
use warnings;

# NOTES:
#
#  Source directory will be:
#    - "/archives-yms/data/bksort_eagle/STAGING"
#
#  Destination directory will be:
#    - "/archives-yms/data/bksort_eagle/PRODUCTION", or
#    - "/archives-yms/data/bksort_eagle/SANDBOX"
#
# Note that: "bksort_eagle" can change to another name like:
#  "szast_camstar" or "bkfb8_wks"
#
# DESCRIPTION:
#
# Archives all .gz files in source directory and puts them into .zip
# files which are written to the destination directory.
#
#
# REQUIREMENTS:
#
# - ZIP file should not be larger than 100 Mb
# - ZIP file should not contain more than 1000 files


use Data::Dumper;
use File::Basename qw(basename);
use File::Spec;
{
    my @sourcedirs = ('/archives-yms/data/szast_camstar2/historical_wait/PRODUCTION', '/archives-yms/data/szast_camstar2/historical_wait/SANDBOX');
    my @destdirs   = ('/archives-yms/data/szast_camstar2/historical/PRODUCTION', '/archives-yms/data/szast_camstar2/historical/SANDBOX');
    my $maxfiles  = 1000;
    my $maxsize = 10000000;
    for my $idx (0..$#sourcedirs) {
        my $src = $sourcedirs[$idx];
        my $dst = $destdirs[$idx];
        say "\nWorking on sourcedir: $src, destdir: $dst ..\n";
        my $zip = ZipDir->new(
            sourcedir => $src,
            destdir   => $dst,
            maxfiles  => $maxfiles,
            maxsize   => $maxsize,
        );
        $zip->init();
        $zip->get_files();
        $zip->start_new_archive();
        while ($zip->{cur_files_left} > 0) {
            $zip->add_file();
            if ($zip->{cur_num_arch_files} >= $zip->{maxfiles}) {
                $zip->start_new_archive();
            }
            elsif ($zip->cur_arch_size() >= $zip->{maxsize}) {
                $zip->start_new_archive();
            }
        }
        $zip->cleanup();
    }
    say "Done.";
}

package ZipDir;
use Cwd qw(getcwd);
use Data::Dumper;
use File::Basename qw(basename);
use File::Spec;


sub add_file {
    my ( $self ) = @_;
    my $files = $self->{files};
    die "Unexpected, no file names in array" if @$files == 0;
    my $fn = shift @$files;
    die "Unexpected, file does not exist" if !(-e $fn && -f $fn);
    $self->{sum_file_sizes} += -s $fn;
    say ".. $fn";
    system "zip", "-q", $self->{zip_fn}, $fn;
    unlink $fn or warn "Could not delete file '$fn': $!";
    $self->{cur_files_left} = scalar @$files;
    $self->{cur_num_arch_files} += 1;
}

sub cd {
    my ( $self,  $dir ) = @_;

    chdir $dir or die "Could not chdir to '$dir': $!";
}

sub cleanup {
    my ( $self ) = @_;

    $self->cd( $self->{cwd} );
}

sub cur_arch_size {
    my ( $self ) = @_;

    my $fn = $self->{zip_fn};
    die "Unexpected, file does not exist" if !(-e $fn && -f $fn);
    return -s $fn;
}

sub get_files {
    my ( $self ) = @_;

    $self->cd( $self->{sourcedir} );
    my @files = sort <*.gz>;
    $self->{files} = \@files;
    $self->{cur_files_left} = scalar @files;
}

sub init {
    my ( $self ) = @_;

    $self->{cwd} = getcwd();
    $self->{zip_count} = 0;
    $self->{cur_num_arch_files} = 0;
    $self->{sourcedir} = File::Spec->rel2abs($self->{sourcedir});
    $self->{destdir} = File::Spec->rel2abs($self->{destdir});
    $self->{zip_fn} = undef;
    $self->{sum_file_sizes} = 0;
}

sub new {
    my ( $class, %args ) = @_;

    return bless \%args, $class;
}

sub start_new_archive {
    my ( $self ) = @_;

    my $zfn = $self->{zip_fn};
    if (defined $zfn) {
        my $zsz = -s $zfn;
        $zfn = basename $zfn;
        my $N = $self->{cur_num_arch_files};
        my $fsz = $self->{sum_file_sizes};
        say "Finished with $zfn (size: $zsz), $N files added (size: $fsz)";
    }
    $self->{sum_file_sizes} = 0;
    my $date = qx'date -d "now" +"%Y%m%d%H%M"';
    chomp $date;
    $self->{zip_count} += 1;
    my $count = sprintf "%04d", $self->{zip_count};
    my $fn = "szast_camstar_" . $count . "_" . $date . ".zip";
    $self->{zip_fn} = File::Spec->catfile($self->{destdir}, $fn);
    $self->{cur_num_arch_files} = 0;
}
