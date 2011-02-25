use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
	module_name	=> 'TAP::Harness::JUnit',
	license		=> 'perl',
	dist_author	=> 'Lubomir Rintel (GoodData) <lubo.rintel@gooddata.com>',
	dist_version_from => 'lib/TAP/Harness/JUnit.pm',
	meta_merge     => {
		resources => {
			bugtracker => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=TAP-Harness-JUnit',
			repository => 'https://github.com/jlavallee/tap-harness-junit',
		}
	},
	requires	=> {
		'TAP::Harness'	=> 3.05,
		'File::Temp'	=> 0,
		'TAP::Parser'	=> 0,
		'XML::Simple'	=> 0,
		'Scalar::Util'	=> 0,
		'Test::More'	=> 0,
		'Encode'	=> 0,
	},
	build_requires => {
		'Test::Deep'	=> 0,
	}
);

$build->create_build_script;
