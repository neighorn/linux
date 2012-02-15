#-------------------------------- process Item -----------------------------------
#
# process - check to see if a process is present.
#

use strict;
no strict 'refs';
use warnings;
package process;
use base 'CheckItem';

my @Processes;

# Load this data once at start-up.
BEGIN { @Processes=`ps -e -o cmd` };


#================================= Data Accessors ===============================
sub Target {

	# Retrieve or validate and save the target.
	my $Self = shift;

	if (@_) {
		# This is a set operation.
		my $TargetDef = shift;
		eval "\$Self->{Target} = qr${TargetDef};";
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
		return join(',',@{$Self->{Target}});
	}
}

#================================= Public Methods ===============================

sub Check {

	# See if this item is up.
	my $Self = shift;

	my $File = $Self->{'FILE'};
	my $Line = $Self->{'LINE'};
	my $Target = $Self->{'Target'};

	# First, make sure we have the necessary info.
	my $Errors = 0;
	if (! $Self->{Desc}) {
		warn "$File:$Line: Desc not specified.\n";
		$Self->{StatusDetail} = "Configuration error: Desc not specified";
		$Errors++;
	}
	if (! $Self->{Target}) {
		warn "$File:$Line: Target not specified.\n";
		$Self->{StatusDetail} = "Configuration error: Target not specified";
		$Errors++;
	}
	return "Status=" . $Self->CHECK_FAIL if ($Errors);

	foreach (@Processes) {
		print __PACKAGE__ . "::Check: $File:$Line Checking $_\n"
			if ($Self->{Verbose});
		return "Status=" . $Self->CHECK_OK if ( $_ =~ $Target );
	};
	return "Status=" . $Self->CHECK_FAIL;
}
1;

