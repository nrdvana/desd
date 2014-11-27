#! /usr/bin/env perl

=head1 NAME

descall-kill

=head1 SYNOPSIS

  descall-kill [OPTIONS] DIRECTIVE ...

=head1 SERVICE EXAMPLE

  action stop:
    run: descall-kill SIGTERM SIGCONT 30 SIGTERM 20 SIGQUIT 5 SIGKILL

This will send SIGTERM, SIGCONT, wait up to 30 seconds for the process to exit,
then if not it will send SIGTERM again and wait up to 20 seconds, then send
SIGQUIT and wait up to 5 seconds before sending SIGKILL.

=head1 DESCRIPTION

Provides script access to the internal "killscript" function of desd.

desd has an internal scripting function for killing services, based on
alternating between 'kill' and 'wait'.  It is a two-fold improvement over
calling "kill"/"sleep" directly from your script:

=over

=item *

By using a unix "wait()", the delay ends as soon as the process is reaped and
there is no unnecessary idle time.

=item *

When desd perform the kill() there is no race condition, where the process
could be reaped and a new one spawned with that PID right before the kill is
delivered.  (while unlikely, it is entirely possible to happen on a highly
loaded server)

=back

This script communicates with desd over a socket.  This script automatically
has socket access to desd if you are running from a service's action with the
default file descriptors and environment variables.  If not, you additionally
need to specify C<--service> and/or C<--basedir> and/or C<--socket> options.

=head1 OPTIONS

No options are needed for the default desd actions (other than "start") where
the socket exists on file descriptor 3 and the environment variables
DESD_SV_NAME and DESD_COMM_FD are set.

=over

=item --basedir

Tells this script the root of the desd instance.  Defaults to C<$DESD_BASEDIR>

=item --socket

Path to socket or integer file handle of existing socket.  Defaults to
DESD_COMM_FD if set, or C<basedir/desd.sock> if C<$DESD_BASEDIR> is set or
C<--basedir> was given.

=item --service

The name of the service that should be killed.  Defaults to C<$DESD_SV_NAME>

=back

=head1 EXIT CODES

=over

=item 0

The target service was not running or was reaped during the killscript.

=item 1

Invalid options or arguments or environment

=item 2

The target service did not terminate.

=back

=cut

use strict;
use warnings;
use Pod::Usage;
use Getopt::Long;
use IO::Handle;

my $opt_basedir= $ENV{DESD_BASEDIR} // '';
my $opt_sv_name= $ENV{DESD_SV_NAME} // '';
my $opt_socket=  $ENV{DESD_COMM_FD} // '';

GetOptions(
	'help|h|?'  => sub { pod2usage(1) },
	'basedir=s' => \$opt_basedir,
	'service=s' => \$opt_sv_name,
	'socket=s'  => \$opt_socket,
) or pod2usage(2);

length $opt_sv_name
	or die "Which service? (missing \$DESD_SV_NAME or --service option)\n";
$opt_sv_name =~ /^[0-9a-zA-Z_.-]+$/
	or die "Invalid service name '$opt_sv_name'\n";

length $opt_socket
	or length $opt_basedir
	or die "No socket available (missing \$DESD_COMM_FD or --socket or --basedir)\n";

# Check the killscript for sanity
@ARGV && !grep { /[^\w.]/ } @ARGV
	or die "Invalid killscript: ".join(' ', @ARGV)."\n";

# If socket is a number, use that file descriptor
my $sock;
if ($opt_socket =~ /^[0-9]+$/) {
	$sock= IO::Handle->new_from_fd($opt_socket, "r+")
		or die "fdopen($opt_socket) failed: $!\n";
	$sock->autoflush(1);
}
# else try connecting to the socket.
else {
	my $path= !length $opt_socket? "$opt_basedir/desd.sock"
		: length $opt_basedir && !-S $opt_socket? "$opt_basedir/$opt_socket"
		: $opt_socket;
	-S $path
		or die "No such socket '$path'\n";
	require Socket;
	socket($sock, Socket::PF_UNIX(), Socket::SOCK_STREAM(), 0)
		or die "socket: $!\n";
	my $addr= Socket::pack_sockaddr_un($path);
	connect($sock, $addr)
		or die "Unable to connect to desd: $!\n";
}

# Call the killscript function
print $sock join("\t", 'killscript', $opt_sv_name, @ARGV)."\n";

# Read the result
my $response= <$sock>;
defined $response
	or die "lost connection to desd: $!\n";

# First field tells the outcome of the killscript
# More fields may be added later.
my ($result)= split /[\t\n]/, $response;

if ($result eq 'reaped') {
	exit(0);
} elsif ($result eq 'not_running') {
	exit(0);
} elsif ($result eq 'invalid') {
	die "Invalid killscript: ".join(' ', @ARGV)."\n";
} elsif ($result eq 'still_running') {
	exit(2);
} else {
	die "Unknown response from desd: '$result'\n";
}
