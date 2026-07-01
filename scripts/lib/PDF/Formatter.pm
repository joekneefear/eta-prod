package PDF::Formatter;
# SVN $Id: Formatter.pm 95 2015-04-13 15:58:49Z dpower $
use strict;

use Exporter;
use PDF::Formatter::IFF;
our @ISA=qw/Exporter/;
our @EXPORT=qw/new_iff_formatter/;

sub new_iff_formatter{return PDF::Formatter::IFF->new(@_);}

1;

__END__;

=pod

=head1 NAME

PDF::Formatter - Format and print out to file from PDF::DpData::Model object

=head1 SYNOPSYS

  use PDF::Formatter;

  my $formatter = new_iff_formatter({
        model => $model,                 # model is a PDF::DpData::Model
        writer => $wr                    # writer is a PDF::DpWriter
  });          
  $formatter->printPar;                  # this method print out IFF file

=head1 ATTRIBUTES

=over 4

=item model

model is a PDF::DpData::Model
 
=item writter

writter is a PDF::DWritter

=back

=head1 METHODS

=over 4

=item new_iff_format

This method is short cut of

  PDF::Formatter::IFff->new;

=back

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

2015/04/06 kazukik: 1st verion

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

