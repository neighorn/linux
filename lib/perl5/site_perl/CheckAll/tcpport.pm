#-------------------------------- TCPPort Item -----------------------------------
#
# tcpport - check to see if a TCP Port is accessible.
#

use strict;
no strict 'refs';
use warnings;
package tcpport;
use base 'CheckItem';
use fields qw(_TargetArray Send Expect Ssl Logfile);
use Fcntl;
use POSIX qw(strftime);

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
                        if (/(\S+):(\d{1,5})/) {
                                my($Host,$Port) = ($1,$2);
                                $Port += 0;     # Normalize port value.
                                push @{$Self->{'_TargetArray'}},"$Host:$Port";
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


sub Expect {

        # Retrieve or validate and save the target.
        my $Self = shift;

        if (@_) {
                # This is a set operation.
                my $ExpectDef = shift;
                eval "\$Self->{Expect} = qr${ExpectDef};";
                if ($@) {
                        print "$Self->{FILE}:$Self->{LINE}: " .
                                qq[Invalid target expression "$ExpectDef": $@\n];
                        return undef();
                }
                else {
                        return 1;
                }
        }
        else {
                # This is a read operation.
                return $Self->{Expect};
        }
}


sub Send {

        # Retrieve or validate and save the target.
        my $Self = shift;

        if (@_) {
                # This is a set operation.
                my $Send = shift;
		$Self->{Send} = $Self->TransEscapes($Send);
                return 1;
        }
        else {
                # This is a read operation.
                return $Self->{Send};
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
	if ($Self->{'Send'} and ! $Self->{'Expect'}) {
		warn "$File:$Line: Send specified without Expect - item skipped.\n";
		$Self->{'StatusDetail'} = "Configuration error: Expect not specified";
		$Errors++;
	}
	if (! $Self->{'Send'} and $Self->{'Expect'}) {
		warn "$File:$Line: Expect specified without Send - item skipped.\n";
		$Self->{'StatusDetail'} = "Configuration error: Send not specified";
		$Errors++;
	}
	return "Status=" . $Self->CHECK_FAIL if ($Errors);
	if ($Self->{'Ssl'} and !exists($INC{"IO/Socket/SSL.pm"})) {
               	eval qq[require IO::Socket::SSL;];
               	if ($@) {
			warn "$File:$Line: Unable to load IO::Socket:SSL: $@\n";
			$Self->{'StatusDetail'} = 'Configuration error: missing required module';
			$Errors++;
		}
	}
	
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
		return "Status=" . _CheckPort($Self,$File,$Line,$Desc);
	}

	# Spin off a child process to check the status of this item.
	my $CHECKFH;
	my $pid = open($CHECKFH,"-|");
	if ($pid) {
		# We're the parent.  Remember the pid that goes with this line.
		my @array = ("FHList",$pid,$CHECKFH);
		return (\@array);
	}
	else {
		# We're the child.  Recover our file handles, then test the service.
		printf REALSTDOUT "\n%5d %s Checking %s %s\n",
			$$, __PACKAGE__, $Self->Host, $Self->Target
				if ($Self->{'Verbose'});
		my $GroupOK = _CheckPort($Self,$File,$Line,$Desc);
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
sub _CheckPort {
	my($Self,$File,$Line,$Desc) = @_;
	my $GroupOK=$Self->CHECK_FAIL;
	my $socket;


	# Set up logging if requested.
	my $LOGFH;
	my $LogFile;
	if ($Self->{'Logfile'}) {
		$LogFile = strftime($Self->{Logfile},localtime());
		sysopen($LOGFH,$LogFile,O_CREAT | O_WRONLY) ||
			warn "$File:$Line: Unable to open logfile $LogFile: $!";
	}

	# Loop through each host until we get a success.
	HOST: foreach (@{$Self->_TargetArray}) {
		my($host,$port)=split(/:/);
		# try to connect.
		my $HostDone = 0;
		TRY: for (my $Try = 1; $Try <= $Self->{'Tries'}; $Try++) {
		    printf REALSTDOUT "\r\%5d   Checking %s:%d (%s) try %d\n", $$,$host,$port,$Desc,$Try if ($Self->Verbose);  
			if ($Self->{'Ssl'}) {
    				$socket=IO::Socket::SSL->new(
					PeerAddr=>"$host:$port",
					Timeout=>$Self->{'Timeout'},
					SSL_hostname=>$host,
				);
			}
			else {
    				$socket=IO::Socket::INET->new(
					PeerAddr=>"$host:$port",
					Timeout=>$Self->{'Timeout'}
				);
			}
    			printf REALSTDOUT "\r%5d   %s:%d Connected - %s\n", $$, $host, $port, $Desc if ($Self->Verbose);
			if ($socket) {
    				# Connected OK.  See if we're supposed to send a string.
				$HostDone = 1;		# Good or bad, we got an answer.
				if ($Self->{'Send'}) {
					# Looking for the right send/receive response.
					print $LOGFH "PID $$, $File:$Line, Host $host:port, Try $Try," .
						" Sending following:\n" .
						$Self->{'Send'} . "\n"
							if ($LOGFH);
					$socket->print($Self->{'Send'});
					my $response;
					$socket->sysread($response,4096);
					print $LOGFH "PID $$, $File:$Line, Host $host:port, Try $Try," .
						" Received following:\n" .
						$response . "\n"
							if ($LOGFH);

					if ($response =~ $Self->{'Expect'}) {
						printf REALSTDOUT "\r%5d  %s:%d Received %s - match\n", $$, $host, $port, $response
							if ($Self->Verbose);
						$GroupOK=$Self->CHECK_OK;
					}
					else {
						printf REALSTDOUT "\r%5d  %s:%d Received %s - no-match\n", $$, $host, $port, $response
							if ($Self->Verbose);
						$Self->{'StatusDetail'} = "Missing required response";
					}
				}
				else {
					# Just looking for a basic connection.
    					printf REALSTDOUT "\r%5d   %s:%d OK - %s\n", $$, $host, $port, $Desc if ($Self->Verbose);
    					$GroupOK=$Self->CHECK_OK;	# One of this target group worked.
				}
				close($socket);
			}
			else {
				$Self->{'StatusDetail'} = "Connect error: $!";
				printf REALSTDOUT "\r%5d  %s:%d Connect error: %s\n", $$, $host, $port, $!
					if ($Self->Verbose);
			}
    			last TRY if ($HostDone);		# Don't need to try this host again
		}
		if ($GroupOK == $Self->CHECK_OK) {
			printf REALSTDOUT "\r%5d           %s OK\n", $$,$Desc if ($Self->Verbose);
			$Self->{'StatusDetail'} = '';		# Delete any recovered errors.
			if ($LOGFH) {
				close $LOGFH;
				unlink($LogFile);
				$LOGFH = undef;
			}
			last HOST;					# Don't need to try other hosts.
		}
		else {
			# Service failed.
			printf REALSTDOUT "\r%5d           %s FAILING: %s\n", $$,$Desc,$Self->{'StatusDetail'} if ($Self->Verbose);
			close($socket) if ($socket);
		}
	}
	close $LOGFH if ($LOGFH);
	return($GroupOK);
}
=pod

=head1 Checkall::tcpport

=head2 Summary

tcpport checks to see whether it is possible to connect to a specific TCP port on a
designated host.  Multiple host/port combinations may be listed, in which case a
connection to any successful connection returns success.  Optionally, a string may
be sent and the results compared to a pattern.

=head2 Syntax

  process Target=localhost:22
  process Target=www.abc.com:80,www.def.com:80,www.ghi.com:443
  process Target=www.abc.com:80 Send='GET / HTTP/1.0\r\n\r\n' Expect="/Welcome to my site/"
  process Target=www.abc.com:443 SSL=1 Send='GET / HTTP/1.0\r\n\r\n' Expect="/Welcome to my site/"


=head2 Fields

tcpport is derived from CheckItem.pm.  It supports any fields found in CheckItem.

The target field specifies a comma-separated list of items to check.  Each item consists of a
host name or IP address, followed by a colon and the TCP port number.

Additionally, it supports the following optional fields:

=h3 Send

Send the following string if a connection is made.

=h3 Expect

Compare the response returned as a result of the Send field to this pattern.

=h3 SSL

If set to a true value (e.g. 1), use the SSL protocol.  The default is to use 
unencrypted traffic.

=back

=cut
1;
