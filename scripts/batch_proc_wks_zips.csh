#!/bin/csh

gunzip *.gz
~/project/scripts/stripMD5.csh strip_quiet
foreach z (*.zip)
set a=$z:r
set b=$a.ZIP
mv $z $b
end
