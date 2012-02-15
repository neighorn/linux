#-------------------------------- TCPPort Item -----------------------------------
#
# tcpport - check to see if a TCP Port is accessible.
#

use strict;
no strict 'refs';
use warnings;
package tcpport;
use base 'CheckItem';
use fields qw(_TargetArray);

#================================= Data Accessors ===============================
sub Target {

	# Retrieve or validate and save the target.
	my $Self = shift;

	if (@_) {
		# This is a set operation.
		my $Exit=1;		# Assume it all will go well.
		my($TargetList) = (@_);
		@{$Self->{'_TargetArray'}} = ();	# Initialize target array.
		foreach (split(/\s*,\s*/,$TargetList)) {
			s/^\s*//;	# Remove leading blanks.
			s/\s*$//;	# Remove trailing blanks.
			if (/(\S+):(\d{1,5})/) {
				my($Host,$Port) = ($1,$2);
				$Port += 0;	# Normalize port value.
				push @{$Self->{'_TargetArray'}},"$Host:$Port";
			}
			else {
				my $File = $Self->{'FILE'};
				my $Line = $Self->{'LINE'};
				warn "$File:$Line - invalid target $_ -- ignored.\n";
				$Exit=undef();	# Remeber we had an error.
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

	# See if this item is up.
	my $Self = shift;

	my $File = $Self->{'FILE'};
	my $Line = $Self->{'LINE'};

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

	# Spin off a child process to check the status of this item.
	my $pid = fork();
	if ($pid) {
		# We're the parent.  Remember the pid that goes with this line.
		return "PIDList=$pid"
	}
	else {
		# We're the child.  Go test this service.
		my $Desc = $Self->{'Desc'};
		print "\n$$ Checking $Desc\n" if ($main::opt_v);
		my $GroupOK=$Self->CHECK_FAIL;
		my $socket;
		foreach (@{$Self->_TargetArray}) {
			my($host,$port)=split(/:/);
			# try to connect.
			printf "\r\%5d   Checking %s:%d (%s)\n", $$,$host,$port,$Desc if ($main::opt_v);
			if ($socket=IO::Socket::INET->new(PeerAddr=>"$host:$port",Timeout=>20)) {
				# Connected OK.
				printf "\r%5d   %s:%d OK - %s\n", $$, $host, $port, $Desc if ($main::opt_v);
				close($socket);
				$GroupOK=$Self->CHECK_OK;	# One of this target group worked.
				last;			# Don't need to do any further checking.
			}
			else {
				# Connection is down.
				printf "\r%5d           %s DOWN: $!\n", $$,$Desc if ($main::opt_v);
				close($socket) if ($socket);
			}
		}
		exit($GroupOK);		# Tell the parent whether it was up or down.
	}
}
1;
