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
package	RunRemote;
require	Exporter;

our @ISA	= qw(Exporter);
our @EXPORT	= qw(RunRemote);
#our @EXPORT_OK	= qw(yyy);
our $Version	= 3.1;

# RunRemote - Run this elsewhere and track the results.
#
sub RunRemote {

	my ($ListRef,%Settings) = @_;
	my @HostList;
	my $Errors = 0;
	my $Test = (exists($Settings{test})?$Settings{test}:$main::$Options{test});
	my $Verbose = (exists($Settings{verbose})?$Settings{verbose}:$main::$Options{verbose});
	foreach my $RemoteItem (@{$ListRef}) {
		$RemoteItem =~ s/,+/ /g;
		foreach (split(/\s+/,$RemoteItem)) {
		        if (exists($Config{uc($_)})) {
		                # This is a name from the config file.  Push it's list.
		                my $ConfigItem = $Config{uc($_)};
				$ConfigItem =~ s/,+/ /g;
				my @SplitList = split(/\s+/,$Config{uc($_)});
		                push @HostList, @SplitList;
		        }
		        else {
		                push @HostList, $_;
		        }
	        }
	}
	die "No remote hosts specified on the command line or in the configuration file.\n" unless (@HostList);

	my $MaxLength = 0;
	foreach (@HostList) { $MaxLength=($MaxLength < length($_)?length($_):$MaxLength); }
	$MaxLength++;		# Allow for trailing colon.

	foreach my $Host (@HostList) {
		my $Cmd =   "ssh $Host $Prog "
			  . '-F /usr/local/etc/filter-accept-all.filter '
			  . '--always-mail= '
			  . ($Verbose > 1?'-v ':'')
			  . ($Test?'-t ':'')
			  . '2\>\&1 '
			  ;
		my $FH;
		print "Verbose: Running $Cmd\n" if ($Verbose or $Test);
		if (open($FH, "$Cmd |")) {
			while (<$FH>) {
				printf "%-*s %s", $MaxLength, "$Host:", $_;
			}
			close $FH;
			my ($ExitCode, $Signal) = ($? >> 8, $? & 127);
			print "$Host:  Remote job exited with return code $ExitCode and signal $Signal\n";
			$Errors++ if ($ExitCode);
		}
		else {
			warn "Unable to open ssh session to $Host: $!\n";
			$Errors++;
		}
	}

	return $Errors;
}
1;
