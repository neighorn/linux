# Copyright (c) 2005-2009, Martin Consulting Services, Inc.
# Licensed under the Lesser Gnu Public License (LGPL).
# 
# ABSOLUTELY NO WARRENTIES EXPRESSED OR IMPLIED.  ANY USE OF THIS
# CODE IS STRICTLY AT YOUR OWN RISK.
#
#		POD documentation appears at the end of this file.
#
use strict;
use warnings;
package	LogOutput;
require	Exporter;
use Mail::Sendmail;
use LogOutput_cfg;
use POSIX qw(strftime);
use Sys::Syslog;
use File::Glob;

our @ISA	= qw(Exporter);
our @EXPORT	= qw(LogOutput);
our @EXPORT_OK	= qw(WriteMessage $Verbose $MailServer $MailDomain $Subject);
our $Version	= 3.11;

our($ExitCode);			# Exit-code portion of child's status.
our($RawRunTime);		# Unformatted run time.
our($MailServer);		# Who sends our mail.
our($MailDomain);		# What's our default domain (i.e. "example.com").
our($READLOGFILE_FH);		# File handle.
our($WRITELOGFILE_FH);		# File handle.
our($Verbose);			# Do we print diagnostics?
our($Subject);			# Do they want to alter the subject line?

# Package variables.  Private to this file, but used in multiple routines.
my %Options;			# We'll store all our command line parameters and such here.
my $PID;			# PID of the child, that will do the
my $ErrorsDetected = 0;		# Flags whether errors were detected.
my $HostName;			# Our host name.
				# productive work while we monitor it.
#	Tests used to determine how to process messages.
my($NormalTest);		# Reference to anonymous subroutine.
my($IgnoreTest);		# Reference to anonymous subroutine.
my($MailOnlyTest);		# Reference to anonymous subroutine.


sub LogOutput {

	# Declare our local variables.
	my $DeleteMailFile;		# Do we delete the log file on exit?
	my $StdOut;			# Should this message go to STDOUT?
	my $Prefix;			# Message prefix ("   " or "-> ");
	my $Status;			# Returned status from child process.
	my $SignalCode;			# Signal code portion of child's status.
	my $RunTime;			# How long we ran.
	my $TimeStamp;			# Start/stop time stamp
	my $StopTime;			# Stop time.

	our($StartTime)=time();		# Record our start time.
	
	# Set %Options based on our defaults, site defaults and calling options.
	# All output is stored in %Options.
	_SetOptions(@_);

	# Clean up e-mail addresses (convert to list, append error lists to
	# "always" lists, remove duplicates).  All input comes from %Options,
	# and all output goes there too.
	_CleanEmailLists();

	# LogOutput can't run under debug mode.  Can't figure out the fork logic.
	{
		no warnings "once";
		if (defined($DB::single)) {
			warn "$Options{PROGRAM_NAME} is in debug mode - LogOutput call suppressed.\n";
			return;
		}
	}

	# Unbuffer stdout and stderr.
	select STDERR;
	$|=1;
	select STDOUT;
	$|=1;

	# Set our host name.
	if ($^O eq 'MSWin32') {
		$HostName = $ENV{'COMPUTERNAME'};
	} else {
		$HostName = `hostname`;	# Get host name.
		chomp $HostName;	# Remove trailing \n;
		$HostName =~ s/\..*//;	# Remove domain name.
	}

	# Prepare our log file.
	$DeleteMailFile = _PrepareMailFile();

	# If we're going to the Syslog, set that up now.
	if ($Options{SYSLOG_FACILITY}) {
		if ($^O =~ /^(os2|MSWin32|MacOS)$/) {
			require Sys::Syslog;
			warn "LogOutput: Syslog is not supported under this operating system.";
			$Options{SYSLOG_FACILITY}=0;
		} else {
			my $options = $Options{SYSLOG_OPTIONS};
			$options='pid' unless (defined($options));
			openlog($Options{PROGRAM_NAME},$options,$Options{SYSLOG_FACILITY});
		}
	}

	# Load in our filters.  Input file comes from %Options.  Output
	# goes into $NormalTest, $IgnoreTest, $MailOnlyTest.
	_LoadFilters();

	# Now that we made it this far, we're safe to spin off the child process

	# Fork off child process to run the real job.  Parent will stay here
	# to monitor child's sysout and exit code.
	if ($ eq 'MSWin32') {
		# We're windows.  Don't have -|
		pipe LOGREADHANDLE, LOGWRITEHANDLE or die;
		$PID = fork();
		die "fork() failed: $!" unless defined $PID;
		if ($PID) {
			# In parent.
			close LOGWRITEHANDLE;
		}
		else {
			# In child.
			close LOGREADHANDLE;
			close STDOUT;	# Crit. in Win32 to avoid hangs.
			open(STDOUT,">&LOGWRITEHANDLE")
				or die "Unable to redirect STDOUT into pipe.";
			close LOGWRITEHANDLE;	# Have it as STDOUT now.
		}
	}
	else {
		$PID=open(LOGREADHANDLE, "-|");	# Fork off a child and read it's output.
	}

	# How did that for go?  Are we the child, parent, or did it fail?
	if ($PID == 0) {
		# We're the child.  Close handles only needed by the parent.
		close($WRITELOGFILE_FH) if ($Options{MAIL_FILE});
		closelog() if ($Options{SYSLOG_FACILITY});

		# Unbuffer our pipe.
		select STDOUT;
		$|=1;

		# Redirect STDERR into the pipe, too, so we get it all.
		close STDERR; # Crit in Win32 to avoid hangs.
		open(STDERR, ">&STDOUT") or
                	die("Unable to redirect STDERR: $!");
		select STDERR;		# Is it necessary to unbuffer
		$|=1;			# STDERR in this case?
		select STDOUT;

		# Begin our log.
		$TimeStamp=strftime("%m/%d/%Y at %H:%M:%S",localtime($));
		my @ArgList = @main::ARGV;
		foreach (@ArgList) { 
			$_ = '' unless defined($_)
		};
		printf STDOUT "$Options{PROGRAM_NAME} started on $HostName on %s\nCommand: $0 %s\n\n",
        		"$TimeStamp", join(' ',@ArgList);

		return;		# Run main code.
	} elsif (!defined($PID)) {
		# PID undefined.  We failed to fork.
		die "Cannot fork LogOutput process: $!";
	};	# Fall through if we're the parent.

	# We're the parent.
	$0="$Options{PROGRAM_NAME} -- output logger";		# Make us easy to find in ps.
	
	# Read and process everything from child's STDOUT.
	while (<LOGREADHANDLE>) {
		chomp;
		print "LogOutput: Read: $_\n" if $Options{VERBOSE} > 5;

		# Run it through the filters, and log/print as appropriate.
		$ErrorsDetected += _FilterMessage($_);
	}

# The output is done.
if ($ErrorsDetected >= 1) {
	$ErrorsDetected += _FilterMessage("Unexpected messages (\"->\") detected in $Options{PROGRAM_NAME} execution.");
}

# Check the status of the child.
close LOGREADHANDLE; #Ignore return from close.  Always says child went away.
waitpid($PID,0) if ($^O eq 'MSWin32');
$Status=$?;
$ExitCode=$Status>>8;
$SignalCode=$Status & 0x7F;  # This is correct.  0x80 indicates core dump or not.
print "LogOutput: Child ended with Status=$Status (Exit Code = $ExitCode, Signal=$SignalCode)\n"
	if ($Options{VERBOSE});

$StopTime=time();
$TimeStamp=strftime("%m/%d/%Y at %H:%M:%S",localtime($StopTime));
$RunTime=$StopTime-$;
my($RunSec,$RunMin,$RunHour,$RunDay);
$RunSec = $RunTime % 60;		# localtime($RunTime) gave weird results
$RunTime=($RunTime - $RunSec)/60;
$RunMin = $RunTime % 60;
$RunTime=($RunTime - $RunMin)/60;
$RunHour = $RunTime % 24;
$RunDay=($RunTime - $RunHour)/24;
$RunTime = "$RunSec second" . ($RunSec == 1?'':'s');
$RunTime = "$RunMin minute" . ($RunMin == 1?'':'s') . ", $RunTime"
	if ($RunDay+$RunHour+$RunMin);
$RunTime = "$RunHour hour" . ($RunHour == 1?'':'s') . ", $RunTime"
	if ($RunDay+$RunHour);
$RunTime = "$RunDay day" . ($RunDay == 1?'':'s') . ", $RunTime"
	if ($RunDay);
$RawRunTime="$RunDay:$RunHour:$RunMin:$RunSec";
$Options{MAIL_FILE_PREFIX}='';		# Don't prefix wrap-up messages.
$ErrorsDetected += _FilterMessage("   Job ended on $TimeStamp - run time: $RunTime");

# Force an error if the job exited with a bad status code or signal.
$ErrorsDetected++ if ($SignalCode != 0);
if ($ErrorsDetected == 0) {
	# No errors so far.  Check their return code against our list of valid return codes.
	my $Found = 0;
	foreach (@{$Options{NORMAL_RETURN_CODES}}) {
		if ($ExitCode == $_) {
			$Found++;
			last;
		};
	};
	$ErrorsDetected++ unless ($Found);	# Not a valid return code.
}

if ($ErrorsDetected > 0) {
	# Force a non-zero exit if there was an error the child didn't detect.
	$ExitCode = 5 if ($ExitCode == 0);
	$ErrorsDetected += _FilterMessage("Job failed with status $ExitCode and signal $SignalCode");
	close($WRITELOGFILE_FH) if ($Options{MAIL_FILE});
} else {
	$ErrorsDetected += _FilterMessage(
		"Job ended normally with status $ExitCode and signal $SignalCode");
	close($WRITELOGFILE_FH) if ($Options{MAIL_FILE});
}

# Tweak up the subject line, now that we know how we ended.
$Options{MAIL_SUBJECT} = _MakeSubstitutions($Options{MAIL_SUBJECT}, $StartTime);
$Options{MAIL_SUBJECT} =~ s/^\s*//;		# Strip leading blanks.
$Options{MAIL_SUBJECT} =~ s/\s*$//;		# Strip trailing blanks.
$Options{MAIL_SUBJECT} =~ s/\s\s/ /g;	# Strip embedded multiple blanks.
	
# Send mail if requested.
if ($ErrorsDetected) {
	_SetupMail($Options{ERROR_MAIL_LIST}, $Options{MAIL_SUBJECT}, $Options{MAIL_FILE}, $Options{MAIL_FROM});
	_SetupMail($Options{ERROR_PAGE_LIST}, $Options{MAIL_SUBJECT}, '', $Options{MAIL_FROM}) ;
} else {
	_SetupMail($Options{ALWAYS_MAIL_LIST}, $Options{MAIL_SUBJECT}, $Options{MAIL_FILE}, $Options{MAIL_FROM});
	_SetupMail($Options{ALWAYS_PAGE_LIST}, $Options{MAIL_SUBJECT}, '', $Options{MAIL_FROM});
}

my $CleanupSub = $Options{CLEAN_UP};
if (defined($CleanupSub)) {
	# They specified a cleanup subroutine.
	if (defined(&$CleanupSub)) {
		# ... and it exists.
		&$CleanupSub($ExitCode,$Options{MAIL_FILE},$ErrorsDetected)
	}
	else {
		# ... and it doesn't exist.
		warn "LogOutput: Subroutine $CleanupSub does not exist.";
	}
}

unlink($Options{MAIL_FILE})
	if ($Options{MAIL_FILE} && -e $Options{MAIL_FILE} && $DeleteMailFile);

exit $ExitCode;

*main::DATA{IO};	# Dummy ref. to main::DATA to resolve false -w alert.
}


#
# _SetOptions - set our options (%Options) based on defaults, site defaults,
# 		and calling parameters.
# 
sub _SetOptions {

	# First, build a list of valid options.
	my %ValidOptions = (
		ALWAYS_MAIL_LIST => 1,
		ALWAYS_PAGE_LIST => 1,
		CLEAN_UP => 1,
		DEBUG => 1,
		ERROR_MAIL_LIST => 1,
		ERROR_PAGE_LIST => 1,
		FILTER_FILE => 1,
		#LOG_FILE => 1,
		MAIL_FILE_PREFIX => 1,
		MAIL_FILE => 1,
		MAIL_FROM => 1,
		MAIL_DOMAIN => 1,
		MAIL_LIMIT => 1,
		MAIL_SERVER => 1,
		MAIL_SUBJECT => 1,
		NORMAL_RETURN_CODES => 1,
		PROGRAM_NAME => 1,
		SYSLOG_FACILITY => 1,
		SYSLOG_OPTIONS => 1,
		VERBOSE => 1,
	);

	# Set our program default values.  May be overridden by site defaults
	# or by the arguments we were called with.
	$Options{ALWAYS_MAIL_LIST}=[];
	$Options{ALWAYS_PAGE_LIST}=[];
	$Options{CLEANUP}=undef();
	$Options{ERROR_MAIL_LIST}=[];
	$Options{ERROR_PAGE_LIST}=[];
	$Options{MAIL_FILE_PREFIX}='';
	$Options{MAIL_FILE}='';
	$Options{MAIL_FROM}='%U@%O';
	$Options{MAIL_SERVER}='127.0.0.1';
	$Options{MAIL_DOMAIN}='';
	$Options{MAIL_LIMIT}=undef();
	$Options{NORMAL_RETURN_CODES}=[0];
	$Options{PROGRAM_NAME}=(caller(1))[1];	# Get the caller's filename.
	$Options{PROGRAM_NAME}=~ s"^.*[/\\]"";	# Strip path.
	$Options{PROGRAM_NAME}=~ s"\..*?$"";	# Strip suffix.
	$Options{MAIL_SUBJECT} = "%* %m/%d %C %N %E %*%*%*";
	$Options{VERBOSE}=0;

	# Now load our site defaults.  May be overridden by calling args.
	# We support two formats, so we start by figuring out which is 
	# being used.
	my @Config = LogOutput_cfg();
	if (ref(\$Config[0]) eq 'SCALAR') {
		# V1/2 LogOutput_cfg.
		$Options{MAIL_SERVER}=$Config[0];
		$Options{MAIL_DOMAIN}=$Config[1];
	} 
	else {
		# V3 LogOutput_cfg.
		my $HashRef = $Config[0];
		foreach my $key (keys(%$HashRef)) {
			if ($ValidOptions{$key}) {
				$Options{$key} = $$HashRef{$key};
				print "LogOutput: Set $key to $$HashRef{$key} from LogOutput_cfg\n"
					if ($Options{Verbose});
			}
			else {
				warn "LogOutput: Invalid option '$key' passed from LogOutput_cfg -- ignored.\n";
				$Options{$key} = undef;
			}
		}
	}

	# Finally, get our calling parameters.  Again we support two formats,
	# a list of seven scalars (deprecated) or a hash reference.
	if (ref(\$_[0]) eq 'SCALAR') {
		# V1/V2 compatibility mode.  Copy fixed list and check old globals.
		my @ParmKeys = (
			'FILTER_FILE','SYSLOG_FACILITY','MAIL_FILE','ALWAYS_MAIL_LIST',
			'ERROR_MAIL_LIST','ALWAYS_PAGE_LIST','ERROR_PAGE_LIST');
		foreach (@ParmKeys) {
			$Options{$_} = shift;
		}
		# Copy V1/2 global variables into the Options hash if set.
		$Options{VERBOSE} = $Verbose if ($Verbose);
		$Options{MAIL_SUBJECT} = '%*' . $Subject . ' %E' if ($Subject);
		$Options{MAIL_SERVER} = $MailServer if ($MailServer);
		$Options{MAIL_DOMAIN} = $MailDomain if ($MailDomain);
		$Options{PROGRAM_NAME} = $main::Prog if ($main::Prog);
		$Options{CLEAN_UP} = \&main::Cleanup if (defined(&main::Cleanup));
	}
	else {
		# Using V3 hash instead.
		my $HashRef=shift;
		foreach my $key (keys(%$HashRef)) {
			$key = uc($key);
			if ($ValidOptions{$key}) {
				$Options{$key} = $$HashRef{$key};
				print "LogOutput: Set $key to $$HashRef{$key} from calling arguments\n"
					if ($Options{Verbose});
			}
			else {
				warn "LogOutput: Invalid option '$key' passed to LogOutput -- ignored.\n";
				$Options{$key} = undef;
			}
		}
	}
	$Options{VERBOSE} = 0 unless defined($Options{VERBOSE});	# In case supplied $opt_v is undef.
}


#
# _CleanEmailLists - Clean up e-mail addresses.
# 
sub _CleanEmailLists {

	# Convert mailing list scalars to actual lists if necessary.
	foreach ('ERROR_MAIL_LIST', 'ERROR_PAGE_LIST', 'ALWAYS_MAIL_LIST', 'ALWAYS_PAGE_LIST') {
		next unless (defined($Options{$_}));
		if (!ref($Options{$_})) {
			# This is a long string of mail IDs, not a list.
			$Options{$_} =~ s/^\s*//;	# Remove leading spaces.
			$Options{$_} =~ s/\s*$//;	# Remove trailing spaces.
			my @Array = [ split(/[\s,]+/,$Options{$_}) ];
			$Options{$_} = [ split(/[\s,]+/,$Options{$_}) ];
		}
	}

	# Tidy up the mailing lists.  Error lists will be handled as part of the append operation.
	$Options{ALWAYS_MAIL_LIST} = [ _StripDuplicates(@{$Options{ALWAYS_MAIL_LIST}}) ];
	$Options{ALWAYS_PAGE_LIST} = [ _StripDuplicates(@{$Options{ALWAYS_PAGE_LIST}}) ];

	# Append the always mail lists onto the error lists, since people that always get the mail should
	# therefore get it if there are errors.
	$Options{ERROR_MAIL_LIST} = [ _StripDuplicates(@{$Options{ERROR_MAIL_LIST}},@{$Options{ALWAYS_MAIL_LIST}}) ];
	$Options{ERROR_PAGE_LIST} = [ _StripDuplicates(@{$Options{ERROR_PAGE_LIST}},@{$Options{ALWAYS_PAGE_LIST}}) ];

}


#
# _PrepareMailFile
# 
sub _PrepareMailFile {

	my $DeleteMailFile;		# Do we delete the output file when done?
	if (!$Options{MAIL_FILE} && @{$Options{ERROR_MAIL_LIST}} > 0) {
		# They didn't provide a log file, but we need one for e-mail.
		# Note: ERROR_MAIL_LIST is always >= ALWAYS_MAIL_LIST, since
		# AML is appended to EML.
		if ($ eq 'MSWin32') {
			($Options{MAIL_FILE}="$ENV{'TEMP'}/$Options{PROGRAM_NAME}.$$.log") =~ s'\\'/'g;
		} else {
			$Options{MAIL_FILE}="/tmp/$Options{PROGRAM_NAME}.$$.log";
		}
		$DeleteMailFile=1;		# Don't keep it after we're done.
	} else {
		# They provided a log file, or we don't need one.
		$DeleteMailFile=0;
	}

	# If we're logging, Make sure the file name is valid.
	if ($Options{MAIL_FILE}) {
		# Make sure it's valid.
		if ($Options{MAIL_FILE} =~ /^([a-zA-Z]:)?[a-zA-Z0-9_\\\/. ~-]+$/) {
			$Options{MAIL_FILE}=untaint($Options{MAIL_FILE});
		} else {
			warn "LogOutput: Unable to open $Options{MAIL_FILE} invalid symbol in file name";
			$Options{MAIL_FILE}='';
			$DeleteMailFile=0;
		}
	}

	# If we're logging, delete the existing log file.
	if ($Options{MAIL_FILE}) {
		# Make sure it doesn't already exist.
		if (-e $Options{MAIL_FILE}) {
			# File already exists.  Delete it.  Can't just write
			# over it for security reasons (may have wrong perms).
			if (! unlink($Options{MAIL_FILE})) {
				# Couldn't kill it.
				warn "LogOutput: Unable to delete $Options{MAIL_FILE} $!";
				$Options{MAIL_FILE}='';		#We can't log.
				$DeleteMailFile=0;
			}
		}
	}

	# If we're logging, open the log.
	if ($Options{MAIL_FILE}) {
		# Open the log file.
		umask(0077);	# Set our umask.
		if (open($WRITELOGFILE_FH, '>', $Options{MAIL_FILE})) {
			select $WRITELOGFILE_FH;
			$|=1;		# Keep this file unbuffered.
			select STDOUT;	# Undo prior select.
		} else {
			warn "LogOutput: Unable to open $Options{MAIL_FILE} $!";
				$Options{MAIL_FILE}='';		#We can't log.
				$DeleteMailFile=0;
		}
	}
	return $DeleteMailFile;
}



#
# _LoadFilters
# 
sub _LoadFilters {
	my $FilterHandle;		# Handle, in case they don't use DATA.
	my $Type;			# Type of pattern from FilterHandle file
	my $Pattern;			# Pattern from FilterHandle file.
	my $PatternNum;			# Pattern record number.
	my @IgnorePatterns;		# Collected patterns from FilterHandle.
	my @NormalPatterns;		# Collected patterns from FilterHandle.
	my @MailOnlyPatterns;		# Collected patterns from FilterHandle.

	# Get a list of our filter file(s).
	my @FilterList;
	if ($Options{FILTER_FILE}) {
		@FilterList = <$Options{FILTER_FILE}>;
		print "LogOutput: glob of $Options{FILTER_FILE} -> " . join(', ',@FilterList) . "\n"
			if ($Options{VERBOSE});
		die("Unable to find filter file $Options{FILTER_FILE}\n") unless (@FilterList);
	}
	else {
		push @FilterList,'__DATA__';
	}

	# Process each filter file.
	foreach my $FilterFile (@FilterList) {
		# They provided us with a filter file.
		if ($FilterFile eq '__DATA__') {
			# They didn't provide us with a filter file.  Use DATA.
			$FilterHandle=*main::DATA{IO};
			print "LogOutput: Loading filters from DATA\n" if $Options{VERBOSE};
		}
		else {
			print "LogOutput: Loading filters from $FilterFile\n" if $Options{VERBOSE};
			if (!open($FilterHandle,$FilterFile)) {
				warn("Unable to open $FilterFile $!\n");
			}
		}
	
		# Build arrays of our scoring patterns.
		$PatternNum=0;
		while (<$FilterHandle>) {
			$PatternNum++;
			print "LogOutput: \tread $PatternNum: $_\n"
				if ($Options{VERBOSE} >= 2);
			chomp;
	
			# Split out the type from the pattern.
			($Type,$Pattern)=split('\s+',$_,2);
	
			# Skip comments and strip white space.
			next if ($Type =~ /^\s*#/);	# Comment.
			$Pattern=~s/\s+$//;		# Strip trailing whitespace.
	
			# Check for syntax errors.
			eval "qr$Pattern;";		# Check pattern for syntax problems.
			if ($@) {
				print qq<LogOutput: \tSyntax error in $FilterFile line $PatternNum ("> 
					. substr($Pattern,0,50)
					. qq<"): $@\n>;
				next;
			}
	
			# Add to the appropriate pattern list.
			if ($Type =~ /ignore/i) {
				# Add it to this array.
				push @IgnorePatterns, $Pattern;
			} elsif ($Type =~ /show/i) {
				# Add it to this array.
				push @NormalPatterns, $Pattern;
			} elsif ($Type =~ /mailonly|logonly/i) {
				# Add it to this array.
				push @MailOnlyPatterns, $Pattern;
			} else {
				warn "LogOutput: Invalid type $Type in pattern record $PatternNum -- ignored.\n";
			}
		}
		close ($FilterHandle);
	}

	# Add our standard messages on the end of the normal list, so they don't
	# get flagged as errors.  Note that ignore patterns take precedence, so
	# the caller can still choose to ignore them.
	push @MailOnlyPatterns, '"^Job ended normally with status \d and signal \d+"';
	push @MailOnlyPatterns, '"^\s*Job ended on \d+.\d+.\d\d\d\d"';

	# Now turn them in to patterns within three anonymous subroutines.  This
	# means the patterns only get compiled once, making our pattern
	# matches run much faster.

	$IgnoreTest = _CompilePatterns("Ignore",@IgnorePatterns);
	$NormalTest = _CompilePatterns("Show",@NormalPatterns);
	$MailOnlyTest = _CompilePatterns("MailOnly",@MailOnlyPatterns);

}



#
# _StripDuplicates - strip duplicate addresses from e-mail lists
# 
sub _StripDuplicates {
	# Thanks to the Perl Cookbook for this one.
	my %Seen = ();
	return grep { !$Seen{$_} ++} @_;
}



#
# _CompilePatterns - compile a series of patterns into a anon. subroutine.
# 
sub _CompilePatterns {

	my $PatternName = shift;
	if (@_ == 0) {
		# Empty pattern list.  Will never match.
		print "LogOutput: $PatternName pattern is empty\n\n" if $Options{VERBOSE};
		return eval "sub { return 0 };";
	}
	my @Patterns = (@_);

	# Join the individual tests into a single massive pattern.
	my $Pattern=join('||',map {"m$Patterns[$_]o\n\t"} 0..$#Patterns);
	print "LogOutput: $PatternName Patterns=\n\t$Pattern\n\n" if $Options{VERBOSE};
	my $CompiledTest=eval "sub {$Pattern}";
	if ($@) {
		die("Invalid pattern in \"PatternName\" message filters: $@\n");
	}
	else {
		return $CompiledTest;
	}
}

#
# _MakeSubstitutions - substitute values for % variables in text
#
# 	Valid % variables are:
# 		%C - Computer name (aka host name -- H and h were taken)
# 		%E - Error text: either "ended normally" or "ended with errors"
# 			depending on whether have been detected yet.
# 			See also %*.
# 		%N - Name of the program
# 		%P - Process ID of the child process
# 		%* - Error flag: either "*" or "" depending on whether
# 			errors have been detected yet.
#               %p - percent, same as %%
#               %U - User name
#               %D - Mail domain
# 		%anything else: any remaining % are processed by 
# 			POSIX::strftime.
# 		
#
sub _MakeSubstitutions {

	my $Text = shift;
	return $Text unless ($Text =~ /%/);	# Exit unless % variables present.
	my $StartTime = shift;			# Optional time stamp.
	$StartTime = time() unless ($StartTime);	

	# Simple substitutions.
	$Text =~ s/%%/%p/g;		# Change %% to %p so it doesn't match other % constructs.
	$Text =~ s/%C/$HostName/g;
	$Text =~ s/%N/$Options{PROGRAM_NAME}/g;
	$Text =~ s/%P/$PID/g;
	$Text =~ s/%O/$Options{MAIL_DOMAIN}/g;

	# Conditional substitutions (%E, %*).
	if ($ErrorsDetected) {
		$Text =~ s/%E/ended with errors/g;
		$Text =~ s/%\*/* /g;
	}
	else {
		$Text =~ s/%E/ended normally/g;
		$Text =~ s/%\*//g;
	}

	# User name.
	my $UserName;
	if ($^O eq 'MSWin32') {
		if (defined($ENV{'USERNAME'}) and $ENV{'USERNAME'}) {
			$UserName = $ENV{'USERNAME'};
		}
		else {
			$UserName = 'Administrator';
		}
	}
	else {
		$UserName=$ENV{'LOGNAME'};
	}
	$Text =~ s/%U/$UserName/g;

	# STRFTIME substitutions.
	$Text =~ s/%p/%%/g;		# Change %% back for strftime.
	if ($Text =~ /%/) {
		# Still have percent signs.  Call strftime for the rest.
		$Text = strftime($Text,localtime($StartTime));
	}
	
	return($Text);
}


#
# _FilterMessage - decide how this message should be handled.
#
sub _FilterMessage {

	$_ = shift;

	my $Prefix;		# Message prefix (spaces or '-> ').
	my $StdOut;		# Goes to stdout?
	my $ErrorsDetected = 0;	# Did we flag a bad message?
	
	# Log everything through Syslog if requested.
	if ($Options{SYSLOG_FACILITY} && !/^\s*$/) {
		if (!(syslog("INFO", "%s", $_))) {
			warn "LogOutput: Unable to write to syslog: $!";
			$Options{SYSLOG_FACILITY}=0;
		}
	}

	# Classify this message as ignorable, normal, mailonly, or error.
	if (&$IgnoreTest) {
		# Ignore it.
		return $ErrorsDetected;
	}
	elsif (&$NormalTest) {
		# This is normal.
		$Prefix='   ';
		$StdOut=1;
	}
	elsif (&$MailOnlyTest) {
		# This is normal, no stdout.
		$Prefix='   ';
		$StdOut=0;
	}
	else {
		# This is not normal.
		$Prefix='-> ';
		$ErrorsDetected=1;
		$StdOut=1;
	}

	# Now write it out.  We still use and maintain WriteMessage for
	# compatibility with earlier programs, since it was exported.
	WriteMessage($Options{MAIL_FILE},$StdOut,$Prefix.$_);

	return $ErrorsDetected;
}

#
# WriteMessage - write a message to the proper destinations.
#
sub WriteMessage {

	my($MailFile,$StdOut,$Message)=@_;	# Get our calling arguments.

	# Print it to STDOUT.
	printf STDOUT "%s\n", $Message if ($StdOut);

	# Write it to the log file if requested.
	if ($MailFile) {
		$Message = _MakeSubstitutions($Options{MAIL_FILE_PREFIX}) . " $Message"
			if ($Options{MAIL_FILE_PREFIX});
		if (!(printf $WRITELOGFILE_FH "%s\n", $Message)) {
			warn "LogOutput: Unable to write to $Options{MAIL_FILE} $!";
			$Options{MAIL_FILE}='';
		}
	}
}


#
# _SetupMail - prepare and send out a mail message.
#
sub _SetupMail {

	#my($a,$b,...)			# Declare local variables.
	my($ToArrayRef,$Subject,$MailFile,$From)=@_;	# Get our calling arguments.
	my($HostName);			# A place to hold our host name.
	my(%Mail);			# Hash that's passed to SendMail routine.

	return if($#{$ToArrayRef} == -1);	# Exit if we have no one to mail to.
	print "LogOutput: In _SetupMail To=" . join(', ',@$ToArrayRef)
		. ", Subject=$Subject, MailFile=$MailFile\n"
			if ($Options{VERBOSE});

	$Mail{To}='';			# Don't keep list from prior runs.
	# Add each addressee, appending mail domain if necessary.
	foreach (@$ToArrayRef) {
		$_ .="\@$Options{MAIL_DOMAIN}" if ($_ !~ /@.+\../); # Add domain if not something@something.something
		$Mail{To} .= ' ' . $_;
	}
	$Mail{To} =~ s/^\s+//;		# Strip leading space.
	$Mail{Server}=$Options{MAIL_SERVER};
	$Mail{Subject}=$Options{MAIL_SUBJECT};
	$Mail{From}=_MakeSubstitutions($Options{MAIL_FROM});
	$Mail{'X-JOBSUMMARY'}="Name=$Options{PROGRAM_NAME} Status=$ExitCode RunTime=$RawRunTime";
	$Mail{'X-JOBEXIT'}="$ExitCode";	
	# Following added in V3, because non-zero exit codes now may now
	# be a normal return code.  ErrorsDetected will be > 0 if an unexpected
	# message occurs, a non-normal exit code occurs, or a bad signal happens
	$Mail{'X-JOBERRORS'}="$ErrorsDetected";
	if ($MailFile) {
		open($READLOGFILE_FH, $MailFile) or die "Unable to reopen log file: $!\n";
		my $Count = 0;
		while (<$READLOGFILE_FH>) {
			$Count++;
			if (defined($Options{MAIL_LIMIT}) and
				$Count > $Options{MAIL_LIMIT}) {
					$Mail{Message} .= "<< Output truncated -- LogOutput mail limit exceeded >>\n";
					last;
			}
			else {
				$Mail{Message} .= $_;
			}
		}
		close $READLOGFILE_FH;
	} else {
		$Mail{Message}='';	# Null message; subject line says it all.
	}
	if ($Options{VERBOSE}) {
		print "LogOutput: Sending mail.  Mail parameters:\n";
		foreach (keys(%Mail)) {
			printf "\t%-12.12s %s\n", $_, $Mail{$_};
		}
	}
	$Mail{debug}=6 if $Options{Verbose};
	sendmail(%Mail) || warn "LogOutput: Unable to send e-mail: $Mail::Sendmail::error";
}
#
# Untaint  -- use very carefully!
#

sub untaint {
	my(@parms) = @_;
	foreach (@parms) {
		s/^(.*)$/$1/;
		$_=$1;
	}
	if (@parms == 1) {
		# Return scalar
		return $parms[$[];
	} else {
		# Return list
		return (@parms);
	}
}

1;
__END__

=head1 NAME

LogOutput  - this routine sets up the environment to capture all output
from the caller, classify each message, and optionally write a report
to the syslog, a file, and/or e-mail recipients.

=head1 SYNOPSIS

=head3 Version 3

    use LogOutput;
    LogOutput({option1 => value1, ...});

Options and defaults are shown in the table below:

   OPTION NAME   	| DEFAULT VALUE	| DESCRIPTION
   ---------------------|---------------|----------------------------
   ALWAYS_MAIL_LIST	| -none-	| Always send a report
   			|		| to these e-mail addreses
   ALWAYS_PAGE_LIST	| -none-	| Always send a page to
   			|		| these e-mail addresses
   CLEAN_UP		| -none-	| Call this subroutine after
   			|		| the child process completes
   ERROR_MAIL_LIST	| -none-	| Send a report to these
   			|		| e-mail addresses if errors
			|		| are detected.
   ERROR_PAGE_LIST	| -none-	| Send a page to these e-mail
   			|		| addresses if errors are 
			|		| detected.
   FILTER_FILE		| <DATA>	| Name of a file containing
   			|		| the message filters.
   MAIL_FILE		| (temp file)	| Name of a file to write
   			|		| filtered messages to.
   MAIL_FROM            | %U@%O         | Send e-mail with this From value.
                        |               | Defaults to user@domain
   MAIL_DOMAIN		| -none-	| Domain to append to unqualified
   			|		| e-mail addresses
   MAIL_SERVER		| 127.0.0.1	| Address of the SMTP server
   MAIL_SUBJECT		| %*%*%* %m/%d %C %N %E %*%*%*	| Subject line used in
   			|		| e-mail.  See % variables.
   NORMAL_RETURN_CODES	| (0)		| List of normal exit codes
   PROGRAM_NAME		| Name of caller| Program name for logs and e-mail
   SYSLOG_FACILITY	| -none-	| SYSLOG facility code to use
   SYSLOG_OPTIONS	| pid		| SYSLOG options
   VERBOSE		| 0		| Diagnostic/verbosity level (0-9).

The option names (i.e. "ALWAYS_MAIL_LIST") are case-insensitive.

The four mail lists each may be specified as either a space-separated list of
e-mail addresses (i.e. "joe@example.com bob@example.com cindy@example.com")
or as a reference to an array (i.e. \@mail_list).

=head2 Version 1 and 2

This calling format is supported but deprecated in version 3.  This interface 
is maintained for backward compatibility only.

    use LogOutput;
    LogOutput(
	$FilterFile,
	$Syslog,
	$MailFile,
	$MailList,
	$ErrorList,
	$PageList,
	$ErrorPageList
    );

These calling arguments equate to the version 3 options as follows:

   $FilterFile		FILTER_FILE
   $Syslog		SYSLOG_FACILITY
   $MailFile		MAIL_FILE
   $MailList		ALWAYS_MAIL_LIST
   $ErrorList		ERROR_MAIL_LIST
   $PageList		ALWAYS_PAGE_LIST
   $ErrorPageList	ERROR_PAGE_LIST


=head1 DESCRIPTION

LogOutput has been designed to implement script logging.  This logging
can take the form of copying messages to the syslog, writing the messages
to a file, and/or sending mail to one or more e-mail
The caller may specify different mail addresses to be used
for normal termination and error termination.  The mail may contain a complete
list of all messages from the job, or a smaller "summary" report.  Finally,
mail lists of "pager" addresses may be provided, either for all terminations or
for error terminations only.  These addresses will receive very short
notifications when the job has terminated.  

LogOutput's ability to review all output from the script allows it to 
perform aggressive error checking.  See "Filtering and Error Detection" below
for further information.

For details on the overall implementation approach, see
"Detailed Description" below.

=head1 CALLING ARGUMENTS

=head2 FILTER_FILE

This option contains a file name of a file containing message
filtering information.  Wildcards are allowed, in which case all
files matching the pattern are loaded.  The default value is "__DATA__",
which is a reserve word instructing LogOutput to load the filter
data from the built-in Perl <DATA> file handle.

The message filters allow LogOutput to determine whether the 
script generated any unexpected messages, and allows it to reduce the amount
of information sent in the e-mail'd execution reports. 
See "Filtering and Error Detection" below for filter file syntax.

Examples:
    FILTER_FILE => '/home/joeuser/jobname.filter'
    FILTER_FILE => '/home/joeuser/jobname.*.filter'

=head2 SYSLOG_FACILITY

This option contains a string identifying the syslog "facility code" to
use.  See
the "syslog" man pages for details on facility codes.  In general, "USER" is
a good facility code to use.  If this argument is not provided, the execution
is not logged to the system log.

Example:  SYSLOG_FACILITY => 'USER'

=head2 SYSLOG_OPTIONS

This option contains a string of options for the open_syslog call.
See the "syslog" man pages for details on options.  If not set, 'pid'
is used.  

Example:  SYSLOG_FACILITY => 'USER'

=head2 MAIL_FILE

This option contains a file name to use to hold e-mail text.  If not
provided, a
file is created in /tmp and deleted on termination.  Any prior contents of
this file are always deleted.

Example:  MAIL_FILE => '/home/joeuser/log/jobname.log'

=head2 MAIL_FROM

This option specifies who any e-mail is sent from.  Symbol substitution
is allowed.  The default is %U@%O (username@mail.domain).

Example:  MAIL_FROM => 'joe@%O'

=head2 ALWAYS_MAIL_LIST

This option holds is a scalar or a list containing one or more e-mail addresses.
When using a scalar, multiple e-mail addresses may be specified, separated by white space.
On job
termination, each member of this list will receive an e-mail report.  The
report will include the start time, command-line options, any messages
from the calling script written to STDOUT or STDERR (subject to any filtering
specified in the FilterFile), a terminination status, and an execution time.

Example: ALWAYS_MAIL_LIST => 'joe@example.com susan@example.com'
            -or-
	 ALWAYS_MAIL_LIST => ['joe@example.com', 'susan@example.com']

=head2 ERROR_MAIL_LIST

This option is similar to the ALWAYS_MAIL_LIST argument above. 
E-mail is sent to these addresses only if LogOutput detected errors in the
script execution, whereas mail is sent to the ALWAYS_MAIL_LIST regardless of
termination status.  Addresses in ALWAYS_MAIL_LIST are appended to this list
because those folks always want mail, so there's no need to list those folks
explicitly in this list.

=head2 ALWAYS_PAGE_LIST

This option is similar to ALWAYS_MAIL_LIST above.  On
job termination, a very short message is sent to these addresses indicating the job termination status.

=head2 ERROR_PAGE_LIST

This option is similar to ALWAYS_MAIL_LIST above. 
On job
termination, a very short message is sent to these addresses indicating the job
termination status, but only if errors were detected.  Address management
mirrors that used in ERROR_MAIL_LIST.

=head2 CLEAN_UP

This option should contain a reference to a subroutine.  Just
before termination, LogOutput will call this routine with the following
three arguments: 
    - The exit code
    - The name of the log file
    - The number of errors detected (# of unexpected messages, +1 for abnormal
    	exit code, +1 for abnormal signal on termination).
If this option is not provided, no clean-up routine is called.

Example:  CLEAN_UP => \&MyCleanUp

=head2 MAIL_DOMAIN

This option should contain a string to be appended to e-mail addresses that
are not fully qualified.  This option is frequently specified in
LogOutput_cfg.pm, as it is generally constant for all scripts on a given system.

Example: MAIL_DOMAIN => 'example.com'

=head2 MAIL_SERVER

This option identifies the name or IP address of the server used to send
e-mail.  If not specified, it defaults to "127.0.0.1".  This option is 
frequently specified in LogOutput_cfg.pm.

=head2 MAIL_SUBJECT

This option specifies the subject of any e-mails sent out.  By default, the
subject line is specified as "%m/%d %C %N %E %*%*%*" (see SYMBOL SUBSTITUTION
below).  After symbol substitution is complete, a typical subject like might
look like "07/01 SERVER1 MyScript ended normally".

=head2 NORMAL_RETURN_CODES

This option identifies exit codes that should be considered normal.  LogOutput
uses as part of its effort to determine if the script ran normally.  Normal
exit codes are specified as a list, as shown in the example below.  If the
script exits with an exit code other than one in the list, LogOutput will
flag the script as having ended with errors.  By default, zero is a normal exit code, and anything else is abnormal.

Example:  NORMAL_RETURN_CODES => [0,6,10]	# Zero, 6, and 10 are normal.

=head2 PROGRAM_NAME

=head1 SYMBOL SUBSTITUTION

Some options (MAIL_SUBJECT, MAIL_FROM) allow symbol substitution.  Substituted
symbols are as follows:

	%C - Computer name (aka host name -- H and h were taken)
	%E - Error text: either "ended normally" or "ended with errors"
		depending on whether have been detected yet.
		See also %*.
	%N - Name of the program
	%P - Process ID of the child process
	%* - Error flag: either "* " or "" depending on whether
		errors have been detected yet.
	%p - percent, same as %%
	%U - User name
	%O - Mail domain

After local substitution, any remaining % strings are processed by strftime.

=head1 Filtering and Error Detection

LogOutput determines whether a job failed based on three criteria:

=over 4

=item 1)

Return code - non-zero return codes indicate failure

=item 2)

Termination signal - a job that was terminated in response to 
a signal (segfault, kill, etc.), is considered to have failed

=item 3)

Unexpected messages, according to the specification found in
the "$FilterFile" file.

=back

When initially called, LogOutput reads the filter file (usually <DATA>), and
builds two lists of patterns.  The first list matches messages from the
calling script that are considered normal messages that should be shown
in the e-mail reports and at the console.  The second list matches messages
that are normal, but should not be shown.  

As the script runs, any messages it produces are matched against these pattern
lists.  If the message matches the first list, it is echoed to the console,
the syslog if requested, and the e-mail report file.  If the message matches
the second list, it is echoed to the syslog, but otherwise ignored.  Any
message that does not match either list is echoed to all output media, and
is treated as an error condition.

The format of the filter file is:   TYPE  PATTERN

TYPE can be one of the following:

    SHOW	Show this message on all output media
    MAILONLY	Show this message on the syslog and e-mail reports
    LOGONLY	Same as MAILONLY, deprecated
    IGNORE	Show this message on the system log only

PATTERN is any valid PERL pattern.

For example:

    IGNORE	"^Now processing record \d+$"
    SHOW	"^\d+ records written successfully.$"

The "Now processing" progress messages will not be shown in the e-mail
report.  The "### records written" summary message will be shown.

=head1 Clean-up

Once the script has terminated, LogOutput checks to see if a subroutine
exists in the main program called "Cleanup".  If one exists, LogOutput
will call this routine to perform clean-up processing.  Note that this is being
called in the parent process (see Detailed Description below), so Cleanup
won't have access to global variables set in the child process that ran
most of the script code.

=head1 Detailed Description

When LogOutput is called, it begins by loading the filter file patterns.
Once these patterns are loaded, they are compiled into a pair of anonymous
subroutines to improve efficiency.  Any errors in the pattern syntax are
detected and reported at this time.

Next LogOutput forks a child process.  The child process then returns to the
caller, so that the calling script now runs as a child of LogOutput.  The 
parent process reads STDOUT and STDERR from the child, matching each message
against the two filter patterns, and logging messages accordingly.

When the child process terminates, the parent process
calls any clean-up routine,
notes any unusual termination statuses from the child in the log file,
closes the log file,
and sends e-mail as appropriate.

This parent/child structure also allows the parent to document any signals
that caused the child to terminate, including untrappable signals like
"kill -9".  Killing the parent process at the same time, of course, will defeat
this logging.

=head1 BUGS & LIMITATIONS

Due to the need to fork a child process, LogOutput can't run under the debugger.
If it detects that the debugger
is running, it returns to the caller without processing.  This allows the
calling script to run normally, but no output will be logged.

LogOutput intercepts messages from STDOUT and STDERR.  Based on the filter file
it may or may not echo any given message to the console.  If a message is
echoed to the console, it is echoed as STDOUT even if the original message
came via STDERR.  This effectively reclassifies all messages as STDOUT 
messages for purposes of command line redirection.

=cut
