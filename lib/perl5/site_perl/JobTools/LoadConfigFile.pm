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
package	LoadConfigFile;
require	Exporter;

our @ISA	= qw(Exporter);
our @EXPORT	= qw(LoadConfigFile %Config);
#our @EXPORT_OK	= qw(LoadConfigFile);
our $Version	= 3.1;

# LoadConfigFile - load a configuration file
#
sub LoadConfigFile {
	my $ConfigFile = shift;
	if (-e $ConfigFile) {
		my $CONFIGFH;
                open($CONFIGFH,$ConfigFile) || die("Unable to open $ConfigFile: $!\n");
                # Build a hash of settings found in the config file.
                my @Lines;

                # Read config file and assemble continuation lines into single items.
                while (<$CONFIGFH>) {
                        next if (/^\s*#/);                      # Comment.
                        next if (/^\s*$/);                      # Blank line.
                        chomp;
                        if (/^\s+/ and @Lines > 0) {
                                # Continuation line.  Append to prior line.
                                $Lines[$#Lines] .= " $_";
                        }
                        else {
                                push @Lines, $_;
                        }
                }
                close $CONFIGFH;

                # Process assembled lines.
                foreach (@Lines) {
                        my ($name,$settings)=split(/:?\s+/,$_,2);
                        $name=uc($name);                        # Name is not case sensitive.
                        $settings='' unless ($settings);        # Avoid undef warnings.
                        $settings=~s/\s+$//;                    # Trim trailing spaces.
			if ($name eq 'INCLUDE') {
				LoadConfigFile($settings);
			}
			else {
				$settings=~s/\s+$//;	# Trim trailing spaces.
				$Config{$name}.=$settings . ',' ;
			}
                }
		foreach (keys(%Config)) {
			$Config{$_} =~ s/,$//;  # Remove trailing comma
		}
        }
}
1
