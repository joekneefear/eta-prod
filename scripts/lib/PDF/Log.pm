package PDF::Log;

use strict;
use Exporter 'import';
use Log::Log4perl;
use Log::Log4perl::Level;
use File::Basename qw/dirname basename/;
use Carp;
our @EXPORT = qw/INFO WARN DEBUG ERROR TRACE LOGDIE LOGWARN get_logger isLogDebug/;
our $VERSION="1.0";

our $log;
our $INITIALIZED = 0;
our $pplog;     # wsanopao:

# Default log configuration
my %config_kv = ( 
	"log4perl.rootLogger" => "INFO, CONSOLE",
	"log4perl.appender.Logfile" => "Log::Dispatch::FileRotate",
	"log4perl.appender.Logfile.max"         => 5,
	"log4perl.appender.Logfile.mode"        => "append",
	"log4perl.appender.Logfile.size"        => 10,
	"log4perl.appender.Logfile.DatePattern" => "yyyy-MM-dd",
	"log4perl.appender.Logfile.layout" =>   "Log::Log4perl::Layout::PatternLayout", 
	"log4perl.appender.Logfile.layout.ConversionPattern" => '%d %5p %m %n',
	"log4perl.appender.CONSOLE"     => "Log::Log4perl::Appender::Screen",
	"log4perl.appender.CONSOLE.layout" => "Log::Log4perl::Layout::PatternLayout",
	"log4perl.appender.CONSOLE.layout.ConversionPattern" => '%5p %m%n',
);

##################################################
sub init { # Define logfile name, or configuration file)
##################################################
	# wsanopao: added parameter for pplogger object
    my($class, $config,$pplog_object) = @_;
	return $log if ($INITIALIZED); 
	if (ref($config) eq "HASH"){
 		if (defined($config->{LOGFILE})){
			initByLogFile($config->{LOGFILE});
		} elsif (defined($config->{LOGCONF})){
			initByLogConf($config->{LOGCONF});
		} else {
			initDefault();
		}
		$log = Log::Log4perl::get_logger(basename($0));
		$log->level($DEBUG) if (defined($config->{DEBUG}));
		$log->level($TRACE) if (defined($config->{TRACE}));
	} elsif ($config =~ /\.log$/) {
		initByLogFile($config);
		$log = Log::Log4perl::get_logger(basename($0));
	} else {
		initDefault();
		$log = Log::Log4perl::get_logger(basename($0));
    }
	$log->info("########### Start ".basename($0)." #########");
	$log->info("logfile = ".$config_kv{"log4perl.appender.Logfile.filename"});
	$INITIALIZED=1;
	
	# wsanopao: pplogger Object
	$pplog = $pplog_object;
	return $log;	

}
sub initDefault{
	Log::Log4perl->init(\%config_kv);
	print "log initilized by default mode: only screen log\n";
}
sub initByConfigFile{
	my $conf = shift;
	Log::Log4perl->init($conf);
	print "log initilized by config mode: $conf\n";
}
sub initByLogFile{
	my $file = shift;
	$config_kv{"log4perl.rootLogger"} = "INFO, Logfile, CONSOLE";
	$config_kv{"log4perl.appender.Logfile.filename"} = $file;
	Log::Log4perl->init(\%config_kv);
	print "log initilized by filename mode: $file\n";
}

sub INFO{
	my $msg = shift;
	if($INITIALIZED){ 
		if(($msg =~ /found|sending to sandbox|metastrip|invalid|sandbox|SEND ANYWAY-Forcibly sent|metadata verifier|lot lookup|lot verification|ReworkFiles|File is not accepted and will remain|Skipping metadata check/ig) && ($msg !~ /Delete|gzip|NEW/ig)){
			$pplog->setLogMsg($msg) if defined($pplog);  # wsanopao: Capture messages
		}elsif($msg =~ /outfile.*\/(.*\.limit)/ig){
			if($pplog->{_LIMIT_FILE} eq '') {
				$pplog->setLimitFile($1) if defined($pplog);
			}
		}elsif(($msg =~ /outfile.+(\/archives-yms\/data\/.*\/PRODUCTION)\/.*/ig) || ($msg =~ /outfile.+(\/archives-yms\/data\/.*\/SANDBOX)\/.*/ig) || ($msg =~ /outfile.+(\/archives-yms\/data.*)\/.*/ig) || ($msg =~ /outfile.+(\/apps\/exensio_data.*)\/.*/ig)){
			if($pplog->{_OUT_DIR} eq '') {
				$pplog->setOutDir($1) if defined($pplog);
			}
		}
		$log->info($msg); 
	}
}

sub WARN{
	my $msg = shift;
	if($INITIALIZED){
		if (($msg =~ /found|sending to sandbox|invalid|sandbox|metastrip|SEND ANYWAY-Forcibly sent|metadata verifier|lot lookup|lot verification|ReworkFiles|File is not accepted and will remain|Skipping metadata check/ig) && ($msg !~ /Delete|gzip|NEW/ig)){  #considering cpsort_fet
			$pplog->setLogMsg(substr($msg,0,2000)) if defined($pplog);  # wsanopao: Capture messages
		}elsif(($msg =~ /outfile.+(\/archives-yms\/data\/.*\/PRODUCTION)\/.*/ig) || ($msg =~ /outfile.+(\/archives-yms\/data\/.*\/SANDBOX)\/.*/ig) || ($msg =~ /outfile.+(\/archives-yms\/data.*)\/.*/ig) || ($msg =~ /outfile.+(\/apps\/exensio_data.*)\/.*/ig)){
			if($pplog->{_OUT_DIR} eq '') {
				$pplog->setOutDir($1) if defined($pplog);
			}
		}
		$log->warn($msg); 
	}
}

sub DEBUG{
	if($INITIALIZED){
		$log->debug(shift);
	}
}

sub TRACE{
	if($INITIALIZED){
		$log->trace(shift);
	}
}

sub ERROR{
	my $msg = shift;
	if($INITIALIZED){ 
		if ($msg =~ /Corresponding PIR not found/ig){  #hana_th_ft_advan
			$pplog->setLogMsg("Corresponding PIR not found") if defined($pplog);
		}else{
			$pplog->setLogMsg(substr($msg,0,2000)) if defined($pplog);  # wsanopao: Capture messages
		}
		$log->error($msg); 
	}
}

sub LOGDIE{
	my $msg = shift;
	if($INITIALIZED){ 
		$pplog->setLogMsg(substr($msg,0,2000)) if defined($pplog);	  # wsanopao: Capture messages
		$log->logdie($msg); 
	}
}

sub LOGWARN{
	my $msg = shift;
	if($INITIALIZED){ 
		$pplog->setLogMsg(substr($msg,0,2000)) if defined($pplog);  # wsanopao: Capture messages
		$log->logwarn($msg); 
	}
}

sub get_logger{
	return $log;
}
sub isLogDebug{
   	if($INITIALIZED and 
            ( $log->level eq $DEBUG 
           or $log->level eq $TRACE )){
	  return 1;
	} else {
	  return 0;
	}
}
sub setLevelDebug{
	$log->level($DEBUG);
}
sub setLevelTrace{
	$log->level($TRACE);
}

1;

__END__;

=pod

=head1 NAME

PDF::Log - Wrapper module of L<Log::Log4perl|http://search.cpan.org/perldoc?Log::Log4perl> module

=head1 SYNOPSYS
 
default mode 

  use PDF::Log;
  
  PDF::Log->init;     
     # screen log only, verbosity = INFO 

  INFO("this is info level message");

  DEBUG("Debug level message");

  TRACE("very detail message");

  # screen output 
   INFO this is infor level message

specify log file and verbosity

  PDF::Log->init({logfile => '$DPLOG/sample.log' 
                  debug => 1);
     # auto log rotate max : 5
     # log file size : 10
     
  # screen ouput
   INFO this is infor level message
   DEBUG Debug level mesage

  # logfile
   2015/03/29 22:42:27  INFO  this is infor level message
   2015/03/29 22:42:27  DEBUG Debug level mesage

specify external log configuration file

  PDF::Log->init({logconf => 'log4perl.conf'}); 

refer L<Log::Log4perl|http://search.cpan.org/~mschilli/Log-Log4perl-1.46/lib/Log/Log4perl.pm> for log4perl.conf 

combination with Getopt::Long

  use Getopt::Long qw/:config ignore_case auto_help/;
  use PDF::Log;
  my %hOptions;
  GetOptions(\%hOptions, 
    "LOGFILE=s",
    "DEBUG",
    "TRACE",
    "someOptionsForApplication"
  );

  PDF::Log->init(\%hOptions);

=head1 Method

=head2 init(\%hash);

=over 4

=item logfile

full path to log file.
If not specified, no file logging.
If the directory does not exist, init method fail.

=item logconf

full path to log configuration file.

=item debug

set log verbosity DEBUG

=item trace

set log verbosity TRACE

=back

=head2 logging method

  ERROR();
  WARN();
  INFO();
  DEBUG();
  TRACE();
  LOGDIE();   # FATAL message and die
  LOGWARN();  # WARN message and warn
  
  # \n will be added at the end of message.
  # if PDF::Log->init it not called, all method do nothing.
 
=head2 isLogDebug
  
return true (1)  if log verbosity is DEBUG or TRACE.
otherwise, falese(0)

typical use case

  ## Bad implementation
  foreach my $key (keys %someHash){
     DEBUG("$key = ".$someHash($key));
  }

  ## Good implementation
  if (isLogDebug){
    foreach my $key (keys %someHash){
      DEBUG("$key = ".$someHash($key));
    }
  }


=head1 AUTHOR

B<kazuki.kunitoshi@pdf.com>

=head1 CHANGES

2015/03/31 kazukik: 1st verion

=head1 LICENSE

(C) PDF Solutions Inc. 2015 All rights reserved.

=cut



