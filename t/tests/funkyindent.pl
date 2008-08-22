#!/usr/bin/perl

use Test::More qw/no_plan/;

diag ("abcd");
diag ("    abcd");
diag ("        abcd");
diag ("<<< >>      abcd");
ok (0, "This is not ok");
diag ("<<< >>      abcd");
diag ("<<< >>      abcd");
diag ("        abcd");
