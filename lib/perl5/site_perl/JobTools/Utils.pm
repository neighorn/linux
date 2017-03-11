package JobTools::Utils;
require Exporter;
@ISA			= qw(Exporter);
@EXPORT_OK		= qw( Commify CompressByteSize ExpandByteSize FormatElapsedTime LoadConfigFiles OptArray OptFlag OptValue OptOptionSet RunDangerousCmd RunRemote ExpandConfigList);
%EXPORT_TAGS		= (
	Opt		=> [qw(OptArray OptFlag OptValue OptOptionSet)],
	ByteSize	=> [qw(CompressByteSize ExpandByteSize)],
);

use strict;
use warnings;
use POSIX qw(strftime);
use Text::ParseWords;

our $Version		= 1.0;
our $BYTESIZE_UNITS 	= 'BKMGTPEZY';
our $OptionsRef;				# Pointer to %Options hash
our $ConfigRef;					# Pointer to %Config hash
our %OptArrayConfigUsed;			# Hash used to prevent infinite loops in OptArray config look-ups

# ---------------------------------------------------------
# Copyright (c) 2015, Martin Consulting Services, Inc.
# Licensed under the Lesser Gnu Public License (LGPL).
# 
# ABSOLUTELY NO WARRENTIES EXPRESSED OR IMPLIED.  ANY USE OF THIS
# CODE IS STRICTLY AT YOUR OWN RISK.
#



#
# init - accept and store pointers we may need elsewhere.
#
sub init {
	my %Hash = @_;

	foreach (keys(%Hash)) {
		if ($_ eq 'options') {
			$OptionsRef = $Hash{$_};
		}
		elsif ($_ eq 'config') {
			$ConfigRef = $Hash{$_};
		}
		else {
			warn "JobTools::Utils: Unknown option $_ -- ignored\n";
		}
	}
	undef %OptArrayConfigUsed;	# (Re)initialize this.
	return;
}



#
# Commify - insert commas in numbers.
#
sub Commify {
	local $_ = shift;
	1 while s/^(-?\d+)(\d{3})/$1,$2/;
	return $_;
}



# ---------------------------------------------------------
#
# ExpandByteSize - convert various byte number formats to a simple bytes.
#
sub ExpandByteSize {

	my %Hash;		# Input parameters.
	if (@_ == 1) { 
	        $Hash{Value} = shift;
	}
	else {
		%Hash = @_;
	}

	# Parse the value and suffix, and validate the value.
	if (! exists($Hash{Value})) {
		warn qq<No conversion value provided -- no conversion possible.>;
		return undef;
	}
	my $Input = $Hash{Value};

	my $Value;			# Resulting value.
	my $Suffix;			# Resulting suffix.
        $Input =~ s/,//g;               # Ignore commas.
	if ($Input =~ /^\s*(\d+|\d+.|\d*.\d+)\s*([$BYTESIZE_UNITS])?B?\s*$/i) {
		$Value = $1;
		$Suffix = $2;
	}
	else {
		warn qq<Invalid value "$Hash{Value}" -- no conversion possible>;
		return undef;
	}
	$Suffix = 'B' unless (defined($Suffix));
	$Suffix = uc($Suffix);
		
	# Validate the conversion factor.
	if (! exists($Hash{Conversion})) {
		$Hash{Conversion} = 1024;		# Using the default.
	}
	elsif ($Hash{Conversion} =~ /^\s*0*([1-9]\d*)\s*$/) {
		$Hash{Conversion} = $1;
	}
	else {
		warn qq<Invalid conversion value "$Hash{Conversion}" -- using 1024>;
		$Hash{Conversion} = 1024;
	}

        return $1 unless (defined($Suffix));	# No suffix means bytes.
	
	my $Factor = index(uc($BYTESIZE_UNITS),$Suffix);
	if (defined($Factor)) {
		return $Value*$Hash{Conversion}**$Factor;
        }
}



# ---------------------------------------------------------
#
# CompressByteSize - convert integer bytes to KMGT...
#
sub CompressByteSize {

	my %Hash;		# Input parameters.
	if (@_ == 1) { 
	        $Hash{Value} = shift;
	}
	else {
		%Hash = @_;
	}

	# Parse the value and suffix, and validate the value.
	if (! exists($Hash{Value})) {
		warn qq<No conversion value provided -- no conversion possible.>;
		return undef;
	}
	my $Value = $Hash{Value};
        $Value =~ s/,//g;               # Ignore commas.

	my $Conversion = (exists($Hash{Conversion})?$Hash{Conversion}:1024);	# Default to 1024

	my $UnitsRemaining = $BYTESIZE_UNITS;
	$UnitsRemaining =~ m/^(.)(.*)$/;
	my $Unit=$1;
	$UnitsRemaining = $2;
	while ($Value >= $Conversion and $UnitsRemaining) {
		($Unit,$UnitsRemaining) = split('',$UnitsRemaining,2);
		$Value /= $Conversion;
	}
	$Hash{Format}='%.1f%s' unless ($Hash{Format});
	return sprintf($Hash{Format},$Value,$Unit);
}



# ---------------------------------------------------------
#
# LoadConfigFiles - load a configuration file
#
my %LoadConfigFiles_ConfigFilesRead;	# Persistent package module.
sub LoadConfigFiles {

	my %Hash;		# Input parameters.
	if (@_ == 1) { 
		# "LoadConfigFiles('my.cfg')" format.
		@{$Hash{files}}	= @_;	# Create a list of 1 file.
	}
	else {
		# "LoadConfigFiles(files => \@file_list)" or
		# "LoadConfigFiles(files => ["file1", "file2"])" format.
		%Hash = @_;
	}
	$Hash{verbose} = $OptionsRef->{verbose} unless (exists($Hash{verbose}));
	$Hash{verbose} = 0 unless (defined($Hash{verbose}));

	foreach my $ConfigFile (@{$Hash{files}}) {
		if (exists($LoadConfigFiles_ConfigFilesRead{$ConfigFile})) {
			# We already read this one.
			print "Verbose: JobTools::Utils::LoadConfigFiles: Ignoring duplicate $ConfigFile\n" if ($Hash{verbose});
			next;
		}
		else {
			# Remember we read this one, to avoid include-loops.
			$LoadConfigFiles_ConfigFilesRead{$ConfigFile} = 1;
		}
		print "Verbose: JobTools::Utils::LoadConfigFiles: Processing $ConfigFile\n" if ($Hash{verbose});
		if (-e $ConfigFile) {
			my $CONFIGFH;
	                open($CONFIGFH,$ConfigFile) || die("Unable to open $ConfigFile: $!\n");
	                # Build a hash of settings found in the config file.
	                my @Lines;
	
	                # Read config file and assemble continuation lines into single items.
	                while (<$CONFIGFH>) {
				chomp;
	                        next if (/^\s*#/);                      # Comment.
	                        next if (/^\s*$/);                      # Blank line.
	                        if (/^\s+(\S.*)/ and @Lines > 0) {
	                                # Continuation line.  Append to prior line.
	                                $Lines[$#Lines] .= " $1";
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
				$settings=~s/\s\s+/ /g;			# Normalize separating spaces.
				if ($name eq 'INCLUDE') {
					LoadConfigFiles($settings);
				}
				else {
					$settings=~s/\s+$//;	# Trim trailing spaces.
					if ($ConfigRef->{$name}) {
						# Append to existing values.
						$ConfigRef->{$name}.=" $settings";
						print qq<Verbose: JobTools::Utils::LoadConfigFiles: Appending to $name: "$settings"\n> if ($Hash{verbose} >=2 );
					}
					else {
						$ConfigRef->{$name}=$settings;
						print qq<Verbose: JobTools::Utils::LoadConfigFiles: Setting $name to "$settings"\n> if ($Hash{verbose} >=2 );
					}
				}
	                }
	        }
        }
}



# ---------------------------------------------------------
#
# OptArray - generic multi-value option  processing
#
sub OptArray {

	my $Name = shift;
	my $Value = shift;
	
	# Possible array processing options:
	#       preserve-lists: 0 (default), split on embedded spaces or commas
	#                       1, don't split on embedded spaces or commas
	#	allow-delete:	0 (default), leading ! on value has no meaning
	#			1, leading ! on value means delete value from
	#				current list.
	#	force-delete:	0 (default), assume add unless ! and allow-delete=1
	#			1, delete this item regardless of leading !
	#			   Used internally with expand-config=1 to pass !
	#                          indicator to expanded Config values that are 
	#                          also keys.  (e.g. !SERVERS => !a !b !MORESERVERS)
	#	expand-config:	0 (default), leave values unexamined
	#			1, check values to see if they match a %Config key.
	#			   If so, replace with the associated Config values.
	#			   Then check resulting values for more keys.

	my %Defaults = (
		'preserve-lists'	=> 0,
		'allow-delete'		=> 0,
		'force-delete'		=> 0,
		'expand-config'		=> 0,
		'verbose'		=> 0,
	);
	my %Parms = _GatherParms({@_}, \%Defaults);	# Gather parms into one place.

	# Is the value empty, meaning to wipe any entries to this point.
	if (!$Value) {
		# Received "--opt=".  Empty this array.
		@{$OptionsRef->{$Name}}=();
		return;
	}

	# Split out lists by default, unless embedded-lists are preserved.
	my @ValueList;
	if ($Parms{'preserve-lists'}) {
		# Preserve commas and embedded spaces.  Just leave value as is.
		@ValueList = ($Value);
	}
	else {
		$Value =~ s/[\s,]+$//;	# Trailing separators make no sense.
		$Value =~ s/^\s+//;	# Ignore leading whitespace.
		@ValueList = quotewords('[\s,]+',1,$Value);
	}

	# Now process each list item individually.
	while ($Value = shift(@ValueList)) {
		
		# Are we adding or deleting this item.
		my $AddItem = 1;	# Assume we're adding.
		my $Prefix;
		if ($Parms{'force-delete'}) {
			# We've been told, flat-out, to delete this item.
			$AddItem = 0;
			$Value =~ s/^!+// if ($Parms{'allow-delete'});
		}
		elsif ($Parms{'allow-delete'} and $Value =~ /^!+(.*)$/) {
			# Delete is allowed, and ! is present.
			$AddItem = 0;
			$Value = $1;
		}
		
		# If config lists are permitted, see if this is a config list.
		my $UCValue = uc($Value);
		if ($Parms{'expand-config'} and exists($ConfigRef->{$UCValue})) {
			# This is a reference to a config file list. First, make
			# sure we haven't already used this config file list for this
			# array, to avoid loops.
			if (	    exists($OptArrayConfigUsed{$Name})
				and exists($OptArrayConfigUsed{$Name}{$UCValue})
			) {
				# Already been here. Don't expand it a second time.
				print "Verbose: JobTools::Utils::OptArray: $Name refers to $UCValue configuration file values more than once.  Ignored.\n"
					if ($Parms{verbose});
			}
			else {
				# Load up options from this config file entry.
				$OptArrayConfigUsed{$Name}{$UCValue} = 1;	# Remember we did this one.
				print "Verbose: JobTools::Utils::OptArray: $Name refers to $UCValue configuration file values.  Expanding $UCValue.\n"
					if ($Parms{verbose});
				OptArray(
					$Name,
					$ConfigRef->{uc($Value)},
					%Parms,
					'force-delete'=> (1-$AddItem),
				);
			}
			next;
		}

		# If we got here, we have a value to either add or delete.
		if ($AddItem) {
			push @{$OptionsRef->{$Name}},$Value
				unless grep { $_ eq $Value } @{$OptionsRef->{$Name}};
		}
		else {
			# Remove this item from the list if present.
			@{$OptionsRef->{$Name}} = grep { $_ ne $Value } @{$OptionsRef->{$Name}};
		}
	}
}



# ---------------------------------------------------------
#
# OptValue - generic single-value option processing
#
sub OptValue {
	my($Name,$Value) = @_;
	$OptionsRef->{$Name} = $Value;
}


# ---------------------------------------------------------
#
# OptFlag - generic no-value flag option processing
#
sub OptFlag {
	my($Name) = @_;
	if (exists($OptionsRef->{$Name})) {
		$OptionsRef->{$Name}++;
	}
	else {
		$OptionsRef->{$Name} = 1;
	}

}


# ---------------------------------------------------------
#
# OptOptionSet - Process options from an option set as if
#                they had been on the command line.
#    Example:
#      Command line: myscript -O optset
#      Confilg file: optset -v -m jsmith
#      OptOptionSet( name => 'optset', optspec => \%OptSpec )
#      Result: %Config (as declared in init) has -v turned on and -m set to 'jsmith'
#
sub OptOptionSet {
	require Getopt::Long; Getopt::Long->import(qw(GetOptionsFromString));
        my %Hash = @_;
	$Hash{verbose} = 0 unless (exists($Hash{verbose}) and $Hash{verbose});
	
	# Make sure we have all the necessary pieces.
	my $Errors = 0;
	foreach my $name (qw(name optspec)) {
		if (!exists($Hash{$name})) {
			warn "OptOptionSet: missing required $name parameter\n";
			$Errors++;
		}
	}
	return $Errors if ($Errors);

        $Hash{name} = uc($Hash{name});	# Normalize the name.
        $Hash{name} =~ m/(:?)(\S+)/;	# See if it starts with a colon, meaning optional.
        my $Optional = (defined($1) and $1 eq ':');
        $Hash{name} = $2;
	print "Verbose: JobTools::Utils::OptOptionSet: Name = $Hash{name}, Optional = $Optional\n"
		if ($Hash{verbose});
        if (exists($ConfigRef->{$Hash{name}})) {
		print "Verbose: JobTools::Utils::OptOptionSet: Processing $Hash{name} option set: $ConfigRef->{$Hash{name}}\n"
			if ($Hash{verbose});
                $Errors++ unless GetOptionsFromString(
                        $ConfigRef->{$Hash{name}},
                        %{$Hash{optspec}},
                );
        }
	elsif (! $Optional) {
                warn qq<Warning: "$Hash{name}" not found in configuration file\n>
			unless (exists($Hash{'suppress-output'}) and $Hash{'suppress-output'});
		$Errors++;
        }
	else {
		print "Verbose: JobTools::Utils::OptOptionSet: Option set $Hash{name} not found and optional -- ignored\n"
			if ($Hash{verbose});
	}
	return $Errors;
}


# ---------------------------------------------------------
#
# RunDangerousCmd - run a command, or suppress it if -t specified.
#
sub RunDangerousCmd {
	my ($Cmd,%Settings) = @_;

	my %Defaults = (
		test => 0,
		verbose => 0,
	);
	my %Parms = _GatherParms(\%Settings,\%Defaults);

	if ($Parms{test}) {
		print "Test: $Cmd\n"
			unless (exists($Settings{'suppress-output'}) and $Settings{'suppress-output'});
		return 0;
	}
	else {
		my($FH,$Line);
		print "Executing: $Cmd\n"
			if ($Parms{verbose} and !$Settings{'suppress-output'});
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



# ---------------------------------------------------------
#
# RunRemote - Run this elsewhere and track the results.
#
sub RunRemote {

	# Load some additional modules only needed on the parent.
	require Parallel::ForkManager;
	require String::ShellQuote; String::ShellQuote->import(qw(shell_quote));

	my %Defaults = (
		'remote-max'	=> 64,
		argv		=> [],
		childpre	=> undef,
		childpost	=> undef,
		quiet		=> 0,
		remote		=> [],
		test		=> 0,
		verbose		=> 0,
	);

	my @HostList;
	my $Errors = 0;
	my @RemoteParms;
	my %Parms = _GatherParms({@_}, \%Defaults);	# Gather parms into one place.
		
	# Make sure we have some required values.
	foreach my $item (qw(argv remote)) {
		if (!exists($Parms{$item}) or (@{$Parms{$item}} == 0)) {
			warn "RunRemote: no $item array provided.\n";
			$Errors++;
		}
	}
	return $Errors if ($Errors);
	if (!exists($Parms{'remote-max'}) or !defined($Parms{'remote-max'}) or $Parms{'remote-max'} !~ /^[1-9]\d*$/) {
		warn qq<RunRemote: Invalid value "$Parms{'remote-max'}" for 'remote-max' -- defaulting to $Defaults{'remote-max'}\n>;
		$Errors++;
		$Parms{'remote-max'}=$Defaults{'remote-max'};
	}

	# Get the list of target hosts.
	if (ref($Parms{remote}) eq 'SCALAR') {
		# They provided us with a blank or comma separated list.
		@HostList = split(/[\s,]+/,$Parms{remote});
	}
	else {
		# They provided us with an array.
		@HostList = @{$Parms{remote}};
	}

	# Analyze the target host list, ignoring duplicates and handling !-deletions.
	@HostList = ExpandConfigList(@HostList);

	# Get the max host name length, for display purposes.
	my $MaxLength = 0;
	foreach (@HostList) { $MaxLength=($MaxLength < length($_)?length($_):$MaxLength); }
	$MaxLength++;		# Allow for trailing colon.

	# Remove -R/--remote-host from remote.  They don't need to know who else we're talking to.
	@RemoteParms = @{$Parms{argv}};
	my $DeleteNext=0;
	foreach (@RemoteParms) {
		if ($DeleteNext) {
			$_ = '';
			$DeleteNext=0;
		}
		elsif (/^--remote=/) {
			$_ = '';		# Delete this for remote systems.
		}
		elsif (/^-R/) {
			$DeleteNext=(/^-R$/);	# Differentiate between "-Rx" and "-R x".
			$_ = '';
		}
	}
	@RemoteParms = grep { $_ ne '' } @RemoteParms;	# Delete empty elements.

	my $PFM = Parallel::ForkManager->new($Parms{'remote-max'});

	foreach my $Host (@HostList) {
		my $pid = $PFM->start;	# Fork the child process.
		if (!$pid) {
			&{$Parms{childpre}}(
				pid		=> $$,
				host		=> $Host,
				parms		=> \%Parms,
				maxhostlength	=> $MaxLength-1
			)
				if (defined($Parms{childpre}));
			my $Cmd =   "ssh "
				  . sprintf("%-*s",$MaxLength,$Host)
				  . shell_quote(@RemoteParms) . ' '
				  ;
			my $FH;
			$Cmd =~ s/%HOST%/$Host/g;
	
			# Don't even go to remote hosts if test level 2 (-tt).
			if($Parms{test} >= 2) {
				print "Test: $Cmd\n";
				$PFM->finish(0);
				next;
			}
	
			print "Verbose: JobTools::Utils::RunRemote: Running $Cmd\n" if ($Parms{verbose} or $Parms{test});
			my $StartTime = time();
			my($ExitCode,$Signal,$StopTime,$Elapsed);
			if (open($FH, "$Cmd |")) {
				while (<$FH>) {
					printf "%-*s %s", $MaxLength, "$Host:", $_;
				}
				close $FH;
				($ExitCode, $Signal) = ($? >> 8, $? & 127);
				$StopTime = time();
				$Elapsed = $StopTime-$StartTime;
				printf "%-*s  Remote job ended at %8s, return code = %3d, signal = %3d, run time = %10ss\n",
					$MaxLength,
					"$Host:",
					strftime("%H:%M:%S", localtime($StopTime)),
					$ExitCode,
					$Signal,
					FormatElapsedTime($Elapsed),
						unless ($Parms{quiet});
				$Errors++ if ($ExitCode or $Signal);
			}
			else {
				warn "Unable to open ssh session to $Host: $!\n";
				$Errors++;
			}
			&{$Parms{childpost}}(
				pid		=> $$,
				host		=> $Host,
				parms		=> \%Parms,
				maxhostlength	=> $MaxLength-1,
				errors		=> $Errors,
				exitcode	=> $ExitCode,
				signal		=> $Signal,
				elapsed		=> $Elapsed,
			)
				if (defined($Parms{childpost}));
			$PFM->finish($Errors);
		}
	}
	$PFM->wait_all_children;

	return $Errors;
}



#
# FormatElapsedTime: - return formatted elapsed time
#
sub FormatElapsedTime {

	use integer;
	my $sec = shift;
	if ($sec !~ /^\d+$/) {
		warn qq<JobTools::Utils::FormatElapsedTime: invalid value "$sec" provided -- treating as zero\n>;
		$sec = 0;
	}
	
	return $sec if $sec < 60;
	
	my $min = $sec / 60, $sec %= 60;
	$sec = "0$sec" if $sec < 10;
	return "$min:$sec" if $min < 60;
	
	my $hr = $min / 60, $min %= 60;
	$min = "0$min" if $min < 10;
	return "$hr:$min:$sec" if $hr < 24;
	
	my $day = $hr / 24, $hr %= 24;
	$hr = "0$hr" if $hr < 10;
	return "$day:$hr:$min:$sec";
}


#
# _GatherParms: - return hash pulled from @_, %OptionsRef, or %Defaults
#
sub _GatherParms {

	my($ArgvRef, $DefaultsRef) = @_;
	my %Parms;
	foreach my $item (keys(%$DefaultsRef)) {
		if (exists($ArgvRef->{$item})) {
			# Provided in passed arguments.
			$Parms{$item} = $ArgvRef->{$item};
		}
		elsif (defined($OptionsRef) and exists($OptionsRef->{$item})) {
			$Parms{$item} = $OptionsRef->{$item};
		}
		else {
			$Parms{$item} = $DefaultsRef->{$item};
		}
	}
	return %Parms;
}


#
# ExpandConfigList: - Expand a host list with any values found in config files.
#
sub ExpandConfigList {

	my @HostList = @_;	# Make a local copy we can mess with.
	my @ExpandedHostList;
	my %HostsUsed;
	while ($_ = shift(@HostList)) {
		my($Prefix,$Host) = m/^(!*)(\S+)$/;
		my $UCHost = uc($Host);
		if (exists($ConfigRef->{$UCHost})) {
			# This is a config list, not a single host name.  Need to expand it.
			my %ConfigSeenHash;	# Avoid recursion loops.
			my @ConfigList = _ExpandConfigGroup($UCHost,\%ConfigSeenHash);
			foreach (@ConfigList) { s/^\!*/$Prefix/}; #Strip any prefixes, then add ours.
			unshift @HostList, @ConfigList;		# Push the expanded list back on the list.
		}
		elsif ($Prefix) {
			# We're deleting a host.
			next unless (exists($HostsUsed{$Host}));		# But we never saw it anyway.
			@ExpandedHostList = grep {$_ ne $Host} @ExpandedHostList;
			$HostsUsed{$Host} = 0;
		}
		elsif ($HostsUsed{$Host}) {
			#next;			# Already saw this one.
		}
		else {
			# This is a new, simple host name.
			push @ExpandedHostList, $Host;
			$HostsUsed{$Host} = 1;
		}
	}
	return @ExpandedHostList;
}



#
# _ExpandConfigGroup: - Expand a configuration setting value into a group of host names.
#
sub _ExpandConfigGroup {

	my($GroupName,$SeenRef) = @_;
	return () if (exists($SeenRef->{$GroupName}));		# We've already done this one.
	$SeenRef->{$GroupName} = 1;				# Remember we've done this one, to avoid loops.
	return ($GroupName) unless (exists($ConfigRef->{$GroupName}));	# Doesn't exist.  Should not happen.

	my @GroupList = split(/[,\s]+/,$ConfigRef->{$GroupName});
	my @ReturnList;
	while ($_ = shift @GroupList) {
		if (exists($ConfigRef->{$_})) {
			# It's a nested group.
			unshift @GroupList,_ExpandConfigGroup($_,$SeenRef);
		}
		else {
			# It's a simple value.
			push @ReturnList, $_;
		}
	}
	return @ReturnList;
}

1;
