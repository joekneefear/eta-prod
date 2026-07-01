package PDF::MetadataVerifier::LotHandler;
use base 'Class::Accessor';

__PACKAGE__->mk_accessors(qw(model params pplogger));

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub handle_lot {
    my ($self) = @_;
    die "handle_lot method must be implemented in subclasses";
}

1;
