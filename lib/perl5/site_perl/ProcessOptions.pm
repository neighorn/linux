#! /usr/bin/perl
#
# Copyright (c) 2005, Martin Consulting Services, Inc.
# Licensed under the Lesser Gnu Public License (LGPL).
# 
# ABSOLUTELY NO WARRENTIES EXPRESSED OR IMPLIED.  ANY USE OF THIS
# CODE IS STRICTLY AT YOUR OWN RISK.
#
#
#          POD documentation appears at the end of this file.
#
#
package ProcessOptions;
require Exporter;
use strict;
use Getopt::Mixed;
no strict "refs";
our @ISA        = qw(Exporter);
our @EXPORT     = qw(ProcessOptions);
our @EXPORT_OK  = qw(Debug);
our $Version    = 1.3;

our($Debug);			# Show diagnostic data.

sub ProcessOptions {

	use Text::ParseWords;	# For parsing data from the config file.

	# Declare local variables.
	my(@Args);			# Temporary hold area for args.
	my($Option);			# Option letter (i.e. "a" in "-a")
	my($Value);			# Option parm (i.e. "x" in "-m x")
	my($FullOption);		# Option letter with prefix (i.e. "+k")
	my($OptName);			# opt_$Option
	my($YesNoOpts)='';		# List of simple options (i.e. -h).
	my($ValueOpts)='';		# List of options taking one value.
	my($ListOpts)='';		# List of options taking multiple vals.
	my($OptType)='';		# Used to parse option desc.
	my($OptFunc)='';		# Used to parse option desc.
	my($opt_name);			# Name of current option.
	my($ErrorFlag)=0;			# Flag to indicate errors were detected.

	my($OptDesc,$Args)=@_;	# Get our calling args
	if (defined($Args)) {
		# They provided a pseudo-command line.  Turn it into an ARGV
		# array.  This code stolen from "perldoc -q delimited".
		$Args =~ s/^\s+//;	# Strip leading blanks.
		$Args =~ s/\s+$//;	# Strip trailing blanks.
		@Args = quotewords(" ",0,$Args);
		print "ProcessOptions: Option Specification=$OptDesc\nProcessOptions: Args=$Args\n"
			if ($Debug);
	} else {
		# They didn't supply anything.  Just copy ARGV.
		@Args = @main::ARGV;
		print "ProcessOptions: Option Specification=$OptDesc\nProcessOptions: Args=$Args\n"
			if ($Debug);
	}
	if ($Debug) {
		print "ProcessOptions: \@Args:\n";
		foreach(@Args) {print qq(\t"$_"\n);};
	}

	local(@ARGV)=@Args;		# Load up a private copy of our argv.

	# Build our patterns.
	foreach (split(/\s+/,$OptDesc)) {
		($OptName,$OptFunc,$OptType)=m/([^=:>])+([=:>])(\S*)/;
		$OptName=$_ if (!defined($OptName));
		$OptFunc='' if (!defined($OptFunc));
		$OptType='' if (!defined($OptType));
		next if ($OptFunc eq '>');	# Alias.
		if ($OptType eq '')	{$YesNoOpts.=$OptName; next};
		if ($OptType=~/[is]/)	{$ValueOpts.=$OptName; next};
		if ($OptType eq 'l')	{$ListOpts.=$OptName; next};
		die("Invalid option type '$OptType' for $OptName in ProcessOptions");
	}
	print "ProcessOptions: Boolean flags:$YesNoOpts, Value flags:$ValueOpts, List flags:$ListOpts\n"
		if ($Debug);

	# Convert our new lists into patterns.  Space handles null lists.
	$YesNoOpts=qr/^[ ${YesNoOpts}]$/;
	$ValueOpts=qr/^[ ${ValueOpts}]$/;
	$ListOpts=qr/^[ ${ListOpts}]$/;

	# Now clean up OptDesc, since Getopt doesn't understand =l or :l.
	$OptDesc=~s/([=:])l/${1}s/g;

	# Start processing the options.
	use Getopt::Mixed 'nextOption';
	Getopt::Mixed::init('-+',$OptDesc);
	while (($Option, $Value, $FullOption) = nextOption()) {
		print "ProcessOptions: Option=$Option, Value=$Value, FullOption=$FullOption\n"
			if ($Debug);
		$opt_name="main::opt_$Option";
		if ($Option eq 'd') {
			# Debug flag set.
			if ($ENV{'PERLDB_OPTS'} !~ /NonStop/)	{
				# Rerun ourselves with an autotrace.
				$ENV{'PERLDB_OPTS'}='AutoTrace NonStop=1';
				exec join(' ','perl -d',$0,@Args);
				die("exec returned $? executing @Args: $!\n");
			} else {
				# NonStop set.  This *IS* the traced version.
				next;	# Nothing to do -- ignore the -d.
			}
		}
		if ($Option eq 'O')	{
			# Load a special option set from the options file.
			$Value=~tr/[a-z]/[A-Z]/;
			if (defined($main::Config{$Value})) {
				unshift @ARGV,
					quotewords(" ",0,$main::Config{$Value});
			} else {
				warn "$Value configuration not found in $main::ConfigFile.\n";
				$ErrorFlag=3;
			}
			next;
		}
		if ($Option =~ /${YesNoOpts}/) {
			# Handle our binary options en masse.
			$Value=($FullOption =~ /^\+/)?0:1;
			&$opt_name($Value) if defined(&$opt_name);
			$$opt_name=$Value if (defined($Value));
			next;
		}
		if ($Option =~ /${ValueOpts}/) {
			# Handle simple settings en masse.
			&$opt_name($Value) if defined(&$opt_name);
			#eval "\$$opt_name='$Value';" if(defined($Value));
			$$opt_name=$Value if(defined($Value));
			next;
		};
		if ($Option =~ /${ListOpts}/)	{
			# Handle list en masse, & strip lead/trailing blanks.
			if ($FullOption =~ /^\+/) {
				# Delete list so far.
				$Value='';	# Set to anything.
				&$opt_name($Value) if defined(&$opt_name);
				#eval "\$$opt_name='';" if (defined($Value));
				$$opt_name='' if (defined($Value));
				undef @$opt_name;	# Make list go away.
				# Work around the fact that +list needs no
				# parms, but Getopt can't handle that. Note
				# that this means +list can't be last.
				unshift @ARGV, $Value;
			} else {
				# Append new item to existing list.
				&$opt_name($Value) if defined(&$opt_name);
				$$opt_name .= " $Value" if (defined($Value));
				push @$opt_name,$Value;
				# Strip leading and trailing spaces off of options.
				#eval "\$$opt_name=~s/^\\s*(.*)\\s*\$/\$1/;";
				$$opt_name=~s/^\s+//;
				$$opt_name=~s/\s+$//;
			}
			next;
		}
		print STDERR "Unrecognized option: \"$FullOption\".  Enter \"$main::Prog -h\" " .
			"for usage information.\n";
		$ErrorFlag=2;
	}

	# Anything left is part of our parms.
	Getopt::Mixed::cleanup();
	$main::Parms.=join(" ",@ARGV);
	push @main::Parms,@ARGV;

	my($Trash)=$main::ConfigFile;	# Dummy ref to suppress -w msg.
	$Trash=$main::Parms;		# Dummy ref to suppress -w msg.
	$Trash=$main::Prog;		# Dummy ref to suppress -w msg.
	print "ProcessOptions: On exit: \$Parms=$main::Parms, \@Parms=" . join(", ", @main::Parms) . "\n"
		if ($Debug);
	return $ErrorFlag;
}
1;
__END__

=head1 NAME

ProcessOptions  - process command line or config file options.

=head1 SYNOPSIS

use ProcessOptions;
ProcessOptions($OptionSpec,@Args);

=head1 GLOBAL VARIABLES

$ProcessOptions::Debug may be set to 1 to provide diagnostic information
during any subsequent calls to ProcessOptions.

=head1 DESCRIPTION

ProcessOptions is used to process command line arguments in a standard
way.  It relies on Getopt::Mixed for lower-level processing, and then
provides additional functionality.

=head1 CALLING ARGUMENTS

ProcessOptions takes two calling arguments, an option specification, and 
an optional array of command line parameters to process. 

=head2 Option Specification

The 
option specification consists of string containing a series of option names
and optional qualifiers.  An example:

	"a b c=s d=l e"

This states that a, b, c, d, and e are the only valid options in @Args.  "a",
"b", and "e", are simple boolean flags that might appear on the command
line as "-a", "+b", etc.  They do not take any parameters.

"c=s" indicates that "c" is a command line option that will take a 
parameter (a "string"), such as in the following command line:

	commandname -a -b -c myfilename -e

"myfilename" is the parameter to the "-c" option.

If the "-c" option is listed twice, the second value replaces the first.

"d=l" indicates that the "d" command line option will take a list of 
values, as in the following example:

	commandname -d file1 -d file2

In this case, the calling program will receive a list of values for "d",
containing both "file1" and "file2".

=head2 Command Line Parameters

The second argument (@Args) above is an optional array of arguments
to process.  This is typically @ARGV, and if not specified, @main::ARGV
will be used.  

=head1 RETURNED DATA

=head2 Boolean Options

Consistent with many other option processing packages, ProcessOptions will
return data by modifying or creating variables in the "main" namespace.  For
any boolean option "x" (like a, b, and e above), a variable $opt_x will 
either be set to 1 if the option was specified, or left undefined if it was
not.  A + before an option on the command line is equivalent to leaving it
unset, and is handy in some kinds of override situations.  So the command line:

	commandname -a +b -e

would result in $opt_a and $opt_e being set to 1, and $opt_b being undefined.

=head2 String Options

For any given string option x, (like c above), $opt_x will be set to the
option parameter if the option is specified on the command line, or left
undefined if the option was not specified or specified as +x.  For example,

	commandname -a -c myfile

would cause $opt_a to be set to 1 (it's a boolean), and $opt_c to be set to
"myfile".

=head2 List Options

For any given list option x, (like d above), @opt_x will contain each of
the values provided.  For example,

	commandname -d file1 -d file2 -d file9

will result in the following array:

	$opt_d[0]=file1
	$opt_d[1]=file2
	$opt_d[2]=file9

In addition, the scalar $opt_d will be set to a space-separated list of
values (i.e. $opt_d="file1 file2 file9").  This is for backwards compatibility,
and is deprecated because it doesn't provide any graceful way to handle
options that contain spaces, such as:

	commandname -d 'file 1'

=head1 SPECIAL OPTIONS

As ProcessOptions is designed for a specific environment, it reserves two
options to have specific meanings.  

The "-d" option is reserved for future use to turn on a diagnostic trace.  
There is code in place to activate a trace similar to Korn shell's "-xv"
option (line-by-line with variable interpretation), but this is not working
well at this time.

The "-O" (capital letter o), is used to insert additional canned option strings.
The -O option takes a parameter.  When -O is processed, the main::Config hash
is queried, using the supplied parameter as a key.  If a string is found, 
it is inserted in the argument array ProcessOptions is processing in place
of the -O parameter.  This allows long option strings to be stored in 
a configuration file, and then pulled in using -O.  For example, $Config{Friday} might contain "-w /dev/rmt0.1 -n -m jjones -m tsmith -e rgray".  Then,
running:

	commandname -v -O Friday -x tmp

would be equivalent to running:

	commandname -v -w /dev/rmt0.1 -n -m jjones -m tsmith -e rgray -x tmp
	
-O may be used as often as needed in a command line.

=head1 ADDITIONAL PROCESSING

ProcessOptions provides a mechanism to allow the calling program to validate
or change an option as it is being processed.  For any given option x, 
if the calling program contains a subroutine called "opt_x", that routine
will be called each time the x option is processed.  It will be provided
with the option parameter (i.e. "myfile", "file1", etc.) as an argument.  Any
value the opt_x subroutine returns will be used instead of the provided
parameter.  For example, such a routine could check for an option parameter
of "1day", and if found replace it with "24hours".  Such a routine could
also validate that a provided option parameter is all numeric, and "die"
if it is not.

A non-obvious use of this facility is to define a "opt_h" subroutine that
provides usage ("help") information, and then immediately terminates.

=head2 Command line parameters

Once the last option is processed, any remaining data is considered to be
command line parameters.  Command line parameters are returned to the 
"main" namespace in the @Parms array.  An additional $Parms variable
contains the command line parameters in a single, space-separated string,
but this exists for backwards compatibility only, and is deprecated because
it doesn't handle command line parameters with embedded spaces well.

=head1 BUGS

Perhaps, but none that I know of.

=cut
