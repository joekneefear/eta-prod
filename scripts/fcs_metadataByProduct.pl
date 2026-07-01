#!/usr/bin/env perl_db
=pod

=head1 SYNOPSIS

  fcs_metadataByProdct.pl <Input file name>
      [--out <output dir>]
      [--logfile <logfilepath>]
      [--debug|--trace]

=head1 DESCRIPTIONS

B<This script> will add Meta data by keying product name.

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

use FindBin::libs;
use strict;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use Getopt::Long  qw/:config ignore_case auto_help/;
use PDF::FCS_Common qw/getMetaByProduct/;
use PDF::Log;
use PDF::DpLoad;



if ($#ARGV < 0) {
   pod2usage(3);
   dpExit(1,"No input file specified");
}

my $filename = $ARGV[0];

if (! -f $filename) {
        dpExit(1,"Input file $filename Not Found");
}
my %hOptions =
 (
        OUT => undef,
        LOGFILE => undef,
        DEBUG  => undef,
        HELP => undef
);

unless(GetOptions(\%hOptions,
        "OUT=s",
        "LOGFILE=s",
        "DEBUG",
        "TRACE"))
{
        dpExit(1,"invalid options");
        pod2usage(3);
}

PDF::Log->init(\%hOptions);

my $OUTFILE = $filename;
$OUTFILE = $filename."2";
if ($hOptions{OUT}) {
        $OUTFILE = $hOptions{OUT}."/".(basename $OUTFILE);
}
INFO("Input  : $filename");
INFO("Output : $OUTFILE");
open(IN,$filename);
my @buffer;
my $product;
while(<IN>){
 my @items = split(/\|/); 
 $product = $items[2];
 push (@buffer, $_);
}
  INFO("product before trim = $product");
  $product =~ s/~//g;
  INFO("product after  trim = $product");

  my $meta = getMetaByProduct($product);
  open(OUT,">".$OUTFILE);
  print OUT $meta;
  foreach (@buffer){
    print OUT $_;
  }
  close OUT;



