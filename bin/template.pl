#!/usr/bin/perl
#
# Backup critical system components and gather recovery information.
#
use strict;
use warnings;
use LogOutput;
use Getopt::Long qw(GetOptionsFromArray :config gnu_compat permute bundling);
use Text::ParseWords;
use POSIX qw(strftime);
use Fcntl qw(:flock :mode :DEFAULT);
use File::Basename;

# Initialize variables.
my $Prog=$0;			# Get our name, for messages.
$Prog=~s/\.pl$|\.bat$//;	# Trim off the suffix, if present.
$Prog=~s".*[/\\]"";		# Trim off the path, if present.
$ENV{PATH} = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';
my @Args=@ARGV;			# Preserve orig command for ref.
my $ErrorFlag=0;		# No errors so far.
my @ConfigFiles=("/usr/local/etc/${Prog}.cfg");     # Name of config files.
my $JobLockFile;		# Name of our lock file.
my $JOBLOCKFH;			# Lock file handle.
our $Errors=0;
our %Config;
our @Parms;
our %Options;			# Options settings.

# Define our command-line options.  I use sub for everything, because
# GetOptions doesn't work right on a second call to it (which we need
# to do) with the conventional approach.
$DB::AutoTrace=$DB::AutoTrace;		# Suppress spurious warning.
our %OptionSpecifications=(
		'<>'			=>	sub {my $Arg = shift; push @Parms,$Arg if (length($Arg));},
		'always-mail|m=s'	=>	\&opt_Array,
		'always-page|p=s'	=>	\&opt_Array,
		'debug|d'		=>	sub {$DB::AutoTrace=1;},
		'error-mail|M=s'	=>	\&opt_Array,
		'error-page|P=s'	=>	\&opt_Array,
		'filter-file|F=s'	=>	\&opt_Array,
		'help|h|?!'		=>	\&opt_h,
		'option-set|O=s'	=>	\&opt_O,
		'remote-host|R=s'	=>	sub { opt_Array(@_,'allow-delete'=>1,'expand-config'=>1);},
		'test|t'		=>	sub {$Options{test} = (exists($Options{test})?$Options{test}+1:1)},
		'verbose|v'		=>	sub {$Options{verbose} = (exists($Options{verbose})?$Options{verbose}+1:1)},
);
#
our $ExitCode;

my $HostName = `hostname`;
chomp $HostName;
$HostName =~ s/\..*$//;		# Strip domain.
our $BaseDir="/usr/local/backup/$Prog";	# Set our base directory.
# ---------------------------------------------------------
#
# Load the config file.
#
foreach (@ConfigFiles) {
        LoadConfigFile($_);
}
foreach (keys(%Config)) { s/,$//;};     # Trim off trailing commas.

# ---------------------------------------------------------
#
# Process the config file defaults if present.
#
# Use the default job if it's defined and we didn't get anything on 
# the command line.
push @ARGV,(shellwords($Config{DEFAULTJOB}))
        if (join(' ',@ARGV) =~ /^\s*(\b-[tv]+)*\s*$/ && defined($Config{DEFAULTJOB}));

# Process the config file host defaults and general defaults if present.
unshift @ARGV, quotewords(" ",0,$Config{'ALLJOBS'})
        if (defined($Config{'ALLJOBS'}));

# ---------------------------------------------------------
#
# Process the command line options.
#
my @ARGVSave = @ARGV;           # In case we need to reprocess the command line later.
%Options=(verbose => 0);        # Initialize Options.
die "Invalid options specified\n" unless (GetOptions(%OptionSpecifications));
@ARGV = @ARGVSave;              # Restore @ARGV for LogOutput and second GetOptions.

# ---------------------------------------------------------
#
# Set up our logging and output filtering.
#
LogOutput({
	ALWAYS_MAIL_LIST => $Options{'always-mail'},
	ERROR_MAIL_LIST => $Options{'error-mail'},
	ALWAYS_PAGE_LIST => $Options{'always-page'},
	ERROR_PAGE_LIST => $Options{'error-page'},
	SYSLOG_FACILITY => 'user',
	VERBOSE => ($Options{verbose} >= 5? $Options{verbose}-4:0),
	FILTER_FILE => $Options{'filter-file'},
});

# Verify the command line.
die('Excess parameters on the command line: "' . join(' ',@Parms) . "\" See \"$Prog -h\" for usage.")
	if (@Parms);

if (exists($Options{'remote-host'})) {
	$Errors = RunRemote(@ARGV);
}
else {
	$Errors = RunLocally($Config{uc("host=$HostName")});
}

# ---------------------------------------------------------
#
# Release the job lock.
#
if ($JOBLOCKFH) {
        close $JOBLOCKFH;
        unlink $JobLockFile;
}


if ($ExitCode) {
	warn "$Prog failed.\n";
} else {
	#print "$Prog ended normally.\n";
}

$ExitCode=$Errors?10:0;
exit($ExitCode);


# ---------------------------------------------------------
#
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
                        chomp;
                        next if (/^\s*#/);                      # Comment.
                        next if (/^\s*$/);                      # Blank line.
                        if (/^\s+(\S.*)$/ and @Lines > 0) {
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
# ---------------------------------------------------------
#
# RunRemote - Run this elsewhere and track the results.
#
sub RunRemote {

	my @ARGV=@_;
	my $Errors = 0;

	# Analyze the remote-host list, ignoring duplicates and handling !-deletions.
	my @HostList = @{$Options{'remote-host'}};
	die "No remote hosts specified on the command line or in the configuration file.\n" unless (@HostList);

	my $MaxLength = 0;
	foreach (@HostList) { $MaxLength=($MaxLength < length($_)?length($_):$MaxLength); }
	$MaxLength++;		# Allow for trailing colon.
	my $DeleteNext=0;
	foreach (@ARGV) {
		if ($DeleteNext) {
			$_ = '';
			$DeleteNext=0;
		}
		elsif (/^--remote-host=/) {
			$_ = '';		# Delete this for remote systems.
		}
		elsif (/^-R/) {
			$_ = '';
			$DeleteNext=1;
		}
	}
	@ARGV = grep { $_ ne '' } @ARGV;
	@ARGV = map {qq<"$_">} @ARGV;

	foreach my $Host (@HostList) {
		my $Cmd =   "ssh $Host $Prog "
			  . join(' ', @ARGV) . ' '
			  . '-F SHOWALL '
			  . '--always-mail= '
			  . '2\>\&1 '
			  ;
		my $FH;

		# Don't even go to remote hosts if test level 2 (-tt).
		if($Options{test} and $Options{test} >= 2) {
			print "Test: $Cmd\n";
			next;
		}

		print "Verbose: Running $Cmd\n" if ($Options{verbose} or $Options{test});
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


# ---------------------------------------------------------
#
# RunLocally - run a sysbackup on this machine.
#
sub RunLocally {
	# ---------------------------------------------------------
	#
	# Load any host-specific options
	#
	my $HostOptions = shift;
	if ($HostOptions) {
		my @Array = quotewords(" ",0,$HostOptions);
		die "Invalid options specified\n" unless (GetOptionsFromArray(\@Array,\%Options,%OptionSpecifications));
	}

	#
	# Check for conflicting jobs.
	#
	$JobLockFile = "/var/run/$Prog.lock";
	if (!$Options{test} and !open($JOBLOCKFH,'>>',$JobLockFile)) {
	        print "Unable to create/open $JobLockFile: $!\n";
	        exit 11;
	}
	if (!$Options{test} and !flock($JOBLOCKFH, LOCK_EX | LOCK_NB)) {
	        my @stat = stat($JobLockFile);
	        my $mdate = strftime("%Y-%m-%d",localtime($stat[8]));
	        $mdate = 'today' if ($mdate eq strftime("%Y-%m-%d",localtime(time())));
	        print "Skipped this job due to a conflicting job in progress per "
	                . qq<"$JobLockFile" dated $mdate at >
	                . strftime(
	                        "%H:%M:%S",
	                        localtime((stat($JobLockFile))[8]))
	                . "\n"
	                ;
	        exit 11;
	}
}



# ---------------------------------------------------------
#
# commify - insert commas in numbers.
#
sub commify {
	local $_ = shift;
	1 while s/^(-?\d+)(\d{3})/$1,$2/;
	return $_;
}


# ---------------------------------------------------------
#
# RunDangerousCmd - run a command, or suppress it if -t specified.
#
sub RunDangerousCmd {
	my ($Cmd,$FH,$Line);
	$Cmd=join(' ',@_);
	if ($Options{test}) {
		print "Test: $Cmd\n";
		return 0;
	} else {
		print "Executing: $Cmd\n" if ($Options{'verbose'});
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
# opt_Value - generic single-value option processing
#
sub opt_Value {
	my($Name,$Value) = @_;
	$Options{$Name} = $Value;
}


# ---------------------------------------------------------
#
# opt_Array - generic multi-value option  processing
#
sub opt_Array {

	my($Name,$Value,%ArrayOpt) = @_;

	# Possible array processing options:
	#	preserve-lists:	0 (default), split on embedded spaces or commas
	#			1, don't split on embedded spaces or commas
	#	allow-delete:	0 (default), leading ! on value has no meaning
	#			1, leading ! on value means delete value from
	#				current list.
	#	force-delete:	0 (default), assume add unless ! and allow-delete=1
	#			1, delete this item regardless of leading !


	# Set a recursion limit if we don't already have one.  This helps
	# us detect list loops (listA points to listA, or A->B->A, etc.).
	$ArrayOpt{'recursion-limit'} = 64 unless ($ArrayOpt{'recursion-limit'});

	# Is the value empty, meaning to wipe any entries to this point.
	if (!$Value) {
		# Received "--opt=".  Empty this array.
		@{$Options{$Name}}=();
		return;
	}

	# Split out lists by default, unless embedded-lists are preserved.
	my @ValueList;
	if ($ArrayOpt{'preserve-lists'}) {
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
		if ($ArrayOpt{'force-delete'}) {
			# We've been told, flat-out, to delete this item.
			$AddItem = 0;
			$Value =~ s/^!+// if ($ArrayOpt{'allow-delete'});
		}
		elsif ($ArrayOpt{'allow-delete'} and $Value =~ /^!+(.*)$/) {
			# Delete is allowed, and ! is present.
			$AddItem = 0;
			$Value = $1;
		}
		
		# If config lists are permitted, see if this is a config list.
		if ($ArrayOpt{'expand-config'} and exists($Config{uc($Value)})) {
			# This is a reference to a config file list. Recurse
			# through this, in case the list contains more lists.
			die "List loop detected in --$Name=$Value"
				if ($ArrayOpt{'recursion-limit'} <= 0);
			opt_Array(
				$Name,
				$Config{uc($Value)},
				%ArrayOpt,'recursion-limit'=>($ArrayOpt{'recursion-limit'}-1),
				'force-delete'=> (1-$AddItem),
			);
			next;
		}

		# If we got here, we have a value to either add or delete.
		if ($AddItem) {
			push @{$Options{$Name}},$Value
				unless grep { $_ eq $Value } @{$Options{$Name}};
		}
		else {
			# Remove this item from the list if present.
			@{$Options{$Name}} = grep { $_ ne $Value } @{$Options{$Name}};
		}
	}
}



# ---------------------------------------------------------
#
# opt_h: Usage
#
sub opt_h {

	use FindBin qw($Bin $Script);

	my $Pager;
	if ( $ENV{PAGER} ) {
		$Pager = $ENV{PAGER};
	}
	elsif ( -x '/usr/bin/less' ) {
		$Pager = '/usr/bin/less';
	}
	else {
		$Pager = 'more'
	}
	system(qq<pod2text $Bin/$Script | $Pager>);
exit 1;
}

=pod

=head1 %Prog -   <<<<<<<<<<<<<Description>>>>>>>

=head3 Usage:  
        %Prog [flag1 ...]

        %Prog -h

=head3 Options:
        --error-mail|-e mailid: Error: Send an execution report to this
                                e-mail address if errors are detected.
        --filter|-F filter:     Filter: Use alternate error detection
                                filter file "filter".  The default is
                                to use the built-in error filter.
        --always-mail|-m addr:  Mailid: Send an execution report to
                                this e-mail address.
        --always-page|-p addr:  Page: Send a very brief message
                                (suitable for a pager) to this e-mail
                                address when this job completes.
        --error-page|-P addr:   Page error: Send a very brief message to
                                this e-mail address if errors are
                                detected in this job.
        --option-set|-O config: Insert the "config" configuration options
                                from /usr/local/etc/%Prog.cfg
                                into the command line at this point.
	--remote-host|-R host	Remote: Run this on one or more remote
				hosts.  "host" may be a host name, an
				IP address, a configuration file entry
				name, or a comma or space separated list of
				any mix of these.  This option may also be
				repeated to append to the list.  Host names
				preceeded by ! are removed from the list.
				This is primarily to allow a configuration
				file list to be included, but some of the
				hosts in the list to subsequently be excluded.
        --test|-t:              Test: echo commands instead of running them.
        --verbose|-v:           Verbose: echo commands before running them.
				May be used multiple times to increase verbosity.
        --help|-h:              Help: display this panel

=head3 Parameters:
        (none)

=head3 Configuration files

Configuration data may be loaded from the configuration files.  These files
form key-value pairs that $Prog may reference.  The syntax of the file is:

        name: value

"name" must begin in column 1, and is case-insensitive.  Lines beginning
with white-space are treated as continuations of the previous line.  Blank
lines or lines beginning with # are ignored.

Several "names" are reserved, as follows:

=over

=item *
Alljobs: any value listed here is prepended to the command line before
command line processing begins.  This permits default options to be
set.

=item *
Defaultjob: any value listed here is used as the command line if no
command line options are specified.

=item *
Host=name: any values here are processed only when the machine 
hostname matches "name".  Examples:

	host=server1: -x /usr/local/data

=item *
Include: any value here is treated as another configuration file, which
is loaded immediately.

=back

=head3 Return codes:
        0       :       Normal termination
        1       :       Help panel displayed.
        2       :       Invalid or unrecognized command line options.
        3       :       Invalid or unrecognized command line option value.
        4       :       Incorrect command line parameters.
        5       :       Unexpected message found in output.


=head3 Notes:

=cut

__END__
#
# ---------------------------------------------------------
#
# Output filters.  The syntax is: type pattern
#
#  Type:        Ignore - Don't display this message, it's not interesting.
#               LogOnly - Write this message to the syslog and log file, but
#                       don't display it on STDOUT.
#               Show - Display this message, but it's not an error condition.
#               # - This is a comment, ignore it.
#
#  Pattern:     an ordinary perl pattern.  All patterns for a given score
#               are joined by logical OR conditions.
#
#  Notes:
#       1) The "Type" parameter may be specified in upper, lower, or mixed case.
#       2) All messages go to the syslog, regardless of this filter.
#
IGNORE	"^\s*(\S+:\s*)?\S+:\s+Starting \S+ at \d+:\d+:\d+ on \S+, \d\d\d\d-\d\d-\d\d...\s*$"
IGNORE	"^\s*\S+:\s*\S+ ended normally with status 0 and signal 0"
IGNORE	"^\s*\S+:\s*\S+ ended on \S+, \d\d\d\d-\d\d-\d\d at \d\d:\d\d:\d\d"
IGNORE	"^\s*\S+:\s*\S+:\s+\S+ ended normally with status 0 and signal 0"
IGNORE	"^\s*\S+:\s*Remote job exited with return code 0 and signal 0$"
IGNORE	"^\s*\S+:\s+\S+ started on \S+ on \S+, \d+-\d+-\d+ at \d+:\d+:\d+"
IGNORE	"^\s*\S+:\s+Command: "
LOGONLY "^\s*\S+ started on \S+ on \S+, \d+-\d+-\d+ at \d+:\d+:\d+"
LOGONLY "^\s*Command: "
SHOW	"^\s*(\S+:\s*)?(Test|Executing|Verbose|debug):"
SHOW	"^\s*(\S+:\s*)?Starting \S+ at \d+:\d+:\d+ on \S+, \d\d\d\d-\d\d-\d\d...\s*$"
SHOW	"^\s*\S+ ended normally with status 0 and signal 0$"
SHOW	"^\s*\S+ ended on \S+, \d\d\d\d-\d\d-\d\d at \d\d:\d\d:\d\d"
