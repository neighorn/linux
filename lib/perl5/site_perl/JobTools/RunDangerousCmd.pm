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
package	RunDangerousCmd;
require	Exporter;
use Sys::Syslog;

our @ISA	= qw(Exporter);
our @EXPORT	= qw(RunDangerousCmd);
#our @EXPORT_OK	= qw(yyy);
our $Version	= 3.1;

# RunDangerousCmd - run a command, or suppress it if -t specified.
#
sub RunDangerousCmd {
	my ($Cmd,%Settings) = @_;
	
	my($FH,$Line,$Test,$Verbose);
	$Test = (exists($Settings{test})?$Settings{test}:$main::Options{test});
	$Verbose = (exists($Settings{verbose})?$Settings{verbose}:$main::Options{verbose});
	if ($Test) {
		print "Test: $Cmd\n";
		return 0;
	} else {
		print "Executing: $Cmd\n" if ($Verbose);
		if (open($FH,"$Cmd 2>&1 |")) {
			while ($Line=<$FH>) {
				$Line=~s/[
]//g;
				chomp $Line;
				print "$Line\n";
			};
			close $FH;
			return $?;
		} else {
			warn qq(Unable to start process for "$Cmd": $!\n");
			return 8<<8;
		}
	}
}
1;
