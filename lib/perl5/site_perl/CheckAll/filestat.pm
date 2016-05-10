#-------------------------------- filestat Item -----------------------------------
#
# filestat - check filesystem stat values.
#

use strict;
no strict 'refs';
use warnings;
package filestat;
use base 'CheckItem';
use fields qw(Port User Dev Ino Mode Nlink Uid Gid Rdev Size Atime Mtime Ctime Blksize Blocks Type Perm);
use Fcntl qw(:mode);

my %Attributes = (
	Dev =>		'integer,keep-operator',
	Ino =>		'integer,keep-operator',
	Mode =>		'string,keep-operator',
	Nlink =>	'integer,keep-operator',
	Uid =>		'integer,keep-operator',
	Gid =>		'integer,keep-operator',
	Rdev =>		'integer,keep-operator',
	Size =>		'integer,keep-operator',
	Absmtime =>	'integer,keep-operator',
	Absmtime =>	'integer,keep-operator',
	Absctime =>	'integer,keep-operator',
	Blksize =>	'integer,keep-operator',
	Blocks =>	'integer,keep-operator',
	Atime =>	'pasttime,keep-operator',
	Mtime =>	'pasttime,keep-operator',
	Ctime =>	'pasttime,keep-operator',
	Type =>		'string,keep-operator',
	Perm =>		'string,keep-operator',
);
my $ComparisonOperators = qr/=[<>]?|!=|<[=>]?|>[<=]?/;	# =, !=, <, <=, =<, >, >=, =>, <>, ><
my %Operators = (
	Dev =>		$ComparisonOperators,
	Ino =>		$ComparisonOperators,
#	Mode =>
	Nlink =>	$ComparisonOperators,
	Uid =>		$ComparisonOperators,
	Gid =>		$ComparisonOperators,
	Rdev =>		$ComparisonOperators,
	Size =>		$ComparisonOperators,
	Absatime =>	$ComparisonOperators,
	Absmtime =>	$ComparisonOperators,
	Absctime =>	$ComparisonOperators,
	Blksize =>	$ComparisonOperators,
	Blocks =>	$ComparisonOperators,
	Atime =>	$ComparisonOperators,
	Mtime =>	$ComparisonOperators,
	Ctime =>	$ComparisonOperators,
	Type =>		qr/!?=/,
	Perm =>		qr/!?=/,
);

#================================= Data Accessors ===============================
sub Target {

	# Retrieve or validate and save the target.
	my $Self = shift;

	if (@_) {
		# This is a set operation.
		my $TargetDef = shift;
		eval "\$Self->{Target} = '${TargetDef}';";
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

        # Run overall checks.  Any defined response means set the status and are done.
        my $Status = $Self->SUPER::Check($Self);
        return $Status if (defined($Status));

	# This host or remote?
	my @StatData;
	if (defined($Self->{Host}) and $Self->{Host} and $Self->{Host} ne 'localhost') {
		# On a remote host.
		my $Cmd = 
			'ssh '
			. '-o "NumberOfPasswordPrompts 0" '
			. ($Self->{Port}?"-oPort=$Self->{Port} ":'')
			. ($Self->{User}?"$Self->{User}@":'')
			. $Self->{Host} . ' '
			. qq["stat -c %d,%i,%f,%h,%u,%g,%t,%s,%X,%Y,%Z,%o,%b '$Self->{Target}' 2> /dev/null || exit 0"]
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
			@StatData=split(',',$Data);
			$Self->{StatusDetail} = "";
			if (!@StatData) {
				return "Status=" . $Self->CHECK_FAIL;
			}
		}
		else {
		       	$Self->{StatusDetail} = "not found";
			return "Status=" . $Self->CHECK_FAIL;
		}
	}
	else {
		# On the local host.
		if (!(@StatData=stat($Self->{Target}))) {
			$Self->{StatusDetail} = "Unable to find/read file system stat data";
			return "Status=" . $Self->CHECK_FAIL;
		}
	}
        # Calculate (elapsed) Atime, Mtime, Ctime from absolute values.
	foreach (8..10) {
		$StatData[$_+5] = time() - $StatData[$_];
	}

	# Check attributes.
	my @AttrList = qw(Dev Ino Mode Nlink Uid Gid Rdev Size Absatime Absmtime Absctime Blksize Blocks Atime Mtime Ctime Type Perm);
	$StatData[2] = hex($StatData[2]);	# Convert file mode to hex.
	$StatData[16] = sprintf('%o',S_IFMT($StatData[2]));	# Strip out file format (dir, file, socket, etc.) for easy ref.
	$StatData[17] = sprintf('%o',S_IMODE($StatData[2]));	# Strip out file mode (rwxr-xr-x, etc.) for easy ref.
	foreach (0..$#AttrList) {
		my $AttrName = $AttrList[$_];
		my $TargetValue;
		if (exists($Self->{$AttrName})) {
			my($Operator,$Value) = ($Self->{$AttrName} =~ /^([!<=>]+) (.*)$/);
			if ($AttrName =~ /^.time$/) {
				# Change provided time-offset to TOD.
				my $Normalized = NormalizeTime($Value);
				$TargetValue = $Normalized if ($Attributes{$AttrName} =~ /\bpasttime\b/);
			}
			elsif ($AttrName eq 'Uid' and $Value !~ /^\d+$/) {
				# Convert user name to uid.
				$TargetValue = getpwnam($Value);
				if (!defined($TargetValue)) {
					$Self->{StatusDetail} = "Unable to resolve $Value to a UID number";
					return "Status=" . $Self->CHECK_FAIL
				}
			}
			elsif ($AttrName eq 'Gid' and $Value !~ /^\d+$/) {
				# Convert group name to gid.
				$TargetValue = getgrnam($Value);
				if (!defined($TargetValue)) {
					$Self->{StatusDetail} = "Unable to resolve $Value to a GID number";
					return "Status=" . $Self->CHECK_FAIL
				}
			}
			else {
				$TargetValue = $Value;
			}
			
		        my $StatValue = $StatData[$_];
			printf "\n%5d %s    Checking Actual(%s) %s Target(%s)\n", $$, __PACKAGE__, $StatValue, $Operator, $TargetValue
				if ($Self->{Verbose} >= 2);
			if (! eval "($StatValue $Operator $TargetValue);") {
				$Self->{StatusDetail} = "$AttrName($StatValue) not $Operator $Value" . ($TargetValue eq $Value?'':"($TargetValue)");
				return "Status=" . $Self->CHECK_FAIL
			}
		}
	}
	return "Status=" . $Self->CHECK_OK;
}

sub NormalizeTime {
	
	my $Time = shift;
	my $Seconds;
	if ($Time =~ /^\s*([+-]?\d+)\s*([dhms])?\s*$/) {
		my($Value,$Unit) = ($1,$2);
		$Unit = 'd' unless ($Unit);
		if ($Unit eq 'd') {
			$Value *= 86400;
		}
		elsif ($Unit eq 'h') {
			$Value *= 3600;
		}
		elsif ($Unit eq 'm') {
			$Value *= 60;
		}
		return $Value;
	}
	else {
		return undef;
	}
}

1;

=pod

=head1 Checkall::filestat

=head2 Summary

filestat checks the attributes of file system objects (files, directories, pipes, etc.).

=head2 Syntax

  filestat Target=filename Desc="descriptive text" attribute-oper-value

  # Example: /var/log/messages must be updated in the last 5 minutes
  filestat Target="/var/log/messages" Desc="syslog" mtime<5m
  

=head2 Fields

filestat is derived from CheckItem.pm.  It supports the same fields as CheckItem.  

The target field specifies the file system object to check.  

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
operators are listed below.  If no
comparisons are supplied, the item is simply checked for existence.

=over 4

=item -

dev: The file system device number is compared to the provided value.  (See comparison operators below).

=item -

ino: The inode number is compared to the provided value.

=item -

mode: [Currently unsupported]

=item -

nlink: The number of hard links is compared to the provided value.

=item -

uid: The uid number is compared to the provided value.

=item -

gid: The gid number is compared to the provided value.

=item -

rdev: The device identifier (special files only) is compared to the provided value.

=item -

size: The total file size in bytes is compared to the specified value

=item -

absatime: The actual last accessed time (in seconds) is compared to the provided value.

=item -

absmtime: The actual last modification (in seconds) is compared to the provided value.

=item -

absctime: The actual last inode change (in seconds) is compared to the provided value.

=item -

atime: The elapsed time since the last access is compared to the provided value.

=item -

mtime: The elapsed time since the last modification is compared to the provided value.

=item -

ctime: The elapsed time since the last inode change is compared to the provided value.

=item -

blksize: The preferred block size for the file system I/O is compared to the provided value.

=item -

blocks: The actual number of blocks allocated is compared to the provided value.

=item -

type: The type of the entity (file, directory, link, etc.), as one of the follow values:

     140000 socket
     120000 symbolic link
     100000 regular file
      60000 block device
      40000 directory
      20000 character device
      10000 FIFO

=item -

perm: The permission bits, in octal (e.g. "644" for "rw-r--r--").

=back

=back

=head2 Comparison operators

The comparison operators for numeric and relative time fields of the file system attributes are =, <, <=, =>, >, and !=.
For convenience, =<, >=, ==, and <> are recognized synonyms for <=, =>, =, and != respectively.

=head2 Relative time values

Comparison values for atime, mtime, and ctime are provided as an integer, optionally followed by one of the units s, m, h, or d representing seconds, minutes,
hours, and days respectively.  If no unit is specified, the default unit is "s".

Examples:

    mtime<=2 	# Modified in the last two seconds
    mtime<=2s 	# Modified in the last two seconds
    atime>30d	# Last accessed more than 30 days ago.

=cut

