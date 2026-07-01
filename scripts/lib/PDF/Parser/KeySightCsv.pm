# 09-Dec-2019 Eric Alfanta	: Original
package PDF::Parser::KeySightCsv;

use strict;
use PDF::Log;
use PDF::DpData;
use PDF::DpLoad;
use PDF::WS;
use Data::Dumper;
use File::Basename qw/basename dirname/;
use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}

__PACKAGE__->mk_accessors(array);


sub parseFile {
	my $self = shift;
	my $infile = shift;
	my $config = shift;
	my $retdir = $config->{retwaf}->{dir};
	my $fname = basename $infile;
	my %td;
	my %seen;
	my $dup_cnt = 0;
	my $lotid = "";
	my $subconlot = "";
	my $subconprod = "";
	my $rev = "";
	my $cust_prod_name = "";
	my $prod_id = "";
	my $prod = "";
	my $pn = "";
	my $customer_pn = "";
	my $equip1 = "";
	my $temperature = "";
	my $technology = "";
	my @pnp1;
	my @pnp2;
	my @pnp2cnt;
	my $hdr_flg = 0;
	my $wfr_flg = 0;
	my $llm_flg = 0;
	my $hlm_flg = 0;
	my $pnp_flg = 0;
	my $sct_flg = 0;
	my $ptr_flg = 0;
	my $tnu_flg = 0;
	my $tna_flg = 0;
	my $unt_flg = 0;
	my $res_flg = 0;
	my $totalparamcnt = 0;
	my $new_fmt_flg = "N";
	my $tnum_flg = "N";
	my $fab = "UV5:GF%FISHKILL%FE%CTI";

	my @tname;
	my @tunit;
	my @tnumb;
	my @hilim;
	my @lolim;
	my @tcond;

	my @csv_xy = ();
        my @ret_xy = ();

	INFO("Reticle Directory = $retdir");
	if (-d $retdir) {
		INFO("Reticle Directory found.");
	}
	else {
		dpExit(1,"Reticle Directory does not exists.");	
	}

	my $header = new_onheaderLong;
        my $wmap = new_wmap;
        my $model = new_model({ header => $header, wmap => $wmap, dataSource => 'KEYSIGHT', misc => {} });	
	
	open( FH, $infile );
    	while (my $line = <FH>) {
		next if $line !~ /\w+/;
		if ($line =~ /^Customer|^PN|^Lot Id|^UL|^CLL|^Timestamp|^Fab|^Technology|^Product|^Test|^Equipment|^Parameter|^Temperature|^Flat Orientation|^Wafer Count/i){
			$hdr_flg = 1;
			$wfr_flg = 0;
			$pnp_flg = 0;
			$sct_flg = 0;
			$ptr_flg = 0;
			$tnu_flg = 0;
			$tna_flg = 0;
			$unt_flg = 0;
			$res_flg = 0;
			$llm_flg = 0;
			$hlm_flg = 0;
		}
		#elsif ($line =~ /PNP\,\d+/i) {
		elsif ($line =~ /PNP\,\d+i|PNP\,\w+/i) {
			$hdr_flg = 0;
			$wfr_flg = 0;
			$pnp_flg = 1;
			$sct_flg = 0;
			$ptr_flg = 0;
			$tnu_flg = 0;
			$tna_flg = 0;
			$unt_flg = 0;
			$res_flg = 0;
			$llm_flg = 0;
			$hlm_flg = 0;
		}
		elsif ($line =~ /SiteCount\,\d+/i) {
			$hdr_flg = 0;
			$wfr_flg = 0;
			$pnp_flg = 0;
			$sct_flg = 1;
			$ptr_flg = 0;
			$tnu_flg = 0;
			$tna_flg = 0;
			$unt_flg = 0;
			$res_flg = 0;
			$llm_flg = 0;
			$hlm_flg = 0;
		}
		elsif ($line =~ /Parameter\,\d+|ParameterCount\,\d+/i) {
			$hdr_flg = 0;
			$wfr_flg = 0;
			$pnp_flg = 0;
			$sct_flg = 0;
			$ptr_flg = 1;
			$tnu_flg = 0;
			$tna_flg = 0;
			$unt_flg = 0;
			$res_flg = 0;
			$llm_flg = 0;
			$hlm_flg = 0;
		}
		elsif($line =~ /^Wafer\,|^Vendor/i) {
			$hdr_flg = 0;
			$wfr_flg = 0;
			$pnp_flg = 0;
			$sct_flg = 0;
			$ptr_flg = 0;
			$tnu_flg = 0;
			$tna_flg = 1;
			$unt_flg = 0;
			$res_flg = 0;
			$llm_flg = 0;
			$hlm_flg = 0;
		}
		elsif($line =~ /Test Number\,/i) {
			$hdr_flg = 0;
			$wfr_flg = 0;
			$pnp_flg = 0;
			$sct_flg = 0;
			$ptr_flg = 0;
			$tnu_flg = 1;
			$tna_flg = 0;
			$unt_flg = 0;
			$res_flg = 0;
			$llm_flg = 0;
			$hlm_flg = 0;
			$tnum_flg = "Y";
		}
		elsif ($line =~ /Units\,|Unit\,/i) {
			$hdr_flg = 0;
			$wfr_flg = 0;
			$pnp_flg = 0;
			$sct_flg = 0;
			$ptr_flg = 0;
			$tnu_flg = 0;
			$tna_flg = 0;
			$unt_flg = 1;
			$res_flg = 0;
			$llm_flg = 0;
			$hlm_flg = 0;
		}
		elsif ($line =~ /^SPEC HIGH\,/i) {
			$hdr_flg = 0;
			$wfr_flg = 0;
			$pnp_flg = 0;
			$sct_flg = 0;
			$ptr_flg = 0;
			$tnu_flg = 0;
			$tna_flg = 0;
			$unt_flg = 0;
			$res_flg = 0;
			$llm_flg = 0;
			$hlm_flg = 1;
		}
		elsif ($line =~ /^SPEC LOW\,/i) {
			$hdr_flg = 0;
			$wfr_flg = 0;
			$pnp_flg = 0;
			$sct_flg = 0;
			$ptr_flg = 0;
			$tnu_flg = 0;
			$tna_flg = 0;
			$unt_flg = 0;
			$res_flg = 0;
			$llm_flg = 1;
			$hlm_flg = 0;
		}
		elsif ($line =~ /^MAX|^MIN|^AVG|^MEDIAN|^STDEV|^STDDEV|^TARGET|^CENSOR HIGH|^CENSOR LOW|^CEMSOR LOW/i) {
			$hdr_flg = 0;
			$wfr_flg = 0;
			$pnp_flg = 0;
			$sct_flg = 0;
			$ptr_flg = 0;
			$tnu_flg = 0;
			$tna_flg = 0;
			$unt_flg = 0;
			$res_flg = 0;
			$llm_flg = 0;
			$hlm_flg = 0;
		}
		else {
			$hdr_flg = 0;
			$wfr_flg = 0;
			$pnp_flg = 0;
			$sct_flg = 0;
			$ptr_flg = 0;
			$tnu_flg = 0;
			$tna_flg = 0;
			$unt_flg = 0;
			$res_flg = 1;
			$llm_flg = 0;
			$hlm_flg = 0;
		}
				
		if ($hdr_flg == 1) {			
			my @item = split /\,/, $line;			
			$item[0] = trim(uc($item[0]));				
			$item[1] = trim(uc($item[1]));
			$item[0] =~ s/\(|\)//ig;
			$item[0] =~ s/\s/\_/ig;

			if ($item[0] =~ /^PN/i) {
				$pn = trim($item[1]);
			}
			elsif ($item[0] =~ /^Customer_PN/i) {
				$customer_pn = trim($item[1]);
				my @arr  = split /\./, $customer_pn;
				$customer_pn = substr $arr[0], -7;
				$header->PRODUCT($customer_pn);
			}
			elsif ($item[0] =~ /^Customer_Product_Name/i) {
				$cust_prod_name = trim($item[1]);
				$new_fmt_flg = "Y";
			}				
			elsif ($item[0] =~ /^Lot_id/i) {
				$lotid = trim($item[1]);
				$header->LOT(uc($lotid));
			}
			elsif ($item[0] =~ /^Ull/i) {
				$subconlot = trim($item[1]);
				#$header->SUBCON_LOT(uc($subconlot))	
				#$header->SUBCON_LOTID(uc($subconlot));
			}
			elsif ($item[0] =~ /^Timestamp_start/i) {
				my $new_date = formatDate($item[1]);
				$header->START_TIME($new_date);
			}
			elsif ($item[0] =~ /^Timestamp_end/i) {
				my $new_date = formatDate($item[1]);
				$header->END_TIME($new_date);
			}
			elsif ($item[0] =~ /^Fab/i) {
				#$fab = trim($item[1]);
				#$header->FAB($fab);
			}
			elsif ($item[0] =~ /^Equipment_id/i) {
				$equip1 = trim($item[1]);
				#$header->EQUIP1_ID($equip1);
				$header->TESTER_HOSTNAME($equip1);
			}
			elsif ($item[0] =~ /^Temperature/i) {
				#$header->EQUIP5_ID($item[1]);
				$temperature = trim($item[1]);
				$header->TEMPERATURE($temperature);
			}
			elsif ($item[0] =~ /^Product$/i) {
				#$header->PRODUCT($item[1]);
				$prod = trim($item[1]);
				$model->misc->{prod} = $item[1];
				#$header->SUBCON_PRODUCT(uc($prod));
			}
			elsif ($item[0] =~ /^Technology/i) {
				$technology = trim($item[1]);
				$header->PROGRAM(uc($technology));
				$model->misc->{tech} = $technology;
				#$header->TECHNOLOGY($technology);
			}
			elsif ($item[0] =~ /^Product_id/i) {
				$prod_id = trim(uc($item[1]));
			}
			elsif ($item[0] =~ /^Test_Prog_EC/i) {
				$rev = trim($item[1]);
				$header->REVISION($rev);
			}
			elsif ($item[0] =~ /^Test_Program/i) {
				for (my $j=1; $j<=$#item; $j++) { #start at next element						
					$item[$j] = trim($item[$j]);
					next if $item[$j] eq "";
					push @pnp1, $item[$j];
				}				
			}
			
		}
		
		if ($pnp_flg == 1) {			
			my @item = split /\,/, $line;
			for (my $i=0; $i<=$#item; $i++) {
				$item[$i] = trim($item[$i]);
				next if $item[$i] eq "";
				if ($item[$i] eq "PNP") {
					push @pnp2, $item[$i+1];
				}
			}					
		}
		
		if ($ptr_flg == 1) {			
			my @item = split /\,/, $line;
			my $j = 0;
			for (my $i=0; $i<=$#item; $i++) {
				$item[$i] = trim($item[$i]);
				next if $item[$i] eq "";
				if ($item[$i] eq "Parameter" || $item[$i] eq "ParameterCount") {	
					$totalparamcnt = $totalparamcnt + $item[$i+1];
					push @pnp2cnt, $item[$i+1];
					$j++;
				}
			}
		}
		
		if ($tna_flg == 1) {						
			my @item = split /\,/, $line;
			my @tmp_param;
			for (my $i=0; $i<=$#item; $i++) {
				$item[$i] = trim($item[$i]);
				next if $item[$i] =~ m/^Wafer$|^SlotId$|^Pass\/Fail$|^SiteID$|^Site_X$|^Site_Y$|^Vendor Wafer Scribe ID$|^Wafer ID\/Alias$/i;
				push @tmp_param, $item[$i]
			}		
			for (my $i=0; $i<=$#pnp2; $i++) {
				my @tmp = splice (@tmp_param, 0, $pnp2cnt[$i]);				
				foreach my $e (@tmp){
					$e = trim($e);
					$e = repNA($e);
					push @tname, $e;
					push @tcond, $pnp2[$i];
				}
			}
		}
		
		if ($tnu_flg == 1) {			
			my @item = split /\,/, $line;
			my $dump = 6;  #6 represent first six columns
			for (my $i=0; $i<=$#pnp2; $i++) {
				my @tmp;
				if ($i == 0) {
					@tmp = splice (@item, $dump, $pnp2cnt[$i]);					
				}
				else {
					$dump = $dump + 2; #2 represent  site xy of next tp 
					@tmp = splice (@item, $dump, $pnp2cnt[$i]);					
				}	
				foreach my $e (@tmp){
					$e = trim($e);
					$e = repNA($e);
					push @tnumb, $e;
				}									
			}
		}
		
		if ($unt_flg == 1) {			
			my @item = split /\,/, $line;
			my $dump = 6;  #6 represent first six columns
			for (my $i=0; $i<=$#pnp2; $i++) {
				my @tmp;
				if ($i == 0) {
					@tmp = splice (@item, $dump, $pnp2cnt[$i]);					
				}
				else {
					$dump = $dump + 2; #2 represent  site xy of next tp 
					@tmp = splice (@item, $dump, $pnp2cnt[$i]);					
				}				 
				foreach my $e (@tmp){
					$e = trim($e);
					$e = repNA($e);
					push @tunit, $e;
				}								
			}
		}
		
		if ($hlm_flg == 1) {			
			my @item = split /\,/, $line;
			my $dump = 6;  #6 represent first six columns
			for (my $i=0; $i<=$#pnp2; $i++) {
				my @tmp;
				if ($i == 0) {
					@tmp = splice (@item, $dump, $pnp2cnt[$i]);					
				}
				else {
					$dump = $dump + 2; #2 represent  site xy of next tp 
					@tmp = splice (@item, $dump, $pnp2cnt[$i]);					
				}				 
				foreach my $e (@tmp){
					$e = trim($e);
					$e = repNA($e);
					#push @arr, $e;
					push @hilim, $e;
				}				
			}
		}
		
		if ($llm_flg == 1) {			
			my @item = split /\,/, $line;
			my $dump = 6;  #6 represent first six columns
			for (my $i=0; $i<=$#pnp2; $i++) {
				my @tmp;
				if ($i == 0) {
					@tmp = splice (@item, $dump, $pnp2cnt[$i]);					
				}
				else {
					$dump = $dump + 2; #2 represent  site xy of next tp 
					@tmp = splice (@item, $dump, $pnp2cnt[$i]);					
				}		
				foreach my $e (@tmp){
					$e = trim($e);
					$e = repNA($e);
					push @lolim, $e;
				}				
			}
		}
		
		if ($res_flg == 1) {			
			my @item = split /\,/, $line;
			my $wfr = shift @item;
			my $slotid = shift @item;
			my $pf = shift @item;
			my $site = shift @item;
			$wfr 	= trim($wfr);
			$slotid = trim($slotid);
			$pf 	= trim($pf);
			$site 	= trim($site);
			my $x = "";
			my $y = "";
			my @arr2;

			if ($slotid eq "") {
				#$slotid = "NULL";
				$slotid = "NA";
				my $msg = "SLOTID is missing for WAFER = $wfr.";
				WARN($msg);
				WARN("SLOTID will be replaced with NA");
				#$model->misc->{msg} = $msg;
			}

			for (my $i=0; $i<=$#pnp2; $i++) {
				my @tmp;	
				if ($i == 0) {
					$x = shift @item;
					$y = shift @item;
					@tmp = splice (@item, 0, $pnp2cnt[$i]);
				}
				else {
					$x = shift @item;
					$y = shift @item;
					@tmp = splice (@item, 0, $pnp2cnt[$i]);
				}
				$x = trim($x);
				$y = trim($y);

				next if ($x eq "" && $y eq "");

				for (my $j=1; $j<=$pnp2cnt[$i]; $j++) {
					$tmp[$j-1] = trim($tmp[$j-1]);
					$tmp[$j-1] = repNA($tmp[$j-1]);
					push @arr2, $tmp[$j-1];
				}	

			}
			
			$td{$wfr}{$slotid}{$site} = {
						pf => $pf,
                                                x => $x,
                                                y => $y,
                                                res => \@arr2
			};

			push @csv_xy, "x".$x."y".$y;
		}
	}
	close FH;

	#GET PRODUCT FROM OTHERS SOURCES IF ""
	if ($customer_pn eq "") {
		my @arr = split /\./, $pn;
		if ($arr[0] ne "") {
			$arr[0] = substr $arr[0], -7;
			$header->PRODUCT($arr[0]);		
		}
		else { #POSSIBELY NEW FORMAT
			my @arr = split /\./, $cust_prod_name;
			$arr[0] = substr $arr[0], -7;	
			$header->PRODUCT($arr[0]);
		}
	}

	#NEW CSV FORMAT
	#if ($new_fmt_flg eq "Y") {
	#	my $fname = basename $infile;
	#	my @item = split/\_/, $fname;
	#	my $fn_lotid = $item[3];
	#	if ($fn_lotid eq "") {   #some dont follow filenaming ocnvention
	#		$fn_lotid = $lotid
	#	}
	#	$header->LOT($fn_lotid);
		#$header->SUBCON_LOTID($lotid);
		#$header->SUBCON_PRODUCT($cust_prod_name);
	#}

	my $test_program = join ' ',@pnp1;
	$header->RECIPE($test_program);

	my $waf_regexp = "";
	my $ret_regexp = "";
	
	#$ret_regexp = "${pn}.ret";
	#$waf_regexp = "${pn}.waf"; 

	#INFO("WAF/RET file search pattern = $pn");

	
	my $ret_file = "";
	my $waf_file = "";

	if ($pn ne "") {
		$ret_regexp = "${pn}.ret";
	        $waf_regexp = "${pn}.waf";

		INFO("WAF/RET file search pattern using PN = $pn");
		foreach my $file (glob "$retdir/*"){
			if ($file =~ /$ret_regexp/i) {
				INFO("RET Found : $file");
				$ret_file = $file;
				$ret_file = trim($ret_file);
			}
			elsif ($file =~ /$waf_regexp/i) {
				INFO("WAF Found : $file");
				$waf_file = $file;
				$waf_file = trim($waf_file);	
			}
		}
	}
	#Try using prod id to search for RET/WAF file if nof found
	else {#($ret_file eq "" && $waf_file eq "") {
		$ret_regexp = "${prod_id}.ret";
		$waf_regexp = "${prod_id}.waf";
		INFO("WAF/RET file search pattern using PRODUCT ID = $prod_id");

		foreach my $file (glob "$retdir/*"){
			if ($file =~ /$ret_regexp/i) {
				INFO("RET Found : $file");
				$ret_file = $file;
				$ret_file = trim($ret_file);
			}
			elsif ($file =~ /$waf_regexp/i) {
				INFO("WAF Found : $file");
				$waf_file = $file;
				$waf_file = trim($waf_file);
			}
		}
	}


	my $die_flg = 0;
        my %RETXY;
        open RET, $ret_file;
        while (my $line=<RET>) {
                chomp $line;
                if ($line =~ /^#BEGIN_DIE_KERF/i) {
                        $die_flg = 1;
                }
                elsif ($line =~ /^#END_DIE_KERF/i) {
                        $die_flg = 0;
                }
                if ($die_flg == 1) {
                        next if ($line =~ /^\#/);
                        my ($x1, $y1, $x2, $y2) = split /\s+/, $line;

			$RETXY{$x2}{$y2} = {
				org_x => $x1,
				org_y => $y1
			};	

			push @ret_xy, "x".$x2."y".$y2;
                }
        }
        close RET;		


	my $attrib_flg = 0;
	my $size = "";
	my $wfunit = "";
	my $flat_position =  "";
	my $coordinate = "";
	my $stepx = "";
	my $stepy = "";
	my $stepx_unit = "";
	my $stepy_unit = "";
	my $centerdiex = "";
	my $centerdiey = "";
	my $offsetdiex = "";
	my $offsetdiey = "";

	open WAF, $waf_file;
	while (my $line=<WAF>) {
		chomp $line;
		if ($line =~ /ATTRIBUTE/i) {
			$attrib_flg = 1;
		}
		elsif ($line =~ /BODY/i) {
			$attrib_flg = 0;
		}
		
		if ($attrib_flg == 1) {
			my @item = split /\=|\,|\s+/, $line;
			if ($item[1] eq "SIZE") {
				$size = $item[4];
				$wfunit = $item[3];
				$wfunit =~ s/\"//ig;
			}
			elsif($item[1] eq "STEPX") {
				$stepx_unit = $item[3];
				$stepx_unit =~ s/\"//ig;
				if ($wfunit eq "mm") {
					$stepx = $item[4]/1000;
				}
				elsif ($stepx_unit eq "um") {
					$stepx = $item[4];
				}
                        }
			elsif($item[1] eq "STEPY") {
				$stepy_unit = $item[3];
				$stepy_unit =~ s/\"//ig;
				if ($wfunit eq "mm") {
					$stepy = $item[4]/1000;
				}
				elsif ($stepx_unit eq "um") {
					$stepy = $item[4];
				}
                        }
			elsif($item[1] eq "FLAT") {
				$flat_position = $item[4];
                        }
			elsif($item[1] eq "CENTERDIEX") {
				$centerdiex = $item[3];
                        }	
			elsif($item[1] eq "CENTERDIEY") {
				$centerdiey = $item[3];
                        }
			elsif($item[1] eq "OFFSETDIEX") {
				$offsetdiex = $item[4];	
                        }
			elsif($item[1] eq "OFFSETDIEY") {
				$offsetdiey = $item[4];
                        }
			elsif($item[1] eq "COORDINATE") {
				$coordinate = $item[3];
                        }

		}
	}
	close WAF;


	my $wmc_flg = "N";
	my $xy_flg = "N";
        if ($ret_file ne "" && $waf_file ne "") {

                for (my $i=0; $i<=$#csv_xy; $i++) {
                        if (my ($matched) = grep $_ eq $csv_xy[$i], @ret_xy) {
                                $wmc_flg = "Y";
				$xy_flg = "Y";
                        }
                        else {
                                WARN("$csv_xy[$i] coordinates not found in RET File.");
                                $wmc_flg = "N";
				$xy_flg = "N";
                                last;
                        }

                }

                if ($wmc_flg eq "N") {
			if ($pn ne "") {
                        #	$header->PROGRAM($header->{PROGRAM}.":".$pn.":"."UNV");
			}
			else {
			#	$header->PROGRAM($header->{PROGRAM}.":".$prod_id.":"."UNV");
			}
                }
                else {
                        $wmc_flg = "Y";
			if ($pn ne "") {
                        #	$header->PROGRAM($header->{PROGRAM}.":".$pn);
			}
			else {
			#	$header->PROGRAM($header->{PROGRAM}.":".$prod_id);
			}
                }
        }
        else {
		if ($pn ne "") {
               	#	$header->PROGRAM($header->{PROGRAM}.":".$pn.":"."UNV");
		}
		else {
		#	$header->PROGRAM($header->{PROGRAM}.":".$prod_id.":"."UNV");
		}
        }	

	#WMC
	my $centerx = "";
	my $centery = "";
	my $positivex = "";
	my $positivey = "";
	my $flat = "";
	my $flattype = "";
	my $retrow = "";
	my $retcol = "";

	if ($wmc_flg eq "Y") {
		($centerx,$centery) = calcCenterXY($centerdiex,$centerdiey,$stepx,$stepy,$offsetdiex,$offsetdiey);
        	($positivex,$positivey) = calcPositiveXY($coordinate);
        	$flat = calcFlat($flat_position);
        	$flattype = "N";
        	$retrow = 1;
        	$retcol = 1;


        	$wmap->wf_units($wfunit);
        	$wmap->wf_size($size);
        	$wmap->flat_type($flattype);
        	$wmap->flat($flat);
        	$wmap->die_width($stepx);
        	$wmap->die_height($stepy);
        	$wmap->center_x($centerx);
        	$wmap->center_y($centery);
        	$wmap->positive_x($positivex);
        	$wmap->positive_y($positivey);
        	$wmap->reticle_rows($retrow);
        	$wmap->reticle_cols($retcol);
        	$wmap->reticle_row_offset($offsetdiex);
        	$wmap->reticle_col_offset($offsetdiey);
	}

	#INFO("WF_UNITS=$wfunit");
        #INFO("WF_SIZE=$size");
        #INFO("FLAT_TYPE=$flattype");
        #INFO("FLAT=$flat");
        #INFO("DIE_WIDTH=$stepx");
        #INFO("DIE_HEIGHT=$stepy");
        #INFO("CENTER_X=$centerx");
        #INFO("CENTER_Y=$centery");
        #INFO("POSITIVE_X=$positivex");
        #INFO("POSITIVE_Y=$positivey");
        #INFO("RETICLE_ROWS=$retrow");
        #INFO("RETICLE_COLS=$retcol");
        #INFO("RETICLE_ROW_OFFSET=$offsetdiex");
        #INFO("RETICLE_COL_OFFSET=$offsetdiey");

	# Trap
	if ($lotid eq "") {
		my $msg = "Missing LOTID";
		ERROR($msg);
		$model->misc->{msg} = $msg;
	}
	if ($ret_file eq "") {
		my $msg = "Missing RET file";
		ERROR($msg);
                #$model->misc->{msg} = $msg;
	} 
	if ($waf_file eq "") {
		my $msg = "Missing WAF file";
		ERROR($msg);
		#$model->misc->{msg} = $msg;
	}
	if ($xy_flg eq "N") {
		my $msg = "Missing XY Coordinates in RET file";
		ERROR($msg);
		#$model->misc->{msg} = $msg;
	}
	if ($tnum_flg eq "N"){
		my $msg = "Missing TEST NUMBERS";
		ERROR($msg);
		#$model->misc->{msg} = $msg;
	}

	for (my $i=0; $i<=$#tname; $i++) {
		my $test = new_test;
		$test->name($tname[$i]);
		$test->number($tnumb[$i]);
		$test->units($tunit[$i]);
		$test->HSL($hilim[$i]);
		$test->LSL($lolim[$i]);
		$test->group($tcond[$i]);
		$model->add('tests',$test);
	}

	my $wafer;
	my $custindex;
	foreach my $wfr_nam (keys %td) {
		foreach my $sub_lot (keys %{$td{$wfr_nam}}) {
			my $waferNum = "";
			if ($wfr_nam ne "") {
				my @dump = split /\_/, $wfr_nam;
				INFO("Searching metadata in ONSCRIBE refdb web service for scribe : $dump[0]");
				my $onscribews = $config->{webservice}->{onscribe}.${dump[0]}."?fab=".${fab};
				my %onscribe = getMetaFromRefDbWS($onscribews);
				$waferNum = $onscribe{waferNum};
			}

			if ($waferNum ne "" && $waferNum ne "N/A")  {
				WARN("Wafer Number $waferNum does not match to Slotid $sub_lot") if ($waferNum ne $sub_lot);
				INFO("Wafer number in ONSCRIBE refDB will be used: $waferNum");
			}
			else {
				if ($sub_lot ne "NA") {
					my $msg = "Wafer Number is missing in ONSCRIBE refdb. SlotId $sub_lot will be used as Wafer Number.";
					WARN($msg);
					$model->misc->{msg} = $msg;
					$waferNum = $sub_lot;	
				}
				else {
					my $msg = "Wafer Number is missing.";
					#WARN($msg);
					$model->misc->{msg} = $msg; 
				}
			}
			#else {
			#	INFO("Good!...Wafer numaber matches to the ONSCRIBE refDB: $sub_lot");
			#	$waferNum = $sub_lot;
			#}
			
			$wafer = $model->find('wafers',{name => $wfr_nam});
			unless (defined $wafer){
                        	$wafer = new_wafer;
                                $wafer->name($wfr_nam);
                                $wafer->number($waferNum);
                                $model->add('wafers',$wafer);
                        }
	
			$custindex = new_custindexes;
			$custindex->index1($sub_lot);
			$wafer->add('custindexes',$custindex);
			
			foreach my $site (keys %{$td{$wfr_nam}{$sub_lot}}) {
				my $die = new_die;
				my $x = $td{$wfr_nam}{$sub_lot}{$site}{x};
				my $y = $td{$wfr_nam}{$sub_lot}{$site}{y};

                                $die->site($site);
				$die->x($x);
				$die->y($y);

				if ($wmc_flg eq "Y") {
                                        $die->org_x($RETXY{$x}{$y}{org_x});
                                        $die->org_y($RETXY{$x}{$y}{org_y});
                                }
                                else {
                                        $die->org_x($x);
                                        $die->org_y($y);
                                }	
				
				my $readings = $td{$wfr_nam}{$sub_lot}{$site}{res};
				
				foreach my $r (@{$readings}) {
                                	$die->add( 'result', repNA($r));
                                }
                                $wafer->add('dies',$die);
			}
		}
	}

	return $model;
}

sub calcCenterXY {
	my $centerdiex = shift;
	my $centerdiey = shift;
	my $stepx = shift;
	my $stepy = shift;
	my $offsetdiex = shift;
	my $offsetdiey = shift;

	my $centerx = $centerdiex + ($offsetdiex / $stepx);
	my $centery = $centerdiey + ($offsetdiey / $stepy);

	return ($centerx, $centery);
}

sub calcPositiveXY {
	my $coordinate = shift;
	my $positivex = "";
	my $positivey = "";

	if ($coordinate == 1) {
		$positivex = "L";
		$positivey = "D";
	}
	elsif ($coordinate == 2) {
                $positivex = "R";
                $positivey = "D";
        }
	elsif ($coordinate == 3) {
                $positivex = "R";
                $positivey = "U";
        }
	elsif ($coordinate == 4) {
                $positivex = "L";
                $positivey = "U";
        }
	
	return ($positivex,$positivey);

}

sub calcFlat {
	my $flat_position = shift;
	my $flat = "";

	if ($flat_position == 0) {
		$flat = "B";
	}
	elsif ($flat_position == 90) {
                $flat = "L";
        }
	elsif ($flat_position == 180) {
                $flat = "T";
        }
	if ($flat_position == 270) {
                $flat = "R";
        }
	
	return $flat;

}


1;

