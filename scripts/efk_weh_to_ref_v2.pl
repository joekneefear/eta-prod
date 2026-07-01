#!/usr/bin/env perl_db
#
# 13-Dec-2021   Eric Alfanta    : new
#
# Function : Load EFK WEH metadata to ON_LOT,ON_PROD,ON_SCRIBE reference tables

use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DAO;
use PDF::Log;
use PPLOG::PPLogger;
use File::Basename qw/basename dirname/;
use PDF::DpLoad;
use File::Copy;
use Archive::Extract;
use Data::Dumper;

our $VERSION = "1.0";

# a hash to receive options
my (%hOptions) = ();

# Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

# Read arguments
if ( $#ARGV < 0 ) {
    pod2usage(3);
}
unless (
    GetOptions(
        \%hOptions, "LOGFILE=s", "DEBUG", "TRACE", "V", "OUT=s", "PPLOG", "UPDATE_EXISTING", "TABLE=s" 
    )
    )
{
    dpExit( 1, "invalid options" );
}

if($hOptions{V})
{
        print("$VERSION\n");
        dpExit(0);
};

my @required_options = qw/TABLE/;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

# Initialize logging
PDF::Log->init( \%hOptions,$pplogger );

if ($hOptions{PPLOG}){
        $pplogger->settobeLog(1);  #Set flag for pp logging
}

# check input file
my $infile = $ARGV[0];
my $dfile = "";

if ( ! -f $infile ) {
        dpExit( 1, "Input file $infile not found." );
}

unless ( $hOptions{TABLE} ) {
        dpExit( 1, "Table must be sepcified." );
}

my $table = lc( $hOptions{TABLE} );
unless ( grep { $_ eq $table } qw/on_lot on_prod on_scribe/ ) {
        dpExit( 1, "Wrong table specified : $table" );
}

unless (defined($ENV{"REFDB_TNS"})) {
        dpExit( 1, "Please set REFDB_TNS environment variable  as <dbi:Oracle://HOST:PORT/SID>");
}

my $updateExisting = 0;
if (defined( $hOptions{UPDATE_EXISTING} ))
{
        $updateExisting = 1;
}

our $db = getRefdb({AutoCommit => 0});
our $uniqueKey = {};
our @colNames;
$uniqueKey->{on_lot} = [qw/lot/];	
$uniqueKey->{on_prod} = [qw/product/];
$uniqueKey->{on_scribe} = [qw/scribeid/];

INFO ("Infile: $infile");

$pplogger->setRawFile($infile);

if ($infile =~ /\.enr/ig) {

	#read_enrFile($infile,$table);
	my ($lotHash, $prodHash, $scribeHash) = getUniqData($infile);
	my $num = 0;
	my $total = 0;
	my $inserted = 0;

	my @colums = @{$db->select($table,*,{rownum => 0})->columns};
	INFO( "field name in file = " . join( " , ", @colNames ) );
	INFO( "field name in db  = " . join( " , ", @colums ) );
	INFO( "primary key in db  = " . join( " , ", @{$uniqueKey->{$table}} ) );

	#replace some header names to match table primary keys
	$colNames[7] = "efkproduct";      #replace product with efkproduct
	$colNames[8] = "product";         #replace customer product with product
	$colNames[13] = "scribeid";       #replace wafer with scribeid

	foreach my $key (@{$uniqueKey->{$table}}){
		unless (grep {$_ eq $key} @colNames){
			dpExit(1,"Primary key $key is not in file header");
		}
	}
	
	if ( $table  eq "on_lot") {
		#print Dumper ($lotHash);
		foreach my $lotid( keys %{$lotHash}) {
			my %data = ();
			$num++;
			$data{lot} = uc($$lotHash{$lotid}{lot});
			$data{subcon_product} = uc($$lotHash{$lotid}{subcon_product});
			$data{product} = uc($$lotHash{$lotid}{product});
			$data{source_lot} = uc($$lotHash{$lotid}{source_lot});
			$data{subcon_lot} = uc($$lotHash{$lotid}{subcon_lot});
			$data{lot_type} = uc($$lotHash{$lotid}{lot_type});
			$data{fab} = uc($$lotHash{$lotid}{fab});
			$data{lot_class} = uc($$lotHash{$lotid}{lot_class});
			$data{product_code} = uc($$lotHash{$lotid}{product_code});
			$data{alternate_product} = uc($$lotHash{$lotid}{alternate_product});
			$data{status} = "MANUAL";		

			my $ret = populateTable( $table, \%data, $num );
			$total++;
			$inserted += $ret;
		}
	}
	elsif ($table eq "on_prod") {
		#print Dumper ($prodHash);
		foreach my $prodid ( keys %{$prodHash}) {
			my %data = ();
			$data{product} = uc($$prodHash{$prodid}{product});
			$data{fab} = uc($$prodHash{$prodid}{fab});
			$data{process} = uc($$prodHash{$prodid}{process});
			$data{technology} = uc($$prodHash{$prodid}{technology});
			$data{family} = uc($$prodHash{$prodid}{family});
			$data{pti4} = uc($$prodHash{$prodid}{pti4});
			$data{maskset} = uc($$prodHash{$prodid}{maskset});
			$data{status} = "MANUAL";
			
			my $ret = populateTable( $table, \%data, $num );
			$total++;
			$inserted += $ret;
		}
	}
	elsif ($table eq "on_scribe") {
		#print Dumper ($scribeHash);
		foreach my $scribe ( keys %{$scribeHash} ) {
			my %data = ();
			$data{scribeid} = uc($$scribeHash{$scribe}{scribeid});
			$data{lot} = uc($$scribeHash{$scribe}{lot});
			$data{fab} = uc($$scribeHash{$scribe}{fab});
			$data{wafer_num} = uc($$scribeHash{$scribe}{wafer_num});
			$data{waferid} = uc($$scribeHash{$scribe}{waferid});
			$data{status} = "MANUAL";			

			my $ret = populateTable( $table, \%data, $num );
			$total++;
			$inserted += $ret;
		}		
	}

	$db->commit;

	INFO("Total = $total unique data in $infile, $inserted rows inserted");
        INFO("################  End  #############");
	
}
else {
        dpExit(1,"Expected input file is ENR.");
}

dpExit(0);


sub getUniqData {
	my $enrFile = shift;
	my $lnCnt = 0;
	my $separator = qr/\|/;
	my %lotHash;
	my %prodHash;
	my %scribeHash;

	open( ENR, $enrFile ) or dpExit( 1, "Failed to open file : $enrFile" );
	while(my $line = <ENR>) {
		$lnCnt++;
		chomp $line;
		$line =~ s/[\s\r\n]+$//g;
        	$line = lc($line);
		my @words = split ( $separator, $line );
		#my @words = map { trim($line) } split($separator);

		if ($lnCnt ==  1) {
			@colNames = split /\,/,$line;
		}
		elsif ($lnCnt > 1 ) {
			my @prod = split /\./, $words[7];
			my @custprod = split /\-/, $words[8];

			if ($words[8] eq "na") {
				$custprod[0] = substr $prod[0], -7;
				$words[8] = ${custprod[0]}."-FAB";
			}

			$lotHash{$words[2]}{lot} = $words[2];
			$lotHash{$words[2]}{subcon_product} = $prod[0];
			$lotHash{$words[2]}{product} = $custprod[0];
			$lotHash{$words[2]}{source_lot} = $words[9];
			$lotHash{$words[2]}{subcon_lot} = $words[10];
			$lotHash{$words[2]}{lot_type} = $words[35];
			$lotHash{$words[2]}{fab} = $words[36];
			$lotHash{$words[2]}{lot_class} = $words[38];
			$lotHash{$words[2]}{product_code} = $words[8];
			$lotHash{$words[2]}{alternate_product} = $words[8];

			$prodHash{$custprod[0]}{product} = $custprod[0];
			$prodHash{$custprod[0]}{fab} = $words[36];
			$prodHash{$custprod[0]}{process} = $words[32];
			$prodHash{$custprod[0]}{technology} = $words[33];
			$prodHash{$custprod[0]}{family} = $words[34];
			$prodHash{$custprod[0]}{pti4} = $words[37];
			$prodHash{$custprod[0]}{maskset} = $words[40];

			$scribeHash{$words[13]}{scribeid} = $words[13];
			$scribeHash{$words[13]}{lot} = $words[2];
			$scribeHash{$words[13]}{fab} = $words[36];
			$scribeHash{$words[13]}{wafer_num} = $words[12];
			$scribeHash{$words[13]}{waferid} = $words[13];
			
		}
	}
	close ENR;	

	return (\%lotHash, \%prodHash, \%scribeHash);
}

sub populateTable {
        my $table = shift;
        my $data = shift;
        my $num = shift;
        my $keydata = {};

        foreach my $key ( keys %$data ) {
                if ( grep { $_ =~ /^$key$/i } @{ $uniqueKey->{$table} } ) {
                        $keydata->{$key} = $data->{$key};
                }
        }

        # check if the data already exist
        my ($count) = $db->select( $table, 'count(*)', $keydata )->list
        or dpExit( 1, "$num:Failed to get data from $table: ".$db->error );

        my $doInsert = 1;
        if ( $count > 0 ) {
                if ($updateExisting == 1)
                {
                        WARN("$num:". join( ",", values( %{$keydata} ) ) . " is already in $table. Delete old data and insert new data." );
                        $db->delete( $table, $keydata )
                }
                else
                {
                        WARN("$num:". join( ",", values( %{$keydata} ) ) . " is already in $table. Row discarded $keydata.");
                        $doInsert = 0;
                }
        }

        if ( $doInsert == 1 )
        {
                $db->insert( $table, $data ) or dpExit( 1, "$num:Failed to insert into $table: ".$db->error );
                return 1;
        }
        else
        {
                return 0;
        }
}
