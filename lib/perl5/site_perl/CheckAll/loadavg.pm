#-------------------------------- loadavg Item -----------------------------------
#
# loadavg - check values found in /proc/loadavg
#

use strict;
no strict 'refs';
use warnings;
package loadavg;
use base 'CheckItem';
use fields qw(Port User Var1m Var5m Var15m Running Total Lastpid);

my %Attributes = (
	'Var1m' =>	'float,keep-operator',
	'Var5m' =>	'float,keep-operator',
	'Var15m' =>	'float,keep-operator',
	Running =>	'integer,keep-operator',
	Total =>	'integer,keep-operator',
	Lastpid =>	'integer,keep-operator',
);
my $ComparisonOperators = qr/=[<>]?|!=|<[=>]?|>[<=]?/;	# =, !=, <, <=, =<, >, >=, =>, <>, ><
my %Operators = (
        'Var1m' =>	$ComparisonOperators,
        'Var5m' =>	$ComparisonOperators,
        'Var15m' =>	$ComparisonOperators,
	Running =>	$ComparisonOperators,
	Total =>	$ComparisonOperators,
	Lastpid =>	$ComparisonOperators,
);

#================================= Data Accessors ===============================
sub SetOptions {
	my $Self = shift;
	my $OptionRef = shift;
	return $Self->SUPER::SetOptions($OptionRef,\%Operators,\%Attributes);
}

sub Check {

	# See if this item is OK.
	my $Self = shift;

	my $File = $Self->{'FILE'};
	my $Line = $Self->{'LINE'};

	printf "\n%5d %s Checking %s %s\n", $$, __PACKAGE__, $Self->Host, $Self->Desc
		if ($Self->{Verbose});
	# First, make sure we have the necessary config info.
	my $Errors = 0;
	if (! $Self->{Desc}) {
		$Self->{StatusDetail} = "Configuration error: Desc not specified";
		$Errors++;
	}
	if (	    ! $Self->{Var1m}
		and ! $Self->{Var5m}
		and ! $Self->{Var15m}
		and ! $Self->{Running}
		and ! $Self->{Total}
		and ! $Self->{Lastpid}
	) {
		$Self->{StatusDetail} = "Configuration error: no comparisons specified";
		$Errors++;
	}
	foreach (qw(Var1m Var5m Var15m)) {
		if (defined($Self->{$_}) and $Self->{$_} !~ /^[<=>]*\s*(\d+|\d+\.\d*|\d*\.\d+)$/) {
			$Self->{StatusDetail} =
				"Configuration error: invalid value("
				. $Self->{$_}
				. ") for "
				. substr($_,3);
			$Errors++;
		}
	}
	return "Status=" . $Self->CHECK_FAIL if ($Errors);

        # Run overall checks.  Any defined response means it set the status and we're done.
        my $Status = $Self->SUPER::Check($Self);
        return $Status if (defined($Status));

	# This host or remote?
	my @Data;
	if (defined($Self->{Host}) and $Self->{Host} ne 'localhost') {
		# On a remote host.
		my $Cmd = 
			'ssh '
			. '-o "NumberOfPasswordPrompts 0" '
			. ($Self->{Port}?"-oPort=$Self->{Port} ":'')
			. ($Self->{User}?"$Self->{User}@":'')
			. $Self->{Host} . ' '
			. qq["head -1 /proc/loadavg" 2>/dev/null ]
			. ' 2> /dev/null'
			;
		my $Data;
		for (my $Try = 1; $Try <= $Self->{'Tries'}; $Try++) {
			printf "\r\%5d   Gathering data from %s (%s) try %d\n", $$,$Self->{Host},$Self->{Desc},$Try if ($Self->Verbose);
			eval("\$Data = `$Cmd`;");
			$Status =$?;
			last unless ($@ or $Status != 0);
		}
		if ($Status) {
			# SSH failed.
			$Self->{StatusDetail} = "Unable to gather data($Status)";
			return "Status=" . $Self->CHECK_FAIL;
		}
		if ($Data) {
			$Data =~ s/^\s+//;
			@Data=split('\s+',$Data);
			$Self->{StatusDetail} = '';
		}
		else {
		       	$Self->{StatusDetail} = 'unable to read /proc/loadavg';
			return "Status=" . $Self->CHECK_FAIL;
		}
	}
	else {
		# On the local host.
		if (!(@Data=split'\s+',`head -1 /proc/loadavg 2> /dev/null`)) {
			$Self->{StatusDetail} = "Unable to read /proc/loadavg";
			return "Status=" . $Self->CHECK_FAIL;
		}
	}
	
        # Extract values
	my %Actual;
	$Actual{Var1m} = $Data[0];
	$Actual{Var5m} = $Data[1];
	$Actual{Var15m} = $Data[2];
	($Actual{Running},$Actual{Total}) = split('/',$Data[3]);
	$Actual{Lastpid} = $Data[4];

	# Check attributes.
	my @AttrList = qw(Var1m Var5m Var15m Running Total Lastpid);
	foreach (0..$#AttrList) {
		my $AttrName = $AttrList[$_];
		my $TargetValue;
		if (exists($Self->{$AttrName})) {
			my($Operator,$TargetValue) = ($Self->{$AttrName} =~ /^([!<=>]+) (.*)$/);
			my $ActualValue = $Actual{$AttrName};
			if (! eval qq<($Actual{"$AttrName"} $Operator $TargetValue);>) {
				$AttrName =~ s/^Var//;
				$Self->{StatusDetail} = "$AttrName($ActualValue) $Operator $TargetValue failed";
				return "Status=" . $Self->CHECK_FAIL
			}
		}
	}
	return "Status=" . $Self->CHECK_OK;
}


1;

=pod

=head1 Checkall::loadavg;

=head2 Summary

Check values from /proc/loadavg

=head2 Syntax

  loadavg Desc="descriptive text" attribute-oper-value

  # Example: 
  1) 1 minute load average must be <= 7
        loadavg  Desc="1m loadavg" 1m<=7
  2) 1 minute load average must be <= 7 and 5 minute average must be < = 4
        loadavg  Desc="1m loadavg<=7, 5m loadavg<=4" 1m<=7 5m<=4
  
=head2 Fields

loadavg is derived from CheckItem.pm.  It supports the same fields as CheckItem.  

The target field is not used.

=over 4

=item *

Host = name or IP address of a remote host.  The file system object on the remote
host will be checked.  SSH keys must be set up in advance to use remote hosts.
The default is to check the file system object on the local host.

=item *

Port = the ssh port to connect to.  The default is to not specify a port number, which 
typically results in using port 22.

=item *

User = the name of the remote user account.  The default is to not specify a remote user name
typically resulting in using the same name as the local user.

=item *

Attributes-oper-value

Zero or more of the following attributes may be compared to the specified value.  Comparison
operators are following this list.

=over 4

=item -

1m: 1 minute exponential moving average.  1m is known internally as Var1m.

=item -

5m: 5 minute exponential moving average.  5m is known internally as Var5m.

=item -

15m: 15 minute exponential moving average.  15m is known internally as Var15m.

=item -

Running: number of running processes

=item -

Total: number of total processes

=item -

Lastpid: the last PID assigned.

=back

=back

=head2 Comparison operators

The comparison operators for numeric and relative time fields of the file system attributes are =, <, <=, =>, >, and !=.
For convenience, =<, >=, ==, and <> are recognized synonyms for <=, =>, =, and != respectively.

=cut

