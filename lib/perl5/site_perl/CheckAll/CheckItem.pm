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
