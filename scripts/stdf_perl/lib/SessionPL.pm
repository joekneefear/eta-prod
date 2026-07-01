#
# FSC Perl STDF Libraries
#
# Confidential Property of Fairchild Semiconductor Corperation
# (c) Copyright Fairchild Semiconductor Corperation, 2000
# All rights reserved
#
# MODIFICATION HISTORY:
#
# DATE       WHO             DESCRIPTION
# __________ ______________  __________________________________________________
# 03-07-2001 Steve Frampton  Original.  Contact Information:
#                            (207) 273-3364
#                            sframpto@fairchildsemi.com,
#                            sframpto@midcoast.com
#

#
# Session object holds stdf structure
# for an entire session.
#
# stdf records supported:
# emir, ewcr, epdr, eftr, wir, wrr, wtsr, whbr, wsbr, wmr, pir, eprr, ptr, eftr, tsr, hbr, sbr, mrr     
#
# Other records could be easily added with a copy, paste, and changes.
#
# methods:
#
# use get_ref and get_exists_ref for records that don't occur in sequence:
#   emir, ewcr, wir, wrr, eprr, mrr, ltr
#
# get_ref - returns ref if it exists, creates and returns new ref initialized based on stdf init hash if it does not exist
# get_exists_ref - returns ref if it exists, returns undef if it does not
#
# records that can occur in sequence have their own methods and are called by id
#   epdr, eftr, wtsr, whbr, wsbr, mmr, ptr, eftr, tsr, hbr, sbr
#
# methods are only valid when called within a heirchy
#
# $id = 1 ;
# $session = Session->new() ;         # session constructor
# $session->get_ref('emir') ;         # used for emir, ltr, ewcr, and mrr records
# $session->get_exists_ref('emir') ;  # used for emir, ltr, ewcr, and mrr records
# $session->tsr($id) ;                # creates first record in a sequence
# $session->tsr()                     # returns all tsr ids
# $session->hbr()                     # similar to tsr with or without arg
# $session->sbr()                     # similar to tsr with or without arg
# $session->epdr()                     # similar to tsr with or without arg
# $session->wafer($id)->get_ref('wir')  # used for wir, wrr records
# $session->wafer($id)->get_exists_ref('wir')  # used for wir, wrr records
# $session->wafer($id)->wtsr($id)     # similar to tsr with or without arg
# $session->wafer($id)->wsbr($id)     # similar to tsr with or without arg
# $session->wafer($id)->whbr($id)     # similar to tsr with or without arg
# $session->wafer($id)->wmr($id)      # similar to tsr with or without arg
# $session->wafer($id)->part($id)->get_ref('pir') # use for pir,prr
# $session->wafer($id)->part($id)->ptr() # similar to tsr with or without args
# $session->wafer($id)->part($id)->eftr() # similar to tsr with or without args
#
# if the caller knows that the wafer or part is not going to change for
# access itterations, the something like this is ok:
#
# my $wafer = $session->wafer($id)
# foreach $pid ($wafer->part())
#   {
#   ($wir,$wrr) = $wafer->part($pid)->get_ref('wir','wrr') ;
#   }
#
# $session->update_cnt() # update record counts in emir, mrr, eprr, and wrr records.
#
# $session->write_stdf_file(\*OUTPUT)  # call update_cnt, and output file
#
# Also see examples in example_SessionPL.pl
#
# $session->update_cnt() and $session->write_stdf_file() demonstrate how
# to walk through an stdf_file.
#
# WARNING WARNING references must be destroyed at the same time or before
# the session object:
#
# ok:
# {
# my $session = Session->new() ;
# my $emir = $session->get_ref('emir') ;
# } # $session gets destroyed at end of block
#
# memory leak not ok:
#
# my $emir ;
# {
# my $session = Session->new() ;
# $emir = $session->get_ref('emir') ;
# } # session cannot be destroyed because $emir is referencing it
# 

{ # packages are nested with Session
package Session ;
  use Carp;
  
  sub new
  {
	  my $self = {} ;
	  $self->{wafer} = {} ;
	  $self->{epdr} = {} ;
	  $self->{tsr} = {} ;
	  $self->{hbr} = {} ;
	  $self->{sbr} = {} ;
	  return bless $self;
  }

  sub get_ref
  {
	  my $self = shift ;
	  my @refs ;
	  foreach my $rec (@_)
		{
		if (! defined($self->{$rec}))
		  {
		  my %hash = %{$Session::init{$rec}} ; 
		  $self->{$rec} = \%hash ;
		  }    
		push @refs, $self->{$rec} ;
		}
	  # return all requested references
	  return @refs ;
  }


  sub get_exists_ref
  {
	  my $self = shift ;
	  my $rec = shift ;
		{
		if (defined($self->{$rec}))
		  {
		  return($self->{$rec}) ;
		  }
		else
		  {
		  return(undef) ;
		  }
		}
  }


sub update_cnt
  {
  my $self = shift ;
  (my $emir) = $self->get_exists_ref('emir') ;
  defined($emir) || confess "emir not defined, cannot update" ;
  (my $mrr) = $self->get_exists_ref('mrr') ;
  defined($mrr) || confess "mrr not defined, cannot update" ;
  $$emir{ssum_cnt} = 0 ;  # mrr
  $$emir{ssum_cnt} = 1 unless (! $mrr) ; # mrr
  $$emir{wsum_cnt} = 0 ;  # wrr
  $$emir{psum_cnt} = 0 ;  # eprr
  $$emir{pres_cnt} = 0 ;  # ptr
  $$emir{fres_cnt} = 0 ;  # fres eftr
  $$emir{wsyn_cnt} = 0 ;  # wtsr
  $$emir{whwb_cnt} = 0 ;  # whbr
  $$emir{wswb_cnt} = 0 ;  # wsbr
  $$emir{ssyn_cnt} = 0 ;  # tsr
  $$emir{sswb_cnt} = 0 ;  # sbr
  $$emir{shwb_cnt} = 0 ;  # hbr
  $$mrr{part_cnt} = 0  if(!defined $$mrr{part_cnt} || $$mrr{part_cnt} <= 0); # eprr ?

  my $orig_mrr_part_cnt = $$mrr{part_cnt};
  #
  # more mrr counts could be done, by examining various flags
  #
  my $wir ;
  my $wrr ;
  foreach my $wafer_id ($self->wafer())
  {
   my $wafer = $self->wafer($wafer_id) ;
   #($wir) = $self->wafer($wafer_id)->get_exists_ref('wir') ;
   ($wir) = $wafer->get_exists_ref('wir') ;
   #($wrr) = $self->wafer($wafer_id)->get_exists_ref('wrr') ;
   ($wrr) = $wafer->get_exists_ref('wrr') ;
   $$emir{wsum_cnt}++ unless (! $wrr ) ;

   if(!defined $$wrr{part_cnt} || $$wrr{part_cnt} <= 0)
   {
     $$wrr{part_cnt} = 0 ;

     foreach my $part_id ($self->wafer($wafer_id)->part())
     {
       my $part = $wafer->part($part_id) ;
       (my $eprr) = $part->get_exists_ref('eprr') ;
       $$eprr{num_test} = 0 ;
       if ($eprr)
       {
        $$emir{psum_cnt}++ ;
        $$mrr{part_cnt}++ unless $orig_mrr_part_cnt > 0;
        $$wrr{part_cnt}++;
       }

      foreach my $test_num ($part->ptr())
       { $$emir{pres_cnt}++ ; $$eprr{num_test}++ ; }
      foreach my $test_num ($part->eftr())
       { $$emir{fres_cnt}++ ; $$eprr{num_test}++ ; }
     }
   }
     foreach my $test_num ($wafer->wtsr())
     { $$emir{wsyn_cnt}++ ; }
     foreach my $test_num ($wafer->whbr())
     { $$emir{whwb_cnt}++ ; }
     foreach my $test_num ($wafer->wsbr())
     { $$emir{wswb_cnt}++ ; }
  }

  foreach my $test_num ($self->tsr())
     { $$emir{ssyn_cnt}++ ; }
  foreach my $test_num ($self->sbr())
     { $$emir{sswb_cnt}++ ; }
  foreach my $test_num ($self->hbr())
     { $$emir{shwb_cnt}++ ; }
  return(0) ;
  }

# 

sub write_stdf_file
  {
  my $self = shift ;
  local $file = shift ;
  if (! defined( $file ) )
    {
    $file = \*STDOUT ;
    }
  $self->update_cnt() ;  # update emir, wrr, mrr counts
  my $ptr_bin ;
  my $ptr ;
  (my $emir) = $self->get_exists_ref('emir') ;
  (my $mrr) = $self->get_exists_ref('mrr') ;
  defined($emir) && print $file &pack_EMIR($emir) ;
  (my $ltr) = $self->get_exists_ref('ltr') ;		#added
  defined($ltr) && print $file &pack_LTR($ltr) ;	#added
  (my $ewcr) = $self->get_exists_ref('ewcr') ;
  defined($ewcr) && print $file &pack_EWCR($ewcr) ;
  foreach my $test_num ($self->epdr())
   { print $file &pack_EPDR($self->epdr($test_num)) ; }
  my $wir ;
  my $wrr ;
  foreach my $wafer_id ($self->wafer())
   {
   my $wafer=$self->wafer($wafer_id) ;
#   ($wir) = $self->wafer($wafer_id)->get_exists_ref('wir') ;
   ($wir) = $wafer->get_exists_ref('wir') ;
#   ($wrr) = $self->wafer($wafer_id)->get_exists_ref('wrr') ;
   ($wrr) = $wafer->get_exists_ref('wrr') ;
   defined($wir) && print $file &pack_WIR($wir) ;
#   foreach my $part_id ($self->wafer($wafer_id)->part())
   foreach my $part_id ($wafer->part())
     {
     my $part ;
     $part = $wafer->part($part_id) ;
#     (my $pir) = $self->wafer($wafer_id)->part($part_id)->get_exists_ref('pir') ;
     (my $pir) = $part->get_exists_ref('pir') ;
#     (my $eprr) = $self->wafer($wafer_id)->part($part_id)->get_exists_ref('eprr') ;
     (my $eprr) = $part->get_exists_ref('eprr') ;
     defined($pir) && print $file &pack_PIR($pir) ;
#     foreach my $test_num ($self->wafer($wafer_id)->part($part_id)->ptr())
     foreach my $test_num ($part->ptr())
       {
#       $ptr = $self->wafer($wafer_id)->part($part_id)->ptr($test_num) ; 
       $ptr = $part->ptr($test_num) ; 
#       my $ptr_bin = &pack_PTR($ptr) ;
#       my %ptr2 ;
#       &unpack_PTR(\$ptr_bin, \%ptr2) ;
#       print $file $ptr_bin ;
       print $file &pack_PTR($part->ptr($test_num)) ;
       }
#     foreach my $test_num ($self->wafer($wafer_id)->part($part_id)->eftr())
     foreach my $test_num ($part->eftr())
#       { print $file &pack_EFTR($self->wafer($wafer_id)->part($part_id)->eftr($test_num)) ; }
       { print $file &pack_EFTR($part->eftr($test_num)) ; }
     defined($eprr) && print $file &pack_EPRR($eprr) ;
     }
#   foreach my $test_num ($self->wafer($wafer_id)->wmr())
#     { print $file &pack_WMR($self->wafer($wafer_id)->wmr($test_num)) ; }
   foreach my $test_num ($wafer->wmr())
     { print $file &pack_WMR($wafer->wmr($test_num)) ; }
#   foreach my $test_num ($self->wafer($wafer_id)->wtsr())
#     { print $file &pack_WTSR($self->wafer($wafer_id)->wtsr($test_num)) ; }
   foreach my $test_num ($wafer->wtsr())
     { print $file &pack_WTSR($wafer->wtsr($test_num)) ; }
#   foreach my $test_num ($self->wafer($wafer_id)->whbr())
#     { print $file &pack_WHBR($self->wafer($wafer_id)->whbr($test_num)) ; }
   foreach my $test_num ($wafer->whbr())
     { print $file &pack_WHBR($wafer->whbr($test_num)) ; }
#   foreach my $test_num ($self->wafer($wafer_id)->wsbr())
#     { print $file &pack_WSBR($self->wafer($wafer_id)->wsbr($test_num)) ; }
   foreach my $test_num ($wafer->wsbr())
     { print $file &pack_WSBR($wafer->wsbr($test_num)) ; }
   defined($wrr) && print $file &pack_WRR($wrr) ;
   }
  foreach my $test_num ($self->tsr())
   { print $file &pack_TSR($self->tsr($test_num)) ; }
  foreach my $test_num ($self->sbr())
   { print $file &pack_SBR($self->sbr($test_num)) ; }
  foreach my $test_num ($self->hbr())
   { print $file &pack_HBR($self->hbr($test_num)) ; }
  print $file &pack_MRR($mrr) ;
  return(0) ;
  }

sub ltr
{
	my $self = shift;
	my $id   = shift;

	if(defined($id))
	{
		$id = $id.'_~id' ;  # keep Summary hash elements separate
		
		if (! defined($self->{ltr}{$id}))
      		{
      			my %ltr = %{$Session::init{ltr}} ;
      			$self->{'ltr'}{$id} = \%ltr ;
      		}

    		return $self->{'ltr'}{$id} ;
    	}
  	else
    	{
    		return(&Session::fix_keys(keys(%{$self->{'ltr'}}))) ;
    	}
}

sub epdr
  {
  my $self = shift ;
  my $id = shift ;
  if (defined($id))
    {
    $id = $id.'_~id' ;  # keep Summary hash elements separate
    if (! defined($self->{epdr}{$id}))
      {
      my %epdr = %{$Session::init{epdr}} ;
      $self->{'epdr'}{$id} = \%epdr ;
      }
    return $self->{'epdr'}{$id} ;
    }
  else
    {
    return(&Session::fix_keys(keys(%{$self->{'epdr'}}))) ;
    }
  }

sub tsr
  {
  my $self = shift ;
  my $id = shift ;
  if (defined($id))
    {
    $id = $id.'_~id' ;  # keep Summary hash elements separate
    if (! defined($self->{tsr}{$id}))
      {
      my %tsr = %{$Session::init{tsr}} ;
      $self->{'tsr'}{$id} = \%tsr ;
      }
    return $self->{'tsr'}{$id} ;
    }
  else
    {
    return(&Session::fix_keys(keys(%{$self->{'tsr'}}))) ;
    }
  }

sub hbr
  {
  my $self = shift ;
  my $id = shift ;
  if (defined($id))
    {
    $id = $id.'_~id' ;  # keep Summary hash elements separate
    if (! defined($self->{hbr}{$id}))
      {
      my %hbr = %{$Session::init{hbr}} ;
      $self->{'hbr'}{$id} = \%hbr ;
      }
    return $self->{'hbr'}{$id} ;
    }
  else
    {
    return(&Session::fix_keys(keys(%{$self->{'hbr'}}))) ;
    }
  }


sub sbr
  {
  my $self = shift ;
  my $id = shift ;
  if (defined($id))
    {
    $id = $id.'_~id' ;  # keep Summary hash elements separate
    if (! defined($self->{sbr}{$id}))	#should this be sbr????
      {
      my %sbr = %{$Session::init{sbr}} ;
      $self->{'sbr'}{$id} = \%sbr ;
      }
    return $self->{'sbr'}{$id} ;
    }
  else
    {
    return(&Session::fix_keys(keys(%{$self->{'sbr'}}))) ;
    }
  }


sub wafer
  {
  my $self = shift ;
  my $id = shift ;
  if (defined($id))
    {
    $id = $id.'_~id' ;  # keep Summary hash elements separate
    if (! defined($self->{wafer}{$id}))
      {
      $self->{'wafer'}{$id} = Wafer->new() ;
      }
    return $self->{'wafer'}{$id} ;
    }
  else
    {
    return(&Session::fix_keys(keys(%{$self->{'wafer'}}))) ;
    }
  }

{
package Wafer ;
use Carp ;

sub new
  {
  my $self = {} ;
  $self->{part} = {} ;
  $self->{wtsr} = {} ;
  $self->{whbr} = {} ;
  $self->{wsbr} = {} ;
  $self->{wmr} = {} ;
  return bless $self ;
  }

sub get_ref
  {
  my $self = shift ;
  my @refs ;
  foreach my $rec (@_)
    {
    if (! defined($self->{$rec}))
      {
      my %hash = %{$Session::init{$rec}} ; 
      $self->{$rec} = \%hash ;
      }    
    push @refs, $self->{$rec} ;
    }
  # return all requested references
  return @refs ;
  }
  
  sub get_exists_ref
  {
  my $self = shift ;
  my $rec = shift ;
    {
    if (defined($self->{$rec}))
      {
      return($self->{$rec}) ;
      }
    else
      {
      return(undef) ;
      }
    }
  }

sub wtsr
  {
  my $self = shift ;
  my $id = shift ;
  if (defined($id))
    {
    $id = $id.'_~id' ;  # keep Summary hash elements separate
    if (! defined($self->{wtsr}{$id}))
      {
      my %wtsr = %{$Session::init{wtsr}} ;
      $self->{'wtsr'}{$id} = \%wtsr ;
      }
    return $self->{'wtsr'}{$id} ;
    }
  else
    {
    return(&Session::fix_keys(keys(%{$self->{'wtsr'}}))) ;
    }
  }

sub whbr
  {
  my $self = shift ;
  my $id = shift ;
  if (defined($id))
    {
    $id = $id.'_~id' ;  # keep Summary hash elements separate
    if (! defined($self->{whbr}{$id}))
      {
      my %whbr = %{$Session::init{whbr}} ;
      $self->{'whbr'}{$id} = \%whbr ;
      }
    return $self->{'whbr'}{$id} ;
    }
  else
    {
    return(&Session::fix_keys(keys(%{$self->{'whbr'}}))) ;
    }
  }

sub wsbr
  {
  my $self = shift ;
  my $id = shift ;
  if (defined($id))
    {
    $id = $id.'_~id' ;  # keep Summary hash elements separate
    if (! defined($self->{wsbr}{$id}))
      {
      my %wsbr = %{$Session::init{wsbr}} ;
      $self->{'wsbr'}{$id} = \%wsbr ;
      }
    return $self->{'wsbr'}{$id} ;
    }
  else
    {
    return(&Session::fix_keys(keys(%{$self->{'wsbr'}}))) ;
    }
  }

sub wmr
  {
  my $self = shift ;
  my $id = shift ;
  if (defined($id))
    {
    $id = $id.'_~id' ;  # keep Summary hash elements separate
    if (! defined($self->{wmr}{$id}))
      {
      my %wmr = %{$Session::init{wmr}} ;
      $self->{'wmr'}{$id} = \%wmr ;
      }
    return $self->{'wmr'}{$id} ;
    }
  else
    {
    return(&Session::fix_keys(keys(%{$self->{'wmr'}}))) ;
    }
  }



sub part 
  {
  my $self = shift ;
  my $id = shift ;
  if (defined($id))
    {
    $id = $id.'_~id' ;  # keep Summary hash elements separate
    if (! defined($self->{part}{$id}))
      {
      $self->{'part'}{$id} = Part->new() ;
      }
    return $self->{'part'}{$id} ;
    }
  else
    {
    return(&Session::fix_keys(keys(%{$self->{'part'}}))) ;
    }
  }
}

{
package Part ;
use Carp ;

sub new
  {
  my $self = {} ;
  $self->{ptr} = {} ;
  $self->{eftr} = {} ;
  return bless $self ;
  }

sub get_ref
  {
  my $self = shift ;
  my @refs ;
  foreach my $rec (@_)
    {
    if (! defined($self->{$rec}))
      {
      my %hash = %{$Session::init{$rec}} ; 
      $self->{$rec} = \%hash ;
      }    
    push @refs, $self->{$rec} ;
    }
  # return all requested references
  return @refs ;
  }
  
  sub get_exists_ref
  {
  my $self = shift ;
  my $rec = shift ;
    {
    if (defined($self->{$rec}))
      {
      return($self->{$rec}) ;
      }
    else
      {
      return(undef) ;
      }
    }
  }

sub ptr 
  {
  my $self = shift ;
  my $id = shift ;
  if (defined($id))
    {
    $id = $id.'_~id' ;  # keep Summary hash elements separate
    if (! defined($self->{ptr}{$id}))
      {
      my %ptr = %{$Session::init{ptr}} ;
      $self->{'ptr'}{$id} = \%ptr ;
      }
    return $self->{'ptr'}{$id} ;
    }
  else
    {
    return(&Session::fix_keys(keys(%{$self->{'ptr'}}))) ;
    }
  }

sub eftr 
  {
  my $self = shift ;
  my $id = shift ;
  if (defined($id))
    {
    $id = $id.'_~id' ;  # keep Summary hash elements separate
    if (! defined($self->{eftr}{$id}))
      {
      my %eftr = %{$Session::init{eftr}} ;
      $self->{'eftr'}{$id} = \%eftr ;
      }
    return $self->{'eftr'}{$id} ;
    }
  else
    {
    return(&Session::fix_keys(keys(%{$self->{'eftr'}}))) ;
    }
  }
}

#
# strip information of keys and sort
#
sub fix_keys
{
my $is_alpha = 0 ;
my @keys ;
foreach $_ (grep /[_][~]id$/, @_)
  {
  s/_~id$//;
  if ( ! /^\d+$/ )
    { $is_alpha = 1 }
  push @keys, $_ ;
  }
if ($is_alpha)
  { return(sort @keys) ; }
else
  { return(sort {$a <=> $b; } @keys) ; } # don't retrieve Summary elements
}

}

1
