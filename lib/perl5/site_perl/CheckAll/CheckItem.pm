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

use constant CHECK_OK => 0;
use constant CHECK_FAIL => 8;
use constant CHECK_HIGHLIGHT => "\e[33;40;1m"; # Yellow FG, Black BG, Bright
use constant CHECK_RESET => "\e[0m";

use constant CHECK_STILL_OK => 0;
use constant CHECK_STILL_FAILING => 1;
use constant CHECK_NOW_OK => 2;
use constant CHECK_NOW_FAILING => 3;

our @ISA = ('Exporter');
our @EXPORT = qw(
	CHECK_OK CHECK_FAIL CHECK_HIGHLIGHT CHECK_RESET
	CHECK_STILL_OK CHECK_STILL_FAILING CHECK_NOW_OK CHECK_NOW_FAILING
);

my %Attributes;
my %Operators;
my $x = $main::opt_R;	# suppress warning

my %IntegerFields = (
	Delayfirstnotification => 1,
	Renotifyinterval =>1,
);

# Define fields.  Note that Autoload normalizes all field names to "first-upper rest lowercase".
# Names with multiple uppercase characters are not settable from the service files.
use fields (
	'FILE',				# File this definition came from
	'LINE',				# Line in file this definition came from
	'Name',				# Unique descriptor for status file - defaults to desc.
	'Delayfirstnotification',	# Delay the first notification this much time.
	'Desc',				# Description of service, for messages.
	'Target',			# Target of check (host:port, process pattern, etc.).
	'Status',			# Current status (set by Check).
	'StatusDetail',			# Additional detail
	'FirstFail',			# When this was first detected failing
	'FirstNotification',		# When we first reported it down (for DelayFirstNotification).
	'PriorStatus',			# Its prior status.  Detects "Now failing" vs "Still failing".
	'NextNotification',		# The last time we told someone it was failing.
	'Onfail',			# Run this command when it first fails.
	'Onok',				# Run this command when it becomes OK again.
	'Renotifyinterval',		# How often to repeat failing notifications.
	'Timeout',			# Timeout: time in seconds to wait for conn.
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
	$Self->{NextNotification} = 0;			# Ditto.
	$Self->{Renotifyinterval} = $main::opt_R;	# Default renotify minutes.
	$Self->{Verbose} = $main::opt_v;		# Default verbose flag.

	# Set options from the caller (from the file).
	$Self->SetOptions(\@_,\%Operators,\%Attributes);				# Run through our initialization code.
	return $Self;
}


sub Report {
        my($Self,$DescLen) = @_;
	$DescLen = 40 unless ($DescLen);

	# Make sure we have values for everything.
	$Self->{Status} = CHECK_FAIL	unless (exists($Self->{Status}));
	$Self->{PriorStatus} = CHECK_OK unless (exists($Self->{PriorStatus}));
	$Self->{StatusDetail} = ''	unless (exists($Self->{StatusDetail}));
	$Self->{Desc} = '(No desc)'	unless (exists($Self->{Desc}));

	# Return our status + status change information.
	if ($Self->{Status} eq CHECK_OK and $Self->{PriorStatus} eq CHECK_OK) {
		printf "\t%-${DescLen}.${DescLen}s OK\n", $Self->{Desc} if (!$main::opt_q);
		return CHECK_STILL_OK;
	}
	elsif ($Self->{Status} eq CHECK_FAIL and $Self->{PriorStatus} eq CHECK_FAIL) {
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
				if (!$main::opt_q);
		syslog('WARNING','%s',$text)
			if ($^O !~ /MSWin/);
		return CHECK_STILL_FAILING;
	}
	elsif ($Self->{Status} eq CHECK_OK and $Self->{PriorStatus} eq CHECK_FAIL) {
		printf "\t%-${DescLen}.${DescLen}s OK\n", $Self->{Desc} if (!$main::opt_q);
		return CHECK_NOW_OK;
	}
	else {
		my $text = $Self->{Desc}
			. " now FAILING "
			. ($Self->{StatusDetail}?' -- ':'') . $Self->{StatusDetail};
		printf "\t\t%s%s%s\n",
			CHECK_HIGHLIGHT,
			$text,
			CHECK_RESET
				if (!$main::opt_q);
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
	if ( $ lt 5.9.0 ) {
		# Can validate using the pseudo-hash on older Perls.
		die qq[$Self->{FILE}:$Self->{LINE}: "$Attribute" is an invalid attribute.\n]
			unless (exists($Self->{$Attribute}));
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
to separate Field=Value items, values containing whitei space must either have the white space escaped
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

Target:  This is target item to check.  Interpretation of the target is left to the derived module.

=item *

Desc: This is the description of this item, used when reporting the status of the item.

=item *

OnFail: A command to execute when the target is first discovered failing.

=item *

OnDown: Deprecated synonym for OnFail

=item *

OnOK: A command to execute when a previously failing target is first discovered OK.

=item *

OnUp: Deprecated synonym for OnOK

=item *

Verbose:  A diagnostic flag.  The derived process should provide additional divided messages
when this is non-zero.

=item *

Name: A unique identification value used internally to track status across runs.  This is normally left to default, in which case it uses "modname=targetvalue".  The only known reason to set this would
be if two different checkall service lists monitored the same service with different target values
(e.g. "localhost:80" in one list, and "127.0.0.1:80" in another), couldn't be changed to a common target, 
but still needed to be tracked as a single service.

=back

The following additional fields are used internally by the checkall script and various
derived items, but cannot be set by a checkall service file.

=over 4

=item *

FILE: The name of the service list file that defined this item.

=item *

LINE: The line number of the service list file that defined this item.

=item *

Delayfirstnotification: Time in minutes before the first notification should be sent.  If the
error clears during that interval, no notification is sent.  This can be used to suppress
transient errors, at the risk of delaying notification.

=item *

FirstFail: The time at which the item was first detected failing.

=item *

PriorNotification: The time at which the most recent alert was sent about this item being
failing.  This is only applicable if notifications were requested with the checkall -P option.

=item *

PriorStatus: The previous status of this item (defaults to "OK" for new items).  This is used to
determine if an item is "now failing" (newly failing), "still failing", "now OK", or "still OK".

=item *

Renotifyinterval: The time in minutes after which another notification should be sent.  If not set,
this defaults to the current value of -R.

=item *

Status: The status of the service (OK or failing), as set by the Check method.

=item *

StatusDetail: Additional text information about the status.  This is typically used to indicate that
a service was marked as "FAILING" for unusual reasons, such as a configuration error.

=item *

Timeout: The time in seconds to wait for this check to complete.  The effective value for this
is the greater of the specified value (if specified), or the main program -w value.  This value
is not meaningful for all types of checks and is primarily used to with network connections.

=back

=head2 Methods

CheckItem provides the following methods:

=over 4

=item *

new: create a new item and set initial values.  Derived items don't typically need to override this.  It
calls the SetOptions method, passing any parameters it receives.  Derived items may override SetOptions if they need special set-up.

=item *

SetOptions: set object values.  Typically this is passed a (possibly empty) array of "Field=Value" strings
that came from a service file or internal logic.  SetOptions validates the field names, and stores
the values.  Derived items sometimes override this in order to provide custome set-up.

=item *

Report: Generates a single-line report of the status of this item in a standard format.  It is rare
for a derived class to replace this, with the exception of "heading", which has different formatting 
requirements.

=cut
