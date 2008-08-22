#!/usr/bin/perl

#my $record = 1;

use TAP::Harness::JUnit;
use Test::More;
use XML::Simple;
use File::Temp;
use File::Basename;

my %tests = (
	resultcode	=> 'Successful tet with good plan and a bad return code',
	badplan		=> 'Has a plan, successful tests, just too small amount of them',
	funkyindent	=> 'Indentation of comments',
);

plan tests => int (keys %tests);

foreach my $test (keys %tests) {
	my $model = dirname($0)."/tests/$test.xml";
	my $outfile = ($record ? $model : File::Temp->new (UNLINK => 0)->filename);

	$harness = new TAP::Harness::JUnit ({
		xmlfile		=> $outfile,
		verbosity	=> -1,
		merge		=> 1,
	});

	$harness->runtests ([dirname($0)."/tests/$test.pl" => $tests{$test}]);

	unless ($record) {
		is_deeply (XMLin ($outfile), XMLin ($model));
		#print STDERR "$outfile $model\n";
		unlink $outfile;
	}
}
