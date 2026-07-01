# SVN $Id: Runner.pm 1622 2016-05-12 09:17:39Z dpower $
package PDF::Test::Runner;
use strict;
use PDF::Log;
use base qw/PDF::DpData::Base/;
use PDF::DAO;
use Text::Diff;
use Test::More;
use File::Basename qw/basename/;
use PDF::DpData;

my $attr = [qw/ base dir outdir out script option
         isFinalLot isRelLot ignoreWMap
         infile header limit 
         /];
sub array { qw/wafer /}

__PACKAGE__->mk_accessors(array,@$attr);
sub clear {
   my $self = shift;
   $self->{out} = undef;
   $self->{wafer} = [];
   $self->{option} = undef;
   $self->{isFinalLot} = undef;
   $self->{isRelLot} = undef;
   $self->{infile} = undef;
   $self->{limit} = undef;
   $self->{header} = undef;
}
sub header {
    my $self= shift;
    if ( defined $self->{header} ) {
        return $self->{header};
    }
    my $header = new_headerLong;
    my $goodfile;
    if (@{$self->wafer}){
       $goodfile = $self->goodfile($self->wafer->[0]);
    } else {
       $goodfile = $self->goodfile;
    } 
    if ( -f $goodfile ) {
        my ( $program, $rev, $class, $stime );
        open OUTFILE, "<", $goodfile;
        while (<OUTFILE>) {
            if (/^PROGRAM_CLASS=(.*)/) {
                my $v = $1;
                $v =~ s|^N/A$||g;
                $header->PROGRAM_CLASS($v);
            }
            if (/^PROGRAM=(.*)/) {
                my $v = $1;
                 $v =~ s|^N/A$||g;
                $header->PROGRAM($v);
            }
            if (/^REVISION=(.*)/) {
                my $v = $1;
                $v =~ s|^N/A$||g;
                $header->REVISION($v);
            }
            if (/^PRODUCT=(.*)/) {
                my $v = $1;
                $v =~ s|^N/A$||g;
                $header->PRODUCT($v);
            }
            if (/^LOT=(.*)/) {
                my $v = $1;
                $v =~ s|^N/A$||g;
                $header->LOT($v);
            }
            if (/^START_TIME=(.*)/) {
                my $v = $1;
                $header->START_TIME($v);
                last;
            }
        }
        $header->isFinalLot($self->isFinalLot);
	$header->isRelLot($self->isRelLot);
        $self->set('header',$header);
    return $header;
    } else {
     ERROR ("good file not found ".$goodfile);
     return undef;
    }
}

sub out {
    my $self = shift;
    if ( defined $self->{out} ) {
        return $self->{out};
    }
    my $out = $self->outdir;
    if (defined $self->header){
	    my $wmap = new_wmap_from_refdb($self->header->PRODUCT, 'SEPM');
	    if (! $self->header->populateMeta){
	       $out .= "_sandbox";
	    } elsif (! $self->ignoreWMap and ( $wmap->isEmpty or ! $wmap->confirmed) ){
	       $out .= "_sandbox";
	    }
    } 
    $self->set('out',$out);
    return $out; 
}

sub outfile {
    my $self = shift;
    my $waferNum = shift;
    my $outdir  = $self->base . "/" . $self->dir . "/" . $self->out;
    my $outfile = "$outdir/" . $self->infile;
    if ( defined $waferNum ) {
        $outfile .= "_".sprintf("%02d",$waferNum);
    }
    $outfile .= ".iff";
    return $outfile;
}

sub limitfile{
    my $self = shift;
    return 0 unless(defined $self->limit);
    my $outdir  = $self->base . "/" . $self->dir . "/" . $self->out;
    my $outfile = "$outdir/" . $self->limit->limit_file.".limit";
    return $outfile; 
}
sub goodlimit{
    my $self = shift;
    return 0 unless(defined $self->limit);
    my $outdir  = $self->base . "/" . $self->dir . "/good";
    my $outfile = "$outdir/" . $self->limit->limit_file.".limit";
    return $outfile; 
}

sub goodfile {
  my $self = shift;
  my $waferNum = shift;
    my $outdir  = $self->base . "/" . $self->dir . "/good";
    my $outfile = "$outdir/" . $self->infile;
    if ( defined $waferNum ) {
        $outfile .= "_".sprintf("%02d",$waferNum);
    }
    $outfile .= ".iff";
   return $outfile;
}

sub existsGoodfile {
    my $self = shift;
    my $goodfile;
    if (@{$self->wafer}){
       $goodfile = $self->goodfile($self->wafer->[0]);
    } else {
       $goodfile = $self->goodfile;
    } 
    if ( -f $goodfile ) {
       return 1;
    } else {
       return 0;
    }
}

sub limit {
    my $self = shift;
    if ( defined $self->{limit} ) {
        return $self->{limit};
    }
    unless (defined $self->header){
      return undef;
    }
    my $limit = new_limit;
    $limit->copyHeader($self->header);
    $self->set('limit',$limit);
    return $limit;
}

sub diffFile{
  my $self=shift;
  if (@{$self->wafer}){
    foreach my $waferNum (@{$self->wafer}){
      is (-f $self->outfile($waferNum),1,"Outfile created:".$self->outfile($waferNum));
      my $goodfile = $self->goodfile($waferNum);
      if (-f $goodfile){
         my $diff = diff($self->outfile($waferNum), $goodfile,{STYLE =>'OldStyle'});
         is(scalar(split("\n",$diff)),4,"Diff:".(basename $self->outfile($waferNum)));
      } else {
         WARN ("Good file not exists:$goodfile");
      } 
    }
  } else {
      is (-f $self->outfile,1,"Outfile created:".$self->outfile);
      my $goodfile = $self->goodfile;
      if (-f $goodfile){
        my $diff = diff($self->outfile, $goodfile,{STYLE =>'OldStyle'});
        is(scalar(split("\n",$diff)),4,"Diff:".(basename $self->outfile));
      } else {
         WARN ("Good file not exists:$goodfile");
      } 
   } 
}

sub diffLimit{
  my $self=shift;
 if (-f $self->goodlimit){
     my $diff = diff($self->limitfile, $self->goodlimit,{STYLE =>'OldStyle'});
    is(scalar(split("\n",$diff)),4,"DiffLiimt:".(basename $self->limitfile));
      } else {
         WARN ("Good Limit file not exists:".$self->goodlimit);
      } 
}
sub deleteOutfile{
  my $self = shift;
  if (@{$self->wafer}){
    foreach my $waferNum (@{$self->wafer}){
    if( -f $self->outfile($waferNum)) {
      unlink $self->outfile($waferNum);
    }
    }
  } else {
    if( -f $self->outfile) {
      unlink $self->outfile;
    }
  }
}
sub deleteLimit {
  my $self= shift;
  my $limit = $self->limit;
  if (defined $limit) {
	  my $values->{PROGRAM} = $limit->PROGRAM;
	  $values->{REVISION} = $limit->REVISION;
	  getRefdb->delete('pp_limits',$values);
          unlink $limit->limit_file;
          return 1;
  } else {
     return 0;
  }
}

sub run {
    my $self       = shift;
    my $infilePath = $self->base . "/" . $self->dir . "/" . $self->infile;
    my $outdir     = $self->base . "/" . $self->dir . "/stage";
    $self->deleteOutfile;
    my $command = "./" . $self->script;
    $command .= " $infilePath ";
    $command .= " --out $outdir ";
    if ($self->isFinalLot) {
          $command .= " --finallot ";
    }
    if ($self->isRelLot) {
    	$command .= " --rellot ";
    }	
    $command .= $self->option . " ";
    $command .= join( " ", @ARGV );
    INFO($command);
    my $ret = system($command);
    is ($ret,0,"command ".$self->script." executed with exit 0") or ERROR($command);
}

1;

=pod

=head1 NAME

PDF::Test::Runner - Testing framework for PPDF (Pre-Processor Development Framework)

=head1 DESCRIPTION

This class provide testing framework for PPDF in order to enable B<Test First> practice for pp development.

The developer is encourage to write test script before making changes in parser or main pl files.

If you are not familiar with L<Test::More|http://search.cpan.org/perldoc?Test::More> read the manual and usage in CPAN or google.

The basic idea of this test is execute B<diff> the output file and already known good file. The good file is generated in the last good run by the target <script>. The good file must be save in <base>/<dir>/good folder.

=head1 Workflow

=over 4

=item 1 Run developed script with TestRunnder without good file.
  
The test will fail but the output file will be created if the developed Parser and main pl is well implemeted.

Check the file is expected or not manuaaly.

=item 2 Copy generated file to good folder

  cp <base>/<dir>/<out>/<outputfile> <baes>/<dir>/good

  # you may need to mkdir good folder if the folder doesn't exists

=item 3 run again with TestRunner

This time, the test runner compare with good file and the output file.

The CREATION_DATE field must be different because this field is populated by the current time. The L</diffFile> method ignore this part and make the judgment.

=back

=head1 SYNOPSYS

  use Test::More;
  use PDF::Test::Runner;
  use strict;
  
  PDF::Log->init();
  
  our $runner = PDF::Test::Runner->new;
  $runner->base('/home/dpower/project/work/test_data');
  $runner->dir('stdf');
  $runner->script('fcs_stdf_IFF.pl');
  $runner->outdir('stage');

  our $file = 'amkor_csp_M000778570_25_M000778570_E1_CP_CP1_021915132506.STD';
    # subtest $file => sub {   # uncomment this line if you want to skipt this test
    plan skip_all => 'skip';
    $runner->infile($file);
    $runner->isFinalLot(0);
    $runner->wafer([25]);
    $runner->deleteLimit;
    $runner->run;
    $runner->diffFile;
    $runner->diffLimit;
  };
  
  $runner->clear;
  
  our $file = "pmft_H013934643_PMFT_ADVAN.ADVT_20150323205401_STDF";
    # subtest $file => sub {
    plan skip_all => 'skip';
    $runner->infile($file);
    $runner->outdir('stage');
    $runner->isFinalLot(1);
    $runner->deleteLimit;
    $runner->run;
    $runner->diffFile;
    $runner->diffLimit;
  };
  
  done_testing
 
=head1 ATTRIBUTES

  base       - base directory of test data
  dir        - sub directory under <base> direcotry
  outdir     - out directory will be set in pp script --out option. Typicaly "stage"
  script     - pp script name
  option     - option to pass to <script>. Other than --out and --finalLot  
  isFinalLot - same as isFinalLot in most of pp scirpt 
  ignoreWMap - set 1 if the <script> doesn't output <WMAP>
  infile     - file name to test. base name only.
  limit      - set L<PDF::DpData::Limit> object if the <script> genearte limit only.

=head1 ATTRIBUTES -- Array Ref

  wafer      - wafer numbers in the <infile>

=head1 METHODS

=head2 run

=over 4

run <script> with options specified in <out>, <isFinalLot> and <option>, then test 2 cases.

=item 1 exit code = 0 

=item 2 the expected output file is generated.

=back

=head2 diffFile

Compare output file and good file by diff command. Because CREATION_DATE is current time, the diff ouput 4 lines is expected as OK result.

the output file name is estimated by following logic;

  infile name as basename
  add _<wafer number> if wafer attribute is defined
  if wafer has more than 2 numbers, which means infile contains more than 2 wafers data, diffFile will execute diff command for each files.
  add .iff as extension
  directory based on <out> parameter
  check good file and get LOT, PRODUCT
  check if the LOT has meta data in PP_LOT or PP_FINALLOT.
  check if the PP_WMAP has wmap data and confirmed = 1 for the PRODUCT
  if meta not found nor wmap is not confirmed, the output directory will be <out>_sandbox 

=head2 diffLimit

Compare limit file and good limit file by diff command.

the output limit file name is estimated by following logic;

  get PROGRAM_CLASS, PROGRAM ,REVISION and DATE from good file.
  the limit file name = LIMIT_<PROGRAM_CLASS>_<PROGRAM>_<REVISION>_<DATE>.limit
  remove non alpha-numeric char.

=head2 deleteLimit

Remove row from PP_LIMIT for the infile. The PROGRAM and REVISION is found in good file.

This will enforce to re-generate limit file for testing.

B<Do not call this method,> if you are working on production environment.

=head2 clear

clear following object as undef to reuse this class instance for next test file.

  out
  wafer
  option
  isFinalLot
  infile
  limit
  header

This is important call this method before test next file.

If not called, the result will be unexpected.

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/04/27 kazukik: new release

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

