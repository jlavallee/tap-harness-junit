#!/usr/bin/perl

use TAP::Harness::JUnit;
use Test::More;
use XML::Simple;
use Test::Deep;
use File::Temp;
use File::Basename;
use Encode;

my %tests = (
	resultcode	=> 'Successful test with good plan and a bad return code',
	badplan		=> 'Has a plan, successful tests, just too small amount of them',
	funkyindent	=> 'Indentation of comments',
	uniquename	=> 'Multiple tests with identical names',
	nonutf8log	=> 'Special characters in log',
	earlyterm	=> 'Bad plan and non-zero return value',
);

plan tests => int (keys %tests);

foreach my $test (keys %tests) {
	my $model = dirname($0)."/tests/$test.xml";
	my $outfile = File::Temp->new (UNLINK => 0)->filename;

	$harness = new TAP::Harness::JUnit ({
		xmlfile		=> $outfile,
		verbosity	=> -1,
		merge		=> 1,
		exec		=> ['cat'],
	});

	$harness->runtests ([dirname($0)."/tests/$test.txt" => $tests{$test}]);

    my $expected = XMLin ($model);
    $expected->{testsuite}{'time'} = re('^\d+\.\d+');

    cmp_deeply(XMLin ($outfile), $expected, "Output of $test matches model");

    unlink $outfile;
}
