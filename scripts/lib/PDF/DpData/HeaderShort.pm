package PDF::DpData::HeaderShort;
use strict;
use base qw/PDF::DpData::Base/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DAO;

sub list {qw/
    VERSION CREATION_DATE
    PROGRAM_CLASS PROGRAM RELEASE REVISION 
    FAB TECHNOLOGY FAMILY PROCESS PRODUCT PACKAGE
   /}

my $attr = [
    qw/
        isFinalLot isRelLot
        /
];

__PACKAGE__->mk_accessors( list, @$attr );


sub new {
    my ($class, $args) = @_;
    foreach my $key (%$args){
      if ( $key =~ /TIME$|DATE$/ ) {
         my $value = formatDate($args->{$key}) ;
         $args->{$key} = $value;
      }
    }
    my $self= $class->SUPER::new($args );
    $self->CREATION_DATE(currentDate);
    return $self;
}

sub set {
    my ( $self, $key ) = splice( @_, 0, 2 );
    if ( $key =~ /TIME$|DATE$/ ) {
        my $value = shift @_;
        push( @_, formatDateToYYYYMMDD($value) );
    }
    $self->SUPER::set( $key, @_ );
}

sub populateMeta{
  my $self = shift;
  unless (defined($self->PRODUCT)){
    ERROR("Product to lookup RefDB is null ");
    return 0;
  }
  my $hash = getRefdb->getProduct($self->PRODUCT);
  if (keys %$hash > 0 ){
        INFO("Good. Meta Found for Product = ".$self->PRODUCT);
        $self->FAMILY($hash->{family});
        $self->PROCESS($hash->{process});
        $self->PACKAGE($hash->{package});
        if ( !$self->isFinalLot and ($hash->{fab_desc} ne "" and $hash->{fab_desc} ne "N/A"))
        {
            $self->FAB($hash->{fab_desc});
        }
	if ( !$self->isRelLot and ($hash->{fab_desc} ne "" and $hash->{fab_desc} ne "N/A"))
	{
		$self->FAB($hash->{fab_desc});
	}
        return 1;
  } else {
        WARN("Bad.. Meta Not Found for Product = ".$self->PRODUCT);
        return 0;
  }
}

1;

__END__;

=pod

=head1 NAME

PDF::DpData::HeaderShort - Header for LEH, Met, Fab datatype to generate IFF file 

=head1 SYNOPSIS

  use PDF::DpData
  my $header = PDF::DpData::HeaderShort->new;
  $header->VERSION($VERSION);
  $header->CREATION_DATE(strftime("%Y/%m/%d %H:%M:%S",localtime(time())));
  $header->PROGRAM_CLASS(4);
  $header->PROGRAM($program."_SPEM");
  $header->REVISION();
  $header->PRODUCT($product);
  
 
    # get Meta data from database
  $header->populateMet
   
    # get String to output to IFF
  print OUT "<HEADER>\n";
  print OUT $header->toString."\n";
  print OUT "</HEADER>\n";


=head1 Attributes
  
  VERSION 
  CREATION_DATE  -- YYYY/MM/DD HH24:MI:SS (Default = current datetime)
  PROGRAM_CLASS  -- program class number 
  PROGRAM        -- No prefix 
  RELEASE 
  REVISION 
  FAB
  TECHNOLOGY 
  FAMILY      
  PROCESS 
  PRODUCT
  PACKAGE 

=head1 METHODS

=head2 toString

inherit from L<PDF::DpData::Base.pm/toString>

=head2 populateMeta() 

PRODUCT attibute must be set before calling this method.
It accesss REFDB and get data from PP_PROD, and populate to following attribute.
  FAMILY,PROCESS,PRODUCT,PACKAGE,FAB

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/03/10 kazukik: output IFF format
 2015/03/29 kazukik: refactor module IFF format

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

