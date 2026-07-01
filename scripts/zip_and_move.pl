#! /usr/bin/env perl

use feature qw(say);
use strict;
use warnings;

#May-19-2021	Karen	Updated script to hold temp file in /tmp
#
# DESCRIPTION:
#
# Archives all .gz files in the source directories and put them into .zip
# files which are written to the destination directories.
#
# Source directories are listed as separate lines in an input file
#
# Source directory names will be like:
#    - "/archives-yms/data/mefab_eqp_asm/STAGING/PRODUCTION"
#
#  Destination directories will be like:
#    - "/archives-yms/data/mefab_eqp_asm/PRODUCTION"
#
#
# REQUIREMENTS:
#
# - ZIP file should not be larger than 100 Mb
# - ZIP file should not contain more than 1000 files
# - Name of zip file should be on the form:
#
#      <grand_parent_dir>_date_count.zip
#
#  where <grand_parent_dir> is the parent of the parent directory of the source dir
#
# - The source files should be deleted after having been added to the archive.
#

use Data::Dumper;
use File::Basename qw(basename dirname);
use File::Spec;
use File::Temp ();
use Getopt::Long;
{
    my $fn = get_command_line_options();
    print("INFILE=$fn\n");
    my $sourcedirs = read_source_dirs($fn);
    #my $maxfiles  = 4;
    #my $maxsize = 1000;
    my $maxfiles  = 1000;
    my $maxsize = 10000000;
    my $temp_dir = get_temp_dir();
    for my $src (@$sourcedirs) {
        my $dst = get_dest_dir($src);
        say "\nWorking on sourcedir: $src, destdir: $dst ..\n";
        my $zip = ZipDir->new(
            sourcedir => $src,
            destdir   => $dst,
            maxfiles  => $maxfiles,
            maxsize   => $maxsize,
            temp_dir  => $temp_dir,
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

sub get_command_line_options {
    my $fn = "/export/home/dpower/project/scripts/source_dir_ref.txt";
    GetOptions ("infile=s" => \$fn ) or die("Error in command line arguments\n");
    return $fn;
}

#
# - Assume $src is on the form "/archives-yms/data/mefab_eqp_asm/STAGING/PRODUCTION"
# -- Create destination on the form "/archives-yms/data/mefab_eqp_asm/PRODUCTION"
# - Assume $src is on the form "/archives-yms/data/mefab_eqp_asm/STAGING/SANDBOX"
# -- Create destination on the form "/archives-yms/data/mefab_eqp_asm/SANDBOX"
#
sub get_dest_dir {
    my ($src) = @_;

    my $name = basename($src);
    my $basedir = dirname(dirname($src));
    return File::Spec->catfile($basedir, $name);
}

# Use a temp dir to store the .zip archive until all files have been added.
#  This is done such that the middle ware will not move the .zip file before
#  all files have been added.
# When all files have been added, the .zip file is moved to the production folder.
sub get_temp_dir {
    my $dir = File::Temp::tempdir( CLEANUP => 1 );
    say "Using temp dir: $dir";
    return $dir;
}

sub read_source_dirs {
    my ( $fn ) = @_;

    my @dirs;
    open ( my $fh, '<', $fn ) or die "Could not open file '$fn': $!";
    while( my $line = <$fh> ) {
        chomp $line;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next if (length $line) == 0;
        push @dirs, $line;
    }
    close $fh;
    return \@dirs;
}

package ZipDir;
use Cwd qw(getcwd);
use Data::Dumper;
use File::Basename qw(basename dirname);
use File::Spec;

sub add_file {
    my ( $self ) = @_;
    my $files = $self->{files};
    die "Unexpected, no file names in array" if @$files == 0;
    my $fn = shift @$files;
    die "Unexpected, file does not exist" if !(-e $fn && -f $fn);
    $self->{sum_file_sizes} += -s $fn;
    say ".. $fn";
    die sys_err_str("Failed to execute zip command")
      if !run_system_cmd(["zip", "-q", $self->{zip_fn}, $fn]);
    unlink $fn or die "Could not delete file '$fn': $!";
    $self->{cur_files_left} = scalar @$files;
    $self->{cur_num_arch_files} += 1;
}

sub cd {
    my ( $self,  $dir ) = @_;

    chdir $dir or die "Could not chdir to '$dir': $!";
}

sub cleanup {
    my ( $self ) = @_;

    $self->move_zip_to_production();
    $self->cd( $self->{cwd} );
}

sub cur_arch_size {
    my ( $self ) = @_;

    my $fn = $self->{zip_fn};
    die "Unexpected, file does not exist" if !(-e $fn && -f $fn);
    return -s $fn;
}

# Add $ERRNO to the input string if $ERRNO is defined
sub sys_err_str {
    my $error = $_[0];
    $error .= " : $!" if $!;
    return $error;
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
    $self->{parent_dir_name} = basename(dirname(dirname( $self->{sourcedir} )));
    $self->{destdir} = File::Spec->rel2abs($self->{destdir});
    $self->{zip_fn} = undef;
    $self->{sum_file_sizes} = 0;
}

# When all files have been added to the zip archive in the temp folder, we
#   can safely move it to the production folder. (If we instead had kept the zip
#   archive in the source directory rather than in the temp directory, it could have
#   been moved prematurely (before all files had been added) by the middle ware program)
sub move_zip_to_production {
    my ( $self ) = @_;

    my $zfn = $self->{zip_fn};
    return if !defined $zfn;
    return if ! (-e $zfn);
    my $zsz = -s $zfn;
    my $zfn_base = basename $zfn;
    my $N = $self->{cur_num_arch_files};
    my $fsz = $self->{sum_file_sizes};
    my $source = $zfn;
    my $dest = $self->{destdir};
    die sys_err_str("Cannot move .zip file to production dir")
      if !run_system_cmd(["mv", $source, $dest]);
    say "Finished with $zfn_base (size: $zsz), $N files added (size: $fsz)";

}

sub new {
    my ( $class, %args ) = @_;

    return bless \%args, $class;
}

sub start_new_archive {
    my ( $self ) = @_;

    if (defined $self->{zip_fn}) {
        $self->move_zip_to_production();
    }
    $self->{sum_file_sizes} = 0;
    my $date = qx'date -d "now" +"%Y%m%d%H%M"';
    chomp $date;
    $self->{zip_count} += 1;
    my $count = sprintf "%04d", $self->{zip_count};
    #my $fn = $count . "_" . $date . ".zip";
    my $fn = $self->{parent_dir_name} . "_" . $date . "_" . $count . ".zip";
    $self->{zip_fn} = File::Spec->catfile($self->{temp_dir}, $fn);
    $self->{cur_num_arch_files} = 0;
}

sub run_system_cmd {
    my ($cmd) = @_;

    my $res = system @$cmd;
    if ( $res == -1 ) {
        # A return value of -1 from system() indicates a failure to start the program
        # Note: The caller can inspect $ERRNO for more information
        return 0;
    }
    elsif ($res & 127) {
        printf "system(@$cmd) : killed by signal %d, %s coredump\n",
          ($res & 127),  ($res & 128) ? 'with' : 'without';
        return 0;
    }
    elsif ($res != 0) {
        printf "system(@$cmd) exited with error code %d\n", $res >> 8;
        # Note: The caller can inspect $ERRNO for more information
        return 0;
    }
    return 1;
}
