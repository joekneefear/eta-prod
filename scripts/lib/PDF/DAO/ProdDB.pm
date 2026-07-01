# 2016-09-29 jgarcia : initial
# 2016-11-11 jgarcia : sanitize revision before assigning to limit hash.
# 2016-11-14 jgarcia : modified getPGKEY_REL_DB, getPGKEY, to distinguish PCM against PCM for PSA.
package PDF::DAO::ProdDB;
use strict;
use File::Basename qw/basename/;
use PDF::Log;
use PDF::DpLoad;
use base qw/DBIx::Simple/;
use Try::Tiny;
#use SQL::Interp ':all';
our $VERSION = "1.0";

sub connect {
    my ( $class, @args ) = @_;
    return $class->SUPER::connect(@args);
}

sub getPGKEY {
	my $self = shift;
	my $program = shift;
	my $pgClassPrefix = shift;
	my $hash;
	my $ftClass = 2;
	my $wsClass = 1;
	my $etClass = 5;
	my $prefix = "";
	
	#print "\n>>INSIDE get PGKEY=$pgClassPrefix<<\n";
	if($pgClassPrefix eq "PCM") {
		
		my $sqlGetpgGrpKey = qq/select pg_grp_key from production.program where (ppid like '%$program%') and (pgc_key = '$etClass') 
		                     and (rownum = 1)/;
	  my $pgGrpKey = $self->query($sqlGetpgGrpKey)->list;
	  #print "pgGrpKey = $pgGrpKey\n";
	  if ($pgGrpKey != "135") {
	  	#$prefix = "PCMP";	
	  	$program = "PCMP::".$program;
	  } else {
	  	$program = "PCM::".$program;
	  }
	  
	  	
	} else {
		#$prefix = $pgClassPrefix;
		$program = $pgClassPrefix."::".$program;
	}
		
	
	#print "PROGRAM WITH PREFIX = $program\n";
	
	my $sql  = qq/ select pg_key, ppid from production.program where (ppid = '$program') and (pgc_key = '$wsClass'
									or pgc_key = '$ftClass' or pgc_key = '$etClass')/;
	
	my ($pgKey, $pgName) = $self->query($sql)->list;
	#$result->bind(my ($pgKey, $pgName));
	#print "$pgKey\t$pgName\n";
	return $pgKey, $pgName;
	
}

sub getPGKEY_REL_DB {
	my $self = shift;
	my $program = shift;
	my $pgClassPrefix = shift;
	#my $revision = shift;
	my $hash;
	my $ftClass = 2;
	my $wsClass = 1;
	my $etClass = 5;
	
	if($pgClassPrefix eq "PCM") {
		
		my $sqlGetpgGrpKey = qq/select pg_grp_key from reliability.program where (ppid like '%$program%') and (pgc_key = '$etClass') 
		                     and (rownum = 1)/;
	  my $pgGrpKey = $self->query($sqlGetpgGrpKey)->list;
	  #print "pgGrpKey = $pgGrpKey\n";
	  if ($pgGrpKey != "135") {
	  	#$prefix = "PCMP";	
	  	$program = "PCMP::".$program;
	  } else {
	  	$program = "PCM::".$program;
	  }
	  
	  	
	} else {
		#$prefix = $pgClassPrefix;
		$program = $pgClassPrefix."::".$program;
	}
		
	
	#print "PROGRAM WITH PREFIX = $program\n";
	
	#print "\n>>getPGKEYTEST>$program<<\n";
		
	my $sql  = qq/ select pg_key, ppid from reliability.program where (ppid = '$program') and (pgc_key = '$wsClass'
									or pgc_key = '$ftClass' or pgc_key = '$etClass')/;
	
	my ($pgKey, $pgName) = $self->query($sql)->list;
	#$result->bind(my ($pgKey, $pgName));
	#print "$pgKey\t$pgName\n";
	return $pgKey, $pgName;
	
}


sub getPrevkey {
	my $self = shift;
	my $programKey = shift;
	my $rev = shift;
	my $hash;
	my $ftClass = 2;
	my $wsClass = 1;
	my $etClass = 5;
	#$rev = "'$rev'";	
	#my $sql  = q/ select prev_key from production.prog_rev where (pg_key = $programKey and revision = \'$rev\') /;
	#my $sql  = ""select prev_key from production.prog_rev where (pg_key = $programKey and revision = \'$rev\'";
	
	my ($prevKey) = $self->query('select prev_key from production.prog_rev where pg_key = ? and revision = ?', $programKey, $rev)->list;
	#$result->bind(my ($pgKey, $pgName));
	#print "$pgKey\t$pgName\n";
	return $prevKey;
}

sub runGetLimitFunction {
	
	my $self = shift;
	my $pgkey = shift;
	my $prevKey = shift;
	my $table = "production.def"."$pgkey";
	my $errorFlag = 0;
	my $errorMessage = "";
	my $result = "";
	my @results = ();
	
	my $sql = qq (select d.test_index, d.cond0, d.cond1, d.cond2, r.revision
						, REFDB.GET_LIMIT('PRODUCTION', ll.pg_key, ll.lim_key, d.test_index, 'LSL') AS LSL
						, REFDB.GET_LIMIT('PRODUCTION', ll.pg_key, ll.lim_key, d.test_index, 'USL') AS USL
						, ll.lim_date, ll.insert_time	from $table d, production.lim_log ll, production.prog_rev r 
						where ll.pg_key = $pgkey 
						and ll.prev_key = $prevKey and ll.pg_key = r.pg_key
						and cond2 is not null	order by revision);    ####, cast(cond2 as float));
						
  $errorFlag = 0;
  eval {
		@results = $self->query($sql)->flat; #or do {$errorMessage = "query failed"};
  };
  if($@) {
  	warn $@;
  	print "Error on query but the Program has limits loaded\n";
  	$errorFlag = 1;
  }
  # catch {print "got Error $_\n"; $errorFlag = 1;}
	#print "$self->";
	#if($errorMessage =~ /query failed/ && $result ne "") {
	#	print("ERROR_MESSAGE=>$errorMessage\n");
	#	$errorFlag = 1;
	#}
#	if($result =~ /DBD::Oracle::st execute failed/i ) {
#		print ">>$result\n";
#		$errorFlag = 1;
#	}
	
	return $results[4], $results[8], $errorFlag;
	
}

#sub getLimit {
#	my $self = shift;
#	my $name;
#	my $rev;
#	my %limitHash = ();
#	my @arrRev = ();
#	my $sql = qq/ select distinct program from REFDB.PP_LIMITS where program not like 'ToDrop%' and rownum <= 5 order by program asc/;
#	
#	my $result = $self->query($sql);
#	#$result->bind($name, $rev);
#	#print "Name=>$name\tRev=>$rev\n";
#	my @arry = ();
#	while ($result->into($name)) {
#		#print "Name=>$name<<||Rev=>$rev<<\n";	
#		 my $sql2 = qq/ select revision from REFDB.PP_LIMITS where program = '$name'/;
#		 @arrRev = $self->query($sql2)->flat;
#		 #push @arry, $rev;		 
#		 $limitHash{$name} = \@arrRev;
#	}
#	
#	return %limitHash;
#}

sub getLimit {
	my $self = shift;
	my $name;
	my $rev;
	my $insertTime;
	my $env;
	my $keyString = "insertTime";
	my %limitHash = ();
	my @arrRev = ();
	#my $sql = qq/ select program, revision, to_char(insert_time,'yyyy\/mm\/dd hh24:mi:ss') from REFDB.PP_LIMITS where (program not like 'ToDrop%')
	#							and (program not like '%WKS') and (insert_time >= SYSDATE - 1) and (pplog.)order by program asc/;
#	 my $sql = qq/ select pplim.program, pplim.revision, to_char(pplim.insert_time,'yyyy\/mm\/dd hh24:mi:ss'), 
#	               pplog.environment from REFDB.PP_LIMITS pplim, REFDB.PP_LOG pplog 
#	               where (pplim.program not like 'ToDrop%') and (pplim.program not like '%_REL_%') and (pplim.program not like '%WKS') 
#	               and (pplim.insert_time >= SYSDATE - 1) and (pplog.program_name = pplim.program) 
#	               order by pplim.program asc/;
	               
	  my $sql = qq/ select program, revision, to_char(insert_time,'yyyy\/mm\/dd hh24:mi:ss') 
	               from REFDB.PP_LIMITS 
	               where (program not like 'ToDrop%') and (program not like '%_REL_%') and (program not like '%WKS') and (program not like '%::COC_%')
	               and (program not like '%CAM') and (insert_time >= SYSDATE - 1) 
	               order by program asc/;
	#  my $sqlEnv = qq / select environment from refdb.pp_log where 
	
	my $result = $self->query($sql);
	#$result->bind($name, $rev);
	#print "Name=>$name\tRev=>$rev\n";
	my @arry = ();
	while ($result->into($name, $rev, $insertTime)) {
		#$name = s/^\s+|\s+$//g;
		#$rev = s/^\s+|\s+$//g;
		#print "TEST::Name=>$name<<||Rev=>$rev<<\n";	
		 #my $sql2 = qq/ select revision from REFDB.PP_LIMITS where program = '$name'/;
		 #@arrRev = $self->query($sql2)->flat;
		 #push @arry, $rev;
		 
		 
		 my $sqlEnv = qq/ select environment from refdb.pp_log where program_name = '$name' and rownum = 1 /;
		 
		 my $ppLogEnv = $self->query($sqlEnv)->list;
		 
		 #$resultEnv->into($env);
		 $env = $ppLogEnv;
		 
		 my $key = $name."--".$insertTime."--".$env;
		 $rev = trim($rev);
		 #print "TRIMMED REV>>$rev<<\n";
		 $limitHash{$key} .= ($limitHash{$key} eq "") ? $rev : ",$rev";
		 #$limitHash{$dateKey} = "$insertTime";
	}
	
	return %limitHash;
}


sub testGetProduction {
	my $self = shift;
	my @test;
	my $sql = qq / select pg_key, ppid from production.program where (ppid like '%H_GF001HFT_D02_GN364_F1FT::EAGLE%') and (pgc_key = 1 or pgc_key = 2 or pgc_key = 5)/;
	my ($pgkey, $ppid) = $self->query($sql)->list;
	return $pgkey, $ppid;
}


sub updateProgramNameInPP_LIMITS {
	my $self = shift;
	my $programName = shift;
	my $revision = shift;
	my $dateKey = shift;
	my $currentDate = shift;
	#$programName = "To_Drop_$programName";
	#my $newProgramName = "ToDrop_".$programName."_".$revision."_".$dateKey;
	my $newProgramName = "ToDrop_".$programName."_DropDate_".$currentDate;
	
	#print ">>$programName<<\n";
	#print ">>$revision<<\n";
	#print ">>$dateKey<<\n";
	my $updateSQL = qq /update refdb.pp_limits set program = '$newProgramName' where program ='$programName' and revision='$revision'
											and to_char(insert_time,'yyyy\/mm\/dd hh24:mi:ss') = '$dateKey'/;
	
			$self->query( $updateSQL ); #or do {
			#ERROR( "Failed to updatePP_LIMITS: " . $self->error );
			#return 0;
		#};

}

sub trim {
    my ($text) = @_;

    if ($text) {
        $text =~ s/[\n\r]//gs;
        $text =~ s/^\s+//gs;
        $text =~ s/\s+$//gs;
        $text =~ s/\"$//gs;
        $text =~ s/^\"//gs;
        $text =~ s/[^\x09-\x7E]//gs;
    }
    return $text;
}

1;

__END__


