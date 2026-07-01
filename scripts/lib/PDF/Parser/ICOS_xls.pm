# 18-Apr-2016 Eric	: Initial release
# 06-May-2016 Eric	: improved parsing
# 11-May-2107 Eric	: assign source lot as wafer name
# 14-Apr-2021 jgarcia : modified to use pass in ref_file and not to hardcode the file location.
#
package PDF::Parser::ICOS_xls;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use Spreadsheet::ParseExcel;
use POSIX;
use List::Util qw(min max);

use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

#my $ref_file = "$ENV{DPDATA}/data/cpcsp_icos/REF/bin.ref";
my %bin_ref = ();
my @bins;

sub readFile {
	my $self   = shift;
	my $infile = shift;
	my $type = shift;
	my $ref_file = shift;
	my $lotid = "";
	my $product = "";
	my $tpname = "AOI";
	my $tprev = 1;
	my $wafer_id		= "";
	my $machine_id		= "";
	my $operator_id		= "";
	my $ins_start_time 	= 0;
	my $ins_end_time 	= 0;
	my $tst_start_time 	= POSIX::LONG_MAX;
	my $tst_end_time 	= 0;
	my $td_flag		= 0;
	my $tp_flag		= 0;
	my $def_flag		= 0;
	my $empty_def_tbl       = 0;
	my @sbin_name		= ();
	my @readings		= ();
	my @wafid		= ();
	my @opr_flg		= ();
	my %sbin		= ();
	my %tp			= ();
	my %td			= ();
	my $header = new_headerLong;
	my $wmap = new_wmap;
	my $model = new_model ( 
		{
			header => $header,
			wmap => $wmap,
            		misc   => {},
            		dataSource => 'ICOS'
		}
	);

	my $parser = Spreadsheet::ParseExcel->new();
	my $workbook = $parser->parse($infile);	

	if (!defined $workbook)
	{
		die $parser->error(), ".\n";
	}

	my $worksheet = $workbook->worksheet(0);
	my ($row_min, $row_max) = $worksheet->row_range();
	my ($col_min, $col_max) = $worksheet->col_range();


	for my $row ($row_min .. $row_max)
	{
		my @dummy = ();

		for my $col ($col_min .. $col_max)
		{
			my $cell = $worksheet->get_cell($row, $col);	
			next unless $cell;
			my $cell_val = $cell->value();
                       	$dummy[$col] = &clean_string($cell_val);
		}		

		if (grep /Lot:/i, (@dummy)) {   # some datalogs have shifted or have blank cols
			for (my $i=0; $i<=$#dummy; $i++) {
				$header->LOT(trim($dummy[$i+1])) if $dummy[$i] =~ /lot\:/i;
				if ($header->LOT eq "") {
					$header->LOT(trim($dummy[$i+3])) if $dummy[$i] =~ /lot\:/i;
				}
			}
			$header->populateSrcLot;
			$header->PROGRAM($tpname);
			$header->REVISION($tprev);
		}
		if (grep /Product:/i, (@dummy)) {   # some datalogs have shifted or have blank cols
			for (my $i=0; $i<=$#dummy; $i++) {
				$header->PRODUCT(trim($dummy[$i+1])) if $dummy[$i] =~ /product\:/i;
				if ($header->PRODUCT eq ""){
					$header->PRODUCT(trim($dummy[$i+3])) if $dummy[$i] =~ /product\:/i;
				}
			}
		}
		if (grep /Wafer_ID/i, (@dummy)) {   # some datalogs have shifted or have blank cols
			$td_flag = 1;
			#get pass and invalid bin names
			@opr_flg = @dummy;
			foreach (@dummy) {
				if ($_ =~ /Pass/i) {
					$_ =~ s/\#\_//; 
					push (@sbin_name, uc($_));
				}
				elsif ($_ =~ /#_Invalid/i){
					$_ =~ s/\#\_//;
					push (@sbin_name, uc($_));
				}
			}	
		}
		elsif ($dummy[0] =~ /^\d+$/i && $td_flag == 1 && $type =~ /^SORT/i){
			my @item = &clean_row(@dummy);
			my $blank = "";
			# some files do not have operator col so insert a blank space
			splice @item, 2, 0, $blank if (!grep /Operator/i, (@opr_flg));
			
			push @readings , ($item[8], $item[10]);
			
			my ($mm, $dd, $yy, $hh, $min, $sec, $dump) = split /[\/\_\:]+/, $item[3];
			$ins_start_time = $yy."/".$mm."/".$dd." ".$hh.":".$min.":".$sec;

			my ($mm, $dd, $yy, $hh, $min, $sec, $dump) = split /[\/\_\:]+/, $item[4];
			$ins_end_time = $yy."/".$mm."/".$dd." ".$hh.":".$min.":".$sec;
	
			$header->EQUIP1_ID($item[1]);
			$header->OPERATOR($item[2]);

			my $wafer = $model->find('wafers', {number=>$item[0]});
                	unless (defined $wafer) {
				$wafer = new_wafer({number => $item[0]});
				if ($header->SOURCE_LOT ne "") {
					$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
				}
                        	$model->add('wafers', $wafer);
                	}
			push @wafid, $wafer->number;
			$wafer->START_TIME($ins_start_time);
			$wafer->END_TIME($ins_end_time);
		}
		elsif ($dummy[0] =~ /^[A-Z]\d+$/i && $td_flag == 1 && $type =~ /ASSY/i){
			my @item = &clean_row(@dummy);
                        my $blank = "";
			# some files do not have operator col so insert a blank space
			splice @item, 2, 0, $blank if (!grep /Operator/i, (@opr_flg));

                        push @readings , ($item[8], $item[10]);

                        my ($mm, $dd, $yy, $hh, $min, $sec, $dump) = split /[\/\_\:]+/, $item[3];
                        $ins_start_time = $yy."/".$mm."/".$dd." ".$hh.":".$min.":".$sec;

                        my ($mm, $dd, $yy, $hh, $min, $sec, $dump) = split /[\/\_\:]+/, $item[4];
                        $ins_end_time = $yy."/".$mm."/".$dd." ".$hh.":".$min.":".$sec;

                        $header->EQUIP1_ID($item[1]);
                        $header->OPERATOR($item[2]);
                        my $wafer = $model->find('wafers', {name=> $item[0]});
                        unless (defined $wafer) {
                                $wafer = new_wafer({name => $item[0] });
                                $model->add('wafers', $wafer);
                        }
                        push @wafid, $wafer->name;
                        $wafer->START_TIME($ins_start_time);
                        $wafer->END_TIME($ins_end_time);
                }
		elsif (grep /Defect_Class_Table/i, (@dummy)){
                        $td_flag = 0;
			$def_flag = 1;
                }
		elsif ($def_flag == 1 && $td_flag == 0) {
			$def_flag = 0;
			my $invalid_binname = pop(@sbin_name); # remove "INVALID" bin name
			# push other bin names to array
			foreach (@dummy)
                        {
				next if $_ eq "";
                        	push (@sbin_name, uc($_));
                        }
			push (@sbin_name, uc($invalid_binname));   # push back "INVALID" bin name to last
			#print "sbin names=@sbin_name\n";

			# append new bins to bin.ref
			for (my $i=0; $i<=$#sbin_name; $i++) {
				&read_ref_table($ref_file);
				my $bnum = $bin_ref{$sbin_name[$i]};
				if ($bnum eq "") {
					my @new_bins;
					foreach (@bins) {
						next if $_ == 99;
						push @new_bins, $_;
					}
					my $max = max @new_bins;
					my $nwbin = $max + 1;
					#open REF, ">$ref_file"  if ! -e $ref_file;
                                        open REF, ">>$ref_file" if   -e $ref_file;
					if ($sbin_name[$i] =~ /PASS/i){
						print REF "$sbin_name[$i],\t1\n";
					}
					elsif ($sbin_name[$i] =~ /INVALID/i){
						print REF "$sbin_name[$i],\t99\n";
					}
					else {
						print REF "$sbin_name[$i],\t$nwbin\n";
					}

					close(REF);
				}
			}
			# sometimes the defect table is empty
                        $empty_def_tbl = 1 if $#sbin_name > 1;

                        if ($empty_def_tbl == 0){
				foreach my $id (@wafid) {
                                        my @array_tmp;
                                        my $good = shift(@readings);
                                        my $invalid_bin = shift(@readings);
                                        unshift (@array_tmp, $good);               # push PASS bin to first
                                        push (@array_tmp, $invalid_bin);                # push INVALID bin to last
					my $wafer = $model->find('wafers', {number=>$id});
                        		unless (defined $wafer) {
                                		$wafer = new_wafer({number => $id});
                                		$model->add('wafers', $wafer);
                        		}
					for (my $i=0; $i<=$#array_tmp; $i++) {
						my $bin = new_bin;
						my $bnum = $bin_ref{$sbin_name[$i]} if $sbin_name[$i] ne "";
                                		$bin->number($bnum);
                                		$bin->name($sbin_name[$i]);
                                		$bin->count($array_tmp[$i]);
                                		$bin->PF(($sbin_name[$i] =~ /PASS/i) ? 'P' : 'F');
                                		$wafer->add('bins',$bin);
					}
                                }
                                last;
                        }
		}
		elsif ((grep /^#$/, (@dummy)) && (grep /\%/, (@dummy))){
                       $tp_flag = 1;
                }
		elsif ($dummy[0] =~ /^\d+$/i && $tp_flag == 1 && $def_flag == 0 && $type =~ /SORT/i ){
			my @item = &clean_row(@dummy);
			my @array_tmp3;
			my $good = shift(@readings);
			my $invalid_bin = shift(@readings);
			unshift (@item, $good);			# push PASS bin to first
			push (@item, $invalid_bin);			# push INVALID bin to last

			# get even elements of array
			@array_tmp3 = @item [map { $_ * 2} 0..int($#item / 2)];   #even
			#print "final bin readings=@array_tmp3\n";

			my $wafer = $model->find('wafers', {number=>$item[1]});
                        unless (defined $wafer) {
                                $wafer = new_wafer({number => $item[1]});
                                $model->add('wafers', $wafer);
                        }
			#my $val = max values %bin_ref;
			&read_ref_table($ref_file);
			for (my $i=0; $i<=$#array_tmp3; $i++) {
				my $bin = new_bin;
				my $bnum = $bin_ref{$sbin_name[$i]} if $sbin_name[$i] ne "";
				$bin->number($bnum);
                                $bin->name($sbin_name[$i]);
                                $bin->count($array_tmp3[$i]);
                                $bin->PF(($sbin_name[$i] =~ /PASS/i) ? 'P' : 'F');
                                $wafer->add('bins',$bin);
			}
		}
		elsif ($dummy[0] =~ /^[A-Z]\d+$/i && $tp_flag == 1 && $def_flag == 0 && $type =~ /ASSY/i ){
			my @item = &clean_row(@dummy);
                        my @array_tmp3;
                        my $good = shift(@readings);
                        my $invalid_bin = shift(@readings);
                        unshift (@item, $good);                        # push PASS bin to first
                        push (@item, $invalid_bin);                    # push INVALID bin to last

                        # get even elements of array
                        @array_tmp3 = @item [map { $_ * 2} 0..int($#item / 2)];   #even
                        #print "final bin readings=@array_tmp3\n";

                        my $wafer = $model->find('wafers', {name=>$item[1]});
                        unless (defined $wafer) {
                                $wafer = new_wafer({name => $item[1]});
                                $model->add('wafers', $wafer);
                        }
                        #my $val = max values %bin_ref;
                        &read_ref_table($ref_file);
                        for (my $i=0; $i<=$#array_tmp3; $i++) {
                                my $bin = new_bin;
                                my $bnum = $bin_ref{$sbin_name[$i]} if $sbin_name[$i] ne "";
                                $bin->number($bnum);
                                $bin->name($sbin_name[$i]);
                                $bin->count($array_tmp3[$i]);
                                $bin->PF(($sbin_name[$i] =~ /PASS/i) ? 'P' : 'F');
                                $wafer->add('bins',$bin);
                        }
                }
		elsif ($dummy[0] =~ /^TOTALS/) {
			$tp_flag = 0;
		}

	}	

	return $model;
}

sub read_ref_table {
	my $ref_file = shift;
	open FH, "${ref_file}" or die "can't load $ref_file\n";
        while(my $line=<FH>)
        {
                chomp($line);
                $line =~ s/\s+|\t+//g;
                next if $line =~ /^\#/ || $line eq "";
                my (@dummy) = split /\,/, $line;
                # Load bin ref table
                if ($dummy[0] =~ /[A-Z]+/i && $dummy[1] =~ /^\d+$/)
                {
                        $dummy[0] = uc $dummy[0];
                        $dummy[0] = &clean_string($dummy[0]);
                        $bin_ref{$dummy[0]} = $dummy[1];
			push @bins, $dummy[1];
                }
        }
        close(FH);	
}

sub clean_string
{
        my $str = shift;
           $str =~ s/^\s+|\s+$//g;
           #$str = &EDBUtil::cleanString($str); 
	   $str =~ s/\,//g;	
           $str =~ s/\s+/_/g;
        return($str);
}

sub clean_row
{
	my @arr     = @_;
	my @new_arr = ();
	foreach (@arr)
        {
        	if ($_ ne "undef" && $_ ne "")
                {
                	push (@new_arr, $_);
                }
        }
	return(@new_arr);	
}
1;

