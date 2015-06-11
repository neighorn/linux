# Declare our group path name.
COMPANY=""
export COMPANY
# Set our path.
test -n "$COMPANY" && PATH="/usr/$COMPANY/sbin:/usr/$COMPANY/bin:$PATH"
PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:$PATH
export PATH
# Set up our aliases.
alias r="fc -s"
# Expand our PERL path.
test -n "$COMPANY" && PERL5LIB="/usr/$COMPANY/lib/perl5/site_perl:$PERL5LIB"
PERL5LIB="/usr/local/lib/perl5/site_perl:$PERL5LIB"
PERL5LIB="${PERL5LIB%:}"	# Strip trailing colon, if any.
export PERL5LIB
#
export HISTTIMEFORMAT="%F %T "
#
# Change LS colors (directory from blue to green; blue on black is hard to read)
LS_COLORS=`echo $LS_COLORS|sed 's/di=00;34/di=00;33/'`
