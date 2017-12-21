#!/usr/bin/perl

# This test tests whether TAP::Harness::JUnit can be
# instantialized without a xmlfile argument (rt#42069)

use strict;
use warnings;

use TAP::Harness::JUnit;
use Test::More;

plan tests => 7;

my $harness;

# case#  env    import new
# ------ ------ ------ ------
#        -      -      -      => default (tested by t/xmlfile_default.t)
# 1      -      -      Z      => Z
# 2      -      Y      -      => Y
# 3      -      Y      Z      => Z
# 4      X      -      -      => X
# 5      X      -      Z      => Z
# 6      X      Y      -      => Y
# 7      X      Y      Z      => Z

# case 1
$harness = TAP::Harness::JUnit->new({ xmlfile => 'new' });
is( 'new', $harness->{__xmlfile} );

# case 2
TAP::Harness::JUnit->import( xmlfile => 'import' );
$harness = TAP::Harness::JUnit->new;
is( 'import', $harness->{__xmlfile} );
# cleanp import-ed xmlfile
TAP::Harness::JUnit->import;

# case 3
$harness = TAP::Harness::JUnit->new({ xmlfile => 'new' });
is( 'new', $harness->{__xmlfile} );

{

local %ENV = ( JUNIT_OUTPUT_FILE => 'env' );

# case 4
$harness = TAP::Harness::JUnit->new;
is( 'env', $harness->{__xmlfile} );

# case 5
$harness = TAP::Harness::JUnit->new({ xmlfile => 'new' });
is( 'new', $harness->{__xmlfile} );

# case 6
TAP::Harness::JUnit->import( xmlfile => 'import' );
$harness = TAP::Harness::JUnit->new;
is( 'import', $harness->{__xmlfile} );
# cleanp import-ed xmlfile
TAP::Harness::JUnit->import;

# case 7
$harness = TAP::Harness::JUnit->new({ xmlfile => 'new' });
is( 'new', $harness->{__xmlfile} );

}
