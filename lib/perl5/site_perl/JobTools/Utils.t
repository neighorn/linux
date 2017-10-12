#! /usr/bin/perl -w
#
# Test Utils.pm
#
#   To do: test RunRemote
#
use strict;
use warnings;
use lib '..';
use Test::More qw(no_plan);
use File::Temp qw(tempfile);
use JobTools::Utils @JobTools::Utils::EXPORT_OK;	# Import everything.

my %Config = (test1 => 'abc');
my %Options = (test2 => 'def');
my $Status;
JobTools::Utils::init( options => \%Options, config => \%Config);
is ($JobTools::Utils::OptionsRef,\%Options, 'init Options');
is ($JobTools::Utils::OptionsRef->{test1},$Options{test1}, 'init Options - right pointer');
is ($JobTools::Utils::ConfigRef,\%Config, 'init Config');
is ($JobTools::Utils::ConfigRef->{test2},$Config{test2}, 'init Config right pointer');

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


is(ExpandByteSize('1'),1,'ExpandByteSize("1")');
is(ExpandByteSize('1B'),1,'ExpandByteSize("1B")');
is(ExpandByteSize('1 B'),1,'ExpandByteSize("1 B")');
is(ExpandByteSize('10B'),10,'ExpandByteSize("10B")');
is(ExpandByteSize('100B'),100,'ExpandByteSize("100B")');
is(ExpandByteSize('1023B'),1023,'ExpandByteSize("1023B")');
is(ExpandByteSize('1K'),1024,'ExpandByteSize("1K")');
is(ExpandByteSize('10K'),10240,'ExpandByteSize("10K")');
is(ExpandByteSize('10.5K'),10752,'ExpandByteSize("10.5K")');
is(ExpandByteSize('100K'),102400,'ExpandByteSize("100K")');
is(ExpandByteSize('1M'),1024**2,'ExpandByteSize("1M")');
is(ExpandByteSize('10M'),1024**2*10,'ExpandByteSize("10M")');
is(ExpandByteSize('100M'),1024**2*100,'ExpandByteSize("100M")');
is(ExpandByteSize('1G'),1024**3,'ExpandByteSize("1G")');
is(ExpandByteSize('1g'),1024**3,'ExpandByteSize("1g")-lower case');
is(ExpandByteSize('1T'),1024**4,'ExpandByteSize("1T")');
is(ExpandByteSize('1.K'),1024,'ExpandByteSize("1.K")');
is(ExpandByteSize('.1K'),102.4,'ExpandByteSize(".1K")');
is(ExpandByteSize('1.1K'),1126.4,'ExpandByteSize("1.1K")');
is(ExpandByteSize('0'),0,'ExpandByteSize("0")');
is(ExpandByteSize('0K'),0,'ExpandByteSize("0K")');
is(ExpandByteSize('01K'),1024,'ExpandByteSize("01K")');
is(ExpandByteSize(value=>'1K',conversion=>1000),1000,'ExpandByteSize(value=>1K,conversion=>1000))');


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
is(CompressByteSize(-1024**4*100),'-100.0T','CompressByteSize(-1024^4*100)');
is(CompressByteSize(value=>999,conversion=>1000),'999.0B','CompressByteSize(value=>999,conversion=>1000)');
is(CompressByteSize(value=>1000,conversion=>1000),'1.0K','CompressByteSize(value=>1000,conversion=>1000)');
is(CompressByteSize(value=>1000,conversion=>1000),'1.0K','CompressByteSize(value=>1000,conversion=>1000)');
is(CompressByteSize(value=>1234567,conversion=>1000),'1.2M','CompressByteSize(value=>1234567,conversion=>1000)');
is(CompressByteSize(value=>1234567,conversion=>1000,format=>'%.3f %s'),'1.235 M','CompressByteSize(value=>1234567,conversion=>1000,format=>%.3f %s)');

my %Args = 	(                                 test3 => 'arg', test4 => 'arg' );
   %Options =	(                 test2 => 'opt',                 test4 => 'opt' );
my %Defaults = 	( test1 => 'def', test2 => 'def', test3 => 'def', test4 => 'def' );
my %Parms = JobTools::Utils::_GatherParms(\%Args,\%Defaults);
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
test11: testg

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
is($Config{TEST9},'testa testb','LoadConfigFile multiple declarations with append = 1');
is($Config{TEST10},'testa testb testc testd teste','LoadConfigFile include file, recursive include');
LoadConfigFiles($TempFile2);
is($Config{TEST11},'testg','LoadConfigFile prevent loading file multiple times');	# Would be 'testg testg' if it fails.
undef %Config;
undef %JobTools::Utils::LoadConfigFiles_ConfigFilesRead;				# Reset read-file list so we can reuse the test file.
LoadConfigFiles(files=>[$TempFile],append=>0);
is($Config{TEST9},'testb','LoadConfigFile multiple declarations with append = 0');
undef %Config;
my %Config2;
LoadConfigFiles(files=>[$TempFile],config=>\%Config2);
ok((!exists($Config{TEST1}) and exists($Config2{TEST1}) and $Config2{TEST1} eq 'testa'),'LoadConfigFiles config parm');

undef %Options;		# Make sure this is initialized.
OptValue('opt1','test1');							is($Options{opt1},'test1','OptValue simple value');
OptValue('opt1','test2');							is($Options{opt1},'test2','OptValue simple value with replace');
OptValue('opt2','test1', append => 1);						is($Options{opt2},'test1','OptValue simple value with append');
OptValue('opt2','test2', append => 1);						is($Options{opt2},'test1,test2','OptValue simple value with second value and append');
OptValue('opt2','');								is(0+defined($Options{opt2}),0,'OptValue unset simple value');

#
# OptFlag
#
undef %Options;		# Reinitialize this.
OptFlag('test',1);								is($Options{test},1,'OptFlag first use');
OptFlag('test',1);								is($Options{test},2,'OptFlag second use');
OptFlag('test',1);								is($Options{test},3,'OptFlag third use');
OptFlag('test',0);								is($Options{test},0,'OptFlag negation');

#
# OptArray
#
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
OptArray('opt12','a b "c d e" f g');						is(join('/',@{$Options{opt12}}),'a/b/"c d e"/f/g','OptArray quoted values');

#
# OptOptionSet
#
my @Parms;
%Config = (
	OPTION1 => '-a',
	OPTION2 => '-b',
	OPTION3 => '-c',
	OPTION4 => '-d -e',
	'OPTION5=5' => '-f',
	OPTION6 => '-g=6',
	OPTION7 => '-h=1 -h=2 -h=3',
	# No option8 for optional test
	OPTION9 => '-i',
	# No option10 for mandatory test
	OPTION11 => '-j abc',
	OPTION12 => 'def -k ghi -l',
);
%Options = ();
my %OptionSpecifications=(
	'-a'	=>	\&OptFlag,
	'-b'	=>	\&OptFlag,
	'-c'	=>	\&OptFlag,
	'-d'	=>	\&OptFlag,
	'-e'	=>	\&OptFlag,
	'-f'	=>	\&OptFlag,
	'-g=n'	=>	\&OptValue,
	'-h=n'	=>	\&OptArray,
	'-i'	=>	\&OptFlag,
	'-j'	=>	\&OptFlag,
	'-k'	=>	\&OptFlag,
	'-l'	=>	\&OptFlag,
	'<>' => sub {my $Arg = shift; push @Parms,$Arg if (length($Arg));},
);

OptOptionSet(name => 'option1', optspec => \%OptionSpecifications);		is($Options{a},1,'OptOptionSet simple flag, lower case');
OptOptionSet(name => 'OPTION2', optspec => \%OptionSpecifications);		is($Options{b},1,'OptOptionSet simple flag, upper case');
OptOptionSet(name => 'Option3', optspec => \%OptionSpecifications);		is($Options{c},1,'OptOptionSet simple flag, mixed case');
OptOptionSet(name => 'option4', optspec => \%OptionSpecifications);		ok(($Options{d}==1 and $Options{e}==1),'OptOptionSet multiple simple flags');
OptOptionSet(name => 'option5=5', optspec => \%OptionSpecifications);		is($Options{f},1,'OptOptionSet embedded equal sign');
OptOptionSet(name => 'option6', optspec => \%OptionSpecifications);		is($Options{g},6,'OptOptionSet value assigned');
OptOptionSet(name => 'option7', optspec => \%OptionSpecifications);		is(join('-',@{$Options{h}}),'1-2-3','OptOptionSet list assigned');
$Status = OptOptionSet(name => ':option8', optspec => \%OptionSpecifications);	is($Status,0,'OptOptionSet optional set not found');
$Status = OptOptionSet(name => 'option9', optspec => \%OptionSpecifications);	is($Options{i},1,'OptOptionSet optional set found');
$Status = OptOptionSet(name => 'option10', optspec => \%OptionSpecifications, 'suppress-output' => 1);
										ok(($Status != 0),"OptOptionSet mandatory set not found - status $Status");
@Parms=();
OptOptionSet(name => 'option11', optspec => \%OptionSpecifications);		is(join('-',@Parms),'abc','OptOptionSet trailing parm');
@Parms=();
OptOptionSet(name => 'option12', optspec => \%OptionSpecifications);		is(join('-',@Parms),'def-ghi','OptOptionSet intermixed parms');


#
# RunDangerousCmd
#
%Options = (test => 1);	# Reinitialize this.
unlink($TempFile);
RunDangerousCmd("touch $TempFile",'suppress-output' => 1);
ok(! -f $TempFile,'RunDangerousCmd - test in program options');
unlink($TempFile);
undef %Options;
RunDangerousCmd("touch $TempFile", test => 1, 'suppress-output' => 1);
ok(! -f $TempFile,'RunDangerousCmd - test in calling options');
unlink($TempFile);
$Status = RunDangerousCmd("touch $TempFile", 'suppress-output' => 1);
ok(-f $TempFile,'RunDangerousCmd - live test');
ok($Status == 0,'RunDangerousCmd - normal status');
unlink($TempFile);
$Status = RunDangerousCmd("ls $TempFile > /dev/null 2> /dev/null");
ok($Status != 0,'RunDangerousCmd - error status');

#
# ExpandConfigList
#
%Config = (
	LIST1 => "a",
	LIST2 => "a b",
	LIST3 => "a b c",
	LIST4 => "a,b,c",
	LIST5 => "a b,c",
	LIST6 => "LIST5",
	LIST7 => "d,LIST5",
	LIST8 => "LIST8",
	LIST9 => "e,LIST10",
	LIST10 => "f,LIST9",
);
is(join('-',ExpandConfigList('LIST1')),'a','ExpandConfigList simple value');
is(join('-',ExpandConfigList('LIST2')),'a-b','ExpandConfigList two values');
is(join('-',ExpandConfigList('LIST1','LIST2')),'a-b','ExpandConfigList duplicate value');
is(join('-',ExpandConfigList('LIST3')),'a-b-c','ExpandConfigList three values');
is(join('-',ExpandConfigList('LIST4')),'a-b-c','ExpandConfigList comma separators');
is(join('-',ExpandConfigList('LIST5')),'a-b-c','ExpandConfigList mixed separators');
is(join('-',ExpandConfigList('LIST6')),'a-b-c','ExpandConfigList simple group referral');
is(join('-',ExpandConfigList('LIST7')),'d-a-b-c','ExpandConfigList list and group');
is(join('-',ExpandConfigList('LIST8')),'','ExpandConfigList simple recursive loop');
is(join('-',ExpandConfigList('LIST9')),'e-f','ExpandConfigList multi-part recursive loop');
is(join('-',ExpandConfigList('LIST3','!b')),'a-c','ExpandConfigList simple element delete');
is(join('-',ExpandConfigList('!b','LIST3')),'a-b-c','ExpandConfigList premature element delete');
is(join('-',ExpandConfigList('LIST3','!LIST1')),'b-c','ExpandConfigList List-based single delete');
is(join('-',ExpandConfigList('LIST3','!LIST2')),'c','ExpandConfigList List-based multiple delete');

#
# FormatElapsedTime
#

is (FormatElapsedTime(      0),           0,	'FormatElapsedTime - 0');
is (FormatElapsedTime(      1),           1,	'FormatElapsedTime - 1');
is (FormatElapsedTime(     10),          10,	'FormatElapsedTime - 10');
is (FormatElapsedTime(     59),         '59',	'FormatElapsedTime - 59');
is (FormatElapsedTime(     60),       '1:00',	'FormatElapsedTime - 1:00');
is (FormatElapsedTime(     61),       '1:01',	'FormatElapsedTime - 1:01');
is (FormatElapsedTime(    599),       '9:59',	'FormatElapsedTime - 9:59');
is (FormatElapsedTime(    600),      '10:00',	'FormatElapsedTime - 10:00');
is (FormatElapsedTime(   3599),      '59:59',	'FormatElapsedTime - 59:59');
is (FormatElapsedTime(   3600),    '1:00:00',	'FormatElapsedTime - 1:00:00');
is (FormatElapsedTime(   3601),    '1:00:01',	'FormatElapsedTime - 1:00:01');
is (FormatElapsedTime(   3661),    '1:01:01',	'FormatElapsedTime - 1:01:01');
is (FormatElapsedTime(  86399),   '23:59:59',	'FormatElapsedTime - 23:59:59');
is (FormatElapsedTime(  86400),	'1:00:00:00',	'FormatElapsedTime - 1:00:00:00');
is (FormatElapsedTime(  86401),	'1:00:00:01',	'FormatElapsedTime - 1:00:00:01');
is (FormatElapsedTime(86400*2),	'2:00:00:00',	'FormatElapsedTime - 2:00:00:00');


#
# UtilGetLock/UtilReleaseLock
#

my $Lock = UtilGetLock('suppress-output'=>1);		ok((defined($Lock) and $Lock),		'UtilGetLock - acquire lock');
my $Lock2 = UtilGetLock('suppress-output'=>1);		ok((defined($Lock2) and !$Lock2),	'UtilGetLock - duplicate lock rejected');
ok(UtilReleaseLock($Lock,'suppress-output'=>1),		'UtilReleaseLock - release lock');
ok(!UtilReleaseLock($Lock,'suppress-output'=>1),	'UtilReleaseLock - release unacquired lock');

#
# RunRemote
#

print "Note: No tests for RunRemote are currently available.\n";
