#!/usr/bin/perl

use Test::More tests => 2;

ok (1, "First");
die "Yielding non-zero return value";
