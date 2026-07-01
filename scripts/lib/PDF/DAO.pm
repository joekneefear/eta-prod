# SVN $Id: DAO.pm 2269 2018-01-11 00:33:01Z dpower $a
# 2016-10-25  jgarcia  : added getProductionDb
# 2017-10-07  eric     : added getRmsdb
# 2021-05-12  eric     : added getDWPlm

package PDF::DAO;
use strict;
use Exporter 'import';
use PDF::DAO::Refdb;
use PDF::DAO::ProdDB;
use PDF::DAO::DWPLM;
use PDF::Log;
use PDF::DpLoad;
our @EXPORT = qw/getRefdb getProductionDb getRmsdb getDWPlm/;
#our @EXPORT = qw/getProduction/;
my $refdb;
my $prodDb;
my $rmsdb;

sub getRefdb {
    my $attrOver = shift ;
     my $attr = {
         PrintError => 1,
         RaiseError => 0,
         AutoCommit => 1,
     };
    if (defined $attrOver){
      foreach my $key (keys %$attrOver){
         $attr->{$key} = $attrOver->{$key}
      }
    }
    if ( defined($::refdb) ) {
        return $::refdb;
    }
    else {
        #my $db_tns  = "dbi:Oracle:host=oruxymsora01d;port=1521;sid=YMS01DEV";
        #my $db_tns  = "dbi:Oracle:host=oruxymsora01p;port=1521;sid=YMS01PRD";
        #my $db_tns = "dbi:Oracle://exnprd-db.onsemi.com:1729/EXNPRD.onsemi.com";
        #my $db_tns = "dbi:Oracle://exndev-db.onsemi.com:1739/EXNDEV.onsemi.com";
        #my $db_pass = '88sgX%#$29-azx'; #dev'XBfjCq#$1542FFz';
        #my $db_pass = 'XBfjCq#$1542FFz';
        #my $db_pass = '88sgX%#$29-azx'; #'XBfjCq#$1542FFz';
        my $db_tns = "";
        my $db_user = 'refdb';
        my $db_pass = "";

        if ( defined( $ENV{REFDB_TNS} ) ) {
            $db_tns = $ENV{REFDB_TNS};
        }
        if ( defined( $ENV{REFDB_USER} ) ) {
            $db_user = $ENV{REFDB_USER};
        }
        if ( defined( $ENV{REFDB_PASS} ) ) {
            $db_pass = $ENV{REFDB_PASS};
        }
        DEBUG("connecting to ${db_tns},${db_user},${db_pass}");
        $::refdb = PDF::DAO::Refdb->connect( $db_tns, $db_user, $db_pass, $attr )
    		or dpExit( 1, "Unable to connect to database: ".$DBIx::Simple->error );
        DEBUG("connectted to ${db_tns},${db_user},${db_pass}");
        return $::refdb;
    }

}

sub getProductionDb {
    my $attrOver = shift ;
     my $attr = {
         PrintError => 0,
         RaiseError => 1,
         AutoCommit => 1,
     };
    if (defined $attrOver){
      foreach my $key (keys %$attrOver){
         $attr->{$key} = $attrOver->{$key}
      }
    }
    if ( defined($::prodDb) ) {
        return $::prodDb;
    }
    else {
        #my $db_tns  = "dbi:Oracle:host=oruxymsora01d;port=1521;sid=YMS01DEV";
        my $db_tns  = "dbi:Oracle:host=oruxymsora01p;port=1521;sid=YMS01PRD";
        my $db_user = 'exn_admin';
        my $db_pass = 'exn_admin';

        if ( defined( $ENV{REFDB_TNS} ) ) {
            $db_tns = $ENV{REFDB_TNS};
        }
        if ( defined( $ENV{REFDB_USER} ) ) {
            $db_user = $ENV{REFDB_USER};
        }
        if ( defined( $ENV{REFDB_PASS} ) ) {
            $db_pass = $ENV{REFDB_PASS};
        }
        DEBUG("connecting to ${db_tns},${db_user},${db_pass}");
        $::prodDb = PDF::DAO::ProdDB->connect( $db_tns, $db_user, $db_pass, $attr )
    		or dpExit( 1, "Unable to connect to database: ".$DBIx::Simple->error );
        DEBUG("connectted to ${db_tns},${db_user},${db_pass}");
        return $::prodDb;
    }

}

# ON RMS
sub getRmsdb {
        my $attrOver = shift ;
        my $attr = {
                PrintError => 1,
                RaiseError => 0,
                AutoCommit => 1,
        };
        if (defined $attrOver){
                foreach my $key (keys %$attrOver){
                        $attr->{$key} = $attrOver->{$key}
                }
        }
        if ( defined($::rmsdb) ) {
                return $::rmsdb;
        }
        else {
                #my $db_tns  = "dbi:Oracle:host=myondb5-db.onsemi.com;port=1535;sid=myondb5";
                my $db_tns  = "dbi:Oracle:host=10.242.52.60;port=1535;sid=myondb5";  #temporarily uses IP. Network tean need to resolve
                my $db_user = 'RMS_READ';
                my $db_pass = 'RmsR34d';

                DEBUG("connecting to ${db_tns},${db_user},${db_pass}");
                $::rmsdb = PDF::DAO::Refdb->connect( $db_tns, $db_user, $db_pass, $attr )
                or dpExit( 1, "Unable to connect to database: ".$DBIx::Simple->error );
                DEBUG("connectted to ${db_tns},${db_user},${db_pass}");
                return $::rmsdb;
    }

}

sub getDWPlm {
        my $attrOver = shift ;
        my $attr = {
                PrintError => 1,
                RaiseError => 0,
                AutoCommit => 1,
        };

        if (defined $attrOver){
                foreach my $key (keys %$attrOver){
                        $attr->{$key} = $attrOver->{$key}
                }
        }

        if (defined($::dwPlmDb) ) {
                return $::dwPlmDb;

        }
        else {
                #my $db_tns  = "dbi:Oracle:host=dwprd-db.onsemi.com;port=1693;sid=DWPRD";
                my $db_tns  = "dbi:Oracle:DWPRD";
                my $db_user = 'dw_query';
                my $db_pass = 'dw_query';

                DEBUG("connecting to ${db_tns},${db_user},${db_pass}");
                $::dwPlmDb = PDF::DAO::DWPLM->connect( $db_tns, $db_user, $db_pass, $attr )
                or dpExit( 1, "Unable to connect to database: ".$DBIx::Simple->error );
                DEBUG("connected to ${db_tns},${db_user},${db_pass}");
                return $::dwPlmDb;
        }
}

1;

__END__;

=pod

=head1 NAME

PDF::DAO - Expoter module to provide Data Access Object for each schame

=head1 SYNPSIS

  use PDF::DAO;
  my $db = getRefdb;
  $db->method_defined_in_PDF::DAO::Refdb

=head1 METHODS

=head2 getRefdb

return L<PDF::DAO::Refdb.pm> object. If the object is instanciated before, just return the cache.
PDF::DAO::Refdb is child class of L<DBIx::Simple|http://search.cpan.org/perldoc?Log::Log4perl> can be used.

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

2015/03/31 kazukik: new creation
2016/10/25 jgarcia: added getProductionDb

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut
