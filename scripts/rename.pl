$file = $ARGV[0];
$file =~ /^(.+\.zip)\..+/; 
print $1;
rename $file, $1  or die "cannot rename $!";
