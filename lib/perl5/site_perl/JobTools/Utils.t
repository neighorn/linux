#! /usr/bin/perl -w
#
# Test Utils.pm
#
#   To do: test RunRemote
#
use strict;
use warnings;
use Test::More qw(no_plan);
use lib '.';
use File::Temp qw(tempfile);
use Utils @Utils::EXPORT_OK;	# Import everything.
#use Utils::_GatherParms;	# And the unexported stuff.

my %Config = (test1 => 'abc');
my %Options = (test2 => 'def');
Utils::init( options => \%Options, config => \%Config);
is ($Utils::OptionsRef,\%Options, 'init Options');
is ($Utils::OptionsRef->{test1},$Options{test1}, 'init Options - right pointer');
is ($Utils::ConfigRef,\%Config, 'init Config');
is ($Utils::ConfigRef->{test2},$Config{test2}, 'init Config right pointer');

is(Commify(-1000000),'-1,000,000','Commify(-1,000000)');
is(Commify(-100000),'-100,000','Commify(-100000)');
is(Commify(-10000),'-10,000','Commify(-10000)');
is(Commify(-1000),'-1,000','Commify(-1000)');
is(Commify(-100),'-100','Commify(-100)');
is(Commify(-10),'-10','Commify(-10)');
is(Commify(0),'0','Commify(0)');
is(Commify(10),'10','Commify(10)');
is(Commify(100),'100','Commify(100)');
is(Commify(1000),'1,000','Commify(1000)');
is(Commify(10000),'10,000','Commify(10000)');
is(Commify(100000),'100,000','Commify(100000)');
is(Commify(1000000),'1,000,000','Commify(1,000000)');
is(Commify(-1000.1),'-1,000.1','Commify(-1,000.1)');
is(Commify(1000.1),'1,000.1','Commify(1,000.1)');


is(ExpandByteSize('1B'),1,'ExpandByteSize("1B")');
is(ExpandByteSize('10B'),10,'ExpandByteSize("10B")');
is(ExpandByteSize('100B'),100,'ExpandByteSize("100B")');
is(ExpandByteSize('1023B'),1023,'ExpandByteSize("1023B")');
is(ExpandByteSize('1K'),1024,'ExpandByteSize("1K")');
is(ExpandByteSize('10K'),10240,'ExpandByteSize("10K")');
is(ExpandByteSize('100K'),102400,'ExpandByteSize("100K")');
is(ExpandByteSize('1M'),1024**2,'ExpandByteSize("1M")');
is(ExpandByteSize('10M'),1024**2*10,'ExpandByteSize("10M")');
is(ExpandByteSize('100M'),1024**2*100,'ExpandByteSize("100M")');
is(ExpandByteSize('1G'),1024**3,'ExpandByteSize("1G")');
is(ExpandByteSize('1T'),1024**4,'ExpandByteSize("1T")');
is(ExpandByteSize(Value=>'1K',Conversion=>1000),1000,'ExpandByteSize(Value=>1K,Conversion=>1000))');


is(CompressByteSize(1),'1.0B','CompressByteSize(1)');
is(CompressByteSize(10),'10.0B','CompressByteSize(10)');
is(CompressByteSize(102),'102.0B','CompressByteSize(102)');
is(CompressByteSize(1023),'1023.0B','CompressByteSize(1023)');
is(CompressByteSize(1024**1*1),'1.0K','CompressByteSize(1024)');
is(CompressByteSize(1024**1*10),'10.0K','CompressByteSize(10240)');
is(CompressByteSize(1024**1*100),'100.0K','CompressByteSize(102400)');
is(CompressByteSize(1024**2*1),'1.0M','CompressByteSize(1024^2)');
is(CompressByteSize(1024**2*10),'10.0M','CompressByteSize(1024^2*10)');
is(CompressByteSize(1024**2*100),'100.0M','CompressByteSize(1024^2*100)');
is(CompressByteSize(1024**3*1),'1.0G','CompressByteSize(1024^3*1)');
is(CompressByteSize(1024**3*10),'10.0G','CompressByteSize(1024^3*10)');
is(CompressByteSize(1024**3*100),'100.0G','CompressByteSize(1024^3*100)');
is(CompressByteSize(1024**4*1),'1.0T','CompressByteSize(1024^4*1)');
is(CompressByteSize(1024**4*10),'10.0T','CompressByteSize(1024^4*10)');
is(CompressByteSize(1024**4*100),'100.0T','CompressByteSize(1024^4*100)');
is(CompressByteSize(Value=>999,Conversion=>1000),'999.0B','CompressByteSize(Value=>999,Conversion=>1000)');
is(CompressByteSize(Value=>1000,Conversion=>1000),'1.0K','CompressByteSize(Value=>1000,Conversion=>1000)');
is(CompressByteSize(Value=>1000,Conversion=>1000),'1.0K','CompressByteSize(Value=>1000,Conversion=>1000)');
is(CompressByteSize(Value=>1234567,Conversion=>1000),'1.2M','CompressByteSize(Value=>1234567,Conversion=>1000)');
is(CompressByteSize(Value=>1234567,Conversion=>1000,Format=>'%.3f %s'),'1.235 M','CompressByteSize(Value=>1234567,Conversion=>1000,Format=>%.3f %s)');

my %Args = 	(                                 test3 => 'arg', test4 => 'arg' );
   %Options =	(                 test2 => 'opt',                 test4 => 'opt' );
my %Defaults = 	( test1 => 'def', test2 => 'def', test3 => 'def', test4 => 'def' );
my %Parms = Utils::_GatherParms(\%Args,\%Defaults);
is($Parms{test1},'def','_GatherParms default used');
is($Parms{test2},'opt','_GatherParms options overrides default');
is($Parms{test3},'arg','_GatherParms args overrides default');
is($Parms{test4},'arg','_GatherParms args overrides options and default');

my ($TMP,$TempFile) = tempfile(UNLINK => 1);
my ($TMP2,$TempFile2) = tempfile(UNLINK => 1);
print $TMP <<CONFIG1;
# Simple format
test1 testa
# With colons.
test2: testa
# Multiple values
test3: testa testb testc testd
# Continuation lines - single space
test4: testa
 testb
# Continuation lines - multiple spaces
test5: testa
    testb
# Continuation lines - single tab
test6: testa
	testb
# Continuation line - multiple tabs
test7: testa
		testb
# Continuation lines - multiple continuations, mixed whitespace, embedded comments
test8:	testa testb
	testc 		testd
# embedded comment
 teste
	testf
# Repeated declarations
test9: testa
test9b: testXXX - dummy intervening declaration
test9: testb
# Test INCLUDE
test10: testa testb
INCLUDE	$TempFile2
CONFIG1
close $TMP;

print $TMP2 <<CONFIG2;
# Second tempfile.
# Add more to test10
test10: testc testd teste

# Test recursive include prevention.
INCLUDE $TempFile2
CONFIG2
close $TMP2;

undef %Config;		# Make sure this is initialized.
LoadConfigFiles($TempFile);
is($Config{TEST1},'testa','LoadConfigFile simple');
is($Config{TEST2},'testa','LoadConfigFile colon');
is($Config{TEST3},'testa testb testc testd','LoadConfigFile multiple values');
is($Config{TEST4},'testa testb','LoadConfigFile continuation line/single space');
is($Config{TEST5},'testa testb','LoadConfigFile continuation line/multiple spaces');
is($Config{TEST6},'testa testb','LoadConfigFile continuation line/single tab');
is($Config{TEST7},'testa testb','LoadConfigFile continuation line/multiple tabs');
is($Config{TEST8},'testa testb testc testd teste testf','LoadConfigFile continuation line/mixed whitespace, embedded comment');
is($Config{TEST9},'testa testb','LoadConfigFile multiple declarations');
is($Config{TEST10},'testa testb testc testd teste','LoadConfigFile include file, recursive include');

undef %Options;		# Make sure this is initialized.
OptValue('opt1','test1');						is($Options{opt1},'test1','OptValue simple value');

undef %Options;		# Make sure this is initialized.
%Config = (		# Reinitialize with testing values.
	SERVERS => 'b c MORE h',
	MORE => 'd e STILLMORE g',
	STILLMORE => 'f',
	LOOP => 'b c LOOP d',
	CGROUP => 'c',
);
OptArray('opt2','test2');							is($Options{opt2}[0],'test2','OptArray simple value');
OptArray('opt2','test3');							is($Options{opt2}[1],'test3','OptArray second value');
OptArray('opt3','test4,test5,test6'); 						is(join('/',@{$Options{opt3}}),'test4/test5/test6','OptArray split embedded list');
OptArray('opt4','test4,test5,test6', 'preserve-lists' => 1 ); 			is(${$Options{opt4}}[0],'test4,test5,test6','OptArray preserve-lists');
OptArray('opt5','test5,test6,test7,!test5');					is(${$Options{opt5}}[3],'!test5','OptArray allow-delete=0');
OptArray('opt6','test6,test7,test8,!test6','allow-delete' => 1);		is(${$Options{opt6}}[0],'test7','OptArray allow-delete=1');
OptArray('opt7','a,SERVERS,i');							is(join('/',@{$Options{opt7}}),'a/SERVERS/i','OptArray expand-config=0');
OptArray('opt8','a,SERVERS,i','expand-config' => 1);				is(join('/',@{$Options{opt8}}),'a/b/c/d/e/f/g/h/i','OptArray expand-config=1');
OptArray('opt9','a,LOOP,h','expand-config' => 1);				is(join('/',@{$Options{opt9}}),'a/b/c/d/h','OptArray expand-config=1, config loop');
OptArray('opt10','a,b,c,d,!CGROUP','expand-config' => 1, 'allow-delete' => 1);	is(join('/',@{$Options{opt10}}),'a/b/d','OptArray expand-config=1, negate config');

%Options = (		# Reinitialize this.
	test => 1,
);
unlink($TempFile);
RunDangerousCmd("touch $TempFile");
ok(! -f $TempFile,'RunDangerousCmd - test in program options');
unlink($TempFile);
undef %Options;
RunDangerousCmd("touch $TempFile", test => 1);
ok(! -f $TempFile,'RunDangerousCmd - test in calling options');
unlink($TempFile);
my $Status = RunDangerousCmd("touch $TempFile");
ok(-f $TempFile,'RunDangerousCmd - live test');
ok($Status == 0,'RunDangerousCmd - normal status');
unlink($TempFile);
$Status = RunDangerousCmd("ls $TempFile > /dev/null 2> /dev/null");
ok($Status != 0,'RunDangerousCmd - error status');

print "Note: No tests for RunRemote are currently available.\n";
