#! /usr/bin/perl -w
#
# Test LogOutput.pm
#
use strict;
use warnings;
use lib '.';
use Test::More qw(no_plan);
use LogOutput qw(AddFilter FilterMessage);

$| = 1;

is (AddFilter('IGNORE  /^1$/'),0,'AddFilter - basic addition');
is (AddFilter('IGNORE  /^2$/'),0,'AddFilter - second addition');
is (AddFilter('IGNORE  "^3$"'),0,'AddFilter - quotes');
is (AddFilter("IGNORE  '^4\$'"),0,'AddFilter - apostrophes');
is (AddFilter('IGNORE  {^7$}'),0,'AddFilter - braces');
is (AddFilter('IGNORE  <^8$>'),0,'AddFilter - angle brackets');

print "Note: These tests handle basic filter addition and pattern matching.  Other functions are not tested yet.\n";
