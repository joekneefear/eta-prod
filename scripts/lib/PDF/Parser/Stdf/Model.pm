# SVN $Id: Model.pm 514 2015-06-08 06:31:08Z dpower $
package PDF::Parser::Stdf::Model;
use strict;
use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";
use PDF::Log;

my $attr = [qw/FAR MIR SDR WCR MRR EMIR EWCR/];

sub array{
  return qw/ PMR PGR PCR PDR SBR SBR_each HBR HBR_each EPDR TGD TSR GDR wafers/;
}
sub item{
    return  @$attr;
}
__PACKAGE__->mk_accessors(@$attr, array );

package PDF::Parser::Stdf::Model::Wafer;
use strict;
use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

my $attr = [qw/WIR WRR/];
sub array{
  return qw/ WSBR WHBR WMR WTSR res/;
}

__PACKAGE__->mk_accessors(@$attr, array);

package PDF::Parser::Stdf::Model::Res;
use strict;
use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr =  [qw/ PIR PRR EPRR /] ;
sub array{
  return qw/PTR MPR FTR EFTR /;
}

__PACKAGE__->mk_accessors(@$attr, array);


1;

