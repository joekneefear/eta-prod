#!/usr/bin/env perl_db
#
# 25-Jul-2021	Eric Alfanta	: new
# 22-Apr-2023   jag             : added support for scribe file without ship scribe and single uncompressed .txt file
# Function : Decrypt and load JND scribe to ON_SCRIBE reference table


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

my $passphrase = "P\@ssw0rd";

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
        \%hOptions, "LOGFILE=s", "DEBUG", "TRACE", "V", "OUT=s", "PPLOG", "UPDATE_EXISTING", "TABLE=s", "FAB=s"
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
# Initialize logging

my @required_options = qw/ /;
pod2usage(3) if grep { !exists $hOptions{$_} } @required_options;

PDF::Log->init( \%hOptions,$pplogger );

if ($hOptions{PPLOG}){
	$pplogger->settobeLog(1);  #Set flag for pp logging
}

# check input file
my $infile = $ARGV[0];
my $dfile = "";
my $fab = $hOptions{FAB};
$fab = "JND:AIZU2 FAB (PTI)";

if ( ! -f $infile ) {
	dpExit( 1, "Input file $infile not found." );
}

unless ( $hOptions{TABLE} ) {
	dpExit( 1, "Table must be sepcified." );
}

my $table = lc( $hOptions{TABLE} );
unless ( grep { $_ eq $table } qw/on_scribe/ ) {
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
$uniqueKey->{on_scribe}     = [qw/scribeid/];

INFO ("Infile: $infile");

$pplogger->setRawFile($infile);

if ($infile =~ /\.GPG/i) {
	INFO("Decrypting file...");
	$dfile = $infile;
	$dfile =~ s/\.gpg$//;
	
	#system `gpg -v --batch --use-embedded-filename --passphrase $passphrase $infile`;
	system `gpg -v --batch --passphrase $passphrase $infile`;

	if (-e $dfile && $dfile =~ /\.zip/ig) {
		INFO("Decrypted file successfully.");
		my $tfile = "";
		my $ext_dir = dirname $dfile;
		my $ae = Archive::Extract->new(archive => $dfile);
		#my $ok = $ae->extract( to => $ext_dir) or die->error;
		my $ok = $ae->extract( to => $ext_dir) or dpExit(1,"Extracting file failed.");
			
		foreach my $file (@{$ae->files}) {
			if ($file =~ /\.txt/i) {
				$tfile = "${ext_dir}/${file}";
				INFO("Extracted file = $tfile");
				my $orig_header = `head -1 $tfile`;
				$orig_header = trim($orig_header);		
				if ($orig_header eq "LOT_ID,SLOT_ID,VENDOR_SCRIBE,SHIP_LOT_ID,SHIP_ONLOT_ID") {
					INFO("Replacing file header.");
					system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDOR_SCRIBE\,SHIP_LOT_ID\,SHIP_ONLOT_ID/LOT_ID\,WAFER_NUM\,SCRIBEID\,SHIP_LOT_ID\,LOT/' $tfile`;
					INFO("Reading text file.");
					read_txtFile($tfile,$table,$fab);
				} elsif ($orig_header eq "LOT_ID,SLOT_ID,VENDER_SCRIBE,SHIP_LOT_ID,SHIP_ONLOT_ID") {
                    INFO("Replacing file header.");
                    system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDER_SCRIBE\,SHIP_LOT_ID\,SHIP_ONLOT_ID/LOT_ID\,WAFER_NUM\,SCRIBEID\,SHIP_LOT_ID\,LOT/' $tfile`;
                    INFO("Reading text file.");
                    read_txtFile($tfile,$table,$fab);
                } elsif ($orig_header eq "ORIGINAL_LOT_ID,SLOT_ID,VENDER_SCRIBE,SHIP_LOT_ID,SHIP_ONLOT_ID" ) {
                	INFO("Replacing file header.");
                    system `sed -i '1 s/ORIGINAL_LOT_ID\,SLOT_ID\,VENDER_SCRIBE\,SHIP_LOT_ID\,SHIP_ONLOT_ID/ORIGINAL_LOT_ID\,WAFER_NUM\,SCRIBEID\,SHIP_LOT_ID\,LOT/' $tfile`;
                    INFO("Reading text file.");
                    read_txtFile($tfile,$table,$fab);
                } elsif ($orig_header eq "ORIGINAL_LOT_ID,SLOT_ID,VENDOR_SCRIBE,SHIP_LOT_ID,SHIP_ONLOT_ID" ) {
                	INFO("Replacing file header.");
                    system `sed -i '1 s/ORIGINAL_LOT_ID\,SLOT_ID\,VENDOR_SCRIBE\,SHIP_LOT_ID\,SHIP_ONLOT_ID/ORIGINAL_LOT_ID\,WAFER_NUM\,SCRIBEID\,SHIP_LOT_ID\,LOT/' $tfile`;
                    INFO("Reading text file.");
                    read_txtFile($tfile,$table,$fab);
                } elsif ($orig_header eq "LOT_ID,SLOT_ID,VENDER_SCRIBE,AFSM_LOT_ID,SHIP_ON_LOT_ID" ) {
                	INFO("Replacing file header.");
                    system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDER_SCRIBE\,AFSM_LOT_ID\,SHIP_ON_LOT_ID/LOT_ID\,WAFER_NUM\,SCRIBEID\,AFSM_LOT_ID\,LOT/' $tfile`;
                    INFO("Reading text file.");
                    read_txtFile($tfile,$table,$fab);
                } elsif ($orig_header eq "LOT_ID,SLOT_ID,VENDOR_SCRIBE,AFSM_LOT_ID,SHIP_ON_LOT_ID" ) {
                	INFO("Replacing file header.");
                    system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDOR_SCRIBE\,AFSM_LOT_ID\,SHIP_ON_LOT_ID/LOT_ID\,WAFER_NUM\,SCRIBEID\,AFSM_LOT_ID\,LOT/' $tfile`;
                    INFO("Reading text file.");
                    read_txtFile($tfile,$table,$fab);
	            } elsif($orig_header eq "LOT_ID,SLOT_ID,VENDOR_SCRIBE") {
					INFO("Replacing file header.");
                    system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDOR_SCRIBE/LOT\,WAFER_NUM\,SCRIBEID/' $tfile`;
                    INFO("Reading text file.");
                    read_txtFile($tfile,$table,$fab);
				} elsif($orig_header eq "LOT,WAFER_NUM,SCRIBEID") {
					INFO("No need to replace header.");
                    INFO("Reading text file.");
                    read_txtFile($tfile,$table,$fab);
				} else {
					unlink $tfile;
					dpExit(1,"Incorrect file header : $orig_header");
				}
			}
		}
		unlink $tfile;
		unlink $dfile;
		
	}
	else {
		dpExit(1,"Decrypting file failed.");
	}

}
elsif($infile =~ /\.ZIP/i) {
	my $tfile = "";
	my $ext_dir = dirname $infile;
	my $ae = Archive::Extract->new(archive => $infile);
	my $ok = $ae->extract( to => $ext_dir) or dpExit(1,"Extracting file failed.");

	foreach my $file (@{$ae->files}) {
		if ($file =~ /\.txt/i) {
			$tfile = "${ext_dir}/${file}";
			INFO("Extracted file = $tfile");
			my $orig_header = `head -1 $tfile`;
			$orig_header = trim($orig_header);
			if ($orig_header eq "LOT_ID,SLOT_ID,VENDOR_SCRIBE,SHIP_LOT_ID,SHIP_ONLOT_ID") {
				INFO("Replacing file header.");
				system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDOR_SCRIBE\,SHIP_LOT_ID\,SHIP_ONLOT_ID/LOT_ID\,WAFER_NUM\,SCRIBEID\,SHIP_LOT_ID\,LOT/' $tfile`;
				INFO("Reading text file.");
				read_txtFile($tfile,$table,$fab);
			} elsif ($orig_header eq "LOT_ID,SLOT_ID,VENDER_SCRIBE,SHIP_LOT_ID,SHIP_ONLOT_ID") {
                INFO("Replacing file header.");
                system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDER_SCRIBE\,SHIP_LOT_ID\,SHIP_ONLOT_ID/LOT_ID\,WAFER_NUM\,SCRIBEID\,SHIP_LOT_ID\,LOT/' $tfile`;
                INFO("Reading text file.");
                read_txtFile($tfile,$table,$fab);
            } elsif ($orig_header eq "ORIGINAL_LOT_ID,SLOT_ID,VENDER_SCRIBE,SHIP_LOT_ID,SHIP_ONLOT_ID" ) {
            	INFO("Replacing file header.");
                system `sed -i '1 s/ORIGINAL_LOT_ID\,SLOT_ID\,VENDER_SCRIBE\,SHIP_LOT_ID\,SHIP_ONLOT_ID/ORIGINAL_LOT_ID\,WAFER_NUM\,SCRIBEID\,SHIP_LOT_ID\,LOT/' $tfile`;
                INFO("Reading text file.");
                read_txtFile($tfile,$table,$fab);
            }
			elsif ($orig_header eq "ORIGINAL_LOT_ID,SLOT_ID,VENDOR_SCRIBE,SHIP_LOT_ID,SHIP_ONLOT_ID" ) {
                INFO("Replacing file header.");
                system `sed -i '1 s/ORIGINAL_LOT_ID\,SLOT_ID\,VENDOR_SCRIBE\,SHIP_LOT_ID\,SHIP_ONLOT_ID/ORIGINAL_LOT_ID\,WAFER_NUM\,SCRIBEID\,SHIP_LOT_ID\,LOT/' $tfile`;
                INFO("Reading text file.");
                 read_txtFile($tfile,$table,$fab);
            } elsif ($orig_header eq "LOT_ID,SLOT_ID,VENDER_SCRIBE,AFSM_LOT_ID,SHIP_ON_LOT_ID" ) {
                INFO("Replacing file header.");
                system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDER_SCRIBE\,AFSM_LOT_ID\,SHIP_ON_LOT_ID/LOT_ID\,WAFER_NUM\,SCRIBEID\,AFSM_LOT_ID\,LOT/' $tfile`;
                INFO("Reading text file.");
                read_txtFile($tfile,$table,$fab);
            } elsif ($orig_header eq "LOT_ID,SLOT_ID,VENDOR_SCRIBE,AFSM_LOT_ID,SHIP_ON_LOT_ID" ) {
               	INFO("Replacing file header.");
                system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDOR_SCRIBE\,AFSM_LOT_ID\,SHIP_ON_LOT_ID/LOT_ID\,WAFER_NUM\,SCRIBEID\,AFSM_LOT_ID\,LOT/' $tfile`;
                INFO("Reading text file.");
                read_txtFile($tfile,$table,$fab);
            } elsif($orig_header eq "LOT_ID,SLOT_ID,VENDOR_SCRIBE") {
				INFO("Replacing file header.");
                system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDOR_SCRIBE/LOT\,WAFER_NUM\,SCRIBEID/' $tfile`;
                INFO("Reading text file.");
                read_txtFile($tfile,$table,$fab);
			} elsif($orig_header eq "LOT,WAFER_NUM,SCRIBEID") {
				INFO("No need to replace header.");
                INFO("Reading text file.");
                read_txtFile($tfile,$table,$fab);
			} else {
				unlink $tfile;
				dpExit(1,"Incorrect file header : $orig_header");
			}
		}
	}
	unlink $tfile;
	unlink $dfile;
		
} elsif($infile =~ /\.txt/i) {
	my $tfile = $infile;
	INFO("Extracted file = $tfile");
			my $orig_header = `head -1 $tfile`;
			$orig_header = trim($orig_header);
			if ($orig_header eq "LOT_ID,SLOT_ID,VENDOR_SCRIBE,SHIP_LOT_ID,SHIP_ONLOT_ID") {
				INFO("Replacing file header.");
				system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDOR_SCRIBE\,SHIP_LOT_ID\,SHIP_ONLOT_ID/LOT_ID\,WAFER_NUM\,SCRIBEID\,SHIP_LOT_ID\,LOT/' $tfile`;
				INFO("Reading text file.");
				read_txtFile($tfile,$table,$fab);
			} elsif ($orig_header eq "LOT_ID,SLOT_ID,VENDER_SCRIBE,SHIP_LOT_ID,SHIP_ONLOT_ID") {
            	INFO("Replacing file header.");
                system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDER_SCRIBE\,SHIP_LOT_ID\,SHIP_ONLOT_ID/LOT_ID\,WAFER_NUM\,SCRIBEID\,SHIP_LOT_ID\,LOT/' $tfile`;
                INFO("Reading text file.");
                read_txtFile($tfile,$table,$fab);
            } elsif ($orig_header eq "ORIGINAL_LOT_ID,SLOT_ID,VENDER_SCRIBE,SHIP_LOT_ID,SHIP_ONLOT_ID" ) {
            	INFO("Replacing file header.");
                system `sed -i '1 s/ORIGINAL_LOT_ID\,SLOT_ID\,VENDER_SCRIBE\,SHIP_LOT_ID\,SHIP_ONLOT_ID/ORIGINAL_LOT_ID\,WAFER_NUM\,SCRIBEID\,SHIP_LOT_ID\,LOT/' $tfile`;
                INFO("Reading text file.");
                read_txtFile($tfile,$table,$fab);
            } elsif ($orig_header eq "ORIGINAL_LOT_ID,SLOT_ID,VENDOR_SCRIBE,SHIP_LOT_ID,SHIP_ONLOT_ID" ) {
            	INFO("Replacing file header.");
                system `sed -i '1 s/ORIGINAL_LOT_ID\,SLOT_ID\,VENDOR_SCRIBE\,SHIP_LOT_ID\,SHIP_ONLOT_ID/ORIGINAL_LOT_ID\,WAFER_NUM\,SCRIBEID\,SHIP_LOT_ID\,LOT/' $tfile`;
                INFO("Reading text file.");
                read_txtFile($tfile,$table,$fab);
            } elsif ($orig_header eq "LOT_ID,SLOT_ID,VENDER_SCRIBE,AFSM_LOT_ID,SHIP_ON_LOT_ID" ) {
            	INFO("Replacing file header.");
                system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDER_SCRIBE\,AFSM_LOT_ID\,SHIP_ON_LOT_ID/LOT_ID\,WAFER_NUM\,SCRIBEID\,AFSM_LOT_ID\,LOT/' $tfile`;
                INFO("Reading text file.");
                read_txtFile($tfile,$table,$fab);
            } elsif ($orig_header eq "LOT_ID,SLOT_ID,VENDOR_SCRIBE,AFSM_LOT_ID,SHIP_ON_LOT_ID" ) {
            	INFO("Replacing file header.");
                system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDOR_SCRIBE\,AFSM_LOT_ID\,SHIP_ON_LOT_ID/LOT_ID\,WAFER_NUM\,SCRIBEID\,AFSM_LOT_ID\,LOT/' $tfile`;
                INFO("Reading text file.");
                read_txtFile($tfile,$table,$fab);
            } elsif($orig_header eq "LOT_ID,SLOT_ID,VENDOR_SCRIBE") {
				INFO("Replacing file header.");
                system `sed -i '1 s/LOT_ID\,SLOT_ID\,VENDOR_SCRIBE/LOT\,WAFER_NUM\,SCRIBEID/' $tfile`;
                INFO("Reading text file.");
                read_txtFile($tfile,$table,$fab);
			} elsif($orig_header eq "LOT,WAFER_NUM,SCRIBEID") {
				INFO("No need to replace header.");
                INFO("Reading text file.");
                read_txtFile($tfile,$table,$fab);
			}
			else {
				unlink $tfile;
				dpExit(1,"Incorrect file header : $orig_header");
			}
	unlink $tfile;
	

}
else {
	dpExit(1,"Expected input file is txt, GPG and ZIP.");
}

dpExit(0);

sub read_txtFile {
	my $tfile = shift;
	my $table = shift;
	my $fab = shift;
	my $separator = qr/\,/;
	
	open( TXT, $tfile ) or dpExit( 1, "Failed to open file : $tfile" );
	
	#read header
	my $line = <TXT>;
	chop $line;
	$line =~ s/[\s\r\n]+$//g;
	$line = lc($line);

	my @Header = split( $separator, $line );

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

	while (<TXT>) {
		$num++;
		s/[\s\r\n]+$//g;
		my @words    = map { trim($_) } split($separator);
		my %data = ();
		@data{@Header} = @words;

		# remove fields
		foreach my $key (@ignoreField){
			delete( $data{$key} );
		}

		if ( $_ ne "" ) {
			#add fab if defined
			$data{fab} = $fab if ($fab ne "");
			$data{waferid} = $words[2];
			$data{status} = "MANUAL";

			my $ret = populateTable( $table, \%data, $num );
			$total++;
			$inserted += $ret;
		}

	}
	$db->commit;
	close INPUTFILE;	

	INFO("Total = $total line in $tfile, $inserted rows inserted");
	INFO("################  End  #############");
}

sub populateTable {
	my $table = shift;
	my $data = shift;
	my $num	= shift;
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
			WARN("$num:". join( ",", values( %{$keydata} ) ) . " is already in $table. Row discarded with scribe value =>." . join( ",", values( %{$keydata} ) ));
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
