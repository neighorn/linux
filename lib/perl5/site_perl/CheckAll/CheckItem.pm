#----------------------------CheckItem base class-----------------------------
#
# CheckItem - basic monitoring item - base class.
#
package CheckItem;
$VERSION = 1.0;

use strict;
use warnings;
no strict 'refs';

use Text::ParseWords;
use POSIX qw(strftime);
use Exporter;
use Sys::Syslog;
use Net::Ping;

use constant CHECK_OK => 0;
use constant CHECK_FAIL => 8;
use constant CHECK_HIGHLIGHT => "\e[33;40;1m"; # Yellow FG, Black BG, Bright
use constant CHECK_RESET => "\e[0m";

use constant CHECK_STILL_OK => 0;		# We're up.
use constant CHECK_STILL_FAILING => 1;		# We're down, and we've been down.
use constant CHECK_NOW_OK => 2;			# We've just come up.
use constant CHECK_NOW_FAILING => 3;		# We've just come down.
use constant CHECK_NOT_TESTED => 4;		# We're outside of our time period.
use constant CHECK_PENDING => 5;		# We're down, but within our delay period.

our @ISA = ('Exporter');
our @EXPORT = qw(
	CHECK_OK CHECK_FAIL CHECK_HIGHLIGHT CHECK_RESET
	CHECK_STILL_OK CHECK_STILL_FAILING CHECK_NOW_OK CHECK_NOW_FAILING
	CHECK_NOT_TESTED
);

my %Attributes;
my %Operators;
my $x = $main::Options{renotify};	# suppress warning

my %IntegerFields = (
	Delayfirstnotification => 1,
	Renotifyinterval =>1,
);
my $PINGFH;				# Ping file handle, for ifping.

# Define fields.  Note that Autoload normalizes all field names to "first-upper rest lowercase".
# Names with multiple uppercase characters are not settable from the service files.
use fields (
	'FILE',				# File this definition came from
	'LINE',				# Line in file this definition came from
	'Name',				# Unique descriptor for status file - defaults to desc.
	'Delayfirstnotification',	# Delay the first notification this much time in minutes.
	'Desc',				# Description of service, for messages.
	'Host',				# Target host.
	'Iftime',			# Only check on this date/time pattern.
	'Ifping',			# Only check if this system is reachable.
	'Target',			# Target of check (host:port, process pattern, etc.).
	'Status',			# Current status (set by Check).
	'StatusDetail',			# Additional detail
	'FirstFail',			# When this was first detected failing
	'FirstNotification',		# When we first reported it down (for Delayfirstnotification).
	'PriorStatus',			# Its prior status.  Detects "Now failing" vs "Still failing".
	'NextNotification',		# The last time we told someone it was failing.
	'Onfail',			# Run this command when it first fails.
	'Onok',				# Run this command when it becomes OK again.
	'PIDComplete',			# PID ended of it's own accord (e.g. no timeout).
	'Renotifyinterval',		# How often to repeat failing notifications.
	'Timeout',			# Timeout: time in seconds to wait for conn.
	'Tries',			# How many times we attempt a TCP or SSH connection.
	'Verbose',			# Verbose.
);


# ================================ Public Methods ===============================
sub new{
        # Create a new item.

	# First, get the invocant.
	my $Invocant=shift;
	my $Class = ref($Invocant) || $Invocant;	# Object or class name.
	my $Self = fields::new($Class);			# Create object as anon hash.

	# Initialize some fields.  
	$Self->{FILE} = shift @_;			# Store the file name.
	$Self->{LINE} = shift @_;			# Store the line number.
	$Self->{FirstFail} = 0;				# Not failing, unless status file changes it.
	$Self->{Host} = 'localhost';			# Assume localhost.
	$Self->{NextNotification} = 0;			# Ditto.
	$Self->{Renotifyinterval} = $main::Options{renotify};	# Default renotify minutes.
	$Self->{Verbose} = $main::Options{verbose};		# Default verbose flag.
	$Self->{Tries} = 1;                # Assume only one TCP/SSH attempt.

	# Set options from the caller (from the file).
	$Self->SetOptions(\@_,\%Operators,\%Attributes);				# Run through our initialization code.
	return $Self;
}


sub Report {
        my($Self,$DescLen,$failonly,$StartTime) = @_;
	$DescLen = 40 unless ($DescLen);

	# Make sure we have values for everything.
	$Self->{Status} = CHECK_FAIL	unless (exists($Self->{Status}));
	$Self->{PriorStatus} = CHECK_OK unless (exists($Self->{PriorStatus}));
	$Self->{StatusDetail} = ''	unless (exists($Self->{StatusDetail}));
	$Self->{Desc} = '(No desc)'	unless (exists($Self->{Desc}));
	$Self->{FirstFail} = time()	unless (
		   $Self->{FirstFail} 
		or ($Self->{Status} eq CHECK_OK)
		or ($Self->{Status} eq CHECK_NOT_TESTED)
	);

	# Return our status + status change information.
	if ( 
		     ($Self->{PriorStatus} eq CHECK_OK)
		 and ($Self->{Status} eq CHECK_OK)
	) {
		# Was OK.  Still OK.
		printf "\t%-${DescLen}.${DescLen}s OK\n", $Self->{Desc} if (!$main::Options{verbose} && !$failonly);
		return CHECK_STILL_OK;
	}
	elsif (
		    ($Self->{Status} eq CHECK_FAIL)
		and $Self->{Delayfirstnotification}
		and ($Self->{FirstFail}+60*$Self->{Delayfirstnotification} > time())
	) {
		# Pending failure, but notice is delayed for an interval.
		$Self->{FirstFail} = $StartTime unless ($Self->{FirstFail});	# Remember when it first failed.
		my $text = $Self->{Desc}
			. " pending failure "
			. ($Self->{StatusDetail}?' -- ':'') . $Self->{StatusDetail};
		printf "\t\t%s%s%s\n",
			CHECK_HIGHLIGHT,
			$text,
			CHECK_RESET
				if (!$main::Options{quiet});
		syslog('WARNING','%s',$text)
			if ($^O !~ /MSWin/);
		return CHECK_PENDING;
	}
	elsif (
		    ($Self->{PriorStatus} eq CHECK_FAIL)
		and ($Self->{Status} eq CHECK_FAIL)
	) {
		# Was failing.  Still failing.
		my $Since;
		my $FirstFail = $Self->FirstFail;
		if (time() - $FirstFail < 84200) {
			$Since = strftime("%T",localtime($FirstFail));
		}
		else {
			$Since = strftime("%D %T",localtime($FirstFail));
		}
		my $text = $Self->{Desc}
			. " FAILING since "
			. $Since
			. ($Self->{StatusDetail}?' -- ':'') . $Self->{StatusDetail}
			;
		printf "\t\t%s%s%s\n",
			CHECK_HIGHLIGHT,
			$text,
			CHECK_RESET
				if (!$main::Options{quiet});
		syslog('WARNING','%s',$text)
			if ($^O !~ /MSWin/);
		return CHECK_STILL_FAILING;
	}
	elsif (
		    ($Self->{PriorStatus} eq CHECK_FAIL) 
		and ($Self->{Status} eq CHECK_OK)
	) {
		# Was failing.  Now OK.
		printf "\t%-${DescLen}.${DescLen}s OK\n", $Self->{Desc} if (!$main::Options{quiet} && !$failonly);
		return CHECK_NOW_OK;
	}
	elsif ($Self->{Status} eq CHECK_NOT_TESTED) {
		# Didn't test this one due to time constraints.
		printf "\t%-${DescLen}.${DescLen}s not tested\n", $Self->{Desc} if (!$main::Options{quiet} && !$failonly);
		return CHECK_NOT_TESTED;
	}
	else {
		# Wasn't failing before (or was pending), but it's failing now.
		my $text = $Self->{Desc}
			. " now FAILING "
			. ($Self->{StatusDetail}?' -- ':'') . $Self->{StatusDetail};
		printf "\t\t%s%s%s\n",
			CHECK_HIGHLIGHT,
			$text,
			CHECK_RESET
				if (!$main::Options{quiet});
		syslog('WARNING','%s',$text)
			if ($^O !~ /MSWin/);
		return CHECK_NOW_FAILING;
	}
}


sub SetOptions {
	#
	# Set options. Calling arguments: ($Self,\@Options,\%Oper,\%Attr)
	#	
        my $Self = shift;
        my $OptionRef = shift;		# Get the array of options from the service file record.
	my $HashRef = shift;		# Get the valid operators for each field.
	my %Oper = %$HashRef;		 
	$HashRef = shift;		# Get the any attributes for each field.
	my %Attr = %$HashRef;

	# Assign any values they passed on init/new.
	foreach my $InitItem (@$OptionRef) {
		foreach my $Parm (shellwords($InitItem)) {
			my($Field,$Rest) = ($Parm =~ /^([A-Za-z0-9_]+)(.*)\s*$/);
			$Field = ucfirst(lc($Field));	# Normalize case.
			# Support old field names.
			if ($Field eq 'Ondown') {
				$Field = 'Onfail';
			}
			elsif ($Field eq 'OnUp') {
				$Field = 'Onok';
			}
			
			# Fix up field names that don't match valid variable names, 
			# like loadavg's "1m", "5m", "15m".
			$Field = "Var$Field" if ("$Field" !~ /^[A-Z]/);  # Hack for loadavg 1m, etc.

			# Extract the operator.
			my $OperRegEx = (exists($Oper{$Field})?$Oper{$Field}:qr/=/o);
			my($Operator,$Value) = ($Rest =~ /^($OperRegEx)(.*)$/);
			if (!defined($Operator)) {
				warn "$Self->{FILE}:$Self->{LINE}: Invalid operator specified for $Field -- ignored.\n";
				next;
			}
			# Normalize some operators.
			if ($Operator eq '=<') {
				$Operator = '<=';
			}
			elsif ($Operator eq '=>') {
				$Operator = '>=';
			}
			elsif ($Operator eq '=' ) {
				$Operator = '==';
			}
			elsif ($Operator =~ /^(<>|><)$/) {
				$Operator = '!=';
			}
			if (exists($Attr{$Field}) and $Attr{$Field} =~ /\bkeep-operator\b/) {
				$Operator .= ' ';	# Separate operator from value with space.
			}
			else {
				$Operator = '';		# Delete operator so we prepend nothing.
			}
			
			$Value = '' unless (defined($Value));
			eval "\$Self->$Field(\${Operator} . \$Value);";
			if ($@) {
				warn "$Self->{FILE}:$Self->{LINE}: Unable to set $Field: $@\n";
			}
		}
	}
	return 1;
}


sub Check {
	#
	# Perform common checks (e.g. time/date restrictions).
	#
	#	Returns:
	#		CHECK_FAIL - check failed (e.g. test parameters invalid)
	#		CHECK_NOT_TESTED - outside of time range for testing
	#		undef - no failures detected, continue module-specific tests.
	#	
        my $Self = shift;

        my $File = $Self->{'FILE'};
        my $Line = $Self->{'LINE'};
	my $Status;

	if ($Self->{Iftime} and (! $main::Options{ignoretimes}) ) {
		$Status = CheckTimePattern($Self, $File, $Line, $main::StartTime);
		return "Status=$Status" if ($Status);
	}
	if ($Self->{Ifping}) {
		$PINGFH=Net::Ping->new('tcp',3) unless ($PINGFH); # Get a handle if necessary.
		$Self->{Ifping} = $Self->{Host} if ($Self->{Ifping} eq '1' and $Self->{Host});
		return "Status=" . CHECK_NOT_TESTED
			unless $PINGFH->ping($Self->{Ifping});
	}

	return undef;
}



sub CheckTimePattern {
	my($Self, $File, $Line, $StartTime) = @_;
	my($TimeFormat,$Pattern) = split(',',$Self->{Iftime},2);
	my $Regex;
	eval "\$Regex = qr$Pattern;";
	if ($@) {
		# Pattern is invalid.
		print "$File:Line: " .
			qq[Invalid pattern "$Pattern": $@\n];
		$Self->{Status} = CHECK_FAIL;
		$Self->{StatusDetail} = "Configuration error";
		return CHECK_FAIL;		# Config error
	}
	my $Time = strftime($TimeFormat,localtime($StartTime));
	if ($Time =~ $Regex) {
		# We're within the specified time.  Continue the test.
		print "$File:$Line CheckTimePattern: $Time matches $Regex\n"
				if ($Self->{'Verbose'});
		return undef;
	}
	else {
		# We're outside the specified time.  Skip the test.
		$Self->{Status} = CHECK_NOT_TESTED;
		print "$File:$Line CheckTimePattern: $Time does not match $Regex\n"
				if ($Self->{'Verbose'});
		return CHECK_NOT_TESTED;	# Skip test.
	}
}


# ================================ Data Accessors ===============================
#
# AUTOLOAD - Generic attribute creation routine.  This is used if 
#	someone tries to set an attribute that we don't have a 
#	specific handler for.
#
sub AUTOLOAD {
	# Set an option.
	
	return if our $AUTOLOAD =~ /::DESTROY$/;
	my $Self = shift;
	my $Name='AUTOLOAD';
	my($Package,$Attribute) = ($AUTOLOAD =~ /^(\S+)::(\S+)$/);
	if ( !$^V or $^V lt v5.9.0 ) {
		# Can validate using the pseudo-hash on older Perls.
		die qq[$Self->{FILE}:$Self->{LINE}: "$Attribute" is an invalid attribute.\n]
			unless (exists($Self->[0]{$Attribute}));
	}
		

	return $Self->{$Attribute} unless (@_);	# No value supplied.  They're reading.

	my $Value = shift;
	$Value =~ s/^\s+//;		# Strip leading blanks
	$Value =~ s/\s+$//;		# Strip trailing blanks
	$Value =~ s/(['"])(.*)\1$/$2/;	# Strip quotes.
	$Value += 0 if ($Value =~ /^[+-]?([0-9]+|[0-9]+\.[0-9]*|[0-9]*\.[0-9]+)$/);

	if ($IntegerFields{$Attribute} and $Value !~ /^\d+$/) {
		die qq[$Attribute has an invalid value "$Value".\n];
	}
	# Can't validate attribute in advance on later Perls (>= 5.9).  Just try, and Perl
	# will block it if it's invalid.
	eval "\$Self->{$Attribute} = \$Value;";
	if ($@ =~ /Attempt to access disallowed key/) {
		die qq["$Attribute" is an invalid attribute.\n];
	}
	elsif ($@) {
		die qq[$@\n];
	}
	
	return $Value;
}


# =================================== Utility routines ==================================
#
# TransEscapes - translate \n to newline, etc.  Supports octal, hex, upper/lowercase, too.
#
sub TransEscapes {

	my($Self,$data) = @_;
        $data=~s/\\(
            (?:[arnt'"\\]) |               # Single char escapes
            (?:[ul].) |                    # uc or lc next char
            (?:x[0-9a-fA-F]{2}) |          # 2 digit hex escape
            (?:x\{[0-9a-fA-F]+\}) |        # more than 2 digit hex
            (?:\d{2,3}) |                  # octal
            (?:N\{U\+[0-9a-fA-F]{2,4}\})   # unicode by hex
        )/"qq|\\$1|"/geex;  
    return $data;
}

1;

=pod

=head1 Checkall::CheckItem

=head2 Summary

CheckItem is used by the /usr/local/sbin/checkall script.  It is a base class for other check routines.
As such it provides only basic field definitions and house-keeping code, and cannot be invoked
directly.

=head2 Syntax

The standard syntax is:

  modname Field=value {Field2=value2 ...}

Where:

=over 4

=item *

modname is the name of the derived module (tcpport, process, heading, possibly more).  modname
is not case sensitive.

=item *

Field is the name of a standard field (shown below) or one added by the derived module. The field name is
not case sensitive.

=item *

Value is the value for the specified field.  The values are case sensitive.  As white-space is used
to separate Field=Value items, values containing white space must either have the white space escaped
using \, or be quoted.  Similarly, backslashes that are intended as part of the value must also
either be quoted or escaped (i.e. \\).

=back

The module name must begin in column 1.  Lines beginning with white space are treated as continuation lines.

Blank lines, or lines beginning with # are ignored.

=head2 Fields

The following standard fields are provided to all derived modules, though some modules may ignore some 
fields:

=over 4

=item *

B<Target>:  This is target item to check.  Interpretation of the target is left to the derived module.

=item *

B<Desc>: This is the description of this item, used when reporting the status of the item.  The variable
"%C" will be replaced with the value of Host, if specified and not "localhost", or else the name of
the computer running checkall.

=item *

B<OnFail>: A command to execute when the target is first discovered failing.

=item *

B<OnDown>: Deprecated synonym for OnFail

=item *

B<OnOK>: A command to execute when a previously failing target is first discovered OK.

=item *

B<OnUp>: Deprecated synonym for OnOK

=item *

B<Verbose>:  A diagnostic flag.  The derived process should provide additional divided messages
when this is non-zero.

=item *

B<Name>: A unique identification value used internally to track status across runs.  This is normally left to default, in which case it uses "modname=targetvalue".  The only known reason to set this would
be if two different checkall service lists monitored the same service with different target values
(e.g. "localhost:80" in one list, and "127.0.0.1:80" in another), couldn't be changed to a common target, 
but still needed to be tracked as a single service.

=back

The following additional fields are used internally by the checkall script and various
derived items, but cannot be set by a checkall service file.

=over 4

=item *

B<FILE>: The name of the service list file that defined this item.

=item *

B<LINE>: The line number of the service list file that defined this item.

=item *

B<Delayfirstnotification>: Time in minutes before the first notification should be sent.  If the
error clears during that interval, no notification is sent.  This can be used to suppress
transient errors, at the risk of delaying notification.

=item *

B<FirstFail>: The time at which the item was first detected failing.

=item *

B<PriorNotification>: The time at which the most recent alert was sent about this item being
failing.  This is only applicable if notifications were requested with the checkall -P option.

=item *

B<PriorStatus>: The previous status of this item (defaults to "OK" for new items).  This is used to
determine if an item is "now failing" (newly failing), "still failing", "now OK", or "still OK".

=item *

B<Renotifyinterval>: The time in minutes after which another notification should be sent.  If not set,
this defaults to the current value of -R.

=item *

B<Status>: The status of the service (OK or failing), as set by the Check method.

=item *

B<StatusDetail>: Additional text information about the status.  This is typically used to indicate that
a service was marked as "FAILING" for unusual reasons, such as a configuration error.

=item *

B<Timeout>: The time in seconds to wait for this check to complete.  The effective value for this
is the greater of the specified value (if specified), or the main program -w value.  This value
is not meaningful for all types of checks and is primarily used to with network connections.

=item *

B<Tries>: The number of times to try a TCP connection or SSH connection (for remote commands)
before considering it a failure.  

=item *

B<Iftime>: Restricts when this test is run.  The parameter is
formatted as "format,pattern".  "format" is a time format that is interpreted by strftime(3)
using the current local time.  These are the same format symbols as used by date(1).  
"pattern" is a Perl
regular expression.  If the results of strftime match the pattern, the test is executed. 
Otherwise, it is marked as "not tested".

B<Examples>:

  Iftime=%d,/01/			# Test only on the first day of the month
  Iftime=%u,[1-5]			# Test only on Monday-Friday
  Iftime=%m-%d,/(01|04|07|10)-01/	# Test only on Jan 01, Apr 01, Sep 01, Oct 01
  Iftime=%H-%u,/(09|1[0-7])-[1-5]/	# Test 9AM-5:59PM (09:00-17:59), Monday-Friday.

=item *

B<Ifping>: Restricts this test to only run if the host is up.  The parameter
is an IP address, DNS name, or the "1" to use the the value of the Host parameter.
The test will be skipped if the host is not pingable.

=back

=head2 Methods

CheckItem provides the following methods:

=over 4

=item *

B<new>: create a new item and set initial values.  Derived items don't typically need to override this.  It
calls the SetOptions method, passing any parameters it receives.  Derived items may override SetOptions if they need special set-up.

=item *

B<SetOptions>: set object values.  Typically this is passed a (possibly empty) array of "Field=Value" strings
that came from a service file or internal logic.  SetOptions validates the field names, and stores
the values.  Derived items sometimes override this in order to provide custome set-up.

=item *

B<Report>: Generates a single-line report of the status of this item in a standard format.  It is rare
for a derived class to replace this, with the exception of "heading", which has different formatting 
requirements.

=cut
