#!/usr/bin/perl
#
# >>>> Description <<<<
#
use strict;
use warnings;
use Getopt::Long qw(GetOptionsFromArray :config gnu_compat permute bundling);
use Text::ParseWords;
use POSIX qw(strftime);
use File::Basename;
use LogOutput;
use JobTools::Utils qw(:Opt :Lock LoadConfigFiles RunRemote RunDangerousCmd);

# Initialize variables.
my $Prog=$0;			# Get our name, for messages.
$Prog=~s/\.pl$|\.bat$//;	# Trim off the suffix, if present.
$Prog=~s".*[/\\]"";		# Trim off the path, if present.
$ENV{PATH} = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';
my @Args=@ARGV;			# Preserve orig command for ref.
my $ErrorFlag=0;		# No errors so far.
my @ConfigFiles=("/usr/local/etc/${Prog}.cfg");     # Name of config files.
our $Errors=0;
our %Config;
our @Parms;
our %Options;			# Options settings.
JobTools::Utils::init(config => \%Config, options => \%Options);

# Define our command-line options.  I use sub for everything, because
# GetOptions doesn't work right on a second call to it (which we need
# to do) with the conventional approach.
$DB::AutoTrace=$DB::AutoTrace;		# Suppress spurious warning.
my %OptionSpecifications;
%OptionSpecifications=(
	'<>'			=>	sub {my $Arg = shift; push @Parms,$Arg if (length($Arg));},
	'always-mail|m=s'	=>	\&OptArray,
	'always-page|p=s'	=>	\&OptArray,
	'debug|d'		=>	sub {$DB::AutoTrace=1;},
	'error-mail|M=s'	=>	\&OptArray,
	'error-page|P=s'	=>	\&OptArray,
	'filter-file|F=s'	=>	\&OptArray,
	'help|h|?!'		=>	\&opt_h,
	'option-set|O=s'	=>	sub {OptOptionSet(name => $_[1],optspec => \%OptionSpecifications);},
	'remote|R=s'		=>	sub {OptArray(@_,'allow-delete'=>1,'expand-config'=>1);},
	'test|t'		=>	\&OptFlag,
	'verbose|v'		=>	\&OptFlag,
);
our $ExitCode;

my $HostName = `hostname`;
chomp $HostName;
$HostName =~ s/\..*$//;		# Strip domain.
our $BaseDir="/usr/local/backup/$Prog";	# Set our base directory.

# ---------------------------------------------------------
#
# Load the config file.
#
LoadConfigFiles(files => \@ConfigFiles);

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

# ---------------------------------------------------------
#
# Verify the command line and run the job.
#
die('Excess parameters on the command line: "' . join(' ',@Parms) . "\" See \"$Prog -h\" for usage.")
	if (@Parms);

# ---------------------------------------------------------
#
# Get the job lock.
#
my $Lock = UtilGetLock();
exit 11 unless ($Lock);

# ---------------------------------------------------------
#
# Run the job.
#
if (exists($Options{remote}) and @{$Options{remote}} > 0) {
        unshift @ARGV,$Prog;
        push @ARGV,split(/\s+/,'-F SHOWALL --always-mail= --remote= -O :remote=%HOST%');
        $Errors = RunRemote(argv => \@ARGV);
}
else {
	$Errors = RunLocally($Config{uc("host=$HostName")});
}

# ---------------------------------------------------------
#
# Release the job lock.
#
UtilReleaseLock($Lock);

# ---------------------------------------------------------
#
# Wrap up.
#
if ($ExitCode) {
	warn "$Prog failed.\n";
} else {
	#print "$Prog ended normally.\n";
}

$ExitCode=$Errors?10:0;
exit($ExitCode);


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

	# -------------- add code here -----------------

}


# ---------------------------------------------------------
#
# opt_h: Usage
#
sub opt_h {

	use FindBin qw($RealBin $RealScript);

	system(qq<pod2text $RealBin/$RealScript | sed "s/%Prog/$Prog/g" | more>);
exit 1;
}

=pod

=head1 %Prog -  

=head3 Usage:  
        %Prog [flag1 ...]

        %Prog -h

=head3 Options:
        --always-mail|-m addr:  Mailid: Send an execution report to
                                this e-mail address.
        --always-page|-p addr:  Page: Send a very brief message
                                (suitable for a pager) to this e-mail
                                address when this job completes.
        --error-mail|-e mailid: Error: Send an execution report to this
                                e-mail address if errors are detected.
        --error-page|-P addr:   Page error: Send a very brief message to
                                this e-mail address if errors are
                                detected in this job.
        --filter|-F filter:     Filter: Use alternate error detection
                                filter file "filter".  The default is
                                to use the built-in error filter.
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
# See LogOutput.pm for an explanation of output filtering.
IGNORE	"^\s*(\S+:\s*)?$"
IGNORE	"^\s*(\S+:\s*)?\S+:\s+Starting \S+ at \d+:\d+:\d+ on \S+, \d\d\d\d-\d\d-\d\d...\s*$"
IGNORE	"^\s*\S+:\s*\S+ ended normally with status 0 and signal 0"
IGNORE	"^\s*\S+:\s*\S+ ended on \S+, \d\d\d\d-\d\d-\d\d at \d\d:\d\d:\d\d"
IGNORE	"^\s*\S+:\s*\S+:\s+\S+ ended normally with status 0 and signal 0"
IGNORE	"^\s*\S+:\s+\S+ started on \S+ on \S+, \d+-\d+-\d+ at \d+:\d+:\d+"
IGNORE	"^\s*\S+:\s+Command: "
LOGONLY "^\s*\S+ started on \S+ on \S+, \d+-\d+-\d+ at \d+:\d+:\d+"
LOGONLY "^\s*Command: "
SHOW	"^\s*(\S+:\s*)?(Test|Executing|Verbose|debug):"
SHOW	"^\s*(\S+:\s*)?Starting \S+ at \d+:\d+:\d+ on \S+, \d\d\d\d-\d\d-\d\d...\s*$"
SHOW	"^\s*\S+ ended normally with status 0 and signal 0$"
SHOW	"^\s*\S+ ended on \S+, \d\d\d\d-\d\d-\d\d at \d\d:\d\d:\d\d"
SHOW	"^\s*\S+:\s*Remote job ended at ..:..:.., return code =   0, signal =   0, run time = "
