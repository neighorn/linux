#-------------------------------- process Item -----------------------------------
#
# adjoin - check whether we're joined to an Active Directory server.
#

use strict;
no strict 'refs';
use warnings;
package adjoin;
use base 'CheckItem';
use fields qw(Port User);

#================================= Public Methods ===============================

sub Check {

	# See if this item is OK.
	my $Self = shift;

	my $File = $Self->{'FILE'};
	my $Line = $Self->{'LINE'};
	my $Target = $Self->{'Target'};
	printf "\n%5d %s Checking %s\n", $$, __PACKAGE__, $Self->Host
		if ($Self->{Verbose});
		
	# First, make sure we have the necessary config info.
	my $Errors = 0;
	$Self->{Desc} = 'adjoin' unless ($Self->{Desc});
	return "Status=" . $Self->CHECK_FAIL if ($Errors);

        # Run overall checks.  Any defined response means set set the status and are done.
        my $Status = $Self->SUPER::Check($Self);
        return $Status if (defined($Status));

	# See if we've gathered the process information for this host yet.
	my @Data;
	my $BaseCmd = 'net ads testjoin 2>&1 < /dev/null ';	# Our core command, whether local or remote.
	if ($Self->{Host} and $Self->{Host} ne 'localhost') {
		# On a remote host.
		my $Cmd = 
			'ssh '
			. '-o "NumberOfPasswordPrompts 0" '
			. ($Self->{Port}?"-oPort=$Self->{Port} ":'')
			. ($Self->{User}?"$Self->{User}@":'')
			. $Self->{Host} . ' '
			. $BaseCmd
			. ' 2>&1'
			;
    		for (my $Try = 1; $Try <= $Self->{'Tries'}; $Try++) {
    			printf "\r\%5d   Gathering data from %s (%s) try %d\n", $$,$Self->{Host},$Self->{Desc},$Try if ($Self->Verbose);
    			eval("\@Data = `$Cmd`;");
    			last unless ($@ or $? != 0);
		}
		if (@Data == 0)
		{
			$Self->{StatusDetail} = 'Unable to gather data';
			return "Status=" . $Self->CHECK_FAIL;
		}
	}
	else {
		@Data = `$BaseCmd`;
	}

	if ($Self->{Verbose}) {
		foreach (@Data) {
			printf "\r\%5d     %s (%s) received %s\n", $$,$Self->{Host},$Self->{Desc}, $_;
		}
	}

	my $Detail;
	my $Actual = ($Data[0]?$Data[0]:'');
	chomp $Actual;
	if ($Actual =~ / OK\s*$/) {
		$Status = $Self->CHECK_OK;
		$Detail = '';
	}
	else {
		$Status = $Self->CHECK_FAIL;
		$Detail = $Actual;
	}
			
	$Self->{StatusDetail}=$Detail;
	return "Status=" . $Status;
}
1;

=pod

=head1 Checkall::adjoin

=head2 Summary

adjoin checks to see if the specified host is joined to an active directory server.

=head2 Syntax

  adjoin				# Check the localhost
  adjoin Host=alpha			# Check to see if host 'alpha' is joined.

=head2 Fields

adjoin is derived from CheckItem.pm.  It supports the same fields as CheckItem.  
In addition, the following optional fields are supported:

=over 4

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

