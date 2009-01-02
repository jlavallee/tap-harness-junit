use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
	module_name	=> 'TAP::Harness::JUnit',
	license		=> 'perl',
	dist_author	=> 'Lubomir Rintel (Good Data) <lubo.rintel@gooddata.com>',
	dist_version	=> '0.26',
	requires	=> {
		'TAP::Harness'	=> 3.05,
		'File::Temp'	=> 0,
		'TAP::Parser'	=> 0,
		'XML::Simple'	=> 0,
		'Scalar::Util'	=> 0,
		'Test::More'	=> 0,
		'Encode'	=> 0,
	},
);

$build->create_build_script;
