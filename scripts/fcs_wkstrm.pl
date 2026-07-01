#!/usr/bin/env perl_db

my $ToolName = "fcs_wkstrm.pl";
#
#------------------------- File Header -----------------------------------
#
# File Name: fcs_wkstrm.pl
#
# Description: This script will add LSR meta and summary data to SPD files, and validate data in some cases.
#
# Sccs Id:    @(#)fcs_wkstrm_st.pl	1.0 25/02/2015 17:00:47
#
# Related Files/Documents:
#
# Revision History
# ________________
# Date      Author           Description
#
# 25-02-2015  Jacky     Initial Version
# 21-05-2015  Grace     LOSS: Add two columns more (_QTY_IN, _TOTAL_LOSS)
# 21-05-2015  Grace     LOSS: no output for useless data that doesn't have parameter
# 28-05-2015  Grace     delete single quotes from short description
# 28-05-2015  Eric		Gunzip files if ZIPFile containa gz files.
# 28-05-2015  Grace     delete #  from "#if($equipId =~ /^\s*$/){	"   to exclude data that has empty for equip_id
# 29-05-2015  grace  	Added support for -v option.
# 12-06-2015  S. Boothby Get package during lot meta lookup.
# 13-06-2015  S. Boothby Use product info from product file if lot fails meta lookup.
# 14-06-2015  S. Boothby Use Text::CSV to parse entity file.
# 15-06-2015  S. Boothby Output no more than 100 lots per lot attribute file.
# 16-06-2015  S. Boothby If lot history lot meta lookup fails, set source lot equal to lot.S
# 24-06-2015  S. Boothby Identify Maine silicon carbide (SiC) lots.  For FabSite, set lot=SiC lot and set SiC wafer.
# 26-06-2015  Jacky sustitute N/A with unitid when calling OutputFabSiteLine and OutputMetOffLine functions
# 07-07-2015  S. Boothby Losses with qty=1 were not being loaded.
# 14-07-2015  S. Boothby FabSite data was missing if a lot history existed with the same datetime for a non-lot data collection.
# 18-07-2015  S. Boothby Strip single quotes from lot attribute value.
# 18-07-2015  S. Boothby Strip comma from recipe.
# 07-08-2015  S. Boothby Set stage as route for loss data.
# 03-09-2015  S. Boothby Fixed bug in LEH loading that caused incorrect random entity to be listed as PE instead of latest.
# 29-09-2015  S. Boothby Added operation groups to loss IFF as stage_grp.
# 30-09-2015  S. Boothby Changed wafer to use lot instead of source lot.
# 22-10-2015  S. Boothby Don't transform product ID read from product file.
# 26-04-2016  E. Alfanta remove commas to fix lot class issue in sub ProcessLhistFile
# 21-06-2016  S. Boothby Use Text::CSV to parse phist file.
#                        Use vertical tab (ctrl-k) as separator for FS file.
# 2017-06-07  S. Boothby Limits by lot instead of by revision and date.
# 2020-08-15  jgarcia added support to fork processed output files to designated location.
# 2021-04-28  jgarcia  modified for colo server setup
# 2022-05-28  jgarcia  added support for LEHS.
# 2023-05-25  Eric A	: pplogging bug fixes
# 2023-07-03  Eric A	: pass ERT url to header
#-------------------------------------------------------------------------
# Usage:
#
# ----------------- Start CVS Section (do not modify) -------------------
#
#      $Id: fcs_wkstrm.pl 2584 2020-10-06 02:20:43Z dpower $
      my($sVersionId) = ( split(' ', '$Revision: 2584 $') )[1];
	  my($VersionAndDate) = "

1.0
";
# ------------------------- End CVS Section -----------------------------
#
##############################################################################

# Variable declarations
# Variable declarations
use strict;
use FindBin qw/$Bin/;
use FindBin::libs;
use Archive::Extract;
use Getopt::Long;
use File::Copy qw(move copy);
use DateTime;
use DateTime::Duration;
use Text::CSV;
use File::Copy;
use POSIX qw(strftime);
use PDF::DAO;
use PDF::DpData;
use PDF::DpWriter;
use PDF::Parser::BK_LEHS;
use PDF::Formatter;
use File::Path qw(make_path);
use PDF::DpLoad;
use PDF::Log;
use Text::Unidecode;
#use FindBin qw/$Bin/;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Compress::Gzip qw(gzip $GzipError) ;
use File::Basename qw/basename fileparse dirname/;
use Data::Dumper;
use Config::Tiny;
use PPLOG::PPLogger;


my %normalizeChars = (
    'Š'=>'S', 'š'=>'s', 'Ð'=>'Dj','Ž'=>'Z', 'ž'=>'z', 'À'=>'A', 'Á'=>'A', 'Â'=>'A', 'Ã'=>'A', 'Ä'=>'A',
    'Å'=>'A', 'Æ'=>'A', 'Ç'=>'C', 'È'=>'E', 'É'=>'E', 'Ê'=>'E', 'Ë'=>'E', 'Ì'=>'I', 'Í'=>'I', 'Î'=>'I',
    'Ï'=>'I', 'Ñ'=>'N', 'Ò'=>'O', 'Ó'=>'O', 'Ô'=>'O', 'Õ'=>'O', 'Ö'=>'O', 'Ø'=>'O', 'Ù'=>'U', 'Ú'=>'U',
    'Û'=>'U', 'Ü'=>'U', 'Ý'=>'Y', 'Þ'=>'B', 'ß'=>'Ss','à'=>'a', 'á'=>'a', 'â'=>'a', 'ã'=>'a', 'ä'=>'a',
    'å'=>'a', 'æ'=>'a', 'ç'=>'c', 'è'=>'e', 'é'=>'e', 'ê'=>'e', 'ë'=>'e', 'ì'=>'i', 'í'=>'i', 'î'=>'i',
    'ï'=>'i', 'ð'=>'o', 'ñ'=>'n', 'ò'=>'o', 'ó'=>'o', 'ô'=>'o', 'õ'=>'o', 'ö'=>'o', 'ø'=>'o', 'ù'=>'u',
    'ú'=>'u', 'û'=>'u', 'ý'=>'y', 'ý'=>'y', 'þ'=>'b', 'ÿ'=>'y', 'ƒ'=>'f',
    'ă'=>'a', 'î'=>'i', 'â'=>'a', 'ș'=>'s', 'ț'=>'t', 'Ă'=>'A', 'Î'=>'I', 'Â'=>'A', 'Ș'=>'S', 'Ț'=>'T',
);
my $readWksm="$Bin/read_wksm.pl";
#my $readWksm = "/home/dpower/project/work/karen/scripts/read_wksm.pl";

#my $readWksm = "/data/projects/fairchild/test/read_wksm.pl";
#my $readWksm = "read_wksm.pl";
#my $perlname = "perl";
my $perlname = "perl_db";
# a hash to receive options

#Initialized PPLogger Object
my $pplogger = new PPLOG::PPLogger();

my (%hOptions)= (
	"out" => undef,
	"FORK" => undef,
	"fmtdir" => undef,
	"product"=>undef,
	"convert"=>undef,
	"logfile" => undef,
	"loc" => undef,
	"read_wksm_path" => undef,
	"type" => undef,
	"LEHGROUP"=>undef,
	"FINALLOT" => 0,
	"DEBUG"  => undef,
	"TRACE"  => undef,
	"HELP" => undef,
	"WAFERPRODUCT" => undef,
	"FACILITYFILE" => undef,
  	"FACILITYAREA" => undef,
	"PPLOG" => undef

);

my $ErrorCode = 0;
my $ErrorMsg = 0;

my $convert=undef;
my $location=undef;
my $facilityArea=undef;

my $equip6_id=undef;
my $config=undef;
my $pp_method=undef;
my $prodpattern=undef;

my $ZIPFile=undef;
my $indir=undef;
my $environment=undef;
my $ertUrl=undef;

my %parameter_sets=();

my %operinfo=();

my %prodinfo=();
my %prodfile=();
my %lotinfo=();
my %lhistlossinfo=();
my %lhistinfo=();
my %lhistfsinfo=();
my %lhistloteventinfo=();
my %lhistoffinfo=();
my %ehistinfo=();
my %ehistupdinfo=();

my %ehistoffinfo=();
my %entitytransaction=();
my %phistinfo=();
my %entinfo=();
my %parminfo=();

my %sicinfo=();

my %missingLot=();
my %missingProduct=();
my %lothashes=();
my %lehprogramhash=();
my %fhs=();

my %output=();
my %erroutput=();
my %headers=();

my %offoutput=();
my $phistfilenname=undef;
my $ehistfilename=undef;
my $preoutputfilename=undef;
my $lattbasename=undef;
my $lattext=undef;
my $forkDirectory="";

my %m2d=("JAN"=>"01","FEB"=>"02","MAR"=>"03","APR"=>"04","MAY"=>"05","JUN"=>"06","JUL"=>"07","AUG"=>"08","SEP"=>"09","OCT"=>"10","NOV"=>"11","DEC"=>"12");
my $NA="N/A";
##############################################################################
#                                 Main
#
##############################################################################
# command line arguments.

Initialize_argument();

ProcessZipFile();
INFO(" --> Done!");
dpExit(0);
##############################################################################
# Subroutine: Initialize_argument
##############################################################################
sub Initialize_argument{

	# turn the ignorecase option on so that the options will be case-insensitive
	$Getopt::Long::ignorecase = 1;
	$Getopt::Long::debug = 0;


	# get all values of the options that the user has defined

	MyUsage() unless(GetOptions(\%hOptions,
								"out=s",
								"FORK=s",
								"fmtdir=s",
								"product=s"=>\$prodpattern,
								"logfile=s",
								"loc=s",
								"type=s",
								"method=s",
								"convert"=>\$convert,
								"LEHGROUP",
								"WAFERPRODUCT",
								"FINALLOT",
								"V",
								"VERSION",
								"DEBUG",
								"TRACE",
								"HELP",
								"FACILITYFILE=s",
        						        "FACILITYAREA=s",
								"PPLOG"
							)
					);

	$config = Config::Tiny->read($hOptions{FACILITYFILE});

	#Pass PPLogger object to PDF::Log
        PDF::Log->init( \%hOptions,$pplogger);
        if ($hOptions{PPLOG}){
                $pplogger->settobeLog(1);  #Set flag for pp logging
        }

	#log script name
        $pplogger->setScript(basename($0));

	if($hOptions{FORK}) {
		$forkDirectory = $hOptions{FORK};
	}
	if($hOptions{V} || $hOptions{VERSION} || $hOptions{help})
	{
	    print("$VersionAndDate\n");
	    dpExit(0);
	};

	if($hOptions{HELP}) {MyUsage();}

	$ZIPFile = shift(@ARGV);
    	#print "ZIPFIle = $ZIPFile \n";

	#log raw filename
	$pplogger->setRawFile($ZIPFile);

	unless (defined($ZIPFile)) {MyUsage();}

	if(defined($hOptions{out})){
		if(-d $hOptions{out}){
        		print "OUT is OK exist $ZIPFile \n";

		}else{
			printf STDERR "Making output directory: $hOptions{out}\n";
			my $mkdir_ret = mkdir($hOptions{out}, 0777);
			if ($mkdir_ret != 1) {
				dpExit(1,"Fail to make output directory $hOptions{out}");
			}
		}
	}else{
		MyUsage();
	}

        $pp_method = "BY_PRODUCT";
        if (defined($hOptions{method}))
        {
	   INFO("Option : method = ".$hOptions{method});
           if ( $hOptions{method} eq "BY_PROGRAM" )
           {
              $pp_method = "BY_PROGRAM";
           }
        }

        if ( !defined($hOptions{loc}))
        {
                dpExit(1,"Missing option -loc=LOC");
        }
        $location = uc($hOptions{loc});
        $facilityArea = $hOptions{FACILITYAREA};
	$environment = dirname($ZIPFile);
	$ertUrl = $config->{$location}->{onLotProd};
	INFO("ERT URL=$ertUrl");

	#log site
	$pplogger->setSITE($location);

        if($facilityArea =~ /fab8/i) {
          $equip6_id = $config->{$location}->{fab8};
        } elsif($facilityArea =~ /fab6/i) {
            $equip6_id = $config->{$location}->{fab6};
        } elsif($facilityArea =~ /probe/i) {
          $equip6_id = $config->{$location}->{probe};
        } elsif($facilityArea =~ /epi/i) {
          $equip6_id = $config->{$location}->{epi};
        } elsif($facilityArea eq "") {
          dpExit(1,"Cant get FACILITY AREA which is a mandatory argument.");
        }

	# if ($hOptions{FINALLOT}) {
	# 	$equip6_id = $config->{$location}->{finalTest};
	# } elsif ($hOptions{FAB8}) {
	# 	$equip6_id = $config->{$location}->{fab8};
	# } elsif ($hOptions{FAB6}) {
	# 	$equip6_id = $config->{$location}->{fab6};
	# } elsif ($hOptions{EPI}) {
	# 	$equip6_id = $config->{$location}->{epi};
	# } else {
	# 	$equip6_id = $config->{$location}->{probe};
	# }
	INFO("FACILITY|EQUIP6_ID=$equip6_id");

	if(defined($hOptions{fmtdir})){
		if(-d $hOptions{fmtdir}){
        print "FMT is OK exist $ZIPFile \n";

		}else{
			dpExit(1,"invalid fmt directory: ".$hOptions{fmtdir});
		}
	}else{
		MyUsage();
	}

	if ($hOptions{logfile}){
		PDF::Log->init($hOptions{logfile});
	} else {
		PDF::Log->init;
	}
	PDF::Log->setLevelDebug if ($hOptions{DEBUG});
	PDF::Log->setLevelTrace if ($hOptions{TRACE});
	INFO("Option : isFinalLot = ".$hOptions{FINALLOT});
	# Build Meta file names out of data files
	my ($volume,$pardir,$file) = File::Spec->splitpath( $ZIPFile );
	$indir=$pardir;

	if(-d $indir){
	}else{
		dpExit(1,"invalid input directory: ".$indir);
	}
	if(defined($hOptions{read_wksm_path})){
		$readWksm = $hOptions{read_wksm_path};
	}
	return 1;
}


##############################################################################
# Subroutine: MyUsage
##############################################################################
sub MyUsage{
	my($sUsageMsg) = <<"__END_OF_USAGE_MESSAGE__";      # Usage note
    \n$ToolName <inputfiles> ...
		OUTPUT DIRECTORY:
			[ -out <string> ]               Directory where the output files exist
			[ -fmtdir <string> ]            Directory where the fmt files exist
			[ -product <string> ]			Filter the leh and fs output by product

		SHARE OPTIONS:
			[ -waferproduct ]               Specify whether the product is wafer product
			[ -finallot ]			Specify whether the log is final lot
			[ -type <string>]		Specify which type of files you want to output only for LEH, FS, LOSS, LOTEVENT, LATT, if you assign type as other values, it will not output any files above. If you dont use type option, the default will output all the files above
			[ -logfile ]			specify the log file path
			[ -convert ]                    Generate csv files only
			[ -debug ]                      Debug mode (off by default)
			[ -help ]                       Display version ID or help messages
			[ -facilityfile ] 		required to read facility reference file
			[ -fab8 ]			bk 8 inch fab
			[ -fab6 ]			bk 6 inch fab
			[ -epi ]			epi fab
__END_OF_USAGE_MESSAGE__

	die "$sUsageMsg";
}

##############################################################################
# Subroutine: ProcessZipFile
##############################################################################
sub ProcessZipFile{

	my $index=0;
	#unzip zip file
	my $ae=Archive::Extract->new(archive => $ZIPFile);
	my $ok=$ae->extract(to => $indir);
	my @outgz = ();
	if ( grep(/\.gz$/, @{$ae->files} ) ) {
	   for my $input ( glob "${indir}*.gz" ) {
	       my $output = $input;
	       $output =~ s/\.gz$//;
	       gunzip $input => $output or die "gunzip failed: $GunzipError\n";
	       push @outgz , $output;
	   }
	}
	#process oper, lot_v21 and lhist files
	my $files=$ae->files;
	# Process product and entity and oper and lot attribute file first
	while($files->[$index])
	{
		my $filename=$files->[$index];
		$filename = basename($filename);
		$filename =~ s/\.gz$//;
		$filename =~ /^(.*)\.(\w+)$/;
		my $basename = $1;
		my $ext=$2;
		if($basename =~ /prod$/ || $basename =~ /product$/)
		{

			ProcessProductFile($basename,$ext);
		}
		elsif($basename =~ /oper$/ || $basename =~ /operation$/)
		{
			ProcessOperFile($basename,$ext);
		}
		elsif($basename =~ /_ent$/ || $basename =~ /_entity$/)
		{
			ProcessAndOutputEntFile($basename,$ext);
		}
		elsif($basename =~ /lot_attr$/)
		{
			$lattbasename=$basename;
			$lattext=$ext;
			if(!defined($hOptions{type}) || ($hOptions{type} eq "LATT"))
			{
				OutputLatt($lattbasename,$lattext,"latt");
			}
		}
		$index=$index+1;
	}
	$index=0;
	while($files->[$index]){
		my $filename=$files->[$index];
		$filename = basename($filename);
		$filename =~ s/\.gz$//;
		$filename =~ /^(.*)\.(\w+)$/;
		my $basename = $1;
		my $ext=$2;
		if(defined($convert) && $convert){
			if($basename =~ /lot_attr$/){
				OutputOriginalFile($basename,$ext,"latt");
			}
			GenerateCSVFile($basename,$ext,"csv",0);
		}else{

			if($basename =~ /lot_v21$/){
				#process lot_v21 file
				ProcessLotV21File($basename,$ext);
			}elsif($basename =~ /lhist$/ || $basename =~ /lot_history$/){
				$preoutputfilename=$filename;
				#process lhist file
				ProcessLhistFile($basename,$ext);
			}elsif($basename =~ /phist$/ || $basename =~ /parameter_history$/){
				$phistfilenname=$filename;
				ProcessPhistFile($basename,$ext);
			}elsif($basename =~ /_dllh$/){
				#GenerateCSVFile($basename,$ext,"ltev");
				AddLotInfoForCSVFile($basename,$ext,"ltev");
			}elsif($basename =~ /_ehist$/ || $basename =~ /_entity_history$/){
				$ehistfilename=$filename;
				ProcessAndOutputEhistFile($basename,$ext);
			}elsif($basename =~ /_parm$/ || $basename =~ /_parameter$/){
				ProcessParmFile($basename,$ext);
			}elsif($basename =~ /_eatr$/ || $basename =~ /_entity_attribute$/){
				GenerateCSVFile($basename,$ext,"eatr",0);
			}elsif($basename =~ /_lehs$/) {
        processLehWithStep($basename,$ext);
      }
		}

		$index=$index+1;

	}

	if(defined($convert) && $convert){

	}else{


		if(!defined($hOptions{type}) || ($hOptions{type} eq "LEH"))	{
			OutputLEH();
		}

		if(!defined($hOptions{type}) || ($hOptions{type} eq "FS"))	{
			OutputFabSite();
		}

		if(!defined($hOptions{type}) || ($hOptions{type} eq "OFF"))	{
			OutputMetrologyOffline();
		}

		if(!defined($hOptions{type}) || ($hOptions{type} eq "LOSS"))	{
			OutputLoss();
		}

		if(!defined($hOptions{type}) || ($hOptions{type} eq "LOTEVENT"))	{
			OutputLotEvent();
		}

		if(!defined($hOptions{type}) || ($hOptions{type} eq "EHIST"))	{
			OutputEhist();
		}

	}


	#remove temparary extracted binary files
	$index=0;
	while($files->[$index]){
		unlink($indir."/".$files->[$index]);
		unlink($outgz[$index]);
		$index++;
	}

}

##############################################################################
# Subroutine: PrintLotEventHeader
##############################################################################
sub PrintLotEventHeader{
	my $product=shift;
	my $fab=shift;


	my $header = PDF::DpData::HeaderShort->new;
	$header->VERSION($sVersionId);
	$header->CREATION_DATE(strftime("%m/%d/%Y %H:%M:%S",localtime(time())));

	$header->PRODUCT($product);
	$header->PROGRAM_CLASS(13);

	#$header->populateMeta;
	if(defined($missingProduct{$product})){
	}else{
		unless ($header->populateMeta){
			ERROR("cannot populate Meta data from refdb by product id: ".$product);
			$missingProduct{$product} = 1;
		};
	}
        if ( defined($missingProduct{$product}))
        {
		if ( $missingProduct{$product} == 1 )
		{
			# Substitute info from product table
			INFO("Substituting product ".$product." for missing meta" );
			$header->PRODUCT($product);
			$header->FAMILY($prodfile{$product}{"family"});
			$header->PROCESS($prodfile{$product}{"process"});
			$header->PACKAGE($prodfile{$product}{"package"});
		}
        }
	$header->FAB($fab);
	#$header->PROGRAM("NA");
	my $headerstr="<HEADER>\n";
	$headerstr .= $header->toString;
	$headerstr .= "</HEADER>\n";
	return $headerstr;


}

##############################################################################
# Subroutine: PrintFSHeader
##############################################################################
sub PrintFSHeader{
	my $product=shift;
	my $fab=shift;


	my $header = PDF::DpData::HeaderLong->new;
	$header->VERSION($sVersionId);
	$header->CREATION_DATE(strftime("%m/%d/%Y %H:%M:%S",localtime(time())));

	$header->PRODUCT($product);
	$header->PROGRAM_CLASS(13);
	$header->ertUrl($ertUrl);

	if(defined($missingProduct{$product})){
	}else{
		unless ($header->populateMetaByProduct){
			ERROR("cannot populate Meta data from refdb by product id: ".$product);
			$missingProduct{$product} = 1;
		};
	}
        if ( defined($missingProduct{$product}))
        {
		if ( $missingProduct{$product} == 1 )
		{
			# Substitute info from product table
			INFO("Substituting product ".$product." for missing meta" );
			$header->PRODUCT($product);
			$header->FAMILY($prodfile{$product}{"family"});
			$header->PROCESS($prodfile{$product}{"process"});
			$header->PACKAGE($prodfile{$product}{"package"});
		}
        }
	$header->FAB($fab);
	$header->PROGRAM("N/A");
	#$header->EQUIP6_ID($location);
	$header->EQUIP6_ID($equip6_id);
	my $headerstr="<HEADER>\n";
	$headerstr .= $header->toString;
	$headerstr .= "</HEADER>\n";
	return $headerstr;


}




##############################################################################
# Subroutine: PrintLEHHeader
##############################################################################
sub PrintLEHHeader{
	my $product=shift;
	my $fab=shift;
	my $fname=shift;

	my $header = PDF::DpData::HeaderShort->new;
	$header->VERSION($sVersionId);
	$header->CREATION_DATE(strftime("%m/%d/%Y %H:%M:%S",localtime(time())));

	$header->PRODUCT($product);
	$header->PROGRAM_CLASS(13);

	if(defined($missingProduct{$product})){
	}else{
		unless ($header->populateMeta){
			ERROR("cannot populate Meta data from refdb by product id: ".$product);
			$missingProduct{$product} = 1;
		};
	}
        if ( defined($missingProduct{$product}))
        {
		if ( $missingProduct{$product} == 1 )
		{
			# Substitute info from product table
			INFO("Substituting product ".$product." for missing meta" );
			$header->PRODUCT($product);
			$header->FAMILY($prodfile{$product}{"family"});
			$header->PROCESS($prodfile{$product}{"process"});
			$header->PACKAGE($prodfile{$product}{"package"});
		}
        }
	$header->FAB($fab);
	if((!defined($header->PROCESS)) || ($header->PROCESS eq '')){
		$header->PROGRAM($header->PACKAGE."::".$fab."::WKS");
	}else{
		$header->PROGRAM($header->PROCESS."::".$fab."::WKS");
	}
	$lehprogramhash{$fname}="LEH_".$header->PROGRAM;

	my $headerstr="<HEADER>\n";
	$headerstr .= $header->toString;
	$headerstr .= "</HEADER>\n";



	return $headerstr;


}
##############################################################################
# Subroutine: OutputEhist
##############################################################################
sub OutputEhist{
	my $holder=undef;
	my $eline=undef;

	my $outputdata="entity_type,entity_id,transaction_date_time,facility,time_in_status,standard_status,old_standard_status,status_1,status_2,status_3,status_4,status_5,status_6,status_7,status_8,status_9,comment,operator_id,availability,out of spec indicator,fail flag,facility-related downtime,downtime flag\n";
	foreach $holder (sort keys %ehistinfo){
		my @elines=@{$ehistinfo{$holder}};
		if($#elines == 0){
			next;
		}

		foreach $eline (@elines){
			my $tracktime=${$eline}{"transaction_date_time"};
			if(($tracktime eq $entitytransaction{$holder}) || !(${$eline}{"if_qualified"})){
				next;
			}
			my $entkey = ${$eline}{"entity_id"}."|".${$eline}{"facility"};
			my $entitytype = $entinfo{$entkey};
			my $newline = '"'.join('","',(FormatField($entitytype),FormatField(${$eline}{"entity_id"}),FormatField(${$eline}{"transaction_date_time"}),FormatField(${$eline}{"facility"}),FormatField(${$eline}{"time_in_status"}),FormatField(${$eline}{"standard_status"}),FormatField(${$eline}{"old_standard_status"}),FormatField(${$eline}{"status_1"}),FormatField(${$eline}{"status_2"}),FormatField(${$eline}{"status_3"}),FormatField(${$eline}{"status_4"}),FormatField(${$eline}{"status_5"}),FormatField(${$eline}{"status_6"}),FormatField(${$eline}{"status_7"}),FormatField(${$eline}{"status_8"}),FormatField(${$eline}{"status_9"}),FormatField(${$eline}{"comment"}),FormatField(${$eline}{"operator_id"}),FormatField(${$eline}{"new_availability"}),FormatField(${$eline}{"oosi_flag"}),FormatField(${$eline}{"fail_flag"}),FormatField(${$eline}{"frdt_flag"}),FormatField(${$eline}{"dt_flag"}))).'"'."\n";
			$outputdata .= $newline;
		}
	}

	foreach $holder (sort keys %ehistupdinfo){
		my @elines=@{$ehistupdinfo{$holder}};
		if($#elines == 0){
			next;
		}
		my $entkey = ${$eline}{"entity_id"}."|".${$eline}{"facility"};
		my $entitytype = $entinfo{$entkey};

		foreach $eline (@elines){
			my $newline = '"'.join('","',(FormatField($entitytype),FormatField(${$eline}{"entity_id"}),FormatField(${$eline}{"transaction_date_time"}),FormatField(${$eline}{"facility"}),FormatField(${$eline}{"time_in_status"}),FormatField(${$eline}{"standard_status"}),FormatField(${$eline}{"old_standard_status"}),FormatField(${$eline}{"status_1"}),FormatField(${$eline}{"status_2"}),FormatField(${$eline}{"status_3"}),FormatField(${$eline}{"status_4"}),FormatField(${$eline}{"status_5"}),FormatField(${$eline}{"status_6"}),FormatField(${$eline}{"status_7"}),FormatField(${$eline}{"status_8"}),FormatField(${$eline}{"status_9"}),FormatField(${$eline}{"comment"}),FormatField(${$eline}{"operator_id"}),FormatField(${$eline}{"new_availability"}),FormatField(${$eline}{"oosi_flag"}),FormatField(${$eline}{"fail_flag"}),FormatField(${$eline}{"frdt_flag"}),FormatField(${$eline}{"dt_flag"}))).'"'."\n";
			$outputdata .= $newline;
		}
	}

	MakeSubDir("PRODUCTION");
	my $outputfile=$hOptions{out}."/PRODUCTION/".$ehistfilename."\.ehist";
	INFO("output ehist file:".$outputfile);
	my $ext = "ehist";
	my $fh=undef;

	print $outputfile."\n";
	open($fh,'>',$outputfile);
	print $fh $outputdata;
	close($fh);
	if($hOptions{FORK} ne "") {
		forkFile($outputfile, $hOptions{FORK}, $ehistfilename, $ext, "PRODUCTION");
	}else {
		INFO("Compress $outputfile with gzip");
		my $gzOutfile = $outputfile.".gz";
		if(-e $gzOutfile) {
			INFO("$gzOutfile already exist");
			INFO("Delete $gzOutfile");
			unlink $gzOutfile;
		}
		qx(gzip "$outputfile");
	}
	# if($hOptions{FORK} ne "") {
		# forkFile($outputfile, $hOptions{FORK}, $ehistfilename, $ext, "PRODUCTION");
	# }
}
##############################################################################
# Subroutine: OutputLotEvent
##############################################################################
sub OutputLotEvent{

	my $holder=undef;

	%output=();
	%erroutput=();
	INFO("start output lot event files");
	foreach $holder (sort keys %lhistloteventinfo){
		my $fname = $preoutputfilename."_".$holder;



		my @lelines=@{$lhistloteventinfo{$holder}};
		my $lehash=undef;
		my $iGotHeader = 0;
		my $headerstr = undef;
		foreach $lehash (@lelines){
			my $fab=${$lehash}{"facility"};
			my $operkey=${$lehash}{"operation"}."|".$fab;
			my $lot=${$lehash}{"lot_id"};
			my $entkey=${$lehash}{"equip_id"}."|".${$lehash}{"facility"};
			my $sourceLot = ${$lehash}{"sourcelot"};
			
			my $newline = join(",",(FormatField(${$lehash}{"lot_id"}), FormatField(${$lehash}{"facility"}), FormatField(${$lehash}{"transaction"})
						,FormatField(${$lehash}{"transaction_date_time"}), FormatField(${$lehash}{"operation"})
						,FormatField($operinfo{$operkey}{"short_description"}), FormatField(${$lehash}{"operator_id"})
						,FormatField($entinfo{$entkey}),FormatField(${$lehash}{"equip_id"})
						,FormatField(${$lehash}{"product_id"}),FormatField(${$lehash}{"comment"}),FormatField(${$lehash}{"event"}), FormatField(${$lehash}{"eventtype"})
						,FormatField(${$lehash}{"rework_cat"}),FormatField(${$lehash}{"hold_flag"}),FormatField(${$lehash}{"hold_cat"})
									,FormatField(${$lehash}{"hold_name"}),FormatField(${$lehash}{"hold_note"}),FormatField(${$lehash}{"unit_change"})
									,FormatField(${$lehash}{"lot_quantity_new"}),FormatField(${$lehash}{"loss_quantity"}),formatSourceLot($sourceLot, $lot),FormatField(${$lehash}{"lotclass"})))."\n";

			if(!$iGotHeader){
				$headerstr = PrintLotEventHeader($holder,$fab);
				$iGotHeader=1;
			}
			if(defined($missingLot{$lot}) || defined($missingProduct{$holder})){
				if(defined($erroutput{$fname})){

				}else{
					$erroutput{$fname}=$headerstr;
					$erroutput{$fname} .= "<DATA>\n";
					$erroutput{$fname} .=  join(",",("lot_id","facility","transaction","transaction_date_time","operation"
							,"short_description","operator_id","entity_type","equip_id","product_id"
							,"comment","event","eventtype","rework_cat","hold_flag","hold_cat"
							,"hold_name","hold_note","unit_change","lot_quantity_new","loss_quantity","SOURCE_LOT","LOT_CLASS"))."\n";
				}
				$erroutput{$fname} .= $newline;
			}else{
				if(defined($output{$fname})){

				}else{
					$output{$fname}=$headerstr;
					$output{$fname} .= "<DATA>\n";
					$output{$fname} .=  join(",",("lot_id","facility","transaction","transaction_date_time","operation"
							,"short_description","operator_id","entity_type","equip_id","product_id"
							,"comment","event","eventtype","rework_cat","hold_flag","hold_cat"
							,"hold_name","hold_note","unit_change","lot_quantity_new","loss_quantity","SOURCE_LOT","LOT_CLASS"))."\n";
				}
				$output{$fname} .= $newline;
			}

		}
	}
	OutputFiles("ltevt",1,0);
	INFO("end output lot event files");

}


##############################################################################
# Subroutine: OutputLoss
##############################################################################
sub OutputLoss{

	my $holder=undef;
	my $fh=undef;
	%output = ();
	%erroutput = ();

	INFO("start output loss files");
	foreach $holder (sort keys %lhistlossinfo){
		my $fname=$preoutputfilename."_".$holder;
		#INFO("output loss file: ".$fname);
		#open($fh,'>',$outputfile);

		my @losslines=@{$lhistlossinfo{$holder}};
		my $losshash=undef;
		my $outputdata = undef;
		my $total_loss = 0;
		my $qty_in = 0;
		my $valid_data = 0;

		#my $ifMissing = 0;
		foreach $losshash (@losslines){
			my $operkey=${$losshash}{"operation"}."|".${$losshash}{"facility"};

			my $lot = ${$losshash}{"lot_id"};
			my $facilityCode = ${$losshash}{"facility"};
			my $operator = ${$losshash}{"operator_id"};
			my $txndate = ${$losshash}{"transaction_date_time"};
			my $lotQuantityNew = ${$losshash}{"lot_quantity_new"};
			my $operation = ${$losshash}{"operation"};
			my $equip_id = ${$losshash}{"equip_id"};
		        my $entkey=$equip_id."|".$facilityCode;
			my $entType=$entinfo{$entkey};
			my $transaction = ${$losshash}{"transaction"};
			my $prod_id = ${$losshash}{"product_id"};
			my $route = ${$losshash}{"route"};

			my $lenOperation = length($operation);
			my $zero = "";
			for(my $i =0 ; $i<4-$lenOperation; $i++)
			{
				$zero = "0".$zero;
			}

			$operation = $zero.$operation;
			my $step = $operation." ".$operinfo{$operkey}{"short_description"};

			my $header = PDF::DpData::HeaderLong->new();
			$header->VERSION($sVersionId);
			$header->CREATION_DATE(strftime("%m/%d/%Y %H:%M:%S",localtime(time())));
			$header->LOT($lot);
			$header->isFinalLot($hOptions{FINALLOT});
			$header->PROGRAM_CLASS(12);
			$header->PROGRAM("LOSS::".$facilityCode."::WKS");
			#$header->PROGRAM("LOSS::".$operation." ".$step."::".$facilityCode."::WKS");
			#$header->EQUIP6_ID($location);
			$header->EQUIP6_ID($equip6_id);
			$header->ertUrl($ertUrl);
			

			 # get Mata from database

			if(defined($missingLot{$lot})){
			}else{
				unless ($header->populateMeta){
					ERROR("cannot populate Meta data from refdb by lot id: ".$lot);
					$missingLot{$lot} = 1;
				}
			}
			if ( defined($missingLot{$lot}))
			{
				if ( $missingLot{$lot} == 1 )
				{
					# Substitute info from product table
					INFO("Substituting product ".$prod_id." for missing meta" );
					$header->PRODUCT($prod_id);
					$header->FAMILY($prodfile{$prod_id}{"family"});
					$header->PROCESS($prodfile{$prod_id}{"process"});
					$header->PACKAGE($prodfile{$prod_id}{"package"});
				}
			}

#			my($sourceLot,$lotowner,$lotclass) = GetMetaByLot($lot);

			$header->FAB($facilityCode);


			$header->STEP($step);
			$header->STEP_GRP1($operinfo{$operkey}{'oper_group_1'});
			$header->STEP_GRP2($operinfo{$operkey}{'oper_group_2'});
			$header->STEP_GRP3($operinfo{$operkey}{'oper_group_3'});
			$header->STAGE($route);
			if ( defined($equip_id) && defined($entType) && $equip_id ne " " )
			{
			   $header->EQUIP1_ID($entType."::".$equip_id);
                        }
			else
			{
			   if ( $equip_id =~ /^\s*$/ || $equip_id eq "n/a" )
			   {
			   	$equip_id = "N/A";
			   }
			   $header->EQUIP1_ID($equip_id);
			}
			$header->OPERATOR($operator);
			$header->START_TIME($txndate);
			$header->END_TIME($txndate);
			$header->DEVICE_COUNT($lotQuantityNew);
			$header->SOURCE_LOT(formatSourceLot($header->{SOURCE_LOT}, $lot));
			my $str_header ="<HEADER>\n";
			$str_header.=$header->toString;
			$str_header .= "</HEADER>\n";


			$outputdata = $str_header;
			$outputdata .= "<SUB_LOT>\n";

			
			# if ( $header->SOURCE_LOT =~ /^\s*$/ || $header->SOURCE_LOT eq "N/A" || $header->SOURCE_LOT eq "NA" )
			# {
			# 	$sourceLot = $lot.".S";
			# }
			# else
			# {
			#  	$sourceLot = $header->SOURCE_LOT;
			# }
			

			$outputdata .= $lot."_00\n";
			$outputdata .= "</SUB_LOT>\n";
			$outputdata .= "<EQUIP1_ID>\n";
			$outputdata .= $equip_id."\n";
			$outputdata .= "</EQUIP1_ID>\n";

			$outputdata .= "<BIN_DATA>\n";
			$outputdata .= "</BIN_DATA>\n";

			$outputdata .= "<PAR_DATA>\n";
			my $index = 1;

			for(my $i=0;$i<=12;$i++){
				my $namekey = "loss_category_".$i;
				my $valuekey = "loss_quantity_".$i;
=pod
				if(${$losshash}{$namekey} =~ /^\s*$/){
					next;
				}
=cut

				if(${$losshash}{$valuekey} =~ /^\s*$/ || ${$losshash}{$valuekey} =~ /^0+$/){
					next;
				}

				$outputdata .= join(",",(${$losshash}{$namekey},${$losshash}{$valuekey}))."\n";
				$index++;

				$total_loss = $total_loss +  ${$losshash}{$valuekey};
				$valid_data = 1;
			}

			$qty_in = $total_loss + $lotQuantityNew;

			if($transaction eq "MVOU" || $total_loss gt 0)
			{
				$outputdata .= "_GOOD,".$lotQuantityNew."\n";

				$outputdata .= "_TOTAL_LOSS,".$total_loss."\n";

				$outputdata .= "_QTY_IN,".$qty_in."\n";

				$valid_data = 1;

			}

			$outputdata .= "</PAR_DATA>\n";

			if($valid_data)
			{
				if(defined($missingLot{$lot})){
					$erroutput{$fname} = $outputdata;
				}else{
					$output{$fname} = $outputdata;
				}
			}

			last;
		}
		#print $fh $outputdata;
		#close($fh);

	}
	OutputFiles("loss",0,0);
	INFO("end output loss files");
}

sub addTestInfo {
   my $parameter_set=shift;
   my $parameter_set_version=shift;
   my $date_stamp=shift;
   my $test_name=shift;
   my $test_units=shift;
   my $test_low_limit=shift;
   my $test_high_limit=shift;

   my $ntest = new_test;
   $ntest->name($test_name);
   $ntest->units($test_units);
   $ntest->LSL($test_low_limit);
   $ntest->HSL($test_high_limit);
   my $psver_key = $parameter_set . "~~~" . $parameter_set_version;
   if (exists($parameter_sets{$psver_key} ))
   {
      #print "Existing $parameter_set, $parameter_set_version\n";
      my $psetver = $parameter_sets{$psver_key};
      if (exists($psetver->{$test_name}))
      {
          #print "Existing $parameter_set, $parameter_set_version, $test_name\n";
      }
      else
      {
         # Add test
         #print "Adding $test_name to $parameter_set, $parameter_set_version\n";
         $psetver->{$test_name}=$ntest;
      }
   }
   else
   {
      my $new_psver={$test_name=>$ntest};
      $new_psver->{"YMS PSET Start Date"} = $date_stamp;
      $parameter_sets{$psver_key} = $new_psver;
      #print "Adding $parameter_set, $parameter_set_version, $test_name\n";
   }
}
##############################################################################
# Subroutine: OutputFabSiteLine
##############################################################################
sub OutputFabSiteLine{
	my $holder=shift;
	my $site_in=shift;
	my $unitid=shift;
	my $currentsite=$site_in;
	my $i=undef;
	my $fh=undef;
	my @vs=();
	my $newline=undef;

	my $numofvs=$phistinfo{$holder}{'number_of_values'};
	if($phistinfo{$holder}{'parameter_set_id'} =~ /WB-CSPL-L/){
		INFO("WB-CSPL-L Found");
	}
	@vs = split(',',$phistinfo{$holder}{'values'});

	my $lhistfskey_prime=$phistinfo{$holder}{'type_id'}."|".$phistinfo{$holder}{'facility'}."|".$phistinfo{$holder}{'parameter_set_id'}."|".
	                     $phistinfo{$holder}{'parameter_set_version'}."|".$phistinfo{$holder}{'date_time'};
	my $lhistfskey=undef;
#	INFO( "Checking::".$lhistfskey_prime);
	if(defined($lhistfsinfo{$lhistfskey_prime})){

		my $proc_lots = 1;
		my $in_lot=$lhistfsinfo{$lhistfskey_prime}{'lot_id'};
		my $lot = undef;
		my $lotix = 0;
		while( $proc_lots )
		{
		if ( $in_lot eq "##MULTI##" )
		{
			$lot=@{$lhistfsinfo{$lhistfskey_prime}{'multi_lot'}}[$lotix];
#			INFO("CHECKING LOT::".$lot." (".$lotix.") - ".$in_lot." [".(scalar @{$lhistfsinfo{$lhistfskey_prime}{'multi_lot'}})."]");
			$lhistfskey=$lot."|".$phistinfo{$holder}{'facility'}."|".$phistinfo{$holder}{'parameter_set_id'}."|".
			            $phistinfo{$holder}{'parameter_set_version'}."|".$phistinfo{$holder}{'date_time'};
		}
		else
		{
			$lot=$in_lot;
			$lhistfskey=$lhistfskey_prime;
			$proc_lots = 0;
	  	}
		my $prod=$lhistfsinfo{$lhistfskey}{'product_id'};
		my $fab=$lhistfsinfo{$lhistfskey}{'facility'};
		if(defined($prodpattern)){
			if($prod =~ /$prodpattern/){

			}else{
				return;
			}
		}

		my $operkey=$lhistfsinfo{$lhistfskey}{'operation'}."|".$lhistfsinfo{$lhistfskey}{'facility'};
		if(defined($operinfo{$operkey})){
			my $datetime=$phistinfo{$holder}{'date_time'};


			my $parmkey=$phistinfo{$holder}{'parameter_name'}."|".$phistinfo{$holder}{'facility'};
			my $parag1=undef;
			my $parag2=undef;
			my $parag3=undef;
			if(defined($parminfo{$parmkey})){
				$parag1=$parminfo{$parmkey}{'parameter_group_1'};
				$parag2=$parminfo{$parmkey}{'parameter_group_2'};
				$parag3=$parminfo{$parmkey}{'parameter_group_3'};
			}else{
				$parag1='';
				$parag2='';
				$parag3='';
			}

			my $entkey=$lhistfsinfo{$lhistfskey}{"equip_id"}."|".$lhistfsinfo{$lhistfskey}{"facility"};

#			if (defined($sicinfo{$lot}{$unitid}))
#			{
#				INFO( "SiC lot ".$lot." found with unit_id=\"".$unitid."\", SiCLot=\"".$sicinfo{$lot}{$unitid}."\"");
#			}
#			else
#			{
#				INFO( "SiC lot ".$lot." NOT found with unit_id=\"".$unitid."\", SiCLot=\"".$sicinfo{$lot}{$unitid}."\"");
#			}
#			my($sourcelot,$lotowner,$lotclass,$product) = GetMetaByLot($lot);
			if($phistinfo{$holder}{'parameter_set_id'} =~ /WB-CSPL-L/){
				INFO("vs = ".$#vs);
				INFO("vs values = ".$phistinfo{$holder}{'values'});
			}
			$currentsite = $site_in;
			for($i=1;$i<=$#vs+1;$i++){

                                my $progName="FS::" .  $lhistfsinfo{$lhistfskey}{'operation'} .
				   "_" .  $operinfo{$operkey}{'short_description'} .
				   "::" .  $phistinfo{$holder}{'parameter_set_id'} .
				   "::" .  $lhistfsinfo{$lhistfskey}{'facility'} . "::WKS";

				$newline=FormatField($datetime)
				                ."\cK".FormatField($lot)
						."\cK".FormatField($lhistfsinfo{$lhistfskey}{'facility'})
						."\cK".FormatField($lhistfsinfo{$lhistfskey}{'operation'})
						."\cK".FormatField($operinfo{$operkey}{'oper_group_1'})
						."\cK".FormatField($operinfo{$operkey}{'oper_group_2'})
						."\cK".FormatField($operinfo{$operkey}{'oper_group_3'})
						."\cK".FormatField($operinfo{$operkey}{'short_description'})
						."\cK".FormatField($entinfo{$entkey})
						."\cK".FormatField($lhistfsinfo{$lhistfskey}{'equip_id'})
						."\cK".FormatField($lhistfsinfo{$lhistfskey}{'product_id'});
				if ( $pp_method eq "BY_PROGRAM" )
				{
				    $newline .=  "\cK".FormatField($lhistfsinfo{$lhistfskey}{'family'})
						."\cK".FormatField($lhistfsinfo{$lhistfskey}{'process'})
						."\cK".FormatField($lhistfsinfo{$lhistfskey}{'package'})
				}
			        $newline .=      "\cK".FormatField($unitid)
						."\cK".FormatField($currentsite)
						."\cK".FormatField($phistinfo{$holder}{'parameter_set_id'})
						."\cK".FormatField($phistinfo{$holder}{'parameter_set_version'})
						."\cK".FormatField($phistinfo{$holder}{'parameter_name'})
						."\cK".FormatField($phistinfo{$holder}{'exceed_limit_flag'})
						."\cK".FormatField($phistinfo{$holder}{'test_data_flag_1'})
						."\cK".FormatField($parag1)
						."\cK".FormatField($parag2)
						."\cK".FormatField($parag3)
						."\cK".FormatField($phistinfo{$holder}{'format_flag'})
						."\cK".FormatField($vs[$i-1])
						."\cK".FormatField((split / /, $datetime)[0]) # Just the date
						."\cK".FormatField($phistinfo{$holder}{'low_lim'})
						."\cK".FormatField($phistinfo{$holder}{'high_lim'})
						."\cK".FormatField($lhistfsinfo{$lhistfskey}{'comment'})
						."\cK".FormatField($lhistfsinfo{$lhistfskey}{'route'})
						."\cK".FormatField($lhistfsinfo{$lhistfskey}{'owner'})
						."\cK".FormatField($lhistfsinfo{$lhistfskey}{'operator_id'})
						."\cK".formatSourceLot($lhistfsinfo{$lhistfskey}{'sourcelot'},$lot)
						."\cK".FormatField($lhistfsinfo{$lhistfskey}{'lotclass'});

				if($phistinfo{$holder}{'parameter_set_id'} =~ /WB-CSPL-L/){
					INFO("Output NewLine:".$newline);
				}


				my $fname=$preoutputfilename."_";
				if ( $pp_method eq "BY_PROGRAM" )
				{
				   my $pset_fn = $phistinfo{$holder}{'parameter_set_id'};
				   $pset_fn =~ tr/ /_/;
				   $fname.= $pset_fn;
				}
				else
				{
				   $fname.=$prod."-".$lot;
				}
				if(defined($headers{$fname})){
				}else{
					$headers{$fname} = PrintFSHeader($prod,$fab);
				}
				if(defined($missingLot{$lot}) || defined($missingProduct{$prod})){
					if(defined($erroutput{$fname})){

					}else{
				                if ( $pp_method eq "BY_PRODUCT" )
						{
						   $erroutput{$fname}=$headers{$fname};
						   $erroutput{$fname}.= "<DATA>\n";
						}
						else
                                                {
						   $erroutput{$fname} = "<DATA>\n";
                                                }
						$erroutput{$fname} .=  "date_time,Lot_id,fab,Sequence_number,Condition1,Condition2,Condition3,Step,entity_type,equip_id,product_id";
				                if ( $pp_method eq "BY_PROGRAM" )
        				        {
						   $erroutput{$fname} .=  ",family,process,package";
						}
						$erroutput{$fname} .=  ",unit_id,site,parameter_set_id,parameter_set_version,parameter name,exceed_limit,test_flag,parm_grp_1,parm_grp_2,parm_grp_3,format_flag,result,lim_date,low_lim,high_lim,recipe,stage,lot class,operator,SOURCE_LOT,LOT_CLASS\n";
					}
#					INFO("ERROUTOUT (".defined($missingLot{$lot}).")".$lot." (".defined($missingProduct{$prod}).")".$prod);
					$erroutput{$fname} .= $newline."\n";
				}else{
					if(defined($output{$fname})){

					}else{
				                if ( $pp_method eq "BY_PRODUCT" )
						{
						   $output{$fname}=$headers{$fname};
						   $output{$fname} .= "<DATA>\n";
						}
						else
						{
						   $output{$fname} = "<DATA>\n";
						}
						$output{$fname} .=  "date_time,Lot_id,fab,Sequence_number,Condition1,Condition2,Condition3,Step,entity_type,equip_id,product_id";
				                if ( $pp_method eq "BY_PROGRAM" )
        				        {
						   $output{$fname} .=  ",family,process,package";
						}
						$output{$fname} .=  ",unit_id,site,parameter_set_id,parameter_set_version,parameter name,exceed_limit,test_flag,parm_grp_1,parm_grp_2,parm_grp_3,format_flag,result,lim_date,low_lim,high_lim,recipe,stage,lot class,operator,SOURCE_LOT,LOT_CLASS\n";
					}
					$output{$fname} .= $newline."\n";
				}

				$currentsite=$currentsite+1;

			}

		}else{
			WARN($operkey." does not exist in oper file for ".$lhistfskey);
		}
		$lotix++;
		if ( $in_lot eq "##MULTI##" && $lotix >= scalar @{$lhistfsinfo{$lhistfskey_prime}{'multi_lot'}} )
		{
#			INFO ("TWO::".scalar @{$lhistfsinfo{$lhistfskey_prime}{'multi_lot'}});
			$proc_lots = 0;
		}
		}			# END WHILE
	}else{
		WARN($lhistfskey_prime." does not exist in lhist file");

	}
	return($currentsite);
}
##############################################################################
# Subroutine: OutputFabSite
##############################################################################
sub OutputFabSite
{
	my $holder=undef;
	my @work=[];


	my $currentseqnum=undef;
	my $currentparainfo=undef;
	my $currentsite=undef;
	my %currentparahash=();

	my $ifdirection=0;
	%fhs=();
	%output=();
	%erroutput=();
	%headers=();
	INFO("start output fs files");
	foreach $holder (sort keys %phistinfo){
		@work = split("\\|",$holder);


		my $tmpseqnum=undef;
		my $unitid=undef;
		if($#work==6){
			$tmpseqnum=$work[$#work];
			$unitid='';
			splice(@work,$#work);
		}elsif($#work==7){
			$tmpseqnum=$work[$#work-1];
			$unitid=$work[$#work];
			splice(@work,$#work-1);
		}else{
			INFO($holder." is invalid key in phist file");
			next;
		}



		my $tmpparainfo=join("|",@work);

		if(defined($currentparainfo) && ($currentparainfo eq $tmpparainfo)){
			if(($unitid eq "LEFT") || ($unitid eq "CENTER") || ($unitid eq "RIGHT") || ($unitid eq "TOP") || ($unitid eq "BOTTOM")){
				$currentparahash{$unitid}=$holder;
			}else{
				$currentsite=OutputFabSiteLine($holder,$currentsite,$unitid);
				# SiC lot has EPI SLOT NN, this isn't written if we send "N/A"
				#$currentsite=OutputFabSiteLine($holder,$currentsite,$unitid);
			}

		}else{
			if($ifdirection  && defined($currentparainfo)){
				my $ckey=undef;

				if(defined($currentparahash{'LEFT'})){
					$currentsite=OutputFabSiteLine($currentparahash{'LEFT'},$currentsite,"LEFT");
				}

				if(defined($currentparahash{'CENTER'})){

					$currentsite=OutputFabSiteLine($currentparahash{'CENTER'},$currentsite,"CENTER");
				}

				if(defined($currentparahash{'RIGHT'})){
					$currentsite=OutputFabSiteLine($currentparahash{'RIGHT'},$currentsite,"RIGHT");
				}

				if(defined($currentparahash{'TOP'})){
					$currentsite=OutputFabSiteLine($currentparahash{'TOP'},$currentsite,"TOP");
				}

				if(defined($currentparahash{'BOTTOM'})){
					$currentsite=OutputFabSiteLine($currentparahash{'BOTTOM'},$currentsite,"BOTTOM");
				}

				%currentparahash=();
				$ifdirection=0;
			}
			$currentparainfo=$tmpparainfo;
			$currentseqnum=$tmpseqnum;
			$currentsite=1;


			if(($unitid eq "LEFT") || ($unitid eq "CENTER") || ($unitid eq "RIGHT") || ($unitid eq "TOP") || ($unitid eq "BOTTOM")){

				$currentparahash{$unitid}=$holder;
				$ifdirection=1;
			}else{

				$currentsite=OutputFabSiteLine($holder,$currentsite,$unitid);
			}

		}
	}
	if($ifdirection  && defined($currentparainfo)){
		if(defined($currentparahash{'LEFT'})){
			$currentsite=OutputFabSiteLine($currentparahash{'LEFT'},$currentsite,"LEFT");
		}

		if(defined($currentparahash{'CENTER'})){
			$currentsite=OutputFabSiteLine($currentparahash{'CENTER'},$currentsite,"CENTER");
		}

		if(defined($currentparahash{'RIGHT'})){
			$currentsite=OutputFabSiteLine($currentparahash{'RIGHT'},$currentsite,"RIGHT");
		}

		if(defined($currentparahash{'TOP'})){
			$currentsite=OutputFabSiteLine($currentparahash{'TOP'},$currentsite,"TOP");
		}

		if(defined($currentparahash{'BOTTOM'})){
			$currentsite=OutputFabSiteLine($currentparahash{'BOTTOM'},$currentsite,"BOTTOM");
		}
		%currentparahash=();
		$ifdirection=0;
	}

	OutputFiles("fs",1,0);
	#print Dumper(\%parameter_sets);
	INFO("end output fs files");
}



##############################################################################
# Subroutine: OutputMetrologyOffline
##############################################################################
sub OutputMetrologyOffline
{
	my $holder=undef;
	my @work=[];


	my $currentseqnum=undef;
	my $currentparainfo=undef;
	my $currentsite=undef;
	my %currentparahash=();

	my $ifdirection=0;
	%fhs=();
	%offoutput=();
	#%erroutput=();
	#%headers=();
	INFO("start output metrology offline files");
	foreach $holder (sort keys %phistinfo){
		@work = split("\\|",$holder);


		my $tmpseqnum=undef;
		my $unitid=undef;
		if($#work==6){
			$tmpseqnum=$work[$#work];
			$unitid='';
			splice(@work,$#work);
		}elsif($#work==7){
			$tmpseqnum=$work[$#work-1];
			$unitid=$work[$#work];
			splice(@work,$#work-1);
		}else{
			INFO($holder." is invalid key in phist file");
			next;
		}



		my $tmpparainfo=join("|",@work);

		if(defined($currentparainfo) && ($currentparainfo eq $tmpparainfo)){
			if(($unitid eq "LEFT") || ($unitid eq "CENTER") || ($unitid eq "RIGHT") || ($unitid eq "TOP") || ($unitid eq "BOTTOM")){
				$currentparahash{$unitid}=$holder;
			}else{
				$currentsite=OutputMetOffLine($holder,$currentsite,$unitid);
			}

		}else{
			if($ifdirection  && defined($currentparainfo)){
				my $ckey=undef;

				if(defined($currentparahash{'LEFT'})){
					$currentsite=OutputMetOffLine($currentparahash{'LEFT'},$currentsite,"LEFT");
				}

				if(defined($currentparahash{'CENTER'})){

					$currentsite=OutputMetOffLine($currentparahash{'CENTER'},$currentsite,"CENTER");
				}

				if(defined($currentparahash{'RIGHT'})){
					$currentsite=OutputMetOffLine($currentparahash{'RIGHT'},$currentsite,"RIGHT");
				}

				if(defined($currentparahash{'TOP'})){
					$currentsite=OutputMetOffLine($currentparahash{'TOP'},$currentsite,"TOP");
				}

				if(defined($currentparahash{'BOTTOM'})){
					$currentsite=OutputMetOffLine($currentparahash{'BOTTOM'},$currentsite,"BOTTOM");
				}

				%currentparahash=();
				$ifdirection=0;
			}
			$currentparainfo=$tmpparainfo;
			$currentseqnum=$tmpseqnum;
			$currentsite=1;


			if(($unitid eq "LEFT") || ($unitid eq "CENTER") || ($unitid eq "RIGHT") || ($unitid eq "TOP") || ($unitid eq "BOTTOM")){

				$currentparahash{$unitid}=$holder;
				$ifdirection=1;
			}else{

				$currentsite=OutputMetOffLine($holder,$currentsite,$unitid);
			}

		}
	}
	if($ifdirection  && defined($currentparainfo)){
		if(defined($currentparahash{'LEFT'})){
			$currentsite=OutputMetOffLine($currentparahash{'LEFT'},$currentsite,"LEFT");
		}

		if(defined($currentparahash{'CENTER'})){
			$currentsite=OutputMetOffLine($currentparahash{'CENTER'},$currentsite,"CENTER");
		}

		if(defined($currentparahash{'RIGHT'})){
			$currentsite=OutputMetOffLine($currentparahash{'RIGHT'},$currentsite,"RIGHT");
		}

		if(defined($currentparahash{'TOP'})){
			$currentsite=OutputMetOffLine($currentparahash{'TOP'},$currentsite,"TOP");
		}

		if(defined($currentparahash{'BOTTOM'})){
			$currentsite=OutputMetOffLine($currentparahash{'BOTTOM'},$currentsite,"BOTTOM");
		}
		%currentparahash=();
		$ifdirection=0;
	}
	OutputMetrologyOfflineFiles("off");
	#OutputFiles("fs",1,0);
	INFO("end output metrology offline files");
}
##############################################################################
# Subroutine: OutputMetOffLine
##############################################################################
sub OutputMetOffLine{
	my $holder=shift;
	my $currentsite=shift;
	my $unitid=shift;
	my $i=undef;
	my $fh=undef;
	my @vs=();


	my $ifOff=1;

	my $ehistoffkey = $phistinfo{$holder}{'parameter_set_id'}."|".$phistinfo{$holder}{'parameter_set_version'}."|".$phistinfo{$holder}{'date_time'}
					."|".$phistinfo{$holder}{'facility'}."|".$phistinfo{$holder}{'type_id'};
	my $lhistoffkey1 = $phistinfo{$holder}{'facility'};
	my $lhistoffkey2 = $phistinfo{$holder}{'date_time'}."|".$phistinfo{$holder}{'type_id'}."|".$phistinfo{$holder}{'parameter_set_id'}."|".$phistinfo{$holder}{'parameter_set_version'}."|".$phistinfo{$holder}{'facility'};

	if(!defined($ehistoffkey)){
		$ifOff = 0;
	}

	if(!defined($lhistoffinfo{$lhistoffkey1}) || !defined($lhistoffinfo{$lhistoffkey2})){
		#$ifOff = 0;
	}else{
		$ifOff=0;
	}
	if(!$ifOff){
		return($currentsite);
	}
	my $numofvs=$phistinfo{$holder}{'number_of_values'};

	@vs = split(',',$phistinfo{$holder}{'values'});

	my $datetime=$phistinfo{$holder}{'date_time'};


	my $parmkey=$phistinfo{$holder}{'parameter_name'}."|".$phistinfo{$holder}{'facility'};
	my $parag1=undef;
	my $parag2=undef;
	my $parag3=undef;
	if(defined($parminfo{$parmkey})){
		$parag1=$parminfo{$parmkey}{'parameter_group_1'};
		$parag2=$parminfo{$parmkey}{'parameter_group_2'};
		$parag3=$parminfo{$parmkey}{'parameter_group_3'};
	}else{
		$parag1='';
		$parag2='';
		$parag3='';
	}

	my $entkey = $phistinfo{$holder}{'type_id'}."|".$phistinfo{$holder}{'facility'};


	for($i=1;$i<=$#vs+1;$i++){

		if(!defined($offoutput{$phistfilenname})){
			$offoutput{$phistfilenname} = join("|",("date_time","fab","entity_type","entity_id","unit_id","site","parameter_set_id","parameter_set_version"
													,"parameter_name","exceed_limit","test_flag","paramter_grp_1"
													,"parameter_grp_2","parameter_grp_3","format_flag","result","lim_date","low_lim","high_lim"))."\n";
		}
                my $progName="FSNL::" .  $phistinfo{$holder}{'parameter_set_id'} .
			         "::" .  $phistinfo{$holder}{'facility'} . "::WKS";

		my $offline = join("|",(FormatField($phistinfo{$holder}{'date_time'}),FormatField($phistinfo{$holder}{'facility'}),FormatField($entinfo{$entkey})
							,FormatField($phistinfo{$holder}{'type_id'}),FormatField($unitid),FormatField($currentsite)
							,FormatField($phistinfo{$holder}{'parameter_set_id'})
							,FormatField($phistinfo{$holder}{'parameter_set_version'}),FormatField($phistinfo{$holder}{'parameter_name'})
							,FormatField($phistinfo{$holder}{'exceed_limit_flag'}),FormatField($phistinfo{$holder}{'test_data_flag_1'})
							,FormatField($parag1), FormatField($parag2), FormatField($parag3), FormatField($phistinfo{$holder}{'format_flag'})
							,FormatField($vs[$i-1]), FormatField((split / /, ($phistinfo{$holder}{'date_time'})[0]))
							,FormatField($phistinfo{$holder}{'low_lim'}), FormatField($phistinfo{$holder}{'high_lim'})))."\n";
		$offoutput{$phistfilenname} .= $offline;

		$currentsite=$currentsite+1;

	}

	return($currentsite);
}
##############################################################################
# Subroutine: GetMetaByLot
##############################################################################
sub GetMetaByLot{
	my $lot=shift();
	my $in_product=shift();
	my $hash=undef;
	if(defined($missingLot{$lot})){
		if($hOptions{FINALLOT}){
			return ($lot,"N/A","N/A",$in_product);
		}else{
			return ("N/A","N/A","N/A",$in_product);
		}
	}
	if(defined($lothashes{$lot})){
		$hash = $lothashes{$lot};
	}else{
		if($hOptions{FINALLOT}){
			$hash = getRefdb->getMetaDataFinalLot($lot);
		}else{
			$hash = getRefdb->getMetaData($lot);
		}
		if(keys %$hash > 0){
			$lothashes{$lot}=$hash;
		}else{
			WARN("Bad.. Meta Not Found for Lot = ".$lot);
			$missingLot{$lot}=1;
			if($hOptions{FINALLOT}){
				return ($lot,"N/A","N/A", $in_product);
			}else{
				return ("N/A","N/A","N/A", $in_product);
			}
		}
	}
	if(!defined($prodinfo{$hash->{product}}))
	{
		$prodinfo{$hash->{product}}=$hash->{package};
	}

	if($hOptions{FINALLOT}){
		return ($lot,$hash->{lot_owner},$hash->{lot_class},$hash->{product},$hash->{family},"N/A",$hash->{package});
	}else{
		return ($hash->{source_lot},$hash->{lot_owner},$hash->{lot_class},$hash->{product},$hash->{family},$hash->{process},"N/A");
	}
}
##############################################################################
# Subroutine: OutputLEH
##############################################################################
sub OutputLEH{
	my $holder=undef;
	%fhs=();
	INFO("start output LEH files");
	%output=();
	%erroutput=();
	%headers=();
	%lehprogramhash=();
	foreach $holder (sort keys %lhistinfo){
		if(defined($prodpattern)){
			if($lhistinfo{$holder}{"product_id"} =~ /$prodpattern/){
			}else{
				next;
			}
		}
		my $operkey=$lhistinfo{$holder}{"operation"}."|".$lhistinfo{$holder}{"facility"};
		my $entkey=$lhistinfo{$holder}{"equip_id"}."|".$lhistinfo{$holder}{"facility"};

		my $lot=$lhistinfo{$holder}{"lot_id"};
#		my($sourcelot,$lotowner,$lotclass,$product) = GetMetaByLot($lot);
		my $prod = $lhistinfo{$holder}{"product_id"};

		my $newline=FormatField($lhistinfo{$holder}{"lot_id"}).",".FormatField($lotinfo{$lhistinfo{$holder}{"lot_id"}})
					.",".FormatField($lhistinfo{$holder}{"operation"})
					.",".FormatField($operinfo{$operkey}{"oper_group_1"}).",".FormatField($operinfo{$operkey}{"oper_group_2"})
					.",".FormatField($operinfo{$operkey}{"oper_group_3"}).",".FormatField($operinfo{$operkey}{"units"})
					.",".FormatField($operinfo{$operkey}{"short_description"}).",".FormatField($lhistinfo{$holder}{"owner"})
					.",".FormatField($lhistinfo{$holder}{"TI_operator_id"}).",".FormatField($lhistinfo{$holder}{"TO_operator_id"})
					.",".FormatField($lhistinfo{$holder}{"loss_quantity"}).",".FormatField($lhistinfo{$holder}{"product_id"})
					.",".FormatField($prodinfo{$lhistinfo{$holder}{"product_id"}}).",".FormatField($lhistinfo{$holder}{"route"})
					.",".FormatField($lhistinfo{$holder}{"lot_quantity"}).",".FormatField($lhistinfo{$holder}{"equip_id"})
					.",".FormatField($lhistinfo{$holder}{"rework_flag"}).",".FormatField($lhistinfo{$holder}{"rework_cat"})
					.",".FormatField($lhistinfo{$holder}{"rework_count"}).",".FormatField($lhistinfo{$holder}{"hot_lot_flag"})
					.",".FormatField($lhistinfo{$holder}{"hold_flag"}).",".FormatField($lhistinfo{$holder}{"comment"})
					.",".FormatDate($lhistinfo{$holder}{"TrackIN_time"}).",".FormatDate($lhistinfo{$holder}{"TrackOUT_time"})
					.",".FormatField($entinfo{$entkey}).",".formatSourceLot($lhistinfo{$holder}{"sourcelot"},$lot)
					.",".FormatField($lhistinfo{$holder}{"lotclass"});
		my $fname = $preoutputfilename."_".$lhistinfo{$holder}{"product_id"};
		if(defined($headers{$fname})){
		}else{
			$headers{$fname} = PrintLEHHeader($prod,$lhistinfo{$holder}{"facility"},$fname);
		}
		if(defined($missingLot{$lot}) || defined($missingProduct{$prod})){
			if(defined($erroutput{$fname})){

			}else{
				$erroutput{$fname} = $headers{$fname};
				$erroutput{$fname} .= "<DATA>\n";
				$erroutput{$fname} .=  "lot,lot_type,sequence_number,condition1,condition2,condition3,unit,step,owner,PI,PO,loss_quantity,product,pkg_id,stage,lot_quantity,PE,rework_flag,rework_cat,rework_count,hot_lot_flag,hold_flag,recipe,TI,TO,entity_type,SOURCE_LOT,LOT_CLASS\n";


			}
			$erroutput{$fname} .= $newline."\n";
		}else{
			if(defined($output{$fname})){

			}else{
				$output{$fname} = $headers{$fname};
				$output{$fname} .= "<DATA>\n";
				$output{$fname} .=  "lot,lot_type,sequence_number,condition1,condition2,condition3,unit,step,owner,PI,PO,loss_quantity,product,pkg_id,stage,lot_quantity,PE,rework_flag,rework_cat,rework_count,hot_lot_flag,hold_flag,recipe,TI,TO,entity_type,SOURCE_LOT,LOT_CLASS\n";


			}
			$output{$fname} .= $newline."\n";
		}

	}

	OutputFiles("leh",1,0);
	INFO("end output leh files");
}
##############################################################################
# Subroutine: MakeSubDir
##############################################################################
sub MakeSubDir{
	my $ext=shift();
	my $subfolder=$ext;
	my $poutdir=$hOptions{out}."/".$subfolder;
	if(-d $poutdir){

	}else{
		printf STDERR "Making output directory: $poutdir\n";
		my $mkdir_ret = mkdir($poutdir, 0777);
		if ($mkdir_ret != 1) {
			dpExit(1,"Fail to make output directory $poutdir");
		}
	}
}
##############################################################################
# Subroutine: OutputFiles
##############################################################################
sub OutputFiles{
	my $ext=shift();
	my $ifdata=shift();
	my $ifSubfolder = shift;
	my $subfolder=$ext;
	my $poutdir= ""; #$hOptions{out}."/".$subfolder;
	if($ifSubfolder) {
		$poutdir= $hOptions{out}."/".$subfolder;
	} else {
		$poutdir= $hOptions{out};
	}
	#INFO("IM HERE $hOptions{fork}");
	if(-d $poutdir){

	}else{
		if($ifSubfolder) {
			printf STDERR "Making output directory: $poutdir\n";
			my $mkdir_ret = mkdir($poutdir, 0777);
			if ($mkdir_ret != 1) {
				dpExit(1,"Fail to make output directory $poutdir");
			}
		}
	}

	my $holder = undef;
	foreach $holder (sort keys %output)
	{
		my $fn=$holder;
		my $outdir=$poutdir;
		#$fn =~ s/ //g;
		#$fn =~ s/\///g;
		if($subfolder eq "leh" && defined($hOptions{LEHGROUP})){
			my $pn=$lehprogramhash{$holder};
			$pn =~ s/ //g;
			$pn =~ s/\///g;
			$outdir .= "/".$pn;
			if(-d $outdir){

			}else{
				printf STDERR "Making output directory: $outdir\n";
				my $mkdir_ret = mkdir($outdir, 0777);
				if ($mkdir_ret != 1) {
					dpExit(1,"Fail to make output directory $outdir");
				}
			}
		}
		#INFO("Fork dir=$hOptions{FORK}");
		#INFO("OUT dir=$outdir");
		my $wr=PDF::DpWriter->new(
		{
			outdir => $outdir,
			forkdir => $hOptions{FORK},
			basename => ($fn),
			ext => $ext,
			gzipIFF  => 'Y'
		}
		);
		if($ifdata){
			$output{$holder} .= "</DATA>\n";
		}


		$wr->open;
		$wr->put($output{$holder});
		$wr->close;

		# if($forkDirectory ne "") {

		# 	my $forkdir = $forkDirectory . "/PRODUCTION/";
		# 	$wr->outdir($forkdir);
		# 	$wr->basename($fn);
		# 	$wr->ext($ext);

		# 	if($ifdata){
		# 		$output{$holder} .= "</DATA>\n";
		# 	}
		# 	$wr->open;
		# 	$wr->put($output{$holder});
		# 	$wr->close;
		# }
	}

	if(keys %erroutput > 0){
		#$poutdir=$hOptions{out}."/".$subfolder;
		$poutdir=$hOptions{out};
		if(-d $poutdir){

		}else{
			printf STDERR "Making output directory: $poutdir\n";
			make_path($poutdir);
		}
		foreach $holder (sort keys %erroutput){
			my $fn=$holder;
			my $outdir = $poutdir;
			if($subfolder eq "leh" && defined($hOptions{LEHGROUP})){
			my $pn=$lehprogramhash{$holder};
			$pn =~ s/ //g;
			$pn =~ s/\///g;

				$outdir .= "/".$pn;
				if(-d $outdir){

				}else{
					printf STDERR "Making output directory: $outdir\n";
					my $mkdir_ret = mkdir($outdir, 0777);
					if ($mkdir_ret != 1) {
						dpExit(1,"Fail to make output directory $outdir");
					}
				}
			}

			$fn =~ s/ //g;
			$fn =~ s/\///g;
			INFO("Fork dir=$hOptions{FORK}");
		  INFO(" OUT dir=$outdir");
			my $wr=PDF::DpWriter->new(
			{
				outdir => $outdir,
				forkdir => $hOptions{FORK},
				basename => ($fn),
				ext => $ext,
				noMeta => 1,
				gzipIFF  => 'Y'
			}
		);
		if($ifdata){
			$erroutput{$holder} .= "</DATA>\n";
		}
		$wr->open;
		$wr->put($erroutput{$holder});
		$wr->close;

		# if($forkDirectory ne "") {

		# 	my $forkdir = $forkDirectory . "/PRODUCTION/";
		# 	$wr->outdir($forkdir);
		# 	$wr->basename($fn);
		# 	$wr->ext($ext);

		# 	if($ifdata){
		# 		$output{$holder} .= "</DATA>\n";
		# 	}
		# 	$wr->open;
		# 	$wr->put($output{$holder});
		# 	$wr->close;
		# }

		}

	}
}
##############################################################################
# Subroutine: OutputFiles
##############################################################################
sub OutputMetrologyOfflineFiles{
	my $ext=shift();

	my $subfolder=$ext;
	#my $poutdir=$hOptions{out}."/".$subfolder;
	my $poutdir=$hOptions{out};
	if(-d $poutdir){

	}else{
		printf STDERR "Making output directory: $poutdir\n";
		my $mkdir_ret = mkdir($poutdir, 0777);
		if ($mkdir_ret != 1) {
			dpExit(1,"Fail to make output directory $poutdir");
		}
	}

	my $holder = undef;
	foreach $holder (sort keys %offoutput)
	{
		my $fn=$holder;
		my $outdir=$poutdir;


		my $wr=PDF::DpWriter->new(
		{
			outdir => $outdir,
			forkdir => $hOptions{FORK},
			basename => ($fn),
			ext => $ext,
			gzipIFF  => 'Y',
		}
		);

		$wr->open;
		$wr->put($offoutput{$holder});
		$wr->close;

		# if($forkDirectory ne "") {

		# 	my $forkdir = $forkDirectory . "/PRODUCTION/";
		# 	$wr->outdir($forkdir);
		# 	$wr->basename($fn);
		# 	$wr->ext($ext);

		# 	$wr->open;
		# 	$wr->put($output{$holder});
		# 	$wr->close;
		# }
	}


}
##############################################################################
# Subroutine: OutputLatt
##############################################################################
sub OutputLatt{

	my $basename=shift();
	my $ext=shift();
	my $newext=shift();
	my $filepath=$indir.$basename."\.".$ext;
	# Process no more than 100 lots per output file to keep file size < 32K lines.
	my $outputQty = 0;
	my $erroutputQty = 0;
	my $outputIx = 1;
	my $erroutputIx = 1;
	my $last_lot = "wjefnwejbwjkfje";
	my $newbasename=undef;
	%output=();
	%erroutput=();
	my @work=[];

	INFO("Processing ".$filepath);

	open(fhIn, "<$filepath") || dpExit(1,"Unable to open file $filepath");
	while(<fhIn>){
		chomp;
		s/\r//;
		my $line=$_;
		@work = split(",");
		if($#work >= 1){
			my $lot = $work[0];
			$lot =~ s/\s+$//;
			if($lot =~ /^\s*$/){
				WARN("lot undefined in line: ".$line);
			}else{
			    # Reformat line to replace commas with tabs.
				my ($c_lot, $c_attr_num, $c_attr_name, $c_attr_type, $c_attr_val) = getLotAttrColumns($line);
				my $new_line = $c_lot."\t".$c_attr_num."\t".$c_attr_name."\t".$c_attr_type."\t".$c_attr_val;
				my($sourcelot,$lotowner,$lotclass,$product) = GetMetaByLot($lot,"N/A");
				#my $facility=$lhistlot2facility{$lot};
				if(defined($missingLot{$lot})){
			                if ( $lot ne $last_lot )
					{
						$outputQty = $outputQty + 1;
						if ( $outputQty > 100 )
						{
							$outputIx = $outputIx + 1;
							$outputQty = 0;
						}
					}
					$newbasename = $basename."\.".$outputIx."\.".$ext;
					if(defined($erroutput{$newbasename})){
					}else{
						$erroutput{$newbasename} = "";
					}
					$erroutput{$newbasename} .= $new_line."\t".formatSourceLot($sourcelot,$lot)."\t".FormatField($lotclass)."\n";
				}else{
			                if ( $lot ne $last_lot )
					{
						$erroutputQty = $erroutputQty + 1;
						if ( $erroutputQty > 100 )
						{
							$erroutputIx = $erroutputIx + 1;
							$erroutputQty = 0;
						}
					}
					$newbasename = $basename."\.".$erroutputIx."\.".$ext;
					if(defined($output{$newbasename})){
					}else{
						$output{$newbasename} = "";
					}
					$output{$newbasename} .= $new_line."\t".formatSourceLot($sourcelot,$lot)."\t".FormatField($lotclass)."\n";
				}
				$last_lot = $lot;
			}
			my $attr_name = $work[2];
			$attr_name =~ s/\s+$//;
			if ( $attr_name =~ /^EPI SLOT/ )
			{
				my $attr_value = $work[4];
				$attr_value =~ s/\s+$//;
				if ( !defined($sicinfo{$lot} ))
				{
					$sicinfo{$lot} = {$attr_name=>$attr_value};
				}
				else
				{
					if ( !defined( $sicinfo{$lot}{$attr_name}))
					{
						$sicinfo{$lot}{$attr_name}=$attr_value;
					}
				}
			}
		}else{
			WARN("invalid line in latt:".$line);
		}
	}
	#my $fmtpath=$inputdir."/".$basename."\.bcp_fmt";
#	print Dumper(\%sicinfo);
	OutputFiles($newext,0,0);
}

sub getLotAttrColumns
{
my $str = shift;
my $ix = 0;
my $newix;

my $lot;
my $attr_num;
my $attr_name;
my $attr_val;
my $attr_type;
my $valid = 0;

$newix=index($str,",",$ix);
if ( $newix > 0 )
{
   $lot = substr($str,$ix,($newix - $ix));
   $lot =~ s/\s//g;
   $ix = $newix + 1;
   $newix=index($str,",",$ix);
   if ( $newix > 0 )
   {
      $attr_num=substr($str,$ix,($newix - $ix));
      $attr_num =~ s/\s//g;
      $ix = $newix + 1;
      # After attribute name is an indicator of whether the value is blank, (A)SCII or (N)umeric.
      my $found = 0;
      $newix=index($str,",A,",$ix);
      if ( $newix == -1 )
      {
         $newix=index($str,",N,",$ix);
         if ( $newix == -1 )
         {
            $newix=index($str,", ,",$ix);
            if ( $newix >= 0 )
            {
               $found = 1;
	       $attr_type = " ";
            }
         }
         else
         {
	    $attr_type = "N";
            $found = 1;
         }
      }
      else
      {
	 $attr_type = "A";
         $found = 1;
      }
      if ( $found )
      {
         $attr_name=substr($str,$ix,($newix - $ix));
		 $attr_name=~s/\s+$//;
         $ix = $newix + 3;
         $attr_val=substr($str,$ix);
		 $attr_val=~s/\s+$//;
		 $attr_val=~s/'//; # Strip single quotes
         return( $lot, $attr_num, $attr_name, $attr_type, $attr_val);
      }
   }
}
return( "N/A", "N/A", "N/A", "N/A", "N/A");
}

##############################################################################
# Subroutine: AddLotInfoForCSVFile
##############################################################################
sub AddLotInfoForCSVFile{
	my $basename=shift();
	my $ext=shift();
	my $newext=shift();

	my $filepath=$indir.$basename."\.".$ext;
	INFO("Processing ".$filepath);
	my $fmtpath=$hOptions{fmtdir}."/".$basename."\.bcp_fmt";
	my $line=undef;
	my @lines=`$perlname $readWksm $fmtpath $filepath`;

	my @work=[];
	my $iGotHeader = 0;

	my $headerline=undef;

	my $lotidColumn=undef;
	%output=();
	%erroutput=();
	$basename = $basename."\.".$ext;
	my $line=undef;
	my $newline = undef;
	my $csv=Text::CSV->new({sep_char => ','});

	foreach $line(@lines){
		$_=$line;
		chomp;
		s/\r//;


		if($_ =~ /^\s*$/){
			next;
		}

		if($csv->parse($_)){
			@work=$csv->fields();
		}else{
			WARN("error: line could not be parsed--".$line);
			next;
		}

		$newline = $_;
		#$newline =~ s/"//g;
		if (not $iGotHeader)
		{
			#get column header info

			for (my $i = 0;$i <= $#work;$i++)
			{
				if ($work[$i] eq "lot_id")
				{
					$lotidColumn = $i;


				}


			}
			$iGotHeader = 1;
			if(defined($lotidColumn)){
				$headerline=$newline;
			}else{
				ERROR("error lotid column undefined: ".$filepath);
				dpExit(1,"error lotid necessary columns undefined: ".$filepath);
			}

		}else{

			my $lotid = $work[$lotidColumn];
			if($lotid =~ /^\s*$/){
				WARN("lot id undefined in line:".$newline);
				next;
			}

			my($sourcelot,$lotowner,$lotclass,$product) = GetMetaByLot($lotid,"N/A");
			if(defined($missingLot{$lotid})){
				if(defined($erroutput{$basename})){
				}else{
					$erroutput{$basename} .= $headerline.",\"SOURCE_LOT\",\"LOT_OWNER\"";
				}
				$erroutput{$basename} .= $line.",".formatSourceLot($sourcelot,$lotid).",".FormatField($lotowner)."\n";
			}else{
				if(defined($output{$basename})){
				}else{
					$output{$basename} .= $headerline.",\"SOURCE_LOT\",\"LOT_OWNER\"";
				}
				$output{$basename} .= $line.",".formatSourceLot($sourcelot,$lotid).",".FormatField($lotowner)."\n";
			}



		}

	}
	OutputFiles($newext,0,0);
}
##############################################################################
# Subroutine: OutputOriginalFile
##############################################################################
sub OutputOriginalFile{

	my $basename=shift();
	my $ext=shift();
	my $newext=shift();
	my $filepath=$indir.$basename."\.".$ext;
	INFO("Copying ".$filepath);
	#my $fmtpath=$inputdir."/".$basename."\.bcp_fmt";
	my $outputfile=$hOptions{out}."/".$basename."\.".$ext."\.".$newext;
	copy($filepath,$outputfile) or dpExit(1,"Copy failed: $!");
	my $ext2 = "${ext}.${newext}";
	if($hOptions{FORK} ne "") {
		forkFile($outputfile, $hOptions{FORK}, $basename, $ext2, "PRODUCTION");
	}else {
		INFO("Compress $outputfile with gzip");
		my $gzOutfile = $outputfile.".gz";
		if(-e $gzOutfile) {
		  INFO("$gzOutfile already exist");
		  INFO("Delete $gzOutfile");
		  unlink $gzOutfile;
		}
		qx(gzip "$outputfile");
	}
	#if($hOptions{FORK} ne "") {
	#	forkFile($outputfile, $hOptions{FORK}, $basename, $ext2, "PRODUCTION");
	#}

}

##############################################################################
# Subroutine: GenerateCSVFile
##############################################################################
sub GenerateCSVFile{

	my $basename=shift();
	my $ext=shift();
	my $newext=shift();
	my $ifsubdir=shift();
	my $outputfile=undef;
	my $filepath=$indir.$basename."\.".$ext;
	INFO("Converting ".$filepath);
	#my $fmtpath=$inputdir."/".$basename."\.bcp_fmt";
	my $fmtpath=$hOptions{fmtdir}."/".$basename."\.bcp_fmt";
	if($ifsubdir){
		MakeSubDir($newext);
		$outputfile=$hOptions{out}."/".$newext."/".$basename."\.".$ext."\.".$newext;
	}else{
		$outputfile=$hOptions{out}."/PRODUCTION/".$basename."\.".$ext."\.".$newext;
	}
	my $res=`$perlname $readWksm $fmtpath $filepath > $outputfile`;
	my $ext2 = "${ext}.${newext}";
	if($hOptions{FORK} ne "") {
		forkFile($outputfile, $hOptions{FORK}, $basename, $ext2, "PRODUCTION");
	}else {
		INFO("Compress $outputfile with gzip");
		my $gzOutfile = $outputfile.".gz";
		if(-e $gzOutfile) {
      INFO("$gzOutfile already exist");
      INFO("Delete $gzOutfile");
      unlink $gzOutfile;
    }
    qx(gzip "$outputfile");
	}


}


##############################################################################
# Subroutine: ProcessParmFile
##############################################################################
sub ProcessParmFile{
	my $basename=shift();
	my $ext=shift();

	my $filepath=$indir.$basename."\.".$ext;
	INFO("Processing ".$filepath);
	my $fmtpath=$hOptions{fmtdir}."/".$basename."\.bcp_fmt";
	my $line=undef;
	my @lines=`$perlname $readWksm $fmtpath $filepath`;
	my @work=[];

	my $iGotHeader = 0;
	my $paranameColumn=undef;
	my $facilityColumn=undef;
	my $parag1Column=undef;
	my $parag2Column=undef;
	my $parag3Column=undef;


	foreach $line(@lines){
		$_=$line;
		chomp;
		s/\r//;
		s/\"//g;

		if($_ =~ /^\s*$/){
			next;
		}
		@work = split(',');
		if (not $iGotHeader)
		{
			#get column header info
			for (my $i = 0;$i <= $#work;$i++)
			{
				if ($work[$i] eq "parameter_name")
				{
					$paranameColumn = $i;


				}
				elsif($work[$i] eq "facility")
				{
					$facilityColumn = $i;


				}
				elsif ($work[$i] eq "parameter_group_1")
				{
					$parag1Column = $i;


				}
				elsif ($work[$i] eq "parameter_group_2")
				{
					$parag2Column = $i;


				}
				elsif ($work[$i] eq "parameter_group_3")
				{
					$parag3Column = $i;

				}

			}
			$iGotHeader = 1;
			if(defined($paranameColumn) && defined($facilityColumn) && defined($parag1Column) && defined($parag2Column) && defined($parag3Column)){

			}else{
				ERROR("necesary parminfo columns undefined".$filepath);
				dpExit(1,"error parminfo necessary columns undefined: ".$filepath);
			}

		}else{
			my $paraname=$work[$paranameColumn];

			if($paraname =~ /^\s*$/){
				WARN("necessary paraname undefined line in oper file--".$line);
				next;
			}

			my $facility=$work[$facilityColumn];
			#my $facility=$equip6_id;
			if($facility =~ /^\s*$/){
				WARN("necessary facility undefined line--".$line);
				next;
			}

			my $parag1=$work[$parag1Column];
			if($parag1 =~ /^\s*$/){
				DEBUG("optional parag1 undefined line--".$line);

			}

			my $parag2=$work[$parag2Column];
			if($parag2 =~ /^\s*$/){
				DEBUG("optional parag2 undefined line--".$line);

			}

			my $parag3=$work[$parag3Column];
			if($parag3  =~ /^\s*$/){
				DEBUG("optional parag3 undefined line--".$line);

			}



			my $key=$paraname."|".$facility;


			if(defined($parminfo{$key})){
				WARN("duplicate paraname and facility line--".$line);
				next;
			}

			$parminfo{$key}={"parameter_group_1"=>$parag1,"parameter_group_2"=>$parag2,"parameter_group_3"=>$parag3};



		}

	}
}



##############################################################################
# Subroutine: ProcessAndOutputEhistFile
##############################################################################
sub ProcessAndOutputEhistFile{
	my $basename=shift();
	my $ext=shift();

	my $filepath=$indir.$basename."\.".$ext;
	INFO("Processing ".$filepath);
	my $fmtpath=$hOptions{fmtdir}."/".$basename."\.bcp_fmt";
	my $line=undef;
	my @lines=`$perlname $readWksm $fmtpath $filepath`;

	my @work=[];
	my $iGotHeader = 0;

	my $entityidColumn=undef;
	my $facilityColumn=undef;
	my $tisColumn=undef;
	my $ssColumn=undef;
	my $ossColumn=undef;

	my $s1Column=undef;
	my $s2Column=undef;
	my $s3Column=undef;
	my $s4Column=undef;
	my $s5Column=undef;
	my $s6Column=undef;
	my $s7Column=undef;
	my $s8Column=undef;
	my $s9Column=undef;

	my $commentColumn=undef;
	my $operatoridColumn=undef;
	my $naColumn=undef;
	my $oosifColumn=undef;
	my $failfColumn=undef;
	my $frdtfColumn=undef;
	my $dtfColumn=undef;
	my $tdtColumn=undef;

	my $dtColumn=undef;
	my $psiColumn=undef;
	my $psvColumn=undef;

	%ehistinfo=();
	%entitytransaction=();

	my $line=undef;
	my $csv=Text::CSV->new({sep_char => ','});

	foreach $line(@lines){
		$_=$line;
		chomp;
		s/\r//;


		if($_ =~ /^\s*$/){
			next;
		}
=head
		if($_ =~ /PKPNP13/){
			INFO($_);
		}
=cut
		if($csv->parse($_)){
			@work=$csv->fields();
		}else{
			WARN("error: line could not be parsed--".$line);
			next;
		}
		if (not $iGotHeader)
		{
			#get column header info

			for (my $i = 0;$i <= $#work;$i++)
			{
				if ($work[$i] eq "entity_id")
				{
					$entityidColumn = $i;


				}
				elsif($work[$i] eq "facility")
				{
					$facilityColumn = $i;


				}
				elsif($work[$i] eq "time_in_status")
				{
					$tisColumn = $i;


				}elsif($work[$i] eq "standard_status")
				{
					$ssColumn = $i;


				}elsif($work[$i] eq "old_standard_status")
				{
					$ossColumn = $i;


				}elsif($work[$i] eq "status_1")
				{
					$s1Column = $i;


				}elsif($work[$i] eq "status_2")
				{
					$s2Column = $i;


				}elsif($work[$i] eq "status_3")
				{
					$s3Column = $i;


				}elsif($work[$i] eq "status_4")
				{
					$s4Column = $i;


				}elsif($work[$i] eq "status_5")
				{
					$s5Column = $i;


				}elsif($work[$i] eq "status_6")
				{
					$s6Column = $i;


				}elsif($work[$i] eq "status_7")
				{
					$s7Column = $i;


				}elsif($work[$i] eq "status_8")
				{
					$s8Column = $i;


				}elsif($work[$i] eq "status_9")
				{
					$s9Column = $i;


				}elsif($work[$i] eq "comment")
				{
					$commentColumn = $i;


				}elsif($work[$i] eq "operator_id")
				{
					$operatoridColumn = $i;


				}elsif($work[$i] eq "new_availability")
				{
					$naColumn = $i;


				}elsif($work[$i] eq "oosi_flag")
				{
					$oosifColumn = $i;

				}elsif($work[$i] eq "fail_flag")
				{
					$failfColumn = $i;

				}elsif($work[$i] eq "frdt_flag")
				{
					$frdtfColumn = $i;


				}elsif($work[$i] eq "dt_flag")
				{
					$dtfColumn = $i;


				}elsif($work[$i] eq "transaction_date_time")
				{
					$tdtColumn = $i;


				}elsif($work[$i] eq "date_time")
				{
					$dtColumn = $i;


				}elsif($work[$i] eq "parameter_set_id")
				{
					$psiColumn = $i;


				}elsif($work[$i] eq "parameter_set_version")
				{
					$psvColumn = $i;


				}


			}
			$iGotHeader = 1;
			if(defined($entityidColumn) && defined($facilityColumn) && defined($tisColumn) && defined($ssColumn)
					&& defined($ossColumn) && defined($s1Column) && defined($s2Column) && defined($s3Column)
					&& defined($s4Column) && defined($s5Column) && defined($s6Column) && defined($s7Column)
					&& defined($s8Column) && defined($s9Column) && defined($commentColumn) && defined($operatoridColumn)
					&& defined($naColumn) && defined($oosifColumn) && defined($failfColumn) && defined($frdtfColumn)
					&& defined($dtfColumn) && defined($tdtColumn) && defined($dtColumn) && defined($psiColumn) && defined($psvColumn)){

			}else{
				ERROR("error ehist columns undefined: ".$filepath);
				dpExit(1,"error ehist necessary columns undefined: ".$filepath);
			}

		}else{
			my $ifQualified = 1;

			my $na=$work[$naColumn];

			if($na =~ /^\s*$/){
				DEBUG("optional new_availability undefined line--".$line);
			}
			my $tmpna=$na;
			$tmpna =~ s/\s//g;
			my $oosif=$work[$oosifColumn];

			if($oosif  =~ /^\s*$/){
				DEBUG("optional oosi_flag undefined line--".$line);
			}

			my $failf=$work[$failfColumn];

			if($failf  =~ /^\s*$/){
				DEBUG("optional fail_flag undefined line--".$line);
			}

			my $frdtf=$work[$frdtfColumn];

			if($frdtf  =~ /^\s*$/){
				DEBUG("optional frdt_flag undefined line--".$line);
			}

			my $dtf=$work[$dtfColumn];

			if($dtf  =~ /^\s*$/){
				DEBUG("optional dt_flag undefined line--".$line);
			}
			my $entityid=$work[$entityidColumn];
			if($entityid  =~ /^\s*$/){
				DEBUG("optional entityid undefined line--".$line);
			}

			my $facility=$work[$facilityColumn];
			#my $facility=$equip6_id;

			if($facility =~ /^\s*$/){
				DEBUG("optional facility undefined line--".$line);
			}


			my $psi=$work[$psiColumn];
			if($psi =~ /^\s*$/){
			}else{
				my $psv=$work[$psvColumn];
				my $dt=$work[$dtColumn];
				if($dt =~ /^\s*$/){
					DEBUG("optional transaction_date_time undefined line--".$line);

				}else{
					if($dt =~ /^(\w+) (\d{2}) (\d{4}) (\d{2})\:(\d{2}):(\d{2})\:\d{3}(\w{2})$/){
						$dt=FormatDate($dt);

					}else{
						ERROR("error invalid datetime line--".$line);
						next;
					}
				}

				my $ehistoffkey=$psi."|".$psv."|".$dt."|".$facility."|".$entityid;

				if(defined($ehistoffinfo{$ehistoffkey})){
					WARN("duplicate ehist metrology offline key: ".$ehistoffkey." in the line".$line);
				}else{
					$ehistoffinfo{$ehistoffkey} = 1;
				}
			}
			if($tmpna ne "" ||$oosif ne "N" || $failf ne "N" || $frdtf ne "N" || $dtf ne "N"){
			}else{

				#next;
				$ifQualified = 0;
			}







			my $tis=$work[$tisColumn];
			if($tis =~ /^\s*$/){
				DEBUG("optional time_in_status undefined line--".$line);

			}

			my $ss=$work[$ssColumn];
			if($ss =~ /^\s*$/){
				DEBUG("optional standard_status undefined line--".$line);

			}
			my $oss=$work[$ossColumn];
			if($oss=~ /^\s*$/){
				DEBUG("optional old_standard_status undefined line--".$line);

			}

			my $s1=$work[$s1Column];
			if($s1 =~ /^\s*$/){
				DEBUG("optional status_1 undefined line--".$line);

			}

			my $s2=$work[$s2Column];
			if($s2 =~ /^\s*$/){
				DEBUG("optional status_2 undefined line--".$line);

			}

			my $s3=$work[$s3Column];
			if($s3 =~ /^\s*$/){
				DEBUG("optional status_3 undefined line--".$line);

			}

			my $s4=$work[$s4Column];
			if($s4 =~ /^\s*$/){
				DEBUG("optional status_4 undefined line--".$line);

			}

			my $s5=$work[$s5Column];
			if($s5 =~ /^\s*$/){
				DEBUG("optional status_5 undefined line--".$line);

			}

			my $s6=$work[$s6Column];
			if($s6 =~ /^\s*$/){
				DEBUG("optional status_6 undefined line--".$line);

			}

			my $s7=$work[$s7Column];
			if($s7 =~ /^\s*$/){
				DEBUG("optional status_7 undefined line--".$line);

			}

			my $s8=$work[$s8Column];
			if($s8 =~ /^\s*$/){
				DEBUG("optional status_8 undefined line--".$line);

			}

			my $s9=$work[$s9Column];
			if($s9 =~ /^\s*$/){
				DEBUG("optional status_9 undefined line--".$line);

			}


			my $operatorid=$work[$operatoridColumn];
			if($operatorid =~ /^\s*$/){
				DEBUG("optional operatorid undefined line--".$line);

			}


			my $comment=$work[$commentColumn];
			if($comment =~ /^\s*$/){
				DEBUG("optional comment undefined line--".$line);

			}

			my $tdt=$work[$tdtColumn];
			if($tdt =~ /^\s*$/){
				DEBUG("optional transaction_date_time undefined line--".$line);

			}else{
				if($tdt =~ /^(\w+) (\d{2}) (\d{4}) (\d{2})\:(\d{2}):(\d{2})\:\d{3}(\w{2})$/){
					$tdt=FormatDate($tdt);

				}else{
					ERROR("error invalid datetime line--".$line);
					next;
				}
			}

			my $ekey = $entityid;
			#INFO("ehist entityid = ".$ekey);
			$ehistinfo{$ekey}=[] unless exists $ehistinfo{$ekey};
			if(!defined($entitytransaction{$ekey})){
				$entitytransaction{$ekey} = $tdt;
			}else{
				if($tdt gt $entitytransaction{$ekey}){
					$entitytransaction{$ekey}=$tdt;
				}
			}
			#push @{$ehistinfo{$ekey}},{"if_qualified"=>$ifQualified,"transaction_date_time"=>$tdt,"line"=>'"'.join('","',(FormatField($entityid),FormatField($tdt),FormatField($facility),FormatField($tis),FormatField($ss),FormatField($oss),FormatField($s1),FormatField($s2),FormatField($s3),FormatField($s4),FormatField($s5),FormatField($s6),FormatField($s7),FormatField($s8),FormatField($s9),FormatField($comment),FormatField($operatorid),FormatField($na),FormatField($oosif),FormatField($failf),FormatField($frdtf),FormatField($dtf))).'"'."\n"};

			push @{$ehistinfo{$ekey}},{"if_qualified"=>$ifQualified,"transaction_date_time"=>$tdt,"entity_id"=>$entityid,"facility"=>$facility
										,"time_in_status"=>$tis,"standard_status"=>$ss,"old_standard_status"=>$oss,"status_1"=>$s1
										,"status_2"=>$s2,"status_3"=>$s3,"status_4"=>$s4,"status_5"=>$s5
										,"status_6"=>$s6,"status_7"=>$s7,"status_8"=>$s8,"status_9"=>$s9
										,"comment"=>$comment,"operator_id"=>$operatorid,"new_availability"=>$na,"oosi_flag"=>$oosif
										,"fail_flag"=>$failf,"frdt_flag"=>$frdtf,"dt_flag"=>$dtf
										};
		}

	}


	ProcessAndOutputEhistUpdFile($basename,$ext);


}

##############################################################################
# Subroutine: ProcessAndOutputEhistUpdFile
##############################################################################
sub ProcessAndOutputEhistUpdFile{
	my $basename=shift();
	my $ext=shift();



	if($basename =~ /_entity_history$/){
		$basename = "edbws_ehist_update";
	}else{
		$basename = "edbws_ehist_upd";
	}
	my $filepath=$indir.$basename."\.".$ext;
	INFO("Processing ".$filepath);
	my $fmtpath=$hOptions{fmtdir}."/".$basename."\.bcp_fmt";
	my $line=undef;
	my @lines=`$perlname $readWksm $fmtpath $filepath`;

	my @work=[];
	my $iGotHeader = 0;

	my $entityidColumn=undef;
	my $facilityColumn=undef;
	my $tisColumn=undef;
	my $ssColumn=undef;
	my $ossColumn=undef;

	my $s1Column=undef;
	my $s2Column=undef;
	my $s3Column=undef;
	my $s4Column=undef;
	my $s5Column=undef;
	my $s6Column=undef;
	my $s7Column=undef;
	my $s8Column=undef;
	my $s9Column=undef;

	my $commentColumn=undef;
	my $operatoridColumn=undef;
	my $naColumn=undef;
	my $oosifColumn=undef;
	my $failfColumn=undef;
	my $frdtfColumn=undef;
	my $dtfColumn=undef;
	my $tdtColumn=undef;

	%ehistupdinfo=();

	my $line=undef;
	my $csv=Text::CSV->new({sep_char => ','});
	my $outputdata="";
	foreach $line(@lines){
		$_=$line;
		chomp;
		s/\r//;


		if($_ =~ /^\s*$/){
			next;
		}

		if($csv->parse($_)){
			@work=$csv->fields();
		}else{
			WARN("error: line could not be parsed--".$line);
			next;
		}
		if (not $iGotHeader)
		{
			#get column header info

			for (my $i = 0;$i <= $#work;$i++)
			{
				if ($work[$i] eq "entity_id")
				{
					$entityidColumn = $i;


				}
				elsif($work[$i] eq "facility")
				{
					$facilityColumn = $i;


				}
				elsif($work[$i] eq "time_in_status")
				{
					$tisColumn = $i;


				}elsif($work[$i] eq "standard_status")
				{
					$ssColumn = $i;


				}elsif($work[$i] eq "old_standard_status")
				{
					$ossColumn = $i;


				}elsif($work[$i] eq "status_1")
				{
					$s1Column = $i;


				}elsif($work[$i] eq "status_2")
				{
					$s2Column = $i;


				}elsif($work[$i] eq "status_3")
				{
					$s3Column = $i;


				}elsif($work[$i] eq "status_4")
				{
					$s4Column = $i;


				}elsif($work[$i] eq "status_5")
				{
					$s5Column = $i;


				}elsif($work[$i] eq "status_6")
				{
					$s6Column = $i;


				}elsif($work[$i] eq "status_7")
				{
					$s7Column = $i;


				}elsif($work[$i] eq "status_8")
				{
					$s8Column = $i;


				}elsif($work[$i] eq "status_9")
				{
					$s9Column = $i;


				}elsif($work[$i] eq "comment")
				{
					$commentColumn = $i;


				}elsif($work[$i] eq "operator_id")
				{
					$operatoridColumn = $i;


				}elsif($work[$i] eq "new_availability")
				{
					$naColumn = $i;


				}elsif($work[$i] eq "oosi_flag")
				{
					$oosifColumn = $i;

				}elsif($work[$i] eq "fail_flag")
				{
					$failfColumn = $i;

				}elsif($work[$i] eq "frdt_flag")
				{
					$frdtfColumn = $i;


				}elsif($work[$i] eq "dt_flag")
				{
					$dtfColumn = $i;


				}elsif($work[$i] eq "transaction_date_time")
				{
					$tdtColumn = $i;


				}


			}
			$iGotHeader = 1;
			if(defined($entityidColumn) && defined($facilityColumn) && defined($tisColumn) && defined($ssColumn)
					&& defined($ossColumn) && defined($s1Column) && defined($s2Column) && defined($s3Column)
					&& defined($s4Column) && defined($s5Column) && defined($s6Column) && defined($s7Column)
					&& defined($s8Column) && defined($s9Column) && defined($commentColumn) && defined($operatoridColumn)
					&& defined($naColumn) && defined($oosifColumn) && defined($failfColumn) && defined($frdtfColumn)
					&& defined($dtfColumn) && defined($tdtColumn)){

			}else{
				ERROR("error ehist columns undefined: ".$filepath);
				dpExit(1,"error ehist necessary columns undefined: ".$filepath);
			}

		}else{

			my $na=$work[$naColumn];

			if($na =~ /^\s*$/){
				DEBUG("optional new_availability undefined line--".$line);
			}
			my $tmpna=$na;
			$tmpna =~ s/\s//g;
			my $oosif=$work[$oosifColumn];

			if($oosif  =~ /^\s*$/){
				DEBUG("optional oosi_flag undefined line--".$line);
			}

			my $failf=$work[$failfColumn];

			if($failf  =~ /^\s*$/){
				DEBUG("optional fail_flag undefined line--".$line);
			}

			my $frdtf=$work[$frdtfColumn];

			if($frdtf  =~ /^\s*$/){
				DEBUG("optional frdt_flag undefined line--".$line);
			}

			my $dtf=$work[$dtfColumn];

			if($dtf  =~ /^\s*$/){
				DEBUG("optional dt_flag undefined line--".$line);
			}

			if($tmpna ne "" ||$oosif ne "N" || $failf ne "N" || $frdtf ne "N" || $dtf ne "N"){
			}else{
				next;
			}

			my $entityid=$work[$entityidColumn];

			if($entityid  =~ /^\s*$/){
				DEBUG("optional entityid undefined line--".$line);

			}

			my $facility=$work[$facilityColumn];
			#my $facility=$equip6_id;

			if($facility =~ /^\s*$/){
				DEBUG("optional facility undefined line--".$line);

			}



			my $tis=$work[$tisColumn];
			if($tis =~ /^\s*$/){
				DEBUG("optional time_in_status undefined line--".$line);

			}

			my $ss=$work[$ssColumn];
			if($ss =~ /^\s*$/){
				DEBUG("optional standard_status undefined line--".$line);

			}
			my $oss=$work[$ossColumn];
			if($oss=~ /^\s*$/){
				DEBUG("optional old_standard_status undefined line--".$line);

			}

			my $s1=$work[$s1Column];
			if($s1 =~ /^\s*$/){
				DEBUG("optional status_1 undefined line--".$line);

			}

			my $s2=$work[$s2Column];
			if($s2 =~ /^\s*$/){
				DEBUG("optional status_2 undefined line--".$line);

			}

			my $s3=$work[$s3Column];
			if($s3 =~ /^\s*$/){
				DEBUG("optional status_3 undefined line--".$line);

			}

			my $s4=$work[$s4Column];
			if($s4 =~ /^\s*$/){
				DEBUG("optional status_4 undefined line--".$line);

			}

			my $s5=$work[$s5Column];
			if($s5 =~ /^\s*$/){
				DEBUG("optional status_5 undefined line--".$line);

			}

			my $s6=$work[$s6Column];
			if($s6 =~ /^\s*$/){
				DEBUG("optional status_6 undefined line--".$line);

			}

			my $s7=$work[$s7Column];
			if($s7 =~ /^\s*$/){
				DEBUG("optional status_7 undefined line--".$line);

			}

			my $s8=$work[$s8Column];
			if($s8 =~ /^\s*$/){
				DEBUG("optional status_8 undefined line--".$line);

			}

			my $s9=$work[$s9Column];
			if($s9 =~ /^\s*$/){
				DEBUG("optional status_9 undefined line--".$line);

			}


			my $operatorid=$work[$operatoridColumn];
			if($operatorid =~ /^\s*$/){
				DEBUG("optional operatorid undefined line--".$line);

			}


			my $comment=$work[$commentColumn];
			$comment =~ s/'//;
			if($comment =~ /^\s*$/){
				DEBUG("optional comment undefined line--".$line);

			}

			my $tdt=$work[$tdtColumn];
			if($tdt =~ /^\s*$/){
				DEBUG("optional transaction_date_time undefined line--".$line);

			}else{
				if($tdt =~ /^(\w+) (\d{2}) (\d{4}) (\d{2})\:(\d{2}):(\d{2})\:\d{3}(\w{2})$/){
					$tdt=FormatDate($tdt);

				}else{
					ERROR("error invalid datetime line--".$line);
					next;
				}
			}

			if(defined($ehistinfo{$entityid})){
				push @{$ehistupdinfo{$entityid}},{"transaction_date_time"=>$tdt,"entity_id"=>$entityid,"facility"=>$facility
										,"time_in_status"=>$tis,"standard_status"=>$ss,"old_standard_status"=>$oss,"status_1"=>$s1
										,"status_2"=>$s2,"status_3"=>$s3,"status_4"=>$s4,"status_5"=>$s5
										,"status_6"=>$s6,"status_7"=>$s7,"status_8"=>$s8,"status_9"=>$s9
										,"comment"=>$comment,"operator_id"=>$operatorid,"new_availability"=>$na,"oosi_flag"=>$oosif
										,"fail_flag"=>$failf,"frdt_flag"=>$frdtf,"dt_flag"=>$dtf
										};
				#$outputdata .= '"'.join('","',(FormatField($entityid),FormatField($tdt),FormatField($facility),FormatField($tis),FormatField($ss),FormatField($oss),FormatField($s1),FormatField($s2),FormatField($s3),FormatField($s4),FormatField($s5),FormatField($s6),FormatField($s7),FormatField($s8),FormatField($s9),FormatField($comment),FormatField($operatorid),FormatField($na),FormatField($oosif),FormatField($failf),FormatField($frdtf),FormatField($dtf))).'"'."\n";
			}
		}

	}
	#return $outputdata;
}


##############################################################################
# Subroutine: ProcessPhistFile
##############################################################################
sub ProcessPhistFile{
	my $basename=shift();
	my $ext=shift();

	my $filepath=$indir.$basename."\.".$ext;
	INFO("Processing ".$filepath);
	my $fmtpath=$hOptions{fmtdir}."/".$basename."\.bcp_fmt";
	my $line=undef;
	my @lines=`$perlname $readWksm $fmtpath $filepath`;



	my @work=[];
	my $iGotHeader = 0;
	my $parasetidColumn=undef;
	my $parasetverColumn=undef;
	my $paranameColumn=undef;
	my $elfColumn=undef;
	my $tdf1Column=undef;

	my $cv1Column=undef;
	my $cv2Column=undef;
	my $cv3Column=undef;
	my $cv4Column=undef;
	my $cv5Column=undef;

	my $dv1Column=undef;
	my $dv2Column=undef;
	my $dv3Column=undef;
	my $dv4Column=undef;
	my $dv5Column=undef;

	my $lowlimitColumn=undef;
	my $highlimitColumn=undef;

	my $seqnumColumn=undef;
	my $unitidColumn=undef;
	my $numofvsColumn=undef;
	my $formatflagColumn=undef;
	my $datetimeColumn=undef;
	my $typeidColumn=undef;
	my $facilityColumn=undef;
	my $line=undef;

	my $csv=Text::CSV->new({sep_char => ','});

	foreach $line(@lines){
		$_=$line;
		chomp;
		s/\r//;
		s/[[:cntrl:]]//g;

		if($_ =~ /^\s*$/){
			next;
		}
=head
		if($line =~ /WB-CSPL-L/){
			INFO("issued line in phist:".$line);
		}
=cut
		#@work = split(',');
		if($csv->parse($_)){
			@work=$csv->fields();
		}else{
			WARN("error: line could not be parsed--".$line);
			next;
		}
		if (not $iGotHeader)
		{
			#get column header info
			for (my $i = 0;$i <= $#work;$i++)
			{
				if ($work[$i] eq "parameter_set_id")
				{
					$parasetidColumn = $i;


				}
				elsif($work[$i] eq "parameter_set_version")
				{
					$parasetverColumn = $i;


				}
				elsif($work[$i] eq "parameter_name")
				{
					$paranameColumn = $i;


				}
				elsif($work[$i] eq "c_value_1")
				{
					$cv1Column = $i;


				}
				elsif($work[$i] eq "c_value_2")
				{
					$cv2Column = $i;


				}
				elsif($work[$i] eq "c_value_3")
				{
					$cv3Column = $i;


				}
				elsif($work[$i] eq "c_value_4")
				{
					$cv4Column = $i;


				}
				elsif($work[$i] eq "c_value_5")
				{
					$cv5Column = $i;

				}
				elsif($work[$i] eq "d_value_1")
				{
					$dv1Column = $i;


				}
				elsif($work[$i] eq "d_value_2")
				{
					$dv2Column = $i;


				}
				elsif($work[$i] eq "d_value_3")
				{
					$dv3Column = $i;


				}
				elsif($work[$i] eq "d_value_4")
				{
					$dv4Column = $i;


				}
				elsif($work[$i] eq "d_value_5")
				{
					$dv5Column = $i;

				}
				elsif($work[$i] eq "high_shutdown_limit")
				{
					$highlimitColumn = $i;


				}
				elsif($work[$i] eq "low_shutdown_limit")
				{
					$lowlimitColumn = $i;

				}
				elsif($work[$i] eq "sequence_number")
				{
					$seqnumColumn = $i;

				}
				elsif($work[$i] eq "unit_id")
				{
					$unitidColumn = $i;


				}
				elsif($work[$i] eq "number_of_values")
				{
					$numofvsColumn = $i;

				}
				elsif($work[$i] eq "format_flag")
				{
					$formatflagColumn = $i;

				}
				elsif($work[$i] eq "date_time")
				{
					$datetimeColumn = $i;

				}
				elsif($work[$i] eq "facility")
				{
					$facilityColumn = $i;

				}
				elsif($work[$i] eq "type_id")
				{
					$typeidColumn = $i;

				}elsif($work[$i] eq "exceed_limit_flag")
				{
					$elfColumn = $i;

				}elsif($work[$i] eq "test_data_flag_1")
				{
					$tdf1Column = $i;

				}
			}
			$iGotHeader = 1;
			if(defined($parasetidColumn) && defined($parasetverColumn) && defined($paranameColumn) && defined($cv1Column)
				&& defined($cv2Column) && defined($cv3Column) && defined($cv4Column) && defined($cv5Column)
				&& defined($dv1Column) && defined($dv2Column) && defined($dv3Column) && defined($dv4Column)
				&& defined($dv5Column) && defined($highlimitColumn) && defined($lowlimitColumn) && defined($seqnumColumn)
				&& defined($unitidColumn) && defined($numofvsColumn) && defined($formatflagColumn) && defined($elfColumn) && defined($tdf1Column)){

			}else{
				ERROR("phist columns undefined: ".$filepath);
				dpExit(1,"error phist necessary columns undefined: ".$filepath);
			}

		}else{

			my $parasetid=$work[$parasetidColumn];

			if($parasetid =~ /^\s*$/){
				WARN("parasetid undefined line--".$line);
				next;
			}

			my $parasetver=$work[$parasetverColumn];

			if($parasetver =~ /^\s*$/){
				WARN("parasetver undefined line--".$line);
				next;
			}

			my $paraname=$work[$paranameColumn];
			if($paraname =~ /^\s*$/){
				WARN("paraname undefined line--".$line);
				next;
			}

			my $seqnum=$work[$seqnumColumn];

			if($seqnum =~ /^\s*$/){
				WARN("seqnum undefined line--".$line);
				next;
			}

			my $unitid=$work[$unitidColumn];
			$unitid =~ s/'//g;
			if($unitid =~ /^\s*$/){
				DEBUG("optional unitid undefined line in phist file--".$line);

			}

			my $facility=$work[$facilityColumn];
			#my $facility=$equip6_id;

			if($facility =~ /^\s*$/){
				WARN("facility undefined line--".$line);
				next;
			}

			my $typeid=$work[$typeidColumn];
			if($typeid =~ /^\s*$/){
				WARN("typeid undefined line--".$line);
				next;
			}

			my $datetime=$work[$datetimeColumn];
			if($datetime =~ /^\s*$/){
				WARN("datetime undefined line--".$line);
				next;
			}


			if($datetime =~ /^(\w+) (\d{2}) (\d{4}) (\d{2})\:(\d{2}):(\d{2})\:\d{3}(\w{2})$/){
				$datetime = FormatDate($datetime);

			}else{
				ERROR("invalid datetime line--".$line);
				next;
			}


			my $key=$parasetid."|".$parasetver."|".$paraname."|".$datetime."|".$facility."|".$typeid."|".$seqnum."|".$unitid;

			if(defined($phistinfo{$key})){
				WARN("duplicate phist line--".$line);
				next;
			}

			my $lowlimit=$work[$lowlimitColumn];
			if($lowlimit =~ /^\s*$/){
				DEBUG("optional lowlimit undefined line in phist file--".$line);

			}
			my $highlimit=$work[$highlimitColumn];
			if($highlimit =~ /^\s*$/){
				DEBUG("optional highlimit undefined line in phist file--".$line);

			}



			my $elf=$work[$elfColumn];
			if($elf =~ /^\s*$/){
				DEBUG("optional exceed_limit_flag undefined line in phist file--".$line);

			}

			my $tdf1=$work[$tdf1Column];
			if($tdf1 =~ /^\s*$/){
				DEBUG("optional test_data_flag_1 undefined line in phist file--".$line);

			}


			my $numofvs=$work[$numofvsColumn];

			if($numofvs =~ /^\s*$/){
				WARN("numofvs undefined line--".$line);
				next;
			}

			my $formatflag=$work[$formatflagColumn];
#			if($formatflag =~ /^\s*$/){
#				WARN("formatflag undefined line--".$line);
#				next;
#			}
			my $values=undef;
			my $i=undef;
#			if($formatflag =~ /^[a-zA-Z]$/){
			if($formatflag =~ /^[atAT]$/){
				my $cv1=$work[$cv1Column];
				my $cv2=$work[$cv2Column];
				my $cv3=$work[$cv3Column];
				my $cv4=$work[$cv4Column];
				my $cv5=$work[$cv5Column];
				$values=$cv1.",".$cv2.",".$cv3.",".$cv4.",".$cv5;
			}else{
				my $dv1=$work[$dv1Column];
				my $dv2=$work[$dv2Column];
				my $dv3=$work[$dv3Column];
				my $dv4=$work[$dv4Column];
				my $dv5=$work[$dv5Column];
				$values=$dv1.",".$dv2.",".$dv3.",".$dv4.",".$dv5;
			}

			addTestInfo($parasetid
			          , $parasetver
			          , (split / /, $datetime)[0] #Just the date
				  , $paraname
				  , $unitid
				  , $lowlimit
				  , $highlimit);
			$phistinfo{$key}={"type_id"=>$typeid,"facility"=>$facility,"date_time"=>$datetime,"parameter_set_id"=>$parasetid
						,"parameter_set_version"=>$parasetver,"parameter_name"=>$paraname, "sequence_number"=>$seqnum, "unit_id"=>$unitid
						,"exceed_limit_flag"=>$elf,"test_data_flag_1"=>$tdf1, "format_flag"=>$formatflag
						,"low_lim"=>$lowlimit,"high_lim"=>$highlimit,"number_of_values"=>$numofvs,"values"=>$values};
=head
			if($line =~ /WB-CSPL-L/){
				INFO("OK line in phist:".$line);
			}
=cut
		}

	}
}
##############################################################################
# Subroutine: ProcessLhistFile
##############################################################################
sub ProcessLhistFile{
	my $basename=shift();
	my $ext=shift();

	my $filepath=$indir.$basename."\.".$ext;
	INFO("Processing ".$filepath);
	my $fmtpath=$hOptions{fmtdir}."/".$basename."\.bcp_fmt";
	my $line=undef;
	my @lines=`$perlname $readWksm $fmtpath $filepath`;

	my @work=[];
	my $iGotHeader = 0;

	my $lotidColumn=undef;
	my $facilityColumn=undef;
	my $operationColumn=undef;
	my $ownerColumn=undef;
	my $operatoridColumn=undef;
	my $lossQuantityColumn=undef;


	my $productidColumn=undef;
	my $routeColumn=undef;
	my $lotQuantityColumn=undef;
	my $equipIdColumn=undef;
	my $reworkFlagColumn=undef;
	my $reworkCatColumn=undef;
	my $reworkCountColumn=undef;
	my $hotlotflagColumn=undef;
	my $holdFlagColumn=undef;

	my $tracktimeColumn=undef;
	my $datetimeColumn=undef;
	my $transactionColumn=undef;

	my $parasetidColumn=undef;
	my $parasetverColumn=undef;
	my $commentColumn=undef;

	my $lc1Column=undef;
	my $lq1Column=undef;
	my $lc2Column=undef;
	my $lq2Column=undef;
	my $lc3Column=undef;
	my $lq3Column=undef;
	my $lc4Column=undef;
	my $lq4Column=undef;
	my $lc5Column=undef;
	my $lq5Column=undef;
	my $lc6Column=undef;
	my $lq6Column=undef;
	my $lc7Column=undef;
	my $lq7Column=undef;
	my $lc8Column=undef;
	my $lq8Column=undef;
	my $lc9Column=undef;
	my $lq9Column=undef;
	my $lc10Column=undef;
	my $lq10Column=undef;
	my $lc11Column=undef;
	my $lq11Column=undef;
	my $lc12Column=undef;
	my $lq12Column=undef;

	my $eventColumn=undef;
	my $holdCatColumn = undef;
	my $holdNameColumn=undef;
	my $holdNoteColumn=undef;
	my $unitChangeColumn=undef;
	my $lotQuantityNewColumn=undef;

	my $ntcdatetimeColumn=undef;
	my $line=undef;
	my $csv=Text::CSV->new({sep_char => ','});
	foreach $line(@lines){
		$_=$line;
		chomp;
		s/\r//;

		if($_ =~ /^\s*$/){
			next;
		}
=head
		if($line =~ /WB-CSPL-L/){
			INFO("issue line in lhist:".$line);
		}
=cut
		if($csv->parse($_)){
			@work=$csv->fields();
			# 26-Apr-16 EA remove "," to fix lot class issue
			for (@work) {
                                s/\,/\//;
                        }
		}else{
			WARN("warn: line could not be parsed or contained special chars--".$line);
			#next;
			my $nl=ReplaceSpecialChars($_);
			$nl =~ s/"//g;
			$nl = trim($nl);
			#INFO("corrected line: ".$nl);
			if($csv->parse($nl)){
				@work=$csv->fields();
			}else{
				#$nl =~ s/"//g;
				#$nl = trim($nl);
				INFO("corrected line:".$nl);
				@work=split(",",$nl);
				if($#work<=10){
					ERROR("invalid line, please check : ".$nl);
					next;
				}

			}
		}
		if (not $iGotHeader)
		{
			#get column header info
			for (my $i = 0;$i <= $#work;$i++)
			{
				if ($work[$i] eq "lot_id")
				{
					$lotidColumn = $i;
				}
				elsif($work[$i] eq "facility")
				{
					$facilityColumn = $i;
				}
				elsif ($work[$i] eq "transaction")
				{
					$transactionColumn = $i;
				}
				elsif ($work[$i] eq "operation")
				{
					$operationColumn = $i;
				}
				elsif ($work[$i] eq "owner")
				{
					$ownerColumn = $i;
				}
				elsif($work[$i] eq "operator_id")
				{
					$operatoridColumn = $i;
				}
				elsif ($work[$i] eq "loss_quantity")
				{
					$lossQuantityColumn = $i;
				}
				elsif ($work[$i] eq "product_id")
				{
					$productidColumn = $i;
				}
				elsif ($work[$i] eq "route")
				{
					$routeColumn = $i;
				}
				elsif($work[$i] eq "lot_quantity")
				{
					$lotQuantityColumn = $i;
				}
				elsif ($work[$i] eq "equip_id")
				{
					$equipIdColumn = $i;
				}
				elsif ($work[$i] eq "rework_flag")
				{
					$reworkFlagColumn = $i;
				}
				elsif ($work[$i] eq "rework_cat")
				{
					$reworkCatColumn = $i;
				}
				elsif($work[$i] eq "rework_count")
				{
					$reworkCountColumn = $i;
				}
				elsif ($work[$i] eq "hot_lot_flag")
				{
					$hotlotflagColumn = $i;
				}
				elsif ($work[$i] eq "hold_flag")
				{
					$holdFlagColumn = $i;
				}
				elsif ($work[$i] eq "transaction_date_time")
				{
					$tracktimeColumn = $i;
				}
				elsif ($work[$i] eq "date_time")
				{
					$datetimeColumn = $i;
				}elsif ($work[$i] eq "ntc_date_time")
				{
					$ntcdatetimeColumn = $i;
				}
				elsif ($work[$i] eq "parameter_set_id")
				{
					$parasetidColumn = $i;
				}elsif ($work[$i] eq "parameter_set_version")
				{
					$parasetverColumn = $i;
				}elsif ($work[$i] eq "comment")
				{
					$commentColumn = $i;
				}elsif ($work[$i] eq "loss_category_1")
				{
					$lc1Column = $i;
				}elsif ($work[$i] eq "loss_quantity_1")
				{
					$lq1Column = $i;
				}elsif ($work[$i] eq "loss_category_2")
				{
					$lc2Column = $i;
				}elsif ($work[$i] eq "loss_quantity_2")
				{
					$lq2Column = $i;
				}elsif ($work[$i] eq "loss_category_3")
				{
					$lc3Column = $i;
				}elsif ($work[$i] eq "loss_quantity_3")
				{
					$lq3Column = $i;
				}elsif ($work[$i] eq "loss_category_4")
				{
					$lc4Column = $i;
				}elsif ($work[$i] eq "loss_quantity_4")
				{
					$lq4Column = $i;
				}elsif ($work[$i] eq "loss_category_5")
				{
					$lc5Column = $i;
				}elsif ($work[$i] eq "loss_quantity_5")
				{
					$lq5Column = $i;
				}elsif ($work[$i] eq "loss_category_6")
				{
					$lc6Column = $i;
				}elsif ($work[$i] eq "loss_quantity_6")
				{
					$lq6Column = $i;
				}elsif ($work[$i] eq "loss_category_7")
				{
					$lc7Column = $i;
				}elsif ($work[$i] eq "loss_quantity_7")
				{
					$lq7Column = $i;
				}elsif ($work[$i] eq "loss_category_8")
				{
					$lc8Column = $i;
				}elsif ($work[$i] eq "loss_quantity_8")
				{
					$lq8Column = $i;
				}elsif ($work[$i] eq "loss_category_9")
				{
					$lc9Column = $i;
				}elsif ($work[$i] eq "loss_quantity_9")
				{
					$lq9Column = $i;
				}elsif ($work[$i] eq "loss_category_10")
				{
					$lc10Column = $i;
				}elsif ($work[$i] eq "loss_quantity_10")
				{
					$lq10Column = $i;
				}elsif ($work[$i] eq "loss_category_11")
				{
					$lc11Column = $i;
				}elsif ($work[$i] eq "loss_quantity_11")
				{
					$lq11Column = $i;
				}elsif ($work[$i] eq "loss_category_12")
				{
					$lc12Column = $i;
				}elsif ($work[$i] eq "loss_quantity_12")
				{
					$lq12Column = $i;
				}elsif ($work[$i] eq "event")
				{
					$eventColumn = $i;
				}elsif ($work[$i] eq "hold_cat")
				{
					$holdCatColumn = $i;
				}elsif ($work[$i] eq "hold_name")
				{
					$holdNameColumn = $i;
				}
				elsif ($work[$i] eq "hold_note")
				{
					$holdNoteColumn = $i;
				}elsif ($work[$i] eq "unit_change")
				{
					$unitChangeColumn = $i;
				}elsif($work[$i] eq "lot_quantity_new")
				{
					$lotQuantityNewColumn = $i;
				}
			}
			$iGotHeader = 1;
			if(defined($lotidColumn) && defined($operationColumn) && defined($facilityColumn) && defined($transactionColumn)
				&& defined($ownerColumn) && defined($operatoridColumn)&& defined($lossQuantityColumn) && defined($productidColumn)
				&& defined($routeColumn) && defined($lotQuantityColumn)
				&& defined($equipIdColumn) && defined($reworkFlagColumn)
				&& defined($reworkCatColumn) && defined($reworkCountColumn) && defined($holdFlagColumn)
				&& defined($tracktimeColumn) && defined($parasetidColumn)&& defined($commentColumn)
				&& defined($lc1Column) && defined($lq1Column)&& defined($lc2Column) && defined($lq2Column)
				&& defined($lc3Column) && defined($lq3Column)&& defined($lc4Column) && defined($lq4Column)
				&& defined($lc5Column) && defined($lq5Column)&& defined($lc6Column) && defined($lq6Column)
				&& defined($lc7Column) && defined($lq7Column)&& defined($lc8Column) && defined($lq8Column)
				&& defined($lc9Column) && defined($lq9Column)&& defined($lc10Column) && defined($lq10Column)
				&& defined($lc11Column) && defined($lq11Column)&& defined($lc12Column) && defined($lq12Column)
				&& defined($eventColumn) && defined($holdCatColumn) && defined($holdNameColumn)&& defined($holdNoteColumn)
				&& defined($unitChangeColumn) && defined($lotQuantityNewColumn) && defined($ntcdatetimeColumn)
				){
				if(!defined($hotlotflagColumn)){
					WARN("warn lhit optional hot_lot_flag column undefined");
				}
			}else{

				ERROR("error lhit necessary columns undefined: ".$filepath);
				dpExit(1,"error lhit necessary columns undefined: ".$filepath);
			}

		}else{

			my $ifLEH=1;
			my $ifFS=1;
			my $ifLOSS=1;
			my $ifLOTEVENT=1;
			my $ifOff=1;
			#get lotid column for lot event, LEH
			my $lotid=$work[$lotidColumn];
			if($lotid =~ /^\s*$/){
				WARN("lotid undefined line--".$line);
				next;
			}
########################get facility column for lot event, LEH
			my $facility=$work[$facilityColumn];
			#my $facility = $equip6_id;
			if($facility =~ /^\s*$/){
				WARN("facility undefined line--".$line);
				next;
			}
			$lhistoffinfo{$facility} = 1;
			my $dt=$work[$datetimeColumn];
			if($dt =~ /^\s*$/){
				WARN("necessary date_time undefined line--".$line);
				#$ifLEH=0;
				$ifOff=0;
				#next;
			}
			$dt = FormatDate($dt);
			#$lhistlot2facility{$lotid} = $facility;

			#get operation column for lot event, LEH
			my $operation=$work[$operationColumn];
			if($operation =~ /^\s*$/){
				WARN("necessary operation undefined line in lhist file--".$line);
				next;
			}

			#get equipId column for lot event, LEH
			my $equipId=$work[$equipIdColumn];
			if($equipId =~ /^\s*$/){
				DEBUG("optional equipId undefined line in lhist file--".$line);
			}
			my $parasetid=$work[$parasetidColumn];
			my $parasetver=$work[$parasetverColumn];

			if($ifOff){
				my $offkey=$dt."|".$equipId."|".$parasetid."|".$parasetver."|".$facility;
				$lhistoffinfo{$offkey} = 1;
				if ( ! $lotid =~ /^\s*$/ )
				{
					my $offlotkey=$dt."|".$lotid."|".$parasetid."|".$parasetver."|".$facility;
					$lhistoffinfo{$offlotkey} = 1;
				}
			}

			#get productid column for lot event, LEH
			# 02-Jun-2015 SAB do meta lookup and store.
			my $in_productid=$work[$productidColumn];
			if($in_productid =~ /^\s*$/){
				WARN("necessary productid undefined line--".$line);
				next;
			}
			my($sourcelot,$lotowner,$lotclass,$productid,$family,$process,$package) = GetMetaByLot($lotid,$in_productid);
			#replace spaces with _
#			$productid =~ s/\s+/_/;
			if($productid eq "product_id"){
				ERROR($line);
			}
			if(defined($hOptions{WAFERPRODUCT})){
				$productid = $productid."_WAFER";
			}
			if ( $sourcelot eq "N/A" )
			{
				$sourcelot = $lotid."\.S";
			}


			#format transaction time, get transaction_date_time column for lot event, LEH
			my $tracktime=$work[$tracktimeColumn];
			if($tracktime =~ /^\s*$/){
				WARN("necessary tracktime undefined line--".$line);
				$ifLEH=0;
				#next;
			}
			$tracktime = FormatDate($tracktime);


			#get operatorid column for lot event, LEH
			my $operatorid=$work[$operatoridColumn];
			if($operatorid =~ /^\s*$/){
				WARN("operatorid undefined line--".$line);
				#next;
			}
			my $reworkFlag=$work[$reworkFlagColumn];
			if($reworkFlag =~ /^\s*$/){
				WARN("reworkFlag undefined line--".$line);
				#next;
			}
			#format comment for lot event, LEH
			my $comment=$work[$commentColumn];
			my $lecomment=$comment;
			if($comment =~ /^\s*$/){
				DEBUG("warn optional comment undefined line--".$line);
				#next;
			}else{
				if($comment =~ /Recipe:\s?(\S+)\s+/i || $comment =~ /Recipe:\s?(\S+)$/i){
					$comment=$1;
				}elsif($comment =~ /Recipe run:\s?(\S+)\s+/i || $comment =~ /Recipe run:\s?(\S+)$/i){
					$comment=$1;
				}elsif($comment =~ /Recipe (\S+)\s+/i || $comment =~ /Recipe (\S+)$/i){
					$comment=$1;
				}elsif($comment =~ /Recipe_ID : (\S+)\s+/i || $comment =~ /Recipe_ID : (\S+)$/i){
					$comment=$1;
				}elsif($comment =~ /RECIPE DOWNLOADED:\s*(\S+)\s+/i || $comment =~ /RECIPE DOWNLOADED:\s*(\S+)$/i){
					$comment=$1;
				}else{

					DEBUG("cannot get recipe info in the comment--".$comment);
					$comment="";
				}
				$comment =~ s/,//g;
			}

			#get reworkCat column for lot event, LEH
			my $reworkCat=$work[$reworkCatColumn];
			if($reworkCat =~ /^\s*$/){
				DEBUG("optional reworkCat undefined line--".$line);
			}

			#get holdFlag column for lot event, LEH
			my $holdFlag=$work[$holdFlagColumn];
			if($holdFlag =~ /^\s*$/){
				DEBUG("optional holdFlag undefined line--".$line);
			}





			#get transaction column for lot event, LEH
			my $transaction=$work[$transactionColumn];
			if($transaction =~ /^\s*$/){
				WARN("transaction undefined line--".$line);
				#next;
				#$ifLOTEVENT = 0;
			}
			#get unitChange column for lot event
			my $lotQuantityNew=$work[$lotQuantityNewColumn];
			if($lotQuantityNew =~ /^\s*$/){
				DEBUG("optional lotQuantityNew undefined line--".$line);
			}

			my $lossQuantity=$work[$lossQuantityColumn];
			my $eventtype = undef;
			if($transaction eq "HLLT"){
			#if($transaction eq "HLLT"){
				$eventtype = "Hold Lot";
			}elsif($transaction eq "RLLT"){
			#}elsif($transaction eq "RLLT"){
				$eventtype = "Release Lot";
			}elsif(!($lossQuantity =~ /^\s*$/) && ($lossQuantity > 0) && $lotQuantityNew == 0){ # Whole-lot scraps only
				$eventtype = "Scrap";
			}elsif($reworkFlag eq "Y"){
				$eventtype = "Rework";
			}else{
				$ifLOTEVENT=0;
			}
			#if(($reworkFlag eq "Y") || ($ifLOTEVENT && (($transaction eq "HLLT") || ($transaction eq "RLLT") || (($transaction eq "MVOU") && !($lossQuantity =~ /^\s*$/))))){
			if($ifLOTEVENT){
				#get event column for lot event
				my $event=$work[$eventColumn];
				if($event =~ /^\s*$/){
					DEBUG("event undefined line--".$line);
				}

				#get holdCat column for lot event
				my $holdCat=$work[$holdCatColumn];
				if($holdCat =~ /^\s*$/){
					DEBUG("optional holdFlag undefined line--".$line);
				}

				#get holdName column for lot event
				my $holdName=$work[$holdNameColumn];
				if($holdName =~ /^\s*$/){
					DEBUG("optional holdName undefined line--".$line);
				}

				#get holdNote column for lot event
				my $holdNote=$work[$holdNoteColumn];
				if($holdNote =~ /^\s*$/){
					DEBUG("optional holdNote undefined line--".$line);
				}
				#get unitChange column for lot event
				my $unitChange=$work[$unitChangeColumn];
				if($unitChange =~ /^\s*$/){
					DEBUG("optional unitChange undefined line--".$line);
				}


				my $lekey = $productid;
				$lhistloteventinfo{$lekey}=[] unless exists $lhistloteventinfo{$lekey};
				$lecomment =~ s/,/ /g;
				push @{$lhistloteventinfo{$lekey}},{"lot_id"=>$lotid,"facility"=>$facility,"transaction_date_time"=>$tracktime,"operation"=>$operation
						,"operator_id"=>$operatorid,"equip_id"=>$equipId, "product_id"=>$productid,"comment"=>$lecomment
						,"event"=>$transaction,"rework_cat"=>$reworkCat,"hold_flag"=>$holdFlag,"hold_cat"=>$holdCat
						,"hold_name"=>$holdName,"hold_note"=>$holdNote,"unit_change"=>$unitChange
						,"lot_quantity_new"=>$lotQuantityNew,"transaction"=>$transaction,"loss_quantity"=>$lossQuantity
						,"eventtype"=>$eventtype,"sourcelot"=>$sourcelot,"lotclass"=>$lotclass};

			}

			my $owner=$work[$ownerColumn];
			if($owner =~ /^\s*$/){
				WARN("owner undefined line--".$line);
				next;
			}
			if($owner eq "CPREA"){
				next;
			}else{

			}


			if($lossQuantity =~ /^\s*$/){
				WARN("necessary lossQuantity undefined line--".$line);
				$ifLOSS=0;
				#next;
			}

			my $lotQuantity=$work[$lotQuantityColumn];
			if($lotQuantity =~ /^\s*$/){
				WARN("necessary lotQuantity undefined line--".$line);
				#next;
			}
			my $lotQuantityNew=$work[$lotQuantityNewColumn];
			if($lotQuantityNew =~ /^\s*$/){
				WARN("necessary lotQuantityNew undefined line--".$line);
				#next;
			}

			my $route=$work[$routeColumn];
			if($route =~ /^\s*$/){
#				WARN("necessary route undefined line--".$line);
	                        $route="--UNDEFINED--";
				#next;
			}








			#if($ifLOSS && $lossQuantity>0){
				my $lc1=$work[$lc1Column];
				if($lc1 =~ /^\s*$/){
					DEBUG("optional loss_category_1 undefined line--".$line);
				}
				my $lq1=$work[$lq1Column];
				if($lq1 =~ /^\s*$/){
					DEBUG("optional loss_quantity_1 undefined line--".$line);
				}

				my $lc2=$work[$lc2Column];
				if($lc2 =~ /^\s*$/){
					DEBUG("optional loss_category_2 undefined line--".$line);
				}
				my $lq2=$work[$lq2Column];
				if($lq2 =~ /^\s*$/){
					DEBUG("optional loss_quantity_2 undefined line--".$line);
				}

				my $lc3=$work[$lc3Column];
				if($lc3 =~ /^\s*$/){
					DEBUG("optional loss_category_3 undefined line--".$line);
				}
				my $lq3=$work[$lq3Column];
				if($lq3 =~ /^\s*$/){
					DEBUG("optional loss_quantity_3 undefined line--".$line);
				}

				my $lc4=$work[$lc4Column];
				if($lc4 =~ /^\s*$/){
					DEBUG("optional loss_category_4 undefined line--".$line);
				}
				my $lq4=$work[$lq4Column];
				if($lq4 =~ /^\s*$/){
					DEBUG("optional loss_quantity_4 undefined line--".$line);
				}

				my $lc5=$work[$lc5Column];
				if($lc5 =~ /^\s*$/){
					DEBUG("optional loss_category_5 undefined line--".$line);
				}
				my $lq5=$work[$lq5Column];
				if($lq5 =~ /^\s*$/){
					DEBUG("optional loss_quantity_5 undefined line--".$line);
				}
				my $lc6=$work[$lc6Column];
				if($lc6 =~ /^\s*$/){
					DEBUG("optional loss_category_6 undefined line--".$line);
				}
				my $lq6=$work[$lq6Column];
				if($lq6 =~ /^\s*$/){
					DEBUG("optional loss_quantity_6 undefined line--".$line);
				}
				my $lc7=$work[$lc7Column];
				if($lc7 =~ /^\s*$/){
					DEBUG("optional loss_category_7 undefined line--".$line);
				}
				my $lq7=$work[$lq7Column];
				if($lq7 =~ /^\s*$/){
					DEBUG("optional loss_quantity_7 undefined line--".$line);
				}
				my $lc8=$work[$lc8Column];
				if($lc8 =~ /^\s*$/){
					DEBUG("optional loss_category_8 undefined line--".$line);
				}
				my $lq8=$work[$lq8Column];
				if($lq8 =~ /^\s*$/){
					DEBUG("optional loss_quantity_8 undefined line--".$line);
				}
				my $lc9=$work[$lc9Column];
				if($lc9 =~ /^\s*$/){
					DEBUG("optional loss_category_9 undefined line--".$line);
				}
				my $lq9=$work[$lq9Column];
				if($lq9 =~ /^\s*$/){
					DEBUG("optional loss_quantity_1 undefined line--".$line);
				}
				my $lc10=$work[$lc10Column];
				if($lc10 =~ /^\s*$/){
					DEBUG("optional loss_category_10 undefined line--".$line);
				}
				my $lq10=$work[$lq10Column];
				if($lq10 =~ /^\s*$/){
					DEBUG("optional loss_quantity_10 undefined line--".$line);
				}
				my $lc11=$work[$lc11Column];
				if($lc11 =~ /^\s*$/){
					DEBUG("optional loss_category_11 undefined line--".$line);
				}
				my $lq11=$work[$lq11Column];
				if($lq11 =~ /^\s*$/){
					DEBUG("optional loss_quantity_11 undefined line--".$line);
				}
				my $lc12=$work[$lc12Column];
				if($lc12 =~ /^\s*$/){
					DEBUG("optional loss_category_12 undefined line--".$line);
				}
				my $lq12=$work[$lq12Column];
				if($lq12 =~ /^\s*$/){
					DEBUG("optional loss_quantity_12 undefined line--".$line);
				}
				my $trt=$tracktime;
				$trt =~ s/ /_/g;
				$trt =~ s/[:-]//g;

				my $lqkey=$lotid."_".$trt;
				$lhistlossinfo{$lqkey}=[] unless exists $lhistlossinfo{$lqkey};
				push @{$lhistlossinfo{$lqkey}},{"lot_id"=>$lotid,"sourcelot"=>$sourcelot,"lotclass"=>$lotclass
				        ,"facility"=>$facility,"route"=>$route,"operation"=>$operation, "product_id"=>$productid
					,"transaction_date_time"=>$tracktime,"loss_quantity"=>$lossQuantity,"owner"=>$owner
					,"lot_quantity"=>$lotQuantity,"lot_quantity_new"=>$lotQuantityNew,"operator_id"=>$operatorid
					,"loss_category_1"=>$lc1,"loss_quantity_1"=>$lq1,"loss_category_2"=>$lc2,"loss_quantity_2"=>$lq2
					,"loss_category_3"=>$lc3,"loss_quantity_3"=>$lq3,"loss_category_4"=>$lc4,"loss_quantity_4"=>$lq4
					,"loss_category_5"=>$lc5,"loss_quantity_5"=>$lq5,"loss_category_6"=>$lc6,"loss_quantity_6"=>$lq6
					,"loss_category_7"=>$lc7,"loss_quantity_7"=>$lq7,"loss_category_8"=>$lc8,"loss_quantity_8"=>$lq8
					,"loss_category_9"=>$lc9,"loss_quantity_9"=>$lq9,"loss_category_10"=>$lc10,"loss_quantity_10"=>$lq10
					,"loss_category_11"=>$lc11,"loss_quantity_11"=>$lq11,"loss_category_12"=>$lc12,"loss_quantity_12"=>$lq12,"transaction"=>$transaction,"equip_id"=>$equipId};

			#}

			if($equipId =~ /^\s*$/){

			}else{
			#if($transaction eq "LVNE"){

				#my $key=$lotid."|".$operation."|".$equipId."|".$facility;
				my $entkey=$equipId."|".$facility;
				my $operkey=$operation."|".$facility;
				my $entType=$entinfo{$entkey};
				my $operdesc=$operinfo{$operkey}{"short_description"};
				my $key=$lotid."|".$operation."|".$operdesc."|".$entType."|".$facility;

				if(defined($lhistinfo{$key})){

					#compute trackin and trackout time
					my $trackIn=$lhistinfo{$key}{"TrackIN_time"};
					if($tracktime lt  $trackIn){
						$lhistinfo{$key}{"TrackIN_time"}=$tracktime;
						$lhistinfo{$key}{"TI_operator_id"}=$operatorid;
					}

					my $trackOut=$lhistinfo{$key}{"TrackOUT_time"};
					if($tracktime gt  $trackOut){
						$lhistinfo{$key}{"TrackOUT_time"}=$tracktime;
						$lhistinfo{$key}{"TO_operator_id"}=$operatorid;
					}


				}else{







					my $reworkCount=$work[$reworkCountColumn];
					if($reworkCount =~ /^\s*$/){
						DEBUG("optional reworkCount undefined line--".$line);

					}

					my $hotlotflag=undef;
					if(defined($hotlotflagColumn)){
						$hotlotflag=$work[$hotlotflagColumn];
						if($hotlotflag =~ /^\s*$/){
							WARN("hotlotflag undefined line--".$line);
							#next;
						}
					}else{
						$hotlotflag="N/A";
					}


					if($ifLEH){

						$lhistinfo{$key}={"lot_id"=>$lotid,"sourcelot"=>$sourcelot,"lotclass"=>$lotclass
						        ,"facility"=>$facility,"operation"=>$operation,"owner"=>$owner
							,"TI_operator_id"=>$operatorid,"TO_operator_id"=>$operatorid, "loss_quantity"=>$lossQuantity
							 , "product_id"=>$productid
							,"route"=>$route,"lot_quantity"=>$lotQuantity,"equip_id"=>$equipId,"rework_flag"=>$reworkFlag
							,"rework_cat"=>$reworkCat,"rework_count"=>$reworkCount,"hot_lot_flag"=>$hotlotflag,"hold_flag"=>$holdFlag
							,"TrackIN_time"=>$tracktime,"TrackOUT_time"=>$tracktime,"comment"=>$comment};
					}
				}
			}

			my $parasetid=$work[$parasetidColumn];
			my $parasetver=$work[$parasetverColumn];

			if($parasetid){

				my $ntcdatetime=$work[$ntcdatetimeColumn];
				if($ntcdatetime =~ /^\s*$/){
					WARN("ntcdatetime undefined line--".$line);
					$ifFS=0;
					next;
				}
				$ntcdatetime = FormatDate($ntcdatetime);
=head
				if($ntcdatetime =~ /^(\w+) (\d{2}) (\d{4}) (\d{2})\:(\d{2}):(\d{2})\:\d{3}(\w{2})$/){
					my $month=$m2d{$1};
					my $day=$2;
					my $year=$3;
					my $apm=$7;
					my $hour=undef;
					if($apm eq "PM" &&  $4<12){
						$hour=$4+12;
					}else{
						$hour=$4;
					}
					my $minute=$5;
					my $second=$6;
					$ntcdatetime=$year."-".$month."-".$day." ".$hour.":".$minute.":".$second;
				}
=cut
				my $key=undef;


				$key = $lotid."|".$facility."|".$parasetid."|".$parasetver."|".$ntcdatetime;
#				INFO( "Adding   LOT::".$key);
				if(defined($lhistfsinfo{$key})){
#					03-Jun-15 SAB Don't warn on this -- this is normal when there are more than 5 data values collected.
#					WARN("duplicate lotid and facility line in fabsite lhist file--key=".$key." line=".$line);
					#next;
				}else{
					$lhistfsinfo{$key}={"lot_id"=>$lotid,"sourcelot"=>$sourcelot,"lotclass"=>$lotclass,"facility"=>$facility,"operation"=>$operation
					, "product_id"=>$productid, "family"=>$family, "process"=>$process, "package"=>$package
					,"equip_id"=>$equipId,"ntc_date_time"=>$ntcdatetime,"owner"=>$owner,"route"=>$route,"operator_id"=>$operatorid,"comment"=>$comment};
				}

				$key = $equipId."|".$facility."|".$parasetid."|".$parasetver."|".$ntcdatetime;
#				INFO( "Adding EQUIP::".$key);
				if(defined($lhistfsinfo{$key})){
#					03-Jun-15 SAB Don't warn on this -- this is normal when there are more than 5 data values collected.
#					WARN("duplicate equipId and facility line in fabsite lhist file--key=".$key." line=".$line);
#					26-Jun-15 SAB Adding an array of lot(s) to indicate every lot processed through this tool at this time
					push @{$lhistfsinfo{$key}{"multi_lot"}}, $lotid;
					next;
				}else{

					$lhistfsinfo{$key}={"lot_id"=>"##MULTI##","facility"=>$facility,"operation"=>$operation
					        , "product_id"=>$productid, "family"=>$family, "process"=>$process, "package"=>$package
						,"equip_id"=>$equipId,"ntc_date_time"=>$ntcdatetime,"owner"=>$owner,"route"=>$route,"operator_id"=>$operatorid,"comment"=>$comment,"multi_lot"=>[$lotid]};
				}

=head
				if($line =~ /WB-CSPL-L/){
					INFO("OK line in lhist:".$line);
				}
=cut
			}




		}

	}
}
##############################################################################
# Subroutine: ProcessAndOutputEntFile
##############################################################################
sub ProcessAndOutputEntFile{
	my $basename=shift();
	my $ext=shift();

	my $filepath=$indir.$basename."\.".$ext;
	INFO("Processing ".$filepath);
	my $fmtpath=$hOptions{fmtdir}."/".$basename."\.bcp_fmt";
	my $line=undef;
	my @lines=`$perlname $readWksm $fmtpath $filepath`;

	my @work=[];
	my %entdetailinfo=();
	my $iGotHeader = 0;
	my $facilityColumn=undef;
	my $entityidColumn=undef;
	my $entitytypeColumn=undef;
	my $entitydesColumn=undef;
	my $entitylocColumn=undef;

	my $csv=Text::CSV->new();

	foreach $line(@lines){
		$_=$line;
		chomp;
		s/\r//;
		s/\"//g;

		if($_ =~ /^\s*$/){
			next;
		}
		#@work = split(',');
		my $status = $csv->parse($line);
		@work = $csv->fields();

		if (not $iGotHeader)
		{
			#get column header info

			for (my $i = 0;$i <= $#work;$i++)
			{
				if ($work[$i] eq "entity_id")
				{
					$entityidColumn = $i;


				}
				elsif($work[$i] eq "facility")
				{
					$facilityColumn = $i;


				}
				elsif($work[$i] eq "entity_type")
				{
					$entitytypeColumn = $i;


				}elsif($work[$i] eq "entity_description")
				{
					$entitydesColumn = $i;


				}elsif($work[$i] eq "entity_location")
				{
					$entitylocColumn = $i;


				}


			}
			$iGotHeader = 1;
			if(defined($entityidColumn) && defined($facilityColumn) && defined($entitytypeColumn)&& defined($entitydesColumn) && defined($entitylocColumn)){

			}else{
				ERROR("ent columns undefined: ".$filepath);
				dpExit(1,"necessary ent columns undefined: ".$filepath);
			}

		}else{

			my $facility=$work[$facilityColumn];
			#my $facility=$equip6_id;

			if(!$facility){
				WARN("necessary facility undefined line--".$line);
				next;
			}

			my $entityid=$work[$entityidColumn];

			if(!$entityid){
				WARN("necessary entityid undefined line--".$line);
				next;
			}

			my $entitytype=$work[$entitytypeColumn];
			if(!$entitytype){
				WARN("necessary entitytype undefined line--".$line);
				next;
			}

			my $key=$entityid."|".$facility;

			if(defined($entinfo{$key})){
				WARN("duplicate entityid and facility line--".$line);
				next;
			}

			$entinfo{$key}=$entitytype;

			my $entitydes=$work[$entitydesColumn];

			if(!$entitydes){
				DEBUG("optional entitydes undefined line--".$line);

			}

			my $entityloc=$work[$entitylocColumn];
			if(!$entityloc){
				DEBUG("optional entityloc undefined line--".$line);

			}

			my $entdetailkey=$entityid."|".$facility."|".$entitydes."|".$entitytype."|".$entityloc;
			if(!defined($entdetailinfo{$entdetailkey})){
				$entdetailinfo{$entdetailkey}={"entity_id"=>$entityid,"facility"=>$facility,"entity_description"=>$entitydes,"entity_type"=>$entitytype
				,"entity_location"=>$entityloc};
			}
		}

	}

	MakeSubDir("PRODUCTION");
	my $outputfile=$hOptions{out}."/PRODUCTION/".$basename."\.".$ext."\.ent";

	my $fh=undef;

	#print $outputfile."\n";
	open($fh,'>',$outputfile);
	my $outputdata= "entity_id,facility,entity_description,entity_type,entity_location\n";


	my $entkey=undef;
	foreach $entkey (sort keys %entdetailinfo){

		$outputdata.=FormatField($entdetailinfo{$entkey}{"entity_id"}).",".FormatField($entdetailinfo{$entkey}{"facility"}).",".FormatField($entdetailinfo{$entkey}{"entity_description"}).",".FormatField($entdetailinfo{$entkey}{"entity_type"}).",".FormatField($entdetailinfo{$entkey}{"entity_location"})."\n";
	}
	print $fh $outputdata;
	close($fh);
	my $ext2 = "${ext}.ent";

	if($hOptions{FORK} ne "") {
		forkFile($outputfile, $hOptions{FORK}, $basename, $ext2, "PRODUCTION");
	}else {
		INFO("Compress $outputfile with gzip");
		my $gzOutfile = $outputfile.".gz";
		if(-e $gzOutfile) {
			INFO("$gzOutfile already exist");
			INFO("Delete $gzOutfile");
			unlink $gzOutfile;
		}
		qx(gzip "$outputfile");
	}


}

##############################################################################
# Subroutine: ProcessLotV21File
##############################################################################
sub ProcessLotV21File{
	my $basename=shift();
	my $ext=shift();

	my $filepath=$indir.$basename."\.".$ext;
	INFO("Processing ".$filepath);
	my $fmtpath=$hOptions{fmtdir}."/".$basename."\.bcp_fmt";
	my $line=undef;
	my @lines=`$perlname $readWksm $fmtpath $filepath`;

	my @work=[];
	my $iGotHeader = 0;
	my $lotidColumn=undef;
	my $lottypeColumn=undef;


	foreach $line(@lines){
		$_=$line;
		chomp;
		s/\r//;
		s/\"//g;

		if($_ =~ /^\s*$/){
			next;
		}
		@work = split(',');
		if (not $iGotHeader)
		{
			#get column header info
			for (my $i = 0;$i <= $#work;$i++)
			{
				if ($work[$i] eq "lot_id")
				{
					$lotidColumn = $i;


				}
				elsif($work[$i] eq "lot_type")
				{
					$lottypeColumn = $i;


				}


			}
			$iGotHeader = 1;
			if(defined($lotidColumn) && defined($lottypeColumn)){

			}else{
				ERROR("lotinfo columns undefined:".$filepath);
				dpExit(1,"necessary lotinfo columns undefined: ".$filepath);
			}

		}else{
			my $lotid=$work[$lotidColumn];

			if($lotid =~ /^\s*$/){
				WARN("lotid undefined line--".$line);
				next;
			}

			my $lottype=$work[$lottypeColumn];
			if($lottype =~ /^\s*$/){
				WARN("lottype undefined line--".$line);
				next;
			}


			if(defined($lotinfo{$lotid})){
				WARN("duplicate lotid line--".$line);
				next;
			}

			$lotinfo{$lotid}=$lottype;
		}

	}
}
# Don't use package from product file -- use lookup from PP_PROD.
# Do use package, device, etc. from product file when Meta lookup fails.
##############################################################################
# Subroutine: ProcessProductFile
##############################################################################
sub ProcessProductFile{
	my $basename=shift();
	my $ext=shift();

	my $filepath=$indir.$basename."\.".$ext;
	INFO("Processing ".$filepath."\n");
	my $fmtpath=$hOptions{fmtdir}."/".$basename."\.bcp_fmt";
	my $line=undef;
	my @lines=`$perlname $readWksm $fmtpath $filepath`;

	my @work=[];
	my $iGotHeader = 0;
	my $productidColumn=undef;
	my $pkgidColumn=undef;
	my $deviceColumn=undef;
	my $familyColumn=undef;

	foreach $line(@lines){
		$_=$line;
		chomp;
		s/\r//;
		s/\"//g;

		if($_ =~ /^\s*$/){
			next;
		}
		@work = split(',');
		if (not $iGotHeader)
		{
			#get column header info
			for (my $i = 0;$i <= $#work;$i++)
			{
				if ($work[$i] eq "product_id")
				{
					$productidColumn = $i;
				}
				elsif($work[$i] eq "product_group")
				{
					$familyColumn = $i;
				}
				elsif($work[$i] eq "device_id")
				{
					$deviceColumn = $i;
				}
				elsif($work[$i] eq "pkg_id")
				{
					$pkgidColumn = $i;
				}
			}
			$iGotHeader = 1;
			if(defined($productidColumn) && defined($pkgidColumn)){

			}else{
				ERROR("product info columns undefined: ".$filepath);
				dpExit(1,"necessary product columns undefined: ".$filepath);
			}

		}else{
			my $productid=$work[$productidColumn];

			if($productid =~ /^\s*$/){
				WARN("necessary productid undefined line--".$line);
				next;
			}
#			$productid =~ s/\s+/_/;
			if(defined($hOptions{WAFERPRODUCT})){
				$productid = $productid."_WAFER";
			}
			my $familyid=$work[$familyColumn];
			if($familyid =~ /^\s*$/){
				DEBUG("optional product_group(family) undefined line--".$line);
			}
			my $deviceid=$work[$deviceColumn];
			if($deviceid =~ /^\s*$/){
				DEBUG("optional device_id undefined line--".$line);
			}
			my $pkgid=$work[$pkgidColumn];
			if($pkgid =~ /^\s*$/){
				DEBUG("optional pkgid undefined line--".$line);
				#next;
			}

			if(defined($prodfile{$productid})){
				WARN("duplicate productid line--".$line);
				next;
			}

			$prodfile{$productid}={"package"=>$pkgid, "family"=>$deviceid, "process"=>$familyid};
		}

	}
}
##############################################################################
# Subroutine: ProcessOperFile
##############################################################################
sub ProcessOperFile{
	my $basename=shift();
	my $ext=shift();

	my $filepath=$indir.$basename."\.".$ext;
	INFO("Processing ".$filepath);
	my $fmtpath=$hOptions{fmtdir}."/".$basename."\.bcp_fmt";
	my $line=undef;
	my @lines=`$perlname $readWksm $fmtpath $filepath`;

	my @work=[];
	my $iGotHeader = 0;
	my $operationColumn=undef;
	my $facilityColumn=undef;
	my $sdColumn=undef;
	my $operg1Column=undef;
	my $operg2Column=undef;
	my $operg3Column=undef;
	my $unitsColumn=undef;

	foreach $line(@lines){
		$_=$line;
		chomp;
		s/\r//;
		s/\"//g;

		if($_ =~ /^\s*$/){
			next;
		}
		@work = split(',');
		if (not $iGotHeader)
		{
			#get column header info
			for (my $i = 0;$i <= $#work;$i++)
			{
				if ($work[$i] eq "operation")
				{
					$operationColumn = $i;


				}
				elsif($work[$i] eq "facility")
				{
					$facilityColumn = $i;


				}
				elsif ($work[$i] eq "short_description")
				{
					$sdColumn = $i;


				}
				elsif ($work[$i] eq "oper_group_1")
				{
					$operg1Column = $i;


				}
				elsif ($work[$i] eq "oper_group_2")
				{
					$operg2Column = $i;


				}
				elsif ($work[$i] eq "oper_group_3")
				{
					$operg3Column = $i;


				}
				elsif ($work[$i] eq "units")
				{
					$unitsColumn = $i;


				}
			}
			$iGotHeader = 1;
			if(defined($operationColumn) && defined($facilityColumn) && defined($sdColumn) && defined($operg1Column) && defined($operg2Column)
					&& defined($operg3Column) && defined($unitsColumn)){

			}else{
				ERROR("necessary operinfo columns undefined: ".$filepath);
				dpExit(1,"necessary operinfo columns undefined: ".$filepath);

			}

		}else{
			my $operation=$work[$operationColumn];
			if($operation =~ /^\s*$/){
				WARN("necessary operation undefined line in oper file--".$line);
				next;
			}

			my $facility=$work[$facilityColumn];
			#my $facility=$equip6_id;
			if($facility =~ /^\s*$/){
				WARN("necessary facility undefined line--".$line);
				next;
			}

			my $sd=$work[$sdColumn];
			$sd =~ s/''/"/;
			if($sd =~ /^\s*$/){
				DEBUG("optional short_description undefined line--".$line);
			}

			my $operg1=$work[$operg1Column];
			if($operg1 =~ /^\s*$/){
				DEBUG("optional oper_group_1 undefined line--".$line);
			}

			my $operg2=$work[$operg2Column];
			if($operg2 =~ /^\s*$/){
				DEBUG("optional oper_group_2 undefined line--".$line);
			}

			my $operg3=$work[$operg3Column];
			if($operg3 =~ /^\s*$/){
				DEBUG("optional oper_group_3 undefined line--".$line);
			}

			my $units=$work[$unitsColumn];
			if($units =~ /^\s*$/){
				DEBUG("optional units undefined line--".$line);
			}

			my $key=$operation."|".$facility;

			if(defined($operinfo{$key})){
				WARN("duplicate operation and facility line--".$line);
				next;
			}

			$operinfo{$key}={"short_description"=>$sd,"oper_group_1"=>$operg1,"oper_group_2"=>$operg2,"oper_group_3"=>$operg3,"units"=>$units};



		}

	}

}

##############################################################################
# Subroutine: FormatField
##############################################################################
sub FormatField{
	my $va=shift();
	if($va =~ /^\s*$/){
		return($NA);
	}else{
		return($va);
	}

}



##############################################################################
# Subroutine: FormatDate
##############################################################################
sub FormatDate{
	my $tracktime=shift();
	if($tracktime =~ /^(\w+) (\d{2}) (\d{4}) (\d{2})\:(\d{2}):(\d{2})\:\d{3}(\w{2})$/){
		my $month=$m2d{$1};
		my $day=$2;
		my $year=$3;
		my $apm=$7;
		my $hour=undef;
		if($apm eq "PM" && $4<12){
			$hour=$4+12;
		}else{
			$hour=$4;
		}
		my $minute=$5;
		my $second=$6;
		$tracktime=$year."-".$month."-".$day." ".$hour.":".$minute.":".$second;
		if($apm eq "AM" && $hour==12){
			#$hour = $hour-12;
			$tracktime = $year."-".$month."-".$day." 00:".$minute.":".$second;
		}else{
			$tracktime = $tracktime;
		}
	}

	return $tracktime;

}

##############################################################################
# Subroutine: ReplaceSpecialChars
##############################################################################
sub ReplaceSpecialChars{
	my $va=shift();
	return unidecode($va);

}

sub processLehWithStep {
  my $basename = shift;
	my $ext = shift;
  my $subfolder = shift;
  my $filepath=$indir.$basename."\.".$ext;
  my $poutdir = "";
  my $product;
	INFO("Processing ".$filepath);

  my $parser = PDF::Parser::BK_LEHS->new;
  my $model = $parser->readPerLineAndEnrichProduct( $filepath );
  #my $lehsDataPerProduct = $model->misc;


  # check output dir
  #INFO("Fork dir=$hOptions{FORK}");

  if($subfolder ne "") {
    &MakeSubDir($subfolder);
		$poutdir= $hOptions{out}."/".$subfolder;
	} else {
		$poutdir= $hOptions{out};
	}

  my $fileData = $model->misc;
  my $sourceLot;
  my $product;
  my $fab = $equip6_id;
  if($fab eq "") {
    $fab = "NA"
  }
  foreach my $key(keys (%{$fileData})){
		#INFO("ROUTE=$route");
		next if $key eq "header";
		#next if $route =~ /HASH.+/i;
    my $wr = PDF::DpWriter->new(
        {   outdir   => $poutdir,
       	    basename => ( basename $filepath),
            ext      => 'lehs',
            gzipIFF  => 'Y',
            pplogger => $pplogger
        }
    );

    $pplogger->setModelHeader($model);

    my $fmt = new_iff_formatter({
        model=>$model,
        writer=>$wr
    });

    if($key ne "" && $key !~ /header/i) {
      my @inputFileLineData = ();
      my ($lot,$grp4) = split(/\_/, $key);
      $grp4 =~ s/\?+/\_/;
      my ($sourceLot,$product,$process);
      my $hash = getRefdb->getBKLEHSmetadata($lot);
      if (keys %$hash > 0) {

        # if($hash->{product} ne "N/A") {
        #    #INFO("replace $columns[1] to $hash->{product}.");
        #    splice(@columns, 1, 1, $hash->{product});
        #  }
         $sourceLot = $hash->{source_lot};
         $product = $hash->{product};
         $process = $hash->{process};
         if($sourceLot !~ /.+\.\S$/i && $sourceLot ne "NA") {
           $sourceLot = "${sourceLot}.S";
         } elsif($sourceLot eq "NA") {
           $sourceLot = "${lot}.S";
         }
         # push(@columns,$sourceLot);
         # push(@columns,$hash->{process});
       } else {
          $wr->noMeta(1);
          $sourceLot = "${lot}.S";
          $product = "NA";
          $process = "NA";
       }
      my $addr = $fileData->{$key};
      #my $fname = "${outfilename}_${route}";
      #INFO("OUT=$fname");
      #$wr->basename($fname);
      #$wr->open;
      #$wr->put($fileData->{'header'}."\n");
      #push(@columns,$sourceLot);
      my $headerLine = $fileData->{header};
      $headerLine  = "${headerLine}|SOURCE_LOT|PROCESS|FAB";
      push(@inputFileLineData, $headerLine);
      foreach my $lineData(@$addr){
        my @columns = split(/\|/, $lineData);
        my $row;
        my $group4 = $columns[23];
        $group4 =~ s/\s+/\_/;
        splice(@columns, 23, 1, $group4);
        if($product ne "NA") {
          splice(@columns, 1, 1, $product);
        }
        push(@columns,$sourceLot);
        push(@columns,$process);
        push(@columns,$fab);
        if(@columns) { # && ($column[0] ne "" || $columns[1] =~ /FACILITY/i)) {
          $row = join('|', @columns);
        }
        push(@inputFileLineData, $row);
      }

      $model->misc(@inputFileLineData);

      my $fname = basename $filepath;
      $fname = "${fname}_${lot}_${grp4}";
      #INFO("OUT=$fname");
      $wr->basename($fname);

      $fmt->printLineArray();
    }

  } #end of foreach
} #end of Subroutine


