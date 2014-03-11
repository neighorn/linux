#-------------------------------- process Item -----------------------------------
#
# findcmd - run a find command and count the results.
#

use strict;
no strict 'refs';
use warnings;
package findcmd;
use base 'CheckItem';
use fields qw(Port User Parms );

#================================= Data Accessors ===============================
sub Target {

	# Retrieve or validate and save the target.
	my $Self = shift;

	if (@_) {
		# This is a set operation.
		my $Target = shift;
		if (defined($Target) and $Target =~ /^\d+$/ ) {
			$Self->{Target} = $Target;
			return 1;
		}
		else {
			print "$Self->{FILE}:$Self->{LINE}: " .
				qq[Missing or invalid Target value "$Target"\n];
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
	printf "\n%5d %s Checking %s %s\n", $$, __PACKAGE__, $Self->Host, $Self->Target
		if ($Self->{Verbose});
		
	# First, make sure we have the necessary config info.
	my $Errors = 0;
	$Self->{Desc} = 'findcmd' unless ($Self->{Desc});
	if (!exists($Self->{Target}) or !defined($Self->{Target})) {
		warn "$File:$Line: Target not specified.\n";
		$Self->{StatusDetail} = "Configuration error: Target not specified";
		$Errors++;
	}
	if (! $Self->{Parms}) {
		warn "$File:$Line: Parms not specified.\n";
		$Self->{StatusDetail} = "Configuration error: Parms not specified";
		$Errors++;
	}
	return "Status=" . $Self->CHECK_FAIL if ($Errors);

        # Run overall checks.  Any defined response means set set the status and are done.
        my $Status = $Self->SUPER::Check($Self);
        return $Status if (defined($Status));

	my @Data;
	my $BaseCmd = "find " . $Self->{Parms} . " | wc -l";
	if ($Self->{Host} and $Self->{Host} ne "localhost") {
		# On a remote host.
		my $Cmd = 
			'ssh '
			. '-o "NumberOfPasswordPrompts 0" '
			. ($Self->{Port}?"-oPort=$Self->{Port} ":'')
			. ($Self->{User}?"$Self->{User}@":'')
			. $Self->{Host}
			. " $BaseCmd "
			;
    		for (my $Try = 1; $Try <= $Self->{'Tries'}; $Try++) {
    		    printf "\r\%5d   Gathering data from %s (%s) try %d\n", $$,$Self->{Host},$Self->{Desc},$Try if ($Self->Verbose);
    			eval("\@Data = `$Cmd`;");
    			last unless ($@ or $? != 0);
		}
		if (@Data == 0) {
		        warn "$Self->{FILE}:$Self->{LINE} Unable to gather data from $Self->{Host}: rc=$?, $@\n";
		        $Self->{StatusDetail} = "Unable to gather data";
		        return "Status=" . $Self->CHECK_FAIL;
		}
	}
	else {
		@Data = `$BaseCmd`;
	}

	my $Status = $Self->CHECK_OK;		# Assume no errors.
	my $Detail = '';
	my $Actual = $Data[0];
	if ( $Actual =~ /^\s*\d+\s*$/) {
		$Actual = 0+$Actual;
	}
	else {
		warn "$Self->{FILE}:$Self->{LINE} Non-numeric count received: $Actual\n";
		$Self->{StatusDetail} = "Invalid count received";
	        return "Status=" . $Self->CHECK_FAIL;
	}
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
		if ($Actual != $Target) {
			$Status = $Self->CHECK_FAIL;
			$Detail = "Actual $Actual != $Target";
		}
	}
			
	$Self->{StatusDetail}=$Detail;
	return "Status=" . $Status;
}
1;

=pod

=head1 Checkall::findcmd

=head2 Summary

findcmd executes a Linux/Unix find command, and returns the count of found items.

=head2 Syntax

  findcmd Target=0  Parms='/var/crash -type f' Desc='crash dumps'	# No dumps
  findcmd Target=<5 Parms='/var/spool/postfix -type f' Desc='mailq'	# Small mail queue
  findcmd Target=>3 Parms='/var/log -mtime -1' Desc='logs active'	# Recent logs.

=head2 Fields

findcmd is derived from CheckItem.pm.  It supports the same fields as CheckItem.  

The Target field is required, and defines the expected number of lines of output from findcmd.
It may be prefixed with a > symbol to indicate the specified value or larger; or with a < symbol
to indicate the specified value or less.

In addition, the following optional fields are supported:

The Parms field is required, and defines the parameters passed to the find command.  The find command will be executed as
  find $Parms | wc -l

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

