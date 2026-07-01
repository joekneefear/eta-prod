# SVN $Id: DpWriter.pm 2641 2020-11-16 06:11:19Z dpower $
# 2015-05-19 eric: Added 'forSBox' to sandbox data other then noWMap, noMeta
# 2015-07-09 eric: Only postfix _nc if filename does not end in _nc.
# 2020-08-15 jgarcia : added support of forking data into specified folder, initially identified as PRODUCTION, SANDBOX, QDE
# 2020-11-16 kgabato : added "" double qoutes in this line qx(gzip "$forkfile"); so all filename will be in gz
# 2021-03-24 jgarcia : modified to write IFF to either PRODUCTION, SANDBOX, QDE folder.
# 2021-03-24 jgarcia : added timestamp to IFF filename.
# 2025-08-13 jgarcia : make timestamp optional

package PDF::DpWriter;
use strict;
use base qw(Class::Accessor);
use PDF::Log;
use PDF::DpLoad;
use File::Copy;
use File::Basename qw/fileparse/;
use IO::Compress::Gzip qw(gzip $GzipError);
our $VERSION = "1.1";
use List::Util qw(any);
use List::MoreUtils qw(first_index last_index indexes);
use IO::Tee;

my $attr = [
    qw/
        outdir basename ext noMeta noWMap wmapIsEmpty forSBox FH openedfile forkedfile forkdir qde gzipIFF pplogger
        appendTimestampInFilename site script_name
        /
];

my $forkDirectory = "";

__PACKAGE__->mk_accessors(@$attr);

sub new {
    my ($class, $args) = @_;
    $args ||= {};

    my $outdir  = delete $args->{outdir};
    my $forkdir = delete $args->{forkdir};
    my $qde     = delete $args->{qde};
    my $noMeta  = delete $args->{noMeta};
    my $noWMap  = delete $args->{noWMap};
    my $wmapIsEmpty = delete $args->{wmapIsEmpty};
    my $forSBox = delete $args->{forSBox};
    my $gzipIFF = delete $args->{gzipIFF};
    my $pplogger = delete $args->{pplogger};

    # New optional controls
    my $use_ts = exists $args->{appendTimestampInFilename} ? delete $args->{appendTimestampInFilename} : 1; # default True for backward compatibility
    my $site         = delete $args->{site};
    my $script_name  = delete $args->{script_name};

    my $self = $class->SUPER::new($args);

    if (defined $outdir) {
        $self->outdir($outdir);
        $self->noMeta($noMeta);
        $self->noWMap($noWMap);
        $self->wmapIsEmpty($wmapIsEmpty);
        $self->forSBox($forSBox);
        $self->gzipIFF($gzipIFF);
        $self->pplogger($pplogger);
    }

    if (defined $forkdir) {
        $self->forkdir($forkdir);
    }
    if (defined $qde) {
        $self->qde($qde);
    }
    if (defined $pplogger) {
        $self->pplogger($pplogger);
    }

    # Set new flags/metadata
    $self->appendTimestampInFilename($use_ts);
    $self->site($site)               if defined $site;
    $self->script_name($script_name) if defined $script_name;

    # Conditionally apply timestamp to basename
    $self->_set_timestamp_to_basename();

    return $self;
}

sub should_apply_timestamp {
    my ($self) = @_;

    # Default to True if not set (backward compatible)
    my $use = defined $self->appendTimestampInFilename ? $self->appendTimestampInFilename : 1;

    # Optional skip lists
    my %skip_sites    = ();
    my %skip_scripts  = (); 

    if (defined $self->site && exists $skip_sites{$self->site}) {
        return 0;
    }
    if (defined $self->script_name && exists $skip_scripts{$self->script_name}) {
        return 0;
    }
    return $use ? 1 : 0;
}

sub _set_timestamp_to_basename {
    my ($self) = @_;
    my $basename = $self->basename;

    return unless defined $basename;
    return unless $self->should_apply_timestamp();

    my ($fname, $fdir, $ext) = fileparse($basename, qr/\.[^.]*$/);

    # If the last extension is .gz or .zip, strip it and use the inner extension
    if (defined $ext && $ext =~ /\.gz$|\.zip$/i) {
        my $temp = $basename;
        $temp =~ s/\.gz$|\.zip$//i;
        ($fname, $fdir, $ext) = fileparse($temp, qr/\.[^.]*$/);
    }

    my $date = &getLoggingTime();
    $self->basename($fname . "_" . $date . (defined $ext ? $ext : ''));
}

sub set {
    my ( $self, $key ) = splice( @_, 0, 2 );
    if ( $key eq 'outdir' ) {
        my $value = $_[0];
        INFO("out dir = $value");
        if ( !-d $value ) {
            dpExit( 1, "output directory does not exist $value" );
        }
    }
    elsif ( $key eq 'forkdir' ) {
        	my $value = $_[0];
		INFO("Fork directory = $value");

		if ( !-d $value ) {
			WARN("Warning! Fork directory does not exists");
		}
    }
    elsif ( $key eq 'qde' ) {
        	my $value = $_[0];
		unless ( defined( $self->outdir ) ) {
            dpExit( 1, "outdir must set before QDE called" );
        }
		#INFO("For QDE fork directory");
    }
    elsif ( $key eq 'noWMap' ) {
        unless ( defined( $self->outdir ) ) {
            dpExit( 1, "outdir must set before noWMap called" );
        }
    }
    elsif ( $key eq 'wmapIsEmpty' ) {
        unless ( defined( $self->outdir ) ) {
            dpExit( 1, "outdir must set before wmapIsEmpty called" );
        }
    }
    elsif ( $key eq 'noMeta' ) {
        unless ( defined( $self->outdir ) ) {
            dpExit( 1, "outdir must set before noMeta called" );
        }
    }
    elsif ( $key eq 'forSBox' ) {
        unless ( defined( $self->outdir ) ) {
            dpExit( 1, "outdir must set before forSBox called" );
        }
    }
    elsif ($key eq 'gzipIFF') {
         unless ( defined( $self->outdir ) ) {
            dpExit( 1, "outdir must set before gzipIFF called" );
        }
    }
    $self->SUPER::set( $key, @_ );
}

sub outfile {
    my $self = shift;
    unless ( defined( $self->basename ) and defined( $self->ext ) ) {
        dpExit( 1, "outfile basename or extension is not defined" );
    }
    if ( $self->noWMap ) #&& $self->ext ne "limit")
    {
    	if ( $self->ext !~ /\_nc$/) {
    	   $self->ext( $self->ext."_nc");
	    }
    }
    if ( $self->noMeta or $self->wmapIsEmpty or $self->forSBox) {
        my $outdir = $self->outdir."/SANDBOX";
        #$self->pplogger->setOutDir($outdir);
        setOutputDirectoryToPPLogger($outdir);
        if ( !-d $outdir ) {
            mkdir $outdir;
        }
        return
              "$outdir/"
            . $self->basename . "."
            . $self->ext;
    } elsif ($self->qde) {
		my $outdir = $self->outdir."/QDE";
        setOutputDirectoryToPPLogger($outdir);
        #$self->pplogger->setOutDir($outdir);
        if ( !-d $outdir ) {
            mkdir $outdir;
        }
        return
              "$outdir/"
            . $self->basename . "."
            . $self->ext;
	}
    else {
		my $outdir = $self->outdir."/PRODUCTION";
        setOutputDirectoryToPPLogger($outdir);
        #$self->pplogger->setOutDir($outdir);
        if ( !-d $outdir ) {
            mkdir $outdir;
        }
		return
              "$outdir/"
            . $self->basename . "."
            . $self->ext;
        #return $self->outdir . "/" . $self->basename . "." . $self->ext;
    }

}


sub getForkFile {
    my $self = shift;
    my $qde = $self->qde;
    $forkDirectory = "";
    unless ( defined( $self->basename ) and defined( $self->ext ) ) {
        dpExit( 1, "forkfile basename or extension is not defined" );
    }

    if ( $self->noMeta or $self->wmapIsEmpty or $self->forSBox) {
        $forkDirectory = $self->forkdir."/SANDBOX";
        if ( !-d $forkDirectory ) {
            mkdir $forkDirectory;
        }
        return
              "$forkDirectory/"
            . $self->basename . "."
            . $self->ext;
    }
    elsif($qde) {
      $forkDirectory = $self->forkdir."/QDE";
       if ( !-d $forkDirectory ) {
            mkdir $forkDirectory;
        }
      return "$forkDirectory/" . $self->basename . "." . $self->ext;
    }
    else {
        $forkDirectory = $self->forkdir."/PRODUCTION";
         if ( !-d $forkDirectory ) {
            mkdir $forkDirectory;
        }
        return "$forkDirectory/" . $self->basename . "." . $self->ext;
    }
}

sub open {
    my $self    = shift;
    my $outfile = $self->outfile();
    my $bothFH;
    open FH, ">", $outfile or dpExit( 1, "Failed to open " . $outfile );
    $self->FH(*FH);
    INFO( "outfile = " . $outfile );
    $self->openedfile($outfile);

    return $self->FH;
}

sub put {
    my $self = shift;
    my $str  = shift;
    my $FH   = $self->FH;
    print $FH $str;
}

sub close {
    my $self = shift;
    close $self->FH;
    if($self->forkdir ne "") {
     $self->fork();
	}elsif($self->gzipIFF ne "") {
        $self->compressToGzipIFF();
    }
}

sub cancel {
    my $self = shift;
    close $self->FH;
    unlink $self->openedfile;
    INFO( "outfile removed: " . $self->openedfile );
}

sub fork {
	my $self = shift;
	my $forkfile = $self->getForkFile();
	INFO("Forking the file = $self->{openedfile} to $forkDirectory");
    my $gzipForkfile = $forkfile.".gz";
    if(-e $gzipForkfile) {
      INFO("$gzipForkfile already exist");
      INFO("Delete $gzipForkfile");
      unlink $gzipForkfile;
    }
    copy($self->openedfile, $forkfile);
    $self->forkedfile($forkfile);
    INFO("Compress $forkfile with gzip");
    qx(gzip "$forkfile");
}
sub compressToGzipIFF {
    my $self = shift;
    my $gzipFile = $self->{openedfile}.".gz";
    gzip $self->{openedfile} => "$gzipFile" or WARN("Unable to gzip $self->{openedfile}");
    if(-e $gzipFile) {
	#INFO("gzip IFF file = $gzipFile");
    #INFO("Delete original IFF=$self->{openedfile}");
	unlink($self->openedfile);
}
sub setOutputDirectoryToPPLogger {
    my $self = shift;
    my $outdir = shift;
    if($outdir ne "") {
        $self->pplogger->setOutDir($outdir);
    } 
}

}

1;

__END__;

=pod

=head1 NAME

Writer object to handle exceptions on Meta and WMap not found.

=head1 DESCRIPTION

Most of the preprocessor need to lookup product and/or lot information from REFDB tables. If corresponding data is not available, each script must output the iff files to specified destination.

This module provide standarized way to manage destination direcotry on exceptions.

=over 4

=item *

lot or product not found in REFDB.PP_RPOD, PP_LOT, PP_FINALLOT

ex) outdir = "stage" --> output to "stage_noMeta"

=item *

wafer map config is not found or not confirmed in REFDB.PP_WMAP

ex) outdir = "stage" --> output to "stage_noWMap"

=item *

When both lot/product and wafer map not found, output to "_noMeta"

=back

=head1 SYNOPSYS

  use File::Basename qw/basename/;
  use PDF::DpWriter

  my $wr=PDF::DpWriter->new(
    {
      outdir => "/data/mydata/stage",
      basename => (basename $infile),
      ext => 'iff'
    }
  );

  $wr->open;
  $wr->put(<HEADER>\n");
  $wr->put($header->toString);
  $wr->put(</HEADER>\n");

  $wr->close;

Also you can use FileHander

  my $fh = $wr->open;
  print $fh "<DATA>\n";

=head1 METHOD

=head2 noMeta

add "_noMeta" surfix to output directory.

  $wr->noMeta(1);

=head2 noWMap

add "_noWMap" surfix to output directory.

  $wr->noWMap(1);

=head2 open

open output file and return file handler

outdir must exist.

=over 4

=item *
output filename :  "$outdir/$basename.$ext"

=item *
if noMeta = true,  "$outdir_sandbox/$basename.$ext"

=item *
if noWMap = true,  "$outdir_sandbox/$basename.$ext"

=back

=head2 put

print strings to opened file. \n will NOT be added.

=head2 close

close the opened file.

=head2 cancel

close the opened file and remove it.

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/03/31 kazukik: 1st verion
 2015/04/22 kazukik: change outdir to _sanbox when noMeta or noWMap is true.

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut
