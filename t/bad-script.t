use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Fatal;
use Test::DZil;

my $tzil = Builder->from_config(
	{ dist_root => 't/does_not_exist' },
	{
		add_files => {
			'source/dist.ini' => simple_ini(
				'GatherDir',
				'ExecDir',  # defaults to bin/
				'ModuleBuildTiny',
			),
			'source/bin/exe' => 'executable content',
		},
	},
);

like(
	exception { $tzil->build },
	qr{detected file 'bin/exe' that will not be installed as an executable - move it to script},
	'warning issued when there is an ExecFile outside of script/',
);

done_testing;

# vim: set ts=4 sw=4 noet nolist :
