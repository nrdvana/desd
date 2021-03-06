#! /usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use FindBin;
use lib "$FindBin::Bin/../lib";

=head1 SYNOPSIS

  desd [-d BASE_DIR] [-s CONTROL_SOCKET] [-c CONFIG_FILE]

Where BASE_DIR defaults to the current dir, CONTROL_SOCKET defaults to $base/desd.control
and CONFIG_FILE defaults to $base/desd.conf.yaml

=head1 OPTIONS

=over

=item -d PATH

=item --base-dir PATH

Change to PATH before starting or after receiving certain signals.  If PATH is
relative to the current directory, it will be prefixed by the canonical form
of the current directory.  If PATH contains symlinks they will be preserved
and re-traversed during later chdir()s.

=item -c CONFIGFILE

=item --config CONFIGFILE

Use CONFIGFILE instead of the default "./desd.conf.yaml".  Note that relative paths
are relative to base-dir (which defaults to the current directory)

=item -s SOCKET

=item --socket SOCKET

Use SOCKET instead of the default "./desd.control".  Note that relative paths
are relative to base-dir (which defaults to the current directory)

=item -v

=item --verbose

Increase logging output. (is relative to DEBUG env var)

=item -q

=item --quiet

Decrease logging output. (is relative to DEBUG env var)

=back

=cut

my $opt_verbose= $ENV{DEBUG} || 0;
my $opt_version;
my $opt_control_socket;
my %opt;

Getopt::Long::Configure(qw: no_ignore_case bundling permute :);
GetOptions(
	'help|h|?'           => sub { pod2usage(1) },
	'verbose|v'          => sub { $opt_verbose++ },
	'quiet|q'            => sub { $opt_verbose-- },
	'version'            => \$opt_version,
	'base-dir|d=s'       => \$opt{base_dir},
	'config|c=s'         => \$opt{config_path},
	'socket|s=s'         => \$opt{control_path},
	'desd-path=s'        => \$opt{desd_path},
	'daemonproxy-path=s' => \$opt{daemonproxy_path},
	'control=s'          => \$opt_control_socket,
) or pod2usage(2);

require Log::Any::Adapter;
Log::Any::Adapter->set( 'Daemontools', filter => "debug-$opt_verbose" );

require App::Desd;
if ($opt_version) {
	printf("desd version %s\n", App::Desd->VERSION);
	exit 1;
}

# strip null keys
defined $opt{$_} or delete $opt{$_}
	for keys %opt;

my $desd= App::Desd->new(\%opt);

if (defined $opt_control_socket) {
	$desd->run_controller($opt_control_socket);
} else {
	$desd->exec_daemonproxy;
}

__END__

=head1 SIGNALS

Desd handles signals sent to daemonproxy with these default actions (which
can be overridden in the config file):

=over

=item SIGHUP

Reload config.  Desd first performs a "chdir" to the base directory (useful in
case of mount point changes).  It then re-reads the config file, and builds a
hierarchial diff of the old settings and new settings.  It then applies the
diff to its current running state.  It then re-creates its control socket.

=item SIGINT

Like SIGHUP, but without reloading the config file.

=item SIGTERM

Cause desd to perform a clean orderly shutdown, sending all supervised
processes a SIGTERM and waiting for them to exit for a timeout before sending
SIGQUIT or finally SIGKILL.  It then also exits.

=item SIGQUIT

Like SIGTERM, but doesn't wait for supervised processes to exit.

=item SIGUSR1

Run-time equivalent of option --verbose.

=item SIGUSR2

Run-time equivalent of option --quiet.

=back

=item ENVIRONMENT

desd is affected by the following environment variables:

=over

=item DESD_IS_CONTROLLER

When false, desd behaves like a top level script, and execs daemonproxy.
When true, desd behaves as a daemonproxy contoller script.

=item DEBUG

Initial log level.  If 0 or unset, log level is 'info'.  If 1, log level is
'debug'.  If 2, log level is 'trace'.

Basically, positive numbers are like "-v" and negative numbers are like "-q".

=item PERL5LIB ...

This is a perl script, and affected by all the environment variables that
affect perl.

=back

=cut