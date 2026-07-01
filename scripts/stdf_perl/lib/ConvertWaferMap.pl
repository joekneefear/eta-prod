#!/usr/bin/perl -w

#########################################################################################
#
# Fairchild Semiconductor
#
# Author         : David Fletcher
# Date           : Feb. 11th, 2007
#
# Function       : Convert a wafer map to another format.
#
# Input          : -I<Input file Name>
#                  -O<OutPutFile Name>
#                  -C<Map Conversion Type>
#
# Output         : WaferMap File. 
#
#
# Required Files :
#   This file                   - ConvertWafermap.pl
#   Constants File              - sepi_const.pm
#   ConvertMap perl Module File - ConvertWaferMap_Class.pm 
#
# Notes          : sepi_const.pm contains the following values that will need to be set -
#		   use constant SEPI_SVR_HOST           => 'localhost';			# Location of SEPI Server
#		   use constant SEPI_SVR_PORT           => '8080';			# Port Number on SEPI server to communicate with
#		   use constant SEPI_SVR_PATH           => 'PJQ/SEPIConvertWaferMap'; 	# SEPI URL to communicate with
#		   use constant SEPI_SVR_TIMEOUT        => '120';			# Time out value
#		   use constant SEPI_SITE_LOCATION      => 'MESORT';			# SEPIAdmin Job Config ID to obtain SEPOL server info
#
#
#   List of available Map types SE Probe is able to export to.
#
#		EXPORT_MAPTYPE_SE                0	Export SE-PROBE Map 
#		EXPORT_MAPTYPE_ARRAY             1	Export Array Map 
#		EXPORT_MAPTYPE_ASCII             2	Export ASCII Map 
#		EXPORT_MAPTYPE_XY                3	Export XY Map 
#		EXPORT_MAPTYPE_MICREL            4	Export Micrel Map 
#		EXPORT_MAPTYPE_SNI               7	Export SNI Map 
#		EXPORT_MAPTYPE_CARSEM	         9	Export Carsem Map
#		EXPORT_MAPTYPE_TRIAGE           10	Export Triage Map
#		EXPORT_MAPTYPE_CHIPPAC	        16	Export Chippac Map 
#		EXPORT_MAPTYPE_LEXMARK          17	Export Lexmark Map 
#		EXPORT_MAPTYPE_CSV              18	Export CSV Map 
#		EXPORT_MAPTYPE_ECN              19	Export ECN Map 
#		EXPORT_MAPTYPE_ECN_R            20	Export ECN-R Map 
#		EXPORT_MAPTYPE_SIMPLIFIED_INF	21	Export Simplified INF Map 
#
#   Currently, the only acceptable input file formats are SEP and aww (contact Salland if need others).
#
##########################################################################################
use strict;
use ConvertWaferMap_Class;

my $InputFileName  = "";
my $OutPutFileName = "";
my $MapConvertType = "";

#
# Handle the command line arguments...
#
foreach my $argnum (0 .. $#ARGV) 
{
   if( substr($ARGV[$argnum], 0, 1) eq "-" )
   {
      if ( substr($ARGV[$argnum], 1, 1) eq "I" )
      { $InputFileName = substr($ARGV[$argnum], 2); }
      if ( substr($ARGV[$argnum], 1, 1) eq "O" )
      { $OutPutFileName = substr($ARGV[$argnum], 2); }
      if ( substr($ARGV[$argnum], 1, 1) eq "C" )
      { $MapConvertType = substr($ARGV[$argnum], 2); }
   }
}

my $Usage = "\n\nUsage: ConvertWafermap.pl   -IInputFileName -OOutPutFileName -C#\n";
if( $InputFileName eq "" ) 
{
   print $Usage;
   print "Input File Name Parameter not set!\n";
   exit 1;
}
if( $OutPutFileName eq "" ) 
{
   print $Usage;
   print "Output File Name Parameter not set!\n";
   exit 1;
}
if( $MapConvertType eq "" ) 
{
   print $Usage;
   print "Map Convert Type Parameter not set!\n";
   exit 1;
}

my @ret = ();

############################################################
#
# Create a new ConvertMap Object
#
my $ConvertMap = new ConvertWaferMap_Class();
$ConvertMap->set_ConvertMapType($MapConvertType);
$ConvertMap->set_DeflateFiles(0);
$ConvertMap->set_SEPISiteLocation(sepi_const::SEPI_SITE_LOCATION);

############################################################
#
# Read the file into our object
#
@ret = $ConvertMap->ReadWaferMap($InputFileName);
if ($ret[0] eq "FAIL") 
{
   print $ret[1]."\n";
   exit -1;
}

###########################################################
#
# Convert the Map File
#
@ret = $ConvertMap->ConvertWaferMap();
if (defined($ret[0]) && $ret[0] eq "FAIL") 
{
   print $ret[1]."\n";
   exit -1;
}
###########################################################
#
# Write the file out to disk
#
@ret = $ConvertMap->WriteWaferMap($OutPutFileName);
if (defined($ret[0]) && $ret[0] eq "FAIL") 
{
   print $ret[1]."\n";
   exit -1;
} else {
   print "PASS";
   exit 0;
}
