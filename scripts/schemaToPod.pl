#!/usr/bin/env perl_db
# SVN $Id: schemaToPod.pl 299 2015-05-07 00:58:30Z dpower $
#
use strict;
use FindBin::libs;
use PDF::DAO;

my $db = getRefdb;
my $schema = 'REFDB';

my @tables = qw/PP_LOT PP_FINALLOT PP_LOTCLASS PP_PROD PP_LIMITS PP_WMAP/;
my $format = " %1s %-20s %5s %-17s %-10s\n";
print "=pod\n\n";

foreach my $table(@tables){
  print "=head1 $table\n\n";
  print sprintf($format,'P','Name','Null','Type','Default');
  print sprintf($format,' ','-'x20,'-'x5,'-'x17,'-'x10);
  my $sth = $db->dbh->primary_key_info(undef,$schema,$table);
  my @primaryKey;
  my @column;
  foreach my $item (@{$sth->fetchall_arrayref}){
     push @primaryKey, $item->[3];
  } 
  $sth = $db->dbh->column_info(undef,$schema,$table,'%');
  foreach my $item (@{$sth->fetchall_arrayref}){
     my $name = $item->[3];
     my $type = $item->[5];
     my $size = $item->[6];
     my $nullable = $item->[17];
     my $default = $item->[12];
     my $key = ' ';
     if (grep {$_ eq $name} @primaryKey){
       $key = '*';
     }
     unless (grep {$_ eq $type} qw/DATE/){
        $type = "$type($size)";
     }
     print sprintf($format,$key,$name,$nullable,$type,$default);
  } 
  print "\n" ;
}
print "\n=cut\n";





