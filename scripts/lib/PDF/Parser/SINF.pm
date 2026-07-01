#CHANGES
#03-Aug-2015 grace : new

package PDF::Parser::SINF;
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

=pod
DEVICE:VP3920A-T6FYEBC2
LOT:G6A840.2
WAFER:22
FNLOC:180
ROWCT:131
COLCT:79
BCEQU:01
REFPX:6
REFPY:93
DUTMS:mil
XDIES:100.000
YDIES:60.000
RowData:__ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ @@ @@ @@ @@ @@ @@ @@ @@ @@ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ _
_ __ __
RowData:__ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ @@ @@ @@ @@ @@ @@ @@ @@ @@ @@ @@ @@ @@ @@ @@ @@ @@ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ _
_ __ __
RowData:__ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ @@ @@ @@ @@ @@ @@ @@ 01 @@ @@ @@ @@ @@ 01 @@ @@ @@ @@ @@ @@ @@ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ _
_ __ __
RowData:__ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ @@ @@ @@ @@ @@ 01 01 01 01 01 01 01 17 01 01 01 17 01 17 01 @@ @@ @@ @@ @@ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ _
_ __ __
RowData:__ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ @@ @@ @@ @@ @@ 16 16 01 01 01 01 01 01 01 01 01 01 01 01 01 17 01 17 01 @@ @@ @@ @@ @@ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ _
_ __ __
RowData:__ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ @@ @@ @@ @@ 01 01 01 01 01 01 01 01 01 01 01 01 01 01 01 01 01 01 01 01 01 01 01 @@ @@ @@
=cut

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
            dataSource => 'SINF'
        }
    );
    my $wafer = new_wafer;
    $model->add( 'wafers', $wafer );

    my $section = "Header";	
    my $context = {};
    my ( $x, $y );
	my ( $rows, $cols );
    open( INFILE, $infile );
	
	my $ref_x;
	my $ref_y;
	my $nullBin;
	my $wk;
	my $good_bin;
	my $binCuttoff = 64;  # ignore anything above bin # 64
	my %bin_container = ();
	$y = 0;
    while (<INFILE>) {
		s/\015//;
		chop;
		if($section eq "Header"){
			my @item = split(/\s*:\s*/);
			$item[1] =~ tr/"//d;
			if (uc($item[0]) eq "DEVICE"){
				my $wk = substr($item[1], 0, 6); 
				$header->PROGRAM($wk);
				$header->EQUIP2_ID($wk);
			}
			if (uc($item[0]) eq "LOT"){
				$item[1]  =~ s/\s+/_/g;
				$header->LOT($item[1]);
				$header->EQUIP1_ID("SINF");
				$header->REVISION("1");
				
			}
			if (uc($item[0]) eq "WAFER"){ $wafer->number($item[1]); }			
			if (uc($item[0]) eq "ROWCT"){ $rows = int($item[1]); }
			if (uc($item[0]) eq "COLCT"){ $cols = int($item[1]);}
			if (uc($item[0]) eq "REFPX"){ $ref_x = int($item[1]);}
			if (uc($item[0]) eq "REFPY"){ $ref_y = int($item[1]);}
			if (uc($item[0]) eq "BCEQU"){
				my $dummy_bin = $item[1];
				my $digits    = split //, $item[1];
				$good_bin  = ($digits == 2) ? hex($dummy_bin) : $dummy_bin;
			}
			if (uc($item[0]) eq "YDIES"){ $section = "Map" ; next }
			if (uc($item[0]) eq "FNLOC"){
				given ($item[1]){
				when (180){$wmap->flat('B');}
				when (0){$wmap->flat('T');}
				when (360){$wmap->flat('T');}
				when (90){$wmap->flat('R');}
				when (270){$wmap->flat('L');}
				default { ERROR("invalid Flat Direction: ".$item[1]);}
				}
			}			
		}		
		if($section eq "Map"){
			
			my @item = split(/\s*:\s*/);
					
			#INFO("item0:".$item[0]);
			#INFO("item1:".$item[1]);
			my @binArr = split(/\s/,$item[1]);
					
			for($x = 0;$x < scalar(@binArr);$x++){
				
				if(@binArr[$x] eq '' ){ next; }				
				
				my $bin = convertBinNumber(@binArr[$x]);
				if($bin > $binCuttoff) { next; }
				
				my $die = new_die();
				$die->x($x);
				#$y = $y * -1;
				$die->y($y * -1);
				$die->soft_bin($bin);
				
				### save bin information
				if(exists $bin_container{$bin}){
					$bin_container{$bin} = $bin_container{$bin} + 1;
				}
				else{
					$bin_container{$bin} = 1;
				}							
				$wafer->add( 'dies', $die );				
			}
			$y++;
		}
	}
	
	
			
				foreach my $item (keys %bin_container)
				{
					my $binName = "Bin_".$item;
					my $bin = new_bin(
						{   number => $item,
							name   => $binName,
							count  => $bin_container{$item}
						}						
					);
					
					INFO("print"."number=".$item."/name=".$binName."/count=".$bin_container{$item});
					
					if($good_bin eq $item) { $bin->PF('P'); } else { $bin->PF('F'); }

					$wafer->add( 'bins', $bin );				
				}	
			
			
	
=pod	
	 my $stats = $wafer->stats;
	$wmap->wf_size( 150 );
	$wmap->wf_units("mm");
	$wmap->flat_type('N');
	$wmap->positive_x('R');
	$wmap->positive_y('D');
	$wmap->die_width($wmap->wf_size/$cols);
	$wmap->die_height($wmap->wf_size/$rows);
	$wmap->reticle_rows(1);
	$wmap->reticle_cols(1);
	$wmap->reticle_row_offset(0);
	$wmap->reticle_col_offset(0);
	$wmap->calcCenterDie($stats);
=cut	
    return $model;
}

sub convertBinNumber
{
	my $bin = shift;	
	if($bin =~ /\d+[a-f]/){		
		return hex($bin);
	}
	elsif($bin =~ /\d+/){		
		return hex($bin);
	}
		
	if($bin =~ '[A-V]'){ return int(ord($bin)) - 55; }
	if($bin =~ '[\x0a-\x1f]'){ return int(ord($bin)) - 55; }
	if($bin =~ '[X]'){ return 32; }
	if($bin =~ '[\*]'){ return 253; }
	if($bin =~ '[i]'){ return 253; }
	if($bin =~ '[\$]'){ return 253; }
	if($bin =~ '[\:]'){ return 254; }
	if($bin =~ '[\.]'){ return 255; }
	if($bin =~ '[s]'){ return 255; }
	if($bin =~ '[z]'){ return 255; }
	if($bin =~ '[\-]'){ return 255; }
	
	return 255;
}

1;

