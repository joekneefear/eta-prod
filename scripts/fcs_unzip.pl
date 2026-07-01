#!/usr/bin/env perl_db
# SVN $Id: fcs_unzip.pl 458 2015-05-29 16:03:35Z dpower $

=pod

=head1 SYNOPSIS

  fcs_unzip.pl <Input flie name>
      [--out <output dir>]
      [--logfile <logfilepath>]
      [--debug|--trace]

=head1 DESCRIPTIONS

B<This script> will unzip a file into the specified directory (default is current directory).

=head1 AUTHOR

B<scott.boothby@fairchildsemi.com>

=head1 CHANGES

 2015/05/27 sboothby : Created.

=head1 LICENSE

(C) Fairchild.

=cut

use strict;
use Archive::Extract;
#use FindBin::libs;
use Getopt::Long;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use File::Spec;
use File::Touch;
use POSIX qw(strftime);
use PDF::Log;
use PDF::DpLoad;
#use PDF::DpData;
use PDF::DpWriter;
#use PDF::Formatter;
#use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use v5.10;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;

my($sVersionId) = ( split(' ', '$Revision: 458 $') )[1];
my($VersionAndDate) = "1.0 - May 29, 2015";

my (%hOptions) = ( "OUTDIR" => undef
                 , "LOGFILE" => undef
                 , "TOUCH" => 0
		 , "DEBUG" => undef
		 , "V" => undef
		 , "TRACE" => undef);

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage();
    dpExit( 1, "No input file specified" );
}
unless (
    GetOptions( \%hOptions, "OUTDIR=s", "LOGFILE=s", "DEBUG", "TRACE", "TOUCH", "V" )
    )
{
    dpExit( 1, "invalid options" );
}
if ( ! exists($hOptions{OUTDIR}))
{
   $hOptions{OUTDIR}=".";
}

if($hOptions{V} || $hOptions{VERSION} || $hOptions{help})
{
    print("$VersionAndDate\n");
    dpExit(0);
};

my @required_options = qw/OUTDIR/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions );

# Read input file
my $ZIPFile = shift(@ARGV);
if ( !defined($ZIPFile) || !-f $ZIPFile ) 
{
    pod2usage();
    dpExit( 1, "input file does not exist $ZIPFile" );
}

# check output dir
my $wr = PDF::DpWriter->new(
    {   outdir   => $hOptions{OUTDIR},
        basename => ( basename $ZIPFile),
        ext      => 'iff'
    }
);

# Unzip
my $ae=Archive::Extract->new(archive => $ZIPFile);
my $ok=$ae->extract(to => $hOptions{OUTDIR});
# if TOUCH option passed in, touch all extracted files to update modification date.
if ( $hOptions{TOUCH} != 0 )
{
    # Update the files array with the full path
    foreach (@{$ae->files})
    {
        $_ = File::Spec->catfile( $hOptions{OUTDIR}, $_ );
    }
    touch( @{$ae->files} );
}

if ( -f "$hOptions{OUTDIR}/[Content_Types].xml" )
{
   unlink "$hOptions{OUTDIR}/[Content_Types].xml";
}

INFO(" --> Done!");
dpExit(0);

