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
	my $POSIX = (!defined($Self->{Posix}) or $Self->{Posix})?'-P':' ';

	# If we're checking localhost, just run it now and evaluate the results.
	if ($Self->{Host} eq 'localhost') {
		# Get the data.
		@Data = `df -k $POSIX 2> /dev/null`;
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
	    		. $Self->{Host}
	    		. " df -k $POSIX 2> /dev/null"
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
	my($device,$total,$used,$free,$percent,$mount);
	# Create a hash of arrays keyed on mount point.  Each array is one df line-item.
	foreach (@Data) {
		next if (/^\s*Filesystem/);
		# Filesystem           1K-blocks      Used Available Use% Mounted on
		next if (/^\s*Filesystem\s/i);		# Heading
		# Data line.  Break it out into fields.
    	        printf REALSTDOUT "\r\%5d       Processing: %s", $$,$_
			if ($Self->Verbose);
		my($device,$total,$used,$free,$percent,$mount) = split(/\s+/);
    	        printf REALSTDOUT "\r\%5d       	device=%s, total=%s, used=%s, free=%s, percent=%s, mount=%s\n",
			$$,$device,$total,$used,$free,$percent,$mount
				if ($Self->Verbose);
		next if ($device eq 'none');		# Not a real file system (e.g. proc, sys, etc.).
		$percent=~s/%//;			# Strip the percent sign off the percent value.
		$HostHash{$Host}{$mount}{device}=$device;
		#$HostHash{$Host}{$mount}{total}=$total;	# Uncomment this when we find a need for it
		#$HostHash{$Host}{$mount}{used}=$used;		# Uncomment this when we find a need for it
		#$HostHash{$Host}{$mount}{free}=$free;		# Uncomment this when we find a need for it
		$HostHash{$Host}{$mount}{percent}=$percent;
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
			# Use everything except NFS mounts, which can be too many
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

