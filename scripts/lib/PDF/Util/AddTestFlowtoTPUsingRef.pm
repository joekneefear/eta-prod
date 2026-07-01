# 04-June-2015 Eric - Initial Release
# 09-June-2015 Eric - Parse retest codes
# 15-July-2015 jgarcia - modified to not append test flow code in the program... here, only return the test flow code to the caller.
# 07-Oct-2016 Eric - added amkor_ph_ft
# 07-Oct-2016 Eric - sandbox if test code not found
# 10-Oct-2016 Eric - return array of testcode
# 18-Oct-2016 Eric - fix script to return the correct $header->INDEX2
# 03-Nov-2016 Eric - amkor_tw accepts blank test code.
#2021/04/21 jgarcia : modified to not hardcode testflow code reference file location. pass as parameter to addTestFlowtoTP instead to load_testflow_ref.
#
package PDF::Util::AddTestFlowtoTPUsingRef;
use strict;

use base qw/Class::Accessor/;
use PDF::DpLoad;
use base qw/PDF::DpData::Base Class::Accessor/;
use Exporter qw(import);
use FindBin::libs;
use Getopt::Long qw/:config ignore_case auto_help/;
use Pod::Usage qw/pod2usage/;
use File::Basename qw/basename/;
use PDF::Log;
use PDF::DpLoad;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Formatter;
use PDF::DpData::HeaderLong;
use PDF::DpData::HeaderShort;
use PDF::DpData::Model;
use v5.10;
no warnings qw/experimental::lexical_subs experimental::smartmatch/;

our @EXPORT_OK = qw(addTestFlowtoTP load_testflow_ref);

my %testFlow     = ();
my %retestCode   = ();
my @tfSbox       = ();
my @tfProd       = ();
my @tcode        = ();
my $testFlowCode = "";

sub addTestFlowtoTP {
    my $model    = shift;
    my $testMode = shift;
    my $site     = shift;
    my $refFile = shift;
    my $tf_mode  = "";
    my $header   = $model->header;
    my $program  = $header->PROGRAM;
    if ( grep { $_ eq $site } (qw/gtk_tw_ft hana_th_ft atec_ph_ft isti_tw_csp its_tw_ft amkor_tw_csp etrend_tw_ft utac_th_ft amkor_ph_ft/) ) {
       &load_testflow_ref($site, $refFile);
       $tf_mode = $testFlow{$testMode} if exists($testFlow{$testMode});
       if ( (grep { $_ eq $tf_mode } (@tfSbox))){
              $testFlowCode = $tf_mode;
	      $model->{forSBflag} = 1;
              WARN("Loaded to Sandbox due to test mode = $tf_mode");
       }
       elsif ( (grep { $_ eq $tf_mode } (@tfProd))){
		$testFlowCode = $tf_mode;
       }
       else {
       		if ($site =~ /amkor_tw_csp/ && $testMode eq "") {
			$testFlowCode = $tf_mode;
		}else {
       			WARN ("Unknown test mode = $testMode");	
			$testFlowCode = $tf_mode;
			$model->{forSBflag} = 1;
		}
       }
       INFO("Appended Test Code to Program = $tf_mode");
       INFO("Corresponding Code = $retestCode{$testMode}");
       $header->INDEX2($retestCode{$testMode});
    }
    return($testFlowCode);
}

sub load_testflow_ref {
    my $site = shift;
    my $ref_file = shift;
    my $line = "";
    my $flag = 0;
    #my $ref_file = "/home/dpower/project/fmt/TestFlowCode/testFlow.ref";
    open REF, $ref_file or die "can't open test flow reference file: $?\n";
    while($line=uc(<REF>))
    {
        next if $line =~ /^\#|^\s+/;
	if ( $line =~ /$site/i ) {
	  $flag = 1;
	}
	elsif ( $line =~ /\,.+/ && $flag == 1) {
          my ($tf_code,$append,$rw_code,$load) = split /\,/, $line;
          next if $tf_code eq "" || $append eq "";
          $testFlow{$tf_code} = $append;
	  $retestCode{$tf_code} = $rw_code;
          push @tfSbox, $tf_code if $load =~ /Sandbox/i;
	  push @tfProd, $tf_code if $load =~ /Production/i;
	  push @tcode, $tf_code;
	}
	elsif ( $line !~ /$site/ ) {
	  $flag = 0;
	}
    }
    close(REF);
    return @tcode;
}
1;
