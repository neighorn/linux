#-------------------------------- TCPPort Item -----------------------------------
#
# heading - print a heading
#

use strict;
no strict 'refs';
use warnings;
package heading;
use base 'CheckItem';

#================================= Data Accessors ===============================

#================================= Public Methods ===============================

sub SetOptions {
		
	my $Self = shift;

	# Headings don't use the standard xxx=yyy format.  Instead, it's just
	# a single line of text.  Save it as the description.

	$Self->{Desc} = shift;
	$Self->{Desc} =~ s/^(["'])(.*)\1/$2/;		# Strip quotes if present.
}
		

sub Check {

	# See if this item is up.
	my $Self = shift;

	return "Status=" . $Self->CHECK_OK;		# Headings never fail.

}

sub Report {
        my $Self = shift;

        printf "%-48.48s --\n", $Self->{Desc} if (!$main::opt_q);
        return $Self->{Status};
}

1;
