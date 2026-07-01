#### PDF::DpData::Limit
package PDF::DpData::Limit;
use strict;
use PDF::Log;
use base qw/PDF::DpData::Base/;
use PDF::DpLoad;
use PDF::DAO;
use PDF::DpWriter;
use File::Basename qw/basename/;

# LIMITS_STR
# <LIMIT>
# testNumber,testName,Units,LPL,HPL,LSL,HSL,LOL,HOL,LWL,HWL
# </LIMIT

sub list {
    qw/
        VERSION CREATION_DATE
        PROGRAM_CLASS PROGRAM REVISION DATE PROCESS LOT
        /;
}

my $attr = [
    qw/
        scriptName input_file limit_file /
];
sub array {qw / testItems conditionNames tests/}

__PACKAGE__->mk_accessors( list, @$attr, array );

sub new {
    my ( $class, $args ) = @_;
    foreach my $key (%$args) {
        if ( $key =~ /TIME$|DATE$/ ) {
            my $value = formatDate( $args->{$key} );
            $args->{$key} = $value;
        }
    }
    my $self = $class->SUPER::new($args);
    $self->CREATION_DATE(currentDate);
    $self->testItems( [qw/number name units/] );
    return $self;
}

sub set {
    my ( $self, $key ) = splice( @_, 0, 2 );
    if ( $key =~ /DATE$/ ) {
        my $value = shift @_;
        push( @_, formatDateToYYYYMMDD($value) );
    }
    $self->SUPER::set( $key, @_ );
}

sub copyHeader {
    my $self   = shift;
    my $header = shift;
    $self->VERSION( $header->{VERSION} );
    $self->CREATION_DATE( $header->{CREATION_DATE} );
    $self->PROGRAM_CLASS( $header->{PROGRAM_CLASS} );
    $self->PROGRAM( $header->{PROGRAM} );
    if(ref($header) eq "PDF::DpData::MetaData") {
	$self->REVISION( $header->{RECIPE_REVISION} );
    }else{
   	$self->REVISION( $header->{REVISION} );
    }
    $self->PROCESS( $header->PROCESS );
    $self->DATE( $header->START_TIME );
    $self->LOT( $header->{LOT} );
    return 1;
}

sub limit_file {
    my  $self = shift;

        if ( defined $self->{limit_file} ) {
            return $self->{limit_file};
        }
        my $date = $self->DATE;
	my $lot = $self->LOT;
	   $lot =~ s/[\n\$\%\^\&\*\{\}\[\]\|\!\~\/\`\<\>\:\;\"\,\']//sg;
	   $lot =~ s/^\s+|\s+$//g;
	   $lot =~ s/\s+/_/g;

        $date =~ s/:|\s//g;
        $date =~ s|/||g;
        unless ( defined $self->PROGRAM ) {
            dpExit( 1,
                "Cannot create limit file because PROGRAM is not defined" );
        }
        unless ( defined $self->REVISION ) {
            WARN("REVISION is not defined. Set NA as default REVISION");
            $self->REVISION('NA');
        }
        my $revision = $self->REVISION;
        $revision =~ s/\W//g;

		$revision =~ s/\s+//g;
		
        my $program = $self->PROGRAM;
        $program =~ s/\W//g;
        my $outfile = join(
            "_",
            (   "LIMIT",         $self->PROGRAM_CLASS, $program,
                $revision, $lot, $date
            )
        ) ;
        $self->set('limit_file',$outfile);
        return $outfile;
}

sub isNew{
   my $self = shift;
   my $count = getRefdb->isNewLimit($self);
   return $count; 
}

sub registerRefdb{
    my $self    = shift;
    my $values  = {%$self};
    return getRefdb->checkAndInsertLimit($values) ;
}


1;

__END__;

=pod

=head1 NAME

PDF::DpData::Limit - Limit object for all parametric datasource.

=head1 SYNOPSIS  
  
  if ($model->isLimitNew){ 
    $model->buildLimit;
    $model->limit->conditionNames(...);
    $formatter->printLimit;
    $model->limit->registerRefdb;
  }

=head1 Attributes (target of toString)
  
  VERSION 
  CREATION_DATE  -- YYYY/MM/DD HH24:MI:SS
  PROGRAM_CLASS  -- program class number 
  PROGRAM        -- No prefix 
  REVISION 
  DATE           -- YYYY/MM/DD HH24:MI:SS
  PROCESS

=head1 Attributes 
  
  limit_file     -- output file name. Automatically build as 
                    LIMIT_<PROGRAM_CLASS>_<PROGRAM>_<REVISION>_<DATE>.limit
  input_file     -- the input file for the main script

=head1 Atributes -- ArrayRef

  conditionNames -- Array ref of condition names to print in <CONDITION>
                    If conditionNames is not defined, formatter will notprint <CONDITION> section

=head1 METHODS

=head2 toString()

inherit from L<PDF::DpData::Base.pm>

=head2 copyHeader(HeaderLong or HeaderShort) 

copy header values to this object

VERSION,CREATION_DATE,PROGRAM_CLASS,PROGRAM,REVISION,DATE

DATE is copied from START_DATE  

=head2 registerRefdb

insert into PP_LIMITS table 

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/03/10 kazukik: output IFF format
 2015/03/30 kazukik: refactor modules
 2015/04/20 kazukik: remove printOut method
 2015/11/18 jgarcia: added PROCESS into Header
 2016/12/20 gmiole:  added LOT in Header section
 2018/08/07 ealfanta: append lot in the limit filename
 2018/08/08 ealfanta: remove special chars from lot

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

