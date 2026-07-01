# 24-Nov-2015 Eric	: initial release
# 08-Jul-2016 Eric	: added options for rel data processing
# 02-Feb-2017 Eric	: added people on the distri list
# 11-Jan-2018 Eric	: parse ONRMS datalog
# 06-Jun-2019 Eric	: changed domain name for email add to onsemi.com
# 13-Apr-2021 jgarcia : updated to received passed in bin ref file.
#
package PDF::Parser::Shiba;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use PDF::ExcelReader;
use Number::Range;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;


our $VERSION = "1.0";
our $mat_type = "";

my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

#my $ref_file_dir = "/data/szft_shiba/TP";
my $ref_file = "bin.ref";
my %param_bin_ref = ();
my %bin_ref = ();
my %tp = ();
my %td = ();
my %sbin = ();
my $tp_rev = "";
my $tp_name = "";
my $lotid = "";
my $log_file = "/data/szft_shiba/log/params_not_in_bin_ref_file.log";
my $subject = "Shibasoku: Undefined parameters and/or bins";
my $to = "pan.luo\@onsemi.com,xiang.hu\@onsemi.com,apollo.wang\@onsemi.com,ryan.ren\@onsemi.com,alec.deng\@onsemi.com,yms.admins\@onsemi.com,";
my $error_msg     = "";

sub readFile {
	my $self = shift;
  my $infile = shift;
	my $rel_lot = shift;
	my $ref_file_dir = shift;
	my $line = "";
	my @params_wo_bins = ();
	my %bins_wo_name = ();
	my $scan_code_err_flag = 0;
	my $serial = "";
	my %readings = ();
	my $ref_file = "${ref_file_dir}/bin.ref";

	# load bin ref file
	&load_ref_table($ref_file);

 	my $header = new_headerLong;
        my $model = new_model (
                {
                        header => $header,
                        misc   => {},
                        dataSource => 'SHIBA'
                }
        );

        my $wafer = $model->find('wafers',{number => 0});
        unless (defined $wafer){
                $wafer = new_wafer( { number => 0 } );
                $model->add('wafers',$wafer);
        }	

	# Get equip1_id/tester# from filename
	my ($dump, $eqptid, $dump) = split /\_|\./, substr($infile,rindex($infile,"/") + 1), 3;   
	   $eqptid = "" if $eqptid !~ /^SMT/i;	
	   $header->EQUIP1_ID("SOKU ".$eqptid);
	
	open FH, $infile or die "can't open $infile\n";
	while($line=<FH>)
	{
		chomp($line);
		$line =~ s/^\s+|\s+$//g;
		my (@dummy) = split /\s+/, $line;
		
		if ($line =~ /Scan\s+Code\s+Error/i) {
			$scan_code_err_flag = 1;	# Skip readingg affected by "SCAN CODE ERROR"
		}
		elsif ($dummy[0]=~/\d/ && $line=~/\s+Lo\s+/i && $line=~/\s+Hi\s+/i && $scan_code_err_flag==0){
			my $die = new_die;
			my $test_num = shift(@dummy);
			my $pf_flag  = shift(@dummy) if $dummy[0] =~ /^F$/i;	# "F" flag if failed
			my $test_nam = uc(shift(@dummy));
			   $test_nam = &clean_string($test_nam);
			my $dump     = shift(@dummy) if $dummy[0] =~ /^FAIL$/i;
			my $reading  = shift(@dummy);
			my $unit     = shift(@dummy) if $dummy[0] !~ /^LO$/i && $dummy[0] =~ /^[A-Z]/i;
				       shift(@dummy) if $dummy[0] =~ /^LO$/i;	# Dump "LO"	
			my $lolim    = shift(@dummy) if $dummy[0] =~ /\d$/i;
			   $lolim    = -1e20         if $lolim    =~ /^\%-?\d+/;
				       shift(@dummy) if $dummy[0] =~ /^HI$/i;	# Dump "HI"	
			my $hilim    = shift(@dummy) if $dummy[0] =~ /\d$/i;
			   $hilim    = 1e20          if $hilim    =~ /^\%\d+/;
			# Ignore the ff
			next if $test_nam =~ /ITEMS|INPOS/i;	# Represents total parameter count, ignore INPOS as per Xiang Hu
			#next if $test_num == 99999;	### "99999" MEANS "SCAN CODE ERROR"

			# Get test program rev
			next if $test_nam =~/^REV$/i && $tp_rev ne "";
			 
			if ($test_nam =~/^REV$/i && $tp_rev eq "")
			{
				$tp_rev  = $reading;
				$tp_rev  =~ s/\.//g;
				$tp_rev += 1000;	# Force tp revision to start at 1000
				$header->REVISION($tp_rev);
				next;
			}
			
			# Save test reading
                        $readings{$test_num} =
                        {
                                RESULT => $reading,
                                PF     => $pf_flag||"P",
                        };

			# Capture unique test parameter
			next if defined $tp{$test_num};

			# Get associated bin number and name
			my $bin_number = $param_bin_ref{$test_nam};
			my $bin_name   = $bin_ref{$bin_number};
			
			# Log parameters without bin
			push(@params_wo_bins,$test_nam) if  $bin_number eq "";

			# Log bin number without bin name
			$bins_wo_name{$bin_number}=1 if $bin_name eq "" && $bin_number != 1;

			$tp{$test_num} = 
			{
				NAME     => $test_nam,
				UNIT     => $unit||"",
				LOLIM    => $lolim,
				HILIM    => $hilim,
				BIN_NUM  => $bin_number,
				BIN_NAM  => $bin_name,
			};

		}	
		elsif ($dummy[0] =~ /^BIN$/i){
			# Get Bin Count
			next if $dummy[1] == 8;
			$sbin{$dummy[1]}++;
			# Log bin numbers not in reference file
			if ($bin_ref{$dummy[1]} eq "" && $dummy[1] != 1 && $scan_code_err_flag == 0)
			{
				$bins_wo_name{$dummy[1]}=1;
			}
			$td{$serial} = 
			{
				DATA => {%readings},
				BIN  => $dummy[1],
			};
			# Reinitialize Hash
			%readings = ();

		}
		elsif ($dummy[0] =~ /DUT\#/i && $dummy[2] =~ /SER\#/i){
			$serial  = $dummy[3];
			
			my ($day,$mon, $year)= split /\-/, $dummy[5];
			my ($hr, $min, $sec) = split /\:/, $dummy[6];
			$year += 2000 if length($year) == 2;		### DLG LOADING STARTS IN YR 2010
			my $start_time = $year."/".$mon."/".$day." ".$hr.":".$min.":".$sec;
                        $header->START_TIME($start_time);
                        $header->END_TIME($start_time);
			
			# Reset "Scan_Code_Error" flag	
			$scan_code_err_flag = 0;
		}
		elsif ($dummy[0] =~ /LOT/i && $dummy[2] =~ /NAME/i && $lotid eq ""){
			$lotid = trim($dummy[1]);
			$tp_name = trim($dummy[3]);
			
			# check if data is a retest
			if ($lotid =~ /REJ/i || $infile =~ /REJ/i) {
				$lotid =~ s/REJ//i;
				$tp_name = $tp_name."_"."R";	
			}
			$header->LOT(uc($lotid));
			$header->PROGRAM($tp_name);
		}
	}
	close(FH);
	
	### REPORT PARAMETERS NOT IN BIN REF FILE ###
	if ($#params_wo_bins > -1 || (keys %bins_wo_name) > 0)
	{
		my (@dummy)  = split /\//, $infile;
		my $err_file = $dummy[$#dummy];

		### LOG PARAMETERS W/O BIN ###
		if ($#params_wo_bins > -1)
		{
			open LOG, ">$log_file"  if ! -e $log_file;
			open LOG, ">>$log_file" if   -e $log_file;
			print LOG "The ff. params are not defined in the bin reference file. Kindly update.\n";
			print LOG "FILE = $err_file\n";

			foreach (@params_wo_bins)
                        {
				print LOG "$_\n";
                        }
			close(LOG);
		}

		### LOG BIN NUMBERS NOT IN BIN REF FILE ###
        	if (keys %bins_wo_name > 0)
        	{
                	### LOG PARAMETERS W/O BIN ###
                	open LOG, ">$log_file"  if ! -e $log_file;
                	open LOG, ">>$log_file" if   -e $log_file;
			print LOG "\nThe ff. bin numbers are not defined in the bin reference file. Kindly update.\n";

			foreach my $bin_no (sort {$a<=>$b} keys %bins_wo_name)
                        {
				print LOG "$bins_wo_name{$bin_no}, \n";
                        }
			close(LOG);

        	}
		&send_email();
		my $cmd = "/bin/rm -f $log_file";
		system($cmd);           # Delete log file after sending
		$model->{mis} = "No bin reference";
		return $model;
		#dpExit(1, "No bin reference");
	}
        
	### STORE PARSED VALUES INTO MODEL ####
	foreach my $no(sort {$a<=>$b} keys %tp){
		my $test = new_test;
		$test->number($no);
               	$test->name($tp{$no}{NAME});
               	$test->units($tp{$no}{UNIT});
               	$test->LSL($tp{$no}{LOLIM});
               	$test->HSL($tp{$no}{HILIM});
                $model->add( 'tests', $test );
	}		
	
	foreach my $no(sort {$a<=>$b} keys %sbin){
		#next if $no == 8;
		my $phbin = new_bin;
		my $bin_name;
		my $pf_flag;
		if ($no == 1){
			$bin_name = "BIN_".$no;
			$pf_flag = "P";
			#print "BIN= $bin_name\t$pf_flag\n";
                }
                else {
                       	$bin_name = $bin_ref{$no};
			$pf_flag = "F";
			#print "BIN= $bin_name\t$pf_flag\n";
                }
		$phbin->number($no);
		$phbin->name($bin_name);
		$phbin->PF($pf_flag);
		$phbin->count($sbin{$no});
		$wafer->add('bins',$phbin);
        }

	#my $siteid = 1;
	foreach my $no(sort {$a<=>$b} keys %td){
		my $die = new_die;
		#$die->site($siteid++);
		$die->site($no);
		$die->partid($no);
		$die->x("");
		$die->y("");
		$die->soft_bin($td{$no}{BIN});
		$die->hard_bin($td{$no}{BIN});
		$wafer->add('dies',$die);
		
		my $addr  = $td{$no}{DATA};
		foreach my $res(sort {$a<=>$b} keys %$addr){
			$die->add( 'result', repNA($$addr{$res}{RESULT}) );
		}
	}

	# perform for reliability data
	if ($rel_lot) {
		# assumed that fn always start with "Q" and duration and temp is separated with "T";
		my $base_fn = basename($infile);
           	$base_fn =~ s/\.DLG.*+//ig;
        	my @item = split /\_/, $base_fn;
		   $item[0] =~ s/^Q//i; 
		my $qpnum;
		my $devchar;
		my $lotchar;
		my $temp = 25;    #default to 25 because cannot be added to fname
		   $item[0] = substr $item[0], 10; 
		my $strdur = $item[0];   
		   $strdur =~ s/\D//g;
	   	my $strname = substr $item[0],0,(index($item[0],$strdur)); 
		   $strname =~ s/\d//g;
		my $dtype = substr $item[0], -1;
		   $dtype = "" if $dtype =~ /[0-9]/;

		if ($item[0] =~ /^20/) {
			$qpnum = substr $item[0], 0, 8;
			$devchar = substr $item[0], 8, 1;
			$lotchar = substr $item[0], 9, 1;
		 	$header->LOT($qpnum.$devchar.$lotchar);	
		}
		elsif($item[0] =~ /^U/i) {
			$qpnum = substr $item[0], 0, 6;
			$lotchar = substr $item[0], 6, 1;
			$header->LOT($qpnum.$lotchar);
		}

        	my $range = Number::Range->new("0..1000000");
        	if ( $range->inrange($strdur) && $strdur !~ /\D/) {
                	#do nothing
        	}
        	else {
                	WARN ("Stress Duration not in range =  $strdur");
			$strdur = "" if $strdur =~ /[a-z]/i;
			$model->{forSBflag} = 1;
        	}
        	my $range = Number::Range->new("-1000000..1000000");
        	if ( $range->inrange($temp) && $temp !~ /\D/) {
                	#do nothing
        	}
        	else {
                	WARN ("ATETemp not in range = $temp");
			$temp = "" if $temp =~ /[a-z]/i;
			$model->{forSBflag} = 1;
        	}

		#$header->LOT($qpnum.$devchar.$lotchar);
		$header->INDEX1($strname."_".$strdur."_".$temp."_".$dtype);

        	my $rel = new_rel;
        	$rel->qpnumber($qpnum);
        	$rel->devchar($devchar);
        	$rel->lotchar($lotchar);
        	$rel->strname($strname);
        	$rel->strduration($strdur);
        	$rel->atetemp($temp);
        	$rel->datalogtype($dtype);
        	$model->add('rels', $rel);
	}

	return $model;
}

sub load_ref_table
{
	      my $bin_ref_file = shift;
        open FH, $bin_ref_file or die "can't load $ref_file\n";
        while(my $line=<FH>)
        {
                chomp($line);
                $line =~ s/\s+|\t+//g;
                next if $line =~ /^\#/ || $line eq "";

                my (@dummy) = split /\,/, $line;
                # Load parameter-bin ref table
                if ($dummy[0] =~ /[A-Z]+/i && $dummy[1] =~ /^\d+$/)
                {
                        $dummy[0] = uc $dummy[0];
                        $dummy[0] = &clean_string($dummy[0]);
                        $param_bin_ref{$dummy[0]} = $dummy[1];
                }
                # Load bin-ref table
                elsif ($dummy[0] =~ /^\d+$/ && $dummy[1] =~ /[A-Z]+/i)
                {
                        $dummy[1] = &clean_string($dummy[1]);
                        $bin_ref{$dummy[0]} = uc $dummy[1];
                }
        }
        close(FH);

}

sub send_email
{
        if ( -e $log_file) {
                my @message = ();
                open LOG, $log_file or die "Could not open log file: $!\n";
                while(<LOG>) {
                        push @message, $_;
                }
                close(LOG);

                open(MAIL, "|mailx -s \"$subject\" $to");
                for ( my $ii=0; $ii<=$#message; $ii++)
                {
                        print MAIL "$message[$ii]\n";
                }
                close(MAIL);
        }
        else {
                print "No log file found.\n";
        }
}

sub clean_string
{
        my $str = shift;
           $str =~ s/^\s+|\s+$//g;
           #$str = &EDBUtil::cleanString($str);
           $str =~ s/\,//g;
           $str =~ s/\s+/_/g;
        return($str);
}

1;
