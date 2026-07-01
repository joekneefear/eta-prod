# SVN $Id: Model.pm 2568 2020-09-01 13:46:44Z dpower $
# 2015/Jun/04 jgarcia : Added forSBflag attribute.
# 2015/Jul/13 jgarcia : change the order of the condition in updateWmap subroutine. Not check wmap if it is empty, when wmap object has not been initialized.
# 2015/Jul/16 jgarcia : updated to support inserting configs from other map formats like AWW, ASC and NAM maps into pp_wmap.#
# 2015-Aug-18 Eric	: Added datasource FET in updateWMap
# 2016-Feb-15 Gilbert   : Added unprobed in attr dies
# 2016-Mar-16 Eric	: added cnt in sub array
# 2016-Apr-25 Eric	: return rels in sub array
# 2017-Feb-24 Gilbert   : added SINF on subroutine updateWMap
# 2020-Jun-18 jgarcia - added touchdown_num
# 2021-May-12 Eric	: added org_x and org_y in die model
#<<<<<<< HEAD
# 2021-Sep-16 gmllego   : added ecid.
#=======
# 2022-Feb-19 jag   : added support for diel level ECID data.
# 2022-Feb-19 jag   : added support for SICBurnIn die level runtime readtime data.
# 2025-Mar-12 eric	: added die level bindesc and testtime
#>>>>>>> 0af60b8432d9d46821e0f93ee6ebf30eb5bde49d

package PDF::DpData::Model;
use strict;
use PDF::DpLoad;
use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";
use PDF::Log;
use PDF::DAO;

my $attr = [qw/header wmap limit misc dataSource forSBflag programOrg cfg_tester_type defect/];

sub array{
  return qw/ wafers tests sbins hbins dies rels custindexes/;
}

sub updateProgram{
 my $self = shift;
 my $applyPGM = shift;
 my $program = $self->header->PROGRAM;
 my $progrev = $self->header->REVISION;
 $self->programOrg($program);
 # 13-Jun-2015 S. Boothby Only add product ID to PCM PPID.
 # 23-Nov-2015 jgarcia - add process to PCMP PPID and product to PCM for PSA PPID
 if ( defined( $self->header->PROGRAM_CLASS ))
 {
	if ( $self->header->PROGRAM_CLASS == 5 )
	{
		if ($applyPGM =~ /Product/i) {

			$program .= "::".$self->header->PRODUCT;
		}
		elsif ($applyPGM =~ /Process/i)  {

			if ($self->header->PROCESS ne "") {
				my $noSpaceProcess = $self->header->PROCESS;
				$noSpaceProcess =~ s/\s+/\_/g;
				$program .= "::".$noSpaceProcess;
			} else {
				#$self->header->{PROCESS} = "UNKNOWN";
				# 25-Nov-2015 jgarcia - assign UNKNOWN as PROCESS value to Program name if no PROCESS from the db
				$program .= "::"."UNKNOWN";
			}

		}
	}
 }
 else
 {
 	# Require program class
	dpExit(1,"PROGRAM_CLASS not defined in header.");
 }
 my $pgm_ext = "";
 my $cfg_id = "";
 if ( defined $self->wmap )
 {
	$cfg_id = $self->wmap->cfg_id;
	if ( $self->wmap->isEmpty || $self->wmap->confirmed == 0 )
	{
		$pgm_ext = "-NC";
	}
 }
 if( $applyPGM eq "MAP_PGM" ) {
	 $program .= "::".$cfg_id."::".$self->dataSource.$pgm_ext;
 }elsif ( $applyPGM eq "MAP_PGM_REV") {
	if ($progrev ne "" || $progrev ne "NA") {
		INFO($applyPGM." option is used. Adding program revision to program name.");
		$program .= "::".$cfg_id."::".$progrev."::".$self->dataSource.$pgm_ext;
	}
	else {
		$program .= "::".$cfg_id."::".$self->dataSource.$pgm_ext;
	}

 }else{
	$program .= "::".$self->dataSource;
 }
 $self->header->PROGRAM($program);
 $program =~ s/\'//;
 return $program;
}


sub updateWMap{

  my $self = shift;

  my $wmap = $self->wmap;

  INFO( " Get WMAP from REFDB");
  if( !( $self->header->CFG_TESTER_TYPE eq "N/A" or $self->header->CFG_TESTER_TYPE eq "NA")) {
		$wmap = PDF::DpData::WMap->new_from_refdb($self->header->PRODUCT, $self->header->CFG_TESTER_TYPE, $self->header->EQUIP6_ID);

	if ((($self->dataSource eq 'SEPM') or ($self->dataSource eq 'SZ') or ($self->dataSource eq 'AWW') or ($self->dataSource eq 'NAM')
	or ($self->dataSource eq 'ASC') or ($self->dataSource eq 'SINF') or ($self->dataSource eq 'FET')) and $wmap->isEmpty){
    		$wmap = $self->wmap;
		if(defined $wmap){
			$wmap->product($self->header->PRODUCT);
			$wmap->tester_type($self->header->CFG_TESTER_TYPE);
			$wmap->location($self->header->EQUIP6_ID);
			$wmap->register_refdb;
			####  for auto confirmed
			#	07-Jul-15 SAB Don't auto-confirm new configs.
			$wmap->confirmed_flag;
		}
  	}
  	elsif($wmap->isEmpty){
		#	return $self->wmap;   #### original data from file
		INFO("WMAP NOT found PRODUCT = ". $self->header->PRODUCT);
	}
  	else {
	    INFO("WMAP found PRODUCT = ".$self->header->PRODUCT. " and  CFG_TESTER_TYPE = ". $self->header->CFG_TESTER_TYPE. " and LOCATION = ". $self->header->EQUIP6_ID);
	    $self->wmap($wmap);
  	}
  }
  else{
		INFO( " use WMAP in file");
  }

  return $wmap;
}
#########################################################
#sub updateWMap{
#  my $self = shift;
#
#  my $wmap = $self->wmap;
#
#  if( !( $self->header->CFG_TESTER_TYPE eq "N/A" or $self->header->CFG_TESTER_TYPE eq "NA"))
#  {
#	$wmap = PDF::DpData::WMap->new_from_refdb($self->header->PRODUCT, $self->header->CFG_TESTER_TYPE, $self->header->EQUIP6_ID);
#	INFO( " get WMAP from DB");
#  }
#  else{
#	INFO( " use WMAP in file");
#  }
#
#  if ((($self->dataSource eq 'SEPM') or ($self->dataSource eq 'SZ')) and $wmap->isEmpty){
#    $wmap = $self->wmap;
#	if(defined $wmap){
#
#		$wmap->product($self->header->PRODUCT);
#		$wmap->tester_type($self->header->CFG_TESTER_TYPE);
#		$wmap->location($self->header->EQUIP6_ID);
#		$wmap->register_refdb;
#	####  for auto confirmed
##		07-Jul-15 SAB Don't auto-confirm new configs.
#		$wmap->confirmed_flag;
#
#	}
#  }
#  elsif($wmap->isEmpty){
##	return $self->wmap;   #### original data form fi	le
#	INFO("WMAP NOT found PRODUCT = ". $self->header->PRODUCT);
#  }
#  else {
#    INFO("WMAP found PRODUCT = ".$self->header->PRODUCT. " and  CFG_TESTER_TYPE = ". $self->header->CFG_TESTER_TYPE. " and LOCATION = ". $self->header->EQUIP6_ID);
#    $self->wmap($wmap);
#  }
#  return $wmap;
#}#####################################

sub isLimitNew{
  my $self = shift;
  if(getRefdb->isNewLimit({PROGRAM=>$self->header->PROGRAM, REVISION=>$self->header->REVISION})){
     INFO("Limit: PROGRAM=".$self->header->PROGRAM.",REVISION=".$self->header->REVISION." is New");
     return 1;
  } else {
     INFO("Limit: PROGRAM=".$self->header->PROGRAM.",REVISION=".$self->header->REVISION." is Not New");
     return 0;
  }
}

sub buildLimit{
  my $self = shift;
  if (defined $self->limit){
     return $self->limit;
  } else {
     my $limit = PDF::DpData::Limit->new;
     $limit->copyHeader($self->header);
     if(@{$self->tests}){
       $limit->tests($self->tests);
     } elsif  (@{$self->wafers} and @{$self->wafers->[0]->tests}){
       $limit->tests($self->wafers->[0]->tests);
     }
     $self->limit($limit);
     return $limit;
  }
}
__PACKAGE__->mk_accessors(@$attr, array );

package PDF::DpData::Model::Wafer;
use strict;
use PDF::DpLoad;
use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";
use PDF::Log;

my $attr = [qw/key number START_TIME END_TIME name /];

sub array{
  return qw/ tests bins dies hbins sbins rels custindexes/;
}

__PACKAGE__->mk_accessors(@$attr, array );

sub stats{
   my $self = shift;
   my ($minX, $minY, $maxX, $maxY) = (99999,99999,-99999,-99999);
   my $deviceCount =0;
   foreach my $die (@{$self->dies}){
      next if ($die->inked);
      $deviceCount++;
      $minX = ($minX > $die->x) ? $die->x : $minX;
      $minY = ($minY > $die->y) ? $die->y : $minY;
      $maxX = ($maxX < $die->x) ? $die->x : $maxX;
      $maxY = ($maxY < $die->y) ? $die->y : $maxY;
   }
   my $columns = $maxX - $minX + 1;
   my $rows = $maxY - $minY + 1;
   return {
     minX => $minX,
     minY => $minY,
     maxX => $maxX,
     maxY => $maxY,
     deviceCount => $deviceCount,
     columns => $columns,
     rows => $rows
    };
}

package PDF::DpData::Model::Test;
use strict;
use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

my $attr =  [qw/ name number units critical group LPL HPL LSL HSL LOL HOL LWL HWL desc min max avg std sum ss/] ;
sub array{
  return qw/ conditions /;
}

__PACKAGE__->mk_accessors(@$attr, array);

package PDF::DpData::Model::Bin;
use strict;
use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr =  [qw/ number name PF count /] ;
sub array{
  return qw/ conditions /;
}

__PACKAGE__->mk_accessors(@$attr, array);

package PDF::DpData::Model::Die;
use strict;
use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

# 2016-Feb-15 gmiole - added # unprobed die
# 2020-Jun-18 jgarcia - added touchdown_num
#<<<<<<< HEAD
# 2021-Jul-15 gmllego - added parttesttime
# $attr =  [qw/ x y site partid touchdown_num soft_bin hard_bin indexes inked notest hash unprobed org_x org_y ecid /] ;
#=======
my $attr =  [qw/ x y site partid touchdown_num soft_bin hard_bin indexes inked notest hash unprobed org_x org_y ecid runtime readtime bindesc testtime /] ;
#>>>>>>> 0af60b8432d9d46821e0f93ee6ebf30eb5bde49d

sub array{
  return qw/ result min max mean sdev sums sqrs cnt level cpk pass_fail /;
}

__PACKAGE__->mk_accessors(@$attr, array);

# eric added
package PDF::DpData::Model::Rel;
use strict;
use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr =  [qw/ qpnumber devchar lotchar strname strduration atetemp datalogtype /] ;
sub array{
  return qw/ reliability /;
}

__PACKAGE__->mk_accessors(@$attr, array);

# eric added
package PDF::DpData::Model::CustIndexes;
use strict;
use base qw/PDF::DpData::Base Class::Accessor/;

our $VERSION = "1.0";

my $attr =  [qw/ index1 index2 index3 index4 index5 /] ;
sub array{
	return qw/ custindexes /;
}

__PACKAGE__->mk_accessors(@$attr, array);

1;

=pod

=head1 NAME

PDF::DpData::Model - die model for binMap, WSort, FinalTest, PCM die

=head1 DESCRIPTION

this class provide generalized die model to represen the die for binMap, Wafer Sort, Final Test and PCM die.
Once the die is mapped to this die model, it is easy to create IFF file

  Model
    |-- header (PDF::DpData::HeaderLong)
    |-- wmap   (PDF::DpData::WMap)
    |-- tests (ArrayRef of PDF::DpData::Model::Test) (same structure as wafers->tests)
    |-- wafers (ArrayRef of PDF::DpData::Model::Wafer)
        |-- number
        |-- START_TIME
        |-- END_TIME
        |-- tests (ArrayRef of PDF::DpData::Model::Test)
            |-- number
            |-- name
            |-- units
            |-- group
            |-- LPL
            |-- HPL
            |-- LSL
            |-- HSL
            |-- LOL
            |-- HOL
            |-- LWL
            |-- HWL
            |-- conditions (ArrayRef)
        |--bins  (ArrayRef of PDF::DpData::Model::Bin)
            |-- number
            |-- name
            |-- PF
            |-- count
            |-- conditions (ArrayRef)
        |--dies  (ArrayRef of PDF::DpData::Model::Die)
            |-- x
            |-- y
            |-- site
            |-- partid
            |-- soft_bin
            |-- hard_bin
            |-- indexes (ArrayRef)
            |-- result ( ArrayRef of each test result)
            |-- hash
	    |-- unprobed

=head1 SYNOPSYS

  use PDF::DpData;  # all the new methods are exported by PDF::DpData
  my $model = new_model;
  my $wafer = new_wafer;
  my $header = new_header;
  $model->header($header);

create die model and populate values from data source.

  my $model = new_model;
  foreach  {...... loop by wafer in source file.
    my $wafer = new_wafer;
    $wafer->number(...);
    $wafer->START_TIME(...);
    $wafer->END_TIME(...);
    $model->add('wafers',$wafer);  # add methods for array ref attributes

    foreach  {.... loop by Bin Infomartion
       my $bin = new_bin;
       $bin->number(...);
       $bin->name(...);
       ....
       $wafer->add('bins',$bin);
    }
    foreach  {.... loop by Test Infomartion
       my $test = new_test;
       $test->number(...);
       $test->name(...);
       ....
       $wafer->add('tests',$test);
    }
    foreach  {.... loop by die test result Infomartion
       my $die = new_die;
       $die->x(...);
       $die->y(...);
       $die->add('result',.....);
       ....
       $wafer->add('dies',$die);
    }
  }

=head1 Inheritance

All the classes under PDF::DpData inherit from L<PDF::DpData::Base.pm> which provide convinence methods.

Especially L<add|PDF::DpData::Base.pm/add> method is handy to build up this data from data source. The attributes with : ArrayRef can use this add method.

=head1 new Method

Handy new method for each class are exposed by L<PDF::DpData.pm>. Therefore you don't need to B<use> or B<require> this class.

=head1 PDF::DpData::Model

Top object of the data model. A model represent one lot or one wafer.

=head2 ATTRIBUTES

  header     -- PDF::DpData::HeaderLong or PDF::DpData::HeaderShort object.
  wmap       -- PDF::DpData::WMap object.
  misc       -- miscellaneous object depending on dataource.
                Any data which can not map to this standard data model can set to misc field.
  dataSource -- tester type
  programOrg -- original program name before updateProgram

=head2 ATTRIBUTES -- Array Ref

  wafers   -- Array Ref of PDF::DpData::Model::Wafer
  tests    -- Array Ref of /PDF::DpData::Model::Test

=head2 METHODS

=over 4

=item updateProgram

update $self->header->PROGRAM, as <PROGRAM>::<PRODUCT>::<DataSource>

where <DataSource> = $model->dataSource

original program name will be kept in $model->programOrg

=item updateWMap

lookup PP_WMAP key by PRODUCT and TesterType and location/facility (= DataSource)

Current logic is specifict to use SEPM as TesterType for all datasource type because only SEPM has reliable wafer map configuration in the datasource file.

If the data exist, get the valeus in $self->wmap object.

If not, insert into PP_WMAP.

=item buildLimit

build $self->limit obejct which isa PDF::DpData::Limit.

get array ref of PDF::DpData::Test from $model->tests or $model->wafers->[0]->tests

=back

=head1 PDF::DpData::Model::Wafer

A model will have 0..N wafars. Even if the data source has no wafer number (ex: final test), at lease one wafer required to set die data.

=head2 ATTRIBUTES

  number      -- Wafer number.
  START_TIME  -- Wafer test start time in YYYY/MM/DD HH24:MI:SS
  END_TIME    -- Wafer test end time in YYYY/MM/DD HH24:MI:SS

This value will be key when create IFF file in case N wafers in one model.

If START_TIME is indentical accros wafers in the model, single IFF will be created and contain all wafer data. N wafers -> 1 Iff file.

If START_TIME are all different, each wafer will be print as separate file. N wafers -> N Iff files.

START_TIME and END_TIME can accept several date text format and will be automatically converted to YYYY/MM/DD HH24:MI::SS format by L<PDF::DpLoad.pm/formatDate>.

=head2 ATTRIBUTES -- Array Ref

  tests    -- Array Ref of PDF::DpData::Model::Test.
  bins     -- Array Ref of PDF::DpData::Model::Bins.
  dies     -- Array Ref of PDF::DpData::Model::Dies.

=head2 METHODS

=over 4

=item stats

return statistics of die information as hash reference.

  my $stats = $wafer->stats;

  $stats->{minX};         # minimum die number in X
  $stats->{minY};         # minimum die number in Y
  $stats->{maxX};         # maximum die number in X
  $stats->{maxY};         # maximum die number in Y
  $stats->{deviceCount};  # total device count in the wafer
  $stats->{columns};      # number of columns (= maxX - minX +1)
  $stats->{rows};         # number of rows (= maxY - minY +1)

The stats doesn't include inked die ($die->inked == 1)

=head1 PDF::DpData::Model::Test

Test definition.

=head2 ATTRIBUTES

  number   -- Test number
  name     -- Test name
  units    -- Test units
  group    -- Test group

=head2 ATTRIBUTES -- Array Ref

  conditions  -- Test conditions to be print to limit file.
                 Array Ref of scallar value.

=head1 PDF::DpData::Model::Bin

Binning information

=head2 ATTRIBUTES

  number    -- Bin number
  name      -- Bin name
  PF        -- Pass/Fail. 'P' or 'F'
  count     -- Bin count
  unprobed  -- unprobed die '#'

=head1 PDF::DpData::Model::Die

Die test results

=head2 ATTRIBUTES

  x         -- x coordinate
  y         -- y coordinate
  site      -- site id
  partid    -- part id
  soft_bin  -- Soft Bin
  hard bin  -- Hard Bin
  inked     -- inked die
  notest    -- not tested
  hash      -- object to keep test result as temporary if needed.

=head2 ATTRIBUTES -- Array Ref

  result    -- Array Ref of parameteric test result (scalar).

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

2015/04/06 kazukik : 1st verion
2015/04/20 kazukik : add methods in Model class
2015/06/04 jgarcia : Added forSBflag attribute.
2015/07/13 jgarcia : change the order of the condition in updateWmap subroutine. Not check wmap if it is empty when wmap object has not been initialized.
2015/07/16 jgarcia : updated to support inserting configs from other map formats like AWW, ASC and NAM maps into pp_wmap.

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut
