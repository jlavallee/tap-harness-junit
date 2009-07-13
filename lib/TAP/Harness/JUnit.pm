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

our $VERSION = '0.32';

=head2 new

These options are added (compared to I<TAP::Harness>):

=over

=item xmlfile

Name of the file XML output will be saved to.  In case this argument
is ommited, default of "junit_output.xml" is used and a warning is issued.

=item notimes (DEPRECATED)

If provided (and true), test case times will not be recorded.

=item namemangle

Specify how to mangle testcase names. This is sometimes required to
interact with buggy JUnit consumers that lack sufficient validation.
Available values are:

=over

=item hudson

Replace anything but alphanumeric characters with underscores.
This is default for historic reasons.

=item perl (RECOMMENDED)

Replace slashes in directory hierarchy with dots so that the
filesystem layout resemble Java class hierarchy.

This is the recommended setting and may become a default in
future.

=item none

Do not do any transformations.

=back

=back

=cut

sub new {
	my ($class, $args) = @_;
	$args ||= {};

	# Process arguments
	my $xmlfile;
	unless ($xmlfile = delete $args->{xmlfile}) {
		$xmlfile = 'junit_output.xml';
		warn 'xmlfile argument not supplied, defaulting to "junit_output.xml"';
	}
	defined $args->{merge} or
		warn 'You should consider using "merge" parameter. See BUGS section of TAP::Harness::JUnit manual';

	# Get the name of raw perl dump directory
	my $rawtapdir = $ENV{PERL_TEST_HARNESS_DUMP_TAP};
	$rawtapdir = $args->{rawtapdir} unless $rawtapdir;
	$rawtapdir = File::Temp::tempdir() unless $rawtapdir;
	delete $args->{rawtapdir};

	my $notimes = delete $args->{notimes};

	my $self = $class->SUPER::new($args);
	$self->{__xmlfile} = $xmlfile;
	$self->{__xml} = {testsuite => []};
	$self->{__rawtapdir} = $rawtapdir;
	$self->{__cleantap} = not defined $ENV{PERL_TEST_HARNESS_DUMP_TAP};
	$self->{__notimes} = $notimes;
	if (defined $args->{namemangle}) {
		$self->{__namemangle} = $args->{namemangle};
	} else {
		$self->{__namemangle} = 'hudson';
	}

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
	my $parser = shift;

	my $time = $parser->{end_time} - $parser->{start_time};
	$time = 0 if $self->{__notimes};

	my $badretval;

	if ($self->{__namemangle}) {
		# Older version of hudson crafted an URL of the test
		# results using the name verbatim. Unfortunatelly,
		# they didn't escape special characters, soo '/'-s
		# and family would result in incorrect URLs.
		# See hudson bug #2167
		$self->{__namemangle} eq 'hudson'
			and $name =~ s/[^a-zA-Z0-9, ]/_/g;

		# Transform hierarchy of directories into what would
		# look like hierarchy of classes in Hudson
		if ($self->{__namemangle} eq 'perl') {
			$name =~ s/^[\.\/]*//;
			$name =~ s/\./_/g;
			$name =~ s/\//./g;
		}
	}

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

	# Reset the parser, so we can reparse the output, iterating through it
	$parser = new TAP::Parser ({'tap' => $rawtap });

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

	# Make up times for sub-tests
	if ($time) {
		foreach my $testcase (@{$xml->{testcase}}) {
			$testcase->{time} = $time / @{$xml->{testcase}};
		}
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

		# Comment for the file is the file name unless overriden
		if (ref $test eq 'ARRAY') {
			($file, $comment) = @{$test};
		} else {
			$file = $test;
		}
		$comment = $file unless defined $comment;

		$self->parsetest ($file, $comment, $aggregator->{parser_for}->{$comment});
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

Test durations are not mesaured. Unless the "notimes" parameter is provided (and
true), the test duration is recorded as testcase duration divided by number of
tests, otherwise it's set to 0 seconds. This could be addressed if the module
was reimplmented as a formatter.

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
