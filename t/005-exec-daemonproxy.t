use strict;
use warnings;
use FindBin;
use Test::More;
use Log::Any '$log';
use Log::Any::Adapter 'TAP';
use File::Slurp 'slurp','write_file';

my $tmp_path= "$FindBin::Bin/tmp/005";
`mkdir -p $tmp_path`; $? == 0 or die;
write_file($tmp_path."/desd.conf.yaml", "---\n") or die;

my $desd_script= "$FindBin::Bin/../bin/desd.pl";
-f $desd_script or die "Can't find desd.pl ($desd_script)\n";

my $dp_path= "$FindBin::Bin/lib/MockDaemonproxy.pl";
chmod 0755, $dp_path;

my $daemonproxy_input= `"$desd_script" --base-dir="$tmp_path" --daemonproxy_path="$dp_path"`;

like( $daemonproxy_input, qr/^service.args\t.*\t\Q$desd_script\E/m, 'running correct desd path' )
&& like ( $daemonproxy_input, qr/^service.fds\t.*\tcontrol.socket/m, 'attached to control socket' )
or diag( explain $daemonproxy_input );

done_testing;
