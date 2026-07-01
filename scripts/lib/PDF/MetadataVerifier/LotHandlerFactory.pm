package PDF::MetadataVerifier::LotHandlerFactory;
use base 'Class::Accessor';
use PDF::MetadataVerifier::BkSortNamLotHandler;

__PACKAGE__->mk_accessors('handler_config');

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub get_handler {
    my ($self, $env, $model, $params, $pplogger) = @_;
    my $handler_class = $self->handler_config->{$env} or return;
    $handler_class = "PDF::MetadataVerifier::${handler_class}";
    # print("TEST=".$handler_class);
    if ($handler_class) {
        eval "require $handler_class";
        die $@ if $@; # Add this line to catch errors during require
        return $handler_class->new(model => $model, params => $params, pplogger => $pplogger);
    } else {
        return; # or default handler
    }
}

1;
