package PDF::WS;

=pod
    2020-Jul-05 - jgarcia - initial.
=cut

use strict;
use Exporter 'import';
use POSIX qw/strftime/;
use Time::Local;
use List::MoreUtils qw/first_index/;
use Carp qw/longmess/;
use XML::XPath;
use XML::XPath::XMLParser;
use LWP;
use PDF::DpLoad;
use PDF::Log;
use JSON;

our @EXPORT = qw/getLotInfoFromLotG getLotInfoFromLotM getScribeFromRWS getMetaFromRefDbWS getFromERTWS/;

our $VERSION = "1.0";

sub getFromERTWS {
  my $url = shift;
  my $ua = LWP::UserAgent->new;
  my $request = HTTP::Request->new( GET => $url );
  my $response;
  eval { my $res = $ua->request($request) };
  if($@) {
      dpExit(1, "ERT WS call encountered an error, please check log or ERT log=>$@"); 
  } 
  $response = $ua->request($request);
  
  return (handleResponse( $response, \&decode_json )); 
  
}

sub getLotInfoFromLotG {
    my $url = shift;
    my $ua = LWP::UserAgent->new;
    ### LotG version=4
    ###$url = "http://lotg.onsemi.com:60034/LotGWS/resources/lotg/lot/${lot}/sourceLot";
    ##$url = "http://lotg.onsemi.com:9099/LotGWS/resources/lotg/lot/${lot}/sourceLot";
    ### LotG version 4.1 (Still in QA)
    #$url = "http://usco09ls210.onsemi.com:60030/LotGWS/resources/lotg/lot/${lot}/sourceLotWLotClass";
    my $request = HTTP::Request->new( GET => $url );
    my  $response = $ua->request($request);
    
    return (handleResponse( $response, \&parseXmlLotG ));    # pointer to a function
}

sub parseXmlLotG {
  my ($rawXml) = @_;
  my @elements = ();
  my %lotGhash = {};
  my $status;
  #INFO("=============$rawXml");
  my $xp = XML::XPath->new( xml => trim($rawXml) );
  my $nodeset = $xp->find('/SourceLot/');
  foreach my $node($nodeset->get_nodelist) {
    my $nodeString = XML::XPath::XMLParser::as_string($node);
    $nodeString =~ s/^\s+|\s+$//g;
    @elements = split(/\s+/,$nodeString);
    foreach my $item (@elements) {
      if($item =~ /(.+)\=\"(.+)\"$/ && $item ne "") {
        my $k = $1;
        my $v = $2;
        #INFO("KEY=$k||VAL=$v");
        $lotGhash{Lot}{$k} = $v;
      }
    }
  }
  return(%lotGhash);
}
 

sub getLotInfoFromLotM {
    my $url= shift;
    my $ua = LWP::UserAgent->new;
    INFO("URL-$url");
    my $request = HTTP::Request->new( GET => $url );
    my  $response = $ua->request($request);

        return (handleResponse( $response, \&parseXmlLotM ));    # pointer to a function
}

sub parseXmlLotM {
  my ($rawXml) = @_;
  my @elements = ();
  my %lotMHash = {};
  my $status;
  #INFO("=============$rawXml");
  my $xp = XML::XPath->new( xml => trim($rawXml) );
  my $nodeset = $xp->find('/LotInfo/');
  foreach my $node($nodeset->get_nodelist) {
    my $nodeString = XML::XPath::XMLParser::as_string($node);
    $nodeString =~ s/^\s+|\s+$//g;
    #INFO(">>$nodeString<<"); dpExit(1,"");
    #="UNKNOWN"a
    @elements = split(/\s+/,$nodeString);
    #INFO("TEST==".@elements); dpExit(1, "");
    foreach my $item (@elements) {
      if($item =~ /(.+)\=\"(.+)\"$/ && $item ne "") {
        my $k = $1;
        my $v = $2;
        #INFO("KEY=$k||VAL=$v");
        if($k =~ /SourceLot|Status|SourcePart/i) {
          $lotMHash{LotInfo}{$k} = $v;
        } elsif($k =~ /Technology|Process|Family|Product|Part|PtiCode/i) {
          $lotMHash{Metadata}{$k}= $v; 
        }    
      }
    }
  }
  return(%lotMHash);
}

sub getScribeFromRWS {
    my $url= shift;
    my $ua = LWP::UserAgent->new;
    INFO("URL-$url");
    my $request = HTTP::Request->new( GET => $url );
    my  $response = $ua->request($request);

    return (handleResponse( $response, \&parseXmlScribeRMS ));    # pointer to a function

}

sub parseXmlScribeRMS {
  my ($rawXml) = @_;
  my @elements = ();
  my %lotScribeHash = {};
  my $status;
  #INFO("=============$rawXml");
  my $xp = XML::XPath->new( xml => trim($rawXml) );
  my $nodeset = $xp->find('/Result/');
  foreach my $node($nodeset->get_nodelist) {
    my $nodeString = XML::XPath::XMLParser::as_string($node);
    $nodeString =~ s/^\s+|\s+$//g;
    @elements = split(/\s+/,$nodeString);
    foreach my $item (@elements) {
      if($item =~ /(.+)\=\"(.+)\"$/ && $item ne "") {
        my $k = $1;
        my $v = $2;
        #INFO("KEY=$k||VAL=$v");
        $lotScribeHash{LotInfo}{$k} = $v;
      } elsif($item =~ /\<Scribe\>(.+)\<\/Scribe\>/i) {
        $lotScribeHash{LotInfo}{Scribe} = $1;
      }
    }
  }
  return(%lotScribeHash);

}

sub getMetaFromRefDbWS {
	my $url = shift;
	my $ua = LWP::UserAgent->new;
	my $request = HTTP::Request->new( GET => $url );
	my $response = $ua->request($request);
 
 	return (handleResponse( $response, \&parseRefDbXml ));

}

sub parseRefDbXml {
	my ($rawXml) = @_;
	my %RefDbHash;

	my @arr = split/\,/, $rawXml;

	foreach my $item (@arr) {
		my ($key,$val) = split /\:/, $item;
		
		$key = trim($key);
		$val = trim($val);

		if ($val =~ /null/i) {
			$val = "N/A";
		}
		else {
			$val = $val;
		}

		$RefDbHash{$key} = $val;
	}

	if ($RefDbHash{status} !~ /no_data|error/ig) {
		INFO("Good!...Metadata found in refdb web service.");
	}
	else {
		WARN("Bad!...Metadata not found in refdb web service.");
	}

	return %RefDbHash;
}

sub handleResponse {
        my ( $response, $callback ) = @_;
        if($response->content =~ /400 URL must be absolute/i) {
          dpExit(1, "ERT WS call encountered an error, please check URL=>".$response->content);
        }
        if ( $response->is_success ) {
                if ( defined $callback ) {
                        return($callback->( $response->content ));
                }
                else {
                        return ($response->content . "\n");
                }
        }
        else {
                return( $response->status_line . "\n");
        }
}


1;
