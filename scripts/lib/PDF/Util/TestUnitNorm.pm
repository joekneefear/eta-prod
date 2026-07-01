
=pod

=head1 SYNOPSIS

  instantiate or use the method/subroutine directly as it is exposed.

B<This Utility Module> will try to convert/nomalize the HSL and LSL.. etc into base unit.

=head1 AUTHOR

B<junifferallan.garcia@fairchildsemi.com>

=head1 CHANGES

 	2015/04/24 - jgarcia - fixed bug on Micron unit to be treated as Mega.
 	2015/04/30 - jgarcia - checked $test->XXX first if defined before checking if it is not equal N/A to avoid getting warnings.
 	2015/05/01 - jgarcia - do nothing for GNG unit
 	2015/06/03 - rcyr    - Do nothing when unit is blank or undefined.
 	2015/06/05 - jgarcia - Modified to not apply the muliplier to LSL and HSL when LSL and HSL are not in digit.
	2015/06/25 - rcyr    - Do nothing when unit is GAIN.
	2015/07/06 - Grace   - added '0' in some limit value such as '.94' and '-.984'.
	2015/07/08 - Grace   - Changed from "/^[0-9]/" to "/^(\-?)[0-9]/" (limits were not normalized to base units)
	2015/09/02 - jgarcia - Changed from "/^[0-9]/" to "/^(\-?)[0-9]/" (limits were not normalized to base units)[if negative value]-> for sort tests.
	2015/12/16 - jgarcia - do nothing for MHO unit which is usually treated as M as it start with M.
	2015/01/25 - jgarcia - modified to set PF unit as pico which is interpreted as pF. [1.0 x 10^(-12)]
	2015/01/27 - jgarcia - modified to treat PF as Pass and Fail, therefore, will not be normalized.
	2015/02/02 - jgarcia - modified to fix bug for pF as being treated as PF which will not be normalized.
	2016/02/10 - eric - do not normalize if unit eq amps|volts|ang. fix bug to normalize limit values if plus is at the beginning.
	2016/03/10 - eric - do not normalize if unit eq microns
	19-Oct-2016 - gmiole - do not normalize if unit eq grav
	2017/04/24 - jgarcia - corrected the test's type variable name.
	2018/12/21 - eric - fixed bug on units starting with /^K/i

=head1 LICENSE

(C) Fairchild.

=cut

package PDF::Util::TestUnitNorm;
use strict;
use warnings;

use base qw/Class::Accessor/;
use PDF::DpLoad;
use base qw/PDF::DpData::Base Class::Accessor/;
use PDF::Log;

use Exporter qw(import);
our @EXPORT_OK = qw(normalizeToBaseUnit @multipliers);


my $multiplier = "";
my $test_unit = "";
our @multipliers = ();




sub normalizeToBaseUnit {

	my $model = shift;

  if(@{$model->tests}) {
  
  	my $counter = 0;
  
    foreach my $test (@{$model->tests}) {
    
    	$multiplier = 1;
    	$test_unit = "";
    	
    	#if (defined $test->units eq "PF") {
    	#	$test->units("pF");
    	#}
    
#    	if (!defined $test->units || $test->units =~ /^(PF|P\/F|MHO|A|Pct|Percent|P\_F|GNG|GAIN)$/ || $test->units eq "")	{
#    		### DO NOTHING ###
#		}
	if (!defined $test->units || $test->units eq "PF" || $test->units =~ /^(P\/F|MHO|A|Pct|Percent|P\_F|GNG|GAIN|amps|volts|ang|microns)$/i || $test->units eq "")	{
    		### DO NOTHING ###
	}
	 	elsif ($test->units =~ /^a/)
    	{
    		$test_unit = $test->units;
    		$test_unit =~ s/^a//;
    		$test_unit = uc($test_unit);
    		$test->units($test_unit);
    		$multiplier = 1e-18;
    	}
    	elsif ($test->units =~ /^f/)
    	{
    		$test_unit = $test->units;
    		$test_unit =~ s/^f//;
    		$test_unit = uc($test_unit);
    		$test->units($test_unit);
    		$multiplier = 1e-15;
    	}
    	elsif ($test->units =~ /^p/)
    	{
    		$test_unit = $test->units;
    		$test_unit =~ s/^p//;
    		$test_unit = uc($test_unit);
    		$test->units($test_unit);
    		$multiplier = 1e-12;
    	}
    	elsif ($test->units =~ /^n/)
    	{
    		$test_unit = $test->units;
    		$test_unit =~ s/^n//;
    		$test_unit = uc($test_unit);
    		$test->units($test_unit);
    		$multiplier = 1e-9;
    	}
    	elsif ($test->units =~ /^u/)
    	{
    		$test_unit = $test->units;
    		$test_unit =~ s/^u//;
    		$test_unit = uc($test_unit);
    		$test->units($test_unit);
    		$multiplier = 1e-6;
    	}
    	elsif ($test->units =~ /^m/ )
    	{
    		$test_unit = $test->units;
    		$test_unit =~ s/^m//;
    		$test_unit = uc($test_unit);
    		$test->units($test_unit);
    		$multiplier = 1e-3;
    	}
    	elsif ($test->units =~ /^K/i)
    	{
    		$test_unit = $test->units;
    		$test_unit =~ s/^K//i;
    		$test_unit = uc($test_unit);
    		$test->units($test_unit);
    		$multiplier = 1e3;
    	}
    	elsif ($test->units =~ /^M/ && $test->units !~ /Micron/i && $test->units !~ /MHO/i)
    	{
    		$test_unit = $test->units;
    		$test_unit =~ s/^M//;
    		$test_unit = uc($test_unit);
    		$test->units($test_unit);
    		$multiplier = 1e6;
    	}
    	elsif ($test->units =~ /^G/ && $test->units !~ /GNG/i && $test->units !~ /GRAV/i)
    	{
    		$test_unit = $test->units;
    		$test_unit =~ s/^G//;
    		$test_unit = uc($test_unit);
    		$test->units($test_unit);
    		$multiplier = 1e9;
    	}
    	elsif ($test->units =~ /^T/)
    	{
    		$test_unit = $test->units;
    		$test_unit =~ s/^T//;
    		$test_unit = uc($test_unit);
    		$test->units($test_unit);
    		$multiplier = 1e12;
    	}
    	elsif ($test->units =~ /^P/)
    	{
    		$test_unit = $test->units;
    		$test_unit =~ s/^P//;
    		$test_unit = uc($test_unit);
    		$test->units($test_unit);
    		$multiplier = 1e15;
    	}
    
    	$multipliers[$counter] = $multiplier;
    	$counter++;
    
    	trim($test->LSL);
    	trim($test->HSL);
    	trim($test->LPL);
    	trim($test->HPL);
    	trim($test->LOL);
    	trim($test->HOL);
    	trim($test->LWL);
    	trim($test->HWL);

	$test->LSL(AddZeroAhead($test->LSL));
	$test->HSL(AddZeroAhead($test->HSL));
	$test->LPL(AddZeroAhead($test->LPL));
	$test->HPL(AddZeroAhead($test->HPL));
	$test->LOL(AddZeroAhead($test->LOL));
	$test->HOL(AddZeroAhead($test->HOL));
	$test->LWL(AddZeroAhead($test->LWL));
	$test->HWL(AddZeroAhead($test->HWL));

    	if(defined($test->LSL)) {
    		if ($test->{LSL} ne "N/A" &&  ($test->{LSL} =~ /^(\-?)[0-9]/ || $test->{LSL} =~ /^(\+?)[0-9]/ || $test->{LSL} =~ /^[0-9]/)) {
    			 $test->LSL($test->LSL * $multiplier);
    		}
    	}
    	if(defined($test->HSL)) {
    		if ($test->{HSL} ne "N/A" && ($test->{HSL} =~ /^(\-?)[0-9]/ || $test->{HSL} =~ /^(\+?)[0-9]/ || $test->{HSL} =~ /^[0-9]/)) {
    			$test->HSL($test->HSL * $multiplier);
    		}
    	}
    	if(defined($test->LPL)) {
    		if ($test->{LPL} ne "N/A" && ($test->{LPL} =~ /^(\-?)[0-9]/ || $test->{LSL} =~ /^(\+?)[0-9]/ || $test->{LSL} =~ /^[0-9]/)) {
    			$test->LPL($test->LPL * $multiplier);
    		}
    	}
    	if(defined($test->HPL)) {
    		if ($test->{HPL} ne "N/A" && ($test->{HPL} =~ /^(\-?)[0-9]/ || $test->{HPL} =~ /^(\+?)[0-9]/ || $test->{HPL} =~ /^[0-9]/)) {
    			$test->HPL($test->HPL * $multiplier);
    		}
    	}
    	if(defined($test->LOL)) {
    		if ($test->{LOL} ne "N/A" && ($test->{LOL} =~ /^(\-?)[0-9]/ || $test->{LOL} =~ /^(\+?)[0-9]/ || $test->{LOL} =~ /^[0-9]/)) {
    			$test->LOL($test->LOL * $multiplier);
    		}
    	}
    	if(defined($test->HOL)) {
    		if ($test->{HOL} ne "N/A" && ($test->{HOL} =~ /^(\-?)[0-9]/ || $test->{HOL} =~ /^(\+?)[0-9]/ || $test->{HOL} =~ /^[0-9]/)) {
    			$test->HOL($test->HOL * $multiplier);
    		}
    	}
    	if(defined($test->LWL)) {
    		if ($test->{LWL} ne "N/A" && ($test->{LWL} =~ /^(\-?)[0-9]/ || $test->{LWL} =~ /^(\+?)[0-9]/ || $test->{LWL} =~ /^[0-9]/)) {
    			$test->LWL($test->LWL * $multiplier);
    		}
    	}
    	if(defined($test->HWL)) {
    		if ($test->{HWL} ne "N/A" && ($test->{HWL} =~ /^(\-?)[0-9]/ || $test->{HWL} =~ /^(\+?)[0-9]/ || $test->{HWL} =~ /^[0-9]/)) {
    			$test->HWL($test->HWL * $multiplier);
    		}
    	}
    
    	if (defined $test->units) {
			$test->units(uc($test->units));
		}
			
		
    	#print "HERE>>>$test->LSL<<<\t>>>$test->HSL<<<\n";
    
    } ###end of foreach my $test (@{$model->tests})
    
  } ###end of if(@{$model->tests}) condition
  else {
  
    foreach my $wafer(@{$model->wafers}) {
    
      if (@{$wafer->tests}) {
      
      	my $counter = 0;
      
        foreach my $test (@{$wafer->tests}) {
        
        	$multiplier = 1;
        	$test_unit = "";
        	
        	
        	#if (defined $test->units eq "PF") {
    			#	$test->units("pF");
    			#}
        
#        	if (!defined $test->units || $test->units =~ /^(P\/F|MHO|A|Pct|Percent|P\_F|GNG|GAIN)$/ || $test->units eq "")	{
#        		### DO NOTHING
#        	}
        	if (!defined $test->units || $test->units eq "PF" || $test->units =~ /^(P\/F|MHO|A|Pct|Percent|P\_F|GNG|GAIN|amps|volts|ang|microns)$/i || $test->units eq "")	{
			### DO NOTHING ###
		}
        	elsif ($test->units =~ /^a/)
        	{
        		$test_unit = $test->units;
        		$test_unit =~ s/^a//;
        		$test_unit = uc($test_unit);
        		$test->units($test_unit);
        		$multiplier = 1e-18;
        	}
        	elsif ($test->units =~ /^f/)
        	{
        		$test_unit = $test->units;
        		$test_unit =~ s/^f//;
        		$test_unit = uc($test_unit);
        		$test->units($test_unit);
        		$multiplier = 1e-15;
        	}
        	elsif ($test->units =~ /^p/)
        	{
        		$test_unit = $test->units;
        		$test_unit =~ s/^p//;
        		$test_unit = uc($test_unit);
        		$test->units($test_unit);
        		$multiplier = 1e-12;
        	}
        	elsif ($test->units =~ /^n/)
        	{
        		$test_unit = $test->units;
        		$test_unit =~ s/^n//;
        		$test_unit = uc($test_unit);
        		$test->units($test_unit);
        		$multiplier = 1e-9;
        	}
        	elsif ($test->units =~ /^u/)
        	{
        		$test_unit = $test->units;
        		$test_unit =~ s/^u//;
        		$test_unit = uc($test_unit);
        		$test->units($test_unit);
        		$multiplier = 1e-6;
        	}
        	elsif ($test->units =~ /^m/)
        	{
        		$test_unit = $test->units;
        		$test_unit =~ s/^m//;
        		$test_unit = uc($test_unit);
        		$test->units($test_unit);
        		$multiplier = 1e-3;
        	}
        	elsif ($test->units =~ /^K/i)
        	{
        		$test_unit = $test->units;
        		$test_unit =~ s/^K//i;
        		$test_unit = uc($test_unit);
        		$test->units($test_unit);
        		$multiplier = 1e3;
        	}
        	elsif ($test->units =~ /^M/ && $test->units !~ /Micron/i && $test->units !~ /MHO/i)
        	{
        		$test_unit = $test->units;
        		$test_unit =~ s/^M//;
        		$test->units($test_unit);
        		$multiplier = 1e6;
        	}
        	elsif ($test->units =~ /^G/ && $test->units !~ /GNG/i && $test->units !~ /GRAV/i)
        	{
        		$test_unit = $test->units;
        		$test_unit =~ s/^G//;
        		$test->units($test_unit);
        		$multiplier = 1e9;
        	}
        	elsif ($test->units =~ /^T/)
        	{
        		$test_unit = $test->units;
        		$test_unit =~ s/^T//;
        		$test->units($test_unit);
        		$multiplier = 1e12;
        	}
        	elsif ($test->units =~ /^P/)
        	{
        		$test_unit = $test->units;
        		$test_unit =~ s/^P//;
        		$test_unit = uc($test_unit);
        		$test->units($test_unit);
        		$multiplier = 1e15;
        	}
		
        	$multipliers[$counter] = $multiplier;
        	$counter++;
        
        	trim($test->LSL);
        	trim($test->HSL);
        	trim($test->LPL);
        	trim($test->HPL);
        	trim($test->LOL);
        	trim($test->HOL);
        	trim($test->LWL);
        	trim($test->HWL);
			        
        	if(defined($test->LSL)) {
        		if ($test->{LSL} ne "N/A" && ($test->{LSL} =~ /^(\-?)[0-9]/ || $test->{LSL} =~ /^(\+?)[0-9]/ || $test->{LSL} =~ /^[0-9]/)) {
        			$test->LSL($test->LSL * $multiplier);
        		}
        	}
        	if(defined($test->HSL)) {
        		if ($test->{HSL} ne "N/A" && ($test->{HSL} =~ /^(\-?)[0-9]/ || $test->{HSL} =~ /^(\+?)[0-9]/ || $test->{HSL} =~ /^[0-9]/)) {
        			$test->HSL($test->HSL * $multiplier);
        		}
        	}
        	if(defined($test->LPL)) {
        		if ($test->{LPL} ne "N/A" && ($test->{LPL} =~ /^(\-?)[0-9]/ || $test->{LPL} =~ /^(\+?)[0-9]/ || $test->{LPL} =~ /^[0-9]/)) {
        			$test->LPL($test->LPL * $multiplier);
        		}
        	}
        	if(defined($test->HPL)) {
        		if ($test->{HPL} ne "N/A" && ($test->{HPL} =~ /^(\-?)[0-9]/|| $test->{HPL} =~ /^(\+?)[0-9]/ || $test->{HPL} =~ /^[0-9]/)) {
        			$test->HPL($test->HPL * $multiplier);
        		}
        	}
        	if(defined($test->LOL)) {
        		if ($test->{LOL} ne "N/A" && ($test->{LOL} =~ /^(\-?)[0-9]/ || $test->{LOL} =~ /^(\+?)[0-9]/ || $test->{LOL} =~ /^[0-9]/)) {
        			$test->LOL($test->LOL * $multiplier);
        		}
        	}
        	if(defined($test->HOL)) {
        		if ($test->{HOL} ne "N/A" && ($test->{HOL} =~ /^(\-?)[0-9]/ || $test->{HOL} =~ /^(\+?)[0-9]/ || $test->{HOL} =~ /^[0-9]/)) {
        			$test->HOL($test->HOL * $multiplier);
        		}
        	}
        	if(defined($test->LWL)) {
        		if ($test->{LWL} ne "N/A" && ($test->{LWL} =~ /^(\-?)[0-9]/ || $test->{LWL} =~ /^(\+?)[0-9]/ || $test->{LWL} =~ /^[0-9]/)) {
        			$test->LWL($test->LWL * $multiplier);
        		}
        	}
        	if(defined($test->HWL)) {
        		if ($test->{HWL} ne "N/A" && ($test->{HWL} =~ /^(\-?)[0-9]/ || $test->{HWL} =~ /^(\+?)[0-9]/ || $test->{HWL} =~ /^[0-9]/)) {
        			$test->HWL($test->HWL * $multiplier);
        		}
        	}
        
			if (defined $test->units) {
				$test->units(uc($test->units));
			}
        
        }
      
      }
    
    }
  }

}### end of subroutine

sub AddZeroAhead{
my $value = shift;

if (defined $value ){
	if($value =~/^\./){
		$value = "0".$value;
	}
	elsif($value =~/^\-\.(\d+)/)
	{
		$value = "-0.".$1;
	}
}

return $value;

}
1;
