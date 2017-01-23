package Utils;
require Exporter;
@ISA		= qw(Exporter);
@EXPORT_OK	= qw( Commify ExpandByteSize CompressByteSize LoadConfigFiles OptArray OptValue RunDangerousCmd RunRemote);
our $Version	= 1.0;
our $BYTESIZE_UNITS = 'BKMGTPEZY';
our $OptionsRef;				# Pointer to %Options hash
our $ConfigRef;					# Pointer to %Config hash
our %OptArrayConfigUsed;			# Hash used to prevent infinite loops in OptArray config look-ups

use strict;
use warnings;

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
	if ($Input =~ /^\s*0*([1-9]\d*)\s*([$BYTESIZE_UNITS])?B?\s*$/) {
		$Value = $1;
		$Suffix = $2;
	}
	else {
		warn qq<Invalid value "$Hash{Value}" -- no conversion possible>;
		return undef;
	}
	$Suffix = 'B' unless (defined($Suffix));
	if ($Suffix !~ /^[$BYTESIZE_UNITS]$/) {
		warn qq<Unrecognized unit suffix "$Suffix" in $Hash{Value} -- conversion not possible>;
		return undef;
	}
		
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
	
	my $Factor = index($BYTESIZE_UNITS,$Suffix);
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
		@{$Hash{files}}	 = @_;	# Create a list of 1 file.
	}
	else {
		# "LoadConfigFiles(files => \@file_list)" or
		# "LoadConfigFiles(files => ["file1", "file2"])" format.
		%Hash = @_;
	}

	foreach my $ConfigFile (@{$Hash{files}}) {
		if (exists($LoadConfigFiles_ConfigFilesRead{$ConfigFile})) {
			# We already read this one.
			print "LoadConfigFiles: Ignoring duplicate $ConfigFile\n" if ($OptionsRef->{Verbose});
			next;
		}
		else {
			# Remember we read this one, to avoid include-loops.
			$LoadConfigFiles_ConfigFilesRead{$ConfigFile} = 1;
		}
		print "LoadConfigFiles: Processing $ConfigFile\n" if ($OptionsRef->{Verbose});
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
					}
					else {
						$ConfigRef->{$name}=$settings;
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
	#	preserve-lists:	0 (default), split on embedded spaces or commas
	#			1, don't split on embedded spaces or commas
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
		@ValueList = split(/[,\s]+/,$Value);
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
				print "OptArray: $Name refers to $UCValue configuration file values more than once.  Ignored.\n"
					if ($Parms{verbose});
			}
			else {
				# Load up options from this config file entry.
				$OptArrayConfigUsed{$Name}{$UCValue} = 1;	# Remember we did this one.
				print "OptArray: $Name refers to $UCValue configuration file values.  Expanding $UCValue.\n"
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
		print "Test: $Cmd\n";
		return 0;
	}
	else {
		my($FH,$Line);
		print "Executing: $Cmd\n" if ($Parms{verbose});
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

	my %Defaults = (
		test => 0,
		verbose => 0,
		pmax => 1,
		argv => [],
		remote => [],
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
	my $MaxLength = 0;
	foreach (@HostList) { $MaxLength=($MaxLength < length($_)?length($_):$MaxLength); }
	$MaxLength++;		# Allow for trailing colon.

	# Remove -R/--remote-host from remote.  They don't need to know who else we're backing up.
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
			$_ = '';
			$DeleteNext=1;
		}
	}
	@RemoteParms = grep { $_ ne '' } @RemoteParms;
	@RemoteParms = map {qq<"$_">} @RemoteParms;

	my $PFM = Parallel::ForkManager->new($Parms{pmax},'/tmp');

	foreach my $Host (@HostList) {
		my $pid = $PFM->start;	# Fork the child process.
		if (!$pid) {
			my $Cmd =   "ssh $Host "
				  . join(' ', @RemoteParms) . ' '
				  . '-F SHOWALL '
				  . '--always-mail= '
				  . '--remote= '	# Avoid --remote recursion from AllJobs in .cfg.
				  . '2\>\&1 '
				  ;
			my $FH;
	
			# Don't even go to remote hosts if test level 2 (-tt).
			if($Parms{test} >= 2) {
				print "Test: $Cmd\n";
				next;
			}
	
			print "Verbose: Running $Cmd\n" if ($Parms{verbose} or $Parms{test});
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
			$PFM->finish(0,\$Errors);
		}
	}

	return $Errors;
}



#
# _GatherParms: - return hash pulled from @_, %OptionsRef, or %Defaults
#
sub _GatherParms {

	my($ArgvRef, $DefaultsRef) = @_;
	my %Parms;
	foreach my $item (keys($DefaultsRef)) {
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


1;
