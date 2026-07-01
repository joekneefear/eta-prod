#
# CHANGES
# 23-Jun-2015 gilbert: Change Program name from RH_MT to RH.
# 26-Aug-2015 gilbert: Uppercase the lot id.
# 29-Oct-2015 eric   : extract correct tp rev location
#
package PDF::Parser::RH_MT;
use strict;
use PDF::DpData;
use PDF::DpLoad;
use PDF::Log;
use v5.10;
no warnings qw/experimental::smartmatch experimental::lexical_subs/;

use base qw/PDF::DpData::Base Class::Accessor/;
our $VERSION = "1.0";

my $attr = [ qw/minX minY maxX maxY/];
sub array {
   return qw/testConditions_EPDR/;
}

__PACKAGE__->mk_accessors(array);

=pod
--- header ---
$REV06,20246FTJ,          ,2015/03/30,14:41:52,        ,REEDHOLM,     1 , 32766 ,     3 ,   270 , 8.000000E+00 , 6.129020E+04 , 4.516120E+04 ,LHMFG          ,               , 65535
Fixed comments: 0
Test plans: 0
Operator comments: 0
27365   ,    14 ,255
1,     1 ,255
Revision,-1.000000E+37 , 1.000000E+37 ,-1.000000E+37 , 1.000000E+37 ,-1.000000E+37 , 1.000000E+37 ,     0 ,   100 ,NONE
2,     2 ,255
RsSrcBody,-1.000000E+37 , 1.000000E+37 ,-1.000000E+37 , 1.000000E+37 ,-1.000000E+37 , 1.000000E+37 ,     0 ,   100 ,Ohms
RsHeavyBody,-1.000000E+37 , 1.000000E+37 ,-1.000000E+37 , 1.000000E+37 ,-1.000000E+37 , 1.000000E+37 ,     0 ,   100 ,Ohms
3,     2 ,255
RsBodyPinch,-1.000000E+37 , 1.000000E+37 ,-1.000000E+37 , 1.000000E+37 ,-1.000000E+37 , 1.000000E+37 ,     0 ,   100 ,Ohms
RsHBPinch,-1.000000E+37 , 1.000000E+37 ,-1.000000E+37 , 1.000000E+37 ,-1.000000E+37 , 1.000000E+37 ,     0 ,   100 ,Ohms
4,     2 ,255
&&&&
#22,1,27365, 0.000000E+00 , 0.000000E+00
 2.000000E+00 ,     0
#22,1,27365, 0.000000E+00 , 0.000000E+00
 3.800000E+21 ,     0
 7.140807E+04 ,     0
#22,1,27365, 0.000000E+00 , 0.000000E+00
=cut

sub readFile{
  my $self = shift;
  my $infile = shift;
  my $testPlan = shift;
  open (INFILE, $infile);
  my $header = new_headerLong;
  my $wmap = new_wmap({
     positive_x => 'R',
     positive_y => 'D'
     });
  my $model = new_model({
    header=>$header,
    misc => {},
	wmap => $wmap,
    dataSource => 'RH'
   });

  my %wfSize = (
        4   => 100,
        6  => 150,
        8 => 200,
        12 => 300,
	);
  my %flatDir = (
        0   => 'T',
        90  => 'R',
        180 => 'B',
        270 => 'L',
	);
  my $wafers = {};
  my $waferSites = {};
  my $wafer;
  my $testNum = 0;
  my %testList = ();

  my $section = "Header";
  my ($columns, $rows);
  my $line = 1;
  while(<INFILE>)
  {
	if ($line==1)
	{
		my @item = split(/\s*,\s*/);
		$header->START_TIME($item[3]." ".$item[4]);
		$header->EQUIP1_ID($item[6]);
		$header->LOT(uc($item[14]));
		$wmap->flat( $flatDir{ $item[10] } );
		$wmap->wf_size($wfSize{ int($item[11]) } );
		$wmap->die_width(eng($item[12])/25.4/1000);
		$wmap->die_height(eng($item[13])/25.4/1000);
		$wmap->flat_type('N');
		$wmap->wf_units('mm');
		if($wmap->wf_size < 200){
			$wmap->flat_type('F');
		}
	}
	if ($line==5)
	{
		my @item = split(/\s*,\s*/);
		$header->PROGRAM($item[0]);
	}
	if($line==6)
	{
		$section = "Tests";
	}

    if ($section eq "Tests")
	{
		my @item = split(/\s*,\s*/);
		# ~~~~ signifies end of header block and beginning of data block
		if($item[0] =~ '&&&&')
		{
			$section = "Data";
			next;
		}

		my $testCnt = int($item[1]);
		my $testGrp = $item[0];
		$testList{ keys( %testList ) } = $testCnt;

		for(my $i=0;$i<$testCnt;$i++)
		{
			my @tests = split(/\s*,\s*/, <INFILE>);
			my $test = new_test;
			$test->number( $testNum );
			my $tpTest;
			# check for test plan
			if(defined($testPlan)){
				$tpTest = $testPlan->find("tests",{number=>$testNum});
			}
			# if no test plan, use local info
			if(!defined($tpTest)){
				$test->name( repNA( $tests[0] ) );
				$test->units( repNA( $tests[9] ) );
				$test->LSL( repNA( $tests[1] ) );
				$test->HSL( repNA( $tests[2] ) );
			}else{
				$test->name( $tpTest->name );
				$test->units( $tpTest->units );
				$test->LSL( $tpTest->LSL );
				$test->HSL( $tpTest->HSL );
				$test->LOL( $tpTest->LOL );
				$test->HOL( $tpTest->HOL );
			}
			$model->add('tests',$test);

			$line++;
			$testNum++;
		}
    }
    if ($section eq "Data"){
		my @item = split(/\s*,\s*/);
		my $waferNum = $item[0];
		$waferNum =~ s/^.{1}//s;

		# wafer
		if(!defined($wafer)){
			$wafer = new_wafer( { number => $waferNum } );
			$model->add('wafers',$wafer);
		}
		if($waferNum != $wafer->number){
			$wafer = new_wafer( { number => $waferNum } );
			$model->add('wafers',$wafer);
		}

		# new die
		my $die = new_die;
		$die->x(int($item[3]));
		$die->y(int($item[4]));
		$die->site(int($item[1]));

		# loop over tests hash and grab data
		$testNum = 0;
		for(my $test = 0;$test < keys( %testList );$test++)
		{
			my $numTests = $testList{$test};
			# loop over tests in file
			for(my $i = 0;$i < int($numTests);$i++)
			{
				my @data = split(/\s*,\s*/, <INFILE>);
				if($i==0 && !defined($header->REVISION))
				{
					$header->REVISION(int($data[0]));
				}
				# log results
				# skip revision
				if(uc($model->tests->[$test]->name) eq "REVISION"){
					next;
				}
				$die->add( 'result', $data[0] );
				$line++;
			}
			# skip repeating wafer info row
			if($test < keys( %testList )-1){
				my $ignore = <INFILE>;
				$line++;
			}
			$testNum++;
		}
		$wafer->add('dies',$die);
    }
	$line++;
  }

$wmap->calcCenterDie($wafer->stats);
$wmap->convertDieSizeToMM('MILS', $wafer->stats );

# remove revision if exists
if(uc($model->tests->[0]->name) eq "REVISION"){
    splice(@{$model->{tests}}, 0, 1);
}

return $model;
}

sub eng
{
	my ($ENG) = @_;

	my $num = 0.0;
	my $exp = 0;

	($num, $exp) = split(/[Ee]/, $ENG);

	return ($num * 10 ** $exp);
}

sub GetProgramRev{
	my $self   = shift;
        my $infile = shift;
	open( INFILE, $infile );
        my $line = 1;
	my $ln = 1;
	my $program;
	my $rev;
	while(<INFILE>)
    	{
		if ($line==5)
		{
			my @item = split(/\s*,\s*/);
			$program = $item[0];
		}
		#if ($line==8)
		#{
		#	my @item = split(/\s*,\s*/);
		#	$rev = $item[0];
		#	last;
		#}
		if ($_ =~ /^#/ && $ln == 1)
		{
			$ln = ($line + $ln);
		}
		if ($line == $ln && $ln != 1){
			my @item = split(/\s*,\s*/);
			$rev = int($item[0]);
			last;
		}
		$line++;
	}

	return $program."_".$rev."*.TPL";
}

sub readTestPlanFile {
	my $self   = shift;
    my $infile = shift;
    my $num = 0;
	my $header = new_headerLong;
	my $model = new_model({
		header=>$header,
		dataSource => 'RH'
    });
	INFO("Test Plan File : ".$infile);
    open( INFILE, $infile );
    while (<INFILE>) {
        s/[\r\n]+\z//;
        $num++;
        if($num < 4){
          next;
        }
		my @item = split(/\s*,\s*/);
		my $test = new_test;
		$test->number(repNA($item[0]));
		$test->name(repNA($item[1]));
		$test->units(repNA($item[2]));
		$test->LSL(repNA($item[3]));
		$test->HSL(repNA($item[4]));
		$test->LOL(repNA($item[5]));
		$test->HOL(repNA($item[6]));
		$model->add('tests',$test);
    }

	return $model;
}

1;
