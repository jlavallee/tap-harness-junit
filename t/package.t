#!/usr/bin/perl

use TAP::Harness::JUnit;
use Test::More;
use XML::Simple;
use File::Temp;
use File::Basename;
use Encode;

my %tests = (
	package => 'Package prefix test',
);

plan tests => 8 * int (keys %tests);

my $our_cat  = [$^X, qw/-ne print/];
my $our_cat2 = join(' ', @$our_cat);

foreach my $test (keys %tests) {
	my $model = dirname($0)."/tests/$test.xml";
	my $outfile = File::Temp->new (UNLINK => 0)->filename;

	my $harness = new TAP::Harness::JUnit ({
		xmlfile		=> $outfile,
		verbosity	=> -1,
		merge		=> 1,
		exec		=> $our_cat,
		notimes		=> 1,
	});

	$harness->runtests ([dirname($0)."/tests/$test.txt" => $tests{$test}]);

	# Repeat with explicit empty package
	my $outfile_p0 = File::Temp->new (UNLINK => 0)->filename;

	my $harness_p0 = new TAP::Harness::JUnit ({
		xmlfile		=> $outfile_p0,
		package     => '',
		verbosity	=> -1,
		merge		=> 1,
		exec		=> $our_cat,
		notimes		=> 1,
	});

	$harness_p0->runtests ([dirname($0)."/tests/$test.txt" => $tests{$test}]);

	# Repeat with a defined package
	my $model_pkg  = dirname($0)."/tests/$test.qqq.xml";
	my $outfile_p1 = File::Temp->new (UNLINK => 0)->filename;

	my $harness_p1 = new TAP::Harness::JUnit ({
		xmlfile		=> $outfile_p1,
		package     => 'QQQ',
		verbosity	=> -1,
		merge		=> 1,
		exec		=> $our_cat,
		notimes		=> 1,
	});

	$harness_p1->runtests ([dirname($0)."/tests/$test.txt" => $tests{$test}]);

	# Repeat with package in ENV
	my $outfile_p2 = File::Temp->new (UNLINK => 0)->filename;
	$ENV{JUNIT_PACKAGE} = 'QQQ';
	my $harness_p2 = new TAP::Harness::JUnit ({
		xmlfile		=> $outfile_p2,
		verbosity	=> -1,
		merge		=> 1,
		exec		=> $our_cat,
		notimes		=> 1,
	});

	$harness_p2->runtests ([dirname($0)."/tests/$test.txt" => $tests{$test}]);

	is_deeply (XMLin ($outfile), XMLin ($model), "Output of $test (no package) matches model");
	eval { decode ('UTF-8', `$our_cat2 $outfile`, Encode::FB_CROAK) };
	ok (!$@, "Output of $test is valid UTF-8");
	unlink $outfile;

	is_deeply (XMLin ($outfile_p0), XMLin ($model), "Output of $test (empty package) matches model");
	eval { decode ('UTF-8', `$our_cat2 $outfile_p0`, Encode::FB_CROAK) };
	ok (!$@, "Output of $test is valid UTF-8");
	unlink $outfile_p0;

	is_deeply (XMLin ($outfile_p1), XMLin ($model_pkg), "Output of $test (defined package) matches model");
	eval { decode ('UTF-8', `$our_cat2 $outfile_p1`, Encode::FB_CROAK) };
	ok (!$@, "Output of $test is valid UTF-8");
	unlink $outfile_p1;

	is_deeply (XMLin ($outfile_p2), XMLin ($model_pkg), "Output of $test (package through ENV) matches model");
	eval { decode ('UTF-8', `$our_cat2 $outfile_p2`, Encode::FB_CROAK) };
	ok (!$@, "Output of $test is valid UTF-8");
	unlink $outfile_p2;
}
