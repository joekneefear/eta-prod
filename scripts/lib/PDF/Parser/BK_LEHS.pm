package PDF::Parser::BK_LEHS;
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

sub readPerLineAndEnrichProduct() {
  my $self   = shift;
  my $infile = shift;
  my @inputFileLineData = ();
  my %linePerProduct;
  my @elements = ();
  my $header = new_headerLong;
  my $model  = new_model(
    {
      misc       => {},
      dataSource => 'LEHS'
    }
  );


  my %leh;
  my $row = "";
  my $fileHandle = IO::File->new($infile) or dpExitError("Failed to open LEHS file $infile");

  while (my $line = $fileHandle->getline) {

    chomp($line);
    $row = "";
    #my (FACILITY	PRODUCT	LOT	LOT_TYPE	ROUTE	OPERATION	STEP_NO	OPER_DESC	SUB_STEP_NAME	STEP_NAME	PE	RP	TI	TO	PI	PO	WOPR_LONG_DESC	ROOM_CODE	FINANCE_OPER	OPER_DIVSN SOURCE_LOT PROCESS
    if($line =~ /^[a-zA-Z0-9]*/) {
      my ($lot,$grp4) = "";
      my @columns = split(/\|/, $line);
      if($columns[0] !~ /FACILITY(.+)?/i) {
        $lot = $columns[2];
        $grp4 = $columns[23];
        $grp4 =~ s/\s+/\?/;
        my $key = "${lot}_${grp4}";
        #INFO("Lotid=>>$lotid<<");
        #INFO("Array=>@columns");
        # my $hash = getRefdb->getBKLEHSmetadata($lotid);
        # if (keys %$hash > 0) {
        #
        #   if($hash->{product} ne "N/A") {
        #     #INFO("replace $columns[1] to $hash->{product}.");
        #     splice(@columns, 1, 1, $hash->{product});
        #   }
        #   my $sourceLot = $hash->{source_lot};
        #   if($sourceLot !~ /.+\.\S$/i && $sourceLot ne "N/A") {
        #     $sourceLot = "${sourceLot}.S";
        #   }
        #   push(@columns,$sourceLot);
        #   push(@columns,$hash->{process});
        # } else {
        #   $model->forSBflag(1);
        # }

        #if(@columns) { # && ($column[0] ne "" || $columns[1] =~ /FACILITY/i)) {
          #$row = join('|', @columns);
          if($key  ne "" && $line ne "") {
            push(@{ $linePerProduct{$key} }, $line);
          }
        #}

      } else {

        #push(@columns,"SOURCE_LOT");
        #push(@columns,"PROCESS");
        #$row = $line;
        #push(@{ $linePerProduct{'header'} }, $row);
        $linePerProduct{'header'} = $line;
      }

    }#end of if($line =~ /^[a-zA-Z0-9]*/) {

  }

  $model->misc(\%linePerProduct);
  return $model;
}
1;
