#! /usr/bin/env perl


use feature qw(say);
use strict;
use warnings;
use Getopt::Long;
{
    my $fn = parse_command_line_options();
    my $cur_time = time;
    my $self = Main->new(
        cur_time => $cur_time,
        infile  => $fn,
    );
    my $dirs = $self->parse_infile();
    my @counts;
    my @email_dirs;
    my @skipped_dirs;
    for my $dir (@$dirs) {
        my $max_age = $self->get_directory_files_max_age( $dir );
        if ( $max_age > 1 ) {
            my $count = $self->count_files( $dir );
            say "$dir,$count";
            push @counts, $count;
            push @email_dirs, $dir;
        }
        else {
            push @skipped_dirs, $dir;
        }
    }
   if ( @email_dirs > 0 ) {
	$self->send_email(\@email_dirs, \@counts);
   }
}

sub parse_command_line_options {
    my $fn = "/export/home/dpower/project/scripts/list_dir.txt";
    GetOptions("infile=s" => \$fn ) or die "Error in command line arguments\n";
    return $fn;
}

package Main;
use feature qw(say);
use strict;
use warnings;
use Cwd qw(getcwd);

sub get_directory_files_max_age {
    my ( $self,  $dir ) = @_;

    my $curdir = getcwd();
    my $max_age = 0;
    chdir $dir or die "Could not cd to dir '$dir': $!";
    for my $fn (<*.gz>) {
        my $mtime = (stat $fn)[9];
        my $age = $self->{cur_time} - $mtime;
        my $hours = $age / (60 * 60);

        $max_age = $hours if $hours > $max_age;
    }
    chdir $curdir;
    return $max_age;
}

sub count_files {
    my ( $self,  $dir ) = @_;

    my $curdir = getcwd();
    chdir $dir or die "Could not cd to dir '$dir': $!";
    my $count = () = grep {-f $_} <*.gz>;
    chdir $curdir;
    return $count;
}


sub new {
    my ( $class, %args ) = @_;

    return bless \%args, $class;
}

sub parse_infile {
    my ( $self ) = @_;

    my $fn = $self->{infile};
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

sub send_email {
    my ( $self, $dirs, $counts) = @_;

    my $email_addr = 'yms.admins@onsemi.com';
    my $msg = join "\n", map {$dirs->[$_] . "," . $counts->[$_]} 0..$#$dirs;
    my $subj = "xFCS MDW Exensio Hosted Outbox monitoring - files not moving for > 1 hours";
    my $pid = open (my $MAIL, "|-", "mailx", "-s", $subj, $email_addr)
      or die "Cannot run mailx: $!";
    print $MAIL "$msg\n";
    close $MAIL;
}
