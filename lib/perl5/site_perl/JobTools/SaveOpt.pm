#
# Copyright (c) 2015, Martin Consulting Services, Inc.
# Licensed under the Lesser Gnu Public License (LGPL).
# 
# ABSOLUTELY NO WARRENTIES EXPRESSED OR IMPLIED.  ANY USE OF THIS
# CODE IS STRICTLY AT YOUR OWN RISK.
#
#		POD documentation appears at the end of this file.
#
use strict;
use warnings;
package	SaveOpt;
require	Exporter;

our @ISA	= qw(Exporter);
our @EXPORT	= qw(opt_Value opt_Array);
#our @EXPORT_OK	= qw(yyy);
our $Version	= 1.0;

# opt_Value - generic single-value option processing
#
sub opt_Value {
	my($Name,$Value) = @_;
	$Options{$Name} = $Value;
}


#
# opt_Array - generic multi-value optoin  processing
#
sub opt_Array {

	my($Name,$Value,%Settings) = @_;
	if (defined($Value) and length($Value)) {
		# Add this value to the array.
		if (!$Settings{'split'}) {
			# They set split=0, so don't split on a delimiter.
			push @{$Options{$Name}},$Value;
		}
		else {
			# By default, split on a delimiter, typically comma.
			my $Delimiter=($Settings{'split-delimiter'}?$Settings{'split-delimiter'}:',');
			push @{$Options{$Name}},split($Delimiter,$Value);
		}
	}
	else {
		# Received "--opt=".  Empty this array.
		@{$Options{$Name}}=();
	}
}
1;
