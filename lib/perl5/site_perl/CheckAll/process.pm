#-------------------------------- process Item -----------------------------------
#
# process - check to see if a process is present.
#

use strict;
no strict 'refs';
use warnings;
package process;
use base 'CheckItem';
use fields qw(Port User);

my %ProcessHash;	# Hash of lists of processes, keyed by remote host.

#================================= Data Accessors ===============================
sub Target {

	# Retrieve or validate and save the target.
	my $Self = shift;

	if (@_) {
		# This is a set operation.
		my $TargetDef = shift;
		eval "\$Self->{Target} = qr${TargetDef};";
		if ($@) {
			print "$Self->{FILE}:$Self->{LINE}: " .
				qq[Invalid target expression "$TargetDef": $@\n];
			return undef();
		}
		else {
			return 1;
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
	printf "\n%5d %s Checking %s %s\n", $$, __PACKAGE__, $Self->Host, $Self->Target
		if ($Self->{Verbose});
		
	# First, make sure we have the necessary config info.
	my $Errors = 0;
	if (! $Self->{Desc}) {
		warn "$File:$Line: Desc not specified.\n";
		$Self->{StatusDetail} = "Configuration error: Desc not specified";
		$Errors++;
	}
	if (! $Self->{Target}) {
		warn "$File:$Line: Target not specified.\n";
		$Self->{StatusDetail} = "Configuration error: Target not specified";
		$Errors++;
	}
	return "Status=" . $Self->CHECK_FAIL if ($Errors);

        # Run overall checks.  Any defined response means set set the status and are done.
        my $Status = $Self->SUPER::Check($Self);
        return $Status if (defined($Status));

	# See if we've gathered the process information for this host yet.
	$Self->{Host} = 'localhost' unless (defined($Self->{Host}));
	if (!exists($ProcessHash{$Self->{Host}})) {
		# No.  Go gather it.
		my @Data;
		if ($Self->{Host} eq 'localhost') {
			@Data = `ps -e o cmd`;
		}
		else {
			# On a remote host.
			my $Cmd = 
				'ssh '
				. '-o "NumberOfPasswordPrompts 0" '
				. ($Self->{Port}?"-oPort=$Self->{Port} ":'')
				. ($Self->{User}?"$Self->{User}@":'')
				. $Self->{Host}
				. ' ps -e -o cmd '
				;
			for (my $Try = 1; $Try <= $Self->{'Tries'}; $Try++) {
    		    printf "\r\%5d   Gathering data from %s (%s) try %d\n", $$,$Self->{Host},$Self->{Desc},$Try if ($Self->Verbose);
    			eval("\@Data = `$Cmd`;");
    			last unless ($@ or $? != 0);
		    }
		    if (@Data == 0)
		    {
			    warn "$Self->{FILE}:$Self->{LINE} Unable to gather data from $Self->{Host}: rc=$?, $@\n";
			    $Self->{StatusDetail} = "Unable to gather data";
			    return "Status=" . $Self->CHECK_FAIL;
		    }
		}
		$ProcessHash{$Self->{Host}} = \@Data;
	}

	foreach (@{$ProcessHash{$Self->{Host}}}) {
	    chomp;
		printf "\r%5d   Checking %s\n", $$, $_ if ($Self->{Verbose});
		return "Status=" . $Self->CHECK_OK if ( $_ =~ $Target );
	};
	return "Status=" . $Self->CHECK_FAIL;
}
1;

=pod

=head1 Checkall::process

=head2 Summary

process checks for the presence of a running process on a local or remote system.

=head2 Syntax

  process Target="process-regex"
  process Target="process-regex" Host=hostname Port=portnum User=username
  

=head2 Fields

process is derived from CheckItem.pm.  It supports the same fields as CheckItem.  

The target field specifies a regex.  The results of "ps -e -o cmd" is searched for any 
item matching the regex.  The provided regex must include regex delimiters, and if the pattern
contains spaces, it must be quoted or the spaces escaped.  Examples:

	Target="/^init /"
	Target="_^/sbin/rsyslogd_"	# Using underscores for delims.

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

=cut

