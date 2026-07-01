# 2016-Jan-12 Eric	: New
# 2017-May-02 Eric	: return limit, use sourec lot as wafername, store error as misc
package PDF::Parser::ET_BKET;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use File::Basename qw/basename/;
use Tie::File;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

my $attr = [];

sub array {
    return qw//;
}
__PACKAGE__->mk_accessors(array);

	my ($key1,$key2,$key3,$TestData,$file_name)="";
        my ($hash_tmp1,$hash_tmp2,$hash_tmp3)="";
        my ($a,$b,$Dhash1,$Dhash2,$Dhash3,$Dhash4,$Debugging)="";
        my ($start_time,$hashkey,$wafer_id,$position,$x_coord,$y_coord) = "";
        my ($i,$j,$k,$wafer_no,$test_cnt,$setup_time,$tmp)=(0,0,0,0,0,0,0);
        my %value=();
        my %comment=();
        my %test_name=();
        my %ResultData=();
        my %WaferData=();
        my %RawData=();
	my %uniqueTest=();
        my @test_num=();
        my ($run,$lot_type,$mode_cod,$oper_id,$process_id,$process_no,$str,$tot_info,$tmp_str,$tmp_info)="";
        my ($facility,$location,$tester_nm,$node_nam,$stat_num,$device_nm,$lot_no,$testplan_nm,$revision_id)="";
        my ($inch_info,$start_date,$test_seq,$tested_wafer_id,$t_coord,$c_coord,$b_coord,$l_coord,$r_coord)="";
        my ($test_flg,$tested_wafer,$point_num,$tested_cnt,$revision_no,$tested_seq_length)=0;
        my $cnt = 1;
        my $wafer_cnt = 1;
        my $status = 1;
	my $errmsg = "";
	my $errcod = 1;
        my ($out,$out1, $out2,$temp,$data,$data1,$tmp1)="";
        my ($tot_reading_count,$tot_count)=(0,0);
        my $flg=1;
	my $vaild_check = 0;
        my %PartHash= qw (
                    T  TOP
                    C  CENTER
                    B  BOTTOM
                    L  LEFT
                    R  RIGHT
        );

sub readFile {
	my $self   = shift;
    	my $infile = shift;
	my $tpDir  = shift;
	my $limit;
    	my $header = new_headerLong;
        my $wmap   = new_wmap;
    	my $model  = new_model(
        	{   header => $header,
        	    misc   => {},
        	    wmap => $wmap,
        	    dataSource => 'ET'
        	}
        );

	open(INFLE,"$infile");
	if($status > 0 ) {
	    #print  "Completely Open the Inputfile(=$file)\n"; #COMMENTED OUT FOR MFT
	}
	else {
	        print  "Can't read the Inputfile(=$infile)\n";
	}

	if ($infile =~ /\.EWB/) {
    		#print  "TR ET Data file(=$infile)\n"; #COMMENTED OUT FOR MFT
    		#$TestData  = ReadFile_TRET();  ## TR ET
	}
	elsif ($infile =~ /\.ET/) {
    		$TestData  = ReadFile_LICET($model);  ## LIC ET
	}
	else {
    		#print  "CAE ET Data file(=$infile)\n";
    		#$TestData  = ReadFile_CAEET();  ## CAE ET
	}

	($hashkey) = keys %$TestData;
	$test_cnt  = length($$TestData{$hashkey}{TEST_SEQ});
	
	#$setup_time = stdf_time();

	my $PRES_CNT = 0;
	my $PSUM_CNT = 0;
	my $WRR_CNT  = 0;

	my ($diff,$diff1,$siz,$tmp_lot)="";
	$tmp_lot = uc $$TestData{$hashkey}{LOT_NO};
	$header->LOT($tmp_lot);
	$tmp_lot = substr($tmp_lot,0,6);
	#$header->LOT($tmp_lot);
	$tmp_lot = substr($tmp_lot,6,6);
	while($tmp_lot =~ /[0-9]$/)
	{
    		$tmp_lot =~ s/[0-9]$//g;
	}

	if ($tmp_lot ne "") {
		$header->LOT(substr($tmp_lot,6,6));
	}

	# get source lot
	$header->populateSrcLot;

	if ($infile !~ /\.EWB/i && $infile !~ /\.rdf/i ) {
		## Samsung LSI Lot ID Naming Rule change  2004. 08. 05 DJ KWON
		#if ($inch_info ne ""){
		if ($inch_info ne "" && $inch_info =~ /inch/i){
			$siz = substr($inch_info,0,1);
    		}
		else
		{
	    		$diff = $$TestData{$hashkey}{LOT_NO};  # 2003/03/26 DS kang
	    		$diff =~ s/^\s//g;
	
	    		$diff = uc substr($$TestData{$hashkey}{LOT_NO},0,1);
	    		$diff1= uc substr($$TestData{$hashkey}{LOT_NO},0,2);
	
	    		if(($diff eq "G") || ($diff1 eq "KG"))            	# case A or B      4 inch
	    		{                                     			# case C or E or F 5 inch
				$siz = "6";                          		# case G           6 inch
	    		}
	    		elsif(($diff eq "C") || ($diff eq "E") || ($diff eq "F") || ($diff1 eq "KC") || ($diff1 eq "KE") || ($diff1 eq "KF"))
	    		{
				$siz = "5";
	    		}
	    		elsif(($diff eq "A") || ($diff eq "B") || ($diff1 eq "KA") || ($diff1 eq "KB"))
	    		{
	        		$siz = "4";
	    		}
	    		else  # 2003/08/07 JH KIM - Case B C E F G or EXIT
	    		{
				$siz = "5";  
	    		}
		}
   		$$TestData{$hashkey}{TESTPLAN} = "$$TestData{$hashkey}{TESTPLAN}".$siz;
	}	

	if ($infile =~ /\.EWB/i) {
		$header->EQUIP1_ID($$TestData{$hashkey}{NODE_NAM});
	}
	$header->PROGRAM($$TestData{$hashkey}{TESTPLAN});
	$header->REVISION($$TestData{$hashkey}{REVISION});
	$header->OPERATOR($$TestData{$hashkey}{OPER_ID});
	$header->EQUIP1_ID($$TestData{$hashkey}{TESTER_NM});

	# Get limits
	my $program = $header->PROGRAM;
	my $rev = $header->REVISION;
	my $regexp1 = "${program}_${rev}.*\.TXT";
	   $program =~ s/\-//;
	my $regexp2 = "${program}_${rev}.*\.TXT";
	my $limitfile;
	INFO("Limit file search patterns: $regexp1 and $regexp2");
        foreach my $tpfile (glob "$tpDir/*.TXT") {
                if ($tpfile =~ /$regexp1/i){
                        INFO("TP Found : $tpfile");
                        $limitfile = $tpfile;
                }
                elsif ($tpfile =~ /$regexp2/i){
                        INFO("TP Found : $tpfile");
                        $limitfile = $tpfile;
                }
        }
	unless (defined $limitfile) {
		$errmsg = "Limit file not found";
		$errcod = 4;
		$model->misc->{err_msg} = $errmsg;
		$model->misc->{err_cod} = $errcod;
	}		

	$limit = $self->readTestsFile($limitfile);

	# Store limits into model
	foreach my $tnum (sort keys %uniqueTest) {
		my $test = $limit->find('tests',{number => $tnum});
		my $testName = $test->name;
		my $testUnit = $test->units;
        	my $test = new_test({
           		number => $tnum,
           		name => $testName,
			units => $testUnit,
        	});	
		$model->add('tests',$test);
	}

	
	$Dhash1=$$TestData{$hashkey}{RESULT};
	foreach $wafer_no ( sort keys %$Dhash1) {
		my $wafer = new_wafer;
		$wafer = $model->find('wafers',{number => $wafer_no});
		unless (defined $wafer){
			$wafer = new_wafer( { number => $wafer_no } );
			if ($header->SOURCE_LOT ne "" ) {
				$wafer->name($header->SOURCE_LOT."_".sprintf("%02d",$wafer->number));
			}
			$model->add('wafers',$wafer);
		}
		$Dhash2=$$Dhash1{$wafer_no}{ReadData};

		my $npart_id ;
		foreach $position ( sort keys %$Dhash2)  {
			my $coordition = $$TestData{$hashkey}{$position."_COORD"};
			($x_coord,$y_coord) = split(/\,/,$coordition);

			$npart_id = uc $PartHash{$position};
        		$npart_id =~ s/^\s//g;

			if($npart_id eq 'TOP') {
				$PartHash{$position} = 1;
			}
			elsif($npart_id eq 'CENTER') {
				$PartHash{$position} = 2;
			}
			elsif($npart_id eq 'BOTTOM') {
				$PartHash{$position} = 3;
			}
			elsif($npart_id eq 'LEFT') {
				$PartHash{$position} = 4;
			}	
			elsif($npart_id eq 'RIGHT') {
				$PartHash{$position} = 5;
			}
			else {
				$PartHash{$position} = $npart_id;
			}

			my $die = new_die;
			$die = $model->find('dies',{site => $PartHash{$position}});
                	unless (defined $die) {
                        	$die = new_die( {site => $PartHash{$position}});
                        	$wafer->add('dies',$die);
                	}		
			$die->x($x_coord);
			$die->y($y_coord);
			
			$Dhash3=$$Dhash2{$position}{result_data};

			if ($infile =~  /\.EWB/i) {
				$Dhash4=$$Dhash2{$position}{result_comment};
			}	

			#foreach my $test_number ( sort keys %$Dhash3) {
			foreach my $test_number (sort keys %uniqueTest) {
				$die->add('result', repNA($$Dhash3{$test_number}));	
				$PRES_CNT++;
			}
		}
	}

return $model, $limit;
}

sub ReadFile_LICET {
	#my $infile = shift;
	my $model = shift;
	read INFLE, $str,514;
	$flg=1;
	while($cnt < 20) {
		$flg=read INFLE,$str,1;
		$tmp=ord($str);
		if( $tmp == 35 || $tmp == 95 || ($tmp >= 48 && $tmp <= 57 ) || ($tmp >= 65 && $tmp <= 90)
		|| ($tmp >= 97 && $tmp <= 122) || ($tmp >= 40 && $tmp <= 46)) {
			$tmp_info .= $str;
			$tmp_info =~ s/\s+//g;
			$vaild_check = 1;
		}
		else {
	    		if ($vaild_check == 1){
				$tot_info .= $tmp_info."/";
	        		$tmp_info="";
	        		$cnt++;
	        		$vaild_check = 0;
			} #vaild_check if-end
	    	}
	}

	$tot_info =~ s/\/\//\//;
	($facility,$location,$tester_nm,$device_nm,$lot_no,$revision_id,$inch_info,
	$oper_id,$process_id,$process_no,$start_date,$tested_wafer,$point_num,
	$tested_cnt,$tested_wafer_id,$test_seq,$t_coord,$c_coord,$b_coord)
	=split(/\//,$tot_info);

    	$testplan_nm = $device_nm;
	#$testplan_nm =~ s/\-//;
    	$revision_id =~ s/[a-z]//;
    	$revision_no = $revision_id+0;

	$tot_count=($point_num * $tested_cnt) + (2 * $tested_cnt);
	#$start_date = stdf_time();
	if(substr($inch_info,1,4) ne "inch") {
		print "inch=$inch_info\n";
    		close(INFLE);
		$errmsg = "File is old version file";
		$model->misc->{err_msg} = $errmsg;
		$model->misc->{err_cod} = $errcod;
	}
	if( (substr($lot_no,0,1) eq "s") || (substr($lot_no,0,1) eq "S") ){
        	close(INFLE);
        	#$run = "/bin/rm $infile";
        	#system($run);
		$errmsg = "Lot is test version!";
		$model->misc->{err_msg} = $errmsg;
		$model->misc->{err_cod} = $errcod;
        }
	
	## Read Result Data
    	$flg=$cnt=$j=$k=1;
    	$tested_seq_length=length($test_seq);
    	$vaild_check =0;
	
	while($flg eq 1){
		$flg=read INFLE,$str,1;
       		$tmp=ord($str);
		if( $tmp == 35 || $tmp == 95
		|| ($tmp >= 48 && $tmp <= 57 ) || ($tmp >= 65 && $tmp <= 90)
		|| ($tmp >= 97 && $tmp <= 122) || ($tmp >= 40 && $tmp <= 46)){
			$tmp_info .= $str;
			$tmp_info =~ s/\s+//g;
			$vaild_check = 1;
		}
		else {
			if ($vaild_check == 1) {
				$tot_reading_count++;
				if($tot_reading_count > $tot_count) {
       	  		 		last;
       	  			}
				$k = $cnt % $tested_cnt;
				if ($k eq 0) {
              				$k = $tested_cnt;
          			}
				if($cnt <= $tested_cnt) { #Storing Test Number;
             				$tmp_info += 0 ;
             				$test_num[$k-1] = $tmp_info;
          			}
				elsif($cnt > $tested_cnt && $cnt <= $tested_cnt * 2) { #Storing Test Name;
             				$test_name{$test_num[$k-1]}=$tmp_info;
          			}
				else { # Storing a Tested Value(=Result Value);
					$tmp_info =~ s/ÿÿ//g;
       	      				$value{$test_num[$k-1]} = $tmp_info;
		       	      		if($k eq $tested_cnt) {
                				$i = $j % $tested_seq_length;
                				if($i eq 0 ) {
                   					$i = $tested_seq_length;
                				}
                				$position = substr($test_seq, $i - 1,1);
	 
       	         				if($i % $tested_seq_length eq 1) {
                   					$wafer_no = substr($tested_wafer_id, 2 * $wafer_cnt - 2,2);
                   					$wafer_cnt++;
                				}

                				$RawData{$position} =
                   				{
                       					result_data => {%value}
                   				};
                				if($j % $tested_seq_length eq 0) {
                    					$WaferData{$wafer_no} =
                      					{
                       		   				ReadData => {%RawData}
                      					};
                    					undef %RawData;
               					}
                				$j++;
             				}
				}
				$tmp_info="";
    	      			$cnt++;
          			$vaild_check = 0;
			}
		}
	}
	close(INFLE);
	
	$ResultData{$lot_no} =
        {
           FACILITY        =>  $facility,
           LOCATION        =>  $location,
           TESTER_NM       =>  $tester_nm,
           DEVICE_NM       =>  $device_nm,
           LOT_NO          =>  $lot_no,
           TESTPLAN        =>  $testplan_nm,
           REVISION        =>  $revision_no,
           OPER_ID         =>  $oper_id,
           PROCESS_NO      =>  $process_no,
           PROCESS_ID      =>  $process_id,
           START_DATE      =>  $start_date,
           TESTED_WAFER    =>  $tested_wafer,
           POINT_NUM       =>  $point_num,
           TESTED_CNT      =>  $tested_cnt,
           TESTED_WAFER_ID =>  $tested_wafer_id,
           TEST_SEQ        =>  $test_seq,
           T_COORD         =>  $t_coord,
           C_COORD         =>  $c_coord,
           B_COORD         =>  $b_coord,
           L_COORD         =>  $l_coord,
           R_COORD         =>  $r_coord,
           TEST_NM         =>  {%test_name},
           RESULT          =>  {%WaferData}
        };

    	(\%ResultData);
}

sub by_number
{
        if ($a < $b)
        {
                -1;
        }
        elsif ($a == $b)
        {
                 0;
        }
        elsif ($a > $b)
        {
                1;
        }
}

sub readTestsFile {
    my $self = shift;
    my $infile = shift;
    tie my @file, 'Tie::File', $infile or return $!;
    my $tests_ary;
    my $limit = new_limit;
    my $test;
    for my $linenr (0 .. $#file) {
        next if $linenr == 0;
        $test = new_test;
        my @items = split /\:/, $file[$linenr];
           $items[1] =~ s/^_//g;
           $items[1] =~ s/^\s//g;
           $items[1] =~ s/_/-/g;
           $test->number(trim($items[0]));
           $test->name(trim($items[1]));
           $test->desc(trim($items[2]));
           $test->units(trim($items[3]));
           $test->LOL(trim($items[6]));
           $test->HOL(trim($items[7]));
           trim($items[4]);
           trim($items[5]);
	   unless (defined $uniqueTest{$items[0]}){
		$uniqueTest{$items[0]} = 1;
	   }
           # Check if next test eq SAME
           if ($file[$linenr + 1] !~ /SAME/ && $file[$linenr] !~ /SAME/ && $linenr <= $#file) {
               if ($items[4] > $items[5]){
                       $test->LSL($items[5]);
                       $test->HSL($items[4]);
               }
               else {
                       $test->LSL($items[4]);
                       $test->HSL($items[5]);
               }
           }
           else {
               $items[4] = ($items[4] =~ /^0\.0*/) ? -1e12 : $items[4];
               $items[5] = ($items[5] =~ /^0\.0*/) ? 1e12 : $items[5];
               $test->LSL($items[4]);
               $test->HSL($items[5]);
           }
           #push @$tests_ary, $test;
	   $limit->add('tests', $test);
    }
    untie @file;
    #return $tests_ary;
    return $limit;
}

=pod
sub Comment_del
{
    my $sub_len = length $sub_tmp;
    my $sub_tmp = substr $_[0],  7,  $len;
    $sub_tmp =~ s/ //g; 
    chomp($sub_tmp);
    return($sub_tmp);
}
=cut
1;
