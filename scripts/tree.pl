#!/usr/bin/perl

use File::Find;
use Getopt::Std;

getopts('d:ahfH');

$dir = '.';
if(@ARGV){
    $dir = shift @ARGV;
}
($opt_h) and &usage;
($opt_d) and ($dir = $opt_d);

$dir =~ s/\/$//;
find(\&show, $dir);

$ic  = 0;
$all = @tree;
foreach $tree ( sort {$b cmp $a} @tree ){
    $ic++;
    $name = $tree;
    $tree =~ s/$dir//;
    @line = split(/\//,$tree);
    $line[0] = $dir;

    @{$buf[$all-$ic]} = @line;
    next if($ic == 1);

    $icp  = $all - $ic + 1;
    $col  = @{$buf[$icp]};
    $colm = @{$buf[$icp-1]};

    if(-d $name){
        $buf[$icp-1]->[$colm-1] .= '/';
    }

    unless($col-2 <0){
        $buf[$icp]->[$col-2] = ' +--';
    }

    for($j = $col-3 ; $j >= 0; $j--){
        if($ic != 2){
            if($buf[$icp]->[$j] eq $buf[$icp-1]->[$j]){
                unless($buf[$icp+1]->[$j] =~ /\|/ || $buf[$icp+1]->[$j] =~ /\+\-\-/){
                    $buf[$icp]->[$j] = '    ';
                }else{
                    $buf[$icp]->[$j] = ' |  ';
                }
            }
        }else{
            if($buf[$icp]->[$j] eq $buf[$icp-1]->[$j]){
                $buf[$icp]->[$j] = '    ';
            }else{
                $buf[$icp]->[$j] = ' |  ';
            }
        }

    }
}

for( $i = 0 ; $i < $ic ; $i++){
    print "@{$buf[$i]}\n";
}
exit;

sub show{

    if(-d || $opt_f){
        (!$opt_a && ($File::Find::name =~ /\/\.[^\.]/)) and return;
        push(@tree, $File::Find::name);
    }
}

sub usage{
    print <<'END';

USAGE:
        tree.pl [-a] [-d <dir>] [-f] [-h] [<dir>]

OPTIONS:
   <dir>
       specify directory which you want to show

    -a
       do not hide entries starting with .

    -f
       show all files

    -h
       show this message

    -d <dir>
       specify directory which you want to show

END
    exit;
}

