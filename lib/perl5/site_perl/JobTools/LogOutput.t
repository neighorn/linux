#! /usr/bin/perl -w
#
# Test LogOutput.pm
#
use strict;
use warnings;
use lib '.';
use Test::More qw(no_plan);
use JobTools::LogOutput qw(AddFilter FilterMessage FormatVerboseElapsedTime);

$| = 1;

is (AddFilter('IGNORE  /^1$/'),0,'AddFilter - basic addition');
is (AddFilter('IGNORE  /^2$/'),0,'AddFilter - second addition');
is (AddFilter('IGNORE  "^3$"'),0,'AddFilter - quotes');
is (AddFilter("IGNORE  '^4\$'"),0,'AddFilter - apostrophes');
is (AddFilter('IGNORE  {^7$}'),0,'AddFilter - braces');
is (AddFilter('IGNORE  <^8$>'),0,'AddFilter - angle brackets');

is (FormatVerboseElapsedTime(0),'0 seconds','FormatVerboseElapsedTime - zero elapsed');
is (FormatVerboseElapsedTime(1),'1 second','FormatVerboseElapsedTime - 1 second elapsed');
is (FormatVerboseElapsedTime(2),'2 seconds','FormatVerboseElapsedTime - 1 second elapsed');
is (FormatVerboseElapsedTime(60),'1 minute, 0 seconds','FormatVerboseElapsedTime - 1 minute elapsed');
is (FormatVerboseElapsedTime(600),'10 minutes, 0 seconds','FormatVerboseElapsedTime - 10 minutes elapsed');
is (join('-',FormatVerboseElapsedTime(600)),'10 minutes, 0 seconds-0:0:10:0','FormatVerboseElapsedTime - 10 minutes elapsed, raw value');

print "Note: These tests handle AddFilter and FormatVerboseElapsedTime.  Other functions are not tested yet.\n";
