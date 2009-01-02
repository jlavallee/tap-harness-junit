#!/usr/bin/perl

# This test tests whether TAP::Harness::JUnit can be
# instantialized without a xmlfile argument (rt#42069)

use strict;
use warnings;

use TAP::Harness::JUnit;
use Test::More;

plan tests => 3;

my $harness;
close STDERR;
eval { $harness = TAP::Harness::JUnit->new };

ok( !$@ );
ok( $harness );
isa_ok( $harness, 'TAP::Harness::JUnit');
