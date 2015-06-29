sub ReadConfigFiles
{
	# ---------------------------------------------------------
	#
	# Load the config files.
	#
	use strict;
	use warnings;
	use Switch;
	my %Parms = @_;
	my %Config;		# Work area for settings.
	my $FileListRef;	# Ref. to array of files to read.
	my $ResultRef;		# Ref. to return hash.
	
	my $Error = 0;
	foreach (keys(%Parms)) {
		switch ($_) {
			case /^FILELIST$/i	{$FileListRef = $Parms{$_}}
			case /^RESULTS$/i	{$ResultRef = $Parms{$_}}
			else	{
				print STDERR "ReadConfigFiles: Unknown setting $_\n";
				$Error=1;
			}
		}
	}
	die "ReadConfigFiles: processing aborted due to prior errors." if ($Error);
	
	# Loop through each config file.
	foreach my $ConfigFile (@$FileListRef) {
		# Does this file exist?
		if (-e $ConfigFile) {
			# Yes, parse it.
			my $CONFIG;
			open($CONFIG,$ConfigFile) || die("Unable to open $ConfigFile: $!\n");
			# Build a hash of settings found in the config file.
			while (<$CONFIG>) {
				next if (/^\s*#/);      # Comment.
				next if (/^\s*$/);      # Blank line.
				chomp;
				# Split out.  Recognized operators are \s+, :, =, .=, +, +=, -, -=.
				my($name,$operator,$settings) = 
					m/^\s*(\S+)\s*(:|=|\.=|\+|\+=|\-|\-=|\s+)\s*([^\s:=\+.]+)\s*(\S.*$)/;
				$name=~tr/[a-z]/[A-Z]/;
				switch ($operator) {
					case /^(\s+|:|\.=|\+|\+=)$/{
						# Append operation.
						$Config{$name} .= "," if ($Config{name});
						$Config{$name} .= $settings;
						push @{$Config{"\@$name"}},$settings;
					}
					case "=" {
						$Config{$name} = $settings;
						@{$Config{"\@$name"}} = ($settings);
					}
					else {
						die "ConfigFile: $operator is not an implemented operator";
					}
				}
			}
			close $CONFIG;
		}
	}
	
	%$ResultRef = %Config;
}
1;
