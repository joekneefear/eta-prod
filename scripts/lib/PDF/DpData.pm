package PDF::DpData;
# SVN $Id: DpData.pm 1784 2016-07-28 06:15:57Z dpower $
# 25-Apr-2016 Eric	: added sub new_rel
# 28-Jul-2016 jgarcia : added new_defect subroutine for instantiating PDF::DpData::Defect
# 12-may-2021 Eric	: added new_onheaderLong
use strict;

use Exporter;
use PDF::DpData::MetaData;
use PDF::DpData::HeaderLong;
use PDF::DpData::HeaderShort;
use PDF::DpData::Limit;
use PDF::DpData::WMap;
use PDF::DpData::Model;
use PDF::DpData::ONHeaderLong;
use PDF::DpData::eCofAHeaderLong;
our @ISA=qw/Exporter/;
our @EXPORT=qw/new_metadata new_headerLong new_headerShort new_limit new_wmap new_wmap_from_refdb
		new_model new_wafer new_test new_bin new_die new_rel new_defect new_onheaderLong new_ecofaheaderLong new_custindexes
                 /;

sub new_metadata{ return PDF::DpData::MetaData->new(@_);};
sub new_headerLong{ return PDF::DpData::HeaderLong->new(@_);};
sub new_headerShort{ return PDF::DpData::HeaderShort->new(@_);};
sub new_limit{ return PDF::DpData::Limit->new(@_);};
sub new_wmap_from_refdb{ return PDF::DpData::WMap->new_from_refdb(@_);};
sub new_wmap{ return PDF::DpData::WMap->new(@_);};
sub new_model{ return PDF::DpData::Model->new(@_);};
sub new_wafer{ return PDF::DpData::Model::Wafer->new(@_);};
sub new_test{ return PDF::DpData::Model::Test->new(@_);};
sub new_bin{ return PDF::DpData::Model::Bin->new(@_);};
sub new_die{ return PDF::DpData::Model::Die->new(@_);};
sub new_rel{ return PDF::DpData::Model::Rel->new(@_);};
sub new_defect{ return PDF::DpData::Defect->new(@_);};
sub new_onheaderLong{ return PDF::DpData::ONHeaderLong->new(@_);};
sub new_ecofaheaderLong{ return PDF::DpData::eCofAHeaderLong->new(@_);};
sub new_custindexes{ return PDF::DpData::Model::CustIndexes->new(@_);};


1;

__END__;

=pod

=head1 NAME

PDF::DpData - Exporter module for useful classes to create dataPower standard IFF file 
This module provide alias methods to create new obejct.

=head1 METHODS

B<new_headerLong> -- L<PDF::DpData::HeaderLong|PDF::DpData::HeaderLong.pm>->new;

B<new_headerShort> -- L<PDF::DpData::HeaderShort|PDF::DpData::HeaderShort.pm>->new;

B<new_limit> -- L<PDF::DpData::Limit|PDF::DpData::Limit.pm>->new;

B<new_wmap> -- L<PDF::DpData::WMap|PDF::DpData::WMap.pm>->new;

B<new_wmap_from_refdb> -- L<PDF::DpData::WMap|PDF::DpData::WMap.pm>->new_from_ref_db;

B<new_model> -- L<PDF::DpData::Model|PDF::DpData::Model.pm>->new;

B<new_wafer> -- L<PDF::DpData::Model::Wafer|PDF::DpData::Model.pm>->new;

B<new_test> -- L<PDF::DpData::Model::Test|PDF::DpData::Model.pm>->new;

B<new_bin> -- L<PDF::DpData::Model::Bin|PDF::DpData::Model.pm>->new;

B<new_die> -- L<PDF::DpData::Model::Data|PDF::DpData::Model.pm>->new;

B<new_rel> -- L<PDF::DpData::Model::Rel|PDF::DpData::Model.pm>->new;

=head1 LINK
 
L<PDF::DpData::HeaderLong.pm>    

L<PDF::DpData::HeaderShort.pm>    

L<PDF::DpData::Limit.pm>    

L<PDF::DpData::WMap.pm>    

=head1 SYNOPSYS

  use PDF::DpData;
  # do not need to use PDF::DpData::HeaderLong.

  my $header = PDF::DpData::HeaderLong->new;

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

2015/03/31 kazukik: 1st verion

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut

