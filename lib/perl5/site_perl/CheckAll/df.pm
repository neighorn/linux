#-------------------------------- process Item -----------------------------------
#
# df - check file system available space.
#

use strict;
no strict 'refs';
use warnings;
package df;
use base 'CheckItem';
use fields qw(Host Port User Maxpercent);

my %HostHash;	# Hash of lists of df data.

#================================= Data Accessors ===============================
sub Maxpercent {

	# Retrieve or validate and save the target.
	my $Self = shift;

	if (@_) {
		# This is a set operation.
		my $Maxpercent = shift;
		if ($Maxpercent =~ /^\s*(\d{1,2}|100)%?\s*$/) {
			$Self->{Maxpercent} = $1;
			return 1;
		}
		else {
			print "$Self->{FILE}:$Self->{LINE}: " .
				qq[Invalid Maxpercent value "$Maxpercent"\n];
			return undef();
		}
	}
	else {
		# This is a read operation.
		return $Self->{Maxpercent};
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
	if (! $Self->{Maxpercent}) {
		warn "$File:$Line: MaxPercent not specified.\n";
		$Self->{StatusDetail} = "Configuration error: MaxPercent not specified";
		$Errors++;
	}
	return "Status=" . $Self->CHECK_FAIL if ($Errors);

	# See if we've gathered the process information for this host yet.
	$Self->{Host} = 'localhost' unless (defined($Self->{Host}));
	my %Hash;
	my($device,$total,$used,$free,$percent,$mount);
	if (!exists($HostHash{$Self->{Host}})) {
		# No.  Go gather it.
		my @Data;
		if ($Self->{Host} eq 'localhost') {
			@Data = `df -Pk`;
		}
		else {
			# On a remote host.
			my $Cmd = 
				'ssh '
				. '-o "NumberOfPasswordPrompts 0" '
				. ($Self->{Port}?"-oPort=$Self->{Port} ":'')
				. ($Self->{User}?"$Self->{User}@":'')
				. $Self->{Host}
				. ' df -Pk '
				;
			eval("\@Data = `$Cmd`;");
			warn "$Self->{FILE}:$Self->{LINE} Unable to gather data from $Self->{Host}: $@\n"
				if ($@)
		}
		foreach (@Data) {
			next if (/^\s*Filesystem/);
			# Filesystem           1K-blocks      Used Available Use% Mounted on
			my($device,$total,$used,$free,$percent,$mount) = split(/\s+/);
			next if ($device eq 'none');
			$percent=~s/%//;
			@{$Hash{$mount}} = ($device,$total,$used,$free,$percent);
		}
		$HostHash{$Self->{Host}} = \%Hash;
	}
	else {
		# Retrive the previously gathered data.
		%Hash = %{$HostHash{$Self->{Host}}};
	}

	my @TargetList;
	if ($Self->{Target} =~ /^ALL$/i) {
		@TargetList = keys(%Hash);
	}
	else {
		@TargetList = ($Self->{Target});
	}
	
	my $Status = $Self->CHECK_OK;		# Assume no errors.
	my $Detail = '';
	foreach my $Target (@TargetList) {
		print __PACKAGE__ . "::Check: $File:$Line Checking $Self->{Target}\n"
			if ($Self->{Verbose});
		($device,$total,$used,$free,$percent) = @{$Hash{$Target}};
		if ($Self->{Maxpercent}) {
			if (defined($percent)) {
				if ($percent > $Self->{Maxpercent}) {
					$Detail .= ", $Target at $percent%";
					$Status = $Self->CHECK_FAIL;
				}
			}
			else {
				$Detail .= ", $Target not mounted";
				$Status = $Self->CHECK_FAIL;
			}
		}
	}
			
	$Detail =~ s/^, //;
	$Self->{StatusDetail}=$Detail;
	return "Status=" . $Status;
}
1;

=pod

=head1 Checkall::df

=head2 Summary

df checks on the output from a df -Pk command.

=head2 Syntax

  process Target=/var MaxPercent=80
  Process Target=ALL MaxPercent=90
  process Target=/opt Host=hostname MaxPercent=70
  

=head2 Fields

df is derived from CheckItem.pm.  It supports the same fields as CheckItem.  

The target field specifies a mount point to check.

In addition, the following optional fields are supported:

=over 4

=item *

MaxPercent = the maximum percent df may report before an alert is issued.

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

This module ignores df-reported items with a device name of "none", as these are not real 
file systems.

=item *

ALL may be specified to check all items reported by df, except ones using a device of "none".

=back

=cut

