#!/usr/bin/perl

use strict;
use warnings;
use LogOutput;
use Getopt::Long qw(GetOptionsFromString :config gnu_compat permute bundling);
use Text::ParseWords;
use POSIX qw(strftime);
use FindBin qw($Bin $Script);

$ENV{PATH}='/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin';

# Initialize variables.
our $Prog=$0;                           # Get our name, for messages.
$Prog=~s/\.pl$|\.bat$//;            	# Trim off the suffix, if present.
$Prog=~s".*[/\\]"";     	    	# Trim off the path, if present.
my $Errors=0;   	                # No errors so far.
my $Syslog='user';                      # Name of Syslog facility.  '' for none.
my $BaseDir="/usr/local/etc";		# Set our base directory.
my @ConfigFiles=("$BaseDir/${Prog}.cfg");	# Name of config files.
our %Config;				# Data from the config file.
our %Options;				# Options settings.
our @Parms;				# List of non-option arguments.

# Define our command-line options.  I use sub for everything, because
# GetOptions doesn't work right on a second call to it (which we need
# to do) with the conventional approach.
$DB::AutoTrace=$DB::AutoTrace;		# Suppress spurious warning.
our %OptionSpecifications=(
		'<>'			=>	sub {push @Parms,shift;},
		'debug|d'		=>	sub {$DB::AutoTrace=1;},
		'help|h|?!'		=>	\&opt_h,
		'always-mail|m=s'	=>	\&opt_Array,
		'error-mail|M=s'	=>	\&opt_Array,
		'option-set|O=s'	=>	\&opt_O,
		'always-page|p=s'	=>	\&opt_Array,
		'error-page|P=s'	=>	\&opt_Array,
		'filter-file|F=s'	=>	\&opt_Value,
		'test|t'		=>	\&opt_Value,
		'verbose|v'		=>	sub {$Options{verbose} = (exists($Options{verbose})?$Options{verbose}+1:1)},
);
#

# Note: general purpose script - don't change current directory.
#chdir $BaseDir || die "Unable to change directories to $BaseDir: $!\n";

# Load the config file.
foreach (@ConfigFiles) {
	LoadConfigFile($_);
}
foreach (keys(%Config)) { s/,$//;};	# Trim off trailing commas.

# Process the config file defaults if present.
unshift @ARGV, quotewords(" ",0,$Config{'ALLJOBS'})
	if (defined($Config{'ALLJOBS'}));

# Use the default job if it's defined and we didn't get anything on 
# the command line.
push @ARGV,(shellwords($Config{DEFAULTJOB}))
	if (!@ARGV && defined($Config{DEFAULTJOB}));

# Pre-process our command line, to get the options we need for LogOutput.
my @ARGVSave = @ARGV;		# Needed to reprocess command line later.
%Options=(verbose => 0);	# Initialize Options.
$Errors ++ unless (GetOptions(%OptionSpecifications));
@ARGV = @ARGVSave;		# Restore @ARGV for LogOutput and second GetOptions.
	
# Set up our logging and output filtering.
my $RunDate=`date +%m/%d`;
chomp $RunDate;
my $Subject;
if ($Options{subject}) {
	$Subject="$Options{subject}" ;
} elsif (@Parms >= 1) {
	$Subject="%* %m/%d %C %N " . join(', ',@Parms) . " %E %*%*%*" ;
} else {
	$Subject="%* %m/%d %C %N %E %*%*%*" ;
};

# Make sure some key items exist;
foreach (qw(always-mail error-mail always-page error-page)) {
	@{$Options{$_}} = () unless (exists($Options{$_}));
}
$Options{verbose} = 0 unless (exists($Options{verbose}));
$Options{logfile} = '' unless (exists($Options{logfile}));
my $LogOutputVerbose = ($Options{verbose} > 4?$Options{verbose}-4:0);

LogOutput({
	SYSLOG_FACILITY		=> $Syslog,
	MAIL_FILE		=> $Options{logfile},
	MAIL_FILE_PERMS		=> 0644,
	ALWAYS_MAIL_LIST	=> \@{$Options{'always-mail'}},
	ERROR_MAIL_LIST		=> \@{$Options{'error-mail'}},
	ALWAYS_PAGE_LIST	=> \@{$Options{'always-page'}},
	ERROR_PAGE_LIST		=> \@{$Options{'error-page'}},
	MAIL_SUBJECT		=> $Subject,
	FILTER_FILE		=> $Options{'filter-file'},
	VERBOSE			=> $LogOutputVerbose,
});


# --------- add main line code here ----------

if ($Errors) {
	warn "$Prog failed.\n";
} else {
	#print "$Prog ended normally.\n";
}

exit( ($Errors?10:0) );


#
# xxxxx
#
sub xxxxxx {

}


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
        }
}


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
		print "Executing: $Cmd\n" if ($Options{verbose});
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


#
# opt_Value - generic single-value option processing
#
sub opt_Value {
	my($Name,$Value) = @_;
	$Options{$Name} = $Value;
}


#
# opt_Array - generic multi-value optoin  processing
#
sub opt_Array {

	my($Name,$Value,undef) = @_;
	if (defined($Value) and length($Value)) {
		# Add this value to the array.
		push @{$Options{$Name}},$Value;
	}
	else {
		# Received "--opt=".  Empty this array.
		@{$Options{$Name}}=();
	}
}


#
# opt_O - Load an option set.
#
sub opt_O {
	my(undef,$Value) = @_;
	$Value = uc($Value);
	if (exists($Config{$Value})) {
		$Errors ++ unless GetOptionsFromString($Config{$Value},%OptionSpecifications);
	}
	else {
		warn qq<Warning: "$Value" not found in configuration file\n>;
	}
}


#
# opt_h: Usage
#
sub opt_h {

        my $Pagenater=$ENV{PAGENATER};
        $Pagenater="more" unless ($Pagenater);
        system("pod2text $Bin/$Script | $Pagenater");
        exit(1);
}
=pod

=head1 $Prog - 

<<description>>

=head3 Usage:  
        $Prog [-e mailid] [-m mailid] [-p mailid] [-P mailid] [-O config] [-t|-v] 

        $Prog -h

=head3 Flags:
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
                                from $ConfigFiles[0]
                                into the command line at this point.
        --test|-t:              Test: echo commands instead of running them.
        --verbose|-v:           Verbose: echo commands before running them.
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

=cut

__END__
#
# Output filters.  The syntax is: type pattern
#
#  Type:        Ignore - Don't display this message, it's not interesting.
#               LogOnly - Write this message to the syslog and log file, but
#                       don't display it on STDOUT.
#               Show - Display this message, but it's not an error condition.
#               # - This is a comment, ignore it.
#
#               Everything else is flagged as an error.
#
#  Pattern:     an ordinary perl pattern.  All patterns for a given type
#               are joined by logical OR conditions.
#
#  Notes:
#       1) The "Type" parameter may be specified in upper, lower, or mixed case.
#       2) All messages go to the syslog, regardless of this filter.
#
LOGONLY "^\s*\S+ started on \S+ on \S+, \d+/\d+/\d+ at \d+:\d+:\d+"
LOGONLY "^\s*Command: "
SHOW    "^\s*Starting \S+ at \d+:\d+:\d+ on \S+, \d\d\d\d-\d\d-\d\d...\s*$"
SHOW    "^\s*Job ended normally with status 0 and signal 0 - run time:"
SHOW    "^\s*Test:"
SHOW    "^\s*Executing:"
SHOW    "^\s*Verbose:"
SHOW    "^\s*debug:"
SHOW    "^\s*$"
