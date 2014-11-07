#! /usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;

my $opt_verbose= $ENV{DEBUG} || 0;
my $opt_base_dir;

Getopt::Long::Configure(qw: no_ignore_case bundling permute :);
GetOptions(
	'help|h|?'       => sub { pod2usage(1) },
	'verbose|v'      => sub { $opt_verbose++ },
	'quiet|q'        => sub { $opt_verbose-- },
	'base-dir|d=s'   => \$opt_base_dir,
) or pod2usage(2);

require Log::Any::Adapter;
Log::Any::Adapter->set( 'Daemontools', filter => "debug-$opt_verbose" );

require App::Desd;
exit App::Desd->new(\@ARGV)->run;

__END__

=head1 SYNOPSIS

  desd DIRECTORY # config file is DIRECTORY/config.yaml, socket is DIRECTORY/control.sock

=head1 OPTIONS

=over

=item -d PATH

=item --base-dir PATH

Change to PATH before starting.  If PATH contains symlinks or
relative paths they will be preserved, so that when SIGHUP is received it
will re-evaluate the symbolic path.

=item -c CONFIGFILE

=item --config CONFIGFILE

Use CONFIGFILE instead of the default "./desd.conf".  Note that relative paths
are relative to base-dir (which defaults to the current directory)

=item -s SOCKET

=item --socket SOCKET

Use SOCKET instead of the default "./control.sock".  Note that relative paths
are relative to base-dir (which defaults to the current directory)

=item -v

=item --verbose

Increase logging output. (is relative to DEBUG env var)

=item -q

=item --quiet

Decrease logging output. (is relative to DEBUG env var)

=back

=head1 SIGNALS

Desd has several default signal handlers.  These behaviors can be overridden
with the config file, but the defaults are:

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

=item DEBUG

Initial log level.  If 0 or unset, log level is 'info'.  If 1, log level is
'debug'.  If 2, log level is 'trace'.

Basically, positive numbers are like "-v" and negative numbers are like "-q".

=item PERL5LIB ...

This is a perl script, and affected by all the environment variables that
affect perl.

=back

=cut