#CHANGES
#
=head1 CHANGES

	2015/07/14 grace : set EQUIP1_ID with the last line in the file 
	2015-Aug-26 gilbert : uppercase the lot id.
	2016-Jan-5 eric	: extract correct wafer number.
	2016-Jul-12 eric : change x-offset to positive for quadrant 1 & 4 for 4-panel maps.
=cut

package PDF::Parser::TESEC;
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
H013956780,H013956780,AF51696,STANDARD
UMLP 1.6x1.6 (SINGLEDAP),8,23,23
171529,-67418,129631,-67287,171410,-109339,129499,-109221
1,1,1,1,3,1,1,1,1,1,1,1,1,3,1,1,1,1,3,1,4,1,1
1,1,1,4,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,4,1,1
1,1,1,1,1,1,4,1,3,4,1,1,1,1,1,1,1,1,1,1,1,1,1
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
1,1,1,3,4,1,4,1,1,1,1,1,1,1,1,1,1,1,4,1,1,1,1
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
1,1,1,1,1,1,1,1,1,4,1,1,1,1,1,1,1,1,1,1,1,1,1
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,4,1
1,1,1,1,1,1,1,3,1,1,4,1,1,1,1,1,1,1,1,1,1,1,1
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
1,1,4,1,1,1,1,1,1,1,1,4,1,1,1,1,1,1,1,1,1,1,1
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
1,1,3,1,1,1,4,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
1,1,1,1,1,1,4,1,1,1,1,1,1,1,1,1,1,1,3,1,1,1,1
1,1,1,4,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1

=cut


###################
# GLOBAL VARIABLES
###################
my $file        = "";
my $plant       = uc($ENV{ENV_FACILITY});     ### MFT ENV VAR
my $env_mod     = "";
my $mft_flag    = ($^O=~/linux/i) ? 1 : 0; 	### SET 0=OTHERS; 1=LINUX/MFT
my $envname     = "PMFTWMTESEC";
my $lotid       = "";
my $sublotid    = "";
my $ring_id     = "";
my $waferid     = "";
my $map_type    = "STD"; 	### HANDLER MAPS ARE "STD" WHILE PICKER IS "SORT". LOADING HANDLER MAPS ONLY
my $test_mode   = "";
my $pkg_name    = "";
my $die_size    = "";
my $plate_count = "";
my $row_count   = "";
my $col_count   = "";
my %hbin	= ();
my %hbin_rtst   = ();
my %hbin_name   = ("1"=>"GOOD PART","2"=>"QA TEST FAILS");
my %strip_map       = ();
my $total_col_count = 0;
my $total_row_count = 0;
my $map_data        = "";
my $map_data_rtst   = "";
my $retest_flag     = "P";		### P=NEW TEST; R=RESTEST
my %mapval          = (0=>0,1=>1,2=>2,3=>3,4=>4,5=>5,6=>6,7=>7,8=>8,9=>9,10=>'A',11=>'B',12=>'C',13=>'D',14=>'E',15=>'F',16=>'G',17=>'H',18=>'I',19=>'J',20=>'K',21=>'L',22=>'M',23=>'N',24=>'O',25=>'P',26=>'Q',27=>'R',28=>'S',29=>'T',30=>'U',31=>'V',32=>'X');
my $eqptid          = "";
my $td_filename     = "";
my $td_filenames    = "";
my $bin_number = 0;
my @good_bins = ();
my $line = "";
my ($die_unit, $addr, $bin, $dump);


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
            dataSource => 'TESEC'
        }
    	);
    	my $wafer = new_wafer;
    	$model->add( 'wafers', $wafer );
	
	# LOCAL VARIABLES
	my $x  	        = 0; 	### TOP RIGHT X COORDINATE
	my $y           = 0;	### TOP RIGHT Y COORDINATE
	my $row_num     = 0;
	my $row_offset  = 0;
	my $read_plates = 0;
	my $line_num    = 1;
	my $xoffset     = 0;
	my $yoffset     = 0;
	my @lower_range = ();
	my @upper_range = ();

   	open( INFILE, $infile );	
	
	if($infile =~ /([\d][\d]).CSV/)
	{	
		$wafer->number($1);
	}
	
	my $dummy 	 = `grep HANDLER $infile`;
	chomp($dummy);
	my ($dump, $eqptid) = split /\,/, $dummy;
	$eqptid          =~ s/ //g;
	$eqptid          = uc $eqptid;

        # FILE PARSING
	my $line_num = 1;
        
        while($line=<INFILE>)
        {
                chomp($line);
                $line        =~ s/\cM//;
                $line        =~ s/^\s|\s$//g;
		my (@dummy)  = split /\,/, $line;

		if ($line_num == 1)
		{
			$lotid     = uc($dummy[0]);
			$sublotid  = uc($dummy[1]);
			$ring_id   = uc($dummy[2]);
			$test_mode = uc($dummy[3]);
			
			$header->LOT(uc($lotid));
			$header->REVISION(1);
			$header->EQUIP1_ID($eqptid);
			$header->EQUIP5_ID($ring_id);
			$wafer->name($ring_id);

			### UTILIZE RINGID AS WAFERID BUT W/O THE CHAR ###
			$waferid = $ring_id;
			$waferid =~ s/\D//gi;
			if ($waferid eq "" || $waferid !~ /\d/)
			{
				print "Error: failed to derive a valid waferid value from the ringid \"$ring_id\"\n";
				exit 1;
			}
			$waferid = substr($waferid, length($waferid) - 2) if $waferid > 254;
			$waferid = int($waferid);
			$wafer->number($waferid);
		}
		elsif ($line_num == 2)
		{
			my ($pkg_name,$die_size, $dump) = split /\(|\)/, $dummy[0];
			$die_size    =~ /([a-z]{1,})$/i;
			$die_unit    = $1;
			$die_size    =~ s/$die_unit//g;
			$die_size = "0" if $die_size == "";  ## 0 indicates missing/invalid (cannot be blank)
			$pkg_name    = uc($pkg_name);
			$pkg_name    =~ s/^\s+|\s+$//g;
			$pkg_name    =~ s/\s+/\_/g;
			$header->PROGRAM($pkg_name);
			$plate_count = $dummy[1];
			$col_count   = $dummy[2];
			$row_count   = $dummy[3];
			
			INFO($die_size."/".$die_unit);

			# PLATE IS ALWAYS ARRANGED IN 2X4. SO FORM A 2X4 ARRAY 
			$total_col_count = (4 * $col_count) + 3;   
			$total_row_count = (2 * $row_count) + 1;
			
			$wmap->wf_size($die_size);
			$wmap->wf_units(3);
			$wmap->reticle_rows($total_row_count);
			$wmap->reticle_cols($total_col_count);
			$wmap->positive_x('R');
			$wmap->positive_y('D');
			$wmap->device_count( $col_count * $row_count );		
			$wmap->flat('T');
			$wmap->flat_type('F');
			$wmap->die_width( $die_size );
		    	$wmap->die_height( $die_size );
			my $stats = $wafer->stats;
			$wmap->convertDieSizeToMM( $wmap->wf_units, $stats );
			#$wmap->calcCenterDie($stats);
			$wmap->center_x(0);
			$wmap->center_y(0);
		}
		# GET "TOP RIGHT COORDINATES" ONLY
		elsif ($line_num == 3 || $line_num == (2 + ($read_plates * $row_count * 3) + ($read_plates + 1))) 
		{
			last if $dummy[0] eq "" || $dummy[1] eq "";			
						
			$read_plates++;
			$row_num = 0;

			if ($plate_count == 4 && ($read_plates == 1 || $read_plates == 4)) {
				if ($dummy[0] =~ /^\-/) {
					$dummy[0] = $dummy[0] * -1;
				}
			}
			
			### AUTO-COMPUTE THE STARTING COLUMN OF THE STRIP_MAP ARRAY. STARTS W/ THE RIGHTMOST PLATE ###
			#my $plate_x_loc = ($read_plates < 5) ? $read_plates : $read_plates - 4;
			#$xoffset = $total_col_count - ($plate_x_loc * $col_count) - ($plate_x_loc - 1);
			### AUTO-COMPUTE THE STARTING ROW IN THE STRIP_MAP ARRAY. STARTS W/ THE TOPMOST PLATE ###
			#$yoffset = $row_count + 1 if $read_plates == 5;

			### DETECT PLATE's COLUMN(X) LOCATION THRU TOP_RIGHT_X COORDINATE ###
			if ($dummy[0] < 1000)
			{
				$xoffset = 0;
			}
			elsif ($dummy[0] < 60000)
			{
				$xoffset = $col_count + 1;
			}
			elsif ($dummy[0] < 120000)
			{
				$xoffset = ($col_count * 2) + 2;
			}
			elsif ($dummy[0] < 190000)
			{
				$xoffset = ($col_count * 3) + 3;
			}

			### DETECT PLATE's COLUMN(Y) LOCATION THRU TOP_RIGHT_Y COORDINATE ###
                        if ($dummy[1] > -100000)
                        {
                                $yoffset = 0;
                        }
                        elsif ($dummy[1] < -100000)
                        {
                                $yoffset = $row_count + 1;
                        }
			
			#print "plate=$read_plates\txoffset=$xoffset\tyoffset=$yoffset\ttrx=$dummy[0]\ttry=$dummy[1]\n";
			$wmap->reticle_row_offset($xoffset);
			$wmap->reticle_col_offset($yoffset);

		}	
		# STORE MAP TO ARRAY
		elsif ($col_count == scalar(@dummy) && $row_num < $row_count)
		{

			@dummy = reverse @dummy;

			if($dummy[0] == 129) {
				$bin_number = 129 - 108;
			}

			for(my $i=0; $i <= $#dummy; $i++)
			{
				### SET RETEST FLAG ###
				$retest_flag = "R" if $dummy[$i] >= 128;
	
				### TRAP UNEXPECTED HBIN NUMBERS ###
				if ($dummy[$i] < 0 || ($dummy[$i] > 32 && $dummy[$i] < 128) || $dummy[$i] > 160)
				{
					print "Error: Invalid hbin number \"$dummy[$i]\"\n";
					exit 1;
				}

				### UPDATE STRIP_MAP ARRAY WITH CORRECT BIN NUMBER ###
				#${$strip_map[$yoffset + $row_num]}[$i + $xoffset] = $dummy[$i];
				#$strip_map{$i + $xoffset}{$yoffset + $row_num} = $dummy[$i];				
				$strip_map{$yoffset + $row_num}{$i + $xoffset} = $dummy[$i];				
				
			}
			$row_num++;

		}
		else
		{
			$row_num++;
		}

		$line_num++;
	}
	close(INFILE);

	my %hbin = ();
	foreach my $xxx (sort keys  %strip_map)
	{
		foreach my $yyy(sort keys  $strip_map{$xxx}){
			my $die = new_die();
			$die->x($yyy);
			$die->y($xxx);
			$die->soft_bin($strip_map{$xxx}{$yyy});
			$wafer->add( 'dies', $die );
			if(defined  $hbin{$strip_map{$xxx}{$yyy}}){
				$hbin{$strip_map{$xxx}{$yyy}}++;				
			}
			else{
				$hbin{$strip_map{$xxx}{$yyy}} = 1;
			}
		}
	}
	
	foreach my $key (sort keys %hbin){
		my $bin_pf = "F";
		my $binNum;
		my $binName;
		my $count = $hbin{$key};
		
		if($key == 1){
			$bin_pf = "P";		
		}
		$binName = "Bin".$key;
		$binNum = $key;
		
		my $bin = new_bin(
                    {   number => $binNum,
                        name   => $binName,
                        count  => $count,
			PF     => $bin_pf
                    }
                );				

                $wafer->add( 'hbins', $bin );
	}
    	return $model;
}

1;
