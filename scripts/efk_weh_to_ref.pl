#!/usr/bin/env perl_db
#
# 24-Sep-2021   Eric Alfanta    : new
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

my @required_options = qw/TABLE /;
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
$uniqueKey->{on_lot} = [qw/lot/];	
$uniqueKey->{on_prod} = [qw/product/];
$uniqueKey->{on_scribe} = [qw/scribeid/];

INFO ("Infile: $infile");

$pplogger->setRawFile($infile);

if ($infile =~ /\.enr/ig) {

	read_enrFile($infile,$table);
	
}
else {
        dpExit(1,"Expected input file is ENR.");
}

dpExit(0);

sub read_enrFile {
	my $enrFile = shift;
	my $table = shift;
	my $separator = qr/\,/;
	
	open( ENR, $enrFile ) or dpExit( 1, "Failed to open file : $enrFile" );
	
	#read header
        my $line = <ENR>;
        chop $line;
        $line =~ s/[\s\r\n]+$//g;
        $line = lc($line);

        my @Header = split( $separator, $line );
	#replace some header names to match table primary keys
	$Header[7] = "efkproduct";	#replace product with efkproduct
	$Header[8] = "product";		#replace customer product with product
	$Header[13] = "scribeid";	#replace wafer with scribeid

        my @colums = @{$db->select($table,*,{rownum => 0})->columns};
        INFO( "field name in file = " . join( " , ", @Header ) );
        INFO( "field name in db   = " . join( " , ", @colums ) );
        INFO( "primary key in db  = " . join( " , ", @{$uniqueKey->{$table}} ) );
		
	my @ignoreField;
        foreach my $key (@Header){
                unless (grep {$_ eq $key } @colums) {
                        WARN("$key is not in $table. Ignored.");
                        push @ignoreField , $key;
                }


        }

        foreach my $key (@{$uniqueKey->{$table}}){
                unless (grep {$_ eq $key} @Header){
                        dpExit(1,"Primary key $key is not in file header");
                }
        }

        my $num = 1;
        my ( $total, $inserted ) = ( 0, 0 );
	$separator = qr/\|/; 
	
        while (<ENR>) {
                $num++;
                s/[\s\r\n]+$//g;
                my @words = map { trim($_) } split($separator);
                my %data = ();
                @data{@Header} = @words;

                # remove fields
                foreach my $key (@ignoreField){
                        delete( $data{$key} );
                }

                if ( $_ ne "" ) {
                        my @prod = split /\./, $words[7];
			my @custprod = split /\-/, $words[8];
			if ($table eq "on_lot") {	
				$data{subcon_product} = $prod[0];
				$data{product} = $custprod[0];
				$data{source_lot} = $words[9];
				$data{subcon_lot} = $words[10];
				$data{lot_type} = $words[35];
				$data{fab} = $words[36];
				$data{lot_class} = $words[38];
				$data{product_code} = $words[39];
				$data{alternate_product} = $words[39];
				$data{status} = "FOUND";
			}
			elsif ($table eq "on_prod") {
				$data{product} = $custprod[0];
				$data{fab} = $words[36];
				$data{process} = $words[32];
				$data{technology} = $words[33];
				$data{family} = $words[34];
				$data{pti4} = $words[37];
				$data{maskset} = $words[40];
				$data{status} = "FOUND";
			}
			elsif ($table eq "on_scribe") {
				$data{lot} = $words[2];
				$data{fab} = $words[36];
				$data{wafer_num} = $words[12];
				$data{waferid} = $words[13];
				$data{status} = "FOUND";
			}
                        
                        my $ret = populateTable( $table, \%data, $num );
                        $total++;
                        $inserted += $ret;
                }

        }
        $db->commit;
        close ENR;

        INFO("Total = $total line in $enrFile, $inserted rows inserted");
        INFO("################  End  #############");
	
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
