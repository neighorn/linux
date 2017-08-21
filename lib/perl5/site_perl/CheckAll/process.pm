#-------------------------------- process Item -----------------------------------
#
# process - check to see if a process is present
#

use strict;
no strict 'refs';
use warnings;
package process;
use base 'CheckItem';
use fields qw(Port User);	

my %HostData;	# Hash of lists of process data.

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
	$Self->{StatusDetail} = '';

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
	return "Status=" . $Self->CHECK_FAIL if ($Errors);

        # Run overall checks.  Any defined response means set set the status and are done.
        my $Status = $Self->SUPER::Check($Self);
        return $Status if (defined($Status));

	# See if we've gathered the process information for this host yet.
	$Self->{Host} = 'localhost' unless (defined($Self->{Host}));
	my $Host = $Self->{Host};
	if (exists($HostData{$Host})) {
		# Already have gathered data on this host.
		_Check($Self);
		return "Status=" . $Self->{Status};
	}

	# Need a copy of STDOUT for consistency between forked and non-forked environment.
	open(REALSTDOUT,'>&STDOUT') || warn "Unable to duplicate STDOUT: $!";

	# Don't have any data on this host.  Go gather it.
	my @Data;
	my $CmdStatus;

	# If we're checking localhost, just run it now and evaluate the results.
	if ($Host eq 'localhost') {
		# Get the data.
		@Data = `ps -e -o cmd 2> /dev/null`;
		$CmdStatus = $?;
	    	if ($CmdStatus != 0) {
		    $Self->{StatusDetail} = "Unable to gather data: $CmdStatus";
		    return "Status=" . $Self->CHECK_FAIL;
	    	}
		@{$HostData{$Host}} = @Data;
		
		# Find out how we're doing.
		_Check($Self);
		printf REALSTDOUT "\r\%5d	Status=%d, Detail=%s\n", $$, $Self->{Status}, $Self->{StatusDetail}
			if ($Self->{Verbose} >= 2);
		return "Status=" . $Self->{Status}
	}

	# We're checking on a remote host.  Need to fork, as this could take some time.
        my $CHECKFH;
        my $pid = open($CHECKFH,"-|");
        if ($pid) {
                # We're the parent.  Remember the pid that goes with this line.
                my @array = ("FHList",$pid,$CHECKFH);
                return (\@array);
        }
        elsif (! defined($pid)) {
                warn "$File:$Line: fork failed: $!";
                $Self->{'StatusDetail'} = 'Operating system error: fork failed: $!';
                return "Status=" . $Self->CHECK_FAIL;
        }
        else {
                # We're the child.  Recover our file handles, then test the service.
                printf REALSTDOUT "\n%5d %s Checking %s %s\n",
                        $$, __PACKAGE__, $Self->Host, $Self->Target
                                if ($Self->{'Verbose'} >= 2);
		
		my $Timeout = int($main::Options{waittime} / $Self->{Tries});
		my $Cmd = 
	    		'ssh '
	    		. '-o "NumberOfPasswordPrompts 0" '
	    		. "-o 'ConnectTimeOut $Timeout' "
	    		. ($Self->{Port}?"-oPort=$Self->{Port} ":'')
	    		. ($Self->{User}?"$Self->{User}@":'')
	    		. $Host
	    		. " ps -e -o cmd"
			. ' 2> /dev/null '
	    		;

    		for (my $Try = 1; $Try <= $Self->{'Tries'}; $Try++) {
			printf REALSTDOUT "\r\%5d   Gathering data from %s (%s) try %d\n", $$,$Self->{Host},$Self->{Desc},$Try if ($Self->Verbose);
    			eval("\@Data = `$Cmd`;");
    			last unless ($@ or $? != 0);
			$CmdStatus = ($??"rc=$?":$@);
		}
		if (@Data == 0)
		{
			# No data came back.
			printf "%d/%d/%s\n", $$, $Self->CHECK_FAIL, "Unable to gather data: $CmdStatus"
				or warn("$$ $File:$Line: Error returning status: $!");
			close REALSTDOUT;
			close STDOUT;
			exit($Self->CHECK_FAIL);
		}
				
		# We have data.  Go run our checks.
		@{$HostData{$Host}} = @Data;
		_Check($Self);
		printf REALSTDOUT "\r\%5d		Status=%d, Detail=%s\n", $$, $Self->{Status}, $Self->{StatusDetail}
			if ($Self->{Verbose});
		printf "%d/%d/%s\n", $$, $Self->{Status}, $Self->{StatusDetail}
			or warn("$$ $File:$Line: Error returning status: $!");
                close REALSTDOUT;
                close STDOUT;
                exit($Self->{Status});         # Tell the parent whether it was OK or FAILING.
	}
}



#
# _Check
#
sub _Check {
	my $Self = shift;
	my $Host = $Self->{Host};
	my $Target = $Self->{Target};

        foreach (@{$HostData{$Host}}) {
        	chomp;
        	printf REALSTDOUT "\r%5d   Comparing %s to %s\n", $$, $Target, $_ if ($Self->{Verbose} >= 2);
		if ($_ =~ $Target) {
        		printf REALSTDOUT "\r%5d     Match found: %s\n", $$, $_ if ($Self->{Verbose} >= 2);
			$Self->{Status} = $Self->CHECK_OK;
        		return $Self->CHECK_OK;
		}
        };
       	printf REALSTDOUT "\r%5d   %s did not match any process\n", $$, $Target if ($Self->{Verbose} >= 2);
	$Self->{Status} = $Self->CHECK_FAIL;
       	return $Self->CHECK_FAIL;
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

