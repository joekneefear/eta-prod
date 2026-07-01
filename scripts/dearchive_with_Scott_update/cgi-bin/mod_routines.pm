# MODIFICATION HISTORY:
#
# DATE       WHO            COMMENTS
# ---------- -------------- ---------------------------------------------------
# 09/08/2012 Ben Rommel Kho Author
# 02/06/2013 Ben Rommel Kho Removed "fix_email_add_entry" routine
# 11/05/2015 ben Rommel Kho Adjusted for Exensio
#
#
#


###########################
# REMOTE EXECUTE A COMMAND
###########################
sub ssh
{
	my $host = shift;
	my $cmd  = shift;
	my @envs = split /\n/, `/usr/bin/ssh $host -q -l dpower $cmd`;
	return(@envs);
}


##############
# SAVE COOKIE 
##############
sub save_cookie
{
	my $name   = shift;
	my $val    = shift;
	my $expiry = shift;

	### SAVE DATA TO COOKIE ###
	$cookie->param($name, $val);

	### SET EXPIRATION ###
	$cookie->expire($name, $expiry) if $expiry=~/\d/;;
}


##############
# READ COOKIE
##############
sub read_cookie
{
	my $name = shift;
	if ($cookie->param($name) ne "")
	{
		return($cookie->param($name));
	}
}


################
# CLEAR COOKIES
################
sub clear_cookies
{
	$cookie->clear(\@_)
}


################
# REDIRECT PAGE
################
sub go_to_url
{
	my $url = shift;
	print "<script language='javascript'>",
	      qq{location.replace("$url")},
	      "</script>";
}


###################################
# STORE "GET/POST" DATA INTO A HASH
###################################
sub qs_to_hash
{
	my $str    = $ENV{'QUERY_STRING'};

	###############################
	# PARSE DATA INTO KEY/VAL PAIR
	###############################
        my @qs  = split /\&/, $str;
        my %qs  = ();
        foreach my $qs(@qs)
        {
                my ($key, $val) = split /\=/, $qs;
		$val      =~ tr/+/ /;
		$val      =~ s/%(..)/pack("C", hex($1))/eg;	### DECODE HTML "GE"T HEX VALUES
                $qs{$key} = $val;
        }
        return(%qs);

}



###################################################
# USES JAVASCRIPT's COOKIE TO STORE USERNAME TO PC
###################################################
sub save_js_cookie
{
	my $c_name  = shift;
	my $c_value = shift;
	
        print "<script>",
              "var exdate=new Date();",
	      "exdate.setDate(exdate.getDate() + 365);",
	      "var c_value=escape(\"$c_value\") + '; expires=' + exdate.toUTCString();",
	      "document.cookie=\"$c_name\" + '=' + c_value;",
              "</script>";
}


############################################################
# READS JAVASCRIPT COOKIE AND WRITE IT INTO AN HTML ELEMENT
############################################################
sub read_js_cookie
{
	my $c_name  = shift;
	my $element = shift;
	
	print "<script>",
	      "var i,x,y,ARRcookies=document.cookie.split(';');",
              "for (i=0;i<ARRcookies.length;i++)",
              "{",
              "    x=ARRcookies[i].substr(0,ARRcookies[i].indexOf('='));",
              "    y=ARRcookies[i].substr(ARRcookies[i].indexOf('=')+1);",
              "    x=x.replace(/^\\s+|\\s+\$/g,'');",
	      "    if (x==\"$c_name\")",
              "    {",
	      "       $element = unescape(y) ;",
              "    }",
              "}",
   	      "</script>";
}



##############
# SENDS EMAIL
##############
sub sendEmail
{
        my $subject   = shift;
        my $body      = shift;
        my $to        = shift;          ### ACCEPTS EMAIL ADD COMMA-DELIMTED
                                        ### OR FILE WITH LIST OF EMAIL ADDRESSES
        my $from      = shift;
        my $host      = "";

        ### GET HOST AS SMTP SERVER ###
        $host = `hostname`;
        chomp($host);

        ### USE HOSTNAME IF "FROM" IS BLANK ###
        $from = $host if $from eq "";

        ### READ IF "TO" IS A FILE ###
        if (-f $to && -e $to)
        {
                my $file = $to;
                   $to   = "";
                open MAIL, $file or print "Error: Can't open/read $file file. $!\n";
                while(my $email_add=<MAIL>)
                {
                        chomp($email_add);
                        $email_add =~ s/\s+//g;
                        next if $email_add eq "";
                        $to = ($to eq "") ? $email_add : $to .",". $email_add;
                }
                close(MAIL);
        }


        ### SEND EMAIL ###
        if ($to =~ /\@/)
        {
                my $mailto = MIME::Lite->new
                (
                        Subject => "$subject",
                        From    => "${from}@onsemi.com",
                        To      => "$to",
                        Type    => 'text/plain',
                        Data    => "$body"
                );

                $mailto->send($host);
        }
        else
        {
                print "Can't send email. Invalid addressee \"$to\".\n";
        }
}

1;
