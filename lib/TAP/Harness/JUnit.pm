use warnings;
use strict;

=head1 NAME

TAP::Harness::JUnit - Generate JUnit compatible output from TAP results

=head1 SYNOPSIS

    use TAP::Harness::JUnit;
    my $harness = TAP::Harness::JUnit->new({
    	xmlfile => 'output.xml',
    	...
    });
    $harness->runtests(@tests);

=head1 DESCRIPTION

The only difference between this module and I<TAP::Harness> is that
this adds mandatory 'xmlfile' argument, that causes the output to
be formatted into XML in format similar to one that is produced by
JUnit testing framework.

=head1 METHODS

This modules inherits all functions from I<TAP::Harness>.

=cut

package TAP::Harness::JUnit;
use base 'TAP::Harness';

use File::Temp;
use TAP::Parser;
use XML::Simple;
use Scalar::Util qw/blessed/;

our $VERSION = '0.22';

=head2 new

These options are added (compared to I<TAP::Harness>):

=over

=item xmlfile

Name of the file XML output will be saved to.

=back

=cut

sub new {
	my ($class, $args) = @_;
	$args ||= {};

	# Process arguments
	my $xmlfile = $args->{xmlfile} or
		$class->_croak("'xmlfile' argument is mandatory");

	# Get the name of raw perl dump directory
	my $rawtapdir = $ENV{PERL_TEST_HARNESS_DUMP_TAP};
	$rawtapdir = $args->{rawtapdir} unless $rawtapdir;
	$rawtapdir = File::Temp::tempdir() unless $rawtapdir;

	# Don't pass these to TAP::Harness
	delete $args->{rawtapdir};
	delete $args->{xmlfile};

	my $self = $class->SUPER::new($args);
	$self->{__xmlfile} = $xmlfile;
	$self->{__xml} = {testsuite => []};
	$self->{__rawtapdir} = $rawtapdir;
	$self->{__cleantap} = not defined $ENV{PERL_TEST_HARNESS_DUMP_TAP};

	return $self;
}

sub parsetest {
	my $self = shift;
	my $file = shift;
	my $name = shift;

	my $xml = {
		name => $name,
		failures => 0,
		errors => 0,
		tests => 0,
		'time' => 0,
		testcase => [],
		'system-out' => [''],
	};

	my $parser = new TAP::Parser ({'exec' => ['/bin/cat', $self->{__rawtapdir}.'/'.$file]});

	my $tests_run = 0;
	my $comment = ''; # Comment agreggator
	while ( my $result = $parser->next ) {

		# Counters
		if ($result->type eq 'plan') {
			$xml->{tests} = $result->tests_planned;
		}

		# Comments
		if ($result->type eq 'comment') {
			$comment .= $result->comment."\n";
		}

		# Errors
		if ($result->type eq 'unknown') {
			$comment .= $result->raw."\n";
		}

		# Test case
		if ($result->type eq 'test') {
			$tests_run++;

			# JUnit can't express these -- pretend they do not exist
			$result->directive eq 'TODO' and next;
			$result->directive eq 'SKIP' and next;

			my $test = {
				'time' => 0,
				name => $result->description,
				classname => $name,
			};

			# Beautify a bit -- strip leading "- "
			# (that is added by Test::More)
			$test->{name} =~ s/^[\s-]*//;

			if ($result->ok eq 'not ok') {
				$test->{failure} = [{
					type => blessed ($result),
					message => $result->raw,
					content => $comment,
				}];
				$xml->{errors}++;
			};

			push @{$xml->{testcase}}, $test;
			$comment = '';
		}

		# Log
		$xml->{'system-out'}->[0] .= $result->raw."\n";
	}

	# Detect bad plan
	if ($xml->{failures} = $xml->{tests} - $tests_run) {
		# Fake a failed test
		push @{$xml->{testcase}}, {
			'time' => 0,
			name => 'Test died too soon, some test did not execute.',
			classname => $name,
			failure => {
				type => 'Plan',
				message => 'Some test were not executed. The test died prematurely.',
				content => 'Bad plan',
			},
		};
		$xml->{errors}++;
	}

	# Add this suite to XML
	push @{$self->{__xml}->{testsuite}}, $xml;
}

sub runtests {
	my ($self, @files) = @_;

	$ENV{PERL_TEST_HARNESS_DUMP_TAP} = $self->{__rawtapdir};
	my $aggregator = $self->SUPER::runtests(@files);

	foreach my $test (@files) {
		my $file;
		my $comment;

		if (ref $test eq 'ARRAY') {
			($file, $comment) = @{$test};
		} else {
			$file = $test;
		}
		$comment = $file unless defined $comment;

		# Hudson crafts an URL of the test results using the comment verbatim.
		# Unfortunatelly, they don't escape special characters.
		# '/'-s and family will result in incorrect URLs.
		# Filed here: https://hudson.dev.java.net/issues/show_bug.cgi?id=2167
		$comment =~ s/[^a-zA-Z0-9 ]/_/g;

		$self->parsetest ($file, $comment);
	}

	# Format XML output
	my $xs = new XML::Simple;
	my $xml = $xs->XMLout ($self->{__xml}, RootName => 'testsuites');

	open (XMLFILE, '>'.$self->{__xmlfile})
		or die $self->{__xmlfile}.': '.$!;
	print XMLFILE "<?xml version='1.0' encoding='utf-8'?>\n";
	print XMLFILE $xml;
	close (XMLFILE);

	# If we caused the dumps to be preserved, clean them
	File::Path::rmtree($self->{__rawtapdir}) if $self->{__cleantap};

	return $aggregator;
}

=head1 SEE ALSO

JUnit XML schema was obtained from L<http://jra1mw.cvs.cern.ch:8180/cgi-bin/jra1mw.cgi/org.glite.testing.unit/config/JUnitXSchema.xsd?view=markup>.

=head1 ACKNOWLEDGEMENTS

This module was partly inspired by Michael Peters' I<TAP::Harness::Archive>.

=head1 BUGS

Test return value is ignored. This is actually not a bug, I<TAP::Parser> doesn't present
the fact and TAP specification does not require that anyway.

Test durations are always set to 0 seconds.

The comments that are above the C<ok> or C<not ok> are considered the output
of the test. This, though being more logical, is against TAP specification.

L<XML::Simple> is used to generate the output. It is suboptimal and involves
some hacks.

=head1 AUTHOR

Lubomir Rintel (Good Data) C<< <lubo.rintel@gooddata.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Good Data, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
