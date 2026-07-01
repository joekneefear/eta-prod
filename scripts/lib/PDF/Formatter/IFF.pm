# SVN $Id: IFF.pm 2569 2020-09-01 13:51:24Z dpower $
# 18-Feb-2016 Eric	: added sub printPar_v2 to support multiple IFF with not unique start time.
# 10-Mar-2016 Eric	: added sub printPar_v3 to cater CREE datalog format.
# 16-Mar-2016 Eric	: added cnt in statToString
# 29-Mar-2016 Eric	: retained outfilename format in  printPar_v3.
# 25-Apr-2016 Eric	: add relItems for REL loading
# 04-May-2016 Eric	: added sub printPar_v4 to append ringid instead of waf# (icos)
# 28-Jul-2016 jgarcia : added printDefect subroutine to write defect data.
# 28-Jul-2016 jgarcia : added headerDefectToString and defectToString to convert header and defect attribute to string.
# 13-Mar-2017 Eric      : added sub printPar_v5 to fix the
# 			  Number of wafers exceeded the maximum allowed wafers per lot which is <128> error (Autovision)
# 28-Jul-2020 jgarcia : make sure to only try to normalize results that are pure numeric.
# 30-Jun-2020 jgarcia : added support to touchdown_num.
# 12-May-2021 Eric	:added org_x org_y in dataItems
# 16-Sep-2021 gmllego   :added support to ecid.
# 23-May-2024 Eric	: added functions printAutoChar autoCharHeaderToString autoCharParametersToString
#
package PDF::Formatter::IFF;
use strict;
use PDF::DpLoad;
use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";
use PDF::Log;
use PDF::Util::TestUnitNorm qw/normalizeToBaseUnit @multipliers/;
use Scalar::Util qw(looks_like_number);

my $attr = [qw/writer model defect/];

sub array { return qw/testItems dataItems binItems relItems indexItems/; }

__PACKAGE__->mk_accessors(array, @$attr);

sub new {
	my ($class, $args) = @_;
	my $self = $class->SUPER::new($args);
	$self->testItems ([qw/number name units/]);
	$self->binItems ([qw/number name PF count/]);
	$self->dataItems ([qw/x y site partid touchdown_num soft_bin hard_bin org_x org_y bindesc testtime/]);
	$self->relItems ([qw/qpnumber devchar lotchar strname strduration atetemp datalogtype/]);
	$self->indexItems ([qw/index1 index2 index3 index4 index5/]);
	return $self;
}

sub printLineHashArray {
	my $self =shift;
	my $wr = $self->writer;
	my $model = $self->model;
	my $outfilename = $wr->basename;
	#my ($route,$lineData);
	my $fileData = $model->misc;

	foreach my $route(keys (%{$fileData})){
		#INFO("ROUTE=$route");
		next if $route eq "header";
		#next if $route =~ /HASH.+/i;
		if($route ne "" && $route !~ /header/i) {
			my $addr = $fileData->{$route};
			my $fname = "${outfilename}_${route}";
		  #INFO("OUT=$fname");
		  $wr->basename($fname);
			$wr->open;
			if($fileData->{'header'} ne "") {
				$wr->put($fileData->{'header'}."\n");
			}
			foreach my $lineData(@$addr){
				$wr->put($lineData."\n");
			}
			$wr->put( "\n" );
			$wr->close;
		}
  }
}


sub printLineArray {
	my $self =shift;
	my $wr = $self->writer;
	my $model = $self->model;
	my $outfilename = $wr->basename;

	$wr->open;
	foreach my $line (@{$model->misc}) {
		$wr->put($line."\n");
	}
	$wr->put( "\n" );
	$wr->close;
}

sub printDefectRefFile {
	my $self =shift;
	my $wr = $self->writer;
	my $defect = $self->defect;
	my $outfilename = $wr->basename;
	#my $misc = $model->misc;

	$wr->open;
	#$wr->put( "<BOM>\n" . $self->headerDefectToString($model->header));
	#$wr->put( $self->defectRefFileToString($defect->) ."<EOM>\n" );
	$wr->put( "<DEFECT_REF_DATA>\n" );
	$wr->put( $self->defectRefFileToString($defect));
	$wr->put( "</DEFECT_REF_DATA>\n" );
	#$wr->put( "\n" );
	$wr->close;
}

sub defectRefFileToString{
	my $self= shift;
	my $defect = $self->defect;
	#my $defect = $model->defect;
	#my $dataSource = $model->dataSource;
	my $string  ;
	foreach my $key ($defect->list){
		my $value = $defect->{$key};
			if($key =~ /DEFECT_INDEX$|IMAGE_INDEX$|IMAGE_FILENAME$|IMAGE_TYPE$|SLOT$|STEP_ID$|RESULT_DATETIME$|LOT$/) {
			$value = repNA($value);
			$string .=  "$key=$value\n";
		}

	}
	return $string;
}

sub printDefect {
	my $self =shift;
	my $wr = $self->writer;
	my $model = $self->model;
	my $outfilename = $wr->basename;
	my $misc = $model->misc;

	$wr->open;
	$wr->put( "<BOM>\n" . $self->headerDefectToString($model->header));
	$wr->put( $self->defectToString($model->defect) ."<EOM>\n" );
	#$wr->put( "<DEFECT_DATA>\n" );
	foreach my $d (@{$model->misc}) {
			$wr->put($d);
	}
	$wr->put( "\n" );
	$wr->close;
}

sub headerDefectToString{
	my $self= shift;
	my $model = $self->model;
	my $header = $model->header;
	my $dataSource = $model->dataSource;
	my $string  ;
	foreach my $key ($header->list){
		my $value = $header->{$key};
		if ($key eq 'LOT'){
			$value = uc($value);
		}
		if($key =~ /LOT$|PRODUCT$|FAMILY|FAB|EQUIP1_ID$|PROCESS$|VERSION|CREATION_DATE$|DATE_CODE$/) {
			$value = repNA($value);
			$string .=  "$key=$value\n";
		}

	}
	return $string;
}

sub defectToString{
	my $self= shift;
	my $model = $self->model;
	my $defect = $model->defect;
	my $dataSource = $model->dataSource;
	my $string  ;
	foreach my $key ($defect->list){
		my $value = $defect->{$key};
			if($key =~ /SLOT$|STEP_ID$|RESULT_DATETIME$|LOCATION$/) {
			$value = repNA($value);
			$string .=  "$key=$value\n";
		}

	}
	return $string;
}

sub printBinmap{
	my $self =shift;
	my $wr = $self->writer;
	my $model = $self->model;
	my $outfilename = $wr->basename;
	my %group;
	foreach my $wafer (@{$model->wafers}){
		my $key = $wafer->START_TIME ;
		unless (exists $group{$key}) {
			$group{$key} = [];
		}
		push @{$group{$key}}, $wafer;
	}
	foreach my $wafers(values %group){
		my $firstWafer = $wafers->[0] ;
		if (defined $firstWafer->START_TIME){
			$model->header->START_TIME($firstWafer->START_TIME);
		}
		if (defined $firstWafer->END_TIME){
			$model->header->END_TIME($firstWafer->END_TIME);
		}
		if ($firstWafer->number + 0 > 0){
			$wr->basename($outfilename."_".sprintf("%02d",$firstWafer->number)) ;
		}

		$wr->open;
		$wr->put( "<HEADER>\n" . $self->headerToString_v2($model->header) ."</HEADER>\n" );

		if (defined $model->wmap){
			$wr->put( "<WMAP>\n" . $model->wmap->toString . "</WMAP>\n");
		}
		foreach my $wafer(@$wafers){
			my $wafer_id = uc($model->header->LOT)."_".sprintf("%02d",$wafer->number);

			$wr->put( "<WAFER>\n");
			if($wafer->name ne ""){
				$wr->put( "WAFER_ID=".$wafer->name."\n");
			}
			else{
				$wr->put( "WAFER_ID=".$wafer_id."\n");
			}
			$wr->put( "WAFER_NUMBER=".sprintf("%02d",$wafer->number)."\n");
			$wr->put( "</WAFER>\n");

			if (@{$wafer->bins}){
				$wr->put( "<BIN>\n" . $self->binsToString($wafer->bins) . "</BIN>\n" );
			}
	  		if(defined $wafer->sbins ){
				if (@{$wafer->sbins}){
					$wr->put( "<SBIN>\n" . $self->binsToString($wafer->sbins) . "</SBIN>\n" );
				}
			}

			if(defined $wafer->hbins ){
				if (@{$wafer->hbins}){
				$wr->put( "<HBIN>\n" . $self->binsToString($wafer->hbins) . "</HBIN>\n" );
				}
			}

			if (@{$wafer->dies}){
				$wr->put( "<DATA>\n" . $self->diesToBinmap($wafer->dies). "</DATA>\n" );
			}
		}

=pod
	if (@{$model->sbins}){
        $wr->put( "<SBIN>\n" . $self->binsToString($model->sbins) . "</SBIN>\n" );
    }
	if (@{$model->hbins}){
        $wr->put( "<HBIN>\n" . $self->binsToString($model->hbins) . "</HBIN>\n" );
    }
=cut
	$wr->close;
	}
}


sub printParams {
	my $self =shift;
	my $wr = $self->writer;
	my $model = $self->model;
	my $outfilename = $wr->basename;
	my %group;
	foreach my $wafer (@{$model->wafers}){
		my $key = $wafer->START_TIME ;
		unless (exists $group{$key}) {
			$group{$key} = [];
		}
		push @{$group{$key}}, $wafer;
	}
	foreach my $wafers(values %group){
		my $firstWafer = $wafers->[0] ;
		if (defined $firstWafer->START_TIME && ($model->header->{START_TIME} eq "" || $model->header->{START_TIME} eq "N/A")){
			$model->header->START_TIME($firstWafer->START_TIME);
		}
		if (defined $firstWafer->END_TIME){
			$model->header->END_TIME($firstWafer->END_TIME);
		}
		if (defined $firstWafer->key)
		{
			print (" firstWafer key : ".$firstWafer->key."\n");
			$wr->basename($outfilename."_".$firstWafer->key) ;
		}
		elsif ($firstWafer->number + 0 > 0){
			$wr->basename($outfilename."_".sprintf("%02d",$firstWafer->number)) ;
		}
		$wr->open;
		$wr->put( "<METADATA>\n" . $self->metadataHeaderToString($model->header) ."</METADATA>\n" );
		if (defined $model->wmap){
			$wr->put( "<WMAP>\n" . $model->wmap->toString . "</WMAP>\n");
		}
		if (@{$model->tests}){
			$wr->put( "<PAR>\n" . $self->testsToString($model->tests)."</PAR>\n");
		}
		foreach my $wafer(@$wafers){
		    my $sl = uc($model->header->SOURCE_LOT);
			$sl =~ s/\.S$//g;			
			my $wafer_id = $sl."-".sprintf("%02d",$wafer->number);
			$wr->put( "<WAFER>\n");
			if($wafer->name ne ""){
			$wr->put( "WAFER_ID=".$wafer->name."\n");
			}
			else{
			$wr->put( "WAFER_ID=".$wafer_id."\n");
			}


			$wr->put( "WAFER_NUMBER=".sprintf("%02d",$wafer->number)."\n");
			$wr->put( "</WAFER>\n");

			if (@{$wafer->bins}){
				$wr->put( "<BIN>\n" . $self->binsToString($wafer->bins) . "</BIN>\n" );
			}

			if(defined $wafer->sbins ){
				if (@{$wafer->sbins}){
					$wr->put( "<SBIN>\n" . $self->binsToString($wafer->sbins) . "</SBIN>\n" );
				}
			}

			if(defined $wafer->hbins){
				if (@{$wafer->hbins}){
					$wr->put( "<HBIN>\n" . $self->binsToString($wafer->hbins) . "</HBIN>\n" );
				}
			}

			if(defined $model->sbins){
				if (@{$model->sbins}){
					$wr->put( "<SBIN>\n" . $self->binsToString($model->sbins) . "</SBIN>\n" );
				}
			}

			if(defined $model->hbins){
				if (@{$model->hbins}){
					$wr->put( "<HBIN>\n" . $self->binsToString($model->hbins) . "</HBIN>\n" );
				}
			}

			if(defined $wafer->rels ){
                                if (@{$wafer->rels}){
                                        $wr->put( "<REL>\n" . $self->relsToString($wafer->rels) . "</REL>\n" );
                                }
                        }
			if(defined $model->rels){
                                if (@{$model->rels}){
                                        $wr->put( "<REL>\n" . $self->relsToString($model->rels) . "</REL>\n" );
                                }
                        }

			if(defined $wafer->custindexes ){
				if (@{$wafer->custindexes}){
					$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($wafer->custindexes) . "</CUSTOM_INDEXES>\n" );
				}
			}
			if(defined $model->custindexes){
				if (@{$model->custindexes}){
					$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($model->custindexes) . "</CUSTOM_INDEXES>\n" );
				}
			}

			if (@{$wafer->tests}){
				$wr->put( "<PAR>\n" . $self->testsToString($wafer->tests)."</PAR>\n");
			}

			$wr->put( "<DATA>\n" . $self->diesToString($wafer->dies )."</DATA>\n");

			### wafer level
			my $generate_stat = 0;
			foreach my $die (@{$wafer->dies}){
	  			if(@{$die->min} > 0)
				{
					$generate_stat =1;
				}
			}

			if($generate_stat)
			{
				$wr->put( "<STAT>\n" . $self->statToString($wafer->dies ). "</STAT>\n");
			}

			#### lot level
			$generate_stat = 0;
			foreach my $die (@{$model->dies}){
				if(@{$die->min} > 0)
				{
					$generate_stat =1;
				}
			}

			if($generate_stat)
			{
				$wr->put( "<STAT>\n" . $self->statToString($model->dies ). "</STAT>\n");
			}

		}
		$wr->close;
	}
}

sub printPar{
	my $self =shift;
	my $wr = $self->writer;
	my $model = $self->model;
	my $outfilename = $wr->basename;
	my %group;
	foreach my $wafer (@{$model->wafers}){
		my $key = $wafer->START_TIME ;
		unless (exists $group{$key}) {
			$group{$key} = [];
		}
		push @{$group{$key}}, $wafer;
	}
	foreach my $wafers(values %group){
		my $firstWafer = $wafers->[0] ;
		if (defined $firstWafer->START_TIME){
			$model->header->START_TIME($firstWafer->START_TIME);
		}
		if (defined $firstWafer->END_TIME){
			$model->header->END_TIME($firstWafer->END_TIME);
		}
		if (defined $firstWafer->key)
		{
			print (" firstWafer key : ".$firstWafer->key."\n");
			$wr->basename($outfilename."_".$firstWafer->key) ;
		}
		elsif ($firstWafer->number + 0 > 0){
			$wr->basename($outfilename."_".sprintf("%02d",$firstWafer->number)) ;
		}
		$wr->open;
		$wr->put( "<HEADER>\n" . $self->headerToString_v2($model->header) ."</HEADER>\n" );
		if (defined $model->wmap){
			$wr->put( "<WMAP>\n" . $model->wmap->toString . "</WMAP>\n");
		}
		if (@{$model->tests}){
			$wr->put( "<PAR>\n" . $self->testsToString($model->tests)."</PAR>\n");
		}
		foreach my $wafer(@$wafers){
			my $wafer_id = uc($model->header->LOT)."_".sprintf("%02d",$wafer->number);
			$wr->put( "<WAFER>\n");
			if($wafer->name ne ""){
			$wr->put( "WAFER_ID=".$wafer->name."\n");
			}
			else{
			$wr->put( "WAFER_ID=".$wafer_id."\n");
			}

			$wr->put( "WAFER_NUMBER=".sprintf("%02d",$wafer->number)."\n");
			$wr->put( "</WAFER>\n");

			if (@{$wafer->bins}){
				$wr->put( "<BIN>\n" . $self->binsToString($wafer->bins) . "</BIN>\n" );
			}

			if(defined $wafer->sbins ){
				if (@{$wafer->sbins}){
					$wr->put( "<SBIN>\n" . $self->binsToString($wafer->sbins) . "</SBIN>\n" );
				}
			}

			if(defined $wafer->hbins){
				if (@{$wafer->hbins}){
					$wr->put( "<HBIN>\n" . $self->binsToString($wafer->hbins) . "</HBIN>\n" );
				}
			}

			if(defined $model->sbins){
				if (@{$model->sbins}){
					$wr->put( "<SBIN>\n" . $self->binsToString($model->sbins) . "</SBIN>\n" );
				}
			}

			if(defined $model->hbins){
				if (@{$model->hbins}){
					$wr->put( "<HBIN>\n" . $self->binsToString($model->hbins) . "</HBIN>\n" );
				}
			}

			if(defined $wafer->rels ){
                                if (@{$wafer->rels}){
                                        $wr->put( "<REL>\n" . $self->relsToString($wafer->rels) . "</REL>\n" );
                                }
                        }
			if(defined $model->rels){
                                if (@{$model->rels}){
                                        $wr->put( "<REL>\n" . $self->relsToString($model->rels) . "</REL>\n" );
                                }
                        }

			if(defined $wafer->custindexes ){
				if (@{$wafer->custindexes}){
					$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($wafer->custindexes) . "</CUSTOM_INDEXES>\n" );
				}
			}
			if(defined $model->custindexes){
				if (@{$model->custindexes}){
					$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($model->custindexes) . "</CUSTOM_INDEXES>\n" );
				}
			}

			if (@{$wafer->tests}){
				$wr->put( "<PAR>\n" . $self->testsToString($wafer->tests)."</PAR>\n");
			}

			$wr->put( "<DATA>\n" . $self->diesToString($wafer->dies )."</DATA>\n");

			### wafer level
			my $generate_stat = 0;
			foreach my $die (@{$wafer->dies}){
	  			if(@{$die->min} > 0)
				{
					$generate_stat =1;
				}
			}

			if($generate_stat)
			{
				$wr->put( "<STAT>\n" . $self->statToString($wafer->dies ). "</STAT>\n");
			}

			#### lot level
			$generate_stat = 0;
			foreach my $die (@{$model->dies}){
				if(@{$die->min} > 0)
				{
					$generate_stat =1;
				}
			}

			if($generate_stat)
			{
				$wr->put( "<STAT>\n" . $self->statToString($model->dies ). "</STAT>\n");
			}

		}

=pod
	if(defined $model->sbins){
		if (@{$model->sbins}){
			$wr->put( "<SBIN>\n" . $self->binsToString($model->sbins) . "</SBIN>\n" );
		}
	}

	if(defined $model->hbins){
		if (@{$model->hbins}){
			$wr->put( "<HBIN>\n" . $self->binsToString($model->hbins) . "</HBIN>\n" );
		}
	}
=cut


    $wr->close;
	}
}

sub printPar_v2{
	my $self =shift;
	my $wr = $self->writer;
	my $model = $self->model;
	my $outfilename = $wr->basename;
	my %group;
	foreach my $wafer (@{$model->wafers}){
		# Unique wafer start time produces multipe iff/wafid but have exceptions depending on datalog
		my $key = $wafer;
		unless (exists $group{$key}) {
			$group{$key} = [];
		}
		push @{$group{$key}}, $wafer;

	}
	foreach my $wafers(values %group){
		my $firstWafer = $wafers->[0] ;
		if (defined $firstWafer->START_TIME){
			$model->header->START_TIME($firstWafer->START_TIME);
		}
		if (defined $firstWafer->END_TIME){
			$model->header->END_TIME($firstWafer->END_TIME);
		}
		if (defined $firstWafer->key)
		{
			print (" firstWafer key : ".$firstWafer->key."\n");
			$wr->basename($outfilename."_".$firstWafer->key) ;
		}
		elsif ($firstWafer->number + 0 > 0){
			$wr->basename($outfilename."_".sprintf("%02d",$firstWafer->number)) ;
		}
		$wr->open;
		$wr->put( "<HEADER>\n" . $self->headerToString_v2($model->header) ."</HEADER>\n" );
		if (defined $model->wmap){
			$wr->put( "<WMAP>\n" . $model->wmap->toString . "</WMAP>\n");
		}
		if (@{$model->tests}){
			$wr->put( "<PAR>\n" . $self->testsToString($model->tests)."</PAR>\n");
		}
		foreach my $wafer(@$wafers){
			my $wafer_id = uc($model->header->LOT)."_".sprintf("%02d",$wafer->number);
			$wr->put( "<WAFER>\n");
			if($wafer->name ne ""){
				$wr->put( "WAFER_ID=".$wafer->name."\n");
			}
			else{
				$wr->put( "WAFER_ID=".$wafer_id."\n");
			}

			$wr->put( "WAFER_NUMBER=".sprintf("%02d",$wafer->number)."\n");
			$wr->put( "</WAFER>\n");

			if (@{$wafer->bins}){
				$wr->put( "<BIN>\n" . $self->binsToString($wafer->bins) . "</BIN>\n" );
			}

			if(defined $wafer->sbins ){
				if (@{$wafer->sbins}){
					$wr->put( "<SBIN>\n" . $self->binsToString($wafer->sbins) . "</SBIN>\n" );
				}
			}

			if(defined $wafer->hbins){
				if (@{$wafer->hbins}){
					$wr->put( "<HBIN>\n" . $self->binsToString($wafer->hbins) . "</HBIN>\n" );
				}
			}

			if(defined $model->sbins){
				if (@{$model->sbins}){
					$wr->put( "<SBIN>\n" . $self->binsToString($model->sbins) . "</SBIN>\n" );
				}
			}

			if(defined $model->hbins){
				if (@{$model->hbins}){
					$wr->put( "<HBIN>\n" . $self->binsToString($model->hbins) . "</HBIN>\n" );
				}
			}

			if(defined $wafer->rels ){
                                if (@{$wafer->rels}){
                                        $wr->put( "<REL>\n" . $self->relsToString($wafer->rels) . "</REL>\n" );
                                }
                        }
                        if(defined $model->rels){
                                if (@{$model->rels}){
                                        $wr->put( "<REL>\n" . $self->relsToString($model->rels) . "</REL>\n" );
                                }
                        }

			if(defined $wafer->custindexes ){
				if (@{$wafer->custindexes}){
					$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($wafer->custindexes) . "</CUSTOM_INDEXES>\n" );
				}
			}
			if(defined $model->custindexes){
				if (@{$model->custindexes}){
					$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($model->custindexes) . "</CUSTOM_INDEXES>\n" );
				}
			}

			if (@{$wafer->tests}){
				$wr->put( "<PAR>\n" . $self->testsToString($wafer->tests)."</PAR>\n");
			}
			$wr->put( "<DATA>\n" . $self->diesToString($wafer->dies )."</DATA>\n");

			### wafer level
			my $generate_stat = 0;
			foreach my $die (@{$wafer->dies}){
				if(@{$die->min} > 0)
				{
					$generate_stat =1;
				}
			}

			if($generate_stat)
			{
				$wr->put( "<STAT>\n" . $self->statToString($wafer->dies ). "</STAT>\n");
			}

	  		#### lot level
			$generate_stat = 0;
			foreach my $die (@{$model->dies}){
				if(@{$die->min} > 0)
				{
					$generate_stat =1;
				}
			}

			if($generate_stat)
			{
				$wr->put( "<STAT>\n" . $self->statToString($model->dies ). "</STAT>\n");
			}
		}
=pod
	if(defined $model->sbins){
		if (@{$model->sbins}){
			$wr->put( "<SBIN>\n" . $self->binsToString($model->sbins) . "</SBIN>\n" );
		}
	}

	if(defined $model->hbins){
		if (@{$model->hbins}){
			$wr->put( "<HBIN>\n" . $self->binsToString($model->hbins) . "</HBIN>\n" );
		}
	}
=cut
    $wr->close;
	}
}

sub printPar_v3{
	my $self = shift;
	my $lot = shift;
	my $wr = $self->writer;
	my $model = $self->model;
	my $outfilename = $wr->basename;
	   #$outfilename =~ s/\_\D.*+$// if $model->header->EQUIP6_ID =~ /CREE_US/i;

	$wr->basename($outfilename."_".$lot);
	$wr->open;
	$wr->put( "<HEADER>\n" . $self->headerToString_v2($model->header) ."</HEADER>\n" );

	if (defined $model->wmap){
		$wr->put( "<WMAP>\n" . $model->wmap->toString . "</WMAP>\n");
	}
	if (@{$model->tests}){
		$wr->put( "<PAR>\n" . $self->testsToString($model->tests)."</PAR>\n");
	}

	foreach my $wafer(@{$model->wafers}){
		my $wafer_id = uc($model->header->LOT)."_".sprintf("%02d",$wafer->number);
		$wr->put( "<WAFER>\n");
		if($wafer->name ne ""){
			$wr->put( "WAFER_ID=".$wafer->name."\n");
		}
		else{
			$wr->put( "WAFER_ID=".$wafer_id."\n");
		}
		$wr->put( "WAFER_NUMBER=".sprintf("%02d",$wafer->number)."\n");
		$wr->put( "</WAFER>\n");

		if (@{$wafer->bins}){
			$wr->put( "<BIN>\n" . $self->binsToString($wafer->bins) . "</BIN>\n" );
		}
		if(defined $wafer->sbins ){
			if (@{$wafer->sbins}){
				$wr->put( "<SBIN>\n" . $self->binsToString($wafer->sbins) . "</SBIN>\n" );
			}
		}
		if(defined $wafer->hbins){
			if (@{$wafer->hbins}){
				$wr->put( "<HBIN>\n" . $self->binsToString($wafer->hbins) . "</HBIN>\n" );
			}
		}
		if(defined $model->sbins){
			if (@{$model->sbins}){
				$wr->put( "<SBIN>\n" . $self->binsToString($model->sbins) . "</SBIN>\n" );
			}
		}
		if(defined $model->hbins){
			if (@{$model->hbins}){
				$wr->put( "<HBIN>\n" . $self->binsToString($model->hbins) . "</HBIN>\n" );
			}
		}

		if(defined $wafer->rels ){
                	if (@{$wafer->rels}){
                        	$wr->put( "<REL>\n" . $self->relsToString($wafer->rels) . "</REL>\n" );
                        }
                }
                if(defined $model->rels){
                	if (@{$model->rels}){
                        	$wr->put( "<REL>\n" . $self->relsToString($model->rels) . "</REL>\n" );
                        }
                }

		if(defined $wafer->custindexes ){
			if (@{$wafer->custindexes}){
				$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($wafer->custindexes) . "</CUSTOM_INDEXES>\n" );
			}
		}
		if(defined $model->custindexes){
			if (@{$model->custindexes}){
				$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($model->custindexes) . "</CUSTOM_INDEXES>\n" );
			}
		}

		if (@{$wafer->tests}){
			$wr->put( "<PAR>\n" . $self->testsToString($wafer->tests)."</PAR>\n");
		}

		$wr->put( "<DATA>\n" . $self->diesToString($wafer->dies )."</DATA>\n");

		### wafer level
		my $generate_stat = 0;
		foreach my $die (@{$wafer->dies}){
			if(@{$die->min} > 0)
			{
				$generate_stat =1;
			}
		}

		if($generate_stat){
			$wr->put( "<STAT>\n" . $self->statToString($wafer->dies ). "</STAT>\n");
		}
		#### lot level
		$generate_stat = 0;
		foreach my $die (@{$model->dies}){
			if(@{$die->min} > 0){
				$generate_stat =1;
			}
		}
		if($generate_stat){
			$wr->put( "<STAT>\n" . $self->statToString($model->dies ). "</STAT>\n");
		}

	}
	$wr->close;
}

sub printPar_v4{
	my $self =shift;
	my $wr = $self->writer;
	my $model = $self->model;
	my $outfilename = $wr->basename;
	my %group;
	foreach my $wafer (@{$model->wafers}){
		my $key = $wafer->START_TIME ;
		unless (exists $group{$key}) {
			$group{$key} = [];
		}
		push @{$group{$key}}, $wafer;
	}
	foreach my $wafers(values %group){
		my $firstWafer = $wafers->[0] ;
		if (defined $firstWafer->START_TIME){
			$model->header->START_TIME($firstWafer->START_TIME);
		}
		if (defined $firstWafer->END_TIME){
			$model->header->END_TIME($firstWafer->END_TIME);
		}
		if (defined $firstWafer->key)
		{
			print (" firstWafer key : ".$firstWafer->key."\n");
			$wr->basename($outfilename."_".$firstWafer->key) ;
		}
		#elsif ($firstWafer->number + 0 > 0){
		#	$wr->basename($outfilename."_".sprintf("%02d",$firstWafer->number)) ;
		#}
		elsif (defined $firstWafer->name) {
			$wr->basename($outfilename."_".$firstWafer->name);
		}
		$wr->open;
		$wr->put( "<HEADER>\n" . $self->headerToString_v2($model->header) ."</HEADER>\n" );
		if (defined $model->wmap){
			$wr->put( "<WMAP>\n" . $model->wmap->toString . "</WMAP>\n");
		}
		if (@{$model->tests}){
			$wr->put( "<PAR>\n" . $self->testsToString($model->tests)."</PAR>\n");
		}
		foreach my $wafer(@$wafers){
			my $wafer_id = uc($model->header->LOT)."_".$wafer->name;
			$wr->put( "<WAFER>\n");
			if($wafer->name ne ""){
				#$wr->put( "WAFER_ID=".$wafer->name."\n");
				$wr->put( "WAFER_ID=".$wafer_id."\n");
			}
			else{
				$wr->put( "WAFER_ID=".$wafer_id."\n");
			}

			$wr->put( "WAFER_NUMBER=".sprintf("%02d",$wafer->number)."\n");
			$wr->put( "</WAFER>\n");

			if (@{$wafer->bins}){
				$wr->put( "<BIN>\n" . $self->binsToString($wafer->bins) . "</BIN>\n" );
			}

			if(defined $wafer->sbins ){
				if (@{$wafer->sbins}){
					$wr->put( "<SBIN>\n" . $self->binsToString($wafer->sbins) . "</SBIN>\n" );
				}
			}

			if(defined $wafer->hbins){
				if (@{$wafer->hbins}){
					$wr->put( "<HBIN>\n" . $self->binsToString($wafer->hbins) . "</HBIN>\n" );
				}
			}

			if(defined $model->sbins){
				if (@{$model->sbins}){
					$wr->put( "<SBIN>\n" . $self->binsToString($model->sbins) . "</SBIN>\n" );
				}
			}

			if(defined $model->hbins){
				if (@{$model->hbins}){
					$wr->put( "<HBIN>\n" . $self->binsToString($model->hbins) . "</HBIN>\n" );
				}
			}

			if(defined $wafer->rels ){
                                if (@{$wafer->rels}){
                                        $wr->put( "<REL>\n" . $self->relsToString($wafer->rels) . "</REL>\n" );
                                }
                        }
			if(defined $model->rels){
                                if (@{$model->rels}){
                                        $wr->put( "<REL>\n" . $self->relsToString($model->rels) . "</REL>\n" );
                                }
                        }

			if(defined $wafer->custindexes ){
				if (@{$wafer->custindexes}){
					$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($wafer->custindexes) . "</CUSTOM_INDEXES>\n" );
				}
			}
			if(defined $model->custindexes){
				if (@{$model->custindexes}){
					$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($model->custindexes). "</CUSTOM_INDEXES>\n" );
				}
			}

			if (@{$wafer->tests}){
				$wr->put( "<PAR>\n" . $self->testsToString($wafer->tests)."</PAR>\n");
			}

			$wr->put( "<DATA>\n" . $self->diesToString($wafer->dies )."</DATA>\n");

			### wafer level
			my $generate_stat = 0;
			foreach my $die (@{$wafer->dies}){
	  			if(@{$die->min} > 0)
				{
					$generate_stat =1;
				}
			}

			if($generate_stat)
			{
				$wr->put( "<STAT>\n" . $self->statToString($wafer->dies ). "</STAT>\n");
			}

			#### lot level
			$generate_stat = 0;
			foreach my $die (@{$model->dies}){
				if(@{$die->min} > 0)
				{
					$generate_stat =1;
				}
			}

			if($generate_stat)
			{
				$wr->put( "<STAT>\n" . $self->statToString($model->dies ). "</STAT>\n");
			}

		}

    	$wr->close;
	}
}

sub printPar_v5{
	my $self =shift;
	my $wr = $self->writer;
	my $model = $self->model;
	my $outfilename = $wr->basename;
	my %group;
	foreach my $wafer (@{$model->wafers}){
		# Unique wafer start time produces multipe iff/wafid but have exceptions depending on datalog
		my $key = $wafer;
		unless (exists $group{$key}) {
			$group{$key} = [];
		}
		push @{$group{$key}}, $wafer;

	}
	foreach my $wafers(values %group){
		my $firstWafer = $wafers->[0] ;
		if (defined $firstWafer->START_TIME){
			$model->header->START_TIME($firstWafer->START_TIME);
		}
		if (defined $firstWafer->END_TIME){
			$model->header->END_TIME($firstWafer->END_TIME);
		}
		if (defined $firstWafer->key)
		{
			print (" firstWafer key : ".$firstWafer->key."\n");
			$wr->basename($outfilename."_".$firstWafer->key) ;
		}
		#elsif ($firstWafer->number + 0 > 0){
		#	$wr->basename($outfilename."_".sprintf("%02d",$firstWafer->number)) ;
		#}
		elsif (defined $firstWafer->name) {
			$wr->basename($outfilename."_".$firstWafer->name);
		}
		$wr->open;
		$wr->put( "<HEADER>\n" . $self->headerToString_v2($model->header) ."</HEADER>\n" );
		if (defined $model->wmap){
			$wr->put( "<WMAP>\n" . $model->wmap->toString . "</WMAP>\n");
		}
		if (@{$model->tests}){
			$wr->put( "<PAR>\n" . $self->testsToString($model->tests)."</PAR>\n");
		}
		foreach my $wafer(@$wafers){
			my $wafer_id = uc($model->header->LOT)."_".sprintf("%02d",$wafer->number);
			$wr->put( "<WAFER>\n");
			if($wafer->name ne ""){
				$wr->put( "WAFER_ID=".$wafer->name."\n");
			}
			else{
				$wr->put( "WAFER_ID=".$wafer_id."\n");
			}

			$wr->put( "WAFER_NUMBER=".sprintf("%02d",$wafer->number)."\n");
			$wr->put( "</WAFER>\n");

			if (@{$wafer->bins}){
				$wr->put( "<BIN>\n" . $self->binsToString($wafer->bins) . "</BIN>\n" );
			}

			if(defined $wafer->sbins ){
				if (@{$wafer->sbins}){
					$wr->put( "<SBIN>\n" . $self->binsToString($wafer->sbins) . "</SBIN>\n" );
				}
			}

			if(defined $wafer->hbins){
				if (@{$wafer->hbins}){
					$wr->put( "<HBIN>\n" . $self->binsToString($wafer->hbins) . "</HBIN>\n" );
				}
			}

			if(defined $model->sbins){
				if (@{$model->sbins}){
					$wr->put( "<SBIN>\n" . $self->binsToString($model->sbins) . "</SBIN>\n" );
				}
			}

			if(defined $model->hbins){
				if (@{$model->hbins}){
					$wr->put( "<HBIN>\n" . $self->binsToString($model->hbins) . "</HBIN>\n" );
				}
			}

			if(defined $wafer->rels ){
                                if (@{$wafer->rels}){
                                        $wr->put( "<REL>\n" . $self->relsToString($wafer->rels) . "</REL>\n" );
                                }
                        }
                        if(defined $model->rels){
                                if (@{$model->rels}){
                                        $wr->put( "<REL>\n" . $self->relsToString($model->rels) . "</REL>\n" );
                                }
                        }

			if(defined $wafer->custindexes ){
				if (@{$wafer->custindexes}){
					$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($wafer->custindexes) . "</CUSTOM_INDEXES>\n" );
				}
			}
			if(defined $model->custindexes){
				if (@{$model->custindexes}){
					$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($model->custindexes) . "</CUSTOM_INDEXES>\n" );
				}
			}

			if (@{$wafer->tests}){
				$wr->put( "<PAR>\n" . $self->testsToString($wafer->tests)."</PAR>\n");
			}
			$wr->put( "<DATA>\n" . $self->diesToString($wafer->dies )."</DATA>\n");

			### wafer level
			my $generate_stat = 0;
			foreach my $die (@{$wafer->dies}){
				if(@{$die->min} > 0)
				{
					$generate_stat =1;
				}
			}

			if($generate_stat)
			{
				$wr->put( "<STAT>\n" . $self->statToString($wafer->dies ). "</STAT>\n");
			}

	  		#### lot level
			$generate_stat = 0;
			foreach my $die (@{$model->dies}){
				if(@{$die->min} > 0)
				{
					$generate_stat =1;
				}
			}

			if($generate_stat)
			{
				$wr->put( "<STAT>\n" . $self->statToString($model->dies ). "</STAT>\n");
			}
		}
=pod
	if(defined $model->sbins){
		if (@{$model->sbins}){
			$wr->put( "<SBIN>\n" . $self->binsToString($model->sbins) . "</SBIN>\n" );
		}
	}

	if(defined $model->hbins){
		if (@{$model->hbins}){
			$wr->put( "<HBIN>\n" . $self->binsToString($model->hbins) . "</HBIN>\n" );
		}
	}
=cut
    $wr->close;
	}
}

sub printPar_v6{
	my $self = shift;
	my $wafn = shift;
	my $wr = $self->writer;
	my $model = $self->model;
	my $outfilename = $wr->basename;
	   #$outfilename =~ s/\_\D.*+$// if $model->header->EQUIP6_ID =~ /CREE_US/i;

	$wr->basename($outfilename."_".$wafn);
	$wr->open;
	$wr->put( "<HEADER>\n" . $self->headerToString_v2($model->header) ."</HEADER>\n" );

	if (defined $model->wmap){
		$wr->put( "<WMAP>\n" . $model->wmap->toString . "</WMAP>\n");
	}
	if (@{$model->tests}){
		$wr->put( "<PAR>\n" . $self->testsToString($model->tests)."</PAR>\n");
	}

	foreach my $wafer(@{$model->wafers}){
		my $wafer_id = uc($model->header->LOT)."_".sprintf("%02d",$wafer->number);
		$wr->put( "<WAFER>\n");
		if($wafer->name ne ""){
			$wr->put( "WAFER_ID=".$wafer->name."\n");
		}
		else{
			$wr->put( "WAFER_ID=".$wafer_id."\n");
		}
		$wr->put( "WAFER_NUMBER=".sprintf("%02d",$wafer->number)."\n");
		$wr->put( "</WAFER>\n");

		if (@{$wafer->bins}){
			$wr->put( "<BIN>\n" . $self->binsToString($wafer->bins) . "</BIN>\n" );
		}
		if(defined $wafer->sbins ){
			if (@{$wafer->sbins}){
				$wr->put( "<SBIN>\n" . $self->binsToString($wafer->sbins) . "</SBIN>\n" );
			}
		}
		if(defined $wafer->hbins){
			if (@{$wafer->hbins}){
				$wr->put( "<HBIN>\n" . $self->binsToString($wafer->hbins) . "</HBIN>\n" );
			}
		}
		if(defined $model->sbins){
			if (@{$model->sbins}){
				$wr->put( "<SBIN>\n" . $self->binsToString($model->sbins) . "</SBIN>\n" );
			}
		}
		if(defined $model->hbins){
			if (@{$model->hbins}){
				$wr->put( "<HBIN>\n" . $self->binsToString($model->hbins) . "</HBIN>\n" );
			}
		}

		if(defined $wafer->rels ){
                	if (@{$wafer->rels}){
                        	$wr->put( "<REL>\n" . $self->relsToString($wafer->rels) . "</REL>\n" );
                        }
                }
                if(defined $model->rels){
                	if (@{$model->rels}){
                        	$wr->put( "<REL>\n" . $self->relsToString($model->rels) . "</REL>\n" );
                        }
                }

		if(defined $wafer->custindexes ){
			if (@{$wafer->custindexes}){
				$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($wafer->custindexes) . "</CUSTOM_INDEXES>\n" );
			}
		}
		if(defined $model->custindexes){
			if (@{$model->custindexes}){
				$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($model->custindexes) . "</CUSTOM_INDEXES>\n" );
			}
		}

		if (@{$wafer->tests}){
			$wr->put( "<PAR>\n" . $self->testsToString($wafer->tests)."</PAR>\n");
		}

		#$wr->put( "<DATA>\n" . $self->diesToString($wafer->dies )."</DATA>\n");

		### wafer level
		my $generate_stat = 0;
		foreach my $die (@{$wafer->dies}){
			if(@{$die->min} > 0)
			{
				$generate_stat =1;
			}
		}

		if($generate_stat){
			$wr->put( "<STAT>\n" . $self->statToString_v2($wafer->dies ). "</STAT>\n");
		}
		#### lot level
		$generate_stat = 0;
		foreach my $die (@{$model->dies}){
			if(@{$die->min} > 0){
				$generate_stat =1;
			}
		}
		if($generate_stat){
			$wr->put( "<STAT>\n" . $self->statToString_v2($model->dies ). "</STAT>\n");
		}

	}
	$wr->close;
}

sub printPar_v7{
	my $self = shift;
	my $wafn = shift;
	my $wr = $self->writer;
	my $model = $self->model;
	my $outfilename = $wr->basename;
	   #$outfilename =~ s/\_\D.*+$// if $model->header->EQUIP6_ID =~ /CREE_US/i;

	$wr->basename($outfilename."_".$wafn);
	$wr->open;
	$wr->put( "<HEADER>\n" . $self->headerToString_v2($model->header) ."</HEADER>\n" );

	if (defined $model->wmap){
		$wr->put( "<WMAP>\n" . $model->wmap->toString . "</WMAP>\n");
	}
	if (@{$model->tests}){
		$wr->put( "<PAR>\n" . $self->testsToString($model->tests)."</PAR>\n");
	}

	foreach my $wafer(@{$model->wafers}){
		my $wafer_id = uc($model->header->LOT)."_".sprintf("%02d",$wafer->number);
		$wr->put( "<WAFER>\n");
		if($wafer->name ne ""){
			$wr->put( "WAFER_ID=".$wafer->name."\n");
		}
		else{
			$wr->put( "WAFER_ID=".$wafer_id."\n");
		}
		$wr->put( "WAFER_NUMBER=".sprintf("%02d",$wafer->number)."\n");
		$wr->put( "</WAFER>\n");

		if (@{$wafer->bins}){
			$wr->put( "<BIN>\n" . $self->binsToString($wafer->bins) . "</BIN>\n" );
		}
		if(defined $wafer->sbins ){
			if (@{$wafer->sbins}){
				$wr->put( "<SBIN>\n" . $self->binsToString($wafer->sbins) . "</SBIN>\n" );
			}
		}
		if(defined $wafer->hbins){
			if (@{$wafer->hbins}){
				$wr->put( "<HBIN>\n" . $self->binsToString($wafer->hbins) . "</HBIN>\n" );
			}
		}
		if(defined $model->sbins){
			if (@{$model->sbins}){
				$wr->put( "<SBIN>\n" . $self->binsToString($model->sbins) . "</SBIN>\n" );
			}
		}
		if(defined $model->hbins){
			if (@{$model->hbins}){
				$wr->put( "<HBIN>\n" . $self->binsToString($model->hbins) . "</HBIN>\n" );
			}
		}

		if(defined $wafer->rels ){
                	if (@{$wafer->rels}){
                        	$wr->put( "<REL>\n" . $self->relsToString($wafer->rels) . "</REL>\n" );
                        }
                }
                if(defined $model->rels){
                	if (@{$model->rels}){
                        	$wr->put( "<REL>\n" . $self->relsToString($model->rels) . "</REL>\n" );
                        }
                }

		if(defined $wafer->custindexes ){
			if (@{$wafer->custindexes}){
				$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($wafer->custindexes) . "</CUSTOM_INDEXES>\n" );
			}
		}
		if(defined $model->custindexes){
			if (@{$model->custindexes}){
				$wr->put( "<CUSTOM_INDEXES>\n" . $self->custindexesToString($model->custindexes) . "</CUSTOM_INDEXES>\n" );
			}
		}

		if (@{$wafer->tests}){
			$wr->put( "<PAR>\n" . $self->testsToString($wafer->tests)."</PAR>\n");
		}

		#$wr->put( "<DATA>\n" . $self->diesToString($wafer->dies )."</DATA>\n");

		### wafer level
		my $generate_stat = 0;
		foreach my $die (@{$wafer->dies}){
			if(@{$die->min} > 0)
			{
				$generate_stat =1;
			}
		}

		if($generate_stat){
			$wr->put( "<STAT>\n" . $self->statToString_v3($wafer->dies ). "</STAT>\n");
		}
		#### lot level
		$generate_stat = 0;
		foreach my $die (@{$model->dies}){
			if(@{$die->min} > 0){
				$generate_stat =1;
			}
		}
		if($generate_stat){
			$wr->put( "<STAT>\n" . $self->statToString_v3($model->dies ). "</STAT>\n");
		}

	}
	$wr->close;
}

sub printLimit{
	my $self =shift;
	my $wr = $self->writer;
	my $limit = $self->model->limit;
	my $outfile = $limit->limit_file;
    	$wr->basename($outfile);
    	$wr->ext('limit');
    	# Set noWMap to 0 to ensure no changes to extension
    	$wr->noWMap(0);
    	$wr->open;
    	$wr->put( "<HEADER>\n" . $limit->toString . "</HEADER>\n" );
    	$wr->put(
    	"<LIMIT>\n" . $self->limitToString . "</LIMIT>\n" );
	if ( @{ $limit->conditionNames } ) {
		$wr->put("<CONDITION>\n");
		$wr->put( join( ",", @{ $limit->conditionNames } ) . "\n" );
		$wr->put( $self->limitToStringWithConditions );
     	   	$wr->put("</CONDITION>\n");
    	}
   	$wr->close;
}

sub binsToString{
	my $self= shift;
	my $bins = shift;
	my @string;
	foreach my $bin (@$bins){
		# Rodney wants to see sbin that hs '0'
		#next if ($bin->count ==0);
		my @line;
		push @line,$bin->number if (grep {$_ eq 'number'} @{$self->binItems});
		if (grep {$_ eq 'name'} @{$self->binItems}){
			if ($bin->name eq '') {
				push @line, "BIN_".sprintf("%02d",$bin->number);
			} else {
				push @line, trim($bin->name);
			}
		}
		push @line, repNA($bin->PF) if (grep {$_ eq 'PF'} @{$self->binItems});
		push @line, repNA($bin->count) if (grep {$_ eq 'count'} @{$self->binItems});;
		my $str = join (",",@line);
		push @string, $str;
	}
	return join("\n",@string)."\n";
}

sub metadataHeaderToString{
	my $self= shift;
	my $model = $self->model;
	my $header = $model->header;
	my $dataSource = $model->dataSource;
	my $string  ;
	foreach my $key ($header->list){
		my $value = $header->{$key};
		if ($key =~ /LOT|LOT_ID/){
			$value = uc($value);
		}
		$value = repNA($value);
		$string .=  "$key=$value\n";

	}
	return $string;
}

sub headerToString{
	my $self= shift;
	my $model = $self->model;
	my $header = $model->header;
	my $dataSource = $model->dataSource;
	my $string  ;
	foreach my $key ($header->list){
		my $value = $header->{$key};
		if ($key eq 'PROGRAM'){
			$value = $value."_".$header->{PRODUCT}."_".$dataSource;
		}
		$value = repNA($value);
		$string .=  "$key=$value\n";
	}
	return $string;
}

sub headerToString_v2{
	my $self= shift;
	my $model = $self->model;
	my $header = $model->header;
	my $dataSource = $model->dataSource;
	my $string  ;
	foreach my $key ($header->list){
		my $value = $header->{$key};
		if ($key eq 'LOT'){
			$value = uc($value);
		}
		$value = repNA($value);
		$string .=  "$key=$value\n";

	}
	return $string;
}

sub testsToString{
	my $self = shift;
	my $tests = shift;
	my @string  ;
	foreach my $test (@$tests){
		my @line;
		foreach my $item (@{$self->testItems}){
			push @line, repNA($test->{$item});
		}
		my $str = join (",",@line);
		push @string, $str;
	}
	return join("\n",@string)."\n";
}

sub diesToString{
	my $self= shift;
	my $dies = shift;
	my @string ;
	foreach my $die (@$dies){
		next if ($die->inked or $die->notest);
		my $counter = 0;
		my @line;
		push @line,"DIE_X=".repNA($die->x) if (grep {$_ eq 'x'} @{$self->dataItems});
		push @line,"DIE_Y=".repNA($die->y) if (grep {$_ eq 'y'} @{$self->dataItems});
		push @line,"ORG_X=".repNA($die->org_x) if (grep {$_ eq 'org_x'} @{$self->dataItems});
                push @line,"ORG_Y=".repNA($die->org_y) if (grep {$_ eq 'org_y'} @{$self->dataItems});
		push @line,"SITE=".repNA($die->site) if (grep {$_ eq 'site'} @{$self->dataItems}) ;
		push @line,"PARTID=".repNA($die->partid) if (grep {$_ eq 'partid'} @{$self->dataItems}) ;
		push @line,"TOUCHDOWN_NUM=".repNA($die->touchdown_num) if (grep {$_ eq 'touchdown_num'} @{$self->dataItems}) ;
		push @line,"ECID=".repNA($die->ecid) if (grep {$_ eq 'ecid'} @{$self->dataItems}) ;
		push @line,"HARD_BIN=".repNA($die->hard_bin) if (grep {$_ eq 'hard_bin'} @{$self->dataItems});
		push @line,"SOFT_BIN=".repNA($die->soft_bin) if (grep {$_ eq 'soft_bin'} @{$self->dataItems});
##<<<<<<< HEAD
##=======
		push @line,"READTIME=".repNA($die->readtime) if (grep {$_ eq 'readtime'} @{$self->dataItems}) ;
		push @line,"RUNTIME=".repNA($die->runtime) if (grep {$_ eq 'runtime'} @{$self->dataItems}) ;
		push @line,"BINDESC=".repNA($die->bindesc) if (grep {$_ eq 'bindesc'} @{$self->dataItems}) ;
		push @line,"TESTTIME=".repNA($die->testtime) if (grep {$_ eq 'testtime'} @{$self->dataItems}) ;

#>>>>>>> 0af60b8432d9d46821e0f93ee6ebf30eb5bde49d

		####
		#normalize the die result#

		#print "@{$die->result}\n";
		foreach my $multiplier(@multipliers) {
        		#print">>>$die->result[$counter]<<<<\n";
        		trim($die->result->[$counter]);
 	        	if ($die->result->[$counter] ne "N/A" && looks_like_number($die->result->[$counter]) ) {
            			$die->result->[$counter] *= $multiplier;
            		}
            		$counter++;
		}
		#end of the code for normalizing the die/test result#

		push @line, join(",",@{$die->result});
		my $str = join ("\n",@line);
		push @string, $str;
	}
	return join("\n",@string)."\n";
}


sub statToString{
	my $self= shift;
	my $dies = shift;
	my @string ;
	foreach my $die (@$dies){
		next if ($die->inked or $die->notest);
		my $counter = 0;
		my @line;

		#end of the code for normalizing the die/test result#
		my @wk = @{$die->level};
		push @line, "level:".$wk[0];

		my $min = "min:". join(",",@{$die->min});
		push @line, $min;

		my $max = "max:".join(",",@{$die->max});
		push @line, $max;

		my $mean = "avg:".join(",",@{$die->mean});
		push @line, $mean;

		my $sdev = "std:".join(",",@{$die->sdev});
		push @line, $sdev;

		my $sums = "sum:".join(",",@{$die->sums});
		push @line, $sums;

		my $sqrs = "ss:". join(",",@{$die->sqrs});
		push @line,$sqrs;

		my $cnt = "cnt:". join(",",@{$die->cnt});
		push @line,$cnt;

		my $str = join ("\n",@line);
	    	push @string, $str;
	}
	return join("\n",@string)."\n";
}

sub statToString_v2{
        my $self= shift;
        my $dies = shift;
        my @string ;
        foreach my $die (@$dies){
                next if ($die->inked or $die->notest);
                my $counter = 0;
                my @line;

                #end of the code for normalizing the die/test result#
                my @wk = @{$die->level};
                push @line, "level:".$wk[0];

                my $min = "min:". join(",",@{$die->min});
                push @line, $min;

                my $max = "max:".join(",",@{$die->max});
                push @line, $max;

                my $mean = "avg:".join(",",@{$die->mean});
                push @line, $mean;

                my $sdev = "std:".join(",",@{$die->sdev});
                push @line, $sdev;

		#my $qty = "qty:".join(",",@{$die->qty});
		#push @line, $qty;

                my $cpk = "cpk:". join(",",@{$die->cpk});
                push @line, $cpk;

		my $result = "pass_fail:".join(",",@{$die->pass_fail});
		push @line, $result;

                my $str = join ("\n",@line);
                push @string, $str;
        }
        return join("\n",@string)."\n";
}

sub statToString_v3{
        my $self= shift;
        my $dies = shift;
        my @string ;
        foreach my $die (@$dies){
                next if ($die->inked or $die->notest);
                my $counter = 0;
                my @line;

                #end of the code for normalizing the die/test result#
                my @wk = @{$die->level};
                push @line, "level:".$wk[0];

                my $min = "min:". join(",",@{$die->min});
                push @line, $min;

                my $max = "max:".join(",",@{$die->max});
                push @line, $max;

                my $mean = "avg:".join(",",@{$die->mean});
                push @line, $mean;

                my $sdev = "std:".join(",",@{$die->sdev});
                push @line, $sdev;	
               
                my $str = join ("\n",@line);
                push @string, $str;
        }
        return join("\n",@string)."\n";
}

sub diesToBinmap{
	my $self= shift;
	my $dies = shift;
	my @string;
	foreach my $die (@$dies){
		next if ($die->inked or $die->notest);
		my @line;
		foreach my $attr (@{$self->dataItems}){
			push @line, repNA($die->{$attr});
		}
		push @string, join(",",@line);
	}
	return join("\n",@string)."\n";
}

sub limitToString{
    my $self  = shift;
    my $limit = $self->model->limit;
    my $tests = $limit->tests;
    my @string;
    foreach my $test (@$tests) {
        my @line;
        foreach my $item ( @{ $limit->testItems } ) {
            push @line, repNA( $test->{$item} );
        }
        push @line, repNA( $test->LPL );
        push @line, repNA( $test->HPL );
        push @line, repNA( $test->LSL );
        push @line, repNA( $test->HSL );
        push @line, repNA( $test->LOL );
        push @line, repNA( $test->HOL );
        push @line, repNA( $test->LWL );
        push @line, repNA( $test->HWL );
        my $str = join( ",", @line );
        push @string, $str;
    }
    return join( "\n", @string ) . "\n";
}

sub limitToStringWithConditions {
    my $self  = shift;
    my $limit = $self->model->limit;
    my $tests = $limit->tests;
    my @string;
    foreach my $test (@$tests) {
        my @line;
        foreach my $item ( @{ $limit->testItems } ) {
            push @line, repNA( $test->{$item} );
        }
        foreach my $cond ( @{ $test->conditions } ) {
            push @line, repNA($cond);
        }
        my $str = join( ",", @line );
        push @string, $str;
    }
    return join( "\n", @string ) . "\n";
}

sub relsToString{
        my $self = shift;
        my $rels = shift;
        my @string  ;
        foreach my $rel (@$rels){
                my @line;
                foreach my $item (@{$self->relItems}){
                        push @line, repNA($rel->{$item});
                }
                my $str = join (",",@line);
                push @string, $str;
        }
        return join("\n",@string)."\n";
}

sub custindexesToString{
	my $self = shift;
	my $indexes = shift;
	my @string;

	foreach my $index (@$indexes){
		my @line;
		foreach my $item (@{$self->indexItems}){
			 push @line, repNA($index->{$item});
		}
		my $str = join (",",@line);
		push @string, $str;
	}

	return join("\n",@string)."\n";
}

sub printAutoChar {
	my $self =shift;
	my $wr = $self->writer;
	my $model = $self->model;
	my $outfilename = $wr->basename;
	my $AutoCharData = $model->misc;
	
	my $lotid = $$AutoCharData{LOT};
	my $wafer = $$AutoCharData{WFN};
	my $hedAddr = $$AutoCharData{HED};
	my $resAddr = $$AutoCharData{RES};
	my $parAddr = $$AutoCharData{PAR};	
	my $lnCntr = 0;
	
	$wr->open;
	$wr->put( "<HEADER>\n" . $self->autoCharHeaderToString($hedAddr) ."</HEADER>\n" );
	$wr->put( "<LOTINFO>\n" );
	$wr->put( "LOTID=$lotid\n" );
	$wr->put( "WAFERNUMBER=$wafer\n" );
	$wr->put( "</LOTINFO>\n");
	$wr->put( "<PAR>\n" . $self->autoCharParametersToString($parAddr) ."</PAR>\n" );	
	$wr->put( "<DATA>\n");
		foreach my $ln (sort {$$resAddr{$a} <=> $$resAddr{$b} } keys %$resAddr) {
			$lnCntr++;
			my $die_index = "DIE_INDEX=$lnCntr\n";
			$wr->put( "$die_index");
			my $resIdxAddr = $$resAddr{$ln}{IDX};
			my $resValAddr = $$resAddr{$ln}{VAL};
			
			for (my $i=0; $i<=$#$resIdxAddr; $i++){
				$wr->put( "$$resIdxAddr[$i]\n" );
			}
			my $resValStr = join (',',@{$resValAddr})."\n";
			$wr->put( "$resValStr");
		}
	$wr->put( "</DATA>\n");
	$wr->close;
}

sub autoCharHeaderToString {
	my $self = shift;
	my $header = shift;
	my @strArr = ();
	
	foreach my $h (@$header){
		push @strArr, $h;
	}
	return join ("\n",@strArr)."\n";
}

sub autoCharParametersToString {
	my $self = shift;
	my $testnames = shift;
	my @strArr = ();
	
	foreach my $h (@$testnames){
		push @strArr, $h;
	}
	return join ("\n",@strArr)."\n";
}

1;
=pod

=head1 NAME

PDF::Formatter::IFF - Formatter to print IFF standard file

=head1 DESCRIPTION

This module can format and print IFF file from L<PDF::DpData::Model.pm> object.

=head1 SYNOPSYS

  use PDF::Formatter;

  my $model =  new_model;
  $model->header(......);
  ....

  my $wr = PDF::DpWriter;
  $wr->ourdir(....);
  ....

  my $fmt = new_iff_formatter({  # new_iff_formatter is exposed by PDF::Formatter
    model => $model,
    writer => $wr
    });

  $fmt->testItems([qw/number name units group/]);
  $fmt->dataItems([qw/x y soft_bin/]);

  $fmt->printBinmap

=head1 ATTRIBUTES

  writer     -- PDF::Writer object
  model      -- PDF::DpData::Model object

=head1 ATTRIBUTES -- Array Ref

  testItems  -- test items to print in <PAR> section
                By default,
                <PAR>
                <number>,<name>,<units>
                 ..........
                </PAR>
  binItems   -- bin items to print in <BIN> section
                By default,
                <BIN>
                <number>,<name>,<PF>,<count>
                 ..........
                </BIN>
  dataItems  -- data items to print in <DATA> section
                For Parametric data
                <DATA>
                DIE_X=<x>
                DIE_Y=<y>
                SITE=<site>
                PARTID=<partid>
                HARD_BIN=<hard_bin>
                SOFT_BIN=<soft_bin>
                .............values ...........
                </DATA>

                For Binmap data
                <DATA>
                <x>,<y>,<site>,<partid>,<bindata>
                 ..........
                </DATA>

=head1 METHOD

=head2 printPar

print IFF file for Parameteric data type. WaferSort, FinalTest, PCM

=head2 printBinmap

print IFF file for Binmap data type

=head2 printLimit

print IFF file for Limit data

=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

 2015/04/06 kazukik: 1st verion
 2015/04/20 kazukik: add printLimit

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut
