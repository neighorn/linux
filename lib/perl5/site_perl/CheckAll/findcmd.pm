#-------------------------------- process Item -----------------------------------
#
# findcmd - run a find command and count the results.
#

use strict;
no strict 'refs';
use warnings;
package findcmd;
use base 'CheckItem';
use fields qw(Port User Parms Verifyexist Listfiles);
my %Attributes = (
        Target =>      'integer,keep-operator',
        Listfiles =>   'integer',
);
my $ComparisonOperators = qr/=[<>]?|!=|<[=>]?|>[<=]?/;  # =, ==, <, <=, =<, >, >=, =>, !=, <>, ><
my %Operators = (
        Target =>      $ComparisonOperators,
);


#================================= Data Accessors ===============================
sub Target {

	# Retrieve or validate and save the target.
	my $Self = shift;

	if (@_) {
		# This is a set operation.
		my $Target = shift;
		if (defined($Target) and $Target =~ /^[<>=!]*\s*\d+$/ ) {
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
	my $Target = $Self->{'Target'};
	printf "\n%5d %s Checking %s %s\n", $$, __PACKAGE__, $Self->Host, $Self->Parms
		if ($Self->{Verbose});
		
	# First, make sure we have the necessary config info.
	my $Errors = 0;
	$Self->{Desc} = 'findcmd' unless ($Self->{Desc});
	if (!exists($Self->{Target}) or !defined($Self->{Target})) {
		$Self->{StatusDetail} = "Configuration error: Target not specified";
		$Errors++;
	}
	if (! $Self->{Parms}) {
		$Self->{StatusDetail} = "Configuration error: Parms not specified";
		$Errors++;
	}
	if (exists($Self->{Listfiles})) {
		if ($Self->{Listfiles} !~ /^\d+$/) {
			$Self->{StatusDetail} = "Configuration error: ListFiles is not numeric";
			$Errors++;
		}
	}
	return "Status=" . $Self->CHECK_FAIL if ($Errors);


        # Run overall checks.  Any defined response means set set the status and are done.
        my $Status = $Self->SUPER::Check($Self);
	printf "\n%5d %s\tSUPER returned status %d\n", $$, __PACKAGE__, $Status
		if ($Self->{Verbose} >= 3 && $Status);
        return $Status if (defined($Status));

	if ($Self->{Verifyexist}) {
		my $Found;
		for (my $Count=1;$Count<=$Self->{Tries};$Count++) {
			last if (defined($Found = glob($Self->{Verifyexist})));
			printf "\n%5d %s\tVerifyExist failed on try %d\n", $$, __PACKAGE__, $Count
				if ($Self->{Verbose} >= 3);
			sleep(15) unless ($Count >= $Self->{Tries});
		}
		if (! defined($Found)) {
			$Self->{StatusDetail} = "$Self->{Verifyexist} not present";
			return "Status=" . $Self->CHECK_FAIL;
		}
	}
	printf "\n%5d %s\tVerifyExist OK\n", $$, __PACKAGE__
		if ($Self->{Verbose} >= 3);

	my @Data;
	my $BaseCmd = "find " . $Self->{Parms} . " ";
	if ($Self->{Host} and $Self->{Host} ne "localhost") {
		# On a remote host.
		my $Cmd = 
			'ssh '
			. '-o "NumberOfPasswordPrompts 0" '
			. ($Self->{Port}?"-oPort=$Self->{Port} ":'')
			. ($Self->{User}?"$Self->{User}@":'')
			. $Self->{Host}
			. " $BaseCmd "
			. ' 2> /dev/null '
			;
    		for (my $Try = 1; $Try <= $Self->{'Tries'}; $Try++) {
    		    printf "\r\%5d   Gathering data from %s (%s) try %d\n", $$,$Self->{Host},$Self->{Desc},$Try if ($Self->Verbose);
    			eval("\@Data = `$Cmd`;");
    			last unless ($@ or $? != 0);
		}
		if (@Data == 0) {
		        $Self->{StatusDetail} = "Unable to gather data";
		        return "Status=" . $Self->CHECK_FAIL;
		}
	}
	else {
		@Data = `$BaseCmd 2> /dev/null`;
	}
	printf "\n%5d %s\t\@Data = %s\n", $$, __PACKAGE__, join(', ',@Data)
		if ($Self->{Verbose} >= 3);

	$Status = $Self->CHECK_OK;		# Assume no errors.
	my $Detail = '';
	my $Actual = @Data;
	my($Operator,$TargetValue) = ($Target =~ /^([!<=>]+) (.*)$/);
	$Operator = '==' if ($Operator eq '=');
	$Operator = '!=' if ($Operator eq '<>' or $Operator eq '><');
	$Operator = '<=' if ($Operator eq '=<');
	$Operator = '>=' if ($Operator eq '=>');
	if (! eval "($Actual $Operator $TargetValue);") {
		my $LastIndex = $Self->{Listfiles};
		if ($LastIndex) {
			# They want the files found.
			$LastIndex = ($LastIndex > @Data? @Data - 1 : $LastIndex - 1);
			chomp @Data;
			$Self->{StatusDetail} = "Found: " 
				. join(', ',@Data[0..$LastIndex]);
		}
		else {
			# They just need the basic count.
			$Self->{StatusDetail} = qq<"$Actual $Operator $TargetValue" failed>;
		}
		return "Status=" . $Self->CHECK_FAIL
	}

	printf "\n%5d %s\tExiting with Status = %d and Detail = %s\n", $$, __PACKAGE__, $Status, ($Detail?$Detail:'""')
		if ($Self->{Verbose} >= 3);
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

The Parms field is required, and defines the parameters passed to the find command.  The find command will be executed as
  find $Parms | wc -l

The Target field is required, and defines the expected number of lines of output from findcmd.
The Target syntax is "TargetOperatorValue", where:
    Target is the keyword "Target"
    Operator is one of <,<=,=<,=,==,>,>=,=>,<>, or !=
    Value is an integer

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

=item *

VerifyExist = the optional name of a directory or file that must exist before running the
specified find command.  If the specified item doesn't exist, the module will sleep 15
seconds and try again "Tries" times (typically 3).  This is primarily used for auto-mounted
directories that may not mount instantly.

=item *
ListFiles = X.  Zero is the default.  If a mismatch is found and X > 0 ,
	then the standard detail message is replaced with a list of the first X files 
	found.
=back

=head2 Notes

=over 4

=item *

(none)

=back

=cut

