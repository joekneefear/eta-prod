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
#                            sframpto@adelphia.net
# ?????????? Andrew Pruesser Renamed to SessionNew.pm
#                            Change to arrays instead of hashes ??
# 03/27/2006 Steve Frampton  Fixed bugs/added support for functional records.
#                            write_stdf_file sorts by default.
#                            Call with sort=>0 for non-sort
#                            Call with sort=>1 for sort behavior
#                            Call with sort=>2 for string sort behavior
#                             for parts (other records numberic sort)
#                            write_stdf_file skips update_cnt if called with
#                            no_cnt=>1 parameter.
#                            Added destroy_epdr, destroy_efdr, destroy_ptr, destroy_eftr,destroy_part
#                            eprr{num_counts} updated to include eftr as walls as ptr tests
# 05/12/2006 Steve Frampton  Fixed bugs in destroy_efdr and destroy_epdr.
# 05/16/2006 Steve Frampton  Tuning changes to $keys to allocate.
#                            Added destroy methods for final test.
# 06-Dec-12  Scott Boothby   Return 1 if write_stdf_file fails.
# 
#
# Session object holds stdf structure
# for an entire session.
#
# stdf records supported:
# emir, ewcr, epdr, eftr, wir, wrr, wtsr, bgd, whbr, wsbr, wmr, pir, eprr, ptr, eftr, tsr, hbr, sbr, mrr     
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
#   epdr, eftr, wtsr, whbr, wsbr, mmr, ptr, eftr, tsr, hbr, sbr, bgd
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
# $session->hbr()		      # similar to tsr with or without arg
# $session->epdr()                    # similar to tsr with or without arg
# $session->efdr()                    # similar to epdr records
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
# $session->write_stdf_file(\*OUTPUT)  # update counts and output file
# $session->write_stdf_file(\*OUTPUT,no_cnt=>1) # output file without updating counts.
# $session->write_stdf_file(\*OUTPUT,sort=>1)  # call update_cnt, and output file in sorted order - recommended for debug only.
# $session->write_stdf_file(\*OUTPUT,sort=>2)  # string sort for parts, other records sort as numeric.
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
	  my $self = {};
	  #keys(%$self) = 8;

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

	if (defined($self->{$rec}))
  	{
	  return($self->{$rec}) ;
	}
	else
	{
	  return(undef) ;
	}
  }


sub update_cnt
{
  my $self = shift ;

  (my $emir) = $self->get_exists_ref('emir') ;
  if ( !defined($emir))
  {
     carp "emir not defined, cannot update" ;
     return(1);
  }

  (my $mrr) = $self->get_exists_ref('mrr') ;
  if ( !defined($mrr))
  {
     carp "mrr not defined, cannot update" ;
     return(1);
  }

  $$emir{ssum_cnt} = 1 unless (! $mrr) ; # mrr

  $$emir{sswb_cnt} = 0;	# SBR
  $$emir{shwb_cnt} = 0; # HBR
  $$emir{ssyn_cnt} = 0; # TSR
  $$emir{wsum_cnt} = 0; # WRR
  $$emir{wswb_cnt} = 0; # WSBR
  $$emir{whwb_cnt} = 0; # WHBR
  $$emir{wsyn_cnt} = 0; # WTSR
  $$emir{psum_cnt} = 0; # EPRR
  $$emir{pres_cnt} = 0; # PTR
  $$emir{fres_cnt} = 0; # EFTR

  $$mrr{part_cnt} = 0 if(!defined $$mrr{part_cnt} || $$mrr{part_cnt} <= 0);
  my $orig_mrr_part_cnt = $$mrr{part_cnt};

  # Set all top level records.
  $$emir{sswb_cnt} = scalar($self->sbr()); 
  $$emir{shwb_cnt} = scalar($self->hbr());
  $$emir{ssyn_cnt} = scalar($self->tsr());

  # Set all wafer level records.
  $$emir{wsum_cnt} = scalar($self->wafer());

  # Loop over all part level records.
  foreach my $part_num ($self->part())
  {
                my $part = $self->part($part_num);

                (my $eprr) = $part->get_exists_ref('eprr');
		$$eprr{num_test} = scalar($part->ptr())+scalar($part->eftr());

                $$emir{psum_cnt}++;
                $$mrr{part_cnt}++ unless $orig_mrr_part_cnt > 0;

                $$emir{pres_cnt} += scalar($part->ptr());
                $$emir{fres_cnt} += scalar($part->eftr());
  }

  # Loop over individual Wafers to calc wafer level counts.
   foreach my $wafer_num ($self->wafer())
   {
	my $wafer = $self->wafer($wafer_num);

  	$$emir{wswb_cnt} += scalar($wafer->wsbr());
  	$$emir{whwb_cnt} += scalar($wafer->whbr());
  	$$emir{wsyn_cnt} += scalar($wafer->wtsr());

	(my $wrr) = $wafer->get_exists_ref('wrr');

	$$wrr{part_cnt} = 0 if(!defined $$wrr{part_cnt} || $$wrr{part_cnt} <= 0);

	$$wrr{part_cnt} = scalar($wafer->part()) unless $$wrr{part_cnt} > 0;

  	# Loop over all part level records.
  	foreach my $part_num ($wafer->part())
  	{
		my $part = $wafer->part($part_num);

		(my $eprr) = $part->get_exists_ref('eprr');
		$$eprr{num_test} = scalar($part->ptr())+scalar($part->eftr());

		$$emir{psum_cnt}++; 
		$$mrr{part_cnt}++ unless $orig_mrr_part_cnt > 0;
	
        	$$emir{pres_cnt} += scalar($part->ptr());
        	$$emir{fres_cnt} += scalar($part->eftr());
  	}
   }

  return(0) ;
}

sub write_stdf_file
{
  my $self = shift ;
  local $file = shift ;
  my %named_args = @_ ;
  my $sort = $named_args{sort} || ($sort = 1) ;
  my $no_cnt = $named_args{no_cnt} || ($no_cnt = 0) ;

  if (! defined( $file ) )
    {
    $file = \*STDOUT ;
    }

  if (! $no_cnt)
  { 
    # update emir, wrr, mrr counts
    my $status = $self->update_cnt() ;
    if ( $status != 0 )
    {
       return(1);
    }
  }

  # Print the EMIR Record.
  (my $emir) = $self->get_exists_ref('emir') ;
  defined($emir) && print $file &pack_EMIR($emir) ;

  # If there is a LTR record, print it.
  (my $ltr) = $self->get_exists_ref('ltr') ;            #added
  defined($ltr) && print $file &pack_LTR($ltr) ;        #added

  # If there are any BGD records, print them
  if ($sort)
   { foreach my $test_num (sort {$a <=> $b} $self->bgd())
   { print $file &pack_BGD($self->bgd($test_num)) ; } }
  else
   { foreach my $test_num ($self->bgd())
   { print $file &pack_BGD($self->bgd($test_num)) ; } }



  # If there is a EWCR record, print it.
  (my $ewcr) = $self->get_exists_ref('ewcr') ;
  defined($ewcr) && print $file &pack_EWCR($ewcr) ;

  # If there are any EPDR records, print them
  if ($sort)
   {foreach my $test_num (sort {$a <=> $b} $self->epdr())
   { print $file &pack_EPDR($self->epdr($test_num)) ; }}
  else
   {foreach my $test_num ($self->epdr())
   { print $file &pack_EPDR($self->epdr($test_num)) ; }}
  
  # If there are any EFDR records, print them
  if ($sort)
   {foreach my $test_num (sort {$a <=> $b} $self->efdr())
   { print $file &pack_EFDR($self->efdr($test_num)) ; }}
  else
   {foreach my $test_num ($self->efdr())
   { print $file &pack_EFDR($self->efdr($test_num)) ; }}


  my $wir ;
  my $wrr ;
  my $pir ;
  my $eprr ;

  {
  my @parts ;
   if ($sort==1)
    {
    @parts = sort {$a <=> $b;} $self->part() ;
    }
   elsif ($sort==2)
    {
    @parts = sort $self->part() ;
    }

  foreach my $part_id (@parts)
  {
		# Get a reference to the current PART
     		my $part ;
     		$part = $self->part($part_id) ;

		# Print this PART's PIR record.
     		(my $pir) = $part->get_exists_ref('pir') ;
     		defined($pir) && print $file &pack_PIR($pir) ;

     		# Loop over all PTR's in this PART.
		{
		my @ptrs ;
		if ($sort)
     			{ @ptrs = sort {$a <=> $b} $part->ptr() ; }
  		else
   			{ @ptrs = $part->ptr() ; }
     		foreach my $key ( @ptrs )
     		{
         		my $smallptr = $part->ptr($key) ;
         		my %ptr      = %{$Session::init{ptr}} ;
       
         		foreach $rec (keys %{$smallptr})
         		{
                		$ptr{$rec} = $$smallptr{$rec};
         		}

         		print $file &pack_PTR(\%ptr) ;
     		}
		}

     		# Loop over all EFTR's in the PART.
		{
		my @eftrs ;
		if ($sort)
			{@eftrs = sort {$a <=> $b} $part->eftr() ;}
		else
			{@eftrs = $part->eftr() ;}

     		foreach my $key (@eftrs)
     		{
         		my $smalleftr = $part->eftr($key) ;
         		my %eftr      = %{$Session::init{eftr}} ;
       
		        foreach $rec (keys %{$smalleftr})
		        {
               			$eftr{$rec} = $$smalleftr{$rec};
         		}

         		print $file &pack_EFTR(\%eftr) ;
     		}
		}
	
		# print this PART's EPRR record.
     		(my $eprr) = $part->get_exists_ref('eprr') ;
     		defined($eprr) && print $file &pack_EPRR($eprr) ;
  }
  }
  {
  my @wafers ;
  if ($sort)
    { @wafers = sort {$a <=> $b;} $self->wafer() ; }
  else
    { @wafers = $self->wafer() ; }
  foreach my $wafer_id (@wafers)
  {
   # Get a referance to the current wafer.
   my $wafer=$self->wafer($wafer_id) ;

   # Print the current WIR record.
   ($wir) = $wafer->get_exists_ref('wir') ;
   defined($wir) && print $file &pack_WIR($wir) ;

   # Loop over all parts on the current Wafer
   {
   my @parts ;
   if ($sort==1)
    {
    @parts = sort {$a <=> $b;} $wafer->part() ;
    }
   elsif ($sort==2)
    {
    @parts = sort $wafer->part() ;
    }

   foreach my $part_id (@parts)
   {
     # Get a reference to the current PART
     my $part ;
     $part = $wafer->part($part_id) ;

     # Print this PART's PIR record.
     (my $pir) = $part->get_exists_ref('pir') ;
     defined($pir) && print $file &pack_PIR($pir) ;

     # Loop over all PTR's in this PART.
     {
     my @ptrs ; 
     if ($sort) 
     	{ @ptrs = sort {$a <=> $b} $part->ptr() ; }
     else
     	{ @ptrs = $part->ptr() ; }
     foreach my $key (@ptrs)
     { 
	 my $smallptr = $part->ptr($key) ;
         my %ptr      = %{$Session::init{ptr}} ;
	 
	 foreach $rec (keys %{$smallptr})
	 {
		$ptr{$rec} = $$smallptr{$rec};
	 }

	 print $file &pack_PTR(\%ptr) ; 
     }
     }  

     # Loop over all EFTR's in the PART.
     {
     my @eftrs ;
     if ($sort)
       {@eftrs = sort {$a <=> $b} $part->eftr() ;}
     else
       {@eftrs = $part->eftr() ;}
     foreach my $key (@eftrs)
     { 
	 my $smalleftr = $part->eftr($key) ;
         my %eftr      = %{$Session::init{eftr}} ;
	 
	 foreach $rec (keys %{$smalleftr})
	 {
		$eftr{$rec} = $$smalleftr{$rec};
	 }

	 print $file &pack_EFTR(\%eftr) ; 
     }
     }  
     
     # print this PART's EPRR record.
     (my $eprr) = $part->get_exists_ref('eprr') ;
     defined($eprr) && print $file &pack_EPRR($eprr) ;
   }
   }

   # If there are WMR records, print them
   foreach my $test_num ($wafer->wmr())
     { print $file &pack_WMR($wafer->wmr($test_num)) ; }

   # If there are WTSR records, print them
   if ($sort)
     {foreach my $test_num (sort {$a <=> $b} $wafer->wtsr())
       { print $file &pack_WTSR($wafer->wtsr($test_num)) ; }}
   else
     {foreach my $test_num ($wafer->wtsr())
       { print $file &pack_WTSR($wafer->wtsr($test_num)) ; }}

   # If there are WHBR records, print them
   if ($sort)
     {foreach my $test_num (sort {$a <=> $b} $wafer->whbr())
       { print $file &pack_WHBR($wafer->whbr($test_num)) ; }}
   else
     {foreach my $test_num ($wafer->whbr())
       { print $file &pack_WHBR($wafer->whbr($test_num)) ; }}

   # If there are WSBR records, print them
   if ($sort)
     {foreach my $test_num (sort {$a <=> $b} $wafer->wsbr())
       { print $file &pack_WSBR($wafer->wsbr($test_num)) ; }}
   else
     {foreach my $test_num ($wafer->wsbr())
       { print $file &pack_WSBR($wafer->wsbr($test_num)) ; }}
   
   # Print the WRR for this wafer.
   ($wrr) = $wafer->get_exists_ref('wrr') ;
   defined($wrr) && print $file &pack_WRR($wrr) ;
  }
  }

  # If there are any TSR records, print them
  if ($sort)
    {foreach my $test_num (sort {$a <=> $b} $self->tsr())
      { print $file &pack_TSR($self->tsr($test_num)) ; }}
  else
    {foreach my $test_num ($self->tsr())
      { print $file &pack_TSR($self->tsr($test_num)) ; }}


  # If there are any SBR records, print them
  if ($sort)
    {foreach my $test_num (sort {$a <=> $b} $self->sbr())
       { print $file &pack_SBR($self->sbr($test_num)) ; }}
  else
    {foreach my $test_num ($self->sbr())
       { print $file &pack_SBR($self->sbr($test_num)) ; }}

  # If there are any HBR records, print them
  if ($sort)
  	{foreach my $test_num (sort {$a <=> $b} $self->hbr())
   	  { print $file &pack_HBR($self->hbr($test_num)) ; }}
  else
  	{foreach my $test_num ($self->hbr())
   	  { print $file &pack_HBR($self->hbr($test_num)) ; }}

  # Print the MRR record.
  (my $mrr) = $self->get_exists_ref('mrr') ;
  print $file &pack_MRR($mrr) ;

  return(0) ;
}

sub epdr
{
  my $self = shift ;
  my $id = shift ;
  my %opt = @_ ;
  
  if (defined($id))
  {
    if (! defined($self->{epdr}{$id}))
    {
      my %epdr = %{$Session::init{epdr}} ;
      $self->{'epdr'}{$id} = \%epdr ;
    }
    return $self->{'epdr'}{$id} ;
  }
  else
  {
    return keys(%{$self->{'epdr'}});
  }
}

sub destroy_epdr
{
  my $self = shift ;
  my $id = shift ;
  
  if (defined($id))
  {
    if (defined($self->{epdr}{$id}))
    {
      delete($self->{'epdr'}{$id}) ;
    }
  }
  else
  {
    undef $self->{'epdr'} ; 
  }
return ;
}


sub efdr
{
  my $self = shift ;
  my $id = shift ;
  my %opt = @_ ;
  
  if (defined($id))
  {
    if (! defined($self->{efdr}{$id}))
    {
      my %efdr = %{$Session::init{efdr}} ;
      $self->{'efdr'}{$id} = \%efdr ;
    }
    return $self->{'efdr'}{$id} ;
  }
  else
  {
    return keys(%{$self->{'efdr'}});
  }
}

sub destroy_efdr
{
  my $self = shift ;
  my $id = shift ;
  
  if (defined($id))
  {
    if (defined($self->{efdr}{$id}))
    {
      delete($self->{'efdr'}{$id}) ;
    }
  }
  else
  {
    undef $self->{'efdr'} ; 
  }
return ;
}

sub tsr
  {
  my $self = $_[0] ;
  my $id = $_[1] ;

  if (defined($id))
  {
    if (! defined($self->{tsr}{$id}))
    {
      my %tsr = %{$Session::init{tsr}} ;
      $self->{'tsr'}{$id} = \%tsr ;
    }
    return $self->{'tsr'}{$id} ;
  }
  else
  {
    return keys(%{$self->{'tsr'}}) ;
  }
}

sub hbr
{
  my $self = $_[0] ;
  my $id = $_[1] ;

  #if(!defined $self->{hbr})
  #{
	#keys(%{$self->{hbr}}) = 16;
  #}

  if (defined($id))
  {
    if (! defined($self->{hbr}{$id}))
    {
      my %hbr = %{$Session::init{hbr}} ;
      $self->{'hbr'}{$id} = \%hbr ;
    }
    return $self->{'hbr'}{$id} ;
  }
  else
  {
    return keys(%{$self->{'hbr'}}) ;
  }
}

sub bgd 
{
  my $self = shift ;
  my $id = shift ;

  #if(!defined $self->{bgd})
  #{
	#keys(%{$self->{bgd}}) = 16;
  #}

  if (defined($id))
  {
    if (! defined($self->{bgd}{$id}))
    {
      my %bgd = %{$Session::init{bgd}} ;
      $self->{'bgd'}{$id} = \%bgd ;
    }
    return $self->{'bgd'}{$id} ;
  }
  else
  {
    return keys(%{$self->{'bgd'}}) ;
  }
}


sub sbr
{
  my $self = $_[0] ;
  my $id = $_[1] ;

  #if(!defined $self->{sbr})
  #{
	#keys(%{$self->{sbr}}) = 16;
  #}

  if (defined($id))
  {
    if (! defined($self->{sbr}{$id}))	
    {
      my %sbr = %{$Session::init{sbr}} ;
      $self->{'sbr'}{$id} = \%sbr ;
    }
    return $self->{'sbr'}{$id} ;
  }
  else
  {
    return keys(%{$self->{'sbr'}}) ;
  }
}

sub destroy_part
  {
  my $self = $_[0] ;
  my $id = $_[1] ;
  if (defined($id))
  {
    if (defined($self->{part}{$id}))
    {
      delete $self->{'part'}{$id} ;
    }
  }
  else
  {
    undef $self->{'part'} ;
  }
  return ;
  }

#############Kerry added this############
sub part
{
  my $self = $_[0] ;
  my $id = $_[1] ;

  
  #if(!defined $self->{part})
  #{
    #keys(%{$self->{part}}) = 8;
  #}

  if (defined($id))
  {
    if (! defined($self->{part}{$id}))
    {
      $self->{'part'}{$id} = Part->new() ;
    }
    return $self->{'part'}{$id} ;
  }
  else
  {
    return keys(%{$self->{'part'}}) ;
  }
}

sub wafer
{
  my $self = $_[0] ;
  my $id = $_[1] ;

  #if(!defined $self->{wafer})
  #{
	#keys(%{$self->{wafer}}) = 8;
  #}

  if (defined($id))
  {
    if (! defined($self->{wafer}{$id}))
    {
      $self->{'wafer'}{$id} = Wafer->new() ;
    }
    return $self->{'wafer'}{$id} ;
  }
  else
  {
    return keys(%{$self->{'wafer'}}) ;
  }
}

{
package Wafer ;
use Carp ;

sub new
{
  my $self = {} ;
  #keys(%$self) = 8;

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

  if (defined($self->{$rec}))
  {
    return($self->{$rec}) ;
  }
  else
  {
    return(undef) ;
  }
}

sub wtsr
{
  my $self = $_[0] ;
  my $id = $_[1] ;

  if (defined($id))
  {
    if (! defined($self->{wtsr}{$id}))
    {
      my %wtsr = %{$Session::init{wtsr}} ;
      $self->{'wtsr'}{$id} = \%wtsr ;
    }
    return $self->{'wtsr'}{$id} ;
  }
  else
  {
    return keys(%{$self->{'wtsr'}}) ;
  }
}

sub whbr
{
  my $self = $_[0] ;
  my $id = $_[1] ;

  #if(!defined $self->{whbr})
  #{
	#keys(%{$self->{whbr}}) = 16;
  #}

  if (defined($id))
  {
    if (! defined($self->{whbr}{$id}))
    {
      my %whbr = %{$Session::init{whbr}} ;
      $self->{'whbr'}{$id} = \%whbr ;
    }

    return $self->{'whbr'}{$id} ;
  }
  else
  {
    return keys(%{$self->{'whbr'}}) ;
  }
}

sub wsbr
{
  my $self = $_[0] ;
  my $id = $_[1] ;

  #if(!defined $self->{wsbr})
  #{
	#keys(%{$self->{wsbr}}) = 16;
  #}

  if (defined($id))
  {
    if (! defined($self->{wsbr}{$id}))
    {
      my %wsbr = %{$Session::init{wsbr}} ;
      $self->{'wsbr'}{$id} = \%wsbr ;
    }
    return $self->{'wsbr'}{$id} ;
  }
  else
  {
    return keys(%{$self->{'wsbr'}}) ;
  }
}

sub wmr
{
  my $self = $_[0] ;
  my $id = $_[1] ;

  if(!defined $self->{wmr})
  {
	keys(%{$self->{wmr}}) = 8;
  }

  if (defined($id))
  {
    if (! defined($self->{wmr}{$id}))
    {
      my %wmr = %{$Session::init{wmr}} ;
      $self->{'wmr'}{$id} = \%wmr ;
    }
    return $self->{'wmr'}{$id} ;
  }
  else
  {
    return keys(%{$self->{'wmr'}}) ;
  }
}

sub part 
{
  my $self = $_[0] ;
  my $id = $_[1] ;


  if (defined($id))
  {
    if (! defined($self->{part}{$id}))
    {
      $self->{'part'}{$id} = Part->new() ;
    }
    return $self->{'part'}{$id} ;
  }
  else
  {
    return keys(%{$self->{'part'}}) ;
  }
}

sub destroy_part
  {
  my $self = $_[0] ;
  my $id = $_[1] ;
  if (defined($id))
  {
    if (defined($self->{part}{$id}))
    {
      delete $self->{'part'}{$id} ;
    }
  }
  else
  {
    undef $self->{'part'} ;
  }
  return ;
  }
}

{
package Part ;
use Carp ;

sub new
  {
    my $self = {} ;
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

sub get_exists_ptr
  {
  my $self = $_[0] ;
  my $id = $_[1] ;
  my $keyval = $id."ptr";

  (defined($self->{$keyval})) && return(1);
  return(0) ;
  }

sub get_exists_ftr
  {
  my $self = $_[0] ;
  my $id = $_[1] ;
  my $keyval = $id."ftr";

  (defined($self->{$keyval})) && return(1);
  return(0) ;
  }

sub ptr 
  {
  my $self = $_[0] ;
  my $id = $_[1] ;
  my $ptr = ();

  if (defined($id))
    {
      my $keyval = $id."ptr";

      if ( ! defined($self->{$keyval}) )
      {
          #keys(%{$ptr}) = 8; 
          %{$ptr} = {} ;
	  $self->{$keyval} = $ptr;
	  $$ptr{test_num} = $id;
      }
      else
      {
	$ptr = $self->{$keyval};
      }

      return $ptr;
    }
  else
    {
      my @ptrs = ();

	foreach $rec (keys %{$self})
	{
		if($rec =~ /ptr/)
		{
			$copyOfRec = $rec;

			$copyOfRec =~ s/[ptr]//g;
			push @ptrs, $copyOfRec;
		}
	}

      return @ptrs;
    }
  }


sub destroy_ptr
  {
  my $self = $_[0] ;
  my $id = $_[1] ;

  if (defined($id))
    {
      my $keyval = $id."ptr";

      if (defined($self->{$keyval}) )
      {
	  delete($self->{$keyval}) ;
      }
    }
  else
    {
	foreach $rec (keys %{$self})
	{
		if($rec =~ /ptr/)
		{
			delete($self->{$rec}) ;
		}
	}
    }
  return ;
  }

sub eftr 
  {
  my $self = $_[0] ;
  my $id = $_[1] ;
  my $eftr = ();

  if (defined($id))
    {
      my $keyval = $id."eftr";

      if ( ! defined($self->{$keyval}) )
      {
          %{$eftr} = {} ;
          #keys(%{$eftr}) = 8;
          $self->{$keyval} = $eftr;
          $$eftr{test_num} = $id;
      }
      else
      {
        $eftr = $self->{$keyval};
      }

      return $eftr;
    }
  else
    {
      my @eftrs = ();

        foreach $rec (keys %{$self})
        {
                if($rec =~ /eftr/)
                {
                        $copyOfRec = $rec;

                        $copyOfRec =~ s/[eftr]//g;
                        push @eftrs, $copyOfRec;
                }
        }

      return @eftrs;
    }
  }

sub destroy_eftr
  {
  my $self = shift ;
  my $id = shift ;

  if (defined($id))
    {
      my $keyval = $id."eftr";

      if (defined($self->{$keyval}) )
      {
	  delete($self->{$keyval}) ;
      }
    }
  else
    {
	foreach $rec (keys %{$self})
	{
		if($rec =~ /eftr/)
		{
			delete($self->{$rec}) ;
		}
	}
    }
  return ;
  }




}

}

1
