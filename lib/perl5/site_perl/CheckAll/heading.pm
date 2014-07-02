#-------------------------------- heading Item -----------------------------------
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

	my $ValueRef = shift;
	my $Value = $ValueRef->[0];
	$Value = '' unless (defined($Value));	# Allow blank lines.
	$Value =~ s/^(["'])(.*)\1/$2/;		# Strip quotes if present.
	$Self->{Desc} = $Value;

	# Also, set a name for status purposes.
	$Self->{Name}="$Self->{FILE}:$Self->{LINE}";
}
		

sub Check {

	# See if this item is OK.
	my $Self = shift;

	return "Status=" . $Self->CHECK_OK;		# Headings never fail.

}

sub Report {
        my($Self,$DescLen,$failonly) = @_;

	# Can't use Iftime logic, as header doesn't use parm=value
#        if ($Self->{Iftime}) {
#                my $Status = CheckTimePattern($Self, $Self->{FILE}, $Self->{LINE}, $main::StartTime);
#                return "Status=$Status" if ($Status);
#        }

        printf "%s\n", $Self->{Desc} if (!$main::Options{quiet} and !$failonly);
        return $Self->{Status};
}

1;

=pod

=head1 Checkall::heading

=head2 Summary

heading prints a heading line in the output.

=head2 Syntax

  heading heading-text

=head2 Fields

heading is derived from CheckItem.pm.  It supports the same fields as CheckItem.  The heading
text is stored in the Desc field.  No additional fields are provided.
=cut
