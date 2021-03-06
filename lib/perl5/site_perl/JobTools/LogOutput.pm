# Copyright (c) 2005-2017, Martin Consulting Services, Inc.
# Licensed under the Lesser Gnu Public License (LGPL).
# 
# ABSOLUTELY NO WARRENTIES EXPRESSED OR IMPLIED.  ANY USE OF THIS
# CODE IS STRICTLY AT YOUR OWN RISK.
#
#		POD documentation appears at the end of this file.
#
use strict;
use warnings;
package	JobTools::LogOutput;
require	Exporter;
use Mail::Sendmail;
use JobTools::Utils qw(LoadConfigFiles);
use POSIX qw(strftime);
use Sys::Syslog;
use File::Glob qw(:glob);	# :bsd_glob not recognized on older systems
use File::Temp qw(tempfile);
use Fcntl;
use Fcntl qw(:flock);

our @ISA	= qw(Exporter);
our @EXPORT	= qw(LogOutput);
our @EXPORT_OK	= qw(AddFilter FilterMessage WriteMessage $Verbose $MailServer $MailDomain $Subject FormatVerboseElapsedTime);
our $Version	= 3.38;

our($ExitCode);			# Exit-code portion of child's status.
our($RawRunTime);		# Unformatted run time.
our($MailServer);		# Who sends our mail.
our($MailDomain);		# What's our default domain (i.e. "example.com").
our($READLOGFILE_FH);		# File handle.
our($WRITEMAILFILE_FH) = undef;	# File handle.
our($Verbose);			# Do we print diagnostics?
our($Subject);			# Do they want to alter the subject line?
our %FilterFiles;		# List of filter files we've loaded, so we don't duplicate.
our @Filters;			# Array of collected filter patterns.
our @FiltersMetaData;		# Array of hashes.  Each has metadata for one filter.
our $CompiledRegex;		# The assembled, compiled regex we actually use.

# Package variables.  Private to this file, but used in multiple routines.
my %Options;			# We'll store all our command line parameters and such here.
my $PID;			# PID of the child, that will do the
my $ErrorsDetected = 0;		# Flags whether errors were detected.
my $HostName;			# Our host name.
				# productive work while we monitor it.
#	Tests used to determine how to process messages.  Initially reject all.

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
		$HostName = lc($ENV{'COMPUTERNAME'});
	} else {
		$HostName = `hostname`;	# Get host name.
		chomp $HostName;	# Remove trailing \n;
		$HostName =~ s/\..*//;	# Remove domain name.
	}

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

	# Prepare our mail file.
	$DeleteMailFile = _PrepareMailFile();

	# Load in our filters.
	#	First from filter files.
	_LoadFilters();
	#	Last, add some of our own.  These go last, so they can be pre-empted by the caller.
        AddFilter('LOGONLY "^\s*\S+ started on \S+ on \S+, \d\d\d\d-\d\d-\d\d at \d\d:\d\d:\d\d$"');
        AddFilter('LOGONLY "^\S+ ended normally with status \d and signal \d+"');
        AddFilter('LOGONLY "^\s*\S+ ended on \S+, \d\d\d\d-\d\d-\d\d at \d\d:\d\d:\d\d - run time:"');
	print "LogOutput: " . (0+@Filters) . " filters loaded.\n" if $Options{Verbose};

	# Assemble and compile the final filter.
        my $FinalRegex=join('||',map {"m$Filters[$_]o\n\t"} 0..$#Filters);
        print "LogOutput: Final Pattern=\n\t$FinalRegex\n\n" if $Options{VERBOSE};
        $CompiledRegex=eval "sub {\$_ = shift; return ($FinalRegex?\$^R:undef);}";
        if ($@) {
                die(qq<LogOutput: Invalid pattern in\n\n"$FinalRegex"\n\nmessage filters: $@\n>);
	}

	# Now that we made it this far, we're safe to spin off the child process

	# Fork off child process to run the real job.  Parent will stay here
	# to monitor child's sysout and exit code.
	if ($^O eq 'MSWin32') {
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
		close($WRITEMAILFILE_FH) if ($Options{MAIL_FILE});
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

		# Release a bunch of big stuff the parent needed, but we don't.
		undef %FilterFiles;
		undef @Filters;
		undef @FiltersMetaData;
		undef $CompiledRegex;

		# Begin our log.
		$TimeStamp=strftime("%A, %Y-%m-%d at %H:%M:%S",localtime($^T));
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

	# Prepare full log file, if requested.
	my $RAW_LOGFILE_FH;
	if ($Options{RAW_LOGFILE}) {
		if (!open($RAW_LOGFILE_FH,'>',$Options{RAW_LOGFILE})) {
			warn qq<LogOutput: Unable to open raw log file "$Options{RAW_LOGFILE}": $! - logging to this file has been disabled.\n>;
			$RAW_LOGFILE_FH = undef();
		}
	}
	
	# Read and process everything from child's STDOUT.
	while (<LOGREADHANDLE>) {
		if ($RAW_LOGFILE_FH) {
			if (! print($RAW_LOGFILE_FH $_)) {
				warn qq<LogOutput: Unable to write to full log file "$Options{RAW_LOGFILE}": $! - further logging has been disabled.\n>;
				close $RAW_LOGFILE_FH;
				$RAW_LOGFILE_FH = undef;
			}
		}
		chomp;
		print "LogOutput: Read: $_\n" if $Options{VERBOSE} > 5;

		# Run it through the filters, and log/print as appropriate.
		$ErrorsDetected += _FilterMessage($_);
		print "LogOutput: Errors detected so far: $ErrorsDetected\n" if $Options{VERBOSE} > 6;
	}

	# The output is done.  Check our min/max counts.
	foreach my $MetaRef (@FiltersMetaData) {
		if (defined($MetaRef->{mincount}) and ($MetaRef->{mincount} > $MetaRef->{count})) {
			&_FilterMessage("LogOutput: Message count failed.  Needed at least $MetaRef->{mincount} but received $MetaRef->{count} for $MetaRef->{filename} line $MetaRef->{linenum}.\n");
			$ErrorsDetected++;
		}
		if (defined($MetaRef->{maxcount}) and ($MetaRef->{maxcount} < $MetaRef->{count})) {
			&_FilterMessage("LogOutput: Message count failed.  Needed no more than $MetaRef->{maxcount} but received $MetaRef->{count} for $MetaRef->{filename} line $MetaRef->{linenum}.\n");
			$ErrorsDetected++;
		}
	}

	if ($ErrorsDetected >= 1) {
		$ErrorsDetected += _FilterMessage(
			$ErrorsDetected 
			. ' unexpected message'
			. ($ErrorsDetected==1?'':'s')		# Manage plurals.
			. ' ("->") detected in '
			. $Options{PROGRAM_NAME} 
			. ' execution.'
		);
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
	$TimeStamp=strftime("%A, %Y-%m-%d at %H:%M:%S",localtime($StopTime));
	($RunTime,$RawRunTime)=FormatVerboseElapsedTime($StopTime-$^T);
	$Options{MAIL_FILE_PREFIX}='';		# Don't prefix wrap-up messages.
	$ErrorsDetected += _FilterMessage("   $Options{PROGRAM_NAME} ended on $TimeStamp - run time: $RunTime");
	
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
		$ErrorsDetected += _FilterMessage("$Options{PROGRAM_NAME} failed with status $ExitCode and signal $SignalCode");
		close($WRITEMAILFILE_FH) if ($Options{MAIL_FILE});
	} else {
		$ErrorsDetected += _FilterMessage(
			"$Options{PROGRAM_NAME} ended normally with status $ExitCode and signal $SignalCode");
		close($WRITEMAILFILE_FH) if ($Options{MAIL_FILE});
	}
	
	# Tweak up the subject line, now that we know how we ended.
	$Options{MAIL_SUBJECT} = '' unless $Options{MAIL_SUBJECT};
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
	
	close $RAW_LOGFILE_FH if ($RAW_LOGFILE_FH);

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
		RAW_LOGFILE => 1,
		MAIL_FILE_PREFIX => 1,
		MAIL_FILE_PERMS => 1,
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
	$Options{RAW_LOGFILE}='';
	$Options{MAIL_FILE_PREFIX}='';
	$Options{MAIL_FILE}='';
	$Options{MAIL_FILE_PERMS}=0640;
	$Options{MAIL_FROM}='%U@%O';
	$Options{MAIL_SERVER}='127.0.0.1';
	$Options{MAIL_DOMAIN}='';
	$Options{MAIL_LIMIT}=undef();
	$Options{NORMAL_RETURN_CODES}=[0];
	$Options{PROGRAM_NAME}=(caller(1))[1];	# Get the caller's filename.
	$Options{PROGRAM_NAME}=~ s"^.*[/\\]"";	# Strip path.
	$Options{PROGRAM_NAME}=~ s"\..*?$"";	# Strip suffix.
	$Options{MAIL_SUBJECT} = '';		# Set in SetupMail if not set before.
	$Options{VERBOSE}=0;

	# Now load our site defaults.  May be overridden by calling args.
	# Have two sources here.  The deprecated LogOutput_cfg.pm module,
	# and /usr/local/etc/LogOutput.cfg.
	eval qq[require JobTools::LogOutput_cfg;];
	if (!$@) {
		my @Config = JobTools::LogOutput_cfg::LogOutput_cfg();
		# We support two formats, so we start by figuring out which is 
		# being used.
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
					print "LogOutput: Set $key to $Options{$key} from LogOutput_cfg\n"
						if ($Options{VERBOSE});
				}
				else {
					$ErrorsDetected += _FilterMessage("LogOutput: Invalid option '$key' passed from LogOutput_cfg -- ignored.\n");
					$Options{$key} = undef;
				}
			}
		}
	}
	LoadConfigFiles(files=>['/usr/local/etc/LogOutput.cfg'],config=>\%Options,append=>0);

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
				if ($Options{Verbose}) {
					my $DisplayValue=(ref($Options{$key}) eq 'ARRAY'?join(', ',@{$Options{$key}}):$Options{$key});
					$DisplayValue = '' unless defined($DisplayValue);
					print "LogOutput: Set $key to $DisplayValue from calling arguments\n";
				}
			}
			else {
				$ErrorsDetected += _FilterMessage("LogOutput: Invalid option '$key' passed to LogOutput -- ignored.\n");
				$Options{$key} = undef;
			}
		}
	}
	# Check for environmental overrides
	$Options{VERBOSE} = $ENV{LOGOUTPUT_VERBOSE} if (exists($ENV{LOGOUTPUT_VERBOSE}));
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
# FormatVerboseElapsedTime - format seconds elapsed into human-readable format.
# 
sub FormatVerboseElapsedTime {

	my $RunTime = shift;

	if ($RunTime !~ /^\d+$/) {
		warn <LogOutput::FormatVerboseElapsedTime: invalid elapsed time "$RunTime" provided - treated as zero.\n>;
		$RunTime = 0;
	}

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
	if (wantarray) {
		my $RawRunTime="$RunDay:$RunHour:$RunMin:$RunSec";
		return ($RunTime,$RawRunTime);
	}
	else {
		return $RunTime;
	}
}


#
# _PrepareMailFile
# 
# Return 0 if the file should be kept on exit, or 1 if it should be deleted.
sub _PrepareMailFile {

	# Do we need a mail file?  Only if they asked for one or we're sending mail.
	return 0 if (!$Options{MAIL_FILE} && @{$Options{ERROR_MAIL_LIST}} == 0);

	my $DeleteMailFile;		# Do we delete the output file when done?
	if ($Options{MAIL_FILE}) {
		# They supplied a file name.  Try to use that one.
		$Options{MAIL_FILE} = _MakeSubstitutions($Options{MAIL_FILE});
		return 0 if (_OpenMailFile($Options{MAIL_FILE}));  # If it worked, we're done.
	}

	# If we got here, either they didn't supply a name or we couldn't open it.
	# Create a temporary file to use as a mail file.
	if ($Options{MAIL_FILE} = _OpenMailFile('')) {
		return 1;	# Created a temporary file.  Delete it on exit.
	}
	else {
		return 0;	# Failed to create it, so we don't need to delete it.
	}
}


#
# _OpenMailFile
#
# 	On exit, return empty string on error, or the file name on success.
#
#	Note: can't use _FilterMessage yet -- haven't loaded the filters so the user
#	can't have any say as to what to ignore (like can't lock log file).
#
sub _OpenMailFile {

	my $FileName = shift;


	# Do we have a file name?
	if ($FileName) {
		# Yes.  Make sure the file name is valid.
		if ($FileName =~ /^([a-zA-Z]:)?[a-zA-Z0-9_\\\/. ~-]+$/) {
			$FileName=untaint($FileName);
		}
		else {
			warn qq<LogOutput: Unable to open "$FileName" invalid symbol in file name.>;
			$ErrorsDetected++;
			return '';
		}
	
		# Open the log file R/W with create and append.  No trunctation until
		# we get the lock.
		if (!open($WRITEMAILFILE_FH, '+>>', $FileName)) {
			warn qq<LogOutput: Unable to open "$FileName": $!>;
			close $WRITEMAILFILE_FH;
			$WRITEMAILFILE_FH = undef;
			$ErrorsDetected++;
			return '';
		}
	}
	else {
		($WRITEMAILFILE_FH, $FileName) = tempfile();
	}

	# Lock it, so we don't get another job using the same file.  Primarily just if they picked
	# a fixed file name.
        if (!flock($WRITEMAILFILE_FH, LOCK_EX | LOCK_NB)) {
		close $WRITEMAILFILE_FH;
		$WRITEMAILFILE_FH = undef;
                print qq<Unable to lock mail file "$FileName": $!\n>;	# Print, since it's not a critical error.
		# Don't flag this as an error - it's a transient problem that doesn't mean the job failed.
                return '';	# We're done -- don't delete mail file on exit.
	}
	
	# We got the lock.  Set the permissions and empty it out.
	if ($^O ne 'MSWin32') {
		warn qq<Unable to set file permissions on "$FileName": $!> 
			unless chmod($Options{MAIL_FILE_PERMS},$WRITEMAILFILE_FH);
	}
	seek($WRITEMAILFILE_FH,0,0);		# Rewind to the beginning.
	truncate($WRITEMAILFILE_FH,0);		# Clean it out.

	# Unbuffer the file.
	select $WRITEMAILFILE_FH;
	$|=1;		# Keep this file unbuffered.
	select STDOUT;	# Undo prior select.

	return $FileName;
}



#
# _LoadFilters
# 
sub _LoadFilters {
	my $FilterHandle;		# Handle, in case they don't use DATA.
	my $Type;			# Type of pattern from FilterHandle file
	my $Pattern;			# Pattern from FilterHandle file.

	# Get a list of our filter file(s).
	my @FilterList;
	if ($Options{FILTER_FILE} and ref($Options{FILTER_FILE}) eq 'ARRAY') {
		# This is an array of globs (or simple file names).
		foreach (@{$Options{FILTER_FILE}}) {
			my @TempList = bsd_glob($_);
			print "LogOutput: Filter File specification $_ yields " . join(', ',@TempList) . "\n"
				if ($Options{VERBOSE});
			push @FilterList,@TempList;
		}
	}
	elsif ($Options{FILTER_FILE}) {
		# This is a single file glob or simple file name
		@FilterList = <$Options{FILTER_FILE}>;
		print "LogOutput: Filter File specification $Options{FILTER_FILE} yields " . join(', ',@FilterList) . "\n"
			if ($Options{VERBOSE});
		die("Unable to find filter file $Options{FILTER_FILE}\n") unless (@FilterList);
	}
	else {
		push @FilterList,'__DATA__';
		print "LogOutput: Setting FilterList to __DATA__\n" if ($Options{VERBOSE});
	}

	# Process each filter file.
	foreach my $FilterFile (@FilterList) {
		# See if it's a reserved file name.  Otherwise, process it as a file.
		if ($FilterFile eq 'SHOWALL') {
			# Reserved word - show all messages.  Used sometimes when scripts call other scripts.
			undef @Filters;
			undef @FiltersMetaData;
			AddFilter('SHOW //');
			print "LogOutput: FilterList includes SHOWALL -- any other filters discarded\n" if ($Options{VERBOSE});
			last;
		}
		elsif ($FilterFile eq 'IGNOREALL') {
			# Reserved word - ignore all messages.  Could be used when scripts call other scripts.
			undef @Filters;
			undef @FiltersMetaData;
			AddFilter('IGNORE //');
			print "LogOutput: FilterList includes IGNOREALL -- any other filters discarded\n" if ($Options{VERBOSE});
			last;
		}
		elsif ($FilterFile eq 'REJECTALL') {
			# Reserved word - reject all messages.  Not sure why this would be useful.  Testing, perhaps.
			undef @Filters;
			undef @FiltersMetaData;
			AddFilter('IGNORE /a^/');	# Impossible pattern - can't have data before start of line.
			print "LogOutput: FilterList includes REJECTALL -- all filters discarded\n" if ($Options{VERBOSE});
			last;
		}
		else {
			# It's an ordinary file.  Go load it.
			_LoadFilterFile($FilterFile);
		}
	}
}



#
# _LoadFilterFile - load an individual filter file.
#
sub _LoadFilterFile {
	my $FilterHandle;		# Handle, in case they don't use DATA.
	my $LineNum;			# Pattern record number.

	my $FilterFile = shift;
	if (exists($FilterFiles{$FilterFile})) {
		# We already read this one.  Skip it.
		print "LogOutput: Skipping filters from $FilterFile -- already read\n" if $Options{VERBOSE};
		return;
	}
	else {
		print "LogOutput: Loading filters from $FilterFile\n" if $Options{VERBOSE};
		$FilterFiles{$FilterFile}=1;
	}

	if ($FilterFile eq '__DATA__') {
		# Input is coming from the embedded data file.
		$FilterHandle=*main::DATA{IO};
	}
	elsif (!sysopen($FilterHandle,$FilterFile,O_RDONLY)) {
		$ErrorsDetected += _FilterMessage(qq<Unable to open "$FilterFile" $!\n>);
		close $FilterHandle;
		return;
	}

	# Read and process the file.
	$LineNum=0;
	while (<$FilterHandle>) {
		$LineNum++;
		chomp;
		print "LogOutput: \tRead $LineNum: $_\n"
			if ($Options{VERBOSE} >= 2);
		next if (/^\s*$/ or /^\s*#/);	# Skip comments and blank lines.
                AddFilter($_,$FilterFile,$LineNum);
	}
	close ($FilterHandle);
}


#
# AddFilter - add one filter to our stack.
#
sub AddFilter {
	my($FilterLine,$FilterFile,$LineNum) = @_;

	# Try to document who called us if they didn't pass file and/or line number.
	my(undef,$callfile,$callline) = caller;
	$FilterFile = ($callfile?$callfile:'?') unless $FilterFile;	
	$LineNum = ($callline?$callline:'?') unless $LineNum;

	# Split out the settings from the pattern.
	my($SettingsList,$Pattern)=split(/\s+/,$FilterLine,2);
	$Pattern=~s/\s+$//;		# Strip trailing whitespace.
	if ($SettingsList =~ /^include$/i) {
		_LoadFilterFile($Pattern);
		print "LogOutput: Resuming $FilterFile\n" if $Options{VERBOSE};
		next;
	}

	# Compile pattern and check for syntax errors.
	eval "qr$Pattern;";		# Check pattern for syntax problems.
	if ($@) {
		print qq<LogOutput: \tSyntax error in $FilterFile line $LineNum ("> 
			. substr($Pattern,0,50)
			. qq<"): $@\n>;
		return 1;
	}
	my %Hash = (
		filename => $FilterFile,	# Save the file name.
		linenum => $LineNum,	# Save the line number.
		count => 0,		# Initialize the "seen" count to zero.
		regex => $Pattern,	# Store the compiled regex.
	);

	# Add to the appropriate pattern list.
	my $Errors = 0;
	foreach my $Setting (split(/,/,$SettingsList)) {		# Split the settings list into settings.
		my($Name,$Value)= split(/=/,$Setting,2);		# Might be name=value format.
		$Name = uc($Name);					# Ignore case.
		if ( ($Setting =~ /^ignore$/i) or ( ($Name eq 'OUTPUT') and ($Value eq 'IGNORE') ) ) {
			# Ignore this message.
			$Hash{output}=();
		}
		elsif ( ($Setting =~ /^show$/i) or ( ($Name eq 'OUTPUT') and ($Value eq 'SHOW') ) ) {
			# Show this message.
			$Hash{output}=['STDOUT'];
		}
		elsif ( ($Setting =~ /^(MAILONLY|LOGONLY)$/i) or ( ($Name eq 'OUTPUT') and ($Value eq 'LOGFILE') ) ) {
			# Log this message.
			$Hash{output}=['LOGFILE'];
		}
		elsif ( ($Name eq 'COUNT') and ($Value =~ /^(\d+)$/)) {
			# Count=x: must be x messages, typically 1 to say this message must appear.
			$Hash{mincount} = $Hash{maxcount} = $1;
			my($min,$max) = ($1, $2);
		}
		elsif ( ($Name eq 'COUNT') and ($Value =~ /^(\d*)(?:-|\.\.)(\d*)$/)) {
			# Count=x-y, Count=x-, Count=-x, or the same with .. instead of -.
			my($min,$max) = ($1, $2);
			undef $min unless ($min =~ /^\d+$/);
			undef $max unless ($max =~ /^\d+$/);
			if (defined($min) and defined($max) and ($min > $max)) {
				print qq<LogOutput: \tCount minimum($min) is greater than maximum($max) in $FilterFile line $LineNum -- ignored\n>;
				$Errors++;
			}
			elsif (!defined($min) and !defined($max)) {
				print qq<LogOutput: \tCount minimum and maximum are both unspecified in $FilterFile line $LineNum -- ignored\n>;
				$Errors++;
			}
			else {
				$Hash{mincount} = $min if (defined($min));
				$Hash{maxcount} = $max if (defined($max));
			}
		}
		
		else {
			$ErrorsDetected += _FilterMessage(qq<LogOutput: Invalid type "$Setting" in pattern record $LineNum -- ignored.\n>);
		}
	}
	push @FiltersMetaData, { %Hash };		# Store this filter's meta-data.

	# Now we need to add tracking to the filter, so when it matches we can look up the metadata.
	# To do this, we add (?{xxx}) to the end of each pattern, where xxx is the index number of
	# the metadata in @FiltersMetaData.  On a match, $^R will be set to xxx.  Unreliable before
	# perl 5.10, however we're currently at 5.22 so probably safe.
	#
	# Alternation creates a problem, in that turning "x|y" into "x|y(?{xxx})" will only return xxx
	# on y, not x.  To fix this, we check for alternation.  If it's present we wrap it in a non-bind
	# grouping operator, so that xxx is returned if either match.  Technically, we do this even 
	# when the alternation operator is escaped, which isn't necessary, but since the grouping operator
	# is harmless, it doesn't hurt anything.  We could do it on every pattern, but that's just a 
	# waste of Regex CPU cycles.
	$Pattern =~ s/^\s*//;				# Strip any leading spaces.
	my $StartDelim = substr($Pattern,0,1);		# Get the leading delimiter.
	my $index = index('<{',$StartDelim);		# See if it's special.
	my $EndDelim = ($index >= 0			# Is it < or {
		? substr('>}',$index,1)			# Yes, use > or } for end delim.
		: $StartDelim				# No, end delim is same as start.
	);
	my($Regex,$Flags) = ($Pattern =~ /${StartDelim}(.*)${EndDelim}([^\s]*)\s*$/);
	$Regex="(?:$Regex)" if ($Regex =~ /\|/);	# Fix alternations
	push @Filters,"${StartDelim}$Regex(?{$#FiltersMetaData})${EndDelim}$Flags";
	
	return $Errors;
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
#               %O - Mail domain
#               %. - space -- used to avoid word splitting by ssh.
# 		%anything else: any remaining % are processed by 
# 			POSIX::strftime.
# 		
#
sub _MakeSubstitutions {

	my $Text = shift;
	return $Text unless (defined($Text) and ($Text =~ /%/));	# Exit unless % variables present.
	my $StartTime = shift;			# Optional time stamp.
	$StartTime = time() unless ($StartTime);	

	# Simple substitutions.
	$Text =~ s/%%/%p/g;		# Change %% to %p so it doesn't match other % constructs.
	$Text =~ s/%C/$HostName/g;
	$Text =~ s/%N/$Options{PROGRAM_NAME}/g;
	$Text =~ s/%P/$PID/g;
	$Text =~ s/%O/$Options{MAIL_DOMAIN}/g;
	$Text =~ s/%\./ /g;

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

	my $Message = shift;

	my $Prefix;		# Message prefix (spaces or '-> ').
	my $StdOut;		# Goes to stdout?
	my $ErrorsDetected = 0;	# Did we flag a bad message?

	# Log everything through Syslog if requested.
	if ($Options{SYSLOG_FACILITY} && ( $Message !~ /^\s*$/) ) {
		if (!(syslog("INFO", "%s", $Message))) {
			$ErrorsDetected += _FilterMessage("LogOutput: Unable to write to syslog: $!");
			print "LogOutput: Unable to write to syslog\n" if ($Options{VERBOSE});
			$Options{SYSLOG_FACILITY}=0;		# Don't try again.

		}
	}

	# See if this message matches.  Have to verify $CompiledRegex is defined in
	# case we haven't built it yet.
	if (defined($CompiledRegex) and defined(my $Index=$CompiledRegex->($Message))) {
		my $MetaData = $FiltersMetaData[$Index];
		$MetaData->{count}++;				# Increment the count.
		print "LogOutput: Message match:"
			. " File=" . $MetaData->{filename}
			. ", Line=" . $MetaData->{linenum}
			. ", Count=" . $MetaData->{count}
			. ", Text=$Message\n"
				if ($Options{VERBOSE} >= 1);
		# Process the output instructions.
		foreach my $Output (@{$MetaData->{output}}) {
			if ($Output eq 'STDOUT') {
				WriteMessage($Options{MAIL_FILE},1,"   $Message");
			}
			elsif ($Output eq 'LOGFILE') {
				WriteMessage($Options{MAIL_FILE},0,"   $Message");
			}
		}
		return 0;	# We're done with this message.
	}

	print "LogOutput: Message did not match: $Message\n" if ($Options{VERBOSE});
	WriteMessage($Options{MAIL_FILE},1,'-> '.$Message);
	$ErrorsDetected++;

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
	if (defined($WRITEMAILFILE_FH)) {
		$Message = _MakeSubstitutions($Options{MAIL_FILE_PREFIX}) . " $Message"
			if ($Options{MAIL_FILE_PREFIX});
		if (!(printf $WRITEMAILFILE_FH "%s\n", $Message)) {
			close $WRITEMAILFILE_FH;
			$WRITEMAILFILE_FH = undef;
			$ErrorsDetected += _FilterMessage("LogOutput: Unable to write to $Options{MAIL_FILE} $!");
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
	$Mail{Subject}= ($Options{MAIL_SUBJECT}				# Did we ever get a subject?
			? $Options{MAIL_SUBJECT}			#  We got something, use it.
			: _MakeSubstitutions('%*%m/%d %C %N %E %*%*%*')	#  No, use a default.
	);
	$Mail{From}=_MakeSubstitutions($Options{MAIL_FROM});
	$Mail{'X-JOBSUMMARY'}="Name=$Options{PROGRAM_NAME} Status=$ExitCode RunTime=$RawRunTime";
	$Mail{'X-JOBEXIT'}="$ExitCode";	
	$Mail{retries}=3;
	$Mail{delay}=30;
	# Following added in V3, because non-zero exit codes now may now
	# be a normal return code.  ErrorsDetected will be > 0 if an unexpected
	# message occurs, a non-normal exit code occurs, or a bad signal happens
	$Mail{'X-JOBERRORS'}="$ErrorsDetected";
	if ($MailFile) {
		open($READLOGFILE_FH, $MailFile) or die qq<Unable to reopen log file "$MailFile": $!\n>;
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
	$Mail{debug}=6 if $Options{VERBOSE};
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
   ALWAYS_PAGE_LIST	| -none-	| Always send a page (short email)
   			|		| to these e-mail addresses
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
   RAW_LOGFILE		| -none-	| Write every output message here.
   MAIL_FILE		| (temp file)	| Name of a file to write
   			|		| filtered messages to.
   MAIL_FROM            | %U@%O         | Send e-mail with this From value.
                        |               | Defaults to user@domain
   MAIL_DOMAIN		| -none-	| Domain to append to unqualified
   			|		| e-mail addresses
   MAIL_SERVER		| 127.0.0.1	| Address of the SMTP server
   MAIL_SUBJECT		| %*%m/%d %C %N %E %*%*%*	| Subject line used in
   			|		| e-mail.  See % variables.
   NORMAL_RETURN_CODES	| (0)		| List of normal exit codes
   PROGRAM_NAME		| Name of caller| Program name for logs and e-mail
   SYSLOG_FACILITY	| -none-	| SYSLOG facility code to use
   SYSLOG_OPTIONS	| pid		| SYSLOG options
   VERBOSE		| 0		| Diagnostic/verbosity level (0-9).
   			| 		| May be overridden by setting the
   			| 		| $LOGOUTPUT_VERBOSE environmental
   			| 		| variable.

The option names (i.e. "ALWAYS_MAIL_LIST") are case-insensitive.

In addition to specifying the options as calling arguments, they may also
be specified in /usr/local/etc/LogOutput.cfg.  Each line consists of a 
option name and value in the format "name: value".  See JobTools::Utils::LoadConfigFile
for more details about acceptable syntax rules.  There is also a deprecated
LogOutput_cfg.pm.  In case multiple sources are provided for values, the priority (least to most) for each
option is: LogOutput_cfg.pm (lowest), LogOutput.cfg, calling parameters (highest).

The four mail lists each may be specified as either a space-separated list of
e-mail addresses (i.e. "joe@example.com bob@example.com cindy@example.com")
or as a reference to an array (i.e. \@mail_list).

=head2 Version 1 and 2

This calling format is supported but deprecated starting in version 3.  This interface 
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

These calling arguments equate to the version 3+ options as follows:

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
perform aggressive error checking.  Normal messages are defined in advance
using a list of message filters.  Any other messages are flagged as errors.
See "Filtering and Error Detection" below for further information.

For details on the overall implementation approach, see
"Detailed Description" below.

=head1 CALLING ARGUMENTS

=head2 FILTER_FILE

This option contains a path name a file containing message
filtering information.  Wildcards are allowed, in which case all
files matching the pattern are loaded.  This can also be an array,
in which case each element is is processed as a file name, possibly
with wildcards.  Additionally, directory names may be specified, in
which case all files in the directory are loaded.

The following case-sensitive reserved file names have special
meanings:

=over 4

=item *
__DATA__

Load the filter data from the built-in Perl <DATA> file handle.

=item *
SHOWALL

Ignore all other filters and treat every message as a normal message
that should be displayed.  This filter is used primarily for diagnostic 
purposes, and when a script is being executed by another script that
will handle filtering and error detection.

=item *
IGNOREALL

Ignore all other filters and treat every message as a normal
message that should be ignored.  This filter is used primarily for
diagnostic purposes.

=item *
REJECTALL

Ignore all other filters and treat every message as an unexpected
message.  This filter is used primarily for diagnostic purposes.

=back


The default value is "__DATA__".

The message filters allow LogOutput to determine whether the 
script generated any unexpected messages, and allows it to reduce the amount
of information sent in the e-mail'd execution reports. 
See "Filtering and Error Detection" below for filter file syntax.

Examples:

    FILTER_FILE => '/home/joeuser/jobname.filter'
    FILTER_FILE => '/home/joeuser/jobname.*.filter'
    FILTER_FILE => (
	'/home/joeuser/jobname*.filter',
	'/home/joeuser/general.filter',
	'__DATA__)

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

=head2 RAW_LOGFILE

This option contains the name of a file to hold the full output
text before filtering.  If not provided, no full log file
is maintained.  This is often used instead of logging to the 
syslog, although the two are not mutually exclusive.

=head2 MAIL_FILE

This option contains a file name to use to hold e-mail text.  If not
provided, a
file is created in /tmp and deleted on termination.  Any prior contents of
this file are always deleted.  Symbol substitution is allowed (see below).

Example:  MAIL_FILE => '/home/joeuser/log/jobname.log'

=head2 MAIL_FILE_PERMS

This sets the file permissions for the mail file.  The default is 0640.

Example: MAIL_FILE_PERMS => 0644

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
/usr/local/etc/LogOutput.cfg, as it is generally constant for all scripts on a given system.

Example: MAIL_DOMAIN => 'example.com'

=head2 MAIL_SERVER

This option identifies the name or IP address of the server used to send
e-mail.  If not specified, it defaults to "127.0.0.1".  This option is 
frequently specified in /usr/local/etc/LogOutput.cfg.

=head2 MAIL_SUBJECT

This option specifies the subject of any e-mails sent out.  By default, the
subject line is specified as "%*%m/%d %C %N %E %*%*%*" (see SYMBOL SUBSTITUTION
below).  After symbol substitution is complete, a typical subject like might
look like "07/01 SERVER1 MyScript ended normally".

=head2 NORMAL_RETURN_CODES

This option identifies exit codes that should be considered normal.  LogOutput
uses the exit code as part of its effort to determine if the script ran normally.  Normal
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

Return code - non-zero return codes (default) or return code not listed in NORMAL_RETURN_CODES if specified indicate failure

=item 2)

Termination signal - a job that was terminated in response to 
a signal (segfault, kill, etc.), is considered to have failed

=item 3)

Unexpected messages, according to the specification found in
the "$FilterFile" files.

=back

LogOutput begins by reading the filter files (usually <DATA>) and creating a
list of patterns.  It returns control to the calling program, while capturing
the output and comparing it to the list of patterns.
When a match occurs, it uses options associated with the matching pattern
to determine the disposition of the message.  If no match occurs, the message
is flagged as an error.

The format of the filter file is:   OPTIONS  PATTERN

Options is a comma separated list of options.  Options may be in one of two formats:

    NAME
    NAME=value
     
The possible options are:

    SHOW	  Show this message in the syslog, on STDOUT, and in the e-mail report
    MAILONLY	  Show this message in the syslog and e-mail reports
    LOGONLY	  Same as MAILONLY, deprecated
    IGNORE	  Show this message on the system log only
    INCLUDE	  PATTERN is an additional filter file to be loaded
    COUNT=value	  Value may be an integer or a range of integers.  At the end of 
                  the output, LogOutput will verify that the number of occurrances
                  of messages matching this pattern matches the value or is within
                  the range.  If not, an error is reported.  Range formats are:
                     x-y  - counts between x and y inclusive are valid
                     x..y - synonym for x-y
                     -y   - counts less than or equal to y are valid
                     ..y  - synonym for -y
                     x-   - counts at or above x are valid
                     x..  - synonym for x-

Except for "INCLUDE", PATTERN is any valid PERL pattern.

For example:

    IGNORE		"^Now processing record \d+$"
    SHOW		"^\d+ records written successfully.$"
    SHOW,COUNT=1	/^Backup completed successfully$/

The "Now processing" progress messages will not be shown in the e-mail
report or on STDOUT.  The "### records written" summary message will be shown.
The "Backup completed..." message will also be shown on STDOUT and in the
e-mail.  In addition, at the end of the job, an error will be thrown if this
message did not occur exactly once (e.g. job killed part way through, or two
backups occurred in the same job.

=head1 Clean-up

Once the script has terminated, LogOutput checks to see if a subroutine
was specified using the CLEAN_UP option.  If one exists, LogOutput
will call this routine to perform clean-up processing.  Note that this is being
called in the parent process (see Detailed Description below).  This is 
necessary so it has access to the child's exit status, but it also means
that the routine won't have access to global variables set in the child
process that ran most of the script code.

=head1 Detailed Description

When LogOutput is called, it begins by loading the filter file patterns.
Any errors in the pattern syntax are detected and reported at this time.

Next LogOutput forks a child process.  The child process then returns to the
caller, so that the calling script now runs as a child of LogOutput.  The 
parent process reads STDOUT and STDERR from the child, matching each message
against the filter patterns, and logging messages accordingly.

When the child process terminates, the parent process
checks any filters that have COUNT= parameters, 
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

Signals sent to the parent process (notably ^C from a command line) are not
relayed to the child process.

=cut
