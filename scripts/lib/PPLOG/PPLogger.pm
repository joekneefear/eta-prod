package PPLOG::PPLogger;

#use strict;
#use warnings;
use DBI;
use PDF::Log;
use Digest::MD5  qw(md5_hex);
use YAML::XS qw(LoadFile);
use Scalar::Util qw(blessed dualvar isdual readonly refaddr reftype
                    tainted weaken isweak isvstring looks_like_number
                    set_prototype);

#use Exporter qw(import);
#our @EXPORT = qw(setLot setEnv setProcDT setProcCode setRawFile setOutDir setLogMsg setMapID setWafNum pplogExit);

our $self;
our $INITIALIZED = 0;
our $model;
our $header;
our $ISTOBELOG=0;
our $waferFlag = 0;

#my $db_tns  = "dbi:Oracle:host=oruxymsora01d;port=1521;sid=YMS01DEV";
#my $db_tns  = "dbi:Oracle:host=oruxymsora01p;port=1521;sid=YMS01PRD";
# my $db_tns = "dbi:Oracle://exnprd-db.onsemi.com:1729/EXNPRD.onsemi.com";
# my $db_user = "refdb";
# my $db_pass = "88sgX%#$29-azx";
my $dbh;
my ($db_tns, $db_user, $db_pass) = "";
if ( defined( $ENV{REFDB_TNS} ) ) {
  $db_tns = $ENV{REFDB_TNS};
}
if ( defined( $ENV{REFDB_USER} ) ) {
  $db_user = $ENV{REFDB_USER};
}
if ( defined( $ENV{REFDB_PASS} ) ) {
  $db_pass = $ENV{REFDB_PASS};
}

my %attr = (
   PrintError  => 0,
   HandleError => \&handle_error,
);

my $ctx = Digest::MD5->new;

my $separator = "";
if (blessed($header) && $header->isa('HeaderLong')) { 
	$separator = "_";
} else {
	$separator = "-";
}



sub new {
	my $class = shift;
	my $flag = shift;
	return $self if ($INITIALIZED);
	$self = {
		_LOT => '',
		_SOURCE_LOT => '',
		_ENV => '',
		_PROC_CODE=> '',
		_RAW_FILE=> '',
		_OUT_DIR=> '',
		_LOG_MSG=> '',
		_MAP_ID=> '',
		_WAF_NUM=> '',
		_WAF_NUM_SL=> '',
		_PROG_CLASS=> '',
		_SITE => '',
		_PROG_NAME=>'',
		_LIMIT_FILE=>'',
		_EXT=>'',
		_MD5=>'',
		_PATH=>'',
		_SCRIPT=>''
	};
	$INITIALIZED=1;
	bless $self, $class;
	return $self;
}

sub settobeLog{
	my ($self,$flag) = @_;
	$ISTOBELOG = $flag;
}
sub setWaferFlag{
	my ($self,$flag) = @_;
	$waferFlag = $flag;
}

sub setModelHeader{
	my ($self,$mod) = @_;
	if($INITIALIZED){
		$model = $mod;
		$header = $mod->header;
	}
}

sub setLot{
	my ($self,$lot) = @_;
	if($INITIALIZED){
		$self->{_LOT} = $lot if defined($lot);
		return $self->{_LOT};
	}
}

sub setScript{
	my ($self,$script) = @_;
	if($INITIALIZED){
		$self->{_SCRIPT} = $script if defined($script);
		return $self->{_SCRIPT};
	}
}

sub setSourceLot{
	my ($self,$sourceLot) = @_;
	if($INITIALIZED){
		$self->{_SOURCE_LOT} = $sourceLot if defined($sourceLot);
		return $self->{_SOURCE_LOT};
	}
}

sub setEnv{
	my ($self,$site,$tester) = @_;
	if($INITIALIZED){
		my $env = '';
		if ($tester ne ''){
			if ($site =~ /$tester/ig){
				$env = $site;
			}else{
				$env = $site . '_' . $tester;
			}
		}else{
			$env = $site;
		}

		$self->{_ENV} = $env;
		return $self->{_ENV};
	}
}

sub setProcCode{
	my ($self,$proc_code) = @_;
	if($INITIALIZED){
		$self->{_PROC_CODE} = $proc_code if defined($proc_code);
		return $self->{_PROC_CODE};
	}
}

sub setRawFile{
	my ($self,$raw_file) = @_;
	if($INITIALIZED){
		$self->{_RAW_FILE} = $raw_file if defined($raw_file);
		return $self->{_RAW_FILE};
	}
}

sub setOutDir{
	my ($self,$out_directory) = @_;
	if($INITIALIZED && $self->{_OUT_DIR} eq ""){
		$self->{_OUT_DIR} = $out_directory if defined($out_directory);
		return $self->{_OUT_DIR};
	}
}

sub setLogMsg {
    my ($self, $log_msg) = @_;

    if ($INITIALIZED) {
        # Check if the new log message contains "second" or "third"
        my $is_lot_lookup = ($log_msg =~ /lot lookup/i);

        if ($is_lot_lookup) {
            # If the new log message contains "second" or "third",
            # always append it to _LOG_MSG
            if ($log_msg !~ /Delete original.*|gzip IFF file.*|outfile.*/ig) {
                $self->{_LOG_MSG} .= "--" . $log_msg;
            }
        }
        elsif ($self->{_LOG_MSG} ne '') {
            if ($self->{_LOG_MSG} !~ /$log_msg/i) {
                if ($log_msg !~ /Delete original.*|gzip IFF file.*|outfile.*/ig) {
                    $self->{_LOG_MSG} = $self->{_LOG_MSG} . "--" . $log_msg;
                }
            }
        }
        else {
            if ($log_msg !~ /Delete original.*|gzip IFF file.*|outfile.*/ig) {
                $self->{_LOG_MSG} = $log_msg if defined($log_msg);
            }
        }
        return $self->{_LOG_MSG};
    }
}

# sub setLogMsg{
# 	my ($self,$log_msg) = @_;
# 	if($INITIALIZED){
# 		if ($self->{_LOG_MSG} ne ''){
# 			if($self->{_LOG_MSG} !~ /$log_msg/i) {
# 				if($log_msg !~ /Delete original.*|gzip IFF file.*|outfile.*/ig) {
# 					$self->{_LOG_MSG} = $self->{_LOG_MSG} . "--" . $log_msg;
# 				}
# 			}
# 		}else{
# 			if($log_msg !~ /Delete original.*|gzip IFF file.*|outfile.*/ig) {
# 				$self->{_LOG_MSG} = $log_msg if defined($log_msg);
# 			}
			
# 		}
# 		return $self->{_LOG_MSG};
# 	}
# }

sub setMapID{
	my ($self,$map_id) = @_;
	if($INITIALIZED){
		$self->{_MAP_ID} = $map_id if defined($map_id);
		return $self->{_MAP_ID};
	}
}
### 03-22-2017:jgarcia: modified to have option to initialize _WAF_NUM with sourceLot_wafer# or lot_wafer#.
sub setWafNum{
	my ($self,$waf_num) = @_;
	if($INITIALIZED){
		#$self->{_WAF_NUM} = $self->{_LOT}."_".$waf_num if defined($waf_num);
		my $sourceLot = $self->{_SOURCE_LOT};
		$sourceLot =~ s/\.S$//;
		if (defined($waf_num)) {
			if ($sourceLot ne "" && $waferFlag != 0) {
				$self->{_WAF_NUM} = $sourceLot.$separator.$waf_num;
			} else {
				$self->{_WAF_NUM} = $self->{_LOT}.$separator.$waf_num;
			}

		}
		return $self->{_WAF_NUM};
	}
}

###03-21-2017 jgarcia added
sub setWafNumSL{
	my ($self,$waf_num) = @_;
	my $sourceLot = $self->{_SOURCE_LOT};
	$sourceLot =~ s/\.S$//;
	if($INITIALIZED){
		$self->{_WAF_NUM_SL} = $sourceLot."_".$waf_num if defined($waf_num);
		return $self->{_WAF_NUM_SL};
	}
}

sub setProgramClass{
	my ($self,$prog_class) = @_;
	if($INITIALIZED){
		$self->{_PROG_CLASS} = $prog_class if defined($prog_class);
		return $self->{_PROG_CLASS};
	}
}

sub setSITE{
	my ($self,$site) = @_;
	if($INITIALIZED){
		$self->{_SITE} = $site if defined($site);
		return $self->{_SITE};
	}
}

sub setProgramName{
	my ($self,$prog_name) = @_;
	if($INITIALIZED){
		$self->{_PROG_NAME} = $prog_name if defined($prog_name);
		return $self->{_PROG_NAME};
	}
}

sub setLimitFile{
	my ($self,$limit_file) = @_;
	if($INITIALIZED){
		if ($self->{_LIMIT_FILE} eq ''){
			$self->{_LIMIT_FILE} = $limit_file if defined($limit_file);
		}
		return $self->{_LIMIT_FILE};
	}
}

sub setExt{
	my ($self,$ext) = @_;
	if($INITIALIZED){
		$self->{_EXT} = $ext if defined($ext);
		return $self->{_EXT};
	}
}

sub setMD5{
	my ($self,$md5) = @_;
	if($INITIALIZED){
		if(defined($md5) && $md5 ne "") {
			$self->{_MD5} = $md5;
		}else {
			open FILE, "$self->{_RAW_FILE}";
			$self->{_MD5} = $ctx->hexdigest;
			close FILE;
		}
			
		return $self->{_MD5};
	}
}

sub setPath{
	my ($self,$path) = @_;
	if($INITIALIZED){
		$self->{_PATH} = $path if defined($path);
		return $self->{_PATH};
	}
}

sub connect {
	my $isconnected = 0;
    $dbh = DBI->connect($db_tns,$db_user,$db_pass, \%attr) or $isconnected = handle_error(DBI->errstr);
    return $isconnected;
}

sub handle_error{
	my $message = shift;
    #write error message wherever you want
    WARN("DBI error: $message");
    return 1;
}

sub pplogExit {
	my ($self,$proc_code) = @_;

	#INFO("PROCESS CODE=$proc_code");
	if($INITIALIZED){
		$self->setProcCode($proc_code);
		#$self->setLogMsg($msg) if defined($msg);
		if (defined($header)){
			$self->setLot($header->LOT);
			$self->setSourceLot($header->{SOURCE_LOT});
			$self->setProgramClass($header->{PROGRAM_CLASS});
			$self->setProgramName($header->{PROGRAM});
			
		}
		eval {$self->setWafNum(sprintf("%02d",$model->wafers->[0]->number));};
		if ($@ && $self->{_WAF_NUM} !~ /.+\_\d{1,}$/) {
			if ($self->{_WAF_NUM} =~ /^\_\d{1,}/) {
				$self->{_WAF_NUM} =~ s/\_//g;
			}
			#INFO("\$model->wafer[0]->number has no value");
			INFO("INFO to be logged=>SOURCE_LOT=$self->{_SOURCE_LOT}||WAFER=$self->{_WAF_NUM}||LOT=$self->{_LOT}");
			#print "PP_LOG: initialize wafer number:: \$model->wafer[0]->number has no value - assign \$self->{WAF_NUM} as wafer\n";
			
			if ($self->{_SOURCE_LOT} ne "" && $self->{_WAF_NUM} ne "") {
				$self->{_WAF_NUM} = $self->{_SOURCE_LOT}.$separater.$self->{_WAF_NUM};
			}else {
				$self->{_WAF_NUM} = $self->{_LOT}.$separator.$self->{_WAF_NUM};
			}

		} else {

			INFO("INFO to be logged=>SOURCE_LOT=$self->{_SOURCE_LOT}||WAFER=$self->{_WAF_NUM}||LOT=$self->{_LOT}");
		}

		if ($ISTOBELOG){
			&insert_db;
		}else{
			INFO("Not to be logged");
		}
	}
	#return $proc_code;
}

sub insert_db {
	$self = shift;
	my $flag = &connect;
	my $datex = &getdatetime();
	if ($flag eq 0){

		my $ERR_CODE="";
		my $time_zone ="America/New_York";

		if($self->{_SCRIPT} eq "fcs_metadataVerifier.pl") {
			$ERR_CODE = "E0000";
			if ($self->{_PROC_CODE} !~ /0|10|1011|100|4/){
				$self->{_OUT_DIR} = "NotProcessed";
			#$ERR_CODE = &geterrcode($self->{_LOG_MSG});
			} else {
				$ERR_CODE = &get_errcode_yaml($self->{_LOG_MSG});
			}
		
		} else {
			if ($self->{_OUT_DIR} =~ /PRODUCTION|QDE|SANDBOX|ReworkFiles|inbox/i){
				$ERR_CODE = &get_errcode_yaml($self->{_LOG_MSG});
			}else{
				$ERR_CODE = "E0000";
			}

			#if ($self->{_PROC_CODE} ne 0){
			#	$self->{_OUT_DIR} = "NotProcessed";
			#}
		}

		&parseInfile;

		if ($self->{_LOG_MSG} ne ''){
			$self->{_LOG_MSG}=~ s/'//g;
			$self->{_LOG_MSG} = substr($self->{_LOG_MSG},0,4000);
		}

		if ($self->{_SITE} eq ''){
			$self->{_SITE} = uc(substr($self->{_ENV},0,2));
		}

		if($self->{_MD5} eq "" && $self->{_RAW_FILE} ne "") {
			open FILE, "$self->{_RAW_FILE}";
			$self->{_MD5} = $ctx->hexdigest;
			close FILE;
		}

		#Adjust time zone
		unless (grep { $_ eq $self->{_SITE} } qw/ME MT SL/ ){
			$time_zone = "Asia/Hong_Kong";
		}

		my $sql = qq/
						INSERT INTO refdb.pp_log
						(LOT,WAFER_NUM,ENVIRONMENT,PROCESS_DATETIME,
						PROCESS_CODE,FILE_NAME,OUTPUT_DIRECTORY,LOG_MESSAGE,
						INSERT_ID,MAP_ID,ERROR_CODE,PROGRAM_CLASS,SITE,
						PROCESS_DATETIME_ADJUST,LIMIT_FILE_NAME,PROGRAM_NAME,EXTENSION,MD5,PATH,SCRIPT)
						values
						('$self->{_LOT}','$self->{_WAF_NUM}','$self->{_ENV}',TO_DATE('$datex','yyyy\/mm\/dd hh24:mi:ss'),
						'$self->{_PROC_CODE}','$self->{_RAW_FILE}','$self->{_OUT_DIR}','$self->{_LOG_MSG}','','$self->{_MAP_ID}',
						'$ERR_CODE','$self->{_PROG_CLASS}','$self->{_SITE}',
						FROM_TZ(CAST(TO_DATE('$datex','yyyy\/mm\/dd hh24:mi:ss') AS TIMESTAMP),'America\/New_York')AT TIME ZONE '$time_zone',
						'$self->{_LIMIT_FILE}','$self->{_PROG_NAME}','$self->{_EXT}','$self->{_MD5}','$self->{_PATH}','$self->{_SCRIPT}')
					/;

		my $sth = $dbh->prepare($sql);
		$sth->execute() or $flag = handle_error(DBI->errstr);
		$sth->finish();
		$dbh->disconnect;

		# if ($flag eq 0){
		# 	INFO("Successfully logged to refdb.pp_log");
		# }
	}
}

sub getdatetime{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	my $datex = sprintf("%04d/%02d/%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
	return $datex;
}

sub parseInfile{
	#$self = shift;
	my $path;
	my $rawfile=$self->{_RAW_FILE};
	my $ext;

	unless ($self->{_RAW_FILE} =~ /.*\.gz$/){
		if ($self->{_RAW_FILE}=~ /.*\.SPD;.*\.LSR/ig){
			if ($rawfile =~ /(.*)\;/ig){
				$rawfile = $1;
			}
			if ($rawfile =~ /(.*)\/(.*)\.(.*)/ig){
				$path=$1;
				$rawfile=$2;
				$ext = 'LSR;SPD';
			}
		}elsif ($self->{_RAW_FILE} =~ /(.*)\/(.*)\.(.*)/ig){
			$path=$1;
			$rawfile=$2;
			$ext =$3;
		}
	}elsif ($self->{_RAW_FILE} =~ /(.*)\/(.*)\.(.*)\.gz$/ig) {
		$path=$1;
		$rawfile=$2;
		$ext =$3;
	}

	if ($self->{_ENV} eq ''){
		if ($path =~ /\/data\/([^\/]*)/ig){
			$self->{_ENV} = $1;
		}
	}

	if ($ext =~ /(.*)_MD5-(.*)/ig){
		$ext = $1;
		my $md5 = $2;

		$self->{_MD5}=$md5;
	}

	$self->{_PATH}=$path;
	$self->{_RAW_FILE}=$rawfile;
	$self->{_EXT}=$ext;


	#return;
}

sub geterrcode{
	my ($info) = @_;
	chomp($info);

	if($info =~ /meta not found for lot|metadata not found/ig){
		return "E1001";
	}elsif ($info =~ /wmap not found/ig){
		return "E1002";
	}elsif ($info =~ /program name is blank/ig){
		return "E1003";
	}elsif ($info =~ /pir not found/ig){
		return "E1004";
	}elsif ($info =~ /unknown test flow code/ig){
		return "E1005";
	}elsif ($info =~ /cant get testplan revision/ig){
		return "E1006";
	}elsif ($info =~ /will be truncated/ig){
		return "E1007";
	}elsif ($info =~ /test.+code.+box/ig){ #test flow code is set for sandbox loading
		return "E1008";
	}elsif ($info =~ /invalid test mode/ig){
		return "E1009";
	}
}

sub get_errcode_yaml {
    my ($info) = @_;
    chomp($info);

    my $error_codes = LoadFile('/export/home/dpower/project/scripts/lib/PPLOG/error_codes.yml');

    for my $code (keys %$error_codes) {
        my $pattern = $error_codes->{$code};
        if ($info =~ /$pattern/i) {
			return $code;
        }
    }

    return ''; # No error code found
}

1;
