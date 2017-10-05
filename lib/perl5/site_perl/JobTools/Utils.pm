# ---------------------------------------------------------
# Copyright (c) 2015,2017 Martin Consulting Services, Inc.
# Licensed under the Lesser Gnu Public License (LGPL).
# 
# ABSOLUTELY NO WARRENTIES EXPRESSED OR IMPLIED.  ANY USE OF THIS
# CODE IS STRICTLY AT YOUR OWN RISK.
#

package JobTools::Utils;
require Exporter;
@ISA			= qw(Exporter);
@EXPORT_OK		= qw(Commify CompressByteSize ExpandByteSize FormatElapsedTime UtilGetLock LoadConfigFiles OptArray OptFlag OptValue OptOptionSet UtilReleaseLock RunDangerousCmd RunRemote ExpandConfigList);
%EXPORT_TAGS		= (
	Opt		=> [qw(OptArray OptFlag OptValue OptOptionSet)],
	Lock		=> [qw(UtilGetLock UtilReleaseLock)],
	ByteSize	=> [qw(CompressByteSize ExpandByteSize)],
);

use strict;
use warnings;
use POSIX qw(strftime);
use Text::ParseWords;
use Fcntl qw(:flock :mode :DEFAULT);

our $Version		= 1.1;
our $BYTESIZE_UNITS 	= 'BKMGTPEZY';
our $OptionsRef;				# Pointer to %Options hash
our $ConfigRef;					# Pointer to %Config hash
our %OptArrayConfigUsed;			# Hash used to prevent infinite loops in OptArray config look-ups

=pod

=head1 JobTools::Utils

=head2 Overview

JobTools::Utils contains a variety of scripting tools (e.g. 
convert "1234567" to "1,234,567)
used by the MCSI script library.  Many require JobTools::Utils::init to be called to provide two hash references.  See JobTools::init
for details.

=head2 ----------

=cut

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
=pod

=head2 JobTools::Utils::init

=head3 Synopsis

    use JobTools::Utils
    our %Config;                # Config data.
    our %Options;               # Options settings.
    JobTools::Utils::init(config => \%Config, options => \%Options);

=head3 Explanation


Many of the subroutines in JobTools::Utils need to know the location of one or both
of two hashes maintained by the caller.  These two hashes contain the following information:

=over

=item *

A hash to contain option settings (e.g. what level of verbosity do we want, are we testing, are we sending e-mail to anyone and if so what are the addresses).  The 
internal format is an key that matches whatever the relevant option is as reported by GetOpt::Long (e.g. "verbose"), with the values containing whatever
was provided on the command line, as interpreted by OptFlag, OptValue, or OptArray (discussed below).  

=item *

A hash to contain configuration data as loaded out of configuration files.  This data is less widely used, but still required by some routines.
The internal format is the uppercase key found in the configuration file by LoadConfigFiles (see below), with the value being whatever data was found in the
configuration file for that key.

=back

JobTools::init allows the calling program to pass references to these two hashes, which various routines JobTools::Utils can reference.  In the simplest
case, the calling program just declares these two hashes, passes them to JobTools::Utils::init, and subsequently ignores them.  In more advanced
cases, the calling program or its subroutines may reference these arrays to get settings for their own purposes (e.g. the main program may also 
like to know if we're in verbose mode or not).

    our %Config;		# Config data.
    our %Options;		# Options settings.
    JobTools::Utils::init(config => \%Config, options => \%Options);

=head2 ----------

=cut

}



#
# Commify - insert commas in numbers.
#
sub Commify {
	local $_ = shift;
	s/,//g;		# Remove any pre-existing commas.
	1 while s/^(-?\d+)(\d{3})/$1,$2/;
	return $_;

=pod

=head2 JobTools::Commify

=head3 Synopsis

    use JobTools::Utils qw(Commify);
    my $formatted = Commify('1234567');			# Returns '1,234,567'.
    my $formatted = Commify('12,34,56,7');		# Returns '1,234,567'.

=head3 Explanation

Commify removes any existing commas, and then inserts commas in the appropriate
places to separate strings of digits into three-digit blocks. 

=head2 ----------

=cut

}



# ---------------------------------------------------------
#
# ExpandByteSize - convert various byte number formats to a simple bytes.
#
sub ExpandByteSize {

	my %Hash;		# Input parameters.
	if (@_ == 1) { 
	        $Hash{value} = shift;
	}
	else {
		%Hash = @_;
	}

	# Parse the value and suffix, and validate the value.
	if (! exists($Hash{value})) {
		warn qq<No conversion value provided -- no conversion possible.>;
		return undef;
	}
	my $Input = $Hash{value};

	my $Value;			# Resulting value.
	my $Suffix;			# Resulting suffix.
        $Input =~ s/,//g;               # Ignore commas.
	if ($Input =~ /^\s*(\d+|\d+.|\d*.\d+)\s*([$BYTESIZE_UNITS])?B?\s*$/i) {
		$Value = $1;
		$Suffix = $2;
	}
	else {
		warn qq<Invalid value "$Hash{value}" -- no conversion possible>;
		return undef;
	}
	$Suffix = 'B' unless (defined($Suffix));
	$Suffix = uc($Suffix);
		
	# Validate the conversion factor.
	if (! exists($Hash{conversion})) {
		$Hash{conversion} = 1024;		# Using the default.
	}
	elsif ($Hash{conversion} =~ /^\s*0*([1-9]\d*)\s*$/) {
		$Hash{conversion} = $1;
	}
	else {
		warn qq<Invalid conversion value "$Hash{conversion}" -- using 1024>;
		$Hash{conversion} = 1024;
	}

        return $1 unless (defined($Suffix));	# No suffix means bytes.
	
	my $Factor = index(uc($BYTESIZE_UNITS),$Suffix);
	if (defined($Factor)) {
		return $Value*$Hash{conversion}**$Factor;
        }

=pod

=head2 JobTools::ExpandByteSize

=head3 Synopsis

    use JobTools::Utils qw(ExpandByteSize);		# Or "... qw(ByteSize);"
    my $bytes = ExpandByteSize('1K');			# Returns 1024.
    my $bytes = ExpandByteSize('3G');			# Returns 3221225472.
    my $bytes = ExpandByteSize(value=>'1K',conversion=1000);	# Returns 1000.
    my $bytes = ExpandByteSize(value=>'3G',conversion=1000);	# Returns 3000000000.

=head3 Explanation

ExpandByteSize converts numbers with common storage-unit suffixes to
the equivalent integers.


Calling parameters may be expressed in either of two formats:

=over

=item *

A single value, to be converted (e.g. "ExpandByteSize('1K')").

=item *

A hash-style list of keys and associated values (e.g. "ExpandsByteSize(value=>'1K',conversion=>1000)").
Legitimate keys are:

=over

=item -

value - the value to be converted (required)

=item -

conversion - an alternate conversion value (e.g. 1000, defaults to 1024).

=back

=back

The default suffixes recognized are
    B, K, M, G, T, P, E, Z, Y
These can be changed by setting JobTools::Utils::BYTESIZE to a string
containing the proper sequence (e.g. JobTools::Utils::BYTESIZE = 'ABCDEFG')
with the leftmost symbol representing bytes, and each subsequent letter
indicating the next higher unit.

Using the hash-based calling format, the default conversion unit of 1024
can be changed to 1000, or any other desired value.

See also: JobTools::CompressByteSize for the reverse operation.

=head2 ----------

=cut

}



# ---------------------------------------------------------
#
# CompressByteSize - convert integer bytes to KMGT...
#
sub CompressByteSize {

	my %Hash;		# Input parameters.
	if (@_ == 1) { 
	        $Hash{value} = shift;
	}
	else {
		%Hash = @_;
	}

	# Parse the value and suffix, and validate the value.
	if (! exists($Hash{value})) {
		warn qq<No conversion value provided -- no conversion possible.>;
		return undef;
	}
	my $Value = $Hash{value};
        $Value =~ s/,//g;               # Ignore commas.

	my $Conversion = (exists($Hash{conversion})?$Hash{conversion}:1024);	# Default to 1024

	# Preserve the sign, then remove it temporarily.
	my $Sign = ($Value <=> 0);
	$Value *= $Sign;	

	my $UnitsRemaining = $BYTESIZE_UNITS;
	$UnitsRemaining =~ m/^(.)(.*)$/;
	my $Unit=$1;
	$UnitsRemaining = $2;
	while ($Value >= $Conversion and $UnitsRemaining) {
		($Unit,$UnitsRemaining) = split('',$UnitsRemaining,2);
		$Value /= $Conversion;
	}
	$Hash{format}='%.1f%s' unless ($Hash{format});
	$Value *= $Sign;	# Restore the sign.
	return sprintf($Hash{format},$Value,$Unit);

=pod

=head2 JobTools::CompressByteSize

=head3 Synopsis

    use JobTools::Utils qw(CompressByteSize);		# Or "... qw(ByteSize);"
    my $bytes = CompressByteSize(1024);		# Returns '1.0K' - exact
    my $bytes = CompressByteSize(1075);		# Returns '1.0K' - rounding down
    my $bytes = CompressByteSize(1076);		# Returns '1.1K' - roounding up
    my $bytes = CompressByteSize(3221225472);		# Returns '3.0G' - larger unit
    my $bytes = CompressByteSize(value=>1075,format=>'%.3f%s');	# Returns '1.05K'.
    my $bytes = CompressByteSize(value=>1000,conversion=>1000);	# Returns '1.0K'.
    my $bytes = CompressByteSize(value=>3000000000,conversion=>1000);	# Returns '3.0G'.

=head3 Explanation

CompressByteSize converts integers to approximate values using common storage-unit suffixes.

Calling parameters may be expressed in either of two formats:

=over

=item *

A single value, to be converted (e.g. "CompressByteSize(102400)").

=item *

A hash-style list of keys and associated values (e.g. "CompressByteSize(value=>102400,conversion=>1000)").
Legitimate keys are:

=over

=item -

value - the value to be converted (required)

=item -

conversion - an alternate conversion value (e.g. 1000, defaults to 1024).

=item -

format - a display format (e.g. '%.3f %s', defaults to '%.1f%s').

=back

=back

The default suffixes recognized are
    B, K, M, G, T, P, E, Z, Y
These can be changed by setting JobTools::Utils::BYTESIZE to a string
containing the proper sequence (e.g. JobTools::Utils::BYTESIZE = 'ABCDEFG')
with the leftmost symbol representing bytes, and each subsequent letter
indicating the next higher unit.  Changing this affects both ExpandByteSize
and CompressByteSize.

The default format is "%.1f%s".  Using the hash-based call, the format can be changed
as shown above.

Using the hash-based calling format, the default conversion unit of 1024
can be changed to 1000, or any other desired value.

See also: JobTools::ExpandByteSize for the reverse operation.

=head2 ----------

=cut

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


=pod

=head2 JobTools::LoadConfigFiles

=head3 Synopsis

    # Common preface...
      use JobTools::Utils qw(LoadConfigFiles);
      my %Config;	# Where we'll store configuration parameters (unused here).
      my %Options;	# Where we'll store command line options.
      JobTools::Utils::init(config => \%Config, options => \%Options);
    # Individual examples...
      LoadConfigFiles('my.cfg');			# Read "my.cfg" 
      LoadConfigFiles(files => \@file_list);	# Load file names in @file_list.
      LoadConfigFiles(files => \@file_list, verbose=>1);	# ... and turn on verbose
      LoadConfigFiles(files => ["site.cfg", "local.cfg"]);	# Load multiple files

=head3 Explanation

LoadConfigFiles read one or more configuration files, and creates entries 
in the "Config" hash (as provided using JobTools::Utils::init).

Calling parameters may be expressed in either of two formats:

=over

=item *

A single value, naming a single file to be loaded.

=item *

A hash-style list of keys and associated values (e.g. "LoadConfigFiles(files=>\@file_list,verbose=>2)").
Legitimate keys are:

=over

=item -

files - a reference to an array of file names to be loaded as shown above.

=item -

verbose - an integer indicating the level of verbosity desired.  The default
is 0.  At present, meaningful values range from 0 to 2.

=back

=back

=head3 Configuration file format

Configuration files consist of lines of key-value pairs, in the format:

        name: value

"name" must begin in column 1, and is case-insensitive.  Lines beginning
with white-space are treated as continuations of the previous line.  Blank
lines or lines beginning with # are ignored.  The colon after the name is
optional.  Multiple lines defining the same value are combined.  The 
following three examples all result in $Config{MAILDIR} having a value of
"joe@example.com sarah@example.com".

    # Example 1 - one line
    maildir: joe@example.com sarah@example.com

    # Example 2 - continued line
    maildir: joe@example.com
        sarah@example.com

    # Example 3 - multiple lines
    maildir: joe@example.com
    maildir: sarah@example.com

=head2 ----------

=cut

}



# ---------------------------------------------------------
#
# OptFlag - generic no-value flag option processing
#
sub OptFlag {
	my($Name,$Value) = @_;
	if (exists($OptionsRef->{$Name}) and $Value) {
		# Positive value.  Increment option.
		$OptionsRef->{$Name} += $Value;
	}
	elsif (exists($OptionsRef->{$Name})) {
		# Value is 0.  Flag is being turned off.
		$OptionsRef->{$Name} = 0;
	}
	else {
		$OptionsRef->{$Name} = $Value;
	}


=pod

=head2 JobTools::OptFlag

=head3 Synopsis

    # Common preface...
      use JobTools::Utils qw(OptFlag);		# or ... qw(:Opt);
      use Getopt::Long;
      my %Config;	# Where we'll store configuration parameters (unused here).
      my %Options;	# Where we'll store command line options.
      JobTools::Utils::init(config => \%Config, options => \%Options);
    # Individual examples...
      GetOptions(
	  # Simple flag - false unless --quiet is specified on the command line
	  'quiet'    =>  \&OptFlag,
	  # Negatatable flag - can be turned on with --test, turned off with --notest.
	  'test!'    =>  \&OptFlag,
	  # Incremental flag - undefined by default, 1 if --verbose, 2 if --verbose --verbose, etc.
          'verbose+' =>  \&OptFlag,
      );
      print "Starting script\n" unless ($Options{quiet});
      print "Testing\n" if ($Options{test});
      print "Using verbose level $Options{verbose}\n" if ($Options{verbose});

=head3 Explanation

OptFlag is intended to be called from Getopt::Long to process command line options that are simple flags.
It stores the flag settings as a hash entry in the options hash as identified in JobTools::Utils::init
(referred here by the traditional hash name of $Options). It supports GetOpt::Long's negation and
increment flags, as shown above.

=head2 ----------

=cut

}


# ---------------------------------------------------------
#
# OptValue - generic single-value option processing
#
sub OptValue {
	my($Name,$Value) = @_;

        # Possible array processing options:
        #       append: 0 (default), if repeated, replace prior value with
	#		  new value
	#		1, if repeated, append the new value to the prior
	#		   value, separated by a comma

        my %Defaults = (
                'append'        => 0,
        );
        my %Parms = _GatherParms({@_}, \%Defaults);     # Gather parms into one place.

        # Is the value empty, meaning to wipe any entries to this point.
        if (!$Value) {
                # Received "--opt=".  Empty this.
                delete ($OptionsRef->{$Name});
                return;
        }
	if (!$OptionsRef->{$Name} or !$Parms{append}) {
		# No prior value, or don't append
		$OptionsRef->{$Name} = $Value;
	}
	else {
		# Prior value and appending
		$OptionsRef->{$Name} .= ",$Value";
	}

=pod

=head2 JobTools::OptValue

=head3 Synopsis

    # Common preface...
      use JobTools::Utils qw(OptValue);		# or ... qw(:Opt);
      use Getopt::Long;
      my %Config;	# Where we'll store configuration parameters (unused here).
      my %Options;	# Where we'll store command line options.
      JobTools::Utils::init(config => \%Config, options => \%Options);
    # Individual examples...
      GetOptions(
	  # Simple call using all the default options...
	  'source=s'  =>  \&OptValue,
	  # Complex call to set non-default options....
          'target=s'    =>  sub {OptValue(@_,append => 1);},
      );
      print "Source:    $Options{source}\n";
      print "Target(s): $Options{target}\n";

=head2 ----------

=head3 Explanation

OptValue is intended to be called from Getopt::Long to process command line options that accept a single value.
It captures the values and stores them as a hash entry in the options hash as identified in JobTools::Utils::init
(referred here by the traditional hash name of $Options).  In the example above, a command line option of
"--source=alpha" would result in $Options{source} having a value of "alpha".  

OptValue provides additional handling if a command line option is specified multiple times, or specified without
a value.  Using the above example, if --source is specified multiple times, the last specified value is retained.
So "--source=alpha --source=beta" would result in $Options{source} having a value of "beta".

A previously set value can be unset by specifying an empty value.  So "--source=alpha --source=" would
result in the source key in $Options being deleted (no key, as opposed to a key with an undefined value).
This can be useful in scripts where an option has a predefined value, or has previously received a value from
a configuration file, that the user now wants to remove.

Finally, when the append option is true as shown with the "targets" option above, multiple uses cause the
values to be appended, separated by commas.  So in the above example, "--target=gamma --target=delta"
will result in $Options{target} having a value of "gamma,delta".  As in the prior example, a null value
deletes the target key from %Options.

=cut

}


# ---------------------------------------------------------
#
# OptArray - generic multi-value option  processing
#
sub OptArray {

	my $Name = shift;
	my $Value = shift;
	
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

=pod

=head2 JobTools::OptArray

=head3 Synopsis

    # Common preface...
      use JobTools::Utils qw(OptArray);		# or ... qw(:Opt);
      use Getopt::Long;
      my %Config;	# Where we'll store configuration parameters.
      my %Options;	# Where we'll store command line options.
      JobTools::Utils::init(config => \%Config, options => \%Options);
    # Individual examples...
      GetOptions(
	  # Simple call using all the default options...
	  'maillist=s'  =>  \&OptArray,
	  # Complex call to set non-default options....
          'remote=s'    =>  sub {OptArray(@_,'preserve-lists' => 1);},
      );
      print "Sending e-mail to " . join(', ',@{$Options{maillist}) . "\n";
      print "Remote hosts are " . join(', ',@{$Options{remote}) . "\n";

=head3 Explanation

OptArray is intended to be called from Getopt::Long to process command line options that accept multiple values.
It captures the values and stores them as an array in the options hash as identified in JobTools::Utils::init
(referred here by the traditional hash name of $Options).  
Facilities to support splitting comma-separated lists and to delete prior list items are
provided (see options below).

When specifying non-default options, the Getopt::Long syntax requires that it be called using the "=> sub {...}"
syntax.

OptArray supports the following options:

=over

=item *

preserve-lists

By default ('preserve-lists'=>0), OptArray considers a value containing commas or embedded spaces to be a
comma/space-separated list of values.  In the above example, a command line option of '--maillist=a,b' would
be treated as equivalent to '--maillist=a --maillist=b', and the resulting @{$Options{maillist}} array would
contain two elements.  Setting preserve-lists to 1 suppresses splitting on commas/spaces.  In this case, maillist
would contain one element with a value of 'a,b'.

=item *

expand-config

By default ('expand-config'=>0), individual values are not examined beyond comma/space
and exclamation point (discussed below) processing.  If expand-config is set to 1,
then individual values are compared (case-insensitive) to the keys in the configuration hash
(traditionally "%Config").  If a matching key is found, the array value is replace with
the configuration hash value.  For example, 

  - if $Config{SERVERS} = 'a'
  - and the command line includes "--maillist=servers,test"
  - then
    - with expand-config=0 the resulting maillist values will be
      'servers' and 'test' from the command line (no interpretation)
    - with expand-config=1 the resulting maillist value will be
      'a' and 'test', because 'servers' matched a configuration
      file key and was replaced, but 'test' did not match and so
      was left as-is.

=item *

allow-delete

By default ('allow-delete'=>0), values starting with exclamation points ('!') have no special meaning.  If 
allow-delete is set to 1, values starting with exclamation points indicate values to be deleted from the
existing list of values.  (Note that ! has special meaning in most shells, and so needs to be escaped.)  For
example, a command line containing "--maillist=a,b,c  --maillist=\!b" would be equivalent to 
"--maillist=a,c", because value "b" was deleted.

This feature is most commonly used in cases
where a default list of values is provided from a configuration file, but sometimes the user
wants to remove one or more of the values for the current execution.  It is also used with expand-config=1
to use an existing configuration file list, but remove some items.  For example, if the configuration file
defines SERVERS to be 'a,b,c', then a command line could be --maillist=SERVERS,\!b to leave b out of the list.

=item *

force-delete

force-delete is primarily used internally by OptArray.  It's purpose is to support cases where allow-delete
and expand-config are both enabled and something like "--maillist=\!SERVERS" is given where SERVERS is a
configuration file hash key.  In this case, OptArray needs to expand the configuration file list, and 
then delete everything in the list.  So if the configuration file contains "SERVER: a,b,c", the above
example is equivalent to "--maillist=\!a,\!b,\!c" and not "--maillist=\!a,b,c".  force-delete supports
that.

=item *

verbose

verbose defines a value of 0 or 1 to turn verbosity off or on.  Default is 0 (off).

=back

=head2 ----------

=cut

}


# ---------------------------------------------------------
#
# OptOptionSet - Process options from an option set as if
#                they had been on the command line.
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

=pod

=head2 JobTools::OptOptionSet

=head3 Synopsis

    # Common preface...
      use JobTools::Utils qw(OptOptionSet);		# or ... qw(:Opt);
      use Getopt::Long;
      my %Config;	# Where we'll store configuration parameters.
      my %Options;	# Where we'll store command line options.
      JobTools::Utils::init(config => \%Config, options => \%Options);
    # Individual example...
      my %OptionSpecifications;		# Declare GetOpt::Long parms in a hash
      %OptionSpecifications=(
        'option-set|O=s' => sub {OptOptionSet(name => $_[1], optspec => \%OptionSpecifications);},
        'test|t'         => \&OptFlag, # Other options also in the hash, as needed
        'verbose|v'      => \&OptFlag, # Other options also in the hash, as needed
        'min-size=i'     => \&OptValue, # Other options also in the hash, as needed
        'max-size=i'     => \&OptValue, # Other options also in the hash, as needed
        'output=s'       => \&OptValue, # Other options also in the hash, as needed
      );
      # Now invoke GetOptions to process our command line options.
      die "Invalid options specified\n" unless (GetOptions(%OptionSpecifications));

=head3 Explanation

OptOptionSet is designed to be called by GetOpt::Long, as a way to allow the user to type a short
name instead of a long list of options.  It accomplishes this by allowing frequently used 
option combinations ("option sets") to be named and stored in a configuration
file.  The option set name can be specified on the command line, where it will be replaced by
the associated options.

For example, supposing the configuration file
contains:

    Saturday: --min-size=100000 --max-size=100000000
    Sunday:   --min-size=500000 --max-size=500000000
    testrun:  --min-size=100 --max-size=1000
    outfile:  --output=/home/myhome/weekly/output/myscript.out

Then running the script "myscript" as:

    myscript -O testrun

would be equivalent to:

    myscript --min-size=100 --max-size=1000

Option sets can be intermixed with other options, as:

    myscript -O testrun -v -O outfile

which is equivalent to:

    myscript --min-size=100 --max-size=1000 -v --output=/home/myhome/weekly/output/myscript.out

OptOptionSets supports the following options:

=over

=item *

name

name provides the name of the option set to be loaded from the configuration file hash 
(%Config in the above example - typically loaded with LoadConfigFiles).  "name" is required.

=item *

optspec

optspec provides a reference to the GetOpt::Long::GetOptions parameter list.  Internally
OptOptionSets calls GetOpt::Long::GetOptionsFromString with these option specifications and
the options found in the named option set.  "optspec" is required.

=item *

verbose

verbose defines a value of 0 or 1 to turn verbosity off or on.  Default is 0 (off).


=item *

suppress-output

suppress-output defines a value of 0 or 1 to present or suppress output.  Default is 0 (present).
When suppress-output is set to 1, it overrides verbose and test.  
This is used primarily by the JobTools::Utils test suite for testing, and not expected to be used in 
production.

=back

=head2 ----------

=cut

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

=pod

=head2 JobTools::RunDangerousCmd

=head3 Synopsis

    # Common preface...
    use JobTools::Utils qw(RunDangerouscmd);
    my %Config;		# Where we'll store configuration parameters.
    my %Options;	# Where we'll store command line options (unused here).
    JobTools::Utils::init(config => \%Config, options => \%Options);
    # Individual examples...
    RunDangerousCmd('rm -f /abc/def/ghi.dat');
    RunDangerousCmd('rm -f /abc/def/ghi.dat',verbose=>1);

=head3 Explanation

RunDangerousCmd is a wrapper around system().  It provides the following enhancements:

=over

=item 1

It honors the $Options{test} flag (or whatever hash was provided for options in JobTools::Utils::init).
When the test flag is set, it doesn't actually run the "dangerous" command, but instead displays
what it would have executed.  Thorough use of RunDangerousCmd means that a script can be executed
safely with the test flag, even in a production environment if necessary, to help diagnose problems.

=item 2

It honors the $Options{verbose} flag.  When the verbose flag is set, it displays a command before
executing it.  In the case that both the test and verbose flags are set, test is safer and takes
priority over verbose.

=back

Calling format consists of a single string value defining a command to be executed, optionally
followed by a series of one or more hash-style key=>value pairs.  Valid key=>value pairs are:

=over

=item *

verbose

verbose defines a value of 0 or 1 to turn verbosity off or on.  Default is 0 (off).

=item *

test

test defines a value of 0 or 1 to turn test mode off or on.  Default is 0 (off).

=item *

suppress-output

suppress-output defines a value of 0 or 1 to present or suppress output.  Default is 0 (present).
When suppress-output is set to 1, it overrides verbose and test.  
This is used primarily by the JobTools::Utils test suite for testing, and not expected to be used in 
production.

=back

=head3 Notes

=over

=item 1

Some scripts may need additional logic to run gracefully in test mode.
This happens when they rely on a prior command having been executed, but test mode
prevented it from being run.  For example:
 
    RunDangerousCmd("mkdir /tmp/abc");
    opendir(my $dh, '/tmp/abc') || die "Can't open /tmp/abc";
 
In test mode the opendir will always fail, because the "mkdir" didn't actually run.
This can be resolved by using logic similar to the following:
 
    RunDangerousCmd("mkdir /tmp/abc");
    (opendir(my $dh, '/tmp/abc') || die "Can't open /tmp/abc") unless ($Options{test});;
 
=item 2

RunDangerousCmd deletes ^H and ^M from the command output, and appends \n, for better logging and processing by JobTools::LogOutput.

=back

=head2 ----------

=cut

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
		childpost	=> \&_RunRemoteChildPostDefault,
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
			my $Cmd =   "ssh "
				  . sprintf("%-*s",$MaxLength,$Host)
				  . shell_quote(@RemoteParms) . ' '
				  ;
			my $FH;
			$Cmd =~ s/%HOST%/$Host/g;

			# Call user pre-execution run if desired.
			my $StartTime = time();
			&{$Parms{childpre}}(
				pid		=> $$,
				host		=> $Host,
				parms		=> \%Parms,
				maxhostlength	=> $MaxLength-1,
				starttime	=> $StartTime,
			)
				if (defined($Parms{childpre}));
	
			# Don't even go to remote hosts if test level 2 (-tt).
			if($Parms{test} >= 2) {
				print "Test: $Cmd\n";
				$PFM->finish(0);
				next;
			}
	
			print "Verbose: JobTools::Utils::RunRemote: Running $Cmd\n" if ($Parms{verbose} or $Parms{test});
			my($ExitCode,$Signal,$StopTime,$Elapsed);
			if (open($FH, "$Cmd |")) {
				while (<$FH>) {
					printf "%-*s %s", $MaxLength, "$Host:", $_;
				}
				close $FH;
				($ExitCode, $Signal) = ($? >> 8, $? & 127);
				$StopTime = time();
				$Elapsed = $StopTime-$StartTime;
				$Errors++ if ($ExitCode or $Signal);
			}
			else {
				warn "Unable to open ssh session to $Host: $!\n";
				$StopTime = time();
				$Elapsed = $StopTime-$StartTime;
				$Errors++;
				$Signal=127;		# Indicate that fork failed.
				$ExitCode=127;		# Indicate that fork failed.
			};
			&{$Parms{childpost}}(
				pid		=> $$,
				host		=> $Host,
				parms		=> \%Parms,
				maxhostlength	=> $MaxLength-1,
				errors		=> $Errors,
				exitcode	=> $ExitCode,
				signal		=> $Signal,
				starttime	=> $StartTime,
				stoptime	=> $StopTime,
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
# _RunRemoteChildPostDefault - default post-execution process - display status and detail.
#
sub _RunRemoteChildPostDefault {

	my %Parms = @_;
	printf "%-*s  Remote job ended at %8s, return code = %3d, signal = %3d, run time = %10ss\n",
		$Parms{maxhostlength}+1,	# +1 for the colon
		"$Parms{host}:",
		strftime("%H:%M:%S", localtime($Parms{stoptime})),
		$Parms{exitcode},
		$Parms{signal},
		FormatElapsedTime($Parms{elapsed}),
	;
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

	my($ArgvRef, $DefaultsRef, $OptPrefix) = @_;
	my %Parms;
	if ($OptPrefix) {
		$OptPrefix .= '-' unless ($OptPrefix =~ /-$/);	# Add - if missing.
	}
	else {
		$OptPrefix = '';
	}
	$OptPrefix = '' unless ($OptPrefix);
	foreach my $Item (keys(%$DefaultsRef)) {
		if (exists($ArgvRef->{$Item})) {
			# Provided in passed arguments.
			$Parms{$Item} = $ArgvRef->{$Item};
		}
		elsif (defined($OptionsRef) and exists($OptionsRef->{$Item})) {
			$Parms{$Item} = $OptionsRef->{"${OptPrefix}${Item}"};
		}
		else {
			$Parms{$Item} = $DefaultsRef->{$Item};
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


#
# UtilGetLock - try to get a lock, so we don't run multiple overlapping jobs
#
sub UtilGetLock {

	use FindBin qw($Script);
	my $LockFile;				# Name of our lock file.
	my $LOCKFH;				# Lock file handle.
	my %Defaults = (
		'verbose'		=> 0,
		'suppress-output'	=> 0,
		'test'			=> $OptionsRef->{test},
		'message'		=> qq<UtilGetLock: Skipped this job due to a conflicting job in progress per "%FILE%" dated %Y-%m-%d at %H:%M:%S\n>
	);

	my %Parms = _GatherParms({@_}, \%Defaults,'Lock');	# Gather parms into one place.

	if ($Parms{lockfile}) {
		$LockFile = $Parms{lockfile};
	}
	elsif ($^O eq 'MSWin32') {
		# Windows.  Write it to temp file area.
		$LockFile = "$ENV{TEMP}\\$Script.lock";
	}
	elsif (-w '/run') {
		# Linux/Unix.  See if we can write to /run (generally only root can).
		$LockFile = "/run/$Script.lock";
	}
	else {
		# Linux/Unix.  Can't write to /run, so use /tmp.
		$LockFile = "/tmp/$Script.lock";
	}

	print "Verbose: UtilGetLock: attempting to acquire lock for $LockFile\n"
		if ($Parms{verbose});
	if ($Parms{test}) {
		return 1;	# Dummy value.
	}
	if (!open($LOCKFH,'>>',$LockFile)) {
	        warn "Unable to create/open $LockFile: $!\n"
			unless ($Parms{'suppress-output'});
		return undef;
	}
	elsif (!flock($LOCKFH, LOCK_EX | LOCK_NB)) {
	        my $mtime = (stat($LockFile))[9];
		$Parms{message} =~ s/%FILE%/$LockFile/g;
	        warn strftime($Parms{message},localtime($mtime))
			unless ($Parms{'suppress-output'});
	        return 0;
	}
	else {
		print "Verbose: UtilGetLock: acquired lock for $LockFile\n"
			if ($Parms{verbose});
		print $LOCKFH strftime("PID $$ locked file at %Y-%m-%d %H:%M:%S\n",localtime());
		return [$LockFile,$LOCKFH];
	}
}

#
# Release the lock.
#
sub UtilReleaseLock {

	my %Defaults = (
		'verbose'		=> 0,
		'suppress-output'	=> 0,
		'test'			=> $OptionsRef->{test},
	);

	my $ArrayRef = shift;
	my %Parms = _GatherParms({@_}, \%Defaults,'Lock');	# Gather parms into one place.

	if (!defined($ArrayRef) or !defined($ArrayRef->[0]) or !defined($ArrayRef->[1])) {
		warn "UtilReleaseLock: No lock was previously acquired\n"
			unless ($Parms{'suppress-output'});
		return undef;
	}
	
	return 1 if ($Parms{test});
	my($LockFile,$LOCKFH) = @$ArrayRef;
	print "Verbose: UtilReleaseLock: attempting to release lock on $LockFile\n"
		if ($Parms{verbose});
	if (defined(fileno($LOCKFH))) {
        	close $LOCKFH;
	}
	else {
		warn "UtilReleaseLock: File handle was already closed.\n"
			unless ($Parms{'suppress-output'});
		return undef;
	}

	if (-e $LockFile) {
	        unlink $LockFile;
	}
	else {
		warn "UtilReleaseLock: Lock file was already deleted.\n"
			unless ($Parms{'suppress-output'});
		undef;
	}
	return 1;
}

#
#=pod
#
#=head2 JobTools::OptXXXX
#
#=head3 Synopsis
#
#    # Common preface...
#      use JobTools::Utils qw(XXXX);
#      use Getopt::Long;
#      my %Config;	# Where we'll store configuration parameters.
#      my %Options;	# Where we'll store command line options.
#      JobTools::Utils::init(config => \%Config, options => \%Options);
#    # Individual examples...
#
#=head3 Explanation
#
#XXXX supports the following options:
#
#=over
#
#=item *
#
#xxxx
#
#=back
#
#=head2 ----------
#
#=cut
#

1;
