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

	# Need a copy of STDOUT for consistency between forked and non-forked environment.
	open(REALSTDOUT,'>&STDOUT') || warn "Unable to duplicate STDOUT: $!";

	# Don't have any data on this host.  Go gather it.
	my $POSIX = (!defined($Self->{Posix}) or $Self->{Posix})?'-P':' ';

	my(@RunResult) = $Self->RunCmd(Command => "df -k $POSIX");

        if (ref($RunResult[0]) eq 'ARRAY') {
                # Must be from a fork.  Just back the array reference.
		my $arrayref=$RunResult[0];
		return($arrayref);
        }
        elsif ($RunResult[0] ne 'Results') {
		# We have a status already (must have failed to fork, failed to connect, etc.).
		# Just pass it back.
                return(@RunResult);
        }
	else {
		my(undef,$CmdStatus,@Data) = @RunResult;

		# Find out how we're doing.
		CheckData($Self,@Data);
		printf "\r\%5d	Status=%d, Detail=%s\n", $$, $Self->{Status}, $Self->{StatusDetail}
			if ($Self->{Verbose});
		return "Status=" . $Self->{Status}
	}
}



#
# CheckData
#
sub CheckData {
	my($Self,@Data) = @_;
	my $Host = $Self->{Host};

	my @TargetList;
	if ($Self->{Target} =~ /^(ALL|LOCAL)$/i) {
		foreach my $Target (keys(%{$HostHash{$Host}})) {
			# Use everything except NFS and CIFS mounts
			# to exclude due to /net.
			push @TargetList,$Target unless ($HostHash{$Host}{$Target}{device} =~ m"^[^/\s]+(:|//)");
		}
	}
	else {
		@TargetList = ($Self->{Target});
	}
	
	my $Status = $Self->CHECK_OK;		# Assume no errors.
	my $Detail = '';
	foreach my $Target (@TargetList) {
		next if (exists($Self->{Exclude}{$Target}));
		if (! exists($HostHash{$Host}{$Target}{percent})) {
				$Detail .= ", $Target not mounted";
				$Status = $Self->CHECK_FAIL;
				next;
		}
		my $percent = $HostHash{$Host}{$Target}{percent};
		printf REALSTDOUT "\r\%5d   Checking %s at %d%%\n", $$, $Target, $percent
			if ($Self->{Verbose});
		if ($percent > $Self->{Maxpercent}) {
			$Detail .= ", $Target at $percent%";
			$Status = $Self->CHECK_FAIL;
		}
	}
			
	$Detail =~ s/^, //;
	$Self->{Status} = $Status;
	$Self->{StatusDetail}=$Detail;
	return $Status;
}
1;

=pod

=head1 Checkall::df

=head2 Summary

df checks on the output from a df -Pk command.

=head2 Syntax

  df Target=/var MaxPercent=90
  df Target=/opt Host=hostname MaxPercent=90
  df Target=LOCAL MaxPercent=80 Exclude=/var,/opt
  

=head2 Fields

df is derived from CheckItem.pm.  It supports the same fields as CheckItem.  

The target field specifies a mount point to check.

In addition, the following optional fields are supported:

=over 4

=item *

Exclude = a comma separated list of files systems (mount points) to ignore.  This
is primarily intended for use with a target of "LOCAL" to test all but a fixed
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

The target of "LOCAL" may be specified to check all items reported by df, except ones using a device of "none",
NFS, or CIFS.

=back

=cut

