#-------------------------------- process Item -----------------------------------
#
# wanrouter - check status of wanrouter devices for Asterisk
#

use strict;
no strict 'refs';
use warnings;
package wanrouter;
use base 'CheckItem';
use fields qw(Port User Exclude);	

my %HostHash;	# Hash of lists of wanrouter data.

#================================= Data Accessors ===============================

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
	$Self->{Target} = 'ALL' unless ($Self->{Target});	# Set default.
	if (! $Self->{Desc}) {
		$Self->{StatusDetail} = "Configuration error: Desc not specified";
		$Errors++;
	}
	return "Status=" . $Self->CHECK_FAIL if ($Errors);

        # Run overall checks.  Any defined response means set set the status and are done.
        my $Status = $Self->SUPER::Check($Self);
        return $Status if (defined($Status));

	# See if we've gathered the process information for this host yet.
	$Self->{Host} = 'localhost' unless (defined($Self->{Host}));
	if (exists($HostHash{$Self->{Host}})) {
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
	if ($Self->{Host} eq 'localhost') {
		# Get the data.
		my $Cmd = "wanrouter status" . ($Self->{Verbose} < 3?' 2> /dev/null':'');
		@Data = `$Cmd`;
		$CmdStatus = $?;
	    	if ($CmdStatus != 0) {
		    $Self->{StatusDetail} = "Unable to gather data: $CmdStatus";
		    return "Status=" . $Self->CHECK_FAIL;
	    	}
		# Populate the hash for this host, in case there are subsequent checks
		# that need this data.
		_PopulateHostHash($Self,@Data);
		# Find out how we're doing.
		_Check($Self);
		printf REALSTDOUT "\r\%5d	Status=%d, Detail=%s\n", $$, $Self->{Status}, $Self->{StatusDetail}
			if ($Self->{Verbose});
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
                                if ($Self->{'Verbose'});
		
		my $Timeout = int($main::Options{waittime} / $Self->{Tries});
		my $Cmd = 
	    		'ssh '
	    		. '-o "NumberOfPasswordPrompts 0" '
	    		. "-o 'ConnectTimeOut $Timeout' "
	    		. ($Self->{Port}?"-oPort=$Self->{Port} ":'')
	    		. ($Self->{User}?"$Self->{User}@":'')
	    		. ($Self->{Verbose} > 4?'-vvv ':'')
	    		. $Self->{Host}
	    		. " wanrouter status "
			. ($Self->{Verbose} < 3?' 2> /dev/null':'')
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
		_PopulateHostHash($Self,@Data);
		_Check($Self);
		printf "%d/%d/%s\n", $$, $Self->{Status}, $Self->{StatusDetail}
			or warn("$$ $File:$Line: Error returning status: $!");
		printf REALSTDOUT "\r\%5d		Status=%d, Detail=%s\n", $$, $Self->{Status}, $Self->{StatusDetail}
			if ($Self->{Verbose});
                close REALSTDOUT;
                close STDOUT;
                exit($Self->{Status});         # Tell the parent whether it was OK or FAILING.
	}
}



#
# Populate Hash of data for this host.
#  This saves time when run on localhost, but is kind of a waste for remote hosts
#  since we're a child process and the hash goes away.  Haven't figured out how
#  I should address that yet.
#
sub _PopulateHostHash {

	my($Self,@Data) = @_;
	my $Host = $Self->{Host};	# Save some dereferencing.
	# Create a hash of arrays keyed on device name

# Sample response
#	Devices currently active:
#		wanpipe1
#	Wanpipe Config:
#	Device name | Protocol Map | Adapter  | IRQ | Slot/IO | If's | CLK | Baud rate |
#	wanpipe1    | N/A          | A101/1D/2/2D/4/4D/8/8D/16/16D| 16  | 4       | 1    | N/A | 0         |
#	Wanrouter Status:
#	Device name | Protocol | Station | Status        |
#	wanpipe1    | AFT TE1  | N/A     | Disconnected  |

	my $StatusStarted = 0;
	foreach (@Data) {
		printf REALSTDOUT "\r\%5d   Processing %s\n", $$, $_
			if ($Self->{Verbose});
		if (/^\s*Wanrouter Status:/) {
			$StatusStarted = 1;	# Now we start reading wanpipe lines.
		}
		elsif (/^\s*(wanpipe\d+)\s+\|[^|]*\|[^|]*\|\s*([^|]*)\s*\|/ and $StatusStarted) {
			my ($device,$status) = ($1,$2);
			$status =~ s/\s+$//;
			$HostHash{$Host}{$device}=$status;
			printf REALSTDOUT "\r\%5d     Found %s %s\n", $$, $device, $status
				if ($Self->{Verbose});
		}
	}
}



#
# _Check
#
sub _Check {
	my $Self = shift;
	my $Host = $Self->{Host};

	my @TargetList;
	if ($Self->{Target} =~ /^ALL$/i) {
		foreach my $Target (keys(%{$HostHash{$Host}})) {
			push @TargetList,$Target;
		}
	}
	else {
		@TargetList = (split(/\s*,\s*/,$Self->{Target}));
	}
	
	my $Status = $Self->CHECK_OK;		# Assume no errors.
	my $Detail = '';
	foreach my $Target (@TargetList) {
		next if (exists($Self->{Exclude}{$Target}));
		if (! exists($HostHash{$Host}{$Target})) {
				$Detail .= ", $Target not present";
				$Status = $Self->CHECK_FAIL;
				next;
		}
		printf REALSTDOUT "\r\%5d   Checking %s\n", $$, $Target
			if ($Self->{Verbose});
		my $status = $HostHash{$Host}{$Target};
		if ($status ne 'Connected') {
			$Detail .= ", $Target $status";
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

=head1 Checkall::wanrouter

=head2 Summary

Checks the status of devices as reported from "wanrouter status" (Asterisk/FreePBX interface).

=head2 Syntax

  wanrouter Target=ALL
  wanrouter Target=wanpipe1
  

=head2 Fields

wanrouter is derived from CheckItem.pm.  It supports the same fields as CheckItem.  

The target field specifies a comma-separated list of wanrouter interfaces to check, or ALL to check all mounted file systems.
If the target is not specified, ALL is assumed.

In addition, the following optional fields are supported:

=over 4

=item *

Exclude = a comma separated list of interfaces to ignore.  This
is primarily intended for use with a target of "ALL" to test all but a fixed
set of file systems.

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

