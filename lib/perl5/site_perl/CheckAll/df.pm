#-------------------------------- process Item -----------------------------------
#
# df - check file system available space.
#

use strict;
no strict 'refs';
use warnings;
package df;
use base 'CheckItem';
use fields qw(Port User Maxpercent Exclude Posix);	

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

sub Exclude {
	# Retrieve or validate and save the target.
	my $Self = shift;

	$Self->{Exclude} = () unless ($Self->{Exclude});
	if (@_) {
		my @List=split(',',shift);
		foreach (@List) {
			s/^\s+//;
			s/\s+$//;
			$Self->{Exclude}{$_}=1;
		}
	}
	else {
		return %{$Self->{Exclude}};
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
		$Self->{StatusDetail} = "Configuration error: Desc not specified";
		$Errors++;
	}
	if (! $Self->{Target}) {
		$Self->{StatusDetail} = "Configuration error: Target not specified";
		$Errors++;
	}
	if (! $Self->{Maxpercent}) {
		$Self->{StatusDetail} = "Configuration error: MaxPercent not specified";
		$Errors++;
	}
	return "Status=" . $Self->CHECK_FAIL if ($Errors);

        # Run overall checks.  Any defined response means set set the status and are done.
        my $Status = $Self->SUPER::Check($Self);
        return $Status if (defined($Status));

	# See if we've gathered the process information for this host yet.
	$Self->{Host} = 'localhost' unless (defined($Self->{Host}));
	my %Hash;
	my($device,$total,$used,$free,$percent,$mount);
	my $CmdStatus;
	if (!exists($HostHash{$Self->{Host}})) {
		# No.  Go gather it.
		my @Data;
		my $POSIX = (!defined($Self->{Posix}) or $Self->{Posix})?'-P':' ';
		if ($Self->{Host} eq 'localhost') {
			@Data = `df -k $POSIX`;
			$CmdStatus = "rc=$?";
		}
		else {
			# On a remote host.
			my $Cmd = 
    			'ssh '
    			. '-o "NumberOfPasswordPrompts 0" '
    			. ($Self->{Port}?"-oPort=$Self->{Port} ":'')
    			. ($Self->{User}?"$Self->{User}@":'')
    			. $Self->{Host}
    			. " df -k $POSIX"
    			;
    		for (my $Try = 1; $Try <= $Self->{'Tries'}; $Try++) {
    		    printf "\r\%5d   Gathering data from %s (%s) try %d\n", $$,$Self->{Host},$Self->{Desc},$Try if ($Self->Verbose);
    			eval("\@Data = `$Cmd`;");
    			last unless ($@ or $? != 0);
			$CmdStatus = ($??"rc=$?":$@);
		    }
		    if (@Data == 0)
		    {
			    $Self->{StatusDetail} = "Unable to gather data: $CmdStatus";
			    return "Status=" . $Self->CHECK_FAIL;
		    }
				
		}
		foreach (@Data) {
			next if (/^\s*Filesystem/);
			# Filesystem           1K-blocks      Used Available Use% Mounted on
			next if (/^\s*Filesystem\s/i);
    		        printf "\r\%5d       Processing: %s\n", $$,$_
				if ($Self->Verbose);
			my($device,$total,$used,$free,$percent,$mount) = split(/\s+/);
    		        printf "\r\%5d       device=%s, total=%s, used=%s, free=%s, percent=%s, mount=%s\n",
				$$,$device,$total,$used,$free,$percent,$mount
					if ($Self->Verbose);
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
		foreach (keys(%Hash)) {
			# Use everything except NFS mounts, which can be too many
			# to exclude due to /net.
			push @TargetList,$_ unless ($Hash{$_}->[0] =~ m"^[^/\s]+:");
		}
	}
	else {
		@TargetList = ($Self->{Target});
	}
	
	$Status = $Self->CHECK_OK;		# Assume no errors.
	my $Detail = '';
	foreach my $Target (@TargetList) {
		next if ($Self->{Exclude}{$Target});
		($device,$total,$used,$free,$percent) = @{$Hash{$Target}};
		printf "\r\%5d   Checking %s at %d%%\n", $$, $device, $percent
			if ($Self->{Verbose});
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

  df Target=/var MaxPercent=90
  df Target=/opt Host=hostname MaxPercent=90
  df Target=ALL MaxPercent=80 Exclude=/var,/opt
  

=head2 Fields

df is derived from CheckItem.pm.  It supports the same fields as CheckItem.  

The target field specifies a mount point to check.

In addition, the following optional fields are supported:

=over 4

=item *

Exclude = a comma separated list of files systems (mount points) to ignore.  This
is primarily intended for use with a target of "ALL" to test all but a fixed
set of file systems.

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

=item *

Posix - a true value adds the -P flag to the df command (default).  This option allows df to
work on some embedded systems that don't support the -P option by specifying Posix=0.

=back

=head2 Notes

=over 4

=item *

This module ignores df-reported items with a device name of "none", as these are not real 
file systems.

=item *

The target of "ALL" may be specified to check all items reported by df, except ones using a device of "none".

=back

=cut

