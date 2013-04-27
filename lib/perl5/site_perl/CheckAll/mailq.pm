#-------------------------------- process Item -----------------------------------
#
# mailq - count items in the mail queue.
#

use strict;
no strict 'refs';
use warnings;
package mailq;
use base 'CheckItem';
use fields qw(Port User);

#================================= Data Accessors ===============================
sub Target {

	# Retrieve or validate and save the target.
	my $Self = shift;

	if (@_) {
		# This is a set operation.
		my $Target = shift;
		if ($Target =~ /^\s*([<>]?\d{1,2}|100)%?\s*$/) {
			$Self->{Target} = $1;
			return 1;
		}
		else {
			print "$Self->{FILE}:$Self->{LINE}: " .
				qq[Invalid Target value "$Target"\n];
			return undef();
		}
	}
	else {
		# This is a read operation.
		return $Self->{Target};
	}
}

#================================= Public Methods ===============================

sub Check {

	# See if this item is OK.
	my $Self = shift;

	my $File = $Self->{'FILE'};
	my $Line = $Self->{'LINE'};
	my $Target = $Self->{'Target'};

	# First, make sure we have the necessary config info.
	my $Errors = 0;
	$Self->{Desc} = 'mailq' unless ($Self->{Desc});
	if (! $Self->{Target}) {
		warn "$File:$Line: Target not specified.\n";
		$Self->{StatusDetail} = "Configuration error: Target not specified";
		$Errors++;
	}
	return "Status=" . $Self->CHECK_FAIL if ($Errors);

	# See if we've gathered the process information for this host yet.
	my @Data;
	if ($Self->{Host}) {
		# On a remote host.
		my $Cmd = 
			'ssh '
			. '-o "NumberOfPasswordPrompts 0" '
			. ($Self->{Port}?"-oPort=$Self->{Port} ":'')
			. ($Self->{User}?"$Self->{User}@":'')
			. $Self->{Host}
			. ' mailq '
			. ' 2>&1 '
			;
		eval("\@Data = `$Cmd`;");
		warn "$Self->{FILE}:$Self->{LINE} Unable to gather data from $Self->{Host}: $@\n"
			if ($@);
	}
	else {
		@Data = `mailq`;
	}

	my $Status = $Self->CHECK_OK;		# Assume no errors.
	my $Detail = '';
	my $Actual = @Data;
	if ($Target =~ /^<(\d+)/) {
		$Target = $1;
		if ($Actual > $Target) {
			$Status = $Self->CHECK_FAIL;
			$Detail = "Actual $Actual > $Target";
		}
	}
	elsif ($Target =~ /^\>(\d+)/) {
		$Target = $1;
		if ($Actual < $Target) {
			$Status = $Self->CHECK_FAIL;
			$Detail = "Actual $Actual < $Target";
		}
	}
	else {
		$Target = $Self->{Target};
		if (@Data != $Target) {
			$Status = $Self->CHECK_FAIL;
			$Detail = "Actual $Actual != $Target";
		}
	}
			
	$Self->{StatusDetail}=$Detail;
	return "Status=" . $Status;
}
1;

=pod

=head1 Checkall::mailq

=head2 Summary

mailq checks on the output from a mailq command.

=head2 Syntax

  mailq	Target=>1		# Output lines must be 1 or greater.
  mailq	Target=<5		# Output lines must be 5 or less.
  mailq	Target=3			# Output lines must be 3.

=head2 Fields

mailq is derived from CheckItem.pm.  It supports the same fields as CheckItem.  

The Target field is required, and defines the expected number of lines of output from mailq.
It may be prefixed with a > symbol to indicate the specified value or larger; or with a < symbol
to indicate the specified value or less.

In addition, the following optional fields are supported:

=over 4

=item *

Target is a regexp that is used to filter the output from mailq.  This feature
is currently not implemented.

=item *

Host = name or IP address of a remote host.  Processes on this host will be checked.
The default is to search for processes on the local host.

=item *

Port = the ssh port to connect to.  The default is to not specify a port number, which 
typically results in using port 22.

=item *

User = the name of the remote user account.  The default is to not specify a remote user name
typically resulting in using the same name as the local user.

=back

=head2 Notes

=over 4

=item *

(none)

=back

=cut

