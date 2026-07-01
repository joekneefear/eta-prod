#!/bin/csh

# Strip the MD5 string from all files in the current directory. 
# If the file doesn't have an MD5 string, nothing is changed.
# Usage:
#   CD to directory where files reside.

# To list the files with MD5s and show what the new names will be:
# % stripMD5.csh test

# To list the files with MD5s, show what the new names will be and do the rename:
# % stripMD5.csh strip

# To list the files with MD5s, do the rename with no listing of changes:
# % stripMD5.csh strip_quiet

if ( $#argv != 1 ) then
   echo "USAGE: $0 test|strip|strip_quiet"
   exit 1
endif

set mode = $argv[1]

if ( "$mode" != "test" && "$mode" != "strip" && "$mode" != "strip_quiet" ) then
   echo "USAGE: $0 test|strip|strip_quiet"
   exit 1
endif

set nonomatch

set md5s = ( *_MD5-* )
unset nonomatch
if ( $#md5s == 0 ) then
  echo "Nothing to rename."
  exit 1
else if ("$md5s[1]" == '*_MD5-*' ) then
  echo "Nothing to rename."
  exit 1
endif

foreach md5 ( $md5s )
  set new = `echo $md5 | sed 's/.\{37\}$//'`
  if ( "$mode" != "strip_quiet" ) then
    echo "$md5 $new"
  endif
  if ( "$mode" != "test" ) then
     /bin/mv $md5 $new
  endif
end
