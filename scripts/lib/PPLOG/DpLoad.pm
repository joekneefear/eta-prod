package PPLOG::DpLoad;

use strict;
use Exporter 'import';
use PDF::Log;
use POSIX qw/strftime/;
use Time::Local;
use List::MoreUtils qw/first_index/;
use Carp qw/longmess/;
our @EXPORT
    = qw/dpExit validateOutDir currentDate parseDate trim repNA formatDate formatDateToYYYYMMDD/;
our $VERSION = "1.0";

sub dpExit {
    my $code  = shift // 0;
    my $pplogger = shift;
    my $error = shift;
    my $warn  = shift;
    my @errorArray;
    my @warnArray;
    my $outFile = "err.jnk";
    my $ret_val;
    my $trace = longmess;
    $trace =~ s/\n/\t/g;
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
        $pplogger->setLogMsg($msg);
        ERROR($msg);
    }
    foreach my $msg (@warnArray) {
        print OUTFILE "1	9002	W	0	0	$msg\n";
        $pplogger->setLogMsg($msg);
        WARN($msg);
    }
    close(OUTFILE);

    INFO("############ End $0 script (code = $code)");
    $pplogger->setProcCode($code);
    $pplogger->insert_db();
    exit($code);
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
    if ( $date
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
    if ( ( $data eq '' ) or ( !defined($data) ) ) {
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

  

