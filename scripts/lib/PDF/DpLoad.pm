package PDF::DpLoad;

use strict;
use Exporter 'import';
use PDF::Log;
use POSIX qw/strftime/;
use Time::Local;
use List::MoreUtils qw/first_index/;
use File::Copy;
use File::Basename qw/basename dirname fileparse/;
use IO::Compress::Gzip qw(gzip $GzipError) ;
use PPLOG::PPLogger; 	# wsanopao:
use Carp qw/longmess/;
use IPC::Open3;
use Spreadsheet::ParseExcel;
use Spreadsheet::ParseXLSX;
use Data::Dumper;
our @EXPORT
    = qw/dpExit validateOutDir currentDate parseDate trim repNA formatDate formatDateToYYYYMMDD forkFile getLoggingTime 
         withoutExt extOnly doCompressGzip formatSourceLot moveFile checkMetadataByLotMoveToPreprocessingFolder xlsxToHash move_oldest_file format_age move_files_by_age/;
our $VERSION = "1.0";

my $pplogger = new PPLOG::PPLogger;

sub dpExit {
    my $code  = shift  // 0;
    my $error = shift;
    my $warn  = shift;
    my @errorArray;
    my @warnArray;
    my $outFile = "err.jnk";
    my $ret_val;
    my $trace = longmess;
    $trace =~ s/\n/\t/g;
    
    if($code == 10 ) {
       exit(10);
    }

    if ( defined $error ) {
        if ( ref $error eq 'ARRAY' ) {
            @errorArray = @$error;
        }
        elsif ( ref $error eq '' ) {
            @errorArray = ($error);
        }
        else {
            LOGDIE( "message is not scalar or ArrayRef:" . $error );
        }
        
        push @errorArray, $trace;
        
        
    }
    my $errCount = scalar @errorArray;
    if ( defined $warn ) {
        if ( ref $warn eq 'ARRAY' ) {
            @warnArray = @$warn;
        }
        elsif ( ref $warn eq '' ) {
            @warnArray = ($warn);
        }
        else {
            LOGDIE( "message is not scalar or ArrayRef:" . $warn );
        }
    }
    my $warnCount = scalar @warnArray;

    $ret_val = open( OUTFILE, ">$outFile" );
    if ( $ret_val != 1 ) {
        my $message = "cannot open File: $outFile";
        LOGDIE($message);
    }
    print OUTFILE "$errCount\t$warnCount\n";
    foreach my $msg (@errorArray) {
        print OUTFILE "1	9001	E	0	0	$msg\n";
        ERROR($msg);
    }
    foreach my $msg (@warnArray) {
        print OUTFILE "1	9002	W	0	0	$msg\n";
        WARN($msg);
    }
    $pplogger->pplogExit($code) if defined($pplogger); 
    close(OUTFILE);
    INFO("############ End $0 script (code = $code)");
    if($code == 10 ) {
       #INFO("++++++++++++++++++++TEST+++++++++++++");
        exit(10);
    } elsif($code == 100) {
        exit(0); 
    }  else {
        exit($code);
    }
}
######

sub formatDate { return formatDateToYYYYMMDD(@_); }

our @months = qw( JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC );

sub formatDateToYYYYMMDD {
    my $date = shift;
    my $tz   = shift;
    my $new_date;
    unless (defined $date){
        WARN (" date value is undefined");
        return $date;
    }
    INFO ("Date : $date");
    ### 2020-Jul-27 jgarcia - added support for date formate like DD-MM-YYY 24H:MI:SS (14/07/2020 23:22:29).
    if($date =~ /(\d{2})\/(\d{2})\/(\d{4})\s+?(\d{1,})\:(\d{1,})\:(\d{1,})/) {

        my $day = $1;
        my $mon = $2;
        if($day > 12 && $mon <= 12 ) {

            $new_date =  sprintf( "%04d/%02d/%02d %02d:%02d:%02d", $3, $mon, $day, $4, $5,$6 );
        } else {
            $new_date = sprintf( "%04d/%02d/%02d %02d:%02d:%02d", $3, $1, $2, $4, $5,$6 );
        }
    }

    elsif ( $date
        =~ /(\d{4})\D(\d{1,2})\D(\d{1,2})\D+(\d{1,2})\D(\d{1,2})\D(\d{1,2})/ )
    {
        $new_date
            = sprintf( "%04d/%02d/%02d %02d:%02d:%02d", $1, $2, $3, $4, $5,
            $6 );

    }
    elsif ( $date
        =~ /(\d{1,2})\D(\d{1,2})\D(\d{4})\D+(\d{1,2})\D(\d{1,2})\D(\d{1,2})/ )
    {
        $new_date
            = sprintf( "%04d/%02d/%02d %02d:%02d:%02d", $3, $1, $2, $4, $5,
            $6 );
        DEBUG("input format is MM/DD/YYYY. $date -> $new_date");

    }
    elsif ( $date =~ /^\d{10}$/ ||  $date =~ /^\d{9}$/  ) {
        if ( defined $tz ) {
            $ENV{'TZ'} = $tz;
        }
        else {
            $ENV{'TZ'} = 'UTC';
        }
        ## assume 10 digit number as unixtime. 10 digit unixtime ranges 2001/09/09 - 2286/11/21
        $new_date = strftime( "%Y/%m/%d %H:%M:%S", localtime($date) );
        DEBUG("input format is unixtime. $date -> $new_date");
        delete $ENV{'TZ'};

    }
    elsif ( $date
        =~ /(\w+)\s+(\d{1,2})\D+(\d{4})\D+(\d{1,2})\D(\d{1,2})\D(\d{1,2})/ )
    {
        my $month = first_index { $_ eq uc(substr( $1, 0, 3 )) } @months;
        if ( $month < 0 ) {
            dpExit( 1, "Invalid date :$date Month is not valid: $month" );
        }
        $new_date = sprintf(
            "%04d/%02d/%02d %02d:%02d:%02d",
            $3, ( $month + 1 ),
            $2, $4, $5, $6
        );
        DEBUG("input format is MMM DD YYYY. $date -> $new_date");
    }
    elsif ( $date
        =~ /(\d{1,2})\D(\w{3})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})/ )
    {
        my $month = first_index { $_ eq uc(substr( $2, 0, 3 )) } @months;
        if ( $month < 0 ) {
            dpExit( 1, "Invalid date :$date Month is not valid: $2->$month" );
        }
        $new_date = sprintf(
            "%04d/%02d/%02d %02d:%02d:%02d",
            2000+$3, ( $month + 1 ),
            $1, $4, $5, $6
        );
        DEBUG("input format is DD-MMM-YY. $date -> $new_date");
    }
    elsif ( $date
        =~ /(\d{1,2})\D(\w{3})\D(\d{4})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})/ )
    {
        my $month = first_index { $_ eq uc(substr( $2, 0, 3 )) } @months;
        if ( $month < 0 ) {
            dpExit( 1, "Invalid date :$date Month is not valid: $2->$month" );
        }
        $new_date = sprintf(
            "%04d/%02d/%02d %02d:%02d:%02d",
            $3, ( $month + 1 ),
            $1, $4, $5, $6
        );
        DEBUG("input format is DD-MMM-YYYY. $date -> $new_date");
    }
    elsif ( $date
        =~ /(\d{1,2})\D(\w{3})\D(\d{1,2})/ )
    {
        my $month = first_index { $_ eq uc(substr( $2, 0, 3 )) } @months;
        if ( $month < 0 ) {
            dpExit( 1, "Invalid date :$date Month is not valid: $2->$month" );
        }
        $new_date = sprintf(
            "%04d/%02d/%02d",
            2000+$3, ( $month + 1 ),
            $1
        );
        DEBUG("input format is DD-MMM-YY. $date -> $new_date");
    }
    elsif ( $date =~ /(\d{4})\D(\d{1,2})\D(\d{1,2})/ )
    {
        $new_date = sprintf( "%04d/%02d/%02d", $1, $2, $3);
        DEBUG("input format is YYYY-MM-DD. $date -> $new_date");
    }
    elsif ( $date =~ /(\d{1,2})\D(\d{1,2})\D(\d{4})/ )
    {
	$new_date = sprintf( "%04d/%02d/%02d", $3, $1, $2);
	DEBUG("input format is M/D/YYYY. $date -> $new_date");
    }
    elsif ( $date =~ /(\d{1,2})\D(\d{1,2})\D(\d{2})\D+(\d{1,2})\D(\d{1,2})\D(\d{1,2})/)#added 08/07/2025 (09/29/2025 21:45:37)
    {
        $new_date
            = sprintf( "%04d/%02d/%02d %02d:%02d:%02d", 2000 + $3, $1, $2, $4, $5, $6);
       #$new_date
       #     = sprintf( "%04d/%02d/%02d", $1, $2, $3);

        DEBUG("input format is YYYY/MM/DD. $date -> $new_date");

    }	
    elsif ($date eq 'NA') {
        WARN (" date value is NA");
    }
    else {
        dpExit( 1, "Invalid date : $date" );
    }

    return $new_date;
}

sub parseDate {
    my ($s) = @_;
    my ( $year, $month, $day, $hour, $minute, $second );

    if ($s =~ m{^\s*(\d{1,4})\W*0*(\d{1,2})\W*0*(\d{1,2})\W*0*
                 (\d{0,2})\W*0*(\d{0,2})\W*0*(\d{0,2})}x
        )
    {
        $year   = $1;
        $month  = $2;
        $day    = $3;
        $hour   = $4;
        $minute = $5;
        $second = $6;
        $hour   |= 0;
        $minute |= 0;
        $second |= 0;    # defaults.
        $year = (
            $year < 100
            ? ( $year < 70 ? 2000 + $year : 1900 + $year )
            : $year
        );
        return timelocal( $second, $minute, $hour, $day, $month - 1, $year );
    }
    return -1;
}

#######
sub validateOutDir {
    my $hOptions = shift;
    my $outdir   = $hOptions->{OUT};
    if ( defined($outdir) ) {
        if ( !-d $outdir ) {
            dpExit( 1, "output direcotry does not exist $outdir" );
        }
        if ( defined( $hOptions->{META} ) and !-d $outdir . "_noMeta" ) {
            mkdir $outdir . "_noMeta";
        }
        if ( defined( $hOptions->{WMAP} ) and !-d $outdir . "_noWMap" ) {
            mkdir $outdir . "_noWMap";
        }
    }
}

sub currentDate {
    return strftime( "%Y/%m/%d %H:%M:%S", localtime( time() ) );
}

sub repNA {
    my $data = trim(shift);
    if ( ( $data eq '' ) or ( !defined($data) or $data =~ /null|undef/i) ) {
        return 'N/A';  
    }
    else {
        return $data;
    }
}

sub trim {
    my ($text) = @_;

    if ($text) {
        $text =~ s/[\n\r]//gs;
        $text =~ s/^\s+//gs;
        $text =~ s/\s+$//gs;
        $text =~ s/\"$//gs;
        $text =~ s/^\"//gs;
        $text =~ s/[^\x09-\x7E]//gs;
    }
    return $text;
}

### Aug 15, 2020 - jgarcia - added forkfile subroutine
### Nov 16, 2020 - kgabato - added "" in line qx(gzip $forkfile); so all files will be in gz
sub forkFile {
	my $openedFile = shift;
    my $forkDir = shift;
    my $filename = shift;
    my $ext = shift;
	my $finalFolder = shift;
	my $forkfile = "";
	if($forkDir ne "") {
		$forkDir = "${forkDir}/${finalFolder}";
		$forkfile = "${forkDir}/${filename}.${ext}";
	}else {
		$forkfile = "${forkDir}/${filename}.${ext}";
	}
    INFO("Forking the file = $openedFile to $forkDir");
    my $gzipForkfile = $forkfile.".gz";
    if(-e $gzipForkfile) {
      INFO("$gzipForkfile already exist");
      INFO("Delete $gzipForkfile");
      unlink $gzipForkfile;
    }
    copy($openedFile, $forkfile);
    INFO("Compress $forkfile with gzip");
    qx(gzip "$forkfile");
}

sub moveFile {
	my $openedFile = shift;
    my $outDir = shift;
    my $filename = shift;
    my $ext = shift;
	my $outfile = "";
    if($filename !~ /\.$ext$/) {
        $outfile = "${outDir}/${filename}.${ext}";
    } else {
        $outfile = "${outDir}/${filename}";
    }
	
	
    INFO("moving the file = $openedFile to $outDir");
    if(-e $outfile) {
      INFO("$outfile already exist");
      INFO("Delete $outfile");
      unlink $outfile;
    }
    INFO("OUTFILE=>$outfile");
    move($openedFile, $outfile);
    if(-e $outfile) {
      INFO("$outfile move successful");
    }
    if(-e $openedFile) {
        unlink $openedFile;
    }
}
### Mar 26, 2021 - jgarcia - added getLoggingTime subroutine
sub getLoggingTime {

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $compressedTimestamp = sprintf ( "%04d%02d%02d%02d%02d%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec);
    return $compressedTimestamp;
}
### Mar 29, 2021 - jgarcia - added withoutExt subroutine to return filename without file extension
sub withoutExt {
    my ($file) = @_;
    return substr($file, 0, rindex($file, '.'));
}

### Mar 29, 2021 - jgarcia - added extOnly subroutine to return file extension only
sub extOnly {
    my ($file) = @_;
    return substr($file, rindex($file, '.') + 1);
}

### May 5, 2021 - jgarcia - subroutine to gzip using open3 reading, writing and error handling
sub doCompressGzip {
    my $file = shift;
    my @values;

    return $file if ( $file =~ /\.Z$|\.gz$/i );

    my $pid = open3( \*GZIP_IN, \*GZIP_OUT, \*GZIP_ERR,
        "/usr/bin/gzip --force -v $file" );
    waitpid( $pid, 0 );
    while (<GZIP_ERR>) {
        @values = split /\s+/;
    }
    close GZIP_IN;
    close GZIP_OUT;
    close GZIP_ERR;

    return $values[$#values];
}


sub formatSourceLot {
	my $sl = shift;
	my $l = shift;
	my $sourceLot = "";
    INFO("SourceLot=>>$sl<<");
    INFO("Lot=>>$l<<");
    if(($sl ne "") && ($sl ne "NA") && ($sl ne "N/A")) {
        $sourceLot = "${sl}.S";
    } else {
      if($l eq "") {
        WARN("NO LotID provided.");
        $sourceLot = "NA";
      } else {
        $sourceLot = "${l}.S";
    }
  }
  INFO("Formatted Source Lot=>>$sourceLot<<||ORIG Source Lot = $sl");
	return($sourceLot);
}

sub checkMetadataByLotMoveToPreprocessingFolder {
    my $model = shift;
    my $hash = shift;
    my $header = $model->header;
    if($hash->{finallot}) {
        $header->isFinalLot(1);
    } 
    my $customMessage = "First lookup original lot=$header->{LOT}";
    my $lot_check_successful = $header->checkLotMetadata($header->{LOT}, $customMessage);
       

    if($lot_check_successful) {
        INFO("metadata verifier script is able to get result from metadata table, pre-processing script expects that the file will be moved to inbox/Processed folder=>".$hash->{outdir});
        #moveFile($hash->{infile}, $hash->{outdir}, $hash->{filename}, $hash->{ext});
        return(0);
    } else {
        if($hash->{inFileAge} > $hash->{fileAge}) {
            INFO("SEND ANYWAY-Forcibly sent to preprocessing staging folder=inbox/Processed, file age is beyond the set threshold, could be loaded to SANDBOX.");
            #moveFile($hash->{infile}, $hash->{outdir}, $hash->{filename}, $hash->{ext});
            return(100);
        } 
        INFO("File is not accepted and will remain in inbox folder, threshold is not yet met and lot metadata is not yet avaiable in refdb");
        return(10); 
    }
}

sub xlsxToHash {
    #my $xlxs = shift;
    #INFO("REF_file=$xlxs");
    my $parser    = Spreadsheet::ParseExcel->new;
    my $workbook  = $parser->parse( shift or die "Please provide a file\n" );
    my $worksheet = $workbook->worksheet(0);

    my %data;
    for my $row ( 1 .. $worksheet->row_range ) {
        my $lot = $worksheet->get_cell( $row, 0 )->value;
        my $waferNum = $worksheet->get_cell( $row, 1 )->value;
        my $value     = $worksheet->get_cell( $row, 3 )->value;
        my $key = "${lot}_${waferNum}";
        #INFO("KEY=$key||VALUE=$value");
        $data{$key} = $value;
    }

    #print Dumper \%data;
    return \%data;

}

sub move_oldest_file {
    my ($source_dir, $destination_dir, $age_limit) = @_;

    # Ensure source and destination directories are provided
    if (!$source_dir || !$destination_dir) {
        dpExit(1,"Usage: move_oldest_file(source_dir, destination_dir, [age_limit]), Please provide the source and destination folders");
    }

    # Open the source directory
    opendir(my $dh, $source_dir) or die "Cannot open directory $source_dir: $!";
    my @files = map { "$source_dir/$_" } grep { -f "$source_dir/$_" } readdir($dh);
    closedir($dh);

    # Sort files by modification time, with oldest first
    @files = sort { (stat($a))[9] <=> (stat($b))[9] } @files;

    # Move the oldest file if it's older than the age limit, or if no age limit is provided
    if (@files) {
        my $oldest_file = $files[0];
        my ($basename, $dirname) = fileparse($oldest_file);
        my $age_in_seconds = time() - (stat($oldest_file))[9];

        # Convert age to human-readable format
        my $age_str = format_age($age_limit);

        if (defined $age_limit) {
            if ($age_in_seconds > $age_limit) {
                move($oldest_file, "$destination_dir/$basename") or die "Failed to move $basename: $!";
                INFO(": Moved $basename to $destination_dir (older than $age_str)");
            } else {
                INFO(": $basename is not older than $age_str");
            }
        } else {
            move($oldest_file, "$destination_dir/$basename") or die "Failed to move $basename: $!";
            INFO(": Moved $basename to $destination_dir");
        }
    } else {
        INFO(": No files found in $source_dir");
    }
}
sub move_files_by_age {
    my ($source_dir, $destination_dir, $age_limit) = @_;

    # Ensure source and destination directories are provided
    if (!$source_dir || !$destination_dir) {
        dpExit(1,"Usage: move_files_by_age(source_dir, destination_dir, age_limit), Please provide the source and destination folders");
    }

    # Open the source directory
    opendir(my $dh, $source_dir) or die "Cannot open directory $source_dir: $!";
    my @files = map { "$source_dir/$_" } grep { -f "$source_dir/$_" } readdir($dh);
    closedir($dh);

    # Sort files by modification time, with oldest first
    @files = sort { (stat($a))[9] <=> (stat($b))[9] } @files;

    # Move files older than or equal to the age limit
    foreach my $file (@files) {
        my ($basename, $dirname) = fileparse($file);
        my $age_in_seconds = time() - (stat($file))[9];
        my $age_str = format_age($age_limit);

        if ($age_in_seconds >= $age_limit) {
            move($file, "$destination_dir/$basename") or die "Failed to move $basename: $!";
            INFO(": Moved $basename to $destination_dir (older than or equal to $age_str)");
        } else {
            INFO(": Stopping file move as $basename is not older than or equal to $age_str");
            last;
        }
    }

    if (!@files) {
        INFO(": No files found in $source_dir");
    }
}

sub format_age {
    my ($age_seconds) = @_;

    # Calculate the age in days and hours
    my $age_days  = int($age_seconds / 86400);
    my $age_hours = int(($age_seconds % 86400) / 3600);

    # Construct the age string
    my $age_str;
    if ($age_days > 0) {
        $age_str = "$age_days day" . ($age_days > 1 ? 's' : '');
        if ($age_hours > 0) {
            $age_str .= " $age_hours hour" . ($age_hours > 1 ? 's' : '');
        }
    } else {
        $age_str = "$age_hours hour" . ($age_hours > 1 ? 's' : '');
    }

    return $age_str;
}

1;

__END__;

=pod

=head1 NAME

PDF::DpLoad - utility module for dataPower preprocessor

=head1 DESCRIPTION

This module provide usefule functions for preprocessor development

=head1 SYNOPSYS

  use PDF::DpLoad;

  dpExit(0);


=head1 FUNCTIONS

=head2 dpExit(exitCode,errorMessage,warnMessage)


print out B<err.jnk> in working direcotry and end the script with the given exitCode.

=over 4

=item exitCode

the code to exit this scirpt. default = 0

=item errorMessage

the error message to print out B<err.jnk>

It can be either string or ArrayRef.

=item warnMessage

the warn message to print out B<err.jnk>

It can be either string or ArrayRef.

=back

sample err.jnk: no error

  dpExit(0);
  ---err.jnk---
  0	0

sample err.jnk: 2 errors and 1 warning

  my $error = ["1st error","2nd error"];
  my $warn = "single warn";
  dpExit(0,$error,$warn);
  ---err.jnk---
  2       1
  1       9001    E       0       0       1st error
  1       9001    E       0       0       2nd error
  1       9002    W       0       0       single warn

If L<PDF::Log> is initiated, messages will be print as ERROR or WARN.

=head2 formatDate(date_text,TZ)

alias to formatDateToYYYYMMDD

=head2 formatDateToYYYYMMDD(date,TZ)

It format date_text to "YYYY/MM/SS HH24:MI:SS".

If the input date_text format is unixtime, get localtime using specified TZ. The default TZ is 'UTC'

The input text must match with one of following RegExp.

  /(\d{4})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})/
  /(\d{1,2})\D(\d{1,2})\D(\d{4})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})/
  /(\w+)\s+(\d{1,2})\D+(\d{4})\D+(\d{1,2})\D(\d{1,2})\D(\d{1,2})/
  /^\d{10}$/

Acceptable input date text example

  /(\d{4})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})/
  2015/03/17 13:04:10
  2015/3/17 13:4:10
  2015-03-17-13-04-10
  2015-03-17T13:04:10
  2015-03-17T13:04:10+00:00

  /(\d{1,2})\D(\d{1,2})\D(\d{4})\D(\d{1,2})\D(\d{1,2})\D(\d{1,2})/
  3/17/2015 13:4:10
  03/17/2015 13:04:10
  03-17-2015_13:04:10

  /(\w+)\s+(\d{1,2})\D+(\d{4})\D+(\d{1,2})\D(\d{1,2})\D(\d{1,2})/
  March 18 2014 10:46:40
  March 18, 2014 10:46:40
  Jan 18 2014, 10:46:40

  /^\d{10}$/  # unix time
  1427791571
  1000000000   # 2001/09/09
  9999999999   # 2286/11/21

=head2 repNA(value)

return NA if the value is undef or '' after L</trim(text)>

=head2 trim(text)

return trimed text by following rule

    $text =~ s/[\n\r]//gs;
    $text =~ s/^\s+//gs;
    $text =~ s/\s+$//gs;
    $text =~ s/\"$//gs;
    $text =~ s/^\"//gs;
    $text =~ s/[^\x09-\x7E]//gs;   # remove double byte

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/03/31 kazukik: add pod

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut
