package ConvertWaferMap_Class;

require 5.002;
use strict;
use sigtrap;
use sepi_const;
use XMLRPC::Lite;
use Data::Dumper;
use Carp;

my $Wafer_Results;

sub new 
{
	#
	# Class Object that will be sent to SEPI server, ConvertWMap method call.
	#
	my $class = shift;
	
	my $self = {	};
					
	bless ($self, $class);
	
	return $self;
}

sub PrintParams
{
	my $self = shift;
	
	print "LotID: "         . $self->{'lot_id'}        ."\n";
	print "WaferID: "       . $self->{'wafer_id'}      ."\n";
	print "ConvertMapType: ". $self->{'convertmaptype'}."\n";
	print "Deflate Files: " . $self->{'deflate_files'} ."\n";
	print "File Data: "     . $self->{'file_data'}     ."\n";	
	
}

sub PrintWaferMap
{
	my $self   = shift;
	print $self->{'file_data'};
}

sub ReadWaferMap
{
	my $self   = shift;
	my $infile = shift;
	
	my $errmsg = "";
	#
	# Check and make sure the file exists on the server
	#
	if (! -e $infile) 
	{
		$errmsg = "Input File: '".	$infile . "' is not readable!"; 
		return ("FAIL", $errmsg);
	}
	
	my $line = "";
	my $file = "";
	open (CWM, $infile);
	while ($line = <CWM>) 
	{
		$file = $file.$line;
	}
	close(CWM);
	
	$self->{'file_data'} = XMLRPC::Data->type(base64 => $file);
	
	return ("SUCCESS", $errmsg);
}

sub WriteWaferMap
{
	my $self    = shift;
	my $outfile = shift;
	my $errmsg = "";
	
	if (! defined($self->{'converted_file_data'}) || $self->{'converted_file_data'} eq "")
	{
		return ("FAIL", "ERROR:  \$self->{'converted_file_data'} is not set");
	}
	
	open (OUT, ">$outfile") || return ("FAIL", "ERROR: could not create file '$outfile'!");
	print OUT $self->{'converted_file_data'};
	close(OUT);
	
	return ("SUCCESS", $errmsg);
}

sub ConvertWaferMap 
{
	my $self = shift;
	
	my $errmsg = "";
	if ($self->{'convertmaptype'} eq "") 
	{
		$errmsg = "ConvertMapType field is not set..."; 
		return ("FAIL", $errmsg);	
	}
	
	my $ProxyString = 'http://'.sepi_const::SEPI_SVR_HOST.':'.sepi_const::SEPI_SVR_PORT.'/'.sepi_const::SEPI_SVR_PATH;
	
	my $SEPI = XMLRPC::Lite->proxy($ProxyString)
				#->on_debug(sub { print @_; })
				->encoding("ISO-8859-1")
			  	->call("SEPIConvertWaferMapJob.ConvertWaferMap", $self)
				->result();

	#print Dumper(@{$SEPI});
 
	if (!defined($SEPI) && @{$SEPI}[0] eq "1" )
	{
  		$errmsg = "ERROR: Method Call Failed. Return Data:".Dumper(@{$SEPI}); 
		return ("FAIL", $errmsg);
	} else {
		#print "Call made to server!\n";
		if (@{$SEPI}[1] ne "" && @{$SEPI}[0] ne "FAIL") 
		{
		   	$self->{'converted_file_data'} = @{$SEPI}[1];
		   	$self->{'converted_file_data'} =~ s/\r//g;
		} else {
			$errmsg = ( @{$SEPI}[0] eq "FAIL" ? "ERROR: ".@{$SEPI}[1] : "ERROR: ".Dumper(@{$SEPI}) );
			return( "FAIL", $errmsg );
		}
	}
  
	return ("SUCCESS", $errmsg);
}


sub set_FileData
{
	my $self  = shift;
	my $FileData = shift;
	$self->{'file_data'} = XMLRPC::Data->type(base64 => $FileData); 
}

sub set_DeflateFiles
{
	my $self  = shift;
	my $DeflateFiles = shift;
	$self->{'deflate_files'} = XMLRPC::Data->type(int => $DeflateFiles); 
}

sub set_ConvertMapType
{
	my $self  = shift;
	my $ConvertMapType = shift;
	$self->{'convertmaptype'} = XMLRPC::Data->type(int => $ConvertMapType); 
}

sub set_LotID
{
	my $self  = shift;
	my $LotID = shift;
	$self->{'lot_id'} = XMLRPC::Data->type(string => $LotID); 
}

sub set_WaferID
{
	my $self  = shift;
	my $WaferID = shift;
	$self->{'wafer_id'} = XMLRPC::Data->type(int => $WaferID); 
}

sub set_SEPISiteLocation
{
	my $self   = shift;
	my $SITEID = shift;
	$self->{'map_sever_loc'} = XMLRPC::Data->type(string => $SITEID); 
}

1;
