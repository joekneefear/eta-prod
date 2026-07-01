package PDF::DpData::Base;
use strict;
use base qw/Class::Accessor/;
use PDF::Log;
use PDF::DpLoad;
our $VERSION = "1.0";

sub array {()};
sub list {()};

sub new{
  my ($class, $args) = @_;
  my $self= $class->SUPER::new($args);

  foreach ($class->array){
        $self->{$_} = [];
  }
  return $self;
}

sub add{
   my $self = shift;
   my $name = shift;
   my $data = shift;
   unless (grep {$_ eq $name } $self->array){
     dpExit(1,"$name is not array ref");
     return 0;
   }
   my $array = $self->{$name};
   push @$array, $data;
   return 1;
}

sub find{
   my $self = shift;
   my $name = shift;
   my $hash = shift;
   unless (grep {$_ eq $name } $self->array){
     dpExit(1,"$name is not array ref");
   }
   my ($found) = grep {
       my $result = 1;
       foreach my $key (keys %$hash) {
         $result *= ($_->{$key} eq $hash->{$key}) ;
       } 
       $result;
      } @{$self->{$name}};
   #undef $found if ($found eq 0); 
   return $found;
}


sub toString {
    my $self = shift;
    my $string;
    foreach ( $self->list ) {
        my $value = repNA( $self->{$_} );
        TRACE( uc($_) . " = " . $value );
        $string .= uc($_) . "=" . $value . "\n";
    }
    return $string;
}

sub isEmpty {
    my $self = shift;
    my $hash = {%$self};
    if (%$hash) {
        return 0;
    }
    else {
        return 1;
    }
};

1;

__END__;

=pod

=head1 NAME

PDF::DpData::Base - Abstract class for dataPower loading model classes. DO Not instanciate this class.

=head1 SYNOPSIS

sample subclass 

  package PDF::DpData::People;
  ues base qw/PDF::DpData::Base Class::Accessor/;   # inherit this class
  my $list = qw/name age address tel ... /;  # define $list as array ref
  sub array {qw/friends/); #  array referece 
  __PACKAGE->mk_accessors($list, array); # create setter and getter

main script 

  my $john = PDF::DpData::People->new;
  $john->name("John");
  $john->age("10");
  $john->address("     some where in US   ");
   
  my $bill = PDF::DpData::People->new({name => 'Bill'});
  $john->add('friends',$bill);
 
  print $sample->toString;    # toString method in this class
  
output

  name=John
  age=10 
  address=some where in US    # spaces, tab are trimmed.
  tel=NA                      # empty or undefined value will be replaced to "NA"

  ## print out order by defined in $list 
  
=head1 Attributes
 
  list; 

=head1 METHODS

=over 4

=item

=head2 add(<attribute name>,$obj);

add is available for attribute defined by array method. 

In above sample class case

 $john->add('friends',$bill);

is equivalent to

 my @friends = @($john->friends);
 push @firends , $bill;

=head2 find(<attribute name>,{key => value});

find is available for attribute defined by array method.

find return the 1st object matched by 2nd argument condition. The 2nd argument must be Hash Ref.

  my $bill = $john->find('friends',{name=>'Bill});

=head2 toString

return string formated as <Attribute>=<Value> for the attribute defined as $list

order by listed above attributes section in each class

null value will be replaced to "NA"

  VERSION=1.0
  CREATION_DATE=2015/03/18 04:01:55
  PROGRAM_CLASS=1
  PROGRAM=ULSG0125WSX4_13_EAGLE
  RELEASE=NA
  ....

=head2 isEmpty

return 1 if the object has no value at all.
Otherwise 0.
usage

  if (defined($obj) and ! $obj->isEmpty) {
     # ok, the object is not empty hash
  }

=back

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

2015/03/30 kazukik: pod maintained

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

