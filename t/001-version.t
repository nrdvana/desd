use strict;
use warnings;
use FindBin;
use Test::More;
use Log::Any '$log';
use Log::Any::Adapter 'TAP';

use_ok( 'App::Desd' );
my $version= App::Desd->VERSION;

my $desd_script= "$FindBin::Bin/../bin/desd.pl";
-f $desd_script or die "Can't find desd.pl ($desd_script)\n";

my $cmdline_ver= `"$desd_script" --version`;
$cmdline_ver =~ /^desd version (\d+\.\d+)$/m or die "Can't parse version";
is( $1, $version, 'commandline reports correct version' );

`grep '^Version $version\$' "$FindBin::Bin/../Changes"`;
is( $?, 0, 'found version in Changes' );

done_testing;
