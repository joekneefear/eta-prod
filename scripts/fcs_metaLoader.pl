#!/usr/bin/env perl_db
# SVN $Id: fcs_metaLoader.pl 1865 2016-10-10 17:21:22Z dpower $
=pod

=head1 SYNOPSIS

  fcs_metaLoader.pl <Input flie name>
      --table [pp_lot | pp_lotclass | pp_finallot | pp_prod | on_slice]
      --sid
      --host
      [--update_existing]
      [--logfile <logfilepath>]
      [--debug|--trace]
	  [--V Display version ID ]
=head1 DESCRIPTIONS

B<This script> will read meta data file and insert into corresponding table defined by --table option.

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/03/31 kazukik: new creation
 2015/04/08 kazukik: remove column name mapping
 2015/05/16 hiroshi: added sid and host options
 2015/05/29 grace  : Added support for -v option.
 2021/03/08 jgarcia: remove host, port and sid as script arguments, make use of REFDB_TNS environment variable instead.
 2022/03/09 sboothby: added support for on_slice table
 2022/04/13 sboothby: Fixed bug in processing for on_slice
 2022/07/21 sboothby: Update global_wafer_id and slice_order if found in file
 2024/06/11 sboothby: Update more on_slice fields if found in file
 2024/10/02 sboothby: Update slice_start_time for on_slice
=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

use strict;
use FindBin::libs;
use Pod::Usage qw/pod2usage/;
use Getopt::Long qw/:config ignore_case auto_help/;
use File::Basename;
use File::Spec;
use PDF::Log;
use PDF::DpLoad;
use PDF::DAO;

our $VERSION = "

1.0
";

### Check Argument
my (%hOptions) = (
    "TABLE"   => undef,
    "LOGFILE" => undef,
    "DEBUG"   => undef,
    "TRACE"   => undef,
    "UPDATE_EXISTING" => undef,
);
unless ( GetOptions( \%hOptions, "TABLE=s", "LOGFILE=s", "DEBUG", "TRACE", "UPDATE_EXISTING", "V" ) )
{
    pod2usage(3);
}

if($hOptions{V}) 
{
	print("$VERSION\n"); 
	dpExit(0);
};
PDF::Log->init( \%hOptions );

if ($#ARGV < 0 ) {
  pod2usage(3);
}
my $filename = $ARGV[0];    # incoming file to be parsed
if ( !-f $filename ) {
    dpExit( 1, "Input file $filename Not Found" );
}
unless ( $hOptions{TABLE} ) {
    dpExit( 1, "--table must be sepcified" );
}
my $table = lc( $hOptions{TABLE} );
unless ( grep { $_ eq $table } qw/pp_lot pp_prod pp_lotclass pp_finallot on_slice/ ) {
    dpExit( 1, "wrong table code :$table" );
}

#$ENV{"REFDB_TNS"} =  "dbi:Oracle:host=${host};port=1521;sid=${sid}";
#$ENV{"REFDB_TNS"} =  "dbi:Oracle://${host}:${port}/${sid}";
unless (defined($ENV{"REFDB_TNS"})) {
    dpExit( 1, "Please set REFDB_TNS environment variable  as <dbi:Oracle://HOST:PORT/SID>");
}


my $updateExisting = 0;
if (defined( $hOptions{UPDATE_EXISTING} ))
{
   $updateExisting = 1;
}
###

our $db = getRefdb({AutoCommit => 0});

my $separator = qr/\|/;    #by default the separator is the comma

### unique key
our $uniqueKey = {};
$uniqueKey->{pp_prod}     = [qw/product/];
$uniqueKey->{pp_lot}      = [qw/lot/];
$uniqueKey->{pp_lotclass} = [qw/lot_owner/];
$uniqueKey->{pp_finallot} = [qw/lot/];
$uniqueKey->{on_slice}    = [qw/slice/];

##### Main #####

# open the file
open( INPUTFILE, $filename )
    or dpExit( 1, "Failed to open file : $filename" );

# Read Header line
my $line = <INPUTFILE>;

# remove white spaces and CR from end of line
chop $line;
$line =~ s/[\s\r\n]+$//g;
$line =~ s/\"//g;
$line = lc($line);

# Split the lines using separator
my @Header = split( $separator, $line );

my @columns = @{$db->select($table,*,{rownum => 0})->columns};
INFO( "field name in file = " . join( " , ", @Header ) );
INFO( "field name in db   = " . join( " , ", @columns ) );
INFO( "primary key in db  = " . join( " , ", @{$uniqueKey->{$table}} ) );

my @ignoreField;
foreach my $key (@Header){
  unless (grep {$_ eq $key } @columns) {
    WARN("$key is not in $table. Ignored.");
    push @ignoreField , $key;
  }
}
foreach my $key (@{$uniqueKey->{$table}}){
   unless (grep {$_ eq $key} @Header){
      dpExit(1,"Primary key $key is not in file header");
   }
}

our $num = 1;
my ( $total, $inserted ) = ( 0, 0 );
while (<INPUTFILE>) {
    $num++;
    s/[\s\r\n]+$//g;
    s/\"//g;
    my @words    = map { trim($_) } split($separator);
    my %data = ();
    @data{@Header} = @words;
    # remove fields
    foreach my $key (@ignoreField){
       delete( $data{$key} );
    }
    if ( $_ ne "" ) {
	if ( $table eq "on_slice" ) {
		# Replace date time string with date time value
		$data{slice_start_time} = \["to_date(?,'YYYY-MM-DD HH24:MI:SS')",$data{slice_start_time}];
	}
        my $ret = populateTable( $table, \%data );
        $total++;
        $inserted += $ret;
    }
   
}
$db->commit;
close INPUTFILE;
INFO("Total = $total line in $filename,$inserted rows inserted");
INFO("################  End  #############");
dpExit(0);

################
sub populateTable {
    my $table   = shift;
    my $data    = shift;
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
           if ( $table eq "on_slice" && exists($data->{global_wafer_id}))
           {
               my $global_waferid = $data->{global_wafer_id};
               my $slice_order = $data->{slice_order};
               my $start_lot = $data->{start_lot};
               my $puck_id = $data->{puck_id};
               my $run_id = $data->{run_id};
               my $slice_source_lot = $data->{slice_source_lot};
               my $slice_lottype = $data->{slice_lottype};
               my $slice_supplierid = $data->{slice_supplierid};
               my $slice_start_time = $data->{slice_start_time};
               my $st_arr = $$slice_start_time;
               my $st_str = $st_arr->[1];
               my $slice_partname = $data->{slice_partname};
               INFO("Updating $data->{slice} with puckid=\"$puck_id\", runid=\"$run_id\", slice_source_lot=\"$slice_source_lot\", global_wafer_id = \"$global_waferid\", slice_order=\"$slice_order\", start_lot=\"$start_lot\", slice_start_time=\"$st_str\", slice_partname=\"$slice_partname\", slice_supplierid=\"$slice_supplierid\", slice_lottype=\"$slice_lottype\" ");
               $db->update($table, {puck_id => $puck_id, run_id => $run_id, slice_source_lot => $slice_source_lot, slice_lottype => $slice_lottype, slice_start_time => $slice_start_time, slice_partname => $slice_partname, slice_supplierid => $slice_supplierid, global_wafer_id => $global_waferid, slice_order => $slice_order, start_lot => $start_lot}, $keydata);
               $doInsert = 0;
           }
           else
           {
               WARN("$num:". join( ",", values( %{$keydata} ) ) . " is already in $table. Delete old data and insert new data." );
               $db->delete( $table, $keydata )
           }
	}
	else
	{
           WARN("$num:". join( ",", values( %{$keydata} ) ) . " is already in $table. Row discarded $keydata.");
	   $doInsert = 0;
	}
    }
    if ( $doInsert == 1 )
    {
       INFO("Inserting $data->{slice}");
       $db->insert( $table, $data ) or dpExit( 1, "$num:Failed to insert into $table: ".$db->error . " from file=" . $filename );
       return 1;
    }
    else
    {
       return 0;
    }
}

