# 13-July-2022 : jgarcia : initial.

package PDF::Parser::CZ2Weh;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::DAO;
use PDF::Log;
use IO::File;

use base qw/PDF::DpData::Base Class::Accessor/;


our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}

__PACKAGE__->mk_accessors(array);

sub readPerLineAndSplitByProcessFamily() {
  my $self   = shift;
  my $infile = shift;
  my @inputFileLineData = ();
  my %linePerProcessFamily;
  my @elements = ();
  my $header = new_headerLong;
  my $model  = new_model(
    {
      misc       => {},
      dataSource => ''
    }
  );


  #my %leh;
  my $row = "";
  my $fileHandle = IO::File->new($infile) or dpExitError("Failed to open Text file $infile");

  while (my $line = $fileHandle->getline) {

    chomp($line);
    $row = "";
    my @columns = ();
    if($line =~ /PROCESS_FAMILY\,SOURCE_LOT\,.*/i) {
      #INFO("====>>>$line");
      $line =~ s/\,/\|/g;
      #@columns = split(/\,/, $line);
    } #else {
      #@columns = split(/\|/, $line);
    #}
    @columns = split(/\|/, $line);
    
    if($columns[0] !~ /PROCESS_FAMILY/i) {
      my $key = $columns[0];
      if($key eq "") {
        $key = "NA";
      }
      if($key  ne "" && $line ne "") {
        push(@{ $linePerProcessFamily{$key} }, $line);
      }

    } else {
       $linePerProcessFamily{'header'} = $line;
     }
  }

  $model->misc(\%linePerProcessFamily);
  return $model;
}
1;
