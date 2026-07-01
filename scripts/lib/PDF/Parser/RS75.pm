# 09-May-2017 Eric	: new
package PDF::Parser::RS75;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

sub readFile {
        my $self = shift;
        my $infile = shift;
	my $ref = shift;
	my @tnum = ();
	my @result = ();
	my %xyref; 
	#my $ref = "/data/bkfb_rs75/REF/xy_coordinates.ref";

	open REF, $ref or die "can't open reference file: $?\n";
	while(my $line=<REF>)
	{
		chomp $line;
		$line       =~ s/\"|\cM//g;
		next if $line =~ /Die/i;
		my ($partid, $y, $x) = split /\,/, $line;
		$xyref{$partid}{X} = $x;
		$xyref{$partid}{Y} = $y;
	}
	close REF;
	
	my $header = new_headerLong;
        my $model = new_model (
	{
        	header => $header,
                misc   => {},
                dataSource => 'RS75'
        }
        );
	my $wafer = new_wafer;
	$model->add('wafers', $wafer );
	

	my $test = new_test;
	$test->number(1);
	$test->name("RESISTIVITY");
	$test->units("Ohms");
	$wafer->add('tests', $test);
	
	open FH, $infile or die "can't open $infile\n";
        while(my $line=<FH>){
		#print "$line\n";
		chomp $line;
		$line       =~ s/\"|\cM//g;
		my @item = split /\,/, $line;
		if ($line =~ /^date/i) {
			@tnum = splice @item, 3;
		}
		elsif ($line =~ /^\d+/) {
			if ( $item[0] =~ /(\d{4})(\d{2})(\d{2})/ ) {
				my $startdate = $1."/".$2."/".$3." "."00:00:00";
				$header->START_TIME($startdate);
				$header->END_TIME($startdate);
			}
			$header->LOT($item[1]);
			$wafer->number($item[2]);
			@result = splice @item, 3;
		}
	}
	close(FH);
	
	foreach my $part (sort {$a<=>$b} keys %xyref) {
		my $die = new_die;
		$die->partid($part);
		$die->site($part);
		$die->x(trim($xyref{$part}{X}));
		$die->y(trim($xyref{$part}{Y}));
		$die->add('result',trim($result[$part-1]));
		$wafer->add('dies',$die);
	}

return $model;
}

1;
