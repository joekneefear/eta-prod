# SVN $Id: NAM.pm 2510 2019-09-17 23:52:22Z dpower $
# 2014-07-21 jgarcia removed PRODUCT ID in constructing the program name. only use SYSTEM ID.
# 2014-07-24 jgarcia used PROGRAM value and SYSTEM ID value for program name <PROGRAM>_<SYSTEM ID>.
# 2015-Aug-26 Gilbert - Uppercase the lot id.
# 2016-Sep-15 Eric - store "COMMENT" section as misc to get map type
# 2019-Sep-16 Eric - store "PASSTYPE" section as misc to determine defect downgrade maps
# 2022-Aug-10 jgarcia remove systemID in the program name as per Tom Grein - CE-779
# 2023-Jun-20 Eric - added option reading header to fix the invalid date issue
#
package PDF::Parser::NAM;
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
    my $self   = shift;
    my $infile = shift;
    my $header = new_headerLong;
    $header->PROGRAM_CLASS(4);
    my $wmap  = new_wmap;
    my $model = new_model(
        {   header     => $header,
            wmap       => $wmap,
            misc       => {},
            dataSource => 'NAM'
        }
    );
    my $wafer = new_wafer;
    $model->add( 'wafers', $wafer );
    my $section = "Header";
    my $context = {};
    my ( $x, $y );
    open( INFILE, $infile );

    while (<INFILE>) {
        chop;
		 s/\015//;
        if (/^#$/)  { $section = "BinMap";   next }
        if (/^##$/) { $section = "CHECKSUM"; next }
        if (/^##&/) { $section = "End";      next }
        if (/^#&$|^CHECKSUM\s+\S+#&$/) { $section = "Header";   next }
        if ( $section eq "Header" ) {
            if (/^BIN\s+(\d+)\t(\d+)/) {
                my $binName = sprintf( "BIN_%02d", $1 );
                my $bin = new_bin(
                    {   number => $1,
                        name   => $binName,
                        count  => $2
                    }
                );
                $wafer->add( 'bins', $bin );
                next;
            }
            my ( $key, $value ) = split(/\t/);
            $context->{$key} = $value;

	    if (/COMMENT.+/i) {
	    	$model->misc($context->{$key});
	    }
	    if (/^PASSTYPE.+/i) {
		$model->misc($context->{$key});
	    }
        }
        if ( $section eq "BinMap" ) {
            $y++;
            $x = 0;
            foreach my $c ( split // ) {
                $x++;
                next if ( $c eq '.');
                if ( $c =~ /[A-V]/ ) {
                    $c = ord($c) - 55;
                }
                if ( $c eq 'X' ) {
                    $c = 32
                }
                my $die = new_die(
                    {   x        => $x,
                        y        => $y,
                        soft_bin => $c
                    }
                );
                if ($c eq '*') {
                   $die->inked(1);
                }
                $wafer->add( 'dies', $die );
            }
        }
    }
    close(INFILE);
    my @PF = split( ",", $context->{INK_BIN} );
    foreach my $bin ( @{ $wafer->bins } ) {
        my $binPF = 'F';
        if ( ( shift @PF ) eq 0 ) {
            $binPF = 'P';
        }
        $bin->PF($binPF);
    }

    $header->VERSION($VERSION);
    $header->LOT(uc( $context->{'LOT ID'} ));
    $header->PROGRAM_CLASS(4);
    #2022-Aug-10 jgarcia remove systemID in the program name as per Tom Grein
    #$header->PROGRAM($context->{PROGRAM}.",".$context->{'SYSTEM ID'} );
    $header->PROGRAM($context->{PROGRAM});
    $header->REVISION();
    $header->EQUIP1_ID( $context->{PROBER} );
    $header->EQUIP2_ID( $context->{'TEST SYSTEM'} );
    $header->EQUIP3_ID( $context->{'TEST STATION'} );
    $header->EQUIP4_ID( $context->{PROBECARD} );
    $header->EQUIP5_ID( $context->{LOADBOARD} );
    $header->START_TIME(
        $context->{'PROBE DATE'} . " " . $context->{'PROBE TIME'} );
    $header->END_TIME(
        $context->{'PROBE DATE'} . " " . $context->{'PROBE TIME'} );
    $header->OPERATOR( $context->{OPERATOR} );
    $header->INDEX1($context->{'SYSTEM ID'});

    foreach my $item ($header->list){
       if ($header->{$item} eq '????' or $header->{$item} eq '<Unknown>') {
            $header->set($item,'');
       }
    }

    $wafer->number($context->{'WAFER ID'});

    $wmap->wf_units('mm');
    $wmap->wf_size( $context->{'WAFER SIZE'} );
    if ( $wmap->wf_size eq 200 ) {
        $wmap->flat_type('N');
    }
    else {
        $wmap->flat_type('F');
    }
    my %flatDir = (
        0   => 'T',
        90  => 'R',
        180 => 'B',
        270 => 'L',
    );
    INFO(" FLAT Pos = $context->{'FLAT PROBED'}");
    $wmap->flat( $flatDir{ $context->{'FLAT PROBED'} } );
    $wmap->die_width( $context->{'X SIZE'} );
    $wmap->die_height( $context->{'Y SIZE'} );
    my $stats = $wafer->stats;
    $wmap->convertDieSizeToMM( 'AUTO', $stats );
    $wmap->positive_x('R');
    $wmap->positive_y('D');
    $wmap->calcCenterDie($stats);
    $wmap->device_count( $stats->{deviceCount} );
    $header->DEVICE_COUNT( $stats->{deviceCount} );

    $model->misc($context);
    return $model;

}

1;
