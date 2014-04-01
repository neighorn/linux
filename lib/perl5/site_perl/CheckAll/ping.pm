#-------------------------------- TCPPort Item -----------------------------------
#
# ping - check to see if a machine is ping-able.
#

use strict;
no strict 'refs';
use warnings;
package ping;
use base 'CheckItem';
use fields qw(_TargetArray);
use Net::Ping;

#================================= Data Accessors ===============================
sub Target {

        # Retrieve or validate and save the target.
        my $Self = shift;

        if (@_) {
                # This is a set operation.
                my $Exit=1;             # Assume it all will go well.
                my($TargetList) = (@_);
                @{$Self->{'_TargetArray'}} = ();        # Initialize target array.
                foreach (split(/\s*,\s*/,$TargetList)) {
                        s/^\s*//;       # Remove leading blanks.
                        s/\s*$//;       # Remove trailing blanks.
                        if (/(\S+)/) {
                                my $Host = $1;
                                push @{$Self->{'_TargetArray'}},"$Host";
                        }
                        else {
                                my $File = $Self->{'FILE'};
                                my $Line = $Self->{'LINE'};
                                warn "$File:$Line - invalid target $_ -- ignored.\n";
                                $Exit=undef();  # Remeber we had an error.
                        }
                }
                return $Exit;
        }
        else {
                # This is a read operation.
                return join(',',@{$Self->{'_TargetArray'}});
        }
}

#================================= Public Methods ===============================

sub Check {

	# See if this item is OK.
	my $Self = shift;

	my $File = $Self->{'FILE'};
	my $Line = $Self->{'LINE'};
	my $Desc = $Self->{'Desc'};

	# First, make sure we have the necessary info.
	my $Errors = 0;
	if (! $Self->{Desc}) {
		warn "$File:$Line: Desc not specified - item skipped.\n";
		$Self->{'StatusDetail'} = "Configuration error: Desc not specified";
		$Errors++;
	}
	if (! $Self->{_TargetArray}) {
		warn "$File:$Line: Target not specified - item skipped.\n";
		$Self->{'StatusDetail'} = "Configuration error: Target not specified";
		$Errors++;
	}
	return "Status=" . $Self->CHECK_FAIL if ($Errors);
	
	# Run overall checks.  Any defined response means set set the status and are done.
	my $Status = $Self->SUPER::Check($Self);
	return $Status if (defined($Status));

	# If we don't have a timeout change it to the main value.
	if (! $Self->{'Timeout'} ) {
		$Self->{'Timeout'} = $main::opt_w;
	}

	# Need a copy of STDOUT for consistency between forked and non-forked environment.
	open(REALSTDOUT,'>&STDOUT') || warn "Unable to duplicate STDOUT: $!";

	# If we're in single-stream mode, just test it ourselves rather than forking.
	if ($main::opt_S) {
		return "Status=" . _Check($Self,$File,$Line,$Desc);
	}

	# Spin off a child process to check the status of this item.
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
		my $GroupOK = _Check($Self,$File,$Line,$Desc);
		printf "%d/%d/%s\n", $$, $GroupOK, $Self->{'StatusDetail'}	# Tell the parent whether it was OK or FAILING.
			or warn("$$ $File:$Line: Error returning status: $!");
		close REALSTDOUT;
		close STDOUT;
		exit($GroupOK);		# Tell the parent whether it was OK or FAILING.
	}
}


#
# See if the port is up.
#
sub _Check {
	my($Self,$File,$Line,$Desc) = @_;
	my $GroupOK=$Self->CHECK_FAIL;
    	my $handle=Net::Ping->new('icmp',$Self->{Timeout},,,,$Self->{Timeout});

	# Loop through each host until we get a success.
	HOST: foreach my $host (@{$Self->_TargetArray}) {
		# try to connect.
		my $HostDone = 0;
		TRY: for (my $Try = 1; $Try <= $Self->{'Tries'}; $Try++) {
		    printf REALSTDOUT "\r\%5d   Checking %s (%s) try %d\n", $$,$host,$Desc,$Try if ($Self->Verbose);  
			my $Status = $handle->ping($host);
			if (!defined($Status)) {
				warn qq<Invalid address "$host"\n>;
				$Self->{'StatusDetail'}=qq<Invalid address "$host">;
				$HostDone=1;
		                printf REALSTDOUT "\r\%5d   %s (%s) try %d - Invalid address\n", $$,$host,$Desc,$Try if ($Self->Verbose);  
			}
			elsif ($Status == 1) {
				$GroupOK = $Self->CHECK_OK;
				$HostDone = 1;
		                printf REALSTDOUT "\r\%5d   %s (%s) try %d - success\n", $$,$host,$Desc,$Try if ($Self->Verbose);  
				$Self->{'StatusDetail'}='';
			}
			else {
		                printf REALSTDOUT "\r\%5d   %s (%s) try %d - failed\n", $$,$host,$Desc,$Try if ($Self->Verbose);  
				$Self->{'StatusDetail'}='no response';
			}
    			last TRY if ($HostDone);		# Don't need to try this host again
		}
		if ($GroupOK == $Self->CHECK_OK) {
			printf REALSTDOUT "\r%5d           %s OK\n", $$,$Desc if ($Self->Verbose);
			$Self->{'StatusDetail'}='';
			last HOST;					# Don't need to try other hosts.
		}
		else {
			# Service failed.
			printf REALSTDOUT "\r%5d           %s FAILING: %s\n", $$,$Desc,$Self->{'StatusDetail'} if ($Self->Verbose);
		}
	}
	$handle = undef();
	return($GroupOK);
}
=pod

=head1 Checkall::ping

=head2 Summary

Ping the specified host or list of hosts.

=head2 Syntax

  ping Target=www.example.com Desc="webserver"
  ping Target=www.example.com,www2.example.com Desc="webserver"

=head2 Fields

ping is derived from CheckItem.pm.  It supports any fields found in CheckItem.

The target field specifies a comma-separated list of items to check.  Each item consists of a
host name or IP address.  The ping is considered successful if any of the hosts is reachable.

=back

=cut
1;
