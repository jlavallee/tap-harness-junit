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
this adds optional 'xmlfile' argument, that causes the output to
be formatted into XML in format similar to one that is produced by
JUnit testing framework.

=head1 METHODS

This modules inherits all functions from I<TAP::Harness>.

=cut

package TAP::Harness::JUnit;
use base 'TAP::Harness';

use Benchmark ':hireswallclock';
use File::Temp;
use TAP::Parser;
use XML::Simple;
use Scalar::Util qw/blessed/;
use Encode;

our $VERSION = '0.26';

=head2 new

These options are added (compared to I<TAP::Harness>):

=over

=item xmlfile

Name of the file XML output will be saved to.  In case this argument
is ommited, default of "junit_output.xml" is used and a warning is issued.

=item notimes

If provided (and true), test case times will not be recorded.

=back

=cut

sub new {
	my ($class, $args) = @_;
	$args ||= {};

	# Process arguments
	my $xmlfile;
	unless ($xmlfile = $args->{xmlfile}) {
		$xmlfile = 'junit_output.xml';
		warn 'xmlfile argument not supplied, defaulting to "junit_output.xml"';
	}
	defined $args->{merge} or
		warn 'You should consider using "merge" parameter. See BUGS section of TAP::Harness::JUnit manual';

	# Get the name of raw perl dump directory
	my $rawtapdir = $ENV{PERL_TEST_HARNESS_DUMP_TAP};
	$rawtapdir = $args->{rawtapdir} unless $rawtapdir;
	$rawtapdir = File::Temp::tempdir() unless $rawtapdir;

	my $notimes = $args->{notimes};

	# Don't pass these to TAP::Harness
	delete $args->{rawtapdir};
	delete $args->{xmlfile};
	delete $args->{notimes};

	my $self = $class->SUPER::new($args);
	$self->{__xmlfile} = $xmlfile;
	$self->{__xml} = {testsuite => []};
	$self->{__rawtapdir} = $rawtapdir;
	$self->{__cleantap} = not defined $ENV{PERL_TEST_HARNESS_DUMP_TAP};
	$self->{__notimes} = $notimes;

	return $self;
}

# Add "(number)" at the end of the test name if the test with
# the same name already exists in XML
sub uniquename {
	my $xml = shift;
	my $name = shift;

	my $newname;
	my $number = 1;

	# Beautify a bit -- strip leading "- "
	# (that is added by Test::More)
	$name =~ s/^[\s-]*//;

	NAME: while (1) {
		if ($name) {
			$newname = $name;
			$newname .= " ($number)" if $number > 1;
		} else {
			$newname = "Unnamed test case $number";
		}

		$number++;
		foreach my $testcase (@{$xml->{testcase}}) {
			next NAME if $newname eq $testcase->{name};
		}

		return $newname;
	}
}

# Add a single TAP output file to the XML
sub parsetest {
	my $self = shift;
	my $file = shift;
	my $name = shift;
	my $time = shift;

	my $badretval;

	my $xml = {
		name => $name,
		failures => 0,
		errors => 0,
		tests => undef,
		'time' => $time,
		testcase => [],
		'system-out' => [''],
	};

	open (my $tap_handle, $self->{__rawtapdir}.'/'.$file)
		or die $!;
	my $rawtap = join ('', <$tap_handle>);
	close ($tap_handle);

	my $parser = new TAP::Parser ({'tap' => $rawtap });

	my $tests_run = 0;
	my $comment = ''; # Comment agreggator
	while ( my $result = $parser->next ) {

		# Counters
		if ($result->type eq 'plan') {
			$xml->{tests} = $result->tests_planned;
		}

		# Comments
		if ($result->type eq 'comment') {
			# See BUGS
			$badretval = $result if $result->comment =~ /Looks like your test died/;

			#$comment .= $result->comment."\n";
			# ->comment has leading whitespace stripped
			$result->raw =~ /^# (.*)/ and $comment .= $1."\n";
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
				name => uniquename ($xml, $result->description),
				classname => $name,
			};

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

	# Detect no plan
	unless (defined $xml->{tests}) {
		# Ensure XML will have non-empty value
		$xml->{tests} = 0;

		# Fake a failed test
		push @{$xml->{testcase}}, {
			'time' => 0,
			name => uniquename ($xml, 'Test died too soon, even before plan.'),
			classname => $name,
			failure => {
				type => 'Plan',
				message => 'The test suite died before a plan was produced. You need to have a plan.',
				content => 'No plan',
			},
		};
		$xml->{errors}++;
	}

	# Detect bad plan
	elsif ($xml->{failures} = $xml->{tests} - $tests_run) {
		# Fake a failed test
		push @{$xml->{testcase}}, {
			'time' => 0,
			name => uniquename ($xml, 'Number of runned tests does not match plan.'),
			classname => $name,
			failure => {
				type => 'Plan',
				message => ($xml->{failures} > 0
					? 'Some test were not executed, The test died prematurely.'
					: 'Extra tests tun.'),
				content => 'Bad plan',
			},
		};
		$xml->{errors}++;
		$xml->{failures} = abs ($xml->{failures});
	}

	# Bad return value. See BUGS
	elsif ($badretval and not $xml->{errors}) {
		# Fake a failed test
		push @{$xml->{testcase}}, {
			'time' => 0,
			name => uniquename ($xml, 'Test returned failure'),
			classname => $name,
			failure => {
				type => 'Died',
				message => $badretval->comment,
				content => $badretval->raw,
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
		$comment =~ s/[^a-zA-Z0-9, ]/_/g;

		$self->parsetest ($file, $comment, $self->{__notimes} ? 0 : $aggregator->elapsed->[0]);
	}

	# Format XML output
	my $xs = new XML::Simple;
	my $xml = $xs->XMLout ($self->{__xml}, RootName => 'testsuites');

	# Ensure it is valid XML. Not very smart though.
	$xml = encode ('UTF-8', decode ('UTF-8', $xml));

	# Dump output
	open my $xml_fh, '>', $self->{__xmlfile}
		or die $self->{__xmlfile}.': '.$!;
	print $xml_fh "<?xml version='1.0' encoding='utf-8'?>\n";
	print $xml_fh $xml;
	close $xml_fh;

	# If we caused the dumps to be preserved, clean them
	File::Path::rmtree($self->{__rawtapdir}) if $self->{__cleantap};

	return $aggregator;
}

=head1 SEE ALSO

JUnit XML schema was obtained from L<http://jra1mw.cvs.cern.ch:8180/cgi-bin/jra1mw.cgi/org.glite.testing.unit/config/JUnitXSchema.xsd?view=markup>.

=head1 ACKNOWLEDGEMENTS

This module was partly inspired by Michael Peters' I<TAP::Harness::Archive>.

Following people (in no specific order) have reported problems
or contributed fixes to I<TAP::Harness::JUnit>:

=over

=item David Ritter

=item Jeff Lavallee

=item Andreas Pohl

=back

=head1 BUGS

Test return value is ignored. This is actually not a bug, I<TAP::Parser> doesn't present
the fact and TAP specification does not require that anyway.

Note that this may be a problem when running I<Test::More> tests with C<no_plan>,
since it will add a plan matching the number of tests actually run even in case
the test dies. Do not do that -- always write a plan! In case it's not possible,
pass C<merge> argument when creating a I<TAP::Harness::JUnit> instance, and the
harness will detect such failures by matching certain comments.

Test durations are always set to 0 seconds, but testcase durations are recorded unless the "notimes" parameter is provided (and true).

The comments that are above the C<ok> or C<not ok> are considered the output
of the test. This, though being more logical, is against TAP specification.

I<XML::Simple> is used to generate the output. It is suboptimal and involves
some hacks.

During testing, the resulting files are not tested against the schema, which
would be a good thing to do.

=head1 AUTHOR

Lubomir Rintel (Good Data) C<< <lubo.rintel@gooddata.com> >>

Source code for I<TAP::Harness::JUnit> is kept in a public GIT repository.
Visit L<http://repo.or.cz/w/TAP-Harness-JUnit.git> to get it.

=head1 COPYRIGHT & LICENSE

Copyright 2008, 2009 Good Data, All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
