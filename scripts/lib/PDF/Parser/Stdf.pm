# SVN $Id: Stdf.pm 2104 2017-04-25 02:56:58Z dpower $
# 2015-06-08 grace   - added HBR_each, SBR_each
# 2015-06-16 grace   - arrange line
# 2015-06-17 grace   - Fixed one issue (There are a few parts that have more readings for certain tests than there should be)
# 2015-08-03 eric    - Get test results even if headnum & sitenum is not 255 in readStdfAscii_fet_sort
# 2015-10-23 eric    - added readStdfAscii_bksort_tmt subroutine
# 2015-11-23 gilbert - delete TD_txt file in convertBinToAscii on every dpExit 1
# 2016-Mar-03 gilbert - delete the outfile if the command stdf_copy failed to convert to text.
# 2017-Mar-03 jgarcia - added getLotWaferFromSTDFV4RawFile, loadSTDFV4Template and unpack_me subroutines.

package PDF::Parser::Stdf;
use strict; 
use FindBin qw/$Bin/;
use File::Basename qw/dirname basename/;
use PDF::Parser::Stdf::Model;
use PDF::DpLoad;
use PDF::Log;
our @ISA=qw/Exporter/;
our @EXPORT = qw/ convertBinToAscii readStdfAscii  readStdfAscii_WM readStdfAscii_fet_sort
	new_stdf new_stdfWafer new_stdfRes readStdfAscii_bksort_tmt getLotWaferFromSTDFV4RawFile unpack_me loadSTDFV4Template /;
our $VERSION = "1.0";
my  $rec_keys      = "LOT_ID|WAFER_ID|SBLOT_ID";
my  %stdf_recs     = ();
my  %stdf_format   = ("B*1" => "B",
		      						"B*n" => "B",
                      "C*1" => "A",
                      "C*n" => "A",
                      "I*1" => "c",
                      "I*2" => "s",
                      "R*4" => "f",
                      "U*1" => "C",
                      "U*2" => "S",
                      "U*4" => "L");
                  
my ($cpu_type,$stdf_ver,$fld_len,$lotid,$waferid,$sblotid);
my %rec_counter;
my $fileHandle;
my $in;
my $rec_name;


# Class method
sub new_stdf{ return PDF::Parser::Stdf::Model->new(@_) };
sub new_stdfWafer{ return PDF::Parser::Stdf::Model::Wafer->new(@_) };
sub new_stdfRes{ return PDF::Parser::Stdf::Model::Res->new(@_) };
sub get_headerItem{ return PDF::Parser::Stdf::Model->item };
sub get_headerArray{ return PDF::Parser::Stdf::Model->array };
sub get_waferArray{ return PDF::Parser::Stdf::Model::Wafer->array };
sub get_resArray{ return PDF::Parser::Stdf::Model::Res->array };
#
#

sub getLotWaferFromSTDFV4RawFile() {

	############
	# VARIABLES
	############
	#my %WIR = {};
	my $file = shift;
	my $rec_counter = "";
	my $rec_typ     = "";
	my $wid		= 0;
  #my $WIR{$wid}   = "";		### WAFERID=0 FOR F/T DATA
  
 
  #$WIR{$wid} = "";
 
  

	####################
	# OPEN DATALOG FILE
	####################    
	open $fileHandle, "<", $file or dpExit(1,"Unable to open raw file $file");


	##########################################
	# READ FAR FOR STDF FILE VERSION(REQUIRED)
	##########################################
	read $fileHandle, $in, 2;
	$rec_typ   = unpack_me($fileHandle, "C", 1, "") . "_" . unpack_me($fileHandle, "C", 1, "");
	$cpu_type  = unpack_me($fileHandle, "C", 1, "");
	$stdf_ver  = unpack_me($fileHandle, "C", 1, "");
	#print "$rec_typ\t$rec_typ\t$stdf_ver\n";
	
#	unless ($cpu_type =~ /[012]/ && $rec_typ eq "0_10")	{
#		print "\ndir=bad_file_format";  
#		               ### RETURN BAD SUBDIR FOR MFT
#		               #$errDesc = "Bad File Format";
#				close $fileHandle;
#				exit 100;
#	}

	##################################
	# START PARSING DATA FILE CONTENT
	##################################
	LEVEL1: while (1){
		#####################
		# READ RECORD HEADER 
		#####################
		my $rec_read = 0;	### HOLD THE NUMBER OF BYTES READ PER STDF REC
		my $rec_len  = unpack_me($fileHandle, "S", 2, "");
		my $rec_typ  = unpack_me($fileHandle, "C", 1, "") . "_" . unpack_me($fileHandle, "C", 1, "");
		$rec_name = $stdf_recs{$rec_typ}{NAME}||"";
		#print "parsing $rec_name\t$rec_typ rec_len=$rec_len\n";


		#######################################
		# EXIT IF REC_LEN IS ZERO. ASSUMES EOF
		#######################################
		last if $rec_len == 0;                   


		###############################
		# SKIP UNWANTED STDFv4 RECORDS
		###############################
		if ($rec_name eq ""){
			#print "\tskipping $rec_typ\n";
			my $dummy1 = "";
			read $fileHandle, $dummy1, $rec_len;    
			next;
		}

	
		my %tmp     = ();
		my $rec_key = "";
		foreach my $line(split /\n/, $stdf_recs{$rec_typ}{FORMAT}){
			###############
			# FIELD FORMAT
			###############
			my ($fld_name, $fld_format, $v4_inv_val,$plus_inv_val) = split /\s+/, $line;
			my $value     = "";
			$fld_name     =~ s/ //g;
			$fld_len      =~ s/ //g;
			$v4_inv_val   =~ s/ //g;
			$plus_inv_val =~ s/ //g;
			
			###########################
			# TRAP UNKNOW FIELD FORMAT
			###########################
			my $junk;
			if (exists($stdf_format{$fld_format})){
				($junk, $fld_len) = split /\*/, $fld_format;
				$fld_format       =~ s/ //g;
				$fld_format       = $stdf_format{$fld_format};
			} else {
				print "Unknown format: ${rec_name}.${fld_name} \"$fld_format\"\n";
				#$errDesc = "Unknown format: ${rec_name}.${fld_name} \"$fld_format\"";
				#exit 1;
			}
			
			##############
			# UNPACK DATA
			##############
			### FIXED REC LENGTH ###
			if ($fld_len =~ /\d+/){
				$value = unpack_me($fileHandle, $fld_format, $fld_len, $v4_inv_val, $plus_inv_val);
				$rec_read += $fld_len;
			}
			### VARIABLE REC LENGTH ###
			elsif ($fld_len eq "n")	{
				$fld_len = unpack_me($fileHandle, "C", 1, "");
				$value   = unpack_me($fileHandle, $fld_format, $fld_len, $v4_inv_val, $plus_inv_val);
				$rec_read += 1 + $fld_len;
			}
			#print "\t$fld_name\t$fld_format\t$fld_len\n";

		
			### UCASE BUT PTR.UNIT ###
			$value = uc($value) unless ($rec_name eq "PTR" && $fld_name eq "UNITS"); 
			$value =~ s/\s+/\_/g;
			$rec_key        = $value if $fld_name =~ /$rec_keys/i;
			$tmp{$fld_name} = $value;
			#print "\"$rec_name\"\t\"$fld_name\"\t=\t$value\n";
			if ($fld_name eq "LOT_ID") {
				
				$lotid = $value;
			} elsif ($fld_name eq "WAFER_ID") {
				$waferid = $value;
			} elsif ($fld_name eq "SBLOT_ID") {
				$sblotid = $value;
			} 
			
      last if $rec_name eq "PIR";
			################################
			# READ UP TO RECORD LENGTH ONLY
			################################
			last if $rec_read >= $rec_len;
		}
		#print "\n\n";


		


		########################
		# STOP AFTER MRR IS READ
		########################
		last if $rec_counter{MIR} == 1;
  }       
  close($fileHandle);
  return $lotid, $waferid, $sblotid;

}


#######################
# UNPACK BINARY RECORD
#######################
sub unpack_me(){
  ########################
  # GET PASSED PARAMETERS 
  ########################
  
  my $fH       = shift;
  my $f           = shift;
  my $count            = shift;  
	my $v4_invalid_val   = shift;
	my $plus_invalid_val = shift;
	my $out;
	my (@vaxFlt, @b); 

  ################        
  # UNPACK RECORD 
  ################
  read $fH, $in, $count;
  if ($f =~ /^B$/i){
   $out = unpack("${f}".${count}*8, $in);
  }	elsif ($f eq "f" && $cpu_type == 0){
    
  @vaxFlt = unpack "C" x 4, $in;

    my $XPVAXFlt4Byt1ExpMask            =0x7f ;
    my $XPVAXFlt4Byt1ExpTooSmallForIEEE =0x00 ;
    my $XPVAXFlt4Byt1SgnMask            =0x80 ;
    my $XPVAXFlt4Byt1ExpTwo             =0x01 ;
    my @ieeeFlt ;

    if ( $XPVAXFlt4Byt1ExpTooSmallForIEEE == ( $vaxFlt[1] & $XPVAXFlt4Byt1ExpMask ) ){
       # too small, assume 0
       #
       # This should probably return FLT_MIN and preserve sign
       # Not likely to be an issue
       #
       $ieeeFlt[0] = 0x00 ;
       $ieeeFlt[1] = 0x00 | $vaxFlt[1] & $XPVAXFlt4Byt1SgnMask ;
       $ieeeFlt[2] = 0x00 ;
       $ieeeFlt[3] = 0x00 ;
    } else {
       # Reorder the bytes subtract two to the exponent.
       $ieeeFlt[0] = $vaxFlt[1] - $XPVAXFlt4Byt1ExpTwo ;
       $ieeeFlt[1] = $vaxFlt[0] ;
       $ieeeFlt[2] = $vaxFlt[3] ;
       $ieeeFlt[3] = $vaxFlt[2] ;
    }
	
		if ($cpu_type =~ /[1]/) {
       $out = unpack("f",pack("CCCC",($ieeeFlt[0], $ieeeFlt[1], $ieeeFlt[2], $ieeeFlt[3])));
		}	elsif ($cpu_type =~ /[02]/)	{
			 $out = unpack("f",pack("CCCC",($ieeeFlt[3], $ieeeFlt[2], $ieeeFlt[1], $ieeeFlt[0])));
		}
	} elsif ($f eq "f"){
			my @real ;
			if ($cpu_type =~ /[1]/){
         ($real[3], $real[2], $real[1], $real[0]) = unpack("CCCC",$in) ;
         $out = unpack("f",pack("CCCC", @real)) ;
			}	elsif ($cpu_type =~ /[02]/){
				$out = unpack("f", $in);
			}
  } elsif ($f eq "L") {
      @b   = unpack "C" x 4, $in;
      $out = unpack "I", (pack "CCCC", $b[3], $b[2], $b[1], $b[0]) if $cpu_type =~ /[1]/;
      $out = unpack "I", $in					     if $cpu_type =~ /[02]/;
  } elsif ($f=~/S/i) {
      @b   = unpack "C" x 2, $in;
      $out = unpack $f, (pack "CC", $b[1], $b[0]) if $cpu_type =~ /[1]/;
      $out = unpack $f, (pack "CC", $b[0], $b[1]) if $cpu_type =~ /[02]/;
  } else {
      $out = unpack("${f}${count}", $in);
  }
        

  $out =~ s/^\s+//g;      
  $out =~ s/\s+$//g;
        

	##############################
	# APPLY STDFV3+ INVALID VALUE
	##############################
	if ($v4_invalid_val ne "" && $plus_invalid_val ne "" && $v4_invalid_val==$out){
		$out = $plus_invalid_val;
	}

  ########################
  # RETURN UNPACKED VALUE 
  ########################
  return ($out);
}


sub loadSTDFV4Template(){
	my $rec_typ       = "";
	my $sub_rec_typ   = "";
	my $line;
	#my $rec_name;
	#my $template_file = "/data/edbmgr/code/master_scripts/convert/conv_stdf4.ref";
	my $templateFile = "/export/home/dpower/project/scripts/stdf_perl/conv_stdf4.ref";
	my $FH;
	
	open $FH, "<", $templateFile or dpExit(1,"Unable to locate conv_stdf4.ref template file");
	while($line=<$FH>){
  	chomp($line);
		next if $line =~ /^#/;
	
    if ($line =~ /\[.*\_START\_/i){
			my $junk = "";
			($junk, $rec_typ, $sub_rec_typ, $junk, $rec_name) = split /\[|\_|\]/, $line;
			$stdf_recs{$rec_typ."_".$sub_rec_typ}{NAME} = $rec_name;
    } elsif ($rec_typ ne "" && $sub_rec_typ ne "" && $line=~/\s+/){
			$stdf_recs{$rec_typ."_".$sub_rec_typ}{FORMAT} .= "$line\n";
    }
	}
	close($FH);
}





sub convertBinToAscii {
    my $infile   = shift;
    my $debugOption = shift;
    my $perl     = "perl";
    my $tempdir  = (dirname $infile)."/temp/";
    mkdir $tempdir unless ( -d $tempdir );
    my $outfile  = $tempdir.(basename $infile). ".txt";
    my $command  = "$perl -Ilib $Bin/stdf_perl/script/stdf_copy $infile $outfile ";
    my $ret = system($command);
    if ($debugOption) {
    	DEBUG("$command");
    }
    
    if ($ret) {
        unlink $outfile;
        #$ppLogger->setLot($lot);
  			#$ppLogger->setWafNum($wafer);
        #dpExit( 1, "Failed to convert $command : $!" );
        return "Failed to convert $command : $!";
    }
    #print "im here\n";
    return $outfile;
}
#
#
sub readStdfAscii_WM {
    my $file = shift;
    open FH, "<", $file or dpExit(1,"failed to open file. $file");
    INFO("STDF(Ascii): $file");
    my $stdf = new_stdf;
    my $rec   = {};
    my $table = "";
    my $wafer = new_stdfWafer;
    my $pirs = {};
    my $logkey;
    my $ignoreLogkey =0;
    my $num =0;
    my $mir = 0;
    my $wir = 0;
    my $i = 0;
    while (<FH>) {
        $num++;
        if (/^\t(\S+) :\tREC_LEN=(\d+)$/) {
            $table = $1;
            $rec = {};
	    if($1 eq "EWCR"){				
		INFO("EWCR");
	    }
        }
	if (/TEST_NAM=/){
	    my $wk = $_;
	    $wk =~ s/TEST_NAM=//;
	    $rec->{TEST_NAM} = $wk;				
	}
	elsif (/TEST_TXT=/){
	    my $wk = $_;
	       $wk =~ s/TEST_TXT=//;
	       $rec->{TEST_TXT} = $wk;				
	}
        elsif (/^\t\t(\S+)=(.*)$/) {
            $rec->{$1} = $2;	
        }		
        if (/^$/) {
            if (%$rec) {	
		if ( $table eq 'WIR' ) {
                    $wafer = new_stdfWafer;
                    $wafer->WIR($rec);
                    $wir = 1;
                }
                elsif ( grep {$_ eq $table } get_waferArray) {
                    $wafer->add($table,$rec);	
		    if($table eq "WMR"){
			INFO($rec->{"DIE_BIN[0]"});
			INFO($table);
		    }
                }
                elsif ( $table eq 'WRR' ) {
                    $wafer->WRR($rec);
                    $stdf->add('wafers', $wafer);
                    $wir = 0;
                    undef $wafer;
                } 
             elsif ( grep {$_ eq $table } get_headerItem) {
		if($table eq "EWCR"){
		    INFO("EWCR   105");
		}
                if ( $table eq 'MIR' or $table eq 'EMIR'){
                    $mir = 1;
                }
                if ( $table eq 'MRR'){
                    $mir = 0;
                    if ($wir){
		       unlink $file;
		       							###03-29-2017:jgarcia:return error msg and do not exit.
		       						 return("NO_WRR_AFTER_WIR");
                       #dpExit(1,"STDF:no WRR after WIR");
                    }
                    if (defined $wafer){
                       $stdf->add('wafers',$wafer);
                    }
		}
		$stdf->{$table} = $rec;
	    } 
	    else {
		WARN("STDF:Undefined table name : $table");
	    }
            $rec = {};
            }
	}
        
    }
    # no WRR after WIR
    if ($wir){
        unlink $file;
        ###03-29-2017:jgarcia:return error msg and do not exit.
        return("NO_WRR_AFTER_WIR");
        #dpExit(1,"STDF:no WRR after WIR");
    }
    if ($mir){
        unlink $file;
        ###03-29-2017:jgarcia:return error msg and do not exit.
        return("NO_MRR_AFTER_MIR/EMIR");
        #dpExit(1,"STDF:no MRR after MIR/EMIR");
    }
       
    return $stdf;
}
#
#
sub readStdfAscii {
    my $file = shift;
    open FH, "<", $file or dpExit(1,"failed to open file. $file");
    INFO("STDF(Ascii): $file");
    my $stdf = new_stdf;
    my $rec   = {};
    my $table = "";
    my $wafer = new_stdfWafer;
    my $pirs = {};
    my $logkey;
    my $ignoreLogkey =0;
    my $num =0;
    my $mir = 0;
    my $wir = 0;
    my $i = 0;
    while (<FH>) {
        $num++;
        if (/^\t(\S+) :\tREC_LEN=(\d+)$/) {
            $table = $1;
            #print "TABLE=$table";
            $rec = {};
        }
	if (/TEST_NAM=/){
	    my $wk = $_;
	       $wk =~ s/TEST_NAM=//;
	       #print "TEST_NAM=$wk\n";
	       $rec->{TEST_NAM} = $wk;				
	}
	elsif (/TEST_TXT=/){
	    my $wk = $_;
	       $wk =~ s/TEST_TXT=//;
	       $rec->{TEST_TXT} = $wk;	
	       #print "TEST_TXT=$rec->{TEST_TXT}\t$wk\n";			
	}
        elsif (/^\t\t(\S+)=(.*)$/) {
        	  #print "/^\\t\\t(\S+)=(.*)$/\n";
            $rec->{$1} = $2;
            #print "REC=rec->{$1}=$1||$2\n";
        }
        if (/^$/) {
            if (%$rec) {	
		if ( $table eq 'WIR' ) {
                    $wafer = new_stdfWafer;
                    $wafer->WIR($rec);
                    $wir = 1;
                }
                elsif ( grep {$_ eq $table } get_waferArray) {
                    $wafer->add($table,$rec);
                }
                elsif ( $table eq 'WRR' ) {
                    $wafer->WRR($rec);
                    $stdf->add('wafers', $wafer);
                    $wir = 0;
                    undef $wafer;
                }
                elsif ( $table eq 'PIR' ) {
		    $i++;
		    if( $i eq 1){
			$pirs = {};
		    }
                    if ($rec->{HEAD_NUM} eq 255 or $rec->{SITE_NUM} eq 255){
			$ignoreLogkey = 1;
                        $logkey= 1;
		    }
		    else {
                        $logkey= $rec->{HEAD_NUM}.".".$rec->{SITE_NUM};
                        $ignoreLogkey = 0;
                    }
					
                    my $res = new_stdfRes;
                    #print "REC=$rec\$LOGKEY=$logkey\n";
                    $res->PIR($rec);
                    $pirs->{$logkey} = $res;
                }
                elsif ( grep {$_ eq $table } get_resArray) {
                    if ($ignoreLogkey){
                        $logkey= 1;
		    }
		    else {
			$logkey= $rec->{HEAD_NUM}.".".$rec->{SITE_NUM};
		    }           
                    if (exists $pirs->{$logkey}){
                        $pirs->{$logkey}->add($table,$rec);
                    }
		    else {
			WARN("$num:$table: unmatched HEAD_NUM and SITE_NUM = $logkey");
                    }
                }
                elsif ( $table eq 'EPRR' or $table eq 'PRR' ) {
		    $i=0;
                    if ($ignoreLogkey){
                        $logkey= 1;
		    }
		    else {
			$logkey= $rec->{HEAD_NUM}.".".$rec->{SITE_NUM};
		    }           
                    if (exists $pirs->{$logkey}){
                        $pirs->{$logkey}->{$table} = $rec;
                        #print "PIRS==>>$pirs->{$logkey}->{$table}==$rec\n";
                        $wafer->add('res',$pirs->{$logkey});
                    }
		    else {
			WARN("$num:$table: unmatched HEAD_NUM and SITE_NUM = $logkey");
			ERROR("Corresponding PIR not found. ".join(",",%$rec));
                    }
                }
                elsif ( grep {$_ eq $table } get_headerArray) {
		    if($table eq "SBR" or $table eq "HBR") {
			if ($rec->{SITE_NUM} eq "255" or $rec->{HEAD_NUM} eq "255") { ## if any contain SITE_NUM=255 then load only those with SITE_NUM=255, 
			    $stdf->add($table,$rec);								
			}
			else{  #otherwise load them as they are.
			    $stdf->add($table."_each",$rec);	
			}
		    }
		    elsif($table eq "EPDR") {
			if(!( $rec->{TEST_NAM} =~ /BIN/)) {     ####  to remove BIN from parameter 
			    $stdf->add($table,$rec);
			}
		    }
		    else{
			$stdf->add($table,$rec);	
		    }
		    #INFO("table=".$table.",rec=".$rec);
                } 
		elsif ( grep {$_ eq $table } get_headerItem) {
                    if ( $table eq 'MIR' or $table eq 'EMIR'){
                        $mir = 1;
                    }
                    if ( $table eq 'MRR'){
                        $mir = 0;
                        if ($wir){
        		    unlink $file;
        		    						###03-29-2017:jgarcia:return error msg and do not exit.
        										return("NO_WRR_AFTER_WIR");
                            #dpExit(1,"STDF:no WRR after WIR");
                        }
                        if (defined $wafer){
                            $stdf->add('wafers',$wafer);
                        }
		    }
		    $stdf->{$table} = $rec;
		    if($table eq "EMIR"){
			INFO($rec->{PART_TYP});
		    }
		} 
		else {
		    WARN("STDF:Undefined table name : $table");
		}
                $rec = {};
            }
        }
    }
    # no WRR after WIR
    if ($wir){
        unlink $file;
        ###03-29-2017:jgarcia:return error msg and do not exit.
        return("NO_WRR_AFTER_WIR");
        #dpExit(1,"STDF:no WRR after WIR");
    }
    if ($mir){
        unlink $file;
        ###03-29-2017:jgarcia:return error msg and do not exit.
        return("NO_MRR_AFTER_MIR/EMIR");
        #dpExit(1,"STDF:no MRR after MIR/EMIR");
    }
       
    return $stdf;
}
#
#
sub readStdfAscii_fet_sort {
    my $file = shift;
    my $data_type = shift;
    open FH, "<", $file or dpExit(1,"failed to open file. $file");
    INFO("STDF(Ascii): $file");
    my $stdf = new_stdf;
    my $rec   = {};
    my $table = "";
    my $wafer = new_stdfWafer;
    my $pirs = {};
    my $logkey;
    my $ignoreLogkey =0;
    my $num =0;
    my $mir = 0;
    my $wir = 0;
    my $i = 0;
    while (<FH>) {
        $num++;
        if (/^\t(\S+) :\tREC_LEN=(\d+)$/) {
            $table = $1;
            $rec = {};
        }
	if (/TEST_NAM=/){
	    my $wk = $_;
	       $wk =~ s/TEST_NAM=//;
	       $rec->{TEST_NAM} = $wk;				
	}
	elsif (/TEST_TXT=/){
	    my $wk = $_;
	       $wk =~ s/TEST_TXT=//;
	       $rec->{TEST_TXT} = $wk;				
	}
        elsif (/^\t\t(\S+)=(.*)$/) {
            $rec->{$1} = $2;
        }
        if (/^$/) {
            if (%$rec) {	
		if ( $table eq 'WIR' ) {
                    $wafer = new_stdfWafer;
                    $wafer->WIR($rec);
                    $wir = 1;
                }
                elsif ( grep {$_ eq $table } get_waferArray) {
                    $wafer->add($table,$rec);
                }
                elsif ( $table eq 'WRR' ) {
                    $wafer->WRR($rec);
                    $stdf->add('wafers', $wafer);
                    $wir = 0;
                    undef $wafer;
                }
                elsif ( $table eq 'PIR' ) {
		    $i++;
		    if( $i eq 1){
			$pirs = {};
		    }
		    if($data_type eq "fet_sort"){
			#$logkey= $rec->{HEAD_NUM}.".".$rec->{SITE_NUM};
			#$ignoreLogkey = 0;
			$ignoreLogkey = 1;
			$logkey= 1;
		    }
		    #else{
			#if ($rec->{HEAD_NUM} eq 255 or $rec->{SITE_NUM} eq 255){
			elsif ($rec->{HEAD_NUM} eq 255 or $rec->{SITE_NUM} eq 255){
		            $ignoreLogkey = 1;
			    $logkey= 1;
			}
			else {
			    $logkey= $rec->{HEAD_NUM}.".".$rec->{SITE_NUM};
			    $ignoreLogkey = 0;
			}
		    #}
                    my $res = new_stdfRes;
                    $res->PIR($rec);
                    $pirs->{$logkey} = $res;
                }
                elsif ( grep {$_ eq $table } get_resArray) {
                    if ($ignoreLogkey){
                        $logkey= 1;
		    }
		    else {
			$logkey= $rec->{HEAD_NUM}.".".$rec->{SITE_NUM};
		    }           
                    if (exists $pirs->{$logkey}){
                        $pirs->{$logkey}->add($table,$rec);
                    }
		    else {
			WARN("$num:$table: unmatched HEAD_NUM and SITE_NUM = $logkey");
                    }
                }
                elsif ( $table eq 'EPRR' or $table eq 'PRR' ) {
		    $i=0;
                    if ($ignoreLogkey){
                        $logkey= 1;
		    }
		    else {
			$logkey= $rec->{HEAD_NUM}.".".$rec->{SITE_NUM};
		    }           
                    if (exists $pirs->{$logkey}){
                        $pirs->{$logkey}->{$table} = $rec;
                        $wafer->add('res',$pirs->{$logkey});
                    }
		    else {
			WARN("$num:$table: unmatched HEAD_NUM and SITE_NUM = $logkey");
			ERROR("Corresponding PIR not found. ".join(",",%$rec));
                    }
                }
                elsif ( grep {$_ eq $table } get_headerArray) {
		     if($table eq "SBR" or $table eq "HBR"){
			if ($rec->{SITE_NUM} eq "255" or $rec->{HEAD_NUM} eq "255") { ## if any contain SITE_NUM=255 then load only those with SITE_NUM=255, 
			    $stdf->add($table,$rec);								
			}
			else{  #otherwise load them as they are.
			    $stdf->add($table."_each",$rec);	
			}
		     }
		     elsif($table eq "EPDR"){
			if(!( $rec->{TEST_NAM} =~ /BIN/)){     ####  to remove BIN from parameter 
			    $stdf->add($table,$rec);
			}
		     }
		     else{
		        $stdf->add($table,$rec);	
		     }
		     #INFO("table=".$table.",rec=".$rec);
                }
		elsif ( grep {$_ eq $table } get_headerItem) {
                     if ( $table eq 'MIR' or $table eq 'EMIR'){
                        $mir = 1;
                     }
                     if ( $table eq 'MRR'){
                        $mir = 0;
                        if ($wir){
        		    unlink $file;
        		    						###03-29-2017:jgarcia:return error msg and do not exit.
        										return("NO_WRR_AFTER_WIR");
                            #dpExit(1,"STDF:no WRR after WIR");
                        }
                        if (defined $wafer){
                            $stdf->add('wafers',$wafer);
                        }
		     }
		     $stdf->{$table} = $rec;
		     if($table eq "EMIR"){
			INFO($rec->{PART_TYP});
		     }
		} 
		else {
		     WARN("STDF:Undefined table name : $table");
		}
                $rec = {};
            }
        }
    }
    # no WRR after WIR
    if ($wir){
        unlink $file;
        ###03-29-2017:jgarcia:return error msg and do not exit.
        return("NO_WRR_AFTER_WIR");
        #dpExit(1,"STDF:no WRR after WIR");
    }
    if ($mir){
        unlink $file;
        ###03-29-2017:jgarcia:return error msg and do not exit.
        return("NO_MRR_AFTER_MIR/EMIR");
        #dpExit(1,"STDF:no MRR after MIR/EMIR");
    }
       
    return $stdf;
}

sub readStdfAscii_bksort_tmt {
    my $file = shift;
    open FH, "<", $file or dpExit(1,"failed to open file. $file");
    INFO("STDF(Ascii): $file");
    my $stdf = new_stdf;
    my $rec   = {};
    my $table = "";
    my $wafer = new_stdfWafer;
    my $pirs = {};
    my $logkey;
    my $ignoreLogkey =0;
    my $num =0;
    my $mir = 0;
    my $wir = 0;
    my $i = 0;
    while (<FH>) {
        $num++;
        if (/^\t(\S+) :\tREC_LEN=(\d+)$/) {
            $table = $1;
            $rec = {};
        }
        if (/TEST_NAM=/){
            my $wk = $_;
               $wk =~ s/TEST_NAM=//;
               $rec->{TEST_NAM} = $wk;
        }
        elsif (/TEST_TXT=/){
            my $wk = $_;
               $wk =~ s/TEST_TXT=//;
               $rec->{TEST_TXT} = $wk;
        }
        elsif (/^\t\t(\S+)=(.*)$/) {
            $rec->{$1} = $2;
        }
        if (/^$/) {
            if (%$rec) {
                if ( $table eq 'WIR' ) {
                    #$wafer = new_stdfWafer;
                    $wafer->WIR($rec);
                    $wir = 1;
                }
                elsif ( grep {$_ eq $table } get_waferArray) {
                    $wafer->add($table,$rec);
                }
                elsif ( $table eq 'WRR' ) {
                    $wafer->WRR($rec);
                    $stdf->add('wafers', $wafer);
                    $wir = 0;
                    undef $wafer;
                }
                elsif ( $table eq 'PIR' ) {
                    $i++;
                    if( $i eq 1){
                        $pirs = {};
                    }
                    if ($rec->{HEAD_NUM} eq 255 or $rec->{SITE_NUM} eq 255){
			$ignoreLogkey = 1;
                        $logkey= 1;
                    }
                    else {
                        $logkey= $rec->{HEAD_NUM}.".".$rec->{SITE_NUM};
                        $ignoreLogkey = 0;
                    }

                    my $res = new_stdfRes;
                    $res->PIR($rec);
                    $pirs->{$logkey} = $res;
                }
                elsif ( grep {$_ eq $table } get_resArray) {
                    if ($ignoreLogkey){
                        $logkey= 1;
                    }
                    else {
                        $logkey= $rec->{HEAD_NUM}.".".$rec->{SITE_NUM};
                    }
                    if (exists $pirs->{$logkey}){
                        $pirs->{$logkey}->add($table,$rec);
                    }
                    else {
                        WARN("$num:$table: unmatched HEAD_NUM and SITE_NUM = $logkey");
                    }
                }
                elsif ( $table eq 'EPRR' or $table eq 'PRR' ) {
                    $i=0;
                    if ($ignoreLogkey){
                        $logkey= 1;
                    }
                    else {
                        $logkey= $rec->{HEAD_NUM}.".".$rec->{SITE_NUM};
                    }
                    if (exists $pirs->{$logkey}){
                        $pirs->{$logkey}->{$table} = $rec;
                        $wafer->add('res',$pirs->{$logkey});
                    }
                    else {
                        WARN("$num:$table: unmatched HEAD_NUM and SITE_NUM = $logkey");
                        ERROR("Corresponding PIR not found. ".join(",",%$rec));
                    }
                }
                elsif ( grep {$_ eq $table } get_headerArray) {
                    if($table eq "SBR" or $table eq "HBR") {
                        if ($rec->{SITE_NUM} eq "255" or $rec->{HEAD_NUM} eq "255") { ## if any contain SITE_NUM=255 then load only those with SITE_NUM=255,
                            $stdf->add($table,$rec);
                        }
                        else{  #otherwise load them as they are.
                            $stdf->add($table."_each",$rec);
                        }
                    }
		    elsif($table eq "EPDR") {
                        if(!( $rec->{TEST_NAM} =~ /BIN/)) {     ####  to remove BIN from parameter
                            $stdf->add($table,$rec);
                        }
                    }
                    else{
                        $stdf->add($table,$rec);
                    }
                    #INFO("table=".$table.",rec=".$rec);
                }
                elsif ( grep {$_ eq $table } get_headerItem) {
                    if ( $table eq 'MIR' or $table eq 'EMIR'){
                        $mir = 1;
                    }
                    if ( $table eq 'MRR'){
                        $mir = 0;
                        if ($wir){
        		    unlink $file;
        		    						###03-29-2017:jgarcia:return error msg and do not exit.
        										return("NO_WRR_AFTER_WIR");
                            #dpExit(1,"STDF:no WRR after WIR");
                        }
                        if (defined $wafer){
                            $stdf->add('wafers',$wafer);
                        }
                    }
                    $stdf->{$table} = $rec;
                    if($table eq "EMIR"){
                        INFO($rec->{PART_TYP});
                    }
                }
                else {
                    WARN("STDF:Undefined table name : $table");
                }
                $rec = {};
            }
        }
    }
    # no WRR after WIR
    if ($wir){
        unlink $file;
        ###03-29-2017:jgarcia:return error msg and do not exit.
        return("NO_WRR_AFTER_WIR");
        #dpExit(1,"STDF:no WRR after WIR");
    }
    if ($mir){
        unlink $file;
        ###03-29-2017:jgarcia:return error msg and do not exit.
        return("NO_MRR_AFTER_MIR/EMIR");
        #dpExit(1,"STDF:no MRR after MIR/EMIR");
    }

    return $stdf;
}	
	
1;
