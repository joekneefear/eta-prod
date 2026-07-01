# 18-Feb-2016 Eric	: create
# 10-Apr-2019 Eric	: fix bug when the file has fewer limits than parameters
# 18-Apr-2020 Eric	: return tp instead to limit
# 25-Apr-2020 Eric	: create test program reference file for test numbers
#
package PDF::Parser::Sic_xls;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use Spreadsheet::ParseExcel;
use List::MoreUtils qw(first_index);

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
	my $tpdir = shift;
	my $lotid		= "";
	my $deviceid		= "";
	my $session_datetime	= "";
	my $box_boat_no		= "";
	my $no_in_box		= "";
	my $tpname		= "";
	my $tprev		= 1;
	my $customer_nam	= "";
	my $cust_ord_num	= "";
	my $cust_part_num	= "";
	my $cre_sales_ord_num	= "";
	my $ord_line_itm_num	= "";
	my $description		= "";
	my $polish		= "";
	my $delivery_no		= "";
	my $grade		= "";
	my $tpflag		= 0;
	my $tdflag		= 0;
	my $specflag		= 0;
	my %td			= ();
	my %tp			= ();
	my @sbin_name		= ();
	my @readings		= ();
	my @tnum_arr		= ();
	my @unit		= ();
	my @hispec		= ();
	my @lowspec		= ();
	my $limit = new_limit;
	
	my $parser = Spreadsheet::ParseExcel->new();
	my $workbook = $parser->parse($infile);
	
	if (!defined $workbook)
	{
		die $parser->error(), ".\n";
	}	
	
	my $worksheet = $workbook->worksheet(0);
	my ($row_min, $row_max) = $worksheet->row_range();
	my ($col_min, $col_max) = $worksheet->col_range();

	my @dummy = ();
	my $dup_cell = 1;

	for my $row ($row_min .. $row_max)
	{
		for my $col ($col_min .. $col_max)
		{
			my $cell = $worksheet->get_cell($row, $col);	
			next unless $cell;
			my $cell_val = $cell->value();
                       	$dummy[$col] = &clean_string($cell_val);
		}
		if ($dummy[0] =~ /^Shipment\_Date/i)
		{	
			my @new_arr = &clean_row(@dummy);              	# REMOVES EMPTY CELLS
			my $tmp_datetime   = $new_arr[1];
			$cre_sales_ord_num = $new_arr[3];

			my ($mm, $dd, $yy) = split /\//, $tmp_datetime;
			$session_datetime  = $yy."/".$mm."/".$dd." ".00.":".00.":".00;
		}
		elsif ($dummy[0] =~ /^Customer\_Name/)
		{
			my @new_arr 	  = &clean_row(@dummy);		# REMOVES EMPTY CELLS
			$customer_nam	  = $new_arr[1];
			$ord_line_itm_num = $new_arr[3];
			$description	  = $new_arr[5];
		}
		elsif ($dummy[0] =~ /^Customer\_Order\_Number/)
		{
			my @new_arr      = &clean_row(@dummy);		# REMOVES EMPTY CELLS
			$cust_ord_num = $new_arr[1];
			$delivery_no = $new_arr[3];
			$polish = $new_arr[5];

		}
		elsif ($dummy[0] =~ /^Customer\_Part\_Number/)
		{
			my @new_arr = &clean_row(@dummy);			# REMOVES EMPTY CELLS
			$deviceid = $new_arr[1];
			$tpname   = $deviceid;
		}
		elsif ($dummy[0] =~ /^Item/i && $specflag == 0)
		{
			$tpflag      = 1;
			my @new_arr     = &clean_row(@dummy);			# REMOVES EMPTY CELLS
			my @tmp_unit = splice(@new_arr, 5);

			for (my $i=0; $i<=$#tmp_unit; $i++)
			{
				my @dump  = split /[\(|\)|\s]/, $tmp_unit[$i];
				$unit[$i] = pop @dump if scalar @dump > 1;
				$unit[$i] = &remove_unwanted_chars($unit[$i]);
				$dump[0]  =~ s/\_$//;
				push (@sbin_name, $dump[0]);
			}
		}
		elsif ($dummy[0] =~ /^\d+$/ && $specflag == 0 && $tpflag == 1)
		{
			$tdflag    = 1;
			my @new_arr   = &clean_row(@dummy);		# REMOVES EMPTY CELLS
			my $itemno = $new_arr[0];
			my @tmp    = splice(@new_arr, 5);
			
			$lotid     = $new_arr[1];
			$box_boat_no = $new_arr[2];
			$no_in_box   = sprintf("%02d", $new_arr[3]);	
			$grade	   = $new_arr[4];
			for (my $i=0; $i<=$#tmp; $i++)
                        {
				$tmp[$i] =~ s/\(//g;	
				$tmp[$i] =~ s/\)//g;
				$readings[$i] = trim($tmp[$i]);
			}
			$td{$itemno}{START_T} = $session_datetime;
			$td{$itemno}{EQUIP1} = $delivery_no;
			$td{$itemno}{EQUIP2} = $cust_ord_num;
			$td{$itemno}{EQUIP3} = $description;
			$td{$itemno}{EQUIP4} = $polish;
			$td{$itemno}{EQUIP5} = $grade;
			$td{$itemno}{CUST} = $customer_nam;
			$td{$itemno}{PROGRAM} = $tpname;
			$td{$itemno}{LOTID} = $lotid;
			$td{$itemno}{NO_BX_BT} = $no_in_box;
			$td{$itemno}{BX_BT_NO} = $box_boat_no;
			$td{$itemno}{READINGS} = [@readings];  
		}
		#elsif ($dummy[0] =~ /^Specs/)
		elsif ($dummy[0] =~ /^Specs/ && $dup_cell == 1)
		{
			$dup_cell++;
			my $tp = "${tpdir}/${tpname}.ref";
			my @spec_arr = ();
			my @tmp_arr  = ();
			   @tmp_arr  = &clean_row(@dummy);                # REMOVES EMPTY CELLS	
			   @spec_arr = splice(@tmp_arr, 2);	

			my @ret_tnum = generateTnum($tp,\@sbin_name);

			for (my $i=0; $i<=$#sbin_name; $i++)
			{

				if ($spec_arr[$i] !~ /Max/i)
				{
					($lowspec[$i],my $dump,$hispec[$i]) = split /_/, $spec_arr[$i];
					$lowspec[$i] = ($lowspec[$i] =~ /\d/) ? $lowspec[$i] : -1e20;
					$hispec[$i] = ($hispec[$i] =~ /\d/) ? $hispec[$i] : 1e20;
				}
				else
				{
					(my $dump,$hispec[$i]) = split /_/, $spec_arr[$i];
					$lowspec[$i] = ($lowspec[$i] =~ /\d/) ? $lowspec[$i] : -1e20;
					$hispec[$i] = ($hispec[$i] =~ /\d/) ? $hispec[$i] : 1e20;
				}
			}	

			$tp{TNAM} = [@sbin_name];
			$tp{TNUM} = [@ret_tnum];
			$tp{UNIT} = [@unit];
			$tp{HLIM} = [@hispec];
			$tp{LLIM} = [@lowspec];
		}
		elsif ($dummy[0] =~ /^Minimum/)
		{
			#print "@dummy\n";
		}
		elsif ($dummy[0] =~ /^Average/)
                {
                        #print "@dummy\n";
                }
		elsif ($dummy[0] =~ /^Maximum/)
                {
                        #print "@dummy\n";
                }
	}
	
return (\%td, \%tp);

}

sub remove_unwanted_chars
{
        my $value = shift;
        $value =~ s/[^a-zA-Z0-9\-\_\.]/\-/gi;
        $value =~ s/\-{2,}/\-/g;
        $value =~ s/^\-+|\-+$//g;             ### REMOVE LEADING/TRAILING "-"
        return($value);
}

sub clean_string
{
        my $str = shift;
           $str =~ s/^\s+|\s+$//g;
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

sub generateTnum {
	my $tp = shift;
	my $xls_tnam = shift;
	my @ret_tnum = ();
	my @ref_tnam = ();
	my @ref_tnum = ();
	my @app_tnam = ();
	my @app_tnum = ();

	if ( ! -e $tp) {
		open REF, ">$tp" or dpExit(1,"Error. Failed to create $tp file.");
		my $n = 0;
		foreach my $name (@{$xls_tnam}) {
			$n++;	
			print REF "$n,$name\n";
			push @ret_tnum, $n;
		}
        	close REF;
	}
	elsif ( -e $tp) {
		open REF, "<$tp" or dpExit(1,"Error. Failed to open $tp file.");
		while (my $ln=<REF>) {
			chomp $ln;
			next if $ln eq "";
			if ($ln =~ /^(\d+)\,(.+)/g) {
				my $num = $1;
				my $nam = $2;
				push @ref_tnum, $num;
				push @ref_tnam, $nam;
			}
		}
		close REF;

		my $last_tnum = $ref_tnum[$#ref_tnum];


		for (my $i=0; $i<=$#$xls_tnam; $i++) {
			if ( grep { $$xls_tnam[$i] eq $_ } @ref_tnam) {
				my $indx = first_index { $_ eq $$xls_tnam[$i] } @ref_tnam;
				$indx = $indx+1;
				push @ret_tnum, $indx;
				#print "Found => $$xls_tnam[$i] => $indx\n";
			}
			else  {
				$last_tnum++;
				push @ret_tnum, $last_tnum;
				push @app_tnum, $last_tnum;
				push @app_tnam, $$xls_tnam[$i];
				#print "Not Found => $$xls_tnam[$i] => $last_tnum\n";
			}
		}

		if (scalar @app_tnam > 0) {
			open REF, ">>$tp" or dpExit(1,"Error. Failed to open $tp file.");
			for (my $i=0; $i<=$#app_tnam; $i++) {
				print REF "$app_tnum[$i],$app_tnam[$i]\n";
			}
			close REF;
		}
	}


	return @ret_tnum; 
}
1;

