#!/usr/bin/perl

use TAP::Harness::JUnit;
use Test::More;
use XML::Simple;
use Test::Deep;
use File::Temp;
use File::Basename;
use Encode;

my %tests = (
	resultcode  => 'Successful test with good plan and a bad return code',
	badplan     => 'Has a plan, successful tests, just too small amount of them',
	funkyindent => 'Indentation of comments',
	uniquename  => 'Multiple tests with identical names',
	nonutf8log  => 'Special characters in log',
	earlyterm   => 'Bad plan and non-zero return value',
	empty       => 'Zero-length output',
);

plan tests => int (keys %tests);

my $our_cat  = [$^X, qw/-ne print/];

foreach my $test (keys %tests) {
	my $model = dirname($0)."/tests/$test.xml";
	my $outfile = File::Temp->new (UNLINK => 1)->filename;

	$harness = new TAP::Harness::JUnit ({
		xmlfile     => $outfile,
		verbosity   => -1,
		merge       => 1,
		exec        => $our_cat,
	});

	$harness->runtests ([dirname($0)."/tests/$test.txt" => $tests{$test}]);

	my $expected = XMLin ($model);
	my $testcase = $expected->{testsuite}{testcase};

	# Each time key must be replaced with a regex match
	foreach my $test (
		$expected->{testsuite}, $testcase,
		map { $testcase->{$_} } keys %$testcase
	) {
		next unless defined $test->{'time'};
		$test->{'time'} = re ('^\d+(:?\.\d+)?');
	}

	cmp_deeply(XMLin ($outfile), $expected, "Output of $test matches model");
}
