#!/home/dpower/dp94/bin/perl_db -w
BEGIN {
       unshift (@INC, "/home/dpower/dp94/lib/perl5lib");
}

###################################################################
# Name		: DpCount.pl 
# Description	: counts files with specified extension for IdsLoad 
#		  std sub directories each entry in IdsLoad cfg 
# Usage		: DpCount.pl <IdsLoad cfg file>  <email address (optional)>
#  
# Wed Mar  5 01:25:56 PST 2008
# $Id: DpCountDp.pl 676 2015-07-03 03:03:15Z dpower $
###################################################################

use strict;
use Net::SMTP;
use DBI;

my $cfg; 
my $total_stage = 0;
my $total_processed = 0;
my $total_notprocessed = 0;
my $time;
my $str;
my $mailFlag;
my @mailList;
my $mailprog = '/bin/mail';
my $title = "[FCS] Exensio DPDATA Loading Status";
my $errStr;

#####
my $gwdb = undef;
my $d = 0;
my @contextFlowCnt = ();
my @processedCnt = ();
my %cfg = ();
$cfg{'aem_user'} = "prod_aem";
$cfg{'aem_password'} = "prod_aem";
$cfg{'aem_host'} = "db300mmsrv10";
$cfg{'aem_sid'} = "exensio";
$cfg{'aem_port'} = "1521";
####

if ($ARGV[0]){
   $cfg = shift @ARGV;
   @mailList = @ARGV if @ARGV; 
}else{
   print "\nUsage: $0 <IdsLoad_cfg_file> <email_address (optional)>\n\n";
   exit;
}

open IN,${cfg} || die "cannot open $cfg $!";
$str = "\n";
$str .= $time = localtime;
$str .= "\n\n";
$str .= "[FILE PROCESSING STATUS]\n";
$str .= "========================\n\n";
$str .= sprintf "%42s %34s %7s %7s", "DIRECTORY  <EXT>", "STAGE", "PRC", "NPRC\n" ; 
$str .= "-"x92 . "\n";
while (<IN>){
       	 my @line = split /:/, $_;
	 unless ($line[0] =~ /(^$|^#)/){
            $line[0]=~s/\${?(\w+)}?/$ENV{"$1"}/; ##added hiro
	    if ($line[1] =~ /UpStat/){
		my @opt = split / /, $line[3]; 

		if ($line[3] =~ /-defectonly/){
#			&upstatcnt($opt[$#opt],"df_upstat");
		}elsif ($line[3] =~ /-zonalonly/){
#			&upstatcnt($opt[$#opt],"z_update_waf");
#			&upstatcnt($opt[$#opt],"z_update_lot")
		}elsif ($line[3] =~ /defect/){
#			&upstatcnt($opt[$#opt],"df_upstat");
#			&upstatcnt($opt[$#opt],"update_stats");
		}elsif ($line[3] =~ /zonal/){
#			&upstatcnt($opt[$#opt],"z_update_waf");
#			&upstatcnt($opt[$#opt],"z_update_lot");
#			&upstatcnt($opt[$#opt],"update_stats");
		}else{
#                        &upstatcnt($opt[$#opt],"update_stats");
		};
	    }elsif ($line[0] =~ /^NA/ ){
	        # skipping this line.
	    }else{
		$errStr .=  &reportErr($line[0],0); #0:all errors
	        my @result = &count_file($line[0], $line[2]);
		$total_stage = $total_stage + $result[0] ;
		$total_processed = $total_processed + $result[1];
		$total_notprocessed = $total_notprocessed + $result[2];
	 	$str .= sprintf "%-60s %-8s %7s %7s %7s", $line[0], "<$line[2]>", $result[0], $result[1], $result[2] . "\n";											   
            }
	    }
}

$str .= "-"x92 . "\n";
$str .= sprintf("%31s %45s %7s %7s", "TOTAL", $total_stage, $total_processed, $total_notprocessed . "\n");
$str .= "\n";


##Init();
##getContextFlow();
##getProcessedFile();
##disconnect();
##
##$str .= "\n[PROD_AEM.CONTEXT_FLOW]\n";
##$str .= "============================\n\n";
##$str .= "YYYY/MM/DD HH     PRC  MIS\n";
##$str .= "--------------------------\n";
##$str .= join("\n", @contextFlowCnt);
##
##$str .= "\n\n\n";
##$str .= "\n[PROD_AEM.PROCESSED FILE COUNT]\n";
##$str .= "============================\n\n";
##$str .= "YYYY/MM/DD HH     PRC_file  PROCESSED_12HOURS  dccontext_cnt  sum(dccontext_cnt)\n";
##$str .= "--------------------------\n";
##$str .= join("\n", @processedCnt);
##
##$str .= "\n\n\n";
##$str .= "[ERROR SUMMARY]\n";
##$str .= "===============";
##$str .= $errStr; #append error summary report
##$str .= "\n\n\n";
###$str .= "[SPACE SUMMARY]\n";
###$str .= "===============\n\n";
###$str .= &checkSpace();
##
print $str;
#hiro

if ( scalar(@mailList) > 0  ){
	if ($title) 
        {
           &sendmail($title,$str,@mailList)
        }
        else
        {
           &sendmail("$0 $cfg",$str,@mailList)
        }
}

#########################################################################################
# Name		: count_file
# Function	: counts files with specified extension for IdsLoad std sub directories
# Parameters	: stage -- staging directory
#		  extension -- file extension
# Returns	: # of files for Staging, Processed and NotProcessed directories
# Notes		:
# Revisions	:
#########################################################################################
sub count_file 
{
	# get my args
	my $stage = shift;
	my $ext   = shift;

	#
	my $staging = 0;
	my $processed = 0;
	my $notprocessed = 0;
	my $myfile = "";

	# check extension
	if ($ext eq "%"){ 
		# except . and ..
		$ext = "[^.]{1,2}" 
	}else{
		$ext = "\.${ext}"
	}

	# count for Staging Dir
	opendir DIR, $stage || die print "Unable to open dir:$!";

	while ($myfile = readdir DIR){
		chomp($myfile);
		if (
			( $myfile =~ /${ext}$/ ) && 
			( -f "${stage}\/${myfile}" )
							){
			${staging} ++
		}
	}
	closedir DIR;

	# count for Processed Dir
	opendir DIR,"${stage}/Processed";
	while ($myfile = readdir DIR){
		chomp($myfile);
		if (
			((( $myfile =~ /${ext}$/ ) || ($myfile =~ /${ext}\.gz$/ ))&& 
		   	( -f "${stage}\/Processed\/${myfile}" )) ||
                        ( $myfile =~ /gz$/ )
								){
			${processed} ++ 
		}
	}
	closedir DIR;
	
	# count for NotProcessed Dir
	opendir DIR,"${stage}/NotProcessed";
	while ($myfile = readdir DIR){
		chomp($myfile);
		# count files except .err 
		if (
			(( $myfile =~ /${ext}$/ ) || ( $myfile =~ /${ext}\.gz$/ ) )&&  
		        !( ($myfile =~ /\.err$/) | ($myfile =~/\.err\.gz$/) ) &&
		        ( -f "${stage}\/NotProcessed\/${myfile}" ) 
								){
			${notprocessed} ++ 
		}
	}
	closedir DIR;
	 
	return ($staging, $processed, $notprocessed)
}


#########################################################################################
# Name		: sendmail
# Function	: Output a message and send email to the address list
# Parameters	: subject -- subject of the email
#		  content -- message body
#		  toList  -- email list 
# Returns	: 
# Notes		:
# Revisions	:
#########################################################################################
sub sendmail
{
    # grab the args
    my $subject = shift(@_);
    #my $content = shift(@_);
	my $content = shift(@_);
    my @toList = @_;

    open(REPORT,"|$mailprog -t");
    print REPORT "To: @toList\n";
    print REPORT "From:  dpower\n";
    print REPORT "Subject: $subject\n";
    print REPORT $content;
    print REPORT ("\n\nRegards,\n");
    print REPORT ("Your DBA.\n");
    close(REPORT);

    return;
}

sub getProcessedFile
{  
  #log_text($d, "begin FDLE::FileReport::getJobRef");

  my $self = shift();
  my $ctrljob = shift();
  
  my $sql = undef;
  my $sth = undef;
  my $ret = 1;
  my $value = undef;
  
  if ($cfg{'aem_user'})
  {
    my $fetchArrayRef = undef;

    $sql =  "  
			 select day_time, processed_count, sum(processed_count) over() all_sum_12hours
			 from (
				   select day_time, count(datafilename) processed_count
				   from (
						 select distinct to_char(flow_start_time,'YYYY/MM/DD HH24') day_time , datafilename
						 from context_flow
						 where flow_start_time > sysdate -1/2
						 and lt_storage_time is not null
				  ) group by day_time       
			)  order by day_time  ";

	$sql = "  select day_time, processed_count, sum(processed_count) over() all_sum_12hours, dc_count, sum(dc_count) over() 
			 from (
				   select day_time, count(distinct datafilename) processed_count, count(dccontextid) dc_count
				   from (
						 select distinct to_char(flow_start_time,'YYYY/MM/DD HH24') day_time , datafilename, dccontextid
						 from context_flow
						 where flow_start_time > sysdate -1/2
						 and lt_storage_time is not null
				  ) group by day_time   
				  order by day_time
			) 	";

    #log_data($d, "sql", \$sql);
	
	$ret = justPrepare($sql, \$sth);
	
	if($ret)
	{	
		#$sth->bind_param(":CTRLJOB", $ctrljob);	
		$ret = justExecute($sth);
	}
    if ($ret)
    {
      $fetchArrayRef = $sth->fetchall_arrayref();
      #log_data($d, "fetchArray", $fetchArrayRef);
      $sth->finish;
      for (my $i = 0; $i <= $#{$fetchArrayRef}; $i++)
      { 
       # $value = ${$fetchArrayRef}[$i][0].",".${$fetchArrayRef}[$i][1];    
	
		push @processedCnt, "${$fetchArrayRef}[$i][0]     ${$fetchArrayRef}[$i][1]   ${$fetchArrayRef}[$i][2]   ${$fetchArrayRef}[$i][3]    ${$fetchArrayRef}[$i][4]";
		
		$ret = 2;
      } 
    }	
  }
return $ret;  
}


sub getContextFlow
{  
  #log_text($d, "begin FDLE::FileReport::getJobRef");

  my $self = shift();
  my $ctrljob = shift();
  
  my $sql = undef;
  my $sth = undef;
  my $ret = 1;
  my $value = undef;
  
  if ($cfg{'aem_user'})
  {
    my $fetchArrayRef = undef;

    $sql =  " select to_char(flow_start_time,'YYYY/MM/DD HH24') day_time,  "
			. "        count(flow_start_time)  Processed, count  "
			. "        ((decode(lt_storage_time, '',1))) as MissinginLT_STOAGE_TIME "
			. " from context_flow "
			. " where flow_start_time > sysdate -1/2 "
			. " group by to_char(flow_start_time,'YYYY/MM/DD HH24') "
			. " order by 1" ;

    #log_data($d, "sql", \$sql);
	
	$ret = justPrepare($sql, \$sth);
	
	if($ret)
	{	
		#$sth->bind_param(":CTRLJOB", $ctrljob);	
		$ret = justExecute($sth);
	}
    if ($ret)
    {
      $fetchArrayRef = $sth->fetchall_arrayref();
      #log_data($d, "fetchArray", $fetchArrayRef);
      $sth->finish;
      for (my $i = 0; $i <= $#{$fetchArrayRef}; $i++)
      { 
       # $value = ${$fetchArrayRef}[$i][0].",".${$fetchArrayRef}[$i][1];    
	
		push @contextFlowCnt, "${$fetchArrayRef}[$i][0]     ${$fetchArrayRef}[$i][1]   ${$fetchArrayRef}[$i][2] ";
		
		$ret = 2;
      } 
    }	
  }
return $ret;  
}

sub Init
{
  
  #log_text($d, "begin aem::Init");
  my $self = shift();

  my $connect = undef;
  my $ret = 1;

  if ($cfg{'aem_user'})
  {
    $connect = "dbi:Oracle:host=$cfg{'aem_host'};"
             . "sid=$cfg{'aem_sid'}"
             ;
    if ($cfg{'aem_port'})
    {
      $connect .= ";port=$cfg{'aem_port'}";
    }
    #log_data($d, "Connection String", \$connect);

    $gwdb = DBI->connect($connect
                        ,$cfg{'aem_user'}
                        ,$cfg{'aem_password'}
                        ,{AutoCommit => 0
                         ,RaiseError => 0
                         ,PrintError => 0
                         }
                        );
    if ($DBI::errstr)
    {
      #log_data(1, "DB ERROR ", \$DBI::errstr);
      $ret = 0;
    }
    else
    {
      $ret = 1;
    }
  }
  #log_text($d, "end aem::Init");
  return $ret;
}


sub disconnect
{
 
  #log_text($d, "begin aem->disconnect");
  my $self = shift();

  my $ret = undef;

  $gwdb->rollback;
  $gwdb->disconnect;

  if ($DBI::errstr)
  {
    #log_data(1, "DB ERROR ", \$DBI::errstr);
    $ret = 0;
  }
  else
  {
    $ret = 1;
  }
  #log_text($d, "end aem->disconnect");
  return $ret;
}


sub justPrepare
{
  #log_text($d, "justPrepare");
  
  my $sql = shift();
  my $shr = shift();

  my $sth = undef;
  my $return = undef;

  $sth = $gwdb->prepare($sql);
  if ($DBI::errstr)
  {
    #log_data(1, "PREPARE ERROR ", \$DBI::errstr);
    $return = 0;
  }
  else
  {
    ${$shr} = $sth;
    $return = 1;
  }
  #log_data($d, "return", \$return);
  return $return;
}

sub justExecute
{
  #log_text($d, "justExecute");

  my $sth = shift();

  my $return = undef;

  $sth->execute;
  if ($DBI::errstr)
  {
    #log_data(1, "EXECUTE ERROR ", \$DBI::errstr);
    $return = 0;
  }
  else
  {
    $return = 1;
  }
}

sub reportErr()
{
        my $dir = shift;
        my $topN = shift;
	my @errArray;
	my $fileName;
	my $errMsg;
	my %errCnt;
        my $gotErr;
	my $i; 
	my $str; 


	$dir = $dir . "/NotProcessed";
        opendir DIRHANDLE, $dir || die "cannot open $dir:$!";
        while ( defined ( $fileName = readdir(DIRHANDLE)) )
        {
            if ( $fileName =~ /err$/ )
            {
               #print "opening $fileName\n";
               $fileName="$dir\/$fileName";
               open ERR, $fileName || die "cannot open file: $fileName: $!";
               $gotErr = 0;
	       @errArray = ();	
               while(<ERR>)
               {
                  #print "=======INSIDE WHILE";
                  chomp;
                  #print $_ . "\n";
		  if (/^#/) {next};	
		  if (/.+\t.+\t.+\t.+\t.+\t.+/){
                     @errArray = split /\t/, $_;
                     if ((( $errArray[2] eq "E" ) && ( $errArray[5] ne  "" ) && ($gotErr == 0)) || (( $errArray[2] eq "E" ) && ( $errArray[5] =~ /SENSORFIX/)))
                     {
                        @errArray = split /\t/, $_;
                        #print "$errArray[1] $errArray[2] $errArray[5]\n" ;
                        #$errMsg = "$errArray[1] $errArray[5]";
                        $errMsg = &generalErr($errArray[5]);
                        if (exists $errCnt{$errMsg})
                        {
                           #print "adding 1\n";
                           $errCnt{$errMsg} = $errCnt{$errMsg} + 1;
                        }else{
                           #print "initialize errCnt hash\n";
                           $errCnt{$errMsg} = 1;
                        }
                        $gotErr = 1;  #checking only first error message in err file
                     }
		  }

                  }
               close ERR;
            }
        }

        #foreach (keys %errCnt)
        $i =  0;

        $str = "\n\nCnt    Error   [$dir]           \n";
        $str .= "--------------------------------------------------------------------\n";
        foreach (sort { $errCnt{$b} <=>  $errCnt{$a} } keys %errCnt)
        {
           $i ++;
           if ($topN == 0)
	   {
              $str .= "$errCnt{$_}   $_\n";
	   }
	   elsif ($i <= $topN)
	   {
              $str .= "$errCnt{$_}   $_\n";
	   }
           #print "i = $i, topN=$topN \n";
        }

	if ($i != 0){ return $str };
}

sub generalErr()
{
        my $orgErr = shift;
        my $newErr = "";
        chomp $orgErr;
        if ($orgErr =~ /^Defect \d+ diexy locations (.+) not found in die map look up table/)
        {
            $newErr = "Defect xx diexy locations (xx,xx) not found in die map look up table";
	}	
        elsif ($orgErr =~ /.*Couldn't lookup Base Route for child lot :.*/)
	{
	    $newErr ="Couldn't lookup Base Route for child lot : xxxx";
	}
        elsif ($orgErr =~ /ORA-00904: "T.+": invalid identifier/)
	{
	    $newErr = "ORA-00904: \"Txx\": invalid identifier";	
	}
        elsif ($orgErr =~ /ZERO DATA POINTS FOUND .*/)
	{
	    $newErr = "ZERO DATA POINTS FOUND";	
	}
        else
	{
            $newErr = $orgErr;
        }
	return $newErr;
}

sub checkSpace()
{
	my $str;
	$str = `df -kh | egrep '(Filesystem|project15|/projects/csn|sda3|sda11|sdb1|sdc1|sdd1)' `;
	print $str;
	return $str;
}
