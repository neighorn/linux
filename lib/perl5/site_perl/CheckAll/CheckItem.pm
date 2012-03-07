#----------------------------CheckItem base class-----------------------------
#
# CheckItem - basic monitoring item - base class.
#
package CheckItem;

use strict;
use warnings;
no strict 'refs';

use Text::ParseWords;
use POSIX qw(strftime);
use Exporter;

use constant CHECK_OK => 0;
use constant CHECK_FAIL => 8;
use constant CHECK_HIGHLIGHT => "\e[33;40m";
use constant CHECK_RESET => "\e[0m";

use constant CHECK_STILL_UP => 0;
use constant CHECK_STILL_DOWN => 1;
use constant CHECK_NOW_UP => 2;
use constant CHECK_NOW_DOWN => 3;

our @ISA = ('Exporter');
our @EXPORT = qw(
	CHECK_OK CHECK_FAIL CHECK_HIGHLIGHT CHECK_RESET
	CHECK_STILL_UP CHECK_STILL_DOWN CHECK_NOW_UP CHECK_NOW_DOWN
);

my $x = $main::opt_R;	# suppress warning

# Define fields.  Note that Autoload normalizes all field names to "first-upper rest lowercase".
# Names with multiple uppercase characters are not settable from the service files.
use fields (
	'FILE',			# File this definition came from
	'LINE',			# Line in file this definition came from
	'Name',			# Unique descriptor for status file - defaults to desc.
	'Desc',			# Description of service, for messages.
	'Target',		# Target of check (host:port, process pattern, etc.).
	'Status',		# Current status (set by Check).
	'StatusDetail',		# Additional detail
	'FirstDown',		# When this was first detected down
	'PriorStatus',		# Its prior status.  Detects "Now down" vs "Still down".
	'PriorNotification',	# The last time we told someone it was down.
	'Ondown',		# Run this command when it goes down.
	'Onup',			# Run this command when it comes up.
	'Renotifyinterval',	# How often to repeat down notifications (unimplemented).
	'Verbose',		# Verbose (unimplemented).
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
	$Self->{FirstDown} = 0;				# Not down, unless status file changes it.
	$Self->{PriorNotification} = 0;			# Ditto.
	$Self->{Renotifyinterval} = $main::opt_R;	# Default renotify minutes.

	# Set options from the caller (from the file).
	$Self->SetOptions(@_);				# Run through our initialization code.
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
		return CHECK_STILL_UP;
	}
	elsif ($Self->{Status} eq CHECK_FAIL and $Self->{PriorStatus} eq CHECK_FAIL) {
		my $Since;
		my $FirstDown = $Self->FirstDown;
		if (time() - $FirstDown < 84200) {
			$Since = strftime("%T",localtime($FirstDown));
		}
		else {
			$Since = strftime("%D %T",localtime($FirstDown));
		}
		printf "\t\t%s%s DOWN since %s %s%s\n",
			CHECK_HIGHLIGHT,
			$Self->{Desc},
			$Since,
			($Self->{StatusDetail}?' -- ':'') . $Self->{StatusDetail},
			CHECK_RESET
				if (!$main::opt_q);
		return CHECK_STILL_DOWN;
	}
	elsif ($Self->{Status} eq CHECK_OK and $Self->{PriorStatus} eq CHECK_FAIL) {
		printf "\t%-${DescLen}.${DescLen}s OK\n", $Self->{Desc} if (!$main::opt_q);
		return CHECK_NOW_UP;
	}
	else {
		printf "\t\t%s%s now DOWN %s%s\n",
			CHECK_HIGHLIGHT,
			$Self->{Desc},
			($Self->{StatusDetail}?' -- ':'') . $Self->{StatusDetail},
			CHECK_RESET
				if (!$main::opt_q);
		return CHECK_NOW_DOWN;
	}
}


sub SetOptions {
	# Set options.
        my $Self = shift;

	# Assign any values they passed on init/new.
	foreach my $InitItem (@_) {
		foreach (shellwords($InitItem)) {
			my($Field,$Value) = (/^(\S+?)=(.*)$/);
			$Field = ucfirst(lc($Field));	# Normalize case.
			$Value = '' unless (defined($Value));
			eval "\$Self->$Field(\$Value);";
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
	# Can't validate attribute in advance on later Perls (>= 5.9).  Just try, and Perl
	# will block it if it's invalid.
	eval "\$Self->{$Attribute} = \$Value;";
	if ($@ =~ /Attempt to access disallowed key/) {
		die qq[$Self->{FILE}:$Self->{LINE}: "$Attribute" is an invalid attribute.\n];
	}
	elsif ($@) {
		die qq[$Self->{FILE}:$Self->{LINE}: $@\n];
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

OnDown: A command to execute when the target is first discovered down.

=item *

OnUp: A ccommand to execute when a previously down target is first discovered up.

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

Status: The status of the service (up or down), as set by the Check method.

=item *

StatusDetail: Additional text information about the status.  This is typically used to indicate that
a service was marked as "DOWN" for unusual reasons, such as a configuration error.

=item *

PriorStatus: The previous status of this item (defaults to "up" for new items).  This is used to
determine if an item is "now down" (newly down), "still down", "now up", or "still up".

=item *

FirstDown: The time at which the item was first detected down.

=item *

PriorNotification: The time at which the most recent alert was sent about this item being
down.  This is only applicable if notifications were requested with the checkall -P option.

=item *

Renotifyinterval: The time in minutes after which another notification must be sent.  This is
currently unimplemented at the service item level.

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
