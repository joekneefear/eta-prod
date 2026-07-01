# 12-Jan-2017 Eric	: create
# 23-Jan-2017 Eric	: read also XLS file.
#
package PDF::Parser::powertech_xlsx_sum;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use Spreadsheet::ParseXLSX;
use Spreadsheet::ParseExcel;

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
	my $tstflg = 0;
	my $sumflg = 0;
	my $dtaflg = 0;
	my $resflg = 0;
	my $seqflg = 0;
	my $hbflg  = 0;
	my $sbflg  = 0;
	my $stname = "";
	my $tstrname ="";
	my $prog = "";
	my $rev = "";
	my %hwbin = {};
	my $header = new_headerLong;
	my $wmap   = new_wmap;
	my $model  = new_model (
	{	header => $header,
		wmap   => $wmap,
		misc   => {},
		dataSource => 'QTEC'

	}
	);

	my $wafer = $model->find('wafers',{number => 0});
        unless (defined $wafer){
                $wafer = new_wafer( { number => 0 } );
                $model->add('wafers',$wafer);
        }

	my $parser;
	if ($infile =~ /\.xlsx$|\.xlsx_md5/i){
		$parser = Spreadsheet::ParseXLSX->new;
	}
	elsif ($infile =~ /\.xls$|\.xls_md5/i){
		$parser = Spreadsheet::ParseExcel->new;	
	}

	my $workbook = $parser->parse($infile);
	
	if (!defined $workbook)
	{
		die $parser->error(), ".\n";
	}	

	my $fn = basename $infile;
	my @item = split /\_|\-/, $fn;
	$header->LOT($item[0]);
	
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
                       	#$dummy[$col] = &clean_string($cell_val);
			$dummy[$col] = $cell_val;
		}
		if ($dummy[0] =~ /Type/i && $dummy[1] =~ /Bin/i) {	
			$tstflg = 0;
			$seqflg = 0;
			$hbflg  = 1;
			$sbflg  = 0;
			$dtaflg = 0;
		}elsif ($dummy[0] =~ /\*\*\*/ && $dummy[2] =~ /Summary/i) {
			$sumflg  = 1;
		}elsif ($dummy[0] =~ /Tester:/) {
			$tstrname = trim($dummy[1]);
		}elsif ($dummy[0] =~ /Station:/) {
			$stname = trim($dummy[1]);
			$header->EQUIP1_ID($tstrname." ".$stname);
		}elsif ($dummy[0] =~ /Sort\sFile:/) {
			my @item = split /\\|\./, $dummy[1];
			$prog = $item[2];
			$prog =~ s/V\d+$//i;
			$rev  = substr ($item[2], rindex($item[2], "V"));
			$rev  =~ s/^V//i;
			$header->PROGRAM($prog);
			$header->REVISION($rev);
		}elsif ($dummy[0] =~ /Operator:/){
			$header->OPERATOR(trim($dummy[1]));
		}elsif ($hbflg == 1 && $dummy[2] !~ /REJECT/i ) {
			#print "HB= @dummy\n";
			my $no = trim($dummy[1]);
			$hwbin{$no}{NAME} = trim($dummy[2]);
			$hwbin{$no}{CNT} += trim($dummy[4]);
		}

		
	}

	foreach my $no (sort {$a<=>$b} keys %hwbin) {
		next if $hwbin{$no} eq "";
		my $hbin = new_bin;
		$hbin->number($no);
		$hbin->name($hwbin{$no}{NAME});
		$hbin->count($hwbin{$no}{CNT});
		$hbin->PF( $no == 5 ? 'P' : 'F');
		$wafer->add('hbins', $hbin);
	}
	
return ($model);

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
1;

