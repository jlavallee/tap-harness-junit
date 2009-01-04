#!/usr/bin/perl

my $record = $ENV{T_REC};

use TAP::Harness::JUnit;
use Test::More;
use XML::Simple;
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

plan tests => 2 * int (keys %tests);

foreach my $test (keys %tests) {
	my $model = dirname($0)."/tests/$test.xml";
	my $outfile = ($record ? $model : File::Temp->new (UNLINK => 0)->filename);

	$harness = new TAP::Harness::JUnit ({
		xmlfile		=> $outfile,
		verbosity	=> -1,
		merge		=> 1,
		exec		=> ['cat'],
		notimes		=> 1,
	});

	$harness->runtests ([dirname($0)."/tests/$test.txt" => $tests{$test}]);

	unless ($record) {
		is_deeply (XMLin ($outfile), XMLin ($model), "Output of $test matches model");
		eval { decode ('UTF-8', `cat $outfile`, Encode::FB_CROAK) };
		ok (!$@, "Output of $test is valid UTF-8");
		unlink $outfile;
	}
}
