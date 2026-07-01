
=pod

=head1 SYNOPSIS

  instantiate or use the method/subroutine directly as it is exposed.

B<This Utility Module> will accept site, test flow code and tester type and will return appropriate testflow code, mode and sandbox flag[0/1].
								test flow code will be appended to Program name.

=head1 AUTHOR

B<junifferallan.garcia@fairchildsemi.com>

=head1 CHANGES
	2015-Jun-8	jgarcia : added condition for utac, hana, atec  test MODE.
	2015-Jun-25 jgarcia : remove condition for tester type.
	2015-Jul-27 jgarcia : added to return approiate mode code for atec_ph_ft.
 

=head1 LICENSE

(C) Fairchild.

=cut

package PDF::Util::TestFlowCodeUtility;
use strict;
use warnings;

use base qw/Class::Accessor/;
use PDF::DpLoad;
use base qw/PDF::DpData::Base Class::Accessor/;

use Exporter qw(import);
our @EXPORT_OK = qw(getTestFlowCodeMode);

  #my $site = shift;
	#my $testFlow = shift;
	#my $tester = shift;
	my @gtkTestCodeForModeO = qw/F1R1 F1R2 F1R3 F1R4 F1R5 F1B5 R1 R2 R3 R4 R5 F2R1 F2R2 F2R3 F2R4 F2R5 F2B5 M1FT M1R1 M1R2 M1R3 M1R4 M1R5/;
	my @gtkTestCodeForModeR = qw/F1O1 OF/;
	my @gtkTestCodeForModeP = qw/F1FT F1QC F1G1 M1QC F2GR F2QC/;
	my @gtktTestFlowF1FT = qw/F1FT F1 F1R1 R1 F1R2 R2 F1R3 R3 F1R4 R4 F1R5 R5 F1OF OF F1B5/;
	my @gtkTestFlowF2FT = qw/F2FT F2R1 F2R2 F2R3 F2R4 F2R5 F2B5/;
	my @gtkTestFlowM1FT = qw/M1FT M1R1 M1R2 M1R3 M1R4 M1R5/;
	my @gtkTestFlowF1QC = qw/F1QC QC/;
	my @gtkTestFlowM1QC = qw/M1QC/;
	my @gtkTestFlowF2QC = qw/F2QC/;
	my @gtkTestFlowF2GR = qw/F2GR/;
	my @gtkTestFlowF1G1 = qw/F1G1 G1/;
	my @gtkTestFlowF1GF = qw/F1GF/;
	my @gtkTestFlowF1GR = qw/F1GR/;
	my @gtkTestFlowF1FOF = qw/F1FOF/;
	my @gtkTestFlowF1RE = qw/F1RE/;
	my @gtkTestFlowR1QC = qw/R1QC/;
	my @gtkTestFlowInvalid = qw/F1ET F1FOF F1RE R1QC/;
	
	my @hanaTestFlowSU1 = qw/SU1 S1 SU SI SU2/;
	my @hanaTestFlowFT1 = qw/FT1 F1 T1 F2 T2 FT2 F3 FT3 T3 FT4 F4 T4 FT5 F5 T5 B BT BT1 BT2 B2/;
	my @hanaTestFlowFT1withRetest = qw/RT1 R1 RT2 R2 RT3 R3 RT4 R4/;
	my @hanaTestFlowQA1 = qw/QA1 Q1 QA2 Q2 QA3 Q3/;
	my @hanaTestCodeForModeO = qw/RT1 R1 RT2 R2 RT3 R3 RT4 R4/;
	my @hanaTestCodeForModeP = ();
	my @hanaTestCodeForModeR = ();
	
	my @utacTestFlowFT1 =  qw/FT1 FT FT2/;
	my @utacTestFlowFT1withRetest = qw/RT1 RT/;
	my @utacTestFlowF1 = qw/F1 F2 F3/;
	my @utacTestFlowF1withRetest = qw/R1 R2 R3/;
	my @utacTestFlowQ1 = qw/Q1 Q2 Q3/;
	my @utacTestFlowQA = qw/QA/;
	my @utacTestFlowQAwithRetest = qw/QR1 QR2 QR3/;
	my @utacTestCodeForModeO = qw/RT1 RT R1 R2 R3 Q3 QR1 QR2 QR3/;
	my @utacTestCodeForModeP = ();
	my @utacTestCodeForModeR = ();
	
	my @atecTestFlowP1 = qw/P1 P2 P3/;
	my @atecTestFlowP1withRetest = qw/R1 R2 R3/;
	my @atecTestFlowQ1 = qw/Q1 Q2 Q3/;
	my @atecTestCodeForModeO = qw/R1 R2 R3/;
	my @atecTestCodeForModeP = ();
	my @atecTestCodeForModeR = ();
	
		
	my $mode = "";
	my $testMode = "";
	my $sandBoxFlag = 0;

### accepts site test flow code and tester type
### returns appropriate test flow code, appropriate mode, and appropriate sand box flag[0/1 - value].
sub getTestFlowCodeMode {
		
	my $site = shift;
	my $testFlow = shift;
	my $tester = shift;
	
	trim($site);
	trim($testFlow);
	trim($tester);
	
	#if($tester =~ /tmt/i) {
		
		if($site eq "gtk_tw_ft") {
			
			  		if ( grep { $_ eq $testFlow } ( @gtkTestFlowInvalid ) ) {
		            #dpExit( 1, "TestMode is invalid. :$testMode" );
		            $testMode = $testFlow;
		            $sandBoxFlag = 1;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @gtkTestFlowR1QC ) ) {
		            
		            $testMode = "R1QC";
		            $sandBoxFlag = 1;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @gtkTestFlowF1RE ) ) {
		            $testMode = "F1RE";
		            $sandBoxFlag = 1;
		        }
		        elsif ( grep { $_ eq $testFlow } (@gtkTestFlowF1FOF) ) {
		            
		            $testMode = "F1FOF";
		            $sandBoxFlag = 1;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @gtkTestFlowF1GR ) ) {
		            
		            $testMode = "F1GR";
		            $sandBoxFlag = 1;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @gtkTestFlowF1GF ) ) {
		            
		            $testMode = "F1GF";
		            $sandBoxFlag = 1;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @gtkTestFlowF1G1 ) ) {
		            
		            $testMode = "F1G1";
		            $sandBoxFlag = 1;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @gtkTestFlowF2GR ) ) {
		            
		            $testMode = "F2GR";
		            $sandBoxFlag = 0;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @gtkTestFlowF2QC ) ) {
		            
		            $testMode = "F2QC";
		            $sandBoxFlag = 0;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @gtkTestFlowM1QC ) ) {
		            
		            $testMode = "M1QC";
		            $sandBoxFlag = 0;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @gtkTestFlowF1QC ) ) {
		            
		            $testMode = "F1QC";
		            $sandBoxFlag = 0;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @gtkTestFlowM1FT ) ) {
		            
		            $testMode = "M1FT";
		            $sandBoxFlag = 0;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @gtkTestFlowF2FT ) ) {
		            
		            $testMode = "F2FT";
		            $sandBoxFlag = 0;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @gtktTestFlowF1FT ) ) {
		            
		            $testMode = "F1FT";
		            $sandBoxFlag = 0;
		        }
		        else {
		        		$testMode = $testFlow;
		        		$sandBoxFlag = 1;
		        }
		        ###MODE###
		        
		        $mode = getMode($testFlow, $site);

		}
		
		elsif($site eq "hana_th_ft" || $site eq "hana_cn_ft") {
			
			  		if ( grep { $_ eq $testFlow } ( @hanaTestFlowQA1 ) ) {
		            
		            $testMode = "QA1";
		            $sandBoxFlag = 0;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @hanaTestFlowFT1 ) ) {
		            $testMode = "FT1";
		            $sandBoxFlag = 0;
		        }
		        elsif ( grep { $_ eq $testFlow } (@hanaTestFlowFT1withRetest) ) {
		            
		            $testMode = "FT1";
		            $sandBoxFlag = 0;
		        }
		        elsif ( grep { $_ eq $testFlow } ( @hanaTestFlowSU1 ) ) {
		            
		            $testMode = "SU1";
		            $sandBoxFlag = 1;
		        }else { 
		        	$testMode = $testFlow;
		        	$sandBoxFlag = 1;
		        }
		        
		        ###MODE###
		        $mode = getMode($testFlow, $site);
		}
		elsif($site eq "utac_th_ft") {
			if ( grep { $_ eq $testFlow } ( @utacTestFlowQAwithRetest ) ) {
		            
		            $testMode = "QA";
		            $sandBoxFlag = 0;
		            #$mode = "R";
		        }
		  elsif ( grep { $_ eq $testFlow } ( @utacTestFlowQA ) ) {
		            $testMode = "QA";
		            $sandBoxFlag = 0;
		  }
		  elsif ( grep { $_ eq $testFlow } ( @utacTestFlowQ1 ) ) {
		            $testMode = "Q1";
		            $sandBoxFlag = 0;
		  }
		  elsif ( grep { $_ eq $testFlow } ( @utacTestFlowF1withRetest ) ) {
		            $testMode = "F1";
		            $sandBoxFlag = 0;
		            #$mode = "R";
		  }
		  elsif ( grep { $_ eq $testFlow } ( @utacTestFlowF1 ) ) {
		            $testMode = "F1";
		            $sandBoxFlag = 0;
		            
		  }
		  elsif ( grep { $_ eq $testFlow } ( @utacTestFlowFT1withRetest ) ) {
		            $testMode = "FT1";
		            $sandBoxFlag = 0;
		            #$mode = "R"
		  }
		  elsif ( grep { $_ eq $testFlow } ( @utacTestFlowFT1) ) {
		            $testMode = "FT1";
		            $sandBoxFlag = 0;
		            
		  }
		  else {
		  	
		  	$testMode = $testFlow;
		    $sandBoxFlag = 1;
		  	
		  }
		  $mode = getMode($testFlow, $site);

		}
		elsif ($site eq "atec_ph_ft") {
			
			if ( grep { $_ eq $testFlow } ( @atecTestFlowP1 ) ) {
		            
		            $testMode = "P1";
		            $sandBoxFlag = 0;
		            
		        }
		  elsif ( grep { $_ eq $testFlow } ( @atecTestFlowP1withRetest ) ) {
		            $testMode = "P1";
		            $sandBoxFlag = 0;
		            $mode = "O";
		  }
		  elsif ( grep { $_ eq $testFlow } ( @atecTestFlowQ1 ) ) {
		            $testMode = "Q1";
		            $sandBoxFlag = 0;
		            
		  }
		  else {
		  	
		  	$testMode = $testFlow;
		    $sandBoxFlag = 1;
		  }
			
		#}
		
		
		
	}
	
	return ( $testMode, $mode, $sandBoxFlag );
	
}




### accepts test flow code and site
### returns appropriate mode code
sub getMode {
	
	my $testMode = shift;
	my $site = shift;
	my $mode = "";
	
	if($site eq "gtk_tw_ft") {
	    if ( grep { $_ eq $testMode } ( @gtkTestCodeForModeP ) ) {
		            
		            $mode = "P";
		            #$sandBoxFlag = 0;
		  }
		  elsif ( grep { $_ eq $testMode } ( @gtkTestCodeForModeR ) ) {
		            
		            $mode = "R";
		            #$sandBoxFlag = 0;
		  }
		  elsif ( grep { $_ eq $testMode } ( @gtkTestCodeForModeO ) ) {
		            
		       $mode = "0";
		            #$sandBoxFlag = 0;
		  }
	}
	elsif ($site eq "hana_th_ft" || $site eq "hana_cn_ft") {
		
		if ( grep { $_ eq $testMode } ( @hanaTestCodeForModeO ) ) {
		            
		            $mode = "O";
		            #$sandBoxFlag = 0;
		}
		elsif ( grep { $_ eq $testMode } ( @hanaTestCodeForModeP ) ) {
		            
		            $mode = "P";
		            #$sandBoxFlag = 0;
		}
		elsif ( grep { $_ eq $testMode } ( @hanaTestCodeForModeR ) ) {
		            
		            $mode = "R";
		            #$sandBoxFlag = 0;
		}
	
	}
	elsif ($site eq "utac_th_tmt") {
		
		if ( grep { $_ eq $testMode } ( @utacTestCodeForModeO ) ) {
		            
		            $mode = "O";
		            #$sandBoxFlag = 0;
		}
		elsif ( grep { $_ eq $testMode } ( @utacTestCodeForModeP ) ) {
		            
		            $mode = "P";
		            #$sandBoxFlag = 0;
		}
		elsif ( grep { $_ eq $testMode } ( @hanaTestCodeForModeR ) ) {
		            
		            $mode = "R";
		            #$sandBoxFlag = 0;
		}
	}
	elsif ($site eq "atec_ph_tmt") {
		
		if ( grep { $_ eq $testMode } ( @atecTestCodeForModeO ) ) {
		            
		            $mode = "O";
		            #$sandBoxFlag = 0;
		}
		elsif ( grep { $_ eq $testMode } ( @atecTestCodeForModeP ) ) {
		            
		            $mode = "P";
		            #$sandBoxFlag = 0;
		}
		elsif ( grep { $_ eq $testMode } ( @atecTestCodeForModeR ) ) {
		            
		            $mode = "R";
		            #$sandBoxFlag = 0;
		}
	}
		  
	return ($mode);
	
}

1;