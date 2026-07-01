=pod
#20-May-2015 gilbertm: Added 360 in orientation and adjust flat location for 90 and 270 to match the EWB converter
#		       Removed the program for test code indicator and let the pre-processor script handle it
#23-May-2015 gilbertm: Capture the value on DEVICE field as product by default but overwritten if product is available in PP_LOT
#15-Jul-2015 eric    : Make PRODUCT as ppid
#2015-Aug-18 jgarcia : set flat notch location based on the passed site argument.
#2015-Aug-26 gilbertm: Uppercase the lot id
=cut

package PDF::Parser::AWW;
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
WAFER_MAP = {
WAFER_ID = "01"
MAP_TYPE = "ASCII"
NULL_BIN = "."
ROWS =  111
COLUMNS = 111
FLAT_NOTCH = 0
DEVICE = "FAN48630A8_9797Z"
LOT_ID = "M000780660"
REF_DIES = 1
REF_DIE = 10,56
BINS = 12
BIN = "1" 8007 "Pass"
BIN = "3" 16 "Fail"
BIN = "4" 127 "Fail"
DIES = 9703
MAP = {
...............................................----------------................................................
..........................................--------------------------...........................................
......................................----------------------------------.......................................
...................................-------------44441111111111-------------....................................
.................................----------111111111111111111111818----------..................................
=cut

sub readFile {
    my $self   = shift;
    my $infile = shift;
    my $site   = shift;
    my $header = new_headerLong;
    $header->PROGRAM_CLASS(4);
    my $wmap  = new_wmap;
    my $model = new_model(
        {   header     => $header,
            wmap       => $wmap,
            misc       => {},
            dataSource => 'AWW'
        }
    );
    my $wafer = new_wafer;
    $model->add( 'wafers', $wafer );

    my $section = "Header";
    my $context = {};
    my ( $x, $y );
	my ( $rows, $cols );
    open( INFILE, $infile );

	my $nullBin;
	my $binCuttoff = 64;  # ignore anything above bin # 64
	$y = 0;
    while (<INFILE>) {
		s/\015//;
		chop;
		if($section eq "Header"){
			my @item = split(/\s*=\s*/);
			$item[1] =~ tr/"//d;
			if (uc($item[0]) eq "NULL_BIN"){ $nullBin = $item[1]; }
			if (uc($item[0]) eq "WAFER_ID"){ $wafer->number($item[1]); }
			if (uc($item[0]) eq "LOT_ID"){ $header->LOT(uc($item[1])); }
			if (uc($item[0]) eq "DEVICE"){ $header->PRODUCT($item[1]); }
			if (uc($item[0]) eq "ROWS"){ $rows = int($item[1]); }
			if (uc($item[0]) eq "COLUMNS"){ $cols = int($item[1]);}
			if (uc($item[0]) eq "BINS"){ $section = "Bins" ; next }
			if (uc($item[0]) eq "FLAT_NOTCH"){
			if ($site eq 'amkor_tw_ft') {
				given ($item[1]){
					when (180){$wmap->flat('T');}
					when (0){$wmap->flat('B');}
					when (360){$wmap->flat('B');}
					when (90){$wmap->flat('L');}
					when (270){$wmap->flat('R');}
					default { ERROR("invalid Flat Direction: ".$item[1]);}
				}
				
			} elsif ($site eq 'gtk_tw_sort') {
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
			# make product as ppid
			$header->PROGRAM($header->PRODUCT);
		}
		if($section eq "Bins"){
			my @item = split(/\s*=\s*/);
			if($item[0] eq "BIN"){ # BIN = "1" 8007 "Pass"
				my @binArr = split(/\s/,$item[1]);
				# bin number
				@binArr[0] =~ tr/"//d; 
				my $binNum = convertBinNumber(@binArr[0]);
				if($binNum > $binCuttoff) { next; }

				$binNum =~ tr/"//d;
				# bin name
				my $binName = "Bin_".$binNum;
				# count
				my $count = @binArr[1];
				$count =~ tr/"//d; 
				my $bin = new_bin(
                    {   number => $binNum,
                        name   => $binName,
                        count  => $count
                    }
                );
				# bin state
				my $binState = @binArr[2];
				$binState =~ tr/"//d;
				if($binState eq "Pass") { $bin->PF('P'); } else { $bin->PF('F'); }

                $wafer->add( 'bins', $bin );
			}
			if ($item[0] eq "MAP"){ $section = "Map" ; next }
		}
		if($section eq "Map"){
			if (/^}/){ last; }
			
			my @dieArray = split(//);
			for($x = 0;$x < scalar(@dieArray);$x++){
				if(@dieArray[$x] eq $nullBin){ next; }
				if(@dieArray[$x] eq '' ){ next; }
				
				
				my $bin = convertBinNumber(@dieArray[$x]);
				if($bin > $binCuttoff) { next; }
				
				my $die = new_die();
				$die->x($x);
				$die->y($y);
				$die->soft_bin($bin);
				$wafer->add( 'dies', $die );				
			}
			$y++;
		}
	}
	
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
    return $model;
}

sub convertBinNumber
{
	my $bin = shift;
	if($bin =~ '[0-9]'){ return $bin; }
	if($bin =~ '[A-V]'){ return int(ord($bin)) - 55; }
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

sub convertBinNumberFCS
{
	my $bin = shift;
	
	my $map_i_0_9   = '[0-9]' ; my $map_o_0_9   = '[\x00-\x09]' ;  	#   0- 9
	my $map_i_A_V   = '[A-V]' ; my $map_o_A_V   = '[\x0a-\x1f]' ;    #  10-31
	my $map_i_X     = '[X]'   ; my $map_o_X     = '[\x20]' ;      	#     32
	my $map_i_astx  = '[\*]'  ; my $map_o_astx  = '[\xfd]' ; 	  	#    253
	my $map_i_i     = '[i]'   ; my $map_o_i     = '[\xfd]' ;      	#    253
	my $map_i_ink1  = '[\$]'  ; my $map_o_ink1  = '[\xfd]' ;      	#    253
	my $map_i_coln  = '[\:]'  ; my $map_o_coln  = '[\xfe]' ;      	#    254
	my $map_i_ghost = '[\.]'  ; my $map_o_ghost = '[\xff]' ;      	#    255
	my $map_i_skip  = '[s]'   ; my $map_o_skip  = '[\xff]' ; 	  	#    255
	my $map_i_skip2 = '[z]'   ; my $map_o_skip2 = '[\xff]' ;         #    255
	my $map_i_skip4 = '[\-]'  ; my $map_o_skip4 = '[\xff]' ;      	#    255
	
	my $map_input  = $map_i_skip4.$map_i_skip2.$map_i_skip.$map_i_ghost.$map_i_0_9.$map_i_A_V.$map_i_astx.$map_i_i.$map_i_ink1.$map_i_coln.$map_i_X ;
	my $map_output = $map_o_skip4.$map_o_skip2.$map_o_skip.$map_o_ghost.$map_o_0_9.$map_o_A_V.$map_o_astx.$map_o_i.$map_o_ink1.$map_o_coln.$map_o_X ;
	my $tr_cmd     = "\$bin =~ tr /$map_input/$map_output/" ;
	eval $tr_cmd ; # Convert the bins from NAM format to Numeric 

	return ($bin) ;
}
1;

