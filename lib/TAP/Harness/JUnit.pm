use warnings;
use strict;

=head1 NAME

TAP::Harness::JUnit - Generate JUnit compatible output from TAP results

=head1 SYNOPSIS

    use TAP::Harness::JUnit;
    my $harness = TAP::Harness::JUnit->new({
        xmlfile => 'output.xml',
        package => 'database',
        # ...
    });
    $harness->runtests(@tests);
    
    # set xmlfile via import()
    use TAP::Harness::JUnit xmlfile => 'output.xml';
    
    prove --harness TAP::Harness::JUnit=xmlfile,output.xml

=head1 DESCRIPTION

The only difference between this module and I<TAP::Harness> is that this module
adds the optional arguments 'xmlfile', 'package', and 'namemangle' that cause
the output to be formatted into XML in a format similar to the one that is
produced by the JUnit testing framework.

=head1 METHODS

This module inherits all functions from I<TAP::Harness>.

=cut

package TAP::Harness::JUnit;
use base 'TAP::Harness';

use Benchmark ':hireswallclock';
use File::Temp;
use TAP::Parser;
use XML::Simple;
use Scalar::Util qw/blessed/;
use Encode;

our $VERSION = '0.42';

=head2 new

These options are added (compared to I<TAP::Harness>):

=over

=item xmlfile

Name of the file XML output will be saved to. If this argument is omitted, the
default of "junit_output.xml" is used and a warning is issued.

Alternatively, the name of the output file can be specified either as a key/value
pair when use-ing this module (see L<#DESCRIPTION>) or in the
$JUNIT_OUTPUT_FILE environment variable.

=item package

The Hudson/Jenkins continuous-integration systems support separating test
results into "packages". By default any number of output xml files will be
merged into the default package "(root)".

Setting a package name will place all test results from the current run into
that package. You can also set the environment variable $JUNIT_PACKAGE to do
the same.

=item notimes (DEPRECATED)

If provided (and true), test case times will not be recorded.

=item namemangle

Specify how to mangle testcase names. This is sometimes required to interact
with buggy JUnit consumers that lack sufficient validation.

Alternatively, this value can be set in the environment variable
$JUNIT_NAME_MANGLE.

Available values are:

=over

=item hudson

Replace anything but alphanumeric characters with underscores. This is the
default for historic reasons.

=item perl (RECOMMENDED)

Replace slashes in the directory hierarchy with dots so that the filesystem
layout resembles a Java class hierarchy.

This is the recommended setting and may become the default in future.

=item none

Do not perform any transformations.

=back

=back

=head1 ENVIRONMENT VARIABLES

The name of the output file can be specified in the $JUNIT_OUTPUT_FILE
environment variable

The package name that Hudson/Jenkins use to categorise test results can be
specified in $JUNIT_PACKAGE.

The name mangling mechanism used to rewrite test names can be specified in
$JUNIT_NAME_MANGLE. (See namemangle documentation for available values.)

=cut

my $xmlfile_by_import;

sub import {
	my (undef, %args) = @_;
	$xmlfile_by_import = delete $args{xmlfile};
}

sub new {
	my ($class, $args) = @_;
	$args ||= {};

	# Process arguments
	my $xmlfile = delete $args->{xmlfile};

	$xmlfile = $xmlfile_by_import unless defined $xmlfile;

	$xmlfile = $ENV{JUNIT_OUTPUT_FILE} unless defined $xmlfile;
	unless ($xmlfile) {
		$xmlfile = 'junit_output.xml';
		warn 'xmlfile argument not supplied, defaulting to "junit_output.xml"';
	}

	my $xmlpackage = delete $args->{package};
	$xmlpackage = $ENV{JUNIT_PACKAGE} unless defined $xmlpackage;

	# Get the name of raw perl dump directory
	my $rawtapdir = $ENV{PERL_TEST_HARNESS_DUMP_TAP};
	$rawtapdir = $args->{rawtapdir} unless $rawtapdir;
	$rawtapdir = File::Temp::tempdir() unless $rawtapdir;
	delete $args->{rawtapdir};

	my $notimes = delete $args->{notimes};

	my $namemangle = delete $args->{namemangle};
	$namemangle = $ENV{JUNIT_NAME_MANGLE} unless defined $namemangle;
	unless ($namemangle) {
		$namemangle = 'hudson';
	}

	my $self = $class->SUPER::new($args);
	$self->{__xmlfile} = $xmlfile;
	$self->{__xml} = {testsuite => []};
	$self->{__xmlpackage} = $xmlpackage;
	$self->{__rawtapdir} = $rawtapdir;
	$self->{__cleantap} = not defined $ENV{PERL_TEST_HARNESS_DUMP_TAP};
	$self->{__notimes} = $notimes;
	$self->{__namemangle} = $namemangle;
	$self->{__auto_number} = 1;

	# Inject our parser, that persists results for later
	# consumption and adds timing information
	@TAP::Harness::JUnit::Parser::ISA = ($self->parser_class);
	$self->parser_class ('TAP::Harness::JUnit::Parser');

	return $self;
}

# Add "(number)" at the end of the test name if the test with
# the same name already exists in XML
sub uniquename {
	my $self = shift;
	my $xml  = shift;
	my $name = shift;

	my $newname;

	# Beautify a bit -- strip leading "- "
	# (that is added by Test::More)
	$name =~ s/^[\s-]*//;

	$self->{__test_names} = { map { $_->{name} => 1 } @{ $xml->{testcase} } }
		unless $self->{__test_names};

	while(1) {
		my $number = $self->{__auto_number};
		$newname = $name
				 ? $name.($number > 1 ? " ($number)" : '')
				 : "Unnamed test case $number"
		;
		last unless exists $self->{__test_names}->{$newname};
		$self->{__auto_number}++;
	};

	$self->{__test_names}->{$newname}++;

	return xmlsafe($newname);
}

# Add result of a single TAP parse to the XML
sub parsetest {
	my $self = shift;
	my $name = shift;
	my $parser = shift;

	my $time = $parser->end_time - $parser->start_time;
	$time = 0 if $self->{__notimes};

	# Get the return code of test script before re-parsing the TAP output
	my $badretval = $parser->exit;

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

	# Hudson/Jenkins strip the prefix from a classname to figure out the package
	my $prefixname = $self->{__xmlpackage}
		? $self->{__xmlpackage}.'.'.$name
		: $name;

	my $xml = {
		name => $prefixname,
		failures => 0,
		errors => 0,
		tests => undef,
		'time' => $time,
		testcase => [],
		'system-out' => [''],
		skipped => 0,
	};

	my $tests_run = 0;
	my $comment = ''; # Comment agreggator
	foreach my $result (@{$parser->{__results}}) {

		my $time = $result->{__end_time} - $result->{__start_time};
		$time = 0 if $self->{__notimes};

		# Counters
		if ($result->type eq 'plan') {
			$xml->{tests} = $result->tests_planned;
		}

		# Comments
		if ($result->type eq 'comment') {
			$result->raw =~ /^# (.*)/ and $comment .= xmlsafe($1)."\n";
		}

		# Errors
		if ($result->type eq 'unknown') {
			$comment .= xmlsafe($result->raw)."\n";
		}

		# Test case
		if ($result->type eq 'test') {
			$tests_run++;

			# JUnit can't express these -- pretend they do not exist
			$result->directive eq 'TODO' and next;
			
			my $test = {
				'time' => $time,
				name => $self->uniquename($xml, $result->description),
				classname => $prefixname,
			};

			if ($result->ok eq 'not ok') {
				$test->{failure} = [{
					type => blessed ($result),
					message => xmlsafe($result->raw),
					content => $comment,
				}];
				$xml->{failures}++;
			};
      
			if ($result->directive eq 'SKIP') {
				$test->{skipped} = [{
					message => xmlsafe($result->raw),
				}];
				$xml->{skipped}++;
			};

			push @{$xml->{testcase}}, $test;
			$comment = '';
		}

		# Log
		$xml->{'system-out'}->[0] .= xmlsafe($result->raw)."\n";
	}

	# Detect no plan
	unless (defined $xml->{tests}) {
		# Ensure XML will have non-empty value
		$xml->{tests} = 0;

		# Fake a failed test
		push @{$xml->{testcase}}, {
			'time' => $time,
			name => $self->uniquename($xml, 'Test died too soon, even before plan.'),
			classname => $prefixname,
			failure => {
				type => 'Plan',
				message => 'The test suite died before a plan was produced. You need to have a plan.',
				content => 'No plan',
			},
		};
		$xml->{errors}++;
	}

	# Detect bad plan
	elsif ($xml->{errors} = $xml->{tests} - $tests_run) {
		# Fake an error
		push @{$xml->{testcase}}, {
			'time' => $time,
			name => $self->uniquename($xml, 'Number of runned tests does not match plan.'),
			classname => $prefixname,
			failure => {
				type => 'Plan',
				message => ($xml->{errors} > 0
					? 'Some test were not executed, The test died prematurely.'
					: 'Extra tests tun.'),
				content => 'Bad plan',
			},
		};
		$xml->{failures}++;
		$xml->{errors} = abs ($xml->{errors});
	}

	# Bad return value. See BUGS
	elsif ($badretval and not $xml->{failures}) {
		# Fake an error
		push @{$xml->{testcase}}, {
			'time' => $time,
			name => $self->uniquename($xml, 'Test returned failure'),
			classname => $prefixname,
			failure => {
				type => 'Died',
				message => "Test died with return code $badretval",
				content => "Test died with return code $badretval",
			},
		};
		$xml->{errors}++;
		$xml->{tests}++;
	}

	# Add this suite to XML
	push @{$self->{__xml}->{testsuite}}, $xml;
}

sub runtests {
	my ($self, @files) = @_;

	my $aggregator = $self->SUPER::runtests(@files);

	foreach my $test (keys %{$aggregator->{parser_for}}) {
		$self->parsetest ($test => $aggregator->{parser_for}->{$test});
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

# Because not all utf8 characters are allowed in xml, only these
#    Char       ::=      #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
# http://www.w3.org/TR/REC-xml/#NT-Char
sub xmlsafe {
	my $s = shift;

	return '' unless defined $s && length($s) > 0;

	$s =~ s/([\x00|\x01|\x02|\x03|\x04|\x05|\x06|\x07|\x08|\x0B|\x0C|\x0E|\x0F|\x11|\x12|\x13|\x14|\x15|\x16|\x17|\x18|\x19|\x1A|\x1B|\x1C|\x1D|\x1E|\x1F])/ sprintf("<%0.2x>", ord($1)) /gex;


	return $s;
}

# This is meant to transparently extend the parser chosen by user.
# Dynamically superubclassed to the chosen parser upon harnsess construction.
package TAP::Harness::JUnit::Parser;

use Time::HiRes qw/time/;

# Upon each line taken, account for time and remember the exact
# result. A harness should then collect the results from the aggregator.
sub next
{
	my $self = shift;
	my $result = $self->SUPER::next (@_);
	return $result unless $result; # last call

	# First assert
	unless ($self->{__results}) {
		$self->{__last_assert} = $self->start_time;
		$self->{__results} = []
	}

	# Account for time taken
	$result->{__start_time} = $self->{__last_assert};
	$result->{__end_time} = $self->{__last_assert} = time;

	# Remember for the aggregator
	push @{$self->{__results}}, $result;

	return $result;
}

=head1 SEE ALSO

I<TAP::Formatter::JUnit> at L<https://metacpan.org/pod/TAP::Formatter::JUnit>

The JUnit XML schema was obtained from
L<http://jra1mw.cvs.cern.ch:8180/cgi-bin/jra1mw.cgi/org.glite.testing.unit/config/JUnitXSchema.xsd?view=markup>.

=head1 ACKNOWLEDGEMENTS

This module was partly inspired by Michael Peters's I<TAP::Harness::Archive>.
It was originally written by Lubomir Rintel (GoodData)
C<< <lubo.rintel@gooddata.com> >> and includes code from several contributors.

The following people (in no specific order) have reported problems or
contributed code to I<TAP::Harness::JUnit>:

=over

=item David Ritter

=item Jeff Lavallee

=item Andreas Pohl

=item Ton Voon

=item Kevin Goess

=item Richard Huxton

=item David E. Wheeler

=item Malcolm Parsons

=item Finn Smith

=item Toby Broyles

=back

=head1 BUGS

The comments that are above the C<ok> or C<not ok> are considered the output of
the test. This, though being more logical, is against TAP specification.

I<XML::Simple> is used to generate the output. This is suboptimal and involves
some hacks.

During testing the resulting files are not tested against the schema. This
would be a good thing to do.

=head1 CONTRIBUTING

Source code for I<TAP::Harness::JUnit> is kept in a public Git repository.
Visit L<https://github.com/jlavallee/tap-harness-junit>.

Bug reports and feature enhancement requests are tracked at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=TAP-Harness-JUnit>.

=head1 COPYRIGHT & LICENSE

Copyright 2008, 2009, 2010, 2011, 2012, 2013 I<TAP::Harness::JUnit>
contributors. All rights reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
